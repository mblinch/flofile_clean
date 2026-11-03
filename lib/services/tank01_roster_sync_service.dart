import '../config/tank01_config.dart';
import 'league_venue_service.dart';
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

  /// Writes league-API stadium names onto existing `sports_tank01` team docs
  /// without re-pulling Tank01 rosters.
  Future<List<Tank01RosterSyncResult>> syncVenuesOnly({
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
    final venuesApi = LeagueVenueService();
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
      onProgress?.call('Fetching league stadiums for $sport…');
      final errors = <String>[];
      Map<String, String> venues = const {};
      try {
        venues = await venuesApi.fetchVenuesByAbbrev(sport);
      } catch (e) {
        out.add(Tank01RosterSyncResult(
          sportId: sport,
          teamsSynced: 0,
          playersWritten: 0,
          errors: ['Venue fetch failed: $e'],
        ));
        continue;
      }
      final teams = await RosterFirestoreService.listTeams(
        sportId: sport,
        rootCollection: RosterFirestoreService.tank01RootCollection,
      );
      var updated = 0;
      for (final team in teams) {
        final venue = LeagueVenueService.lookup(venues, team.id);
        if (venue == null || venue.isEmpty) continue;
        if (team.venueName == venue) {
          updated++;
          continue;
        }
        try {
          await RosterFirestoreService.writeTeamVenue(
            sportId: sport,
            teamId: team.id,
            venueName: venue,
            teamDisplayName: team.name,
            rootCollection: RosterFirestoreService.tank01RootCollection,
            source: 'tank01',
          );
          updated++;
        } catch (e) {
          errors.add('${team.name} (${team.id}): $e');
        }
      }
      onProgress?.call(
        'Stadiums $sport — $updated/${teams.length} teams'
        '${errors.isEmpty ? '' : ', ${errors.length} errors'}',
      );
      out.add(Tank01RosterSyncResult(
        sportId: sport,
        teamsSynced: updated,
        playersWritten: 0,
        errors: errors,
      ));
    }
    return out;
  }

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

    onProgress?.call('Fetching league stadiums for $sportId…');
    Map<String, String> venues = const {};
    try {
      venues = await LeagueVenueService().fetchVenuesByAbbrev(sportId);
    } catch (e) {
      errors.add('Venue fetch failed: $e');
    }

    for (var i = 0; i < teams.length; i++) {
      final team = teams[i];
      onProgress?.call(
        'Tank01 $sportId ${i + 1}/${teams.length}: ${team.name}…',
      );
      try {
        final players = await api.fetchRosterByTeamAbv(team.id);
        final venue = LeagueVenueService.lookup(venues, team.id);
        await RosterFirestoreService.writeTeamPlayers(
          sportId: sportId,
          teamId: team.id,
          players: players,
          teamDisplayName: team.name,
          rootCollection: RosterFirestoreService.tank01RootCollection,
          source: 'tank01',
          venueName: venue,
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
