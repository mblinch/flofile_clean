import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/layout/verb_accordion.dart';

void main() {
  test('All hides verbs already open in another category', () {
    final hidden = verbKeysAlreadyShownOutsideAll(
      openCategories: {'Offense', 'All'},
      keysByCategory: {
        'Offense': ['Scores a Goal'],
        'Defense': ['Makes a Save'],
        'All': ['Scores a Goal', 'Makes a Save'],
      },
    );

    expect(hidden, {'Scores a Goal'});
  });

  test('All keeps the full list when it is the only open category', () {
    final hidden = verbKeysAlreadyShownOutsideAll(
      openCategories: {'All'},
      keysByCategory: {
        'Offense': ['Scores a Goal'],
        'All': ['Scores a Goal'],
      },
    );

    expect(hidden, isEmpty);
  });

  test('closed categories do not hide their verbs from All', () {
    final hidden = verbKeysAlreadyShownOutsideAll(
      openCategories: {'All', 'Defense'},
      keysByCategory: {
        'Offense': ['Scores a Goal'],
        'Defense': ['Makes a Save'],
        'All': ['Scores a Goal', 'Makes a Save'],
      },
    );

    expect(hidden, {'Makes a Save'});
  });
}
