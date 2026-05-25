import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/color_managed_preview_channel.dart';

/// Decodes a photo and applies EXIF orientation so pixels match how the shot
/// should be displayed (Lightroom, Finder, etc.).
class OrientedImageBytes {
  OrientedImageBytes._();

  static final Map<String, Uint8List> _cache = {};

  static const _cacheVersion = 'macos-ci-srgb-v2';

  static String _cacheKey(String path, int? maxWidth) =>
      '$_cacheVersion|$path|${maxWidth ?? 0}';

  /// PNG/JPEG bytes suitable for [Image.memory]; cached per [path] + [maxWidth] + mtime.
  static Future<Uint8List?> load(
    String path, {
    int? maxWidth,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final mod = await file.lastModified();
    final key = '${_cacheKey(path, maxWidth)}|${mod.millisecondsSinceEpoch}';
    final hit = _cache[key];
    if (hit != null) return hit;

    final maxPx = maxWidth != null && maxWidth > 0 ? maxWidth : 4096;

    if (ColorManagedPreviewChannel.supported) {
      try {
        final png = await ColorManagedPreviewChannel.decodePng(
          path: path,
          maxPixelDimension: maxPx,
        );
        if (png != null && png.isNotEmpty) {
          _cache[key] = png;
          return png;
        }
      } catch (_) {}
    }

    try {
      final raw = await file.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;

      // JPEG decode already bakes EXIF into pixels and clears the tag.
      // Only call [bakeOrientation] when a non-default tag is still present.
      final hasExifOrientation = decoded.exif.imageIfd.hasOrientation &&
          decoded.exif.imageIfd.orientation != null &&
          decoded.exif.imageIfd.orientation != 1;
      var oriented =
          hasExifOrientation ? img.bakeOrientation(decoded) : decoded;

      if (maxWidth != null && maxWidth > 0 && oriented.width > maxWidth) {
        oriented = img.copyResize(
          oriented,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
      }

      final out = Uint8List.fromList(
        img.encodeJpg(oriented, quality: 88),
      );
      _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  static void evict(String path) {
    _cache.removeWhere((k, _) => k.startsWith('$path|'));
  }
}
