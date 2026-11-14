import 'dart:math' as math;
import 'dart:ui';

/// Fine straighten angle range for horizon fixes (degrees, CW positive).
const straightenMinDegrees = -45.0;
const straightenMaxDegrees = 45.0;

/// Axis-aligned bounding box of [rect] after rotating [radians] about its center.
Rect rotatedAabb(Rect rect, double radians) {
  if (rect.isEmpty) return rect;
  final c = rect.center;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  Offset map(Offset p) {
    final d = p - c;
    return Offset(c.dx + d.dx * cos - d.dy * sin, c.dy + d.dx * sin + d.dy * cos);
  }

  final corners = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]
      .map(map);
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in corners) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Centered BoxFit.contain of [inner] inside [viewport].
Rect containRect(Size inner, Size viewport) {
  if (viewport.isEmpty ||
      inner.width <= 0 ||
      inner.height <= 0 ||
      !viewport.width.isFinite ||
      !viewport.height.isFinite) {
    return Rect.zero;
  }
  final scale = math.min(
    viewport.width / inner.width,
    viewport.height / inner.height,
  );
  return Rect.fromCenter(
    center: Offset(viewport.width / 2, viewport.height / 2),
    width: inner.width * scale,
    height: inner.height * scale,
  );
}

/// Upright photo rect and its rotated AABB, scaled so the AABB fits [viewport].
///
/// Keeps the photo a rectangle under straighten (no clipped octagon) and leaves
/// empty AABB bands as stage chrome.
({Rect image, Rect aabb}) fittedStraightenRects({
  required Size viewport,
  required double imageAspect,
  required double degrees,
}) {
  final aspect = imageAspect <= 0 ? 1.5 : imageAspect;
  if (viewport.isEmpty) {
    return (image: Rect.zero, aabb: Rect.zero);
  }
  final rad = degrees * math.pi / 180.0;
  if (rad.abs() <= 1e-6) {
    final image = containRect(Size(aspect, 1), viewport);
    return (image: image, aabb: image);
  }
  final c = math.cos(rad).abs();
  final s = math.sin(rad).abs();
  final unitAabb = Size(aspect * c + s, aspect * s + c);
  final aabbFitted = containRect(unitAabb, viewport);
  if (aabbFitted.isEmpty || unitAabb.width <= 1e-9) {
    return (image: Rect.zero, aabb: Rect.zero);
  }
  final scale = aabbFitted.width / unitAabb.width;
  final image = Rect.fromCenter(
    center: Offset(viewport.width / 2, viewport.height / 2),
    width: aspect * scale,
    height: scale,
  );
  return (image: image, aabb: rotatedAabb(image, rad));
}

