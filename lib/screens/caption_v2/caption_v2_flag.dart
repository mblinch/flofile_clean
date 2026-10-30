import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Feature flag for the caption V2 UI.
///
/// FloFile 2.0+ defaults to [CaptionV2Screen]. Opt out with
/// `--dart-define=CAPTION_V2=false` if you need the classic builder.
const bool kUseCaptionV2 =
    bool.fromEnvironment('CAPTION_V2', defaultValue: true);

/// Compile-time force via `--dart-define=CAPTION_V2_MOBILE=true`.
const bool kCaptionV2MobileDefine =
    bool.fromEnvironment('CAPTION_V2_MOBILE', defaultValue: false);

/// Container width under this uses the mobile stack (when not forced).
const double kCaptionV2MobileBreakpoint = 600;

/// Admin Modes toggle — phone/swipe layout preview on desktop.
/// Listen with [ValueListenableBuilder] so the workspace rebuilds.
final ValueNotifier<bool> captionV2ForceMobilePreview = ValueNotifier(false);

/// Max width of the forced desktop phone preview.
const double kCaptionV2MobilePreviewWidth = 390;

/// Phone/swipe layout regardless of window width.
bool get kCaptionV2MobilePreview =>
    kCaptionV2MobileDefine || captionV2ForceMobilePreview.value;

/// True when the caption workspace should use the mobile arrangement.
bool useCaptionV2MobileLayout(double maxWidth) =>
    kCaptionV2MobilePreview || maxWidth < kCaptionV2MobileBreakpoint;

/// Convenience for widgets that only have [BuildContext].
bool useIsMobile(BuildContext context) =>
    useCaptionV2MobileLayout(MediaQuery.sizeOf(context).width);
