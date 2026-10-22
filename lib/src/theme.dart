/// Colour + type tokens.
///
/// Values follow the macOS system palette so the app reads as "the Mac app"
/// rather than "a Windows app": `windowBackgroundColor`, `.bar` material,
/// `controlBackgroundColor` and the system status colours for both schemes.
library;

import 'package:flutter/material.dart';

@immutable
class Palette {
  const Palette({
    required this.isDark,
    required this.window,
    required this.content,
    required this.altRow,
    required this.bar,
    required this.text,
    required this.secondary,
    required this.tertiary,
    required this.separator,
    required this.accent,
    required this.green,
    required this.yellow,
    required this.orange,
    required this.red,
    required this.selection,
    required this.hover,
    required this.groupFill,
    required this.chipFill,
    required this.barBorder,
  });

  final bool isDark;

  /// Window / toolbar background.
  final Color window;

  /// Table and log list background (NSColor.controlBackgroundColor).
  final Color content;

  /// NSColor.alternatingContentBackgroundColors[1].
  final Color altRow;

  /// The `.bar` material used by the header strips.
  final Color bar;
  final Color barBorder;

  final Color text;
  final Color secondary;
  final Color tertiary;
  final Color separator;

  final Color accent;
  final Color green;
  final Color yellow;
  final Color orange;
  final Color red;

  /// accentColor at 18% — the macOS row selection tint.
  final Color selection;

  /// primary at 4%.
  final Color hover;

  /// Fill behind the toolbar's icon group.
  final Color groupFill;
  final Color chipFill;

  Color statusColor(PingStatusColor status) => switch (status) {
        PingStatusColor.idle => secondary,
        PingStatusColor.running => yellow,
        PingStatusColor.success => green,
        PingStatusColor.failed => red,
      };

  Color latencyColor(double ms) {
    if (ms < 30) return green;
    if (ms < 120) return yellow;
    return red;
  }

  Color rateColor(double rate) {
    if (rate >= 95) return green;
    if (rate >= 75) return orange;
    return red;
  }
}

/// Status enum lived in models.dart; re-declared as a narrow alias here to keep
/// this file free of model imports.
enum PingStatusColor { idle, running, success, failed }

const Palette darkPalette = Palette(
  isDark: true,
  window: Color(0xFF2C2C2E),
  content: Color(0xFF1C1C1E),
  altRow: Color(0xFF232326),
  bar: Color(0xFF2C2C2E),
  barBorder: Color(0x1FFFFFFF),
  text: Color(0xFFF2F2F7),
  secondary: Color(0x99EBEBF5),
  tertiary: Color(0x4DEBEBF5),
  separator: Color(0x1FFFFFFF),
  accent: Color(0xFF0A84FF),
  green: Color(0xFF32D74B),
  yellow: Color(0xFFFFD60A),
  orange: Color(0xFFFF9F0A),
  red: Color(0xFFFF453A),
  selection: Color(0x2E0A84FF),
  hover: Color(0x0AFFFFFF),
  groupFill: Color(0x14FFFFFF),
  chipFill: Color(0x1FFFFFFF),
);

const Palette lightPalette = Palette(
  isDark: false,
  window: Color(0xFFECECEC),
  content: Color(0xFFFFFFFF),
  altRow: Color(0xFFF7F7F8),
  bar: Color(0xFFF5F5F5),
  barBorder: Color(0x1F000000),
  text: Color(0xFF1D1D1F),
  secondary: Color(0x8A3C3C43),
  tertiary: Color(0x4D3C3C43),
  separator: Color(0x1F000000),
  accent: Color(0xFF007AFF),
  green: Color(0xFF248A3D),
  yellow: Color(0xFFB37A00),
  orange: Color(0xFFCD6000),
  red: Color(0xFFD70015),
  selection: Color(0x2E007AFF),
  hover: Color(0x0A000000),
  groupFill: Color(0x0F000000),
  chipFill: Color(0x14000000),
);

/// UI font: SF Pro's closest Windows stand-in.
const String uiFontFamily = 'Segoe UI';

/// Monospaced font, mirroring `.system(design: .monospaced)`.
const String monoFontFamily = 'Cascadia Mono';
const List<String> monoFallback = <String>['Consolas', 'Courier New', 'monospace'];

extension PaletteContext on BuildContext {
  /// The active palette, derived from the resolved brightness.
  Palette get palette =>
      Theme.of(this).brightness == Brightness.dark ? darkPalette : lightPalette;
}

/// Text styles used across the painted widgets.
class AppText {
  const AppText._();

  static const TextStyle title = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(fontFamily: uiFontFamily, fontSize: 13);

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle callout = TextStyle(fontFamily: uiFontFamily, fontSize: 12);

  static const TextStyle caption = TextStyle(fontFamily: uiFontFamily, fontSize: 11);

  static const TextStyle captionStrong = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Uppercase column header (10 pt semibold).
  static const TextStyle columnHeader = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 12.5,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 11.5,
  );

  static const TextStyle monoLog = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 11,
  );
}
