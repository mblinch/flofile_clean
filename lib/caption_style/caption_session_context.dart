import 'game_info.dart';
import 'caption_formula_renderer.dart';

/// Holds the most-recently generated real caption data so the layout builder
/// dialog can preview with actual session content instead of a random sample.
///
/// Updated by [CaptionFieldsWidget] every time it produces a caption.
/// Read-only by anyone that needs a live preview (e.g. [CaptionLayoutBuilderDialog]).
class CaptionSessionContext {
  CaptionSessionContext._();

  static String? _captionBody;
  static GameInfo? _gameInfo;
  static List<CaptionPreviewPlayer> _previewPlayers = const [];
  static List<String> _previewActions = const [];

  /// The player/action text segment from the last generated caption
  /// (i.e. everything before location / date / credit).
  static String? get captionBody => _captionBody;

  /// The game info used to produce the last generated caption.
  static GameInfo? get gameInfo => _gameInfo;
  static List<CaptionPreviewPlayer> get previewPlayers => _previewPlayers;
  static List<String> get previewActions => _previewActions;

  /// Called by [CaptionFieldsWidget] after every successful caption render.
  static void update({
    required String captionBody,
    required GameInfo gameInfo,
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
  }) {
    _captionBody = captionBody.trim().isEmpty ? null : captionBody.trim();
    _gameInfo = gameInfo;
    if (previewPlayers != null) {
      _previewPlayers = List<CaptionPreviewPlayer>.from(previewPlayers);
    }
    if (previewActions != null) {
      _previewActions = List<String>.from(previewActions);
    }
  }

  static void setPreviewData({
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
  }) {
    if (previewPlayers != null) {
      _previewPlayers = List<CaptionPreviewPlayer>.from(previewPlayers);
    }
    if (previewActions != null) {
      _previewActions = List<String>.from(previewActions);
    }
  }

  static bool get hasData => _captionBody != null && _gameInfo != null;
}
