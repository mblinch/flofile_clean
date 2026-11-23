import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/firebar_shorthand.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _p(String name, String number) {
  final parts = name.split(' ');
  return Player(
    fullName: name,
    firstName: parts.first,
    jerseyNumber: number,
    displayName: '$name #$number',
  );
}

FirebarShorthand _nhlOttTor() {
  return FirebarShorthand(
    homeRoster: [
      _p('Auston Matthews', '34'),
      _p('William Nylander', '88'),
      _p('John Tavares', '91'),
      _p('Mitch Marner', '16'),
      _p('Home Eight', '8'),
      _p('Home Eighty One', '81'),
      _p('Home Eighty Two', '82'),
    ],
    awayRoster: [
      _p('Claude Giroux', '28'),
      _p('Linus Ullmark', '35'),
      _p('Stephen Halliday', '34'),
      _p('Brady Tkachuk', '7'),
    ],
    verbs: const [
      FirebarVerbCatalogEntry(
        key: 'Faceoff',
        label: 'Faceoff',
        matchTexts: ['Faceoff', 'takes a faceoff', 'faceoff', 'fa'],
      ),
      FirebarVerbCatalogEntry(
        key: 'Fights',
        label: 'Fights',
        matchTexts: ['Fights', 'fights', 'fight'],
      ),
      FirebarVerbCatalogEntry(
        key: 'Celebrates a Goal',
        label: 'Celebrates a Goal',
        matchTexts: [
          'Celebrates a Goal',
          'celebrates a goal',
          'celebrate',
          'ce',
        ],
      ),
      FirebarVerbCatalogEntry(
        key: 'Makes a Save',
        label: 'Makes a Save',
        matchTexts: ['Makes a Save', 'makes a save', 'save', 'sav'],
      ),
    ],
    homeAbbrev: 'TOR',
    awayAbbrev: 'OTT',
    playerLastName: (p) {
      final parts = p.fullName.split(' ');
      return parts.length <= 1 ? p.fullName : parts.last;
    },
  );
}

