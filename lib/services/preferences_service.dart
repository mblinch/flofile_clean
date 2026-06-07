import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import '../caption_style/caption_template.dart';
import '../caption_style/game_info.dart';
import 'app_defaults_firestore_service.dart';
import 'iptc_template_apply_service.dart';
import 'user_preferences_firestore_service.dart';

class PreferencesService {
  static const String _keyCategoryOrder = 'category_order';
  static const String _keyCategoryOrderBaseball = 'category_order_baseball';
  /// Per-category ordered verb lists (JSON map: category name -> list of verb strings).
  static const String _keyVerbOrderBaseball = 'verb_order_baseball';
  static const String _keyFavoriteVerbs = 'favorite_verbs';
  static const String _keyFavoriteVerbsBaseball =
      'favorite_verbs_baseball'; // Sport-specific favorites
  static const String _keyCurrentSport = 'current_sport'; // Track current sport
  static const String _keyFavoriteTeams = 'favorite_teams';
  static const String _keyFavoriteTeamsBaseball =
      'favorite_teams_baseball'; // Sport-specific team favorites
  static const String _keyFtpProfiles = 'ftp_profiles';
  static const String _keyCurrentFtpProfile = 'current_ftp_profile';
  static const String _keyPlaceFirebarOnRight = 'place_firebar_on_right';
  static const String _keyLastSavedMetadata = 'last_saved_metadata';
  // Custom verb wordings (per sport)
  static const String _keyCustomVerbWordings = 'custom_verb_wordings';
  static const String _keyCustomVerbWordingsBaseball =
      'custom_verb_wordings_baseball';
  static const String _keySerialNumberBylines = 'serial_number_bylines';
  /// When true, selecting a verb merges its keyword presets into the IPTC keywords field.
  static const String _keyApplyVerbKeywords = 'apply_verb_keywords';
  /// When true, selected player names are also merged into the IPTC keywords field.
  static const String _keyApplyPlayerNamesToKeywords =
      'apply_player_names_to_keywords';
  static const String _keyResolutionWarningThreshold =
      'resolution_warning_threshold';
  static const String _keyPhotoshopPath = 'photoshop_path';
  static const String _keyCurrentLayout = 'current_layout';
  /// Caption entry mode: 'keyboard_fire' (default) or 'classic'.
  static const String _keyCaptionEntryMode = 'caption_entry_mode';
  static const String _keyCustomVerbs = 'custom_verbs';
  static const String _keyVerbOverrides = 'verb_overrides'; // For editing built-in verbs
  static const String _keyDeletedVerbs = 'deleted_verbs'; // For tracking deleted built-in verbs
  static const String _keySportDefaultPrefix = 'sport_default_'; // Per-sport "Set as default" bundle
  static const String _keySyncServerUrl = 'sync_server_url';
  static const String _keySyncAccountId = 'sync_account_id';
  /// IANA zone: EXIF capture times are interpreted as this local zone when
  /// resolving MLB innings from play-by-play (internal / allowlisted users).
  static const String _keyMlbInningExifTimezone = 'mlb_inning_exif_timezone';
  static const String _keyMlbInningFromClockEnabled =
      'mlb_inning_from_clock_enabled';
  static const String mlbInningExifTimezoneDefault = 'America/New_York';
  /// Legacy prefs key; optional headline strip under the caption is no longer offered.
  static const String _keyShowHeadlineField = 'show_headline_field';
  static const String _keyShowKeywordsField = 'show_keywords_field';
  static const String _keyShowPersonalityField = 'show_personality_field';
  /// Keyboard Fire: Actions column — expand/collapse shortcut cheatsheet under FTP.
  static const String _keyShowKeyboardFireShortcutsHelp =
      'show_keyboard_fire_shortcuts_help';
  static const String _keyKeywordShortcuts = 'keyword_shortcuts';
  static const String _keyHasLaunchedBefore = 'has_launched_before';
  /// When true, saving may prompt to apply captions across rapid (≤1s) sequences.
  static const String _keyBurstDetectionEnabled = 'burst_detection_enabled';
  /// `none` | `on_import` | `on_save` — when startup IPTC template is applied.
  static const String _keyIptcApplyMode = 'iptc_apply_mode';
  static const String _keyApplyIptcOnImport = 'apply_iptc_on_import';
  static const String _keyApplyIptcOnSave = 'apply_iptc_on_save';
  static const String _legacyApplyPresetToAllImages =
      'apply_preset_to_all_images';
  /// [package_info_plus] build number for which “What’s new” was dismissed.
  static const String _keyLastAcknowledgedAppBuild =
      'last_acknowledged_app_build';
  /// JSON array of segment ids for caption wire order (game_date, location, body, venue, credit).
  static const String _keyCaptionLayoutOrder = 'caption_layout_order';
  /// `getty` or `imagn` — legacy; superseded by [CaptionTemplate] JSON.
  static const String _keyCaptionLayoutFlavor = 'caption_layout_flavor';
  static const String _keyCaptionTemplateJson = 'caption_template_json';
  /// Optional per-wire layout baselines (Getty USA / Imagn / AP) for [CaptionLayoutBuilderDialog].
  static const String _keyCaptionTemplateDefaultGettyJson =
      'caption_template_default_getty_json';
  static const String _keyCaptionTemplateDefaultImagnJson =
      'caption_template_default_imagn_json';
  static const String _keyCaptionTemplateDefaultApJson =
      'caption_template_default_ap_json';
  static const String _keyCaptionTemplateDefaultCpJson =
      'caption_template_default_cp_json';
  static const String _keyCaptionTemplateDefaultGettyInternationalJson =
      'caption_template_default_getty_international_json';
  /// Named snapshots from “Save new caption style” in the layout builder.
  static const String _keyCaptionStyleLibraryJson = 'caption_style_library_json';
  /// User-chosen labels shown in the Caption Style menu for the built-in wires.
  /// Null / absent → fall back to the factory name (Getty USA / Imagn / AP /
  /// Getty International).
  static const String _keyCaptionWireLabelGetty =
      'caption_wire_label_getty';
  static const String _keyCaptionWireLabelImagn =
      'caption_wire_label_imagn';
  static const String _keyCaptionWireLabelAp = 'caption_wire_label_ap';
  static const String _keyCaptionWireLabelCp = 'caption_wire_label_cp';
  static const String _keyCaptionWireLabelGettyInternational =
      'caption_wire_label_getty_international';
  /// One-time migration flag — true once the legacy "Getty International"
  /// library entry has been promoted to the new built-in wire.
  static const String _keyGettyInternationalMigrationDone =
      'getty_international_migration_done';
  static const String _keyCaptionGameInfoJson = 'caption_game_info_json';
  static const String _keyCaptionPreviewHomePrefix =
      'caption_preview_last_home_';
  static const String _keyCaptionPreviewAwayPrefix =
      'caption_preview_last_away_';
  static const String _keyFavoriteCaptionStylePrefix =
      'favorite_caption_style_';
  /// `gettyImages` | `imagn` | `ap` for sample credit line in caption layout preview.
  static const String _keyCaptionCreditSampleAgency = 'caption_credit_sample_agency';
  static const String _keySavedDefaultPreferences = 'saved_default_preferences';
  static const String _keyHiddenIptcTemplateIds = 'hidden_iptc_template_ids';
  static const String _keyIptcWirePresetPrefix = 'iptc_wire_preset_';
  static const String _keyIptcWireClearedPrefix = 'iptc_wire_cleared_';
  static const String _keySelectedIptcTemplateId = 'selected_iptc_template_id';
  /// Per-wire, per-sport game identifier phrases (mirrors Firebase catalog).
  static const String _keyGameIdentifierByWireAndSportJson =
      'game_identifier_by_wire_and_sport_json';
  static const String _keyUserPreferencesUpdatedAtMs =
      'user_preferences_updated_at_ms';
  static const String _keyUserPreferencesCloudUpdatedAtMs =
      'user_preferences_cloud_updated_at_ms';

  static PreferencesService? _instance;
  static SharedPreferences? _prefs;

  /// Fires after cloud preferences are applied so open screens can reload.
  final StreamController<void> cloudPreferencesAppliedController =
      StreamController<void>.broadcast();

  bool _suppressCloudSync = false;

  PreferencesService._();

  static Future<PreferencesService> getInstance() async {
    _instance ??= PreferencesService._();
    _prefs ??= await SharedPreferences.getInstance();
    await _instance!._applyFirstLaunchDefaults();
    return _instance!;
  }

  /// On first launch, explicitly save keyword-related prefs as off.
  /// Existing users already have saved prefs so this is a no-op for them.
  Future<void> _applyFirstLaunchDefaults() async {
    final prefs = await _getPrefs();
    if (prefs.getBool(_keyHasLaunchedBefore) == true) return;
    await prefs.setBool(_keyHasLaunchedBefore, true);

    // Only set defaults if user has never saved these prefs
    if (!prefs.containsKey(_keyApplyVerbKeywords)) {
      await prefs.setBool(_keyApplyVerbKeywords, false);
    }
    if (!prefs.containsKey(_keyApplyPlayerNamesToKeywords)) {
      await prefs.setBool(_keyApplyPlayerNamesToKeywords, false);
    }
    if (!prefs.containsKey(_keyShowKeywordsField)) {
      await prefs.setBool(_keyShowKeywordsField, false);
    }
    if (!prefs.containsKey(_keyBurstDetectionEnabled)) {
      await prefs.setBool(_keyBurstDetectionEnabled, false);
    }
  }

