import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/photo_edit/photo_adjustments.dart';
import 'package:quick_cap/photo_edit/photo_crop.dart';
import 'package:quick_cap/photo_edit/photo_histogram.dart';

void main() {
  Uint8List solid(int r, int g, int b, int count) {
    final rgb = Uint8List(count * 3);
    for (var i = 0; i < count; i++) {
      rgb[i * 3] = r;
      rgb[i * 3 + 1] = g;
      rgb[i * 3 + 2] = b;
    }
    return rgb;
  }

  test('a flat gray image peaks in one bin', () {
    final histogram = rgbHistogram(
      rgb: solid(128, 128, 128, 40),
      width: 8,
      height: 5,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    final peak = histogram.red.reduce((a, b) => a > b ? a : b);
    expect(peak, 40);
    expect(histogram.red.where((count) => count > 0), [40]);
  });

  test('crop counts only pixels inside the frame', () {
    final rgb = Uint8List.fromList([
      0, 0, 0, // left
      255, 255, 255, // right
    ]);
    final histogram = rgbHistogram(
      rgb: rgb,
      width: 2,
      height: 1,
      adjustments: PhotoAdjustments.neutral,
      crop: const PhotoCrop(left: 0, top: 0, width: 0.5, height: 1),
    );
    expect(histogram.red.first, 1);
    expect(histogram.red.last, 0);
  });

  test('exposure moves a mid gray toward white', () {
    final before = rgbHistogram(
      rgb: solid(128, 128, 128, 16),
      width: 4,
      height: 4,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    final after = rgbHistogram(
      rgb: solid(128, 128, 128, 16),
      width: 4,
      height: 4,
      adjustments: const PhotoAdjustments(exposure: 1),
      crop: PhotoCrop.full,
    );
    int peakBin(List<int> bins) {
      var index = 0;
      for (var i = 1; i < bins.length; i++) {
        if (bins[i] > bins[index]) index = i;
      }
      return index;
    }

    expect(peakBin(after.red), greaterThan(peakBin(before.red)));
  });

  test('flat mid gray does not warn for clipping', () {
    final histogram = rgbHistogram(
      rgb: solid(128, 128, 128, 64),
      width: 8,
      height: 8,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    expect(histogram.shadowsClipping, isFalse);
    expect(histogram.highlightsClipping, isFalse);
  });

  test('crushed blacks warn for shadow clipping', () {
    final histogram = rgbHistogram(
      rgb: solid(0, 0, 0, 64),
      width: 8,
      height: 8,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    expect(histogram.shadowClipped, 64);
    expect(histogram.shadowsClipping, isTrue);
    expect(histogram.highlightsClipping, isFalse);
  });

  test('blown whites warn for highlight clipping', () {
    final histogram = rgbHistogram(
      rgb: solid(255, 255, 255, 64),
      width: 8,
      height: 8,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    expect(histogram.highlightClipped, 64);
    expect(histogram.highlightsClipping, isTrue);
    expect(histogram.shadowsClipping, isFalse);
  });

  test('single blown channel counts as highlight clip', () {
    final histogram = rgbHistogram(
      rgb: solid(255, 40, 40, 64),
      width: 8,
      height: 8,
      adjustments: PhotoAdjustments.neutral,
      crop: PhotoCrop.full,
    );
    expect(histogram.highlightsClipping, isTrue);
  });

  test('pulling blacks on a dark gray trips shadow clipping', () {
    final histogram = rgbHistogram(
      rgb: solid(36, 36, 36, 256),
      width: 16,
      height: 16,
      adjustments: const PhotoAdjustments(blacks: -100),
      crop: PhotoCrop.full,
    );
    expect(histogram.shadowsClipping, isTrue);
  });
}
