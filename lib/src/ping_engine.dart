/// The Windows ping engine.
///
/// The macOS original keeps one long-lived `/sbin/ping -i <interval>` process
/// per host and parses its stream. Here each tick sends one echo request
/// through the Windows ICMP API ([icmpEcho]) on a fixed-interval timer and
/// never awaits it, so pacing stays independent of the reply deadline — the
/// guarantee macOS gets from `-i` plus `-W`.
///
/// Every message the log shows is written here, in English, in ping.exe's own
/// wording ("Reply from 8.8.8.8: bytes=32 time=14ms TTL=118"), so the app
/// reads the same on any Windows display language.
library;

import 'dart:async';
import 'dart:io';

import 'icmp_stub.dart' if (dart.library.ffi) 'icmp.dart';
import 'icmp_types.dart';
import 'models.dart';

/// One packet's outcome, as the table and log consume it.
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

/// A resolved destination.
class PingTarget {
  const PingTarget(this.ip, {this.scopeId = 0});

  final InternetAddress ip;

  /// IPv6 zone index from an address like "fe80::1%12".
  final int scopeId;
}

/// Resolves [address] to the IP that gets pinged, or `null` when it cannot.
///
/// IP literals skip DNS. Names prefer IPv4 — what macOS `/sbin/ping` (IPv4
/// only) does for the original — and fall back to IPv6.
Future<PingTarget?> resolveTarget(String address) async {
  final int zone = address.indexOf('%');
  final String bare = zone < 0 ? address : address.substring(0, zone);
  final literal = InternetAddress.tryParse(bare);
  if (literal != null) {
    final scope = zone < 0 ? 0 : int.tryParse(address.substring(zone + 1)) ?? 0;
    return PingTarget(literal, scopeId: scope);
  }
  try {
    final found = await InternetAddress.lookup(
      address,
    ).timeout(const Duration(seconds: 5));
    for (final ip in found) {
      if (ip.type == InternetAddressType.IPv4) return PingTarget(ip);
    }
    return found.isEmpty ? null : PingTarget(found.first);
  } on Object {
    // SocketException text comes from the OS in its display language; the
    // caller reports the failure in its own (English) words instead.
    return null;
  }
}

/// ping.exe's message for an `IP_STATUS` failure code.
String describeIcmpStatus(int status) => switch (status) {
  11002 => 'Destination net unreachable.',
  11003 => 'Destination host unreachable.',
  11004 => 'Destination protocol unreachable.',
  11005 => 'Destination port unreachable.',
  11006 => 'No resources.',
  11008 => 'Hardware error.',
  11009 => 'Packet needs to be fragmented but DF set.',
  11010 => 'Request timed out.',
  11011 => 'Bad request.',
  11012 => 'Bad route.',
  11013 => 'TTL expired in transit.',
  11014 => 'TTL expired during reassembly.',
  11015 => 'Parameter problem.',
  11016 => 'Source quench received.',
  11018 => 'Bad destination.',
  11050 => 'General failure.',
  _ => 'Ping failed (IP status $status).',
};

/// ping.exe's reply line: "Reply from 8.8.8.8: bytes=32 time=14ms TTL=118",
/// or "Reply from ::1: time<1ms" for IPv6, which reports no TTL.
String replyMessage(String from, {required int rttMs, int? ttl}) {
  final time = rttMs == 0 ? 'time<1ms' : 'time=${rttMs}ms';
  if (ttl == null) return 'Reply from $from: $time';
  return 'Reply from $from: bytes=$echoDataSize $time TTL=$ttl';
}

/// Turns one ICMP outcome into the row/log result for [target].
PingResult resultFromOutcome(IcmpOutcome outcome, PingTarget target) {
  final String ip = target.ip.address;
  if (outcome.status == ipSuccess) {
    final int rtt = outcome.rttMs ?? 0;
    return PingResult(
      isSuccess: true,
      resolvedIP: outcome.from ?? ip,
      // The API counts whole milliseconds; "<1ms" stays a small non-zero
      // number so the column never claims a 0.0 ms round trip.
      latency: rtt == 0 ? 0.1 : rtt.toDouble(),
      message: replyMessage(outcome.from ?? ip, rttMs: rtt, ttl: outcome.ttl),
    );
  }
  final String reason = describeIcmpStatus(outcome.status);
  // A router answering for the target ("Reply from 192.168.1.1: Destination
  // host unreachable.") is named, as ping.exe does; a plain loss is not.
  final bool fromOther =
      outcome.from != null &&
      outcome.status != ipReqTimedOut &&
      outcome.status != ipGeneralFailure;
  return PingResult(
    isSuccess: false,
    resolvedIP: ip,
    latency: null,
    message: fromOther ? 'Reply from ${outcome.from}: $reason' : reason,
  );
}

