/// Whether roster abbreviations (C, RF, 1B, …) are written out in captions.
/// AP and Imagn use full labels (`catcher`, `right fielder`); Getty USA often
/// keeps the abbreviation.
bool captionWireExpandsPositionLabels({
  required bool apStyleWire,
  required bool imagnStyleWire,
}) =>
    apStyleWire || imagnStyleWire;

String formatPositionLabelForCaption(
  String raw, {
  required bool apStyle,
  bool imagnStyle = false,
  bool americanEnglish = true,
  String? sport,
}) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  final expand = captionWireExpandsPositionLabels(
    apStyleWire: apStyle,
    imagnStyleWire: imagnStyle,
  );
  if (!expand) return value;

  final parts = value
      .split('/')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map((p) => _expandPositionToken(
            p,
            americanEnglish: americanEnglish,
            sport: sport,
          ))
      .toList();
  if (parts.isEmpty) return value;
  return parts.join('/');
}

String _expandPositionToken(
  String token, {
  required bool americanEnglish,
  String? sport,
}) {
  final key = token.trim().toUpperCase();
  if (key.isEmpty) return token;

  final centerWord = americanEnglish ? 'center' : 'centre';
  const map = <String, String>{
    // Baseball
    'P': 'pitcher',
    'SP': 'starting pitcher',
    'RP': 'relief pitcher',
    'CP': 'closer',
    '1B': 'first baseman',
    '2B': 'second baseman',
    '3B': 'third baseman',
    'SS': 'shortstop',
    'LF': 'left fielder',
    'CF': 'center fielder',
    'RF': 'right fielder',
    'DH': 'designated hitter',
    'OF': 'outfielder',
    'IF': 'infielder',
    'UTIL': 'utility player',

    // Basketball
    'PG': 'point guard',
    'SG': 'shooting guard',
    'SF': 'small forward',
    'PF': 'power forward',
    'G': 'guard',
    'F': 'forward',

    // Hockey
    'LW': 'left wing',
    'RW': 'right wing',
    'D': 'defenseman',
    'LD': 'left defenseman',
    'RD': 'right defenseman',
    'GK': 'goalkeeper',

    // Soccer / football
    'CB': 'center back',
    'LB': 'left back',
    'RB': 'right back',
    'LWB': 'left wing-back',
    'RWB': 'right wing-back',
    'DM': 'defensive midfielder',
    'CDM': 'defensive midfielder',
    'CM': 'central midfielder',
    'CAM': 'attacking midfielder',
    'LM': 'left midfielder',
    'RM': 'right midfielder',
    'ST': 'striker',
  };

  final mapped = map[key];
  if (mapped != null) {
    return mapped.replaceAll('center', centerWord);
  }
  if (key == 'C') {
    final s = (sport ?? '').toLowerCase();
    if (s == 'baseball') return 'catcher';
    return centerWord;
  }
  return token;
}
