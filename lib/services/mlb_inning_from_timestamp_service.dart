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
    final games = await _findScheduledGames(
      userHomeName: userHomeName,
      userAwayName: userAwayName,
      calendarDay: calendarDay,
    );
    return [for (final game in games) game.gamePk];
  }

  Future<List<_ScheduledGame>> _findScheduledGames({
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

    final games = <_ScheduledGame>[];
    final seen = <int>{};
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
          if (id != null && seen.add(id)) {
            games.add(_ScheduledGame(gamePk: id, isFinal: _gameIsFinal(g)));
          }
        }
      }
    }
    return games;
  }

  /// `null` when the schedule payload has no usable status.
  static bool? _gameIsFinal(Map<String, dynamic> game) {
    final status = game['status'];
    if (status is! Map) return null;
    final abstract = status['abstractGameState']?.toString().trim() ?? '';
    if (abstract == 'Final') return true;
    if (abstract == 'Live' || abstract == 'Preview') return false;
    final detailed = status['detailedState']?.toString().toLowerCase() ?? '';
    if (detailed.contains('final') ||
        detailed.contains('game over') ||
        detailed.contains('completed')) {
      return true;
    }
    if (abstract.isEmpty && detailed.isEmpty) return null;
    return false;
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
  ///
  /// [gameIsFinal] aligns with [games]. `false` means the game is still in
  /// progress, so a photo after the last logged play stays in that inning
  /// instead of "following the game". `null` uses a short grace window.
  static MlbPhotoInningLookup timelineForPhoto(
    List<List<MlbPlayStart>> games,
    DateTime photoTimeUtc, {
    DateTime? photoCalendarDay,
    List<DateTime?>? gameCalendarDays,
    List<bool?>? gameIsFinal,
  }) {
    if (games.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: false,
        hasPlayByPlay: false,
      );
    }
    final scored = <_ScoredTimeline>[];
    for (var i = 0; i < games.length; i++) {
      final plays = games[i];
      if (plays.isEmpty) continue;
      scored.add(_scoreTimeline(
        plays,
        photoTimeUtc,
        gameCalendarDay: gameCalendarDays != null && i < gameCalendarDays.length
            ? gameCalendarDays[i]
            : null,
        gameIsFinal: gameIsFinal != null && i < gameIsFinal.length
            ? gameIsFinal[i]
            : null,
      ));
    }
    if (scored.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: true,
        hasPlayByPlay: false,
      );
    }
    scored.sort((a, b) {
      final cover = a.coverRank.compareTo(b.coverRank);
      if (cover != 0) return cover;
      return a.distance.compareTo(b.distance);
    });
    if (scored.first.inside) return scored.first.lookup;
    return _pickOutsideGame(
      scored,
      photoTimeUtc,
      photoCalendarDay: photoCalendarDay,
    );
  }

  /// A photo taken before first pitch of the game on the same date uses the
  /// pregame caption. Another date's finished game does not turn it into
  /// "following the game".
  static MlbPhotoInningLookup _pickOutsideGame(
    List<_ScoredTimeline> scored,
    DateTime photoTimeUtc, {
    DateTime? photoCalendarDay,
  }) {
    bool sameDate(_ScoredTimeline item) {
      final pitch = item.firstPitch.toUtc();
      final photo = photoTimeUtc.toUtc();
      if (_sameYmd(pitch, photo)) return true;
      if (photoCalendarDay != null && _sameYmd(pitch, photoCalendarDay)) {
        return true;
      }
      if (item.gameCalendarDay != null &&
          photoCalendarDay != null &&
          _sameYmd(item.gameCalendarDay!, photoCalendarDay)) {
        return true;
      }
      return false;
    }

    final sameDay = scored.where(sameDate).toList();
    final pool = sameDay.isNotEmpty ? sameDay : scored;
    final pre = pool
        .where((item) => item.lookup.phase == MlbPhotoGametimePhase.pregame)
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (sameDay.isNotEmpty && pre.isNotEmpty) return pre.first.lookup;

    final post = pool
        .where((item) => item.lookup.phase == MlbPhotoGametimePhase.postgame)
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (pre.isEmpty) return post.first.lookup;
    if (post.isEmpty) return pre.first.lookup;
    return post.first.distance <= pre.first.distance
        ? post.first.lookup
        : pre.first.lookup;
  }

  static bool _sameYmd(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// How long after the last logged play a photo can still be that inning when
  /// the schedule didn't say the game is live. Covers the gap between pitches
  /// and inning breaks without calling the next morning "the 9th inning".
  static const Duration liveGraceAfterLastPlay = Duration(minutes: 45);

  static _ScoredTimeline _scoreTimeline(
    List<MlbPlayStart> plays,
    DateTime photoTimeUtc, {
    DateTime? gameCalendarDay,
    bool? gameIsFinal,
  }) {
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
        coverRank: 2,
        distance: firstStart.difference(photoTimeUtc),
        boundary: firstStart,
        firstPitch: firstStart,
        gameCalendarDay: gameCalendarDay,
      );
    }
    if (photoTimeUtc.isAfter(endBound)) {
      final sinceLastPlay = photoTimeUtc.difference(endBound);
      final stillLive = gameIsFinal == false ||
          (gameIsFinal != true && sinceLastPlay <= liveGraceAfterLastPlay);
      if (stillLive) {
        return _ScoredTimeline(
          lookup: MlbPhotoInningLookup(
            hasScheduleMatch: true,
            hasPlayByPlay: true,
            phase: MlbPhotoGametimePhase.live,
            inningNumber: plays.last.inning,
          ),
          inside: true,
          coverRank: 1,
          distance: sinceLastPlay,
          boundary: endBound,
          firstPitch: firstStart,
          gameCalendarDay: gameCalendarDay,
        );
      }
      return _ScoredTimeline(
        lookup: const MlbPhotoInningLookup(
          hasScheduleMatch: true,
          hasPlayByPlay: true,
          phase: MlbPhotoGametimePhase.postgame,
        ),
        inside: false,
        coverRank: 2,
        distance: sinceLastPlay,
        boundary: endBound,
        firstPitch: firstStart,
        gameCalendarDay: gameCalendarDay,
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
      coverRank: 0,
      distance: Duration.zero,
      boundary: photoTimeUtc,
      firstPitch: firstStart,
      gameCalendarDay: gameCalendarDay,
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

    final timelines = <List<MlbPlayStart>>[];
    final gameDays = <DateTime?>[];
    final finals = <bool?>[];
    final seenPks = <int>{};
    for (final day in days) {
      final scheduled = await _findScheduledGames(
        userHomeName: userHomeName,
        userAwayName: userAwayName,
        calendarDay: day,
      );
      for (final game in scheduled) {
        if (!seenPks.add(game.gamePk)) continue;
        timelines.add(await _loadTimeline(game.gamePk));
        gameDays.add(DateTime(day.year, day.month, day.day));
        finals.add(game.isFinal);
      }
    }
    if (seenPks.isEmpty) {
      return const MlbPhotoInningLookup(
        hasScheduleMatch: false,
        hasPlayByPlay: false,
      );
    }
    return timelineForPhoto(
      timelines,
      photoTimeUtc,
      photoCalendarDay: photoCalendarDay ?? gameCalendarDay,
      gameCalendarDays: gameDays,
      gameIsFinal: finals,
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

class _ScoredTimeline {
  const _ScoredTimeline({
    required this.lookup,
    required this.inside,
    required this.coverRank,
    required this.distance,
    required this.boundary,
    required this.firstPitch,
    this.gameCalendarDay,
  });

  final MlbPhotoInningLookup lookup;
  final bool inside;

  /// 0 = photo falls inside logged plays, 1 = game still live after the last
  /// logged play, 2 = before first pitch or after a finished game.
  final int coverRank;
  final Duration distance;

  /// First pitch when [lookup] is pregame, last play when postgame.
  final DateTime boundary;

  /// First pitch of this game, used to match the photo's calendar date.
  final DateTime firstPitch;

  /// Schedule date this timeline was loaded for, when known.
  final DateTime? gameCalendarDay;
}

class _ScheduledGame {
  const _ScheduledGame({required this.gamePk, required this.isFinal});

  final int gamePk;

  /// `true` when the schedule says the game is final. `null` if unknown.
  final bool? isFinal;
}

class MlbPlayStart {
  const MlbPlayStart(this.startUtc, this.inning, this.endUtc);

  final DateTime startUtc;
  final int inning;
  final DateTime? endUtc;

  DateTime get effectiveEndUtc => endUtc ?? startUtc;
}
