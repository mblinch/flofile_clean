import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_style_catalog.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/game_info.dart';
import '../../../caption_style/team_home_place.dart';
import '../../../config/tank01_config.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_manager.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/current_user_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/jersey_ocr_channel.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/preferences_service.dart';
import '../../../services/verb_admin_choice.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
import '../../../services/camera_serial_service.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/camera_serial_dialog.dart';
import '../../../widgets/ff_menu.dart';
import '../../../widgets/ftp_settings_panel.dart';
import '../../../widgets/file_rename_dialog.dart';
import '../../../widgets/caption_layout_builder_dialog.dart';
import '../data/team_abbrev.dart';
import 'caption_v2_iptc_dialog.dart';
import 'iptc_template_editor.dart';
import 'roster_import_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// New Session IPTC source — maps onto apply-mode + fill-gaps + elsewhere prefs.
enum _IptcSourceMode { apply, fill, files }

/// Result handed from the V2 startup screen into the caption session.
class CaptionV2StartupResult {
  const CaptionV2StartupResult({
    required this.sport,
    required this.folderPath,
    required this.homeTeam,
    required this.awayTeam,
    this.homeRoster,
    this.awayRoster,
    this.singleTeamMode = false,
    this.homeWearsDark,
  });

  final String sport;
  final String folderPath;
  final String homeTeam;
  final String awayTeam;
  final List<Player>? homeRoster;
  final List<Player>? awayRoster;

  /// When true, the session has one roster only ([homeTeam]); [awayTeam] is empty.
  final bool singleTeamMode;

  /// Which bench wears the dark jersey tonight (OCR home/away tie-break).
  /// Null → the controller's sport default.
  final bool? homeWearsDark;
}

/// Sport default for "home wears dark" — hockey yes, basketball/baseball no.
bool? defaultHomeWearsDark(String? sport) {
  switch ((sport ?? '').trim().toLowerCase()) {
    case 'hockey':
      return true;
    case 'basketball':
    case 'wnba':
    case 'baseball':
      return false;
    default:
      return null;
  }
}

/// FloFile V2 initial screen — sport, folder, teams via API, then Go Time.
class CaptionV2StartupScreen extends StatefulWidget {
  const CaptionV2StartupScreen({
    super.key,
    required this.onComplete,
  });

  final ValueChanged<CaptionV2StartupResult> onComplete;

  @override
  State<CaptionV2StartupScreen> createState() => _CaptionV2StartupScreenState();
}

class _CaptionV2StartupScreenState extends State<CaptionV2StartupScreen> {
  final _api = ApiManager();
  final _rootFocus = FocusNode();
  final _awayFocus = FocusNode();
  final _homeFocus = FocusNode();
  final _captionBuilderKey = GlobalKey<CaptionLayoutBuilderDialogState>();
  Future<void> Function()? _flushCaptionBuilder;
  bool _savingCaptionDefault = false;
  PreferencesService? _prefs;

  String? _sport;
  int _sportSelectGen = 0;
  String? _folderPath;
  int _imageCount = 0;
  /// Caption preview date: EXIF from folder photos, else today.
  DateTime _previewPhotoDate = DateTime.now();
  /// True when [_previewPhotoDate] came from a folder photo; false when today.
  bool _previewDateFromFolder = false;
  String? _homeTeam;
  String? _awayTeam;
  List<Player>? _homeRoster;
  List<Player>? _awayRoster;
  /// Real roster names for the caption style preview / shuffle.
  List<CaptionPreviewPlayer> _captionPreviewPlayers = const [];
  int _captionPreviewRosterGen = 0;
  int _captionPreviewSeed =
      DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  /// Home venue from the league API when available.
  String? _previewHomeVenue;

  List<String> _teams = const [];
  bool _loadingTeams = false;
  bool _offline = false;
  bool _pickingFolder = false;
  bool _folderDragOver = false;
  bool _going = false;
  bool _usingCustomRosters = false;
  String? _error;

  String? _favoriteHome;
  String? _favoriteAway;
  /// All favorited team display names for the current sport (home, away, plain).
  Set<String> _favoriteTeamNamesRaw = {};
  bool _useOfficialLeagueApis = false;
  IptcApplyMode _iptcMode = IptcApplyMode.none;
  String _iptcStatus = 'Off';
  /// When true, FloFile will not write IPTC and will not block Go Time on
  /// missing caption/filing fields (handled in Photo Mechanic / elsewhere).
  bool _iptcAppliedElsewhere = false;
  /// When writing IPTC on ingest, only fill empty file fields (keep existing).
  bool _iptcFillGapsOnly = false;
  List<String> _missingCaptionIptc = const [];
  List<String> _missingFilingIptc = const [];
  bool _scanningIptc = false;
  int _iptcScanGen = 0;
  /// Folder scan: files that already have City + Date (for "Already in files").
  int _iptcScanWithCityDate = 0;
  int _iptcScanTotal = 0;
  /// IPTC values read from folder photos (inline menu / Already in files).
  Map<String, String> _iptcValuesFromFiles = const {};
  /// IPTC template values shown/edited for Apply / Fill missing.
  Map<String, String> _iptcValuesFromTemplate = const {};
  /// Panel keys present on folder photos (marks “Found in files”).
  Set<String> _iptcKeysFoundInFiles = const {};
  int _iptcInlineRevision = 0;
  /// When true, folder auto-select will not override the user's IPTC source pick.
  bool _iptcSourceManual = false;

  /// Step 1 = wire; Step 2 = setup (folder/IPTC/league/teams);
  /// Step 3 = Caption layout + Session options.
  int _setupStep = 1;
  /// Which setup field to focus when returning from the summary strip.
  String? _setupFocusTarget;

  /// Latest folder + template IPTC panel values (for caption / structure preview).
  Map<String, String> _iptcPanelForPreview = const {};

  bool _ftpModeEnabled = true;
  bool _fileRenamingEnabled = true;
  String _fileRenameTemplate = '';
  String? _ftpProfileName;
  List<String> _ftpProfileNames = const [];
  /// When true, the caption Firebar is hidden. Same pref as the session menu.
  bool _hideFirebar = false;
  /// On-device jersey/name OCR + folder pre-scan (macOS). Same pref as the
  /// session header toggle.
  bool _jerseyOcrEnabled = false;
  bool _serialBylinesEnabled = false;
  int? _openMenuId;

  CaptionStyleCatalog? _styleCatalog;
  CaptionTemplate? _captionTemplate;
  String? _selectedStyleToken;
  bool _gettyNoteIsNbae = false;
  bool _loadingStyles = true;

  /// IPTC pad already opened for this wire on the Caption step (avoid loops).
  String? _iptcOpenedForStyleToken;

