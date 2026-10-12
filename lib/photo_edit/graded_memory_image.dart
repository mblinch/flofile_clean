import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_tone_base.dart';

/// Draws JPEG bytes with the Camera Raw grade shader.
class GradedMemoryImage extends StatefulWidget {
  const GradedMemoryImage({
    super.key,
    required this.bytes,
    required this.adjustments,
    this.crop = PhotoCrop.full,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
  });

  final Uint8List bytes;
  final PhotoAdjustments adjustments;
  final PhotoCrop crop;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  State<GradedMemoryImage> createState() => _GradedMemoryImageState();
}

class PhotoGradeShader {
  PhotoGradeShader._();

  static ui.FragmentProgram? program;
  static ui.Image? placeholder;
  static Future<void>? _loading;

  static Future<void> ensure() {
    return _loading ??= () async {
      try {
        program = await ui.FragmentProgram.fromAsset('shaders/photo_grade.frag');
        placeholder ??= await _solidPixel();
      } catch (_) {
        program = null;
      }
    }();
  }

  static Future<ui.Image> _solidPixel() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(const [0, 0, 0, 255]),
    );
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}

Future<ui.Image?> toneBaseImage(
  Uint8List bytes,
  PhotoAdjustments adjustments,
) async {
  // Match the preview bitmap. A tiny base sampled across a large photo
  // turns highlight recovery into visible blocks.
  const maxEdge = 2048;
  ui.Codec? codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    var image = frame.image;
    if (image.width > maxEdge || image.height > maxEdge) {
      final wide = image.width >= image.height;
      image.dispose();
      codec.dispose();
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: wide ? maxEdge : null,
        targetHeight: wide ? null : maxEdge,
      );
      final scaledFrame = await codec.getNextFrame();
      image = scaledFrame.image;
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List();
    final rgb = Uint8List(width * height * 3);
    for (var i = 0; i < width * height; i++) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    final base = lumaBaseForDisplayRgb(rgb, width, height, adjustments);
    final encoded = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final value = (encodeBaseLuma(base[i]) * 255).round().clamp(0, 255);
      encoded[i * 4] = value;
      encoded[i * 4 + 1] = value;
      encoded[i * 4 + 2] = value;
      encoded[i * 4 + 3] = 255;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final outCodec = await descriptor.instantiateCodec();
    final outFrame = await outCodec.getNextFrame();
    outCodec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return outFrame.image;
  } finally {
    codec?.dispose();
  }
}

class _GradedMemoryImageState extends State<GradedMemoryImage> {
  ui.Image? _image;
  ui.Image? _base;
  ui.FragmentShader? _shader;
  int _token = 0;
  int _baseToken = 0;
  PhotoAdjustments? _baseKey;

  @override
  void initState() {
    super.initState();
    _decode();
    _scheduleBase();
    PhotoGradeShader.ensure().then((_) {
      if (!mounted) return;
      _shader ??= PhotoGradeShader.program?.fragmentShader();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant GradedMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _baseKey = null;
      _decode();
    }
    _scheduleBase();
  }

  @override
  void dispose() {
    _token++;
    _baseToken++;
    _image?.dispose();
    _base?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  bool _sameBaseKey(PhotoAdjustments a, PhotoAdjustments b) {
    return a.exposure == b.exposure &&
        a.contrast == b.contrast &&
        a.whites == b.whites &&
        a.blacks == b.blacks &&
        a.temperature == b.temperature &&
        a.tint == b.tint;
  }

  void _scheduleBase() {
    if (!widget.adjustments.needsLocalTone) {
      _baseToken++;
      final previous = _base;
      _base = null;
      _baseKey = null;
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previous.dispose();
        });
      }
      return;
    }
    final key = widget.adjustments;
    final photo = _image;
    final base = _base;
    final coarse = photo != null &&
        base != null &&
        (base.width * 2 < photo.width || base.height * 2 < photo.height);
    if (!coarse &&
        base != null &&
        _baseKey != null &&
        _sameBaseKey(_baseKey!, key)) {
      return;
    }
    final token = ++_baseToken;
    final bytes = widget.bytes;
    final adjustments = widget.adjustments;
    toneBaseImage(bytes, adjustments).then((image) {
      if (!mounted || token != _baseToken) {
        image?.dispose();
        return;
      }
      final previous = _base;
      setState(() {
        _base = image;
        _baseKey = adjustments;
      });
      previous?.dispose();
    });
  }

  void _decode() {
    final token = ++_token;
    ui.instantiateImageCodec(widget.bytes).then((codec) async {
      try {
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (!mounted || token != _token) {
          frame.image.dispose();
          return;
        }
        final previous = _image;
        setState(() => _image = frame.image);
        previous?.dispose();
      } catch (_) {
        codec.dispose();
      }
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
    final needsShader =
        !widget.adjustments.isNeutral || !widget.crop.isFull;
    if (!needsShader || _image == null || _shader == null) return plain;
    return CustomPaint(
      painter: _PhotoGradePainter(
        image: _image!,
        base: _base,
        shader: _shader!,
        adjustments: widget.adjustments,
        crop: widget.crop,
        fit: widget.fit,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PhotoGradePainter extends CustomPainter {
  _PhotoGradePainter({
    required this.image,
    required this.base,
    required this.shader,
    required this.adjustments,
    required this.crop,
    required this.fit,
  });

  final ui.Image image;
  final ui.Image? base;
  final ui.FragmentShader shader;
  final PhotoAdjustments adjustments;
  final PhotoCrop crop;
  final BoxFit fit;

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

    shader
      ..setFloat(0, dest.left)
      ..setFloat(1, dest.top)
      ..setFloat(2, dest.width)
      ..setFloat(3, dest.height)
      ..setFloat(4, adjustments.exposure)
      ..setFloat(5, adjustments.contrast)
      ..setFloat(6, adjustments.shadows)
      ..setFloat(7, adjustments.highlights)
      ..setFloat(8, adjustments.temperature)
      ..setFloat(9, adjustments.tint)
      ..setFloat(10, adjustments.whites)
      ..setFloat(11, adjustments.blacks)
      ..setFloat(12, base == null ? 0 : 1)
      ..setFloat(13, crop.left)
      ..setFloat(14, crop.top)
      ..setFloat(15, crop.width)
      ..setFloat(16, crop.height)
      ..setImageSampler(0, image)
      ..setImageSampler(1, base ?? PhotoGradeShader.placeholder ?? image);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(dest, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PhotoGradePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.fit != fit ||
        oldDelegate.adjustments.exposure != adjustments.exposure ||
        oldDelegate.adjustments.contrast != adjustments.contrast ||
        oldDelegate.adjustments.shadows != adjustments.shadows ||
        oldDelegate.adjustments.highlights != adjustments.highlights ||
        oldDelegate.adjustments.temperature != adjustments.temperature ||
        oldDelegate.adjustments.tint != adjustments.tint ||
        oldDelegate.adjustments.whites != adjustments.whites ||
        oldDelegate.adjustments.blacks != adjustments.blacks ||
        oldDelegate.base != base ||
        oldDelegate.crop.left != crop.left ||
        oldDelegate.crop.top != crop.top ||
        oldDelegate.crop.width != crop.width ||
        oldDelegate.crop.height != crop.height;
  }
}
