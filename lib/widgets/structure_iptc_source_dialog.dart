import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/game_info.dart';
import '../caption_style/structure_formula.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/iptc_template_apply_service.dart';
import '../services/iptc_template_import_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'startup_iptc_template_panel.dart';

/// Opens the IPTC master panel focused on the field a structure chip reads.
///
/// Seeds the panel from the wire IPTC preset, then overlays values from
/// [game] (loaded photo / session IPTC) and marks those keys as found in files.
Future<void> showStructureIptcSourceDialog(
  BuildContext context, {
  required String structureKey,
  required WireStyle wire,
  required GameInfo game,
}) {
  final panelKey = StructureFormulaKeys.iptcPanelKey(structureKey);
  final chipLabel = StructureFormulaKeys.label(structureKey);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _StructureIptcSourceDialog(
      structureKey: structureKey,
      panelKey: panelKey,
      chipLabel: chipLabel,
      wire: wire,
      game: game,
    ),
  );
}

class _StructureIptcSourceDialog extends StatefulWidget {
  const _StructureIptcSourceDialog({
    required this.structureKey,
    required this.panelKey,
    required this.chipLabel,
    required this.wire,
    required this.game,
  });

  final String structureKey;
  final String? panelKey;
  final String chipLabel;
  final WireStyle wire;
  final GameInfo game;

  @override
  State<_StructureIptcSourceDialog> createState() =>
      _StructureIptcSourceDialogState();
}

class _StructureIptcSourceDialogState extends State<_StructureIptcSourceDialog> {
  Map<String, String> _values = const {};
  Set<String> _foundInFiles = {};
  int _revision = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PreferencesService.getInstance();
    final preset = await prefs.getIptcWirePreset(widget.wire);
    final base = IptcTemplateApplyService.denormalizeForPanel(
      Map<String, String>.from(preset),
    );

    final fromPhoto = <String, String>{};
    final found = <String>{};

    void put(String key, String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      fromPhoto[key] = v;
      found.add(key);
    }

    // Structured GameInfo fields (session / photo-derived).
    put('City', widget.game.city);
    put('Province/State', widget.game.resolvedRegionName.isNotEmpty
        ? widget.game.resolvedRegionName
        : widget.game.region);
    put('Country', widget.game.country);
    put('Country Code', widget.game.countryCode);
    put('Creator', widget.game.photographerName);
    put('Credit', widget.game.agencyName);
    final loc = CaptionFormulaRenderer.storedVenue(widget.game);
    put('Location', loc);

    // Raw IPTC map on the game (exiftool-style keys from the loaded photo).
    if (widget.game.iptcMetadata.isNotEmpty) {
      final panel = IptcTemplateImportService.panelValuesFromExiftool(
        Map<String, dynamic>.from(widget.game.iptcMetadata),
      );
      panel.forEach((k, v) {
        if (v.trim().isEmpty) return;
        if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(v)) return;
        fromPhoto[k] = v.trim();
        found.add(k);
      });
    }

    final merged = Map<String, String>.from(base);
    fromPhoto.forEach((k, v) => merged[k] = v);

    if (IptcTemplateApplyService.lookupValue(merged, 'Urgency')
            ?.trim()
            .isEmpty ??
        true) {
      merged['Urgency'] = '5';
    }

    if (!mounted) return;
    setState(() {
      _values = merged;
      _foundInFiles = found;
      _revision++;
      _loading = false;
    });
  }

  String get _sourceBlurb {
    final key = widget.panelKey;
    if (key == null) {
      return '${widget.chipLabel} is not backed by an IPTC panel field.';
    }
    if (key == 'Camera time') {
      return 'Date chips use the photo’s DateTimeOriginal (Camera time).';
    }
    if (key == 'Caption') {
      return 'Caption is written by the app into IPTC Caption / Description.';
    }
    if (_foundInFiles.contains(key)) {
      return 'Highlighted field is filled from the loaded photo’s IPTC.';
    }
    return 'Highlighted field is the IPTC master row this chip reads.';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.identificationCard,
                      size: 18,
                      color: t.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IPTC master · ${widget.chipLabel}',
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sourceBlurb,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: PhosphorIcon(
                        PhosphorIconsRegular.x,
                        size: 16,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.divider),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : IptcPanelStyle(
                        session: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          child: StartupIptcTemplatePanel(
                            selectedWire: widget.wire,
                            wireLabels: {
                              for (final w in WireIptcSpecs.builtInWires)
                                w: WireIptcSpecs.factoryWireLabel(w),
                            },
                            values: _values,
                            foundInFilesKeys: _foundInFiles,
                            highlightStorageKey: widget.panelKey,
                            iptcApplyMode: IptcApplyMode.none,
                            fieldsOnly: true,
                            templateRevision: _revision,
                            sessionStyle: true,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    if (_foundInFiles.isNotEmpty) ...[
                      PhosphorIcon(
                        PhosphorIconsRegular.checkCircle,
                        size: 14,
                        color: FfTokens.sessionOk,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Green = found in loaded photo IPTC',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 11,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    AppSecondaryButton(
                      label: 'Close',
                      fullWidth: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
