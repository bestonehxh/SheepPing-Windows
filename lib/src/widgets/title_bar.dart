/// The unified title bar: window title on the left, the macOS-style segmented
/// toolbar group on the right. Mirrors `buildToolbar()` from `PingInfoView.swift`
/// (a `ToolbarItemGroup(placement: .primaryAction)` renders exactly like this on
/// macOS: icon-only buttons, right aligned, inside one rounded group).
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../win32_window_stub.dart'
    if (dart.library.ffi) '../win32_window.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.anyActive,
    required this.anyInactive,
    required this.sessionCount,
    required this.hasHosts,
    required this.hasSelection,
    required this.onAdd,
    required this.onRemove,
    required this.onStopAll,
    required this.onResume,
    required this.onRestart,
    required this.onSettings,
  });

  final bool anyActive;
  final bool anyInactive;
  final int sessionCount;
  final bool hasHosts;
  final bool hasSelection;

  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onStopAll;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onSettings;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: p.window,
        border: Border(bottom: BorderSide(color: p.separator, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          // Draggable region covers the empty space to the left of the groups.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => startDrag(),
              onDoubleTap: toggleMaximize,
              child: const SizedBox.expand(),
            ),
          ),
          _ToolbarGroup(
            anyActive: anyActive,
            anyInactive: anyInactive,
            sessionCount: sessionCount,
            hasHosts: hasHosts,
            hasSelection: hasSelection,
            onAdd: onAdd,
            onRemove: onRemove,
            onStopAll: onStopAll,
            onResume: onResume,
            onRestart: onRestart,
            onSettings: onSettings,
          ),
          const SizedBox(width: 8),
          _WindowButtons(p: p),
        ],
      ),
    );
  }
}

class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({
    required this.anyActive,
    required this.anyInactive,
    required this.sessionCount,
    required this.hasHosts,
    required this.hasSelection,
    required this.onAdd,
    required this.onRemove,
    required this.onStopAll,
    required this.onResume,
    required this.onRestart,
    required this.onSettings,
  });

  final bool anyActive;
  final bool anyInactive;
  final int sessionCount;
  final bool hasHosts;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onStopAll;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: p.groupFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: p.barBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _BarButton(
            icon: Icons.add,
            tooltip: 'Add a new host to monitor',
            onPressed: onAdd,
          ),
          _BarButton(
            icon: Icons.remove,
            tooltip: 'Remove selected host(s) (Delete)',
            onPressed: hasSelection ? onRemove : null,
          ),
          _Divider(p: p),
          _BarButton(
            icon: Icons.stop,
            tooltip: 'Stop all active pings',
            onPressed: anyActive ? onStopAll : null,
          ),
          _BarButton(
            icon: Icons.play_arrow,
            tooltip: 'Resume stopped hosts',
            onPressed: anyInactive ? onResume : null,
          ),
          _BarButton(
            icon: Icons.refresh,
            tooltip: 'Clear stats and restart all hosts',
            onPressed: hasHosts ? onRestart : null,
          ),
          if (hasHosts) ...<Widget>[
            _Divider(p: p),
            _StatusChip(active: anyActive, count: sessionCount),
          ],
          _BarButton(
            icon: Icons.tune,
            tooltip: 'Ping interval and other settings',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.p});
  final Palette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: p.separator,
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final bool enabled = widget.onPressed != null;
    final Color color = enabled ? p.text : p.tertiary;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _down = false);
                  widget.onPressed!();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              color: _down
                  ? p.text.withValues(alpha: 0.14)
                  : (_hover && enabled
                      ? p.text.withValues(alpha: 0.08)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active, required this.count});

  final bool active;
  final int count;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final String text = active ? '$count active' : 'Stopped';

    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: p.chipFill,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: active ? p.green : p.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: AppText.caption.copyWith(color: p.secondary)),
        ],
      ),
    );
  }
}

/// The window controls sit flush against the right edge of the bar, drawn as
/// plain caption buttons (no capsule) so they read like Windows' own minimise /
/// maximise / close cluster.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.p});
  final Palette p;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CaptionButton(icon: Icons.remove, p: p, onTap: minimize),
        _CaptionButton(icon: Icons.crop_square, p: p, onTap: toggleMaximize),
        _CaptionButton(icon: Icons.close, p: p, onTap: close),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.icon, required this.p, required this.onTap});
  final IconData icon;
  final Palette p;
  final VoidCallback onTap;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool isClose = widget.icon == Icons.close;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: _hover
                ? (isClose
                    ? widget.p.red.withValues(alpha: 0.85)
                    : widget.p.text.withValues(alpha: 0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 13,
            color: _hover && isClose ? Colors.white : widget.p.secondary,
          ),
        ),
      ),
    );
  }
}
