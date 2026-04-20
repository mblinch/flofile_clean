/// Parse persisted JSON (list or comma string) into keyword strings.
List<String> verbKeywordsFromJson(dynamic v) {
  if (v == null) return const [];
  if (v is List) {
    return v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (v is String) {
    return v
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Parse comma-separated keywords from an editor text field.
List<String> parseVerbKeywordsField(String text) {
  return text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Default IPTC-style keywords per verb **display name** (sport-agnostic keys).
/// Used when opening the verb editor and when no override has saved keywords.
List<String> defaultKeywordsForVerbLabel(String label) {
  final key = label.trim();
  if (key.isEmpty) return const [];
  final fromMap = _defaults[key];
  if (fromMap != null && fromMap.isNotEmpty) {
    return List<String>.from(fromMap);
  }
  return _fallbackKeywords(key);
}

List<String> _fallbackKeywords(String label) {
  final lower = label.toLowerCase();
  final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  if (words.length == 1) {
    final w = words.first;
    return [w, '${w}ing'];
  }
  return [lower.replaceAll(' ', ''), words.first];
}

/// Keys = exact verb labels used in UI (hockey popup, keyboard fire, baseball, basketball).
final Map<String, List<String>> _defaults = {
  // Hockey — Offense
  'Skates': ['skate', 'skates', 'skating'],
  'Shoots': ['shoot', 'shoots', 'shooting', 'shot'],
  'Battles': ['battle', 'battles', 'battling', 'compete'],
  'Scores': ['score', 'scores', 'scoring', 'goal'],
  'Goes to the Net': ['net', 'front of the net', 'crease attack'],
  'Faceoff': ['faceoff', 'face-off', 'draw', 'centerman'],
  'Celebrates a Goal': ['celebrate', 'celebration', 'goal'],
  'Celebrates': ['celebrate', 'celebration', 'celly'],
  // Hockey — Defense
  'Blocks': ['block', 'blocks', 'blocking', 'shot block'],
  'Clears': ['clear', 'clears', 'clearing', 'puck'],
  'Checks': ['check', 'checks', 'checking', 'hit'],
  'Defends': ['defend', 'defends', 'defense', 'defending'],
  // Hockey — Goalie
  'Saves': ['save', 'saves', 'goaltending', 'goalie'],
  'Handles the Puck': ['puck', 'stickhandling', 'handles puck'],
  'Stands in Net': ['net', 'crease', 'goalie', 'stance'],
  'Guards the Net': ['net', 'crease', 'goalie', 'guards net'],
  // Hockey — Non game / reactions
  'Looks On': ['bench', 'observes', 'looks on'],
  'Warm Ups': ['warmup', 'warm-ups', 'pregame'],
  'Takes the Ice': ['ice', 'pregame', 'takes ice'],
  'Walks to the Ice': ['ice', 'pregame', 'walks on'],
  'Comes Off the Ice': ['ice', 'bench', 'leaves ice'],
  'National Anthem': ['anthem', 'pregame', 'ceremony'],
  'Stretching': ['stretch', 'stretching', 'pregame'],
  'Bench': ['bench', 'reserve'],
  'Post Game Win': ['postgame', 'win', 'victory'],
  'Post Game Loss': ['postgame', 'loss', 'defeat'],
  'Dejection': ['dejection', 'defeat', 'reaction'],
  // Baseball — Offense
  'Single': ['single', 'singles', 'hit'],
  'Double': ['double', 'doubles', 'hit'],
  'Triple': ['triple', 'triples', 'hit'],
  'Home Run': ['home run', 'homer', 'hr', 'dinger'],
  'Sacrifice Fly': ['sac fly', 'sacrifice fly', 'sacrifice'],
  'At Bat': ['at bat', 'batting', 'ab', 'hitter'],
  'Swings': ['swing', 'swings', 'swinging', 'batter'],
  'Bunts': ['bunt', 'bunts', 'bunting'],
  'Hit by Pitch': ['hbp', 'hit by pitch', 'plunked'],
  // Baseball — Defense
  'Pitching': ['pitch', 'pitcher', 'pitching', 'mound'],
  'Mound Visit': ['mound visit', 'mound', 'visit', 'coach visit'],
  'Catches': ['catch', 'catches', 'catching', 'receiver'],
  'Throws': ['throw', 'throws', 'throwing', 'arm'],
  'Tags': ['tag', 'tags', 'tagging', 'out'],
  'Groundball': ['groundball', 'grounder', 'gb', 'ground ball'],
  'Fielding Position': ['fielding', 'position', 'defense'],
  'Double Play': ['double play', 'dp', 'twin killing'],
  'Triple Play': ['triple play', 'tp', 'triple killing'],
  // Baseball — Running
  'Steals': ['steal', 'steals', 'stealing', 'stolen base'],
  'Slides': ['slide', 'slides', 'sliding'],
  'Runs': ['run', 'runs', 'running', 'basepath'],
  'Rounds': ['round', 'rounds', 'bases', 'advance'],
  // Baseball — Non game-action
  'Batting Practice': ['batting practice', 'bp', 'pregame'],
  'Fielding Practice': ['fielding practice', 'pregame'],
  'Takes the Field': ['field', 'pregame', 'takes field'],
  'Comes Off the Field': ['field', 'dugout', 'exits'],
  'Pitching Change': ['pitching change', 'reliever', 'bullpen', 'hook'],
  // Basketball — Offense
  'Drives': ['drive', 'drives', 'driving', 'penetration'],
  'Dribbles': ['dribble', 'dribbles', 'dribbling', 'handles'],
  'Dunks': ['dunk', 'dunks', 'dunking', 'slam'],
  'Lays Up': ['layup', 'lay up', 'lay-in', 'finger roll'],
  'Three-Pointer': ['three pointer', 'three', '3pt', 'from deep'],
  'Free Throw': ['free throw', 'ft', 'charity stripe'],
  // Basketball — Defense
  'Steals the Ball': ['steal', 'steals', 'turnover', 'pick'],
  'Contests': ['contest', 'contests', 'shot contest', 'closeout'],
  'Rebounds': ['rebound', 'rebounds', 'board', 'glass'],
  // Basketball — Non game
  'Takes the Court': ['court', 'pregame', 'tipoff'],
  'Comes Off the Court': ['court', 'bench', 'substitution'],
};

// --- Quick-insert groups (verb editor keyword bar; output is comma-separated)

const List<String> verbKeywordQuickGroupC = [
  'celebrates',
  'reacts',
];

const List<String> verbKeywordQuickGroupP = [
  'pitcher',
  'pitches',
  'pitching',
  'throws',
  'throwing',
];

const List<String> verbKeywordQuickGroupPs = [
  'pitcher',
  'pitches',
  'pitching',
  'throws',
  'throwing',
  'slowy',
  'motion blur',
  'pan',
  'panski',
];

const List<String> verbKeywordQuickGroupB = [
  'bats',
  'batting',
  'at bat',
  'hits',
  'hitting',
];

const List<String> verbKeywordQuickGroupO = [
  'overhead',
  'remote',
  'home plate',
  'aerial',
  'top down',
];

const List<String> verbKeywordQuickTpx = ['toppix'];

/// Appends keywords to comma-separated [current]; skips duplicates (case-insensitive).
String mergeVerbKeywordFieldText(String current, List<String> toAppend) {
  final existing = parseVerbKeywordsField(current);
  final lower = existing.map((e) => e.toLowerCase()).toSet();
  final merged = List<String>.from(existing);
  for (final a in toAppend) {
    final t = a.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    if (lower.contains(k)) continue;
    merged.add(t);
    lower.add(k);
  }
  return merged.join(', ');
}
