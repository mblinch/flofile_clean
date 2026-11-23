import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/layout/caption_v2_search.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  testWidgets('Return applies the shorthand line and replaces selection',
      (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final giroux = _player('Claude Giroux', '28');
    final controller = CaptionV2Controller()
      ..sport = 'hockey'
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Ottawa Senators'
      ..homeRoster = [matthews, _player('William Nylander', '88')]
      ..awayRoster = [giroux]
      ..setSearchOpen(true);
    // Seed a prior click selection that Return must replace.
    controller.selectPlayer(matthews, isHome: true);
    expect(controller.selectedPlayers, hasLength(1));

    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 120,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    // Players only — no sport verb catalog required for this apply path.
    controller.setSearchQuery('h34 v28');
    await tester.pump();
    textController.value = TextEditingValue(
      text: controller.searchQuery,
      selection: TextSelection.collapsed(offset: controller.searchQuery.length),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.selectedPlayers, hasLength(2));
    expect(controller.selectedPlayers.first.player.fullName, 'Auston Matthews');
    expect(controller.selectedPlayers.last.player.fullName, 'Claude Giroux');
  });

  testWidgets('first completed player starts the caption like a roster click',
      (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final controller = CaptionV2Controller()
      ..homeRoster = [matthews]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 120,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    controller.setSearchQuery('h3');
    await tester.pump();
    expect(controller.isPlayerSelected(matthews, isHome: true), isFalse);

    controller.setSearchQuery('h34');
    await tester.pump();
    expect(controller.isPlayerSelected(matthews, isHome: true), isTrue);
    expect(controller.firebarCommitted, hasLength(1));
    expect(controller.firebarCommitted.single.player?.fullName, 'Auston Matthews');
    expect(controller.searchQuery, isEmpty);
  });

  testWidgets('Space on shared jersey # opens H/V prompt in the Firebar',
      (tester) async {
    final home = _player('Auston Matthews', '34');
    final away = _player('Stephen Halliday', '34');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Ottawa Senators'
      ..homeRoster = [home]
      ..awayRoster = [away]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 120,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    controller.setSearchQuery('34 ');
    await tester.pump();

    expect(controller.firebarJerseySideChoiceOpen, isTrue);
    expect(controller.firebarOptionPrompt, 'Which #34?');
    expect(find.text('Which #34?'), findsOneWidget);
    expect(find.textContaining('Auston Matthews'), findsWidgets);
    expect(find.textContaining('Stephen Halliday'), findsWidgets);

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    // Ambiguous teardown may remount the field; focus restores over frames.
    await tester.pump();
    await tester.pump();

    expect(controller.firebarJerseySideChoiceOpen, isFalse);
    expect(controller.searchOpen, isTrue);
    expect(controller.searchQuery, isEmpty);
    expect(
      controller.firebarCommitted.single.player?.fullName,
      'Stephen Halliday',
    );
    expect(controller.isPlayerSelected(away, isHome: false), isTrue);
    expect(focusNode.hasFocus, isTrue);
    final input = find.byKey(const ValueKey('firebar-input'));
    expect(input, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: input, matching: find.byType(TextField)),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.enabled, isTrue);
    expect(field.showCursor, isTrue);
  });

  testWidgets('Space on shared jersey opens H/V instead of committing menu',
      (tester) async {
    final home = _player('Auston Matthews', '34');
    final away = _player('Stephen Halliday', '34');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Ottawa Senators'
      ..homeRoster = [home]
      ..awayRoster = [away]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            // Tall enough for the bar + suggestion list before Space opens H/V.
            height: 220,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.setSearchQuery('34');
    await tester.pump();
    textController.value = TextEditingValue(
      text: controller.searchQuery,
      selection: TextSelection.collapsed(offset: controller.searchQuery.length),
    );
    expect(controller.firebarSpaceOpensJerseySide, isTrue);
    expect(controller.firebarMenuOpen, isTrue);
    expect(controller.firebarJerseySideChoiceOpen, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();

    expect(controller.firebarJerseySideChoiceOpen, isTrue);
    expect(controller.firebarOptionPrompt, 'Which #34?');
    expect(find.text('Which #34?'), findsOneWidget);
    expect(controller.firebarCommitted, isEmpty);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('Tab commitFirebarMenu keeps Firebar input focused',
      (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final controller = CaptionV2Controller()
      ..homeRoster = [matthews]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 180,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.setSearchQuery('matt');
    await tester.pump();
    textController.value = TextEditingValue(
      text: controller.searchQuery,
      selection: TextSelection.collapsed(offset: controller.searchQuery.length),
    );
    expect(controller.firebarMenuOpen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();

    expect(controller.searchOpen, isTrue);
    expect(controller.firebarCommitted, isNotEmpty);
    expect(focusNode.hasFocus, isTrue);
    final input = find.byKey(const ValueKey('firebar-input'));
    expect(input, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: input, matching: find.byType(TextField)),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.enabled, isTrue);
    expect(field.showCursor, isTrue);
  });

  testWidgets('Enter on shared jersey # opens H/V prompt in the Firebar',
      (tester) async {
    final home = _player('Auston Matthews', '34');
    final away = _player('Stephen Halliday', '34');
    final controller = CaptionV2Controller()
      ..homeTeam = 'Toronto Maple Leafs'
      ..awayTeam = 'Ottawa Senators'
      ..homeRoster = [home]
      ..awayRoster = [away]
      ..setSearchOpen(true);
    addTearDown(controller.dispose);

    controller.setSearchQuery('34');
    expect(controller.firebarJerseySideChoiceOpen, isFalse);
    expect(controller.firebarOptions, isEmpty);

    final applied = controller.applyFirebarLine();
    expect(applied, isFalse);
    expect(controller.firebarJerseySideChoiceOpen, isTrue);
    expect(
      controller.firebarOptions.map((o) => o.label).toList(),
      ['H - Auston Matthews', 'V - Stephen Halliday'],
    );

    controller.chooseFirebarJerseySide(isHome: true);
    expect(controller.isPlayerSelected(home, isHome: true), isTrue);
  });

  testWidgets('Backspace deletes a completed Firebar entry', (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final controller = CaptionV2Controller()
      ..homeRoster = [matthews]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 120,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.setSearchQuery('h34');
    await tester.pump();
    expect(controller.isPlayerSelected(matthews, isHome: true), isTrue);
    expect(controller.firebarCommitted, hasLength(1));
    expect(controller.searchQuery, isEmpty);

    // Empty field + Backspace removes the last confirmed chip.
    textController.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.firebarCommitted, isEmpty);
    expect(controller.searchQuery, isEmpty);
    expect(controller.isPlayerSelected(matthews, isHome: true), isFalse);
  });

  testWidgets('Esc exits without changing selection', (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final controller = CaptionV2Controller()
      ..homeRoster = [matthews]
      ..setSearchOpen(true);
    controller.selectPlayer(matthews, isHome: true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 120,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CaptionV2SearchBar(
                controller: controller,
                focusNode: focusNode,
                textController: textController,
                onActivate: () => controller.setSearchOpen(true),
                onExit: () => controller.setSearchOpen(false),
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.setSearchQuery('h34');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.searchOpen, isFalse);
    expect(controller.isPlayerSelected(matthews, isHome: true), isTrue);
  });

  testWidgets('Firebar suggestions overlay without growing layout height',
      (tester) async {
    final matthews = _player('Auston Matthews', '34');
    final marner = _player('Mitch Marner', '16');
    final controller = CaptionV2Controller()
      ..homeRoster = [matthews, marner]
      ..setSearchOpen(true);
    final focusNode = FocusNode();
    final textController = TextEditingController();
    addTearDown(focusNode.dispose);
    addTearDown(textController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 400,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CaptionV2SearchBar(
                    controller: controller,
                    focusNode: focusNode,
                    textController: textController,
                    onActivate: () => controller.setSearchOpen(true),
                    onExit: () => controller.setSearchOpen(false),
                  ),
                  const ColoredBox(
                    key: Key('board_marker'),
                    color: Color(0xFF112233),
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    final boardBefore =
        tester.getTopLeft(find.byKey(const Key('board_marker')));

    controller.setSearchQuery('ma');
    await tester.pump();
    textController.value = TextEditingValue(
      text: controller.searchQuery,
      selection: TextSelection.collapsed(offset: controller.searchQuery.length),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.firebarMenuOpen, isTrue);
    expect(controller.firebarMenuResults.length, greaterThan(1));
    expect(find.byKey(const Key('firebar_suggestions_overlay')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('board_marker'))),
      boardBefore,
    );
    expect(find.textContaining('Auston Matthews'), findsWidgets);
  });
}
