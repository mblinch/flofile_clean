import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/layout/duplicate_jersey_dialog.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number, {String? playerId}) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
      playerId: playerId,
    );

void main() {
  test('groups only shared jersey numbers', () {
    final guerrero = _player('Vladimir Guerrero', '27', playerId: '1');
    final springer = _player('George Springer', '4', playerId: '2');
    final bichette = _player('Bo Bichette', '27', playerId: '3');

    final groups = duplicateJerseyGroups([guerrero, springer, bichette]);

    expect(groups, hasLength(1));
    expect(groups.single, [guerrero, bichette]);
  });

  test('applies session jersey edits without dropping players', () {
    final guerrero = _player('Vladimir Guerrero', '27', playerId: '1');
    final springer = _player('George Springer', '4', playerId: '2');
    final bichette = _player('Bo Bichette', '27', playerId: '3');
    final roster = [guerrero, springer, bichette];

    final next = applySessionJerseyEdits(roster, {
      'id:1': '27',
      'id:3': '11',
    });

    expect(next, hasLength(3));
    expect(next[0].jerseyNumber, '27');
    expect(next[0].displayName, 'Vladimir Guerrero #27');
    expect(next[1].jerseyNumber, '4');
    expect(next[2].jerseyNumber, '11');
    expect(next[2].displayName, 'Bo Bichette #11');
  });
}
