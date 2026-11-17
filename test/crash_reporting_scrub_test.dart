import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/crash_reporting_service.dart';
import 'package:sentry/sentry.dart';

void main() {
  test('scrubText strips paths, emails, and image filenames', () {
    final withPath =
        'Write failed /Users/mark/Pictures/game/DSC_1234.JPG for alice@wire.example '
        r'also C:\Photos\home\IMG_99.CR3';
    final scrubbedPath = CrashReportingService.scrubText(withPath);
    expect(scrubbedPath, isNot(contains('/Users/mark')));
    expect(scrubbedPath, isNot(contains(r'C:\Photos')));
    expect(scrubbedPath, isNot(contains('alice@wire.example')));
    expect(scrubbedPath, isNot(contains('DSC_1234.JPG')));
    expect(scrubbedPath, contains('[path]'));
    expect(scrubbedPath, contains('[email]'));

    // Basename without a directory prefix is still scrubbed.
    final scrubbedFile =
        CrashReportingService.scrubText('open DSC_1234.JPG now');
    expect(scrubbedFile, isNot(contains('DSC_1234.JPG')));
    expect(scrubbedFile, contains('[file]'));
  });

  test('scrubEvent drops user and path-like extras', () {
    CrashReportingService.updateSessionContext(
      wire: 'ap',
      iptcMode: 'fill',
      league: 'hockey',
    );

    final event = SentryEvent(
      message: SentryMessage(
        'Failed on /Users/mark/Desktop/secret.jpg for bob@example.com',
      ),
      user: SentryUser(email: 'bob@example.com', id: 'uid-1'),
      extra: {
        'caption': 'should never send',
        'file_path': '/tmp/photo.jpg',
        'exit_code': 1,
      },
    );

    final scrubbed = CrashReportingService.scrubEvent(event);
    expect(scrubbed, isNotNull);
    expect(scrubbed!.user, isNull);
    expect(scrubbed.message?.formatted, isNot(contains('/Users/mark')));
    expect(scrubbed.message?.formatted, isNot(contains('bob@example.com')));
    expect(scrubbed.extra?.containsKey('caption'), isFalse);
    expect(scrubbed.extra?.containsKey('file_path'), isFalse);
    expect(scrubbed.extra?['exit_code'], 1);
    expect(scrubbed.tags?['wire'], 'ap');
    expect(scrubbed.tags?['iptc_mode'], 'fill');
    expect(scrubbed.tags?['league'], 'hockey');
  });

  test('session tags never include caption text', () {
    CrashReportingService.updateSessionContext(
      wire: 'reuters',
      iptcMode: 'apply',
      league: 'soccer',
    );
    final tags = CrashReportingService.sessionTags;
    expect(tags.keys, isNot(contains('caption')));
    expect(tags['wire'], 'reuters');
    expect(tags['iptc_mode'], 'apply');
    expect(tags['league'], 'soccer');
  });
}
