import 'dart:convert';
import 'package:http/http.dart' as http;
import 'mlb_api_service.dart'; // Player, TeamInfo

/// Major League Soccer rosters via ESPN’s public API (`soccer/usa.1`).
/// Same data shape as [NbaApiService]; no authentication. MLS-only (usa.1).
class MlsApiService {
  static const String _baseUrl = 'site.api.espn.com';
  static const String _basePath = '/apis/site/v2/sports/soccer/usa.1';
  static const Duration _timeout = Duration(seconds: 15);

  Future<List<TeamInfo>> fetchAllTeams() async {
    final url = Uri.https(_baseUrl, '$_basePath/teams', {'limit': '40'});
    final response = await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception('ESPN MLS teams request timed out');
    });

    if (response.statusCode != 200) {
      throw Exception('ESPN MLS teams fetch failed: ${response.statusCode}');
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

  Future<List<Player>> fetchTeamRoster(String teamName) async {
    final teams = await fetchAllTeams();
    final team = _findTeam(teams, teamName);
    if (team == null) {
      throw Exception('MLS team not found: "$teamName"');
    }
    return _fetchRosterById(team.id);
  }

  Future<List<Player>> _fetchRosterById(String teamId) async {
    final url = Uri.https(_baseUrl, '$_basePath/teams/$teamId/roster');
    final response = await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception('ESPN MLS roster request timed out for team $teamId');
    });

    if (response.statusCode != 200) {
      throw Exception('ESPN MLS roster fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final athletes = data['athletes'] as List<dynamic>?;
    if (athletes == null) return [];

    return athletes.map((a) {
      final map = a as Map<String, dynamic>;
      final fullName = map['fullName'] as String? ?? '';
      final jersey = map['jersey'] as String?;
      final firstName =
          (map['firstName'] as String?) ?? fullName.split(' ').first;
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

  /// Best-effort lookup for MLS head coach from ESPN team payload.
  /// Some responses do not include coaching staff fields.
  Future<String?> fetchHeadCoachByTeamName(String teamName) async {
    final teams = await fetchAllTeams();
    final team = _findTeam(teams, teamName);
    if (team == null) return null;

    try {
      final url = Uri.https(_baseUrl, '$_basePath/teams/${team.id}');
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final teamData = data['team'] as Map<String, dynamic>?;
      if (teamData == null) return null;

      final coach = teamData['coach'] ?? teamData['headCoach'];
      if (coach is Map<String, dynamic>) {
        final name = coach['fullName']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
      if (coach is String && coach.trim().isNotEmpty) return coach.trim();
    } catch (_) {}
    return null;
  }

  TeamInfo? _findTeam(List<TeamInfo> teams, String teamName) {
    final lower = teamName.trim().toLowerCase();
    for (final t in teams) {
      if (t.name.toLowerCase() == lower) return t;
    }
    for (final t in teams) {
      if (t.name.toLowerCase().contains(lower) ||
          lower.contains(t.name.toLowerCase().split(' ').last)) {
        return t;
      }
    }
    return null;
  }
}
