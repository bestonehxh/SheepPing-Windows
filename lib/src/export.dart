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

/// A CSV that could not be written, explained in the app's own (English)
/// words: the OS error text is in the Windows display language.
class SaveFailure implements Exception {
  const SaveFailure(this.fileName, this.reason);

  final String fileName;
  final String reason;

  /// Plain-English reason for a Win32 error code from a failed write.
  static String reasonFor(int? code) => switch (code) {
    2 || 3 => 'The folder no longer exists.',
    5 => 'Access is denied. Choose a folder you can write to.',
    19 => 'The disk is write-protected.',
    32 || 33 => 'The file is open in another program. Close it and try again.',
    39 || 112 => 'There is not enough space on the disk.',
    null => 'The file could not be written.',
    _ => 'The file could not be written (Windows error $code).',
  };

  @override
  String toString() => "Couldn't save $fileName. $reason";
}

/// What a saved CSV file holds: [csv] behind a `sep=,` line.
///
/// Excel splits a CSV on the *regional* list separator, which is ";" wherever
/// "," is the decimal mark (most of Europe) — there every row landed in one
/// column. The `sep=` line pins the separator to "," on any region. It is for
/// files only: pasted into a sheet from the clipboard it would be a data row.
///
/// No UTF-8 BOM: with one in front, Excel shows the `sep=` line as text
/// instead of obeying it — and every value the app writes is ASCII anyway.
String csvFileContents(String csv) => 'sep=,\n$csv';

/// Turns a host address into something safe for a file name, matching
/// `address.replacingOccurrences(of: "/", with: "-")`.
String safeFileName(String address) {
  final cleaned = address.replaceAll('/', '-').replaceAll('\\', '-');
  return cleaned.replaceAll(RegExp(r'[:*?"<>|]'), '-');
}
