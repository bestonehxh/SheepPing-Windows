/// CSV builders, ported verbatim from `PingInfoView.swift`.
///
/// Column order, header spelling and quoting all follow the macOS build so a
/// file exported on Windows opens identically to one exported on macOS.
library;

import 'models.dart';

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String _latency(double? ms) => ms == null ? '' : ms.toStringAsFixed(1);

/// One row per host: the `⌘C` / "Copy Ping Row" payload.
String pingCsv(List<PingHost> hosts) {
  final lines = <String>[
    'Host,Resolved IP,Status,Latency (ms),Success,Failed,Rate (%),Active',
  ];
  for (final host in hosts) {
    final total = host.successCount + host.failCount;
    lines.add(
      <String>[
        _csv(host.address),
        _csv(host.resolvedIP),
        _csv(host.status.label),
        _csv(_latency(host.latency)),
        _csv('${host.successCount}'),
        _csv('${host.failCount}'),
        _csv(total == 0 ? '' : host.successRate.toStringAsFixed(0)),
        _csv(host.isActive ? 'Yes' : 'No'),
      ].join(','),
    );
  }
  return lines.join('\n');
}

/// One host's packet log, oldest first.
String logCsv(PingHost host) {
  final lines = <String>['Timestamp,Status,Latency (ms),Message'];
  for (final e in host.log.reversed) {
    lines.add(
      '${_stamp(e.timestamp)},${e.isSuccess ? 'OK' : 'Fail'},'
      '${_latency(e.latency)},"${e.message.replaceAll('"', '""')}"',
    );
  }
  return lines.join('\n');
}

/// Several hosts' logs in one file, grouped by host.
String combinedLogCsv(List<PingHost> hosts) {
  final lines = <String>['Host,Timestamp,Status,Latency (ms),Message'];
  for (final h in hosts) {
    for (final e in h.log.reversed) {
      lines.add(
        '${h.address},${_stamp(e.timestamp)},'
        '${e.isSuccess ? 'OK' : 'Fail'},${_latency(e.latency)},'
        '"${e.message.replaceAll('"', '""')}"',
      );
    }
  }
  return lines.join('\n');
}

/// Turns a host address into something safe for a file name, matching
/// `address.replacingOccurrences(of: "/", with: "-")`.
String safeFileName(String address) {
  final cleaned = address.replaceAll('/', '-').replaceAll('\\', '-');
  return cleaned.replaceAll(RegExp(r'[:*?"<>|]'), '-');
}
