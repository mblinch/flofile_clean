import 'mlb_api_service.dart';
import 'balldontlie_api_service.dart';

class ApiManager {
  static const String _mlbStatsApi = 'MLB Stats API';
  static const String _balldontlieApi = 'Balldontlie.io API';

  final MlbApiService _mlbService = MlbApiService();
  final BalldontlieApiService _balldontlieService = BalldontlieApiService();

  String _currentApi = _mlbStatsApi; // Default to MLB

  String get currentApi => _currentApi;

  void setApi(String api) {
    _currentApi = api;
    print('API Manager: Switched to $api');
  }

  /// Fetches teams from the currently selected API
  Future<List<TeamInfo>> fetchTeams() async {
    print('API Manager: Fetching teams from $_currentApi');

    try {
      if (_currentApi == _balldontlieApi) {
        final balldontlieTeams = await _balldontlieService.fetchAllTeams();
        // Convert BalldontlieTeam to TeamInfo for compatibility
        return balldontlieTeams
            .map((team) => TeamInfo(
                  id: team.id,
                  name: team.displayName,
                  locationName: team.location,
                  venueName: null, // Will be fetched separately from games API
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
      if (_currentApi == _balldontlieApi) {
        // For balldontlie, we need to find the team ID first
        final teams = await _balldontlieService.fetchAllTeams();
        final team = teams.firstWhere(
          (t) => t.displayName == teamName,
          orElse: () => throw Exception('Team "$teamName" not found'),
        );

        final balldontliePlayers =
            await _balldontlieService.fetchTeamActivePlayers(team.id);
        // Convert BalldontliePlayer to Player for compatibility
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
      if (_currentApi == _balldontlieApi) {
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
      if (_currentApi == _balldontlieApi) {
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
    if (_currentApi == _balldontlieApi) {
      return 'Connected to Balldontlie.io API';
    } else {
      return 'Connected to MLB Stats API';
    }
  }
}
