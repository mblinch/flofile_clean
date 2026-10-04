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

  test('Hallway custom verb writes against in pregame fold', () async {
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
      ..awayTeam = 'Ottawa Senators'
      ..captionTemplate = CaptionTemplate.getty().copyWith(
        gameIdentifierText: 'in their NHL game',
      );
    await controller.reloadVerbCatalog();

    controller.selectPlayer(player('Sergei Bobrovsky', '72'), isHome: true);
    controller.selectVerb('Hallway');
    controller.setPre(true);

    final body = controller.buildCaptionBody();
    expect(body, contains('walks the hallway tunnel against the Ottawa Senators'));
    expect(
      controller.buildCaptionSentence(),
      contains('ahead of their NHL game'),
    );
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
