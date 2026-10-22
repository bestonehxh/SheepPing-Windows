/// No-op window control for platforms without `dart:ffi` (the web preview
/// build). The Windows build always resolves to `win32_window.dart`.
library;

const String kWindowTitle = 'SheepPing';

void applyBorderless() {}

const int htTop = 12;
const int htTopLeft = 13;
const int htTopRight = 14;

void startDrag() {}

void startResize(int hitTest) {}

int windowHandle() => 0;

void minimize() {}

bool isMaximized() => false;

void toggleMaximize() {}

void close() {}
