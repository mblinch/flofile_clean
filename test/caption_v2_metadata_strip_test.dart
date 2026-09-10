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

  testWidgets('MLB timestamp loading state does not overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptionStrip(
            leading: '',
            trailing: '',
            chips: const [],
            inningLabel: '1st',
            onInningDecrement: () {},
            onInningIncrement: () {},
            onPreTap: () {},
            onPostTap: () {},
            mlbTimestampVisible: true,
            mlbTimestampLoading: true,
            onMlbTimestampTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('MLB TIME'), findsOneWidget);
    final error = tester.takeException();
    expect(error, isNull);
  });

  testWidgets('baseball inning squares page extras with arrows', (tester) async {
    var selected = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CaptionStrip(
                leading: '',
                trailing: '',
                chips: const [],
                inningLabel: '$selected',
                inning: selected,
                regulationCount: 9,
                maxInning: 27,
                onInningSelected: (value) => setState(() => selected = value),
                onPreTap: () {},
                onPostTap: () {},
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('9'), findsOneWidget);
    expect(find.text('10'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(selected, 14);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.text('19'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);

    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();
    expect(selected, 27);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('27'), findsNothing);
  });
}
