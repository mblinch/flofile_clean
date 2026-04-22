import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/date_formula.dart';
import '../caption_style/game_info.dart';
import '../services/current_user_service.dart';
import '../services/preferences_service.dart';
import 'date_formula_editor.dart';
import 'location_formula_editor.dart';

/// Same primary blue as [PreferencesDialog] (FTP / accents).
const Color _captionLayoutBlue = Color(0xFF0052CC);

/// Location / date editor panel surface (behind preview + formula editors).
const Color _locPanelSurface = Color(0xFFF5F6F8);
const Color _locChipBorder = Color(0x14000000);

/// Caption layout: wire preset or custom formula; preview uses fixed sample metadata.
class CaptionLayoutBuilderDialog extends StatefulWidget {
  const CaptionLayoutBuilderDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => const CaptionLayoutBuilderDialog(),
    );
  }

  @override
  State<CaptionLayoutBuilderDialog> createState() =>
      _CaptionLayoutBuilderDialogState();
}

class _CaptionLayoutBuilderDialogState extends State<CaptionLayoutBuilderDialog> {
  /// Sample city / date / venue for preview only (matches sample sentence in renderer).
  /// Photographer is resolved from the signed-in user at build time via
  /// [CurrentUserService]; agency is left blank so the renderer falls back to
  /// the selected wire style's sample label (e.g. Getty → "Getty Images").
  /// TODO: wire credit to the IPTC byline/credit fields once available.
  static final GameInfo _baseMockGameInfo = GameInfo(
    gameDate: DateTime(2026, 4, 4),
    city: 'Toronto',
    region: 'Ontario',
    country: 'Canada',
    countryCode: 'CAN',
    venue: 'BMO Field',
  );

  /// Fallback IPTC date samples when no folder import has populated prefs yet.
  static const Map<String, String> _mockIptcDates = {
    'DateTimeOriginal': '2026:04:04 14:30:00',
    'CreateDate': '2026:04:04 15:00:00',
    'DateCreated': '20260404',
  };

  /// Session [GameInfo] from prefs (updated when images are imported — EXIF date).
  GameInfo? _loadedGameInfo;

  /// Preview row: merge imported game/IPTC dates with static place/venue sample.
  GameInfo get _previewGameInfo {
    final snap = _loadedGameInfo;
    String pick(String a, String b) =>
        b.trim().isNotEmpty ? b : a;
    return _baseMockGameInfo.copyWith(
      gameDate: snap?.gameDate ?? _baseMockGameInfo.gameDate,
      city: snap != null ? pick(_baseMockGameInfo.city, snap.city) : _baseMockGameInfo.city,
      region: snap != null ? pick(_baseMockGameInfo.region, snap.region) : _baseMockGameInfo.region,
      regionCode: snap != null
          ? pick(_baseMockGameInfo.regionCode, snap.regionCode)
          : _baseMockGameInfo.regionCode,
      country: snap != null ? pick(_baseMockGameInfo.country, snap.country) : _baseMockGameInfo.country,
      countryCode: snap != null
          ? pick(_baseMockGameInfo.countryCode, snap.countryCode)
          : _baseMockGameInfo.countryCode,
      iptcMetadata: (snap != null && snap.iptcMetadata.isNotEmpty)
          ? snap.iptcMetadata
          : _mockIptcDates,
      photographerName: CurrentUserService.displayNameOrPlaceholder(),
      agencyName: '',
    );
  }

  late Future<void> _load;
  CaptionTemplate _template = CaptionTemplate.getty();
  CaptionTemplate _lastPreset = CaptionTemplate.getty();
  WireStyle _selectedWire = WireStyle.getty;
  bool _locationEditorOpen = false;
  bool _dateEditorOpen = false;
  int _captionSampleSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  final List<TextEditingController> _gapControllers = [];

  /// Structured date formula — drives the chip-based [DateFormulaEditor].
  /// Seeded from [_template.dateFormula] on load, or [DateFormula.ap] as fallback.
  DateFormula _dateFormula = DateFormula.ap();

  @override
  void initState() {
    super.initState();
    _load = _loadFromPrefs();
  }

