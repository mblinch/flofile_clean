import 'dart:convert';
import 'package:http/http.dart' as http;
import 'espn_api_service.dart';
import 'mlb_api_service.dart'; // Player, TeamInfo

/// Players plus optional head coach from one ESPN roster response.
class NbaRosterFetchResult {
  NbaRosterFetchResult({required this.players, this.headCoach});
  final List<Player> players;
  final String? headCoach;
}

/// ESPN NBA endpoints (same unofficial public JSON used by ESPN’s site; no API key).
class NbaApiService {
  static const String _baseUrl = 'site.api.espn.com';
  static const String _basePath = '/apis/site/v2/sports/basketball/nba';
  static const Duration _timeout = Duration(seconds: 15);

  /// Fetches all NBA teams from ESPN.
  Future<List<TeamInfo>> fetchAllTeams() async {
    final url = Uri.https(_baseUrl, '$_basePath/teams', {'limit': '32'});
    final response = await http.get(url).timeout(
          _timeout,
          onTimeout: () => throw Exception('ESPN NBA teams request timed out'),
        );

    if (response.statusCode != 200) {
      throw Exception('ESPN NBA teams fetch failed: ${response.statusCode}');
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

  Future<TeamInfo?> findTeamByName(String teamName) async {
    final teams = await fetchAllTeams();
    return _findTeam(teams, teamName);
  }

  Future<List<Player>> fetchTeamRoster(String teamName) async {
    final team = await findTeamByName(teamName);
    if (team == null) {
      throw Exception('NBA team not found: "$teamName"');
    }
    return fetchRosterByTeamId(team.id);
  }

  Future<List<Player>> fetchRosterByTeamId(String teamId) async {
    final r = await fetchRosterWithHeadCoachByTeamId(teamId);
    return r.players;
  }

  /// One roster request; [headCoach] comes from ESPN’s top-level `coach` array.
  Future<NbaRosterFetchResult> fetchRosterWithHeadCoachByTeamId(
      String teamId) async {
    final data = await _fetchRosterJson(teamId);
    final headCoach = EspnApiService.parseHeadCoachFromEspnRoster(data['coach']);
    final athletes = _extractEspnAthletes(data);
    final players = athletes.map((map) {
      final fullName = map['fullName'] as String? ?? '';
      final jersey = map['jersey'] as String?;
      final firstName =
          (map['firstName'] as String?) ?? fullName.split(' ').first;
      final displayName =
          jersey != null && jersey.isNotEmpty ? '$fullName #$jersey' : fullName;
      final playerId = map['id']?.toString();
      return Player(
        fullName: fullName,
        firstName: firstName,
        jerseyNumber: jersey,
        displayName: displayName,
        playerId: playerId,
      );
    }).toList();
    return NbaRosterFetchResult(players: players, headCoach: headCoach);
  }

  Future<Map<String, dynamic>> _fetchRosterJson(String teamId) async {
    final url = Uri.https(_baseUrl, '$_basePath/teams/$teamId/roster');
    final response = await http.get(url).timeout(
          _timeout,
          onTimeout: () =>
              throw Exception('ESPN NBA roster request timed out for team $teamId'),
        );

    if (response.statusCode != 200) {
      throw Exception('ESPN NBA roster fetch failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Head coach from the same roster feed as [fetchRosterWithHeadCoachByTeamId].
  Future<String?> fetchHeadCoachByTeamName(String teamName) async {
    final team = await findTeamByName(teamName);
    if (team == null) return null;
    final r = await fetchRosterWithHeadCoachByTeamId(team.id);
    return r.headCoach;
  }

  /// ESPN sometimes nests athletes under `items` per position group.
  List<Map<String, dynamic>> _extractEspnAthletes(Map<String, dynamic> data) {
    final raw = data['athletes'] as List<dynamic>?;
    if (raw == null) return [];
    final out = <Map<String, dynamic>>[];
    for (final el in raw) {
      final m = el as Map<String, dynamic>;
      final items = m['items'];
      if (items is List) {
        for (final a in items) {
          if (a is Map<String, dynamic>) out.add(a);
        }
      } else {
        out.add(m);
      }
    }
    return out;
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
