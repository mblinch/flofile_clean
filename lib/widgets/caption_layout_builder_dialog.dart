import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_session_context.dart';
import '../caption_style/caption_style_catalog.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/date_formula.dart';
import '../caption_style/game_info.dart';
import '../caption_style/sport_verb_categories.dart';
import '../caption_style/team_home_place.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/current_user_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'date_formula_editor.dart';
import 'ff_dropdown.dart';
import 'location_formula_editor.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

FfTokens _ffOf(BuildContext context) =>
    Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

/// Caption layout: wire preset or custom formula; preview uses fixed sample metadata.
class CaptionLayoutBuilderDialog extends StatefulWidget {
  const CaptionLayoutBuilderDialog({
    super.key,
    this.embedded = false,
    this.adminMode = false,
    this.initialWire,
    this.initialTemplate,
    this.wireDraftsSeed,
    this.gameIdDraftsSeed,
    this.initialSport,
    this.onDraftChanged,
    this.onWireChanged,
    this.onSportChanged,
    this.onRegisterFlush,
    this.onRegisterSetAllDefaults,
  });

  /// When true, renders without [Dialog] chrome (for embedding in admin).
  final bool embedded;

  /// Edits in-memory wire drafts instead of writing user preferences.
  final bool adminMode;
  final WireStyle? initialWire;
  final CaptionTemplate? initialTemplate;
  final Map<WireStyle, CaptionTemplate>? wireDraftsSeed;
  final Map<WireStyle, Map<String, String>>? gameIdDraftsSeed;
  final String? initialSport;
  final void Function(WireStyle wire, CaptionTemplate template)? onDraftChanged;
  final ValueChanged<WireStyle>? onWireChanged;
  final ValueChanged<String>? onSportChanged;
  final void Function(Future<void> Function() flush)? onRegisterFlush;
  final void Function(Future<void> Function() setAll)? onRegisterSetAllDefaults;

  /// Returns the applied [CaptionTemplate] when Done succeeds; `null` on Cancel.
  static Future<CaptionTemplate?> show(BuildContext context) {
    return showDialog<CaptionTemplate>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (context) => const CaptionLayoutBuilderDialog(),
    );
  }

  @override
  State<CaptionLayoutBuilderDialog> createState() =>
      CaptionLayoutBuilderDialogState();
}

class CaptionLayoutBuilderDialogState extends State<CaptionLayoutBuilderDialog> {
  FfTokens get _t => _ffOf(context);

  /// Sample city / date / venue for preview only (matches sample sentence in renderer).
  /// Photographer is resolved from the signed-in user at build time via
  /// [CurrentUserService]; agency is left blank so the renderer falls back to
  /// the selected wire style's sample label (e.g. Getty USA → "Getty Images").
  /// TODO: wire credit to the IPTC byline/credit fields once available.
  static final GameInfo _baseMockGameInfo = GameInfo(
    gameDate: DateTime(2026, 4, 4),
    city: 'Los Angeles',
    region: 'California',
    regionCode: 'CA',
    country: 'United States',
    countryCode: 'USA',
    venue: 'Los Angeles Sports Stadium',
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

  bool get _isGettyWire =>
      _template.wireStyle == WireStyle.getty ||
      _template.wireStyle == WireStyle.gettyInternational;

  /// Caption preview game. Getty switches between a US club and a non-US club
  /// from the teams already chosen, or the last saved teams for this sport.
  GameInfo get _captionPreviewGame {
    final base = _previewGameInfo;
    if (!_isGettyWire) return base;
    final pick = _gettyPreviewPlace();
    if (pick == null) return base;
    final session = CaptionSessionContext.gameInfo;
    if (session != null &&
        session.city.trim().isNotEmpty &&
        session.city.trim().toLowerCase() == pick.city.trim().toLowerCase()) {
      return session.copyWith(
        photographerName: base.photographerName,
        iptcMetadata: session.iptcMetadata.isNotEmpty
            ? session.iptcMetadata
            : base.iptcMetadata,
      );
    }
    return pick.applyTo(base);
  }

  (String?, String?) get _exampleTeamNames {
    final live = CaptionSessionContext.previewPlayers;
    if (live.isNotEmpty) {
      final home = live.first.team.trim();
      final away = live.first.opponent.trim();
      if (home.isNotEmpty || away.isNotEmpty) {
        return (
          home.isEmpty ? null : home,
          away.isEmpty ? null : away,
        );
      }
    }
    final home = _savedExampleHome?.trim();
    final away = _savedExampleAway?.trim();
    return (
      (home == null || home.isEmpty) ? null : home,
      (away == null || away.isEmpty) ? null : away,
    );
  }

  TeamHomePlace? _gettyPreviewPlace() {
    final names = _exampleTeamNames;
    final home = names.$1 == null ? null : teamHomePlace(names.$1!);
    final away = names.$2 == null ? null : teamHomePlace(names.$2!);
    final wantUs = _gettyPreviewUnitedStates;
    if (home != null && home.isUnitedStates == wantUs) return home;
    if (away != null && away.isUnitedStates == wantUs) return away;
    return wantUs ? (home ?? away) : (away ?? home);
  }

  List<CaptionPreviewPlayer>? _examplePlayersFromTeams() {
    if (CaptionSessionContext.previewPlayers.isNotEmpty) return null;
    final names = _exampleTeamNames;
    final home = names.$1;
    final away = names.$2;
    if (home == null && away == null) return null;
    final team = home ?? away!;
    final opponent = away ?? home!;
    final position = switch (_sessionSport) {
      'hockey' => 'C',
      'basketball' || 'wnba' => 'G',
      'soccer' => 'FW',
      _ => 'P',
    };
    return [
      CaptionPreviewPlayer(team, position, 'Jordan Lee', 12, opponent),
    ];
  }

  late Future<void> _load;
  CaptionTemplate _template = CaptionTemplate.getty();
  CaptionTemplate _lastPreset = CaptionTemplate.getty();

  /// User-saved baselines when switching wires (see [PreferencesService] wire defaults).
  CaptionTemplate? _gettyWireDefault;
  CaptionTemplate? _imagnWireDefault;
  CaptionTemplate? _apWireDefault;
  CaptionTemplate? _cpWireDefault;
  CaptionTemplate? _gettyIntlWireDefault;
  final Map<WireStyle, CaptionTemplate> _wireDrafts = {};

  /// Custom labels shown in the Caption Style dropdown for built-in wires.
  /// `null` means “use factory name (Getty USA / Imagn / AP / Getty International)”.
  String? _gettyWireLabel;
  String? _imagnWireLabel;
  String? _apWireLabel;
  String? _cpWireLabel;
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
  bool _freeTextSnippetEditorOpen = false;
  bool _separatorSnippetEditorOpen = false;
  bool _punctuationSnippetEditorOpen = false;
  final TextEditingController _snippetLiteralCtrl = TextEditingController();
  bool _syncingSnippetLiteralCtrl = false;
  final TextEditingController _freeTextCtrl = TextEditingController();
  bool _syncingFreeTextCtrl = false;
  int? _activeFormulaIndex;

  /// Which formula separator field (index in [customSeparators]) has focus.
  int? _focusedGapIndex;

  /// Controllers for visible punctuation / separator fields in the preview row.
  final Map<int, TextEditingController> _glueSnippetControllers = {};
  bool _syncingGlueSnippetCtrls = false;

  /// [segmentOrder] index of the inline glue field that currently has focus.
  int? _focusedGlueSegmentIndex;
  bool _layoutPrefixFocused = false;
  bool _layoutSuffixFocused = false;
  int _captionSampleSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  bool _prefsLoaded = false;
  String _lastSavedTemplateSnapshot = '';
  /// Set by [_done] so [dispose] does not race a second prefs write.
  bool _appliedOnDone = false;
  Timer? _autosaveDebounce;
  bool _renameCaptionStylePromptOpen = false;
  /// When true, a successful Save as template from the footer closes the dialog.
  bool _closeDialogAfterSaveAs = false;
  /// When set, overrides [_currentRenameMode] (used by Save as template).
  _RenamePromptMode? _forcedRenameMode;
  TextEditingController? _renameCaptionStyleNameCtrl;
  List<CaptionStyleLibraryEntry> _captionStyleLibrary = const [];

  /// Caption screen: Personality / Keywords visibility (same prefs as Preferences dialog).

  /// When set, the dropdown shows this library entry; cleared for wire presets.
  String? _selectedSavedStyleId;

  /// Application sport (baseball / hockey / basketball / soccer) for defaults.
  String _sessionSport = 'baseball';

  /// Resolved game identifier per built-in wire for [_sessionSport].
  final Map<WireStyle, String> _gameIdByWire = {};

  /// Favorite caption-style menu token (per sport), shown with a star in the dropdown.
  String? _favoriteCaptionStyleToken;

  /// Scroll target for "edit snippets below" when tapping Caption Preview.
  final GlobalKey _structureSectionKey = GlobalKey();
  bool _structureHintFlash = false;

  /// Getty caption preview: American is City, State. International is City, Country.
  bool _gettyPreviewUnitedStates = true;

  /// Last home/away saved for the current sport, used when no teams are open.
  String? _savedExampleHome;
  String? _savedExampleAway;
  bool _exampleTeamsLoaded = false;
  Timer? _structureHintFlashTimer;

  static const String _menuTokGetty = 'wire:getty';
  static const String _menuTokImagn = 'wire:imagn';
  static const String _menuTokAp = 'wire:ap';
  static const String _menuTokCp = 'wire:cp';
  static const String _menuTokGettyIntl = 'wire:getty_international';
  static const String _menuTokCustom = 'wire:custom';

  final List<TextEditingController> _gapControllers = [];
  final TextEditingController _layoutPrefixCtrl = TextEditingController();
  final TextEditingController _layoutSuffixCtrl = TextEditingController();
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
    _layoutPrefixCtrl.addListener(_onLayoutPrefixEdited);
    _layoutSuffixCtrl.addListener(_onLayoutSuffixEdited);
    _bylinePrefixCtrl.addListener(_onBylineTextEdited);
    _bylineBetweenCtrl.addListener(_onBylineTextEdited);
    _bylineSuffixCtrl.addListener(_onBylineTextEdited);
    _gameIdentifierCtrl.addListener(_onGameIdentifierEdited);
    _customCreatorCtrl.addListener(_onCustomCreatorEdited);
    _customCreditCtrl.addListener(_onCustomCreditEdited);
    _snippetLiteralCtrl.addListener(_onSnippetLiteralEdited);
    _freeTextCtrl.addListener(_onFreeTextEdited);
    _load = widget.adminMode ? _loadForAdmin() : _loadFromPrefs();
  }

  /// Flushes pending edits (used before admin publish).
  Future<void> flushDraft() async {
    await _persistCaptionLayoutToPreferences(
      syncBuiltInWireDefault: true,
      allowSkipIfUnchanged: false,
    );
  }

  void _seedWireDefaultFromDraft(WireStyle wire, CaptionTemplate template) {
    final copy = _deepCopyCaptionTemplate(template).copyWith(wireStyle: wire);
    switch (wire) {
      case WireStyle.getty:
        _gettyWireDefault = copy;
        break;
      case WireStyle.imagn:
        _imagnWireDefault = copy;
        break;
      case WireStyle.ap:
        _apWireDefault = copy;
        break;
      case WireStyle.cp:
        _cpWireDefault = copy;
        break;
      case WireStyle.gettyInternational:
        _gettyIntlWireDefault = copy;
        break;
      case WireStyle.custom:
        break;
    }
  }

