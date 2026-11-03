/// Central accessor for the currently-signed-in photographer display name.
///
/// Priority: [setPhotographerNameOverride] (saved prefs / profile dialog) →
/// auth [setProvider] (Google display name / email) → [placeholderName].
class CurrentUserService {
  CurrentUserService._();

  /// Placeholder shown in previews when no user name is available.
  static const String placeholderName = 'First Last';

  /// Saved photographer name from prefs / profile setup.
  static String? _photographerOverride;

  /// Optional override installed by the auth layer once it exists.
  /// Returning a non-empty name takes priority after [_photographerOverride].
  static String? Function()? _provider;

  /// Wire an auth-aware provider (e.g. Firebase Auth displayName).
  static void setProvider(String? Function()? provider) {
    _provider = provider;
  }

  /// Cache the saved photographer name used for caption preview / bylines.
  static void setPhotographerNameOverride(String? name) {
    final trimmed = name?.trim();
    _photographerOverride =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Returns the preferred photographer name, or `null` when unknown.
  static String? currentDisplayName() {
    final override = _photographerOverride?.trim();
    if (override != null && override.isNotEmpty) return override;

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
