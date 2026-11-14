import 'package:flutter/material.dart';

import '../../../photo_edit/photo_edit_session.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';

/// Horizontal frame strip under the mobile photo. Edit mode covers this.
class MobilePhotoFilmstrip extends StatefulWidget {
  const MobilePhotoFilmstrip({
    super.key,
    required this.controller,
    this.editSession,
    this.editStyle = false,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession? editSession;

  /// Edit Photo chrome: slide-mount thumbs + gold dirty dots.
  final bool editStyle;

  static const double height = 76;
  static const double itemExtent = 72;
  static const double editMount = 76;

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
    widget.editSession?.addListener(_onFrame);
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
    if (oldWidget.editSession != widget.editSession) {
      oldWidget.editSession?.removeListener(_onFrame);
      widget.editSession?.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFrame);
    widget.editSession?.removeListener(_onFrame);
    _scroll.dispose();
    super.dispose();
  }

  void _onFrame() {
    final index = widget.controller.currentIndex;
    if (index != _lastIndex) {
      _lastIndex = index;
      _reveal(animate: true);
      return;
    }
    if (mounted) setState(() {});
  }

  double get _stride {
    return widget.editStyle
        ? MobilePhotoFilmstrip.editMount + 6
        : MobilePhotoFilmstrip.itemExtent + 6;
  }

  void _reveal({required bool animate}) {
    if (!_scroll.hasClients) return;
    final target = (widget.controller.currentIndex * _stride)
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
      animation: Listenable.merge([
        widget.controller,
        if (widget.editSession != null) widget.editSession!,
      ]),
      builder: (context, _) {
        final paths = widget.controller.imagePaths;
        if (paths.isEmpty) return const SizedBox.shrink();
        final current = widget.controller.currentIndex;
        final editStyle = widget.editStyle;
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MobilePhotoFilmstrip.height;
            if (editStyle) {
              return SizedBox(
                height: h,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemExtent: MobilePhotoFilmstrip.editMount + 6,
                    itemCount: paths.length,
                    itemBuilder: (context, index) {
                      final path = paths[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _EditFilmstripThumb(
                          path: path,
                          version:
                              widget.controller.imageContentStamp(path),
                          selected: index == current,
                          dirty:
                              widget.editSession?.isDirty(path) ?? false,
                          onTap: () => widget.controller.goToIndex(index),
                        ),
                      );
                    },
                  ),
                ),
              );
            }
            final gap = 6.0;
            final extent =
                (h - 4).clamp(48.0, MobilePhotoFilmstrip.itemExtent);
            return SizedBox(
              height: h,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: extent + gap,
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  final selected = index == current;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: gap,
                      bottom: 2,
                      top: 2,
                    ),
                    child: GestureDetector(
                      onTap: () => widget.controller.goToIndex(index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? tokens.accent
                                : tokens.divider,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: OrientedFilePreview(
                            path: path,
                            version: widget.controller
                                .imageContentStamp(path),
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

/// Slide-mount thumb: 76×76 sunken square, image contained at ≤60×60.
class _EditFilmstripThumb extends StatefulWidget {
  const _EditFilmstripThumb({
    required this.path,
    required this.version,
    required this.selected,
    required this.dirty,
    required this.onTap,
  });

  final String path;
  final int version;
  final bool selected;
  final bool dirty;
  final VoidCallback onTap;

  @override
  State<_EditFilmstripThumb> createState() => _EditFilmstripThumbState();
}

class _EditFilmstripThumbState extends State<_EditFilmstripThumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final hover = _hover;
    final fill = selected
        ? FfTokens.nocturneAccentSoft
        : hover
            ? FfTokens.nocturneHv
            : FfTokens.nocturneSunken;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: MobilePhotoFilmstrip.editMount,
          height: MobilePhotoFilmstrip.editMount,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? FfTokens.nocturneAc
                    : const Color(0x0FE8EEF4), // ~.06 white hairline
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: selected || hover ? 1 : 0.6,
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: OrientedFilePreview(
                        path: widget.path,
                        version: widget.version,
                        fit: BoxFit.contain,
                        cacheWidth: 120,
                      ),
                    ),
                  ),
                ),
                if (widget.dirty)
                  const Positioned(
                    right: 5,
                    top: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: FfTokens.gold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xCC101418),
                            blurRadius: 0,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: SizedBox(width: 7, height: 7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
