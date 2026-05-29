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

  /// Shown in the startup IPTC panel when caption/personality exist in files.
  /// Display-only — never persisted or written to IPTC.
  static const String inAppGeneratedPlaceholder = 'To be generated in app';

  static bool isInAppGeneratedPlaceholder(String? value) {
    return value?.trim().toLowerCase() ==
        inAppGeneratedPlaceholder.toLowerCase();
  }

  static bool isInAppGeneratedFieldKey(String key) {
    final presetKey = toPresetKey(key);
    return inAppGeneratedPresetKeys.contains(key) ||
        inAppGeneratedPresetKeys.contains(presetKey);
  }

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
      case 'Location':
        return 'Stadium';
      case 'ObjectName':
        return 'Object Name';
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
      if (v.isEmpty || isInAppGeneratedPlaceholder(v)) continue;
      final presetKey = toPresetKey(e.key);
      if (inAppGeneratedPresetKeys.contains(presetKey)) continue;
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

  /// ExifTool CLI: hyphenated bare tags (e.g. [Sub-location]) must use `--Tag=value`
  /// or they are parsed as invalid options.
  static String exiftoolWriteArg(String tag, String value) {
    final needsDoubleDash = !tag.contains(':') && tag.contains('-');
    final prefix = needsDoubleDash ? '--' : '-';
    return '$prefix$tag=$value';
  }

  /// Registers every ExifTool tag alias the Edit IPTC dialog writes for [presetKey].
  ///
  /// Photo Mechanic / JPEG files often only update when both the short tag
  /// (e.g. [Headline], [CaptionWriter]) and the IPTC: form are set — same as
  /// [MetadataPopupDialog._buildOutgoingMetadataFromState].
  static void addExiftoolTagsForPresetKey(
    Map<String, String> into,
    String presetKey,
    String value,
  ) {
    final v = value.trim();
    if (v.isEmpty) return;

    void tag(String name) => into[name] = v;

    switch (presetKey) {
      case 'Creator':
        tag('Creator');
        tag('IPTC:By-line');
        break;
      case 'MEID':
        tag('TransmissionReference');
        tag('OriginalTransmissionReference');
        tag('IPTC:OriginalTransmissionReference');
        break;
      case 'Description Writers':
        tag('CaptionWriter');
        tag('IPTC:Writer-Editor');
        break;
      case 'Creator\'s Job Title':
        tag('AuthorsPosition');
        tag('By-lineTitle');
        tag('IPTC:By-lineTitle');
        break;
      case 'Copyright':
        // Prefer CopyrightNotice — bare "Copyright" can clash with exiftool's
        // -copyright switch; Rights is lang-alt XMP that PM also reads.
        tag('CopyrightNotice');
        tag('IPTC:CopyrightNotice');
        tag('Rights');
        tag('XMP:Rights');
        break;
      case 'Credit':
        tag('Credit');
        tag('IPTC:Credit');
        break;
      case 'Source':
        tag('Source');
        tag('IPTC:Source');
        break;
      case 'Headline':
        tag('Headline');
        tag('IPTC:Headline');
        break;
      case 'Category':
        tag('Category');
        tag('IPTC:Category');
        break;
      case 'Object Name':
      case 'ObjectName':
        // Written in [applyObjectName]; include PM / iptcExt "Title" alias.
        _tagObjectNameAliases(into, v);
        break;
      case 'Stadium':
      case 'Location':
        tag('Sub-location');
        tag('SubLocation');
        tag('IPTC:Sub-location');
        tag('IPTC:SubLocation');
        tag('Location');
        tag('XMP:Location');
        break;
      case 'City':
        tag('City');
        tag('IPTC:City');
        break;
      case 'Province/State':
        tag('Province-State');
        tag('ProvinceState');
        tag('IPTC:Province-State');
        tag('IPTC:ProvinceState');
        tag('State');
        tag('XMP:State');
        break;
      case 'Country':
        tag('Country');
        tag('CountryPrimaryLocationName');
        tag('IPTC:CountryPrimaryLocationName');
        break;
      case 'Country Code':
        tag('CountryCode');
        tag('CountryPrimaryLocationCode');
        tag('IPTC:CountryPrimaryLocationCode');
        break;
      case 'Special Instructions':
        tag('SpecialInstructions');
        tag('IPTC:SpecialInstructions');
        break;
      case 'Personality':
        tag('XMP-getty:Personality');
        tag('Personality');
        break;
      case 'Caption':
        tag('IPTC:Description');
        tag('Description');
        tag('Caption-Abstract');
        tag('IPTC:Caption-Abstract');
        break;
      case 'Urgency':
        tag('Urgency');
        tag('IPTC:Urgency');
        break;
      case 'Creator\'s Identity':
        tag('XMP:CreatorIdentity');
        tag('CreatorIdentity');
        break;
      case 'Date':
      case 'Time':
      case 'Time and Date':
      case 'Keywords':
      case 'Supp Cat 1':
      case 'Supp Cat 2':
      case 'Supp Cat 3':
        break;
      default:
        break;
    }
  }

  /// All ExifTool keys for Getty / Photo Mechanic **Title** (= Object Name slug).
  ///
  /// PM often shows slugs like `776360337_MB_00_LEAFS` under Title / Object Name.
  /// Writes IPTC Object Name plus [XMP:Title] (dc:title) — not iptcExt:Title, which
  /// ExifTool does not support on JPEG.
  static void _tagObjectNameAliases(Map<String, String> into, String value) {
    into['IPTC:ObjectName'] = value;
    into['ObjectName'] = value;
    into['XMP:Title'] = value;
  }

  /// IPTC Object Name / XMP Title — dedicated pass so it isn't lost in large batches.
  static Future<bool> applyObjectName(String imagePath, String value) async {
    final v = value.trim();
    if (v.isEmpty) return true;

    final args = <String>[
      exiftoolWriteArg('IPTC:ObjectName', v),
      exiftoolWriteArg('ObjectName', v),
      exiftoolWriteArg('XMP:Title', v),
      '-charset',
      'iptc=UTF8',
      '-overwrite_original',
      imagePath,
    ];

    final proc = await ExiftoolHelper.run(args);
    if (!proc.isSuccess) {
      print('IPTC Object Name apply failed for $imagePath: ${proc.stderrText}');
      print('IPTC Object Name apply args: ${args.join(' ')}');
      return false;
    }
    return true;
  }

  static String? _meidFromPreset(Map<String, String> preset) {
    for (final key in const [
      'MEID',
      'TransmissionReference',
      'OriginalTransmissionReference',
      'JobID',
    ]) {
      final v = preset[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _descriptionWritersFromPreset(Map<String, String> preset) {
    for (final key in const [
      'Description Writers',
      'CaptionWriter',
      'Writer-Editor',
    ]) {
      final v = preset[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _objectNameFromPreset(Map<String, String> preset) {
    for (final key in const ['Object Name', 'ObjectName']) {
      final v = preset[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Supp cat used as team code in Getty object-name slugs (e.g. …_LEAFS).
  static String? _teamCodeFromPreset(Map<String, String> preset) {
    for (final key in const ['Supp Cat 3', 'Supp Cat 2', 'Supp Cat 1']) {
      final v = preset[key]?.trim();
      if (v != null && v.isNotEmpty && v != 'SPO') return v;
    }
    return null;
  }

  /// Builds `MEID_WRITER_00_TEAM` (e.g. 776360337_MB_00_LEAFS) when components exist.
  static String? buildGettyObjectNameSlug(
    Map<String, String> preset, {
    required int imageIndex,
  }) {
    final meid = _meidFromPreset(preset);
    final writer = _descriptionWritersFromPreset(preset);
    if (meid == null || writer == null) return null;

    final seq = imageIndex.toString().padLeft(2, '0');
    final team = _teamCodeFromPreset(preset);
    if (team != null && team.isNotEmpty) {
      return '${meid}_${writer}_${seq}_$team';
    }
    return '${meid}_${writer}_$seq';
  }

  /// Explicit Object Name from template, else Getty slug from MEID + writer + index + supp cat.
  static String? resolveObjectNameForImage(
    Map<String, String> preset, {
    int? imageIndex,
  }) {
    final explicit = _objectNameFromPreset(preset);
    if (explicit != null && explicit.isNotEmpty) {
      if (imageIndex != null && explicit.contains('{seq}')) {
        return explicit.replaceAll(
          '{seq}',
          imageIndex.toString().padLeft(2, '0'),
        );
      }
      return explicit;
    }
    if (imageIndex == null) return null;
    return buildGettyObjectNameSlug(preset, imageIndex: imageIndex);
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
    int? imageIndex,
  }) async {
    final preset = normalizeForPreset(template);
    if (preset.isEmpty) return true;

    final keywords = preset['Keywords']?.trim() ?? '';
    final objectName =
        resolveObjectNameForImage(preset, imageIndex: imageIndex);
    if (objectName != null) {
      print(
        'IPTC apply Object Name for $imagePath: $objectName (index=$imageIndex)',
      );
    }

    try {
      // Title / Object Name first — still written if the main batch fails later.
      if (objectName != null) {
        final ok = await applyObjectName(imagePath, objectName);
        if (!ok) return false;
      }

      if (keywords.isNotEmpty) {
        await applyKeywords(imagePath, keywords);
      }

      final allValues = <String, String>{};
      preset.forEach((key, value) {
        if (value.trim().isEmpty) return;
        if (key == 'Keywords') return;
        if (key == 'Object Name' || key == 'ObjectName') return;
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
          addExiftoolTagsForPresetKey(allValues, key, value);
        }
      });

      if (objectName != null) {
        _tagObjectNameAliases(allValues, objectName);
      }

      if (allValues.isEmpty && keywords.isEmpty && objectName == null) {
        return true;
      }

      // Match MetadataPopupDialog save order/flags (no -m, which hides write failures).
      final args = <String>[];

      allValues.forEach((tag, value) {
        if (value.trim().isNotEmpty) {
          args.add(exiftoolWriteArg(tag, value));
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
          arg.contains('SupplementalCategories1') ||
          arg.contains('SupplementalCategories2') ||
          arg.contains('SupplementalCategories3'));
      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      args.add('-overwrite_original');
      args.add(imagePath);

      var mainOk = true;
      if (args.length > 2) {
        final proc = await ExiftoolHelper.run(args);
        mainOk = proc.isSuccess;
        if (!mainOk) {
          print('IPTC template apply failed for $imagePath: ${proc.stderrText}');
          print('IPTC template apply args: ${args.join(' ')}');
        }
      }

      // Re-apply Object Name after main batch in case a tag in that batch cleared it.
      if (objectName != null) {
        final ok = await applyObjectName(imagePath, objectName);
        if (!ok) return false;
      }

      return mainOk;
    } catch (e) {
      print('IPTC template apply error for $imagePath: $e');
      return false;
    }
  }
}
