/// App state. A 1:1 port of Swift's `PingViewModel`, including the session
/// bookkeeping that drives the toolbar's enabled states.
library;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'ping_engine.dart';
import 'store.dart';

class PingViewModel extends ChangeNotifier {
  PingViewModel({bool autoStart = true}) : _autoStart = autoStart {
    final saved = SettingsStore.load();
    _interval = saved.interval;
    _timeout = saved.timeout;
    for (final address in saved.hosts) {
      final host = PingHost(address);
      hosts.add(host);
      if (_autoStart) _startSession(host);
    }
  }

  static const double defaultPingTimeout = 3.0;
  static const double minPingTimeout = 0.5;
  static const double maxPingTimeout = 15.0;
  static const double minInterval = 0.5;
  static const double maxInterval = 30.0;

  final bool _autoStart;

  final List<PingHost> hosts = <PingHost>[];
  final Set<String> selectedIDs = <String>{};

  final Map<String, PingSession> _sessions = <String, PingSession>{};

  double _interval = 1.0;
  double _timeout = defaultPingTimeout;

  /// Shift-click anchor, matching `anchorID` in the SwiftUI view.
  String? anchorID;

  double get interval => _interval;
  double get timeout => _timeout;

  int get sessionCount => _sessions.length;
  bool get anyActive => _sessions.isNotEmpty;
  bool get anyInactive => hosts.isNotEmpty && _sessions.length < hosts.length;

  PingHost? get selectedHost {
    if (selectedIDs.length != 1) return null;
    for (final h in hosts) {
      if (selectedIDs.contains(h.id)) return h;
    }
    return null;
  }

  List<PingHost> get selectedHosts =>
      hosts.where((h) => selectedIDs.contains(h.id)).toList(growable: false);

  // MARK: - Hosts

  /// Returns true when the address was actually added.
  bool addHost(String rawAddress) {
    final address = rawAddress.trim();
    // A leading "-" would be handed to ping.exe as a flag, so reject it.
    if (address.isEmpty || address.startsWith('-')) return false;
    for (final h in hosts) {
      if (h.address.toLowerCase() == address.toLowerCase()) return false;
    }
    final host = PingHost(address);
    hosts.add(host);
    _startSession(host);
    _save();
    notifyListeners();
    return true;
  }

  void removeHost(PingHost host) {
    _sessions.remove(host.id)?.stop();
    selectedIDs.remove(host.id);
    hosts.removeWhere((h) => h.id == host.id);
    _save();
    notifyListeners();
  }

  void removeHosts(Iterable<PingHost> list) {
    for (final host in list.toList(growable: false)) {
      _sessions.remove(host.id)?.stop();
      selectedIDs.remove(host.id);
      hosts.removeWhere((h) => h.id == host.id);
    }
    _save();
    notifyListeners();
  }

  // MARK: - Sessions

  void stopAll() {
    for (final host in hosts) {
      _sessions.remove(host.id)?.stop();
    }
    notifyListeners();
  }

  /// Starts only the hosts that have no session yet, keeping their stats.
  void resumeAll() {
    for (final host in hosts) {
      if (!_sessions.containsKey(host.id)) _startSession(host);
    }
    notifyListeners();
  }

  void restartAll() {
    for (final host in hosts) {
      _sessions.remove(host.id)?.stop();
      host.resetStats();
      _startSession(host);
    }
    notifyListeners();
  }

  void resetStats(PingHost host) {
    _sessions.remove(host.id)?.stop();
    host.resetStats();
    _startSession(host);
    notifyListeners();
  }

  void applyInterval(double value) {
    _interval = value.clamp(minInterval, maxInterval).toDouble();
    _save();
    _restartActiveSessions();
    notifyListeners();
  }

  void applyTimeout(double value) {
    _timeout = value.clamp(minPingTimeout, maxPingTimeout).toDouble();
    _save();
    _restartActiveSessions();
    notifyListeners();
  }

  void _restartActiveSessions() {
    for (final host in hosts) {
      if (!host.isActive) continue;
      _sessions.remove(host.id)?.stop();
      _startSession(host);
    }
  }

  void _startSession(PingHost host) {
    if (!_autoStart) return;
    final session = PingSession(host: host, interval: _interval, timeout: _timeout);
    _sessions[host.id] = session;
    session.start();
  }

  // MARK: - Selection

  void selectSingle(PingHost host) {
    selectedIDs
      ..clear()
      ..add(host.id);
    anchorID = host.id;
    notifyListeners();
  }

  void toggleSelect(PingHost host) {
    if (selectedIDs.contains(host.id)) {
      selectedIDs.remove(host.id);
    } else {
      selectedIDs.add(host.id);
      anchorID = host.id;
    }
    notifyListeners();
  }

  /// Shift-click: everything between the anchor and the tapped row.
  void selectRange(PingHost host) {
    final anchor = anchorID;
    if (anchor == null) {
      selectSingle(host);
      return;
    }
    final ai = hosts.indexWhere((h) => h.id == anchor);
    final ti = hosts.indexWhere((h) => h.id == host.id);
    if (ai < 0 || ti < 0) {
      selectSingle(host);
      return;
    }
    final lo = ai < ti ? ai : ti;
    final hi = ai < ti ? ti : ai;
    selectedIDs
      ..clear()
      ..addAll(hosts.sublist(lo, hi + 1).map((h) => h.id));
    notifyListeners();
  }

  void selectAll() {
    selectedIDs
      ..clear()
      ..addAll(hosts.map((h) => h.id));
    anchorID = hosts.isEmpty ? null : hosts.first.id;
    notifyListeners();
  }

  void clearSelection() {
    if (selectedIDs.isEmpty) return;
    selectedIDs.clear();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  void _save() {
    SettingsStore.save(Settings(
      hosts: hosts.map((h) => h.address).toList(growable: false),
      interval: _interval,
      timeout: _timeout,
    ));
  }
}
