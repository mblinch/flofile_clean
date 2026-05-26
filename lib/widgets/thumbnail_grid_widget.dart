import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:extended_image/extended_image.dart';
import '../utils/exiftool_helper.dart';
import '../flo_layout_constants.dart';
import 'app_styled_dialogs.dart';
import 'caption_fields_widget.dart' show CustomButton;
import 'thumbnail_popup_dialog.dart';
import 'oriented_file_preview.dart';

class ThumbnailGridWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final ScrollController? scrollController;
  final double? loadingProgress; // Add loading progress parameter
  final Map<String, String>? exifTimes; // Optional precomputed EXIF times
  final Set<String> uploadedImages; // Track uploaded images
  final Set<String> savedImages; // Track saved images
  final Set<String> queuedUploads; // Track queued uploads
  final Set<String> currentlyUploading; // Track currently uploading images
  final Map<String, int>? xmpRatings; // Optional XMP ratings (0-5)
  final Map<String, String>?
      xmpLabels; // Optional XMP color labels (Red, Yellow, ...)
  final Map<String, bool>? xmpTagged; // Optional XMP tagged/keep flags
  final Set<String>? lockedPaths; // Files detected as locked (read-only)
  final Map<String, double> uploadProgress; // Track upload progress
  // Bump this number to request the grid to center the selected index
  final int centerRequestId;
  // Callback when an image is deleted
  final Function(String)? onImageDeleted;
  // Callbacks for metadata operations
  final Function(String)? onCopyMetadata;
  final Function(String)? onPasteMetadata;
  final Function(String)? onApplyIptcTemplate;
  // Callback for FTP operations
  final Function(String)? onFtpImage;
  // Callback when an image is renamed
  final Function(String, String)? onImageRenamed;
  // Callback for multi-selection operations
  final Function(List<String>)? onMultiSelect;
  // Callback for editing metadata
  final VoidCallback? onEditMetadata;
  // Callback for editing in Photoshop
  final Function(String)? onEditInPhotoshop;
  // Called when computed column count changes (for arrow Up/Down row navigation)
  final void Function(int columns)? onColumnsComputed;
  // Whether the thumbnail grid is expanded over the picture preview
  final bool isExpanded;
  // Callback to toggle expand/collapse
  final VoidCallback? onToggleExpand;

  const ThumbnailGridWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    this.scrollController,
    this.loadingProgress,
    this.exifTimes,
    required this.uploadedImages,
    required this.savedImages,
    required this.queuedUploads,
    required this.currentlyUploading,
    this.xmpRatings,
    this.xmpLabels,
    this.xmpTagged,
    this.lockedPaths,
    required this.uploadProgress,
    required this.centerRequestId,
    this.onImageDeleted,
    this.onCopyMetadata,
    this.onPasteMetadata,
    this.onApplyIptcTemplate,
    this.onFtpImage,
    this.onImageRenamed,
    this.onMultiSelect,
    this.onEditMetadata,
    this.onEditInPhotoshop,
    this.onColumnsComputed,
    this.isExpanded = false,
    this.onToggleExpand,
  });

  @override
  State<ThumbnailGridWidget> createState() => ThumbnailGridWidgetState();
}

class ThumbnailGridWidgetState extends State<ThumbnailGridWidget> {
  // Thumbnail size control
  double _thumbSize = 140.0; // Start at medium size (140px)
  double _thumbSpacing = 14.0;
  int _lastComputedColumns = 4;
  int _lastReportedColumns = 4;
  int _lastCenterRequestId = 0;
  bool _hideFtpdImages = false;
  bool _hideSavedImages = false;
  List<String> _visiblePaths = [];
  String _tagFilterMode = 'all'; // 'all', 'tagged', 'untagged'
  String? _selectedLabel; // null -> any

  // EXIF data cache (fallback when exifTimes not provided)
  final Map<String, String> _exifTimeCache = {};

  // Loading state for thumbnails
  bool _isLoadingThumbnails = false;
  int _loadedThumbnails = 0;
  List<String> _previousImagePaths = [];

  // Multi-selection state
  Set<String> _selectedImages = {};
  bool _isMultiSelectMode = false;

  /// Clear multi-selection (called from parent on arrow-key navigation, etc.)
  void clearMultiSelection() {
    if (_selectedImages.isEmpty) return;
    setState(() {
      _selectedImages.clear();
      _isMultiSelectMode = false;
    });
  }

