import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'roster_firestore_service.dart';

/// Why a roster player is flagged for review.
enum RosterIssueKind {
  missingJersey,
  duplicateJersey,

  /// Manual jersey kept on this team while Tank01 still reports another number.
  differsFromTank01,
}

/// One player-level roster problem (missing, shared, or manual-vs-Tank01).
class RosterIssue {
  const RosterIssue({
    required this.kind,
    required this.sportId,
    required this.teamId,
    required this.teamName,
    required this.playerDocId,
    required this.fullName,
    this.jerseyNumber,
    this.tank01JerseyNumber,
    this.position,
    this.playerId,
    this.detail,
    this.rootCollection = RosterFirestoreService.tank01RootCollection,
  });

  final RosterIssueKind kind;
  final String sportId;
  final String teamId;
  final String teamName;
  final String playerDocId;
  final String fullName;
  final String? jerseyNumber;

  /// Tank01's last reported number when it differs from [jerseyNumber].
  final String? tank01JerseyNumber;
  final String? position;
  final String? playerId;
  /// Extra context (e.g. other players sharing the number).
  final String? detail;
  final String rootCollection;

  String get kindLabel {
    switch (kind) {
      case RosterIssueKind.missingJersey:
        return 'Missing jersey';
      case RosterIssueKind.duplicateJersey:
        final j = jerseyNumber?.trim() ?? '';
        return j.isEmpty ? 'Duplicate jersey' : 'Duplicate #$j';
      case RosterIssueKind.differsFromTank01:
        final ours = jerseyNumber?.trim() ?? '';
        final tank = tank01JerseyNumber?.trim() ?? '';
        if (ours.isNotEmpty && tank.isNotEmpty) {
          return 'Saved #$ours · Tank01 #$tank';
        }
        return 'Differs from Tank01';
    }
  }

  String get label {
    final bits = <String>[fullName];
    final p = position?.trim();
    if (p != null && p.isNotEmpty) bits.add(p);
    return bits.join(' · ');
  }
}

