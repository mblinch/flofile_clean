import 'mlb_api_service.dart';
import 'nhl_api_service.dart';
import 'balldontlie_api_service.dart';
import 'nba_api_service.dart';

class ApiManager {
  static const String _mlbStatsApi = 'MLB Stats API';
  static const String _nhlStatsApi = 'NHL Stats API';
  static const String _balldontlieApi = 'Balldontlie.io API';
  static const String _nbaStatsApi = 'NBA Stats API';

  final MlbApiService _mlbService = MlbApiService();
  final NhlApiService _nhlService = NhlApiService();
  final BalldontlieApiService _balldontlieService = BalldontlieApiService();
  final NbaApiService _nbaService = NbaApiService();

  String _currentApi = _mlbStatsApi; // Default to MLB
  String _currentSport = 'baseball'; // Track current sport

  String get currentApi => _currentApi;
  String get currentSport => _currentSport;

  void setApi(String api) {
    _currentApi = api;
    print('API Manager: Switched to $api');
  }

  /// Sets the sport and automatically selects the appropriate API
  void setSport(String sport) {
    _currentSport = sport.toLowerCase();

    // Automatically select the appropriate API based on sport
    switch (_currentSport) {
      case 'hockey':
        _currentApi = _nhlStatsApi;
        break;
      case 'basketball':
        _currentApi = _nbaStatsApi;
        break;
      case 'baseball':
      default:
        _currentApi = _mlbStatsApi;
        break;
    }

    print('API Manager: Switched to $_currentSport mode using $_currentApi');
  }

  /// Fetches teams from the currently selected API
  Future<List<TeamInfo>> fetchTeams() async {
    print('API Manager: Fetching teams from $_currentApi');

    try {
      if (_currentApi == _nhlStatsApi) {
        return await _nhlService.fetchAllTeams();
      } else if (_currentApi == _nbaStatsApi) {
        return await _nbaService.fetchAllTeams();
      } else if (_currentApi == _balldontlieApi) {
        final fetchFn = _currentSport == 'basketball'
            ? _balldontlieService.fetchAllNbaTeams()
            : _balldontlieService.fetchAllTeams();
        final balldontlieTeams = await fetchFn;
        return balldontlieTeams
            .map((team) => TeamInfo(
                  id: team.id,
                  name: team.displayName,
                  locationName: team.location,
                  venueName: null,
                ))
            .toList();
      } else {
        return await _mlbService.fetchAllTeams();
      }
    } catch (e) {
      print('API Manager: Error fetching teams from $_currentApi: $e');
      rethrow;
    }
  }

  /// Fetches team roster from the currently selected API
  Future<List<Player>> fetchTeamRoster(String teamName) async {
    print('API Manager: Fetching roster from $_currentApi for team $teamName');

    try {
      if (_currentApi == _nhlStatsApi) {
        return await _nhlService.fetchRosterByTeamName(teamName);
      } else if (_currentApi == _nbaStatsApi) {
        return await _nbaService.fetchTeamRoster(teamName);
      } else if (_currentApi == _balldontlieApi) {
        List<BalldontliePlayer> balldontliePlayers;
        if (_currentSport == 'basketball') {
          balldontliePlayers =
              await _balldontlieService.fetchNbaRosterByTeamName(teamName);
        } else {
          final teams = await _balldontlieService.fetchAllTeams();
          final team = teams.firstWhere(
            (t) => t.displayName == teamName,
            orElse: () => throw Exception('Team "$teamName" not found'),
          );
          balldontliePlayers =
              await _balldontlieService.fetchTeamActivePlayers(team.id);
        }
        return balldontliePlayers
            .map((player) => Player(
                  fullName: player.fullName,
                  firstName: player.firstName,
                  jerseyNumber: player.jerseyNumber,
                  displayName: player.displayName,
                ))
            .toList();
      } else {
        return await _mlbService.fetchRosterByTeamName(teamName);
      }
    } catch (e) {
      print('API Manager: Error fetching roster from $_currentApi: $e');
      rethrow;
    }
  }

  /// Gets the API name for display
  String getApiDisplayName() {
    return _currentApi;
  }

  /// Gets the API connection status
  bool get isConnected {
    // For now, assume connected if API is set
    return _currentApi.isNotEmpty;
  }

  /// Fetches venue information for a team
  Future<String?> fetchVenueForTeam(String teamName) async {
    print('API Manager: Fetching venue for team $teamName from $_currentApi');

    try {
      if (_currentApi == _nhlStatsApi) {
        // For NHL API, venue info is already included in team data
        final teams = await _nhlService.fetchAllTeams();
        final team = teams.firstWhere(
          (t) => t.name == teamName,
          orElse: () => throw Exception('Team "$teamName" not found'),
        );
        return team.venueName;
      } else if (_currentApi == _nbaStatsApi) {
        return null; // NBA API service doesn't provide venue in team list
      } else if (_currentApi == _balldontlieApi) {
        return await _balldontlieService.fetchVenueForTeam(teamName);
      } else {
        // For MLB API, venue info is already included in team data
        final teams = await _mlbService.fetchAllTeams();
        final team = teams.firstWhere(
          (t) => t.name == teamName,
          orElse: () => throw Exception('Team "$teamName" not found'),
        );
        return team.venueName;
      }
    } catch (e) {
      print('API Manager: Error fetching venue from $_currentApi: $e');
      return null;
    }
  }

  /// Fetches venue information for a specific game on a specific date
  Future<String?> fetchVenueForGame(
      String homeTeam, String awayTeam, DateTime gameDate) async {
    print(
        'API Manager: Fetching venue for game $awayTeam @ $homeTeam on ${gameDate.toIso8601String().split('T')[0]} from $_currentApi');

    try {
      if (_currentApi == _nbaStatsApi) {
        return null; // Venue for game not implemented for NBA API
      } else if (_currentApi == _balldontlieApi) {
        return await _balldontlieService.fetchVenueForGame(
            homeTeam, awayTeam, gameDate);
      } else {
        // For MLB API, we'd need to implement similar logic
        // For now, fall back to team venue
        return await fetchVenueForTeam(homeTeam);
      }
    } catch (e) {
      print('API Manager: Error fetching venue for game from $_currentApi: $e');
      return null;
    }
  }

  /// Gets the connection status message
  String getConnectionStatusMessage() {
    if (_currentApi == _nhlStatsApi) {
      return 'Connected to NHL Stats API';
    } else if (_currentApi == _nbaStatsApi) {
      return 'Connected to NBA Stats API';
    } else if (_currentApi == _balldontlieApi) {
      return 'Connected to Balldontlie.io API';
    } else {
      return 'Connected to MLB Stats API';
    }
  }
}
