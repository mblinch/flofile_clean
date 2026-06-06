import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/iptc_template_apply_service.dart';
import 'app_styled_dialogs.dart';

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
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final List<IptcTemplateCatalogEntry> visibleTemplates;
  final String? selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry>? onTemplateSelected;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;
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

  @override
  Widget build(BuildContext context) {
    final specs = WireIptcSpecs.fieldsForPanel(selectedWire);
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

    return Column(
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
                          fontSize: 9,
                          fontVariations: const [FontVariation('wght', 600)],
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    const _IptcApplyModeHelpButton(),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 240,
                      child: _IptcApplyModeSelector(
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
                      value: _displayValueForField(
                        label: captionSpec.label,
                        storedValue: IptcTemplateApplyService.lookupValue(
                          values,
                          captionSpec.storageKey,
                        ),
                        showFoundInFiles: _isFoundInFiles(
                          captionSpec.storageKey,
                          foundInFilesKeys,
                        ),
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        captionSpec.storageKey,
                        foundInFilesKeys,
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
                      value: IptcTemplateApplyService.lookupValue(
                        values,
                        headlineSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        headlineSpec.storageKey,
                        foundInFilesKeys,
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
                      value: IptcTemplateApplyService.lookupValue(
                        values,
                        keywordsSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        keywordsSpec.storageKey,
                        foundInFilesKeys,
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
                      value: IptcTemplateApplyService.lookupValue(
                        values,
                        specialInstructionsSpec.storageKey,
                      ),
                      showFoundInFiles: _isFoundInFiles(
                        specialInstructionsSpec.storageKey,
                        foundInFilesKeys,
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
                        values: values,
                        foundInFilesKeys: foundInFilesKeys,
                        templateRevision: templateRevision,
                        onValueChanged: onValueChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FieldColumn(
                        specs: right,
                        values: values,
                        foundInFilesKeys: foundInFilesKeys,
                        templateRevision: templateRevision,
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
                              icon: Icons.upload_file_outlined,
                              isTealGradient: true,
                              fullWidth: true,
                              onPressed: isLoadTemplateLoading ||
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
                              icon: Icons.restore_page_outlined,
                              fullWidth: true,
                              onPressed: isLoadTemplateLoading ||
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
                              icon: Icons.clear_all,
                              isDanger: true,
                              fullWidth: true,
                              onPressed: isLoadTemplateLoading ||
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
    );
  }
}

class _IptcApplyModeHelpButton extends StatelessWidget {
  const _IptcApplyModeHelpButton();

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
            color: Color(0xFF2A4858),
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _HelpOptionBlock(
                title: 'Off',
                body:
                    'The template is for reference only. Nothing is written to your image files automatically.',
              ),
              SizedBox(height: 10),
              _HelpOptionBlock(
                title: 'On import',
                body:
                    'When you open a folder, template fields are written to each image as it loads. Caption and Personality are skipped — those are generated in the app.',
              ),
              SizedBox(height: 10),
              _HelpOptionBlock(
                title: 'On save',
                body:
                    'Nothing is written when you open a folder. Template fields are written only when you save IPTC metadata. Caption and Personality are written too — from what you build in the app, not from this template panel.',
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
            child: Icon(
              Icons.help_outline,
              size: 12,
              color: Colors.grey.shade600,
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
        Text(title, style: _IptcApplyModeHelpButton._titleStyle),
        const SizedBox(height: 2),
        Text(body, style: _IptcApplyModeHelpButton._bodyStyle),
      ],
    );
  }
}

class _IptcApplyModeSelector extends StatelessWidget {
  const _IptcApplyModeSelector({
    required this.mode,
    this.onChanged,
  });

  final IptcApplyMode mode;
  final ValueChanged<IptcApplyMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8E8E8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              label: 'Off',
              selected: mode == IptcApplyMode.none,
              onTap: () => _select(IptcApplyMode.none),
            ),
          ),
          Container(width: 0.7, height: 22, color: const Color(0xFFD0D0D0)),
          Expanded(
            child: _segment(
              label: 'On import',
              selected: mode == IptcApplyMode.onImport,
              onTap: () => _select(IptcApplyMode.onImport),
            ),
          ),
          Container(width: 0.7, height: 22, color: const Color(0xFFD0D0D0)),
          Expanded(
            child: _segment(
              label: 'On save',
              selected: mode == IptcApplyMode.onSave,
              onTap: () => _select(IptcApplyMode.onSave),
            ),
          ),
        ],
      ),
    );
  }

  void _select(IptcApplyMode target) {
    if (onChanged == null) return;
    onChanged!(target);
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          alignment: Alignment.center,
          color: selected ? Colors.white : Colors.transparent,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontVariations: [
                FontVariation('wght', selected ? 700 : 500),
              ],
              color:
                  selected ? const Color(0xFF333333) : const Color(0xFF888888),
            ),
          ),
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
    this.onValueChanged,
  });

  final List<WireIptcFieldSpec> specs;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;
  final int templateRevision;
  final void Function(String storageKey, String value)? onValueChanged;

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
    this.valueMaxLines = 1,
    this.onValueChanged,
  });

  final WireIptcFieldSpec spec;
  final String? value;
  final bool showFoundInFiles;
  final int valueMaxLines;
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

  TextStyle get _valueStyle => _showingPlaceholder
      ? StartupIptcTemplatePanel._fieldValueStyle.copyWith(
          color: const Color(0xFFD32F2F),
          fontStyle: FontStyle.italic,
        )
      : StartupIptcTemplatePanel._fieldValueStyle;

  bool get _isUrgency =>
      widget.spec.label == StartupIptcTemplatePanel._urgencyLabel;

  @override
  Widget build(BuildContext context) {
    final singleLine = widget.valueMaxLines == 1;

    if (_isUrgency) {
      return _buildUrgencyRow();
    }

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _focused ? const Color(0xFF4A7A96) : const Color(0xFFD0D0D0),
          width: _focused ? 1.0 : 0.7,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 1,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
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
            ),
          ),
          Expanded(
            child: Align(
              alignment: singleLine ? Alignment.centerLeft : Alignment.topLeft,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: widget.valueMaxLines,
                minLines: 1,
                keyboardType:
                    singleLine ? TextInputType.text : TextInputType.multiline,
                textInputAction:
                    singleLine ? TextInputAction.next : TextInputAction.newline,
                style: _valueStyle,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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

  Widget _buildUrgencyRow() {
    final current = IptcTemplateApplyService.normalizeUrgencyValue(
      _controller.text,
    );

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _focused ? const Color(0xFF4A7A96) : const Color(0xFFD0D0D0),
          width: _focused ? 1.0 : 0.7,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 1,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
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
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: IptcTemplateApplyService.urgencyValues.contains(current)
                    ? current
                    : '0',
                isExpanded: true,
                isDense: true,
                style: StartupIptcTemplatePanel._fieldValueStyle,
                items: IptcTemplateApplyService.urgencyValues.map((level) {
                  return DropdownMenuItem<String>(
                    value: level,
                    child: Text(
                      IptcTemplateApplyService.urgencyMenuLabel(level),
                      style: StartupIptcTemplatePanel._fieldValueStyle,
                    ),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue == null) return;
                  setState(() => _controller.text = newValue);
                  _notifyChanged(newValue);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    this.showFoundInFiles = false,
  });

  final String label;
  final bool showFoundInFiles;

  static const TextStyle _labelStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontVariations: [FontVariation('wght', 600)],
    color: Color(0xFF333333),
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    final displayLabel = StartupIptcTemplatePanel._labelOnOneLine(label);

    if (!showFoundInFiles) {
      return Text(
        displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _labelStyle,
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
          style: _labelStyle,
        ),
        const Text(
          'Found in files',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8,
            fontVariations: [FontVariation('wght', 600)],
            color: Color(0xFF2E7D32),
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
            fontSize: compact ? 10 : 11,
            fontVariations: const [FontVariation('wght', 600)],
            color: const Color(0xFF2A4858),
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
                fontSize: 11,
                fontVariations: [
                  FontVariation('wght', isSelected ? 700 : 500),
                ],
                color: const Color(0xFF2A4858),
              ),
            ),
          ),
        );
      },
      decoration: CustomDropdownDecoration(
        closedFillColor: Colors.white,
        expandedFillColor: Colors.white,
        closedBorder: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
        expandedBorder: Border.all(color: const Color(0xFF4A7A96), width: 1.0),
        closedBorderRadius: BorderRadius.circular(5),
        expandedBorderRadius: BorderRadius.circular(8),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: compact ? 10 : 11,
          color: Colors.grey.shade500,
        ),
        listItemDecoration: const ListItemDecoration(
          selectedColor: Color(0xFFEEF3F6),
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