  static const _sports = <String>[
    'baseball',
    'hockey',
    'basketball',
    'wnba',
    'soccer',
  ];

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.tif',
    '.tiff',
    '.png',
  };

  /// Shared stage size for wire / setup / caption steps.
  static const double _stageWidth = 1270;
  static const double _stageHeight = 670;

  bool get _sportChosen => _sport != null && _sport!.isNotEmpty;
  bool get _folderChosen => _folderPath != null && _folderPath!.isNotEmpty;

  /// Who wears dark tonight. Defaults by sport; the user can flip it.
  bool? _homeWearsDark;

  bool get _homeFilled => _homeTeam != null && _homeTeam!.isNotEmpty;
  bool get _awayFilled => _awayTeam != null && _awayTeam!.isNotEmpty;

  /// Exactly one side filled → single-team session.
  bool get _inferredSingleTeam =>
      (_homeFilled && !_awayFilled) || (!_homeFilled && _awayFilled);

  bool get _bothTeamsChosen =>
      _homeFilled && _awayFilled && _homeTeam != _awayTeam;

  /// Go Time (step 3) require folder + sport + both teams.
  bool get _canGo =>
      _sportChosen && _folderChosen && _bothTeamsChosen && !_going;

  /// Setup panel Continue (step 2 → 3).
  bool get _canContinue =>
      _folderChosen && _sportChosen && _bothTeamsChosen && !_going;

  bool get _wireChosen {
    final token = _selectedStyleToken;
    if (token == null || token.isEmpty) return false;
    return CaptionStyleCatalog.isCoreWireToken(token) ||
        CaptionStyleCatalog.isCustomMenuToken(token);
  }

  /// Wire step Continue (step 1 → 2).
  bool get _canContinueFromWire => _wireChosen && !_loadingStyles;

  bool get _writeIptc => _iptcMode != IptcApplyMode.none;

  /// Visual IPTC source for the 3-way control.
  _IptcSourceMode get _iptcSource {
    if (_iptcAppliedElsewhere) return _IptcSourceMode.files;
    if (_writeIptc && _iptcFillGapsOnly) return _IptcSourceMode.fill;
    return _IptcSourceMode.apply;
  }

  bool get _tank01Supported => _sport != null && tank01SupportsSport(_sport!);

  Set<String> get _favoriteTeamNames {
    final out = <String>{..._favoriteTeamNamesRaw};
    if (_favoriteHome != null) out.add(_favoriteHome!);
    if (_favoriteAway != null) out.add(_favoriteAway!);
    return out;
  }

  /// Map a saved favorite onto a name from the live team list.
  String? _resolveFavoriteToTeam(String favorite, List<String> names) {
    final trimmed = favorite.trim();
    if (trimmed.isEmpty) return null;
    if (names.contains(trimmed)) return trimmed;
    final lower = trimmed.toLowerCase();
    for (final n in names) {
      if (n.toLowerCase() == lower) return n;
    }
    for (final n in names) {
      final nl = n.toLowerCase();
      if (lower.endsWith(nl) || nl.endsWith(lower) || lower.contains(nl) || nl.contains(lower)) {
        return n;
      }
    }
    return null;
  }

  String get _apiLabel {
    if (!_sportChosen) return '';
    // Official league APIs are admin-only (also hides under User view preview).
    final official = AdminService.isCurrentUserAdminSync() &&
        _useOfficialLeagueApis &&
        _tank01Supported;
    final tank01Fb = _tank01Supported && !official;
    switch (_sport) {
      case 'baseball':
        return tank01Fb ? 'Tank01 Firebase (MLB)' : 'MLB Stats API';
      case 'hockey':
        return tank01Fb ? 'Tank01 Firebase (NHL)' : 'NHL API';
      case 'basketball':
        return tank01Fb ? 'Tank01 Firebase (NBA)' : 'ESPN NBA';
      case 'wnba':
        return tank01Fb ? 'Tank01 Firebase (WNBA)' : 'ESPN WNBA';
      case 'soccer':
        return 'ESPN MLS';
      default:
        return _api.currentApi;
    }
  }

  String get _goHint {
    if (_setupStep == 1) {
      if (_canContinueFromWire) return 'Press Enter to continue';
      return 'Choose a wire to continue';
    }
    if (_setupStep == 2) {
      if (_canContinue) return 'Press Enter to continue';
      if (!_folderChosen) return 'Choose an images folder';
      if (!_sportChosen) return 'Pick a league to continue';
      if (!_awayFilled || !_homeFilled) return 'Pick both teams to continue';
      if (_homeTeam == _awayTeam) return 'Home and away must be different';
      return 'Complete setup to continue';
    }
    if (_canGo) return 'Ready';
    // One step at a time: folder → league → teams.
    if (!_folderChosen) return 'Choose an images folder to start';
    if (!_sportChosen) return 'Choose a league to start';
    if (!_awayFilled && !_homeFilled) return 'Choose away and home teams to start';
    if (!_awayFilled) return 'Choose an away team to start';
    if (!_homeFilled) return 'Choose a home team to start';
    if (_homeTeam == _awayTeam) return 'Home and away must be different';
    return 'Complete setup to start.';
  }

  void _swapTeams() {
    setState(() {
      final away = _awayTeam;
      final home = _homeTeam;
      final awayRoster = _awayRoster;
      final homeRoster = _homeRoster;
      _awayTeam = home;
      _homeTeam = away;
      _awayRoster = homeRoster;
      _homeRoster = awayRoster;
      final favAway = _favoriteAway;
      _favoriteAway = _favoriteHome;
      _favoriteHome = favAway;
      _captionPreviewPlayers = const [];
    });
    unawaited(_refreshCaptionPreviewPlayers());
  }

  IconData _sportIcon(String? sport) {
    switch ((sport ?? '').toLowerCase()) {
      case 'hockey':
        return PhosphorIconsRegular.hockey;
      case 'basketball':
      case 'wnba':
        return PhosphorIconsRegular.basketball;
      case 'soccer':
        return PhosphorIconsRegular.soccerBall;
      case 'baseball':
        return PhosphorIconsRegular.baseball;
      case 'football':
        return PhosphorIconsRegular.football;
      default:
        return PhosphorIconsRegular.circlesThree;
    }
  }

  String get _filingWireLabel {
    final wire = _captionTemplate?.wireStyle ?? WireStyle.getty;
    final labelWire = wire == WireStyle.gettyInternational ||
            wire == WireStyle.custom
        ? WireStyle.getty
        : wire;
    return WireIptcSpecs.factoryWireLabel(labelWire);
  }

  bool get _hasIptcFieldWarnings =>
      !_iptcAppliedElsewhere &&
      (_missingCaptionIptc.isNotEmpty || _missingFilingIptc.isNotEmpty);

  /// Caption structure fields are filled (does not require wire filing fields).
  /// [ _iptcAppliedElsewhere ] also counts as ready so Go Time is not blocked.
  bool get _captionIptcReady =>
      _iptcAppliedElsewhere ||
      (_folderChosen && !_scanningIptc && _missingCaptionIptc.isEmpty);

  /// Caption + wire filing fields are filled (not used when applied elsewhere).
  bool get _iptcComplete =>
      !_iptcAppliedElsewhere &&
      _folderChosen &&
      !_scanningIptc &&
      _missingCaptionIptc.isEmpty &&
      _missingFilingIptc.isEmpty;

  /// Filing gaps stay muted grey; caption gaps stay red.
  static const Color _filingWarnColor = FfTokens.sessionT2;

  WireStyle get _iptcInlineWire {
    final wire = _captionTemplate?.wireStyle ?? WireStyle.getty;
    if (wire == WireStyle.custom || wire == WireStyle.gettyInternational) {
      return WireStyle.getty;
    }
    return wire;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _awayFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  /// Setup unlocks in order: folder → league → teams → the rest.
  bool get _leagueUnlocked => _folderChosen;
  bool get _teamsUnlocked => _folderChosen && _sportChosen;
  bool get _postTeamsUnlocked =>
      _folderChosen && _sportChosen && _bothTeamsChosen;

  /// Locked steps stay unreadable: heavy blur + fade until the prior pick.
  Widget _setupGate({required bool unlocked, required Widget child}) {
    return IgnorePointer(
      ignoring: !unlocked,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: unlocked ? 0.0 : 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, t, child) {
          final content = child!;
          if (t <= 0.001) return content;
          return ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 7.5 * t,
                sigmaY: 7.5 * t,
              ),
              child: Opacity(
                opacity: 1.0 - (0.78 * t),
                child: content,
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }

  Future<void> _bootstrap() async {
    try {
      _prefs = await PreferencesService.getInstance();
      // Match legacy StartupDialog: fetch public appDefaults so skip-sign-in
      // users get Firebase verbs, caption styles, IPTC catalog, game IDs.
      await _prefs!.ensureAppDefaultsHydrated();
      _useOfficialLeagueApis = await _prefs!.getUseOfficialLeagueApis();
      // Write IPTC starts off every visit unless "Already in files" is sticky.
      // The 3-way control turns writing on (Apply / Fill gaps) or keeps it off.
      _iptcMode = IptcApplyMode.none;
      await _prefs!.saveIptcApplyMode(_iptcMode);
      _iptcAppliedElsewhere = await _prefs!.getIptcAppliedElsewhere();
      _iptcFillGapsOnly = await _prefs!.getIptcFillGapsOnly();
      _iptcStatus = await _iptcStatusFromPrefs();
      _ftpModeEnabled = await _prefs!.getFtpModeEnabled();
      _fileRenamingEnabled = await _prefs!.getFileRenamingEnabled();
      await _loadFtpProfiles();
      await _refreshFileRenameTemplate();
      _hideFirebar = await _prefs!.getHideFirebar();
      _jerseyOcrEnabled = JerseyOcrChannel.supported &&
          await _prefs!.getJerseyOcrEnabled();
      _serialBylinesEnabled = await _prefs!.getSerialNumberBylines();
      await _loadCaptionStyles();
      await _refreshIptcCaptionWarning();
      if (!mounted) return;
      setState(() {});

      final savedSport = await _prefs!.getLastSelectedSport();
      if (savedSport != null && _sports.contains(savedSport)) {
        // Favorites still apply. Last home/away picks do not — blank each launch.
        await _selectSport(savedSport, persist: false, restoreTeams: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Startup failed: $e');
    }
  }

  Future<String> _iptcStatusFromPrefs() async {
    final mode = await _prefs!.getIptcApplyMode();
    final id = await _prefs!.getSelectedIptcTemplateId();
    final label = (id == null || id.isEmpty) ? 'template' : id;
    switch (mode) {
      case IptcApplyMode.none:
        return 'Off';
      case IptcApplyMode.onImport:
        return 'On load · $label';
      case IptcApplyMode.onSave:
        return 'On save · $label';
      case IptcApplyMode.onFtp:
        return 'On FTP · $label';
      case IptcApplyMode.onSaveAndFtp:
        return 'On save & FTP · $label';
    }
  }

  Future<void> _loadCaptionStyles() async {
    setState(() => _loadingStyles = true);
    try {
      final prefs = _prefs ?? await PreferencesService.getInstance();
      final catalog =
          await CaptionStyleCatalog.load(prefs, sport: _sport);
      var template = await prefs.getCaptionTemplate();
      final nbae = await prefs.getGettyNoteIsNbae();
      // Each sport can have its own published structure. The working template
      // may still be the previous sport until saveCurrentSport finishes.
      if (_sportChosen && !template.isUserAuthoredCaptionStyle) {
        final admin = AppDefaultsFirestoreService.mergedCaptionWireDefaults(
          sport: _sport!,
        )[template.wireStyle];
        if (admin != null) {
          template = admin.copyWith(
            wireStyle: template.wireStyle,
            includeTimingPhrase: template.includeTimingPhrase,
            showKeywordsField: template.showKeywordsField,
            showPersonalityField: template.showPersonalityField,
          );
        }
      }
      final sportAware = template;
      if (!mounted) return;
      setState(() {
        _styleCatalog = catalog;
        _captionTemplate = sportAware;
        _selectedStyleToken = catalog.activeToken;
        _gettyNoteIsNbae = nbae;
        _loadingStyles = false;
      });
      // Styles may finish after teams unlock — open IPTC once the Caption box
      // is available and this wire's caption fields are still missing.
      if (_postTeamsUnlocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_maybeOpenIptcAfterWirePick());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStyles = false;
        _error = 'Could not load caption styles: $e';
      });
    }
  }

  Future<void> _selectSport(
    String sport, {
    bool persist = true,
    bool restoreTeams = false,
  }) async {
    final gen = ++_sportSelectGen;
    if (!mounted) return;
    setState(() {
      _sport = sport;
      _error = null;
      _loadingTeams = true;
      _teams = const [];
      _homeTeam = null;
      _awayTeam = null;
      _homeRoster = null;
      _awayRoster = null;
      _usingCustomRosters = false;
      _homeWearsDark = defaultHomeWearsDark(sport);
    });
    try {
      _api.setSport(sport);
      if (persist) {
        unawaited(() async {
          try {
            await _prefs?.saveCurrentSport(sport);
          } catch (e) {
            debugPrint('saveCurrentSport failed: $e');
          }
        }());
      }
      if (!mounted || gen != _sportSelectGen) return;
      await VerbAdminChoice.offer(
        context: context,
        sport: sport,
        stillCurrent: () => mounted && gen == _sportSelectGen,
      );
      if (!mounted || gen != _sportSelectGen) return;
      await _loadFavorites(sport);
      await _loadTeams(restoreLastTeams: restoreTeams);
      await _loadCaptionStyles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTeams = false;
        _offline = true;
        _teams = _fallbackTeams(sport);
        _error = 'Could not load teams — using offline list.';
      });
    }
  }

  Future<void> _loadFavorites(String sport) async {
    final favs = await _prefs?.getFavoriteTeams(sport: sport) ?? <String>{};
    String? home;
    String? away;
    final names = <String>{};
    for (final t in favs) {
      final raw = t.trim();
      if (raw.isEmpty) continue;
      if (raw.startsWith('HOME:')) {
        home = raw.substring(5).trim();
        if (home.isNotEmpty) names.add(home);
      } else if (raw.startsWith('AWAY:')) {
        away = raw.substring(5).trim();
        if (away.isNotEmpty) names.add(away);
      } else {
        names.add(raw);
        home ??= raw;
        if (away == null && raw != home) away = raw;
      }
    }
    _favoriteHome = home?.isEmpty == true ? null : home;
    _favoriteAway = away?.isEmpty == true ? null : away;
    _favoriteTeamNamesRaw = names;
  }

  Future<void> _loadTeams({bool restoreLastTeams = false}) async {
    if (!_sportChosen) return;
    setState(() {
      _loadingTeams = true;
      _error = null;
    });
    try {
      final teams = await _api.fetchTeams();
      if (!mounted) return;
      final names = teams.map((t) => t.name).toSet().toList()..sort();
      await _applyTeamList(
        names,
        offline: false,
        restoreLastTeams: restoreLastTeams,
      );
    } catch (e) {
      if (!mounted) return;
      await _applyTeamList(
        _fallbackTeams(_sport!),
        offline: true,
        restoreLastTeams: restoreLastTeams,
        error: 'Teams loaded offline — check network to refresh.',
      );
    }
  }

  Future<void> _applyTeamList(
    List<String> names, {
    required bool offline,
    bool restoreLastTeams = false,
    String? error,
  }) async {
    // Resolve saved favorites onto the live team list (Tank01 / API names
    // can differ slightly from what was stored).
    final resolvedFavs = <String>{};
    for (final fav in _favoriteTeamNames) {
      final resolved = _resolveFavoriteToTeam(fav, names);
      if (resolved != null) resolvedFavs.add(resolved);
    }
    _favoriteTeamNamesRaw = resolvedFavs;
    final resolvedHome = _favoriteHome == null
        ? null
        : _resolveFavoriteToTeam(_favoriteHome!, names);
    final resolvedAway = _favoriteAway == null
        ? null
        : _resolveFavoriteToTeam(_favoriteAway!, names);
    _favoriteHome = resolvedHome;
    _favoriteAway =
        resolvedAway != null && resolvedAway != resolvedHome ? resolvedAway : null;

    String? home;
    String? away;

    if (_favoriteHome != null) {
      home = _favoriteHome;
    }
    if (_favoriteAway != null && _favoriteAway != home) {
      away = _favoriteAway;
    }

    // Only restore the previous matchup when asked. Otherwise leave blank sides
    // empty so a launch without favorites starts with no teams selected.
    if (restoreLastTeams) {
      final last = await _prefs?.getStartupLastTeams(sport: _sport!) ??
          const MapEntry(null, null);
      if (home == null &&
          last.key != null &&
          names.contains(last.key) &&
          last.key != away) {
        home = last.key;
      }
      if (away == null &&
          last.value != null &&
          names.contains(last.value) &&
          last.value != home) {
        away = last.value;
      }
    }

    if (home != null && home == away) {
      away = null;
    }

    if (!mounted) return;
    final wasUnlocked = _postTeamsUnlocked;
    setState(() {
      _offline = offline;
      _teams = names;
      _loadingTeams = false;
      _homeTeam = home;
      _awayTeam = away;
      _error = error;
      _captionPreviewPlayers = const [];
      if (!_postTeamsUnlocked) _iptcOpenedForStyleToken = null;
    });
    unawaited(_refreshCaptionPreviewPlayers());
    _onCaptionStepUnlocked(wasUnlocked: wasUnlocked);
  }

  Future<void> _setFolder(String path) async {
    final files = await _imageFilesInFolder(path);
    // Prefer EXIF from a photo in the folder; empty folder → today.
    DateTime previewDate = DateTime.now();
    var fromFolderPhoto = false;
    if (files.isNotEmpty) {
      final fromFolder =
          await FileRenameDialog.previewDateFromFolder(path);
      if (fromFolder != null) {
        previewDate = fromFolder;
        fromFolderPhoto = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _folderPath = path;
      _imageCount = files.length;
      _previewPhotoDate = previewDate;
      _previewDateFromFolder = fromFolderPhoto;
      _pickingFolder = false;
      _folderDragOver = false;
      // New folder → let the IPTC checker pick Apply / Fill / Already in files.
      _iptcSourceManual = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_images_folder', path);
    } catch (_) {}
    if (files.isEmpty) {
      await _promptEmptyFolderIptcPlan();
    } else {
      await _refreshIptcCaptionWarning(autoSelectSource: true);
    }
  }

  static String _exifDateTimeOriginal(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}:${two(dt.month)}:${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// Provenance line for the New Session caption preview.
  String? get _captionPreviewSourceNote {
    final bits = <String>[];
    if (_folderChosen) {
      bits.add(
        _previewDateFromFolder
            ? 'Date from folder photo'
            : 'Date is today (no photos in folder)',
      );
    }
    if (_captionPreviewPlayers.isNotEmpty) {
      if (_homeFilled && _awayFilled) {
        bits.add('Players from $_homeTeam / $_awayTeam rosters');
      } else {
        bits.add(
          'Players from ${(_homeFilled ? _homeTeam : _awayTeam)!} roster',
        );
      }
    } else if (_homeFilled || _awayFilled) {
      bits.add('Loading team roster…');
    }
    final home = _homeFilled
        ? _homeTeam
        : (_awayFilled ? _awayTeam : null);
    if (home != null && teamHomePlace(home) != null) {
      bits.add('Location from $home');
    }
    final iptcLocation = IptcTemplateApplyService.lookupValue(
          _iptcPanelForPreview,
          'Location',
        ) ??
        IptcTemplateApplyService.lookupValue(_iptcPanelForPreview, 'Stadium');
    final venue = (iptcLocation ?? _previewHomeVenue ?? '').trim();
    if (venue.isNotEmpty) {
      bits.add('Location: $venue');
    }
    if (bits.isEmpty) return null;
    return bits.join(' · ');
  }

  /// Sample [GameInfo] for caption style preview / layout editor.
  /// City/state from the selected home team; Location from IPTC when set,
  /// otherwise the league API stadium for home.
  GameInfo _buildPreviewGameInfo() {
    final date = _previewPhotoDate;
    final fromPanel =
        IptcTemplateApplyService.gameInfoFromPanelValues(_iptcPanelForPreview);
    final iptcLocation = fromPanel.venue.trim();
    var info = GameInfo(
      gameDate: date,
      photographerName: fromPanel.photographerName.trim().isNotEmpty
          ? fromPanel.photographerName
          : CurrentUserService.displayNameOrPlaceholder(),
      agencyName: fromPanel.agencyName,
      iptcMetadata: {
        'DateTimeOriginal': _exifDateTimeOriginal(date),
        ...fromPanel.iptcMetadata,
      },
    );
    final home = _homeFilled
        ? _homeTeam
        : (_awayFilled ? _awayTeam : null);
    if (home != null) {
      final place = teamHomePlace(home);
      if (place != null) {
        info = place.applyTo(info);
      }
    }
    // Prefer IPTC City / Province / Country when the template or folder has them.
    if (fromPanel.city.trim().isNotEmpty ||
        fromPanel.region.trim().isNotEmpty ||
        fromPanel.country.trim().isNotEmpty) {
      info = info.copyWith(
        city: fromPanel.city.trim().isNotEmpty ? fromPanel.city : info.city,
        region:
            fromPanel.region.trim().isNotEmpty ? fromPanel.region : info.region,
        country: fromPanel.country.trim().isNotEmpty
            ? fromPanel.country
            : info.country,
        countryCode: fromPanel.countryCode.trim().isNotEmpty
            ? fromPanel.countryCode
            : info.countryCode,
      );
    }
    final apiVenue = (_previewHomeVenue ?? '').trim();
    final venue = iptcLocation.isNotEmpty ? iptcLocation : apiVenue;
    if (venue.isNotEmpty) {
      info = info.copyWith(
        venue: venue,
        iptcMetadata: iptcLocation.isNotEmpty
            ? CaptionFormulaRenderer.iptcLocationMetadata(
                iptcLocation,
                info.iptcMetadata,
              )
            : info.iptcMetadata,
      );
    }
    return info;
  }

  Future<List<String>> _imageFilesInFolder(String dirPath) async {
    try {
      final out = <String>[];
      await for (final entity in Directory(dirPath).list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name.startsWith('._')) continue;
        final lower = name.toLowerCase();
        if (lower.startsWith('tmp.') || lower.endsWith('.tmp')) continue;
        if (_imageExtensions.contains(p.extension(lower))) {
          out.add(entity.path);
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _pickingFolder = true);
    try {
      String? last;
      try {
        final prefs = await SharedPreferences.getInstance();
        last = prefs.getString('last_images_folder');
      } catch (_) {}
      final result = await NativeFilePicker.pickDirectory(
        initialDirectory: last,
      );
      if (result == null) {
        if (mounted) setState(() => _pickingFolder = false);
        return;
      }
      await _setFolder(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickingFolder = false;
        _error = 'Could not open folder: $e';
      });
    }
  }

  void _onFolderDropped(DropDoneDetails detail) {
    if (detail.files.isEmpty) return;
    final first = detail.files.first.path;
    if (first.isEmpty) return;
    final entity = FileSystemEntity.typeSync(first);
    final folder = entity == FileSystemEntityType.directory
        ? first
        : p.dirname(first);
    unawaited(_setFolder(folder));
  }

  Future<void> _toggleFavoriteTeam(
    String team, {
    required bool isHome,
  }) async {
    if (_sport == null || _prefs == null) return;
    final favs = await _prefs!.getFavoriteTeams(sport: _sport!);
    final prefix = isHome ? 'HOME:' : 'AWAY:';
    final currently = isHome ? _favoriteHome == team : _favoriteAway == team;
    // Drop this side’s tagged entry and any plain duplicate of [team].
    favs.removeWhere(
      (e) =>
          e.startsWith(prefix) ||
          e.trim() == team ||
          e.trim().toLowerCase() == team.toLowerCase(),
    );
    if (!currently) {
      favs.add('$prefix$team');
      if (isHome) {
        _favoriteHome = team;
      } else {
        _favoriteAway = team;
      }
      _favoriteTeamNamesRaw = {..._favoriteTeamNamesRaw, team};
    } else {
      if (isHome) {
        _favoriteHome = null;
      } else {
        _favoriteAway = null;
      }
      _favoriteTeamNamesRaw = {
        for (final n in _favoriteTeamNamesRaw)
          if (n != team) n,
      };
      if (_favoriteHome != null) _favoriteTeamNamesRaw.add(_favoriteHome!);
      if (_favoriteAway != null) _favoriteTeamNamesRaw.add(_favoriteAway!);
    }
    await _prefs!.saveFavoriteTeams(favs, sport: _sport!);
    if (mounted) setState(() {});
  }

  Future<void> _setUseOfficialLeagueApis(bool enabled) async {
    await _prefs?.saveUseOfficialLeagueApis(enabled);
    if (!mounted) return;
    setState(() => _useOfficialLeagueApis = enabled);
  }

  Future<void> _setWriteIptc(bool enabled) async {
    if (enabled == _writeIptc) return;
    if (!enabled) {
      await _prefs?.saveIptcApplyMode(IptcApplyMode.none);
      if (!mounted) return;
      setState(() {
        _iptcMode = IptcApplyMode.none;
        _iptcStatus = 'Off';
      });
      await _refreshIptcCaptionWarning();
      return;
    }

    final summary = await showCaptionV2IptcDialog(
      context,
      folderPath: _folderPath,
      enableWriting: true,
      populateFromFolder: _folderChosen,
      captionTemplate: _captionTemplate,
    );
    if (!mounted) return;
    if (summary == null || summary.mode == IptcApplyMode.none) {
      await _prefs?.saveIptcApplyMode(IptcApplyMode.none);
      if (!mounted) return;
      setState(() {
        _iptcMode = IptcApplyMode.none;
        _iptcStatus = 'Off';
      });
      await _refreshIptcCaptionWarning();
      return;
    }
    await _prefs?.saveIptcApplyMode(summary.mode);
    if (!mounted) return;
    setState(() {
      _iptcMode = summary.mode;
      _iptcStatus = summary.statusLine;
    });
    await _refreshIptcCaptionWarning();
  }

  /// Startup strip toggle: write the IPTC template when the session opens.
  Future<void> _setApplyIptcOnIngest(bool enabled) async {
    if (enabled == _iptcMode.appliesOnLoad) return;
    await _setIptcSource(
      enabled
          ? (_iptcFillGapsOnly ? _IptcSourceMode.fill : _IptcSourceMode.apply)
          : _IptcSourceMode.files,
    );
  }

  /// IPTC is handled outside FloFile — do not write or block on missing fields.
  Future<void> _setIptcAppliedElsewhere(bool enabled) async {
    if (enabled == _iptcAppliedElsewhere) return;
    await _setIptcSource(
      enabled ? _IptcSourceMode.files : _IptcSourceMode.apply,
    );
  }

  /// Maps the 3-way IPTC source control onto apply-mode + fill-gaps + elsewhere.
  Future<void> _setIptcSource(
    _IptcSourceMode source, {
    bool refresh = true,
    bool markManual = true,
  }) async {
    if (markManual) _iptcSourceManual = true;
    if (source == _iptcSource &&
        (source != _IptcSourceMode.apply || _writeIptc) &&
        (source != _IptcSourceMode.fill || (_writeIptc && _iptcFillGapsOnly))) {
      // Allow re-selecting Apply/Fill when write is still off (fresh visit).
      if (source == _IptcSourceMode.files || _writeIptc) return;
    }
    switch (source) {
      case _IptcSourceMode.apply:
        await _prefs?.saveIptcApplyMode(IptcApplyMode.onImport);
        await _prefs?.saveIptcAppliedElsewhere(false);
        await _prefs?.saveIptcFillGapsOnly(false);
        if (!mounted) return;
        setState(() {
          _iptcMode = IptcApplyMode.onImport;
          _iptcAppliedElsewhere = false;
          _iptcFillGapsOnly = false;
          _iptcStatus = 'On load';
        });
      case _IptcSourceMode.fill:
        await _prefs?.saveIptcApplyMode(IptcApplyMode.onImport);
        await _prefs?.saveIptcAppliedElsewhere(false);
        await _prefs?.saveIptcFillGapsOnly(true);
        if (!mounted) return;
        setState(() {
          _iptcMode = IptcApplyMode.onImport;
          _iptcAppliedElsewhere = false;
          _iptcFillGapsOnly = true;
          _iptcStatus = 'Fill gaps';
        });
      case _IptcSourceMode.files:
        await _prefs?.saveIptcApplyMode(IptcApplyMode.none);
        await _prefs?.saveIptcAppliedElsewhere(true);
        await _prefs?.saveIptcFillGapsOnly(false);
        if (!mounted) return;
        setState(() {
          _iptcMode = IptcApplyMode.none;
          _iptcAppliedElsewhere = true;
          _iptcFillGapsOnly = false;
          _iptcStatus = 'Elsewhere';
        });
    }
    if (refresh) await _refreshIptcCaptionWarning();
  }

  /// Folder scan → recommended IPTC source for New Session load-in.
  ///
  /// All required caption + wire fields present on files → Already in files.
  /// Some IPTC present but required fields still missing → Fill missing IPTC.
  /// Nothing on the files → Apply my template.
  _IptcSourceMode _recommendIptcSourceFromScan({
    required Map<String, String> fromFiles,
    required CaptionTemplate captionTemplate,
    required WireStyle wire,
  }) {
    final hasAny = fromFiles.values.any((v) {
      final trimmed = v.trim();
      return trimmed.isNotEmpty &&
          !IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed);
    });
    if (!hasAny) return _IptcSourceMode.apply;

    final captionMissing = CaptionFormulaRenderer.missingCaptionIptcLabels(
      template: captionTemplate,
      game: IptcTemplateApplyService.gameInfoFromPanelValues(fromFiles),
      includeCreator: false,
    );
    final filingMissing =
        IptcTemplateApplyService.missingRequiredLabels(wire, fromFiles);
    if (captionMissing.isEmpty && filingMissing.isEmpty) {
      return _IptcSourceMode.files;
    }
    return _IptcSourceMode.fill;
  }

  /// Empty edit folder: ask which of the three IPTC sources to use.
  Future<void> _promptEmptyFolderIptcPlan() async {
    if (!mounted) return;
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final choice = await showDialog<_IptcSourceMode>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        final screenW = MediaQuery.sizeOf(ctx).width;
        final dialogW = math.min(440.0, screenW * 0.92);
        Widget option({
          required _IptcSourceMode mode,
          required String label,
          required bool primary,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedGreyButton(
                label: label,
                fontSize: 11,
                isPrimary: primary,
                onPressed: () => Navigator.pop(ctx, mode),
              ),
            ),
          );
        }

        return AppDialogFfStyle(
          enabled: true,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 280, maxWidth: dialogW),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius:
                        BorderRadius.circular(FfTokens.radiusWindow),
                    border: Border.all(color: tokens.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(FfTokens.radiusWindow),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                          decoration: BoxDecoration(
                            color: tokens.bg,
                            border: Border(
                              bottom: BorderSide(color: tokens.divider),
                            ),
                          ),
                          child: Text(
                            'No images yet',
                            style: tokens.labelStyle.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(
                            'This folder has no images yet. How should IPTC be '
                            'handled when photos arrive?',
                            style: tokens.bodyStyle.copyWith(
                              fontSize: 13,
                              height: 1.4,
                              color: tokens.text.withValues(alpha: 0.88),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              option(
                                mode: _IptcSourceMode.apply,
                                label: 'Apply my template',
                                primary: true,
                              ),
                              option(
                                mode: _IptcSourceMode.fill,
                                label: 'Fill missing IPTC',
                                primary: false,
                              ),
                              option(
                                mode: _IptcSourceMode.files,
                                label: 'Already in files',
                                primary: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    await _setIptcSource(
      choice ?? _IptcSourceMode.files,
      refresh: false,
      markManual: false,
    );
    await _refreshIptcCaptionWarning();
  }

  void _showSetupStep(int step, {String? focus}) {
    setState(() {
      _setupStep = step;
      _setupFocusTarget = step == 2 ? focus : null;
    });
    if (step == 2 && focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (focus) {
          case 'away':
            _awayFocus.requestFocus();
          case 'home':
            _homeFocus.requestFocus();
          default:
            _rootFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _continueFromWire() async {
    if (!_canContinueFromWire || _setupStep != 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted || _setupStep != 1) return;
    _showSetupStep(2);
  }

  Future<void> _continueToCaptionStep() async {
    if (!_canContinue || _setupStep != 2) return;
    // Defer past pointer-up. Any setState during the Continue gesture
    // (including IPTC sync) disposes the button under the cursor and
    // blanks Step 3 via MouseTracker asserts.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted || _setupStep != 2) return;

    // Fresh visit leaves write off — sync the visible Apply/Fill choice on.
    if (!_iptcAppliedElsewhere && !_writeIptc) {
      await _setIptcSource(
        _iptcFillGapsOnly ? _IptcSourceMode.fill : _IptcSourceMode.apply,
      );
      if (!mounted || _setupStep != 2) return;
    }
    _showSetupStep(3);
  }

  List<(String, String)> get _wireStepOptions {
    final catalog = _styleCatalog;
    if (catalog != null) {
      final fromCatalog = <(String, String)>[
        for (final option in catalog.options)
          if (CaptionStyleCatalog.isCoreWireToken(option.token))
            (option.token, option.label),
      ];
      if (fromCatalog.isNotEmpty) return fromCatalog;
    }
    return const [
      (CaptionStyleCatalog.tokGetty, 'Getty'),
      (CaptionStyleCatalog.tokImagn, 'Imagn'),
      (CaptionStyleCatalog.tokAp, 'AP'),
      (CaptionStyleCatalog.tokCp, 'CP'),
    ];
  }

  String get _selectedWireLabel {
    final token = _selectedStyleToken;
    if (token == null) return 'Wire';
    final catalog = _styleCatalog;
    if (catalog != null) return catalog.labelFor(token);
    for (final option in _wireStepOptions) {
      if (option.$1 == token) return option.$2;
    }
    return 'Wire';
  }

  Future<void> _refreshIptcCaptionWarning({
    bool autoSelectSource = false,
  }) async {
    final prefs = _prefs;
    final gen = ++_iptcScanGen;
    final folder = _folderPath?.trim() ?? '';
    if (prefs == null || folder.isEmpty) {
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _missingCaptionIptc = const [];
        _missingFilingIptc = const [];
        _iptcScanWithCityDate = 0;
        _iptcScanTotal = 0;
        _iptcValuesFromFiles = const {};
        _iptcValuesFromTemplate = const {};
        _iptcKeysFoundInFiles = const {};
        _scanningIptc = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _scanningIptc = true);
    }

    try {
      await AppDefaultsFirestoreService.fetchAndCacheAppDefaults();
      final hidden = await prefs.getHiddenIptcTemplateIds();
      final visible = await AppDefaultsFirestoreService.getVisibleIptcTemplates(
        hiddenIds: hidden,
      );
      final selectedId = await prefs.getSelectedIptcTemplateId() ?? 'getty';
      final captionTemplate = _captionTemplate ?? CaptionTemplate.getty();
      var wire = captionTemplate.wireStyle == WireStyle.custom
          ? WireStyle.getty
          : captionTemplate.wireStyle;
      for (final t in visible) {
        if (t.id == selectedId) {
          // Prefer the active caption style’s wire; fall back to template id.
          if (captionTemplate.wireStyle == WireStyle.custom) {
            wire = t.wireStyle;
          }
          break;
        }
      }
      if (visible.isEmpty) {
        for (final w in WireStyle.values) {
          if (AppDefaultsFirestoreService.templateIdForWire(w) == selectedId) {
            if (captionTemplate.wireStyle == WireStyle.custom) {
              wire = w;
            }
            break;
          }
        }
      }

      // 1) Scan images from the chosen folder (sample for template gaps;
      //    full folder for city+date coverage when reading from files).
      final files = await _imageFilesInFolder(folder);
      if (gen != _iptcScanGen) return;
      final rawFromFiles = <String, String>{};
      var withCityDate = 0;
      var withCityDateRaw = 0;
      if (files.isNotEmpty) {
        // Cap the coverage scan so huge folders stay responsive.
        final coverage = files.length <= 80 ? files : files.take(80).toList();
        var batch =
            await IptcTemplateImportService.readMetadataBatch(coverage);
        if (gen != _iptcScanGen) return;
        // Fallback: big batches can fail; read a small sample one-by-one.
        if (batch.isEmpty) {
          final sample = files.take(8).toList();
          batch = await IptcTemplateImportService.readMetadataBatch(sample);
          if (gen != _iptcScanGen) return;
          if (batch.isEmpty) {
            for (final path in sample) {
              final meta =
                  await IptcTemplateImportService.readMetadata(path);
              if (meta != null) batch[path] = meta;
            }
            if (gen != _iptcScanGen) return;
          }
        }
        // Union filled fields from every unique metadata map (path aliases can
        // duplicate the same map under several keys).
        final seenMeta = <int>{};
        for (final meta in batch.values) {
          if (!seenMeta.add(identityHashCode(meta))) continue;
          final panel = IptcTemplateImportService.panelValuesFromExiftool(meta);
          panel.forEach((k, v) {
            final trimmed = v.trim();
            if (trimmed.isEmpty) return;
            if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
              return;
            }
            rawFromFiles.putIfAbsent(k, () => trimmed);
          });
        }
        for (final path in coverage) {
          final meta = batch[path] ??
              batch[p.normalize(path)] ??
              batch[p.normalize(File(path).absolute.path)];
          if (meta == null) continue;
          final panel = IptcTemplateImportService.panelValuesFromExiftool(meta);
          final city = (panel['City'] ?? '').trim();
          final date = (panel['Date'] ?? panel['Time and Date'] ?? '').trim();
          if (city.isNotEmpty && date.isNotEmpty) withCityDateRaw++;
        }
        withCityDate = withCityDateRaw;
        // Scale the sample count up when we only scanned a subset.
        if (coverage.length < files.length && coverage.isNotEmpty) {
          withCityDate =
              ((withCityDateRaw / coverage.length) * files.length).round();
        }
      }
      // Normalize to wire panel keys so the IPTC builder can show them.
      final fromFiles =
          IptcTemplateApplyService.panelValuesFromImportedTemplate(
        rawFromFiles,
        wire,
      );
      rawFromFiles.forEach((k, v) {
        final trimmed = v.trim();
        if (trimmed.isEmpty) return;
        if (IptcTemplateApplyService.toPresetKey(k) == 'Caption' ||
            k == 'Caption') {
          return;
        }
        fromFiles.putIfAbsent(k, () => trimmed);
      });
      fromFiles.removeWhere(
        (k, _) =>
            IptcTemplateApplyService.toPresetKey(k) == 'Caption' ||
            k == 'Caption',
      );

      // Load-in checker: pick Already in files / Fill gaps / Apply template.
      if (autoSelectSource &&
          !_iptcSourceManual &&
          files.isNotEmpty &&
          gen == _iptcScanGen) {
        final recommended = _recommendIptcSourceFromScan(
          fromFiles: fromFiles,
          captionTemplate: captionTemplate,
          wire: wire,
        );
        await _setIptcSource(
          recommended,
          refresh: false,
          markManual: false,
        );
        if (!mounted || gen != _iptcScanGen) return;
      }

      // 2) Selected IPTC template fills gaps for structure/caption preview.
      // Write-IPTC warnings only count the template when writing is enabled.
      var preset = await prefs.getIptcWirePreset(wire);
      if (preset.isEmpty) {
        for (final t in visible) {
          if (t.wireStyle == wire && t.preset.isNotEmpty) {
            preset = t.preset;
            break;
          }
        }
      }
      final templatePanel =
          IptcTemplateApplyService.denormalizeForPanel(preset);
      final previewPanel = Map<String, String>.from(fromFiles);
      templatePanel.forEach((k, v) {
        final trimmed = v.trim();
        if (trimmed.isEmpty) return;
        if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
          return;
        }
        previewPanel.putIfAbsent(k, () => trimmed);
      });
      final effective =
          _writeIptc ? previewPanel : Map<String, String>.from(fromFiles);

      final missing = CaptionFormulaRenderer.missingCaptionIptcLabels(
        template: captionTemplate,
        game: IptcTemplateApplyService.gameInfoFromPanelValues(effective),
        includeCreator: false,
      );
      final filingMissing =
          IptcTemplateApplyService.missingRequiredLabels(wire, effective)
              .where(
                (label) => !missing.any(
                  (m) => m.toLowerCase() == label.toLowerCase(),
                ),
              )
              .toList();
      if (!mounted || gen != _iptcScanGen) return;
      final foundKeys = <String>{};
      for (final key in fromFiles.keys) {
        if (key == 'Caption' || key == 'Personality') continue;
        foundKeys.add(key);
      }
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _iptcPanelForPreview = previewPanel;
        _missingCaptionIptc = missing;
        _missingFilingIptc = filingMissing;
        _iptcScanWithCityDate = withCityDate;
        _iptcScanTotal = files.length;
        _iptcValuesFromFiles = Map<String, String>.from(fromFiles);
        _iptcValuesFromTemplate = Map<String, String>.from(templatePanel);
        _iptcKeysFoundInFiles = foundKeys;
        _iptcInlineRevision++;
        _scanningIptc = false;
      });
    } catch (_) {
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _missingCaptionIptc = const [];
        _missingFilingIptc = const [];
        _iptcScanWithCityDate = 0;
        _iptcScanTotal = 0;
        _iptcValuesFromFiles = const {};
        _iptcValuesFromTemplate = const {};
        _iptcKeysFoundInFiles = const {};
        _scanningIptc = false;
      });
    }
  }

  Future<void> _loadFtpProfiles() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final profiles = await prefs.getFtpProfiles();
    final current = await prefs.getCurrentFtpProfile();
    final names = profiles.keys.toList()..sort();
    if (!mounted) return;
    setState(() {
      _ftpProfileNames = names;
      _ftpProfileName =
          current != null && names.contains(current) ? current : null;
    });
  }

  Future<void> _openFtpSettings(BuildContext anchorContext) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 820,
            height: 580,
            decoration: BoxDecoration(
              color: FfTokens.sessionPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: FfTokens.sessionLn),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C000000),
                  blurRadius: 60,
                  offset: Offset(0, 24),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: FtpSettingsPanel(
              embedded: false,
              onClose: () {
                Navigator.pop(dialogContext);
              },
              onProfilesChanged: () {
                unawaited(_loadFtpProfiles());
              },
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    await _loadFtpProfiles();
    await _refreshFileRenameTemplate();
  }

  Future<void> _setFtpMode(bool enabled) async {
    if (enabled == _ftpModeEnabled) return;
    await _prefs?.saveFtpModeEnabled(enabled);
    if (!mounted) return;
    setState(() => _ftpModeEnabled = enabled);
  }

  Future<void> _refreshFileRenameTemplate() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final current = await prefs.getCurrentFtpProfile();
    final profiles = await prefs.getFtpProfiles();
    final name = current != null && profiles.containsKey(current)
        ? current
        : (profiles.isNotEmpty ? profiles.keys.first : null);
    final template =
        name == null ? '' : (profiles[name]?['renameAs']?.toString() ?? '');
    if (!mounted) return;
    setState(() => _fileRenameTemplate = template.trim());
  }

  Future<void> _setFileRenaming(bool enabled) async {
    if (enabled == _fileRenamingEnabled) return;
    await _prefs?.saveFileRenamingEnabled(enabled);
    if (!mounted) return;
    setState(() => _fileRenamingEnabled = enabled);
  }

  Future<void> _openFileRename() async {
    final preview = await FileRenameDialog.previewDataFromFolder(
      _folderPath,
      awayTeam: _awayFilled ? mlbTeamAbbreviation(_awayTeam!) : '',
      homeTeam: _homeFilled ? mlbTeamAbbreviation(_homeTeam!) : '',
    );
    if (!mounted) return;
    final saved = await FileRenameDialog.show(
      context,
      preview: preview,
    );
    if (!mounted) return;
    await _refreshFileRenameTemplate();
    if (saved != null && !_fileRenamingEnabled) {
      await _setFileRenaming(true);
    }
  }

  Future<void> _setFirebarShown(bool shown) async {
    final hidden = !shown;
    if (hidden == _hideFirebar) return;
    await _prefs?.saveHideFirebar(hidden);
    if (!mounted) return;
    setState(() => _hideFirebar = hidden);
  }

  Future<void> _setJerseyOcr(bool enabled) async {
    if (enabled == _jerseyOcrEnabled) return;
    await _prefs?.saveJerseyOcrEnabled(enabled);
    if (!mounted) return;
    setState(() => _jerseyOcrEnabled = enabled);
  }

  Future<void> _setSerialBylines(bool enabled) async {
    if (enabled == _serialBylinesEnabled) return;
    await _prefs?.saveSerialNumberBylines(enabled);
    if (!mounted) return;
    setState(() => _serialBylinesEnabled = enabled);
  }

  Future<void> _openSerialNumbers() async {
    final cameraService = CameraSerialService.instance;
    await cameraService.initialize();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => CameraSerialDialog(
        cameraService: cameraService,
      ),
    );
  }

  Future<void> _openIptc({
    bool populateFromFolder = false,
    bool enableWriting = false,
    String? focusField,
    IptcMissingHighlight? missingHighlight,
  }) async {
    final summary = await showCaptionV2IptcDialog(
      context,
      folderPath: _folderPath,
      enableWriting: enableWriting,
      // Always fill the pad from folder IPTC when a folder is set.
      populateFromFolder: _folderChosen || populateFromFolder,
      captionTemplate: _captionTemplate,
      initialFocusField: focusField,
      initialMissingHighlight: missingHighlight,
    );
    if (!mounted || summary == null) return;
    await _prefs?.saveIptcApplyMode(summary.mode);
    if (summary.mode != IptcApplyMode.none) {
      await _prefs?.saveIptcAppliedElsewhere(false);
    }
    if (!mounted) return;
    setState(() {
      _iptcMode = summary.mode;
      _iptcStatus = summary.statusLine;
      if (summary.mode != IptcApplyMode.none) {
        _iptcAppliedElsewhere = false;
      }
    });
    await _refreshIptcCaptionWarning();
  }

  /// Prefer red caption gaps; otherwise grey filing gaps.
  IptcMissingHighlight? get _preferredMissingHighlight {
    if (_missingCaptionIptc.isNotEmpty) return IptcMissingHighlight.caption;
    if (_missingFilingIptc.isNotEmpty) return IptcMissingHighlight.filing;
    return null;
  }

  Future<void> _openIptcForMissingFields({
    IptcMissingHighlight? highlight,
  }) {
    return _openIptc(
      populateFromFolder: true,
      enableWriting: true,
      missingHighlight: highlight ?? _preferredMissingHighlight,
    );
  }

  /// Opens IPTC when the Caption style box is reached (or wire changes) and
  /// caption fields are still missing. Folder pick alone must not open the pad.
  Future<void> _maybeOpenIptcAfterWirePick() async {
    if (!_postTeamsUnlocked || !_folderChosen) return;
    if (_iptcAppliedElsewhere) return;
    final token = _selectedStyleToken;
    if (token == null || _captionTemplate == null) return;

    await _refreshIptcCaptionWarning();
    if (!mounted) return;
    if (_missingCaptionIptc.isEmpty) {
      _iptcOpenedForStyleToken = token;
      return;
    }
    // Skip only if we already opened for this wire in this pass (e.g. wire
    // change fired select + onWireChanged together).
    if (_iptcOpenedForStyleToken == token) return;

    _iptcOpenedForStyleToken = token;
    await _openIptc(populateFromFolder: true, enableWriting: true);
    if (!mounted) return;
    await _refreshIptcCaptionWarning();
    // Still missing after dismiss → allow another open on the next wire tap.
    if (!_captionIptcReady) _iptcOpenedForStyleToken = null;
  }

  /// Caption style box just unlocked (both teams chosen).
  void _onCaptionStepUnlocked({required bool wasUnlocked}) {
    if (wasUnlocked || !_postTeamsUnlocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeOpenIptcAfterWirePick());
    });
  }

  /// Opens IPTC when caption fields are missing. Returns true only when
  /// everything needed for captions is present (folder and/or template), or
  /// when the user marked IPTC as applied elsewhere.
  Future<bool> _ensureCaptionIptcReady() async {
    if (_iptcAppliedElsewhere) return true;
    if (_scanningIptc) {
      await _refreshIptcCaptionWarning();
      if (!mounted) return false;
    }
    if (_captionIptcReady) return true;

    await _openIptc(populateFromFolder: true, enableWriting: true);
    if (!mounted) return false;
    if (_captionIptcReady) return true;

    if (_missingCaptionIptc.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Missing fields to build caption'),
          duration: Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  Future<void> _pasteRoster() async {
    if (!_sportChosen) return;
    setState(() => _usingCustomRosters = true);
    final result = await showRosterImportDialog(
      context,
      sport: _sport!,
      homeTeamLabel: _homeRoster == null ? null : _homeTeam,
      awayTeamLabel: _awayRoster == null ? null : _awayTeam,
      homePlayers: _homeRoster,
      awayPlayers: _awayRoster,
    );
    if (!mounted || result == null) return;
    setState(() {
      _homeRoster = result.homePlayers;
      _awayRoster = result.awayPlayers;
      if (result.homePlayers != null) {
        _homeTeam = result.homeTeamName;
      }
      if (result.awayPlayers != null) {
        _awayTeam = result.awayTeamName;
      }
      _captionPreviewPlayers = const [];
    });
    unawaited(_refreshCaptionPreviewPlayers());
  }

  Future<void> _selectStyle(String token) async {
    final catalog = _styleCatalog;
    if (catalog == null) return;
    if (token == _selectedStyleToken) {
      // Same wire re-tapped on the Caption step — open IPTC if still missing.
      await _refreshIptcCaptionWarning();
      if (!mounted) return;
      await _maybeOpenIptcAfterWirePick();
      return;
    }
    final prefs = _prefs ?? await PreferencesService.getInstance();
    final template = catalog
        .resolve(token, refForCustom: _captionTemplate)
        .normalizePerOccurrenceLists();
    final sportAware = _sportChosen
        ? await prefs.applyGameIdentifierForSport(
            template,
            template.wireStyle,
            _sport!,
          )
        : template;
    await prefs.saveCaptionTemplate(sportAware);
    if (!mounted) return;
    setState(() {
      _selectedStyleToken = token;
      _captionTemplate = sportAware;
    });
    // GlobalKey keeps the embedded builder State alive across KeyedSubtree
    // remounts — push the new wire template into Structure + PREVIEW.
    _captionBuilderKey.currentState?.applyHostCaptionTemplate(sportAware);
    await _refreshIptcCaptionWarning();
    if (!mounted) return;
    // Caption box + wire chosen → open IPTC if caption fields are still missing.
    await _maybeOpenIptcAfterWirePick();
  }

  Future<void> _editStyles() async {
    if (_captionPreviewPlayers.isEmpty &&
        (_homeFilled || _awayFilled)) {
      await _refreshCaptionPreviewPlayers();
      if (!mounted) return;
    }
    final applied = await CaptionLayoutBuilderDialog.show(
      context,
      initialSport: _sport,
      previewHomeTeam: _homeFilled ? _homeTeam : null,
      previewAwayTeam: _awayFilled ? _awayTeam : null,
      previewGameInfo: _buildPreviewGameInfo(),
      previewPlayers: _captionPreviewPlayers.isEmpty
          ? null
          : List<CaptionPreviewPlayer>.from(_captionPreviewPlayers),
      previewDateFromFolder: _folderChosen ? _previewDateFromFolder : null,
    );
    if (!mounted) return;
    if (applied != null) {
      final prefs = _prefs ?? await PreferencesService.getInstance();
      final catalog =
          await CaptionStyleCatalog.load(prefs, sport: _sport);
      final sportAware = _sportChosen
          ? await prefs.applyGameIdentifierForSport(
              applied,
              applied.wireStyle,
              _sport!,
            )
          : applied;
      if (!mounted) return;
      setState(() {
        _styleCatalog = catalog;
        _captionTemplate = sportAware;
        _selectedStyleToken = catalog.activeToken;
      });
      await _refreshIptcCaptionWarning();
      return;
    }
    await _loadCaptionStyles();
    await _refreshIptcCaptionWarning();
  }

  Future<bool> _confirmWriteIptc() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Apply IPTC?',
      message:
          'Template fields will be written to these photos. Existing captions '
          'stay as they are.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Apply IPTC',
    );
    return confirmed == true;
  }

  Future<void> _restartSetup() async {
    final hasProgress = _folderChosen ||
        _homeFilled ||
        _awayFilled ||
        _writeIptc ||
        _usingCustomRosters;
    if (hasProgress) {
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Restart setup?',
        message:
            'Clear the folder, teams, and IPTC write settings on this screen?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Restart',
      );
      if (confirmed != true || !mounted) return;
    }

    await _prefs?.saveIptcApplyMode(IptcApplyMode.none);
    await _prefs?.saveIptcAppliedElsewhere(false);
    await _prefs?.saveIptcFillGapsOnly(false);
    if (!mounted) return;
    setState(() {
      _setupStep = 1;
      _setupFocusTarget = null;
      _folderPath = null;
      _imageCount = 0;
      _pickingFolder = false;
      _folderDragOver = false;
      _previewPhotoDate = DateTime.now();
      _previewDateFromFolder = false;
      _homeTeam = null;
      _awayTeam = null;
      _homeRoster = null;
      _awayRoster = null;
      _usingCustomRosters = false;
      _captionPreviewPlayers = const [];
      _previewHomeVenue = null;
      _going = false;
      _error = null;
      _iptcMode = IptcApplyMode.none;
      _iptcAppliedElsewhere = false;
      _iptcFillGapsOnly = false;
      _iptcStatus = 'Off';
      _missingCaptionIptc = const [];
      _missingFilingIptc = const [];
      _iptcScanWithCityDate = 0;
      _iptcScanTotal = 0;
      _iptcValuesFromFiles = const {};
      _iptcValuesFromTemplate = const {};
      _iptcKeysFoundInFiles = const {};
      _iptcInlineRevision = 0;
      _iptcSourceManual = false;
      _scanningIptc = false;
      _iptcPanelForPreview = const {};
      _iptcOpenedForStyleToken = null;
      _homeWearsDark = null;
    });
    if (_sport != null) {
      await _loadFavorites(_sport!);
      if (mounted) setState(() {});
    }
    await _refreshIptcCaptionWarning();
  }

  Future<void> _goTime() async {
    if (!_canGo) return;

    final single = _inferredSingleTeam;
    if (single) {
      final teamName = _homeFilled ? _homeTeam! : _awayTeam!;
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'One team only?',
        message:
            'Only $teamName is selected. Continue with a single-team session (no opponent)?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Continue',
      );
      if (confirmed != true || !mounted) return;
    }

    // Caption IPTC must be complete before the session starts.
    final iptcReady = await _ensureCaptionIptcReady();
    if (!iptcReady || !mounted) return;

    if (_writeIptc) {
      final confirmed = await _confirmWriteIptc();
      if (confirmed != true || !mounted) return;
    }

    setState(() => _going = true);
    await _prefs?.saveUseOfficialLeagueApis(_useOfficialLeagueApis);
    if (_sport != null) {
      try {
        await _prefs?.saveCurrentSport(_sport!);
      } catch (_) {}
    }

    final String home;
    final String away;
    final List<Player>? homeRoster;
    final List<Player>? awayRoster;
    if (single) {
      if (_homeFilled) {
        home = _homeTeam!;
        homeRoster = _homeRoster;
      } else {
        home = _awayTeam!;
        homeRoster = _awayRoster;
      }
      away = '';
      awayRoster = null;
    } else {
      home = _homeTeam!;
      away = _awayTeam!;
      homeRoster = _homeRoster;
      awayRoster = _awayRoster;
    }

    if (_sport != null && away.isNotEmpty) {
      await _prefs?.saveStartupLastTeams(
        sport: _sport!,
        homeTeam: home,
        awayTeam: away,
      );
    }

    widget.onComplete(
      CaptionV2StartupResult(
        sport: _sport!,
        folderPath: _folderPath!,
        homeTeam: home,
        awayTeam: away,
        homeRoster: homeRoster,
        awayRoster: awayRoster,
        singleTeamMode: single,
        homeWearsDark: single ? null : _homeWearsDark,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_openMenuId != null) return KeyEventResult.ignored;
      if (_setupStep == 3) {
        _showSetupStep(2);
        return KeyEventResult.handled;
      }
      if (_setupStep == 2) {
        _showSetupStep(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    final mods = HardwareKeyboard.instance.logicalKeysPressed;
    final chord = mods.contains(LogicalKeyboardKey.meta) ||
        mods.contains(LogicalKeyboardKey.control);

    if (_awayFocus.hasFocus || _homeFocus.hasFocus || _openMenuId != null) {
      return KeyEventResult.ignored;
    }

    if (_setupStep == 1) {
      if (chord) return KeyEventResult.ignored;
      if (!_canContinueFromWire) return KeyEventResult.ignored;
      unawaited(_continueFromWire());
      return KeyEventResult.handled;
    }

    if (_setupStep == 2) {
      if (chord) return KeyEventResult.ignored;
      if (!_canContinue) return KeyEventResult.ignored;
      unawaited(_continueToCaptionStep());
      return KeyEventResult.handled;
    }

    // Step 3: ⌘/Ctrl+Enter starts the session.
    if (!chord) return KeyEventResult.ignored;
    if (!_canGo) return KeyEventResult.ignored;
    unawaited(_goTime());
    return KeyEventResult.handled;
  }

  List<String> _sortedTeams({String? exclude}) {
    final favs = _favoriteTeamNames;
    final excluded = exclude?.trim();
    final list = _teams
        .where((t) => excluded == null || excluded.isEmpty || t != excluded)
        .toList();
    list.sort((a, b) {
      final af = favs.contains(a);
      final bf = favs.contains(b);
      if (af != bf) return af ? -1 : 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }

  void _setAwayTeam(String? team) {
    final wasUnlocked = _postTeamsUnlocked;
    setState(() {
      _usingCustomRosters = false;
      _awayTeam = team;
      if (team != null && team == _homeTeam) {
        _homeTeam = null;
      }
      _homeRoster = null;
      _awayRoster = null;
      _captionPreviewPlayers = const [];
      _previewHomeVenue = null;
      if (!_postTeamsUnlocked) _iptcOpenedForStyleToken = null;
    });
    unawaited(_refreshCaptionPreviewPlayers());
    _onCaptionStepUnlocked(wasUnlocked: wasUnlocked);
  }

  void _setHomeTeam(String? team) {
    final wasUnlocked = _postTeamsUnlocked;
    setState(() {
      _usingCustomRosters = false;
      _homeTeam = team;
      if (team != null && team == _awayTeam) {
        _awayTeam = null;
      }
      _homeRoster = null;
      _awayRoster = null;
      _captionPreviewPlayers = const [];
      _previewHomeVenue = null;
      if (!_postTeamsUnlocked) _iptcOpenedForStyleToken = null;
    });
    unawaited(_refreshCaptionPreviewPlayers());
    _onCaptionStepUnlocked(wasUnlocked: wasUnlocked);
  }

  Future<void> _refreshCaptionPreviewPlayers() async {
    final home = _homeFilled ? _homeTeam!.trim() : null;
    final away = _awayFilled ? _awayTeam!.trim() : null;
    if (home == null && away == null) {
      if (!mounted) return;
      setState(() {
        _captionPreviewPlayers = const [];
        _previewHomeVenue = null;
      });
      return;
    }
    final gen = ++_captionPreviewRosterGen;
    final sport = _sport;
    if (sport == null || sport.isEmpty) return;

    CaptionPreviewPlayer? toPreview(Player p, String team, String opp) {
      final rawNum = (p.jerseyNumber ?? '').trim();
      final number =
          int.tryParse(rawNum.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final position = (p.position ?? '').trim();
      var name = p.fullName.trim();
      if (name.isEmpty) {
        name = p.displayName.trim().replaceAll(RegExp(r'\s*#\d+\s*$'), '');
      }
      if (name.isEmpty) return null;
      if (name.toLowerCase() == team.toLowerCase()) return null;
      return CaptionPreviewPlayer(
        team,
        position.isEmpty ? 'P' : position,
        name,
        number,
        opp,
      );
    }

    final out = <CaptionPreviewPlayer>[];
    String? homeVenue;
    try {
      _api.setSport(sport);
      if (home != null) {
        try {
          final team = await _api.findTeamByName(home);
          final venue = team?.venueName?.trim();
          if (venue != null && venue.isNotEmpty) {
            homeVenue = venue;
          } else {
            homeVenue = await _api.fetchVenueForTeam(home);
          }
        } catch (_) {}
      }
      if (_usingCustomRosters) {
        for (final p in _homeRoster ?? const <Player>[]) {
          if (home == null) continue;
          final preview = toPreview(p, home, away ?? '');
          if (preview != null) out.add(preview);
        }
        for (final p in _awayRoster ?? const <Player>[]) {
          if (away == null) continue;
          final preview = toPreview(p, away, home ?? '');
          if (preview != null) out.add(preview);
        }
      } else {
        if (home != null) {
          final roster = await _api.fetchTeamRoster(home);
          for (final p in roster) {
            final preview = toPreview(p, home, away ?? '');
            if (preview != null) out.add(preview);
          }
        }
        if (away != null && away != home) {
          final roster = await _api.fetchTeamRoster(away);
          for (final p in roster) {
            final preview = toPreview(p, away, home ?? '');
            if (preview != null) out.add(preview);
          }
        }
      }
    } catch (e) {
      debugPrint('Caption preview roster failed: $e');
    }
    if (!mounted || gen != _captionPreviewRosterGen) return;
    setState(() {
      _captionPreviewPlayers = out;
      if (homeVenue != null && homeVenue.trim().isNotEmpty) {
        _previewHomeVenue = homeVenue.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final stackTeams =
        MediaQuery.sizeOf(context).width <= 620;

    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: FfTokens.sessionBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = math.min(_stageWidth, constraints.maxWidth);
                    final h = math.min(_stageHeight, constraints.maxHeight);
                    return Center(
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: FfTokens.sessionPanel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: FfTokens.sessionLn),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: switch (_setupStep) {
                              1 => _buildV5WireStep(),
                              2 => _buildV5SetupPanel(
                                  stackTeams: stackTeams,
                                ),
                              _ => _buildV5CaptionStep(t),
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                child: Text(
                  _error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    color: FfTokens.danger,
                  ),
                ),
              ),
            _buildV5Footer(t),
          ],
        ),
      ),
    );
  }

  Widget _buildV5CaptionStep(FfTokens t) {
    // Fills the shared stage frame so Structure / Player Output get height.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildV5SummaryStrip(),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: AdminService.previewAsNonAdmin,
              builder: (context, _, __) {
                final showAdminSave =
                    AdminService.isCurrentUserAdminSync();
                return _buildV4CaptionCard(showAdminSave: showAdminSave);
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSessionStep(t, compact: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _buildStepBackButton(
              onPressed: _going ? null : () => _showSetupStep(2),
            ),
          ),
        ],
      ),
    );
  }

  /// Step 1 — pick the wire before IPTC / teams / caption layout.
  Widget _buildV5WireStep() {
    final options = _wireStepOptions;
    final selected = _selectedStyleToken;
    final current = options.any((o) => o.$1 == selected)
        ? selected
        : (options.isNotEmpty ? options.first.$1 : null);

    IconData iconFor(String token) {
      switch (token) {
        case CaptionStyleCatalog.tokImagn:
          return PhosphorIconsRegular.camera;
        case CaptionStyleCatalog.tokAp:
          return PhosphorIconsRegular.broadcast;
        case CaptionStyleCatalog.tokCp:
          return PhosphorIconsRegular.flag;
        case CaptionStyleCatalog.tokGettyIntl:
          return PhosphorIconsRegular.globeHemisphereWest;
        case CaptionStyleCatalog.tokGetty:
        default:
          return PhosphorIconsRegular.newspaper;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          const Text(
            'Choose your wire',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: FfTokens.sessionTx,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This sets the caption layout and IPTC fields for the session.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              color: FfTokens.sessionT2,
            ),
          ),
          const SizedBox(height: 36),
          if (_loadingStyles)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Row(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _Pressable(
                          height: 132,
                          radius: 12,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          color: options[i].$1 == current
                              ? FfTokens.nocturneAccentSoft
                              : FfTokens.nocturneSf,
                          borderColor: options[i].$1 == current
                              ? FfTokens.nocturneAccentEdge
                              : FfTokens.sessionLn,
                          borderWidth: options[i].$1 == current ? 1.4 : 1,
                          hoverColor: FfTokens.sessionHv,
                          onPressed: () =>
                              unawaited(_selectStyle(options[i].$1)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PhosphorIcon(
                                iconFor(options[i].$1),
                                size: 28,
                                color: options[i].$1 == current
                                    ? FfTokens.nocturneAc
                                    : FfTokens.sessionT2,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                options[i].$2,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: options[i].$1 == current
                                      ? FfTokens.sessionTx
                                      : FfTokens.sessionT2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const Spacer(flex: 3),
          Align(
            alignment: Alignment.centerRight,
            child: _GoTimeButton(
              enabled: _canContinueFromWire,
              loading: false,
              compact: false,
              label: 'Continue',
              shortcut: '↵',
              onPressed: () => unawaited(_continueFromWire()),
            ),
          ),
        ],
      ),
    );
  }

  /// Step 2 — setup panel (Images / IPTC / League / Teams).
  Widget _buildV5SetupPanel({required bool stackTeams}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            // Images + League + Teams on one row.
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: FfTokens.sessionLn),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Images', style: _kSectionLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 280,
                    child: _buildV5ImagesField(),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 52,
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('League', style: _kSectionLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 180,
                    child: _setupGate(
                      unlocked: _leagueUnlocked,
                      child: _buildV5LeagueField(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 48,
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Teams', style: _kSectionLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _setupGate(
                      unlocked: _teamsUnlocked,
                      child: _buildV5TeamsField(stack: false),
                    ),
                  ),
                ],
              ),
            ),
            // IPTC template only after both teams are chosen.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: _bothTeamsChosen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('IPTC', style: _kSectionLabel),
                          const SizedBox(height: 6),
                          Expanded(child: _buildV5IptcSourceField()),
                        ],
                      )
                    : const Center(
                        child: Text(
                          'Select away and home teams to set up IPTC',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: FfTokens.sessionT3,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Row(
                children: [
                  _buildStepBackButton(
                    onPressed: () => _showSetupStep(1),
                  ),
                  const Spacer(),
                  _GoTimeButton(
                    enabled: _canContinue,
                    loading: false,
                    compact: false,
                    label: 'Continue',
                    shortcut: '↵',
                    onPressed: () => unawaited(_continueToCaptionStep()),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildStepBackButton({required VoidCallback? onPressed}) {
    return _Pressable(
      height: 38,
      radius: 9,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.transparent,
      hoverColor: onPressed == null ? Colors.transparent : FfTokens.sessionHv,
      hoverForeground: onPressed != null,
      foreground: onPressed == null
          ? FfTokens.sessionT3.withValues(alpha: 0.35)
          : FfTokens.sessionT2,
      onPressed: onPressed,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(PhosphorIconsRegular.arrowLeft, size: 15),
          SizedBox(width: 8),
          Text(
            'Back',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 8),
          _KbdHint('Esc'),
        ],
      ),
    );
  }

  Widget _buildV5SetupRow({
    required String label,
    required Widget child,
    bool showDivider = true,
    double topPadding = 14,
    double bottomPadding = 14,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, topPadding, 10, bottomPadding),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FfTokens.sessionLn),
              ),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 520;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: _kSectionLabel),
                const SizedBox(height: 6),
                child,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: _kSectionLabel),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: child),
            ],
          );
        },
      ),
    );
  }

  Widget _buildV4FieldHeader({
    required String label,
    Widget? trailing,
  }) {
    // Fixed height so Images / League / Teams boxes stay aligned even when
    // a column has no trailing control (e.g. Images has no Change link).
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Text(label, style: _kSectionLabel),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildV4LinkButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return _Pressable(
      height: 24,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.transparent,
      hoverColor: FfTokens.sessionHv,
      hoverForeground: true,
      foreground: FfTokens.sessionT3,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(icon, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildV5ImagesField() {
    final chosen = _folderChosen;
    final title = chosen ? p.basename(_folderPath!) : 'Choose a folder…';
    final subtitle = chosen
        ? (_imageCount == 1 ? '1 photo' : '$_imageCount photos')
        : '';
    return DropTarget(
      onDragEntered: (_) => setState(() => _folderDragOver = true),
      onDragExited: (_) => setState(() => _folderDragOver = false),
      onDragDone: _onFolderDropped,
      child: _Pressable(
        height: 40,
        radius: 9,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: _folderDragOver
            ? FfTokens.sessionOnSoft
            : FfTokens.sessionEl,
        hoverColor: FfTokens.sessionHv,
        borderColor: _folderDragOver ? FfTokens.sessionOn : Colors.transparent,
        borderWidth: _folderDragOver ? 1 : 0,
        onPressed: _pickingFolder ? null : _pickFolder,
        child: Row(
          children: [
            PhosphorIcon(
              chosen
                  ? PhosphorIconsRegular.folder
                  : PhosphorIconsRegular.folderSimpleDashed,
              size: 17,
              color: FfTokens.sessionT3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _pickingFolder ? 'Opening…' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 14,
                  fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                  color: chosen ? FfTokens.sessionTx : FfTokens.sessionT3,
                ),
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: FfTokens.sessionT3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _persistInlineIptcTemplate() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final wire = _iptcInlineWire;
    final preset = IptcTemplateApplyService.normalizeForPreset(
      _iptcValuesFromTemplate,
      includeInAppGenerated: true,
    );
    await prefs.saveIptcWirePreset(wire, preset: preset);
    if (!mounted) return;
    setState(() {
      final preview = Map<String, String>.from(_iptcValuesFromFiles);
      for (final e in _iptcValuesFromTemplate.entries) {
        final trimmed = e.value.trim();
        if (trimmed.isEmpty) continue;
        if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
          continue;
        }
        preview[e.key] = trimmed;
      }
      _iptcPanelForPreview = preview;
    });
  }

  void _onInlineIptcValueChanged(String storageKey, String value) {
    if (_iptcSource == _IptcSourceMode.files) return;
    setState(() {
      final next = Map<String, String>.from(_iptcValuesFromTemplate);
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        next.remove(storageKey);
      } else {
        next[storageKey] = value;
      }
      _iptcValuesFromTemplate = next;
      _iptcInlineRevision++;
    });
    unawaited(_persistInlineIptcTemplate());
  }

  void _clearInlineIptcTemplate() {
    if (_iptcSource == _IptcSourceMode.files) return;
    setState(() {
      _iptcValuesFromTemplate = const {};
      _iptcInlineRevision++;
    });
    unawaited(_persistInlineIptcTemplate());
  }

  /// Values shown in the inline IPTC builder — always seeded from folder files.
  Map<String, String> get _inlineIptcDisplayValues {
    final files = _iptcValuesFromFiles;
    final template = _iptcValuesFromTemplate;
    switch (_iptcSource) {
      case _IptcSourceMode.files:
        return files;
      case _IptcSourceMode.fill:
        // Keep file values; template only fills blanks.
        final out = Map<String, String>.from(files);
        for (final e in template.entries) {
          final trimmed = e.value.trim();
          if (trimmed.isEmpty) continue;
          if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
            continue;
          }
          out.putIfAbsent(e.key, () => e.value);
        }
        return out;
      case _IptcSourceMode.apply:
        // Start from files so the pad shows what's already there, then
        // overlay template values that will be written.
        final out = Map<String, String>.from(files);
        for (final e in template.entries) {
          final trimmed = e.value.trim();
          if (trimmed.isEmpty) continue;
          if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
            continue;
          }
          out[e.key] = e.value;
        }
        return out;
    }
  }

  Widget _buildV5InlineIptcMenu() {
    final source = _iptcSource;
    final fromFiles = source == _IptcSourceMode.files;
    final onTemplate = !fromFiles;
    final values = _inlineIptcDisplayValues;
    final scanning = _folderChosen && _scanningIptc;
    final styleLabel = _styleCatalog == null
        ? 'IPTC template'
        : _styleCatalog!.labelFor(
            _selectedStyleToken ?? _styleCatalog!.activeToken,
          );
    final title = fromFiles
        ? 'From files'
        : 'TEMPLATE PAGE';
    final subtitle = fromFiles
        ? 'Read-only values from folder photos'
        : (source == _IptcSourceMode.fill
            ? 'This template fills empty IPTC fields on incoming files'
            : 'This template will overwrite all IPTC on incoming files');

    return Container(
      decoration: BoxDecoration(
        color: onTemplate ? FfTokens.nocturneAccentSoft : FfTokens.nocturneSf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTemplate ? FfTokens.nocturneAccentEdge : FfTokens.sessionLn,
          width: onTemplate ? 1.2 : 1,
        ),
        boxShadow: onTemplate
            ? FfTokens.accentButtonGlow(FfTokens.nocturneAc)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: !_folderChosen
          ? const Center(
              child: Text(
                'Choose a folder to see IPTC fields.',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  color: FfTokens.sessionT3,
                ),
              ),
            )
          : scanning
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IptcTemplateEditor(
                  key: ValueKey(
                    'inline-iptc-$_iptcInlineRevision-${_iptcInlineWire.name}-$source',
                  ),
                  wire: _iptcInlineWire,
                  templates: const [],
                  selectedTemplateId: '',
                  values: values,
                  foundInFilesKeys: _iptcKeysFoundInFiles,
                  revision: _iptcInlineRevision,
                  fieldsEnabled: onTemplate,
                  onTemplateSelected: (_) {},
                  onValueChanged: fromFiles
                      ? (_, __) {}
                      : _onInlineIptcValueChanged,
                  onLoadTemplate: null,
                  onClearTemplate:
                      fromFiles ? null : _clearInlineIptcTemplate,
                  onSaveTemplate: null,
                  loadEnabled: false,
                  clearEnabled: onTemplate,
                  embedded: true,
                  showTemplateControls: false,
                  templatePageHeader: onTemplate,
                  title: title,
                  subtitle: subtitle,
                  captionTemplate: _captionTemplate,
                  captionStyleLabel: styleLabel,
                  onCancel: () {},
                  onDone: () {},
                ),
    );
  }

  Widget _buildV5IptcSourceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _V5Segmented<_IptcSourceMode>(
          value: _iptcSource,
          onChanged: (next) => unawaited(_setIptcSource(next)),
          options: const [
            (_IptcSourceMode.apply, 'Apply my template'),
            (_IptcSourceMode.fill, 'Fill missing IPTC'),
            (_IptcSourceMode.files, 'Already in files'),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildV5InlineIptcMenu()),
      ],
    );
  }

  Widget _buildV5LeagueField() {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminService.previewAsNonAdmin,
      builder: (context, _, __) {
        return _SessionSelect(
          value: _sport,
          hint: _leagueUnlocked ? 'Select league' : 'Pick a folder first',
          enabled: _leagueUnlocked,
          height: 40,
          fontSize: 14,
          leading: PhosphorIcon(
            _sportIcon(_sport),
            size: 17,
            color: FfTokens.sessionT3,
          ),
          options: [
            for (final sport in _sports) (sport, _leagueLabel(sport)),
          ],
          onChanged: _selectSport,
        );
      },
    );
  }

  Widget _buildV5TeamsField({required bool stack}) {
    final away = _TeamDropdown(
      menuId: 0,
      openMenuId: _openMenuId,
      label: 'Away',
      value: _awayTeam,
      teams: _sortedTeams(exclude: _homeTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteAway,
      favoriteNames: _favoriteTeamNames,
      focusNode: _awayFocus,
      hideLabel: true,
      fieldHeight: 40,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select team' : 'Pick a league first'),
      onChanged: _setAwayTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: false)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 0 : (_openMenuId == 0 ? null : _openMenuId);
      }),
    );
    final home = _TeamDropdown(
      menuId: 1,
      openMenuId: _openMenuId,
      label: 'Home',
      value: _homeTeam,
      teams: _sortedTeams(exclude: _awayTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteHome,
      favoriteNames: _favoriteTeamNames,
      focusNode: _homeFocus,
      hideLabel: true,
      fieldHeight: 40,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select team' : 'Pick a league first'),
      onChanged: _setHomeTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: true)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 1 : (_openMenuId == 1 ? null : _openMenuId);
      }),
    );
    final swap = _Pressable(
      height: 32,
      width: 32,
      radius: 8,
      padding: EdgeInsets.zero,
      color: Colors.transparent,
      hoverColor: FfTokens.sessionHv,
      onPressed: _teamsUnlocked ? _swapTeams : null,
      child: PhosphorIcon(
        PhosphorIconsRegular.arrowsLeftRight,
        size: 16,
        color: FfTokens.sessionT3,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stack)
          Column(
            children: [
              away,
              const SizedBox(height: 6),
              Transform.rotate(angle: 1.5708, child: swap),
              const SizedBox(height: 6),
              home,
            ],
          )
        else
          Row(
            children: [
              Expanded(child: away),
              const SizedBox(width: 6),
              swap,
              const SizedBox(width: 6),
              Expanded(child: home),
            ],
          ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Text(
              'Away',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: FfTokens.sessionT3,
              ),
            ),
            Spacer(),
            Text(
              'Home',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: FfTokens.sessionT3,
              ),
            ),
          ],
        ),
        if (_loadingTeams && availableTeamsEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Loading team list…',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildV5SummaryStrip() {
    final folderName =
        _folderChosen ? p.basename(_folderPath!) : 'No folder';
    final countLabel =
        _imageCount == 1 ? '1' : '$_imageCount';
    final srcLabel = switch (_iptcSource) {
      _IptcSourceMode.apply => 'My template',
      _IptcSourceMode.fill => 'Fill missing',
      _IptcSourceMode.files => 'From files',
    };
    final iptcDot = _iptcSource != _IptcSourceMode.files &&
            _hasIptcFieldWarnings
        ? FfTokens.sessionWarn
        : FfTokens.sessionOk;
    final awayAbbr = mlbTeamAbbreviation(_awayTeam ?? '');
    final homeAbbr = mlbTeamAbbreviation(_homeTeam ?? '');
    final venue = (_previewHomeVenue ?? '').trim();

    Widget chip({
      required String focus,
      required Widget child,
      int step = 2,
    }) {
      return _Pressable(
        height: 32,
        radius: 8,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.transparent,
        hoverColor: FfTokens.sessionHv,
        onPressed: () => _showSetupStep(step, focus: focus),
        child: child,
      );
    }

    Widget divider() => Container(
          width: 1,
          height: 18,
          color: FfTokens.sessionLn,
        );

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FfTokens.sessionPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip(
            focus: 'wire',
            step: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(
                  PhosphorIconsRegular.newspaper,
                  size: 15,
                  color: FfTokens.sessionT3,
                ),
                const SizedBox(width: 7),
                Text(
                  _selectedWireLabel,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
              ],
            ),
          ),
          divider(),
          chip(
            focus: 'folder',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(
                  PhosphorIconsRegular.folder,
                  size: 15,
                  color: FfTokens.sessionT3,
                ),
                const SizedBox(width: 7),
                Text(
                  folderName,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  countLabel,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FfTokens.sessionT3,
                  ),
                ),
              ],
            ),
          ),
          divider(),
          chip(
            focus: 'src',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: iptcDot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'IPTC',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  srcLabel,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FfTokens.sessionT3,
                  ),
                ),
              ],
            ),
          ),
          divider(),
          chip(
            focus: 'league',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  _sportIcon(_sport),
                  size: 15,
                  color: FfTokens.sessionT3,
                ),
                const SizedBox(width: 7),
                Text(
                  _sportChosen ? _leagueLabel(_sport!) : 'League',
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
              ],
            ),
          ),
          divider(),
          chip(
            focus: 'away',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  awayAbbr.isEmpty ? '—' : awayAbbr,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'at',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FfTokens.sessionT3,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  homeAbbr.isEmpty ? '—' : homeAbbr,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
                if (venue.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    venue,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: FfTokens.sessionT3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Pressable(
            height: 32,
            radius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.transparent,
            hoverColor: FfTokens.sessionHv,
            hoverForeground: true,
            foreground: FfTokens.sessionT2,
            onPressed: () => _showSetupStep(2),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(PhosphorIconsRegular.pencilSimple, size: 14),
                SizedBox(width: 6),
                Text(
                  'Edit setup',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                _KbdHint('Esc'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Legacy v4 images field kept for older step builders still in this file.
  Widget _buildV4ImagesField() {
    final chosen = _folderChosen;
    final title = chosen ? p.basename(_folderPath!) : 'Drop a folder here';
    final subtitle = chosen
        ? (_imageCount == 1 ? '1 photo' : '$_imageCount photos')
        : 'Choose a folder';
    const captionWarn = FfTokens.danger;
    const filingWarn = _filingWarnColor;
    final showIptcTip = chosen && !_pickingFolder && !_scanningIptc;
    final iptcNeedsAdd = showIptcTip && _hasIptcFieldWarnings;
    final iptcComplete = showIptcTip && _iptcComplete;
    return DropTarget(
      onDragEntered: (_) => setState(() => _folderDragOver = true),
      onDragExited: (_) => setState(() => _folderDragOver = false),
      onDragDone: _onFolderDropped,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildV4FieldHeader(label: 'Images'),
          const SizedBox(height: 6),
          _Pressable(
            height: 38,
            radius: 9,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: _folderDragOver
                ? FfTokens.sessionOnSoft
                : FfTokens.sessionEl,
            hoverColor: FfTokens.sessionHv,
            borderColor: _folderDragOver
                ? FfTokens.sessionOn
                : Colors.transparent,
            borderWidth: _folderDragOver ? 1 : 0,
            onPressed: _pickingFolder ? null : _pickFolder,
            child: Row(
              children: [
                PhosphorIcon(
                  chosen
                      ? PhosphorIconsRegular.folder
                      : PhosphorIconsRegular.folderSimpleDashed,
                  size: 16,
                  color: FfTokens.sessionT3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: chosen
                          ? FfTokens.sessionTx
                          : FfTokens.sessionT3,
                    ),
                  ),
                ),
                if (_iptcAppliedElsewhere && showIptcTip) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Applied elsewhere',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      color: FfTokens.sessionT2,
                    ),
                  ),
                ] else if (iptcNeedsAdd) ...[
                  const SizedBox(width: 8),
                  _MissingFieldsLink(
                    label: 'Missing fields',
                    color: _missingCaptionIptc.isNotEmpty
                        ? captionWarn
                        : filingWarn,
                    onTap: () => unawaited(_openIptcForMissingFields()),
                  ),
                ] else if (iptcComplete) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Enough existing IPTC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      height: 1.1,
                      color: FfTokens.sessionOk,
                    ),
                  ),
                ] else if (chosen && _scanningIptc) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  _pickingFolder ? 'Opening…' : subtitle,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FfTokens.sessionT3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _buildImagesIptcStrip(),
        ],
      ),
    );
  }

  Widget _buildImagesIptcStrip() {
    final enabled = _folderChosen;
    final complete = _iptcComplete;
    final scanning = enabled && _scanningIptc;
    final needsAdd = enabled && !scanning && _hasIptcFieldWarnings;
    const captionWarn = FfTokens.danger;
    const filingWarn = _filingWarnColor;
    final elsewhere = _iptcAppliedElsewhere;

    final Widget statusIcon;
    if (!enabled) {
      statusIcon = const PhosphorIcon(
        PhosphorIconsRegular.tag,
        size: 15,
        color: FfTokens.sessionT3,
      );
    } else if (scanning) {
      statusIcon = const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    } else if (elsewhere || complete) {
      statusIcon = PhosphorIcon(
        elsewhere
            ? PhosphorIconsRegular.arrowSquareOut
            : PhosphorIconsFill.checkCircle,
        size: 15,
        color: elsewhere ? FfTokens.sessionT2 : FfTokens.sessionOk,
      );
    } else {
      statusIcon = PhosphorIcon(
        PhosphorIconsFill.warningCircle,
        size: 15,
        color: _missingCaptionIptc.isNotEmpty ? captionWarn : filingWarn,
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: complete && !elsewhere
              ? FfTokens.nocturneAccentRow
              : FfTokens.sessionEl,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: complete && !elsewhere
                ? FfTokens.nocturneAccentEdge
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            statusIcon,
            const SizedBox(width: 7),
            const Text(
              'IPTC',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: FfTokens.sessionTx,
              ),
            ),
            const Spacer(),
            Tooltip(
              message:
                  'IPTC will be applied outside FloFile — start without writing IPTC',
              waitDuration: const Duration(milliseconds: 350),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Applied elsewhere',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? (elsewhere
                              ? FfTokens.sessionTx
                              : FfTokens.sessionT2)
                          : FfTokens.sessionT3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SessionSwitch(
                    value: elsewhere,
                    onChanged: enabled
                        ? (next) => unawaited(_setIptcAppliedElsewhere(next))
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Apply on ingest',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled && !elsewhere
                    ? FfTokens.sessionT2
                    : FfTokens.sessionT3,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Write the IPTC template onto photos when the session opens',
              waitDuration: const Duration(milliseconds: 350),
              child: _SessionSwitch(
                value: !elsewhere && _iptcMode.appliesOnLoad,
                onChanged: enabled && !elsewhere
                    ? (next) => unawaited(_setApplyIptcOnIngest(next))
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            _SessionOptionAction(
              label: 'Edit',
              icon: PhosphorIconsRegular.pencilSimple,
              onPressed: enabled
                  ? () => unawaited(
                        needsAdd
                            ? _openIptcForMissingFields()
                            : _openIptc(),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildV4LeagueField() {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminService.previewAsNonAdmin,
      builder: (context, _, __) {
        final showApi = AdminService.isCurrentUserAdminSync() &&
            _sport != 'soccer';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildV4FieldHeader(
              label: 'League',
              trailing: showApi
                  ? _buildV4LinkButton(
                      icon: PhosphorIconsRegular.plug,
                      label: (!_tank01Supported || _useOfficialLeagueApis)
                          ? 'Official'
                          : 'Tank01',
                      onPressed: !_sportChosen || !_tank01Supported
                          ? null
                          : () => _setUseOfficialLeagueApis(
                                !_useOfficialLeagueApis,
                              ),
                    )
                  : (_sport == 'soccer'
                      ? const Text(
                          'ESPN MLS',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: FfTokens.sessionT3,
                          ),
                        )
                      : null),
            ),
            const SizedBox(height: 6),
            _SessionSelect(
              value: _sport,
              hint: _leagueUnlocked
                  ? 'Select league'
                  : 'Pick a folder first',
              enabled: _leagueUnlocked,
              height: 38,
              fontSize: 13,
              leading: PhosphorIcon(
                _sportIcon(_sport),
                size: 16,
                color: FfTokens.sessionT3,
              ),
              options: [
                for (final sport in _sports) (sport, _leagueLabel(sport)),
              ],
              onChanged: _selectSport,
            ),
          ],
        );
      },
    );
  }

  Widget _buildV4TeamsField({required bool stack}) {
    final away = _TeamDropdown(
      menuId: 0,
      openMenuId: _openMenuId,
      label: 'Away',
      value: _awayTeam,
      teams: _sortedTeams(exclude: _homeTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteAway,
      favoriteNames: _favoriteTeamNames,
      focusNode: _awayFocus,
      hideLabel: true,
      fieldHeight: 38,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select away team' : 'Pick a league first'),
      onChanged: _setAwayTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: false)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 0 : (_openMenuId == 0 ? null : _openMenuId);
      }),
    );
    final home = _TeamDropdown(
      menuId: 1,
      openMenuId: _openMenuId,
      label: 'Home',
      value: _homeTeam,
      teams: _sortedTeams(exclude: _awayTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteHome,
      favoriteNames: _favoriteTeamNames,
      focusNode: _homeFocus,
      hideLabel: true,
      fieldHeight: 38,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select home team' : 'Pick a league first'),
      onChanged: _setHomeTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: true)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 1 : (_openMenuId == 1 ? null : _openMenuId);
      }),
    );
    final pastedCount =
        (_awayRoster?.length ?? 0) + (_homeRoster?.length ?? 0);
    final customRosters = _buildV4LinkButton(
      icon: PhosphorIconsRegular.clipboardText,
      label: _usingCustomRosters && pastedCount > 0
          ? 'Custom rosters ($pastedCount)'
          : 'Custom rosters',
      onPressed: _sportChosen ? _pasteRoster : null,
    );
    final swap = _Pressable(
      height: 38,
      radius: 8,
      padding: EdgeInsets.zero,
      color: Colors.transparent,
      hoverColor: FfTokens.sessionHv,
      onPressed: _teamsUnlocked ? _swapTeams : null,
      child: const SizedBox(
        width: 30,
        child: PhosphorIcon(
          PhosphorIconsRegular.arrowsLeftRight,
          size: 15,
          color: FfTokens.sessionT3,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildV4FieldHeader(
          label: 'Away  ·  Home',
          trailing: customRosters,
        ),
        const SizedBox(height: 6),
        if (stack)
          Column(
            children: [
              away,
              const SizedBox(height: 6),
              home,
            ],
          )
        else
          Row(
            children: [
              Expanded(child: away),
              swap,
              Expanded(child: home),
            ],
          ),
        if (_loadingTeams && availableTeamsEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Loading team list…',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
      ],
    );
  }

  /// v4: Caption card — wire segments + colour code + shuffle over structure.
  Widget _buildV4CaptionCard({required bool showAdminSave}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: FfTokens.sessionPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildV4CaptionHeader(showAdminSave: showAdminSave),
          const SizedBox(height: 12),
          Expanded(
            child: _buildEmbeddedCaptionBuilder(showAdminSave: false),
          ),
        ],
      ),
    );
  }

  Widget _buildV4CaptionHeader({required bool showAdminSave}) {
    final catalog = _styleCatalog;
    final tokens = <String>[
      if (catalog != null)
        for (final option in catalog.options)
          if (!CaptionStyleCatalog.isCustomMenuToken(option.token))
            option.token,
    ];
    final current = tokens.contains(_selectedStyleToken)
        ? _selectedStyleToken
        : (tokens.isNotEmpty ? tokens.first : null);
    final colorOn =
        _captionBuilderKey.currentState?.structurePreviewColorCode ?? false;
    final structureDirty =
        _captionBuilderKey.currentState?.structureEditorDirty ?? false;
    final showSave = showAdminSave && structureDirty;

    return Row(
      children: [
        const Text(
          'Caption',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: FfTokens.sessionTx,
          ),
        ),
        const SizedBox(width: 10),
        // Must be Expanded — _V5Segmented uses Expanded chips and cannot
        // sit loose in a Row (unbounded width collapses the caption header).
        if (tokens.isNotEmpty)
          Expanded(
            child: _V5Segmented<String>(
              value: current ?? tokens.first,
              small: true,
              onChanged: (token) => unawaited(_selectStyle(token)),
              options: [
                for (final token in tokens) (token, catalog!.labelFor(token)),
              ],
            ),
          )
        else
          const Spacer(),
        if (showSave)
          _Pressable(
            height: 32,
            radius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.transparent,
            hoverColor: FfTokens.sessionHv,
            hoverForeground: true,
            foreground: FfTokens.accentHover,
            onPressed: _savingCaptionDefault
                ? null
                : () => unawaited(_saveCaptionStyleAsFirebaseDefault()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(PhosphorIconsRegular.floppyDisk, size: 15),
                const SizedBox(width: 6),
                Text(
                  _savingCaptionDefault ? 'Saving…' : 'Save as default',
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (showSave) const SizedBox(width: 4),
        Tooltip(
          message: 'Colour code',
          waitDuration: const Duration(milliseconds: 350),
          child: _Pressable(
            height: 32,
            width: 32,
            radius: 8,
            padding: EdgeInsets.zero,
            color: colorOn ? FfTokens.nocturneAccentSoft : Colors.transparent,
            borderColor:
                colorOn ? FfTokens.nocturneAccentEdge : Colors.transparent,
            borderWidth: colorOn ? 1 : 0,
            hoverColor: FfTokens.sessionHv,
            hoverForeground: true,
            foreground: colorOn ? FfTokens.sessionTx : FfTokens.sessionT2,
            onPressed: () {
              _captionBuilderKey.currentState
                  ?.toggleStructurePreviewColorCode();
              setState(() {});
            },
            child: const PhosphorIcon(PhosphorIconsRegular.palette, size: 15),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Shuffle sample',
          waitDuration: const Duration(milliseconds: 350),
          child: _Pressable(
            height: 32,
            width: 32,
            radius: 8,
            padding: EdgeInsets.zero,
            color: Colors.transparent,
            hoverColor: FfTokens.sessionHv,
            hoverForeground: true,
            foreground: FfTokens.sessionT2,
            onPressed: () {
              _captionBuilderKey.currentState?.shuffleCaptionSample();
              setState(() {});
            },
            child: const PhosphorIcon(PhosphorIconsRegular.shuffle, size: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderStep(
    FfTokens t, {
    required bool compact,
  }) {
    final chosen = _folderChosen;
    final title = chosen ? p.basename(_folderPath!) : 'Drop a folder here';
    final subtitle = chosen
        ? (_imageCount == 1 ? '1 image' : '$_imageCount images')
        : 'or choose one from your computer';
    return DropTarget(
      onDragEntered: (_) => setState(() => _folderDragOver = true),
      onDragExited: (_) => setState(() => _folderDragOver = false),
      onDragDone: _onFolderDropped,
      child: _StepCard(
        number: 1,
        title: 'Images folder',
        complete: chosen,
        compact: compact,
        highlighted: _folderDragOver,
        child: _FolderDropRow(
          empty: !chosen,
          emphasized: _folderDragOver,
          compact: compact,
          icon: chosen
              ? PhosphorIconsRegular.folderSimple
              : PhosphorIconsRegular.folderSimpleDashed,
          title: title,
          subtitle: subtitle,
          buttonLabel: _pickingFolder
              ? 'Opening…'
              : (chosen ? 'Change' : 'Choose folder'),
          onPressed: _pickingFolder ? null : _pickFolder,
        ),
      ),
    );
  }

  Widget _buildSportStep(
    FfTokens t, {
    required bool compact,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminService.previewAsNonAdmin,
      builder: (context, _, __) {
        final soccerNote = _sport == 'soccer'
            ? const Text(
                'Always use ESPN MLS rosters for soccer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  color: FfTokens.sessionT3,
                ),
              )
            : null;
        // Tank01 vs official league APIs — admin accounts only.
        final apiChoice = AdminService.isCurrentUserAdminSync() &&
                soccerNote == null
            ? _AttachedChoice(
                expand: true,
                enabled: _sportChosen && _tank01Supported,
                selected:
                    (!_tank01Supported || _useOfficialLeagueApis) ? 1 : 0,
                options: const ['Tank01 APIs', 'Official league APIs'],
                onSelected: (index) => _setUseOfficialLeagueApis(index == 1),
              )
            : null;
        return _StepCard(
          number: 2,
          title: 'League',
          // Saved/favorite league may already be set, but don't show a check
          // until this step is unlocked (folder chosen).
          complete: _leagueUnlocked && _sportChosen,
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionSelect(
                value: _sport,
                hint: _leagueUnlocked
                    ? 'Select league'
                    : 'Pick a folder first',
                enabled: _leagueUnlocked,
                leading: PhosphorIcon(
                  _sportIcon(_sport),
                  size: 16,
                  color: FfTokens.sessionT3,
                ),
                options: [
                  for (final sport in _sports) (sport, _leagueLabel(sport)),
                ],
                onChanged: _selectSport,
              ),
              if (apiChoice != null) ...[
                SizedBox(height: compact ? 6 : 8),
                apiChoice,
              ],
              if (soccerNote != null) ...[
                SizedBox(height: compact ? 6 : 8),
                soccerNote,
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamsStepCard(
    FfTokens t, {
    required bool stack,
    required bool compact,
  }) {
    final away = _TeamDropdown(
      menuId: 0,
      openMenuId: _openMenuId,
      label: 'Away',
      value: _awayTeam,
      teams: _sortedTeams(exclude: _homeTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteAway,
      favoriteNames: _favoriteTeamNames,
      focusNode: _awayFocus,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select away team' : 'Pick a league first'),
      onChanged: _setAwayTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: false)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 0 : (_openMenuId == 0 ? null : _openMenuId);
      }),
    );
    final home = _TeamDropdown(
      menuId: 1,
      openMenuId: _openMenuId,
      label: 'Home',
      value: _homeTeam,
      teams: _sortedTeams(exclude: _awayTeam),
      enabled: _teamsUnlocked && !_loadingTeams,
      sideFavorite: _favoriteHome,
      favoriteNames: _favoriteTeamNames,
      focusNode: _homeFocus,
      hintText: !_folderChosen
          ? 'Pick a folder first'
          : (_sportChosen ? 'Select home team' : 'Pick a league first'),
      onChanged: _setHomeTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: true)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 1 : (_openMenuId == 1 ? null : _openMenuId);
      }),
    );

    final swap = _Pressable(
      height: 32,
      radius: 8,
      padding: EdgeInsets.zero,
      color: Colors.transparent,
      hoverColor: FfTokens.sessionHv,
      onPressed: _teamsUnlocked ? _swapTeams : null,
      child: const SizedBox(
        width: 28,
        child: PhosphorIcon(
          PhosphorIconsRegular.arrowsLeftRight,
          size: 14,
          color: FfTokens.sessionT3,
        ),
      ),
    );

    final pastedCount =
        (_awayRoster?.length ?? 0) + (_homeRoster?.length ?? 0);
    final customRosters = _Pressable(
      height: 32,
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: _usingCustomRosters
          ? FfTokens.sessionOnSoft
          : FfTokens.sessionEl,
      hoverColor: FfTokens.sessionHv,
      borderColor:
          _usingCustomRosters ? FfTokens.sessionOnRing : Colors.transparent,
      borderWidth: _usingCustomRosters ? 1 : 0,
      foreground: _sportChosen
          ? (_usingCustomRosters ? FfTokens.sessionOn : FfTokens.sessionT2)
          : FfTokens.sessionT3,
      hoverForeground: _sportChosen,
      onPressed: _sportChosen ? _pasteRoster : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.clipboardText,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            _usingCustomRosters && pastedCount > 0
                ? 'Custom rosters ($pastedCount)'
                : 'Custom rosters',
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return _StepCard(
      number: 3,
      title: 'Teams',
      complete: _teamsUnlocked && _bothTeamsChosen,
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stack)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                away,
                SizedBox(height: compact ? 4 : 8),
                home,
                SizedBox(height: compact ? 4 : 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: customRosters,
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: away),
                swap,
                Expanded(child: home),
                const SizedBox(width: 8),
                customRosters,
              ],
            ),
          if (_loadingTeams && availableTeamsEmpty) ...[
            SizedBox(height: compact ? 4 : 8),
            const Text(
              'Loading team list…',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: FfTokens.sessionT3,
              ),
            ),
          ],
          if (_offline && _sportChosen) ...[
            SizedBox(height: compact ? 4 : 8),
            const Text(
              'Offline list',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: FfTokens.sessionT3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get availableTeamsEmpty => _teams.isEmpty;

  Future<void> _setNbae(bool next) async {
    setState(() => _gettyNoteIsNbae = next);
    final prefs = _prefs ?? await PreferencesService.getInstance();
    await prefs.saveGettyNoteIsNbae(next);
  }

  String _tokenForWire(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return CaptionStyleCatalog.tokGetty;
      case WireStyle.imagn:
        return CaptionStyleCatalog.tokImagn;
      case WireStyle.ap:
        return CaptionStyleCatalog.tokAp;
      case WireStyle.cp:
        return CaptionStyleCatalog.tokCp;
      case WireStyle.custom:
        return CaptionStyleCatalog.tokCustom;
    }
  }

  void _onEmbeddedCaptionDraft(WireStyle wire, CaptionTemplate template) {
    if (!mounted) return;
    setState(() {
      _captionTemplate = template;
      _selectedStyleToken = _tokenForWire(wire);
    });
    unawaited(() async {
      final prefs = _prefs ?? await PreferencesService.getInstance();
      await prefs.saveCaptionTemplate(template);
      await _refreshIptcCaptionWarning();
    }());
  }

  Widget _buildCaptionStyleTrailingActions() {
    return Tooltip(
      message: 'Shuffle sample',
      waitDuration: const Duration(milliseconds: 350),
      child: _Pressable(
        height: 24,
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: Colors.transparent,
        hoverColor: FfTokens.sessionHv,
        hoverForeground: true,
        foreground: FfTokens.sessionT2,
        onPressed: () =>
            _captionBuilderKey.currentState?.shuffleCaptionSample(),
        child: PhosphorIcon(
          PhosphorIconsRegular.shuffle,
          size: 13,
          color: FfTokens.sessionT2,
        ),
      ),
    );
  }

  /// Admin: publish the current Structure (notes, free-text add-ons, etc.)
  /// as the Firebase wire master for all users.
  Future<void> _saveCaptionStyleAsFirebaseDefault() async {
    if (!AdminService.isCurrentUserAdminSync()) return;
    if (!_postTeamsUnlocked) return;
    final wire = _captionTemplate?.wireStyle ?? WireStyle.getty;
    // Confirm copy: Getty USA / International both read as "Getty".
    final wireLabel =
        (wire == WireStyle.getty || wire == WireStyle.gettyInternational)
            ? 'Getty'
            : WireIptcSpecs.factoryWireLabel(wire);
    final sport = (_sport ?? '').trim();
    final sportLabel = sport.isEmpty
        ? ''
        : sport[0].toUpperCase() + sport.substring(1);

    final scope = sportLabel.isEmpty ? wireLabel : '$wireLabel - $sportLabel';
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Save as default?',
      message:
          'Are you sure you want to make this the default for $scope?',
      confirmLabel: 'Save',
    );
    if (ok != true || !mounted) return;

    final okAdmin = await showAppConfirmDialog(
      context: context,
      title: 'Publishing as admin',
      message:
          'You are signed in as an admin. This writes Firebase app originals '
          'that affect all users — not your personal Preferences.',
      confirmLabel: 'Publish as admin',
    );
    if (okAdmin != true || !mounted) return;

    setState(() => _savingCaptionDefault = true);
    try {
      await _flushCaptionBuilder?.call();
      await _captionBuilderKey.currentState?.flushDraft();
      if (!mounted) return;

      final state = _captionBuilderKey.currentState;
      final template = state?.currentTemplate ?? _captionTemplate;
      if (template == null) {
        throw StateError('No caption template to publish');
      }
      final publishWire = state?.currentWire ?? template.wireStyle;

      await AppDefaultsFirestoreService.publishCaptionWireDefault(
        publishWire,
        template,
        gameIdentifierForSport: template.gameIdentifierText,
        gameIdentifierSport: sport.isEmpty ? null : sport,
        // Startup save is sport-scoped — basketball must not overwrite hockey.
        structureSport: sport.isEmpty ? null : sport,
      );

      final prefs = _prefs ?? await PreferencesService.getInstance();
      final catalog = await CaptionStyleCatalog.load(prefs, sport: _sport);
      if (!mounted) return;
      setState(() {
        _styleCatalog = catalog;
        _captionTemplate = template.copyWith(wireStyle: publishWire);
        _selectedStyleToken = _tokenForWire(publishWire);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sportLabel.isEmpty
                ? 'Saved the $wireLabel Structure to Firebase.'
                : 'Saved the $wireLabel Structure for $sportLabel to Firebase.',
          ),
          backgroundColor: FfTokens.sessionOk,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save caption default: $e'),
          backgroundColor: FfTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCaptionDefault = false);
    }
  }

  /// Wire picker on the Caption style title row (saves vertical space).
  Widget? _buildCaptionStyleHeaderWirePicker({required bool compact}) {
    final catalog = _styleCatalog;
    if (_loadingStyles || catalog == null) return null;
    final tokens = <String>[
      for (final option in catalog.options)
        if (!CaptionStyleCatalog.isCustomMenuToken(option.token)) option.token,
    ];
    if (tokens.isEmpty) return null;
    final current = tokens.contains(_selectedStyleToken)
        ? _selectedStyleToken!
        : tokens.first;
    return SizedBox(
      width: compact ? 132 : 148,
      child: _SessionSelect(
        value: current,
        hint: 'Select wire…',
        fontWeight: FontWeight.w400,
        height: 24,
        fontSize: 12,
        options: [
          for (final token in tokens) (token, catalog.labelFor(token)),
        ],
        onChanged: (token) => unawaited(_selectStyle(token)),
      ),
    );
  }

  /// Same nocturne caption layout builder used in Admin Mode (embedded).
  Widget _buildEmbeddedCaptionBuilder({bool showAdminSave = false}) {
    // Don't mount the builder (or its caption preview) until this step
    // is reachable — a saved style may already be selected.
    if (!_postTeamsUnlocked) {
      return const SizedBox.expand();
    }
    if (_loadingStyles) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: FfTokens.sessionT3,
          ),
        ),
      );
    }
    if (_captionTemplate == null && _styleCatalog == null) {
      return const SizedBox.shrink();
    }
    final dialog = CaptionLayoutBuilderDialog(
      key: _captionBuilderKey,
      embedded: true,
      adminMode: false,
      initialSport: _sport,
      initialTemplate: _captionTemplate,
      preferFileIptcValues: _iptcSource == _IptcSourceMode.files,
      previewHomeTeam: _homeFilled ? _homeTeam : null,
      previewAwayTeam: _awayFilled ? _awayTeam : null,
      previewGameInfo: _buildPreviewGameInfo(),
      previewPlayers: _captionPreviewPlayers.isEmpty
          ? null
          : List<CaptionPreviewPlayer>.from(_captionPreviewPlayers),
      previewDateFromFolder: _folderChosen ? _previewDateFromFolder : null,
      onRegisterFlush: (flush) => _flushCaptionBuilder = flush,
      onDraftChanged: _onEmbeddedCaptionDraft,
      onWireChanged: (wire) {
        if (!mounted) return;
        setState(() => _selectedStyleToken = _tokenForWire(wire));
        unawaited(_maybeOpenIptcAfterWirePick());
      },
      onSessionStructureChipTap: (focusField) {
        unawaited(
          _openIptc(
            populateFromFolder: true,
            // Don't flip "Already in files" back to write-on-ingest.
            enableWriting: _iptcSource != _IptcSourceMode.files,
            focusField: focusField,
          ),
        );
      },
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: ColoredBox(
        color: FfTokens.sessionEl,
        child: showAdminSave
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: dialog),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _Pressable(
                        height: 28,
                        radius: 8,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        color: FfTokens.gold,
                        hoverColor: FfTokens.favoritesLight,
                        borderColor: FfTokens.sessionWarnRing,
                        borderWidth: 1,
                        foreground: FfTokens.nocturneBg,
                        onPressed: _savingCaptionDefault
                            ? null
                            : () => unawaited(
                                  _saveCaptionStyleAsFirebaseDefault(),
                                ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PhosphorIcon(
                              PhosphorIconsRegular.cloudArrowUp,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _savingCaptionDefault
                                  ? 'Saving…'
                                  : 'Save as default',
                              style: const TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : SizedBox.expand(child: dialog),
      ),
    );
  }

  Widget _buildSessionStep(
    FfTokens t, {
    required bool compact,
  }) {
    final cards = <Widget>[
      _SessionOptionTile(
        icon: PhosphorIconsRegular.uploadSimple,
        title: 'FTP',
        description: 'Show the FTP button',
        value: _ftpModeEnabled,
        onChanged: (next) => unawaited(_setFtpMode(next)),
        onEdit: _openFtpSettings,
      ),
      _SessionOptionTile(
        icon: PhosphorIconsRegular.textbox,
        title: 'File renaming',
        description: 'Rename on FTP upload',
        value: _fileRenamingEnabled,
        onChanged: (next) => unawaited(_setFileRenaming(next)),
        onEdit: (_) => unawaited(_openFileRename()),
      ),
      _SessionOptionTile(
        icon: PhosphorIconsRegular.lightning,
        title: 'Firebar',
        description: 'Pin quick-caption bar',
        value: !_hideFirebar,
        onChanged: (next) => unawaited(_setFirebarShown(next)),
      ),
      if (JerseyOcrChannel.supported)
        _SessionOptionTile(
          icon: PhosphorIconsRegular.scan,
          title: 'Text recognition',
          description: 'Read jersey numbers',
          value: _jerseyOcrEnabled,
          onChanged: (next) => unawaited(_setJerseyOcr(next)),
        ),
      _SessionOptionTile(
        icon: PhosphorIconsRegular.hash,
        title: 'Serial numbers',
        description: 'Byline from serials',
        value: _serialBylinesEnabled,
        onChanged: (next) => unawaited(_setSerialBylines(next)),
        onEdit: (_) => unawaited(_openSerialNumbers()),
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: FfTokens.sessionPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Session options', style: _kSectionLabel),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 1100
                  ? 5
                  : constraints.maxWidth >= 900
                      ? 3
                      : 2;
              final gap = 8.0;
              final width = constraints.maxWidth;
              final tileW = (width - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: tileW,
                      height: 44,
                      child: card,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildV5Footer(FfTokens t) {
    final missingCount =
        _missingCaptionIptc.length + _missingFilingIptc.length;
    final Widget status;
    if (_setupStep == 1) {
      status = _FooterStatus(
        icon: _wireChosen
            ? PhosphorIconsFill.checkCircle
            : PhosphorIconsRegular.info,
        iconColor:
            _wireChosen ? FfTokens.sessionOk : FfTokens.sessionT3,
        text: _wireChosen
            ? 'Filing to $_selectedWireLabel'
            : 'Choose Getty, Imagn, AP, or CP',
      );
    } else if (_setupStep == 2) {
      if (!_folderChosen) {
        status = const _FooterStatus(
          icon: PhosphorIconsRegular.info,
          iconColor: FfTokens.sessionT3,
          text: 'Choose an images folder',
        );
      } else if (!_awayFilled || !_homeFilled) {
        status = const _FooterStatus(
          icon: PhosphorIconsRegular.info,
          iconColor: FfTokens.sessionT3,
          text: 'Pick both teams to continue',
        );
      } else if (_iptcSource != _IptcSourceMode.files &&
          _hasIptcFieldWarnings) {
        status = _FooterStatus(
          icon: PhosphorIconsFill.warningCircle,
          iconColor: FfTokens.sessionWarn,
          linkLabel: '$missingCount IPTC fields missing for $_filingWireLabel',
          onLink: () => unawaited(_openIptcForMissingFields()),
        );
      } else {
        status = const _FooterStatus(
          icon: PhosphorIconsFill.checkCircle,
          iconColor: FfTokens.sessionOk,
          text: 'Ready',
        );
      }
    } else if (_iptcSource == _IptcSourceMode.files) {
      status = const _FooterStatus(
        icon: PhosphorIconsRegular.fileMagnifyingGlass,
        iconColor: FfTokens.sessionT3,
        text: 'Underlined values are read from each file',
      );
    } else if (_hasIptcFieldWarnings) {
      status = _FooterStatus(
        icon: PhosphorIconsFill.warningCircle,
        iconColor: FfTokens.sessionWarn,
        linkLabel:
            'IPTC warning — $missingCount fields missing to file to $_filingWireLabel',
        onLink: () => unawaited(_openIptcForMissingFields()),
      );
    } else {
      status = const _FooterStatus(
        icon: PhosphorIconsFill.checkCircle,
        iconColor: FfTokens.sessionOk,
        text: 'IPTC template complete',
      );
    }

    // Back lives on each stage panel. Footer: status (+ Go time on step 3).
    if (_setupStep != 3) {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
        decoration: const BoxDecoration(
          color: FfTokens.sessionPanel,
          border: Border(top: BorderSide(color: FfTokens.sessionLn)),
        ),
        child: status,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
      decoration: const BoxDecoration(
        color: FfTokens.sessionPanel,
        border: Border(top: BorderSide(color: FfTokens.sessionLn)),
      ),
      child: Row(
        children: [
          Expanded(child: status),
          _GoTimeButton(
            enabled: _canGo,
            loading: _going,
            compact: false,
            label: 'Go time',
            shortcut: '⌘↵',
            onPressed: _goTime,
          ),
        ],
      ),
    );
  }

  static String _leagueLabel(String s) {
    switch (s.toLowerCase()) {
      case 'hockey':
        return 'NHL';
      case 'basketball':
        return 'NBA';
      case 'wnba':
        return 'WNBA';
      case 'baseball':
        return 'MLB';
      case 'soccer':
        return 'MLS';
      case 'football':
        return 'NFL';
      default:
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  static List<String> _fallbackTeams(String sport) {
    switch (sport.toLowerCase()) {
      case 'hockey':
        return const [
          'Anaheim Ducks',
          'Arizona Coyotes',
          'Boston Bruins',
          'Buffalo Sabres',
          'Calgary Flames',
          'Carolina Hurricanes',
          'Chicago Blackhawks',
          'Colorado Avalanche',
          'Columbus Blue Jackets',
          'Dallas Stars',
          'Detroit Red Wings',
          'Edmonton Oilers',
          'Florida Panthers',
          'Los Angeles Kings',
          'Minnesota Wild',
          'Montreal Canadiens',
          'Nashville Predators',
          'New Jersey Devils',
          'New York Islanders',
          'New York Rangers',
          'Ottawa Senators',
          'Philadelphia Flyers',
          'Pittsburgh Penguins',
          'San Jose Sharks',
          'Seattle Kraken',
          'St. Louis Blues',
          'Tampa Bay Lightning',
          'Toronto Maple Leafs',
          'Vancouver Canucks',
          'Vegas Golden Knights',
          'Washington Capitals',
          'Winnipeg Jets',
        ];
      case 'basketball':
        return const [
          'Atlanta Hawks',
          'Boston Celtics',
          'Brooklyn Nets',
          'Charlotte Hornets',
          'Chicago Bulls',
          'Cleveland Cavaliers',
          'Dallas Mavericks',
          'Denver Nuggets',
          'Detroit Pistons',
          'Golden State Warriors',
          'Houston Rockets',
          'Indiana Pacers',
          'Los Angeles Clippers',
          'Los Angeles Lakers',
          'Memphis Grizzlies',
          'Miami Heat',
          'Milwaukee Bucks',
          'Minnesota Timberwolves',
          'New Orleans Pelicans',
          'New York Knicks',
          'Oklahoma City Thunder',
          'Orlando Magic',
          'Philadelphia 76ers',
          'Phoenix Suns',
          'Portland Trail Blazers',
          'Sacramento Kings',
          'San Antonio Spurs',
          'Toronto Raptors',
          'Utah Jazz',
          'Washington Wizards',
        ];
      case 'wnba':
        return const [
          'Atlanta Dream',
          'Chicago Sky',
          'Connecticut Sun',
          'Dallas Wings',
          'Golden State Valkyries',
          'Indiana Fever',
          'Las Vegas Aces',
          'Los Angeles Sparks',
          'Minnesota Lynx',
          'New York Liberty',
          'Phoenix Mercury',
          'Portland Fire',
          'Seattle Storm',
          'Toronto Tempo',
          'Washington Mystics',
        ];
      case 'soccer':
        return const [
          'Atlanta United FC',
          'Austin FC',
          'CF Montréal',
          'Charlotte FC',
          'Chicago Fire FC',
          'Colorado Rapids',
          'Columbus Crew',
          'D.C. United',
          'FC Cincinnati',
          'FC Dallas',
          'Houston Dynamo FC',
          'Inter Miami CF',
          'LA Galaxy',
          'LAFC',
          'Minnesota United FC',
          'Nashville SC',
          'New England Revolution',
          'New York City FC',
          'Orlando City SC',
          'Philadelphia Union',
          'Portland Timbers',
          'Real Salt Lake',
          'Red Bull New York',
          'San Diego FC',
          'San Jose Earthquakes',
          'Seattle Sounders FC',
          'Sporting Kansas City',
          'St. Louis CITY SC',
          'Toronto FC',
          'Vancouver Whitecaps',
        ];
      default:
        return const [
          'Arizona Diamondbacks',
          'Atlanta Braves',
          'Baltimore Orioles',
          'Boston Red Sox',
          'Chicago Cubs',
          'Chicago White Sox',
          'Cincinnati Reds',
          'Cleveland Guardians',
          'Colorado Rockies',
          'Detroit Tigers',
          'Houston Astros',
          'Kansas City Royals',
          'Los Angeles Angels',
          'Los Angeles Dodgers',
          'Miami Marlins',
          'Milwaukee Brewers',
          'Minnesota Twins',
          'New York Mets',
          'New York Yankees',
          'Oakland Athletics',
          'Philadelphia Phillies',
          'Pittsburgh Pirates',
          'San Diego Padres',
          'San Francisco Giants',
          'Seattle Mariners',
          'St. Louis Cardinals',
          'Tampa Bay Rays',
          'Texas Rangers',
          'Toronto Blue Jays',
          'Washington Nationals',
        ];
    }
  }
}

// ---------------------------------------------------------------------------
// Live caption preview (sport-correct league / period; placeholder styling)
// ---------------------------------------------------------------------------

class _CaptionPreviewLive extends StatelessWidget {
  const _CaptionPreviewLive({
    required this.sport,
    required this.awayTeam,
    required this.homeTeam,
    required this.gameInfo,
    required this.previewPlayers,
    required this.sampleSeed,
    required this.template,
    required this.gettyNbaeNote,
    required this.fontSize,
  });

  final String? sport;
  final String? awayTeam;
  final String? homeTeam;
  final GameInfo gameInfo;
  final List<CaptionPreviewPlayer> previewPlayers;
  final int sampleSeed;
  final CaptionTemplate? template;
  final bool gettyNbaeNote;
  final double fontSize;

  static const _awayPlaceholder = 'Away team';
  static const _homePlaceholder = 'Home team';
  static const _periodPlaceholder = 'period';
  static const _leaguePlaceholder = 'league';

  @override
  Widget build(BuildContext context) {
    final tpl = template ?? CaptionTemplate.getty();
    final sportKey = (sport ?? '').toLowerCase().trim();
    final hasSport = sportKey.isNotEmpty;

    final away = (awayTeam != null && awayTeam!.isNotEmpty)
        ? awayTeam!
        : _awayPlaceholder;
    final home = (homeTeam != null && homeTeam!.isNotEmpty)
        ? homeTeam!
        : _homePlaceholder;
    final awayFilled = away != _awayPlaceholder;
    final homeFilled = home != _homePlaceholder;

    final timing = hasSport
        ? CaptionFormulaRenderer.previewTimePhraseForSport(sportKey)
        : 'in the $_periodPlaceholder';

    final game = gameInfo;
    final agency = _agencyFor(tpl.wireStyle);
    // Structure free-text only — do not inject a hidden league phrase.
    final previewTemplate = tpl.stripGameIdentifierForWireMaster();

    final String body;
    if (previewPlayers.isNotEmpty) {
      body = CaptionFormulaRenderer.randomSinglePlayerCaption(
        previewTemplate,
        seed: sampleSeed,
        previewPlayers: previewPlayers,
        sport: hasSport ? sportKey : null,
      );
    } else if (awayFilled || homeFilled) {
      body = 'Loading ${awayFilled ? away : home} roster…';
    } else {
      body = '$away player against the $home $timing';
    }

    // Prefer a full formula render when we have a template; fall back to body.
    String caption;
    try {
      caption = CaptionFormulaRenderer.render(
        template: previewTemplate,
        game: game,
        sampleAgency: agency,
        captionOverride: body,
        sport: hasSport ? sportKey : null,
        applyGettyNoteVariant: true,
        gettyNbaeNote: gettyNbaeNote,
      );
    } catch (_) {
      final loc = [
        if (game.city.trim().isNotEmpty) game.city.trim(),
        if (game.region.trim().isNotEmpty) game.region.trim(),
        if (game.countryCode.trim().isNotEmpty) game.countryCode.trim(),
      ].join(', ');
      final venue = game.venue.trim().isNotEmpty
          ? game.venue.trim()
          : 'Sports Stadium';
      final when = game.gameDate != null ? _weekday(game.gameDate!) : '';
      caption =
          '$loc. $body at $venue${when.isEmpty ? '' : ' $when'}. '
          '${game.photographerName}/${CaptionFormulaRenderer.defaultAgencyLabel(agency)}';
    }

    // If sport is unset, ensure period/league placeholders appear.
    if (!hasSport) {
      caption = caption
          .replaceAll(
            RegExp(
              r'\b(during the third period|during the third inning|during the fourth quarter|during the second half)\b',
              caseSensitive: false,
            ),
            'during the $_periodPlaceholder',
          )
          .replaceAll(
            RegExp(
              r'\b(NHL|MLB|NBA|WNBA|MLS)\b',
            ),
            _leaguePlaceholder,
          );
    }

    final filled = <String>[
      if (awayFilled) away,
      if (homeFilled) home,
    ];
    final missing = <String>[
      if (!awayFilled) _awayPlaceholder,
      if (!homeFilled) _homePlaceholder,
      if (!hasSport) _periodPlaceholder,
      if (!hasSport) _leaguePlaceholder,
    ];

    return Text.rich(
      TextSpan(
        children: _spanCaption(
          caption,
          filled: filled,
          missing: missing,
          text: FfTokens.sessionTx,
          hot: FfTokens.sessionHot,
          missingColor: FfTokens.sessionT3,
          rule: FfTokens.sessionLn2,
        ),
      ),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: fontSize,
        height: 1.35,
        color: FfTokens.sessionTx,
      ),
    );
  }

  static CreditSampleAgency _agencyFor(WireStyle wire) {
    switch (wire) {
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
      case WireStyle.cp:
        return CreditSampleAgency.ap;
      case WireStyle.getty:
      case WireStyle.gettyInternational:
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  static String _weekday(DateTime d) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[d.weekday - 1];
  }

  static List<InlineSpan> _spanCaption(
    String caption, {
    required List<String> filled,
    required List<String> missing,
    required Color text,
    required Color hot,
    required Color missingColor,
    required Color rule,
  }) {
    final markers = <_Mark>[];
    for (final f in filled) {
      if (f.isEmpty) continue;
      var start = 0;
      while (true) {
        final i = caption.indexOf(f, start);
        if (i < 0) break;
        markers.add(_Mark(i, i + f.length, filled: true));
        start = i + f.length;
      }
    }
    for (final m in missing) {
      if (m.isEmpty) continue;
      var start = 0;
      while (true) {
        final i = caption.indexOf(m, start);
        if (i < 0) break;
        markers.add(_Mark(i, i + m.length, filled: false));
        start = i + m.length;
      }
    }
    markers.sort((a, b) => a.start.compareTo(b.start));

    // Drop overlaps (keep earlier / longer).
    final kept = <_Mark>[];
    var cursor = 0;
    for (final m in markers) {
      if (m.start < cursor) continue;
      kept.add(m);
      cursor = m.end;
    }

    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in kept) {
      if (m.start > i) {
        spans.add(TextSpan(
          text: caption.substring(i, m.start),
          style: TextStyle(color: text),
        ));
      }
      spans.add(TextSpan(
        text: caption.substring(m.start, m.end),
        style: m.filled
            ? TextStyle(
                color: text,
                fontWeight: FontWeight.w600,
                backgroundColor: hot,
              )
            : TextStyle(
                color: missingColor,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.underline,
                decorationColor: rule,
                decorationThickness: 1,
              ),
      ));
      i = m.end;
    }
    if (i < caption.length) {
      spans.add(TextSpan(
        text: caption.substring(i),
        style: TextStyle(color: text),
      ));
    }
    return spans;
  }
}

class _Mark {
  const _Mark(this.start, this.end, {required this.filled});
  final int start;
  final int end;
  final bool filled;
}

const _kSectionLabel = TextStyle(
  fontFamily: FfTokens.fontFamily,
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.88,
  color: FfTokens.sessionT3,
);

const _kBody = TextStyle(
  fontFamily: FfTokens.fontFamily,
  color: FfTokens.sessionTx,
);

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.complete,
    this.child,
    this.trailing,
    this.headerControl,
    this.expandHeader = false,
    this.inline = false,
    this.highlighted = false,
    this.compact = false,
    this.expand = false,
  });

  final int number;
  final String title;
  final bool complete;
  final Widget? child;
  final Widget? trailing;
  final Widget? headerControl;
  final bool expandHeader;
  final bool inline;
  final bool highlighted;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final denseHeader = expandHeader;
    final titleStyle = _kBody.copyWith(
      fontSize: denseHeader ? 12 : (compact ? 13 : 14),
      fontWeight: FontWeight.w600,
    );
    final padV = denseHeader
        ? (compact ? 4.0 : 6.0)
        : (compact ? 8.0 : 12.0);
    final padH = compact ? 12.0 : 14.0;
    final headerH = denseHeader ? 24.0 : (inline ? 32.0 : 22.0);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: headerH,
          child: Row(
            children: [
              _StepBadge(
                number: number,
                complete: complete,
                compact: denseHeader,
              ),
              SizedBox(width: denseHeader ? 6 : 8),
              if (inline || expandHeader || headerControl != null)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                )
              else
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              if (inline) ...[
                const SizedBox(width: 12),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
              if (expandHeader && headerControl != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: headerControl,
                    ),
                  ),
                ),
              ] else if (headerControl != null) ...[
                const SizedBox(width: 10),
                headerControl!,
                if (!inline) const Spacer(),
              ],
              if (trailing != null) ...[
                SizedBox(width: denseHeader ? 4 : 8),
                trailing!,
              ],
            ],
          ),
        ),
        if (!inline && child != null) ...[
          SizedBox(height: denseHeader ? 4 : (compact ? 6 : 10)),
          if (expand)
            Expanded(child: child!)
          else
            child!,
        ],
      ],
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      height: expand ? double.infinity : null,
      padding: EdgeInsets.fromLTRB(
        padH,
        inline ? 6 : padV,
        padH,
        inline ? 6 : padV,
      ),
      decoration: BoxDecoration(
        color: highlighted ? FfTokens.sessionEl : FfTokens.sessionPanel,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(
          color: highlighted ? FfTokens.sessionOn : Colors.transparent,
        ),
      ),
      child: body,
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.complete,
    this.compact = false,
  });

  final int number;
  final bool complete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 18.0 : 22.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: complete ? FfTokens.sessionOkSoft : Colors.transparent,
        border: complete
            ? null
            : Border.all(color: FfTokens.sessionLn2, width: compact ? 1 : 1.5),
      ),
      child: complete
          ? PhosphorIcon(
              PhosphorIconsBold.check,
              size: compact ? 11 : 13,
              color: FfTokens.sessionOk,
            )
          : Text(
              '$number',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: FfTokens.sessionT3,
                height: 1,
              ),
            ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.child,
    this.expand = false,
    this.compact = false,
  });

  final Widget child;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 12.0 : 14.0;
    return Container(
      width: double.infinity,
      height: expand ? double.infinity : null,
      padding: EdgeInsets.fromLTRB(pad, compact ? 10 : 12, pad, compact ? 12 : 14),
      decoration: BoxDecoration(
        color: FfTokens.sessionPanel,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
      ),
      child: child,
    );
  }
}