/// Scans Tank01 (or league) Firestore rosters for data-quality issues and
/// applies verified jersey fixes that sync will not wipe.
class RosterIssuesService {
  RosterIssuesService({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;

  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  static const List<String> tank01SportIds = [
    'baseball',
    'basketball',
    'hockey',
    'wnba',
  ];

  /// Walks `sports_tank01` (or [rootCollection]) for missing, duplicate, and
  /// manual-vs-Tank01 jersey conflicts. Pass [sportId] to limit to one sport.
  Future<List<RosterIssue>> scanIssues({
    String? sportId,
    String rootCollection = RosterFirestoreService.tank01RootCollection,
  }) async {
    if (!isAvailable) return const [];

    final sports = sportId == null || sportId.trim().isEmpty
        ? tank01SportIds
        : [sportId.toLowerCase().trim()];

    final out = <RosterIssue>[];
    for (final sport in sports) {
      final teams = await RosterFirestoreService.listTeams(
        sportId: sport,
        rootCollection: rootCollection,
      );
      for (final team in teams) {
        final snap = await RosterFirestoreService.teamsCollection(
          sport,
          rootCollection: rootCollection,
        ).doc(team.id).collection('players').get();

        final byJersey = <String, List<_PlayerDoc>>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          final fullName = (data['fullName'] as String?)?.trim() ?? '';
          if (fullName.isEmpty) continue;
          final jersey = (data['jerseyNumber'] as String?)?.trim() ?? '';
          final tankJersey =
              (data['tank01JerseyNumber'] as String?)?.trim() ?? '';
          final source = (data['jerseySource'] as String?)?.trim() ?? '';
          final position = (data['position'] as String?)?.trim();
          final playerId = (data['playerId'] as String?)?.trim();
          final player = _PlayerDoc(
            docId: doc.id,
            fullName: fullName,
            jerseyNumber: jersey.isEmpty ? null : jersey,
            tank01JerseyNumber: tankJersey.isEmpty ? null : tankJersey,
            position: (position == null || position.isEmpty) ? null : position,
            playerId: (playerId == null || playerId.isEmpty) ? null : playerId,
          );

          if (jersey.isEmpty) {
            out.add(RosterIssue(
              kind: RosterIssueKind.missingJersey,
              sportId: sport,
              teamId: team.id,
              teamName: team.name,
              playerDocId: player.docId,
              fullName: player.fullName,
              position: player.position,
              playerId: player.playerId,
              rootCollection: rootCollection,
            ));
            continue;
          }

          if (source == 'manual' &&
              tankJersey.isNotEmpty &&
              tankJersey != jersey) {
            out.add(RosterIssue(
              kind: RosterIssueKind.differsFromTank01,
              sportId: sport,
              teamId: team.id,
              teamName: team.name,
              playerDocId: player.docId,
              fullName: player.fullName,
              jerseyNumber: jersey,
              tank01JerseyNumber: tankJersey,
              position: player.position,
              playerId: player.playerId,
              detail: 'Saved #$jersey · Tank01 has #$tankJersey',
              rootCollection: rootCollection,
            ));
          }

          byJersey.putIfAbsent(jersey, () => []).add(player);
        }

        for (final entry in byJersey.entries) {
          if (entry.value.length < 2) continue;
          final names = entry.value.map((p) => p.fullName).toList()..sort();
          for (final player in entry.value) {
            final others = names.where((n) => n != player.fullName).join(', ');
            out.add(RosterIssue(
              kind: RosterIssueKind.duplicateJersey,
              sportId: sport,
              teamId: team.id,
              teamName: team.name,
              playerDocId: player.docId,
              fullName: player.fullName,
              jerseyNumber: entry.key,
              position: player.position,
              playerId: player.playerId,
              detail: others.isEmpty ? null : 'Also worn by $others',
              rootCollection: rootCollection,
            ));
          }
        }
      }
    }

    out.sort((a, b) {
      final s = a.sportId.compareTo(b.sportId);
      if (s != 0) return s;
      final t = a.teamName.compareTo(b.teamName);
      if (t != 0) return t;
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      final j = (a.jerseyNumber ?? '').compareTo(b.jerseyNumber ?? '');
      if (j != 0) return j;
      return a.fullName.compareTo(b.fullName);
    });
    return out;
  }

  /// Convenience wrapper kept for older call sites.
  Future<List<RosterIssue>> scanMissingJerseys({
    String? sportId,
    String rootCollection = RosterFirestoreService.tank01RootCollection,
  }) async {
    final all = await scanIssues(
      sportId: sportId,
      rootCollection: rootCollection,
    );
    return all
        .where((i) => i.kind == RosterIssueKind.missingJersey)
        .toList(growable: false);
  }

  /// Writes a verified jersey onto the player doc and marks
  /// `jerseySource: manual`. Sync keeps that number on this team. A move
  /// to another team starts fresh from Tank01.
  ///
  /// When the previous number came from Tank01 (or is already a stored Tank01
  /// conflict), that feed number is kept on `tank01JerseyNumber` so the
  /// admin issues list can show the mismatch. No email is sent for that.
  Future<void> setVerifiedJersey({
    required RosterIssue issue,
    required String jerseyNumber,
  }) async {
    if (!isAvailable) {
      throw StateError('Firebase is not available');
    }
    final jersey = jerseyNumber.trim();
    if (jersey.isEmpty) {
      throw ArgumentError('Jersey number is required');
    }
    if (int.tryParse(jersey) == null) {
      throw ArgumentError('Jersey number must be numeric');
    }

    final ref = RosterFirestoreService.teamsCollection(
      issue.sportId,
      rootCollection: issue.rootCollection,
    ).doc(issue.teamId).collection('players').doc(issue.playerDocId);

    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Player doc not found: ${issue.playerDocId}');
    }
    final data = snap.data() ?? const <String, dynamic>{};
    final fullName = (data['fullName'] as String?)?.trim() ?? issue.fullName;
    final oldJersey = (data['jerseyNumber'] as String?)?.trim() ?? '';
    final oldSource = (data['jerseySource'] as String?)?.trim() ?? '';
    final existingTank =
        (data['tank01JerseyNumber'] as String?)?.trim() ?? '';
    final issueTank = issue.tank01JerseyNumber?.trim() ?? '';

    final knownTank = existingTank.isNotEmpty
        ? existingTank
        : (issueTank.isNotEmpty
            ? issueTank
            : (oldSource != 'manual' && oldJersey.isNotEmpty ? oldJersey : ''));

    final patch = <String, dynamic>{
      'jerseyNumber': jersey,
      'displayName': '$fullName #$jersey',
      'jerseySource': 'manual',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (knownTank.isNotEmpty && knownTank != jersey) {
      patch['tank01JerseyNumber'] = knownTank;
    } else {
      patch['tank01JerseyNumber'] = FieldValue.delete();
    }

    await ref.set(patch, SetOptions(merge: true));
  }
}

class _PlayerDoc {
  const _PlayerDoc({
    required this.docId,
    required this.fullName,
    this.jerseyNumber,
    this.tank01JerseyNumber,
    this.position,
    this.playerId,
  });

  final String docId;
  final String fullName;
  final String? jerseyNumber;
  final String? tank01JerseyNumber;
  final String? position;
  final String? playerId;
}
