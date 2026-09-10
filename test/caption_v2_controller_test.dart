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

  test('player-only selection still uses styled caption with date and byline',
      () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'Colorado Rockies'
      ..city = 'Toronto'
      ..country = 'Canada'
      ..venue = 'Rogers Centre'
      ..photographerName = 'Jane Doe'
      ..agencyName = 'Getty Images';

    controller.selectPlayer(player('Sean Keys', '20'), isHome: true);
    controller.selectPlayer(player('Jesus Sanchez', '12'), isHome: true);
    controller.selectPlayer(player('Nathan Lukes', '38'), isHome: true);
    controller.selectPlayer(player('Zac Veen', '13'), isHome: false);

    final body = controller.buildCaptionBody();
    expect(body, contains('Sean Keys'));
    expect(body, contains('Jesus Sanchez'));
    expect(body, contains('Nathan Lukes'));
    expect(body, contains('Zac Veen'));
    expect(body, contains('of the Colorado Rockies'));
    expect(body, isNot(contains('20 Keys +')));

    final caption = controller.buildCaptionSentence();
    expect(caption, isNot(contains('20 Keys +')));
    expect(caption.toLowerCase(), contains('toronto'));
    expect(caption, contains('Rogers Centre'));
    expect(caption, contains('Jane Doe'));
    expect(
      caption,
      anyOf(
        contains(RegExp(r'\d{4}')),
        contains(RegExp(
          r'(January|February|March|April|May|June|July|August|September|October|November|December)',
        )),
      ),
    );
  });

  test('uses an exact session-only custom verb phrase', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.setCustomVerbPhrase('poses with the trophy');

    expect(controller.selectedVerb, isNull);
    expect(controller.hasVerbSelection, isTrue);
    expect(controller.hasCompleteCaption, isTrue);
    expect(controller.verbChipLabel, 'poses with the trophy');
    expect(
      controller.buildCaptionBody(),
      contains('poses with the trophy against the New York Yankees'),
    );
  });

  test('custom verb supports pin and last-used session actions', () {
    final controller = CaptionV2Controller();

    controller.setCustomVerbPhrase('signs autographs');
    controller.toggleCustomVerbPin();
    expect(controller.customVerbPinned, isTrue);

    controller.setCustomVerbPhrase('');
    expect(controller.customVerbPinned, isFalse);
    controller.useLastCustomVerb();
    expect(controller.customVerbPhrase, 'signs autographs');

    controller.selectVerb('Celebrates');
    expect(controller.customVerbPhrase, isEmpty);
    expect(controller.customVerbPinned, isFalse);
  });

  test('celebration selector applies and toggles a celebration type', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectVerb('Celebrates');

    expect(controller.verbNeedsCelebration('Celebrates'), isTrue);
    expect(controller.celebrationOptionsFor('Celebrates'), contains('Scoring'));

    controller.setCelebrationType('Scoring');
    expect(controller.buildCaptionBody(), contains('celebrates scoring'));

    controller.setCelebrationType('Scoring');
    expect(controller.celebrationType, isNull);
  });

  test('hit verbs expose the V1 reaction mechanic', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectVerb('Double');

    expect(controller.verbNeedsCelebration('Double'), isTrue);
    expect(controller.celebrationOptionsFor('Double'), contains('Celebrates'));

    controller.setCelebrationType('Celebrates');
    expect(
      controller.buildCaptionBody(),
      contains('celebrates after hitting a double'),
    );
  });

  test('compound live search keeps jersey and verb matches visible', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Vladimir Guerrero Jr.', '27')]
      ..awayRoster = [player('Away Player', '27')];

    controller.setSearchQuery('27 home run');

    expect(controller.searchHasJerseyAndVerb, isTrue);
    expect(controller.filteredHome.single.player.fullName,
        'Vladimir Guerrero Jr.');
    expect(controller.filteredAway.single.player.fullName, 'Away Player');
    expect(controller.filteredVerbs, contains('Home Run'));
    expect(
      controller.topSearchHits().map((hit) => hit.kind),
      containsAll(['player', 'verb']),
    );
    expect(
      controller
          .topSearchHits()
          .where((hit) => hit.kind == 'player')
          .map((hit) => hit.shortcutLabel),
      ['H', 'V'],
    );
  });

  test('standalone team prefix does not match players or verbs', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Home Player', '27')]
      ..awayRoster = [player('Visiting Player', '27')]
      ..setSearchQuery('H');

    expect(controller.searchIsTeamPrefixOnly, isTrue);
    expect(controller.filteredHome, isEmpty);
    expect(controller.filteredAway, isEmpty);
    expect(controller.filteredVerbs, isEmpty);
  });

  test('verb search uses shortest prefixes and multi-word initials', () {
    final controller = CaptionV2Controller()
      ..setSearchOpen(true)
      ..selectPlayer(player('Home Player', '27'), isHome: true);

    controller.setSearchQuery('h');
    expect(controller.filteredVerbs, contains('Hit by Pitch'));
    expect(controller.filteredVerbs, isNot(contains('Single')));

    controller.setSearchQuery('hbp');
    expect(controller.filteredVerbs, ['Hit by Pitch']);

    controller.setSearchQuery('si');
    expect(controller.filteredVerbs, ['Single']);
  });

  test('RBI choices use their value as the shortcut label', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Home Player', '27')];

    expect(controller.submitSearchCommand('27 single'), isTrue);
    expect(controller.guidedSearchPrompt, 'How many RBI?');
    expect(
      controller.topSearchHits().map((hit) => hit.shortcutLabel),
      ['0', '1', '2', '3'],
    );
  });

  test('opening Firebar preserves the active caption fields', () {
    final controller = CaptionV2Controller()
      ..manualCaptionOverride = 'Existing caption'
      ..personality = 'Existing Person'
      ..keywords = 'existing, keywords'
      ..selectedVerb = 'Double'
      ..rbi = 2;
    controller.selectedPlayers
        .add(RosterHit(player: player('Existing Player', '7'), isHome: true));
    controller.selectedPlayer = controller.selectedPlayers.first.player;

    controller.setSearchOpen(true);

    expect(controller.captionSelectionStarted, isFalse);
    expect(controller.selectedPlayers, hasLength(1));
    expect(controller.selectedPlayer?.fullName, 'Existing Player');
    expect(controller.selectedVerb, 'Double');
    expect(controller.manualCaptionOverride, 'Existing caption');
    expect(controller.personality, 'Existing Person');
    expect(controller.keywords, 'existing, keywords');
    expect(controller.rbi, 2);
    expect(controller.firebarCommitted, hasLength(2));
  });

  test('compound search asks for inning after player and verb', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Vladimir Guerrero Jr.', '27')]
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.setSearchOpen(true);
    controller.setSearchQuery('27 celebrates');
    controller
        .topSearchHits()
        .firstWhere((hit) => hit.kind == 'player')
        .apply();
    controller.topSearchHits().firstWhere((hit) => hit.kind == 'verb').apply();

    expect(controller.guidedSearchPrompt, 'What inning?');
    controller.topSearchHits().firstWhere((hit) => hit.label == '3rd').apply();
    expect(controller.inning, 3);
    expect(controller.guidedSearchPrompt, 'Save or FTP?');
    expect(
      controller.topSearchHits().map((hit) => hit.label),
      containsAll(['Save', 'FTP']),
    );
  });

  test('typed inning previews immediately and completes without Enter', () {
    final controller = CaptionV2Controller();

    controller.previewCommandInning(1);
    expect(controller.inning, 1);
    controller.completeCommandInning(10);

    expect(controller.inning, 10);
    expect(controller.guidedSearchPrompt, 'Save or FTP?');
  });

  test('last command number sets the inning', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Vladimir Guerrero Jr.', '27')]
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees';

    controller.setSearchOpen(true);
    expect(controller.submitSearchCommand('27 celebrates 6'), isTrue);

    expect(controller.selectedPlayer?.fullName, 'Vladimir Guerrero Jr.');
    expect(controller.selectedVerb, 'Celebrates');
    expect(controller.inning, 6);
    expect(controller.guidedSearchPrompt, 'Save or FTP?');
  });

  test('h and v command prefixes choose the home or visiting player', () {
    CaptionV2Controller buildController() => CaptionV2Controller()
      ..homeRoster = [player('Home Player', '27')]
      ..awayRoster = [player('Visiting Player', '27')];

    final home = buildController()..setSearchOpen(true);
    expect(home.submitSearchCommand('h 27 celebrates 6'), isTrue);
    expect(home.selectedPlayer?.fullName, 'Home Player');

    final visitor = buildController()..setSearchOpen(true);
    expect(visitor.submitSearchCommand('v27 celebrates 6'), isTrue);
    expect(visitor.selectedPlayer?.fullName, 'Visiting Player');
  });

  test('navigating to another frame clears the Firebar', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..setSearchOpen(true)
      ..setSearchQuery('27 celebrates 6');

    controller.nextFrame();

    expect(controller.currentIndex, 1);
    expect(controller.searchQuery, isEmpty);
    expect(controller.searchOpen, isFalse);
    expect(controller.searchGuided, isFalse);
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

  test('Firebar matching follows name, jersey, and verb rules', () {
    final sanchez = player('Jesús Sánchez', '4');
    final forty = player('Kazuma Okamoto', '40');
    final straw = player('Myles Straw', '3');
    final controller = CaptionV2Controller()
      ..homeRoster = [sanchez, forty]
      ..awayRoster = [straw]
      ..setSearchOpen(true);

    controller.setSearchQuery('sanchez');
    expect(controller.firebarHomeResults.single.player, same(sanchez));
    expect(controller.firebarAwayResults, isEmpty);

    controller.setSearchQuery('4');
    expect(
      controller.firebarHomeResults.map((result) => result.player),
      [sanchez, forty],
    );
    expect(controller.firebarVerbResults, isEmpty);

    controller.setSearchQuery('h4');
    expect(
      controller.firebarHomeResults.map((result) => result.player),
      [sanchez, forty],
    );
    expect(controller.firebarAwayResults, isEmpty);

    controller.setSearchQuery('v3');
    expect(controller.firebarHomeResults, isEmpty);
    expect(controller.firebarAwayResults.single.player, same(straw));

    controller.setSearchQuery('st');
    expect(controller.firebarAwayResults.single.player, same(straw));
    expect(
      controller.firebarVerbResults
          .map((result) => controller.verbDefinition(result.verbKey!)?.label),
      contains('Steals'),
    );

    controller.setSearchQuery('hr');
    final hrLabels = controller.firebarVerbResults
        .map((result) => controller.verbDefinition(result.verbKey!)?.label);
    expect(hrLabels, contains('Home Run'));
    expect(hrLabels, isNot(contains('Throws')));

    controller.setSearchQuery('hbp');
    expect(
      controller.firebarVerbResults
          .map((result) => controller.verbDefinition(result.verbKey!)?.label),
      contains('Hit by Pitch'),
    );
  });

  test('Firebar uses one bounded selection across all three lanes', () {
    final active = player('Steven Home', '1');
    final other = player('Myles Straw', '3');
    final controller = CaptionV2Controller()
      ..homeRoster = [active]
      ..awayRoster = [other]
      ..setSearchOpen(true)
      ..setSearchQuery('st');

    expect(controller.firebarSelectedResult?.player, same(active));
    controller.moveFirebarSelection(1);
    expect(controller.firebarSelectedResult?.kind, FirebarResultKind.verb);

    for (var i = 0; i < 100; i++) {
      controller.moveFirebarSelection(1);
    }
    expect(controller.firebarSelectedResult?.player, same(other));
    controller.moveFirebarSelection(1);
    expect(controller.firebarSelectedResult?.player, same(other));
  });

  test('Firebar commits chips, clears query, and exits cleanly', () {
    final first = player('Bo Bichette', '11');
    final controller = CaptionV2Controller()
      ..homeRoster = [first]
      ..setSearchOpen(true)
      ..setSearchQuery('bo');

    controller.commitSelectedFirebarResult();
    expect(controller.selectedPlayers.single.player, same(first));
    expect(controller.firebarCommitted.single.player, same(first));
    expect(controller.searchQuery, isEmpty);

    controller.removeLastFirebarChip();
    expect(controller.selectedPlayers, isEmpty);
    expect(controller.firebarCommitted, isEmpty);
    expect(controller.captionSelectionStarted, isFalse);
    expect(controller.manualCaptionOverride, isNull);

    controller.setSearchQuery('single');
    controller.setSearchOpen(false);
    expect(controller.searchQuery, isEmpty);
    expect(controller.firebarSelectedResult, isNull);
    expect(controller.searchOpen, isFalse);
  });

  test('Firebar inning shorthand updates the inning selector', () {
    final controller = CaptionV2Controller()
      ..setSearchOpen(true)
      ..setPre(true);

    controller.setSearchQuery('i6');
    expect(controller.inning, 6);
    expect(controller.preGame, isFalse);
    expect(controller.searchQuery, isEmpty);

    controller.setSearchQuery('8i');
    expect(controller.inning, 8);
    expect(controller.searchQuery, isEmpty);
  });

  test('baseball extras select real innings through 27', () {
    final controller = CaptionV2Controller();

    expect(controller.timingMaxInning, 27);
    controller.setInning(14);
    expect(controller.inning, 14);
    expect(controller.inningLabel, '14th');
    expect(controller.timingCaptionClause, 'during the 14th inning');

    controller.setInning(27);
    expect(controller.inning, 27);
    expect(controller.inningLabel, '27th');

    controller.setInning(28);
    expect(controller.inning, 27);

    controller.setSearchOpen(true);
    controller.setSearchQuery('i19');
    expect(controller.inning, 19);
  });

  test('Firebar asks for verb sub-options before continuing', () {
    final controller = CaptionV2Controller()
      ..setSearchOpen(true)
      ..setSearchQuery('hr');
    final homeRun = controller.firebarVerbResults.singleWhere(
      (result) => result.verbKey == 'Home Run',
    );

    controller.commitFirebarResult(homeRun);
    expect(controller.selectedVerb, 'Home Run');
    expect(
      controller.firebarOptions.map((option) => option.label),
      ['1R', '2R', '3R', 'GS'],
    );
    expect(controller.firebarOptionPrompt, 'Home run type?');

    controller.setSearchQuery('2r');
    controller.commitSelectedFirebarResult();
    expect(controller.rbi, 2);
    expect(controller.searchQuery, isEmpty);
  });

  test('running verbs accept a base and rewrite the caption action', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'Houston Astros'
      ..homeRoster = [player('George Springer', '4')]
      ..selectPlayer(player('George Springer', '4'), isHome: true)
      ..selectVerb('Steals');
    addTearDown(controller.dispose);

    expect(controller.verbNeedsBase('Steals'), isTrue);
    expect(controller.buildCaptionBody(), contains('steals a base'));

    controller.setSelectedBase('2B');
    expect(controller.selectedBase, '2B');
    expect(controller.buildCaptionBody(), contains('steals second base'));

    controller.setSelectedBase('Home');
    expect(controller.buildCaptionBody(), contains('steals home'));

    controller.selectVerb('Slides');
    controller.setSelectedBase('Home');
    expect(controller.buildCaptionBody(), contains('slides into home plate'));
  });
}
