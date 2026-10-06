import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'auth_service.dart';
import 'mlb_api_service.dart';

/// Outcome of an explicit player-data report (UI shows snackbars).
enum RosterIssueReportResult { success, notSignedIn, failed }

/// Writes a one-shot report when a signed-in user hits a roster conflict UI.
/// A Cloud Function emails the admin list from these docs.
class RosterIssueReportService {
  RosterIssueReportService._();

  static Future<void> reportDuplicateJerseys({
    required String teamName,
    required String sportId,
    required List<List<Player>> groups,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final user = AuthService.instance.currentUser;
    if (user == null || AuthService.instance.signInSkipped) return;

    final conflicts = <Map<String, dynamic>>[];
    for (final group in groups) {
      final jersey = (group.first.jerseyNumber ?? '').trim();
      if (jersey.isEmpty) continue;
      conflicts.add({
        'jersey': jersey,
        'players': [
          for (final player in group)
            {
              'fullName': player.fullName,
              'playerId': player.playerId,
              'position': player.position,
              'jerseyNumber': (player.jerseyNumber ?? '').trim(),
            },
        ],
      });
    }
    if (conflicts.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('roster_issue_reports').add({
        'kind': 'duplicateJersey',
        'teamName': teamName.trim(),
        'sportId': sportId.trim().isEmpty ? 'unknown' : sportId.trim(),
        'userEmail': user.email,
        'userUid': user.uid,
        'userDisplayName': user.displayName,
        'conflicts': conflicts,
        'createdAt': FieldValue.serverTimestamp(),
        'client': 'caption_v2',
      });
    } catch (e) {
      // Reporting must never block captioning.
      print('[RosterIssueReport] failed: $e');
    }
  }

  /// Reports session-only jersey number edits from the duplicate dialog.
  static Future<void> reportSessionJerseyEdits({
    required String teamName,
    required String sportId,
    required List<Map<String, dynamic>> changes,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final user = AuthService.instance.currentUser;
    if (user == null || AuthService.instance.signInSkipped) return;
    if (changes.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('roster_issue_reports').add({
        'kind': 'sessionJerseyEdit',
        'teamName': teamName.trim(),
        'sportId': sportId.trim().isEmpty ? 'unknown' : sportId.trim(),
        'userEmail': user.email,
        'userUid': user.uid,
        'userDisplayName': user.displayName,
        'changes': changes,
        'createdAt': FieldValue.serverTimestamp(),
        'client': 'caption_v2',
      });
    } catch (e) {
      print('[RosterIssueReport] sessionJerseyEdit failed: $e');
    }
  }

  /// Files a wrong-number / spelling / don't-use report for one roster player.
  static Future<RosterIssueReportResult> reportPlayerDataIssue({
    required String teamName,
    required String sportId,
    required String side,
    required Player player,
    required bool wrongNumber,
    required bool spelling,
    bool dontUsePlayer = false,
    String note = '',
  }) async {
    if (Firebase.apps.isEmpty) return RosterIssueReportResult.failed;
    if (!AuthService.instance.isSignedIn) {
      return RosterIssueReportResult.notSignedIn;
    }
    final user = AuthService.instance.currentUser;
    if (user == null) return RosterIssueReportResult.notSignedIn;
    if (!wrongNumber && !spelling && !dontUsePlayer) {
      return RosterIssueReportResult.failed;
    }

    final issueTypes = <String>[
      if (wrongNumber) 'wrongNumber',
      if (spelling) 'spelling',
      if (dontUsePlayer) 'dontUsePlayer',
    ];

    try {
      await FirebaseFirestore.instance.collection('roster_issue_reports').add({
        'kind': 'playerDataIssue',
        'teamName': teamName.trim(),
        'sportId': sportId.trim().isEmpty ? 'unknown' : sportId.trim(),
        'side': side.trim().isEmpty ? 'unknown' : side.trim(),
        'userEmail': user.email,
        'userUid': user.uid,
        'userDisplayName': user.displayName,
        'issueTypes': issueTypes,
        'note': note.trim(),
        'player': {
          'fullName': player.fullName,
          'playerId': player.playerId,
          'position': player.position,
          'jerseyNumber': (player.jerseyNumber ?? '').trim(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'client': 'caption_v2',
      });
      return RosterIssueReportResult.success;
    } catch (e) {
      print('[RosterIssueReport] playerDataIssue failed: $e');
      return RosterIssueReportResult.failed;
    }
  }
}
