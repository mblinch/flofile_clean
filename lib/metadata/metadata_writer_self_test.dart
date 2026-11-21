import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../screens/caption_v2/data/iptc_caption_writer.dart';
import '../utils/exiftool_helper.dart';
import 'caption_metadata_writer.dart';
import 'jpeg/dart_jpeg_caption_writer.dart';
import 'metadata_compare.dart';
import 'template_tag_map.dart';

/// Result of an in-app / CI metadata writer self-test.
class MetadataWriterSelfTestResult {
  const MetadataWriterSelfTestResult({
    required this.passed,
    required this.lines,
  });

  final bool passed;
  final List<String> lines;

  String get report => lines.join('\n');
}

/// Runs ExifTool vs Dart JPEG compare checks (desktop; needs exiftool on PATH).
///
/// Used by Admin → Metadata Writer and by automated tests. Does not change
/// production write paths.
class MetadataWriterSelfTest {
  MetadataWriterSelfTest._();

  static Uint8List minimalJpeg() {
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

  static Future<bool> exiftoolAvailable() async {
    final which = await Process.run('which', ['exiftool']);
    return which.exitCode == 0 && (which.stdout as String).trim().isNotEmpty;
  }

  /// Full suite: list-field dedupe (both writers) + 20-field parity compare.
  static Future<MetadataWriterSelfTestResult> run() async {
    final lines = <String>[];
    var passed = true;

    void ok(String msg) => lines.add('PASS  $msg');
    void fail(String msg) {
      passed = false;
      lines.add('FAIL  $msg');
    }

    lines.add('Metadata writer self-test');
    lines.add('Started: ${DateTime.now().toIso8601String()}');
    lines.add('');

    if (!await exiftoolAvailable()) {
      fail('exiftool not on PATH — install with: brew install exiftool');
      return MetadataWriterSelfTestResult(passed: false, lines: lines);
    }
    ok('exiftool found');

    const exiftool = IptcCaptionWriter();
    const dartJpeg = DartJpegCaptionWriter();

    for (final writer in <CaptionMetadataWriter>[exiftool, dartJpeg]) {
      try {
        await _runListFieldDedupe(writer);
        ok('list-field dedupe (${writer.writerId})');
      } catch (e) {
        fail('list-field dedupe (${writer.writerId}): $e');
      }
    }

    try {
      final report = await _runTwentyFieldCompare(exiftool, dartJpeg);
      lines.add(report.summarize().trimRight());
      if (report.isMatch) {
        ok('20-field template parity');
      } else {
        fail('20-field template parity');
      }
    } catch (e) {
      fail('20-field template parity: $e');
    }

    lines.add('');
    lines.add(passed ? 'ALL PASSED' : 'FAILED');
    return MetadataWriterSelfTestResult(passed: passed, lines: lines);
  }

  static Future<void> _runListFieldDedupe(CaptionMetadataWriter writer) async {
    final dir =
        await Directory.systemTemp.createTemp('flofile-admin-list-dedupe');
    try {
      final file = File('${dir.path}/${writer.writerId}.jpg');
      await file.writeAsBytes(minimalJpeg());

      final strip = await ExiftoolHelper.run([
        '-all=',
        '-overwrite_original',
        file.path,
      ]);
      if (!strip.isSuccess) {
        throw StateError('strip failed: ${strip.stderrText}');
      }

      final seed = await ExiftoolHelper.run([
        '-Keywords=A',
        '-Keywords=A',
        '-Keywords=B',
        '-IPTC:SupplementalCategories=SPO1',
        '-IPTC:SupplementalCategories=SPO1',
        '-IPTC:SupplementalCategories=BBN1',
        '-Country-PrimaryLocationCode=CAN',
        '-XMP-getty:Personality=Auston Matthews;Nathan MacKinnon',
        '-overwrite_original',
        file.path,
      ]);
      if (!seed.isSuccess) {
        throw StateError('seed failed: ${seed.stderrText}');
      }

      const personality = 'Auston Matthews;Nathan MacKinnon';
      final values = <String, String>{
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

      final before = await file.readAsBytes();
      for (var i = 1; i <= 3; i++) {
        final okPaths = await writer.writeCaptionToPaths(
          paths: [file.path],
          values: values,
        );
        if (okPaths.length != 1) {
          throw StateError('write $i failed');
        }
        final after = await file.readAsBytes();
        if (!jpegEntropyPayloadEqual(before, after)) {
          throw StateError('SOS→EOI changed on save $i');
        }
        final meta = await _readListMeta(file.path);
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
        if (keywords.join('|') != 'A|B') {
          throw StateError('keywords=$keywords');
        }
        if (subject.join('|') != 'A|B') {
          throw StateError('subject=$subject');
        }
        if (supp.join('|') != 'SPO1|BBN1') {
          throw StateError('supp=$supp');
        }
        if (country.join('|') != 'CAN') {
          throw StateError('country=$country');
        }
        if (await _personalityLiCount(file.path) != 1) {
          throw StateError('personality li count != 1');
        }
        final personalityRaw =
            meta['XMP-getty:Personality'] ?? meta['Personality'];
        if (personalityRaw?.toString() != personality) {
          throw StateError('personality=$personalityRaw');
        }
      }
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<MetadataCompareReport> _runTwentyFieldCompare(
    CaptionMetadataWriter left,
    CaptionMetadataWriter right,
  ) async {
    final dir = await Directory.systemTemp.createTemp('flofile-admin-20field');
    final stripFile = File('${dir.path}/strip.jpg');
    await stripFile.writeAsBytes(minimalJpeg());
    final strip = await ExiftoolHelper.run([
      '-all=',
      '-overwrite_original',
      stripFile.path,
    ]);
    if (!strip.isSuccess) {
      throw StateError('strip failed: ${strip.stderrText}');
    }
    final clean = await stripFile.readAsBytes();
    final values = templatePanelToTagMap(kTwentyFieldTemplateFixture);
    // compareMetadataWriters owns [dir] for the duration of the write+read.
    // Leave the temp folder for the OS; do not delete while ExifTool may still
    // hold paths (and not before the report is fully built).
    return compareMetadataWriters(
      sourceJpeg: clean,
      values: values,
      left: left,
      right: right,
      workDir: dir,
    );
  }

  static Future<Map<String, dynamic>> _readListMeta(String path) async {
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
    if (!proc.isSuccess) {
      throw StateError(proc.stderrText);
    }
    final decoded = jsonDecode(proc.stdoutText);
    if (decoded is! List || decoded.isEmpty) {
      throw StateError('empty exiftool json');
    }
    return Map<String, dynamic>.from(decoded.first as Map);
  }

  static Future<int> _personalityLiCount(String path) async {
    final proc = await ExiftoolHelper.run(['-XMP', '-b', path]);
    if (!proc.isSuccess) return 0;
    final bag = RegExp(
      r'<GettyImagesGIFT:Personality>\s*<rdf:Bag>(.*?)</rdf:Bag>\s*</GettyImagesGIFT:Personality>',
      dotAll: true,
    ).firstMatch(proc.stdoutText);
    if (bag == null) return 0;
    return RegExp(r'<rdf:li>').allMatches(bag.group(1)!).length;
  }

  static List<String> _asList(dynamic raw) {
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
}
