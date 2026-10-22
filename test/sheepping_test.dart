import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheepping/src/export.dart';
import 'package:sheepping/src/models.dart';
import 'package:sheepping/src/icmp.dart';
import 'package:sheepping/src/icmp_types.dart';
import 'package:sheepping/src/ping_engine.dart';
import 'package:sheepping/src/view_model.dart';

void main() {
  group('ICMP results', () {
    final v4 = PingTarget(InternetAddress('142.250.66.110'));
    final v6 = PingTarget(InternetAddress('::1'));

    test('an IPv4 reply reads like ping.exe', () {
      final r = resultFromOutcome(
        const IcmpOutcome(
          status: 0,
          from: '142.250.66.110',
          rttMs: 14,
          ttl: 118,
        ),
        v4,
      );
      expect(r.isSuccess, isTrue);
      expect(r.latency, 14);
      expect(r.resolvedIP, '142.250.66.110');
      expect(
        r.message,
        'Reply from 142.250.66.110: bytes=32 time=14ms TTL=118',
      );
    });

    test('a sub-millisecond IPv6 reply', () {
      final r = resultFromOutcome(
        const IcmpOutcome(status: 0, from: '::1', rttMs: 0),
        v6,
      );
      expect(r.isSuccess, isTrue);
      expect(r.latency, 0.1);
      expect(r.message, 'Reply from ::1: time<1ms');
    });

    test('a timeout keeps the target IP and names no responder', () {
      final r = resultFromOutcome(const IcmpOutcome(status: ipReqTimedOut), v4);
      expect(r.isSuccess, isFalse);
      expect(r.resolvedIP, '142.250.66.110');
      expect(r.message, 'Request timed out.');
    });

    test('a router reporting an error is named', () {
      final r = resultFromOutcome(
        const IcmpOutcome(status: 11003, from: '192.168.1.1'),
        v4,
      );
      expect(r.isSuccess, isFalse);
      expect(
        r.message,
        'Reply from 192.168.1.1: Destination host unreachable.',
      );
    });

    test('an unknown status is still English', () {
      expect(describeIcmpStatus(11999), 'Ping failed (IP status 11999).');
    });

    test('an unresolvable name', () {
      final r = unresolvedResult('nope.invalid');
      expect(r.isSuccess, isFalse);
      expect(r.message, contains('could not find host nope.invalid'));
    });
  });

  group('resolveTarget', () {
    test('takes IP literals without DNS, keeping the IPv6 zone', () async {
      expect((await resolveTarget('10.0.0.1'))!.ip.address, '10.0.0.1');
      final scoped = await resolveTarget('fe80::1%12');
      expect(scoped!.ip.type, InternetAddressType.IPv6);
      expect(scoped.scopeId, 12);
    });

    test('returns null for a name that cannot resolve', () async {
      expect(await resolveTarget('nope.invalid'), isNull);
    });
  });

  group('live ICMP (Windows)', () {
    test('loopback answers over IPv4', () async {
      final o = await icmpEcho(
        InternetAddress('127.0.0.1'),
        timeout: const Duration(seconds: 2),
      );
      expect(o.status, ipSuccess);
      expect(o.from, '127.0.0.1');
      expect(o.ttl, greaterThan(0));
    }, skip: !Platform.isWindows);

    test('loopback answers over IPv6', () async {
      final o = await icmpEcho(
        InternetAddress('::1'),
        timeout: const Duration(seconds: 2),
      );
      expect(o.status, ipSuccess);
      expect(o.from, '::1');
      expect(o.rttMs, lessThan(1000));
    }, skip: !Platform.isWindows);

    test('an unanswered address times out on schedule', () async {
      final watch = Stopwatch()..start();
      // TEST-NET-1: reserved, never routed to a live host.
      final o = await icmpEcho(
        InternetAddress('192.0.2.1'),
        timeout: const Duration(milliseconds: 800),
      );
      expect(o.status, isNot(ipSuccess));
      expect(watch.elapsedMilliseconds, lessThan(4000));
    }, skip: !Platform.isWindows);

    test('many requests in flight complete independently', () async {
      final all = await Future.wait(<Future<IcmpOutcome>>[
        for (var i = 0; i < 20; i++)
          icmpEcho(
            InternetAddress('127.0.0.1'),
            timeout: const Duration(seconds: 2),
          ),
      ]);
      expect(all.every((o) => o.status == ipSuccess), isTrue);
    }, skip: !Platform.isWindows);
  });

  group('host validation', () {
    test('rejects ping.exe options in either syntax', () {
      expect(PingViewModel.isValidAddress('/t'), isFalse);
      expect(PingViewModel.isValidAddress('-t'), isFalse);
      expect(PingViewModel.isValidAddress('8.8.8.8 -t'), isFalse);
      expect(PingViewModel.isValidAddress('a&calc'), isFalse);
      // English only: internationalized names go in their xn-- form.
      expect(PingViewModel.isValidAddress('ไทย.th'), isFalse);
      expect(PingViewModel.isValidAddress('xn--o3cw4h.th'), isTrue);
    });

    test('accepts hostnames and addresses', () {
      expect(PingViewModel.isValidAddress('google.com'), isTrue);
      expect(PingViewModel.isValidAddress('192.168.1.1'), isTrue);
      expect(PingViewModel.isValidAddress('2606:4700:4700::1111'), isTrue);
      expect(PingViewModel.isValidAddress('fe80::1%12'), isTrue);
      expect(PingViewModel.isValidAddress('my-host_01.local'), isTrue);
    });
  });

  test('an overtaken result is counted but does not roll the status back', () {
    final host = PingHost('h');
    host.applyResult(
      isSuccess: true,
      resolvedIP: '1.1.1.1',
      latency: 5,
      message: 'ok',
    );
    host.applyResult(
      isSuccess: false,
      resolvedIP: '',
      latency: null,
      message: 'Request timed out.',
      updateLiveState: false,
    );
    expect(host.status, PingStatus.success);
    expect(host.latency, 5);
    expect(host.successCount, 1);
    expect(host.failCount, 1);
    expect(host.log, hasLength(2));
  });

  group('CSV export', () {
    test('pingCsv quotes every field and keeps the macOS header', () {
      final host = PingHost('8.8.8.8')
        ..resolvedIP = '8.8.8.8'
        ..status = PingStatus.success
        ..latency = 14.25
        ..successCount = 3
        ..isActive = true;

      final csv = pingCsv(<PingHost>[host]);
      final lines = csv.split('\n');
      expect(
        lines.first,
        'Host,Resolved IP,Status,Latency (ms),Success,Failed,Rate (%),Active',
      );
      expect(lines[1], '"8.8.8.8","8.8.8.8","OK","14.3","3","0","100","Yes"');
    });

    test('logCsv escapes embedded quotes', () {
      final host = PingHost('h')
        ..addLog(isSuccess: false, message: 'said "nope"');
      final lines = logCsv(host).split('\n');
      expect(lines.first, 'Timestamp,Status,Latency (ms),Message');
      expect(lines[1], endsWith('"said ""nope"""'));
    });
  });

  test('saved CSV files pin the separator for Excel, without a BOM', () {
    final file = csvFileContents('Host,Status\n"8.8.8.8","OK"');
    expect(file, startsWith('sep=,\nHost,Status'));
    expect(file.codeUnitAt(0), isNot(0xFEFF));
    // The clipboard copy stays plain CSV: the header comes first.
    expect(pingCsv(<PingHost>[]), startsWith('Host,'));
  });

  test('save failures are explained in English, not OS text', () {
    expect(SaveFailure.reasonFor(5), startsWith('Access is denied.'));
    expect(SaveFailure.reasonFor(32), contains('open in another program'));
    expect(SaveFailure.reasonFor(1234), contains('Windows error 1234'));
  });

  test('safeFileName strips characters Windows rejects', () {
    expect(safeFileName('fe80::1%eth0'), isNot(contains(':')));
    expect(safeFileName('a/b\\c'), 'a-b-c');
  });
}
