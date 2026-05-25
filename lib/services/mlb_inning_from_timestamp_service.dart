import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import 'mlb_api_service.dart';

/// Where a photo timestamp falls relative to MLB play-by-play.
enum MlbPhotoGametimePhase {
  pregame,
  live,
  postgame,
}

/// Result of correlating a file timestamp with MLB play-by-play.
class MlbPhotoInningLookup {
  const MlbPhotoInningLookup({
    required this.hasScheduleMatch,
    required this.hasPlayByPlay,
    this.phase = MlbPhotoGametimePhase.live,
    this.inningNumber,
  });

  final bool hasScheduleMatch;
  /// False when the game matched but play-by-play had no usable timestamps.
  final bool hasPlayByPlay;
  /// Meaningful when [hasPlayByPlay] is true.
  final MlbPhotoGametimePhase phase;
  /// Set only when [phase] is [MlbPhotoGametimePhase.live].
  final int? inningNumber;
}

/// Maps a photo’s capture time to the MLB inning on that calendar day using
/// [statsapi.mlb.com](https://statsapi.mlb.com) play-by-play timestamps.
class MlbInningFromTimestampService {
  MlbInningFromTimestampService({MlbApiService? mlbApi})
      : _mlb = mlbApi ?? MlbApiService();

  static const String _baseUrl = 'statsapi.mlb.com';
  final MlbApiService _mlb;

  /// gamePk → sorted play starts (UTC), newest cache wins for the session.
  final Map<int, List<MlbPlayStart>> _timelineCache = {};

  /// Parses EXIF `DateTimeOriginal` / `CreateDate`-style `YYYY:MM:DD HH:MM:SS`.
  static DateTime? parseExifDateTimeOriginal(Map<String, dynamic> meta) {
    final raw = meta['DateTimeOriginal']?.toString() ??
        meta['EXIF:DateTimeOriginal']?.toString() ??
        meta['DateTimeCreated']?.toString() ??
        meta['CreateDate']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final t = raw.trim();
    if (t.length < 19) return null;
    // EXIF uses colons in the date portion; DateTime.parse expects dashes.
    final isoLike = t.replaceFirst(':', '-').replaceFirst(':', '-');
    try {
      return DateTime.parse(isoLike);
    } catch (_) {
      return null;
    }
  }

