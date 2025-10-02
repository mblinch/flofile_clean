import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PreferencesService {
  static const String _keyCategoryOrder = 'category_order';
  static const String _keyCategoryOrderBaseball = 'category_order_baseball';
  static const String _keyFavoriteVerbs = 'favorite_verbs';
  static const String _keyFavoriteVerbsBaseball =
      'favorite_verbs_baseball'; // Sport-specific favorites
  static const String _keyCurrentSport = 'current_sport'; // Track current sport
  static const String _keyFavoriteTeams = 'favorite_teams';
  static const String _keyFtpProfiles = 'ftp_profiles';
  static const String _keyCurrentFtpProfile = 'current_ftp_profile';
  static const String _keyPlaceFirebarOnRight = 'place_firebar_on_right';
  static const String _keyLastSavedMetadata = 'last_saved_metadata';

  static PreferencesService? _instance;
  static SharedPreferences? _prefs;

  PreferencesService._();

  static Future<PreferencesService> getInstance() async {
    _instance ??= PreferencesService._();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

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
    // Return default order if not found or error
    final defaultOrder = [
      'Offense',
      'Defense',
      'Running',
      'Reactions',
      'Non Game-Action',
      'Favorites',
    ];
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
    return <String>{};
  }

  Future<void> saveFavoriteVerbs(Set<String> verbs,
      {String sport = 'baseball'}) async {
    final prefs = await _getPrefs();
    final key = _getSportSpecificKey(sport);
    await prefs.setString(key, json.encode(verbs.toList()));
  }

  // Favorite Teams Preferences
  Future<Set<String>> getFavoriteTeams() async {
    final prefs = await _getPrefs();
    final teamsJson = prefs.getString(_keyFavoriteTeams);
    if (teamsJson != null) {
      try {
        final List<dynamic> teamsList = json.decode(teamsJson);
        return teamsList.cast<String>().toSet();
      } catch (e) {
        print('Error parsing favorite teams: $e');
      }
    }
    return <String>{};
  }

  Future<void> saveFavoriteTeams(Set<String> teams) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyFavoriteTeams, json.encode(teams.toList()));
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

  // Export all preferences as JSON
  Future<Map<String, dynamic>> exportAllPreferences() async {
    return {
      'categoryOrder': await getCategoryOrder(),
      'favoriteVerbs': (await getFavoriteVerbs()).toList(),
      'favoriteTeams': (await getFavoriteTeams()).toList(),
      'ftpProfiles': await getFtpProfiles(),
      'currentFtpProfile': await getCurrentFtpProfile(),
      'placeFirebarOnRight': await getPlaceFirebarOnRight(),
      'lastSavedMetadata': await getLastSavedMetadata(),
    };
  }

  // Import preferences from JSON
  Future<void> importPreferences(Map<String, dynamic> preferences) async {
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
          preferences['ftpProfiles'].map(
              (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));
      await saveFtpProfiles(profiles);
    }
    if (preferences.containsKey('currentFtpProfile')) {
      await saveCurrentFtpProfile(preferences['currentFtpProfile']);
    }
    if (preferences.containsKey('placeFirebarOnRight')) {
      await savePlaceFirebarOnRight(preferences['placeFirebarOnRight']);
    }
    if (preferences.containsKey('lastSavedMetadata')) {
      await saveLastSavedMetadata(
          Map<String, dynamic>.from(preferences['lastSavedMetadata']));
    }
  }

  // Clear all preferences
  Future<void> clearAllPreferences() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }

  // Reset to defaults
  Future<void> resetToDefaults() async {
    await clearAllPreferences();
    // Set default category order
    await saveCategoryOrder([
      'Offense',
      'Defense',
      'Running',
      'Reactions',
      'Non Game-Action',
      'Favorites',
    ]);
    await savePlaceFirebarOnRight(true);
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
}
