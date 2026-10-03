/// How verbs are ordered inside each category in Caption V2.
enum VerbSortMode {
  /// A–Z by label (default on first launch).
  alphabetical,

  /// Highest local/Firebase usage count first, then A–Z.
  mostUsed,

  /// User-arranged order from saved [verbOrder].
  custom,
}

extension VerbSortModeX on VerbSortMode {
  String get storageValue {
    switch (this) {
      case VerbSortMode.alphabetical:
        return 'alphabetical';
      case VerbSortMode.mostUsed:
        return 'mostUsed';
      case VerbSortMode.custom:
        return 'custom';
    }
  }

  String get menuLabel {
    switch (this) {
      case VerbSortMode.alphabetical:
        return 'Sort A–Z';
      case VerbSortMode.mostUsed:
        return 'Sort by most used';
      case VerbSortMode.custom:
        return 'Custom arrange';
    }
  }

  static VerbSortMode fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'mostUsed':
        return VerbSortMode.mostUsed;
      case 'custom':
        return VerbSortMode.custom;
      case 'alphabetical':
      default:
        return VerbSortMode.alphabetical;
    }
  }
}
