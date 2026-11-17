void _handleVerbClick(
    String verb, Function setState, Map<String, bool?> stateMap) {
  setState(() {
    stateMap[verb] = !(stateMap[verb] ?? false);
  });
}

/// Combined supplemental categories from the first IPTC/XMP key that has a
/// non-empty value. [??] alone is not enough: an empty string in XMP would
/// block reading IPTC.
dynamic combinedSupplementalCategoriesValue(Map<String, dynamic> m) {
  const keys = <String>[
    'XMP-photoshop:SupplementalCategories',
    'IPTC:SupplementalCategories',
    'SupplementalCategories',
    'XMP:SupplementalCategories',
  ];
  for (final key in keys) {
    final v = m[key];
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    if (v is List && v.isEmpty) continue;
    return v;
  }
  return null;
}

/// Which key [combinedSupplementalCategoriesValue] uses (for logging).
String? sourceKeyForSupplementalCategories(Map<String, dynamic> m) {
  const keys = <String>[
    'XMP-photoshop:SupplementalCategories',
    'IPTC:SupplementalCategories',
    'SupplementalCategories',
    'XMP:SupplementalCategories',
  ];
  for (final key in keys) {
    final v = m[key];
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    if (v is List && v.isEmpty) continue;
    return key;
  }
  return null;
}

/// Values for [buildSupplementalCategoriesArgs] when saving IPTC.
///
/// [getCurrentCaptionValues] does not include `SupplementalCategories1..3`, so
/// without this merge every save would pass empty strings and
/// [buildSupplementalCategoriesArgs] would **clear** all supplemental categories
/// in the file.
List<String> supplementalCategoryRawInputsForSave(
  Map<String, String> allValues,
  Map<String, dynamic>? currentMetadata,
) {
  String pickSlot(int slot) {
    final keys = <String>[
      'SupplementalCategories$slot',
      'Supp Cat $slot',
    ];
    for (final key in keys) {
      final fromForm = allValues[key]?.trim() ?? '';
      if (fromForm.isNotEmpty) return fromForm;
    }
    for (final key in keys) {
      final fromMeta = currentMetadata?[key]?.toString().trim() ?? '';
      if (fromMeta.isNotEmpty) return fromMeta;
    }
    return '';
  }

  String s1 = pickSlot(1);
  String s2 = pickSlot(2);
  String s3 = pickSlot(3);

  if (s1.isEmpty && s2.isEmpty && s3.isEmpty && currentMetadata != null) {
    final combined = combinedSupplementalCategoriesValue(currentMetadata);
    if (combined is List && combined.isNotEmpty) {
      s1 = combined
          .map((e) => e.toString().trim())
          .where((x) => x.isNotEmpty)
          .join(',');
    } else if (combined is String && combined.trim().isNotEmpty) {
      s1 = combined.trim();
    }
  }

  return [s1, s2, s3];
}

/// Normalizes supplemental category input for Photo Mechanic compatibility
///
/// Takes raw UI input (from Supp Cat 1/2/3 fields or combined strings) and returns
/// a normalized, deduplicated list ready for XMP photoshop:SupplementalCategories bag.
///
/// Rules:
/// - Splits on commas and whitespace
/// - Trims and uppercases each value
/// - Removes empty values
/// - Deduplicates while preserving first occurrence
/// - Returns empty list if no valid values
List<String> normalizeSupplementalCategories(List<String> inputs) {
  print(
      'DEBUG: normalizeSupplementalCategories - Raw inputs received: $inputs');
  final List<String> allValues = [];

  // Process each input string
  for (final input in inputs) {
    if (input.trim().isEmpty) continue;

    print(
        'DEBUG: normalizeSupplementalCategories - Processing input: "$input"');

    // Handle corrupted array string format like "[A, B, C]" or nested brackets
    String cleanInput = input;
    if (cleanInput.startsWith('[') && cleanInput.endsWith(']')) {
      cleanInput = cleanInput.substring(1, cleanInput.length - 1);
      print(
          'DEBUG: normalizeSupplementalCategories - Removed outer brackets: "$cleanInput"');
    }

    // Remove any remaining corrupted nested bracket patterns
    cleanInput = cleanInput.replaceAll(RegExp(r'\[+|\]+'), '');
    print(
        'DEBUG: normalizeSupplementalCategories - After bracket cleanup: "$cleanInput"');

    // Split on commas and whitespace
    final parts = cleanInput.split(RegExp(r'[,\s]+'));
    for (final part in parts) {
      final trimmed = part.trim().toUpperCase();
      if (trimmed.isNotEmpty &&
          !trimmed.contains('[') &&
          !trimmed.contains(']')) {
        allValues.add(trimmed);
        print(
            'DEBUG: normalizeSupplementalCategories - Added clean value: "$trimmed"');
      }
    }
  }

  // Deduplicate while preserving first occurrence
  final seen = <String>{};
  final result = <String>[];
  for (final value in allValues) {
    if (seen.add(value)) {
      result.add(value);
    }
  }

  print('DEBUG: normalizeSupplementalCategories - Final result: $result');
  return result;
}

