import 'package:flutter/foundation.dart';

/// Gates MLB “inning from photo time” behind an allowlist so you can ship a
/// build with the code present but inert for everyone except chosen accounts.
///
/// Uses the same string as **Preferences → Sync account id** (or export key
/// `syncAccountId`). Matching is case-insensitive after trim.
///
/// For a commercial build with nobody allowed: set [allowedSyncAccountIds]
/// to `{}` and [enableInDebugBuilds] to `false`.
class MlbInningFeatureGate {
  MlbInningFeatureGate._();
  /// Sync account ids (lowercase) that may use inning-from-timestamp.
  static const Set<String> allowedSyncAccountIds = <String>{
    // Example: 'markblinch',
  };

  /// When `true`, non-release builds ([kDebugMode] or [kProfileMode]) get the
  /// feature without an allowlist entry. Release builds still require
  /// [allowedSyncAccountIds]. Set to `false` before wide release.
  static const bool enableInDebugBuilds = true;

  static bool isEnabled(String? syncAccountId) {
    final id = syncAccountId?.trim().toLowerCase() ?? '';
    if (id.isNotEmpty && allowedSyncAccountIds.contains(id)) {
      return true;
    }
    if (enableInDebugBuilds && (kDebugMode || kProfileMode)) {
      return true;
    }
    return false;
  }
}