  /// Treats [wallClock] as local civil time in [ianaTimezone] and returns UTC.
  static DateTime? naiveWallClockToUtc(String ianaTimezone, DateTime wallClock) {
    try {
      final loc = tz.getLocation(ianaTimezone.trim());
      final z = tz.TZDateTime(
        loc,
        wallClock.year,
        wallClock.month,
        wallClock.day,
        wallClock.hour,
        wallClock.minute,
        wallClock.second,
        wallClock.millisecond,
      );
      return z.toUtc();
    } catch (_) {
      return null;
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Finds [gamePk] where the two franchises match (home/away may be swapped
  /// in the UI vs the official game record).
  Future<int?> findGamePkForTeamsOnDate({
    required String userHomeName,
    required String userAwayName,
    required DateTime calendarDay,
  }) async {
    final home = await _mlb.findTeamByName(userHomeName);
    final away = await _mlb.findTeamByName(userAwayName);
    if (home == null || away == null) return null;
    final date = _ymd(calendarDay);

    Future<List<dynamic>> gamesForTeam(String teamId) async {
      final url = Uri.https(_baseUrl, '/api/v1/schedule', {
        'sportId': '1',
        'date': date,
        'teamId': teamId,
      });
      final response = await http.get(url);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final dates = data['dates'] as List<dynamic>? ?? const [];
      if (dates.isEmpty) return const [];
      final first = dates.first as Map<String, dynamic>;
      return first['games'] as List<dynamic>? ?? const [];
    }

    final list = await gamesForTeam(home.id);
    int? homeId = int.tryParse(home.id);
    int? awayId = int.tryParse(away.id);
    if (homeId == null || awayId == null) return null;

    for (final g in list) {
      if (g is! Map<String, dynamic>) continue;
      final teams = g['teams'] as Map<String, dynamic>?;
      if (teams == null) continue;
      final apiHome =
          (teams['home'] as Map<String, dynamic>?)?['team'] as Map<String, dynamic>?;
      final apiAway =
          (teams['away'] as Map<String, dynamic>?)?['team'] as Map<String, dynamic>?;
      if (apiHome == null || apiAway == null) continue;
      final h = _apiTeamId(apiHome['id']);
      final a = _apiTeamId(apiAway['id']);
      if (h == null || a == null) continue;
      if ((h == homeId && a == awayId) || (h == awayId && a == homeId)) {
        return g['gamePk'] as int?;
      }
    }
    return null;
  }

  Future<List<MlbPlayStart>> _loadTimeline(int gamePk) async {
    final cached = _timelineCache[gamePk];
    if (cached != null) return cached;

    final url = Uri.https(_baseUrl, '/api/v1/game/$gamePk/playByPlay');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      return const [];
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final plays = data['allPlays'] as List<dynamic>? ?? const [];
    final out = <MlbPlayStart>[];
    for (final p in plays) {
      if (p is! Map<String, dynamic>) continue;
      final about = p['about'] as Map<String, dynamic>?;
      if (about == null) continue;
      final start = about['startTime']?.toString();
      final inning = about['inning'];
      if (start == null || start.isEmpty || inning is! int) continue;
      final t = DateTime.tryParse(start);
      if (t == null) continue;
      final startUtc = t.toUtc();
      final endStr = about['endTime']?.toString();
      DateTime? endUtc;
      if (endStr != null && endStr.isNotEmpty) {
        endUtc = DateTime.tryParse(endStr)?.toUtc();
      }
      out.add(MlbPlayStart(startUtc, inning, endUtc));
    }
    out.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    _timelineCache[gamePk] = out;
    return out;
  }

  /// Latest moment covered by play-by-play (max of each play’s end, or start).
  static DateTime gameEndUtc(List<MlbPlayStart> plays) {
    DateTime maxEnd = plays.first.effectiveEndUtc;
    for (final p in plays) {
      final e = p.effectiveEndUtc;
      if (e.isAfter(maxEnd)) maxEnd = e;
    }
    return maxEnd;
  }

  /// Last play with `startTime <= tUtc` determines the inning; only for
  /// timestamps during the game.
  static int? inningAtUtc(List<MlbPlayStart> plays, DateTime tUtc) {
    if (plays.isEmpty) return null;
    if (tUtc.isBefore(plays.first.startUtc)) return null;
    int lo = 0;
    int hi = plays.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (plays[mid].startUtc.isAfter(tUtc)) {
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return plays[hi].inning;
  }

  static int? _apiTeamId(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  Future<MlbPhotoInningLookup> lookupPhotoInning({
    required String userHomeName,
    required String userAwayName,
    required DateTime gameCalendarDay,
    required DateTime photoTimeUtc,
  }) async {
    final pk = await findGamePkForTeamsOnDate(
      userHomeName: userHomeName,
      userAwayName: userAwayName,
      calendarDay: gameCalendarDay,
    );
    if (pk == null) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: false,
        hasPlayByPlay: false,
      );
    }
    final plays = await _loadTimeline(pk);
    if (plays.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: false,
      );
    }
    final firstStart = plays.first.startUtc;
    final endBound = gameEndUtc(plays);
    if (photoTimeUtc.isBefore(firstStart)) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: true,
        phase: MlbPhotoGametimePhase.pregame,
      );
    }
    if (photoTimeUtc.isAfter(endBound)) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: true,
        phase: MlbPhotoGametimePhase.postgame,
      );
    }
    final inn = inningAtUtc(plays, photoTimeUtc);
    return MlbPhotoInningLookup(
      hasScheduleMatch: true,
      hasPlayByPlay: true,
      phase: MlbPhotoGametimePhase.live,
      inningNumber: inn,
    );
  }

  Future<int?> resolveInning({
    required String userHomeName,
    required String userAwayName,
    required DateTime gameCalendarDay,
    required DateTime photoTimeUtc,
  }) async {
    final r = await lookupPhotoInning(
      userHomeName: userHomeName,
      userAwayName: userAwayName,
      gameCalendarDay: gameCalendarDay,
      photoTimeUtc: photoTimeUtc,
    );
    if (!r.hasScheduleMatch || !r.hasPlayByPlay) return null;
    if (r.phase != MlbPhotoGametimePhase.live) return null;
    return r.inningNumber;
  }
}

class MlbPlayStart {
  const MlbPlayStart(this.startUtc, this.inning, this.endUtc);

  final DateTime startUtc;
  final int inning;
  final DateTime? endUtc;

  DateTime get effectiveEndUtc => endUtc ?? startUtc;
}
