import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_transfer_payload.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/data/team_abbrev.dart';
import 'package:quick_cap/screens/caption_v2/data/effective_verb_catalog.dart';
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

  test('Celebrates a Goal keeps first player as scorer with teammates', () {
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Montreal Canadiens';

    controller.selectPlayer(player('Auston Matthews', '34'), isHome: true);
    controller.selectPlayer(player('William Nylander', '88'), isHome: true);
    controller.selectPlayer(player('Mitch Marner', '16'), isHome: true);
    controller.selectVerb('Celebrates a Goal');

    final body = controller.buildCaptionBody();
    expect(body, startsWith('Auston Matthews'));
    expect(body, isNot(contains('Auston Matthews #34 and William')));
    expect(body, contains('celebrates a goal with'));
    expect(body, contains('William Nylander'));
    expect(body, contains('Mitch Marner'));
    expect(body, contains('against the Montreal Canadiens'));
    expect(body.toLowerCase(), isNot(contains('teammate')));
  });

  test('withTeammates catalog flag shapes Speaks captions like Celebrates a Goal',
      () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'hockey',
      categoryOrder: const ['Reactions'],
      verbOrder: const {
        'Reactions': ['Speaks'],
      },
      favorites: const {},
      customVerbs: const [
        {
          'label': 'Speaks',
          'verbPhrase': 'speaks',
          'pluralPhrase': 'speak',
          'category': 'Reactions',
          'withTeammates': true,
          'wantsOpponent': true,
          'isCustom': true,
        },
      ],
      customWordings: const {},
      overrides: const {},
      deletedVerbs: const {},
      catalogComplete: true,
    );
    expect(catalog.byKey['Speaks']!.withTeammates, isTrue);
  });

  test('single team mode omits opponent clause from captions', () {
    final controller = CaptionV2Controller()
      ..singleTeamMode = true
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = '';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectVerb('Celebrates');

    final body = controller.buildCaptionBody();
    expect(body, contains('Bo Bichette'));
    expect(body, contains('celebrates'));
    expect(body.toLowerCase(), isNot(contains('against')));
    expect(controller.hasOpponentTeam, isFalse);
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

  test('captions always name the other team', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'Cincinnati Reds';

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectVerb('Single');
    expect(
      controller.buildCaptionBody(),
      contains('against the Cincinnati Reds'),
    );

    controller.selectPlayer(player('Bo Bichette', '11'), isHome: true);
    controller.selectPlayer(player('Elly De La Cruz', '44'), isHome: false);
    controller.selectVerb('Post Game Win');
    expect(
      controller.buildCaptionBody(),
      contains('against the Toronto Blue Jays'),
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

  test('unpinned custom verb clears on frame change; pinned survives', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg'];

    controller.setCustomVerbPhrase('waves to fans');
    controller.goToIndex(1);
    expect(controller.customVerbPhrase, isEmpty);
    expect(controller.customVerbPinned, isFalse);

    controller.setCustomVerbPhrase('tips his cap');
    controller.toggleCustomVerbPin();
    controller.goToIndex(0);
    expect(controller.customVerbPinned, isTrue);
    expect(controller.customVerbPhrase, 'tips his cap');
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

  test('basketball half selection uses half caption wording', () {
    final controller = CaptionV2Controller()
      ..sport = 'basketball'
      ..homeTeam = 'Toronto Raptors'
      ..awayTeam = 'New York Knicks';

    expect(controller.timingUnitTitle, 'Half/Quarter');
    controller.setTimingHalf('1H');
    expect(controller.timingHalf, '1H');
    expect(controller.timingCaptionClause, 'during the first half');

    controller.setInning(3);
    expect(controller.timingHalf, isNull);
    expect(controller.timingCaptionClause, 'during the third quarter');
  });

  test('pre folds into in-their game identifier instead of stacking', () {
    final controller = CaptionV2Controller()
      ..sport = 'wnba'
      ..homeTeam = 'New York Liberty'
      ..awayTeam = 'Las Vegas Aces'
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: 'in their WNBA game',
      );

    controller.selectPlayer(player('Breanna Stewart', '30'), isHome: true);
    controller.selectVerb('Celebrates');
    controller.setPre(true);

    expect(controller.timingCaptionClause, isEmpty);
    expect(controller.buildCaptionBody(), isNot(contains('before the game')));
    expect(
      controller.buildCaptionSentence(),
      contains('ahead of their WNBA game'),
    );
    expect(
      controller.buildCaptionSentence(),
      isNot(contains('before the game')),
    );
    expect(
      controller.buildCaptionSentence(),
      isNot(contains('in their WNBA game')),
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

  test('caption box h34 / v88 expands to select roster players', () {
    final home = player('Home Ace', '34');
    final away = player('Away Ace', '88');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home'
      ..awayTeam = 'Away'
      ..homeRoster = [home]
      ..awayRoster = [away];

    controller.setManualCaption('h34 ');
    expect(controller.selectedPlayers.single.player, same(home));
    expect(controller.selectedIsHome, isTrue);
    expect(controller.manualCaptionOverride, isNull);
    expect(controller.displayedCaption.toLowerCase(), contains('home ace'));

    controller.selectedPlayers.clear();
    controller.setManualCaption('v88 ');
    expect(controller.selectedPlayers.single.player, same(away));
    expect(controller.selectedIsHome, isFalse);
    expect(controller.manualCaptionOverride, isNull);

    controller.selectedPlayers.clear();
    controller.setManualCaption('Hello h34 there ');
    expect(controller.selectedPlayers.single.player, same(home));
    expect(controller.manualCaptionOverride, 'Hello Home Ace there ');
  });

  test('caption box unknown jersey leaves text and reports status', () {
    final controller = CaptionV2Controller()
      ..homeRoster = [player('Home Ace', '34')];

    controller.setManualCaption('h99 ');
    expect(controller.selectedPlayers, isEmpty);
    expect(controller.manualCaptionOverride, 'h99 ');
    expect(controller.statusMessage, 'No player wearing #99');
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

  test('hockey checks and fights agree for one and multiple players', () {
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Montreal Canadiens';

    controller.selectPlayer(player('Auston Matthews', '34'), isHome: true);
    controller.selectPlayer(player('Nick Suzuki', '14'), isHome: false);

    controller.selectVerb('Checks');
    expect(
      controller.buildCaptionBody().toLowerCase(),
      contains('checks against nick suzuki'),
    );

    controller.selectVerb('Fights');
    expect(
      controller.buildCaptionBody().toLowerCase(),
      contains('fights against nick suzuki'),
    );

    controller.selectPlayer(player('Mitch Marner', '16'), isHome: true);
    controller.selectVerb('Fights');
    final fightBody = controller.buildCaptionBody().toLowerCase();
    expect(fightBody, contains('matthews'));
    expect(fightBody, contains('marner'));
    expect(fightBody, contains('fight against nick suzuki'));
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

  test('partial burst save advances to first unselected frame', () {
    final start = DateTime(2026, 9, 7, 12);
    final controller = CaptionV2Controller()
      ..imagePaths = [
        '/a.jpg',
        '/b.jpg',
        '/c.jpg',
        '/d.jpg',
        '/e.jpg',
        '/after.jpg',
      ]
      ..currentIndex = 0
      ..captureByPath.addAll({
        '/a.jpg': start,
        '/b.jpg': start.add(const Duration(milliseconds: 200)),
        '/c.jpg': start.add(const Duration(milliseconds: 400)),
        '/d.jpg': start.add(const Duration(milliseconds: 600)),
        '/e.jpg': start.add(const Duration(milliseconds: 800)),
        '/after.jpg': start.add(const Duration(seconds: 5)),
      });

    final chain = ['/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg', '/e.jpg'];
    controller.advanceAfterBurstSelection(
      chain: chain,
      savedPaths: ['/a.jpg', '/c.jpg'],
    );
    expect(controller.currentPath, '/b.jpg');

    controller.currentIndex = 0;
    controller.advanceAfterBurstSelection(
      chain: chain,
      savedPaths: chain,
    );
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

  test('pinned player survives frame navigation while unpinned player clears',
      () {
    final bo = player('Bo Bichette', '11');
    final vlad = player('Vladimir Guerrero Jr.', '27');
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..homeRoster = [bo, vlad];

    controller.selectPlayer(bo, isHome: true);
    controller.goToIndex(1);
    expect(controller.selectedPlayers, isEmpty);

    controller.goToIndex(0);
    controller.togglePlayerPin(vlad, isHome: true);
    expect(controller.isPlayerPinned(vlad, isHome: true), isTrue);
    expect(controller.isPlayerSelected(vlad, isHome: true), isTrue);

    controller.selectPlayer(bo, isHome: true);
    expect(controller.selectedPlayers, hasLength(2));
    expect(controller.isPlayerPinned(vlad, isHome: true), isTrue);

    controller.goToIndex(1);
    expect(controller.isPlayerPinned(vlad, isHome: true), isTrue);
    expect(controller.selectedPlayers, hasLength(1));
    expect(controller.selectedPlayer?.fullName, 'Vladimir Guerrero Jr.');
    expect(controller.captionSelectionStarted, isTrue);

    controller.unpinPlayer();
    controller.goToIndex(0);
    expect(controller.selectedPlayers, isEmpty);
  });

  test('pinned player stays pinned after selecting another player', () {
    final bo = player('Bo Bichette', '11');
    final vlad = player('Vladimir Guerrero Jr.', '27');
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..homeRoster = [bo, vlad];

    controller.togglePlayerPin(bo, isHome: true);
    expect(controller.isPlayerPinned(bo, isHome: true), isTrue);
    expect(controller.isPlayerSelected(bo, isHome: true), isTrue);

    controller.selectPlayer(vlad, isHome: true);
    expect(controller.isPlayerPinned(bo, isHome: true), isTrue);
    expect(controller.selectedPlayers, hasLength(2));

    controller.goToIndex(1);
    expect(controller.isPlayerPinned(bo, isHome: true), isTrue);
    expect(controller.selectedPlayers, hasLength(1));
    expect(controller.selectedPlayer?.fullName, 'Bo Bichette');
  });

  test('pinned catalog verb stays pinned after selecting another verb', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg'];

    controller.toggleVerbPin('Single');
    expect(controller.pinnedVerb, 'Single');
    expect(controller.selectedVerb, 'Single');

    controller.selectVerb('Double');
    expect(controller.pinnedVerb, 'Single');
    expect(controller.selectedVerb, 'Double');

    controller.goToIndex(1);
    expect(controller.pinnedVerb, 'Single');
    expect(controller.selectedVerb, 'Single');
  });

  test('pinned verb waits for a player before writing caption', () {
    final bo = player('Bo Bichette', '11');
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..homeRoster = [bo]
      ..currentIptcMeta = {'IPTC:Description': 'Embedded caption'};

    controller.toggleVerbPin('Single');
    expect(controller.pinDefersCaptionUntilPlayer, isTrue);
    expect(controller.displayedCaption, 'Embedded caption');
    expect(controller.captionSelectionStarted, isFalse);

    controller.goToIndex(1);
    expect(controller.selectedVerb, 'Single');
    expect(controller.pinDefersCaptionUntilPlayer, isTrue);
    expect(controller.displayedCaption, 'Embedded caption');

    controller.selectPlayer(bo, isHome: true);
    expect(controller.pinDefersCaptionUntilPlayer, isFalse);
    expect(controller.displayedCaption.toLowerCase(), contains('bichette'));
    expect(controller.displayedCaption.toLowerCase(), contains('single'));
  });

  test('Firebar verb override keeps catalog pin for the next frame', () {
    final bo = player('Bo Bichette', '11');
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg']
      ..homeRoster = [bo];

    controller.toggleVerbPin('Single');
    controller.selectPlayer(bo, isHome: true);
    expect(controller.pinnedVerb, 'Single');
    expect(controller.selectedVerb, 'Single');

    controller.setSearchOpen(true);
    controller.setSearchQuery('double');
    expect(controller.firebarCanQuickSaveVerb, isTrue);
    expect(controller.selectedVerb, 'Double'); // live preview
    expect(controller.pinnedVerb, 'Single');

    controller.commitFirebarResult(const FirebarResult.verb('Double'));
    expect(controller.selectedVerb, 'Double');
    expect(controller.pinnedVerb, 'Single');
    expect(controller.displayedCaption.toLowerCase(), contains('double'));

    controller.goToIndex(1);
    expect(controller.pinnedVerb, 'Single');
    expect(controller.selectedVerb, 'Single');
  });

  test('custom verb does not unpin a catalog pin', () {
    final controller = CaptionV2Controller()
      ..imagePaths = ['/one.jpg', '/two.jpg'];

    controller.toggleVerbPin('Celebrates');
    expect(controller.pinnedVerb, 'Celebrates');

    controller.setCustomVerbPhrase('arrives');
    expect(controller.pinnedVerb, 'Celebrates');
    expect(controller.selectedVerb, isNull);
    expect(controller.customVerbPhrase, 'arrives');

    controller.goToIndex(1);
    expect(controller.pinnedVerb, 'Celebrates');
    expect(controller.selectedVerb, 'Celebrates');
    expect(controller.customVerbPhrase, isEmpty);
  });

  test('pinned custom verb survives selecting a catalog verb', () {
    final controller = CaptionV2Controller();

    controller.setCustomVerbPhrase('arrives');
    controller.toggleCustomVerbPin();
    expect(controller.customVerbPinned, isTrue);
    expect(controller.customVerbPhrase, 'arrives');

    controller.selectVerb('Celebrates');
    expect(controller.customVerbPinned, isTrue);
    expect(controller.lastCustomVerbPhrase, 'arrives');
    expect(controller.customVerbPhrase, isEmpty);
    expect(controller.selectedVerb, 'Celebrates');

    controller.imagePaths = ['/one.jpg', '/two.jpg'];
    controller.goToIndex(1);
    expect(controller.customVerbPinned, isTrue);
    expect(controller.customVerbPhrase, 'arrives');
    expect(controller.selectedVerb, isNull);
  });

  test('copy uses the same caption text shown in the strip', () {
    final controller = CaptionV2Controller()
      ..currentIptcMeta = {'IPTC:Description': 'Embedded caption'};

    expect(controller.displayedCaption, 'Embedded caption');

    controller.setManualCaption('Pasted caption');
    expect(controller.displayedCaption, 'Pasted caption');
  });

  test('applies clipboard and previous captions exactly', () async {
    final controller = CaptionV2Controller();
    const payload = CaptionTransferPayload(
      caption: '  Exact edited caption  ',
      personality: 'Player One;Player Two',
      headline: 'Game story',
      keywords: 'baseball, sports',
    );

    await controller.applyTransferredCaption(payload);
    expect(controller.buildCaptionSentence(), '  Exact edited caption  ');
    expect(controller.personality, 'Player One;Player Two');
    expect(controller.headline, 'Game story');
    expect(controller.keywords, 'baseball, sports');

    controller.previousCaption = payload;
    controller.setManualCaption(null);
    expect(await controller.applyPreviousCaption(), isTrue);
    expect(controller.buildCaptionSentence(), '  Exact edited caption  ');
  });

  test('paste keeps the destination photo photographer from IPTC', () async {
    final controller = CaptionV2Controller()..photographerName = 'Jane Doe';
    const payload = CaptionTransferPayload(
      caption: 'Alex Smith scores. (Photo by John Smith/Getty Images)',
      photographerName: 'John Smith',
    );

    await controller.applyTransferredCaption(payload);

    expect(
      controller.buildCaptionSentence(),
      'Alex Smith scores. (Photo by Jane Doe/Getty Images)',
    );
  });

  test('Firebar offers an unmatched phrase as a custom verb', () {
    final controller = CaptionV2Controller()..setSearchOpen(true);

    controller.setSearchQuery('double');
    expect(controller.firebarCustomVerbOffer, isNull);

    controller.setSearchQuery('dances through the rain');
    expect(controller.firebarCustomVerbOffer, 'dances through the rain');
    expect(
        controller.firebarSelectedResult?.verbKey, 'dances through the rain');

    controller.commitSelectedFirebarResult();
    expect(controller.customVerbPhrase, 'dances through the rain');
    expect(controller.searchQuery, isEmpty);
  });

  test('clicking a Firebar name exits and reopening keeps later picks', () {
    final bo = player('Bo Bichette', '11');
    final controller = CaptionV2Controller()
      ..homeRoster = [bo]
      ..setSearchOpen(true);

    controller.commitFirebarResultAndClose(
      FirebarResult.player(player: bo, isHome: true),
    );

    expect(controller.searchOpen, isFalse);
    expect(controller.isPlayerSelected(bo, isHome: true), isTrue);

    controller.selectVerb('Single');
    controller.setSearchOpen(true);

    expect(controller.searchOpen, isTrue);
    expect(controller.selectedVerb, 'Single');
    expect(
      controller.firebarCommitted.map((chip) => chip.kind),
      containsAll([FirebarResultKind.player, FirebarResultKind.verb]),
    );
  });

  test('Firebar marks the caption text it inserted', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees'
      ..setSearchOpen(true);
    controller.selectPlayer(player('Auston Matthews', '34'), isHome: true);
    controller.selectVerb('Single');

    final highlights = controller.firebarInsertedHighlights;
    expect(highlights, isNotEmpty);
    expect(controller.displayedCaption, contains(highlights.first));
    expect(highlights.first.toLowerCase(), contains('matthews'));
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

  test('Firebar two jersey numbers apply both players immediately', () {
    final bo = player('Bo Bichette', '11');
    final vlad = player('Vladimir Guerrero Jr.', '27');
    final controller = CaptionV2Controller()
      ..homeRoster = [bo, vlad]
      ..setSearchOpen(true);

    controller.setSearchQuery('11 27');
    expect(controller.selectedPlayers, hasLength(2));
    expect(
      controller.selectedPlayers.map((row) => row.player.fullName),
      containsAll(['Bo Bichette', 'Vladimir Guerrero Jr.']),
    );
    final caption = controller.displayedCaption.toLowerCase();
    expect(caption, contains('bichette'));
    expect(caption, contains('guerrero'));

    controller.setSearchQuery('11 2');
    expect(controller.selectedPlayers, isEmpty);

    controller.setSearchQuery('11 27');
    controller.commitSelectedFirebarResult();
    expect(controller.selectedPlayers, hasLength(2));
    expect(controller.searchQuery, isEmpty);
  });

  test('Firebar two jerseys plus verb previews Looks On', () {
    final nylander = player('William Nylander', '88');
    final knies = player('Matthew Knies', '92');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Montréal Canadiens'
      ..homeRoster = [nylander, knies]
      ..awayRoster = [player('Away Skater', '12')]
      ..setSearchOpen(true);

    controller.setSearchQuery('88 92 look');

    expect(
      controller.selectedPlayers.map((row) => row.player.fullName),
      containsAll(['William Nylander', 'Matthew Knies']),
    );
    expect(controller.selectedVerb, 'Looks On');
    expect(
      controller.firebarVerbResults.map((result) => result.verbKey),
      contains('Looks On'),
    );
    final caption = controller.displayedCaption.toLowerCase();
    expect(caption, contains('nylander'));
    expect(caption, contains('knies'));
    expect(caption, contains('look'));

    controller.commitSelectedFirebarResult();
    expect(controller.selectedPlayers, hasLength(2));
    expect(controller.selectedVerb, 'Looks On');
    expect(controller.searchQuery, isEmpty);
  });

  test('Firebar jersey+verb query activates player and Looks On', () {
    final nylander = player('William Nylander', '88');
    final controller = CaptionV2Controller()
      ..sport = 'Hockey'
      ..homeRoster = [nylander]
      ..awayRoster = [player('Away Skater', '12')]
      ..setSearchOpen(true);

    controller.setSearchQuery('88 looks');

    expect(controller.firebarHomeResults.single.player, same(nylander));
    expect(controller.firebarAwayResults, isEmpty);
    expect(
      controller.firebarVerbResults.map((result) => result.verbKey),
      contains('Looks On'),
    );
    expect(controller.selectedPlayers.single.player, same(nylander));
    expect(controller.selectedVerb, 'Looks On');

    controller.commitSelectedFirebarResult();
    expect(controller.selectedPlayers.single.player, same(nylander));
    expect(controller.selectedVerb, 'Looks On');
    expect(controller.searchQuery, isEmpty);
    expect(
      controller.firebarCommitted.map((chip) => chip.kind),
      containsAll([FirebarResultKind.player, FirebarResultKind.verb]),
    );
  });

  test('Firebar ambiguous jersey+verb previews highlighted player in caption',
      () {
    final nylander = player('William Nylander', '88');
    final poulin = player('Samuel Poulin', '88');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Montréal Canadiens'
      ..homeRoster = [nylander]
      ..awayRoster = [poulin]
      ..setSearchOpen(true);

    controller.setSearchQuery('88 looks');

    expect(controller.firebarHomeResults.single.player, same(nylander));
    expect(controller.firebarAwayResults.single.player, same(poulin));
    expect(controller.selectedPlayers.single.player, same(nylander));
    expect(controller.selectedVerb, 'Looks On');
    expect(
      controller.displayedCaption.toLowerCase(),
      contains('nylander'),
    );
    expect(
      controller.displayedCaption.toLowerCase(),
      contains('looks'),
    );

    controller.selectFirebarResult(controller.firebarAwayResults.single);
    expect(controller.selectedPlayers.single.player, same(poulin));
    expect(
      controller.displayedCaption.toLowerCase(),
      contains('poulin'),
    );
  });

  test('applyRosterEdits updates team names without restarting session', () {
    final bo = player('Bo Bichette', '11');
    final vlad = player('Vladimir Guerrero Jr.', '27');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'New York Yankees'
      ..homeRoster = [bo]
      ..awayRoster = [vlad]
      ..selectPlayer(bo, isHome: true);

    controller.applyRosterEdits(
      homeTeamName: 'Toronto Blue Jays',
      homePlayers: [bo],
      awayTeamName: 'Boston Red Sox',
      awayPlayers: [vlad],
    );

    expect(controller.homeTeam, 'Toronto Blue Jays');
    expect(controller.awayTeam, 'Boston Red Sox');
    expect(controller.homeAbbr, 'TOR');
    expect(controller.selectedPlayers.single.player, same(bo));
    expect(controller.displayedCaption.toLowerCase(), contains('bichette'));
  });

  test('team titles use three-letter abbreviations', () {
    expect(mlbTeamAbbreviation('Toronto Blue Jays'), 'TOR');
    expect(mlbTeamAbbreviation('Toronto Maple Leafs'), 'TOR');
    expect(mlbTeamAbbreviation('Maple Leafs'), 'TOR');
    expect(mlbTeamAbbreviation('Los Angeles Lakers'), 'LAL');
    expect(mlbTeamAbbreviation('New York Liberty'), 'NYL');
  });

  test('Firebar unique player match applies caption immediately', () {
    final sanchez = player('Jesús Sánchez', '4');
    final forty = player('Kazuma Okamoto', '40');
    final controller = CaptionV2Controller()
      ..homeRoster = [sanchez, forty]
      ..setSearchOpen(true);

    controller.setSearchQuery('4');
    expect(controller.selectedPlayers, isEmpty);

    controller.setSearchQuery('sanchez');
    expect(controller.selectedPlayers.single.player, same(sanchez));
    expect(controller.displayedCaption.toLowerCase(), contains('sanchez'));

    controller.setSearchQuery('4');
    expect(controller.selectedPlayers, isEmpty);

    controller.setSearchQuery('sanchez');
    controller.commitSelectedFirebarResult();
    expect(controller.selectedPlayers.single.player, same(sanchez));
    expect(controller.searchQuery, isEmpty);
  });

  test('Firebar Shift+Enter quick-save commits name matches like jerseys', () {
    final sanchez = player('Jesús Sánchez', '4');
    final forty = player('Kazuma Okamoto', '40');
    final controller = CaptionV2Controller()
      ..homeRoster = [sanchez, forty]
      ..setSearchOpen(true);

    controller.setSearchQuery('4');
    expect(controller.firebarCanQuickSavePlayer, isTrue);
    expect(controller.commitFirebarForShiftEnterSave(), isFalse);
    expect(controller.selectedPlayers.single.player, same(sanchez));
    expect(controller.searchQuery, isEmpty);

    controller.selectedPlayers.clear();
    controller.setSearchOpen(true);
    controller.setSearchQuery('okamoto');
    expect(controller.firebarCanQuickSavePlayer, isTrue);
    expect(controller.firebarSelectedResult?.player, same(forty));
    expect(controller.commitFirebarForShiftEnterSave(), isFalse);
    expect(controller.selectedPlayers.single.player, same(forty));
    expect(controller.searchQuery, isEmpty);

    controller.selectedPlayers.clear();
    controller.setSearchOpen(true);
    controller.setSearchQuery('single');
    expect(controller.firebarCanQuickSavePlayer, isFalse);
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

  test('Firebar finds verbs by phrase, keywords, and modifier labels', () {
    final controller = CaptionV2Controller()..setSearchOpen(true);
    addTearDown(controller.dispose);

    controller.setSearchQuery('hits a');
    expect(
      controller.firebarVerbResults.map((result) => result.verbKey),
      contains('Home Run'),
    );

    controller.setSearchQuery('solo');
    expect(
      controller.firebarVerbResults.map((result) => result.verbKey),
      contains('Home Run'),
    );
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
