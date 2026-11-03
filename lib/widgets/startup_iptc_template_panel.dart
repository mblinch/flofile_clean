import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/iptc_template_apply_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'ff_dropdown.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Light by default. Caption V2 wraps the panel in the session chrome.
class IptcPanelStyle extends InheritedWidget {
  const IptcPanelStyle({
    required this.session,
    required super.child,
  });

  final bool session;

  static bool sessionOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<IptcPanelStyle>()
            ?.session ??
        false;
  }

  @override
  bool updateShouldNotify(IptcPanelStyle oldWidget) => session != oldWidget.session;
}

/// Startup right column: compact IPTC checklist filled from folder files.
class StartupIptcTemplatePanel extends StatelessWidget {
  const StartupIptcTemplatePanel({
    super.key,
    required this.selectedWire,
    required this.wireLabels,
    required this.values,
    this.foundInFilesKeys = const {},
    this.onValueChanged,
    this.onWireSelected,
    this.isLoading = false,
    required this.iptcApplyMode,
    this.onIptcApplyModeChanged,
    this.onLoadTemplate,
    this.onClearTemplate,
    this.onLoadOriginalValues,
    this.isLoadTemplateLoading = false,
    this.isLoadTemplateDisabled = false,
    this.isLoadOriginalValuesDisabled = false,
    this.templateRevision = 0,
    this.fieldsOnly = false,
    this.visibleTemplates = const [],
    this.selectedTemplateId,
    this.onTemplateSelected,
    this.sessionStyle = false,
    this.highlightStorageKey,
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final List<IptcTemplateCatalogEntry> visibleTemplates;
  final String? selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry>? onTemplateSelected;
  final bool sessionStyle;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;

  /// When set, that IPTC row is accent-highlighted (structure chip source).
  final String? highlightStorageKey;
  final void Function(String storageKey, String value)? onValueChanged;
  final ValueChanged<WireStyle>? onWireSelected;
  final bool isLoading;
  final IptcApplyMode iptcApplyMode;
  final ValueChanged<IptcApplyMode>? onIptcApplyModeChanged;
  final VoidCallback? onLoadTemplate;
  final VoidCallback? onClearTemplate;
  final VoidCallback? onLoadOriginalValues;
  final bool isLoadTemplateLoading;
  final bool isLoadTemplateDisabled;
  final bool isLoadOriginalValuesDisabled;
  final int templateRevision;

  /// When true, shows only the scrollable IPTC field grid (no wire dropdown,
  /// apply mode, or template action buttons). Used by [MetadataPopupDialog].
  final bool fieldsOnly;

  /// One height for every row so the grid stays even; "Found in files" fits on line 2.
  static const double _rowHeight = 34;
  static const double _twoLineRowHeight = 58;
  static const double _rowGap = 2;

  /// Wide enough for longest panel labels on one line.
  static const double _labelWidth = 106;

  /// Same as the main caption editor ([CaptionFieldsWidget] caption field).
  static const TextStyle _fieldValueStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    height: 1.25,
    color: Colors.black87,
  );

  static const TextStyle _fieldValueDisabledStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    height: 1.25,
    color: Color(0xFFB0B0B0),
  );

  static const Color _fieldDisabledFill = Color(0xFFF3F3F3);
  static const Color _fieldDisabledBorder = Color(0xFFE0E0E0);

  static const String _captionLabel = 'Caption';
  static const String _keywordsLabel = 'Keywords';
  static const String _headlineLabel = 'Headline';
  static const String _specialInstructionsLabel = 'Special Instructions';
  static const String _personalityLabel = 'Personality';
  static const String _urgencyLabel = 'Urgency';

  static const Set<String> _inAppGeneratedLabels = {
    _captionLabel,
    _personalityLabel,
  };

