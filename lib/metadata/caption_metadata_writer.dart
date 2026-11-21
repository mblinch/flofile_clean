/// Shared caption / IPTC metadata writer contract.
///
/// Production desktop still uses [IptcCaptionWriter] (ExifTool). The pure-Dart
/// JPEG implementation is exercised in compare-mode tests only for now.
abstract class CaptionMetadataWriter {
  /// Writes [values] (ExifTool-style tag keys) to each path.
  /// Returns paths that succeeded.
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  });

  /// Human-readable id for compare reports (`exiftool`, `dart_jpeg`, …).
  String get writerId;
}
