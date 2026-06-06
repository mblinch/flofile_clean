import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_sign_in_config.dart';
import 'app_defaults_firestore_service.dart';
import 'current_user_service.dart';
import 'preferences_service.dart';

/// Firebase Authentication via Google Sign-In.
///
/// Google supplies an ID token; [FirebaseAuth.signInWithCredential] stores the
/// user in Firebase. Auth state persists across app restarts via Firebase Auth.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  bool _initialized = false;

  bool get isFirebaseReady => Firebase.apps.isNotEmpty;

  FirebaseAuth? get _auth =>
      isFirebaseReady ? FirebaseAuth.instance : null;

  User? get currentUser => _auth?.currentUser;

  bool get isGoogleSignInConfigured => googleOAuthClientId != null;

  Future<void> initialize() async {
    if (!isFirebaseReady || _initialized) return;
    _initialized = true;

    CurrentUserService.setProvider(() {
      final user = _auth?.currentUser;
      if (user == null) return null;
      final name = user.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
      return user.email;
    });

    final clientId = googleOAuthClientId;
    if (clientId != null) {
      await GoogleSignIn.instance.initialize(clientId: clientId);
      try {
        await GoogleSignIn.instance.attemptLightweightAuthentication();
      } catch (e) {
        debugPrint('[Auth] lightweight Google restore: $e');
      }
    } else {
      print(
        '[Auth] Google Sign-In: set GOOGLE_OAUTH_CLIENT_ID or '
        'lib/config/google_sign_in_config.dart — see docs/FIREBASE_AUTH_SETUP.md',
      );
    }

    _auth?.authStateChanges().listen(_onUserChanged);
    await _onUserChanged(_auth?.currentUser);
  }

  Future<void> _onUserChanged(User? user) async {
    if (user == null) return;
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.setSyncAccountId(user.uid);
      await AppDefaultsFirestoreService.fetchAndCacheAppDefaults();
      for (final sport in AppDefaultsFirestoreService.catalogSports) {
        await prefs.seedVerbsFromAppDefaultsIfEmpty(sport);
      }
    } catch (e, st) {
      print('[Auth] Failed to persist sync account id: $e');
      print(st);
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Firebase is not initialized');
    }
    if (!isGoogleSignInConfigured) {
      throw StateError(
        'Google Sign-In is not configured. Add your OAuth CLIENT_ID — '
        'see docs/FIREBASE_AUTH_SETUP.md',
      );
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google Sign-In is not supported on this platform');
    }

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google Sign-In did not return an ID token');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await auth.signInWithCredential(credential);
    await _onUserChanged(result.user);
    return result;
  }

  Future<void> signOut() async {
    try {
      if (isGoogleSignInConfigured) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (e) {
      debugPrint('[Auth] Google signOut: $e');
    }
    await _auth?.signOut();
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.setSyncAccountId('');
    } catch (e) {
      debugPrint('[Auth] clear sync account id: $e');
    }
  }
}
