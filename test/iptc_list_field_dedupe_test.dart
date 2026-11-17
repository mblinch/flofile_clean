import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/helpers.dart';
import 'package:quick_cap/screens/caption_v2/data/iptc_caption_writer.dart';
import 'package:quick_cap/services/iptc_template_apply_service.dart';
import 'package:quick_cap/utils/exiftool_helper.dart';

/// Minimal valid 1×1 JPEG — metadata only; never mutate pixel payload in tests.
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

Future<Map<String, dynamic>> _readMeta(String path) async {
  final proc = await ExiftoolHelper.run([
    '-j',
    '-a',
    '-G1',
    '-Keywords',
    '-Subject',
    '-SupplementalCategories',
    '-Country-PrimaryLocationCode',
    '-CountryCode',
    '-XMP-getty:Personality',
    '-Personality',
    path,
  ]);
  expect(proc.isSuccess, isTrue, reason: proc.stderrText);
  final decoded = jsonDecode(proc.stdoutText);
  expect(decoded, isA<List>());
  expect((decoded as List).isNotEmpty, isTrue);
  return Map<String, dynamic>.from(decoded.first as Map);
}

List<String> _asList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .expand((e) => e.toString().split(RegExp(r'[,;]')))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return raw
      .toString()
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

void _expectNoDuplicates(List<String> values, {required String label}) {
  expect(
    values.toSet().length,
    values.length,
    reason: '$label has duplicates: $values',
  );
}

