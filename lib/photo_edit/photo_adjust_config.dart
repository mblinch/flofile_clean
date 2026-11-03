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
  // Temp: r *= 1 + tempStrength*t , b *= 1 − tempStrength*t
  // Tint: g *= 1 − tintStrength*tint
  // ---------------------------------------------------------------------------

  static const double tempStrength = 0.3;
  static const double tintStrength = 0.2;

  // ---------------------------------------------------------------------------
  // Contrast: log2 space around linear mid-grey
  //   stops' = log2(Y / pivot) * (1 + contrastStrength * c)
  // ---------------------------------------------------------------------------

  static const double contrastPivot = 0.18;
  static const double contrastStrength = 0.6;

  // ---------------------------------------------------------------------------
  // Highlights / Shadows — guided-filter mask
  // Radius is a fraction of *full* image width; at mask resolution it scales
  // automatically (same fraction of the mask width).
  // ---------------------------------------------------------------------------

  static const double guidedRadiusWidthFraction = 0.015;
  static const double guidedEps = 0.01;

  /// mask = maskFilterBlend * filtered + (1 − blend) * sharp
  static const double maskFilterBlend = 0.8;

  /// hiW = smoothstep(hiLo, hiHi, mask)
  static const double highlightMaskLo = 0.45;
  static const double highlightMaskHi = 0.85;

  /// shW = 1 − smoothstep(shLo, shHi, mask)
  static const double shadowMaskLo = 0.1;
  static const double shadowMaskHi = 0.5;

  /// Gain in stops: exp2(weight * amount * localToneStrength)
  static const double localToneStrength = 1.5;

  /// Log-luma encode range for the mask texture (approx 1e−4 … 4).
  static const double maskLogMin = -13.287712379549449; // log2(1e-4)
  static const double maskLogMax = 2.0; // log2(4)

  // ---------------------------------------------------------------------------
  // Whites / Blacks
  // ---------------------------------------------------------------------------

  /// Whites weight rises above this linear Y.
  static const double whitesStart = 0.6;

  /// Max endpoint push at whites = ±1 (eased).
  static const double whitesAmount = 0.45;

  /// Blacks toe is mostly below this linear Y.
  static const double blacksEnd = 0.05;

  /// Max toe lift/drop at blacks = ±1 (eased).
  static const double blacksAmount = 0.08;

  // ---------------------------------------------------------------------------
  // Vibrance / Saturation
  // ---------------------------------------------------------------------------

  static const double vibranceAmount = 0.55;
  static const double saturationAmount = 0.75;

  /// Skin protection: reduce vibrance near orange (hue degrees in HSV).
  static const double skinHueCenter = 35; // degrees
  static const double skinHueWidth = 40; // degrees half-width
  static const double skinVibranceScale = 0.35; // residual vibrance on skin

  // ---------------------------------------------------------------------------
  // Soft highlight shoulder (linear RGB, hue-preserving via max-channel)
  //   x' = shoulderKnee + (x − knee) / (1 + (x − knee) / shoulderRoom)
  // ---------------------------------------------------------------------------

  static const double shoulderKnee = 0.8;
  static const double shoulderRoom = 0.2;

  // ---------------------------------------------------------------------------
  // Output dither (±0.5/255) after sRGB encode, before 8-bit quantize
  // ---------------------------------------------------------------------------

  static const double ditherAmplitude = 0.5 / 255.0;

  /// Rec. 709 luminance weights (linear sRGB).
  static const double lumaR = 0.2126;
  static const double lumaG = 0.7152;
  static const double lumaB = 0.0722;
}
