import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/frame_status_dot.dart';
import 'caption_v2_photo_actions.dart';

Future<void> showCaptionV2ThumbnailOverview(
  BuildContext context,
  CaptionV2Controller controller,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _CaptionV2ThumbnailOverview(controller: controller),
  );
}

class _CaptionV2ThumbnailOverview extends StatefulWidget {
  const _CaptionV2ThumbnailOverview({required this.controller});

  final CaptionV2Controller controller;

  @override
  State<_CaptionV2ThumbnailOverview> createState() =>
      _CaptionV2ThumbnailOverviewState();
}

class _CaptionV2ThumbnailOverviewState
    extends State<_CaptionV2ThumbnailOverview> {
  int _columns = 4;

  int get _cacheWidth {
    switch (_columns) {
      case 2:
        return 1600;
      case 3:
        return 1100;
      case 4:
        return 800;
      case 5:
        return 640;
      case 6:
        return 520;
      case 7:
        return 450;
      default:
        return 400;
    }
  }

  String _captureTime(String path) {
    final value = widget.controller.captureByPath[path];
    if (value == null) return '';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.92,
        height: size.height * 0.86,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
          border: Border.all(color: tokens.divider),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: tokens.badgeFill,
                border: Border(bottom: BorderSide(color: tokens.divider)),
              ),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 17, color: tokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    'THUMBNAILS · ${widget.controller.imagePaths.length}',
                    style: tokens.labelStyle,
                  ),
                  const Spacer(),
                  _SizeButton(
                    icon: Icons.remove,
                    tooltip: 'Smaller thumbnails',
                    tokens: tokens,
                    onTap:
                        _columns >= 8 ? null : () => setState(() => _columns++),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '$_columns×',
                      textAlign: TextAlign.center,
                      style: tokens.monoMetaStyle,
                    ),
                  ),
                  _SizeButton(
                    icon: Icons.add,
                    tooltip: 'Larger thumbnails',
                    tokens: tokens,
                    onTap:
                        _columns <= 2 ? null : () => setState(() => _columns--),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    color: tokens.textSecondary,
                    iconSize: 18,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  final paths = widget.controller.imagePaths;
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.94,
                    ),
                    itemCount: paths.length,
                    itemBuilder: (context, index) {
                      final path = paths[index];
                      final selected = index == widget.controller.currentIndex;
                      final state = widget.controller.frameStateFor(path);
                      return GestureDetector(
                        onTap: () => widget.controller.goToIndex(index),
                        onSecondaryTapDown: (details) => showCaptionV2PhotoMenu(
                          context: context,
                          controller: widget.controller,
                          imagePath: path,
                          position: details.globalPosition,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color:
                                selected ? tokens.selectedFill : tokens.sunken,
                            borderRadius:
                                BorderRadius.circular(FfTokens.radiusTile),
                            border: Border.all(
                              color: selected ? tokens.accent : tokens.divider,
                              width: selected ? FfTokens.focusOutlineWidth : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: OrientedFilePreview(
                                        path: path,
                                        fit: BoxFit.contain,
                                        cacheWidth: _cacheWidth,
                                      ),
                                    ),
                                    Positioned(
                                      right: 5,
                                      bottom: 5,
                                      child: FrameStatusDot(
                                        state: state,
                                        size: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                p.basename(path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: tokens.monoMetaStyle.copyWith(
                                  color: tokens.text,
                                ),
                              ),
                              if (_captureTime(path).isNotEmpty)
                                Text(
                                  _captureTime(path),
                                  textAlign: TextAlign.center,
                                  style: tokens.microStyle,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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

class _SizeButton extends StatelessWidget {
  const _SizeButton({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon),
      color: tokens.textSecondary,
      disabledColor: tokens.textSecondary.withValues(alpha: 0.3),
      iconSize: 16,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
    );
  }
}
