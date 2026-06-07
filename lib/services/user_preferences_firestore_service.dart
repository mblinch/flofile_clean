import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'preferences_service.dart';

/// Syncs per-user preferences (captions, verbs, FTP, etc.) to Firestore so
/// settings follow the account across machines.
///
/// Document: `users/{uid}/preferences/current`
class UserPreferencesFirestoreService {
  UserPreferencesFirestoreService._();

  static const String docPathTemplate = 'users/{uid}/preferences/current';
  static const int currentSchemaVersion = 1;
  static const Duration _uploadDebounce = Duration(seconds: 3);

  static Timer? _uploadDebounceTimer;
  static Future<void>? _uploadInFlight;
  static PreferencesService? _pendingUploadPrefs;

  static bool get isAvailable => Firebase.apps.isNotEmpty;

  static DocumentReference<Map<String, dynamic>> _docFor(String uid) =>
      FirebaseFirestore.instance.doc(
        docPathTemplate.replaceFirst('{uid}', uid),
      );

  static String? get _signedInUid => FirebaseAuth.instance.currentUser?.uid;

  /// Pull cloud prefs on sign-in / cold start; push local when newer.
  static Future<UserPreferencesSyncResult> syncOnSignIn(
    PreferencesService prefs,
  ) async {
    if (!isAvailable) {
      return UserPreferencesSyncResult.skipped('Firebase not available');
    }
    final uid = _signedInUid;
    if (uid == null || uid.isEmpty) {
      return UserPreferencesSyncResult.skipped('Not signed in');
    }

    try {
      final snap = await _docFor(uid).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final localUpdatedAt = await prefs.getUserPreferencesUpdatedAtMs();

      if (!snap.exists) {
        await _uploadNow(prefs, uid);
        return UserPreferencesSyncResult.uploaded('Initial cloud backup created');
      }

      final data = snap.data();
      if (data == null) {
        await _uploadNow(prefs, uid);
        return UserPreferencesSyncResult.uploaded('Initial cloud backup created');
      }

      final cloudUpdatedAt = _readUpdatedAtMs(data);
      final cloudPrefs = _readPreferencesMap(data);
      if (cloudPrefs == null) {
        await _uploadNow(prefs, uid);
        return UserPreferencesSyncResult.uploaded('Initial cloud backup created');
      }

      if (cloudUpdatedAt > localUpdatedAt) {
        await prefs.applyCloudPreferences(cloudPrefs, cloudUpdatedAt);
        return UserPreferencesSyncResult.downloaded(
          'Settings restored from your account',
        );
      }
      if (localUpdatedAt > cloudUpdatedAt) {
        await _uploadNow(prefs, uid);
        return UserPreferencesSyncResult.uploaded(
          'Local settings backed up to your account',
        );
      }
      return UserPreferencesSyncResult.unchanged();
    } catch (e, st) {
      print('UserPreferencesFirestoreService.syncOnSignIn failed: $e');
      print(st);
      return UserPreferencesSyncResult.failed(e.toString());
    }
  }

  /// Debounced upload after local edits while signed in.
  static void scheduleUpload(PreferencesService prefs) {
    if (!isAvailable || _signedInUid == null) return;
    _pendingUploadPrefs = prefs;
    _uploadDebounceTimer?.cancel();
    _uploadDebounceTimer = Timer(_uploadDebounce, () {
      final p = _pendingUploadPrefs;
      _pendingUploadPrefs = null;
      if (p == null) return;
      unawaited(_uploadNow(p, _signedInUid!));
    });
  }

  static Future<void> _uploadNow(PreferencesService prefs, String uid) async {
    if (_uploadInFlight != null) {
      await _uploadInFlight;
    }
    _uploadInFlight = _uploadNowInner(prefs, uid);
    try {
      await _uploadInFlight;
    } finally {
      _uploadInFlight = null;
    }
  }

  static Future<void> _uploadNowInner(
    PreferencesService prefs,
    String uid,
  ) async {
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final bundle = await prefs.exportSyncablePreferences();
    await _docFor(uid).set(
      {
        'schemaVersion': currentSchemaVersion,
        'updatedAtMs': updatedAtMs,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
        'preferences': bundle,
      },
      SetOptions(merge: true),
    );
    await prefs.markCloudPreferencesSynced(updatedAtMs);
  }

  static int _readUpdatedAtMs(Map<String, dynamic> data) {
    final raw = data['updatedAtMs'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  static Map<String, dynamic>? _readPreferencesMap(Map<String, dynamic> data) {
    final raw = data['preferences'];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }
}

class UserPreferencesSyncResult {
  const UserPreferencesSyncResult._({
    required this.action,
    this.message,
    this.error,
  });

  final UserPreferencesSyncAction action;
  final String? message;
  final String? error;

  factory UserPreferencesSyncResult.skipped(String reason) =>
      UserPreferencesSyncResult._(
        action: UserPreferencesSyncAction.skipped,
        message: reason,
      );

  factory UserPreferencesSyncResult.uploaded(String message) =>
      UserPreferencesSyncResult._(
        action: UserPreferencesSyncAction.uploaded,
        message: message,
      );

  factory UserPreferencesSyncResult.downloaded(String message) =>
      UserPreferencesSyncResult._(
        action: UserPreferencesSyncAction.downloaded,
        message: message,
      );

  factory UserPreferencesSyncResult.unchanged() => const UserPreferencesSyncResult._(
        action: UserPreferencesSyncAction.unchanged,
      );

  factory UserPreferencesSyncResult.failed(String error) =>
      UserPreferencesSyncResult._(
        action: UserPreferencesSyncAction.failed,
        error: error,
      );
}

enum UserPreferencesSyncAction {
  skipped,
  uploaded,
  downloaded,
  unchanged,
  failed,
}
