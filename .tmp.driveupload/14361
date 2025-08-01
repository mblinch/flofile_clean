import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'dart:io';

class PicturePreviewWidget extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final Function() onNextImage;
  final Function() onPreviousImage;

  const PicturePreviewWidget({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    required this.onNextImage,
    required this.onPreviousImage,
  });

  @override
  State<PicturePreviewWidget> createState() => _PicturePreviewWidgetState();
}

class _PicturePreviewWidgetState extends State<PicturePreviewWidget> {
  @override
  Widget build(BuildContext context) {
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
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.black,
      ),
      child: Column(
        children: [
          // Image counter and navigation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous button
                IconButton(
                  onPressed:
                      widget.currentIndex > 0 ? widget.onPreviousImage : null,
                  icon: Icon(
                    Icons.chevron_left,
                    color: widget.currentIndex > 0 ? Colors.white : Colors.grey,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),

                // Image counter
                Text(
                  '${widget.currentIndex + 1} / $imageCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // Next button
                IconButton(
                  onPressed: widget.currentIndex < imageCount - 1
                      ? widget.onNextImage
                      : null,
                  icon: Icon(
                    Icons.chevron_right,
                    color: widget.currentIndex < imageCount - 1
                        ? Colors.white
                        : Colors.grey,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Image preview
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
                        return Container(
                          color: Colors.grey.shade200,
                          child:
                              const Center(child: CircularProgressIndicator()),
                        );
                      case LoadState.completed:
                        return null; // Use default completed state
                      case LoadState.failed:
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child:
                                Icon(Icons.error, color: Colors.red, size: 48),
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
