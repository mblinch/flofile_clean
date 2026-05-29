import 'dart:convert';
import 'dart:io';

import '../utils/exiftool_helper.dart';

class _GettyIimParseResult {
  const _GettyIimParseResult({required this.values, required this.skippedCount});

  final Map<String, String> values;
  final int skippedCount;
}

class _IimLineParse {
  const _IimLineParse({required this.dataset, required this.value});

  final int dataset;
  final String value;
}

/// Result of importing an external IPTC template (Getty .txt, Photo Mechanic .xmp, etc.).
class IptcTemplateImportResult {
  const IptcTemplateImportResult({
    required this.values,
    this.sourceLabel,
    this.skippedFieldCount = 0,
  });

  final Map<String, String> values;
  final String? sourceLabel;
  final int skippedFieldCount;

  bool get isEmpty => values.isEmpty;
}

/// Parses Getty GIFT / IIM text templates and XMP sidecars into FloFile panel keys.
class IptcTemplateImportService {
  IptcTemplateImportService._();

  static const _supportedExtensions = ['txt', 'xmp', 'jpg', 'jpeg'];

  /// IPTC-IIM dataset → FloFile startup panel storage key.
  static const Map<int, String> _iimDatasetToPanelKey = {
    10: 'Urgency',
    15: 'Category',
    25: 'Keywords',
    40: 'Special Instructions',
    55: 'Time and Date',
    80: 'Creator',
    85: 'Job Title',
    90: 'City',
    92: 'Stadium',
    95: 'Province/State',
    100: 'Country Code',
    101: 'Country',
    103: 'MEID',
    105: 'Headline',
    110: 'Credit',
    115: 'Source',
    116: 'Copyright',
    118: 'Description Writers',
    120: 'Caption',
  };

  static Future<IptcTemplateImportResult?> importFromPath(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    if (!_supportedExtensions.contains(ext)) {
      throw FormatException(
        'Unsupported file type ".$ext". Use .txt (Getty), .xmp, or .jpg.',
      );
    }

    if (ext == 'txt') {
      final content = await File(filePath).readAsString();
      final parsed = parseGettyIimText(content);
      return IptcTemplateImportResult(
        values: parsed.values,
        sourceLabel: 'Getty template',
        skippedFieldCount: parsed.skippedCount,
      );
    }

    final meta = await _readMetadataViaExiftool(filePath);
    if (meta == null) {
      throw Exception('Could not read metadata from file.');
    }
    final values = panelValuesFromExiftool(meta);
    return IptcTemplateImportResult(
      values: values,
      sourceLabel: ext == 'xmp' ? 'XMP template' : 'Image metadata',
    );
  }

  /// Parses `2:dataset:maxBytes:value` lines (Getty GIFT / standard IIM export).
  static _GettyIimParseResult parseGettyIimText(String content) {
    final values = <String, String>{};
    final supplemental = <String>[];
    var skipped = 0;

    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parsed = _parseIimLine(trimmed);
      if (parsed == null) {
        skipped++;
        continue;
      }

      final dataset = parsed.dataset;
      final value = parsed.value.trim();
      if (value.isEmpty) continue;

      if (dataset == 20) {
        supplemental.add(value);
        continue;
      }

      final key = _iimDatasetToPanelKey[dataset];
      if (key == null) {
        skipped++;
        continue;
      }

      if (key == 'Time and Date') {
        values[key] = _formatIimDate(value);
      } else if (key == 'Urgency') {
        values[key] = value;
      } else {
        values[key] = value;
      }
    }

    for (var i = 0; i < supplemental.length && i < 3; i++) {
      values['Supp Cat ${i + 1}'] = supplemental[i];
    }

