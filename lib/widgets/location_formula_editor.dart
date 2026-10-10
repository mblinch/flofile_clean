import 'package:flutter/material.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/game_info.dart';
import '../caption_style/region_abbrev.dart';
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

/// All geo field kinds the editor exposes, in the canonical order they appear
/// when an existing template hasn't placed them yet.
const List<LocationChipKind> _allGeoKinds = [
  LocationChipKind.city,
  LocationChipKind.region,
  LocationChipKind.country,
];

/// Structured, single-line location editor.
///
/// Every supported geo field (City, State/Province, Country) is always shown
/// as a chip. A switch on each chip toggles whether that field appears in the
/// rendered caption. Between every pair of adjacent chips sits a small
/// separator field that owns the literal text printed between them. Each chip
/// has a leading drag handle (the ⋮⋮ icon); click + drag from there to reorder
/// — the rest of the chip stays interactive so the toggle / caps / gear stay
/// clickable. A live preview line at the bottom shows the resulting
/// geographical string using the host's sample [GameInfo] (or a hard-coded
/// Toronto/Ontario/Canada example when none is provided).
class LocationFormulaEditor extends StatefulWidget {
  const LocationFormulaEditor({
    super.key,
    required this.options,
    required this.onChanged,
    this.sampleGameInfo,
    this.adaptsUsIntl = false,
  });

  final LocationLineOptions options;
  final ValueChanged<LocationLineOptions> onChanged;

  /// Drives the inline sample text on each chip and the bottom preview line.
  /// Falls back to canonical Toronto / Ontario / Canada values when null or
  /// the corresponding field is empty.
  final GameInfo? sampleGameInfo;

  /// Getty (and any layout with auto-adapt) writes City, State in the US and
  /// City, Country everywhere else, even though both chips stay in the editor.
  final bool adaptsUsIntl;

  @override
  State<LocationFormulaEditor> createState() => _LocationFormulaEditorState();
}

class _LocField {
  _LocField({
    required this.kind,
    required this.id,
    this.enabled = true,
    this.caps = false,
    this.countryVariant = LocationCountryVariant.fullName,
    this.regionVariant = LocationRegionVariant.fullName,
  });
  final LocationChipKind kind;
  final String id;
  bool enabled;
  bool caps;
  LocationCountryVariant countryVariant;
  LocationRegionVariant regionVariant;
}

class _LocationFormulaEditorState extends State<LocationFormulaEditor> {
  int _idSeq = 0;

  /// Geo fields in display order. Always contains exactly one entry per kind
  /// in [_allGeoKinds]; missing kinds are appended at the end as disabled.
  late List<_LocField> _fields;

  /// Literal text around fields. Length is always `_fields.length + 1`.
  /// `_separators[0]` is before the first field, `_separators[i + 1]`
  /// follows `_fields[i]`, and the final entry is after the last field.
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

  /// Build [_fields] / [_separators] from the persisted chip list. Geo chips
  /// are taken in their saved order with their saved enabled/caps/variant.
  /// Literal chips collapse into separator slots around the geo chips.
  void _parseFromOptions() {
    final fields = <_LocField>[];
    final seps = <String>[];
    final pendingLit = StringBuffer();
    for (final c in widget.options.chips) {
      if (c.kind == LocationChipKind.literal) {
        pendingLit.write(c.literal);
        continue;
      }
      seps.add(pendingLit.toString());
      pendingLit.clear();
      fields.add(_LocField(
        kind: c.kind,
        id: c.id,
        enabled: c.enabled,
        caps: c.caps,
        countryVariant: c.kind == LocationChipKind.country
            ? c.countryVariant
            : LocationCountryVariant.fullName,
        regionVariant: c.kind == LocationChipKind.region
            ? c.regionVariant
            : LocationRegionVariant.fullName,
      ));
    }

    // Append disabled placeholders for any geo kinds not already present, so
    // the user can toggle them on without ever needing an "Add field" button.
    final present = fields.map((f) => f.kind).toSet();
    for (final k in _allGeoKinds) {
      if (!present.contains(k)) {
        if (fields.isEmpty) {
          seps.add('');
        } else {
          seps.add(_defaultSeparator(k));
        }
        fields.add(_LocField(
          kind: k,
          id: _newId(k.name),
          enabled: false,
        ));
      }
    }
    seps.add(pendingLit.toString());

    _fields = fields;
    _separators = seps;
  }

  String _defaultSeparator(LocationChipKind incomingKind) => ', ';

