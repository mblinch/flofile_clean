import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Home stadium / arena names from official (or ESPN) league APIs,
/// keyed by common team abbreviations (Tank01 + league variants).
class LeagueVenueService {
  LeagueVenueService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 25);
  static const _ua = 'caption-writer-venue-sync/1';

  /// Returns `teamAbv → venueName` for [sportId]
  /// (`baseball` / `basketball` / `hockey` / `wnba`).
  Future<Map<String, String>> fetchVenuesByAbbrev(String sportId) async {
    switch (sportId.toLowerCase().trim()) {
      case 'baseball':
        return _mlbVenues();
      case 'hockey':
        return _nhlVenues();
      case 'basketball':
        return _espnScheduleHomeVenues('basketball/nba');
      case 'wnba':
        return _espnScheduleHomeVenues('basketball/wnba');
      default:
        return const {};
    }
  }

  /// Looks up [teamAbv] in [venues], trying common abbreviation aliases.
  static String? lookup(Map<String, String> venues, String teamAbv) {
    final key = teamAbv.trim().toUpperCase();
    if (key.isEmpty) return null;
    final direct = venues[key]?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final alt in _aliases[key] ?? const <String>[]) {
      final v = venues[alt]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static const Map<String, List<String>> _aliases = {
    // NBA Tank01 ↔ ESPN
    'GSW': ['GS'],
    'GS': ['GSW'],
    'NYK': ['NY'],
    'NY': ['NYK'],
    'SAS': ['SA'],
    'SA': ['SAS'],
    'NOP': ['NO'],
    'NO': ['NOP'],
    'UTA': ['UTAH'],
    'UTAH': ['UTA'],
    'PHO': ['PHX'],
    'PHX': ['PHO'],
    'WAS': ['WSH'],
    'WSH': ['WAS'],
    'BRO': ['BKN'],
    'BKN': ['BRO'],
    // NHL Tank01 / ESPN ↔ NHL API
    'LA': ['LAK'],
    'LAK': ['LA'],
    'SJ': ['SJS'],
    'SJS': ['SJ'],
    'TB': ['TBL'],
    'TBL': ['TB'],
    'NJ': ['NJD'],
    'NJD': ['NJ'],
  };

  Future<Map<String, String>> _mlbVenues() async {
    final data = await _getJson(
      Uri.https('statsapi.mlb.com', '/api/v1/teams', {'sportId': '1'}),
    );
    final out = <String, String>{};
    final teams = data['teams'];
    if (teams is! List) return out;
    for (final raw in teams) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final abv = (map['abbreviation'] as String?)?.trim().toUpperCase() ?? '';
      final venue = map['venue'];
      final name = venue is Map
          ? (venue['name'] as String?)?.trim() ?? ''
          : '';
      if (abv.isEmpty || name.isEmpty) continue;
      _put(out, abv, name);
    }
    return out;
  }

  Future<Map<String, String>> _nhlVenues() async {
    // Prefer NHL schedule home venues (current arena names).
    final standings = await _getJson(
      Uri.https('api-web.nhle.com', '/v1/standings/now'),
    );
    final rows = standings['standings'];
    final abvs = <String>{};
    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final abbrev = raw['teamAbbrev'];
        final code = abbrev is Map
            ? (abbrev['default'] as String?)?.trim().toUpperCase()
            : null;
        if (code != null && code.isNotEmpty) abvs.add(code);
      }
    }
    if (abvs.isEmpty) {
      abvs.addAll(const [
        'ANA', 'BOS', 'BUF', 'CAR', 'CBJ', 'CGY', 'CHI', 'COL', 'DAL', 'DET',
        'EDM', 'FLA', 'LAK', 'MIN', 'MTL', 'NJD', 'NSH', 'NYI', 'NYR', 'OTT',
        'PHI', 'PIT', 'SEA', 'SJS', 'STL', 'TBL', 'TOR', 'UTA', 'VAN', 'VGK',
        'WPG', 'WSH',
      ]);
    }

    final out = <String, String>{};
    for (final abv in abvs) {
      try {
        final data = await _getJson(
          Uri.https('api-web.nhle.com', '/v1/club-schedule-season/$abv/now'),
        );
        final counts = <String, int>{};
        final games = data['games'];
        if (games is List) {
          for (final raw in games) {
            if (raw is! Map) continue;
            final home = raw['homeTeam'];
            final homeAbv = home is Map
                ? (home['abbrev'] as String?)?.trim().toUpperCase()
                : null;
            if (homeAbv != abv) continue;
            final venue = raw['venue'];
            final name = venue is Map
                ? (venue['default'] as String?)?.trim() ?? ''
                : '';
            if (name.isEmpty) continue;
            counts[name] = (counts[name] ?? 0) + 1;
          }
        }
        if (counts.isEmpty) continue;
        final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
        _put(out, abv, best.key);
      } catch (_) {
        // Keep going — one team failure should not abort the map.
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return out;
  }

  Future<Map<String, String>> _espnScheduleHomeVenues(String leaguePath) async {
    final listing = await _getJson(
      Uri.https(
        'site.api.espn.com',
        '/apis/site/v2/sports/$leaguePath/teams',
        {'limit': '50'},
      ),
    );
    final sports = listing['sports'];
    if (sports is! List || sports.isEmpty) return {};
    final leagues = (sports.first as Map)['leagues'];
    if (leagues is! List || leagues.isEmpty) return {};
    final teams = (leagues.first as Map)['teams'];
    if (teams is! List) return {};

    final out = <String, String>{};
    for (final row in teams) {
      if (row is! Map) continue;
      final team = row['team'];
      if (team is! Map) continue;
      final tid = team['id']?.toString() ?? '';
      final abv = (team['abbreviation'] as String?)?.trim().toUpperCase() ?? '';
      if (tid.isEmpty || abv.isEmpty) continue;
      try {
        final schedule = await _getJson(
          Uri.https(
            'site.api.espn.com',
            '/apis/site/v2/sports/$leaguePath/teams/$tid/schedule',
          ),
        );
        final counts = <String, int>{};
        final events = schedule['events'];
        if (events is List) {
          for (final event in events) {
            if (event is! Map) continue;
            final comps = event['competitions'];
            if (comps is! List || comps.isEmpty) continue;
            final comp = comps.first;
            if (comp is! Map) continue;
            final venue = comp['venue'];
            final name = venue is Map
                ? (venue['fullName'] as String?)?.trim() ?? ''
                : '';
            if (name.isEmpty) continue;
            var isHome = false;
            final competitors = comp['competitors'];
            if (competitors is List) {
              for (final c in competitors) {
                if (c is! Map) continue;
                if (c['homeAway'] != 'home') continue;
                final ct = c['team'];
                if (ct is Map && ct['id']?.toString() == tid) {
                  isHome = true;
                  break;
                }
              }
            }
            if (!isHome) continue;
            counts[name] = (counts[name] ?? 0) + 1;
          }
        }
        if (counts.isNotEmpty) {
          final best =
              counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
          _put(out, abv, best.key);
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return out;
  }

  void _put(Map<String, String> out, String abv, String name) {
    out[abv] = name;
    for (final alt in _aliases[abv] ?? const <String>[]) {
      out.putIfAbsent(alt, () => name);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _client
        .get(url, headers: {'User-Agent': _ua})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Unexpected JSON for $url');
  }
}

/// Mutable copy helper when callers want to merge maps.
LinkedHashMap<String, String> copyVenueMap(Map<String, String> src) =>
    LinkedHashMap<String, String>.from(src);
