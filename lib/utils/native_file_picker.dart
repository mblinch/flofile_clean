import 'dart:io';

class NativeFilePicker {
  /// Pick a directory using macOS native dialog
  static Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      String script = 'set chosenFolder to choose folder';

      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        script += ' default location "$initialDirectory"';
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
        script += ' default location "$initialDirectory"';
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
}
