import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'dart:io';
import 'dart:convert';
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
      final proc = await Process.run('exiftool', [
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
        '-WhiteBalance',
        '-ColorTemperature',
        '-Tint',
        '-FocalLength',
        '-ExposureTime',
        imagePath,
      ]);

      if (proc.exitCode == 0) {
        final List data = jsonDecode(proc.stdout as String);
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
        print('DEBUG: exiftool failed for $imagePath: ${proc.stderr}');
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
      child: Row(
        children: [
          // Image preview
          Expanded(
            child: Column(
              children: [
                // Main image area
                Expanded(
                  child: Stack(
                    children: [
                      // Main image
                      ExtendedImage.file(
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
                    ],
                  ),
                ),
              ],
            ),
          ),

          // EXIF data panel on the right side
          if (_exifData != null || _isLoadingExif)
            Container(
              width: 180, // Fixed width for EXIF panel
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300, width: 1),
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Camera info
                        if (_exifData!['Make'] != null ||
                            _exifData!['Model'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${_exifData!['Make'] ?? ''} ${_exifData!['Model'] ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                        // Settings in a more compact vertical layout
                        if (_exifData!['ShutterSpeed'] != null ||
                            _exifData!['FNumber'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${_exifData!['ShutterSpeed'] != null ? _formatShutterSpeed(_exifData!['ShutterSpeed']) : ''}${_exifData!['ShutterSpeed'] != null && _exifData!['FNumber'] != null ? ' @ ' : ''}${_exifData!['FNumber'] != null ? _formatAperture(_exifData!['FNumber']) : ''}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_exifData!['ISO'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'ISO ${_exifData!['ISO']}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_exifData!['FocalLength'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              _formatFocalLength(_exifData!['FocalLength']),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),

                        // Spacer to push navigation buttons to bottom
                        const Spacer(),

                        // Filename above divider
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            p.basename(widget.imagePaths[widget.currentIndex]),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),

                        // Resolution under filename
                        if (_exifData!['ImageWidth'] != null &&
                            _exifData!['ImageHeight'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${_exifData!['ImageWidth']} × ${_exifData!['ImageHeight']}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Date/time under resolution
                        if (_exifData != null &&
                            _exifData!['DateTimeOriginal'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _formatDateTime(_exifData!['DateTimeOriginal']),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Navigation buttons at bottom of EXIF panel
                        const Padding(
                          padding: EdgeInsets.only(top: 8, bottom: 4),
                          child: Divider(height: 1, color: Colors.grey),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                fontSize: 9,
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
}
