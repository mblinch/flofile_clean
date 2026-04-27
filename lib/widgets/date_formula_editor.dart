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

/// All date kinds the editor exposes, in the canonical order they appear when
/// an existing template hasn't placed them yet (mirrors the location editor's
/// "always show every supported field as a chip" model).
const List<DateFieldKind> _allDateKinds = [
  DateFieldKind.weekday,
  DateFieldKind.month,
  DateFieldKind.day,
  DateFieldKind.year,
];

/// Structured, single-line date formula builder.
///
/// Every supported date field (Day-of-week, Month, Day, Year) is always shown
/// as a chip. A switch on each chip toggles whether that field appears in the
/// rendered date. Between every pair of adjacent chips sits a small
/// separator field that owns the literal text printed between them. Each chip
/// has a leading drag handle (the ⋮⋮ icon); click + drag from there to reorder
/// — the rest of the chip stays interactive so the toggle / format gear /
/// caps button stay clickable. A live preview line at the bottom shows the
/// resulting date string using the host's [sampleDate] (or a fixed Tuesday,
/// April 9, 2026 example when none is provided).
class DateFormulaEditor extends StatefulWidget {
  const DateFormulaEditor({
    super.key,
    required this.formula,
    required this.onChanged,
    this.sampleDate,
  });

  final DateFormula formula;
  final ValueChanged<DateFormula> onChanged;

  /// Drives the inline sample text on each chip and the bottom preview line.
  /// Defaults to a fixed sample date when null.
  final DateTime? sampleDate;

  @override
  State<DateFormulaEditor> createState() => _DateFormulaEditorState();
}

class _DateField {
  _DateField({
    required this.kind,
    this.optionIndex = 0,
    this.caps = false,
    this.enabled = true,
  });
  final DateFieldKind kind;
  int optionIndex;
  bool caps;
  bool enabled;
}

class _DateFormulaEditorState extends State<DateFormulaEditor> {
  /// Date fields in display order. The editor preserves any duplicates that
  /// existed in the saved formula and appends disabled placeholders for any
  /// kinds in [_allDateKinds] not already present, so the user can toggle
  /// every field on without ever needing an "Add field" button.
  late List<_DateField> _fields;

  /// Literal text between fields. Length is always `_fields.length - 1`,
  /// where `_separators[i]` is the literal between `_fields[i]` and
  /// `_fields[i + 1]`.
  late List<String> _separators;

  int? _openPopoverFieldIndex;

  @override
  void initState() {
    super.initState();
    _parseFromFormula();
  }

