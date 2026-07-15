import '../config/tank01_config.dart';
import 'mlb_api_service.dart'; // TeamInfo, Player
import 'nhl_api_service.dart';
import 'nba_api_service.dart';
import 'wnba_api_service.dart';
import 'mls_api_service.dart';
import 'preferences_service.dart';
import 'roster_firestore_service.dart';
import 'tank01_api_service.dart';

/// Routes team and roster requests by sport.
/// With admin Tank01 toggle: baseball / basketball / hockey / wnba use Tank01
/// RapidAPI (skip Firestore). Soccer has no Tank01 product and always uses ESPN MLS.
class ApiManager {
  final MlbApiService _mlbService = MlbApiService();
  final NhlApiService _nhlService = NhlApiService();
  final NbaApiService _nbaService = NbaApiService();
  final WnbaApiService _wnbaService = WnbaApiService();
  final MlsApiService _mlsService = MlsApiService();

  String _currentSport = 'baseball';

  String get currentSport => _currentSport;
  /// Display name of the API used for the current sport.
  String get currentApi => _apiDisplayName();

  void setApi(String api) {
    print('API Manager: API hint $api (sport $_currentSport determines source)');
  }

  void setSport(String sport) {
    _currentSport = sport.toLowerCase();
    print('API Manager: Switched to $_currentSport mode using ${_apiDisplayName()}');
  }

  Future<bool> _useTank01Rosters() async {
    if (!tank01SupportsSport(_currentSport)) return false;
    try {
      final prefs = await PreferencesService.getInstance();
      return await prefs.getUseTank01Rosters();
    } catch (_) {
      return false;
    }
  }

  Tank01ApiService _tank01ForCurrentSport() =>
      Tank01ApiService.forSport(_currentSport);

  String _apiDisplayName({bool tank01 = false}) {
    switch (_currentSport) {
      case 'baseball':
        return tank01 ? 'Tank01 MLB (RapidAPI)' : 'MLB API';
      case 'hockey':
        return tank01 ? 'Tank01 NHL (RapidAPI)' : 'NHL API';
      case 'basketball':
        return tank01 ? 'Tank01 NBA (RapidAPI)' : 'ESPN NBA API';
      case 'wnba':
        return tank01 ? 'Tank01 WNBA (RapidAPI)' : 'ESPN WNBA API';
      case 'soccer':
        return 'MLS (ESPN)';
      default:
        return 'ESPN NBA API';
    }
  }

  /// Fetches all teams for the current sport.
  Future<List<TeamInfo>> fetchTeams() async {
    print('API Manager: Fetching $_currentSport teams from ${_apiDisplayName()}');
    try {
      switch (_currentSport) {
        case 'baseball':
          return await _mlbService.fetchAllTeams();
        case 'hockey':
          return await _nhlService.fetchAllTeams();
        case 'basketball':
          return await _nbaService.fetchAllTeams();
        case 'wnba':
          return await _wnbaService.fetchAllTeams();
        case 'soccer':
          return await _mlsService.fetchAllTeams();
        default:
          return await _nbaService.fetchAllTeams();
      }
    } catch (e) {
      print('API Manager: Error fetching teams: $e');
      rethrow;
    }
  }

