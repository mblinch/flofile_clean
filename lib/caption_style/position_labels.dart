/// Whether roster abbreviations (C, RF, 1B, …) are written out in captions.
/// AP and Imagn use full labels (`catcher`, `right fielder`); Getty USA often
/// keeps the abbreviation.
bool captionWireExpandsPositionLabels({
  required bool apStyleWire,
  required bool imagnStyleWire,
}) =>
    apStyleWire || imagnStyleWire;

/// US ↔ Intl spelling swaps for position labels (longer keys first).
///
/// Covers plain `defenseman` / `defenceman` as well as left/right and
/// `center` / `centre` compounds. Applied to expanded abbrevs and raw
/// roster words.
const List<(String us, String intl)> kPositionIntlSpellings = [
  ('defensemen', 'defencemen'),
  ('defenseman', 'defenceman'),
  ('center', 'centre'),
];

/// Positions whose expanded English form changes under Intl spelling.
/// (Abbrev → US form; Intl is derived via [kPositionIntlSpellings].)
const Map<String, String> kPositionsWithIntlSpelling = {
  'CF': 'center fielder',
  'C': 'center', // basketball / hockey / soccer; baseball catcher is special-cased
  'D': 'defenseman',
  'LD': 'left defenseman',
  'RD': 'right defenseman',
  'CB': 'center back',
};

String _swapCased(String label, String from, String to) {
  var out = label;
  out = out.replaceAll(from, to);
  out = out.replaceAll(
    '${from[0].toUpperCase()}${from.substring(1)}',
    '${to[0].toUpperCase()}${to.substring(1)}',
  );
  out = out.replaceAll(from.toUpperCase(), to.toUpperCase());
  return out;
}

/// Normalize position spelling to US or Intl.
///
/// - Intl on: `defenseman` → `defenceman`, `center` → `centre`
/// - US on: `defenceman` → `defenseman`, `centre` → `center`
///   (so Canadian roster text still matches Spelling → US)
String applyPositionSpelling(
  String label, {
  required bool americanEnglish,
}) {
  if (label.isEmpty) return label;
  var out = label;
  for (final (us, intl) in kPositionIntlSpellings) {
    if (americanEnglish) {
      out = _swapCased(out, intl, us);
    } else {
      out = _swapCased(out, us, intl);
    }
  }
  return out;
}

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

  final String labeled;
  if (!expand) {
    labeled = value;
  } else {
    final parts = value
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map(
          (p) => _expandPositionToken(
            p,
            americanEnglish: americanEnglish,
            sport: sport,
          ),
        )
        .toList();
    labeled = parts.isEmpty ? value : parts.join('/');
  }

  // Always run spelling on the final string so raw roster words
  // (`Center`, `Left Defenseman`) flip when Intl is on — even if the
  // wire did not expand abbreviations.
  return applyPositionSpelling(
    labeled,
    americanEnglish: americanEnglish,
  );
}

String _expandPositionToken(
  String token, {
  required bool americanEnglish,
  String? sport,
}) {
  final key = token.trim().toUpperCase();
  if (key.isEmpty) return token;

  // Baseball C is catcher (no US/Intl spelling change).
  if (key == 'C') {
    final s = (sport ?? '').toLowerCase();
    if (s == 'baseball') return 'catcher';
    return americanEnglish ? 'center' : 'centre';
  }

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

    // Hockey — plain defenseman plus side variants
    'LW': 'left wing',
    'RW': 'right wing',
    'D': 'defenseman',
    'LD': 'left defenseman',
    'RD': 'right defenseman',
    'DEFENSEMAN': 'defenseman',
    'DEFENCEMAN': 'defenseman',
    'DEFENSEMEN': 'defensemen',
    'DEFENCEMEN': 'defencemen',
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
  if (mapped == null) {
    // Already a full word from the roster — spelling applied by caller.
    return token;
  }
  return applyPositionSpelling(mapped, americanEnglish: americanEnglish);
}
