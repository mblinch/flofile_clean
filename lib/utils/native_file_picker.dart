import 'dart:io';

class NativeFilePicker {
  /// Pick a directory using macOS native dialog
  static Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      String script = 'set chosenFolder to choose folder';

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        // Normalize the path to ensure it's a valid POSIX path
        String normalizedPath = _normalizePath(initialDirectory);

        // Verify the path exists before using it
        if (Directory(normalizedPath).existsSync()) {
          final appleScriptPath = _appleScriptString(normalizedPath);
          // Coerce to alias so macOS reliably honors the default location.
          script += ' default location (POSIX file $appleScriptPath as alias)';
        } else {
          print('Initial directory does not exist, ignoring: $normalizedPath');
        }
      }

      script += '\nreturn POSIX path of chosenFolder';

      final result = await Process.run('osascript', ['-e', script]);

      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        return path.isEmpty ? null : path;
      } else {
        print('Directory picker error: ${result.stderr}');
        return null;
      }
    } catch (e) {
      print('Directory picker exception: $e');
      return null;
    }
  }

  /// Pick a file using macOS native dialog
  static Future<String?> pickFile(
      {List<String>? allowedExtensions, String? initialDirectory}) async {
    try {
      String script = 'set chosenFile to choose file';

      if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
        final extensions = allowedExtensions.map((ext) => '".$ext"').join(', ');
        script += ' of type {$extensions}';
      }

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        // Normalize the path to ensure it's a valid POSIX path
        String normalizedPath = _normalizePath(initialDirectory);

        // Verify the path exists before using it
        if (Directory(normalizedPath).existsSync()) {
          final appleScriptPath = _appleScriptString(normalizedPath);
          // Coerce to alias so macOS reliably honors the default location.
          script += ' default location (POSIX file $appleScriptPath as alias)';
        } else {
          print('Initial directory does not exist, ignoring: $normalizedPath');
        }
      }

      script += '\nreturn POSIX path of chosenFile';

      final result = await Process.run('osascript', ['-e', script]);

      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        return path.isEmpty ? null : path;
      } else {
        print('File picker error: ${result.stderr}');
        return null;
      }
    } catch (e) {
      print('File picker exception: $e');
      return null;
    }
  }

  /// Normalize a path to ensure it's a valid POSIX path
  /// Converts HFS+ style paths (colon-separated) to POSIX (slash-separated)
  static String _normalizePath(String path) {
    // If the path contains colons and no slashes, it's likely an HFS+ path
    if (path.contains(':') && !path.contains('/')) {
      // Convert HFS+ path to POSIX
      // HFS+ format: "VolumeName:folder:subfolder:"
      // POSIX format: "/Volumes/VolumeName/folder/subfolder/"

      List<String> parts = path.split(':');
      parts = parts.where((part) => part.isNotEmpty).toList();

      if (parts.isNotEmpty) {
        // First part is the volume name
        String volumeName = parts[0];
        List<String> subdirs = parts.sublist(1);

        // Construct POSIX path
        if (subdirs.isEmpty) {
          return '/Volumes/$volumeName';
        } else {
          return '/Volumes/$volumeName/${subdirs.join('/')}';
        }
      }
    }

    // Already a POSIX path or empty, return as-is
    return path;
  }

  static String _appleScriptString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
