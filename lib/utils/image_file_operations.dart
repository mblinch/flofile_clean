import 'dart:io';

import 'package:path/path.dart' as p;

/// Deletes an image from disk, including a same-name XMP sidecar when present.
///
/// Returns `true` only when the primary image file no longer exists after the
/// operation. Throws [FileSystemException] when deletion fails.
Future<bool> deleteImageFromDisk(String imagePath) async {
  final normalized = p.normalize(imagePath);
  final file = File(normalized);

  if (!await file.exists()) {
    throw FileSystemException('File not found', normalized);
  }

  final sidecarPaths = <String>[
    p.setExtension(normalized, '.xmp'),
    '${p.withoutExtension(normalized)}.XMP',
  ];

  await _deletePath(normalized);

  for (final sidecar in sidecarPaths) {
    if (sidecar == normalized) continue;
    final sidecarFile = File(sidecar);
    if (await sidecarFile.exists()) {
      await _deletePath(sidecar);
    }
  }

  if (await file.exists()) {
    throw FileSystemException('File still exists after delete', normalized);
  }

  return true;
}

Future<void> _deletePath(String path) async {
  final file = File(path);
  if (!await file.exists()) return;

  try {
    await file.delete();
  } on FileSystemException {
    // Fall through to rm on macOS/Linux.
  }

  if (!await file.exists()) return;

  if (Platform.isMacOS || Platform.isLinux) {
    final result = await Process.run('/bin/rm', ['-f', path]);
    if (result.exitCode != 0) {
      final message = '${result.stderr}'.trim();
      throw FileSystemException(
        message.isEmpty ? 'rm failed with exit code ${result.exitCode}' : message,
        path,
      );
    }
  }

  if (await file.exists()) {
    throw FileSystemException('Unable to delete file', path);
  }
}
