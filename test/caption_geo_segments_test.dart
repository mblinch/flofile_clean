import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';

void main() {
  group('CaptionSegment city/state/country', () {
    test('expandLocationSegments rewrites location into geo + punctuation', () {
      final legacy = CaptionTemplate.custom(
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
        ],
        punctuationSnippets: const ['; '],
        customSeparators: const ['', ''],
        locationOptions: LocationLineOptions.imagnDefault(),
      );

      final expanded = legacy.expandLocationSegments();
      expect(expanded.segmentOrder.contains(CaptionSegment.location), isFalse);
      expect(expanded.segmentOrder, contains(CaptionSegment.city));
      expect(expanded.segmentOrder, contains(CaptionSegment.state));
      expect(expanded.segmentOrder, contains(CaptionSegment.country));
      // city , state , country ; caption
      expect(
        expanded.segmentOrder
            .where((s) => s == CaptionSegment.punctuation)
            .length,
        greaterThanOrEqualTo(3),
      );
    });

    test('fromJson migrates legacy location segmentOrder', () {
      final json = CaptionTemplate.custom(
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.date,
        ],
        punctuationSnippets: const [' - '],
        customSeparators: const ['', ''],
        locationOptions: LocationLineOptions.apDefault(),
      ).toJson();
      // Force legacy shape as if an older build wrote "location".
      json['segmentOrder'] = ['location', 'punctuation', 'date'];

      final loaded = CaptionTemplate.fromJson(json);
      expect(loaded.segmentOrder.contains(CaptionSegment.location), isFalse);
      expect(loaded.segmentOrder.first, CaptionSegment.city);
      expect(loaded.segmentOrder.contains(CaptionSegment.state), isTrue);
    });

    test('Getty preset renders city+state for US and city+country elsewhere',
        () {
      final t = CaptionTemplate.getty();
      expect(t.segmentOrder.contains(CaptionSegment.location), isFalse);
      expect(t.segmentOrder.where((s) => s == CaptionSegment.city).length, 2);

      const us = GameInfo(
        city: 'Los Angeles',
        region: 'California',
        regionCode: 'CA',
        country: 'United States',
        countryCode: 'USA',
        venue: 'Dodger Stadium',
        photographerName: 'Jane Doe',
        agencyName: 'Getty Images',
      );
      const intl = GameInfo(
        city: 'Toronto',
        region: 'Ontario',
        regionCode: 'ON',
        country: 'Canada',
        countryCode: 'CAN',
        venue: 'Rogers Centre',
        photographerName: 'Jane Doe',
        agencyName: 'Getty Images',
      );

      final usLine = CaptionFormulaRenderer.render(
        template: t,
        game: us,
        captionOverride: 'hits a home run',
        sampleAgency: CreditSampleAgency.gettyImages,
      );
      final intlLine = CaptionFormulaRenderer.render(
        template: t,
        game: intl,
        captionOverride: 'hits a home run',
        sampleAgency: CreditSampleAgency.gettyImages,
      );

      expect(usLine, contains('LOS ANGELES'));
      expect(usLine, contains('CALIFORNIA'));
      expect(usLine.toUpperCase(), isNot(contains('UNITED STATES')));

      expect(intlLine, contains('TORONTO'));
      expect(intlLine, contains('CANADA'));
      // Auto-adapt hides province for international Getty.
      expect(intlLine.toUpperCase(), isNot(contains('ONTARIO')));
    });

    test('formatGeoField respects caps and country variant', () {
      const opts = LocationLineOptions(
        uppercase: false,
        chips: [
          LocationChip(
            id: 'c',
            kind: LocationChipKind.country,
            caps: true,
            countryVariant: LocationCountryVariant.isoCode,
          ),
        ],
      );
      const g = GameInfo(
        city: 'Toronto',
        country: 'Canada',
        countryCode: 'CAN',
      );
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: g,
          options: opts,
          kind: LocationChipKind.country,
        ),
        'CAN',
      );
    });

    test('Getty State-only formula shows Country outside US', () {
      // Structures with City+State but no Country chip still need Canada.
      const opts = LocationLineOptions(
        uppercase: false,
        autoAdaptUsIntl: true,
        chips: [
          LocationChip(id: 'c', kind: LocationChipKind.city, caps: true),
          LocationChip(id: 'r', kind: LocationChipKind.region, caps: true),
          LocationChip(id: 'k', kind: LocationChipKind.country, caps: true),
        ],
      );
      const intl = GameInfo(
        city: 'Toronto',
        region: 'Ontario',
        regionCode: 'ON',
        country: 'Canada',
        countryCode: 'CAN',
      );
      const us = GameInfo(
        city: 'Chicago',
        region: 'Illinois',
        regionCode: 'IL',
        country: 'United States',
        countryCode: 'USA',
      );

      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: intl,
          options: opts,
          kind: LocationChipKind.region,
          forceAutoAdaptUsIntl: true,
          formulaIncludesCountry: false,
        ).toUpperCase(),
        'CANADA',
      );
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: us,
          options: opts,
          kind: LocationChipKind.region,
          forceAutoAdaptUsIntl: true,
          formulaIncludesCountry: false,
        ).toUpperCase(),
        'ILLINOIS',
      );
      // With a Country segment present, State blanks outside the US.
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: intl,
          options: opts,
          kind: LocationChipKind.region,
          forceAutoAdaptUsIntl: true,
          formulaIncludesCountry: true,
        ),
        '',
      );
    });

    test('formatGeoField countryCode uses resolvedCountryCode (never auto-blanked)',
        () {
      const opts = LocationLineOptions(
        uppercase: false,
        autoAdaptUsIntl: true,
        chips: [
          LocationChip(id: 'cc', kind: LocationChipKind.countryCode),
        ],
      );
      const us = GameInfo(
        city: 'Los Angeles',
        region: 'California',
        country: 'United States',
        countryCode: 'USA',
      );
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: us,
          options: opts,
          kind: LocationChipKind.countryCode,
          forceAutoAdaptUsIntl: true,
        ),
        'USA',
      );
      // Country name still blanks for US under Getty auto-adapt.
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: us,
          options: opts,
          kind: LocationChipKind.country,
          forceAutoAdaptUsIntl: true,
        ),
        '',
      );
    });
  });
}
