import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

  test('one stop of exposure doubles linear light below the shoulder', () {
    final graded = gradeDisplayRgb(
      0.5,
      0.5,
      0.5,
      const PhotoAdjustments(exposure: 1),
    );
    final expected = linearToSrgb(srgbToLinear(0.5) * 2);
    expect(graded.r, closeTo(expected, 0.002));
  });

  test('zero exposure is exact, and positive exposure shoulders instead of clipping', () {
    expect(exposeLinear(0.95, 0), 0.95);
    final lifted = exposeLinear(0.5, 3);
    final hotter = exposeLinear(1, 3);
    expect(lifted, lessThan(1));
    expect(hotter, lessThan(1));
    expect(hotter, greaterThan(lifted));
    expect(exposeLinear(0.2, -2), closeTo(0.05, 1e-9));
  });

  test('contrast pivots on 18% gray and keeps channel ratios', () {
    const grade = PhotoAdjustments(contrast: 1);
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
    const whites = PhotoAdjustments(whites: 1);
    final mid = gradeLinearRgb(0.18, 0.18, 0.18, whites);
    final high = gradeLinearRgb(0.80, 0.80, 0.80, whites);
    expect(mid.r, closeTo(0.18, 1e-6));
    expect(high.r, greaterThan(0.90));

    const blacks = PhotoAdjustments(blacks: 1);
    final still = gradeLinearRgb(0.18, 0.18, 0.18, blacks);
    final toe = gradeLinearRgb(0.004, 0.004, 0.004, blacks);
    expect(still.r, closeTo(0.18, 1e-6));
    expect(toe.r, greaterThan(0.02));
  });

  test('shadows open a flat dark field and leave black and mid gray', () {
    const grade = PhotoAdjustments(shadows: 1);
    final black = gradeDisplayRgb(0, 0, 0, grade);
    final dark = gradeDisplayRgb(0.2, 0.2, 0.2, grade);
    final mid = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(black.r, closeTo(0, 0.002));
    expect(dark.r, greaterThan(0.35));
    expect(mid.r, closeTo(0.5, 0.05));
  });

  test('shadows lift a dark region more than a one-pixel speck', () {
    const width = 64;
    const height = 64;
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final speck = x == 58 && y == 32;
        final region = x < 24;
        final value = (region || speck) ? 40 : 230;
        final i = (y * width + x) * 3;
        rgb[i] = value;
        rgb[i + 1] = value;
        rgb[i + 2] = value;
      }
    }
    const grade = PhotoAdjustments(shadows: 1);
    final base = lumaBaseForDisplayRgb(rgb, width, height, grade);
    final region = gradeDisplayRgb(
      40 / 255,
      40 / 255,
      40 / 255,
      grade,
      baseLuma: base[32 * width + 8],
    );
    final speck = gradeDisplayRgb(
      40 / 255,
      40 / 255,
      40 / 255,
      grade,
      baseLuma: base[32 * width + 58],
    );
    expect(region.r, greaterThan(speck.r + 0.04));
  });

  test('highlight recovery pulls brights down and leaves white', () {
    const grade = PhotoAdjustments(highlights: -1);
    final white = gradeDisplayRgb(1, 1, 1, grade);
    final bright = gradeDisplayRgb(0.85, 0.85, 0.85, grade);
    final mid = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(white.r, closeTo(1, 0.02));
    expect(bright.r, lessThan(0.78));
    expect(mid.r, closeTo(0.5, 0.04));
  });

  test('temperature slider is 6500K in the middle and finer there than at the end', () {
    expect(temperatureKelvin(0), 6500);
    expect(temperatureKelvin(1), closeTo(2000, 1));
    expect(temperatureKelvin(-1), closeTo(50000, 1));
    final nearCenter = (temperatureKelvin(0.1) - 6500).abs();
    final nearEnd = (temperatureKelvin(1) - temperatureKelvin(0.9)).abs();
    expect(nearCenter, lessThan(nearEnd));
  });

  test('magenta tint lifts red and blue above green', () {
    const grade = PhotoAdjustments(tint: 1);
    final black = gradeDisplayRgb(0, 0, 0, grade);
    final gray = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(black.r, closeTo(0, 0.002));
    expect(gray.r, greaterThan(gray.g));
    expect(gray.b, greaterThan(gray.g));
  });

  test('green tint lifts green above red', () {
    final gray = gradeDisplayRgb(
      0.5,
      0.5,
      0.5,
      const PhotoAdjustments(tint: -1),
    );
    expect(gray.g, greaterThan(gray.r));
    expect(gray.g, greaterThan(gray.b));
  });

  test('warm temperature yellows a gray without lifting black', () {
    const grade = PhotoAdjustments(temperature: 1);
    final black = gradeDisplayRgb(0, 0, 0, grade);
    final gray = gradeDisplayRgb(0.5, 0.5, 0.5, grade);
    expect(black.r, closeTo(0, 0.002));
    expect(gray.r, greaterThan(gray.b + 0.05));
  });
}
