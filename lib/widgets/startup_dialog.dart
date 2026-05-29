import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/native_file_picker.dart';
import 'dart:io';
import '../services/api_manager.dart';
import 'dart:convert'; // Added for jsonDecode
import '../utils/exiftool_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import '../services/preferences_service.dart';
import '../caption_style/caption_template.dart';
import 'startup_caption_layout_preview.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/iptc_template_apply_service.dart';
import '../services/iptc_template_import_service.dart';
import 'startup_iptc_template_panel.dart';
import 'sport_selection_dialog.dart';

// Custom button widget with cursor styling (matching the one in caption_fields_widget.dart)
class CustomButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const CustomButton({
    super.key,
    required this.onTap,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class StartupDialog extends StatefulWidget {
  final void Function(
    String folderPath,
    String? homeTeam,
    String? awayTeam,
    Map<String, String> iptcPreset,
  ) onConfigurationComplete;
  final String? sport; // Current sport mode
  final ValueChanged<String>? onSportSelected;
  final VoidCallback? onBackToSportSelection;
  final bool inline;

  const StartupDialog({
    Key? key,
    required this.onConfigurationComplete,
    this.sport,
    this.onSportSelected,
    this.onBackToSportSelection,
    this.inline = false,
  }) : super(key: key);

  @override
  State<StartupDialog> createState() => _StartupDialogState();
}

class _StartupDialogState extends State<StartupDialog> {
  String? selectedFolderPath;
  String? selectedHomeTeam;
  String? selectedAwayTeam;
  DateTime? selectedGameDate;
  List<String> availableTeams = [];
  bool isLoadingTeams = false;
  bool isLoadingFolder = false;
  bool hasImagesInFolder = false;
  bool isExtractingDate = false;
  IptcApplyMode _iptcApplyMode = IptcApplyMode.none;
  bool _burstDetectionEnabled = false;

  Map<String, String> _iptcTemplateValues = {};
  final Set<String> _iptcKeysFoundInFiles = {};
  bool _loadingIptcFromFiles = false;
  bool _loadingExternalTemplate = false;
  /// Set when an external template is loaded before an images folder is chosen.
  bool _iptcTemplateLoadedBeforeFolder = false;
  int _iptcTemplateRevision = 0;
  WireStyle _iptcWireStyle = WireStyle.getty;
  /// Panel keys whose template value is intentionally blank → cleared from files on import.
  Set<String> _iptcTemplateClearedFields = {};
  List<String> _selectedImageFiles = [];
  final Map<WireStyle, String> _wireLabels = {};

  // Network status
  bool _isOffline = false;

  final ApiManager _apiManager = ApiManager();

  // Preferences service and favorite teams
  late PreferencesService _preferencesService;
  Set<String> _favoriteTeams = {};
  String? _favoriteHomeTeam;
  String? _favoriteAwayTeam;
  String? _goTimeWarningText;
  static const bool _showStartupCoachInfo = false;
  String? _homeCoachRole;
  String? _awayCoachRole;
  bool _homeCoachLoading = false;
  bool _awayCoachLoading = false;
  String _homeCoachName = '';
  String _awayCoachName = '';

  bool get _folderChosen => selectedFolderPath != null;

  bool get _sportChosen =>
      widget.sport != null && widget.sport!.trim().isNotEmpty;

  bool get _teamsChosen =>
      selectedHomeTeam != null &&
      selectedAwayTeam != null &&
      selectedHomeTeam != selectedAwayTeam;

  @override
  void initState() {
    super.initState();

    // Configure API Manager based on sport
    if (widget.sport != null) {
      _apiManager.setSport(widget.sport!);
    }

    _initializeAndLoadData();
  }

  @override
  void didUpdateWidget(StartupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sport != widget.sport && _sportChosen) {
      _apiManager.setSport(widget.sport!);
      unawaited(_reloadForSport());
    }
  }

  Future<void> _reloadForSport() async {
    if (!_sportChosen) return;
    await _initializePreferences();
    await _loadTeams();
  }

  Future<void> _initializeAndLoadData() async {
    _preferencesService = await PreferencesService.getInstance();
    await _loadIptcWireContext();
    _resetIptcTemplate();
    await _loadIptcApplyOptions();
    if (_sportChosen) {
      await _initializePreferences();
      await _loadTeams();
    }
  }

  Future<void> _loadIptcApplyOptions() async {
    final prefs = await PreferencesService.getInstance();
    final mode = await prefs.getIptcApplyMode();
    if (!mounted) return;
    setState(() => _iptcApplyMode = mode);
  }

  Future<void> _loadIptcWireContext() async {
    final prefs = await PreferencesService.getInstance();
    final template = await prefs.getCaptionTemplate();
    final gettyLabel = await prefs.getCaptionWireLabel(WireStyle.getty);
    final gettyIntlLabel =
        await prefs.getCaptionWireLabel(WireStyle.gettyInternational);
    final imagnLabel = await prefs.getCaptionWireLabel(WireStyle.imagn);
    final apLabel = await prefs.getCaptionWireLabel(WireStyle.ap);
    final cpLabel = await prefs.getCaptionWireLabel(WireStyle.cp);
    if (!mounted) return;
    setState(() {
      _iptcWireStyle = template.wireStyle;
      _wireLabels[WireStyle.getty] = gettyLabel ?? '';
      _wireLabels[WireStyle.gettyInternational] = gettyIntlLabel ?? '';
      _wireLabels[WireStyle.imagn] = imagnLabel ?? '';
      _wireLabels[WireStyle.ap] = apLabel ?? '';
      _wireLabels[WireStyle.cp] = cpLabel ?? '';
    });
  }

  Map<String, String> _normalizeIptcPresetMap(Map<String, dynamic> preset) {
    final raw = <String, String>{};
    preset.forEach((key, value) {
      final v = value?.toString().trim() ?? '';
      if (v.isEmpty) return;
      raw[key] = v;
    });
    return IptcTemplateApplyService.denormalizeForPanel(raw);
  }

  void _resetIptcTemplate() {
    if (!mounted) return;
    setState(() {
      _iptcTemplateValues = {};
      _iptcKeysFoundInFiles.clear();
    });
  }

  void _onSportSelected(String sport) {
    widget.onSportSelected?.call(sport);
  }

  void _onCaptionWireStyleChanged(WireStyle wire) {
    if (_iptcWireStyle == wire) return;
    setState(() => _iptcWireStyle = wire);
  }

  void _onIptcTemplateValueChanged(String storageKey, String value) {
    setState(() {
      final next = Map<String, String>.from(_iptcTemplateValues);
      var trimmed = value.trim();
      if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
        trimmed = '';
      }
      if (trimmed.isEmpty) {
        next.remove(storageKey);
      } else {
        next[storageKey] = trimmed;
      }
      _iptcTemplateValues = next;
    });
  }

  Future<void> _clearIptcTemplateValues() async {
    if (_loadingIptcFromFiles || _loadingExternalTemplate) return;
    setState(() {
      _iptcTemplateValues = {};
      _iptcKeysFoundInFiles.clear();
      _iptcTemplateLoadedBeforeFolder = false;
      _iptcApplyMode = IptcApplyMode.onImport;
      _iptcTemplateRevision++;
    });
    await _persistIptcTemplateValues();
  }

  Future<void> _loadOriginalIptcValuesFromFiles() async {
    if (_loadingIptcFromFiles || _loadingExternalTemplate) return;
    var imageFiles = List<String>.from(_selectedImageFiles);
    if (imageFiles.isEmpty && selectedFolderPath != null) {
      imageFiles = await _imageFilesInDirectory(selectedFolderPath!);
    }
    if (imageFiles.isEmpty || !mounted) return;

    setState(() => _loadingIptcFromFiles = true);
    try {
      final folderIptc = await _collectIptcFromFolderSample(imageFiles);
      if (!mounted) return;

      final merged = IptcTemplateApplyService.panelValuesFromImportedTemplate(
        folderIptc,
        _iptcWireStyle,
      );
      setState(() {
        _selectedImageFiles = imageFiles;
        _iptcTemplateValues = merged;
        _iptcKeysFoundInFiles
          ..clear()
          ..addAll(merged.keys.where(
            (key) => !IptcTemplateApplyService.isInAppGeneratedFieldKey(key),
          ));
        _iptcTemplateLoadedBeforeFolder = false;
        _iptcApplyMode = IptcApplyMode.onImport;
        _iptcTemplateRevision++;
      });
      await _persistIptcTemplateValues();
    } catch (e) {
      print('Error loading original IPTC values from files: $e');
    } finally {
      if (mounted) setState(() => _loadingIptcFromFiles = false);
    }
  }

  Future<void> _loadExternalIptcTemplate() async {
    if (_loadingExternalTemplate) return;

    String? lastTemplateDir;
    try {
      final prefs = await SharedPreferences.getInstance();
      lastTemplateDir = prefs.getString('last_template_folder');
    } catch (_) {}

    final filePath = await NativeFilePicker.pickFile(
      allowedExtensions: ['txt', 'xmp', 'jpg', 'jpeg'],
      initialDirectory: lastTemplateDir,
    );
    if (filePath == null || !mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_template_folder', File(filePath).parent.path);
    } catch (_) {}

    setState(() => _loadingExternalTemplate = true);
    try {
      final result = await IptcTemplateImportService.importFromPath(filePath);
      if (!mounted) return;

      if (result == null || result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No IPTC fields found in that file.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _iptcTemplateValues =
            IptcTemplateApplyService.panelValuesFromImportedTemplate(
          result.values,
          _iptcWireStyle,
        );
        _iptcKeysFoundInFiles.clear();
        _iptcApplyMode = IptcApplyMode.onImport;
        _iptcTemplateRevision++;
        if (selectedFolderPath == null) {
          _iptcTemplateLoadedBeforeFolder = true;
        }
      });
      await _persistIptcTemplateValues();

      final label = result.sourceLabel ?? 'Template';
      final skipped = result.skippedFieldCount;
      final skippedNote =
          skipped > 0 ? ' ($skipped proprietary fields skipped)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Loaded $label — ${result.values.length} fields$skippedNote',
          ),
          backgroundColor: const Color(0xFF4A7A96),
        ),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load template: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingExternalTemplate = false);
    }
  }

  /// Persists IPTC template + apply mode; returns normalized preset for immediate use.
  /// Preset keys whose template value is blank — to be cleared from files on import.
  Set<String> _computeClearedFields() {
    const neverClear = {'Time and Date', 'Date', 'Time'};
    return WireIptcSpecs.fieldsForPanel(_iptcWireStyle)
        .map((s) => s.storageKey)
        .where((k) => !neverClear.contains(k))
        .where((k) =>
            !_iptcTemplateValues.containsKey(k) ||
            _iptcTemplateValues[k]!.trim().isEmpty)
        .toSet();
  }

  Future<Map<String, String>> _persistIptcTemplateValues() async {
    final prefs = await SharedPreferences.getInstance();
    final preset =
        IptcTemplateApplyService.normalizeForPreset(_iptcTemplateValues);
    if (preset.isNotEmpty) {
      await prefs.setString(
        'selected_metadata_preset',
        jsonEncode(preset),
      );
    } else {
      await prefs.remove('selected_metadata_preset');
    }
    // Persist which panel fields are intentionally blank (to clear on import).
    _iptcTemplateClearedFields = _computeClearedFields();
    await prefs.setStringList(
      'selected_metadata_preset_cleared_fields',
      _iptcTemplateClearedFields.toList(),
    );
    final prefsService = await PreferencesService.getInstance();
    await prefsService.saveIptcApplyMode(_iptcApplyMode);
    return preset;
  }

  String _keywordsFromMeta(Map<String, dynamic> meta) {
    final raw = meta['IPTC:Keywords'] ??
        meta['Keywords'] ??
        meta['Subject'] ??
        meta['XMP:Subject'];
    if (raw == null) return '';
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .join(', ');
    }
    var s = raw.toString().trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1);
    }
    return s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .join(', ');
  }

  String _firstMetaValue(Map<String, dynamic> meta, List<String> keys) {
    for (final key in keys) {
      final raw = meta[key];
      if (raw == null) continue;
      if (raw is List) {
        final parts = raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(', ');
      } else {
        final v = raw.toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static const List<String> _iptcExiftoolTags = [
    '-IPTC:Description',
    '-Description',
    '-IPTC:By-line',
    '-By-line',
    '-Creator',
    '-IPTC:OriginalTransmissionReference',
    '-OriginalTransmissionReference',
    '-MEID',
    '-CaptionWriter',
    '-IPTC:By-lineTitle',
    '-By-lineTitle',
    '-IPTC:CopyrightNotice',
    '-Copyright',
    '-IPTC:Credit',
    '-Credit',
    '-IPTC:Source',
    '-Source',
    '-IPTC:Headline',
    '-Headline',
    '-IPTC:Keywords',
    '-Keywords',
    '-IPTC:Category',
    '-Category',
    '-IPTC:SupplementalCategories',
    '-SupplementalCategories',
    '-XMP-photoshop:SupplementalCategories',
    '-IPTC:ObjectName',
    '-ObjectName',
    '-IPTC:SubLocation',
    '-IPTC:Sub-location',
    '-SubLocation',
    '-Sub-location',
    '-Location',
    '-XMP:Location',
    '-XMP-iptcCore:Location',
    '-LocationShownSublocation',
    '-LocationCreatedSublocation',
    '-IPTC:City',
    '-City',
    '-IPTC:ProvinceState',
    '-IPTC:Province-State',
    '-ProvinceState',
    '-Province-State',
    '-State',
    '-XMP:State',
    '-XMP-photoshop:State',
    '-IPTC:CountryPrimaryLocationName',
    '-Country',
    '-IPTC:CountryPrimaryLocationCode',
    '-CountryCode',
    '-IPTC:SpecialInstructions',
    '-SpecialInstructions',
    '-XMP:Instructions',
    '-XMP-photoshop:Instructions',
    '-Instructions',
    '-XMP-getty:Personality',
    '-Personality',
    '-IPTC:Urgency',
    '-Urgency',
    '-XMP-photomech:CreatorIdentity',
    '-XMP:CreatorIdentity',
    '-CreatorIdentity',
  ];

  String _formatExifDateTime(Map<String, dynamic> meta) {
    final raw = _firstMetaValue(meta, [
      'DateTimeOriginal',
      'CreateDate',
      'ModifyDate',
    ]);
    if (raw.isEmpty) return '';
    try {
      final parts = raw.split(' ');
      if (parts.isEmpty) return raw;
      final datePart = parts[0].replaceAll(':', '-');
      if (parts.length < 2) return datePart;
      return '$datePart ${parts[1]}';
    } catch (_) {
      return raw;
    }
  }

  Future<Map<String, dynamic>?> _readIptcRawFromFile(String imagePath) async {
    final proc = await ExiftoolHelper.run([
      '-a',
      '-j',
      ..._iptcExiftoolTags,
      imagePath,
    ]);
    if (!proc.isSuccess) return null;
    final List data = jsonDecode(proc.stdoutText);
    if (data.isEmpty) return null;
    return data.first as Map<String, dynamic>;
  }

  void _mergeIptcValues(
    Map<String, String> into,
    Map<String, String> from, {
    bool onlyIfEmpty = false,
    Set<String>? foundInFilesKeys,
  }) {
    for (final e in from.entries) {
      final v = e.value.trim();
      if (v.isEmpty) continue;
      final wasEmpty = into[e.key]?.trim().isEmpty ?? true;
      if (IptcTemplateApplyService.isInAppGeneratedFieldKey(e.key)) {
        if (foundInFilesKeys != null && wasEmpty) {
          foundInFilesKeys.add(e.key);
        }
        continue;
      }
      if (!onlyIfEmpty || wasEmpty) {
        into[e.key] = v;
        if (foundInFilesKeys != null && wasEmpty) {
          foundInFilesKeys.add(e.key);
        }
      }
    }
  }

  List<String> _supplementalCategories(Map<String, dynamic> meta) {
    final values = <String>[];
    void collect(dynamic v) {
      if (v == null) return;
      if (v is List) {
        values.addAll(v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
      } else {
        final s = v.toString().trim();
        if (s.contains(',')) {
          values.addAll(
            s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
          );
        } else if (s.isNotEmpty) {
          values.add(s);
        }
      }
    }

    collect(meta['IPTC:SupplementalCategories']);
    collect(meta['SupplementalCategories']);
    collect(meta['XMP-photoshop:SupplementalCategories']);

    final seen = <String>{};
    return values.where((e) => seen.add(e)).toList(growable: false);
  }

  Map<String, String> _iptcDisplayFromRaw(Map<String, dynamic> meta) {
    final supplemental = _supplementalCategories(meta);
    return {
      'Creator': _firstMetaValue(meta, ['IPTC:By-line', 'By-line', 'Creator']),
      'MEID': _firstMetaValue(meta, [
        'IPTC:OriginalTransmissionReference',
        'OriginalTransmissionReference',
        'TransmissionReference',
        'MEID',
        'JobID',
      ]),
      'Description Writers': _firstMetaValue(meta, ['CaptionWriter']),
      'Job Title': _firstMetaValue(meta, [
        'IPTC:By-lineTitle',
        'By-lineTitle',
        'AuthorsPosition',
        'Creator\'s Job Title',
      ]),
      'Copyright': _firstMetaValue(meta, [
        'IPTC:CopyrightNotice',
        'CopyrightNotice',
        'Copyright',
      ]),
      'Credit': _firstMetaValue(meta, ['IPTC:Credit', 'Credit']),
      'Source': _firstMetaValue(meta, ['IPTC:Source', 'Source']),
      'Headline': _firstMetaValue(meta, ['IPTC:Headline', 'Headline']),
      'Keywords': _keywordsFromMeta(meta),
      'Personality': _firstMetaValue(meta, [
        'XMP-getty:Personality',
        'Personality',
        'XMP:Personality',
      ]),
      'Caption': _firstMetaValue(meta, [
        'IPTC:Description',
        'Description',
        'Caption-Abstract',
        'IPTC:Caption-Abstract',
      ]),
      'Object Name': _firstMetaValue(meta, [
        'IPTC:ObjectName',
        'ObjectName',
        'XMP:Title',
      ]),
      'Category': _firstMetaValue(meta, ['IPTC:Category', 'Category']),
      'Supp Cat 1': supplemental.isNotEmpty ? supplemental[0] : '',
      'Supp Cat 2': supplemental.length > 1 ? supplemental[1] : '',
      'Supp Cat 3': supplemental.length > 2 ? supplemental[2] : '',
      'Special Instructions': _firstMetaValue(meta, [
        'IPTC:SpecialInstructions',
        'SpecialInstructions',
        'XMP-photoshop:Instructions',
        'XMP:Instructions',
        'Instructions',
      ]),
      'Stadium': _firstMetaValue(meta, [
        'IPTC:SubLocation',
        'IPTC:Sub-location',
        'SubLocation',
        'Sub-location',
        'Location',
        'XMP:Location',
        'XMP-iptcCore:Location',
        'LocationShownSublocation',
        'LocationCreatedSublocation',
      ]),
      'City': _firstMetaValue(meta, ['IPTC:City', 'City']),
      'Province/State': _firstMetaValue(meta, [
        'IPTC:ProvinceState',
        'IPTC:Province-State',
        'ProvinceState',
        'Province-State',
        'State',
        'XMP:State',
        'XMP-photoshop:State',
      ]),
      'Country': _firstMetaValue(meta, [
        'IPTC:CountryPrimaryLocationName',
        'CountryPrimaryLocationName',
        'Country',
      ]),
      'Country Code': _firstMetaValue(meta, [
        'IPTC:CountryPrimaryLocationCode',
        'CountryPrimaryLocationCode',
        'CountryCode',
      ]),
      "Creator's Identity": _firstMetaValue(meta, [
        'XMP-photomech:CreatorIdentity',
        'XMP:CreatorIdentity',
        'CreatorIdentity',
      ]),
      'Time and Date': _formatExifDateTime(meta),
      'Urgency': IptcTemplateApplyService.normalizeUrgencyValue(
        _firstMetaValue(meta, ['IPTC:Urgency', 'Urgency']),
      ),
    };
  }

  Future<Map<String, String>> _collectIptcFromFolderSample(
    List<String> imageFiles,
  ) async {
    final merged = <String, String>{};
    for (final path in imageFiles.take(8)) {
      final raw = await _readIptcRawFromFile(path);
      if (raw == null) continue;
      _mergeIptcValues(
        merged,
        _iptcDisplayFromRaw(raw),
        onlyIfEmpty: true,
      );
    }
    return merged;
  }

  Future<List<String>> _imageFilesInDirectory(String folderPath) async {
    final directory = Directory(folderPath);
    final entities = await directory.list().toList();
    return entities
        .whereType<File>()
        .map((entity) => entity.path)
        .where((path) {
          final lower = path.toLowerCase();
          return lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.tiff') ||
              lower.endsWith('.bmp');
        })
        .toList();
  }

  Future<void> _loadIptcFromFolderImages(List<String> imageFiles) async {
    if (imageFiles.isEmpty || !mounted) return;
    setState(() => _loadingIptcFromFiles = true);
    try {
      final folderIptc = await _collectIptcFromFolderSample(imageFiles);
      if (!mounted) return;

      if (folderIptc.isEmpty) {
        setState(() {
          _loadingIptcFromFiles = false;
          _iptcTemplateLoadedBeforeFolder = false;
        });
        return;
      }

      var overrideWithFolder = false;
      // Whether the user was explicitly asked (so "Keep" means no folder merge).
      var userChoseToKeep = false;
      if (_iptcTemplateLoadedBeforeFolder && _iptcTemplateValues.isNotEmpty) {
        setState(() => _loadingIptcFromFiles = false);
        final useFolderIptc = await showAppConfirmDialog(
          context: context,
          title: 'Replace IPTC template?',
          message:
              'You loaded a template before choosing a folder. Replace it with IPTC read from the folder images?',
          cancelLabel: 'Keep template',
          confirmLabel: 'Use folder IPTC',
        );
        if (!mounted) return;
        overrideWithFolder = useFolderIptc == true;
        userChoseToKeep = !overrideWithFolder;
        setState(() => _loadingIptcFromFiles = true);
      }

      final foundInFiles = <String>{};
      final Map<String, String> merged;
      if (overrideWithFolder) {
        // Replace entirely with folder IPTC.
        merged = IptcTemplateApplyService.panelValuesFromImportedTemplate(
          folderIptc,
          _iptcWireStyle,
        );
        for (final key in merged.keys) {
          if (!IptcTemplateApplyService.isInAppGeneratedFieldKey(key)) {
            foundInFiles.add(key);
          }
        }
      } else if (userChoseToKeep) {
        // User explicitly kept the template — don't let folder IPTC fill blank fields.
        merged = Map<String, String>.from(_iptcTemplateValues);
      } else {
        // No prior template — fill empty fields from folder as usual.
        merged = Map<String, String>.from(_iptcTemplateValues);
        _mergeIptcValues(
          merged,
          folderIptc,
          onlyIfEmpty: true,
          foundInFilesKeys: foundInFiles,
        );
      }

      if (!mounted) return;
      setState(() {
        _iptcTemplateValues = merged;
        _iptcKeysFoundInFiles
          ..clear()
          ..addAll(foundInFiles);
        _loadingIptcFromFiles = false;
        _iptcTemplateLoadedBeforeFolder = false;
        if (overrideWithFolder) {
          _iptcTemplateRevision++;
        }
      });
    } catch (e) {
      print('Error loading IPTC from folder images: $e');
      if (mounted) {
        setState(() {
          _loadingIptcFromFiles = false;
          _iptcTemplateLoadedBeforeFolder = false;
        });
      }
    }
  }

  Future<void> _initializePreferences() async {
    if (!_sportChosen) return;

    // Load favorite teams for the current sport
    final sport = widget.sport!.toLowerCase();
    print('DEBUG _initializePreferences: Loading favorites for sport=$sport');
    _favoriteTeams = await _preferencesService.getFavoriteTeams(sport: sport);
    print(
        'DEBUG _initializePreferences: Loaded favorite teams: $_favoriteTeams');

    // Extract home and away favorites from the set
    // We'll use a simple convention: favorites are stored as "HOME:teamname" and "AWAY:teamname"
    for (var team in _favoriteTeams) {
      if (team.startsWith('HOME:')) {
        _favoriteHomeTeam = team.substring(5);
        print(
            'DEBUG _initializePreferences: Found home favorite: $_favoriteHomeTeam');
      } else if (team.startsWith('AWAY:')) {
        _favoriteAwayTeam = team.substring(5);
        print(
            'DEBUG _initializePreferences: Found away favorite: $_favoriteAwayTeam');
      }
    }

    // Automatically select favorite teams if they exist
    if (_favoriteHomeTeam != null) {
      selectedHomeTeam = _favoriteHomeTeam;
      print(
          'DEBUG _initializePreferences: Set selectedHomeTeam=$selectedHomeTeam');
    }
    if (_favoriteAwayTeam != null) {
      selectedAwayTeam = _favoriteAwayTeam;
      print(
          'DEBUG _initializePreferences: Set selectedAwayTeam=$selectedAwayTeam');
    }

    _burstDetectionEnabled =
        await _preferencesService.getBurstDetectionEnabled();

    if (mounted) {
      setState(() {});
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _retryLoadTeams() async {
    setState(() => isLoadingTeams = true);
    await _loadTeams();
  }

  Future<void> _loadTeams() async {
    if (!_sportChosen) {
      if (mounted) {
        setState(() => isLoadingTeams = false);
      }
      return;
    }
    if (mounted) {
      setState(() => isLoadingTeams = true);
    }
    try {
      final teams = await _apiManager.fetchTeams();
      if (!mounted) return;
      setState(() {
        _isOffline = false;
        // Remove duplicates by converting to Set, then back to List and sort
        availableTeams = teams.map((team) => team.name).toSet().toList()
          ..sort();
        print('DEBUG _loadTeams: Loaded ${availableTeams.length} teams');
        // Clear selection if no longer in list (e.g. after switching API)
        if (selectedHomeTeam != null &&
            !availableTeams.contains(selectedHomeTeam)) {
          selectedHomeTeam = null;
        }
        if (selectedAwayTeam != null &&
            !availableTeams.contains(selectedAwayTeam)) {
          selectedAwayTeam = null;
        }
        // Restore favorite teams if they exist and are in the team list
        print('DEBUG _loadTeams: Checking home favorite: $_favoriteHomeTeam');
        if (_favoriteHomeTeam != null &&
            availableTeams.contains(_favoriteHomeTeam)) {
          selectedHomeTeam = _favoriteHomeTeam;
          print('DEBUG _loadTeams: Set selectedHomeTeam=$selectedHomeTeam');
        } else {
          print(
              'DEBUG _loadTeams: Home favorite not found in team list or null');
        }
        print('DEBUG _loadTeams: Checking away favorite: $_favoriteAwayTeam');
        if (_favoriteAwayTeam != null &&
            availableTeams.contains(_favoriteAwayTeam)) {
          selectedAwayTeam = _favoriteAwayTeam;
          print('DEBUG _loadTeams: Set selectedAwayTeam=$selectedAwayTeam');
        } else {
          print(
              'DEBUG _loadTeams: Away favorite not found in team list or null');
        }
        isLoadingTeams = false;
      });
      if (_showStartupCoachInfo && selectedHomeTeam != null) {
        _refreshCoachLabelForTeam(isHome: true);
      }
      if (_showStartupCoachInfo && selectedAwayTeam != null) {
        _refreshCoachLabelForTeam(isHome: false);
      }
    } catch (e) {
      print('Error loading teams: $e');
      if (!mounted) return;
      // Fallback teams based on sport
      setState(() {
        _isOffline = true;
        final sport = widget.sport?.toLowerCase() ?? 'baseball';

        if (sport == 'hockey') {
          availableTeams = [
            'Anaheim Ducks',
            'Arizona Coyotes',
            'Boston Bruins',
            'Buffalo Sabres',
            'Calgary Flames',
            'Carolina Hurricanes',
            'Chicago Blackhawks',
            'Colorado Avalanche',
            'Columbus Blue Jackets',
            'Dallas Stars',
            'Detroit Red Wings',
            'Edmonton Oilers',
            'Florida Panthers',
            'Los Angeles Kings',
            'Minnesota Wild',
            'Montreal Canadiens',
            'Nashville Predators',
            'New Jersey Devils',
            'New York Islanders',
            'New York Rangers',
            'Ottawa Senators',
            'Philadelphia Flyers',
            'Pittsburgh Penguins',
            'San Jose Sharks',
            'Seattle Kraken',
            'St. Louis Blues',
            'Tampa Bay Lightning',
            'Toronto Maple Leafs',
            'Vancouver Canucks',
            'Vegas Golden Knights',
            'Washington Capitals',
            'Winnipeg Jets'
          ];
        } else if (sport == 'basketball') {
          availableTeams = [
            'Atlanta Hawks',
            'Boston Celtics',
            'Brooklyn Nets',
            'Charlotte Hornets',
            'Chicago Bulls',
            'Cleveland Cavaliers',
            'Dallas Mavericks',
            'Denver Nuggets',
            'Detroit Pistons',
            'Golden State Warriors',
            'Houston Rockets',
            'Indiana Pacers',
            'Los Angeles Clippers',
            'Los Angeles Lakers',
            'Memphis Grizzlies',
            'Miami Heat',
            'Milwaukee Bucks',
            'Minnesota Timberwolves',
            'New Orleans Pelicans',
            'New York Knicks',
            'Oklahoma City Thunder',
            'Orlando Magic',
            'Philadelphia 76ers',
            'Phoenix Suns',
            'Portland Trail Blazers',
            'Sacramento Kings',
            'San Antonio Spurs',
            'Toronto Raptors',
            'Utah Jazz',
            'Washington Wizards'
          ];
        } else if (sport == 'soccer') {
          availableTeams = [
            'Atlanta United FC',
            'Austin FC',
            'CF Montréal',
            'Charlotte FC',
            'Chicago Fire FC',
            'Colorado Rapids',
            'Columbus Crew',
            'D.C. United',
            'FC Cincinnati',
            'FC Dallas',
            'Houston Dynamo FC',
            'Inter Miami CF',
            'LA Galaxy',
            'LAFC',
            'Minnesota United FC',
            'Nashville SC',
            'New England Revolution',
            'New York City FC',
            'Orlando City SC',
            'Philadelphia Union',
            'Portland Timbers',
            'Real Salt Lake',
            'Red Bull New York',
            'San Diego FC',
            'San Jose Earthquakes',
            'Seattle Sounders FC',
            'Sporting Kansas City',
            'St. Louis CITY SC',
            'Toronto FC',
            'Vancouver Whitecaps',
          ];
        } else {
          // Default to MLB teams
          availableTeams = [
            'Arizona Diamondbacks',
            'Atlanta Braves',
            'Baltimore Orioles',
            'Boston Red Sox',
            'Chicago Cubs',
            'Chicago White Sox',
            'Cincinnati Reds',
            'Cleveland Guardians',
            'Colorado Rockies',
            'Detroit Tigers',
            'Houston Astros',
            'Kansas City Royals',
            'Los Angeles Angels',
            'Los Angeles Dodgers',
            'Miami Marlins',
            'Milwaukee Brewers',
            'Minnesota Twins',
            'New York Mets',
            'New York Yankees',
            'Oakland Athletics',
            'Philadelphia Phillies',
            'Pittsburgh Pirates',
            'San Diego Padres',
            'San Francisco Giants',
            'Seattle Mariners',
            'St. Louis Cardinals',
            'Tampa Bay Rays',
            'Texas Rangers',
            'Toronto Blue Jays',
            'Washington Nationals'
          ];
        }
        print(
            'DEBUG _loadTeams (fallback): Loaded ${availableTeams.length} fallback teams for $sport');
        if (selectedHomeTeam != null &&
            !availableTeams.contains(selectedHomeTeam)) {
          selectedHomeTeam = null;
        }
        if (selectedAwayTeam != null &&
            !availableTeams.contains(selectedAwayTeam)) {
          selectedAwayTeam = null;
        }
        // Restore favorite teams if they exist and are in the team list
        print(
            'DEBUG _loadTeams (fallback): Checking home favorite: $_favoriteHomeTeam');
        if (_favoriteHomeTeam != null &&
            availableTeams.contains(_favoriteHomeTeam)) {
          selectedHomeTeam = _favoriteHomeTeam;
          print(
              'DEBUG _loadTeams (fallback): Set selectedHomeTeam=$selectedHomeTeam');
        } else {
          print(
              'DEBUG _loadTeams (fallback): Home favorite not found in team list or null');
        }
        print(
            'DEBUG _loadTeams (fallback): Checking away favorite: $_favoriteAwayTeam');
        if (_favoriteAwayTeam != null &&
            availableTeams.contains(_favoriteAwayTeam)) {
          selectedAwayTeam = _favoriteAwayTeam;
          print(
              'DEBUG _loadTeams (fallback): Set selectedAwayTeam=$selectedAwayTeam');
        } else {
          print(
              'DEBUG _loadTeams (fallback): Away favorite not found in team list or null');
        }
        isLoadingTeams = false;
      });
    }
  }

  Future<void> _pickFolder() async {
    setState(() {
      isLoadingFolder = true;
    });

    try {
      // Get the last used directory
      String? lastDirectory;
      try {
        final prefs = await SharedPreferences.getInstance();
        lastDirectory = prefs.getString('last_images_folder');
      } catch (prefsError) {
        print('SharedPreferences error: $prefsError');
        lastDirectory = null; // Continue without saved directory
      }

      String? result = await NativeFilePicker.pickDirectory(
        initialDirectory: lastDirectory,
      );

      if (result != null) {
        // Check if folder contains images
        final imageFiles = await _imageFilesInDirectory(result);

        // Save the directory for next time
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_images_folder', result);
        } catch (prefsError) {
          print('SharedPreferences save error: $prefsError');
          // Continue without saving preference
        }

        setState(() {
          selectedFolderPath = result;
          _selectedImageFiles = imageFiles;
          hasImagesInFolder = imageFiles.isNotEmpty;
          isLoadingFolder = false;
        });

        // If images found, try to read date from first 5 images
        if (imageFiles.isNotEmpty) {
          setState(() {
            isExtractingDate = true;
          });
          await _extractDateFromImages(imageFiles);
          setState(() {
            isExtractingDate = false;
          });
          await _loadIptcFromFolderImages(imageFiles);
        } else {
          setState(() {
            _iptcTemplateValues = {};
            _iptcKeysFoundInFiles.clear();
            _selectedImageFiles = [];
            _iptcTemplateLoadedBeforeFolder = false;
          });
        }

      } else {
        setState(() {
          isLoadingFolder = false;
        });
      }
    } catch (e) {
      print('Error picking folder: $e');
      setState(() {
        isLoadingFolder = false;
      });
    }
  }

  Future<void> _extractDateFromImages(List<String> imageFiles) async {
    try {
      // Take first 5 images
      final imagesToCheck = imageFiles.take(5).toList();
      List<DateTime?> dates = [];

      for (String imagePath in imagesToCheck) {
        try {
          // Extract metadata via exiftool
          final proc = await ExiftoolHelper.run([
            '-j', // JSON output
            '-DateTimeOriginal',
            '-CreateDate',
            '-ModifyDate',
            imagePath,
          ]);

          if (proc.isSuccess) {
            final List data = jsonDecode(proc.stdoutText);
            if (data.isNotEmpty) {
              final metadata = data.first as Map<String, dynamic>;

              // Try to get date from various EXIF fields
              String? dateString = metadata['DateTimeOriginal']?.toString() ??
                  metadata['CreateDate']?.toString() ??
                  metadata['ModifyDate']?.toString();

              if (dateString != null && dateString.isNotEmpty) {
                try {
                  // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
                  final parts = dateString.split(' ');
                  if (parts.isNotEmpty) {
                    final datePart = parts[0];
                    final dateComponents = datePart.split(':');
                    if (dateComponents.length >= 3) {
                      final year = int.parse(dateComponents[0]);
                      final month = int.parse(dateComponents[1]);
                      final day = int.parse(dateComponents[2]);
                      dates.add(DateTime(year, month, day));
                    }
                  }
                } catch (e) {
                  print('Error parsing date from $imagePath: $e');
                }
              }
            }
          }
        } catch (e) {
          print('Error reading metadata from $imagePath: $e');
        }
      }

      // If we found dates, use the most common date or the first one
      if (dates.isNotEmpty) {
        // Find the most common date
        Map<DateTime, int> dateCounts = {};
        for (DateTime? date in dates) {
          if (date != null) {
            // Normalize to just the date part
            final normalizedDate = DateTime(date.year, date.month, date.day);
            dateCounts[normalizedDate] = (dateCounts[normalizedDate] ?? 0) + 1;
          }
        }

        if (dateCounts.isNotEmpty) {
          // Find the date with the highest count
          final mostCommonDate = dateCounts.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          setState(() {
            selectedGameDate = mostCommonDate;
          });
          print(
              'Extracted game date from images: ${mostCommonDate.toIso8601String().split('T')[0]}');
        } else {
          print('No valid dates found in images');
        }
      }
    } catch (e) {
      print('Error extracting dates from images: $e');
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        selectedGameDate = picked;
        _goTimeWarningText = null;
      });
    }
  }

  Future<void> _toggleFavoriteTeam({required bool isHome}) async {
    setState(() {
      final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
      if (selectedTeam == null) return;
      if (isHome) {
        if (_favoriteHomeTeam == selectedTeam) {
          _favoriteHomeTeam = null;
          _favoriteTeams.remove('HOME:$selectedTeam');
        } else {
          if (_favoriteHomeTeam != null) {
            _favoriteTeams.remove('HOME:$_favoriteHomeTeam');
          }
          _favoriteHomeTeam = selectedTeam;
          _favoriteTeams.add('HOME:$selectedTeam');
        }
      } else {
        if (_favoriteAwayTeam == selectedTeam) {
          _favoriteAwayTeam = null;
          _favoriteTeams.remove('AWAY:$selectedTeam');
        } else {
          if (_favoriteAwayTeam != null) {
            _favoriteTeams.remove('AWAY:$_favoriteAwayTeam');
          }
          _favoriteAwayTeam = selectedTeam;
          _favoriteTeams.add('AWAY:$selectedTeam');
        }
      }
    });

    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    await _preferencesService.saveFavoriteTeams(_favoriteTeams, sport: sport);
  }

  Future<void> _refreshCoachLabelForTeam({required bool isHome}) async {
    final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;
    if (teamName == null || teamName.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = null;
          _homeCoachLoading = false;
          _homeCoachName = '';
        } else {
          _awayCoachRole = null;
          _awayCoachLoading = false;
          _awayCoachName = '';
        }
      });
      return;
    }

    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    final String headTitle =
        (sport == 'baseball' || sport == 'soccer') ? 'Manager' : 'Head Coach';

    if (mounted) {
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = true;
          _homeCoachName = '';
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = true;
          _awayCoachName = '';
        }
      });
    }

    try {
      final staff = await _apiManager.fetchTeamStaff(teamName);
      final headCoach = (staff['headCoach'] ?? '').trim();
      final name = headCoach.isNotEmpty ? headCoach : 'data missing';
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = false;
          _homeCoachName = name;
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = false;
          _awayCoachName = name;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = false;
          _homeCoachName = 'data missing';
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = false;
          _awayCoachName = 'data missing';
        }
      });
    }
  }

  /// Same typography as Keyboard Fire roster rows (jersey-style role + name).
  Widget _buildStartupCoachRichText({
    required String? role,
    required bool loading,
    required String nameOrStatus,
  }) {
    if (role == null) return const SizedBox.shrink();
    final titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade800,
    );
    final suffix = loading ? 'loading…' : nameOrStatus;
    final suffixStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      fontStyle: loading || nameOrStatus == 'data missing'
          ? FontStyle.italic
          : FontStyle.normal,
      color: loading
          ? Colors.grey.shade600
          : (nameOrStatus == 'data missing'
              ? Colors.grey.shade500
              : Colors.black87),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(role, style: titleStyle),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            suffix,
            style: suffixStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStyledTeamDropdown({
    required bool isHome,
    required String hintText,
  }) {
    final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
    final otherTeam = isHome ? selectedAwayTeam : selectedHomeTeam;
    final favoriteTeam = isHome ? _favoriteHomeTeam : _favoriteAwayTeam;
    final effectiveHint = isLoadingTeams && availableTeams.isEmpty
        ? 'Loading teams…'
        : hintText;
    return _StartupTeamAutocomplete(
      hintText: effectiveHint,
      teams: availableTeams,
      selectedTeam: selectedTeam,
      otherTeam: otherTeam,
      favoriteTeam: favoriteTeam,
      onTeamSelected: (team) {
        setState(() {
          if (isHome) {
            selectedHomeTeam = team;
          } else {
            selectedAwayTeam = team;
          }
          _goTimeWarningText = null;
        });
        if (_showStartupCoachInfo) {
          _refreshCoachLabelForTeam(isHome: isHome);
        }
      },
      onToggleFavorite: (team) async {
        setState(() {
          if (isHome) {
            selectedHomeTeam = team;
          } else {
            selectedAwayTeam = team;
          }
        });
        if (_showStartupCoachInfo) {
          _refreshCoachLabelForTeam(isHome: isHome);
        }
        await _toggleFavoriteTeam(isHome: isHome);
      },
    );
  }

  Widget _buildTeamDropdownWithFavoriteIndicator({
    required bool isHome,
    required String hintText,
  }) {
    final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
    final isFavoriteSelected = selectedTeam != null &&
        ((isHome && _favoriteHomeTeam == selectedTeam) ||
            (!isHome && _favoriteAwayTeam == selectedTeam));

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        _buildStyledTeamDropdown(isHome: isHome, hintText: hintText),
        if (isFavoriteSelected)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(right: 34),
              child: Icon(
                Icons.star,
                size: 14,
                color: Colors.amber.shade700,
              ),
            ),
          ),
      ],
    );
  }

  /// Match button width to full Away + @ + Home row width.
  Widget _sectionCard({
    required String label,
    required List<Widget> children,
    Widget? trailing,
    EdgeInsetsGeometry? padding,
    double labelSpacing = 8,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F8F8), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontVariations: [FontVariation('wght', 700)],
                  color: Color(0xFF333333),
                  letterSpacing: -0.5,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          SizedBox(height: labelSpacing),
          ...children,
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    double iconSize = 11,
    Color? iconColor,
    bool expand = false,
  }) {
    return Container(
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon,
              size: iconSize, color: iconColor ?? const Color(0xFF4A7A96)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontVariations: [FontVariation('wght', 500)],
                color: Color(0xFF2A4858),
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Grey out and block interaction until a prior startup step is complete.
  Widget _lockedUntil(bool unlocked, Widget child) {
    if (unlocked) return child;
    return Opacity(
      opacity: 0.38,
      child: AbsorbPointer(child: child),
    );
  }

  Widget _lockedUntilSport(Widget child) => _lockedUntil(_sportChosen, child);

  Widget _lockedUntilFolder(Widget child) => _lockedUntil(_folderChosen, child);

  Widget _lockedUntilTeams(Widget child) => _lockedUntil(_teamsChosen, child);

  Widget _buildGameDateRow() {
    if (!_folderChosen) return const SizedBox.shrink();
    if (isExtractingDate) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Reading date from images…',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (selectedGameDate != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          ElevatedGreyButton(
            label: 'Select game date',
            fontSize: 10,
            icon: Icons.calendar_today,
            onPressed: _selectDate,
          ),
          const SizedBox(width: 8),
          Text(
            hasImagesInFolder
                ? 'Could not read date from images'
                : 'No images in folder — pick a date',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  bool get _canProceed {
    if (hasImagesInFolder) {
      return selectedFolderPath != null &&
          selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          selectedHomeTeam != selectedAwayTeam;
    } else {
      return selectedFolderPath != null &&
          selectedGameDate != null &&
          selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          selectedHomeTeam != selectedAwayTeam;
    }
  }

  Widget _buildDialogHeader() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFF6F6F6), Color(0xFFFEFEFE)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
        ),
      ),
      child: const Row(
        children: [
          Text(
            'FLO FILE',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontVariations: [FontVariation('wght', 900)],
              color: Color(0xFF2A4858),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelBody() {
    if (widget.inline) {
      return _buildInlineSplitLayout();
    }

    final sections = _buildConfigurationSections();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDialogHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: sections,
          ),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 3,
          offset: const Offset(0, 1.5),
        ),
      ],
    );
  }

  Widget _buildSportSection() {
    return _sectionCard(
      label: 'SPORT',
      children: [
        SportSelectionDialog(
          sectionCard: true,
          selectedSport: widget.sport,
          onSportSelected: _onSportSelected,
        ),
      ],
    );
  }

  Widget _buildLeftFormSections() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSportSection(),
        const SizedBox(height: 10),
        _lockedUntilSport(
          _sectionCard(
            label: 'IMAGES FOLDER',
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: ElevatedGreyButton(
                      label: isLoadingFolder
                          ? 'Loading…'
                          : 'Pick images folder',
                      fontSize: 10,
                      icon: Icons.folder_open,
                      isTealGradient: true,
                      fullWidth: true,
                      onPressed: (!_sportChosen || isLoadingFolder)
                          ? null
                          : _pickFolder,
                    ),
                  ),
                  if (selectedFolderPath != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _pill(
                        icon: Icons.folder_outlined,
                        text: selectedFolderPath!,
                        expand: true,
                      ),
                    ),
                    if (selectedGameDate != null) ...[
                      const SizedBox(width: 8),
                      _pill(
                        icon: Icons.circle,
                        iconSize: 6,
                        iconColor: Colors.green,
                        text: _formatDate(selectedGameDate!),
                      ),
                    ],
                  ],
                ],
              ),
              _buildGameDateRow(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _lockedUntilFolder(_buildTeamsSection()),
        const SizedBox(height: 10),
        _lockedUntilTeams(
          _sectionCard(
            label: 'CAPTION LAYOUT',
            children: [
              StartupCaptionLayoutPreview(
                sport: widget.sport,
                compact: false,
                onWireStyleChanged: _onCaptionWireStyleChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _lockedUntilTeams(_buildOptionalSection()),
        const SizedBox(height: 12),
        _lockedUntilTeams(_buildGoTimeButton()),
      ],
    );
  }

  Widget _buildIptcInfoHeader() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFF6F6F6), Color(0xFFFEFEFE)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
        ),
      ),
      child: const Row(
        children: [
          Text(
            'IPTC TEMPLATE',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontVariations: [FontVariation('wght', 700)],
              color: Color(0xFF333333),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightIptcPanel() {
    return _lockedUntilTeams(
      Container(
        decoration: _panelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIptcInfoHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: StartupIptcTemplatePanel(
                  selectedWire: _iptcWireStyle,
                  wireLabels: _wireLabels,
                  values: _iptcTemplateValues,
                  foundInFilesKeys: _iptcKeysFoundInFiles,
                  isLoading: _loadingIptcFromFiles,
                  onValueChanged: _onIptcTemplateValueChanged,
                  onWireSelected: _onCaptionWireStyleChanged,
                  iptcApplyMode: _iptcApplyMode,
                  onIptcApplyModeChanged: (mode) {
                    setState(() => _iptcApplyMode = mode);
                  },
                  onLoadTemplate: _loadExternalIptcTemplate,
                  onClearTemplate: _clearIptcTemplateValues,
                  onLoadOriginalValues: _loadOriginalIptcValuesFromFiles,
                  isLoadTemplateLoading: _loadingExternalTemplate,
                  isLoadTemplateDisabled: _loadingIptcFromFiles,
                  isLoadOriginalValuesDisabled:
                      _selectedImageFiles.isEmpty && !hasImagesInFolder,
                  templateRevision: _iptcTemplateRevision,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineSplitLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 9,
          child: Container(
            decoration: _panelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDialogHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: _buildLeftFormSections(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 11,
          child: _buildRightIptcPanel(),
        ),
      ],
    );
  }

  Widget _buildConfigurationSections() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSportSection(),
        const SizedBox(height: 10),
        _lockedUntilSport(
          _sectionCard(
            label: 'IMAGES FOLDER',
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: ElevatedGreyButton(
                      label: isLoadingFolder
                          ? 'Loading…'
                          : 'Pick images folder',
                      fontSize: 10,
                      icon: Icons.folder_open,
                      isTealGradient: true,
                      fullWidth: true,
                      onPressed: (!_sportChosen || isLoadingFolder)
                          ? null
                          : _pickFolder,
                    ),
                  ),
                  if (selectedFolderPath != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _pill(
                        icon: Icons.folder_outlined,
                        text: selectedFolderPath!,
                        expand: true,
                      ),
                    ),
                    if (selectedGameDate != null) ...[
                      const SizedBox(width: 8),
                      _pill(
                        icon: Icons.circle,
                        iconSize: 6,
                        iconColor: Colors.green,
                        text: _formatDate(selectedGameDate!),
                      ),
                    ],
                  ],
                ],
              ),
              _buildGameDateRow(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _lockedUntilFolder(_buildTeamsSection()),
        const SizedBox(height: 10),
        _lockedUntilTeams(
          _sectionCard(
            label: 'CAPTION LAYOUT',
            children: [
              StartupCaptionLayoutPreview(
                sport: widget.sport,
                compact: false,
                onWireStyleChanged: _onCaptionWireStyleChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _lockedUntilTeams(_buildOptionalSection()),
        const SizedBox(height: 12),
        _lockedUntilTeams(_buildGoTimeButton()),
      ],
    );
  }

  Widget _buildTeamsSection() {
    return _sectionCard(
      label: 'TEAMS',
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      labelSpacing: 5,
      trailing: _isOffline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Text(
                    'Offline',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontVariations: [FontVariation('wght', 500)],
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedGreyButton(
                  label: isLoadingTeams ? 'Loading…' : 'Retry',
                  fontSize: 11,
                  onPressed: isLoadingTeams ? null : _retryLoadTeams,
                ),
              ],
            )
          : null,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _buildTeamDropdownWithFavoriteIndicator(
                isHome: false,
                hintText: 'Away team',
              ),
            ),
            SizedBox(
              width: 22,
              child: Center(
                child: Text(
                  '@',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildTeamDropdownWithFavoriteIndicator(
                isHome: true,
                hintText: 'Home team',
              ),
            ),
          ],
        ),
        if (isLoadingTeams && availableTeams.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Loading team list…',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
        if (selectedHomeTeam != null &&
            selectedAwayTeam != null &&
            selectedHomeTeam == selectedAwayTeam) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 14),
                SizedBox(width: 4),
                Text(
                  'Home and away teams must be different',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontVariations: [FontVariation('wght', 500)],
                    color: Colors.red,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionalSection() {
    return _sectionCard(
      label: 'OPTIONAL',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppCompactCheckbox(
              value: _burstDetectionEnabled,
              onChanged: (v) async {
                await _preferencesService.saveBurstDetectionEnabled(v);
                setState(() => _burstDetectionEnabled = v);
              },
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Burst sequence detection',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoTimeButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomButton(
          onTap: () async {
            if (!_folderChosen) {
              setState(
                  () => _goTimeWarningText = 'Pick an images folder first.');
              return;
            }
            if (_canProceed) {
              setState(() => _goTimeWarningText = null);
              final preset = await _persistIptcTemplateValues();
              if (!mounted) return;
              widget.onConfigurationComplete(
                selectedFolderPath!,
                selectedHomeTeam,
                selectedAwayTeam,
                preset,
              );
              return;
            }
            final missingTeams =
                selectedHomeTeam == null || selectedAwayTeam == null;
            final sameTeam = selectedHomeTeam != null &&
                selectedAwayTeam != null &&
                selectedHomeTeam == selectedAwayTeam;
            final needsDate =
                !hasImagesInFolder && selectedGameDate == null;
            String message = 'Complete setup before continuing.';
            if (needsDate) {
              message = 'Select a game date.';
            } else if (missingTeams) {
              message = 'Select both Away and Home teams.';
            } else if (sameTeam) {
              message = 'Home and away teams must be different.';
            }
            setState(() => _goTimeWarningText = message);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
            decoration: BoxDecoration(
              gradient: _canProceed
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF4A7A96), Color(0xFF2A4858)],
                    )
                  : null,
              color: _canProceed ? null : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _canProceed
                    ? const Color(0xFF2A4858)
                    : const Color(0xFFD0D0D0),
                width: 0.7,
              ),
              boxShadow: _canProceed
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 5,
                        offset: const Offset(0, 2.5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 14,
                  color: _canProceed ? Colors.white : Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  'Go Time',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontVariations: const [FontVariation('wght', 600)],
                    color:
                        _canProceed ? Colors.white : Colors.grey.shade500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_goTimeWarningText != null) ...[
          const SizedBox(height: 6),
          Text(
            _goTimeWarningText!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontVariations: const [FontVariation('wght', 500)],
              color: Colors.red.shade400,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const dialogWidth = 720.0;
    const dialogHeight = 600.0;

    final panelDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(widget.inline ? 8 : 12),
      border: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
              alpha: widget.inline ? 0.08 : 0.18),
          blurRadius: widget.inline ? 3 : 24,
          offset: Offset(0, widget.inline ? 1.5 : 8),
        ),
      ],
    );

    if (widget.inline) {
      return _buildPanelBody();
    }

    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 24,
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            clipBehavior: Clip.antiAlias,
            decoration: panelDecoration,
            child: _buildPanelBody(),
          ),
        ),
      ),
    );
  }
}

