/// Tank01 leagues on RapidAPI — admin roster testing.
///
/// Prefer `--dart-define=TANK01_RAPIDAPI_KEY=...` when building.
const String kTank01RapidApiKey =
    'ed2a5e646dmshb06eaba5a965245p1254d8jsndbec435fecd4';

const String kTank01MlbHost =
    'tank01-mlb-live-in-game-real-time-statistics.p.rapidapi.com';
const String kTank01NbaHost = 'tank01-fantasy-stats.p.rapidapi.com';
const String kTank01NhlHost =
    'tank01-nhl-live-in-game-real-time-statistics-nhl.p.rapidapi.com';
const String kTank01WnbaHost =
    'tank01-wnba-live-in-game-real-time-statistics-wnba.p.rapidapi.com';

/// Tank01 league products available for FloFile sports.
enum Tank01League {
  mlb,
  nba,
  nhl,
  wnba,
}

extension Tank01LeagueX on Tank01League {
  String get host {
    switch (this) {
      case Tank01League.mlb:
        return kTank01MlbHost;
      case Tank01League.nba:
        return kTank01NbaHost;
      case Tank01League.nhl:
        return kTank01NhlHost;
      case Tank01League.wnba:
        return kTank01WnbaHost;
    }
  }

  String get teamsPath {
    switch (this) {
      case Tank01League.mlb:
        return 'getMLBTeams';
      case Tank01League.nba:
        return 'getNBATeams';
      case Tank01League.nhl:
        return 'getNHLTeams';
      case Tank01League.wnba:
        return 'getWNBATeams';
    }
  }

  String get rosterPath {
    switch (this) {
      case Tank01League.mlb:
        return 'getMLBTeamRoster';
      case Tank01League.nba:
        return 'getNBATeamRoster';
      case Tank01League.nhl:
        return 'getNHLTeamRoster';
      case Tank01League.wnba:
        return 'getWNBATeamRoster';
    }
  }

  String get label {
    switch (this) {
      case Tank01League.mlb:
        return 'MLB';
      case Tank01League.nba:
        return 'NBA';
      case Tank01League.nhl:
        return 'NHL';
      case Tank01League.wnba:
        return 'WNBA';
    }
  }

  /// FloFile sport key → Tank01 league, or null if unsupported (e.g. soccer).
  static Tank01League? fromSport(String sport) {
    switch (sport.toLowerCase().trim()) {
      case 'baseball':
        return Tank01League.mlb;
      case 'basketball':
        return Tank01League.nba;
      case 'hockey':
        return Tank01League.nhl;
      case 'wnba':
        return Tank01League.wnba;
      default:
        return null;
    }
  }
}

String? get tank01RapidApiKey {
  const fromDefine = String.fromEnvironment('TANK01_RAPIDAPI_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  final configured = kTank01RapidApiKey.trim();
  if (configured.isNotEmpty) return configured;
  return null;
}

bool tank01SupportsSport(String sport) =>
    Tank01LeagueX.fromSport(sport) != null;
