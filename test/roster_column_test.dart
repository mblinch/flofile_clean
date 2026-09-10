import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/layout/roster_column.dart';
import 'package:quick_cap/screens/caption_v2/layout/verbs_column.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  testWidgets('player wheel is available alongside the classic roster',
      (tester) async {
    final second = _player('Second Player', '22');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home Team'
      ..homeRoster = [
        _player('First Player', '11'),
        second,
        _player('Third Player', '33'),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: RosterColumn(
              controller: controller,
              isHome: true,
              focused: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byKey(const ValueKey('player-wheel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('roster-wheel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('player-wheel')), findsOneWidget);

    final wheelCenter =
        tester.getCenter(find.byKey(const ValueKey('player-wheel')));
    final mouse = await tester.startGesture(
      wheelCenter,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, -20));
    await tester.pump();
    await mouse.moveBy(const Offset(0, -60));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(controller.isPlayerSelected(second, isHome: true), isFalse);

    await tester.tap(find.text('Second Player'));
    await tester.pumpAndSettle();

    expect(controller.isPlayerSelected(second, isHome: true), isTrue);

    await tester.tap(find.byKey(const ValueKey('roster-wheel')));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byKey(const ValueKey('player-wheel')), findsNothing);
  });

  testWidgets('verb wheel is available alongside category view',
      (tester) async {
    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: VerbsColumn(
              controller: controller,
              focused: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('verb-wheel-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('verb-wheel')), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('verb-wheel'))),
    );
    await tester.pumpAndSettle();

    expect(controller.selectedVerb, isNotNull);

    await tester.tap(find.byKey(const ValueKey('verb-wheel-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('verb-wheel')), findsNothing);
  });

  testWidgets('desktop classic verbs use a persistent category rail',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 620,
            child: VerbsColumn(
              controller: controller,
              focused: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final categories = controller.verbCategories;
    expect(categories.length, greaterThan(1));
    expect(
      find.byKey(ValueKey('verb-rail-${categories.first}')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('verb-wheel')), findsNothing);

    await tester.tap(find.byKey(ValueKey('verb-rail-${categories[1]}')));
    await tester.pumpAndSettle();
    expect(controller.verbCategory, categories[1]);
    expect(
      find.byKey(ValueKey('verb-rail-${categories.first}')),
      findsOneWidget,
    );
  });

  testWidgets('Firebar filters existing columns and keeps rows clickable',
      (tester) async {
    final player = _player('Visible Player', '27');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home Team'
      ..homeRoster = [player]
      ..setSearchOpen(true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 840,
            height: 500,
            child: Row(
              children: [
                Expanded(
                  child: RosterColumn(
                    controller: controller,
                    isHome: true,
                    focused: false,
                  ),
                ),
                Expanded(
                  child: VerbsColumn(
                    controller: controller,
                    focused: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Visible Player'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byKey(const ValueKey('roster-wheel')), findsNothing);
    expect(
      find.byKey(const ValueKey('firebar-verb-reference')),
      findsOneWidget,
    );

    await tester.tap(find.text('Visible Player'));
    await tester.pump();

    expect(controller.isPlayerSelected(player, isHome: true), isTrue);
  });

  testWidgets('roster header search ranks best matches first', (tester) async {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..homeRoster = [
        _player('Marcus Stroman', '6'),
        _player('Austin Martin', '2'),
        _player('Justin Martinez', '99'),
        _player('George Springer', '4'),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: RosterColumn(
              controller: controller,
              isHome: true,
              focused: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('TOR'), findsOneWidget);

    final ranked = controller.filterAndRankPlayers(
      controller.homeRoster,
      'mar',
    );
    expect(
      ranked.map((player) => player.fullName).toList(),
      [
        'Austin Martin',
        'Justin Martinez',
        'Marcus Stroman',
      ],
    );

    await tester.enterText(find.byType(TextField), 'mar');
    await tester.pumpAndSettle();

    expect(find.text('George Springer'), findsNothing);
    expect(find.text('Austin Martin'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Austin Martin')).dy,
      lessThan(tester.getTopLeft(find.text('Marcus Stroman')).dy),
    );
  });

  test('roster sort field and direction are independent', () {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..homeRoster = [
        _player('George Springer', '4'),
        _player('Bo Bichette', '11'),
        _player('Vladimir Guerrero Jr.', '27'),
      ];
    addTearDown(controller.dispose);

    expect(controller.rosterSort, RosterSortMode.number);
    expect(controller.rosterSortAscending, isTrue);
    expect(controller.rosterSortFieldLabel(), '#');
    expect(controller.rosterSortDirectionLabel(), '↑');
    expect(controller.homeRoster.first.jerseyNumber, '4');

    controller.toggleRosterSortDirection();
    expect(controller.rosterSort, RosterSortMode.number);
    expect(controller.rosterSortAscending, isFalse);
    expect(controller.rosterSortLabel(), '#↓');
    expect(controller.homeRoster.first.jerseyNumber, '27');

    controller.cycleRosterSortField();
    expect(controller.rosterSort, RosterSortMode.firstName);
    expect(controller.rosterSortAscending, isFalse);
    expect(controller.rosterSortFieldLabel(), 'First');
    expect(controller.homeRoster.first.fullName, 'Vladimir Guerrero Jr.');

    controller.toggleRosterSortDirection();
    expect(controller.rosterSortAscending, isTrue);
    expect(controller.rosterSortLabel(), 'First↑');
    expect(controller.homeRoster.first.fullName, 'Bo Bichette');
    expect(controller.playerListName(controller.homeRoster.first),
        'Bo Bichette');

    controller.cycleRosterSortField();
    expect(controller.rosterSort, RosterSortMode.lastName);
    expect(controller.rosterSortAscending, isTrue);
    expect(controller.rosterSortLabel(), 'Last↑');
    expect(controller.homeRoster.first.fullName, 'Bo Bichette');
    expect(
      controller.playerListName(controller.homeRoster.first),
      'Bichette, Bo',
    );

    controller.cycleRosterSortField();
    expect(controller.rosterSort, RosterSortMode.number);
    expect(controller.rosterSortAscending, isTrue);
    expect(controller.rosterSortLabel(), '#↑');
  });

  testWidgets('Firebar removes nonmatches and preserves lane width',
      (tester) async {
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home Team'
      ..awayTeam = 'Away Team'
      ..homeRoster = [
        _player('Myles Straw', '3'),
        _player('Other Player', '22'),
      ]
      ..awayRoster = [_player('No Result Here', '1')]
      ..setSearchOpen(true)
      ..setSearchQuery('st');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 360,
            child: Row(
              children: [
                Expanded(
                  child: RosterColumn(
                    controller: controller,
                    isHome: true,
                    focused: false,
                  ),
                ),
                Expanded(
                  child: VerbsColumn(
                    controller: controller,
                    focused: false,
                  ),
                ),
                Expanded(
                  child: RosterColumn(
                    controller: controller,
                    isHome: false,
                    focused: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Myles Straw'), findsOneWidget);
    expect(find.text('Other Player'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('No match'), findsOneWidget);
  });
}