/// Team field: click, type to filter the list — no separate search bar in the menu.
class _StartupTeamAutocomplete extends StatefulWidget {
  const _StartupTeamAutocomplete({
    required this.hintText,
    required this.teams,
    required this.selectedTeam,
    required this.otherTeam,
    required this.favoriteTeam,
    required this.onTeamSelected,
    required this.onToggleFavorite,
  });

  final String hintText;
  final List<String> teams;
  final String? selectedTeam;
  final String? otherTeam;
  final String? favoriteTeam;
  final ValueChanged<String> onTeamSelected;
  final Future<void> Function(String team) onToggleFavorite;

  @override
  State<_StartupTeamAutocomplete> createState() =>
      _StartupTeamAutocompleteState();
}

class _StartupTeamAutocompleteState extends State<_StartupTeamAutocomplete> {
  final GlobalKey _fieldKey = GlobalKey();
  double? _fieldWidth;

  static const _fieldStyle = TextStyle(
    fontSize: 11,
    color: Color(0xFF2A4858),
    fontWeight: FontWeight.w500,
  );

  InputDecoration _fieldDecoration({required bool focused}) {
    final borderRadius = BorderRadius.circular(focused ? 8 : 5);
    final borderColor =
        focused ? const Color(0xFF4A7A96) : const Color(0xFFD0D0D0);
    final borderWidth = focused ? 1.0 : 0.7;
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      hintText: widget.hintText,
      hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: Icon(
        Icons.arrow_drop_down,
        size: 18,
        color: Colors.grey.shade600,
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
    );
  }

