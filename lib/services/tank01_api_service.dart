import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/tank01_config.dart';
import 'mlb_api_service.dart' show Player;

/// Tank01 roster lookups via RapidAPI for MLB / NBA / NHL / WNBA.
class Tank01ApiService {
  Tank01ApiService({
    required this.league,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Convenience for baseball callers / roster compare.
  factory Tank01ApiService.mlb({http.Client? client}) =>
      Tank01ApiService(league: Tank01League.mlb, client: client);

  factory Tank01ApiService.forSport(String sport, {http.Client? client}) {
    final league = Tank01LeagueX.fromSport(sport);
    if (league == null) {
      throw ArgumentError('Tank01 does not support sport "$sport"');
    }
    return Tank01ApiService(league: league, client: client);
  }

  final Tank01League league;
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 20);

  final Map<Tank01League, List<_Tank01Team>> _teamsCacheByLeague = {};

  bool get isConfigured {
    final key = tank01RapidApiKey;
    return key != null && key.isNotEmpty;
  }

  /// Resolves a FloFile display name (e.g. "Toronto Blue Jays") to a Tank01 roster.
  Future<List<Player>> fetchRosterByTeamName(String teamName) async {
    final abv = await resolveTeamAbv(teamName);
    if (abv == null) {
      throw Exception('Tank01 ${league.label} team not found for "$teamName"');
    }
    return fetchRosterByTeamAbv(abv);
  }

  Future<String?> resolveTeamAbv(String teamName) async {
    final teams = await _getTeams();
    final q = teamName.toLowerCase().trim();
    if (q.isEmpty) return null;

    for (final t in teams) {
      final full = '${t.city} ${t.name}'.toLowerCase().trim();
      if (full == q || t.name.toLowerCase() == q || t.abv.toLowerCase() == q) {
        return t.abv;
      }
    }

    for (final t in teams) {
      final full = '${t.city} ${t.name}'.toLowerCase().trim();
      if (q.contains(t.name.toLowerCase()) ||
          full.contains(q) ||
          q.contains(full)) {
        return t.abv;
      }
    }
    return null;
  }

  Future<List<Player>> fetchRosterByTeamAbv(String teamAbv) async {
    if (!isConfigured) {
      throw StateError('Tank01 RapidAPI key is not configured');
    }
    final payload =
        await _getJson(league.rosterPath, {'teamAbv': teamAbv});
    final body = payload['body'];
    if (body is! Map<String, dynamic>) {
      throw Exception(
          'Tank01 ${league.label} roster response missing body for $teamAbv');
    }
    final roster = body['roster'];
    if (roster is! List) {
      throw Exception('Tank01 ${league.label} roster empty for $teamAbv');
    }

    final players = <Player>[];
    for (final raw in roster) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final fullName = (map['longName'] as String?)?.trim() ?? '';
      if (fullName.isEmpty) continue;
      final jersey = (map['jerseyNum'] as String?)?.trim();
      final cleanJersey =
          (jersey == null || jersey.isEmpty) ? null : jersey;
      final firstName = fullName.split(RegExp(r'\s+')).first;
      final position = (map['pos'] as String?)?.trim();
      final playerId = (map['mlbID'] ??
              map['nbaComID'] ??
              map['nhlComID'] ??
              map['playerID'])
          ?.toString();
      players.add(
        Player(
          fullName: fullName,
          firstName: firstName,
          jerseyNumber: cleanJersey,
          displayName: cleanJersey != null && cleanJersey.isNotEmpty
              ? '$fullName #$cleanJersey'
              : fullName,
          playerId: playerId,
          position: (position == null || position.isEmpty) ? null : position,
        ),
      );
    }

    players.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      if (aNum != bNum) return aNum.compareTo(bNum);
      return a.fullName.compareTo(b.fullName);
    });
    return players;
  }

  Future<List<_Tank01Team>> _getTeams() async {
    final cached = _teamsCacheByLeague[league];
    if (cached != null) return cached;
    final payload = await _getJson(league.teamsPath);
    final body = payload['body'];
    if (body is! List) {
      throw Exception(
          'Tank01 ${league.label} teams response missing body list');
    }
    final out = <_Tank01Team>[];
    for (final raw in body) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final abv = (map['teamAbv'] as String?)?.trim() ?? '';
      final name = (map['teamName'] as String?)?.trim() ?? '';
      final city = (map['teamCity'] as String?)?.trim() ?? '';
      if (abv.isEmpty || name.isEmpty) continue;
      out.add(_Tank01Team(abv: abv, name: name, city: city));
    }
    _teamsCacheByLeague[league] = out;
    return out;
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final key = tank01RapidApiKey;
    if (key == null || key.isEmpty) {
      throw StateError('Tank01 RapidAPI key is not configured');
    }
    final host = league.host;
    final uri = Uri.https(host, '/$path', query);
    final response = await _client
        .get(
          uri,
          headers: {
            'x-rapidapi-key': key,
            'x-rapidapi-host': host,
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Tank01 HTTP ${response.statusCode} for $uri');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected Tank01 JSON for $uri');
    }
    if (decoded['error'] != null &&
        (decoded['body'] == null ||
            (decoded['body'] is Map && (decoded['body'] as Map).isEmpty) ||
            (decoded['body'] is List && (decoded['body'] as List).isEmpty))) {
      throw Exception('Tank01 error: ${decoded['error']}');
    }
    return decoded;
  }
}

/// Back-compat alias for existing MLB-only call sites.
class Tank01MlbApiService extends Tank01ApiService {
  Tank01MlbApiService({http.Client? client})
      : super(league: Tank01League.mlb, client: client);
}

class _Tank01Team {
  const _Tank01Team({
    required this.abv,
    required this.name,
    required this.city,
  });

  final String abv;
  final String name;
  final String city;
}
