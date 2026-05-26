import 'package:flutter/material.dart';
import 'app_styled_dialogs.dart';
import 'color_managed_file_preview.dart';
import 'oriented_file_preview.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import '../utils/exiftool_helper.dart';
import 'dart:async';
import 'package:path/path.dart' as p;
import '../flo_layout_constants.dart';

// Public interface for the picture preview widget state
abstract class PicturePreviewWidgetState {
  void refreshExifData();
}

class PicturePreviewWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final Function() onNextImage;
  final Function() onPreviousImage;
  // Quick navigation that avoids any extra parent-side work (like thumbnail centering)
  final Function()? onQuickNextImage;
  final Function()? onQuickPreviousImage;
  final Future<void> Function()? onSaveIptc;
  final Future<void> Function()? onSaveIptcBackground;
  // Callbacks for right-click context menu
  final Function(String)? onCopyMetadata;
  final Function(String)? onPasteMetadata;
  final Function(String)? onApplyIptcTemplate;
  final Function(String)? onFtpImage;
  final Function(String)? onImageDeleted;
  final Function(String, String)? onImageRenamed;
  final Function(String)? onEditInPhotoshop;
  final Set<String>? uploadedImages;
  final Set<String>? savedImages;
  final Set<String>? queuedUploads;
  final Set<String>? currentlyUploading;
  final Map<String, double>? uploadProgress;
  final Map<String, int>? xmpRatings;
  final Map<String, String>? xmpLabels;
  final Map<String, bool>? xmpTagged;
  final Set<String>? lockedPaths;
  final List<String> multiSelectedPaths;

  final VoidCallback? onEditMetadata;
  final void Function(Map<String, dynamic>)? onExifLoaded;
  final Color? backgroundColor;

  const PicturePreviewWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    required this.onNextImage,
    required this.onPreviousImage,
    this.onQuickNextImage,
    this.onQuickPreviousImage,
    this.onSaveIptc,
    this.onSaveIptcBackground,
    this.onCopyMetadata,
    this.onPasteMetadata,
    this.onApplyIptcTemplate,
    this.onFtpImage,
    this.onImageDeleted,
    this.onImageRenamed,
    this.onEditInPhotoshop,
    this.uploadedImages,
    this.savedImages,
    this.queuedUploads,
    this.currentlyUploading,
    this.uploadProgress,
    this.xmpRatings,
    this.xmpLabels,
    this.xmpTagged,
    this.lockedPaths,
    this.multiSelectedPaths = const [],
    this.onEditMetadata,
    this.onExifLoaded,
    this.backgroundColor,
  });

  @override
  State<PicturePreviewWidget> createState() => _PicturePreviewWidgetState();
}

