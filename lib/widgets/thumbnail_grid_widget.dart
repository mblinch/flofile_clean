import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:extended_image/extended_image.dart';
import '../utils/exiftool_helper.dart';
import 'thumbnail_popup_dialog.dart';

class ThumbnailGridWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final ScrollController? scrollController;
  final double? loadingProgress; // Add loading progress parameter
  final Map<String, String>? exifTimes; // Optional precomputed EXIF times
  final Set<String> uploadedImages; // Track uploaded images
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

  const ThumbnailGridWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    this.scrollController,
    this.loadingProgress,
    this.exifTimes,
    required this.uploadedImages,
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
  });

  @override
  State<ThumbnailGridWidget> createState() => ThumbnailGridWidgetState();
}

class ThumbnailGridWidgetState extends State<ThumbnailGridWidget> {
  // Thumbnail size control
  double _thumbSize = 110.0; // Start at second smallest size (110px)
  double _thumbSpacing = 14.0;
  int _lastComputedColumns = 4;
  int _lastReportedColumns = 4;
  int _lastCenterRequestId = 0;
  String? _ftpFilterMode; // null, 'hide_ftpd', 'show_ftpd'
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

  /// Compact label for the FTP filter bar trigger (team-picker style).
  String _ftpFilterBarLabel() {
    if (_ftpFilterMode == null) return 'All images';
    if (_ftpFilterMode == 'hide_ftpd') return 'Hide FTPd';
    return 'Show FTPd';
  }

