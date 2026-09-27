import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quick_cap/caption_style/caption_style_catalog.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final raw = await SharedPreferences.getInstance();
    await raw.clear();
  });

  test('Done-style custom promotion survives catalog reload', () async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCurrentSport('baseball');

    final edited = CaptionTemplate.getty().copyWith(
      includeTimingPhrase: false,
      showPersonalityField: false,
      showKeywordsField: true,
      gameIdentifierText: 'during spring training',
      segmentOrder: const [
        CaptionSegment.caption,
        CaptionSegment.punctuation,
        CaptionSegment.date,
      ],
    );
    await prefs.saveCaptionTemplateWireDefault(WireStyle.getty, edited);
    final custom = edited.copyWith(
      wireStyle: WireStyle.custom,
      id: 'custom',
      name: 'Custom',
    );
    await prefs.saveCaptionTemplate(custom);

    // Catalog load used to call saveCurrentSport and clobber authored text.
    final catalog = await CaptionStyleCatalog.load(prefs, sport: 'baseball');
    expect(catalog.activeToken, CaptionStyleCatalog.tokCustom);

    final raw = await prefs.getCaptionTemplateRaw();
    expect(raw.wireStyle, WireStyle.custom);
    expect(raw.includeTimingPhrase, isFalse);
    expect(raw.showPersonalityField, isFalse);
    expect(raw.showKeywordsField, isTrue);
    expect(raw.gameIdentifierText, 'during spring training');
    expect(raw.segmentOrder, [
      CaptionSegment.caption,
      CaptionSegment.punctuation,
      CaptionSegment.date,
    ]);

    final loaded = await prefs.getCaptionTemplate();
    expect(loaded.wireStyle, WireStyle.custom);
    expect(loaded.gameIdentifierText, 'during spring training');
    expect(loaded.includeTimingPhrase, isFalse);
  });

  test('controller reloads custom template from prefs on catalog load', () async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCurrentSport('hockey');

    final custom = CaptionTemplate.getty().copyWith(
      wireStyle: WireStyle.custom,
      id: 'custom',
      name: 'Custom',
      includeTimingPhrase: false,
      gameIdentifierText: 'during training camp',
    );
    await prefs.saveCaptionTemplate(custom);

    final controller = CaptionV2Controller();
    await controller.bootstrap();
    // Simulate stale in-memory template (what happened before Go Time fix).
    controller.captionTemplate = CaptionTemplate.getty();
    controller.sport = 'hockey';
    await controller.reloadCaptionStyle();

    expect(controller.captionTemplate.wireStyle, WireStyle.custom);
    expect(controller.captionTemplate.includeTimingPhrase, isFalse);
    expect(
      controller.captionTemplate.gameIdentifierText,
      'during training camp',
    );
  });
}