  Future<bool> getBurstDetectionEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyBurstDetectionEnabled) ?? false;
  }

  Future<void> saveBurstDetectionEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyBurstDetectionEnabled, enabled);
    _afterLocalPreferencesChanged();
  }

  Future<IptcApplyMode> getIptcApplyMode() async {
    final prefs = await _getPrefs();
    if (!prefs.containsKey(_keyIptcApplyMode)) {
      final onImport = prefs.getBool(_keyApplyIptcOnImport);
      final onSave = prefs.getBool(_keyApplyIptcOnSave);
      final legacy = prefs.getBool(_legacyApplyPresetToAllImages);

      IptcApplyMode mode;
      if (onSave == true && onImport != true) {
        mode = IptcApplyMode.onSave;
      } else if (onImport == true || legacy == true) {
        mode = IptcApplyMode.onImport;
      } else if (onImport == false && onSave == false) {
        mode = IptcApplyMode.none;
      } else {
        mode = IptcApplyMode.none;
      }

      await prefs.setString(_keyIptcApplyMode, mode.storageValue);
      return mode;
    }
    return IptcApplyMode.fromStorage(prefs.getString(_keyIptcApplyMode));
  }

  Future<void> saveIptcApplyMode(IptcApplyMode mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyIptcApplyMode, mode.storageValue);
  }

  /// Last [package_info_plus] build number the user saw update notes for (0 = never).
  Future<int> getLastAcknowledgedAppBuild() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_keyLastAcknowledgedAppBuild) ?? 0;
  }

  Future<void> setLastAcknowledgedAppBuild(int buildNumber) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyLastAcknowledgedAppBuild, buildNumber);
  }

  /// Bumped when keywords/personality visibility toggles — caption UI listens to reflow.
  final ValueNotifier<int> captionFieldVisibilityRevision =
      ValueNotifier<int>(0);

  void _notifyCaptionFieldVisibilityChanged() {
    captionFieldVisibilityRevision.value = captionFieldVisibilityRevision.value + 1;
  }

  Future<bool> getShowHeadlineField() async {
    return false;
  }

  Future<void> saveShowHeadlineField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowHeadlineField, false);
    _notifyCaptionFieldVisibilityChanged();
  }

  Future<bool> getShowKeywordsField() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowKeywordsField) ?? false;
  }

  Future<void> saveShowKeywordsField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowKeywordsField, show);
    final active = CaptionTemplate.tryDecode(prefs.getString(_keyCaptionTemplateJson));
    if (active != null && active.showKeywordsField != show) {
      await prefs.setString(
        _keyCaptionTemplateJson,
        active.copyWith(showKeywordsField: show).encode(),
      );
    }
    _notifyCaptionFieldVisibilityChanged();
  }

  Future<bool> getShowPersonalityField() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowPersonalityField) ?? true;
  }

  Future<void> saveShowPersonalityField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowPersonalityField, show);
    final active = CaptionTemplate.tryDecode(prefs.getString(_keyCaptionTemplateJson));
    if (active != null && active.showPersonalityField != show) {
      await prefs.setString(
        _keyCaptionTemplateJson,
        active.copyWith(showPersonalityField: show).encode(),
      );
    }
    _notifyCaptionFieldVisibilityChanged();
  }

  /// Immediate read after [getInstance]; matches on-disk values right after each
  /// `saveShow*Field` call (avoids async lag when [captionFieldVisibilityRevision] fires).
  bool get captionFieldHeadlineVisibleSync => false;
  bool get captionFieldKeywordsVisibleSync =>
      _prefs?.getBool(_keyShowKeywordsField) ?? false;
  bool get captionFieldPersonalityVisibleSync =>
      _prefs?.getBool(_keyShowPersonalityField) ?? true;

  Future<bool> getShowKeyboardFireShortcutsHelp() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowKeyboardFireShortcutsHelp) ?? true;
  }

  Future<void> saveShowKeyboardFireShortcutsHelp(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowKeyboardFireShortcutsHelp, show);
  }

  /// Returns saved keyword shortcuts as a list of maps with 'label' (String)
  /// and 'keywords' (List<String>). Returns empty list when nothing is saved
  /// (caller should fall back to built-in defaults).
  Future<List<Map<String, dynamic>>> getKeywordShortcuts() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keyKeywordShortcuts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveKeywordShortcuts(
      List<Map<String, dynamic>> shortcuts) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyKeywordShortcuts, jsonEncode(shortcuts));
  }

  bool get showKeyboardFireShortcutsHelpSync =>
      _prefs?.getBool(_keyShowKeyboardFireShortcutsHelp) ?? true;

  // Category Order Preferences (sport-specific)
  Future<List<String>> getCategoryOrder({String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getCategoryOrderKey(sport);
    final orderJson = prefs.getString(key);
    if (orderJson != null) {
      try {
        final List<dynamic> orderList = json.decode(orderJson);
        final order = orderList.cast<String>();
        print('DEBUG: Loaded category order for ' +
            sport +
            ': ' +
            order.toString() +
            ' (key=' +
            key +
            ')');
        return order;
      } catch (e) {
        print(
            'Error parsing category order for ' + sport + ': ' + e.toString());
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['categoryOrder'] != null) {
      try {
        final order = List<String>.from(sportDefault['categoryOrder'] as List<dynamic>);
        if (order.isNotEmpty) return order;
      } catch (_) {}
    }
    // Return sport-specific default order if not found or error
    final List<String> defaultOrder;
    switch (sport.toLowerCase()) {
      case 'hockey':
        defaultOrder = [
          'Offense',
          'Defense',
          'Goalie',
          'Non Game-Action',
          'Reactions',
          'Favorites',
        ];
        break;
      case 'soccer':
        defaultOrder = [
          'Offense',
          'Defense',
          'Goalkeeper',
          'Set Pieces',
          'Non Game-Action',
          'Reactions',
          'Favorites',
        ];
        break;
      case 'baseball':
      default:
        defaultOrder = [
          'Offense',
          'Defense',
          'Pitching',
          'Running',
          'Reactions',
          'Non Game-Action',
          'Favorites',
        ];
        break;
    }
    print('DEBUG: No saved category order for ' +
        sport +
        '; using default ' +
        defaultOrder.toString() +
        ' (key=' +
        key +
        ')');
    return defaultOrder;
  }

  Future<void> saveCategoryOrder(List<String> order,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getCategoryOrderKey(sport);
    await prefs.setString(key, json.encode(order));
    print('DEBUG: Saved category order for ' +
        sport +
        ': ' +
        order.toString() +
        ' (key=' +
        key +
        ')');
    _afterLocalPreferencesChanged();
  }

  // Current sport
  Future<void> saveCurrentSport(String sport) async {
    final prefs = await _getPrefs();
    final normalized = sport.toLowerCase().trim();
    await prefs.setString(_keyCurrentSport, normalized);

    final active = CaptionTemplate.tryDecode(prefs.getString(_keyCaptionTemplateJson));
    if (active != null) {
      final gid = await resolveGameIdentifierText(active.wireStyle, normalized);
      final updated = CaptionTemplate.applyGameIdentifierText(active, gid);
      if (updated.gameIdentifierText != active.gameIdentifierText) {
        await prefs.setString(_keyCaptionTemplateJson, updated.encode());
      }
    }
    _afterLocalPreferencesChanged();
  }

  /// Local per-wire-per-sport game identifier map (wire name → sport → text).
  Future<Map<String, Map<String, String>>>
      getGameIdentifierByWireAndSport() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keyGameIdentifierByWireAndSportJson);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, String>>{};
      decoded.forEach((wireKey, sportMap) {
        if (sportMap is! Map) return;
        final bySport = <String, String>{};
        sportMap.forEach((sportKey, value) {
          final text = value?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            bySport[sportKey.toString().toLowerCase().trim()] = text;
          }
        });
        if (bySport.isNotEmpty) out[wireKey.toString()] = bySport;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveGameIdentifierByWireAndSport(
    Map<String, Map<String, String>> map,
  ) async {
    final prefs = await _getPrefs();
    if (map.isEmpty) {
      await prefs.remove(_keyGameIdentifierByWireAndSportJson);
      _afterLocalPreferencesChanged();
      return;
    }
    await prefs.setString(
      _keyGameIdentifierByWireAndSportJson,
      json.encode(map),
    );
    _afterLocalPreferencesChanged();
  }

  Future<void> setGameIdentifierForWireAndSport(
    WireStyle wire,
    String sport,
    String text,
  ) async {
    final map = await getGameIdentifierByWireAndSport();
    final bySport = Map<String, String>.from(map[wire.name] ?? {});
    final normalizedSport = sport.toLowerCase().trim();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      bySport.remove(normalizedSport);
    } else {
      bySport[normalizedSport] = trimmed;
    }
    if (bySport.isEmpty) {
      map.remove(wire.name);
    } else {
      map[wire.name] = bySport;
    }
    await saveGameIdentifierByWireAndSport(map);
  }

  /// Local overlay → Firebase catalog → [defaultGameIdentifierText].
  Future<String> resolveGameIdentifierText(
    WireStyle wire,
    String sport,
  ) async {
    final normalizedSport = sport.toLowerCase().trim();
    final local = await getGameIdentifierByWireAndSport();
    final fromLocal = local[wire.name]?[normalizedSport]?.trim();
    if (fromLocal != null && fromLocal.isNotEmpty) return fromLocal;
    return AppDefaultsFirestoreService.resolveGameIdentifierText(
      wire,
      normalizedSport,
    );
  }

  Future<CaptionTemplate> applyGameIdentifierForSport(
    CaptionTemplate template,
    WireStyle wire,
    String sport,
  ) async {
    final text = await resolveGameIdentifierText(wire, sport);
    return CaptionTemplate.applyGameIdentifierText(template, text);
  }

  Future<String> getCurrentSport() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyCurrentSport) ?? 'baseball';
  }

  // Helper to get sport-specific key
  String _getSportSpecificKey(String sport) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return _keyFavoriteVerbsBaseball;
      default:
        return '${_keyFavoriteVerbs}_${sport.toLowerCase()}';
    }
  }

  // Helper for category order key per sport
  String _getCategoryOrderKey(String sport) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return _keyCategoryOrderBaseball;
      default:
        return '${_keyCategoryOrder}_${sport.toLowerCase()}';
    }
  }

  String _getVerbOrderKey(String sport) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return _keyVerbOrderBaseball;
      default:
        return 'verb_order_${sport.toLowerCase()}';
    }
  }

  /// Saved verb order per category for [sport]. Empty map if none.
  Future<Map<String, List<String>>> getVerbOrder({String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_getVerbOrderKey(sport));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        return decoded.map(
          (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
        );
      } catch (_) {}
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['verbOrder'] is Map) {
      try {
        final vo = sportDefault['verbOrder'] as Map<String, dynamic>;
        return vo.map(
          (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
        );
      } catch (_) {}
    }
    return {};
  }

  Future<void> saveVerbOrder(
    Map<String, List<String>> order, {
    String sport = 'baseball',
  }) async {
    final prefs = await _getPrefs();
    final key = _getVerbOrderKey(sport);
    if (order.isEmpty) {
      await prefs.remove(key);
      _afterLocalPreferencesChanged();
      return;
    }
    await prefs.setString(key, json.encode(order));
    _afterLocalPreferencesChanged();
  }

  // Per-sport default (e.g. "Set as default for Baseball") — used when user has no saved prefs for that sport
  String _getSportDefaultKey(String sport) =>
      '$_keySportDefaultPrefix${sport.toLowerCase()}';

  Future<Map<String, dynamic>?> getSportDefault(String sport) async {
    final fromAppDefaults =
        await AppDefaultsFirestoreService.getCachedSportVerbSettings(sport);
    if (fromAppDefaults != null && fromAppDefaults.isNotEmpty) {
      return fromAppDefaults;
    }
    final prefs = await _getPrefs();
    final raw = prefs.getString(_getSportDefaultKey(sport));
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSportDefault(String sport) async {
    final prefs = await _getPrefs();
    return prefs.containsKey(_getSportDefaultKey(sport));
  }

  Future<void> setSportDefault(String sport, Map<String, dynamic> data) async {
    final prefs = await _getPrefs();
    await prefs.setString(_getSportDefaultKey(sport), json.encode(data));
  }

  Future<void> clearSportDefault(String sport) async {
    final prefs = await _getPrefs();
    await prefs.remove(_getSportDefaultKey(sport));
  }

  // Helper for custom verb wordings key per sport
  String _getCustomVerbWordingsKey(String sport) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return _keyCustomVerbWordingsBaseball;
      default:
        return '${_keyCustomVerbWordings}_${sport.toLowerCase()}';
    }
  }

  // Favorite Verbs Preferences (sport-specific)
  Future<Set<String>> getFavoriteVerbs({String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getSportSpecificKey(sport);
    final verbsJson = prefs.getString(key);
    if (verbsJson != null) {
      try {
        final List<dynamic> verbsList = json.decode(verbsJson);
        final verbs = verbsList.cast<String>().toSet();
        return verbs;
      } catch (e) {
        print('Error parsing favorite verbs for $sport: $e');
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['favoriteVerbs'] != null) {
      try {
        return Set<String>.from(sportDefault['favoriteVerbs'] as List<dynamic>);
      } catch (_) {}
    }
    return <String>{};
  }

  Future<void> saveFavoriteVerbs(Set<String> verbs,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getSportSpecificKey(sport);
    await prefs.setString(key, json.encode(verbs.toList()));
    _afterLocalPreferencesChanged();
  }

  // Favorite Teams Preferences (sport-specific)
  Future<Set<String>> getFavoriteTeams({String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getFavoriteTeamsKey(sport);
    final teamsJson = prefs.getString(key);
    if (teamsJson != null) {
      try {
        final List<dynamic> teamsList = json.decode(teamsJson);
        return teamsList.cast<String>().toSet();
      } catch (e) {
        print('Error parsing favorite teams for $sport: $e');
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['favoriteTeams'] != null) {
      try {
        return Set<String>.from(sportDefault['favoriteTeams'] as List<dynamic>);
      } catch (_) {}
    }
    return <String>{};
  }

  Future<void> saveFavoriteTeams(Set<String> teams,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getFavoriteTeamsKey(sport);
    await prefs.setString(key, json.encode(teams.toList()));
    _afterLocalPreferencesChanged();
  }

  // Helper for favorite teams key per sport
  String _getFavoriteTeamsKey(String sport) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return _keyFavoriteTeamsBaseball;
      default:
        return '${_keyFavoriteTeams}_${sport.toLowerCase()}';
    }
  }

  // FTP Profiles Preferences
  Future<Map<String, Map<String, dynamic>>> getFtpProfiles() async {
    final prefs = await _getPrefs();
    final profilesJson = prefs.getString(_keyFtpProfiles);
    if (profilesJson != null) {
      try {
        final Map<String, dynamic> profilesMap = json.decode(profilesJson);
        return profilesMap.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      } catch (e) {
        print('Error parsing FTP profiles: $e');
      }
    }
    return <String, Map<String, dynamic>>{};
  }

  Future<void> saveFtpProfiles(
      Map<String, Map<String, dynamic>> profiles) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyFtpProfiles, json.encode(profiles));
    _afterLocalPreferencesChanged();
  }

  // Current FTP Profile
  Future<String?> getCurrentFtpProfile() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyCurrentFtpProfile);
  }

  Future<void> saveCurrentFtpProfile(String? profileName) async {
    final prefs = await _getPrefs();
    if (profileName != null) {
      await prefs.setString(_keyCurrentFtpProfile, profileName);
    } else {
      await prefs.remove(_keyCurrentFtpProfile);
    }
    _afterLocalPreferencesChanged();
  }

  // Firebar Position Preference
  Future<bool> getPlaceFirebarOnRight() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyPlaceFirebarOnRight) ?? true;
  }

  Future<void> savePlaceFirebarOnRight(bool placeOnRight) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyPlaceFirebarOnRight, placeOnRight);
    _afterLocalPreferencesChanged();
  }

  // Last Saved Metadata
  Future<Map<String, dynamic>?> getLastSavedMetadata() async {
    final prefs = await _getPrefs();
    final metadataJson = prefs.getString(_keyLastSavedMetadata);
    if (metadataJson != null) {
      try {
        final Map<String, dynamic> metadata = json.decode(metadataJson);
        return metadata;
      } catch (e) {
        print('Error parsing last saved metadata: $e');
      }
    }
    return null;
  }

  Future<void> saveLastSavedMetadata(Map<String, dynamic>? metadata) async {
    final prefs = await _getPrefs();
    if (metadata != null) {
      await prefs.setString(_keyLastSavedMetadata, json.encode(metadata));
    } else {
      await prefs.remove(_keyLastSavedMetadata);
    }
  }

  // Custom Verb Wordings (per sport)
  Future<Map<String, String>> getCustomVerbWordings(
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getCustomVerbWordingsKey(sport);
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (e) {
        print('Error parsing custom verb wordings for ' +
            sport +
            ': ' +
            e.toString());
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['customVerbWordings'] != null) {
      try {
        final m = sportDefault['customVerbWordings'] as Map<String, dynamic>;
        return m.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    return <String, String>{};
  }

  Future<void> saveCustomVerbWording(String verb, String wording,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getCustomVerbWordingsKey(sport);
    final existing = await getCustomVerbWordings(sport: sport);
    existing[verb] = wording;
    await prefs.setString(key, json.encode(existing));
    _afterLocalPreferencesChanged();
  }

  Future<void> removeCustomVerbWording(String verb,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getCustomVerbWordingsKey(sport);
    final existing = await getCustomVerbWordings(sport: sport);
    existing.remove(verb);
    if (existing.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, json.encode(existing));
    }
    _afterLocalPreferencesChanged();
  }

  // Serial Number Bylines Preference
  Future<bool> getSerialNumberBylines() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keySerialNumberBylines) ?? false;
  }

  Future<void> saveSerialNumberBylines(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keySerialNumberBylines, enabled);
  }

  Future<bool> getApplyVerbKeywords() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyApplyVerbKeywords) ?? true;
  }

  Future<void> saveApplyVerbKeywords(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyApplyVerbKeywords, enabled);
  }

  Future<bool> getApplyPlayerNamesToKeywords() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyApplyPlayerNamesToKeywords) ?? true;
  }

  Future<void> saveApplyPlayerNamesToKeywords(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyApplyPlayerNamesToKeywords, enabled);
  }

  // Resolution Warning Threshold Preference
  Future<int> getResolutionWarningThreshold() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_keyResolutionWarningThreshold) ?? 3000;
  }

  Future<void> saveResolutionWarningThreshold(int threshold) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyResolutionWarningThreshold, threshold);
  }

  // Photoshop Path Preference
  Future<String?> getPhotoshopPath() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyPhotoshopPath);
  }

  Future<void> savePhotoshopPath(String? path) async {
    final prefs = await _getPrefs();
    if (path != null && path.isNotEmpty) {
      await prefs.setString(_keyPhotoshopPath, path);
    } else {
      await prefs.remove(_keyPhotoshopPath);
    }
  }

  // Current Layout Preference
  Future<String> getCurrentLayout() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyCurrentLayout) ?? 'player_popup_board';
  }

  Future<void> saveCurrentLayout(String layout) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCurrentLayout, layout);
  }

  /// Caption entry: 'keyboard_fire' (default) or 'classic'.
  Future<String> getCaptionEntryMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyCaptionEntryMode) ?? 'keyboard_fire';
  }

  Future<void> saveCaptionEntryMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCaptionEntryMode, mode);
    _afterLocalPreferencesChanged();
  }

  // Custom Verbs (user-created verbs)
  String _getCustomVerbsKey(String sport) {
    return '${_keyCustomVerbs}_${sport.toLowerCase()}';
  }

  Future<List<Map<String, dynamic>>> getCustomVerbs({String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getCustomVerbsKey(sport);
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = json.decode(jsonString);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        print('Error parsing custom verbs for $sport: $e');
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['customVerbs'] != null) {
      try {
        return (sportDefault['customVerbs'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> saveCustomVerbs(List<Map<String, dynamic>> verbs, {String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getCustomVerbsKey(sport);
    await prefs.setString(key, json.encode(verbs));
    _afterLocalPreferencesChanged();
  }

  Future<void> addCustomVerb(Map<String, dynamic> verb, {String sport = 'hockey'}) async {
    final verbs = await getCustomVerbs(sport: sport);
    verbs.add(verb);
    await saveCustomVerbs(verbs, sport: sport);
  }

  Future<void> removeCustomVerb(String verbPhrase, {String sport = 'hockey'}) async {
    final verbs = await getCustomVerbs(sport: sport);
    verbs.removeWhere((v) => v['verbPhrase'] == verbPhrase);
    await saveCustomVerbs(verbs, sport: sport);
  }

  // Verb Overrides (modifications to built-in verbs)
  String _getVerbOverridesKey(String sport) {
    return '${_keyVerbOverrides}_${sport.toLowerCase()}';
  }

  Future<Map<String, Map<String, dynamic>>> getVerbOverrides({String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getVerbOverridesKey(sport);
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      } catch (e) {
        print('Error parsing verb overrides for $sport: $e');
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['verbOverrides'] != null) {
      try {
        final m = sportDefault['verbOverrides'] as Map<String, dynamic>;
        return m.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      } catch (_) {}
    }
    return {};
  }

  Future<void> saveVerbOverride(String originalVerbPhrase, Map<String, dynamic> override, {String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getVerbOverridesKey(sport);
    final overrides = await getVerbOverrides(sport: sport);
    overrides[originalVerbPhrase] = override;
    await prefs.setString(key, json.encode(overrides));
    _afterLocalPreferencesChanged();
  }

  Future<void> removeVerbOverride(String originalVerbPhrase, {String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getVerbOverridesKey(sport);
    final overrides = await getVerbOverrides(sport: sport);
    overrides.remove(originalVerbPhrase);
    if (overrides.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, json.encode(overrides));
    }
    _afterLocalPreferencesChanged();
  }

  // Deleted Verbs (for tracking deleted built-in verbs during reorganization)
  String _getDeletedVerbsKey(String sport) {
    return '${_keyDeletedVerbs}_${sport.toLowerCase()}';
  }

  Future<Set<String>> getDeletedVerbs({String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getDeletedVerbsKey(sport);
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = json.decode(jsonString);
        return decoded.cast<String>().toSet();
      } catch (e) {
        print('Error parsing deleted verbs for $sport: $e');
      }
    }
    final sportDefault = await getSportDefault(sport);
    if (sportDefault != null && sportDefault['deletedVerbs'] != null) {
      try {
        return Set<String>.from(sportDefault['deletedVerbs'] as List<dynamic>);
      } catch (_) {}
    }
    return <String>{};
  }

  Future<void> saveDeletedVerbs(Set<String> deletedVerbs, {String sport = 'hockey'}) async {
    final prefs = await _getPrefs();
    final key = _getDeletedVerbsKey(sport);
    if (deletedVerbs.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, json.encode(deletedVerbs.toList()));
    }
    _afterLocalPreferencesChanged();
  }

  Future<void> addDeletedVerb(String verbPhrase, {String sport = 'hockey'}) async {
    final deletedVerbs = await getDeletedVerbs(sport: sport);
    deletedVerbs.add(verbPhrase);
    await saveDeletedVerbs(deletedVerbs, sport: sport);
  }

  Future<void> removeDeletedVerb(String verbPhrase, {String sport = 'hockey'}) async {
    final deletedVerbs = await getDeletedVerbs(sport: sport);
    deletedVerbs.remove(verbPhrase);
    await saveDeletedVerbs(deletedVerbs, sport: sport);
  }

  /// Saves the current effective state for [sport] as that sport's default (used when user has no prefs yet).
  Future<void> setCurrentSportAsDefault(String sport) async {
    final data = {
      'categoryOrder': await getCategoryOrder(sport: sport),
      'verbOrder': await getVerbOrder(sport: sport),
      'favoriteVerbs': (await getFavoriteVerbs(sport: sport)).toList(),
      'favoriteTeams': (await getFavoriteTeams(sport: sport)).toList(),
      'customVerbWordings': await getCustomVerbWordings(sport: sport),
      'verbOverrides': await getVerbOverrides(sport: sport),
      'customVerbs': await getCustomVerbs(sport: sport),
      'deletedVerbs': (await getDeletedVerbs(sport: sport)).toList(),
    };
    await setSportDefault(sport, data);
  }

  // Sync server (your hosted endpoint for cloud sync)
  Future<String> getSyncServerUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keySyncServerUrl) ?? '';
  }

  Future<void> setSyncServerUrl(String url) async {
    final prefs = await _getPrefs();
    if (url.isEmpty) {
      await prefs.remove(_keySyncServerUrl);
    } else {
      await prefs.setString(_keySyncServerUrl, url.trim());
    }
  }

  Future<String> getSyncAccountId() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keySyncAccountId) ?? '';
  }

  Future<void> setSyncAccountId(String id) async {
    final prefs = await _getPrefs();
    if (id.isEmpty) {
      await prefs.remove(_keySyncAccountId);
    } else {
      await prefs.setString(_keySyncAccountId, id.trim());
    }
  }

  Future<int> getUserPreferencesUpdatedAtMs() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_keyUserPreferencesUpdatedAtMs) ?? 0;
  }

  Future<void> touchUserPreferencesUpdatedAt() async {
    final prefs = await _getPrefs();
    await prefs.setInt(
      _keyUserPreferencesUpdatedAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> markCloudPreferencesSynced(int updatedAtMs) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyUserPreferencesUpdatedAtMs, updatedAtMs);
    await prefs.setInt(_keyUserPreferencesCloudUpdatedAtMs, updatedAtMs);
  }

  /// Applies a cloud bundle without triggering an immediate re-upload.
  Future<void> applyCloudPreferences(
    Map<String, dynamic> preferences,
    int cloudUpdatedAtMs,
  ) async {
    _suppressCloudSync = true;
    try {
      await importPreferences(preferences);
      await markCloudPreferencesSynced(cloudUpdatedAtMs);
    } finally {
      _suppressCloudSync = false;
    }
    cloudPreferencesAppliedController.add(null);
  }

  void _afterLocalPreferencesChanged() {
    if (_suppressCloudSync) return;
    unawaited(_afterLocalPreferencesChangedAsync());
  }

  Future<void> _afterLocalPreferencesChangedAsync() async {
    if (_suppressCloudSync) return;
    await touchUserPreferencesUpdatedAt();
    UserPreferencesFirestoreService.scheduleUpload(this);
  }

  Future<Map<String, String>> _exportCaptionWireLabels() async {
    final out = <String, String>{};
    for (final wire in WireStyle.values) {
      if (wire == WireStyle.custom) continue;
      final label = await getCaptionWireLabel(wire);
      if (label != null && label.trim().isNotEmpty) {
        out[wire.name] = label.trim();
      }
    }
    return out;
  }

  Future<Map<String, String>> _exportFavoriteCaptionStyleBySport() async {
    const sports = ['baseball', 'hockey', 'basketball', 'soccer'];
    final out = <String, String>{};
    for (final sport in sports) {
      final token = await getFavoriteCaptionStyleToken(sport: sport);
      if (token != null && token.trim().isNotEmpty) {
        out[sport] = token.trim();
      }
    }
    return out;
  }

  /// Preferences bundle for cloud sync (excludes device-local account metadata).
  Future<Map<String, dynamic>> exportSyncablePreferences() async {
    final bundle = await exportAllPreferences();
    bundle.remove('syncAccountId');
    bundle.remove('syncServerUrl');
    return bundle;
  }

  Future<String> getMlbInningExifTimezone() async {
    final prefs = await _getPrefs();
    final v = prefs.getString(_keyMlbInningExifTimezone);
    if (v == null || v.trim().isEmpty) {
      return mlbInningExifTimezoneDefault;
    }
    return v.trim();
  }

  Future<void> setMlbInningExifTimezone(String iana) async {
    final prefs = await _getPrefs();
    final t = iana.trim();
    if (t.isEmpty) {
      await prefs.remove(_keyMlbInningExifTimezone);
    } else {
      await prefs.setString(_keyMlbInningExifTimezone, t);
    }
  }

  /// When true (default), baseball photos auto-resolve inning from MLB vs EXIF.
  Future<bool> getMlbInningFromClockEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyMlbInningFromClockEnabled) ?? true;
  }

  Future<void> setMlbInningFromClockEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyMlbInningFromClockEnabled, enabled);
  }

  /// Exports all preferences as JSON, including per-sport verb settings so they can be saved and passed on.
  Future<Map<String, dynamic>> exportAllPreferences() async {
    const sports = ['baseball', 'hockey', 'basketball', 'soccer'];
    final verbSettingsBySport = <String, Map<String, dynamic>>{};
    for (final sport in sports) {
      verbSettingsBySport[sport] = {
        'categoryOrder': await getCategoryOrder(sport: sport),
        'verbOrder': await getVerbOrder(sport: sport),
        'favoriteVerbs': (await getFavoriteVerbs(sport: sport)).toList(),
        'favoriteTeams': (await getFavoriteTeams(sport: sport)).toList(),
        'customVerbWordings': await getCustomVerbWordings(sport: sport),
        'verbOverrides': await getVerbOverrides(sport: sport),
        'customVerbs': await getCustomVerbs(sport: sport),
        'deletedVerbs': (await getDeletedVerbs(sport: sport)).toList(),
      };
    }
    final captionWireDefaultGetty =
        await getCaptionTemplateWireDefault(WireStyle.getty);
    final captionWireDefaultImagn =
        await getCaptionTemplateWireDefault(WireStyle.imagn);
    final captionWireDefaultAp =
        await getCaptionTemplateWireDefault(WireStyle.ap);
    final captionWireDefaultCp =
        await getCaptionTemplateWireDefault(WireStyle.cp);
    final captionWireDefaultGettyIntl =
        await getCaptionTemplateWireDefault(WireStyle.gettyInternational);
    return {
      'version': 2,
      'currentSport': await getCurrentSport(),
      'verbSettingsBySport': verbSettingsBySport,
      'categoryOrder': await getCategoryOrder(),
      'favoriteVerbs': (await getFavoriteVerbs()).toList(),
      'favoriteTeams': (await getFavoriteTeams()).toList(),
      'syncServerUrl': await getSyncServerUrl(),
      'syncAccountId': await getSyncAccountId(),
      'mlbInningExifTimezone': await getMlbInningExifTimezone(),
      'mlbInningFromClockEnabled': await getMlbInningFromClockEnabled(),
      'ftpProfiles': await getFtpProfiles(),
      'currentFtpProfile': await getCurrentFtpProfile(),
      'placeFirebarOnRight': await getPlaceFirebarOnRight(),
      'lastSavedMetadata': await getLastSavedMetadata(),
      'currentLayout': await getCurrentLayout(),
      'captionEntryMode': await getCaptionEntryMode(),
      'showHeadlineField': await getShowHeadlineField(),
      'showKeywordsField': await getShowKeywordsField(),
      'showPersonalityField': await getShowPersonalityField(),
      'burstDetectionEnabled': await getBurstDetectionEnabled(),
      'captionLayoutOrder': await getCaptionLayoutOrder(),
      'captionLayoutFlavor': await getCaptionLayoutFlavor(),
      'captionTemplate': (await getCaptionTemplate()).toJson(),
      'captionStyleLibrary':
          (await getCaptionStyleLibrary()).map((e) => e.toJson()).toList(),
      'captionTemplateWireDefaults': <String, dynamic>{
        if (captionWireDefaultGetty != null)
          'getty': CaptionTemplate.wireMasterJsonFromTemplate(
            captionWireDefaultGetty,
          ),
        if (captionWireDefaultImagn != null)
          'imagn': CaptionTemplate.wireMasterJsonFromTemplate(
            captionWireDefaultImagn,
          ),
        if (captionWireDefaultAp != null)
          'ap': CaptionTemplate.wireMasterJsonFromTemplate(captionWireDefaultAp),
        if (captionWireDefaultCp != null)
          'cp': CaptionTemplate.wireMasterJsonFromTemplate(captionWireDefaultCp),
        if (captionWireDefaultGettyIntl != null)
          'gettyInternational': CaptionTemplate.wireMasterJsonFromTemplate(
            captionWireDefaultGettyIntl,
          ),
      },
      'gameIdentifierByWireAndSport':
          await getGameIdentifierByWireAndSport(),
      'captionGameInfo': (await getCaptionGameInfo()).toJson(),
      'captionCreditSampleAgency': await getCaptionCreditSampleAgency(),
      'captionWireLabels': await _exportCaptionWireLabels(),
      'favoriteCaptionStyleBySport': await _exportFavoriteCaptionStyleBySport(),
    };
  }

  /// Saves the current preferences as the "default" bundle. Reset to defaults will restore this if present.
  Future<void> saveAsDefaultPreferences() async {
    final prefs = await _getPrefs();
    final bundle = await exportAllPreferences();
    await prefs.setString(_keySavedDefaultPreferences, json.encode(bundle));
  }

  /// Returns the saved default bundle, or null if none.
  Future<Map<String, dynamic>?> getSavedDefaultPreferences() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keySavedDefaultPreferences);
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Imports preferences from JSON (export format). Supports full verbSettingsBySport and legacy flat keys.
  Future<void> importPreferences(Map<String, dynamic> preferences) async {
    if (preferences.containsKey('verbSettingsBySport')) {
      final bySport = preferences['verbSettingsBySport'] as Map<String, dynamic>;
      for (final entry in bySport.entries) {
        final sport = entry.key;
        final data = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
        if (data.containsKey('categoryOrder')) {
          await saveCategoryOrder(List<String>.from(data['categoryOrder']), sport: sport);
        }
        if (data.containsKey('favoriteVerbs')) {
          await saveFavoriteVerbs(Set<String>.from(data['favoriteVerbs']), sport: sport);
        }
        if (data.containsKey('favoriteTeams')) {
          await saveFavoriteTeams(Set<String>.from(data['favoriteTeams']), sport: sport);
        }
        if (data.containsKey('customVerbWordings')) {
          final existing = await getCustomVerbWordings(sport: sport);
          for (final k in existing.keys) {
            await removeCustomVerbWording(k, sport: sport);
          }
          final wordings = Map<String, dynamic>.from(data['customVerbWordings']);
          for (final w in wordings.entries) {
            await saveCustomVerbWording(w.key, w.value.toString(), sport: sport);
          }
        }
        if (data.containsKey('verbOverrides')) {
          final existing = await getVerbOverrides(sport: sport);
          for (final k in existing.keys) {
            await removeVerbOverride(k, sport: sport);
          }
          final overrides = data['verbOverrides'] as Map<String, dynamic>;
          for (final o in overrides.entries) {
            await saveVerbOverride(o.key, Map<String, dynamic>.from(o.value as Map<String, dynamic>), sport: sport);
          }
        }
        if (data.containsKey('customVerbs')) {
          await saveCustomVerbs((data['customVerbs'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList(), sport: sport);
        }
        if (data.containsKey('deletedVerbs')) {
          await saveDeletedVerbs(Set<String>.from(data['deletedVerbs']), sport: sport);
        }
        if (data.containsKey('verbOrder')) {
          final vo = data['verbOrder'];
          if (vo is Map<String, dynamic>) {
            await saveVerbOrder(
              vo.map(
                (k, v) => MapEntry(
                  k,
                  List<String>.from(v as List<dynamic>),
                ),
              ),
              sport: sport,
            );
          }
        }
      }
    }
    if (preferences.containsKey('currentSport')) {
      await saveCurrentSport(preferences['currentSport'] as String);
    }
    if (preferences.containsKey('syncServerUrl')) {
      await setSyncServerUrl(preferences['syncServerUrl'] as String? ?? '');
    }
    if (preferences.containsKey('syncAccountId')) {
      await setSyncAccountId(preferences['syncAccountId'] as String? ?? '');
    }
    if (preferences.containsKey('mlbInningExifTimezone')) {
      await setMlbInningExifTimezone(
          preferences['mlbInningExifTimezone'] as String? ?? '');
    }
    if (preferences.containsKey('mlbInningFromClockEnabled')) {
      await setMlbInningFromClockEnabled(
        preferences['mlbInningFromClockEnabled'] as bool? ?? true,
      );
    }
    if (preferences.containsKey('useBallDontLieApi')) {
      final prefs = await _getPrefs();
      await prefs.remove('use_balldontlie_api');
    }
    if (preferences.containsKey('categoryOrder')) {
      await saveCategoryOrder(List<String>.from(preferences['categoryOrder']));
    }
    if (preferences.containsKey('favoriteVerbs')) {
      await saveFavoriteVerbs(Set<String>.from(preferences['favoriteVerbs']));
    }
    if (preferences.containsKey('favoriteTeams')) {
      await saveFavoriteTeams(Set<String>.from(preferences['favoriteTeams']));
    }
    if (preferences.containsKey('ftpProfiles')) {
      final profiles = Map<String, Map<String, dynamic>>.from(
          (preferences['ftpProfiles'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));
      await saveFtpProfiles(profiles);
    }
    if (preferences.containsKey('currentFtpProfile')) {
      await saveCurrentFtpProfile(preferences['currentFtpProfile']);
    }
    if (preferences.containsKey('placeFirebarOnRight')) {
      await savePlaceFirebarOnRight(preferences['placeFirebarOnRight'] as bool);
    }
    if (preferences.containsKey('lastSavedMetadata')) {
      await saveLastSavedMetadata(
          Map<String, dynamic>.from(preferences['lastSavedMetadata']));
    }
    if (preferences.containsKey('currentLayout')) {
      await saveCurrentLayout(preferences['currentLayout'] as String);
    }
    if (preferences.containsKey('captionEntryMode')) {
      await saveCaptionEntryMode(preferences['captionEntryMode'] as String);
    }
    if (preferences.containsKey('showHeadlineField')) {
      await saveShowHeadlineField(preferences['showHeadlineField'] as bool);
    }
    if (preferences.containsKey('showKeywordsField')) {
      await saveShowKeywordsField(preferences['showKeywordsField'] as bool);
    }
    if (preferences.containsKey('showPersonalityField')) {
      await saveShowPersonalityField(preferences['showPersonalityField'] as bool);
    }
    if (preferences.containsKey('burstDetectionEnabled')) {
      await saveBurstDetectionEnabled(
          preferences['burstDetectionEnabled'] as bool);
    }
    if (preferences.containsKey('captionLayoutOrder')) {
      await saveCaptionLayoutOrder(
        List<String>.from(preferences['captionLayoutOrder'] as List<dynamic>),
      );
    }
    if (preferences.containsKey('captionLayoutFlavor')) {
      await saveCaptionLayoutFlavor(
        preferences['captionLayoutFlavor'] as String,
      );
    }
    if (preferences.containsKey('captionTemplate')) {
      final raw = preferences['captionTemplate'];
      if (raw is Map<String, dynamic>) {
        await saveCaptionTemplate(CaptionTemplate.fromJson(raw));
      } else if (raw is String && raw.isNotEmpty) {
        final t = CaptionTemplate.tryDecode(raw);
        if (t != null) await saveCaptionTemplate(t);
      }
    }
    if (preferences.containsKey('captionGameInfo')) {
      final raw = preferences['captionGameInfo'];
      if (raw is Map<String, dynamic>) {
        await saveCaptionGameInfo(GameInfo.fromJson(raw));
      }
    }
    if (preferences.containsKey('captionCreditSampleAgency')) {
      await saveCaptionCreditSampleAgency(
        preferences['captionCreditSampleAgency'] as String? ?? 'gettyImages',
      );
    }
    if (preferences.containsKey('captionTemplateWireDefaults')) {
      final raw = preferences['captionTemplateWireDefaults'];
      if (raw is Map<String, dynamic>) {
        for (final name in [
          'getty',
          'imagn',
          'ap',
          'cp',
          'gettyInternational',
        ]) {
          final entry = raw[name];
          if (entry is Map<String, dynamic>) {
            await saveCaptionTemplateWireDefault(
              WireStyle.values.firstWhere((e) => e.name == name),
              CaptionTemplate.fromJson(Map<String, dynamic>.from(entry)),
            );
          }
        }
      }
    }
    if (preferences.containsKey('gameIdentifierByWireAndSport')) {
      final raw = preferences['gameIdentifierByWireAndSport'];
      if (raw is Map) {
        final map = <String, Map<String, String>>{};
        raw.forEach((wireKey, sportMap) {
          if (sportMap is! Map) return;
          final bySport = <String, String>{};
          sportMap.forEach((sportKey, value) {
            final text = value?.toString().trim() ?? '';
            if (text.isNotEmpty) {
              bySport[sportKey.toString().toLowerCase().trim()] = text;
            }
          });
          if (bySport.isNotEmpty) map[wireKey.toString()] = bySport;
        });
        await saveGameIdentifierByWireAndSport(map);
      }
    }
    if (preferences.containsKey('captionStyleLibrary')) {
      final raw = preferences['captionStyleLibrary'];
      if (raw is List) {
        final list = <CaptionStyleLibraryEntry>[];
        for (final e in raw) {
          if (e is! Map) continue;
          try {
            list.add(CaptionStyleLibraryEntry.fromJson(
              Map<String, dynamic>.from(e),
            ));
          } catch (_) {}
        }
        await _saveCaptionStyleLibrary(list);
      }
    }
    if (preferences.containsKey('captionWireLabels')) {
      final raw = preferences['captionWireLabels'];
      if (raw is Map) {
        for (final wire in WireStyle.values) {
          if (wire == WireStyle.custom) continue;
          final label = raw[wire.name]?.toString();
          await saveCaptionWireLabel(wire, label);
        }
      }
    }
    if (preferences.containsKey('favoriteCaptionStyleBySport')) {
      final raw = preferences['favoriteCaptionStyleBySport'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final sport = entry.key.toString();
          final token = entry.value?.toString();
          if (token == null || token.trim().isEmpty) {
            await saveFavoriteCaptionStyleToken(null, sport: sport);
          } else {
            await saveFavoriteCaptionStyleToken(token.trim(), sport: sport);
          }
        }
      }
    }
    if (!_suppressCloudSync) {
      _afterLocalPreferencesChanged();
    }
  }

  Future<List<String>> getCaptionLayoutOrder() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keyCaptionLayoutOrder);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCaptionLayoutOrder(List<String> order) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCaptionLayoutOrder, json.encode(order));
    _afterLocalPreferencesChanged();
  }

  /// Returns `getty` or `imagn`.
  Future<String> getCaptionLayoutFlavor() async {
    final prefs = await _getPrefs();
    final v = prefs.getString(_keyCaptionLayoutFlavor);
    if (v == 'imagn') return 'imagn';
    if (v == 'getty') return 'getty';
    return 'getty';
  }

  Future<void> saveCaptionLayoutFlavor(String flavor) async {
    final prefs = await _getPrefs();
    final v = flavor == 'imagn' ? 'imagn' : 'getty';
    await prefs.setString(_keyCaptionLayoutFlavor, v);
    _afterLocalPreferencesChanged();
  }

  /// Full caption wire template (presets + custom). Migrates legacy order/flavor once if needed.
  Future<CaptionTemplate> getCaptionTemplate() async {
    final prefs = await _getPrefs();
    final sport = await getCurrentSport();
    final raw = prefs.getString(_keyCaptionTemplateJson);
    final decoded = CaptionTemplate.tryDecode(raw);
    CaptionTemplate template;
    if (decoded != null) {
      // One-time: templates saved before per-style layout options stored globals.
      if (raw != null && !raw.contains('"showKeywordsField"')) {
        template = decoded.copyWith(
          showKeywordsField: prefs.getBool(_keyShowKeywordsField) ?? false,
          showPersonalityField: prefs.getBool(_keyShowPersonalityField) ?? true,
        );
      } else {
        template = decoded;
      }
    } else {
      final migrated = await _migrateCaptionTemplateFromLegacy();
      template = migrated ?? CaptionTemplate.getty();
    }
    return await applyGameIdentifierForSport(template, template.wireStyle, sport);
  }

  Future<CaptionTemplate?> _migrateCaptionTemplateFromLegacy() async {
    final prefs = await _getPrefs();
    if (!prefs.containsKey(_keyCaptionLayoutOrder) &&
        !prefs.containsKey(_keyCaptionLayoutFlavor)) {
      return null;
    }
    final order = await getCaptionLayoutOrder();
    final flavor = await getCaptionLayoutFlavor();
    if (order.isEmpty) {
      return flavor == 'imagn' ? CaptionTemplate.imagn() : CaptionTemplate.getty();
    }
    return CaptionTemplate.fromLegacySegmentOrder(order, flavor);
  }

  Future<void> saveCaptionTemplate(CaptionTemplate template) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCaptionTemplateJson, template.encode());
    await prefs.remove(_keyCaptionLayoutOrder);
    await prefs.remove(_keyCaptionLayoutFlavor);
    // Keep legacy global keys in sync with the active caption style.
    await prefs.setBool(_keyShowKeywordsField, template.showKeywordsField);
    await prefs.setBool(_keyShowPersonalityField, template.showPersonalityField);
    _notifyCaptionFieldVisibilityChanged();
    _afterLocalPreferencesChanged();
  }

  static String? _captionTemplateWireDefaultKey(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
        return _keyCaptionTemplateDefaultGettyJson;
      case WireStyle.imagn:
        return _keyCaptionTemplateDefaultImagnJson;
      case WireStyle.ap:
        return _keyCaptionTemplateDefaultApJson;
      case WireStyle.cp:
        return _keyCaptionTemplateDefaultCpJson;
      case WireStyle.gettyInternational:
        return _keyCaptionTemplateDefaultGettyInternationalJson;
      case WireStyle.custom:
        return null;
    }
  }

  /// User-saved baseline for a wire (used when switching to that wire in the layout builder).
  Future<CaptionTemplate?> getCaptionTemplateWireDefault(WireStyle wire) async {
    final key = _captionTemplateWireDefaultKey(wire);
    if (key == null) return null;
    final prefs = await _getPrefs();
    final decoded = CaptionTemplate.tryDecode(prefs.getString(key));
    if (decoded == null) return null;
    final sport = await getCurrentSport();
    return applyGameIdentifierForSport(decoded, wire, sport);
  }

  Future<void> saveCaptionTemplateWireDefault(
    WireStyle wire,
    CaptionTemplate template,
  ) async {
    final key = _captionTemplateWireDefaultKey(wire);
    if (key == null) return;
    final prefs = await _getPrefs();
    final normalized = template.copyWith(wireStyle: wire);
    await prefs.setString(key, normalized.encode());
    _afterLocalPreferencesChanged();
  }

  Future<void> clearCaptionTemplateWireDefault(WireStyle wire) async {
    final key = _captionTemplateWireDefaultKey(wire);
    if (key == null) return;
    final prefs = await _getPrefs();
    await prefs.remove(key);
    _afterLocalPreferencesChanged();
  }

  static String? _captionWireLabelKey(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
        return _keyCaptionWireLabelGetty;
      case WireStyle.imagn:
        return _keyCaptionWireLabelImagn;
      case WireStyle.ap:
        return _keyCaptionWireLabelAp;
      case WireStyle.cp:
        return _keyCaptionWireLabelCp;
      case WireStyle.gettyInternational:
        return _keyCaptionWireLabelGettyInternational;
      case WireStyle.custom:
        return null;
    }
  }

  /// User's custom label for a built-in wire in the Caption Style menu,
  /// or `null` if the factory name (Getty USA / Imagn / AP) should be shown.
  Future<String?> getCaptionWireLabel(WireStyle wire) async {
    final key = _captionWireLabelKey(wire);
    if (key == null) return null;
    final prefs = await _getPrefs();
    final v = prefs.getString(key);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Pass [label] = null or empty to restore the factory wire name.
  Future<void> saveCaptionWireLabel(WireStyle wire, String? label) async {
    final key = _captionWireLabelKey(wire);
    if (key == null) return;
    final prefs = await _getPrefs();
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, trimmed);
    }
    _afterLocalPreferencesChanged();
  }

  /// One-time migration: if the user had saved a library entry called
  /// "Getty International" before it became a built-in wire, promote it to
  /// [WireStyle.gettyInternational]'s wire default and drop it from the
  /// library so the Caption Style menu doesn't double up.
  ///
  /// Safe to call repeatedly — [_keyGettyInternationalMigrationDone] short-
  /// circuits subsequent runs.
  Future<void> migrateGettyInternationalLibraryEntry() async {
    final prefs = await _getPrefs();
    if (prefs.getBool(_keyGettyInternationalMigrationDone) == true) return;
    final lib = await getCaptionStyleLibrary();
    final matches = lib
        .where((e) =>
            e.displayName.trim().toLowerCase() == 'getty international')
        .toList();
    if (matches.isEmpty) {
      await prefs.setBool(_keyGettyInternationalMigrationDone, true);
      return;
    }
    final first = matches.first;
    final existingWireDefault =
        await getCaptionTemplateWireDefault(WireStyle.gettyInternational);
    if (existingWireDefault == null) {
      await saveCaptionTemplateWireDefault(
        WireStyle.gettyInternational,
        first.template.copyWith(wireStyle: WireStyle.gettyInternational),
      );
    }
    final remaining =
        lib.where((e) => !matches.any((m) => m.id == e.id)).toList();
    await _saveCaptionStyleLibrary(remaining);
    await prefs.setBool(_keyGettyInternationalMigrationDone, true);
  }

  /// User-named layouts saved from the caption layout builder (not the active template).
  Future<List<CaptionStyleLibraryEntry>> getCaptionStyleLibrary() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keyCaptionStyleLibraryJson);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      final out = <CaptionStyleLibraryEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        try {
          out.add(CaptionStyleLibraryEntry.fromJson(
            Map<String, dynamic>.from(e),
          ));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCaptionStyleLibrary(
    List<CaptionStyleLibraryEntry> entries,
  ) async {
    final prefs = await _getPrefs();
    final encoded = json.encode(entries.map((e) => e.toJson()).toList());
    final ok = await prefs.setString(_keyCaptionStyleLibraryJson, encoded);
    if (!ok) {
      throw StateError(
        'Could not write caption style library (preferences storage rejected the write).',
      );
    }
    _afterLocalPreferencesChanged();
  }

  /// Appends a deep copy of [template] with a stable library [id] and [displayName].
  /// Returns the new entry’s [CaptionStyleLibraryEntry.id].
  Future<String> addCaptionStyleToLibrary({
    required String displayName,
    required CaptionTemplate template,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(displayName, 'displayName', 'must be non-empty');
    }
    final id = 'saved_${DateTime.now().millisecondsSinceEpoch}';
    final raw = json.decode(json.encode(template.toJson())) as Map<String, dynamic>;
    final stored = CaptionTemplate.fromJson(raw).copyWith(id: id, name: name);
    final entry = CaptionStyleLibraryEntry(
      id: id,
      displayName: name,
      template: stored,
    );
    final list = [...await getCaptionStyleLibrary(), entry];
    await _saveCaptionStyleLibrary(list);
    return id;
  }

  /// Removes one entry from the saved caption style library by [id].
  Future<void> removeCaptionStyleFromLibrary(String id) async {
    if (id.isEmpty) return;
    final list =
        (await getCaptionStyleLibrary()).where((e) => e.id != id).toList();
    await _saveCaptionStyleLibrary(list);
  }

  /// Updates the display name (and template [CaptionTemplate.name]) for one library entry.
  Future<void> renameCaptionStyleInLibrary({
    required String id,
    required String newDisplayName,
  }) async {
    final name = newDisplayName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(newDisplayName, 'newDisplayName', 'must be non-empty');
    }
    final list = await getCaptionStyleLibrary();
    final out = <CaptionStyleLibraryEntry>[];
    var found = false;
    for (final e in list) {
      if (e.id == id) {
        found = true;
        final t = e.template.copyWith(name: name);
        out.add(CaptionStyleLibraryEntry(
          id: e.id,
          displayName: name,
          template: t,
        ));
      } else {
        out.add(e);
      }
    }
    if (!found) {
      throw StateError('No saved caption style with id "$id".');
    }
    await _saveCaptionStyleLibrary(out);
  }

  /// Replaces the stored [CaptionTemplate] for one library row (same [id] and display name).
  /// Used when the user edits the active layout while a saved caption style is selected.
  Future<void> updateCaptionStyleTemplateInLibrary({
    required String id,
    required CaptionTemplate template,
  }) async {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be non-empty');
    }
    final list = await getCaptionStyleLibrary();
    final out = <CaptionStyleLibraryEntry>[];
    var found = false;
    for (final e in list) {
      if (e.id == id) {
        found = true;
        final raw =
            json.decode(json.encode(template.toJson())) as Map<String, dynamic>;
        final stored = CaptionTemplate.fromJson(raw).copyWith(
          id: e.id,
          name: e.displayName,
        );
        out.add(CaptionStyleLibraryEntry(
          id: e.id,
          displayName: e.displayName,
          template: stored,
        ));
      } else {
        out.add(e);
      }
    }
    if (!found) {
      throw StateError('No saved caption style with id "$id".');
    }
    await _saveCaptionStyleLibrary(out);
  }

  Future<GameInfo> getCaptionGameInfo() async {
    final prefs = await _getPrefs();
    return GameInfo.tryDecode(prefs.getString(_keyCaptionGameInfoJson)) ??
        const GameInfo();
  }

  Future<void> saveCaptionGameInfo(GameInfo info) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCaptionGameInfoJson, info.encode());
    _afterLocalPreferencesChanged();
  }

  Future<void> saveLastCaptionPreviewTeams({
    required String sport,
    required String homeTeam,
    required String awayTeam,
  }) async {
    final prefs = await _getPrefs();
    final s = sport.toLowerCase().trim();
    await prefs.setString('$_keyCaptionPreviewHomePrefix$s', homeTeam);
    await prefs.setString('$_keyCaptionPreviewAwayPrefix$s', awayTeam);
  }

  Future<MapEntry<String?, String?>> getLastCaptionPreviewTeams({
    required String sport,
  }) async {
    final prefs = await _getPrefs();
    final s = sport.toLowerCase().trim();
    return MapEntry(
      prefs.getString('$_keyCaptionPreviewHomePrefix$s'),
      prefs.getString('$_keyCaptionPreviewAwayPrefix$s'),
    );
  }

  /// Menu token for the user's favorite caption layout style (per sport).
  Future<String?> getFavoriteCaptionStyleToken({String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    return prefs.getString(
      '${_keyFavoriteCaptionStylePrefix}${sport.toLowerCase().trim()}',
    );
  }

  Future<void> saveFavoriteCaptionStyleToken(
    String? token, {
    String sport = 'baseball',
  }) async {
    final prefs = await _getPrefs();
    final key = '${_keyFavoriteCaptionStylePrefix}${sport.toLowerCase().trim()}';
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, token.trim());
    }
    _afterLocalPreferencesChanged();
  }

  /// One of `gettyImages`, `imagn`, `ap`.
  Future<String> getCaptionCreditSampleAgency() async {
    final prefs = await _getPrefs();
    final v = prefs.getString(_keyCaptionCreditSampleAgency);
    if (v == 'imagn') return 'imagn';
    if (v == 'ap') return 'ap';
    if (v == 'gettyImages') return 'gettyImages';
    return 'gettyImages';
  }

  Future<void> saveCaptionCreditSampleAgency(String value) async {
    final prefs = await _getPrefs();
    final v =
        value == 'imagn' || value == 'ap' || value == 'gettyImages' ? value : 'gettyImages';
    await prefs.setString(_keyCaptionCreditSampleAgency, v);
    _afterLocalPreferencesChanged();
  }

  // Clear all preferences
  Future<void> clearAllPreferences() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }

  // --- App originals (Firebase catalog) — IPTC templates + restore ---

  Future<Set<String>> getHiddenIptcTemplateIds() async {
    final prefs = await _getPrefs();
    final list = prefs.getStringList(_keyHiddenIptcTemplateIds);
    if (list == null) return <String>{};
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> hideIptcTemplate(String templateId) async {
    final id = templateId.trim();
    if (id.isEmpty) return;
    final hidden = await getHiddenIptcTemplateIds();
    hidden.add(id);
    final prefs = await _getPrefs();
    await prefs.setStringList(_keyHiddenIptcTemplateIds, hidden.toList());
  }

  Future<void> clearHiddenIptcTemplateIds() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyHiddenIptcTemplateIds);
  }

  Future<String?> getSelectedIptcTemplateId() async {
    final prefs = await _getPrefs();
    final v = prefs.getString(_keySelectedIptcTemplateId);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<void> setSelectedIptcTemplateId(String id) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keySelectedIptcTemplateId, id.trim());
  }

  String _iptcWirePresetKey(WireStyle wire) =>
      '$_keyIptcWirePresetPrefix${wire.name}';

  String _iptcWireClearedKey(WireStyle wire) =>
      '$_keyIptcWireClearedPrefix${wire.name}';

  Future<void> saveIptcWirePreset(
    WireStyle wire, {
    required Map<String, String> preset,
    List<String> clearedFields = const [],
  }) async {
    final prefs = await _getPrefs();
    final key = _iptcWirePresetKey(wire);
    if (preset.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, json.encode(preset));
    }
    final clearedKey = _iptcWireClearedKey(wire);
    if (clearedFields.isEmpty) {
      await prefs.remove(clearedKey);
    } else {
      await prefs.setStringList(clearedKey, clearedFields);
    }
  }

  Future<Map<String, String>> getIptcWirePreset(WireStyle wire) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_iptcWirePresetKey(wire));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> getIptcWireClearedFields(WireStyle wire) async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_iptcWireClearedKey(wire)) ?? const [];
  }

  /// Writes [selected_metadata_preset] for the active wire from per-wire storage.
  Future<void> syncActiveMetadataPresetFromWire(WireStyle wire) async {
    final preset = await getIptcWirePreset(wire);
    final cleared = await getIptcWireClearedFields(wire);
    final prefs = await _getPrefs();
    if (preset.isNotEmpty) {
      await prefs.setString(
        'selected_metadata_preset',
        json.encode(preset),
      );
    } else {
      await prefs.remove('selected_metadata_preset');
    }
    await prefs.setStringList(
      'selected_metadata_preset_cleared_fields',
      cleared,
    );
    await setSelectedIptcTemplateId(AppDefaultsFirestoreService.templateIdForWire(wire));
  }

  Future<void> applyIptcCatalogToLocal(
    List<IptcTemplateCatalogEntry> templates,
  ) async {
    for (final t in templates) {
      await saveIptcWirePreset(
        t.wireStyle,
        preset: t.preset,
        clearedFields: t.clearedFields,
      );
    }
    if (templates.isNotEmpty) {
      final wire = templates.first.wireStyle;
      await syncActiveMetadataPresetFromWire(wire);
    }
  }

  /// Per-sport verb bundle for admin publish (matches export format).
  Future<Map<String, Map<String, dynamic>>> exportVerbSettingsBySport() async {
    final out = <String, Map<String, dynamic>>{};
    for (final sport in AppDefaultsFirestoreService.catalogSports) {
      out[sport] = {
        'categoryOrder': await getCategoryOrder(sport: sport),
        'verbOrder': await getVerbOrder(sport: sport),
        'favoriteVerbs': (await getFavoriteVerbs(sport: sport)).toList(),
        'favoriteTeams': (await getFavoriteTeams(sport: sport)).toList(),
        'customVerbWordings': await getCustomVerbWordings(sport: sport),
        'verbOverrides': await getVerbOverrides(sport: sport),
        'customVerbs': await getCustomVerbs(sport: sport),
        'deletedVerbs': (await getDeletedVerbs(sport: sport)).toList(),
      };
    }
    return out;
  }

  /// When the user has no saved category order for [sport], apply cached app defaults.
  Future<void> seedVerbsFromAppDefaultsIfEmpty(String sport) async {
    final prefs = await _getPrefs();
    if (prefs.containsKey(_getCategoryOrderKey(sport))) return;
    final slice =
        await AppDefaultsFirestoreService.getCachedSportVerbSettings(sport);
    if (slice == null || slice.isEmpty) return;
    await importPreferences({'verbSettingsBySport': {sport: slice}});
  }

  /// Fetches latest app originals from Firebase and applies verbs + caption structures.
  Future<void> restoreAppOriginals() async {
    await AppDefaultsFirestoreService.fetchAndCacheAppDefaults(
      forceNetwork: true,
    );
    final catalog = AppDefaultsFirestoreService.getCachedCatalog();
    if (catalog == null) {
      throw StateError(
        'Could not load app originals. Sign in and check your connection.',
      );
    }
    if (catalog.verbSettingsBySport.isNotEmpty) {
      await importPreferences({
        'verbSettingsBySport': catalog.verbSettingsBySport,
      });
    }
    if (catalog.captionTemplateWireDefaults.isNotEmpty) {
      await importPreferences({
        'captionTemplateWireDefaults': catalog.captionTemplateWireDefaults,
      });
    }
    if (catalog.gameIdentifierByWireAndSport.isNotEmpty) {
      await importPreferences({
        'gameIdentifierByWireAndSport': catalog.gameIdentifierByWireAndSport,
      });
    } else if (catalog.captionTemplateWireDefaults.isNotEmpty) {
      await saveGameIdentifierByWireAndSport(
        AppDefaultsFirestoreService.seededGameIdentifierByWireAndSport(),
      );
    }
  }

  /// Reset to defaults. If a "Save as default" bundle exists, restores that; otherwise clears and applies hardcoded defaults.
  Future<void> resetToDefaults() async {
    final savedDefault = await getSavedDefaultPreferences();
    if (savedDefault != null && savedDefault.isNotEmpty) {
      await clearAllPreferences();
      await importPreferences(savedDefault);
      await saveAsDefaultPreferences();
      return;
    }
    await clearAllPreferences();
    await saveCategoryOrder([
      'Offense',
      'Defense',
      'Running',
      'Reactions',
      'Non Game-Action',
      'Favorites',
    ]);
    await savePlaceFirebarOnRight(true);
    await saveCaptionEntryMode('keyboard_fire');
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
}

/// One named caption layout stored in [PreferencesService] (library, not active template).
class CaptionStyleLibraryEntry {
  const CaptionStyleLibraryEntry({
    required this.id,
    required this.displayName,
    required this.template,
  });

  final String id;
  final String displayName;
  final CaptionTemplate template;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'template': template.toJson(),
      };

  factory CaptionStyleLibraryEntry.fromJson(Map<String, dynamic> j) {
    final templateRaw = j['template'];
    if (templateRaw is! Map) {
      throw FormatException('CaptionStyleLibraryEntry missing template map');
    }
    return CaptionStyleLibraryEntry(
      id: j['id']?.toString() ?? 'saved_unknown',
      displayName:
          (j['displayName'] ?? j['name'] ?? 'Saved style').toString(),
      template: CaptionTemplate.fromJson(
        Map<String, dynamic>.from(templateRaw),
      ),
    );
  }
}
