import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/flo_caption_mark.dart';

void main() {
  test('already-captioned files keep caption, personality, and keywords', () {
    final preset = FloCaptionMark.withoutProtectedFields({
      'Caption': 'New template caption',
      'Personality': 'Someone Else',
      'Keywords': 'baseball, template',
      'Credit': 'Getty Images',
      'City': 'Cincinnati',
    });
    final cleared = FloCaptionMark.withoutProtectedClears({
      'Caption',
      'Keywords',
      'Headline',
    });

    expect(preset.keys, ['Credit', 'City']);
    expect(cleared, {'Headline'});
  });
}
