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
  testWidgets('Firebar commits the selected row as an inline chip',
      (tester) async {
    final first = _player('Home Player', '27');
    final controller = CaptionV2Controller()
      ..homeRoster = [first, _player('Second Player', '28')]
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
            height: 80,
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue);
    expect(controller.isPlayerSelected(first, isHome: true), isTrue);
    expect(find.text('Home Player'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(controller.searchQuery, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.selectedPlayers, isEmpty);
  });
}
