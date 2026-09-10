import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/layout/desktop_drum_picker.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  testWidgets('scroll mode hovers, magnifies, and commits player rows',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final second = _player('Second Player', '22');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Home Team'
      ..awayTeam = 'Away Team'
      ..homeRoster = [
        _player('First Player', '11'),
        second,
        _player('Third Player', '33'),
      ]
      ..awayRoster = [
        _player('Away First', '1'),
        _player('Away Second', '2'),
      ];
    addTearDown(controller.dispose);
    var exited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              onExit: () => exited = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-drum-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-scroll-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('scroll-list-verbs')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('scroll-away-player-0')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.isPlayerSelected(controller.awayRoster.first, isHome: false),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('scroll-home-player-0')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.isPlayerSelected(second, isHome: true), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.isPlayerSelected(second, isHome: true), isTrue);

    final thirdCenter = tester.getCenter(find.text('Third Player'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: thirdCenter);
    await tester.pump();
    await mouse.down(thirdCenter);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(
      controller.isPlayerSelected(controller.homeRoster[2], isHome: true),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(exited, isTrue);
  });

  testWidgets('verb accordion scopes the list and keyboard enter commits',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller()
      ..homeRoster = [_player('Home Player', '1')]
      ..awayRoster = [_player('Away Player', '2')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offense'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Defense'), findsOneWidget);
    expect(find.text('Non-game'), findsOneWidget);
    expect(find.text('Reactions'), findsOneWidget);
    expect(find.text('Pitching'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('verb-accordion-Offense')))
          .height,
      34,
    );
    final offenseVerb = controller.verbDefinitionsByCategory['Offense']!.first;
    await tester.tap(
      find.byKey(const ValueKey('verb-accordion-Offense')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('verb-accordion-row-${offenseVerb.key}')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('verb-accordion-Offense')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('verb-accordion-row-${offenseVerb.key}')),
      findsOneWidget,
    );

    final categories = controller.verbCategories
        .where(
          (category) =>
              category != 'Favorites' &&
              (controller.verbDefinitionsByCategory[category] ?? const [])
                  .isNotEmpty,
        )
        .toList();
    expect(categories.length, greaterThan(1));
    const nextCategory = 'Running';

    await tester.tap(
      find.byKey(const ValueKey('verb-accordion-Running')),
    );
    await tester.pumpAndSettle();
    expect(controller.verbCategory, nextCategory);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(controller.verbCategory, 'Offense');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.verbCategory, nextCategory);

    final firstVerb = controller.verbDefinitionsByCategory[nextCategory]!.first;
    await tester.tap(
      find.byKey(ValueKey('verb-accordion-row-${firstVerb.key}')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedVerb, firstVerb.key);
    expect(
      tester
          .getSize(
            find.byKey(ValueKey('verb-accordion-row-${firstVerb.key}')),
          )
          .height,
      20,
    );

    await tester.tap(
      find.byKey(ValueKey('verb-accordion-row-${firstVerb.key}')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedVerb, isNull);

    await tester.tap(
      find.byKey(ValueKey('verb-accordion-row-${firstVerb.key}')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedVerb, firstVerb.key);
    expect(
      controller.verbDefinitionsByCategory[nextCategory]!
          .map((verb) => verb.key),
      contains(controller.selectedVerb),
    );
  });

  testWidgets('scroll mode uses a compact standard roster list',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller()
      ..homeRoster = [
        for (var index = 0; index < 30; index++)
          _player('Player ${index + 1}', '${index + 1}'),
      ]
      ..awayRoster = [_player('Away Player', '1')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('scroll-list-home'));
    expect(listFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('drum-home')), findsNothing);
    final list = tester.widget<ListView>(listFinder);
    expect(list.itemExtent, 20);
  });

  testWidgets('home surname index filters the left roster', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller()
      ..homeRoster = [
        _player('Adam Baker', '1'),
        _player('Chris Jones', '2'),
        _player('Drew Smith', '3'),
      ]
      ..awayRoster = [
        _player('Away Player', '4'),
        _player('Away Zebra', '5'),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('drum-index-B')));
    await tester.pumpAndSettle();
    expect(find.text('Adam Baker'), findsOneWidget);
    expect(find.text('Chris Jones'), findsNothing);
    expect(find.text('Drew Smith'), findsNothing);
    expect(
      find.byKey(const ValueKey('player-filter-back')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('player-filter-back')));
    await tester.pumpAndSettle();
    expect(find.text('Chris Jones'), findsOneWidget);
    expect(find.text('Drew Smith'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drum-index-P')));
    await tester.pumpAndSettle();
    expect(find.text('Away Player'), findsOneWidget);
    expect(find.text('Away Zebra'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player-filter-back')));
    await tester.pumpAndSettle();
    expect(find.text('Away Zebra'), findsOneWidget);
  });

  testWidgets('drum mode uses a verb list with side categories',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller()
      ..homeRoster = [_player('Home Player', '1')]
      ..awayRoster = [_player('Away Player', '2')];
    addTearDown(controller.dispose);
    final firstVerb = controller.verbDefinitionsByCategory.values
        .expand((verbs) => verbs)
        .first;
    final running = controller.verbDefinitionsByCategory['Running']!.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              mode: DrumPickerMode.infinite,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('verb-side-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-gate-verbs')), findsNothing);
    expect(find.text(firstVerb.label), findsWidgets);
    expect(find.byKey(const ValueKey('verb-drum-index-Running')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('verb-drum-index-Running')));
    await tester.pumpAndSettle();
    expect(find.text(running.label), findsWidgets);
    expect(find.text(firstVerb.label), findsNothing);

    await tester.tap(find.byKey(ValueKey('verb-accordion-row-${running.key}')));
    await tester.pumpAndSettle();

    expect(controller.selectedVerb, running.key);
  });

  testWidgets('drum mode keeps a finite list with hard ends', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lastPlayer = _player('Last Player', '2');
    final firstPlayer = _player('First Player', '1');
    final controller = CaptionV2Controller()
      ..homeRoster = [
        firstPlayer,
        lastPlayer,
      ]
      ..awayRoster = [_player('Away Player', '3')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              mode: DrumPickerMode.infinite,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First Player'), findsOneWidget);
    expect(find.text('Last Player'), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-home-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-home-row-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-home-loop--1')), findsNothing);
    expect(find.byKey(const ValueKey('drum-gate-home')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drum-target-home')));
    await tester.pumpAndSettle();

    expect(controller.isPlayerSelected(lastPlayer, isHome: true), isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drum-home-row-1')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    // Extra downs stay on the last item — no wrap.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drum-target-home')));
    await tester.pumpAndSettle();

    expect(controller.isPlayerSelected(firstPlayer, isHome: true), isTrue);
  });

  testWidgets('default view search ranks matches and sort cycles',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Blue Jays'
      ..awayTeam = 'Away Team'
      ..homeRoster = [
        _player('Marcus Stroman', '6'),
        _player('Austin Martin', '2'),
        _player('Justin Martinez', '99'),
        _player('George Springer', '4'),
      ]
      ..awayRoster = [_player('Away Player', '1')];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 620,
            child: DesktopDrumPicker(
              controller: controller,
              onExit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drum-search-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-sort-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('drum-sort-dir-home')), findsOneWidget);
    expect(find.text('#'), findsWidgets);
    expect(find.text('↑'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('drum-search-home')),
      'mar',
    );
    await tester.pumpAndSettle();

    expect(find.text('George Springer'), findsNothing);
    expect(find.text('Austin Martin'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Austin Martin')).dy,
      lessThan(tester.getTopLeft(find.text('Marcus Stroman')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('drum-sort-dir-home')));
    await tester.pumpAndSettle();
    expect(controller.rosterSort, RosterSortMode.number);
    expect(controller.rosterSortAscending, isFalse);
    expect(find.text('↓'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('drum-sort-home')));
    await tester.pumpAndSettle();
    expect(controller.rosterSort, RosterSortMode.firstName);
    expect(controller.rosterSortAscending, isFalse);
    expect(find.text('First'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('drum-sort-dir-home')));
    await tester.pumpAndSettle();
    expect(controller.rosterSortAscending, isTrue);

    await tester.tap(find.byKey(const ValueKey('drum-sort-home')));
    await tester.pumpAndSettle();
    expect(controller.rosterSort, RosterSortMode.lastName);
    expect(controller.rosterSortAscending, isTrue);
    expect(find.text('Martin, Austin'), findsOneWidget);
  });
}
