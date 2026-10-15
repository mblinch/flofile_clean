import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/sport_verb_categories.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../flo_layout_constants.dart';
import '../theme/auth_ui_constants.dart';
import '../services/admin_service.dart';
import '../services/api_manager.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/auth_service.dart';
import '../config/tank01_config.dart';
import '../services/preferences_service.dart';
import '../services/roster_compare_service.dart';
import '../services/roster_issues_service.dart';
import '../services/tank01_roster_sync_service.dart';
import '../caption_style/verb_sub_options.dart';
import '../caption_style/verb_defaults_bundle.dart';
import '../theme/ff_glow.dart';
import '../theme/ff_tokens.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'admin_verb_authoring_editor.dart';
import 'verb_edit_plural_field.dart';
import 'verb_edit_sub_options_section.dart';
import 'caption_layout_builder_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _AdminSection { verbs, captionStructures, rosterCompare, rosterIssues }

/// Admin console for editing app originals (verbs + caption structures).
class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    this.openRosterCompare = false,
  });

  /// When true, opens on the Tank01 vs Firebase roster compare tab.
  final bool openRosterCompare;

  static Future<void> open(
    BuildContext context, {
    bool openRosterCompare = false,
    Future<void> Function()? onClosed,
  }) async {
    final isAdmin = await AdminService.isCurrentUserAdmin();
    if (!context.mounted) return;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => AdminScreen(openRosterCompare: openRosterCompare),
    );
    if (onClosed != null) await onClosed();
  }

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late PreferencesService _prefs;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  late _AdminSection _section;

  AppDefaultsCatalog? _catalog;
  final Map<String, Map<String, dynamic>> _verbBundles = {};
  String _verbSport = 'baseball';

  WireStyle _captionWire = WireStyle.getty;
  String _captionSport = 'baseball';
  final Map<WireStyle, CaptionTemplate> _captionDrafts = {};
  final Map<WireStyle, Map<String, CaptionTemplate>> _captionByWireAndSport =
      {};
  final Map<WireStyle, Map<String, String>> _gameIdDrafts = {};
  int _captionBuilderRevision = 0;
  Future<void> Function()? _flushCaptionBuilder;

  List<String> _compareTeamNames = const [];
  String _compareSport = 'baseball';
  String? _compareTeamA;
  String? _compareTeamB;
  bool _compareLoadingTeams = false;
  bool _compareRunning = false;
  String? _compareError;
  List<RosterCompareReport> _compareReports = const [];
  bool _tank01SyncRunning = false;
  String? _tank01SyncStatus;

  final _issuesService = RosterIssuesService();
  List<RosterIssue> _rosterIssues = const [];
  bool _issuesScanning = false;
  bool _issuesSaving = false;
  String? _issuesError;
  String? _issuesStatus;
  String _issuesSportFilter = 'all';

  static const _sports = AppDefaultsFirestoreService.catalogSports;
  static const _dialogWidth = 1180.0;
  static const _dialogHeight = 780.0;
  static const _sidebarWidth = 180.0;
  static const _contentPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _section = widget.openRosterCompare
        ? _AdminSection.rosterCompare
        : _AdminSection.verbs;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _prefs = await PreferencesService.getInstance();
      await AppDefaultsFirestoreService.loadCacheFromDisk();
      await AppDefaultsFirestoreService.fetchAndCacheAppDefaults(
        forceNetwork: true,
      );
      _catalog = AppDefaultsFirestoreService.getCachedCatalog();
      _verbBundles.clear();
      for (final sport in _sports) {
        _verbBundles[sport] = await _sportBundleForAdmin(sport);
      }
      final currentSport =
          (await _prefs.getCurrentSport()).toLowerCase().trim();
      final sport = _sports.contains(currentSport) ? currentSport : 'baseball';
      _verbSport = sport;
      _captionSport = sport;
      _compareSport = sport;
      _loadCaptionDraftsFromCatalog(_catalog);
      _captureCaptionBaseline();
      _captionDirty = false;
      _captionBuilderRevision++;
      if (_compareTeamNames.isEmpty) {
        unawaited(_loadTeamsForCompare());
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTeamsForCompare() async {
    if (!mounted) return;
    setState(() {
      _compareLoadingTeams = true;
      _compareError = null;
      _compareTeamA = null;
      _compareTeamB = null;
      _compareReports = const [];
    });
    try {
      final api = ApiManager()..setSport(_compareSport);
      final teams = await api.fetchTeams();
      final names = teams.map((t) => t.name).toList()..sort();
      if (!mounted) return;
      setState(() {
        _compareTeamNames = names;
        _compareTeamA = names.isNotEmpty ? names.first : null;
        _compareTeamB = names.length > 1
            ? names[1]
            : (names.isNotEmpty ? names.first : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _compareError = 'Failed to load $_compareSport teams: $e');
    } finally {
      if (mounted) setState(() => _compareLoadingTeams = false);
    }
  }

  Future<void> _scanRosterIssues() async {
    setState(() {
      _issuesScanning = true;
      _issuesError = null;
      _issuesStatus =
          'Scanning sports_tank01 for missing and duplicate jersey numbers…';
    });
    try {
      final sport = _issuesSportFilter == 'all' ? null : _issuesSportFilter;
      final issues = await _issuesService.scanIssues(sportId: sport);
      if (!mounted) return;
      final missing =
          issues.where((i) => i.kind == RosterIssueKind.missingJersey).length;
      final duplicates =
          issues.where((i) => i.kind == RosterIssueKind.duplicateJersey).length;
      setState(() {
        _rosterIssues = issues;
        if (issues.isEmpty) {
          _issuesStatus = 'No jersey issues found.';
        } else {
          final parts = <String>[];
          if (missing > 0) {
            parts.add('$missing missing');
          }
          if (duplicates > 0) {
            parts.add('$duplicates duplicate');
          }
          _issuesStatus =
              'Found ${issues.length} issue(s): ${parts.join(', ')}.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _issuesError = e.toString();
        _issuesStatus = null;
      });
    } finally {
      if (mounted) setState(() => _issuesScanning = false);
    }
  }

  Future<void> _fixJerseyIssue(RosterIssue issue) async {
    final controller = TextEditingController(
      text: issue.jerseyNumber?.trim() ?? '',
    );
    final jersey = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx).extension<FfTokens>() ?? FfTokens.dark;
        return AppDialogFfStyle(
          enabled: true,
          child: Theme(
            data: Theme.of(ctx).copyWith(
              extensions: <ThemeExtension<dynamic>>[t],
            ),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 380,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                  border: Border.all(color: t.divider),
                  boxShadow: [
                    BoxShadow(
                      color: t.bg.withValues(alpha: 0.55),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Set jersey number',
                                style: TextStyle(
                                  fontFamily: FfTokens.labelFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: t.text,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cancel',
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: PhosphorIcon(
                                PhosphorIconsRegular.x,
                                size: 16,
                                color: t.text.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: t.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${issue.teamName} · ${issue.fullName}',
                              style: t.metaStyle.copyWith(
                                color: t.text.withValues(alpha: 0.70),
                              ),
                            ),
                            if (issue.detail != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                issue.detail!,
                                style: t.metaStyle.copyWith(
                                  color: t.text.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            AppDialogLabeledField(
                              label: 'Jersey number',
                              bottomGap: 0,
                              child: AppDialogControlShell(
                                child: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: t.metaStyle.copyWith(
                                    fontSize: 11,
                                    color: t.text,
                                    height: 1.25,
                                  ),
                                  cursorColor: t.accent,
                                  decoration: appDialogBareFieldDecoration(),
                                  onSubmitted: (v) {
                                    final next = v.trim();
                                    if (next.isEmpty) return;
                                    Navigator.of(ctx).pop(next);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: Row(
                          children: [
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(
                                'Cancel',
                                style: t.metaStyle.copyWith(
                                  color: t.text.withValues(alpha: 0.62),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedGreyButton(
                              label: 'Save',
                              fontSize: 11,
                              isPrimary: true,
                              onPressed: () {
                                final next = controller.text.trim();
                                if (next.isEmpty) return;
                                Navigator.of(ctx).pop(next);
                              },
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
        );
      },
    );
    controller.dispose();
    if (jersey == null || jersey.isEmpty || !mounted) return;

    setState(() {
      _issuesSaving = true;
      _issuesError = null;
    });
    try {
      await _issuesService.setVerifiedJersey(
        issue: issue,
        jerseyNumber: jersey,
      );
      if (!mounted) return;
      final savedMsg =
          'Saved #$jersey for ${issue.fullName}. Sync keeps this number until they change teams.';
      await _scanRosterIssues();
      if (!mounted) return;
      setState(() {
        final scan = _issuesStatus;
        _issuesStatus =
            scan == null || scan.isEmpty ? savedMsg : '$savedMsg $scan';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _issuesError = e.toString());
    } finally {
      if (mounted) setState(() => _issuesSaving = false);
    }
  }

  Future<void> _openPlayerGoogleSearch(RosterIssue issue) async {
    final sport = issue.sportId.toLowerCase().trim();
    String league;
    switch (sport) {
      case 'hockey':
        league = 'NHL';
        break;
      case 'baseball':
        league = 'MLB';
        break;
      case 'basketball':
        league = 'NBA';
        break;
      case 'wnba':
        league = 'WNBA';
        break;
      case 'soccer':
        league = 'soccer';
        break;
      default:
        league = SportVerbCategories.displayLabel(issue.sportId);
    }
    final name = issue.fullName.trim();
    final query = name.isEmpty ? '$league player' : '$league player $name';
    final url = Uri.https('www.google.com', '/search', {'q': query}).toString();
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Google search: $e')),
      );
    }
  }

  Future<void> _runRosterCompare() async {
    final teams = <String>{
      if (_compareTeamA != null && _compareTeamA!.trim().isNotEmpty)
        _compareTeamA!.trim(),
      if (_compareTeamB != null &&
          _compareTeamB!.trim().isNotEmpty &&
          _compareTeamB != _compareTeamA)
        _compareTeamB!.trim(),
    }.toList();
    if (teams.isEmpty) {
      setState(() => _compareError = 'Pick at least one team.');
      return;
    }
    if (!tank01SupportsSport(_compareSport)) {
      setState(() => _compareError =
          'Tank01 compare is not available for $_compareSport (no Tank01 product).');
      return;
    }
    setState(() {
      _compareRunning = true;
      _compareError = null;
      _compareReports = const [];
    });
    try {
      final service = RosterCompareService();
      final reports = <RosterCompareReport>[];
      for (final team in teams) {
        reports.add(await service.compareTeam(team, sportId: _compareSport));
      }
      if (!mounted) return;
      setState(() => _compareReports = reports);
    } catch (e) {
      if (!mounted) return;
      setState(() => _compareError = e.toString());
    } finally {
      if (mounted) setState(() => _compareRunning = false);
    }
  }

  Future<void> _syncTank01ToFirestore({required bool allSports}) async {
    if (!tank01SupportsSport(_compareSport) && !allSports) {
      setState(() =>
          _compareError = 'Tank01 sync is not available for $_compareSport.');
      return;
    }
    setState(() {
      _tank01SyncRunning = true;
      _tank01SyncStatus = 'Starting Tank01 → sports_tank01 sync…';
      _compareError = null;
    });
    try {
      final results = await Tank01RosterSyncService().sync(
        sportId: allSports ? null : _compareSport,
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _tank01SyncStatus = msg);
        },
      );
      if (!mounted) return;
      final teams = results.fold<int>(0, (n, r) => n + r.teamsSynced);
      final players = results.fold<int>(0, (n, r) => n + r.playersWritten);
      final errors = results.expand((r) => r.errors).toList();
      setState(() {
        _tank01SyncStatus =
            'Synced $teams teams / $players players into sports_tank01'
            '${errors.isEmpty ? '' : ' (${errors.length} errors)'}';
        if (errors.isNotEmpty) {
          _compareError = errors.take(8).join('\n');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tank01SyncStatus = null;
        _compareError = 'Tank01 sync failed: $e';
      });
    } finally {
      if (mounted) setState(() => _tank01SyncRunning = false);
    }
  }

  Map<String, dynamic> _sportBundleFromCatalog(String sport) {
    final fromCatalog = _catalog?.sportVerbSettings(sport);
    if (fromCatalog != null && fromCatalog.isNotEmpty) {
      final raw = Map<String, dynamic>.from(fromCatalog);
      if (VerbDefaultsBundle.looksCollapsedIntoOneCategory(raw, sport)) {
        return VerbDefaultsBundle.resetToFactoryPreservingCustoms(raw, sport);
      }
      return VerbDefaultsBundle.ensureComplete(raw, sport);
    }
    return VerbDefaultsBundle.buildFactory(sport);
  }

  /// Published app originals only. Personal verb edits stay in Preferences
  /// and are not mixed into this draft.
  Future<Map<String, dynamic>> _sportBundleForAdmin(String sport) async {
    final bundle = _sportBundleFromCatalog(sport);
    bundle['favoriteVerbs'] = <String>[];
    return bundle;
  }

  Map<String, dynamic> _emptySportBundle(String sport) =>
      VerbDefaultsBundle.buildFactory(sport);

  Map<String, dynamic> get _activeVerbBundle =>
      _verbBundles[_verbSport] ?? _emptySportBundle(_verbSport);

  void _setActiveVerbBundle(Map<String, dynamic> next) {
    _verbBundles[_verbSport] = next;
  }

  void _onAdminVerbBundleChanged(Map<String, dynamic> next) {
    setState(() => _setActiveVerbBundle(next));
  }

  Future<void> _importLocalVerbsForSport() async {
    final sport = _verbSport;
    final bundle = {
      'categoryOrder': await _prefs.getCategoryOrder(sport: sport),
      'favoriteVerbs': (await _prefs.getFavoriteVerbs(sport: sport)).toList(),
      'deletedVerbs': (await _prefs.getDeletedVerbs(sport: sport)).toList(),
      'verbOrder': await _prefs.getVerbOrder(sport: sport),
      'customVerbs': await _prefs.getCustomVerbs(sport: sport),
      'verbOverrides': await _prefs.getVerbOverrides(sport: sport),
      'verbWordingDefaults': await _prefs.getVerbWordingDefaults(sport: sport),
      'customVerbWordings': await _prefs.getCustomVerbWordings(sport: sport),
      'favoriteTeams': (await _prefs.getFavoriteTeams(sport: sport)).toList(),
    };
    setState(() => _setActiveVerbBundle(bundle));
  }

  CaptionTemplate _cloneCaption(CaptionTemplate template) {
    return CaptionTemplate.fromJson(Map<String, dynamic>.from(template.toJson()));
  }

  void _loadCaptionDraftsFromCatalog(AppDefaultsCatalog? catalog) {
    _captionByWireAndSport.clear();
    _gameIdDrafts.clear();
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      final bySportTemplate = <String, CaptionTemplate>{};
      final bySportGid = <String, String>{};
      for (final sport in _sports) {
        final gid = catalog?.gameIdentifierText(wire, sport) ??
            defaultGameIdentifierText(sport);
        final base = catalog?.captionForWireAndSport(wire, sport) ??
            catalog?.captionWireDefault(wire) ??
            AppDefaultsFirestoreService.factoryCaptionForWire(wire);
        bySportTemplate[sport] = _cloneCaption(base).copyWith(
          wireStyle: wire,
          gameIdentifierText: gid,
        );
        bySportGid[sport] = gid;
      }
      _captionByWireAndSport[wire] = bySportTemplate;
      _gameIdDrafts[wire] = bySportGid;
    }
    _showCaptionSport(_captionSport);
  }

  void _showCaptionSport(String sport) {
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      final template = _captionByWireAndSport[wire]?[sport];
      if (template == null) continue;
      final gid = _gameIdDrafts[wire]?[sport] ?? template.gameIdentifierText;
      _captionDrafts[wire] = _cloneCaption(template).copyWith(
        wireStyle: wire,
        gameIdentifierText: gid,
      );
    }
  }

  void _stashGameIdFromTemplate(WireStyle wire, CaptionTemplate template) {
    _gameIdDrafts.putIfAbsent(wire, () => {});
    _gameIdDrafts[wire]![_captionSport] = template.gameIdentifierText.trim();
  }

  bool _captionDirty = false;
  final Map<String, String> _captionBaselineJson = {};
  final Map<WireStyle, String> _gameIdBaselineJson = {};

  String _captionStructureKey(CaptionTemplate template) {
    final json = Map<String, dynamic>.from(template.toJson());
    json.remove('gameIdentifierText');
    return jsonEncode(json);
  }

  void _captureCaptionBaseline() {
    _captionBaselineJson
      ..clear()
      ..addEntries([
        for (final wireEntry in _captionByWireAndSport.entries)
          for (final sportEntry in wireEntry.value.entries)
            MapEntry(
              _captionSlotKey(wireEntry.key, sportEntry.key),
              _captionStructureKey(sportEntry.value),
            ),
      ]);
    _gameIdBaselineJson
      ..clear()
      ..addEntries(
        _gameIdDrafts.entries.map(
          (entry) => MapEntry(entry.key, jsonEncode(entry.value)),
        ),
      );
  }

  String _captionSlotKey(WireStyle wire, String sport) =>
      '${wire.name}|${sport.toLowerCase().trim()}';

  bool _sportHasPending(WireStyle wire, String sport) {
    final template = _captionByWireAndSport[wire]?[sport];
    if (template == null) return false;
    final structureChanged = _captionStructureKey(template) !=
        _captionBaselineJson[_captionSlotKey(wire, sport)];
    Map<String, dynamic> baselineGids = const {};
    try {
      final decoded = jsonDecode(_gameIdBaselineJson[wire] ?? '{}');
      if (decoded is Map) baselineGids = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final gidChanged = (_gameIdDrafts[wire]?[sport] ?? '') !=
        (baselineGids[sport]?.toString() ?? '');
    return structureChanged || gidChanged;
  }

  int get _captionPendingCount {
    var count = 0;
    for (final wire in _captionByWireAndSport.keys) {
      for (final sport in _sports) {
        if (_sportHasPending(wire, sport)) count++;
      }
    }
    return count;
  }

  void _markSportPublished(WireStyle wire, String sport) {
    final template = _captionByWireAndSport[wire]?[sport];
    if (template != null) {
      _captionBaselineJson[_captionSlotKey(wire, sport)] =
          _captionStructureKey(template);
    }
    _gameIdBaselineJson[wire] = jsonEncode(_gameIdDrafts[wire] ?? const {});
  }

  void _discardCaptionEdits() {
    _seedCaptionDraftsFromCatalog();
    _captureCaptionBaseline();
    setState(() {
      _captionDirty = false;
      _captionBuilderRevision++;
    });
  }
  final Map<String, int> _verbPendingBySport = {};
  bool _adminCloseConfirmed = false;
  Future<void> Function()? _setAllCaptionDefaults;

  void _onCaptionDraftChanged(WireStyle wire, CaptionTemplate template) {
    final copy = _cloneCaption(template).copyWith(wireStyle: wire);
    _captionDrafts[wire] = copy;
    (_captionByWireAndSport[wire] ??= {})[_captionSport] = _cloneCaption(copy);
    _stashGameIdFromTemplate(wire, copy);
    final pending = _captionPendingCount > 0;
    if (!mounted) {
      _captionDirty = pending;
      return;
    }
    setState(() => _captionDirty = pending);
  }

  Future<void> _onCaptionSportChanged(String sport) async {
    if (sport == _captionSport) return;
    await _flushCaptionBuilderDrafts();
    if (!mounted) return;
    setState(() {
      _captionSport = sport;
      _showCaptionSport(sport);
    });
  }

  void _onCaptionWireChanged(WireStyle wire) {
    if (wire == _captionWire) return;
    setState(() => _captionWire = wire);
  }

  void _seedCaptionDraftsFromCatalog() {
    _loadCaptionDraftsFromCatalog(_catalog);
  }

  Future<void> _setCaptionStructuresAsDefaults() async {
    await _publishCaptions(saveLocalDefaults: true);
  }

  Map<String, Map<String, String>> _gameIdDraftsForFirestore() {
    final out = <String, Map<String, String>>{};
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      final bySport = _gameIdDrafts[wire];
      if (bySport != null && bySport.isNotEmpty) {
        out[wire.name] = Map<String, String>.from(bySport);
      }
    }
    return out;
  }

  Future<void> _flushCaptionBuilderDrafts() async {
    await _flushCaptionBuilder?.call();
  }

  /// Two-step confirm so admin publishes to app originals are hard to misfire.
  Future<bool> _confirmAdminPublish({
    required String title,
    required String message,
    String confirmLabel = 'Publish',
  }) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    if (ok != true || !mounted) return false;

    final okAdmin = await showAppConfirmDialog(
      context: context,
      title: 'Publishing as admin',
      message:
          'You are signed in as an admin. This writes Firebase app originals '
          'that affect all users — not your personal Preferences.',
      confirmLabel: 'Publish as admin',
    );
    return okAdmin == true && mounted;
  }

  Future<bool> _writeActiveVerbBundleAsDefaults({String? successLabel}) async {
    if (!mounted) return false;
    setState(() => _busy = true);
    try {
      final bundle = VerbDefaultsBundle.ensureComplete(
        Map<String, dynamic>.from(_activeVerbBundle),
        _verbSport,
      );
      _setActiveVerbBundle(bundle);
      await AppDefaultsFirestoreService.publishVerbsForSport(
          _verbSport, bundle);
      _catalog = AppDefaultsFirestoreService.getCachedCatalog();
      _verbBundles[_verbSport] = Map<String, dynamic>.from(bundle);
      _verbBundles[_verbSport]!['favoriteVerbs'] = <String>[];
      if (!mounted) return false;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successLabel == null
                ? 'Saved $_verbSport verb defaults.'
                : '$successLabel to app defaults.',
          ),
          backgroundColor: kFloTealLight,
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to write defaults: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishCurrentVerb({
    required String key,
    required Map<String, dynamic> record,
    required bool isCustom,
  }) async {
    final label = (record['label'] ?? key).toString();
    final groups = record['modifierGroups'];
    if (groups is List) {
      final empty = groups.whereType<Map>().any((group) {
        final options = group['options'];
        return options is! List || options.isEmpty;
      });
      if (empty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Publish blocked: “$label” has a modifier group with no options.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final ok = await _confirmAdminPublish(
      title: 'Publish “$label” as default?',
      message: 'Updates Firebase app originals for this sport’s verb catalog '
          '(including this verb).',
    );
    if (!ok) return;

    // Merge the flushed verb into the in-editor catalog, then publish that.
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    if (isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      final index = list.indexWhere(
        (item) => (item['key'] ?? item['label']).toString() == key,
      );
      if (index < 0) {
        list.add(record);
      } else {
        list[index] = record;
      }
      bundle['customVerbs'] = list;
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      );
      overrides[key] = record;
      bundle['verbOverrides'] = overrides;
    }
    _setActiveVerbBundle(bundle);
    await _writeActiveVerbBundleAsDefaults(
      successLabel: 'Published “$label”',
    );
  }

  Future<void> _publishVerbs({bool allSports = false}) async {
    final invalid = <String>[];
    final bundles = allSports
        ? _verbBundles.entries
        : [_verbSport].map((sport) => MapEntry(sport, _activeVerbBundle));
    for (final bundleEntry in bundles) {
      final records = <Map<String, dynamic>>[
        ...((bundleEntry.value['customVerbs'] as List?) ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from),
        ...((bundleEntry.value['verbOverrides'] as Map?) ?? const {})
            .values
            .whereType<Map>()
            .map(Map<String, dynamic>.from),
      ];
      for (final record in records) {
        final groups = record['modifierGroups'];
        if (groups is! List) continue;
        final hasEmptyGroup = groups.whereType<Map>().any((group) {
          final options = group['options'];
          return options is! List || options.isEmpty;
        });
        if (hasEmptyGroup) {
          invalid.add(
            '${SportVerbCategories.displayLabel(bundleEntry.key)} · '
            '${record['label'] ?? 'Untitled verb'}',
          );
        }
      }
    }
    if (invalid.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Publish blocked: modifier groups need at least one option '
            '(${invalid.take(3).join(', ')}${invalid.length > 3 ? ', …' : ''}).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ok = await _confirmAdminPublish(
      title:
          allSports ? 'Publish all verb defaults?' : 'Publish verb defaults?',
      message: allSports
          ? 'Updates Firebase app originals for every sport.'
          : 'Updates Firebase app originals for $_verbSport.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      if (allSports) {
        await AppDefaultsFirestoreService.publishAllVerbs(_verbBundles);
      } else {
        await AppDefaultsFirestoreService.publishVerbsForSport(
          _verbSport,
          _activeVerbBundle,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allSports
                ? 'Published verb defaults for all sports.'
                : 'Published verb defaults for $_verbSport.',
          ),
          backgroundColor: kFloTealLight,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishCaptions({
    bool allWires = false,
    bool saveLocalDefaults = false,
  }) async {
    final wireLabel = WireIptcSpecs.factoryWireLabel(_captionWire);
    final sportLabel = SportVerbCategories.displayLabel(_captionSport);
    final ok = await _confirmAdminPublish(
      title: allWires
          ? 'Publish caption defaults?'
          : 'Save this structure as default?',
      message: allWires
          ? 'Saves every wire caption layout to Firebase app originals.'
          : 'Saves the caption structure you are editing as the default for '
              '$sportLabel on $wireLabel.',
      confirmLabel: allWires ? 'Publish' : 'Save',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _flushCaptionBuilderDrafts();
      if (saveLocalDefaults && allWires) {
        await _setAllCaptionDefaults?.call();
      }
      final wires = allWires
          ? AppDefaultsFirestoreService.captionWireStyles
          : [_captionWire];
      _stashGameIdFromTemplate(
        _captionWire,
        _captionDrafts[_captionWire] ??
            AppDefaultsFirestoreService.factoryCaptionForWire(_captionWire),
      );
      if (allWires) {
        final defaults = <String, Map<String, dynamic>>{};
        for (final wire in wires) {
          final template = _captionDrafts[wire] ??
              AppDefaultsFirestoreService.factoryCaptionForWire(wire);
          defaults[wire.name] = CaptionTemplate.wireMasterJsonFromTemplate(
            template.copyWith(wireStyle: wire),
          );
        }
        await AppDefaultsFirestoreService.publishCaptionWireDefaults(
          defaults,
          gameIdentifierByWireAndSport: _gameIdDraftsForFirestore(),
        );
      } else {
        final template = _captionDrafts[_captionWire] ??
            AppDefaultsFirestoreService.factoryCaptionForWire(_captionWire);
        await AppDefaultsFirestoreService.publishCaptionWireDefault(
          _captionWire,
          template,
          gameIdentifierForSport: _gameIdDrafts[_captionWire]?[_captionSport] ??
              template.gameIdentifierText,
          gameIdentifierSport: _captionSport,
        );
      }
      await _applyPublishedCaptionToWorkingTemplate();
      if (!mounted) return;
      _catalog = AppDefaultsFirestoreService.getCachedCatalog();
      if (allWires) {
        _captureCaptionBaseline();
      } else {
        _markSportPublished(_captionWire, _captionSport);
      }
      setState(() => _captionDirty = _captionPendingCount > 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allWires
                ? 'Published all caption structures.'
                : 'Saved the $wireLabel caption structure for $sportLabel.',
          ),
          backgroundColor: kFloTealLight,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// New captions read the active local template, not the Firebase wire
  /// original. After a publish, copy that original onto the working template
  /// when it is a built-in wire or an unnamed custom layout. Named library
  /// styles stay as saved.
  Future<void> _applyPublishedCaptionToWorkingTemplate() async {
    final prefs = await PreferencesService.getInstance();
    final active = await prefs.getCaptionTemplateRaw();
    if (active.id.startsWith('saved_') || active.id.startsWith('saved:')) {
      return;
    }
    final library = await prefs.getCaptionStyleLibrary();
    for (final entry in library) {
      if (entry.id == active.id) return;
    }

    final sourceWire = active.wireStyle == WireStyle.custom
        ? _captionWire
        : active.wireStyle;
    if (sourceWire != _captionWire) return;
    final published = _captionDrafts[sourceWire];
    if (published == null) return;

    final keepCustom = active.wireStyle == WireStyle.custom;
    final sport = await prefs.getCurrentSport();
    if (sport.toLowerCase().trim() != _captionSport.toLowerCase().trim()) {
      return;
    }
    var next = published.copyWith(
      id: keepCustom ? active.id : published.id,
      name: keepCustom ? active.name : published.name,
      wireStyle: keepCustom ? WireStyle.custom : sourceWire,
      includeTimingPhrase: active.includeTimingPhrase,
      showKeywordsField: active.showKeywordsField,
      showPersonalityField: active.showPersonalityField,
    );
    next = await prefs.applyGameIdentifierForSport(
      next,
      keepCustom ? next.wireStyle : sourceWire,
      sport,
    );
    await prefs.saveCaptionTemplate(next);
  }

  List<String> _categoryOrder(Map<String, dynamic> bundle, String sport) {
    final raw = bundle['categoryOrder'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    return List<String>.from(_emptySportBundle(sport)['categoryOrder'] as List);
  }

  List<_AdminVerbRow> _verbsForCategory(
    String sport,
    String category,
    Map<String, dynamic> bundle,
  ) {
    final factory = SportVerbCategories.forSport(sport);
    final deleted =
        (bundle['deletedVerbs'] as List?)?.map((e) => e.toString()).toSet() ??
            {};
    final overrides = Map<String, dynamic>.from(
      (bundle['verbOverrides'] as Map?) ?? {},
    );
    final custom = ((bundle['customVerbs'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final verbOrder = (bundle['verbOrder'] as Map?) ?? {};
    final ordered = verbOrder[category];
    final base = ordered is List && ordered.isNotEmpty
        ? ordered.map((e) => e.toString()).toList()
        : List<String>.from(factory[category] ?? []);

    final rows = <_AdminVerbRow>[];
    final seen = <String>{};

    void add(String key, {required bool isCustom}) {
      if (key.isEmpty || deleted.contains(key) || !seen.add(key)) return;
      Map<String, dynamic>? meta;
      if (isCustom) {
        for (final c in custom) {
          if (c['label']?.toString() == key) {
            meta = c;
            break;
          }
        }
      } else {
        meta = overrides[key] as Map<String, dynamic>?;
      }
      final label = meta?['label']?.toString() ?? key;
      final phrase = meta?['verbPhrase']?.toString().trim() ?? '';
      final singular =
          phrase.isNotEmpty ? phrase : VerbCaptionWording.defaultWording(key);
      final savedPlural = meta?['pluralPhrase']?.toString().trim() ?? '';
      final plural = savedPlural.isNotEmpty
          ? savedPlural
          : VerbCaptionWording.defaultPluralWording(key, singular);
      rows.add(
        _AdminVerbRow(
          key: key,
          isCustom: isCustom,
          label: label,
          verbPhrase: singular,
          pluralPhrase: plural,
          usePluralPhrase: meta?['usePluralPhrase'] as bool? ?? true,
          category: meta?['category']?.toString() ?? category,
          wantsOpponent: meta?['wantsOpponent'] == true,
          omitAgainst: meta?['omitAgainst'] == true,
          keywords: ((meta?['keywords'] as List?) ?? [])
              .map((e) => e.toString())
              .join(', '),
          subOptions: VerbSubOptions.fromJson(
            meta?['subOptions'],
            verbLabel: label,
            sport: _verbSport,
          ),
          sport: _verbSport,
        ),
      );
    }

    for (final v in base) {
      final isCustom = custom.any((c) => c['label']?.toString() == v);
      add(v, isCustom: isCustom);
    }
    for (final c in custom) {
      if (c['category']?.toString() == category) {
        add(c['label']?.toString() ?? '', isCustom: true);
      }
    }
    return rows;
  }

  Future<void> _editVerb(_AdminVerbRow row) async {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final categories = _categoryOrder(bundle, _verbSport);
    final wordingDefaults = Map<String, dynamic>.from(
      (bundle['verbWordingDefaults'] as Map?) ?? {},
    );
    final result = await showDialog<_AdminVerbEditResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _VerbEditDialog(
        initial: row,
        categories: categories,
        alreadyRecordedAsDefault: wordingDefaults.containsKey(row.key),
        sport: _verbSport,
      ),
    );
    if (result == null) return;

    if (result.row.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final idx = list.indexWhere((e) => e['label']?.toString() == row.key);
      final map = result.row.toCustomVerbMap();
      if (idx >= 0) {
        list[idx] = map;
      } else {
        list.add(map);
      }
      bundle['customVerbs'] = list;
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? {},
      );
      overrides[row.key] = result.row.toOverrideMap();
      bundle['verbOverrides'] = overrides;
    }
    if (result.recordAsDefault) {
      wordingDefaults[result.row.key] = result.row.isCustom
          ? result.row.toCustomVerbMap()
          : result.row.toOverrideMap();
      bundle['verbWordingDefaults'] = wordingDefaults;
    }
    setState(() => _setActiveVerbBundle(bundle));
    if (result.recordAsDefault && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded "${result.row.label}" as a default for $_verbSport. '
            'Publish to push it to Firebase.',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kFloTealLight,
        ),
      );
    }
  }

  Future<void> _addVerb() async {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final categories = _categoryOrder(bundle, _verbSport);
    final result = await showDialog<_AdminVerbEditResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _VerbEditDialog(
        initial: _AdminVerbRow(
          key: '',
          isCustom: true,
          label: '',
          verbPhrase: '',
          pluralPhrase: '',
          usePluralPhrase: true,
          category: categories.firstWhere(
            (c) => c != 'Favorites',
            orElse: () => categories.first,
          ),
          sport: _verbSport,
        ),
        categories: categories,
        isNew: true,
        sport: _verbSport,
      ),
    );
    if (result == null || result.row.label.trim().isEmpty) return;
    final list = ((bundle['customVerbs'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    list.add(result.row.toCustomVerbMap());
    bundle['customVerbs'] = list;
    if (result.recordAsDefault) {
      final wordingDefaults = Map<String, dynamic>.from(
        (bundle['verbWordingDefaults'] as Map?) ?? {},
      );
      wordingDefaults[result.row.key] = result.row.toCustomVerbMap();
      bundle['verbWordingDefaults'] = wordingDefaults;
    }
    setState(() => _setActiveVerbBundle(bundle));
    if (result.recordAsDefault && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded "${result.row.label}" as a default for $_verbSport. '
            'Publish to push it to Firebase.',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kFloTealLight,
        ),
      );
    }
  }

  void _deleteVerb(_AdminVerbRow row) {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet()
      ..add(row.key);
    final label = row.label.trim();
    if (label.isNotEmpty) deleted.add(label);
    bundle['deletedVerbs'] = deleted.toList();
    if (row.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['label']?.toString() != row.key)
          .toList();
      bundle['customVerbs'] = list;
    }
    setState(() => _setActiveVerbBundle(bundle));
  }

  static CustomDropdownDecoration get _dropdownDecoration =>
      CustomDropdownDecoration(
        closedFillColor: Colors.grey.shade50,
        expandedFillColor: Colors.white,
        closedBorder: Border.all(color: AuthUiColors.panelBorder, width: 0.7),
        expandedBorder: Border.all(color: kFloTealLight, width: 1),
        closedBorderRadius: BorderRadius.circular(6),
        expandedBorderRadius: BorderRadius.circular(8),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: Colors.grey.shade500,
        ),
        headerStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: AuthUiColors.brand,
        ),
        listItemStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: Colors.grey.shade800,
        ),
        listItemDecoration: const ListItemDecoration(
          selectedColor: kFloTealSelectedFill,
        ),
      );

  static BoxDecoration get _sectionDecoration => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F8F8), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: AuthUiColors.panelBorder, width: 0.7),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      );

  static const TextStyle _sectionTitleStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontVariations: [FontVariation('wght', 700)],
    color: Color(0xFF333333),
    letterSpacing: -0.5,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    color: AuthUiColors.subtitle,
    height: 1.35,
  );

  Widget _sectionCard({
    required String label,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _sectionDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: _sectionTitleStyle),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _sidebarTile(FfTokens t, _AdminSection section, String label) {
    final selected = _section == section;
    return Material(
      color: selected ? t.selectedFill : Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _section = section),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: selected
                ? Border(
                    left: BorderSide(color: t.accent, width: 2),
                  )
                : null,
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.labelFamily,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? t.accent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _captionSportDropdown() {
    return SizedBox(
      width: 160,
      child: DropdownFlutter<String>(
        hintText: 'Sport',
        items: _sports.map((s) => SportVerbCategories.displayLabel(s)).toList(),
        initialItem: SportVerbCategories.displayLabel(_captionSport),
        closedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        expandedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listItemPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _dropdownDecoration,
        onChanged: _busy
            ? null
            : (label) {
                if (label == null) return;
                final sport = _sports.firstWhere(
                  (s) => SportVerbCategories.displayLabel(s) == label,
                  orElse: () => label.toLowerCase(),
                );
                _onCaptionSportChanged(sport);
              },
      ),
    );
  }

  Widget _sportDropdown({required void Function(String sport) onChanged}) {
    return SizedBox(
      width: 160,
      child: DropdownFlutter<String>(
        hintText: 'Sport',
        items: _sports.map((s) => SportVerbCategories.displayLabel(s)).toList(),
        initialItem: SportVerbCategories.displayLabel(_verbSport),
        closedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        expandedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listItemPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _dropdownDecoration,
        onChanged: (label) {
          if (label == null) return;
          final sport = _sports.firstWhere(
            (s) => SportVerbCategories.displayLabel(s) == label,
            orElse: () => label.toLowerCase(),
          );
          onChanged(sport);
        },
      ),
    );
  }

  Widget _verbRow(_AdminVerbRow v) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.7),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      v.label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontVariations: [FontVariation('wght', 600)],
                        color: Colors.black87,
                      ),
                    ),
                    if (v.isCustom) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: kFloTealSelectedFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kFloTealLight, width: 0.5),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: kFloTealDark,
                          ),
                        ),
                      ),
                    ],
                    if (_verbHasRecordedDefault(v.key)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFB300),
                            width: 0.5,
                          ),
                        ),
                        child: const Text(
                          'Default',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A6D00),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  v.verbPhrase.isEmpty ? '(default phrase)' : v.verbPhrase,
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          _iconAction(
            icon: _verbHasRecordedDefault(v.key)
                ? PhosphorIconsFill.star
                : PhosphorIconsRegular.star,
            tooltip: _verbHasRecordedDefault(v.key)
                ? 'Already a recorded default — click to update from current wording'
                : 'Set as default for app originals',
            iconColor:
                _verbHasRecordedDefault(v.key) ? const Color(0xFFFFB300) : null,
            onPressed: _busy ? null : () => _recordVerbAsDefault(v),
          ),
          _iconAction(
            icon: PhosphorIconsRegular.pencilSimple,
            tooltip: 'Edit verb',
            onPressed: _busy ? null : () => _editVerb(v),
          ),
          _iconAction(
            icon: PhosphorIconsRegular.trash,
            tooltip: 'Remove verb',
            onPressed: _busy ? null : () => _deleteVerb(v),
          ),
        ],
      ),
    );
  }

  bool _verbHasRecordedDefault(String key) {
    final defaults = _activeVerbBundle['verbWordingDefaults'];
    if (defaults is! Map) return false;
    return defaults.containsKey(key);
  }

  void _recordVerbAsDefault(_AdminVerbRow row) {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final wordingDefaults = Map<String, dynamic>.from(
      (bundle['verbWordingDefaults'] as Map?) ?? {},
    );
    final map = row.isCustom ? row.toCustomVerbMap() : row.toOverrideMap();
    wordingDefaults[row.key] = map;
    bundle['verbWordingDefaults'] = wordingDefaults;
    if (row.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final idx = list.indexWhere((e) => e['label']?.toString() == row.key);
      if (idx >= 0) {
        list[idx] = map;
      } else {
        list.add(map);
      }
      bundle['customVerbs'] = list;
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? {},
      );
      overrides[row.key] = map;
      bundle['verbOverrides'] = overrides;
    }
    setState(() => _setActiveVerbBundle(bundle));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recorded "${row.label}" as a default for $_verbSport. '
          'Publish to push it to Firebase.',
          style: const TextStyle(fontSize: 11),
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kFloTealLight,
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: PhosphorIcon(
              icon,
              size: 16,
              color: iconColor ?? Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerbsContent() {
    return AdminVerbAuthoringEditor(
      key: ValueKey('admin-verb-editor-$_verbSport'),
      sport: _verbSport,
      sports: _sports,
      bundle: _activeVerbBundle,
      busy: _busy,
      embedded: true,
      onSportChanged: (sport) => setState(() => _verbSport = sport),
      onBundleChanged: _onAdminVerbBundleChanged,
      onPublishCurrentVerb: _publishCurrentVerb,
      onWriteSportDefaults: _writeActiveVerbBundleAsDefaults,
      onPendingChanges: _onVerbPendingChanges,
    );
  }

  Widget _buildCaptionContent(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CaptionLayoutBuilderDialog(
            key: ValueKey('admin_caption_$_captionBuilderRevision'),
            embedded: true,
            adminMode: true,
            initialWire: _captionWire,
            initialSport: _captionSport,
            initialTemplate: _captionDrafts[_captionWire],
            wireDraftsSeed:
                Map<WireStyle, CaptionTemplate>.from(_captionDrafts),
            gameIdDraftsSeed:
                Map<WireStyle, Map<String, String>>.from(_gameIdDrafts),
            onDraftChanged: _onCaptionDraftChanged,
            onWireChanged: _onCaptionWireChanged,
            onSportChanged: (sport) {
              unawaited(_onCaptionSportChanged(sport));
            },
            onRegisterFlush: (flush) => _flushCaptionBuilder = flush,
            onRegisterSetAllDefaults: (setAll) => _setAllCaptionDefaults = setAll,
          ),
        ),
        _buildFooter(t),
      ],
    );
  }

  Widget _buildFooter(FfTokens t) {
    final count = _captionPendingCount;
    final pending = count > 0 && !_busy;
    final status = count <= 0
        ? 'Everything is published'
        : '$count unpublished change${count == 1 ? '' : 's'}, not live until published';
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: t.microStyle.copyWith(
                fontSize: 11,
                height: 1.25,
                color: t.text.withValues(alpha: 0.55),
              ),
            ),
          ),
          TextButton(
            onPressed: pending ? _discardCaptionEdits : null,
            child: Text(
              'Discard',
              softWrap: false,
              style: t.metaStyle.copyWith(
                color: pending
                    ? t.text.withValues(alpha: 0.70)
                    : t.text.withValues(alpha: 0.28),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedGreyButton(
            label: _busy ? 'Saving…' : 'Save as default',
            fontSize: 11,
            isPrimary: true,
            isAdmin: true,
            onPressed: _sportHasPending(_captionWire, _captionSport) && !_busy
                ? _setCaptionStructuresAsDefaults
                : null,
          ),
        ],
      ),
    );
  }

  bool get _hasUnpublishedEdits =>
      _captionDirty || _verbPendingBySport.values.any((count) => count > 0);

  void _onVerbPendingChanges(String sport, int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _verbPendingBySport[sport] ?? 0;
      if (count <= 0) {
        if (!_verbPendingBySport.containsKey(sport)) return;
        setState(() => _verbPendingBySport.remove(sport));
        return;
      }
      if (current == count) return;
      setState(() => _verbPendingBySport[sport] = count);
    });
  }

  Future<void> _requestClose() async {
    if (_busy || _adminCloseConfirmed) return;
    if (_hasUnpublishedEdits) {
      final ok = await showAppConfirmDialog(
        context: context,
        title: 'Close without saving?',
        message:
            'You have changes that are not saved yet. Close and discard them?',
        cancelLabel: 'Stay',
        confirmLabel: 'Discard',
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _adminCloseConfirmed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Widget _buildHeaderActions(FfTokens t) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => unawaited(_requestClose()),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: PhosphorIcon(
            PhosphorIconsRegular.x,
            size: 20,
            color: t.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AppDialogFfStyle(
      enabled: true,
      child: PopScope(
        canPop: _adminCloseConfirmed,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _adminCloseConfirmed) return;
          unawaited(_requestClose());
        },
        child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: _dialogWidth,
          height: _dialogHeight,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            border: Border.all(color: t.divider),
            boxShadow: [
              BoxShadow(
                color: t.bg.withValues(alpha: 0.55),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border(
                      bottom: BorderSide(color: t.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: FfTokens.gold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontFamily: FfTokens.labelFamily,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: FfTokens.inkOnGold,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FfGlow(
                        glowW: 320,
                        glowH: 180,
                        child: Text(
                          'App originals',
                          style: t.labelStyle.copyWith(
                            fontSize: 13,
                            color: t.text,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'Reload app originals',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _busy || _loading
                                ? null
                                : () => unawaited(_bootstrap()),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: PhosphorIcon(
                                PhosphorIconsRegular.arrowClockwise,
                                size: 18,
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildHeaderActions(t),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(color: t.accent),
                        )
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  style: t.metaStyle.copyWith(
                                    color: const Color(0xFFE57373),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: _sidebarWidth,
                                  decoration: BoxDecoration(
                                    color: t.sunken,
                                    border: Border(
                                      right: BorderSide(color: t.divider),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ListView(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          children: [
                                            _sidebarTile(
                                              t,
                                              _AdminSection.verbs,
                                              'Verbs',
                                            ),
                                            Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: t.divider,
                                            ),
                                            _sidebarTile(
                                              t,
                                              _AdminSection.captionStructures,
                                              'Caption Structures',
                                            ),
                                            Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: t.divider,
                                            ),
                                            _sidebarTile(
                                              t,
                                              _AdminSection.rosterCompare,
                                              'Roster Compare',
                                            ),
                                            Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: t.divider,
                                            ),
                                            _sidebarTile(
                                              t,
                                              _AdminSection.rosterIssues,
                                              'Roster Issues',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ColoredBox(
                                    color: t.bg,
                                    child: _section == _AdminSection.verbs
                                        ? Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              _contentPadding,
                                              _contentPadding,
                                              _contentPadding,
                                              0,
                                            ),
                                            child: _buildVerbsContent(),
                                          )
                                        : _section ==
                                                _AdminSection.captionStructures
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                  _contentPadding,
                                                  _contentPadding,
                                                  _contentPadding,
                                                  0,
                                                ),
                                                child: _buildCaptionContent(t),
                                              )
                                            : SingleChildScrollView(
                                                padding: const EdgeInsets.all(
                                                  _contentPadding,
                                                ),
                                                child: _section ==
                                                        _AdminSection
                                                            .rosterIssues
                                                    ? _buildRosterIssuesContent(
                                                        t,
                                                      )
                                                    : _buildRosterCompareContent(
                                                        t,
                                                      ),
                                              ),
                                  ),
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
    );
  }

  static const _issuesSportIds = [
    'all',
    'baseball',
    'basketball',
    'hockey',
    'wnba',
  ];

  String _issuesSportLabel(String sportId) =>
      sportId == 'all' ? 'All' : SportVerbCategories.displayLabel(sportId);

  String? _issuesSportIdFromLabel(String label) {
    for (final id in _issuesSportIds) {
      if (_issuesSportLabel(id) == label) return id;
    }
    return null;
  }

  Widget _issuesSportDropdown(FfTokens t) {
    final labels = _issuesSportIds.map(_issuesSportLabel).toList();
    final selected = _issuesSportLabel(_issuesSportFilter);
    return DropdownFlutter<String>(
      key: ValueKey('issues-sport-$selected'),
      hintText: 'Sport',
      initialItem: selected,
      items: labels,
      closedHeaderPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      expandedHeaderPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      listItemPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: CustomDropdownDecoration(
        closedFillColor: t.sunken,
        expandedFillColor: t.surface,
        closedBorder: Border.all(color: t.divider),
        expandedBorder: Border.all(color: t.divider),
        closedBorderRadius: BorderRadius.circular(6),
        expandedBorderRadius: BorderRadius.circular(8),
        closedShadow: [
          BoxShadow(
            color: t.bg.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        expandedShadow: [
          BoxShadow(
            color: t.bg.withValues(alpha: 0.55),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        hintStyle: TextStyle(fontSize: 11, color: t.textSecondary),
        headerStyle: TextStyle(fontSize: 11, color: t.text),
        listItemStyle: TextStyle(fontSize: 11, color: t.text),
        listItemDecoration: ListItemDecoration(
          selectedColor: t.selectedFill,
        ),
        closedSuffixIcon: PhosphorIcon(
          PhosphorIconsRegular.caretDown,
          size: 16,
          color: t.textSecondary,
        ),
        expandedSuffixIcon: PhosphorIcon(
          PhosphorIconsRegular.caretUp,
          size: 16,
          color: t.textSecondary,
        ),
      ),
      onChanged: (label) {
        if (label == null) return;
        final id = _issuesSportIdFromLabel(label);
        if (id == null) return;
        setState(() => _issuesSportFilter = id);
      },
    );
  }

  Widget _buildRosterIssuesContent(FfTokens t) {
    final bySport = <String, List<RosterIssue>>{};
    for (final issue in _rosterIssues) {
      (bySport[issue.sportId] ??= []).add(issue);
    }
    final sportKeys = bySport.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Roster issues (Tank01 mirror)',
          style: t.labelStyle.copyWith(fontSize: 14, color: t.text),
        ),
        const SizedBox(height: 6),
        Text(
          'Players in sports_tank01 with missing or duplicate jersey numbers. '
          'Enter a verified number here — it is saved as a manual override so '
          'the next Tank01 sync will not wipe it. Sync summary emails also '
          'list these.',
          style: t.metaStyle.copyWith(height: 1.35),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: _issuesSportDropdown(t),
            ),
            const SizedBox(width: 10),
            ElevatedGreyButton(
              label: _issuesScanning ? 'Scanning…' : 'Scan jersey issues',
              fontSize: 11,
              icon: PhosphorIconsRegular.magnifyingGlass,
              onPressed:
                  _issuesScanning || _issuesSaving ? null : _scanRosterIssues,
            ),
          ],
        ),
        if (_issuesStatus != null) ...[
          const SizedBox(height: 10),
          Text(
            _issuesStatus!,
            style: t.metaStyle.copyWith(color: t.accent),
          ),
        ],
        if (_issuesError != null) ...[
          const SizedBox(height: 10),
          Text(
            _issuesError!,
            style: t.metaStyle.copyWith(color: const Color(0xFFE57373)),
          ),
        ],
        const SizedBox(height: 16),
        if (_rosterIssues.isEmpty && !_issuesScanning)
          Text(
            'Run a scan to list missing and duplicate jersey numbers.',
            style: t.metaStyle.copyWith(color: t.textSecondary),
          )
        else
          ...sportKeys.map((sport) {
            final rows = bySport[sport]!;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${SportVerbCategories.displayLabel(sport)} · ${rows.length} issue(s)',
                    style: t.labelStyle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: t.divider),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        rows[i].label,
                        style: t.labelStyle.copyWith(
                          fontSize: 13,
                          color: t.text,
                        ),
                      ),
                      subtitle: Text(
                        [
                          rows[i].teamName,
                          rows[i].kindLabel,
                          if (rows[i].detail != null) rows[i].detail!,
                        ].join(' · '),
                        style: t.metaStyle.copyWith(color: t.textSecondary),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _openPlayerGoogleSearch(rows[i]),
                            child: const Text('Google'),
                          ),
                          TextButton(
                            onPressed: _issuesSaving
                                ? null
                                : () => _fixJerseyIssue(rows[i]),
                            child: const Text('Set #'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildRosterCompareContent(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compare $_compareSport rosters: Tank01 vs Firebase vs live API',
          style: t.labelStyle.copyWith(
            fontSize: 14,
            color: t.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use this after Go Time while captioning. Tank01 is the RapidAPI roster; '
          'Firebase sports/... is your league-API cache; sports_tank01/... is the '
          'Tank01 mirror (same player fields, team ids = Tank01 abbreviations). '
          'Live API is MLB Stats / NHL / ESPN depending on sport.',
          style: t.metaStyle.copyWith(height: 1.35),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedGreyButton(
              label: _tank01SyncRunning
                  ? 'Syncing…'
                  : 'Sync Tank01 → sports_tank01 ($_compareSport)',
              fontSize: 11,
              icon: PhosphorIconsRegular.cloudArrowUp,
              onPressed: _tank01SyncRunning ||
                      _compareRunning ||
                      !tank01SupportsSport(_compareSport)
                  ? null
                  : () => _syncTank01ToFirestore(allSports: false),
            ),
            ElevatedGreyButton(
              label: _tank01SyncRunning ? 'Syncing…' : 'Sync all Tank01 sports',
              fontSize: 11,
              icon: PhosphorIconsRegular.arrowsClockwise,
              onPressed: _tank01SyncRunning || _compareRunning
                  ? null
                  : () => _syncTank01ToFirestore(allSports: true),
            ),
          ],
        ),
        if (_tank01SyncStatus != null) ...[
          const SizedBox(height: 8),
          Text(
            _tank01SyncStatus!,
            style: t.metaStyle.copyWith(color: t.accent),
          ),
        ],
        const SizedBox(height: 14),
        if (_compareLoadingTeams)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(color: t.accent),
          )
        else ...[
          Row(
            children: [
              Expanded(child: _compareTeamDropdown(isA: true)),
              const SizedBox(width: 10),
              Expanded(child: _compareTeamDropdown(isA: false)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedGreyButton(
                label: _compareRunning ? 'Comparing…' : 'Compare rosters',
                fontSize: 11,
                icon: PhosphorIconsRegular.arrowsLeftRight,
                onPressed: _compareRunning ||
                        _tank01SyncRunning ||
                        _compareTeamNames.isEmpty
                    ? null
                    : _runRosterCompare,
              ),
              const SizedBox(width: 8),
              ElevatedGreyButton(
                label: 'Reload teams',
                fontSize: 11,
                icon: PhosphorIconsRegular.arrowClockwise,
                onPressed: _compareRunning || _tank01SyncRunning
                    ? null
                    : _loadTeamsForCompare,
              ),
            ],
          ),
        ],
        if (_compareError != null) ...[
          const SizedBox(height: 12),
          Text(
            _compareError!,
            style: t.metaStyle.copyWith(color: const Color(0xFFE57373)),
          ),
        ],
        const SizedBox(height: 16),
        ..._compareReports.map(_buildCompareReportCard),
      ],
    );
  }

  Widget _compareTeamDropdown({required bool isA}) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final value = isA ? _compareTeamA : _compareTeamB;
    final hint = isA ? 'Team A' : 'Team B (optional)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint,
          style: t.microStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        DropdownFlutter<String>(
          hintText: 'Select team',
          initialItem:
              value != null && _compareTeamNames.contains(value) ? value : null,
          items: _compareTeamNames,
          closedHeaderPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          expandedHeaderPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          listItemPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: _dropdownDecoration,
          onChanged: (v) {
            setState(() {
              if (isA) {
                _compareTeamA = v;
              } else {
                _compareTeamB = v;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildCompareReportCard(RosterCompareReport report) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.teamName,
            style: t.labelStyle.copyWith(fontSize: 13, color: t.text),
          ),
          const SizedBox(height: 8),
          _sourceLine(report.tank01),
          _sourceLine(report.firestore),
          _sourceLine(report.mlbStats),
          const SizedBox(height: 8),
          _diffBlock(
            'Only in Tank01 (not ${report.liveApi.source})',
            report.onlyInTank01VsLive.map((p) => p.label).toList(),
          ),
          _diffBlock(
            'Only in ${report.liveApi.source} (not Tank01)',
            report.onlyInLiveVsTank01.map((p) => p.label).toList(),
          ),
          _diffBlock(
            'Only in Tank01 (not Firebase)',
            report.onlyInTank01VsFirebase.map((p) => p.label).toList(),
          ),
          _diffBlock(
            'Only in Firebase (not Tank01)',
            report.onlyInFirebaseVsTank01.map((p) => p.label).toList(),
          ),
          _diffBlock(
            'Jersey mismatches (Tank01 vs ${report.liveApi.source})',
            report.jerseyMismatches,
          ),
        ],
      ),
    );
  }

  Widget _sourceLine(RosterCompareSourceResult s) {
    final color = s.ok ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    final text = s.ok
        ? '${s.source}: ${s.players.length} players'
        : '${s.source}: failed — ${s.error}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _diffBlock(String title, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${items.length})',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF333333),
            ),
          ),
          if (items.isEmpty)
            Text(
              '  none',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            )
          else
            ...items.take(40).map(
                  (line) => Text(
                    '  • $line',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: Color(0xFF444444),
                    ),
                  ),
                ),
          if (items.length > 40)
            Text(
              '  …and ${items.length - 40} more',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminVerbEditResult {
  const _AdminVerbEditResult({
    required this.row,
    this.recordAsDefault = false,
  });

  final _AdminVerbRow row;
  final bool recordAsDefault;
}

class _AdminVerbRow {
  const _AdminVerbRow({
    required this.key,
    required this.isCustom,
    required this.label,
    required this.verbPhrase,
    required this.pluralPhrase,
    this.usePluralPhrase = true,
    required this.category,
    this.wantsOpponent = true,
    this.omitAgainst = false,
    this.keywords = '',
    this.subOptions = const VerbSubOptions(),
    this.sport = 'baseball',
  });

  final String key;
  final bool isCustom;
  final String label;
  final String verbPhrase;
  final String pluralPhrase;
  final bool usePluralPhrase;
  final String category;
  final bool wantsOpponent;
  final bool omitAgainst;
  final String keywords;
  final VerbSubOptions subOptions;
  final String sport;

  Map<String, dynamic> toOverrideMap() => {
        'label': label,
        'verbPhrase': verbPhrase,
        'pluralPhrase':
            pluralPhrase.trim().isEmpty ? null : pluralPhrase.trim(),
        'usePluralPhrase': usePluralPhrase,
        'category': category,
        'wantsOpponent': wantsOpponent,
        'omitAgainst': omitAgainst,
        'isCustom': false,
        if (keywords.trim().isNotEmpty)
          'keywords': keywords
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        if (subOptions.differsFromDefaults(label, sport: sport))
          'subOptions': subOptions.toJson(),
      };

  Map<String, dynamic> toCustomVerbMap() => {
        ...toOverrideMap(),
        'isCustom': true,
      };
}

class _VerbEditDialog extends StatefulWidget {
  const _VerbEditDialog({
    required this.initial,
    required this.categories,
    this.isNew = false,
    this.alreadyRecordedAsDefault = false,
    this.sport = 'baseball',
  });

  final _AdminVerbRow initial;
  final List<String> categories;
  final bool isNew;
  final bool alreadyRecordedAsDefault;
  final String sport;

  @override
  State<_VerbEditDialog> createState() => _VerbEditDialogState();
}

class _VerbEditDialogState extends State<_VerbEditDialog> {
  late final TextEditingController _label;
  late final TextEditingController _phrase;
  late final TextEditingController _plural;
  late final TextEditingController _keywords;
  late String _category;
  late bool _wantsOpponent;
  late bool _omitAgainst;
  late bool _usePluralPhrase;
  late VerbSubOptions _subOptions;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.initial.label);
    _phrase = TextEditingController(text: widget.initial.verbPhrase);
    _plural = TextEditingController(text: widget.initial.pluralPhrase);
    _keywords = TextEditingController(text: widget.initial.keywords);
    _category = widget.initial.category;
    _wantsOpponent = widget.initial.wantsOpponent;
    _omitAgainst = widget.initial.omitAgainst;
    _usePluralPhrase = widget.initial.usePluralPhrase;
    _subOptions = widget.initial.subOptions;
  }

  @override
  void dispose() {
    _label.dispose();
    _phrase.dispose();
    _plural.dispose();
    _keywords.dispose();
    super.dispose();
  }

  _AdminVerbRow _buildRow() => _AdminVerbRow(
        key: widget.isNew ? _label.text.trim() : widget.initial.key,
        isCustom: widget.isNew || widget.initial.isCustom,
        label: _label.text.trim(),
        verbPhrase: _phrase.text.trim(),
        pluralPhrase: _plural.text.trim(),
        usePluralPhrase: _usePluralPhrase,
        category: _category,
        wantsOpponent: _wantsOpponent,
        omitAgainst: _omitAgainst,
        keywords: _keywords.text.trim(),
        subOptions: _subOptions,
        sport: widget.sport,
      );

  void _popResult({required bool recordAsDefault}) {
    final row = _buildRow();
    if (row.label.isEmpty || row.verbPhrase.isEmpty) return;
    Navigator.pop(
      context,
      _AdminVerbEditResult(row: row, recordAsDefault: recordAsDefault),
    );
  }

  Widget _captionFlagRow({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: appDialogCardDecoration(radius: 6),
      child: Row(
        children: [
          AppCompactCheckbox(
            value: value,
            accentColor: kFloTealLight,
            onChanged: onChanged,
          ),
          const SizedBox(width: 8),
          Text(label, style: kAppDialogFieldTextStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories.where((c) => c != 'Favorites').toList();
    final categoryValue = cats.contains(_category)
        ? _category
        : (cats.isNotEmpty ? cats.first : _category);
    return Center(
      child: SizedBox(
        width: kVerbEditDialogWidth,
        child: AlertDialog(
          shape: kAppDialogShape,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: AppDialogTealTitleBar(
            title: widget.isNew ? 'Add verb' : 'Edit verb',
          ),
          content: SizedBox(
            width: kVerbEditDialogWidth - 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: AppDialogLabeledTextField(
                              label: 'Label',
                              controller: _label,
                              bottomGap: 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppDialogLabeledDropdown<String>(
                              label: 'Category',
                              value: categoryValue,
                              items: cats
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _category = v ?? _category),
                              bottomGap: 0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AppDialogLabeledTextField(
                        label: 'Singular phrase (1 player)',
                        controller: _phrase,
                        bottomGap: 0,
                        onChanged: (_) {
                          if (_plural.text.trim().isEmpty ||
                              _plural.text ==
                                  VerbCaptionWording.defaultPluralWording(
                                    widget.initial.key,
                                    _phrase.text,
                                  )) {
                            _plural.text =
                                VerbCaptionWording.defaultPluralWording(
                              _label.text.trim().isEmpty
                                  ? widget.initial.key
                                  : _label.text.trim(),
                              _phrase.text.trim(),
                            );
                          }
                          setState(() {});
                        },
                      ),
                      VerbEditPluralPhraseField(
                        pluralController: _plural,
                        usePluralPhrase: _usePluralPhrase,
                        onUsePluralChanged: (v) =>
                            setState(() => _usePluralPhrase = v),
                        onPluralChanged: (_) => setState(() {}),
                        bottomGap: 0,
                      ),
                      const SizedBox(height: 4),
                      AppDialogLabeledTextField(
                        label: 'Keywords',
                        controller: _keywords,
                        hintText: 'comma-separated',
                        maxLines: 2,
                        bottomGap: 8,
                      ),
                      _captionFlagRow(
                        value: _wantsOpponent,
                        label: 'Wants opponent',
                        onChanged: (v) => setState(() {
                          _wantsOpponent = v;
                          if (!v) _omitAgainst = false;
                        }),
                      ),
                      if (_wantsOpponent) ...[
                        const SizedBox(height: 8),
                        _captionFlagRow(
                          value: _omitAgainst,
                          label: 'Omit "against"',
                          onChanged: (v) => setState(() => _omitAgainst = v),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (VerbSubOptions.showEditorPanel(
                  sport: widget.sport,
                  verbLabel: _label.text.trim().isEmpty
                      ? widget.initial.label
                      : _label.text.trim(),
                  value: _subOptions,
                ))
                  VerbEditSubOptionsSection(
                    sport: widget.sport,
                    verbLabel: _label.text.trim().isEmpty
                        ? widget.initial.label
                        : _label.text.trim(),
                    value: _subOptions,
                    onChanged: (v) => setState(() => _subOptions = v),
                  ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            SizedBox(
              width: kVerbEditDialogWidth - 48,
              child: Row(
                children: [
                  Tooltip(
                    message: widget.alreadyRecordedAsDefault
                        ? 'Update the recorded Reset baseline for this verb in the app originals'
                        : 'Record this wording as the Reset baseline in app originals (then Publish)',
                    child: ElevatedGreyButton(
                      label: widget.alreadyRecordedAsDefault
                          ? 'Update Default · Admin'
                          : 'Set as Default · Admin',
                      fontSize: 11,
                      isAdmin: true,
                      onPressed: () => _popResult(recordAsDefault: true),
                    ),
                  ),
                  const Spacer(),
                  ElevatedGreyButton(
                    label: 'Cancel',
                    fontSize: 11,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  ElevatedGreyButton(
                    label: 'Save',
                    fontSize: 11,
                    isPrimary: true,
                    onPressed: () => _popResult(recordAsDefault: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable admin badge for chrome headers.
class AdminBadgeButton extends StatelessWidget {
  const AdminBadgeButton({
    super.key,
    required this.child,
    this.openRosterCompare = false,
    this.onClosed,
  });

  final Widget child;
  final bool openRosterCompare;
  final Future<void> Function()? onClosed;

  @override
  Widget build(BuildContext context) {
    if (!AdminService.isCurrentUserAdminSync()) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AdminScreen.open(
          context,
          openRosterCompare: openRosterCompare,
          onClosed: onClosed,
        ),
        child: child,
      ),
    );
  }
}
