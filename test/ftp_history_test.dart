import 'package:quick_cap/screens/caption_v2/data/ftp_history.dart';
import 'package:flutter_test/flutter_test.dart';

FtpHistoryEntry _entry({
  required String path,
  required DateTime at,
  String? sessionId,
}) {
  return FtpHistoryEntry(
    at: at,
    fileName: path,
    path: path,
    profile: 'Photoshelter',
    success: true,
    sessionId: sessionId,
  );
}

void main() {
  final earlier = DateTime(2026, 10, 17, 13);
  final now = DateTime(2026, 10, 18, 12, 45);
  const current = '/session/current.jpg';
  const previous = '/session/previous.jpg';

  test('open session shows only its own images', () {
    final entries = [
      _entry(path: current, at: now),
      _entry(path: previous, at: earlier),
    ];
    final visible = ftpHistoryForSession(
      entries,
      sessionId: null,
      sessionStartedAt: null,
      imagePaths: {current},
    );
    expect(visible.map((entry) => entry.path), [current]);
  });

  test('new session hides uploads from the previous one', () {
    final started = DateTime(2026, 10, 18, 12);
    final entries = [
      _entry(path: current, at: now, sessionId: 'new'),
      _entry(path: current, at: earlier),
      _entry(path: previous, at: earlier, sessionId: 'old'),
    ];
    final visible = ftpHistoryForSession(
      entries,
      sessionId: 'new',
      sessionStartedAt: started,
      imagePaths: {current, previous},
    );
    expect(visible.map((entry) => entry.sessionId), ['new']);
  });

  test('session id round-trips and stays empty when missing', () {
    final tagged = _entry(path: current, at: now, sessionId: 'abc');
    final restored = FtpHistoryEntry.fromJson(tagged.toJson());
    expect(restored.sessionId, 'abc');
    final legacy = FtpHistoryEntry.fromJson(
      _entry(path: current, at: now).toJson(),
    );
    expect(legacy.sessionId, isNull);
  });
}
