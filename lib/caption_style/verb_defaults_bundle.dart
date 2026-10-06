import '../utils/default_verb_keywords.dart';
import 'sport_verb_categories.dart';
import 'verb_authoring_model.dart';
import 'verb_caption_wording.dart';
import 'verb_sub_options.dart';

/// Builds and normalizes the Firebase / offline verb catalog for a sport.
///
/// A **complete** catalog stores every default verb as a full record in
/// `verbOverrides` (plus order / favorites / customs). Factory Dart lists are
/// only used to seed an empty catalog or fill gaps before the first publish.
class VerbDefaultsBundle {
  VerbDefaultsBundle._();

  static const String catalogCompleteKey = 'catalogComplete';

  static bool isComplete(Map<String, dynamic>? bundle) =>
      bundle != null && bundle[catalogCompleteKey] == true;

  /// Favorites are personal — never ship them in app-default / factory catalogs.
  static Map<String, dynamic> withoutFavoriteVerbs(Map<String, dynamic> bundle) {
    final next = Map<String, dynamic>.from(bundle);
    next['favoriteVerbs'] = <String>[];
    return next;
  }

  /// Full factory sport catalog ready to publish / cache offline.
  static Map<String, dynamic> buildFactory(String sport) {
    final factory = SportVerbCategories.copyForSport(sport);
    final categoryOrder = <String>[
      for (final entry in factory.entries)
        if (entry.value.any((label) => label.trim().isNotEmpty)) entry.key,
    ];
    final verbOrder = <String, List<String>>{};
    final overrides = <String, Map<String, dynamic>>{};

    for (final entry in factory.entries) {
      final keys = <String>[];
      for (final raw in entry.value) {
        final key = raw.trim();
        if (key.isEmpty) continue;
        keys.add(key);
        overrides[key] = factoryVerbRecord(key, entry.key, sport);
      }
      if (keys.isNotEmpty) verbOrder[entry.key] = keys;
    }

    return {
      catalogCompleteKey: true,
      'categoryOrder': categoryOrder,
      'verbOrder': verbOrder,
      'favoriteVerbs': <String>[],
      'favoriteTeams': <String>[],
      'deletedVerbs': <String>[],
      'customVerbs': <Map<String, dynamic>>[],
      'verbOverrides': overrides,
      'verbWordingDefaults': <String, dynamic>{},
      'customVerbWordings': <String, dynamic>{},
      // verbKey → category for intentional moves of factory verbs.
      'categoryOverrides': <String, String>{},
    };
  }

  /// Intentional category move for a factory verb, if any.
  static String? pinnedCategoryFor(
    Map<String, dynamic> bundle,
    String verbKey,
    String Function(String) remapCategory,
  ) {
    final raw = bundle['categoryOverrides'];
    if (raw is! Map) return null;
    final value = raw[verbKey]?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return remapCategory(value);
  }

  /// True when nearly every override shares one category while the factory
  /// sport has several — the old "everything landed in Offense" poison.
  static bool looksCollapsedIntoOneCategory(
    Map<String, dynamic>? bundle,
    String sport,
  ) {
    if (bundle == null) return false;
    final raw = bundle['verbOverrides'];
    if (raw is! Map || raw.length < 8) return false;
    final cats = <String>{};
    for (final value in raw.values) {
      if (value is Map) {
        final category = (value['category'] ?? '').toString().trim();
        if (category.isNotEmpty) cats.add(category);
      }
    }
    if (cats.length != 1) return false;
    final factoryCats = SportVerbCategories.forSport(sport)
        .entries
        .where((entry) => entry.value.any((label) => label.trim().isNotEmpty))
        .length;
    return factoryCats > 1;
  }

  /// Factory catalog plus any custom verbs / favorites from [bundle].
  static Map<String, dynamic> resetToFactoryPreservingCustoms(
    Map<String, dynamic>? bundle,
    String sport,
  ) {
    final next = buildFactory(sport);
    if (bundle == null) return next;
    next['customVerbs'] =
        ((bundle['customVerbs'] as List?) ?? const []).toList();
    next['favoriteVerbs'] =
        ((bundle['favoriteVerbs'] as List?) ?? const [])
            .map((value) => value.toString())
            .where((value) => (next['verbOverrides'] as Map).containsKey(value))
            .toList();
    next['favoriteTeams'] =
        ((bundle['favoriteTeams'] as List?) ?? const []).toList();
    next['customVerbWordings'] =
        Map<String, dynamic>.from((bundle['customVerbWordings'] as Map?) ?? {});
    return next;
  }

