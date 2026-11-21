import 'dart:io';

import 'package:path/path.dart' as p;

/// OS label for the trash / recycle location.
String trashBinLabel() {
  if (Platform.isWindows) return 'Recycle Bin';
  return 'Trash';
}

/// Moves an image to the OS trash, including a same-name XMP sidecar when present.
///
/// Returns `true` only when the primary image file no longer exists after the
/// operation. Throws [FileSystemException] when the move fails.
Future<bool> deleteImageFromDisk(String imagePath) async {
  final normalized = p.normalize(imagePath);
  final file = File(normalized);

  if (!await file.exists()) {
    throw FileSystemException('File not found', normalized);
  }

  final sidecarPaths = <String>{
    p.setExtension(normalized, '.xmp'),
    '${p.withoutExtension(normalized)}.XMP',
  };

  await _movePathToTrash(normalized);

  for (final sidecar in sidecarPaths) {
    if (sidecar == normalized) continue;
    final sidecarFile = File(sidecar);
    if (await sidecarFile.exists()) {
      await _movePathToTrash(sidecar);
    }
  }

  if (await file.exists()) {
    throw FileSystemException(
      'File still exists after move to ${trashBinLabel()}',
      normalized,
    );
  }

  return true;
}

Future<void> _movePathToTrash(String path) async {
  final file = File(path);
  if (!await file.exists()) return;

  if (Platform.isMacOS) {
    await _trashMacOS(path);
  } else if (Platform.isWindows) {
    await _trashWindows(path);
  } else if (Platform.isLinux) {
    await _trashLinux(path);
  } else {
    throw FileSystemException(
      'Move to ${trashBinLabel()} is not supported on this platform',
      path,
    );
  }

  if (await file.exists()) {
    throw FileSystemException(
      'Unable to move file to ${trashBinLabel()}',
      path,
    );
  }
}

Future<void> _trashMacOS(String path) async {
  // Pass the path as argv so spaces / quotes do not need shell escaping.
  final result = await Process.run('osascript', [
    '-e',
    'on run argv\n'
        'set theFile to POSIX file (item 1 of argv)\n'
        'tell application "Finder" to delete theFile\n'
        'end run',
    path,
  ]);
  if (result.exitCode != 0) {
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty
          ? 'Finder could not move the file to Trash'
          : message,
      path,
    );
  }
}

Future<void> _trashWindows(String path) async {
  final escaped = path.replaceAll("'", "''");
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "Add-Type -AssemblyName Microsoft.VisualBasic; "
        "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
        "'$escaped', 'OnlyErrorDialogs', 'SendToRecycleBin')",
  ]);
  if (result.exitCode != 0) {
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty
          ? 'Could not move the file to the Recycle Bin'
          : message,
      path,
    );
  }
}

Future<void> _trashLinux(String path) async {
  ProcessResult result = await Process.run('gio', ['trash', path]);
  if (result.exitCode == 0) return;

  result = await Process.run('trash-put', [path]);
  if (result.exitCode == 0) return;

  final message = '${result.stderr}'.trim();
  throw FileSystemException(
    message.isEmpty
        ? 'Could not move the file to Trash (install gio or trash-cli)'
        : message,
    path,
  );
}

/// Same-name XMP sidecars that travel with an image (`.xmp` / `.XMP`).
List<String> imageSidecarPaths(String imagePath) {
  final normalized = p.normalize(imagePath);
  final lower = p.setExtension(normalized, '.xmp');
  final upper = '${p.withoutExtension(normalized)}.XMP';
  final out = <String>{};
  if (lower != normalized) out.add(lower);
  if (upper != normalized) out.add(upper);
  return out.toList(growable: false);
}

/// Destination path in [folder] that does not overwrite an existing file.
Future<String> uniquePathInFolder(String folder, String fileName) async {
  final base = p.basenameWithoutExtension(fileName);
  final ext = p.extension(fileName);
  var candidate = p.join(folder, fileName);
  var n = 2;
  while (await File(candidate).exists()) {
    candidate = p.join(folder, '$base-$n$ext');
    n++;
  }
  return candidate;
}

Future<String> _sidecarDestinationFor({
  required String destImagePath,
  required String sourceSidecarPath,
}) async {
  final matched = p.setExtension(destImagePath, p.extension(sourceSidecarPath));
  if (!await File(matched).exists()) return matched;
  return uniquePathInFolder(
    p.dirname(destImagePath),
    p.basename(sourceSidecarPath),
  );
}

Future<void> _relocateFile(String from, String to, {required bool copy}) async {
  final source = File(from);
  if (!await source.exists()) return;
  if (copy) {
    await source.copy(to);
    return;
  }
  try {
    await source.rename(to);
  } on FileSystemException {
    await source.copy(to);
    await source.delete();
  }
}

/// Copies [imagePath] (and XMP sidecar when present) into [destinationFolder].
///
/// Returns the new image path. Throws [FileSystemException] on failure.
Future<String> copyImageToFolder(
  String imagePath,
  String destinationFolder,
) async {
  final source = File(p.normalize(imagePath));
  if (!await source.exists()) {
    throw FileSystemException('File not found', source.path);
  }
  final destDir = Directory(destinationFolder);
  if (!await destDir.exists()) {
    throw FileSystemException('Folder not found', destinationFolder);
  }
  final destPath = await uniquePathInFolder(
    destinationFolder,
    p.basename(source.path),
  );
  await _relocateFile(source.path, destPath, copy: true);
  for (final sidecar in imageSidecarPaths(source.path)) {
    if (!await File(sidecar).exists()) continue;
    final to = await _sidecarDestinationFor(
      destImagePath: destPath,
      sourceSidecarPath: sidecar,
    );
    await _relocateFile(sidecar, to, copy: true);
  }
  return destPath;
}

/// Moves [imagePath] (and XMP sidecar when present) into [destinationFolder].
///
/// Returns the new image path. Throws [FileSystemException] on failure.
Future<String> moveImageToFolder(
  String imagePath,
  String destinationFolder,
) async {
  final source = File(p.normalize(imagePath));
  if (!await source.exists()) {
    throw FileSystemException('File not found', source.path);
  }
  final destDir = Directory(destinationFolder);
  if (!await destDir.exists()) {
    throw FileSystemException('Folder not found', destinationFolder);
  }
  final sameFolder = p.equals(
    p.normalize(p.dirname(source.path)),
    p.normalize(destinationFolder),
  );
  if (sameFolder) {
    throw FileSystemException(
      'Choose a different folder',
      destinationFolder,
    );
  }
  final destPath = await uniquePathInFolder(
    destinationFolder,
    p.basename(source.path),
  );
  final sidecars = <({String from, String to})>[];
  for (final sidecar in imageSidecarPaths(source.path)) {
    if (!await File(sidecar).exists()) continue;
    sidecars.add((
      from: sidecar,
      to: await _sidecarDestinationFor(
        destImagePath: destPath,
        sourceSidecarPath: sidecar,
      ),
    ));
  }
  await _relocateFile(source.path, destPath, copy: false);
  for (final pair in sidecars) {
    await _relocateFile(pair.from, pair.to, copy: false);
  }
  return destPath;
}
