import '../helpers.dart';
import '../utils/exiftool_helper.dart';

/// When (if ever) the startup IPTC template is written to image files.
enum IptcApplyMode {
  none,
  onImport,
  onSave;

  static IptcApplyMode fromStorage(String? value) {
    switch (value) {
      case 'on_import':
        return IptcApplyMode.onImport;
      case 'on_save':
        return IptcApplyMode.onSave;
      default:
        return IptcApplyMode.none;
    }
  }

  String get storageValue {
    switch (this) {
      case IptcApplyMode.onImport:
        return 'on_import';
      case IptcApplyMode.onSave:
        return 'on_save';
      case IptcApplyMode.none:
        return 'none';
    }
  }
}

/// Applies startup / metadata-preset IPTC values to image files (Photo Mechanic style).
class IptcTemplateApplyService {
  IptcTemplateApplyService._();

  /// Panel order for urgency dropdown (Photo Mechanic).
  static const List<String> urgencyValues = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '0',
  ];

  /// Fields generated in-app; not written when applying a template on ingest.
  static const Set<String> inAppGeneratedPresetKeys = {
    'Caption',
    'Personality',
  };

  static String urgencyMenuLabel(String value) {
    switch (value) {
      case '1':
        return 'High';
      case '5':
        return 'Normal';
      case '8':
        return 'Low';
      case '0':
        return 'Undefined';
      default:
        return value;
    }
  }

  static String normalizeUrgencyValue(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return '5';
    if (urgencyValues.contains(v)) return v;
    final lower = v.toLowerCase();
    if (lower == 'high') return '1';
    if (lower == 'normal') return '5';
    if (lower == 'low') return '8';
    if (lower == 'undefined') return '0';
    return '5';
  }

  /// Maps panel / storage keys to metadata-preset JSON keys.
  static String toPresetKey(String key) {
    switch (key) {
      case 'Job Title':
        return 'Creator\'s Job Title';
      default:
        return key;
    }
  }

  /// Maps metadata-preset keys to panel storage keys.
  static String toPanelKey(String presetKey) {
    switch (presetKey) {
      case 'Creator\'s Job Title':
        return 'Job Title';
      default:
        return presetKey;
    }
  }

  static Map<String, String> normalizeForPreset(Map<String, String> raw) {
    final out = <String, String>{};
    for (final e in raw.entries) {
      final v = e.value.trim();
      if (v.isEmpty) continue;
      final presetKey = toPresetKey(e.key);
      if (presetKey == 'Urgency') {
        out[presetKey] = normalizeUrgencyValue(v);
      } else {
        out[presetKey] = v;
      }
    }
    return out;
  }

  static Map<String, String> denormalizeForPanel(Map<String, String> preset) {
    final out = <String, String>{};
    for (final e in preset.entries) {
      final v = e.value.trim();
      if (v.isEmpty) continue;
      out[toPanelKey(e.key)] = e.key == 'Urgency' ? normalizeUrgencyValue(v) : v;
    }
    return out;
  }

  static String? lookupValue(Map<String, String> values, String storageKey) {
    final presetKey = toPresetKey(storageKey);
    final v = values[storageKey] ?? values[presetKey] ?? values[toPanelKey(presetKey)];
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  static String? exiftoolTagForPresetKey(String key) {
    switch (key) {
      case 'Creator':
        return 'IPTC:By-line';
      case 'MEID':
        return 'IPTC:OriginalTransmissionReference';
      case 'Description Writers':
        return 'CaptionWriter';
      case 'Creator\'s Job Title':
        return 'IPTC:By-lineTitle';
      case 'Copyright':
        return 'IPTC:CopyrightNotice';
      case 'Credit':
        return 'IPTC:Credit';
      case 'Source':
        return 'IPTC:Source';
      case 'Headline':
        return 'IPTC:Headline';
      case 'Category':
        return 'IPTC:Category';
      case 'Object Name':
        return 'IPTC:ObjectName';
      case 'Stadium':
        return 'IPTC:Sub-location';
      case 'City':
        return 'IPTC:City';
      case 'Province/State':
        return 'IPTC:Province-State';
      case 'Country':
        return 'IPTC:Country-Primary-Location-Name';
      case 'Country Code':
        return 'IPTC:Country-Primary-Location-Code';
      case 'Special Instructions':
        return 'IPTC:Special-Instructions';
      case 'Personality':
        return 'XMP-getty:Personality';
      case 'Caption':
        return 'IPTC:Caption-Abstract';
      case 'Urgency':
        return 'IPTC:Urgency';
      case 'Creator\'s Identity':
        return 'XMP:CreatorIdentity';
      case 'Date':
      case 'Time':
      case 'Time and Date':
        return null;
      default:
        return null;
    }
  }

  /// Writes keywords using clear-then-add (Photo Mechanic compatible).
  static Future<void> applyKeywords(String imagePath, String keywordsValue) async {
    final cleanValue = keywordsValue.trim();
    if (cleanValue.startsWith('[') && cleanValue.endsWith(']')) {
      keywordsValue = cleanValue.substring(1, cleanValue.length - 1);
    } else {
      keywordsValue = cleanValue;
    }

    if (keywordsValue.isEmpty) {
      final clearArgs = [
        '-IPTC:Keywords=',
        '-Subject=',
        '-XMP-dc:Subject=',
        '-XMP:Subject=',
        '-Keywords=',
        '-XMP:Keywords=',
        '-XMP-photoshop:Keywords=',
        '-overwrite_original',
        imagePath,
      ];
      final proc = await ExiftoolHelper.run(clearArgs);
      if (!proc.isSuccess) {
        throw Exception('Failed to clear keywords: ${proc.stderrText}');
      }
      return;
    }

    final kw = keywordsValue
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (kw.isEmpty) return;

    final clearArgs = [
      '-Subject=',
      '-XMP-dc:Subject=',
      '-XMP:Subject=',
      '-Keywords=',
      '-IPTC:Keywords=',
      '-XMP:Keywords=',
      '-XMP-photoshop:Keywords=',
      '-overwrite_original',
      imagePath,
    ];
    final clearProc = await ExiftoolHelper.run(clearArgs);
    if (!clearProc.isSuccess) {
      throw Exception('Failed to clear keywords: ${clearProc.stderrText}');
    }

    final addArgs = <String>[
      '-Subject=${kw.join(', ')}',
      for (final keyword in kw) '-IPTC:Keywords+=$keyword',
      '-overwrite_original',
      imagePath,
    ];
    final addProc = await ExiftoolHelper.run(addArgs);
    if (!addProc.isSuccess) {
      throw Exception('Failed to write keywords: ${addProc.stderrText}');
    }
  }

  /// Applies [template] (preset display keys) to [imagePath].
  static Future<bool> applyToImage(
    String imagePath,
    Map<String, String> template, {
    bool skipInAppGenerated = true,
  }) async {
    final preset = normalizeForPreset(template);
    if (preset.isEmpty) return true;

    final keywords = preset['Keywords']?.trim() ?? '';

    try {
      if (keywords.isNotEmpty) {
        await applyKeywords(imagePath, keywords);
      }

      final allValues = <String, String>{};
      preset.forEach((key, value) {
        if (value.trim().isEmpty) return;
        if (key == 'Keywords') return;
        if (skipInAppGenerated && inAppGeneratedPresetKeys.contains(key)) {
          return;
        }
        if (key == 'Supp Cat 1') {
          allValues['SupplementalCategories1'] = value;
        } else if (key == 'Supp Cat 2') {
          allValues['SupplementalCategories2'] = value;
        } else if (key == 'Supp Cat 3') {
          allValues['SupplementalCategories3'] = value;
        } else {
          final tag = exiftoolTagForPresetKey(key);
          if (tag != null) {
            allValues[tag] = value;
          }
        }
      });

      if (allValues.isEmpty && keywords.isEmpty) return true;

      final args = <String>[
        '-overwrite_original',
        '-P',
        '-m',
        '-charset',
        'iptc=UTF8',
      ];

      allValues.forEach((tag, value) {
        if (value.trim().isNotEmpty) {
          args.add('-$tag=$value');
        }
      });

      final metadataForSupp = <String, dynamic>{
        for (final e in preset.entries) e.key: e.value,
      };
      final rawInputs = supplementalCategoryRawInputsForSave(
        allValues,
        metadataForSupp,
      );
      args.removeWhere((arg) =>
          arg.startsWith('-SupplementalCategories') ||
          arg.startsWith('-XMP-photoshop:SupplementalCategories'));
      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      args.add(imagePath);

      if (args.length <= 5 && keywords.isEmpty) return true;

      final proc = await ExiftoolHelper.run(args);
      if (!proc.isSuccess) {
        print('IPTC template apply failed for $imagePath: ${proc.stderrText}');
        return false;
      }
      return true;
    } catch (e) {
      print('IPTC template apply error for $imagePath: $e');
      return false;
    }
  }
}
