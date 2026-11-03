import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_style_catalog.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
import '../../../widgets/app_styled_dialogs.dart';
import 'iptc_template_editor.dart';

/// Result summary shown on the V2 startup form after closing the dialog.
class CaptionV2IptcSummary {
  const CaptionV2IptcSummary({
    required this.mode,
    required this.templateLabel,
  });

  final IptcApplyMode mode;
  final String templateLabel;

  String get statusLine {
    final wire = templateLabel.trim().isEmpty ? 'template' : templateLabel;
    switch (mode) {
      case IptcApplyMode.none:
        return 'Off';
      case IptcApplyMode.onImport:
        return 'On load · $wire';
      case IptcApplyMode.onSave:
        return 'On save · $wire';
      case IptcApplyMode.onFtp:
        return 'On FTP · $wire';
      case IptcApplyMode.onSaveAndFtp:
        return 'On save & FTP · $wire';
    }
  }
}

/// Opens the classic IPTC template panel in a dialog for Caption V2.
Future<CaptionV2IptcSummary?> showCaptionV2IptcDialog(
  BuildContext context, {
  String? folderPath,
  bool enableWriting = false,
  bool populateFromFolder = false,
  CaptionTemplate? captionTemplate,
}) {
  return showDialog<CaptionV2IptcSummary>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CaptionV2IptcDialog(
      folderPath: folderPath,
      enableWriting: enableWriting,
      populateFromFolder: populateFromFolder,
      captionTemplate: captionTemplate,
    ),
  );
}

class CaptionV2IptcDialog extends StatefulWidget {
  const CaptionV2IptcDialog({
    super.key,
    this.folderPath,
    this.enableWriting = false,
    this.populateFromFolder = false,
    this.captionTemplate,
  });

  final String? folderPath;

  /// Opened from the start-menu Write IPTC switch. Fields stay editable, and
  /// writing is saved only when the user finishes the dialog.
  final bool enableWriting;

  /// When true (folder just chosen), fill the panel from image IPTC and show
  /// what is already populated vs still missing.
  final bool populateFromFolder;

  /// Caption style from New Session — drives which IPTC fields are marked red.
  final CaptionTemplate? captionTemplate;

  @override
  State<CaptionV2IptcDialog> createState() => _CaptionV2IptcDialogState();
}

class _CaptionV2IptcDialogState extends State<CaptionV2IptcDialog> {
  late PreferencesService _prefs;

  IptcApplyMode _mode = IptcApplyMode.none;
  WireStyle _wire = WireStyle.getty;
  String _selectedTemplateId = '';
  List<IptcTemplateCatalogEntry> _visibleTemplates = const [];
  final Map<WireStyle, String> _wireLabels = {};
  Map<String, String> _values = const {'Urgency': '5'};
  final Set<String> _keysFoundInFiles = {};
  Set<String> _clearedFields = {};
  int _revision = 0;
  bool _loading = true;
  bool _loadingFromFiles = false;
  bool _loadingExternal = false;
  CaptionTemplate _captionTemplate = CaptionTemplate.getty();
  String _captionStyleLabel = 'Getty';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _prefs = await PreferencesService.getInstance();
    // Ensure appDefaults cache is warm (public read) before listing templates.
    await AppDefaultsFirestoreService.fetchAndCacheAppDefaults();
    var mode = await _prefs.getIptcApplyMode();
    if (widget.enableWriting) mode = IptcApplyMode.onImport;
    final captionTemplate =
        widget.captionTemplate ?? await _prefs.getCaptionTemplate();
    final locals = await _prefs.getLocalIptcTemplates();
    final selectedId = await _prefs.getSelectedIptcTemplateId() ?? '';
    final styleCatalog = await CaptionStyleCatalog.load(_prefs);
    await _loadWireLabels();

    if (!mounted) return;
    final catalog = await _buildTemplateCatalog(
      locals,
      captionWire: captionTemplate.wireStyle,
    );
    var pickId = selectedId;
    if (pickId.isEmpty || !catalog.any((t) => t.id == pickId)) {
      pickId = catalog.isNotEmpty ? catalog.first.id : '';
    }
    IptcTemplateCatalogEntry? selected;
    for (final t in catalog) {
      if (t.id == pickId) {
        selected = t;
        break;
      }
    }

