import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/caption_formula_renderer.dart';
import 'package:quick_cap/caption_style/caption_template.dart';

void main() {
  test('timingPhraseCaps defaults off and uppercases preview phrase', () {
    final off = CaptionTemplate.custom(id: 't', name: 'T');
    expect(off.timingPhraseCaps, isFalse);
    expect(
      CaptionFormulaRenderer.previewTimePhraseForSport('baseball'),
      'during the third inning',
    );

    final on = off.copyWith(timingPhraseCaps: true);
    expect(
      CaptionFormulaRenderer.previewTimePhraseForSport(
        'baseball',
        caps: on.timingPhraseCaps,
      ),
      'DURING THE THIRD INNING',
    );

    final body = CaptionFormulaRenderer.randomSinglePlayerCaption(
      on,
      seed: 1,
      sport: 'baseball',
    );
    expect(body.contains('DURING THE THIRD INNING'), isTrue);
  });
}
