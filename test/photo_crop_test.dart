import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/photo_edit/photo_crop.dart';

/// Maps an AABB-normalized point into upright source pixels (height 1),
/// using the exact inverse of the on-screen [Transform.rotate].
Offset _toSource(double nx, double ny, double image, double deg) {
  final rad = deg * math.pi / 180.0;
  final c = math.cos(rad);
  final s = math.sin(rad);
  final aabbW = image * c.abs() + s.abs();
  final aabbH = image * s.abs() + c.abs();
  final x = (nx - 0.5) * aabbW;
  final y = (ny - 0.5) * aabbH;
  return Offset(x * c + y * s, -x * s + y * c);
}

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

  test('right edge grows the width and keeps the ratio', () {
    const start = PhotoCrop(left: 0.1, top: 0.2, width: 0.4, height: 0.4);
    final next = dragCrop(
      start: start,
      handle: CropHandle.right,
      dx: 0.2,
      dy: 0,
    );
    expect(next.left, closeTo(0.1, 0.001));
    expect(next.width, closeTo(0.6, 0.001));
    expect(next.height, closeTo(0.6, 0.001));
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

  test('freeform corner drag keeps the starting aspect ratio', () {
    const start = PhotoCrop(left: 0.2, top: 0.1, width: 0.4, height: 0.2);
    final next = dragCrop(
      start: start,
      handle: CropHandle.bottomRight,
      dx: 0.15,
      dy: 0.2,
      normAspect: null,
    );
    expect(next.width / next.height, closeTo(start.width / start.height, 0.02));
    expect(next.left, closeTo(0.2, 0.001));
    expect(next.top, closeTo(0.1, 0.001));
    expect(next.width, greaterThan(start.width));
  });

  test('off-centre corner drag reaches the real straightened photo edge', () {
    const image = 1.5;
    for (final deg in [-20.0, 20.0]) {
      const start = PhotoCrop(left: 0.42, top: 0.42, width: 0.2, height: 0.14);
      expect(
        cropFitsStraightenedSource(crop: start, imageAspect: image, degrees: deg),
        isTrue,
      );
      final next = dragCrop(
        start: start,
        handle: CropHandle.bottomRight,
        dx: 0.6,
        dy: 0.6,
        imageAspect: image,
        straightenDegrees: deg,
      );
      expect(next.left, closeTo(start.left, 1e-9));
      expect(next.top, closeTo(start.top, 1e-9));
      expect(
        next.width / next.height,
        closeTo(start.width / start.height, 1e-9),
      );
      // Every corner is on the photo as drawn, and at least one touches its
      // edge (the drag went all the way to the edge, not short of it).
      var slack = double.infinity;
      for (final p in [
        _toSource(next.left, next.top, image, deg),
        _toSource(next.right, next.top, image, deg),
        _toSource(next.left, next.bottom, image, deg),
        _toSource(next.right, next.bottom, image, deg),
      ]) {
        final sx = image / 2 - p.dx.abs();
        final sy = 0.5 - p.dy.abs();
        expect(sx, greaterThanOrEqualTo(-1e-4));
        expect(sy, greaterThanOrEqualTo(-1e-4));
        slack = math.min(slack, math.min(sx, sy));
      }
      expect(slack, lessThan(1e-3));
    }
  });

  test('straighten reprojection never changes the crop pixel aspect', () {
    const image = 1.5;
    const start = PhotoCrop(left: 0.3, top: 0.3, width: 0.3, height: 0.25);
    final startAspect =
        cropPixelAspect(crop: start, imageAspect: image, degrees: 0);
    var crop = start;
    var deg = 0.0;
    for (final next in [3.0, 8.0, -6.0, 12.0, 0.0]) {
      crop = shrinkCropKeepingAspect(
        crop: reprojectCropForStraighten(
          crop: crop,
          imageAspect: image,
          fromDegrees: deg,
          toDegrees: next,
        ),
        imageAspect: image,
        degrees: next,
      );
      deg = next;
      expect(
        cropPixelAspect(crop: crop, imageAspect: image, degrees: deg),
        closeTo(startAspect, 0.001),
      );
      expect(
        cropFitsStraightenedSource(
          crop: crop,
          imageAspect: image,
          degrees: deg,
        ),
        isTrue,
      );
    }
  });

  test('straighten keeps the crop box still on screen', () {
    const image = 1.5;
    const start = PhotoCrop(left: 0.55, top: 0.2, width: 0.25, height: 0.2);
    // Stage-pixel centre offset from the photo centre (photo height = 1).
    Offset screen(PhotoCrop c, double deg) {
      final aabb = straightenAabbSize(image, deg);
      return Offset(
        (c.left + c.width / 2 - 0.5) * aabb.width,
        (c.top + c.height / 2 - 0.5) * aabb.height,
      );
    }

    final next = reprojectCropForStraighten(
      crop: start,
      imageAspect: image,
      fromDegrees: 4,
      toDegrees: -9,
    );
    final before = screen(start, 4);
    final after = screen(next, -9);
    expect(after.dx, closeTo(before.dx, 1e-9));
    expect(after.dy, closeTo(before.dy, 1e-9));
  });

  test('unlocked ratio lets edges and corners reshape', () {
    const start = PhotoCrop(left: 0.2, top: 0.2, width: 0.4, height: 0.3);
    final edge = dragCrop(
      start: start,
      handle: CropHandle.right,
      dx: 0.2,
      dy: 0,
      lockRatio: false,
    );
    expect(edge.height, closeTo(start.height, 1e-9));
    expect(edge.width, closeTo(0.6, 1e-9));
    final corner = dragCrop(
      start: start,
      handle: CropHandle.bottomRight,
      dx: 0.05,
      dy: 0.3,
      lockRatio: false,
    );
    expect(corner.width, closeTo(0.45, 1e-9));
    expect(corner.height, closeTo(0.6, 1e-9));
  });

  test('unlocked straightened drag stays on the photo', () {
    const image = 1.5;
    const deg = 8.0;
    const start = PhotoCrop(left: 0.4, top: 0.4, width: 0.2, height: 0.2);
    final next = dragCrop(
      start: start,
      handle: CropHandle.bottomRight,
      dx: 0.6,
      dy: 0.1,
      imageAspect: image,
      straightenDegrees: deg,
      lockRatio: false,
    );
    expect(next.width, greaterThan(start.width));
    expect(
      cropFitsStraightenedSource(crop: next, imageAspect: image, degrees: deg),
      isTrue,
    );
  });

  test('locked corner drag flips to portrait when pulled tall', () {
    const image = 1.5;
    // 3:2 landscape crop in pixels.
    const start = PhotoCrop(left: 0.3, top: 0.3, width: 0.3, height: 0.3);
    final startPixel =
        cropPixelAspect(crop: start, imageAspect: image, degrees: 0);
    expect(startPixel, closeTo(1.5, 1e-9));
    final tall = dragCrop(
      start: start,
      handle: CropHandle.bottomRight,
      dx: -0.15,
      dy: 0.3,
      imageAspect: image,
    );
    final tallPixel =
        cropPixelAspect(crop: tall, imageAspect: image, degrees: 0);
    expect(tallPixel, closeTo(1 / 1.5, 1e-9));
    expect(tall.left, closeTo(start.left, 1e-9));
    expect(tall.top, closeTo(start.top, 1e-9));
  });

  test('swap orientation inverts the pixel ratio and stays on the photo', () {
    const image = 1.5;
    for (final deg in [0.0, 7.0]) {
      final start = shrinkCropKeepingAspect(
        crop: const PhotoCrop(left: 0.25, top: 0.3, width: 0.5, height: 0.3),
        imageAspect: image,
        degrees: deg,
      );
      final before =
          cropPixelAspect(crop: start, imageAspect: image, degrees: deg);
      final swapped = swapCropOrientation(
        crop: start,
        imageAspect: image,
        degrees: deg,
      );
      final after =
          cropPixelAspect(crop: swapped, imageAspect: image, degrees: deg);
      expect(after, closeTo(1 / before, 1e-6));
      expect(
        cropFitsStraightenedSource(
          crop: swapped,
          imageAspect: image,
          degrees: deg,
        ),
        isTrue,
      );
    }
  });

  test('freeform edge drag keeps the ratio', () {
    const start = PhotoCrop(left: 0.2, top: 0.2, width: 0.4, height: 0.3);
    final next = dragCrop(
      start: start,
      handle: CropHandle.right,
      dx: 0.2,
      dy: 0,
      normAspect: null,
    );
    expect(next.width, greaterThan(start.width + 0.1));
    expect(next.width / next.height, closeTo(start.width / start.height, 1e-9));
  });

  test('rotated AABB grows with angle', () {
    const rect = Rect.fromLTWH(10, 10, 100, 50);
    final aabb = rotatedAabb(rect, 0.3);
    expect(aabb.width, greaterThan(rect.width));
    expect(aabb.height, greaterThan(rect.height));
    expect(aabb.center.dx, closeTo(rect.center.dx, 0.01));
    expect(aabb.center.dy, closeTo(rect.center.dy, 0.01));
  });

  test('fitted straighten keeps AABB inside the viewport', () {
    const viewport = Size(400, 300);
    final fitted = fittedStraightenRects(
      viewport: viewport,
      imageAspect: 1.5,
      degrees: 35,
    );
    expect(fitted.aabb.left, greaterThanOrEqualTo(-0.01));
    expect(fitted.aabb.top, greaterThanOrEqualTo(-0.01));
    expect(fitted.aabb.right, lessThanOrEqualTo(viewport.width + 0.01));
    expect(fitted.aabb.bottom, lessThanOrEqualTo(viewport.height + 0.01));
    expect(fitted.image.width, lessThan(fitted.aabb.width + 0.01));
    expect(
      fitted.aabb.width,
      closeTo(rotatedAabb(fitted.image, 35 * 3.141592653589793 / 180).width, 0.5),
    );
  });

  test('safe straighten crop is centered and inset', () {
    final crop = safeCropForStraighten(imageAspect: 1.5, degrees: 5);
    expect(crop.left, closeTo(crop.left, 0.001));
    expect(crop.left + crop.width, closeTo(1 - crop.left, 0.02));
    expect(crop.top + crop.height, closeTo(1 - crop.top, 0.02));
    expect(crop.width, lessThan(1));
    expect(crop.height, lessThan(1));
  });

  test('straighten clamp keeps a framed crop inside the picture', () {
    const crop = PhotoCrop(left: 0.1, top: 0.1, width: 0.8, height: 0.8);
    expect(
      cropFitsStraightenedSource(
        crop: crop,
        imageAspect: 1.5,
        degrees: 0,
      ),
      isTrue,
    );
    expect(
      cropFitsStraightenedSource(
        crop: crop,
        imageAspect: 1.5,
        degrees: 40,
      ),
      isFalse,
    );
    final limited = clampStraightenForCrop(
      requested: 40,
      crop: crop,
      imageAspect: 1.5,
    );
    expect(limited.abs(), lessThan(40));
    expect(
      cropFitsStraightenedSource(
        crop: crop,
        imageAspect: 1.5,
        degrees: limited,
      ),
      isTrue,
    );
  });

  test('crop drag cannot leave source pixels while straightened', () {
    final start = safeCropForStraighten(imageAspect: 1.5, degrees: 12);
    final pushed = dragCrop(
      start: start,
      handle: CropHandle.move,
      dx: -0.5,
      dy: -0.5,
      imageAspect: 1.5,
      straightenDegrees: 12,
    );
    expect(
      cropFitsStraightenedSource(
        crop: pushed,
        imageAspect: 1.5,
        degrees: 12,
      ),
      isTrue,
    );
    // Would sit in an empty AABB corner without the pixel clamp.
    expect(pushed.left, greaterThan(0));
    expect(pushed.top, greaterThan(0));
  });

  test('constrain crop never leaves the image edges', () {
    const loose = PhotoCrop(left: -0.2, top: 0.8, width: 1.4, height: 0.5);
    final boxed = constrainCropToSource(
      crop: loose,
      imageAspect: 1.5,
      degrees: 0,
    );
    expect(boxed.left, greaterThanOrEqualTo(0));
    expect(boxed.top, greaterThanOrEqualTo(0));
    expect(boxed.right, lessThanOrEqualTo(1.0001));
    expect(boxed.bottom, lessThanOrEqualTo(1.0001));

    final angled = constrainCropToSource(
      crop: const PhotoCrop(left: 0, top: 0, width: 1, height: 1),
      imageAspect: 1.5,
      degrees: 20,
    );
    expect(
      cropFitsStraightenedSource(
        crop: angled,
        imageAspect: 1.5,
        degrees: 20,
      ),
      isTrue,
    );
  });

  test('shrink crop removes straightened AABB wedges', () {
    const loose = PhotoCrop(left: 0, top: 0, width: 1, height: 1);
    final tight = shrinkCropToSource(
      crop: loose,
      imageAspect: 1.5,
      degrees: 15,
    );
    expect(tight.isFull, isFalse);
    expect(
      cropFitsStraightenedSource(
        crop: tight,
        imageAspect: 1.5,
        degrees: 15,
      ),
      isTrue,
    );
  });

  test('refit recenters instead of sliding into margins', () {
    const crop = PhotoCrop(left: 0.05, top: 0.05, width: 0.7, height: 0.7);
    const degrees = 12.0;
    expect(
      cropFitsStraightenedSource(
        crop: crop,
        imageAspect: 1.5,
        degrees: degrees,
      ),
      isFalse,
    );
    final fitted = refitCropForStraighten(
      crop: crop,
      imageAspect: 1.5,
      degrees: degrees,
    );
    expect(
      cropFitsStraightenedSource(
        crop: fitted,
        imageAspect: 1.5,
        degrees: degrees,
      ),
      isTrue,
    );
    // Stays centered in the AABB.
    expect(fitted.left + fitted.width / 2, closeTo(0.5, 0.02));
    expect(fitted.top + fitted.height / 2, closeTo(0.5, 0.02));
    expect(fitted.width, greaterThan(0.3));
    expect(fitted.height, greaterThan(0.3));
  });

  test('small straighten recenters and keeps crop size when possible', () {
    const crop = PhotoCrop(left: 0.05, top: 0.05, width: 0.7, height: 0.7);
    final fitted = refitCropForStraighten(
      crop: crop,
      imageAspect: 1.5,
      degrees: 3,
    );
    expect(fitted.width, closeTo(0.7, 0.001));
    expect(fitted.height, closeTo(0.7, 0.001));
    expect(fitted.left, closeTo(0.15, 0.001));
    expect(fitted.top, closeTo(0.15, 0.001));
    expect(
      cropFitsStraightenedSource(
        crop: fitted,
        imageAspect: 1.5,
        degrees: 3,
      ),
      isTrue,
    );
  });

  test('diagonal move still slides when one axis is hard against the edge', () {
    // Crop parked on the AABB bottom; diagonal up-right must still move right
    // even if further-down is impossible.
    const start = PhotoCrop(left: 0.2, top: 0.55, width: 0.4, height: 0.45);
    final next = dragCrop(
      start: start,
      handle: CropHandle.move,
      dx: 0.3,
      dy: 0.3,
      imageAspect: 1.5,
      straightenDegrees: 0,
    );
    expect(next.top, closeTo(0.55, 0.001)); // clamped at bottom
    expect(next.left, closeTo(0.5, 0.001)); // horizontal still applied
    expect(next.width, 0.4);
    expect(next.height, 0.45);
  });

  test('outside a crop corner is a rotate handle', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    final handle = cropHandleAt(const Offset(70, 70), crop);
    expect(handle, CropHandle.rotate);
  });

  test('permanent rotate handle centre is a rotate hit', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    final centers = cropRotateHandleCenters(crop);
    expect(cropHandleAt(centers[CropHandle.topLeft]!, crop), CropHandle.rotate);
    expect(
      cropHandleAt(centers[CropHandle.bottomRight]!, crop),
      CropHandle.rotate,
    );
  });

  test('a little past a crop corner is a rotate handle', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    // Just past cornerSlop (~16), on ~45° — rotate starts sooner.
    expect(cropHandleAt(const Offset(86, 86), crop), CropHandle.rotate);
    expect(cropHandleAt(const Offset(314, 86), crop), CropHandle.rotate);
  });

  test('on a crop corner is still a resize handle', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    expect(cropHandleAt(const Offset(100, 100), crop), CropHandle.topLeft);
    // Still inside corner hit, not rotate.
    expect(cropHandleAt(const Offset(90, 90), crop), CropHandle.topLeft);
    expect(cropHandleAt(const Offset(88, 100), crop), CropHandle.topLeft);
  });

  test('just outside an edge still resizes that edge', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    expect(cropHandleAt(const Offset(80, 200), crop), CropHandle.left);
    expect(cropHandleAt(const Offset(200, 320), crop), CropHandle.bottom);
  });

  test('far outside the box pans the picture (rotate is corner handles only)',
      () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);
    expect(cropHandleAt(const Offset(20, 200), crop), CropHandle.move);
    expect(cropHandleAt(const Offset(200, 20), crop), CropHandle.move);
    expect(cropHandleAt(const Offset(900, 700), crop), CropHandle.move);
    expect(cropHandleAt(const Offset(-400, 150), crop), CropHandle.move);
    // Interior still moves.
    expect(cropHandleAt(const Offset(200, 200), crop), CropHandle.move);
  });
}
