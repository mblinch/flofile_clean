import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_style_catalog.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/game_info.dart';
import '../../../config/tank01_config.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_manager.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/current_user_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/jersey_ocr_channel.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/caption_layout_builder_dialog.dart';
import 'caption_v2_iptc_dialog.dart';
import 'roster_import_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
  PreferencesService? _prefs;

  String? _sport;
  String? _folderPath;
  int _imageCount = 0;
  String? _homeTeam;
  String? _awayTeam;
  List<Player>? _homeRoster;
  List<Player>? _awayRoster;

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
  bool _useOfficialLeagueApis = false;
  bool _isAdmin = false;
  IptcApplyMode _iptcMode = IptcApplyMode.none;
  IptcApplyMode _preferredWriteMode = IptcApplyMode.onSave;
  String _iptcStatus = "Don't write IPTC";
  List<String> _missingCaptionIptc = const [];
  bool _scanningIptc = false;
  int _iptcScanGen = 0;
  bool _ftpModeEnabled = true;
  /// On-device jersey/name OCR + folder pre-scan (macOS). Same pref as the
  /// session header toggle.
  bool _jerseyOcrEnabled = false;

  CaptionStyleCatalog? _styleCatalog;
  CaptionTemplate? _captionTemplate;
  String? _selectedStyleToken;
  bool _loadingStyles = true;

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

  /// Go Time requires folder + sport + both teams (per redesign).
  bool get _canGo =>
      _sportChosen && _folderChosen && _bothTeamsChosen && !_going;

  bool get _writeIptc => _iptcMode != IptcApplyMode.none;

  bool get _tank01Supported => _sport != null && tank01SupportsSport(_sport!);

  Set<String> get _favoriteTeamNames {
    final out = <String>{};
    if (_favoriteHome != null) out.add(_favoriteHome!);
    if (_favoriteAway != null) out.add(_favoriteAway!);
    return out;
  }

  String get _apiLabel {
    if (!_sportChosen) return '';
    final official = _isAdmin && _useOfficialLeagueApis && _tank01Supported;
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

  String get _outputLabel {
    if (_writeIptc && _ftpModeEnabled) return 'IPTC + FTP';
    if (_writeIptc) return 'IPTC';
    if (_ftpModeEnabled) return 'FTP';
    return 'Captions only';
  }

  String get _goHint {
    if (_canGo) {
      final n = _imageCount;
      return n == 1 ? '1 image ready' : '$n images ready';
    }
    final missing = <String>[];
    if (!_folderChosen) missing.add('a folder');
    if (!_sportChosen) missing.add('a sport');
    if (!_bothTeamsChosen) missing.add('both teams');
    if (missing.isEmpty) return 'Complete setup to start.';
    if (missing.length == 1) return 'Add ${missing.first} to start.';
    if (missing.length == 2) {
      return 'Add ${missing[0]} and ${missing[1]} to start.';
    }
    return 'Add ${missing[0]}, ${missing[1]} and ${missing[2]} to start.';
  }

  String? get _iptcWarningText {
    if (!_folderChosen) return null;
    if (_scanningIptc) return 'Scanning folder IPTC for caption fields…';
    if (_missingCaptionIptc.isEmpty) return null;
    final fields = _missingCaptionIptc.join(', ');
    if (_writeIptc) {
      return 'Missing IPTC for caption: $fields';
    }
    return 'Missing IPTC for caption: $fields — turn on Write IPTC or fix files';
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

  Future<void> _bootstrap() async {
    try {
      _prefs = await PreferencesService.getInstance();
      // Match legacy StartupDialog: fetch public appDefaults so skip-sign-in
      // users get Firebase verbs, caption styles, IPTC catalog, game IDs.
      await _prefs!.ensureAppDefaultsHydrated();
      _useOfficialLeagueApis = await _prefs!.getUseOfficialLeagueApis();
      _isAdmin = await AdminService.isCurrentUserAdmin();
      _iptcMode = await _prefs!.getIptcApplyMode();
      if (_iptcMode != IptcApplyMode.none) {
        _preferredWriteMode = _iptcMode;
      }
      _iptcStatus = await _iptcStatusFromPrefs();
      _ftpModeEnabled = await _prefs!.getFtpModeEnabled();
      _jerseyOcrEnabled = JerseyOcrChannel.supported &&
          await _prefs!.getJerseyOcrEnabled();
      await _loadCaptionStyles();
      await _refreshIptcCaptionWarning();
      if (!mounted) return;
      setState(() {});

      final savedSport = (await _prefs!.getCurrentSport()).trim();
      if (savedSport.isNotEmpty && _sports.contains(savedSport)) {
        await _selectSport(savedSport, persist: false, restoreTeams: true);
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
        return "Don't write IPTC";
      case IptcApplyMode.onImport:
        return 'Write IPTC on import · $label';
      case IptcApplyMode.onSave:
        return 'Write IPTC on save · $label';
    }
  }

  Future<void> _loadCaptionStyles() async {
    setState(() => _loadingStyles = true);
    try {
      final prefs = _prefs ?? await PreferencesService.getInstance();
      final catalog =
          await CaptionStyleCatalog.load(prefs, sport: _sport);
      final template = await prefs.getCaptionTemplate();
      // Overlay sport-correct game ID for built-in wires so the side preview
      // never shows a stale league (e.g. NHL during baseball).
      final sportAware = _sportChosen
          ? await prefs.applyGameIdentifierForSport(
              template,
              template.wireStyle,
              _sport!,
            )
          : template;
      if (!mounted) return;
      setState(() {
        _styleCatalog = catalog;
        _captionTemplate = sportAware;
        _selectedStyleToken = catalog.activeToken;
        _loadingStyles = false;
      });
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
    _favoriteHome = null;
    _favoriteAway = null;
    for (final t in favs) {
      if (t.startsWith('HOME:')) _favoriteHome = t.substring(5);
      if (t.startsWith('AWAY:')) _favoriteAway = t.substring(5);
    }
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
    String? home;
    String? away;

    if (_favoriteHome != null && names.contains(_favoriteHome)) {
      home = _favoriteHome;
    }
    if (_favoriteAway != null &&
        names.contains(_favoriteAway) &&
        _favoriteAway != home) {
      away = _favoriteAway;
    }

    if (restoreLastTeams || (home == null && away == null)) {
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
    setState(() {
      _offline = offline;
      _teams = names;
      _loadingTeams = false;
      _homeTeam = home;
      _awayTeam = away;
      _error = error;
    });
  }

  Future<void> _setFolder(String path) async {
    final files = await _imageFilesInFolder(path);
    if (!mounted) return;
    setState(() {
      _folderPath = path;
      _imageCount = files.length;
      _pickingFolder = false;
      _folderDragOver = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_images_folder', path);
    } catch (_) {}
    await _refreshIptcCaptionWarning();
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

  Future<void> _toggleFavorite({required bool isHome}) async {
    final team = isHome ? _homeTeam : _awayTeam;
    if (team == null || _sport == null || _prefs == null) return;
    final favs = await _prefs!.getFavoriteTeams(sport: _sport!);
    final key = isHome ? 'HOME:$team' : 'AWAY:$team';
    final prefix = isHome ? 'HOME:' : 'AWAY:';
    favs.removeWhere((e) => e.startsWith(prefix));
    final currently = isHome ? _favoriteHome == team : _favoriteAway == team;
    if (!currently) {
      favs.add(key);
      if (isHome) {
        _favoriteHome = team;
      } else {
        _favoriteAway = team;
      }
    } else {
      if (isHome) {
        _favoriteHome = null;
      } else {
        _favoriteAway = null;
      }
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
    final mode = enabled ? _preferredWriteMode : IptcApplyMode.none;
    await _prefs?.saveIptcApplyMode(mode);
    final status = await _iptcStatusFromPrefs();
    if (!mounted) return;
    setState(() {
      _iptcMode = mode;
      _iptcStatus = status;
    });
    await _refreshIptcCaptionWarning();
  }

  Future<void> _refreshIptcCaptionWarning() async {
    final prefs = _prefs;
    final gen = ++_iptcScanGen;
    final folder = _folderPath?.trim() ?? '';
    if (prefs == null || folder.isEmpty) {
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _missingCaptionIptc = const [];
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
      var wire = WireStyle.getty;
      for (final t in visible) {
        if (t.id == selectedId) {
          wire = t.wireStyle;
          break;
        }
      }
      if (visible.isEmpty) {
        for (final w in WireStyle.values) {
          if (AppDefaultsFirestoreService.templateIdForWire(w) == selectedId) {
            wire = w;
            break;
          }
        }
      }

      // 1) Scan a sample of images from the chosen folder.
      final files = await _imageFilesInFolder(folder);
      if (gen != _iptcScanGen) return;
      final sample = files.take(8).toList();
      final fromFiles = <String, String>{};
      if (sample.isNotEmpty) {
        final batch =
            await IptcTemplateImportService.readMetadataBatch(sample);
        if (gen != _iptcScanGen) return;
        for (final meta in batch.values) {
          final panel = IptcTemplateImportService.panelValuesFromExiftool(meta);
          panel.forEach((k, v) {
            final trimmed = v.trim();
            if (trimmed.isEmpty) return;
            if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
              return;
            }
            fromFiles.putIfAbsent(k, () => trimmed);
          });
        }
      }

      // 2) If Write IPTC is on, template values fill gaps (on import/save).
      final effective = Map<String, String>.from(fromFiles);
      if (_writeIptc) {
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
        templatePanel.forEach((k, v) {
          final trimmed = v.trim();
          if (trimmed.isEmpty) return;
          if (IptcTemplateApplyService.isInAppGeneratedPlaceholder(trimmed)) {
            return;
          }
          effective.putIfAbsent(k, () => trimmed);
        });
      }

      final captionTemplate = _captionTemplate ?? CaptionTemplate.getty();
      final missing = CaptionFormulaRenderer.missingCaptionIptcLabels(
        template: captionTemplate,
        game: IptcTemplateApplyService.gameInfoFromPanelValues(effective),
        includeCreator: false,
      );
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _missingCaptionIptc = missing;
        _scanningIptc = false;
      });
    } catch (_) {
      if (!mounted || gen != _iptcScanGen) return;
      setState(() {
        _missingCaptionIptc = const [];
        _scanningIptc = false;
      });
    }
  }

  Future<void> _setFtpMode(bool enabled) async {
    if (enabled == _ftpModeEnabled) return;
    await _prefs?.saveFtpModeEnabled(enabled);
    if (!mounted) return;
    setState(() => _ftpModeEnabled = enabled);
  }

  Future<void> _setJerseyOcr(bool enabled) async {
    if (enabled == _jerseyOcrEnabled) return;
    await _prefs?.saveJerseyOcrEnabled(enabled);
    if (!mounted) return;
    setState(() => _jerseyOcrEnabled = enabled);
  }

  Future<void> _openIptc() async {
    final summary = await showCaptionV2IptcDialog(
      context,
      folderPath: _folderPath,
    );
    if (!mounted || summary == null) return;
    await _refreshIptcCaptionWarning();
    if (!mounted) return;
    setState(() {
      _iptcMode = summary.mode;
      if (summary.mode != IptcApplyMode.none) {
        _preferredWriteMode = summary.mode;
      }
      _iptcStatus = summary.statusLine;
    });
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
    });
  }

  Future<void> _selectStyle(String token) async {
    final catalog = _styleCatalog;
    if (catalog == null || token == _selectedStyleToken) return;
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
    await _refreshIptcCaptionWarning();
  }

  Future<void> _editStyles() async {
    final applied = await CaptionLayoutBuilderDialog.show(context);
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

  void _swapTeams() {
    setState(() {
      final tmp = _homeTeam;
      _homeTeam = _awayTeam;
      _awayTeam = tmp;
      final tmpRoster = _homeRoster;
      _homeRoster = _awayRoster;
      _awayRoster = tmpRoster;
      // Favorites stay side-specific; only swap selections.
      _usingCustomRosters = false;
    });
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
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_awayFocus.hasFocus || _homeFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
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
    setState(() {
      _usingCustomRosters = false;
      _awayTeam = team;
      if (team != null && team == _homeTeam) {
        _homeTeam = null;
      }
      _homeRoster = null;
      _awayRoster = null;
    });
  }

  void _setHomeTeam(String? team) {
    setState(() {
      _usingCustomRosters = false;
      _homeTeam = team;
      if (team != null && team == _awayTeam) {
        _awayTeam = null;
      }
      _homeRoster = null;
      _awayRoster = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: t.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final width = constraints.maxWidth.clamp(0.0, 1200.0);
            final height = constraints.maxHeight.clamp(0.0, 780.0);
            return Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: width,
                height: height,
                child: wide
                    ? _buildWideLayout(t)
                    : _buildNarrowLayout(t),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(FfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 60, child: _buildSteps(t)),
                const SizedBox(width: 16),
                Expanded(flex: 40, child: _buildSidePanel(t)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(FfTokens t) {
    // Still no page scroll — stack and let columns share height.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _buildSteps(t),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 2,
            child: _buildSidePanel(t),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: 2,
          child: _StepCard(
            number: 1,
            title: 'Images folder',
            complete: _folderChosen,
            child: _buildFolderStep(t),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          flex: 2,
          child: _StepCard(
            number: 2,
            title: 'Sport',
            complete: _sportChosen,
            child: _buildSportStep(t),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          flex: 3,
          child: _StepCard(
            number: 3,
            title: 'Teams',
            complete: _bothTeamsChosen,
            trailing: _GhostButton(
              label: 'Refresh rosters',
              icon: PhosphorIconsRegular.arrowClockwise,
              onPressed: _sportChosen && !_loadingTeams ? _loadTeams : null,
            ),
            child: _buildTeamsStep(t),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          flex: 3,
          child: _StepCard(
            number: 4,
            title: 'Caption style',
            complete: _selectedStyleToken != null,
            trailing: _GhostButton(
              label: 'Edit styles',
              onPressed: _editStyles,
            ),
            child: _buildStyleStep(t),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          flex: 3,
          child: _StepCard(
            number: 5,
            title: 'Session options',
            complete: true,
            child: _buildSessionStep(t),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11.5,
              color: t.accent,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFolderStep(FfTokens t) {
    final chosen = _folderChosen;
    final borderColor = _folderDragOver
        ? t.accent
        : chosen
            ? t.divider
            : const Color(0x38E4EAF2); // rgba(228,234,242,.22)
    final bg = _folderDragOver ? t.selected : t.sunken;

    final useDashed = !chosen && !_folderDragOver;

    return Align(
      alignment: Alignment.centerLeft,
      child: DropTarget(
      onDragEntered: (_) => setState(() => _folderDragOver = true),
      onDragExited: (_) => setState(() => _folderDragOver = false),
      onDragDone: _onFolderDropped,
      child: CustomPaint(
        painter: useDashed
            ? _DashedRRectPainter(
                color: borderColor,
                radius: 8,
              )
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: useDashed
                ? null
                : Border.all(color: borderColor, width: 1),
          ),
          child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: t.elevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.divider),
              ),
              child: PhosphorIcon(PhosphorIconsRegular.folder,
                size: 16,
                color: chosen ? FfTokens.statusSaved : t.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: chosen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(_folderPath!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _imageCount == 1
                              ? '1 image'
                              : '$_imageCount images',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 11,
                            color: t.textTertiary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Drop a folder here',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'or choose one from your computer',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 11,
                            color: t.textTertiary,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 10),
            _OutlinedAction(
              label: _pickingFolder
                  ? 'Opening…'
                  : (chosen ? 'Change' : 'Choose folder'),
              onPressed: _pickingFolder ? null : _pickFolder,
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  Widget _buildSportStep(FfTokens t) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _sports)
              _SportChip(
                label: _sportLabel(s),
                selected: _sport == s,
                onTap: () => _selectSport(s),
              ),
          ],
        ),
        if (_sport == 'soccer') ...[
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: true,
                  onChanged: null,
                  activeColor: t.accent,
                  checkColor: t.inkOnAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Always use ESPN MLS rosters for soccer',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11.5,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ] else if (_isAdmin) ...[
          const SizedBox(height: 6),
          _OptionRow(
            title: 'Official league APIs',
            description: _tank01Supported
                ? 'On: sports/… APIs · Off: Tank01 Firebase (default)'
                : _apiLabel,
            value: _useOfficialLeagueApis && _tank01Supported,
            enabled: _sportChosen && _tank01Supported,
            onChanged: _setUseOfficialLeagueApis,
          ),
        ],
      ],
      ),
    );
  }

  Widget _buildTeamsStep(FfTokens t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _TeamDropdown(
                label: 'Away',
                value: _awayTeam,
                teams: _sortedTeams(exclude: _homeTeam),
                excludeTeam: _homeTeam,
                enabled: _sportChosen && !_loadingTeams,
                favorited:
                    _awayTeam != null && _favoriteAway == _awayTeam,
                favoriteNames: _favoriteTeamNames,
                focusNode: _awayFocus,
                hintText:
                    _sportChosen ? 'Select away…' : 'Pick a sport first',
                onChanged: _setAwayTeam,
                onToggleFavorite: () => _toggleFavorite(isHome: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 2),
              child: _SwapButton(
                enabled: _sportChosen,
                onPressed: _swapTeams,
              ),
            ),
            Expanded(
              child: _TeamDropdown(
                label: 'Home',
                value: _homeTeam,
                teams: _sortedTeams(exclude: _awayTeam),
                excludeTeam: _awayTeam,
                enabled: _sportChosen && !_loadingTeams,
                favorited:
                    _homeTeam != null && _favoriteHome == _homeTeam,
                favoriteNames: _favoriteTeamNames,
                focusNode: _homeFocus,
                hintText:
                    _sportChosen ? 'Select home…' : 'Pick a sport first',
                onChanged: _setHomeTeam,
                onToggleFavorite: () => _toggleFavorite(isHome: true),
              ),
            ),
          ],
        ),
        if (_loadingTeams && availableTeamsEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Loading team list…',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              color: t.textTertiary,
            ),
          ),
        ],
        if (_offline && _sportChosen) ...[
          const SizedBox(height: 6),
          Text(
            'Offline list',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              color: t.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _PasteRosterButton(
          enabled: _sportChosen,
          pastedCount: _usingCustomRosters
              ? (_awayRoster?.length ?? 0) + (_homeRoster?.length ?? 0)
              : 0,
          onPressed: _sportChosen ? _pasteRoster : null,
        ),
      ],
    );
  }

  bool get availableTeamsEmpty => _teams.isEmpty;

  Widget _buildStyleStep(FfTokens t) {
    if (_loadingStyles) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final catalog = _styleCatalog;
    if (catalog == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in catalog.options)
                SizedBox(
                  width: _styleCardWidth(constraints.maxWidth),
                  child: _StyleCard(
                    name: opt.label,
                    description: _styleDescription(opt.token, opt.label),
                    selected: _selectedStyleToken == opt.token,
                    onTap: () => _selectStyle(opt.token),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _styleCardWidth(double maxWidth) {
    // Approximate CSS: repeat(auto-fill, minmax(150px, 1fr))
    const gap = 8.0;
    const min = 150.0;
    final cols = ((maxWidth + gap) / (min + gap)).floor().clamp(1, 4);
    return (maxWidth - gap * (cols - 1)) / cols;
  }

  String _styleDescription(String token, String label) {
    final lower = label.toLowerCase();
    if (token == CaptionStyleCatalog.tokGetty ||
        token == CaptionStyleCatalog.tokGettyIntl) {
      return 'Dateline, full sentence, credit';
    }
    if (token == CaptionStyleCatalog.tokAp ||
        token == CaptionStyleCatalog.tokCp) {
      return 'City (STATE) — shorter form';
    }
    if (lower.contains('short')) {
      return 'Name and action only';
    }
    if (token == CaptionStyleCatalog.tokImagn) {
      return 'Agency wire style';
    }
    if (token.startsWith('saved:')) {
      return 'Custom saved layout';
    }
    return 'Custom caption layout';
  }

  Widget _buildSessionStep(FfTokens t) {
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OptionRow(
          title: 'Write IPTC',
          description: (_missingCaptionIptc.isNotEmpty && !_scanningIptc)
              ? (_iptcWarningText ??
                  "Embed the caption in each image's metadata")
              : "Embed the caption in each image's metadata",
          value: _writeIptc,
          onChanged: _setWriteIptc,
          trailing: _GhostButton(
            label: 'Edit IPTC',
            onPressed: _folderChosen || _writeIptc ? _openIptc : null,
          ),
          warning: _missingCaptionIptc.isNotEmpty && !_scanningIptc,
        ),
        const SizedBox(height: 6),
        _OptionRow(
          title: 'FTP Mode',
          description: 'Adds an FTP button to send images as you go',
          value: _ftpModeEnabled,
          onChanged: _setFtpMode,
        ),
        if (JerseyOcrChannel.supported) ...[
          const SizedBox(height: 6),
          _OptionRow(
            title: 'Text Recognition',
            description:
                'Reads jersey numbers and names, and pre-loads the folder '
                'in the background so each frame is ready',
            value: _jerseyOcrEnabled,
            onChanged: _setJerseyOcr,
          ),
        ],
      ],
      ),
    );
  }

  Widget _buildSidePanel(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _SideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CAPTION PREVIEW',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: t.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _CaptionPreviewLive(
                      sport: _sport,
                      awayTeam: _awayTeam,
                      homeTeam: _homeTeam,
                      template: _captionTemplate,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'READY CHECK',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              _ReadyRow(
                label: 'Folder',
                value: _folderChosen
                    ? p.basename(_folderPath!)
                    : 'Not chosen',
                done: _folderChosen,
              ),
              _ReadyRow(
                label: 'Sport',
                value: _sportChosen ? _sportLabel(_sport!) : 'Not chosen',
                done: _sportChosen,
              ),
              _ReadyRow(
                label: 'Away',
                value: _awayTeam ?? 'Not chosen',
                done: _awayTeam != null && _awayTeam!.trim().isNotEmpty,
              ),
              _ReadyRow(
                label: 'Home',
                value: _homeTeam ?? 'Not chosen',
                done: _homeTeam != null && _homeTeam!.trim().isNotEmpty,
              ),
              _ReadyRow(
                label: 'Style',
                value: _styleCatalog != null && _selectedStyleToken != null
                    ? _styleCatalog!.labelFor(_selectedStyleToken!)
                    : 'Not chosen',
                done: _selectedStyleToken != null,
              ),
              _ReadyRow(
                label: 'Output',
                value: _outputLabel,
                done: true,
              ),
              if (_folderChosen)
                _ReadyRow(
                  label: 'IPTC',
                  value: _scanningIptc
                      ? 'Scanning folder…'
                      : (_missingCaptionIptc.isEmpty
                          ? 'Caption fields ready'
                          : 'Missing ${_missingCaptionIptc.join(', ')}'),
                  done: !_scanningIptc && _missingCaptionIptc.isEmpty,
                  warning: !_scanningIptc && _missingCaptionIptc.isNotEmpty,
                ),
              const SizedBox(height: 8),
              _GoTimeButton(
                enabled: _canGo,
                loading: _going,
                onPressed: _goTime,
              ),
              const SizedBox(height: 4),
              Text(
                _iptcWarningText ?? _goHint,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: (_iptcWarningText != null &&
                          _missingCaptionIptc.isNotEmpty &&
                          !_scanningIptc)
                      ? FfTokens.danger
                      : t.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _sportLabel(String s) {
    switch (s) {
      case 'wnba':
        return 'WNBA';
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
    required this.template,
  });

  final String? sport;
  final String? awayTeam;
  final String? homeTeam;
  final CaptionTemplate? template;

  static const _awayPlaceholder = 'Away team';
  static const _homePlaceholder = 'Home team';
  static const _periodPlaceholder = 'period';
  static const _leaguePlaceholder = 'league';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
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

    final leagueId = hasSport
        ? defaultGameIdentifierText(sportKey)
        : 'in their $_leaguePlaceholder';
    final timing = hasSport
        ? CaptionFormulaRenderer.previewTimePhraseForSport(sportKey)
        : 'in the $_periodPlaceholder';

    final action = _actionFor(sportKey, timing);
    final body =
        '$away #00 Heater Ace $action against the $home $timing ahead of their ${leagueId.replaceFirst('in their ', '')}';

    final game = GameInfo(
      gameDate: DateTime.now(),
      city: 'Los Angeles',
      region: 'California',
      regionCode: 'CA',
      country: 'United States',
      countryCode: 'USA',
      venue: 'Los Angeles Sports Stadium',
      photographerName: CurrentUserService.displayNameOrPlaceholder(),
      agencyName: '',
    );

    final agency = _agencyFor(tpl.wireStyle);
    // Force sport-correct game identifier even if the stored template is stale.
    final previewTemplate = hasSport
        ? CaptionTemplate.applyGameIdentifierText(tpl, leagueId)
        : tpl.copyWith(gameIdentifierText: leagueId);

    // Prefer a full formula render when we have a template; fall back to body.
    String caption;
    try {
      caption = CaptionFormulaRenderer.render(
        template: previewTemplate,
        game: game,
        sampleAgency: agency,
        captionOverride:
            '$away #00 Heater Ace $action against the $home $timing',
        sport: hasSport ? sportKey : null,
      );
    } catch (_) {
      caption =
          'Los Angeles, California, USA. $body at Los Angeles Sports Stadium '
          '${_weekday(game.gameDate!)}. '
          '${game.photographerName}/${CaptionFormulaRenderer.defaultAgencyLabel(agency)}';
    }

    // If sport is unset, ensure period/league placeholders appear.
    if (!hasSport) {
      caption = caption
          .replaceAll(
            RegExp(
              r'\b(in the third period|during the third inning|in the fourth quarter|in the second half)\b',
              caseSensitive: false,
            ),
            'in the $_periodPlaceholder',
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
          text: t.text,
          filledColor: t.text,
          missingColor: t.textTertiary,
          filledUnderline: t.accentEdge,
          missingUnderline: const Color(0x6BE4EAF2), // --text-3-ish for dashed
        ),
      ),
      style: const TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: 13.5,
        height: 1.55,
      ),
    );
  }

  static String _actionFor(String sport, String timing) {
    switch (sport) {
      case 'hockey':
        return 'scores a goal';
      case 'basketball':
      case 'wnba':
        return 'dunks';
      case 'soccer':
        return 'scores a goal';
      case 'baseball':
        return 'hits a home run';
      default:
        return 'scores a goal';
    }
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
    required Color filledColor,
    required Color missingColor,
    required Color filledUnderline,
    required Color missingUnderline,
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
        style: TextStyle(
          color: m.filled ? filledColor : missingColor,
          fontWeight: m.filled ? FontWeight.w600 : FontWeight.w400,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dashed,
          decorationColor: m.filled ? filledUnderline : missingUnderline,
          decorationThickness: 1.25,
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

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _Mark {
  const _Mark(this.start, this.end, {required this.filled});
  final int start;
  final int end;
  final bool filled;
}

// ---------------------------------------------------------------------------
// Shared chrome widgets
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.complete,
    required this.child,
    this.trailing,
  });

  final int number;
  final String title;
  final bool complete;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: t.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withValues(alpha: 0.85)),
        boxShadow: FfTokens.accentButtonGlow(t.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StepBadge(number: number, complete: complete),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                    shadows: [
                      Shadow(
                        color: (complete ? t.accent : t.text)
                            .withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.number, required this.complete});

  final int number;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: complete ? t.selected : Colors.transparent,
        border: Border.all(
          color: complete ? t.accent : t.accentEdge,
        ),
        boxShadow: complete ? FfTokens.accentButtonGlow(t.accent) : null,
      ),
      alignment: Alignment.center,
      child: complete
          ? PhosphorIcon(
              PhosphorIconsRegular.check,
              size: 8,
              color: t.accent,
            )
          : Text(
              '$number',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withValues(alpha: 0.85)),
        boxShadow: FfTokens.accentButtonGlow(t.accent),
      ),
      child: child,
    );
  }
}

