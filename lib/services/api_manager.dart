import 'mlb_api_service.dart'; // TeamInfo, Player
import 'nhl_api_service.dart';
import 'nba_api_service.dart';
import 'mls_api_service.dart';
import 'balldontlie_api_service.dart';
import 'preferences_service.dart';

/// Routes team and roster requests by sport. When "Use BallDontLie API (testing)" is on,
/// Baseball and Basketball use BallDontLie; Hockey always uses official NHL API.
/// Default: Baseball = MLB API, Hockey = NHL API, Basketball = ESPN API, Soccer (MLS) = ESPN usa.1.
class ApiManager {
  final MlbApiService _mlbService = MlbApiService();
  final NhlApiService _nhlService = NhlApiService();
  final NbaApiService _nbaService = NbaApiService();
  final MlsApiService _mlsService = MlsApiService();
  final BalldontlieApiService _bdlService = BalldontlieApiService();

  String _currentSport = 'baseball';
  bool? _useBallDontLieCache;

  String get currentSport => _currentSport;
  /// Display name of the API used for the current sport (e.g. "MLB API", "BallDontLie API (testing)").
  String get currentApi => _apiDisplayName();

  void setApi(String api) {
    print('API Manager: API hint $api (sport $_currentSport determines source)');
  }

  void setSport(String sport) {
    _currentSport = sport.toLowerCase();
    print('API Manager: Switched to $_currentSport mode using ${_apiDisplayName()}');
  }

  Future<void> _ensurePrefsLoaded() async {
    final prefs = await PreferencesService.getInstance();
    _useBallDontLieCache = await prefs.getUseBallDontLieApi();
  }

  bool get _useBallDontLie => _useBallDontLieCache == true;

  String _apiDisplayName() {
    if (_useBallDontLie && (_currentSport == 'baseball' || _currentSport == 'basketball')) {
      return 'BallDontLie API (testing)';
    }
    switch (_currentSport) {
      case 'baseball':
        return 'MLB API';
      case 'hockey':
        return 'NHL API';
      case 'basketball':
        return 'ESPN API';
      case 'soccer':
        return 'MLS (ESPN)';
      default:
        return 'ESPN API';
    }
  }

  /// Fetches all teams for the current sport.
  Future<List<TeamInfo>> fetchTeams() async {
    await _ensurePrefsLoaded();
    print('API Manager: Fetching $_currentSport teams from ${_apiDisplayName()}');
    try {
      if (_useBallDontLie && _currentSport == 'baseball') {
        final teams = await _bdlService.fetchAllTeams();
        return teams
            .map((t) => TeamInfo(
                  id: t.id,
                  name: t.displayName,
                  locationName: t.location,
                  venueName: t.venue,
                ))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      if (_useBallDontLie && _currentSport == 'basketball') {
        final teams = await _bdlService.fetchAllNbaTeams();
        return teams
            .map((t) => TeamInfo(
                  id: t.id,
                  name: t.displayName,
                  locationName: t.location,
                  venueName: t.venue,
                ))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      switch (_currentSport) {
        case 'baseball':
          return await _mlbService.fetchAllTeams();
        case 'hockey':
          return await _nhlService.fetchAllTeams();
        case 'basketball':
          return await _nbaService.fetchAllTeams();
        case 'soccer':
          return await _mlsService.fetchAllTeams();
        default:
          return await _nbaService.fetchAllTeams();
      }
    } catch (e) {
      print('API Manager: Error fetching teams: $e');
      rethrow;
    }
  }

  /// Fetches the roster for [teamName] in the current sport.
  Future<List<Player>> fetchTeamRoster(String teamName) async {
    await _ensurePrefsLoaded();
    print(
        'API Manager: Fetching $_currentSport roster for "$teamName" from ${_apiDisplayName()}');
    try {
      if (_useBallDontLie && _currentSport == 'baseball') {
        final team = await _bdlService.findTeamByName(teamName);
        if (team == null) throw Exception('BallDontLie MLB team not found: "$teamName"');
        final players = await _bdlService.fetchTeamActivePlayers(team.id);
        return players
            .map((p) => Player(
                  fullName: p.fullName,
                  firstName: p.firstName,
                  jerseyNumber: p.jerseyNumber,
                  displayName: p.displayName,
                ))
            .toList();
      }
      if (_useBallDontLie && _currentSport == 'basketball') {
        final players = await _bdlService.fetchNbaRosterByTeamName(teamName);
        return players
            .map((p) => Player(
                  fullName: p.fullName,
                  firstName: p.firstName,
                  jerseyNumber: p.jerseyNumber,
                  displayName: p.displayName,
                ))
            .toList();
      }
      switch (_currentSport) {
        case 'baseball':
          final team = await _mlbService.findTeamByName(teamName);
          if (team == null) throw Exception('MLB team not found: "$teamName"');
          return await _mlbService.fetchTeamRoster(team.id);
        case 'hockey':
          return await _nhlService.fetchTeamRoster(teamName);
        case 'basketball':
          return await _nbaService.fetchTeamRoster(teamName);
        case 'soccer':
          return await _mlsService.fetchTeamRoster(teamName);
        default:
          return await _nbaService.fetchTeamRoster(teamName);
      }
    } catch (e) {
      print('API Manager: Error fetching roster: $e');
      rethrow;
    }
  }

  String getApiDisplayName() => _apiDisplayName();

  bool get isConnected => true;

  /// Venue info — MLB and BallDontLie (MLB) can expose it; NHL/ESPN return null.
  Future<String?> fetchVenueForTeam(String teamName) async {
    await _ensurePrefsLoaded();
    if (_currentSport != 'baseball') return null;
    if (_useBallDontLie) return await _bdlService.fetchVenueForTeam(teamName);
    final team = await _mlbService.findTeamByName(teamName);
    return team?.venueName;
  }

  Future<String?> fetchVenueForGame(
      String homeTeam, String awayTeam, DateTime gameDate) async {
    await _ensurePrefsLoaded();
    if (_currentSport != 'baseball') return null;
    if (_useBallDontLie) {
      return await _bdlService.fetchVenueForGame(homeTeam, awayTeam, gameDate);
    }
    return null;
  }

  String getConnectionStatusMessage() => 'Connected to ${_apiDisplayName()}';
}
