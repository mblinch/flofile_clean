import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/layout/duplicate_jersey_dialog.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  test('groups only shared jersey numbers', () {
    final guerrero = _player('Vladimir Guerrero', '27');
    final springer = _player('George Springer', '4');
    final bichette = _player('Bo Bichette', '27');

    final groups = duplicateJerseyGroups([guerrero, springer, bichette]);

    expect(groups, hasLength(1));
    expect(groups.single, [guerrero, bichette]);
  });

  test('keeps every player on a number or only the chosen one', () {
    final guerrero = _player('Vladimir Guerrero', '27');
    final springer = _player('George Springer', '4');
    final bichette = _player('Bo Bichette', '27');
    final roster = [guerrero, springer, bichette];

    expect(
      applyDuplicateJerseyChoices(roster, {'27': null}),
      roster,
    );
    expect(
      applyDuplicateJerseyChoices(roster, {'27': bichette}),
      [springer, bichette],
    );
  });
}
