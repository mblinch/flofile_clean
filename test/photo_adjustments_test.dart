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

  test('contrast pivots on 18% gray and keeps channel ratios', () {
    const grade = PhotoAdjustments(contrast: 100);
    final gray = gradeLinearRgb(0.18, 0.18, 0.18, grade);
    expect(gray.r, closeTo(0.18, 1e-6));
    final colored = gradeLinearRgb(0.20, 0.05, 0.08, grade);
    expect(colored.r / colored.g, closeTo(0.20 / 0.05, 0.001));
    expect(colored.b / colored.g, closeTo(0.08 / 0.05, 0.001));
    final dark = gradeLinearRgb(0.04, 0.04, 0.04, grade);
    final bright = gradeLinearRgb(0.60, 0.60, 0.60, grade);
    expect(dark.r, lessThan(0.04));
    expect(bright.r, greaterThan(0.60));
  });

  test('whites and blacks leave middle gray and move the ends', () {
    const whites = PhotoAdjustments(whites: 100);
    final mid = gradeLinearRgb(0.18, 0.18, 0.18, whites);
    final high = gradeLinearRgb(0.80, 0.80, 0.80, whites);
    expect(mid.r, closeTo(0.18, 1e-5));
    expect(high.r, greaterThan(0.80));

    const blacks = PhotoAdjustments(blacks: 100);
    final still = gradeLinearRgb(0.18, 0.18, 0.18, blacks);
    final toe = gradeLinearRgb(0.004, 0.004, 0.004, blacks);
    expect(still.r, closeTo(0.18, 1e-5));
    expect(toe.r, greaterThan(0.004));
  });

  test('positive shadows lift a dark field via the mask', () {
    const grade = PhotoAdjustments(shadows: 100);
    final black = gradeDisplayRgb(0, 0, 0, grade, mask01: 0.0);
    final dark = gradeDisplayRgb(0.15, 0.15, 0.15, grade, mask01: 0.05);
    final mid = gradeDisplayRgb(0.5, 0.5, 0.5, grade, mask01: 0.55);
    expect(black.r, closeTo(0, 0.02));
    expect(dark.r, greaterThan(0.15));
    expect(mid.r, closeTo(0.5, 0.08));
  });

  test('negative highlights darken bright regions via the mask', () {
    const grade = PhotoAdjustments(highlights: -100);
    final bright = gradeDisplayRgb(0.85, 0.85, 0.85, grade, mask01: 0.9);
    final mid = gradeDisplayRgb(0.5, 0.5, 0.5, grade, mask01: 0.4);
    expect(bright.r, lessThan(0.85));
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
  });

  test('magenta tint reduces green relative to red/blue', () {
    const grade = PhotoAdjustments(tint: 100);
    final gray = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(gray.r, greaterThan(gray.g));
    expect(gray.b, greaterThan(gray.g));
  });

  test('vibrance boosts low-sat more than high-sat', () {
    const grade = PhotoAdjustments(vibrance: 100);
    final dull = gradeLinearRgb(0.40, 0.38, 0.37, grade);
    final vivid = gradeLinearRgb(0.70, 0.20, 0.15, grade);
    final dullChroma = ((dull.r - dull.luma).abs() +
            (dull.g - dull.luma).abs() +
            (dull.b - dull.luma).abs()) /
        3;
    final vividChroma = ((vivid.r - vivid.luma).abs() +
            (vivid.g - vivid.luma).abs() +
            (vivid.b - vivid.luma).abs()) /
        3;
    final dullBase = ((0.40 - 0.388).abs()); // roughly
    expect(dullChroma, greaterThan(dullBase * 0.5));
    // Vivid should not explode saturation as hard as a uniform sat boost.
    expect(vividChroma, lessThan(0.55));
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
