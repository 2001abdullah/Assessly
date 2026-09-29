import 'dart:io';

/// Turns OMR engine / network errors into advice the user can act on.
String friendlyScanError(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '');
  final m = raw.toLowerCase();
  if (m.contains('corner registration')) {
    return 'We could not see all four corner squares. Keep the whole sheet '
        'inside the frame and do not cover the corners.';
  }
  if (m.contains('cut off')) {
    return 'Part of the sheet is cut off at the edge of the photo. Step back '
        'a little so the whole sheet is visible.';
  }
  if (m.contains('timing marks')) {
    return 'We could not lock onto the black marks along the sheet edges. '
        'Flatten the sheet, use even light, and check that this is the sheet '
        'printed for this exam.\n\n($raw)';
  }
  if (m.contains('could not read image')) {
    return 'The photo could not be opened. Please take it again.';
  }
  if (error is SocketException ||
      m.contains('too long') ||
      m.contains('connection')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return raw;
}
