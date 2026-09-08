import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/color_managed_preview_channel.dart';

/// Decodes a photo and applies EXIF orientation so pixels match how the shot
/// should be displayed (Lightroom, Finder, etc.).
class OrientedImageBytes {
  OrientedImageBytes._();

  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static int _cacheBytes = 0;

  static const _cacheVersion = 'macos-ci-srgb-v2';
  static const _maxCacheBytes = 32 * 1024 * 1024;

  static String _cacheKey(String path, int? maxWidth) =>
      '$_cacheVersion|$path|${maxWidth ?? 0}';

  static Uint8List? _readCache(String key) {
    final hit = _cache.remove(key);
    if (hit == null) return null;
    _cache[key] = hit;
    return hit;
  }

  static void _writeCache(String key, Uint8List bytes) {
    final old = _cache.remove(key);
    if (old != null) _cacheBytes -= old.lengthInBytes;
    _cache[key] = bytes;
    _cacheBytes += bytes.lengthInBytes;
    while (_cacheBytes > _maxCacheBytes && _cache.isNotEmpty) {
      final evicted = _cache.remove(_cache.keys.first);
      if (evicted != null) _cacheBytes -= evicted.lengthInBytes;
    }
  }

  /// PNG/JPEG bytes suitable for [Image.memory]; cached per [path] + [maxWidth] + mtime.
  static Future<Uint8List?> load(
    String path, {
    int? maxWidth,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final mod = await file.lastModified();
    final key = '${_cacheKey(path, maxWidth)}|${mod.millisecondsSinceEpoch}';
    final hit = _readCache(key);
    if (hit != null) return hit;

    final maxPx = maxWidth != null && maxWidth > 0 ? maxWidth : 4096;

    if (ColorManagedPreviewChannel.supported) {
      try {
        final png = await ColorManagedPreviewChannel.decodePng(
          path: path,
          maxPixelDimension: maxPx,
        );
        if (png != null && png.isNotEmpty) {
          _writeCache(key, png);
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
      _writeCache(key, out);
      return out;
    } catch (_) {
      return null;
    }
  }

  static void evict(String path) {
    final prefix = '$_cacheVersion|$path|';
    _cache.removeWhere((key, value) {
      if (!key.startsWith(prefix)) return false;
      _cacheBytes -= value.lengthInBytes;
      return true;
    });
  }
}
