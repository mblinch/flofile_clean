import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/photo_edit/photo_crop.dart';

void main() {
  test('moving a crop stays inside the frame', () {
    const start = PhotoCrop(left: 0.2, top: 0.2, width: 0.4, height: 0.4);
    final next = dragCrop(
      start: start,
      handle: CropHandle.move,
      dx: 1,
      dy: -1,
    );
    expect(next.left, closeTo(0.6, 0.001));
    expect(next.top, closeTo(0, 0.001));
    expect(next.width, 0.4);
    expect(next.height, 0.4);
  });

  test('free right edge grows the width', () {
    const start = PhotoCrop(left: 0.1, top: 0.1, width: 0.4, height: 0.4);
    final next = dragCrop(
      start: start,
      handle: CropHandle.right,
      dx: 0.2,
      dy: 0,
    );
    expect(next.left, closeTo(0.1, 0.001));
    expect(next.width, closeTo(0.6, 0.001));
  });

  test('largest square is centered', () {
    final crop = PhotoCrop.largest(1);
    expect(crop.left, closeTo(0, 0.001));
    expect(crop.top, closeTo(0, 0.001));
    expect(crop.width, closeTo(1, 0.001));
    expect(crop.height, closeTo(1, 0.001));
  });

  test('largest 1:1 on a wide frame uses the full height', () {
    final crop = PhotoCrop.largest(0.5);
    expect(crop.height, closeTo(1, 0.001));
    expect(crop.width, closeTo(0.5, 0.001));
    expect(crop.left, closeTo(0.25, 0.001));
  });

  test('aspect-locked corner stays on the requested ratio', () {
    const start = PhotoCrop(left: 0.1, top: 0.1, width: 0.4, height: 0.4);
    final next = dragCrop(
      start: start,
      handle: CropHandle.bottomRight,
      dx: 0.2,
      dy: 0,
      normAspect: 1,
    );
    expect(next.width, closeTo(next.height, 0.02));
    expect(next.left, closeTo(0.1, 0.001));
    expect(next.top, closeTo(0.1, 0.001));
    expect(next.width, greaterThan(0.5));
  });

  test('rotated AABB grows with angle', () {
    const rect = Rect.fromLTWH(10, 10, 100, 50);
    final aabb = rotatedAabb(rect, 0.3);
    expect(aabb.width, greaterThan(rect.width));
    expect(aabb.height, greaterThan(rect.height));
    expect(aabb.center.dx, closeTo(rect.center.dx, 0.01));
    expect(aabb.center.dy, closeTo(rect.center.dy, 0.01));
  });

  test('safe straighten crop is centered and inset', () {
    final crop = safeCropForStraighten(imageAspect: 1.5, degrees: 5);
    expect(crop.left, closeTo(crop.left, 0.001));
    expect(crop.left + crop.width, closeTo(1 - crop.left, 0.02));
    expect(crop.top + crop.height, closeTo(1 - crop.top, 0.02));
    expect(crop.width, lessThan(1));
    expect(crop.height, lessThan(1));
  });
}
