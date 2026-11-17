import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/iptc_template_apply_service.dart';
import 'package:quick_cap/services/iptc_template_import_service.dart';
import 'package:quick_cap/utils/exiftool_helper.dart';

Uint8List _minimalJpeg() {
  return Uint8List.fromList(const [
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
    0x7F, 0xFF, 0xD9,
  ]);
}

Future<bool> _exiftoolAvailable() async {
  final which = await Process.run('which', ['exiftool']);
  return which.exitCode == 0 && (which.stdout as String).trim().isNotEmpty;
}

Future<File> _jpegFile(Directory dir, String name) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(_minimalJpeg());
  return file;
}

Future<void> _seedMeta(String path, Map<String, String> tags) async {
  final args = <String>[
    for (final e in tags.entries) '-${e.key}=${e.value}',
    '-overwrite_original',
    path,
  ];
  final proc = await ExiftoolHelper.run(args);
  expect(proc.isSuccess, isTrue, reason: proc.stderrText);
}

Future<Map<String, String>> _panel(String path) async {
  final meta = await IptcTemplateImportService.readMetadata(path);
  expect(meta, isNotNull);
  return IptcTemplateImportService.panelValuesFromExiftool(meta!);
}

Future<Map<String, dynamic>> _copyrightRaw(String path) async {
  final proc = await ExiftoolHelper.run([
    '-j',
    '-a',
    '-G1',
    '-IPTC:CopyrightNotice',
    '-XMP-dc:Rights',
    '-IFD0:Copyright',
    path,
  ]);
  expect(proc.isSuccess, isTrue, reason: proc.stderrText);
  final decoded = jsonDecode(proc.stdoutText);
  expect(decoded, isA<List>());
  expect((decoded as List).isNotEmpty, isTrue);
  return Map<String, dynamic>.from(decoded.first as Map);
}

Future<int> _creatorLiCount(String path) async {
  final proc = await ExiftoolHelper.run(['-XMP', '-b', path]);
  if (!proc.isSuccess) return 0;
  final match = RegExp(
    r'<dc:creator>\s*<rdf:Seq>(.*?)</rdf:Seq>\s*</dc:creator>',
    dotAll: true,
  ).firstMatch(proc.stdoutText);
  if (match == null) return 0;
  return RegExp(r'<rdf:li>').allMatches(match.group(1)!).length;
}

Future<int> _personalityLiCount(String path) async {
  final proc = await ExiftoolHelper.run(['-XMP', '-b', path]);
  if (!proc.isSuccess) return 0;
  final match = RegExp(
    r'<GettyImagesGIFT:Personality>\s*<rdf:Bag>(.*?)</rdf:Bag>\s*</GettyImagesGIFT:Personality>',
    dotAll: true,
  ).firstMatch(proc.stdoutText);
  if (match == null) return 0;
  return RegExp(r'<rdf:li>').allMatches(match.group(1)!).length;
}

