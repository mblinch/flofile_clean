/// How multi-count RBI phrases are written in captions (e.g. "two-RBI" vs "2 RBI").
enum RbiCaptionStyle {
  /// `2 RBI`
  digitSpace('digitSpace', '2 RBI'),

  /// `two RBI`
  wordSpace('wordSpace', 'two RBI'),

  /// `2-RBI`
  digitDash('digitDash', '2-RBI'),

  /// `two-RBI` (app default)
  wordDash('wordDash', 'two-RBI'),

  /// `2 runs batted in` (before the hit noun)
  runsBattedIn('runsBattedIn', '2 runs batted in'),

  /// `2 R.B.I.`
  dotted('dotted', '2 R.B.I.'),

  /// After the hit noun: `single with two runs batted in`
  withRunsBattedIn('withRunsBattedIn', 'with two runs batted in'),

  /// Home-run style run count: `two-run` (also `solo` / `three-run`)
  runDash('runDash', 'two-run');

  const RbiCaptionStyle(this.id, this.menuLabel);

  final String id;

  /// Sample shown in the style dropdown (always for count 2).
  final String menuLabel;

  static const RbiCaptionStyle defaultStyle = RbiCaptionStyle.wordDash;

  static RbiCaptionStyle fromId(String? raw) {
    final id = (raw ?? '').trim();
    for (final s in RbiCaptionStyle.values) {
      if (s.id == id) return s;
    }
    return defaultStyle;
  }
}

/// Per-verb caption sub-options editable in the verb editor (RBI + celebration).
class VerbSubOptions {
  const VerbSubOptions({
    this.rbiEnabled = false,
    this.rbiWord = 'RBI',
    this.rbiStyle = RbiCaptionStyle.defaultStyle,
    this.grandSlamPhrase = defaultGrandSlamPhrase,
    this.celebrationEnabled = false,
    this.celebrationPhrase = 'celebrates',
    this.celebrationTypes =
        'Scoring, Single, Double, Triple, Home Run, Strikeout',
  });

  /// Show RBI count buttons (Keyboard Fire / hitting popup). Baseball only.
  final bool rbiEnabled;

  /// Legacy free-text unit (kept for older prefs). Prefer [rbiStyle].
  final String rbiWord;

  /// Caption formatting for RBI counts (e.g. `two-RBI` vs `2 RBI`).
  final RbiCaptionStyle rbiStyle;

  /// Full noun phrase after "hits a" / "celebrates a" for grand slam.
  /// Default: `grand slam home run`.
  final String grandSlamPhrase;

  /// Show celebration (Cele on hits, or celebration chips on celebration verbs).
  final bool celebrationEnabled;

  /// Verb used when Cele is selected, e.g. "celebrates".
  final String celebrationPhrase;

  /// Comma-separated chip labels for Celebration / Celebrates verbs.
  final String celebrationTypes;

  static const String defaultCelebrationTypes =
      'Scoring, Single, Double, Triple, Home Run, Strikeout';

  static const String defaultGrandSlamPhrase = 'grand slam home run';

  static const Set<String> hitVerbs = {
    'Single',
    'Double',
    'Triple',
    'Home Run',
    'Sacrifice Fly',
    'Bunt',
    'Hit by Pitch',
  };

  static const Set<String> celebrationVerbs = {
    'Celebration',
    'Celebrates',
    'Celebrates With',
    'Celebrates Against',
    'Celebrates a Goal',
  };

  static String normalizeSport(String? sport) =>
      (sport ?? 'baseball').trim().toLowerCase();

  static bool isBaseballSport(String? sport) =>
      normalizeSport(sport) == 'baseball';

  static bool isHitVerb(String verbLabel) => hitVerbs.contains(verbLabel);

  static bool isCelebrationVerb(String verbLabel) =>
      celebrationVerbs.contains(verbLabel);

