import 'dart:io';
import 'dart:typed_data';

import '../caption_metadata_writer.dart';
import 'iptc_iim.dart';
import 'jpeg_segments.dart';
import 'photoshop_irb.dart';
import 'xmp_packet.dart';

/// Pure-Dart JPEG IPTC IIM + XMP writer (no ExifTool, no pixel re-encode).
///
/// Used in compare-mode tests. Production still uses ExifTool via
/// [IptcCaptionWriter].
class DartJpegCaptionWriter implements CaptionMetadataWriter {
  const DartJpegCaptionWriter();

  @override
  String get writerId => 'dart_jpeg';

  /// Case-sensitive dedupe, keeping first occurrence (same as ExifTool writer).
  static List<String> dedupeListValues(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) out.add(trimmed);
    }
    return out;
  }

  @override
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  }) async {
    if (paths.isEmpty || values.isEmpty) return const [];
    final succeeded = <String>[];
    for (final path in paths) {
      try {
        final ok = await writeToFile(path, values);
        if (ok) succeeded.add(path);
      } catch (_) {
        // Leave path out of succeeded.
      }
    }
    return succeeded;
  }

  /// Writes [values] into a JPEG file in place (temp file + rename).
  Future<bool> writeToFile(String path, Map<String, String> values) async {
    final lower = path.toLowerCase();
    if (!(lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.jpe'))) {
      return false;
    }
    final file = File(path);
    if (!await file.exists()) return false;
    final input = await file.readAsBytes();
    final output = writeToBytes(input, values);
    // Write via sibling temp + replace so a crash mid-write can't truncate the
    // JPEG. delete+rename avoids platforms that refuse rename-over-existing.
    final tmp = File('$path.flofile_meta_tmp');
    await tmp.writeAsBytes(output, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(path);
    return true;
  }

  /// Applies ExifTool-style tag map to JPEG bytes; returns new JPEG bytes.
  ///
  /// Pixel/entropy data (SOS→EOI) is copied unchanged.
  Uint8List writeToBytes(Uint8List jpegBytes, Map<String, String> values) {
    final jpeg = JpegSegments.parse(jpegBytes);
    final plan = _WritePlan.fromValues(values);

    // --- IPTC ---
    final existingApp13 = jpeg.readPhotoshopApp13Payload();
    final irb = existingApp13 != null
        ? PhotoshopIrb.parseApp13Payload(existingApp13)
        : PhotoshopIrb([]);
    final existingIptc = irb.iptcBytes();
    final iptc = existingIptc != null
        ? IptcIim.parse(existingIptc)
        : IptcIim();

    // Strip envelope CCS; encoder re-adds UTF-8.
    iptc.datasets.removeWhere((d) =>
        d.record == IptcIim.recordEnvelope &&
        d.dataset == IptcIim.dsCodedCharacterSet);

    if (plan.clearKeywords || plan.keywords != null) {
      iptc.setUtf8List(IptcIim.dsKeywords, plan.keywords ?? const []);
    }
    if (plan.clearSuppCats || plan.suppCats != null) {
      iptc.setUtf8List(
        IptcIim.dsSupplementalCategories,
        plan.suppCats ?? const [],
      );
    }

    void setOrClear(int ds, String? value, bool clear) {
      // clear+value means replace (clear then set), not clear-only.
      if (clear || value != null) {
        iptc.setUtf8Field(ds, value ?? '');
      }
    }

    setOrClear(IptcIim.dsCaption, plan.caption, plan.clearCaption);
    setOrClear(IptcIim.dsHeadline, plan.headline, plan.clearHeadline);
    setOrClear(IptcIim.dsByLine, plan.byLine, plan.clearByLine);
    setOrClear(IptcIim.dsByLineTitle, plan.byLineTitle, plan.clearByLineTitle);
    setOrClear(
        IptcIim.dsWriterEditor, plan.writerEditor, plan.clearWriterEditor);
    setOrClear(IptcIim.dsCopyright, plan.copyright, plan.clearCopyright);
    setOrClear(IptcIim.dsCredit, plan.credit, plan.clearCredit);
    setOrClear(IptcIim.dsSource, plan.source, plan.clearSource);
    setOrClear(
        IptcIim.dsTransmissionRef, plan.transmissionRef, plan.clearTransmissionRef);
    setOrClear(IptcIim.dsCategory, plan.category, plan.clearCategory);
    setOrClear(IptcIim.dsObjectName, plan.objectName, plan.clearObjectName);
    setOrClear(IptcIim.dsSpecialInstructions, plan.specialInstructions,
        plan.clearSpecialInstructions);
    setOrClear(IptcIim.dsCity, plan.city, plan.clearCity);
    setOrClear(IptcIim.dsSubLocation, plan.subLocation, plan.clearSubLocation);
    setOrClear(
        IptcIim.dsProvinceState, plan.provinceState, plan.clearProvinceState);
    setOrClear(IptcIim.dsCountryName, plan.countryName, plan.clearCountryName);
    setOrClear(IptcIim.dsCountryCode, plan.countryCode, plan.clearCountryCode);
    setOrClear(IptcIim.dsUrgency, plan.urgency, plan.clearUrgency);

    irb.setIptcBytes(iptc.encode());
    jpeg.setPhotoshopApp13(irb.encodeApp13Payload());

    // --- XMP ---
    final existingXmp = jpeg.readXmpXml();
    final xmp = existingXmp != null ? XmpPacket.parse(existingXmp) : XmpPacket();

    if (plan.clearKeywords || plan.keywords != null) {
      xmp.setList('subject', plan.keywords);
    }
    if (plan.clearSuppCats || plan.suppCats != null) {
      xmp.setList('supplementalCategories', plan.suppCats);
    }
    if (plan.clearPersonality || plan.personality != null) {
      xmp.setScalar('personality', plan.personality);
    }
    if (plan.clearCaption || plan.caption != null) {
      xmp.setScalar('description', plan.caption);
    }
    if (plan.clearHeadline || plan.headline != null) {
      xmp.setScalar('headline', plan.headline);
    }
    if (plan.clearByLine || plan.byLine != null) {
      if (plan.clearByLine) {
        xmp.setList('creator', const []);
      } else if (plan.byLine != null) {
        xmp.setList('creator', [plan.byLine!]);
      }
    }
    if (plan.clearWriterEditor || plan.writerEditor != null) {
      xmp.setScalar('captionWriter', plan.writerEditor);
    }
    if (plan.clearCopyright || plan.copyright != null) {
      xmp.setScalar('rights', plan.copyright);
    }
    if (plan.clearCredit || plan.credit != null) {
      xmp.setScalar('credit', plan.credit);
    }
    if (plan.clearSource || plan.source != null) {
      xmp.setScalar('source', plan.source);
    }
    if (plan.clearObjectName || plan.objectName != null) {
      xmp.setScalar('title', plan.objectName);
    }
    if (plan.clearSpecialInstructions || plan.specialInstructions != null) {
      xmp.setScalar('instructions', plan.specialInstructions);
    }
    if (plan.clearCity || plan.city != null) {
      xmp.setScalar('city', plan.city);
    }
    if (plan.clearSubLocation || plan.subLocation != null) {
      xmp.setScalar('location', plan.subLocation);
    }
    if (plan.clearProvinceState || plan.provinceState != null) {
      xmp.setScalar('state', plan.provinceState);
    }
    if (plan.clearCountryName || plan.countryName != null) {
      xmp.setScalar('country', plan.countryName);
    }
    if (plan.clearCountryCode || plan.countryCode != null) {
      xmp.setScalar('countryCode', plan.countryCode);
    }

    jpeg.setXmpApp1(xmp.encode());
    return jpeg.rebuild();
  }
}

class _WritePlan {
  _WritePlan();

  String? caption;
  String? headline;
  List<String>? keywords;
  String? personality;
  String? byLine;
  String? byLineTitle;
  String? writerEditor;
  String? copyright;
  String? credit;
  String? source;
  String? transmissionRef;
  String? category;
  List<String>? suppCats;
  String? objectName;
  String? specialInstructions;
  String? city;
  String? subLocation;
  String? provinceState;
  String? countryName;
  String? countryCode;
  String? urgency;

  bool clearCaption = false;
  bool clearHeadline = false;
  bool clearKeywords = false;
  bool clearPersonality = false;
  bool clearByLine = false;
  bool clearByLineTitle = false;
  bool clearWriterEditor = false;
  bool clearCopyright = false;
  bool clearCredit = false;
  bool clearSource = false;
  bool clearTransmissionRef = false;
  bool clearCategory = false;
  bool clearSuppCats = false;
  bool clearObjectName = false;
  bool clearSpecialInstructions = false;
  bool clearCity = false;
  bool clearSubLocation = false;
  bool clearProvinceState = false;
  bool clearCountryName = false;
  bool clearCountryCode = false;
  bool clearUrgency = false;

  static bool _isKeywordKey(String key) {
    return key == 'IPTC:Keywords' ||
        key == 'Keywords' ||
        key == 'Subject' ||
        key == 'XMP:Subject' ||
        key == 'XMP-dc:Subject' ||
        key == 'XMP:Keywords' ||
        key == 'XMP-photoshop:Keywords';
  }

  static bool _isSuppCatKey(String key) {
    return key.contains('SupplementalCategories') ||
        key == 'SupplementalCategories1' ||
        key == 'SupplementalCategories2' ||
        key == 'SupplementalCategories3';
  }

  static _WritePlan fromValues(Map<String, String> values) {
    final plan = _WritePlan();

    // Keywords: same clear-then-set semantics as IptcCaptionWriter.
    String? keywordsRaw;
    for (final e in values.entries) {
      if (_isKeywordKey(e.key)) {
        keywordsRaw = e.value;
        break;
      }
    }
    if (values.containsKey('IPTC:Keywords') ||
        values.containsKey('Keywords') ||
        values.containsKey('XMP-dc:Subject') ||
        values.containsKey('XMP:Subject')) {
      plan.clearKeywords = true;
      plan.keywords = DartJpegCaptionWriter.dedupeListValues(
        (keywordsRaw ?? '').split(RegExp(r'[,;]')),
      );
    }

    // Supp cats: gather slot keys or list.
    final suppSlots = <String>[];
    for (var i = 1; i <= 3; i++) {
      final v = values['SupplementalCategories$i'];
      if (v != null && v.trim().isNotEmpty) suppSlots.add(v.trim());
    }
    if (suppSlots.isNotEmpty ||
        values.keys.any(_isSuppCatKey) ||
        values.containsKey('IPTC:SupplementalCategories')) {
      plan.clearSuppCats = true;
      if (suppSlots.isNotEmpty) {
        plan.suppCats = DartJpegCaptionWriter.dedupeListValues(suppSlots);
      } else {
        final raw = values['IPTC:SupplementalCategories'] ??
            values['SupplementalCategories'] ??
            '';
        plan.suppCats = DartJpegCaptionWriter.dedupeListValues(
          raw.split(RegExp(r'[,;]')),
        );
      }
    }

    void take(
      List<String> keys,
      void Function(String v) set, {
      void Function()? onEmpty,
    }) {
      for (final k in keys) {
        if (!values.containsKey(k)) continue;
        final v = values[k]!;
        if (v.trim().isEmpty) {
          onEmpty?.call();
        } else {
          set(v);
        }
        return;
      }
    }

    take(
      [
        'IPTC:Caption-Abstract',
        'Caption-Abstract',
        'IPTC:Description',
        'Description',
        'XMP:Description',
        'XMP-dc:Description',
      ],
      (v) => plan.caption = v,
      onEmpty: () => plan.clearCaption = true,
    );
    take(
      ['IPTC:Headline', 'Headline', 'XMP:Headline', 'XMP-photoshop:Headline'],
      (v) => plan.headline = v,
      onEmpty: () => plan.clearHeadline = true,
    );
    take(
      ['XMP-getty:Personality'],
      (v) => plan.personality = v,
      onEmpty: () => plan.clearPersonality = true,
    );
    take(
      ['IPTC:By-line', 'By-line', 'XMP-dc:Creator'],
      (v) => plan.byLine = v,
      onEmpty: () => plan.clearByLine = true,
    );
    take(
      ['IPTC:By-lineTitle', 'By-lineTitle', 'AuthorsPosition'],
      (v) => plan.byLineTitle = v,
      onEmpty: () => plan.clearByLineTitle = true,
    );
    take(
      [
        'IPTC:Writer-Editor',
        'Writer-Editor',
        'XMP-photoshop:CaptionWriter',
        'CaptionWriter',
      ],
      (v) => plan.writerEditor = v,
      onEmpty: () => plan.clearWriterEditor = true,
    );
    take(
      ['IPTC:CopyrightNotice', 'CopyrightNotice', 'XMP-dc:Rights'],
      (v) => plan.copyright = v,
      onEmpty: () => plan.clearCopyright = true,
    );
    take(
      ['IPTC:Credit', 'Credit', 'XMP-photoshop:Credit'],
      (v) => plan.credit = v,
      onEmpty: () => plan.clearCredit = true,
    );
    take(
      ['IPTC:Source', 'Source', 'XMP:Source'],
      (v) => plan.source = v,
      onEmpty: () => plan.clearSource = true,
    );
    take(
      [
        'IPTC:OriginalTransmissionReference',
        'OriginalTransmissionReference',
        'TransmissionReference',
      ],
      (v) => plan.transmissionRef = v,
      onEmpty: () => plan.clearTransmissionRef = true,
    );
    take(
      ['IPTC:Category', 'Category'],
      (v) => plan.category = v,
      onEmpty: () => plan.clearCategory = true,
    );
    take(
      ['IPTC:ObjectName', 'ObjectName', 'XMP:Title', 'Title'],
      (v) => plan.objectName = v,
      onEmpty: () => plan.clearObjectName = true,
    );
    take(
      [
        'IPTC:SpecialInstructions',
        'SpecialInstructions',
        'XMP:Instructions',
        'XMP-photoshop:Instructions',
      ],
      (v) => plan.specialInstructions = v,
      onEmpty: () => plan.clearSpecialInstructions = true,
    );
    take(
      ['IPTC:City', 'City'],
      (v) => plan.city = v,
      onEmpty: () => plan.clearCity = true,
    );
    take(
      [
        'IPTC:Sub-location',
        'IPTC:SubLocation',
        'Sub-location',
        'SubLocation',
        'XMP-iptcCore:Location',
        'Location',
      ],
      (v) => plan.subLocation = v,
      onEmpty: () => plan.clearSubLocation = true,
    );
    take(
      [
        'IPTC:Province-State',
        'IPTC:ProvinceState',
        'Province-State',
        'ProvinceState',
        'State',
        'XMP-photoshop:State',
      ],
      (v) => plan.provinceState = v,
      onEmpty: () => plan.clearProvinceState = true,
    );
    take(
      [
        'IPTC:Country-PrimaryLocationName',
        'IPTC:CountryPrimaryLocationName',
        'Country-PrimaryLocationName',
        'CountryPrimaryLocationName',
        'Country',
        'XMP-photoshop:Country',
      ],
      (v) => plan.countryName = v,
      onEmpty: () => plan.clearCountryName = true,
    );
    take(
      [
        'IPTC:Country-PrimaryLocationCode',
        'Country-PrimaryLocationCode',
        'CountryCode',
        'XMP-iptcCore:CountryCode',
        'XMP:CountryCode',
      ],
      (v) {
        final parts = DartJpegCaptionWriter.dedupeListValues(
          v.split(RegExp(r'[,;/\s]+')),
        );
        plan.countryCode = parts.isEmpty ? null : parts.first;
        plan.clearCountryCode = true;
      },
      onEmpty: () => plan.clearCountryCode = true,
    );
    take(
      ['IPTC:Urgency', 'Urgency'],
      (v) => plan.urgency = v,
      onEmpty: () => plan.clearUrgency = true,
    );

    return plan;
  }
}