  /// If the current image is hidden by active filters, move selection to a visible image.
  void _advanceSelectionIfCurrentHidden() {
    if (!(_hideFtpdImages || _hideSavedImages)) return;
    if (widget.currentIndex < 0 ||
        widget.currentIndex >= widget.imagePaths.length) {
      return;
    }
    final path = widget.imagePaths[widget.currentIndex];
    final hiddenByFtp =
        _hideFtpdImages && widget.uploadedImages.contains(path);
    final hiddenBySaved =
        _hideSavedImages && widget.savedImages.contains(path);
    if (!hiddenByFtp && !hiddenBySaved) return;

    int nextIndex = widget.currentIndex + 1;
    while (nextIndex < widget.imagePaths.length) {
      final p = widget.imagePaths[nextIndex];
      final hFtp = _hideFtpdImages && widget.uploadedImages.contains(p);
      final hSav = _hideSavedImages && widget.savedImages.contains(p);
      if (!hFtp && !hSav) break;
      nextIndex++;
    }
    if (nextIndex >= widget.imagePaths.length) {
      nextIndex = widget.currentIndex - 1;
      while (nextIndex >= 0) {
        final p = widget.imagePaths[nextIndex];
        final hFtp = _hideFtpdImages && widget.uploadedImages.contains(p);
        final hSav = _hideSavedImages && widget.savedImages.contains(p);
        if (!hFtp && !hSav) break;
        nextIndex--;
      }
    }
    if (nextIndex >= 0 && nextIndex < widget.imagePaths.length) {
      widget.onImageSelected(nextIndex);
    }
  }

  void _adjustThumbSizeStep(int delta) {
    setState(() {
      _thumbSize = (_thumbSize + delta * 20).clamp(80.0, 200.0);
      _thumbSpacing = _thumbSize * 0.1;
    });
    _ensureVisibleAfterLayout();
  }

