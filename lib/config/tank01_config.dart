/// Tank01 MLB on RapidAPI — admin roster testing.
///
/// Prefer `--dart-define=TANK01_RAPIDAPI_KEY=...` when building.
const String kTank01RapidApiKey =
    'ed2a5e646dmshb06eaba5a965245p1254d8jsndbec435fecd4';

const String kTank01MlbHost =
    'tank01-mlb-live-in-game-real-time-statistics.p.rapidapi.com';

String? get tank01RapidApiKey {
  const fromDefine = String.fromEnvironment('TANK01_RAPIDAPI_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  final configured = kTank01RapidApiKey.trim();
  if (configured.isNotEmpty) return configured;
  return null;
}
