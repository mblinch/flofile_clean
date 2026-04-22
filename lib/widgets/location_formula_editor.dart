import 'package:flutter/material.dart';

import '../caption_style/caption_template.dart';

/// Matches the caption layout dialog's accent blue.
const Color _editorBlue = Color(0xFF0052CC);

/// Neutral surface used by the chip / panel (matches existing caption editor chips).
const Color _chipSurface = Color(0xFFF4F4F5);
const Color _chipBorder = Color(0x14000000);
const Color _fieldText = Color(0xFF3A3A3A);

/// Active state for the ALL CAPS (Aa) control only; chip fill stays neutral.
const Color _capsButtonBg = Color(0xFFD0E3FA);

/// Structured, chip-based location line builder.
///
/// Same visual / interaction model as the date formula editor: each geo field
/// (city / region / country) is a draggable chip and the literal text between
/// fields lives in fixed-width separator boxes (leading + one between each pair
/// + trailing). Internally we parse the persisted
/// [LocationLineOptions.chips] list into a (fields, separators) tuple, let the
/// user mutate that, then serialize it back to literal / geo chips when we
/// emit [onChanged].
class LocationFormulaEditor extends StatefulWidget {
  const LocationFormulaEditor({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final LocationLineOptions options;
  final ValueChanged<LocationLineOptions> onChanged;

  @override
  State<LocationFormulaEditor> createState() => _LocationFormulaEditorState();
}

class _LocField {
  _LocField({
    required this.kind,
    required this.caps,
    required this.id,
    this.countryVariant = LocationCountryVariant.fullName,
    this.regionVariant = LocationRegionVariant.fullName,
  });
  final LocationChipKind kind;
  bool caps;
  final String id;
  LocationCountryVariant countryVariant;
  LocationRegionVariant regionVariant;
}

class _LocationFormulaEditorState extends State<LocationFormulaEditor> {
  int? _hoverIndex;
  int _idSeq = 0;

  /// The geo fields in order.
  late List<_LocField> _fields;

  /// Literal text between / around fields — length == fields.length + 1.
  late List<String> _separators;

  @override
  void initState() {
    super.initState();
    _parseFromOptions();
  }

  @override
  void didUpdateWidget(covariant LocationFormulaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.options, widget.options)) {
      _parseFromOptions();
    }
  }

  void _parseFromOptions() {
    final fields = <_LocField>[];
    final seps = <String>[];
    final buf = StringBuffer();
    for (final c in widget.options.chips) {
      if (c.kind == LocationChipKind.literal) {
        buf.write(c.literal);
      } else {
        seps.add(buf.toString());
        buf.clear();
        fields.add(_LocField(
          kind: c.kind,
          caps: c.caps,
          id: c.id,
          countryVariant: c.kind == LocationChipKind.country
              ? c.countryVariant
              : LocationCountryVariant.fullName,
          regionVariant: c.kind == LocationChipKind.region
              ? c.regionVariant
              : LocationRegionVariant.fullName,
        ));
      }
    }
    seps.add(buf.toString());
    _fields = fields;
    _separators = seps;
  }

  String _newId(String prefix) {
    _idSeq++;
    return '${prefix}_lfe_${DateTime.now().microsecondsSinceEpoch}_$_idSeq';
  }

  /// Convert current in-memory (fields, separators) → canonical
  /// [LocationLineOptions.chips] list and emit to the parent.
  void _emit() {
    final out = <LocationChip>[];
    for (var i = 0; i < _fields.length; i++) {
      final sep = _separators[i];
      if (sep.isNotEmpty) {
        out.add(LocationChip(
          id: _newId('lit'),
          kind: LocationChipKind.literal,
          literal: sep,
        ));
      }
      out.add(LocationChip(
        id: _fields[i].id,
        kind: _fields[i].kind,
        caps: _fields[i].caps,
        countryVariant: _fields[i].kind == LocationChipKind.country
            ? _fields[i].countryVariant
            : LocationCountryVariant.fullName,
        regionVariant: _fields[i].kind == LocationChipKind.region
            ? _fields[i].regionVariant
            : LocationRegionVariant.fullName,
      ));
    }
    final trail = _separators.last;
    if (trail.isNotEmpty) {
      out.add(LocationChip(
        id: _newId('lit'),
        kind: LocationChipKind.literal,
        literal: trail,
      ));
    }
    widget.onChanged(widget.options.copyWith(
      uppercase: false,
      chips: out,
    ));
  }