  Widget _buildEyeFilterToggle({
    required String label,
    required bool hiding,
    required VoidCallback onTap,
  }) {
    final active = hiding;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3A3A3A) : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? const Color(0xFF3A3A3A) : const Color(0xFFE6E6E6),
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 12,
                color: active ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontVariations: const [FontVariation('wght', 500)],
                  color: active ? Colors.white : Colors.grey.shade700,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Toolbar row: same fill as the image preview filename/EXIF bars (`grey.shade50`).
  Widget _buildThumbnailToolbar() {
    final bar = Colors.grey.shade100;
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEyeFilterToggle(
                label: 'FTPd',
                hiding: _hideFtpdImages,
                onTap: () {
                  setState(() => _hideFtpdImages = !_hideFtpdImages);
                  _advanceSelectionIfCurrentHidden();
                  _ensureVisibleAfterLayout();
                },
              ),
              const SizedBox(width: 4),
              _buildEyeFilterToggle(
                label: 'Saved',
                hiding: _hideSavedImages,
                onTap: () {
                  setState(() => _hideSavedImages = !_hideSavedImages);
                  _advanceSelectionIfCurrentHidden();
                  _ensureVisibleAfterLayout();
                },
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onToggleExpand != null)
                Tooltip(
                  message: widget.isExpanded ? 'Collapse thumbnails' : 'Expand thumbnails',
                  waitDuration: const Duration(milliseconds: 400),
                  child: GestureDetector(
                    onTap: widget.onToggleExpand,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 26,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.isExpanded ? const Color(0xFF3A3A3A) : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: widget.isExpanded ? const Color(0xFF3A3A3A) : const Color(0xFFE6E6E6),
                            width: 0.7,
                          ),
                        ),
                        child: Icon(
                          widget.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                          size: 15,
                          color: widget.isExpanded ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'See larger thumbnails',
                waitDuration: const Duration(milliseconds: 400),
                child: GestureDetector(
                  onTap: () => _showThumbnailPopup(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 26,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
                      ),
                      child: Icon(
                        Icons.image_search,
                        size: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _adjustThumbSizeStep(-1),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
                    ),
                    child: Icon(Icons.remove, size: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${_thumbSize.toInt()}px',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontVariations: const [FontVariation('wght', 500)],
                    color: Colors.grey.shade700,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _adjustThumbSizeStep(1),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
                    ),
                    child: Icon(Icons.add, size: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleThumbnailTap(String imagePath) {
    // Check if Cmd/Meta key is pressed
    final isMetaPressed = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaLeft) ||
        RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.metaRight);

    // If Cmd is not pressed, clear selection and select single image
    if (!isMetaPressed) {
      final hadSelection = _selectedImages.isNotEmpty;
      setState(() {
        _selectedImages.clear();
        _isMultiSelectMode = false;
      });
      if (hadSelection) {
        widget.onMultiSelect?.call([]);
      }

      final originalIndex = widget.imagePaths.indexOf(imagePath);
      if (originalIndex != -1) {
        widget.onImageSelected(originalIndex);
      }
      return;
    }

    // Cmd is pressed - handle multi-selection

    // If we're starting multi-selection and there's a current image, add it first
    if (_selectedImages.isEmpty &&
        widget.currentIndex >= 0 &&
        widget.currentIndex < widget.imagePaths.length) {
      final currentImagePath = widget.imagePaths[widget.currentIndex];
      _selectedImages.add(currentImagePath);
    }

    if (_selectedImages.contains(imagePath)) {
      // Remove from selection
      _selectedImages.remove(imagePath);

      if (_selectedImages.isEmpty) {
        // All deselected — revert to single-image mode
        setState(() {
          _isMultiSelectMode = false;
        });
        widget.onMultiSelect?.call([]);
        final originalIndex = widget.imagePaths.indexOf(imagePath);
        if (originalIndex != -1) {
          widget.onImageSelected(originalIndex);
        }
        return;
      }
    } else {
      // Add to selection
      _selectedImages.add(imagePath);
    }

    // Update local UI and notify parent of the full selection
    setState(() {
      _isMultiSelectMode = true;
    });
    widget.onMultiSelect?.call(_selectedImages.toList());
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dt = DateTime.parse(
          dateTimeStr.replaceFirst(':', '-').replaceFirst(':', '-'));
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute:$second $ampm';
    } catch (e) {
      return '';
    }
  }

  List<String> _getVisiblePaths() {
    // Start with image visibility filters
    Iterable<String> paths;
    paths = widget.imagePaths.where((p) {
      if (_hideFtpdImages && widget.uploadedImages.contains(p)) return false;
      if (_hideSavedImages && widget.savedImages.contains(p)) return false;
      return true;
    });

    // Apply tagged/untagged filter
    paths = paths.where((p) {
      final tagged = widget.xmpTagged ?? const {};
      final labels = widget.xmpLabels ?? const {};
      final isTagged = tagged[p] ?? false;

      bool passTagFilter = true;
      if (_tagFilterMode == 'tagged') passTagFilter = isTagged;
      if (_tagFilterMode == 'untagged') passTagFilter = !isTagged;

      bool passLabel = true;
      if (_selectedLabel != null && _selectedLabel!.isNotEmpty) {
        final lab = labels[p]?.toLowerCase().trim();
        passLabel = lab == _selectedLabel!.toLowerCase();
      }

      return passTagFilter && passLabel;
    });

    return paths.toList();
  }

  // Removed helper for FTP filter display (replaced by two-state toggles)

  Color? _labelToColor(String? label) {
    switch (label?.toLowerCase().trim()) {
      case 'magenta':
      case 'pink':
        return Colors.pinkAccent;
      case 'red':
        return Colors.red;
      case 'yellow':
        return Colors.yellow[700];
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'purple':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      case 'cyan':
        return Colors.cyan;
      case 'grey':
      case 'gray':
      case 'none':
        return Colors.grey;
      default:
        return null;
    }
  }

  void _onThumbnailLoaded() {
    _loadedThumbnails++;
    if (_loadedThumbnails >= widget.imagePaths.length) {
      setState(() {
        _isLoadingThumbnails = false;
      });
    }
  }

  void _ensureVisibleAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCenterSelection(context, force: true);
      // Run one more time shortly after to catch any late relayout
      Timer(const Duration(milliseconds: 40), () {
        if (!mounted) return;
        _maybeCenterSelection(context, force: true);
      });
    });
  }

  Future<String> _getImageTime(String imagePath) async {
    if (_exifTimeCache.containsKey(imagePath)) {
      return _exifTimeCache[imagePath]!;
    }

    try {
      final proc = await ExiftoolHelper.run([
        '-j',
        '-DateTimeOriginal',
        imagePath,
      ]);

      if (proc.isSuccess) {
        final List data = jsonDecode(proc.stdoutText);
        if (data.isNotEmpty) {
          final meta = data.first as Map<String, dynamic>;
          final dateTime = meta['DateTimeOriginal']?.toString();
          final formattedTime = _formatTime(dateTime);
          _exifTimeCache[imagePath] = formattedTime;
          return formattedTime;
        }
      }
    } catch (e) {
      print('Error loading EXIF time for $imagePath: $e');
    }

    _exifTimeCache[imagePath] = '';
    return '';
  }

  /// Returns the next image index when moving one row up (direction -1) or down (direction 1) in the visible grid. Keeps same column.
  int? getNextIndexVertical(int direction) {
    if (widget.imagePaths.isEmpty || _visiblePaths.isEmpty) return null;
    final currentIndex =
        widget.currentIndex.clamp(0, widget.imagePaths.length - 1);
    final currentPath = widget.imagePaths[currentIndex];
    final visibleIndex = _visiblePaths.indexOf(currentPath);
    if (visibleIndex < 0) return null;
    final cols = _lastComputedColumns > 0 ? _lastComputedColumns : 4;
    final nextVisible = visibleIndex + direction * cols;
    if (nextVisible < 0 || nextVisible >= _visiblePaths.length) return null;
    final nextPath = _visiblePaths[nextVisible];
    final nextIndex = widget.imagePaths.indexOf(nextPath);
    return nextIndex >= 0 ? nextIndex : null;
  }

  void _maybeCenterSelection(BuildContext context, {bool force = false}) {
    if (widget.scrollController == null) return;
    if (!force && widget.centerRequestId == _lastCenterRequestId) return;
    if (!force) _lastCenterRequestId = widget.centerRequestId;

    final controller = widget.scrollController!;
    if (!controller.hasClients) return;

    // Recalculate columns from the actual rendered width so math matches layout
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Account for GridView padding (8 on each side); same formula as LayoutBuilder
    const double gridPaddingHorizontal = 16.0; // 8 left + 8 right
    const double gridPaddingVertical = 16.0; // 8 top + 8 bottom
    final double crossAxisExtent = renderBox.size.width - gridPaddingHorizontal;
    final columnsCalc =
        ((crossAxisExtent + _thumbSpacing) / (_thumbSize + _thumbSpacing))
            .floor();
    final columns = columnsCalc > 0 ? columnsCalc : 4;

    // Compute actual row height using current layout parameters
    final totalSpacing = (columns - 1) * _thumbSpacing;
    final cellWidth = (crossAxisExtent - totalSpacing) / columns; // aspect 1.0
    final rowHeight = cellWidth; // childAspectRatio is 1.0
    final rowExtent = rowHeight + _thumbSpacing; // include spacing between rows

    // Compute visible index for current image (accounts for hidden uploaded images)
    if (widget.currentIndex < 0 ||
        widget.currentIndex >= widget.imagePaths.length) {
      return;
    }
    final String currentPath = widget.imagePaths[widget.currentIndex];
    final int visibleIndex = _visiblePaths.indexOf(currentPath);
    if (visibleIndex < 0) return; // current item hidden; skip centering

    // Current tile row extents in visible grid
    final rowIndex = (visibleIndex ~/ columns).toDouble();
    final rowTop = (rowIndex * rowExtent) + (gridPaddingVertical / 2);
    final rowBottom = rowTop + rowHeight;

    final viewportTop = controller.position.pixels;
    final viewportBottom = viewportTop + controller.position.viewportDimension;

    double? targetOffset;
    const double safety = 8.0; // larger margin to avoid edge clipping

    // For resize operations (force=true), position in middle row of viewport
    if (force) {
      // Calculate how many rows fit in the viewport
      final rowsInViewport =
          (controller.position.viewportDimension / rowExtent).floor();
      final middleRowOffset = (rowsInViewport ~/ 2).toDouble();

      // Position selected row in the middle row of the viewport
      final selectedRowIndex = (widget.currentIndex ~/ columns).toDouble();
      targetOffset = (selectedRowIndex - middleRowOffset) * rowExtent +
          (gridPaddingVertical / 2);
    } else {
      // For navigation, just ensure fully visible
      if (rowTop < viewportTop + safety) {
        targetOffset = rowTop - safety;
      } else if (rowBottom > viewportBottom - safety) {
        targetOffset =
            rowBottom - controller.position.viewportDimension + safety;
      }
    }

    if (targetOffset == null) {
      // Already fully visible (navigation case only)
      return;
    }

    final clamped = targetOffset.clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );

    controller.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Center on selection if requested after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCenterSelection(context);
    });
    // Reset loading state when new images are loaded
    if (widget.imagePaths != _previousImagePaths) {
      _previousImagePaths = List.from(widget.imagePaths);
      _loadedThumbnails = 0;
      _isLoadingThumbnails = false;
    }

    // Mark loading as complete when all thumbnails are loaded
    if (widget.imagePaths.isNotEmpty &&
        _isLoadingThumbnails &&
        _loadedThumbnails >= widget.imagePaths.length) {
      setState(() {
        _isLoadingThumbnails = false;
      });
    }

    if (widget.imagePaths.isEmpty) {
      return Container(
      margin: const EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
        borderRadius: BorderRadius.circular(7),
        color: Colors.grey.shade50,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No Images',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Thumbnails will appear here',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state while thumbnails are being generated
    if (_isLoadingThumbnails) {
      return Container(
      margin: const EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
        borderRadius: BorderRadius.circular(7),
        color: Colors.grey.shade50,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Generating thumbnails...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Determine visible list based on filter mode
    final List<String> visiblePaths = _getVisiblePaths();
    _visiblePaths = visiblePaths;

    // Use actual layout width: count thumbs across so Up/Down arrows move by row.
    // Updates when window is resized or thumbnail size slider changes.
    return LayoutBuilder(
      builder: (context, constraints) {
        const double containerMarginH = 6.0; // Container margin 3 * 2
        const double gridPaddingH = 16.0; // GridView padding 8 * 2
        final double crossAxisExtent =
            constraints.maxWidth - containerMarginH - gridPaddingH;
        // Same formula as SliverGridDelegate: count * size + (count-1) * spacing <= extent => count <= (extent + spacing) / (size + spacing)
        final int columns = ((crossAxisExtent + _thumbSpacing) /
                (_thumbSize + _thumbSpacing))
            .floor();
        final int cols = columns > 0 ? columns : 4;
        _lastComputedColumns = cols;

        // Report when column count changes (window resize or thumb size change).
        if (widget.onColumnsComputed != null &&
            cols > 0 &&
            cols != _lastReportedColumns) {
          _lastReportedColumns = cols;
          final colsToReport = cols;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onColumnsComputed!(colsToReport);
          });
        }

        return Container(
      margin: const EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
        borderRadius: BorderRadius.circular(7),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              border: Border(
                bottom: BorderSide(color: const Color(0xFFE6E6E6), width: 0.7),
              ),
            ),
            child: _buildThumbnailToolbar(),
          ),

          // Thumbnail grid
          Expanded(
            child: GridView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: _thumbSpacing,
                crossAxisSpacing: _thumbSpacing,
                childAspectRatio: 1.0,
              ),
              itemCount: visiblePaths.length,
              itemBuilder: (context, index) {
                final imagePath = visiblePaths[index];
                final isCurrent =
                    widget.imagePaths.indexOf(imagePath) == widget.currentIndex;
                final isMultiSelected = _selectedImages.contains(imagePath);
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _handleThumbnailTap(imagePath);
                    },
                    onSecondaryTapDown: (TapDownDetails details) {
                      unawaited(_showContextMenu(
                          context, imagePath, details.globalPosition));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrent ? null : Colors.white,
                        gradient: isCurrent
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.07),
                                  Colors.white,
                                ],
                                stops: const [0.0, 0.52],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMultiSelected
                              ? Colors.blue
                              : isCurrent
                                  ? const Color(0xFF424242)
                                  : Colors.grey.shade500,
                          width: isMultiSelected
                              ? 2.0
                              : isCurrent
                                  ? 1.0
                                  : 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Color label badge (top-left)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Builder(builder: (context) {
                              final label = widget.xmpLabels?[imagePath];
                              final c = _labelToColor(label);
                              if (c == null) return const SizedBox.shrink();
                              return Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 1),
                                ),
                              );
                            }),
                          ),
                          // Multi-select check (top-right)
                          if (isMultiSelected)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          // Saved (IPTC written) — floppy-disk style
                          if (widget.savedImages.contains(imagePath))
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Icon(
                                Icons.save,
                                size: (_thumbSize * 0.09).clamp(11.0, 18.0),
                                color: Colors.green.shade700,
                              ),
                            ),
                          // Lock — bottom-left
                          if ((widget.lockedPaths ?? const {})
                              .contains(imagePath))
                            const Positioned(
                              bottom: 4,
                              left: 4,
                              child: Icon(Icons.lock,
                                  size: 12, color: Colors.black54),
                            ),
                          // Main content on top
                          Column(
                            children: [
                              // Image thumbnail (+ FTP watermark over image only)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      Opacity(
                                        opacity: widget.uploadedImages
                                                .contains(imagePath)
                                            ? 0.54
                                            : 1.0,
                                        child: _buildThumbnail(imagePath),
                                      ),
                                      if (widget.uploadedImages
                                          .contains(imagePath))
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 2,
                                          child: Center(
                                            child: Text(
                                              'FTP',
                                              style: TextStyle(
                                                fontSize: _thumbSize * 0.42,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade600
                                                    .withValues(alpha: 0.72),
                                                letterSpacing: 2.0,
                                                shadows: const [
                                                  Shadow(
                                                    offset: Offset(0, 0),
                                                    blurRadius: 3,
                                                    color: Color(0xE6FFFFFF),
                                                  ),
                                                  Shadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2,
                                                    color: Color(0x66000000),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Filename at top
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: const BoxDecoration(
                                  color: Colors.transparent,
                                ),
                                child: Text(
                                  p.basename(imagePath),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Time at bottom
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: const BoxDecoration(
                                  color: Colors.transparent,
                                ),
                                child: () {
                                  final provided = widget.exifTimes?[imagePath];
                                  if (provided != null && provided.isNotEmpty) {
                                    return Text(
                                      provided,
                                      style: const TextStyle(
                                          fontSize: 9, color: Colors.grey),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  }
                                  return FutureBuilder<String>(
                                    future: _getImageTime(imagePath),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData &&
                                          snapshot.data!.isNotEmpty) {
                                        return Text(
                                          snapshot.data!,
                                          style: const TextStyle(
                                              fontSize: 9, color: Colors.grey),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  );
                                }(),
                              ),
                            ],
                          ),
                          // Upload progress overlay (must render last to sit on top)
                          if ((widget.uploadProgress.containsKey(imagePath) &&
                                  widget.uploadProgress[imagePath]! < 1.0) ||
                              widget.queuedUploads.contains(imagePath))
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.85),
                                  borderRadius: BorderRadius.zero,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Show different icons and content based on state
                                      if (widget.uploadProgress
                                              .containsKey(imagePath) &&
                                          widget.uploadProgress[imagePath]! <
                                              1.0) ...[
                                        // Currently uploading
                                        Icon(
                                          Icons.cloud_upload,
                                          size: _thumbSize * 0.2,
                                          color: const Color(0xFF0052CC),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: _thumbSize * 0.75,
                                          child: LinearProgressIndicator(
                                            value: widget
                                                .uploadProgress[imagePath],
                                            minHeight: 14,
                                            backgroundColor:
                                                Colors.white.withOpacity(0.3),
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Colors.white),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${(widget.uploadProgress[imagePath]! * 100).toInt()}%',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: _thumbSize * 0.08,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ] else ...[
                                        // Queued
                                        Icon(
                                          Icons.schedule,
                                          size: _thumbSize * 0.2,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Queued',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: _thumbSize * 0.08,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Waiting...',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.8),
                                            fontSize: _thumbSize * 0.06,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    },
    );
  }

  Widget _buildThumbnail(String imagePath) {
    // Decode at a resolution matching the current thumbnail size and screen DPR
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // Subtract padding inside the image container (approx 8px) before scaling
    final double targetLogicalWidth = (_thumbSize - 8).clamp(80.0, 2000.0);
    final int cacheWidthPx = (targetLogicalWidth * devicePixelRatio).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: OrientedFilePreview(
          path: imagePath,
          fit: BoxFit.contain,
          cacheWidth: cacheWidthPx,
          filterQuality: FilterQuality.high,
          onLoaded: _onThumbnailLoaded,
        ),
      ),
    );
  }

  // Removed dimension probing to speed up thumbnail rendering

  Future<void> _showContextMenu(
      BuildContext context, String imagePath, Offset tapPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(tapPosition, tapPosition),
      Offset.zero & overlay.size,
    );

    final isMultiSelect = _selectedImages.isNotEmpty;
    final selectedCount = _selectedImages.length;

    final List<PopupMenuEntry<String>> entries;
    if (isMultiSelect) {
      entries = [
        AppPopupMenu.tile(
          value: 'paste_metadata',
          label: 'Paste Metadata ($selectedCount)',
          icon: Icons.paste_outlined,
        ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'ftp_images',
          label: 'FTP Images ($selectedCount)',
          icon: Icons.cloud_upload_outlined,
        ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'delete_images',
          label: 'Delete Images ($selectedCount)',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ];
    } else {
      entries = [
        AppPopupMenu.tile(
          value: 'copy_metadata',
          label: 'Copy Metadata',
          icon: Icons.copy_outlined,
        ),
        AppPopupMenu.tile(
          value: 'paste_metadata',
          label: 'Paste Metadata',
          icon: Icons.paste_outlined,
        ),
        AppPopupMenu.tile(
          value: 'apply_iptc_template',
          label: 'Apply IPTC Template',
          icon: Icons.description_outlined,
        ),
        if (widget.onEditMetadata != null)
          AppPopupMenu.tile(
            value: 'edit_iptc',
            label: 'Edit IPTC',
            icon: Icons.edit_outlined,
          ),
        if (widget.onEditInPhotoshop != null)
          AppPopupMenu.tile(
            value: 'edit_photoshop',
            label: 'Edit in Photoshop',
            icon: Icons.brush_outlined,
          ),
        const PopupMenuDivider(height: 1),
        if (widget.uploadedImages.contains(imagePath))
          AppPopupMenu.tile(
            value: 'remove_ftp',
            label: 'Remove FTP Status',
            icon: Icons.cloud_done_outlined,
          )
        else
          AppPopupMenu.tile(
            value: 'ftp_image',
            label: 'FTP Image',
            icon: Icons.cloud_upload_outlined,
          ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'open',
          label: 'Open in Finder',
          icon: Icons.open_in_new,
        ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'rename',
          label: 'Rename Image',
          icon: Icons.drive_file_rename_outline,
        ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'delete',
          label: 'Delete Image',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ];
    }

    final result = await showAppContextMenu<String>(
      context: context,
      position: position,
      items: entries,
    );
    if (!context.mounted || result == null) return;
    _handleContextMenuAction(result, imagePath, tapPosition);
  }

  void _handleContextMenuAction(
      String action, String imagePath, Offset tapPosition) {
    switch (action) {
      case 'edit_iptc':
        final originalIndex = widget.imagePaths.indexOf(imagePath);
        if (originalIndex != -1) {
          widget.onImageSelected(originalIndex);
          Future.microtask(() => widget.onEditMetadata?.call());
        } else {
          widget.onEditMetadata?.call();
        }
        break;
      case 'edit_photoshop':
        widget.onEditInPhotoshop?.call(imagePath);
        break;
      case 'select':
        final originalIndex = widget.imagePaths.indexOf(imagePath);
        if (originalIndex != -1) {
          widget.onImageSelected(originalIndex);
        }
        break;
      case 'open':
        // Open in Finder (macOS)
        Process.run('open', ['-R', imagePath]);
        break;
      case 'rename':
        // Show rename dialog
        _showRenameDialog(context, imagePath, tapPosition);
        break;
      case 'copy_path':
        // Copy path to clipboard
        Clipboard.setData(ClipboardData(text: imagePath));
        break;
      case 'remove_ftp':
        // Remove FTP status (would need to be implemented in parent)
        print('Remove FTP status for: $imagePath');
        break;
      case 'mark_ftp':
        // Mark as FTPd (would need to be implemented in parent)
        print('Mark as FTPd: $imagePath');
        break;
      case 'ftp_image':
        // FTP the image
        widget.onFtpImage?.call(imagePath);
        break;
      case 'copy_metadata':
        // Copy metadata from this image
        widget.onCopyMetadata?.call(imagePath);
        break;
      case 'paste_metadata':
        // Paste metadata to selected images or single image
        if (_selectedImages.isNotEmpty) {
          // Paste to all selected images
          final selectedCount = _selectedImages.length;
          for (final selectedPath in _selectedImages) {
            widget.onPasteMetadata?.call(selectedPath);
          }

          // Keep selection active after paste

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Metadata pasted to $selectedCount images'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Paste to single image
          widget.onPasteMetadata?.call(imagePath);
        }
        break;
      case 'apply_iptc_template':
        // Apply IPTC template to this image
        widget.onApplyIptcTemplate?.call(imagePath);
        break;
      case 'delete':
        // Show confirmation dialog at the click position
        _showDeleteDialog(context, imagePath, tapPosition);
        break;
      case 'ftp_images':
        // FTP multiple selected images
        _ftpMultipleImages();
        break;
      case 'delete_images':
        // Delete multiple selected images
        _deleteMultipleImages(context, tapPosition);
        break;
    }
  }

  void _ftpMultipleImages() {
    // FTP all selected images
    final selectedCount = _selectedImages.length;
    print('DEBUG: FTPing $selectedCount images: $_selectedImages');

    for (final imagePath in _selectedImages) {
      print('DEBUG: Calling onFtpImage for: $imagePath');
      widget.onFtpImage?.call(imagePath);
    }

    // Keep selection active after FTP (like paste metadata)

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $selectedCount images to FTP queue'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _deleteMultipleImages(BuildContext context, Offset tapPosition) {
    // Show confirmation dialog for multiple deletions
    final selectedCount = _selectedImages.length;

    // Calculate dialog position based on tap position
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = 400.0;
    final dialogHeight = 200.0;

    // Position dialog near the tap position, but ensure it stays on screen
    double left = tapPosition.dx - (dialogWidth / 2);
    double top = tapPosition.dy - (dialogHeight / 2);

    // Ensure dialog stays within screen bounds
    left = left.clamp(16.0, screenSize.width - dialogWidth - 16.0);
    top = top.clamp(16.0, screenSize.height - dialogHeight - 16.0);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: dialogWidth,
                  height: dialogHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Delete Images',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Are you sure you want to delete $selectedCount images?\n\nThis action cannot be undone.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 11,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 16),
                          ElevatedGreyButton(
                            label: 'Delete',
                            fontSize: 11,
                            isDanger: true,
                            onPressed: () {
                              Navigator.of(context).pop();
                              _executeMultipleDeletions();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _executeMultipleDeletions() async {
    final selectedPaths = _selectedImages.toList();
    int deletedCount = 0;

    for (final imagePath in selectedPaths) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
          deletedCount++;

          // Notify parent widget that image was deleted
          widget.onImageDeleted?.call(imagePath);
        }
      } catch (e) {
        print('Error deleting file: $e');
      }
    }

    // Clear selection after deletion
    setState(() {
      _selectedImages.clear();
      _isMultiSelectMode = false;
    });

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $deletedCount images'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showRenameDialog(
      BuildContext context, String imagePath, Offset tapPosition) {
    final currentFileName = p.basename(imagePath);
    final currentNameWithoutExt = p.basenameWithoutExtension(imagePath);
    final extension = p.extension(imagePath);

    // Calculate dialog position based on tap position
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = 400.0;
    final dialogHeight = 250.0;

    // Position dialog near the tap position, but ensure it stays on screen
    double left = tapPosition.dx - (dialogWidth / 2);
    double top = tapPosition.dy - (dialogHeight / 2);

    // Ensure dialog stays within screen bounds
    left = left.clamp(16.0, screenSize.width - dialogWidth - 16.0);
    top = top.clamp(16.0, screenSize.height - dialogHeight - 16.0);

    final TextEditingController controller =
        TextEditingController(text: currentNameWithoutExt);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: dialogWidth,
                  height: dialogHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Rename Image',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              'Current name: $currentFileName',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'New name',
                                hintText:
                                    'Enter new filename (without extension)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                suffixText: extension,
                              ),
                              autofocus: true,
                              onSubmitted: (value) {
                                if (value.trim().isNotEmpty) {
                                  _renameImage(
                                      imagePath, value.trim() + extension);
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 11,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 16),
                          ElevatedGreyButton(
                            label: 'Rename',
                            fontSize: 11,
                            isPrimary: true,
                            onPressed: () {
                              final newName = controller.text.trim();
                              if (newName.isNotEmpty) {
                                _renameImage(imagePath, newName + extension);
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(
      BuildContext context, String imagePath, Offset tapPosition) {
    // Calculate dialog position based on tap position
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = 400.0;
    final dialogHeight = 200.0;

    // Position dialog near the tap position, but ensure it stays on screen
    double left = tapPosition.dx - (dialogWidth / 2);
    double top = tapPosition.dy - (dialogHeight / 2);

    // Ensure dialog stays within screen bounds
    left = left.clamp(16.0, screenSize.width - dialogWidth - 16.0);
    top = top.clamp(16.0, screenSize.height - dialogHeight - 16.0);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: dialogWidth,
                  height: dialogHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Delete Image',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Are you sure you want to delete "${p.basename(imagePath)}"?\n\nThis action cannot be undone.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 11,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 16),
                          ElevatedGreyButton(
                            label: 'Delete',
                            fontSize: 11,
                            isDanger: true,
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteImage(imagePath);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _renameImage(String oldPath, String newFileName) async {
    try {
      final oldFile = File(oldPath);
      if (!await oldFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File not found'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final directory = p.dirname(oldPath);
      final newPath = p.join(directory, newFileName);
      final newFile = File(newPath);

      // Check if new filename already exists
      if (await newFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "$newFileName" already exists'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Rename the file
      await oldFile.rename(newPath);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Renamed to: $newFileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Notify parent widget that file was renamed
      widget.onImageRenamed?.call(oldPath, newPath);
      print('Successfully renamed: $oldPath -> $newPath');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error renaming file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error renaming file: $e');
    }
  }

  void _deleteImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted: ${p.basename(imagePath)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Notify parent widget that image was deleted
        widget.onImageDeleted?.call(imagePath);
        print('Successfully deleted: $imagePath');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File not found'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error deleting file: $e');
    }
  }

  void _showThumbnailPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ThumbnailPopupDialog(
          imagePaths: widget.imagePaths,
          currentIndex: widget.currentIndex,
          onImageSelected: (index) {
            widget.onImageSelected(index);
            Navigator.of(context).pop();
          },
          onEditMetadata: widget.onEditMetadata,
          savedImages: widget.savedImages,
          uploadedImages: widget.uploadedImages,
          queuedUploads: widget.queuedUploads,
          currentlyUploading: widget.currentlyUploading,
          uploadProgress: widget.uploadProgress,
          xmpRatings: widget.xmpRatings ?? {},
          xmpLabels: widget.xmpLabels ?? {},
          xmpTagged: widget.xmpTagged ?? {},
          lockedPaths: widget.lockedPaths ?? {},
        );
      },
    );
  }
}
