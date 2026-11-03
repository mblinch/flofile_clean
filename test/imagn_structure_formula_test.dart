import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';
import 'package:quick_cap/caption_style/structure_formula.dart';

void main() {
  const formula =
      '{month} {day}, {year}; {city}, {state}, {country_code}; {caption} at {location}. {byline}';

  final game = GameInfo(
    city: 'Toronto',
    region: '',
    regionCode: '',
    country: 'Canada',
    countryCode: 'CAN',
    venue: 'Scotiabank Arena',
    photographerName: 'Jane Doe',
    agencyName: 'Imagn Images',
    gameDate: DateTime(2026, 11, 2),
  );

  test('Imagn preset Structure formula includes layout joiners', () {
    final t = CaptionTemplate.imagn();
    expect(StructureFormula.fromTemplate(t), formula);
    expect(t.separatorSnippets, [' at ']);
    expect(t.punctuationSnippets, [' ', ', ', '; ', ', ', ', ', '; ', '. ']);
    // Wired gaps stay empty — joiners live in Structure snippets only.
    expect(t.separator, '');
    expect(
      CaptionFormulaRenderer.defaultGapBetweenSegments(
        t,
        CaptionSegment.city,
        CaptionSegment.state,
      ),
      '',
    );
    expect(
      CaptionFormulaRenderer.defaultGapBetweenSegments(
        t,
        CaptionSegment.year,
        CaptionSegment.city,
      ),
      '',
    );
  });

  test('Imagn Structure round-trip keeps abbreviated month and joiners', () {
    final base = CaptionTemplate.imagn();
    final applied = StructureFormula.applyToTemplate(base, formula);
    expect(StructureFormula.fromTemplate(applied), formula);
    expect(applied.monthTokensByOccurrence?.first.optionIndex, 1);
    expect(applied.separatorSnippets, [' at ']);
    expect(applied.punctuationSnippets?.last, '. ');

    final line = CaptionFormulaRenderer.render(
      template: applied,
      game: game,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.imagn,
    );
    expect(line, startsWith('Nov 2, 2026;'));
    expect(line, contains(' at Scotiabank Arena. '));
    expect(line, contains('Mandatory Credit: Jane Doe-Imagn Images'));
  });

  test('Imagn empty State drops adjacent Structure commas (no double comma)', () {
    final line = CaptionFormulaRenderer.render(
      template: CaptionTemplate.imagn(),
      game: game,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.imagn,
    );
    expect(line, contains('Toronto, CAN'));
    expect(line, isNot(contains(', ,')));
    expect(line, isNot(contains('Toronto, , CAN')));
  });

  test('Imagn empty country code drops trailing geo comma before semicolon', () {
    final noCountry = GameInfo(
      city: 'Toronto',
      region: 'Ontario',
      regionCode: 'ON',
      country: '',
      countryCode: '',
      venue: 'Scotiabank Arena',
      photographerName: 'Jane Doe',
      agencyName: 'Imagn Images',
      gameDate: DateTime(2026, 11, 2),
    );
    final line = CaptionFormulaRenderer.render(
      template: CaptionTemplate.imagn(),
      game: noCountry,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.imagn,
    );
    expect(line, contains('Toronto, Ontario;'));
    expect(line, isNot(contains(', ;')));
    expect(line, isNot(contains(', ,')));
  });

  test('Imagn keeps province AND country code when both present (no Getty auto-adapt)',
      () {
    expect(LocationLineOptions.imagnDefault().autoAdaptUsIntl, isFalse);
    expect(CaptionTemplate.imagn().locationOptions.autoAdaptUsIntl, isFalse);

    final withProvince = GameInfo(
      city: 'Toronto',
      region: 'Ontario',
      regionCode: 'ON',
      country: 'Canada',
      countryCode: 'CAN',
      venue: 'Scotiabank Arena',
      photographerName: 'Jane Doe',
      agencyName: 'Imagn Images',
      gameDate: DateTime(2026, 11, 2),
    );
    final line = CaptionFormulaRenderer.render(
      template: CaptionTemplate.imagn(),
      game: withProvince,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.imagn,
    );
    expect(line, contains('Toronto, Ontario, CAN'));
    expect(line, isNot(contains(', ,')));
  });

  test('Structure {country_code} parses and renders ISO code', () {
    const formulaWithCode =
        '{city}, {state}, {country_code}; {caption}';
    final applied = StructureFormula.applyToTemplate(
      CaptionTemplate.imagn(),
      formulaWithCode,
    );
    expect(applied.segmentOrder, contains(CaptionSegment.countryCode));
    expect(StructureFormula.fromTemplate(applied), contains('{country_code}'));

    final withProvince = GameInfo(
      city: 'Toronto',
      region: 'Ontario',
      regionCode: 'ON',
      country: 'Canada',
      countryCode: 'CAN',
      venue: 'Scotiabank Arena',
      photographerName: 'Jane Doe',
      agencyName: 'Imagn Images',
      gameDate: DateTime(2026, 11, 2),
    );
    final line = CaptionFormulaRenderer.render(
      template: applied,
      game: withProvince,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.imagn,
    );
    expect(line, contains('Toronto, Ontario, CAN'));
    expect(
      CaptionFormulaRenderer.formatGeoField(
        game: withProvince,
        options: LocationLineOptions.imagnDefault(),
        kind: LocationChipKind.countryCode,
      ),
      'CAN',
    );
  });
}
