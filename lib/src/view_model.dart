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
      if (!isValidAddress(address.trim())) continue;
      final host = PingHost(address.trim());
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

  /// ASCII hostnames, IPv4, IPv6 and an IPv6 zone suffix. The app is
  /// English-only, so internationalized names are entered in their ASCII
  /// (xn--) form.
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9._:%-]+$');

  /// Whether [address] can be handed to ping.exe as a target.
  ///
  /// ping.exe takes options with *either* "-" or "/", so "/t" or "-t" would
  /// become a flag rather than a host — "/t" pings forever, and a new one of
  /// those would be spawned every tick. Spaces and shell punctuation never
  /// belong in a host either.
  static bool isValidAddress(String address) =>
      address.isNotEmpty &&
      !address.startsWith('-') &&
      _hostPattern.hasMatch(address);

  /// Returns true when the address was actually added.
  bool addHost(String rawAddress) {
    final added = _insert(rawAddress);
    if (added) {
      _save();
      notifyListeners();
    }
    return added;
  }

  /// Adds every address in [list] and saves once. Returns how many were new.
  int addHosts(Iterable<String> list) {
    var count = 0;
    for (final address in list) {
      if (_insert(address)) count += 1;
    }
    if (count > 0) {
      _save();
      notifyListeners();
    }
    return count;
  }

  bool _insert(String rawAddress) {
    final address = rawAddress.trim();
    if (!isValidAddress(address)) return false;
    for (final h in hosts) {
      if (h.address.toLowerCase() == address.toLowerCase()) return false;
    }
    final host = PingHost(address);
    hosts.add(host);
    _startSession(host);
    return true;
  }

  void removeHost(PingHost host) => removeHosts(<PingHost>[host]);

  void removeHosts(Iterable<PingHost> list) {
    for (final host in list.toList(growable: false)) {
      _sessions.remove(host.id)?.stop();
      selectedIDs.remove(host.id);
      if (anchorID == host.id) anchorID = null;
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
    final session = PingSession(
      host: host,
      interval: _interval,
      timeout: _timeout,
    );
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
    SettingsStore.save(
      Settings(
        hosts: hosts.map((h) => h.address).toList(growable: false),
        interval: _interval,
        timeout: _timeout,
      ),
    );
  }
}
