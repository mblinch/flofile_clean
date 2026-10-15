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
import '../../../services/verb_admin_choice.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/ff_menu.dart';
import '../../../widgets/caption_layout_builder_dialog.dart';
import '../data/team_abbrev.dart';
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
  int _sportSelectGen = 0;
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
  String _iptcStatus = "Don't write IPTC";
  List<String> _missingCaptionIptc = const [];
  bool _scanningIptc = false;
  int _iptcScanGen = 0;
  bool _ftpModeEnabled = true;
  String? _ftpProfileName;
  List<String> _ftpProfileNames = const [];
  /// When true, the caption Firebar is hidden. Same pref as the session menu.
  bool _hideFirebar = false;
  /// On-device jersey/name OCR + folder pre-scan (macOS). Same pref as the
  /// session header toggle.
  bool _jerseyOcrEnabled = false;
  bool _serialBylinesEnabled = false;
  List<MapEntry<String, String>> _recentMatchups = const [];
  StreamSubscription<void>? _cloudPrefsSub;
  int? _openMenuId;

  CaptionStyleCatalog? _styleCatalog;
  CaptionTemplate? _captionTemplate;
  String? _selectedStyleToken;
  /// Null follows the selected style. A tap pins Wire defaults or Custom.
  bool? _styleTabCustom;
  bool _gettyNoteIsNbae = false;
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
    final parts = <String>[
      if (_writeIptc) 'IPTC',
      if (_ftpModeEnabled) 'FTP',
      if (_jerseyOcrEnabled) 'Text',
    ];
    if (parts.isEmpty) return 'Captions only';
    return 'Captions + ${parts.join(', ')}';
  }

  String get _teamsReadyValue {
    if (_awayFilled && _homeFilled) {
      return '${mlbTeamAbbreviation(_awayTeam!)} @ ${mlbTeamAbbreviation(_homeTeam!)}';
    }
    if (_awayFilled) return mlbTeamAbbreviation(_awayTeam!);
    if (_homeFilled) return mlbTeamAbbreviation(_homeTeam!);
    return 'Not chosen';
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
    _cloudPrefsSub?.cancel();
    _rootFocus.dispose();
    _awayFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _prefs = await PreferencesService.getInstance();
      _cloudPrefsSub ??=
          _prefs!.cloudPreferencesAppliedController.stream.listen((_) {
        unawaited(_reloadRecentMatchups());
      });
      // Match legacy StartupDialog: fetch public appDefaults so skip-sign-in
      // users get Firebase verbs, caption styles, IPTC catalog, game IDs.
      await _prefs!.ensureAppDefaultsHydrated();
      _useOfficialLeagueApis = await _prefs!.getUseOfficialLeagueApis();
      _isAdmin = await AdminService.isCurrentUserAdmin();
      _iptcMode = await _prefs!.getIptcApplyMode();
      if (_iptcMode == IptcApplyMode.onSave) {
        _iptcMode = IptcApplyMode.onImport;
        await _prefs!.saveIptcApplyMode(_iptcMode);
      }
      _iptcStatus = await _iptcStatusFromPrefs();
      _ftpModeEnabled = await _prefs!.getFtpModeEnabled();
      await _loadFtpProfiles();
      _hideFirebar = await _prefs!.getHideFirebar();
      _jerseyOcrEnabled = JerseyOcrChannel.supported &&
          await _prefs!.getJerseyOcrEnabled();
      _serialBylinesEnabled = await _prefs!.getSerialNumberBylines();
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

    final recent = _sport == null
        ? const <MapEntry<String, String>>[]
        : (await _prefs?.getRecentMatchups(sport: _sport!) ??
            const <MapEntry<String, String>>[]);
    final visibleRecent = recent
        .where((e) => names.contains(e.key) && names.contains(e.value))
        .toList();

    if (!mounted) return;
    setState(() {
      _offline = offline;
      _teams = names;
      _loadingTeams = false;
      _homeTeam = home;
      _awayTeam = away;
      _recentMatchups = visibleRecent;
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

  Future<void> _toggleFavoriteTeam(
    String team, {
    required bool isHome,
  }) async {
    if (_sport == null || _prefs == null) return;
    final favs = await _prefs!.getFavoriteTeams(sport: _sport!);
    final prefix = isHome ? 'HOME:' : 'AWAY:';
    final currently = isHome ? _favoriteHome == team : _favoriteAway == team;
    favs.removeWhere((e) => e.startsWith(prefix));
    if (!currently) {
      favs.add('$prefix$team');
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

  void _applyRecentMatchup(String away, String home) {
    if (!_teams.contains(away) || !_teams.contains(home) || away == home) {
      return;
    }
    setState(() {
      _usingCustomRosters = false;
      _awayTeam = away;
      _homeTeam = home;
      _homeRoster = null;
      _awayRoster = null;
    });
  }

  Future<void> _setUseOfficialLeagueApis(bool enabled) async {
    await _prefs?.saveUseOfficialLeagueApis(enabled);
    if (!mounted) return;
    setState(() => _useOfficialLeagueApis = enabled);
  }

  Future<void> _setWriteIptc(bool enabled) async {
    if (enabled == _writeIptc) return;
    final mode = enabled ? IptcApplyMode.onImport : IptcApplyMode.none;
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

  Future<void> _pickFtpProfile(BuildContext anchorContext) async {
    if (_ftpProfileNames.isEmpty) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final picked = await showFfMenu<String>(
      context: anchorContext,
      anchorGlobal: origin & box.size,
      width: 220,
      choices: [
        for (final name in _ftpProfileNames)
          FfMenuChoice<String>(
            value: name,
            selected: name == _ftpProfileName,
            child: Text(name),
          ),
      ],
    );
    final name = picked?.value;
    if (name == null || name == _ftpProfileName) return;
    await _prefs?.saveCurrentFtpProfile(name);
    if (!mounted) return;
    setState(() => _ftpProfileName = name);
  }

  Future<void> _setFtpMode(bool enabled) async {
    if (enabled == _ftpModeEnabled) return;
    await _prefs?.saveFtpModeEnabled(enabled);
    if (!mounted) return;
    setState(() => _ftpModeEnabled = enabled);
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

    if (_writeIptc) {
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Write IPTC?',
        message:
            'Are you sure you want the IPTC to be written to all these photos?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Write IPTC',
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
      await _prefs?.pushRecentMatchup(
        sport: _sport!,
        away: away,
        home: home,
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
    if (_awayFocus.hasFocus || _homeFocus.hasFocus || _openMenuId != null) {
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
        color: FfTokens.nocturneBg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final twoColumn = width >= 880;
            final styleColumns = width <= 640 ? 1 : (twoColumn ? 3 : 2);
            final stackTeams = width <= 640;
            final contentWidth =
                width > 1340 ? 1300.0 : (width - 20).clamp(0.0, 1300.0);
            return Padding(
              padding: const EdgeInsets.all(10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: twoColumn
                      ? _buildWideLayout(
                          t,
                          styleColumns: styleColumns,
                          stackTeams: stackTeams,
                        )
                      : _buildNarrowLayout(
                          t,
                          styleColumns: styleColumns,
                          stackTeams: stackTeams,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    FfTokens t, {
    required int styleColumns,
    required bool stackTeams,
  }) {
    return SizedBox(
      height: 750,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _buildSteps(
                      t,
                      styleColumns: styleColumns,
                      stackTeams: stackTeams,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 400,
            child: _buildSidePanel(t),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(
    FfTokens t, {
    required int styleColumns,
    required bool stackTeams,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSteps(
          t,
          styleColumns: styleColumns,
          stackTeams: stackTeams,
        ),
        const SizedBox(height: 10),
        _buildSidePanel(t),
      ],
    );
  }

  Widget _buildSteps(
    FfTokens t, {
    required int styleColumns,
    required bool stackTeams,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFolderStep(t),
        const SizedBox(height: 10),
        _buildSportStep(t),
        const SizedBox(height: 10),
        _StepCard(
          number: 3,
          title: 'Teams',
          complete: _bothTeamsChosen,
          headerControl: _recentMatchupRow(),
          expandHeader: _recentMatchups.isNotEmpty,
          trailing: _LinkButton(
            label: 'Refresh rosters',
            icon: PhosphorIconsRegular.arrowClockwise,
            onPressed: _sportChosen && !_loadingTeams ? _loadTeams : null,
          ),
          child: _buildTeamsStep(t, stack: stackTeams),
        ),
        const SizedBox(height: 10),
        _StepCard(
          number: 4,
          title: 'Caption style',
          complete: _selectedStyleToken != null,
          headerControl: _styleTabs(),
          trailing: _LinkButton(
            label: 'Edit styles',
            icon: PhosphorIconsRegular.pencilSimple,
            onPressed: _editStyles,
          ),
          child: _buildStyleStep(t, columns: styleColumns),
        ),
        const SizedBox(height: 10),
        _buildSessionStep(t),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.danger,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFolderStep(FfTokens t) {
    final chosen = _folderChosen;
    final prompt = chosen
        ? '${p.basename(_folderPath!)} · ${_imageCount == 1 ? '1 image' : '$_imageCount images'}'
        : 'Drop a folder here';
    return DropTarget(
      onDragEntered: (_) => setState(() => _folderDragOver = true),
      onDragExited: (_) => setState(() => _folderDragOver = false),
      onDragDone: _onFolderDropped,
      child: _StepCard(
        number: 1,
        title: 'Images folder',
        complete: chosen,
        inline: true,
        highlighted: _folderDragOver,
        trailing: _RaisedButton(
          label: _pickingFolder
              ? 'Opening…'
              : (chosen ? 'Change' : 'Choose folder'),
          onPressed: _pickingFolder ? null : _pickFolder,
        ),
        child: _DropSlot(
          emphasized: _folderDragOver,
          child: Text(
            prompt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: chosen ? FfTokens.sessionTx : FfTokens.sessionT2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSportStep(FfTokens t) {
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
    final apiChoice = _isAdmin && soccerNote == null
        ? _AttachedChoice(
            enabled: _sportChosen && _tank01Supported,
            selected: (!_tank01Supported || _useOfficialLeagueApis) ? 1 : 0,
            options: const ['Tank01 APIs', 'Official league APIs'],
            onSelected: (index) => _setUseOfficialLeagueApis(index == 1),
          )
        : null;
    return _StepCard(
      number: 2,
      title: 'Sport',
      complete: _sportChosen,
      inline: true,
      headerControl: SizedBox(
        width: 180,
        child: _SessionSelect(
          value: _sport,
          hint: 'Select sport…',
          options: [
            for (final sport in _sports) (sport, _sportLabel(sport)),
          ],
          onChanged: _selectSport,
        ),
      ),
      child: apiChoice ?? soccerNote,
    );
  }

  Widget _buildTeamsStep(FfTokens t, {required bool stack}) {
    final away = _TeamDropdown(
      menuId: 0,
      openMenuId: _openMenuId,
      label: 'Away',
      value: _awayTeam,
      teams: _sortedTeams(exclude: _homeTeam),
      enabled: _sportChosen && !_loadingTeams,
      sideFavorite: _favoriteAway,
      favoriteNames: _favoriteTeamNames,
      focusNode: _awayFocus,
      hintText: _sportChosen ? 'Select away…' : 'Pick a sport first',
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
      enabled: _sportChosen && !_loadingTeams,
      sideFavorite: _favoriteHome,
      favoriteNames: _favoriteTeamNames,
      focusNode: _homeFocus,
      hintText: _sportChosen ? 'Select home…' : 'Pick a sport first',
      onChanged: _setHomeTeam,
      onToggleFavorite: (team) =>
          unawaited(_toggleFavoriteTeam(team, isHome: true)),
      onMenuOpenChanged: (open) => setState(() {
        _openMenuId = open ? 1 : (_openMenuId == 1 ? null : _openMenuId);
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stack)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              away,
              const SizedBox(height: 8),
              home,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: away),
              const SizedBox(width: 10),
              Expanded(child: home),
            ],
          ),
        if (_loadingTeams && availableTeamsEmpty) ...[
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          const Text(
            'Offline list',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
        const SizedBox(height: 12),
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

  Future<void> _reloadRecentMatchups() async {
    final sport = _sport;
    final prefs = _prefs;
    if (sport == null || prefs == null) return;
    final names = _teams.toSet();
    final recent = await prefs.getRecentMatchups(sport: sport);
    final visible = recent
        .where((e) => names.contains(e.key) && names.contains(e.value))
        .toList();
    if (!mounted) return;
    setState(() => _recentMatchups = visible);
  }

  Widget? _recentMatchupRow() {
    if (_recentMatchups.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Recent',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12,
            color: FfTokens.sessionT3,
          ),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i < _recentMatchups.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _MatchupChip(
            label:
                '${mlbTeamAbbreviation(_recentMatchups[i].key)} @ ${mlbTeamAbbreviation(_recentMatchups[i].value)}',
            onPressed: () => _applyRecentMatchup(
              _recentMatchups[i].key,
              _recentMatchups[i].value,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _setNbae(bool next) async {
    setState(() => _gettyNoteIsNbae = next);
    final prefs = _prefs ?? await PreferencesService.getInstance();
    await prefs.saveGettyNoteIsNbae(next);
  }

  String _styleSubtitle(String token) {
    switch (token) {
      case CaptionStyleCatalog.tokGetty:
      case CaptionStyleCatalog.tokGettyIntl:
      case CaptionStyleCatalog.tokNbae:
        return 'Getty Images';
      case CaptionStyleCatalog.tokAp:
        return 'Associated Press';
      case CaptionStyleCatalog.tokImagn:
        return 'Imagn';
      case CaptionStyleCatalog.tokCp:
        return 'The Canadian Press';
      case CaptionStyleCatalog.tokCustom:
        return 'My layout';
      default:
        return 'Saved layout';
    }
  }

  Widget _styleTabs() {
    final token = _selectedStyleToken;
    final onCustom = _styleTabCustom ??
        (token != null && CaptionStyleCatalog.isCustomMenuToken(token));
    return _AttachedChoice(
      expand: false,
      selected: onCustom ? 1 : 0,
      options: const ['Wire Style Defaults', 'Custom'],
      onSelected: (index) => setState(() => _styleTabCustom = index == 1),
    );
  }

  Widget _buildStyleStep(FfTokens t, {required int columns}) {
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
    final catalog = _styleCatalog;
    if (catalog == null) return const SizedBox.shrink();

    final gettyBasketball = (_sport ?? '').toLowerCase() == 'basketball' &&
        (_selectedStyleToken == CaptionStyleCatalog.tokGetty ||
            _selectedStyleToken == CaptionStyleCatalog.tokGettyIntl);
    final tokens = catalog.options.map((option) => option.token).toList();
    if (tokens.isEmpty) return const SizedBox.shrink();
    final current = tokens.contains(_selectedStyleToken)
        ? _selectedStyleToken!
        : tokens.first;
    final onCustom =
        _styleTabCustom ?? CaptionStyleCatalog.isCustomMenuToken(current);
    final visible = [
      for (final token in tokens)
        if (CaptionStyleCatalog.isCustomMenuToken(token) == onCustom) token,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visible.isEmpty)
          const Text(
            'No styles in this tab.',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final cols = columns.clamp(1, visible.length);
              final tileWidth =
                  (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final token in visible)
                    SizedBox(
                      width: tileWidth,
                      child: _StyleCard(
                        token: token,
                        title: catalog.labelFor(token),
                        subtitle: _styleSubtitle(token),
                        selected: token == current,
                        onPressed: () => unawaited(_selectStyle(token)),
                      ),
                    ),
                ],
              );
            },
          ),
        if (gettyBasketball) ...[
          const SizedBox(height: 12),
          _OptionRow(
            title: 'NBAE credit',
            description:
                'Keeps the NBAE copyright line when the layout includes it',
            value: _gettyNoteIsNbae,
            onChanged: (next) => unawaited(_setNbae(next)),
          ),
        ],
      ],
    );
  }

  Widget _buildSessionStep(FfTokens t) {
    final iptcWarning = _missingCaptionIptc.isNotEmpty && !_scanningIptc;
    final cards = <Widget>[
      _SessionOptionCard(
        icon: PhosphorIconsRegular.uploadSimple,
        title: (_ftpProfileName == null || _ftpProfileName!.isEmpty)
            ? 'No FTP profile'
            : 'FTP: $_ftpProfileName',
        description: 'Sends images with this profile',
        value: _ftpModeEnabled,
        onChanged: (next) => unawaited(_setFtpMode(next)),
        onTitleTap: _ftpProfileNames.isEmpty ? null : _pickFtpProfile,
      ),
      if (JerseyOcrChannel.supported)
        _SessionOptionCard(
          icon: PhosphorIconsRegular.scan,
          title: 'Text recognition',
          description: 'Reads jersey numbers and names in the background',
          value: _jerseyOcrEnabled,
          onChanged: (next) => unawaited(_setJerseyOcr(next)),
        ),
      _SessionOptionCard(
        icon: PhosphorIconsRegular.lightning,
        title: 'Firebar',
        description: 'Keeps the quick-caption bar pinned while you work',
        value: !_hideFirebar,
        onChanged: (next) => unawaited(_setFirebarShown(next)),
      ),
      _SessionOptionCard(
        icon: PhosphorIconsRegular.hash,
        title: 'Serial numbers',
        description: 'Writes the byline according to serial numbers from cameras',
        value: _serialBylinesEnabled,
        onChanged: (next) => unawaited(_setSerialBylines(next)),
      ),
    ];
    return _StepCard(
      number: 5,
      title: 'Session options',
      complete: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionLeadOption(
            icon: PhosphorIconsRegular.pencilSimple,
            title: 'Write IPTC',
            description: iptcWarning
                ? (_iptcWarningText ??
                    'When on, writes over IPTC on every photo when the folder loads')
                : 'When on, writes over IPTC on every photo when the folder loads',
            warn: iptcWarning,
            value: _writeIptc,
            onChanged: (next) => unawaited(_setWriteIptc(next)),
            trailing: _writeIptc
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Pressable(
                      height: 30,
                      radius: 8,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: FfTokens.sessionEl,
                      hoverColor: FfTokens.sessionHv,
                      borderColor: FfTokens.sessionLn2,
                      borderWidth: 1,
                      onPressed: _openIptc,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhosphorIcon(
                            PhosphorIconsRegular.pencilSimple,
                            size: 14,
                            color: FfTokens.sessionTx,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Edit IPTC',
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: FfTokens.sessionTx,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(FfTokens t) {
    final note = _iptcWarningText;
    final noteIsWarning = note != null &&
        _missingCaptionIptc.isNotEmpty &&
        !_scanningIptc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _SideCard(
            expand: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'CAPTION PREVIEW',
                  style: _kSectionLabel,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _CaptionPreviewLive(
                    sport: _sport,
                    awayTeam: _awayTeam,
                    homeTeam: _homeTeam,
                    template: _captionTemplate,
                    gettyNbaeNote: _gettyNoteIsNbae &&
                        (_sport ?? '').toLowerCase() == 'basketball',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('READY CHECK', style: _kSectionLabel),
              const SizedBox(height: 12),
              _ReadyRow(
                label: 'Folder',
                value: _folderChosen ? p.basename(_folderPath!) : 'Not chosen',
                done: _folderChosen,
              ),
              _ReadyRow(
                label: 'Sport',
                value: _sportChosen ? _sportLabel(_sport!) : 'Not chosen',
                done: _sportChosen,
              ),
              _ReadyRow(
                label: 'Teams',
                value: _teamsReadyValue,
                done: _bothTeamsChosen,
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
              const SizedBox(height: 12),
              _GoTimeButton(
                enabled: _canGo,
                loading: _going,
                onPressed: _goTime,
              ),
              const SizedBox(height: 8),
              Text(
                note ??
                    (_canGo ? 'Opens the captioning screen' : _goHint),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  height: 1.4,
                  color: noteIsWarning ? FfTokens.danger : FfTokens.sessionT3,
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
    required this.gettyNbaeNote,
  });

  final String? sport;
  final String? awayTeam;
  final String? homeTeam;
  final CaptionTemplate? template;
  final bool gettyNbaeNote;

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
        applyGettyNoteVariant: true,
        gettyNbaeNote: gettyNbaeNote,
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

    return SingleChildScrollView(
      child: Text.rich(
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
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 15,
          height: 1.6,
          color: FfTokens.sessionTx,
        ),
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

  @override
  Widget build(BuildContext context) {
    final titleStyle = _kBody.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(14, inline ? 8 : 14, 14, inline ? 8 : 14),
      decoration: BoxDecoration(
        color: highlighted ? FfTokens.nocturneSunken : FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? FfTokens.sessionAc : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: inline ? 36 : 28),
            child: SizedBox(
              height: expandHeader ? 30 : null,
              child: Row(
                children: [
                  _StepBadge(number: number, complete: complete),
                  const SizedBox(width: 10),
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
                    const SizedBox(width: 14),
                    Expanded(child: child ?? const SizedBox.shrink()),
                  ],
                  if (expandHeader && headerControl != null) ...[
                    const SizedBox(width: 12),
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
                    const SizedBox(width: 12),
                    headerControl!,
                    if (!inline) const Spacer(),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
          if (!inline && child != null) ...[
            const SizedBox(height: 10),
            child!,
          ],
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
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: complete ? FfTokens.sessionOkSoft : FfTokens.nocturneSunken,
      ),
      child: complete
          ? const PhosphorIcon(
              PhosphorIconsBold.check,
              size: 13,
              color: FfTokens.sessionOk,
            )
          : Text(
              '$number',
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: FfTokens.sessionT2,
                height: 1,
              ),
            ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({required this.child, this.expand = false});

  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: expand ? double.infinity : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FfTokens.nocturneEl,
        borderRadius: BorderRadius.circular(12),
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
  });

  final String? value;
  final String hint;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

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
    return _Pressable(
      height: 36,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FfTokens.nocturneSunken,
      hoverColor: FfTokens.nocturneHv,
      onPressed: () => _open(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasValue ? label : hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
    );
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final picked = await showFfMenu<String>(
      context: context,
      anchorGlobal: origin & box.size,
      width: box.size.width < 180 ? 180 : box.size.width,
      choices: [
        for (final option in options)
          FfMenuChoice<String>(
            value: option.$1,
            selected: option.$1 == value,
            child: Text(option.$2),
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
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.72,
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
            return FfTokens.nocturneAc;
          }
          return FfTokens.nocturneEl;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

class _SessionLeadOption extends StatelessWidget {
  const _SessionLeadOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.warn = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool warn;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PhosphorIcon(icon, size: 16, color: FfTokens.sessionT2),
          const SizedBox(width: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: warn ? FfTokens.danger : FfTokens.sessionTx,
            ),
          ),
          const SizedBox(width: 14),
          _SessionSwitch(
            value: value,
            onChanged: onChanged,
            alignment: Alignment.centerLeft,
          ),
          if (trailing != null) trailing!,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: warn ? FfTokens.danger : FfTokens.sessionT3,
              ),
            ),
          ),
        ],
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
    this.onTitleTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final void Function(BuildContext anchor)? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? FfTokens.nocturneAc : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhosphorIcon(
                  icon,
                  size: 15,
                  color: value ? FfTokens.sessionTx : FfTokens.sessionT2,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final tappable = onTitleTap != null;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: tappable ? () => onTitleTap!(context) : null,
                        child: Row(
                          children: [
                            Flexible(
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
                            if (tappable) ...[
                              const SizedBox(width: 4),
                              const PhosphorIcon(
                                PhosphorIconsRegular.caretDown,
                                size: 12,
                                color: FfTokens.sessionT3,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _SessionSwitch(value: value, onChanged: onChanged),
              ],
            ),
            Text(
              description,
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                height: 1.3,
                color: FfTokens.sessionT3,
              ),
            ),
          ],
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
      height: 32,
      radius: 0,
      padding: expand
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12),
      borderRadius: BorderRadius.horizontal(
        left: i == 0 ? const Radius.circular(10) : Radius.zero,
        right: i == options.length - 1 ? const Radius.circular(10) : Radius.zero,
      ),
      borderColor: i == selected ? FfTokens.nocturneLn2 : Colors.transparent,
      borderWidth: i == selected ? 1 : 0,
      color: i == selected ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
      hoverColor: i == selected ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
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

  @override
  State<_TeamDropdown> createState() => _TeamDropdownState();
}

class _TeamDropdownState extends State<_TeamDropdown> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void didUpdateWidget(covariant _TeamDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entry == null) return;
    final shouldClose = _open && widget.openMenuId != widget.menuId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry == null) return;
      if (shouldClose) {
        _remove(notify: false);
      } else {
        _entry?.markNeedsBuild();
      }
    });
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
    if (notify && wasOpen) widget.onMenuOpenChanged(false);
  }

  Widget _menu() {
    final favorites =
        widget.teams.where(widget.favoriteNames.contains).toList();
    final rest =
        widget.teams.where((t) => !widget.favoriteNames.contains(t)).toList();
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
    final favorite = widget.sideFavorite == name;
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
    final favorited = hasValue && widget.sideFavorite == value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: _kSectionLabel,
        ),
        const SizedBox(height: 6),
        CompositedTransformTarget(
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
              height: 48,
              radius: 10,
              padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
              color: FfTokens.nocturneSunken,
              hoverColor: FfTokens.nocturneHv,
              onPressed: widget.enabled ? _toggle : null,
              child: Row(
                children: [
                  if (hasValue) ...[
                    Container(
                      height: 34,
                      constraints: const BoxConstraints(minWidth: 44, maxWidth: 72),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: FfTokens.nocturneEl,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        mlbTeamAbbreviation(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.48,
                          color: FfTokens.sessionTx,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      hasValue ? value : widget.hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                      color: FfTokens.gold,
                    ),
                    const SizedBox(width: 8),
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
        ),
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

class _MatchupChip extends StatelessWidget {
  const _MatchupChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      height: 28,
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: FfTokens.nocturneSunken,
      hoverColor: FfTokens.nocturneHv,
      hoverForeground: true,
      foreground: FfTokens.sessionT2,
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _Pressable(
      height: 30,
      radius: 7,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.transparent,
      hoverColor: enabled ? FfTokens.nocturneSunken : Colors.transparent,
      hoverForeground: enabled,
      foreground: enabled ? FfTokens.sessionT2 : FfTokens.sessionT3,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            PhosphorIcon(icon!, size: 15),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaisedButton extends StatelessWidget {
  const _RaisedButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _Pressable(
      height: 36,
      radius: 9,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: FfTokens.nocturneSunken,
      hoverColor: enabled ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: enabled ? FfTokens.sessionTx : FfTokens.sessionT3,
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.token,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  final String token;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mark = _wordmark(token, title);
    return _Pressable(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: selected ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
      hoverColor: FfTokens.nocturneHv,
      borderColor: selected ? FfTokens.sessionTx : Colors.transparent,
      borderWidth: 2,
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mark.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mark.style,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              letterSpacing: 0.2,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
      ),
    );
  }

  static ({String text, TextStyle style}) _wordmark(String token, String title) {
    const base = TextStyle(
      color: FfTokens.sessionTx,
      height: 1,
    );
    switch (token) {
      case CaptionStyleCatalog.tokGetty:
      case CaptionStyleCatalog.tokGettyIntl:
      case CaptionStyleCatalog.tokNbae:
        return (
          text: 'GETTY',
          style: base.copyWith(
            fontFamily: FfTokens.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: 4.4,
          ),
        );
      case CaptionStyleCatalog.tokImagn:
        return (
          text: 'imagn',
          style: base.copyWith(
            fontFamily: 'InterTight',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        );
      case CaptionStyleCatalog.tokAp:
        return (
          text: 'AP',
          style: base.copyWith(
            fontFamily: 'InterTight',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        );
      case CaptionStyleCatalog.tokCp:
        return (
          text: 'CP',
          style: base.copyWith(
            fontFamily: FfTokens.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: 5,
          ),
        );
      default:
        return (
          text: title,
          style: base.copyWith(
            fontFamily: FfTokens.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        );
    }
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({
    required this.label,
    required this.value,
    required this.done,
  });

  final String label;
  final String value;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          PhosphorIcon(
            done ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.circle,
            size: 16,
            color: done ? FfTokens.sessionOk : FfTokens.sessionT3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                color: FfTokens.sessionT2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: done ? FontWeight.w600 : FontWeight.w500,
                color: done ? FfTokens.sessionTx : FfTokens.sessionT3,
              ),
            ),
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
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_GoTimeButton> createState() => _GoTimeButtonState();
}

class _GoTimeButtonState extends State<_GoTimeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !widget.loading;
    final bg = !widget.enabled
        ? FfTokens.nocturneSunken
        : (_hover ? FfTokens.sessionGoHover : FfTokens.sessionTx);
    final fg = widget.enabled ? FfTokens.nocturneBg : FfTokens.sessionT3;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.loading ? 'Starting…' : 'Go time',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (!widget.loading) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? FfTokens.sessionKbd
                        : FfTokens.nocturneHv,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '↵',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ],
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
          alignment: Alignment.center,
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
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
