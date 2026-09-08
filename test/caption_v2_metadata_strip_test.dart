import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/widgets/caption_strip.dart';

void main() {
  testWidgets('shows enabled compact metadata fields', (tester) async {
    String? changedKeywords;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptionStrip(
            leading: '',
            trailing: '',
            chips: const [],
            headline: 'Game headline',
            onHeadlineChanged: (_) {},
            keywords: 'manual',
            onKeywordsChanged: (value) => changedKeywords = value,
          ),
        ),
      ),
    );

    expect(find.text('HEADLINE'), findsOneWidget);
    expect(find.text('KEYWORDS'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'manual'),
      'manual, action',
    );
    expect(changedKeywords, 'manual, action');
  });

  testWidgets('hides metadata fields when callbacks are disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptionStrip(
            leading: '',
            trailing: '',
            chips: [],
            headline: 'Hidden headline',
            keywords: 'hidden',
          ),
        ),
      ),
    );

    expect(find.text('HEADLINE'), findsNothing);
    expect(find.text('KEYWORDS'), findsNothing);
  });
}
