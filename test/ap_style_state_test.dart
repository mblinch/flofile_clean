import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';
import 'package:quick_cap/caption_style/region_abbrev.dart';

void main() {
  group('AP style state abbreviations', () {
    test('normalizes full name, postal code, and AP abbrev', () {
      expect(abbreviateUsStateApStyle('California'), 'Calif.');
      expect(abbreviateUsStateApStyle('CA'), 'Calif.');
      expect(abbreviateUsStateApStyle('Calif.'), 'Calif.');
      expect(abbreviateUsStateApStyle('NY'), 'N.Y.');
      expect(abbreviateUsStateApStyle('New York'), 'N.Y.');
      expect(abbreviateUsStateApStyle('N.Y.'), 'N.Y.');
      expect(abbreviateUsStateApStyle('TX'), 'Texas');
      expect(abbreviateUsStateApStyle('Ohio'), 'Ohio');
      expect(abbreviateUsStateApStyle('OH'), 'Ohio');
      expect(abbreviateUsStateApStyle('West Virginia'), 'W.Va.');
      expect(abbreviateUsStateApStyle('WV'), 'W.Va.');
    });

    test('never-abbreviated states stay full', () {
      for (final s in [
        'Alaska',
        'Hawaii',
        'Idaho',
        'Iowa',
        'Maine',
        'Ohio',
        'Texas',
        'Utah',
      ]) {
        expect(abbreviateUsStateApStyle(s), s);
      }
    });

    test('standalone cities omit state', () {
      expect(
        formatApStyleState(
          city: 'Philadelphia',
          region: 'Pennsylvania',
          regionCode: 'PA',
        ),
        '',
      );
      expect(
        formatApStyleState(
          city: 'Washington',
          region: 'District of Columbia',
          regionCode: 'DC',
        ),
        '',
      );
      expect(
        formatApStyleState(
          city: 'New York',
          region: 'New York',
          regionCode: 'NY',
        ),
        '',
      );
    });

    test('non-standalone cities keep abbreviated state', () {
      expect(
        formatApStyleState(
          city: 'Anaheim',
          region: 'California',
        ),
        'Calif.',
      );
      expect(
        formatApStyleState(
          city: 'Buffalo',
          region: 'NY',
        ),
        'N.Y.',
      );
      expect(
        formatApStyleState(
          city: 'Columbus',
          region: 'Ohio',
        ),
        'Ohio',
      );
      expect(
        formatApStyleState(
          city: 'Arlington',
          region: 'TX',
        ),
        'Texas',
      );
    });
  });

  group('AP style location line output', () {
    const apOpts = LocationLineOptions(
      uppercase: false,
      chips: [
        LocationChip(id: 'c', kind: LocationChipKind.city),
        LocationChip(
          id: 'lit',
          kind: LocationChipKind.literal,
          literal: ', ',
        ),
        LocationChip(
          id: 'r',
          kind: LocationChipKind.region,
          regionVariant: LocationRegionVariant.apStyle,
        ),
      ],
    );

    String line(GameInfo g) => CaptionFormulaRenderer.formatLocationLine(
          g,
          apOpts,
          apStyleCaption: true,
        );

    /// AP abbrevs already end with `.` — don't double the sentence period.
    String inPhrase(GameInfo g) {
      final loc = line(g);
      return loc.endsWith('.') ? 'in $loc' : 'in $loc.';
    }

    test('Philadelphia → no state, no dangling comma', () {
      expect(
        line(const GameInfo(
          city: 'Philadelphia',
          region: 'Pennsylvania',
          regionCode: 'PA',
          country: 'United States',
          countryCode: 'USA',
        )),
        'Philadelphia',
      );
      expect(
        inPhrase(const GameInfo(city: 'Philadelphia', region: 'PA')),
        'in Philadelphia.',
      );
    });

    test('Anaheim, California → Anaheim, Calif.', () {
      expect(
        line(const GameInfo(
          city: 'Anaheim',
          region: 'California',
          country: 'United States',
        )),
        'Anaheim, Calif.',
      );
      expect(
        inPhrase(const GameInfo(city: 'Anaheim', region: 'California')),
        'in Anaheim, Calif.',
      );
    });

    test('Buffalo, NY → Buffalo, N.Y.', () {
      expect(
        line(const GameInfo(
          city: 'Buffalo',
          region: 'NY',
          country: 'United States',
        )),
        'Buffalo, N.Y.',
      );
      expect(
        inPhrase(const GameInfo(city: 'Buffalo', regionCode: 'NY')),
        'in Buffalo, N.Y.',
      );
    });

    test('Columbus, Ohio → Columbus, Ohio', () {
      expect(
        line(const GameInfo(
          city: 'Columbus',
          region: 'Ohio',
          country: 'United States',
        )),
        'Columbus, Ohio',
      );
      expect(
        inPhrase(const GameInfo(city: 'Columbus', region: 'Ohio')),
        'in Columbus, Ohio.',
      );
    });

    test('Arlington, TX → Arlington, Texas', () {
      expect(
        line(const GameInfo(
          city: 'Arlington',
          region: 'TX',
          country: 'United States',
        )),
        'Arlington, Texas',
      );
      expect(
        inPhrase(const GameInfo(city: 'Arlington', regionCode: 'TX')),
        'in Arlington, Texas.',
      );
    });

    test('Washington, DC → Washington', () {
      expect(
        line(const GameInfo(
          city: 'Washington',
          region: 'DC',
          country: 'United States',
        )),
        'Washington',
      );
      expect(
        inPhrase(const GameInfo(
          city: 'Washington',
          region: 'District of Columbia',
        )),
        'in Washington.',
      );
    });

    test('formatGeoField returns empty state for standalone city', () {
      const opts = LocationLineOptions(
        uppercase: false,
        chips: [
          LocationChip(
            id: 'r',
            kind: LocationChipKind.region,
            regionVariant: LocationRegionVariant.apStyle,
          ),
        ],
      );
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: const GameInfo(
            city: 'Philadelphia',
            region: 'Pennsylvania',
          ),
          options: opts,
          kind: LocationChipKind.region,
          apStyleCaption: true,
        ),
        '',
      );
      expect(
        CaptionFormulaRenderer.formatGeoField(
          game: const GameInfo(
            city: 'Anaheim',
            region: 'California',
          ),
          options: opts,
          kind: LocationChipKind.region,
          apStyleCaption: true,
        ),
        'Calif.',
      );
    });

    test('AP wire Structure drops comma when state suppressed', () {
      final t = CaptionTemplate.ap();
      final rendered = CaptionFormulaRenderer.render(
        template: t,
        game: GameInfo(
          city: 'Philadelphia',
          region: 'Pennsylvania',
          regionCode: 'PA',
          country: 'United States',
          countryCode: 'USA',
          venue: 'Wells Fargo Center',
          photographerName: 'Jane Doe',
          agencyName: 'Associated Press',
          gameDate: DateTime(2026, 4, 4),
        ),
        captionOverride: 'scores',
        sampleAgency: CreditSampleAgency.ap,
      );
      expect(rendered, contains('Philadelphia ('));
      expect(rendered, isNot(contains('Philadelphia, (')));
      expect(rendered, isNot(contains('Pa.')));
    });

    test('fullName region variant still prints full state when AP Style is off',
        () {
      const opts = LocationLineOptions(
        uppercase: false,
        chips: [
          LocationChip(id: 'c', kind: LocationChipKind.city),
          LocationChip(
            id: 'lit',
            kind: LocationChipKind.literal,
            literal: ', ',
          ),
          LocationChip(
            id: 'r',
            kind: LocationChipKind.region,
            regionVariant: LocationRegionVariant.fullName,
          ),
        ],
      );
      expect(
        CaptionFormulaRenderer.formatLocationLine(
          const GameInfo(
            city: 'Philadelphia',
            region: 'Pennsylvania',
          ),
          opts,
        ),
        'Philadelphia, Pennsylvania',
      );
    });
  });
}
