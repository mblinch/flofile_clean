import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/preferences_service.dart';
import '../../../utils/native_file_picker.dart';
import '../../../widgets/startup_iptc_template_panel.dart';

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
  Map<String, String> _values = {};
  final Set<String> _keysFoundInFiles = {};
  Set<String> _clearedFields = {};
  int _revision = 0;
  bool _loading = true;
  bool _loadingFromFiles = false;
  bool _loadingExternal = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _prefs = await PreferencesService.getInstance();
    final mode = await _prefs.getIptcApplyMode();
    final hidden = await _prefs.getHiddenIptcTemplateIds();
    final visible = await AppDefaultsFirestoreService.getVisibleIptcTemplates(
      hiddenIds: hidden,
    );
    final selectedId = await _prefs.getSelectedIptcTemplateId();
    await _loadWireLabels();

    String id = selectedId ?? 'getty';
    if (visible.isNotEmpty && !visible.any((t) => t.id == id)) {
      id = visible.first.id;
    }
    WireStyle wire = WireStyle.getty;
    for (final t in visible) {
      if (t.id == id) {
        wire = t.wireStyle;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _mode = mode;
      _visibleTemplates = visible;
      _selectedTemplateId = id;
      _wire = wire;
      _loading = false;
    });
    await _loadPresetForWire(wire, forceReplace: true);
  }

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
        _values = IptcTemplateApplyService.panelValuesFromImportedTemplate(
          _values,
          wire,
        );
        _revision++;
      });
      return;
    }
    setState(() {
      _wire = wire;
      _selectedTemplateId = AppDefaultsFirestoreService.templateIdForWire(wire);
      _values = IptcTemplateApplyService.denormalizeForPanel(preset);
      _clearedFields = cleared.toSet();
      _keysFoundInFiles.clear();
      _revision++;
    });
  }

  void _onTemplateSelected(IptcTemplateCatalogEntry entry) {
    if (_wire == entry.wireStyle && _selectedTemplateId == entry.id) return;
    setState(() => _selectedTemplateId = entry.id);
    unawaited(_loadPresetForWire(entry.wireStyle));
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
          _values = {};
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
      _values = {};
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
        _values = merged;
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
        _values = IptcTemplateApplyService.panelValuesFromImportedTemplate(
          result.values,
          _wire,
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
    await _prefs.setSelectedIptcTemplateId(_selectedTemplateId);
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      backgroundColor: const Color(0xFFF7F7F7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: (size.width * 0.72).clamp(640.0, 980.0),
        height: (size.height * 0.82).clamp(480.0, 820.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFEFEFE),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE0E0E0)),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'IPTC TEMPLATE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF333333),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _loading ? null : _done,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4A7A96),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                      child: StartupIptcTemplatePanel(
                        selectedWire: _wire,
                        wireLabels: _wireLabels,
                        values: _values,
                        foundInFilesKeys: _keysFoundInFiles,
                        isLoading: _loadingFromFiles,
                        onValueChanged: _onValueChanged,
                        onWireSelected: _onWireSelected,
                        visibleTemplates: _visibleTemplates,
                        selectedTemplateId: _selectedTemplateId,
                        onTemplateSelected: _onTemplateSelected,
                        iptcApplyMode: _mode,
                        onIptcApplyModeChanged: _onModeChanged,
                        onLoadTemplate: _loadExternalTemplate,
                        onClearTemplate: _clearTemplate,
                        onLoadOriginalValues: _loadOriginalFromFolder,
                        isLoadTemplateLoading: _loadingExternal,
                        isLoadTemplateDisabled: _loadingFromFiles,
                        isLoadOriginalValuesDisabled:
                            widget.folderPath == null ||
                                widget.folderPath!.isEmpty,
                        templateRevision: _revision,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
