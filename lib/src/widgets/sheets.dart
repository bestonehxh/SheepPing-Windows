/// The two modal sheets, ported from `AddHostSheet` and `SettingsSheet`.
///
/// Presentation mimics macOS: the panel drops in from the title bar over a dim
/// window, is not dismissed by clicking outside, and closes on Escape.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart'
    show MacosSlider, MacosTheme, MacosThemeData;


import '../theme.dart';
import '../view_model.dart';

Future<void> showAddHostSheet(BuildContext context, PingViewModel vm) {
  return _showSheet<void>(
    context,
    _AddHostSheet(vm: vm, onAdded: () => Navigator.of(context).pop()),
  );
}

Future<void> showSettingsSheet(BuildContext context, PingViewModel vm) {
  return _showSheet<void>(context, _SettingsSheet(vm: vm));
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Sheet',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext ctx, _, __) => sheet,
    transitionBuilder: (BuildContext ctx, Animation<double> animation, _, Widget child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(curved),
          // The route sits above HomeShell, so it needs its own MacosTheme for
          // the macos_ui controls inside the sheet.
          child: MacosTheme(
            data: dark ? MacosThemeData.dark() : MacosThemeData.light(),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Rounded floating panel, centred under the title bar.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.width,
    required this.body,
    required this.onEscape,
    this.footer,
  });

  final double width;
  final List<Widget> body;
  final VoidCallback onEscape;

  /// Pinned below the scrolling body so the sheet's primary action is always
  /// reachable even when the window is short.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): onEscape,
          },
          child: Focus(
            autofocus: true,
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                // A short window must scroll the sheet rather than overflow it,
                // which is what macOS does with a tall sheet.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height - 38,
                ),
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    color: p.window,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.separator, width: 1),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: 4,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              24, 24, 24, footer == null ? 24 : 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: body,
                          ),
                        ),
                      ),
                      if (footer != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Divider(height: 1, color: p.separator),
                              const SizedBox(height: 16),
                              footer!,
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: p.accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: uiFontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: p.text,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// MARK: - Add Host

class _AddHostSheet extends StatefulWidget {
  const _AddHostSheet({required this.vm, required this.onAdded});

  final PingViewModel vm;
  final VoidCallback onAdded;

  @override
  State<_AddHostSheet> createState() => _AddHostSheetState();
}

class _AddHostSheetState extends State<_AddHostSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isEmpty => _controller.text.trim().isEmpty;

  void _submit() {
    if (_isEmpty) return;
    for (final line in _controller.text.split('\n')) {
      final address = line.trim();
      if (address.isNotEmpty) widget.vm.addHost(address);
    }
    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return _SheetFrame(
      width: 420,
      onEscape: widget.onAdded,
      body: <Widget>[
        const _SheetTitle(icon: Icons.add_circle, label: 'Add Host'),
        const SizedBox(height: 18),
        SizedBox(
          height: 132,
          child: Container(
            decoration: BoxDecoration(
              color: p.content,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: p.secondary.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _submit,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                maxLines: null,
                minLines: 3,
                cursorColor: p.accent,
                style: AppText.mono.copyWith(color: p.text),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'One host per line â€” e.g. 8.8.8.8, google.com or 2606:4700:4700::1111. '
          'IP addresses and hostnames are both supported, and DNS is resolved '
          'automatically. Press Ctrl+Enter to add.',
          style: AppText.caption.copyWith(color: p.secondary),
        ),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _SheetButton(
            label: 'Cancel',
            onPressed: widget.onAdded,
          ),
          const SizedBox(width: 10),
          _SheetButton(
            label: 'Add',
            prominent: true,
            onPressed: _isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// MARK: - Settings

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.vm});

  final PingViewModel vm;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late double _intervalDraft = widget.vm.interval;
  late double _timeoutDraft = widget.vm.timeout;

  static double _snap(double value) => (value * 2).round() / 2;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return _SheetFrame(
      width: 430,
      onEscape: () => Navigator.of(context).pop(),
      body: <Widget>[
        const _SheetTitle(icon: Icons.tune, label: 'Settings'),
        const SizedBox(height: 16),
        _GroupBox(
          icon: Icons.timer_outlined,
          label: 'Ping Interval',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ValueRow(
                title: 'Ping Interval',
                subtitle: 'How often each host is pinged',
                value: '${_intervalDraft.toStringAsFixed(1)} s',
              ),
              const SizedBox(height: 4),
              _Slider(
                value: _intervalDraft,
                min: PingViewModel.minInterval,
                max: PingViewModel.maxInterval,
                onChanged: (double v) =>
                    setState(() => _intervalDraft = _snap(v).clamp(
                          PingViewModel.minInterval,
                          PingViewModel.maxInterval,
                        )),
                onCommit: () => widget.vm.applyInterval(_intervalDraft),
              ),
              const SizedBox(height: 2),
              _RangeLabels(left: '0.5 s (fast)', right: '30 s (slow)'),
              const SizedBox(height: 8),
              _Note(
                'Changes apply immediately to all active hosts and are saved '
                'as the default.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GroupBox(
          icon: Icons.hourglass_empty,
          label: 'Reply Timeout',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ValueRow(
                title: 'Reply Timeout',
                subtitle:
                    'How long to wait for a reply before marking a ping failed',
                value: '${_timeoutDraft.toStringAsFixed(1)} s',
              ),
              const SizedBox(height: 4),
              _Slider(
                value: _timeoutDraft,
                min: PingViewModel.minPingTimeout,
                max: PingViewModel.maxPingTimeout,
                onChanged: (double v) =>
                    setState(() => _timeoutDraft = _snap(v).clamp(
                          PingViewModel.minPingTimeout,
                          PingViewModel.maxPingTimeout,
                        )),
                onCommit: () => widget.vm.applyTimeout(_timeoutDraft),
              ),
              const SizedBox(height: 2),
              _RangeLabels(
                left: '${PingViewModel.minPingTimeout.toStringAsFixed(1)} s',
                right: '${PingViewModel.maxPingTimeout.toStringAsFixed(0)} s',
              ),
              const SizedBox(height: 8),
              if (_timeoutDraft < 1)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, size: 13, color: p.orange),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Below 1 s, hosts on slow or distant links will report '
                        'false timeouts.',
                        style: AppText.caption.copyWith(color: p.orange),
                      ),
                    ),
                  ],
                )
              else
                _Note(
                  'Independent of the ping interval, so a fast interval no '
                  'longer marks slow hosts as failed.',
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _SheetButton(
            label: 'Done',
            prominent: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _GroupBox extends StatelessWidget {
  const _GroupBox({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
      decoration: BoxDecoration(
        color: p.content.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.separator, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 13, color: p.secondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppText.caption.copyWith(color: p.secondary),
              ),
            ],
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              fontFamily: uiFontFamily,
              fontSize: 17,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: p.text,
            ),
          ),
      ],
    );
  }
}

class _RangeLabels extends StatelessWidget {
  const _RangeLabels({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final style = AppText.caption.copyWith(fontSize: 10, color: p.tertiary);

    return Row(
      children: <Widget>[
        Text(left, style: style),
        const Spacer(),
        Text(right, style: style),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppText.caption.copyWith(color: context.palette.secondary),
    );
  }
}

/// `MacosSlider` plus a commit callback: the original only writes the setting
/// when the drag ends, because applying per tick restarts every ping session.
class _Slider extends StatelessWidget {
  const _Slider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onCommit,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Listener(
      onPointerUp: (_) => onCommit(),
      child: MacosSlider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        color: p.accent,
      ),
    );
  }
}

/// `.borderedProminent` / plain push button.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onPressed,
    this.prominent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final bool enabled = onPressed != null;

    // `.borderedProminent` is the only filled button; everything else is the
    // standard grey push button. (macos_ui's PushButton always paints the
    // accent gradient, so the two styles are drawn here.)
    final Color background = prominent
        ? p.accent
        : (p.isDark ? const Color(0xFF4A4A4C) : Colors.white);
    final Color foreground =
        prominent ? Colors.white : (p.isDark ? p.text : p.text);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
              border: prominent
                  ? null
                  : Border.all(
                      color: p.secondary.withValues(alpha: 0.35),
                      width: 1,
                    ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: AppText.body.copyWith(
                color: foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
