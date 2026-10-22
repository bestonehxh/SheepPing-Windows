/// The unified title bar: window title on the left, the toolbar on the right.
/// Mirrors `buildToolbar()` from `PingInfoView.swift`.
///
/// On macOS 26 a `ToolbarItemGroup` renders each run of buttons between two
/// `Divider()`s as its own glass capsule, so the bar reads
/// `[+ −]  [■ ▶ ↻]  (● N active)  [⚙]`. The window controls on the far right
/// stay Windows-native (Windows 11 caption buttons), by request.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../win32_window_stub.dart' if (dart.library.ffi) '../win32_window.dart';

class TitleBar extends StatefulWidget {
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

  /// The macOS unified toolbar height.
  static const double height = 52;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WidgetsBindingObserver {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maximized = isMaximized();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Maximise/restore always resizes the view, so this keeps the caption
  /// glyph and the top resize strip in step with the window state.
  @override
  void didChangeMetrics() {
    final bool now = isMaximized();
    if (now != _maximized) setState(() => _maximized = now);
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    final Widget bar = Container(
      height: TitleBar.height,
      decoration: BoxDecoration(
        color: p.window,
        border: Border(bottom: BorderSide(color: p.separator, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The title and all the empty space around it move the window.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => startDrag(),
              onDoubleTap: toggleMaximize,
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'SheepPing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(child: _toolbar(p)),
          const SizedBox(width: 14),
          Align(
            alignment: Alignment.topCenter,
            child: _WindowButtons(maximized: _maximized),
          ),
        ],
      ),
    );

    if (_maximized) return bar;

    // The runner removed the native top border, so resizing from the top edge
    // is picked up here: a thin strip across the top, and its two corners.
    return Stack(
      children: <Widget>[
        bar,
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _resizeStrip,
          child: _ResizeEdge(
            hitTest: htTop,
            cursor: SystemMouseCursors.resizeUpDown,
          ),
        ),
        const Positioned(
          left: 0,
          top: 0,
          width: _resizeCorner,
          height: _resizeCorner,
          child: _ResizeEdge(
            hitTest: htTopLeft,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        const Positioned(
          right: 0,
          top: 0,
          width: _resizeCorner,
          height: _resizeCorner,
          child: _ResizeEdge(
            hitTest: htTopRight,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(Palette p) {
    final w = widget;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Capsule(
          children: <Widget>[
            _BarButton(
              icon: Icons.add_rounded,
              tooltip: 'Add a new host to monitor',
              onPressed: w.onAdd,
            ),
            _BarButton(
              icon: Icons.remove_rounded,
              tooltip: 'Remove selected host(s) (Delete)',
              onPressed: w.hasSelection ? w.onRemove : null,
            ),
          ],
        ),
        const SizedBox(width: 8),
        _Capsule(
          children: <Widget>[
            _BarButton(
              icon: Icons.stop_rounded,
              tooltip: 'Stop all active pings',
              onPressed: w.anyActive ? w.onStopAll : null,
            ),
            _BarButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Resume stopped hosts',
              onPressed: w.anyInactive ? w.onResume : null,
            ),
            _BarButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Clear stats and restart all hosts',
              onPressed: w.hasHosts ? w.onRestart : null,
            ),
          ],
        ),
        if (w.hasHosts) ...<Widget>[
          const SizedBox(width: 8),
          _StatusChip(active: w.anyActive, count: w.sessionCount),
        ],
        const SizedBox(width: 8),
        _Capsule(
          children: <Widget>[
            _BarButton(
              icon: Icons.tune_rounded,
              tooltip: 'Ping interval and other settings',
              onPressed: w.onSettings,
            ),
          ],
        ),
      ],
    );
  }
}

const double _resizeStrip = 5;
const double _resizeCorner = 10;

class _ResizeEdge extends StatelessWidget {
  const _ResizeEdge({required this.hitTest, required this.cursor});

  final int hitTest;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => startResize(hitTest),
      ),
    );
  }
}

/// One glass capsule of toolbar buttons.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.children});

  final List<Widget> children;

  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: p.groupFill,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: p.barBorder, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
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

    Color fill = Colors.transparent;
    if (enabled && _down) {
      fill = p.text.withValues(alpha: 0.16);
    } else if (enabled && _hover) {
      fill = p.text.withValues(alpha: 0.09);
    }

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
            width: 36,
            height: 28,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(widget.icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// The live "● N active" capsule (`.regularMaterial` on macOS).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active, required this.count});

  final bool active;
  final int count;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final String text = active ? '$count active' : 'Stopped';

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: p.chipFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.barBorder, width: 1),
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

/// Windows 11 caption buttons: 46×32, flush with the top-right corner, glyphs
/// from the system icon font, red close on hover.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.maximized});

  final bool maximized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _CaptionButton(glyph: '', tooltip: 'Minimize', onTap: minimize),
        _CaptionButton(
          glyph: maximized ? '' : '',
          tooltip: maximized ? 'Restore Down' : 'Maximize',
          onTap: toggleMaximize,
        ),
        const _CaptionButton(
          glyph: '',
          tooltip: 'Close',
          onTap: close,
          isClose: true,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final String glyph;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _down = false;

  static const Color _closeHover = Color(0xFFC42B1C);
  static const Color _closeDown = Color(0xFFB22A1B);

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    Color fill = Colors.transparent;
    Color ink = p.text.withValues(alpha: 0.85);
    if (widget.isClose && (_hover || _down)) {
      fill = _down ? _closeDown : _closeHover;
      ink = Colors.white;
    } else if (_down) {
      fill = p.text.withValues(alpha: 0.04);
    } else if (_hover) {
      fill = p.text.withValues(alpha: 0.07);
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            widget.onTap();
          },
          child: Container(
            width: 46,
            height: 32,
            color: fill,
            alignment: Alignment.center,
            child: Text(
              widget.glyph,
              style: TextStyle(
                fontFamily: 'Segoe Fluent Icons',
                fontFamilyFallback: const <String>['Segoe MDL2 Assets'],
                fontSize: 10,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
