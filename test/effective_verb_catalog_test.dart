import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/effective_verb_catalog.dart';

void main() {
  test('merges ordering, favorites, overrides, customs, moves, and deletes',
      () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'baseball',
      categoryOrder: const ['Pitching', 'Offense', 'Defense'],
      verbOrder: const {
        'Offense': ['Home Run', 'My Play', 'Single'],
        'Defense': ['Double'],
      },
      favorites: const {'Single', 'My Play'},
      customVerbs: const [
        {
          'label': 'My Play',
          'verbPhrase': 'makes my play',
          'pluralPhrase': 'make my play',
          'category': 'Offense',
          'keywords': ['special'],
        },
      ],
      customWordings: const {'Single': 'slaps a single'},
      overrides: const {
        'Single': {
          'label': 'Base Hit',
          'verbPhrase': 'slaps a single',
          'pluralPhrase': 'slap singles',
          'category': 'Offense',
        },
        'Double': {'category': 'Defense'},
      },
      deletedVerbs: const {'Triple'},
    );

    expect(catalog.categoryOrder.first, 'Favorites');
    expect(
        catalog.categoryOrder, containsAll(['Pitching', 'Offense', 'Defense']));
    expect(
      catalog.verbsByCategory['Favorites']!.map((v) => v.key),
      containsAll(['Single', 'My Play']),
    );
    expect(catalog.verbsByCategory['Offense']!.map((v) => v.key),
        containsAllInOrder(['Home Run', 'My Play', 'Single']));
    expect(catalog.verbsByCategory['Defense']!.map((v) => v.key),
        contains('Double'));
    expect(catalog.byKey, isNot(contains('Triple')));
    expect(catalog.byKey['Single']!.label, 'Base Hit');
    expect(catalog.byKey['Single']!.singularPhrase, 'slaps a single');
    expect(catalog.byKey['Single']!.category, 'Offense');
    expect(catalog.byKey['My Play']!.isCustom, isTrue);
    expect(catalog.byKey['My Play']!.keywords, contains('special'));
    expect(catalog.favoriteKeys, containsAll(['Single', 'My Play']));
    expect(catalog.byKey['Single']!.isFavorite, isTrue);
  });

  test('Runs stays in Favorites when saved under a different name', () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'baseball',
      categoryOrder: const ['Running', 'Offense'],
      verbOrder: const {
        'Favorites': ['Runs'],
        'Running': ['Steals', 'Slides', 'Rounds'],
      },
      favorites: const {'runs', 'run to a base'},
      customVerbs: const [],
      customWordings: const {},
      overrides: const {},
      deletedVerbs: const {},
      catalogComplete: true,
    );

    expect(
      catalog.verbsByCategory['Favorites']!.map((verb) => verb.key),
      ['Runs'],
    );
    expect(catalog.byKey['Runs']!.isFavorite, isTrue);
    expect(
      catalog.verbsByCategory['Running']!.map((verb) => verb.key),
      contains('Runs'),
    );
  });

  test('falls back to complete sport factory catalog', () {
    final catalog = EffectiveVerbCatalog.factory('hockey');

    expect(catalog.categoryOrder.first, 'Favorites');
    expect(catalog.categoryOrder, containsAll(['Offense', 'Goalie']));
    expect(catalog.verbsByCategory['Favorites'], isEmpty);
    expect(catalog.byKey['Skates']!.singularPhrase, isNotEmpty);
    expect(catalog.verbsByCategory['Offense']!.map((v) => v.key),
        contains('Shoots'));
  });
}
