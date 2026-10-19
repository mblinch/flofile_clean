import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_tokens.dart';

/// Colors for [showFfMenu]. [session] is the New Session screen.
/// [of] follows the caption workspace theme.
class FfMenuColors {
  const FfMenuColors({
    required this.fill,
    required this.hover,
    required this.selected,
    required this.text,
    required this.border,
    required this.divider,
  });

  final Color fill;
  final Color hover;
  final Color selected;
  final Color text;
  final Color border;
  final Color divider;

  static const session = FfMenuColors(
    fill: FfTokens.sessionEl,
    hover: FfTokens.sessionHv,
    selected: FfTokens.sessionHv,
    text: FfTokens.sessionTx,
    border: FfTokens.sessionLn2,
    divider: FfTokens.sessionLn2,
  );

  static FfMenuColors of(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return FfMenuColors(
      fill: tokens.surface,
      hover: tokens.hover,
      selected: tokens.selected,
      text: tokens.text,
      border: tokens.inputBorder,
      divider: tokens.divider,
    );
  }
}

/// Floating menu card used by the New Session team dropdown.
class FfMenuSurface extends StatelessWidget {
  const FfMenuSurface({
    super.key,
    required this.child,
    this.maxHeight = 300,
    this.color,
    this.borderColor = FfTokens.sessionLn2,
  });

  final Widget child;
  final double maxHeight;
  final Color? color;
  final Color borderColor;

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
            border: Border.all(color: borderColor),
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
  FfMenuColors? colors,
  FfMenuPlace place = FfMenuPlace.below,
}) {
  final overlayState = Overlay.of(context);
  final overlayBox =
      overlayState.context.findRenderObject() as RenderBox?;
  if (overlayBox == null || !overlayBox.hasSize) return Future.value();

  final resolved = colors ?? FfMenuColors.of(context);
  final chrome = color == null
      ? resolved
      : FfMenuColors(
          fill: color,
          hover: resolved.hover,
          selected: resolved.selected,
          text: resolved.text,
          border: resolved.border,
          divider: resolved.divider,
        );
  final topLeft = overlayBox.globalToLocal(anchorGlobal.topLeft);
  final menuWidth = width ?? anchorGlobal.width;
  final anchor = Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    anchorGlobal.width,
    anchorGlobal.height,
  );

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
          CustomSingleChildLayout(
            delegate: _FfMenuPositionDelegate(
              anchor: anchor,
              menuWidth: menuWidth,
              place: place,
            ),
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
                color: chrome.fill,
                borderColor: chrome.border,
                child: _FfMenuBody(
                  children: [
                    for (final choice in choices)
                      if (choice.divider)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: chrome.divider,
                          ),
                        )
                      else
                        _FfMenuRow(
                          enabled: choice.enabled,
                          selected: choice.selected,
                          hoverColor: chrome.hover,
                          selectedColor: chrome.selected,
                          onTap: choice.enabled
                              ? () => close(FfMenuResult(choice.value))
                              : null,
                          trailing: choice.trailingBuilder?.call(
                            menuContext,
                            () => close(),
                          ),
                          child: DefaultTextStyle(
                            style: ffMenuTextStyle.copyWith(color: chrome.text),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            child: IconTheme(
                              data: IconThemeData(
                                size: 16,
                                color: chrome.text,
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
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Keeps the menu inside the overlay. A menu that would run past the bottom
/// shifts up; one taller than the screen pins to the top and scrolls.
class _FfMenuPositionDelegate extends SingleChildLayoutDelegate {
  const _FfMenuPositionDelegate({
    required this.anchor,
    required this.menuWidth,
    required this.place,
  });

  final Rect anchor;
  final double menuWidth;
  final FfMenuPlace place;

  static const double _pad = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = (constraints.maxWidth - _pad * 2).clamp(0.0, double.infinity);
    final maxHeight =
        (constraints.maxHeight - _pad * 2).clamp(0.0, double.infinity);
    final width = menuWidth.clamp(0.0, maxWidth);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var left = switch (place) {
      FfMenuPlace.left => anchor.left - childSize.width - 6,
      FfMenuPlace.right => anchor.right + 6,
      FfMenuPlace.below => anchor.left,
    };
    final maxLeft = size.width - _pad - childSize.width;
    if (maxLeft <= _pad) {
      left = _pad;
    } else {
      left = left.clamp(_pad, maxLeft);
    }

    final top = place == FfMenuPlace.below ? anchor.bottom + 4 : anchor.top;
    final maxTop = size.height - _pad - childSize.height;
    final y = maxTop <= _pad ? _pad : top.clamp(_pad, maxTop);
    return Offset(left, y);
  }

  @override
  bool shouldRelayout(_FfMenuPositionDelegate oldDelegate) {
    return anchor != oldDelegate.anchor ||
        menuWidth != oldDelegate.menuWidth ||
        place != oldDelegate.place;
  }
}

class _FfMenuRow extends StatefulWidget {
  const _FfMenuRow({
    required this.child,
    required this.enabled,
    required this.selected,
    required this.hoverColor,
    required this.selectedColor,
    required this.onTap,
    this.trailing,
  });

  final Widget child;
  final bool enabled;
  final bool selected;
  final Color hoverColor;
  final Color selectedColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<_FfMenuRow> createState() => _FfMenuRowState();
}

class _FfMenuRowState extends State<_FfMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.selected
        ? widget.selectedColor
        : _hovered
            ? widget.hoverColor
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
