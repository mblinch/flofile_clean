import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_caption_domain.dart';

void main() {
  test('withOpponent uses against by default', () {
    expect(
      CaptionV2CaptionDomain.withOpponent(
        verb: 'Scores',
        action: 'scores',
        opponentTeam: 'Montreal Canadiens',
      ),
      'scores against the Montreal Canadiens',
    );
  });

  test('withOpponent follows the joiner box exactly', () {
    expect(
      CaptionV2CaptionDomain.withOpponent(
        verb: 'Celebrates',
        action: 'celebrates',
        opponentTeam: 'New York Yankees',
        opponentJoiner: 'after defeating',
      ),
      'celebrates after defeating the New York Yankees',
    );
  });

  test('empty joiner means no connector word', () {
    expect(
      CaptionV2CaptionDomain.withOpponent(
        verb: 'Scores',
        action: 'scores',
        opponentTeam: 'Montreal Canadiens',
        opponentJoiner: '',
      ),
      'scores the Montreal Canadiens',
    );
  });

  test('special verbs keep their connector even with a custom joiner', () {
    expect(
      CaptionV2CaptionDomain.withOpponent(
        verb: 'Hit by Pitch',
        action: 'is hit by a pitch',
        opponentTeam: 'Yankees',
        opposingPlayers: 'Gerrit Cole #45 of the Yankees',
        opponentJoiner: 'after defeating',
      ),
      'is hit by a pitch by Gerrit Cole #45 of the Yankees',
    );
  });
}