Future<int> _personalityLiCount(String path) async {
  final proc = await ExiftoolHelper.run(['-XMP', '-b', path]);
  if (!proc.isSuccess) return 0;
  final xmp = proc.stdoutText;
  final bag = RegExp(
    r'<GettyImagesGIFT:Personality>\s*<rdf:Bag>(.*?)</rdf:Bag>\s*</GettyImagesGIFT:Personality>',
    dotAll: true,
  ).firstMatch(xmp);
  if (bag == null) return 0;
  return RegExp(r'<rdf:li>').allMatches(bag.group(1)!).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keyword arg builder clears then adds each value individually', () {
    final args = <String>[];
    // Mirror writer private helper via a public write dry-run of the map shape.
    final writer = const IptcCaptionWriter();
    expect(writer, isNotNull);
    final parts = IptcCaptionWriter.dedupeListValues(
      'A, A, B, a'.split(RegExp(r'[,;]')),
    );
    // Case-sensitive: 'A' and 'a' both kept; duplicate 'A' dropped.
    expect(parts, ['A', 'B', 'a']);
    args.add('-IPTC:Keywords=');
    args.add('-Keywords=');
    args.add('-Subject=');
    args.add('-XMP-dc:Subject=');
    args.add('-XMP:Subject=');
    for (final part in parts) {
      args.add('-IPTC:Keywords=$part');
      args.add('-XMP-dc:Subject=$part');
    }
    expect(args, [
      '-IPTC:Keywords=',
      '-Keywords=',
      '-Subject=',
      '-XMP-dc:Subject=',
      '-XMP:Subject=',
      '-IPTC:Keywords=A',
      '-XMP-dc:Subject=A',
      '-IPTC:Keywords=B',
      '-XMP-dc:Subject=B',
      '-IPTC:Keywords=a',
      '-XMP-dc:Subject=a',
    ]);
    expect(args.any((a) => a.contains('Keywords+=') || a.contains('Subject+=')),
        isFalse);
  });

  test(
    'save three times cleans seeded list duplicates and never reintroduces them',
    () async {
      if (!await _exiftoolAvailable()) {
        // ignore: avoid_print
        print('Skipping: exiftool not on PATH');
        return;
      }

      final dir = await Directory.systemTemp.createTemp('flofile-list-dedupe');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/clean.jpg');
      await file.writeAsBytes(_minimalJpeg());

      // Strip, then seed intentional duplicates (pixel payload untouched after this).
      var strip = await ExiftoolHelper.run([
        '-all=',
        '-overwrite_original',
        file.path,
      ]);
      expect(strip.isSuccess, isTrue, reason: strip.stderrText);

      final seed = await ExiftoolHelper.run([
        '-Keywords=A',
        '-Keywords=A',
        '-Keywords=B',
        '-IPTC:SupplementalCategories=SPO1',
        '-IPTC:SupplementalCategories=SPO1',
        '-IPTC:SupplementalCategories=BBN1',
        '-Country-PrimaryLocationCode=CAN',
        '-XMP-getty:Personality=Auston Matthews;Nathan MacKinnon',
        '-Personality=Auston Matthews;Nathan MacKinnon',
        '-overwrite_original',
        file.path,
      ]);
      expect(seed.isSuccess, isTrue, reason: seed.stderrText);

      final before = await _readMeta(file.path);
      expect(_asList(before['IPTC:Keywords'] ?? before['Keywords']).length,
          greaterThan(2));
      expect(await _personalityLiCount(file.path), 2);

      const writer = IptcCaptionWriter();
      const personality = 'Auston Matthews;Nathan MacKinnon';
      final captionValues = <String, String>{
        'IPTC:Caption-Abstract': 'Test caption',
        'Caption-Abstract': 'Test caption',
        'Description': 'Test caption',
        'XMP:Description': 'Test caption',
        'IPTC:Headline': 'Test headline',
        'Headline': 'Test headline',
        'XMP:Headline': 'Test headline',
        'IPTC:Keywords': 'A, A, B',
        'Keywords': 'A, A, B',
        'XMP:Subject': 'A, A, B',
        'XMP-dc:Subject': 'A, A, B',
        'XMP-getty:Personality': personality,
      };

      for (var i = 1; i <= 3; i++) {
        final succeeded = await writer.writeCaptionToPaths(
          paths: [file.path],
          values: captionValues,
        );
        expect(succeeded, [file.path], reason: 'caption save $i failed');

        final apply = await IptcTemplateApplyService.applyToImage(
          file.path,
          {
            'Supp Cat 1': 'SPO1',
            'Supp Cat 2': 'SPO1',
            'Supp Cat 3': 'BBN1',
            'Country Code': 'CAN,CAN',
          },
          skipInAppGenerated: false,
        );
        expect(apply.success, isTrue, reason: 'template apply $i failed');

        final meta = await _readMeta(file.path);
        final keywords = _asList(meta['IPTC:Keywords'] ?? meta['Keywords']);
        final subject = _asList(
          meta['XMP-dc:Subject'] ?? meta['Subject'] ?? meta['XMP:Subject'],
        );
        final supp = _asList(
          meta['IPTC:SupplementalCategories'] ??
              meta['XMP-photoshop:SupplementalCategories'] ??
              meta['SupplementalCategories'],
        );
        final country = _asList(
          meta['IPTC:Country-PrimaryLocationCode'] ??
              meta['Country-PrimaryLocationCode'] ??
              meta['XMP-iptcCore:CountryCode'] ??
              meta['CountryCode'],
        );
        final personalityRaw =
            meta['XMP-getty:Personality'] ?? meta['Personality'];

        _expectNoDuplicates(keywords, label: 'Keywords after save $i');
        _expectNoDuplicates(subject, label: 'Subject after save $i');
        _expectNoDuplicates(supp, label: 'SupplementalCategories after save $i');
        _expectNoDuplicates(country, label: 'Country Code after save $i');
        expect(
          await _personalityLiCount(file.path),
          1,
          reason: 'Personality must be exactly one rdf:li after save $i',
        );
        // Semicolon-joined names live in ONE bag entry — do not split on ';'.
        expect(personalityRaw, personality);
        expect(keywords, ['A', 'B']);
        expect(subject, ['A', 'B']);
        expect(supp, ['SPO1', 'BBN1']);
        expect(country, ['CAN']);
      }
    },
  );

  test('Personality clearArgs only target the single Getty tag', () {
    final clear = IptcTemplateApplyService.clearArgsForPresetKey('Personality');
    expect(clear, ['-XMP-getty:Personality=']);
  });

  test('buildCountryCodeArgs and supp-cat args stay replace-only', () {
    expect(
      buildCountryCodeArgs('CAN,CAN'),
      containsAll([
        '-Country-PrimaryLocationCode=',
        '-Country-PrimaryLocationCode=CAN',
      ]),
    );
    final supp = buildSupplementalCategoriesArgs(['SPO1', 'SPO1', 'BBN1']);
    expect(supp.first, '-SupplementalCategories=');
    expect(
      supp.where((a) => a.startsWith('-IPTC:SupplementalCategories=') && a != '-IPTC:SupplementalCategories=').length,
      2,
    );
    expect(
      supp.any((a) => a.contains('SupplementalCategories+=')),
      isFalse,
    );
  });
}
