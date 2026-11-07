import '../../../caption_style/sport_verb_categories.dart';
import '../../../caption_style/verb_authoring_model.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_defaults_bundle.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../services/preferences_service.dart';
import '../../../services/verb_user_catalog_service.dart';
import '../../../utils/default_verb_keywords.dart';

class EffectiveVerb {
  const EffectiveVerb({
    required this.key,
    required this.label,
    required this.category,
    required this.categories,
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
  /// Primary / home category (edit target, single-category fallback).
  final String category;
  /// Every category this verb appears under (one or more).
  final List<String> categories;
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
    Set<String> hiddenCategories = const {},
    bool catalogComplete = false,
  }) {
    final factory = SportVerbCategories.copyForSport(sport);
    final records = <String, Map<String, dynamic>>{};
    final factoryCategory = <String, String>{};
    // Hockey no longer ships a Reactions category (baseball leftover).
    // Remap saved prefs that still point at Reactions → Non Game-Action.
    final normalizedSport = sport.trim().toLowerCase();
    String remapCategory(String category) {
      if (normalizedSport == 'hockey' &&
          category.trim().toLowerCase() == 'reactions') {
        return 'Non Game-Action';
      }
      return category;
    }

    final deletedLower = {
      for (final value in deletedVerbs) value.trim().toLowerCase(),
    };
    bool isDeleted(String key) {
      final trimmed = key.trim();
      if (trimmed.isEmpty) return false;
      return deletedVerbs.contains(trimmed) ||
          deletedLower.contains(trimmed.toLowerCase());
    }

    // Shipped verbs always start from the factory lists. A complete catalog
    // used to show only whatever was already in verbOverrides, which hid
    // every default the override map had not stored yet.
    for (final entry in factory.entries) {
      for (final raw in entry.value) {
        final key = raw.trim();
        if (key.isEmpty || isDeleted(key)) continue;
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
      if (isDeleted(entry.key)) continue;
      if (!records.containsKey(entry.key)) {
        // User-created verbs belong in customVerbs. Ignore stray override keys.
        continue;
      }
      final merged = {
        ...records[entry.key]!,
        ...entry.value,
        'isCustom': false,
      };
      if (merged['category'] != null) {
        merged['category'] = remapCategory(merged['category'].toString());
      }
      records[entry.key] = merged;
    }

    for (final raw in customVerbs) {
      final label = (raw['label'] ?? raw['verbPhrase'] ?? '').toString().trim();
      if (label.isEmpty || isDeleted(label)) continue;
      final category = raw['category'] == null
          ? null
          : remapCategory(raw['category'].toString());
      records[label] = {
        ...raw,
        'label': label,
        if (category != null) 'category': category,
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
                VerbCaptionWording.defaultWording(entry.key, sport: sport))
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
          category != 'All' &&
          !orderedCategories.contains(category)) {
        orderedCategories.add(category);
      }
    }

    final savedCategories = <String>{
      for (final category in categoryOrder) remapCategory(category),
    };
    final hiddenCategoryNames = <String>{
      for (final category in hiddenCategories) category.trim().toLowerCase(),
    };
    bool isHiddenCategory(String category) =>
        hiddenCategoryNames.contains(category.trim().toLowerCase());
    for (final category in categoryOrder) {
      addCategory(remapCategory(category));
    }
    if (!catalogComplete) {
      for (final category in factory.keys) {
        addCategory(category);
      }
    }
    for (final record in records.values) {
      addCategory(remapCategory((record['category'] ?? '').toString()));
    }

    final categoryKeys = <String, List<String>>{
      for (final category in orderedCategories) category: <String>[],
    };

    List<String> categoriesForRecord(Map<String, dynamic> raw, String fallback) {
      final fromList = <String>[];
      final rawList = raw['categories'];
      if (rawList is List) {
        for (final value in rawList) {
          final category = remapCategory(value.toString().trim());
          if (category.isEmpty ||
              category == 'Favorites' ||
              category == 'All') {
            continue;
          }
          if (!fromList.contains(category)) fromList.add(category);
        }
      }
      if (fromList.isNotEmpty) return fromList;
      final single = remapCategory((raw['category'] ?? fallback).toString());
      if (single.isEmpty || single == 'Favorites' || single == 'All') {
        return const [];
      }
      return [single];
    }

    void placeKey(String category, String key) {
      if (category.isEmpty || key.isEmpty) return;
      addCategory(category);
      final list = categoryKeys.putIfAbsent(category, () => <String>[]);
      if (!list.contains(key)) list.add(key);
    }

    for (final entry in verbOrder.entries) {
      final orderCategory = remapCategory(entry.key);
      if (!categoryKeys.containsKey(orderCategory) &&
          orderCategory != 'Favorites' &&
          orderCategory != 'All' &&
          orderCategory.isNotEmpty) {
        // Allow verbOrder to introduce a saved category before records do.
        addCategory(orderCategory);
        categoryKeys.putIfAbsent(orderCategory, () => <String>[]);
      }
      if (!categoryKeys.containsKey(orderCategory)) continue;
      for (final value in entry.value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) continue;
        final resolved = resolveFavorite(trimmed);
        final key = resolved ?? trimmed;
        if (!records.containsKey(key)) continue;
        if (categoryKeys[orderCategory]!.contains(key)) continue;
        // Phrase aliases ("makes a save") must not pull a verb into a
        // different category than the one stored on the verb itself — unless
        // the verb explicitly lists that category in [categories].
        if (resolved != null && resolved != trimmed) {
          final declared = categoriesForRecord(
            records[key]!,
            factoryCategory[key] ?? '',
          );
          if (declared.isNotEmpty && !declared.contains(orderCategory)) {
            continue;
          }
          if (declared.isEmpty) {
            final home = remapCategory((records[key]!['category'] ??
                    factoryCategory[key] ??
                    '')
                .toString());
            if (home.isNotEmpty && home != orderCategory) continue;
          }
        }
        placeKey(orderCategory, key);
      }
    }
    for (final entry in records.entries) {
      final fallbackCategory =
          orderedCategories.isEmpty ? 'Other' : orderedCategories.first;
      final declared = categoriesForRecord(
        entry.value,
        factoryCategory[entry.key] ?? fallbackCategory,
      );
      if (declared.length > 1) {
        // Explicit multi-category verbs appear in every listed bucket.
        for (final category in declared) {
          placeKey(category, entry.key);
        }
        continue;
      }
      if (categoryKeys.values.any((keys) => keys.contains(entry.key))) {
        continue;
      }
      final category = declared.isEmpty ? fallbackCategory : declared.first;
      placeKey(category, entry.key);
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
      final baseballSingular = VerbCaptionWording.defaultWording(entry.key);
      final sportSingular =
          VerbCaptionWording.defaultWording(entry.key, sport: sport);
      final effectiveSingular = _wordingForSport(
        stored: singular,
        applyDefault: singular.isEmpty,
        sport: sport,
        baseballDefault: baseballSingular,
        sportDefault: sportSingular,
      );
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
      final baseballPlural = VerbCaptionWording.defaultPluralWording(
        entry.key,
        effectiveSingular,
      );
      final sportPlural = VerbCaptionWording.defaultPluralWording(
        entry.key,
        effectiveSingular,
        sport: sport,
      );
      final resolvedPlural = !usePlural
          ? effectiveSingular
          : _wordingForSport(
              stored: hasPlural ? savedPlural : '',
              applyDefault: !hasPlural,
              sport: sport,
              baseballDefault: baseballPlural,
              sportDefault: sportPlural,
            );
      final fallbackCategory =
          orderedCategories.isEmpty ? 'Other' : orderedCategories.first;
      final placedCategories = <String>[
        for (final category in orderedCategories)
          if ((categoryKeys[category] ?? const <String>[]).contains(entry.key))
            category,
      ];
      final declaredCategories = categoriesForRecord(
        raw,
        factoryCategory[entry.key] ?? fallbackCategory,
      );
      final effectiveCategories = placedCategories.isNotEmpty
          ? placedCategories
          : (declaredCategories.isNotEmpty
              ? declaredCategories
              : [fallbackCategory]);
      final primaryCategory = remapCategory((raw['category'] ??
              factoryCategory[entry.key] ??
              effectiveCategories.first)
          .toString());
      byKey[entry.key] = EffectiveVerb(
        key: entry.key,
        label: label.isEmpty ? entry.key : label,
        category: primaryCategory.isNotEmpty
            ? primaryCategory
            : effectiveCategories.first,
        categories: List.unmodifiable(effectiveCategories),
        singularPhrase: effectiveSingular,
        pluralPhrase: resolvedPlural,
        ingPhrase: _wordingForSport(
          stored: hasIng ? savedIng : '',
          applyDefault: !hasIng,
          sport: sport,
          baseballDefault: VerbCaptionWording.defaultIngWording(
            entry.key,
            effectiveSingular,
          ),
          sportDefault: VerbCaptionWording.defaultIngWording(
            entry.key,
            effectiveSingular,
            sport: sport,
          ),
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

    // Favorites and All are virtual categories (not stored in categoryOrder).
    final allVerbs = <EffectiveVerb>[];
    final seenInAll = <String>{};
    for (final category in orderedCategories) {
      if (isHiddenCategory(category)) continue;
      for (final key in categoryKeys[category] ?? const <String>[]) {
        final verb = byKey[key];
        if (verb != null && seenInAll.add(verb.key)) allVerbs.add(verb);
      }
    }
    allVerbs.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    final effective = <String, List<EffectiveVerb>>{
      'Favorites': [
        for (final key in favoriteKeyOrder)
          if (byKey.containsKey(key)) byKey[key]!,
      ],
    };
    for (final category in orderedCategories) {
      final verbs = [
        for (final key in categoryKeys[category] ?? const <String>[])
          if (byKey.containsKey(key)) byKey[key]!,
      ];
      // Drop empty leftover categories (e.g. old hockey "Reactions" prefs).
      // Categories the user saved, including a new empty one, stay visible.
      if (verbs.isEmpty && !savedCategories.contains(category)) continue;
      if (isHiddenCategory(category)) continue;
      effective[category] = verbs;
    }
    effective['All'] = allVerbs;
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

  /// A joiner is only the connector word. Blank still attaches the opposing
  /// team (`scores the Ottawa Senators`). Post Game Win/Loss never take an
  /// opponent unless explicitly enabled.
  ///
  /// Records that stored `opponentJoiner: against` with `wantsOpponent: false`
  /// (e.g. Stands in Net) are healed the same way: the team clause stays.
  static bool _wantsOpponentFromRecord(Map raw, String key) {
    if (key == 'Post Game Win' || key == 'Post Game Loss') {
      return raw['wantsOpponent'] == true;
    }
    if (raw.containsKey('opponentJoiner')) return true;
    if (raw['wantsOpponent'] is bool) return raw['wantsOpponent'] as bool;
    return true;
  }
}

/// Empty wording uses the sport default. A stored baseball base phrase
/// ("runs to a base") on another sport is treated as that leftover default.
String _wordingForSport({
  required String stored,
  required bool applyDefault,
  required String sport,
  required String baseballDefault,
  required String sportDefault,
}) {
  if (!applyDefault) {
    if (!VerbSubOptions.isBaseballSport(sport) &&
        stored.trim().isNotEmpty &&
        stored.trim() == baseballDefault) {
      return sportDefault;
    }
    return stored;
  }
  return VerbSubOptions.isBaseballSport(sport) ? baseballDefault : sportDefault;
}

class EffectiveVerbRepository {
  EffectiveVerbRepository(this.preferences);

  final PreferencesService preferences;

  Future<EffectiveVerbCatalog> load(String sport) async {
    final bundle = await VerbUserCatalogService.loadMergedBundle(
      prefs: preferences,
      sport: sport,
    );
    return EffectiveVerbRepository.fromBundle(sport: sport, bundle: bundle);
  }

  /// Live catalog from an editor bundle, before prefs have been re-read.
  static EffectiveVerbCatalog fromBundle({
    required String sport,
    required Map<String, dynamic> bundle,
  }) {
    final complete = VerbDefaultsBundle.ensureComplete(
      Map<String, dynamic>.from(bundle),
      sport,
    );
    List<String> strings(Object? raw) => [
          for (final value in ((raw as List?) ?? const [])) value.toString(),
        ];
    Map<String, List<String>> stringListMap(Object? raw) {
      if (raw is! Map) return {};
      return {
        for (final entry in raw.entries)
          entry.key.toString(): strings(entry.value),
      };
    }

    final customVerbs = <Map<String, dynamic>>[
      for (final raw in ((complete['customVerbs'] as List?) ?? const []))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
    final overrides = <String, Map<String, dynamic>>{};
    final rawOverrides = complete['verbOverrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        if (value is Map) {
          overrides[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
    }
    final wordings = <String, String>{};
    final rawWordings = complete['customVerbWordings'];
    if (rawWordings is Map) {
      rawWordings.forEach((key, value) {
        final text = value?.toString() ?? '';
        if (text.isNotEmpty) wordings[key.toString()] = text;
      });
    }
    return EffectiveVerbCatalog.merge(
      sport: sport,
      categoryOrder: strings(complete['categoryOrder']),
      verbOrder: stringListMap(complete['verbOrder']),
      favorites: strings(complete['favoriteVerbs']).toSet(),
      customVerbs: customVerbs,
      customWordings: wordings,
      overrides: overrides,
      deletedVerbs: strings(complete['deletedVerbs']).toSet(),
      hiddenCategories: strings(complete['hiddenCategories']).toSet(),
      catalogComplete: VerbDefaultsBundle.isComplete(complete),
    );
  }
}
