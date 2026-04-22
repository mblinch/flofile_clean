import 'package:flutter/material.dart';

import '../caption_style/date_formula.dart';

/// Matches the caption layout dialog's accent blue.
const Color _editorBlue = Color(0xFF0052CC);

/// Neutral surface used by the chip / panel (matches existing caption editor chips).
const Color _chipSurface = Color(0xFFF4F4F5);
const Color _chipBorder = Color(0x14000000);
const Color _fieldText = Color(0xFF3A3A3A);

/// Active state for the ALL CAPS (Aa) control only; chip fill stays neutral.
const Color _capsButtonBg = Color(0xFFD0E3FA);

/// Structured, chip-based date formula builder.
///
/// Use [formula] + [onChanged] to drive state from the parent. Live preview is
/// shown by the hosting dialog, not this widget.
class DateFormulaEditor extends StatefulWidget {
  const DateFormulaEditor({
    super.key,
    required this.formula,
    required this.onChanged,
  });

  final DateFormula formula;
  final ValueChanged<DateFormula> onChanged;

  @override
  State<DateFormulaEditor> createState() => _DateFormulaEditorState();
}

class _DateFormulaEditorState extends State<DateFormulaEditor> {
  int? _hoverIndex;
  int? _openPopoverFieldIndex;

  DateFormula get _f => widget.formula;

  void _emit(DateFormula next) {
    final fields = List<DateFieldToken>.from(next.fields);
    final seps = List<String>.from(next.separators);
    if (seps.length != fields.length + 1) {
      widget.onChanged(next);
      return;
    }
    // Leading/trailing separator boxes are hidden in UI; force them empty.
    if (seps.isNotEmpty) {
      seps[0] = '';
      seps[seps.length - 1] = '';
    }
    widget.onChanged(DateFormula(fields: fields, separators: seps));
  }

  void _setField(int i, DateFieldToken updated) {
    final fields = List<DateFieldToken>.from(_f.fields);
    fields[i] = updated;
    _emit(DateFormula(
        fields: fields, separators: List<String>.from(_f.separators)));
  }

  void _setSeparator(int i, String value) {
    final seps = List<String>.from(_f.separators);
    seps[i] = value;
    _emit(DateFormula(
        fields: List<DateFieldToken>.from(_f.fields), separators: seps));
  }

  void _removeField(int i) {
    final fields = List<DateFieldToken>.from(_f.fields);
    final seps = List<String>.from(_f.separators);
    if (i < 0 || i >= fields.length) return;
    fields.removeAt(i);
    // Merge trailing separator onto the leading one so the surrounding literals
    // collapse rather than leaving a ghost "·" gap.
    final merged = seps[i] + seps[i + 1];
    seps
      ..removeAt(i + 1)
      ..removeAt(i);
    seps.insert(i, merged);
    _emit(DateFormula(fields: fields, separators: seps));
  }

  void _addField(DateFieldKind kind) {
    final fields = List<DateFieldToken>.from(_f.fields)
      ..add(DateFieldToken(kind: kind));
    final seps = List<String>.from(_f.separators)..add('');
    _emit(DateFormula(fields: fields, separators: seps));
  }

