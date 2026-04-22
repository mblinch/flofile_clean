import 'dart:async';
import 'dart:convert';

import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/date_formula.dart';
import '../caption_style/game_info.dart';
import '../services/current_user_service.dart';
import '../services/preferences_service.dart';
import 'app_compact_checkbox.dart';
import 'date_formula_editor.dart';
import 'location_formula_editor.dart';

/// Same primary blue as [PreferencesDialog] (FTP / accents).
const Color _captionLayoutBlue = Color(0xFF0052CC);

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

class _CaptionLayoutBuilderDialogState
    extends State<CaptionLayoutBuilderDialog> {
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
    String pick(String a, String b) => b.trim().isNotEmpty ? b : a;
    return _baseMockGameInfo.copyWith(
      gameDate: snap?.gameDate ?? _baseMockGameInfo.gameDate,
      city: snap != null
          ? pick(_baseMockGameInfo.city, snap.city)
          : _baseMockGameInfo.city,
      region: snap != null
          ? pick(_baseMockGameInfo.region, snap.region)
          : _baseMockGameInfo.region,
      regionCode: snap != null
          ? pick(_baseMockGameInfo.regionCode, snap.regionCode)
          : _baseMockGameInfo.regionCode,
      country: snap != null
          ? pick(_baseMockGameInfo.country, snap.country)
          : _baseMockGameInfo.country,
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

  /// User-saved baselines when switching wires (see [PreferencesService] wire defaults).
  CaptionTemplate? _gettyWireDefault;
  CaptionTemplate? _imagnWireDefault;
  CaptionTemplate? _apWireDefault;
  CaptionTemplate? _gettyIntlWireDefault;

  /// Custom labels shown in the Caption Style dropdown for built-in wires.
  /// `null` means “use factory name (Getty / Imagn / AP / Getty International)”.
  String? _gettyWireLabel;
  String? _imagnWireLabel;
  String? _apWireLabel;
  String? _gettyIntlWireLabel;
  WireStyle _selectedWire = WireStyle.getty;
  bool _locationEditorOpen = false;
  bool _dateEditorOpen = false;
  bool _captionPreviewSelected = false;
  bool _venuePreviewSelected = false;
  bool _bylinePreviewSelected = false;
  int? _activeFormulaIndex;

  /// Which formula separator field (index in [customSeparators]) has focus.
  int? _focusedGapIndex;
  int _captionSampleSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  bool _prefsLoaded = false;
  String _lastSavedTemplateSnapshot = '';
  Timer? _autosaveDebounce;
  bool _renameCaptionStylePromptOpen = false;
  TextEditingController? _renameCaptionStyleNameCtrl;
  List<CaptionStyleLibraryEntry> _captionStyleLibrary = const [];

  /// Caption screen: Personality / Keywords visibility (same prefs as Preferences dialog).
  bool _showKeywordsField = false;
  bool _showPersonalityField = true;

  /// When set, the dropdown shows this library entry; cleared for wire presets.
  String? _selectedSavedStyleId;

  static const String _menuTokGetty = 'wire:getty';
  static const String _menuTokImagn = 'wire:imagn';
  static const String _menuTokAp = 'wire:ap';
  static const String _menuTokGettyIntl = 'wire:getty_international';
  static const String _menuTokCustom = 'wire:custom';

  final List<TextEditingController> _gapControllers = [];
  final TextEditingController _bylinePrefixCtrl = TextEditingController();
  final TextEditingController _bylineBetweenCtrl = TextEditingController();
  final TextEditingController _bylineSuffixCtrl = TextEditingController();
  bool _syncingBylineCtrls = false;

  /// Structured date formula — drives the chip-based [DateFormulaEditor].
  /// Seeded from [_template.dateFormula] on load, or [DateFormula.ap] as fallback.
  DateFormula _dateFormula = DateFormula.ap();

  @override
  void initState() {
    super.initState();
    _bylinePrefixCtrl.addListener(_onBylineTextEdited);
    _bylineBetweenCtrl.addListener(_onBylineTextEdited);
    _bylineSuffixCtrl.addListener(_onBylineTextEdited);
    _load = _loadFromPrefs();
  }

  /// Rebuilds local editor state from [_template]. Called after prefs load and
  /// after a wire-style swap. Any legacy [CaptionTemplate.dateExpression] is
  /// discarded in favour of the structured formula (which is the only editor
  /// surface now).
  void _syncDateUiFromTemplate() {
    setState(() {
      DateFormula? src;
      if (_dateEditorOpen &&
          _activeFormulaIndex != null &&
          _activeFormulaIndex! < _template.segmentOrder.length &&
          _template.segmentOrder[_activeFormulaIndex!] == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, _activeFormulaIndex!, CaptionSegment.date);
        src = CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
      } else {
        src = _template.dateFormula;
      }
      if (src != null && src.fields.isNotEmpty) {
        _dateFormula = src.clone();
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
      final idx = _activeFormulaIndex;
      if (idx != null &&
          idx >= 0 &&
          idx < _template.segmentOrder.length &&
          _template.segmentOrder[idx] == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, idx, CaptionSegment.date);
        _template = _templateWithDateAtOccurrence(_template, occ, next);
      } else {
        _template = _template.copyWith(
          dateFormula: next.clone(),
          dateExpression: '',
        );
      }
    });
  }

  void _syncBylineControllersFromTemplate() {
    _syncingBylineCtrls = true;
    _bylinePrefixCtrl.text = _template.bylineOptions.prefix;
    _bylineBetweenCtrl.text = _template.bylineOptions.between;
    _bylineSuffixCtrl.text = _template.bylineOptions.suffix;
    _syncingBylineCtrls = false;
  }

  void _onBylineTextEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          prefix: _bylinePrefixCtrl.text,
          between: _bylineBetweenCtrl.text,
          suffix: _bylineSuffixCtrl.text,
        ),
      );
    });
  }

  void _closeAllInlineEdits() {
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
    });
  }

  /// Clears formula-chip highlight when the user taps outside the chip strip.
  /// Deferred so taps on other controls (e.g. Save) still win the gesture arena.
  void _deselectFormulaChipStripOnTapOutside() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_locationEditorOpen ||
          _dateEditorOpen ||
          _captionPreviewSelected ||
          _venuePreviewSelected ||
          _bylinePreviewSelected) {
        return;
      }
      if (_activeFormulaIndex == null) return;
      setState(() {
        _activeFormulaIndex = null;
      });
    });
  }

  void _activateFormulaEditor({
    required int index,
    required CaptionSegment segment,
  }) {
    setState(() {
      final currentlyActive = _activeFormulaIndex == index;
      final sameModeActive =
          (segment == CaptionSegment.location && _locationEditorOpen) ||
              (segment == CaptionSegment.date && _dateEditorOpen) ||
              (segment == CaptionSegment.caption && _captionPreviewSelected) ||
              (segment == CaptionSegment.venue && _venuePreviewSelected) ||
              (segment == CaptionSegment.credit && _bylinePreviewSelected);
      if (currentlyActive && sameModeActive) {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _activeFormulaIndex = null;
        return;
      }
      _activeFormulaIndex = index;
      _focusedGapIndex = null;
      _locationEditorOpen = segment == CaptionSegment.location;
      _dateEditorOpen = segment == CaptionSegment.date;
      _captionPreviewSelected = segment == CaptionSegment.caption;
      _venuePreviewSelected = segment == CaptionSegment.venue;
      _bylinePreviewSelected = segment == CaptionSegment.credit;
      if (segment == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, index, CaptionSegment.date);
        final f =
            CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
        _dateFormula = (f ?? _template.dateFormula ?? DateFormula.ap()).clone();
      }
    });
  }

  void _highlightFormulaSegment(int index) {
    if (index < 0 || index >= _template.segmentOrder.length) return;
    setState(() {
      if (_activeFormulaIndex == index &&
          !_locationEditorOpen &&
          !_dateEditorOpen &&
          !_captionPreviewSelected &&
          !_venuePreviewSelected &&
          !_bylinePreviewSelected) {
        _activeFormulaIndex = null;
        return;
      }
      _activeFormulaIndex = index;
      _focusedGapIndex = null;
      // Body click highlights preview only; it does not open any editor pane.
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
    });
  }

  void _toggleBylineFieldCaps(BylineFieldKind kind) {
    setState(() {
      final o = _template.bylineOptions;
      switch (kind) {
        case BylineFieldKind.name:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(nameCaps: !o.nameCaps),
          );
          break;
        case BylineFieldKind.credit:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(
              creditCaps: !o.creditCaps,
              organizationCaps: !o.creditCaps,
            ),
          );
          break;
        case BylineFieldKind.copyright:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(copyrightCaps: !o.copyrightCaps),
          );
          break;
      }
    });
  }

  void _moveBylineField(BylineFieldKind kind, int delta) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    final i = order.indexOf(kind);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= order.length) return;
    setState(() {
      final v = order.removeAt(i);
      order.insert(j, v);
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(fieldOrder: order),
      );
    });
  }

  void _reorderBylineField(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    if (fromIndex < 0 || fromIndex >= order.length) return;
    if (targetIndex < 0 || targetIndex >= order.length) return;
    setState(() {
      final item = order.removeAt(fromIndex);
      // Drop over a chip places the dragged chip at that chip's index.
      // This avoids no-op behavior when moving one step to the right.
      final insert = targetIndex.clamp(0, order.length);
      order.insert(insert, item);
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(fieldOrder: order),
      );
    });
  }

  void _addBylineField(BylineFieldKind kind) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    if (order.contains(kind)) return;
    setState(() {
      order.add(kind);
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(fieldOrder: order),
      );
    });
  }

  void _removeBylineField(BylineFieldKind kind) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    if (kind == BylineFieldKind.name) return;
    if (!order.contains(kind)) return;
    setState(() {
      order.remove(kind);
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(fieldOrder: order),
      );
    });
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await PreferencesService.getInstance();
    // Promote any legacy "Getty International" library entry before we read
    // the library so it doesn't show up alongside the new built-in wire.
    await prefs.migrateGettyInternationalLibraryEntry();
    var template = await prefs.getCaptionTemplate();
    final mergedGaps = CaptionFormulaRenderer.effectiveSegmentGaps(template);
    if (template.customSeparators == null ||
        template.customSeparators!.length != mergedGaps.length) {
      template = template.copyWith(customSeparators: mergedGaps);
    }
    template = template.normalizePerOccurrenceLists();
    final gameInfo = await prefs.getCaptionGameInfo();
    final gettyDef = await prefs.getCaptionTemplateWireDefault(WireStyle.getty);
    final imagnDef = await prefs.getCaptionTemplateWireDefault(WireStyle.imagn);
    final apDef = await prefs.getCaptionTemplateWireDefault(WireStyle.ap);
    final gettyIntlDef =
        await prefs.getCaptionTemplateWireDefault(WireStyle.gettyInternational);
    final styleLib = await prefs.getCaptionStyleLibrary();
    final showKeywords = await prefs.getShowKeywordsField();
    final showPersonality = await prefs.getShowPersonalityField();
    final gettyLabel = await prefs.getCaptionWireLabel(WireStyle.getty);
    final imagnLabel = await prefs.getCaptionWireLabel(WireStyle.imagn);
    final apLabel = await prefs.getCaptionWireLabel(WireStyle.ap);
    final gettyIntlLabel =
        await prefs.getCaptionWireLabel(WireStyle.gettyInternational);
    if (!mounted) return;
    setState(() {
      _loadedGameInfo = gameInfo;
      _gettyWireDefault = gettyDef;
      _imagnWireDefault = imagnDef;
      _apWireDefault = apDef;
      _gettyIntlWireDefault = gettyIntlDef;
      _gettyWireLabel = gettyLabel;
      _imagnWireLabel = imagnLabel;
      _apWireLabel = apLabel;
      _gettyIntlWireLabel = gettyIntlLabel;
      _captionStyleLibrary = styleLib;
      _showKeywordsField = showKeywords;
      _showPersonalityField = showPersonality;
      _template = template;
      _selectedWire = template.wireStyle;
      _selectedSavedStyleId =
          _libraryEntryIdMatchingActiveTemplate(template, styleLib);
      _prefsLoaded = true;
      _lastSavedTemplateSnapshot = _templateSnapshot(template);
      if (template.wireStyle == WireStyle.custom) {
        _lastPreset = _wiredBaseline(WireStyle.getty);
      } else {
        _lastPreset = _clonePreset(template);
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
  }

  String _templateSnapshot([CaptionTemplate? t]) {
    final source = t ?? _template;
    return jsonEncode(source.toJson());
  }

  void _scheduleAutosave() {
    if (!_prefsLoaded) return;
    final snapshot = _templateSnapshot();
    if (snapshot == _lastSavedTemplateSnapshot) return;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 220), () async {
      final templateToSave = _template;
      final saveSnapshot = _templateSnapshot(templateToSave);
      if (saveSnapshot == _lastSavedTemplateSnapshot) return;
      final prefs = await PreferencesService.getInstance();
      await prefs.saveCaptionTemplate(templateToSave);
      _lastSavedTemplateSnapshot = saveSnapshot;
    });
  }

  CreditSampleAgency _sampleAgencyForWire(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return CreditSampleAgency.gettyImages;
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
        return CreditSampleAgency.ap;
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  String _factoryWireLabel(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return 'Getty';
      case WireStyle.imagn:
        return 'Imagn';
      case WireStyle.ap:
        return 'AP';
      case WireStyle.gettyInternational:
        return 'Getty International';
      case WireStyle.custom:
        return 'Custom';
    }
  }

  String? _wireLabelOverride(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return _gettyWireLabel;
      case WireStyle.imagn:
        return _imagnWireLabel;
      case WireStyle.ap:
        return _apWireLabel;
      case WireStyle.gettyInternational:
        return _gettyIntlWireLabel;
      case WireStyle.custom:
        return null;
    }
  }

  String _wireStyleDropdownLabel(WireStyle w) {
    final override = _wireLabelOverride(w);
    if (override != null && override.isNotEmpty) return override;
    return _factoryWireLabel(w);
  }

  String _wireMenuToken(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return _menuTokGetty;
      case WireStyle.imagn:
        return _menuTokImagn;
      case WireStyle.ap:
        return _menuTokAp;
      case WireStyle.gettyInternational:
        return _menuTokGettyIntl;
      case WireStyle.custom:
        return _menuTokCustom;
    }
  }

  WireStyle _wireStyleFromMenuToken(String token) {
    switch (token) {
      case _menuTokImagn:
        return WireStyle.imagn;
      case _menuTokAp:
        return WireStyle.ap;
      case _menuTokGettyIntl:
        return WireStyle.gettyInternational;
      case _menuTokCustom:
        return WireStyle.custom;
      case _menuTokGetty:
      default:
        return WireStyle.getty;
    }
  }

  List<String> _captionStyleDropdownTokens() => [
        _menuTokGetty,
        _menuTokImagn,
        _menuTokAp,
        _menuTokGettyIntl,
        _menuTokCustom,
        ..._captionStyleLibrary.map((e) => 'saved:${e.id}'),
      ];

  CaptionStyleLibraryEntry? _entryForSavedStyleToken(String token) {
    if (!token.startsWith('saved:')) return null;
    final id = token.substring(6);
    for (final e in _captionStyleLibrary) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// When the active caption template was saved from a library row, [CaptionTemplate.id]
  /// matches that row — set [_selectedSavedStyleId] so Rename / Delete apply.
  String? _libraryEntryIdMatchingActiveTemplate(
    CaptionTemplate template,
    List<CaptionStyleLibraryEntry> lib,
  ) {
    for (final e in lib) {
      if (e.id == template.id) return e.id;
      if (e.template.id == template.id) return e.id;
    }
    final norm = template.normalizePerOccurrenceLists();
    final snap = jsonEncode(norm.toJson());
    for (final e in lib) {
      final eNorm = e.template.normalizePerOccurrenceLists();
      if (jsonEncode(eNorm.toJson()) == snap) return e.id;
    }
    return null;
  }

  String _captionStyleMenuLabel(String token) {
    final saved = _entryForSavedStyleToken(token);
    if (saved != null) return saved.displayName;
    switch (token) {
      case _menuTokGetty:
        return _wireStyleDropdownLabel(WireStyle.getty);
      case _menuTokImagn:
        return _wireStyleDropdownLabel(WireStyle.imagn);
      case _menuTokAp:
        return _wireStyleDropdownLabel(WireStyle.ap);
      case _menuTokGettyIntl:
        return _wireStyleDropdownLabel(WireStyle.gettyInternational);
      case _menuTokCustom:
        return _wireStyleDropdownLabel(WireStyle.custom);
      default:
        return token;
    }
  }

  String _captionStyleDropdownInitialToken() {
    if (_selectedSavedStyleId != null) {
      final t = 'saved:$_selectedSavedStyleId';
      if (_captionStyleDropdownTokens().contains(t)) return t;
    }
    return _wireMenuToken(_selectedWire);
  }

  void _applyCaptionStyleMenuToken(String? token) {
    if (token == null) return;
    if (token.startsWith('saved:')) {
      final entry = _entryForSavedStyleToken(token);
      if (entry == null) return;
      setState(() {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _disposeGapControllers();
        _selectedSavedStyleId = entry.id;
        _template = _deepCopyCaptionTemplate(entry.template);
        _selectedWire = _template.wireStyle;
        if (_template.wireStyle == WireStyle.custom) {
          _lastPreset = _wiredBaseline(WireStyle.getty);
        } else {
          _lastPreset = _clonePreset(_template);
        }
        _initGapControllers(_template);
        _syncBylineControllersFromTemplate();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDateUiFromTemplate();
      });
      return;
    }
    _applyWireStyle(_wireStyleFromMenuToken(token));
  }

  /// Factory Getty / Imagn / AP / Getty International, or the user’s saved
  /// default for that wire.
  CaptionTemplate _wiredBaseline(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
        return _gettyWireDefault ?? CaptionTemplate.getty();
      case WireStyle.imagn:
        return _imagnWireDefault ?? CaptionTemplate.imagn();
      case WireStyle.ap:
        return _apWireDefault ?? CaptionTemplate.ap();
      case WireStyle.gettyInternational:
        return _gettyIntlWireDefault ?? CaptionTemplate.gettyInternational();
      case WireStyle.custom:
        return _gettyWireDefault ?? CaptionTemplate.getty();
    }
  }

  CaptionTemplate _clonePreset(CaptionTemplate t) {
    switch (t.wireStyle) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return _wiredBaseline(t.wireStyle).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
        );
      case WireStyle.imagn:
        return _wiredBaseline(WireStyle.imagn).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
        );
      case WireStyle.ap:
        return _wiredBaseline(WireStyle.ap).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
        );
      case WireStyle.custom:
        return _wiredBaseline(WireStyle.getty);
    }
  }

  /// Full JSON round-trip so nested lists (per–date-chip formulas, etc.) stay independent.
  CaptionTemplate _deepCopyCaptionTemplate(CaptionTemplate t) {
    final raw = json.decode(json.encode(t.toJson())) as Map<String, dynamic>;
    return CaptionTemplate.fromJson(raw);
  }

  /// Copies the working layout as [WireStyle.custom] for editing without replacing
  /// the Getty / Imagn / AP wire default.
  void _duplicateCaptionStyle() {
    final previousWire = _selectedWire;
    final copy = _deepCopyCaptionTemplate(_template);
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
      _disposeGapControllers();
      _selectedSavedStyleId = null;
      _selectedWire = WireStyle.custom;
      _template = copy.copyWith(
        wireStyle: WireStyle.custom,
        id: 'custom',
        name: 'Custom',
      );
      if (previousWire != WireStyle.custom) {
        _lastPreset = _clonePreset(_wiredBaseline(previousWire));
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          previousWire == WireStyle.custom
              ? 'Layout duplicated as Custom. Save to keep your caption template.'
              : 'Copied ${_wireStyleDropdownLabel(previousWire)} layout as Custom. '
                  'Save to keep it; your ${_wireStyleDropdownLabel(previousWire)} default is unchanged.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteSelectedCaptionStyle() async {
    final id = _selectedSavedStyleId;
    if (id == null) return;
    String? removedName;
    for (final e in _captionStyleLibrary) {
      if (e.id == id) {
        removedName = e.displayName;
        break;
      }
    }
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.removeCaptionStyleFromLibrary(id);
      final lib = await prefs.getCaptionStyleLibrary();
      if (!mounted) return;
      setState(() {
        _captionStyleLibrary = lib;
        _selectedSavedStyleId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removedName != null
                ? 'Removed "$removedName" from saved caption styles.'
                : 'Removed saved caption style.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete caption style: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _disposeGapControllers() {
    for (final c in _gapControllers) {
      c.dispose();
    }
    _gapControllers.clear();
  }

  void _initGapControllers(CaptionTemplate t) {
    _focusedGapIndex = null;
    _disposeGapControllers();
    // Always match [CaptionFormulaRenderer.effectiveSegmentGaps] so preview and
    // inline fields stay aligned (handles null or wrong-length custom lists).
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(t);
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

  CaptionTemplate _templateWithLocationAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    LocationLineOptions o,
  ) {
    final n = t.segmentOrder.where((s) => s == CaptionSegment.location).length;
    if (n <= 1) {
      return t.copyWith(
        locationOptions: o,
        locationOptionsByOccurrence: null,
      );
    }
    final list = List<LocationLineOptions>.generate(
      n,
      (i) => (t.locationOptionsByOccurrence != null &&
              i < t.locationOptionsByOccurrence!.length)
          ? t.locationOptionsByOccurrence![i].clone()
          : t.locationOptions.clone(),
    );
    list[occurrenceIndex.clamp(0, n - 1)] = o;
    return t.copyWith(
      locationOptions: list[0],
      locationOptionsByOccurrence: list,
    );
  }

  CaptionTemplate _templateWithDateAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    DateFormula next,
  ) {
    final n = t.segmentOrder.where((s) => s == CaptionSegment.date).length;
    if (n <= 1) {
      return t.copyWith(
        dateFormula: next.clone(),
        dateFormulasByOccurrence: null,
        dateExpression: '',
      );
    }
    final list = List<DateFormula>.generate(
      n,
      (i) {
        if (t.dateFormulasByOccurrence != null &&
            i < t.dateFormulasByOccurrence!.length) {
          return t.dateFormulasByOccurrence![i].clone();
        }
        return (t.dateFormula ?? DateFormula.ap()).clone();
      },
    );
    list[occurrenceIndex.clamp(0, n - 1)] = next.clone();
    return t.copyWith(
      dateFormula: list[0],
      dateFormulasByOccurrence: list,
      dateExpression: '',
    );
  }

  List<LocationLineOptions>? _remapLocationOptionsByOccurrence(
    List<CaptionSegment> oldOrder,
    List<CaptionSegment> newOrder,
    CaptionTemplate t,
  ) {
    final newCount = newOrder.where((s) => s == CaptionSegment.location).length;
    if (newCount == 0) return null;
    final oldVals = <LocationLineOptions>[];
    var k = 0;
    for (var i = 0; i < oldOrder.length; i++) {
      if (oldOrder[i] == CaptionSegment.location) {
        oldVals
            .add(CaptionFormulaRenderer.locationLineOptionsForOccurrence(t, k));
        k++;
      }
    }
    final out = <LocationLineOptions>[];
    var vi = 0;
    for (var i = 0; i < newOrder.length; i++) {
      if (newOrder[i] == CaptionSegment.location) {
        out.add(vi < oldVals.length
            ? oldVals[vi].clone()
            : t.locationOptions.clone());
        vi++;
      }
    }
    return out;
  }

  List<DateFormula>? _remapDateFormulasByOccurrence(
    List<CaptionSegment> oldOrder,
    List<CaptionSegment> newOrder,
    CaptionTemplate t,
  ) {
    final newCount = newOrder.where((s) => s == CaptionSegment.date).length;
    if (newCount == 0) return null;
    final oldVals = <DateFormula>[];
    var k = 0;
    for (var i = 0; i < oldOrder.length; i++) {
      if (oldOrder[i] == CaptionSegment.date) {
        final f = CaptionFormulaRenderer.dateFormulaForOccurrence(t, k);
        oldVals.add((f ?? t.dateFormula ?? DateFormula.ap()).clone());
        k++;
      }
    }
    final out = <DateFormula>[];
    var vi = 0;
    for (var i = 0; i < newOrder.length; i++) {
      if (newOrder[i] == CaptionSegment.date) {
        out.add(vi < oldVals.length
            ? oldVals[vi].clone()
            : (t.dateFormula ?? DateFormula.ap()).clone());
        vi++;
      }
    }
    return out;
  }

  CaptionTemplate _applyRemappedLocationOccurrences(
    CaptionTemplate t,
    List<LocationLineOptions>? remapped,
  ) {
    if (remapped == null || remapped.isEmpty) return t;
    if (remapped.length == 1) {
      return t.copyWith(
        locationOptions: remapped[0],
        locationOptionsByOccurrence: null,
      );
    }
    return t.copyWith(
      locationOptions: remapped[0],
      locationOptionsByOccurrence: remapped,
    );
  }

  CaptionTemplate _applyRemappedDateOccurrences(
    CaptionTemplate t,
    List<DateFormula>? remapped,
  ) {
    if (remapped == null || remapped.isEmpty) return t;
    if (remapped.length == 1) {
      return t.copyWith(
        dateFormula: remapped[0],
        dateFormulasByOccurrence: null,
        dateExpression: '',
      );
    }
    return t.copyWith(
      dateFormula: remapped[0],
      dateFormulasByOccurrence: remapped,
      dateExpression: '',
    );
  }

  void _commitLocationOptions(LocationLineOptions o) {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length ||
        _template.segmentOrder[idx] != CaptionSegment.location) {
      return;
    }
    final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
        _template.segmentOrder, idx, CaptionSegment.location);
    setState(() {
      _template = _templateWithLocationAtOccurrence(_template, occ, o);
    });
  }

  void _applyWireStyle(WireStyle w) {
    // Re-applying the same wire (e.g. Caption Style dropdown fires again) must not
    // replace [_template] with [_wiredBaseline], or in-progress Getty edits vanish.
    // Leaving a saved library entry for this wire still reloads the baseline below.
    if (w == _selectedWire && _selectedSavedStyleId == null) {
      return;
    }
    setState(() {
      _selectedSavedStyleId = null;
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _disposeGapControllers();
      _selectedWire = w;
      switch (w) {
        case WireStyle.getty:
        case WireStyle.gettyInternational:
        case WireStyle.imagn:
        case WireStyle.ap:
          final b = _wiredBaseline(w);
          _template = b;
          _lastPreset = b;
          break;
        case WireStyle.custom:
          final ref = _lastPreset;
          _template = CaptionTemplate.custom(
            dateFormat: ref.dateFormat,
            dateExpression: ref.dateExpression,
            dateFormula: ref.dateFormula?.clone(),
            dateFormulasByOccurrence:
                ref.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
            locationOptions: ref.locationOptions,
            locationOptionsByOccurrence:
                ref.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
            numberFormat: ref.numberFormat,
            captionTeamOrder: ref.captionTeamOrder,
            includePlayerPosition: ref.includePlayerPosition,
            removeDiacritics: ref.removeDiacritics,
            separator: ref.separator,
            creditFormat: ref.creditFormat,
            bylineOptions: ref.bylineOptions,
            segmentOrder: List<CaptionSegment>.from(ref.segmentOrder),
            customSeparators: List<String>.from(
              CaptionFormulaRenderer.defaultCustomGaps(ref),
            ),
          );
          break;
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
  }

  Future<void> _save() async {
    _autosaveDebounce?.cancel();
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCaptionTemplate(_template);
    await prefs.saveShowKeywordsField(_showKeywordsField);
    await prefs.saveShowPersonalityField(_showPersonalityField);
    _lastSavedTemplateSnapshot = _templateSnapshot();
    if (mounted) Navigator.of(context).pop();
  }

  /// Three modes for the Rename / Save-as dialog:
  ///  * `libraryEntry` — selected style is a saved library entry → rename it.
  ///  * `wireLabel` — selected style is a built-in wire (Getty/Imagn/AP) →
  ///     update the wire's dropdown label override.
  ///  * `saveAsNewLibrary` — selected style is Custom → save the current
  ///     template as a new library entry.
  _RenamePromptMode _currentRenameMode() {
    if (_selectedSavedStyleId != null) return _RenamePromptMode.libraryEntry;
    if (_selectedWire == WireStyle.custom) {
      return _RenamePromptMode.saveAsNewLibrary;
    }
    return _RenamePromptMode.wireLabel;
  }

  void _openRenameCaptionStylePrompt() {
    final mode = _currentRenameMode();
    String? currentName;
    switch (mode) {
      case _RenamePromptMode.libraryEntry:
        for (final e in _captionStyleLibrary) {
          if (e.id == _selectedSavedStyleId) {
            currentName = e.displayName;
            break;
          }
        }
        break;
      case _RenamePromptMode.wireLabel:
        currentName = _wireStyleDropdownLabel(_selectedWire);
        break;
      case _RenamePromptMode.saveAsNewLibrary:
        currentName = 'My caption style';
        break;
    }
    _renameCaptionStyleNameCtrl?.dispose();
    _renameCaptionStyleNameCtrl =
        TextEditingController(text: currentName ?? '');
    setState(() => _renameCaptionStylePromptOpen = true);
  }

  void _closeRenameCaptionStylePrompt() {
    if (!_renameCaptionStylePromptOpen) return;
    _renameCaptionStyleNameCtrl?.dispose();
    _renameCaptionStyleNameCtrl = null;
    setState(() => _renameCaptionStylePromptOpen = false);
  }

  Future<void> _submitRenameCaptionStyleName() async {
    final ctrl = _renameCaptionStyleNameCtrl;
    if (ctrl == null || !mounted) return;
    final trimmed = ctrl.text.trim();
    if (trimmed.isEmpty) return;
    final mode = _currentRenameMode();
    try {
      final prefs = await PreferencesService.getInstance();
      String snackMessage;
      switch (mode) {
        case _RenamePromptMode.libraryEntry:
          final existingId = _selectedSavedStyleId!;
          await prefs.renameCaptionStyleInLibrary(
              id: existingId, newDisplayName: trimmed);
          final lib = await prefs.getCaptionStyleLibrary();
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            _captionStyleLibrary = lib;
            _selectedSavedStyleId = existingId;
          });
          snackMessage = 'Renamed saved style to "$trimmed".';
          break;
        case _RenamePromptMode.wireLabel:
          final wire = _selectedWire;
          await prefs.saveCaptionWireLabel(wire, trimmed);
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            switch (wire) {
              case WireStyle.getty:
                _gettyWireLabel = trimmed;
                break;
              case WireStyle.imagn:
                _imagnWireLabel = trimmed;
                break;
              case WireStyle.ap:
                _apWireLabel = trimmed;
                break;
              case WireStyle.gettyInternational:
                _gettyIntlWireLabel = trimmed;
                break;
              case WireStyle.custom:
                break;
            }
          });
          snackMessage =
              'Renamed ${_factoryWireLabel(wire)} to "$trimmed" in the menu.';
          break;
        case _RenamePromptMode.saveAsNewLibrary:
          final savedId = await prefs.addCaptionStyleToLibrary(
            displayName: trimmed,
            template: _template,
          );
          final lib = await prefs.getCaptionStyleLibrary();
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            _captionStyleLibrary = lib;
            _selectedSavedStyleId = savedId;
            for (final e in lib) {
              if (e.id == savedId) {
                _template = _deepCopyCaptionTemplate(e.template);
                _selectedWire = _template.wireStyle;
                break;
              }
            }
          });
          snackMessage = 'Saved "$trimmed" as a new caption style.';
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackMessage),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _renameCaptionStyleNameOverlay() {
    final ctrl = _renameCaptionStyleNameCtrl;
    if (ctrl == null) return const SizedBox.shrink();
    final ok = ctrl.text.trim().isNotEmpty;
    final mode = _currentRenameMode();
    String title;
    String submitLabel;
    switch (mode) {
      case _RenamePromptMode.libraryEntry:
        title = 'Rename caption style';
        submitLabel = 'Rename';
        break;
      case _RenamePromptMode.wireLabel:
        title = 'Rename ${_factoryWireLabel(_selectedWire)} in menu';
        submitLabel = 'Rename';
        break;
      case _RenamePromptMode.saveAsNewLibrary:
        title = 'Save caption style as';
        submitLabel = 'Save';
        break;
    }
    return Material(
      color: Colors.black38,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        _submitRenameCaptionStyleName();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _closeRenameCaptionStylePrompt,
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _captionLayoutBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        onPressed: ok ? _submitRenameCaptionStyleName : null,
                        child: Text(
                          submitLabel,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _disposeGapControllers();
    _bylinePrefixCtrl.removeListener(_onBylineTextEdited);
    _bylineBetweenCtrl.removeListener(_onBylineTextEdited);
    _bylineSuffixCtrl.removeListener(_onBylineTextEdited);
    _bylinePrefixCtrl.dispose();
    _bylineBetweenCtrl.dispose();
    _bylineSuffixCtrl.dispose();
    _renameCaptionStyleNameCtrl?.dispose();
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
        return 'Geographical';
      case CaptionSegment.date:
        return 'Date';
      case CaptionSegment.caption:
        return 'Caption';
      case CaptionSegment.venue:
        return 'IPTC:Location';
      case CaptionSegment.credit:
        return 'IPTC:Byline';
    }
  }

  Widget _pill(
    CaptionSegment s, {
    bool highlight = false,
    Widget? trailing,
    VoidCallback? onRemove,
    String? label,
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
            label ?? _pillShortLabel(s),
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
    double size = 14,
  }) {
    final btn = SizedBox(
      width: size,
      height: size,
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

  Widget _segmentPill(CaptionSegment s, {required int index}) {
    final canRemove = _template.segmentOrder.length > 1;
    VoidCallback? onRemove = canRemove ? () => _removeSegmentAt(index) : null;
    final label = _segmentDisplayLabel(s, index);
    final isSelected = _activeFormulaIndex == index;
    if (s == CaptionSegment.location) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _highlightFormulaSegment(index),
          child: _pill(
            s,
            label: label,
            highlight: isSelected,
            trailing: _chipIconSquare(
              tooltip: 'Edit',
              size: 16,
              onTap: () => _activateFormulaEditor(
                index: index,
                segment: CaptionSegment.location,
              ),
              child: Icon(Icons.tune, size: 11, color: Colors.grey.shade700),
            ),
            onRemove: onRemove,
          ),
        ),
      );
    }
    if (s == CaptionSegment.date) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _highlightFormulaSegment(index),
          child: _pill(
            s,
            label: label,
            highlight: isSelected,
            trailing: _chipIconSquare(
              tooltip: 'Edit',
              size: 16,
              onTap: () => _activateFormulaEditor(
                index: index,
                segment: CaptionSegment.date,
              ),
              child: Icon(Icons.tune, size: 11, color: Colors.grey.shade700),
            ),
            onRemove: onRemove,
          ),
        ),
      );
    }
    if (s == CaptionSegment.caption) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _highlightFormulaSegment(index),
          child: _pill(
            s,
            label: label,
            highlight: isSelected,
            trailing: _chipIconSquare(
              tooltip: 'Edit',
              size: 16,
              onTap: () => _activateFormulaEditor(
                index: index,
                segment: CaptionSegment.caption,
              ),
              child: Icon(Icons.tune, size: 11, color: Colors.grey.shade700),
            ),
            onRemove: onRemove,
          ),
        ),
      );
    }
    if (s == CaptionSegment.venue) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _highlightFormulaSegment(index),
          child: _pill(
            s,
            label: label,
            highlight: isSelected,
            trailing: _chipIconSquare(
              tooltip: 'Edit',
              size: 16,
              onTap: () => _activateFormulaEditor(
                index: index,
                segment: CaptionSegment.venue,
              ),
              child: Icon(Icons.tune, size: 11, color: Colors.grey.shade700),
            ),
            onRemove: onRemove,
          ),
        ),
      );
    }
    if (s == CaptionSegment.credit) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _highlightFormulaSegment(index),
          child: _pill(
            s,
            label: label,
            highlight: isSelected,
            trailing: _chipIconSquare(
              tooltip: 'Edit',
              size: 16,
              onTap: () => _activateFormulaEditor(
                index: index,
                segment: CaptionSegment.credit,
              ),
              child: Icon(Icons.tune, size: 11, color: Colors.grey.shade700),
            ),
            onRemove: onRemove,
          ),
        ),
      );
    }
    return _pill(s, label: label, onRemove: onRemove);
  }

  String _segmentDisplayLabel(CaptionSegment segment, int atIndex) {
    final base = _pillShortLabel(segment);
    if (segment != CaptionSegment.location && segment != CaptionSegment.date) {
      return base;
    }
    var seen = 0;
    for (var i = 0; i <= atIndex && i < _template.segmentOrder.length; i++) {
      if (_template.segmentOrder[i] == segment) seen++;
    }
    return seen <= 1 ? base : '$base $seen';
  }

  Widget _activeEditIndicator() {
    if (!_locationEditorOpen &&
        !_dateEditorOpen &&
        !_captionPreviewSelected &&
        !_venuePreviewSelected &&
        !_bylinePreviewSelected) {
      return const SizedBox.shrink();
    }
    String label;
    if (_activeFormulaIndex != null &&
        _activeFormulaIndex! >= 0 &&
        _activeFormulaIndex! < _template.segmentOrder.length) {
      final activeSegment = _template.segmentOrder[_activeFormulaIndex!];
      label = _segmentDisplayLabel(activeSegment, _activeFormulaIndex!);
    } else {
      label = _locationEditorOpen
          ? 'Location'
          : _dateEditorOpen
              ? 'Date'
              : _captionPreviewSelected
                  ? 'Caption'
                  : _venuePreviewSelected
                      ? 'Venue'
                      : 'Byline';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.keyboard_arrow_down, size: 12, color: Colors.grey.shade700),
        const SizedBox(width: 1),
        Text(
          'Edit $label',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _bylineEditor() {
    final order = _template.bylineOptions.fieldOrder;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0x14000000)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _smallBylineField(_bylinePrefixCtrl, width: 140),
                for (var i = 0; i < order.length; i++) ...[
                  _bylineDraggableChip(order[i], index: i, total: order.length),
                  if (i < order.length - 1) _bylineBetweenMirror(i),
                ],
                _smallBylineField(_bylineSuffixCtrl, width: 140),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
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
              if (!order.contains(BylineFieldKind.credit))
                _sourceOptionChip(
                  selected: false,
                  label: '+ Credit',
                  onTap: () => _addBylineField(
                    BylineFieldKind.credit,
                  ),
                ),
              if (!order.contains(BylineFieldKind.copyright))
                _sourceOptionChip(
                  selected: false,
                  label: '+ Copyright',
                  onTap: () => _addBylineField(
                    BylineFieldKind.copyright,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallBylineField(
    TextEditingController ctrl, {
    double width = 44,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: width,
        child: _GapSeparatorField(controller: ctrl),
      ),
    );
  }

  /// Separator between ordered byline fields (same string is repeated in the
  /// caption). Only the first gap is editable; mirrors stay in sync.
  Widget _bylineBetweenMirror(int segmentIndex) {
    if (segmentIndex == 0) {
      return _smallBylineField(_bylineBetweenCtrl);
    }
    return ListenableBuilder(
      listenable: _bylineBetweenCtrl,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: 44,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: Text(
              _bylineBetweenCtrl.text,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  Widget _bylineDraggableChip(
    BylineFieldKind kind, {
    required int index,
    required int total,
  }) {
    final chipCore = _bylineTokenChipCore(
      kind,
      index: index,
      total: total,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _reorderBylineField(d.data, index),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? const Color(0xFF2563EB) : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: active ? const Color(0xFF2563EB) : Colors.transparent,
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
            child: Tooltip(
              message: 'Long-press, then drag to reorder',
              child: chipCore,
            ),
          ),
        );
      },
    );
  }

  Widget _bylineTokenChipCore(
    BylineFieldKind kind, {
    required int index,
    required int total,
  }) {
    String label;
    bool caps;
    switch (kind) {
      case BylineFieldKind.name:
        label = 'IPTC:Creator';
        caps = _template.bylineOptions.nameCaps;
        break;
      case BylineFieldKind.credit:
        label = 'IPTC:Credit';
        caps = _template.bylineOptions.creditCaps;
        break;
      case BylineFieldKind.copyright:
        label = 'IPTC:Copyright';
        caps = _template.bylineOptions.copyrightCaps;
        break;
    }
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x14000000)),
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
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A3A3A),
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          _bylineMiniButton(
            icon: Icons.chevron_left,
            enabled: index > 0,
            onTap: () => _moveBylineField(kind, -1),
          ),
          const SizedBox(width: 2),
          _bylineMiniButton(
            icon: Icons.chevron_right,
            enabled: index < total - 1,
            onTap: () => _moveBylineField(kind, 1),
          ),
          const SizedBox(width: 2),
          _bylineChipIconButton(
            onTap: () => _toggleBylineFieldCaps(kind),
            background: caps ? const Color(0xFFD0E3FA) : Colors.white,
            child: const Text(
              'Aa',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A3A3A),
                height: 1,
              ),
            ),
          ),
          if (kind != BylineFieldKind.name) ...[
            const SizedBox(width: 2),
            _bylineMiniButton(
              icon: Icons.close,
              enabled: true,
              onTap: () => _removeBylineField(kind),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bylineMiniButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: SizedBox(
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
            onTap: enabled ? onTap : null,
            child: Icon(icon, size: 9, color: Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _bylineChipIconButton({
    required Widget child,
    required VoidCallback onTap,
    required Color background,
  }) {
    return SizedBox(
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
  }

  Widget _sourceOptionChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFEAF2FF) : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? _captionLayoutBlue : Colors.grey.shade300,
          width: selected ? 1.2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: selected ? _captionLayoutBlue : Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkOptionChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: selected ? _captionLayoutBlue : Colors.grey.shade600,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: _layoutOptionTextStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _captionTeamOrderChoice(CaptionTeamOrder value) {
    final label =
        value == CaptionTeamOrder.teamBefore ? 'Team before' : 'Team after';
    return _checkOptionChip(
      selected: _template.captionTeamOrder == value,
      label: label,
      onTap: () => setState(() {
        _template = _template.copyWith(captionTeamOrder: value);
      }),
    );
  }

  Widget _numberFormatChoice(NumberFormatStyle value) {
    final label = value == NumberFormatStyle.hash ? '#99' : '(99)';
    return _checkOptionChip(
      selected: _template.numberFormat == value,
      label: label,
      onTap: () => setState(() {
        _template = _template.copyWith(numberFormat: value);
      }),
    );
  }

  Widget _positionToggleChoice(bool includePosition) {
    final label = includePosition ? 'Include position' : 'No position';
    return _checkOptionChip(
      selected: _template.includePlayerPosition == includePosition,
      label: label,
      onTap: () => setState(() {
        _template = _template.copyWith(includePlayerPosition: includePosition);
      }),
    );
  }

  Widget _removeDiacriticsChoice(bool strip) {
    final label = strip ? 'Remove' : 'Keep';
    return _checkOptionChip(
      selected: _template.removeDiacritics == strip,
      label: label,
      onTap: () => setState(() {
        _template = _template.copyWith(removeDiacritics: strip);
      }),
    );
  }

  /// Session-only until the dialog Save button writes prefs.
  Future<void> _setShowKeywordsField(bool show) async {
    setState(() => _showKeywordsField = show);
  }

  /// Session-only until the dialog Save button writes prefs.
  Future<void> _setShowPersonalityField(bool show) async {
    setState(() => _showPersonalityField = show);
  }

  Widget _layoutOptionalFieldRow({
    required String label,
    required bool value,
    required Future<void> Function(bool) onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppCompactCheckbox(
            value: value,
            accentColor: _captionLayoutBlue,
            onChanged: (v) => onSave(v),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSave(!value),
              child: Text(
                label,
                style: _layoutOptionTextStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineDoneButton() {
    return Material(
      color: const Color(0xFF2E7D32),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF2E7D32)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: _closeAllInlineEdits,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'Done',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade50,
            ),
          ),
        ),
      ),
    );
  }

  /// Remove segment at [idx]. Closes its editor if open. Keeps
  /// [customSeparators] aligned by dropping the matching entry.
  void _removeSegmentAt(int idx) {
    final order = _template.segmentOrder;
    if (idx < 0 || order.length <= 1) return;
    final seg = order[idx];
    setState(() {
      if (seg == CaptionSegment.location) _locationEditorOpen = false;
      if (seg == CaptionSegment.date) _dateEditorOpen = false;
      if (seg == CaptionSegment.caption) _captionPreviewSelected = false;
      if (seg == CaptionSegment.venue) _venuePreviewSelected = false;
      if (seg == CaptionSegment.credit) _bylinePreviewSelected = false;

      final newOrder = List<CaptionSegment>.from(order)..removeAt(idx);
      if (_activeFormulaIndex != null) {
        if (_activeFormulaIndex == idx) {
          _activeFormulaIndex = null;
        } else if (_activeFormulaIndex! > idx) {
          _activeFormulaIndex = _activeFormulaIndex! - 1;
        }
      }

      List<String>? newSeps = _template.customSeparators;
      if (newSeps != null) {
        final list = List<String>.from(newSeps);
        // Drop the separator adjacent to the removed segment (prefer trailing).
        final sepIdx = idx < list.length ? idx : list.length - 1;
        if (sepIdx >= 0 && sepIdx < list.length) list.removeAt(sepIdx);
        newSeps = list;
      }

      final locMap =
          _remapLocationOptionsByOccurrence(order, newOrder, _template);
      final dateMap =
          _remapDateFormulasByOccurrence(order, newOrder, _template);
      var next = _template.copyWith(
        segmentOrder: newOrder,
        customSeparators: newSeps,
      );
      next = _applyRemappedLocationOccurrences(next, locMap);
      next = _applyRemappedDateOccurrences(next, dateMap);
      _template = next;
      _initGapControllers(_template);
    });
  }

  /// Add [seg] to the end of the formula (duplicates allowed).
  void _addSegment(CaptionSegment seg) {
    if (seg != CaptionSegment.date && seg != CaptionSegment.location) return;
    final order = _template.segmentOrder;
    setState(() {
      final newOrder = List<CaptionSegment>.from(order)..add(seg);
      _activeFormulaIndex = newOrder.length - 1;

      List<String>? newSeps = _template.customSeparators;
      if (newSeps != null) {
        final list = List<String>.from(newSeps)..add(' ');
        newSeps = list;
      }

      final locMap =
          _remapLocationOptionsByOccurrence(order, newOrder, _template);
      final dateMap =
          _remapDateFormulasByOccurrence(order, newOrder, _template);
      var next = _template.copyWith(
        segmentOrder: newOrder,
        customSeparators: newSeps,
      );
      next = _applyRemappedLocationOccurrences(next, locMap);
      next = _applyRemappedDateOccurrences(next, dateMap);
      _template = next;
      _initGapControllers(_template);
      if (seg == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            newOrder, newOrder.length - 1, CaptionSegment.date);
        final f =
            CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
        _dateFormula = (f ?? _template.dateFormula ?? DateFormula.ap()).clone();
      }
    });
  }

  /// When [order] has no duplicate segments, index of the gap between [a] and [b] if adjacent in [order].
  int? _gapIndexForAdjacentPair(
    List<CaptionSegment> order,
    CaptionSegment a,
    CaptionSegment b,
  ) {
    for (var i = 0; i < order.length - 1; i++) {
      if (order[i] == a && order[i + 1] == b) return i;
    }
    return null;
  }

  /// After dragging a chip, remap [oldGaps] to the new [newOrder] (same length as [oldOrder]).
  List<String> _gapsRemappedForNewOrder({
    required List<CaptionSegment> oldOrder,
    required List<String> oldGaps,
    required List<CaptionSegment> newOrder,
  }) {
    assert(oldOrder.length == newOrder.length);
    assert(oldGaps.length == oldOrder.length - 1);
    final hasDupes = oldOrder.toSet().length != oldOrder.length;
    final out = <String>[];
    for (var j = 0; j < newOrder.length - 1; j++) {
      final a = newOrder[j];
      final b = newOrder[j + 1];
      if (!hasDupes) {
        final i = _gapIndexForAdjacentPair(oldOrder, a, b);
        if (i != null) {
          out.add(oldGaps[i]);
          continue;
        }
      }
      out.add(CaptionFormulaRenderer.defaultGapBetweenSegments(
        _template,
        a,
        b,
      ));
    }
    return out;
  }

  void _reorderFormulaSegment(int fromIndex, int targetIndex) {
    if (fromIndex == targetIndex) return;
    final oldOrder = List<CaptionSegment>.from(_template.segmentOrder);
    final n = oldOrder.length;
    if (fromIndex < 0 || fromIndex >= n) return;
    if (targetIndex < 0 || targetIndex >= n) return;

    var oldGaps = List<String>.from(
      _template.customSeparators ??
          CaptionFormulaRenderer.defaultCustomGaps(_template),
    );
    if (oldGaps.length != n - 1) {
      oldGaps = List<String>.from(
        CaptionFormulaRenderer.defaultCustomGaps(_template),
      );
    }

    final order = List<CaptionSegment>.from(oldOrder);
    final seg = order.removeAt(fromIndex);
    final insert = targetIndex.clamp(0, order.length);
    order.insert(insert, seg);

    final newGaps = _gapsRemappedForNewOrder(
      oldOrder: oldOrder,
      oldGaps: oldGaps,
      newOrder: order,
    );
    final locMap =
        _remapLocationOptionsByOccurrence(oldOrder, order, _template);
    final dateMap = _remapDateFormulasByOccurrence(oldOrder, order, _template);

    setState(() {
      if (_activeFormulaIndex == fromIndex) {
        _activeFormulaIndex = insert;
      } else if (_activeFormulaIndex != null) {
        final current = _activeFormulaIndex!;
        if (fromIndex < current && current <= insert) {
          _activeFormulaIndex = current - 1;
        } else if (insert <= current && current < fromIndex) {
          _activeFormulaIndex = current + 1;
        }
      }
      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: newGaps,
      );
      next = _applyRemappedLocationOccurrences(next, locMap);
      next = _applyRemappedDateOccurrences(next, dateMap);
      _template = next;
      _initGapControllers(_template);
    });
  }

  Widget _formulaDraggableChip({
    required int index,
    required Widget child,
  }) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _reorderFormulaSegment(d.data, index),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? const Color(0xFF2563EB) : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: active ? const Color(0xFF2563EB) : Colors.transparent,
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
              child: Opacity(opacity: 0.92, child: child),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: child),
            child: Tooltip(
              message: 'Long-press, then drag to reorder',
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Inline chips for all available segment types.
  Widget _addSegmentRow() {
    const allSegments = <CaptionSegment>[
      CaptionSegment.location,
      CaptionSegment.date,
    ];
    final active = _activePreviewSegment();
    final dimOthers = active != null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          'Add chip:',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        for (final s in allSegments)
          dimOthers
              ? Opacity(
                  opacity: 0.45,
                  child: _sourceOptionChip(
                    selected: false,
                    label: '+ ${_pillShortLabel(s)}',
                    onTap: () => _addSegment(s),
                  ),
                )
              : _sourceOptionChip(
                  selected: false,
                  label: '+ ${_pillShortLabel(s)}',
                  onTap: () => _addSegment(s),
                ),
      ],
    );
  }

  LocationLineOptions _activeLocationLineOptions() {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length ||
        _template.segmentOrder[idx] != CaptionSegment.location) {
      return _template.locationOptions;
    }
    final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
        _template.segmentOrder, idx, CaptionSegment.location);
    return CaptionFormulaRenderer.locationLineOptionsForOccurrence(
        _template, occ);
  }

  Widget _locationOptionsEditor() {
    return LocationFormulaEditor(
      options: _activeLocationLineOptions(),
      onChanged: _commitLocationOptions,
    );
  }

  /// Compact separator field that sits inline with chips (matches chip height).
  Widget _gapField(int gapIndex, TextEditingController controller) {
    return _GapSeparatorField(
      controller: controller,
      onFocusChanged: (hasFocus) {
        if (!mounted) return;
        setState(() {
          if (hasFocus) {
            _focusedGapIndex = gapIndex;
            _activeFormulaIndex = null;
          } else if (_focusedGapIndex == gapIndex) {
            _focusedGapIndex = null;
          }
        });
      },
    );
  }

  Widget _dateLineEditor() {
    return DateFormulaEditor(
      formula: _dateFormula,
      onChanged: _commitDateFormula,
    );
  }

  Widget _formulaRow() {
    final order = _template.segmentOrder;
    final activeIndex = _activeFormulaIndex;
    final dimOthers = activeIndex != null || _focusedGapIndex != null;
    final children = <Widget>[];
    for (var i = 0; i < order.length; i++) {
      final seg = order[i];
      final pill = _segmentPill(seg, index: i);
      final draggable = _formulaDraggableChip(
        index: i,
        child: pill,
      );
      children.add(
        dimOthers && i != activeIndex
            ? Opacity(opacity: 0.45, child: draggable)
            : draggable,
      );
      if (i < order.length - 1 && i < _gapControllers.length) {
        final gap = _gapField(i, _gapControllers[i]);
        final gapDimmed = dimOthers &&
            ((_focusedGapIndex != null)
                ? _focusedGapIndex != i
                : activeIndex != null);
        children.add(gapDimmed ? Opacity(opacity: 0.45, child: gap) : gap);
      }
    }
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

  /// Same as "Show Personality Field" / layout option rows (Player Output choices use this too).
  TextStyle get _layoutOptionTextStyle => TextStyle(
        fontSize: 11,
        color: Colors.grey.shade800,
      );

  CaptionSegment? _activePreviewSegment() {
    if (_locationEditorOpen) return CaptionSegment.location;
    if (_dateEditorOpen) return CaptionSegment.date;
    if (_captionPreviewSelected) return CaptionSegment.caption;
    if (_venuePreviewSelected) return CaptionSegment.venue;
    if (_bylinePreviewSelected) return CaptionSegment.credit;
    return null;
  }

  List<InlineSpan> _buildPreviewSpans({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final active = _activePreviewSegment();
    final activeIndex = _activeFormulaIndex;
    final focusedGap = _focusedGapIndex;
    final activeIndexSegment = (activeIndex != null &&
            activeIndex >= 0 &&
            activeIndex < _template.segmentOrder.length)
        ? _template.segmentOrder[activeIndex]
        : null;
    final dimNonActive =
        active != null || activeIndex != null || focusedGap != null;
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: Colors.grey.shade900,
    );
    final dimStyle = baseStyle.copyWith(color: Colors.grey.shade500);
    final hiStyle = baseStyle.copyWith(
      backgroundColor: const Color(0xFFDDEBFF),
      color: const Color(0xFF1F3F74),
      fontWeight: FontWeight.w600,
    );

    final venue = _previewGameInfo.venue.trim().isEmpty
        ? 'Venue'
        : _previewGameInfo.venue.trim();
    final credit = CaptionFormulaRenderer.formatCreditLine(
      format: _template.creditFormat,
      bylineOptions: _template.bylineOptions,
      photographerName: _previewGameInfo.photographerName,
      agencyName: _previewGameInfo.agencyName,
      iptcMetadata: _previewGameInfo.iptcMetadata,
      sampleAgency: sampleAgency,
      apShortParen: _template.wireStyle == WireStyle.ap,
    );

    String valueAt(int segmentIndex, List<CaptionSegment> order) {
      final s = order[segmentIndex];
      switch (s) {
        case CaptionSegment.location:
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, CaptionSegment.location);
          return CaptionFormulaRenderer.formatLocationLine(
            _previewGameInfo,
            CaptionFormulaRenderer.locationLineOptionsForOccurrence(
                _template, occ),
          );
        case CaptionSegment.date:
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, CaptionSegment.date);
          final f =
              CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
          return CaptionFormulaRenderer.formatTemplateDateLine(
            _previewGameInfo,
            _template,
            uppercaseAll: _template.wireStyle == WireStyle.getty ||
                _template.wireStyle == WireStyle.gettyInternational,
            dateFormulaOverride: f,
          );
        case CaptionSegment.caption:
          return sampleCaption;
        case CaptionSegment.venue:
          return venue;
        case CaptionSegment.credit:
          return credit;
      }
    }

    TextStyle styleFor(CaptionSegment s) {
      if (focusedGap != null) return dimStyle;
      if (activeIndexSegment != null) {
        return s == activeIndexSegment ? hiStyle : dimStyle;
      }
      if (active == s) return hiStyle;
      if (dimNonActive) return dimStyle;
      return baseStyle;
    }

    InlineSpan rawGap(int gapIndex, String text) => TextSpan(
          text: text,
          style: focusedGap != null
              ? (focusedGap == gapIndex ? hiStyle : dimStyle)
              : (dimNonActive ? dimStyle : baseStyle),
        );

    final spans = <InlineSpan>[];
    final order = _template.segmentOrder;
    if (order.isEmpty) return spans;
    final n = order.length;
    final gapStrings = CaptionFormulaRenderer.effectiveSegmentGaps(_template);

    InlineSpan indexedSpan(int i) {
      if (focusedGap != null) {
        return TextSpan(text: valueAt(i, order), style: dimStyle);
      }
      if (activeIndex == null) {
        return TextSpan(text: valueAt(i, order), style: styleFor(order[i]));
      }
      return TextSpan(
        text: valueAt(i, order),
        style: activeIndex == i ? hiStyle : dimStyle,
      );
    }

    spans.add(indexedSpan(0));
    for (var i = 1; i < n; i++) {
      spans.add(rawGap(i - 1, gapStrings[i - 1]));
      spans.add(indexedSpan(i));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutosave();
    final sampleCaption = CaptionFormulaRenderer.randomSinglePlayerCaption(
      _template,
      seed: _captionSampleSeed,
    );
    final playerPreviewText = CaptionFormulaRenderer.randomSinglePlayerPreview(
      _template,
      seed: _captionSampleSeed,
    );
    final previewSpans = _buildPreviewSpans(
      sampleCaption: sampleCaption,
      sampleAgency: _sampleAgencyForWire(_selectedWire),
    );

    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.92;
    final dialogHeight = maxH.clamp(300.0, 720.0);
    // Size to the viewport (minus the insetPadding) up to a cap so the layout
    // stays usable on short windows while using more height on large displays.
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
            borderRadius: BorderRadius.circular(0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom:
                            BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Caption Layout',
                          style: TextStyle(
                            fontSize: 14,
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
                            borderRadius: BorderRadius.circular(0),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(Icons.close,
                                  size: 18, color: Colors.grey.shade600),
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
                          return const SizedBox(
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
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Colors.transparent,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 360,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Caption Style',
                                                        style:
                                                            _sectionTitleStyle
                                                                .copyWith(
                                                          fontSize: 12,
                                                          height: 1.0,
                                                        ),
                                                      ),
                                                      DropdownFlutter<String>(
                                                        key: ValueKey<String>(
                                                          '${_template.id}_'
                                                          '${_captionStyleLibrary.length}_'
                                                          '${_captionStyleLibrary.map((e) => '${e.id}:${e.displayName}').join()}',
                                                        ),
                                                        hintText:
                                                            'Caption Style',
                                                        items:
                                                            _captionStyleDropdownTokens(),
                                                        initialItem:
                                                            _captionStyleDropdownInitialToken(),
                                                        overlayHeight: () {
                                                          final n =
                                                              _captionStyleDropdownTokens()
                                                                  .length;
                                                          final h = n * 40.0;
                                                          if (h < 140)
                                                            return 140.0;
                                                          if (h > 380)
                                                            return 380.0;
                                                          return h;
                                                        }(),
                                                        // Padding is tuned so the natural closed height matches the
                                                        // Player Output Style preview: 2px borders + 6px top/bottom
                                                        // padding + 11px × 1.35 line height ≈ 28.85 px on both.
                                                        closedHeaderPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 9,
                                                                vertical: 6),
                                                        expandedHeaderPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 9,
                                                                vertical: 6),
                                                        listItemPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 4),
                                                        headerBuilder: (ctx,
                                                            selectedItem,
                                                            enabled) {
                                                          return Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                              _captionStyleMenuLabel(
                                                                  selectedItem),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                height: 1.35,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .grey
                                                                    .shade900,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        listItemBuilder: (ctx,
                                                            item,
                                                            isSelected,
                                                            onItemSelect) {
                                                          return InkWell(
                                                            onTap: onItemSelect,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          4),
                                                              child: Row(
                                                                children: [
                                                                  if (item.startsWith(
                                                                      'saved:'))
                                                                    Padding(
                                                                      padding: const EdgeInsets
                                                                          .only(
                                                                          right:
                                                                              6),
                                                                      child:
                                                                          Icon(
                                                                        Icons
                                                                            .bookmark_outline,
                                                                        size:
                                                                            14,
                                                                        color: Colors
                                                                            .grey
                                                                            .shade600,
                                                                      ),
                                                                    ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      _captionStyleMenuLabel(
                                                                          item),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight: isSelected
                                                                            ? FontWeight.w600
                                                                            : FontWeight.w500,
                                                                        color: Colors
                                                                            .grey
                                                                            .shade800,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        decoration:
                                                            CustomDropdownDecoration(
                                                          closedFillColor:
                                                              Colors.white,
                                                          expandedFillColor:
                                                              Colors.white,
                                                          closedBorder:
                                                              Border.all(
                                                                  color: Colors
                                                                      .grey
                                                                      .shade300),
                                                          expandedBorder:
                                                              Border.all(
                                                            color:
                                                                _captionLayoutBlue
                                                                    .withValues(
                                                                        alpha:
                                                                            0.45),
                                                            width: 1,
                                                          ),
                                                          closedBorderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          expandedBorderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          closedShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withValues(
                                                                      alpha:
                                                                          0.03),
                                                              blurRadius: 2,
                                                              offset:
                                                                  const Offset(
                                                                      0, 1),
                                                            ),
                                                          ],
                                                          expandedShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withValues(
                                                                      alpha:
                                                                          0.08),
                                                              blurRadius: 8,
                                                              offset:
                                                                  const Offset(
                                                                      0, 2),
                                                            ),
                                                          ],
                                                          hintStyle: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .grey.shade500,
                                                          ),
                                                          headerStyle:
                                                              TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Colors
                                                                .grey.shade900,
                                                          ),
                                                          listItemStyle:
                                                              TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey.shade800,
                                                          ),
                                                          listItemDecoration:
                                                              const ListItemDecoration(
                                                            selectedColor:
                                                                Color(
                                                                    0xFFEAF2FF),
                                                          ),
                                                          closedSuffixIcon:
                                                              Icon(
                                                            Icons
                                                                .keyboard_arrow_down_rounded,
                                                            size: 14,
                                                            color: Colors
                                                                .grey.shade600,
                                                          ),
                                                          expandedSuffixIcon:
                                                              const Icon(
                                                            Icons
                                                                .keyboard_arrow_up_rounded,
                                                            size: 14,
                                                            color:
                                                                _captionLayoutBlue,
                                                          ),
                                                        ),
                                                        onChanged: (token) {
                                                          if (token == null)
                                                            return;
                                                          _applyCaptionStyleMenuToken(
                                                              token);
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Wrap(
                                                      spacing: 0,
                                                      runSpacing: 2,
                                                      alignment:
                                                          WrapAlignment.end,
                                                      children: [
                                                        Builder(builder: (_) {
                                                          final mode =
                                                              _currentRenameMode();
                                                          String label;
                                                          String tooltip;
                                                          switch (mode) {
                                                            case _RenamePromptMode
                                                                .libraryEntry:
                                                              label = 'Rename';
                                                              tooltip =
                                                                  'Change the name of the saved caption style '
                                                                  'currently selected in the Caption Style menu.';
                                                              break;
                                                            case _RenamePromptMode
                                                                .wireLabel:
                                                              label = 'Rename';
                                                              tooltip =
                                                                  'Change how “${_factoryWireLabel(_selectedWire)}” is labelled in your '
                                                                  'Caption Style menu (e.g. rename Getty to Getty USA). '
                                                                  'The layout itself is unchanged.';
                                                              break;
                                                            case _RenamePromptMode
                                                                .saveAsNewLibrary:
                                                              label =
                                                                  'Save as…';
                                                              tooltip =
                                                                  'Save the current layout to your Caption Style '
                                                                  'menu with a name of your choice.';
                                                              break;
                                                          }
                                                          return Tooltip(
                                                            message: tooltip,
                                                            waitDuration:
                                                                const Duration(
                                                                    milliseconds:
                                                                        400),
                                                            child: TextButton(
                                                              style: TextButton
                                                                  .styleFrom(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                                minimumSize:
                                                                    Size.zero,
                                                                tapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                              ),
                                                              onPressed:
                                                                  _openRenameCaptionStylePrompt,
                                                              child: Text(
                                                                label,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      _captionLayoutBlue,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                        Tooltip(
                                                          message:
                                                              'Copy this layout as Custom so you can edit it '
                                                              'without changing your Getty, Imagn, or AP default.',
                                                          child: TextButton(
                                                            style: TextButton
                                                                .styleFrom(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            onPressed:
                                                                _duplicateCaptionStyle,
                                                            child: Text(
                                                              'Duplicate',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    _captionLayoutBlue,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Tooltip(
                                                          message:
                                                              'Only your own saved caption styles can be removed '
                                                              '(entries at the bottom of the Caption Style menu). '
                                                              'Select one of those first. Built-in Getty / Imagn / AP '
                                                              'cannot be deleted. Your current layout stays open; '
                                                              'use Save to update the active template.',
                                                          waitDuration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      500),
                                                          child: TextButton(
                                                            style: TextButton
                                                                .styleFrom(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            onPressed:
                                                                _selectedSavedStyleId ==
                                                                        null
                                                                    ? null
                                                                    : _deleteSelectedCaptionStyle,
                                                            child: Text(
                                                              'Delete',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: _selectedSavedStyleId ==
                                                                        null
                                                                    ? Colors
                                                                        .grey
                                                                        .shade400
                                                                    : Colors.red
                                                                        .shade700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          'Layout options',
                                                          style:
                                                              _sectionTitleStyle
                                                                  .copyWith(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Tooltip(
                                                          message:
                                                              'Turn optional fields on or off '
                                                              'while you edit.\n'
                                                              'Personality appears first, then Keywords, '
                                                              'in a column beside the caption.\n'
                                                              'Keywords sits below Personality in that column.',
                                                          waitDuration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      400),
                                                          child: Icon(
                                                            Icons.help_outline,
                                                            size: 14,
                                                            color: Colors
                                                                .grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  _layoutOptionalFieldRow(
                                                    label:
                                                        'Show Personality Field:',
                                                    value:
                                                        _showPersonalityField,
                                                    onSave:
                                                        _setShowPersonalityField,
                                                  ),
                                                  _layoutOptionalFieldRow(
                                                    label:
                                                        'Show Keywords Field:',
                                                    value: _showKeywordsField,
                                                    onSave:
                                                        _setShowKeywordsField,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.topRight,
                                              child: LayoutBuilder(
                                                builder: (ctx, cons) {
                                                  // Tight cap + right-align pushes the block flush to the dialog's
                                                  // right edge; still shrinks to available width on narrow windows.
                                                  // `topRight` keeps the right column's top at the same y as the
                                                  // left column's top so the label / dropdown / preview boxes line up.
                                                  const double preferred =
                                                      360.0;
                                                  final double w =
                                                      cons.maxWidth.isFinite
                                                          ? (cons.maxWidth <
                                                                  preferred
                                                              ? cons.maxWidth
                                                              : preferred)
                                                          : preferred;
                                                  return SizedBox(
                                                    width: w,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                          'Player Output Style',
                                                          style:
                                                              _sectionTitleStyle
                                                                  .copyWith(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            height: 1.0,
                                                          ),
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          // Matches the Caption Style dropdown's closed-header
                                                          // padding (horizontal 9, vertical 6) + the same 11px × 1.35
                                                          // text line height, so the two boxes render at an identical
                                                          // ~28.85 px natural height and align top-to-bottom.
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 9,
                                                            vertical: 6,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            border: Border.all(
                                                              color: Colors.grey
                                                                  .shade300,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: SelectionArea(
                                                            child: Text.rich(
                                                              TextSpan(
                                                                text:
                                                                    playerPreviewText,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  height: 1.35,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade900,
                                                                ),
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            SizedBox(
                                                              width: 90,
                                                              child: Text(
                                                                'Team Order:',
                                                                style:
                                                                    _layoutOptionTextStyle,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  _captionTeamOrderChoice(
                                                                    CaptionTeamOrder
                                                                        .teamBefore,
                                                                  ),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  _captionTeamOrderChoice(
                                                                    CaptionTeamOrder
                                                                        .teamAfter,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            SizedBox(
                                                              width: 90,
                                                              child: Text(
                                                                'Number:',
                                                                style:
                                                                    _layoutOptionTextStyle,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  _numberFormatChoice(
                                                                    NumberFormatStyle
                                                                        .hash,
                                                                  ),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  _numberFormatChoice(
                                                                    NumberFormatStyle
                                                                        .parens,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            SizedBox(
                                                              width: 90,
                                                              child: Text(
                                                                'Position:',
                                                                style:
                                                                    _layoutOptionTextStyle,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  _positionToggleChoice(
                                                                      true),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  _positionToggleChoice(
                                                                      false),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            SizedBox(
                                                              width: 90,
                                                              child: Text(
                                                                'Diacritics:',
                                                                style:
                                                                    _layoutOptionTextStyle,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Tooltip(
                                                                    message:
                                                                        'Leave player and opponent names exactly as on the roster.',
                                                                    child: _removeDiacriticsChoice(
                                                                        false),
                                                                  ),
                                                                  const SizedBox(
                                                                      width:
                                                                          12),
                                                                  Tooltip(
                                                                    message:
                                                                        'Strip accents from names in captions (e.g. José → Jose).',
                                                                    child:
                                                                        _removeDiacriticsChoice(
                                                                            true),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0xFFDDDDDD),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade300),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.08),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade50,
                                                      border: Border(
                                                        bottom: BorderSide(
                                                            color: Colors
                                                                .grey.shade300),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          'Preview',
                                                          style:
                                                              _sectionTitleStyle
                                                                  .copyWith(
                                                                      fontSize:
                                                                          11),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          '(randomly generated)',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .grey.shade500,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        _shuffleCaptionButton(),
                                                      ],
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 8),
                                                    child: SelectableText.rich(
                                                      TextSpan(
                                                          children:
                                                              previewSpans),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                        ),
                                        child: Text('Caption Formula',
                                            style: _sectionTitleStyle),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 6, 8, 6),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TapRegion(
                                              onTapOutside: (_) =>
                                                  _deselectFormulaChipStripOnTapOutside(),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _formulaRow(),
                                                  const SizedBox(height: 6),
                                                  _addSegmentRow(),
                                                ],
                                              ),
                                            ),
                                            if (_locationEditorOpen ||
                                                _dateEditorOpen ||
                                                _captionPreviewSelected ||
                                                _venuePreviewSelected ||
                                                _bylinePreviewSelected) ...[
                                              const SizedBox(height: 6),
                                              _activeEditIndicator(),
                                            ],
                                            if (_captionPreviewSelected) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                'The portion of the caption made in the app',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                            if (_venuePreviewSelected) ...[
                                              const SizedBox(height: 3),
                                              // Venue has no dedicated chip editor yet.
                                            ],
                                            if (_bylinePreviewSelected) ...[
                                              const SizedBox(height: 3),
                                              _bylineEditor(),
                                            ],
                                            if (_dateEditorOpen) ...[
                                              const SizedBox(height: 3),
                                              _dateLineEditor(),
                                            ],
                                            if (_locationEditorOpen) ...[
                                              const SizedBox(height: 3),
                                              _locationOptionsEditor(),
                                            ],
                                            if (_locationEditorOpen ||
                                                _dateEditorOpen ||
                                                _captionPreviewSelected ||
                                                _venuePreviewSelected ||
                                                _bylinePreviewSelected) ...[
                                              const SizedBox(height: 6),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: _inlineDoneButton(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 6,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade700),
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _captionLayoutBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _save,
                          child: const Text('Save',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_renameCaptionStylePromptOpen)
                Positioned.fill(child: _renameCaptionStyleNameOverlay()),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the Rename / Save-as prompt should do when the user submits.
enum _RenamePromptMode {
  libraryEntry,
  wireLabel,
  saveAsNewLibrary,
}

/// Narrow separator field used between caption-formula chips.
///
/// Draws its own border so height/centering are deterministic (TextField with
/// an [OutlineInputBorder] plus isDense renders at an awkward height that
/// clashes with the 28px chip row).
class _GapSeparatorField extends StatefulWidget {
  const _GapSeparatorField({
    required this.controller,
    this.onFocusChanged,
  });

  final TextEditingController controller;
  final void Function(bool hasFocus)? onFocusChanged;

  @override
  State<_GapSeparatorField> createState() => _GapSeparatorFieldState();
}

class _GapSeparatorFieldState extends State<_GapSeparatorField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusNodeChanged);
  }

  void _onFocusNodeChanged() {
    widget.onFocusChanged?.call(_focus.hasFocus);
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusNodeChanged);
    if (_focus.hasFocus) {
      widget.onFocusChanged?.call(false);
    }
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
