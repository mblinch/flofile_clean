import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/teal_action_button.dart';

/// Blank field the caption structure still needs.
const Color _captionWarn = FfTokens.danger;
final Color _captionWarnLine = FfTokens.danger.withValues(alpha: 0.45);

/// Blank field the wire still needs for filing (e.g. Getty) — muted grey so
/// caption-required (red) stays the urgent signal.
const Color _filingWarn = FfTokens.sessionT2;
final Color _filingWarnLine = FfTokens.sessionT2.withValues(alpha: 0.45);

enum _FieldAlert { none, caption, filing }

Color _alertColor(_FieldAlert alert) {
  switch (alert) {
    case _FieldAlert.caption:
      return _captionWarn;
    case _FieldAlert.filing:
      return _filingWarn;
    case _FieldAlert.none:
      return Colors.transparent;
  }
}

/// Hover/tap tip for list fields — always merge, never overwrite.
String _listMergeTip(String field) {
  final subject = field == 'Personality' ? 'Personality names' : field;
  return '$subject are added to what’s already in the IPTC — never '
      'overwritten. Duplicates will not be added.';
}

enum _LegendFocus { none, caption, filing }

/// Opens the IPTC editor with caption (red) or filing (yellow) fields highlighted.
enum IptcMissingHighlight { caption, filing }

/// Shared tap group: fields + legend buttons. Outside taps dismiss focus mode.
const Object _legendFocusTapGroup = Object();

/// Visual tab order for IPTC panel fields (Story → Credit → Location → Filing).
const List<String> _iptcTabOrder = [
  'Headline',
  'Personality',
  'Keywords',
  'Special Instructions',
  'Creator',
  'Job Title',
  'Description Writers',
  'Credit',
  'Source',
  'Copyright',
  'Location',
  'City',
  'Province/State',
  'Country',
  'Country Code',
  'MEID',
  'Object Name',
  'Category',
  'Supp Cat 1',
  'Supp Cat 2',
  'Supp Cat 3',
  'Urgency',
];

class _IptcTabField {
  _IptcTabField({
    required this.id,
    required this.node,
    required this.needsCaptionFill,
    required this.needsFilingFill,
  });

  final String id;
  final FocusNode node;
  bool Function() needsCaptionFill;
  bool Function() needsFilingFill;

  int get order {
    final i = _iptcTabOrder.indexOf(id);
    return i < 0 ? 999 : i;
  }
}

/// Footer legend focus — dim fields that aren’t in the selected alert group.
class _LegendFocusScope extends InheritedWidget {
  const _LegendFocusScope({
    required this.focus,
    required this.onToggleCaption,
    required this.onToggleFiling,
    required this.dismissFocus,
    required this.registerTabField,
    required this.unregisterTabField,
    required this.focusNextNeeded,
    required super.child,
  });

  final _LegendFocus focus;
  final VoidCallback onToggleCaption;
  final VoidCallback onToggleFiling;
  final VoidCallback dismissFocus;
  final void Function(_IptcTabField field) registerTabField;
  final void Function(FocusNode node) unregisterTabField;
  final bool Function({required FocusNode from, required bool reverse})
      focusNextNeeded;

  static _LegendFocusScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LegendFocusScope>();

  @override
  bool updateShouldNotify(_LegendFocusScope oldWidget) =>
      focus != oldWidget.focus;
}

class _LegendFocusHost extends StatefulWidget {
  const _LegendFocusHost({
    required this.child,
    this.initialFocusField,
    this.initialMissingHighlight,
  });

  final Widget child;

  /// IPTC panel storage key / tab id to focus once fields register.
  final String? initialFocusField;

  /// When set (e.g. from startup “Missing fields”), enter legend highlight
  /// mode and focus the first blank field in that group.
  final IptcMissingHighlight? initialMissingHighlight;

  @override
  State<_LegendFocusHost> createState() => _LegendFocusHostState();
}

class _LegendFocusHostState extends State<_LegendFocusHost> {
  late _LegendFocus _focus;
  final List<_IptcTabField> _tabFields = [];
  bool _didInitialFocus = false;
  bool _didInitialLegendFocus = false;

  @override
  void initState() {
    super.initState();
    switch (widget.initialMissingHighlight) {
      case IptcMissingHighlight.caption:
        _focus = _LegendFocus.caption;
      case IptcMissingHighlight.filing:
        _focus = _LegendFocus.filing;
      case null:
        _focus = _LegendFocus.none;
    }
  }

  void _toggle(_LegendFocus target) {
    final next = _focus == target ? _LegendFocus.none : target;
    setState(() => _focus = next);
    if (next == _LegendFocus.none) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focus != next) return;
      _focusFirstNeeded(next);
    });
  }

  void _focusFirstNeeded(_LegendFocus mode) {
    final sorted = [..._tabFields]..sort((a, b) => a.order.compareTo(b.order));
    for (final field in sorted) {
      final needed = mode == _LegendFocus.caption
          ? field.needsCaptionFill()
          : field.needsFilingFill();
      if (needed) {
        field.node.requestFocus();
        return;
      }
    }
  }

  void _dismissFocus() {
    if (_focus == _LegendFocus.none) return;
    setState(() => _focus = _LegendFocus.none);
  }

  void _registerTabField(_IptcTabField field) {
    _tabFields.removeWhere((e) => e.node == field.node || e.id == field.id);
    _tabFields.add(field);
    final target = widget.initialFocusField?.trim();
    if (!_didInitialFocus && target != null && target.isNotEmpty) {
      if (field.id == target) {
        _didInitialFocus = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          field.node.requestFocus();
        });
      }
    }
    if (_didInitialLegendFocus || _focus == _LegendFocus.none) return;
    final needed = _focus == _LegendFocus.caption
        ? field.needsCaptionFill()
        : field.needsFilingFill();
    if (!needed) return;
    _didInitialLegendFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focus == _LegendFocus.none) return;
      _focusFirstNeeded(_focus);
    });
  }

  void _unregisterTabField(FocusNode node) {
    _tabFields.removeWhere((e) => e.node == node);
  }

  bool _focusNextNeeded({required FocusNode from, required bool reverse}) {
    if (_focus == _LegendFocus.none) return false;
    final sorted = [..._tabFields]..sort((a, b) => a.order.compareTo(b.order));
    if (sorted.isEmpty) return false;

    bool needed(_IptcTabField f) {
      switch (_focus) {
        case _LegendFocus.caption:
          return f.needsCaptionFill();
        case _LegendFocus.filing:
          return f.needsFilingFill();
        case _LegendFocus.none:
          return false;
      }
    }

    final neededFields = sorted.where(needed).toList();
    if (neededFields.isEmpty) return false;

    final fromIndex = sorted.indexWhere((f) => f.node == from);
    if (fromIndex < 0) {
      neededFields.first.node.requestFocus();
      return true;
    }

    if (reverse) {
      for (var i = fromIndex - 1; i >= 0; i--) {
        if (needed(sorted[i])) {
          sorted[i].node.requestFocus();
          return true;
        }
      }
      neededFields.last.node.requestFocus();
      return true;
    }

    for (var i = fromIndex + 1; i < sorted.length; i++) {
      if (needed(sorted[i])) {
        sorted[i].node.requestFocus();
        return true;
      }
    }
    neededFields.first.node.requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return _LegendFocusScope(
      focus: _focus,
      onToggleCaption: () => _toggle(_LegendFocus.caption),
      onToggleFiling: () => _toggle(_LegendFocus.filing),
      dismissFocus: _dismissFocus,
      registerTabField: _registerTabField,
      unregisterTabField: _unregisterTabField,
      focusNextNeeded: _focusNextNeeded,
      child: widget.child,
    );
  }
}

