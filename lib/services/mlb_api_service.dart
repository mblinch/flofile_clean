import 'dart:convert';
import 'package:http/http.dart' as http;

class Player {
  final String fullName;
  final String firstName;
  final String? jerseyNumber;
  final String displayName;

  Player({
    required this.fullName,
    required this.firstName,
    this.jerseyNumber,
    required this.displayName,
  });

  factory Player.fromJson(Map<String, dynamic> json, String? jerseyNumber) {
    final fullName = json['fullName'] as String;
    final firstName = fullName.split(' ').first;
    final displayName =
        jerseyNumber != null ? '$fullName #$jerseyNumber' : fullName;

    return Player(
      fullName: fullName,
      firstName: firstName,
      jerseyNumber: jerseyNumber,
      displayName: displayName,
    );
  }
}

class TeamInfo {
  final String id;
  final String name;
  final String? locationName;
  final String? venueName;

  TeamInfo({
    required this.id,
    required this.name,
    this.locationName,
    this.venueName,
  });

  factory TeamInfo.fromJson(Map<String, dynamic> json) {
    final venueInfo = json['venue'] as Map<String, dynamic>?;

    return TeamInfo(
      id: json['id'].toString(),
      name: json['name'] as String,
      locationName: json['locationName'] as String?,
      venueName: venueInfo?['name'] as String?,
    );
  }
}

class MlbApiService {
  static const String _baseUrl = 'statsapi.mlb.com';

  /// Fetches all MLB teams
  Future<List<TeamInfo>> fetchAllTeams() async {
    try {
      final url = Uri.https(_baseUrl, '/api/v1/teams', {'sportId': '1'});
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Team lookup failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final teamsData = data['teams'] as List<dynamic>;

      return teamsData.map((teamJson) => TeamInfo.fromJson(teamJson)).toList();
    } catch (e) {
      print('Error fetching teams: $e');
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
      print('Error finding team $teamName: $e');
      return null;
    }
  }

  /// Fetches active roster for a team
  Future<List<Player>> fetchTeamRoster(String teamId) async {
    try {
      final url = Uri.https(
        _baseUrl,
        '/api/v1/teams/$teamId/roster',
        {'rosterType': 'active'},
      );
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Roster fetch failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final rosterList = data['roster'] as List<dynamic>;

      return rosterList.map((playerJson) {
        final person = playerJson['person'] as Map<String, dynamic>;
        final jerseyNumber = playerJson['jerseyNumber'] as String?;
        return Player.fromJson(person, jerseyNumber);
      }).toList();
    } catch (e) {
      print('Error fetching roster for team $teamId: $e');
      rethrow;
    }
  }

  /// Fetches roster by team name (convenience method)
  Future<List<Player>> fetchRosterByTeamName(String teamName) async {
    final team = await findTeamByName(teamName);
    if (team == null) {
      throw Exception('Team "$teamName" not found');
    }
    return fetchTeamRoster(team.id);
  }

  /// Fetches key coaching/staff names for a team.
  /// Returns keys: headCoach, pitchingCoach, firstBaseCoach, thirdBaseCoach.
  Future<Map<String, String?>> fetchKeyStaffByTeamName(String teamName) async {
    final team = await findTeamByName(teamName);
    if (team == null) {
      throw Exception('Team "$teamName" not found');
    }

    final url = Uri.https(_baseUrl, '/api/v1/teams/${team.id}/coaches');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Coach fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final roster = (data['roster'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

    String? nameForJob(String job) {
      final hit = roster.firstWhere(
        (c) => (c['job']?.toString() ?? '').toLowerCase() == job.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      if (hit.isEmpty) return null;
      final person = hit['person'] as Map<String, dynamic>?;
      final name = person?['fullName']?.toString().trim();
      return (name == null || name.isEmpty) ? null : name;
    }

    final manager = nameForJob('Manager');
    return {
      'headCoach': manager,
      'pitchingCoach': nameForJob('Pitching Coach'),
      'firstBaseCoach': nameForJob('First Base Coach'),
      'thirdBaseCoach': nameForJob('Third Base Coach'),
    };
  }
}
