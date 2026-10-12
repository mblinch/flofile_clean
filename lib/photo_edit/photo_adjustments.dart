import 'dart:math' as math;
import 'dart:typed_data';

import 'photo_tone_base.dart';

/// Live photo grade in linear light.
///
/// JPEG pixels are display-referred sRGB. Each stage below is its own
/// function. Sliders at 0 leave the pixel unchanged. Processing order is
/// fixed: white balance, exposure, contrast, whites and blacks, then local
/// shadows and highlights. Gamma is applied only when encoding the result.
/// `shaders/photo_grade.frag` repeats this math.
class PhotoAdjustments {
  const PhotoAdjustments({
    this.exposure = 0,
    this.contrast = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.whites = 0,
    this.blacks = 0,
    this.temperature = 0,
    this.tint = 0,
  });

  static const neutral = PhotoAdjustments();

  /// Stops, −5…5. Linear multiply by 2^EV, then a highlight shoulder.
  final double exposure;

  /// −1…1, shown as −100…100. Luminance S-curve around 18% gray.
  final double contrast;

  /// −1…1. Local shadow lift. Pure black stays black.
  final double shadows;

  /// −1…1. Local highlight recovery. Pure white stays white.
  final double highlights;

  /// −1…1. Moves the white end of the tone curve.
  final double whites;

  /// −1…1. Moves the black end of the tone curve.
  final double blacks;

  /// −1…1. Negative is cooler (toward 50000K), positive is warmer (toward 2000K).
  final double temperature;

  /// −1…1, shown as −100…100. Negative is green, positive is magenta.
  final double tint;

  bool get needsLocalTone =>
      shadows.abs() >= 0.0005 || highlights.abs() >= 0.0005;

  bool get affectsToneBase =>
      exposure.abs() >= 0.0005 ||
      contrast.abs() >= 0.0005 ||
      whites.abs() >= 0.0005 ||
      blacks.abs() >= 0.0005 ||
      temperature.abs() >= 0.0005 ||
      tint.abs() >= 0.0005 ||
      needsLocalTone;

  bool get isNeutral => !affectsToneBase;

  PhotoAdjustments copyWith({
    double? exposure,
    double? contrast,
    double? shadows,
    double? highlights,
    double? whites,
    double? blacks,
    double? temperature,
    double? tint,
  }) {
    return PhotoAdjustments(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      shadows: shadows ?? this.shadows,
      highlights: highlights ?? this.highlights,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
    );
  }
}