  void _syncFieldWidth() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final w = box.size.width;
    if (w > 0 && w != _fieldWidth) {
      setState(() => _fieldWidth = w);
    }
  }

  Iterable<String> _matchingTeams(String query) {
    final q = query.trim().toLowerCase();
    return widget.teams.where((team) {
      if (q.isEmpty) return true;
      return team.toLowerCase().contains(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFieldWidth());

    return Autocomplete<String>(
      key: ValueKey(widget.teams),
      initialValue: TextEditingValue(text: widget.selectedTeam ?? ''),
      optionsBuilder: (textEditingValue) =>
          _matchingTeams(textEditingValue.text),
      displayStringForOption: (team) => team,
      onSelected: (team) {
        if (widget.otherTeam == team) return;
        widget.onTeamSelected(team);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return KeyedSubtree(
          key: _fieldKey,
          child: ListenableBuilder(
            listenable: focusNode,
            builder: (context, _) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: _fieldStyle,
                decoration: _fieldDecoration(focused: focusNode.hasFocus),
                onTap: () {
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                },
                onSubmitted: (_) => onFieldSubmitted(),
              );
            },
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final width = _fieldWidth;
        if (width == null || options.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 380, maxWidth: width),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final team = options.elementAt(index);
                  final blocked = widget.otherTeam == team;
                  final isSelected = widget.selectedTeam == team;
                  final isFavorite = widget.favoriteTeam == team;
                  return InkWell(
                    onTap: blocked ? null : () => onSelected(team),
                    child: Container(
                      width: width,
                      color: isSelected
                          ? const Color(0xFFEEF3F6)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              team,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: blocked
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade800,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: blocked
                                ? null
                                : () => widget.onToggleFavorite(team),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                size: 16,
                                color: isFavorite
                                    ? Colors.amber
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
