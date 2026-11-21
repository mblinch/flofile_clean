import 'dart:convert';
import 'dart:typed_data';

/// Photoshop Image Resource Block (IRB) helpers for APP13.
class PhotoshopIrb {
  PhotoshopIrb(this.blocks);

  final List<IrbBlock> blocks;

  static const int iptcResourceId = 0x0404;
  static const String signature = '8BIM';
  static const String photoshop30 = 'Photoshop 3.0\x00';

  /// Parses payload that starts with `Photoshop 3.0\0`.
  static PhotoshopIrb parseApp13Payload(Uint8List payload) {
    final sig = utf8.encode(photoshop30);
    var i = 0;
    if (payload.length >= sig.length) {
      var match = true;
      for (var j = 0; j < sig.length; j++) {
        if (payload[j] != sig[j]) {
          match = false;
          break;
        }
      }
      if (match) i = sig.length;
    }
    final blocks = <IrbBlock>[];
    while (i + 12 <= payload.length) {
      if (payload[i] != 0x38 ||
          payload[i + 1] != 0x42 ||
          payload[i + 2] != 0x49 ||
          payload[i + 3] != 0x4D) {
        break;
      }
      i += 4;
      final id = (payload[i] << 8) | payload[i + 1];
      i += 2;
      final nameLen = payload[i];
      i += 1;
      final nameBytes = payload.sublist(i, i + nameLen);
      i += nameLen;
      // Name is Pascal string padded to even size including length byte.
      final nameFieldLen = nameLen + 1;
      if (nameFieldLen.isOdd) i += 1;
      if (i + 4 > payload.length) break;
      final dataLen =
          (payload[i] << 24) | (payload[i + 1] << 16) | (payload[i + 2] << 8) | payload[i + 3];
      i += 4;
      if (i + dataLen > payload.length) break;
      final data = Uint8List.sublistView(payload, i, i + dataLen);
      i += dataLen;
      if (dataLen.isOdd) i += 1;
      blocks.add(IrbBlock(id: id, name: utf8.decode(nameBytes), data: data));
    }
    return PhotoshopIrb(blocks);
  }

  /// Full APP13 payload including Photoshop 3.0 signature.
  Uint8List encodeApp13Payload() {
    final out = BytesBuilder(copy: false);
    out.add(utf8.encode(photoshop30));
    for (final b in blocks) {
      out.add(utf8.encode(signature));
      out.addByte((b.id >> 8) & 0xFF);
      out.addByte(b.id & 0xFF);
      final nameBytes = utf8.encode(b.name);
      if (nameBytes.length > 255) {
        throw ArgumentError('IRB name too long');
      }
      out.addByte(nameBytes.length);
      out.add(nameBytes);
      // Pad name field (length byte + name) to even.
      if (((nameBytes.length + 1) & 1) != 0) {
        out.addByte(0);
      }
      final dataLen = b.data.length;
      out.addByte((dataLen >> 24) & 0xFF);
      out.addByte((dataLen >> 16) & 0xFF);
      out.addByte((dataLen >> 8) & 0xFF);
      out.addByte(dataLen & 0xFF);
      out.add(b.data);
      if ((dataLen & 1) != 0) {
        out.addByte(0);
      }
    }
    return out.takeBytes();
  }

  Uint8List? iptcBytes() {
    for (final b in blocks) {
      if (b.id == iptcResourceId) return b.data;
    }
    return null;
  }

  void setIptcBytes(Uint8List iptc) {
    blocks.removeWhere((b) => b.id == iptcResourceId);
    blocks.add(IrbBlock(id: iptcResourceId, name: '', data: iptc));
  }
}

class IrbBlock {
  IrbBlock({
    required this.id,
    required this.name,
    required this.data,
  });

  final int id;
  final String name;
  final Uint8List data;
}
