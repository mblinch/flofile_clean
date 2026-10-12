import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/caption_style/game_info.dart';

void main() {
  test('country Aa toggle works when IPTC country is already ALL CAPS', () {
    const g = GameInfo(
      city: 'TORONTO',
      region: 'ONTARIO',
      country: 'CANADA',
      countryCode: 'CAN',
    );
    LocationLineOptions opts({required bool caps}) => LocationLineOptions(
          uppercase: false,
          autoAdaptUsIntl: true,
          chips: [
            const LocationChip(
              id: 'c',
              kind: LocationChipKind.city,
              caps: true,
            ),
            const LocationChip(
              id: 'l1',
              kind: LocationChipKind.literal,
              literal: ', ',
            ),
            LocationChip(
              id: 'co',
              kind: LocationChipKind.country,
              caps: caps,
            ),
          ],
        );

    expect(
      CaptionFormulaRenderer.formatLocationLine(
        g,
        opts(caps: true),
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, CANADA',
    );
    expect(
      CaptionFormulaRenderer.formatLocationLine(
        g,
        opts(caps: false),
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, Canada',
    );
  });

  test('Getty uses the American formula in the US and international elsewhere',
      () {
    const toronto = GameInfo(
      city: 'TORONTO',
      region: 'ONTARIO',
      country: 'CANADA',
      countryCode: 'CAN',
    );
    const chicago = GameInfo(
      city: 'CHICAGO',
      region: 'ILLINOIS',
      country: 'United States',
      countryCode: 'USA',
    );
    final opts = LocationLineOptions.gettyDefault();
    expect(
      CaptionFormulaRenderer.formatLocationLine(
        toronto,
        opts,
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, CANADA',
    );
    expect(
      CaptionFormulaRenderer.formatLocationLine(
        chicago,
        opts,
        forceAutoAdaptUsIntl: true,
      ),
      'CHICAGO, ILLINOIS',
    );
  });

  test('a disabled country chip still prints on the international formula', () {
    const toronto = GameInfo(
      city: 'TORONTO',
      region: 'ONTARIO',
      country: 'CANADA',
      countryCode: 'CAN',
    );
    final opts = LocationLineOptions(
      uppercase: false,
      autoAdaptUsIntl: true,
      chips: const [
        LocationChip(id: 'c', kind: LocationChipKind.city, caps: true),
        LocationChip(id: 'l1', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(id: 'r', kind: LocationChipKind.region, caps: true),
        LocationChip(id: 'l2', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(
          id: 'co',
          kind: LocationChipKind.country,
          caps: true,
          enabled: false,
        ),
      ],
    );
    expect(
      CaptionFormulaRenderer.formatLocationLine(
        toronto,
        opts,
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, CANADA',
    );
  });

  test('location line adds a trailing space only from the user separator', () {
    const g = GameInfo(
      city: 'TORONTO',
      region: 'ONTARIO',
      country: 'CANADA',
      countryCode: 'CAN',
    );
    LocationLineOptions opts(String trailing) => LocationLineOptions(
          uppercase: false,
          autoAdaptUsIntl: true,
          chips: [
            const LocationChip(id: 'c', kind: LocationChipKind.city, caps: true),
            const LocationChip(
              id: 'l1',
              kind: LocationChipKind.literal,
              literal: ', ',
            ),
            const LocationChip(
              id: 'co',
              kind: LocationChipKind.country,
              caps: true,
            ),
            LocationChip(
              id: 'end',
              kind: LocationChipKind.literal,
              literal: trailing,
            ),
          ],
        );

    expect(
      CaptionFormulaRenderer.formatLocationLine(
        g,
        opts(''),
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, CANADA',
    );
    expect(
      CaptionFormulaRenderer.formatLocationLine(
        g,
        opts(' '),
        forceAutoAdaptUsIntl: true,
      ),
      'TORONTO, CANADA ',
    );
  });

  test('applyLocationChipCaps title-cases ALL-CAPS full names when Aa is off',
      () {
    expect(
      CaptionFormulaRenderer.applyLocationChipCaps('CANADA', caps: false),
      'Canada',
    );
    expect(
      CaptionFormulaRenderer.applyLocationChipCaps('CANADA', caps: true),
      'CANADA',
    );
    expect(
      CaptionFormulaRenderer.applyLocationChipCaps(
        'CAN',
        caps: false,
        isIsoCode: true,
      ),
      'CAN',
    );
    expect(
      CaptionFormulaRenderer.applyLocationChipCaps('Canada', caps: false),
      'Canada',
    );
  });
}