  /// Baseball-only RBI block in the verb editor.
  static bool showRbiEditor({
    required String? sport,
    required String verbLabel,
    VerbSubOptions? value,
  }) {
    if (!isBaseballSport(sport)) return false;
    return isHitVerb(verbLabel) || (value?.rbiEnabled ?? false);
  }

  /// Celebration block when the verb is celebration-related or already enabled.
  static bool showCelebrationEditor({
    required String verbLabel,
    VerbSubOptions? value,
  }) {
    return isHitVerb(verbLabel) ||
        isCelebrationVerb(verbLabel) ||
        (value?.celebrationEnabled ?? false);
  }

  static bool showEditorPanel({
    required String? sport,
    required String verbLabel,
    VerbSubOptions? value,
  }) {
    return showRbiEditor(
          sport: sport,
          verbLabel: verbLabel,
          value: value,
        ) ||
        showCelebrationEditor(verbLabel: verbLabel, value: value);
  }

  static String defaultCelebrationTypesForSport(String? sport) {
    switch (normalizeSport(sport)) {
      case 'hockey':
        return 'Goal, Win, Handshake, Shootout, Power Play';
      case 'basketball':
        return 'Dunk, Three, Win, Free Throw, Block';
      case 'baseball':
      default:
        return defaultCelebrationTypes;
    }
  }

  VerbSubOptions copyWith({
    bool? rbiEnabled,
    String? rbiWord,
    RbiCaptionStyle? rbiStyle,
    String? grandSlamPhrase,
    bool? celebrationEnabled,
    String? celebrationPhrase,
    String? celebrationTypes,
  }) {
    return VerbSubOptions(
      rbiEnabled: rbiEnabled ?? this.rbiEnabled,
      rbiWord: rbiWord ?? this.rbiWord,
      rbiStyle: rbiStyle ?? this.rbiStyle,
      grandSlamPhrase: grandSlamPhrase ?? this.grandSlamPhrase,
      celebrationEnabled: celebrationEnabled ?? this.celebrationEnabled,
      celebrationPhrase: celebrationPhrase ?? this.celebrationPhrase,
      celebrationTypes: celebrationTypes ?? this.celebrationTypes,
    );
  }

  Map<String, dynamic> toJson() => {
        'rbiEnabled': rbiEnabled,
        'rbiWord': rbiWord.trim(),
        'rbiStyle': rbiStyle.id,
        'grandSlamPhrase': grandSlamPhrase.trim(),
        'celebrationEnabled': celebrationEnabled,
        'celebrationPhrase': celebrationPhrase.trim(),
        'celebrationTypes': celebrationTypes.trim(),
      };