  /// Fetches the roster for [teamName] in the current sport.
  Future<List<Player>> fetchTeamRoster(String teamName) async {
    final useTank01 = await _useTank01Rosters();
    print(
        'API Manager: Fetching $_currentSport roster for "$teamName" from ${_apiDisplayName(tank01: useTank01)}');
    try {
      if (useTank01) {
        print(
            'API Manager: Fetching $_currentSport roster for "$teamName" from Tank01 (skipping Firestore)');
        final roster =
            await _tank01ForCurrentSport().fetchRosterByTeamName(teamName);
        print(
            'API Manager: Loaded ${roster.length} players from Tank01 for "$teamName"');
        return roster;
      }

      switch (_currentSport) {
        case 'baseball':
          final team = await _mlbService.findTeamByName(teamName);
          if (team == null) throw Exception('MLB team not found: "$teamName"');
          final cached =
              await _readRosterFromFirestoreIfAvailable('baseball', team.id);
          if (cached != null) return cached;
          final roster = await _mlbService.fetchTeamRoster(team.id);
          Map<String, String?> staff = {
            'headCoach': null,
            'pitchingCoach': null,
            'firstBaseCoach': null,
            'thirdBaseCoach': null,
          };
          try {
            staff = await _mlbService.fetchKeyStaffByTeamId(team.id);
          } catch (_) {}
          await _maybeSyncRosterToFirestore(
            'baseball',
            team.id,
            roster,
            teamDisplayName: team.name,
            headCoach: staff['headCoach'],
            pitchingCoach: staff['pitchingCoach'],
            firstBaseCoach: staff['firstBaseCoach'],
            thirdBaseCoach: staff['thirdBaseCoach'],
          );
          return roster;
        case 'hockey':
          final nhlTeam = await _nhlService.findTeamByName(teamName);
          if (nhlTeam == null) {
            throw Exception('NHL team not found: "$teamName"');
          }
          final cached =
              await _readRosterFromFirestoreIfAvailable('hockey', nhlTeam.id);
          if (cached != null) return cached;
          final roster = await _nhlService.fetchTeamRoster(nhlTeam.id);
          final headCoach = await _nhlService.fetchHeadCoachByTeamName(teamName);
          await _maybeSyncRosterToFirestore(
            'hockey',
            nhlTeam.id,
            roster,
            teamDisplayName: teamName,
            headCoach: headCoach,
          );
          return roster;
        case 'basketball':
          final nbaTeam = await _nbaService.findTeamByName(teamName);
          if (nbaTeam == null) {
            throw Exception('NBA team not found: "$teamName"');
          }
          final cached = await _readRosterFromFirestoreIfAvailable(
            'basketball',
            nbaTeam.id,
          );
          if (cached != null) return cached;
          final nbaRoster =
              await _nbaService.fetchRosterWithHeadCoachByTeamId(nbaTeam.id);
          await _maybeSyncRosterToFirestore(
            'basketball',
            nbaTeam.id,
            nbaRoster.players,
            teamDisplayName: teamName,
            headCoach: nbaRoster.headCoach,
          );
          return nbaRoster.players;
        case 'wnba':
          final wnbaTeam = await _wnbaService.findTeamByName(teamName);
          if (wnbaTeam == null) {
            throw Exception('WNBA team not found: "$teamName"');
          }
          final wnbaCached = await _readRosterFromFirestoreIfAvailable(
            'wnba',
            wnbaTeam.id,
          );
          if (wnbaCached != null) return wnbaCached;
          final wnbaRoster =
              await _wnbaService.fetchRosterWithHeadCoachByTeamId(wnbaTeam.id);
          await _maybeSyncRosterToFirestore(
            'wnba',
            wnbaTeam.id,
            wnbaRoster.players,
            teamDisplayName: teamName,
            headCoach: wnbaRoster.headCoach,
          );
          return wnbaRoster.players;
        case 'soccer':
          final mlsTeam = await _mlsService.findTeamByName(teamName);
          if (mlsTeam == null) {
            throw Exception('MLS team not found: "$teamName"');
          }
          final cached =
              await _readRosterFromFirestoreIfAvailable('soccer', mlsTeam.id);
          if (cached != null) return cached;
          final roster = await _mlsService.fetchRosterByTeamId(mlsTeam.id);
          await _maybeSyncRosterToFirestore(
            'soccer',
            mlsTeam.id,
            roster,
            teamDisplayName: teamName,
          );
          return roster;
        default:
          final nbaTeam = await _nbaService.findTeamByName(teamName);
          if (nbaTeam == null) {
            throw Exception('NBA team not found: "$teamName"');
          }
          final cached = await _readRosterFromFirestoreIfAvailable(
            'basketball',
            nbaTeam.id,
          );
          if (cached != null) return cached;
          final nbaRoster =
              await _nbaService.fetchRosterWithHeadCoachByTeamId(nbaTeam.id);
          await _maybeSyncRosterToFirestore(
            'basketball',
            nbaTeam.id,
            nbaRoster.players,
            teamDisplayName: teamName,
            headCoach: nbaRoster.headCoach,
          );
          return nbaRoster.players;
      }
    } catch (e) {
      print('API Manager: Error fetching roster: $e');
      rethrow;
    }
  }

  /// Returns Firestore roster when available; null means "fallback to API".
  Future<List<Player>?> _readRosterFromFirestoreIfAvailable(
    String sportId,
    String teamId,
  ) async {
    if (!RosterFirestoreService.isAvailable) return null;
    try {
      final players = await RosterFirestoreService.readTeamPlayers(
        sportId: sportId,
        teamId: teamId,
      );
      if (players.isEmpty) return null;
      print(
          'API Manager: Loaded ${players.length} players for $sportId/$teamId from Firestore');
      return players;
    } catch (e) {
      print('API Manager: Firestore roster read failed for $sportId/$teamId: $e');
      return null;
    }
  }