  void _handleThumbnailTap(String imagePath) {
    // Check if Cmd/Meta key is pressed
    final isMetaPressed = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaLeft) ||
        RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.metaRight);

    print('DEBUG: _handleThumbnailTap called, isMetaPressed: $isMetaPressed');
    print('DEBUG: Keys pressed: ${RawKeyboard.instance.keysPressed}');

    // If Cmd is not pressed, clear selection and select single image
    if (!isMetaPressed) {
      setState(() {
        _selectedImages.clear();
        _isMultiSelectMode = false;
      });

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
      setState(() {
        _selectedImages.add(currentImagePath);
        _isMultiSelectMode = true;
      });
      print('DEBUG: Added current image to selection: $currentImagePath');
    }

    if (_selectedImages.contains(imagePath)) {
      // Remove from selection
      setState(() {
        _selectedImages.remove(imagePath);
        _isMultiSelectMode = _selectedImages.isNotEmpty;
      });

      // If no more selections, select the clicked image normally
      if (_selectedImages.isEmpty) {
        final originalIndex = widget.imagePaths.indexOf(imagePath);
        if (originalIndex != -1) {
          widget.onImageSelected(originalIndex);
        }
      }
    } else {
      // Add to selection
      setState(() {
        _selectedImages.add(imagePath);
        _isMultiSelectMode = true;
      });

      // Also make this the current image
      final originalIndex = widget.imagePaths.indexOf(imagePath);
      if (originalIndex != -1) {
        widget.onImageSelected(originalIndex);
      }

      // Notify parent of multi-selection
      widget.onMultiSelect?.call(_selectedImages.toList());
    }
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
    // Start with FTP filter
    Iterable<String> paths;
    if (_ftpFilterMode == 'hide_ftpd') {
      paths =
          widget.imagePaths.where((p) => !widget.uploadedImages.contains(p));
    } else if (_ftpFilterMode == 'show_ftpd') {
      paths = widget.imagePaths.where((p) => widget.uploadedImages.contains(p));
    } else {
      paths = widget.imagePaths;
    }

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
        margin: const EdgeInsets.all(3.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.zero,
          color: Colors.grey.shade50,
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
        margin: const EdgeInsets.all(3.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.zero,
          color: Colors.white,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Generating thumbnails...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_loadedThumbnails / ${widget.imagePaths.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
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
      margin: const EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.zero,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.zero,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left — FTP filter (same chrome as team picker: Material + bordered white box)
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Material(
                          elevation: 2,
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                            ),
                            child: PopupMenuButton<String>(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 0),
                              // Do not set [constraints] on PopupMenuButton — it is applied to
                              // the *popup menu* (showMenu), not the trigger. A small maxHeight
                              // here was clipping the menu to ~22px so labels looked empty.
                              onSelected: (value) {
                                setState(() {
                                  if (value == 'all') {
                                    _ftpFilterMode = null;
                                  } else if (value == 'hide') {
                                    _ftpFilterMode = 'hide_ftpd';
                                  } else {
                                    _ftpFilterMode = 'show_ftpd';
                                  }
                                  if (_ftpFilterMode == 'hide_ftpd' &&
                                      widget.currentIndex <
                                          widget.imagePaths.length &&
                                      widget.uploadedImages.contains(widget
                                          .imagePaths[widget.currentIndex])) {
                                    int nextIndex = widget.currentIndex + 1;
                                    while (nextIndex <
                                            widget.imagePaths.length &&
                                        widget.uploadedImages.contains(
                                            widget.imagePaths[nextIndex])) {
                                      nextIndex++;
                                    }
                                    if (nextIndex >= widget.imagePaths.length) {
                                      nextIndex = widget.currentIndex - 1;
                                      while (nextIndex >= 0 &&
                                          widget.uploadedImages.contains(
                                              widget.imagePaths[nextIndex])) {
                                        nextIndex--;
                                      }
                                    }
                                    if (nextIndex >= 0 &&
                                        nextIndex < widget.imagePaths.length) {
                                      widget.onImageSelected(nextIndex);
                                    }
                                  }
                                });
                                _ensureVisibleAfterLayout();
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'all',
                                  child: Text(
                                    'Show All Images',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'hide',
                                  child: Text(
                                    'Hide FTPd Images',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'show',
                                  child: Text(
                                    'Show FTPd Images',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                              child: SizedBox(
                                height: 24,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      _ftpFilterBarLabel(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade800,
                                        height: 1.0,
                                      ),
                                    ),
                                    Icon(Icons.arrow_drop_down,
                                        size: 12,
                                        color: Colors.grey.shade700),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Center — plain text link (no chip)
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showThumbnailPopup(),
                          child: Text(
                            'SEE LARGER THUMBNAILS',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                              letterSpacing: 0.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Right — size stepper (fixed width for stable layout)
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 118),
                            child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      final currentStep =
                                          ((_thumbSize - 80) / 30).round();
                                      final newStep =
                                          (currentStep - 1).clamp(0, 4);
                                      _thumbSize = 80 + (newStep * 30);
                                      _thumbSpacing = _thumbSize * 0.1;
                                    });
                                    _ensureVisibleAfterLayout();
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Icon(
                                      Icons.remove,
                                      size: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${_thumbSize.toInt()}px',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                      height: 1.0,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      final currentStep =
                                          ((_thumbSize - 80) / 30).round();
                                      final newStep =
                                          (currentStep + 1).clamp(0, 4);
                                      _thumbSize = 80 + (newStep * 30);
                                      _thumbSpacing = _thumbSize * 0.1;
                                    });
                                    _ensureVisibleAfterLayout();
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      size: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                      _showContextMenu(
                          context, imagePath, details.globalPosition);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: isMultiSelected
                              ? Colors.blue
                              : isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade500,
                          width: isMultiSelected
                              ? 2.0
                              : isCurrent
                                  ? 3.0
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
                          // Background FTP watermark (only for uploaded images)
                          if (widget.uploadedImages.contains(imagePath))
                            Positioned.fill(
                              child: Center(
                                child: Text(
                                  'FTP',
                                  style: TextStyle(
                                    fontSize: _thumbSize * 0.4,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade200,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ),
                            ),
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
                          // Selection checkmark for multi-selected images
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
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          // Current preview marker
                          if (isCurrent && !isMultiSelected)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: const Text(
                                  'CURRENT',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          // Rocket with checkmark for uploaded images
                          if (widget.uploadedImages.contains(imagePath))
                            Positioned(
                              bottom: 4,
                              left: 4,
                              child: Icon(
                                Icons.rocket_launch,
                                size: _thumbSize * 0.09,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          // Lock icon for locked images
                          if ((widget.lockedPaths ?? const {})
                              .contains(imagePath))
                            const Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(Icons.lock,
                                  size: 12, color: Colors.black54),
                            ),
                          // Main content on top
                          Column(
                            children: [
                              // Image thumbnail
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Opacity(
                                    opacity: widget.uploadedImages.contains(imagePath) ? 0.5 : 1.0,
                                    child: _buildThumbnail(imagePath),
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

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.zero,
      ),
      child: ExtendedImage.file(
        File(imagePath),
        fit: BoxFit.contain,
        cacheWidth: cacheWidthPx,
        // Let height scale automatically for speed; request higher quality at larger sizes
        filterQuality: FilterQuality.high,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.completed ||
              state.extendedImageLoadState == LoadState.failed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onThumbnailLoaded();
            });
          }
          return null;
        },
      ),
    );
  }

  // Removed dimension probing to speed up thumbnail rendering

  void _showContextMenu(
      BuildContext context, String imagePath, Offset tapPosition) {
    // Check if we're in multi-selection mode
    final isMultiSelect = _selectedImages.isNotEmpty;
    final selectedCount = _selectedImages.length;

    // Position the menu at the tap location
    final double menuWidth = 200.0;
    final double menuHeight =
        isMultiSelect ? 200.0 : 300.0; // Smaller for multi-select

    // Ensure menu doesn't go off screen
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Size screenSize = overlay.size;

    double x = tapPosition.dx;
    double y = tapPosition.dy;

    // Adjust if menu would go off the right edge
    if (x + menuWidth > screenSize.width) {
      x = screenSize.width - menuWidth - 10;
    }

    // Adjust if menu would go off the bottom edge
    if (y + menuHeight > screenSize.height) {
      y = screenSize.height - menuHeight - 10;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Transparent overlay to capture taps outside
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Context menu positioned at tap location
            Positioned(
              left: x,
              top: y,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: menuWidth,
                  constraints: BoxConstraints(maxHeight: menuHeight),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: isMultiSelect
                        ? [
                            // Multi-selection menu items
                            _buildMenuItem(
                                'paste_metadata',
                                'Paste Metadata ($selectedCount)',
                                Icons.paste,
                                imagePath,
                                tapPosition),
                            const Divider(height: 1),
                            _buildMenuItem(
                                'ftp_images',
                                'FTP Images ($selectedCount)',
                                Icons.rocket_launch,
                                imagePath,
                                tapPosition),
                            const Divider(height: 1),
                            _buildMenuItem(
                                'delete_images',
                                'Delete Images ($selectedCount)',
                                Icons.delete,
                                imagePath,
                                tapPosition,
                                isDestructive: true),
                          ]
                        : [
                            // Single selection menu items
                            _buildMenuItem('copy_metadata', 'Copy Metadata',
                                Icons.copy, imagePath, tapPosition),
                            _buildMenuItem('paste_metadata', 'Paste Metadata',
                                Icons.paste, imagePath, tapPosition),
                            _buildMenuItem(
                                'apply_iptc_template',
                                'Apply IPTC Template',
                                Icons.description,
                                imagePath,
                                tapPosition),
                            if (widget.onEditMetadata != null)
                              _buildMenuItem('edit_iptc', 'Edit IPTC',
                                  Icons.edit, imagePath, tapPosition),
                            if (widget.onEditInPhotoshop != null)
                              _buildMenuItem(
                                  'edit_photoshop',
                                  'Edit in Photoshop',
                                  Icons.brush,
                                  imagePath,
                                  tapPosition),
                            const Divider(height: 1),
                            if (widget.uploadedImages.contains(imagePath))
                              _buildMenuItem('remove_ftp', 'Remove FTP Status',
                                  Icons.rocket_launch, imagePath, tapPosition),
                            if (!widget.uploadedImages.contains(imagePath))
                              _buildMenuItem('ftp_image', 'FTP Image',
                                  Icons.rocket_launch, imagePath, tapPosition),
                            const Divider(height: 1),
                            _buildMenuItem('open', 'Open in Finder',
                                Icons.open_in_new, imagePath, tapPosition),
                            const Divider(height: 1),
                            _buildMenuItem('rename', 'Rename Image', Icons.edit,
                                imagePath, tapPosition),
                            const Divider(height: 1),
                            _buildMenuItem('delete', 'Delete Image',
                                Icons.delete, imagePath, tapPosition,
                                isDestructive: true),
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

  Widget _buildMenuItem(String value, String text, IconData icon,
      String imagePath, Offset tapPosition,
      {bool isDestructive = false}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _handleContextMenuAction(value, imagePath, tapPosition);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isDestructive ? Colors.red : Colors.black87,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: isDestructive ? Colors.red : Colors.black87,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
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
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _executeMultipleDeletions();
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text('Delete'),
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
                                  borderRadius: BorderRadius.circular(4),
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
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () {
                              final newName = controller.text.trim();
                              if (newName.isNotEmpty) {
                                _renameImage(imagePath, newName + extension);
                                Navigator.of(context).pop();
                              }
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.blue),
                            child: const Text('Rename'),
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
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteImage(imagePath);
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text('Delete'),
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
