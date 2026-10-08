import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shows the pointing-hand cursor over clickable controls.
///
/// Material uses an arrow for buttons on desktop. This sits above the app and
/// switches to a hand when the control under the pointer accepts a tap.
/// Text, resize, grab, and other explicit cursors stay as they are.
class ClickHandCursor extends StatefulWidget {
  const ClickHandCursor({super.key, required this.child});

  final Widget child;

  @override
  State<ClickHandCursor> createState() => _ClickHandCursorState();
}

class _ClickHandCursorState extends State<ClickHandCursor> {
  MouseCursor _cursor = MouseCursor.defer;

  void _onHover(PointerHoverEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      event.position,
      event.viewId,
    );
    final next = _cursorFor(result);
    if (next != _cursor) setState(() => _cursor = next);
  }

  void _clearCursor() {
    if (_cursor != MouseCursor.defer) {
      setState(() => _cursor = MouseCursor.defer);
    }
  }

  MouseCursor _cursorFor(HitTestResult result) {
    final self = context.findRenderObject();
    var clickable = false;
    for (final entry in result.path) {
      final target = entry.target;
      if (identical(target, self)) continue;
      if (target is RenderMouseRegion) {
        final cursor = target.cursor;
        if (cursor != MouseCursor.defer && cursor != SystemMouseCursors.basic) {
          return MouseCursor.defer;
        }
      }
      if (target is RenderSemanticsGestureHandler && target.onTap != null) {
        clickable = true;
      } else if (target is RenderSemanticsAnnotations &&
          target.properties.onTap != null) {
        clickable = true;
      }
    }
    return clickable ? SystemMouseCursors.click : MouseCursor.defer;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: MouseRegion(
            cursor: _cursor,
            hitTestBehavior: HitTestBehavior.translucent,
            onHover: _onHover,
            onExit: (_) => _clearCursor(),
          ),
        ),
      ],
    );
  }
}
