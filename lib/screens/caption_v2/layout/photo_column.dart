import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/frame_status_dot.dart';
import 'caption_v2_photo_actions.dart';
import 'caption_v2_thumbnail_overview.dart';

enum _BrowseScope { all, toCaption, captioned, toFtp, ftp }

enum _BrowseSort {
  captureAscending,
  captureDescending,
  filenameAscending,
  filenameDescending
}

/// Desktop photo preview + regular thumbnail grid (V1-style, no burst cards).
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

class _PhotoColumnState extends State<PhotoColumn> {
  static const double _handleHeight = 14;
  double _previewFraction = 0.6;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final path = widget.controller.currentPath;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
            (constraints.maxHeight - _handleHeight).clamp(0.0, double.infinity);
        final previewHeight =
            availableHeight * _previewFraction.clamp(0.6, 0.8);
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
                onSavePrevious: widget.onSavePrevious,
                onSaveNext: widget.onSaveNext,
              ),
            ),
            _PhotoThumbnailResizeHandle(
              tokens: t,
              onDrag: (delta) {
                if (availableHeight <= 0) return;
                setState(() {
                  _previewFraction =
                      (_previewFraction + delta / availableHeight)
                          .clamp(0.6, 0.8);
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

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.controller,
    required this.path,
    required this.tokens,
    required this.onSavePrevious,
    required this.onSaveNext,
  });

  final CaptionV2Controller controller;
  final String? path;
  final FfTokens tokens;
  final VoidCallback onSavePrevious;
  final VoidCallback onSaveNext;

  String _meta(List<String> keys) {
    for (final key in keys) {
      final value = controller.currentIptcMeta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
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
    final state =
        path == null ? FrameState.todo : controller.frameStateFor(path!);
    final savedLabel = state == FrameState.todo
        ? null
        : (state == FrameState.sent ? 'Sent' : 'Saved');
    final width = _meta(const ['ImageWidth', 'ExifImageWidth']);
    final height = _meta(const ['ImageHeight', 'ExifImageHeight']);
    final fileSize = path == null ? '' : _formatFileSize(path!);
    final technicalInfo = [
      if (path != null) p.basename(path!),
      if (width.isNotEmpty && height.isNotEmpty) '$width×$height',
      if (fileSize.isNotEmpty) fileSize,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(color: tokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: tokens.sunken,
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
                      : GestureDetector(
                          onSecondaryTapDown: (details) =>
                              showCaptionV2PhotoMenu(
                            context: context,
                            controller: controller,
                            imagePath: path!,
                            position: details.globalPosition,
                          ),
                          onDoubleTap: () => showCaptionV2Zoom(context, path!),
                          child: OrientedFilePreview(
                            path: path!,
                            fit: BoxFit.contain,
                            cacheWidth: 1600,
                          ),
                        ),
                ),
                if (savedLabel != null)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _StatusPill(
                      label: savedLabel,
                      tokens: tokens,
                      accent: false,
                    ),
                  ),
                if (path != null)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _StatusPill(
                      label: state == FrameState.sent ? 'Sent' : 'Not sent',
                      tokens: tokens,
                      accent: state == FrameState.sent,
                    ),
                  ),
                if (path != null) ...[
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Tooltip(
                      message: 'Zoom image',
                      child: Material(
                        color: tokens.surface.withValues(alpha: 0.88),
                        shape: CircleBorder(
                          side: BorderSide(color: tokens.divider),
                        ),
                        child: IconButton(
                          onPressed: () => showCaptionV2Zoom(context, path!),
                          icon: const Icon(Icons.zoom_in_rounded),
                          color: tokens.text,
                          iconSize: 20,
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 38,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
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
              ],
            ),
          ),
          if (technicalInfo.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.divider)),
              ),
              child: Text(
                technicalInfo,
                textAlign: TextAlign.center,
                style: tokens.microStyle.copyWith(fontSize: 10),
              ),
            ),
        ],
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
      message: previous ? 'Save & previous' : 'Save & next',
      child: Material(
        color: t.surface.withValues(alpha: 0.82),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: CircleBorder(side: BorderSide(color: t.divider)),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(
              previous
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.arrow_forward_ios_rounded,
              size: 22,
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

  CaptionV2Controller get controller => widget.controller;
  FfTokens get tokens => widget.tokens;
  Set<String> get _selectedPaths => controller.selectedImagePaths;

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
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

  int _thumbCacheWidth(int columns) {
    switch (columns) {
      case 2:
        return 480;
      case 3:
        return 320;
      case 4:
        return 240;
      case 5:
        return 192;
      case 6:
        return 160;
      case 7:
        return 144;
      default:
        return 128;
    }
  }

  String _captureTime(String path) {
    final value = controller.captureByPath[path];
    if (value == null) return '';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
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
          border: Border.all(color: tokens.divider),
        ),
        child: Text('No images', style: tokens.metaStyle),
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
            color: widget.focused ? tokens.accent : tokens.divider,
            width: widget.focused ? FfTokens.focusOutlineWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _ThumbnailToolbar(
              tokens: tokens,
              sort: _sort,
              columnCount: columnCount,
              maxColumns: maxColumns,
              onSortChanged: _setSort,
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
                      child: Text(
                        'No images match current filters',
                        style: tokens.metaStyle,
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
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? tokens.selectedFill
                                              : tokens.surface,
                                          borderRadius: BorderRadius.circular(
                                            FfTokens.radiusTile,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? tokens.accent
                                                : tokens.divider,
                                            width: selected
                                                ? FfTokens.focusOutlineWidth
                                                : 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: tokens.text
                                                  .withValues(alpha: 0.08),
                                              blurRadius: 5,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
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
                                                      fit: BoxFit.contain,
                                                      cacheWidth:
                                                          _thumbCacheWidth(
                                                              columns),
                                                    ),
                                                    if (captioned || ftp)
                                                      Positioned(
                                                        top: 4,
                                                        right: 4,
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            if (captioned)
                                                              _ThumbnailStatusIcon(
                                                                icon: Icons
                                                                    .save_rounded,
                                                                tooltip:
                                                                    'Captioned',
                                                                tokens: tokens,
                                                              ),
                                                            if (captioned &&
                                                                ftp)
                                                              const SizedBox(
                                                                  width: 3),
                                                            if (ftp)
                                                              _ThumbnailStatusIcon(
                                                                icon: Icons
                                                                    .cloud_upload_rounded,
                                                                tooltip:
                                                                    "FTP'd",
                                                                tokens: tokens,
                                                                emphasized:
                                                                    true,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.center,
                                              child: Text(
                                                p.basename(path),
                                                maxLines: 1,
                                                textAlign: TextAlign.center,
                                                style: tokens.monoMetaStyle
                                                    .copyWith(
                                                  color: tokens.text,
                                                  fontSize: 9,
                                                ),
                                              ),
                                            ),
                                            _captureTimeLabel(path),
                                          ],
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
    );
  }

  Widget _captureTimeLabel(String path) {
    final value = _captureTime(path);
    if (value.isEmpty) return const SizedBox.shrink();
    return Text(
      value,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: tokens.microStyle.copyWith(fontSize: 8.5),
    );
  }
}

class _ThumbnailStatusIcon extends StatelessWidget {
  const _ThumbnailStatusIcon({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    this.emphasized = false,
  });

  final IconData icon;
  final String tooltip;
  final FfTokens tokens;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surface.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: emphasized ? tokens.accent : tokens.divider,
          ),
        ),
        child: Icon(
          icon,
          size: 13,
          color: emphasized ? tokens.accent : tokens.textSecondary,
        ),
      ),
    );
  }
}