  String _newId(String prefix) {
    _idSeq++;
    return '${prefix}_lfe_${DateTime.now().microsecondsSinceEpoch}_$_idSeq';
  }

  /// Convert the current (fields, separators) state back to the canonical
  /// [LocationLineOptions.chips] list and emit it to the parent.
  void _emit() {
    widget.onChanged(_currentOptions());
  }

  LocationLineOptions _currentOptions() {
    final out = <LocationChip>[];
    for (var i = 0; i < _fields.length; i++) {
      final sep = i < _separators.length ? _separators[i] : '';
      if (sep.isNotEmpty) {
        out.add(LocationChip(
          id: _newId('lit'),
          kind: LocationChipKind.literal,
          literal: sep,
        ));
      }
      final f = _fields[i];
      out.add(LocationChip(
        id: f.id,
        kind: f.kind,
        enabled: f.enabled,
        caps: f.caps,
        countryVariant: f.kind == LocationChipKind.country
            ? f.countryVariant
            : LocationCountryVariant.fullName,
        regionVariant: f.kind == LocationChipKind.region
            ? f.regionVariant
            : LocationRegionVariant.fullName,
      ));
    }
    final trailing =
        _fields.length < _separators.length ? _separators[_fields.length] : '';
    if (trailing.isNotEmpty) {
      out.add(LocationChip(
        id: _newId('lit'),
        kind: LocationChipKind.literal,
        literal: trailing,
      ));
    }
    return widget.options.copyWith(
      uppercase: false,
      chips: out,
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

  void _setCountryVariant(int i, LocationCountryVariant v) {
    setState(() => _fields[i].countryVariant = v);
    _emit();
  }

  void _setRegionVariant(int i, LocationRegionVariant v) {
    setState(() => _fields[i].regionVariant = v);
    _emit();
  }

  void _reorder(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    if (fromIndex < 0 || fromIndex >= _fields.length) return;
    if (targetIndex < 0 || targetIndex >= _fields.length) return;
    setState(() {
      final f = _fields.removeAt(fromIndex);
      // "Drop chip X onto chip Y" semantic: X lands AT Y's slot in the
      // post-removal list (length N-1), and the chips between fromIndex and
      // targetIndex shift to fill the gap. Do NOT subtract 1 when moving
      // right — that biases the insertion to the slot *before* Y, which
      // makes right-direction drags look like a no-op (A drops next to its
      // own former position instead of crossing past Y).
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
        _separators.add(', ');
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
        if (widget.adaptsUsIntl || widget.options.autoAdaptUsIntl) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              'United States games use City, State. Games everywhere else use City, Country. Both chips stay here; the caption picks one from the game’s country.',
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: _mutedText,
              ),
            ),
          ),
        ],
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
              label: _locationFieldLabel(_fields[i].kind),
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
    return _LocSeparatorInput(
      // Stable key: must NOT include the current value, otherwise the widget
      // gets thrown away and rebuilt on every keystroke, which both loses
      // focus (you'd have to click again to keep typing) and causes macOS to
      // ring the system bell when an unfocused backspace bubbles to the OS.
      key: ValueKey('loc-sep-$gapIndex'),
      value: _separators[gapIndex],
      onChanged: (v) => _setSeparator(gapIndex, v),
    );
  }