const _template = {
  'Creator': 'TPL Mark Blinch',
  'Job Title': 'Contributor',
  'Description Writers': 'MB',
  'Object Name': 'TPL_OBJ_001',
  'Special Instructions': 'TPL special',
  'Headline': 'TPL Headline',
  'City': 'TPL Toronto',
  'Credit': 'TPL Getty Images',
  'Keywords': 'TPLhockey',
  'Personality': 'Paige Bueckers',
  'Source': 'Getty Images North America',
  'Stadium': 'Coca-Cola Coliseum',
  'MEID': '776465233',
  'Supp Cat 1': 'SPO',
  'Supp Cat 2': 'BKP',
  'Supp Cat 3': 'WBA',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Creator write tags are single-store (no XMP bag alias stack)', () {
    final tags = <String, String>{};
    IptcTemplateApplyService.addExiftoolTagsForPresetKey(
      tags,
      'Creator',
      'Mark Blinch',
    );
    expect(tags.keys.toSet(), {
      'IPTC:By-line',
      'XMP-dc:Creator',
    });
    final clear = IptcTemplateApplyService.clearArgsForPresetKey('Creator');
    expect(clear, contains('-XMP-dc:Creator='));
    expect(clear, contains('-XMP:Creator='));
    expect(clear, contains('-Creator='));
  });

  test('Copyright write tags are IPTC notice + XMP-dc:Rights only', () {
    final tags = <String, String>{};
    IptcTemplateApplyService.addExiftoolTagsForPresetKey(
      tags,
      'Copyright',
      'copyright test',
    );
    expect(tags.keys.toSet(), {
      'IPTC:CopyrightNotice',
      'XMP-dc:Rights',
    });
  });

  test('fill-empty write plan keeps Job Title when panel key differs', () {
    final existingMeta = <String, dynamic>{
      'IPTC:By-lineTitle': 'job title teset',
      'By-lineTitle': 'job title teset',
    };
    final existing =
        IptcTemplateImportService.panelValuesFromExiftool(existingMeta);
    expect(existing['Job Title'], 'job title teset');
    expect(
      IptcTemplateApplyService.lookupValue(existing, "Creator's Job Title"),
      'job title teset',
    );
  });

  test('creatorPrimaryFromExiftool ignores EXIF Artist', () {
    expect(
      IptcTemplateImportService.creatorPrimaryFromExiftool({
        'EXIF:Artist': 'Camera Body',
        'Artist': 'Camera Body',
      }),
      '',
    );
    expect(
      IptcTemplateImportService.creatorPrimaryFromExiftool({
        'EXIF:Artist': 'Camera Body',
        'IPTC:By-line': 'Mark Blinch',
      }),
      'Mark Blinch',
    );
  });

  test('copyrightPrimaryFromExiftool ignores IFD0 Copyright', () {
    expect(
      IptcTemplateImportService.copyrightPrimaryFromExiftool({
        'IFD0:Copyright': 'Camera Copyright',
        'Copyright': 'Camera Copyright',
      }),
      '',
    );
    expect(
      IptcTemplateImportService.copyrightPrimaryFromExiftool({
        'IFD0:Copyright': 'Camera Copyright',
        'IPTC:CopyrightNotice': 'TPL Copyright',
      }),
      'TPL Copyright',
    );
  });

  test('normalizeForPreset prefers Stadium over Location alias', () {
    final preset = IptcTemplateApplyService.normalizeForPreset({
      'Stadium': 'TPL Venue',
      'Location': 'venue test',
      'Copyright': 'TPL Copyright',
    });
    expect(preset['Stadium'], 'TPL Venue');
    expect(preset.containsKey('Location'), isFalse);
  });

  test(
    'Apply replaces every template field; Fill leaves filled fields untouched',
    () async {
      if (!await _exiftoolAvailable()) {
        return;
      }

      final dir = await Directory.systemTemp.createTemp('iptc_modes_');
      addTearDown(() => dir.delete(recursive: true));

      final full = await _jpegFile(dir, 'full.jpg');
      final partial = await _jpegFile(dir, 'partial.jpg');
      final empty = await _jpegFile(dir, 'empty.jpg');
      final blankCreatorHeadline =
          await _jpegFile(dir, 'blank_creator_headline.jpg');

      await _seedMeta(full.path, {
        'IPTC:By-line': 'Existing Creator',
        'IPTC:By-lineTitle': 'job title teset',
        'IPTC:Writer-Editor': 'OLD',
        'IPTC:ObjectName': 'OLD_OBJ',
        'XMP:Title': 'OLD_OBJ',
        'IPTC:SpecialInstructions': 'old si',
        'IPTC:Headline': 'Existing Headline',
        'IPTC:City': 'Existing City',
        'IPTC:Credit': 'Existing Credit',
        'IPTC:Keywords': 'keyword test',
        'XMP-getty:Personality': 'personality test',
        'IPTC:Source': 'Existing Source',
        'IPTC:Sub-location': 'Existing Venue',
        'IPTC:OriginalTransmissionReference': '111',
        'IPTC:SupplementalCategories': 'AAA',
      });

      await _seedMeta(partial.path, {
        'IPTC:By-lineTitle': 'job title teset',
        'IPTC:Keywords': 'keyword test',
        'XMP-getty:Personality': 'personality test',
        'IPTC:City': 'Existing City',
      });

      await _seedMeta(blankCreatorHeadline.path, {
        'IPTC:City': 'Existing City',
        'IPTC:Credit': 'Existing Credit',
        'IPTC:By-lineTitle': 'job title teset',
      });

      // Same map the UI would persist / pass to the writer.
      final onScreenTemplate = Map<String, String>.from(_template);

      Future<void> applyAll({required bool fillEmptyOnly}) async {
        for (final entry in {
          full: 0,
          partial: 1,
          empty: 2,
          blankCreatorHeadline: 3,
        }.entries) {
          final result = await IptcTemplateApplyService.applyToImage(
            entry.key.path,
            onScreenTemplate,
            imageIndex: entry.value,
            replaceExisting: !fillEmptyOnly,
            preserveOnLoad: true,
            fillEmptyOnly: fillEmptyOnly,
          );
          expect(result.success, isTrue);
        }
      }

      // --- Apply mode ---
      await applyAll(fillEmptyOnly: false);

      for (final file in [full, partial, empty, blankCreatorHeadline]) {
        final panel = await _panel(file.path);
        expect(panel['Creator'], 'TPL Mark Blinch');
        expect(panel['Job Title'], 'Contributor');
        expect(panel['Description Writers'], 'MB');
        expect(panel['Object Name'], 'TPL_OBJ_001');
        expect(panel['Special Instructions'], 'TPL special');
        expect(panel['Headline'], 'TPL Headline');
        expect(panel['City'], 'TPL Toronto');
        expect(panel['Credit'], 'TPL Getty Images');
        expect(panel['Keywords'], 'TPLhockey');
        expect(panel['Personality'], 'Paige Bueckers');
        expect(panel['Source'], 'Getty Images North America');
        expect(panel['Stadium'], 'Coca-Cola Coliseum');
        expect(panel['MEID'], '776465233');
        expect(await _creatorLiCount(file.path), 1);
        expect(await _personalityLiCount(file.path), 1);
        expect(
          panel['Keywords']!.contains('keyword test'),
          isFalse,
          reason: 'Apply must replace keywords, not merge',
        );
        expect(
          panel['Personality']!.contains('personality test'),
          isFalse,
          reason: 'Apply must replace personality, not merge',
        );
      }

      // Reset fixtures for Fill mode.
      await _jpegFile(dir, 'full.jpg');
      await _jpegFile(dir, 'partial.jpg');
      await _jpegFile(dir, 'empty.jpg');
      await _jpegFile(dir, 'blank_creator_headline.jpg');

      await _seedMeta(full.path, {
        'IPTC:By-line': 'Existing Creator',
        'IPTC:By-lineTitle': 'job title teset',
        'IPTC:Writer-Editor': 'OLD',
        'IPTC:ObjectName': 'OLD_OBJ',
        'XMP:Title': 'OLD_OBJ',
        'IPTC:SpecialInstructions': 'old si',
        'IPTC:Headline': 'Existing Headline',
        'IPTC:City': 'Existing City',
        'IPTC:Credit': 'Existing Credit',
        'IPTC:Keywords': 'keyword test',
        'XMP-getty:Personality': 'personality test',
        'IPTC:Source': 'Existing Source',
        'IPTC:Sub-location': 'Existing Venue',
        'IPTC:OriginalTransmissionReference': '111',
      });
      await _seedMeta(partial.path, {
        'IPTC:By-lineTitle': 'job title teset',
        'IPTC:Keywords': 'keyword test',
        'XMP-getty:Personality': 'personality test',
        'IPTC:City': 'Existing City',
      });
      await _seedMeta(blankCreatorHeadline.path, {
        'IPTC:City': 'Existing City',
        'IPTC:Credit': 'Existing Credit',
        'IPTC:By-lineTitle': 'job title teset',
      });

      final beforeFull = await _panel(full.path);
      final beforePartial = await _panel(partial.path);
      final beforeBlank = await _panel(blankCreatorHeadline.path);

      await applyAll(fillEmptyOnly: true);

      final afterFull = await _panel(full.path);
      for (final key in beforeFull.keys) {
        if (key == 'Caption') continue;
        expect(
          afterFull[key],
          beforeFull[key],
          reason: 'Fill must leave filled field "$key" unchanged on full.jpg',
        );
      }

      final afterPartial = await _panel(partial.path);
      expect(afterPartial['Job Title'], 'job title teset');
      expect(afterPartial['Keywords'], 'keyword test');
      expect(afterPartial['Personality'], 'personality test');
      expect(afterPartial['City'], 'Existing City');
      expect(afterPartial['Creator'], 'TPL Mark Blinch');
      expect(afterPartial['Headline'], 'TPL Headline');
      expect(afterPartial['Description Writers'], 'MB');
      expect(afterPartial['Object Name'], 'TPL_OBJ_001');
      expect(afterPartial['Special Instructions'], 'TPL special');
      expect(afterPartial['Credit'], 'TPL Getty Images');
      expect(await _creatorLiCount(partial.path), 1);
      expect(await _personalityLiCount(partial.path), 1);

      final afterEmpty = await _panel(empty.path);
      expect(afterEmpty['Creator'], 'TPL Mark Blinch');
      expect(afterEmpty['Job Title'], 'Contributor');
      expect(afterEmpty['Description Writers'], 'MB');
      expect(afterEmpty['Object Name'], 'TPL_OBJ_001');
      expect(afterEmpty['Special Instructions'], 'TPL special');
      expect(afterEmpty['Headline'], 'TPL Headline');
      expect(afterEmpty['Keywords'], 'TPLhockey');
      expect(afterEmpty['Personality'], 'Paige Bueckers');
      expect(await _creatorLiCount(empty.path), 1);

      final afterBlank = await _panel(blankCreatorHeadline.path);
      expect(afterBlank['City'], beforeBlank['City']);
      expect(afterBlank['Credit'], beforeBlank['Credit']);
      expect(afterBlank['Job Title'], 'job title teset');
      expect(afterBlank['Creator'], 'TPL Mark Blinch');
      expect(afterBlank['Headline'], 'TPL Headline');
      expect(await _creatorLiCount(blankCreatorHeadline.path), 1);

      // On-screen template model is the same map passed to the writer.
      expect(
        MapEquality().equals(onScreenTemplate, _template),
        isTrue,
      );
    },
  );

  test(
    'Fill empty file gets every edited on-screen field (Venue + Copyright)',
    () async {
      if (!await _exiftoolAvailable()) return;

      final dir = await Directory.systemTemp.createTemp('iptc_fill_all_');
      addTearDown(() => dir.delete(recursive: true));

      // On-screen Fill model after editing every field. Includes the real UI
      // collision: Stadium=<edited Venue> beside leftover Location=<file>.
      const onScreen = {
        'Personality': 'TPL Personality',
        'Description Writers': 'TPL',
        'Headline': 'TPL Headline',
        'MEID': 'TPLMEID001',
        'Keywords': 'TPLhockey, TPLKeyword',
        'Creator': 'TPL Mark Blinch',
        'Job Title': 'TPL Job Title',
        'Copyright': 'TPL Copyright',
        'Credit': 'TPL Getty Images',
        'Source': 'TPL Source',
        'City': 'TPL Toronto',
        'Stadium': 'TPL Venue',
        'Location': 'venue test', // stale file mirror — must not win
        'Province/State': 'TPL ON',
        'Country': 'TPL Canada',
        'Country Code': 'TPL',
        'Object Name': 'TPL_OBJECT',
        'Special Instructions': 'TPL special instructions',
        'Category': 'S',
        'Supp Cat 1': 'TEA',
        'Supp Cat 2': 'TEB',
        'Supp Cat 3': 'TEC',
        'Urgency': '5',
      };
      final expected = IptcTemplateApplyService.normalizeForPreset(onScreen);
      expect(expected['Stadium'], 'TPL Venue');
      expect(expected['Copyright'], 'TPL Copyright');

      final empty = await _jpegFile(dir, 'empty.jpg');
      // Leftover camera Copyright must not block IPTC/XMP fill.
      await _seedMeta(empty.path, {
        'IFD0:Copyright': 'Camera Copyright Leftover',
      });

      final result = await IptcTemplateApplyService.applyToImage(
        empty.path,
        onScreen,
        replaceExisting: false,
        preserveOnLoad: true,
        fillEmptyOnly: true,
      );
      expect(result.success, isTrue);

      final panel = await _panel(empty.path);
      for (final e in expected.entries) {
        if (e.key == 'Urgency') {
          expect(
            IptcTemplateApplyService.normalizeUrgencyValue(
              panel['Urgency'] ?? '',
            ),
            e.value,
            reason: 'Urgency',
          );
          continue;
        }
        expect(
          panel[e.key] ??
              IptcTemplateApplyService.lookupValue(panel, e.key) ??
              '',
          e.value,
          reason: 'empty file must get on-screen field ${e.key}',
        );
      }
      expect(panel['Stadium'], 'TPL Venue');
      expect(panel['Stadium'], isNot('venue test'));

      final copyrightRaw = await _copyrightRaw(empty.path);
      expect(copyrightRaw['IPTC:CopyrightNotice'], 'TPL Copyright');
      expect(copyrightRaw['XMP-dc:Rights'], 'TPL Copyright');
      expect(await _creatorLiCount(empty.path), 1);

      // EXIF Artist alone must not block filling By-line / XMP-dc:Creator.
      final artistOnly = await _jpegFile(dir, 'artist_only.jpg');
      await _seedMeta(artistOnly.path, {
        'EXIF:Artist': 'Camera Body Artist',
      });
      final creatorFill = await IptcTemplateApplyService.applyToImage(
        artistOnly.path,
        {'Creator': 'TPL Mark Blinch'},
        replaceExisting: false,
        preserveOnLoad: true,
        fillEmptyOnly: true,
      );
      expect(creatorFill.success, isTrue);
      final afterArtist = await _panel(artistOnly.path);
      expect(afterArtist['Creator'], 'TPL Mark Blinch');
      expect(await _creatorLiCount(artistOnly.path), 1);
    },
  );
}

/// Tiny equality helper so the test file stays dependency-light.
class MapEquality {
  bool equals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