  @override
  void didUpdateWidget(covariant DateFormulaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.formula, widget.formula)) {
      _parseFromFormula();
    }
  }

  /// Build [_fields] / [_separators] from the persisted [DateFormula].
  ///
  /// The persisted model uses `separators.length == fields.length + 1` (i.e.
  /// a leading + a trailing literal slot in addition to the between-field
  /// gaps). The editor only exposes between-field gaps; legacy non-empty
  /// leading/trailing literals are dropped because they have no chip to
  /// attach to in the new flat editor and also wouldn't be reachable in the
  /// new render path (which strips them too).
  void _parseFromFormula() {
    final f = widget.formula;
    final fields = <_DateField>[];
    for (final tok in f.fields) {
      fields.add(_DateField(
        kind: tok.kind,
        optionIndex: tok.optionIndex,
        caps: tok.caps,
        enabled: tok.enabled,
      ));
    }
    final between = <String>[];
    // separators[i] for i in 1..fields.length-1 sits between fields[i-1] and
    // fields[i]. separators[0] (leading) and separators[last] (trailing) are
    // ignored.
    for (var i = 1; i < f.fields.length; i++) {
      between.add(i < f.separators.length ? f.separators[i] : ' ');
    }

    final present = fields.map((e) => e.kind).toSet();
    for (final k in _allDateKinds) {
      if (!present.contains(k)) {
        if (fields.isNotEmpty) between.add(_defaultSeparator(k));
        fields.add(_DateField(kind: k, enabled: false));
      }
    }

    _fields = fields;
    _separators = between;
  }

  String _defaultSeparator(DateFieldKind k) {
    switch (k) {
      case DateFieldKind.year:
        return ', ';
      case DateFieldKind.weekday:
      case DateFieldKind.month:
      case DateFieldKind.day:
        return ' ';
    }
  }

  /// Convert the current (fields, separators) state back to a [DateFormula]
  /// and emit it to the parent. Leading/trailing literal slots are forced
  /// empty (the editor never exposes them) so the canonical
  /// `separators.length == fields.length + 1` invariant still holds.
  void _emit() {
    final tokens = _fields
        .map((f) => DateFieldToken(
              kind: f.kind,
              optionIndex: f.optionIndex,
              caps: f.caps,
              enabled: f.enabled,
            ))
        .toList();
    final seps = <String>[];
    seps.add('');
    for (final s in _separators) {
      seps.add(s);
    }
    seps.add('');
    widget.onChanged(DateFormula(fields: tokens, separators: seps));
  }

  // -- Mutations -------------------------------------------------------------

  void _setSeparator(int gapIndex, String value) {
    setState(() => _separators[gapIndex] = value);
    _emit();
  }

  void _setEnabled(int i, bool enabled) {
    setState(() => _fields[i].enabled = enabled);
    _emit();
  }

  void _toggleCaps(int i) {
    setState(() => _fields[i].caps = !_fields[i].caps);
    _emit();
  }

  void _setOptionIndex(int i, int optionIndex) {
    setState(() => _fields[i].optionIndex = optionIndex);
    _emit();
  }

  void _reorder(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    if (fromIndex < 0 || fromIndex >= _fields.length) return;
    if (targetIndex < 0 || targetIndex >= _fields.length) return;
    setState(() {
      final f = _fields.removeAt(fromIndex);
      // "Drop chip X onto chip Y" semantic: X lands AT Y's slot in the
      // post-removal list. See location_formula_editor._reorder for why we
      // do NOT subtract 1 when moving right.
      var insert = targetIndex;
      if (insert < 0) insert = 0;
      if (insert > _fields.length) insert = _fields.length;
      _fields.insert(insert, f);
      // Separators are positional — they always sit between adjacent slots —
      // so we leave them in place and let the user re-edit if needed. We do
      // need to make sure the count stays exactly `_fields.length - 1`.
      while (_separators.length > _fields.length - 1) {
        _separators.removeLast();
      }
      while (_separators.length < _fields.length - 1) {
        _separators.add(' ');
      }
    });
    _emit();
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _tokenRow(),
        const SizedBox(height: 6),
        _previewLine(),
      ],
    );
  }

  Widget _tokenRow() {
    final children = <Widget>[];
    for (var i = 0; i < _fields.length; i++) {
      children.add(_fieldChip(i));
      if (i < _fields.length - 1) {
        children.add(_separatorInput(i));
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

  Widget _separatorInput(int gapIndex) {
    return _DateSeparatorInput(
      // Stable key — must NOT include the current value, otherwise the widget
      // gets thrown away and rebuilt on every keystroke, which both loses
      // focus (you'd have to click again to keep typing) and causes macOS to
      // ring the system bell when an unfocused backspace bubbles to the OS.
      key: ValueKey('date-sep-$gapIndex'),
      value: _separators[gapIndex],
      onChanged: (v) => _setSeparator(gapIndex, v),
    );
  }

  Widget _fieldChip(int index) {
    final f = _fields[index];
    final sample = _sampleValueFor(f);
    final enabled = f.enabled;
    final showCaps = _showCaps(f.kind);

    Widget buildChipBody({required Widget handle}) {
      return Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          height: 28,
          padding: const EdgeInsets.only(left: 2, right: 6),
          decoration: BoxDecoration(
            color: _chipSurface,
            border: Border.all(color: _chipBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 4),
              _ChipSwitch(
                value: enabled,
                onChanged: (v) => _setEnabled(index, v),
              ),
              const SizedBox(width: 6),
              Text(
                _dateIptcChipLabel(f.kind),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _fieldText,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sample,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade600,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
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
                kind: f.kind,
                optionIndex: f.optionIndex,
                onSelect: (i) => _setOptionIndex(index, i),
              ),
              if (showCaps) ...[
                const SizedBox(width: 6),
                _chipIconButton(
                  tooltip: 'ALL CAPS',
                  onTap: () => _toggleCaps(index),
                  background: f.caps ? _capsButtonBg : Colors.white,
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
            ],
          ),
        ),
      );
    }

    Widget staticHandle() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Icon(
            Icons.drag_indicator,
            size: 14,
            color: Colors.grey.shade500,
          ),
        );

    final feedbackChip = buildChipBody(handle: staticHandle());

    final draggableHandle = Draggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(opacity: 0.92, child: feedbackChip),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag to reorder',
          child: staticHandle(),
        ),
      ),
    );

    final chipCore = buildChipBody(handle: draggableHandle);

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _reorder(d.data, index),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: hot ? _editorBlue : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: hot ? _editorBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: chipCore,
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

  Widget _previewLine() {
    final date = widget.sampleDate ?? _fallbackSampleDate();
    final rendered = widget.formula.render(date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'Preview:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rendered,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _fieldText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the field's CURRENT format option using the sample date so the
  /// chip preview always reflects the user's choice (e.g. "April" vs "Apr"
  /// vs "4" vs "04"). Caps is also applied so toggling Aa updates the chip.
  String _sampleValueFor(_DateField f) {
    final date = widget.sampleDate ?? _fallbackSampleDate();
    final tok = DateFieldToken(
      kind: f.kind,
      optionIndex: f.optionIndex,
      caps: f.caps,
    );
    return tok.render(date);
  }

  /// Tuesday, April 9, 2026 — picked so every kind has a distinct, recognizable
  /// sample (weekday "Tue", month "Apr", day "9", year "2026") that fits in
  /// the chip without truncating.
  DateTime _fallbackSampleDate() => DateTime(2026, 4, 9);
}

/// ALL CAPS (Aa) shows on month and weekday only; day/year are numeric so the
/// toggle wouldn't change anything.
bool _showCaps(DateFieldKind kind) {
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

/// Compact iOS-style switch sized to fit inside a 28px-tall editor chip.
class _ChipSwitch extends StatelessWidget {
  const _ChipSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 18,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: _editorBlue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Gear button that opens the per-field format-options popover.
class _GearButton extends StatefulWidget {
  const _GearButton({
    required this.active,
    required this.onOpen,
    required this.onClose,
    required this.kind,
    required this.optionIndex,
    required this.onSelect,
  });

  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final DateFieldKind kind;
  final int optionIndex;
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
                  kind: widget.kind,
                  optionIndex: widget.optionIndex,
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
              side: BorderSide(
                color: widget.active ? _editorBlue : Colors.grey.shade300,
                width: widget.active ? 1.4 : 1,
              ),
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
  const _OptionsCard({
    required this.kind,
    required this.optionIndex,
    required this.onSelect,
  });

  final DateFieldKind kind;
  final int optionIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final opts = kDateFieldOptions[kind]!;
    return Container(
      width: 200,
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
              '${dateFieldKindLabel(kind).toUpperCase()} FORMAT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (var i = 0; i < opts.length; i++)
            _optionRow(i, opts[i], selected: i == optionIndex),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _optionRow(
    int index,
    DateFieldFormatOption opt, {
    required bool selected,
  }) {
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

/// Fixed-size separator text field — sized to roughly five characters wide so
/// it's the obvious "small punctuation slot" between two field chips.
///
/// Mirrors `_LocSeparatorInput` from the location editor: stable key, owns its
/// [TextEditingController], resyncs in [didUpdateWidget] only when unfocused,
/// and wraps everything in a [GestureDetector] so clicking anywhere in the
/// 38×28 box focuses the input on the first try.
class _DateSeparatorInput extends StatefulWidget {
  const _DateSeparatorInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_DateSeparatorInput> createState() => _DateSeparatorInputState();
}

class _DateSeparatorInputState extends State<_DateSeparatorInput> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _DateSeparatorInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // While the user is actively typing we let our local controller win; only
    // pick up an external change when focus is elsewhere (e.g. the parent
    // restored a saved template or a reorder shuffled the separator pool).
    if (!_focus.hasFocus && widget.value != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: Container(
          width: 38,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          alignment: Alignment.center,
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
            onChanged: widget.onChanged,
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
