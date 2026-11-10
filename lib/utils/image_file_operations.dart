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