class _FolderDropRow extends StatelessWidget {
  const _FolderDropRow({
    required this.empty,
    required this.emphasized,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.compact = false,
  });

  final bool empty;
  final bool emphasized;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 36.0 : 40.0;
    final row = Row(
      children: [
        PhosphorIcon(icon, size: compact ? 18 : 20, color: FfTokens.sessionT3),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FfTokens.sessionTx,
                  height: 1.1,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: FfTokens.sessionT3,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _Pressable(
          height: compact ? 26 : 30,
          radius: 6,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          color: FfTokens.sessionPanel,
          hoverColor: FfTokens.sessionHv,
          onPressed: onPressed,
          child: Text(
            buttonLabel,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onPressed == null
                  ? FfTokens.sessionT3
                  : FfTokens.sessionTx,
            ),
          ),
        ),
      ],
    );
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      child: row,
    );
    if (empty) {
      return SizedBox(
        height: height,
        child: CustomPaint(
          painter: _DottedRRectPainter(
            color: emphasized ? FfTokens.sessionOn : FfTokens.sessionLn2,
            radius: 9,
          ),
          child: child,
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: height,
      decoration: BoxDecoration(
        color: FfTokens.sessionEl,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: emphasized ? FfTokens.sessionOn : FfTokens.sessionLn2,
        ),
      ),
      child: child,
    );
  }
}

