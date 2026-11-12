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

  /// Edit Photo chrome: 72px thumbs, teal selection ring, gold dirty dots.
  final bool editStyle;

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

  void _reveal({required bool animate}) {
    if (!_scroll.hasClients) return;
    final target =
        (widget.controller.currentIndex * MobilePhotoFilmstrip.itemExtent)
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
            final extent = editStyle
                ? 72.0
                : (h - 4).clamp(48.0, MobilePhotoFilmstrip.itemExtent);
            return SizedBox(
              height: h,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: extent + (editStyle ? 8 : 6),
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  final selected = index == current;
                  final dirty =
                      widget.editSession?.isDirty(path) ?? false;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: editStyle ? 8 : 6,
                      bottom: editStyle ? 0 : 2,
                      top: editStyle ? 0 : 2,
                    ),
                    child: GestureDetector(
                      onTap: () => widget.controller.goToIndex(index),
                      child: Opacity(
                        opacity: editStyle
                            ? (selected ? 1 : 0.7)
                            : 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(editStyle ? 8 : 6),
                            border: Border.all(
                              color: selected
                                  ? (editStyle
                                      ? FfTokens.nocturneAc
                                      : tokens.accent)
                                  : (editStyle
                                      ? Colors.transparent
                                      : tokens.divider),
                              width: selected ? 2 : (editStyle ? 2 : 1),
                            ),
                            boxShadow: editStyle && selected
                                ? const [
                                    BoxShadow(
                                      color: FfTokens.sessionOnRing,
                                      blurRadius: 0,
                                      spreadRadius: 3,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              editStyle ? 6 : 5,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                OrientedFilePreview(
                                  path: path,
                                  version: widget.controller
                                      .imageContentStamp(path),
                                  fit: BoxFit.cover,
                                  cacheWidth: 144,
                                ),
                                if (editStyle && dirty)
                                  const Positioned(
                                    right: 5,
                                    top: 5,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: FfTokens.gold,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: FfTokens.photoHeader,
                                            blurRadius: 0,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: SizedBox(width: 8, height: 8),
                                    ),
                                  ),
                              ],
                            ),
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
