import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../utils/exiftool_helper.dart';
import 'caption_metadata_writer.dart';

/// One semantic field that differed between two writer outputs.
class MetadataFieldDiff {
  const MetadataFieldDiff({
    required this.field,
    required this.left,
    required this.right,
  });

  final String field;
  final String left;
  final String right;

  @override
  String toString() => '$field: left=$left right=$right';
}

/// Result of writing the same tags with two writers onto copies of one JPEG.
class MetadataCompareReport {
  const MetadataCompareReport({
    required this.leftWriterId,
    required this.rightWriterId,
    required this.diffs,
    required this.leftPath,
    required this.rightPath,
  });

  final String leftWriterId;
  final String rightWriterId;
  final List<MetadataFieldDiff> diffs;
  final String leftPath;
  final String rightPath;

  bool get isMatch => diffs.isEmpty;

  String summarize() {
    if (isMatch) {
      return 'OK: $leftWriterId == $rightWriterId (${_compareFields.length} fields)';
    }
    final buf = StringBuffer(
      'DIFF: $leftWriterId vs $rightWriterId (${diffs.length} fields)\n',
    );
    for (final d in diffs) {
      buf.writeln('  - $d');
    }
    return buf.toString();
  }
}

/// Canonical fields compared after each writer run (ExifTool `-j -G1` keys).
const List<String> _compareFields = [
  'IPTC:Caption-Abstract',
  'IPTC:Headline',
  'IPTC:Keywords',
  'XMP-dc:Subject',
  'XMP-getty:Personality',
  'IPTC:By-line',
  'XMP-dc:Creator',
  'IPTC:By-lineTitle',
  'IPTC:Writer-Editor',
  'XMP-photoshop:CaptionWriter',
  'IPTC:CopyrightNotice',
  'XMP-dc:Rights',
  'IPTC:Credit',
  'IPTC:Source',
  'IPTC:OriginalTransmissionReference',
  'IPTC:Category',
  'IPTC:SupplementalCategories',
  'XMP-photoshop:SupplementalCategories',
  'IPTC:ObjectName',
  'IPTC:SpecialInstructions',
  'IPTC:City',
  'IPTC:Sub-location',
  'IPTC:Province-State',
  'IPTC:Country-PrimaryLocationName',
  'IPTC:Country-PrimaryLocationCode',
  'XMP-iptcCore:CountryCode',
  'IPTC:Urgency',
];

/// Writes [values] with both writers onto copies of [sourceJpeg] and diffs
/// ExifTool reads of the result. Pixel bytes past SOS are not compared here —
/// the Dart writer guarantees SOS→EOI identity; ExifTool `-P` preserves times.
Future<MetadataCompareReport> compareMetadataWriters({
  required Uint8List sourceJpeg,
  required Map<String, String> values,
  required CaptionMetadataWriter left,
  required CaptionMetadataWriter right,
  Directory? workDir,
  List<String>? fields,
}) async {
  final dir = workDir ??
      await Directory.systemTemp.createTemp('flofile-meta-compare');
  final leftFile = File('${dir.path}/${left.writerId}.jpg');
  final rightFile = File('${dir.path}/${right.writerId}.jpg');
  await leftFile.writeAsBytes(sourceJpeg);
  await rightFile.writeAsBytes(sourceJpeg);

  final leftOk = await left.writeCaptionToPaths(
    paths: [leftFile.path],
    values: values,
  );
  final rightOk = await right.writeCaptionToPaths(
    paths: [rightFile.path],
    values: values,
  );
  if (leftOk.isEmpty || rightOk.isEmpty) {
    return MetadataCompareReport(
      leftWriterId: left.writerId,
      rightWriterId: right.writerId,
      leftPath: leftFile.path,
      rightPath: rightFile.path,
      diffs: [
        MetadataFieldDiff(
          field: '_write',
          left: leftOk.isEmpty ? 'FAILED' : 'ok',
          right: rightOk.isEmpty ? 'FAILED' : 'ok',
        ),
      ],
    );
  }

  final compareKeys = fields ?? _compareFields;
  final leftMeta = await _readFields(leftFile.path, compareKeys);
  final rightMeta = await _readFields(rightFile.path, compareKeys);

  final diffs = <MetadataFieldDiff>[];
  for (final key in compareKeys) {
    final a = _normalize(leftMeta[key]);
    final b = _normalize(rightMeta[key]);
    if (a != b) {
      diffs.add(MetadataFieldDiff(field: key, left: a, right: b));
    }
  }

  return MetadataCompareReport(
    leftWriterId: left.writerId,
    rightWriterId: right.writerId,
    leftPath: leftFile.path,
    rightPath: rightFile.path,
    diffs: diffs,
  );
}

/// Asserts SOS→EOI bytes are identical (Dart writer must never touch pixels).
bool jpegEntropyPayloadEqual(Uint8List a, Uint8List b) {
  final ia = _sosIndex(a);
  final ib = _sosIndex(b);
  if (ia < 0 || ib < 0) return false;
  if (a.length - ia != b.length - ib) return false;
  for (var i = 0; i < a.length - ia; i++) {
    if (a[ia + i] != b[ib + i]) return false;
  }
  return true;
}

int _sosIndex(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xDA) return i;
  }
  return -1;
}

Future<Map<String, dynamic>> _readFields(
  String path,
  List<String> fields,
) async {
  final args = <String>[
    '-j',
    '-a',
    '-G1',
    '-struct',
    ...fields.map((f) => '-$f'),
    path,
  ];
  final proc = await ExiftoolHelper.run(args);
  if (!proc.isSuccess) {
    throw StateError('exiftool read failed: ${proc.stderrText}');
  }
  final decoded = jsonDecode(proc.stdoutText);
  if (decoded is! List || decoded.isEmpty) return {};
  return Map<String, dynamic>.from(decoded.first as Map);
}

String _normalize(dynamic raw) {
  if (raw == null) return '';
  // ExifTool may return a List or a single comma-joined string; treat both as
  // a list. Dedupe consecutive alias stacks (e.g. By-lineTitle written twice).
  final parts = <String>[];
  final seen = <String>{};
  void add(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    if (seen.add(t)) parts.add(t);
  }

  if (raw is List) {
    for (final e in raw) {
      for (final p in e.toString().split(RegExp(r'[,;|]'))) {
        add(p);
      }
    }
  } else {
    for (final p in raw.toString().split(RegExp(r'[,;|]'))) {
      add(p);
    }
  }
  return parts.join('|');
}
