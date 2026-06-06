/// Per-verb caption sub-options editable in the verb editor (RBI + celebration only).
class VerbSubOptions {
  const VerbSubOptions({
    this.rbiEnabled = false,
    this.rbiWord = 'RBI',
    this.celebrationEnabled = false,
    this.celebrationPhrase = 'celebrates',
    this.celebrationTypes =
        'Scoring, Single, Double, Triple, Home Run, Strikeout',
  });

  /// Show RBI count buttons (Keyboard Fire / hitting popup).
  final bool rbiEnabled;

  /// Word used in captions: "hits a {rbiWord} single" or "two-{rbiWord}".
  final String rbiWord;

  /// Show celebration (Cele on hits, or celebration chips on celebration verbs).
  final bool celebrationEnabled;

  /// Verb used when Cele is selected, e.g. "celebrates".
  final String celebrationPhrase;

  /// Comma-separated chip labels for Celebration / Celebrates verbs.
  final String celebrationTypes;

  static const String defaultCelebrationTypes =
      'Scoring, Single, Double, Triple, Home Run, Strikeout';

  VerbSubOptions copyWith({
    bool? rbiEnabled,
    String? rbiWord,
    bool? celebrationEnabled,
    String? celebrationPhrase,
    String? celebrationTypes,
  }) {
    return VerbSubOptions(
      rbiEnabled: rbiEnabled ?? this.rbiEnabled,
      rbiWord: rbiWord ?? this.rbiWord,
      celebrationEnabled: celebrationEnabled ?? this.celebrationEnabled,
      celebrationPhrase: celebrationPhrase ?? this.celebrationPhrase,
      celebrationTypes: celebrationTypes ?? this.celebrationTypes,
    );
  }

  Map<String, dynamic> toJson() => {
        'rbiEnabled': rbiEnabled,
        'rbiWord': rbiWord.trim(),
        'celebrationEnabled': celebrationEnabled,
        'celebrationPhrase': celebrationPhrase.trim(),
        'celebrationTypes': celebrationTypes.trim(),
      };

  static VerbSubOptions fromJson(
    dynamic raw, {
    required String verbLabel,
  }) {
    if (raw is! Map) return defaultsFor(verbLabel);
    final d = defaultsFor(verbLabel);
    return VerbSubOptions(
      rbiEnabled: raw['rbiEnabled'] as bool? ??
          raw['rbiMenu'] as bool? ??
          d.rbiEnabled,
      rbiWord: (raw['rbiWord'] as String?)?.trim().isNotEmpty == true
          ? (raw['rbiWord'] as String).trim()
          : 'RBI',
      celebrationEnabled: raw['celebrationEnabled'] as bool? ??
          raw['celeButton'] as bool? ??
          raw['celebrationChips'] as bool? ??
          d.celebrationEnabled,
      celebrationPhrase:
          (raw['celebrationPhrase'] as String?)?.trim().isNotEmpty == true
              ? (raw['celebrationPhrase'] as String).trim()
              : d.celebrationPhrase,
      celebrationTypes:
          (raw['celebrationTypes'] as String?)?.trim().isNotEmpty == true
              ? (raw['celebrationTypes'] as String).trim()
              : d.celebrationTypes,
    );
  }

  static VerbSubOptions defaultsFor(String verbLabel) {
    const hitVerbs = {
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'Sacrifice Fly',
      'Bunt',
      'Hit by Pitch',
    };
    const celebrationVerbs = {
      'Celebration',
      'Celebrates',
      'Celebrates With',
      'Celebrates Against',
      'Celebrates a Goal',
    };

    final isHit = hitVerbs.contains(verbLabel);
    final isHomeRun = verbLabel == 'Home Run';

    return VerbSubOptions(
      rbiEnabled: isHit && !isHomeRun,
      celebrationEnabled: isHit || celebrationVerbs.contains(verbLabel),
    );
  }

  bool differsFromDefaults(String verbLabel) {
    final d = defaultsFor(verbLabel);
    return rbiEnabled != d.rbiEnabled ||
        rbiWord != d.rbiWord ||
        celebrationEnabled != d.celebrationEnabled ||
        celebrationPhrase != d.celebrationPhrase ||
        celebrationTypes != d.celebrationTypes;
  }

  List<String> celebrationTypeList() {
    final list = celebrationTypes
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return list.isEmpty
        ? defaultCelebrationTypes
            .split(',')
            .map((e) => e.trim())
            .toList()
        : list;
  }

  String rbiCountLabel(int count) {
    final word = rbiWord.trim().isEmpty ? 'RBI' : rbiWord.trim();
    if (count <= 1) return word;
    return '${_numberWord(count)}-$word';
  }

  static String _numberWord(int count) {
    switch (count) {
      case 1:
        return 'one';
      case 2:
        return 'two';
      case 3:
        return 'three';
      case 4:
        return 'four';
      default:
        return count.toString();
    }
  }

  // Legacy UI behavior (not editable in verb editor; factory defaults only).

  static bool legacyHomeRunTypeMenu(String verbLabel) =>
      verbLabel == 'Home Run';

  static bool legacyTagsSubMenu(String verbLabel) => verbLabel == 'Tags';

  static bool legacyBaseSubMenu(String verbLabel) =>
      const {'Steals', 'Slides', 'Runs', 'Rounds'}.contains(verbLabel);

  static bool legacyInningSelector(String verbLabel) {
    const verbs = {
      'At Bat',
      'Pitching',
      'Swings',
      'Bunts',
      'Hit by Pitch',
      'Walks',
      'Catches',
      'Throws',
      'Groundball',
      'Double Play',
      'Triple Play',
      'Steals',
      'Slides',
      'Runs',
      'Rounds',
      'Fielding Position',
      'Looks On',
      'Walks Off Field',
      'Runs Off Field',
      'Takes the Field',
      'Comes Off the Field',
      'Strikeout',
      'Shoots',
      'Scores',
      'Passes',
      'Skates',
      'Battles',
      'Faceoff',
      'Goes to the Net',
      'Power Play',
      'Breakaway',
      'Blocks',
      'Saves',
      'Handles the Puck',
      'Stands in Net',
      'Guards the Net',
      'Clears',
      'Checks',
      'Defends',
      'Warm Ups',
      'Takes the Ice',
      'Comes Off the Ice',
      'National Anthem',
      'Stretching',
      'Bench',
      'Celebrates',
      'Celebrates a Goal',
      'Dejection',
      'Post Game Win',
      'Post Game Loss',
      'Home Run',
      'Single',
      'Double',
      'Triple',
    };
    return verbs.contains(verbLabel);
  }

  static bool legacyFullHittingPopup(String verbLabel) =>
      const {'Home Run', 'Single', 'Double', 'Triple'}.contains(verbLabel);
}
