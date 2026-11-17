import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/widgets/caption_strip.dart';
import 'package:quick_cap/theme/ff_tokens.dart';

/// Marker below the caption strip — its Y must not move when caption grows.
class _BelowMarker extends StatelessWidget {
  const _BelowMarker({required this.keyRef});

  final GlobalKey keyRef;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: keyRef,
      height: 40,
      child: const Center(child: Text('Save & Next')),
    );
  }
}

Widget _harness({
  required String caption,
  required GlobalKey belowKey,
}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(
      extensions: <ThemeExtension<dynamic>>[FfTokens.dark],
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CaptionStrip(
                leading: '',
                chips: const [],
                trailing: '',
                fullCaption: caption,
                captionHint: 'No caption embedded in image.',
                onCaptionChanged: (_) {},
              ),
              _BelowMarker(keyRef: belowKey),
              const SizedBox(
                height: 80,
                child: Center(child: Text('Verb list')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Save & Next stays put for 1-line and 4-line captions',
    (tester) async {
      final belowKey = GlobalKey();
      const oneLine =
          'TORONTO, ON - NOVEMBER 10: Auston Matthews #34 of the Toronto Maple Leafs.';
      const fourLines =
          'TORONTO, ON - NOVEMBER 10: Auston Matthews #34 of the Toronto Maple Leafs '
          'skates with the puck against Nathan MacKinnon #29 of the Colorado Avalanche '
          'during the third period at Scotiabank Arena on November 10, 2026 in Toronto, '
          'Ontario, Canada. (Photo by Mark Blinch/Getty Images)';

      await tester.pumpWidget(_harness(caption: oneLine, belowKey: belowKey));
      await tester.pumpAndSettle();
      final shortY = tester.getTopLeft(find.byKey(belowKey)).dy;
      final shortHeight = tester.getSize(find.byType(CaptionStrip)).height;

      await tester.pumpWidget(_harness(caption: fourLines, belowKey: belowKey));
      await tester.pumpAndSettle();
      final longY = tester.getTopLeft(find.byKey(belowKey)).dy;
      final longHeight = tester.getSize(find.byType(CaptionStrip)).height;

      expect(
        shortHeight,
        longHeight,
        reason: 'CaptionStrip height must not grow when caption wraps',
      );
      expect(
        shortY,
        longY,
        reason: 'Save & Next must not shift when caption wraps',
      );

      // Empty / "No caption embedded" hint uses the same reserved height.
      await tester.pumpWidget(_harness(caption: '', belowKey: belowKey));
      await tester.pumpAndSettle();
      final emptyY = tester.getTopLeft(find.byKey(belowKey)).dy;
      final emptyHeight = tester.getSize(find.byType(CaptionStrip)).height;
      expect(emptyHeight, shortHeight);
      expect(emptyY, shortY);
    },
  );
}
