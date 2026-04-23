import 'dart:convert';
import 'package:http/http.dart' as http;
import 'mlb_api_service.dart'; // TeamInfo, Player

/// Unified ESPN unofficial API for NBA, NHL, and MLB.
/// No API key required. Rosters updated daily by ESPN.
/// Base: site.api.espn.com/apis/site/v2/sports/{sport}/{league}/...
class EspnApiService {
  static const String _baseUrl = 'site.api.espn.com';
  static const Duration _timeout = Duration(seconds: 15);

  // ── Sport / league path segments (full path under site.api.espn.com) ───────

  static const String _pathPrefix = 'apis/site/v2/sports';
  static const Map<String, String> _sportPath = {
    'basketball': '$_pathPrefix/basketball/nba',
    'hockey': '$_pathPrefix/hockey/nhl',
    'baseball': '$_pathPrefix/baseball/mlb',
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetches all teams for [sport] (e.g. 'basketball', 'hockey', 'baseball').
  Future<List<TeamInfo>> fetchAllTeams(String sport) async {
    final path = _pathFor(sport);
    final url = Uri.https(_baseUrl, '$path/teams', {'limit': '40'});
    final response = await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception('ESPN $sport teams request timed out');
    });

    if (response.statusCode != 200) {
      throw Exception(
          'ESPN $sport teams fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sports = data['sports'] as List<dynamic>;
    final leagues =
        (sports.first as Map<String, dynamic>)['leagues'] as List<dynamic>;
    final teams =
        (leagues.first as Map<String, dynamic>)['teams'] as List<dynamic>;

    return (teams.map((t) {
      final team = t['team'] as Map<String, dynamic>;
      return TeamInfo(
        id: team['id'].toString(),
        name: team['displayName'] as String,
        locationName: team['location'] as String?,
        venueName: null,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name)));
  }

  /// Fetches the active roster for [teamName] in [sport].
  Future<List<Player>> fetchTeamRoster(String sport, String teamName) async {
    final teams = await fetchAllTeams(sport);
    final team = _findTeam(teams, teamName);
    if (team == null) {
      throw Exception('ESPN: $sport team not found for "$teamName"');
    }
    return _fetchRosterById(sport, team.id);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  String _pathFor(String sport) {
    final p = _sportPath[sport.toLowerCase()];
    if (p == null) throw Exception('Unsupported sport: $sport');
    return p;
  }

  Future<List<Player>> _fetchRosterById(String sport, String teamId) async {
    final path = _pathFor(sport);
    final url = Uri.https(_baseUrl, '$path/teams/$teamId/roster');
    final response = await http.get(url).timeout(_timeout, onTimeout: () {
      throw Exception(
          'ESPN $sport roster request timed out for team $teamId');
    });

    if (response.statusCode != 200) {
      throw Exception(
          'ESPN $sport roster fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = data['athletes'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return [];

    // ESPN groups athletes by position category for some sports.
    // Flatten either format: List<athlete> or List<{items: [athlete]}>
    final List<dynamic> athletes;
    if (raw.first is Map && (raw.first as Map).containsKey('items')) {
      athletes = [for (final group in raw) ...(group['items'] as List<dynamic>)];
    } else {
      athletes = raw;
    }

    return athletes.map((a) {
      final map = a as Map<String, dynamic>;
      final fullName = map['fullName'] as String? ?? '';
      final jersey = map['jersey'] as String?;
      final firstName =
          (map['firstName'] as String?) ?? fullName.split(' ').first;
      final displayName =
          jersey != null && jersey.isNotEmpty ? '$fullName #$jersey' : fullName;
      final playerId = map['id']?.toString();
      final posMap = map['position'] as Map<String, dynamic>?;
      final position = (posMap?['abbreviation'] as String?)?.trim();
      return Player(
        fullName: fullName,
        firstName: firstName,
        jerseyNumber: jersey,
        displayName: displayName,
        playerId: playerId,
        position: position?.isEmpty == true ? null : position,
      );
    }).toList();
  }

  /// Case-insensitive + fuzzy team name lookup.
  TeamInfo? _findTeam(List<TeamInfo> teams, String teamName) {
    final lower = teamName.trim().toLowerCase();

    // 1. Exact displayName match
    for (final t in teams) {
      if (t.name.toLowerCase() == lower) return t;
    }

    // 2. "location + nickname" built from locationName + last word of name
    for (final t in teams) {
      final loc = t.locationName?.toLowerCase() ?? '';
      if (loc.isNotEmpty && lower.startsWith(loc)) return t;
    }

    // 3. Partial — team name contains query or query contains nickname
    for (final t in teams) {
      final nameLower = t.name.toLowerCase();
      final nickname = nameLower.split(' ').last;
      if (nameLower.contains(lower) || lower.contains(nickname)) return t;
    }

    return null;
  }

  /// Head coach from ESPN roster `coach` (same shape as NBA). [sport] must be
  /// a key of [_sportPath] with roster coach data (e.g. `hockey`, `basketball`).
  Future<String?> fetchHeadCoachByTeamName(String sport, String teamName) async {
    try {
      final path = _pathFor(sport);
      final teams = await fetchAllTeams(sport);
      final team = _findTeam(teams, teamName);
      if (team == null) return null;
      final url = Uri.https(_baseUrl, '$path/teams/${team.id}/roster');
      final response = await http.get(url).timeout(
        _timeout,
        onTimeout: () =>
            throw Exception('ESPN $sport coach roster request timed out'),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return parseHeadCoachFromEspnRoster(data['coach']);
    } catch (_) {
      return null;
    }
  }

  /// Shared by NBA/NHL ESPN roster payloads (`coach` array).
  static String? parseHeadCoachFromEspnRoster(dynamic coachField) {
    if (coachField is! List || coachField.isEmpty) return null;
    final first = coachField.first;
    if (first is! Map) return null;
    final m = Map<String, dynamic>.from(first);
    final full = (m['fullName'] as String?)?.trim();
    if (full != null && full.isNotEmpty) return full;
    final fn = (m['firstName'] as String?)?.trim() ?? '';
    final ln = (m['lastName'] as String?)?.trim() ?? '';
    final combined = '$fn $ln'.trim();
    return combined.isEmpty ? null : combined;
  }
}
