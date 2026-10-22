/// Domain model, mirroring `PingCore.swift` from the macOS original.
///
/// [PingHost] is a [ChangeNotifier] so a single row can rebuild on its own
/// without walking the whole table (the SwiftUI version relies on
/// `@ObservedObject` for exactly the same reason).
library;

import 'package:flutter/foundation.dart';

/// One packet's verdict, identical in shape to Swift's `PingStatus`.
enum PingStatus { idle, running, success, failed }

extension PingStatusLabel on PingStatus {
  String get label => switch (this) {
    PingStatus.idle => 'Idle',
    PingStatus.running => '...',
    PingStatus.success => 'OK',
    PingStatus.failed => 'Fail',
  };
}

/// A single logged packet.
@immutable
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.isSuccess,
    required this.latency,
    required this.message,
  });

  final DateTime timestamp;
  final bool isSuccess;
  final double? latency;
  final String message;
}

int _nextHostId = 0;

/// One monitored address. Field-for-field equivalent of Swift's `PingHost`.
class PingHost extends ChangeNotifier {
  PingHost(this.address) : id = 'h${_nextHostId++}';

  final String id;
  final String address;

  String resolvedIP = '';
  PingStatus status = PingStatus.idle;
  double? latency;
  int successCount = 0;
  int failCount = 0;
  final List<LogEntry> log = <LogEntry>[];
  bool isActive = false;

  /// Bumped by [resetStats]; in-flight results captured against an older
  /// generation are dropped, exactly like the Swift implementation.
  int generation = 0;

  double get successRate {
    final total = successCount + failCount;
    if (total == 0) return 0;
    return successCount / total * 100;
  }

  /// The em dash the macOS table prints for "no value yet".
  String get resolvedText => resolvedIP.isEmpty ? '\u2014' : resolvedIP;

  String get latencyText {
    final ms = latency;
    if (ms == null) return '\u2014';
    return ms < 1000
        ? '${ms.toStringAsFixed(1)} ms'
        : '${ms.toStringAsFixed(0)} ms';
  }

  String get rateText {
    if (successCount + failCount == 0) return '\u2014';
    return '${successRate.toStringAsFixed(0)}%';
  }

  void addLog({
    required bool isSuccess,
    double? latency,
    required String message,
  }) {
    log.insert(
      0,
      LogEntry(
        timestamp: DateTime.now(),
        isSuccess: isSuccess,
        latency: latency,
        message: message,
      ),
    );
    if (log.length > 500) log.removeLast();
    notifyListeners();
  }

  /// Lets the session tell observers that `isActive`/`status` changed without
  /// exposing `notifyListeners` (which is protected) to other classes.
  void touch() => notifyListeners();

  /// Empties the packet log only; counters and status stay untouched.
  void clearLog() {
    if (log.isEmpty) return;
    log.clear();
    notifyListeners();
  }

  void resetStats() {
    generation += 1;
    successCount = 0;
    failCount = 0;
    latency = null;
    resolvedIP = '';
    log.clear();
    status = PingStatus.idle;
    isActive = false;
    notifyListeners();
  }

  /// Applies one packet result. Callers have already checked epoch/generation.
  ///
  /// [updateLiveState] is false for a result that was overtaken by a newer
  /// one: it is still counted and logged, but must not roll the row's status
  /// and latency back to an older packet.
  void applyResult({
    required bool isSuccess,
    required String resolvedIP,
    required double? latency,
    required String message,
    bool updateLiveState = true,
  }) {
    if (isSuccess) {
      successCount += 1;
    } else {
      failCount += 1;
    }
    if (updateLiveState) {
      if (resolvedIP.isNotEmpty && (isSuccess || this.resolvedIP.isEmpty)) {
        this.resolvedIP = resolvedIP;
      }
      this.latency = isSuccess ? latency : null;
      status = isSuccess ? PingStatus.success : PingStatus.failed;
    } else if (this.resolvedIP.isEmpty && resolvedIP.isNotEmpty) {
      this.resolvedIP = resolvedIP;
    }
    addLog(isSuccess: isSuccess, latency: latency, message: message);
  }
}
