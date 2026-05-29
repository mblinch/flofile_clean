import '../helpers.dart';
import '../utils/exiftool_helper.dart';
import 'iptc_template_import_service.dart';

/// Fields to write when applying a preset to one image (skip-unchanged path).
class _IptcWritePlan {
  const _IptcWritePlan({
    required this.presetFields,
    this.keywords,
    this.objectName,
    required this.skipEntirely,
  });

  final Map<String, String> presetFields;
  final String? keywords;
  final String? objectName;
  final bool skipEntirely;
}

/// Result of applying IPTC template values to one image file.
class IptcApplyToImageResult {
  const IptcApplyToImageResult({
    required this.success,
    this.skipped = false,
  });

  final bool success;
  /// True when every template field already matched file metadata (no ExifTool write).
  final bool skipped;
}

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
      case 'SpecialInstructions':
        return 'Special Instructions';
      case 'Creators Identity':
        return 'Creator\'s Identity';
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
        // Photo Mechanic often displays the XMP Instructions field.
        tag('XMP:Instructions');
        tag('XMP-photoshop:Instructions');
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
      case 'Creators Identity':
        // PM stores this in the PhotoMechanic XMP namespace (not dc/XMP core).
        tag('XMP-photomech:CreatorIdentity');
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

  static Set<String> _keywordSet(String raw) {
    var s = raw.trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1);
    }
    return s
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static bool _keywordsMatch(String expected, String existing) {
    return _keywordSet(expected) == _keywordSet(existing);
  }

  static bool _fieldNeedsWrite(String presetKey, String expected, String existing) {
    final e = expected.trim();
    if (e.isEmpty) return false;
    final x = existing.trim();
    if (presetKey == 'Urgency') {
      return normalizeUrgencyValue(e) != normalizeUrgencyValue(x);
    }
    if (presetKey.startsWith('Supp Cat')) {
      return e.toUpperCase() != x.toUpperCase();
    }
    return e != x;
  }

  /// Preset fields (plus keywords / object name) that differ from [existingMeta].
  static _IptcWritePlan _writePlanForImage(
    Map<String, String> preset,
    Map<String, dynamic> existingMeta, {
    bool skipInAppGenerated = true,
    int? imageIndex,
  }) {
    final existing =
        IptcTemplateImportService.panelValuesFromExiftool(existingMeta);
    final changed = <String, String>{};

    // If any supp cat differs, rewrite all preset slots (full bag overwrite).
    var anySuppOutOfSync = false;
    for (var i = 1; i <= 3; i++) {
      final key = 'Supp Cat $i';
      final v = preset[key]?.trim();
      if (v == null || v.isEmpty) continue;
      if (_fieldNeedsWrite(key, v, existing[key] ?? '')) {
        anySuppOutOfSync = true;
        break;
      }
    }
    if (anySuppOutOfSync) {
      for (var i = 1; i <= 3; i++) {
        final key = 'Supp Cat $i';
        final v = preset[key]?.trim() ?? '';
        if (v.isNotEmpty) changed[key] = v;
      }
    }

    preset.forEach((key, value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (key == 'Keywords' ||
          key == 'Object Name' ||
          key == 'ObjectName' ||
          key.startsWith('Supp Cat')) {
        return;
      }
      if (skipInAppGenerated && inAppGeneratedPresetKeys.contains(key)) {
        return;
      }
      final existingVal = existing[key] ?? '';
      if (_fieldNeedsWrite(key, v, existingVal)) {
        changed[key] = v;
      }
    });

    final keywordsRaw = preset['Keywords']?.trim() ?? '';
    final keywords = keywordsRaw.isNotEmpty &&
            !_keywordsMatch(keywordsRaw, existing['Keywords'] ?? '')
        ? keywordsRaw
        : null;

    final resolvedObjectName =
        resolveObjectNameForImage(preset, imageIndex: imageIndex);
    final objectName = resolvedObjectName != null &&
            _fieldNeedsWrite(
              'Object Name',
              resolvedObjectName,
              existing['Object Name'] ?? '',
            )
        ? resolvedObjectName
        : null;

    return _IptcWritePlan(
      presetFields: changed,
      keywords: keywords,
      objectName: objectName,
      skipEntirely:
          changed.isEmpty && keywords == null && objectName == null,
    );
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
  ///
  /// When [existingMetadata] is supplied, fields that already match the template
  /// are skipped (no ExifTool write for that field). Returns [IptcApplyToImageResult.skipped]
  /// when the entire image is unchanged.
  static Future<IptcApplyToImageResult> applyToImage(
    String imagePath,
    Map<String, String> template, {
    bool skipInAppGenerated = true,
    int? imageIndex,
    Map<String, dynamic>? existingMetadata,
  }) async {
    final preset = normalizeForPreset(template);
    if (preset.isEmpty) {
      return const IptcApplyToImageResult(success: true, skipped: true);
    }

    Map<String, dynamic>? meta = existingMetadata;
    meta ??= await IptcTemplateImportService.readMetadata(imagePath);

    final Map<String, String> fieldsToWrite;
    final String? keywordsToWrite;
    final String? objectNameToWrite;

    if (meta != null) {
      final plan = _writePlanForImage(
        preset,
        meta,
        skipInAppGenerated: skipInAppGenerated,
        imageIndex: imageIndex,
      );
      if (plan.skipEntirely) {
        return const IptcApplyToImageResult(success: true, skipped: true);
      }
      fieldsToWrite = plan.presetFields;
      keywordsToWrite = plan.keywords;
      objectNameToWrite = plan.objectName;
    } else {
      fieldsToWrite = Map<String, String>.from(preset)
        ..removeWhere((key, _) =>
            key == 'Keywords' ||
            key == 'Object Name' ||
            key == 'ObjectName' ||
            (skipInAppGenerated && inAppGeneratedPresetKeys.contains(key)));
      final kw = preset['Keywords']?.trim();
      keywordsToWrite = (kw == null || kw.isEmpty) ? null : kw;
      objectNameToWrite =
          resolveObjectNameForImage(preset, imageIndex: imageIndex);
    }

    if (fieldsToWrite.isEmpty &&
        keywordsToWrite == null &&
        objectNameToWrite == null) {
      return const IptcApplyToImageResult(success: true, skipped: true);
    }

    try {
      if (keywordsToWrite != null) {
        await applyKeywords(imagePath, keywordsToWrite);
      }

      if (objectNameToWrite != null) {
        final objectOk =
            await applyObjectName(imagePath, objectNameToWrite);
        if (!objectOk) {
          return const IptcApplyToImageResult(success: false);
        }
      }

      final allValues = <String, String>{};
      fieldsToWrite.forEach((key, value) {
        if (value.trim().isEmpty) return;
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

      var mainOk = true;
      if (allValues.isNotEmpty) {
        final args = <String>[];

        allValues.forEach((tag, value) {
          if (value.trim().isNotEmpty) {
            args.add(exiftoolWriteArg(tag, value));
          }
        });

        final metadataForSupp = <String, dynamic>{
          for (final e in fieldsToWrite.entries) e.key: e.value,
        };
        if (fieldsToWrite.keys.any((k) => k.startsWith('Supp Cat'))) {
          final existing = meta != null
              ? IptcTemplateImportService.panelValuesFromExiftool(meta)
              : <String, String>{};
          for (var i = 1; i <= 3; i++) {
            final key = 'Supp Cat $i';
            final value = fieldsToWrite[key] ??
                preset[key] ??
                existing[key] ??
                '';
            if (value.trim().isNotEmpty) {
              metadataForSupp[key] = value.trim();
              allValues['SupplementalCategories$i'] = value.trim();
            }
          }
        }
        final rawInputs = supplementalCategoryRawInputsForSave(
          allValues,
          meta,
        );
        args.removeWhere((arg) =>
            arg.contains('SupplementalCategories1') ||
            arg.contains('SupplementalCategories2') ||
            arg.contains('SupplementalCategories3'));
        args.addAll(buildSupplementalCategoriesArgs(rawInputs));

        args.addAll(['-charset', 'iptc=UTF8']);
        args.add('-overwrite_original');
        args.add(imagePath);

        final proc = await ExiftoolHelper.run(args);
        mainOk = proc.isSuccess;
        if (!mainOk) {
          print('IPTC template apply failed for $imagePath: ${proc.stderrText}');
          print('IPTC template apply args: ${args.join(' ')}');
        }
      }

      return IptcApplyToImageResult(success: mainOk);
    } catch (e) {
      print('IPTC template apply error for $imagePath: $e');
      return const IptcApplyToImageResult(success: false);
    }
  }
}
