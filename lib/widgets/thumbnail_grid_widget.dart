import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:extended_image/extended_image.dart';
import '../utils/exiftool_helper.dart';

class ThumbnailGridWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final ScrollController? scrollController;
  final double? loadingProgress; // Add loading progress parameter
  final Map<String, String>? exifTimes; // Optional precomputed EXIF times
  final Set<String> uploadedImages; // Track uploaded images
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
  // Callback for FTP operations
  final Function(String)? onFtpImage;

  const ThumbnailGridWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    this.scrollController,
    this.loadingProgress,
    this.exifTimes,
    required this.uploadedImages,
    this.xmpRatings,
    this.xmpLabels,
    this.xmpTagged,
    this.lockedPaths,
    required this.uploadProgress,
    required this.centerRequestId,
    this.onImageDeleted,
    this.onCopyMetadata,
    this.onPasteMetadata,
    this.onFtpImage,
  });

  @override
  State<ThumbnailGridWidget> createState() => _ThumbnailGridWidgetState();
}

class _ThumbnailGridWidgetState extends State<ThumbnailGridWidget> {
  // Thumbnail size control
  double _thumbSize = 110.0; // Start at second smallest size (110px)
  double _thumbSpacing = 14.0;
  int _lastComputedColumns = 4;
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

  void _maybeCenterSelection(BuildContext context, {bool force = false}) {
    if (widget.scrollController == null) return;
    if (!force && widget.centerRequestId == _lastCenterRequestId) return;
    if (!force) _lastCenterRequestId = widget.centerRequestId;

    final controller = widget.scrollController!;
    if (!controller.hasClients) return;

    // Recalculate columns from the actual rendered width so math matches layout
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Account for GridView padding (8 on each side)
    const double gridPaddingHorizontal = 16.0; // 8 left + 8 right
    const double gridPaddingVertical = 16.0; // 8 top + 8 bottom
    final availableWidth = renderBox.size.width - gridPaddingHorizontal;
    final columnsCalc =
        ((availableWidth - _thumbSpacing) / (_thumbSize + _thumbSpacing))
            .floor();
    final columns = columnsCalc > 0 ? columnsCalc : 4;

    // Compute actual row height using current layout parameters
    final totalSpacing = (columns - 1) * _thumbSpacing;
    final cellWidth = (availableWidth - totalSpacing) / columns; // aspect 1.0
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
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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

    // Calculate grid parameters based on container size
    final containerWidth =
        MediaQuery.of(context).size.width * 0.4; // Approximate width
    final columns =
        ((containerWidth - _thumbSpacing) / (_thumbSize + _thumbSpacing))
            .floor();
    _lastComputedColumns = columns > 0 ? columns : _lastComputedColumns;

    // Determine visible list based on filter mode
    final List<String> visiblePaths = _getVisiblePaths();
    _visiblePaths = visiblePaths;

    return Container(
      margin: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Thumbnail grid
          Expanded(
            child: GridView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns > 0 ? columns : 4,
                mainAxisSpacing: _thumbSpacing,
                crossAxisSpacing: _thumbSpacing,
                childAspectRatio: 1.0,
              ),
              itemCount: visiblePaths.length,
              itemBuilder: (context, index) {
                final imagePath = visiblePaths[index];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      final originalIndex =
                          widget.imagePaths.indexOf(imagePath);
                      if (originalIndex != -1) {
                        widget.onImageSelected(originalIndex);
                      }
                    },
                    onSecondaryTapDown: (TapDownDetails details) {
                      _showContextMenu(
                          context, imagePath, details.globalPosition);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: widget.imagePaths.indexOf(imagePath) ==
                                  widget.currentIndex
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade500,
                          width: widget.imagePaths.indexOf(imagePath) ==
                                  widget.currentIndex
                              ? 1.5
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
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
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
                          if (widget.uploadProgress.containsKey(imagePath) &&
                              widget.uploadProgress[imagePath]! < 1.0)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.cloud_upload,
                                        size: _thumbSize * 0.2,
                                        color: const Color(0xFF0052CC),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: _thumbSize * 0.75,
                                        child: LinearProgressIndicator(
                                          value:
                                              widget.uploadProgress[imagePath],
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

          // Bottom bar with slider
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SizedBox(
              height: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      DropdownButton<String>(
                        value: _ftpFilterMode == null
                            ? 'all'
                            : _ftpFilterMode == 'hide_ftpd'
                                ? 'hide'
                                : 'show',
                        isDense: true,
                        underline: Container(),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.black),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Show All Images'),
                          ),
                          DropdownMenuItem(
                            value: 'hide',
                            child: Text('Hide FTPd Images'),
                          ),
                          DropdownMenuItem(
                            value: 'show',
                            child: Text('Show FTPd Images'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            if (value == 'all') {
                              _ftpFilterMode = null;
                            } else if (value == 'hide') {
                              _ftpFilterMode = 'hide_ftpd';
                            } else if (value == 'show') {
                              _ftpFilterMode = 'show_ftpd';
                            }

                            // Handle current image selection when hiding FTPd images
                            if (_ftpFilterMode == 'hide_ftpd' &&
                                widget.currentIndex <
                                    widget.imagePaths.length &&
                                widget.uploadedImages.contains(
                                    widget.imagePaths[widget.currentIndex])) {
                              int nextIndex = widget.currentIndex + 1;
                              while (nextIndex < widget.imagePaths.length &&
                                  widget.uploadedImages
                                      .contains(widget.imagePaths[nextIndex])) {
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
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Thumbnail size control with plus/minus buttons
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Minus button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              // Move to previous division (30px increments)
                              final currentStep =
                                  ((_thumbSize - 80) / 30).round();
                              final newStep = (currentStep - 1).clamp(0, 4);
                              _thumbSize = 80 + (newStep * 30);
                              _thumbSpacing = _thumbSize * 0.1;
                            });
                            _ensureVisibleAfterLayout();
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Icon(
                              Icons.remove,
                              size: 12,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Size text
                        Text(
                          '${_thumbSize.round()}px',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Plus button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              // Move to next division (30px increments)
                              final currentStep =
                                  ((_thumbSize - 80) / 30).round();
                              final newStep = (currentStep + 1).clamp(0, 4);
                              _thumbSize = 80 + (newStep * 30);
                              _thumbSpacing = _thumbSize * 0.1;
                            });
                            _ensureVisibleAfterLayout();
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 12,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(2),
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
    // Position the menu at the tap location
    final double menuWidth = 200.0;
    final double menuHeight = 300.0;

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
                    children: [
                      _buildMenuItem('copy_metadata', 'Copy Metadata',
                          Icons.copy, imagePath),
                      _buildMenuItem('paste_metadata', 'Paste Metadata',
                          Icons.paste, imagePath),
                      const Divider(height: 1),
                      if (widget.uploadedImages.contains(imagePath))
                        _buildMenuItem('remove_ftp', 'Remove FTP Status',
                            Icons.rocket_launch, imagePath),
                      if (!widget.uploadedImages.contains(imagePath))
                        _buildMenuItem('ftp_image', 'FTP Image',
                            Icons.rocket_launch, imagePath),
                      const Divider(height: 1),
                      _buildMenuItem('open', 'Open in Finder',
                          Icons.open_in_new, imagePath),
                      const Divider(height: 1),
                      _buildMenuItem(
                          'delete', 'Delete Image', Icons.delete, imagePath,
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

  Widget _buildMenuItem(
      String value, String text, IconData icon, String imagePath,
      {bool isDestructive = false}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _handleContextMenuAction(value, imagePath);
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

  void _handleContextMenuAction(String action, String imagePath) {
    switch (action) {
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
        // Paste metadata to this image
        widget.onPasteMetadata?.call(imagePath);
        break;
      case 'delete':
        // Show confirmation dialog before deleting
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Delete Image'),
              content: Text(
                  'Are you sure you want to delete "${p.basename(imagePath)}"?\n\nThis action cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _deleteImage(imagePath);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
        break;
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
}
