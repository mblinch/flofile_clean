import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../caption_v2_flag.dart';
import 'mobile_design.dart';

/// Centres a fixed 390×844 phone chrome when previewing on desktop.
class MobilePhoneFrame extends StatelessWidget {
  const MobilePhoneFrame({
    super.key,
    required this.child,
    this.width = kCaptionV2MobilePreviewWidth,
    this.height = kCaptionV2MobilePreviewHeight,
    this.background = MobileDesign.bg,
  });

  final Widget child;
  final double width;
  final double height;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = width.clamp(0.0, constraints.maxWidth);
          final h = height.clamp(0.0, constraints.maxHeight);
          return Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: w,
              height: h,
              child: ClipRect(child: child),
            ),
          );
        },
      ),
    );
  }
}

/// Lets mouse click-drag drive [PageView] / horizontal scrollables on desktop.
class MobileDragScrollBehavior extends MaterialScrollBehavior {
  const MobileDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
