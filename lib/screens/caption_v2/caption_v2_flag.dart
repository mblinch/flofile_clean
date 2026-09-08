/// Feature flag for the caption V2 UI.
///
/// Default (`flutter run`) → existing [CaptionBuilderScreen].
/// `flutter run --dart-define=CAPTION_V2=true` → [CaptionV2Screen].
const bool kUseCaptionV2 = bool.fromEnvironment('CAPTION_V2');
