import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// In-app admin checks for feature gates and UI.
///
/// **Solo / internal use:** matching [adminEmails] is fine for beta features.
/// **Production:** also set Firebase custom claim `admin: true` on your UID
/// (see docs/FIREBASE_AUTH_SETUP.md) and enforce the same rules in Cloud
/// Functions + Firestore security rules — never rely on the client alone.
class AdminService {
  AdminService._();

  /// Google accounts that receive admin privileges in the app.
  static const Set<String> adminEmails = {
    'projectflofile@gmail.com',
  };

  /// Optional Firebase Auth UIDs (stable if email ever changes).
  static const Set<String> adminUids = <String>{
    // Add your UID from Firebase Console → Authentication after first sign-in.
  };

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

  static Future<bool> isCurrentUserAdmin() async {
    if (Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (isAdminUser(user)) return true;
    return hasAdminCustomClaim(user);
  }

  /// Sync version for gates that cannot await (email/uid only).
  static bool isCurrentUserAdminSync() {
    if (Firebase.apps.isEmpty) return false;
    return isAdminUser(FirebaseAuth.instance.currentUser);
  }
}
