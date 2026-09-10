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
import 'caption_v2_iptc_dialog.dart';
import 'roster_import_dialog.dart';

/// Result handed from the V2 startup screen into the caption session.
class CaptionV2StartupResult {
  const CaptionV2StartupResult({
    required this.sport,
    required this.folderPath,
    required this.homeTeam,
    required this.awayTeam,
    required this.burstDetectionEnabled,
    this.homeRoster,
    this.awayRoster,
  });

  final String sport;
  final String folderPath;
  final String homeTeam;
  final String awayTeam;
  final bool burstDetectionEnabled;
  final List<Player>? homeRoster;
  final List<Player>? awayRoster;
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
  bool _burstDetection = true;

  List<String> _teams = const [];
  bool _loadingTeams = false;
  bool _offline = false;
  bool _pickingFolder = false;
  bool _going = false;
  bool _usingCustomRosters = false;
  String? _error;

  String? _favoriteHome;
  String? _favoriteAway;
  bool _useTank01 = false;
  bool _isAdmin = false;
  IptcApplyMode _iptcMode = IptcApplyMode.none;
  IptcApplyMode _preferredWriteMode = IptcApplyMode.onSave;
  String _iptcStatus = "Don't write IPTC";

  static const _sports = <String>[
    'baseball',
    'hockey',
    'basketball',
    'wnba',
    'soccer',
  ];

  bool get _sportChosen => _sport != null && _sport!.isNotEmpty;
  bool get _folderChosen => _folderPath != null && _folderPath!.isNotEmpty;
  bool get _teamsChosen =>
      _homeTeam != null &&
      _awayTeam != null &&
      _homeTeam!.isNotEmpty &&
      _awayTeam!.isNotEmpty &&
      _homeTeam != _awayTeam;
  bool get _canGo => _sportChosen && _folderChosen && _teamsChosen && !_going;

  bool get _writeIptc => _iptcMode != IptcApplyMode.none;

  bool get _tank01Supported => _sport != null && tank01SupportsSport(_sport!);

  String get _apiLabel {
    if (!_sportChosen) return '';
    final tank01 = _useTank01 && _tank01Supported;
    switch (_sport) {
      case 'baseball':
        return tank01 ? 'Tank01 MLB' : 'MLB Stats API';
      case 'hockey':
        return tank01 ? 'Tank01 NHL' : 'NHL API';
      case 'basketball':
        return tank01 ? 'Tank01 NBA' : 'ESPN NBA';
      case 'wnba':
        return tank01 ? 'Tank01 WNBA' : 'ESPN WNBA';
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
      _burstDetection = await _prefs!.getBurstDetectionEnabled();
      _useTank01 = await _prefs!.getUseTank01Rosters();
      _isAdmin = await AdminService.isCurrentUserAdmin();
      _iptcMode = await _prefs!.getIptcApplyMode();
      if (_iptcMode != IptcApplyMode.none) {
        _preferredWriteMode = _iptcMode;
      }
      _iptcStatus = await _iptcStatusFromPrefs();
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

  Future<void> _setTank01(bool enabled) async {
    await _prefs?.saveUseTank01Rosters(enabled);
    if (!mounted) return;
    setState(() => _useTank01 = enabled);
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
    setState(() => _going = true);
    await _prefs?.saveBurstDetectionEnabled(_burstDetection);
    await _prefs?.saveUseTank01Rosters(_useTank01);
    if (_sport != null) {
      try {
        await _prefs?.saveCurrentSport(_sport!);
      } catch (_) {}
    }
    widget.onComplete(
      CaptionV2StartupResult(
        sport: _sport!,
        folderPath: _folderPath!,
        homeTeam: _homeTeam!,
        awayTeam: _awayTeam!,
        burstDetectionEnabled: _burstDetection,
        homeRoster: _homeRoster,
        awayRoster: _awayRoster,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New Flo File Session',
                  style: t.labelStyle.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 12),
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
                        ),
                      ),
                      const SizedBox(width: 12),
                      _OutlinedBtn(
                        label: _pickingFolder ? 'Opening…' : 'Choose folder',
                        onPressed: _pickingFolder ? null : _pickFolder,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
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
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _useTank01,
                                activeColor: t.accent,
                                checkColor: t.inkOnAccent,
                                side: BorderSide(
                                  color: _tank01Supported
                                      ? t.textSecondary
                                      : t.divider,
                                ),
                                onChanged: !_sportChosen || !_tank01Supported
                                    ? null
                                    : (v) => _setTank01(v ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _tank01Supported
                                    ? 'Use Tank01 rosters (skip Firebase) — MLB/NBA/NHL/WNBA'
                                    : 'Tank01 unavailable for soccer (MLS stays ESPN)',
                                maxLines: 2,
                                style: t.metaStyle.copyWith(
                                  color: _tank01Supported
                                      ? t.text
                                      : t.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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
                          const SizedBox(width: 12),
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Section(
                  title: 'Custom rosters',
                  unlocked: _sportChosen,
                  selected: _usingCustomRosters,
                  child: _RosterPasteButton(
                    playerCount: _awayRoster == null && _homeRoster == null
                        ? null
                        : (_awayRoster?.length ?? 0) +
                            (_homeRoster?.length ?? 0),
                    onPressed: _pasteRoster,
                  ),
                ),
                const SizedBox(height: 10),
                _Section(
                  title: 'Session',
                  unlocked: _teamsChosen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _burstDetection,
                              activeColor: t.accent,
                              checkColor: t.inkOnAccent,
                              side: BorderSide(color: t.textSecondary),
                              onChanged: !_teamsChosen
                                  ? null
                                  : (v) => setState(
                                        () => _burstDetection = v ?? true,
                                      ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Burst detection', style: t.bodyStyle),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _writeIptc,
                              activeColor: t.accent,
                              checkColor: t.inkOnAccent,
                              side: BorderSide(color: t.textSecondary),
                              onChanged: !_teamsChosen
                                  ? null
                                  : (v) => _setWriteIptc(v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Write IPTC', style: t.bodyStyle),
                          const SizedBox(width: 10),
                          _OutlinedBtn(
                            label: 'IPTC…',
                            onPressed: !_teamsChosen || !_writeIptc
                                ? null
                                : _openIptc,
                          ),
                        ],
                      ),
                      if (_writeIptc) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 30),
                          child: Text(
                            _iptcStatus,
                            style: t.metaStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: t.metaStyle.copyWith(color: t.accent)),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: _OutlinedBtn(
                    label: _going ? 'Loading…' : 'Go Time',
                    emphasized: true,
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
        padding: const EdgeInsets.all(10),
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
                Text(title.toUpperCase(), style: t.microStyle),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            IgnorePointer(ignoring: !unlocked, child: child),
          ],
        ),
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.selectedFill : t.badgeFill,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(
            color: selected ? t.selectedBorder : t.divider,
          ),
        ),
        child: Text(
          label,
          style: t.chipStyle.copyWith(
            color: selected ? t.text : t.textSecondary,
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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

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
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: t.accent, width: 1.5),
            ),
            child: Text(label, style: t.labelStyle),
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
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  for (final name in teams)
                    DropdownMenuItem<String>(
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
