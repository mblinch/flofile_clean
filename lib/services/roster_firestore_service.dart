import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'mlb_api_service.dart' show Player;

/// Firestore paths: `sports/{sportId}/teams/{teamId}/players/{leaguePlayerId}`.
///
/// Reconciles against the current roster: adds new players, deletes players
/// no longer on the roster, and only rewrites players whose visible fields
/// changed. Team doc meta (`displayName`, coach fields) is read first and
/// written only when something changed, so repeat syncs are effectively free.
///
/// Coach fields on `teams/{teamId}` come from [writeTeamCoachStaff]: MLB
/// manager + pitching / first / third base coaches for baseball, head coach
/// for basketball and hockey. Timestamps (`teamUpdatedAt`,
/// `coachStaffUpdatedAt`) only move when the related data changed.
///
/// Safe to call before [Firebase.initializeApp] completes; methods no-op when
/// no Firebase app is registered.
class RosterFirestoreService {
  RosterFirestoreService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static bool get isAvailable => Firebase.apps.isNotEmpty;

  static const List<String> _coachKeys = [
    'headCoach',
    'pitchingCoach',
    'firstBaseCoach',
    'thirdBaseCoach',
  ];

  static CollectionReference<Map<String, dynamic>> teamsCollection(
    String sportId,
  ) =>
      _db.collection('sports').doc(sportId).collection('teams');

