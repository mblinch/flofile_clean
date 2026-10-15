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
        return "Don't write IPTC";
      case IptcApplyMode.onImport:
        return 'Write IPTC on import · $wire';
      case IptcApplyMode.onSave:
        return 'Write IPTC on save · $wire';
    }
  }
}

/// Opens the classic IPTC template panel in a dialog for Caption V2.
Future<CaptionV2IptcSummary?> showCaptionV2IptcDialog(
  BuildContext context, {
  String? folderPath,
}) {
  return showDialog<CaptionV2IptcSummary>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CaptionV2IptcDialog(folderPath: folderPath),
  );
}

class CaptionV2IptcDialog extends StatefulWidget {
  const CaptionV2IptcDialog({super.key, this.folderPath});

  final String? folderPath;

  @override
  State<CaptionV2IptcDialog> createState() => _CaptionV2IptcDialogState();
}

class _CaptionV2IptcDialogState extends State<CaptionV2IptcDialog> {
  late PreferencesService _prefs;

  IptcApplyMode _mode = IptcApplyMode.none;
  WireStyle _wire = WireStyle.getty;
  String _selectedTemplateId = 'getty';
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
    final mode = await _prefs.getIptcApplyMode();
    final hidden = await _prefs.getHiddenIptcTemplateIds();
    final visible = await AppDefaultsFirestoreService.getVisibleIptcTemplates(
      hiddenIds: hidden,
    );
    final local = await _prefs.getLocalIptcTemplates();
    final captionTemplate = await _prefs.getCaptionTemplate();
    await _loadWireLabels();

    if (!mounted) return;
    setState(() {
      _mode = mode;
      _visibleTemplates = [
        ...local,
        for (final t in visible)
          if (!local.any((saved) => saved.id == t.id)) t,
      ];
      _selectedTemplateId = '';
      _wire = WireStyle.getty;
      _captionTemplate = captionTemplate;
      _values = const {'Urgency': '5'};
      _loading = false;
    });
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
      if (t.id == _selectedTemplateId && t.id.startsWith('local:')) {
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
      preset: IptcTemplateApplyService.normalizeForPreset(_values),
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
      _visibleTemplates = [
        ...next,
        for (final t in _visibleTemplates)
          if (!t.id.startsWith('local:')) t,
      ];
      _selectedTemplateId = id;
      _clearedFields = entry.clearedFields.toSet();
    });
    await _persist();
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
    if (mode == IptcApplyMode.onImport) {
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
      final merged = IptcTemplateApplyService.panelValuesFromImportedTemplate(
        mergedRaw,
        _wire,
      );
      if (!mounted) return;
      setState(() {
        _values = _withDefaultUrgency(merged);
        _keysFoundInFiles
          ..clear()
          ..addAll(merged.keys.where(
            (key) => !IptcTemplateApplyService.isInAppGeneratedFieldKey(key),
          ));
        _revision++;
      });
      await _persist();
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
    const neverClear = {'Time and Date', 'Date', 'Time'};
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
    final preset = IptcTemplateApplyService.normalizeForPreset(_values);
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
    await _persist();
    if (!mounted) return;
    Navigator.of(context).pop(
      CaptionV2IptcSummary(mode: _mode, templateLabel: _templateLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fieldsOff = _mode == IptcApplyMode.none;
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
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IptcTemplateEditor(
                wire: _wire,
                templates: _visibleTemplates,
                selectedTemplateId: _selectedTemplateId,
                values: _values,
                foundInFilesKeys: _keysFoundInFiles,
                revision: _revision,
                fieldsEnabled: !fieldsOff,
                onTemplateSelected: _onTemplateSelected,
                onValueChanged: _onValueChanged,
                onLoadTemplate: _loadExternalTemplate,
                onClearTemplate: _clearTemplate,
                onSaveTemplate: _saveNamedTemplate,
                loadEnabled: !_loadingExternal && !_loadingFromFiles && !fieldsOff,
                clearEnabled: !_loadingExternal && !fieldsOff,
                loadingTemplate: _loadingExternal,
                onCancel: () => Navigator.of(context).pop(),
                onDone: _done,
              ),
      ),
    );
  }

}
