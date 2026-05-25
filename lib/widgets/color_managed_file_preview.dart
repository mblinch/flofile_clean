import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/oriented_image_bytes.dart';

/// Preview with EXIF orientation and ICC color management before display.
///
/// On macOS, [OrientedImageBytes] decodes via Core Image (ICC → sRGB + orientation);
/// other platforms use the Dart [image] package fallback (no ICC).
class ColorManagedFilePreview extends StatefulWidget {
  const ColorManagedFilePreview({
    super.key,
    required this.path,
    required this.maxPixelDimension,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.high,
  });

  final String path;
  final int maxPixelDimension;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  @override
  State<ColorManagedFilePreview> createState() =>
      _ColorManagedFilePreviewState();
}

class _ColorManagedFilePreviewState extends State<ColorManagedFilePreview> {
  Uint8List? _bytes;
  bool _loading = true;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant ColorManagedFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.maxPixelDimension != widget.maxPixelDimension) {
      _startLoad();
    }
  }

  void _startLoad() {
    final t = ++_token;
    setState(() {
      _loading = true;
      _bytes = null;
    });
    OrientedImageBytes.load(
      widget.path,
      maxWidth: widget.maxPixelDimension,
    ).then((bytes) {
      if (!mounted || t != _token) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        width: widget.width,
        height: widget.height,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        width: widget.width,
        height: widget.height,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 48),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
    );
  }
}