class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.child,
    required this.emphasized,
  });

  final Widget child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedRRectPainter(
        color: emphasized ? FfTokens.sessionAc : FfTokens.sessionT3,
        radius: 8,
      ),
      child: Container(
        height: 32,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: child,
      ),
    );
  }
}

class _DottedRRectPainter extends CustomPainter {
  const _DottedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  static const double _dash = 3;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _SessionSelect extends StatelessWidget {
  const _SessionSelect({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.leading,
    this.fontWeight = FontWeight.w600,
    this.enabled = true,
    this.height = 32,
    this.fontSize = 13,
  });

  final String? value;
  final String hint;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final Widget? leading;
  final FontWeight fontWeight;
  final bool enabled;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final current = value;
    final label = current == null
        ? hint
        : options
            .where((option) => option.$1 == current)
            .map((option) => option.$2)
            .firstOrNull;
    final hasValue = label != null && current != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: _Pressable(
        height: height,
        radius: 7,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        color: FfTokens.sessionEl,
        hoverColor: enabled ? FfTokens.sessionHv : FfTokens.sessionEl,
        onPressed: enabled ? () => _open(context) : null,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                hasValue ? label : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: hasValue ? FfTokens.sessionTx : FfTokens.sessionT3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 12,
              color: FfTokens.sessionT3,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final picked = await showFfMenu<String>(
      context: context,
      anchorGlobal: origin & box.size,
      width: box.size.width < 180 ? 180 : box.size.width,
      colors: FfMenuColors.session,
      choices: [
        for (final option in options)
          FfMenuChoice<String>(
            value: option.$1,
            selected: option.$1 == value,
            child: Text(
              option.$2,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: fontWeight,
              ),
            ),
          ),
      ],
    );
    if (picked == null) return;
    final next = picked.value;
    if (next == null || next == value) return;
    onChanged(next);
  }
}

