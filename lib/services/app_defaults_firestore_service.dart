import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/wire_iptc_specs.dart';
import 'admin_service.dart';
import 'iptc_template_apply_service.dart';

/// One IPTC template in the global app catalog (`appDefaults/current`).
class IptcTemplateCatalogEntry {
  const IptcTemplateCatalogEntry({
    required this.id,
    required this.wireStyle,
    required this.displayName,
    required this.preset,
    this.clearedFields = const [],
  });

  final String id;
  final WireStyle wireStyle;
  final String displayName;
  final Map<String, String> preset;
  final List<String> clearedFields;

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'wireStyle': wireStyle.name,
        'displayName': displayName,
        'preset': preset,
        'clearedFields': clearedFields,
      };

  static IptcTemplateCatalogEntry? fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final id = raw['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final wireName = raw['wireStyle']?.toString() ?? '';
    WireStyle wire;
    try {
      wire = WireStyle.values.firstWhere((w) => w.name == wireName);
    } catch (_) {
      wire = WireStyle.getty;
    }
    final presetRaw = raw['preset'];
    final preset = <String, String>{};
    if (presetRaw is Map) {
      presetRaw.forEach((k, v) {
        final s = v?.toString().trim() ?? '';
        if (s.isNotEmpty) preset[k.toString()] = s;
      });
    }
    final cleared = <String>[];
    final clearedRaw = raw['clearedFields'];
    if (clearedRaw is List) {
      for (final e in clearedRaw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) cleared.add(s);
      }
    }
    return IptcTemplateCatalogEntry(
      id: id,
      wireStyle: wire,
      displayName: (raw['displayName']?.toString().trim().isNotEmpty == true)
          ? raw['displayName'].toString().trim()
          : WireIptcSpecs.factoryWireLabel(wire),
      preset: preset,
      clearedFields: cleared,
    );
  }
}

/// Global app originals stored at Firestore `appDefaults/current`.
class AppDefaultsCatalog {
  const AppDefaultsCatalog({
    required this.schemaVersion,
    this.updatedAt,
    this.updatedBy,
    this.verbSettingsBySport = const {},
    this.iptcTemplates = const [],
    this.captionTemplateWireDefaults = const {},
    this.gameIdentifierByWireAndSport = const {},
    this.captionStyleLibrary = const [],
  });

  final int schemaVersion;
  final DateTime? updatedAt;
  final String? updatedBy;
  final Map<String, Map<String, dynamic>> verbSettingsBySport;
  final List<IptcTemplateCatalogEntry> iptcTemplates;
  /// Per-wire [CaptionTemplate] JSON keyed by [WireStyle.name].
  final Map<String, Map<String, dynamic>> captionTemplateWireDefaults;
  /// Per-wire, per-sport game identifier phrase (wire name → sport → text).
  final Map<String, Map<String, String>> gameIdentifierByWireAndSport;
  /// Shared caption style library entries pushed by admin, stored as raw JSON
  /// maps so this class avoids a circular dependency with PreferencesService.
  /// Applied on first launch for new users; existing customisations are never
  /// overwritten.
  final List<Map<String, dynamic>> captionStyleLibrary;

