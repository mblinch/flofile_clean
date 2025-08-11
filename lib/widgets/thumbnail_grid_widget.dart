import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:extended_image/extended_image.dart';

class ThumbnailGridWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final ScrollController? scrollController;
  final double? loadingProgress; // Add loading progress parameter
  final Map<String, String>? exifTimes; // Optional precomputed EXIF times

  const ThumbnailGridWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    this.scrollController,
    this.loadingProgress,
    this.exifTimes,
  });

  @override
  State<ThumbnailGridWidget> createState() => _ThumbnailGridWidgetState();
}

class _ThumbnailGridWidgetState extends State<ThumbnailGridWidget> {
  // Thumbnail size control
  double _thumbSize = 140.0; // Start at middle size (140px)
  double _thumbSpacing = 14.0;

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
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
    } catch (e) {
      return '';
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

  Future<String> _getImageTime(String imagePath) async {
    if (_exifTimeCache.containsKey(imagePath)) {
      return _exifTimeCache[imagePath]!;
    }

    try {
      final proc = await Process.run('exiftool', [
        '-j',
        '-DateTimeOriginal',
        imagePath,
      ]);

      if (proc.exitCode == 0) {
        final List data = jsonDecode(proc.stdout as String);
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

  @override
  Widget build(BuildContext context) {
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
        margin: const EdgeInsets.all(8.0),
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
        margin: const EdgeInsets.all(8.0),
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

    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Header with image count only
          Container(
            padding:
                const EdgeInsets.all(4), // Match image preview header padding
            decoration: BoxDecoration(
              color: Colors.grey.shade50, // Match image preview header color
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: SizedBox(
              height: 20, // Match image preview header height
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center, // Center the counter
                children: [
                  // Thumbnail counter
                  Text(
                    'Thumbnails (${widget.currentIndex + 1}/${widget.imagePaths.length})',
                    style: const TextStyle(
                      fontSize: 10, // Match image preview header font size
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),

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
              itemCount: widget.imagePaths.length,
              itemBuilder: (context, index) {
                final imagePath = widget.imagePaths[index];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => widget.onImageSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: index == widget.currentIndex
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade500,
                          width: index == widget.currentIndex ? 1.5 : 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
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
                            child: Text(
                              p.basename(imagePath),
                              style: const TextStyle(
                                fontSize: 8,
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
                                horizontal: 4, vertical: 2),
                            child: () {
                              final provided = widget.exifTimes?[imagePath];
                              if (provided != null && provided.isNotEmpty) {
                                return Text(
                                  provided,
                                  style: const TextStyle(
                                      fontSize: 7, color: Colors.grey),
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
                                          fontSize: 7, color: Colors.grey),
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
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SizedBox(
              height: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Minus button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        // Move to previous division (30px increments)
                        final currentStep = ((_thumbSize - 80) / 30).round();
                        final newStep = (currentStep - 1).clamp(0, 3);
                        _thumbSize = 80 + (newStep * 30);
                        _thumbSpacing = _thumbSize * 0.1;
                      });
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 10,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Slider
                  SizedBox(
                    width: 120,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 3,
                          elevation: 1,
                        ),
                        trackHeight: 4,
                        thumbColor: Colors.black,
                      ),
                      child: Slider(
                        value: _thumbSize,
                        min: 110.0,
                        max: 170.0,
                        divisions: 2,
                        activeColor: Colors.grey.shade800,
                        inactiveColor: Colors.grey.shade300,
                        onChanged: (value) {
                          setState(() {
                            _thumbSize = value;
                            _thumbSpacing = value * 0.1;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Plus button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        // Move to next division (30px increments)
                        final currentStep = ((_thumbSize - 110) / 30).round();
                        final newStep = (currentStep + 1).clamp(0, 2);
                        _thumbSize = 110 + (newStep * 30);
                        _thumbSpacing = _thumbSize * 0.1;
                      });
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 10,
                        color: Colors.grey.shade800,
                      ),
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
    const int maxSize = 170;
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
        cacheWidth: maxSize,
        // Let height scale automatically for speed
        filterQuality: FilterQuality.medium,
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
}
