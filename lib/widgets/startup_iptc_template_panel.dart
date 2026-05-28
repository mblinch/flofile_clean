import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/iptc_template_apply_service.dart';

/// Startup right column: compact IPTC checklist filled from folder files.
class StartupIptcTemplatePanel extends StatelessWidget {
  const StartupIptcTemplatePanel({
    super.key,
    required this.selectedWire,
    required this.wireLabels,
    required this.values,
    this.onValueChanged,
    this.onWireSelected,
    this.isLoading = false,
    required this.iptcApplyMode,
    this.onIptcApplyModeChanged,
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final Map<String, String> values;
  final void Function(String storageKey, String value)? onValueChanged;
  final ValueChanged<WireStyle>? onWireSelected;
  final bool isLoading;
  final IptcApplyMode iptcApplyMode;
  final ValueChanged<IptcApplyMode>? onIptcApplyModeChanged;

  static const double _rowHeight = 36;
  static const double _captionRowHeight = 96;
  static const double _keywordsRowHeight = 56;
  /// Wide enough for longest panel labels; may wrap to 2 lines instead of ellipsis.
  static const double _labelWidth = 100;

  /// Same as the main caption editor ([CaptionFieldsWidget] caption field).
  static const TextStyle _fieldValueStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    height: 1.35,
    color: Colors.black87,
  );

  static const String _captionLabel = 'Caption';
  static const String _keywordsLabel = 'Keywords';
  static const String _headlineLabel = 'Headline';
  static const String _personalityLabel = 'Personality';
  static const String _urgencyLabel = 'Urgency';

  static const Set<String> _inAppGeneratedLabels = {
    _captionLabel,
    _personalityLabel,
  };

  @override
  Widget build(BuildContext context) {
    final specs = WireIptcSpecs.fieldsForPanel(selectedWire);
    WireIptcFieldSpec? captionSpec;
    WireIptcFieldSpec? keywordsSpec;
    WireIptcFieldSpec? headlineSpec;
    final remaining = <WireIptcFieldSpec>[];
    for (final spec in specs) {
      if (spec.label == _captionLabel) {
        captionSpec = spec;
      } else if (spec.label == _keywordsLabel) {
        keywordsSpec = spec;
      } else if (spec.label == _headlineLabel) {
        headlineSpec = spec;
      } else {
        remaining.add(spec);
      }
    }
    final mid = (remaining.length / 2).ceil();
    final left = remaining.sublist(0, mid);
    final right = remaining.sublist(mid);

    final requiredTotal =
        specs.where((s) => s.level == IptcFieldLevel.required).length;
    var requiredFilled = 0;
    for (final s in specs) {
      if (s.level == IptcFieldLevel.required &&
          (values[s.storageKey]?.trim().isNotEmpty ?? false)) {
        requiredFilled++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: _WireTemplateDropdown(
                selectedWire: selectedWire,
                wireLabels: wireLabels,
                onSelected: onWireSelected,
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
                  const SizedBox(width: 6),
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
        const SizedBox(height: 6),
        Row(
          children: [
            if (isLoading) ...[
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
                  fontVariations: const [FontVariation('wght', 500)],
                  color: Colors.grey.shade600,
                ),
              ),
            ] else
              Text(
                '$requiredFilled / $requiredTotal required',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontVariations: [FontVariation('wght', 600)],
                  color: Color(0xFF4A7A96),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (captionSpec != null) ...[
                SizedBox(
                  height: _captionRowHeight,
                  child: _EditableFieldRow(
                    key: ValueKey(captionSpec.storageKey),
                    spec: captionSpec,
                    value: IptcTemplateApplyService.lookupValue(
                      values,
                      captionSpec.storageKey,
                    ),
                    valueMaxLines: 6,
                    onValueChanged: onValueChanged,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (keywordsSpec != null) ...[
                SizedBox(
                  height: _keywordsRowHeight,
                  child: _EditableFieldRow(
                    key: ValueKey(keywordsSpec.storageKey),
                    spec: keywordsSpec,
                    value: IptcTemplateApplyService.lookupValue(
                      values,
                      keywordsSpec.storageKey,
                    ),
                    valueMaxLines: 3,
                    onValueChanged: onValueChanged,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (headlineSpec != null) ...[
                SizedBox(
                  height: _rowHeight,
                  child: _EditableFieldRow(
                    key: ValueKey(headlineSpec.storageKey),
                    spec: headlineSpec,
                    value: IptcTemplateApplyService.lookupValue(
                      values,
                      headlineSpec.storageKey,
                    ),
                    onValueChanged: onValueChanged,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _FieldColumn(
                          specs: left,
                          values: values,
                          rowHeight: _rowHeight,
                          onValueChanged: onValueChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FieldColumn(
                          specs: right,
                          values: values,
                          rowHeight: _rowHeight,
                          onValueChanged: onValueChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
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
              color: selected
                  ? const Color(0xFF333333)
                  : const Color(0xFF888888),
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
    required this.rowHeight,
    this.onValueChanged,
  });

  final List<WireIptcFieldSpec> specs;
  final Map<String, String> values;
  final double rowHeight;
  final void Function(String storageKey, String value)? onValueChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          SizedBox(
            height: rowHeight,
            child: _EditableFieldRow(
              key: ValueKey(specs[i].storageKey),
              spec: specs[i],
              value: IptcTemplateApplyService.lookupValue(
                values,
                specs[i].storageKey,
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
    this.valueMaxLines = 1,
    this.onValueChanged,
  });

  final WireIptcFieldSpec spec;
  final String? value;
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
    final incoming = widget.value?.trim() ?? '';
    if (incoming != oldWidget.value?.trim() && !_focusNode.hasFocus) {
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
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _notifyChanged(String value) {
    widget.onValueChanged?.call(widget.spec.storageKey, value);
  }

  bool get _isUrgency => widget.spec.label == StartupIptcTemplatePanel._urgencyLabel;

  @override
  Widget build(BuildContext context) {
    final singleLine = widget.valueMaxLines == 1;

    if (_isUrgency) {
      return _buildUrgencyRow();
    }

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _focused
              ? const Color(0xFF4A7A96)
              : const Color(0xFFD0D0D0),
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
        crossAxisAlignment:
            singleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: StartupIptcTemplatePanel._labelWidth,
            child: _FieldLabel(
              label: widget.spec.label,
              showGeneratedInApp:
                  StartupIptcTemplatePanel._inAppGeneratedLabels
                      .contains(widget.spec.label),
              compact: !StartupIptcTemplatePanel._inAppGeneratedLabels
                  .contains(widget.spec.label),
            ),
          ),
          Expanded(
            child: Align(
              alignment: singleLine
                  ? Alignment.centerLeft
                  : Alignment.topLeft,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: widget.valueMaxLines,
                minLines: 1,
                keyboardType: singleLine
                    ? TextInputType.text
                    : TextInputType.multiline,
                textInputAction:
                    singleLine ? TextInputAction.next : TextInputAction.newline,
                style: StartupIptcTemplatePanel._fieldValueStyle,
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _focused
              ? const Color(0xFF4A7A96)
              : const Color(0xFFD0D0D0),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: StartupIptcTemplatePanel._labelWidth,
            child: _FieldLabel(
              label: widget.spec.label,
              showGeneratedInApp: false,
              compact: true,
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: IptcTemplateApplyService.urgencyValues.contains(current)
                    ? current
                    : '5',
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
    required this.showGeneratedInApp,
    this.compact = true,
  });

  final String label;
  final bool showGeneratedInApp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontVariations: [FontVariation('wght', 600)],
      color: Color(0xFF333333),
      height: 1.15,
    );

    if (compact && !showGeneratedInApp) {
      return Text(
        label,
        maxLines: 2,
        softWrap: true,
        style: labelStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          softWrap: true,
          style: labelStyle,
        ),
        if (showGeneratedInApp)
          const Text(
            'Generated In-App',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 8,
              fontVariations: [FontVariation('wght', 600)],
              color: Color(0xFFD32F2F),
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
    this.onSelected,
    this.compact = false,
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final ValueChanged<WireStyle>? onSelected;
  final bool compact;

  static List<String> get _itemKeys =>
      WireIptcSpecs.builtInWires.map((w) => w.name).toList();

  String _labelForKey(String key) {
    final wire = WireStyle.values.firstWhere((w) => w.name == key);
    return WireIptcSpecs.displayWireLabel(wire, wireLabels[wire]);
  }

  WireStyle _wireFromKey(String key) =>
      WireStyle.values.firstWhere((w) => w.name == key);

  @override
  Widget build(BuildContext context) {
    final initialKey = selectedWire.name;
    final safeInitial =
        _itemKeys.contains(initialKey) ? initialKey : _itemKeys.first;

    return DropdownFlutter<String>(
      key: ValueKey('startup_iptc_wire_$safeInitial'),
      hintText: 'Select IPTC template',
      items: _itemKeys,
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
        return Text(
          _labelForKey(selectedItem),
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
        return InkWell(
          onTap: onItemSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              _labelForKey(item),
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
      onChanged: (key) {
        if (key == null || onSelected == null) return;
        onSelected!(_wireFromKey(key));
      },
    );
  }
}
