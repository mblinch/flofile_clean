import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../services/jersey_ocr_channel.dart';
import '../../../theme/ff_glow.dart';
import '../../../theme/ff_icons.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/oriented_image_bytes.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/frame_status_dot.dart';
import '../widgets/transmit_progress_overlay.dart';
import 'caption_v2_photo_actions.dart';
import 'caption_v2_thumbnail_overview.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Chip label: "#14 Oliver Kapanen" — number and name, nothing else.
String _ocrMatchLabel(JerseyOcrSuggestion match) {
  final jersey = match.jersey.trim();
  final name = match.player.fullName.trim();
  return jersey.isEmpty ? name : '#$jersey $name';
}

/// Target detail under the box on the photo: jersey tone + what Vision read.
/// e.g. "Dark Jersey · read “34”".
String _ocrTargetDetail(JerseyOcrSuggestion match) {
  final parts = <String>[];
  switch (match.jerseyTone) {
    case 'dark':
      parts.add('Dark Jersey');
    case 'light':
      parts.add('Light Jersey');
  }
  final ocr = match.matchedText.trim();
  if (ocr.isNotEmpty) parts.add('read “$ocr”');
  return parts.join(' · ');
}

/// OCR target colours — the steel-blue accent line from the column chrome
/// (#537690), brighter when hovered. Box, label, and chip hover share it.
const _ocrTargetTeal = Color(0xFF537690);
const _ocrTargetTealHot = Color(0xFF7FA6C2);

enum _BrowseScope { all, toCaption, captioned, toFtp, ftp }

enum _BrowseSort {
  captureAscending,
  captureDescending,
  filenameAscending,
  filenameDescending
}

/// Desktop photo preview + thumbnail grid with burst linking.
class PhotoColumn extends StatefulWidget {
  const PhotoColumn({
    super.key,
    required this.controller,
    required this.focused,
    required this.onSavePrevious,
    required this.onSaveNext,
  });

  final CaptionV2Controller controller;
  final bool focused;
  final VoidCallback onSavePrevious;
  final VoidCallback onSaveNext;

  @override
  State<PhotoColumn> createState() => _PhotoColumnState();
}

String _twelveHourTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute:$second $suffix';
}

/// EXIF `YYYY:MM:DD HH:MM:SS` → short numeric date + 12-hour time.
String _formatExifDateTime(String raw) {
  final match = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(raw);
  if (match == null) return raw;
  final year = int.tryParse(match.group(1)!) ?? 0;
  final month = int.tryParse(match.group(2)!) ?? 0;
  final day = int.tryParse(match.group(3)!) ?? 0;
  final hour24 = int.tryParse(match.group(4)!) ?? 0;
  final minute = match.group(5)!;
  final second = match.group(6)!;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final yy = (year % 100).toString().padLeft(2, '0');
  return '$month/$day/$yy $hour12:$minute:$second $suffix';
}

String _formatShutter(String raw) {
  if (raw.isEmpty || raw.contains('/')) return raw;
  final value = double.tryParse(raw);
  if (value == null || value <= 0) return raw;
  return value < 1
      ? '1/${(1 / value).round()}s'
      : '${value.toStringAsFixed(1)}s';
}

class _PhotoColumnState extends State<PhotoColumn> {
  final ValueNotifier<JerseyOcrSuggestion?> _ocrHover =
      ValueNotifier<JerseyOcrSuggestion?>(null);

  static const double _handleHeight = 14;
  /// Keep a usable large preview — never collapse it away.
  static const double _minPreviewFraction = 0.28;
  static const double _maxPreviewFraction = 0.85;
  static const double _minPreviewPixels = 180;
  double _previewFraction = 0.6;

  @override
  void initState() {
    super.initState();
    widget.controller.ensureLiveFolderRefresh();
  }