/// Case-sensitive dedupe of list items, keeping first occurrence.
List<String> dedupeMetadataListValues(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) out.add(trimmed);
  }
  return out;
}

/// Builds ExifTool arguments for setting supplemental categories with proper overwrite semantics
///
/// This function implements Photo Mechanic compatible behavior:
/// - Clears IPTC / XMP supplemental-category aliases completely
/// - Adds each normalized category as a separate array item in IPTC and
///   XMP-photoshop (never writes the bare `-SupplementalCategories=` alias
///   alongside IPTC — those are the same tag and would double every value)
/// - Ensures proper overwrite (no merging with existing values)
///
/// Returns a list of ExifTool arguments to be added to the command
List<String> buildSupplementalCategoriesArgs(List<String> rawInputs) {
  final List<String> normalizedSuppCats =
      normalizeSupplementalCategories(rawInputs);
  final List<String> args = [];

  print('DEBUG: Supplemental Categories - Raw inputs: $rawInputs');
  print('DEBUG: Supplemental Categories - Normalized: $normalizedSuppCats');
  print('DEBUG: Supplemental Categories - Save path: ExifTool');

  // Always clear all related fields first to guarantee overwrite semantics.
  args.add('-SupplementalCategories=');
  args.add('-IPTC:SupplementalCategories=');
  args.add('-XMP:SupplementalCategories=');
  args.add('-XMP-photoshop:SupplementalCategories=');

  // One `=` per value into each distinct bag (not `+=`). ExifTool ignores an
  // IPTC clear when `+=` follows in the same invocation; repeated `=` replaces
  // the list with individual entries. Do not also write the bare
  // SupplementalCategories alias — it maps to IPTC and doubles the list.
  for (final cat in normalizedSuppCats) {
    args.add('-IPTC:SupplementalCategories=$cat');
    args.add('-XMP-photoshop:SupplementalCategories=$cat');
  }

  return args;
}

/// Builds ExifTool arguments for Country Code (IPTC 2:100) with replace + dedupe.
///
/// Clears IPTC / XMP country-code aliases, then writes a single ISO code to
/// IPTC Country-PrimaryLocationCode and XMP-iptcCore:CountryCode.
List<String> buildCountryCodeArgs(String? raw) {
  final parts = dedupeMetadataListValues(
    (raw ?? '').split(RegExp(r'[,;/\s]+')),
  );
  // Country code is a single ISO value; keep the first unique token.
  final code = parts.isEmpty ? '' : parts.first;

  final args = <String>[
    '-CountryCode=',
    '-Country-PrimaryLocationCode=',
    '-IPTC:Country-PrimaryLocationCode=',
    '-XMP:CountryCode=',
    '-XMP-iptcCore:CountryCode=',
  ];
  if (code.isNotEmpty) {
    args.add('-Country-PrimaryLocationCode=$code');
    args.add('-XMP-iptcCore:CountryCode=$code');
  }
  return args;
}
