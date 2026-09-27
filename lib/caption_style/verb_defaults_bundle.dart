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
    };
  }

  /// Ensures [bundle] contains every factory verb as an override record and
  /// marks it [catalogCompleteKey]. Preserves existing edits.
  static Map<String, dynamic> ensureComplete(
    Map<String, dynamic> bundle,
    String sport,
  ) {
    final next = Map<String, dynamic>.from(bundle);
    final factory = buildFactory(sport);
    final overrides = <String, Map<String, dynamic>>{};
    final rawOverrides = next['verbOverrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        if (value is Map) {
          overrides[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
    }
    final factoryOverrides =
        Map<String, Map<String, dynamic>>.from(factory['verbOverrides'] as Map);
    for (final entry in factoryOverrides.entries) {
      overrides.putIfAbsent(entry.key, () => entry.value);
    }

    final categoryOrder = <String>[];
    final seenCategories = <String>{};
    void addCategory(String category) {
      if (category.trim().isEmpty || category == 'Favorites') return;
      if (seenCategories.add(category)) categoryOrder.add(category);
    }

    for (final value in ((next['categoryOrder'] as List?) ?? const [])) {
      addCategory(value.toString());
    }
    for (final value in ((factory['categoryOrder'] as List?) ?? const [])) {
      addCategory(value.toString());
    }
    for (final record in overrides.values) {
      addCategory((record['category'] ?? '').toString());
    }

    final verbOrder = <String, List<String>>{};
    final rawOrder = next['verbOrder'];
    if (rawOrder is Map) {
      rawOrder.forEach((key, value) {
        if (value is List) {
          verbOrder[key.toString()] = value
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList();
        }
      });
    }
    final factoryOrder =
        Map<String, List<String>>.from(factory['verbOrder'] as Map);
    for (final entry in factoryOrder.entries) {
      final existing = verbOrder[entry.key] ?? const <String>[];
      final merged = <String>[...existing];
      final seen = existing.toSet();
      for (final key in entry.value) {
        if (seen.add(key)) merged.add(key);
      }
      verbOrder[entry.key] = merged;
    }
    for (final entry in overrides.entries) {
      final category = (entry.value['category'] ?? categoryOrder.first).toString();
      final list = verbOrder.putIfAbsent(category, () => <String>[]);
      if (!list.contains(entry.key)) list.add(entry.key);
    }

    next[catalogCompleteKey] = true;
    next['categoryOrder'] = categoryOrder;
    next['verbOrder'] = verbOrder;
    next['verbOverrides'] = overrides;
    next['favoriteVerbs'] =
        ((next['favoriteVerbs'] as List?) ?? const []).toList();
    next['favoriteTeams'] =
        ((next['favoriteTeams'] as List?) ?? const []).toList();
    next['deletedVerbs'] =
        ((next['deletedVerbs'] as List?) ?? const []).toList();
    next['customVerbs'] =
        ((next['customVerbs'] as List?) ?? const []).toList();
    next['verbWordingDefaults'] =
        Map<String, dynamic>.from((next['verbWordingDefaults'] as Map?) ?? {});
    next['customVerbWordings'] =
        Map<String, dynamic>.from((next['customVerbWordings'] as Map?) ?? {});
    return next;
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
      'isCustom': false,
      'subOptions': subOptions.toJson(),
      ...authoring.toRecordFields(),
    };
  }
}