/// The failure for a name that does not resolve, in ping.exe's wording.
PingResult unresolvedResult(String address) => PingResult(
  isSuccess: false,
  resolvedIP: '',
  latency: null,
  message:
      'Ping request could not find host $address. '
      'Please check the name and try again.',
);

/// Owns the interval timer for one host. Fire-and-forget, guarded by an epoch
/// (so [stop] is final) and the host's generation (so a stats reset discards
/// packets that were already in flight).
class PingSession {
  PingSession({
    required this.host,
    required this.interval,
    required this.timeout,
  });

  final PingHost host;
  final double interval;
  final double timeout;

  Timer? _timer;
  int _epoch = 0;
  bool _running = false;

  /// Ticks overlap whenever the reply timeout exceeds the interval, so results
  /// can land out of order: a timeout from an earlier tick arrives after a
  /// later tick's reply. Every result still counts, but only the newest one
  /// may set the row's live status/latency.
  int _sent = 0;
  int _newestApplied = 0;

  /// DNS answers are reused for a minute rather than looked up every tick;
  /// a failed lookup is not cached, so a name that starts resolving is
  /// picked up on the next tick.
  static const Duration _resolveTtl = Duration(minutes: 1);
  PingTarget? _target;
  DateTime _resolvedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<PingTarget?>? _resolving;

  Future<PingTarget?> _currentTarget() {
    final cached = _target;
    if (cached != null &&
        DateTime.now().difference(_resolvedAt) < _resolveTtl) {
      return Future<PingTarget?>.value(cached);
    }
    return _resolving ??= resolveTarget(host.address).then((target) {
      _resolving = null;
      if (target != null) {
        _target = target;
        _resolvedAt = DateTime.now();
      }
      return target;
    });
  }

  Future<PingResult> _pingOnce() async {
    final target = await _currentTarget();
    if (target == null) return unresolvedResult(host.address);
    final outcome = await icmpEcho(
      target.ip,
      timeout: Duration(milliseconds: (timeout * 1000).round()),
      scopeId: target.scopeId,
    );
    return resultFromOutcome(outcome, target);
  }

  bool get isRunning => _running;

  void start() {
    stop(notify: false);
    final myEpoch = ++_epoch;
    _running = true;

    host.isActive = true;
    host.status = PingStatus.running;
    host.touch();

    final period = Duration(
      milliseconds: (interval * 1000).round().clamp(50, 600000),
    );
    _timer = Timer.periodic(period, (_) => _fire(myEpoch));
    _fire(myEpoch);
  }

  void _fire(int myEpoch) {
    if (!_running || myEpoch != _epoch) return;
    final gen = host.generation;
    final seq = ++_sent;

    void apply(PingResult result) {
      if (!_running || myEpoch != _epoch || host.generation != gen) return;
      final newest = seq > _newestApplied;
      if (newest) _newestApplied = seq;
      host.applyResult(
        isSuccess: result.isSuccess,
        resolvedIP: result.resolvedIP,
        latency: result.latency,
        message: result.message,
        updateLiveState: newest,
      );
    }

    _pingOnce().then(apply).catchError((Object _) {
      apply(
        const PingResult(
          isSuccess: false,
          resolvedIP: '',
          latency: null,
          message: 'General failure.',
        ),
      );
    });
  }

  /// Ends the session. `notify: false` is used when immediately superseded.
  void stop({bool notify = true}) {
    _epoch += 1;
    _target = null;
    _running = false;
    _timer?.cancel();
    _timer = null;
    host.isActive = false;
    host.status = PingStatus.idle;
    if (notify) host.touch();
  }
}