class _PicturePreviewWidgetState extends State<PicturePreviewWidget>
    implements PicturePreviewWidgetState {
  // EXIF data state
  Map<String, dynamic>? _exifData;
  bool _isLoadingExif = false;
  // Cache to prevent unnecessary reloads
  final Map<String, Map<String, dynamic>> _exifCache = {};
  String? _lastLoadedImagePath;

  // Method to refresh EXIF data (can be called from parent)
  @override
  void refreshExifData() {
    if (mounted) {
      setState(() {
        _exifData = null;
        _isLoadingExif = false;
      });
      _loadExifData();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadExifData();
  }

  @override
  void didUpdateWidget(PicturePreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload EXIF data if the image actually changed
    if (oldWidget.currentIndex != widget.currentIndex) {
      _loadExifData();
    }
  }

  Future<void> _loadExifData() async {
    if (widget.imagePaths.isEmpty ||
        widget.currentIndex >= widget.imagePaths.length) {
      setState(() {
        _exifData = null;
        _isLoadingExif = false;
      });
      return;
    }

    final imagePath = widget.imagePaths[widget.currentIndex];
    print('DEBUG: Loading EXIF for $imagePath');

    // Check if we already have this image's EXIF data cached
    if (_exifCache.containsKey(imagePath)) {
      print('DEBUG: Using cached EXIF data for $imagePath');
      setState(() {
        _exifData = _exifCache[imagePath];
        _isLoadingExif = false;
        _lastLoadedImagePath = imagePath;
      });
      widget.onExifLoaded?.call(_exifCache[imagePath]!);
      return;
    }

    print('DEBUG: Cache miss, running exiftool for $imagePath');
    setState(() {
      _isLoadingExif = true;
    });

    try {
      final proc = await ExiftoolHelper.run([
        '-j',
        '-Model',
        '-Make',
        '-ImageWidth',
        '-ImageHeight',
        '-ShutterSpeed',
        '-DateTimeOriginal',
        '-SubSecTimeOriginal',
        '-FNumber',
        '-ISO',
        '-LensID',
        '-LensModel',
        '-Lens',
        '-WhiteBalance',
        '-ColorTemperature',
        '-Tint',
        '-FocalLength',
        '-ExposureTime',
        imagePath,
      ]);

      if (proc.isSuccess) {
        final List data = jsonDecode(proc.stdoutText);
        if (data.isNotEmpty) {
          final exifData = data.first as Map<String, dynamic>;
          print('DEBUG: Successfully loaded EXIF data for $imagePath');
          // Cache the EXIF data
          _exifCache[imagePath] = exifData;
          _lastLoadedImagePath = imagePath;
          setState(() {
            _exifData = exifData;
            _isLoadingExif = false;
          });
          widget.onExifLoaded?.call(exifData);
        } else {
          print('DEBUG: No EXIF data returned for $imagePath');
          // Cache empty result to avoid repeated failed attempts
          _exifCache[imagePath] = {};
          _lastLoadedImagePath = imagePath;
          setState(() {
            _exifData = {};
            _isLoadingExif = false;
          });
        }
      } else {
        print('DEBUG: exiftool failed for $imagePath: ${proc.stderrText}');
        // Cache empty result to avoid repeated failed attempts
        _exifCache[imagePath] = {};
        _lastLoadedImagePath = imagePath;
        setState(() {
          _exifData = {};
          _isLoadingExif = false;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading EXIF data for $imagePath: $e');
      setState(() {
        _exifData = null;
        _isLoadingExif = false;
      });
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dt = DateTime.parse(
          dateTimeStr.replaceFirst(':', '-').replaceFirst(':', '-'));
      final month = _getMonthName(dt.month);
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$month ${dt.day}, ${dt.year} • $hour:$minute:$second $ampm';
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  String _formatShutterSpeed(dynamic shutterSpeed) {
    if (shutterSpeed == null) return '';
    final str = shutterSpeed.toString();
    if (str.contains('/')) {
      final parts = str.split('/');
      if (parts.length == 2) {
        final denominator = parts[1];
        return '1/$denominator';
      }
    }
    return str;
  }

  String _formatAperture(dynamic fNumber) {
    if (fNumber == null) return '';
    return 'f/$fNumber';
  }

  String _formatFocalLength(dynamic focalLength) {
    if (focalLength == null) return '';
    // Remove any "mm" or "mmmm" suffix and add our own "mm"
    String value = focalLength.toString().replaceAll(RegExp(r'm+$'), '');

    // Try to parse as double and remove decimal places
    try {
      double? numericValue = double.tryParse(value);
      if (numericValue != null) {
        return '${numericValue.toInt()}mm';
      }
    } catch (e) {
      // If parsing fails, use original value
    }

    return '${value}mm';
  }

  String _buildCameraAndLensText() {
    if (_exifData == null) return '';

    List<String> parts = [];

    // Add camera make and model
    String camera =
        '${_exifData!['Make'] ?? ''} ${_exifData!['Model'] ?? ''}'.trim();
    if (camera.isNotEmpty) {
      parts.add(camera);
    }

    // Add lens info
    if (_exifData!['LensModel'] != null &&
        _exifData!['LensModel'].toString().isNotEmpty) {
      parts.add('${_exifData!['LensModel']}');
    } else if (_exifData!['Lens'] != null &&
        _exifData!['Lens'].toString().isNotEmpty) {
      parts.add('${_exifData!['Lens']}');
    } else if (_exifData!['LensID'] != null &&
        _exifData!['LensID'].toString().isNotEmpty) {
      parts.add('${_exifData!['LensID']}');
    }

    return parts.join(' • ');
  }

  String _buildNaturalLanguageSettings() {
    if (_exifData == null) return '';

    List<String> parts = [];

    // Add shutter speed
    if (_exifData!['ShutterSpeed'] != null) {
      String shutter = _formatShutterSpeed(_exifData!['ShutterSpeed']);
      if (shutter.isNotEmpty) {
        parts.add(shutter);
      }
    }

    // Add aperture
    if (_exifData!['FNumber'] != null) {
      String aperture = _formatAperture(_exifData!['FNumber']);
      if (aperture.isNotEmpty) {
        parts.add(aperture);
      }
    }

    // Add focal length
    if (_exifData!['FocalLength'] != null) {
      String focal = _formatFocalLength(_exifData!['FocalLength']);
      if (focal.isNotEmpty) {
        parts.add(focal);
      }
    }

    if (parts.isEmpty) return '';

    // Join all parts with spaces
    return parts.join(' ');
  }

  /// Picks column count so square-ish cells fit in [innerW] x [innerH] without scrolling when possible.
  static int _crossAxisCountForFit(
    double innerW,
    double innerH,
    int count, {
    double spacing = 4,
    double childAspectRatio = 1.0,
  }) {
    if (count <= 0) return 1;
    if (innerW <= 0 || innerH <= 0) return math.min(2, count);

    int bestCols = 1;
    double bestTileCross = 0;

    for (int cols = 1; cols <= count; cols++) {
      final tileCross =
          (innerW - (cols - 1) * spacing) / cols;
      if (tileCross <= 0) continue;
      final tileMain = tileCross / childAspectRatio;
      final rows = (count / cols).ceil();
      final totalMain =
          rows * tileMain + (rows - 1) * spacing;
      if (totalMain <= innerH && tileCross > bestTileCross) {
        bestTileCross = tileCross;
        bestCols = cols;
      }
    }

    if (bestTileCross > 0) return bestCols;

    // Too tall for viewport: pick columns that minimize vertical overflow (scroll).
    int fallback = 1;
    double minOverflow = double.infinity;
    final maxTry = math.min(count, 8);
    for (int cols = 1; cols <= maxTry; cols++) {
      final tileCross =
          (innerW - (cols - 1) * spacing) / cols;
      if (tileCross <= 0) continue;
      final tileMain = tileCross / childAspectRatio;
      final rows = (count / cols).ceil();
      final totalMain =
          rows * tileMain + (rows - 1) * spacing;
      final overflow = totalMain - innerH;
      if (overflow < minOverflow) {
        minOverflow = overflow;
        fallback = cols;
      }
    }
    return fallback;
  }

  Widget _buildMultiSelectionView(BuildContext context) {
    final paths = widget.multiSelectedPaths;
    final count = paths.length;
    const double gridPad = 6;
    const double gap = 4;
    const double bannerH = 28;
    const double aspect = 1.0;

    return Container(
      margin: const EdgeInsets.only(left: 3, right: 3, top: 8, bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue.shade300, width: 2.0),
        borderRadius: BorderRadius.circular(7),
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
            height: bannerH,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.blue.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.photo_library, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  '$count images selected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Caption will apply to all selected images',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final innerW =
                    constraints.maxWidth - 2 * gridPad;
                final innerH =
                    constraints.maxHeight - 2 * gridPad;
                final cols = _crossAxisCountForFit(
                  innerW,
                  innerH,
                  count,
                  spacing: gap,
                  childAspectRatio: aspect,
                );
                final tileW =
                    (innerW - (cols - 1) * gap) / cols;
                final rows = (count / cols).ceil();
                final tileH = tileW / aspect;
                final gridMainExtent =
                    rows * tileH + (rows - 1) * gap;
                final fitsWithoutScroll =
                    gridMainExtent <= innerH + 0.5;

                final dpr = MediaQuery.devicePixelRatioOf(context);
                final cacheW =
                    math.max(64, (tileW * dpr).round());

                return GridView.builder(
                  padding: const EdgeInsets.all(gridPad),
                  physics: fitsWithoutScroll
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: aspect,
                  ),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    final imgPath = paths[index];
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.shade300, width: 0.5),
                        color: Colors.white,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  2, 2, 2, 16),
                              child: ClipRect(
                                child: OrientedFilePreview(
                                  path: imgPath,
                                  fit: BoxFit.contain,
                                  cacheWidth: cacheW,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              color: Colors.black.withOpacity(0.55),
                              child: Text(
                                p.basename(imgPath),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.multiSelectedPaths.length > 1) {
      return _buildMultiSelectionView(context);
    }

    if (widget.imagePaths.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 3, right: 3, top: 8, bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
          borderRadius: BorderRadius.circular(7),
          color: Colors.grey.shade50,
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No Images Selected',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Use "Pick Folder" to load images',
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

    final currentImagePath = widget.imagePaths[widget.currentIndex];
    final imageCount = widget.imagePaths.length;

    return Container(
      margin: const EdgeInsets.only(left: 3, right: 3, top: 8, bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
        borderRadius: BorderRadius.circular(7),
        color: widget.backgroundColor ?? Colors.white,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const double _imageVerticalPadding = 6;
          final double _mainImageHeight = constraints.maxHeight -
              (_imageVerticalPadding * 2);
          final double dpr = MediaQuery.devicePixelRatioOf(context);
          final int colorManagedMaxPx = (math.max(
                    constraints.maxWidth,
                    _mainImageHeight,
                  ) *
                  dpr)
              .round()
              .clamp(1200, 8192);
          return Column(
            children: [

              // Main image area with padding so image doesn't touch outline
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: _mainImageHeight,
                  child: Stack(
                  children: [
                    // Main image with right-click and double-click support
                    GestureDetector(
                      onSecondaryTapDown: (details) {
                        unawaited(_showContextMenu(
                            context, currentImagePath, details.globalPosition));
                      },
                      onDoubleTap: widget.onEditMetadata != null
                          ? () => widget.onEditMetadata!()
                          : null,
                      child: ColorManagedFilePreview(
                        path: currentImagePath,
                        maxPixelDimension: colorManagedMaxPx,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                      ),
                    ),

                    // Zoom button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () =>
                              _showHighResZoom(context, currentImagePath),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.zoom_in,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),

                    // FTP Upload Status Overlay
                    if ((widget.uploadProgress?.containsKey(currentImagePath) ==
                                true &&
                            widget.uploadProgress![currentImagePath]! < 1.0) ||
                        widget.queuedUploads?.contains(currentImagePath) ==
                            true)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.uploadProgress
                                          ?.containsKey(currentImagePath) ==
                                      true &&
                                  widget.uploadProgress![currentImagePath]! <
                                      1.0) ...[
                                // Currently uploading
                                const Icon(Icons.rocket_launch,
                                    color: Colors.blue, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${(widget.uploadProgress![currentImagePath]! * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ] else ...[
                                // Queued
                                const Icon(Icons.schedule,
                                    color: Colors.orange, size: 16),
                                const SizedBox(width: 4),
                                const Text(
                                  'Queued',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ),
              ),

            ],
          );
        },
      ),
    );
  }

  // Show high-resolution zoom for focus checking
  void _showHighResZoom(BuildContext context, String imagePath) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Stack(
              children: [
                // High-res image with zoom/pan capabilities
                Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                      maxHeight: MediaQuery.of(context).size.height * 0.9,
                    ),
                    child: ColorManagedFilePreview(
                      path: imagePath,
                      maxPixelDimension: 4096,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                // Close button
                Positioned(
                  top: 40,
                  right: 40,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(25),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(25),
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show context menu for right-click (matches app / Keyboard Fire menu chrome).
  Future<void> _showContextMenu(
      BuildContext context, String imagePath, Offset tapPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(tapPosition, tapPosition),
      Offset.zero & overlay.size,
    );

    final entries = <PopupMenuEntry<String>>[
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
      if (widget.uploadedImages?.contains(imagePath) ?? false)
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

    final result = await showAppContextMenu<String>(
      context: context,
      position: position,
      items: entries,
    );
    if (!context.mounted || result == null) return;
    _handleContextMenuAction(result, imagePath, tapPosition);
  }

  // Handle context menu actions
  void _handleContextMenuAction(
      String action, String imagePath, Offset tapPosition) {
    switch (action) {
      case 'edit_iptc':
        // Open metadata editor for current image (already selected)
        Future.microtask(() => widget.onEditMetadata?.call());
        break;
      case 'edit_photoshop':
        // Edit in Photoshop
        widget.onEditInPhotoshop?.call(imagePath);
        break;
      case 'apply_iptc_template':
        // Apply IPTC template to this image
        widget.onApplyIptcTemplate?.call(imagePath);
        break;
      case 'open':
        // Open in Finder
        Process.run('open', ['-R', imagePath]);
        break;
      case 'rename':
        // Show rename dialog
        _showRenameDialog(context, imagePath, tapPosition);
        break;
      case 'delete':
        // Show confirmation dialog at the click position
        _showDeleteDialog(context, imagePath, tapPosition);
        break;
      case 'ftp_image':
        // FTP the image
        widget.onFtpImage?.call(imagePath);
        break;
      case 'remove_ftp':
        // Remove FTP status
        widget.onFtpImage?.call(imagePath); // This will toggle the status
        break;
      case 'copy_metadata':
        // Copy metadata from this image
        widget.onCopyMetadata?.call(imagePath);
        break;
      case 'paste_metadata':
        // Paste metadata to this image
        widget.onPasteMetadata?.call(imagePath);
        break;
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

  // Delete image
  void _deleteImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted: ${p.basename(imagePath)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Notify parent about deletion to update thumbnail grid
        widget.onImageDeleted?.call(imagePath);

        // Navigate to next image after deletion
        final currentIndex = widget.currentIndex;
        final totalImages = widget.imagePaths.length;

        if (totalImages > 1) {
          if (currentIndex < totalImages - 1) {
            // Go to next image
            widget.onImageSelected(currentIndex + 1);
          } else if (currentIndex > 0) {
            // Go to previous image if we're at the end
            widget.onImageSelected(currentIndex - 1);
          }
        }

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
