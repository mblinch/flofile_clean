import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quick_cap/caption_style/caption_style_catalog.dart';
import 'package:quick_cap/caption_style/caption_template.dart';
import 'package:quick_cap/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final raw = await SharedPreferences.getInstance();
    await raw.clear();
  });

  test('user-authored styles keep custom game identifier on load', () async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCurrentSport('baseball');

    final custom = CaptionTemplate.getty().copyWith(
      wireStyle: WireStyle.custom,
      id: 'saved_training_camp',
      name: 'Training camp',
      gameIdentifierText: 'during training camp',
    );
    await prefs.saveCaptionTemplate(custom);

    final loaded = await prefs.getCaptionTemplate();
    expect(loaded.isUserAuthoredCaptionStyle, isTrue);
    expect(loaded.gameIdentifierText, 'during training camp');

    final exportedRaw = await prefs.getCaptionTemplateRaw();
    expect(exportedRaw.gameIdentifierText, 'during training camp');
  });

  test('built-in wire styles still receive sport game identifier overlay',
      () async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCurrentSport('hockey');

    final getty = CaptionTemplate.getty().copyWith(
      gameIdentifierText: 'in their MLB game',
    );
    await prefs.saveCaptionTemplate(getty);

    final loaded = await prefs.getCaptionTemplate();
    expect(loaded.isUserAuthoredCaptionStyle, isFalse);
    expect(loaded.gameIdentifierText, 'in their NHL game');
  });

  test('catalog marks saved library entry as active and preserves text',
      () async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCurrentSport('baseball');

    final style = CaptionTemplate.getty().copyWith(
      wireStyle: WireStyle.custom,
      gameIdentifierText: 'during training camp',
    );
    final id = await prefs.addCaptionStyleToLibrary(
      displayName: 'Training camp',
      template: style,
    );
    final applied = style.copyWith(id: id, name: 'Training camp');
    await prefs.saveCaptionTemplate(applied);

    final catalog = await CaptionStyleCatalog.load(prefs, sport: 'baseball');
    expect(catalog.activeToken, 'saved:$id');

    final resolved = catalog.resolve(catalog.activeToken);
    expect(resolved.gameIdentifierText, 'during training camp');
  });
}
