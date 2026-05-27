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
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final Map<String, String> values;
  final void Function(String storageKey, String value)? onValueChanged;
  final ValueChanged<WireStyle>? onWireSelected;
  final bool isLoading;

  static const double _rowHeight = 36;
  static const double _captionRowHeight = 96;
  static const double _keywordsRowHeight = 56;
  /// Wide enough for longest panel labels; may wrap to 2 lines instead of ellipsis.
  static const double _labelWidth = 100;

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
        _WireTemplateDropdown(
          selectedWire: selectedWire,
          wireLabels: wireLabels,
          onSelected: onWireSelected,
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
    final hasValue = _controller.text.trim().isNotEmpty;
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
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontVariations: [
                    FontVariation('wght', hasValue ? 600 : 400),
                  ],
                  color: const Color(0xFF2A4858),
                  height: 1.2,
                ),
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
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontVariations: [FontVariation('wght', 600)],
                  color: Color(0xFF2A4858),
                ),
                items: IptcTemplateApplyService.urgencyValues.map((level) {
                  return DropdownMenuItem<String>(
                    value: level,
                    child: Text(
                      IptcTemplateApplyService.urgencyMenuLabel(level),
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
      color: Color(0xFF4A7A96),
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
  });

  final WireStyle selectedWire;
  final Map<WireStyle, String> wireLabels;
  final ValueChanged<WireStyle>? onSelected;

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
      closedHeaderPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      expandedHeaderPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      listItemPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      headerBuilder: (context, selectedItem, enabled) {
        return Text(
          _labelForKey(selectedItem),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontVariations: [FontVariation('wght', 600)],
            color: Color(0xFF2A4858),
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
          fontSize: 11,
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
