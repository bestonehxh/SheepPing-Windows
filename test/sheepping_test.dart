import 'package:flutter_test/flutter_test.dart';
import 'package:sheepping/src/export.dart';
import 'package:sheepping/src/models.dart';
import 'package:sheepping/src/ping_engine.dart';

void main() {
  group('parsePingOutput', () {
    test('reads an IPv4 reply', () {
      const out = '\r\nPinging 8.8.8.8 with 32 bytes of data:\r\n'
          'Reply from 8.8.8.8: bytes=32 time=14ms TTL=118\r\n';
      final result = parsePingOutput(out, '8.8.8.8');
      expect(result.isSuccess, isTrue);
      expect(result.latency, 14);
      expect(result.resolvedIP, '8.8.8.8');
    });

    test('maps time<1ms to 0.1 ms', () {
      const out = 'Reply from 192.168.1.1: bytes=32 time<1ms TTL=64';
      expect(parsePingOutput(out, '192.168.1.1').latency, 0.1);
    });

    test('reads an IPv6 reply that has no bytes= field', () {
      const out = 'Reply from ::1: time<1ms ';
      final result = parsePingOutput(out, '::1');
      expect(result.isSuccess, isTrue);
      expect(result.resolvedIP, '::1');
    });

    test('reads a timeout', () {
      const out = 'Request timed out.';
      final result = parsePingOutput(out, '10.0.0.1');
      expect(result.isSuccess, isFalse);
    });

    test('reads an unresolvable host', () {
      const out = 'Ping request could not find host nope.invalid. '
          'Please check the name and try again.';
      final result = parsePingOutput(out, 'nope.invalid');
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('could not find'));
    });
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
      expect(lines.first,
          'Host,Resolved IP,Status,Latency (ms),Success,Failed,Rate (%),Active');
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

  test('safeFileName strips characters Windows rejects', () {
    expect(safeFileName('fe80::1%eth0'), isNot(contains(':')));
    expect(safeFileName('a/b\\c'), 'a-b-c');
  });
}
