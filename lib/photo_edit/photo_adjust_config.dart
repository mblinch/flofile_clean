/// Tunable constants for the Camera Raw–style grade pipeline.
///
/// Preview and export share these values so both paths look identical.
/// Radii are fractions of image width (never raw pixels) so a 4K export
/// matches a 2K preview.
class PhotoAdjustConfig {
  const PhotoAdjustConfig._();

  // ---------------------------------------------------------------------------
  // Preview / export
  // ---------------------------------------------------------------------------

  /// Long-edge cap for the live preview texture.
  static const int previewLongEdge = 2048;

  /// Guided-filter mask is computed at least this fraction of preview size.
  static const double maskResolutionScale = 0.25;

  /// Soft GPU texture-size limit; export tiles above this.
  static const int maxTextureEdge = 8192;

  /// Export tile edge when the full frame exceeds [maxTextureEdge].
  static const int exportTileEdge = 2048;

  /// JPEG quality for baked output.
  static const int exportJpegQuality = 92;

  // ---------------------------------------------------------------------------
  // Slider easing: UI −100…100 → normalize to −1…1, then
  //   eased = sign(v) * pow(|v|, sliderEasePower)
  // Small moves stay subtle; large moves bite. Exposure is linear stops.
  // ---------------------------------------------------------------------------

  static const double sliderEasePower = 1.5;
  static const double sliderUiMin = -100;
  static const double sliderUiMax = 100;
  static const double exposureStopsMin = -5;
  static const double exposureStopsMax = 5;
  static const double exposureStep = 0.01;

  // ---------------------------------------------------------------------------
  // White balance (linear RGB gains, then luminance renormalize)
  // Temp UI is linear (−1…1), not power-eased — ACR Temp tracks slider
  // more evenly. Warm is stronger than cool on ice neutrals.
  // Temp: r *= 1 + strength*t , b *= 1 − strength*t
  // Tint: g *= 1 − tintStrength*tint
  // ---------------------------------------------------------------------------

  static const double tempStrengthPos = 0.28;
  static const double tempStrengthNeg = 0.14;

  /// Tint UI is linear (−1…1). Positive = magenta (less green); negative = green.
  /// ACR green-side moves are stronger than magenta at the same |value|.
  static const double tintStrengthPos = 0.10;
  static const double tintStrengthNeg = 0.175;

  // ---------------------------------------------------------------------------
  // Contrast: ACR-shaped log2 S-curve (not a single strength knob)
  //   stops' = log2(Y / pivot) * (1 + strength(Y) * fade(Y) * c)
  // ACR +contrast crushes below ~0.30 linear harder than it lifts above,
  // and the lift fades out toward specular whites.
  // ---------------------------------------------------------------------------

  static const double contrastPivot = 0.35;

  /// Strength below the pivot (shadows / lower mids).
  static const double contrastStrengthLo = 0.55;

  /// Strength above the pivot (upper mids).
  static const double contrastStrengthHi = 0.45;

  /// Highlight fade: contrast amount → 0 between these linear Y values.
  static const double contrastFadeLo = 0.60;
  static const double contrastFadeHi = 0.98;

  // ---------------------------------------------------------------------------
  // Highlights / Shadows — guided-filter mask
  // Radius is a fraction of *full* image width; at mask resolution it scales
  // automatically (same fraction of the mask width).
  // ---------------------------------------------------------------------------

  static const double guidedRadiusWidthFraction = 0.015;
  static const double guidedEps = 0.01;

  /// mask = maskFilterBlend * filtered + (1 − blend) * sharp
  static const double maskFilterBlend = 0.8;

  /// ACR Highlights weight: rises into soft brights, then fades before specular white.
  /// hiW = smoothstep(lo, hi, mask) * (1 − smoothstep(fadeLo, fadeHi, mask))
  static const double highlightMaskLo = 0.50;
  static const double highlightMaskHi = 0.70;
  static const double highlightFadeLo = 0.85;
  static const double highlightFadeHi = 1.00;

  /// ACR Shadows weight: strongest in deep darks, falls through lower mids,
  /// hard cut before highlights.
  /// shW = pow(1 − mask, power) * (1 − smoothstep(fadeLo, fadeHi, mask))
  static const double shadowMaskPower = 1.2;
  static const double shadowFadeLo = 0.55;
  static const double shadowFadeHi = 0.75;

