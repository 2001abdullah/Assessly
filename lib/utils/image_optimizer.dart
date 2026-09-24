import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Shrinks big photos (typically gallery picks from 12-50 MP cameras) before
/// they are uploaded.
///
/// Why 2400 px is plenty: the backend warps the sheet to 200 dpi (about
/// 1654 x 2339 px) for reading, and tests showed answers read 100% correctly
/// from photos as small as 800 px wide. Camera captures from the in-app scanner
/// are already ~1080p and are passed through untouched.
class ImageOptimizer {
  ImageOptimizer._();

  /// Files at or below this size are uploaded as they are.
  static const int skipBelowBytes = 2500000;

  /// Longest side after downscaling.
  static const int maxLongEdge = 2400;

  static const int jpegQuality = 88;

  /// Returns a file that is safe and quick to upload. Falls back to [source]
  /// if anything goes wrong, so scanning is never blocked by optimisation.
  static Future<File> prepareForUpload(File source) async {
    try {
      if (await source.length() <= skipBelowBytes) return source;

      final bytes = await source.readAsBytes();
      final Uint8List? out = await compute(_downscale, <String, Object>{
        'bytes': bytes,
        'maxEdge': maxLongEdge,
        'quality': jpegQuality,
      });
      if (out == null) return source;

      final target = File(
        '${Directory.systemTemp.path}/assessly_scan_'
        '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await target.writeAsBytes(out, flush: true);
      return target;
    } catch (e) {
      debugPrint('ImageOptimizer: falling back to original file ($e)');
      return source;
    }
  }
}

/// Runs in a background isolate.
Uint8List? _downscale(Map<String, Object> job) {
  final bytes = job['bytes']! as Uint8List;
  final maxEdge = job['maxEdge']! as int;
  final quality = job['quality']! as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Apply EXIF rotation to the pixels so orientation can never be lost.
  var image = img.bakeOrientation(decoded);

  if (math.max(image.width, image.height) > maxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxEdge,
            interpolation: img.Interpolation.average,
          );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