class _SessionSwitch extends StatelessWidget {
  const _SessionSwitch({
    required this.value,
    required this.onChanged,
    this.alignment = Alignment.centerRight,
    this.activeColor = FfTokens.sessionOn,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Alignment alignment;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    // Scale visually, but also clamp layout size so option cards stay compact.
    return SizedBox(
      width: 30,
      height: 18,
      child: Transform.scale(
        scale: 0.64,
        alignment: alignment,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          thumbIcon: const WidgetStatePropertyAll(
            Icon(Icons.circle, size: 0, color: Colors.transparent),
          ),
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return activeColor;
            }
            // Darker than sessionEl / option card fills so the off state reads.
            return FfTokens.sessionBg;
          }),
          trackOutlineColor: const WidgetStatePropertyAll(FfTokens.sessionLn2),
        ),
      ),
    );
  }
}

class _SessionOptionCard extends StatelessWidget {
  const _SessionOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? actionLabel;
  final IconData? actionIcon;
  final void Function(BuildContext anchor)? onAction;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final showAction = actionLabel != null && onAction != null && value;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(8),
          hoverColor: enabled ? FfTokens.sessionHv : Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: value
                  ? FfTokens.nocturneAccentRow
                  : FfTokens.nocturneSf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: value
                    ? FfTokens.nocturneAccentEdge
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 9,
                vertical: compact ? 4 : 5,
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    icon,
                    size: 14,
                    color: value
                        ? FfTokens.accentHover
                        : FfTokens.sessionT3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                            color: FfTokens.sessionTx,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 11,
                            height: 1.15,
                            color: FfTokens.sessionT3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showAction) ...[
                    const SizedBox(width: 4),
                    Builder(
                      builder: (context) {
                        return _SessionOptionAction(
                          label: actionLabel!,
                          icon: actionIcon,
                          onPressed:
                              enabled ? () => onAction!(context) : null,
                        );
                      },
                    ),
                  ],
                  const SizedBox(width: 4),
                  _SessionSwitch(
                    value: value,
                    onChanged: enabled ? onChanged : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionOptionAction extends StatefulWidget {
  const _SessionOptionAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  State<_SessionOptionAction> createState() => _SessionOptionActionState();
}

class _SessionOptionActionState extends State<_SessionOptionAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? FfTokens.sessionT3
        : (_hover ? FfTokens.sessionTx : FfTokens.sessionT2);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon == PhosphorIconsRegular.pencilSimple) ...[
                PhosphorIcon(widget.icon!, size: 11, color: color),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (widget.icon == PhosphorIconsRegular.caretDown) ...[
                const SizedBox(width: 2),
                PhosphorIcon(widget.icon!, size: 11, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachedChoice extends StatelessWidget {
  const _AttachedChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.expand = true,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            _choiceSegment(i),
        ],
      ),
    );
  }

  Widget _choiceSegment(int i) {
    final label = Text(
      options[i],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final button = _Pressable(
      height: 26,
      radius: 0,
      padding: expand
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8),
      borderRadius: BorderRadius.horizontal(
        left: i == 0 ? const Radius.circular(8) : Radius.zero,
        right: i == options.length - 1 ? const Radius.circular(8) : Radius.zero,
      ),
      borderColor: i == selected ? FfTokens.sessionLn2 : Colors.transparent,
      borderWidth: i == selected ? 1 : 0,
      color: i == selected ? FfTokens.sessionHv : FfTokens.sessionEl,
      hoverColor: i == selected ? FfTokens.sessionHv : FfTokens.sessionEl,
      hoverForeground: enabled && i != selected,
      foreground: i == selected ? FfTokens.sessionTx : FfTokens.sessionT2,
      onPressed: !enabled || i == selected ? null : () => onSelected(i),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (i == selected) ...[
            const PhosphorIcon(PhosphorIconsBold.check, size: 14),
            const SizedBox(width: 6),
          ],
          if (expand) Flexible(child: label) else label,
        ],
      ),
    );
    if (!expand) return button;
    return Expanded(child: button);
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.trailing,
    this.warning = false,
    this.padded = false,
    this.divider = false,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final Widget? trailing;
  final bool warning;
  final bool padded;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padded ? const EdgeInsets.symmetric(vertical: 10) : null,
      decoration: divider
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: FfTokens.sessionLn)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: enabled ? FfTokens.sessionTx : FfTokens.sessionT3,
                  ),
                ),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    height: 1.3,
                    color: warning ? FfTokens.danger : FfTokens.sessionT3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
          const SizedBox(width: 12),
          _Switch36(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Switch36 extends StatelessWidget {
  const _Switch36({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? () => onChanged(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? FfTokens.sessionOn : FfTokens.nocturneHv,
              borderRadius: BorderRadius.circular(99),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? FfTokens.nocturneBg : FfTokens.sessionT3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamDropdown extends StatefulWidget {
  const _TeamDropdown({
    required this.menuId,
    required this.openMenuId,
    required this.label,
    required this.value,
    required this.teams,
    required this.enabled,
    required this.sideFavorite,
    required this.favoriteNames,
    required this.hintText,
    required this.onChanged,
    required this.onToggleFavorite,
    required this.onMenuOpenChanged,
    required this.focusNode,
    this.hideLabel = false,
    this.fieldHeight = 32,
  });

  final int menuId;
  final int? openMenuId;
  final String label;
  final String? value;
  final List<String> teams;
  final bool enabled;
  final String? sideFavorite;
  final Set<String> favoriteNames;
  final String hintText;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<bool> onMenuOpenChanged;
  final FocusNode focusNode;
  final bool hideLabel;
  final double fieldHeight;

  @override
  State<_TeamDropdown> createState() => _TeamDropdownState();
}

class _TeamDropdownState extends State<_TeamDropdown> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  /// Row order at open time. Starring must not reshuffle the open menu —
  /// the jump to Favorites looks like a glitch.
  List<String> _menuFavorites = const [];
  List<String> _menuRest = const [];

  void _captureMenuOrder() {
    _menuFavorites =
        widget.teams.where(widget.favoriteNames.contains).toList();
    _menuRest =
        widget.teams.where((t) => !widget.favoriteNames.contains(t)).toList();
  }

  @override
  void didUpdateWidget(covariant _TeamDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entry == null) return;
    final shouldClose = _open && widget.openMenuId != widget.menuId;
    final favoritesChanged = !_sameStrings(
      oldWidget.favoriteNames,
      widget.favoriteNames,
    );
    if (_open && favoritesChanged) {
      // Keep Favorites section in sync when stars change; don't reshuffle All.
      _menuFavorites =
          widget.teams.where(widget.favoriteNames.contains).toList();
      _menuRest =
          widget.teams.where((t) => !widget.favoriteNames.contains(t)).toList();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry == null) return;
      if (shouldClose) {
        _remove(notify: false);
      } else {
        _entry?.markNeedsBuild();
      }
    });
  }

  static bool _sameStrings(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final s in a) {
      if (!b.contains(s)) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _remove(notify: false);
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_open) {
      _remove(notify: true);
    } else {
      _show();
    }
  }

  void _show() {
    _captureMenuOrder();
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 240;
    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _remove(notify: true),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 4),
              child: SizedBox(
                width: width,
                child: _menu(),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_entry!);
    _open = true;
    widget.onMenuOpenChanged(true);
  }

  void _remove({required bool notify}) {
    _entry?.remove();
    _entry = null;
    final wasOpen = _open;
    _open = false;
    _menuFavorites = const [];
    _menuRest = const [];
    if (notify && wasOpen) widget.onMenuOpenChanged(false);
  }

  Widget _menu() {
    final favorites = _menuFavorites;
    final rest = _menuRest;
    return FfMenuSurface(
      child: ListView(
          padding: const EdgeInsets.all(6),
          shrinkWrap: true,
          primary: false,
          children: [
            if (favorites.isNotEmpty) ...[
              const _MenuHeader('Favorites'),
              for (final name in favorites) _menuRow(name),
            ],
            const _MenuHeader('All teams'),
            for (final name in rest) _menuRow(name),
            if (widget.teams.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Text(
                  'No teams yet',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    color: FfTokens.sessionT3,
                  ),
                ),
              ),
          ],
        ),
    );
  }

  Widget _menuRow(String name) {
    final favorite = widget.favoriteNames.contains(name) ||
        widget.sideFavorite == name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            widget.onChanged(name);
            _remove(notify: true);
          },
          hoverColor: FfTokens.nocturneHv,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    mlbTeamAbbreviation(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: FfTokens.sessionT2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _kBody.copyWith(fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: () => widget.onToggleFavorite(name),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: PhosphorIcon(
                      favorite
                          ? PhosphorIconsFill.star
                          : PhosphorIconsRegular.star,
                      size: 14,
                      color: favorite ? FfTokens.gold : FfTokens.sessionT3,
                    ),
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
  Widget build(BuildContext context) {
    final value = widget.value;
    final hasValue = value != null && value.isNotEmpty;
    final favorited = hasValue &&
        (widget.sideFavorite == value ||
            widget.favoriteNames.contains(value));
    final field = CompositedTransformTarget(
          link: _link,
          child: Focus(
            focusNode: widget.focusNode,
            onKeyEvent: (node, event) {
              if (_open &&
                  event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _remove(notify: true);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _Pressable(
              height: widget.fieldHeight,
              radius: 9,
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              color: FfTokens.sessionEl,
              hoverColor: FfTokens.sessionHv,
              onPressed: widget.enabled ? _toggle : null,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FfTokens.sessionPanel,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasValue ? mlbTeamAbbreviation(value) : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: hasValue
                            ? FfTokens.sessionTx
                            : FfTokens.sessionT3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasValue ? value : widget.hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight:
                            hasValue ? FontWeight.w600 : FontWeight.w500,
                        color: hasValue
                            ? FfTokens.sessionTx
                            : FfTokens.sessionT3,
                      ),
                    ),
                  ),
                  if (favorited) ...[
                    const PhosphorIcon(
                      PhosphorIconsFill.star,
                      size: 14,
                      color: FfTokens.sessionWarn,
                    ),
                    const SizedBox(width: 6),
                  ],
                  const PhosphorIcon(
                    PhosphorIconsRegular.caretDown,
                    size: 12,
                    color: FfTokens.sessionT3,
                  ),
                ],
              ),
            ),
          ),
        );
    if (widget.hideLabel) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: _kSectionLabel,
        ),
        const SizedBox(height: 2),
        field,
      ],
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: FfTokens.sessionT3,
        ),
      ),
    );
  }
}

