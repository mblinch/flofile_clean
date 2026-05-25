import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS: decode via CoreGraphics (ICC / wide gamut → sRGB PNG) so previews match
/// system color-managed apps closer than Flutter’s default JPEG decode.
class ColorManagedPreviewChannel {
  ColorManagedPreviewChannel._();

  static const MethodChannel _channel = MethodChannel(
    'caption_writer/color_managed_preview',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Returns PNG bytes, or null on failure / unsupported platform.
  static Future<Uint8List?> decodePng({
    required String path,
    required int maxPixelDimension,
  }) async {
    if (!supported) return null;
    try {
      final Object? r = await _channel.invokeMethod<dynamic>(
        'decodePng',
        <String, dynamic>{
          'path': path,
          'maxPixelDimension': maxPixelDimension,
        },
      );
      if (r == null) return null;
      if (r is Uint8List) return r;
      if (r is ByteData) return r.buffer.asUint8List();
      return null;
    } catch (_) {
      return null;
    }
  }
}
