import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_session_context.dart';
import '../caption_style/game_info.dart';
import '../services/current_user_service.dart';

/// Generic preview data for caption layout previews (startup and editor).
class CaptionPreviewSnapshot {
  const CaptionPreviewSnapshot({
    required this.players,
    required this.actions,
    required this.gameInfo,
    required this.hasRosterData,
  });

  final List<CaptionPreviewPlayer> players;
  final List<String> actions;
  final GameInfo gameInfo;
  final bool hasRosterData;
}

class CaptionPreviewDataService {
  CaptionPreviewDataService._();

  static const String _homeTeam = 'Los Angeles Boulevards';
  static const String _awayTeam = 'New York Avenues';
  static const String _venue = 'Los Angeles Sports Stadium';
  static const String _city = 'Los Angeles';
  static const String _region = 'California';
  static const String _regionCode = 'CA';
  static const String _country = 'United States';
  static const String _countryCode = 'USA';

  static const List<CaptionPreviewPlayer> _baseballPlayers = [
    CaptionPreviewPlayer(_homeTeam, 'CF', 'Heater Ace', 24, _awayTeam),
    CaptionPreviewPlayer(_awayTeam, 'SS', 'Clutch Buckets', 7, _homeTeam),
  ];

  static const List<CaptionPreviewPlayer> _hockeyPlayers = [
    CaptionPreviewPlayer(_homeTeam, 'RW', 'Heater Ace', 24, _awayTeam),
    CaptionPreviewPlayer(_awayTeam, 'C', 'Clutch Buckets', 7, _homeTeam),
  ];

  static const List<CaptionPreviewPlayer> _basketballPlayers = [
    CaptionPreviewPlayer(_homeTeam, 'PF', 'Heater Ace', 24, _awayTeam),
    CaptionPreviewPlayer(_awayTeam, 'SG', 'Clutch Buckets', 7, _homeTeam),
  ];

  static const List<CaptionPreviewPlayer> _soccerPlayers = [
    CaptionPreviewPlayer(_homeTeam, 'FW', 'Heater Ace', 24, _awayTeam),
    CaptionPreviewPlayer(_awayTeam, 'MF', 'Clutch Buckets', 7, _homeTeam),
  ];

  static List<CaptionPreviewPlayer> _playersForSport(String sport) {
    switch (sport) {
      case 'hockey':
        return _hockeyPlayers;
      case 'basketball':
        return _basketballPlayers;
      case 'soccer':
        return _soccerPlayers;
      case 'baseball':
      default:
        return _baseballPlayers;
    }
  }

  static String _actionForSport(String sport) {
    final phrase = CaptionFormulaRenderer.previewTimePhraseForSport(sport);
    switch (sport) {
      case 'hockey':
        return 'scores a goal against the {opp} $phrase';
      case 'basketball':
        return 'dunks against the {opp} $phrase';
      case 'soccer':
        return 'scores a goal against the {opp} $phrase';
      case 'baseball':
      default:
        return 'hits a home run against the {opp} $phrase';
    }
  }

  static CaptionPreviewSnapshot load({required String sport}) {
    final resolvedSport = sport.toLowerCase().trim().isEmpty
        ? 'baseball'
        : sport.toLowerCase().trim();

    if (CaptionSessionContext.previewPlayers.isNotEmpty &&
        CaptionSessionContext.previewActions.isNotEmpty) {
      final sessionGame = CaptionSessionContext.gameInfo;
      return CaptionPreviewSnapshot(
        players: CaptionSessionContext.previewPlayers,
        actions: CaptionSessionContext.previewActions,
        gameInfo: _withPhotographer(sessionGame ?? _mockGameInfo()),
        hasRosterData: true,
      );
    }

    return CaptionPreviewSnapshot(
      players: _playersForSport(resolvedSport),
      actions: [_actionForSport(resolvedSport)],
      gameInfo: _mockGameInfo(),
      hasRosterData: true,
    );
  }

  static GameInfo _mockGameInfo() => GameInfo(
        gameDate: DateTime.now(),
        city: _city,
        region: _region,
        regionCode: _regionCode,
        country: _country,
        countryCode: _countryCode,
        venue: _venue,
        photographerName: CurrentUserService.displayNameOrPlaceholder(),
        agencyName: '',
      );

  static GameInfo _withPhotographer(GameInfo info) => info.copyWith(
        photographerName: info.photographerName.trim().isNotEmpty
            ? info.photographerName
            : CurrentUserService.displayNameOrPlaceholder(),
      );
}
