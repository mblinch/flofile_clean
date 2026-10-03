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
