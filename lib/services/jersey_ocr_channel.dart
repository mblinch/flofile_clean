import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One text token from on-device Vision OCR (jersey digits or name-like words).
class JerseyOcrHit {
  const JerseyOcrHit({
    required this.text,
    required this.confidence,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.jerseyTone,
    this.jerseyRed,
    this.jerseyGreen,
    this.jerseyBlue,
    this.region,
    this.onPerson = false,
  });

  final String text;
  final double confidence;

  /// Vision-normalized box (origin bottom-left, 0–1).
  final double x;
  final double y;
  final double width;
  final double height;

  /// Fabric luminance under the read: `dark`, `light`, or null when unknown.
  /// Used to tell home from away when both rosters share a number.
  final String? jerseyTone;

  /// Fabric colour near the median luminance, 0–1. Null when the torso
  /// could not be sampled.
  final double? jerseyRed;
  final double? jerseyGreen;
  final double? jerseyBlue;

  Color? get fabricColor {
    final r = jerseyRed;
    final g = jerseyGreen;
    final b = jerseyBlue;
    if (r == null || g == null || b == null) return null;
    int byte(double channel) => (channel.clamp(0.0, 1.0) * 255).round();
    return Color.fromARGB(255, byte(r), byte(g), byte(b));
  }

  /// Where on the player this came from: `torso`, `sleeve`, `helmet`,
  /// `body`, `loupe`, or null for frame-level passes.
  final String? region;

  /// True when the read came from a detected person crop (not boards/crowd).
  final bool onPerson;

  bool get isDarkJersey => jerseyTone == 'dark';
  bool get isLightJersey => jerseyTone == 'light';

  factory JerseyOcrHit.fromMap(Map<dynamic, dynamic> map) {
    final box = map['boundingBox'];
    final boxMap = box is Map ? box : const <dynamic, dynamic>{};
    final tone = (map['jerseyTone'] as String? ?? '').trim().toLowerCase();
    final region = (map['region'] as String? ?? '').trim().toLowerCase();
    double? channel(String key) {
      final value = (map[key] as num?)?.toDouble();
      if (value == null || value.isNaN) return null;
      return value.clamp(0.0, 1.0);
    }

    return JerseyOcrHit(
      text: (map['text'] as String? ?? '').trim(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      x: (boxMap['x'] as num?)?.toDouble() ?? 0,
      y: (boxMap['y'] as num?)?.toDouble() ?? 0,
      width: (boxMap['width'] as num?)?.toDouble() ?? 0,
      height: (boxMap['height'] as num?)?.toDouble() ?? 0,
      jerseyTone: tone == 'dark' || tone == 'light' ? tone : null,
      jerseyRed: channel('jerseyRed'),
      jerseyGreen: channel('jerseyGreen'),
      jerseyBlue: channel('jerseyBlue'),
      region: region.isEmpty ? null : region,
      onPerson: map['onPerson'] == true,
    );
  }
}

/// Normalized Vision ROI (origin bottom-left).
class JerseyOcrRegion {
  const JerseyOcrRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, double> toMap() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// macOS Vision text OCR via platform channel. No-op elsewhere.
class JerseyOcrChannel {
  JerseyOcrChannel._();

  static const MethodChannel _channel = MethodChannel(
    'caption_writer/jersey_ocr',
  );

  /// High enough for small / arched jersey glyphs.
  static const int defaultMaxPixelDimension = 2800;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Aborts the in-flight background pre-scan. Frame and loupe scans continue.
  static Future<void> cancelPrescan() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelPrescan');
    } catch (e, st) {
      debugPrint('JerseyOcrChannel.cancelPrescan failed: $e\n$st');
    }
  }

  /// Returns text hits (digits + names), highest confidence / spatial score first.
  ///
  /// [customWords] biases Vision toward roster last names / jersey numbers.
  /// [regionOfInterest] limits the scan (loupe / subject crop).
  /// [sport] tunes ROI bias (e.g. hockey scans helmet stickers).
  /// [prescan] runs on the native background lane: lower priority, and it
  /// never cancels (or is cancelled by) the frame or loupe scans.
  static Future<List<JerseyOcrHit>> recognize({
    required String path,
    int maxPixelDimension = defaultMaxPixelDimension,
    List<String> customWords = const [],
    JerseyOcrRegion? regionOfInterest,
    String sport = '',
    bool prescan = false,
  }) async {
    if (!supported || path.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('recognize', {
        'path': path,
        'maxPixelDimension': maxPixelDimension,
        if (customWords.isNotEmpty) 'customWords': customWords,
        if (regionOfInterest != null)
          'regionOfInterest': regionOfInterest.toMap(),
        if (sport.trim().isNotEmpty) 'sport': sport.trim().toLowerCase(),
        if (prescan) 'prescan': true,
      });
      if (raw == null || raw.isEmpty) return const [];
      return [
        for (final item in raw)
          if (item is Map) JerseyOcrHit.fromMap(item),
      ];
    } catch (e, st) {
      debugPrint('JerseyOcrChannel.recognize failed: $e\n$st');
      return const [];
    }
  }
}