Color _alertLine(_FieldAlert alert) {
  switch (alert) {
    case _FieldAlert.caption:
      return _captionWarnLine;
    case _FieldAlert.filing:
      return _filingWarnLine;
    case _FieldAlert.none:
      return Colors.transparent;
  }
}

/// Session colors for the start-menu template. Workspace colors match captioning.
class IptcEditorColors {
  const IptcEditorColors.session() : workspace = false;
  const IptcEditorColors.workspace() : workspace = true;

  final bool workspace;

  Color get group => workspace ? FfTokens.nocturneEl : FfTokens.sessionBg;
  Color get field => workspace ? FfTokens.nocturneSunken : FfTokens.sessionEl;
  Color get hover => workspace ? FfTokens.nocturneHv : FfTokens.sessionHv;
  Color get line => workspace ? FfTokens.nocturneLn : FfTokens.sessionLn;
  Color get tx => workspace ? FfTokens.nocturneTx : FfTokens.sessionTx;
  Color get t2 => workspace ? FfTokens.nocturneT2 : FfTokens.sessionT2;
  Color get t3 => workspace ? FfTokens.nocturneT3 : FfTokens.sessionT3;
  Color get focus => workspace ? FfTokens.nocturneAc : FfTokens.sessionOn;
  Color get ok => FfTokens.sessionOk;
}

class IptcEditorPalette extends InheritedWidget {
  const IptcEditorPalette({super.key, required this.colors, required super.child});

  final IptcEditorColors colors;

  static IptcEditorColors of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<IptcEditorPalette>()
            ?.colors ??
        const IptcEditorColors.session();
  }

  @override
  bool updateShouldNotify(IptcEditorPalette oldWidget) =>
      colors.workspace != oldWidget.colors.workspace;
}

/// Layout-only IPTC template editor. Values stay in the parent dialog.
class IptcTemplateEditor extends StatelessWidget {
  const IptcTemplateEditor({
    super.key,
    required this.wire,
    required this.templates,
    required this.selectedTemplateId,
    required this.values,
    required this.foundInFilesKeys,
    required this.revision,
    required this.fieldsEnabled,
    required this.onTemplateSelected,
    required this.onValueChanged,
    required this.onLoadTemplate,
    required this.onClearTemplate,
    required this.onSaveTemplate,
    this.onDeleteTemplate,
    required this.onCancel,
    required this.onDone,
    this.loadEnabled = true,
    this.clearEnabled = true,
    this.loadingTemplate = false,
    this.title = 'IPTC template',
    this.subtitle,
    this.doneLabel = 'Done',
    this.showTemplateControls = true,
    this.workspacePalette = false,
    this.embedded = false,
    this.leading,
    this.applyMode,
    this.onApplyModeChanged,
    this.captionTemplate,
    this.captionStyleLabel,
    this.wireLabels = const {},
    this.initialFocusField,
    this.initialMissingHighlight,
    this.templatePageHeader = false,
  });

  final WireStyle wire;
  final List<IptcTemplateCatalogEntry> templates;
  final String selectedTemplateId;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;
  final int revision;
  final bool fieldsEnabled;
  final ValueChanged<IptcTemplateCatalogEntry> onTemplateSelected;
  final void Function(String storageKey, String value) onValueChanged;
  final VoidCallback? onLoadTemplate;
  final VoidCallback? onClearTemplate;
  final VoidCallback? onSaveTemplate;
  final ValueChanged<IptcTemplateCatalogEntry>? onDeleteTemplate;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final bool loadEnabled;
  final bool clearEnabled;
  final bool loadingTemplate;
  final String title;
  final String? subtitle;
  final String doneLabel;

  /// Template picker, load, and save. Off when editing one photo's IPTC.
  final bool showTemplateControls;

  /// Nocturne caption-workspace colors. The start menu keeps the session palette.
  final bool workspacePalette;

  /// Inline embed (New Session): hide close + Cancel/Done chrome.
  final bool embedded;

  /// Optional left column, used for the photo in Edit IPTC.
  final Widget? leading;

  /// IPTC panel field id to focus when the editor first builds (e.g. City).
  final String? initialFocusField;

  /// Highlight blank caption (red) or filing (yellow) fields on open.
  final IptcMissingHighlight? initialMissingHighlight;

  /// When set, shows Apply on load / save / FTP under the header.
  final IptcApplyMode? applyMode;
  final ValueChanged<IptcApplyMode>? onApplyModeChanged;

  /// Active caption style — blank fields it needs for the caption are marked red.
  final CaptionTemplate? captionTemplate;

  /// Label for the active caption style shown in the header.
  final String? captionStyleLabel;

  /// Optional custom wire names for grouped template labels.
  final Map<WireStyle, String> wireLabels;

  /// New Session template modes — one accent header line ("TEMPLATE PAGE").
  final bool templatePageHeader;

  static const _monoKeys = {
    'MEID',
    'Object Name',
    'Category',
    'Supp Cat 1',
    'Supp Cat 2',
    'Supp Cat 3',
    'Country Code',
  };

