/// The bottom log pane, ported from `HostLogSection`, `MultiSelectionPanel`,
/// `LogRow` and `LogActionButton` in `PingInfoView.swift`.
///
/// Three modes, mirroring the Swift `logSection` switch:
///   * nothing selected  → the placeholder strip,
///   * one host selected → its live packet log with Copy / Save… / Clear,
///   * several selected  → per-host entry counts with Save Selected… / Save All….
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export.dart';
import '../models.dart';
import '../save_file_stub.dart' if (dart.library.ffi) '../save_panel.dart';
import '../theme.dart';
import '../view_model.dart';
import 'host_table.dart';

class LogSection extends StatelessWidget {
  const LogSection({super.key, required this.vm});

  final PingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final selected = vm.selectedHosts;
    if (selected.isEmpty) return const _Placeholder();
    if (selected.length == 1) {
      // Keyed by host: without it the State (and a pending "Copied!" or
      // "Saved!" flash) carried over to the next host that was selected.
      return _HostLogPanel(
        key: ValueKey<String>(selected.first.id),
        host: selected.first,
      );
    }
    return _MultiSelectionPanel(hosts: selected, allHosts: vm.hosts);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Column(
      children: <Widget>[
        _LogHeaderBar(
          p: p,
          children: <Widget>[
            Icon(Icons.subject, size: 14, color: p.tertiary),
            const SizedBox(width: 8),
            Text(
              'Select a host to view its log',
              style: AppText.body.copyWith(color: p.secondary),
            ),
          ],
        ),
        // A childless ColoredBox in a centre-aligned Column is laid out zero
        // pixels wide, which left this pane showing the window colour.
        Expanded(
          child: ColoredBox(color: p.content, child: const SizedBox.expand()),
        ),
      ],
    );
  }
}

class _HostLogPanel extends StatefulWidget {
  const _HostLogPanel({super.key, required this.host});

  final PingHost host;

  @override
  State<_HostLogPanel> createState() => _HostLogPanelState();
}

class _HostLogPanelState extends State<_HostLogPanel> {
  bool _copied = false;
  bool _saved = false;
  bool _cleared = false;

  final List<Timer> _timers = <Timer>[];

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _flash(void Function() set, void Function() clear, double seconds) {
    setState(set);
    _timers.add(
      Timer(Duration(milliseconds: (seconds * 1000).round()), () {
        if (mounted) setState(clear);
      }),
    );
  }

