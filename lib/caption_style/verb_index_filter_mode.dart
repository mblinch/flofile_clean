/// Verb Index filter: All · Faves.
/// [mostUsed] is legacy (Frequent tab removed); treat as [all] in the UI.
enum VerbIndexFilterMode {
  all,
  faves,
  mostUsed,
}

extension VerbIndexFilterModeStorage on VerbIndexFilterMode {
  String get storageValue => switch (this) {
        VerbIndexFilterMode.all => 'all',
        VerbIndexFilterMode.faves => 'faves',
        VerbIndexFilterMode.mostUsed => 'mostUsed',
      };

  static VerbIndexFilterMode fromStorage(String? raw) {
    switch (raw) {
      case 'faves':
      case 'fav':
      case 'favorites':
        return VerbIndexFilterMode.faves;
      case 'mostUsed':
      case 'most':
        return VerbIndexFilterMode.mostUsed;
      default:
        return VerbIndexFilterMode.all;
    }
  }
}
