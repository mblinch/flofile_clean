import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/preferences_service.dart';
import 'app_styled_dialogs.dart';
import 'oriented_file_preview.dart';

/// User choice after a burst (rapid sequence) is detected on save.
enum BurstCaptionSaveChoice {
  applyToAll,
  thisImageOnly,
  cancel,
}

/// Result of [showBurstCaptionConfirmDialog] (null if dismissed via barrier).
class BurstCaptionDialogResult {
  final BurstCaptionSaveChoice choice;
  /// When [choice] is [BurstCaptionSaveChoice.applyToAll]: paths to write (excludes tapped-out photos).
  final List<String> pathsToApply;

  const BurstCaptionDialogResult({
    required this.choice,
    this.pathsToApply = const [],
  });
}

/// Matches main caption [TextField] styling in [CaptionFieldsWidget] (12px, grey border, white fill).
const TextStyle _kCaptionPreviewStyle = TextStyle(
  fontSize: 12,
  color: Colors.black87,
  height: 1.35,
);

const TextStyle _kLabelStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: Colors.black87,
);

/// Same as Keyboard Fire FTP (`keyboard_fire_dialog.dart` `_ftpButtonBlue`).
const Color _kKeyboardFireFtpBlue = Color(0xFF0052CC);

/// Fewer columns → larger thumbnails; roughly square grid (ceil √n), max 4 columns.
int _burstGridColumnCount(int n) {
  if (n <= 1) return 1;
  return math.min(4, math.max(1, math.sqrt(n).ceil()));
}

class _BurstGridLayout {
  final int cols;
  final double aspectRatio;
  const _BurstGridLayout({required this.cols, required this.aspectRatio});
}

/// Column count and [childAspectRatio] (width / height) so the grid fits [maxGridHeight]
/// without scrolling. Increases column count when needed to reduce row count.
_BurstGridLayout _burstGridFitToHeight({
  required int n,
  required double gridWidth,
  required double maxGridHeight,
  double spacing = 6.0,
}) {
  if (n <= 0 || gridWidth <= 0 || maxGridHeight <= 8) {
    return const _BurstGridLayout(cols: 1, aspectRatio: 3 / 2);
  }
  const maxAspect = 8.0;
  const minAspect = 0.55;

  var cols = math.max(1, _burstGridColumnCount(n));
  while (cols <= n) {
    final rows = (n + cols - 1) ~/ cols;
    final cellW = (gridWidth - (cols - 1) * spacing) / cols;
    if (cellW < 12) {
      cols++;
      continue;
    }
    final denom = maxGridHeight - (rows - 1) * spacing;
    if (denom <= 0) {
      cols++;
      continue;
    }
    var ar = rows * cellW / denom;
    if (ar > maxAspect) {
      cols++;
      continue;
    }
    ar = ar.clamp(minAspect, maxAspect);
    final cellH = cellW / ar;
    final totalH = rows * cellH + (rows - 1) * spacing;
    if (totalH <= maxGridHeight + 1.0) {
      return _BurstGridLayout(cols: cols, aspectRatio: ar);
    }
    cols++;
  }

  // Single row: spread n thumbnails horizontally with a flat aspect ratio.
  final colsFinal = math.max(1, n);
  final cellW = (gridWidth - (colsFinal - 1) * spacing) / colsFinal;
  final arFallback =
      (cellW / maxGridHeight).clamp(minAspect, maxAspect).toDouble();
  return _BurstGridLayout(cols: colsFinal, aspectRatio: arFallback);
}

Future<BurstCaptionDialogResult?> showBurstCaptionConfirmDialog({
  required BuildContext context,
  required List<String> imagePathsInOrder,
  required String captionPreview,
  /// Called after the user confirms turning burst detection off (prefs already saved).
  VoidCallback? onBurstDetectionDisabled,
}) {
  return showDialog<BurstCaptionDialogResult>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      return _BurstCaptionConfirmDialogBody(
        imagePathsInOrder: imagePathsInOrder,
        captionPreview: captionPreview,
        onBurstDetectionDisabled: onBurstDetectionDisabled,
      );
    },
  );
}

