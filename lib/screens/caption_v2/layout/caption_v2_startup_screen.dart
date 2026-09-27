import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/tank01_config.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_manager.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/native_file_picker.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/startup_caption_layout_preview.dart';
import 'caption_v2_iptc_dialog.dart';
import 'roster_import_dialog.dart';

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
  });

  final String sport;
  final String folderPath;
  final String homeTeam;
  final String awayTeam;
  final List<Player>? homeRoster;
  final List<Player>? awayRoster;

  /// When true, the session has one roster only ([homeTeam]); [awayTeam] is empty.
  final bool singleTeamMode;
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
  PreferencesService? _prefs;

  String? _sport;
  String? _folderPath;
  String? _homeTeam;
  String? _awayTeam;
  List<Player>? _homeRoster;
  List<Player>? _awayRoster;

  List<String> _teams = const [];
  bool _loadingTeams = false;
  bool _offline = false;
  bool _pickingFolder = false;
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
  bool _ftpModeEnabled = true;

  static const _sports = <String>[
    'baseball',
    'hockey',
    'basketball',
    'wnba',
    'soccer',
  ];

  bool get _sportChosen => _sport != null && _sport!.isNotEmpty;
  bool get _folderChosen => _folderPath != null && _folderPath!.isNotEmpty;

  bool get _homeFilled => _homeTeam != null && _homeTeam!.isNotEmpty;
  bool get _awayFilled => _awayTeam != null && _awayTeam!.isNotEmpty;

  /// Exactly one side filled → single-team session.
  bool get _inferredSingleTeam =>
      (_homeFilled && !_awayFilled) || (!_homeFilled && _awayFilled);

  bool get _teamsChosen {
    if (_inferredSingleTeam) return true;
    if (!_homeFilled || !_awayFilled) return false;
    return _homeTeam != _awayTeam;
  }

  bool get _canGo => _sportChosen && _folderChosen && _teamsChosen && !_going;

  bool get _writeIptc => _iptcMode != IptcApplyMode.none;

  bool get _tank01Supported => _sport != null && tank01SupportsSport(_sport!);

  String get _apiLabel {
    if (!_sportChosen) return '';
    final official = _isAdmin && _useOfficialLeagueApis && _tank01Supported;
    final tank01Fb = _tank01Supported && !official;
    switch (_sport) {
      case 'baseball':
        return tank01Fb
            ? 'Tank01 Firebase (MLB)'
            : 'MLB Stats API';
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _prefs = await PreferencesService.getInstance();
      _useOfficialLeagueApis = await _prefs!.getUseOfficialLeagueApis();
      _isAdmin = await AdminService.isCurrentUserAdmin();
      _iptcMode = await _prefs!.getIptcApplyMode();
      if (_iptcMode != IptcApplyMode.none) {
        _preferredWriteMode = _iptcMode;
      }
      _iptcStatus = await _iptcStatusFromPrefs();
      _ftpModeEnabled = await _prefs!.getFtpModeEnabled();
      if (!mounted) return;
      setState(() {});
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

  Future<void> _selectSport(String sport, {bool persist = true}) async {
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
    });
    try {
      _api.setSport(sport);
      if (persist) {
        // Persist only when the user taps a sport (not on cold auto-highlight).
        // Defer cloud-heavy save work so a chip tap can't hang / race the UI.
        unawaited(() async {
          try {
            await _prefs?.saveCurrentSport(sport);
          } catch (e) {
            debugPrint('saveCurrentSport failed: $e');
          }
        }());
      }
      await _loadFavorites(sport);
      await _loadTeams();
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

  Future<void> _loadTeams() async {
    if (!_sportChosen) return;
    setState(() {
      _loadingTeams = true;
      _error = null;
    });
    try {
      final teams = await _api.fetchTeams();
      if (!mounted) return;
      final names = teams.map((t) => t.name).toSet().toList()..sort();
      setState(() {
        _offline = false;
        _teams = names;
        _loadingTeams = false;
        if (_favoriteHome != null && names.contains(_favoriteHome)) {
          _homeTeam = _favoriteHome;
        }
        if (_favoriteAway != null && names.contains(_favoriteAway)) {
          _awayTeam = _favoriteAway;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offline = true;
        _teams = _fallbackTeams(_sport!);
        _loadingTeams = false;
        _error = 'Teams loaded offline — check network to refresh.';
        if (_favoriteHome != null && _teams.contains(_favoriteHome)) {
          _homeTeam = _favoriteHome;
        }
        if (_favoriteAway != null && _teams.contains(_favoriteAway)) {
          _awayTeam = _favoriteAway;
        }
      });
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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_images_folder', result);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _folderPath = result;
        _pickingFolder = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickingFolder = false;
        _error = 'Could not open folder: $e';
      });
    }
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
  }

  Future<void> _setFtpMode(bool enabled) async {
    if (enabled == _ftpModeEnabled) return;
    await _prefs?.saveFtpModeEnabled(enabled);
    if (!mounted) return;
    setState(() => _ftpModeEnabled = enabled);
  }

  Future<void> _openIptc() async {
    final summary = await showCaptionV2IptcDialog(
      context,
      folderPath: _folderPath,
    );
    if (!mounted || summary == null) return;
    setState(() {
      _iptcMode = summary.mode;
      if (summary.mode != IptcApplyMode.none) {
        _preferredWriteMode = summary.mode;
      }
      _iptcStatus = summary.statusLine;
    });
  }

  Future<void> _pasteRoster() async {
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

    widget.onComplete(
      CaptionV2StartupResult(
        sport: _sport!,
        folderPath: _folderPath!,
        homeTeam: home,
        awayTeam: away,
        homeRoster: homeRoster,
        awayRoster: awayRoster,
        singleTeamMode: single,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return ColoredBox(
      color: t.bg,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New Flo File Session',
                  style: t.labelStyle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 8),
                _Section(
                  title: 'Images folder',
                  unlocked: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _folderPath == null
                              ? 'No folder selected'
                              : _folderPath!,
                          style: _folderPath == null
                              ? t.secondaryLabelStyle
                              : t.monoMetaStyle.copyWith(color: t.text),
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _OutlinedBtn(
                        label: _pickingFolder ? 'Opening…' : 'Choose folder',
                        compact: true,
                        onPressed: _pickingFolder ? null : _pickFolder,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _Section(
                  title: 'Sport',
                  unlocked: _folderChosen,
                  trailing: Text(
                    _sportChosen ? _apiLabel : ' ',
                    style: t.metaStyle,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Shrink-wrapped pills on one row (Wrap only if the window is tiny).
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in _sports)
                            _Chip(
                              label: _sportLabel(s),
                              selected: _sport == s,
                              onTap: () => _selectSport(s),
                            ),
                        ],
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: _useOfficialLeagueApis,
                                activeColor: t.accent,
                                checkColor: t.inkOnAccent,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide(
                                  color: _tank01Supported
                                      ? t.textSecondary
                                      : t.divider,
                                ),
                                onChanged: !_sportChosen || !_tank01Supported
                                    ? null
                                    : (v) =>
                                        _setUseOfficialLeagueApis(v ?? false),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _tank01Supported
                                    ? 'Use official league APIs (sports/…) — default is Tank01 Firebase'
                                    : 'Soccer always uses ESPN MLS',
                                maxLines: 2,
                                style: t.metaStyle.copyWith(
                                  color: _tank01Supported
                                      ? t.text
                                      : t.textSecondary,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _Section(
                  title: 'Teams',
                  unlocked: _sportChosen,
                  dimmed: _usingCustomRosters,
                  trailing: SizedBox(
                    height: 14,
                    child: _loadingTeams
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.accent,
                            ),
                          )
                        : (_offline
                            ? Text('Offline list', style: t.metaStyle)
                            : TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 14),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _sportChosen ? _loadTeams : null,
                                child: Text(
                                  'Refresh',
                                  style: t.metaStyle.copyWith(color: t.accent),
                                ),
                              )),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _TeamPicker(
                              label: 'Away',
                              value: _awayTeam,
                              teams: _teams,
                              enabled: _sportChosen && !_loadingTeams,
                              favorited: _awayTeam != null &&
                                  _favoriteAway == _awayTeam,
                              onChanged: (v) => setState(() {
                                _usingCustomRosters = false;
                                _awayTeam = v;
                                _homeRoster = null;
                                _awayRoster = null;
                              }),
                              onToggleFavorite: () =>
                                  _toggleFavorite(isHome: false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TeamPicker(
                              label: 'Home',
                              value: _homeTeam,
                              teams: _teams,
                              enabled: _sportChosen && !_loadingTeams,
                              favorited: _homeTeam != null &&
                                  _favoriteHome == _homeTeam,
                              onChanged: (v) => setState(() {
                                _usingCustomRosters = false;
                                _homeTeam = v;
                                _awayRoster = null;
                                _homeRoster = null;
                              }),
                              onToggleFavorite: () =>
                                  _toggleFavorite(isHome: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _RosterPasteButton(
                        playerCount: _awayRoster == null && _homeRoster == null
                            ? null
                            : (_awayRoster?.length ?? 0) +
                                (_homeRoster?.length ?? 0),
                        onPressed: _pasteRoster,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _Section(
                  title: 'Caption style',
                  unlocked: _sportChosen,
                  child: StartupCaptionLayoutPreview(
                    sport: _sport,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 6),
                _Section(
                  title: 'Session',
                  unlocked: _teamsChosen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: Text('Write IPTC', style: t.bodyStyle),
                          ),
                          _OnOffPills(
                            value: _writeIptc,
                            enabled: _teamsChosen,
                            onChanged: _setWriteIptc,
                          ),
                          const SizedBox(width: 8),
                          _PillSizedBtn(
                            label: 'Edit IPTC',
                            onPressed: !_teamsChosen || !_writeIptc
                                ? null
                                : _openIptc,
                          ),
                        ],
                      ),
                      if (_writeIptc) ...[
                        const SizedBox(height: 4),
                        Text(
                          _iptcStatus,
                          style: t.metaStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: Text('FTP mode', style: t.bodyStyle),
                          ),
                          _OnOffPills(
                            value: _ftpModeEnabled,
                            enabled: _teamsChosen,
                            onChanged: _setFtpMode,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Enables FTP button',
                            style: t.metaStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: t.metaStyle.copyWith(color: t.accent)),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _OutlinedBtn(
                    label: _going ? 'Loading…' : 'Go Time',
                    emphasized: true,
                    compact: true,
                    onPressed: _canGo ? _goTime : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _OnOffPills extends StatelessWidget {
  const _OnOffPills({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  /// Matches [_PillSizedBtn] / segment row height.
  static const double height = 26;

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>()!;
    Widget seg({required String label, required bool selected, required bool on}) {
      return Material(
        color: selected ? const Color(0xFF3A4050) : Colors.transparent,
        child: InkWell(
          onTap: !enabled || selected ? null : () => onChanged(on),
          child: SizedBox(
            height: height - 2, // inside 1px border
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    color: !enabled
                        ? t.text.withValues(alpha: 0.28)
                        : selected
                            ? t.text
                            : t.text.withValues(alpha: 0.42),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg(label: 'On', selected: value, on: true),
            Container(width: 1, height: height - 2, color: t.divider),
            seg(label: 'Off', selected: !value, on: false),
          ],
        ),
      ),
    );
  }
}

/// Compact outlined control matching [_OnOffPills] height; greys out when disabled.
class _PillSizedBtn extends StatelessWidget {
  const _PillSizedBtn({
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: _OnOffPills.height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled ? t.divider : t.divider.withValues(alpha: 0.55),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w500,
                color: enabled
                    ? t.text
                    : t.text.withValues(alpha: 0.42),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.unlocked,
    required this.child,
    this.trailing,
    this.dimmed = false,
    this.selected = false,
  });

  final String title;
  final bool unlocked;
  final Widget child;
  final Widget? trailing;
  final bool dimmed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Opacity(
      opacity: unlocked && !dimmed ? 1 : 0.4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? t.selectedFill : t.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          border: Border.all(
            color: selected ? t.selectedBorder : t.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: FfTokens.railLabel.copyWith(
                    color: t.text.withValues(alpha: 0.70),
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            IgnorePointer(ignoring: !unlocked, child: child),
          ],
        ),
      ),
    );
  }
}

/// Compact selectable pill matching [_OnOffPills] / [_PillSizedBtn].
class _Chip extends StatelessWidget {
  const _Chip({
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
          height: _OnOffPills.height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3A4050) : t.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.divider),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w500,
                color: selected
                    ? t.text
                    : t.text.withValues(alpha: 0.42),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  const _OutlinedBtn({
    required this.label,
    this.onPressed,
    this.emphasized = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        type: emphasized ? MaterialType.canvas : MaterialType.transparency,
        color: emphasized ? t.badgeFill : null,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 28 : 40),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 16,
              vertical: compact ? 5 : 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: t.accent, width: 1.5),
            ),
            child: Text(
              label,
              style: compact
                  ? t.labelStyle.copyWith(fontSize: 11)
                  : t.labelStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterPasteButton extends StatelessWidget {
  const _RosterPasteButton({
    required this.playerCount,
    required this.onPressed,
  });

  final int? playerCount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final imported = playerCount != null;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: imported ? t.selectedFill : t.badgeFill,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(
                color: imported ? t.selectedBorder : t.divider,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  imported ? Icons.check : Icons.content_paste_outlined,
                  size: 16,
                  color: imported ? t.text : t.textSecondary,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    imported
                        ? '$playerCount players pasted'
                        : 'Paste rosters copied from webpage or other source',
                    style: t.metaStyle.copyWith(
                      color: imported ? t.text : t.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
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

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({
    required this.label,
    required this.value,
    required this.teams,
    required this.enabled,
    required this.favorited,
    required this.onChanged,
    required this.onToggleFavorite,
  });

  final String label;
  final String? value;
  final List<String> teams;
  final bool enabled;
  final bool favorited;
  final ValueChanged<String?> onChanged;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final effectiveValue =
        (value != null && teams.contains(value)) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: t.metaStyle),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('$label:$effectiveValue'),
                initialValue: effectiveValue,
                isExpanded: true,
                dropdownColor: t.surface,
                style: t.bodyStyle,
                iconEnabledColor: t.textSecondary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: teams.isEmpty ? 'Loading…' : 'Select $label…',
                  hintStyle: t.secondaryLabelStyle,
                  filled: true,
                  fillColor: t.sunken,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'None',
                      style: t.secondaryLabelStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final name in teams)
                    DropdownMenuItem<String?>(
                      value: name,
                      child: Text(
                        name,
                        style: t.bodyStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled && teams.isNotEmpty ? onChanged : null,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed:
                  effectiveValue == null || !enabled ? null : onToggleFavorite,
              icon: Icon(
                favorited ? Icons.star : Icons.star_border,
                size: 18,
                color: favorited ? t.accent : t.textSecondary,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: 'Favorite $label team',
            ),
          ],
        ),
      ],
    );
  }
}
