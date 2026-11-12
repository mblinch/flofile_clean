import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/oriented_image_bytes.dart';
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
  });

  final PhotoEditSession session;
  final String path;
  final int version;
  final BoxFit fit;

  /// When false, draws the frame only (used after leaving crop tool).
  final bool interactive;

  @override
  State<PhotoCropOverlay> createState() => _PhotoCropOverlayState();
}

class _PhotoCropOverlayState extends State<PhotoCropOverlay> {
  Size? _imageSize;
  int _token = 0;
  CropHandle? _handle;
  PhotoCrop? _origin;
  Offset? _panStart;

  @override
  void initState() {
    super.initState();
    _loadSize();
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
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    if (!mounted || token != _token || size.isEmpty) return;
    setState(() => _imageSize = size);
    widget.session.noteImageAspect(widget.path, size.width / size.height);
  }

  Rect _imageRect(Size viewport) {
    final image = _imageSize;
    if (image == null || viewport.isEmpty || image.isEmpty) return Rect.zero;
    final fitted = applyBoxFit(widget.fit, image, viewport).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & viewport);
  }

  /// Frame the crop overlay uses: upright fit, or AABB after straighten.
  Rect _cropSpace(Size viewport, double straightenDegrees) {
    final image = _imageRect(viewport);
    if (image.isEmpty) return Rect.zero;
    if (straightenDegrees.abs() <= 1e-6) return image;
    return rotatedAabb(image, straightenDegrees * math.pi / 180.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            final straighten = widget.session.straightenFor(widget.path);
            final space = _cropSpace(viewport, straighten);
            final crop = widget.session.cropFor(widget.path);
            final cropRect = space.isEmpty ? Rect.zero : crop.rectIn(space);
            final paint = CustomPaint(
              painter: _CropFramePainter(
                image: space,
                crop: cropRect,
              ),
              child: const SizedBox.expand(),
            );
            if (!widget.interactive || space.isEmpty) {
              return IgnorePointer(child: paint);
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                final handle = cropHandleAt(details.localPosition, cropRect);
                if (handle == null) return;
                _handle = handle;
                _origin = crop;
                _panStart = details.localPosition;
              },
              onPanUpdate: (details) {
                final handle = _handle;
                final origin = _origin;
                final start = _panStart;
                if (handle == null || origin == null || start == null) {
                  return;
                }
                final aspect = widget.session.normAspectFor(widget.path);
                // When straightened, locked aspect is vs AABB of rotated frame.
                final next = dragCrop(
                  start: origin,
                  handle: handle,
                  dx: (details.localPosition.dx - start.dx) / space.width,
                  dy: (details.localPosition.dy - start.dy) / space.height,
                  normAspect: aspect,
                );
                widget.session.setCrop(widget.path, next);
              },
              onPanEnd: (_) {
                _handle = null;
                _origin = null;
                _panStart = null;
              },
              onPanCancel: () {
                _handle = null;
                _origin = null;
                _panStart = null;
              },
              onDoubleTap: widget.session.finishCropping,
              child: paint,
            );
          },
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
      if (degrees.abs() <= 1e-6) return child;
      return Transform.rotate(angle: rad, filterQuality: FilterQuality.medium, child: child);
    }
    if (degrees.abs() <= 1e-6 && crop.isFull) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport.isEmpty) return child;
        final src = Size(imageAspect <= 0 ? 1.5 : imageAspect, 1);
        final fitted = applyBoxFit(BoxFit.contain, src, viewport).destination;
        final imageRect =
            Alignment.center.inscribe(fitted, Offset.zero & viewport);
        final space =
            degrees.abs() <= 1e-6 ? imageRect : rotatedAabb(imageRect, rad);
        final cropPx = crop.isFull ? space : crop.rectIn(space);
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
        return ClipRect(
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

class _CropFramePainter extends CustomPainter {
  const _CropFramePainter({required this.image, required this.crop});

  final Rect image;
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    if (image.isEmpty || crop.isEmpty) return;
    final dim = Paint()..color = const Color(0x99000000);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(crop),
      ),
      dim,
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(crop, line);
    final third = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final dx = crop.left + crop.width * i / 3;
      final dy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), third);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), third);
    }
    final bracket = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const arm = 16.0;
    void corner(Offset origin, double xSign, double ySign) {
      canvas.drawLine(origin, origin + Offset(arm * xSign, 0), bracket);
      canvas.drawLine(origin, origin + Offset(0, arm * ySign), bracket);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.crop != crop;
  }
}