  /// Highlight gain in stops: exp2(hiW * amount * strength).
  /// Negative (recover) and positive (push) are asymmetric, ACR-matched.
  static const double highlightStrengthNeg = 0.50;
  static const double highlightStrengthPos = 0.70;

  /// Shadow gain in stops: exp2(shW * amount * strength).
  static const double shadowStrengthPos = 2.8;
  static const double shadowStrengthNeg = 3.5;

  /// Log-luma encode range for the mask texture (approx 1e−4 … 4).
  static const double maskLogMin = -13.287712379549449; // log2(1e-4)
  static const double maskLogMax = 2.0; // log2(4)

  // ---------------------------------------------------------------------------
  // Whites / Blacks
  // ---------------------------------------------------------------------------

  /// ACR Whites: broad mid/upper lobe in stops, fades before specular white.
  /// whW = smoothstep(lo, hi, Y) * (1 − smoothstep(fadeLo, fadeHi, Y))
  /// Y' = Y * exp2(whites * whitesAmount * whW)
  static const double whitesMaskLo = 0.15;
  static const double whitesMaskHi = 0.45;
  static const double whitesFadeLo = 0.75;
  static const double whitesFadeHi = 0.95;

  /// Max whites gain in stops at peak weight (eased ±1).
  static const double whitesAmount = 0.66;

  /// ACR Blacks: wide toe in stops, strongest in deep darks.
  /// bkW = pow(1 − smoothstep(0, blacksEnd, Y), blacksMaskPower)
  /// Y' = Y * exp2(blacks * amount * bkW)
  static const double blacksEnd = 0.27;
  static const double blacksMaskPower = 2.3;

  /// Lift / crush strengths in stops at full toe weight (eased ±1).
  static const double blacksAmountPos = 1.61;
  static const double blacksAmountNeg = 5.4;

  // ---------------------------------------------------------------------------
  // Vibrance / Saturation
  // ---------------------------------------------------------------------------

  /// Vibrance UI is linear (−1…1). Boosts low chroma more than vivid;
  /// negative is stronger than positive at the same |value| (ACR-matched).
  /// weight = 1 − (1 − floor) * smoothstep(fadeLo, fadeHi, chroma)
  /// floor = 0 on +vibrance; [vibranceChromaFloorNeg] on −vibrance.
  static const double vibranceAmountPos = 0.70;
  static const double vibranceAmountNeg = 1.28;
  static const double vibranceChromaFadeLo = 0.08;
  static const double vibranceChromaFadeHi = 0.45;
  static const double vibranceChromaFloorNeg = 0.55;

  /// Saturation UI is linear (−1…1). Negative must reach full desat at −100.
  /// Positive boost fades on already-vivid chroma (ACR-matched).
  /// mix = 1 + sat * amount * (sat≥0 ? vividFade : 1)
  static const double saturationAmountPos = 0.85;
  static const double saturationAmountNeg = 1.0;

  /// Positive sat fade: weight = 1 − smoothstep(lo, hi, chroma).
  static const double saturationChromaFadeLo = 0.10;
  static const double saturationChromaFadeHi = 0.75;

  /// Skin protection: reduce vibrance near orange (hue degrees in HSV).
  static const double skinHueCenter = 35; // degrees
  static const double skinHueWidth = 40; // degrees half-width
  static const double skinVibranceScale = 0.45; // residual vibrance on skin

  // ---------------------------------------------------------------------------
  // Soft highlight shoulder (linear RGB, hue-preserving via max-channel)
  //   x' = shoulderKnee + (x − knee) / (1 + (x − knee) / shoulderRoom)
  // ---------------------------------------------------------------------------

  static const double shoulderKnee = 0.8;
  /// Slightly roomier than 0.2 so +exposure ice rolloff tracks ACR exports.
  static const double shoulderRoom = 0.3;

  // ---------------------------------------------------------------------------
  // Output dither (±0.5/255) after sRGB encode, before 8-bit quantize
  // ---------------------------------------------------------------------------

  static const double ditherAmplitude = 0.5 / 255.0;

  /// Rec. 709 luminance weights (linear sRGB).
  static const double lumaR = 0.2126;
  static const double lumaG = 0.7152;
  static const double lumaB = 0.0722;
}
