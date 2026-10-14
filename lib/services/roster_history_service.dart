import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../config/tank01_config.dart';
import 'admin_service.dart';
import 'mlb_api_service.dart';
import 'preferences_service.dart';
import 'roster_firestore_service.dart';

/// One team whose saved roster for the game date is older than today's.
class OlderRosterTeam {
  const OlderRosterTeam({
    required this.teamName,
    required this.effectiveOn,
  });

  final String teamName;
  final String effectiveOn;
}

/// Result of a Firestore-only rosterDays lookup. Never calls a league API.
class SideHistory {
  const SideHistory({
    required this.useExistingPath,
    required this.players,
    required this.differsFromLatest,
    required this.teamName,
    this.effectiveOn,
  });

  /// History does not apply. The caller keeps [ApiManager.fetchTeamRoster].
  final bool useExistingPath;
  final List<Player> players;
  final bool differsFromLatest;
  final String teamName;
  final String? effectiveOn;

  static SideHistory existing(String teamName) => SideHistory(
        useExistingPath: true,
        players: const [],
        differsFromLatest: false,
        teamName: teamName,
      );
}

class RosterHistoryService {
  RosterHistoryService._();

  static const String remoteConfigKey = 'useRosterHistory';

  static final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Calendar day already on the [DateTime]. Not converted through UTC.
  static String? calendarDate(DateTime? date) {
    if (date == null) return null;
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final ymd = '$y-$m-$d';
    if (!_dateRe.hasMatch(ymd)) return null;
    if (date.year < 1990 || date.year > 2100) return null;
    return ymd;
  }

  static String formatRosterDay(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null || month < 1 || month > 12) return ymd;
    return '${_months[month - 1]} $day';
  }

  static String promptBody({
    required String gameDate,
    required List<OlderRosterTeam> teams,
  }) {
    final game = formatRosterDay(gameDate);
    final lines = teams
        .map(
          (t) =>
              'We found the ${t.teamName} roster from ${formatRosterDay(t.effectiveOn)}, which differs from today\'s roster.',
        )
        .join(' ');
    return 'This game is from $game. $lines';
  }

  /// Remote Config kill switch. Defaults to on. Does not touch Tank01.
  static Future<bool> useRosterHistory() async {
    if (Firebase.apps.isEmpty) return true;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setDefaults(const {remoteConfigKey: true});
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await rc.fetchAndActivate();
      return rc.getBool(remoteConfigKey);
    } catch (e) {
      print('Roster history: Remote Config unavailable, defaulting on: $e');
      return true;
    }
  }

  /// Same condition as the Tank01 Firestore read, without calling Tank01.
  static Future<bool> servedByTank01(String sport) async {
    if (!tank01SupportsSport(sport)) return false;
    try {
      final isAdmin = await AdminService.isCurrentUserAdmin();
      if (!isAdmin) return true;
      final prefs = await PreferencesService.getInstance();
      return !(await prefs.getUseOfficialLeagueApis());
    } catch (_) {
      return tank01SupportsSport(sport);
    }
  }

  static Future<SideHistory> loadTeam({
    required String sportId,
    required String teamName,
    required String gameDate,
    required bool liveToday,
  }) async {
    if (!RosterFirestoreService.isAvailable || !_dateRe.hasMatch(gameDate)) {
      return SideHistory.existing(teamName);
    }
    final teamId = await RosterFirestoreService.findTeamIdByDisplayName(
      sportId: sportId,
      teamName: teamName,
    );
    if (teamId == null) return SideHistory.existing(teamName);

    if (liveToday) {
      final players = await RosterFirestoreService.readTeamPlayers(
        sportId: sportId,
        teamId: teamId,
      );
      return SideHistory(
        useExistingPath: false,
        players: players,
        differsFromLatest: false,
        teamName: teamName,
      );
    }

    final col = RosterFirestoreService.teamsCollection(sportId)
        .doc(teamId)
        .collection('rosterDays');
    final datedSnap = await col
        .where('effectiveOn', isLessThanOrEqualTo: gameDate)
        .orderBy('effectiveOn', descending: true)
        .limit(1)
        .get();
    if (datedSnap.docs.isEmpty) {
      print(
        'WARNING: No rosterDays doc for team $teamId on $gameDate. Using the live roster.',
      );
      final players = await RosterFirestoreService.readTeamPlayers(
        sportId: sportId,
        teamId: teamId,
      );
      return SideHistory(
        useExistingPath: false,
        players: players,
        differsFromLatest: false,
        teamName: teamName,
      );
    }

    final newestSnap =
        await col.orderBy('effectiveOn', descending: true).limit(1).get();
    final dated = datedSnap.docs.first;
    final newestId = newestSnap.docs.isEmpty ? dated.id : newestSnap.docs.first.id;
    return SideHistory(
      useExistingPath: false,
      players: _playersFromDoc(dated.data()),
      differsFromLatest: dated.id != newestId,
      teamName: teamName,
      effectiveOn: (dated.data()['effectiveOn'] as String?) ?? dated.id,
    );
  }

  static List<Player> _playersFromDoc(Map<String, dynamic> data) {
    final raw = data['players'];
    if (raw is! List) return const [];
    final out = <Player>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final fullName = (map['fullName'] as String?)?.trim() ?? '';
      if (fullName.isEmpty) continue;
      final first = (map['firstName'] as String?)?.trim();
      final jersey = (map['jerseyNumber'] as String?)?.trim();
      final position = (map['position'] as String?)?.trim();
      final display = (map['displayName'] as String?)?.trim();
      final playerId = (map['playerId'] as String?)?.trim();
      out.add(Player(
        fullName: fullName,
        firstName: (first != null && first.isNotEmpty) ? first : fullName.split(' ').first,
        jerseyNumber: (jersey == null || jersey.isEmpty) ? null : jersey,
        displayName: (display != null && display.isNotEmpty)
            ? display
            : (jersey != null && jersey.isNotEmpty)
                ? '$fullName #$jersey'
                : fullName,
        playerId: (playerId == null || playerId.isEmpty) ? null : playerId,
        position: (position == null || position.isEmpty) ? null : position,
      ));
    }
    return out;
  }
}