  /// Ensures [bundle] contains every factory verb as an override record and
  /// marks it [catalogCompleteKey]. Preserves existing edits.
  ///
  /// Phrase-key aliases (e.g. `battles against` → Battles) are folded onto the
  /// factory key and take the factory category so they cannot dump every verb
  /// into Offense.
  static Map<String, dynamic> ensureComplete(
    Map<String, dynamic> bundle,
    String sport,
  ) {
    if (looksCollapsedIntoOneCategory(bundle, sport)) {
      return resetToFactoryPreservingCustoms(bundle, sport);
    }

    final next = Map<String, dynamic>.from(bundle);
    final factory = buildFactory(sport);
    final factoryOverrides =
        Map<String, Map<String, dynamic>>.from(factory['verbOverrides'] as Map);
    final normalizedSport = sport.trim().toLowerCase();
    String remapCategory(String category) {
      if (normalizedSport == 'hockey' &&
          category.trim().toLowerCase() == 'reactions') {
        return 'Non Game-Action';
      }
      return category;
    }
    final factoryKeyByLower = <String, String>{
      for (final key in factoryOverrides.keys) key.toLowerCase(): key,
      // Renamed factory verbs (old key → current factory key).
      'pitching': 'Pitches',
      // Legacy phrase-keys that used to be stored as override ids (hockey).
      'battles against': 'Battles',
      'goes to the net against': 'Goes to the Net',
      'takes a faceoff': 'Faceoff',
      'blocks a shot': 'Blocks',
      'clears the puck': 'Clears',
      'makes a save': 'Saves',
      'guards the net': 'Guards the Net',
      'handles the puck': 'Handles the Puck',
      'stands in net': 'Stands in Net',
      'celebrates a goal': 'Celebrates a Goal',
      'celebrates after the win': 'Post Game Win',
      'reacts with dejection': 'Dejection',
      'reacts': 'Dejection',
      'on the bench': 'Bench',
      'stretches prior to play': 'Stretching',
      'takes the ice prior to play': 'Takes the Ice',
      'warms up prior to play': 'Warm Ups',
      'walks to the ice': 'Walks to the Ice',
      'looks on': 'Looks On',
      'looks on during the national anthem prior to play': 'National Anthem',
    };

    String? resolveFactoryKey(String key, Map<String, dynamic> record) {
      final direct = factoryKeyByLower[key.toLowerCase()];
      if (direct != null) return direct;
      final label = (record['label'] ?? '').toString().trim();
      if (label.isEmpty) return null;
      return factoryKeyByLower[label.toLowerCase()];
    }

    final overrides = <String, Map<String, dynamic>>{
      for (final entry in factoryOverrides.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };

    final rawOverrides = next['verbOverrides'];
    if (rawOverrides is Map) {
      final aliasEdits = <String, Map<String, dynamic>>{};
      final canonicalEdits = <String, Map<String, dynamic>>{};
      rawOverrides.forEach((rawKey, value) {
        if (value is! Map) return;
        final record = Map<String, dynamic>.from(value);
        final key = rawKey.toString();
        final factoryKey = resolveFactoryKey(key, record);
        if (factoryKey == null) {
          // Drop legacy phrase-key / junk overrides. Real user-created verbs
          // live in customVerbs; keeping these keys re-poisons Offense.
          return;
        }
        final canonical = key.toLowerCase() == factoryKey.toLowerCase();
        if (canonical) {
          canonicalEdits[factoryKey] = record;
        } else {
          aliasEdits[factoryKey] = record;
        }
      });

      for (final entry in aliasEdits.entries) {
        final factoryRecord = factoryOverrides[entry.key]!;
        final merged = Map<String, dynamic>.from(overrides[entry.key]!)
          ..addAll(entry.value);
        merged['key'] = entry.key;
        merged['label'] = factoryRecord['label'] ?? entry.key;
        final pinned = pinnedCategoryFor(next, entry.key, remapCategory);
        merged['category'] = (pinned != null && pinned.isNotEmpty)
            ? pinned
            : factoryRecord['category'];
        // Alias renames should pick up current factory keywords (e.g. pitches)
        // while keeping any extra custom keywords the user already had.
        final factoryKeywords = <String>{
          for (final value
              in ((factoryRecord['keywords'] as List?) ?? const []))
            value.toString().trim().toLowerCase(),
        }..removeWhere((value) => value.isEmpty);
        final existingKeywords = <String>{
          for (final value in ((merged['keywords'] as List?) ?? const []))
            value.toString().trim().toLowerCase(),
        }..removeWhere((value) => value.isEmpty);
        merged['keywords'] = {...factoryKeywords, ...existingKeywords}.toList();
        _normalizeOpponentFields(entry.key, merged);
        overrides[entry.key] = merged;
      }
      for (final entry in canonicalEdits.entries) {
        final factoryRecord = factoryOverrides[entry.key]!;
        final merged = Map<String, dynamic>.from(overrides[entry.key]!)
          ..addAll(entry.value);
        merged['key'] = entry.key;
        // Default: heal misfiled factory verbs back to factory categories.
        // Intentional admin/user moves are stored in [categoryOverrides] so
        // they survive persist/publish (plain `category` alone is not enough).
        final pinned = pinnedCategoryFor(next, entry.key, remapCategory);
        merged['category'] = (pinned != null && pinned.isNotEmpty)
            ? pinned
            : factoryRecord['category'];
        if ((merged['label'] ?? '').toString().trim().isEmpty) {
          merged['label'] = factoryRecord['label'] ?? entry.key;
        }
        _normalizeOpponentFields(entry.key, merged);
        overrides[entry.key] = merged;
      }
    }

    final categoryOrder = <String>[];
    final seenCategories = <String>{};
    void addCategory(String category) {
      if (category.trim().isEmpty || category == 'Favorites') return;
      if (seenCategories.add(category)) categoryOrder.add(category);
    }

    for (final value in ((factory['categoryOrder'] as List?) ?? const [])) {
      addCategory(value.toString());
    }
    for (final value in ((next['categoryOrder'] as List?) ?? const [])) {
      addCategory(remapCategory(value.toString()));
    }
    for (final record in overrides.values) {
      addCategory(remapCategory((record['category'] ?? '').toString()));
    }

    final verbOrder = <String, List<String>>{};
    final factoryOrder =
        Map<String, List<String>>.from(factory['verbOrder'] as Map);
    for (final entry in factoryOrder.entries) {
      verbOrder[entry.key] = List<String>.from(entry.value);
    }

    // Place each override under its category; factory keys start in factory order.
    final placed = <String>{};
    for (final entry in verbOrder.entries) {
      placed.addAll(entry.value);
    }
    for (final entry in overrides.entries) {
      if (placed.contains(entry.key)) {
        // If admin moved a factory verb, relocate it.
        final category =
            (entry.value['category'] ?? categoryOrder.first).toString();
        final factoryCategory =
            (factoryOverrides[entry.key]?['category'] ?? '').toString();
        if (factoryCategory.isNotEmpty && category != factoryCategory) {
          for (final list in verbOrder.values) {
            list.remove(entry.key);
          }
          verbOrder.putIfAbsent(category, () => <String>[]).add(entry.key);
        }
        continue;
      }
      final category =
          (entry.value['category'] ?? categoryOrder.first).toString();
      verbOrder.putIfAbsent(category, () => <String>[]).add(entry.key);
      placed.add(entry.key);
    }

    // Keep custom verbs in order (ensureComplete used to drop them).
    final customKeys = <String>{};
    final customCategory = <String, String>{};
    final rawCustoms = next['customVerbs'];
    if (rawCustoms is List) {
      for (final raw in rawCustoms) {
        if (raw is! Map) continue;
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        customKeys.add(key);
        final category =
            remapCategory((raw['category'] ?? '').toString().trim());
        if (category.isNotEmpty) customCategory[key] = category;
      }
    }
    final incomingOrder = next['verbOrder'];
    if (incomingOrder is Map) {
      for (final entry in incomingOrder.entries) {
        final category = remapCategory(entry.key.toString());
        final values = entry.value;
        if (values is! List) continue;
        for (final value in values) {
          final key = value.toString();
          if (!customKeys.contains(key) || placed.contains(key)) continue;
          verbOrder.putIfAbsent(category, () => <String>[]).add(key);
          placed.add(key);
        }
      }
    }
    for (final key in customKeys) {
      if (placed.contains(key)) continue;
      final category = customCategory[key] ??
          (categoryOrder.isEmpty ? 'Other' : categoryOrder.first);
      addCategory(category);
      verbOrder.putIfAbsent(category, () => <String>[]).add(key);
      placed.add(key);
    }

    next[catalogCompleteKey] = true;
    next['categoryOrder'] = categoryOrder;
    next['verbOrder'] = verbOrder;
    next['verbOverrides'] = overrides;
    // Normalize pinned moves; drop pins that match factory (no longer needed).
    final normalizedPins = <String, String>{};
    final rawPins = next['categoryOverrides'];
    if (rawPins is Map) {
      rawPins.forEach((rawKey, rawValue) {
        final key = rawKey.toString();
        if (!overrides.containsKey(key)) return;
        final pinned = remapCategory(rawValue?.toString().trim() ?? '');
        if (pinned.isEmpty) return;
        final factoryCategory =
            (factoryOverrides[key]?['category'] ?? '').toString();
        if (pinned == factoryCategory) return;
        normalizedPins[key] = pinned;
      });
    }
    next['categoryOverrides'] = normalizedPins;
    // Keep caller-supplied favorites for personal prefs merges; factory /
    // publish paths clear them via [withoutFavoriteVerbs].
    next['favoriteVerbs'] =
        ((next['favoriteVerbs'] as List?) ?? const []).toList();
    next['favoriteTeams'] =
        ((next['favoriteTeams'] as List?) ?? const []).toList();
    // Pitching → Pitches rename: migrate soft-deletes onto the new key so a
    // previously hidden Pitching verb stays hidden as Pitches.
    final deleted = <String>{
      for (final value in ((next['deletedVerbs'] as List?) ?? const []))
        value.toString(),
    };
    if (deleted.remove('Pitching')) deleted.add('Pitches');
    next['deletedVerbs'] = deleted.toList();
    next['customVerbs'] =
        ((next['customVerbs'] as List?) ?? const []).toList();
    next['verbWordingDefaults'] =
        Map<String, dynamic>.from((next['verbWordingDefaults'] as Map?) ?? {});
    next['customVerbWordings'] =
        Map<String, dynamic>.from((next['customVerbWordings'] as Map?) ?? {});
    return next;
  }

  /// Keep wantsOpponent / omitAgainst aligned with opponentJoiner text.
  /// Post Game Win/Loss stay opponent-free even when a legacy joiner remains.
  static void _normalizeOpponentFields(String key, Map<String, dynamic> merged) {
    if (key == 'Post Game Win' || key == 'Post Game Loss') {
      merged['wantsOpponent'] = false;
      return;
    }
    final joiner = (merged['opponentJoiner'] ?? 'against').toString().trim();
    if (joiner.isNotEmpty) {
      merged['opponentJoiner'] = joiner;
      merged['wantsOpponent'] = true;
      merged['omitAgainst'] = false;
    } else {
      merged['opponentJoiner'] = '';
      merged['wantsOpponent'] = false;
      merged['omitAgainst'] = true;
    }
  }

  static Map<String, dynamic> factoryVerbRecord(
    String key,
    String category,
    String sport,
  ) {
    final singular = VerbCaptionWording.defaultWording(key);
    final subOptions = VerbSubOptions.defaultsFor(key, sport: sport);
    final authoring = VerbAuthoringData.fromRecord(
      const {},
      verbLabel: key,
      sport: sport,
      fallbackPhrase: singular,
      subOptions: subOptions,
    );
    return {
      'key': key,
      'label': key,
      'category': category,
      'verbPhrase': singular,
      'pluralPhrase':
          VerbCaptionWording.defaultPluralWording(key, singular),
      'ingPhrase': VerbCaptionWording.defaultIngWording(key, singular),
      'usePluralPhrase': true,
      'keywords': defaultKeywordsForVerbLabel(key),
      'wantsOpponent': key != 'Post Game Win' && key != 'Post Game Loss',
      'omitAgainst': false,
      'opponentJoiner': 'against',
      'withTeammates': key == 'Celebrates a Goal',
      'isCustom': false,
      'subOptions': subOptions.toJson(),
      ...authoring.toRecordFields(),
    };
  }
}