class _PasteRosterButton extends StatelessWidget {
  const _PasteRosterButton({
    required this.enabled,
    required this.pastedCount,
    required this.onPressed,
  });

  final bool enabled;
  final int pastedCount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final pasted = pastedCount > 0;
    return _Pressable(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: FfTokens.nocturneSunken,
      hoverColor: enabled ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
      onPressed: onPressed,
      child: Row(
        children: [
          PhosphorIcon(
            PhosphorIconsRegular.clipboardText,
            size: 18,
            color: enabled ? FfTokens.sessionT2 : FfTokens.sessionT3,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste rosters',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: enabled ? FfTokens.sessionTx : FfTokens.sessionT3,
                  ),
                ),
                Text(
                  pasted
                      ? '$pastedCount players pasted'
                      : 'From a webpage or other source',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    color: pasted ? FfTokens.sessionOk : FfTokens.sessionT3,
                  ),
                ),
              ],
            ),
          ),
          const PhosphorIcon(
            PhosphorIconsRegular.caretRight,
            size: 14,
            color: FfTokens.sessionT3,
          ),
        ],
      ),
    );
  }
}

class _GoTimeButton extends StatefulWidget {
  const _GoTimeButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
    this.compact = false,
    this.label = 'Go time',
    this.shortcut = '↵',
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;
  final bool compact;
  final String label;
  final String shortcut;

