import 'dart:convert';
import 'package:http/http.dart' as http;
import 'mlb_api_service.dart'; // Player, TeamInfo

/// ESPN unofficial NBA API (no auth required, no rate limits in practice).
/// Endpoints: site.api.espn.com/apis/site/v2/sports/basketball/nba/...
class NbaApiService {
  static const String _baseUrl =
      'site.api.espn.com';
  static const String _basePath =
      '/apis/site/v2/sports/basketball/nba';
  static const Duration _timeout = Duration(seconds: 15);

  /// Fetches all 30 NBA teams from ESPN.
  Future<List<TeamInfo>> fetchAllTeams() async {
    final url =
        Uri.https(_baseUrl, '$_basePath/teams', {'limit': '32'});
    final response =
        await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception('ESPN NBA teams request timed out');
    });

    if (response.statusCode != 200) {
      throw Exception(
          'ESPN NBA teams fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sports = data['sports'] as List<dynamic>;
    final leagues =
        (sports.first as Map<String, dynamic>)['leagues'] as List<dynamic>;
    final teams =
        (leagues.first as Map<String, dynamic>)['teams'] as List<dynamic>;

    return teams.map((t) {
      final team = t['team'] as Map<String, dynamic>;
      return TeamInfo(
        id: team['id'].toString(),
        name: team['displayName'] as String,
        locationName: team['location'] as String?,
        venueName: null,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Fetches the active roster for [teamName] by finding the team in ESPN
  /// and then calling the roster endpoint.
  Future<List<Player>> fetchTeamRoster(String teamName) async {
    final teams = await fetchAllTeams();
    final team = _findTeam(teams, teamName);
    if (team == null) {
      throw Exception('NBA team not found: "$teamName"');
    }
    return _fetchRosterById(team.id);
  }

  /// Fetches roster directly by ESPN team ID.
  Future<List<Player>> _fetchRosterById(String teamId) async {
    final url = Uri.https(_baseUrl, '$_basePath/teams/$teamId/roster');
    final response =
        await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception('ESPN NBA roster request timed out for team $teamId');
    });

    if (response.statusCode != 200) {
      throw Exception(
          'ESPN NBA roster fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final athletes = data['athletes'] as List<dynamic>?;
    if (athletes == null) return [];

    return athletes.map((a) {
      final map = a as Map<String, dynamic>;
      final fullName = map['fullName'] as String? ?? '';
      final jersey = map['jersey'] as String?;
      final firstName = (map['firstName'] as String?) ?? fullName.split(' ').first;
      final displayName =
          jersey != null && jersey.isNotEmpty ? '$fullName #$jersey' : fullName;
      return Player(
        fullName: fullName,
        firstName: firstName,
        jerseyNumber: jersey,
        displayName: displayName,
      );
    }).toList();
  }

  /// Case-insensitive + fuzzy team lookup.
  TeamInfo? _findTeam(List<TeamInfo> teams, String teamName) {
    final lower = teamName.trim().toLowerCase();
    // Exact match first
    for (final t in teams) {
      if (t.name.toLowerCase() == lower) return t;
    }
    // Partial match (e.g. "Lakers" → "Los Angeles Lakers")
    for (final t in teams) {
      if (t.name.toLowerCase().contains(lower) ||
          lower.contains(t.name.toLowerCase().split(' ').last)) {
        return t;
      }
    }
    return null;
  }
}
