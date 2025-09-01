import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

class ThumbnailPopupDialog extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final Set<String> uploadedImages;
  final Set<String> queuedUploads;
  final Set<String> currentlyUploading;
  final Map<String, double> uploadProgress;
  final Map<String, int> xmpRatings;
  final Map<String, String> xmpLabels;
  final Map<String, bool> xmpTagged;
  final Set<String> lockedPaths;

  const ThumbnailPopupDialog({
    super.key,
    required this.imagePaths,
    required this.currentIndex,
    required this.onImageSelected,
    required this.uploadedImages,
    required this.queuedUploads,
    required this.currentlyUploading,
    required this.uploadProgress,
    required this.xmpRatings,
    required this.xmpLabels,
    required this.xmpTagged,
    required this.lockedPaths,
  });

  @override
  State<ThumbnailPopupDialog> createState() => _ThumbnailPopupDialogState();
}

class _ThumbnailPopupDialogState extends State<ThumbnailPopupDialog> {
  late ScrollController _scrollController;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // Scroll to current image after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentImage();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentImage() {
    if (widget.imagePaths.isNotEmpty) {
      const itemHeight = 120.0; // Approximate height of each thumbnail row
      final targetOffset = (widget.currentIndex / 4) * itemHeight; // 4 columns
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_library, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(
                    'Image Thumbnails (${widget.imagePaths.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            
            // Thumbnails grid
            Expanded(
              child: GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: widget.imagePaths.length,
                itemBuilder: (context, index) {
                  final imagePath = widget.imagePaths[index];
                  final isSelected = index == widget.currentIndex;
                  final isUploaded = widget.uploadedImages.contains(imagePath);
                  final isQueued = widget.queuedUploads.contains(imagePath);
                  final isUploading = widget.currentlyUploading.contains(imagePath);
                  final progress = widget.uploadProgress[imagePath] ?? 0.0;
                  final rating = widget.xmpRatings[imagePath] ?? 0;
                  final label = widget.xmpLabels[imagePath] ?? '';
                  final isTagged = widget.xmpTagged[imagePath] ?? false;
                  final isLocked = widget.lockedPaths.contains(imagePath);

                  return MouseRegion(
                    onEnter: (_) {
                      setState(() {
                        _hoveredIndex = index;
                      });
                    },
                    onExit: (_) {
                      setState(() {
                        _hoveredIndex = null;
                      });
                    },
                    child: GestureDetector(
                      onTap: () {
                        widget.onImageSelected(index);
                        Navigator.of(context).pop();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected 
                              ? Colors.blue.shade600 
                              : _hoveredIndex == index 
                                ? Colors.blue.shade300
                                : Colors.grey.shade300,
                            width: isSelected ? 3 : _hoveredIndex == index ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade100,
                          boxShadow: _hoveredIndex == index ? [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ] : null,
                        ),
                        child: Stack(
                          children: [
                            // Thumbnail image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(imagePath),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    color: Colors.grey.shade300,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                      size: 32,
                                    ),
                                  );
                                },
                              ),
                            ),
                            
                            // Upload status indicators
                            if (isUploaded)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            
                            if (isQueued)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.schedule,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            
                            if (isUploading)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                      value: progress,
                                    ),
                                  ),
                                ),
                              ),
                            
                            // Rating indicator
                            if (rating > 0)
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade600,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$rating',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            
                            // Color label indicator
                            if (label.isNotEmpty)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: _getLabelColor(label),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                            
                            // Tagged indicator
                            if (isTagged)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.bookmark,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            
                            // Locked indicator
                            if (isLocked)
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.lock,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            
                            // Image number overlay
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            
                            // Filename overlay
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(7),
                                    bottomRight: Radius.circular(7),
                                  ),
                                ),
                                child: Text(
                                  p.basename(imagePath),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
      ),
    );
  }

  Color _getLabelColor(String label) {
    switch (label.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'yellow':
        return Colors.yellow;
      case 'purple':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      case 'pink':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }
}
