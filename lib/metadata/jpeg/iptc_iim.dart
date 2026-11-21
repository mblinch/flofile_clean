import 'dart:convert';
import 'dart:typed_data';

/// IPTC-NAA Information Interchange Model (IIM) encoder/decoder.
///
/// Writes UTF-8 with CodedCharacterSet `ESC % G` (dataset 1:90).
class IptcIim {
  IptcIim({List<IptcDataset>? datasets})
      : datasets = List<IptcDataset>.from(datasets ?? const []);

  final List<IptcDataset> datasets;

  /// Record/dataset numbers for fields this app writes.
  static const int recordEnvelope = 1;
  static const int recordApplication = 2;

  static const int dsCodedCharacterSet = 90; // 1:90
  static const int dsObjectName = 5;
  static const int dsUrgency = 10;
  static const int dsCategory = 15;
  static const int dsSupplementalCategories = 20;
  static const int dsKeywords = 25;
  static const int dsSpecialInstructions = 40;
  static const int dsByLine = 80;
  static const int dsByLineTitle = 85;
  static const int dsCity = 90;
  static const int dsSubLocation = 92;
  static const int dsProvinceState = 95;
  static const int dsCountryCode = 100;
  static const int dsCountryName = 101;
  static const int dsTransmissionRef = 103;
  static const int dsHeadline = 105;
  static const int dsCredit = 110;
  static const int dsSource = 115;
  static const int dsCopyright = 116;
  static const int dsCaption = 120;
  static const int dsWriterEditor = 122;

  /// UTF-8 designation: ESC % G
  static final Uint8List utf8CodedCharacterSet =
      Uint8List.fromList(const [0x1B, 0x25, 0x47]);

  static IptcIim parse(Uint8List bytes) {
    final out = <IptcDataset>[];
    var i = 0;
    while (i + 4 < bytes.length) {
      if (bytes[i] != 0x1C) {
        i++;
        continue;
      }
      final record = bytes[i + 1];
      final dataset = bytes[i + 2];
      var len = (bytes[i + 3] << 8) | bytes[i + 4];
      var dataStart = i + 5;
      // Extended length: when high bit of length word is set… IIM uses
      // length==0x80xx form rarely; ExifTool uses short form for our sizes.
      if (bytes[i + 3] >= 0x80) {
        final extCount = bytes[i + 3] & 0x7F;
        if (extCount == 0 || i + 4 + extCount > bytes.length) break;
        len = 0;
        for (var b = 0; b < extCount; b++) {
          len = (len << 8) | bytes[i + 4 + b];
        }
        dataStart = i + 4 + extCount;
      }
      if (dataStart + len > bytes.length) break;
      out.add(IptcDataset(
        record: record,
        dataset: dataset,
        data: Uint8List.sublistView(bytes, dataStart, dataStart + len),
      ));
      i = dataStart + len;
    }
    return IptcIim(datasets: out);
  }

  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    // Ensure UTF-8 CodedCharacterSet is first among envelope datasets.
    final hasCcs = datasets.any((d) =>
        d.record == recordEnvelope && d.dataset == dsCodedCharacterSet);
    if (!hasCcs) {
      _writeDataset(
        out,
        recordEnvelope,
        dsCodedCharacterSet,
        utf8CodedCharacterSet,
      );
    }
    for (final d in datasets) {
      _writeDataset(out, d.record, d.dataset, d.data);
    }
    return out.takeBytes();
  }

  static void _writeDataset(
    BytesBuilder out,
    int record,
    int dataset,
    List<int> data,
  ) {
    out.addByte(0x1C);
    out.addByte(record);
    out.addByte(dataset);
    final len = data.length;
    if (len <= 0x7FFF) {
      out.addByte((len >> 8) & 0xFF);
      out.addByte(len & 0xFF);
    } else {
      // Extended length: 1 length-of-length byte with high bit, then 4 bytes.
      out.addByte(0x84);
      out.addByte((len >> 24) & 0xFF);
      out.addByte((len >> 16) & 0xFF);
      out.addByte((len >> 8) & 0xFF);
      out.addByte(len & 0xFF);
    }
    out.add(data);
  }

  void removeApplicationDatasets(Set<int> datasetNumbers) {
    datasets.removeWhere((d) =>
        d.record == recordApplication && datasetNumbers.contains(d.dataset));
  }

  void setUtf8Field(int dataset, String value, {bool repeatable = false}) {
    final data = Uint8List.fromList(utf8.encode(value));
    if (!repeatable) {
      datasets.removeWhere((d) =>
          d.record == recordApplication && d.dataset == dataset);
    }
    if (value.isEmpty && !repeatable) return;
    if (value.isEmpty) return;
    datasets.add(IptcDataset(
      record: recordApplication,
      dataset: dataset,
      data: data,
    ));
  }

  void setUtf8List(int dataset, List<String> values) {
    datasets.removeWhere(
        (d) => d.record == recordApplication && d.dataset == dataset);
    for (final v in values) {
      final t = v.trim();
      if (t.isEmpty) continue;
      datasets.add(IptcDataset(
        record: recordApplication,
        dataset: dataset,
        data: Uint8List.fromList(utf8.encode(t)),
      ));
    }
  }

  List<String> valuesOf(int dataset) {
    return datasets
        .where((d) =>
            d.record == recordApplication && d.dataset == dataset)
        .map((d) => utf8.decode(d.data, allowMalformed: true))
        .toList();
  }

  String? firstValue(int dataset) {
    final all = valuesOf(dataset);
    return all.isEmpty ? null : all.first;
  }
}

class IptcDataset {
  IptcDataset({
    required this.record,
    required this.dataset,
    required this.data,
  });

  final int record;
  final int dataset;
  final Uint8List data;
}