    return _GettyIimParseResult(values: values, skippedCount: skipped);
  }

  static _IimLineParse? _parseIimLine(String line) {
    // Format: 2:dataset:maxBytes:value (value may contain colons)
    final match = RegExp(r'^2:(\d+):\d+:(.*)$').firstMatch(line);
    if (match == null) return null;
    final dataset = int.tryParse(match.group(1)!);
    if (dataset == null) return null;
    return _IimLineParse(dataset: dataset, value: match.group(2)!);
  }

  static String _formatIimDate(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) {
      return '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}';
    }
    return raw;
  }

  static Future<Map<String, dynamic>?> _readMetadataViaExiftool(
    String filePath,
  ) async {
    final proc = await ExiftoolHelper.run(['-a', '-j', ...applyCompareTags, filePath]);
    if (!proc.isSuccess) return null;
    final List data = jsonDecode(proc.stdoutText);
    if (data.isEmpty) return null;
    return data.first as Map<String, dynamic>;
  }

  /// Tags read before apply-on-import to detect unchanged fields.
  static const applyCompareTags = [
      '-IPTC:Description',
      '-Description',
      '-IPTC:By-line',
      '-By-line',
      '-Creator',
      '-XMP-dc:Creator',
      '-XMP:Creator',
      '-Artist',
      '-EXIF:Artist',
      '-XMP-tiff:Artist',
      '-IPTC:OriginalTransmissionReference',
      '-OriginalTransmissionReference',
      '-TransmissionReference',
      '-MEID',
      '-CaptionWriter',
      '-XMP-photoshop:CaptionWriter',
      '-Writer-Editor',
      '-IPTC:Writer-Editor',
      '-IPTC:By-lineTitle',
      '-By-lineTitle',
      '-AuthorsPosition',
      '-IPTC:CopyrightNotice',
      '-CopyrightNotice',
      '-Copyright',
      '-XMP:Rights',
      '-XMP-dc:Rights',
      '-IPTC:Credit',
      '-Credit',
      '-IPTC:Source',
      '-Source',
      '-XMP:Source',
      '-IPTC:Headline',
      '-Headline',
      '-XMP:Title',
      '-IPTC:Keywords',
      '-Keywords',
      '-Subject',
      '-IPTC:Category',
      '-Category',
      '-IPTC:SupplementalCategories',
      '-SupplementalCategories',
      '-XMP-photoshop:SupplementalCategories',
      '-IPTC:ObjectName',
      '-ObjectName',
      '-IPTC:SubLocation',
      '-SubLocation',
      '-Sub-location',
      '-IPTC:Sub-location',
      '-Location',
      '-XMP:Location',
      '-XMP-iptcCore:Location',
      '-LocationShownSublocation',
      '-LocationCreatedSublocation',
      '-IPTC:City',
      '-City',
      '-IPTC:ProvinceState',
      '-ProvinceState',
      '-Province-State',
      '-IPTC:Province-State',
      '-State',
      '-XMP:State',
      '-XMP-photoshop:State',
      '-IPTC:CountryPrimaryLocationName',
      '-IPTC:Country-PrimaryLocationName',
      '-CountryPrimaryLocationName',
      '-Country-PrimaryLocationName',
      '-Country',
      '-XMP:Country',
      '-XMP-photoshop:Country',
      '-IPTC:CountryPrimaryLocationCode',
      '-IPTC:Country-PrimaryLocationCode',
      '-CountryPrimaryLocationCode',
      '-Country-PrimaryLocationCode',
      '-CountryCode',
      '-XMP:CountryCode',
      '-XMP-iptcCore:CountryCode',
      '-IPTC:SpecialInstructions',
      '-SpecialInstructions',
      '-XMP:Instructions',
      '-XMP-photoshop:Instructions',
      '-Instructions',
      '-XMP-getty:Personality',
      '-Personality',
      '-XMP:Personality',
      '-IPTC:Urgency',
      '-Urgency',
      '-XMP-photomech:CreatorIdentity',
      '-XMP:CreatorIdentity',
      '-CreatorIdentity',
    ];

  /// Reads metadata from [filePath] for apply skip-if-unchanged checks.
  static Future<Map<String, dynamic>?> readMetadata(String filePath) =>
      _readMetadataViaExiftool(filePath);

  /// One ExifTool pass for many files (used before batch IPTC apply on import).
  static Future<Map<String, Map<String, dynamic>>> readMetadataBatch(
    List<String> filePaths,
  ) async {
    if (filePaths.isEmpty) return {};
    final proc = await ExiftoolHelper.run([
      '-a',
      '-j',
      ...applyCompareTags,
      ...filePaths,
    ]);
    if (!proc.isSuccess) return {};
    try {
      final List data = jsonDecode(proc.stdoutText);
      final out = <String, Map<String, dynamic>>{};
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final source = item['SourceFile']?.toString();
          if (source != null && source.isNotEmpty) {
            out[source] = item;
          }
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Maps ExifTool JSON (from .xmp, .jpg, etc.) to startup panel storage keys.
  static Map<String, String> panelValuesFromExiftool(Map<String, dynamic> meta) {
    final supplemental = _supplementalCategories(meta);
    final out = <String, String>{
      'Creator': _first(meta, [
        'IPTC:By-line',
        'By-line',
        'Creator',
        'XMP-dc:Creator',
        'XMP:Creator',
        'Artist',
        'EXIF:Artist',
        'XMP-tiff:Artist',
      ]),
      'MEID': _first(meta, [
        'IPTC:OriginalTransmissionReference',
        'OriginalTransmissionReference',
        'TransmissionReference',
        'MEID',
        'JobID',
      ]),
      'Description Writers': _first(meta, [
        'CaptionWriter',
        'XMP-photoshop:CaptionWriter',
        'IPTC:Writer-Editor',
        'Writer-Editor',
      ]),
      'Job Title': _first(meta, [
        'IPTC:By-lineTitle',
        'By-lineTitle',
        'AuthorsPosition',
        "Creator's Job Title",
      ]),
      'Copyright': _first(meta, [
        'IPTC:CopyrightNotice',
        'CopyrightNotice',
        'Copyright',
        'XMP:Rights',
        'XMP-dc:Rights',
      ]),
      'Credit': _first(meta, ['IPTC:Credit', 'Credit']),
      'Source': _first(meta, ['IPTC:Source', 'Source', 'XMP:Source']),
      'Headline': _first(meta, ['IPTC:Headline', 'Headline']),
      'Keywords': _keywords(meta),
      'Personality': _first(meta, [
        'XMP-getty:Personality',
        'Personality',
        'XMP:Personality',
      ]),
      'Caption': _first(meta, [
        'IPTC:Description',
        'Description',
        'XMP:Description',
        'XMP-dc:Description',
        'Caption-Abstract',
        'IPTC:Caption-Abstract',
      ]),
      'Object Name': _first(meta, [
        'IPTC:ObjectName',
        'ObjectName',
        'XMP:Title',
      ]),
      'Category': _first(meta, ['IPTC:Category', 'Category']),
      'Special Instructions': _first(meta, [
        'IPTC:SpecialInstructions',
        'SpecialInstructions',
        'XMP-photoshop:Instructions',
        'XMP:Instructions',
        'Instructions',
      ]),
      'Stadium': _first(meta, [
        'IPTC:SubLocation',
        'IPTC:Sub-location',
        'SubLocation',
        'Sub-location',
        'Location',
        'XMP:Location',
        'XMP-iptcCore:Location',
        'LocationShownSublocation',
        'LocationCreatedSublocation',
      ]),
      'City': _first(meta, ['IPTC:City', 'City']),
      'Province/State': _first(meta, [
        'IPTC:ProvinceState',
        'IPTC:Province-State',
        'ProvinceState',
        'Province-State',
        'State',
        'XMP:State',
        'XMP-photoshop:State',
      ]),
      'Country': _first(meta, [
        'IPTC:CountryPrimaryLocationName',
        'IPTC:Country-PrimaryLocationName',
        'CountryPrimaryLocationName',
        'Country-PrimaryLocationName',
        'Country',
        'XMP:Country',
        'XMP-photoshop:Country',
      ]),
      'Country Code': _first(meta, [
        'IPTC:CountryPrimaryLocationCode',
        'IPTC:Country-PrimaryLocationCode',
        'CountryPrimaryLocationCode',
        'Country-PrimaryLocationCode',
        'CountryCode',
        'XMP:CountryCode',
        'XMP-iptcCore:CountryCode',
      ]),
      "Creator's Identity": _firstScalar(meta, [
        'XMP-photomech:CreatorIdentity',
        'XMP:CreatorIdentity',
        'CreatorIdentity',
      ]),
      'Time and Date': _formatExifDateTime(meta),
      'Urgency': _first(meta, ['IPTC:Urgency', 'Urgency']),
    };

    if (supplemental.isNotEmpty) out['Supp Cat 1'] = supplemental[0];
    if (supplemental.length > 1) out['Supp Cat 2'] = supplemental[1];
    if (supplemental.length > 2) out['Supp Cat 3'] = supplemental[2];

    out.removeWhere((_, v) => v.trim().isEmpty);
    return out;
  }

  static String _first(Map<String, dynamic> meta, List<String> keys) {
    for (final key in keys) {
      final raw = meta[key];
      if (raw == null) continue;
      if (raw is List) {
        final parts = raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(', ');
      } else {
        final v = raw.toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  /// Like [_first] but uses only the first list item (avoids duplicate bag values).
  static String _firstScalar(Map<String, dynamic> meta, List<String> keys) {
    for (final key in keys) {
      final raw = meta[key];
      if (raw == null) continue;
      if (raw is List) {
        for (final item in raw) {
          final v = item.toString().trim();
          if (v.isNotEmpty) return v;
        }
      } else {
        final v = raw.toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static String _keywords(Map<String, dynamic> meta) {
    final raw = meta['IPTC:Keywords'] ??
        meta['Keywords'] ??
        meta['Subject'] ??
        meta['XMP:Subject'];
    if (raw == null) return '';
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .join(', ');
    }
    var s = raw.toString().trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1);
    }
    return s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .join(', ');
  }

  static List<String> _supplementalCategories(Map<String, dynamic> meta) {
    final values = <String>[];
    void collect(dynamic v) {
      if (v == null) return;
      if (v is List) {
        values.addAll(
          v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        );
      } else {
        final s = v.toString().trim();
        if (s.contains(',')) {
          values.addAll(
            s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
          );
        } else if (s.isNotEmpty) {
          values.add(s);
        }
      }
    }

    collect(meta['IPTC:SupplementalCategories']);
    collect(meta['SupplementalCategories']);
    collect(meta['XMP-photoshop:SupplementalCategories']);

    final seen = <String>{};
    return values.where((e) => seen.add(e)).toList(growable: false);
  }

  static String _formatExifDateTime(Map<String, dynamic> meta) {
    final raw = _first(meta, ['DateTimeOriginal', 'CreateDate', 'ModifyDate']);
    if (raw.isEmpty) return '';
    try {
      final parts = raw.split(' ');
      if (parts.isEmpty) return raw;
      final datePart = parts[0].replaceAll(':', '-');
      if (parts.length < 2) return datePart;
      return '$datePart ${parts[1]}';
    } catch (_) {
      return raw;
    }
  }
}
