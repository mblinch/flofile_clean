import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/mlb_inning_from_timestamp_service.dart';

MlbPlayStart _play(String start, String end, int inning) {
  return MlbPlayStart(
    DateTime.parse(start).toUtc(),
    inning,
    DateTime.parse(end).toUtc(),
  );
}

void main() {
  final afternoon = [
    _play('2026-09-23T17:37:54Z', '2026-09-23T17:39:28Z', 1),
    _play('2026-09-23T20:12:36Z', '2026-09-23T20:14:26Z', 9),
  ];
  final night = [
    _play('2026-09-23T22:35:47Z', '2026-09-23T22:37:30Z', 1),
    _play('2026-09-23T23:05:00Z', '2026-09-23T23:08:00Z', 4),
    _play('2026-09-24T00:56:53Z', '2026-09-24T00:57:45Z', 9),
  ];

  test('doubleheader photo uses the game that was in progress', () {
    final duringNight = MlbInningFromTimestampService.timelineForPhoto(
      [afternoon, night],
      DateTime.parse('2026-09-23T23:10:00Z'),
    );
    expect(duringNight.phase, MlbPhotoGametimePhase.live);
    expect(duringNight.inningNumber, 4);

    final duringAfternoon = MlbInningFromTimestampService.timelineForPhoto(
      [night, afternoon],
      DateTime.parse('2026-09-23T18:00:00Z'),
    );
    expect(duringAfternoon.phase, MlbPhotoGametimePhase.live);
    expect(duringAfternoon.inningNumber, 1);
  });

  test('a photo after both games is postgame of the later game', () {
    final after = MlbInningFromTimestampService.timelineForPhoto(
      [afternoon, night],
      DateTime.parse('2026-09-24T02:00:00Z'),
    );
    expect(after.phase, MlbPhotoGametimePhase.postgame);
  });
}