class GradeRgb {
  const GradeRgb(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  double get luma => _luma(r, g, b);
}

double srgbToLinear(double c) {
  if (c <= 0.04045) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double linearToSrgb(double c) {
  if (c <= 0) return 0;
  if (c <= 0.0031308) return 12.92 * c;
  return 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

double gradeSmoothstep(double edge0, double edge1, double x) {
  final span = edge1 - edge0;
  if (span == 0) return x < edge0 ? 0 : 1;
  final t = ((x - edge0) / span).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Slider −1…1 to kelvin. 0 is 6500K. The curve is flatter around the middle
/// so daylight sits on a finer part of the slider than the extremes.
double temperatureKelvin(double slider) {
  final t = slider.clamp(-1.0, 1.0);
  if (t.abs() < 0.0005) return 6500;
  final curved = t.sign * math.pow(t.abs(), 1.6).toDouble();
  if (curved >= 0) {
    return 6500 * math.pow(2000 / 6500, curved).toDouble();
  }
  return 6500 * math.pow(50000 / 6500, -curved).toDouble();
}

/// Tanner Helland blackbody RGB, divided by 255 so channels are 0…1.
(double, double, double) kelvinToRgb(double kelvin) {
  final k = kelvin.clamp(1000.0, 50000.0) / 100.0;
  final r = k <= 66
      ? 1.0
      : (1.2929361860620923 * math.pow(k - 60, -0.1332047592))
          .toDouble()
          .clamp(0.0, 1.0);
  final g = (k <= 66
          ? 0.3900815787690196 * math.log(k) - 0.6318414437886275
          : 1.129890860895294 * math.pow(k - 60, -0.0755148492))
      .toDouble()
      .clamp(0.0, 1.0);
  final b = k >= 66
      ? 1.0
      : k <= 19
          ? 0.0
          : (0.543206789110196 * math.log(k - 10) - 1.19625408914)
              .toDouble()
              .clamp(0.0, 1.0);
  return (r, g, b);
}

(double, double, double) _linearSrgbToXyz(double r, double g, double b) {
  return (
    0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
    0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
    0.0193339 * r + 0.1191920 * g + 0.9503041 * b,
  );
}

(double, double, double) _xyzToLinearSrgb(double x, double y, double z) {
  return (
    3.2404542 * x + -1.5371385 * y + -0.4985314 * z,
    -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
    0.0556434 * x + -0.2040259 * y + 1.0572252 * z,
  );
}

/// White-balance gains in linear light. Temperature follows the blackbody
/// locus. Tint shifts CIE y, the green–magenta axis, then both are converted
/// back to per-channel gains and normalized so a gray does not change exposure.
(double, double, double) whiteBalanceGain(double temperature, double tint) {
  if (temperature.abs() < 0.0005 && tint.abs() < 0.0005) return (1, 1, 1);
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;
  if (temperature.abs() >= 0.0005) {
    final ill = kelvinToRgb(temperatureKelvin(temperature));
    final d65 = kelvinToRgb(6500);
    r = ill.$1 / d65.$1;
    g = ill.$2 / d65.$2;
    b = ill.$3 / d65.$3;
  }
  if (tint.abs() >= 0.0005) {
    final xyz = _linearSrgbToXyz(r, g, b);
    final sum = xyz.$1 + xyz.$2 + xyz.$3;
    if (sum > 1e-8) {
      final chromaX = xyz.$1 / sum;
      final chromaY =
          (xyz.$2 / sum - tint * 0.045).clamp(0.04, 0.75);
      const y = 1.0;
      final bigX = chromaX * y / chromaY;
      final bigZ = (1 - chromaX - chromaY) * y / chromaY;
      final rgb = _xyzToLinearSrgb(bigX, y, bigZ);
      r = rgb.$1;
      g = rgb.$2;
      b = rgb.$3;
    }
  }
  final y = _luma(r, g, b);
  if (y.abs() < 1e-8) return (1, 1, 1);
  return (r / y, g / y, b / y);
}

/// 2^EV. Positive exposure rolls highlights into the range below 1.
/// Zero exposure, and any value that stays at or below 1, is a plain multiply.
double exposeLinear(double x, double ev) {
  if (ev.abs() < 0.0005) return x;
  final gained = x * math.pow(2, ev).toDouble();
  if (ev < 0 || gained <= 0.80) return gained;
  const knee = 0.80;
  const room = 1 - knee;
  final over = gained - knee;
  return knee + room * (over / (over + room));
}

/// S-curve on linear luminance. The pivot is 18% gray. Strength fades in the
/// deep shadows and highlights so the curve is an S, not a pure power.
double _tanh(double x) {
  final c = x.clamp(-8.0, 8.0);
  final e = math.exp(2 * c);
  return (e - 1) / (e + 1);
}

double contrastCurve(double y, double amount) {
  if (amount.abs() < 0.0005 || y <= 0) return y;
  const pivot = 0.18;
  final stops = math.log(y / pivot) / math.ln2;
  final shaped = stops + amount * 1.15 * _tanh(stops);
  return math.max(0.0, pivot * math.pow(2, shaped).toDouble());
}

/// Soft knees on the darkest and brightest few percent of linear light.
/// Middle gray is outside both knees.
double whitesBlacksCurve(double y, double whites, double blacks) {
  if (whites.abs() < 0.0005 && blacks.abs() < 0.0005) return y;
  var x = y;
  if (blacks.abs() >= 0.0005) {
    const toeEnd = 0.02;
    final knee = 1 - gradeSmoothstep(0, toeEnd, x);
    if (blacks > 0) {
      x = x + blacks * 0.045 * knee;
    } else {
      x = x * (1 + blacks * knee);
    }
  }
  if (whites.abs() >= 0.0005) {
    const start = 0.55;
    final knee = gradeSmoothstep(start, 1, x);
    x = x + whites * 0.40 * knee;
  }
  return x < 0 ? 0 : x;
}

double _luma(double r, double g, double b) =>
    0.2126729 * r + 0.7151522 * g + 0.0721750 * b;

/// Regional mask from the blurred base. 1 in a dark area, 0 by mid gray.
double _shadowMask(double linearBase) {
  final display = linearToSrgb(linearBase.clamp(0.0, 1.0));
  final weight = 1 - gradeSmoothstep(0.05, 0.62, display);
  return math.pow(weight.clamp(0.0, 1.0), 1.05).toDouble();
}

/// Soft toe. Black stays black, and the lift fades out before mid gray.
double _shadowTone(double linearY, double amount) {
  final display = linearToSrgb(linearY.clamp(0.0, 1.0));
  final weight = math
      .pow(1 - gradeSmoothstep(0.0, 0.58, display), 1.15)
      .toDouble();
  final next = amount >= 0
      ? display + amount * 0.34 * weight * (1 - display)
      : display * (1 + amount * 0.75 * weight);
  return srgbToLinear(next.clamp(0.0, 1.0));
}

double _highlightMask(double linearBase) {
  if (linearBase > 1) return math.exp(-(linearBase - 1));
  final display = linearToSrgb(linearBase.clamp(0.0, 1.0));
  final rise = gradeSmoothstep(0.55, 0.82, display);
  final hold = 1 - gradeSmoothstep(0.94, 1.0, display);
  return rise * hold;
}

double _highlightTone(double linearY, double amount) {
  final display = linearToSrgb(linearY.clamp(0.0, 1.0));
  if (amount >= 0) {
    final weight = gradeSmoothstep(0.45, 0.90, display);
    final next = display + amount * 0.25 * weight * (1 - display);
    return srgbToLinear(next.clamp(0.0, 1.0));
  }
  final weight = gradeSmoothstep(0.50, 0.88, display) *
      (1 - gradeSmoothstep(0.96, 1.0, display));
  final next = display + amount * 0.28 * weight;
  return srgbToLinear(next.clamp(0.0, 1.0));
}

/// Local shadows and highlights, in the Camera Raw sense.
///
/// The guided-filter [baseLuma] only decides which region is dark or bright.
/// The toe itself runs on this pixel, so texture is not rebuilt from a
/// low-resolution residual. When [baseLuma] is omitted the pixel is its own
/// base, which is exact on a flat field.
GradeRgb applyShadowsHighlights(
  double r,
  double g,
  double b,
  PhotoAdjustments a, {
  double? baseLuma,
}) {
  if (!a.needsLocalTone) return GradeRgb(r, g, b);
  final y = _luma(r, g, b);
  if (y < 1e-8) return GradeRgb(r, g, b);
  final base = baseLuma ?? y;
  var tone = y;
  if (a.shadows.abs() >= 0.0005) {
    final curved = _shadowTone(tone, a.shadows);
    tone += (curved - tone) * _shadowMask(base);
  }
  if (a.highlights.abs() >= 0.0005) {
    final curved = _highlightTone(tone, a.highlights);
    tone += (curved - tone) * _highlightMask(base);
  }
  final scale = (tone / y).clamp(0.05, 8.0);
  return GradeRgb(r * scale, g * scale, b * scale);
}

GradeRgb _scaleToLuma(double r, double g, double b, double newY) {
  final y = _luma(r, g, b);
  if (y < 1e-8) return GradeRgb(r, g, b);
  final scale = newY / y;
  return GradeRgb(r * scale, g * scale, b * scale);
}

/// Linear-light grade. Channels are linear. Gamma is not applied here.
GradeRgb gradeLinearRgb(
  double r,
  double g,
  double b,
  PhotoAdjustments a, {
  double? baseLuma,
}) {
  if (a.isNeutral) return GradeRgb(r, g, b);
  final wb = whiteBalanceGain(a.temperature, a.tint);
  var lr = exposeLinear(r * wb.$1, a.exposure);
  var lg = exposeLinear(g * wb.$2, a.exposure);
  var lb = exposeLinear(b * wb.$3, a.exposure);
  final y = whitesBlacksCurve(
    contrastCurve(_luma(lr, lg, lb), a.contrast),
    a.whites,
    a.blacks,
  );
  final toned = _scaleToLuma(lr, lg, lb, y);
  return applyShadowsHighlights(
    toned.r,
    toned.g,
    toned.b,
    a,
    baseLuma: baseLuma,
  );
}

/// Grades one sRGB pixel. Channels are 0…1. Pass [baseLuma] when shadows or
/// highlights are active so the local base matches [lumaBaseForDisplayRgb].
GradeRgb gradeDisplayRgb(
  double r,
  double g,
  double b,
  PhotoAdjustments a, {
  double? baseLuma,
}) {
  if (a.isNeutral) return GradeRgb(r, g, b);
  final linear = gradeLinearRgb(
    srgbToLinear(r),
    srgbToLinear(g),
    srgbToLinear(b),
    a,
    baseLuma: baseLuma,
  );
  return GradeRgb(
    linearToSrgb(linear.r).clamp(0.0, 1.0),
    linearToSrgb(linear.g).clamp(0.0, 1.0),
    linearToSrgb(linear.b).clamp(0.0, 1.0),
  );
}

/// Guided-filter luma of [rgb] (tight sRGB bytes) after every stage except
/// the local shadow and highlight mix.
Float32List lumaBaseForDisplayRgb(
  Uint8List rgb,
  int width,
  int height,
  PhotoAdjustments adjustments,
) {
  final n = width * height;
  final luma = Float32List(n);
  final prefix = adjustments.copyWith(shadows: 0, highlights: 0);
  for (var i = 0; i < n; i++) {
    final o = i * 3;
    if (o + 2 >= rgb.length) break;
    final linear = gradeLinearRgb(
      srgbToLinear(rgb[o] / 255.0),
      srgbToLinear(rgb[o + 1] / 255.0),
      srgbToLinear(rgb[o + 2] / 255.0),
      prefix,
    );
    luma[i] = linear.luma;
  }
  return guidedLumaBase(luma, width, height);
}