class _ThumbnailToolbar extends StatelessWidget {
  const _ThumbnailToolbar({
    required this.tokens,
    required this.sort,
    required this.columnCount,
    required this.maxColumns,
    required this.onSortChanged,
    required this.onOpenOverview,
    required this.onSmaller,
    required this.onLarger,
  });

  final FfTokens tokens;
  final _BrowseSort sort;
  final int columnCount;
  final int maxColumns;
  final ValueChanged<_BrowseSort> onSortChanged;
  final VoidCallback onOpenOverview;
  final VoidCallback? onSmaller;
  final VoidCallback? onLarger;

  @override
  Widget build(BuildContext context) {
    final sizeProgress = (maxColumns - columnCount) / (maxColumns - 2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.badgeFill,
        border: Border(
          bottom: BorderSide(color: tokens.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Sort By:',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 6),
          _ThumbnailSortDropdown(
            tokens: tokens,
            sort: sort,
            onChanged: onSortChanged,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: _ThumbnailOverviewButton(
                tokens: tokens,
                onTap: onOpenOverview,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
                        ? Icon(
                            Icons.check_rounded,
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
        width: 110,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(7),
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
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 15,
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
                          ? Icon(
                              Icons.check_rounded,
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
          width: 118,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.bg,
            borderRadius: BorderRadius.circular(7),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
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

class _ThumbnailOverviewButton extends StatelessWidget {
  const _ThumbnailOverviewButton({
    required this.tokens,
    required this.onTap,
  });

  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open large thumbnail view',
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 34,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tokens.divider),
            ),
            child: Icon(
              Icons.image_search_outlined,
              size: 20,
              color: tokens.accent,
            ),
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
          icon: Icons.remove,
          tooltip: 'Smaller thumbnails',
          tokens: tokens,
          onTap: onSmaller,
        ),
        SizedBox(
          width: 48,
          child: Tooltip(
            message: 'Thumbnail size',
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 5,
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
          icon: Icons.add,
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
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
      decoration: BoxDecoration(
        color: tokens.badgeFill,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Text(
            'Filter:',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 6),
          _ThumbnailScopeDropdown(
            tokens: tokens,
            scope: scope,
            totalCount: totalCount,
            captionedCount: captionedCount,
            sentCount: sentCount,
            onChanged: onScopeChanged,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.text.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
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
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: tokens.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.tokens,
    required this.accent,
  });

  final String label;
  final FfTokens tokens;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? tokens.selectedFill : tokens.badgeFill,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: accent ? tokens.selectedBorder : tokens.divider,
        ),
      ),
      child: Text(label, style: tokens.metaStyle.copyWith(color: tokens.text)),
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
              border: Border.all(color: t.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: path == null
                ? Icon(Icons.image_outlined, color: t.textSecondary, size: 20)
                : OrientedFilePreview(
                    path: path,
                    fit: BoxFit.cover,
                    cacheWidth: 88,
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
                      : '${_stateLabel(controller.currentFrameState)} · ${controller.currentIndex + 1}/${controller.imagePaths.length}',
                  style: t.metaStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(FrameState s) {
    switch (s) {
      case FrameState.todo:
        return 'To do';
      case FrameState.saved:
        return 'Saved · not sent';
      case FrameState.sent:
        return 'Sent';
    }
  }
}
