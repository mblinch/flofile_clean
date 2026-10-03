import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'mlb_api_service.dart' show Player, TeamInfo;

/// Firestore paths: `{root}/{sportId}/teams/{teamId}/players/{leaguePlayerId}`.
///
/// [rootCollection] is normally [leagueRootCollection] (`sports`). Use
/// [tank01RootCollection] (`sports_tank01`) for the Tank01 mirror — same
/// player/team field shapes; team ids = Tank01 `teamAbv`.
///
/// Reconciles against the current roster: adds new players, deletes players
/// no longer on the roster, and only rewrites players whose visible fields
/// changed. Team doc meta (`displayName`, coach fields) is read first and
/// written only when something changed, so repeat syncs are effectively free.
///
/// Safe to call before [Firebase.initializeApp] completes; methods no-op when
/// no Firebase app is registered.
class RosterFirestoreService {
  RosterFirestoreService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static bool get isAvailable => Firebase.apps.isNotEmpty;

  /// League-API roster cache (MLB Stats / NHL / ESPN).
  static const String leagueRootCollection = 'sports';

  /// Tank01 RapidAPI mirror — same document shapes as [leagueRootCollection].
  static const String tank01RootCollection = 'sports_tank01';

  static const List<String> _coachKeys = [
    'headCoach',
    'pitchingCoach',
    'firstBaseCoach',
    'thirdBaseCoach',
  ];

  static CollectionReference<Map<String, dynamic>> teamsCollection(
    String sportId, {
    String rootCollection = leagueRootCollection,
  }) =>
      _db.collection(rootCollection).doc(sportId).collection('teams');

  /// Lists team docs under `{root}/{sportId}/teams` (id + displayName).
  static Future<List<TeamInfo>> listTeams({
    required String sportId,
    String rootCollection = leagueRootCollection,
  }) async {
    if (!isAvailable) return const <TeamInfo>[];
    final snap = await teamsCollection(
      sportId,
      rootCollection: rootCollection,
    ).get();
    final out = <TeamInfo>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final name = (data['displayName'] as String?)?.trim();
      final label =
          (name != null && name.isNotEmpty) ? name : doc.id;
      out.add(TeamInfo(id: doc.id, name: label));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Resolves a display team name to a Firestore team doc id.
  static Future<String?> findTeamIdByDisplayName({
    required String sportId,
    required String teamName,
    String rootCollection = leagueRootCollection,
  }) async {
    final q = teamName.toLowerCase().trim();
    if (q.isEmpty) return null;
    final teams = await listTeams(
      sportId: sportId,
      rootCollection: rootCollection,
    );
    for (final t in teams) {
      final name = t.name.toLowerCase().trim();
      final id = t.id.toLowerCase().trim();
      if (name == q || id == q) return t.id;
    }
    for (final t in teams) {
      final name = t.name.toLowerCase().trim();
      if (q.contains(name) || name.contains(q)) return t.id;
    }
    return null;
  }

  /// Reads players already synced for a team from Firestore.
  /// Returns an empty list when unavailable or not yet synced.
  static Future<List<Player>> readTeamPlayers({
    required String sportId,
    required String teamId,
    String rootCollection = leagueRootCollection,
  }) async {
    if (!isAvailable) return const <Player>[];
    final snap = await teamsCollection(
      sportId,
      rootCollection: rootCollection,
    ).doc(teamId).collection('players').get();
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
    String rootCollection = leagueRootCollection,

    /// Optional marker written onto the team doc (e.g. `tank01`).
    String? source,
  }) async {
    if (!isAvailable) return;
    final teamRef =
        teamsCollection(sportId, rootCollection: rootCollection).doc(teamId);
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
    // Doc ids whose jersey was kept from a prior manual verification.
    final preservedManualJersey = <String>{};

    target.forEach((id, p) {
      final cur = existing[id];
      if (cur == null) {
        adds.add(MapEntry(id, p));
        return;
      }
      final effective = _withPreservedManualJersey(cur, p);
      if (effective.jerseyNumber != p.jerseyNumber) {
        preservedManualJersey.add(id);
      }
      if (_playerChanged(cur, effective)) {
        updates.add(MapEntry(id, effective));
      }
    });
    for (final id in existing.keys) {
      if (!target.containsKey(id)) removes.add(id);
    }

    final label = teamDisplayName?.trim();
    final teamDoc = await teamRef.get();
    final curData = teamDoc.data() ?? const <String, dynamic>{};
    final teamDocPatch = <String, dynamic>{};
    if (label != null &&
        label.isNotEmpty &&
        curData['displayName'] != label) {
      teamDocPatch['displayName'] = label;
      teamDocPatch['teamUpdatedAt'] = FieldValue.serverTimestamp();
    }
    if (source != null &&
        source.trim().isNotEmpty &&
        curData['source'] != source.trim()) {
      teamDocPatch['source'] = source.trim();
    }

    if (adds.isEmpty &&
        updates.isEmpty &&
        removes.isEmpty &&
        teamDocPatch.isEmpty) {
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
      if (i == 0 && teamDocPatch.isNotEmpty) {
        batch.set(teamRef, teamDocPatch, SetOptions(merge: true));
      }
      for (final op in ops.skip(i).take(chunkSize)) {
        final ref = playersCol.doc(op.id);
        if (op.isSet) {
          final p = op.player!;
          final keepManual = preservedManualJersey.contains(op.id);
          final incomingHasJersey =
              (p.jerseyNumber ?? '').trim().isNotEmpty && !keepManual;
          batch.set(
            ref,
            {
              'fullName': p.fullName,
              'firstName': p.firstName,
              'jerseyNumber': p.jerseyNumber,
              'displayName': p.displayName,
              if (p.playerId != null) 'playerId': p.playerId,
              if (p.position != null) 'position': p.position,
              if (keepManual) 'jerseySource': 'manual',
              if (incomingHasJersey) 'jerseySource': 'tank01',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else {
          batch.delete(ref);
        }
      }
      await batch.commit();
    }

    if (ops.isEmpty && teamDocPatch.isNotEmpty) {
      await teamRef.set(teamDocPatch, SetOptions(merge: true));
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
    String rootCollection = leagueRootCollection,
  }) async {
    if (!isAvailable) return;
    final teamRef =
        teamsCollection(sportId, rootCollection: rootCollection).doc(teamId);
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
    final slug =
        p.fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return j.isEmpty ? slug : '${j}_$slug';
  }

  /// Keeps a manually verified jersey when the incoming sync has a blank one.
  static Player _withPreservedManualJersey(
    Map<String, dynamic> cur,
    Player incoming,
  ) {
    final incomingJersey = (incoming.jerseyNumber ?? '').trim();
    if (incomingJersey.isNotEmpty) return incoming;
    final source = (cur['jerseySource'] as String?)?.trim() ?? '';
    if (source != 'manual') return incoming;
    final existingJersey = (cur['jerseyNumber'] as String?)?.trim() ?? '';
    if (existingJersey.isEmpty) return incoming;
    return Player(
      fullName: incoming.fullName,
      firstName: incoming.firstName,
      jerseyNumber: existingJersey,
      displayName: '${incoming.fullName} #$existingJersey',
      playerId: incoming.playerId,
      position: incoming.position,
    );
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