  @override
  Widget build(BuildContext context) {
    final specs = {
      for (final spec in WireIptcSpecs.fieldsForPanel(wire)) spec.label: spec,
    };
    final colors = workspacePalette
        ? const IptcEditorColors.workspace()
        : const IptcEditorColors.session();
    return IptcEditorPalette(
      colors: colors,
      child: _LegendFocusHost(
        initialFocusField: initialFocusField,
        initialMissingHighlight: initialMissingHighlight,
        child: LayoutBuilder(
        builder: (context, constraints) {
          // Match IPTC Editor v2.html breakpoints.
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 800.0;
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1200.0;
          final compact = embedded || h < 820 || w < 1100;
          final narrow = !embedded && w < 1100;
          // Edit IPTC.html uses label-above fields; New Session keeps label-left.
          final editIptc = workspacePalette;
          final fieldH = embedded
              ? 24.0
              : editIptc
                  ? (compact ? 38.0 : 34.0)
                  : (narrow ? 36.0 : 32.0);
          final gap = embedded ? 4.0 : (compact ? 8.0 : 10.0);
          final labelAbove = editIptc;

          final Widget fieldsBody;
          if (editIptc) {
            // Edit IPTC.html — stacked category rows + 6-col-style field grids.
            fieldsBody = TapRegion(
              groupId: _legendFocusTapGroup,
              onTapOutside: (_) {
                _LegendFocusScope.maybeOf(context)?.dismissFocus();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _editIptcCat(
                    colors: colors,
                    icon: PhosphorIconsRegular.article,
                    title: 'Story',
                    compact: compact,
                    first: true,
                    child: Column(
                      children: [
                        _text(
                          specs,
                          'Headline',
                          compact,
                          fieldH,
                          labelAbove: labelAbove,
                        ),
                        SizedBox(height: compact ? 6 : 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _text(
                                specs,
                                'Personality',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              child: _text(
                                specs,
                                'Keywords',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 6 : 12),
                        _text(
                          specs,
                          'Special Instructions',
                          compact,
                          fieldH,
                          display: 'Instructions',
                          labelAbove: labelAbove,
                        ),
                      ],
                    ),
                  ),
                  _editIptcCat(
                    colors: colors,
                    icon: PhosphorIconsRegular.user,
                    title: 'Credit',
                    compact: compact,
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _text(
                                specs,
                                'Creator',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              child: _text(
                                specs,
                                'Job Title',
                                compact,
                                fieldH,
                                display: 'Job title',
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              child: _text(
                                specs,
                                'Description Writers',
                                compact,
                                fieldH,
                                display: 'Writers',
                                labelAbove: labelAbove,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 6 : 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _text(
                                specs,
                                'Credit',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              child: _text(
                                specs,
                                'Source',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              child: _text(
                                specs,
                                'Copyright',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _editIptcCat(
                    colors: colors,
                    icon: PhosphorIconsRegular.mapPin,
                    title: 'Location',
                    compact: compact,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _text(
                            specs,
                            'Location',
                            compact,
                            fieldH,
                            display: 'Venue',
                            labelAbove: labelAbove,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 10),
                        Expanded(
                          child: _text(
                            specs,
                            'City',
                            compact,
                            fieldH,
                            labelAbove: labelAbove,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 10),
                        Expanded(
                          child: _text(
                            specs,
                            'Province/State',
                            compact,
                            fieldH,
                            display: 'State / Prov',
                            labelAbove: labelAbove,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 10),
                        Expanded(
                          child: _text(
                            specs,
                            'Country',
                            compact,
                            fieldH,
                            labelAbove: labelAbove,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 10),
                        _text(
                          specs,
                          'Country Code',
                          compact,
                          fieldH,
                          display: 'Country Code',
                          labelAbove: labelAbove,
                          fieldWidth: 52,
                        ),
                      ],
                    ),
                  ),
                  _editIptcCat(
                    colors: colors,
                    icon: PhosphorIconsRegular.folder,
                    title: 'Filing',
                    compact: compact,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 19,
                              child: _text(
                                specs,
                                'Object Name',
                                compact,
                                fieldH,
                                display: 'Object name',
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              flex: 11,
                              child: _text(
                                specs,
                                'MEID',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              flex: 8,
                              child: _text(
                                specs,
                                'Category',
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(
                              flex: 22,
                              child: _supp(
                                specs,
                                compact,
                                fieldH,
                                colors,
                                labelAbove: labelAbove,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 6 : 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 19,
                              child: _urgency(
                                specs,
                                compact,
                                fieldH,
                                labelAbove: labelAbove,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 10),
                            const Expanded(flex: 11, child: SizedBox.shrink()),
                            SizedBox(width: compact ? 6 : 10),
                            const Expanded(flex: 8, child: SizedBox.shrink()),
                            SizedBox(width: compact ? 6 : 10),
                            const Expanded(flex: 22, child: SizedBox.shrink()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Clear all sits under Filing (last category), not in the header.
                  if (clearEnabled && onClearTemplate != null) ...[
                    SizedBox(height: compact ? 4 : 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _ClearLink(
                        onTap: onClearTemplate,
                        compact: compact,
                      ),
                    ),
                  ],
                ],
              ),
            );
          } else {
            final story = _group(
              colors: colors,
              icon: PhosphorIconsRegular.article,
              title: 'Story',
              compact: compact,
              children: [
                _text(specs, 'Headline', narrow, fieldH),
                _text(specs, 'Personality', narrow, fieldH),
                _text(specs, 'Keywords', narrow, fieldH),
                _text(
                  specs,
                  'Special Instructions',
                  narrow,
                  fieldH,
                  display: 'Instructions',
                ),
              ],
            );
            final credit = _group(
              colors: colors,
              icon: PhosphorIconsRegular.user,
              title: 'Credit',
              compact: compact,
              children: [
                _text(specs, 'Creator', narrow, fieldH),
                _text(specs, 'Job Title', narrow, fieldH, display: 'Job title'),
                _text(
                  specs,
                  'Description Writers',
                  narrow,
                  fieldH,
                  display: 'Writers',
                ),
                _text(specs, 'Credit', narrow, fieldH),
                _text(specs, 'Source', narrow, fieldH),
                _text(specs, 'Copyright', narrow, fieldH),
              ],
            );
            final location = _group(
              colors: colors,
              icon: PhosphorIconsRegular.mapPin,
              title: 'Location',
              compact: compact,
              children: [
                _text(specs, 'Location', narrow, fieldH, display: 'Venue'),
                _text(specs, 'City', narrow, fieldH),
                _text(
                  specs,
                  'Province/State',
                  narrow,
                  fieldH,
                  display: 'State/Province',
                ),
                _country(specs, narrow, fieldH),
              ],
            );
            final filing = _group(
              colors: colors,
              icon: PhosphorIconsRegular.folderSimple,
              title: 'Filing',
              compact: compact,
              children: [
                _text(specs, 'MEID', narrow, fieldH),
                _text(
                  specs,
                  'Object Name',
                  narrow,
                  fieldH,
                  display: 'Object name',
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 12,
                      child: _text(specs, 'Category', narrow, fieldH),
                    ),
                    SizedBox(width: embedded ? 4 : 8),
                    Expanded(
                      flex: 18,
                      child: _supp(specs, narrow, fieldH, colors),
                    ),
                  ],
                ),
                _urgency(specs, narrow, fieldH),
              ],
            );

            // New Session / IPTC Editor v2 — 2×2 cards.
            final cards = Column(
              children: [
                if (embedded)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: story),
                        SizedBox(width: gap),
                        Expanded(child: credit),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: story),
                      SizedBox(width: gap),
                      Expanded(child: credit),
                    ],
                  ),
                SizedBox(height: gap),
                if (embedded)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: location),
                        SizedBox(width: gap),
                        Expanded(child: filing),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: location),
                      SizedBox(width: gap),
                      Expanded(child: filing),
                    ],
                  ),
              ],
            );
            fieldsBody = TapRegion(
              groupId: _legendFocusTapGroup,
              onTapOutside: (_) {
                _LegendFocusScope.maybeOf(context)?.dismissFocus();
              },
              child: cards,
            );
          }

          final hasLeading = leading != null;
          final bodyPadL = embedded
              ? 8.0
              : editIptc
                  ? (hasLeading ? 0.0 : (compact ? 12.0 : 20.0))
                  : (compact ? 12.0 : 16.0);
          final bodyPadR = embedded
              ? 8.0
              : editIptc
                  ? (compact ? 16.0 : 24.0)
                  : (compact ? 12.0 : 16.0);
          final bodyPadT = embedded
              ? 4.0
              : editIptc
                  ? (compact ? 12.0 : 20.0)
                  : (compact ? 8.0 : 14.0);
          final bodyPadB = embedded ? 4.0 : (compact ? 8.0 : 16.0);
          final body = embedded
              ? Padding(
                  padding: EdgeInsets.fromLTRB(
                    bodyPadL,
                    bodyPadT,
                    bodyPadR,
                    bodyPadB,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (applyMode != null) ...[
                        _ApplyWhenBar(
                          mode: applyMode!,
                          onChanged: onApplyModeChanged,
                          compact: true,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Expanded(child: fieldsBody),
                    ],
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    bodyPadL,
                    bodyPadT,
                    bodyPadR,
                    bodyPadB,
                  ),
                  children: [
                    if (applyMode != null) ...[
                      _ApplyWhenBar(
                        mode: applyMode!,
                        onChanged: onApplyModeChanged,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 6 : 10),
                    ],
                    fieldsBody,
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: title,
                subtitle: subtitle,
                showTemplateControls: showTemplateControls,
                templates: templates,
                selectedTemplateId: selectedTemplateId,
                onTemplateSelected: onTemplateSelected,
                onDeleteTemplate: onDeleteTemplate,
                onLoad: loadEnabled ? onLoadTemplate : null,
                // Edit IPTC: Clear all lives under Filing, not the header.
                onClear: editIptc
                    ? null
                    : (clearEnabled ? onClearTemplate : null),
                onSave: fieldsEnabled ? onSaveTemplate : null,
                loadingTemplate: loadingTemplate,
                onClose: embedded ? null : onCancel,
                compact: compact,
                captionStyleLabel: captionStyleLabel,
                wireLabels: wireLabels,
                // Startup IPTC only — omit on in-session Edit IPTC.
                showCaptionNote: false,
                templatePageHeader: templatePageHeader,
              ),
              Expanded(
                child: !hasLeading
                    ? body
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          leading!,
                          // Edit IPTC.html `.bd` column gap.
                          SizedBox(width: compact ? 16 : 24),
                          Expanded(child: body),
                        ],
                      ),
              ),
              if (!embedded)
                _Footer(
                  wireLabel: WireIptcSpecs.factoryWireLabel(wire),
                  compact: compact,
                  doneLabel: doneLabel,
                  onCancel: onCancel,
                  // Edit IPTC: Clear all is under Filing; New Session keeps footer Clear.
                  onClear: editIptc
                      ? null
                      : (clearEnabled ? onClearTemplate : null),
                  onDone: onDone,
                  editIptcLegend: editIptc,
                ),
            ],
          );
        },
        ),
      ),
    );
  }

  String _raw(String label, WireIptcFieldSpec? spec) {
    final key = spec?.storageKey ?? label;
    return IptcTemplateApplyService.lookupValue(values, key) ?? '';
  }

  String _display(String label, WireIptcFieldSpec? spec) {
    final stored = _raw(label, spec);
    if (stored.isNotEmpty &&
        !IptcTemplateApplyService.isInAppGeneratedPlaceholder(stored)) {
      if (label == 'Keywords') return _listText(stored, ', ');
      if (label == 'Personality') {
        return _listText(stored, ';', commas: false);
      }
      return stored;
    }
    final found = spec != null && _found(spec.storageKey);
    if ((label == 'Caption' || label == 'Personality') && found) {
      return IptcTemplateApplyService.inAppGeneratedPlaceholder;
    }
    return stored;
  }

  bool _found(String storageKey) {
    if (foundInFilesKeys.contains(storageKey)) return true;
    final preset = IptcTemplateApplyService.toPresetKey(storageKey);
    return foundInFilesKeys.contains(preset) ||
        foundInFilesKeys.contains(IptcTemplateApplyService.toPanelKey(preset));
  }

  bool _required(WireIptcFieldSpec? spec) =>
      spec?.level == IptcFieldLevel.required;

  /// Blank IPTC fields the active caption style still needs to build a caption.
  List<String> _captionMissingLabels() {
    final template = captionTemplate;
    if (template == null) return const [];
    return CaptionFormulaRenderer.missingCaptionIptcLabels(
      template: template,
      game: IptcTemplateApplyService.gameInfoFromPanelValues(values),
      includeCreator: true,
    );
  }

  /// Caption-structure fields — stay bright in red focus even after filled.
  List<String> _captionGroupLabels() {
    final template = captionTemplate;
    if (template == null) return const [];
    return CaptionFormulaRenderer.captionIptcLabels(
      template: template,
      includeCreator: true,
    );
  }

  bool _captionMissing(String label) {
    for (final missing in _captionMissingLabels()) {
      if (missing.toLowerCase() == label.toLowerCase()) return true;
    }
    return false;
  }

  bool _inCaptionGroup(String label) {
    for (final needed in _captionGroupLabels()) {
      if (needed.toLowerCase() == label.toLowerCase()) return true;
    }
    return false;
  }

  bool _inFilingGroup(String label, WireIptcFieldSpec? spec) {
    if (_gettyNeedsOneSupp && _suppLabels.contains(label)) return true;
    return _required(spec);
  }

  /// Caption needs (red) win over wire filing needs (yellow).
  _FieldAlert _alertFor(String label, WireIptcFieldSpec? spec) {
    if (_captionMissing(label)) return _FieldAlert.caption;
    if (_required(spec) && _blank(label, spec)) return _FieldAlert.filing;
    return _FieldAlert.none;
  }

  /// Keywords use a comma and a space. Personality uses a semicolon and no space.
  String _listText(String raw, String separator, {bool commas = true}) {
    final seen = <String>{};
    final parts = [
      for (final part in raw.split(commas ? RegExp(r'[,;]') : RegExp(';')))
        if (part.trim().isNotEmpty && seen.add(part.trim().toLowerCase()))
          part.trim(),
    ];
    return parts.join(separator);
  }

  bool _blank(String label, WireIptcFieldSpec? spec) {
    final shown = _display(label, spec).trim();
    return shown.isEmpty ||
        IptcTemplateApplyService.isInAppGeneratedPlaceholder(shown);
  }

  static const _suppLabels = ['Supp Cat 1', 'Supp Cat 2', 'Supp Cat 3'];

  bool get _gettyNeedsOneSupp => wire == WireStyle.getty;

  bool _suppBlank(Map<String, WireIptcFieldSpec> specs, String label) =>
      _blank(label, specs[label]);

  bool _allSuppBlank(Map<String, WireIptcFieldSpec> specs) =>
      _suppLabels.every((label) => _suppBlank(specs, label));

  Widget _group({
    required IptcEditorColors colors,
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool compact = false,
  }) {
    final dense = embedded;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        dense ? 6 : (compact ? 8 : 12),
        dense ? 4 : (compact ? 8 : 10),
        dense ? 6 : (compact ? 8 : 12),
        dense ? 4 : (compact ? 8 : 12),
      ),
      decoration: BoxDecoration(
        color: colors.group,
        borderRadius: BorderRadius.circular(dense ? 8 : 12),
        border: colors.workspace
            ? Border.all(color: FfTokens.nocturneLn2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, dense ? 2 : (compact ? 2 : 6)),
            child: Row(
              children: [
                PhosphorIcon(icon, size: dense ? 13 : 15, color: colors.t3),
                SizedBox(width: dense ? 6 : 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: dense ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1 * 13,
                    color: colors.t3,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  /// Edit IPTC.html `.cat` — left category label + field grid, hairline dividers.
  Widget _editIptcCat({
    required IptcEditorColors colors,
    required IconData icon,
    required String title,
    required Widget child,
    required bool compact,
    bool first = false,
  }) {
    final titleW = compact ? 84.0 : 112.0;
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 14),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: titleW,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  PhosphorIcon(
                    icon,
                    size: compact ? 14 : 15,
                    color: colors.t3,
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: compact ? 0.08 * 11 : 0.1 * 11,
                        color: colors.t3,
                        height: 16 / 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 10 : 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _text(
    Map<String, WireIptcFieldSpec> specs,
    String label,
    bool narrow,
    double fieldH, {
    String? display,
    bool labelAbove = false,
    double? fieldWidth,
  }) {
    final spec = specs[label];
    final key = spec?.storageKey ?? label;
    final value = _display(label, spec);
    final alert = _alertFor(label, spec);
    return _FieldSlot(
      label: display ?? label,
      alert: alert,
      inCaptionGroup: _inCaptionGroup(label),
      inFilingGroup: _inFilingGroup(label, spec),
      narrow: narrow,
      labelAbove: labelAbove,
      height: fieldH,
      fieldWidth: fieldWidth,
      // Edit IPTC hides the merge warning; New Session keeps it.
      labelTip: !workspacePalette &&
              (label == 'Personality' || label == 'Keywords')
          ? _listMergeTip(label)
          : null,
      child: _TextInput(
        key: ValueKey('$key-$revision'),
        tabId: label,
        value: value,
        enabled: fieldsEnabled,
        mono: _monoKeys.contains(label),
        alert: alert,
        inCaptionGroup: _inCaptionGroup(label),
        inFilingGroup: _inFilingGroup(label, spec),
        height: fieldH,
        narrow: narrow,
        maxLength: label == 'Category' || label == 'Country Code' ? 3 : null,
        center: label == 'Category',
        needsCaptionFill: () => _captionMissing(label),
        needsFilingFill: () =>
            _inFilingGroup(label, spec) && _blank(label, spec),
        normalize: label == 'Keywords'
            ? (v) => _listText(v, ', ')
            : label == 'Personality'
                ? (v) => _listText(v, ';', commas: false)
                : null,
        onChanged: (v) => onValueChanged(key, v),
      ),
    );
  }

  Widget _country(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH,
  ) {
    // Compact 3-char box sits flush beside the label (not stretched).
    const codeBoxW = 52.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _text(specs, 'Country', narrow, fieldH),
        ),
        SizedBox(width: narrow ? 6 : 8),
        _text(
          specs,
          'Country Code',
          narrow,
          fieldH,
          display: 'Country Code',
          fieldWidth: codeBoxW,
        ),
      ],
    );
  }

  Widget _supp(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH,
    IptcEditorColors colors, {
    bool labelAbove = false,
  }) {
    final labels = _suppLabels;
    final shorts = ['Supp 1', 'Supp 2', 'Supp 3'];
    // Compact boxes stay beside "Supp cats" instead of stretching the row.
    final boxW = narrow ? 56.0 : 64.0;
    final groupMissing = _gettyNeedsOneSupp && _allSuppBlank(specs);
    final alerts = [
      for (final label in labels)
        _gettyNeedsOneSupp
            ? (groupMissing ? _FieldAlert.filing : _FieldAlert.none)
            : _alertFor(label, specs[label]),
    ];
    final slotAlert = alerts.contains(_FieldAlert.caption)
        ? _FieldAlert.caption
        : (alerts.contains(_FieldAlert.filing)
            ? _FieldAlert.filing
            : _FieldAlert.none);
    return _FieldSlot(
      label: 'Supp cats',
      alert: slotAlert,
      inCaptionGroup: false,
      inFilingGroup: labels.any((l) => _inFilingGroup(l, specs[l])),
      // Compact fields already label each box (Supp 1–3). A second
      // "Supp cats" label sits on top of those and overlaps them.
      hideLabel: narrow,
      narrow: narrow,
      labelAbove: labelAbove,
      height: fieldH,
      fieldWidth: narrow ? null : (boxW * 3 + 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            SizedBox(
              width: boxW,
              child: Stack(
                children: [
                  _TextInput(
                    key: ValueKey('${labels[i]}-$revision'),
                    tabId: labels[i],
                    value: _display(labels[i], specs[labels[i]]),
                    enabled: fieldsEnabled,
                    mono: true,
                    alert: alerts[i],
                    inCaptionGroup: false,
                    inFilingGroup: _inFilingGroup(labels[i], specs[labels[i]]),
                    height: fieldH,
                    narrow: narrow,
                    center: false,
                    needsCaptionFill: () => _captionMissing(labels[i]),
                    needsFilingFill: () {
                      final label = labels[i];
                      final spec = specs[label];
                      if (_gettyNeedsOneSupp) {
                        return _allSuppBlank(specs) && _blank(label, spec);
                      }
                      return _inFilingGroup(label, spec) &&
                          _blank(label, spec);
                    },
                    onChanged: (v) => onValueChanged(
                      specs[labels[i]]?.storageKey ?? labels[i],
                      v,
                    ),
                  ),
                  if (narrow)
                    Positioned(
                      top: 3,
                      left: 10,
                      right: 4,
                      child: IgnorePointer(
                        child: Builder(
                          builder: (context) {
                            final focus = _LegendFocusScope.maybeOf(context)
                                    ?.focus ??
                                _LegendFocus.none;
                            final paint = focus == _LegendFocus.filing &&
                                    _inFilingGroup(
                                      labels[i],
                                      specs[labels[i]],
                                    )
                                ? _FieldAlert.filing
                                : alerts[i];
                            return Text(
                              shorts[i].toUpperCase(),
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: paint != _FieldAlert.none
                                    ? _alertColor(paint)
                                    : colors.t3,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _urgency(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH, {
    bool labelAbove = false,
  }) {
    final spec = specs['Urgency'];
    final key = spec?.storageKey ?? 'Urgency';
    final raw = _raw('Urgency', spec).trim();
    final value = raw.isEmpty
        ? '5'
        : IptcTemplateApplyService.normalizeUrgencyValue(raw);
    return _FieldSlot(
      label: 'Urgency',
      alert: _FieldAlert.none,
      inCaptionGroup: false,
      inFilingGroup: _inFilingGroup('Urgency', spec),
      narrow: narrow,
      labelAbove: labelAbove,
      height: fieldH,
      child: _UrgencyInput(
        value: value,
        enabled: fieldsEnabled,
        height: fieldH,
        narrow: narrow,
        onChanged: (v) => onValueChanged(key, v),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.showTemplateControls,
    required this.templates,
    required this.selectedTemplateId,
    required this.onTemplateSelected,
    required this.onLoad,
    required this.onClear,
    required this.onSave,
    required this.loadingTemplate,
    required this.onClose,
    required this.compact,
    this.onDeleteTemplate,
    this.captionStyleLabel,
    this.wireLabels = const {},
    this.showCaptionNote = false,
    this.templatePageHeader = false,
  });

  final String title;
  final String? subtitle;
  final bool showTemplateControls;
  final List<IptcTemplateCatalogEntry> templates;
  final String selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry> onTemplateSelected;
  final ValueChanged<IptcTemplateCatalogEntry>? onDeleteTemplate;
  final VoidCallback? onLoad;
  final VoidCallback? onClear;
  final VoidCallback? onSave;
  final bool loadingTemplate;
  final VoidCallback? onClose;
  final bool compact;
  final String? captionStyleLabel;
  final Map<WireStyle, String> wireLabels;
  final bool showCaptionNote;
  final bool templatePageHeader;

  static const _captionNoteText =
      'Caption isn’t in this template — existing captions stay on your '
      'photos and are written later when you caption in the session.';

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final styleLabel = captionStyleLabel?.trim() ?? '';
    final close = onClose;
    final captionNote = showCaptionNote
        ? Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.info,
                    size: 14,
                    color: colors.t3,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _captionNoteText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 12,
                        height: 1.25,
                        color: colors.t2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;
    final templateChrome = templatePageHeader && !showTemplateControls;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 6 : 12,
        compact ? 8 : 12,
        compact ? 6 : 12,
      ),
      decoration: BoxDecoration(
        color: templateChrome ? FfTokens.nocturneAccentRow : null,
        border: Border(
          bottom: BorderSide(
            color: templateChrome
                ? FfTokens.nocturneAccentEdge
                : colors.line,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!showTemplateControls) ...[
            if (templateChrome) ...[
              PhosphorIcon(
                PhosphorIconsRegular.notebook,
                size: 14,
                color: FfTokens.nocturneAc,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: templateChrome
                    ? 11
                    : (compact ? 13 : 15),
                fontWeight: FontWeight.w700,
                letterSpacing: templateChrome ? 0.6 : 0,
                color: templateChrome ? FfTokens.nocturneAc : colors.tx,
              ),
            ),
            if (captionNote != null)
              captionNote
            else if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: compact ? 12 : 13,
                    color: colors.t3,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (onClear != null) _ClearLink(onTap: onClear),
            if (close != null)
              _IconButton(
                icon: PhosphorIconsRegular.x,
                tooltip: 'Close',
                onTap: close,
              ),
          ] else ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Caption Style',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.t3,
                    ),
                  ),
                  TextSpan(
                    text: ' — ',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      color: colors.t3,
                    ),
                  ),
                  TextSpan(
                    text: styleLabel.isEmpty ? title : styleLabel,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.tx,
                    ),
                  ),
                ],
              ),
            ),
            if (captionNote != null)
              captionNote
            else
              const Spacer(),
            _LinkButton(
              icon: PhosphorIconsRegular.uploadSimple,
              label: loadingTemplate
                  ? 'Importing…'
                  : 'Import from JPG, Getty TXT, or XMP',
              tooltip: 'Import from JPG, Getty TXT, or XMP',
              onTap: onLoad,
              fontSize: 11,
              iconSize: 14,
            ),
            const SizedBox(width: 8),
            _TemplateDropdown(
              entries: templates,
              selectedTemplateId: selectedTemplateId,
              onSelected: onTemplateSelected,
              onDelete: onDeleteTemplate,
              captionStyleLabel: styleLabel,
              wireLabels: wireLabels,
            ),
            _LinkButton(
              icon: PhosphorIconsRegular.floppyDisk,
              label: 'Save template',
              tooltip: 'Save IPTC template',
              onTap: onSave,
              compact: compact,
            ),
            if (close != null)
              _IconButton(
                icon: PhosphorIconsRegular.x,
                tooltip: 'Close',
                onTap: close,
              ),
          ],
        ],
      ),
    );
  }
}

/// Apply bar: On load on/off only.
class _ApplyWhenBar extends StatelessWidget {
  const _ApplyWhenBar({
    required this.mode,
    required this.onChanged,
    required this.compact,
  });

  final IptcApplyMode mode;
  final ValueChanged<IptcApplyMode>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final onLoad = mode.appliesOnLoad;
    return Row(
      children: [
        Text(
          'APPLY',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1 * 13,
            color: colors.t3,
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: colors.group,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onChanged == null
                ? null
                : () => onChanged!(
                      onLoad ? IptcApplyMode.none : IptcApplyMode.onImport,
                    ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color:
                          onLoad ? FfTokens.sessionOn : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: onLoad
                          ? null
                          : Border.all(color: FfTokens.sessionLn2),
                    ),
                    child: onLoad
                        ? const PhosphorIcon(
                            PhosphorIconsBold.check,
                            size: 11,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'On load',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onLoad ? colors.tx : colors.t2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              onLoad
                  ? 'Written to every photo as soon as the folder opens'
                  : 'Don’t write IPTC when the folder opens',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: colors.t3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TemplateDropdown extends StatelessWidget {
  const _TemplateDropdown({
    required this.entries,
    required this.selectedTemplateId,
    required this.onSelected,
    this.onDelete,
    this.captionStyleLabel = '',
    this.wireLabels = const {},
  });

  final List<IptcTemplateCatalogEntry> entries;
  final String selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry> onSelected;
  final ValueChanged<IptcTemplateCatalogEntry>? onDelete;
  final String captionStyleLabel;
  final Map<WireStyle, String> wireLabels;

  String _wireName(WireStyle wire) =>
      WireIptcSpecs.displayWireLabel(wire, wireLabels[wire]);

  String _selectedLabel() {
    for (final e in entries) {
      if (e.id == selectedTemplateId) return e.displayName;
    }
    return 'Nothing saved yet';
  }

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final wires = <WireStyle>[
      for (final w in WireIptcSpecs.builtInWires)
        if (entries.any((e) => e.wireStyle == w)) w,
    ];
    return PopupMenuButton<String>(
      tooltip: 'Saved IPTC templates',
      offset: const Offset(0, 36),
      color: colors.group,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.line),
      ),
      onSelected: (id) {
        for (final entry in entries) {
          if (entry.id == id) {
            onSelected(entry);
            return;
          }
        }
      },
      itemBuilder: (context) {
        if (entries.isEmpty) {
          return [
            PopupMenuItem<String>(
              enabled: false,
              height: 36,
              child: Text(
                'Nothing saved yet',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.t3,
                ),
              ),
            ),
          ];
        }
        final items = <PopupMenuEntry<String>>[];
        for (var i = 0; i < wires.length; i++) {
          final wire = wires[i];
          if (i > 0) items.add(const PopupMenuDivider(height: 8));
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text(
                _wireName(wire),
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: colors.t3,
                ),
              ),
            ),
          );
          for (final entry in entries.where((e) => e.wireStyle == wire)) {
            final selected = entry.id == selectedTemplateId;
            items.add(
              PopupMenuItem<String>(
                value: entry.id,
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: colors.tx,
                        ),
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: PhosphorIcon(
                          PhosphorIconsBold.check,
                          size: 14,
                          color: colors.tx,
                        ),
                      ),
                    if (onDelete != null)
                      Tooltip(
                        message: 'Delete template',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            // Close menu without selecting this template.
                            Navigator.pop(context);
                            onDelete!(entry);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: PhosphorIcon(
                              PhosphorIconsRegular.trash,
                              size: 14,
                              color: colors.t3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
        }
        return items;
      },
      child: Container(
        width: 260,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: entries.isEmpty ? colors.t3 : colors.tx,
                ),
              ),
            ),
            PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 12,
              color: colors.t3,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.compact = false,
    this.fontSize = 13,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool compact;
  final double fontSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: colors.t2,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: iconSize, color: colors.t2),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClearLink extends StatefulWidget {
  const _ClearLink({required this.onTap, this.compact = false});
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_ClearLink> createState() => _ClearLinkState();
}

class _ClearLinkState extends State<_ClearLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final enabled = widget.onTap != null;
    final hot = enabled && _hover;
    final color = hot ? const Color(0xFFF07167) : colors.t2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: 'Clear all',
        child: TextButton(
          onPressed: widget.onTap,
          style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor:
                hot ? const Color(0x1AF07167) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.trash,
                size: 16,
                color: color,
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 6),
                Text(
                  'Clear all',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: PhosphorIcon(icon, size: 17, color: colors.t2),
        ),
      ),
    );
  }
}

class _CaptionOmittedNote extends StatelessWidget {
  const _CaptionOmittedNote({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        compact ? 8 : 10,
        14,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: colors.group,
        borderRadius: BorderRadius.circular(12),
        border: colors.workspace
            ? Border.all(color: FfTokens.nocturneLn2)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(
            PhosphorIconsRegular.info,
            size: 16,
            color: colors.t3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Caption isn’t in this template — existing captions stay on your '
              'photos and are written later when you caption in the session.',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                height: 1.35,
                color: colors.t2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldSlot extends StatelessWidget {
  const _FieldSlot({
    required this.label,
    required this.alert,
    required this.inCaptionGroup,
    required this.inFilingGroup,
    required this.narrow,
    required this.height,
    required this.child,
    this.hideLabel = false,
    this.labelAbove = false,
    this.labelTip,
    this.fieldWidth,
  });

  final String label;
  final _FieldAlert alert;
  /// Stays bright in red focus mode even after the field is filled.
  final bool inCaptionGroup;
  /// Stays bright in yellow focus mode even after the field is filled.
  final bool inFilingGroup;
  final bool narrow;
  final double height;
  final Widget child;
  final bool hideLabel;
  /// Edit IPTC.html — label stacked above the input (comfortable size).
  final bool labelAbove;
  /// Tooltip shown via a small warning icon beside the label.
  final String? labelTip;
  /// When set, input stays this wide beside the label instead of stretching.
  final double? fieldWidth;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final legendFocus =
        _LegendFocusScope.maybeOf(context)?.focus ?? _LegendFocus.none;
    final dimOthers = (legendFocus == _LegendFocus.caption && !inCaptionGroup) ||
        (legendFocus == _LegendFocus.filing && !inFilingGroup);
    // In yellow/red focus mode, paint every field in that group — filled too.
    final paintAlert = legendFocus == _LegendFocus.filing && inFilingGroup
        ? _FieldAlert.filing
        : legendFocus == _LegendFocus.caption && inCaptionGroup
            ? _FieldAlert.caption
            : alert;
    final alertOn = paintAlert != _FieldAlert.none;
    final floatLabel = narrow || (labelAbove && narrow);
    final stacked = labelAbove && !narrow;
    final labelColor = alertOn
        ? _alertColor(paintAlert)
        : (floatLabel || stacked ? colors.t2 : colors.t2);
    final tip = labelTip;
    final tipIcon = tip == null
        ? null
        : Tooltip(
            message: tip,
            waitDuration: const Duration(milliseconds: 280),
            child: Padding(
              padding: EdgeInsets.only(left: floatLabel ? 3 : 4),
              child: PhosphorIcon(
                PhosphorIconsRegular.warning,
                size: floatLabel ? 11 : 13,
                color: colors.t3,
              ),
            ),
          );
    // Edit IPTC.html uses a trailing status dot after the label text.
    final labelText = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          if (alertOn)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: floatLabel ? 5 : 6,
                  height: floatLabel ? 5 : 6,
                  decoration: BoxDecoration(
                    color: _alertColor(paintAlert),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: floatLabel ? 10 : (stacked ? 12 : 12),
        fontWeight: floatLabel
            ? FontWeight.w600
            : (stacked ? FontWeight.w500 : FontWeight.w400),
        letterSpacing: floatLabel ? 0.4 : 0,
        height: stacked ? 16 / 12 : null,
        color: floatLabel ? colors.t3 : labelColor,
      ),
    );
    final labelRow = Row(
      children: [
        Flexible(child: labelText),
        if (tipIcon != null) tipIcon,
      ],
    );

    final fixedW = fieldWidth;
    final Widget fieldChild = fixedW == null
        ? child
        : Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: fixedW, child: child),
          );

    final Widget slot;
    if (stacked) {
      slot = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16, child: labelRow),
          const SizedBox(height: 5),
          SizedBox(
            height: height,
            width: fixedW,
            child: fieldChild,
          ),
        ],
      );
    } else if (narrow) {
      // Fixed height — never use Positioned.fill in a scroll view (unbounded).
      slot = Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: height,
          width: fixedW,
          child: Stack(
            children: [
              Positioned.fill(child: fieldChild),
              if (!hideLabel)
                Positioned(
                  top: 3,
                  left: 8,
                  right: 8,
                  child: tipIcon == null
                      ? IgnorePointer(child: labelText)
                      : Row(
                          children: [
                            Flexible(
                              child: IgnorePointer(child: labelText),
                            ),
                            tipIcon,
                          ],
                        ),
                ),
            ],
          ),
        ),
      );
    } else {
      slot = Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisSize:
                fixedW == null ? MainAxisSize.max : MainAxisSize.min,
            children: [
              SizedBox(width: 118, child: labelRow),
              const SizedBox(width: 10),
              if (fixedW != null)
                SizedBox(width: fixedW, child: child)
              else
                Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: dimOthers ? 0.2 : 1,
      child: slot,
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.value,
    required this.enabled,
    required this.alert,
    required this.height,
    required this.narrow,
    required this.onChanged,
    this.tabId,
    this.needsCaptionFill,
    this.needsFilingFill,
    this.inCaptionGroup = false,
    this.inFilingGroup = false,
    this.mono = false,
    this.center = false,
    this.maxLength,
    this.normalize,
  });