  static VerbSubOptions fromJson(
    dynamic raw, {
    required String verbLabel,
    String? sport,
  }) {
    if (raw is! Map) return defaultsFor(verbLabel, sport: sport);
    final d = defaultsFor(verbLabel, sport: sport);
    final baseball = isBaseballSport(sport);
    final rbiEnabled = baseball &&
        (raw['rbiEnabled'] as bool? ??
            raw['rbiMenu'] as bool? ??
            d.rbiEnabled);
    return VerbSubOptions(
      rbiEnabled: rbiEnabled,
      rbiWord: (raw['rbiWord'] as String?)?.trim().isNotEmpty == true
          ? (raw['rbiWord'] as String).trim()
          : d.rbiWord,
      rbiStyle: raw['rbiStyle'] != null
          ? RbiCaptionStyle.fromId(raw['rbiStyle'] as String?)
          : d.rbiStyle,
      grandSlamPhrase:
          (raw['grandSlamPhrase'] as String?)?.trim().isNotEmpty == true
              ? (raw['grandSlamPhrase'] as String).trim()
              : d.grandSlamPhrase,
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

  static VerbSubOptions defaultsFor(String verbLabel, {String? sport}) {
    final baseball = isBaseballSport(sport);
    final isHit = baseball && isHitVerb(verbLabel);
    final isHomeRun = verbLabel == 'Home Run';
    final isCele = isCelebrationVerb(verbLabel);

    return VerbSubOptions(
      rbiEnabled: isHit,
      rbiStyle: isHomeRun
          ? RbiCaptionStyle.runDash
          : RbiCaptionStyle.defaultStyle,
      grandSlamPhrase: defaultGrandSlamPhrase,
      celebrationEnabled: isHit || isCele,
      celebrationTypes: defaultCelebrationTypesForSport(sport),
    );
  }

  bool differsFromDefaults(String verbLabel, {String? sport}) {
    final d = defaultsFor(verbLabel, sport: sport);
    return rbiEnabled != d.rbiEnabled ||
        rbiWord != d.rbiWord ||
        rbiStyle != d.rbiStyle ||
        grandSlamPhrase != d.grandSlamPhrase ||
        celebrationEnabled != d.celebrationEnabled ||
        celebrationPhrase != d.celebrationPhrase ||
        celebrationTypes != d.celebrationTypes;
  }

  List<String> celebrationTypeList({String? sport}) {
    final list = celebrationTypes
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (list.isNotEmpty) return list;
    return defaultCelebrationTypesForSport(sport)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// True when RBI wording comes after the hit noun (e.g. "single with two…").
  bool get rbiPlacesAfterHit =>
      rbiStyle == RbiCaptionStyle.withRunsBattedIn;

  /// Phrase inserted after "hits a …" / "celebrates a …" for an RBI count
  /// (infix styles only). Prefer [hitClauseWithRbi] for full clauses.
  String rbiCountLabel(int count) {
    final c = count < 1 ? 1 : count;
    switch (rbiStyle) {
      case RbiCaptionStyle.digitSpace:
        return c <= 1 ? 'RBI' : '$c RBI';
      case RbiCaptionStyle.wordSpace:
        return c <= 1 ? 'RBI' : '${_numberWord(c)} RBI';
      case RbiCaptionStyle.digitDash:
        return c <= 1 ? 'RBI' : '$c-RBI';
      case RbiCaptionStyle.wordDash:
        return c <= 1 ? 'RBI' : '${_numberWord(c)}-RBI';
      case RbiCaptionStyle.runsBattedIn:
        return c <= 1 ? 'run batted in' : '$c runs batted in';
      case RbiCaptionStyle.dotted:
        return c <= 1 ? 'R.B.I.' : '$c R.B.I.';
      case RbiCaptionStyle.withRunsBattedIn:
        return c <= 1
            ? 'with one run batted in'
            : 'with ${_numberWord(c)} runs batted in';
      case RbiCaptionStyle.runDash:
        if (c <= 1) return 'solo';
        if (c >= 4) return 'grand slam';
        return '${_numberWord(c)}-run';
    }
  }

  /// Builds "hits a two-RBI single" or "hits a single with two runs batted in".
  ///
  /// [leadIn] is typically `hits a` or `celebrates a`.
  String hitClauseWithRbi({
    required String leadIn,
    required String hitNoun,
    required int count,
  }) {
    final c = count < 1 ? 1 : count;
    if (c >= 4) {
      return hitClauseWithGrandSlam(leadIn: leadIn, hitNoun: hitNoun);
    }
    final label = rbiCountLabel(count);
    if (rbiPlacesAfterHit) {
      return '$leadIn $hitNoun $label';
    }
    return '$leadIn $label $hitNoun';
  }

  /// Resolved grand slam noun phrase (after "hits a" / "celebrates a").
  String resolvedGrandSlamPhrase({String hitNoun = 'home run'}) {
    final custom = grandSlamPhrase.trim();
    if (custom.isNotEmpty) return custom;
    return 'grand slam $hitNoun';
  }

  /// Builds "hits a grand slam home run" using [grandSlamPhrase] when set.
  String hitClauseWithGrandSlam({
    required String leadIn,
    String hitNoun = 'home run',
  }) {
    return '$leadIn ${resolvedGrandSlamPhrase(hitNoun: hitNoun)}';
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
