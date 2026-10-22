/// No-op window control for platforms without `dart:ffi` (the web preview
/// build). The Windows build always resolves to `win32_window.dart`.
library;

const String kWindowTitle = 'SheepPing';

void applyBorderless() {}

void startDrag() {}

void minimize() {}

bool isMaximized() => false;

void toggleMaximize() {}

void close() {}
