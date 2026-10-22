/// Minimal Win32 window control through `dart:ffi`.
///
/// The macOS app has a unified title bar with no system chrome. The runner
/// (`windows/runner/win32_window.cpp`, `WM_NCCALCSIZE`) removes the caption and
/// the top resize border; the rest lives here:
///   * round the corners and force the dark frame (Windows 11),
///   * start a native drag from Flutter (so a drag can begin on the custom bar
///     while ordinary clicks still reach the toolbar buttons),
///   * resize from the top edge, which no longer has a native frame,
///   * minimise / maximise / close.
///
/// `dart:ffi` is used instead of `window_manager` on purpose: plugins require
/// symlink support (Windows Developer Mode), and this keeps the build free of
/// that requirement.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _dwmapi = DynamicLibrary.open('dwmapi.dll');

// messages / commands
const int _wmClose = 0x0010;
const int _wmNcLButtonDown = 0x00A1;
const int _htCaption = 2;

/// `WM_NCLBUTTONDOWN` hit-test codes for the edges the toolbar can resize.
const int htTop = 12;
const int htTopLeft = 13;
const int htTopRight = 14;
const int _swMinimize = 6;
const int _swMaximize = 3;
const int _swRestore = 9;
const int _dwmwaWindowCornerPreference = 33;
const int _dwmwaUseImmersiveDarkMode = 20;

typedef _FindWindowWC = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowWD = int Function(Pointer<Utf16>, Pointer<Utf16>);

typedef _ShowWindowC = Int32 Function(IntPtr, Int32);
typedef _ShowWindowD = int Function(int, int);

typedef _IsZoomedC = Int32 Function(IntPtr);
typedef _IsZoomedD = int Function(int);

typedef _SendMessageC = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _SendMessageD = int Function(int, int, int, int);

typedef _PostMessageC = Int32 Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _PostMessageD = int Function(int, int, int, int);

typedef _ReleaseCaptureC = Int32 Function();
typedef _ReleaseCaptureD = int Function();

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdD = int Function(int, Pointer<Uint32>);

typedef _GetCurrentProcessIdC = Uint32 Function();
typedef _GetCurrentProcessIdD = int Function();

typedef _DwmSetC = Int32 Function(IntPtr, Uint32, Pointer<Int32>, Uint32);
typedef _DwmSetD = int Function(int, int, Pointer<Int32>, int);

class _Api {
  _Api()
    : _findWindow = _user32.lookupFunction<_FindWindowWC, _FindWindowWD>(
        'FindWindowW',
      ),
      _showWindow = _user32.lookupFunction<_ShowWindowC, _ShowWindowD>(
        'ShowWindow',
      ),
      _isZoomed = _user32.lookupFunction<_IsZoomedC, _IsZoomedD>('IsZoomed'),
      _sendMessage = _user32.lookupFunction<_SendMessageC, _SendMessageD>(
        'SendMessageW',
      ),
      _postMessage = _user32.lookupFunction<_PostMessageC, _PostMessageD>(
        'PostMessageW',
      ),
      _releaseCapture = _user32
          .lookupFunction<_ReleaseCaptureC, _ReleaseCaptureD>('ReleaseCapture'),
      _getWindowThreadProcessId = _user32
          .lookupFunction<
            _GetWindowThreadProcessIdC,
            _GetWindowThreadProcessIdD
          >('GetWindowThreadProcessId'),
      _getCurrentProcessId = _kernel32
          .lookupFunction<_GetCurrentProcessIdC, _GetCurrentProcessIdD>(
            'GetCurrentProcessId',
          ),
      _dwmSetAttribute = _dwmapi.lookupFunction<_DwmSetC, _DwmSetD>(
        'DwmSetWindowAttribute',
      );

  final _FindWindowWD _findWindow;
  final _ShowWindowD _showWindow;
  final _IsZoomedD _isZoomed;
  final _SendMessageD _sendMessage;
  final _PostMessageD _postMessage;
  final _ReleaseCaptureD _releaseCapture;
  final _GetWindowThreadProcessIdD _getWindowThreadProcessId;
  final _GetCurrentProcessIdD _getCurrentProcessId;
  final _DwmSetD _dwmSetAttribute;
}

_Api? _api;
_Api get _w => _api ??= _Api();

/// The window title the runner creates (`windows/runner/main.cpp`).
const String kWindowTitle = 'SheepPing';

int _handle = -1;

/// Locates this process's Flutter window by title. Returns 0 when not found.
int _findWindowHandle() {
  if (_handle > 0) return _handle;
  final Pointer<Utf16> title = kWindowTitle.toNativeUtf16();
  try {
    final hwnd = _w._findWindow(nullptr, title);
    if (hwnd == 0) return 0;
    // Guard against picking up a different app that happens to share the title.
    final Pointer<Uint32> pid = calloc<Uint32>();
    try {
      _w._getWindowThreadProcessId(hwnd, pid);
      if (pid.value != _w._getCurrentProcessId()) return 0;
    } finally {
      calloc.free(pid);
    }
    _handle = hwnd;
    return hwnd;
  } finally {
    calloc.free(title);
  }
}

/// Rounds the corners and darkens the frame. Safe to call repeatedly.
///
/// The caption itself is removed by the runner, not here: clearing
/// `WS_CAPTION` from Dart left the top resize border behind as a dark band
/// above the toolbar, and also cost the window Snap Layouts and the minimise
/// animation.
void applyBorderless() {
  final hwnd = _findWindowHandle();
  if (hwnd == 0) return;

  // DWMWCP_ROUND (2) — ignored on Windows 10 and earlier.
  final Pointer<Int32> corner = calloc<Int32>();
  try {
    corner.value = 2;
    _w._dwmSetAttribute(hwnd, _dwmwaWindowCornerPreference, corner, 4);

    // The window still keeps its resize frame, and DWM paints that frame in the
    // *system* theme's colour — a light band around a dark window when Windows
    // runs in light mode. The app is night mode only, so force the dark frame.
    corner.value = 1;
    _w._dwmSetAttribute(hwnd, _dwmwaUseImmersiveDarkMode, corner, 4);
  } finally {
    calloc.free(corner);
  }
}

/// Begins a native window move. Call on drag start over the title bar.
void startDrag() {
  final hwnd = _findWindowHandle();
  if (hwnd == 0) return;
  _w._releaseCapture();
  _w._sendMessage(hwnd, _wmNcLButtonDown, _htCaption, 0);
}

/// Begins a native resize from [hitTest] (one of [htTop], [htTopLeft],
/// [htTopRight]). Call on drag start over the matching edge strip.
void startResize(int hitTest) {
  final hwnd = _findWindowHandle();
  if (hwnd == 0) return;
  _w._releaseCapture();
  _w._sendMessage(hwnd, _wmNcLButtonDown, hitTest, 0);
}

/// The top-level window handle, or 0. Used to own modal system dialogs.
int windowHandle() => _findWindowHandle();

void minimize() {
  final hwnd = _findWindowHandle();
  if (hwnd != 0) _w._showWindow(hwnd, _swMinimize);
}

bool isMaximized() {
  final hwnd = _findWindowHandle();
  if (hwnd == 0) return false;
  return _w._isZoomed(hwnd) != 0;
}

void toggleMaximize() {
  final hwnd = _findWindowHandle();
  if (hwnd == 0) return;
  _w._showWindow(hwnd, _w._isZoomed(hwnd) != 0 ? _swRestore : _swMaximize);
}

void close() {
  final hwnd = _findWindowHandle();
  if (hwnd != 0) _w._postMessage(hwnd, _wmClose, 0, 0);
}