  /// Writes the latest roster to Firestore when Firebase is initialized (best-effort).
  /// Coach fields: baseball uses all four MLB roles; basketball/hockey use [headCoach] only.
  Future<void> _maybeSyncRosterToFirestore(
    String sportId,
    String teamId,
    List<Player> roster, {
    String? teamDisplayName,
    String? headCoach,
    String? pitchingCoach,
    String? firstBaseCoach,
    String? thirdBaseCoach,
  }) async {
    if (!RosterFirestoreService.isAvailable) return;
    try {
      await RosterFirestoreService.writeTeamPlayers(
        sportId: sportId,
        teamId: teamId,
        players: roster,
        teamDisplayName: teamDisplayName,
      );
      final hasStaff = [
        headCoach,
        pitchingCoach,
        firstBaseCoach,
        thirdBaseCoach,
      ].any((s) => (s?.trim().isNotEmpty ?? false));
      if (hasStaff) {
        await RosterFirestoreService.writeTeamCoachStaff(
          sportId: sportId,
          teamId: teamId,
          headCoach: headCoach,
          pitchingCoach: pitchingCoach,
          firstBaseCoach: firstBaseCoach,
          thirdBaseCoach: thirdBaseCoach,
        );
      }
    } catch (e) {
      print('API Manager: Firestore roster sync failed: $e');
    }
  }

  String getApiDisplayName() => _apiDisplayName();

  bool get isConnected => true;

  /// Venue info — MLB official API only; other sports return null.
  Future<String?> fetchVenueForTeam(String teamName) async {
    if (_currentSport != 'baseball') return null;
    final team = await _mlbService.findTeamByName(teamName);
    return team?.venueName;
  }

  /// Returns [TeamInfo] (id, name, locationName, venueName) for [teamName].
  Future<TeamInfo?> findTeamByName(String teamName) async {
    try {
      switch (_currentSport) {
        case 'baseball':
          return await _mlbService.findTeamByName(teamName);
        case 'hockey':
          return await _nhlService.findTeamByName(teamName);
        case 'basketball':
          return await _nbaService.findTeamByName(teamName);
        case 'wnba':
          return await _wnbaService.findTeamByName(teamName);
        case 'soccer':
          return await _mlsService.findTeamByName(teamName);
        default:
          return await _nbaService.findTeamByName(teamName);
      }
    } catch (e) {
      print('API Manager: findTeamByName failed: $e');
      return null;
    }
  }

  Future<String?> fetchVenueForGame(
      String homeTeam, String awayTeam, DateTime gameDate) async {
    if (_currentSport != 'baseball') return null;
    return null;
  }

  /// Fetch key staff names for a team. Keys may be null depending on sport/API.
  /// - baseball: headCoach(manager), pitchingCoach, firstBaseCoach, thirdBaseCoach
  /// - basketball: headCoach from ESPN roster `coach` field
  /// - hockey: headCoach from ESPN NHL roster `coach` (name string)
  /// - soccer: same map key `headCoach` (person name); UI labels this role Manager.
  Future<Map<String, String?>> fetchTeamStaff(String teamName) async {
    switch (_currentSport) {
      case 'baseball':
        return await _mlbService.fetchKeyStaffByTeamName(teamName);
      case 'basketball':
        return {
          'headCoach': await _nbaService.fetchHeadCoachByTeamName(teamName),
          'pitchingCoach': null,
          'firstBaseCoach': null,
          'thirdBaseCoach': null,
        };
      case 'wnba':
        return {
          'headCoach': await _wnbaService.fetchHeadCoachByTeamName(teamName),
          'pitchingCoach': null,
          'firstBaseCoach': null,
          'thirdBaseCoach': null,
        };
      case 'hockey':
        return {
          'headCoach': await _nhlService.fetchHeadCoachByTeamName(teamName),
          'pitchingCoach': null,
          'firstBaseCoach': null,
          'thirdBaseCoach': null,
        };
      case 'soccer':
        return {
          'headCoach': await _mlsService.fetchHeadCoachByTeamName(teamName),
          'pitchingCoach': null,
          'firstBaseCoach': null,
          'thirdBaseCoach': null,
        };
      default:
        return {
          'headCoach': null,
          'pitchingCoach': null,
          'firstBaseCoach': null,
          'thirdBaseCoach': null,
        };
    }
  }

  String getConnectionStatusMessage() => 'Connected to ${_apiDisplayName()}';
}
