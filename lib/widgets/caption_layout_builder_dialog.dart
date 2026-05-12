import 'dart:async';
import 'dart:convert';

import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_session_context.dart';
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
  /// the selected wire style's sample label (e.g. Getty USA → "Getty Images").
  /// TODO: wire credit to the IPTC byline/credit fields once available.
  static final GameInfo _baseMockGameInfo = GameInfo(
    gameDate: DateTime(2026, 4, 4),
    city: 'Toronto',
    region: 'Ontario',
    country: 'Canada',
    countryCode: 'CAN',
    venue: 'Rogers Centre',
  );

  /// Fallback IPTC date samples when no folder import has populated prefs yet.
  static const Map<String, String> _mockIptcDates = {
    'DateTimeOriginal': '2026:04:04 14:30:00',
    'CreateDate': '2026:04:04 15:00:00',
    'DateCreated': '20260404',
  };

  /// Session [GameInfo] from prefs (updated when images are imported — EXIF date).
  GameInfo? _loadedGameInfo;

  /// Preview row: prefer live session data, then prefs-loaded data, then mock.
  GameInfo get _previewGameInfo {
    // If the user has already generated a caption this session, use that data.
    final session = CaptionSessionContext.gameInfo;
    if (session != null) {
      return session.copyWith(
        photographerName: session.photographerName.isNotEmpty
            ? session.photographerName
            : CurrentUserService.displayNameOrPlaceholder(),
      );
    }
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
  final Map<WireStyle, CaptionTemplate> _wireDrafts = {};

  /// Custom labels shown in the Caption Style dropdown for built-in wires.
  /// `null` means “use factory name (Getty USA / Imagn / AP / Getty International)”.
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

  /// True when the user opened the [CaptionSegment.customText] snippet — show
  /// a plain text field only, not the full IPTC byline chip row.
  bool _customTextSnippetEditorOpen = false;
  bool _separatorSnippetEditorOpen = false;
  bool _punctuationSnippetEditorOpen = false;
  final TextEditingController _snippetLiteralCtrl = TextEditingController();
  bool _syncingSnippetLiteralCtrl = false;
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

  /// One controller per `BylineFieldKind.custom` occurrence in fieldOrder.
  final List<TextEditingController> _customChipCtrls = [];

  /// Controller for the [CaptionSegment.customText] ("Game identifier") field.
  /// Separate from [_customChipCtrls] which drive [BylineFieldKind.custom] in
  /// the credit line only.
  final TextEditingController _gameIdentifierCtrl = TextEditingController();

  /// Controllers for the typed-override byline fields.
  final TextEditingController _customCreatorCtrl = TextEditingController();
  final TextEditingController _customCreditCtrl = TextEditingController();

  /// Focus for the game identifier inline field inside the full-caption preview.
  final FocusNode _customNarrativeInlineFocus = FocusNode();

  /// Occurrence index of the custom chip whose text field is currently open.
  int? _editingCustomOccurrence;
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
    _gameIdentifierCtrl.addListener(_onGameIdentifierEdited);
    _customCreatorCtrl.addListener(_onCustomCreatorEdited);
    _customCreditCtrl.addListener(_onCustomCreditEdited);
    _snippetLiteralCtrl.addListener(_onSnippetLiteralEdited);
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
    // Sync the standalone game identifier controller.
    if (_gameIdentifierCtrl.text != _template.gameIdentifierText) {
      _gameIdentifierCtrl.text = _template.gameIdentifierText;
    }
    // Sync custom creator / credit controllers.
    if (_customCreatorCtrl.text != _template.bylineOptions.customCreatorText) {
      _customCreatorCtrl.text = _template.bylineOptions.customCreatorText;
    }
    if (_customCreditCtrl.text != _template.bylineOptions.customCreditText) {
      _customCreditCtrl.text = _template.bylineOptions.customCreditText;
    }

    final customCount = _template.bylineOptions.fieldOrder
        .where((k) => k == BylineFieldKind.custom)
        .length;
    final texts = _template.bylineOptions.customTexts;

    // Grow controller list if needed
    while (_customChipCtrls.length < customCount) {
      final ctrl = TextEditingController();
      ctrl.addListener(_onBylineTextEdited);
      _customChipCtrls.add(ctrl);
    }
    // Shrink controller list if needed
    while (_customChipCtrls.length > customCount) {
      final ctrl = _customChipCtrls.removeLast();
      ctrl.removeListener(_onBylineTextEdited);
      ctrl.dispose();
    }
    for (var i = 0; i < _customChipCtrls.length; i++) {
      _customChipCtrls[i].text = i < texts.length ? texts[i] : '';
    }
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
          customTexts: _customChipCtrls.map((c) => c.text).toList(),
        ),
      );
    });
  }

  void _onGameIdentifierEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        gameIdentifierText: _gameIdentifierCtrl.text,
      );
    });
  }

  void _onCustomCreatorEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          customCreatorText: _customCreatorCtrl.text,
        ),
      );
    });
  }

  void _onCustomCreditEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          customCreditText: _customCreditCtrl.text,
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
      _customTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
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
              (segment == CaptionSegment.credit && _bylinePreviewSelected) ||
              (segment == CaptionSegment.customText &&
                  (_customTextSnippetEditorOpen ||
                      (_singleCustomNarrativeInlineEligible &&
                          _activeFormulaIndex == index))) ||
              (segment == CaptionSegment.separator &&
                  _separatorSnippetEditorOpen) ||
              (segment == CaptionSegment.punctuation &&
                  _punctuationSnippetEditorOpen);
      if (currentlyActive && sameModeActive) {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
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
      // Multi–custom narrative still uses the panel editor; single custom is inline in preview.
      _customTextSnippetEditorOpen = segment == CaptionSegment.customText &&
          !_singleCustomNarrativeInlineEligible;
      _separatorSnippetEditorOpen = segment == CaptionSegment.separator;
      _punctuationSnippetEditorOpen = segment == CaptionSegment.punctuation;
      if (_separatorSnippetEditorOpen || _punctuationSnippetEditorOpen) {
        _syncingSnippetLiteralCtrl = true;
        if (segment == CaptionSegment.separator) {
          _snippetLiteralCtrl.text =
              CaptionFormulaRenderer.separatorSnippetFor(_template, index);
        } else {
          _snippetLiteralCtrl.text =
              CaptionFormulaRenderer.punctuationSnippetFor(_template, index);
        }
        _syncingSnippetLiteralCtrl = false;
      }
      if (segment == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, index, CaptionSegment.date);
        final f =
            CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
        _dateFormula = (f ?? _template.dateFormula ?? DateFormula.ap()).clone();
      }
    });
    if (segment == CaptionSegment.customText &&
        _singleCustomNarrativeInlineEligible &&
        _activeFormulaIndex == index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customNarrativeInlineFocus.requestFocus();
      });
    }
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
        case BylineFieldKind.customCreator:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(nameCaps: !o.nameCaps),
          );
          break;
        case BylineFieldKind.customCredit:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(
              creditCaps: !o.creditCaps,
              organizationCaps: !o.creditCaps,
            ),
          );
          break;
        case BylineFieldKind.custom:
          break;
      }
    });
  }

  /// View-order for the byline editor: the persisted [fieldOrder], with any
  /// canonical kinds (name / credit) that aren't already present appended at
  /// the end. The editor always shows these two so users can toggle them
  /// on/off without needing an "Add field" picker.
  /// [customCreator] and [customCredit] are optional — only shown when added.
  List<BylineFieldKind> _bylineViewOrder() {
    final saved = _template.bylineOptions.fieldOrder;
    final result = List<BylineFieldKind>.from(saved);
    for (final k in const [
      BylineFieldKind.name,
      BylineFieldKind.credit,
    ]) {
      if (!result.contains(k)) result.add(k);
    }
    return result;
  }

  /// Toggle whether [kind] renders in the byline. Always promotes [kind] into
  /// the persisted [fieldOrder] (at the position implied by the editor's
  /// view-order) so its slot survives toggling, exactly like the location
  /// editor's per-chip switch.
  void _setBylineKindEnabled(BylineFieldKind kind, bool enabled) {
    if (kind == BylineFieldKind.custom ||
        kind == BylineFieldKind.customCreator ||
        kind == BylineFieldKind.customCredit) return;
    setState(() {
      final view = _bylineViewOrder();
      final order = List<BylineFieldKind>.from(view);
      final disabled = Set<BylineFieldKind>.from(
        _template.bylineOptions.disabledKinds,
      );
      if (enabled) {
        disabled.remove(kind);
      } else {
        disabled.add(kind);
      }
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          disabledKinds: disabled,
        ),
      );
    });
  }

  /// Drag-reorder operating on view-order indices. On first reorder, this
  /// also promotes any canonical kinds that were only in the view (not yet
  /// persisted) into [fieldOrder] so the position survives saves.
  void _reorderBylineFromView(int viewFrom, int viewTo) {
    if (viewFrom == viewTo) return;
    setState(() {
      final view = _bylineViewOrder();
      if (viewFrom < 0 || viewFrom >= view.length) return;
      // "Drop chip X onto chip Y" semantic: X lands AT Y's slot in the
      // post-removal list. See location_formula_editor._reorder for why we
      // do NOT subtract 1 when moving right (that's why dragging chips to
      // the right used to look like a no-op).
      final moved = view.removeAt(viewFrom);
      var insert = viewTo;
      if (insert < 0) insert = 0;
      if (insert > view.length) insert = view.length;
      view.insert(insert, moved);

      // Map custom occurrences across the move so each custom chip's text
      // travels with it (mirrors the existing _reorderBylineField logic).
      final savedOrder = _template.bylineOptions.fieldOrder;
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (moved == BylineFieldKind.custom) {
        // Original occurrence index in the saved order. The editor view is
        // saved + appended-canonical-missing, and customs only live in
        // saved, so the from-occurrence is just "how many customs precede
        // viewFrom in the original saved order". Walk the original saved
        // order until we've seen viewFrom-many chips that match positions
        // in the view.
        final fromOcc = _customOccurrenceAt(
            savedOrder, viewFrom.clamp(0, savedOrder.length));
        // Compute target occurrence: count customs that appear before
        // `insert` in the new view-order, excluding the moved chip itself.
        var toOcc = 0;
        for (var i = 0; i < insert; i++) {
          if (view[i] == BylineFieldKind.custom) toOcc++;
        }
        if (fromOcc < customTexts.length && fromOcc != toOcc) {
          final text = customTexts.removeAt(fromOcc);
          customTexts.insert(toOcc.clamp(0, customTexts.length), text);
          if (fromOcc < _customChipCtrls.length) {
            final ctrl = _customChipCtrls.removeAt(fromOcc);
            _customChipCtrls.insert(
                toOcc.clamp(0, _customChipCtrls.length), ctrl);
          }
          if (_editingCustomOccurrence == fromOcc) {
            _editingCustomOccurrence = toOcc;
          }
        }
      }

      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: view,
          customTexts: customTexts,
        ),
      );
    });
  }

  /// Ensures the byline has at least one custom field so the caption-layout
  /// custom-text snippet editor can show a [TextField] immediately (no extra
  /// "add field" step). Call only from within an existing [setState].
  void _ensureAtLeastOneBylineCustomField() {
    if (_customChipCtrls.isNotEmpty) return;
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    var customTexts = List<String>.from(_template.bylineOptions.customTexts);
    customTexts.add('');
    final ctrl = TextEditingController();
    ctrl.addListener(_onBylineTextEdited);
    _customChipCtrls.add(ctrl);
    _editingCustomOccurrence = 0;
    order.add(BylineFieldKind.custom);
    _template = _template.copyWith(
      bylineOptions: _template.bylineOptions.copyWith(
        fieldOrder: order,
        customTexts: customTexts,
      ),
    );
  }

  void _addBylineField(BylineFieldKind kind) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    // Non-custom fields are unique; custom chips can appear multiple times.
    if (kind != BylineFieldKind.custom && order.contains(kind)) return;
    setState(() {
      order.add(kind);
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (kind == BylineFieldKind.custom) {
        customTexts.add('');
        final ctrl = TextEditingController();
        ctrl.addListener(_onBylineTextEdited);
        _customChipCtrls.add(ctrl);
        // Auto-expand the new chip for editing
        _editingCustomOccurrence = _customChipCtrls.length - 1;
      }
      // customCreator / customCredit store text in their own fields — no
      // customTexts entry needed.
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          customTexts: customTexts,
        ),
      );
    });
  }

  /// Returns the occurrence index (0-based) of [fieldOrder[chipIndex]] among
  /// chips of the same kind that appear before [chipIndex].
  int _customOccurrenceAt(List<BylineFieldKind> order, int chipIndex) {
    int occ = 0;
    for (var i = 0; i < chipIndex; i++) {
      if (order[i] == BylineFieldKind.custom) occ++;
    }
    return occ;
  }

  void _removeBylineFieldAt(int chipIndex) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    if (chipIndex < 0 || chipIndex >= order.length) return;
    final kind = order[chipIndex];
    if (kind == BylineFieldKind.name) return;
    setState(() {
      order.removeAt(chipIndex);
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (kind == BylineFieldKind.custom) {
        final occ =
            _customOccurrenceAt(_template.bylineOptions.fieldOrder, chipIndex);
        if (occ < customTexts.length) customTexts.removeAt(occ);
        if (occ < _customChipCtrls.length) {
          _customChipCtrls[occ].removeListener(_onBylineTextEdited);
          _customChipCtrls[occ].dispose();
          _customChipCtrls.removeAt(occ);
        }
        if (_editingCustomOccurrence != null) {
          if (_editingCustomOccurrence == occ) {
            _editingCustomOccurrence = null;
          } else if (_editingCustomOccurrence! > occ) {
            _editingCustomOccurrence = _editingCustomOccurrence! - 1;
          }
        }
      }
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          customTexts: customTexts,
        ),
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

  /// Ensures [customSeparators] matches the live gap text fields before encoding.
  void _flushGapControllersIntoTemplate() {
    if (_gapControllers.isEmpty) return;
    _template = _template.copyWith(
      customSeparators: _gapControllers.map((c) => c.text).toList(),
    );
  }

  /// Writes the current layout to preferences (active template, optional library row,
  /// field visibility). [syncBuiltInWireDefault] updates the per-wire baseline when
  /// editing a built-in wire (not a named library style).
  Future<void> _persistCaptionLayoutToPreferences({
    bool syncBuiltInWireDefault = false,
    bool allowSkipIfUnchanged = true,
  }) async {
    _autosaveDebounce?.cancel();
    _flushGapControllersIntoTemplate();
    final normalized = _template.normalizePerOccurrenceLists();
    final saveSnapshot = _templateSnapshot(normalized);
    if (allowSkipIfUnchanged &&
        saveSnapshot == _lastSavedTemplateSnapshot &&
        !syncBuiltInWireDefault) {
      return;
    }
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCaptionTemplate(normalized);
    await prefs.saveShowKeywordsField(_showKeywordsField);
    await prefs.saveShowPersonalityField(_showPersonalityField);

    final libId = _selectedSavedStyleId;
    if (libId != null) {
      await prefs.updateCaptionStyleTemplateInLibrary(
        id: libId,
        template: normalized,
      );
    }

    if (syncBuiltInWireDefault &&
        libId == null &&
        _isBuiltInWire(_selectedWire)) {
      await prefs.saveCaptionTemplateWireDefault(_selectedWire, normalized);
    }

    _lastSavedTemplateSnapshot = saveSnapshot;

    List<CaptionStyleLibraryEntry>? refreshedLib;
    if (libId != null) {
      refreshedLib = await prefs.getCaptionStyleLibrary();
    }
    if (!mounted) return;
    _template = normalized;
    final lib = refreshedLib;
    if (lib != null) {
      setState(() => _captionStyleLibrary = lib);
    }
  }

  void _scheduleAutosave() {
    if (!_prefsLoaded) return;
    final snapshot = _templateSnapshot();
    if (snapshot == _lastSavedTemplateSnapshot) return;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        await _persistCaptionLayoutToPreferences(
          syncBuiltInWireDefault: false,
          allowSkipIfUnchanged: true,
        );
      } catch (_) {}
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
        return 'Getty USA';
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
        _customTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
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

  /// True when [t] already has the snippet chip layout (punctuation / separator
  /// segments in segmentOrder). Templates saved before this feature was added
  /// won't have them.
  bool _hasSnippetLayout(CaptionTemplate t) =>
      t.segmentOrder.contains(CaptionSegment.punctuation) ||
      t.segmentOrder.contains(CaptionSegment.separator);

  /// Migrates a legacy template (no snippet chips) to the current factory
  /// segment order while preserving all other user settings (byline, date
  /// format, location options, etc.).
  CaptionTemplate _migrateSnippetLayout(
      CaptionTemplate saved, CaptionTemplate factory) {
    return saved
        .copyWith(
          segmentOrder: List<CaptionSegment>.from(factory.segmentOrder),
          customSeparators: factory.customSeparators != null
              ? List<String>.from(factory.customSeparators!)
              : null,
          separatorSnippets: factory.separatorSnippets != null
              ? List<String>.from(factory.separatorSnippets!)
              : null,
          punctuationSnippets: factory.punctuationSnippets != null
              ? List<String>.from(factory.punctuationSnippets!)
              : null,
        )
        .normalizePerOccurrenceLists();
  }

  /// Factory Getty USA / Imagn / AP / Getty International, or the user's saved
  /// default for that wire. Legacy templates missing snippet chips are silently
  /// migrated to the current factory segment layout on first load.
  CaptionTemplate _wiredBaseline(WireStyle wire) {
    CaptionTemplate apply(CaptionTemplate? saved, CaptionTemplate factory) {
      if (saved == null) return factory;
      if (!_hasSnippetLayout(saved)) {
        return _migrateSnippetLayout(saved, factory);
      }
      return saved;
    }

    switch (wire) {
      case WireStyle.getty:
        return apply(_gettyWireDefault, CaptionTemplate.getty());
      case WireStyle.imagn:
        return apply(_imagnWireDefault, CaptionTemplate.imagn());
      case WireStyle.ap:
        return apply(_apWireDefault, CaptionTemplate.ap());
      case WireStyle.gettyInternational:
        return apply(
            _gettyIntlWireDefault, CaptionTemplate.gettyInternational());
      case WireStyle.custom:
        return apply(_gettyWireDefault, CaptionTemplate.getty());
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
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
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
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
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
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
              : null,
        );
      case WireStyle.custom:
        return _wiredBaseline(WireStyle.getty);
    }
  }

  bool _isBuiltInWire(WireStyle wire) => wire != WireStyle.custom;

  void _rememberCurrentWireDraft() {
    if (!_isBuiltInWire(_selectedWire) || _selectedSavedStyleId != null) return;
    _wireDrafts[_selectedWire] = _deepCopyCaptionTemplate(_template);
  }

  CaptionTemplate _draftOrBaseline(WireStyle wire) {
    final draft = _wireDrafts[wire];
    if (draft != null) {
      return _deepCopyCaptionTemplate(draft).copyWith(wireStyle: wire);
    }
    return _wiredBaseline(wire);
  }

  /// Full JSON round-trip so nested lists (per–date-chip formulas, etc.) stay independent.
  CaptionTemplate _deepCopyCaptionTemplate(CaptionTemplate t) {
    final raw = json.decode(json.encode(t.toJson())) as Map<String, dynamic>;
    return CaptionTemplate.fromJson(raw);
  }

  /// Copies the working layout as [WireStyle.custom] for editing without replacing
  /// the Getty USA / Imagn / AP wire default.
  void _duplicateCaptionStyle() {
    _rememberCurrentWireDraft();
    final previousWire = _selectedWire;
    final copy = _deepCopyCaptionTemplate(_template);
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
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

  Future<void> _setAllStylesAsDefaults() async {
    _rememberCurrentWireDraft();
    final prefs = await PreferencesService.getInstance();
    const wires = <WireStyle>[
      WireStyle.getty,
      WireStyle.imagn,
      WireStyle.ap,
      WireStyle.gettyInternational,
    ];

    final nextDefaults = <WireStyle, CaptionTemplate>{};
    for (final wire in wires) {
      final draft = _wireDrafts[wire];
      final source = draft ?? _wiredBaseline(wire);
      final normalized =
          _deepCopyCaptionTemplate(source).copyWith(wireStyle: wire);
      await prefs.saveCaptionTemplateWireDefault(wire, normalized);
      nextDefaults[wire] = normalized;
    }
    if (!mounted) return;
    setState(() {
      _gettyWireDefault = nextDefaults[WireStyle.getty];
      _imagnWireDefault = nextDefaults[WireStyle.imagn];
      _apWireDefault = nextDefaults[WireStyle.ap];
      _gettyIntlWireDefault = nextDefaults[WireStyle.gettyInternational];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved all caption styles as defaults.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _disposeGapControllers() {
    for (final c in _gapControllers) {
      c.dispose();
    }
    _gapControllers.clear();
  }

  static String _normalizeSep(String raw) {
    return RegExp(r'[,.]').hasMatch(raw)
        ? raw.replaceAll(RegExp(r'\s+'), '')
        : raw;
  }

  void _initGapControllers(CaptionTemplate t) {
    _focusedGapIndex = null;
    _disposeGapControllers();
    // Always match [CaptionFormulaRenderer.effectiveSegmentGaps] so preview and
    // inline fields stay aligned (handles null or wrong-length custom lists).
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(t);
    final normalizedGaps = gaps.map(_normalizeSep).toList();
    for (final g in normalizedGaps) {
      final c = TextEditingController(text: g);
      c.addListener(_onGapEdited);
      _gapControllers.add(c);
    }
    // Apply normalized values back to the template so the preview is correct
    // immediately — even for old saved templates with bad punctuation spacing.
    _template = _template.copyWith(customSeparators: normalizedGaps);
  }

  /// Inserts [kind] into [segmentOrder] immediately after the snippet at
  /// [_activeFormulaIndex], or at the end when no snippet is selected.
  ///
  /// [CaptionSegment.customText] may appear at most once (it maps to the
  /// shared byline custom fields); the menu disables a second add.
  void _addSegmentSnippet(CaptionSegment kind) {
    if (kind == CaptionSegment.customText &&
        _template.segmentOrder.contains(CaptionSegment.customText)) {
      return;
    }
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      final idx = _activeFormulaIndex;
      final insert = (idx != null && idx >= 0 && idx < order.length)
          ? idx + 1
          : order.length;
      order.insert(insert.clamp(0, order.length), kind);
      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: null,
      );
      next = next.copyWith(
        customSeparators: List<String>.from(
          CaptionFormulaRenderer.effectiveSegmentGaps(next),
        ),
      );
      _template = next.normalizePerOccurrenceLists();
      _initGapControllers(_template);
    });
  }

  /// Reorders [CaptionTemplate.segmentOrder] when the user drags one preview
  /// snippet onto another ("drop at target index" semantics, same as byline).
  void _reorderPreviewSegment(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      if (fromIndex < 0 || fromIndex >= order.length) return;
      if (toIndex < 0 || toIndex >= order.length) return;

      final moved = order.removeAt(fromIndex);
      var insert = toIndex;
      if (insert < 0) insert = 0;
      if (insert > order.length) insert = order.length;
      order.insert(insert, moved);

      final oldActive = _activeFormulaIndex;
      if (oldActive != null) {
        int newActive;
        if (oldActive == fromIndex) {
          newActive = insert;
        } else {
          final j = oldActive > fromIndex ? oldActive - 1 : oldActive;
          newActive = j >= insert ? j + 1 : j;
        }
        _activeFormulaIndex =
            newActive.clamp(0, order.length > 0 ? order.length - 1 : 0);
      }

      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: null,
      );
      next = next.copyWith(
        customSeparators: List<String>.from(
          CaptionFormulaRenderer.effectiveSegmentGaps(next),
        ),
      );
      _template = next.normalizePerOccurrenceLists();
      _initGapControllers(_template);
    });
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

  CaptionTemplate _templateWithSeparatorAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.separator)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.separatorSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(separatorSnippets: list);
  }

  CaptionTemplate _templateWithPunctuationAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.punctuation)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.punctuationSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(punctuationSnippets: list);
  }

  void _onSnippetLiteralEdited() {
    if (_syncingSnippetLiteralCtrl) return;
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    final seg = _template.segmentOrder[idx];
    if (seg != CaptionSegment.separator && seg != CaptionSegment.punctuation) {
      return;
    }
    setState(() {
      if (seg == CaptionSegment.separator) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, idx, CaptionSegment.separator);
        _template = _templateWithSeparatorAtOccurrence(
            _template, occ, _snippetLiteralCtrl.text);
      } else {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, idx, CaptionSegment.punctuation);
        _template = _templateWithPunctuationAtOccurrence(
            _template, occ, _snippetLiteralCtrl.text);
      }
    });
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
    _rememberCurrentWireDraft();
    setState(() {
      _selectedSavedStyleId = null;
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _disposeGapControllers();
      _selectedWire = w;
      switch (w) {
        case WireStyle.getty:
        case WireStyle.gettyInternational:
        case WireStyle.imagn:
        case WireStyle.ap:
          final b = _draftOrBaseline(w);
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
            americanEnglish: ref.americanEnglish,
            removeDiacritics: ref.removeDiacritics,
            separator: ref.separator,
            creditFormat: ref.creditFormat,
            bylineOptions: ref.bylineOptions,
            segmentOrder: List<CaptionSegment>.from(ref.segmentOrder),
            customSeparators: List<String>.from(
              CaptionFormulaRenderer.defaultCustomGaps(ref),
            ),
            separatorSnippets: ref.separatorSnippets != null
                ? List<String>.from(ref.separatorSnippets!)
                : null,
            punctuationSnippets: ref.punctuationSnippets != null
                ? List<String>.from(ref.punctuationSnippets!)
                : null,
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
    if (!_prefsLoaded) return;
    try {
      await _persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: true,
        allowSkipIfUnchanged: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caption layout saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save caption layout: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Three modes for the Rename / Save-as dialog:
  ///  * `libraryEntry` — selected style is a saved library entry → rename it.
  ///  * `wireLabel` — selected style is a built-in wire (Getty USA / Imagn / AP) →
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
    // Flush any unsaved changes that were still pending in the debounce buffer.
    final snapshot = _templateSnapshot();
    if (_prefsLoaded && snapshot != _lastSavedTemplateSnapshot) {
      _flushGapControllersIntoTemplate();
      final normalized = _template.normalizePerOccurrenceLists();
      final libId = _selectedSavedStyleId;
      final keywords = _showKeywordsField;
      final personality = _showPersonalityField;
      PreferencesService.getInstance().then((prefs) async {
        try {
          await prefs.saveCaptionTemplate(normalized);
          await prefs.saveShowKeywordsField(keywords);
          await prefs.saveShowPersonalityField(personality);
          if (libId != null) {
            await prefs.updateCaptionStyleTemplateInLibrary(
              id: libId,
              template: normalized,
            );
          }
        } catch (_) {}
      });
    }
    _disposeGapControllers();
    _bylinePrefixCtrl.removeListener(_onBylineTextEdited);
    _bylineBetweenCtrl.removeListener(_onBylineTextEdited);
    _bylineSuffixCtrl.removeListener(_onBylineTextEdited);
    _snippetLiteralCtrl.removeListener(_onSnippetLiteralEdited);
    _bylinePrefixCtrl.dispose();
    _bylineBetweenCtrl.dispose();
    _bylineSuffixCtrl.dispose();
    _snippetLiteralCtrl.dispose();
    for (final ctrl in _customChipCtrls) {
      ctrl.removeListener(_onBylineTextEdited);
      ctrl.dispose();
    }
    _customChipCtrls.clear();
    _gameIdentifierCtrl.removeListener(_onGameIdentifierEdited);
    _gameIdentifierCtrl.dispose();
    _customCreatorCtrl.removeListener(_onCustomCreatorEdited);
    _customCreatorCtrl.dispose();
    _customCreditCtrl.removeListener(_onCustomCreditEdited);
    _customCreditCtrl.dispose();
    _customNarrativeInlineFocus.dispose();
    _renameCaptionStyleNameCtrl?.dispose();
    super.dispose();
  }

  static String _pillShortLabel(CaptionSegment s) {
    switch (s) {
      case CaptionSegment.location:
        return 'Geographical';
      case CaptionSegment.date:
        return 'Date';
      case CaptionSegment.caption:
        return 'Caption';
      case CaptionSegment.customText:
        return 'Game identifier';
      case CaptionSegment.venue:
        return 'IPTC:Location';
      case CaptionSegment.credit:
        return 'IPTC:Byline';
      case CaptionSegment.separator:
        return 'Separator';
      case CaptionSegment.punctuation:
        return 'Custom';
    }
  }

  String _segmentDisplayLabel(CaptionSegment segment, int atIndex) {
    final base = _pillShortLabel(segment);
    if (segment != CaptionSegment.location &&
        segment != CaptionSegment.date &&
        segment != CaptionSegment.separator &&
        segment != CaptionSegment.punctuation) {
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
        !_bylinePreviewSelected &&
        !_customTextSnippetEditorOpen &&
        !_separatorSnippetEditorOpen &&
        !_punctuationSnippetEditorOpen &&
        _focusedGapIndex == null) {
      return const SizedBox.shrink();
    }
    String label;
    if (_focusedGapIndex != null) {
      label = 'Separator';
    } else if (_activeFormulaIndex != null &&
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
                      : _separatorSnippetEditorOpen
                          ? 'Separator'
                          : _punctuationSnippetEditorOpen
                              ? 'Custom'
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
    final saved = _template.bylineOptions;
    final view = _bylineViewOrder();

    // Map view-index -> custom occurrence index. We walk the *view* (which is
    // saved + missing-canonical-appended) but custom occurrences only live in
    // saved order. Since canonical kinds are appended at the end and customs
    // are interleaved with saved-only chips, customs in the view appear in
    // the same relative order as in saved — so a simple running counter on
    // view positions is correct.
    var customOcc = 0;
    final chips = <Widget>[];
    for (var i = 0; i < view.length; i++) {
      final kind = view[i];
      final occ = kind == BylineFieldKind.custom ? customOcc++ : 0;
      chips.add(_bylineFieldChip(
        kind,
        viewIndex: i,
        customOccurrence: occ,
      ));
      if (i < view.length - 1) {
        chips.add(_BylineSeparatorInput(
          key: ValueKey('byline-sep-$i'),
          value: saved.between,
          onChanged: _setBylineBetween,
        ));
      }
    }

    final editingOcc = _editingCustomOccurrence;
    final editingCtrl =
        (editingOcc != null && editingOcc < _customChipCtrls.length)
            ? _customChipCtrls[editingOcc]
            : null;

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
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _BylineWideInput(
                    label: 'Prefix',
                    controller: _bylinePrefixCtrl,
                    width: 110,
                  ),
                  const SizedBox(width: 4),
                  ...chips,
                  const SizedBox(width: 4),
                  _BylineWideInput(
                    label: 'Suffix',
                    controller: _bylineSuffixCtrl,
                    width: 110,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _spaceLegend(),
          // Chip-type palette — add/remove each available field type.
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _BylineAddChipButton(
                label: 'IPTC Creator',
                present: saved.fieldOrder.contains(BylineFieldKind.name),
                onAdd: () => _addBylineField(BylineFieldKind.name),
                onRemove: () {
                  final idx = _template.bylineOptions.fieldOrder
                      .indexOf(BylineFieldKind.name);
                  if (idx >= 0) _removeBylineFieldAt(idx);
                },
              ),
              _BylineAddChipButton(
                label: 'IPTC Credit',
                present: saved.fieldOrder.contains(BylineFieldKind.credit),
                onAdd: () => _addBylineField(BylineFieldKind.credit),
                onRemove: () {
                  final idx = _template.bylineOptions.fieldOrder
                      .indexOf(BylineFieldKind.credit);
                  if (idx >= 0) _removeBylineFieldAt(idx);
                },
              ),
              _BylineAddChipButton(
                label: 'Custom Creator',
                present: saved.fieldOrder.contains(BylineFieldKind.customCreator),
                onAdd: () => _addBylineField(BylineFieldKind.customCreator),
                onRemove: () {
                  final idx = _template.bylineOptions.fieldOrder
                      .indexOf(BylineFieldKind.customCreator);
                  if (idx >= 0) _removeBylineFieldAt(idx);
                },
              ),
              _BylineAddChipButton(
                label: 'Custom Credit',
                present: saved.fieldOrder.contains(BylineFieldKind.customCredit),
                onAdd: () => _addBylineField(BylineFieldKind.customCredit),
                onRemove: () {
                  final idx = _template.bylineOptions.fieldOrder
                      .indexOf(BylineFieldKind.customCredit);
                  if (idx >= 0) _removeBylineFieldAt(idx);
                },
              ),
            ],
          ),
          // Text inputs for custom-typed fields when they are active.
          if (saved.fieldOrder.contains(BylineFieldKind.customCreator)) ...[
            const SizedBox(height: 6),
            _BylineLabeledInput(
              label: 'Custom Creator:',
              controller: _customCreatorCtrl,
            ),
          ],
          if (saved.fieldOrder.contains(BylineFieldKind.customCredit)) ...[
            const SizedBox(height: 6),
            _BylineLabeledInput(
              label: 'Custom Credit:',
              controller: _customCreditCtrl,
            ),
          ],
          if (editingCtrl != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Custom text:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: _GapSeparatorField(controller: editingCtrl),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          _bylinePreviewLine(),
        ],
      ),
    );
  }

  /// Live preview line at the bottom of the byline editor — same pattern as
  /// the location editor's [Preview:] strip. Renders the current
  /// [BylineOptions] against the dialog's preview [GameInfo] so the user can
  /// see exactly what their byline will look like as they toggle / drag /
  /// type.
  Widget _bylinePreviewLine() {
    final g = _previewGameInfo;
    final rendered = CaptionFormulaRenderer.formatCreditLine(
      format: _template.creditFormat,
      bylineOptions: _template.bylineOptions,
      photographerName: g.photographerName,
      agencyName: g.agencyName,
      iptcMetadata: g.iptcMetadata,
      sampleAgency: _sampleAgencyForWire(_selectedWire),
      customTexts: _template.bylineOptions.customTexts,
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
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rendered.isEmpty ? '(empty byline)' : rendered,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: rendered.isEmpty
                    ? Colors.grey.shade500
                    : const Color(0xFF3A3A3A),
                fontStyle:
                    rendered.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _setBylineBetween(String value) {
    if (_bylineBetweenCtrl.text == value) return;
    _bylineBetweenCtrl.text = value;
    _bylineBetweenCtrl.selection =
        TextSelection.collapsed(offset: value.length);
  }

  void _setVenuePrefix(String value) {
    setState(() {
      _template = _template.copyWith(venuePrefix: value);
    });
  }

  void _setVenueSuffix(String value) {
    setState(() {
      _template = _template.copyWith(venueSuffix: value);
    });
  }

  void _setCaptionPrefix(String value) {
    setState(() {
      _template = _template.copyWith(captionPrefix: value);
    });
  }

  void _setCaptionSuffix(String value) {
    setState(() {
      _template = _template.copyWith(captionSuffix: value);
    });
  }

  void _setGameIdentifierPrefix(String value) {
    setState(() {
      _template = _template.copyWith(gameIdentifierPrefix: value);
    });
  }

  void _setGameIdentifierSuffix(String value) {
    setState(() {
      _template = _template.copyWith(gameIdentifierSuffix: value);
    });
  }

  Widget _captionSegmentEditor() {
    final sampleCaption = CaptionFormulaRenderer.randomSinglePlayerCaption(
      _template,
      seed: _captionSampleSeed,
      previewPlayers: CaptionSessionContext.previewPlayers,
      previewActions: CaptionSessionContext.previewActions,
    );
    final rendered =
        '${_template.captionPrefix}$sampleCaption${_template.captionSuffix}';
    return _simpleSegmentSeparatorEditor(
      label: 'Caption',
      body: sampleCaption,
      prefix: _template.captionPrefix,
      suffix: _template.captionSuffix,
      onPrefixChanged: _setCaptionPrefix,
      onSuffixChanged: _setCaptionSuffix,
      rendered: rendered,
    );
  }

  Widget _simpleSegmentSeparatorEditor({
    required String label,
    required String body,
    required String prefix,
    required String suffix,
    required ValueChanged<String> onPrefixChanged,
    required ValueChanged<String> onSuffixChanged,
    required String rendered,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              children: [
                _BylineSeparatorInput(
                  key: ValueKey('$label-prefix'),
                  value: prefix,
                  onChanged: onPrefixChanged,
                ),
                Container(
                  height: 28,
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    border: Border.all(color: const Color(0x14000000)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$label $body',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3A3A3A),
                      height: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _BylineSeparatorInput(
                  key: ValueKey('$label-suffix'),
                  value: suffix,
                  onChanged: onSuffixChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _spaceLegend(),
        const SizedBox(height: 6),
        Padding(
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
                    color: Color(0xFF3A3A3A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _spaceLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '⎵ = space',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _venueEditor() {
    final venue = _previewGameInfo.venue.trim().isEmpty
        ? 'Venue'
        : _previewGameInfo.venue.trim();
    final rendered = '${_template.venuePrefix}$venue${_template.venueSuffix}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              children: [
                _BylineSeparatorInput(
                  key: const ValueKey('venue-prefix'),
                  value: _template.venuePrefix,
                  onChanged: _setVenuePrefix,
                ),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    border: Border.all(color: const Color(0x14000000)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'IPTC:Location $venue',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3A3A3A),
                      height: 1,
                    ),
                  ),
                ),
                _BylineSeparatorInput(
                  key: const ValueKey('venue-suffix'),
                  value: _template.venueSuffix,
                  onChanged: _setVenueSuffix,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _spaceLegend(),
        const SizedBox(height: 6),
        Padding(
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
                    color: Color(0xFF3A3A3A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bylineFieldChip(
    BylineFieldKind kind, {
    required int viewIndex,
    int customOccurrence = 0,
  }) {
    final saved = _template.bylineOptions;
    final isCustomKind = kind == BylineFieldKind.custom ||
        kind == BylineFieldKind.customCreator ||
        kind == BylineFieldKind.customCredit;
    final inSaved = saved.fieldOrder.contains(kind);
    final disabled =
        !isCustomKind && (saved.disabledKinds.contains(kind) || !inSaved);
    final enabled = !disabled;

    String label;
    bool caps;
    switch (kind) {
      case BylineFieldKind.name:
        label = 'IPTC Creator';
        caps = saved.nameCaps;
        break;
      case BylineFieldKind.credit:
        label = 'IPTC Credit';
        caps = saved.creditCaps;
        break;
      case BylineFieldKind.copyright:
        label = 'IPTC Copyright';
        caps = saved.copyrightCaps;
        break;
      case BylineFieldKind.custom:
        label = 'Custom text';
        caps = false;
        break;
      case BylineFieldKind.customCreator:
        label = 'Custom Creator';
        caps = saved.nameCaps;
        break;
      case BylineFieldKind.customCredit:
        label = 'Custom Credit';
        caps = saved.creditCaps;
        break;
    }

    final sample = _bylineSampleValue(kind, customOccurrence: customOccurrence);
    final isEditingThis = kind == BylineFieldKind.custom
        ? _editingCustomOccurrence == customOccurrence
        : false;

    Widget buildChipBody({required Widget handle}) {
      return Opacity(
        opacity: enabled || isCustomKind ? 1.0 : 0.55,
        child: Container(
          height: 28,
          padding: const EdgeInsets.only(left: 2, right: 6),
          decoration: BoxDecoration(
            color: isEditingThis
                ? const Color(0xFFEEF4FF)
                : const Color(0xFFF4F4F5),
            border: Border.all(
              color: isEditingThis
                  ? const Color(0xFF2563EB)
                  : const Color(0x14000000),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 4),
              if (!isCustomKind) ...[
                _BylineChipSwitch(
                  value: enabled,
                  onChanged: (v) => _setBylineKindEnabled(kind, v),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3A),
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  sample,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (isCustomKind) ...[
                if (kind == BylineFieldKind.custom) ...[
                  _BylineChipIconButton(
                    tooltip: 'Edit text',
                    onTap: () => setState(() {
                      _editingCustomOccurrence =
                          _editingCustomOccurrence == customOccurrence
                              ? null
                              : customOccurrence;
                    }),
                    background:
                        isEditingThis ? const Color(0xFFD0E3FA) : Colors.white,
                    child: Icon(
                      Icons.edit_outlined,
                      size: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _BylineChipIconButton(
                  tooltip: 'Remove',
                  onTap: () => _removeBylineFieldAtView(viewIndex),
                  background: Colors.white,
                  child: Icon(
                    Icons.close,
                    size: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ] else ...[
                _BylineChipIconButton(
                  tooltip: 'ALL CAPS',
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
      data: viewIndex,
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
      onWillAcceptWithDetails: (d) => d.data != viewIndex,
      onAcceptWithDetails: (d) => _reorderBylineFromView(d.data, viewIndex),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: hot ? _captionLayoutBlue : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: hot ? _captionLayoutBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: chipCore,
        );
      },
    );
  }

  /// View-index aware variant of [_removeBylineFieldAt]. The view contains
  /// chips that aren't in the persisted [fieldOrder] yet (canonical kinds
  /// appended for display only). Removing those is a no-op since they're
  /// already absent from saved. For chips that are in saved, find the saved
  /// index and delegate.
  void _removeBylineFieldAtView(int viewIndex) {
    final view = _bylineViewOrder();
    if (viewIndex < 0 || viewIndex >= view.length) return;
    final kind = view[viewIndex];
    final saved = _template.bylineOptions.fieldOrder;
    if (kind == BylineFieldKind.custom) {
      // Customs only live in saved, and saved-customs preserve the same
      // relative order as view-customs, so the saved index for this view
      // chip is the count of saved chips up to viewIndex (clamped).
      final customsBefore =
          view.take(viewIndex).where((k) => k == BylineFieldKind.custom).length;
      var savedIdx = -1;
      var seen = 0;
      for (var i = 0; i < saved.length; i++) {
        if (saved[i] == BylineFieldKind.custom) {
          if (seen == customsBefore) {
            savedIdx = i;
            break;
          }
          seen++;
        }
      }
      if (savedIdx == -1) return;
      _removeBylineFieldAt(savedIdx);
      return;
    }
    // Non-custom kinds appear at most once in saved.
    final savedIdx = saved.indexOf(kind);
    if (savedIdx == -1) return;
    _removeBylineFieldAt(savedIdx);
  }

  /// Sample value rendered in each chip's body (so users can see what the
  /// chip will produce without checking the live preview line below).
  /// Non-custom samples come from the dialog's [_previewGameInfo] / wire
  /// fallback, so they automatically reflect imported IPTC data when
  /// available; custom returns the user's typed text (or "<custom text>" when
  /// empty).
  String _bylineSampleValue(
    BylineFieldKind kind, {
    int customOccurrence = 0,
  }) {
    String sample;
    String fromIptc(List<String> keys) {
      for (final k in keys) {
        final v = _previewGameInfo.iptcMetadata[k]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final agency = _sampleAgencyForWire(_selectedWire);
    switch (kind) {
      case BylineFieldKind.name:
        sample = _previewGameInfo.photographerName.trim();
        if (sample.isEmpty) sample = 'Photographer';
        if (_template.bylineOptions.nameCaps) sample = sample.toUpperCase();
        return sample;
      case BylineFieldKind.credit:
        sample = _previewGameInfo.agencyName.trim();
        if (sample.isEmpty) sample = fromIptc(const ['IPTC:Credit', 'Credit']);
        if (sample.isEmpty) {
          sample = CaptionFormulaRenderer.defaultAgencyLabel(agency);
        }
        if (_template.bylineOptions.creditCaps ||
            _template.bylineOptions.organizationCaps) {
          sample = sample.toUpperCase();
        }
        return sample;
      case BylineFieldKind.copyright:
        sample = fromIptc(const [
          'IPTC:CopyrightNotice',
          'CopyrightNotice',
          'Copyright',
          'XMP:Copyright',
        ]);
        if (sample.isEmpty) {
          sample = CaptionFormulaRenderer.defaultAgencyLabel(agency);
        }
        if (_template.bylineOptions.copyrightCaps)
          sample = sample.toUpperCase();
        return sample;
      case BylineFieldKind.custom:
        final txt = customOccurrence < _customChipCtrls.length
            ? _customChipCtrls[customOccurrence].text.trim()
            : '';
        return txt.isEmpty ? '<custom text>' : txt;
      case BylineFieldKind.customCreator:
        final txt = _customCreatorCtrl.text.trim();
        return txt.isEmpty ? '<type name>' : txt;
      case BylineFieldKind.customCredit:
        final txt = _customCreditCtrl.text.trim();
        return txt.isEmpty ? '<type credit>' : txt;
    }
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

  Widget _americanEnglishChoice(bool american) {
    final label = american ? 'American' : 'International';
    return _checkOptionChip(
      selected: _template.americanEnglish == american,
      label: label,
      onTap: () => setState(() {
        _template = _template.copyWith(americanEnglish: american);
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
      sampleGameInfo: _previewGameInfo,
    );
  }

  Widget _dateLineEditor() {
    return DateFormulaEditor(
      formula: _dateFormula,
      onChanged: _commitDateFormula,
      sampleDate: _previewGameInfo.gameDate,
    );
  }

  static const TextStyle _captionFullPreviewStyle = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: Color(0xFF3A3A3A),
    fontWeight: FontWeight.w500,
  );

  /// Game identifier is edited via the panel editor, not inline in the preview.
  bool get _singleCustomNarrativeInlineEligible => false;

  Widget _fullCaptionPreviewArea({
    required String fullCaptionPreview,
    required CaptionPreviewNarrativeSplit? narrativeSplit,
  }) {
    if (narrativeSplit != null) {
      // No SelectionArea here — it swallows taps before the TextField gets them.
      return LayoutBuilder(
        builder: (context, c) {
          final fieldMax = (c.maxWidth * 0.55).clamp(80.0, 360.0);
          return Text.rich(
            TextSpan(
              style: _captionFullPreviewStyle,
              children: [
                TextSpan(text: narrativeSplit.before),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 72,
                      maxWidth: fieldMax,
                    ),
                      child: TextField(
                        focusNode: _customNarrativeInlineFocus,
                        controller: _gameIdentifierCtrl,
                        style: _captionFullPreviewStyle,
                        strutStyle: StrutStyle.fromTextStyle(
                          _captionFullPreviewStyle,
                          forceStrutHeight: true,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: false,
                          contentPadding: const EdgeInsets.only(bottom: 2),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.blue.shade300, width: 1.5),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.blue.shade200, width: 1.5),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.blue.shade500, width: 2),
                          ),
                          hintText: 'type here…',
                          hintStyle: _captionFullPreviewStyle.copyWith(
                            color: Colors.grey.shade400,
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                      ),
                  ),
                ),
                TextSpan(text: narrativeSplit.after),
              ],
            ),
          );
        },
      );
    }
    return SelectionArea(
      child: SelectableText(
        fullCaptionPreview,
        style: _captionFullPreviewStyle,
      ),
    );
  }

  /// Plain editor for the narrative [CaptionSegment.customText] slot — not the
  /// IPTC byline chip row (name / credit / copyright).
  Widget _customTextSnippetEditor() {
    final rendered = '${_template.gameIdentifierPrefix}'
        '${_gameIdentifierCtrl.text}'
        '${_template.gameIdentifierSuffix}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BylineSeparatorInput(
              key: const ValueKey('game-identifier-prefix'),
              value: _template.gameIdentifierPrefix,
              onChanged: _setGameIdentifierPrefix,
            ),
            Expanded(
              child: _CaptionLayoutBorderedMultilineField(
                controller: _gameIdentifierCtrl,
                minLines: 1,
                maxLines: 5,
                autofocus: true,
              ),
            ),
            _BylineSeparatorInput(
              key: const ValueKey('game-identifier-suffix'),
              value: _template.gameIdentifierSuffix,
              onChanged: _setGameIdentifierSuffix,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _spaceLegend(),
        const SizedBox(height: 6),
        Padding(
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
                    color: Color(0xFF3A3A3A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _addSnippetMenuButton() {
    final hasCustomText =
        _template.segmentOrder.contains(CaptionSegment.customText);
    final menuStyle = TextStyle(fontSize: 12, color: Colors.grey.shade900);
    return PopupMenuButton<CaptionSegment>(
      tooltip:
          'Add a snippet after the selected one (or at the end if none selected)',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 30),
      onSelected: _addSegmentSnippet,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: CaptionSegment.location,
          child: Text('Geographical', style: menuStyle),
        ),
        PopupMenuItem(
          value: CaptionSegment.date,
          child: Text('Date', style: menuStyle),
        ),
        PopupMenuItem(
          value: CaptionSegment.caption,
          child: Text('Caption', style: menuStyle),
        ),
        PopupMenuItem(
          value: CaptionSegment.customText,
          enabled: !hasCustomText,
          child: Text(
            hasCustomText
                ? 'Game identifier (already in layout)'
                : 'Game identifier',
            style: menuStyle,
          ),
        ),
        PopupMenuItem(
          value: CaptionSegment.venue,
          child: Text('Venue (IPTC:Location)', style: menuStyle),
        ),
        PopupMenuItem(
          value: CaptionSegment.credit,
          child: Text('Byline (credit)', style: menuStyle),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, size: 13, color: _captionLayoutBlue),
            const SizedBox(width: 4),
            Text(
              'Add snippet',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _captionLayoutBlue,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: _captionLayoutBlue),
          ],
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
    if (_customTextSnippetEditorOpen) return CaptionSegment.customText;
    if (_singleCustomNarrativeInlineEligible) {
      final idx = _activeFormulaIndex;
      if (idx != null &&
          idx >= 0 &&
          idx < _template.segmentOrder.length &&
          _template.segmentOrder[idx] == CaptionSegment.customText) {
        return CaptionSegment.customText;
      }
    }
    if (_separatorSnippetEditorOpen) return CaptionSegment.separator;
    if (_punctuationSnippetEditorOpen) return CaptionSegment.punctuation;
    if (_locationEditorOpen) return CaptionSegment.location;
    if (_dateEditorOpen) return CaptionSegment.date;
    if (_captionPreviewSelected) return CaptionSegment.caption;
    if (_venuePreviewSelected) return CaptionSegment.venue;
    if (_bylinePreviewSelected) {
      final idx = _activeFormulaIndex;
      if (idx != null && idx >= 0 && idx < _template.segmentOrder.length) {
        return _template.segmentOrder[idx];
      }
      return CaptionSegment.credit;
    }
    return null;
  }

  /// Per-snippet-type color palette used in the preview. Background tint shows
  /// at-a-glance which snippet you're looking at; foreground is the readable
  /// text color on that tint. The blue "active" highlight (see [_buildPreviewWidgets])
  /// still wins when a segment is actively being edited.
  static const Map<CaptionSegment, _SegmentTint> _segmentTints = {
    CaptionSegment.location: _SegmentTint(
      bg: Color(0xFFE3F2E8),
      fg: Color(0xFF1E5D33),
    ),
    CaptionSegment.date: _SegmentTint(
      bg: Color(0xFFFFF1D1),
      fg: Color(0xFF7A4E00),
    ),
    CaptionSegment.venue: _SegmentTint(
      bg: Color(0xFFEDE2F8),
      fg: Color(0xFF4A2A82),
    ),
    CaptionSegment.caption: _SegmentTint(
      bg: Color(0xFFEEF0F2),
      fg: Color(0xFF333740),
    ),
    CaptionSegment.customText: _SegmentTint(
      bg: Color(0xFFE8F4FA),
      fg: Color(0xFF1A4A5E),
    ),
    CaptionSegment.credit: _SegmentTint(
      bg: Color(0xFFFCE2E2),
      fg: Color(0xFF8A2727),
    ),
    CaptionSegment.separator: _SegmentTint(
      bg: Color(0xFFFFF4E0),
      fg: Color(0xFF7A4A00),
    ),
    CaptionSegment.punctuation: _SegmentTint(
      bg: Color(0xFFF0F4FF),
      fg: Color(0xFF3A4A7A),
    ),
  };

  List<Widget> _buildPreviewWidgets({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final active = _activePreviewSegment();
    final activeIndex = _activeFormulaIndex;
    final focusedGap = _focusedGapIndex;
    final dimNonActive =
        active != null || activeIndex != null || focusedGap != null;

    final venue = _previewGameInfo.venue.trim().isEmpty
        ? 'Venue'
        : _previewGameInfo.venue.trim();
    final omitCustomInCredit =
        _template.segmentOrder.contains(CaptionSegment.customText);
    final credit = CaptionFormulaRenderer.formatCreditLine(
      format: _template.creditFormat,
      bylineOptions: _template.bylineOptions,
      photographerName: _previewGameInfo.photographerName,
      agencyName: _previewGameInfo.agencyName,
      iptcMetadata: _previewGameInfo.iptcMetadata,
      sampleAgency: sampleAgency,
      apShortParen: _template.wireStyle == WireStyle.ap,
      customTexts: _template.bylineOptions.customTexts,
      includeCustomInCredit: !omitCustomInCredit,
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
            apStyleCaption: _template.wireStyle == WireStyle.ap,
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
          return '${_template.captionPrefix}'
              '$sampleCaption'
              '${_template.captionSuffix}';
        case CaptionSegment.customText:
          return '${_template.gameIdentifierPrefix}'
              '${_template.gameIdentifierText.trim()}'
              '${_template.gameIdentifierSuffix}';
        case CaptionSegment.venue:
          return '${_template.venuePrefix}$venue${_template.venueSuffix}';
        case CaptionSegment.credit:
          return credit;
        case CaptionSegment.separator:
          return _normalizeSep(CaptionFormulaRenderer.separatorSnippetFor(
              _template, segmentIndex));
        case CaptionSegment.punctuation:
          return _normalizeSep(CaptionFormulaRenderer.punctuationSnippetFor(
              _template, segmentIndex));
      }
    }

    _PreviewSegmentState stateFor(int i, CaptionSegment seg) {
      if (focusedGap != null) return _PreviewSegmentState.dim;
      if (activeIndex != null) {
        return activeIndex == i
            ? _PreviewSegmentState.active
            : _PreviewSegmentState.dim;
      }
      if (active == seg) return _PreviewSegmentState.active;
      if (dimNonActive) return _PreviewSegmentState.dim;
      return _PreviewSegmentState.tinted;
    }

    final order = _template.segmentOrder;
    if (order.isEmpty) return const [];
    final n = order.length;

    // Build a list of only content segment indices. Separator/punctuation
    // segments still render in the final caption, but the main layout editor no
    // longer exposes them as editable chips; sub-editors own visible spacing.
    final visibleIndices = <int>[];
    for (var i = 0; i < n; i++) {
      final seg = order[i];
      final isGlue =
          seg == CaptionSegment.punctuation || seg == CaptionSegment.separator;
      if (!isGlue) visibleIndices.add(i);
    }

    final widgets = <Widget>[];
    for (var vi = 0; vi < visibleIndices.length; vi++) {
      final i = visibleIndices[vi];
      final seg = order[i];
      final segState = stateFor(i, seg);
      final rawValue = valueAt(i, order);

      var chipValue = rawValue;
      if (seg == CaptionSegment.customText && chipValue.trim().isEmpty) {
        chipValue = '(no text)';
      }

      final inner = _previewSegmentChip(
        seg: seg,
        value: chipValue,
        state: segState,
        tooltipLabel: _segmentDisplayLabel(seg, i),
        titleLeading: _previewSegmentDragHandle(i),
        onSnippetTap: () => _activateFormulaEditor(index: i, segment: seg),
      );

      final snippetRow = DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != i,
        onAcceptWithDetails: (d) => _reorderPreviewSegment(d.data, i),
        builder: (context, candidate, _) {
          final hot = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: hot ? _captionLayoutBlue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: inner,
          );
        },
      );
      widgets.add(snippetRow);
    }
    return widgets;
  }

  Widget _previewSegmentDragHandle(int viewIndex) {
    return Draggable<int>(
      data: viewIndex,
      feedback: Material(
        color: Colors.transparent,
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child:
            Icon(Icons.drag_indicator, size: 12, color: Colors.grey.shade700),
      ),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child:
            Icon(Icons.drag_indicator, size: 12, color: Colors.grey.shade400),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag to reorder snippets',
          child:
              Icon(Icons.drag_indicator, size: 12, color: Colors.grey.shade500),
        ),
      ),
    );
  }

  /// Snippet chip: title label + value, always coloured so the user can see
  /// every editable segment and knows where to click.
  Widget _previewSegmentChip({
    required CaptionSegment seg,
    required String value,
    required _PreviewSegmentState state,
    required String tooltipLabel,
    Widget? titleLeading,
    VoidCallback? onSnippetTap,
  }) {
    final tint = _segmentTints[seg];
    Color bg;
    Color fg;
    Color labelFg;
    FontWeight weight;
    switch (state) {
      case _PreviewSegmentState.active:
        bg = const Color(0xFFDDEBFF);
        fg = const Color(0xFF1F3F74);
        labelFg = const Color(0xFF1F3F74);
        weight = FontWeight.w600;
        break;
      case _PreviewSegmentState.dim:
        bg = tint?.bg.withValues(alpha: 0.35) ?? const Color(0xFFF0F0F0);
        fg = Colors.grey.shade400;
        labelFg = Colors.grey.shade400;
        weight = FontWeight.normal;
        break;
      case _PreviewSegmentState.tinted:
        bg = tint?.bg ?? const Color(0xFFF0F0F0);
        fg = tint?.fg ?? Colors.grey.shade900;
        labelFg = (tint?.fg ?? Colors.grey.shade700).withValues(alpha: 0.7);
        weight = FontWeight.normal;
        break;
    }

    final chip = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title label row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (titleLeading != null) ...[
                titleLeading,
                const SizedBox(width: 3),
              ],
              Text(
                tooltipLabel,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: labelFg,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Value
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: fg,
              fontWeight: weight,
            ),
          ),
        ],
      ),
    );

    Widget body = Tooltip(
      message: tooltipLabel,
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );

    if (onSnippetTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onSnippetTap,
          child: body,
        ),
      );
    }
    return body;
  }

  /// Plain text rendered between snippet chips. Kept as a single [Text] widget
  /// (no chip background) so the inter-snippet separator visually belongs to
  /// neither side.
  Widget _previewGapText(String text, _PreviewGapState state) {
    TextStyle style;
    switch (state) {
      case _PreviewGapState.active:
        style = const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Color(0xFF1F3F74),
          backgroundColor: Color(0xFFDDEBFF),
          fontWeight: FontWeight.w600,
        );
        break;
      case _PreviewGapState.dim:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Colors.grey.shade400,
        );
        break;
      case _PreviewGapState.normal:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Colors.grey.shade900,
        );
        break;
    }
    return Text(text, style: style);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutosave();
    final previewPlayers = CaptionSessionContext.previewPlayers;
    final previewActions = CaptionSessionContext.previewActions;
    final hasLivePreviewData =
        previewPlayers.isNotEmpty && previewActions.isNotEmpty;
    // Prefer live roster+verb samples; fall back to last rendered caption body.
    final sessionBody = CaptionSessionContext.captionBody;
    final sampleCaption = hasLivePreviewData
        ? CaptionFormulaRenderer.randomSinglePlayerCaption(
            _template,
            seed: _captionSampleSeed,
            previewPlayers: previewPlayers,
            previewActions: previewActions,
          )
        : (sessionBody != null && sessionBody.isNotEmpty
            ? sessionBody
            : CaptionFormulaRenderer.randomSinglePlayerCaption(
                _template,
                seed: _captionSampleSeed,
              ));
    final playerPreviewText = CaptionFormulaRenderer.randomSinglePlayerPreview(
      _template,
      seed: _captionSampleSeed,
      previewPlayers: hasLivePreviewData ? previewPlayers : null,
    );
    final previewAgency = _sampleAgencyForWire(_selectedWire);
    final fullCaptionPreview = CaptionFormulaRenderer.render(
      template: _template,
      game: _previewGameInfo,
      sampleAgency: previewAgency,
      captionOverride: sampleCaption,
    );
    final narrativeSplit = _singleCustomNarrativeInlineEligible
        ? CaptionFormulaRenderer.previewCaptionNarrativeSplit(
            template: _template,
            game: _previewGameInfo,
            sampleAgency: previewAgency,
            captionOverride: sampleCaption,
          )
        : null;
    final previewWidgets = _buildPreviewWidgets(
      sampleCaption: sampleCaption,
      sampleAgency: previewAgency,
    );

    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.92;
    final dialogHeight = maxH.clamp(300.0, 720.0);
    // Size to the viewport (minus the insetPadding) up to a cap so the layout
    // stays usable on short windows while using more height on large displays.
    final dialogWidth = (mq.width - 32).clamp(320.0, 1100.0);

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
                            child: LayoutBuilder(
                              builder: (context, scrollChildConstraints) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: scrollChildConstraints.maxWidth,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        decoration: const BoxDecoration(
                                          color: Colors.transparent,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
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
                                                    constraints:
                                                        const BoxConstraints(
                                                      maxWidth: 360,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .stretch,
                                                          children: [
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                              'Caption Style',
                                                              style:
                                                                  _sectionTitleStyle
                                                                      .copyWith(
                                                                fontSize: 12,
                                                                height: 1.0,
                                                              ),
                                                            ),
                                                            DropdownFlutter<
                                                                String>(
                                                              key: ValueKey<
                                                                  String>(
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
                                                              overlayHeight:
                                                                  () {
                                                                final n =
                                                                    _captionStyleDropdownTokens()
                                                                        .length;
                                                                final h =
                                                                    n * 40.0;
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
                                                                      horizontal:
                                                                          9,
                                                                      vertical:
                                                                          6),
                                                              expandedHeaderPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          9,
                                                                      vertical:
                                                                          6),
                                                              listItemPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          4),
                                                              headerBuilder: (ctx,
                                                                  selectedItem,
                                                                  enabled) {
                                                                return Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child: Text(
                                                                    _captionStyleMenuLabel(
                                                                        selectedItem),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      height:
                                                                          1.35,
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
                                                                  onTap:
                                                                      onItemSelect,
                                                                  child:
                                                                      Padding(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            4),
                                                                    child: Row(
                                                                      children: [
                                                                        if (item
                                                                            .startsWith('saved:'))
                                                                          Padding(
                                                                            padding:
                                                                                const EdgeInsets.only(right: 6),
                                                                            child:
                                                                                Icon(
                                                                              Icons.bookmark_outline,
                                                                              size: 14,
                                                                              color: Colors.grey.shade600,
                                                                            ),
                                                                          ),
                                                                        Expanded(
                                                                          child:
                                                                              Text(
                                                                            _captionStyleMenuLabel(item),
                                                                            maxLines:
                                                                                1,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                            style:
                                                                                TextStyle(
                                                                              fontSize: 11,
                                                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                                                              color: Colors.grey.shade800,
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
                                                                    Colors
                                                                        .white,
                                                                expandedFillColor:
                                                                    Colors
                                                                        .white,
                                                                closedBorder: Border.all(
                                                                    color: Colors
                                                                        .grey
                                                                        .shade300),
                                                                expandedBorder:
                                                                    Border.all(
                                                                  color: _captionLayoutBlue
                                                                      .withValues(
                                                                          alpha:
                                                                              0.45),
                                                                  width: 1,
                                                                ),
                                                                closedBorderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4),
                                                                expandedBorderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            6),
                                                                closedShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withValues(
                                                                            alpha:
                                                                                0.03),
                                                                    blurRadius:
                                                                        2,
                                                                    offset:
                                                                        const Offset(
                                                                            0,
                                                                            1),
                                                                  ),
                                                                ],
                                                                expandedShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withValues(
                                                                            alpha:
                                                                                0.08),
                                                                    blurRadius:
                                                                        8,
                                                                    offset:
                                                                        const Offset(
                                                                            0,
                                                                            2),
                                                                  ),
                                                                ],
                                                                hintStyle:
                                                                    TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade500,
                                                                ),
                                                                headerStyle:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade900,
                                                                ),
                                                                listItemStyle:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade800,
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
                                                                      .grey
                                                                      .shade600,
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
                                                              onChanged:
                                                                  (token) {
                                                                if (token ==
                                                                    null)
                                                                  return;
                                                                _rememberCurrentWireDraft();
                                                                _applyCaptionStyleMenuToken(
                                                                    token);
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Wrap(
                                                            spacing: 0,
                                                            runSpacing: 2,
                                                            alignment:
                                                                WrapAlignment
                                                                    .end,
                                                            children: [
                                                              Builder(
                                                                  builder: (_) {
                                                                final mode =
                                                                    _currentRenameMode();
                                                                String label;
                                                                String tooltip;
                                                                switch (mode) {
                                                                  case _RenamePromptMode
                                                                      .libraryEntry:
                                                                    label =
                                                                        'Rename';
                                                                    tooltip =
                                                                        'Change the name of the saved caption style '
                                                                        'currently selected in the Caption Style menu.';
                                                                    break;
                                                                  case _RenamePromptMode
                                                                      .wireLabel:
                                                                    label =
                                                                        'Rename';
                                                                    tooltip =
                                                                        'Change how “${_factoryWireLabel(_selectedWire)}” is labelled in your '
                                                                        'Caption Style menu (e.g. a shorter label than the default). '
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
                                                                  message:
                                                                      tooltip,
                                                                  waitDuration:
                                                                      const Duration(
                                                                          milliseconds:
                                                                              400),
                                                                  child:
                                                                      TextButton(
                                                                    style: TextButton
                                                                        .styleFrom(
                                                                      padding:
                                                                          const EdgeInsets
                                                                              .symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            2,
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
                                                                        fontSize:
                                                                            10,
                                                                        fontWeight:
                                                                            FontWeight.w600,
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
                                                                    'without changing your Getty USA, Imagn, or AP default.',
                                                                child:
                                                                    TextButton(
                                                                  style: TextButton
                                                                      .styleFrom(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2,
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
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10,
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
                                                                    'After you tune Getty USA / Imagn / AP / Getty International, '
                                                                    'save all of them as your new defaults at once.',
                                                                child:
                                                                    TextButton(
                                                                  style: TextButton
                                                                      .styleFrom(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                    minimumSize:
                                                                        Size.zero,
                                                                    tapTargetSize:
                                                                        MaterialTapTargetSize
                                                                            .shrinkWrap,
                                                                  ),
                                                                  onPressed:
                                                                      _setAllStylesAsDefaults,
                                                                  child: Text(
                                                                    'Set all as defaults',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10,
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
                                                                    'Select one of those first. Built-in Getty USA / Getty International / Imagn / AP '
                                                                    'cannot be deleted. Your current layout stays open; '
                                                                    'use Save to update the active template.',
                                                                waitDuration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            500),
                                                                child:
                                                                    TextButton(
                                                                  style: TextButton
                                                                      .styleFrom(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2,
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
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: _selectedSavedStyleId ==
                                                                              null
                                                                          ? Colors
                                                                              .grey
                                                                              .shade400
                                                                          : Colors
                                                                              .red
                                                                              .shade700,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                'Layout options',
                                                                style:
                                                                    _sectionTitleStyle
                                                                        .copyWith(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
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
                                                                  Icons
                                                                      .help_outline,
                                                                  size: 14,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade600,
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
                                                          value:
                                                              _showKeywordsField,
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
                                                    alignment:
                                                        Alignment.topRight,
                                                    child: LayoutBuilder(
                                                      builder: (ctx, cons) {
                                                        // Tight cap + right-align pushes the block flush to the dialog's
                                                        // right edge; still shrinks to available width on narrow windows.
                                                        // `topRight` keeps the right column's top at the same y as the
                                                        // left column's top so the label / dropdown / preview boxes line up.
                                                        const double preferred =
                                                            360.0;
                                                        final double w = cons
                                                                .maxWidth
                                                                .isFinite
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
                                                                      FontWeight
                                                                          .w600,
                                                                  height: 1.0,
                                                                ),
                                                              ),
                                                              Container(
                                                                width: double
                                                                    .infinity,
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
                                                                  color: Colors
                                                                      .white,
                                                                  border: Border
                                                                      .all(
                                                                    color: Colors
                                                                        .grey
                                                                        .shade300,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              4),
                                                                ),
                                                                child:
                                                                    SelectionArea(
                                                                  child:
                                                                      Text.rich(
                                                                    TextSpan(
                                                                      text:
                                                                          playerPreviewText,
                                                                      style:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        height:
                                                                            1.35,
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
                                                                      'English:',
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
                                                                        _americanEnglishChoice(
                                                                            true),
                                                                        const SizedBox(
                                                                            width:
                                                                                12),
                                                                        _americanEnglishChoice(
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
                                                                          child:
                                                                              _removeDiacriticsChoice(false),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                12),
                                                                        Tooltip(
                                                                          message:
                                                                              'Strip accents from names in captions (e.g. José → Jose).',
                                                                          child:
                                                                              _removeDiacriticsChoice(true),
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
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      border: Border.all(
                                                          color: Colors
                                                              .grey.shade300),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                  alpha: 0.08),
                                                          blurRadius: 4,
                                                          offset: const Offset(
                                                              0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .grey.shade50,
                                                            border: Border(
                                                              bottom: BorderSide(
                                                                  color: Colors
                                                                      .grey
                                                                      .shade300),
                                                            ),
                                                          ),
                                                          child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Text(
                                                                'Preview',
                                                                style: _sectionTitleStyle
                                                                    .copyWith(
                                                                        fontSize:
                                                                            11),
                                                              ),
                                                              const SizedBox(
                                                                  width: 4),
                                                              Text(
                                                                'Shuffle rerolls sample action',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade500,
                                                                ),
                                                              ),
                                                              const Spacer(),
                                                              _addSnippetMenuButton(),
                                                              const SizedBox(
                                                                  width: 4),
                                                              _shuffleCaptionButton(),
                                                            ],
                                                          ),
                                                        ),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 8),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize.min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              Container(
                                                                width: double
                                                                    .infinity,
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .grey
                                                                      .shade50,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              6),
                                                                  border: Border
                                                                      .all(
                                                                    color: Colors
                                                                        .grey
                                                                        .shade300,
                                                                  ),
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 10,
                                                                ),
                                                                child:
                                                                    _fullCaptionPreviewArea(
                                                                  fullCaptionPreview:
                                                                      fullCaptionPreview,
                                                                  narrativeSplit:
                                                                      narrativeSplit,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 10),
                                                              LayoutBuilder(
                                                                builder:
                                                                    (context,
                                                                            c) =>
                                                                        Wrap(
                                                                  spacing: 8,
                                                                  runSpacing: 8,
                                                                  crossAxisAlignment:
                                                                      WrapCrossAlignment
                                                                          .center,
                                                                  children: [
                                                                    for (final w
                                                                        in previewWidgets)
                                                                      ConstrainedBox(
                                                                        constraints:
                                                                            BoxConstraints(
                                                                          maxWidth:
                                                                              c.maxWidth,
                                                                        ),
                                                                        child:
                                                                            w,
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
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_locationEditorOpen ||
                                          _dateEditorOpen ||
                                          _captionPreviewSelected ||
                                          _venuePreviewSelected ||
                                          _bylinePreviewSelected ||
                                          _customTextSnippetEditorOpen) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                                color: Colors.grey.shade300),
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade50,
                                                  border: Border(
                                                    bottom: BorderSide(
                                                        color: Colors
                                                            .grey.shade300),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    _activeEditIndicator(),
                                                    const Spacer(),
                                                    _inlineDoneButton(),
                                                  ],
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        8, 6, 8, 6),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (_captionPreviewSelected)
                                                      _captionSegmentEditor()
                                                    else if (_customTextSnippetEditorOpen)
                                                      _customTextSnippetEditor()
                                                    else if (_venuePreviewSelected)
                                                      _venueEditor()
                                                    else if (_bylinePreviewSelected)
                                                      _bylineEditor(),
                                                    if (_dateEditorOpen)
                                                      _dateLineEditor(),
                                                    if (_locationEditorOpen)
                                                      _locationOptionsEditor(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
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

/// Background + foreground color pair used to tint a [CaptionSegment] in the
/// caption preview. Stand-alone class (not a record) because the project's
/// minimum SDK predates the Dart records feature.
class _SegmentTint {
  const _SegmentTint({required this.bg, required this.fg});
  final Color bg;
  final Color fg;
}

/// Visual state of a single snippet chip in the preview row.
///
/// `tinted` is the resting state where the chip wears its [CaptionSegment]'s
/// background color. `active` is the blue "you're editing this" highlight.
/// `dim` is for "another segment is being edited, fade me out".
enum _PreviewSegmentState { tinted, active, dim }

/// Visual state of a separator between two snippet chips in the preview row.
enum _PreviewGapState { normal, active, dim }

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
  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusNodeChanged);
  }

  void _onFocusNodeChanged() {
    final focused = _focus.hasFocus;
    // Normalize on blur so pre-existing or hand-typed bad spacing is fixed.
    if (_wasFocused && !focused) {
      final raw = widget.controller.text;
      final normalized = _CaptionLayoutBuilderDialogState._normalizeSep(raw);
      if (normalized != raw) {
        widget.controller.value = TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }
    }
    _wasFocused = focused;
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusNodeChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Container(
      width: 56,
      height: 34,
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
            fontSize: 15,
            color: Colors.grey.shade800,
            height: 1.1,
            fontFamily: 'monospace',
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

/// Full-width multiline field matching [_GapSeparatorField] / byline chip
/// borders: white fill, grey border, blue focus ring.
class _CaptionLayoutBorderedMultilineField extends StatefulWidget {
  const _CaptionLayoutBorderedMultilineField({
    required this.controller,
    this.minLines = 1,
    this.maxLines = 5,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final bool autofocus;

  @override
  State<_CaptionLayoutBorderedMultilineField> createState() =>
      _CaptionLayoutBorderedMultilineFieldState();
}

class _CaptionLayoutBorderedMultilineFieldState
    extends State<_CaptionLayoutBorderedMultilineField> {
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = _focus.hasFocus;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: on ? _captionLayoutBlue : Colors.grey.shade300,
          width: on ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade800,
          height: 1.35,
        ),
        cursorColor: _captionLayoutBlue,
        cursorWidth: 1.2,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// Compact iOS-style switch sized to fit inside a 28px-tall byline chip.
///
/// Mirrors the location editor's `_ChipSwitch` so toggles look identical
/// across all three formula editors.
class _BylineChipSwitch extends StatelessWidget {
  const _BylineChipSwitch({required this.value, required this.onChanged});
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
          activeTrackColor: _captionLayoutBlue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Small square button used inside byline chips (Aa, edit pencil, X). Matches
/// the location/date editors' chip-icon button visual language.
class _BylineChipIconButton extends StatelessWidget {
  const _BylineChipIconButton({
    required this.child,
    required this.onTap,
    required this.background,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
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
}

/// 38-character-wide separator input between byline chips. The byline model
/// only stores a single shared between-string, so every separator slot in the
/// row reads/writes the same controller — typing in any one updates them all.
///
/// Mirrors `_LocSeparatorInput` from the location editor: stable key, owns
/// its own [TextEditingController], resyncs in [didUpdateWidget] only when
/// unfocused, wraps everything in a [GestureDetector] so clicks anywhere in
/// the 38×28 box focus on the first try, and never includes the current
/// value in the parent key (which would lose focus on every keystroke and
/// trigger macOS system beeps when backspace bubbles to the OS).
class _BylineSeparatorInput extends StatefulWidget {
  const _BylineSeparatorInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BylineSeparatorInput> createState() => _BylineSeparatorInputState();
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
      fontSize: (style.fontSize ?? 13) * 0.75,
      color: Colors.grey.shade500,
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

class _BylineSeparatorInputState extends State<_BylineSeparatorInput> {
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
  void didUpdateWidget(covariant _BylineSeparatorInput oldWidget) {
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
    final borderColor = _focused ? _captionLayoutBlue : Colors.grey.shade300;
    final borderWidth = _focused ? 1.5 : 1.0;
    const style = TextStyle(
      fontSize: 13,
      color: Color(0xFF3A3A3A),
      height: 1.1,
    );
    final fieldWidth = _fieldWidthFor(_ctrl.text, style);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: Container(
          width: fieldWidth,
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
            style: style,
            textAlign: TextAlign.center,
            cursorWidth: 1.2,
            cursorColor: _captionLayoutBlue,
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
        ),
      ),
    );
  }

  static double _fieldWidthFor(String text, TextStyle style) {
    final visible = text.isEmpty ? ' ' : text.replaceAll(' ', '⎵');
    final painter = TextPainter(
      text: TextSpan(text: visible, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return (painter.width + 18).clamp(38.0, 260.0);
  }
}

/// Wider labeled text field used at the start (Prefix) and end (Suffix) of
/// the byline editor's chip row. Renders the controller-bound input together
/// with a small "Prefix" / "Suffix" caption so users know what slot they're
/// in without having to read documentation.
class _BylineWideInput extends StatelessWidget {
  const _BylineWideInput({
    required this.label,
    required this.controller,
    this.width = 110,
  });

  final String label;
  final TextEditingController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 1),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.4,
              height: 1,
            ),
          ),
        ),
        SizedBox(
          width: width,
          height: 28,
          child: _GapSeparatorField(controller: controller),
        ),
      ],
    );
  }
}

/// Toggle/add button in the byline chip palette. Shows as "active" (blue tint)
/// when [present], with a checkmark; otherwise shows a "+" to add it.
class _BylineAddChipButton extends StatelessWidget {
  const _BylineAddChipButton({
    required this.label,
    required this.present,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final bool present;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: present ? const Color(0xFFEAF2FF) : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: present ? const Color(0xFF2563EB) : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: present ? onRemove : onAdd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                present ? Icons.check : Icons.add,
                size: 11,
                color: present
                    ? const Color(0xFF2563EB)
                    : Colors.grey.shade700,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: present
                      ? const Color(0xFF2563EB)
                      : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labeled inline text field for custom-typed byline values.
class _BylineLabeledInput extends StatelessWidget {
  const _BylineLabeledInput({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 28,
            child: _GapSeparatorField(controller: controller),
          ),
        ),
      ],
    );
  }
}

/// Tiny "+ Custom text" button shown at the right edge of the byline chip row.
/// Custom-text chips are the only kind that supports multiple instances, so unlike
/// name/credit/copyright they're added on demand rather than always shown.
class _BylineAddCustomButton extends StatelessWidget {
  const _BylineAddCustomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add custom text field',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 11, color: Colors.grey.shade700),
                const SizedBox(width: 3),
                Text(
                  'Custom text',
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
