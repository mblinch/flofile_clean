/// Google OAuth client ID for macOS Google Sign-In.
///
/// After enabling **Google** in Firebase Console → Authentication → Sign-in
/// method, re-download `macos/Runner/GoogleService-Info.plist` and copy the
/// `CLIENT_ID` value here (or pass `--dart-define=GOOGLE_OAUTH_CLIENT_ID=...`
/// when running).
///
/// Also add `GIDClientID` and `CFBundleURLTypes` to `macos/Runner/Info.plist`
/// per [docs/FIREBASE_AUTH_SETUP.md](../docs/FIREBASE_AUTH_SETUP.md).
const String? kGoogleSignInClientId =
    '737938045380-1om7uanapjhddrt8l9lncbmhmd1k2q0p.apps.googleusercontent.com';

/// Resolves the OAuth client ID from [kGoogleSignInClientId] or dart-define.
String? get googleOAuthClientId {
  const fromDefine = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  if (fromDefine.isNotEmpty) return fromDefine;
  final configured = kGoogleSignInClientId?.trim();
  if (configured != null && configured.isNotEmpty) return configured;
  return null;
}