  final String value;
  final bool enabled;
  final _FieldAlert alert;
  final double height;
  final bool narrow;
  final ValueChanged<String> onChanged;
  final String? tabId;
  final bool Function()? needsCaptionFill;
  final bool Function()? needsFilingFill;
  final bool inCaptionGroup;
  final bool inFilingGroup;
  final bool mono;
  final bool center;
  final int? maxLength;
  final String Function(String value)? normalize;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _hover = false;
  _IptcTabField? _tabField;
  _LegendFocusScope? _tabScope;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode(onKeyEvent: _onKeyEvent)..addListener(_onFocus);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final scope = _tabScope ?? _LegendFocusScope.maybeOf(context);
    if (scope == null || scope.focus == _LegendFocus.none) {
      return KeyEventResult.ignored;
    }
    final reverse = HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.shiftLeft,
    ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    final moved = scope.focusNextNeeded(from: node, reverse: reverse);
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      final normalize = widget.normalize;
      if (normalize != null) {
        final next = normalize(_controller.text);
        if (next != _controller.text) _controller.text = next;
        if (next != widget.value) widget.onChanged(next);
      }
    }
    setState(() {});
  }

  void _syncTabRegistration() {
    final scope = _LegendFocusScope.maybeOf(context);
    final id = widget.tabId;
    if (scope == null || id == null || !widget.enabled) {
      if (_tabField != null) {
        _tabScope?.unregisterTabField(_focus);
        _tabField = null;
        _tabScope = null;
      }
      return;
    }
    final field = _tabField;
    if (field != null && identical(_tabScope, scope)) {
      field.needsCaptionFill =
          widget.needsCaptionFill ?? field.needsCaptionFill;
      field.needsFilingFill = widget.needsFilingFill ?? field.needsFilingFill;
      return;
    }
    _tabScope?.unregisterTabField(_focus);
    final next = _IptcTabField(
      id: id,
      node: _focus,
      needsCaptionFill: widget.needsCaptionFill ?? () => false,
      needsFilingFill: widget.needsFilingFill ?? () => false,
    );
    scope.registerTabField(next);
    _tabField = next;
    _tabScope = scope;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTabRegistration();
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabRegistration();
    if (_focus.hasFocus) return;
    if (_controller.text != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _tabScope?.unregisterTabField(_focus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  _FieldAlert _paintAlert(BuildContext context) {
    final focus =
        _LegendFocusScope.maybeOf(context)?.focus ?? _LegendFocus.none;
    if (focus == _LegendFocus.filing && widget.inFilingGroup) {
      return _FieldAlert.filing;
    }
    if (focus == _LegendFocus.caption && widget.inCaptionGroup) {
      return _FieldAlert.caption;
    }
    return widget.alert;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final focused = _focus.hasFocus;
    final paintAlert = _paintAlert(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hover && !focused ? colors.hover : colors.field,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: focused
                ? colors.focus
                : paintAlert != _FieldAlert.none
                    ? _alertLine(paintAlert)
                    : colors.workspace
                        ? FfTokens.nocturneLn
                        : Colors.transparent,
          ),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          maxLength: widget.maxLength,
          textAlign: widget.center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontFamily: widget.mono ? FfTokens.monoFamily : FfTokens.fontFamily,
            fontSize: widget.mono ? 12 : 13,
            color: colors.tx,
          ),
          cursorColor: colors.focus,
          inputFormatters: widget.maxLength == null
              ? null
              : [LengthLimitingTextInputFormatter(widget.maxLength)],
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              widget.center ? 6 : 10,
              widget.narrow ? 14 : 0,
              widget.center ? 6 : 10,
              0,
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}


class _UrgencyInput extends StatefulWidget {
  const _UrgencyInput({
    required this.value,
    required this.enabled,
    required this.height,
    required this.narrow,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final double height;
  final bool narrow;
  final ValueChanged<String> onChanged;

  @override
  State<_UrgencyInput> createState() => _UrgencyInputState();
}

class _UrgencyInputState extends State<_UrgencyInput> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: widget.height,
        padding: EdgeInsets.fromLTRB(10, widget.narrow ? 12 : 0, 6, 0),
        decoration: BoxDecoration(
          color: _hover ? colors.hover : colors.field,
          borderRadius: BorderRadius.circular(7),
          border: colors.workspace
              ? Border.all(color: FfTokens.nocturneLn)
              : null,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: IptcTemplateApplyService.urgencyValues.contains(widget.value)
                ? widget.value
                : '5',
            isExpanded: true,
            isDense: true,
            dropdownColor: colors.group,
            icon: PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 12,
              color: colors.t3,
            ),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              color: colors.tx,
            ),
            items: [
              for (final level in IptcTemplateApplyService.urgencyValues)
                DropdownMenuItem(
                  value: level,
                  child: Text(
                    '$level · ${IptcTemplateApplyService.urgencyMenuLabel(level)}',
                  ),
                ),
            ],
            onChanged: widget.enabled
                ? (v) {
                    if (v != null) widget.onChanged(v);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.wireLabel,
    required this.compact,
    required this.doneLabel,
    required this.onCancel,
    required this.onDone,
    this.onClear,
    this.editIptcLegend = false,
  });

  final String wireLabel;
  final bool compact;
  final String doneLabel;
  final VoidCallback onCancel;
  final VoidCallback? onClear;
  final VoidCallback onDone;
  /// Edit IPTC.html legend copy (“Required for captions” / “Needed for Getty”).
  final bool editIptcLegend;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final focus = _LegendFocusScope.maybeOf(context);
    final filingName = wireLabel.trim().isEmpty ? 'wire' : wireLabel;
    final captionLegend = editIptcLegend
        ? 'Required for captions'
        : 'Red - Required to build captions';
    final filingLegend = editIptcLegend
        ? 'Needed for Getty'
        : 'Grey - Needed for filing to $filingName';
    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 12, 16, compact ? 8 : 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TapRegion(
              groupId: _legendFocusTapGroup,
              child: Wrap(
                spacing: editIptcLegend ? 16 : 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegendButton(
                    color: _captionWarn,
                    label: captionLegend,
                    selected: focus?.focus == _LegendFocus.caption,
                    onTap: focus?.onToggleCaption,
                    tooltipOff: 'Highlight fields required to build captions',
                  ),
                  _LegendButton(
                    color: _filingWarn,
                    label: filingLegend,
                    selected: focus?.focus == _LegendFocus.filing,
                    onTap: focus?.onToggleFiling,
                    tooltipOff:
                        'Highlight fields needed for filing to $filingName',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: colors.t2,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: colors.t2,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(
                'Clear',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          if (colors.workspace)
            TealActionButton(
              label: doneLabel,
              onPressed: onDone,
              icon: const PhosphorIcon(
                PhosphorIconsBold.check,
                size: 14,
                color: Colors.white,
              ),
            )
          else
            _DoneButton(label: doneLabel, onPressed: onDone),
        ],
      ),
    );
  }
}

class _LegendButton extends StatefulWidget {
  const _LegendButton({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tooltipOff,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String tooltipOff;

  @override
  State<_LegendButton> createState() => _LegendButtonState();
}

class _LegendButtonState extends State<_LegendButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final selected = widget.selected;
    final hover = _hover;
    final fill = selected
        ? widget.color.withValues(alpha: 0.18)
        : hover
            ? widget.color.withValues(alpha: 0.10)
            : colors.field;
    final border = selected || hover
        ? widget.color.withValues(alpha: selected ? 0.85 : 0.55)
        : colors.line;
    final labelColor = selected || hover ? widget.color : colors.t2;

    return Tooltip(
      message: selected ? 'Show all fields' : widget.tooltipOff,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(9),
            mouseCursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          height: 38,
          padding: const EdgeInsets.fromLTRB(16, 0, 18, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF243848),
                Color(0xFF15242E),
                Color(0xFF0E181F),
              ],
            ),
            border: Border.all(color: const Color(0xF24A7A96)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x404A7A96),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(
                PhosphorIconsBold.check,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
