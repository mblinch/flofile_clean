import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'preferences_service.dart';

/// Clean G–C–G chime played when an FTP batch finishes successfully.
class FtpCompleteSound {
  static Uint8List? _wav;
  static Future<void>? _playing;

  static Future<void> play() {
    final current = _playing;
    if (current != null) return current;
    final next = _play();
    _playing = next;
    return next.whenComplete(() {
      if (identical(_playing, next)) _playing = null;
    });
  }

  static Uint8List wavBytes() => _wav ??= buildFtpCompleteWav();

  static Future<void> _play() async {
    try {
      final prefs = await PreferencesService.getInstance();
      final custom = await prefs.getFtpCompleteSoundPath();
      if (custom != null && File(custom).existsSync()) {
        await _playFile(custom);
        return;
      }
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}quickcap_ftp_complete.wav',
      );
      await file.writeAsBytes(wavBytes(), flush: true);
      await _playFile(file.path);
    } catch (e) {
      print('FTP complete sound failed: $e');
    }
  }

  static Future<void> _playFile(String path) async {
    if (Platform.isMacOS) {
      await Process.run('afplay', [path]);
    } else if (Platform.isWindows) {
      final escaped = path.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(New-Object System.Media.SoundPlayer '$escaped').PlaySync()",
      ]);
    } else if (Platform.isLinux) {
      final pulse = await Process.run('paplay', [path]);
      if (pulse.exitCode != 0) {
        await Process.run('aplay', [path]);
      }
    }
  }
}

/// G5, C6, G6. Same shape as the source clip, lower and faster.
Uint8List buildFtpCompleteWav() {
  const sampleRate = 44100;
  const duration = 1.05;
  final count = (sampleRate * duration).round();
  final samples = Float64List(count);

  void addNote(double freq, double startSec, double decay) {
    const attack = 0.01;
    final start = (startSec * sampleRate).round();
    final len = count - start;
    for (var i = 0; i < len; i++) {
      final t = i / sampleRate;
      final rise = t < attack ? t / attack : 1.0;
      final env = rise * rise * (3 - 2 * rise) * math.exp(-decay * t);
      samples[start + i] += math.sin(2 * math.pi * freq * t) * env;
    }
  }

  addNote(783.99, 0.00, 9.0);
  addNote(1046.50, 0.07, 6.5);
  addNote(1567.98, 0.18, 3.6);

  const fadeSec = 0.06;
  final fadeSamples = (fadeSec * sampleRate).round();
  final fadeStart = count - fadeSamples;
  for (var i = fadeStart; i < count; i++) {
    final u = (i - fadeStart) / fadeSamples;
    final down = 1 - u * u * (3 - 2 * u);
    samples[i] *= down;
  }
  samples[count - 1] = 0;

  var peak = 0.0;
  for (final sample in samples) {
    final amp = sample.abs();
    if (amp > peak) peak = amp;
  }
  final gain = peak == 0 ? 1.0 : 0.72 / peak;

  final bytes = ByteData(44 + count * 2);
  void writeStr(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeStr(0, 'RIFF');
  bytes.setUint32(4, 36 + count * 2, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeStr(36, 'data');
  bytes.setUint32(40, count * 2, Endian.little);

  for (var i = 0; i < count; i++) {
    var value = (samples[i] * gain * 32767).round();
    if (value > 32767) value = 32767;
    if (value < -32768) value = -32768;
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
