import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/frame_status_dot.dart';
import 'caption_v2_photo_actions.dart';
import 'photo_column.dart';

/// Full-screen frame review pushed from the mobile header thumbnail.
class FrameReviewRoute extends StatelessWidget {
  const FrameReviewRoute({
    super.key,
    required this.controller,
    required this.onSavePrevious,
    required this.onSaveNext,
  });

  final CaptionV2Controller controller;
  final VoidCallback onSavePrevious;
  final VoidCallback onSaveNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final path = controller.currentPath;
        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: t.surface,
            foregroundColor: t.text,
            elevation: 0,
            title: Text(
              controller.currentFileName,
              style: t.monoMetaStyle.copyWith(color: t.text),
            ),
            actions: [
              IconButton(
                onPressed: controller.pickImageFolder,
                icon: const Icon(Icons.folder_open),
                tooltip: 'Open folder',
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: path == null
                    ? Center(
                        child: TextButton(
                          onPressed: controller.pickImageFolder,
                          child: Text(
                            'Open photo folder',
                            style: t.labelStyle.copyWith(color: t.accent),
                          ),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onSecondaryTapDown: (details) =>
                                showCaptionV2PhotoMenu(
                              context: context,
                              controller: controller,
                              imagePath: path,
                              position: details.globalPosition,
                            ),
                            onDoubleTap: () => showCaptionV2MetadataEditor(
                              context,
                              controller,
                              path,
                            ),
                            child: OrientedFilePreview(
                              path: path,
                              fit: BoxFit.contain,
                              cacheWidth: 1400,
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 16,
                            child: IconButton.filledTonal(
                              onPressed: () => showCaptionV2Zoom(context, path),
                              icon: const Icon(Icons.zoom_in_rounded),
                              tooltip: 'Zoom image',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    t.surface.withValues(alpha: 0.88),
                                foregroundColor: t.text,
                                side: BorderSide(color: t.divider),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PhotoSaveArrow(
                                direction: AxisDirection.left,
                                onPressed: onSavePrevious,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: PhotoSaveArrow(
                                direction: AxisDirection.right,
                                onPressed: onSaveNext,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.divider)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        FrameStatusDot(state: controller.currentFrameState),
                        const SizedBox(width: 8),
                        Text(
                          '${controller.currentIndex + 1} / ${controller.imagePaths.length}',
                          style: t.monoMetaStyle.copyWith(color: t.text),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
