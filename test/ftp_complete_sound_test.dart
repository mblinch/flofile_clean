import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/ftp_complete_sound.dart';

void main() {
  test('ftp complete chime is a playable wav', () {
    final wav = buildFtpCompleteWav();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final data = ByteData.sublistView(wav);
    final sampleRate = data.getUint32(24, Endian.little);
    final dataBytes = data.getUint32(40, Endian.little);
    expect(sampleRate, 44100);
    expect(dataBytes, wav.length - 44);
    expect(dataBytes / sampleRate / 2, greaterThan(0.5));
  });
}
