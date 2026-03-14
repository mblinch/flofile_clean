import 'dart:convert';
import 'package:http/http.dart' as http;
import 'preferences_service.dart';

/// Uploads/downloads preferences to a user-hosted sync server so settings
/// work seamlessly across computers. See docs/SYNC_SERVER_API.md for the
/// endpoint contract your server must implement.
class PreferencesSyncService {
  static const Duration _timeout = Duration(seconds: 15);

  /// Upload current preferences to the configured sync server.
  /// Server should store by [syncAccountId] (included in the JSON body).
  Future<void> upload(PreferencesService prefs) async {
    final url = await prefs.getSyncServerUrl();
    if (url.isEmpty) throw Exception('Sync server URL is not set');
    final accountId = await prefs.getSyncAccountId();
    if (accountId.isEmpty) throw Exception('Sync account ID is not set');

    final body = await prefs.exportAllPreferences();
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final uri = Uri.parse('$base/upload');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Upload failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Download preferences from the configured sync server for the configured account.
  Future<void> download(PreferencesService prefs) async {
    final url = await prefs.getSyncServerUrl();
    if (url.isEmpty) throw Exception('Sync server URL is not set');
    final accountId = await prefs.getSyncAccountId();
    if (accountId.isEmpty) throw Exception('Sync account ID is not set');

    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final uri = Uri.parse('$base/download').replace(queryParameters: {'accountId': accountId});
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    await prefs.importPreferences(data);
  }
}
