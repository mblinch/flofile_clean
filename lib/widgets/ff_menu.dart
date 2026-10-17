import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_tokens.dart';

/// Floating menu card used by the New Session team dropdown.
class FfMenuSurface extends StatelessWidget {
  const FfMenuSurface({
    super.key,
    required this.child,
    this.maxHeight = 300,
    this.color,
  });

  final Widget child;
  final double maxHeight;
  final Color? color;

  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    side: BorderSide(color: FfTokens.sessionLn2),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: FfTokens.sessionMenuShadow,
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        color: color ?? FfTokens.sessionEl,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FfTokens.sessionLn2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One row in [showFfMenu]. A null [value] is a real choice, not a dismiss.
class FfMenuChoice<T> {
  const FfMenuChoice({
    required this.child,
    this.value,
    this.enabled = true,
    this.selected = false,
    this.trailingBuilder,
  }) : divider = false;

  const FfMenuChoice.divider()
      : child = const SizedBox.shrink(),
        value = null,
        enabled = false,
        selected = false,
        trailingBuilder = null,
        divider = true;

  final Widget child;
  final T? value;
  final bool enabled;
  final bool selected;
  final bool divider;
  final Widget Function(BuildContext context, VoidCallback close)?
      trailingBuilder;
}

class FfMenuResult<T> {
  const FfMenuResult(this.value);
  final T? value;
}

const ffMenuTextStyle = TextStyle(
  fontFamily: FfTokens.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: FfTokens.sessionTx,
);

/// Where a menu sits relative to [showFfMenu]'s anchor.
enum FfMenuPlace { below, left, right }

/// Opens a menu anchored under [anchorGlobal], matching the session team menu.
Future<FfMenuResult<T>?> showFfMenu<T>({
  required BuildContext context,
  required Rect anchorGlobal,
  required List<FfMenuChoice<T>> choices,
  double? width,
  double maxHeight = 300,
  bool scrollable = true,
  Color? color,
  FfMenuPlace place = FfMenuPlace.below,
}) {
  final overlayState = Overlay.of(context);
  final overlayBox =
      overlayState.context.findRenderObject() as RenderBox?;
  if (overlayBox == null || !overlayBox.hasSize) return Future.value();

  final topLeft = overlayBox.globalToLocal(anchorGlobal.topLeft);
  final overlaySize = overlayBox.size;
  final menuWidth = width ?? anchorGlobal.width;
  final spaceBelow =
      overlaySize.height - (topLeft.dy + anchorGlobal.height) - 8;
  final openUp = place == FfMenuPlace.below &&
      spaceBelow < 160 &&
      topLeft.dy > spaceBelow;
  var left = topLeft.dx;
  if (place == FfMenuPlace.left) {
    left = topLeft.dx - menuWidth - 6;
  } else if (place == FfMenuPlace.right) {
    left = topLeft.dx + anchorGlobal.width + 6;
  }
  if (left < 8) left = 8;
  if (left + menuWidth > overlaySize.width - 8) {
    left = (overlaySize.width - 8 - menuWidth).clamp(8.0, overlaySize.width);
  }
  final beside = place != FfMenuPlace.below;
  final top = openUp
      ? null
      : (beside ? topLeft.dy : topLeft.dy + anchorGlobal.height + 4);
  final bottom = openUp ? overlaySize.height - topLeft.dy + 4 : null;

  final completer = Completer<FfMenuResult<T>?>();
  late OverlayEntry entry;
  var closed = false;

  void close([FfMenuResult<T>? result]) {
    if (closed) return;
    closed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (menuContext) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => close(),
            ),
          ),
          Positioned(
            left: left,
            width: menuWidth,
            top: top,
            bottom: bottom,
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: FfMenuSurface(
                maxHeight: scrollable ? maxHeight : double.infinity,
                color: color,
                child: _FfMenuBody(
                  scrollable: scrollable,
                  children: [
                    for (final choice in choices)
                      if (choice.divider)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: FfTokens.sessionLn2,
                          ),
                        )
                      else
                        _FfMenuRow(
                          enabled: choice.enabled,
                          selected: choice.selected,
                          onTap: choice.enabled
                              ? () => close(FfMenuResult(choice.value))
                              : null,
                          trailing: choice.trailingBuilder?.call(
                            menuContext,
                            () => close(),
                          ),
                          child: DefaultTextStyle(
                            style: ffMenuTextStyle,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            child: IconTheme(
                              data: const IconThemeData(
                                size: 16,
                                color: FfTokens.sessionTx,
                              ),
                              child: choice.child,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlayState.insert(entry);
  return completer.future;
}

class _FfMenuBody extends StatelessWidget {
  const _FfMenuBody({
    required this.scrollable,
    required this.children,
  });

  final bool scrollable;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!scrollable) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(6),
      shrinkWrap: true,
      primary: false,
      children: children,
    );
  }
}

class _FfMenuRow extends StatefulWidget {
  const _FfMenuRow({
    required this.child,
    required this.enabled,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final Widget child;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<_FfMenuRow> createState() => _FfMenuRowState();
}

class _FfMenuRowState extends State<_FfMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = _hovered || widget.selected
        ? FfTokens.sessionHv
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(child: widget.child),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