  static String _labelOnOneLine(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length == 2) {
      return '${parts[0]}\u00A0${parts[1]}';
    }
    return label;
  }

  static bool _isFoundInFiles(String storageKey, Set<String> foundKeys) {
    if (foundKeys.contains(storageKey)) return true;
    final presetKey = IptcTemplateApplyService.toPresetKey(storageKey);
    return foundKeys.contains(presetKey) ||
        foundKeys.contains(IptcTemplateApplyService.toPanelKey(presetKey));
  }

  bool _isHighlighted(String storageKey) {
    final want = highlightStorageKey?.trim() ?? '';
    if (want.isEmpty) return false;
    if (storageKey == want) return true;
    final presetKey = IptcTemplateApplyService.toPresetKey(storageKey);
    return want == presetKey ||
        want == IptcTemplateApplyService.toPanelKey(presetKey);
  }

  static String? _displayValueForField({
    required String label,
    required String? storedValue,
    required bool showFoundInFiles,
  }) {
    final trimmed = storedValue?.trim() ?? '';
    if (trimmed.isNotEmpty &&
        !IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
      return trimmed;
    }
    if (_inAppGeneratedLabels.contains(label) && showFoundInFiles) {
      return IptcTemplateApplyService.inAppGeneratedPlaceholder;
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  String _fieldKey(String storageKey) => '$storageKey-$templateRevision';

  bool get _fieldsInactive =>
      !fieldsOnly && iptcApplyMode == IptcApplyMode.none;

  Map<String, String> get _displayValues =>
      _fieldsInactive ? const {} : values;

  Set<String> get _displayFoundInFilesKeys =>
      _fieldsInactive ? const {} : foundInFilesKeys;

  @override
  Widget build(BuildContext context) {
    final specs = WireIptcSpecs.fieldsForPanel(selectedWire);
    if (sessionStyle) return _buildSessionEditorLayout(specs);
    WireIptcFieldSpec? captionSpec;
    WireIptcFieldSpec? keywordsSpec;
    WireIptcFieldSpec? headlineSpec;
    WireIptcFieldSpec? specialInstructionsSpec;
    final remaining = <WireIptcFieldSpec>[];
    for (final spec in specs) {
      if (spec.label == _captionLabel) {
        captionSpec = spec;
      } else if (spec.label == _keywordsLabel) {
        keywordsSpec = spec;
      } else if (spec.label == _headlineLabel) {
        headlineSpec = spec;
      } else if (spec.label == _specialInstructionsLabel) {
        specialInstructionsSpec = spec;
      } else {
        remaining.add(spec);
      }
    }
    final mid = (remaining.length / 2).ceil();
    final left = remaining.sublist(0, mid);
    final right = remaining.sublist(mid);

    return IptcPanelStyle(
      session: sessionStyle,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fieldsOnly) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: _WireTemplateDropdown(
                  selectedWire: selectedWire,
                  wireLabels: wireLabels,
                  templates: visibleTemplates,
                  selectedTemplateId: selectedTemplateId,
                  onTemplateSelected: onTemplateSelected,
                  onWireSelected: onWireSelected,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Write IPTC Template:',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: sessionStyle ? 12 : 9,
                          fontVariations: const [FontVariation('wght', 600)],
                          color: sessionStyle
                              ? FfTokens.sessionT2
                              : const Color(0xFF333333),
                        ),
                      ),
                    ),
                    const IptcApplyModeHelpButton(),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 200,
                      child: IptcApplyModeSelector(
                        mode: iptcApplyMode,
                        onChanged: onIptcApplyModeChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isLoading) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 6),
                Text(
                  'Reading IPTC from folder…',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontVariations: [FontVariation('wght', 500)],
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ],
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (captionSpec != null) ...[
                  SizedBox(
                    height: _twoLineRowHeight,
                    child: _EditableFieldRow(
                      key: ValueKey(_fieldKey(captionSpec.storageKey)),
                      spec: captionSpec,
                      valueMaxLines: 2,
                      enabled: !_fieldsInactive,
                      highlighted: _isHighlighted(captionSpec.storageKey),
                      value: _displayValueForField(
                        label: captionSpec.label,
                        storedValue: IptcTemplateApplyService.lookupValue(
                          _displayValues,
                          captionSpec.storageKey,
                        ),
                        showFoundInFiles: _isFoundInFiles(
                          captionSpec.storageKey,
                          _displayFoundInFilesKeys,
                        ),
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        captionSpec.storageKey,
                        _displayFoundInFilesKeys,
                      ),
                      onValueChanged: onValueChanged,
                    ),
                  ),
                  const SizedBox(height: _rowGap),
                ],
                if (headlineSpec != null) ...[
                  SizedBox(
                    height: _rowHeight,
                    child: _EditableFieldRow(
                      key: ValueKey(_fieldKey(headlineSpec.storageKey)),
                      spec: headlineSpec,
                      enabled: !_fieldsInactive,
                      highlighted: _isHighlighted(headlineSpec.storageKey),
                      value: IptcTemplateApplyService.lookupValue(
                        _displayValues,
                        headlineSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        headlineSpec.storageKey,
                        _displayFoundInFilesKeys,
                      ),
                      onValueChanged: onValueChanged,
                    ),
                  ),
                  const SizedBox(height: _rowGap),
                ],
                if (keywordsSpec != null) ...[
                  SizedBox(
                    height: _twoLineRowHeight,
                    child: _EditableFieldRow(
                      key: ValueKey(_fieldKey(keywordsSpec.storageKey)),
                      spec: keywordsSpec,
                      valueMaxLines: 2,
                      enabled: !_fieldsInactive,
                      highlighted: _isHighlighted(keywordsSpec.storageKey),
                      value: IptcTemplateApplyService.lookupValue(
                        _displayValues,
                        keywordsSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        keywordsSpec.storageKey,
                        _displayFoundInFilesKeys,
                      ),
                      onValueChanged: onValueChanged,
                    ),
                  ),
                  const SizedBox(height: _rowGap),
                ],
                if (specialInstructionsSpec != null) ...[
                  SizedBox(
                    height: _twoLineRowHeight,
                    child: _EditableFieldRow(
                      key: ValueKey(
                          _fieldKey(specialInstructionsSpec.storageKey)),
                      spec: specialInstructionsSpec,
                      valueMaxLines: 2,
                      enabled: !_fieldsInactive,
                      highlighted:
                          _isHighlighted(specialInstructionsSpec.storageKey),
                      value: IptcTemplateApplyService.lookupValue(
                        _displayValues,
                        specialInstructionsSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        specialInstructionsSpec.storageKey,
                        _displayFoundInFilesKeys,
                      ),
                      onValueChanged: onValueChanged,
                    ),
                  ),
                  const SizedBox(height: _rowGap),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FieldColumn(
                        specs: left,
                        values: _displayValues,
                        foundInFilesKeys: _displayFoundInFilesKeys,
                        highlightStorageKey: highlightStorageKey,
                        templateRevision: templateRevision,
                        fieldsEnabled: !_fieldsInactive,
                        onValueChanged: onValueChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FieldColumn(
                        specs: right,
                        values: _displayValues,
                        foundInFilesKeys: _displayFoundInFilesKeys,
                        highlightStorageKey: highlightStorageKey,
                        templateRevision: templateRevision,
                        fieldsEnabled: !_fieldsInactive,
                        onValueChanged: onValueChanged,
                      ),
                    ),
                  ],
                ),
                if (onLoadTemplate != null ||
                    onClearTemplate != null ||
                    onLoadOriginalValues != null) ...[
                  if (!fieldsOnly) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (onLoadTemplate != null)
                          SizedBox(
                            width: 168,
                            child: ElevatedGreyButton(
                              label: isLoadTemplateLoading
                                  ? 'Loading template…'
                                  : 'Load template…',
                              fontSize: 10,
                              icon: PhosphorIconsRegular.uploadSimple,
                              isTealGradient: true,
                              fullWidth: true,
                              onPressed: _fieldsInactive ||
                                      isLoadTemplateLoading ||
                                      isLoadTemplateDisabled
                                  ? null
                                  : onLoadTemplate,
                            ),
                          ),
                        if (onLoadOriginalValues != null)
                          SizedBox(
                            width: 178,
                            child: ElevatedGreyButton(
                              label: 'Load original values',
                              fontSize: 10,
                              icon: PhosphorIconsRegular.arrowCounterClockwise,
                              fullWidth: true,
                              onPressed: _fieldsInactive ||
                                      isLoadTemplateLoading ||
                                      isLoadTemplateDisabled ||
                                      isLoadOriginalValuesDisabled
                                  ? null
                                  : onLoadOriginalValues,
                            ),
                          ),
                        if (onClearTemplate != null)
                          SizedBox(
                            width: 104,
                            child: ElevatedGreyButton(
                              label: 'Clear all',
                              fontSize: 10,
                              icon: PhosphorIconsRegular.trash,
                              isDanger: true,
                              fullWidth: true,
                              onPressed: _fieldsInactive ||
                                      isLoadTemplateLoading ||
                                      isLoadTemplateDisabled
                                  ? null
                                  : onClearTemplate,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildSessionEditorLayout(List<WireIptcFieldSpec> specs) {
    const tokens = FfTokens.dark;
    return IptcPanelStyle(
      session: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!fieldsOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 10, 0),
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: _WireTemplateDropdown(
                      selectedWire: selectedWire,
                      wireLabels: wireLabels,
                      templates: visibleTemplates,
                      selectedTemplateId: selectedTemplateId,
                      onTemplateSelected: onTemplateSelected,
                      onWireSelected: onWireSelected,
                      compact: true,
                    ),
                  ),
                  if (onLoadTemplate != null) ...[
                    const SizedBox(width: 4),
                    _sessionTopAction(
                      label: isLoadTemplateLoading ? 'Loading…' : 'Load template',
                      icon: PhosphorIconsRegular.uploadSimple,
                      enabled: !_fieldsInactive &&
                          !isLoadTemplateLoading &&
                          !isLoadTemplateDisabled,
                      onPressed: onLoadTemplate,
                      tokens: tokens,
                    ),
                    Text(
                      '(load from XMP, Getty TXT, or JPG)',
                      style: tokens.metaStyle.copyWith(color: tokens.textTertiary),
                    ),
                  ],
                  if (onClearTemplate != null)
                    _sessionTopAction(
                      label: 'Clear all',
                      icon: PhosphorIconsRegular.trash,
                      enabled: !_fieldsInactive && !isLoadTemplateLoading,
                      onPressed: onClearTemplate,
                      tokens: tokens,
                      danger: true,
                    ),
                ],
              ),
            ),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Reading IPTC from folder…',
                    style: tokens.metaStyle,
                  ),
                ],
              ),
            ),
          Expanded(child: _sessionFieldList(specs)),
        ],
      ),
    );
  }

  Widget _sessionTopAction({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onPressed,
    required FfTokens tokens,
    bool danger = false,
  }) {
    final color = !enabled
        ? tokens.textTertiary
        : danger
            ? FfTokens.danger
            : tokens.textSecondary;
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: PhosphorIcon(icon, size: 14, color: color),
      label: Text(label, style: tokens.labelStyle.copyWith(color: color)),
    );
  }

  Widget _sessionFieldList(List<WireIptcFieldSpec> specs) {
    WireIptcFieldSpec? caption;
    WireIptcFieldSpec? keywords;
    WireIptcFieldSpec? specialInstructions;
    final rest = <WireIptcFieldSpec>[];
    for (final spec in specs) {
      if (spec.label == _captionLabel && caption == null) {
        caption = spec;
      } else if (spec.label == 'Camera time' &&
          highlightStorageKey != 'Camera time') {
        // Hide camera time in the dense session grid unless a structure
        // date chip opened this panel to show that source.
        continue;
      } else if (spec.label == _keywordsLabel && keywords == null) {
        keywords = spec;
      } else if (spec.label == _specialInstructionsLabel &&
          specialInstructions == null) {
        specialInstructions = spec;
      } else {
        rest.add(spec);
      }
    }
    if (specialInstructions != null) rest.add(specialInstructions);
    if (keywords != null) rest.add(keywords);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _sessionField(caption, lines: 2),
          ),
        for (var i = 0; i < rest.length; i += 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: i + col < rest.length
                        ? _sessionField(
                            rest[i + col],
                            lines: rest[i + col].label == _keywordsLabel ||
                                    rest[i + col].label ==
                                        _specialInstructionsLabel
                                ? 2
                                : 1,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _sessionField(WireIptcFieldSpec spec, {int lines = 1}) {
    return _EditableFieldRow(
      key: ValueKey(_fieldKey(spec.storageKey)),
      spec: spec,
      valueMaxLines: lines,
      enabled: !_fieldsInactive,
      highlighted: _isHighlighted(spec.storageKey),
      value: _displayValueForField(
        label: spec.label,
        storedValue: IptcTemplateApplyService.lookupValue(
          _displayValues,
          spec.storageKey,
        ),
        showFoundInFiles: _isFoundInFiles(
          spec.storageKey,
          _displayFoundInFilesKeys,
        ),
      ),
      showFoundInFiles: _isFoundInFiles(
        spec.storageKey,
        _displayFoundInFilesKeys,
      ),
      onValueChanged: onValueChanged,
    );
  }
}

class IptcApplyModeHelpButton extends StatelessWidget {
  const IptcApplyModeHelpButton();

  static const TextStyle _titleStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontVariations: [FontVariation('wght', 700)],
    color: Color(0xFF333333),
    height: 1.3,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontVariations: [FontVariation('wght', 400)],
    color: Color(0xFF555555),
    height: 1.45,
  );

  static void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: const Text(
          'Write IPTC Template',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontVariations: [FontVariation('wght', 700)],
            color: Color(0xFF3A6076),
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _HelpOptionBlock(
                title: 'Apply on load',
                body:
                    'When you open a folder, existing IPTC on each photo is cleared, then the template is written.',
              ),
              SizedBox(height: 10),
              _HelpOptionBlock(
                title: 'Apply on save',
                body:
                    'When Apply on load is off: write template fields when you save IPTC metadata.',
              ),
              SizedBox(height: 10),
              _HelpOptionBlock(
                title: 'Apply on FTP',
                body:
                    'When Apply on load is off: write template fields when you FTP a photo.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontVariations: [FontVariation('wght', 600)],
                color: Color(0xFF4A7A96),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Explain Write IPTC Template options',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showHelpDialog(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: PhosphorIcon(
              PhosphorIconsRegular.question,
              size: 14,
              color: IptcPanelStyle.sessionOf(context)
                  ? FfTokens.nocturneT2
                  : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpOptionBlock extends StatelessWidget {
  const _HelpOptionBlock({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: IptcApplyModeHelpButton._titleStyle),
        const SizedBox(height: 2),
        Text(body, style: IptcApplyModeHelpButton._bodyStyle),
      ],
    );
  }
}

class IptcApplyModeSelector extends StatelessWidget {
  const IptcApplyModeSelector({
    super.key,
    required this.mode,
    this.onChanged,
    this.forceSessionStyle,
  });

  final IptcApplyMode mode;
  final ValueChanged<IptcApplyMode>? onChanged;

  /// When set, overrides [IptcPanelStyle] (e.g. Caption V2 IPTC dialog).
  final bool? forceSessionStyle;

  @override
  Widget build(BuildContext context) {
    final session = forceSessionStyle ?? IptcPanelStyle.sessionOf(context);
    final onLoad = mode.appliesOnLoad;
    final onSave = mode.appliesOnSave;
    final onFtp = mode.appliesOnFtp;
    final labelColor = session ? FfTokens.sessionTx : const Color(0xFF333333);
    final muted = session ? FfTokens.sessionT2 : const Color(0xFF666666);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _flagRow(
          label: 'Apply on load',
          value: onLoad,
          enabled: onChanged != null,
          session: session,
          labelColor: labelColor,
          onChanged: (v) {
            if (onChanged == null) return;
            onChanged!(
              IptcApplyMode.fromFlags(
                onLoad: v,
                onSave: v ? false : onSave,
                onFtp: v ? false : onFtp,
              ),
            );
          },
        ),
        if (!onLoad) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              'Or apply later',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: session ? 11 : 9,
                fontVariations: const [FontVariation('wght', 500)],
                color: muted,
              ),
            ),
          ),
          const SizedBox(height: 2),
          _flagRow(
            label: 'Apply on save',
            value: onSave,
            enabled: onChanged != null,
            session: session,
            labelColor: labelColor,
            onChanged: (v) {
              if (onChanged == null) return;
              onChanged!(
                IptcApplyMode.fromFlags(
                  onLoad: false,
                  onSave: v,
                  onFtp: onFtp,
                ),
              );
            },
          ),
          _flagRow(
            label: 'Apply on FTP',
            value: onFtp,
            enabled: onChanged != null,
            session: session,
            labelColor: labelColor,
            onChanged: (v) {
              if (onChanged == null) return;
              onChanged!(
                IptcApplyMode.fromFlags(
                  onLoad: false,
                  onSave: onSave,
                  onFtp: v,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _flagRow({
    required String label,
    required bool value,
    required bool enabled,
    required bool session,
    required Color labelColor,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: session ? 18 : 16,
              height: session ? 18 : 16,
              child: Checkbox(
                value: value,
                onChanged: enabled
                    ? (v) => onChanged(v ?? false)
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: session ? FfTokens.sessionLn2 : const Color(0xFFB0B0B0),
                ),
                activeColor: session ? FfTokens.sessionOn : const Color(0xFF4A7A96),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: session ? 12 : 10,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: labelColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _FieldColumn extends StatelessWidget {
  const _FieldColumn({
    required this.specs,
    required this.values,
    required this.foundInFilesKeys,
    required this.templateRevision,
    this.highlightStorageKey,
    this.fieldsEnabled = true,
    this.onValueChanged,
  });

  final List<WireIptcFieldSpec> specs;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;
  final String? highlightStorageKey;
  final int templateRevision;
  final bool fieldsEnabled;
  final void Function(String storageKey, String value)? onValueChanged;

  bool _highlighted(String storageKey) {
    final want = highlightStorageKey?.trim() ?? '';
    if (want.isEmpty) return false;
    if (storageKey == want) return true;
    final presetKey = IptcTemplateApplyService.toPresetKey(storageKey);
    return want == presetKey ||
        want == IptcTemplateApplyService.toPanelKey(presetKey);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(height: StartupIptcTemplatePanel._rowGap),
          SizedBox(
            height: StartupIptcTemplatePanel._rowHeight,
            child: _EditableFieldRow(
              key: ValueKey('${specs[i].storageKey}-$templateRevision'),
              spec: specs[i],
              enabled: fieldsEnabled,
              highlighted: _highlighted(specs[i].storageKey),
              value: StartupIptcTemplatePanel._displayValueForField(
                label: specs[i].label,
                storedValue: IptcTemplateApplyService.lookupValue(
                  values,
                  specs[i].storageKey,
                ),
                showFoundInFiles: StartupIptcTemplatePanel._isFoundInFiles(
                  specs[i].storageKey,
                  foundInFilesKeys,
                ),
              ),
              showFoundInFiles: StartupIptcTemplatePanel._isFoundInFiles(
                specs[i].storageKey,
                foundInFilesKeys,
              ),
              onValueChanged: onValueChanged,
            ),
          ),
        ],
      ],
    );
  }
}

class _EditableFieldRow extends StatefulWidget {
  const _EditableFieldRow({
    super.key,
    required this.spec,
    this.value,
    this.showFoundInFiles = false,
    this.highlighted = false,
    this.valueMaxLines = 1,
    this.enabled = true,
    this.onValueChanged,
  });

  final WireIptcFieldSpec spec;
  final String? value;
  final bool showFoundInFiles;
  final bool highlighted;
  final int valueMaxLines;
  final bool enabled;
  final void Function(String storageKey, String value)? onValueChanged;

  @override
  State<_EditableFieldRow> createState() => _EditableFieldRowState();
}

class _EditableFieldRowState extends State<_EditableFieldRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.trim() ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    if (widget.highlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        if (widget.enabled) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_EditableFieldRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) return;
    final incoming = widget.value?.trim() ?? '';
    if (_controller.text.trim() != incoming) {
      _controller.text = incoming;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final wasFocused = _focused;
    final nowFocused = _focusNode.hasFocus;
    if (nowFocused &&
        !wasFocused &&
        IptcTemplateApplyService.isInAppGeneratedPlaceholder(
            _controller.text)) {
      _controller.clear();
    }
    setState(() => _focused = nowFocused);
  }

  void _notifyChanged(String value) {
    final trimmed = value.trim();
    if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
      widget.onValueChanged?.call(widget.spec.storageKey, '');
      return;
    }
    widget.onValueChanged?.call(widget.spec.storageKey, trimmed);
  }

  bool get _showingPlaceholder =>
      !_focused &&
      IptcTemplateApplyService.isInAppGeneratedPlaceholder(_controller.text);

  TextStyle _valueStyleFor(BuildContext context) {
    final session = IptcPanelStyle.sessionOf(context);
    final base = session
        ? const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            height: 1.25,
            color: FfTokens.sessionTx,
          )
        : StartupIptcTemplatePanel._fieldValueStyle;
    if (!widget.enabled) {
      return session
          ? base.copyWith(color: FfTokens.sessionT3)
          : StartupIptcTemplatePanel._fieldValueDisabledStyle;
    }
    if (_showingPlaceholder) {
      return base.copyWith(
        color: FfTokens.danger,
        fontStyle: FontStyle.italic,
      );
    }
    return base;
  }

  BoxDecoration _decorationFor(BuildContext context) {
    final session = IptcPanelStyle.sessionOf(context);
    if (session) {
      return BoxDecoration(
        color: widget.highlighted
            ? FfTokens.nocturneAccentDeep
            : (widget.enabled ? FfTokens.nocturneSunken : FfTokens.nocturneEl),
        border: Border.all(
          color: widget.highlighted
              ? FfTokens.accentHover
              : (widget.enabled
                  ? (_focused ? FfTokens.nocturneAc : FfTokens.sessionLn2)
                  : Colors.transparent),
          width: widget.highlighted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      );
    }
    return BoxDecoration(
      color: widget.highlighted
          ? const Color(0xFFE8F4FA)
          : (widget.enabled
              ? Colors.white
              : StartupIptcTemplatePanel._fieldDisabledFill),
      border: Border.all(
        color: widget.highlighted
            ? FfTokens.nocturneAc
            : (widget.enabled
                ? (_focused ? FfTokens.nocturneAc : const Color(0xFFD0D0D0))
                : const Color(0xFFE0E0E0)),
        width: widget.highlighted ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(4),
    );
  }

  bool get _isUrgency =>
      widget.spec.label == StartupIptcTemplatePanel._urgencyLabel;

  @override
  Widget build(BuildContext context) {
    if (IptcPanelStyle.sessionOf(context)) {
      return _buildSessionEditor(context);
    }
    final singleLine = widget.valueMaxLines == 1;

    if (_isUrgency) {
      return _buildUrgencyRow();
    }

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: _decorationFor(context),
      child: Row(
        crossAxisAlignment: widget.showFoundInFiles
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: StartupIptcTemplatePanel._labelWidth,
            child: _FieldLabel(
              label: widget.spec.label,
              showFoundInFiles: widget.showFoundInFiles,
              enabled: widget.enabled,
            ),
          ),
          Expanded(
            child: Align(
              alignment: singleLine ? Alignment.centerLeft : Alignment.topLeft,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                readOnly: !widget.enabled,
                maxLines: widget.valueMaxLines,
                minLines: 1,
                keyboardType:
                    singleLine ? TextInputType.text : TextInputType.multiline,
                textInputAction:
                    singleLine ? TextInputAction.next : TextInputAction.newline,
                style: _valueStyleFor(context),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isCollapsed: true,
                ),
                onChanged: (value) {
                  setState(() {});
                  _notifyChanged(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionEditor(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    String level;
    switch (widget.spec.level) {
      case IptcFieldLevel.required:
        level = 'REQUIRED';
        break;
      case IptcFieldLevel.recommended:
        level = 'RECOMMENDED';
        break;
      case IptcFieldLevel.optional:
        level = 'OPTIONAL';
        break;
    }
    final lines = widget.valueMaxLines < 1 ? 1 : widget.valueMaxLines;
    final labelStyle = tokens.metaStyle.copyWith(
      color: widget.enabled ? tokens.textSecondary : tokens.textTertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.spec.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            if (widget.showFoundInFiles) ...[
              Text(
                'IN FILES',
                style: tokens.microStyle.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.4,
                  color: FfTokens.sessionOk,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              level,
              style: tokens.microStyle.copyWith(
                fontSize: 9,
                letterSpacing: 0.4,
                color: widget.spec.level == IptcFieldLevel.required
                    ? tokens.accent
                    : tokens.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (_isUrgency)
          _sessionUrgencyField(tokens)
        else
          SizedBox(
            height: lines == 1
                ? _sessionControlHeight
                : _sessionControlHeight + (lines - 1) * 18,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              readOnly: !widget.enabled,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: lines == 1
                  ? TextAlignVertical.center
                  : TextAlignVertical.top,
              cursorColor: tokens.accent,
              style: _valueStyleFor(context).copyWith(fontSize: 13, height: 1.25),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: widget.enabled
                    ? FfTokens.nocturneSunken
                    : FfTokens.nocturneEl,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                border: _sessionFieldBorder(FfTokens.nocturneLn2),
                enabledBorder: _sessionFieldBorder(FfTokens.nocturneLn2),
                disabledBorder: _sessionFieldBorder(Colors.transparent),
                focusedBorder: _sessionFieldBorder(tokens.accent, width: 1.5),
              ),
              onChanged: (value) {
                setState(() {});
                _notifyChanged(value);
              },
            ),
          ),
      ],
    );
  }

  Widget _sessionUrgencyField(FfTokens tokens) {
    final current = IptcTemplateApplyService.normalizeUrgencyValue(
      _controller.text,
    );
    final value = IptcTemplateApplyService.urgencyValues.contains(current)
        ? current
        : '0';
    return Container(
      height: _sessionControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.enabled ? FfTokens.nocturneSunken : FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: widget.enabled ? FfTokens.nocturneLn2 : Colors.transparent,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: FfTokens.nocturneEl,
          style: _valueStyleFor(context).copyWith(fontSize: 13, height: 1.25),
          items: [
            for (final level in IptcTemplateApplyService.urgencyValues)
              DropdownMenuItem<String>(
                value: level,
                child: Text(
                  IptcTemplateApplyService.urgencyMenuLabel(level),
                  style: _valueStyleFor(context).copyWith(fontSize: 13),
                ),
              ),
          ],
          onChanged: widget.enabled
              ? (newValue) {
                  if (newValue == null) return;
                  setState(() => _controller.text = newValue);
                  _notifyChanged(newValue);
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildUrgencyRow() {
    final current = IptcTemplateApplyService.normalizeUrgencyValue(
      _controller.text,
    );
    final showEmptyDisabled =
        !widget.enabled && (widget.value == null || widget.value!.trim().isEmpty);

    if (showEmptyDisabled) {
      return Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: _decorationFor(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: StartupIptcTemplatePanel._labelWidth,
              child: _FieldLabel(
                label: widget.spec.label,
                showFoundInFiles: false,
                enabled: false,
              ),
            ),
            Expanded(
              child: Text(
                '',
                style: _valueStyleFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: _decorationFor(context),
      child: Row(
        crossAxisAlignment: widget.showFoundInFiles
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: StartupIptcTemplatePanel._labelWidth,
            child: _FieldLabel(
              label: widget.spec.label,
              showFoundInFiles: widget.showFoundInFiles,
              enabled: widget.enabled,
            ),
          ),
          Expanded(
            child: FfDropdownButton<String>(
                value: IptcTemplateApplyService.urgencyValues.contains(current)
                    ? current
                    : '0',
                isExpanded: true,
                style: _valueStyleFor(context),
                items: IptcTemplateApplyService.urgencyValues.map((level) {
                  return DropdownMenuItem<String>(
                    value: level,
                    child: Text(
                      IptcTemplateApplyService.urgencyMenuLabel(level),
                      style: _valueStyleFor(context),
                    ),
                  );
                }).toList(),
                onChanged: widget.enabled
                    ? (newValue) {
                        if (newValue == null) return;
                        setState(() => _controller.text = newValue);
                        _notifyChanged(newValue);
                      }
                    : null,
              ),
          ),
        ],
      ),
    );
  }
}

const double _sessionControlHeight = 34;

OutlineInputBorder _sessionFieldBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    this.showFoundInFiles = false,
    this.enabled = true,
  });

  final String label;
  final bool showFoundInFiles;
  final bool enabled;

  static const TextStyle _labelStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontVariations: [FontVariation('wght', 600)],
    color: Color(0xFF333333),
    height: 1.15,
  );

  static const TextStyle _labelDisabledStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontVariations: [FontVariation('wght', 600)],
    color: Color(0xFFB0B0B0),
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    final displayLabel = StartupIptcTemplatePanel._labelOnOneLine(label);
    final session = IptcPanelStyle.sessionOf(context);
    final labelStyle = session
        ? TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.15,
            color: enabled ? FfTokens.sessionT2 : FfTokens.sessionT3,
          )
        : (enabled ? _labelStyle : _labelDisabledStyle);

    if (!showFoundInFiles) {
      return Text(
        displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
        Text(
          'Found in files',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: session ? 10 : 8,
            fontVariations: const [FontVariation('wght', 600)],
            color: session ? FfTokens.sessionOk : const Color(0xFF2E7D32),
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _WireTemplateDropdown extends StatelessWidget {
  const _WireTemplateDropdown({
    required this.selectedWire,
    required this.wireLabels,
    required this.templates,
    this.selectedTemplateId,
    this.onTemplateSelected,
    this.onWireSelected,
    this.compact = false,
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final List<IptcTemplateCatalogEntry> templates;
  final String? selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry>? onTemplateSelected;
  final ValueChanged<WireStyle>? onWireSelected;
  final bool compact;

  List<IptcTemplateCatalogEntry> get _entries {
    if (templates.isNotEmpty) return templates;
    return AppDefaultsFirestoreService.builtInCatalogEntries();
  }

  String _labelForEntry(IptcTemplateCatalogEntry entry) {
    return WireIptcSpecs.displayWireLabel(
      entry.wireStyle,
      entry.displayName != WireIptcSpecs.factoryWireLabel(entry.wireStyle)
          ? entry.displayName
          : wireLabels[entry.wireStyle],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final itemIds = entries.map((e) => e.id).toList();
    final initialId = selectedTemplateId ??
        AppDefaultsFirestoreService.templateIdForWire(selectedWire);
    final safeInitial =
        itemIds.contains(initialId) ? initialId : itemIds.first;

    final session = IptcPanelStyle.sessionOf(context);
    final ink = session ? FfTokens.sessionTx : const Color(0xFF3A6076);
    return DropdownFlutter<String>(
      key: ValueKey('startup_iptc_wire_$safeInitial'),
      hintText: 'Select IPTC template',
      items: itemIds,
      initialItem: safeInitial,
      excludeSelected: false,
      hideSelectedFieldWhenExpanded: true,
      overlayHeight: 200,
      closedHeaderPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 5,
      ),
      expandedHeaderPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 5,
      ),
      listItemPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      headerBuilder: (context, selectedItem, enabled) {
        final entry = entries.firstWhere((e) => e.id == selectedItem);
        return Text(
          _labelForEntry(entry),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: session ? 13 : (compact ? 10 : 11),
            fontVariations: const [FontVariation('wght', 600)],
            color: ink,
          ),
        );
      },
      listItemBuilder: (context, item, isSelected, onItemSelect) {
        final entry = entries.firstWhere((e) => e.id == item);
        return InkWell(
          onTap: onItemSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: Text(
              _labelForEntry(entry),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: session ? 13 : 11,
                fontVariations: [
                  FontVariation('wght', isSelected ? 700 : 500),
                ],
                color: ink,
              ),
            ),
          ),
        );
      },
      decoration: CustomDropdownDecoration(
        closedFillColor: session ? FfTokens.nocturneSunken : Colors.white,
        expandedFillColor: session ? FfTokens.nocturneEl : Colors.white,
        closedBorder: Border.all(
          color: session ? FfTokens.sessionLn2 : const Color(0xFFD0D0D0),
          width: session ? 1 : 0.7,
        ),
        expandedBorder: Border.all(
          color: session ? FfTokens.nocturneAc : const Color(0xFF4A7A96),
          width: 1.0,
        ),
        closedBorderRadius: BorderRadius.circular(session ? 8 : 5),
        expandedBorderRadius: BorderRadius.circular(8),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: session ? 13 : (compact ? 10 : 11),
          color: session ? FfTokens.sessionT3 : Colors.grey.shade500,
        ),
        listItemDecoration: ListItemDecoration(
          selectedColor: session ? FfTokens.nocturneHv : const Color(0xFFEEF3F6),
        ),
      ),
      onChanged: (id) {
        if (id == null) return;
        final entry = entries.firstWhere((e) => e.id == id);
        onTemplateSelected?.call(entry);
      },
    );
  }
}
