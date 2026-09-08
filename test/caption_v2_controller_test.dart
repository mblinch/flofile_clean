import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_transfer_payload.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/data/iptc_caption_writer.dart';
import 'package:quick_cap/services/mlb_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Player player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

class _FakeCaptionWriter extends IptcCaptionWriter {
  _FakeCaptionWriter(this.succeedingPaths);

  final Set<String> succeedingPaths;
  int calls = 0;
  Map<String, String>? lastValues;

  @override
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  }) async {
    calls++;
    lastValues = Map<String, String>.from(values);
    return paths.where(succeedingPaths.contains).toList();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('selects and toggles multiple players from the same team', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';
    final first = player('Bo Bichette', '11');
    final second = player('Vladimir Guerrero Jr.', '27');

    controller.selectPlayer(first, isHome: true);
    controller.selectPlayer(second, isHome: true);

    expect(controller.selectedPlayers, hasLength(2));
    expect(controller.personality, 'Bo Bichette;Vladimir Guerrero Jr.');
    expect(controller.isPlayerSelected(first, isHome: true), isTrue);
    expect(controller.isPlayerSelected(second, isHome: true), isTrue);

    controller.selectPlayer(first, isHome: true);
    expect(controller.selectedPlayers.single.player, same(second));
  });

  test('uses plural caption wording for multiple players', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectPlayer(
      player('Vladimir Guerrero Jr.', '27'),
      isHome: true,
    );
    controller.selectVerb('Celebrates');

    final body = controller.buildCaptionBody();
    expect(body, contains('Bo Bichette'));
    expect(body, contains('Vladimir Guerrero Jr.'));
    expect(body, contains('celebrate against'));
  });

  test('first selected team stays subject and opposing picks keep order', () {
    final controller = CaptionV2Controller();
    final homeOne = player('Home One', '1');
    final awayOne = player('Away One', '2');
    final homeTwo = player('Home Two', '3');
    final awayTwo = player('Away Two', '4');

    controller.selectPlayer(homeOne, isHome: true);
    controller.selectPlayer(awayOne, isHome: false);
    controller.selectPlayer(homeTwo, isHome: true);
    controller.selectPlayer(awayTwo, isHome: false);

    expect(
      controller.selectedPlayers.map((row) => row.player.fullName),
      ['Home One', 'Away One', 'Home Two', 'Away Two'],
    );
    expect(
      controller.subjectPlayers.map((row) => row.player.fullName),
      ['Home One', 'Home Two'],
    );
    expect(
      controller.opposingPlayers.map((row) => row.player.fullName),
      ['Away One', 'Away Two'],
    );
    expect(
      controller.personality,
      'Home One;Away One;Home Two;Away Two',
    );
  });

  test('manual caption overrides generated caption text', () {
    final controller = CaptionV2Controller()
      ..manualCaptionOverride = 'Edited caption text';

    expect(controller.buildCaptionSentence(), 'Edited caption text');
    expect(
      controller.captionValues()['IPTC:Caption-Abstract'],
      'Edited caption text',
    );
  });

  test('caption values publish headline personality and keyword aliases', () {
    final controller = CaptionV2Controller()
      ..manualCaptionOverride = 'Caption'
      ..headline = 'Headline'
      ..personality = 'Manual Person;Player'
      ..keywords = 'manual, action';

    final values = controller.captionValues();

    expect(values['IPTC:Headline'], 'Headline');
    expect(values['XMP:Headline'], 'Headline');
    expect(values['Personality'], 'Manual Person;Player');
    expect(values['IPTC:Keywords'], 'manual, action');
    expect(values['XMP-dc:Subject'], 'manual, action');
  });

  test('personality selection preserves unrelated embedded names', () {
    final controller = CaptionV2Controller()..showPersonalityField = true;
    controller.setPersonality('Embedded Person;Manual Person');

    final selected = player('Selected Player', '9');
    controller.selectPlayer(selected, isHome: true);
    expect(
      controller.personality,
      'Embedded Person;Manual Person;Selected Player',
    );

    controller.selectPlayer(selected, isHome: true);
    expect(controller.personality, 'Embedded Person;Manual Person');
  });

  test('keyword automation preserves manual values and dedupes case', () {
    final controller = CaptionV2Controller()
      ..showKeywordsField = true
      ..applyVerbKeywords = true
      ..applyPlayerNamesToKeywords = true;
    controller.setKeywords('Manual, HIT, manual');

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectVerb('Single');

    expect(controller.keywords, contains('Manual'));
    expect(
      controller.keywords
          .split(',')
          .where((value) => value.trim().toLowerCase() == 'hit'),
      hasLength(1),
    );
    expect(controller.keywords, contains('Bo Bichette'));
  });

  test('grand slam and celebration state add focused keywords', () {
    final controller = CaptionV2Controller()
      ..showKeywordsField = true
      ..applyVerbKeywords = true
      ..applyPlayerNamesToKeywords = false;

    controller.selectVerb('Grand Slam');
    expect(controller.keywords.toLowerCase(), contains('grand slam'));

    controller.selectVerb('Celebrates');
    expect(controller.keywords.toLowerCase(), contains('jubilation'));
    expect(controller.keywords.toLowerCase(), isNot(contains('grand slam')));
  });

  test('baseball names an opposing pitcher for a walk', () {
    final controller = CaptionV2Controller()
      ..sport = 'baseball'
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectPlayer(player('Gerrit Cole', '45'), isHome: false);
    controller.selectVerb('Walks');

    final body = controller.buildCaptionBody();
    expect(body, contains('Bo Bichette'));
    expect(body, contains('takes a walk against Gerrit Cole'));
    expect(body, contains('of the New York Yankees'));
  });

  test('baseball applies plural hit and RBI wording to co-subjects only', () {
    final controller = CaptionV2Controller()
      ..sport = 'baseball'
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectPlayer(player('Aaron Judge', '99'), isHome: false);
    controller.selectPlayer(
      player('Vladimir Guerrero Jr.', '27'),
      isHome: true,
    );
    controller.selectVerb('Double');
    controller.setRbi(2);

    final body = controller.buildCaptionBody();
    expect(body, contains('Bo Bichette'));
    expect(body, contains('Vladimir Guerrero Jr.'));
    expect(body, contains('hit a two-RBI double'));
    expect(body, contains('against Aaron Judge'));
  });

  test('hockey checks use plural agreement and named opponent', () {
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Montreal Canadiens';

    controller.selectPlayer(player('Auston Matthews', '34'), isHome: true);
    controller.selectPlayer(player('Mitch Marner', '16'), isHome: true);
    controller.selectPlayer(player('Nick Suzuki', '14'), isHome: false);
    controller.selectVerb('Checks');

    final body = controller.buildCaptionBody();
    expect(body, contains('Matthews'));
    expect(body, contains('Marner'));
    expect(body, contains('check against Nick Suzuki'));
    expect(body, contains('of the Montreal Canadiens'));
  });

  test('basketball contest assigns the selected shooter role', () {
    final controller = CaptionV2Controller()
      ..sport = 'basketball'
      ..homeTeam = 'Toronto Raptors'
      ..awayTeam = 'New York Knicks';

    controller.selectPlayer(player('Scottie Barnes', '4'), isHome: true);
    controller.selectPlayer(player('Jalen Brunson', '11'), isHome: false);
    controller.selectVerb('Contests');

    expect(
      controller.buildCaptionBody(),
      contains('contests a shot by Jalen Brunson'),
    );
  });

  test('basketball steal uses selected opponent as source', () {
    final controller = CaptionV2Controller()
      ..sport = 'basketball'
      ..homeTeam = 'Toronto Raptors'
      ..awayTeam = 'New York Knicks';

    controller.selectPlayer(player('Scottie Barnes', '4'), isHome: true);
    controller.selectPlayer(player('Jalen Brunson', '11'), isHome: false);
    controller.selectVerb('Steals the Ball');

    expect(
      controller.buildCaptionBody(),
      contains('steals the ball from Jalen Brunson'),
    );
  });

  test('soccer battles retain V1 ball wording with opposing player', () {
    final controller = CaptionV2Controller()
      ..sport = 'soccer'
      ..homeTeam = 'Toronto FC'
      ..awayTeam = 'Inter Miami';

    controller.selectPlayer(player('Jonathan Osorio', '21'), isHome: true);
    controller.selectPlayer(player('Federico Bernardeschi', '10'),
        isHome: true);
    controller.selectPlayer(player('Lionel Messi', '10'), isHome: false);
    controller.selectVerb('Battles');

    expect(
      controller.buildCaptionBody(),
      contains('battle for the ball against Lionel Messi'),
    );
  });

  test('removing the first pick promotes the next ordered selection', () {
    final controller = CaptionV2Controller();
    final first = player('First Subject', '1');
    final opponent = player('Opponent', '2');
    final second = player('Second Subject', '3');
    controller.selectPlayer(first, isHome: true);
    controller.selectPlayer(opponent, isHome: false);
    controller.selectPlayer(second, isHome: true);

    controller.selectPlayer(first, isHome: true);

    expect(controller.selectedPlayer, same(opponent));
    expect(controller.selectedIsHome, isFalse);
    expect(controller.subjectPlayers.single.player, same(opponent));
    expect(controller.opposingPlayers.single.player, same(second));
  });

  test('selection edits clear stale manual caption and reset clears state', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home'
      ..awayTeam = 'Away';
    controller.setManualCaption('Hand edited');
    controller.selectPlayer(player('Home Player', '1'), isHome: true);
    expect(controller.manualCaptionOverride, isNull);

    controller.selectVerb('Shoots');
    controller.setManualCaption('Another edit');
    controller.setRbi(2);
    expect(controller.manualCaptionOverride, isNull);

    controller.resetToStartup();
    expect(controller.selectedPlayers, isEmpty);
    expect(controller.selectedVerb, isNull);
    expect(controller.personality, isEmpty);
    expect(controller.manualCaptionOverride, isNull);
  });

  test('setSelectedPlayers deduplicates while preserving role order', () {
    final controller = CaptionV2Controller();
    final home = RosterHit(player: player('Home Player', '1'), isHome: true);
    final away = RosterHit(player: player('Away Player', '2'), isHome: false);

    controller.setSelectedPlayers([away, home, away]);

    expect(controller.selectedPlayers, [away, home]);
    expect(controller.subjectPlayers, [away]);
    expect(controller.opposingPlayers, [home]);
  });

  test('applies clipboard and previous captions exactly', () {
    final controller = CaptionV2Controller();
    const payload = CaptionTransferPayload(
      caption: '  Exact edited caption  ',
      personality: 'Player One;Player Two',
    );

    controller.applyTransferredCaption(payload);
    expect(controller.buildCaptionSentence(), '  Exact edited caption  ');
    expect(controller.personality, 'Player One;Player Two');

    controller.previousCaption = payload;
    controller.setManualCaption(null);
    expect(controller.applyPreviousCaption(), isTrue);
    expect(controller.buildCaptionSentence(), '  Exact edited caption  ');
  });

  test('reset restores embedded caption state without ending session', () {
    final controller = CaptionV2Controller()
      ..sessionReady = true
      ..currentIptcMeta = {
        'IPTC:Description': 'Embedded caption',
        'XMP-getty:Personality': 'Embedded person',
      };
    controller.selectPlayer(player('New Player', '1'), isHome: true);
    controller.selectVerb('Celebrates');
    controller.setManualCaption('Edited');

    controller.resetCurrentCaption();

    expect(controller.sessionReady, isTrue);
    expect(controller.selectedPlayers, isEmpty);
    expect(controller.selectedVerb, isNull);
    expect(controller.manualCaptionOverride, isNull);
    expect(controller.originalCaption, 'Embedded caption');
    expect(controller.personality, 'Embedded person');
  });

  test('publishes selected images in frame order', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg', '/three.jpg'];

    controller.setSelectedImagePaths(['/three.jpg', '/one.jpg']);

    expect(
      controller.orderedSelectedImagePaths,
      ['/one.jpg', '/three.jpg'],
    );
  });

  test('forward burst and handled-chain advance exclude earlier frames', () {
    final start = DateTime(2026, 9, 7, 12);
    final controller = CaptionV2Controller()
      ..imagePaths = [
        '/before.jpg',
        '/anchor.jpg',
        '/burst.jpg',
        '/after.jpg',
      ]
      ..currentIndex = 1
      ..captureByPath.addAll({
        '/before.jpg': start,
        '/anchor.jpg': start.add(const Duration(seconds: 1)),
        '/burst.jpg': start.add(const Duration(seconds: 2)),
        '/after.jpg': start.add(const Duration(seconds: 5)),
      });

    final chain = controller.forwardBurstChain;
    expect(chain, ['/anchor.jpg', '/burst.jpg']);

    controller.advancePastHandledChain(chain);
    expect(controller.currentPath, '/after.jpg');
  });

  test('pinned verb survives frame navigation while unpinned verb clears', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg'];

    controller.selectVerb('Single');
    controller.goToIndex(1);
    expect(controller.selectedVerb, isNull);

    controller.goToIndex(0);
    controller.toggleVerbPin('Double');
    expect(controller.pinnedVerb, 'Double');
    controller.goToIndex(1);
    expect(controller.selectedVerb, 'Double');

    controller.unpinVerb();
    controller.goToIndex(0);
    expect(controller.selectedVerb, isNull);
  });

  test('bulk manual save marks only successful paths captioned', () async {
    final writer = _FakeCaptionWriter({'/one.jpg', '/three.jpg'});
    final controller = CaptionV2Controller(writer: writer)
      ..imagePaths = ['/one.jpg', '/two.jpg', '/three.jpg']
      ..manualCaptionOverride = 'Manual caption';

    final result = await controller.savePaths(controller.imagePaths);

    expect(result.succeededPaths, ['/one.jpg', '/three.jpg']);
    expect(result.failedPaths, ['/two.jpg']);
    expect(controller.savedImages, {'/one.jpg', '/three.jpg'});
    expect(controller.captionedImages, {'/one.jpg', '/three.jpg'});
    expect(controller.statusMessage, 'Saved 2 of 3; 1 failed');
  });

  test('untouched embedded caption saves template-only, not captioned',
      () async {
    final writer = _FakeCaptionWriter({});
    final controller = CaptionV2Controller(writer: writer)
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..currentIptcMeta = {'IPTC:Description': 'Existing caption'};

    final result = await controller.savePaths(controller.imagePaths);

    expect(result.allSucceeded, isTrue);
    expect(writer.calls, 0);
    expect(controller.savedImages, {'/one.jpg', '/two.jpg'});
    expect(controller.captionedImages, isEmpty);
  });

  test('metadata-only save preserves the embedded caption', () async {
    final writer = _FakeCaptionWriter({'/one.jpg'});
    final controller = CaptionV2Controller(writer: writer)
      ..imagePaths = ['/one.jpg']
      ..currentIptcMeta = {'IPTC:Description': 'Embedded caption'};
    controller.setHeadline('Edited headline');

    final result = await controller.savePaths(['/one.jpg']);

    expect(result.allSucceeded, isTrue);
    expect(
      writer.lastValues?['IPTC:Caption-Abstract'],
      'Embedded caption',
    );
    expect(writer.lastValues?['IPTC:Headline'], 'Edited headline');
    expect(controller.captionedImages, isEmpty);
  });

  test('total bulk failure updates no saved or captioned paths', () async {
    final controller = CaptionV2Controller(
      writer: _FakeCaptionWriter({}),
    )
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..manualCaptionOverride = 'Manual caption';

    final result = await controller.savePaths(controller.imagePaths);

    expect(result.anySucceeded, isFalse);
    expect(controller.savedImages, isEmpty);
    expect(controller.captionedImages, isEmpty);
    expect(controller.statusMessage, 'Save failed for all 2 frames');
  });
}