  Future<void> _save() async {
    final host = widget.host;
    try {
      final path = await saveTextFile(
        suggestedName: 'ping-${safeFileName(host.address)}.csv',
        title: 'Save log as CSV',
        content: logCsv(host),
      );
      if (path == null || !mounted) return;
      _flash(() => _saved = true, () => _saved = false, 1.5);
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(
            error is SaveFailure
                ? "Couldn't save ${error.fileName}"
                : "Couldn't save the log",
          ),
          content: Text(_saveErrorText(error)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final host = widget.host;

    return AnimatedBuilder(
      animation: host,
      builder: (BuildContext context, Widget? _) {
        return Column(
          children: <Widget>[
            _LogHeaderBar(
              p: p,
              children: <Widget>[
                Transform.scale(
                  scale: 0.85,
                  child: StatusDot(status: host.status),
                ),
                const SizedBox(width: 6),
                Text(
                  host.address,
                  style: AppText.bodyStrong.copyWith(color: p.text),
                ),
                const SizedBox(width: 6),
                Text('·', style: AppText.body.copyWith(color: p.tertiary)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    host.resolvedIP.isEmpty ? 'resolving…' : host.resolvedIP,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.monoSmall.copyWith(color: p.secondary),
                  ),
                ),
                const Spacer(),
                Text(
                  '${host.log.length} entries',
                  style: AppText.caption.copyWith(color: p.tertiary),
                ),
                if (host.log.isNotEmpty) ...<Widget>[
                  _VDivider(p: p, height: 14),
                  _LogActionButton(
                    label: _copied ? 'Copied!' : 'Copy',
                    icon: _copied ? Icons.check : Icons.copy_all_outlined,
                    tint: _copied ? p.green : p.secondary,
                    active: _copied,
                    tooltip: 'Copy log to clipboard',
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: logCsv(host)),
                      );
                      if (!mounted) return;
                      _flash(() => _copied = true, () => _copied = false, 1.5);
                    },
                  ),
                  _LogActionButton(
                    label: _saved ? 'Saved!' : 'Save…',
                    icon: _saved ? Icons.check : Icons.download_outlined,
                    tint: _saved ? p.green : p.secondary,
                    active: _saved,
                    tooltip: 'Save log as CSV',
                    onTap: _save,
                  ),
                  _VDivider(p: p, height: 14),
                  _LogActionButton(
                    label: _cleared ? 'Cleared!' : 'Clear',
                    tint: _cleared ? p.orange : p.secondary,
                    active: _cleared,
                    tooltip: 'Clear log',
                    onTap: () {
                      host.clearLog();
                      _flash(
                        () => _cleared = true,
                        () => _cleared = false,
                        1.2,
                      );
                    },
                  ),
                ],
              ],
            ),
            Expanded(
              child: ColoredBox(
                color: p.content,
                child: host.log.isEmpty
                    ? const SizedBox.expand()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: host.log.length,
                        itemExtent: 18,
                        itemBuilder: (BuildContext context, int i) =>
                            _LogRow(entry: host.log[i]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MultiSelectionPanel extends StatefulWidget {
  const _MultiSelectionPanel({required this.hosts, required this.allHosts});

  final List<PingHost> hosts;
  final List<PingHost> allHosts;

  @override
  State<_MultiSelectionPanel> createState() => _MultiSelectionPanelState();
}

class _MultiSelectionPanelState extends State<_MultiSelectionPanel> {
  bool _savedSelection = false;
  bool _savedAll = false;
  final List<Timer> _timers = <Timer>[];

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _save(List<PingHost> targets, bool all) async {
    final name = targets.length == 1 && !all
        ? 'ping-${safeFileName(targets.first.address)}.csv'
        : 'ping-export.csv';
    try {
      final path = await saveTextFile(
        suggestedName: name,
        title: 'Save logs as CSV',
        content: combinedLogCsv(targets),
      );
      if (path == null || !mounted) return;
      setState(() {
        if (all) {
          _savedAll = true;
        } else {
          _savedSelection = true;
        }
      });
      _timers.add(
        Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          setState(() {
            _savedAll = false;
            _savedSelection = false;
          });
        }),
      );
    } catch (error) {
      // A read-only destination must not claim success; surface it instead.
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(
            error is SaveFailure
                ? "Couldn't save ${error.fileName}"
                : "Couldn't save the log",
          ),
          content: Text(_saveErrorText(error)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Column(
      children: <Widget>[
        _LogHeaderBar(
          p: p,
          children: <Widget>[
            Icon(Icons.check_circle, size: 14, color: p.accent),
            const SizedBox(width: 8),
            Text(
              '${widget.hosts.length} hosts selected',
              style: AppText.bodyStrong.copyWith(color: p.text),
            ),
            const Spacer(),
            _LogActionButton(
              label: _savedSelection ? 'Saved!' : 'Save Selected…',
              icon: _savedSelection ? Icons.check : Icons.download_outlined,
              tint: _savedSelection ? p.green : p.secondary,
              active: _savedSelection,
              tooltip: "Save selected hosts' logs as CSV",
              onTap: () => _save(widget.hosts, false),
            ),
            _LogActionButton(
              label: _savedAll ? 'Saved!' : 'Save All…',
              icon: _savedAll ? Icons.check : Icons.download,
              tint: _savedAll ? p.green : p.secondary,
              active: _savedAll,
              tooltip: "Save all hosts' logs as CSV",
              onTap: () => _save(widget.allHosts, true),
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: p.content,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.hosts.length,
              itemBuilder: (BuildContext context, int i) {
                final host = widget.hosts[i];
                return AnimatedBuilder(
                  animation: host,
                  builder: (BuildContext context, Widget? _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Col.hPad,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: p.separator.withValues(
                            alpha: p.separator.a * 0.4,
                          ),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Transform.scale(
                          scale: 0.75,
                          child: StatusDot(status: host.status),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            host.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.monoSmall.copyWith(color: p.text),
                          ),
                        ),
                        Text(
                          '${host.log.length} entries',
                          style: AppText.caption.copyWith(color: p.tertiary),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The body of the save-failure alert. Anything that is not a [SaveFailure]
/// carries OS text in the Windows display language, so it is not shown.
String _saveErrorText(Object error) =>
    error is SaveFailure ? error.reason : 'The file could not be written.';

/// The `.bar` strip used at the top of every log mode.
class _LogHeaderBar extends StatelessWidget {
  const _LogHeaderBar({required this.p, required this.children});

  final Palette p;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: Col.hPad),
      decoration: BoxDecoration(
        color: p.bar,
        border: Border(bottom: BorderSide(color: p.separator, width: 1)),
      ),
      child: Row(children: children),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider({required this.p, required this.height});

  final Palette p;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: p.separator,
    );
  }
}

class _LogActionButton extends StatefulWidget {
  const _LogActionButton({
    required this.label,
    this.icon,
    required this.tint,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color tint;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_LogActionButton> createState() => _LogActionButtonState();
}

class _LogActionButtonState extends State<_LogActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final Color tint = widget.tint;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: widget.active
                  ? tint.withValues(alpha: 0.15)
                  : (_hover ? p.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.icon != null) ...<Widget>[
                  Icon(widget.icon, size: 11, color: tint),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: AppText.caption.copyWith(color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One packet: colour bar, time, latency, message.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  String get _time {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = entry.timestamp;
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final double? ms = entry.latency;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: entry.isSuccess ? p.green : p.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _time,
              style: AppText.monoLog.copyWith(color: p.secondary),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              ms == null
                  ? '  timeout'
                  : '${ms.toStringAsFixed(1).padLeft(6)} ms',
              textAlign: TextAlign.right,
              style: AppText.monoLog.copyWith(
                color: ms == null ? p.red : p.latencyColor(ms),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.monoLog.copyWith(color: p.secondary),
            ),
          ),
        ],
      ),
    );
  }
}
