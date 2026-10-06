import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/color_managed_preview_channel.dart';

/// One decode target for [OrientedImageBytes.prefetchAll].
class OrientedPrefetchJob {
  const OrientedPrefetchJob({
    required this.path,
    required this.maxWidth,
  });

  final String path;
  final int maxWidth;
}

/// Decodes a photo and applies EXIF orientation so pixels match how the shot
/// should be displayed (Lightroom, Finder, etc.).
///
/// Thumbs and large previews live in **separate** LRU budgets so scrolling the
/// filmstrip to the bottom keeps its thumbs even after big preview decodes.
class OrientedImageBytes {
  OrientedImageBytes._();

  static final LinkedHashMap<String, Uint8List> _thumbCache = LinkedHashMap();
  static final LinkedHashMap<String, Uint8List> _previewCache = LinkedHashMap();
  static int _thumbCacheBytes = 0;
  static int _previewCacheBytes = 0;

  static const _cacheVersion = 'macos-ci-srgb-v2';
  /// Grid thumbs — sized for a full shoot (~2–4k frames at ~80KB each).
  static const _maxThumbCacheBytes = 384 * 1024 * 1024;
  /// Main preview / loupe — independent of the thumb budget.
  static const _maxPreviewCacheBytes = 256 * 1024 * 1024;
  /// Parallel native/JPEG decodes. Higher fills the thumb strip faster.
  static const _maxDecodes = 8;
  static int _decodesInFlight = 0;
  static final List<Completer<void>> _decodeWaiters = [];

  /// Main Caption V2 preview decode width.
  static const int previewMaxWidth = 2200;

  /// Loupe hold / 100% view — `0` means no downscale (full pixels).
  static const int loupeMaxWidth = 0;

  /// Default grid thumb width (3-column layout).
  static const int thumbMaxWidth = 320;

  /// Entries at or below this width use the thumb cache (never evicted by
  /// preview loads).
  static const int _thumbBudgetMaxWidth = 400;

  static bool _isThumbSize(int? maxWidth) =>
      maxWidth != null && maxWidth > 0 && maxWidth <= _thumbBudgetMaxWidth;

  static String _cacheKey(String path, int? maxWidth) =>
      '$_cacheVersion|$path|${maxWidth ?? 0}';

  static Uint8List? _readCache(String key, {required bool thumb}) {
    final map = thumb ? _thumbCache : _previewCache;
    final hit = map.remove(key);
    if (hit == null) return null;
    map[key] = hit;
    return hit;
  }

  static void _writeCache(String key, Uint8List bytes, {required bool thumb}) {
    final map = thumb ? _thumbCache : _previewCache;
    final old = map.remove(key);
    if (old != null) {
      if (thumb) {
        _thumbCacheBytes -= old.lengthInBytes;
      } else {
        _previewCacheBytes -= old.lengthInBytes;
      }
    }
    map[key] = bytes;
    if (thumb) {
      _thumbCacheBytes += bytes.lengthInBytes;
      while (_thumbCacheBytes > _maxThumbCacheBytes && map.isNotEmpty) {
        final evicted = map.remove(map.keys.first);
        if (evicted != null) _thumbCacheBytes -= evicted.lengthInBytes;
      }
    } else {
      _previewCacheBytes += bytes.lengthInBytes;
      while (_previewCacheBytes > _maxPreviewCacheBytes && map.isNotEmpty) {
        final evicted = map.remove(map.keys.first);
        if (evicted != null) _previewCacheBytes -= evicted.lengthInBytes;
      }
    }
  }

  /// Sync cache peek (no decode). Uses file mtime so keys match [load].
  static Uint8List? peekCached(String path, {int? maxWidth}) {
    try {
      final mod = File(path).lastModifiedSync();
      final key = '${_cacheKey(path, maxWidth)}|${mod.millisecondsSinceEpoch}';
      return _readCache(key, thumb: _isThumbSize(maxWidth));
    } catch (_) {
      return null;
    }
  }

  /// True when this path+size is already warm (no disk/decode needed).
  static bool isCached(String path, {int? maxWidth}) =>
      peekCached(path, maxWidth: maxWidth) != null;

