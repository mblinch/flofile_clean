import 'package:flutter/material.dart';

import 'oriented_file_preview.dart';

class FilmstripWidget extends StatelessWidget {
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
  final VoidCallback? onShowThumbnails;
  final VoidCallback? onEditMetadata;

  const FilmstripWidget({
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
    this.onShowThumbnails,
    this.onEditMetadata,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header with show thumbnails button
          if (onShowThumbnails != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onShowThumbnails,
                    icon: const Icon(Icons.grid_view, size: 16),
                    label: const Text('Show All Thumbnails', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
            ),
          // Thumbnails list
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                final imagePath = imagePaths[index];
                final isSelected = index == currentIndex;
                final isUploaded = uploadedImages.contains(imagePath);
                final isQueued = queuedUploads.contains(imagePath);
                final isUploading = currentlyUploading.contains(imagePath);
                final progress = uploadProgress[imagePath] ?? 0.0;
                final rating = xmpRatings[imagePath] ?? 0;
                final label = xmpLabels[imagePath] ?? '';
                final isTagged = xmpTagged[imagePath] ?? false;
                final isLocked = lockedPaths.contains(imagePath);

                return GestureDetector(
                  onTap: () => onImageSelected(index),
                  onDoubleTap: onEditMetadata != null ? () => onEditMetadata!() : null,
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Colors.blue.shade600 : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.grey.shade100,
                    ),
                    child: Stack(
                      children: [
                        // Thumbnail image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            width: 70,
                            height: 80,
                            child: OrientedFilePreview(
                              path: imagePath,
                              fit: BoxFit.cover,
                              cacheWidth: 140,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        
                        // Upload status indicators
                        if (isUploaded)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        
                        if (isQueued)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.schedule,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        
                        if (isUploading)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  value: progress,
                                ),
                              ),
                            ),
                          ),
                        
                        // Rating indicator
                        if (rating > 0)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade600,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$rating',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        
                        // Color label indicator
                        if (label.isNotEmpty)
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getLabelColor(label),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                            ),
                          ),
                        
                        // Tagged indicator
                        if (isTagged)
                          Positioned(
                            top: 2,
                            left: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.bookmark,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        
                        // Locked indicator
                        if (isLocked)
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.lock,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        
                        // Image number overlay
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
