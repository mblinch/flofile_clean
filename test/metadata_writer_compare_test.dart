import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/metadata/caption_metadata_writer.dart';
import 'package:quick_cap/metadata/jpeg/dart_jpeg_caption_writer.dart';
import 'package:quick_cap/metadata/metadata_compare.dart';
import 'package:quick_cap/metadata/metadata_writer_self_test.dart';
import 'package:quick_cap/metadata/template_tag_map.dart';
import 'package:quick_cap/screens/caption_v2/data/iptc_caption_writer.dart';
import 'package:quick_cap/services/iptc_template_import_service.dart';
import 'package:quick_cap/utils/exiftool_helper.dart';

/// Minimal valid 1×1 JPEG — metadata only; never mutate pixel payload.
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
    '-Caption-Abstract',
    '-Headline',
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

  const exiftool = IptcCaptionWriter();
  const dartJpeg = DartJpegCaptionWriter();

  for (final writer in [exiftool, dartJpeg]) {
    group('list-field dedupe (${writer.writerId})', () {
      test(
        'save three times cleans seeded list duplicates and never reintroduces them',
        () async {
          if (!await _exiftoolAvailable()) {
            // ignore: avoid_print
            print('Skipping: exiftool not on PATH (needed to seed/read)');
            return;
          }

          final dir =
              await Directory.systemTemp.createTemp('flofile-list-dedupe');
          addTearDown(() => dir.delete(recursive: true));
          final file = File('${dir.path}/${writer.writerId}.jpg');
          await file.writeAsBytes(_minimalJpeg());

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
            'SupplementalCategories1': 'SPO1',
            'SupplementalCategories2': 'SPO1',
            'SupplementalCategories3': 'BBN1',
            'IPTC:Country-PrimaryLocationCode': 'CAN,CAN',
            'XMP-iptcCore:CountryCode': 'CAN,CAN',
          };

          final beforeBytes = await file.readAsBytes();

          for (var i = 1; i <= 3; i++) {
            final succeeded = await writer.writeCaptionToPaths(
              paths: [file.path],
              values: captionValues,
            );
            expect(succeeded, [file.path], reason: 'caption save $i failed');

            final afterBytes = await file.readAsBytes();
            expect(
              jpegEntropyPayloadEqual(beforeBytes, afterBytes),
              isTrue,
              reason: '${writer.writerId} must not touch SOS→EOI on save $i',
            );

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

            expect(keywords.toSet().length, keywords.length);
            expect(subject.toSet().length, subject.length);
            expect(supp.toSet().length, supp.length);
            expect(country.toSet().length, country.length);
            expect(await _personalityLiCount(file.path), 1);
            expect(personalityRaw, personality);
            expect(keywords, ['A', 'B']);
            expect(subject, ['A', 'B']);
            expect(supp, ['SPO1', 'BBN1']);
            expect(country, ['CAN']);
          }
        },
      );
    });
  }

  group('20-field template parity', () {
    test('exiftool and dart_jpeg match on every compared field', () async {
      if (!await _exiftoolAvailable()) {
        // ignore: avoid_print
        print('Skipping: exiftool not on PATH');
        return;
      }

      final dir = await Directory.systemTemp.createTemp('flofile-20field');
      addTearDown(() => dir.delete(recursive: true));

      final source = _minimalJpeg();
      final stripFile = File('${dir.path}/strip.jpg');
      await stripFile.writeAsBytes(source);
      final strip = await ExiftoolHelper.run([
        '-all=',
        '-overwrite_original',
        stripFile.path,
      ]);
      expect(strip.isSuccess, isTrue, reason: strip.stderrText);
      final clean = await stripFile.readAsBytes();

      final values = templatePanelToTagMap(kTwentyFieldTemplateFixture);
      expect(values.keys, isNotEmpty);

      final report = await compareMetadataWriters(
        sourceJpeg: clean,
        values: values,
        left: exiftool,
        right: dartJpeg,
        workDir: dir,
      );

      // ignore: avoid_print
      print(report.summarize());

      expect(
        report.isMatch,
        isTrue,
        reason: report.summarize(),
      );

      // Panel-level check: both files surface the same startup panel values.
      final leftPanel = IptcTemplateImportService.panelValuesFromExiftool(
        (await IptcTemplateImportService.readMetadata(report.leftPath))!,
      );
      final rightPanel = IptcTemplateImportService.panelValuesFromExiftool(
        (await IptcTemplateImportService.readMetadata(report.rightPath))!,
      );

      for (final key in kTwentyFieldTemplateFixture.keys) {
        final expected = kTwentyFieldTemplateFixture[key]!;
        if (key.startsWith('Supp Cat')) continue; // compared as list below
        if (key == 'Keywords') {
          expect(leftPanel['Keywords'], contains('Bo Bichette'));
          expect(rightPanel['Keywords'], contains('Bo Bichette'));
          continue;
        }
        if (key == 'Country Code') {
          expect(leftPanel['Country Code'], 'CAN');
          expect(rightPanel['Country Code'], 'CAN');
          continue;
        }
        expect(
          leftPanel[key] ?? leftPanel[_panelAlias(key)],
          expected,
          reason: 'exiftool panel $key',
        );
        expect(
          rightPanel[key] ?? rightPanel[_panelAlias(key)],
          expected,
          reason: 'dart_jpeg panel $key',
        );
      }

      expect(leftPanel['Supp Cat 1'], 'SPO');
      expect(rightPanel['Supp Cat 1'], 'SPO');
      expect(await _personalityLiCount(report.leftPath), 1);
      expect(await _personalityLiCount(report.rightPath), 1);

      final leftBytes = await File(report.leftPath).readAsBytes();
      final rightBytes = await File(report.rightPath).readAsBytes();
      expect(jpegEntropyPayloadEqual(clean, rightBytes), isTrue);
      // ExifTool also preserves entropy with -P / overwrite_original on JPEG.
      expect(jpegEntropyPayloadEqual(clean, leftBytes), isTrue);
    });
  });

  test('compare harness reports diffs when writers diverge', () async {
    if (!await _exiftoolAvailable()) return;

    final dir = await Directory.systemTemp.createTemp('flofile-compare-neg');
    addTearDown(() => dir.delete(recursive: true));

    final report = await compareMetadataWriters(
      sourceJpeg: _minimalJpeg(),
      values: {
        'IPTC:Headline': 'Left Only Headline',
        'Headline': 'Left Only Headline',
      },
      left: exiftool,
      right: const _NoopWriter(),
      workDir: dir,
      fields: const ['IPTC:Headline'],
    );
    expect(report.isMatch, isFalse);
    expect(report.diffs, isNotEmpty);
  });

  test('in-app self-test runner passes', () async {
    if (!await MetadataWriterSelfTest.exiftoolAvailable()) {
      // ignore: avoid_print
      print('Skipping: exiftool not on PATH');
      return;
    }
    final result = await MetadataWriterSelfTest.run();
    // ignore: avoid_print
    print(result.report);
    expect(result.passed, isTrue, reason: result.report);
  });
}

String? _panelAlias(String key) {
  if (key == 'Stadium') return 'Location';
  if (key == 'Job Title') return "Creator's Job Title";
  return null;
}

/// Writer that never writes — used to prove the compare harness surfaces diffs.
class _NoopWriter implements CaptionMetadataWriter {
  const _NoopWriter();

  @override
  String get writerId => 'noop';

  @override
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  }) async =>
      paths;
}
