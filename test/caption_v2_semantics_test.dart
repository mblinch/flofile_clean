import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/widgets/player_row.dart';
import 'package:quick_cap/screens/caption_v2/widgets/transmit_dock.dart';

void main() {
  testWidgets('finds Save & Next and a player button by semantics label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlayerRow(
                  jersey: '34',
                  name: 'Auston Matthews',
                  semanticLabel: 'Home 34 Auston Matthews',
                  selected: false,
                  onTap: () {},
                ),
                CaptionV2ActionRow(
                  onSavePrevious: () {},
                  onCopy: () {},
                  onPaste: () {},
                  onPastePrevious: () {},
                  onSaveNext: () {},
                  onTransmit: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Home 34 Auston Matthews'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Save & Next'), findsOneWidget);

      final playerSemantics = tester.getSemantics(
        find.bySemanticsLabel('Home 34 Auston Matthews'),
      );
      expect(playerSemantics.hasFlag(SemanticsFlag.isButton), isTrue);

      final nextSemantics = tester.getSemantics(
        find.bySemanticsLabel('Save & Next'),
      );
      expect(nextSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
    } finally {
      semantics.dispose();
    }
  });
}