  Widget _fieldChip(int index) {
    final f = _fields[index];
    final sampleRaw = _sampleValueFor(f);
    final sample = CaptionFormulaRenderer.applyLocationChipCaps(
      sampleRaw,
      caps: f.caps,
      isIsoCode: (f.kind == LocationChipKind.country &&
              f.countryVariant == LocationCountryVariant.isoCode) ||
          (f.kind == LocationChipKind.region &&
              f.regionVariant == LocationRegionVariant.shortForm),
    );
    final enabled = f.enabled;

    // Body content of the chip excluding the drag handle. Built as a builder
    // because we need two copies: the live one (interactive) and the
    // floating drag-feedback image (frozen / non-interactive).
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
                _locationFieldLabel(f.kind),
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
              if (f.kind == LocationChipKind.country) ...[
                const SizedBox(width: 6),
                _CountryVariantGearButton(
                  current: f.countryVariant,
                  onSelect: (v) => _setCountryVariant(index, v),
                ),
              ],
              if (f.kind == LocationChipKind.region) ...[
                const SizedBox(width: 6),
                _RegionVariantGearButton(
                  current: f.regionVariant,
                  onSelect: (v) => _setRegionVariant(index, v),
                ),
              ],
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

    // The drag handle has two visual states: a static icon (used inside the
    // floating drag feedback) and the live one wrapped in [Draggable] so it
    // becomes the immediate drag source on mouse / touch.
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
          side: BorderSide(color: _chipBorder),
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
    final sample = widget.sampleGameInfo ?? _fallbackSampleGameInfo();
    final rendered = CaptionFormulaRenderer.formatLocationLine(
      sample,
      _currentOptions(),
    );
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

  String _sampleValueFor(_LocField f) {
    final g = widget.sampleGameInfo;
    switch (f.kind) {
      case LocationChipKind.city:
        final v = (g?.city ?? '').trim();
        return v.isNotEmpty ? v : 'Toronto';
      case LocationChipKind.region:
        final full = (g?.resolvedRegionName ?? '').trim();
        final short = (g?.resolvedRegionShort ?? '').trim();
        switch (f.regionVariant) {
          case LocationRegionVariant.fullName:
            if (full.isNotEmpty) return full;
            if (short.isNotEmpty) return short;
            return 'Ontario';
          case LocationRegionVariant.shortForm:
            if (short.isNotEmpty) return short;
            if (full.isNotEmpty) return full;
            return 'ON';
          case LocationRegionVariant.apStyle:
            if (full.isNotEmpty) {
              final ap = abbreviateUsStateApStyle(full);
              return ap.isNotEmpty ? ap : full;
            }
            if (short.isNotEmpty) return short;
            return 'Ont.';
        }
      case LocationChipKind.country:
        final full = (g?.resolvedCountryName ?? '').trim();
        final iso = (g?.resolvedCountryCode ?? '').trim();
        switch (f.countryVariant) {
          case LocationCountryVariant.fullName:
            if (full.isNotEmpty) return full;
            if (iso.isNotEmpty) return iso;
            return 'Canada';
          case LocationCountryVariant.isoCode:
            if (iso.isNotEmpty) return iso;
            if (full.isNotEmpty) return full;
            return 'CAN';
        }
      case LocationChipKind.literal:
        return '';
    }
  }

  GameInfo _fallbackSampleGameInfo() {
    return const GameInfo(
      city: 'Toronto',
      region: 'Ontario',
      regionCode: 'ON',
      country: 'Canada',
      countryCode: 'CAN',
    );
  }
}

/// Same interaction model as [DateFormulaEditor]'s format gear: overlay card, not [PopupMenuButton].
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
    final bg = (_open || _iso) ? FfTokens.nocturneAccentSoft : _chipSurface;
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: 'Country: ${locationCountryVariantLabel(widget.current)}',
        child: SizedBox(
          width: 18,
          height: 18,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: _open ? _editorBlue : _chipBorder,
                width: _open ? 1.4 : 1,
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
        color: FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _chipBorder),
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
                color: _mutedText,
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
        color: selected ? FfTokens.nocturneAccentSoft : Colors.transparent,
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
                color: _mutedText,
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
    final bg = (_open || _short) ? FfTokens.nocturneAccentSoft : _chipSurface;
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
                color: _open ? _editorBlue : _chipBorder,
                width: _open ? 1.4 : 1,
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
      width: 272,
      decoration: BoxDecoration(
        color: FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _chipBorder),
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
                color: _mutedText,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _row(LocationRegionVariant.fullName, hint: 'Full'),
          _row(LocationRegionVariant.shortForm, hint: 'Abbr'),
          _row(LocationRegionVariant.apStyle, hint: 'AP'),
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
        color: selected ? FfTokens.nocturneAccentSoft : Colors.transparent,
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
                color: _mutedText,
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
      return 'IPTC:City';
    case LocationChipKind.region:
      return 'IPTC:ProvinceState';
    case LocationChipKind.country:
      return 'IPTC:Country';
    case LocationChipKind.literal:
      return 'Literal';
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
class _LocSeparatorInput extends StatefulWidget {
  const _LocSeparatorInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The current separator text. The widget owns its own [TextEditingController]
  /// so it doesn't reset on parent rebuilds; [didUpdateWidget] resyncs the
  /// controller text when [value] changes externally (e.g. after a reorder)
  /// and the field is not focused.
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_LocSeparatorInput> createState() => _LocSeparatorInputState();
}

class _LocSeparatorInputState extends State<_LocSeparatorInput> {
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
  void didUpdateWidget(covariant _LocSeparatorInput oldWidget) {
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
