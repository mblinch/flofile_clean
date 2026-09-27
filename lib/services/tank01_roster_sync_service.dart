import '../config/tank01_config.dart';
import 'mlb_api_service.dart' show TeamInfo;
import 'roster_firestore_service.dart';
import 'tank01_api_service.dart';

/// Progress callback while mirroring Tank01 → `sports_tank01/...`.
typedef Tank01SyncProgress = void Function(String message);

/// Result of a full or per-sport Tank01 → Firestore sync.
class Tank01RosterSyncResult {
  const Tank01RosterSyncResult({
    required this.sportId,
    required this.teamsSynced,
    required this.playersWritten,
    required this.errors,
  });

  final String sportId;
  final int teamsSynced;
  final int playersWritten;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Pulls Tank01 RapidAPI rosters into Firestore at
/// `sports_tank01/{sportId}/teams/{teamAbv}/players/{playerId}` —
/// same player document fields as the league `sports/...` cache.
class Tank01RosterSyncService {
  /// FloFile sport ids Tank01 can populate.
  static const List<String> supportedSportIds = [
    'baseball',
    'basketball',
    'hockey',
    'wnba',
  ];

  /// Sync one FloFile sport (or all [supportedSportIds] when [sportId] is null).
  Future<List<Tank01RosterSyncResult>> sync({
    String? sportId,
    Tank01SyncProgress? onProgress,
  }) async {
    if (!RosterFirestoreService.isAvailable) {
      throw StateError('Firebase is not available');
    }
    final sports = sportId == null
        ? supportedSportIds
        : [sportId.toLowerCase().trim()];
    final out = <Tank01RosterSyncResult>[];
    for (final sport in sports) {
      if (!tank01SupportsSport(sport)) {
        out.add(Tank01RosterSyncResult(
          sportId: sport,
          teamsSynced: 0,
          playersWritten: 0,
          errors: ['Tank01 does not support sport "$sport"'],
        ));
        continue;
      }
      out.add(await _syncSport(sport, onProgress: onProgress));
    }
    return out;
  }

  Future<Tank01RosterSyncResult> _syncSport(
    String sportId, {
    Tank01SyncProgress? onProgress,
  }) async {
    final api = Tank01ApiService.forSport(sportId);
    if (!api.isConfigured) {
      return Tank01RosterSyncResult(
        sportId: sportId,
        teamsSynced: 0,
        playersWritten: 0,
        errors: ['Tank01 RapidAPI key is not configured'],
      );
    }

      onProgress?.call('Fetching Tank01 $sportId teams…');
    final List<TeamInfo> teams;
    try {
      teams = await api.fetchTeams();
    } catch (e) {
      return Tank01RosterSyncResult(
        sportId: sportId,
        teamsSynced: 0,
        playersWritten: 0,
        errors: ['Teams fetch failed: $e'],
      );
    }

    var teamsSynced = 0;
    var playersWritten = 0;
    final errors = <String>[];

    for (var i = 0; i < teams.length; i++) {
      final team = teams[i];
      onProgress?.call(
        'Tank01 $sportId ${i + 1}/${teams.length}: ${team.name}…',
      );
      try {
        final players = await api.fetchRosterByTeamAbv(team.id);
        await RosterFirestoreService.writeTeamPlayers(
          sportId: sportId,
          teamId: team.id,
          players: players,
          teamDisplayName: team.name,
          rootCollection: RosterFirestoreService.tank01RootCollection,
          source: 'tank01',
        );
        teamsSynced++;
        playersWritten += players.length;
      } catch (e) {
        errors.add('${team.name} (${team.id}): $e');
      }
      // Soft rate-limit RapidAPI bursts.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    onProgress?.call(
      'Tank01 $sportId done — $teamsSynced teams, $playersWritten players'
      '${errors.isEmpty ? '' : ', ${errors.length} errors'}',
    );
    return Tank01RosterSyncResult(
      sportId: sportId,
      teamsSynced: teamsSynced,
      playersWritten: playersWritten,
      errors: errors,
    );
  }
}
