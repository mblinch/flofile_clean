import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/caption_v2_shortcuts.dart';

void main() {
  test('maps paste, navigation, and numeric activators', () {
    final shortcuts = buildCaptionV2Shortcuts();

    // ⌘↵ / ⌘S / Shift+Enter / ⌘⇧Enter / ⌘U are hardware chords
    // (captionV2SaveChord), not Shortcuts entries — keeps Firebar Enter free.
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyS, meta: true)],
      isNull,
    );
    expect(
      shortcuts[const SingleActivator(LogicalKeyboardKey.enter, shift: true)],
      isNull,
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

  testWidgets('dispatches configured frame and search-hit actions',
      (tester) async {
    var frameDelta = 0;
    var searchHit = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: buildCaptionV2Shortcuts(),
          child: Actions(
            actions: <Type, Action<Intent>>{
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

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);

    expect(frameDelta, 1);
    expect(searchHit, 4);
  });

  test('save / prev / FTP chords match the action-row hints', () {
    CaptionV2SaveChord chord({
      LogicalKeyboardKey key = LogicalKeyboardKey.enter,
      bool shift = false,
      bool meta = false,
      bool control = false,
      bool alt = false,
      bool ftpMode = true,
    }) {
      return captionV2SaveChord(
        key: key,
        shift: shift,
        meta: meta,
        control: control,
        alt: alt,
        ftpMode: ftpMode,
      );
    }

    // ⌘Enter / Ctrl+Enter → save & next.
    expect(chord(meta: true), CaptionV2SaveChord.save);
    expect(
      chord(key: LogicalKeyboardKey.numpadEnter, meta: true),
      CaptionV2SaveChord.save,
    );
    expect(chord(control: true), CaptionV2SaveChord.save);
    // Shift+Enter always saves; ⌘⇧Enter saves & previous.
    expect(chord(shift: true), CaptionV2SaveChord.save);
    expect(chord(shift: true, meta: true), CaptionV2SaveChord.savePrevious);
    expect(
      chord(key: LogicalKeyboardKey.keyS, meta: true),
      CaptionV2SaveChord.save,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyS, meta: true, shift: true),
      CaptionV2SaveChord.save,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyS, control: true, ftpMode: false),
      CaptionV2SaveChord.save,
    );
    // ⌘U → FTP (or save when FTP mode is off).
    expect(
      chord(key: LogicalKeyboardKey.keyU, meta: true),
      CaptionV2SaveChord.transmit,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyU, control: true),
      CaptionV2SaveChord.transmit,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyU, meta: true, ftpMode: false),
      CaptionV2SaveChord.save,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyB, meta: true),
      CaptionV2SaveChord.burst,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyB, control: true),
      CaptionV2SaveChord.burst,
    );
    expect(
      chord(key: LogicalKeyboardKey.keyB, meta: true, shift: true),
      CaptionV2SaveChord.none,
    );
    expect(chord(), CaptionV2SaveChord.none);
    expect(chord(meta: true, ftpMode: false), CaptionV2SaveChord.save);
    expect(chord(shift: true, ftpMode: false), CaptionV2SaveChord.save);
    expect(
      chord(shift: true, meta: true, ftpMode: false),
      CaptionV2SaveChord.savePrevious,
    );
    expect(chord(meta: true, alt: true), CaptionV2SaveChord.none);
  });

  test('save chord still resolves while editable text would be focused', () {
    // Hardware handler uses captionV2SaveChord so ⌘S works in text fields.
    expect(
      captionV2SaveChord(
        key: LogicalKeyboardKey.keyS,
        shift: false,
        meta: true,
        control: false,
        alt: false,
        ftpMode: true,
      ),
      CaptionV2SaveChord.save,
    );
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
