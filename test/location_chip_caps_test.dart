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
