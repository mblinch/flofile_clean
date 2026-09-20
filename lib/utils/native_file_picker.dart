import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NativeFilePicker {
  /// Pick a directory. macOS keeps the AppleScript dialog; other platforms
  /// use [file_picker] so Android/iOS work.
  static Future<String?> pickDirectory({String? initialDirectory}) async {
    if (!kIsWeb && Platform.isMacOS) {
      return _pickDirectoryMacOS(initialDirectory: initialDirectory);
    }
    try {
      if (!await ensureMediaReadPermission()) {
        print('Directory picker: media permission denied');
        return null;
      }
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose images folder',
        initialDirectory: initialDirectory,
      );
      if (path == null || path.isEmpty) return null;
      return path;
    } catch (e) {
      print('Directory picker exception: $e');
      return null;
    }
  }

  /// Pick a file. macOS keeps AppleScript; other platforms use [file_picker].
  static Future<String?> pickFile({
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      return _pickFileMacOS(
        allowedExtensions: allowedExtensions,
        initialDirectory: initialDirectory,
      );
    }
    try {
      if (!await ensureMediaReadPermission()) {
        print('File picker: media permission denied');
        return null;
      }
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose file',
        initialDirectory: initialDirectory,
        type: allowedExtensions == null || allowedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.single.path;
    } catch (e) {
      print('File picker exception: $e');
      return null;
    }
  }

  /// Android/iOS need runtime photo access before Directory/File reads work.
  static Future<bool> ensureMediaReadPermission() async {
    if (kIsWeb) return true;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return true;
    }
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    return true;
  }

  static Future<String?> _pickDirectoryMacOS({String? initialDirectory}) async {
    try {
      String script = 'set chosenFolder to choose folder';

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        String normalizedPath = _normalizePath(initialDirectory);

        if (Directory(normalizedPath).existsSync()) {
          final appleScriptPath = _appleScriptString(normalizedPath);
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

  static Future<String?> _pickFileMacOS({
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) async {
    try {
      String script = 'set chosenFile to choose file';

      if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
        final extensions = allowedExtensions.map((ext) => '".$ext"').join(', ');
        script += ' of type {$extensions}';
      }

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        String normalizedPath = _normalizePath(initialDirectory);

        if (Directory(normalizedPath).existsSync()) {
          final appleScriptPath = _appleScriptString(normalizedPath);
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
    if (path.contains(':') && !path.contains('/')) {
      List<String> parts = path.split(':');
      parts = parts.where((part) => part.isNotEmpty).toList();

      if (parts.isNotEmpty) {
        String volumeName = parts[0];
        List<String> subdirs = parts.sublist(1);

        if (subdirs.isEmpty) {
          return '/Volumes/$volumeName';
        } else {
          return '/Volumes/$volumeName/${subdirs.join('/')}';
        }
      }
    }

    return path;
  }

  static String _appleScriptString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