    setState(() {
      _mode = mode;
      _visibleTemplates = catalog;
      _selectedTemplateId = pickId;
      _wire = selected?.wireStyle ??
          _panelWireForCaption(captionTemplate.wireStyle);
      _captionTemplate = captionTemplate;
      _captionStyleLabel = styleCatalog.labelFor(styleCatalog.activeToken);
      _values = selected == null
          ? const {}
          : _withDefaultUrgency(
              IptcTemplateApplyService.denormalizeForPanel(
                Map<String, String>.from(selected.preset),
              ),
            );
      _clearedFields = selected?.clearedFields.toSet() ?? {};
      _loading = false;
    });

    if (selected == null) {
      await _loadPresetForWire(
        _panelWireForCaption(captionTemplate.wireStyle),
        forceReplace: true,
      );
    } else if (selected.preset.isEmpty) {
      await _loadPresetForWire(selected.wireStyle, forceReplace: true);
    }

    if (widget.populateFromFolder) {
      await _loadOriginalFromFolder();
    }
  }

  /// Panel / preset wire for the active caption style.
  WireStyle _panelWireForCaption(WireStyle wire) {
    return wire == WireStyle.custom ? WireStyle.getty : wire;
  }

  /// Label wire for menus (Getty USA + International both read as Getty).
  WireStyle _labelWireForCaption(WireStyle wire) {
    switch (wire) {
      case WireStyle.gettyInternational:
      case WireStyle.custom:
        return WireStyle.getty;
      case WireStyle.getty:
      case WireStyle.imagn:
      case WireStyle.ap:
      case WireStyle.cp:
        return wire;
    }
  }

  bool _templateMatchesCaptionWire(
    IptcTemplateCatalogEntry t,
    WireStyle captionWire,
  ) {
    final panel = _panelWireForCaption(captionWire);
    if (panel == WireStyle.getty || panel == WireStyle.gettyInternational) {
      return t.wireStyle == WireStyle.getty ||
          t.wireStyle == WireStyle.gettyInternational;
    }
    return t.wireStyle == panel;
  }

  /// Saved templates for the active caption style’s wire only.
  /// Empty when nothing has been saved yet (menu shows “Nothing saved yet”).
  Future<List<IptcTemplateCatalogEntry>> _buildTemplateCatalog(
    List<IptcTemplateCatalogEntry> locals, {
    required WireStyle captionWire,
  }) async {
    final panelWire = _panelWireForCaption(captionWire);
    final labelWire = _labelWireForCaption(captionWire);
    final out = <IptcTemplateCatalogEntry>[];
    for (final t in locals) {
      if (!_templateMatchesCaptionWire(t, captionWire)) continue;
      out.add(
        IptcTemplateCatalogEntry(
          id: t.id,
          wireStyle: panelWire,
          displayName: WireIptcSpecs.iptcTemplateLabel(
            labelWire,
            wireLabel: _wireLabels[labelWire],
            templateName: t.displayName,
          ),
          preset: t.preset,
          clearedFields: t.clearedFields,
        ),
      );
    }
    return out;
  }

  List<String> get _missingCaptionIptc =>
      CaptionFormulaRenderer.missingCaptionIptcLabels(
        template: _captionTemplate,
        game: IptcTemplateApplyService.gameInfoFromPanelValues(_values),
      );

  Future<void> _loadWireLabels() async {
    final getty = await _prefs.getCaptionWireLabel(WireStyle.getty);
    final gettyIntl =
        await _prefs.getCaptionWireLabel(WireStyle.gettyInternational);
    final imagn = await _prefs.getCaptionWireLabel(WireStyle.imagn);
    final ap = await _prefs.getCaptionWireLabel(WireStyle.ap);
    final cp = await _prefs.getCaptionWireLabel(WireStyle.cp);
    if (!mounted) return;
    setState(() {
      _wireLabels[WireStyle.getty] = getty ?? '';
      _wireLabels[WireStyle.gettyInternational] = gettyIntl ?? '';
      _wireLabels[WireStyle.imagn] = imagn ?? '';
      _wireLabels[WireStyle.ap] = ap ?? '';
      _wireLabels[WireStyle.cp] = cp ?? '';
    });
  }

  bool get _hasActiveContent =>
      _keysFoundInFiles.isNotEmpty ||
      _values.entries.any(
        (e) =>
            e.value.trim().isNotEmpty &&
            !IptcTemplateApplyService.isInAppGeneratedPlaceholder(e.value),
      );

  String get _templateLabel {
    for (final t in _visibleTemplates) {
      if (t.id == _selectedTemplateId) return t.displayName;
    }
    return WireIptcSpecs.displayWireLabel(_wire, _wireLabels[_wire]);
  }

  Future<void> _loadPresetForWire(
    WireStyle wire, {
    bool forceReplace = false,
  }) async {
    var preset = await _prefs.getIptcWirePreset(wire);
    var cleared = await _prefs.getIptcWireClearedFields(wire);
    if (preset.isEmpty) {
      IptcTemplateCatalogEntry? entry;
      for (final t in _visibleTemplates) {
        if (t.wireStyle == wire) {
          entry = t;
          break;
        }
      }
      if (entry != null && entry.preset.isNotEmpty) {
        preset = entry.preset;
        cleared = entry.clearedFields;
      }
    }
    if (!mounted) return;
    if (!forceReplace && _hasActiveContent) {
      setState(() {
        _wire = wire;
        _revision++;
      });
      return;
    }
    setState(() {
      _wire = wire;
      // Keep empty selection when nothing is saved yet.
      if (!_visibleTemplates.any((t) => t.id == _selectedTemplateId)) {
        _selectedTemplateId = '';
      }
      _values = _withDefaultUrgency(
        IptcTemplateApplyService.denormalizeForPanel(preset),
      );
      _clearedFields = cleared.toSet();
      _keysFoundInFiles.clear();
      _revision++;
    });
  }

  void _onTemplateSelected(IptcTemplateCatalogEntry entry) {
    if (_selectedTemplateId == entry.id) return;
    setState(() {
      _selectedTemplateId = entry.id;
      _wire = entry.wireStyle;
      _values = _withDefaultUrgency(
        IptcTemplateApplyService.denormalizeForPanel(
          Map<String, String>.from(entry.preset),
        ),
      );
      _clearedFields = entry.clearedFields.toSet();
      _keysFoundInFiles.clear();
      _revision++;
    });
    unawaited(_prefs.setSelectedIptcTemplateId(entry.id));
  }

  Future<void> _deleteNamedTemplate(IptcTemplateCatalogEntry entry) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete template?',
      message: 'Remove “${entry.displayName}” from saved IPTC templates?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;

    final locals = await _prefs.getLocalIptcTemplates();
    final nextLocals = <IptcTemplateCatalogEntry>[
      for (final t in locals)
        if (t.id != entry.id) t,
    ];
    await _prefs.saveLocalIptcTemplates(nextLocals);
    final catalog = await _buildTemplateCatalog(
      nextLocals,
      captionWire: _captionTemplate.wireStyle,
    );
    if (!mounted) return;

    final wasSelected = _selectedTemplateId == entry.id;
    setState(() {
      _visibleTemplates = catalog;
      if (wasSelected) {
        _selectedTemplateId =
            catalog.isNotEmpty ? catalog.first.id : '';
      }
    });
    await _prefs.setSelectedIptcTemplateId(_selectedTemplateId);
    if (wasSelected && catalog.isNotEmpty) {
      _onTemplateSelected(catalog.first);
    }
  }

  bool get _hasSelectedSavedTemplate {
    final id = _selectedTemplateId.trim();
    if (id.isEmpty) return false;
    if (id == AppDefaultsFirestoreService.templateIdForWire(_wire)) {
      return false;
    }
    return _visibleTemplates.any((t) => t.id == id);
  }

  String _currentTemplateDisplayName() {
    for (final t in _visibleTemplates) {
      if (t.id == _selectedTemplateId) {
        return WireIptcSpecs.iptcTemplateLabel(
          _wire,
          wireLabel: _wireLabels[_wire],
          templateName: t.displayName,
        );
      }
    }
    return WireIptcSpecs.iptcTemplateLabel(
      _wire,
      wireLabel: _wireLabels[_wire],
    );
  }

  Future<void> _saveNamedTemplate() async {
    final wireName = WireIptcSpecs.displayWireLabel(_wire, _wireLabels[_wire]);
    final currentName = _currentTemplateDisplayName();
    final canUpdate = _hasSelectedSavedTemplate;

    final takenNames = <String>{
      for (final t in _visibleTemplates)
        WireIptcSpecs.iptcTemplateLabel(
          _wire,
          wireLabel: _wireLabels[_wire],
          templateName: t.displayName,
        ).toLowerCase(),
    };
    final result = await _askTemplateName(
      wireName: wireName,
      initialFullName: currentName,
      canUpdate: canUpdate,
      takenNames: takenNames,
      allowedUpdateName: canUpdate ? currentName : null,
    );
    if (result == null || !mounted) return;

    final trimmed = WireIptcSpecs.iptcTemplateLabel(
      _wire,
      wireLabel: _wireLabels[_wire],
      templateName: result.name.trim(),
    );
    if (trimmed.isEmpty) return;

    final asNew = result.asNew || !canUpdate;
    // Defense in depth — dialog already blocks duplicates.
    final nameKey = trimmed.toLowerCase();
    final nameTaken = takenNames.contains(nameKey) &&
        (asNew || nameKey != currentName.toLowerCase());
    if (nameTaken) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A template named “$trimmed” already exists.'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final locals = await _prefs.getLocalIptcTemplates();
    final id = asNew
        ? 'local:${DateTime.now().millisecondsSinceEpoch}'
        : _selectedTemplateId;

    _values = _withDefaultUrgency(_values);
    final entry = IptcTemplateCatalogEntry(
      id: id,
      wireStyle: _wire,
      displayName: trimmed,
      preset: IptcTemplateApplyService.normalizeForPreset(
        _values,
        includeInAppGenerated: true,
      ),
      clearedFields: _computeClearedFields().toList(),
    );
    final nextLocals = <IptcTemplateCatalogEntry>[
      for (final t in locals)
        if (t.id != id) t,
      entry,
    ];
    await _prefs.saveLocalIptcTemplates(nextLocals);
    final catalog = await _buildTemplateCatalog(
      nextLocals,
      captionWire: _captionTemplate.wireStyle,
    );
    if (!mounted) return;
    setState(() {
      _visibleTemplates = catalog;
      _selectedTemplateId = id;
      _clearedFields = entry.clearedFields.toSet();
    });
    await _prefs.setSelectedIptcTemplateId(id);
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          asNew ? 'Saved new template “$trimmed”' : 'Saved “$trimmed”',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Returns name + whether to create a new template, or null if cancelled.
  Future<({String name, bool asNew})?> _askTemplateName({
    required String wireName,
    required String initialFullName,
    required bool canUpdate,
    required Set<String> takenNames,
    String? allowedUpdateName,
  }) {
    final prefix = '$wireName - ';
    var suffix = initialFullName.trim();
    // Keep only the part after the wire prefix in the editable field.
    for (final legacy in [
      prefix,
      'Getty USA - ',
      'Getty International - ',
      'Getty - ',
      'Imagn - ',
      'AP - ',
      'CP - ',
    ]) {
      if (suffix.toLowerCase().startsWith(legacy.toLowerCase())) {
        suffix = suffix.substring(legacy.length).trim();
        break;
      }
    }
    return showDialog<({String name, bool asNew})>(
      context: context,
      builder: (dialogContext) => _SaveIptcTemplateNameDialog(
        title: 'Save $wireName IPTC template',
        prefix: prefix,
        initialSuffix: suffix,
        canUpdate: canUpdate,
        takenNames: takenNames,
        allowedUpdateName: allowedUpdateName,
      ),
    );
  }

  void _onWireSelected(WireStyle wire) {
    if (wire == _wire) return;
    unawaited(_loadPresetForWire(wire));
  }

  void _onValueChanged(String key, String value) {
    setState(() {
      final next = Map<String, String>.from(_values);
      var trimmed = value.trim();
      if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
        trimmed = '';
      }
      if (trimmed.isEmpty) {
        next.remove(key);
      } else {
        next[key] = trimmed;
      }
      _values = next;
    });
  }

  Future<void> _onModeChanged(IptcApplyMode mode) async {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _revision++;
    });
    await _prefs.saveIptcApplyMode(mode);
    if (mode.appliesOnLoad) {
      final folder = widget.folderPath;
      if (folder != null && folder.isNotEmpty) {
        await _loadOriginalFromFolder();
      } else {
        setState(() {
          _values = const {'Urgency': '5'};
          _keysFoundInFiles.clear();
          _revision++;
        });
      }
    }
    await _persist();
  }

  Future<void> _clearTemplate() async {
    if (_loadingFromFiles || _loadingExternal) return;
    setState(() {
      _values = const {'Urgency': '5'};
      _keysFoundInFiles.clear();
      _revision++;
    });
    await _persist();
  }

  Future<List<String>> _imageFilesInFolder(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.tif') ||
          lower.endsWith('.tiff') ||
          lower.endsWith('.png')) {
        out.add(entity.path);
      }
    }
    out.sort();
    return out;
  }

  Future<void> _loadOriginalFromFolder() async {
    final folder = widget.folderPath;
    if (folder == null || folder.isEmpty) return;
    if (_loadingFromFiles || _loadingExternal) return;
    setState(() => _loadingFromFiles = true);
    try {
      final files = await _imageFilesInFolder(folder);
      if (files.isEmpty || !mounted) return;
      final sample = files.take(8).toList();
      final batch =
          await IptcTemplateImportService.readMetadataBatch(sample);
      final mergedRaw = <String, String>{};
      for (final meta in batch.values) {
        final panel = IptcTemplateImportService.panelValuesFromExiftool(meta);
        panel.forEach((k, v) {
          if (v.trim().isEmpty) return;
          mergedRaw.putIfAbsent(k, () => v);
        });
      }
      // Show fields from the photos. Caption is omitted from the pad — it is
      // never written on load and stays on each photo until the session.
      final merged = IptcTemplateApplyService.panelValuesFromImportedTemplate(
        mergedRaw,
        _wire,
      );
      mergedRaw.forEach((k, v) {
        final trimmed = v.trim();
        if (trimmed.isEmpty) return;
        if (IptcTemplateApplyService.toPresetKey(k) == 'Caption' ||
            k == 'Caption') {
          return;
        }
        merged.putIfAbsent(k, () => trimmed);
      });
      merged.removeWhere(
        (k, _) =>
            IptcTemplateApplyService.toPresetKey(k) == 'Caption' ||
            k == 'Caption',
      );
      final foundInFiles = <String>{};
      for (final e in merged.entries) {
        if (e.value.trim().isEmpty) continue;
        foundInFiles.add(e.key);
      }
      if (!mounted) return;
      setState(() {
        _values = _withDefaultUrgency(merged);
        _keysFoundInFiles
          ..clear()
          ..addAll(foundInFiles);
        _revision++;
      });
      // Don't persist folder read-through into the saved template yet — just
      // show it. Saving still happens via Save template / Done.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load IPTC from folder: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingFromFiles = false);
    }
  }

  Future<void> _loadExternalTemplate() async {
    if (_loadingExternal) return;
    String? lastDir;
    try {
      final prefs = await SharedPreferences.getInstance();
      lastDir = prefs.getString('last_template_folder');
    } catch (_) {}
    final filePath = await NativeFilePicker.pickFile(
      allowedExtensions: const ['txt', 'xmp', 'jpg', 'jpeg'],
      initialDirectory: lastDir,
    );
    if (filePath == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_template_folder',
        File(filePath).parent.path,
      );
    } catch (_) {}

    setState(() => _loadingExternal = true);
    try {
      final result = await IptcTemplateImportService.importFromPath(filePath);
      if (!mounted) return;
      if (result == null || result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No IPTC fields found in that file.')),
        );
        return;
      }
      setState(() {
        _values = _withDefaultUrgency(
          IptcTemplateApplyService.panelValuesFromImportedTemplate(
            result.values,
            _wire,
          ),
        );
        _keysFoundInFiles.clear();
        _revision++;
      });
      await _persist();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load template: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingExternal = false);
    }
  }

  Map<String, String> _withDefaultUrgency(Map<String, String> values) {
    final next = Map<String, String>.from(values);
    final current = IptcTemplateApplyService.lookupValue(next, 'Urgency');
    if (current == null || current.trim().isEmpty) {
      next['Urgency'] = '5';
    }
    return next;
  }

  Set<String> _computeClearedFields() {
    // Caption / Personality / Keywords stay on the photos — never treat blank
    // template slots as “clear this field” on load, save, or FTP.
    const neverClear = {
      'Time and Date',
      'Date',
      'Time',
      'Caption',
      'Personality',
      'Keywords',
    };
    return WireIptcSpecs.fieldsForPanel(_wire)
        .map((s) => s.storageKey)
        .where((k) => !neverClear.contains(k))
        .where(
          (k) => !_values.containsKey(k) || _values[k]!.trim().isEmpty,
        )
        .toSet();
  }

  Future<void> _persist() async {
    _values = _withDefaultUrgency(_values);
    final prefs = await SharedPreferences.getInstance();
    final preset = IptcTemplateApplyService.normalizeForPreset(
      _values,
      includeInAppGenerated: true,
    );
    if (preset.isNotEmpty) {
      await prefs.setString('selected_metadata_preset', jsonEncode(preset));
    } else {
      await prefs.remove('selected_metadata_preset');
    }
    _clearedFields = _computeClearedFields();
    await prefs.setStringList(
      'selected_metadata_preset_cleared_fields',
      _clearedFields.toList(),
    );
    await _prefs.saveIptcWirePreset(
      _wire,
      preset: preset,
      clearedFields: _clearedFields.toList(),
    );
    if (_selectedTemplateId.isNotEmpty) {
      await _prefs.setSelectedIptcTemplateId(_selectedTemplateId);
    }
    await _prefs.saveIptcApplyMode(_mode);
  }

  Future<void> _done() async {
    final missing =
        IptcTemplateApplyService.missingRequiredLabels(_wire, _values);
    await _persist();
    if (!mounted) return;
    if (missing.isNotEmpty) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Missing fields. You can fill these later.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    Navigator.of(context).pop(
      CaptionV2IptcSummary(mode: _mode, templateLabel: _templateLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Keep fields editable so folder IPTC can be reviewed and adjusted.
    const fieldsEnabled = true;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: FfTokens.sessionPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: FfTokens.sessionLn),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (size.width - 32).clamp(0.0, 1240.0),
        height: size.height - 32,
        child: Material(
          type: MaterialType.transparency,
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IptcTemplateEditor(
                  key: ValueKey('iptc-editor-$_revision-$_wire'),
                  wire: _wire,
                  templates: _visibleTemplates,
                  selectedTemplateId: _selectedTemplateId,
                  values: _values,
                  foundInFilesKeys: _keysFoundInFiles,
                  revision: _revision,
                  fieldsEnabled: fieldsEnabled,
                  onTemplateSelected: _onTemplateSelected,
                  onDeleteTemplate: (entry) =>
                      unawaited(_deleteNamedTemplate(entry)),
                  onValueChanged: _onValueChanged,
                  onLoadTemplate: _loadExternalTemplate,
                  onClearTemplate: _clearTemplate,
                  onSaveTemplate: () => unawaited(_saveNamedTemplate()),
                  loadEnabled: !_loadingExternal && !_loadingFromFiles,
                  clearEnabled: !_loadingExternal,
                  loadingTemplate: _loadingExternal,
                  applyMode: _mode,
                  onApplyModeChanged: (mode) =>
                      unawaited(_onModeChanged(mode)),
                  captionTemplate: _captionTemplate,
                  captionStyleLabel: _captionStyleLabel,
                  wireLabels: Map<WireStyle, String>.from(_wireLabels),
                  onCancel: () => Navigator.of(context).pop(),
                  onDone: _done,
                ),
        ),
      ),
    );
  }

}

