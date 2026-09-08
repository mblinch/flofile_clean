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
    expect(catalog.verbsByCategory['Offense']!.map((v) => v.key),
        containsAllInOrder(['Home Run', 'My Play', 'Single']));
    expect(catalog.verbsByCategory['Defense']!.map((v) => v.key),
        contains('Double'));
    expect(catalog.byKey, isNot(contains('Triple')));
    expect(catalog.byKey['Single']!.label, 'Base Hit');
    expect(catalog.byKey['Single']!.singularPhrase, 'slaps a single');
    expect(catalog.byKey['My Play']!.isCustom, isTrue);
    expect(catalog.byKey['My Play']!.keywords, contains('special'));
    expect(catalog.verbsByCategory['Favorites']!.map((v) => v.key),
        containsAll(['Single', 'My Play']));
  });

  test('falls back to complete sport factory catalog', () {
    final catalog = EffectiveVerbCatalog.factory('hockey');

    expect(catalog.categoryOrder, containsAll(['Offense', 'Goalie']));
    expect(catalog.byKey['Skates']!.singularPhrase, isNotEmpty);
    expect(catalog.verbsByCategory['Offense']!.map((v) => v.key),
        contains('Shoots'));
  });
}
