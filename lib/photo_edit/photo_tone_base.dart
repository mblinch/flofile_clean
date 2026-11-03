import 'dart:math' as math;
import 'dart:typed_data';

import 'photo_adjust_config.dart';

/// Edge-aware guided filter (He, Sun, Tang) for the local-tone mask.
///
/// Self-guided: guide = input. Radius is in pixels of the mask buffer;
/// callers derive it as `width * guidedRadiusWidthFraction` so preview and
/// export agree.

const toneBaseLogMin = PhotoAdjustConfig.maskLogMin;
const toneBaseLogMax = PhotoAdjustConfig.maskLogMax;

int toneBaseRadius(int width, int height) {
  if (width <= 1) return 1;
  return (width * PhotoAdjustConfig.guidedRadiusWidthFraction)
      .round()
      .clamp(1, 128);
}

/// Encodes linear luma (~0…4) into 0…1 for an 8-bit debug view.
double encodeBaseLuma(double y) {
  final logv = math.log(y.clamp(0.0, 4.0) + 1e-4) / math.ln2;
  return ((logv - toneBaseLogMin) / (toneBaseLogMax - toneBaseLogMin))
      .clamp(0.0, 1.0);
}

double decodeBaseLuma(double encoded) {
  final logv = toneBaseLogMin +
      encoded.clamp(0.0, 1.0) * (toneBaseLogMax - toneBaseLogMin);
  return math.pow(2, logv).toDouble() - 1e-4;
}

/// Pack a 0…1 value into R/G of an RGBA8 texel (~16-bit precision).
void packFloat01(double v, Uint8List rgba, int offset) {
  final enc = (v.clamp(0.0, 1.0) * 65535.0).round().clamp(0, 65535);
  rgba[offset] = enc >> 8;
  rgba[offset + 1] = enc & 0xff;
  rgba[offset + 2] = 0;
  rgba[offset + 3] = 255;
}

double unpackFloat01(int r, int g) => ((r << 8) | g) / 65535.0;

/// Self-guided filter on a scalar field (typically log-luminance).
Float32List guidedFilterScalar(
  Float32List input,
  int width,
  int height, {
  int? radius,
  double eps = PhotoAdjustConfig.guidedEps,
}) {
  final n = width * height;
  if (n == 0 || input.length < n) return Float32List(n);
  final r = radius ?? toneBaseRadius(width, height);
  final mean = Float32List(n);
  final meanSq = Float32List(n);
  final sq = Float32List(n);
  for (var i = 0; i < n; i++) {
    sq[i] = input[i] * input[i];
  }
  _boxMean(input, mean, width, height, r);
  _boxMean(sq, meanSq, width, height, r);

  final a = Float32List(n);
  final b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final variance = math.max(0.0, meanSq[i] - mean[i] * mean[i]);
    final coeff = variance / (variance + eps);
    a[i] = coeff;
    b[i] = mean[i] * (1 - coeff);
  }
  final meanA = Float32List(n);
  final meanB = Float32List(n);
  _boxMean(a, meanA, width, height, r);
  _boxMean(b, meanB, width, height, r);

  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = meanA[i] * input[i] + meanB[i];
  }
  return out;
}

/// Alias kept for older call sites.
Float32List guidedLumaBase(
  Float32List luma,
  int width,
  int height, {
  int? radius,
  double eps = PhotoAdjustConfig.guidedEps,
}) =>
    guidedFilterScalar(luma, width, height, radius: radius, eps: eps);

double sampleLumaBase(
  Float32List base,
  int baseWidth,
  int baseHeight,
  int x,
  int y,
  int fullWidth,
  int fullHeight,
) {
  if (baseWidth <= 0 || baseHeight <= 0) return 0;
  if (baseWidth == 1 && baseHeight == 1) return base[0];
  // Bilinear — never nearest — so upscaling the mask stays soft.
  final fx = ((x + 0.5) * baseWidth / fullWidth) - 0.5;
  final fy = ((y + 0.5) * baseHeight / fullHeight) - 0.5;
  final x0 = fx.floor().clamp(0, baseWidth - 1);
  final y0 = fy.floor().clamp(0, baseHeight - 1);
  final x1 = (x0 + 1).clamp(0, baseWidth - 1);
  final y1 = (y0 + 1).clamp(0, baseHeight - 1);
  final tx = (fx - x0).clamp(0.0, 1.0);
  final ty = (fy - y0).clamp(0.0, 1.0);
  final i00 = base[y0 * baseWidth + x0];
  final i10 = base[y0 * baseWidth + x1];
  final i01 = base[y1 * baseWidth + x0];
  final i11 = base[y1 * baseWidth + x1];
  final top = i00 + (i10 - i00) * tx;
  final bottom = i01 + (i11 - i01) * tx;
  return top + (bottom - top) * ty;
}

void _boxMean(
  Float32List src,
  Float32List dst,
  int width,
  int height,
  int radius,
) {
  final stride = width + 1;
  final sat = Float64List(stride * (height + 1));
  for (var y = 0; y < height; y++) {
    var row = 0.0;
    final srcRow = y * width;
    final satRow = (y + 1) * stride;
    final satPrev = y * stride;
    for (var x = 0; x < width; x++) {
      row += src[srcRow + x];
      sat[satRow + x + 1] = row + sat[satPrev + x + 1];
    }
  }
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(height, y + radius + 1);
    for (var x = 0; x < width; x++) {
      final x0 = math.max(0, x - radius);
      final x1 = math.min(width, x + radius + 1);
      final sum = sat[y1 * stride + x1] -
          sat[y0 * stride + x1] -
          sat[y1 * stride + x0] +
          sat[y0 * stride + x0];
      dst[y * width + x] = sum / ((x1 - x0) * (y1 - y0));
    }
  }
}
