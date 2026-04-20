import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

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
  static const String _keyUseBallDontLieApi = 'use_balldontlie_api';
  /// Optional caption entry strip: headline / keywords / personality visibility
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
  /// [package_info_plus] build number for which “What’s new” was dismissed.
  static const String _keyLastAcknowledgedAppBuild =
      'last_acknowledged_app_build';

  static PreferencesService? _instance;
  static SharedPreferences? _prefs;

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

  /// Bumped when headline/keywords/personality visibility toggles — caption UI listens to reflow.
  final ValueNotifier<int> captionFieldVisibilityRevision =
      ValueNotifier<int>(0);

  void _notifyCaptionFieldVisibilityChanged() {
    captionFieldVisibilityRevision.value = captionFieldVisibilityRevision.value + 1;
  }

  Future<bool> getShowHeadlineField() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowHeadlineField) ?? false;
  }

  Future<void> saveShowHeadlineField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowHeadlineField, show);
    _notifyCaptionFieldVisibilityChanged();
  }

  Future<bool> getShowKeywordsField() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowKeywordsField) ?? false;
  }

  Future<void> saveShowKeywordsField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowKeywordsField, show);
    _notifyCaptionFieldVisibilityChanged();
  }

  Future<bool> getShowPersonalityField() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyShowPersonalityField) ?? true;
  }

  Future<void> saveShowPersonalityField(bool show) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyShowPersonalityField, show);
    _notifyCaptionFieldVisibilityChanged();
  }

  /// Immediate read after [getInstance]; matches on-disk values right after each
  /// `saveShow*Field` call (avoids async lag when [captionFieldVisibilityRevision] fires).
  bool get captionFieldHeadlineVisibleSync =>
      _prefs?.getBool(_keyShowHeadlineField) ?? false;
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
  }

  // Current sport
  Future<void> saveCurrentSport(String sport) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyCurrentSport, sport);
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
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveVerbOrder(
    Map<String, List<String>> order, {
    String sport = 'baseball',
  }) async {
    final prefs = await _getPrefs();
    final key = _getVerbOrderKey(sport);
    if (order.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, json.encode(order));
  }

  // Per-sport default (e.g. "Set as default for Baseball") — used when user has no saved prefs for that sport
  String _getSportDefaultKey(String sport) =>
      '$_keySportDefaultPrefix${sport.toLowerCase()}';

  Future<Map<String, dynamic>?> getSportDefault(String sport) async {
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
  }

  // Firebar Position Preference
  Future<bool> getPlaceFirebarOnRight() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyPlaceFirebarOnRight) ?? true;
  }

  Future<void> savePlaceFirebarOnRight(bool placeOnRight) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyPlaceFirebarOnRight, placeOnRight);
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

  Future<bool> getUseBallDontLieApi() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyUseBallDontLieApi) ?? false;
  }

  Future<void> setUseBallDontLieApi(bool use) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyUseBallDontLieApi, use);
  }

  Future<void> setSyncAccountId(String id) async {
    final prefs = await _getPrefs();
    if (id.isEmpty) {
      await prefs.remove(_keySyncAccountId);
    } else {
      await prefs.setString(_keySyncAccountId, id.trim());
    }
  }

  static const String _keySavedDefaultPreferences = 'saved_default_preferences';

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
    return {
      'version': 2,
      'currentSport': await getCurrentSport(),
      'verbSettingsBySport': verbSettingsBySport,
      'categoryOrder': await getCategoryOrder(),
      'favoriteVerbs': (await getFavoriteVerbs()).toList(),
      'favoriteTeams': (await getFavoriteTeams()).toList(),
      'syncServerUrl': await getSyncServerUrl(),
      'syncAccountId': await getSyncAccountId(),
      'useBallDontLieApi': await getUseBallDontLieApi(),
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
    if (preferences.containsKey('useBallDontLieApi')) {
      await setUseBallDontLieApi(preferences['useBallDontLieApi'] as bool? ?? false);
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
  }

  // Clear all preferences
  Future<void> clearAllPreferences() async {
    final prefs = await _getPrefs();
    await prefs.clear();
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
