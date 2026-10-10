import 'package:flutter/material.dart';
import '../caption_style/date_formula.dart';
import '../theme/ff_tokens.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Matches the caption layout dialog's accent.
const Color _editorBlue = FfTokens.nocturneAc;

/// Chip fill matches the structure-row field chips.
const Color _chipSurface = FfTokens.nocturneSunken;
const Color _chipBorder = Color(0x665A6570);
const Color _fieldText = FfTokens.nocturneTx;
const Color _mutedText = FfTokens.nocturneT3;

/// Active state for the ALL CAPS (Aa) control only; chip fill stays neutral.
const Color _capsButtonBg = FfTokens.nocturneAccentDeep;

/// Separator text boxes.
const Color _textBoxFill = Color(0xFF1B3344);

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

  /// Literal text around fields. Length is always `_fields.length + 1`.
  /// `_separators[0]` is before the first field, `_separators[i + 1]`
  /// follows `_fields[i]`, and the final entry is after the last field.
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
  /// gaps), and the editor exposes all of those slots.
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
    final seps = <String>[];
    for (var i = 0; i <= f.fields.length; i++) {
      seps.add(i < f.separators.length ? f.separators[i] : '');
    }

    final present = fields.map((e) => e.kind).toSet();
    for (final k in _allDateKinds) {
      if (!present.contains(k)) {
        final insertAt = seps.isEmpty ? 0 : seps.length - 1;
        if (seps.isEmpty) seps.add('');
        seps.insert(insertAt, fields.isNotEmpty ? _defaultSeparator(k) : '');
        fields.add(_DateField(kind: k, enabled: false));
      }
    }

    _fields = fields;
    _separators = seps;
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
  /// and emit it to the parent.
  void _emit() {
    widget.onChanged(_currentFormula());
  }

  DateFormula _currentFormula() {
    final tokens = _fields
        .map((f) => DateFieldToken(
              kind: f.kind,
              optionIndex: f.optionIndex,
              caps: f.caps,
              enabled: f.enabled,
            ))
        .toList();
    return DateFormula(
      fields: tokens,
      separators: List<String>.from(_separators),
      autoSpacing: false,
    );
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
      // Separators are positional — they sit around adjacent slots —
      // so we leave them in place and let the user re-edit if needed. We do
      // need to make sure the count stays exactly `_fields.length + 1`.
      while (_separators.length > _fields.length + 1) {
        _separators.removeLast();
      }
      while (_separators.length < _fields.length + 1) {
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
        _previewLine(),
        const SizedBox(height: 8),
        _tokenRow(),
        _unusedFieldOptions(),
      ],
    );
  }

  Widget _tokenRow() {
    final visible = <int>[
      for (var i = 0; i < _fields.length; i++)
        if (_fields[i].enabled) i,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[
      _separatorInput(visible.first),
    ];
    for (final i in visible) {
      children.add(_fieldChip(i));
      children.add(_separatorInput(i + 1));
    }
    return Wrap(
      spacing: 0,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _unusedFieldOptions() {
    final unused = <int>[
      for (var i = 0; i < _fields.length; i++)
        if (!_fields[i].enabled) i,
    ];
    if (unused.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final i in unused)
            _addableFieldChip(
              label: _dateIptcChipLabel(_fields[i].kind),
              onTap: () => _setEnabled(i, true),
            ),
        ],
      ),
    );
  }

  Widget _addableFieldChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _chipSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0x29E8EEF4),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 14, color: _mutedText),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _fieldText,
                  height: 1,
                ),
              ),
            ],
          ),
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
          height: 32,
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: _chipSurface,
            border: Border.all(
              color: const Color(0x29E8EEF4),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 6),
              Text(
                _dateIptcChipLabel(f.kind),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _fieldText,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sample,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: _mutedText,
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
                  background: f.caps ? _capsButtonBg : _chipSurface,
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
              const SizedBox(width: 4),
              Tooltip(
                message: 'Remove',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _setEnabled(index, false),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: PhosphorIcon(
                        PhosphorIconsRegular.x,
                        size: 12,
                        color: _mutedText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget staticHandle() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: PhosphorIcon(PhosphorIconsRegular.dotsSixVertical,
            size: 14,
            color: _mutedText,
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
          side: const BorderSide(color: _chipBorder),
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
    final rendered = _currentFormula().render(date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'Preview:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _mutedText,
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
            color: widget.active ? FfTokens.nocturneAccentSoft : _chipSurface,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: widget.active ? _editorBlue : _chipBorder,
                width: widget.active ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: _toggle,
              child: Center(
                child: PhosphorIcon(PhosphorIconsRegular.gear,
                  size: 11,
                  color: _fieldText,
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
        color: FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _chipBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
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
                color: _mutedText,
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
        color: selected ? FfTokens.nocturneAccentSoft : Colors.transparent,
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
                color: _mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleSpaceTextController extends TextEditingController {
  _VisibleSpaceTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spaceStyle = style?.copyWith(
      fontSize: (style.fontSize ?? 15) * 0.75,
      color: style.color,
    );
    return TextSpan(
      style: style,
      children: [
        for (final ch in text.split(''))
          TextSpan(
            text: ch == ' ' ? '⎵' : ch,
            style: ch == ' ' ? spaceStyle : null,
          ),
      ],
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
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = _VisibleSpaceTextController(
      text: widget.value,
    );
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _DateSeparatorInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value;
    if (!_focus.hasFocus && value != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  void _handleChanged(String value) {
    setState(() {});
    widget.onChanged(value);
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
    final borderColor =
        _focused ? _editorBlue : const Color(0x29E8EEF4);
    final borderWidth = _focused ? 1.5 : 0.5;
    final idle = _idleLabel(_ctrl.text);
    final measureText = _focused
        ? (_ctrl.text.isEmpty ? ' ' : _ctrl.text.replaceAll(' ', '⎵'))
        : (idle.isEmpty ? ' ' : idle);
    final fieldWidth = _fieldWidthFor(
      measureText,
      _focused ? _style : _idleStyle,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: Container(
          width: fieldWidth,
          height: 32,
          decoration: BoxDecoration(
            color: _textBoxFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                style: _style.copyWith(
                  color: _focused ? _fieldText : Colors.transparent,
                ),
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
                onChanged: _handleChanged,
              ),
              if (!_focused && idle.isNotEmpty)
                IgnorePointer(
                  child: Text(idle, style: _idleStyle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _idleLabel(String raw) {
    if (raw.isEmpty) return '';
    if (raw.trim().isEmpty) return '[space]';
    return raw.replaceAll(' ', '[space]');
  }

  static const TextStyle _style = TextStyle(
    fontSize: 15,
    color: _fieldText,
    height: 1.1,
    fontFamily: 'monospace',
  );

  static const TextStyle _idleStyle = TextStyle(
    fontSize: 11,
    color: _mutedText,
    height: 1,
  );

  static double _fieldWidthFor(String text, TextStyle style) {
    final visible = text.isEmpty ? ' ' : text;
    final painter = TextPainter(
      text: TextSpan(text: visible, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return (painter.width + 18).clamp(56.0, 260.0);
  }
}