  Future<void> _loadGameIdByWire() async {
    _gameIdByWire.clear();
    if (widget.adminMode && widget.gameIdDraftsSeed != null) {
      for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
        final fromDraft = widget.gameIdDraftsSeed![wire]?[_sessionSport]?.trim();
        _gameIdByWire[wire] = (fromDraft != null && fromDraft.isNotEmpty)
            ? fromDraft
            : defaultGameIdentifierText(_sessionSport);
      }
      return;
    }
    final prefs = await PreferencesService.getInstance();
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      _gameIdByWire[wire] =
          await prefs.resolveGameIdentifierText(wire, _sessionSport);
    }
  }

  Future<void> _loadForAdmin() async {
    _sessionSport = widget.initialSport ?? 'baseball';
    await _loadGameIdByWire();
    final wire = widget.initialWire ?? WireStyle.getty;
    _wireDrafts.clear();
    if (widget.wireDraftsSeed != null) {
      for (final entry in widget.wireDraftsSeed!.entries) {
        final copy =
            _deepCopyCaptionTemplate(entry.value).copyWith(wireStyle: entry.key);
        _wireDrafts[entry.key] = copy;
        _seedWireDefaultFromDraft(entry.key, copy);
      }
    }
    var template = widget.initialTemplate != null
        ? _deepCopyCaptionTemplate(widget.initialTemplate!)
        : _draftOrBaseline(wire);
    template = _withSessionSportGameId(template.copyWith(wireStyle: wire));
    final mergedGaps = CaptionFormulaRenderer.effectiveSegmentGaps(template);
    if (template.customSeparators == null ||
        template.customSeparators!.length != mergedGaps.length) {
      template = template.copyWith(customSeparators: mergedGaps);
    }
    template = template.normalizePerOccurrenceLists();
    if (!mounted) return;
    setState(() {
      _template = template;
      _selectedWire = wire;
      _selectedSavedStyleId = null;
      _prefsLoaded = true;
      _lastSavedTemplateSnapshot = _templateSnapshot(template);
      _lastPreset = _clonePreset(template);
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    widget.onRegisterFlush?.call(flushDraft);
    widget.onRegisterSetAllDefaults?.call(_setAllStylesAsDefaults);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
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

  @override
  void didUpdateWidget(covariant CaptionLayoutBuilderDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.adminMode) return;

    final sportChanged = widget.initialSport != null &&
        widget.initialSport != oldWidget.initialSport;
    if (sportChanged || widget.gameIdDraftsSeed != oldWidget.gameIdDraftsSeed) {
      unawaited(_applyAdminSportChange());
    }
  }

  Future<void> _applyAdminSportChange() async {
    _sessionSport = widget.initialSport ?? _sessionSport;
    await _loadGameIdByWire();
    if (!mounted) return;
    final gid = _gameIdByWire[_selectedWire] ??
        defaultGameIdentifierText(_sessionSport);
    setState(() {
      _template = _template.copyWith(gameIdentifierText: gid);
    });
    _syncBylineControllersFromTemplate();
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
    if (widget.adminMode) {
      widget.onDraftChanged?.call(
        _selectedWire,
        _template.normalizePerOccurrenceLists(),
      );
    } else {
      _scheduleAutosave();
    }
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
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
      _focusedGlueSegmentIndex = null;
    });
  }

  void _activateFormulaEditor({
    required int index,
    required CaptionSegment segment,
  }) {
    if (_coreStyleLocked) return;
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
              (segment == CaptionSegment.freeText &&
                  _freeTextSnippetEditorOpen) ||
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
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _focusedGlueSegmentIndex = null;
        _layoutPrefixFocused = false;
        _layoutSuffixFocused = false;
        return;
      }
      _activeFormulaIndex = index;
      _focusedGapIndex = null;
      _focusedGlueSegmentIndex = null;
      _layoutPrefixFocused = false;
      _layoutSuffixFocused = false;
      _locationEditorOpen = segment == CaptionSegment.location;
      _dateEditorOpen = segment == CaptionSegment.date;
      _captionPreviewSelected = segment == CaptionSegment.caption;
      _venuePreviewSelected = segment == CaptionSegment.venue;
      _bylinePreviewSelected = segment == CaptionSegment.credit;
      // Multi–custom narrative still uses the panel editor; single custom is inline in preview.
      _customTextSnippetEditorOpen = segment == CaptionSegment.customText &&
          !_singleCustomNarrativeInlineEligible;
      _freeTextSnippetEditorOpen = segment == CaptionSegment.freeText;
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
      if (_freeTextSnippetEditorOpen) {
        _syncingFreeTextCtrl = true;
        _freeTextCtrl.text =
            CaptionFormulaRenderer.freeTextBodyFor(_template, index);
        _syncingFreeTextCtrl = false;
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
    if (kind == BylineFieldKind.custom) return;
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

  CaptionTemplate _withSessionSportGameId(CaptionTemplate t) {
    // Named library styles and Custom keep authored game-ID / free-text.
    // Blindly applying the wire sport overlay was wiping "Training camp" etc.
    // on dialog open, then Save wrote the wiped text back into the library.
    if (_selectedSavedStyleId != null || t.isUserAuthoredCaptionStyle) {
      return CaptionTemplate.withSportGameIdentifierDefault(
        t,
        _sessionSport,
        replaceKnownDefaults: false,
      );
    }
    final gid = _gameIdByWire[t.wireStyle] ??
        defaultGameIdentifierText(_sessionSport);
    return CaptionTemplate.applyGameIdentifierText(t, gid);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await PreferencesService.getInstance();
    _sessionSport = await prefs.getCurrentSport();
    final lastTeams = await prefs.getStartupLastTeams(sport: _sessionSport);
    _savedExampleHome = lastTeams.key;
    _savedExampleAway = lastTeams.value;
    _exampleTeamsLoaded = true;
    await _loadGameIdByWire();
    _favoriteCaptionStyleToken =
        await prefs.getFavoriteCaptionStyleToken(sport: _sessionSport);
    // Promote any legacy "Getty International" library entry before we read
    // the library so it doesn't show up alongside the new built-in wire.
    await prefs.migrateGettyInternationalLibraryEntry();
    await prefs.cementGettyFactoryDefaultsIfNeeded();
    var template = _withSessionSportGameId(await prefs.getCaptionTemplate());
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
    final cpDef = await prefs.getCaptionTemplateWireDefault(WireStyle.cp);
    final gettyIntlDef =
        await prefs.getCaptionTemplateWireDefault(WireStyle.gettyInternational);
    final styleLib = await prefs.getCaptionStyleLibrary();
    final gettyLabel = await prefs.getCaptionWireLabel(WireStyle.getty);
    final imagnLabel = await prefs.getCaptionWireLabel(WireStyle.imagn);
    final apLabel = await prefs.getCaptionWireLabel(WireStyle.ap);
    final cpLabel = await prefs.getCaptionWireLabel(WireStyle.cp);
    final gettyIntlLabel =
        await prefs.getCaptionWireLabel(WireStyle.gettyInternational);
    if (!mounted) return;
    setState(() {
      _loadedGameInfo = gameInfo;
      _gettyWireDefault = gettyDef;
      _imagnWireDefault = imagnDef;
      _apWireDefault = apDef;
      _cpWireDefault = cpDef;
      _gettyIntlWireDefault = gettyIntlDef;
      _gettyWireLabel = gettyLabel;
      _imagnWireLabel = imagnLabel;
      _apWireLabel = apLabel;
      _cpWireLabel = cpLabel;
      _gettyIntlWireLabel = gettyIntlLabel;
      _captionStyleLibrary = styleLib;
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

  Future<void> _toggleFavoriteCaptionStyle(String token) async {
    if (widget.adminMode) return;
    final prefs = await PreferencesService.getInstance();
    setState(() {
      if (_favoriteCaptionStyleToken == token) {
        _favoriteCaptionStyleToken = null;
      } else {
        _favoriteCaptionStyleToken = token;
      }
    });
    await prefs.saveFavoriteCaptionStyleToken(
      _favoriteCaptionStyleToken,
      sport: _sessionSport,
    );
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
    if (widget.adminMode) {
      if (syncBuiltInWireDefault &&
          _isBuiltInWire(_selectedWire) &&
          _selectedSavedStyleId == null) {
        _wireDrafts[_selectedWire] = _deepCopyCaptionTemplate(normalized);
        _seedWireDefaultFromDraft(_selectedWire, normalized);
      }
      widget.onDraftChanged?.call(_selectedWire, normalized);
      _lastSavedTemplateSnapshot = saveSnapshot;
      if (mounted) {
        setState(() => _template = normalized);
      }
      return;
    }
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCaptionTemplate(normalized);

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
      // Personal wire baseline (Done) — does not create a named library template.
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
    // Built-in wire edits stay in the dialog until Done or Save as template.
    if (_requiresSaveAsNewStyle) return;
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
      case WireStyle.cp:
        return CreditSampleAgency.ap;
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  String _factoryWireLabel(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return 'Getty';
      case WireStyle.imagn:
        return 'Imagn';
      case WireStyle.ap:
        return 'AP';
      case WireStyle.cp:
        return 'CP';
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
      case WireStyle.cp:
        return _cpWireLabel;
      case WireStyle.gettyInternational:
        return _gettyIntlWireLabel ?? _gettyWireLabel;
      case WireStyle.custom:
        return null;
    }
  }

  String _wireStyleDropdownLabel(WireStyle w) {
    final override = _wireLabelOverride(w);
    if (override != null && override.isNotEmpty) {
      final lower = override.trim().toLowerCase();
      if (lower == 'getty usa' ||
          lower == 'getty international' ||
          lower == 'getty images') {
        return _factoryWireLabel(w);
      }
      return override.trim();
    }
    return _factoryWireLabel(w);
  }

  String _wireMenuToken(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return _menuTokGetty;
      case WireStyle.imagn:
        return _menuTokImagn;
      case WireStyle.ap:
        return _menuTokAp;
      case WireStyle.cp:
        return _menuTokCp;
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
      case _menuTokCp:
        return WireStyle.cp;
      case _menuTokGettyIntl:
        // Legacy token → unified Getty.
        return WireStyle.getty;
      case _menuTokCustom:
        return WireStyle.custom;
      case _menuTokGetty:
      default:
        return WireStyle.getty;
    }
  }

  List<String> _captionStyleDropdownTokens() {
    if (widget.adminMode) {
      return const [
        _menuTokGetty,
        _menuTokImagn,
        _menuTokAp,
        _menuTokCp,
      ];
    }
    final saved = _captionStyleLibrary
        .map((e) => 'saved:${e.id}')
        .toList()
      ..sort(
        (a, b) => _captionStyleMenuLabel(a)
            .toLowerCase()
            .compareTo(_captionStyleMenuLabel(b).toLowerCase()),
      );
    return [
      _menuTokGetty,
      _menuTokImagn,
      _menuTokAp,
      _menuTokCp,
      _menuTokCustom,
      ...saved,
    ];
  }

  /// Built-in Getty / Imagn / AP / CP stay editable for normal users. Done
  /// applies the layout without naming; Save as template creates a library style.
  /// Admin mode can still edit and save wire defaults directly.
  bool get _requiresSaveAsNewStyle =>
      !widget.adminMode &&
      _selectedSavedStyleId == null &&
      _isBuiltInWire(_selectedWire);

  /// Legacy name kept for call sites that gated editing. Built-ins are no longer
  /// read-only; use [_requiresSaveAsNewStyle] for autosave / discard rules.
  bool get _coreStyleLocked => false;

  /// Built-ins are editable; no longer shown as locked in the menu.
  bool _tokenIsLockedCore(String token) => false;

  /// No-op wrapper (built-ins are editable). Kept so call sites stay stable.
  Widget _lockableEditorSurface({required Widget child}) => child;

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
  ///
  /// Do not match nested [CaptionTemplate.id] values like `preset_getty` or
  /// full JSON equality — those false positives made Done update a library
  /// row instead of promoting the live style to Custom.
  String? _libraryEntryIdMatchingActiveTemplate(
    CaptionTemplate template,
    List<CaptionStyleLibraryEntry> lib,
  ) {
    for (final e in lib) {
      if (e.id == template.id) return e.id;
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
      case _menuTokCp:
        return _wireStyleDropdownLabel(WireStyle.cp);
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
      // Keep the authored game-ID / custom text; only fill when empty.
      final applied = CaptionTemplate.withSportGameIdentifierDefault(
        _deepCopyCaptionTemplate(entry.template),
        _sessionSport,
        replaceKnownDefaults: false,
      );
      setState(() {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _disposeGapControllers();
        _selectedSavedStyleId = entry.id;
        _template = applied;
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
      // Selecting a named style should become the live caption style.
      if (!widget.adminMode) {
        unawaited(_persistCaptionLayoutToPreferences(
          syncBuiltInWireDefault: false,
          allowSkipIfUnchanged: false,
        ));
      } else {
        unawaited(PreferencesService.getInstance().then((prefs) async {
          await prefs.saveCaptionTemplate(applied);
        }));
      }
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
          freeTextSnippets: factory.freeTextSnippets != null
              ? List<String>.from(factory.freeTextSnippets!)
              : null,
          freeTextSuffixes: factory.freeTextSuffixes != null
              ? List<String>.from(factory.freeTextSuffixes!)
              : null,
        )
        .normalizePerOccurrenceLists();
  }

  /// Factory Getty USA / Imagn / AP / Getty International, or the user's saved
  /// default for that wire. Legacy templates missing snippet chips are silently
  /// migrated to the current factory segment layout on first load.
  CaptionTemplate _wiredBaseline(WireStyle wire) {
    CaptionTemplate apply(CaptionTemplate? saved, CaptionTemplate factory) {
      var base = saved == null
          ? factory
          : (!_hasSnippetLayout(saved)
              ? _migrateSnippetLayout(saved, factory)
              : saved);
      if (wire == WireStyle.getty || wire == WireStyle.gettyInternational) {
        base = CaptionTemplate.migrateGettyClosingFormulaIfNeeded(base);
      }
      return _withSessionSportGameId(base);
    }

    switch (wire) {
      case WireStyle.getty:
        return apply(_gettyWireDefault, CaptionTemplate.getty())
            .copyWith(includePlayerPosition: false);
      case WireStyle.imagn:
        return apply(_imagnWireDefault, CaptionTemplate.imagn());
      case WireStyle.ap:
        return apply(_apWireDefault, CaptionTemplate.ap());
      case WireStyle.cp:
        return apply(_cpWireDefault, CaptionTemplate.cp());
      case WireStyle.gettyInternational:
        return apply(
                _gettyIntlWireDefault, CaptionTemplate.gettyInternational())
            .copyWith(includePlayerPosition: false);
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
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
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
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
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
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
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
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
              : null,
        );
      case WireStyle.ap:
      case WireStyle.cp:
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
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
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
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
              : null,
        );
      case WireStyle.custom:
        return _wiredBaseline(WireStyle.getty);
    }
  }

  bool _isBuiltInWire(WireStyle wire) => wire != WireStyle.custom;

  void _rememberCurrentWireDraft() {
    if (_coreStyleLocked) return;
    if (!_isBuiltInWire(_selectedWire) || _selectedSavedStyleId != null) return;
    _flushGapControllersIntoTemplate();
    final normalized = _template.normalizePerOccurrenceLists();
    _wireDrafts[_selectedWire] = _deepCopyCaptionTemplate(normalized);
    _seedWireDefaultFromDraft(_selectedWire, normalized);
    widget.onDraftChanged?.call(_selectedWire, normalized);
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
  /// the Getty / Imagn / AP / CP built-in defaults.
  void _duplicateCaptionStyle() {
    _rememberCurrentWireDraft();
    final previousWire = _selectedWire;
    final duplicatedCore = _selectedSavedStyleId == null &&
        _isBuiltInWire(previousWire);
    final sourceLabel = _selectedSavedStyleId != null
        ? _captionStyleMenuLabel('saved:$_selectedSavedStyleId')
        : _wireStyleDropdownLabel(previousWire);
    final copy = _deepCopyCaptionTemplate(_template);
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _freeTextSnippetEditorOpen = false;
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
    // Persist as the live active style immediately so edits apply without
    // requiring "Save as…" to create a named library template.
    if (!widget.adminMode) {
      unawaited(_persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: false,
        allowSkipIfUnchanged: false,
      ));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          duplicatedCore
              ? 'Editing a copy of "$sourceLabel". Save applies it now — '
                  'use Save as… only if you want a named style.'
              : previousWire == WireStyle.custom
                  ? 'Layout duplicated as Custom. Save to keep your caption template.'
                  : 'Copied $sourceLabel layout as Custom. Save to keep it.',
        ),
        duration: const Duration(seconds: 3),
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
      WireStyle.cp,
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
      _cpWireDefault = nextDefaults[WireStyle.cp];
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

  void _disposeGlueSnippetControllers() {
    for (final c in _glueSnippetControllers.values) {
      c.dispose();
    }
    _glueSnippetControllers.clear();
  }

  bool _isGlueSegment(CaptionSegment seg) =>
      seg == CaptionSegment.punctuation || seg == CaptionSegment.separator;

  void _initGlueSnippetControllers(CaptionTemplate t) {
    final order = t.segmentOrder;
    final needed = <int>{};
    for (var i = 0; i < order.length; i++) {
      if (!_isGlueSegment(order[i])) continue;
      needed.add(i);
      final raw = order[i] == CaptionSegment.separator
          ? CaptionFormulaRenderer.separatorSnippetFor(t, i)
          : CaptionFormulaRenderer.punctuationSnippetFor(t, i);
      final value = _normalizeSep(raw);
      final existing = _glueSnippetControllers[i];
      if (existing == null) {
        final c = TextEditingController(text: value);
        final index = i;
        c.addListener(() => _onGlueSnippetEdited(index));
        _glueSnippetControllers[i] = c;
      } else if (existing.text != value) {
        _syncingGlueSnippetCtrls = true;
        existing.text = value;
        existing.selection = TextSelection.collapsed(offset: value.length);
        _syncingGlueSnippetCtrls = false;
      }
    }
    for (final key in _glueSnippetControllers.keys.toList()) {
      if (!needed.contains(key)) {
        _glueSnippetControllers.remove(key)?.dispose();
      }
    }
  }

  void _onGlueSnippetEdited(int segmentIndex) {
    if (_syncingGlueSnippetCtrls) return;
    if (segmentIndex < 0 || segmentIndex >= _template.segmentOrder.length) {
      return;
    }
    final seg = _template.segmentOrder[segmentIndex];
    if (!_isGlueSegment(seg)) return;
    final controller = _glueSnippetControllers[segmentIndex];
    if (controller == null) return;
    setState(() {
      if (seg == CaptionSegment.separator) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, segmentIndex, CaptionSegment.separator);
        _template = _templateWithSeparatorAtOccurrence(
            _template, occ, controller.text);
      } else {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, segmentIndex, CaptionSegment.punctuation);
        _template = _templateWithPunctuationAtOccurrence(
            _template, occ, controller.text);
      }
    });
  }

  String _glueFieldTooltip(int segmentIndex) {
    final order = _template.segmentOrder;
    String? before;
    String? after;
    for (var j = segmentIndex - 1; j >= 0; j--) {
      if (!_isGlueSegment(order[j])) {
        before = _segmentDisplayLabel(order[j], j);
        break;
      }
    }
    for (var j = segmentIndex + 1; j < order.length; j++) {
      if (!_isGlueSegment(order[j])) {
        after = _segmentDisplayLabel(order[j], j);
        break;
      }
    }
    if (before != null && after != null) {
      return 'Separator between $before and $after';
    }
    return order[segmentIndex] == CaptionSegment.separator
        ? 'Separator'
        : 'Punctuation';
  }

  void _onGlueSnippetFocusChanged(int segmentIndex, bool focused) {
    setState(() {
      if (focused) {
        _focusedGlueSegmentIndex = segmentIndex;
        _layoutPrefixFocused = false;
        _layoutSuffixFocused = false;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
      } else if (_focusedGlueSegmentIndex == segmentIndex) {
        _focusedGlueSegmentIndex = null;
      }
    });
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
    // Sync layout prefix/suffix controllers.
    _layoutPrefixCtrl.text = t.layoutPrefix;
    _layoutSuffixCtrl.text = t.layoutSuffix;
    _initGlueSnippetControllers(t);
  }

  void _onLayoutPrefixEdited() {
    setState(() {
      _template = _template.copyWith(layoutPrefix: _layoutPrefixCtrl.text);
    });
    _scheduleAutosave();
  }

  void _onLayoutSuffixEdited() {
    setState(() {
      _template = _template.copyWith(layoutSuffix: _layoutSuffixCtrl.text);
    });
    _scheduleAutosave();
  }

  /// Inserts [kind] into [segmentOrder] immediately after the snippet at
  /// [_activeFormulaIndex], or at the end when no snippet is selected.
  ///
  /// [CaptionSegment.customText] may appear at most once (game identifier);
  /// [CaptionSegment.freeText] may appear multiple times.
  void _addSegmentSnippet(CaptionSegment kind) {
    if (kind == CaptionSegment.customText &&
        _template.segmentOrder.contains(CaptionSegment.customText)) {
      return;
    }
    late final int insertedAt;
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      final idx = _activeFormulaIndex;
      final insert = (idx != null && idx >= 0 && idx < order.length)
          ? idx + 1
          : order.length;
      insertedAt = insert.clamp(0, order.length);
      order.insert(insertedAt, kind);
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
    _scheduleAutosave();
    if (kind == CaptionSegment.freeText ||
        kind == CaptionSegment.customText ||
        kind == CaptionSegment.caption ||
        kind == CaptionSegment.location ||
        kind == CaptionSegment.date ||
        kind == CaptionSegment.venue ||
        kind == CaptionSegment.credit) {
      _activateFormulaEditor(index: insertedAt, segment: kind);
    }
  }

  /// Removes the snippet at [index] from [segmentOrder].
  void _removeSegmentSnippet(int index) {
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      if (index < 0 || index >= order.length) return;
      order.removeAt(index);
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
      if (_activeFormulaIndex == index) {
        _activeFormulaIndex = null;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
      } else if (_activeFormulaIndex != null && _activeFormulaIndex! > index) {
        _activeFormulaIndex = _activeFormulaIndex! - 1;
      }
    });
    _scheduleAutosave();
  }

  /// Reorders [CaptionTemplate.segmentOrder] when the user drags one preview
  /// snippet onto another ("drop at target index" semantics, same as byline).
  void _reorderPreviewSegment(int fromSegmentIndex, int toSegmentIndex) {
    if (fromSegmentIndex == toSegmentIndex) return;
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      if (fromSegmentIndex < 0 || fromSegmentIndex >= order.length) return;
      if (toSegmentIndex < 0 || toSegmentIndex >= order.length) return;
      if (_isGlueSegment(order[fromSegmentIndex])) return;

      final moved = order.removeAt(fromSegmentIndex);
      var insert = toSegmentIndex;
      if (fromSegmentIndex < insert) insert--;
      if (insert < 0) insert = 0;
      if (insert > order.length) insert = order.length;
      order.insert(insert, moved);

      final oldActive = _activeFormulaIndex;
      if (oldActive != null) {
        int newActive;
        if (oldActive == fromSegmentIndex) {
          newActive = insert;
        } else {
          final j =
              oldActive > fromSegmentIndex ? oldActive - 1 : oldActive;
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
    _scheduleAutosave();
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

  CaptionTemplate _templateWithFreeTextAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.freeText)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.freeTextSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(freeTextSnippets: list);
  }

  CaptionTemplate _templateWithFreeTextSuffixAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.freeText)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.freeTextSuffixes!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(freeTextSuffixes: list);
  }

  void _setFreeTextSuffix(String value) {
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    if (_template.segmentOrder[idx] != CaptionSegment.freeText) return;
    setState(() {
      final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
          _template.segmentOrder, idx, CaptionSegment.freeText);
      _template =
          _templateWithFreeTextSuffixAtOccurrence(_template, occ, value);
    });
    _scheduleAutosave();
  }

  void _onFreeTextEdited() {
    if (_syncingFreeTextCtrl) return;
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    if (_template.segmentOrder[idx] != CaptionSegment.freeText) return;
    setState(() {
      final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
          _template.segmentOrder, idx, CaptionSegment.freeText);
      _template =
          _templateWithFreeTextAtOccurrence(_template, occ, _freeTextCtrl.text);
    });
    _scheduleAutosave();
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
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _disposeGapControllers();
      _selectedWire = w;
      widget.onWireChanged?.call(w);
      switch (w) {
        case WireStyle.getty:
        case WireStyle.gettyInternational:
        case WireStyle.imagn:
        case WireStyle.ap:
        case WireStyle.cp:
          final b = _draftOrBaseline(w);
          _template = _withSessionSportGameId(b);
          _lastPreset = _withSessionSportGameId(b);
          break;
        case WireStyle.custom:
          final ref = _lastPreset;
          _template = _withSessionSportGameId(CaptionTemplate.custom(
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
            showPersonalityField: ref.showPersonalityField,
            showKeywordsField: ref.showKeywordsField,
            timingPhraseCaps: ref.timingPhraseCaps,
            includeTimingPhrase: ref.includeTimingPhrase,
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
            freeTextSnippets: ref.freeTextSnippets != null
                ? List<String>.from(ref.freeTextSnippets!)
                : null,
            freeTextSuffixes: ref.freeTextSuffixes != null
                ? List<String>.from(ref.freeTextSuffixes!)
                : null,
            gameIdentifierText: ref.gameIdentifierText,
          ));
          break;
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    // Selecting a wire (or Custom) should become the live caption style, same as
    // picking a named library entry — otherwise only the dialog preview changes
    // until the user happens to hit Save.
    if (!widget.adminMode) {
      unawaited(_persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: false,
        allowSkipIfUnchanged: false,
      ));
    }
  }

  /// Ensures live text fields are copied into [_template] before persist/Done.
  void _flushAllEditorsIntoTemplate() {
    _flushGapControllersIntoTemplate();
    if (!_syncingGlueSnippetCtrls) {
      for (final entry in _glueSnippetControllers.entries) {
        final segmentIndex = entry.key;
        if (segmentIndex < 0 ||
            segmentIndex >= _template.segmentOrder.length) {
          continue;
        }
        final seg = _template.segmentOrder[segmentIndex];
        if (!_isGlueSegment(seg)) continue;
        if (seg == CaptionSegment.separator) {
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              _template.segmentOrder, segmentIndex, CaptionSegment.separator);
          _template = _templateWithSeparatorAtOccurrence(
              _template, occ, entry.value.text);
        } else {
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              _template.segmentOrder,
              segmentIndex,
              CaptionSegment.punctuation);
          _template = _templateWithPunctuationAtOccurrence(
              _template, occ, entry.value.text);
        }
      }
    }
    _template = _template.copyWith(
      gameIdentifierText: _gameIdentifierCtrl.text,
      layoutPrefix: _layoutPrefixCtrl.text,
      layoutSuffix: _layoutSuffixCtrl.text,
    );
  }

  /// Applies the current layout as the active caption style and closes.
  /// Built-in wire edits become [WireStyle.custom] so the style menu shows
  /// Custom. The personal wire baseline is updated too. Named library rows
  /// stay named. Use [_saveAsTemplate] to create a new named style.
  Future<void> _done() async {
    if (!_prefsLoaded) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caption layout is still loading — try Done again.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      _autosaveDebounce?.cancel();
      _flushAllEditorsIntoTemplate();

      final prefs = await PreferencesService.getInstance();
      var toSave = _template.normalizePerOccurrenceLists();
      // Only treat as a named library edit when the user actually selected a
      // saved: menu row (template.id == library entry id). Built-in wires
      // always promote to Custom on Done.
      final libId = _selectedSavedStyleId;
      final editingNamedLibrary = libId != null && toSave.id == libId;
      final sourceWire = _selectedWire;
      final promoteToCustom = !widget.adminMode &&
          !editingNamedLibrary &&
          _isBuiltInWire(sourceWire);

      if (widget.adminMode) {
        await _persistCaptionLayoutToPreferences(
          syncBuiltInWireDefault: true,
          allowSkipIfUnchanged: false,
        );
        toSave = _template.normalizePerOccurrenceLists();
      } else {
        if (promoteToCustom) {
          // Personal baseline for Getty/Imagn/… when that wire is chosen again.
          await prefs.saveCaptionTemplateWireDefault(sourceWire, toSave);
          toSave = _deepCopyCaptionTemplate(toSave).copyWith(
            wireStyle: WireStyle.custom,
            id: 'custom',
            name: 'Custom',
          );
        }

        await prefs.saveCaptionTemplate(toSave);

        if (editingNamedLibrary) {
          await prefs.updateCaptionStyleTemplateInLibrary(
            id: libId,
            template: toSave,
          );
        }

        // Hard verify — do not close if prefs still hold the old style.
        final verify = await prefs.getCaptionTemplateRaw();
        if (verify.wireStyle != toSave.wireStyle ||
            verify.includeTimingPhrase != toSave.includeTimingPhrase ||
            verify.showPersonalityField != toSave.showPersonalityField ||
            verify.showKeywordsField != toSave.showKeywordsField ||
            jsonEncode(verify.segmentOrder.map((e) => e.name).toList()) !=
                jsonEncode(toSave.segmentOrder.map((e) => e.name).toList())) {
          await prefs.saveCaptionTemplate(toSave);
          final retry = await prefs.getCaptionTemplateRaw();
          if (retry.wireStyle != toSave.wireStyle) {
            throw StateError(
              'Caption layout did not save (still ${retry.wireStyle.name}).',
            );
          }
        }

        _appliedOnDone = true;
        if (mounted) {
          setState(() {
            _template = toSave;
            _selectedWire = toSave.wireStyle;
            if (promoteToCustom) {
              _selectedSavedStyleId = null;
              _lastPreset = _clonePreset(_wiredBaseline(sourceWire));
            }
            _lastSavedTemplateSnapshot = _templateSnapshot(toSave);
          });
        }
      }

      if (!mounted) return;
      if (widget.embedded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Caption layout applied.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      Navigator.of(context).pop(toSave);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not apply caption layout: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Opens the name prompt to add the current layout as a named library style.
  void _saveAsTemplate() {
    if (!_prefsLoaded) return;
    _forcedRenameMode = _RenamePromptMode.saveAsNewLibrary;
    _closeDialogAfterSaveAs = !widget.embedded;
    _openRenameCaptionStylePrompt();
  }

  /// Three modes for the Rename / Save-as dialog:
  ///  * `libraryEntry` — selected style is a saved library entry → rename it.
  ///  * `wireLabel` — admin renaming a built-in wire's dropdown label.
  ///  * `saveAsNewLibrary` — save the current layout as a new named template.
  _RenamePromptMode _currentRenameMode() {
    if (_forcedRenameMode != null) return _forcedRenameMode!;
    if (_selectedSavedStyleId != null) return _RenamePromptMode.libraryEntry;
    if (_selectedWire == WireStyle.custom || _requiresSaveAsNewStyle) {
      return _RenamePromptMode.saveAsNewLibrary;
    }
    return _RenamePromptMode.wireLabel;
  }

  void _openRenameCaptionStylePrompt() {
    final mode = _currentRenameMode();
    // Inline rename / Save as template link keeps the dialog open unless the
    // footer Save as template button set [_closeDialogAfterSaveAs].
    if (mode != _RenamePromptMode.saveAsNewLibrary) {
      _closeDialogAfterSaveAs = false;
    }
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
    _closeDialogAfterSaveAs = false;
    _forcedRenameMode = null;
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
              case WireStyle.cp:
                _cpWireLabel = trimmed;
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
          _flushGapControllersIntoTemplate();
          final normalized = _template.normalizePerOccurrenceLists();
          final savedId = await prefs.addCaptionStyleToLibrary(
            displayName: trimmed,
            template: normalized,
          );
          // Apply immediately — naming alone used to only add a library row,
          // so Caption V2 kept rendering the previous active template.
          CaptionTemplate? applied;
          final lib = await prefs.getCaptionStyleLibrary();
          for (final e in lib) {
            if (e.id == savedId) {
              applied = _deepCopyCaptionTemplate(e.template);
              break;
            }
          }
          applied ??= normalized.copyWith(id: savedId, name: trimmed);
          await prefs.saveCaptionTemplate(applied);
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            _captionStyleLibrary = lib;
            _selectedSavedStyleId = savedId;
            _template = applied!;
            _selectedWire = _template.wireStyle;
            _lastSavedTemplateSnapshot = _templateSnapshot(applied);
          });
          snackMessage = 'Saved "$trimmed" and applied it as the active caption style.';
          final shouldClose = _closeDialogAfterSaveAs;
          _closeDialogAfterSaveAs = false;
          if (shouldClose && mounted && !widget.embedded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(snackMessage),
                duration: const Duration(seconds: 2),
              ),
            );
            Navigator.of(context).pop();
            return;
          }
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
        title = 'Save as template';
        submitLabel = 'Save';
        break;
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: _t.surface,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              side: BorderSide(color: _t.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _t.surface,
                    border: Border(bottom: BorderSide(color: _t.divider)),
                  ),
                  child: Text(
                    title.toUpperCase(),
                    style: FfTokens.railLabel.copyWith(
                      color: _t.text.withValues(alpha: 0.70),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: AppDialogLabeledField(
                    label: 'Name',
                    bottomGap: 0,
                    child: AppDialogControlShell(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        style: appDialogFieldTextStyleOf(context),
                        decoration: appDialogBareFieldDecoration(
                          hintText: 'My caption style',
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            _submitRenameCaptionStyleName();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedGreyButton(
                        label: 'Cancel',
                        fontSize: 11,
                        onPressed: _closeRenameCaptionStylePrompt,
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: submitLabel,
                        fontSize: 11,
                        isPrimary: true,
                        onPressed: ok ? _submitRenameCaptionStyleName : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _structureHintFlashTimer?.cancel();
    // Flush pending edits for Custom / named styles only. Built-in edits are
    // applied via Done (or Save as template); Cancel discards them.
    // Skip after Done — that path already wrote prefs and must not be raced.
    final snapshot = _templateSnapshot();
    if (_prefsLoaded &&
        !_appliedOnDone &&
        !_requiresSaveAsNewStyle &&
        snapshot != _lastSavedTemplateSnapshot) {
      _flushGapControllersIntoTemplate();
      final normalized = _template.normalizePerOccurrenceLists();
      final libId = _selectedSavedStyleId;
      PreferencesService.getInstance().then((prefs) async {
        try {
          await prefs.saveCaptionTemplate(normalized);
          if (libId != null && normalized.id == libId) {
            await prefs.updateCaptionStyleTemplateInLibrary(
              id: libId,
              template: normalized,
            );
          }
        } catch (_) {}
      });
    }
    _disposeGapControllers();
    _disposeGlueSnippetControllers();
    _layoutPrefixCtrl.removeListener(_onLayoutPrefixEdited);
    _layoutSuffixCtrl.removeListener(_onLayoutSuffixEdited);
    _layoutPrefixCtrl.dispose();
    _layoutSuffixCtrl.dispose();
    _bylinePrefixCtrl.removeListener(_onBylineTextEdited);
    _bylineBetweenCtrl.removeListener(_onBylineTextEdited);
    _bylineSuffixCtrl.removeListener(_onBylineTextEdited);
    _snippetLiteralCtrl.removeListener(_onSnippetLiteralEdited);
    _freeTextCtrl.removeListener(_onFreeTextEdited);
    _bylinePrefixCtrl.dispose();
    _bylineBetweenCtrl.dispose();
    _bylineSuffixCtrl.dispose();
    _snippetLiteralCtrl.dispose();
    _freeTextCtrl.dispose();
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
      case CaptionSegment.freeText:
        return 'Custom text';
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
        segment != CaptionSegment.punctuation &&
        segment != CaptionSegment.freeText) {
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
        !_freeTextSnippetEditorOpen &&
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
        Text(
          '$label field',
          style: _sectionTitleStyle,
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
    final occByIndex = <int, int>{};
    final included = <int>[];
    for (var i = 0; i < view.length; i++) {
      final kind = view[i];
      final occ = kind == BylineFieldKind.custom ? customOcc++ : 0;
      occByIndex[i] = occ;
      final isCustomKind = kind == BylineFieldKind.custom ||
          kind == BylineFieldKind.customCreator ||
          kind == BylineFieldKind.customCredit;
      final disabled = !isCustomKind &&
          (saved.disabledKinds.contains(kind) ||
              !saved.fieldOrder.contains(kind));
      if (!disabled) included.add(i);
    }
    final chips = <Widget>[];
    for (var n = 0; n < included.length; n++) {
      final i = included[n];
      chips.add(_bylineFieldChip(
        view[i],
        viewIndex: i,
        customOccurrence: occByIndex[i] ?? 0,
      ));
      if (n < included.length - 1) {
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
          _bylinePreviewLine(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _BylineWideInput(
                label: 'Prefix',
                controller: _bylinePrefixCtrl,
                width: 110,
              ),
              ...chips,
              _BylineWideInput(
                label: 'Suffix',
                controller: _bylineSuffixCtrl,
                width: 110,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bylineAddFieldButton(),
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
                    color: _ffOf(context).textSecondary,
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
        ],
      ),
    );
  }

  Widget _fieldPreviewLine(String rendered) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'Preview:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _ffOf(context).textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rendered,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _ffOf(context).text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
              color: _ffOf(context).textSecondary,
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
                    ? _ffOf(context).text.withValues(alpha: 0.45)
                    : _ffOf(context).text,
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
      sport: _sessionSport,
    );
    return _simpleSegmentSeparatorEditor(
      label: 'Caption',
      body: sampleCaption,
      prefix: _template.captionPrefix,
      suffix: _template.captionSuffix,
      onPrefixChanged: _setCaptionPrefix,
      onSuffixChanged: _setCaptionSuffix,
    );
  }

  Widget _simpleSegmentSeparatorEditor({
    required String label,
    required String body,
    required String prefix,
    required String suffix,
    required ValueChanged<String> onPrefixChanged,
    required ValueChanged<String> onSuffixChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: _ffOf(context).divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BylineSeparatorInput(
                key: ValueKey('$label-prefix'),
                value: prefix,
                onChanged: onPrefixChanged,
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _ffOf(context).sunken,
                    border: Border.all(
                      color: _ffOf(context).text.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$label $body',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text,
                      height: 1.3,
                    ),
                  ),
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
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Edited in place, beside the token it belongs to — not in a panel at the bottom of the dialog.',
            style: TextStyle(
              fontSize: 10,
              height: 1.35,
              color: _ffOf(context).text.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
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
        _fieldPreviewLine(rendered),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: _ffOf(context).divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BylineSeparatorInput(
                key: const ValueKey('venue-prefix'),
                value: _template.venuePrefix,
                onChanged: _setVenuePrefix,
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _ffOf(context).sunken,
                    border: Border.all(
                      color: _ffOf(context).text.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'IPTC:Location $venue',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text,
                      height: 1.3,
                    ),
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
          height: 32,
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            border: Border.all(
              color: isEditingThis
                  ? _ffOf(context).accent.withValues(alpha: 0.85)
                  : _ffOf(context).text.withValues(alpha: 0.16),
              width: isEditingThis ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _ffOf(context).text,
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
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: _ffOf(context).textSecondary,
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
                        isEditingThis ? _ffOf(context).selectedFill : _ffOf(context).sunken,
                    child: PhosphorIcon(PhosphorIconsRegular.pencilSimple,
                      size: 11,
                      color: _ffOf(context).textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _BylineChipIconButton(
                  tooltip: 'Remove',
                  onTap: () => _removeBylineFieldAtView(viewIndex),
                  background: _ffOf(context).sunken,
                  child: PhosphorIcon(PhosphorIconsRegular.x,
                    size: 11,
                    color: _ffOf(context).textSecondary,
                  ),
                ),
              ] else ...[
                _BylineChipIconButton(
                  tooltip: 'ALL CAPS',
                  onTap: () => _toggleBylineFieldCaps(kind),
                  background: caps ? _ffOf(context).selectedFill : _ffOf(context).sunken,
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _ffOf(context).text,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _BylineChipIconButton(
                  tooltip: 'Remove',
                  onTap: () => _removeBylineFieldAtView(viewIndex),
                  background: _ffOf(context).sunken,
                  child: PhosphorIcon(PhosphorIconsRegular.x,
                    size: 11,
                    color: _ffOf(context).textSecondary,
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
          child: PhosphorIcon(PhosphorIconsRegular.dotsSixVertical,
            size: 14,
            color: _ffOf(context).text.withValues(alpha: 0.45),
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
                color: hot ? _ffOf(context).accent : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: hot ? _ffOf(context).accent : Colors.transparent,
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
      color: selected ? _ffOf(context).selectedFill : _ffOf(context).sunken,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? _ffOf(context).accent : _ffOf(context).divider,
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
              color: selected ? _ffOf(context).accent : _ffOf(context).text.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }

  /// Separate pills: the selected choice is filled, the others stay outlined.
  Widget _optionSegmentedControl({
    required List<_SegOption> options,
  }) {
    final t = _ffOf(context);
    final outline = FfTokens.panelOutline.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7.5),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Container(width: 0.5, height: 28, color: outline),
              Expanded(
                child: Material(
                  color: options[i].selected ? t.sunken : Colors.transparent,
                  child: InkWell(
                    onTap: _coreStyleLocked ? null : options[i].onTap,
                    child: Container(
                      height: 28,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        options[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.0,
                          fontWeight: FontWeight.w500,
                          color: options[i].selected
                              ? t.text
                              : t.text.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamOrderSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'Before',
          selected: _template.captionTeamOrder == CaptionTeamOrder.teamBefore,
          onTap: () => setState(() {
            _template = _template.copyWith(
                captionTeamOrder: CaptionTeamOrder.teamBefore);
          }),
        ),
        _SegOption(
          label: 'After',
          selected: _template.captionTeamOrder == CaptionTeamOrder.teamAfter,
          onTap: () => setState(() {
            _template = _template.copyWith(
                captionTeamOrder: CaptionTeamOrder.teamAfter);
          }),
        ),
      ],
    );
  }

  Widget _englishSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'American',
          selected: _template.americanEnglish,
          onTap: () => setState(() {
            _template = _template.copyWith(americanEnglish: true);
          }),
        ),
        _SegOption(
          label: 'International',
          selected: !_template.americanEnglish,
          onTap: () => setState(() {
            _template = _template.copyWith(americanEnglish: false);
          }),
        ),
      ],
    );
  }

  Widget _numberFormatSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: '#99',
          selected: _template.numberFormat == NumberFormatStyle.hash,
          onTap: () => setState(() {
            _template =
                _template.copyWith(numberFormat: NumberFormatStyle.hash);
          }),
        ),
        _SegOption(
          label: '(99)',
          selected: _template.numberFormat == NumberFormatStyle.parens,
          onTap: () => setState(() {
            _template =
                _template.copyWith(numberFormat: NumberFormatStyle.parens);
          }),
        ),
      ],
    );
  }

  Widget _positionSegments() {
    final gettyLocked = _selectedWire == WireStyle.getty ||
        _selectedWire == WireStyle.gettyInternational;
    final include = gettyLocked ? false : _template.includePlayerPosition;
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'Include',
          selected: include,
          onTap: () {
            if (gettyLocked || _coreStyleLocked) return;
            setState(() {
              _template = _template.copyWith(includePlayerPosition: true);
            });
          },
        ),
        _SegOption(
          label: 'Omit',
          selected: !include,
          onTap: () {
            if (gettyLocked || _coreStyleLocked) return;
            setState(() {
              _template = _template.copyWith(includePlayerPosition: false);
            });
          },
        ),
      ],
    );
  }

  Widget _diacriticsSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'Keep',
          selected: !_template.removeDiacritics,
          onTap: () => setState(() {
            _template = _template.copyWith(removeDiacritics: false);
          }),
        ),
        _SegOption(
          label: 'Remove',
          selected: _template.removeDiacritics,
          onTap: () => setState(() {
            _template = _template.copyWith(removeDiacritics: true);
          }),
        ),
      ],
    );
  }

  Widget _timingPhraseSegments() {
    final include = _template.includeTimingPhrase;
    return Tooltip(
      message: include
          ? 'Include inning / period / quarter / half in the caption'
          : 'Omit the time-of-game clause from the caption',
      waitDuration: const Duration(milliseconds: 400),
      child: _optionSegmentedControl(
        options: [
          _SegOption(
            label: 'Show',
            selected: include,
            onTap: () {
              if (_coreStyleLocked) return;
              setState(() {
                _template = _template.copyWith(includeTimingPhrase: true);
              });
            },
          ),
          _SegOption(
            label: 'Hide',
            selected: !include,
            onTap: () {
              if (_coreStyleLocked) return;
              setState(() {
                _template = _template.copyWith(includeTimingPhrase: false);
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setShowKeywordsField(bool show) async {
    if (_coreStyleLocked) return;
    setState(() => _template = _template.copyWith(showKeywordsField: show));
  }

  Future<void> _setShowPersonalityField(bool show) async {
    if (_coreStyleLocked) return;
    setState(() => _template = _template.copyWith(showPersonalityField: show));
  }

  Widget _layoutOptionalFieldRow({
    required String label,
    required bool value,
    required Future<void> Function(bool) onSave,
  }) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _layoutOptionTextStyle,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          height: 22,
          child: FittedBox(
            child: Switch.adaptive(
              value: value,
              activeTrackColor: _ffOf(context).accent,
              inactiveTrackColor: _ffOf(context).hover,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              onChanged: _coreStyleLocked ? null : (next) => onSave(next),
            ),
          ),
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
      sampleGameInfo: _previewGameInfo,
      adaptsUsIntl: _template.wireStyle == WireStyle.getty ||
          _template.wireStyle == WireStyle.gettyInternational,
    );
  }

  Widget _dateLineEditor() {
    return DateFormulaEditor(
      formula: _dateFormula,
      onChanged: _commitDateFormula,
      sampleDate: _previewGameInfo.gameDate,
    );
  }

  TextStyle get _captionFullPreviewStyle => TextStyle(
        fontSize: 13,
        height: 1.45,
        color: _t.text,
        fontWeight: FontWeight.w500,
      );

  /// Game identifier is edited via the panel editor, not inline in the preview.
  bool get _singleCustomNarrativeInlineEligible => false;

  void _onLayoutEdgeFocusChanged({required bool prefix, required bool focused}) {
    setState(() {
      if (prefix) {
        _layoutPrefixFocused = focused;
      } else {
        _layoutSuffixFocused = focused;
      }
      if (focused) {
        _focusedGlueSegmentIndex = null;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        if (prefix) {
          _layoutSuffixFocused = false;
        } else {
          _layoutPrefixFocused = false;
        }
      }
    });
  }

  /// Finds the selected structure chip or separator inside [full].
  ({int start, int end})? _highlightRangeInPreview({
    required String full,
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final highlightIndex = _focusedGlueSegmentIndex ?? _activeFormulaIndex;
    final highlightPrefix = _layoutPrefixFocused;
    final highlightSuffix = _layoutSuffixFocused;
    if (full.isEmpty ||
        (highlightIndex == null && !highlightPrefix && !highlightSuffix)) {
      return null;
    }

    final order = _template.segmentOrder;
    final hasGlue = order.any(_isGlueSegment);
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(_template);
    final pieces = <({String text, bool hit})>[];

    void add(String text, bool hit) {
      pieces.add((text: text, hit: hit));
    }

    add(_template.layoutPrefix, highlightPrefix);
    for (var i = 0; i < order.length; i++) {
      final seg = order[i];
      if ((seg == CaptionSegment.customText || seg == CaptionSegment.freeText) &&
          _previewSegmentText(i, sampleCaption, sampleAgency).trim().isEmpty) {
        continue;
      }
      add(
        _previewSegmentText(i, sampleCaption, sampleAgency),
        highlightIndex == i,
      );
      if (!hasGlue && i < order.length - 1 && i < gaps.length) {
        add(gaps[i], false);
      }
    }
    add(_template.layoutSuffix, highlightSuffix);

    var cursor = 0;
    ({int start, int end})? hit;
    for (final piece in pieces) {
      if (piece.text.isEmpty) continue;
      final found = _locatePreviewPiece(full, piece.text, cursor);
      if (found == null) continue;
      if (piece.hit) hit = found;
      cursor = found.end;
    }
    return hit;
  }

  ({int start, int end})? _locatePreviewPiece(
    String full,
    String part,
    int cursor,
  ) {
    if (cursor < 0 || cursor > full.length || part.isEmpty) return null;
    var idx = full.indexOf(part, cursor);
    var length = part.length;
    if (idx < 0) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        var i = cursor;
        final take = part.length;
        while (i < full.length && i - cursor < take && full[i] == ' ') {
          i++;
        }
        if (i == cursor && cursor < full.length && full[cursor] == ' ') {
          i = cursor + 1;
        }
        if (i > cursor) return (start: cursor, end: i);
        return null;
      }
      idx = full.indexOf(trimmed, cursor);
      length = trimmed.length;
    }
    if (idx < 0) return null;
    return (start: idx, end: idx + length);
  }

  String _previewSegmentText(
    int segmentIndex,
    String sampleCaption,
    CreditSampleAgency sampleAgency,
  ) {
    final order = _template.segmentOrder;
    if (segmentIndex < 0 || segmentIndex >= order.length) return '';
    final s = order[segmentIndex];
    switch (s) {
      case CaptionSegment.location:
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, CaptionSegment.location);
        final locOpts = CaptionFormulaRenderer.locationLineOptionsForOccurrence(
            _template, occ);
        final gettyWire = _template.wireStyle == WireStyle.getty ||
            _template.wireStyle == WireStyle.gettyInternational;
        return CaptionFormulaRenderer.formatLocationLine(
          _captionPreviewGame,
          locOpts,
          apStyleCaption: _template.wireStyle == WireStyle.ap ||
              _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: gettyWire,
          locationOccurrenceIndex: occ,
        );
      case CaptionSegment.date:
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, CaptionSegment.date);
        final f = CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
        return CaptionFormulaRenderer.formatTemplateDateLine(
          _previewGameInfo,
          _template,
          uppercaseAll: _template.wireStyle == WireStyle.getty ||
              _template.wireStyle == WireStyle.gettyInternational,
          dateFormulaOverride: f,
        );
      case CaptionSegment.caption:
        return '${_template.captionPrefix}$sampleCaption${_template.captionSuffix}';
      case CaptionSegment.customText:
        return '${_template.gameIdentifierPrefix}'
            '${_template.gameIdentifierText.trim()}'
            '${_template.gameIdentifierSuffix}';
      case CaptionSegment.freeText:
        return CaptionFormulaRenderer.freeTextSnippetFor(_template, segmentIndex);
      case CaptionSegment.venue:
        final venue = _previewGameInfo.venue.trim().isEmpty
            ? 'Venue'
            : _previewGameInfo.venue.trim();
        return '${_template.venuePrefix}$venue${_template.venueSuffix}';
      case CaptionSegment.credit:
        final omitCustomInCredit =
            _template.segmentOrder.contains(CaptionSegment.customText);
        return CaptionFormulaRenderer.formatCreditLine(
          format: _template.creditFormat,
          bylineOptions: _template.bylineOptions,
          photographerName: _previewGameInfo.photographerName,
          agencyName: _previewGameInfo.agencyName,
          iptcMetadata: _previewGameInfo.iptcMetadata,
          sampleAgency: sampleAgency,
          apShortParen: _template.wireStyle == WireStyle.ap ||
              _template.wireStyle == WireStyle.cp,
          customTexts: _template.bylineOptions.customTexts,
          includeCustomInCredit: !omitCustomInCredit,
        );
      case CaptionSegment.separator:
        return _normalizeSep(CaptionFormulaRenderer.separatorSnippetFor(
            _template, segmentIndex));
      case CaptionSegment.punctuation:
        return _normalizeSep(CaptionFormulaRenderer.punctuationSnippetFor(
            _template, segmentIndex));
    }
  }

  Widget _fullCaptionPreviewArea({
    required String fullCaptionPreview,
    required CaptionPreviewNarrativeSplit? narrativeSplit,
    ({int start, int end})? highlight,
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
                                color: _ffOf(context).accent.withValues(alpha: 0.45), width: 1.5),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _ffOf(context).accent.withValues(alpha: 0.35), width: 1.5),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _ffOf(context).accent, width: 2),
                          ),
                          hintText: 'type here…',
                          hintStyle: _captionFullPreviewStyle.copyWith(
                            color: _ffOf(context).text.withValues(alpha: 0.40),
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
    // Plain text so the parent InkWell receives taps (SelectionArea would
    // swallow them). Structure chips below are the edit surface.
    final range = highlight;
    if (range != null &&
        range.start >= 0 &&
        range.end > range.start &&
        range.end <= fullCaptionPreview.length) {
      final base = _captionFullPreviewStyle;
      final mark = base.copyWith(
        backgroundColor: _t.accent.withValues(alpha: 0.45),
        color: _t.text,
      );
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: fullCaptionPreview.substring(0, range.start)),
            TextSpan(
              text: fullCaptionPreview.substring(range.start, range.end),
              style: mark,
            ),
            TextSpan(text: fullCaptionPreview.substring(range.end)),
          ],
        ),
      );
    }
    return Text(
      fullCaptionPreview,
      style: _captionFullPreviewStyle,
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
        _fieldPreviewLine(rendered),
        const SizedBox(height: 8),
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
      ],
    );
  }

  /// Freeform [CaptionSegment.freeText] editor (e.g. Getty NOTE TO USER).
  Widget _freeTextSnippetEditor() {
    final idx = _activeFormulaIndex;
    final suffix = (idx != null &&
            idx >= 0 &&
            idx < _template.segmentOrder.length &&
            _template.segmentOrder[idx] == CaptionSegment.freeText)
        ? CaptionFormulaRenderer.freeTextSuffixFor(_template, idx)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CaptionLayoutBorderedMultilineField(
                controller: _freeTextCtrl,
                minLines: 2,
                maxLines: 8,
                autofocus: true,
                hintText: 'Type custom text to include in the caption…',
              ),
            ),
            _BylineSeparatorInput(
              key: ValueKey('free-text-suffix-$idx'),
              value: suffix,
              onChanged: _setFreeTextSuffix,
            ),
          ],
        ),
      ],
    );
  }

  void _ensureExampleTeams() {
    if (_exampleTeamsLoaded) return;
    _exampleTeamsLoaded = true;
    PreferencesService.getInstance().then((prefs) async {
      final last = await prefs.getStartupLastTeams(sport: _sessionSport);
      if (!mounted) return;
      setState(() {
        _savedExampleHome = last.key;
        _savedExampleAway = last.value;
      });
    });
  }

  Widget _gettyPreviewToggle() {
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return Material(
        color: selected ? _t.sunken : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: _snippetChipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? _t.accent.withValues(alpha: 0.85)
                    : _t.text.withValues(alpha: 0.16),
                width: selected ? 1 : 0.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w500,
                color: selected ? _t.text : _t.text.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('American', _gettyPreviewUnitedStates, () {
          setState(() => _gettyPreviewUnitedStates = true);
        }),
        const SizedBox(width: 4),
        pill('International', !_gettyPreviewUnitedStates, () {
          setState(() => _gettyPreviewUnitedStates = false);
        }),
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
              PhosphorIcon(PhosphorIconsRegular.shuffle, size: 12, color: _ffOf(context).textSecondary),
              const SizedBox(width: 4),
              Text(
                'Shuffle sample',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _ffOf(context).textSecondary,
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
    final menuStyle = TextStyle(fontSize: 12, color: _ffOf(context).text);
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
          value: CaptionSegment.freeText,
          child: Text('Custom text', style: menuStyle),
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
      child: _addFieldButtonChrome(),
    );
  }

  Widget _addFieldButtonChrome() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _ffOf(context).sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FfTokens.panelOutline, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 16,
                color: _ffOf(context).text.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 6),
              Text(
                'Add field',
                style: _ffOf(context).metaStyle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text.withValues(alpha: 0.82),
                      height: 1,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bylineAddFieldButton() {
    final saved = _template.bylineOptions;
    final menuStyle = TextStyle(fontSize: 12, color: _ffOf(context).text);
    bool inUse(BylineFieldKind kind) =>
        saved.fieldOrder.contains(kind) &&
        !saved.disabledKinds.contains(kind);
    void add(BylineFieldKind kind) {
      if (saved.fieldOrder.contains(kind)) {
        _setBylineKindEnabled(kind, true);
      } else {
        _addBylineField(kind);
      }
    }

    const options = <(BylineFieldKind, String)>[
      (BylineFieldKind.name, 'IPTC Creator'),
      (BylineFieldKind.credit, 'IPTC Credit'),
      (BylineFieldKind.copyright, 'IPTC Copyright'),
      (BylineFieldKind.customCreator, 'Custom Creator'),
      (BylineFieldKind.customCredit, 'Custom Credit'),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<BylineFieldKind>(
        tooltip: 'Add a byline field',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 30),
        onSelected: add,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem(
              value: option.$1,
              enabled: !inUse(option.$1),
              child: Text(
                inUse(option.$1)
                    ? '${option.$2} (already in layout)'
                    : option.$2,
                style: menuStyle,
              ),
            ),
        ],
        child: _addFieldButtonChrome(),
      ),
    );
  }

  Widget _adminCaptionToolbar() {
    final t = _ffOf(context);
    final sports = AppDefaultsFirestoreService.catalogSports;
    Widget menuBox({required double width, required Widget child}) {
      return SizedBox(
        width: width,
        height: 34,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FfTokens.panelOutline, width: 0.5),
          ),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          menuBox(
            width: 132,
            child: FfDropdownButton<String>(
              value: sports.contains(_sessionSport) ? _sessionSport : sports.first,
              isExpanded: true,
              menuColor: t.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              style: t.metaStyle.copyWith(color: t.text),
              items: [
                for (final sport in sports)
                  DropdownMenuItem(
                    value: sport,
                    child: Text(SportVerbCategories.displayLabel(sport)),
                  ),
              ],
              onChanged: (value) {
                if (value == null || value == _sessionSport) return;
                widget.onSportChanged?.call(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 148,
            height: 34,
            child: _buildCaptionStyleDropdown(),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message:
                'Layout is shared by every sport on this wire. The game identifier phrase is set per sport — switch sport to edit it.',
            waitDuration: const Duration(milliseconds: 300),
            child: PhosphorIcon(
              PhosphorIconsRegular.info,
              size: 16,
              color: t.text.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _panelTitleStyle => FfTokens.railLabel.copyWith(
        color: _t.text.withValues(alpha: 0.48),
        fontSize: 10,
        letterSpacing: 1.15,
      );

  /// Same label treatment as the verb editor titles (Category, Verb).
  TextStyle get _sectionTitleStyle => appDialogFieldLabelStyleOf(context);

  /// Same as "Show Personality Field" / layout option rows (Player Output choices use this too).
  TextStyle get _layoutOptionTextStyle => _t.microStyle.copyWith(
        fontSize: 11,
        color: _t.text.withValues(alpha: 0.82),
      );

  CaptionSegment? _activePreviewSegment() {
    if (_customTextSnippetEditorOpen) return CaptionSegment.customText;
    if (_freeTextSnippetEditorOpen) return CaptionSegment.freeText;
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
    if (_focusedGlueSegmentIndex != null &&
        _focusedGlueSegmentIndex! >= 0 &&
        _focusedGlueSegmentIndex! < _template.segmentOrder.length) {
      return _template.segmentOrder[_focusedGlueSegmentIndex!];
    }
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

  /// Fixed slate fill for formula preview snippets — same in every state so
  /// chips don't flash selectedFill / faded sunken while editing.
  /// Field chips in the structure row.
  static const Color _snippetFill = FfTokens.nocturneSunken;

  /// Punctuation and separator inputs. Bluer than the chips so they read as
  /// text boxes, not another field chip.
  static const Color _textBoxFill = Color(0xFF1B3344);

  /// Shared height for snippet chips and glue/punctuation text boxes.
  static const double _snippetChipHeight = 32;

  /// Preview chips + player sample share [_snippetFill] with light body text.
  _SegmentTint get _segmentTint => const _SegmentTint(
        bg: _snippetFill,
        fg: Color(0xFFE4EAF2),
      );

  List<Widget> _buildPreviewWidgets({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final active = _activePreviewSegment();
    final activeIndex = _activeFormulaIndex;
    final focusedGap = _focusedGapIndex;
    final dimNonActive = active != null ||
        activeIndex != null ||
        focusedGap != null ||
        _focusedGlueSegmentIndex != null;

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
      apShortParen: _template.wireStyle == WireStyle.ap || _template.wireStyle == WireStyle.cp,
      customTexts: _template.bylineOptions.customTexts,
      includeCustomInCredit: !omitCustomInCredit,
    );

    String valueAt(int segmentIndex, List<CaptionSegment> order) {
      final s = order[segmentIndex];
      switch (s) {
        case CaptionSegment.location:
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, CaptionSegment.location);
          final locOpts =
              CaptionFormulaRenderer.locationLineOptionsForOccurrence(
                  _template, occ);
          final gettyWire = _template.wireStyle == WireStyle.getty ||
              _template.wireStyle == WireStyle.gettyInternational;
          return CaptionFormulaRenderer.formatLocationLine(
            _captionPreviewGame,
            locOpts,
            apStyleCaption: _template.wireStyle == WireStyle.ap ||
                _template.wireStyle == WireStyle.cp,
            forceAutoAdaptUsIntl: gettyWire,
            locationOccurrenceIndex: occ,
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
        case CaptionSegment.freeText:
          return CaptionFormulaRenderer.freeTextSnippetFor(
              _template, segmentIndex);
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
      if (_focusedGlueSegmentIndex != null) {
        return _focusedGlueSegmentIndex == i && _isGlueSegment(seg)
            ? _PreviewSegmentState.active
            : _PreviewSegmentState.dim;
      }
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

    final widgets = <Widget>[];

    // Always show an editable text box at the very start of the layout so any
    // leading punctuation (e.g. a stray dash) is visible and removable.
    widgets.add(
      Tooltip(
        message: 'Text before the first block',
        waitDuration: const Duration(milliseconds: 400),
        child: _GapSeparatorField(
          controller: _layoutPrefixCtrl,
          active: _layoutPrefixFocused,
          onFocusChanged: (focused) =>
              _onLayoutEdgeFocusChanged(prefix: true, focused: focused),
        ),
      ),
    );

    for (var i = 0; i < n; i++) {
      final seg = order[i];
      if (_isGlueSegment(seg)) {
        final controller = _glueSnippetControllers[i];
        if (controller == null) continue;
        final glueActive = _focusedGlueSegmentIndex == i;
        final glueDim = dimNonActive && !glueActive;
        widgets.add(
          Tooltip(
            message: _glueFieldTooltip(i),
            waitDuration: const Duration(milliseconds: 400),
            child: Opacity(
              opacity: glueDim ? 0.45 : 1.0,
              child: _GapSeparatorField(
                controller: controller,
                active: glueActive,
                onFocusChanged: (focused) => _onGlueSnippetFocusChanged(i, focused),
              ),
            ),
          ),
        );
        continue;
      }

      final segState = stateFor(i, seg);
      final rawValue = valueAt(i, order);

      var chipValue = rawValue;
      if ((seg == CaptionSegment.customText ||
              seg == CaptionSegment.freeText) &&
          chipValue.trim().isEmpty) {
        chipValue = '(no text)';
      }

      final inner = _previewSegmentChip(
        seg: seg,
        value: chipValue,
        state: segState,
        tooltipLabel: _segmentDisplayLabel(seg, i),
        titleLeading: _previewSegmentDragHandle(i),
        onSnippetTap: () => _activateFormulaEditor(index: i, segment: seg),
        onRemove: () => _removeSegmentSnippet(i),
      );

      final snippetRow = DragTarget<int>(
        onWillAcceptWithDetails: (d) =>
            d.data != i && !_isGlueSegment(order[d.data]),
        onAcceptWithDetails: (d) => _reorderPreviewSegment(d.data, i),
        builder: (context, candidate, _) {
          final hot = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: hot ? _ffOf(context).accent : Colors.transparent,
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

    // Always show an editable text box at the very end of the layout.
    widgets.add(
      Tooltip(
        message: 'Text after the last block',
        waitDuration: const Duration(milliseconds: 400),
        child: _GapSeparatorField(
          controller: _layoutSuffixCtrl,
          active: _layoutSuffixFocused,
          onFocusChanged: (focused) =>
              _onLayoutEdgeFocusChanged(prefix: false, focused: focused),
        ),
      ),
    );

    return widgets;
  }

  Widget _previewSegmentDragHandle(int segmentIndex) {
    return Draggable<int>(
      data: segmentIndex,
      feedback: Material(
        color: Colors.transparent,
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child:
            PhosphorIcon(PhosphorIconsRegular.dotsSixVertical, size: 10, color: _ffOf(context).textSecondary),
      ),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child:
            PhosphorIcon(PhosphorIconsRegular.dotsSixVertical, size: 10, color: _ffOf(context).text.withValues(alpha: 0.40)),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag to reorder snippets',
          child:
              PhosphorIcon(PhosphorIconsRegular.dotsSixVertical, size: 10, color: _ffOf(context).text.withValues(alpha: 0.45)),
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
    VoidCallback? onRemove,
  }) {
    final tint = _segmentTint;
    final tokens = _ffOf(context);
    // Background stays [_snippetFill] in every state; only text weight / opacity
    // and label colour change when active or dimmed.
    final Color bg = _snippetFill;
    Color fg;
    Color labelFg;
    FontWeight weight;
    switch (state) {
      case _PreviewSegmentState.active:
        fg = tokens.text;
        labelFg = tokens.accent;
        weight = FontWeight.w600;
        break;
      case _PreviewSegmentState.dim:
        fg = tokens.text.withValues(alpha: 0.40);
        labelFg = tokens.text.withValues(alpha: 0.40);
        weight = FontWeight.normal;
        break;
      case _PreviewSegmentState.tinted:
        fg = tint.fg;
        labelFg = tokens.textSecondary;
        weight = FontWeight.normal;
        break;
    }

    Widget chipContent = Container(
      height: _snippetChipHeight,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state == _PreviewSegmentState.active
              ? tokens.accent.withValues(alpha: 0.85)
              : tokens.text.withValues(alpha: 0.16),
          width: state == _PreviewSegmentState.active ? 1 : 0.5,
        ),
      ),
      padding: const EdgeInsets.only(left: 6, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titleLeading != null) ...[
            titleLeading,
            const SizedBox(width: 4),
          ],
          Text(
            tooltipLabel,
            style: TextStyle(
              fontSize: 12,
              height: 1.0,
              fontWeight: weight,
              color: fg,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: PhosphorIcon(
                    PhosphorIconsRegular.x,
                    size: 11,
                    color: labelFg.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    chipContent = Tooltip(
      message: value.trim().isEmpty ? tooltipLabel : '$tooltipLabel · $value',
      waitDuration: const Duration(milliseconds: 400),
      child: chipContent,
    );

    if (onSnippetTap != null) {
      chipContent = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onSnippetTap,
          child: chipContent,
        ),
      );
    }

    // Keep the remove control outside the activate GestureDetector so the
    // close tap is not swallowed by "open editor".
    return chipContent;
  }

  /// Plain text rendered between snippet chips. Kept as a single [Text] widget
  /// (no chip background) so the inter-snippet separator visually belongs to
  /// neither side.
  Widget _previewGapText(String text, _PreviewGapState state) {
    final tokens = _ffOf(context);
    TextStyle style;
    switch (state) {
      case _PreviewGapState.active:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text,
          backgroundColor: _snippetFill,
          fontWeight: FontWeight.w600,
        );
        break;
      case _PreviewGapState.dim:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text.withValues(alpha: 0.40),
        );
        break;
      case _PreviewGapState.normal:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text,
        );
        break;
    }
    return Text(text, style: style);
  }


  /// Compact style picker for the dialog header (fixed height; no DropdownFlutter).
  Widget _buildCaptionStyleDropdown() {
    final t = _ffOf(context);
    final tokens = _captionStyleDropdownTokens();
    final current = _captionStyleDropdownInitialToken();
    final locked = _tokenIsLockedCore(current);
    final label = _captionStyleMenuLabel(current);
    final firstCustom = CaptionStyleCatalog.firstCustomTokenIndex(tokens);

    return PopupMenuButton<String>(
      tooltip: 'Caption style',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      color: t.surface,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280, maxHeight: 380),
      onSelected: (token) {
        _rememberCurrentWireDraft();
        _applyCaptionStyleMenuToken(token);
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];
        for (var i = 0; i < tokens.length; i++) {
          final token = tokens[i];
          if (firstCustom >= 0 && i == firstCustom) {
            items.add(const PopupMenuDivider(height: 8));
          }
          final selected = token == current;
          final lockedTok = _tokenIsLockedCore(token);
          final fav = _favoriteCaptionStyleToken == token;
          items.add(
            PopupMenuItem<String>(
              value: token,
              height: 34,
              child: Row(
                children: [
                  if (lockedTok)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PhosphorIcon(PhosphorIconsRegular.lock,
                          size: 13, color: t.textSecondary),
                    )
                  else if (token.startsWith('saved:'))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PhosphorIcon(PhosphorIconsRegular.bookmarkSimple,
                          size: 14, color: t.textSecondary),
                    ),
                  Expanded(
                    child: Text(
                      _captionStyleMenuLabel(token),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: lockedTok ? t.textSecondary : t.text,
                      ),
                    ),
                  ),
                  Icon(
                    fav ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                    size: 15,
                    color: fav
                        ? const Color(0xFFE6B84A)
                        : t.text.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          );
        }
        return items;
      },
      child: Container(
        height: widget.embedded ? 34 : 26,
        width: double.infinity,
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FfTokens.panelOutline, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (locked) ...[
                PhosphorIcon(PhosphorIconsRegular.lock,
                  size: 12,
                  color: t.text.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.metaStyle.copyWith(
                    color: locked ? t.textSecondary : t.text,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: t.text.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptEditStructureSnippets() {
    final target = _structureSectionKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
    setState(() => _structureHintFlash = true);
    _structureHintFlashTimer?.cancel();
    _structureHintFlashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _structureHintFlash = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit the snippets in Structure below.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _extraFieldToggle({
    required String label,
    required String explanation,
    required bool value,
    required Future<void> Function(bool) onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _layoutOptionalFieldRow(
          label: label,
          value: value,
          onSave: onSave,
        ),
        const SizedBox(height: 4),
        Text(
          explanation,
          style: _t.microStyle.copyWith(
            color: _t.text.withValues(alpha: 0.45),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldsShownSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _editorPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DISPLAY EXTRA FIELDS', style: _panelTitleStyle),
          const SizedBox(height: 10),
          _lockableEditorSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _extraFieldToggle(
                  label: 'IPTC Personality',
                  explanation:
                      'Shows a Personality field beside the caption for who is in the photo. It is saved to the image’s IPTC personality metadata. Typically used in Getty.',
                  value: _template.showPersonalityField,
                  onSave: _setShowPersonalityField,
                ),
                const SizedBox(height: 12),
                _extraFieldToggle(
                  label: 'IPTC Keywords',
                  explanation:
                      'Shows a Keywords field beside the caption. It is saved to IPTC keywords, and can be filled from the players and verb you pick.',
                  value: _template.showKeywordsField,
                  onSave: _setShowKeywordsField,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerOptionCell(String label, Widget control) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _layoutOptionTextStyle),
        const SizedBox(height: 6),
        control,
      ],
    );
  }

  Widget _buildPlayerOutputSection(String playerPreviewText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PLAYER OUTPUT', style: _panelTitleStyle),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _snippetFill,
            border: Border.all(
              color: FfTokens.panelOutline.withValues(alpha: 0.45),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            playerPreviewText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: _ffOf(context).text,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _playerOptionCell('Team order', _teamOrderSegments())),
            const SizedBox(width: 16),
            Expanded(child: _playerOptionCell('English', _englishSegments())),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _playerOptionCell('Number', _numberFormatSegments())),
            const SizedBox(width: 16),
            Expanded(child: _playerOptionCell('Position', _positionSegments())),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _playerOptionCell('Time of game', _timingPhraseSegments()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _playerOptionCell(
                'Diacritics',
                Tooltip(
                  message:
                      'Keep accents as on the roster, or strip them (e.g. José → Jose).',
                  child: _diacriticsSegments(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  BoxDecoration _editorPanelDecoration() {
    return BoxDecoration(
      color: _ffOf(context).surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: FfTokens.panelOutline.withValues(alpha: 0.45),
        width: 0.5,
      ),
    );
  }

  Widget _buildInlineFieldEditor() {
    return Container(
      decoration: BoxDecoration(
        color: _ffOf(context).surface,
        border: Border.all(color: _ffOf(context).divider),
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _ffOf(context).sunken,
              border: Border(
                bottom: BorderSide(color: _ffOf(context).divider),
              ),
            ),
            child: Row(
              children: [
                _activeEditIndicator(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_captionPreviewSelected)
                  _captionSegmentEditor()
                else if (_customTextSnippetEditorOpen)
                  _customTextSnippetEditor()
                else if (_freeTextSnippetEditorOpen)
                  _freeTextSnippetEditor()
                else if (_venuePreviewSelected)
                  _venueEditor()
                else if (_bylinePreviewSelected)
                  _bylineEditor(),
                if (_dateEditorOpen) _dateLineEditor(),
                if (_locationEditorOpen) _locationOptionsEditor(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedGreyButton(
                    label: 'Done',
                    isPrimary: true,
                    fontSize: 12,
                    onPressed: _closeAllInlineEdits,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutosave();
    _ensureExampleTeams();
    final previewPlayers = CaptionSessionContext.previewPlayers;
    final previewActions = CaptionSessionContext.previewActions;
    final hasLivePreviewData =
        previewPlayers.isNotEmpty && previewActions.isNotEmpty;
    final fallbackPlayers = hasLivePreviewData
        ? previewPlayers
        : _examplePlayersFromTeams();
    // Prefer live roster+verb samples; fall back to last rendered caption body.
    final sessionBody = CaptionSessionContext.captionBody;
    final sampleCaption = hasLivePreviewData
        ? CaptionFormulaRenderer.randomSinglePlayerCaption(
            _template,
            seed: _captionSampleSeed,
            previewPlayers: previewPlayers,
            previewActions: previewActions,
            sport: _sessionSport,
          )
        : (fallbackPlayers != null
            ? CaptionFormulaRenderer.randomSinglePlayerCaption(
                _template,
                seed: _captionSampleSeed,
                previewPlayers: fallbackPlayers,
                sport: _sessionSport,
              )
            : (sessionBody != null && sessionBody.isNotEmpty
                ? sessionBody
                : CaptionFormulaRenderer.randomSinglePlayerCaption(
                    _template,
                    seed: _captionSampleSeed,
                    sport: _sessionSport,
                  )));
    final playerPreviewText = CaptionFormulaRenderer.randomSinglePlayerPreview(
      _template,
      seed: _captionSampleSeed,
      previewPlayers: fallbackPlayers,
    );
    final previewAgency = _sampleAgencyForWire(_selectedWire);
    final fullCaptionPreview = CaptionFormulaRenderer.render(
      template: _template,
      game: _captionPreviewGame,
      sampleAgency: previewAgency,
      captionOverride: sampleCaption,
      sport: _sessionSport,
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
    final dialogWidth = (mq.width - 32).clamp(320.0, 960.0);

    final shell = SizedBox(
        width: widget.embedded ? double.infinity : dialogWidth,
        height: widget.embedded ? double.infinity : dialogHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _t.bg,
            borderRadius: BorderRadius.circular(
              widget.embedded ? 0 : FfTokens.radiusWindow,
            ),
            border: widget.embedded
                ? null
                : Border.all(color: _t.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              widget.embedded ? 0 : FfTokens.radiusWindow,
            ),
            child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.embedded)
                    Container(
                      height: 40,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _t.surface,
                        border: Border(
                          bottom: BorderSide(color: _t.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'CAPTION LAYOUT',
                            style: FfTokens.railLabel.copyWith(
                              color: _t.text.withValues(alpha: 0.70),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 132,
                            height: 26,
                            child: _buildCaptionStyleDropdown(),
                          ),
                          const Spacer(),
                          if (!widget.adminMode) ...[
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _duplicateCaptionStyle,
                              child: Text(
                                'Duplicate',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _t.accent,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _selectedSavedStyleId == null
                                  ? null
                                  : _deleteSelectedCaptionStyle,
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedSavedStyleId == null
                                      ? _t.text.withValues(alpha: 0.40)
                                      : Colors.red.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: PhosphorIcon(PhosphorIconsRegular.x,
                                  size: 18,
                                  color: _t.textSecondary,
                                ),
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
                                  color: _t.accent,
                                ),
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                      if (widget.embedded && widget.adminMode)
                                        _adminCaptionToolbar(),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            'CAPTION PREVIEW',
                                            style: _panelTitleStyle,
                                          ),
                                          const Spacer(),
                                          if (_isGettyWire) ...[
                                            _gettyPreviewToggle(),
                                            const SizedBox(width: 8),
                                          ],
                                          _shuffleCaptionButton(),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _promptEditStructureSnippets,
                                          borderRadius: BorderRadius.circular(6),
                                          child: Ink(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: _ffOf(context).sunken,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: FfTokens.panelOutline,
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 10,
                                              ),
                                              child: _fullCaptionPreviewArea(
                                                fullCaptionPreview:
                                                    fullCaptionPreview,
                                                narrativeSplit: narrativeSplit,
                                                highlight: _highlightRangeInPreview(
                                                  full: fullCaptionPreview,
                                                  sampleCaption: sampleCaption,
                                                  sampleAgency: previewAgency,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: Row(
                                        key: _structureSectionKey,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 7,
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 220),
                                              padding: _structureHintFlash
                                                  ? const EdgeInsets.all(6)
                                                  : EdgeInsets.zero,
                                              decoration: BoxDecoration(
                                                color: _structureHintFlash
                                                    ? _t.accent
                                                        .withValues(alpha: 0.12)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: _structureHintFlash
                                                      ? _t.accent.withValues(
                                                          alpha: 0.55)
                                                      : Colors.transparent,
                                                ),
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                                                decoration: _editorPanelDecoration(),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'STRUCTURE',
                                                          style: _panelTitleStyle,
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          '[space]',
                                                          style: _t.microStyle.copyWith(
                                                            color: _t.text.withValues(alpha: 0.38),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Expanded(
                                                      child: SingleChildScrollView(
                                                        child: _lockableEditorSurface(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Wrap(
                                                                spacing: 6,
                                                                runSpacing: 8,
                                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                                children: previewWidgets,
                                                              ),
                                                              const SizedBox(height: 8),
                                                              Align(
                                                                alignment: Alignment.centerLeft,
                                                                child: _addSnippetMenuButton(),
                                                              ),
                                                              if (_locationEditorOpen ||
                                                                  _dateEditorOpen ||
                                                                  _captionPreviewSelected ||
                                                                  _venuePreviewSelected ||
                                                                  _bylinePreviewSelected ||
                                                                  _customTextSnippetEditorOpen ||
                                                                  _freeTextSnippetEditorOpen) ...[
                                                                const SizedBox(height: 10),
                                                                _buildInlineFieldEditor(),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Divider(
                                                      height: 16,
                                                      color: _t.text.withValues(alpha: 0.08),
                                                    ),
                                                    Text(
                                                      'Drag fields to reorder  ·  click a field to edit  ·  click a gap to change its separator',
                                                      style: _t.microStyle.copyWith(
                                                        color: _t.text.withValues(alpha: 0.38),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 4,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                                    decoration: _editorPanelDecoration(),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Expanded(
                                                          child: _lockableEditorSurface(
                                                            child: _buildPlayerOutputSection(playerPreviewText),
                                                          ),
                                                        ),
                                                        if (!widget.adminMode)
                                                          Align(
                                                            alignment: Alignment.centerRight,
                                                            child: Builder(
                                                              builder: (_) {
                                                                final mode = _currentRenameMode();
                                                                if (mode != _RenamePromptMode.libraryEntry) {
                                                                  return const SizedBox.shrink();
                                                                }
                                                                return TextButton(
                                                                  style: TextButton.styleFrom(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal: 6,
                                                                      vertical: 2,
                                                                    ),
                                                                    minimumSize: Size.zero,
                                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                  ),
                                                                  onPressed: _openRenameCaptionStylePrompt,
                                                                  child: Text(
                                                                    'Rename',
                                                                    style: TextStyle(
                                                                      fontSize: 10,
                                                                      fontWeight: FontWeight.w600,
                                                                      color: _ffOf(context).accent,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                _buildFieldsShownSection(),
                                              ],
                                            ),
                                          ),
                                        ],
                                        ),
                                      ),
                                    ],
                                  ),
                        );
                      },
                    ),
                  ),
                  if (!widget.embedded)
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _t.surface,
                        border: Border(
                          top: BorderSide(color: _t.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Changes apply as you make them',
                            style: _t.microStyle.copyWith(
                              color: _t.text.withValues(alpha: 0.45),
                            ),
                          ),
                          const Spacer(),
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 10,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 4),
                          ElevatedGreyButton(
                            label: 'Save as template',
                            fontSize: 10,
                            onPressed: _saveAsTemplate,
                          ),
                          const SizedBox(width: 4),
                          ElevatedGreyButton(
                            label: 'Done',
                            fontSize: 10,
                            isPrimary: true,
                            onPressed: _done,
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

    final themed = AppDialogFfStyle(enabled: true, child: shell);
    if (widget.embedded) return themed;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: themed,
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
  const _GapSeparatorField({
    required this.controller,
    this.onFocusChanged,
    this.active = false,
  });

  final TextEditingController controller;
  final ValueChanged<bool>? onFocusChanged;
  final bool active;

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
    widget.onFocusChanged?.call(focused);
    // Normalize on blur so pre-existing or hand-typed bad spacing is fixed.
    if (_wasFocused && !focused) {
      final raw = widget.controller.text;
      final normalized = CaptionLayoutBuilderDialogState._normalizeSep(raw);
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
    final highlighted = focused || widget.active;
    final raw = widget.controller.text;
    final idleLabel = raw.isEmpty
        ? ''
        : raw.trim().isEmpty
            ? '[space]'
            : raw;
    final width = idleLabel == '[space]' ? 72.0 : 36.0;
    final tokens = _ffOf(context);
    return Container(
      width: width,
      height: CaptionLayoutBuilderDialogState._snippetChipHeight,
      decoration: BoxDecoration(
        color: CaptionLayoutBuilderDialogState._textBoxFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? tokens.accent
              : tokens.text.withValues(alpha: 0.16),
          width: highlighted ? 1.5 : 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: focused
                  ? tokens.text.withValues(alpha: 0.88)
                  : Colors.transparent,
              height: 1.1,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 2),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          if (!focused && idleLabel.isNotEmpty)
            IgnorePointer(
              child: Text(
                idleLabel,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.0,
                  color: tokens.text.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
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
    this.hintText,
  });

  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final String? hintText;

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
        color: _ffOf(context).sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: on ? _ffOf(context).accent : _ffOf(context).divider,
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
          color: _ffOf(context).text.withValues(alpha: 0.88),
          height: 1.35,
        ),
        cursorColor: _ffOf(context).accent,
        cursorWidth: 1.2,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: _ffOf(context).text.withValues(alpha: 0.40),
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// One segment in [_CaptionLayoutBuilderDialogState._optionSegmentedControl].
class _SegOption {
  const _SegOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
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
          side: BorderSide(color: _ffOf(context).divider),
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
      color: style?.color,
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
    final borderColor = _focused
        ? _ffOf(context).accent
        : _ffOf(context).text.withValues(alpha: 0.16);
    final borderWidth = _focused ? 1.5 : 0.5;
    final idle = _idleLabel(_ctrl.text);
    final style = TextStyle(
      fontSize: 13,
      color: _focused ? _ffOf(context).text : Colors.transparent,
      height: 1.1,
    );
    final idleStyle = TextStyle(
      fontSize: 11,
      height: 1,
      color: _ffOf(context).text.withValues(alpha: 0.55),
    );
    final measureText = _focused
        ? (_ctrl.text.isEmpty ? ' ' : _ctrl.text.replaceAll(' ', '⎵'))
        : (idle.isEmpty ? ' ' : idle);
    final fieldWidth = _fieldWidthFor(
      measureText,
      _focused ? style : idleStyle,
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
            color: CaptionLayoutBuilderDialogState._textBoxFill,
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
                style: style,
                textAlign: TextAlign.center,
                cursorWidth: 1.2,
                cursorColor: _ffOf(context).accent,
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
                  child: Text(idle, style: idleStyle),
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

  static double _fieldWidthFor(String text, TextStyle style) {
    final visible = text.isEmpty ? ' ' : text;
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
    return Tooltip(
      message: label,
      child: SizedBox(
        width: width,
        height: 32,
        child: _GapSeparatorField(controller: controller),
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
            color: _ffOf(context).textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 180,
          height: 24,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              filled: true,
              fillColor: _ffOf(context).sunken,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: _ffOf(context).divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: _ffOf(context).text.withValues(alpha: 0.45)),
              ),
            ),
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
        color: _ffOf(context).sunken,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _ffOf(context).divider),
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
                PhosphorIcon(PhosphorIconsRegular.plus, size: 11, color: _ffOf(context).textSecondary),
                const SizedBox(width: 3),
                Text(
                  'Custom text',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _ffOf(context).text.withValues(alpha: 0.88),
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
