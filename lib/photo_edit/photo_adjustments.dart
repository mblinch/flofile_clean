import 'dart:math' as math;
import 'dart:typed_data';

import 'photo_adjust_config.dart';
import 'photo_tone_base.dart';

/// Immutable grade settings. Defaults are all zero (identity).
///
/// Non-exposure sliders are stored as UI units −100…100. Exposure is stops
/// (−5…5). Call [eased] before feeding values into shaders / [gradeLinearRgb].
class PhotoAdjustments {
  const PhotoAdjustments({
    this.temperature = 0,
    this.tint = 0,
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.vibrance = 0,
    this.saturation = 0,
  });

  static const neutral = PhotoAdjustments();

  /// UI −100…100. Positive = warmer.
  final double temperature;

  /// UI −100…100. Positive = magenta (less green).
  final double tint;

  /// Stops −5…5. Linear; not eased.
  final double exposure;

  /// UI −100…100.
  final double contrast;

  /// UI −100…100. Negative darkens bright regions.
  final double highlights;

  /// UI −100…100. Positive lifts dark regions.
  final double shadows;

  /// UI −100…100.
  final double whites;

  /// UI −100…100.
  final double blacks;

  /// UI −100…100. Prefers less-saturated pixels; protects skin hues.
  final double vibrance;

  /// UI −100…100. Uniform saturation mix.
  final double saturation;

  /// Eased −1…1 parameters ready for the shader / CPU grade.
  PhotoGradeParams get eased => PhotoGradeParams.fromUi(this);

  bool get needsLocalTone =>
      shadows.abs() >= 0.05 || highlights.abs() >= 0.05;

  bool get affectsToneBase =>
      temperature.abs() >= 0.05 ||
      tint.abs() >= 0.05 ||
      exposure.abs() >= 0.0005 ||
      contrast.abs() >= 0.05 ||
      whites.abs() >= 0.05 ||
      blacks.abs() >= 0.05 ||
      vibrance.abs() >= 0.05 ||
      saturation.abs() >= 0.05 ||
      needsLocalTone;

  bool get isNeutral => !affectsToneBase;

  /// Prefix stages that affect the local-tone mask (everything before H/S).
  bool get affectsMaskPrefix =>
      temperature.abs() >= 0.05 ||
      tint.abs() >= 0.05 ||
      exposure.abs() >= 0.0005 ||
      contrast.abs() >= 0.05;

  PhotoAdjustments copyWith({
    double? temperature,
    double? tint,
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? vibrance,
    double? saturation,
  }) {
    return PhotoAdjustments(
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      vibrance: vibrance ?? this.vibrance,
      saturation: saturation ?? this.saturation,
    );
  }

  Map<String, double> toPresetJson() => {
        'temperature': temperature,
        'tint': tint,
        'exposure': exposure,
        'contrast': contrast,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'vibrance': vibrance,
        'saturation': saturation,
      };

  factory PhotoAdjustments.fromPresetJson(Map<String, dynamic> json) {
    double read(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return PhotoAdjustments(
      temperature: read('temperature'),
      tint: read('tint'),
      exposure: read('exposure'),
      contrast: read('contrast'),
      highlights: read('highlights'),
      shadows: read('shadows'),
      whites: read('whites'),
      blacks: read('blacks'),
      vibrance: read('vibrance'),
      saturation: read('saturation'),
    );
  }
}

/// Eased −1…1 (exposure still in stops) for the grade math.
class PhotoGradeParams {
  const PhotoGradeParams({
    required this.temperature,
    required this.tint,
    required this.exposure,
    required this.contrast,
    required this.highlights,
    required this.shadows,
    required this.whites,
    required this.blacks,
    required this.vibrance,
    required this.saturation,
  });

  final double temperature;
  final double tint;
  final double exposure;
  final double contrast;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double vibrance;
  final double saturation;

