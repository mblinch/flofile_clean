import 'dart:convert';
import 'dart:io';

import '../utils/exiftool_helper.dart';

/// Remembers that FloFile already wrote a caption, stored in the image itself.
///
/// The mark is an XMP tag (`XMP-flofile:CaptionSaved`). It travels with the
/// file, so reopening the folder on this Mac or another still knows Flo saved
/// that caption. It is not a keyword and it is not a separate database.
class FloCaptionMark {
  FloCaptionMark._();

  static const value = '1';
  static const tag = 'XMP-flofile:CaptionSaved';

  static const protectedFieldKeys = {
    'Caption',
    'Personality',
    'Keywords',
  };

  static Map<String, String> withoutProtectedFields(
    Map<String, String> preset,
  ) {
    return Map<String, String>.from(preset)..removeWhere(
        (key, _) => protectedFieldKeys.contains(key),
      );
  }

  static Set<String> withoutProtectedClears(Set<String> cleared) {
    return cleared.where((key) => !protectedFieldKeys.contains(key)).toSet();
  }

  static const _config = r'''
%Image::ExifTool::UserDefined = (
    'Image::ExifTool::XMP::Main' => {
        flofile => {
            SubDirectory => {
                TagTable => 'Image::ExifTool::UserDefined::flofile',
            },
        },
    },
);

%Image::ExifTool::UserDefined::flofile = (
    GROUPS => { 0 => 'XMP', 1 => 'XMP-flofile', 2 => 'Image' },
    NAMESPACE => { 'flofile' => 'http://ns.flofilecaptions.com/flofile/1.0/' },
    WRITABLE => 'string',
    CaptionSaved => { },
);

1;
''';

  static Future<String> _configPath() async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}flofile_exiftool.config',
    );
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsString(_config);
    }
    return file.path;
  }

  /// Writes the mark onto each path. Failures are ignored so a caption save
  /// is not rolled back when the marker cannot be written.
  static Future<void> markSaved(Iterable<String> paths) async {
    final files = paths.where((path) => path.trim().isNotEmpty).toList();
    if (files.isEmpty) return;
    try {
      final config = await _configPath();
      for (final path in files) {
        await ExiftoolHelper.run([
          '-config',
          config,
          '-$tag=$value',
          '-overwrite_original',
          '-P',
          path,
        ]);
      }
    } catch (_) {}
  }

  static Future<bool> isSaved(String path) async {
    final saved = await savedPaths([path]);
    return saved.contains(path);
  }

  /// Paths whose file already carries a FloFile caption-saved mark.
  static Future<Set<String>> savedPaths(Iterable<String> paths) async {
    final files = paths.where((path) => path.trim().isNotEmpty).toList();
    if (files.isEmpty) return const {};
    final found = <String>{};
    try {
      final config = await _configPath();
      const chunk = 40;
      for (var i = 0; i < files.length; i += chunk) {
        final end = i + chunk > files.length ? files.length : i + chunk;
        final slice = files.sublist(i, end);
        final proc = await ExiftoolHelper.run([
          '-config',
          config,
          '-j',
          '-$tag',
          ...slice,
        ]);
        if (!proc.isSuccess || proc.stdoutText.trim().isEmpty) continue;
        final decoded = jsonDecode(proc.stdoutText);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is! Map) continue;
          final source = item['SourceFile']?.toString();
          final mark = item['CaptionSaved']?.toString().trim();
          if (source == null || source.isEmpty || mark != value) continue;
          found.add(source);
        }
      }
    } catch (_) {}
    return found;
  }
}
