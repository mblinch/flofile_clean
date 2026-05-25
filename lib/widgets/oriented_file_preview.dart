import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/oriented_image_bytes.dart';

/// File preview that respects JPEG EXIF orientation (thumbnails, grids).
class OrientedFilePreview extends StatefulWidget {
  const OrientedFilePreview({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.filterQuality = FilterQuality.high,
    this.onLoaded,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final VoidCallback? onLoaded;

  @override
  State<OrientedFilePreview> createState() => _OrientedFilePreviewState();
}

class _OrientedFilePreviewState extends State<OrientedFilePreview> {
  Uint8List? _bytes;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrientedFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _load();
    }
  }

  void _load() {
    final t = ++_token;
    setState(() => _bytes = null);
    OrientedImageBytes.load(
      widget.path,
      maxWidth: widget.cacheWidth,
    ).then((bytes) {
      if (!mounted || t != _token) return;
      setState(() => _bytes = bytes);
      if (bytes != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLoaded?.call();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
    );
  }
}