/// Owns the name field controller so it isn’t disposed while the route is
/// still animating out (avoids `_dependents.isEmpty` assertion).
class _SaveIptcTemplateNameDialog extends StatefulWidget {
  const _SaveIptcTemplateNameDialog({
    required this.title,
    required this.prefix,
    required this.initialSuffix,
    required this.canUpdate,
    required this.takenNames,
    this.allowedUpdateName,
  });

  final String title;
  final String prefix;
  final String initialSuffix;
  final bool canUpdate;
  /// Lowercased full names already in use for this wire.
  final Set<String> takenNames;
  /// When updating, this name may be kept (Save only — not Save as new).
  final String? allowedUpdateName;

  @override
  State<_SaveIptcTemplateNameDialog> createState() =>
      _SaveIptcTemplateNameDialogState();
}

class _SaveIptcTemplateNameDialogState
    extends State<_SaveIptcTemplateNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSuffix);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop({required bool asNew}) {
    final fullName = '${widget.prefix}${_controller.text.trim()}';
    final key = fullName.toLowerCase();
    final allowed = widget.allowedUpdateName?.trim().toLowerCase();
    final conflict = widget.takenNames.contains(key) &&
        (asNew || allowed == null || key != allowed);
    if (conflict) {
      setState(() {
        _error = 'A template with this name already exists.';
      });
      return;
    }
    Navigator.of(context).pop((
      name: fullName,
      asNew: asNew,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FfTokens.sessionPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: FfTokens.sessionLn),
      ),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FfTokens.sessionTx,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Name',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  color: FfTokens.sessionT2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  color: FfTokens.sessionTx,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: FfTokens.sessionEl,
                  prefixText: widget.prefix,
                  prefixStyle: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _pop(asNew: !widget.canUpdate),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.danger,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        color: FfTokens.sessionT2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _pop(asNew: true),
                    child: const Text(
                      'Save as new',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        color: FfTokens.sessionT2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _pop(asNew: false),
                    style: FilledButton.styleFrom(
                      backgroundColor: FfTokens.sessionTx,
                      foregroundColor: FfTokens.sessionBg,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