  @override
  State<_GoTimeButton> createState() => _GoTimeButtonState();
}

class _GoTimeButtonState extends State<_GoTimeButton> {
  bool _hover = false;
  bool _pressed = false;

  /// Same teal ramp as TealActionButton / primary ElevatedGreyButton.
  static const _rest = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF243848),
      Color(0xFF15242E),
      Color(0xFF0E181F),
    ],
    stops: [0.0, 0.45, 1.0],
  );
  static const _hoverGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF2E4658),
      Color(0xFF1A2E3A),
      Color(0xFF121F28),
    ],
    stops: [0.0, 0.45, 1.0],
  );
  static const _down = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1A2A36),
      Color(0xFF0C141A),
      Color(0xFF080E12),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !widget.loading;
    final active = widget.enabled;
    final fg = active ? Colors.white : Colors.white.withValues(alpha: 0.4);
    final gradient = !active
        ? null
        : _pressed
            ? _down
            : _hover
                ? _hoverGrad
                : _rest;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: widget.compact ? 32 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? null
                : const Color(0xFF15242E).withValues(alpha: 0.55),
            gradient: gradient,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(
              color: !active
                  ? FfTokens.nocturneLn
                  : (_hover
                      ? Colors.white.withValues(alpha: 0.92)
                      : FfTokens.nocturneAc.withValues(alpha: 0.95)),
            ),
            boxShadow: active
                ? FfTokens.accentButtonGlow(
                    _hover ? Colors.white : FfTokens.nocturneAc,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.loading ? 'Starting…' : widget.label,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: fg,
                ),
              ),
              if (!widget.loading) ...[
                const SizedBox(width: 10),
                _KbdHint(widget.shortcut, onDark: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingFieldsLink extends StatelessWidget {
  const _MissingFieldsLink({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open IPTC and highlight missing fields',
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
              decoration: TextDecoration.underline,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onPressed,
    required this.color,
    required this.hoverColor,
    this.radius = 9,
    this.borderRadius,
    this.height,
    this.width,
    this.padding = EdgeInsets.zero,
    this.borderColor = Colors.transparent,
    this.borderWidth = 0,
    this.hoverForeground = false,
    this.foreground = FfTokens.sessionTx,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color color;
  final Color hoverColor;
  final double radius;
  final BorderRadius? borderRadius;
  final double? height;
  final double? width;
  final EdgeInsets padding;
  final Color borderColor;
  final double borderWidth;
  final bool hoverForeground;
  final Color foreground;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final hovering = _hover && enabled;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          // Only align when width is explicit. A non-null alignment makes
          // Container expand to max width, which un-right-justified actions.
          alignment: widget.width != null ? Alignment.center : null,
          decoration: BoxDecoration(
            color: hovering && !widget.hoverForeground
                ? widget.hoverColor
                : widget.color,
            borderRadius:
                widget.borderRadius ?? BorderRadius.circular(widget.radius),
            border: Border.all(
              color: widget.borderColor,
              width: widget.borderWidth,
            ),
          ),
          child: IconTheme(
            data: IconThemeData(
              color: hovering && widget.hoverForeground
                  ? FfTokens.sessionTx
                  : widget.foreground,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: hovering && widget.hoverForeground
                    ? FfTokens.sessionTx
                    : widget.foreground,
              ),
              child: widget.width == null && widget.height != null
                  ? Center(widthFactor: 1, child: widget.child)
                  : widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint(this.label, {this.onDark = false});

  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.black.withValues(alpha: 0.28)
            : const Color(0x14E8EEF4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: onDark ? Colors.white : FfTokens.sessionT2,
        ),
      ),
    );
  }
}

class _FooterStatus extends StatelessWidget {
  const _FooterStatus({
    required this.icon,
    required this.iconColor,
    this.text,
    this.linkLabel,
    this.onLink,
  });

  final IconData icon;
  final Color iconColor;
  final String? text;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PhosphorIcon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: linkLabel != null
              ? _MissingFieldsLink(
                  label: linkLabel!,
                  color: iconColor,
                  onTap: onLink ?? () {},
                )
              : Text(
                  text ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    color: FfTokens.sessionT2,
                  ),
                ),
        ),
      ],
    );
  }
}

