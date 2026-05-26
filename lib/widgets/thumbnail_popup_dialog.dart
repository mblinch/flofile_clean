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
  double _popupThumbSize = 200.0;

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

  Widget _popupToolbarBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
          ),
          child: Icon(icon, size: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  void _showLargePreview(BuildContext context, String imagePath, int index) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Stack(
            children: [
              Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: OrientedFilePreview(
                            path: imagePath,
                            fit: BoxFit.contain,
                            cacheWidth: 1600,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          p.basename(imagePath),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFE6E6E6), width: 0.7),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Thumbnails (${widget.imagePaths.length})',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontVariations: const [FontVariation('wght', 500)],
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  // Thumbnail size controls
                  _popupToolbarBtn(Icons.remove, () {
                    const steps = [100.0, 150.0, 200.0, 250.0, 300.0, 400.0, 500.0];
                    final idx = steps.lastIndexWhere((s) => s < _popupThumbSize);
                    if (idx >= 0) setState(() => _popupThumbSize = steps[idx]);
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${_popupThumbSize.toInt()}px',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontVariations: const [FontVariation('wght', 500)],
                        color: Colors.grey.shade700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  _popupToolbarBtn(Icons.add, () {
                    const steps = [100.0, 150.0, 200.0, 250.0, 300.0, 400.0, 500.0];
                    final idx = steps.indexWhere((s) => s > _popupThumbSize);
                    if (idx >= 0) setState(() => _popupThumbSize = steps[idx]);
                  }),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),

            // Thumbnails grid
            Expanded(
              child: GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _popupThumbSize,
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: widget.imagePaths.length,
                itemBuilder: (context, index) {
                  final imagePath = widget.imagePaths[index];
                  final isSelected = index == widget.currentIndex;
                  final isUploaded = widget.uploadedImages.contains(imagePath);

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
                        _showLargePreview(context, imagePath, index);
                      },
                      onDoubleTap: () {
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
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF424242)
                                : _hoveredIndex == index
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500,
                            width: isSelected
                                ? 2
                                : _hoveredIndex == index
                                    ? 1.5
                                    : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: isSelected ? null : Colors.white,
                          gradient: isSelected
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.07),
                                    Colors.white,
                                  ],
                                  stops: const [0.0, 0.52],
                                )
                              : null,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Stack(
                                  fit: StackFit.expand,
                                  clipBehavior: Clip.none,
                                  children: [
                                    Opacity(
                                      opacity: isUploaded ? 0.54 : 1.0,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          width: double.infinity,
                                          height: double.infinity,
                                          decoration: const BoxDecoration(color: Colors.white),
                                          child: OrientedFilePreview(
                                            path: imagePath,
                                            fit: BoxFit.contain,
                                            cacheWidth: 320,
                                            filterQuality: FilterQuality.high,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isUploaded)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        top: 2,
                                        child: Center(
                                          child: Text(
                                            'FTP',
                                            style: TextStyle(
                                              fontSize: 60,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade600.withValues(alpha: 0.72),
                                              letterSpacing: 2.0,
                                              shadows: const [
                                                Shadow(offset: Offset(0, 0), blurRadius: 3, color: Color(0xE6FFFFFF)),
                                                Shadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x66000000)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                            const SizedBox(height: 2),
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

}
