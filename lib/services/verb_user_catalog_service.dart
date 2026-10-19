import '../caption_style/verb_defaults_bundle.dart';
import 'app_defaults_firestore_service.dart';
import 'preferences_service.dart';

/// Loads / saves a sport verb catalog for personal (per-user) editing.
///
/// Merges app-default catalog with the user's prefs. Persisting writes only to
/// [PreferencesService] (which syncs to `users/{uid}/preferences/current`) and
/// never to app-default Firebase originals.
List<Map<String, dynamic>> _verbRecordList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

bool _hockeyTextBanned(Object? value) {
  const phrase = 'skates like an animal';
  if (value is String) return value.toLowerCase().contains(phrase);
  if (value is Map) {
    for (final entry in value.entries) {
      if (_hockeyTextBanned(entry.key) || _hockeyTextBanned(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    for (final item in value) {
      if (_hockeyTextBanned(item)) return true;
    }
  }
  return false;
}

class VerbUserCatalogService {
  VerbUserCatalogService._();

  static Future<Map<String, dynamic>> loadMergedBundle({
    required PreferencesService prefs,
    required String sport,
  }) async {
    final cached =
        await AppDefaultsFirestoreService.getCachedSportVerbSettings(sport);
    final publishedCategories = <String>[
      for (final value in ((cached?['categoryOrder'] as List?) ?? const []))
        value.toString(),
    ];
    final publishedDefaults = <String>[
      for (final value in ((cached?['defaultCategories'] as List?) ?? const []))
        value.toString(),
    ];
    final publishedPins = <String, String>{
      for (final entry
          in ((cached?['categoryOverrides'] as Map?) ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    };
    final base = cached != null && cached.isNotEmpty
        ? VerbDefaultsBundle.ensureComplete(
            Map<String, dynamic>.from(cached),
            sport,
          )
        : VerbDefaultsBundle.buildFactory(sport);

    final localCustoms = await prefs.getCustomVerbs(sport: sport);
    final hasLocalCustoms = await prefs.hasLocalCustomVerbs(sport: sport);
    final localDeleted = await prefs.getDeletedVerbs(sport: sport);
    final localFavorites = await prefs.getFavoriteVerbs(sport: sport);
    final localOrder = await prefs.getVerbOrder(sport: sport);
    final localOverrides = await prefs.getVerbOverrides(sport: sport);
    final localCategoryOverrides =
        await prefs.getVerbCategoryOverrides(sport: sport);
    final localHidden = await prefs.getHiddenCategories(sport: sport);

    final deleted = <String>{
      for (final value in ((base['deletedVerbs'] as List?) ?? const []))
        value.toString(),
      ...localDeleted.map((value) => value.toString()),
    };
    // "Fuck" (key "Untitled verb 2") and any "skates like an animal" wording
    // were removed from the shared hockey catalog. Older accounts still have
    // them in local custom verbs and overrides.
    if (sport.trim().toLowerCase() == 'hockey') {
      deleted.add('Untitled verb 2');
      deleted.add('Fuck');
      for (final raw in [
        ...((base['customVerbs'] as List?) ?? const []),
        ...localCustoms,
      ]) {
        if (raw is! Map) continue;
        if (!_hockeyTextBanned(raw)) continue;
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        final label = (raw['label'] ?? '').toString().trim();
        if (key.isNotEmpty) deleted.add(key);
        if (label.isNotEmpty) deleted.add(label);
      }
    }
    // getSportDefault prefers the published catalog, whose deleted list
    // includes verbs this device still has in its own saved catalog.
    // "Hops the Boards" is one of those: shared hockey deleted it, so the
    // name stayed taken and the saved verb never appeared.
    final storedDefault = await prefs.getStoredSportDefault(sport);
    final storedCustoms = _verbRecordList(storedDefault?['customVerbs']);
    final personalCustoms =
        hasLocalCustoms ? localCustoms : storedCustoms;
    final personalDeleted = <String>{
      if (await prefs.hasExplicitDeletedVerbs(sport: sport))
        ...localDeleted
      else
        for (final value
            in ((storedDefault?['deletedVerbs'] as List?) ?? const []))
          value.toString(),
    };
    final personalDeletedLower = {
      for (final value in personalDeleted) value.trim().toLowerCase(),
    };
    bool personallyDeleted(String value) {
      final trimmed = value.trim().toLowerCase();
      return trimmed.isNotEmpty && personalDeletedLower.contains(trimmed);
    }

    for (final raw in personalCustoms) {
      if (sport.trim().toLowerCase() == 'hockey' && _hockeyTextBanned(raw)) {
        continue;
      }
      final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
      final label = (raw['label'] ?? '').toString().trim();
      final phrase = (raw['verbPhrase'] ?? '').toString().trim();
      if (personallyDeleted(key) ||
          personallyDeleted(label) ||
          personallyDeleted(phrase)) {
        continue;
      }
      deleted.removeWhere((value) {
        final lower = value.trim().toLowerCase();
        return lower == key.toLowerCase() ||
            (label.isNotEmpty && lower == label.toLowerCase()) ||
            (phrase.isNotEmpty && lower == phrase.toLowerCase());
      });
    }
    final deletedLower = {
      for (final value in deleted) value.trim().toLowerCase(),
    };
    bool isDeleted(String key) {
      final trimmed = key.trim();
      if (trimmed.isEmpty) return false;
      return deleted.contains(trimmed) ||
          deletedLower.contains(trimmed.toLowerCase());
    }

    bool customRecordDeleted(Map raw) {
      final key = (raw['key'] ?? '').toString();
      final label = (raw['label'] ?? '').toString();
      final phrase = (raw['verbPhrase'] ?? '').toString();
      return isDeleted(key) ||
          isDeleted(label) ||
          isDeleted(phrase) ||
          (sport.trim().toLowerCase() == 'hockey' && _hockeyTextBanned(raw));
    }

    // Published customs first, then the user's copies. A verb only in app
    // defaults (and not deleted) still shows. The local copy wins when both
    // exist. [hasLocalCustoms] still marks that a local file was read.
    final customsByKey = <String, Map<String, dynamic>>{};
    for (final raw in ((base['customVerbs'] as List?) ?? const [])) {
      if (raw is! Map) continue;
      final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
      if (key.isEmpty || customRecordDeleted(raw)) continue;
      customsByKey[key] = Map<String, dynamic>.from(raw);
    }
    if (hasLocalCustoms || localCustoms.isNotEmpty) {
      for (final raw in localCustoms) {
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        if (key.isEmpty || customRecordDeleted(raw)) continue;
        customsByKey[key] = Map<String, dynamic>.from(raw);
      }
    }
    for (final raw in personalCustoms) {
      final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
      if (key.isEmpty || customRecordDeleted(raw)) continue;
      customsByKey[key] = Map<String, dynamic>.from(raw);
    }
    base['customVerbs'] = customsByKey.values.toList();

    final overrides = Map<String, dynamic>.from(
      (base['verbOverrides'] as Map?) ?? const {},
    );
    localOverrides.forEach((key, value) {
      overrides[key] = Map<String, dynamic>.from(value);
    });
    overrides.removeWhere((key, value) {
      if (isDeleted(key)) return true;
      if (sport.trim().toLowerCase() != 'hockey') return false;
      return _hockeyTextBanned(value) || _hockeyTextBanned(key);
    });
    base['verbOverrides'] = overrides;
    if (sport.trim().toLowerCase() == 'hockey') {
      final wordings = base['customVerbWordings'];
      if (wordings is Map) {
        wordings.removeWhere(
          (key, value) =>
              _hockeyTextBanned(key) || _hockeyTextBanned(value),
        );
      }
    }
    // Local pins win, but a published move (Pre-Game, Post-Game, …) stays
    // when this device never stored that pin.
    final pins = Map<String, String>.from(publishedPins);
    localCategoryOverrides.forEach((key, value) {
      final category = value.trim();
      if (category.isEmpty) return;
      pins[key] = category;
    });
    base['categoryOverrides'] = pins;

    base['deletedVerbs'] = deleted.toList();

    // Favorites are personal — never inherit starred verbs from app defaults.
    base['favoriteVerbs'] = localFavorites.toList();

    final order = <String, List<String>>{};
    final catalogOrder = base['verbOrder'];
    if (catalogOrder is Map) {
      catalogOrder.forEach((key, value) {
        order[key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : <String>[];
      });
    }
    localOrder.forEach((category, keys) {
      final list = order.putIfAbsent(category, () => <String>[]);
      for (final key in keys) {
        if (!list.contains(key)) list.add(key);
      }
    });
    // Drop tombstoned keys from order lists so they can't linger in the UI.
    for (final entry in order.entries) {
      entry.value.removeWhere(isDeleted);
    }
    base['verbOrder'] = order;

    final categories = await prefs.getCategoryOrder(sport: sport);
    // Saved drag order comes first. Categories that exist only on the
    // published catalog are appended, so a new default category is not
    // erased by an older local list.
    final mergedCategories = <String>[];
    final seenCategories = <String>{};
    void addCategory(String category) {
      final name = category.trim();
      if (name.isEmpty || name == 'Favorites' || name == 'All') return;
      if (seenCategories.add(name)) mergedCategories.add(name);
    }

    for (final category in categories) {
      addCategory(category);
    }
    for (final category in publishedCategories) {
      addCategory(category);
    }
    if (mergedCategories.isNotEmpty) {
      base['categoryOrder'] = mergedCategories;
    }

    final defaults = <String>[];
    final seenDefaults = <String>{};
    void addDefault(String category) {
      final name = category.trim();
      if (name.isEmpty || name == 'Favorites' || name == 'All') return;
      if (seenDefaults.add(name.toLowerCase())) defaults.add(name);
    }

    final explicitDefaults =
        publishedDefaults.isNotEmpty ? publishedDefaults : publishedCategories;
    for (final category in explicitDefaults) {
      addDefault(category);
    }
    base['defaultCategories'] = defaults;
    final defaultNames = seenDefaults;
    base['hiddenCategories'] = [
      for (final category in localHidden)
        if (defaultNames.contains(category.trim().toLowerCase())) category,
    ];

    return VerbDefaultsBundle.ensureComplete(base, sport);
  }

  static Future<void> persistBundle({
    required PreferencesService prefs,
    required String sport,
    required Map<String, dynamic> bundle,
  }) async {
    final complete = VerbDefaultsBundle.ensureComplete(bundle, sport);
    final categories = ((complete['categoryOrder'] as List?) ?? const [])
        .map((value) => value.toString())
        .where((value) => value != 'Favorites' && value != 'All')
        .toList();
    final favorites = ((complete['favoriteVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet();
    final deleted = ((complete['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet();
    final custom = ((complete['customVerbs'] as List?) ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((item) {
          final key = (item['key'] ?? item['label'] ?? '').toString().trim();
          return key.isNotEmpty;
        })
        .toList();
    // Saving a user verb brings it back if it was previously hidden/deleted.
    final customKeysLower = {
      for (final item in custom)
        (item['key'] ?? item['label'] ?? '').toString().trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
    deleted.removeWhere((value) => customKeysLower.contains(value.toLowerCase()));
    final order = <String, List<String>>{};
    final rawOrder = complete['verbOrder'];
    if (rawOrder is Map) {
      rawOrder.forEach((key, value) {
        order[key.toString()] = [
          for (final item in ((value as List?) ?? const []))
            if (!deleted.contains(item.toString()) &&
                !deleted.any(
                  (d) => d.toLowerCase() == item.toString().toLowerCase(),
                ))
              item.toString(),
        ];
      });
    }
    final overrides = <String, Map<String, dynamic>>{};
    final rawOverrides = complete['verbOverrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        if (value is! Map) return;
        final k = key.toString();
        if (deleted.contains(k) ||
            deleted.any((d) => d.toLowerCase() == k.toLowerCase())) {
          return;
        }
        overrides[k] = Map<String, dynamic>.from(value);
      });
    }

    // Replace overrides wholesale so deleted keys cannot linger in prefs.
    final pins = <String, String>{};
    final rawPins = complete['categoryOverrides'];
    if (rawPins is Map) {
      rawPins.forEach((key, value) {
        final category = value?.toString().trim() ?? '';
        if (category.isEmpty) return;
        pins[key.toString()] = category;
      });
    }

    await Future.wait([
      prefs.saveCategoryOrder(categories, sport: sport),
      prefs.saveFavoriteVerbs(favorites, sport: sport),
      prefs.saveDeletedVerbs(deleted, sport: sport),
      prefs.saveVerbOrder(order, sport: sport),
      prefs.saveCustomVerbs(custom, sport: sport),
      prefs.saveVerbCatalogComplete(true, sport: sport),
      prefs.saveVerbOverrides(overrides, sport: sport),
      prefs.saveVerbCategoryOverrides(pins, sport: sport),
      prefs.saveHiddenCategories(
        {
          for (final value in ((complete['hiddenCategories'] as List?) ?? const []))
            value.toString(),
        },
        sport: sport,
      ),
    ]);
  }
}
