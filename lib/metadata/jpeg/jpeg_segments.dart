import 'dart:convert';
import 'dart:typed_data';

/// JPEG marker rewrite that never re-encodes entropy-coded pixel data.
///
/// Parses markers from SOI until SOS, then copies SOS→EOI byte-for-byte.
class JpegSegments {
  JpegSegments._({
    required this.headerSegments,
    required this.tailFromSos,
  });

  /// Segment marker + full segment bytes including `FF xx` and length.
  final List<JpegSegment> headerSegments;

  /// Bytes from SOS marker through EOI (inclusive), untouched.
  final Uint8List tailFromSos;

  static const int soi = 0xD8;
  static const int eoi = 0xD9;
  static const int sos = 0xDA;
  static const int app1 = 0xE1;
  static const int app13 = 0xED;

  static const String photoshopSig = 'Photoshop 3.0\x00';
  static const String xmpNamespace =
      'http://ns.adobe.com/xap/1.0/\x00';

  static JpegSegments parse(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != soi) {
      throw FormatException('Not a JPEG (missing SOI)');
    }
    final header = <JpegSegment>[];
    var i = 2;
    while (i + 1 < bytes.length) {
      if (bytes[i] != 0xFF) {
        throw FormatException('Expected JPEG marker at offset $i');
      }
      // Skip fill bytes.
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i];
      i++;
      // Standalone markers (no length): RST, TEM, SOI, EOI — should not appear
      // before SOS except TEM; treat lengthless carefully.
      if (marker == eoi) {
        throw FormatException('EOI before SOS');
      }
      if (marker == sos) {
        // SOS: length of header, then entropy-coded data to EOI.
        if (i + 1 >= bytes.length) {
          throw FormatException('Truncated SOS');
        }
        final sosLen = (bytes[i] << 8) | bytes[i + 1];
        final sosStart = i - 2; // back to FF DA
        // Validate length covers the SOS parameter block.
        if (sosLen < 2 || i + sosLen > bytes.length) {
          throw FormatException('Invalid SOS length');
        }
        return JpegSegments._(
          headerSegments: header,
          tailFromSos: Uint8List.sublistView(bytes, sosStart),
        );
      }
      if (i + 1 >= bytes.length) {
        throw FormatException('Truncated segment length');
      }
      final len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2 || i + len > bytes.length) {
        throw FormatException('Invalid segment length at $i');
      }
      final segmentStart = i - 2; // FF marker
      final segmentEnd = i + len;
      header.add(JpegSegment(
        marker: marker,
        bytes: Uint8List.sublistView(bytes, segmentStart, segmentEnd),
      ));
      i = segmentEnd;
    }
    throw FormatException('JPEG missing SOS');
  }

  /// Rebuilds JPEG: SOI + [headerSegments] + [tailFromSos].
  Uint8List rebuild() {
    final out = BytesBuilder(copy: false);
    out.addByte(0xFF);
    out.addByte(soi);
    for (final seg in headerSegments) {
      out.add(seg.bytes);
    }
    out.add(tailFromSos);
    return out.takeBytes();
  }

  /// Payload after marker+length (excludes FF, marker, and 2-byte length).
  static Uint8List payloadOf(Uint8List segmentBytes) {
    if (segmentBytes.length < 4) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(segmentBytes, 4);
  }

  static Uint8List buildSegment(int marker, List<int> payload) {
    final len = payload.length + 2;
    if (len > 0xFFFF) {
      throw ArgumentError('JPEG segment too large ($len)');
    }
    final out = Uint8List(2 + len);
    out[0] = 0xFF;
    out[1] = marker;
    out[2] = (len >> 8) & 0xFF;
    out[3] = len & 0xFF;
    out.setRange(4, out.length, payload);
    return out;
  }

  bool get hasPhotoshopApp13 => headerSegments.any(_isPhotoshopApp13);

  bool get hasXmpApp1 => headerSegments.any(_isXmpApp1);

  static bool _isPhotoshopApp13(JpegSegment s) {
    if (s.marker != app13) return false;
    final p = payloadOf(s.bytes);
    final sig = utf8.encode(photoshopSig);
    if (p.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (p[i] != sig[i]) return false;
    }
    return true;
  }

  static bool _isXmpApp1(JpegSegment s) {
    if (s.marker != app1) return false;
    final p = payloadOf(s.bytes);
    final sig = utf8.encode(xmpNamespace);
    if (p.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (p[i] != sig[i]) return false;
    }
    return true;
  }

  /// Replaces all Photoshop APP13 segments with [app13Payload] (IRB body after
  /// optional rebuild), or inserts one after the last APP segment.
  void setPhotoshopApp13(Uint8List photoshop30Payload) {
    headerSegments.removeWhere(_isPhotoshopApp13);
    final segment = buildSegment(app13, photoshop30Payload);
    _insertAfterAppSegments(JpegSegment(marker: app13, bytes: segment));
  }

  /// Replaces XMP APP1 or inserts one.
  void setXmpApp1(Uint8List xmpXmlUtf8) {
    headerSegments.removeWhere(_isXmpApp1);
    final payload = <int>[
      ...utf8.encode(xmpNamespace),
      ...xmpXmlUtf8,
    ];
    final segment = buildSegment(app1, payload);
    _insertAfterAppSegments(JpegSegment(marker: app1, bytes: segment));
  }

  Uint8List? readXmpXml() {
    for (final s in headerSegments) {
      if (!_isXmpApp1(s)) continue;
      final p = payloadOf(s.bytes);
      final sig = utf8.encode(xmpNamespace);
      return Uint8List.sublistView(p, sig.length);
    }
    return null;
  }

  Uint8List? readPhotoshopApp13Payload() {
    for (final s in headerSegments) {
      if (!_isPhotoshopApp13(s)) continue;
      return payloadOf(s.bytes);
    }
    return null;
  }

  void _insertAfterAppSegments(JpegSegment segment) {
    var insertAt = 0;
    for (var i = 0; i < headerSegments.length; i++) {
      final m = headerSegments[i].marker;
      if (m >= 0xE0 && m <= 0xEF) {
        insertAt = i + 1;
      }
    }
    headerSegments.insert(insertAt, segment);
  }
}

class JpegSegment {
  JpegSegment({required this.marker, required this.bytes});

  final int marker;
  final Uint8List bytes;
}
