import '../../../caption_style/sport_verb_categories.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../services/preferences_service.dart';
import '../../../utils/default_verb_keywords.dart';

class EffectiveVerb {
  const EffectiveVerb({
    required this.key,
    required this.label,
    required this.category,
    required this.singularPhrase,
    required this.pluralPhrase,
    required this.ingPhrase,
    required this.keywords,
    required this.wantsOpponent,
    required this.subOptions,
    required this.isCustom,
    required this.isFavorite,
  });

  final String key;
  final String label;
  final String category;
  final String singularPhrase;
  final String pluralPhrase;
  final String ingPhrase;
  final List<String> keywords;
  final bool wantsOpponent;
  final VerbSubOptions subOptions;
  final bool isCustom;
  final bool isFavorite;
}

class EffectiveVerbCatalog {
  const EffectiveVerbCatalog({
    required this.sport,
    required this.categoryOrder,
    required this.verbsByCategory,
    required this.byKey,
    required this.favoriteKeys,
  });

  final String sport;
  final List<String> categoryOrder;
  final Map<String, List<EffectiveVerb>> verbsByCategory;
  final Map<String, EffectiveVerb> byKey;
  final Set<String> favoriteKeys;

  static EffectiveVerbCatalog factory(String sport) => merge(
        sport: sport,
        categoryOrder: const [],
        verbOrder: const {},
        favorites: const {},
        customVerbs: const [],
        customWordings: const {},
        overrides: const {},
        deletedVerbs: const {},
      );