  @override
  void dispose() {
    _ocrHover.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PhotoColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller.ensureLiveFolderRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final path = widget.controller.currentPath;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
            (constraints.maxHeight - _handleHeight).clamp(0.0, double.infinity);
        final minFraction = availableHeight <= 0
            ? _minPreviewFraction
            : (_minPreviewPixels / availableHeight)
                .clamp(_minPreviewFraction, _maxPreviewFraction);
        final fraction =
            _previewFraction.clamp(minFraction, _maxPreviewFraction);
        final previewHeight = availableHeight * fraction;
        final windowSize = MediaQuery.sizeOf(context);
        final windowMaxColumns =
            windowSize.width >= 1600 && windowSize.height >= 1000 ? 8 : 6;
        final maxThumbnailColumns =
            constraints.maxWidth < 440 ? 4 : windowMaxColumns;
        return Column(
          children: [
            SizedBox(
              height: previewHeight,
              child: _PhotoCard(
                controller: widget.controller,
                path: path,
                tokens: t,
                ocrHover: _ocrHover,
                onSavePrevious: widget.onSavePrevious,
                onSaveNext: widget.onSaveNext,
              ),
            ),
            _PhotoThumbnailResizeHandle(
              tokens: t,
              onDrag: (delta) {
                if (availableHeight <= 0) return;
                final dragMin = (_minPreviewPixels / availableHeight)
                    .clamp(_minPreviewFraction, _maxPreviewFraction);
                setState(() {
                  _previewFraction =
                      (_previewFraction + delta / availableHeight)
                          .clamp(dragMin, _maxPreviewFraction);
                });
              },
              onReset: () => setState(() => _previewFraction = 0.6),
            ),
            Expanded(
              child: _ThumbnailGrid(
                controller: widget.controller,
                tokens: t,
                maxColumns: maxThumbnailColumns,
                focused: widget.focused,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhotoThumbnailResizeHandle extends StatelessWidget {
  const _PhotoThumbnailResizeHandle({
    required this.tokens,
    required this.onDrag,
    required this.onReset,
  });

  final FfTokens tokens;
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        onDoubleTap: onReset,
        child: SizedBox(
          height: _PhotoColumnState._handleHeight,
          child: Center(
            child: Container(
              width: 54,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.text.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoInfoHeader extends StatelessWidget {
  const _PhotoInfoHeader({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  String _meta(List<String> keys) {
    for (final key in keys) {
      final value = controller.currentIptcMeta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final path = controller.currentPath;
    final total = controller.imagePaths.length;
    if (path == null || total == 0) {
      return const SizedBox.shrink();
    }

    final make = _meta(const ['Make']);
    final model = _meta(const ['Model']);
    final lens = _meta(const ['LensModel', 'Lens', 'LensID']);
    final shutter = _formatShutter(_meta(const ['ShutterSpeed']));
    final fNumber = double.tryParse(_meta(const ['FNumber']));
    final focalRaw =
        _meta(const ['FocalLength']).replaceAll(RegExp(r'm+$'), '').trim();
    final focal = double.tryParse(focalRaw);
    final iso = _meta(const ['ISO']);

    final exposureLine = [
      if (iso.isNotEmpty) 'ISO $iso',
      if (shutter.isNotEmpty) shutter,
      if (fNumber != null) 'f/${fNumber.toStringAsFixed(1)}',
      if (focalRaw.isNotEmpty)
        focal == null ? '${focalRaw}mm' : '${focal.toInt()}mm',
    ].join(' · ');
    final camera = '$make $model'.trim();
    final cameraLine = [
      if (camera.isNotEmpty) camera,
      if (lens.isNotEmpty) lens,
    ].join(' · ');

    final micro = tokens.metaStyle.copyWith(
      fontSize: tokens.textSizeMicro,
      height: 1.2,
      color: tokens.textSecondary,
    );

    final oneLineParts = <String>[
      if (exposureLine.isNotEmpty) exposureLine,
      if (cameraLine.isNotEmpty) cameraLine,
    ];
    final oneLineText = oneLineParts.join('  ·  ');

    if (oneLineText.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: _PhotoCard.metaBarHeight,
      padding: _PhotoCard.metaBarPadding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FfTokens.photoHeader,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Text(
        oneLineText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: micro,
      ),
    );
  }
}

class _LowResolutionWarning extends StatelessWidget {
  const _LowResolutionWarning({
    required this.threshold,
    required this.tokens,
  });

  final int threshold;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: FfTokens.dangerBg,
        border: Border(
          bottom: BorderSide(color: FfTokens.dangerBorder),
        ),
      ),
      child: Row(
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.warning,
            color: FfTokens.danger,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Low resolution — longest side is below ${threshold}px',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.metaStyle.copyWith(
                fontSize: tokens.textSizeMicro,
                height: 1.2,
                color: FfTokens.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.controller,
    required this.path,
    required this.tokens,
    required this.ocrHover,
    required this.onSavePrevious,
    required this.onSaveNext,
  });

  static const double metaBarHeight = 30;
  static const EdgeInsets metaBarPadding = EdgeInsets.fromLTRB(8, 0, 8, 0);

  final CaptionV2Controller controller;
  final String? path;
  final FfTokens tokens;
  final ValueNotifier<JerseyOcrSuggestion?> ocrHover;
  final VoidCallback onSavePrevious;
  final VoidCallback onSaveNext;

  String _meta(List<String> keys) {
    for (final key in keys) {
      final value = controller.currentIptcMeta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isLowResolution(String width, String height) {
    final threshold = controller.resolutionWarningThreshold;
    if (threshold <= 0) return false;
    final w = int.tryParse(width);
    final h = int.tryParse(height);
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    final longest = w > h ? w : h;
    return longest < threshold;
  }

  String _formatFileSize(String imagePath) {
    try {
      final bytes = File(imagePath).lengthSync();
      if (bytes >= 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      }
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      if (bytes >= 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }
      return '$bytes B';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = _meta(const ['ImageWidth', 'ExifImageWidth']);
    final height = _meta(const ['ImageHeight', 'ExifImageHeight']);
    final fileSize = path == null ? '' : _formatFileSize(path!);
    final fileName = path == null ? '' : p.basename(path!);
    final dateRaw = _meta(const [
      'DateTimeOriginal',
      'CreateDate',
      'ModifyDate',
    ]);
    final dateLabel = dateRaw.isEmpty ? '' : _formatExifDateTime(dateRaw);
    final fileMeta = [
      if (width.isNotEmpty && height.isNotEmpty) '$width×$height',
      if (fileSize.isNotEmpty) fileSize,
      if (dateLabel.isNotEmpty) dateLabel,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.85)),
        boxShadow: FfTokens.accentButtonGlow(tokens.accent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        child: Column(
          children: [
            if (path != null)
              _PhotoInfoHeader(controller: controller, tokens: tokens),
            if (path != null && _isLowResolution(width, height))
              _LowResolutionWarning(
                threshold: controller.resolutionWarningThreshold,
                tokens: tokens,
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: FfTokens.photoHeader,
                    child: path == null
                        ? Center(
                            child: TextButton(
                              onPressed: controller.pickImageFolder,
                              child: Text(
                                'Open photo folder',
                                style: tokens.labelStyle.copyWith(
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          )
                        : _PhotoLoupePreview(
                            path: path!,
                            version: controller.imageContentStamp(path!),
                            tokens: tokens,
                            controller: controller,
                            ocrHover: ocrHover,
                            onOpenZoom: () =>
                                showCaptionV2Zoom(context, path!),
                            onSecondaryTapDown: (details) =>
                                showCaptionV2PhotoMenu(
                              context: context,
                              controller: controller,
                              imagePath: path!,
                              position: details.globalPosition,
                            ),
                          ),
                  ),
                if (path != null) ...[
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _PhotoPreviewStatusIcons(
                      state: controller.frameStateFor(path!),
                      tokens: tokens,
                    ),
                  ),
                  if (controller.jerseyOcrEnabled)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PhotoOcrScanButton(
                                controller: controller,
                                tokens: tokens,
                              ),
                            ],
                          ),
                          if (controller.jerseySuggestions.isNotEmpty ||
                              controller.jerseyOcrBusy) ...[
                            const SizedBox(height: 8),
                            _PhotoOcrSuggestionChips(
                              controller: controller,
                              tokens: tokens,
                              ocrHover: ocrHover,
                            ),
                          ],
                        ],
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _PhotoFrameCounter(
                      index: controller.currentIndex + 1,
                      total: controller.imagePaths.length,
                      tokens: tokens,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: PhotoSaveArrow(
                        direction: AxisDirection.left,
                        onPressed: onSavePrevious,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: PhotoSaveArrow(
                        direction: AxisDirection.right,
                        onPressed: onSaveNext,
                      ),
                    ),
                  ),
                ],
                if (path != null &&
                    controller.transmitting &&
                    controller.transmittingPath == path)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: TransmitProgressOverlay(
                        progress: controller.transmitProgress,
                        status: controller.transmitStatus,
                        compact: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (path != null)
            Container(
              width: double.infinity,
              height: metaBarHeight,
              padding: metaBarPadding,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FfTokens.photoHeader,
                border: Border(top: BorderSide(color: tokens.divider)),
              ),
              child: Builder(
                builder: (context) {
                  final barStyle = tokens.metaStyle.copyWith(
                    fontSize: tokens.textSizeMicro,
                    height: 1.2,
                    color: tokens.textSecondary,
                  );
                  final line = [
                    fileName,
                    if (fileMeta.isNotEmpty) fileMeta,
                  ].join('  ·  ');
                  return Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: barStyle,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoLoupePreview extends StatefulWidget {
  const _PhotoLoupePreview({
    required this.path,
    required this.version,
    required this.tokens,
    required this.controller,
    required this.ocrHover,
    required this.onOpenZoom,
    required this.onSecondaryTapDown,
  });

  final String path;
  final int version;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final ValueNotifier<JerseyOcrSuggestion?> ocrHover;
  final VoidCallback onOpenZoom;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  State<_PhotoLoupePreview> createState() => _PhotoLoupePreviewState();
}

class _PhotoLoupePreviewState extends State<_PhotoLoupePreview>
    with SingleTickerProviderStateMixin {
  static const double _loupeSize = 148;
  static const double _holdLoupeSize = 196;
  static const double _magnification = 3.0;

  Offset? _cursor;
  Size _viewport = Size.zero;
  Uint8List? _bytes;
  Size? _imageSize;
  Uint8List? _fullBytes;
  Size? _fullSize;
  int _loadToken = 0;
  Timer? _holdTimer;
  Timer? _loupeOcrTimer;
  bool _pointerDown = false;
  Offset? _lastLoupeOcrAt;
  late final AnimationController _holdAnim;

  @override
  void initState() {
    super.initState();
    _holdAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _holdAnim.addListener(() {
      if (mounted) setState(() {});
    });
    _loadBytes();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _loupeOcrTimer?.cancel();
    _holdAnim.dispose();
    super.dispose();
  }

  JerseyOcrSuggestion? _verbAnchor;

  @override
  void didUpdateWidget(covariant _PhotoLoupePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.version != widget.version) {
      widget.ocrHover.value = null;
      _verbAnchor = null;
      _cancelHold();
      _loadBytes();
    }
  }

  void _openVerbsFor(JerseyOcrSuggestion match) {
    _cancelHold();
    widget.controller.selectPlayerFromTextRecognition(match);
    setState(() {
      if (_verbAnchor != null && _sameOcrMark(_verbAnchor!, match)) {
        _verbAnchor = null;
      } else {
        _verbAnchor = match;
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _pointerDown = true;
    _setCursor(event.localPosition);
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || !_pointerDown) return;
      _holdAnim.value = 1.0;
      _scheduleLoupeOcr();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // MouseRegion.onHover often stops while a button is held; keep tracking.
    _setCursor(event.localPosition);
    if (_pointerDown && _holdAnim.value > 0) {
      _scheduleLoupeOcr();
    }
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _loupeOcrTimer?.cancel();
    _loupeOcrTimer = null;
    _lastLoupeOcrAt = null;
    _pointerDown = false;
    if (_holdAnim.value != 0) {
      _holdAnim.value = 0;
    }
  }

  /// Vision ROI under the loupe (normalized, origin bottom-left).
  ///
  /// Tight on purpose so the native crop upscales the number hard.
  JerseyOcrRegion? _loupeRegion(Offset sampleAt, Rect imageRect) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return null;
    final nx = ((sampleAt.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final nyTop =
        ((sampleAt.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0);
    // ~18% of the frame — number + a little jersey fabric, not the boards.
    const halfW = 0.09;
    const halfH = 0.11;
    final left = (nx - halfW).clamp(0.0, 1.0);
    final top = (nyTop - halfH).clamp(0.0, 1.0);
    final right = (nx + halfW).clamp(0.0, 1.0);
    final bottom = (nyTop + halfH).clamp(0.0, 1.0);
    final width = (right - left).clamp(0.05, 1.0);
    final height = (bottom - top).clamp(0.05, 1.0);
    // Convert top-left normalized → Vision bottom-left origin.
    final visionY = (1.0 - top - height).clamp(0.0, 1.0);
    return JerseyOcrRegion(
      x: left,
      y: visionY,
      width: width,
      height: height,
    );
  }

  void _scheduleLoupeOcr() {
    if (!widget.controller.jerseyOcrEnabled) return;
    _loupeOcrTimer?.cancel();
    // Settle briefly so tiny pointer jitter doesn't cancel the native scan.
    _loupeOcrTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || !_pointerDown || _holdAnim.value <= 0) return;
      if (!widget.controller.jerseyOcrEnabled) return;
      final cursor = _cursor;
      final bytes = _bytes;
      final imageSize = _imageSize;
      if (cursor == null || bytes == null || imageSize == null) return;
      final imageRect = _containRect(_viewport, imageSize);
      if (imageRect.isEmpty) return;
      final sampleAt = _clampToRect(cursor, imageRect);
      final last = _lastLoupeOcrAt;
      // Skip re-scan when the cursor barely moved (keeps in-flight OCR alive).
      if (last != null && (sampleAt - last).distance < 10) return;
      final region = _loupeRegion(sampleAt, imageRect);
      if (region == null) return;
      _lastLoupeOcrAt = sampleAt;
      unawaited(widget.controller.runOcrLoupeScan(region));
    });
  }

  Offset _clampToRect(Offset point, Rect rect) {
    return Offset(
      point.dx.clamp(rect.left, rect.right),
      point.dy.clamp(rect.top, rect.bottom),
    );
  }

  Future<void> _loadBytes() async {
    final token = ++_loadToken;
    setState(() {
      _bytes = null;
      _imageSize = null;
      _fullBytes = null;
      _fullSize = null;
      _cursor = null;
    });
    // Preview first for snappy hover, then full pixels for true 100% hold.
    final bytes = await OrientedImageBytes.load(
      widget.path,
      maxWidth: OrientedImageBytes.previewMaxWidth,
    );
    if (!mounted || token != _loadToken || bytes == null) return;
    final size = await _decodeImageSize(bytes);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _bytes = bytes;
      _imageSize = size;
    });
    unawaited(_loadFullBytes(token));
  }

  Future<void> _loadFullBytes(int token) async {
    final bytes = await OrientedImageBytes.load(
      widget.path,
      maxWidth: OrientedImageBytes.loupeMaxWidth,
    );
    if (!mounted || token != _loadToken || bytes == null) return;
    final size = await _decodeImageSize(bytes);
    if (!mounted || token != _loadToken || size == null) return;
    setState(() {
      _fullBytes = bytes;
      _fullSize = size;
    });
  }

  Future<Size?> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Rect _containRect(Size viewport, Size image) {
    if (viewport.isEmpty || image.isEmpty) return Rect.zero;
    final fitted = applyBoxFit(BoxFit.contain, image, viewport).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & viewport);
  }

  void _setCursor(Offset? next) {
    if (_cursor == next) return;
    setState(() => _cursor = next);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final imageSize = _imageSize;
    final cursor = _cursor;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final imageRect = bytes != null && imageSize != null
            ? _containRect(_viewport, imageSize)
            : Rect.zero;
        final overImage = cursor != null &&
            imageRect.isEmpty == false &&
            imageRect.contains(cursor);
        final showLoupe = cursor != null &&
            imageRect.isEmpty == false &&
            (overImage || _pointerDown);
        final sampleAt = showLoupe
            ? _clampToRect(cursor, imageRect)
            : null;

        return MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          onHover: (event) => _setCursor(event.localPosition),
          onExit: (_) {
            if (_pointerDown) return;
            _cancelHold();
            _setCursor(null);
          },
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: (_) => _cancelHold(),
            onPointerCancel: (_) => _cancelHold(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onOpenZoom,
              onSecondaryTapDown: widget.onSecondaryTapDown,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes == null)
                    Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.tokens.accent,
                        ),
                      ),
                    )
                  else
                    Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  if (!imageRect.isEmpty)
                    _OcrNumberMarks(
                      imageRect: imageRect,
                      matches: widget.controller.jerseySuggestions,
                      hover: widget.ocrHover,
                      enabled: widget.controller.jerseyOcrEnabled,
                      controller: widget.controller,
                      verbAnchor: _verbAnchor,
                      onNameTap: _openVerbsFor,
                      onVerbPicked: () => setState(() => _verbAnchor = null),
                    ),
                  if (showLoupe && sampleAt != null) ...[
                    _buildLoupe(
                      cursor: cursor,
                      sampleAt: sampleAt,
                      imageRect: imageRect,
                    ),
                    // Fixed chrome tip — don't glue copy to the loupe.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: IgnorePointer(
                        child: Center(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Color(0xA6000000),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(6)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                widget.controller.jerseyOcrEnabled
                                    ? 'Hold for 100% + OCR  ·  Double-click to open'
                                    : 'Hold for 100%  ·  Double-click to open',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoupe({
    required Offset cursor,
    required Offset sampleAt,
    required Rect imageRect,
  }) {
    final viewport = _viewport;
    final bytes = _bytes;
    if (bytes == null || viewport.isEmpty) return const SizedBox.shrink();

    final t = _holdAnim.value;
    // Prefer full-res once ready so hold can be true 100% (1:1 pixels).
    final paintBytes = (t > 0 && _fullBytes != null) ? _fullBytes! : bytes;
    final paintSize = (t > 0 && _fullSize != null) ? _fullSize! : _imageSize;
    // 100% = one image pixel per logical screen pixel.
    final oneToOne = (paintSize != null && imageRect.width > 0)
        ? paintSize.width / imageRect.width
        : _magnification;
    final holdMagnification =
        oneToOne > _magnification ? oneToOne : _magnification;
    final magnification =
        _magnification + (holdMagnification - _magnification) * t;
    final loupeSize = _loupeSize + (_holdLoupeSize - _loupeSize) * t;

    final maxLeft =
        (viewport.width - loupeSize - 4).clamp(4.0, double.infinity);
    final maxTop =
        (viewport.height - loupeSize - 4).clamp(4.0, double.infinity);
    final left = (cursor.dx - loupeSize / 2).clamp(4.0, maxLeft);
    final top = (cursor.dy - loupeSize / 2).clamp(4.0, maxTop);

    final localX = sampleAt.dx - imageRect.left;
    final localY = sampleAt.dy - imageRect.top;
    final magnifiedW = imageRect.width * magnification;
    final magnifiedH = imageRect.height * magnification;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: loupeSize,
          height: loupeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.92),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: ColoredBox(
              color: widget.tokens.sunken,
              // Positioned (not Transform+SizedBox): Stack would otherwise
              // clamp the magnified image to 148×148, then translate it away.
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: loupeSize / 2 - localX * magnification,
                    top: loupeSize / 2 - localY * magnification,
                    width: magnifiedW,
                    height: magnifiedH,
                    child: Image.memory(
                      paintBytes,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.75),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _sameOcrMark(JerseyOcrSuggestion a, JerseyOcrSuggestion b) {
  return a.isHome == b.isHome &&
      a.player == b.player &&
      a.matchedText == b.matchedText;
}

class _OcrNumberMarks extends StatelessWidget {
  const _OcrNumberMarks({
    required this.imageRect,
    required this.matches,
    required this.hover,
    required this.enabled,
    required this.controller,
    required this.verbAnchor,
    required this.onNameTap,
    required this.onVerbPicked,
  });

  final Rect imageRect;
  final List<JerseyOcrSuggestion> matches;
  final ValueNotifier<JerseyOcrSuggestion?> hover;
  final bool enabled;
  final CaptionV2Controller controller;
  final JerseyOcrSuggestion? verbAnchor;
  final ValueChanged<JerseyOcrSuggestion> onNameTap;
  final VoidCallback onVerbPicked;

  @override
  Widget build(BuildContext context) {
    final marks = _playerMarks(matches);
    if (!enabled || imageRect.isEmpty || marks.isEmpty) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<JerseyOcrSuggestion?>(
      valueListenable: hover,
      builder: (context, hovered, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final match in marks) ..._mark(match, hovered),
          ],
        );
      },
    );
  }

  /// One box per player match. Same spot keeps the stronger match.
  /// One mark per box. [matches] is already ranked (confirmed name+number
  /// first), so the first player seen at a spot is the one we label.
  List<JerseyOcrSuggestion> _playerMarks(List<JerseyOcrSuggestion> matches) {
    final best = <String, JerseyOcrSuggestion>{};
    for (final match in matches) {
      final box = match.box;
      if (box == null || box.width <= 0.004 || box.height <= 0.004) continue;
      final key = '${(box.x * 40).round()}|${(box.y * 40).round()}|'
          '${(box.width * 40).round()}|${(box.height * 40).round()}';
      best.putIfAbsent(key, () => match);
    }
    return best.values.toList();
  }

  bool _isHovered(JerseyOcrSuggestion match, JerseyOcrSuggestion? hovered) {
    if (hovered == null) return false;
    return identical(match, hovered) ||
        (match.player == hovered.player &&
            match.isHome == hovered.isHome &&
            match.matchedText == hovered.matchedText);
  }

  List<Widget> _mark(JerseyOcrSuggestion match, JerseyOcrSuggestion? hovered) {
    final box = match.box;
    if (box == null) return const [];
    final rect = _photoRect(box);
    if (rect.width < 2 || rect.height < 2) return const [];
    final emphasized = _isHovered(match, hovered);
    final color = emphasized ? _ocrTargetTealHot : _ocrTargetTeal;
    final label = _ocrMatchLabel(match);
    final detail = _ocrTargetDetail(match);
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
    final landscape = imageRect.width >= imageRect.height;
    // Landscape photos: name centered above the box.
    // Portrait photos: name centered on the right of the box.
    final namePosition = landscape
        ? (
            left: rect.center.dx,
            top: (rect.top - 16).clamp(imageRect.top, imageRect.bottom),
            translation: const Offset(-0.5, -1),
          )
        : (
            left: (rect.right + 4).clamp(imageRect.left, imageRect.right),
            top: rect.center.dy,
            translation: const Offset(0, -0.5),
          );
    final nameChip = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(label, style: labelStyle),
      ),
    );
    final showVerbs =
        verbAnchor != null && _sameOcrMark(verbAnchor!, match);
    final menuTop = landscape
        ? namePosition.top + 4
        : namePosition.top + 12;
    final menuLeft = landscape
        ? (rect.center.dx - 100).clamp(imageRect.left, imageRect.right - 8)
        : namePosition.left;
    return [
      Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: emphasized ? 0.28 : 0.16),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: emphasized ? 2.5 : 2),
            ),
          ),
        ),
      ),
      Positioned(
        left: namePosition.left,
        top: namePosition.top,
        child: FractionalTranslation(
          translation: namePosition.translation,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => hover.value = match,
            onExit: (_) {
              if (identical(hover.value, match)) hover.value = null;
            },
            child: Tooltip(
              message: detail.isEmpty ? label : detail,
              waitDuration: const Duration(milliseconds: 250),
              child: GestureDetector(
                onTap: () => onNameTap(match),
                child: nameChip,
              ),
            ),
          ),
        ),
      ),
      if (showVerbs)
        Positioned(
          left: menuLeft,
          top: menuTop.clamp(imageRect.top, imageRect.bottom - 40),
          child: _PhotoVerbCascade(
            controller: controller,
            maxHeight: (imageRect.bottom - menuTop - 8).clamp(120.0, 340.0),
            onPicked: onVerbPicked,
          ),
        ),
    ];
  }

  /// Vision box (origin bottom-left) → photo pixels (origin top-left).
  Rect _photoRect(JerseyOcrRegion box) {
    final raw = Rect.fromLTWH(
      imageRect.left + box.x * imageRect.width,
      imageRect.top + (1 - box.y - box.height) * imageRect.height,
      box.width * imageRect.width,
      box.height * imageRect.height,
    );
    final padded = raw.inflate(4);
    return Rect.fromLTRB(
      padded.left.clamp(imageRect.left, imageRect.right),
      padded.top.clamp(imageRect.top, imageRect.bottom),
      padded.right.clamp(imageRect.left, imageRect.right),
      padded.bottom.clamp(imageRect.top, imageRect.bottom),
    );
  }
}

/// Category cascade that floats on the photo after a scanned name is tapped.
class _PhotoVerbCascade extends StatefulWidget {
  const _PhotoVerbCascade({
    required this.controller,
    required this.maxHeight,
    required this.onPicked,
  });

  final CaptionV2Controller controller;
  final double maxHeight;
  final VoidCallback onPicked;

  @override
  State<_PhotoVerbCascade> createState() => _PhotoVerbCascadeState();
}

class _PhotoVerbCascadeState extends State<_PhotoVerbCascade> {
  String _open = '';

  @override
  void initState() {
    super.initState();
    final cats = widget.controller.verbCategories;
    final current = widget.controller.verbCategory;
    if (current != null && cats.contains(current)) {
      _open = current;
    } else if (cats.contains('Offense')) {
      _open = 'Offense';
    } else if (cats.isNotEmpty) {
      _open = cats.first;
    }
  }

  String _display(String category) {
    if (category == 'Non Game-Action') return 'Non-game';
    return category;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final categories = widget.controller.verbCategories;
    final verbsByCat = widget.controller.verbDefinitionsByCategory;
    return Material(
      elevation: 10,
      color: t.surface,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 200,
          maxHeight: widget.maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: t.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final category in categories) ...[
                InkWell(
                  onTap: () => setState(() {
                    _open = _open == category ? '' : category;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _display(category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _open == category ? t.accent : t.text,
                            ),
                          ),
                        ),
                        Icon(
                          _open == category
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 16,
                          color: t.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_open == category)
                  for (final verb in verbsByCat[category] ?? const [])
                    InkWell(
                      onTap: () {
                        widget.controller.selectVerb(verb.key);
                        widget.onPicked();
                      },
                      child: Container(
                        color: widget.controller.selectedVerb == verb.key
                            ? t.accent.withValues(alpha: 0.16)
                            : null,
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        child: Text(
                          verb.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: widget.controller.selectedVerb == verb.key
                                ? t.accent
                                : t.text,
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoOcrSuggestionChips extends StatelessWidget {
  const _PhotoOcrSuggestionChips({
    required this.controller,
    required this.tokens,
    required this.ocrHover,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final ValueNotifier<JerseyOcrSuggestion?> ocrHover;

  @override
  Widget build(BuildContext context) {
    final matches = controller.jerseySuggestions;
    if (controller.jerseyOcrBusy && matches.isEmpty) {
      return Material(
        color: FfTokens.viewerChrome,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: tokens.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Scanning…',
                style: tokens.metaStyle.copyWith(
                  fontSize: 11,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (matches.isEmpty) {
      return controller.jerseyOcrPrescanActive
          ? _PrescanBadge(controller: controller, tokens: tokens)
          : const SizedBox.shrink();
    }

    return ValueListenableBuilder<JerseyOcrSuggestion?>(
      valueListenable: ocrHover,
      builder: (context, hovered, _) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final match in matches.take(6))
                _OcrMatchChip(
                  match: match,
                  tokens: tokens,
                  selected: controller.isPlayerSelected(
                    match.player,
                    isHome: match.isHome,
                  ),
                  hovered: identical(hovered, match),
                  onHover: (value) => ocrHover.value = value,
                  onTap: () =>
                      controller.selectPlayerFromTextRecognition(match),
                ),
              if (controller.jerseyOcrPrescanActive)
                _PrescanBadge(controller: controller, tokens: tokens),
            ],
          ),
        );
      },
    );
  }
}

/// "Pre-scan 12/80" — background OCR warming the rest of the folder.
class _PrescanBadge extends StatelessWidget {
  const _PrescanBadge({required this.controller, required this.tokens});

  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 350),
      message: 'Text recognition is scanning the rest of the folder in the '
          'background so each frame is ready when you get to it.',
      child: Material(
        color: FfTokens.viewerChrome,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: tokens.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Pre-scan ${controller.jerseyOcrPrescanDone}/'
                '${controller.jerseyOcrPrescanTotal}',
                style: tokens.metaStyle.copyWith(
                  fontSize: 11,
                  color: tokens.textTertiary,
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: controller.stopJerseyOcrPrescan,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.text,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  'Stop',
                  style: tokens.metaStyle.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OcrMatchChip extends StatelessWidget {
  const _OcrMatchChip({
    required this.match,
    required this.tokens,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  final JerseyOcrSuggestion match;
  final FfTokens tokens;
  final bool selected;
  final bool hovered;
  final ValueChanged<JerseyOcrSuggestion?> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _ocrMatchLabel(match);
    return MouseRegion(
      onEnter: (_) => onHover(match),
      onExit: (_) => onHover(null),
      child: Tooltip(
      message:
          '${match.isHome ? 'Home' : 'Away'} · matched “${match.matchedText}” '
          '(${match.matchKind == JerseyOcrMatchKind.jersey ? 'jersey' : 'name'})',
      child: Material(
        // Opaque fills: these chips sit over the photo, so any alpha lets the
        // image bleed through the text.
        color: hovered
            ? Color.alphaBlend(
                _ocrTargetTeal.withValues(alpha: 0.32),
                FfTokens.viewerChrome,
              )
            : selected
                ? Color.alphaBlend(
                    tokens.accent.withValues(alpha: 0.45),
                    FfTokens.viewerChrome,
                  )
                : FfTokens.viewerChrome,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: hovered
                    ? _ocrTargetTealHot
                    : selected
                        ? tokens.accent.withValues(alpha: 0.55)
                        : tokens.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metaStyle.copyWith(
                      fontSize: 11,
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _PhotoOcrScanButton extends StatefulWidget {
  const _PhotoOcrScanButton({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  State<_PhotoOcrScanButton> createState() => _PhotoOcrScanButtonState();
}

class _PhotoOcrScanButtonState extends State<_PhotoOcrScanButton> {
  bool _busy = false;

  Future<void> _runScan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.controller.runOcrTestScan(force: true);
      if (!mounted) return;
      await _showOcrScanDialog(
        context: context,
        controller: widget.controller,
        tokens: widget.tokens,
        result: result,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final supported = JerseyOcrChannel.supported;
    return Tooltip(
      message: supported
          ? 'Re-scan full frame (hold loupe to scan a spot)'
          : 'OCR scan is macOS-only',
      child: Material(
        color: FfTokens.viewerChrome,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: supported && !_busy ? _runScan : null,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: tokens.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy || widget.controller.jerseyOcrBusy)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: tokens.accent,
                    ),
                  )
                else
                  PhosphorIcon(
                    PhosphorIconsRegular.scan,
                    size: 14,
                    color: supported
                        ? tokens.text
                        : tokens.text.withValues(alpha: 0.35),
                  ),
                const SizedBox(width: 6),
                Text(
                  'Scan',
                  style: tokens.labelStyle.copyWith(
                    fontSize: 11,
                    height: 1.1,
                    color: supported
                        ? tokens.text
                        : tokens.text.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showOcrScanDialog({
  required BuildContext context,
  required CaptionV2Controller controller,
  required FfTokens tokens,
  required OcrScanResult result,
}) {
  final hits = result.hits;
  final matches = result.matches;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: tokens.elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          side: BorderSide(color: tokens.divider),
        ),
        title: Text(
          'OCR test scan',
          style: tokens.labelStyle.copyWith(fontSize: 15),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!result.supported)
                Text(
                  'On-device OCR is only available on macOS.',
                  style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
                )
              else ...[
                Text(
                  hits.isEmpty
                      ? 'No text found in this frame.'
                      : 'Found ${hits.length} text region${hits.length == 1 ? '' : 's'}.',
                  style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
                ),
                if (hits.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final hit in hits.take(24))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.sunken,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tokens.divider),
                          ),
                          child: Text(
                            hit.text,
                            style: tokens.metaStyle.copyWith(
                              fontSize: 11,
                              color: tokens.text,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  matches.isEmpty
                      ? 'No roster matches.'
                      : 'Roster matches (${matches.length})',
                  style: tokens.labelStyle.copyWith(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                ),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: tokens.divider,
                      ),
                      itemBuilder: (context, index) {
                        final match = matches[index];
                        final side = match.isHome ? 'Home' : 'Away';
                        final kind = match.matchKind == JerseyOcrMatchKind.jersey
                            ? 'jersey'
                            : 'name';
                        final label = _ocrMatchLabel(match);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            label,
                            style: tokens.metaStyle.copyWith(
                              fontSize: 12,
                              color: tokens.text,
                            ),
                          ),
                          subtitle: Text(
                            '$side · matched “${match.matchedText}” ($kind) · '
                            '${(match.confidence * 100).round()}%',
                            style: tokens.metaStyle.copyWith(
                              fontSize: 10,
                              color: tokens.textSecondary,
                            ),
                          ),
                          trailing: Text(
                            'Select',
                            style: tokens.labelStyle.copyWith(
                              fontSize: 11,
                              color: tokens.accent,
                            ),
                          ),
                          onTap: () {
                            controller.selectPlayerFromTextRecognition(match);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: tokens.labelStyle.copyWith(color: tokens.accent),
            ),
          ),
        ],
      );
    },
  );
}

class _PhotoPreviewStatusIcons extends StatelessWidget {
  const _PhotoPreviewStatusIcons({
    required this.state,
    required this.tokens,
  });

  final FrameState state;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final saved = state != FrameState.todo;
    final sent = state == FrameState.sent;
    return Material(
      color: FfTokens.viewerChrome,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: tokens.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: saved ? 'Saved' : 'Not saved',
              child: PhosphorIcon(PhosphorIconsRegular.floppyDisk,
                size: 15,
                color: saved
                    ? FrameStatusColors.saved
                    : tokens.text.withValues(alpha: 0.28),
              ),
            ),
            const SizedBox(width: 7),
            Tooltip(
              message: sent ? "FTP'd" : 'Not sent',
              child: PhosphorIcon(PhosphorIconsRegular.cloudArrowUp,
                size: 15,
                color: sent
                    ? FrameStatusColors.sent
                    : tokens.text.withValues(alpha: 0.28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PhotoSaveArrow extends StatelessWidget {
  const PhotoSaveArrow({
    super.key,
    required this.direction,
    required this.onPressed,
  });

  final AxisDirection direction;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final previous = direction == AxisDirection.left;
    return Tooltip(
      message: previous ? 'Save & previous' : 'Save & next (⌘S)',
      child: Material(
        color: t.surface.withValues(alpha: 0.82),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: CircleBorder(side: BorderSide(color: t.divider)),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 34,
            child: Icon(
              previous
                  ? PhosphorIconsRegular.caretLeft
                  : PhosphorIconsRegular.caretRight,
              size: 15,
              color: t.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailGrid extends StatefulWidget {
  const _ThumbnailGrid({
    required this.controller,
    required this.tokens,
    required this.maxColumns,
    required this.focused,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final int maxColumns;
  final bool focused;

  @override
  State<_ThumbnailGrid> createState() => _ThumbnailGridState();
}

class _ThumbnailGridState extends State<_ThumbnailGrid> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Thumbnail grid');
  Set<String> _marqueeBase = {};
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeDragging = false;
  int _columnCount = 3;
  _BrowseScope _scope = _BrowseScope.all;
  _BrowseSort _sort = _BrowseSort.captureAscending;
  int _lastSessionGeneration = -1;
  bool _repairScheduled = false;
  String? _visibilitySignature;
  int _lastWarmFirst = -1;

  CaptionV2Controller get controller => widget.controller;
  FfTokens get tokens => widget.tokens;
  Set<String> get _selectedPaths => controller.selectedImagePaths;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_warmAheadOfScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_warmAheadOfScroll);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _warmAheadOfScroll() {
    if (!_scrollController.hasClients) return;
    final paths = _visiblePaths;
    if (paths.isEmpty) return;
    final columns = _columnCount.clamp(2, widget.maxColumns);
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    if (viewport <= 0) return;
    // Match GridView childAspectRatio 0.88 + 8px padding/spacing roughly.
    final cellH = (position.maxScrollExtent > 0 || paths.length > columns)
        ? (viewport / 3.2)
        : viewport;
    final rowH = cellH + 8;
    final firstRow = (position.pixels / rowH).floor().clamp(0, 1 << 20);
    final first = (firstRow * columns).clamp(0, paths.length);
    if (first == _lastWarmFirst) return;
    _lastWarmFirst = first;
    // Warm a deep window ahead of the scroll so flinging to the bottom
    // still hits decoded thumbs (folder preload continues in parallel).
    final end = (first + columns * 48).clamp(0, paths.length);
    if (first >= end) return;
    controller.warmThumbnailPaths(paths.sublist(first, end));
  }

  List<String> get _visiblePaths {
    final paths = controller.imagePaths.where((path) {
      switch (_scope) {
        case _BrowseScope.all:
          return true;
        case _BrowseScope.toCaption:
          return !controller.captionedImages.contains(path);
        case _BrowseScope.captioned:
          return controller.captionedImages.contains(path);
        case _BrowseScope.toFtp:
          return !controller.sentImages.contains(path);
        case _BrowseScope.ftp:
          return controller.sentImages.contains(path);
      }
    }).toList();
    paths.sort(_comparePaths);
    return paths;
  }

  int _comparePaths(String a, String b) {
    final filenameComparison =
        p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
    switch (_sort) {
      case _BrowseSort.filenameAscending:
        return filenameComparison;
      case _BrowseSort.filenameDescending:
        return -filenameComparison;
      case _BrowseSort.captureAscending:
      case _BrowseSort.captureDescending:
        final aCapture = controller.captureByPath[a];
        final bCapture = controller.captureByPath[b];
        if (aCapture == null && bCapture == null) return filenameComparison;
        if (aCapture == null) return 1;
        if (bCapture == null) return -1;
        final comparison = aCapture.compareTo(bCapture);
        if (comparison == 0) return filenameComparison;
        return _sort == _BrowseSort.captureAscending ? comparison : -comparison;
    }
  }

  void _setScope(_BrowseScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _selectedPaths.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    _repairSelectionIfHidden();
  }

  void _setSort(_BrowseSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _adjustColumns(int delta, int maxColumns) {
    final current = _columnCount.clamp(2, maxColumns);
    setState(() => _columnCount = (current + delta).clamp(2, maxColumns));
  }

  void _selectThumbnail(List<String> paths, int index) {
    _focusNode.requestFocus();
    controller.setColumnFocus(3);
    final path = paths[index];
    final keyboard = HardwareKeyboard.instance;
    final additive = keyboard.isMetaPressed || keyboard.isControlPressed;

    if (keyboard.isShiftPressed) {
      final anchor = paths.indexOf(controller.currentPath ?? '');
      setState(() {
        if (_selectedPaths.isEmpty && controller.currentPath != null) {
          _selectedPaths.add(controller.currentPath!);
        }
        if (anchor < 0) {
          _selectedPaths.add(path);
        } else {
          final start = anchor < index ? anchor : index;
          final end = anchor > index ? anchor : index;
          _selectedPaths.addAll(paths.sublist(start, end + 1));
        }
      });
      return;
    }

    if (additive) {
      setState(() {
        if (_selectedPaths.isEmpty && controller.currentPath != null) {
          _selectedPaths.add(controller.currentPath!);
        }
        if (!_selectedPaths.remove(path)) _selectedPaths.add(path);
      });
      return;
    }

    if (_selectedPaths.isNotEmpty) {
      setState(_selectedPaths.clear);
    }
    controller.goToIndex(controller.imagePaths.indexOf(path));
  }

  void _startMarquee(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    final additive = keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed;
    _marqueeStart = event.localPosition;
    _marqueeCurrent = event.localPosition;
    _marqueeDragging = false;
    _marqueeBase = additive ? Set<String>.from(_selectedPaths) : {};
    if (additive && _marqueeBase.isEmpty && controller.currentPath != null) {
      _marqueeBase.add(controller.currentPath!);
    }
  }

  void _updateMarquee(
    PointerMoveEvent event, {
    required List<String> paths,
    required int columns,
    required double spacing,
    required double itemWidth,
  }) {
    final start = _marqueeStart;
    if (start == null || event.buttons & kPrimaryMouseButton == 0) return;
    if (!_marqueeDragging && (event.localPosition - start).distance < 4) return;

    _marqueeDragging = true;
    _focusNode.requestFocus();
    if (controller.columnFocus != 3) controller.setColumnFocus(3);
    final current = event.localPosition;
    final marquee = Rect.fromPoints(start, current);
    final itemHeight = itemWidth / 0.88;
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final hits = <String>{};
    for (var i = 0; i < paths.length; i++) {
      final column = i % columns;
      final row = i ~/ columns;
      final itemRect = Rect.fromLTWH(
        8 + column * (itemWidth + spacing),
        8 + row * (itemHeight + spacing) - scrollOffset,
        itemWidth,
        itemHeight,
      );
      if (marquee.overlaps(itemRect)) hits.add(paths[i]);
    }

    setState(() {
      _marqueeCurrent = current;
      _selectedPaths
        ..clear()
        ..addAll(_marqueeBase)
        ..addAll(hits);
    });
  }

  void _endMarquee(PointerEvent event) {
    if (_marqueeStart == null) return;
    setState(() {
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueeDragging = false;
      _marqueeBase = {};
    });
  }

  Future<void> _showThumbnailMenu(
    BuildContext context,
    String path,
    Offset position,
  ) async {
    _focusNode.requestFocus();
    controller.setColumnFocus(3);
    final useSelection = _selectedPaths.contains(path);
    final targets = useSelection ? _selectedPaths.toList() : <String>[path];
    if (!useSelection && _selectedPaths.isNotEmpty) {
      setState(_selectedPaths.clear);
    }
    await showCaptionV2PhotoMenu(
      context: context,
      controller: controller,
      imagePath: path,
      position: position,
      pasteTargets: targets,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final columns = _columnCount.clamp(2, widget.maxColumns);
    var delta = 0;
    if (key == LogicalKeyboardKey.arrowLeft) {
      delta = -1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      delta = 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -columns;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      delta = columns;
    }
    if (delta == 0) return KeyEventResult.ignored;

    final paths = _visiblePaths;
    if (paths.isEmpty) return KeyEventResult.handled;
    final current = paths.indexOf(controller.currentPath ?? '');
    final start = current < 0 ? 0 : current;
    final next = (start + delta).clamp(0, paths.length - 1);
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        if (current >= 0) _selectedPaths.add(paths[current]);
        _selectedPaths.add(paths[next]);
      });
    } else if (_selectedPaths.isNotEmpty) {
      setState(_selectedPaths.clear);
    }
    controller.goToIndex(controller.imagePaths.indexOf(paths[next]));
    return KeyEventResult.handled;
  }

  void _repairSelectionIfHidden() {
    final current = controller.currentPath;
    final visible = _visiblePaths;
    if (current == null || visible.isEmpty || visible.contains(current)) return;
    final oldIndex = controller.currentIndex;
    var bestPath = visible.first;
    var bestDistance = controller.imagePaths.indexOf(bestPath) - oldIndex;
    for (final path in visible.skip(1)) {
      final distance = controller.imagePaths.indexOf(path) - oldIndex;
      if ((distance >= 0 && bestDistance < 0) ||
          (distance >= 0 && bestDistance >= 0 && distance < bestDistance) ||
          (distance < 0 &&
              bestDistance < 0 &&
              distance.abs() < bestDistance.abs())) {
        bestPath = path;
        bestDistance = distance;
      }
    }
    controller.goToIndex(controller.imagePaths.indexOf(bestPath));
  }

  void _scheduleRepairIfNeeded(List<String> visible) {
    final current = controller.currentPath;
    if (_repairScheduled ||
        current == null ||
        visible.isEmpty ||
        visible.contains(current)) {
      return;
    }
    _repairScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repairScheduled = false;
      if (mounted) _repairSelectionIfHidden();
    });
  }

  void _keepCurrentThumbnailVisible({
    required List<String> paths,
    required int columns,
    required double spacing,
    required double itemWidth,
  }) {
    final current = controller.currentPath;
    final selectedIndex = current == null ? -1 : paths.indexOf(current);
    if (selectedIndex < 0) return;

    final signature = [
      current,
      selectedIndex,
      paths.length,
      columns,
    ].join(':');
    if (_visibilitySignature == signature) return;
    _visibilitySignature = signature;

    final itemHeight = itemWidth / 0.88;
    final row = selectedIndex ~/ columns;
    final itemTop = 8 + row * (itemHeight + spacing);
    final itemBottom = itemTop + itemHeight;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _visibilitySignature != signature ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final itemCenter = (itemTop + itemBottom) / 2;
      final target = (itemCenter - (position.viewportDimension / 2))
          .clamp(0, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() < 1) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  /// Shared with [OrientedImageBytes] warmup so scroll hits the same cache keys.
  int get _thumbCacheWidth => OrientedImageBytes.thumbMaxWidth;

  String _captureTime(String path) {
    final value = controller.captureByPath[path];
    if (value == null) return '';
    return _twelveHourTime(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_lastSessionGeneration != controller.sessionGeneration) {
      _lastSessionGeneration = controller.sessionGeneration;
      _scope = _BrowseScope.all;
      _selectedPaths.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    final allPaths = controller.imagePaths;
    if (allPaths.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.85)),
          boxShadow: FfTokens.accentButtonGlow(tokens.accent),
        ),
        child: FfGlow(
          glowW: 260,
          glowH: 160,
          child: Text('No images', style: tokens.metaStyle),
        ),
      );
    }

    final paths = _visiblePaths;
    final captionedCount = allPaths
        .where((path) => controller.captionedImages.contains(path))
        .length;
    final sentCount =
        allPaths.where((path) => controller.sentImages.contains(path)).length;
    final maxColumns = widget.maxColumns;
    final columnCount = _columnCount.clamp(2, maxColumns);
    _scheduleRepairIfNeeded(paths);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          border: Border.all(
            color: tokens.accent.withValues(alpha: widget.focused ? 1 : 0.85),
            width: 1,
          ),
          boxShadow: FfTokens.accentButtonGlow(tokens.accent),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          child: Column(
          children: [
            _ThumbnailToolbar(
              tokens: tokens,
              sort: _sort,
              columnCount: columnCount,
              maxColumns: maxColumns,
              refreshing: controller.refreshingFolder,
              onSortChanged: _setSort,
              onRefresh: controller.refreshOpenFolder,
              onOpenOverview: () =>
                  showCaptionV2ThumbnailOverview(context, controller),
              onSmaller: columnCount >= maxColumns
                  ? null
                  : () => _adjustColumns(1, maxColumns),
              onLarger: columnCount <= 2
                  ? null
                  : () => _adjustColumns(-1, maxColumns),
            ),
            Expanded(
              child: paths.isEmpty
                  ? Center(
                      child: FfGlow(
                        glowW: 320,
                        glowH: 180,
                        child: Text(
                          'No images match current filters',
                          style: tokens.metaStyle,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final spacing =
                            (constraints.maxWidth * 0.015).clamp(6.0, 14.0);
                        final columns = columnCount;
                        final contentWidth = (constraints.maxWidth - 16)
                            .clamp(1.0, double.infinity);
                        final itemWidth =
                            ((contentWidth - spacing * (columns - 1)) / columns)
                                .clamp(1.0, contentWidth);
                        _keepCurrentThumbnailVisible(
                          paths: paths,
                          columns: columns,
                          spacing: spacing,
                          itemWidth: itemWidth,
                        );
                        return Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _startMarquee,
                          onPointerMove: (event) => _updateMarquee(
                            event,
                            paths: paths,
                            columns: columns,
                            spacing: spacing,
                            itemWidth: itemWidth,
                          ),
                          onPointerUp: _endMarquee,
                          onPointerCancel: _endMarquee,
                          child: Stack(
                            children: [
                              GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(8),
                                cacheExtent: 2200,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: spacing,
                                  crossAxisSpacing: spacing,
                                  childAspectRatio: 0.88,
                                ),
                                itemCount: paths.length,
                                itemBuilder: (context, i) {
                                  final path = paths[i];
                                  final originalIndex =
                                      controller.imagePaths.indexOf(path);
                                  final selected = _selectedPaths.isEmpty
                                      ? originalIndex == controller.currentIndex
                                      : _selectedPaths.contains(path);
                                  final captioned =
                                      controller.captionedImages.contains(path);
                                  final ftp =
                                      controller.sentImages.contains(path);
                                  final borderColor = selected
                                      ? tokens.accent
                                      : Colors.white;
                                  return GestureDetector(
                                    key: ValueKey(path),
                                    onTap: () => _selectThumbnail(paths, i),
                                    onSecondaryTapDown: (details) =>
                                        _showThumbnailMenu(
                                      context,
                                      path,
                                      details.globalPosition,
                                    ),
                                    child: Tooltip(
                                      message: p.basename(path),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? tokens.hover
                                              : FfTokens.card,
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          border: Border.all(
                                            color: borderColor,
                                            width: selected ? 0.8 : 0.5,
                                          ),
                                          boxShadow: selected
                                              ? FfTokens.selectionGlow(
                                                  tokens.accent,
                                                )
                                              : [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.22),
                                                    blurRadius: 8,
                                                    spreadRadius: 0,
                                                  ),
                                                ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    OrientedFilePreview(
                                                      path: path,
                                                      version: controller
                                                          .imageContentStamp(
                                                              path),
                                                      fit: BoxFit.contain,
                                                      cacheWidth:
                                                          _thumbCacheWidth,
                                                    ),
                                                    if (controller
                                                            .transmitting &&
                                                        controller
                                                                .transmittingPath ==
                                                            path)
                                                      Positioned.fill(
                                                        child:
                                                            TransmitProgressOverlay(
                                                          progress: controller
                                                              .transmitProgress,
                                                          status: controller
                                                              .transmitStatus,
                                                          compact: true,
                                                        ),
                                                      ),
                                                    Positioned(
                                                      top: 4,
                                                      right: 4,
                                                      child: FrameStatusBadges(
                                                        saved: captioned,
                                                        sent: ftp,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _shortThumbName(p.basename(path)),
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: tokens.monoMetaStyle
                                                  .copyWith(
                                                color: tokens.textSecondary,
                                                fontSize: 10.5,
                                                fontWeight:
                                                    FfTokens.weightRegular,
                                              ),
                                            ),
                                            _captureTimeLabel(path),
                                          ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_marqueeStart != null &&
                                  _marqueeCurrent != null &&
                                  _marqueeDragging)
                                Positioned.fromRect(
                                  rect: Rect.fromPoints(
                                    _marqueeStart!,
                                    _marqueeCurrent!,
                                  ),
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: tokens.accent
                                            .withValues(alpha: 0.12),
                                        border: Border.all(
                                          color: tokens.accent,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            _ThumbnailScopeFooter(
              tokens: tokens,
              scope: _scope,
              visibleCount: paths.length,
              totalCount: allPaths.length,
              captionedCount: captionedCount,
              sentCount: sentCount,
              onScopeChanged: _setScope,
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _captureTimeLabel(String path) {
    final value = _captureTime(path);
    if (value.isEmpty) return const SizedBox.shrink();
    return Text(
      value,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: 10.5,
        fontWeight: FfTokens.weightRegular,
        letterSpacing: 0,
        color: tokens.textTertiary,
        height: 1.2,
      ),
    );
  }
}

String _shortThumbName(String name) {
  if (name.length <= 18) return name;
  return '…${name.substring(name.length - 16)}';
}

class _ThumbnailToolbar extends StatelessWidget {
  const _ThumbnailToolbar({
    required this.tokens,
    required this.sort,
    required this.columnCount,
    required this.maxColumns,
    required this.refreshing,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onOpenOverview,
    required this.onSmaller,
    required this.onLarger,
  });

  final FfTokens tokens;
  final _BrowseSort sort;
  final int columnCount;
  final int maxColumns;
  final bool refreshing;
  final ValueChanged<_BrowseSort> onSortChanged;
  final VoidCallback onRefresh;
  final VoidCallback onOpenOverview;
  final VoidCallback? onSmaller;
  final VoidCallback? onLarger;

  @override
  Widget build(BuildContext context) {
    final sizeProgress = (maxColumns - columnCount) / (maxColumns - 2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: FfTokens.photoHeader,
        border: Border(
          bottom: BorderSide(color: tokens.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            'SORT',
            softWrap: false,
            style: FfTokens.panelLabel(color: tokens.textSecondary),
          ),
          const SizedBox(width: 4),
          _ThumbnailSortDropdown(
            tokens: tokens,
            sort: sort,
            onChanged: onSortChanged,
          ),
          const SizedBox(width: 4),
          _ThumbnailRefreshButton(
            tokens: tokens,
            refreshing: refreshing,
            onTap: onRefresh,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Center(
              child: _ThumbnailOverviewButton(
                tokens: tokens,
                onTap: onOpenOverview,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _ThumbnailZoomStepper(
            tokens: tokens,
            sizeProgress: sizeProgress,
            onSmaller: onSmaller,
            onLarger: onLarger,
          ),
        ],
      ),
    );
  }
}

class _ThumbnailSortDropdown extends StatelessWidget {
  const _ThumbnailSortDropdown({
    required this.tokens,
    required this.sort,
    required this.onChanged,
  });

  final FfTokens tokens;
  final _BrowseSort sort;
  final ValueChanged<_BrowseSort> onChanged;

  String _label(_BrowseSort value) {
    switch (value) {
      case _BrowseSort.captureAscending:
        return 'Earliest first';
      case _BrowseSort.captureDescending:
        return 'Latest first';
      case _BrowseSort.filenameAscending:
        return 'Name A–Z';
      case _BrowseSort.filenameDescending:
        return 'Name Z–A';
    }
  }

  String _menuLabel(_BrowseSort value) {
    switch (value) {
      case _BrowseSort.captureAscending:
        return 'Earliest first';
      case _BrowseSort.captureDescending:
        return 'Latest first';
      case _BrowseSort.filenameAscending:
        return 'Filename · A–Z';
      case _BrowseSort.filenameDescending:
        return 'Filename · Z–A';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BrowseSort>(
      tooltip: 'Sort thumbnails',
      color: tokens.surface,
      surfaceTintColor: tokens.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: tokens.divider),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final value in _BrowseSort.values)
          PopupMenuItem<_BrowseSort>(
            value: value,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              width: 180,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: value == sort
                    ? tokens.accent.withValues(alpha: 0.16)
                    : tokens.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 17,
                    child: value == sort
                        ? PhosphorIcon(PhosphorIconsRegular.check,
                            size: 14,
                            color: tokens.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      _menuLabel(value),
                      softWrap: false,
                      style: TextStyle(
                        color: value == sort ? tokens.accent : tokens.text,
                        fontSize: 10,
                        fontWeight:
                            value == sort ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        width: 104,
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: tokens.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _label(sort),
                softWrap: false,
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ),
            PhosphorIcon(PhosphorIconsRegular.caretDown,
              size: 14,
              color: tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailScopeDropdown extends StatefulWidget {
  const _ThumbnailScopeDropdown({
    required this.tokens,
    required this.scope,
    required this.totalCount,
    required this.captionedCount,
    required this.sentCount,
    required this.onChanged,
  });

  final FfTokens tokens;
  final _BrowseScope scope;
  final int totalCount;
  final int captionedCount;
  final int sentCount;
  final ValueChanged<_BrowseScope> onChanged;

  @override
  State<_ThumbnailScopeDropdown> createState() =>
      _ThumbnailScopeDropdownState();
}

class _ThumbnailScopeDropdownState extends State<_ThumbnailScopeDropdown> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Thumbnail scope');
  bool _focused = false;

  String _label(_BrowseScope scope) {
    switch (scope) {
      case _BrowseScope.all:
        return 'All';
      case _BrowseScope.toCaption:
        return 'Needs caption';
      case _BrowseScope.captioned:
        return 'Captioned';
      case _BrowseScope.toFtp:
        return 'Needs FTP';
      case _BrowseScope.ftp:
        return "FTP'd";
    }
  }

  int _count(_BrowseScope scope) {
    switch (scope) {
      case _BrowseScope.all:
        return widget.totalCount;
      case _BrowseScope.toCaption:
        return widget.totalCount - widget.captionedCount;
      case _BrowseScope.captioned:
        return widget.captionedCount;
      case _BrowseScope.toFtp:
        return widget.totalCount - widget.sentCount;
      case _BrowseScope.ftp:
        return widget.sentCount;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    const scopes = _BrowseScope.values;
    final current = scopes.indexOf(widget.scope);
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onChanged(scopes[(current - 1 + scopes.length) % scopes.length]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onChanged(scopes[(current + 1) % scopes.length]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: PopupMenuButton<_BrowseScope>(
        tooltip: 'Choose thumbnail scope',
        color: tokens.surface,
        surfaceTintColor: tokens.surface,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: tokens.divider),
        ),
        onOpened: _focusNode.requestFocus,
        onSelected: widget.onChanged,
        itemBuilder: (context) => [
          for (final scope in _BrowseScope.values)
            PopupMenuItem<_BrowseScope>(
              value: scope,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 140,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: scope == widget.scope
                      ? tokens.accent.withValues(alpha: 0.16)
                      : tokens.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 17,
                      child: scope == widget.scope
                          ? PhosphorIcon(PhosphorIconsRegular.check,
                              size: 14,
                              color: tokens.accent,
                            )
                          : null,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        _label(scope),
                        softWrap: false,
                        style: TextStyle(
                          color: scope == widget.scope
                              ? tokens.accent
                              : tokens.text,
                          fontSize: 10.5,
                          fontWeight: scope == widget.scope
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${_count(scope)}',
                      style: TextStyle(
                        color: (scope == widget.scope
                                ? tokens.accent
                                : tokens.text)
                            .withValues(alpha: 0.65),
                        fontSize: 9.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        child: Container(
          width: 108,
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _focused ? tokens.accent : tokens.divider,
              width: _focused ? FfTokens.focusOutlineWidth : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _label(widget.scope),
                  softWrap: false,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              PhosphorIcon(PhosphorIconsRegular.caretDown,
                size: 14,
                color: tokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailScopeControl extends StatefulWidget {
  const _ThumbnailScopeControl({
    required this.tokens,
    required this.scope,
    required this.totalCount,
    required this.captionedCount,
    required this.sentCount,
    required this.onChanged,
  });

  final FfTokens tokens;
  final _BrowseScope scope;
  final int totalCount;
  final int captionedCount;
  final int sentCount;
  final ValueChanged<_BrowseScope> onChanged;

  @override
  State<_ThumbnailScopeControl> createState() => _ThumbnailScopeControlState();
}

class _ThumbnailScopeControlState extends State<_ThumbnailScopeControl> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Thumbnail scope');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    const scopes = _BrowseScope.values;
    final current = scopes.indexOf(widget.scope);
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onChanged(scopes[(current - 1 + scopes.length) % scopes.length]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onChanged(scopes[(current + 1) % scopes.length]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color:
                _focused ? tokens.accent : tokens.accent.withValues(alpha: 0),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: tokens.bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ThumbnailScopeOption(
                  label: 'All',
                  count: '${widget.totalCount}',
                  selected: widget.scope == _BrowseScope.all,
                  tokens: tokens,
                  onTap: () {
                    _focusNode.requestFocus();
                    widget.onChanged(_BrowseScope.all);
                  },
                ),
                const SizedBox(width: 2),
                _ThumbnailScopeOption(
                  label: 'Captioned',
                  count: '${widget.captionedCount}/${widget.totalCount}',
                  selected: widget.scope == _BrowseScope.captioned,
                  tokens: tokens,
                  onTap: () {
                    _focusNode.requestFocus();
                    widget.onChanged(_BrowseScope.captioned);
                  },
                ),
                const SizedBox(width: 2),
                _ThumbnailScopeOption(
                  label: "FTP'd",
                  count: '${widget.sentCount}/${widget.totalCount}',
                  selected: widget.scope == _BrowseScope.ftp,
                  tokens: tokens,
                  onTap: () {
                    _focusNode.requestFocus();
                    widget.onChanged(_BrowseScope.ftp);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailScopeOption extends StatefulWidget {
  const _ThumbnailScopeOption({
    required this.label,
    required this.count,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final String count;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_ThumbnailScopeOption> createState() => _ThumbnailScopeOptionState();
}

class _ThumbnailScopeOptionState extends State<_ThumbnailScopeOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.16)
                : tokens.text.withValues(alpha: _hovered ? 0.06 : 0),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color:
                  selected ? tokens.accent : tokens.accent.withValues(alpha: 0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                softWrap: false,
                style: TextStyle(
                  color: selected ? tokens.accent : tokens.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                widget.count,
                softWrap: false,
                style: TextStyle(
                  color: (selected ? tokens.accent : tokens.text).withValues(
                    alpha: selected ? 0.75 : 0.5,
                  ),
                  fontSize: 9.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailRefreshButton extends StatelessWidget {
  const _ThumbnailRefreshButton({
    required this.tokens,
    required this.refreshing,
    required this.onTap,
  });

  final FfTokens tokens;
  final bool refreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh photos from folder',
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: refreshing ? null : onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: tokens.divider),
            ),
            child: refreshing
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : PhosphorIcon(PhosphorIconsRegular.arrowClockwise,
                    size: 15,
                    color: tokens.accent,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailOverviewButton extends StatelessWidget {
  const _ThumbnailOverviewButton({
    required this.tokens,
    required this.onTap,
  });

  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: tokens.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.magnifyingGlass,
                size: FfIcons.toolbarSize,
              ),
              const SizedBox(width: 5),
              Text(
                'Open larger thumbnails',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailZoomStepper extends StatelessWidget {
  const _ThumbnailZoomStepper({
    required this.tokens,
    required this.sizeProgress,
    required this.onSmaller,
    required this.onLarger,
  });

  final FfTokens tokens;
  final double sizeProgress;
  final VoidCallback? onSmaller;
  final VoidCallback? onLarger;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThumbnailSizeButton(
          icon: PhosphorIconsRegular.minus,
          tooltip: 'Smaller thumbnails',
          tokens: tokens,
          onTap: onSmaller,
        ),
        SizedBox(
          width: 40,
          child: Tooltip(
            message: 'Thumbnail size',
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 3,
                  color: tokens.text.withValues(alpha: 0.14),
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    widthFactor: sizeProgress,
                    heightFactor: 1,
                    child: ColoredBox(color: tokens.accent),
                  ),
                ),
              ),
            ),
          ),
        ),
        _ThumbnailSizeButton(
          icon: PhosphorIconsRegular.plus,
          tooltip: 'Larger thumbnails',
          tokens: tokens,
          onTap: onLarger,
        ),
      ],
    );
  }
}

class _ThumbnailScopeFooter extends StatelessWidget {
  const _ThumbnailScopeFooter({
    required this.tokens,
    required this.scope,
    required this.visibleCount,
    required this.totalCount,
    required this.captionedCount,
    required this.sentCount,
    required this.onScopeChanged,
  });

  final FfTokens tokens;
  final _BrowseScope scope;
  final int visibleCount;
  final int totalCount;
  final int captionedCount;
  final int sentCount;
  final ValueChanged<_BrowseScope> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final hidden = totalCount - visibleCount;
    late final String text;
    switch (scope) {
      case _BrowseScope.all:
        text = 'Showing all $totalCount';
        break;
      case _BrowseScope.toCaption:
        text = 'Showing $visibleCount needing captions · $hidden hidden';
        break;
      case _BrowseScope.captioned:
        text = 'Showing $visibleCount captioned · $hidden hidden';
        break;
      case _BrowseScope.toFtp:
        text = 'Showing $visibleCount needing FTP · $hidden hidden';
        break;
      case _BrowseScope.ftp:
        text = "Showing $visibleCount FTP'd · $hidden hidden";
        break;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: FfTokens.photoHeader,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Text(
            'FILTER',
            softWrap: false,
            style: FfTokens.panelLabel(color: tokens.textSecondary),
          ),
          const SizedBox(width: 4),
          _ThumbnailScopeDropdown(
            tokens: tokens,
            scope: scope,
            totalCount: totalCount,
            captionedCount: captionedCount,
            sentCount: sentCount,
            onChanged: onScopeChanged,
          ),
          const Spacer(),
          Text(
            text,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailSizeButton extends StatelessWidget {
  const _ThumbnailSizeButton({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: PhosphorIcon(icon, size: 13, color: tokens.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _PhotoFrameCounter extends StatelessWidget {
  const _PhotoFrameCounter({
    super.key,
    required this.index,
    required this.total,
    required this.tokens,
  });

  final int index;
  final int total;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FfTokens.viewerChrome,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.divider),
        ),
        child: Text(
          '$index / $total',
          softWrap: false,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: tokens.textSizeMicro,
            fontWeight: FfTokens.weightMedium,
            color: tokens.text,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Compact header thumbnail used on mobile to open full-screen review.
class MobileFrameThumb extends StatelessWidget {
  const MobileFrameThumb({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final CaptionV2Controller controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final path = controller.currentPath;
    return GestureDetector(
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: path == null
                ? PhosphorIcon(PhosphorIconsRegular.image, color: t.textSecondary, size: 20)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      OrientedFilePreview(
                        path: path,
                        version: controller.imageContentStamp(path),
                        fit: BoxFit.cover,
                        cacheWidth: 88,
                      ),
                      if (controller.transmitting &&
                          controller.transmittingPath == path)
                        TransmitProgressOverlay(
                          progress: controller.transmitProgress,
                          status: controller.transmitStatus,
                          compact: true,
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.currentFileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.monoMetaStyle.copyWith(color: t.text),
                ),
                Text(
                  path == null
                      ? 'Tap to open folder'
                      : '${_mobileFrameStateLabel(controller.currentFrameState)} · ${controller.currentIndex + 1}/${controller.imagePaths.length}',
                  style: t.metaStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Large top photo for the mobile stack (tap opens full-screen review).
class MobileFrameBanner extends StatelessWidget {
  const MobileFrameBanner({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final CaptionV2Controller controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
        final paths = controller.imagePaths;
        final path = paths.isEmpty
            ? null
            : paths[controller.currentIndex.clamp(0, paths.length - 1)];
        return GestureDetector(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.sunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.divider),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: path == null
                        ? Center(
                            child: PhosphorIcon(PhosphorIconsRegular.image,
                              color: t.textSecondary,
                              size: 36,
                            ),
                          )
                        : OrientedFilePreview(
                            key: ValueKey(
                              'mobile-banner-$path-${controller.imageContentStamp(path)}',
                            ),
                            path: path,
                            version: controller.imageContentStamp(path),
                            fit: BoxFit.cover,
                            cacheWidth: 780,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                path == null
                    ? (controller.sessionReady
                        ? 'No images in folder'
                        : 'Tap to open folder')
                    : '${controller.currentFileName} · ${_mobileFrameStateLabel(controller.currentFrameState)} · ${controller.currentIndex + 1}/${paths.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.metaStyle,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _mobileFrameStateLabel(FrameState s) {
  switch (s) {
    case FrameState.todo:
      return 'To do';
    case FrameState.saved:
      return 'Saved · not sent';
    case FrameState.sent:
      return 'Sent';
  }
}
