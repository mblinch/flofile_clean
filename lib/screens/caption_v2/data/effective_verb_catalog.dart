import '../../../caption_style/sport_verb_categories.dart';
import '../../../caption_style/verb_authoring_model.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_defaults_bundle.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../services/app_defaults_firestore_service.dart';
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
    required this.omitAgainst,
    required this.opponentJoiner,
    required this.withTeammates,
    required this.subOptions,
    required this.authoring,
    required this.hasAuthoredModifiers,
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
  /// Legacy: true when [opponentJoiner] is intentionally blank.
  final bool omitAgainst;
  /// Exact connector before the opponent (default `against`).
  final String opponentJoiner;
  /// First same-team pick is the subject; later same-team picks become "with …".
  final bool withTeammates;
  final VerbSubOptions subOptions;
  final VerbAuthoringData authoring;
  final bool hasAuthoredModifiers;
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
        catalogComplete: false,
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
    bool catalogComplete = false,
  }) {
    final factory = SportVerbCategories.copyForSport(sport);
    final records = <String, Map<String, dynamic>>{};
    final factoryCategory = <String, String>{};

    if (catalogComplete) {
      for (final entry in overrides.entries) {
        if (deletedVerbs.contains(entry.key)) continue;
        final category = (entry.value['category'] ??
                factoryCategory[entry.key] ??
                (categoryOrder.isNotEmpty ? categoryOrder.first : 'Other'))
            .toString();
        factoryCategory[entry.key] = category;
        records[entry.key] = {
          'label': entry.key,
          'category': category,
          if (customWordings[entry.key] != null)
            'verbPhrase': customWordings[entry.key],
          ...entry.value,
          'isCustom': false,
        };
      }
      // A published catalog can omit a verb the user already favorited.
      // Keep those factory verbs so they still show in Favorites.
      for (final entry in factory.entries) {
        for (final raw in entry.value) {
          final key = raw.trim();
          if (key.isEmpty ||
              records.containsKey(key) ||
              deletedVerbs.contains(key)) {
            continue;
          }
          final wanted = favorites.any(
            (favorite) => favorite.trim().toLowerCase() == key.toLowerCase(),
          );
          if (!wanted) continue;
          factoryCategory[key] = entry.key;
          records[key] = <String, dynamic>{
            'label': key,
            'category': entry.key,
            'verbPhrase': customWordings[key],
            'isCustom': false,
          };
        }
      }
    } else {
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
        if (!records.containsKey(entry.key) ||
            deletedVerbs.contains(entry.key)) {
          continue;
        }
        records[entry.key] = {
          ...records[entry.key]!,
          ...entry.value,
          'isCustom': false,
        };
      }
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

    String? resolveFavorite(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (records.containsKey(trimmed)) return trimmed;
      final lower = trimmed.toLowerCase();
      for (final entry in records.entries) {
        final label = (entry.value['label'] ?? '').toString().trim();
        if (entry.key.toLowerCase() == lower || label.toLowerCase() == lower) {
          return entry.key;
        }
        final phrase = (entry.value['verbPhrase'] ??
                customWordings[entry.key] ??
                VerbCaptionWording.defaultWording(entry.key))
            .toString()
            .trim();
        if (phrase.toLowerCase() == lower) return entry.key;
      }
      return null;
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
    if (!catalogComplete) {
      for (final category in factory.keys) {
        addCategory(category);
      }
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
        final trimmed = value.trim();
        if (trimmed.isEmpty) continue;
        final resolved = resolveFavorite(trimmed);
        final key = resolved ?? trimmed;
        if (!records.containsKey(key) ||
            categoryKeys.values.any((keys) => keys.contains(key))) {
          continue;
        }
        // Phrase aliases ("makes a save") must not pull a verb into a
        // different category than the one stored on the verb itself.
        if (resolved != null && resolved != trimmed) {
          final home = (records[key]!['category'] ??
                  factoryCategory[key] ??
                  '')
              .toString();
          if (home.isNotEmpty && home != entry.key) continue;
        }
        categoryKeys[entry.key]!.add(key);
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

    // Preserve favorites list order, including verbs parked under a
    // "Favorites" verb-order list and case-insensitive names like "runs".
    final favoriteKeyOrder = <String>[];
    final favoriteKeys = <String>{};
    void addFavorite(String? key) {
      if (key == null || key.isEmpty) return;
      if (!records.containsKey(key) || !favoriteKeys.add(key)) return;
      favoriteKeyOrder.add(key);
    }

    for (final raw in favorites) {
      addFavorite(resolveFavorite(raw));
    }
    for (final entry in verbOrder.entries) {
      if (entry.key.trim().toLowerCase() != 'favorites') continue;
      for (final value in entry.value) {
        addFavorite(resolveFavorite(value));
      }
    }
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
      final hasPlural = raw.containsKey('pluralPhrase');
      final savedPlural = (raw['pluralPhrase'] ?? '').toString().trim();
      final hasIng = raw.containsKey('ingPhrase');
      final savedIng = (raw['ingPhrase'] ?? '').toString().trim();
      final keywords = (raw['keywords'] is List)
          ? List<String>.from(raw['keywords'] as List)
          : defaultKeywordsForVerbLabel(entry.key);
      final subOptions = VerbSubOptions.fromJson(
        raw['subOptions'],
        verbLabel: entry.key,
        sport: sport,
      );
      // Respect intentional clears: empty stored plural stays empty. When plural
      // is disabled, fall back to singular so multi-player captions don't invent
      // a plural phrase.
      final resolvedPlural = !usePlural
          ? effectiveSingular
          : hasPlural
              ? savedPlural
              : VerbCaptionWording.defaultPluralWording(
                  entry.key,
                  effectiveSingular,
                );
      byKey[entry.key] = EffectiveVerb(
        key: entry.key,
        label: label.isEmpty ? entry.key : label,
        category: (raw['category'] ??
                factoryCategory[entry.key] ??
                (orderedCategories.isEmpty ? 'Other' : orderedCategories.first))
            .toString(),
        singularPhrase: effectiveSingular,
        pluralPhrase: resolvedPlural,
        ingPhrase: hasIng
            ? savedIng
            : VerbCaptionWording.defaultIngWording(
                entry.key,
                effectiveSingular,
              ),
        keywords: keywords,
        wantsOpponent: _wantsOpponentFromRecord(raw, entry.key),
        omitAgainst: raw['omitAgainst'] == true,
        opponentJoiner: _opponentJoinerFromRecord(raw),
        withTeammates: _withTeammatesFromRecord(raw, entry.key),
        subOptions: subOptions,
        authoring: VerbAuthoringData.fromRecord(
          raw,
          verbLabel: entry.key,
          sport: sport,
          fallbackPhrase: effectiveSingular,
          subOptions: subOptions,
        ),
        hasAuthoredModifiers: raw['modifierGroups'] is List,
        isCustom: raw['isCustom'] == true,
        isFavorite: favoriteKeys.contains(entry.key),
      );
    }

    // Favorites is a pinned virtual category (not stored in categoryOrder prefs).
    final effective = <String, List<EffectiveVerb>>{
      'Favorites': [
        for (final key in favoriteKeyOrder)
          if (byKey.containsKey(key)) byKey[key]!,
      ],
    };
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

  /// Prefer stored joiner text; legacy omitAgainst → blank; else `against`.
  static String _opponentJoinerFromRecord(Map raw) {
    if (raw.containsKey('opponentJoiner')) {
      return (raw['opponentJoiner'] ?? '').toString();
    }
    if (raw['wantsOpponent'] == false) return '';
    return raw['omitAgainst'] == true ? '' : 'against';
  }

  /// Explicit [withTeammates] wins. Legacy Celebrates a Goal always used
  /// lead-player + named "with …" teammates.
  static bool _withTeammatesFromRecord(Map raw, String key) {
    if (raw['withTeammates'] is bool) return raw['withTeammates'] as bool;
    return key == 'Celebrates a Goal';
  }

  /// Opponent joiner text is the source of truth for most verbs: a non-empty
  /// joiner (usually `against`) means attach an opponent clause. Post Game
  /// Win/Loss never take an opponent unless explicitly enabled.
  ///
  /// This also heals poisoned overrides that kept `opponentJoiner: against`
  /// while `wantsOpponent` was left `false` (e.g. Stands in Net, Walks to the
  /// Ice), which previously dropped the against-team clause.
  static bool _wantsOpponentFromRecord(Map raw, String key) {
    if (key == 'Post Game Win' || key == 'Post Game Loss') {
      return raw['wantsOpponent'] == true;
    }
    if (raw.containsKey('opponentJoiner')) {
      return (raw['opponentJoiner'] ?? '').toString().trim().isNotEmpty;
    }
    if (raw['wantsOpponent'] is bool) return raw['wantsOpponent'] as bool;
    return _opponentJoinerFromRecord(raw).trim().isNotEmpty;
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
      preferences.getVerbCatalogComplete(sport: sport),
    ]);
    var categoryOrder = values[0] as List<String>;
    var verbOrder = values[1] as Map<String, List<String>>;
    var favorites = values[2] as Set<String>;
    var customVerbs = values[3] as List<Map<String, dynamic>>;
    var customWordings = values[4] as Map<String, String>;
    var overrides = values[5] as Map<String, Map<String, dynamic>>;
    var deletedVerbs = values[6] as Set<String>;
    var catalogComplete = values[7] as bool;

    // Offline / first launch: prefer the cached Firebase catalog file over
    // the hardcoded factory seed when local prefs have never been seeded.
    if (!catalogComplete &&
        categoryOrder.isEmpty &&
        overrides.isEmpty &&
        customVerbs.isEmpty) {
      final cached =
          await AppDefaultsFirestoreService.getCachedSportVerbSettings(sport);
      if (cached != null && VerbDefaultsBundle.isComplete(cached)) {
        await preferences.importPreferences({
          'verbSettingsBySport': {sport: cached},
        });
        return load(sport);
      }
    }

    // Fold phrase-alias override keys (e.g. "battles against") and restore
    // factory categories so complete catalogs cannot dump junk into Offense.
    if (catalogComplete || overrides.isNotEmpty) {
      final beforeOverrides = {
        for (final entry in overrides.entries)
          entry.key: Map<String, dynamic>.from(entry.value),
      };
      final healed = VerbDefaultsBundle.ensureComplete(
        {
          VerbDefaultsBundle.catalogCompleteKey: catalogComplete,
          'categoryOrder': categoryOrder,
          'verbOrder': verbOrder,
          'favoriteVerbs': favorites.toList(),
          'customVerbs': customVerbs,
          'customVerbWordings': customWordings,
          'verbOverrides': overrides,
          'deletedVerbs': deletedVerbs.toList(),
        },
        sport,
      );
      final healedOverrides = <String, Map<String, dynamic>>{
        for (final entry
            in ((healed['verbOverrides'] as Map?) ?? const {}).entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
      final healedOrder = <String, List<String>>{
        for (final entry in ((healed['verbOrder'] as Map?) ?? const {}).entries)
          entry.key.toString(): [
            for (final value in ((entry.value as List?) ?? const []))
              value.toString(),
          ],
      };
      final healedCategories = [
        for (final value in ((healed['categoryOrder'] as List?) ?? const []))
          value.toString(),
      ];
      final changed = !_sameOverrideMaps(beforeOverrides, healedOverrides) ||
          !_sameStringListMap(verbOrder, healedOrder);

      categoryOrder = healedCategories;
      verbOrder = healedOrder;
      overrides = healedOverrides;
      deletedVerbs = {
        for (final value in ((healed['deletedVerbs'] as List?) ?? const []))
          value.toString(),
      };
      catalogComplete = true;

      if (changed) {
        await preferences.importPreferences({
          'verbSettingsBySport': {sport: healed},
        });
      }
    }

    return EffectiveVerbCatalog.merge(
      sport: sport,
      categoryOrder: categoryOrder,
      verbOrder: verbOrder,
      favorites: favorites,
      customVerbs: customVerbs,
      customWordings: customWordings,
      overrides: overrides,
      deletedVerbs: deletedVerbs,
      catalogComplete: catalogComplete,
    );
  }

  static bool _sameStringListMap(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.length != entry.value.length) return false;
      for (var i = 0; i < entry.value.length; i++) {
        if (other[i] != entry.value[i]) return false;
      }
    }
    return true;
  }

  static bool _sameOverrideMaps(
    Map<String, Map<String, dynamic>> a,
    Map<String, Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (!_sameJsonish(entry.value, other)) return false;
    }
    return true;
  }

  static bool _sameJsonish(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameJsonish(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameJsonish(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