  // -- Mutations -------------------------------------------------------------

  void _setSeparator(int i, String value) {
    setState(() => _separators[i] = value);
    _emit();
  }

  void _toggleCaps(int i) {
    setState(() => _fields[i].caps = !_fields[i].caps);
    _emit();
  }

  void _setCountryVariant(int i, LocationCountryVariant v) {
    setState(() => _fields[i].countryVariant = v);
    _emit();
  }

  void _setRegionVariant(int i, LocationRegionVariant v) {
    setState(() => _fields[i].regionVariant = v);
    _emit();
  }

  void _removeField(int i) {
    if (i < 0 || i >= _fields.length) return;
    setState(() {
      _fields.removeAt(i);
      final merged = _separators[i] + _separators[i + 1];
      _separators
        ..removeAt(i + 1)
        ..removeAt(i);
      _separators.insert(i, merged);
    });
    _emit();
  }

  void _addField(LocationChipKind kind) {
    if (_hasField(kind)) return;
    setState(() {
      _fields.add(_LocField(
        kind: kind,
        caps: false,
        id: _newId(kind.name),
      ));
      _separators.add('');
    });
    _emit();
  }

  bool _hasField(LocationChipKind kind) =>
      _fields.any((f) => f.kind == kind);

  void _reorder(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    if (fromIndex < 0 || fromIndex >= _fields.length) return;
    setState(() {
      final chip = _fields.removeAt(fromIndex);
      final trailing = _separators.removeAt(fromIndex + 1);
      var insert = targetIndex;
      if (fromIndex < targetIndex) insert = targetIndex - 1;
      if (insert < 0) insert = 0;
      if (insert > _fields.length) insert = _fields.length;
      _fields.insert(insert, chip);
      _separators.insert(insert + 1, trailing);
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
        _addFieldsRow(),
      ],
    );
  }

  Widget _tokenRow() {
    final children = <Widget>[];
    for (var i = 0; i < _fields.length; i++) {
      children.add(_separatorInput(i));
      children.add(_fieldChip(i));
    }
    children.add(_separatorInput(_fields.length));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _chipBorder),
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

  Widget _separatorInput(int index) {
    return _LocSeparatorInput(
      key: ValueKey('loc-sep-$index-${_separators[index]}'),
      initialValue: _separators[index],
      onChanged: (v) => _setSeparator(index, v),
    );
  }

  Widget _fieldChip(int index) {
    final f = _fields[index];
    final isCaps = f.caps;
    final isHovered = _hoverIndex == index;

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
              _locationFieldLabel(f.kind),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _fieldText,
                height: 1,
              ),
            ),
            if (f.kind == LocationChipKind.country) ...[
              const SizedBox(width: 4),
              _CountryVariantGearButton(
                current: f.countryVariant,
                onSelect: (v) => _setCountryVariant(index, v),
              ),
            ],
            if (f.kind == LocationChipKind.region) ...[
              const SizedBox(width: 4),
              _RegionVariantGearButton(
                current: f.regionVariant,
                onSelect: (v) => _setRegionVariant(index, v),
              ),
            ],
            const SizedBox(width: 6),
            _chipIconButton(
              tooltip: 'ALL CAPS',
              onTap: () => _toggleCaps(index),
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
              _ghostButton(
                label: 'City',
                enabled: !_hasField(LocationChipKind.city),
                onTap: () => _addField(LocationChipKind.city),
              ),
              _ghostButton(
                label: 'State/Province',
                enabled: !_hasField(LocationChipKind.region),
                onTap: () => _addField(LocationChipKind.region),
              ),
              _ghostButton(
                label: 'Country',
                enabled: !_hasField(LocationChipKind.country),
                onTap: () => _addField(LocationChipKind.country),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ghostButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
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
      ),
    );
  }
}

/// Same interaction model as [DateFormulaEditor]’s format gear: overlay card, not [PopupMenuButton].
class _CountryVariantGearButton extends StatefulWidget {
  const _CountryVariantGearButton({
    required this.current,
    required this.onSelect,
  });

