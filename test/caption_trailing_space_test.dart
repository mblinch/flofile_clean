import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';
import 'package:quick_cap/caption_style/structure_formula.dart';

void main() {
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

  test('render strips trailing whitespace from finished caption', () {
    // Caption must not end with a trailing space when it is the last segment.
    final captionLast = CaptionTemplate.custom(
      segmentOrder: const [
        CaptionSegment.city,
        CaptionSegment.punctuation,
        CaptionSegment.caption,
      ],
      punctuationSnippets: const [': '],
    );
    final line = CaptionFormulaRenderer.render(
      template: captionLast,
      game: game,
      captionOverride: 'hits a home run',
      sampleAgency: CreditSampleAgency.gettyImages,
    );
    expect(line, 'Los Angeles: hits a home run');
    expect(line, isNot(endsWith(' ')));
  });

  test('render strips trailing literal space from structure formula', () {
    final t = StructureFormula.applyToTemplate(
      CaptionTemplate.getty(),
      '{dl_city}, {dl_state} - {dl_month} {dl_day}: {caption} ',
      sport: 'baseball',
    );
    final line = CaptionFormulaRenderer.render(
      template: t,
      game: game,
      captionOverride: 'hits a home run',
      sampleAgency: CreditSampleAgency.gettyImages,
    );
    expect(line, isNot(endsWith(' ')));
    expect(line, endsWith('hits a home run'));
  });

  test('Getty preset keeps internal spaces and has no trailing whitespace', () {
    final line = CaptionFormulaRenderer.render(
      template: CaptionTemplate.getty(),
      game: game,
      captionOverride: 'hits a home run',
      sampleAgency: CreditSampleAgency.gettyImages,
    );
    expect(line, contains('hits a home run'));
    expect(line, isNot(endsWith(' ')));
    expect(line, isNot(endsWith('\t')));
  });
}
