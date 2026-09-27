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
  static DateTime? naiveWallClockToUtc(
      String ianaTimezone, DateTime wallClock) {
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

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// All games that day between the two franchises (doubleheaders included).
  /// Home/away in the UI may be swapped from the official record.
  Future<List<int>> findGamePksForTeamsOnDate({
    required String userHomeName,
    required String userAwayName,
    required DateTime calendarDay,
  }) async {
    final home = await _mlb.findTeamByName(userHomeName);
    final away = await _mlb.findTeamByName(userAwayName);
    if (home == null || away == null) return const [];
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

    final homeId = int.tryParse(home.id);
    final awayId = int.tryParse(away.id);
    if (homeId == null || awayId == null) return const [];

    final pks = <int>{};
    for (final teamId in {home.id, away.id}) {
      final list = await gamesForTeam(teamId);
      for (final g in list) {
        if (g is! Map<String, dynamic>) continue;
        final teams = g['teams'] as Map<String, dynamic>?;
        if (teams == null) continue;
        final apiHome = (teams['home'] as Map<String, dynamic>?)?['team']
            as Map<String, dynamic>?;
        final apiAway = (teams['away'] as Map<String, dynamic>?)?['team']
            as Map<String, dynamic>?;
        if (apiHome == null || apiAway == null) continue;
        final h = _apiTeamId(apiHome['id']);
        final a = _apiTeamId(apiAway['id']);
        if (h == null || a == null) continue;
        if ((h == homeId && a == awayId) || (h == awayId && a == homeId)) {
          final pk = g['gamePk'];
          final id = pk is int ? pk : int.tryParse(pk?.toString() ?? '');
          if (id != null) pks.add(id);
        }
      }
    }
    return pks.toList();
  }

  /// Finds [gamePk] where the two franchises match (home/away may be swapped
  /// in the UI vs the official game record).
  Future<int?> findGamePkForTeamsOnDate({
    required String userHomeName,
    required String userAwayName,
    required DateTime calendarDay,
  }) async {
    final pks = await findGamePksForTeamsOnDate(
      userHomeName: userHomeName,
      userAwayName: userAwayName,
      calendarDay: calendarDay,
    );
    if (pks.isEmpty) return null;
    return pks.first;
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

  /// Picks the game whose play-by-play actually covers [photoTimeUtc].
  ///
  /// A doubleheader produces two timelines. The earlier game must not steal a
  /// photo taken during the later one.
  static MlbPhotoInningLookup timelineForPhoto(
    List<List<MlbPlayStart>> games,
    DateTime photoTimeUtc,
  ) {
    if (games.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: false,
        hasPlayByPlay: false,
      );
    }
    final scored = <_ScoredTimeline>[];
    for (final plays in games) {
      if (plays.isEmpty) continue;
      scored.add(_scoreTimeline(plays, photoTimeUtc));
    }
    if (scored.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: false,
      );
    }
    scored.sort((a, b) {
      final liveCmp = (a.inside ? 0 : 1).compareTo(b.inside ? 0 : 1);
      if (liveCmp != 0) return liveCmp;
      return a.distance.compareTo(b.distance);
    });
    return scored.first.lookup;
  }

  static _ScoredTimeline _scoreTimeline(
    List<MlbPlayStart> plays,
    DateTime photoTimeUtc,
  ) {
    final firstStart = plays.first.startUtc;
    final endBound = gameEndUtc(plays);
    if (photoTimeUtc.isBefore(firstStart)) {
      return _ScoredTimeline(
        lookup: const MlbPhotoInningLookup(
          hasScheduleMatch: true,
          hasPlayByPlay: true,
          phase: MlbPhotoGametimePhase.pregame,
        ),
        inside: false,
        distance: firstStart.difference(photoTimeUtc),
      );
    }
    if (photoTimeUtc.isAfter(endBound)) {
      return _ScoredTimeline(
        lookup: const MlbPhotoInningLookup(
          hasScheduleMatch: true,
          hasPlayByPlay: true,
          phase: MlbPhotoGametimePhase.postgame,
        ),
        inside: false,
        distance: photoTimeUtc.difference(endBound),
      );
    }
    return _ScoredTimeline(
      lookup: MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: true,
        phase: MlbPhotoGametimePhase.live,
        inningNumber: inningAtUtc(plays, photoTimeUtc),
      ),
      inside: true,
      distance: Duration.zero,
    );
  }

  Future<MlbPhotoInningLookup> lookupPhotoInning({
    required String userHomeName,
    required String userAwayName,
    required DateTime gameCalendarDay,
    DateTime? photoCalendarDay,
    required DateTime photoTimeUtc,
  }) async {
    final days = <DateTime>{};
    void addAround(DateTime day) {
      final date = DateTime(day.year, day.month, day.day);
      days.add(date);
      days.add(date.subtract(const Duration(days: 1)));
      days.add(date.add(const Duration(days: 1)));
    }

    addAround(gameCalendarDay);
    if (photoCalendarDay != null) addAround(photoCalendarDay);

    final pks = <int>{};
    for (final day in days) {
      pks.addAll(await findGamePksForTeamsOnDate(
        userHomeName: userHomeName,
        userAwayName: userAwayName,
        calendarDay: day,
      ));
    }
    if (pks.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: false,
        hasPlayByPlay: false,
      );
    }
    final timelines = <List<MlbPlayStart>>[];
    for (final pk in pks) {
      timelines.add(await _loadTimeline(pk));
    }
    return timelineForPhoto(timelines, photoTimeUtc);
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

class _ScoredTimeline {
  const _ScoredTimeline({
    required this.lookup,
    required this.inside,
    required this.distance,
  });

  final MlbPhotoInningLookup lookup;
  final bool inside;
  final Duration distance;
}

class MlbPlayStart {
  const MlbPlayStart(this.startUtc, this.inning, this.endUtc);

  final DateTime startUtc;
  final int inning;
  final DateTime? endUtc;

  DateTime get effectiveEndUtc => endUtc ?? startUtc;
}