void main() {
  late FirebarShorthand fb;

  setUp(() {
    fb = _nhlOttTor();
  });

  test('h3 no complete; h34 → Matthews', () {
    final open = fb.parse('h3');
    expect(open.tokens.single.completed, isFalse);
    expect(open.tokens.single.display, 'h3');

    final done = fb.parse('h34');
    expect(done.tokens.single.completed, isTrue);
    expect(
      done.tokens.single.display.replaceAll('\u00A0', ' '),
      'Auston Matthews',
    );
    expect(done.tokens.single.resolved?.player?.fullName, 'Auston Matthews');
  });

  test('h8 no complete; h8 space → #8', () {
    final open = fb.parse('h8');
    expect(open.tokens.single.completed, isFalse);

    final done = fb.parse('h8 ');
    expect(done.tokens.single.completed, isTrue);
    expect(done.tokens.single.resolved?.player?.jerseyNumber, '8');
  });

  test('f no complete; fa → Faceoff; face → Faceoff', () {
    expect(fb.parse('f').tokens.single.completed, isFalse);

    final fa = fb.parse('fa');
    expect(fa.tokens.single.completed, isTrue);
    expect(fa.tokens.single.display, 'Faceoff');

    final face = fb.parse('face');
    expect(face.tokens.single.completed, isTrue);
    expect(face.tokens.single.display, 'Faceoff');
    expect(face.preview.subjects, isEmpty);
    expect(face.preview.action?.verbKey, 'Faceoff');
  });

  test('c no complete; ce → Celebrates a Goal', () {
    expect(fb.parse('c').tokens.single.completed, isFalse);
    final ce = fb.parse('ce');
    expect(ce.tokens.single.completed, isTrue);
    expect(
      ce.tokens.single.display.replaceAll('\u00A0', ' '),
      'Celebrates a Goal',
    );
  });

  test('matt no complete; matth → Matthews', () {
    expect(fb.parse('matt').tokens.single.completed, isFalse);
    final matth = fb.parse('matth');
    expect(matth.tokens.single.completed, isTrue);
    expect(matth.tokens.single.display, 'Matthews');
  });

  test('facx → red', () {
    final prior = fb.parse('fa');
    final bad = fb.parse('facx', prior: prior.tokens);
    expect(bad.tokens.single.error, isTrue);
    expect(bad.preview.canApply, isFalse);
  });

  test('h34 fa v28 → Matthews, Faceoff, Giroux opponent', () {
    var line = fb.parse('h34');
    line = fb.parse('Auston Matthews fa', prior: line.tokens);
    line = fb.parse(
      'Auston Matthews Faceoff v28',
      prior: line.tokens,
    );
    // Direct full line also works:
    final direct = fb.parse('h34 fa v28');
    // After auto-complete cascade via single parse of raw typed form:
    final typed = fb.parse('h34 fa v28');
    expect(typed.tokens.length, 3);
    expect(typed.preview.subjects.single.player?.fullName, 'Auston Matthews');
    expect(typed.preview.action?.verbKey, 'Faceoff');
    expect(typed.preview.opponents.single.player?.fullName, 'Claude Giroux');
    expect(direct.preview.canApply, isTrue);
  });

  test('h34 h88 ce → two subjects', () {
    final line = fb.parse('h34 h88 ce');
    expect(line.preview.subjects.length, 2);
    expect(line.preview.subjects[0].player?.fullName, 'Auston Matthews');
    expect(line.preview.subjects[1].player?.fullName, 'William Nylander');
    expect(line.preview.action?.verbKey, 'Celebrates a Goal');
  });

  test('34 + pick v34 → v34 with trailing space', () {
    final open = fb.parse('34');
    expect(open.activeMatches.length, greaterThanOrEqualTo(2));
    final v34 = open.activeMatches.firstWhere((m) => m.isHome == false);
    final picked = fb.pickMatch(open, v34);
    expect(picked.tokens.single.display, 'v34');
    expect(picked.trailingSpace, isTrue);
    expect(picked.displayLine.endsWith(' '), isTrue);
    expect(picked.tokens.single.resolved?.player?.fullName, 'Stephen Halliday');
  });

  test('34 fa + finalize with two #34s stays ambiguous for H/V prompt', () {
    final line = fb.parse('34 fa', finalizeOpenNumber: true);
    expect(line.preview.canApply, isFalse);
    expect(line.preview.errorReason, isNull);
    expect(line.preview.errorTokenIndex, isNotNull);
    expect(line.tokens.first.matches.length, greaterThanOrEqualTo(2));
    expect(
      line.tokens.first.matches.any((m) => m.isHome == true),
      isTrue,
    );
    expect(
      line.tokens.first.matches.any((m) => m.isHome == false),
      isTrue,
    );
  });

  test('unique bare number converts on Return', () {
    final line = fb.parse('28', finalizeOpenNumber: true);
    expect(line.preview.canApply, isTrue);
    expect(line.tokens.single.resolved?.player?.fullName, 'Claude Giroux');
  });

  test('h99 fa → red, nothing applied', () {
    final line = fb.parse('h99 fa', finalizeOpenNumber: true);
    expect(line.preview.canApply, isFalse);
    expect(line.preview.errorReason, contains('no player'));
  });

  test('trailing stray letter after Faceoff is dropped, never adds a player',
      () {
    final fa = fb.parse('fa');
    final synced = fb.parse(fa.displayLine, prior: fa.tokens);
    final bad = fb.parse('${synced.displayLine}x', prior: synced.tokens);
    expect(bad.tokens.length, 1);
    expect(bad.tokens.single.error, isFalse);
    expect(bad.tokens.single.completed, isTrue);
    expect(bad.tokens.single.display, 'Faceoff');
    expect(bad.preview.subjects, isEmpty);
    expect(bad.preview.action?.verbKey, 'Faceoff');
  });

  test('Faceoffe after auto-expand snaps back to Faceoff', () {
    final fa = fb.parse('fa');
    final synced = fb.parse(fa.displayLine, prior: fa.tokens);
    final extra = fb.parse('${synced.displayLine}e', prior: synced.tokens);
    expect(extra.tokens.single.display, 'Faceoff');
    expect(extra.tokens.single.completed, isTrue);
    expect(extra.tokens.single.error, isFalse);
    expect(extra.displayLine, 'Faceoff');
  });

  test('Nick Paul fa does not duplicate Paul', () {
    final local = FirebarShorthand(
      homeRoster: [_p('Nick Paul', '13'), _p('Auston Matthews', '34')],
      awayRoster: const [],
      verbs: const [
        FirebarVerbCatalogEntry(
          key: 'Faceoff',
          label: 'Faceoff',
          matchTexts: ['Faceoff', 'faceoff', 'fa'],
        ),
      ],
      homeAbbrev: 'TOR',
      awayAbbrev: 'OTT',
    );
    final line = local.parse('Nick Paul fa');
    expect(
      line.tokens.map((t) => t.display.replaceAll('\u00A0', ' ')).toList(),
      ['Nick Paul', 'Faceoff'],
    );
    expect(line.preview.subjects.single.player?.fullName, 'Nick Paul');
    expect(line.preview.action?.verbKey, 'Faceoff');
  });

  test('v35 sav → Ullmark Makes a Save', () {
    final line = fb.parse('v35 sav');
    expect(line.preview.subjects.single.player?.fullName, 'Linus Ullmark');
    expect(line.preview.action?.verbKey, 'Makes a Save');
  });

  test('excluded players are omitted from name and jersey matches', () {
    final matthews = FirebarMatch.player(
      player: fb.homeRoster.firstWhere((p) => p.fullName == 'Auston Matthews'),
      isHome: true,
    );
    final blocked = FirebarShorthand(
      homeRoster: fb.homeRoster,
      awayRoster: fb.awayRoster,
      verbs: fb.verbs,
      homeAbbrev: fb.homeAbbrev,
      awayAbbrev: fb.awayAbbrev,
      playerLastName: fb.playerLastName,
      excludedPlayerKeys: {matthews.key},
    );

    final byName = blocked.parse('matth');
    expect(
      byName.tokens.single.matches
          .map((m) => m.player?.fullName)
          .contains('Auston Matthews'),
      isFalse,
    );

    final byJersey = blocked.parse('h34');
    expect(byJersey.tokens.single.matches, isEmpty);
    expect(byJersey.tokens.single.error, isTrue);

    // Same jersey on the other team stays available.
    final shared = blocked.parse('34');
    expect(
      shared.tokens.single.matches.map((m) => m.player?.fullName),
      contains('Stephen Halliday'),
    );
    expect(
      shared.tokens.single.matches.map((m) => m.player?.fullName),
      isNot(contains('Auston Matthews')),
    );
  });

  test('same player cannot resolve twice on one line', () {
    final line = fb.parse('Matthews fights Matthews');
    final players = line.tokens
        .where((t) => t.resolved?.kind == FirebarMatchKind.player)
        .map((t) => t.resolved!.player?.fullName)
        .toList();
    expect(players.where((n) => n == 'Auston Matthews').length, 1);
  });
}
