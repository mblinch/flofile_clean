import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/data/effective_verb_catalog.dart';
import 'package:quick_cap/services/mlb_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Player player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Hallway Pre + team only uses before the game against', () async {
    SharedPreferences.setMockInitialValues({
      'custom_verbs_hockey': jsonEncode([
        {
          'key': 'Hallway',
          'label': 'Hallway',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks the hallway tunnel',
          'pluralPhrase': 'walk the hallway tunnel',
          'wantsOpponent': true,
          'omitAgainst': false,
          'opponentJoiner': 'against',
          'isCustom': true,
        },
      ]),
      'verb_catalog_complete_hockey': true,
      'current_sport': 'hockey',
    });

    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    controller
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..captionTemplate = CaptionTemplate.applyGameIdentifierText(
        CaptionTemplate.getty(),
        'in their NHL game',
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectVerb('Hallway');
    controller.setPre(true);

    final body = controller.buildCaptionBody();
    expect(
      body,
      contains(
        'walks the hallway tunnel before the game against the Utah Mammoth',
      ),
    );
    expect(body, isNot(contains('against the Utah Mammoth before the game')));
    expect(
      'before the game'.allMatches(body).length,
      1,
      reason: 'must not stack a second before the game after the opponent',
    );
    expect(
      controller.buildCaptionSentence(),
      contains('before the game against the Utah Mammoth'),
    );
    expect(
      controller.buildCaptionSentence(),
      contains('in their NHL game'),
    );
  });

  test('Hallway Post + team only uses after the game against', () async {
    SharedPreferences.setMockInitialValues({
      'custom_verbs_hockey': jsonEncode([
        {
          'key': 'Hallway',
          'label': 'Hallway',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks the hallway tunnel',
          'pluralPhrase': 'walk the hallway tunnel',
          'wantsOpponent': true,
          'omitAgainst': false,
          'opponentJoiner': 'against',
          'isCustom': true,
        },
      ]),
      'verb_catalog_complete_hockey': true,
      'current_sport': 'hockey',
    });

    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    controller
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..captionTemplate = CaptionTemplate.applyGameIdentifierText(
        CaptionTemplate.getty(),
        'in their NHL game',
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectVerb('Hallway');
    controller.setPost(true);

    final body = controller.buildCaptionBody();
    expect(
      body,
      contains(
        'walks the hallway tunnel after the game against the Utah Mammoth',
      ),
    );
    expect(body, isNot(contains('against the Utah Mammoth after the game')));
    expect(body, isNot(contains('following the game')));
    expect(
      'after the game'.allMatches(body).length,
      1,
      reason: 'must not stack a second after the game after the opponent',
    );
    expect(
      controller.buildCaptionSentence(),
      contains('after the game against the Utah Mammoth'),
    );
    expect(
      controller.buildCaptionSentence(),
      contains('in their NHL game'),
    );
  });

  test('Hallway Pre + opposing player skips against', () async {
    SharedPreferences.setMockInitialValues({
      'custom_verbs_hockey': jsonEncode([
        {
          'key': 'Hallway',
          'label': 'Hallway',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks the hallway tunnel',
          'pluralPhrase': 'walk the hallway tunnel',
          'wantsOpponent': true,
          'omitAgainst': false,
          'opponentJoiner': 'before playing',
          'isCustom': true,
        },
      ]),
      'verb_catalog_complete_hockey': true,
      'current_sport': 'hockey',
    });

    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    controller
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: '',
        freeTextSnippets: const [''],
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectPlayer(player('Dylan Guenther', '11'), isHome: false);
    controller.selectVerb('Hallway');
    controller.setPre(true);

    final body = controller.buildCaptionBody();
    expect(
      body,
      contains(
        'Sergei Bobrovsky #72 of the Toronto Maple Leafs and '
        'Dylan Guenther #11 of the Utah Mammoth',
      ),
    );
    expect(body, contains('walks the hallway tunnel before the game'));
    expect(body, isNot(contains('against')));
    expect(body, isNot(contains('before the game against')));
    expect(body, isNot(contains('before playing')));
    expect('before the game'.allMatches(body).length, 1);
  });

  test('Hallway Post + opposing player skips against', () async {
    SharedPreferences.setMockInitialValues({
      'custom_verbs_hockey': jsonEncode([
        {
          'key': 'Hallway',
          'label': 'Hallway',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks the hallway tunnel',
          'pluralPhrase': 'walk the hallway tunnel',
          'wantsOpponent': true,
          'omitAgainst': false,
          'opponentJoiner': 'after defeating',
          'isCustom': true,
        },
      ]),
      'verb_catalog_complete_hockey': true,
      'current_sport': 'hockey',
    });

    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    controller
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: '',
        freeTextSnippets: const [''],
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectPlayer(player('Dylan Guenther', '11'), isHome: false);
    controller.selectVerb('Hallway');
    controller.setPost(true);

    final body = controller.buildCaptionBody();
    expect(
      body,
      contains(
        'Sergei Bobrovsky #72 of the Toronto Maple Leafs and '
        'Dylan Guenther #11 of the Utah Mammoth',
      ),
    );
    expect(body, contains('walks the hallway tunnel after the game'));
    expect(body, isNot(contains('against')));
    expect(body, isNot(contains('after the game against')));
    expect(body, isNot(contains('after defeating')));
    expect(body, isNot(contains('following the game')));
    expect('after the game'.allMatches(body).length, 1);
  });

  test('non-empty opponentJoiner implies wantsOpponent', () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'hockey',
      categoryOrder: const ['Goalie', 'Non Game-Action'],
      verbOrder: const {},
      favorites: const {},
      customVerbs: const [
        {
          'key': 'Hallway',
          'label': 'Hallway',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks the hallway tunnel',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
          'isCustom': true,
        },
      ],
      customWordings: const {},
      overrides: const {
        'Stands in Net': {
          'key': 'Stands in Net',
          'label': 'Stands in Net',
          'category': 'Goalie',
          'verbPhrase': 'stands in net',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
        },
      },
      deletedVerbs: const {},
      catalogComplete: true,
    );

    expect(catalog.byKey['Hallway']?.wantsOpponent, isTrue);
    expect(catalog.byKey['Hallway']?.opponentJoiner, 'against');
    expect(catalog.byKey['Stands in Net']?.wantsOpponent, isTrue);
    expect(catalog.byKey['Stands in Net']?.opponentJoiner, 'against');
  });

  test('blank opponentJoiner still names the other team', () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'hockey',
      categoryOrder: const ['Offense'],
      verbOrder: const {},
      favorites: const {},
      customVerbs: const [],
      customWordings: const {},
      overrides: const {
        'Skates': {
          'key': 'Skates',
          'label': 'Skates',
          'category': 'Offense',
          'verbPhrase': 'skates',
          'wantsOpponent': false,
          'omitAgainst': true,
          'opponentJoiner': '',
        },
      },
      deletedVerbs: const {},
      catalogComplete: true,
    );

    expect(catalog.byKey['Skates']?.wantsOpponent, isTrue);
    expect(catalog.byKey['Skates']?.opponentJoiner, isEmpty);
  });

  test('pre with no opponent keeps before the game alone', () {
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..singleTeamMode = true
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: '',
        freeTextSnippets: const [''],
      );

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectVerb('Skates');
    controller.setPre(true);

    final body = controller.buildCaptionBody();
    expect(body, contains('before the game'));
    expect(body, isNot(contains('against')));
    expect(body, isNot(contains('Utah Mammoth')));
  });

  test('post with no opponent keeps after the game alone', () {
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Utah Mammoth'
      ..singleTeamMode = true
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: '',
        freeTextSnippets: const [''],
      );

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectVerb('Skates');
    controller.setPost(true);

    final body = controller.buildCaptionBody();
    expect(body, contains('after the game'));
    expect(body, isNot(contains('following the game')));
    expect(body, isNot(contains('against')));
    expect(body, isNot(contains('Utah Mammoth')));
  });

  test('Stands in Net caption includes against the other team', () async {
    SharedPreferences.setMockInitialValues({
      'verb_overrides_hockey': jsonEncode({
        'Stands in Net': {
          'key': 'Stands in Net',
          'label': 'Stands in Net',
          'category': 'Goalie',
          'verbPhrase': 'stands in net',
          'pluralPhrase': 'stand in net',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
        },
      }),
      'verb_catalog_complete_hockey': true,
      'current_sport': 'hockey',
    });

    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    controller
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Ottawa Senators'
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: 'in their NHL game',
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Anthony Stolarz', '41'), isHome: true);
    controller.selectVerb('Stands in Net');

    final body = controller.buildCaptionBody();
    expect(body, contains('stands in net against the Ottawa Senators'));
  });
}
