import 'dart:io';

import 'package:path/path.dart' as p;

/// Waits until [path] has a stable size and passes [isImageFileComplete].
///
/// A create event fires as soon as a file appears, while a copy or camera
/// ingest may still be writing. Returns false on timeout so a truncated
/// frame is never shown.
Future<bool> waitForImageFileReady(
  String path, {
  Duration pollInterval = const Duration(milliseconds: 250),
  Duration timeout = const Duration(seconds: 90),
  int stablePollsRequired = 3,
}) async {
  final file = File(path);
  final deadline = DateTime.now().add(timeout);
  int? lastLength;
  var stableCount = 0;

  while (DateTime.now().isBefore(deadline)) {
    int length;
    try {
      length = await file.length();
    } catch (_) {
      stableCount = 0;
      lastLength = null;
      await Future.delayed(pollInterval);
      continue;
    }

    if (length <= 0) {
      stableCount = 0;
      lastLength = length;
      await Future.delayed(pollInterval);
      continue;
    }

    if (lastLength != null && length == lastLength) {
      stableCount++;
    } else {
      stableCount = 1;
      lastLength = length;
    }

    if (stableCount >= stablePollsRequired) {
      if (await isImageFileComplete(path)) return true;
      stableCount = 0;
    }

    await Future.delayed(pollInterval);
  }

  return false;
}

/// Structural completeness check so truncated downloads are never shown.
///
/// JPEG: SOI (FFD8) at start and EOI (FFD9) near the end.
/// PNG: signature + IEND chunk at end.
/// Other formats: minimum header + non-trivial size after size stabilizes.
Future<bool> isImageFileComplete(String path) async {
  final ext = p.extension(path).toLowerCase();
  final file = File(path);
  RandomAccessFile? raf;
  try {
    raf = await file.open(mode: FileMode.read);
    final length = await raf.length();
    if (length < 24) return false;

    if (ext == '.jpg' || ext == '.jpeg') {
      await raf.setPosition(0);
      final head = await raf.read(2);
      if (head.length < 2 || head[0] != 0xFF || head[1] != 0xD8) {
        return false;
      }
      final scanLen = length < 4096 ? length : 4096;
      await raf.setPosition(length - scanLen);
      final tail = await raf.read(scanLen);
      for (var i = tail.length - 2; i >= 0; i--) {
        if (tail[i] == 0xFF && tail[i + 1] == 0xD9) {
          return true;
        }
      }
      return false;
    }

    if (ext == '.png') {
      await raf.setPosition(0);
      final head = await raf.read(8);
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      if (head.length < 8) return false;
      for (var i = 0; i < 8; i++) {
        if (head[i] != sig[i]) return false;
      }
      if (length < 12) return false;
      await raf.setPosition(length - 8);
      final end = await raf.read(8);
      return end.length == 8 &&
          end[0] == 0x49 &&
          end[1] == 0x45 &&
          end[2] == 0x4E &&
          end[3] == 0x44;
    }

    if (ext == '.bmp') {
      await raf.setPosition(0);
      final head = await raf.read(6);
      if (head.length < 6 || head[0] != 0x42 || head[1] != 0x4D) {
        return false;
      }
      final declared = head[2] |
          (head[3] << 8) |
          (head[4] << 16) |
          (head[5] << 24);
      return declared > 0 && declared <= length;
    }

    if (ext == '.tif' || ext == '.tiff') {
      await raf.setPosition(0);
      final head = await raf.read(4);
      if (head.length < 4) return false;
      final le = head[0] == 0x49 && head[1] == 0x49;
      final be = head[0] == 0x4D && head[1] == 0x4D;
      if (!le && !be) return false;
      final magic =
          be ? ((head[2] << 8) | head[3]) : (head[2] | (head[3] << 8));
      return magic == 42;
    }

    return length > 0;
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}
