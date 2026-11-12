import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/photo_edit/photo_adjust_config.dart';
import 'package:quick_cap/photo_edit/photo_adjustments.dart';

void main() {
  test('neutral grade leaves pixels unchanged', () {
    const samples = [0.0, 0.2, 0.5, 0.8, 1.0];
    for (final r in samples) {
      for (final g in samples) {
        final graded = gradeDisplayRgb(r, g, 0.4, PhotoAdjustments.neutral);
        expect(graded.r, r);
        expect(graded.g, g);
        expect(graded.b, 0.4);
      }
    }
  });

  test('slider easing is subtle near zero and stronger at the ends', () {
    final small = PhotoGradeParams.easeUi(20).abs();
    final large = PhotoGradeParams.easeUi(80).abs();
    expect(small, lessThan(0.20 / 1.0)); // pow(0.2, 1.5) ≈ 0.089
    expect(large, greaterThan(0.7));
    expect(PhotoGradeParams.easeUi(100), closeTo(1.0, 1e-9));
    expect(PhotoGradeParams.easeUi(-100), closeTo(-1.0, 1e-9));
  });

  test('one stop of exposure doubles linear light below the shoulder', () {
    final graded = gradeLinearRgb(
      0.25,
      0.25,
      0.25,
      const PhotoAdjustments(exposure: 1),
    );
    expect(graded.r, closeTo(0.5, 0.002));
  });

  test('soft shoulder compresses above the knee without hard clip', () {
    final hot = softShoulderRgb(2.0, 2.0, 2.0);
    expect(hot.r, lessThan(1.2));
    expect(hot.r, greaterThan(PhotoAdjustConfig.shoulderKnee));
    final cool = softShoulderRgb(0.5, 0.5, 0.5);
    expect(cool.r, closeTo(0.5, 1e-9));
  });

  test('contrast pivots near 0.35 linear and keeps channel ratios', () {
    const grade = PhotoAdjustments(contrast: 100);
    final gray = gradeLinearRgb(0.35, 0.35, 0.35, grade);
    expect(gray.r, closeTo(0.35, 1e-6));
    final colored = gradeLinearRgb(0.20, 0.05, 0.08, grade);
    expect(colored.r / colored.g, closeTo(0.20 / 0.05, 0.001));
    expect(colored.b / colored.g, closeTo(0.08 / 0.05, 0.001));
    final dark = gradeLinearRgb(0.04, 0.04, 0.04, grade);
    final bright = gradeLinearRgb(0.55, 0.55, 0.55, grade);
    expect(dark.r, lessThan(0.04));
    expect(bright.r, greaterThan(0.55));
    // ACR-like: shadows move more (in stops) than near-white highlights.
    final darkStops = math.log(dark.r / 0.04) / math.ln2;
    final hi = gradeLinearRgb(0.90, 0.90, 0.90, grade);
    final hiStops = math.log(hi.r / 0.90) / math.ln2;
    expect(darkStops.abs(), greaterThan(hiStops.abs()));
  });

  test('whites lift upper-mids more than speculars; blacks move the toe', () {
    const whites = PhotoAdjustments(whites: 100);
    final low = gradeLinearRgb(0.08, 0.08, 0.08, whites);
    final upper = gradeLinearRgb(0.55, 0.55, 0.55, whites);
    final specular = gradeLinearRgb(0.95, 0.95, 0.95, whites);
    expect(low.r, closeTo(0.08, 0.01));
    expect(upper.r, greaterThan(0.55));
    // ACR-like fade: specular whites move less (in stops) than upper mids.
    final upperStops = math.log(upper.r / 0.55) / math.ln2;
    final specStops = math.log(specular.r / 0.95) / math.ln2;
    expect(upperStops, greaterThan(specStops));

    const blacks = PhotoAdjustments(blacks: 100);
    final still = gradeLinearRgb(0.40, 0.40, 0.40, blacks);
    final toe = gradeLinearRgb(0.004, 0.004, 0.004, blacks);
    expect(still.r, closeTo(0.40, 0.02));
    expect(toe.r, greaterThan(0.004));
    const crush = PhotoAdjustments(blacks: -100);
    final crushed = gradeLinearRgb(0.04, 0.04, 0.04, crush);
    expect(crushed.r, lessThan(0.04));
  });

  test('positive shadows lift darks hard and spare highlights', () {
    const grade = PhotoAdjustments(shadows: 100);
    final black = gradeDisplayRgb(0, 0, 0, grade, mask01: 0.0);
    final dark = gradeLinearRgb(0.04, 0.04, 0.04, grade, mask01: 0.05);
    final open = gradeLinearRgb(0.12, 0.12, 0.12, grade, mask01: 0.30);
    final bright = gradeDisplayRgb(0.8, 0.8, 0.8, grade, mask01: 0.85);
    expect(black.r, closeTo(0, 0.02));
    expect(dark.r, greaterThan(0.04));
    // ACR-like: deeper mask weight lifts more (in stops) than open lower-mids.
    final darkStops = math.log(dark.r / 0.04) / math.ln2;
    final openStops = math.log(open.r / 0.12) / math.ln2;
    expect(darkStops, greaterThan(openStops));
    expect(bright.r, closeTo(0.8, 0.04));
  });

  test('negative highlights darken soft brights more than speculars', () {
    const grade = PhotoAdjustments(highlights: -100);
    final soft = gradeDisplayRgb(0.75, 0.75, 0.75, grade, mask01: 0.65);
    final specular = gradeDisplayRgb(0.95, 0.95, 0.95, grade, mask01: 0.98);
    final mid = gradeDisplayRgb(0.5, 0.5, 0.5, grade, mask01: 0.4);
    expect(soft.r, lessThan(0.75));
    // ACR-like fade: specular whites move less than soft highlights.
    expect((0.75 - soft.r), greaterThan((0.95 - specular.r)));
    expect(mid.r, closeTo(0.5, 0.06));
  });

  test('guided mask stays dark on the dark side of a hard edge (no halo)', () {
    // Dark left / bright right — classic player-on-ice edge.
    const width = 256;
    const height = 64;
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = x < width ~/ 2 ? 30 : 240;
        final i = (y * width + x) * 3;
        rgb[i] = value;
        rgb[i + 1] = value;
        rgb[i + 2] = value;
      }
    }
    const grade = PhotoAdjustments(shadows: 100);
    final mask = lumaMaskForDisplayRgb(rgb, width, height, grade);
    final dark = mask[32 * width + (width ~/ 2 - 8)];
    final bright = mask[32 * width + (width ~/ 2 + 8)];
    expect(dark, lessThan(0.35));
    expect(bright, greaterThan(0.65));
    // Edge-aware: values just off the edge stay on their own side.
    expect(bright - dark, greaterThan(0.35));
  });

  test('warm temperature lifts red relative to blue without lifting black', () {
    const grade = PhotoAdjustments(temperature: 100);
    final black = gradeDisplayRgb(0, 0, 0, grade);
    final gray = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(black.r, closeTo(0, 0.002));
    expect(gray.r, greaterThan(gray.b + 0.02));
    // Cool is weaker than warm (ACR-matched asymmetry).
    const cool = PhotoAdjustments(temperature: -100);
    final coolGray = gradeDisplayRgb(0.5, 0.5, 0.5, cool);
    final warmSplit = gray.r - gray.b;
    final coolSplit = coolGray.b - coolGray.r;
    expect(warmSplit, greaterThan(coolSplit));
  });

  test('magenta tint reduces green relative to red/blue', () {
    const grade = PhotoAdjustments(tint: 100);
    final gray = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(gray.r, greaterThan(gray.g));
    expect(gray.b, greaterThan(gray.g));
    // ACR-like: green-side tint is stronger than magenta at the same |value|.
    const green = PhotoAdjustments(tint: -100);
    final greenGray = gradeDisplayRgb(0.5, 0.5, 0.5, green);
    final magentaSplit = ((gray.r + gray.b) / 2) - gray.g;
    final greenSplit = greenGray.g - ((greenGray.r + greenGray.b) / 2);
    expect(greenSplit, greaterThan(magentaSplit));
  });

  test('vibrance boosts low-sat more than high-sat', () {
    const grade = PhotoAdjustments(vibrance: 100);
    final dull = gradeLinearRgb(0.40, 0.38, 0.37, grade);
    final vivid = gradeLinearRgb(0.70, 0.20, 0.15, grade);
    double chromaOf(GradeRgb c) {
      final y = c.luma;
      final dr = c.r - y;
      final dg = c.g - y;
      final db = c.b - y;
      return math.sqrt(dr * dr + dg * dg + db * db);
    }

    final dullRatio =
        chromaOf(dull) / chromaOf(const GradeRgb(0.40, 0.38, 0.37));
    final vividRatio =
        chromaOf(vivid) / chromaOf(const GradeRgb(0.70, 0.20, 0.15));
    expect(dullRatio, greaterThan(1.2));
    // Vivid should barely move vs low-sat (ACR soft-limits).
    expect(vividRatio, lessThan(1.15));
    expect(dullRatio, greaterThan(vividRatio));
  });

  test('negative vibrance hits low-sat harder than vivid', () {
    const grade = PhotoAdjustments(vibrance: -40);
    final dull = gradeLinearRgb(0.42, 0.40, 0.39, grade);
    final vivid = gradeLinearRgb(0.70, 0.20, 0.15, grade);
    double chromaOf(GradeRgb c) {
      final y = c.luma;
      final dr = c.r - y;
      final dg = c.g - y;
      final db = c.b - y;
      return math.sqrt(dr * dr + dg * dg + db * db);
    }

    final dullRatio =
        chromaOf(dull) / chromaOf(const GradeRgb(0.42, 0.40, 0.39));
    final vividRatio =
        chromaOf(vivid) / chromaOf(const GradeRgb(0.70, 0.20, 0.15));
    expect(dullRatio, lessThan(0.75));
    expect(vividRatio, greaterThan(dullRatio));
    expect(vividRatio, lessThan(1.0));
  });

  test('saturation −100 fully desaturates; +sat soft-limits vivid', () {
    const desat = PhotoAdjustments(saturation: -100);
    final gray = gradeLinearRgb(0.55, 0.22, 0.18, desat);
    expect((gray.r - gray.g).abs(), lessThan(1e-6));
    expect((gray.g - gray.b).abs(), lessThan(1e-6));

    const boost = PhotoAdjustments(saturation: 100);
    final dull = gradeLinearRgb(0.42, 0.40, 0.39, boost);
    final vivid = gradeLinearRgb(0.70, 0.20, 0.15, boost);
    double chromaOf(GradeRgb c) {
      final y = c.luma;
      final dr = c.r - y;
      final dg = c.g - y;
      final db = c.b - y;
      return math.sqrt(dr * dr + dg * dg + db * db);
    }

    final dullRatio = chromaOf(dull) /
        chromaOf(const GradeRgb(0.42, 0.40, 0.39));
    final vividRatio = chromaOf(vivid) /
        chromaOf(const GradeRgb(0.70, 0.20, 0.15));
    expect(dullRatio, greaterThan(1.5));
    expect(vividRatio, lessThan(dullRatio));
    expect(vividRatio, lessThan(1.4));
  });

  test('preset round-trip preserves all sliders', () {
    const original = PhotoAdjustments(
      temperature: 12,
      tint: -8,
      exposure: 1.25,
      contrast: 40,
      highlights: -30,
      shadows: 55,
      whites: 10,
      blacks: -15,
      vibrance: 20,
      saturation: -5,
    );
    final copy = PhotoAdjustments.fromPresetJson(original.toPresetJson());
    expect(copy.temperature, original.temperature);
    expect(copy.tint, original.tint);
    expect(copy.exposure, original.exposure);
    expect(copy.contrast, original.contrast);
    expect(copy.highlights, original.highlights);
    expect(copy.shadows, original.shadows);
    expect(copy.whites, original.whites);
    expect(copy.blacks, original.blacks);
    expect(copy.vibrance, original.vibrance);
    expect(copy.saturation, original.saturation);
  });
}
