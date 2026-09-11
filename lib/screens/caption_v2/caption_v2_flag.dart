/// Feature flag for the caption V2 UI.
///
/// FloFile 2.0+ defaults to [CaptionV2Screen]. Opt out with
/// `--dart-define=CAPTION_V2=false` if you need the classic builder.
const bool kUseCaptionV2 =
    bool.fromEnvironment('CAPTION_V2', defaultValue: true);
