/// Renders the real widget tree at the target window size so the UI can be
/// reviewed as an image without a Windows toolchain.
///
/// Run with:
///   flutter test test/ui_golden_test.dart --update-goldens
///
/// The PNGs land in `test/goldens/`. They are review artefacts, not assertions:
/// nothing here fails on a machine without the Windows fonts, because missing
/// fonts are simply skipped.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheepping/main.dart';
import 'package:sheepping/src/models.dart';
import 'package:sheepping/src/view_model.dart';

const List<List<String>> _fonts = <List<String>>[
  <String>['Segoe UI', r'C:\Windows\Fonts\segoeui.ttf'],
  <String>['Segoe UI', r'C:\Windows\Fonts\segoeuib.ttf'],
  <String>['Segoe UI', r'C:\Windows\Fonts\segoeuisl.ttf'],
  <String>['Cascadia Mono', r'C:\Windows\Fonts\CascadiaMono.ttf'],
  <String>['Cascadia Mono', r'C:\Windows\Fonts\consola.ttf'],
  <String>['Consolas', r'C:\Windows\Fonts\consola.ttf'],
  <String>[
    'MaterialIcons',
    r'C:\Users\bestchaan\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ],
];

Future<void> _loadFonts() async {
  for (final entry in _fonts) {
    final file = File(entry[1]);
    if (!file.existsSync()) continue;
    final loader = FontLoader(entry[0])
      ..addFont(Future<ByteData>.value(
        ByteData.sublistView(file.readAsBytesSync()),
      ));
    await loader.load();
  }
}

PingViewModel _demoModel() {
  final vm = PingViewModel(autoStart: false);
  vm.hosts.clear();

  final good = PingHost('8.8.8.8')
    ..resolvedIP = '8.8.8.8'
    ..status = PingStatus.success
    ..latency = 0.1
    ..successCount = 12
    ..failCount = 0
    ..isActive = true;
  final named = PingHost('google.com')
    ..resolvedIP = '142.250.66.110'
    ..status = PingStatus.success
    ..latency = 24.0
    ..successCount = 11
    ..failCount = 1
    ..isActive = true;
  final v6 = PingHost('2606:4700:4700::1111')
    ..resolvedIP = '2606:4700:4700::1111'
    ..status = PingStatus.running
    ..latency = 138.0
    ..successCount = 8
    ..failCount = 2
    ..isActive = true;
  final down = PingHost('10.0.0.7')
    ..resolvedIP = '10.0.0.7'
    ..status = PingStatus.failed
    ..successCount = 0
    ..failCount = 4
    ..isActive = true;

  good.addLog(
    isSuccess: true,
    latency: 0.2,
    message: 'Reply from 8.8.8.8: bytes=32 time<1ms TTL=118',
  );
  good.addLog(
    isSuccess: true,
    latency: 0.1,
    message: 'Reply from 8.8.8.8: bytes=32 time<1ms TTL=118',
  );
  named.addLog(
    isSuccess: true,
    latency: 24.0,
    message: 'Reply from 142.250.66.110: bytes=32 time=24ms TTL=117',
  );
  down.addLog(isSuccess: false, message: 'Request timed out.');

  vm.hosts.addAll(<PingHost>[good, named, v6, down]);
  vm.selectSingle(good);
  return vm;
}

void _sizeTo(WidgetTester tester) {
  tester.view.physicalSize = const Size(1120, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('dark window', (WidgetTester tester) async {
    _sizeTo(tester);
    await tester.pumpWidget(SheepPingApp(vm: _demoModel()));
    // The running-status ring pulses forever, so pumpAndSettle never returns.
    await tester.pump(const Duration(milliseconds: 250));

    await expectLater(
      find.byType(SheepPingApp),
      matchesGoldenFile('goldens/dark.png'),
    );
  });

  testWidgets('empty state', (WidgetTester tester) async {
    _sizeTo(tester);
    final vm = PingViewModel(autoStart: false)..hosts.clear();
    await tester.pumpWidget(SheepPingApp(vm: vm));
    await tester.pump(const Duration(milliseconds: 250));

    await expectLater(
      find.byType(SheepPingApp),
      matchesGoldenFile('goldens/empty.png'),
    );
  });

  testWidgets('settings sheet', (WidgetTester tester) async {
    _sizeTo(tester);
    await tester.pumpWidget(SheepPingApp(vm: _demoModel()));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(SheepPingApp),
      matchesGoldenFile('goldens/settings.png'),
    );
  });

  testWidgets('add host sheet', (WidgetTester tester) async {
    _sizeTo(tester);
    await tester.pumpWidget(SheepPingApp(vm: _demoModel()));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(SheepPingApp),
      matchesGoldenFile('goldens/add-host.png'),
    );
  });
}
