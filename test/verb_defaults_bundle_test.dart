import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/verb_defaults_bundle.dart';
import 'package:quick_cap/screens/caption_v2/data/effective_verb_catalog.dart';

void main() {
  test('factory bundle marks catalog complete with full verb overrides', () {
    final bundle = VerbDefaultsBundle.buildFactory('baseball');

    expect(VerbDefaultsBundle.isComplete(bundle), isTrue);
    expect(bundle['categoryOrder'], contains('Offense'));
    expect(
      (bundle['verbOverrides'] as Map).keys,
      containsAll(['Single', 'Home Run', 'Steals']),
    );
    expect(
      (bundle['verbOrder'] as Map)['Offense'],
      contains('Home Run'),
    );
  });

  test('ensureComplete fills missing factory verbs without clobbering edits',
      () {
    final partial = {
      'categoryOrder': ['Offense'],
      'verbOrder': {
        'Offense': ['Single'],
      },
      'verbOverrides': {
        'Single': {
          'label': 'Base Hit',
          'category': 'Offense',
          'verbPhrase': 'slaps a single',
        },
      },
      'favoriteVerbs': ['Single'],
      'deletedVerbs': <String>[],
      'customVerbs': <Map<String, dynamic>>[],
    };

    final complete = VerbDefaultsBundle.ensureComplete(partial, 'baseball');

    expect(VerbDefaultsBundle.isComplete(complete), isTrue);
    expect(
      (complete['verbOverrides'] as Map)['Single']['label'],
      'Base Hit',
    );
    expect(
      (complete['verbOverrides'] as Map).keys,
      contains('Home Run'),
    );
    expect(complete['favoriteVerbs'], ['Single']);
  });

  test('complete catalog merge does not reintroduce factory-only verbs', () {
    final catalog = EffectiveVerbCatalog.merge(
      sport: 'baseball',
      categoryOrder: const ['Offense'],
      verbOrder: const {
        'Offense': ['Single'],
      },
      favorites: const {},
      customVerbs: const [],
      customWordings: const {},
      overrides: const {
        'Single': {
          'label': 'Single',
          'category': 'Offense',
          'verbPhrase': 'hits a single',
        },
      },
      deletedVerbs: const {},
      catalogComplete: true,
    );

    expect(catalog.byKey.keys, ['Single']);
    expect(catalog.byKey.containsKey('Home Run'), isFalse);
  });
}
