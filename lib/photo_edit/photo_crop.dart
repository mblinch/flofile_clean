import 'dart:ui';

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
}

/// [normAspect] is crop width/height in normalized space. Null is freeform.
/// [dx] and [dy] are the drag since it started, as a fraction of the image.
PhotoCrop dragCrop({
  required PhotoCrop start,
  required CropHandle handle,
  required double dx,
  required double dy,
  double? normAspect,
}) {
  if (handle == CropHandle.move) {
    return PhotoCrop(
      left: (start.left + dx).clamp(0.0, 1 - start.width),
      top: (start.top + dy).clamp(0.0, 1 - start.height),
      width: start.width,
      height: start.height,
    );
  }
  if (normAspect == null || normAspect <= 0) {
    return _freeDrag(start, handle, dx, dy);
  }
  return _aspectDrag(start, handle, dx, dy, normAspect);
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
      return start;
  }

  var w = start.width;
  var h = start.height;
  if (sx != 0 && sy != 0) {
    if (dx.abs() >= dy.abs()) {
      w = start.width + sx * dx;
      h = w / normAspect;
    } else {
      h = start.height + sy * dy;
      w = h * normAspect;
    }
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
  final l = left.clamp(0.0, 1 - min);
  final t = top.clamp(0.0, 1 - min);
  final ww = w.clamp(min, 1 - l);
  final hh = h.clamp(min, 1 - t);
  return PhotoCrop(left: l, top: t, width: ww, height: hh);
}

double mathMin(double a, double b) => a < b ? a : b;

/// Which handle [local] hits, in the overlay's coordinate space.
CropHandle? cropHandleAt(Offset local, Rect crop, {double slop = 22}) {
  bool near(Offset point) => (local - point).distance <= slop;
  final tl = crop.topLeft;
  final tr = crop.topRight;
  final bl = crop.bottomLeft;
  final br = crop.bottomRight;
  if (near(tl)) return CropHandle.topLeft;
  if (near(tr)) return CropHandle.topRight;
  if (near(bl)) return CropHandle.bottomLeft;
  if (near(br)) return CropHandle.bottomRight;
  final insideY = local.dy >= crop.top - slop && local.dy <= crop.bottom + slop;
  final insideX = local.dx >= crop.left - slop && local.dx <= crop.right + slop;
  if ((local.dx - crop.left).abs() <= slop && insideY) return CropHandle.left;
  if ((local.dx - crop.right).abs() <= slop && insideY) return CropHandle.right;
  if ((local.dy - crop.top).abs() <= slop && insideX) return CropHandle.top;
  if ((local.dy - crop.bottom).abs() <= slop && insideX) return CropHandle.bottom;
  if (crop.contains(local)) return CropHandle.move;
  return null;
}
