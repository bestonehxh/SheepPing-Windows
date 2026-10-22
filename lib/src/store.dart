/// Persistence for hosts, interval, timeout and theme.
///
/// The macOS build uses `UserDefaults`; the closest Windows equivalent that
/// keeps the same data in one readable place is a JSON file under
/// `%APPDATA%\SheepPing\`.
library;

import 'dart:convert';
import 'dart:io';



class Settings {
  Settings({
    List<String>? hosts,
    this.interval = 1.0,
    this.timeout = 3.0,
  }) : hosts = hosts ?? <String>[];

  final List<String> hosts;
  final double interval;
  final double timeout;
}

class SettingsStore {
  static Directory get _dir {
    final appData = Platform.environment['APPDATA'];
    final base = (appData == null || appData.isEmpty)
        ? Directory.current.path
        : appData;
    return Directory('$base${Platform.pathSeparator}SheepPing');
  }

  static File get file =>
      File('${_dir.path}${Platform.pathSeparator}settings.json');

  static Settings load() {
    try {
      final f = file;
      if (!f.existsSync()) return Settings();
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return Settings();
      final hosts = <String>[];
      final list = raw['hosts'];
      if (list is List) {
        for (final h in list) {
          if (h is String && h.trim().isNotEmpty) hosts.add(h);
        }
      }
      final interval = (raw['interval'] as num?)?.toDouble() ?? 1.0;
      final timeout = (raw['timeout'] as num?)?.toDouble() ?? 3.0;
      return Settings(
        hosts: hosts,
        interval: interval > 0 ? interval : 1.0,
        timeout: timeout > 0 ? timeout : 3.0,
      );
    } catch (_) {
      // A corrupt or unreadable file must never stop the app from starting.
      return Settings();
    }
  }

  static void save(Settings settings) {
    try {
      final dir = _dir;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final payload = <String, Object?>{
        'hosts': settings.hosts,
        'interval': settings.interval,
        'timeout': settings.timeout,
      };
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    } catch (_) {
      // Best effort: a failed write must not surface as a crash.
    }
  }
}
