import '../caption_style/verb_defaults_bundle.dart';
import 'app_defaults_firestore_service.dart';
import 'preferences_service.dart';

/// Loads / saves a sport verb catalog for personal (per-user) editing.
///
/// Merges app-default catalog with the user's prefs. Persisting writes only to
/// [PreferencesService] (which syncs to `users/{uid}/preferences/current`) and
/// never to app-default Firebase originals.
class VerbUserCatalogService {
  VerbUserCatalogService._();

  static Future<Map<String, dynamic>> loadMergedBundle({
    required PreferencesService prefs,
    required String sport,
  }) async {
    final cached =
        await AppDefaultsFirestoreService.getCachedSportVerbSettings(sport);
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

    final deleted = <String>{
      for (final value in ((base['deletedVerbs'] as List?) ?? const []))
        value.toString(),
      ...localDeleted.map((value) => value.toString()),
    };
    final deletedLower = {
      for (final value in deleted) value.trim().toLowerCase(),
    };
    bool isDeleted(String key) {
      final trimmed = key.trim();
      if (trimmed.isEmpty) return false;
      return deleted.contains(trimmed) ||
          deletedLower.contains(trimmed.toLowerCase());
    }

    // Once the user has a local customVerbs file (even `[]`), that list is
    // authoritative — Firebase customs must not resurrect deleted verbs.
    final customsByKey = <String, Map<String, dynamic>>{};
    if (hasLocalCustoms) {
      for (final raw in localCustoms) {
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        if (key.isEmpty || isDeleted(key)) continue;
        customsByKey[key] = Map<String, dynamic>.from(raw);
      }
    } else {
      for (final raw in ((base['customVerbs'] as List?) ?? const [])) {
        if (raw is! Map) continue;
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        if (key.isEmpty || isDeleted(key)) continue;
        customsByKey[key] = Map<String, dynamic>.from(raw);
      }
      for (final raw in localCustoms) {
        final key = (raw['key'] ?? raw['label'] ?? '').toString().trim();
        if (key.isEmpty || isDeleted(key)) continue;
        customsByKey[key] = Map<String, dynamic>.from(raw);
      }
    }
    base['customVerbs'] = customsByKey.values.toList();

    final overrides = Map<String, dynamic>.from(
      (base['verbOverrides'] as Map?) ?? const {},
    );
    localOverrides.forEach((key, value) {
      overrides[key] = Map<String, dynamic>.from(value);
    });
    overrides.removeWhere((key, _) => isDeleted(key));
    base['verbOverrides'] = overrides;

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
    if (categories.isNotEmpty) {
      base['categoryOrder'] = categories;
    }

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
        .where((value) => value != 'Favorites')
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
          if (key.isEmpty) return false;
          return !deleted.contains(key) &&
              !deleted.any((d) => d.toLowerCase() == key.toLowerCase());
        })
        .toList();
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
    await Future.wait([
      prefs.saveCategoryOrder(categories, sport: sport),
      prefs.saveFavoriteVerbs(favorites, sport: sport),
      prefs.saveDeletedVerbs(deleted, sport: sport),
      prefs.saveVerbOrder(order, sport: sport),
      prefs.saveCustomVerbs(custom, sport: sport),
      prefs.saveVerbCatalogComplete(true, sport: sport),
      prefs.saveVerbOverrides(overrides, sport: sport),
    ]);
  }
}