class _V5IptcNote extends StatelessWidget {
  const _V5IptcNote({
    required this.icon,
    required this.iconColor,
    required this.child,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: FfTokens.nocturneSf,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PhosphorIcon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
          if (action != null) ...[
            const SizedBox(width: 10),
            _Pressable(
              height: 19,
              radius: 4,
              padding: EdgeInsets.zero,
              color: Colors.transparent,
              hoverColor: Colors.transparent,
              hoverForeground: true,
              foreground: FfTokens.accentHover,
              onPressed: action,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(PhosphorIconsRegular.pencilSimple, size: 13),
                  SizedBox(width: 5),
                  Text(
                    'Edit template',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _V5Segmented<T> extends StatelessWidget {
  const _V5Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
    this.small = false,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final i = options.indexWhere((o) => o.$1 == value);
        if (i < 0) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onChanged(options[(i + 1) % options.length].$1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onChanged(options[(i - 1 + options.length) % options.length].$1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: FfTokens.sessionBg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            for (final option in options)
              Expanded(
                child: _Pressable(
                  height: small ? 28 : 36,
                  radius: 7,
                  padding: EdgeInsets.symmetric(horizontal: small ? 10 : 12),
                  color: option.$1 == value
                      ? FfTokens.nocturneAccentSoft
                      : Colors.transparent,
                  borderColor: option.$1 == value
                      ? FfTokens.nocturneAccentEdge
                      : Colors.transparent,
                  borderWidth: option.$1 == value ? 1 : 0,
                  hoverColor: FfTokens.sessionHv,
                  hoverForeground: option.$1 != value,
                  foreground: option.$1 == value
                      ? FfTokens.sessionTx
                      : FfTokens.sessionT3,
                  onPressed: () => onChanged(option.$1),
                  child: Center(
                    child: Text(
                      option.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: small ? 12 : 13,
                        fontWeight: FontWeight.w600,
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
}

class _SessionOptionTile extends StatelessWidget {
  const _SessionOptionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.onEdit,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final void Function(BuildContext anchor)? onEdit;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: description,
      waitDuration: const Duration(milliseconds: 350),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            onChanged(!value);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _Pressable(
          height: 44,
          radius: 10,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          color: FfTokens.nocturneSf,
          hoverColor: FfTokens.sessionHv,
          onPressed: () => onChanged(!value),
          child: Row(
            children: [
              PhosphorIcon(
                icon,
                size: 17,
                color: value ? FfTokens.accentHover : FfTokens.sessionT3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
              ),
              if (onEdit != null && value) ...[
                Builder(
                  builder: (ctx) {
                    return _Pressable(
                      height: 24,
                      radius: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      color: Colors.transparent,
                      hoverColor: FfTokens.sessionHv,
                      hoverForeground: true,
                      foreground: FfTokens.sessionT2,
                      onPressed: () => onEdit!(ctx),
                      child: const PhosphorIcon(
                        PhosphorIconsRegular.pencilSimple,
                        size: 13,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
              ],
              _SessionSwitch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
