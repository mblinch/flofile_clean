import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/oriented_image_bytes.dart';
import 'crop_cursors.dart';
import 'photo_crop.dart';
import 'photo_edit_session.dart';

/// Dims outside the crop and lets the frame be dragged.
class PhotoCropOverlay extends StatefulWidget {
  const PhotoCropOverlay({
    super.key,
    required this.session,
    required this.path,
    required this.version,
    required this.fit,
    this.interactive = true,
    this.onChromeSecondaryTap,
  });

  final PhotoEditSession session;
  final String path;
  final int version;
  final BoxFit fit;

  /// When false, draws the frame only (used after leaving crop tool).
  final bool interactive;

  /// Right-click on stage chrome (letterbox behind the photo), not the image.
  final ValueChanged<Offset>? onChromeSecondaryTap;

  @override
  State<PhotoCropOverlay> createState() => _PhotoCropOverlayState();
}

class _PhotoCropOverlayState extends State<PhotoCropOverlay> {
  Size? _imageSize;
  int _token = 0;
  /// Small RGBA buffer for picking guide color against local luminance.
  ByteData? _sampleRgba;
  int _sampleW = 0;
  int _sampleH = 0;
  CropHandle? _handle;
  PhotoCrop? _origin;
  Offset? _panStart;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  bool _didDrag = false;
  double? _rotateOriginDegrees;
  double? _rotateStartRadians;
  Offset? _rotateCenter;
  Size? _panSpaceSize;
  CropHandle? _hoverHandle;
  Offset? _pointer;
  /// Pointer-only updates for the SVG cursor (avoids rebuilding the crop frame).
  final ValueNotifier<Offset?> _pointerTick = ValueNotifier<Offset?>(null);
  /// Which crop corner the rotate zone is nearest (for cursor orientation).
  CropHandle _rotateCorner = CropHandle.bottomRight;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  @override
  void dispose() {
    _pointerTick.dispose();
    super.dispose();
  }

  void _setPointer(Offset? local, {bool rebuild = false}) {
    _pointer = local;
    _pointerTick.value = local;
    if (rebuild && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PhotoCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.version != widget.version) {
      _loadSize();
    }
  }

  Future<void> _loadSize() async {
    final token = ++_token;
    final bytes = await OrientedImageBytes.load(
      widget.path,
      maxWidth: 480,
      priority: true,
    );
    if (!mounted || token != _token || bytes == null) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final sw = image.width;
    final sh = image.height;
    image.dispose();
    if (!mounted || token != _token || size.isEmpty) return;
    setState(() {
      _imageSize = size;
      _sampleRgba = rgba;
      _sampleW = sw;
      _sampleH = sh;
    });
    widget.session.noteImageAspect(widget.path, size.width / size.height);
  }

