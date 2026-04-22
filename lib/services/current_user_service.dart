/// Central accessor for the currently-signed-in app user's display name.
///
/// Firebase Auth is not wired into the app yet, so [currentDisplayName] returns
/// `null` by default and callers can fall back to placeholder values. When
/// auth is introduced, plug the live lookup in via [setProvider] (or update
/// [currentDisplayName] directly) — all caption-layout / credit consumers will
/// automatically pick it up.
class CurrentUserService {
  CurrentUserService._();

  /// Placeholder shown in previews when no user is signed in.
  static const String placeholderName = 'First Last';

  /// Optional override installed by the auth layer once it exists.
  /// Returning a non-empty name takes priority over any other source.
  static String? Function()? _provider;

  /// Wire an auth-aware provider (e.g. `() => FirebaseAuth.instance.currentUser?.displayName`).
  static void setProvider(String? Function()? provider) {
    _provider = provider;
  }

  /// Returns the signed-in user's display name, or `null` when not signed in.
  static String? currentDisplayName() {
    final fromProvider = _provider?.call()?.trim();
    if (fromProvider != null && fromProvider.isNotEmpty) {
      return fromProvider;
    }
    return null;
  }

  /// Convenience: returns [currentDisplayName] or [placeholderName] when null.
  static String displayNameOrPlaceholder() {
    final name = currentDisplayName();
    if (name == null || name.isEmpty) return placeholderName;
    return name;
  }
}