class _SportChip extends StatelessWidget {
  const _SportChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? t.selected : t.sunken,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? t.accent : t.divider),
            boxShadow:
                selected ? FfTokens.accentButtonGlow(t.accent) : null,
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? t.text : t.textSecondary,
                shadows: selected
                    ? [
                        Shadow(
                          color: t.accent.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? t.selected : t.sunken,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: selected ? t.accent : t.divider),
            boxShadow:
                selected ? FfTokens.accentButtonGlow(t.accent) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                  shadows: selected
                      ? [
                          Shadow(
                            color: t.accent.withValues(alpha: 0.45),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: t.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final Widget? trailing;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final titleColor = enabled ? t.text : t.textSecondary;
    final descColor = warning
        ? FfTokens.danger
        : (enabled ? t.textTertiary : t.textTertiary);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                  color: titleColor,
                ),
              ),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  height: 1.2,
                  color: descColor,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 8),
        ],
        _Switch38(
          value: value,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Switch38 extends StatelessWidget {
  const _Switch38({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? () => onChanged(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              // Off = --hv track; on = --ac track.
              color: value ? t.accent : t.hover,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // On = --bg knob; off = muted knob.
                color: value ? t.bg : t.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamDropdown extends StatelessWidget {
  const _TeamDropdown({
    required this.label,
    required this.value,
    required this.teams,
    this.excludeTeam,
    required this.enabled,
    required this.favorited,
    required this.favoriteNames,
    required this.hintText,
    required this.onChanged,
    required this.onToggleFavorite,
    required this.focusNode,
  });

  final String label;
  final String? value;
  final List<String> teams;
  final String? excludeTeam;
  final bool enabled;
  final bool favorited;
  final Set<String> favoriteNames;
  final String hintText;
  final ValueChanged<String?> onChanged;
  final VoidCallback onToggleFavorite;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final effective =
        (value != null && teams.contains(value)) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12.5,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: Stack(
            children: [
              DropdownButtonFormField<String?>(
                key: ValueKey(
                  '$label:$effective:${excludeTeam ?? ''}:$enabled:${teams.length}',
                ),
                focusNode: focusNode,
                initialValue: effective,
                isExpanded: true,
                dropdownColor: t.elevated,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  color: t.text,
                ),
                iconEnabledColor: t.textSecondary,
                iconDisabledColor: t.textTertiary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    color: t.textTertiary,
                  ),
                  filled: true,
                  fillColor: t.sunken,
                  contentPadding: const EdgeInsets.fromLTRB(12, 10, 40, 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: t.accent),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: t.divider),
                  ),
                ),
                items: [
                  for (final name in teams)
                    DropdownMenuItem<String?>(
                      value: name,
                      child: Text(
                        favoriteNames.contains(name) ? '★ $name' : name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 13,
                          color: t.text,
                        ),
                      ),
                    ),
                ],
                onChanged: enabled && teams.isNotEmpty
                    ? (v) {
                        if (v != null &&
                            excludeTeam != null &&
                            v == excludeTeam) {
                          return;
                        }
                        onChanged(v);
                      }
                    : null,
              ),
              Positioned(
                right: 28,
                top: 0,
                bottom: 0,
                child: IconButton(
                  onPressed: effective == null || !enabled
                      ? null
                      : onToggleFavorite,
                  icon: Text(
                    favorited ? '★' : '☆',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1,
                      color: favorited
                          ? FfTokens.favorites
                          : t.textTertiary,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: 'Favorite $label team',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: t.sunken,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.divider),
            ),
            alignment: Alignment.center,
            child: Text(
              '⇄',
              style: TextStyle(
                fontSize: 16,
                color: enabled ? t.text : t.textTertiary,
              ),
            ),
          ),
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
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final pasted = pastedCount > 0;
    final color = enabled ? t.accent : t.textTertiary;
    return Material(
      color: enabled ? t.accent.withValues(alpha: 0.12) : t.sunken,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? t.accent.withValues(alpha: 0.85) : t.divider,
            ),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.clipboardText,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste rosters',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: enabled ? t.text : t.textTertiary,
                      ),
                    ),
                    Text(
                      pasted
                          ? '$pastedCount players pasted'
                          : 'From a webpage or other source',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        color: pasted ? FfTokens.statusSaved : t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                size: 14,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                PhosphorIcon(
                  icon!,
                  size: 14,
                  color: enabled ? t.textSecondary : t.textTertiary,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: enabled ? t.textSecondary : t.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = onPressed != null;
    return Material(
      color: t.sunken,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: enabled ? t.accentEdge : t.divider),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: enabled ? t.text : t.textTertiary,
              ),
            ),
          ),
      ),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({
    required this.label,
    required this.value,
    required this.done,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool done;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final markColor = warning
        ? FfTokens.danger
        : (done ? t.accent : t.divider);
    final valueColor = warning
        ? FfTokens.danger
        : (done ? t.text : t.textTertiary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: markColor),
              color: done && !warning ? t.selected : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: done && !warning
                ? PhosphorIcon(
                    PhosphorIconsRegular.check,
                    size: 7,
                    color: t.accent,
                  )
                : (warning
                    ? const PhosphorIcon(
                        PhosphorIconsRegular.warning,
                        size: 7,
                        color: FfTokens.danger,
                      )
                    : null),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12.5,
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12.5,
                fontWeight: done || warning ? FontWeight.w500 : FontWeight.w400,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoTimeButton extends StatelessWidget {
  const _GoTimeButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: enabled ? FfTokens.accentButtonGlow(t.accent) : null,
      ),
      child: Material(
        color: enabled ? t.selected : t.elevated,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled && !loading ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: enabled ? t.accent : t.divider,
              ),
            ),
            child: Text(
              loading ? 'Loading…' : 'Go time ↵',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled ? t.text : t.textTertiary,
                shadows: enabled
                    ? [
                        Shadow(
                          color: t.accent.withValues(alpha: 0.5),
                          blurRadius: 7,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