  /// White guides on dark edges, black on bright — sampled along the crop rim.
  Color _guideColorFor(PhotoCrop crop) {
    final data = _sampleRgba;
    final w = _sampleW;
    final h = _sampleH;
    if (data == null || w <= 1 || h <= 1) return Colors.white;

    var sum = 0.0;
    var n = 0;
    void sample(double nx, double ny) {
      final x = (nx.clamp(0.0, 1.0) * (w - 1)).round();
      final y = (ny.clamp(0.0, 1.0) * (h - 1)).round();
      final i = (y * w + x) * 4;
      if (i + 2 >= data.lengthInBytes) return;
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      n++;
    }

    const steps = 14;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      sample(crop.left + crop.width * t, crop.top);
      sample(crop.left + crop.width * t, crop.bottom);
      sample(crop.left, crop.top + crop.height * t);
      sample(crop.right, crop.top + crop.height * t);
    }
    if (n == 0) return Colors.white;
    // Bright content under the frame → dark guides (and vice versa).
    return sum / n > 0.52 ? const Color(0xFF101418) : Colors.white;
  }

  double get _imageAspect {
    final stored = widget.session.imageAspectFor(widget.path);
    if (stored != null && stored > 0) return stored;
    final image = _imageSize;
    if (image != null && image.height > 0) return image.width / image.height;
    return 1.5;
  }

  (Rect space, Rect cropRect, double straighten, Rect upright) _geometry(
    Size viewport,
  ) {
    final straighten = widget.session.straightenFor(widget.path);
    // Keep photo at natural contain size while rotating — scaling the AABB
    // into the viewport made straighten feel like a continuous zoom.
    final aspect = _imageAspect;
    final upright = containRect(Size(aspect, 1), viewport);
    final rad = straighten * math.pi / 180.0;
    final space = straighten.abs() <= 1e-6
        ? upright
        : rotatedAabb(upright, rad);
    final crop = widget.session.cropFor(widget.path);
    final cropRect = space.isEmpty ? Rect.zero : crop.rectIn(space);
    return (space, cropRect, straighten, upright);
  }

  void _clearPan() {
    _handle = null;
    _origin = null;
    _panStart = null;
    _rotateOriginDegrees = null;
    _rotateStartRadians = null;
    _rotateCenter = null;
    _panSpaceSize = null;
  }

  void _applyPan(Offset local) {
    final handle = _handle;
    final start = _panStart;
    if (handle == null || start == null) return;
    if ((local - start).distance > 3) {
      _didDrag = true;
    }
    _setPointer(local);
    if (handle == CropHandle.rotate) {
      final originDeg = _rotateOriginDegrees;
      final startRad = _rotateStartRadians;
      final center = _rotateCenter;
      if (originDeg == null || startRad == null || center == null) {
        return;
      }
      final nowRad = math.atan2(
        local.dy - center.dy,
        local.dx - center.dx,
      );
      // Screen y-down atan2 is CW-positive, matching straighten.
      final deltaDeg = (nowRad - startRad) * 180.0 / math.pi;
      widget.session.setStraighten(
        widget.path,
        originDeg + deltaDeg,
      );
      return;
    }
    final origin = _origin;
    final spaceSize = _panSpaceSize;
    if (origin == null ||
        spaceSize == null ||
        spaceSize.width <= 0 ||
        spaceSize.height <= 0) {
      return;
    }
    final aspect = widget.session.normAspectFor(widget.path);
    // Move: picture follows the finger (crop shifts opposite).
    // Resize handles keep the natural edge-follow delta.
    final rawDx = (local.dx - start.dx) / spaceSize.width;
    final rawDy = (local.dy - start.dy) / spaceSize.height;
    final dx = handle == CropHandle.move ? -rawDx : rawDx;
    final dy = handle == CropHandle.move ? -rawDy : rawDy;
    final next = dragCrop(
      start: origin,
      handle: handle,
      dx: dx,
      dy: dy,
      normAspect: aspect,
      imageAspect: widget.session.imageAspectFor(widget.path) ?? 1.5,
      straightenDegrees: widget.session.straightenFor(widget.path),
      lockRatio: widget.session.ratioLocked,
    );
    widget.session.setCrop(widget.path, next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (!widget.interactive) {
          return AnimatedBuilder(
            animation: widget.session,
            builder: (context, _) {
              final geo = _geometry(viewport);
              return IgnorePointer(
                child: CustomPaint(
                  painter: _CropFramePainter(
                    aabb: geo.$1,
                    upright: geo.$4,
                    crop: geo.$2,
                    straightenDegrees: geo.$3,
                    guideColor: _guideColorFor(
                      widget.session.cropFor(widget.path),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          );
        }
        // Active drag wins — hover must not flip corner resize into rotate.
        final activeHandle = _handle ?? _hoverHandle;
        // Keep the gesture detector outside session rebuilds so rotate/drag
        // aren't cancelled when straighten notifies listeners.
        return MouseRegion(
          // Hide OS cursor; SVG overlay uses hotspot 16,16.
          cursor: SystemMouseCursors.none,
          onHover: (event) {
            // Lock mode for the whole gesture; only track the pointer.
            if (_handle != null) {
              _setPointer(event.localPosition);
              return;
            }
            final cropRect = _geometry(viewport).$2;
            if (cropRect.isEmpty) return;
            final next = cropHandleAt(event.localPosition, cropRect);
            final rotateCorner = next == CropHandle.rotate
                ? _nearestCropCorner(event.localPosition, cropRect)
                : _rotateCorner;
            final handleChanged =
                next != _hoverHandle || rotateCorner != _rotateCorner;
            _hoverHandle = next;
            _rotateCorner = rotateCorner;
            _setPointer(event.localPosition, rebuild: handleChanged);
          },
          onExit: (_) {
            if (_handle != null) return;
            if (_hoverHandle != null || _pointer != null) {
              _hoverHandle = null;
              _setPointer(null, rebuild: true);
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onSecondaryTapUp: (details) {
                  final geo = _geometry(viewport);
                  // Stage chrome only — not the real photo pixels.
                  if (geo.$4.isEmpty ||
                      _pointInRotatedRect(
                        details.localPosition,
                        geo.$4,
                        geo.$3,
                      )) {
                    return;
                  }
                  widget.onChromeSecondaryTap?.call(details.globalPosition);
                },
                onTapUp: (details) {
                  if (_didDrag) {
                    _didDrag = false;
                    _lastTapAt = null;
                    _lastTapPos = null;
                    return;
                  }
                  final now = DateTime.now();
                  final lastAt = _lastTapAt;
                  final lastPos = _lastTapPos;
                  final closeInTime = lastAt != null &&
                      now.difference(lastAt) < const Duration(milliseconds: 350);
                  final closeInSpace = lastPos != null &&
                      (details.localPosition - lastPos).distance <= 28;
                  if (closeInTime && closeInSpace) {
                    _lastTapAt = null;
                    _lastTapPos = null;
                    widget.session.finishCropping();
                    return;
                  }
                  _lastTapAt = now;
                  _lastTapPos = details.localPosition;
                },
                onPanStart: (details) {
                  _didDrag = false;
                  final geo = _geometry(viewport);
                  final space = geo.$1;
                  final cropRect = geo.$2;
                  final straighten = geo.$3;
                  if (space.isEmpty || cropRect.isEmpty) return;
                  final handle = cropHandleAt(details.localPosition, cropRect);
                  if (handle == null) return;
                  widget.session.beginGesture(widget.path);
                  _hoverHandle = handle;
                  if (handle == CropHandle.rotate) {
                    _rotateCorner = _nearestCropCorner(
                      details.localPosition,
                      cropRect,
                    );
                  }
                  _setPointer(details.localPosition, rebuild: true);
                  _handle = handle;
                  _origin = widget.session.cropFor(widget.path);
                  _panStart = details.localPosition;
                  _panSpaceSize = space.size;
                  if (handle == CropHandle.rotate) {
                    _rotateOriginDegrees = straighten;
                    _rotateCenter = cropRect.center;
                    _rotateStartRadians = math.atan2(
                      details.localPosition.dy - cropRect.center.dy,
                      details.localPosition.dx - cropRect.center.dx,
                    );
                  } else {
                    _rotateOriginDegrees = null;
                    _rotateStartRadians = null;
                    _rotateCenter = null;
                  }
                },
                onPanUpdate: (details) {
                  _applyPan(details.localPosition);
                },
                onPanEnd: (_) {
                  final release = _pointer;
                  widget.session.endGesture();
                  _clearPan();
                  // Recompute hover from release point so mode doesn't stick.
                  final cropRect = _geometry(viewport).$2;
                  if (release != null && !cropRect.isEmpty) {
                    final next = cropHandleAt(release, cropRect);
                    _hoverHandle = next;
                    if (next == CropHandle.rotate) {
                      _rotateCorner = _nearestCropCorner(release, cropRect);
                    }
                    _setPointer(release, rebuild: true);
                  }
                },
                onPanCancel: () {
                  widget.session.endGesture();
                  _clearPan();
                  _didDrag = false;
                  _hoverHandle = null;
                  _setPointer(null, rebuild: true);
                },
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: widget.session,
                    builder: (context, _) {
                      final geo = _geometry(viewport);
                      return CustomPaint(
                        isComplex: true,
                        willChange: _handle != null,
                        painter: _CropFramePainter(
                          aabb: geo.$1,
                          upright: geo.$4,
                          crop: geo.$2,
                          straightenDegrees: geo.$3,
                          guideColor: _guideColorFor(
                            widget.session.cropFor(widget.path),
                          ),
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
              ValueListenableBuilder<Offset?>(
                valueListenable: _pointerTick,
                builder: (context, pointer, _) {
                  if (pointer == null) return const SizedBox.shrink();
                  return CropCursors.overlay(
                    pointer: pointer,
                    handle: activeHandle,
                    rotateCorner: _rotateCorner,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rotates [child] for straighten and optionally zooms to [crop].
class StraightenPhotoLayer extends StatelessWidget {
  const StraightenPhotoLayer({
    super.key,
    required this.child,
    required this.crop,
    required this.degrees,
    required this.imageAspect,
    required this.editingCrop,
  });

  final Widget child;
  final PhotoCrop crop;
  final double degrees;
  final double imageAspect;
  final bool editingCrop;

  @override
  Widget build(BuildContext context) {
    final rad = degrees * math.pi / 180.0;
    if (editingCrop) {
      // Rotate only — do not scale down to fit the AABB (that felt like zoom).
      if (degrees.abs() <= 1e-6) return child;
      return Transform.rotate(
        angle: rad,
        filterQuality: FilterQuality.low,
        child: RepaintBoundary(child: child),
      );
    }
    if (degrees.abs() <= 1e-6 && crop.isFull) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport.isEmpty) return child;
        final aspect = imageAspect <= 0 ? 1.5 : imageAspect;
        final imageRect = containRect(Size(aspect, 1), viewport);
        final space =
            degrees.abs() <= 1e-6 ? imageRect : rotatedAabb(imageRect, rad);
        // Never frame the full AABB while straightened — that shows empty
        // wedges and a diagonal photo edge inside the picture.
        final effectiveCrop = (degrees.abs() > 1e-6 && crop.isFull)
            ? safeCropForStraighten(
                imageAspect: imageAspect,
                degrees: degrees,
              )
            : (degrees.abs() > 1e-6
                ? shrinkCropToSource(
                    crop: crop,
                    imageAspect: imageAspect,
                    degrees: degrees,
                  )
                : crop);
        final cropPx = effectiveCrop.isFull ? space : effectiveCrop.rectIn(space);
        if (cropPx.isEmpty || space.isEmpty) {
          return degrees.abs() <= 1e-6
              ? child
              : Transform.rotate(
                  angle: rad,
                  filterQuality: FilterQuality.medium,
                  child: child,
                );
        }
        final shown =
            applyBoxFit(BoxFit.contain, cropPx.size, viewport).destination;
        final dest = Alignment.center.inscribe(shown, Offset.zero & viewport);
        final sx = dest.width / cropPx.width;
        final sy = dest.height / cropPx.height;
        final matrix = Matrix4.identity()
          ..translateByDouble(dest.left, dest.top, 0, 1)
          ..scaleByDouble(sx, sy, 1, 1)
          ..translateByDouble(-cropPx.left, -cropPx.top, 0, 1);
        final rotated = degrees.abs() <= 1e-6
            ? child
            : Transform.rotate(
                angle: rad,
                filterQuality: FilterQuality.medium,
                child: child,
              );
        // Clip to the crop itself, not the stage — otherwise the rest of the
        // tilted photo (and its empty corners) shows beside a narrow crop.
        return ClipRect(
          clipper: _FixedRectClipper(dest),
          child: Transform(
            transform: matrix,
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: rotated,
            ),
          ),
        );
      },
    );
  }
}

class _FixedRectClipper extends CustomClipper<Rect> {
  const _FixedRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_FixedRectClipper oldClipper) => oldClipper.rect != rect;
}

class _CropFramePainter extends CustomPainter {
  const _CropFramePainter({
    required this.aabb,
    required this.upright,
    required this.crop,
    required this.straightenDegrees,
    required this.guideColor,
  });

  final Rect aabb;
  final Rect upright;
  final Rect crop;
  final double straightenDegrees;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (aabb.isEmpty || crop.isEmpty || upright.isEmpty) return;
    // Dim only real photo pixels outside the crop. Empty AABB bands stay
    // transparent so stage backdrop shows — photo silhouette stays rectangular.
    final dim = Paint()..color = const Color(0x99000000);
    if (straightenDegrees.abs() <= 1e-6) {
      // Fast path: four rects, no Path.combine (GPU-friendlier).
      final src = upright;
      if (crop.top > src.top) {
        canvas.drawRect(
          Rect.fromLTRB(src.left, src.top, src.right, crop.top),
          dim,
        );
      }
      if (crop.bottom < src.bottom) {
        canvas.drawRect(
          Rect.fromLTRB(src.left, crop.bottom, src.right, crop.bottom),
          dim,
        );
      }
      if (crop.left > src.left) {
        canvas.drawRect(
          Rect.fromLTRB(src.left, crop.top, crop.left, crop.bottom),
          dim,
        );
      }
      if (crop.right < src.right) {
        canvas.drawRect(
          Rect.fromLTRB(crop.right, crop.top, src.right, crop.bottom),
          dim,
        );
      }
    } else {
      final source = _rotatedSourcePath(upright, straightenDegrees);
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          source,
          Path()..addRect(crop),
        ),
        dim,
      );
    }

    // Opposite under-stroke so guides stay readable on mixed edges.
    final underColor = guideColor.computeLuminance() > 0.5
        ? const Color(0xCC000000)
        : const Color(0xCCFFFFFF);
    final under = Paint()
      ..color = underColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final line = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(crop, under);
    canvas.drawRect(crop, line);

    final thirdUnder = Paint()
      ..color = underColor.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    final third = Paint()
      ..color = guideColor.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final dx = crop.left + crop.width * i / 3;
      final dy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), thirdUnder);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), thirdUnder);
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), third);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), third);
    }

    final bracketUnder = Paint()
      ..color = underColor
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;
    final bracket = Paint()
      ..color = guideColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const arm = 16.0;
    void corner(Offset origin, double xSign, double ySign) {
      final h = origin + Offset(arm * xSign, 0);
      final v = origin + Offset(0, arm * ySign);
      canvas.drawLine(origin, h, bracketUnder);
      canvas.drawLine(origin, v, bracketUnder);
      canvas.drawLine(origin, h, bracket);
      canvas.drawLine(origin, v, bracket);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter oldDelegate) {
    return oldDelegate.aabb != aabb ||
        oldDelegate.upright != upright ||
        oldDelegate.crop != crop ||
        oldDelegate.straightenDegrees != straightenDegrees ||
        oldDelegate.guideColor != guideColor;
  }
}

