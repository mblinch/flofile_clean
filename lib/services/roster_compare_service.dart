import 'mlb_api_service.dart';
import 'roster_firestore_service.dart';
import 'tank01_mlb_api_service.dart';

/// One player's identity for roster set diffs.
class RosterComparePlayer {
  const RosterComparePlayer({
    required this.fullName,
    this.jerseyNumber,
    this.position,
    this.playerId,
  });

  final String fullName;
  final String? jerseyNumber;
  final String? position;
  final String? playerId;

  String get normalizedName =>
      fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  String get label {
    final j = jerseyNumber?.trim();
    final p = position?.trim();
    final bits = <String>[fullName];
    if (j != null && j.isNotEmpty) bits.add('#$j');
    if (p != null && p.isNotEmpty) bits.add(p);
    return bits.join(' ');
  }

  factory RosterComparePlayer.fromPlayer(Player p) => RosterComparePlayer(
        fullName: p.fullName,
        jerseyNumber: p.jerseyNumber,
        position: p.position,
        playerId: p.playerId,
      );
}

class RosterCompareSourceResult {
  const RosterCompareSourceResult({
    required this.source,
    required this.ok,
    required this.players,
    this.error,
  });

  final String source;
  final bool ok;
  final List<RosterComparePlayer> players;
  final String? error;
}

/// Diff of Tank01 vs Firestore vs live MLB Stats for one team.
class RosterCompareReport {
  const RosterCompareReport({
    required this.teamName,
    required this.tank01,
    required this.firestore,
    required this.mlbStats,
    required this.onlyInTank01VsMlb,
    required this.onlyInMlbVsTank01,
    required this.onlyInTank01VsFirebase,
    required this.onlyInFirebaseVsTank01,
    required this.jerseyMismatches,
  });

  final String teamName;
  final RosterCompareSourceResult tank01;
  final RosterCompareSourceResult firestore;
  final RosterCompareSourceResult mlbStats;
  final List<RosterComparePlayer> onlyInTank01VsMlb;
  final List<RosterComparePlayer> onlyInMlbVsTank01;
  final List<RosterComparePlayer> onlyInTank01VsFirebase;
  final List<RosterComparePlayer> onlyInFirebaseVsTank01;
  final List<String> jerseyMismatches;
}

class RosterCompareService {
  RosterCompareService({
    MlbApiService? mlb,
    Tank01MlbApiService? tank01,
  })  : _mlb = mlb ?? MlbApiService(),
        _tank01 = tank01 ?? Tank01MlbApiService();

  final MlbApiService _mlb;
  final Tank01MlbApiService _tank01;

  Future<RosterCompareReport> compareTeam(String teamName) async {
    final tank01 = await _loadTank01(teamName);
    final mlb = await _loadMlb(teamName);
    final firestore = await _loadFirestore(teamName);

    final t01 = tank01.players;
    final mlbP = mlb.players;
    final fb = firestore.players;

    return RosterCompareReport(
      teamName: teamName,
      tank01: tank01,
      firestore: firestore,
      mlbStats: mlb,
      onlyInTank01VsMlb: _onlyIn(t01, mlbP),
      onlyInMlbVsTank01: _onlyIn(mlbP, t01),
      onlyInTank01VsFirebase: _onlyIn(t01, fb),
      onlyInFirebaseVsTank01: _onlyIn(fb, t01),
      jerseyMismatches: _jerseyMismatches(t01, mlbP),
    );
  }

  Future<RosterCompareSourceResult> _loadTank01(String teamName) async {
    try {
      final players = await _tank01.fetchRosterByTeamName(teamName);
      return RosterCompareSourceResult(
        source: 'Tank01',
        ok: true,
        players: players.map(RosterComparePlayer.fromPlayer).toList(),
      );
    } catch (e) {
      return RosterCompareSourceResult(
        source: 'Tank01',
        ok: false,
        players: const [],
        error: e.toString(),
      );
    }
  }

  Future<RosterCompareSourceResult> _loadMlb(String teamName) async {
    try {
      final players = await _mlb.fetchRosterByTeamName(teamName);
      return RosterCompareSourceResult(
        source: 'MLB Stats',
        ok: true,
        players: players.map(RosterComparePlayer.fromPlayer).toList(),
      );
    } catch (e) {
      return RosterCompareSourceResult(
        source: 'MLB Stats',
        ok: false,
        players: const [],
        error: e.toString(),
      );
    }
  }

  Future<RosterCompareSourceResult> _loadFirestore(String teamName) async {
    if (!RosterFirestoreService.isAvailable) {
      return const RosterCompareSourceResult(
        source: 'Firebase',
        ok: false,
        players: [],
        error: 'Firebase not available',
      );
    }
    try {
      final team = await _mlb.findTeamByName(teamName);
      if (team == null) {
        return const RosterCompareSourceResult(
          source: 'Firebase',
          ok: false,
          players: [],
          error: 'Team not found in MLB for Firebase lookup',
        );
      }
      final players = await RosterFirestoreService.readTeamPlayers(
        sportId: 'baseball',
        teamId: team.id,
      );
      return RosterCompareSourceResult(
        source: 'Firebase',
        ok: true,
        players: players.map(RosterComparePlayer.fromPlayer).toList(),
      );
    } catch (e) {
      return RosterCompareSourceResult(
        source: 'Firebase',
        ok: false,
        players: const [],
        error: e.toString(),
      );
    }
  }

  List<RosterComparePlayer> _onlyIn(
    List<RosterComparePlayer> a,
    List<RosterComparePlayer> b,
  ) {
    final bNames = b.map((p) => p.normalizedName).toSet();
    return a.where((p) => !bNames.contains(p.normalizedName)).toList();
  }

  List<String> _jerseyMismatches(
    List<RosterComparePlayer> tank01,
    List<RosterComparePlayer> mlb,
  ) {
    final mlbByName = {
      for (final p in mlb) p.normalizedName: p,
    };
    final out = <String>[];
    for (final t in tank01) {
      final m = mlbByName[t.normalizedName];
      if (m == null) continue;
      final tj = (t.jerseyNumber ?? '').trim();
      final mj = (m.jerseyNumber ?? '').trim();
      if (tj.isEmpty || mj.isEmpty) continue;
      if (tj != mj) {
        out.add('${t.fullName}: Tank01 #$tj vs MLB #$mj');
      }
    }
    return out;
  }
}