  /// PNG/JPEG bytes suitable for [Image.memory]; cached per [path] + [maxWidth] + mtime.
  ///
  /// [priority] jumps the decode queue. Defaults to true for large/preview
  /// sizes and for explicit UI loads; background prefetch passes false.
  static Future<Uint8List?> load(
    String path, {
    int? maxWidth,
    bool? priority,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final mod = await file.lastModified();
    final key = '${_cacheKey(path, maxWidth)}|${mod.millisecondsSinceEpoch}';
    final thumb = _isThumbSize(maxWidth);
    final hit = _readCache(key, thumb: thumb);
    if (hit != null) return hit;

    final isPriority = priority ??
        (maxWidth == null || maxWidth <= 0 || maxWidth >= 800);
    await _acquireDecode(priority: isPriority);
    try {
      final again = _readCache(key, thumb: thumb);
      if (again != null) return again;
      return await _decodeUncached(file, path, maxWidth, key, thumb: thumb);
    } finally {
      _releaseDecode();
    }
  }

  /// Decode [jobs] into the cache without returning bytes.
  ///
  /// Stops early when [isCurrent] returns false (folder/index generation).
  /// Prefetch jobs yield to UI [load]s (priority: false).
  static Future<void> prefetchAll(
    List<OrientedPrefetchJob> jobs, {
    required bool Function() isCurrent,
  }) async {
    if (jobs.isEmpty) return;
    // Kick off in waves so we don't create thousands of waiters at once.
    const wave = 24;
    for (var i = 0; i < jobs.length; i += wave) {
      if (!isCurrent()) return;
      final end = (i + wave).clamp(0, jobs.length);
      final slice = jobs.sublist(i, end);
      await Future.wait([
        for (final job in slice)
          load(job.path, maxWidth: job.maxWidth, priority: false),
      ]);
    }
  }

  static Future<void> _acquireDecode({required bool priority}) {
    if (_decodesInFlight < _maxDecodes) {
      _decodesInFlight++;
      return Future.value();
    }
    final waiter = Completer<void>();
    if (priority) {
      _decodeWaiters.insert(0, waiter);
    } else {
      _decodeWaiters.add(waiter);
    }
    return waiter.future;
  }

  static void _releaseDecode() {
    if (_decodeWaiters.isNotEmpty) {
      _decodeWaiters.removeAt(0).complete();
      return;
    }
    _decodesInFlight--;
  }

  static Future<Uint8List?> _decodeUncached(
    File file,
    String path,
    int? maxWidth,
    String key, {
    required bool thumb,
  }) async {
    // `0` / negative = full resolution (no downscale). Null defaults to 4096.
    final fullRes = maxWidth != null && maxWidth <= 0;
    final maxPx = fullRes
        ? 16384
        : (maxWidth != null && maxWidth > 0 ? maxWidth : 4096);

    if (ColorManagedPreviewChannel.supported) {
      try {
        final png = await ColorManagedPreviewChannel.decodePng(
          path: path,
          maxPixelDimension: maxPx,
        );
        if (png != null && png.isNotEmpty) {
          _writeCache(key, png, thumb: thumb);
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

      if (!fullRes &&
          maxWidth != null &&
          maxWidth > 0 &&
          oriented.width > maxWidth) {
        oriented = img.copyResize(
          oriented,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
      }

      final out = Uint8List.fromList(
        img.encodeJpg(oriented, quality: thumb ? 82 : 88),
      );
      _writeCache(key, out, thumb: thumb);
      return out;
    } catch (_) {
      return null;
    }
  }

  static void evict(String path) {
    final prefix = '$_cacheVersion|$path|';
    void sweep(LinkedHashMap<String, Uint8List> map, void Function(int) debit) {
      map.removeWhere((key, value) {
        if (!key.startsWith(prefix)) return false;
        debit(value.lengthInBytes);
        return true;
      });
    }

    sweep(_thumbCache, (n) => _thumbCacheBytes -= n);
    sweep(_previewCache, (n) => _previewCacheBytes -= n);
  }
}