  /// Reads players already synced for a team from Firestore.
  /// Returns an empty list when unavailable or not yet synced.
  static Future<List<Player>> readTeamPlayers({
    required String sportId,
    required String teamId,
  }) async {
    if (!isAvailable) return const <Player>[];
    final snap = await teamsCollection(sportId)
        .doc(teamId)
        .collection('players')
        .get();
    if (snap.docs.isEmpty) return const <Player>[];
    final out = <Player>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final fullName = (data['fullName'] as String?)?.trim() ?? '';
      if (fullName.isEmpty) continue;
      final firstName =
          (data['firstName'] as String?)?.trim().isNotEmpty == true
              ? (data['firstName'] as String).trim()
              : fullName.split(' ').first;
      final jersey = (data['jerseyNumber'] as String?)?.trim();
      final displayName =
          (data['displayName'] as String?)?.trim().isNotEmpty == true
              ? (data['displayName'] as String).trim()
              : (jersey != null && jersey.isNotEmpty)
                  ? '$fullName #$jersey'
                  : fullName;
      final position = (data['position'] as String?)?.trim();
      out.add(Player(
        fullName: fullName,
        firstName: firstName,
        jerseyNumber: (jersey?.isEmpty ?? true) ? null : jersey,
        displayName: displayName,
        playerId: (data['playerId'] as String?)?.trim().isNotEmpty == true
            ? (data['playerId'] as String).trim()
            : doc.id,
        position: (position == null || position.isEmpty) ? null : position,
      ));
    }
    out.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      if (aNum != bNum) return aNum.compareTo(bNum);
      return a.fullName.compareTo(b.fullName);
    });
    return out;
  }

  /// Reconciles the team's player subcollection: add new, delete missing,
  /// update only players whose visible fields differ. Also sets the team doc
  /// `displayName` + `teamUpdatedAt` only when the name actually changed.
  static Future<void> writeTeamPlayers({
    required String sportId,
    required String teamId,
    required List<Player> players,

    /// Human-readable team name (e.g. "Boston Bruins") for the `teams/{teamId}` doc.
    String? teamDisplayName,
  }) async {
    if (!isAvailable) return;
    final teamRef = teamsCollection(sportId).doc(teamId);
    final playersCol = teamRef.collection('players');

    final target = <String, Player>{};
    for (final p in players) {
      final id = _playerDocId(p);
      if (id.isEmpty) continue;
      target[id] = p;
    }

    final existingSnap = await playersCol.get();
    final existing = <String, Map<String, dynamic>>{
      for (final doc in existingSnap.docs) doc.id: doc.data(),
    };

    final adds = <MapEntry<String, Player>>[];
    final updates = <MapEntry<String, Player>>[];
    final removes = <String>[];

    target.forEach((id, p) {
      final cur = existing[id];
      if (cur == null) {
        adds.add(MapEntry(id, p));
        return;
      }
      if (_playerChanged(cur, p)) {
        updates.add(MapEntry(id, p));
      }
    });
    for (final id in existing.keys) {
      if (!target.containsKey(id)) removes.add(id);
    }

    final label = teamDisplayName?.trim();
    final teamDoc = (label != null && label.isNotEmpty) ? await teamRef.get() : null;
    final teamDocChanged = label != null &&
        label.isNotEmpty &&
        (teamDoc?.data()?['displayName'] != label);

    if (adds.isEmpty &&
        updates.isEmpty &&
        removes.isEmpty &&
        !teamDocChanged) {
      return;
    }

    const chunkSize = 400;
    final ops = <_PlayerOp>[
      ...adds.map((e) => _PlayerOp.set(e.key, e.value)),
      ...updates.map((e) => _PlayerOp.set(e.key, e.value)),
      ...removes.map((id) => _PlayerOp.delete(id)),
    ];
    for (var i = 0; i < ops.length; i += chunkSize) {
      final batch = _db.batch();
      if (i == 0 && teamDocChanged) {
        batch.set(teamRef, {
          'displayName': label,
          'teamUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      for (final op in ops.skip(i).take(chunkSize)) {
        final ref = playersCol.doc(op.id);
        if (op.isSet) {
          final p = op.player!;
          batch.set(ref, {
            'fullName': p.fullName,
            'firstName': p.firstName,
            'jerseyNumber': p.jerseyNumber,
            'displayName': p.displayName,
            if (p.playerId != null) 'playerId': p.playerId,
            if (p.position != null) 'position': p.position,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          batch.delete(ref);
        }
      }
      await batch.commit();
    }

    if (ops.isEmpty && teamDocChanged) {
      await teamRef.set({
        'displayName': label,
        'teamUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Reads the team doc first and writes only changed coach fields. Never
  /// blanks out an existing coach — blank / null incoming values are ignored.
  /// Advances `coachStaffUpdatedAt` only when at least one value changed.
  static Future<void> writeTeamCoachStaff({
    required String sportId,
    required String teamId,
    String? headCoach,
    String? pitchingCoach,
    String? firstBaseCoach,
    String? thirdBaseCoach,
  }) async {
    if (!isAvailable) return;
    final teamRef = teamsCollection(sportId).doc(teamId);
    final incoming = <String, String>{};
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) incoming[key] = v;
    }

    put('headCoach', headCoach);
    put('pitchingCoach', pitchingCoach);
    put('firstBaseCoach', firstBaseCoach);
    put('thirdBaseCoach', thirdBaseCoach);
    if (incoming.isEmpty) return;

    final snap = await teamRef.get();
    final cur = snap.data() ?? const <String, dynamic>{};
    final changes = <String, dynamic>{};
    for (final key in _coachKeys) {
      final next = incoming[key];
      if (next == null) continue;
      if (cur[key] != next) changes[key] = next;
    }
    if (changes.isEmpty) return;
    changes['coachStaffUpdatedAt'] = FieldValue.serverTimestamp();
    await teamRef.set(changes, SetOptions(merge: true));
  }

  static String _playerDocId(Player p) {
    final id = p.playerId?.trim();
    if (id != null && id.isNotEmpty) return id;
    final j = (p.jerseyNumber ?? '').trim();
    final slug = p.fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return j.isEmpty ? slug : '${j}_$slug';
  }

  static bool _playerChanged(Map<String, dynamic> cur, Player p) {
    return cur['fullName'] != p.fullName ||
        cur['firstName'] != p.firstName ||
        cur['jerseyNumber'] != p.jerseyNumber ||
        cur['displayName'] != p.displayName ||
        cur['position'] != p.position;
  }
}

class _PlayerOp {
  _PlayerOp._(this.id, this.player, this.isSet);
  factory _PlayerOp.set(String id, Player p) => _PlayerOp._(id, p, true);
  factory _PlayerOp.delete(String id) => _PlayerOp._(id, null, false);

  final String id;
  final Player? player;
  final bool isSet;
}
