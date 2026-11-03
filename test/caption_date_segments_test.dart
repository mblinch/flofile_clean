import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/date_formula.dart';
import 'package:quick_cap/caption_style/game_info.dart';

void main() {
  group('CaptionSegment month/day/year', () {
    test('expandDateSegments rewrites date into parts + punctuation', () {
      final legacy = CaptionTemplate.custom(
        segmentOrder: const [
          CaptionSegment.date,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
        ],
        punctuationSnippets: const ['; '],
        customSeparators: const ['', ''],
        dateFormula: DateFormula.imagn(),
      );

      final expanded = legacy.expandDateSegments();
      expect(expanded.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(expanded.segmentOrder, contains(CaptionSegment.month));
      expect(expanded.segmentOrder, contains(CaptionSegment.day));
      expect(expanded.segmentOrder, contains(CaptionSegment.year));
      expect(
        expanded.segmentOrder
            .where((s) => s == CaptionSegment.punctuation)
            .length,
        greaterThanOrEqualTo(3),
      );
    });

    test('fromJson migrates legacy date segmentOrder', () {
      final json = CaptionTemplate.custom(
        segmentOrder: const [
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.date,
        ],
        punctuationSnippets: const [' ('],
        customSeparators: const ['', ''],
        dateFormula: DateFormula.imagn(),
      ).toJson();
      json['segmentOrder'] = ['city', 'punctuation', 'date'];

      final loaded = CaptionTemplate.fromJson(json);
      expect(loaded.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(loaded.segmentOrder.contains(CaptionSegment.month), isTrue);
      expect(loaded.segmentOrder.contains(CaptionSegment.day), isTrue);
      expect(loaded.segmentOrder.contains(CaptionSegment.year), isTrue);
    });

    test('fromLegacySegmentOrder expands game_date into date parts', () {
      final getty = CaptionTemplate.fromLegacySegmentOrder(
        const ['game_date', 'body', 'venue', 'credit'],
        'getty',
      );
      expect(getty.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(getty.segmentOrder, contains(CaptionSegment.month));
      expect(getty.segmentOrder, contains(CaptionSegment.day));
      // Getty's default formula is opening (month+day, no year).

      final imagn = CaptionTemplate.fromLegacySegmentOrder(
        const ['game_date', 'body', 'venue', 'credit'],
        'imagn',
      );
      expect(imagn.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(imagn.segmentOrder, contains(CaptionSegment.month));
      expect(imagn.segmentOrder, contains(CaptionSegment.day));
      expect(imagn.segmentOrder, contains(CaptionSegment.year));
    });

    test('expand drops disabled date fields', () {
      final formula = DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0, enabled: false),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: const ['', ' ', ', ', ''],
      );
      final legacy = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.date],
        dateFormula: formula,
      );
      final expanded = legacy.expandDateSegments();
      expect(expanded.segmentOrder.contains(CaptionSegment.day), isFalse);
      expect(expanded.segmentOrder, contains(CaptionSegment.month));
      expect(expanded.segmentOrder, contains(CaptionSegment.year));
    });

    test('Getty preset renders opening month+day and closing month+day+year',
        () {
      final t = CaptionTemplate.getty();
      expect(t.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(t.segmentOrder.where((s) => s == CaptionSegment.month).length, 2);
      expect(t.segmentOrder.where((s) => s == CaptionSegment.year).length, 1);

      final game = GameInfo(
        city: 'Los Angeles',
        region: 'California',
        regionCode: 'CA',
        country: 'United States',
        countryCode: 'USA',
        venue: 'Dodger Stadium',
        photographerName: 'Jane Doe',
        agencyName: 'Getty Images',
        gameDate: DateTime(2026, 11, 1),
      );

      final line = CaptionFormulaRenderer.render(
        template: t,
        game: game,
        captionOverride: 'hits a home run',
        sampleAgency: CreditSampleAgency.gettyImages,
      );

      expect(line, contains('NOVEMBER'));
      expect(line, contains('1'));
      expect(line, contains('November'));
      expect(line, contains('2026'));
    });

    test('formatDatePart respects caps and optionIndex', () {
      final t = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.month],
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1, caps: true),
        ],
      );
      final game = GameInfo(
        gameDate: DateTime(2026, 4, 9),
      );
      expect(
        CaptionFormulaRenderer.formatDatePart(
          game: game,
          template: t,
          kind: DateFieldKind.month,
          occurrenceIndex: 0,
        ),
        'APR',
      );
    });

    test('month optionIndex 0 full vs 1 abbreviated', () {
      final game = GameInfo(gameDate: DateTime(2026, 10, 5));
      final full = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.month],
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
        ],
      );
      final abbr = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.month],
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1),
        ],
      );
      expect(
        CaptionFormulaRenderer.formatDatePart(
          game: game,
          template: full,
          kind: DateFieldKind.month,
          occurrenceIndex: 0,
        ),
        'October',
      );
      expect(
        CaptionFormulaRenderer.formatDatePart(
          game: game,
          template: abbr,
          kind: DateFieldKind.month,
          occurrenceIndex: 0,
        ),
        'Oct',
      );
    });

    test('weekday optionIndex 0 full vs 1 abbreviated', () {
      // 2026-11-02 is a Monday.
      final game = GameInfo(gameDate: DateTime(2026, 11, 2));
      final full = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.weekday],
        weekdayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.weekday, optionIndex: 0),
        ],
      );
      final abbr = CaptionTemplate.custom(
        segmentOrder: const [CaptionSegment.weekday],
        weekdayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.weekday, optionIndex: 1),
        ],
      );
      expect(
        CaptionFormulaRenderer.formatDatePart(
          game: game,
          template: full,
          kind: DateFieldKind.weekday,
          occurrenceIndex: 0,
        ),
        'Monday',
      );
      expect(
        CaptionFormulaRenderer.formatDatePart(
          game: game,
          template: abbr,
          kind: DateFieldKind.weekday,
          occurrenceIndex: 0,
        ),
        'Mon',
      );
    });

    test('AP preset keeps city/state and month/day/year order', () {
      final t = CaptionTemplate.ap();
      expect(t.segmentOrder.contains(CaptionSegment.location), isFalse);
      expect(t.segmentOrder.contains(CaptionSegment.date), isFalse);
      expect(t.segmentOrder, contains(CaptionSegment.city));
      expect(t.segmentOrder, contains(CaptionSegment.month));
      expect(t.segmentOrder, contains(CaptionSegment.day));
      expect(t.segmentOrder, contains(CaptionSegment.year));

      final game = GameInfo(
        city: 'Boston',
        region: 'Massachusetts',
        regionCode: 'MA',
        country: 'United States',
        countryCode: 'USA',
        venue: 'Fenway Park',
        photographerName: 'Jane Doe',
        agencyName: 'AP',
        gameDate: DateTime(2026, 11, 1),
      );
      final line = CaptionFormulaRenderer.render(
        template: t,
        game: game,
        captionOverride: 'hits a home run',
        sampleAgency: CreditSampleAgency.ap,
      );
      expect(line, contains('Nov'));
      expect(line, contains('2026'));
    });
  });
}
