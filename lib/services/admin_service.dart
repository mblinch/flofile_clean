import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// In-app admin checks for feature gates and UI.
///
/// **Solo / internal use:** matching [adminEmails] is fine for beta features.
/// **Production:** also set Firebase custom claim `admin: true` on your UID
/// (see docs/FIREBASE_AUTH_SETUP.md) and enforce the same rules in Cloud
/// Functions + Firestore security rules — never rely on the client alone.
///
/// [previewAsNonAdmin] lets a real admin temporarily hide admin-only UI so
/// they can see the product the way a regular account does.
class AdminService {
  AdminService._();

  /// Google accounts that receive admin privileges in the app.
  static const Set<String> adminEmails = {
    'projectflofile@gmail.com',
    'dev@flofilecaptions.com',
  };

  /// Optional Firebase Auth UIDs (stable if email ever changes).
  static const Set<String> adminUids = <String>{
    // Add your UID from Firebase Console → Authentication after first sign-in.
  };

  /// When true, [isCurrentUserAdmin] / [isCurrentUserAdminSync] return false
  /// even though the signed-in account is still an admin. The top-bar toggle
  /// uses [isActuallyAdminSync] so it stays visible to flip back.
  static final ValueNotifier<bool> previewAsNonAdmin = ValueNotifier(false);

  static void setPreviewAsNonAdmin(bool value) {
    if (previewAsNonAdmin.value == value) return;
    previewAsNonAdmin.value = value;
  }

  static bool isAdminUser(User? user) {
    if (user == null) return false;

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty && adminEmails.contains(email)) {
      return true;
    }

    final uid = user.uid.trim();
    if (uid.isNotEmpty && adminUids.contains(uid)) {
      return true;
    }

    return false;
  }

  /// Reads `admin: true` from the ID token (set via Firebase Admin SDK).
  static Future<bool> hasAdminCustomClaim(User? user) async {
    if (user == null) return false;
    try {
      final result = await user.getIdTokenResult();
      final admin = result.claims?['admin'];
      return admin == true || admin == 'true';
    } catch (_) {
      return false;
    }
  }

  /// True if this account is admin, ignoring the non-admin preview toggle.
  static bool isActuallyAdminSync() {
    if (AuthService.instance.signInSkipped) return false;
    if (Firebase.apps.isEmpty) return false;
    return isAdminUser(FirebaseAuth.instance.currentUser);
  }

  /// Async actual-admin check (email/uid or custom claim), ignoring preview.
  static Future<bool> isActuallyAdmin() async {
    if (AuthService.instance.signInSkipped) return false;
    if (Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (isAdminUser(user)) return true;
    return hasAdminCustomClaim(user);
  }

  static Future<bool> isCurrentUserAdmin() async {
    if (previewAsNonAdmin.value) return false;
    return isActuallyAdmin();
  }

  /// Sync version for gates that cannot await (email/uid only).
  static bool isCurrentUserAdminSync() {
    if (previewAsNonAdmin.value) return false;
    return isActuallyAdminSync();
  }
}