/// True when every corner of [crop] (AABB-normalized) lands on source pixels
/// after a CW straighten of [degrees].
bool cropFitsStraightenedSource({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  final aspect = imageAspect <= 0 ? 1.0 : imageAspect;
  final rad = degrees * math.pi / 180.0;
  final c = math.cos(rad);
  final s = math.sin(rad);
  const srcH = 1.0;
  final aabbW = aspect * c.abs() + srcH * s.abs();
  final aabbH = aspect * s.abs() + srcH * c.abs();
  if (aabbW <= 1e-9 || aabbH <= 1e-9) return false;
  const eps = 1e-5;
  bool cornerOk(double nx, double ny) {
    // AABB → center-relative, then inverse CW into upright source (must be
    // the exact inverse of Transform.rotate, or off-centre crops are checked
    // against a mirrored photo).
    final xp = (nx - 0.5) * aabbW;
    final yp = (ny - 0.5) * aabbH;
    final sx = xp * c + yp * s;
    final sy = -xp * s + yp * c;
    return sx.abs() <= aspect / 2 + eps && sy.abs() <= srcH / 2 + eps;
  }

  return cornerOk(crop.left, crop.top) &&
      cornerOk(crop.right, crop.top) &&
      cornerOk(crop.left, crop.bottom) &&
      cornerOk(crop.right, crop.bottom);
}

/// Clamps [requested] so [crop] stays inside the picture while straightening.
///
/// Full-frame crops are not limited here (safe inset is applied separately).
double clampStraightenForCrop({
  required double requested,
  required PhotoCrop crop,
  required double imageAspect,
}) {
  final clamped = clampStraightenDegrees(requested);
  if (crop.isFull || clamped.abs() <= 1e-9) return clamped;
  if (cropFitsStraightenedSource(
    crop: crop,
    imageAspect: imageAspect,
    degrees: clamped,
  )) {
    return clamped;
  }
  final sign = clamped < 0 ? -1.0 : 1.0;
  var lo = 0.0;
  var hi = clamped.abs();
  for (var i = 0; i < 28; i++) {
    final mid = (lo + hi) / 2;
    if (cropFitsStraightenedSource(
      crop: crop,
      imageAspect: imageAspect,
      degrees: sign * mid,
    )) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return sign * lo;
}

/// Keeps [crop] inside the photo: AABB edges always, and real source pixels
/// when straightened (no empty wedges inside the frame).
PhotoCrop constrainCropToSource({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  var w = crop.width;
  var h = crop.height;
  final over = math.max(w, h);
  if (over > 1.0) {
    w /= over;
    h /= over;
  }
  w = w.clamp(PhotoCrop.minSize, 1.0);
  h = h.clamp(PhotoCrop.minSize, 1.0);
  final boxed = PhotoCrop(
    left: crop.left.clamp(0.0, 1.0 - w),
    top: crop.top.clamp(0.0, 1.0 - h),
    width: w,
    height: h,
  );
  if (degrees.abs() <= 1e-9) return boxed;
  if (cropFitsStraightenedSource(
    crop: boxed,
    imageAspect: imageAspect,
    degrees: degrees,
  )) {
    return boxed;
  }
  return shrinkCropToSource(
    crop: boxed,
    imageAspect: imageAspect,
    degrees: degrees,
  );
}

/// Shrinks [crop] toward its center until it lies on source pixels.
///
/// Used so a straightened frame never shows empty AABB wedges (diagonal
/// photo edges) inside the crop.
PhotoCrop shrinkCropToSource({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  if (degrees.abs() <= 1e-9) {
    return constrainCropToSource(
      crop: crop,
      imageAspect: imageAspect,
      degrees: 0,
    );
  }
  if (crop.isFull) {
    return safeCropForStraighten(
      imageAspect: imageAspect,
      degrees: degrees,
    );
  }
  if (cropFitsStraightenedSource(
    crop: crop,
    imageAspect: imageAspect,
    degrees: degrees,
  )) {
    return crop;
  }
  final cx = crop.left + crop.width / 2;
  final cy = crop.top + crop.height / 2;
  var lo = 0.0;
  var hi = 1.0;
  var best = safeCropForStraighten(
    imageAspect: imageAspect,
    degrees: degrees,
  );
  for (var i = 0; i < 28; i++) {
    final mid = (lo + hi) / 2;
    final w = math.max(PhotoCrop.minSize, crop.width * mid);
    final h = math.max(PhotoCrop.minSize, crop.height * mid);
    final candidate = PhotoCrop(
      left: (cx - w / 2).clamp(0.0, 1 - w),
      top: (cy - h / 2).clamp(0.0, 1 - h),
      width: w,
      height: h,
    );
    if (cropFitsStraightenedSource(
      crop: candidate,
      imageAspect: imageAspect,
      degrees: degrees,
    )) {
      best = candidate;
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return best;
}

/// Keeps straighten angle and refits [crop] while staying centered.
///
/// If the current frame still fits, it is left alone. Otherwise the same size
/// is tried centered; if that still overflows source pixels, the frame shrinks
/// toward centre (never slides into a corner/margin).
PhotoCrop refitCropForStraighten({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  if (degrees.abs() <= 1e-9) return crop;
  if (crop.isFull) {
    return safeCropForStraighten(
      imageAspect: imageAspect,
      degrees: degrees,
    );
  }
  if (cropFitsStraightenedSource(
    crop: crop,
    imageAspect: imageAspect,
    degrees: degrees,
  )) {
    return crop;
  }

  final w = crop.width.clamp(PhotoCrop.minSize, 1.0);
  final h = crop.height.clamp(PhotoCrop.minSize, 1.0);
  final centered = PhotoCrop(
    left: (1 - w) / 2,
    top: (1 - h) / 2,
    width: w,
    height: h,
  );
  if (cropFitsStraightenedSource(
    crop: centered,
    imageAspect: imageAspect,
    degrees: degrees,
  )) {
    return centered;
  }

  return shrinkCropToSource(
    crop: centered,
    imageAspect: imageAspect,
    degrees: degrees,
  );
}

/// Width/height of the rotated AABB, in source units (source height = 1).
Size straightenAabbSize(double imageAspect, double degrees) {
  final aspect = imageAspect <= 0 ? 1.0 : imageAspect;
  final rad = degrees * math.pi / 180.0;
  final c = math.cos(rad).abs();
  final s = math.sin(rad).abs();
  return Size(aspect * c + s, aspect * s + c);
}

/// Real pixel width/height of [crop] (crop space is the rotated AABB).
double cropPixelAspect({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  final aabb = straightenAabbSize(imageAspect, degrees);
  final h = crop.height * aabb.height;
  if (h <= 1e-9) return 1;
  return crop.width * aabb.width / h;
}

/// Uniformly scales [crop] about its centre until it fits source pixels.
/// Never changes the crop's aspect ratio.
PhotoCrop shrinkCropKeepingAspect({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  bool fits(PhotoCrop c) => cropFitsStraightenedSource(
        crop: c,
        imageAspect: imageAspect,
        degrees: degrees,
      );
  if (fits(crop)) return crop;
  final cx = crop.left + crop.width / 2;
  final cy = crop.top + crop.height / 2;
  final minDim = math.min(crop.width, crop.height);
  final minScale =
      minDim <= 1e-9 ? 0.0 : math.min(1.0, PhotoCrop.minSize / minDim);
  PhotoCrop at(double scale, {bool recenter = false}) {
    final w = crop.width * scale;
    final h = crop.height * scale;
    final x = recenter ? 0.5 : cx;
    final y = recenter ? 0.5 : cy;
    return PhotoCrop(left: x - w / 2, top: y - h / 2, width: w, height: h);
  }

  for (final recenter in [false, true]) {
    if (!fits(at(minScale, recenter: recenter))) continue;
    var lo = minScale;
    var hi = 1.0;
    for (var i = 0; i < 28; i++) {
      final mid = (lo + hi) / 2;
      if (fits(at(mid, recenter: recenter))) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return at(lo, recenter: recenter);
  }
  return at(minScale, recenter: true);
}

/// Re-expresses [crop] at [toDegrees] keeping its pixel size, pixel aspect,
/// and on-screen position (the photo stays centred on the stage and turns
/// under a still crop box). Straightening must never change the crop's ratio.
PhotoCrop reprojectCropForStraighten({
  required PhotoCrop crop,
  required double imageAspect,
  required double fromDegrees,
  required double toDegrees,
}) {
  final from = straightenAabbSize(imageAspect, fromDegrees);
  final to = straightenAabbSize(imageAspect, toDegrees);
  final pw = crop.width * from.width;
  final ph = crop.height * from.height;
  final ox = (crop.left + crop.width / 2 - 0.5) * from.width;
  final oy = (crop.top + crop.height / 2 - 0.5) * from.height;
  final w = pw / to.width;
  final h = ph / to.height;
  final cx = 0.5 + ox / to.width;
  final cy = 0.5 + oy / to.height;
  return PhotoCrop(left: cx - w / 2, top: cy - h / 2, width: w, height: h);
}

/// Largest centered crop of the expanded AABB that stays on source pixels.
///
/// [imageAspect] is width/height of the upright source. [degrees] is CW.
PhotoCrop safeCropForStraighten({
  required double imageAspect,
  required double degrees,
  double? pixelAspect,
}) {
  final aspect = imageAspect <= 0 ? 1.0 : imageAspect;
  final rad = degrees * math.pi / 180.0;
  final c = math.cos(rad).abs();
  final s = math.sin(rad).abs();
  final w = aspect;
  const h = 1.0;
  final aabbW = w * c + h * s;
  final aabbH = w * s + h * c;
  var innerW = w * c - h * s;
  var innerH = h * c - w * s;
  if (innerW < PhotoCrop.minSize * aabbW || innerH < PhotoCrop.minSize * aabbH) {
    innerW = aabbW * 0.72;
    innerH = aabbH * 0.72;
  }
  var nw = (innerW / aabbW).clamp(PhotoCrop.minSize, 1.0);
  var nh = (innerH / aabbH).clamp(PhotoCrop.minSize, 1.0);
  if (pixelAspect != null && pixelAspect > 0 && aabbH > 0) {
    // pixelAspect = cropPixelW/cropPixelH = (nw*aabbW)/(nh*aabbH)
    // aabb pixel aspect ≈ imageAspect after rotation expansion:
    final aabbAspect = aabbW / aabbH;
    final wantNorm = pixelAspect / aabbAspect;
    if (nw / nh > wantNorm) {
      nw = nh * wantNorm;
    } else {
      nh = nw / wantNorm;
    }
    nw = nw.clamp(PhotoCrop.minSize, 1.0);
    nh = nh.clamp(PhotoCrop.minSize, 1.0);
  }
  return PhotoCrop(
    left: (1 - nw) / 2,
    top: (1 - nh) / 2,
    width: nw,
    height: nh,
  );
}

/// Normalized crop of the oriented photo. 0…1 covers the full frame.
class PhotoCrop {
  const PhotoCrop({
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
  });

  static const full = PhotoCrop();
  static const minSize = 0.08;

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  bool get isFull =>
      left <= 0.0005 &&
      top <= 0.0005 &&
      width >= 0.999 &&
      height >= 0.999;

  /// Largest centered crop whose normalized width/height is [normAspect].
  static PhotoCrop largest(double normAspect) {
    final aspect = normAspect <= 0 ? 1.0 : normAspect;
    var w = 1.0;
    var h = w / aspect;
    if (h > 1) {
      h = 1;
      w = h * aspect;
    }
    return PhotoCrop(
      left: (1 - w) / 2,
      top: (1 - h) / 2,
      width: w,
      height: h,
    );
  }

  Rect rectIn(Rect image) {
    return Rect.fromLTWH(
      image.left + left * image.width,
      image.top + top * image.height,
      width * image.width,
      height * image.height,
    );
  }
}

enum CropHandle {
  move,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  /// Outside the frame (esp. near corners): drag to straighten / rotate.
  rotate,
}

/// [normAspect] is crop width/height in normalized space. When null and
/// [lockRatio] is on, the starting crop's own ratio is kept; with
/// [lockRatio] off, edges and corners reshape freely.
/// [dx] and [dy] are the drag since it started, as a fraction of the image.
///
/// When [straightenDegrees] is non-zero, the result is limited so every crop
/// corner stays on real source pixels (not empty AABB bands). Move drags
/// resolve X/Y separately so a blocked edge still allows diagonal slide.
PhotoCrop dragCrop({
  required PhotoCrop start,
  required CropHandle handle,
  required double dx,
  required double dy,
  double? normAspect,
  double imageAspect = 1.5,
  double straightenDegrees = 0,
  bool lockRatio = true,
}) {
  if (handle == CropHandle.rotate) return start;
  if (handle == CropHandle.move) {
    return constrainCropToSource(
      crop: _moveCrop(
        start: start,
        dx: dx,
        dy: dy,
        imageAspect: imageAspect,
        straightenDegrees: straightenDegrees,
      ),
      imageAspect: imageAspect,
      degrees: straightenDegrees,
    );
  }

  double? lockedAspect;
  if (normAspect != null && normAspect > 0) {
    lockedAspect = normAspect;
  } else if (lockRatio) {
    lockedAspect = start.height > 1e-9 ? start.width / start.height : 1.0;
  } else {
    lockedAspect = null;
  }
  if (lockedAspect != null) {
    lockedAspect = cornerDragOrientation(
      start: start,
      handle: handle,
      dx: dx,
      dy: dy,
      normAspect: lockedAspect,
      imageAspect: imageAspect,
      degrees: straightenDegrees,
    );
  }

  PhotoCrop raw(double tdx, double tdy) => lockedAspect == null
      ? _freeDrag(start, handle, tdx, tdy)
      : _aspectDrag(start, handle, tdx, tdy, lockedAspect);

  bool ok(PhotoCrop crop) {
    if (straightenDegrees.abs() <= 1e-6) return true;
    return cropFitsStraightenedSource(
      crop: crop,
      imageAspect: imageAspect,
      degrees: straightenDegrees,
    );
  }

  PhotoCrop finish(PhotoCrop crop) => constrainCropToSource(
        crop: crop,
        imageAspect: imageAspect,
        degrees: straightenDegrees,
      );

  final full = raw(dx, dy);
  if (ok(full)) return finish(full);

  // Free resize: let the unblocked axis keep going when one side is stopped.
  if (lockedAspect == null) {
    final xOnly = raw(dx, 0);
    final yOnly = raw(0, dy);
    final xOk = ok(xOnly);
    final yOk = ok(yOnly);
    if (xOk && !yOk) return finish(_freeFill(xOnly, (t) => raw(dx, dy * t), ok));
    if (yOk && !xOk) return finish(_freeFill(yOnly, (t) => raw(dx * t, dy), ok));
  }

  // Opposite corner stays pinned; grow until the dragged side meets the photo.
  var lo = 0.0;
  var hi = 1.0;
  var best = start;
  for (var i = 0; i < 28; i++) {
    final mid = (lo + hi) / 2;
    final candidate = raw(dx * mid, dy * mid);
    if (ok(candidate)) {
      best = candidate;
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return finish(best);
}

/// Move with per-axis clamping so a hard bottom/side edge doesn't kill the
/// other axis of a diagonal drag.
PhotoCrop _moveCrop({
  required PhotoCrop start,
  required double dx,
  required double dy,
  required double imageAspect,
  required double straightenDegrees,
}) {
  final maxL = 1 - start.width;
  final maxT = 1 - start.height;
  PhotoCrop at(double left, double top) => PhotoCrop(
        left: left.clamp(0.0, maxL),
        top: top.clamp(0.0, maxT),
        width: start.width,
        height: start.height,
      );

  bool ok(PhotoCrop crop) {
    if (straightenDegrees.abs() <= 1e-6) return true;
    return cropFitsStraightenedSource(
      crop: crop,
      imageAspect: imageAspect,
      degrees: straightenDegrees,
    );
  }

  final targetL = (start.left + dx).clamp(0.0, maxL);
  final targetT = (start.top + dy).clamp(0.0, maxT);
  final target = at(targetL, targetT);
  if (ok(target)) return target;

  PhotoCrop slide({
    required double fromL,
    required double fromT,
    required double toL,
    required double toT,
  }) {
    var lo = 0.0;
    var hi = 1.0;
    var best = at(fromL, fromT);
    for (var i = 0; i < 28; i++) {
      final mid = (lo + hi) / 2;
      final candidate = at(
        fromL + (toL - fromL) * mid,
        fromT + (toT - fromT) * mid,
      );
      if (ok(candidate)) {
        best = candidate;
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return best;
  }

  // X then Y — keeps sideways motion when vertical is blocked.
  final afterX = slide(
    fromL: start.left,
    fromT: start.top,
    toL: targetL,
    toT: start.top,
  );
  final pathA = slide(
    fromL: afterX.left,
    fromT: afterX.top,
    toL: afterX.left,
    toT: targetT,
  );

  // Y then X — keeps vertical motion when horizontal is blocked.
  final afterY = slide(
    fromL: start.left,
    fromT: start.top,
    toL: start.left,
    toT: targetT,
  );
  final pathB = slide(
    fromL: afterY.left,
    fromT: afterY.top,
    toL: targetL,
    toT: afterY.top,
  );

  double score(PhotoCrop crop) =>
      (crop.left - targetL).abs() + (crop.top - targetT).abs();
  return score(pathA) <= score(pathB) ? pathA : pathB;
}

/// Normalized aspect for a locked corner drag, flipped portrait ↔ landscape
/// when the pointer box clearly turns the other way (Lightroom-style).
double cornerDragOrientation({
  required PhotoCrop start,
  required CropHandle handle,
  required double dx,
  required double dy,
  required double normAspect,
  required double imageAspect,
  required double degrees,
}) {
  final int sx;
  final int sy;
  switch (handle) {
    case CropHandle.topLeft:
      sx = -1;
      sy = -1;
    case CropHandle.topRight:
      sx = 1;
      sy = -1;
    case CropHandle.bottomLeft:
      sx = -1;
      sy = 1;
    case CropHandle.bottomRight:
      sx = 1;
      sy = 1;
    default:
      return normAspect;
  }
  final aabb = straightenAabbSize(imageAspect, degrees);
  final k = aabb.height <= 1e-9 ? 1.0 : aabb.width / aabb.height;
  final pixel = normAspect * k;
  if ((math.log(pixel)).abs() < 0.02) return normAspect;
  final wPtr = start.width + sx * dx;
  final hPtr = start.height + sy * dy;
  if (wPtr <= 1e-4 || hPtr <= 1e-4) return normAspect;
  final pointer = math.log(wPtr * k / hPtr);
  // Dead zone near square so it doesn't flicker.
  if (pointer.abs() < 0.12) return normAspect;
  if ((pointer > 0) == (pixel > 1)) return normAspect;
  return (1 / pixel) / k;
}

/// Width/height swapped (portrait ↔ landscape) about the same centre, kept
/// on the photo. Pixel ratio is inverted exactly.
PhotoCrop swapCropOrientation({
  required PhotoCrop crop,
  required double imageAspect,
  required double degrees,
}) {
  final aabb = straightenAabbSize(imageAspect, degrees);
  final pw = crop.width * aabb.width;
  final ph = crop.height * aabb.height;
  final w = ph / aabb.width;
  final h = pw / aabb.height;
  final cx = crop.left + crop.width / 2;
  final cy = crop.top + crop.height / 2;
  final over = math.max(1.0, math.max(w, h));
  final ww = w / over;
  final hh = h / over;
  final boxed = PhotoCrop(
    left: (cx - ww / 2).clamp(0.0, 1 - ww),
    top: (cy - hh / 2).clamp(0.0, 1 - hh),
    width: ww,
    height: hh,
  );
  if (degrees.abs() <= 1e-9) return boxed;
  return shrinkCropKeepingAspect(
    crop: boxed,
    imageAspect: imageAspect,
    degrees: degrees,
  );
}

/// Largest fraction t in 0…1 where [at] still fits, starting from [base].
PhotoCrop _freeFill(
  PhotoCrop base,
  PhotoCrop Function(double t) at,
  bool Function(PhotoCrop crop) ok,
) {
  var lo = 0.0;
  var hi = 1.0;
  var best = base;
  for (var i = 0; i < 28; i++) {
    final mid = (lo + hi) / 2;
    final candidate = at(mid);
    if (ok(candidate)) {
      best = candidate;
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return best;
}

PhotoCrop _freeDrag(PhotoCrop start, CropHandle handle, double dx, double dy) {
  var left = start.left;
  var top = start.top;
  var right = start.right;
  var bottom = start.bottom;

  void setLeft(double v) => left = v.clamp(0.0, right - PhotoCrop.minSize);
  void setRight(double v) => right = v.clamp(left + PhotoCrop.minSize, 1.0);
  void setTop(double v) => top = v.clamp(0.0, bottom - PhotoCrop.minSize);
  void setBottom(double v) => bottom = v.clamp(top + PhotoCrop.minSize, 1.0);

  switch (handle) {
    case CropHandle.left:
      setLeft(start.left + dx);
    case CropHandle.right:
      setRight(start.right + dx);
    case CropHandle.top:
      setTop(start.top + dy);
    case CropHandle.bottom:
      setBottom(start.bottom + dy);
    case CropHandle.topLeft:
      setLeft(start.left + dx);
      setTop(start.top + dy);
    case CropHandle.topRight:
      setRight(start.right + dx);
      setTop(start.top + dy);
    case CropHandle.bottomLeft:
      setLeft(start.left + dx);
      setBottom(start.bottom + dy);
    case CropHandle.bottomRight:
      setRight(start.right + dx);
      setBottom(start.bottom + dy);
    case CropHandle.move:
    case CropHandle.rotate:
      break;
  }
  return PhotoCrop(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}

PhotoCrop _aspectDrag(
  PhotoCrop start,
  CropHandle handle,
  double dx,
  double dy,
  double normAspect,
) {
  const min = PhotoCrop.minSize;
  late final double ax;
  late final double ay;
  late final int sx;
  late final int sy;
  switch (handle) {
    case CropHandle.bottomRight:
      ax = start.left;
      ay = start.top;
      sx = 1;
      sy = 1;
    case CropHandle.bottomLeft:
      ax = start.right;
      ay = start.top;
      sx = -1;
      sy = 1;
    case CropHandle.topRight:
      ax = start.left;
      ay = start.bottom;
      sx = 1;
      sy = -1;
    case CropHandle.topLeft:
      ax = start.right;
      ay = start.bottom;
      sx = -1;
      sy = -1;
    case CropHandle.right:
      ax = start.left;
      ay = start.top + start.height / 2;
      sx = 1;
      sy = 0;
    case CropHandle.left:
      ax = start.right;
      ay = start.top + start.height / 2;
      sx = -1;
      sy = 0;
    case CropHandle.bottom:
      ax = start.left + start.width / 2;
      ay = start.top;
      sx = 0;
      sy = 1;
    case CropHandle.top:
      ax = start.left + start.width / 2;
      ay = start.bottom;
      sx = 0;
      sy = -1;
    case CropHandle.move:
    case CropHandle.rotate:
      return start;
  }

  var w = start.width;
  var h = start.height;
  if (sx != 0 && sy != 0) {
    // Smallest box of this ratio that reaches the pointer (works the same
    // after an orientation flip, where the start size no longer matches).
    final wPtr = math.max(0.0, start.width + sx * dx);
    final hPtr = math.max(0.0, start.height + sy * dy);
    w = math.max(wPtr, hPtr * normAspect);
    h = w / normAspect;
  } else if (sx != 0) {
    w = start.width + sx * dx;
    h = w / normAspect;
  } else {
    h = start.height + sy * dy;
    w = h * normAspect;
  }

  final maxW = sx > 0 ? (1 - ax) : (sx < 0 ? ax : double.infinity);
  final maxH = sy > 0
      ? (1 - ay)
      : (sy < 0 ? ay : mathMin(ay, 1 - ay) * 2);
  w = w.clamp(min, maxW.isFinite ? maxW : 1);
  h = h.clamp(min, maxH.isFinite ? maxH : 1);
  if (w / h > normAspect) {
    w = h * normAspect;
  } else {
    h = w / normAspect;
  }
  if (maxW.isFinite && w > maxW) {
    w = maxW;
    h = w / normAspect;
  }
  if (maxH.isFinite && h > maxH) {
    h = maxH;
    w = h * normAspect;
  }

  final left = sx > 0 ? ax : (sx < 0 ? ax - w : ax - w / 2);
  final top = sy > 0 ? ay : (sy < 0 ? ay - h : ay - h / 2);
  var l = left.clamp(0.0, 1 - min);
  var t = top.clamp(0.0, 1 - min);
  var ww = w;
  var hh = h;
  // Fit inside the remaining frame first, then re-lock aspect so corner
  // clamps never skew the ratio (and both dims stay ≥ min).
  final maxWw = math.max(min, 1 - l);
  final maxHh = math.max(min, 1 - t);
  if (ww > maxWw) {
    ww = maxWw;
    hh = ww / normAspect;
  }
  if (hh > maxHh) {
    hh = maxHh;
    ww = hh * normAspect;
  }
  if (ww > maxWw) {
    ww = maxWw;
    hh = ww / normAspect;
  }
  if (ww < min || hh < min) {
    // Grow to the smallest size that satisfies min on both axes.
    final needW = math.max(min, min * normAspect);
    final needH = math.max(min, min / normAspect);
    ww = needW;
    hh = needH;
  }
  if (l + ww > 1) l = math.max(0.0, 1 - ww);
  if (t + hh > 1) t = math.max(0.0, 1 - hh);
  return PhotoCrop(left: l, top: t, width: ww, height: hh);
}

double mathMin(double a, double b) => a < b ? a : b;

double clampStraightenDegrees(double degrees) =>
    degrees.clamp(straightenMinDegrees, straightenMaxDegrees);

/// Centre of the permanent rotate handle outside a crop corner.
///
/// [ox]/[oy] are −1/1 for the outward diagonal (e.g. top-left → −1,−1).
const cropRotateHandleOffset = 26.0;
const cropRotateHandleHitRadius = 16.0;

Offset cropRotateHandleCenter(Offset corner, double ox, double oy) {
  final along = Offset(ox, oy);
  final len = along.distance;
  if (len < 1e-9) return corner;
  return corner + along * (cropRotateHandleOffset / len);
}

/// All four permanent rotate-handle centres for [crop].
Map<CropHandle, Offset> cropRotateHandleCenters(Rect crop) {
  return {
    CropHandle.topLeft: cropRotateHandleCenter(crop.topLeft, -1, -1),
    CropHandle.topRight: cropRotateHandleCenter(crop.topRight, 1, -1),
    CropHandle.bottomLeft: cropRotateHandleCenter(crop.bottomLeft, -1, 1),
    CropHandle.bottomRight: cropRotateHandleCenter(crop.bottomRight, 1, 1),
  };
}

/// Which handle [local] hits, in the overlay's coordinate space.
///
/// Corner resize first, then the permanent rotate handles (and a short
/// diagonal band around them). Edge/move next. Everything else outside the
/// box rotates, however far away.
CropHandle? cropHandleAt(Offset local, Rect crop, {double slop = 26}) {
  final tl = crop.topLeft;
  final tr = crop.topRight;
  final bl = crop.bottomLeft;
  final br = crop.bottomRight;

  // Corner resize — leave room so rotate handles can start sooner.
  const cornerSlop = 16.0;
  // Soft band around the permanent handles (handles themselves are primary).
  const rotateMin = 16.0;
  const rotateMax = 48.0;
  // |dx|/|dy| (or inverse) must be at least this → ~22° off-axis, ~45° cone.
  const diagonalMinRatio = 0.35;

  bool nearCorner(Offset point) => (local - point).distance <= cornerSlop;
  // 1) Crop resize at the corner.
  if (nearCorner(tl)) return CropHandle.topLeft;
  if (nearCorner(tr)) return CropHandle.topRight;
  if (nearCorner(bl)) return CropHandle.bottomLeft;
  if (nearCorner(br)) return CropHandle.bottomRight;

  // 2) Permanent rotate handles just outside each corner.
  for (final entry in cropRotateHandleCenters(crop).entries) {
    if ((local - entry.value).distance <= cropRotateHandleHitRadius) {
      return CropHandle.rotate;
    }
  }

  // 3) Soft diagonal band (same corners) so the zone feels continuous.
  bool rotateCorner(Offset corner, double ox, double oy) {
    final d = local - corner;
    final dist = d.distance;
    if (dist < rotateMin || dist > rotateMax) return false;
    // Strictly both axes outward — keeps edge resize free.
    if (d.dx * ox <= 0 || d.dy * oy <= 0) return false;
    final ax = d.dx.abs();
    final ay = d.dy.abs();
    final ratio = ax < ay ? ax / ay : ay / ax;
    return ratio >= diagonalMinRatio;
  }

  if (rotateCorner(tl, -1, -1) ||
      rotateCorner(tr, 1, -1) ||
      rotateCorner(bl, -1, 1) ||
      rotateCorner(br, 1, 1)) {
    return CropHandle.rotate;
  }

  final insideY = local.dy >= crop.top - slop && local.dy <= crop.bottom + slop;
  final insideX = local.dx >= crop.left - slop && local.dx <= crop.right + slop;
  if ((local.dx - crop.left).abs() <= slop && insideY) return CropHandle.left;
  if ((local.dx - crop.right).abs() <= slop && insideY) return CropHandle.right;
  if ((local.dy - crop.top).abs() <= slop && insideX) return CropHandle.top;
  if ((local.dy - crop.bottom).abs() <= slop && insideX) return CropHandle.bottom;
  // Inside the frame, or on the dimmed picture outside it: pan the photo.
  // Rotate stays on the dedicated corner handles / diagonal bands above.
  return CropHandle.move;
}
