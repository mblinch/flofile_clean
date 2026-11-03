import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'photo_adjust_config.dart';
import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_grade_engine.dart';

/// Draws JPEG bytes with the Camera Raw grade shader at preview resolution.
class GradedMemoryImage extends StatefulWidget {
  const GradedMemoryImage({
    super.key,
    required this.bytes,
    required this.adjustments,
    this.crop = PhotoCrop.full,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
    this.compareOriginal = false,
    this.debugMask = false,
    this.displayLongEdge,
  });

  final Uint8List bytes;
  final PhotoAdjustments adjustments;
  final PhotoCrop crop;
  final BoxFit fit;
  final FilterQuality filterQuality;

  /// Hold-to-compare: show the ungraded source.
  final bool compareOriginal;

  /// Debug: visualize the local-tone luminance mask.
  final bool debugMask;

  /// Cap preview long edge (defaults to [PhotoAdjustConfig.previewLongEdge]).
  final int? displayLongEdge;

  @override
  State<GradedMemoryImage> createState() => _GradedMemoryImageState();
}

/// Back-compat alias used by older call sites.
class PhotoGradeShader {
  PhotoGradeShader._();

  static Future<void> ensure() => PhotoGradeShaders.ensure();

  static ui.FragmentProgram? get program => PhotoGradeShaders.grade;
  static ui.Image? get placeholder => PhotoGradeShaders.placeholder;
}

class _GradedMemoryImageState extends State<GradedMemoryImage> {
  final PhotoGradeEngine _engine = PhotoGradeEngine();
  ui.Image? _image;
  ui.Image? _mask;
  ui.FragmentShader? _shader;
  int _decodeToken = 0;
  int _maskToken = 0;
  PhotoAdjustments? _maskKey;

  @override
  void initState() {
    super.initState();
    _decode();
    PhotoGradeShaders.ensure().then((_) {
      if (!mounted) return;
      _shader ??= PhotoGradeShaders.grade?.fragmentShader();
      setState(() {});
      _scheduleMask();
    });
  }

  @override
  void didUpdateWidget(covariant GradedMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.displayLongEdge != widget.displayLongEdge) {
      _maskKey = null;
      _decode();
    } else {
      _scheduleMask();
    }
  }

  @override
  void dispose() {
    _decodeToken++;
    _maskToken++;
    _image?.dispose();
    _mask?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  bool _sameMaskKey(PhotoAdjustments a, PhotoAdjustments b) {
    // Mask depends on WB / exposure / contrast only.
    return a.temperature == b.temperature &&
        a.tint == b.tint &&
        a.exposure == b.exposure &&
        a.contrast == b.contrast;
  }

  void _scheduleMask() {
    if (!widget.adjustments.needsLocalTone && !widget.debugMask) {
      _maskToken++;
      final previous = _mask;
      _mask = null;
      _maskKey = null;
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previous.dispose();
        });
      }
      return;
    }
    final photo = _image;
    if (photo == null) return;
    final key = widget.adjustments;
    if (_mask != null &&
        _maskKey != null &&
        _sameMaskKey(_maskKey!, key)) {
      return;
    }
    final token = ++_maskToken;
    final frame = _engine.beginFrame();
    () async {
      var mask = await _engine.buildMask(
        source: photo,
        adjustments: key,
        token: frame,
      );
      mask ??= await _engine.buildMaskCpu(
        source: photo,
        adjustments: key,
        token: frame,
      );
      if (!mounted || token != _maskToken) {
        mask?.dispose();
        return;
      }
      final previous = _mask;
      setState(() {
        _mask = mask;
        _maskKey = key;
      });
      previous?.dispose();
    }();
  }

  void _decode() {
    final token = ++_decodeToken;
    final longEdge =
        widget.displayLongEdge ?? PhotoAdjustConfig.previewLongEdge;
    PhotoGradeEngine.decodeScaled(widget.bytes, longEdge).then((image) {
      if (!mounted || token != _decodeToken) {
        image.dispose();
        return;
      }
      final previous = _image;
      setState(() => _image = image);
      previous?.dispose();
      _maskKey = null;
      _scheduleMask();
    });
  }

  @override
  Widget build(BuildContext context) {
    final plain = Image.memory(
      widget.bytes,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
    );
    if (widget.compareOriginal) return plain;

    final needsShader =
        !widget.adjustments.isNeutral || !widget.crop.isFull || widget.debugMask;
    if (!needsShader || _image == null || _shader == null) return plain;

    return CustomPaint(
      painter: _PhotoGradePainter(
        image: _image!,
        mask: _mask,
        shader: _shader!,
        adjustments: widget.adjustments,
        crop: widget.crop,
        fit: widget.fit,
        debugMask: widget.debugMask,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PhotoGradePainter extends CustomPainter {
  _PhotoGradePainter({
    required this.image,
    required this.mask,
    required this.shader,
    required this.adjustments,
    required this.crop,
    required this.fit,
    required this.debugMask,
  });

  final ui.Image image;
  final ui.Image? mask;
  final ui.FragmentShader shader;
  final PhotoAdjustments adjustments;
  final PhotoCrop crop;
  final BoxFit fit;
  final bool debugMask;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shown = Size(
      image.width * crop.width,
      image.height * crop.height,
    );
    final fitted = applyBoxFit(fit, shown, size);
    final dest = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    if (dest.width <= 0 || dest.height <= 0) return;

    PhotoGradeEngine.bindGradeUniforms(
      shader,
      image: image,
      mask: mask,
      adjustments: adjustments,
      crop: crop,
      dest: dest,
      debugMask: debugMask,
      dither: true,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(dest, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PhotoGradePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.fit != fit ||
        oldDelegate.debugMask != debugMask ||
        oldDelegate.mask != mask ||
        oldDelegate.adjustments.temperature != adjustments.temperature ||
        oldDelegate.adjustments.tint != adjustments.tint ||
        oldDelegate.adjustments.exposure != adjustments.exposure ||
        oldDelegate.adjustments.contrast != adjustments.contrast ||
        oldDelegate.adjustments.highlights != adjustments.highlights ||
        oldDelegate.adjustments.shadows != adjustments.shadows ||
        oldDelegate.adjustments.whites != adjustments.whites ||
        oldDelegate.adjustments.blacks != adjustments.blacks ||
        oldDelegate.adjustments.vibrance != adjustments.vibrance ||
        oldDelegate.adjustments.saturation != adjustments.saturation ||
        oldDelegate.crop.left != crop.left ||
        oldDelegate.crop.top != crop.top ||
        oldDelegate.crop.width != crop.width ||
        oldDelegate.crop.height != crop.height;
  }
}