  final LocationCountryVariant current;
  final ValueChanged<LocationCountryVariant> onSelect;

  @override
  State<_CountryVariantGearButton> createState() =>
      _CountryVariantGearButtonState();
}

class _CountryVariantGearButtonState extends State<_CountryVariantGearButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  bool get _open => _entry != null;
  bool get _iso => widget.current == LocationCountryVariant.isoCode;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
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
                child: _CountryVariantOptionsCard(
                  current: widget.current,
                  onPick: (v) {
                    widget.onSelect(v);
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
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bg = (_open || _iso) ? const Color(0xFFEAF2FF) : Colors.white;
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message:
            'Country: ${locationCountryVariantLabel(widget.current)}',
        child: SizedBox(
          width: 18,
          height: 18,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: _open ? _editorBlue : Colors.grey.shade300,
                width: _open ? 1.4 : 1,
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

class _CountryVariantOptionsCard extends StatelessWidget {
  const _CountryVariantOptionsCard({
    required this.current,
    required this.onPick,
  });

  final LocationCountryVariant current;
  final ValueChanged<LocationCountryVariant> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 212,
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
              'COUNTRY FIELD',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _row(
            LocationCountryVariant.fullName,
            hint: 'Full',
          ),
          _row(
            LocationCountryVariant.isoCode,
            hint: 'ISO',
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _row(LocationCountryVariant value, {required String hint}) {
    final selected = current == value;
    return InkWell(
      onTap: () => onPick(value),
      child: Container(
        color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                locationCountryVariantLabel(value),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _editorBlue : _fieldText,
                ),
              ),
            ),
            Text(
              hint,
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

/// State/Province: full name vs short (CA, Ont., …) — same overlay UX as country gear.
class _RegionVariantGearButton extends StatefulWidget {
  const _RegionVariantGearButton({
    required this.current,
    required this.onSelect,
  });

  final LocationRegionVariant current;
  final ValueChanged<LocationRegionVariant> onSelect;

  @override
  State<_RegionVariantGearButton> createState() =>
      _RegionVariantGearButtonState();
}

class _RegionVariantGearButtonState extends State<_RegionVariantGearButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  bool get _open => _entry != null;
  bool get _short => widget.current == LocationRegionVariant.shortForm;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _close();
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
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
                child: _RegionVariantOptionsCard(
                  current: widget.current,
                  onPick: (v) {
                    widget.onSelect(v);
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
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bg = (_open || _short) ? const Color(0xFFEAF2FF) : Colors.white;
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message:
            'State/Province: ${locationRegionVariantLabel(widget.current)}',
        child: SizedBox(
          width: 18,
          height: 18,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: _open ? _editorBlue : Colors.grey.shade300,
                width: _open ? 1.4 : 1,
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

class _RegionVariantOptionsCard extends StatelessWidget {
  const _RegionVariantOptionsCard({
    required this.current,
    required this.onPick,
  });

  final LocationRegionVariant current;
  final ValueChanged<LocationRegionVariant> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
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
              'STATE / PROVINCE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _row(LocationRegionVariant.fullName, hint: 'Full'),
          _row(LocationRegionVariant.shortForm, hint: 'Abbr'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _row(LocationRegionVariant value, {required String hint}) {
    final selected = current == value;
    return InkWell(
      onTap: () => onPick(value),
      child: Container(
        color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                locationRegionVariantLabel(value),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _editorBlue : _fieldText,
                ),
              ),
            ),
            Text(
              hint,
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

String _locationFieldLabel(LocationChipKind k) {
  switch (k) {
    case LocationChipKind.city:
      return 'City';
    case LocationChipKind.region:
      return 'State/Province';
    case LocationChipKind.country:
      return 'Country';
    case LocationChipKind.literal:
      return 'Literal';
  }
}

/// Fixed-size separator text field — mirrors the date editor's separator box.
class _LocSeparatorInput extends StatefulWidget {
  const _LocSeparatorInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_LocSeparatorInput> createState() => _LocSeparatorInputState();
}

class _LocSeparatorInputState extends State<_LocSeparatorInput> {
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
    final borderColor =
        _focused ? _editorBlue : Colors.grey.shade300;
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
