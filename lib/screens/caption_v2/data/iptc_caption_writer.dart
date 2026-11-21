import '../../../metadata/caption_metadata_writer.dart';
import '../../../utils/exiftool_helper.dart';

/// IPTC caption writer for caption V2 (ExifTool backend — production default).
///
/// List fields are always replaced (clear then set), never appended onto
/// whatever is already on the file.
class IptcCaptionWriter implements CaptionMetadataWriter {
  const IptcCaptionWriter();

  @override
  String get writerId => 'exiftool';

  /// Writes [values] to each path. Returns paths that succeeded.
  @override
  Future<List<String>> writeCaptionToPaths({
    required List<String> paths,
    required Map<String, String> values,
  }) async {
    if (paths.isEmpty || values.isEmpty) return const [];

    final tagAndFlags = <String>[];
    values.forEach((key, value) {
      if (_isKeywordKey(key)) return;
      if (_isSuppCatKey(key)) return;
      if (_isCountryCodeKey(key)) return;
      if (value.trim().isNotEmpty) {
        tagAndFlags.add('-$key=$value');
      } else if (_isClearableWhenEmpty(key)) {
        // Empty Personality must clear Photo Mechanic placeholders rather
        // than omitting the tag and leaving the old value on disk.
        tagAndFlags.add('-$key=');
      }
    });

    final keywords = values['IPTC:Keywords'] ?? values['Keywords'];
    _appendKeywords(tagAndFlags, keywords);
    _appendSupplementalCategories(tagAndFlags, values);
    _appendCountryCode(tagAndFlags, values);

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
        key == 'XMP-dc:Subject' ||
        key == 'XMP:Keywords' ||
        key == 'XMP-photoshop:Keywords';
  }

  static bool _isSuppCatKey(String key) {
    return key.contains('SupplementalCategories');
  }

  static bool _isCountryCodeKey(String key) {
    return key == 'IPTC:Country-PrimaryLocationCode' ||
        key == 'Country-PrimaryLocationCode' ||
        key == 'CountryCode' ||
        key == 'XMP:CountryCode' ||
        key == 'XMP-iptcCore:CountryCode';
  }

  static bool _isClearableWhenEmpty(String key) {
    return key == 'XMP-getty:Personality';
  }

  /// Case-sensitive dedupe, keeping first occurrence.
  static List<String> dedupeListValues(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) out.add(trimmed);
    }
    return out;
  }

  /// Replace IPTC Keywords and XMP-dc:Subject with one entry per keyword.
  ///
  /// Clears related aliases first, then assigns each value with `=` (not `+=`).
  /// ExifTool ignores an IPTC clear when `+=` follows in the **same** invocation,
  /// which would re-append onto old values — repeated `=` replaces the list and
  /// still creates individual entries. Never writes a joined `-Subject=A, B`.
  static void _appendKeywords(List<String> args, String? keywordsValue) {
    if (keywordsValue == null) return;
    final parts = dedupeListValues(
      keywordsValue.split(RegExp(r'[,;]')),
    );

    args.add('-IPTC:Keywords=');
    args.add('-Keywords=');
    args.add('-Subject=');
    args.add('-XMP-dc:Subject=');
    args.add('-XMP:Subject=');
    for (final part in parts) {
      args.add('-IPTC:Keywords=$part');
      args.add('-XMP-dc:Subject=$part');
    }
  }

  /// Replace supplemental categories from slot keys or a joined IPTC value.
  static void _appendSupplementalCategories(
    List<String> args,
    Map<String, String> values,
  ) {
    final slots = <String>[];
    for (var i = 1; i <= 3; i++) {
      final v = values['SupplementalCategories$i']?.trim();
      if (v != null && v.isNotEmpty) slots.add(v);
    }
    final hasSuppKeys = values.keys.any(_isSuppCatKey);
    if (!hasSuppKeys && slots.isEmpty) return;

    final parts = slots.isNotEmpty
        ? dedupeListValues(slots)
        : dedupeListValues(
            (values['IPTC:SupplementalCategories'] ??
                    values['SupplementalCategories'] ??
                    '')
                .split(RegExp(r'[,;]')),
          );

    args.add('-SupplementalCategories=');
    args.add('-IPTC:SupplementalCategories=');
    args.add('-XMP:SupplementalCategories=');
    args.add('-XMP-photoshop:SupplementalCategories=');
    for (final part in parts) {
      args.add('-IPTC:SupplementalCategories=$part');
      args.add('-XMP-photoshop:SupplementalCategories=$part');
    }
  }

  /// Replace country code (single ISO token) on IPTC + XMP.
  static void _appendCountryCode(
    List<String> args,
    Map<String, String> values,
  ) {
    if (!values.keys.any(_isCountryCodeKey)) return;
    final raw = values['IPTC:Country-PrimaryLocationCode'] ??
        values['Country-PrimaryLocationCode'] ??
        values['XMP-iptcCore:CountryCode'] ??
        values['CountryCode'] ??
        '';
    final parts = dedupeListValues(raw.split(RegExp(r'[,;/\s]+')));
    final code = parts.isEmpty ? '' : parts.first;

    args.add('-CountryCode=');
    args.add('-Country-PrimaryLocationCode=');
    args.add('-IPTC:Country-PrimaryLocationCode=');
    args.add('-XMP:CountryCode=');
    args.add('-XMP-iptcCore:CountryCode=');
    if (code.isNotEmpty) {
      args.add('-Country-PrimaryLocationCode=$code');
      args.add('-XMP-iptcCore:CountryCode=$code');
    }
  }
}
