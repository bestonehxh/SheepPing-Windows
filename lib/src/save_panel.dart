/// A native "Save as" dialog via `comdlg32!GetSaveFileNameW`.
///
/// `macos_ui` and `window_manager` are the only packages in this project, and
/// `window_manager` was dropped because Flutter needs symlink support (Windows
/// Developer Mode) for plugins. Talking to `comdlg32` through `dart:ffi` keeps
/// the build plugin-free while still giving the app the real Windows file
/// picker that `NSSavePanel` provides on macOS.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final DynamicLibrary _comdlg32 = DynamicLibrary.open('comdlg32.dll');

typedef _GetSaveFileNameWC = Int32 Function(Pointer<Uint8>);
typedef _GetSaveFileNameWD = int Function(Pointer<Uint8>);

final _GetSaveFileNameWD _getSaveFileNameW =
    _comdlg32.lookupFunction<_GetSaveFileNameWC, _GetSaveFileNameWD>(
        'GetSaveFileNameW');

// OPENFILENAMEW is 152 bytes on x64. Field offsets are used directly because
// the struct has a dozen pointer-sized members whose Dart `Struct` mirror would
// be far longer than the handful of values actually needed here.
const int _size = 152;
const int _oStructSize = 0;
const int _oFilter = 24;
const int _oFilterIndex = 44;
const int _oFile = 48;
const int _oMaxFile = 56;
const int _oTitle = 88;
const int _oFlags = 96;
const int _oDefExt = 104;

const int _ofnOverwritePrompt = 0x00000002;
const int _ofnNoChangeDir = 0x00000008;
const int _ofnPathMustExist = 0x00000800;
const int _ofnExplorer = 0x00080000;

const int _maxPath = 1024;

/// Shows the system save dialog. Returns the chosen path, or `null` when the
/// user cancelled (or when the dialog could not be created).
String? saveFileDialog({
  required String suggestedName,
  String title = 'Save as CSV',
  String extension = 'csv',
  String filterLabel = 'CSV file',
}) {
  final filter = calloc<Uint8>(256);
  final titlePtr = calloc<Uint8>(128);
  final extPtr = calloc<Uint8>(16);
  final fileBuf = calloc<Uint16>(_maxPath);
  final buffer = calloc<Uint8>(_size);
  try {
    // Double-null terminated filter: "CSV file\0*.csv\0All files\0*.*\0\0".
    _writeUtf16(filter, '$filterLabel\u0000*.$extension\u0000All files\u0000*.*\u0000\u0000');
    _writeUtf16(titlePtr, '$title\u0000');
    _writeUtf16(extPtr, '$extension\u0000');
    _writeUtf16(fileBuf.cast<Uint8>(), suggestedName);

    final bd = ByteData.sublistView(buffer.asTypedList(_size));
    bd.setUint32(_oStructSize, _size, Endian.little);
    bd.setInt64(_oFilter, filter.address, Endian.little);
    bd.setUint32(_oFilterIndex, 1, Endian.little);
    bd.setInt64(_oFile, fileBuf.address, Endian.little);
    bd.setUint32(_oMaxFile, _maxPath, Endian.little);
    bd.setInt64(_oTitle, titlePtr.address, Endian.little);
    bd.setUint32(
      _oFlags,
      _ofnOverwritePrompt | _ofnPathMustExist | _ofnNoChangeDir | _ofnExplorer,
      Endian.little,
    );
    bd.setInt64(_oDefExt, extPtr.address, Endian.little);

    if (_getSaveFileNameW(buffer) == 0) return null;

    final path = fileBuf.cast<Utf16>().toDartString();
    return path.isEmpty ? null : path;
  } finally {
    calloc.free(filter);
    calloc.free(titlePtr);
    calloc.free(extPtr);
    calloc.free(fileBuf);
    calloc.free(buffer);
  }
}

void _writeUtf16(Pointer<Uint8> dest, String value) {
  final units = value.codeUnits;
  final out = dest.cast<Uint16>();
  for (var i = 0; i < units.length; i++) {
    out[i] = units[i];
  }
}

/// Shows the save dialog, writes [content] and returns the chosen path.
///
/// Returns `null` when the user cancels. Throws when the write fails so the
/// caller can report it instead of flashing a false "Saved!".
Future<String?> saveTextFile({
  required String suggestedName,
  required String content,
  String title = 'Save as CSV',
}) async {
  final path = saveFileDialog(suggestedName: suggestedName, title: title);
  if (path == null) return null;
  await File(path).writeAsString(content);
  return path;
}
