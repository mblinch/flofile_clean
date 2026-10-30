import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';

/// Horizontal frame strip under the mobile photo. Edit mode covers this.
class MobilePhotoFilmstrip extends StatefulWidget {
  const MobilePhotoFilmstrip({super.key, required this.controller});

  final CaptionV2Controller controller;

  static const double height = 76;
  static const double itemExtent = 72;

  @override
  State<MobilePhotoFilmstrip> createState() => _MobilePhotoFilmstripState();
}

class _MobilePhotoFilmstripState extends State<MobilePhotoFilmstrip> {
  final ScrollController _scroll = ScrollController();
  int _lastIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFrame);
    _lastIndex = widget.controller.currentIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void didUpdateWidget(covariant MobilePhotoFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onFrame);
      widget.controller.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFrame);
    _scroll.dispose();
    super.dispose();
  }

  void _onFrame() {
    final index = widget.controller.currentIndex;
    if (index == _lastIndex) return;
    _lastIndex = index;
    _reveal(animate: true);
  }

  void _reveal({required bool animate}) {
    if (!_scroll.hasClients) return;
    final target = (widget.controller.currentIndex * MobilePhotoFilmstrip.itemExtent)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final paths = widget.controller.imagePaths;
        if (paths.isEmpty) return const SizedBox.shrink();
        final current = widget.controller.currentIndex;
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MobilePhotoFilmstrip.height;
            final extent = (h - 4).clamp(48.0, MobilePhotoFilmstrip.itemExtent);
            return SizedBox(
              height: h,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: extent + 6,
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  final selected = index == current;
                  return Padding(
                    padding:
                        const EdgeInsets.only(right: 6, bottom: 2, top: 2),
                    child: GestureDetector(
                      onTap: () => widget.controller.goToIndex(index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? tokens.accent : tokens.divider,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: OrientedFilePreview(
                            path: path,
                            version:
                                widget.controller.imageContentStamp(path),
                            fit: BoxFit.cover,
                            cacheWidth: 144,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
