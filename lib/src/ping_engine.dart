/// The Windows ping engine.
///
/// The macOS original keeps one long-lived `/sbin/ping -i <interval>` process
/// per host and parses its stream. Windows `ping.exe` has no `-i`, and `-t`
/// sends without any pacing, so the port instead fires a single
/// `ping -n 1 -w <timeout>` per tick on a fixed-interval timer and never awaits
/// it. Pacing is therefore independent of the reply deadline — the same
/// guarantee the macOS version gets from `-i` plus `-W`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// One packet's parsed outcome.
class PingResult {
  const PingResult({
    required this.isSuccess,
    required this.resolvedIP,
    required this.latency,
    required this.message,
  });

  final bool isSuccess;
  final String resolvedIP;
  final double? latency;
  final String message;
}

/// Runs one `ping -n 1` and turns its output into a [PingResult].
Future<PingResult> pingOnce(String address, double timeout) async {
  final args = <String>[];
  // Windows ping needs -6 for an IPv6 literal; -4 is the default.
  if (address.contains(':')) args.add('-6');
  args.addAll(<String>[
    '-n', '1',
    '-w', (timeout * 1000).round().toString(),
    address,
  ]);

  final ProcessResult res = await Process.run(
    'ping',
    args,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  final buffer = StringBuffer();
  buffer.write(res.stdout is String ? res.stdout as String : '');
  buffer.write(res.stderr is String ? res.stderr as String : '');
  return parsePingOutput(buffer.toString(), address);
}

final RegExp _bracketIP = RegExp(r'\[([^\]]+)\]');

/// Parser for the Windows `ping` wording. Kept free of I/O so it can be unit
/// tested against captured output.
PingResult parsePingOutput(String output, String address) {
  String? bannerIP;
  String? replyIP;
  double? replyLatency;
  String? replyMessage;
  bool replyReached = false;
  String? failureMessage;

  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // "Pinging google.com [142.250.66.110] with 32 bytes of data:"
    // "Pinging 127.0.0.1 with 32 bytes of data:"
    if (line.startsWith('Pinging ')) {
      final m = _bracketIP.firstMatch(line);
      if (m != null) {
        bannerIP = m.group(1);
      } else {
        final m2 = RegExp(r'^Pinging\s+(\S+)\s').firstMatch(line);
        if (m2 != null) bannerIP = m2.group(1);
      }
      continue;
    }

    // "Ping request could not find host nope.invalid. Please check the name..."
    if (line.toLowerCase().contains('could not find host')) {
      failureMessage = line;
      continue;
    }
    if (line.toLowerCase().contains('transmit failed')) {
      failureMessage = line;
      continue;
    }

    // Summary / statistics lines belong to the run, not to a packet.
    if (line.startsWith('Ping statistics') ||
        line.startsWith('Packets:') ||
        line.contains('round trip times') ||
        line.startsWith('Minimum =') ||
        line.startsWith('Approximate')) {
      continue;
    }

    if (line == 'Request timed out.' || line.startsWith('Request timed out')) {
      failureMessage ??= line;
      continue;
    }

    // "Reply from 127.0.0.1: bytes=32 time<1ms TTL=128"
    // "Reply from ::1: time<1ms"
    // "Reply from 203.0.113.1: Destination host unreachable."
    if (line.startsWith('Reply from ')) {
      final rest = line.substring('Reply from '.length);
      // The address ends at the first ": " — safe for IPv6 too, because the
      // colons inside an address are never followed by a space.
      final cut = rest.indexOf(': ');
      final ip = (cut >= 0 ? rest.substring(0, cut) : rest).trim();

      final timeMatch = RegExp(r'time[=<]\s*([\d.]+)\s*ms').firstMatch(line);
      if (timeMatch != null) {
        replyReached = true;
        replyIP = ip;
        replyMessage = line;
        if (line.contains('time<')) {
          // Windows cannot resolve sub-millisecond RTTs; the macOS build shows
          // a real fraction here, so keep it a small non-zero number.
          replyLatency = 0.1;
        } else {
          replyLatency = double.tryParse(timeMatch.group(1)!);
        }
      } else {
        // A reply line without a time is an ICMP error carrying the message.
        failureMessage ??= line;
      }
      continue;
    }
  }

  if (replyReached) {
    return PingResult(
      isSuccess: true,
      resolvedIP: replyIP ?? bannerIP ?? '',
      latency: replyLatency,
      message: replyMessage ?? 'Reply from ${replyIP ?? address}',
    );
  }

  return PingResult(
    isSuccess: false,
    resolvedIP: bannerIP ?? '',
    latency: null,
    message: failureMessage ?? 'Request timed out.',
  );
}

/// Owns the interval timer for one host. Fire-and-forget, guarded by an epoch
/// (so [stop] is final) and the host's generation (so a stats reset discards
/// packets that were already in flight).
class PingSession {
  PingSession({required this.host, required this.interval, required this.timeout});

  final PingHost host;
  final double interval;
  final double timeout;

  Timer? _timer;
  int _epoch = 0;
  bool _running = false;

  bool get isRunning => _running;

  void start() {
    stop(notify: false);
    final myEpoch = ++_epoch;
    _running = true;

    host.isActive = true;
    host.status = PingStatus.running;
    host.touch();

    final period = Duration(milliseconds: (interval * 1000).round().clamp(50, 600000));
    _timer = Timer.periodic(period, (_) => _fire(myEpoch));
    _fire(myEpoch);
  }

  void _fire(int myEpoch) {
    if (!_running || myEpoch != _epoch) return;
    final gen = host.generation;
    final address = host.address;

    pingOnce(address, timeout).then((result) {
      if (!_running || myEpoch != _epoch || host.generation != gen) return;
      host.applyResult(
        isSuccess: result.isSuccess,
        resolvedIP: result.resolvedIP,
        latency: result.latency,
        message: result.message,
      );
    }).catchError((Object error) {
      if (!_running || myEpoch != _epoch || host.generation != gen) return;
      host.applyResult(
        isSuccess: false,
        resolvedIP: '',
        latency: null,
        message: 'Launch error: $error',
      );
    });
  }

  /// Ends the session. `notify: false` is used when immediately superseded.
  void stop({bool notify = true}) {
    _epoch += 1;
    _running = false;
    _timer?.cancel();
    _timer = null;
    host.isActive = false;
    host.status = PingStatus.idle;
    if (notify) host.touch();
  }
}
