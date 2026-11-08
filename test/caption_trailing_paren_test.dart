import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';
import 'package:quick_cap/caption_style/structure_formula.dart';

void main() {
  final game = GameInfo(
    city: 'Toronto',
    region: '',
    regionCode: '',
    country: 'Canada',
    countryCode: 'CAN',
    venue: 'Scotiabank Arena',
    photographerName: 'Mark Blinch',
    agencyName: 'NHLI via Getty Images',
    gameDate: DateTime(2026, 11, 7),
  );

  test('Getty Structure trailing ) credit paren is written', () {
    final t = StructureFormula.applyToTemplate(
      CaptionTemplate.gettyInternational(),
      '{dl_city}, {dl_country} - {dl_month} {dl_day}: {caption} at {location} '
          'on {month} {day}, {year}. {city}, {country}. '
          '(Photo by {name}/{credit})',
      sport: 'hockey',
    );
    final line = CaptionFormulaRenderer.render(
      template: t,
      game: game,
      captionOverride:
          'Owen Beck #62 of the Montreal Canadiens stretches prior to play '
          'against the Toronto Maple Leafs during the second period',
      sampleAgency: CreditSampleAgency.gettyImages,
    );
    expect(line, endsWith(')'));
    expect(
      line,
      contains('(Photo by Mark Blinch/NHLI via Getty Images)'),
    );
  });

  test('Getty Structure empty State still drops geo commas', () {
    final t = StructureFormula.applyToTemplate(
      CaptionTemplate.gettyInternational(),
      '{dl_city}, {dl_state}, {dl_country} - {caption}. (Photo by {name}/{credit})',
      sport: 'hockey',
    );
    final line = CaptionFormulaRenderer.render(
      template: t,
      game: game,
      captionOverride: 'Player skates',
      sampleAgency: CreditSampleAgency.gettyImages,
    );
    expect(line, isNot(contains(', ,')));
    expect(line, endsWith(')'));
    expect(line, contains('(Photo by Mark Blinch/NHLI via Getty Images)'));
  });
}