class _BurstCaptionConfirmDialogBody extends StatefulWidget {
  final List<String> imagePathsInOrder;
  final String captionPreview;
  final VoidCallback? onBurstDetectionDisabled;

  const _BurstCaptionConfirmDialogBody({
    required this.imagePathsInOrder,
    required this.captionPreview,
    this.onBurstDetectionDisabled,
  });

  @override
  State<_BurstCaptionConfirmDialogBody> createState() =>
      _BurstCaptionConfirmDialogBodyState();
}

class _BurstCaptionConfirmDialogBodyState
    extends State<_BurstCaptionConfirmDialogBody> {
  final FocusNode _focusNode = FocusNode();

  /// Normalized paths the user chose to skip (see [_normKey]).
  final Set<String> _excludedNormalized = {};

  /// Stable path identity so taps match [imagePathsInOrder] even with `./` or symlink quirks.
  String _normKey(String path) => p.normalize(path);

  /// Original path strings to pass to exiftool (only rows not excluded).
  List<String> get _pathsToApply {
    final out = <String>[];
    for (final path in widget.imagePathsInOrder) {
      if (!_excludedNormalized.contains(_normKey(path))) {
        out.add(path);
      }
    }
    return out;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _applyToAll() {
    final count = _pathsToApply.length;
    if (count == 0) return;
    Navigator.pop(
      context,
      BurstCaptionDialogResult(
        choice: BurstCaptionSaveChoice.applyToAll,
        pathsToApply: _pathsToApply,
      ),
    );
  }

  void _toggleExclude(String path) {
    setState(() {
      final k = _normKey(path);
      if (_excludedNormalized.contains(k)) {
        _excludedNormalized.remove(k);
      } else {
        _excludedNormalized.add(k);
      }
    });
  }

  Future<void> _confirmTurnOffBurstDetection(BuildContext outerContext) async {
    final confirmed = await showAppConfirmDialog(
      context: outerContext,
      title: 'Are you sure?',
      message:
          'Burst sequence detection looks at photos taken after the one you\'re '
          'captioning (each following shot within 1 second of the previous) and '
          'can offer to apply the same caption to those frames. Turning it off '
          'stops that prompt until you enable it again.\n\n'
          'You can turn it back on in Preferences.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Turn off',
    );
    if (confirmed != true || !mounted) return;
    final prefs = await PreferencesService.getInstance();
    await prefs.saveBurstDetectionEnabled(false);
    if (!mounted) return;
    widget.onBurstDetectionDisabled?.call();
    if (!mounted) return;
    if (!outerContext.mounted) return;
    Navigator.of(outerContext).pop(
      const BurstCaptionDialogResult(
        choice: BurstCaptionSaveChoice.cancel,
      ),
    );
  }

  void _showLargePreview(BuildContext context, String path, String filename) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        final previewMaxW = MediaQuery.sizeOf(ctx).width * 0.85;
        final previewMaxH = MediaQuery.sizeOf(ctx).height * 0.8;
        final previewCacheW = (math.max(previewMaxW, previewMaxH) *
                MediaQuery.devicePixelRatioOf(ctx))
            .round()
            .clamp(512, 8192);
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          filename,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: previewMaxW,
                    maxHeight: previewMaxH,
                  ),
                  child: OrientedFilePreview(
                    path: path,
                    fit: BoxFit.contain,
                    cacheWidth: previewCacheW,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.imagePathsInOrder;
    final n = paths.length;
    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = math.min(880.0, screenW * 0.92);
    final applyCount = _pathsToApply.length;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _applyToAll();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      contentPadding: EdgeInsets.zero,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      backgroundColor: Colors.white,
      title: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Colors.black87,
          ),
          children: [
            const TextSpan(
              text: 'Burst sequence: ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text:
                  '$n photos taken within 1 second of each other. Apply the same caption to all?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: dialogW,
        height: math.min(
          620,
          MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Caption to apply', style: _kLabelStyle),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 1.0),
                  borderRadius: BorderRadius.zero,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: SelectableText(
                      widget.captionPreview.trim().isEmpty
                          ? '(empty caption)'
                          : widget.captionPreview,
                      style: widget.captionPreview.trim().isEmpty
                          ? _kCaptionPreviewStyle.copyWith(
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            )
                          : _kCaptionPreviewStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gridW = constraints.maxWidth;
                    final maxGridH = constraints.maxHeight;
                    const spacing = 6.0;
                    final gridLayout = _burstGridFitToHeight(
                      n: n,
                      gridWidth: gridW,
                      maxGridHeight: maxGridH,
                      spacing: spacing,
                    );
                    final cols = gridLayout.cols;
                    final aspectRatio = gridLayout.aspectRatio;
                    final cellLogicalW =
                        (gridW - (cols - 1) * spacing) / cols;
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    final innerLogicalW =
                        (cellLogicalW - 8).clamp(40.0, 2000.0);
                    final cacheThumbW =
                        (innerLogicalW * dpr).round().clamp(128, 4096);
                    return SizedBox(
                      height: maxGridH,
                      width: gridW,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: n,
                        itemBuilder: (context, i) {
                      final path = paths[i];
                      final excluded =
                          _excludedNormalized.contains(_normKey(path));
                      final isAnchor = i == 0;
                      return Tooltip(
                        message: excluded
                            ? '${p.basename(path)} — tap to include'
                            : isAnchor
                                ? '${p.basename(path)} — selected photo'
                                : '${p.basename(path)} — tap to skip',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _toggleExclude(path),
                            behavior: HitTestBehavior.opaque,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: excluded
                                      ? Colors.grey.shade400
                                      : isAnchor
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade300,
                                  width: excluded ? 2 : isAnchor ? 2.5 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(color: Colors.grey.shade50),
                                    OrientedFilePreview(
                                      path: path,
                                      fit: BoxFit.contain,
                                      cacheWidth: cacheThumbW,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  if (excluded)
                                    Container(
                                      alignment: Alignment.center,
                                      color:
                                          Colors.black.withValues(alpha: 0.35),
                                      child: Text(
                                        'Skip',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withValues(
                                                  alpha: 0.8),
                                              blurRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (isAnchor && !excluded)
                                    Positioned(
                                      left: 4,
                                      top: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        color: Colors.blue.shade600,
                                        child: const Text(
                                          'Selected',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: GestureDetector(
                                      onTap: () => _showLargePreview(
                                        context,
                                        path,
                                        p.basename(path),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        child: Icon(
                                          Icons.search,
                                          size: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      color: Colors.white
                                          .withValues(alpha: 0.9),
                                      child: Icon(
                                        excluded
                                            ? Icons.close
                                            : Icons.check,
                                        size: 14,
                                        color: excluded
                                            ? Colors.grey.shade700
                                            : Colors.green.shade700,
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
                    },
                  ),
                    );
                },
              ),
            ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            InkWell(
              onTap: () => _confirmTurnOffBurstDetection(context),
              borderRadius: BorderRadius.circular(2),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Text(
                  'Turn off Burst Detection',
                  style: TextStyle(
                    fontSize: 10,
                    color: _kKeyboardFireFtpBlue,
                    decoration: TextDecoration.underline,
                    decorationColor: _kKeyboardFireFtpBlue,
                  ),
                ),
              ),
            ),
            const Spacer(),
            ElevatedGreyButton(
              label: 'Cancel',
              fontSize: 11,
              onPressed: () => Navigator.pop(
                context,
                const BurstCaptionDialogResult(
                  choice: BurstCaptionSaveChoice.cancel,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: 'First photo only',
              fontSize: 11,
              onPressed: () => Navigator.pop(
                context,
                const BurstCaptionDialogResult(
                  choice: BurstCaptionSaveChoice.thisImageOnly,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: applyCount == n
                  ? 'Apply to all $n'
                  : 'Apply to $applyCount photo${applyCount == 1 ? '' : 's'}',
              fontSize: 11,
              isPrimary: true,
              onPressed: applyCount == 0 ? null : _applyToAll,
            ),
          ],
        ),
      ],
    ),
    );
  }
}
