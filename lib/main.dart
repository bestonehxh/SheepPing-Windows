/// SheepPing â€” a Windows port of the macOS ping monitor by bestonehxh.
///
/// The window is deliberately drawn without system chrome: [TitleBar] rebuilds
/// the macOS unified toolbar (icon-only segmented group + "N active" chip), and
/// the table/log split is dragged exactly like SwiftUI's `VSplitView`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart' show MacosTheme, MacosThemeData;

import 'src/export.dart';

import 'src/theme.dart';
import 'src/view_model.dart';
import 'src/widgets/host_table.dart';
import 'src/widgets/log_panel.dart';
import 'src/widgets/sheets.dart';
import 'src/widgets/title_bar.dart';
import 'src/win32_window_stub.dart'
    if (dart.library.ffi) 'src/win32_window.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The runner has already created and shown the window at this point, so the
  // caption can go before the first frame instead of flashing for one.
  applyBorderless();
  runApp(SheepPingApp(vm: PingViewModel()));
}

class SheepPingApp extends StatelessWidget {
  const SheepPingApp({super.key, required this.vm});

  final PingViewModel vm;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: 'SheepPing',
          debugShowCheckedModeBanner: false,
          // Night mode only: the table and log are designed against a single
          // dark palette, so there is no light scheme to switch to.
          themeMode: ThemeMode.dark,
          darkTheme: _materialTheme(darkPalette),
          theme: _materialTheme(darkPalette),
          home: Builder(
            builder: (BuildContext ctx) {
              return MacosTheme(
                data: MacosThemeData.dark(),
                child: HomeShell(vm: vm),
              );
            },
          ),
        );
      },
    );
  }

  /// Material only provides scaffolding here â€” every visible pixel comes from
  /// the palette, so the Material theme just needs to agree on brightness,
  /// fonts and selection colour.
  static ThemeData _materialTheme(Palette p) {
    final Brightness brightness =
        p.isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: uiFontFamily,
      scaffoldBackgroundColor: p.window,
      canvasColor: p.window,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
      ).copyWith(surface: p.window),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.selection,
        selectionHandleColor: p.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.window,
        surfaceTintColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(p.secondary.withValues(alpha: 0.4)),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.vm});

  final PingViewModel vm;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Height of the log pane. The original starts at roughly half the window and
  /// enforces `minHeight: 220` for the table / `160` for the log.
  double _logHeight = 210;

  static const double _minTable = 220;
  static const double _minLog = 160;
  static const double _splitterHit = 7;

  PingViewModel get vm => widget.vm;

  void _removeSelected() {
    if (vm.selectedIDs.isEmpty) return;
    vm.removeHosts(vm.selectedHosts);
  }

  Future<void> _copyRows() async {
    final selected = vm.selectedHosts;
    if (selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: pingCsv(selected)));
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.delete): _removeSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _removeSelected,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          if (vm.hosts.isNotEmpty) vm.selectAll();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copyRows,
        const SingleActivator(LogicalKeyboardKey.escape): vm.clearSelection,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          // Text renders a "missing Material ancestor" underline without this.
          type: MaterialType.transparency,
          child: ColoredBox(
          color: p.window,
          child: Column(
            children: <Widget>[
              TitleBar(
                anyActive: vm.anyActive,
                anyInactive: vm.anyInactive,
                sessionCount: vm.sessionCount,
                hasHosts: vm.hosts.isNotEmpty,
                hasSelection: vm.selectedIDs.isNotEmpty,
                onAdd: () => showAddHostSheet(context, vm),
                onRemove: _removeSelected,
                onStopAll: vm.stopAll,
                onResume: vm.resumeAll,
                onRestart: vm.restartAll,
                onSettings: () => showSettingsSheet(context, vm),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double maxLog =
                        (c.maxHeight - _minTable).clamp(_minLog, c.maxHeight);
                    final double logHeight = _logHeight.clamp(_minLog, maxLog);

                    return Column(
                      children: <Widget>[
                        Expanded(child: HostTable(hosts: vm.hosts, vm: vm)),
                        _Splitter(
                          palette: p,
                          onDrag: (double dy) {
                            setState(() {
                              _logHeight = (_logHeight - dy).clamp(
                                _minLog,
                                (c.maxHeight - _minTable)
                                    .clamp(_minLog, c.maxHeight),
                              );
                            });
                          },
                          height: _splitterHit,
                        ),
                        SizedBox(
                          height: logHeight,
                          child: LogSection(vm: vm),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px divider with a 7 px grab area, like the `VSplitView` separator.
class _Splitter extends StatefulWidget {
  const _Splitter({
    required this.palette,
    required this.onDrag,
    required this.height,
  });

  final Palette palette;
  final ValueChanged<double> onDrag;
  final double height;

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final bool hot = _hover || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragEnd: (_) => setState(() => _dragging = false),
        onVerticalDragCancel: () => setState(() => _dragging = false),
        onVerticalDragUpdate: (DragUpdateDetails d) => widget.onDrag(d.delta.dy),
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: Container(
              height: 1,
              color: hot
                  ? p.accent.withValues(alpha: 0.7)
                  : p.separator,
            ),
          ),
        ),
      ),
    );
  }
}
