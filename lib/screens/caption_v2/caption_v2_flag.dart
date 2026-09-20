/// Feature flag for the caption V2 UI.
///
/// FloFile 2.0+ defaults to [CaptionV2Screen]. Opt out with
/// `--dart-define=CAPTION_V2=false` if you need the classic builder.
const bool kUseCaptionV2 =
    bool.fromEnvironment('CAPTION_V2', defaultValue: true);

/// Force the phone/swipe layout regardless of window width.
///
/// Use with `--dart-define=CAPTION_V2_MOBILE=true` for a generic mobile
/// preview on desktop (macOS min window is wider than the mobile breakpoint).
const bool kCaptionV2MobilePreview =
    bool.fromEnvironment('CAPTION_V2_MOBILE', defaultValue: false);
