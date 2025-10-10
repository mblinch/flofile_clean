import 'dart:convert';
import 'package:http/http.dart' as http;
import 'mlb_api_service.dart'; // Import to use shared Player and TeamInfo classes

class NhlApiService {
  static const String _baseUrl = 'api-web.nhle.com';

  // Map of team names to their tri-codes for roster lookups
  static const Map<String, String> _teamTriCodes = {
    'Anaheim Ducks': 'ANA',
    'Arizona Coyotes': 'ARI',
    'Boston Bruins': 'BOS',
    'Buffalo Sabres': 'BUF',
    'Calgary Flames': 'CGY',
    'Carolina Hurricanes': 'CAR',
    'Chicago Blackhawks': 'CHI',
    'Colorado Avalanche': 'COL',
    'Columbus Blue Jackets': 'CBJ',
    'Dallas Stars': 'DAL',
    'Detroit Red Wings': 'DET',
    'Edmonton Oilers': 'EDM',
    'Florida Panthers': 'FLA',
    'Los Angeles Kings': 'LAK',
    'Minnesota Wild': 'MIN',
    'Montreal Canadiens': 'MTL',
    'Montréal Canadiens': 'MTL',
    'Nashville Predators': 'NSH',
    'New Jersey Devils': 'NJD',
    'New York Islanders': 'NYI',
    'New York Rangers': 'NYR',
    'Ottawa Senators': 'OTT',
    'Philadelphia Flyers': 'PHI',
    'Pittsburgh Penguins': 'PIT',
    'San Jose Sharks': 'SJS',
    'Seattle Kraken': 'SEA',
    'St. Louis Blues': 'STL',
    'Tampa Bay Lightning': 'TBL',
    'Toronto Maple Leafs': 'TOR',
    'Vancouver Canucks': 'VAN',
    'Vegas Golden Knights': 'VGK',
    'Washington Capitals': 'WSH',
    'Winnipeg Jets': 'WPG',
  };

  /// Fetches all NHL teams from the standings endpoint
  Future<List<TeamInfo>> fetchAllTeams() async {
    try {
      final url = Uri.https(_baseUrl, '/v1/standings/now');
      print('NHL API: Fetching teams from $url');
      final response = await http.get(url);

      print('NHL API: Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('NHL API: Response body: ${response.body}');
        throw Exception('Team lookup failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final standingsData = data['standings'] as List<dynamic>;

      print('NHL API: Found ${standingsData.length} teams');

      // Extract unique teams from standings
      final teamsMap = <String, TeamInfo>{};
      for (var teamData in standingsData) {
        final teamName = teamData['teamName']['default'] as String;
        final teamAbbrev = teamData['teamAbbrev']['default'] as String;
        final placeName = teamData['placeName']['default'] as String;

        if (!teamsMap.containsKey(teamName)) {
          teamsMap[teamName] = TeamInfo(
            id: teamAbbrev, // Use abbreviation as ID for roster lookups
            name: teamName,
            locationName: placeName,
            venueName: null, // Not available in this endpoint
          );
        }
      }

      return teamsMap.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      print('Error fetching NHL teams: $e');
      rethrow;
    }
  }

  /// Finds a team by name (case-insensitive)
  Future<TeamInfo?> findTeamByName(String teamName) async {
    try {
      final teams = await fetchAllTeams();
      return teams.firstWhere(
        (team) => team.name.toLowerCase() == teamName.toLowerCase(),
        orElse: () => throw Exception('Team "$teamName" not found'),
      );
    } catch (e) {
      print('Error finding NHL team $teamName: $e');
      return null;
    }
  }

  /// Fetches active roster for a team using the new NHL API
  Future<List<Player>> fetchTeamRoster(String teamIdOrName) async {
    try {
      // Convert team name to tri-code if necessary
      String triCode = teamIdOrName;
      if (teamIdOrName.length > 3) {
        // It's a team name, convert to tri-code
        triCode = _teamTriCodes[teamIdOrName] ?? teamIdOrName;
      }

      final url = Uri.https(_baseUrl, '/v1/roster/$triCode/current');
      print('NHL API: Fetching roster from $url');
      final response = await http.get(url);

      print('NHL API: Roster response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('NHL API: Roster response body: ${response.body}');
        throw Exception('Roster fetch failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final List<Player> allPlayers = [];

      // Process forwards
      if (data['forwards'] != null) {
        final forwards = data['forwards'] as List<dynamic>;
        for (var playerJson in forwards) {
          allPlayers.add(_parsePlayer(playerJson));
        }
      }

      // Process defensemen
      if (data['defensemen'] != null) {
        final defensemen = data['defensemen'] as List<dynamic>;
        for (var playerJson in defensemen) {
          allPlayers.add(_parsePlayer(playerJson));
        }
      }

      // Process goalies
      if (data['goalies'] != null) {
        final goalies = data['goalies'] as List<dynamic>;
        for (var playerJson in goalies) {
          allPlayers.add(_parsePlayer(playerJson));
        }
      }

      print('NHL API: Found ${allPlayers.length} players for team $triCode');

      // Sort players by jersey number
      allPlayers.sort((a, b) {
        final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
        final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
        return aNum.compareTo(bNum);
      });

      return allPlayers;
    } catch (e) {
      print('Error fetching NHL roster for team $teamIdOrName: $e');
      rethrow;
    }
  }

  /// Helper method to parse player data from the new API format
  Player _parsePlayer(Map<String, dynamic> playerJson) {
    final firstName = playerJson['firstName']['default'] as String;
    final lastName = playerJson['lastName']['default'] as String;
    final jerseyNumber = playerJson['sweaterNumber']?.toString();
    final fullName = '$firstName $lastName';
    final displayName =
        jerseyNumber != null ? '$fullName #$jerseyNumber' : fullName;

    return Player(
      fullName: fullName,
      firstName: firstName,
      jerseyNumber: jerseyNumber,
      displayName: displayName,
    );
  }

  /// Fetches roster by team name (convenience method)
  Future<List<Player>> fetchRosterByTeamName(String teamName) async {
    // Try direct lookup with tri-code first
    final triCode = _teamTriCodes[teamName];
    if (triCode != null) {
      return fetchTeamRoster(triCode);
    }

    // Fallback to finding team info first
    final team = await findTeamByName(teamName);
    if (team == null) {
      throw Exception('Team "$teamName" not found');
    }
    return fetchTeamRoster(team.id);
  }
}
