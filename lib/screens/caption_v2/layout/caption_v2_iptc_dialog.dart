import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
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
}) {
  return showDialog<CaptionV2IptcSummary>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CaptionV2IptcDialog(
      folderPath: folderPath,
      enableWriting: enableWriting,
      populateFromFolder: populateFromFolder,
    ),
  );
}

class CaptionV2IptcDialog extends StatefulWidget {
  const CaptionV2IptcDialog({
    super.key,
    this.folderPath,
    this.enableWriting = false,
    this.populateFromFolder = false,
  });

  final String? folderPath;

  /// Opened from the start-menu Write IPTC switch. Fields stay editable, and
  /// writing is saved only when the user finishes the dialog.
  final bool enableWriting;

  /// When true (folder just chosen), fill the panel from image IPTC and show
  /// what is already populated vs still missing.
  final bool populateFromFolder;

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
    final captionTemplate = await _prefs.getCaptionTemplate();
    final locals = await _prefs.getLocalIptcTemplates();
    await _loadWireLabels();

    if (!mounted) return;
    setState(() {
      _mode = mode;
      // User-created templates only — no built-in wire list.
      _visibleTemplates = locals;
      // Start unselected — dropdown shows "Choose" until the user picks one.
      _selectedTemplateId = '';
      _wire = captionTemplate.wireStyle;
      _captionTemplate = captionTemplate;
      _values = const {};
      _loading = false;
    });

    if (widget.populateFromFolder) {
      await _loadOriginalFromFolder();
    }
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
        _selectedTemplateId = AppDefaultsFirestoreService.templateIdForWire(wire);
        _values = _withDefaultUrgency(
          IptcTemplateApplyService.panelValuesFromImportedTemplate(
            _values,
            wire,
          ),
        );
        _revision++;
      });
      return;
    }
    setState(() {
      _wire = wire;
      _selectedTemplateId = AppDefaultsFirestoreService.templateIdForWire(wire);
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
  }

  Future<void> _saveNamedTemplate() async {
    var currentName = '';
    for (final t in _visibleTemplates) {
      if (t.id == _selectedTemplateId) {
        currentName = t.displayName;
        break;
      }
    }
    final name = await _askTemplateName(currentName);
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final locals = await _prefs.getLocalIptcTemplates();
    var id = 'local:${DateTime.now().millisecondsSinceEpoch}';
    for (final t in locals) {
      if (t.displayName.toLowerCase() == trimmed.toLowerCase()) {
        id = t.id;
        break;
      }
    }
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
    final next = <IptcTemplateCatalogEntry>[
      for (final t in locals)
        if (t.id != id) t,
      entry,
    ];
    await _prefs.saveLocalIptcTemplates(next);
    if (!mounted) return;
    setState(() {
      _visibleTemplates = next;
      _selectedTemplateId = id;
      _clearedFields = entry.clearedFields.toSet();
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved “$trimmed”'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _askTemplateName(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: FfTokens.sessionPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: FfTokens.sessionLn),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Save template',
                  style: TextStyle(
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
                  controller: controller,
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          color: FfTokens.sessionT2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text),
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
        );
      },
    ).whenComplete(controller.dispose);
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
            'IPTC missing: ${missing.join(', ')}. You can fill these later.',
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
                  onValueChanged: _onValueChanged,
                  onLoadTemplate: _loadExternalTemplate,
                  onClearTemplate: _clearTemplate,
                  onSaveTemplate: _saveNamedTemplate,
                  loadEnabled: !_loadingExternal && !_loadingFromFiles,
                  clearEnabled: !_loadingExternal,
                  loadingTemplate: _loadingExternal,
                  applyMode: _mode,
                  onApplyModeChanged: (mode) =>
                      unawaited(_onModeChanged(mode)),
                  onCancel: () => Navigator.of(context).pop(),
                  onDone: _done,
                ),
        ),
      ),
    );
  }

}
