import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'dart:io';
import 'dart:convert';
import '../utils/exiftool_helper.dart';
import 'dart:async';
import 'package:path/path.dart' as p;

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
  final Function(String)? onFtpImage;
  final Function(String)? onImageDeleted;
  final Function(String, String)? onImageRenamed;
  final Set<String>? uploadedImages;
  final Set<String>? queuedUploads;
  final Set<String>? currentlyUploading;
  final Map<String, double>? uploadProgress;
  final Map<String, int>? xmpRatings;
  final Map<String, String>? xmpLabels;
  final Map<String, bool>? xmpTagged;
  final Set<String>? lockedPaths;

  final VoidCallback? onEditMetadata;

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
    this.onFtpImage,
    this.onImageDeleted,
    this.onImageRenamed,
    this.uploadedImages,
    this.queuedUploads,
    this.currentlyUploading,
    this.uploadProgress,
    this.xmpRatings,
    this.xmpLabels,
    this.xmpTagged,
    this.lockedPaths,
    this.onEditMetadata,
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
    return '${value}mm';
  }

  String _buildNaturalLanguageSettings() {
    if (_exifData == null) return '';

    List<String> parts = [];

    // Add shutter speed
    if (_exifData!['ShutterSpeed'] != null) {
      String shutter = _formatShutterSpeed(_exifData!['ShutterSpeed']);
      if (shutter.isNotEmpty) {
        parts.add('You shot this at $shutter');
      }
    }

    // Add aperture
    if (_exifData!['FNumber'] != null) {
      String aperture = _formatAperture(_exifData!['FNumber']);
      if (aperture.isNotEmpty) {
        parts.add('at $aperture');
      }
    }

    // Add focal length
    if (_exifData!['FocalLength'] != null) {
      String focal = _formatFocalLength(_exifData!['FocalLength']);
      if (focal.isNotEmpty) {
        parts.add('at $focal');
      }
    }

    // Add lens info at the end if available
    if (_exifData!['LensModel'] != null &&
        _exifData!['LensModel'].toString().isNotEmpty) {
      parts.add('using a ${_exifData!['LensModel']}');
    } else if (_exifData!['Lens'] != null &&
        _exifData!['Lens'].toString().isNotEmpty) {
      parts.add('using a ${_exifData!['Lens']}');
    } else if (_exifData!['LensID'] != null &&
        _exifData!['LensID'].toString().isNotEmpty) {
      parts.add('using a ${_exifData!['LensID']}');
    }

    if (parts.isEmpty) return '';

    // Join all parts with spaces
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
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
      margin: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Top bar: Filename, pixel size, date and time
          if (_exifData != null || _isLoadingExif)
            Container(
              height: 50, // Fixed height for top info bar
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
              ),
              child: _isLoadingExif
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      children: [
                        // Left: Filename
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                p.basename(
                                    widget.imagePaths[widget.currentIndex]),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Center: Pixel size
                        if (_exifData!['ImageWidth'] != null &&
                            _exifData!['ImageHeight'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '${_exifData!['ImageWidth']} × ${_exifData!['ImageHeight']}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                        // Right: Date and time
                        if (_exifData != null &&
                            _exifData!['DateTimeOriginal'] != null)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatDateTime(
                                      _exifData!['DateTimeOriginal']),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),

          // Main image area
          Expanded(
            child: Stack(
              children: [
                // Main image with right-click and double-click support
                GestureDetector(
                  onSecondaryTapDown: (details) {
                    _showContextMenu(
                        context, currentImagePath, details.globalPosition);
                  },
                  onDoubleTap: widget.onEditMetadata != null
                      ? () => widget.onEditMetadata!()
                      : null,
                  child: ExtendedImage.file(
                    File(currentImagePath),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    width: double.infinity,
                    height: double.infinity,
                    loadStateChanged: (ExtendedImageState state) {
                      switch (state.extendedImageLoadState) {
                        case LoadState.loading:
                          print(
                              'DEBUG: ExtendedImage loading: $currentImagePath');
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                                child: CircularProgressIndicator()),
                          );
                        case LoadState.completed:
                          print(
                              'DEBUG: ExtendedImage completed: $currentImagePath');
                          return null; // Use default completed state
                        case LoadState.failed:
                          print(
                              'DEBUG: ExtendedImage failed: $currentImagePath');
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.error,
                                  color: Colors.red, size: 48),
                            ),
                          );
                      }
                    },
                    mode: ExtendedImageMode.none, // No zoom/pan for speed
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
                      onTap: () => _showHighResZoom(context, currentImagePath),
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
                    widget.queuedUploads?.contains(currentImagePath) == true)
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

          // Bottom bar: Camera model, shutter speed, focal length, and navigation
          if (_exifData != null || _isLoadingExif)
            Container(
              height: 50, // Fixed height for bottom info bar
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
              ),
              child: _isLoadingExif
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      children: [
                        // Left: Camera model
                        if (_exifData!['Make'] != null ||
                            _exifData!['Model'] != null)
                          Expanded(
                            child: Text(
                              '${_exifData!['Make'] ?? ''} ${_exifData!['Model'] ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        // Center: Natural language camera settings
                        Expanded(
                          child: Text(
                            _buildNaturalLanguageSettings(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Right: Navigation buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Previous button
                            IconButton(
                              onPressed: widget.currentIndex > 0
                                  ? () async {
                                      // Save in background without waiting
                                      if (widget.onSaveIptcBackground != null) {
                                        try {
                                          await widget.onSaveIptcBackground!();
                                        } catch (e) {
                                          print('Background save error: $e');
                                        }
                                      }
                                      // Prefer quick navigation if provided (no extra reloads)
                                      if (widget.onQuickPreviousImage != null) {
                                        print(
                                            'DEBUG: Using quick previous navigation');
                                        widget.onQuickPreviousImage!();
                                      } else {
                                        print(
                                            'DEBUG: Using regular previous navigation');
                                        widget.onPreviousImage();
                                      }
                                    }
                                  : null,
                              icon: Icon(
                                Icons.chevron_left,
                                color: widget.currentIndex > 0
                                    ? Colors.black87
                                    : Colors.grey,
                                size: 16,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                            ),

                            // Image counter between arrows
                            Text(
                              '${widget.currentIndex + 1}/$imageCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),

                            // Next button
                            IconButton(
                              onPressed: widget.currentIndex < imageCount - 1
                                  ? () async {
                                      // Save in background without waiting
                                      if (widget.onSaveIptcBackground != null) {
                                        try {
                                          await widget.onSaveIptcBackground!();
                                        } catch (e) {
                                          print('Background save error: $e');
                                        }
                                      }
                                      // Prefer quick navigation if provided (no extra reloads)
                                      if (widget.onQuickNextImage != null) {
                                        print(
                                            'DEBUG: Using quick next navigation');
                                        widget.onQuickNextImage!();
                                      } else {
                                        print(
                                            'DEBUG: Using regular next navigation');
                                        widget.onNextImage();
                                      }
                                    }
                                  : null,
                              icon: Icon(
                                Icons.chevron_right,
                                color: widget.currentIndex < imageCount - 1
                                    ? Colors.black87
                                    : Colors.grey,
                                size: 16,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
        ],
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
                    child: ExtendedImage.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.gesture, // Enable zoom/pan
                      initGestureConfigHandler: (state) {
                        return GestureConfig(
                          minScale: 0.5,
                          maxScale: 3.0,
                          animationMinScale: 0.5,
                          animationMaxScale: 3.0,
                        );
                      },
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

  // Show context menu for right-click
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
            // Context menu
            Positioned(
              left: x,
              top: y,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: menuWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMenuItem('copy_metadata', 'Copy Metadata',
                          Icons.copy, imagePath, tapPosition),
                      _buildMenuItem('paste_metadata', 'Paste Metadata',
                          Icons.paste, imagePath, tapPosition),
                      const Divider(height: 1),
                      if (widget.uploadedImages?.contains(imagePath) ?? false)
                        _buildMenuItem('remove_ftp', 'Remove FTP Status',
                            Icons.rocket_launch, imagePath, tapPosition),
                      if (!(widget.uploadedImages?.contains(imagePath) ??
                          false))
                        _buildMenuItem('ftp_image', 'FTP Image',
                            Icons.rocket_launch, imagePath, tapPosition),
                      const Divider(height: 1),
                      _buildMenuItem('open', 'Open in Finder',
                          Icons.open_in_new, imagePath, tapPosition),
                      const Divider(height: 1),
                      _buildMenuItem('rename', 'Rename Image', Icons.edit,
                          imagePath, tapPosition),
                      const Divider(height: 1),
                      _buildMenuItem('delete', 'Delete Image', Icons.delete,
                          imagePath, tapPosition,
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

  // Build menu item widget
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

  // Handle context menu actions
  void _handleContextMenuAction(
      String action, String imagePath, Offset tapPosition) {
    switch (action) {
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
