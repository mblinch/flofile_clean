import '../config/tank01_config.dart';
import 'mlb_api_service.dart';
import 'nba_api_service.dart';
import 'nhl_api_service.dart';
import 'roster_firestore_service.dart';
import 'tank01_api_service.dart';
import 'wnba_api_service.dart';

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

/// Diff of Tank01 vs Firestore vs live league API for one team.
class RosterCompareReport {
  const RosterCompareReport({
    required this.teamName,
    required this.sportId,
    required this.tank01,
    required this.firestore,
    required this.liveApi,
    required this.onlyInTank01VsLive,
    required this.onlyInLiveVsTank01,
    required this.onlyInTank01VsFirebase,
    required this.onlyInFirebaseVsTank01,
    required this.jerseyMismatches,
  });

  final String teamName;
  final String sportId;
  final RosterCompareSourceResult tank01;
  final RosterCompareSourceResult firestore;
  final RosterCompareSourceResult liveApi;
  final List<RosterComparePlayer> onlyInTank01VsLive;
  final List<RosterComparePlayer> onlyInLiveVsTank01;
  final List<RosterComparePlayer> onlyInTank01VsFirebase;
  final List<RosterComparePlayer> onlyInFirebaseVsTank01;
  final List<String> jerseyMismatches;

  /// Back-compat aliases used by older MLB-only UI.
  RosterCompareSourceResult get mlbStats => liveApi;
  List<RosterComparePlayer> get onlyInTank01VsMlb => onlyInTank01VsLive;
  List<RosterComparePlayer> get onlyInMlbVsTank01 => onlyInLiveVsTank01;
}

class RosterCompareService {
  RosterCompareService({
    MlbApiService? mlb,
    NbaApiService? nba,
    NhlApiService? nhl,
    WnbaApiService? wnba,
  })  : _mlb = mlb ?? MlbApiService(),
        _nba = nba ?? NbaApiService(),
        _nhl = nhl ?? NhlApiService(),
        _wnba = wnba ?? WnbaApiService();

  final MlbApiService _mlb;
  final NbaApiService _nba;
  final NhlApiService _nhl;
  final WnbaApiService _wnba;

  Future<RosterCompareReport> compareTeam(
    String teamName, {
    String sportId = 'baseball',
  }) async {
    final sport = sportId.toLowerCase().trim();
    if (!tank01SupportsSport(sport)) {
      throw ArgumentError('Tank01 compare not supported for sport "$sport"');
    }

    final tank01 = await _loadTank01(teamName, sport);
    final live = await _loadLive(teamName, sport);
    final firestore = await _loadFirestore(teamName, sport);

    final t01 = tank01.players;
    final liveP = live.players;
    final fb = firestore.players;

    return RosterCompareReport(
      teamName: teamName,
      sportId: sport,
      tank01: tank01,
      firestore: firestore,
      liveApi: live,
      onlyInTank01VsLive: _onlyIn(t01, liveP),
      onlyInLiveVsTank01: _onlyIn(liveP, t01),
      onlyInTank01VsFirebase: _onlyIn(t01, fb),
      onlyInFirebaseVsTank01: _onlyIn(fb, t01),
      jerseyMismatches: _jerseyMismatches(t01, liveP, live.source),
    );
  }

  Future<RosterCompareSourceResult> _loadTank01(
    String teamName,
    String sport,
  ) async {
    try {
      final players =
          await Tank01ApiService.forSport(sport).fetchRosterByTeamName(teamName);
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

  Future<RosterCompareSourceResult> _loadLive(
    String teamName,
    String sport,
  ) async {
    String sourceLabel;
    switch (sport) {
      case 'baseball':
        sourceLabel = 'MLB Stats';
        break;
      case 'basketball':
        sourceLabel = 'ESPN NBA';
        break;
      case 'hockey':
        sourceLabel = 'NHL';
        break;
      case 'wnba':
        sourceLabel = 'ESPN WNBA';
        break;
      default:
        sourceLabel = 'Live API';
    }
    try {
      List<Player> players;
      switch (sport) {
        case 'baseball':
          players = await _mlb.fetchRosterByTeamName(teamName);
          break;
        case 'basketball':
          players = await _nba.fetchTeamRoster(teamName);
          break;
        case 'hockey':
          players = await _nhl.fetchRosterByTeamName(teamName);
          break;
        case 'wnba':
          players = await _wnba.fetchTeamRoster(teamName);
          break;
        default:
          throw StateError('Unsupported compare sport: $sport');
      }
      return RosterCompareSourceResult(
        source: sourceLabel,
        ok: true,
        players: players.map(RosterComparePlayer.fromPlayer).toList(),
      );
    } catch (e) {
      return RosterCompareSourceResult(
        source: sourceLabel,
        ok: false,
        players: const [],
        error: e.toString(),
      );
    }
  }

  Future<RosterCompareSourceResult> _loadFirestore(
    String teamName,
    String sport,
  ) async {
    if (!RosterFirestoreService.isAvailable) {
      return const RosterCompareSourceResult(
        source: 'Firebase',
        ok: false,
        players: [],
        error: 'Firebase not available',
      );
    }
    try {
      final team = await _findTeam(teamName, sport);
      if (team == null) {
        return RosterCompareSourceResult(
          source: 'Firebase',
          ok: false,
          players: const [],
          error: 'Team not found for Firebase lookup ($sport)',
        );
      }
      final players = await RosterFirestoreService.readTeamPlayers(
        sportId: sport,
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

  Future<TeamInfo?> _findTeam(String teamName, String sport) async {
    switch (sport) {
      case 'baseball':
        return _mlb.findTeamByName(teamName);
      case 'basketball':
        return _nba.findTeamByName(teamName);
      case 'hockey':
        return _nhl.findTeamByName(teamName);
      case 'wnba':
        return _wnba.findTeamByName(teamName);
      default:
        return null;
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
    List<RosterComparePlayer> live,
    String liveLabel,
  ) {
    final liveByName = {
      for (final p in live) p.normalizedName: p,
    };
    final out = <String>[];
    for (final t in tank01) {
      final m = liveByName[t.normalizedName];
      if (m == null) continue;
      final tj = (t.jerseyNumber ?? '').trim();
      final mj = (m.jerseyNumber ?? '').trim();
      if (tj.isEmpty || mj.isEmpty) continue;
      if (tj != mj) {
        out.add('${t.fullName}: Tank01 #$tj vs $liveLabel #$mj');
      }
    }
    return out;
  }
}
