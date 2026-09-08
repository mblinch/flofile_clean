import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/caption_v2_shortcuts.dart';

void main() {
  test('maps save, transmit, paste, navigation, and numeric activators', () {
    final shortcuts = buildCaptionV2Shortcuts();

    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyS, meta: true)],
      isA<SaveNextIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyS, control: true)],
      isA<SaveNextIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.enter, shift: true)],
      isA<SaveNextIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(
        LogicalKeyboardKey.enter,
        meta: true,
        shift: true,
      )],
      isA<SaveTransmitNextIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      )],
      isA<PastePreviousIntent>(),
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
      isA<NavigateFrameIntent>().having((intent) => intent.delta, 'delta', 1),
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.tab, shift: true)],
      isA<CycleColumnIntent>().having((intent) => intent.delta, 'delta', -1),
    );
    expect(
      shortcuts.values.whereType<SearchHitIntent>().map((i) => i.digit).toSet(),
      {1, 2, 3, 4, 5, 6, 7, 8, 9},
    );
    expect(
      shortcuts.values.whereType<ShiftNumberIntent>().map((i) => i.number),
      containsAll(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );
    expect(
      shortcuts.values.whereType<JerseyDigitIntent>(),
      contains(
        isA<JerseyDigitIntent>()
            .having((intent) => intent.digit, 'digit', 2)
            .having((intent) => intent.isHome, 'isHome', isTrue),
      ),
    );
    expect(
      shortcuts.values.whereType<JerseyDigitIntent>(),
      contains(
        isA<JerseyDigitIntent>()
            .having((intent) => intent.digit, 'digit', 2)
            .having((intent) => intent.isHome, 'isHome', isFalse),
      ),
    );
  });

  testWidgets('dispatches configured save and frame actions', (tester) async {
    var saves = 0;
    var frameDelta = 0;
    var searchHit = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: buildCaptionV2Shortcuts(),
          child: Actions(
            actions: <Type, Action<Intent>>{
              SaveNextIntent: CaptionV2GuardedAction<SaveNextIntent>(
                onInvoke: (_) {
                  saves++;
                  return null;
                },
              ),
              NavigateFrameIntent: CaptionV2GuardedAction<NavigateFrameIntent>(
                onInvoke: (intent) {
                  frameDelta += intent.delta;
                  return null;
                },
              ),
              SearchHitIntent: CaptionV2GuardedAction<SearchHitIntent>(
                onInvoke: (intent) {
                  searchHit = intent.digit;
                  return null;
                },
              ),
            },
            child: const Focus(
              autofocus: true,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);

    expect(saves, 1);
    expect(frameDelta, 1);
    expect(searchHit, 4);
  });

  testWidgets('editable text suppresses global printable and arrow actions',
      (tester) async {
    var searchHits = 0;
    var frameMoves = 0;
    final text = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: buildCaptionV2Shortcuts(),
          child: Actions(
            actions: <Type, Action<Intent>>{
              SearchHitIntent: CaptionV2GuardedAction<SearchHitIntent>(
                onInvoke: (_) {
                  searchHits++;
                  return null;
                },
              ),
              NavigateFrameIntent: CaptionV2GuardedAction<NavigateFrameIntent>(
                onInvoke: (_) {
                  frameMoves++;
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: TextField(
                controller: text,
                autofocus: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(captionV2FocusIsEditable(), isTrue);
    final guarded = CaptionV2GuardedAction<SearchHitIntent>(
      onInvoke: (_) => null,
    );
    expect(guarded.isEnabled(const SearchHitIntent(1)), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

    expect(text.text, isEmpty);
    expect(searchHits, 0);
    expect(frameMoves, 0);
  });
}