  static EffectiveVerbCatalog merge({
    required String sport,
    required List<String> categoryOrder,
    required Map<String, List<String>> verbOrder,
    required Set<String> favorites,
    required List<Map<String, dynamic>> customVerbs,
    required Map<String, String> customWordings,
    required Map<String, Map<String, dynamic>> overrides,
    required Set<String> deletedVerbs,
  }) {
    final factory = SportVerbCategories.copyForSport(sport);
    final records = <String, Map<String, dynamic>>{};
    final factoryCategory = <String, String>{};

    for (final entry in factory.entries) {
      for (final raw in entry.value) {
        final key = raw.trim();
        if (key.isEmpty || deletedVerbs.contains(key)) continue;
        factoryCategory[key] = entry.key;
        records[key] = <String, dynamic>{
          'label': key,
          'category': entry.key,
          'verbPhrase': customWordings[key],
          'isCustom': false,
        };
      }
    }

    for (final entry in overrides.entries) {
      if (!records.containsKey(entry.key) || deletedVerbs.contains(entry.key)) {
        continue;
      }
      records[entry.key] = {
        ...records[entry.key]!,
        ...entry.value,
        'isCustom': false,
      };
    }

    for (final raw in customVerbs) {
      final label = (raw['label'] ?? raw['verbPhrase'] ?? '').toString().trim();
      if (label.isEmpty || deletedVerbs.contains(label)) continue;
      records[label] = {
        ...raw,
        'label': label,
        'isCustom': true,
      };
    }

    String resolveKey(String value) {
      if (records.containsKey(value)) return value;
      for (final entry in records.entries) {
        if ((entry.value['label'] ?? '').toString() == value) return entry.key;
      }
      return value;
    }

    final orderedCategories = <String>[];
    void addCategory(String category) {
      if (category.isNotEmpty &&
          category != 'Favorites' &&
          !orderedCategories.contains(category)) {
        orderedCategories.add(category);
      }
    }

    for (final category in categoryOrder) {
      addCategory(category);
    }
    for (final category in factory.keys) {
      addCategory(category);
    }
    for (final record in records.values) {
      addCategory((record['category'] ?? '').toString());
    }

    final categoryKeys = <String, List<String>>{
      for (final category in orderedCategories) category: <String>[],
    };
    for (final entry in verbOrder.entries) {
      if (!categoryKeys.containsKey(entry.key)) continue;
      for (final value in entry.value) {
        final key = resolveKey(value);
        if (records.containsKey(key) &&
            !categoryKeys.values.any((keys) => keys.contains(key))) {
          categoryKeys[entry.key]!.add(key);
        }
      }
    }
    for (final entry in records.entries) {
      if (categoryKeys.values.any((keys) => keys.contains(entry.key))) continue;
      final fallbackCategory =
          orderedCategories.isEmpty ? 'Other' : orderedCategories.first;
      final category = (entry.value['category'] ??
              factoryCategory[entry.key] ??
              fallbackCategory)
          .toString();
      categoryKeys.putIfAbsent(category, () => <String>[]).add(entry.key);
      addCategory(category);
    }

    final favoriteKeys =
        favorites.map(resolveKey).where(records.containsKey).toSet();
    final byKey = <String, EffectiveVerb>{};
    for (final entry in records.entries) {
      final raw = entry.value;
      final label = (raw['label'] ?? entry.key).toString().trim();
      final singular = (raw['verbPhrase'] ?? customWordings[entry.key] ?? '')
          .toString()
          .trim();
      final effectiveSingular = singular.isEmpty
          ? VerbCaptionWording.defaultWording(entry.key)
          : singular;
      final usePlural = raw['usePluralPhrase'] != false;
      final savedPlural = (raw['pluralPhrase'] ?? '').toString().trim();
      final savedIng = (raw['ingPhrase'] ?? '').toString().trim();
      final keywords = (raw['keywords'] is List)
          ? List<String>.from(raw['keywords'] as List)
          : defaultKeywordsForVerbLabel(entry.key);
      byKey[entry.key] = EffectiveVerb(
        key: entry.key,
        label: label.isEmpty ? entry.key : label,
        category: (raw['category'] ??
                factoryCategory[entry.key] ??
                (orderedCategories.isEmpty ? 'Other' : orderedCategories.first))
            .toString(),
        singularPhrase: effectiveSingular,
        pluralPhrase: usePlural && savedPlural.isNotEmpty
            ? savedPlural
            : VerbCaptionWording.defaultPluralWording(
                entry.key,
                effectiveSingular,
              ),
        ingPhrase: savedIng.isNotEmpty
            ? savedIng
            : VerbCaptionWording.defaultIngWording(
                entry.key,
                effectiveSingular,
              ),
        keywords: keywords,
        wantsOpponent: raw['wantsOpponent'] is bool
            ? raw['wantsOpponent'] as bool
            : entry.key != 'Post Game Win' && entry.key != 'Post Game Loss',
        subOptions: VerbSubOptions.fromJson(
          raw['subOptions'],
          verbLabel: entry.key,
          sport: sport,
        ),
        isCustom: raw['isCustom'] == true,
        isFavorite: favoriteKeys.contains(entry.key),
      );
    }

    final effective = <String, List<EffectiveVerb>>{};
    if (favoriteKeys.isNotEmpty) {
      effective['Favorites'] = [
        for (final category in orderedCategories)
          for (final key in categoryKeys[category] ?? const <String>[])
            if (favoriteKeys.contains(key)) byKey[key]!,
      ];
    }
    for (final category in orderedCategories) {
      effective[category] = [
        for (final key in categoryKeys[category] ?? const <String>[])
          if (byKey.containsKey(key)) byKey[key]!,
      ];
    }
    return EffectiveVerbCatalog(
      sport: sport,
      categoryOrder: List.unmodifiable(effective.keys),
      verbsByCategory: Map.unmodifiable(effective),
      byKey: Map.unmodifiable(byKey),
      favoriteKeys: Set.unmodifiable(favoriteKeys),
    );
  }
}

class EffectiveVerbRepository {
  EffectiveVerbRepository(this.preferences);

  final PreferencesService preferences;

  Future<EffectiveVerbCatalog> load(String sport) async {
    final values = await Future.wait<dynamic>([
      preferences.getCategoryOrder(sport: sport),
      preferences.getVerbOrder(sport: sport),
      preferences.getFavoriteVerbs(sport: sport),
      preferences.getCustomVerbs(sport: sport),
      preferences.getCustomVerbWordings(sport: sport),
      preferences.getVerbOverrides(sport: sport),
      preferences.getDeletedVerbs(sport: sport),
    ]);
    return EffectiveVerbCatalog.merge(
      sport: sport,
      categoryOrder: values[0] as List<String>,
      verbOrder: values[1] as Map<String, List<String>>,
      favorites: values[2] as Set<String>,
      customVerbs: values[3] as List<Map<String, dynamic>>,
      customWordings: values[4] as Map<String, String>,
      overrides: values[5] as Map<String, Map<String, dynamic>>,
      deletedVerbs: values[6] as Set<String>,
    );
  }
}