  Map<String, dynamic>? sportVerbSettings(String sport) {
    final key = sport.toLowerCase().trim();
    final raw = verbSettingsBySport[key];
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  CaptionTemplate? captionWireDefault(WireStyle wire) {
    final raw = captionTemplateWireDefaults[wire.name];
    if (raw == null || raw.isEmpty) return null;
    try {
      return CaptionTemplate.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return CaptionTemplate.tryDecode(json.encode(raw));
    }
  }

  /// Game identifier for [wire] + [sport] from catalog, or null if unset.
  String? gameIdentifierText(WireStyle wire, String sport) {
    final bySport = gameIdentifierByWireAndSport[wire.name];
    if (bySport == null) return null;
    final text = bySport[sport.toLowerCase().trim()]?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

/// Fetches, caches, and (admin) publishes global verb + IPTC defaults.
class AppDefaultsFirestoreService {
  AppDefaultsFirestoreService._();

  static const String docPath = 'appDefaults/current';
  static const int currentSchemaVersion = 2;
  static const String _cacheJsonKey = 'cached_app_defaults_json';
  static const String _cacheUpdatedAtKey = 'cached_app_defaults_updated_at_ms';

  static const List<String> catalogSports = [
    'baseball',
    'hockey',
    'basketball',
    'soccer',
  ];

  static AppDefaultsCatalog? _memoryCache;

  static bool get isAvailable => Firebase.apps.isNotEmpty;

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.doc(docPath);

  static Future<bool> canPublish() async {
    if (!isAvailable) return false;
    return AdminService.isCurrentUserAdmin();
  }

  static Future<AppDefaultsCatalog?> fetchAndCacheAppDefaults({
    bool forceNetwork = false,
  }) async {
    if (!isAvailable) return getCachedCatalog();
    try {
      final snap = await _doc.get(
        forceNetwork
            ? const GetOptions(source: Source.server)
            : const GetOptions(source: Source.serverAndCache),
      );
      if (!snap.exists) {
        return getCachedCatalog();
      }
      final catalog = _catalogFromFirestore(snap.data());
      await _writeCache(catalog);
      _memoryCache = catalog;
      return catalog;
    } catch (e) {
      print('AppDefaultsFirestoreService: fetch failed: $e');
      return getCachedCatalog();
    }
  }

  static AppDefaultsCatalog? getCachedCatalog() {
    return _memoryCache;
  }

  static Future<void> loadCacheFromDisk() async {
    if (_memoryCache != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheJsonKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _memoryCache = _catalogFromJson(decoded);
    } catch (e) {
      print('AppDefaultsFirestoreService: cache parse failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCachedSportVerbSettings(
    String sport,
  ) async {
    await loadCacheFromDisk();
    return _memoryCache?.sportVerbSettings(sport);
  }

  /// Returns the admin-published caption style library from cache as raw JSON
  /// maps (to avoid a circular dependency with PreferencesService), or [].
  static Future<List<Map<String, dynamic>>> getCachedCaptionStyleLibrary() async {
    await loadCacheFromDisk();
    return _memoryCache?.captionStyleLibrary ?? const [];
  }

  static Future<List<IptcTemplateCatalogEntry>> getVisibleIptcTemplates({
    required Set<String> hiddenIds,
  }) async {
    await loadCacheFromDisk();
    final builtIn = builtInCatalogEntries();
    final catalog = _memoryCache;
    if (catalog == null || catalog.iptcTemplates.isEmpty) {
      return builtIn.where((t) => !hiddenIds.contains(t.id)).toList();
    }
    // Firebase may only have a subset published (e.g. AP). Merge so every
    // built-in wire still appears; app-originals override the same id.
    final byId = {for (final t in builtIn) t.id: t};
    for (final t in catalog.iptcTemplates) {
      byId[t.id] = t;
    }
    return builtIn
        .map((t) => byId[t.id]!)
        .where((t) => !hiddenIds.contains(t.id))
        .toList();
  }

  static List<IptcTemplateCatalogEntry> builtInCatalogEntries() {
    return WireIptcSpecs.builtInWires
        .map(
          (w) => IptcTemplateCatalogEntry(
            id: w.name,
            wireStyle: w,
            displayName: WireIptcSpecs.factoryWireLabel(w),
            preset: const {},
          ),
        )
        .toList();
  }

  static String templateIdForWire(WireStyle wire) => wire.name;

  static const List<WireStyle> captionWireStyles = [
    WireStyle.getty,
    WireStyle.gettyInternational,
    WireStyle.imagn,
    WireStyle.ap,
    WireStyle.cp,
  ];

  static CaptionTemplate factoryCaptionForWire(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
        return CaptionTemplate.getty();
      case WireStyle.imagn:
        return CaptionTemplate.imagn();
      case WireStyle.ap:
        return CaptionTemplate.ap();
      case WireStyle.cp:
        return CaptionTemplate.cp();
      case WireStyle.gettyInternational:
        return CaptionTemplate.gettyInternational();
      case WireStyle.custom:
        return CaptionTemplate.getty();
    }
  }

  /// Resolves game identifier: catalog overlay → [defaultGameIdentifierText].
  static Future<String> resolveGameIdentifierText(
    WireStyle wire,
    String sport,
  ) async {
    await loadCacheFromDisk();
    final fromCatalog = _memoryCache?.gameIdentifierText(wire, sport);
    if (fromCatalog != null && fromCatalog.isNotEmpty) return fromCatalog;
    return defaultGameIdentifierText(sport);
  }

  /// Applies catalog/local game ID overlay for [sport] onto a wire layout template.
  static Future<CaptionTemplate> applyGameIdentifierForSport(
    CaptionTemplate template,
    WireStyle wire,
    String sport,
  ) async {
    final text = await resolveGameIdentifierText(wire, sport);
    return CaptionTemplate.applyGameIdentifierText(template, text);
  }

  /// Caption wire defaults from cache, falling back to factory presets.
  static Map<WireStyle, CaptionTemplate> mergedCaptionWireDefaults({
    String sport = 'baseball',
  }) {
    final catalog = _memoryCache;
    final out = <WireStyle, CaptionTemplate>{};
    for (final wire in captionWireStyles) {
      final base =
          catalog?.captionWireDefault(wire) ?? factoryCaptionForWire(wire);
      final gid = catalog?.gameIdentifierText(wire, sport) ??
          defaultGameIdentifierText(sport);
      out[wire] = CaptionTemplate.applyGameIdentifierText(base, gid);
    }
    return out;
  }

  static Map<String, Map<String, String>> _parseGameIdentifierMap(
    dynamic raw,
  ) {
    final out = <String, Map<String, String>>{};
    if (raw is! Map) return out;
    raw.forEach((wireKey, sportMap) {
      if (sportMap is! Map) return;
      final bySport = <String, String>{};
      sportMap.forEach((sportKey, value) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          bySport[sportKey.toString().toLowerCase().trim()] = text;
        }
      });
      if (bySport.isNotEmpty) {
        out[wireKey.toString()] = bySport;
      }
    });
    return out;
  }

  static Map<String, dynamic> _gameIdentifierMapToFirestore(
    Map<String, Map<String, String>> map,
  ) {
    return map.map((wire, bySport) => MapEntry(wire, Map<String, String>.from(bySport)));
  }

  /// Default per-wire-per-sport game identifiers (factory phrases).
  static Map<String, Map<String, String>> seededGameIdentifierByWireAndSport() {
    final out = <String, Map<String, String>>{};
    for (final wire in captionWireStyles) {
      final bySport = <String, String>{};
      for (final sport in catalogSports) {
        final text = defaultGameIdentifierText(sport);
        if (text.isNotEmpty) bySport[sport] = text;
      }
      if (bySport.isNotEmpty) out[wire.name] = bySport;
    }
    return out;
  }

  /// Admin: publish all caption wire structure defaults.
  static Future<void> publishCaptionWireDefaults(
    Map<String, Map<String, dynamic>> defaults, {
    Map<String, Map<String, String>>? gameIdentifierByWireAndSport,
  }) async {
    await _assertCanPublish();
    final payload = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      'captionTemplateWireDefaults': defaults,
    };
    if (gameIdentifierByWireAndSport != null) {
      payload['gameIdentifierByWireAndSport'] =
          _gameIdentifierMapToFirestore(gameIdentifierByWireAndSport);
    }
    await _doc.set(payload, SetOptions(merge: true));
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  /// Admin: merge one wire's caption structure into app defaults.
  static Future<void> publishCaptionWireDefault(
    WireStyle wire,
    CaptionTemplate template, {
    String? gameIdentifierForSport,
    String? gameIdentifierSport,
  }) async {
    await _assertCanPublish();
    final snap = await _doc.get();
    final data = snap.data() ?? <String, dynamic>{};
    final existing = <String, Map<String, dynamic>>{};
    final raw = data['captionTemplateWireDefaults'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          existing[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }
    existing[wire.name] = CaptionTemplate.wireMasterJsonFromTemplate(
      template.copyWith(wireStyle: wire),
    );

    Map<String, Map<String, String>>? gameIds;
    if (gameIdentifierForSport != null &&
        gameIdentifierSport != null &&
        gameIdentifierForSport.trim().isNotEmpty) {
      gameIds = _parseGameIdentifierMap(data['gameIdentifierByWireAndSport']);
      final bySport = Map<String, String>.from(gameIds[wire.name] ?? {});
      bySport[gameIdentifierSport.toLowerCase().trim()] =
          gameIdentifierForSport.trim();
      gameIds[wire.name] = bySport;
    }

    await publishCaptionWireDefaults(existing, gameIdentifierByWireAndSport: gameIds);
  }

  /// Admin: push the caption style library so all users receive it on startup.
  /// Accepts raw JSON maps (call [CaptionStyleLibraryEntry.toJson()] at the
  /// call site) so this service has no dependency on PreferencesService.
  /// Existing users only receive it if their local library is empty.
  static Future<void> publishCaptionStyleLibrary(
    List<Map<String, dynamic>> libraryJson,
  ) async {
    await _assertCanPublish();
    await _doc.set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'captionStyleLibrary': libraryJson,
      },
      SetOptions(merge: true),
    );
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  /// Admin: publish the full game-identifier map.
  static Future<void> publishGameIdentifierByWireAndSport(
    Map<String, Map<String, String>> map,
  ) async {
    await _assertCanPublish();
    await _doc.set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'gameIdentifierByWireAndSport': _gameIdentifierMapToFirestore(map),
      },
      SetOptions(merge: true),
    );
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  /// Admin: merge current sport verb settings into `appDefaults/current`.
  static Future<void> publishVerbsForSport(
    String sport,
    Map<String, dynamic> sportData,
  ) async {
    await _assertCanPublish();
    final normalized = sport.toLowerCase().trim();
    await _doc.set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'verbSettingsBySport': {normalized: sportData},
      },
      SetOptions(merge: true),
    );
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  /// Admin: publish verb settings for all [catalogSports] from export maps.
  static Future<void> publishAllVerbs(
    Map<String, Map<String, dynamic>> bySport,
  ) async {
    await _assertCanPublish();
    await _doc.set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'verbSettingsBySport': bySport,
      },
      SetOptions(merge: true),
    );
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  /// Admin: upsert one IPTC template in the catalog array.
  static Future<void> publishIptcTemplate(IptcTemplateCatalogEntry entry) async {
    await _assertCanPublish();
    final snap = await _doc.get();
    final data = snap.data() ?? <String, dynamic>{};
    final existing = <IptcTemplateCatalogEntry>[];
    final rawList = data['iptcTemplates'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final parsed = IptcTemplateCatalogEntry.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (parsed != null) existing.add(parsed);
        }
      }
    }
    final next = <IptcTemplateCatalogEntry>[
      for (final t in existing)
        if (t.id != entry.id) t,
      entry,
    ];
    await _doc.set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'iptcTemplates': next.map((e) => e.toFirestore()).toList(),
      },
      SetOptions(merge: true),
    );
    await fetchAndCacheAppDefaults(forceNetwork: true);
  }

  static Future<void> _assertCanPublish() async {
    if (!isAvailable) {
      throw StateError('Firebase is not initialized');
    }
    if (!await canPublish()) {
      throw StateError('Only admin accounts may publish app defaults');
    }
  }

  static Future<void> _writeCache(AppDefaultsCatalog catalog) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheJsonKey,
      json.encode(_catalogToJson(catalog)),
    );
    if (catalog.updatedAt != null) {
      await prefs.setInt(
        _cacheUpdatedAtKey,
        catalog.updatedAt!.millisecondsSinceEpoch,
      );
    }
  }

  static AppDefaultsCatalog _catalogFromFirestore(Map<String, dynamic>? data) {
    if (data == null) {
      return const AppDefaultsCatalog(schemaVersion: currentSchemaVersion);
    }
    return _catalogFromJson(data);
  }

  static AppDefaultsCatalog _catalogFromJson(Map<String, dynamic> data) {
    final verbsRaw = data['verbSettingsBySport'];
    final verbs = <String, Map<String, dynamic>>{};
    if (verbsRaw is Map) {
      verbsRaw.forEach((k, v) {
        if (v is Map) {
          verbs[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }
    final iptc = <IptcTemplateCatalogEntry>[];
    final iptcRaw = data['iptcTemplates'];
    if (iptcRaw is List) {
      for (final item in iptcRaw) {
        if (item is Map) {
          final parsed = IptcTemplateCatalogEntry.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (parsed != null) iptc.add(parsed);
        }
      }
    }
    final captionDefaults = <String, Map<String, dynamic>>{};
    final captionRaw = data['captionTemplateWireDefaults'];
    if (captionRaw is Map) {
      captionRaw.forEach((k, v) {
        if (v is Map) {
          captionDefaults[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }
    final gameIds = _parseGameIdentifierMap(data['gameIdentifierByWireAndSport']);
    final styleLib = <Map<String, dynamic>>[];
    final styleLibRaw = data['captionStyleLibrary'];
    if (styleLibRaw is List) {
      for (final item in styleLibRaw) {
        if (item is Map) {
          styleLib.add(Map<String, dynamic>.from(item));
        }
      }
    }
    DateTime? updatedAt;
    final ts = data['updatedAt'];
    if (ts is Timestamp) {
      updatedAt = ts.toDate();
    }
    return AppDefaultsCatalog(
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ??
          currentSchemaVersion,
      updatedAt: updatedAt,
      updatedBy: data['updatedBy']?.toString(),
      verbSettingsBySport: verbs,
      iptcTemplates: iptc,
      captionTemplateWireDefaults: captionDefaults,
      gameIdentifierByWireAndSport: gameIds,
      captionStyleLibrary: styleLib,
    );
  }

  static Map<String, dynamic> _catalogToJson(AppDefaultsCatalog catalog) {
    return {
      'schemaVersion': catalog.schemaVersion,
      if (catalog.updatedAt != null)
        'updatedAtMs': catalog.updatedAt!.millisecondsSinceEpoch,
      if (catalog.updatedBy != null) 'updatedBy': catalog.updatedBy,
      'verbSettingsBySport': catalog.verbSettingsBySport,
      'iptcTemplates':
          catalog.iptcTemplates.map((e) => e.toFirestore()).toList(),
      'captionTemplateWireDefaults': catalog.captionTemplateWireDefaults,
      'gameIdentifierByWireAndSport':
          _gameIdentifierMapToFirestore(catalog.gameIdentifierByWireAndSport),
      if (catalog.captionStyleLibrary.isNotEmpty)
        'captionStyleLibrary': catalog.captionStyleLibrary,
    };
  }

  /// Builds a catalog entry from startup panel values.
  static IptcTemplateCatalogEntry entryFromPanel({
    required WireStyle wire,
    required Map<String, String> panelValues,
    required Set<String> clearedFields,
    String? displayName,
  }) {
    final preset =
        IptcTemplateApplyService.normalizeForPreset(panelValues);
    return IptcTemplateCatalogEntry(
      id: templateIdForWire(wire),
      wireStyle: wire,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : WireIptcSpecs.factoryWireLabel(wire),
      preset: preset,
      clearedFields: clearedFields.toList(),
    );
  }
}