  /// Rebuilds local editor state from [_template]. Called after prefs load and
  /// after a wire-style swap. Any legacy [CaptionTemplate.dateExpression] is
  /// discarded in favour of the structured formula (which is the only editor
  /// surface now).
  void _syncDateUiFromTemplate() {
    setState(() {
      if (_template.dateFormula != null) {
        _dateFormula = _template.dateFormula!.clone();
        if (_template.dateExpression.isNotEmpty) {
          _template = _template.copyWith(dateExpression: '');
        }
        return;
      }
      _dateFormula = DateFormula.ap();
      _template = _template.copyWith(
        dateFormula: _dateFormula.clone(),
        dateExpression: '',
      );
    });
  }

  /// Writes the current [_dateFormula] back into [_template].
  void _commitDateFormula(DateFormula next) {
    setState(() {
      _dateFormula = next;
      _template = _template.copyWith(
        dateFormula: next.clone(),
        dateExpression: '',
      );
    });
  }

  void _commitDateSource(DateFormulaSource source) {
    setState(() {
      _template = _template.copyWith(dateFormulaSource: source);
    });
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await PreferencesService.getInstance();
    final template = await prefs.getCaptionTemplate();
    final gameInfo = await prefs.getCaptionGameInfo();
    if (!mounted) return;
    setState(() {
      _loadedGameInfo = gameInfo;
      _template = template;
      _selectedWire = template.wireStyle;
      if (template.wireStyle == WireStyle.custom) {
        _lastPreset = CaptionTemplate.getty();
      } else {
        _lastPreset = _clonePreset(template);
      }
      _initGapControllers(_template);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
  }

  CreditSampleAgency _sampleAgencyForWire(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return CreditSampleAgency.gettyImages;
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
        return CreditSampleAgency.ap;
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  static const List<String> _wireStyleDropdownItems = [
    'Getty',
    'Imagn',
    'AP',
    'Custom',
  ];

  String _wireStyleDropdownLabel(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return 'Getty';
      case WireStyle.imagn:
        return 'Imagn';
      case WireStyle.ap:
        return 'AP';
      case WireStyle.custom:
        return 'Custom';
    }
  }

  WireStyle _wireStyleFromDropdownLabel(String? label) {
    switch (label) {
      case 'Imagn':
        return WireStyle.imagn;
      case 'AP':
        return WireStyle.ap;
      case 'Custom':
        return WireStyle.custom;
      case 'Getty':
      default:
        return WireStyle.getty;
    }
  }

  CaptionTemplate _clonePreset(CaptionTemplate t) {
    switch (t.wireStyle) {
      case WireStyle.getty:
        return CaptionTemplate.getty().copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          locationOptions: t.locationOptions,
          numberFormat: t.numberFormat,
          separator: t.separator,
          creditFormat: t.creditFormat,
        );
      case WireStyle.imagn:
        return CaptionTemplate.imagn().copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          locationOptions: t.locationOptions,
          numberFormat: t.numberFormat,
          separator: t.separator,
          creditFormat: t.creditFormat,
        );
      case WireStyle.ap:
        return CaptionTemplate.ap().copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          locationOptions: t.locationOptions,
          numberFormat: t.numberFormat,
          separator: t.separator,
          creditFormat: t.creditFormat,
        );
      case WireStyle.custom:
        return CaptionTemplate.getty();
    }
  }

  void _disposeGapControllers() {
    for (final c in _gapControllers) {
      c.dispose();
    }
    _gapControllers.clear();
  }

  void _initGapControllers(CaptionTemplate t) {
    _disposeGapControllers();
    final gaps = t.customSeparators ??
        CaptionFormulaRenderer.defaultCustomGaps(t);
    for (final g in gaps) {
      final c = TextEditingController(text: g);
      c.addListener(_onGapEdited);
      _gapControllers.add(c);
    }
  }

  void _onGapEdited() {
    setState(() {
      _template = _template.copyWith(
        customSeparators: _gapControllers.map((c) => c.text).toList(),
      );
    });
  }

  void _toggleLocationEditor() {
    setState(() {
      _locationEditorOpen = !_locationEditorOpen;
      if (_locationEditorOpen) _dateEditorOpen = false;
    });
  }

  void _toggleDateEditor() {
    setState(() {
      _dateEditorOpen = !_dateEditorOpen;
      if (_dateEditorOpen) _locationEditorOpen = false;
    });
  }

  void _commitLocationOptions(LocationLineOptions o) {
    setState(() => _template = _template.copyWith(locationOptions: o));
  }

  void _applyWireStyle(WireStyle w) {
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _disposeGapControllers();
      _selectedWire = w;
      switch (w) {
        case WireStyle.getty:
          _template = CaptionTemplate.getty();
          _lastPreset = CaptionTemplate.getty();
          break;
        case WireStyle.imagn:
          _template = CaptionTemplate.imagn();
          _lastPreset = CaptionTemplate.imagn();
          break;
        case WireStyle.ap:
          _template = CaptionTemplate.ap();
          _lastPreset = CaptionTemplate.ap();
          break;
        case WireStyle.custom:
          final ref = _lastPreset;
          _template = CaptionTemplate.custom(
            dateFormat: ref.dateFormat,
            dateExpression: ref.dateExpression,
            locationOptions: ref.locationOptions,
            numberFormat: ref.numberFormat,
            separator: ref.separator,
            creditFormat: ref.creditFormat,
            segmentOrder: List<CaptionSegment>.from(ref.segmentOrder),
            customSeparators: List<String>.from(
              CaptionFormulaRenderer.defaultCustomGaps(ref),
            ),
          );
          break;
      }
      _initGapControllers(_template);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
  }

  Future<void> _save() async {
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCaptionTemplate(_template);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _disposeGapControllers();
    super.dispose();
  }

  static String _pillEmoji(CaptionSegment s) {
    switch (s) {
      case CaptionSegment.location:
        return '📍';
      case CaptionSegment.date:
        return '📅';
      case CaptionSegment.caption:
        return '✏️';
      case CaptionSegment.venue:
        return '🏟';
      case CaptionSegment.credit:
        return '©';
    }
  }

  static String _pillShortLabel(CaptionSegment s) {
    switch (s) {
      case CaptionSegment.location:
        return 'Location';
      case CaptionSegment.date:
        return 'Date';
      case CaptionSegment.caption:
        return 'Caption';
      case CaptionSegment.venue:
        return 'Venue';
      case CaptionSegment.credit:
        return 'Credit';
    }
  }

  Widget _pill(
    CaptionSegment s, {
    bool highlight = false,
    Widget? trailing,
    VoidCallback? onRemove,
  }) {
    // Match [LocationFormulaEditor] / [DateFormulaEditor] field chip geometry (h28, r6, 11pt label).
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: highlight ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? Colors.grey.shade400 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(_pillEmoji(s), style: const TextStyle(fontSize: 14, height: 1)),
          const SizedBox(width: 4),
          Text(
            _pillShortLabel(s),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
              letterSpacing: -0.1,
              height: 1,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing,
          ],
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            _chipIconSquare(
              tooltip: 'Remove',
              onTap: onRemove,
              child: Icon(Icons.close, size: 9, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  /// Small rounded icon square matching the [LocationFormulaEditor] chip controls.
  Widget _chipIconSquare({
    required VoidCallback onTap,
    required Widget child,
    String? tooltip,
  }) {
    final btn = SizedBox(
      width: 14,
      height: 14,
      child: Material(
        color: Colors.white,
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

  Widget _segmentPill(CaptionSegment s) {
    final canRemove = _template.segmentOrder.length > 1;
    VoidCallback? onRemove =
        canRemove ? () => _removeSegment(s) : null;
    if (s == CaptionSegment.location) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleLocationEditor,
          borderRadius: BorderRadius.circular(6),
          child: _pill(
            s,
            highlight: _locationEditorOpen,
            trailing: Icon(Icons.tune, size: 14, color: Colors.grey.shade600),
            onRemove: onRemove,
          ),
        ),
      );
    }
    if (s == CaptionSegment.date) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleDateEditor,
          borderRadius: BorderRadius.circular(6),
          child: _pill(
            s,
            highlight: _dateEditorOpen,
            trailing: Icon(Icons.tune, size: 14, color: Colors.grey.shade600),
            onRemove: onRemove,
          ),
        ),
      );
    }
    return _pill(s, onRemove: onRemove);
  }

  /// Remove [seg] from the formula. Closes its editor if open. Keeps
  /// [customSeparators] aligned by dropping the matching entry.
  void _removeSegment(CaptionSegment seg) {
    final order = _template.segmentOrder;
    final idx = order.indexOf(seg);
    if (idx < 0 || order.length <= 1) return;
    setState(() {
      if (seg == CaptionSegment.location) _locationEditorOpen = false;
      if (seg == CaptionSegment.date) _dateEditorOpen = false;

      final newOrder = List<CaptionSegment>.from(order)..removeAt(idx);

      List<String>? newSeps = _template.customSeparators;
      if (newSeps != null) {
        final list = List<String>.from(newSeps);
        // Drop the separator adjacent to the removed segment (prefer trailing).
        final sepIdx = idx < list.length ? idx : list.length - 1;
        if (sepIdx >= 0 && sepIdx < list.length) list.removeAt(sepIdx);
        newSeps = list;
      }

      _template = _template.copyWith(
        segmentOrder: newOrder,
        customSeparators: newSeps,
      );
      _initGapControllers(_template);
    });
  }

  /// Add a previously-removed [seg] to the end of the formula.
  void _addSegment(CaptionSegment seg) {
    final order = _template.segmentOrder;
    if (order.contains(seg)) return;
    setState(() {
      final newOrder = List<CaptionSegment>.from(order)..add(seg);

      List<String>? newSeps = _template.customSeparators;
      if (newSeps != null) {
        final list = List<String>.from(newSeps)..add(' ');
        newSeps = list;
      }

      _template = _template.copyWith(
        segmentOrder: newOrder,
        customSeparators: newSeps,
      );
      _initGapControllers(_template);
    });
  }

  /// Popup "+" button that lists the segments not currently in the formula.
  Widget _addSegmentButton() {
    const allSegments = CaptionSegment.values;
    final missing = allSegments
        .where((s) => !_template.segmentOrder.contains(s))
        .toList();
    if (missing.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<CaptionSegment>(
      tooltip: 'Add segment',
      position: PopupMenuPosition.under,
      onSelected: _addSegment,
      itemBuilder: (context) => [
        for (final s in missing)
          PopupMenuItem<CaptionSegment>(
            value: s,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_pillEmoji(s), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  _pillShortLabel(s),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationOptionsEditor() {
    final previewLocation = CaptionFormulaRenderer.formatLocationLine(
      _previewGameInfo,
      _template.locationOptions,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _locChipBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'LOCATION PREVIEW',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  previewLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.3,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        LocationFormulaEditor(
          options: _template.locationOptions,
          onChanged: _commitLocationOptions,
        ),
      ],
    );
  }

  /// Compact separator field that sits inline with chips (matches chip height).
  Widget _gapField(TextEditingController controller) {
    return _GapSeparatorField(controller: controller);
  }

  Widget _dateLineEditor() {
    final datePreview = CaptionFormulaRenderer.formatTemplateDateLine(
      _previewGameInfo,
      _template,
      uppercaseAll: false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _locChipBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'DATE PREVIEW',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  datePreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.3,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DateFormulaEditor(
          formula: _dateFormula,
          onChanged: _commitDateFormula,
          source: _template.dateFormulaSource,
          onSourceChanged: _commitDateSource,
        ),
      ],
    );
  }

  Widget _formulaRow() {
    final order = _template.segmentOrder;
    final children = <Widget>[];
    for (var i = 0; i < order.length; i++) {
      children.add(_segmentPill(order[i]));
      if (i < order.length - 1 && i < _gapControllers.length) {
        children.add(_gapField(_gapControllers[i]));
      }
    }
    final addBtn = _addSegmentButton();
    if (addBtn is! SizedBox) children.add(addBtn);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 3,
      runSpacing: 4,
      children: children,
    );
  }

  Widget _shuffleCaptionButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _captionSampleSeed =
                (_captionSampleSeed * 1103515245 + 12345) & 0x7fffffff;
          });
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shuffle, size: 12, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(
                'Shuffle',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle get _sectionTitleStyle => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade900,
        letterSpacing: -0.15,
      );

  @override
  Widget build(BuildContext context) {
    final sampleCaption = CaptionFormulaRenderer.randomSinglePlayerCaption(
      _template.numberFormat,
      seed: _captionSampleSeed,
    );
    final preview = CaptionFormulaRenderer.render(
      template: _template,
      game: _previewGameInfo,
      sampleAgency: _sampleAgencyForWire(_selectedWire),
      captionOverride: sampleCaption,
    );

    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.88;
    final dialogHeight = maxH.clamp(300.0, 520.0);
    // Size to the viewport (minus the insetPadding) up to a sensible cap so
    // the token row, separators, and add-fields buttons all fit on one line
    // on typical desktop widths without going edge-to-edge on very wide ones.
    final dialogWidth = (mq.width - 32).clamp(320.0, 840.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Caption Layout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<void>(
                  future: _load,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return SizedBox(
                        height: 120,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _captionLayoutBlue,
                            ),
                          ),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('Caption Style', style: _sectionTitleStyle),
                                const SizedBox(width: 3),
                                SizedBox(
                                  width: 174,
                                  child: DropdownFlutter<String>(
                                  key: ValueKey<String>(_selectedWire.name),
                                  hintText: 'Caption Style',
                                items: _wireStyleDropdownItems,
                                initialItem: _wireStyleDropdownLabel(_selectedWire),
                                overlayHeight: 124,
                                closedHeaderPadding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                expandedHeaderPadding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                listItemPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: CustomDropdownDecoration(
                                  closedFillColor: Colors.white,
                                  expandedFillColor: Colors.white,
                                  closedBorder: Border.all(color: Colors.grey.shade300),
                                  expandedBorder: Border.all(
                                    color: _captionLayoutBlue.withValues(alpha: 0.45),
                                    width: 1,
                                  ),
                                  closedBorderRadius: BorderRadius.circular(4),
                                  expandedBorderRadius: BorderRadius.circular(6),
                                  closedShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                  expandedShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  hintStyle: TextStyle(
                                    fontSize: 8,
                                    color: Colors.grey.shade500,
                                  ),
                                  headerStyle: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade900,
                                  ),
                                  listItemStyle: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade800,
                                  ),
                                  listItemDecoration: ListItemDecoration(
                                    selectedColor: const Color(0xFFEAF2FF),
                                  ),
                                  closedSuffixIcon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  expandedSuffixIcon: Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 14,
                                    color: _captionLayoutBlue,
                                  ),
                                ),
                                    onChanged: (label) {
                                      if (label == null) return;
                                      _applyWireStyle(_wireStyleFromDropdownLabel(label));
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Preview',
                                style: _sectionTitleStyle.copyWith(fontSize: 11),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(randomly generated)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const Spacer(),
                              _shuffleCaptionButton(),
                            ],
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: SelectableText(
                                preview,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 4),
                            child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              color: _locPanelSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Caption Formula', style: _sectionTitleStyle),
                                const SizedBox(height: 4),
                                _formulaRow(),
                                if (_dateEditorOpen) ...[
                                  const SizedBox(height: 6),
                                  _dateLineEditor(),
                                ],
                                if (_locationEditorOpen) ...[
                                  const SizedBox(height: 6),
                                  _locationOptionsEditor(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _captionLayoutBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _save,
                      child: const Text('Save', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow separator field used between caption-formula chips.
///
/// Draws its own border so height/centering are deterministic (TextField with
/// an [OutlineInputBorder] plus isDense renders at an awkward height that
/// clashes with the 28px chip row).
class _GapSeparatorField extends StatefulWidget {
  const _GapSeparatorField({required this.controller});

  final TextEditingController controller;

  @override
  State<_GapSeparatorField> createState() => _GapSeparatorFieldState();
}

class _GapSeparatorFieldState extends State<_GapSeparatorField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Container(
      width: 44,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: focused ? _captionLayoutBlue : Colors.grey.shade300,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade800,
            height: 1.1,
          ),
          decoration: const InputDecoration(
            isDense: true,
            isCollapsed: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