  /// Drop [fromIndex]'s field chip at [targetIndex] in the reordered list.
  ///
  /// We move the chip together with its *trailing* separator (so visually the
  /// literal that sat after the dragged chip travels with it), which matches
  /// how the location editor behaves.
  void _reorder(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    final fields = List<DateFieldToken>.from(_f.fields);
    final seps = List<String>.from(_f.separators);
    if (fromIndex < 0 || fromIndex >= fields.length) return;
    final chip = fields.removeAt(fromIndex);
    final trailing = seps.removeAt(fromIndex + 1);
    var insert = targetIndex;
    if (fromIndex < targetIndex) insert = targetIndex - 1;
    if (insert < 0) insert = 0;
    if (insert > fields.length) insert = fields.length;
    fields.insert(insert, chip);
    seps.insert(insert + 1, trailing);
    _emit(DateFormula(fields: fields, separators: seps));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _tokenRow(),
        const SizedBox(height: 6),
        _addFieldsRow(),
      ],
    );
  }

  // -- Token row -------------------------------------------------------------

  Widget _tokenRow() {
    final children = <Widget>[];
    for (var i = 0; i < _f.fields.length; i++) {
      children.add(_fieldChip(i));
      if (i < _f.fields.length - 1) {
        children.add(_separatorInput(i + 1));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  // -- Separator input -------------------------------------------------------

  Widget _separatorInput(int index) {
    return _SeparatorInput(
      key: ValueKey('sep-$index-${_f.separators[index]}'),
      initialValue: _f.separators[index],
      onChanged: (v) => _setSeparator(index, v),
    );
  }

  // -- Field chip ------------------------------------------------------------

  Widget _fieldChip(int index) {
    final token = _f.fields[index];
    final isCaps = token.caps;
    final isHovered = _hoverIndex == index;
    final showCaps = _dateFieldKindShowsCapsToggle(token.kind);

    final chipCore = MouseRegion(
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) {
        if (_hoverIndex == index) setState(() => _hoverIndex = null);
      },
      cursor: SystemMouseCursors.grab,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _chipSurface,
          border: Border.all(color: _chipBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle (visual only — whole chip is draggable).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.drag_indicator,
                size: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              _dateIptcChipLabel(token.kind),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _fieldText,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            _GearButton(
              active: _openPopoverFieldIndex == index,
              onOpen: () {
                setState(() => _openPopoverFieldIndex = index);
              },
              onClose: () {
                if (_openPopoverFieldIndex == index) {
                  setState(() => _openPopoverFieldIndex = null);
                }
              },
              token: token,
              onSelect: (i) {
                _setField(
                  index,
                  DateFieldToken(
                    kind: token.kind,
                    optionIndex: i,
                    caps: token.caps,
                  ),
                );
              },
            ),
            if (showCaps) ...[
              const SizedBox(width: 2),
              _chipIconButton(
                tooltip: 'ALL CAPS',
                onTap: () {
                  _setField(
                    index,
                    DateFieldToken(
                      kind: token.kind,
                      optionIndex: token.optionIndex,
                      caps: !token.caps,
                    ),
                  );
                },
                background: isCaps ? _capsButtonBg : Colors.white,
                child: const Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _fieldText,
                    height: 1,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: isHovered ? 1 : 0.4,
              child: _chipIconButton(
                tooltip: 'Remove',
                onTap: () => _removeField(index),
                background: Colors.white,
                child: Icon(
                  Icons.close,
                  size: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _reorder(d.data, index),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? _editorBlue : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: active ? _editorBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: LongPressDraggable<int>(
            data: index,
            feedback: Material(
              color: Colors.transparent,
              elevation: 4,
              borderRadius: BorderRadius.circular(6),
              child: Opacity(opacity: 0.92, child: chipCore),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: chipCore),
            child: chipCore,
          ),
        );
      },
    );
  }

  Widget _chipIconButton({
    required VoidCallback onTap,
    required Widget child,
    required Color background,
    String? tooltip,
  }) {
    final btn = SizedBox(
      width: 18,
      height: 18,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip, child: btn);
    return btn;
  }

  // -- Add fields row --------------------------------------------------------

  Widget _addFieldsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Add field:',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final k in DateFieldKind.values)
                _ghostButton(
                  label: dateFieldKindLabel(k),
                  onTap: () => _addField(k),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ghostButton({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 11, color: Colors.grey.shade700),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// ALL CAPS (Aa) in the editor only for month and weekday; day/year are numeric.
bool _dateFieldKindShowsCapsToggle(DateFieldKind kind) {
  switch (kind) {
    case DateFieldKind.month:
    case DateFieldKind.weekday:
      return true;
    case DateFieldKind.day:
    case DateFieldKind.year:
      return false;
  }
}

String _dateIptcChipLabel(DateFieldKind k) {
  switch (k) {
    case DateFieldKind.weekday:
      return 'IPTC:Weekday';
    case DateFieldKind.month:
      return 'IPTC:Month';
    case DateFieldKind.day:
      return 'IPTC:Day';
    case DateFieldKind.year:
      return 'IPTC:Year';
  }
}

/// Inline separator editor. Empty separators render as a small, subtle slot so
/// the chips breathe; only when you click in or type a literal does it bloom
/// into a visible box.
class _SeparatorInput extends StatefulWidget {
  const _SeparatorInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_SeparatorInput> createState() => _SeparatorInputState();
}

class _SeparatorInputState extends State<_SeparatorInput> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? _editorBlue : Colors.grey.shade300;
    final borderWidth = _focused ? 1.5 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 44,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Center(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            style: _style,
            textAlign: TextAlign.center,
            cursorWidth: 1.2,
            cursorColor: _editorBlue,
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (v) {
              setState(() {});
              widget.onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  static const TextStyle _style = TextStyle(
    fontSize: 13,
    color: _fieldText,
    height: 1.1,
  );
}

/// Gear button that opens the per-field format-options popover.
class _GearButton extends StatefulWidget {
  const _GearButton({
    required this.active,
    required this.onOpen,
    required this.onClose,
    required this.token,
    required this.onSelect,
  });

  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final DateFieldToken token;
  final ValueChanged<int> onSelect;

  @override
  State<_GearButton> createState() => _GearButtonState();
}

class _GearButtonState extends State<_GearButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _open();
  }

  void _open() {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            // Invisible barrier to dismiss on outside tap.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 4),
              child: Material(
                color: Colors.transparent,
                child: _OptionsCard(
                  token: widget.token,
                  onSelect: (i) {
                    widget.onSelect(i);
                    _close();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
    widget.onOpen();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: 'Format',
        child: SizedBox(
          width: 18,
          height: 18,
          child: Material(
            color: widget.active ? const Color(0xFFEAF2FF) : Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(3),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: _toggle,
              child: Center(
                child: Icon(
                  Icons.settings,
                  size: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.token, required this.onSelect});

  final DateFieldToken token;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final opts = kDateFieldOptions[token.kind]!;
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
            child: Text(
              '${dateFieldKindLabel(token.kind)} format',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (var i = 0; i < opts.length; i++)
            _optionRow(i, opts[i], selected: i == token.optionIndex),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _optionRow(int index, DateFieldFormatOption opt,
      {required bool selected}) {
    return InkWell(
      onTap: () => onSelect(index),
      child: Container(
        color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                opt.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _editorBlue : _fieldText,
                ),
              ),
            ),
            Text(
              opt.icuToken,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
