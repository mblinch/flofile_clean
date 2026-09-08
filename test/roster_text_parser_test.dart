import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/roster_text_parser.dart';

void main() {
  const parser = RosterTextParser();

  test('parses ESPN roster text and ignores page furniture', () {
    const text = '''
Toronto Blue Jays Roster

Pitchers
Name\tPOS\tBAT\tTHW\tAge\tHT\tWT\tBirth Place
https://a.espncdn.com/i/headshots/mlb/players/full/4726080.png
Spencer Arrighetti45\tSP\tR\tR\t26\t6' 2"\t186 lbs\tAlbuquerque, NM
https://a.espncdn.com/i/headshots/mlb/players/full/35002.png
Vladimir Guerrero Jr.27\t1B\tR\tR\t27\t6' 0"\t245 lbs\tMontreal, Canada
https://a.espncdn.com/i/headshots/mlb/players/full/37729.png
Andres Gimenez0\tSS\tL\tR\t28\t5' 11"\t161 lbs\tBarquisimeto, Venezuela
''';

    final result = parser.parse(text, sport: 'baseball');
    final players = result.players(result.detectedNameOrder);

    expect(result.detectedNameOrder, RosterNameOrder.firstLast);
    expect(players, hasLength(3));
    expect(players.first.fullName, 'Spencer Arrighetti');
    expect(players.first.firstName, 'Spencer');
    expect(players.first.jerseyNumber, '45');
    expect(players.first.position, 'Pitcher');
    expect(players.first.playerId, '4726080');
    expect(players[1].fullName, 'Vladimir Guerrero Jr.');
    expect(players[1].jerseyNumber, '27');
    expect(players[1].position, 'First Baseman');
    expect(players[2].jerseyNumber, '0');
    expect(players[2].position, 'Shortstop');
  });

  test('normalizes baseball pitcher and fielding positions', () {
    const text = '''
Starter One12\tSP
Reliever Two34\tRP
Catcher Three7\tC
Center Four9\tCF
Hitter Five22\tDH
First Six1\tFirst Base
Second Seven2\tSecond Base
Third Eight3\tThird Base
''';

    final players = parser
        .parse(text, sport: 'baseball')
        .players(RosterNameOrder.firstLast);

    expect(
      players.map((player) => player.position),
      [
        'Pitcher',
        'Pitcher',
        'Catcher',
        'Center Fielder',
        'Designated Hitter',
        'First Baseman',
        'Second Baseman',
        'Third Baseman',
      ],
    );
  });

  test('detects comma-separated last-name-first entries', () {
    const text = '''
Arrighetti, Spencer45\tSP
Guerrero Jr., Vladimir27\t1B
''';

    final result = parser.parse(text);
    final players = result.players(result.detectedNameOrder);

    expect(result.detectedNameOrder, RosterNameOrder.lastFirst);
    expect(players.first.fullName, 'Spencer Arrighetti');
    expect(players.last.fullName, 'Vladimir Guerrero Jr.');
  });

  test('can reinterpret space-separated names as last name first', () {
    final result = parser.parse('Arrighetti Spencer45\tSP');
    final players = result.players(RosterNameOrder.lastFirst);

    expect(players.single.fullName, 'Spencer Arrighetti');
  });
}
