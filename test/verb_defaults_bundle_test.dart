import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/verb_defaults_bundle.dart';

void main() {
  test('detects hockey catalog collapsed into Offense', () {
    final poisoned = <String, dynamic>{
      'verbOverrides': {
        for (final key in [
          'battles against',
          'defends',
          'guards the net',
          'makes a save',
          'blocks a shot',
          'clears the puck',
          'Skates',
          'Checks',
        ])
          key: {
            'label': key,
            'category': 'Offense',
            'verbPhrase': key,
          },
      },
    };

    expect(
      VerbDefaultsBundle.looksCollapsedIntoOneCategory(poisoned, 'hockey'),
      isTrue,
    );

    final fixed =
        VerbDefaultsBundle.ensureComplete(poisoned, 'hockey');
    expect(fixed['catalogComplete'], isTrue);

    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    expect(overrides['Defends']?['category'], 'Defense');
    expect(overrides['Guards the Net']?['category'], 'Goalie');
    expect(overrides['Battles']?['category'], 'Offense');
    expect(overrides.containsKey('battles against'), isFalse);
  });

  test('drops hockey phrase-alias overrides that dump into Offense', () {
    final mixed = <String, dynamic>{
      'catalogComplete': true,
      'verbOverrides': {
        'Battles': {
          'label': 'Battles',
          'category': 'Offense',
          'verbPhrase': 'battles',
        },
        'battles against': {
          'label': 'Battles',
          'category': 'Offense',
          'verbPhrase': 'battles',
        },
        'Defends': {
          'label': 'Defends',
          'category': 'Defense',
          'verbPhrase': 'defends',
        },
        'makes a save': {
          'label': 'Saves',
          'category': 'Offense',
          'verbPhrase': 'makes a save',
        },
        'reacts with dejection': {
          'label': 'Reacts',
          'category': 'Offense',
          'verbPhrase': 'reacts with dejection',
        },
        'Celebrates': {
          'label': 'Celebrates',
          'category': 'Reactions',
          'verbPhrase': 'celebrates',
        },
      },
      'verbOrder': {
        'Offense': ['Battles', 'battles against', 'reacts with dejection'],
        'Defense': ['Defends'],
        'Reactions': ['Celebrates'],
      },
    };

    final fixed = VerbDefaultsBundle.ensureComplete(mixed, 'hockey');
    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    expect(overrides.containsKey('battles against'), isFalse);
    expect(overrides.containsKey('reacts with dejection'), isFalse);
    expect(overrides.containsKey('makes a save'), isFalse);
    expect(overrides['Saves']?['category'], 'Goalie');
    expect(overrides['Dejection']?['category'], 'Non Game-Action');

    final offense = List<String>.from(
      (fixed['verbOrder'] as Map)['Offense'] as List,
    );
    expect(offense, isNot(contains('battles against')));
    expect(offense, isNot(contains('reacts with dejection')));
    expect(offense, contains('Battles'));
  });

  test('keeps intentional categoryOverrides for factory verbs', () {
    final moved = <String, dynamic>{
      'catalogComplete': true,
      'verbOverrides': {
        'Handles the Puck': {
          'label': 'Handles the Puck',
          'category': 'Offense',
          'verbPhrase': 'handles the puck',
        },
      },
      'categoryOverrides': {
        'Handles the Puck': 'Offense',
      },
      'categoryOrder': ['Offense', 'Defense', 'Goalie', 'Non Game-Action'],
      'verbOrder': {
        'Offense': ['Handles the Puck'],
        'Goalie': ['Saves'],
      },
    };

    final fixed = VerbDefaultsBundle.ensureComplete(moved, 'hockey');
    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    expect(overrides['Handles the Puck']?['category'], 'Offense');
    final pins = Map<String, dynamic>.from(
      (fixed['categoryOverrides'] as Map?) ?? const {},
    );
    expect(pins['Handles the Puck'], 'Offense');
    final order = Map<String, List<dynamic>>.from(
      (fixed['verbOrder'] as Map).map(
        (key, value) =>
            MapEntry(key.toString(), List<dynamic>.from(value as List)),
      ),
    );
    expect(order['Offense'], contains('Handles the Puck'));
    expect(order['Goalie'] ?? const [], isNot(contains('Handles the Puck')));
  });

  test('heals misfiled hockey factory verbs into factory categories', () {
    final misfiled = <String, dynamic>{
      'catalogComplete': true,
      'verbOverrides': {
        'Celebrates': {
          'label': 'Celebrates',
          'category': 'Offense',
          'verbPhrase': 'celebrates',
        },
        'Celebrates a Goal': {
          'label': 'Celebrates a Goal',
          'category': 'Offense',
          'verbPhrase': 'celebrates a goal',
        },
        'Defends': {
          'label': 'Defends',
          'category': 'Offense',
          'verbPhrase': 'defends',
        },
        'Saves': {
          'label': 'Saves',
          'category': 'Offense',
          'verbPhrase': 'makes a save',
        },
        'Skates': {
          'label': 'Skates',
          'category': 'Offense',
          'verbPhrase': 'skates',
        },
        'Post Game Win': {
          'label': 'Post Game Win',
          'category': 'Non Game-Action',
          'verbPhrase': 'celebrates',
        },
      },
      'categoryOrder': ['Offense', 'Defense', 'Goalie', 'Non Game-Action'],
      'verbOrder': {
        'Offense': [
          'Celebrates',
          'Celebrates a Goal',
          'Defends',
          'Saves',
          'Skates',
        ],
        'Non Game-Action': ['Post Game Win'],
      },
    };

    final fixed = VerbDefaultsBundle.ensureComplete(misfiled, 'hockey');
    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    // Generic Celebrates is no longer a hockey factory verb.
    expect(overrides.containsKey('Celebrates'), isFalse);
    expect(overrides['Celebrates a Goal']?['category'], 'Non Game-Action');
    expect(overrides['Post Game Win']?['category'], 'Non Game-Action');
    expect(overrides['Defends']?['category'], 'Defense');
    expect(overrides['Saves']?['category'], 'Goalie');
    expect(overrides['Skates']?['category'], 'Offense');

    final order = Map<String, List<dynamic>>.from(
      (fixed['verbOrder'] as Map).map(
        (key, value) => MapEntry(key.toString(), List<dynamic>.from(value as List)),
      ),
    );
    expect(order.containsKey('Reactions'), isFalse);
    expect(
      order['Non Game-Action'],
      containsAll(['Celebrates a Goal', 'Post Game Win']),
    );
    expect(order['Defense'], contains('Defends'));
    expect(order['Goalie'], contains('Saves'));
  });

  test('heals poisoned wantsOpponent when joiner text remains', () {
    final poisoned = <String, dynamic>{
      'catalogComplete': true,
      'verbOverrides': {
        'Stands in Net': {
          'label': 'Stands in Net',
          'category': 'Goalie',
          'verbPhrase': 'stands in net',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
        },
        'Walks to the Ice': {
          'label': 'Walks to the Ice',
          'category': 'Non Game-Action',
          'verbPhrase': 'walks to the ice',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
        },
        'Post Game Win': {
          'label': 'Post Game Win',
          'category': 'Reactions',
          'verbPhrase': 'celebrates',
          'wantsOpponent': false,
          'omitAgainst': false,
          'opponentJoiner': 'against',
        },
      },
    };

    final fixed = VerbDefaultsBundle.ensureComplete(poisoned, 'hockey');
    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    expect(overrides['Stands in Net']?['wantsOpponent'], isTrue);
    expect(overrides['Walks to the Ice']?['wantsOpponent'], isTrue);
    expect(overrides['Post Game Win']?['wantsOpponent'], isFalse);
  });

  test('renames legacy Pitching verb to Pitches and migrates hide list', () {
    final legacy = <String, dynamic>{
      'verbOverrides': {
        'Pitching': {
          'label': 'Pitching',
          'category': 'Pitching',
          'verbPhrase': 'delivers a pitch',
          'keywords': ['pitch'],
        },
      },
      'deletedVerbs': ['Pitching'],
      'verbOrder': {
        'Pitching': ['Pitching', 'Pitching Change', 'Mound Visit'],
      },
    };

    final fixed = VerbDefaultsBundle.ensureComplete(legacy, 'baseball');
    final overrides = Map<String, dynamic>.from(fixed['verbOverrides'] as Map);
    expect(overrides.containsKey('Pitches'), isTrue);
    expect(overrides.containsKey('Pitching'), isFalse);
    expect(overrides['Pitches']?['category'], 'Pitching');
    expect(
      List<String>.from(overrides['Pitches']?['keywords'] as List),
      contains('pitches'),
    );
    expect(
      List<String>.from(fixed['deletedVerbs'] as List),
      contains('Pitches'),
    );
    expect(
      List<String>.from(fixed['deletedVerbs'] as List),
      isNot(contains('Pitching')),
    );
  });
}
