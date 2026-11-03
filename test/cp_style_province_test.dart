import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';
import 'package:quick_cap/caption_style/region_abbrev.dart';

void main() {
  group('CP style province abbreviations', () {
    test('normalizes full name, postal code, and CP abbrev', () {
      expect(abbreviateCpStyleProvince('Ontario'), 'Ont.,');
      expect(abbreviateCpStyleProvince('ON'), 'Ont.,');
      expect(abbreviateCpStyleProvince('Ont.'), 'Ont.,');
      expect(abbreviateCpStyleProvince('Ont.,'), 'Ont.,');
      expect(abbreviateCpStyleProvince('British Columbia'), 'B.C.,');
      expect(abbreviateCpStyleProvince('BC'), 'B.C.,');
      expect(abbreviateCpStyleProvince('Quebec'), 'Que.,');
      expect(abbreviateCpStyleProvince('QC'), 'Que.,');
      expect(abbreviateCpStyleProvince('Newfoundland and Labrador'), 'Nfld.,');
      expect(abbreviateCpStyleProvince('NL'), 'Nfld.,');
      expect(abbreviateCpStyleProvince('Northwest Territories'), 'N.W.T.,');
      expect(abbreviateCpStyleProvince('NT'), 'N.W.T.,');
      expect(abbreviateCpStyleProvince('Prince Edward Island'), 'P.E.I.,');
      expect(abbreviateCpStyleProvince('PE'), 'P.E.I.,');
    });

    test('never-abbreviated territories stay full', () {
      expect(abbreviateCpStyleProvince('Yukon'), 'Yukon,');
      expect(abbreviateCpStyleProvince('YT'), 'Yukon,');
      expect(abbreviateCpStyleProvince('Nunavut'), 'Nunavut,');
      expect(abbreviateCpStyleProvince('NU'), 'Nunavut,');
    });

    test('standalone Canadian cities omit province', () {
      expect(
        formatCpStyleProvince(
          city: 'Vancouver',
          region: 'British Columbia',
          regionCode: 'BC',
        ),
        '',
      );
      expect(
        formatCpStyleProvince(
          city: 'Toronto',
          region: 'Ontario',
        ),
        '',
      );
      expect(
        formatCpStyleProvince(
          city: 'Quebec City',
          region: 'Quebec',
        ),
        '',
      );
      expect(
        formatCpStyleProvince(
          city: 'Montréal',
          region: 'Quebec',
        ),
        '',
      );
    });

    test('non-standalone cities keep CP province abbrev', () {
      expect(
        formatCpStyleProvince(
          city: 'Brossard',
          region: 'Quebec',
        ),
        'Que.,',
      );
      expect(
        formatCpStyleProvince(
          city: 'Brossard',
          regionCode: 'QC',
        ),
        'Que.,',
      );
      expect(
        formatCpStyleProvince(
          city: 'Kelowna',
          region: 'BC',
        ),
        'B.C.,',
      );
      expect(
        formatCpStyleProvince(
          city: 'London',
          region: 'Ontario',
        ),
        'Ont.,',
      );
    });
  });

  group('CP wire render', () {
    String line(GameInfo g) {
      return CaptionFormulaRenderer.formatLocationLine(
        g,
        LocationLineOptions.apDefault(),
        cpStyleCaption: true,
      );
    }

    test('Vancouver standalone — no province', () {
      expect(
        line(const GameInfo(
          city: 'Vancouver',
          region: 'British Columbia',
          country: 'Canada',
          countryCode: 'CAN',
        )),
        'Vancouver',
      );
    });

    test('Brossard, Que., — comma on province short form', () {
      expect(
        line(const GameInfo(
          city: 'Brossard',
          region: 'Quebec',
          country: 'Canada',
          countryCode: 'CAN',
        )),
        'Brossard, Que.,',
      );
    });

    test('CP segment glue drops comma after standalone city', () {
      final t = CaptionTemplate.cp();
      final rendered = CaptionFormulaRenderer.render(
        template: t,
        game: const GameInfo(
          city: 'Vancouver',
          region: 'British Columbia',
          regionCode: 'BC',
          country: 'Canada',
          countryCode: 'CAN',
          venue: 'Rogers Arena',
        ),
        sampleAgency: CreditSampleAgency.ap,
        captionOverride:
            "Toronto Maple Leafs' Troy Stecher (28) celebrates",
      );
      expect(rendered, contains('Vancouver,'));
      expect(rendered, isNot(contains('Vancouver, B.C.')));
      expect(rendered, isNot(contains('Vancouver, British')));
    });

    test('CP segment glue keeps province comma before continuation', () {
      final t = CaptionTemplate.cp();
      final rendered = CaptionFormulaRenderer.render(
        template: t,
        game: const GameInfo(
          city: 'Brossard',
          region: 'Quebec',
          regionCode: 'QC',
          country: 'Canada',
          countryCode: 'CAN',
          venue: 'Place Bell',
        ),
        sampleAgency: CreditSampleAgency.ap,
        captionOverride: 'Players warm up',
      );
      // "Brossard, Que., " then month — trailing comma after Que.
      expect(rendered, contains('Brossard, Que.,'));
    });

    test('CP team possessive lead', () {
      final t = CaptionTemplate.cp();
      final lead = CaptionFormulaRenderer.randomSinglePlayerPreview(
        t,
        seed: 1,
        previewPlayers: const [
          CaptionPreviewPlayer(
            'Toronto Maple Leafs',
            'D',
            'Troy Stecher',
            28,
            'Vancouver Canucks',
          ),
        ],
      );
      expect(lead, "Toronto Maple Leafs' Troy Stecher (28)");
    });
  });
}
