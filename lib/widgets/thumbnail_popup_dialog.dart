import 'dart:io';

import 'package:flutter/material.dart';
import 'app_styled_dialogs.dart';
import 'package:path/path.dart' as p;
import 'oriented_file_preview.dart';

class ThumbnailPopupDialog extends StatefulWidget {
  final List<String> imagePaths;
  final int currentIndex;
  final Function(int) onImageSelected;
  final VoidCallback? onEditMetadata;
  /// Images that have had IPTC saved successfully in this session (or restored from prefs).
  final Set<String> savedImages;
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
    this.onEditMetadata,
    this.savedImages = const {},
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
  Offset? _lastSecondaryTapPosition;

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
      // Calculate approximate position based on dynamic grid layout
      // With maxCrossAxisExtent: 500, we'll have roughly 2 columns depending on screen width
      const itemHeight = 500.0; // Height of each thumbnail item
      const estimatedColumns =
          2.0; // Average columns across different screen sizes
      final targetOffset =
          (widget.currentIndex / estimatedColumns) * itemHeight;
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showContextMenu(BuildContext context, int index) {
    // Prefer using the last pointer position for accurate menu placement
    final Size screenSize = MediaQuery.of(context).size;
    final Offset anchor = _lastSecondaryTapPosition ??
        Offset(screenSize.width / 2, screenSize.height / 2);

    showAppContextMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        anchor.dx,
        anchor.dy,
        screenSize.width - anchor.dx,
        screenSize.height - anchor.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              const Icon(Icons.check, size: 16),
              const SizedBox(width: 8),
              const Text('Select Image'),
            ],
          ),
        ),
        if (widget.onEditMetadata != null)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit, size: 16),
                const SizedBox(width: 8),
                const Text('Edit IPTC'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_metadata',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              const Text('Copy Metadata'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'paste_metadata',
          child: Row(
            children: [
              const Icon(Icons.paste, size: 16),
              const SizedBox(width: 8),
              const Text('Paste Metadata'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'apply_iptc_template',
          child: Row(
            children: [
              const Icon(Icons.description, size: 16),
              const SizedBox(width: 8),
              const Text('Apply IPTC Template'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 16),
              const SizedBox(width: 8),
              const Text('Open in Finder'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              const Text('Rename Image'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: 16),
              const SizedBox(width: 8),
              const Text('Delete Image'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'select') {
        widget.onImageSelected(index);
        Navigator.of(context).pop();
      } else if (value == 'edit') {
        // Select the image first so the editor opens for the correct file
        widget.onImageSelected(index);
        Navigator.of(context).pop();
        // Call editor after dialog closes
        Future.microtask(() => widget.onEditMetadata!());
      } else if (value == 'copy_metadata') {
        // Copy metadata from this image
        // Note: This would need to be implemented in the parent widget
        Navigator.of(context).pop();
      } else if (value == 'paste_metadata') {
        // Paste metadata to this image
        // Note: This would need to be implemented in the parent widget
        Navigator.of(context).pop();
      } else if (value == 'apply_iptc_template') {
        // Apply IPTC template to this image
        // Note: This would need to be implemented in the parent widget
        Navigator.of(context).pop();
      } else if (value == 'open') {
        // Open in Finder
        Navigator.of(context).pop();
        Process.run('open', ['-R', widget.imagePaths[index]]);
      } else if (value == 'rename') {
        // Rename image
        // Note: This would need to be implemented in the parent widget
        Navigator.of(context).pop();
      } else if (value == 'delete') {
        // Delete image
        // Note: This would need to be implemented in the parent widget
        Navigator.of(context).pop();
      }
    });
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
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
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 500,
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                ),
                itemCount: widget.imagePaths.length,
                itemBuilder: (context, index) {
                  final imagePath = widget.imagePaths[index];
                  final isSelected = index == widget.currentIndex;
                  final isSaved = widget.savedImages.contains(imagePath);
                  final isUploaded = widget.uploadedImages.contains(imagePath);
                  final isQueued = widget.queuedUploads.contains(imagePath);
                  final isUploading =
                      widget.currentlyUploading.contains(imagePath);
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
                      onSecondaryTapDown: (details) {
                        _lastSecondaryTapPosition = details.globalPosition;
                      },
                      onTap: () {
                        widget.onImageSelected(index);
                        Navigator.of(context).pop();
                      },
                      onSecondaryTap: widget.onEditMetadata != null
                          ? () {
                              _showContextMenu(context, index);
                            }
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue.shade600
                                : _hoveredIndex == index
                                    ? Colors.blue.shade300
                                    : Colors.grey.shade300,
                            width: isSelected
                                ? 3
                                : _hoveredIndex == index
                                    ? 2
                                    : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade100,
                          boxShadow: _hoveredIndex == index
                              ? [
                                  BoxShadow(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Stack(
                          children: [
                            // Thumbnail image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: OrientedFilePreview(
                                path: imagePath,
                                fit: BoxFit.contain,
                                cacheWidth: 320,
                                filterQuality: FilterQuality.high,
                              ),
                            ),

                            // IPTC saved (disk icon — bottom-right)
                            if (isSaved)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Icon(
                                  Icons.save,
                                  color: Colors.green.shade700,
                                  size: 20,
                                ),
                              ),

                            // FTPd / uploaded — cloud upload icon (top-right)
                            if (isUploaded)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.cloud_upload,
                                  color: Colors.blue.shade700,
                                  size: 18,
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
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              Colors.white),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
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

                            // Color label (inset so it does not cover save icon)
                            if (label.isNotEmpty)
                              Positioned(
                                bottom: 4,
                                right: 28,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: _getLabelColor(label),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
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

                            // Right-click hint (only show if edit metadata is available)
                            if (widget.onEditMetadata != null)
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'Right-click to edit',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w500,
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
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
