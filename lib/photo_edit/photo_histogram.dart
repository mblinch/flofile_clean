import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../screens/caption_v2/data/caption_v2_controller.dart';
import '../theme/ff_tokens.dart';
import '../utils/oriented_image_bytes.dart';
import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_edit_session.dart';

const histogramBins = 64;
const _maxHistogramSamples = 1600;

class RgbHistogram {
  const RgbHistogram(this.red, this.green, this.blue);

  final List<int> red;
  final List<int> green;
  final List<int> blue;

  int get peak {
    var maxCount = 1;
    for (final channel in [red, green, blue]) {
      for (final count in channel) {
        if (count > maxCount) maxCount = count;
      }
    }
    return maxCount;
  }
}

/// Bins [rgb] (tight RGB bytes, row-major) after the current grade and crop.
RgbHistogram rgbHistogram({
  required Uint8List rgb,
  required int width,
  required int height,
  required PhotoAdjustments adjustments,
  required PhotoCrop crop,
  int bins = histogramBins,
}) {
  final red = List<int>.filled(bins, 0);
  final green = List<int>.filled(bins, 0);
  final blue = List<int>.filled(bins, 0);
  if (width <= 0 || height <= 0 || rgb.length < width * height * 3) {
    return RgbHistogram(red, green, blue);
  }
  final pixels = width * height;
  final stride = pixels <= _maxHistogramSamples
      ? 1
      : math.max(1, (pixels / _maxHistogramSamples).ceil());
  final neutral = adjustments.isNeutral;
  final base = neutral || !adjustments.needsLocalTone
      ? null
      : lumaBaseForDisplayRgb(rgb, width, height, adjustments);
  final last = bins - 1;

  void add(List<int> channel, double unit) {
    final bin = (unit.clamp(0.0, 1.0) * last).round();
    channel[bin]++;
  }

  for (var y = 0; y < height; y += stride) {
    final ny = y / height;
    if (ny < crop.top || ny >= crop.bottom) continue;
    for (var x = 0; x < width; x += stride) {
      final nx = x / width;
      if (nx < crop.left || nx >= crop.right) continue;
      final i = (y * width + x) * 3;
      final r = rgb[i] / 255.0;
      final g = rgb[i + 1] / 255.0;
      final b = rgb[i + 2] / 255.0;
      if (neutral) {
        add(red, r);
        add(green, g);
        add(blue, b);
      } else {
        final graded = gradeDisplayRgb(
          r,
          g,
          b,
          adjustments,
          baseLuma: base == null ? null : base[y * width + x],
        );
        add(red, graded.r);
        add(green, graded.g);
        add(blue, graded.b);
      }
    }
  }
  return RgbHistogram(red, green, blue);
}

/// RGB histogram for the current frame, graded and cropped like the preview.
class PhotoHistogram extends StatefulWidget {
  const PhotoHistogram({
    super.key,
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  State<PhotoHistogram> createState() => _PhotoHistogramState();
}

class _HistogramSamples {
  const _HistogramSamples({
    required this.path,
    required this.version,
    required this.width,
    required this.height,
    required this.rgb,
  });

  final String path;
  final int version;
  final int width;
  final int height;
  final Uint8List rgb;
}

class _PhotoHistogramState extends State<PhotoHistogram> {
  _HistogramSamples? _samples;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFrame);
    _load();
  }

  @override
  void didUpdateWidget(covariant PhotoHistogram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onFrame);
      widget.controller.addListener(_onFrame);
    }
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFrame);
    super.dispose();
  }

  void _onFrame() => _load();

  Future<void> _load() async {
    final path = widget.controller.currentPath;
    if (path == null) {
      if (_samples != null) setState(() => _samples = null);
      return;
    }
    final version = widget.controller.imageContentStamp(path);
    final current = _samples;
    if (current != null && current.path == path && current.version == version) {
      return;
    }
    final token = ++_token;
    final bytes = await OrientedImageBytes.load(path, maxWidth: 128);
    if (!mounted || token != _token) return;
    if (bytes == null) {
      setState(() => _samples = null);
      return;
    }
    final decoded = img.decodeImage(bytes);
    if (!mounted || token != _token || decoded == null) return;
    final packed = Uint8List(decoded.width * decoded.height * 3);
    var index = 0;
    for (final pixel in decoded) {
      packed[index++] = pixel.r.toInt().clamp(0, 255);
      packed[index++] = pixel.g.toInt().clamp(0, 255);
      packed[index++] = pixel.b.toInt().clamp(0, 255);
    }
    setState(() {
      _samples = _HistogramSamples(
        path: path,
        version: version,
        width: decoded.width,
        height: decoded.height,
        rgb: packed,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final path = widget.controller.currentPath;
        final samples = _samples;
        final ready = samples != null && samples.path == path;
        final histogram = ready
            ? rgbHistogram(
                rgb: samples.rgb,
                width: samples.width,
                height: samples.height,
                adjustments: widget.session.adjustmentsFor(path),
                crop: widget.session.cropping
                    ? PhotoCrop.full
                    : widget.session.cropFor(path),
              )
            : null;
        return SizedBox(
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tokens.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: _HistogramPainter(histogram),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistogramPainter extends CustomPainter {
  const _HistogramPainter(this.histogram);

  final RgbHistogram? histogram;

  @override
  void paint(Canvas canvas, Size size) {
    final data = histogram;
    if (data == null || size.isEmpty) return;
    final peak = data.peak;
    _fill(canvas, size, data.red, peak, const Color(0x99E24B4B));
    _fill(canvas, size, data.green, peak, const Color(0x803DDC84));
    _fill(canvas, size, data.blue, peak, const Color(0x804C8DFF));
  }

  void _fill(Canvas canvas, Size size, List<int> bins, int peak, Color color) {
    final path = ui.Path()..moveTo(0, size.height);
    final last = bins.length - 1;
    for (var i = 0; i < bins.length; i++) {
      final x = last == 0 ? 0.0 : size.width * i / last;
      final y = size.height - (bins[i] / peak) * (size.height - 2);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) {
    return oldDelegate.histogram != histogram;
  }
}
