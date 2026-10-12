import 'dart:math' as math;
import 'dart:typed_data';

/// Edge-aware base layer for local shadows and highlights.
///
/// Self-guided filter (He, Sun, Tang). Reimplemented here; this is not
/// darktable or RawTherapee code. A large radius keeps texture in the detail
/// layer and lets the tone move only the broad regions.
const toneBaseLogMin = -13.287712379549449; // log2(1e-4)
const toneBaseLogMax = 2.0; // log2(4)

int toneBaseRadius(int width, int height) {
  final shortSide = math.min(width, height);
  if (shortSide <= 1) return 1;
  return (shortSide * 0.08).round().clamp(2, 64);
}

/// Encodes a linear luma in about 0…4 into 0…1 for an 8-bit mask texture.
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

Float32List guidedLumaBase(
  Float32List luma,
  int width,
  int height, {
  int? radius,
  double eps = 0.02,
}) {
  final n = width * height;
  if (n == 0 || luma.length < n) return Float32List(n);
  final r = radius ?? toneBaseRadius(width, height);
  final mean = Float32List(n);
  final meanSq = Float32List(n);
  final sq = Float32List(n);
  for (var i = 0; i < n; i++) {
    sq[i] = luma[i] * luma[i];
  }
  _boxMean(luma, mean, width, height, r);
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

  final base = Float32List(n);
  for (var i = 0; i < n; i++) {
    base[i] = meanA[i] * luma[i] + meanB[i];
  }
  return base;
}

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
