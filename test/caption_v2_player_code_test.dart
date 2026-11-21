import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/player_code_key_handler.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  test('shouldCapture allows idle Firebar and blocks busy editable fields', () {
    final handler = PlayerCodeKeyHandler(
      controller: CaptionV2Controller(),
      onSelected: ({required bool isHome}) {},
    );
    addTearDown(handler.dispose);

    expect(
      handler.shouldCapture(
        sessionReady: true,
        sessionLoading: false,
        searchFocused: true,
        searchQuery: '',
        editableFocused: true,
        photoEditing: false,
      ),
      isTrue,
    );
    expect(
      handler.shouldCapture(
        sessionReady: true,
        sessionLoading: false,
        searchFocused: true,
        searchQuery: 'skate',
        editableFocused: true,
        photoEditing: false,
      ),
      isFalse,
    );
    expect(
      handler.shouldCapture(
        sessionReady: true,
        sessionLoading: false,
        searchFocused: false,
        searchQuery: '',
        editableFocused: true,
        photoEditing: false,
      ),
      isFalse,
    );
    expect(
      handler.shouldCapture(
        sessionReady: true,
        sessionLoading: false,
        searchFocused: false,
        searchQuery: '',
        editableFocused: false,
        photoEditing: false,
      ),
      isTrue,
    );
  });

  testWidgets(
    'typing h34 space with Firebar focused selects home #34 via key events',
    (tester) async {
      final home = _player('Auston Matthews', '34');
      final controller = CaptionV2Controller()
        ..sessionReady = true
        ..sessionLoading = false
        ..homeTeam = 'Toronto Maple Leafs'
        ..awayTeam = 'Visitor'
        ..homeRoster = [home, _player('Other', '16')]
        ..awayRoster = [_player('Away Ace', '88')]
        // A photo is "open" for selection purposes without folder polling.
        ..imagePaths = const ['/tmp/frame.jpg']
        ..currentIndex = 0;
      addTearDown(controller.dispose);

      final searchFocus = FocusNode();
      final searchText = TextEditingController();
      late final PlayerCodeKeyHandler codes;
      codes = PlayerCodeKeyHandler(
        controller: controller,
        onSelected: ({required bool isHome}) {},
        onBufferChanged: (_) {},
      );

      bool onKey(KeyEvent event) {
        return codes.handle(
          event,
          sessionReady: controller.sessionReady,
          sessionLoading: controller.sessionLoading,
          searchFocused: searchFocus.hasFocus,
          searchQuery: searchText.text,
          editableFocused: true,
          photoEditing: false,
        );
      }

      HardwareKeyboard.instance.addHandler(onKey);
      addTearDown(() {
        HardwareKeyboard.instance.removeHandler(onKey);
        codes.dispose();
        searchFocus.dispose();
        searchText.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: searchFocus,
              autofocus: true,
              child: Column(
                children: [
                  // Simulates Firebar input without EditableText swallowing keys.
                  Text(
                    searchText.text.isEmpty ? 'firebar-idle' : searchText.text,
                    key: const ValueKey('firebar-input'),
                  ),
                  Text(
                    controller.imagePaths.isEmpty ? 'no-photo' : 'photo-open',
                    key: const ValueKey('photo-status'),
                  ),
                  if (codes.buffer.isNotEmpty)
                    Text(codes.buffer, key: const ValueKey('player-code-box')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('photo-open'), findsOneWidget);
      expect(searchFocus.hasFocus, isTrue);

      // Real HardwareKeyboard path — not selectPlayerByCode / parser.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      expect(codes.buffer, 'h34');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      codes.clear(); // cancel idle timer so the test binding can finish
      await tester.pump();

      expect(controller.selectedPlayers, hasLength(1));
      expect(controller.selectedPlayers.single.player, same(home));
      expect(controller.selectedIsHome, isTrue);
      expect(searchText.text, isEmpty);
    },
  );

  testWidgets(
    'idle Backspace removes last selected player; h99 shows error near badge',
    (tester) async {
      final home = _player('Auston Matthews', '34');
      final away = _player('Visitor Ace', '28');
      final controller = CaptionV2Controller()
        ..sessionReady = true
        ..sessionLoading = false
        ..homeRoster = [home]
        ..awayRoster = [away]
        ..imagePaths = const ['/tmp/frame.jpg'];
      addTearDown(controller.dispose);

      final rootFocus = FocusNode();
      String? error;
      late final PlayerCodeKeyHandler codes;
      codes = PlayerCodeKeyHandler(
        controller: controller,
        onSelected: ({required bool isHome}) {},
        onBufferChanged: (_) {},
        onErrorChanged: (message) => error = message,
      );

      bool onKey(KeyEvent event) {
        return codes.handle(
          event,
          sessionReady: true,
          sessionLoading: false,
          searchFocused: false,
          searchQuery: '',
          editableFocused: false,
          photoEditing: false,
        );
      }

      HardwareKeyboard.instance.addHandler(onKey);
      addTearDown(() {
        HardwareKeyboard.instance.removeHandler(onKey);
        codes.dispose();
        rootFocus.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: rootFocus,
            autofocus: true,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      codes.clear();
      expect(controller.selectedPlayers, hasLength(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.selectedPlayers, hasLength(1));
      expect(controller.selectedPlayers.single.player, same(home));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      codes.clear();
      await tester.pump();
      expect(error, 'No home #99');
      expect(codes.errorMessage, 'No home #99');

      await tester.pump(const Duration(seconds: 2));
      expect(codes.errorMessage, isNull);
    },
  );
}