/// Rotated photo quad using the same matrix as [Transform.rotate] / [rotatedAabb].
Path _rotatedSourcePath(Rect upright, double degrees) {
  final rad = degrees * math.pi / 180.0;
  if (rad.abs() <= 1e-6) {
    return Path()..addRect(upright);
  }
  final c = math.cos(rad);
  final s = math.sin(rad);
  final origin = upright.center;
  Offset map(Offset p) {
    final d = p - origin;
    return Offset(
      origin.dx + d.dx * c - d.dy * s,
      origin.dy + d.dx * s + d.dy * c,
    );
  }

  final tl = map(upright.topLeft);
  final tr = map(upright.topRight);
  final br = map(upright.bottomRight);
  final bl = map(upright.bottomLeft);
  return Path()
    ..moveTo(tl.dx, tl.dy)
    ..lineTo(tr.dx, tr.dy)
    ..lineTo(br.dx, br.dy)
    ..lineTo(bl.dx, bl.dy)
    ..close();
}

bool _pointInRotatedRect(Offset local, Rect upright, double degrees) {
  if (upright.isEmpty) return false;
  final rad = degrees * math.pi / 180.0;
  if (rad.abs() <= 1e-6) return upright.contains(local);
  final c = math.cos(rad);
  final s = math.sin(rad);
  final d = local - upright.center;
  // Inverse of Transform.rotate / rotatedAabb.
  final x = d.dx * c + d.dy * s;
  final y = -d.dx * s + d.dy * c;
  final hw = upright.width / 2;
  final hh = upright.height / 2;
  return x.abs() <= hw && y.abs() <= hh;
}

CropHandle _nearestCropCorner(Offset local, Rect crop) {
  final corners = <CropHandle, Offset>{
    CropHandle.topLeft: crop.topLeft,
    CropHandle.topRight: crop.topRight,
    CropHandle.bottomLeft: crop.bottomLeft,
    CropHandle.bottomRight: crop.bottomRight,
  };
  var best = CropHandle.bottomRight;
  var bestDist = double.infinity;
  for (final entry in corners.entries) {
    final d = (local - entry.value).distanceSquared;
    if (d < bestDist) {
      bestDist = d;
      best = entry.key;
    }
  }
  return best;
}
