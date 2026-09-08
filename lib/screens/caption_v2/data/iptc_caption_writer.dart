import '../../../utils/exiftool_helper.dart';

/// Additive IPTC caption writer for caption V2.
///
/// Mirrors the bulk-write path used by the classic screen without modifying it.
class IptcCaptionWriter {
  const IptcCaptionWriter();

  /// Writes [values] to each path. Returns paths that succeeded.
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  }) async {
    if (paths.isEmpty || values.isEmpty) return const [];

    final tagAndFlags = <String>[];
    values.forEach((key, value) {
      if (_isKeywordKey(key)) return;
      if (value.trim().isNotEmpty) {
        tagAndFlags.add('-$key=$value');
      }
    });

    final keywords = values['IPTC:Keywords'] ?? values['Keywords'];
    _appendKeywords(tagAndFlags, keywords);

    tagAndFlags.addAll([
      '-overwrite_original',
      '-P',
      '-m',
      '-charset',
      'iptc=UTF8',
    ]);

    // Guard: only flags, nothing to write.
    if (tagAndFlags.length <= 5) return const [];

    final succeeded = <String>[];
    for (final path in paths) {
      final proc = await ExiftoolHelper.run([...tagAndFlags, path]);
      if (proc.isSuccess) {
        succeeded.add(path);
      }
    }
    return succeeded;
  }

  static bool _isKeywordKey(String key) {
    return key == 'IPTC:Keywords' ||
        key == 'Keywords' ||
        key == 'Subject' ||
        key == 'XMP:Subject' ||
        key == 'XMP-dc:Subject';
  }

  static void _appendKeywords(List<String> args, String? keywordsValue) {
    if (keywordsValue == null || keywordsValue.trim().isEmpty) return;
    final parts = keywordsValue
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final part in parts) {
      args.add('-IPTC:Keywords+=$part');
      args.add('-XMP:Subject+=$part');
    }
  }
}
