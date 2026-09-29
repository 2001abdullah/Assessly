import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Downloads with [load], lets the user pick where to save, and reports the
/// outcome in a snackbar. Used for CSV reports and PDFs.
Future<void> exportFile(
  BuildContext context, {
  required Future<List<int>> Function() load,
  required String fileName,
  String dialogTitle = 'Save file',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = Uint8List.fromList(await load());
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
    if (path != null) {
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}

/// Snackbar with an error's message (without the "Exception: " prefix).
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );
}
