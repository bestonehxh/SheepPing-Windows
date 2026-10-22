/// Web preview stand-in for the native save dialog: browsers have no
/// `comdlg32`, so the call is reported as cancelled.
library;

String? saveFileDialog({
  required String suggestedName,
  String title = 'Save as CSV',
  String extension = 'csv',
  String filterLabel = 'CSV file',
}) =>
    null;

/// The web preview has no file system target; report as cancelled.
Future<String?> saveTextFile({
  required String suggestedName,
  required String content,
  String title = 'Save as CSV',
}) async =>
    null;