  factory PhotoGradeParams.fromUi(PhotoAdjustments ui) {
    return PhotoGradeParams(
      // ACR Temp/Tint track the slider more linearly than power-eased.
      temperature: (ui.temperature / 100.0).clamp(-1.0, 1.0),
      tint: (ui.tint / 100.0).clamp(-1.0, 1.0),
      exposure: ui.exposure.clamp(
        PhotoAdjustConfig.exposureStopsMin,
        PhotoAdjustConfig.exposureStopsMax,
      ),
      contrast: easeUi(ui.contrast),
      highlights: easeUi(ui.highlights),
      shadows: easeUi(ui.shadows),
      whites: easeUi(ui.whites),
      blacks: easeUi(ui.blacks),
      // ACR Vibrance/Saturation track the slider more linearly than power-eased.
      vibrance: (ui.vibrance / 100.0).clamp(-1.0, 1.0),
      saturation: (ui.saturation / 100.0).clamp(-1.0, 1.0),
    );
  }

  /// Normalize UI −100…100 → −1…1, then pow ease.
  static double easeUi(double ui) {
    final v = (ui / 100.0).clamp(-1.0, 1.0);
    if (v.abs() < 1e-12) return 0;
    return v.sign *
        math.pow(v.abs(), PhotoAdjustConfig.sliderEasePower).toDouble();
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
  // Piecewise sRGB EOTF (not a plain 2.2 power).
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

double _luma(double r, double g, double b) =>
    PhotoAdjustConfig.lumaR * r +
    PhotoAdjustConfig.lumaG * g +
    PhotoAdjustConfig.lumaB * b;

/// Per-channel WB gains, renormalized so overall luminance is preserved.
(double, double, double) whiteBalanceGain(double temperature, double tint) {
  if (temperature.abs() < 1e-8 && tint.abs() < 1e-8) return (1, 1, 1);
  final tempStrength = temperature < 0
      ? PhotoAdjustConfig.tempStrengthNeg
      : PhotoAdjustConfig.tempStrengthPos;
  final tintStrength = tint < 0
      ? PhotoAdjustConfig.tintStrengthNeg
      : PhotoAdjustConfig.tintStrengthPos;
  var r = 1 + tempStrength * temperature;
  var g = 1 - tintStrength * tint;
  var b = 1 - tempStrength * temperature;
  r = math.max(r, 1e-4);
  g = math.max(g, 1e-4);
  b = math.max(b, 1e-4);
  final y = _luma(r, g, b);
  if (y.abs() < 1e-8) return (1, 1, 1);
  return (r / y, g / y, b / y);
}

/// ACR-shaped contrast in log2 space about [PhotoAdjustConfig.contrastPivot].
///
/// Stronger below the pivot than above; amount fades out toward highlights.
double contrastCurve(double y, double amount) {
  if (amount.abs() < 1e-8 || y <= 0) return y;
  final pivot = PhotoAdjustConfig.contrastPivot;
  final stops = math.log(y / pivot) / math.ln2;
  final strength = stops < 0
      ? PhotoAdjustConfig.contrastStrengthLo
      : PhotoAdjustConfig.contrastStrengthHi;
  final fade = 1 -
      gradeSmoothstep(
        PhotoAdjustConfig.contrastFadeLo,
        PhotoAdjustConfig.contrastFadeHi,
        y,
      );
  final shaped = stops * (1 + strength * fade * amount);
  return math.max(0.0, pivot * math.pow(2, shaped).toDouble());
}

/// Soft endpoint push. No hard clamp.
double whitesBlacksCurve(double y, double whites, double blacks) {
  if (whites.abs() < 1e-8 && blacks.abs() < 1e-8) return y;
  var x = y;
  if (blacks.abs() >= 1e-8) {
    final knee = math
        .pow(
          1 - gradeSmoothstep(0, PhotoAdjustConfig.blacksEnd, x),
          PhotoAdjustConfig.blacksMaskPower,
        )
        .toDouble();
    final amount = blacks < 0
        ? PhotoAdjustConfig.blacksAmountNeg
        : PhotoAdjustConfig.blacksAmountPos;
    x = x * math.pow(2, blacks * amount * knee).toDouble();
  }
  if (whites.abs() >= 1e-8) {
    final whW = gradeSmoothstep(
          PhotoAdjustConfig.whitesMaskLo,
          PhotoAdjustConfig.whitesMaskHi,
          x,
        ) *
        (1 -
            gradeSmoothstep(
              PhotoAdjustConfig.whitesFadeLo,
              PhotoAdjustConfig.whitesFadeHi,
              x,
            ));
    x = x *
        math.pow(2, whites * PhotoAdjustConfig.whitesAmount * whW).toDouble();
  }
  return x < 0 ? 0 : x;
}

double softShoulderChannel(double x) {
  const knee = PhotoAdjustConfig.shoulderKnee;
  const room = PhotoAdjustConfig.shoulderRoom;
  if (x <= knee) return x;
  final over = x - knee;
  return knee + over / (1 + over / room);
}

/// Hue-preserving soft clip via the max channel.
GradeRgb softShoulderRgb(double r, double g, double b) {
  final m = math.max(r, math.max(g, b));
  if (m <= PhotoAdjustConfig.shoulderKnee || m < 1e-8) {
    return GradeRgb(r, g, b);
  }
  final m2 = softShoulderChannel(m);
  final s = m2 / m;
  return GradeRgb(r * s, g * s, b * s);
}

GradeRgb _scaleToLuma(double r, double g, double b, double newY) {
  final y = _luma(r, g, b);
  if (y < 1e-8) return GradeRgb(r, g, b);
  final scale = newY / y;
  return GradeRgb(r * scale, g * scale, b * scale);
}

/// Local H/S gain in log space. [mask01] is perceptual 0…1.
GradeRgb applyShadowsHighlights(
  double r,
  double g,
  double b,
  PhotoGradeParams a, {
  required double mask01,
}) {
  if (a.shadows.abs() < 1e-8 && a.highlights.abs() < 1e-8) {
    return GradeRgb(r, g, b);
  }
  final hiW = gradeSmoothstep(
        PhotoAdjustConfig.highlightMaskLo,
        PhotoAdjustConfig.highlightMaskHi,
        mask01,
      ) *
      (1 -
          gradeSmoothstep(
            PhotoAdjustConfig.highlightFadeLo,
            PhotoAdjustConfig.highlightFadeHi,
            mask01,
          ));
  final shW = math.pow(math.max(0.0, 1 - mask01), PhotoAdjustConfig.shadowMaskPower) *
      (1 -
          gradeSmoothstep(
            PhotoAdjustConfig.shadowFadeLo,
            PhotoAdjustConfig.shadowFadeHi,
            mask01,
          ));
  final hiStrength = a.highlights < 0
      ? PhotoAdjustConfig.highlightStrengthNeg
      : PhotoAdjustConfig.highlightStrengthPos;
  final shStrength = a.shadows < 0
      ? PhotoAdjustConfig.shadowStrengthNeg
      : PhotoAdjustConfig.shadowStrengthPos;
  final stops =
      hiW * a.highlights * hiStrength + shW * a.shadows * shStrength;
  if (stops.abs() < 1e-8) return GradeRgb(r, g, b);
  final gain = math.pow(2, stops).toDouble();
  return GradeRgb(r * gain, g * gain, b * gain);
}

double _saturate(double x) => x.clamp(0.0, 1.0);

/// Approximate hue in degrees from linear RGB (HSV hue).
double _hueDegrees(double r, double g, double b) {
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final d = maxC - minC;
  if (d < 1e-8) return 0;
  double h;
  if (maxC == r) {
    h = ((g - b) / d) % 6;
  } else if (maxC == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  if (h < 0) h += 360;
  return h;
}

double _chroma(double r, double g, double b) {
  final y = _luma(r, g, b);
  final dr = r - y;
  final dg = g - y;
  final db = b - y;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

GradeRgb applyVibranceSaturation(
  double r,
  double g,
  double b,
  PhotoGradeParams a,
) {
  if (a.vibrance.abs() < 1e-8 && a.saturation.abs() < 1e-8) {
    return GradeRgb(r, g, b);
  }
  final y = _luma(r, g, b);
  var outR = r;
  var outG = g;
  var outB = b;

  if (a.vibrance.abs() >= 1e-8) {
    final sat = _chroma(r, g, b);
    // Low chroma gets more effect; vivid fades toward floor (0 on +,
    // vibranceChromaFloorNeg on − so ACR still pulls vivid down a bit).
    final fade = gradeSmoothstep(
      PhotoAdjustConfig.vibranceChromaFadeLo,
      PhotoAdjustConfig.vibranceChromaFadeHi,
      sat,
    );
    final floor =
        a.vibrance < 0 ? PhotoAdjustConfig.vibranceChromaFloorNeg : 0.0;
    final lowSatWeight = 1 - (1 - floor) * fade;
    final hue = _hueDegrees(r, g, b);
    var skinDist = (hue - PhotoAdjustConfig.skinHueCenter).abs();
    if (skinDist > 180) skinDist = 360 - skinDist;
    final skin = 1 -
        gradeSmoothstep(
          0,
          PhotoAdjustConfig.skinHueWidth,
          skinDist,
        );
    final skinScale = math.pow(
      PhotoAdjustConfig.skinVibranceScale,
      skin,
    ).toDouble();
    final strength = a.vibrance >= 0
        ? PhotoAdjustConfig.vibranceAmountPos
        : PhotoAdjustConfig.vibranceAmountNeg;
    final amount = a.vibrance * strength * lowSatWeight * skinScale;
    outR = y + (outR - y) * (1 + amount);
    outG = y + (outG - y) * (1 + amount);
    outB = y + (outB - y) * (1 + amount);
  }

  if (a.saturation.abs() >= 1e-8) {
    final strength = a.saturation >= 0
        ? PhotoAdjustConfig.saturationAmountPos
        : PhotoAdjustConfig.saturationAmountNeg;
    var weight = 1.0;
    if (a.saturation > 0) {
      // Already-vivid colors get less boost (ACR soft-limits chroma).
      final sat = _chroma(outR, outG, outB);
      weight = 1 -
          gradeSmoothstep(
            PhotoAdjustConfig.saturationChromaFadeLo,
            PhotoAdjustConfig.saturationChromaFadeHi,
            sat,
          );
    }
    final mix = 1 + a.saturation * strength * weight;
    outR = y + (outR - y) * mix;
    outG = y + (outG - y) * mix;
    outB = y + (outB - y) * mix;
  }
  return GradeRgb(outR, outG, outB);
}

/// Ordered Bayer 4×4 dither in −0.5…0.5, scaled by [PhotoAdjustConfig.ditherAmplitude].
double orderedDither(int x, int y) {
  const bayer = <int>[
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5,
  ];
  final v = bayer[(y & 3) * 4 + (x & 3)] / 16.0 - 0.5;
  return v * 2; // −1…1 before amplitude
}

/// Linear-light grade. [mask01] is required when H/S are active.
GradeRgb gradeLinearRgb(
  double r,
  double g,
  double b,
  PhotoAdjustments ui, {
  double? mask01,
}) {
  if (ui.isNeutral) return GradeRgb(r, g, b);
  final a = ui.eased;
  final wb = whiteBalanceGain(a.temperature, a.tint);
  var lr = r * wb.$1;
  var lg = g * wb.$2;
  var lb = b * wb.$3;

  // Exposure: plain stop multiply (shoulder comes later).
  if (a.exposure.abs() >= 1e-8) {
    final gain = math.pow(2, a.exposure).toDouble();
    lr *= gain;
    lg *= gain;
    lb *= gain;
  }

  // Contrast: hue-preserving luminance S-curve in log2.
  if (a.contrast.abs() >= 1e-8) {
    final y = _luma(lr, lg, lb);
    final y2 = contrastCurve(y, a.contrast);
    final toned = _scaleToLuma(lr, lg, lb, y2);
    lr = toned.r;
    lg = toned.g;
    lb = toned.b;
  }

  // Highlights / Shadows (local).
  if (a.shadows.abs() >= 1e-8 || a.highlights.abs() >= 1e-8) {
    final m = mask01 ?? linearToSrgb(_luma(lr, lg, lb).clamp(0.0, 1.0));
    final local = applyShadowsHighlights(lr, lg, lb, a, mask01: m);
    lr = local.r;
    lg = local.g;
    lb = local.b;
  }

  // Whites / Blacks.
  if (a.whites.abs() >= 1e-8 || a.blacks.abs() >= 1e-8) {
    final y = whitesBlacksCurve(_luma(lr, lg, lb), a.whites, a.blacks);
    final toned = _scaleToLuma(lr, lg, lb, y);
    lr = toned.r;
    lg = toned.g;
    lb = toned.b;
  }

  // Vibrance / Saturation.
  final sat = applyVibranceSaturation(lr, lg, lb, a);
  lr = sat.r;
  lg = sat.g;
  lb = sat.b;

  // Soft highlight shoulder.
  return softShoulderRgb(lr, lg, lb);
}

/// Grades one display-referred sRGB pixel (channels 0…1).
GradeRgb gradeDisplayRgb(
  double r,
  double g,
  double b,
  PhotoAdjustments a, {
  double? mask01,
  int? ditherX,
  int? ditherY,
}) {
  if (a.isNeutral) return GradeRgb(r, g, b);
  final linear = gradeLinearRgb(
    srgbToLinear(r),
    srgbToLinear(g),
    srgbToLinear(b),
    a,
    mask01: mask01,
  );
  var sr = linearToSrgb(linear.r);
  var sg = linearToSrgb(linear.g);
  var sb = linearToSrgb(linear.b);
  if (ditherX != null && ditherY != null) {
    final d = orderedDither(ditherX, ditherY) * PhotoAdjustConfig.ditherAmplitude;
    sr += d;
    sg += d;
    sb += d;
  }
  return GradeRgb(sr.clamp(0.0, 1.0), sg.clamp(0.0, 1.0), sb.clamp(0.0, 1.0));
}

/// Perceptual 0…1 mask from linear luma (for CPU histogram / tests).
double perceptualMask01(double linearY) {
  return linearToSrgb(linearY.clamp(0.0, 1.0));
}

/// Build the blended guided-filter mask (perceptual 0…1) for [rgb] sRGB bytes.
///
/// Mask source is log-luminance after WB / exposure / contrast only.
Float32List lumaMaskForDisplayRgb(
  Uint8List rgb,
  int width,
  int height,
  PhotoAdjustments adjustments,
) {
  final n = width * height;
  final logLuma = Float32List(n);
  final prefix = adjustments.copyWith(
    highlights: 0,
    shadows: 0,
    whites: 0,
    blacks: 0,
    vibrance: 0,
    saturation: 0,
  );
  final a = prefix.eased;
  final wb = whiteBalanceGain(a.temperature, a.tint);
  final expGain =
      a.exposure.abs() < 1e-8 ? 1.0 : math.pow(2, a.exposure).toDouble();

  for (var i = 0; i < n; i++) {
    final o = i * 3;
    if (o + 2 >= rgb.length) break;
    var lr = srgbToLinear(rgb[o] / 255.0) * wb.$1 * expGain;
    var lg = srgbToLinear(rgb[o + 1] / 255.0) * wb.$2 * expGain;
    var lb = srgbToLinear(rgb[o + 2] / 255.0) * wb.$3 * expGain;
    if (a.contrast.abs() >= 1e-8) {
      final y = _luma(lr, lg, lb);
      final y2 = contrastCurve(y, a.contrast);
      if (y > 1e-8) {
        final s = y2 / y;
        lr *= s;
        lg *= s;
        lb *= s;
      }
    }
    final y = math.max(_luma(lr, lg, lb), 0.0);
    logLuma[i] = math.log(y + 1e-4) / math.ln2;
  }

  final radius = math.max(
    1,
    (width * PhotoAdjustConfig.guidedRadiusWidthFraction).round(),
  );
  final filtered = guidedFilterScalar(
    logLuma,
    width,
    height,
    radius: radius,
    eps: PhotoAdjustConfig.guidedEps,
  );

  const blend = PhotoAdjustConfig.maskFilterBlend;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final sharpLin = math.pow(2, logLuma[i]).toDouble() - 1e-4;
    final filtLin = math.pow(2, filtered[i]).toDouble() - 1e-4;
    final sharp = perceptualMask01(sharpLin);
    final filt = perceptualMask01(filtLin);
    out[i] = blend * filt + (1 - blend) * sharp;
  }
  return out;
}

/// Backward-compatible name used by histogram / older call sites.
Float32List lumaBaseForDisplayRgb(
  Uint8List rgb,
  int width,
  int height,
  PhotoAdjustments adjustments,
) =>
    lumaMaskForDisplayRgb(rgb, width, height, adjustments);
