import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_session_context.dart';
import '../../../caption_style/caption_style_catalog.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/caption_text_normalize.dart';
import '../../../caption_style/game_info.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/api_manager.dart';
import '../../../services/ftpclient_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/mlb_inning_feature_gate.dart';
import '../../../services/mlb_inning_from_timestamp_service.dart';
import '../../../services/preferences_service.dart';
import '../../../config/tank01_config.dart';
import '../../../utils/exiftool_helper.dart';
import '../../../utils/default_verb_keywords.dart';
import '../../../utils/native_file_picker.dart';
import '../widgets/frame_status_dot.dart';
import 'burst_groups.dart';
import 'caption_transfer_payload.dart';
import 'caption_v2_caption_domain.dart';
import 'effective_verb_catalog.dart';
import 'iptc_caption_writer.dart';
import 'team_abbrev.dart';

class LastUsedCombo {
  const LastUsedCombo({
    required this.verb,
    required this.rbi,
    this.playerLabel,
    this.verbLabel,
  });

  final String verb;
  final int rbi;
  final String? playerLabel;
  final String? verbLabel;

  String get chipLabel {
    final r = rbi > 0 ? ' · RBI $rbi' : '';
    return '${verbLabel ?? _verbChip(verb)}$r';
  }
}

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.label,
    required this.apply,
    this.aliases = const [],
    this.shortcutLabel,
  });

  final String kind;
  final String label;
  final VoidCallback apply;
  final List<String> aliases;
  final String? shortcutLabel;
}

class RosterHit {
  const RosterHit({required this.player, required this.isHome});
  final Player player;
  final bool isHome;
}

enum FirebarResultKind { player, verb }

enum FirebarOptionKind { homeRun, rbi, celebration, base }

enum RosterSortMode { number, firstName, lastName }

class FirebarOption {
  const FirebarOption(
    this.label, {
    this.rbi,
    this.verbOverride,
    this.celebration,
    this.base,
  });

  final String label;
  final int? rbi;
  final String? verbOverride;
  final String? celebration;
  final String? base;
}

class FirebarResult {
  const FirebarResult.player({
    required this.player,
    required this.isHome,
  })  : kind = FirebarResultKind.player,
        verbKey = null;

  const FirebarResult.verb(this.verbKey)
      : kind = FirebarResultKind.verb,
        player = null,
        isHome = null;

  final FirebarResultKind kind;
  final Player? player;
  final bool? isHome;
  final String? verbKey;

  String get key => kind == FirebarResultKind.player
      ? 'player:${isHome == true ? 'home' : 'away'}:'
          '${player?.playerId ?? ''}:${player?.jerseyNumber ?? ''}:'
          '${player?.fullName ?? ''}'
      : 'verb:$verbKey';
}

class CaptionSaveResult {
  const CaptionSaveResult({
    required this.requestedPaths,
    required this.succeededPaths,
  });

  final List<String> requestedPaths;
  final List<String> succeededPaths;

  List<String> get failedPaths => requestedPaths
      .where((path) => !succeededPaths.contains(path))
      .toList(growable: false);
  bool get anySucceeded => succeededPaths.isNotEmpty;
  bool get allSucceeded => requestedPaths.isNotEmpty && failedPaths.isEmpty;
}

String _verbChip(String verb) {
  switch (verb) {
    case 'Single':
      return 'singles';
    case 'Double':
      return 'doubles';
    case 'Triple':
      return 'triples';
    default:
      return VerbCaptionWording.defaultWording(verb);
  }
}

String _ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String _ordinalWord(int n) {
  switch (n) {
    case 1:
      return 'first';
    case 2:
      return 'second';
    case 3:
      return 'third';
    case 4:
      return 'fourth';
    case 5:
      return 'fifth';
    case 6:
      return 'sixth';
    case 7:
      return 'seventh';
    case 8:
      return 'eighth';
    case 9:
      return 'ninth';
    default:
      return _ordinal(n);
  }
}

/// Session controller for caption V2 — UI talks only to this.
class CaptionV2Controller extends ChangeNotifier {
  CaptionV2Controller({
    ApiManager? apiManager,
    IptcCaptionWriter? writer,
  })  : _api = apiManager ?? ApiManager(),
        _writer = writer ?? const IptcCaptionWriter(),
        _mlbTimestamp = MlbInningFromTimestampService();

  final ApiManager _api;
  final IptcCaptionWriter _writer;
  final MlbInningFromTimestampService _mlbTimestamp;
  PreferencesService? _prefs;
  EffectiveVerbRepository? _verbRepository;
  EffectiveVerbCatalog _verbCatalog = EffectiveVerbCatalog.factory('baseball');

  // --- Game / teams ---
  String homeTeam = '';
  String awayTeam = '';
  String venue = '';
  String sport = 'baseball';
  String city = '';
  String region = '';
  String country = '';
  String countryCode = '';

  /// IPTC/EXIF from the current frame (date, photographer, location, …).
  Map<String, String> currentIptcMeta = {};
  String photographerName = '';
  String agencyName = '';
  String headline = '';
  String keywords = '';
  bool showKeywordsField = false;
  bool showPersonalityField = true;
  bool applyVerbKeywords = true;
  bool applyPlayerNamesToKeywords = true;
  bool metadataDirty = false;
  final Set<String> _basePersonalityNames = {};
  final Set<String> _managedKeywordKeys = {};
  final Set<String> _baseKeywordKeys = {};
  int _iptcLoadGen = 0;

  /// Active caption style from prefs (Getty / Imagn / AP / …).
  CaptionTemplate captionTemplate = CaptionTemplate.getty();
  CaptionStyleCatalog? _captionStyleCatalog;
  String _activeCaptionStyleToken = CaptionStyleCatalog.tokGetty;

  /// False until the V2 startup screen completes.
  bool sessionReady = false;
  bool sessionLoading = false;
  String? sessionLoadingLabel;
  int sessionGeneration = 0;

  String get homeAbbr => mlbTeamAbbreviation(homeTeam);
  String get awayAbbr => mlbTeamAbbreviation(awayTeam);

  String get captionStyleLabel =>
      WireIptcSpecs.displayWireLabel(captionTemplate.wireStyle, null);
  List<CaptionStyleOption> get captionStyleOptions =>
      _captionStyleCatalog?.options ?? const [];
  String get activeCaptionStyleToken => _activeCaptionStyleToken;

  List<Player> homeRoster = const [];
  List<Player> awayRoster = const [];
  bool rostersLoading = false;
  String? rosterError;

  /// e.g. "Tank01 MLB" / "MLB API" — shown in session chrome.
  String rosterSourceLabel = '';

  // --- Selection ---
  final List<RosterHit> selectedPlayers = [];
  Player? selectedPlayer;
  bool selectedIsHome = true;
  String? selectedVerb;
  String customVerbPhrase = '';
  String lastCustomVerbPhrase = '';
  bool customVerbPinned = false;
  bool captionSelectionStarted = false;
  String? celebrationType;
  String? pinnedVerb;
  String? verbCategory = 'Offense';
  String personality = '';
  String? manualCaptionOverride;
  CaptionTransferPayload? previousCaption;
  int rbi = 0;
  /// Running-verb base: `1B`, `2B`, `3B`, `Home`, or null.
  String? selectedBase;
  int inning = 2;
  bool preGame = false;
  bool postGame = false;
  bool mlbTimestampAvailable = false;
  bool mlbTimestampEnabled = true;
  bool mlbTimestampLoading = false;
  String? mlbTimestampMatchedPath;
  int _mlbTimestampToken = 0;

  bool get mlbTimestampMatched =>
      currentPath != null && mlbTimestampMatchedPath == currentPath;

  final List<LastUsedCombo> lastUsed = [];

  // --- Frames ---
  List<String> imagePaths = [];
  int currentIndex = 0;
  final Map<String, DateTime> captureByPath = {};
  final Set<String> savedImages = {};
  final Set<String> captionedImages = {};
  final Set<String> sentImages = {};
  final Set<String> selectedImagePaths = {};
  bool burstDetectionEnabled = true;
  bool loadingImages = false;

  // --- Search / focus ---
  String searchQuery = '';
  bool searchOpen = false;
  String? guidedSearchPrompt;
  List<SearchHit> _guidedSearchHits = const [];
  int? _pendingCommandInning;
  int columnFocus = 1; // 0 home, 1 verbs, 2 away, 3 thumbnails
  RosterSortMode rosterSort = RosterSortMode.number;
  bool rosterSortAscending = true;
  int firebarSelectionIndex = -1;
  final List<FirebarResult> _firebarCommitted = [];
  String? firebarOptionPrompt;
  FirebarOptionKind? _firebarOptionKind;
  List<FirebarOption> firebarOptions = const [];
  int firebarOptionIndex = 0;

  bool get searchGuided => guidedSearchPrompt != null;
  bool get searchHasJerseyAndVerb =>
      RegExp(r'^(?:[hv]\s*)?#?\d+\s+\S', caseSensitive: false)
          .hasMatch(searchQuery.trim());
  bool get searchIsJerseyOnly =>
      RegExp(r'^(?:[hv]\s*)?#?\d+$', caseSensitive: false)
          .hasMatch(searchQuery.trim());
  bool get searchIsTeamPrefixOnly =>
      RegExp(r'^[hv]$', caseSensitive: false).hasMatch(searchQuery.trim());
  bool get searchAwaitingVerb =>
      searchOpen &&
      !searchGuided &&
      selectedPlayers.isNotEmpty &&
      selectedVerb == null;

  List<FirebarResult> get firebarHomeResults =>
      _firebarRosterResults(homeRoster, isHome: true);

  List<FirebarResult> get firebarAwayResults =>
      _firebarRosterResults(awayRoster, isHome: false);

  List<FirebarResult> get firebarVerbResults {
    final query = _normalizedFirebarQuery;
    if (RegExp(r'^(?:[hv])?\d+$').hasMatch(query)) return const [];
    final seen = <String>{};
    final results = <FirebarResult>[];
    for (final category in verbCategories) {
      if (category == 'Favorites') continue;
      for (final verb
          in verbDefinitionsByCategory[category] ?? const <EffectiveVerb>[]) {
        if (!seen.add(verb.key)) continue;
        if (query.isEmpty || _firebarVerbMatches(verb.label, query)) {
          results.add(FirebarResult.verb(verb.key));
        }
      }
    }
    return results;
  }

  List<FirebarResult> get firebarOrderedResults {
    final home = firebarHomeResults;
    final away = firebarAwayResults;
    return selectedIsHome
        ? [...home, ...firebarVerbResults, ...away]
        : [...away, ...firebarVerbResults, ...home];
  }

  FirebarResult? get firebarSelectedResult {
    final results = firebarOrderedResults;
    if (firebarSelectionIndex < 0 || firebarSelectionIndex >= results.length) {
      return null;
    }
    return results[firebarSelectionIndex];
  }

  List<FirebarResult> get firebarCommitted =>
      List.unmodifiable(_firebarCommitted);

  List<FirebarOption> get filteredFirebarOptions {
    final query = _normalizeFirebarText(searchQuery);
    if (query.isEmpty) return firebarOptions;
    return firebarOptions
        .where(
          (option) => _normalizeFirebarText(option.label).startsWith(query),
        )
        .toList(growable: false);
  }

  int get firebarVerbTotal {
    final seen = <String>{};
    for (final category in verbCategories) {
      if (category == 'Favorites') continue;
      for (final verb
          in verbDefinitionsByCategory[category] ?? const <EffectiveVerb>[]) {
        seen.add(verb.key);
      }
    }
    return seen.length;
  }

  int get firebarTotalCount =>
      homeRoster.length + firebarVerbTotal + awayRoster.length;

  int get firebarMatchedCount =>
      firebarHomeResults.length +
      firebarVerbResults.length +
      firebarAwayResults.length;

  String get _normalizedFirebarQuery =>
      firebarOptions.isNotEmpty ? '' : _normalizeFirebarText(searchQuery);

  static String _normalizeFirebarText(String value) =>
      CaptionTextNormalize.stripDiacritics(value).trim().toLowerCase();

  static bool _firebarVerbMatches(String label, String query) {
    final normalized = _normalizeFirebarText(label);
    if (normalized.startsWith(query)) return true;
    final initials = normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .join();
    return initials.startsWith(query);
  }

  List<FirebarResult> _firebarRosterResults(
    List<Player> roster, {
    required bool isHome,
  }) {
    final query = _normalizedFirebarQuery;
    final jerseyMatch = RegExp(r'^([hv])?(\d+)$').firstMatch(query);
    final requestedSide = jerseyMatch?.group(1);
    final jerseyQuery = jerseyMatch?.group(2);
    if ((requestedSide == 'h' && !isHome) || (requestedSide == 'v' && isHome)) {
      return const [];
    }
    final matches = roster.where((player) {
      if (query.isEmpty) return true;
      if (jerseyQuery != null) {
        return (player.jerseyNumber ?? '').trim().startsWith(jerseyQuery);
      }
      return _playerMatchScore(player, query) < 900;
    }).toList();
    if (query.isNotEmpty) {
      matches.sort((a, b) {
        final score = _playerMatchScore(a, query)
            .compareTo(_playerMatchScore(b, query));
        if (score != 0) return score;
        return _comparePlayers(a, b);
      });
    }
    return [
      for (final player in matches)
        FirebarResult.player(
          player: player,
          isHome: isHome,
        ),
    ];
  }

  /// Lower is better. 900+ means no match.
  static int _playerMatchScore(Player player, String query) {
    if (query.isEmpty) return 0;
    final name = _normalizeFirebarText(player.fullName);
    final first = _normalizeFirebarText(player.firstName);
    final last = _normalizeFirebarText(playerLastName(player));
    final jersey = (player.jerseyNumber ?? '').trim().toLowerCase();

    if (jersey == query) return 0;
    if (jersey.startsWith(query)) return 1;
    if (last == query) return 2;
    if (first == query) return 3;
    if (name == query) return 4;
    if (last.startsWith(query)) return 5;
    if (first.startsWith(query)) return 6;
    if (name.startsWith(query)) return 7;
    if (last.contains(query)) return 8;
    if (first.contains(query)) return 9;
    if (name.contains(query)) return 10;
    if (jersey.contains(query)) return 11;
    return 900;
  }

  /// Filter a roster by query with best matches first (exact jersey, then
  /// name prefix / contains). Empty query returns the roster as-is.
  List<Player> filterAndRankPlayers(List<Player> roster, String query) {
    final q = _normalizeFirebarText(query);
    if (q.isEmpty) return List<Player>.from(roster);
    final matches =
        roster.where((player) => _playerMatchScore(player, q) < 900).toList();
    matches.sort((a, b) {
      final score =
          _playerMatchScore(a, q).compareTo(_playerMatchScore(b, q));
      if (score != 0) return score;
      return _comparePlayers(a, b);
    });
    return matches;
  }

  // --- Transmit ---
  String destinationLabel = 'Photoshelter · FTP';
  int queuedCount = 0;
  String? lastSentLabel;
  bool transmitting = false;
  String? statusMessage;

  String? get currentPath => imagePaths.isEmpty
      ? null
      : imagePaths[currentIndex.clamp(0, imagePaths.length - 1)];

  String get currentFileName {
    final path = currentPath;
    if (path == null) return 'No image';
    return p.basenameWithoutExtension(path);
  }

  String get originalCaption =>
      _metaFirst(const [
        'IPTC:Description',
        'Description',
        'Caption-Abstract',
        'IPTC:Caption-Abstract',
        'ImageDescription',
        'XMP:Description',
      ]) ??
      '';

  String get originalPersonality =>
      _metaFirst(const ['XMP-getty:Personality', 'Personality']) ?? '';

  bool get showHeadlineField => false;
  bool get showMetadataEditor => showKeywordsField || showHeadlineField;
  FrameState frameStateFor(String path) {
    if (sentImages.contains(path)) return FrameState.sent;
    if (savedImages.contains(path)) return FrameState.saved;
    return FrameState.todo;
  }

  FrameState get currentFrameState {
    final path = currentPath;
    if (path == null) return FrameState.todo;
    return frameStateFor(path);
  }

  int get sentCount =>
      imagePaths.where((p) => frameStateFor(p) == FrameState.sent).length;
  int get savedNotSentCount =>
      imagePaths.where((p) => frameStateFor(p) == FrameState.saved).length;
  int get todoCount =>
      imagePaths.where((p) => frameStateFor(p) == FrameState.todo).length;

  List<List<String>> get bursts =>
      groupFramesIntoBursts(imagePaths, captureByPath);

  List<String> get currentBurst {
    final path = currentPath;
    if (path == null) return const [];
    for (final g in bursts) {
      if (g.contains(path)) return g;
    }
    return [path];
  }

  List<String> get orderedSelectedImagePaths =>
      imagePaths.where(selectedImagePaths.contains).toList(growable: false);

  List<String> get forwardBurstChain {
    final path = currentPath;
    if (path == null) return const [];
    return burstChainFromAnchor(imagePaths, path, captureByPath);
  }

  void setSelectedImagePaths(Iterable<String> paths) {
    selectedImagePaths
      ..clear()
      ..addAll(paths.where(imagePaths.contains));
    notifyListeners();
  }

  void clearSelectedImagePaths() {
    if (selectedImagePaths.isEmpty) return;
    selectedImagePaths.clear();
    notifyListeners();
  }

  EffectiveVerbCatalog get verbCatalog => _verbCatalog;
  List<String> get verbCategories => _verbCatalog.categoryOrder;
  Map<String, List<String>> get verbsByCategory => {
        for (final entry in _verbCatalog.verbsByCategory.entries)
          entry.key: entry.value.map((verb) => verb.key).toList(),
      };
  Map<String, List<EffectiveVerb>> get verbDefinitionsByCategory =>
      _verbCatalog.verbsByCategory;
  EffectiveVerb? verbDefinition(String key) => _verbCatalog.byKey[key];
  bool isVerbFavorite(String key) => _verbCatalog.favoriteKeys.contains(key);
  bool isVerbPinned(String key) => pinnedVerb == key;

  List<String> get verbsInCategory {
    final cat = verbCategory ?? verbsByCategory.keys.first;
    return verbsByCategory[cat] ?? const [];
  }

  String get playerChipLabel {
    return selectedPlayers.map((row) {
      final j = row.player.jerseyNumber ?? '';
      final short = _shortName(row.player.fullName);
      return j.isEmpty ? short : '$j $short';
    }).join(' + ');
  }

  bool isPlayerSelected(Player player, {required bool isHome}) {
    return selectedPlayers.any(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
  }

  /// The first selected team is the action team. Same-team picks are ordered
  /// co-subjects; picks from the other team are ordered action participants.
  List<RosterHit> get subjectPlayers {
    if (selectedPlayers.isEmpty) return const [];
    final subjectIsHome = selectedPlayers.first.isHome;
    return selectedPlayers
        .where((row) => row.isHome == subjectIsHome)
        .toList(growable: false);
  }

  List<RosterHit> get opposingPlayers {
    if (selectedPlayers.isEmpty) return const [];
    final subjectIsHome = selectedPlayers.first.isHome;
    return selectedPlayers
        .where((row) => row.isHome != subjectIsHome)
        .toList(growable: false);
  }

  bool _samePlayer(Player a, Player b) {
    final aId = a.playerId?.trim();
    final bId = b.playerId?.trim();
    if (aId != null && aId.isNotEmpty && bId != null && bId.isNotEmpty) {
      return aId == bId;
    }
    return a.fullName == b.fullName && a.jerseyNumber == b.jerseyNumber;
  }

  String get verbChipLabel {
    final custom = customVerbPhrase.trim();
    if (custom.isNotEmpty) return custom;
    final v = selectedVerb;
    if (v == null) return '';
    return verbDefinition(v)?.singularPhrase ?? _verbChip(v);
  }

  bool get hasVerbSelection =>
      selectedVerb != null || customVerbPhrase.trim().isNotEmpty;

  String get rbiChipLabel => rbi > 0 ? 'RBI $rbi' : '';

  String get baseChipLabel {
    final base = selectedBase?.trim();
    if (base == null || base.isEmpty) return '';
    return base;
  }

  /// Regular regulation segments before OT/extra (classic inning bar counts).
  int get timingRegulationCount {
    switch (sport.toLowerCase()) {
      case 'hockey':
        return 3;
      case 'basketball':
      case 'wnba':
        return 4;
      case 'soccer':
        return 2;
      case 'baseball':
      default:
        return 9;
    }
  }

  /// Highest selectable inning/period (baseball pages extras through 27).
  int get timingMaxInning {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return 27;
      default:
        return timingRegulationCount + 1;
    }
  }

  /// Noun used in captions: period / quarter / half / inning.
  String get timingUnitNoun {
    switch (sport.toLowerCase()) {
      case 'hockey':
        return 'period';
      case 'basketball':
      case 'wnba':
        return 'quarter';
      case 'soccer':
        return 'half';
      case 'baseball':
      default:
        return 'inning';
    }
  }

  /// Chip / stepper label (e.g. "2nd", "OT", "ET", "10th").
  String get inningLabel {
    final max = timingRegulationCount;
    final s = sport.toLowerCase();
    if (inning > max) {
      switch (s) {
        case 'soccer':
          return 'ET';
        case 'baseball':
          return _ordinal(inning);
        default:
          return 'OT';
      }
    }
    if (s == 'soccer') {
      return inning == 1 ? '1H' : '2H';
    }
    if (s == 'basketball' || s == 'wnba') {
      return 'Q$inning';
    }
    return _ordinal(inning);
  }

  /// Caption clause for the current timing selection (matches classic wording).
  String get timingCaptionClause {
    if (preGame) return 'prior to the game';
    if (postGame) return 'after the game';
    final max = timingRegulationCount;
    final s = sport.toLowerCase();
    if (inning > max && s != 'baseball') {
      switch (s) {
        case 'soccer':
          return 'during extra time';
        default:
          return 'during overtime';
      }
    }
    switch (s) {
      case 'hockey':
        return 'during the ${_ordinalWord(inning)} period';
      case 'basketball':
      case 'wnba':
        return 'during the ${_ordinalWord(inning)} quarter';
      case 'soccer':
        return inning == 1 ? 'during the first half' : 'during the second half';
      case 'baseball':
      default:
        return 'during the ${_ordinalWord(inning)} inning';
    }
  }

  /// Chip-mode leading text (used when the full style caption isn't ready yet).
  String get captionLeading {
    final team = selectedPlayers.isEmpty
        ? (selectedIsHome ? homeTeam : awayTeam)
        : (selectedPlayers.first.isHome ? homeTeam : awayTeam);
    return '$team ';
  }

  String get captionTrailing {
    final subjectIsHome =
        selectedPlayers.isEmpty ? selectedIsHome : selectedPlayers.first.isHome;
    final opp = subjectIsHome ? awayTeam : homeTeam;
    final venueText = venue.trim().isNotEmpty
        ? venue
        : (_metaFirst(const [
              'IPTC:SubLocation',
              'Sub-location',
              'SubLocation',
              'XMP:Location',
            ]) ??
            '');
    final venueBit = venueText.isEmpty ? '' : ' at $venueText';
    return ' against the $opp $timingCaptionClause$venueBit.';
  }

  /// Player + action body that feeds [CaptionFormulaRenderer] (no location/credit).
  ///
  /// Builds as soon as a player is selected (even before a verb), so the
  /// configured caption style can still wrap date / venue / byline around a
  /// partial body — matching V1.
  String buildCaptionBody() {
    if (selectedPlayer == null) return '';
    final lead = _playerLead(captionTemplate);
    if (!hasVerbSelection) {
      return '$lead ${_incompleteContextPhrase()}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    final action = customVerbPhrase.trim().isNotEmpty
        ? _customActionPhrase()
        : _actionPhrase();
    return '$lead $action'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Full caption using the user's saved caption style (Getty / Imagn / …).
  String buildCaptionSentence() {
    final manual = manualCaptionOverride;
    if (manual != null) return manual;
    final body = buildCaptionBody();
    if (body.isEmpty) {
      // No players yet — keep a light chip-friendly preview only.
      final parts = <String>[
        captionLeading.trim(),
        if (hasVerbSelection) verbChipLabel,
        if (rbi > 0) rbiChipLabel,
        if (baseChipLabel.isNotEmpty) baseChipLabel,
        captionTrailing.trim(),
      ];
      return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final path = currentPath;
    final capture = path == null ? null : captureByPath[path];
    final gameDate = capture ??
        _parseExifDate(_metaFirst(const [
              'DateTimeOriginal',
              'CreateDate',
              'ModifyDate',
            ]) ??
            '') ??
        DateTime.now();

    final gameCity = city.trim().isNotEmpty
        ? city
        : (_metaFirst(const ['IPTC:City', 'City', 'XMP:City']) ?? '');
    final gameRegion = region.trim().isNotEmpty
        ? region
        : (_metaFirst(const [
              'IPTC:ProvinceState',
              'Province-State',
              'ProvinceState',
              'XMP:State',
            ]) ??
            '');
    final gameCountry = country.trim().isNotEmpty
        ? country
        : (_metaFirst(const [
              'IPTC:CountryPrimaryLocationName',
              'CountryPrimaryLocationName',
              'Country',
              'XMP:Country',
            ]) ??
            '');
    final gameCountryCode = countryCode.trim().isNotEmpty
        ? countryCode
        : (_metaFirst(const [
              'IPTC:CountryPrimaryLocationCode',
              'CountryPrimaryLocationCode',
              'CountryCode',
            ]) ??
            '');
    final gameVenue = venue.trim().isNotEmpty
        ? venue
        : (_metaFirst(const [
              'IPTC:SubLocation',
              'Sub-location',
              'SubLocation',
              'XMP:Location',
            ]) ??
            '');

    final game = GameInfo(
      gameDate: gameDate,
      city: gameCity,
      region: gameRegion,
      country: gameCountry,
      countryCode: gameCountryCode,
      venue: gameVenue,
      photographerName: photographerName,
      agencyName: agencyName,
      iptcMetadata: currentIptcMeta,
    );

    CreditSampleAgency agency;
    switch (captionTemplate.wireStyle) {
      case WireStyle.imagn:
        agency = CreditSampleAgency.imagn;
        break;
      case WireStyle.ap:
      case WireStyle.cp:
        agency = CreditSampleAgency.ap;
        break;
      case WireStyle.getty:
      case WireStyle.gettyInternational:
      case WireStyle.custom:
        agency = CreditSampleAgency.gettyImages;
        break;
    }

    CaptionSessionContext.update(
      captionBody: body,
      gameInfo: game,
      previewPlayers: [
        for (final row in selectedPlayers)
          CaptionPreviewPlayer(
            row.isHome ? homeTeam : awayTeam,
            row.player.position ?? '',
            row.player.fullName,
            int.tryParse(row.player.jerseyNumber ?? '') ?? 0,
            row.isHome ? awayTeam : homeTeam,
          ),
      ],
      previewActions: [
        if (hasVerbSelection)
          customVerbPhrase.trim().isNotEmpty
              ? customVerbPhrase.trim()
              : (selectedVerb ?? ''),
      ],
    );

    var caption = CaptionFormulaRenderer.render(
      template: captionTemplate,
      game: game,
      sampleAgency: agency,
      captionOverride: body,
      sport: sport,
    );
    if (captionTemplate.removeDiacritics) {
      caption = CaptionTextNormalize.stripDiacritics(caption);
    }
    return caption;
  }

  /// Opponent + timing clause used when players are selected but no verb yet.
  /// Venue / date / byline stay in the caption style renderer.
  String _incompleteContextPhrase() {
    final subjects = subjectPlayers;
    final subjectIsHome =
        subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final target = opposingPlayers.isEmpty
        ? 'the ${opponentTeam.trim()}'
        : _formatPlayersWithTeam(opposingPlayers, captionTemplate);

    if (preGame) return 'ahead of playing against $target';
    if (postGame) return 'after playing against $target';
    return 'against $target $timingCaptionClause';
  }

  bool get hasCompleteCaption => selectedPlayer != null && hasVerbSelection;

  Map<String, String> captionValues() {
    final caption = buildCaptionSentence();
    return {
      'IPTC:Caption-Abstract': caption,
      'Caption-Abstract': caption,
      'IPTC:Description': caption,
      'Description': caption,
      'XMP:Description': caption,
      'XMP-getty:Personality': personality,
      'Personality': personality,
      'IPTC:Headline': headline,
      'Headline': headline,
      'XMP:Headline': headline,
      'IPTC:Keywords': keywords,
      'Keywords': keywords,
      'XMP:Subject': keywords,
      'XMP-dc:Subject': keywords,
    };
  }

  String _playerLead(CaptionTemplate template) {
    final rows = subjectPlayers.isEmpty
        ? [RosterHit(player: selectedPlayer!, isHome: selectedIsHome)]
        : subjectPlayers;
    var teamName = rows.first.isHome ? homeTeam : awayTeam;
    final playerLabels = rows.map((row) {
      var playerName = row.player.fullName;
      if (template.removeDiacritics) {
        playerName = CaptionTextNormalize.stripDiacritics(playerName);
      }
      final jersey = row.player.jerseyNumber?.trim() ?? '';
      if (jersey.isEmpty) return playerName;
      final numText = template.numberFormat == NumberFormatStyle.hash
          ? '#$jersey'
          : '($jersey)';
      return '$playerName $numText';
    }).toList();
    final playersText = _joinNames(playerLabels);
    if (template.removeDiacritics) {
      teamName = CaptionTextNormalize.stripDiacritics(teamName);
    }
    switch (template.captionTeamOrder) {
      case CaptionTeamOrder.teamAfter:
        return '$playersText of the $teamName';
      case CaptionTeamOrder.teamBefore:
        return '$teamName $playersText';
    }
  }

  String _actionPhrase() {
    final verb = selectedVerb!;
    final definition = verbDefinition(verb);
    final subjects = subjectPlayers;
    final subjectIsHome =
        subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final plural = subjects.length > 1;
    var action = CaptionV2CaptionDomain.actionCore(
      verb: verb,
      sport: sport,
      plural: plural,
      rbi: rbi,
      base: selectedBase,
      singularPhrase: definition?.singularPhrase,
      pluralPhrase: definition?.pluralPhrase,
      subOptions: definition?.subOptions,
    );
    action = _withCelebrationType(
      verb: verb,
      action: action,
      type: celebrationType,
      plural: plural,
      subOptions: definition?.subOptions,
    );

    if (definition?.wantsOpponent ?? true) {
      action = CaptionV2CaptionDomain.withOpponent(
        verb: verb,
        action: action,
        opponentTeam: opponentTeam,
        opposingPlayers: opposingPlayers.isEmpty
            ? null
            : _formatPlayersWithTeam(opposingPlayers, captionTemplate),
      );
    }

    if (verb == 'Post Game Win' || verb == 'Post Game Loss') {
      return '$action after the game';
    }
    if (preGame) return '$action prior to the game';
    return '$action $timingCaptionClause';
  }

  String _customActionPhrase() {
    var action = customVerbPhrase.trim();
    final lower = action.toLowerCase();
    if (!lower.contains(' against ') && !lower.contains(' playing ')) {
      final subjects = subjectPlayers;
      final subjectIsHome =
          subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
      action = CaptionV2CaptionDomain.withOpponent(
        verb: action,
        action: action,
        opponentTeam: subjectIsHome ? awayTeam : homeTeam,
        opposingPlayers: opposingPlayers.isEmpty
            ? null
            : _formatPlayersWithTeam(opposingPlayers, captionTemplate),
      );
    }
    if (preGame) return '$action prior to the game';
    if (postGame) return '$action after the game';
    return '$action $timingCaptionClause';
  }

  String _withCelebrationType({
    required String verb,
    required String action,
    required String? type,
    required bool plural,
    required VerbSubOptions? subOptions,
  }) {
    final selected = type?.trim();
    if (selected == null || selected.isEmpty) return action;
    final options =
        subOptions ?? VerbSubOptions.defaultsFor(verb, sport: sport);
    final isReaction = options.reactionPhraseList.any(
          (phrase) => phrase.toLowerCase() == selected.toLowerCase(),
        ) ||
        selected.toLowerCase() == 'celebration';

    if (VerbSubOptions.isHitVerb(verb) || isReaction) {
      var reaction = selected.toLowerCase();
      if (reaction == 'celebration') {
        reaction = options.primaryReactionPhrase;
      }
      if (plural) {
        reaction = VerbCaptionWording.inferPluralFromSingular(reaction);
      }
      if (!VerbSubOptions.isHitVerb(verb)) {
        // Celebration verb + reaction phrase: lead with the reaction.
        return reaction;
      }
      final hit = RegExp(r'^hits? a ', caseSensitive: false);
      if (hit.hasMatch(action)) {
        return '$reaction after hitting a ${action.replaceFirst(hit, '')}';
      }
      return '$reaction after '
          '${VerbSubOptions.gerundPhraseFromSingular(action)}';
    }
    switch (selected) {
      case 'Scoring':
        return '$action scoring';
      case 'Single':
      case 'Double':
      case 'Triple':
        return '$action after hitting a ${selected.toLowerCase()}';
      case 'Home Run':
        return '$action after hitting a home run';
      case 'Strikeout':
        return '$action after a strikeout';
      case 'Goal':
        return '$action after a goal';
      case 'Win':
        return '$action after a win';
      case 'With Teammates':
        return '$action with teammates';
      default:
        return '$action after ${selected.toLowerCase()}';
    }
  }

  String _formatPlayersWithTeam(
    List<RosterHit> rows,
    CaptionTemplate template,
  ) {
    if (rows.isEmpty) return '';
    var team = rows.first.isHome ? homeTeam : awayTeam;
    if (template.removeDiacritics) {
      team = CaptionTextNormalize.stripDiacritics(team);
    }
    final labels = rows.map((row) {
      var name = row.player.fullName;
      if (template.removeDiacritics) {
        name = CaptionTextNormalize.stripDiacritics(name);
      }
      final jersey = row.player.jerseyNumber?.trim() ?? '';
      if (jersey.isEmpty) return name;
      return template.numberFormat == NumberFormatStyle.hash
          ? '$name #$jersey'
          : '$name ($jersey)';
    }).toList();
    return '${_joinNames(labels)} of the $team';
  }

  static String _joinNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first} and ${names.last}';
    return '${names.sublist(0, names.length - 1).join(', ')}, '
        'and ${names.last}';
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> bootstrap() async {
    _prefs = await PreferencesService.getInstance();
    _verbRepository = EffectiveVerbRepository(_prefs!);
    sport = await _prefs!.getCurrentSport();
    await _loadVerbCatalog();
    burstDetectionEnabled = await _prefs!.getBurstDetectionEnabled();
    captionTemplate = await _prefs!.getCaptionTemplate();
    mlbTimestampEnabled = await _prefs!.getMlbInningFromClockEnabled();
    showKeywordsField = await _prefs!.getShowKeywordsField();
    showPersonalityField = await _prefs!.getShowPersonalityField();
    applyVerbKeywords = await _prefs!.getApplyVerbKeywords();
    applyPlayerNamesToKeywords = await _prefs!.getApplyPlayerNamesToKeywords();
    _prefs!.captionFieldVisibilityRevision.addListener(
      _onCaptionFieldVisibilityChanged,
    );
    final syncId = await _prefs!.getSyncAccountId();
    mlbTimestampAvailable = MlbInningFeatureGate.isEnabled(syncId);
    final previous = await _prefs!.getLastSavedMetadata();
    previousCaption = previous == null
        ? null
        : CaptionTransferPayload.decode(jsonEncode(previous));
    await _loadCaptionStyleCatalog();
    await _refreshFtpDestination();
    notifyListeners();
  }

  Future<void> _loadCaptionStyleCatalog() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final catalog = await CaptionStyleCatalog.load(prefs, sport: sport);
    _captionStyleCatalog = catalog;
    _activeCaptionStyleToken = catalog.activeToken;
    captionTemplate = catalog.resolve(
      catalog.activeToken,
      refForCustom: captionTemplate,
    );
  }

  Future<void> _loadVerbCatalog() async {
    final repository = _verbRepository;
    if (repository == null) return;
    _verbCatalog = await repository.load(sport);
    if (!_verbCatalog.verbsByCategory.containsKey(verbCategory)) {
      verbCategory = _verbCatalog.categoryOrder.isEmpty
          ? null
          : _verbCatalog.categoryOrder.first;
    }
    if (selectedVerb != null && !_verbCatalog.byKey.containsKey(selectedVerb)) {
      selectedVerb = null;
    }
    if (pinnedVerb != null && !_verbCatalog.byKey.containsKey(pinnedVerb)) {
      pinnedVerb = null;
    }
  }

  Future<void> reloadCaptionStyle() async {
    final prefs = _prefs;
    if (prefs == null) return;
    captionTemplate = await prefs.getCaptionTemplate();
    await _loadCaptionStyleCatalog();
    manualCaptionOverride = null;
    notifyListeners();
  }

  Future<void> setCaptionStyle(String token) async {
    final catalog = _captionStyleCatalog;
    final prefs = _prefs;
    if (catalog == null || prefs == null || token == _activeCaptionStyleToken) {
      return;
    }
    captionTemplate = catalog.resolve(token, refForCustom: captionTemplate);
    _activeCaptionStyleToken = token;
    notifyListeners();
    await prefs.saveCaptionTemplate(captionTemplate);
  }

  /// Apply startup choices, then load rosters via API and images from folder.
  Future<void> applyStartup({
    required String sport,
    required String homeTeam,
    required String awayTeam,
    required String folderPath,
    required bool burstDetectionEnabled,
    List<Player>? homeRosterOverride,
    List<Player>? awayRosterOverride,
    String venue = '',
    String city = '',
    String region = '',
    String country = '',
    String countryCode = '',
  }) async {
    sessionGeneration++;
    this.sport = sport;
    this.homeTeam = homeTeam;
    this.awayTeam = awayTeam;
    this.venue = venue;
    this.city = city;
    this.region = region;
    this.country = country;
    this.countryCode = countryCode;
    this.burstDetectionEnabled = burstDetectionEnabled;
    pinnedVerb = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = null;
    celebrationType = null;
    personality = '';
    manualCaptionOverride = null;
    rbi = 0;
    selectedBase = null;
    inning = 1;
    preGame = false;
    postGame = false;
    sessionLoading = true;
    sessionLoadingLabel = 'Loading rosters…';
    sessionReady = false;
    notifyListeners();

    _api.setSport(sport);
    await _prefs?.saveCurrentSport(sport);
    await _prefs?.saveBurstDetectionEnabled(burstDetectionEnabled);
    await _loadVerbCatalog();
    await _loadCaptionStyleCatalog();

    await loadRosters(
      homeOverride: homeRosterOverride,
      awayOverride: awayRosterOverride,
    );
    sessionLoadingLabel = 'Loading images…';
    notifyListeners();
    await loadFolder(folderPath);

    sessionLoading = false;
    sessionLoadingLabel = null;
    sessionReady = true;
    notifyListeners();
  }

  void resetToStartup() {
    sessionReady = false;
    sessionLoading = false;
    sessionLoadingLabel = null;
    imagePaths = [];
    currentIndex = 0;
    selectedImagePaths.clear();
    homeRoster = const [];
    awayRoster = const [];
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = null;
    pinnedVerb = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    personality = '';
    manualCaptionOverride = null;
    notifyListeners();
  }

  Future<void> loadRosters({
    List<Player>? homeOverride,
    List<Player>? awayOverride,
  }) async {
    rostersLoading = true;
    rosterError = null;
    rosterSourceLabel = '';
    notifyListeners();
    try {
      _api.setSport(sport);
      final useTank01 = tank01SupportsSport(sport) &&
          (await _prefs?.getUseTank01Rosters() ?? false);
      final apiSource = _rosterSourceFor(sport, useTank01);
      rosterSourceLabel = homeOverride != null && awayOverride != null
          ? 'Pasted rosters'
          : homeOverride != null || awayOverride != null
              ? '$apiSource + pasted roster'
              : apiSource;
      final results = await Future.wait([
        homeOverride == null
            ? _api.fetchTeamRoster(homeTeam)
            : Future.value(homeOverride),
        awayOverride == null
            ? _api.fetchTeamRoster(awayTeam)
            : Future.value(awayOverride),
      ]);
      homeRoster = _sortPlayers(results[0]);
      awayRoster = _sortPlayers(results[1]);
    } catch (e) {
      rosterError = e.toString();
      // Fallback demo roster so UI remains reviewable offline.
      homeRoster = homeOverride == null
          ? _demoRoster(homeTeam)
          : _sortPlayers(homeOverride);
      awayRoster = awayOverride == null
          ? _demoRoster(awayTeam)
          : _sortPlayers(awayOverride);
    } finally {
      rostersLoading = false;
      notifyListeners();
    }
  }

  static String _rosterSourceFor(String sport, bool useTank01) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return useTank01 ? 'Tank01 MLB' : 'MLB API';
      case 'hockey':
        return useTank01 ? 'Tank01 NHL' : 'NHL API';
      case 'basketball':
        return useTank01 ? 'Tank01 NBA' : 'ESPN NBA';
      case 'wnba':
        return useTank01 ? 'Tank01 WNBA' : 'ESPN WNBA';
      case 'soccer':
        return 'ESPN MLS';
      default:
        return '';
    }
  }

  Future<void> pickImageFolder() async {
    final dir = await NativeFilePicker.pickDirectory();
    if (dir == null) return;
    await loadFolder(dir);
  }

  Future<void> loadFolder(String dirPath) async {
    loadingImages = true;
    notifyListeners();
    try {
      final dir = Directory(dirPath);
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .where((f) {
            final ext = p.extension(f.path).toLowerCase();
            return const {'.jpg', '.jpeg', '.tif', '.tiff', '.png'}
                .contains(ext);
          })
          .map((f) => f.path)
          .toList();
      files.sort();
      imagePaths = files;
      currentIndex = 0;
      selectedImagePaths.clear();
      savedImages.clear();
      captionedImages.clear();
      sentImages.clear();
      captureByPath.clear();
      await _loadCaptureTimes();
      await _restoreSavedPrefs(dirPath);
      await _applyIptcTemplateOnImportIfEnabled();
      await _refreshFrameIptc();
    } finally {
      loadingImages = false;
      notifyListeners();
    }
  }

  Future<Map<String, String>> _loadSelectedIptcPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('selected_metadata_preset');
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        final s = v?.toString().trim() ?? '';
        if (s.isNotEmpty) out[k.toString()] = s;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _loadIptcClearedFields() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          prefs.getStringList('selected_metadata_preset_cleared_fields');
      return list?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _applyIptcTemplateOnImportIfEnabled() async {
    if (imagePaths.isEmpty || _prefs == null) return;
    try {
      final mode = await _prefs!.getIptcApplyMode();
      if (mode != IptcApplyMode.onImport) return;
      final preset = await _loadSelectedIptcPreset();
      final cleared = await _loadIptcClearedFields();
      if (preset.isEmpty && cleared.isEmpty) return;
      sessionLoadingLabel =
          'Writing IPTC template to ${imagePaths.length} images…';
      notifyListeners();
      var i = 0;
      for (final path in imagePaths) {
        await IptcTemplateApplyService.applyToImage(
          path,
          preset,
          imageIndex: i,
          fieldsToClear: cleared.isNotEmpty ? cleared : null,
        );
        i++;
      }
    } catch (e) {
      statusMessage = 'IPTC on import failed: $e';
    }
  }

  Future<bool> _applyIptcTemplateOnSaveIfEnabled(String imagePath) async {
    if (_prefs == null) return true;
    try {
      if (await _prefs!.getIptcApplyMode() != IptcApplyMode.onSave) {
        return true;
      }
      final preset = await _loadSelectedIptcPreset();
      final cleared = await _loadIptcClearedFields();
      if (preset.isEmpty && cleared.isEmpty) return true;
      final index = imagePaths.indexOf(imagePath);
      final result = await IptcTemplateApplyService.applyToImage(
        imagePath,
        preset,
        imageIndex: index >= 0 ? index : null,
        fieldsToClear: cleared.isNotEmpty ? cleared : null,
      );
      return result.success;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadCaptureTimes() async {
    for (final path in imagePaths) {
      try {
        final proc = await ExiftoolHelper.run([
          '-s3',
          '-DateTimeOriginal',
          '-d',
          '%Y:%m:%d %H:%M:%S',
          path,
        ]);
        if (proc.isSuccess) {
          final raw = proc.stdoutText.trim().split('\n').first.trim();
          final parsed = _parseExifDate(raw);
          if (parsed != null) {
            captureByPath[path] = parsed;
            continue;
          }
        }
      } catch (_) {}
      try {
        captureByPath[path] = await File(path).lastModified();
      } catch (_) {}
    }
    // Re-sort by capture time when available.
    imagePaths.sort((a, b) {
      final ta = captureByPath[a];
      final tb = captureByPath[b];
      if (ta != null && tb != null) return ta.compareTo(tb);
      return a.compareTo(b);
    });
  }

  DateTime? _parseExifDate(String raw) {
    // 2024:06:09 19:08:56
    final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  Future<void> _restoreSavedPrefs(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'caption_v2_saved_${folder.hashCode}';
    final list = prefs.getStringList(key) ?? const [];
    savedImages.addAll(list);
    final captionedKey = 'caption_v2_captioned_${folder.hashCode}';
    final captionedList = prefs.getStringList(captionedKey) ?? const [];
    captionedImages.addAll(captionedList);
  }

  Future<void> _persistSaved() async {
    if (imagePaths.isEmpty) return;
    final folder = p.dirname(imagePaths.first);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'caption_v2_saved_${folder.hashCode}',
      savedImages.toList(),
    );
    await prefs.setStringList(
      'caption_v2_captioned_${folder.hashCode}',
      captionedImages.toList(),
    );
  }

  Future<void> _refreshFtpDestination() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final current = await prefs.getCurrentFtpProfile();
    if (current != null && current.isNotEmpty) {
      destinationLabel = '$current · FTP';
    }
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void selectPlayer(Player player, {required bool isHome}) {
    captionSelectionStarted = true;
    final existingIndex = selectedPlayers.indexWhere(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
    if (existingIndex >= 0) {
      selectedPlayers.removeAt(existingIndex);
    } else {
      selectedPlayers.add(RosterHit(player: player, isHome: isHome));
    }
    manualCaptionOverride = null;
    _syncPrimaryPlayer();
    _syncKeywords();
    notifyListeners();
  }

  void _syncPrimaryPlayer() {
    if (selectedPlayers.isEmpty) {
      selectedPlayer = null;
      _syncPersonality();
      return;
    }
    selectedPlayer = selectedPlayers.first.player;
    selectedIsHome = selectedPlayers.first.isHome;
    _syncPersonality();
  }

  void _syncPersonality() {
    if (!showPersonalityField) return;
    final merged = <String>[];
    final seen = <String>{};
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) return;
      merged.add(trimmed);
    }

    for (final name in _basePersonalityNames) {
      add(name);
    }
    for (final row in selectedPlayers) {
      add(row.player.fullName);
    }
    personality = merged.join(';');
  }

  void setSelectedPlayers(Iterable<RosterHit> players) {
    captionSelectionStarted = true;
    selectedPlayers.clear();
    for (final row in players) {
      if (!isPlayerSelected(row.player, isHome: row.isHome)) {
        selectedPlayers.add(row);
      }
    }
    _syncPrimaryPlayer();
    notifyListeners();
  }

  void setPersonality(String value) {
    personality = value;
    _basePersonalityNames
      ..clear()
      ..addAll(_parseMetadataList(value).where(
        (name) => !selectedPlayers.any(
          (row) => row.player.fullName.toLowerCase() == name.toLowerCase(),
        ),
      ));
    notifyListeners();
  }

  void setHeadline(String value) {
    headline = value;
    metadataDirty = true;
    notifyListeners();
  }

  void setKeywords(String value) {
    keywords = _dedupeMetadataList(value, separator: ', ');
    _baseKeywordKeys
      ..clear()
      ..addAll(_parseMetadataList(keywords).map((e) => e.toLowerCase()));
    _managedKeywordKeys.clear();
    metadataDirty = true;
    notifyListeners();
  }

  void setManualCaption(String? value) {
    manualCaptionOverride = value;
    notifyListeners();
  }

  void applyTransferredCaption(CaptionTransferPayload payload) {
    customVerbPhrase = '';
    customVerbPinned = false;
    manualCaptionOverride = payload.caption;
    personality = payload.personality;
    notifyListeners();
  }

  bool applyPreviousCaption() {
    final previous = previousCaption;
    if (previous == null) return false;
    applyTransferredCaption(previous);
    return true;
  }

  void resetCurrentCaption() {
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    rbi = 0;
    selectedBase = null;
    preGame = false;
    postGame = false;
    manualCaptionOverride = null;
    personality = originalPersonality;
    statusMessage = null;
    notifyListeners();
  }

  void selectVerb(String verb) {
    captionSelectionStarted = true;
    if (selectedVerb != verb) celebrationType = null;
    selectedVerb = verb;
    customVerbPhrase = '';
    customVerbPinned = false;
    manualCaptionOverride = null;
    if (!_verbNeedsRbi(verb)) {
      rbi = 0;
    }
    if (!_verbNeedsBase(verb)) {
      selectedBase = null;
    }
    _syncKeywords();
    notifyListeners();
  }

  void clearSelectedVerb() {
    if (selectedVerb == null &&
        customVerbPhrase.trim().isEmpty &&
        celebrationType == null &&
        rbi == 0 &&
        selectedBase == null) {
      return;
    }
    selectedVerb = null;
    customVerbPhrase = '';
    customVerbPinned = false;
    celebrationType = null;
    rbi = 0;
    selectedBase = null;
    manualCaptionOverride = null;
    captionSelectionStarted = selectedPlayers.isNotEmpty || pinnedVerb != null;
    _syncKeywords();
    notifyListeners();
  }

  void setCustomVerbPhrase(String value) {
    customVerbPhrase = value;
    final custom = value.trim();
    if (custom.isNotEmpty) {
      lastCustomVerbPhrase = custom;
      captionSelectionStarted = true;
      selectedVerb = null;
      pinnedVerb = null;
      celebrationType = null;
      rbi = 0;
      selectedBase = null;
      manualCaptionOverride = null;
      _syncKeywords();
    } else {
      customVerbPinned = false;
      captionSelectionStarted =
          selectedPlayers.isNotEmpty || selectedVerb != null;
    }
    notifyListeners();
  }

  void toggleCustomVerbPin() {
    if (customVerbPhrase.trim().isEmpty) return;
    customVerbPinned = !customVerbPinned;
    notifyListeners();
  }

  void useLastCustomVerb() {
    if (lastCustomVerbPhrase.isEmpty) return;
    setCustomVerbPhrase(lastCustomVerbPhrase);
  }

  void toggleVerbPin(String verb) {
    pinnedVerb = pinnedVerb == verb ? null : verb;
    if (pinnedVerb != null) selectVerb(verb);
    notifyListeners();
  }

  void unpinVerb() {
    if (pinnedVerb == null) return;
    pinnedVerb = null;
    notifyListeners();
  }

  Future<void> toggleVerbFavorite(String verb) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final favorites = await prefs.getFavoriteVerbs(sport: sport);
    if (!favorites.remove(verb)) favorites.add(verb);
    await prefs.saveFavoriteVerbs(favorites, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> deleteVerb(String verb) async {
    final prefs = _prefs;
    final definition = verbDefinition(verb);
    if (prefs == null || definition == null) return;
    if (definition.isCustom) {
      final customs = await prefs.getCustomVerbs(sport: sport)
        ..removeWhere((item) =>
            item['label']?.toString() == verb ||
            item['verbPhrase']?.toString() == verb);
      await prefs.saveCustomVerbs(customs, sport: sport);
    } else {
      await prefs.addDeletedVerb(verb, sport: sport);
      await prefs.removeVerbOverride(verb, sport: sport);
    }
    final favorites = await prefs.getFavoriteVerbs(sport: sport)
      ..remove(verb);
    await prefs.saveFavoriteVerbs(favorites, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> moveVerb(String verb, String category, int index) async {
    final prefs = _prefs;
    if (prefs == null || !_verbCatalog.byKey.containsKey(verb)) return;
    final order = {
      for (final entry in _verbCatalog.verbsByCategory.entries)
        if (entry.key != 'Favorites')
          entry.key: entry.value.map((item) => item.key).toList(),
    };
    for (final verbs in order.values) {
      verbs.remove(verb);
    }
    final target = order.putIfAbsent(category, () => <String>[]);
    target.insert(index.clamp(0, target.length), verb);
    await prefs.saveVerbOrder(order, sport: sport);
    final definition = verbDefinition(verb);
    if (definition != null && definition.category != category) {
      if (definition.isCustom) {
        final customs = await prefs.getCustomVerbs(sport: sport);
        final customIndex =
            customs.indexWhere((item) => item['label']?.toString() == verb);
        if (customIndex >= 0) customs[customIndex]['category'] = category;
        await prefs.saveCustomVerbs(customs, sport: sport);
      } else {
        final overrides = await prefs.getVerbOverrides(sport: sport);
        final override = Map<String, dynamic>.from(overrides[verb] ?? {});
        override['category'] = category;
        await prefs.saveVerbOverride(verb, override, sport: sport);
      }
    }
    await _loadVerbCatalog();
    verbCategory = category;
    notifyListeners();
  }

  Future<void> saveVerbOrder(
    Map<String, List<String>> order,
  ) async {
    await _prefs?.saveVerbOrder(order, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> saveCategoryOrder(List<String> order) async {
    await _prefs?.saveCategoryOrder(order, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> reloadVerbCatalog() async {
    await _loadVerbCatalog();
    notifyListeners();
  }

  Map<String, dynamic> verbEditorInitialData(String verb) {
    final definition = verbDefinition(verb);
    if (definition == null) return const {};
    return {
      'label': definition.label,
      'verbPhrase': definition.singularPhrase,
      'pluralPhrase': definition.pluralPhrase,
      'ingPhrase': definition.ingPhrase,
      'usePluralPhrase': true,
      'keywords': definition.keywords,
      'wantsOpponent': definition.wantsOpponent,
      'category': definition.category,
      'subOptions': definition.subOptions,
    };
  }

  Map<String, dynamic> _verbRecord({
    required String label,
    required String singular,
    required String pluralText,
    required String ingText,
    required bool usePluralPhrase,
    required List<String> keywords,
    required bool wantsOpponent,
    required String category,
    required VerbSubOptions subOptions,
    required bool isCustom,
  }) {
    return {
      'label': label,
      'verbPhrase': singular,
      'pluralPhrase': usePluralPhrase ? pluralText : null,
      'ingPhrase': ingText,
      'usePluralPhrase': usePluralPhrase,
      'keywords': keywords,
      'wantsOpponent': wantsOpponent,
      'category': category,
      'isCustom': isCustom,
      'subOptions': subOptions.toJson(),
    };
  }

  Future<void> createCustomVerb({
    required String label,
    required String singular,
    required String pluralText,
    required String ingText,
    required bool usePluralPhrase,
    required List<String> keywords,
    required bool wantsOpponent,
    required String category,
    required VerbSubOptions subOptions,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.addCustomVerb(
      _verbRecord(
        label: label,
        singular: singular,
        pluralText: pluralText,
        ingText: ingText,
        usePluralPhrase: usePluralPhrase,
        keywords: keywords,
        wantsOpponent: wantsOpponent,
        category: category,
        subOptions: subOptions.copyWith(rbiEnabled: false),
        isCustom: true,
      ),
      sport: sport,
    );
    final order = {
      for (final entry in _verbCatalog.verbsByCategory.entries)
        if (entry.key != 'Favorites')
          entry.key: entry.value.map((item) => item.key).toList(),
    };
    order.putIfAbsent(category, () => <String>[]).add(label);
    await prefs.saveVerbOrder(order, sport: sport);
    await _loadVerbCatalog();
    verbCategory = category;
    notifyListeners();
  }

  Future<void> updateCustomVerb({
    required String previousLabel,
    required String label,
    required String singular,
    required String pluralText,
    required String ingText,
    required bool usePluralPhrase,
    required List<String> keywords,
    required bool wantsOpponent,
    required String category,
    required VerbSubOptions subOptions,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final customs = await prefs.getCustomVerbs(sport: sport);
    final record = _verbRecord(
      label: label,
      singular: singular,
      pluralText: pluralText,
      ingText: ingText,
      usePluralPhrase: usePluralPhrase,
      keywords: keywords,
      wantsOpponent: wantsOpponent,
      category: category,
      subOptions: subOptions.copyWith(rbiEnabled: false),
      isCustom: true,
    );
    final index = customs
        .indexWhere((item) => item['label']?.toString() == previousLabel);
    if (index < 0) {
      customs.add(record);
    } else {
      customs[index] = record;
    }
    await prefs.saveCustomVerbs(customs, sport: sport);
    final order = await prefs.getVerbOrder(sport: sport);
    for (final verbs in order.values) {
      final oldIndex = verbs.indexOf(previousLabel);
      if (oldIndex >= 0) verbs[oldIndex] = label;
      verbs.remove(label);
    }
    order.putIfAbsent(category, () => <String>[]).add(label);
    await prefs.saveVerbOrder(order, sport: sport);
    final favorites = await prefs.getFavoriteVerbs(sport: sport);
    if (favorites.remove(previousLabel)) {
      favorites.add(label);
      await prefs.saveFavoriteVerbs(favorites, sport: sport);
    }
    if (selectedVerb == previousLabel) selectedVerb = label;
    if (pinnedVerb == previousLabel) pinnedVerb = label;
    await _loadVerbCatalog();
    verbCategory = category;
    notifyListeners();
  }

  Future<void> saveBuiltInVerb({
    required String key,
    required String label,
    required String singular,
    required String pluralText,
    required String ingText,
    required bool usePluralPhrase,
    required List<String> keywords,
    required bool wantsOpponent,
    required String category,
    required VerbSubOptions subOptions,
    required bool asDefault,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final override = _verbRecord(
      label: label,
      singular: singular,
      pluralText: pluralText,
      ingText: ingText,
      usePluralPhrase: usePluralPhrase,
      keywords: keywords,
      wantsOpponent: wantsOpponent,
      category: category,
      subOptions: subOptions,
      isCustom: false,
    );
    await prefs.saveVerbOverride(key, override, sport: sport);
    await prefs.saveCustomVerbWording(key, singular, sport: sport);
    if (asDefault) {
      await prefs.saveVerbWordingDefault(key, override, sport: sport);
    }
    await moveVerb(key, category, 9999);
  }

  Future<void> resetBuiltInVerb(String key) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final savedDefault = await prefs.getVerbWordingDefault(key, sport: sport);
    if (savedDefault == null) {
      await prefs.removeVerbOverride(key, sport: sport);
      await prefs.removeCustomVerbWording(key, sport: sport);
    } else {
      await prefs.saveVerbOverride(key, savedDefault, sport: sport);
      final singular = savedDefault['verbPhrase']?.toString() ??
          VerbCaptionWording.defaultWording(key);
      await prefs.saveCustomVerbWording(key, singular, sport: sport);
    }
    await _loadVerbCatalog();
    notifyListeners();
  }

  bool verbNeedsRbi(String verb) => _verbNeedsRbi(verb);

  bool verbNeedsBase(String verb) => _verbNeedsBase(verb);

  bool verbNeedsCelebration(String verb) {
    final definition = verbDefinition(verb);
    final options = definition?.subOptions ??
        VerbSubOptions.defaultsFor(verb, sport: sport);
    return VerbSubOptions.showCelebrationEditor(
          verbLabel: verb,
          value: options,
          isCustom: definition?.isCustom ?? false,
        ) &&
        options.celebrationEnabled;
  }

  List<String> celebrationOptionsFor(String verb) {
    if (VerbSubOptions.isHitVerb(verb)) {
      return reactionOptionsFor(verb);
    }
    return celebrationTypeOptionsFor(verb);
  }

  List<String> reactionOptionsFor(String verb) {
    return const ['Celebrates', 'Reacts'];
  }

  List<String> celebrationTypeOptionsFor(String verb) {
    final definition = verbDefinition(verb);
    final options = definition?.subOptions ??
        VerbSubOptions.defaultsFor(verb, sport: sport);
    return options.celebrationTypeList(sport: sport);
  }

  void setCelebrationType(String? value) {
    if (celebrationType == value) return;
    celebrationType = value;
    manualCaptionOverride = null;
    _syncKeywords();
    notifyListeners();
  }

  bool _verbNeedsRbi(String verb) {
    return const {
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'Sacrifice Fly',
      'Grand Slam',
    }.contains(verb);
  }

  bool _verbNeedsBase(String verb) {
    return CaptionV2CaptionDomain.runningVerbs.contains(verb);
  }

  void setRbi(int value) {
    rbi = value.clamp(0, 4);
    manualCaptionOverride = null;
    _syncKeywords();
    notifyListeners();
  }

  void setSelectedBase(String? value) {
    final next = value?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (selectedBase == normalized) return;
    selectedBase = normalized;
    manualCaptionOverride = null;
    _syncKeywords();
    notifyListeners();
  }

  void setVerbCategory(String cat) {
    verbCategory = cat;
    notifyListeners();
  }

  void bumpInning(int delta) {
    final max = timingMaxInning;
    inning = (inning + delta).clamp(1, max);
    if (delta != 0) {
      manualCaptionOverride = null;
      preGame = false;
      postGame = false;
      mlbTimestampMatchedPath = null;
    }
    notifyListeners();
  }

  void setInning(int value) {
    final max = timingMaxInning;
    final next = value.clamp(1, max);
    if (next == inning && !preGame && !postGame) {
      notifyListeners();
      return;
    }
    inning = next;
    manualCaptionOverride = null;
    preGame = false;
    postGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void setPre(bool v) {
    preGame = v;
    manualCaptionOverride = null;
    if (v) postGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void setPost(bool v) {
    postGame = v;
    manualCaptionOverride = null;
    if (v) preGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void activateInning() {
    if (!preGame && !postGame) return;
    preGame = false;
    postGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  Future<void> toggleMlbTimestamp() async {
    if (!mlbTimestampAvailable || sport.toLowerCase() != 'baseball') return;
    if (!mlbTimestampEnabled) {
      mlbTimestampEnabled = true;
      await _prefs?.setMlbInningFromClockEnabled(true);
      await applyMlbTimestamp(userInitiated: true);
      return;
    }
    if (mlbTimestampMatched) {
      mlbTimestampEnabled = false;
      mlbTimestampMatchedPath = null;
      _mlbTimestampToken++;
      await _prefs?.setMlbInningFromClockEnabled(false);
      notifyListeners();
      return;
    }
    await applyMlbTimestamp(userInitiated: true);
  }

  Future<void> applyMlbTimestamp({bool userInitiated = false}) async {
    if (!mlbTimestampEnabled && !userInitiated) return;
    final path = currentPath;
    if (path == null) {
      _mlbTimestampFailure('No image selected.', userInitiated);
      return;
    }
    if (sport.toLowerCase() != 'baseball') {
      _mlbTimestampFailure(
        'Switch to baseball to use MLB timestamp.',
        userInitiated,
      );
      return;
    }
    if (!mlbTimestampAvailable) {
      _mlbTimestampFailure(
        'MLB timestamp is not enabled for this account.',
        userInitiated,
      );
      return;
    }

    final wall = MlbInningFromTimestampService.parseExifDateTimeOriginal(
        currentIptcMeta);
    if (wall == null) {
      _mlbTimestampFailure(
        'No EXIF capture time found for this image.',
        userInitiated,
      );
      return;
    }
    final prefs = _prefs;
    if (prefs == null) return;
    final timezone = await prefs.getMlbInningExifTimezone();
    final photoUtc =
        MlbInningFromTimestampService.naiveWallClockToUtc(timezone, wall);
    if (photoUtc == null) {
      _mlbTimestampFailure(
        'Invalid MLB EXIF timezone in Preferences.',
        userInitiated,
      );
      return;
    }
    final gameInfo = await prefs.getCaptionGameInfo();
    final gameDay = gameInfo.gameDate ?? wall;
    final token = ++_mlbTimestampToken;
    mlbTimestampLoading = true;
    notifyListeners();

    try {
      final lookup = await _mlbTimestamp.lookupPhotoInning(
        userHomeName: homeTeam,
        userAwayName: awayTeam,
        gameCalendarDay: gameDay,
        photoTimeUtc: photoUtc,
      );
      if (token != _mlbTimestampToken || path != currentPath) return;
      if (!lookup.hasScheduleMatch) {
        _mlbTimestampFailure(
          'No MLB game matched these teams on the game date.',
          userInitiated,
        );
        return;
      }
      if (!lookup.hasPlayByPlay) {
        _mlbTimestampFailure(
          'No MLB play-by-play timestamps are available.',
          userInitiated,
        );
        return;
      }

      switch (lookup.phase) {
        case MlbPhotoGametimePhase.pregame:
          preGame = true;
          postGame = false;
          break;
        case MlbPhotoGametimePhase.postgame:
          preGame = false;
          postGame = true;
          break;
        case MlbPhotoGametimePhase.live:
          final matchedInning = lookup.inningNumber;
          if (matchedInning == null) {
            _mlbTimestampFailure(
              'Could not map this image time to an inning.',
              userInitiated,
            );
            return;
          }
          inning = matchedInning;
          preGame = false;
          postGame = false;
          break;
      }
      mlbTimestampMatchedPath = path;
      statusMessage = null;
    } catch (error) {
      if (token == _mlbTimestampToken && path == currentPath) {
        _mlbTimestampFailure(
          'MLB timestamp request failed: $error',
          userInitiated,
        );
      }
    } finally {
      if (token == _mlbTimestampToken) {
        mlbTimestampLoading = false;
        notifyListeners();
      }
    }
  }

  void _mlbTimestampFailure(String message, bool userInitiated) {
    mlbTimestampMatchedPath = null;
    if (userInitiated) statusMessage = message;
    notifyListeners();
  }

  void setColumnFocus(int col) {
    columnFocus = col.clamp(0, 3);
    notifyListeners();
  }

  void setSearchQuery(String q) {
    final inningMatch =
        RegExp(r'^(?:i(\d{1,2})|(\d{1,2})i)$', caseSensitive: false)
            .firstMatch(q.trim());
    final inningValue = int.tryParse(
      inningMatch?.group(1) ?? inningMatch?.group(2) ?? '',
    );
    if (inningValue != null &&
        inningValue >= 1 &&
        inningValue <= timingMaxInning) {
      inning = inningValue;
      preGame = false;
      postGame = false;
      manualCaptionOverride = null;
      mlbTimestampMatchedPath = null;
      searchQuery = '';
      firebarSelectionIndex = firebarOrderedResults.isEmpty ? -1 : 0;
      notifyListeners();
      return;
    }
    if (firebarOptions.isNotEmpty) {
      searchQuery = q;
      firebarOptionIndex = 0;
      notifyListeners();
      return;
    }
    final selectedKey = firebarSelectedResult?.key;
    searchQuery = q;
    final results = firebarOrderedResults;
    final retained = selectedKey == null
        ? -1
        : results.indexWhere((r) => r.key == selectedKey);
    firebarSelectionIndex =
        retained >= 0 ? retained : (results.isEmpty ? -1 : 0);
    notifyListeners();
  }

  void setSearchOpen(bool open) {
    if (open && !searchOpen) {
      searchQuery = '';
      guidedSearchPrompt = null;
      _guidedSearchHits = const [];
      _pendingCommandInning = null;
      _clearFirebarOptions();
      _firebarCommitted
        ..clear()
        ..addAll(
          selectedPlayers.map(
            (row) => FirebarResult.player(
              player: row.player,
              isHome: row.isHome,
            ),
          ),
        );
      if (selectedVerb != null) {
        _firebarCommitted.add(FirebarResult.verb(selectedVerb));
      }
    }
    searchOpen = open;
    firebarSelectionIndex = open && firebarOrderedResults.isNotEmpty ? 0 : -1;
    if (!open) {
      searchQuery = '';
      guidedSearchPrompt = null;
      _guidedSearchHits = const [];
      _pendingCommandInning = null;
      _firebarCommitted.clear();
      _clearFirebarOptions();
    }
    notifyListeners();
  }

  void moveFirebarSelection(int delta) {
    if (firebarOptions.isNotEmpty) {
      final options = filteredFirebarOptions;
      if (options.isEmpty || delta == 0) return;
      firebarOptionIndex =
          (firebarOptionIndex + delta).clamp(0, options.length - 1);
      notifyListeners();
      return;
    }
    final results = firebarOrderedResults;
    if (!searchOpen || results.isEmpty || delta == 0) return;
    final start = firebarSelectionIndex < 0 ? 0 : firebarSelectionIndex;
    final next = (start + delta).clamp(0, results.length - 1);
    if (next == firebarSelectionIndex) return;
    firebarSelectionIndex = next;
    notifyListeners();
  }

  void selectFirebarResult(FirebarResult result) {
    final index = firebarOrderedResults
        .indexWhere((candidate) => candidate.key == result.key);
    if (index < 0 || index == firebarSelectionIndex) return;
    firebarSelectionIndex = index;
    notifyListeners();
  }

  void commitSelectedFirebarResult() {
    if (firebarOptions.isNotEmpty) {
      final options = filteredFirebarOptions;
      if (options.isEmpty) return;
      chooseFirebarOption(
        options[firebarOptionIndex.clamp(0, options.length - 1)],
      );
      return;
    }
    final result = firebarSelectedResult;
    if (result != null) commitFirebarResult(result);
  }

  void commitFirebarResult(FirebarResult result) {
    captionSelectionStarted = true;
    manualCaptionOverride = null;
    if (result.kind == FirebarResultKind.player) {
      final player = result.player!;
      final isHome = result.isHome!;
      if (!isPlayerSelected(player, isHome: isHome)) {
        selectedPlayers.add(RosterHit(player: player, isHome: isHome));
      }
      _syncPrimaryPlayer();
      _syncPersonality();
    } else {
      final verb = result.verbKey!;
      selectedVerb = verb;
      customVerbPhrase = '';
      customVerbPinned = false;
      celebrationType = null;
      if (!_verbNeedsRbi(verb)) rbi = 0;
      if (!_verbNeedsBase(verb)) selectedBase = null;
      _firebarCommitted.removeWhere(
        (item) => item.kind == FirebarResultKind.verb,
      );
      _prepareFirebarOptions(verb);
    }
    if (!_firebarCommitted.any((item) => item.key == result.key)) {
      _firebarCommitted.add(result);
    }
    _syncKeywords();
    searchQuery = '';
    firebarSelectionIndex = firebarOrderedResults.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void removeFirebarChip(FirebarResult result) {
    final removed = _firebarCommitted.any((item) => item.key == result.key);
    if (!removed) return;
    _firebarCommitted.removeWhere((item) => item.key == result.key);
    if (result.kind == FirebarResultKind.player) {
      selectedPlayers.removeWhere(
        (row) =>
            row.isHome == result.isHome &&
            _samePlayer(row.player, result.player!),
      );
      _syncPrimaryPlayer();
    } else if (selectedVerb == result.verbKey) {
      selectedVerb = null;
      celebrationType = null;
      rbi = 0;
      selectedBase = null;
      _clearFirebarOptions();
    }
    if (_firebarCommitted.isEmpty) {
      captionSelectionStarted = false;
      manualCaptionOverride = null;
    }
    _syncKeywords();
    firebarSelectionIndex = firebarOrderedResults.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void removeLastFirebarChip() {
    if (_firebarCommitted.isEmpty) return;
    removeFirebarChip(_firebarCommitted.last);
  }

  void _prepareFirebarOptions(String verb) {
    if (verb == 'Home Run') {
      firebarOptionPrompt = 'Home run type?';
      _firebarOptionKind = FirebarOptionKind.homeRun;
      firebarOptions = const [
        FirebarOption('1R', rbi: 1),
        FirebarOption('2R', rbi: 2),
        FirebarOption('3R', rbi: 3),
        FirebarOption('GS', rbi: 4, verbOverride: 'Grand Slam'),
      ];
    } else if (_verbNeedsRbi(verb)) {
      firebarOptionPrompt = 'How many RBI?';
      _firebarOptionKind = FirebarOptionKind.rbi;
      firebarOptions = const [
        FirebarOption('0 RBI', rbi: 0),
        FirebarOption('1 RBI', rbi: 1),
        FirebarOption('2 RBI', rbi: 2),
        FirebarOption('3 RBI', rbi: 3),
      ];
    } else if (_verbNeedsBase(verb)) {
      firebarOptionPrompt = 'Which base?';
      _firebarOptionKind = FirebarOptionKind.base;
      firebarOptions = const [
        FirebarOption('1B', base: '1B'),
        FirebarOption('2B', base: '2B'),
        FirebarOption('3B', base: '3B'),
        FirebarOption('Home', base: 'Home'),
      ];
    } else if (verbNeedsCelebration(verb)) {
      _prepareFirebarCelebrationOptions(verb);
    } else {
      _clearFirebarOptions();
    }
    firebarOptionIndex = 0;
  }

  void _prepareFirebarCelebrationOptions(String verb) {
    firebarOptionPrompt =
        VerbSubOptions.isHitVerb(verb) ? 'Reaction?' : 'Celebration?';
    _firebarOptionKind = FirebarOptionKind.celebration;
    firebarOptions = [
      const FirebarOption('None'),
      ...celebrationOptionsFor(verb).map(
        (value) => FirebarOption(value, celebration: value),
      ),
    ];
    firebarOptionIndex = 0;
  }

  void chooseFirebarOption(FirebarOption option) {
    final kind = _firebarOptionKind;
    if (kind == null) return;
    if (option.verbOverride != null) {
      selectedVerb = option.verbOverride;
      _firebarCommitted.removeWhere(
        (item) => item.kind == FirebarResultKind.verb,
      );
      _firebarCommitted.add(FirebarResult.verb(option.verbOverride));
    }
    if (option.rbi != null) rbi = option.rbi!;
    if (option.base != null) selectedBase = option.base;
    if (kind == FirebarOptionKind.celebration) {
      celebrationType = option.celebration;
    }
    final verb = selectedVerb;
    searchQuery = '';
    _clearFirebarOptions();
    if (kind != FirebarOptionKind.celebration &&
        verb != null &&
        verbNeedsCelebration(verb)) {
      _prepareFirebarCelebrationOptions(verb);
    }
    _syncKeywords();
    notifyListeners();
  }

  void _clearFirebarOptions() {
    firebarOptionPrompt = null;
    _firebarOptionKind = null;
    firebarOptions = const [];
    firebarOptionIndex = 0;
  }

  void toggleSort() {
    cycleRosterSortField();
  }

  /// Cycles # → First → Last → # (direction unchanged).
  void cycleRosterSortField() {
    switch (rosterSort) {
      case RosterSortMode.number:
        rosterSort = RosterSortMode.firstName;
        break;
      case RosterSortMode.firstName:
        rosterSort = RosterSortMode.lastName;
        break;
      case RosterSortMode.lastName:
        rosterSort = RosterSortMode.number;
        break;
    }
    homeRoster = _sortPlayers(homeRoster);
    awayRoster = _sortPlayers(awayRoster);
    notifyListeners();
  }

  /// Toggles ascending ↔ descending without changing the sort field.
  void toggleRosterSortDirection() {
    rosterSortAscending = !rosterSortAscending;
    homeRoster = _sortPlayers(homeRoster);
    awayRoster = _sortPlayers(awayRoster);
    notifyListeners();
  }

  String rosterSortFieldLabel() {
    switch (rosterSort) {
      case RosterSortMode.number:
        return '#';
      case RosterSortMode.firstName:
        return 'First';
      case RosterSortMode.lastName:
        return 'Last';
    }
  }

  String rosterSortDirectionLabel() => rosterSortAscending ? '↑' : '↓';

  String rosterSortLabel() =>
      '${rosterSortFieldLabel()}${rosterSortDirectionLabel()}';

  String playerListName(Player player) {
    switch (rosterSort) {
      case RosterSortMode.lastName:
        final last = playerLastName(player);
        if (last == player.fullName.trim()) return player.fullName;
        return '$last, ${player.firstName}';
      case RosterSortMode.firstName:
      case RosterSortMode.number:
        return player.fullName;
    }
  }

  static String playerLastName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return player.fullName.trim();
    return parts.sublist(1).join(' ');
  }

  void rememberCombo() {
    if (selectedVerb == null) return;
    final combo = LastUsedCombo(
      verb: selectedVerb!,
      rbi: rbi,
      playerLabel: selectedPlayer == null ? null : playerChipLabel,
      verbLabel: verbDefinition(selectedVerb!)?.label,
    );
    lastUsed.removeWhere((c) => c.verb == combo.verb && c.rbi == combo.rbi);
    lastUsed.insert(0, combo);
    if (lastUsed.length > 8) lastUsed.removeLast();
  }

  void applyLastUsed([LastUsedCombo? combo]) {
    final c = combo ?? (lastUsed.isEmpty ? null : lastUsed.first);
    if (c == null || !_verbCatalog.byKey.containsKey(c.verb)) return;
    captionSelectionStarted = true;
    selectedVerb = c.verb;
    customVerbPhrase = '';
    customVerbPinned = false;
    rbi = c.rbi;
    final cat = _categoryForVerb(c.verb);
    if (cat != null) verbCategory = cat;
    notifyListeners();
  }

  String? _categoryForVerb(String verb) {
    for (final e in verbsByCategory.entries) {
      if (e.value.contains(verb)) return e.key;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void goToIndex(int index) {
    if (imagePaths.isEmpty) return;
    currentIndex = index.clamp(0, imagePaths.length - 1);
    _clearCaptionSelection();
    searchQuery = '';
    searchOpen = false;
    guidedSearchPrompt = null;
    _guidedSearchHits = const [];
    _pendingCommandInning = null;
    mlbTimestampMatchedPath = null;
    mlbTimestampLoading = false;
    _mlbTimestampToken++;
    notifyListeners();
    unawaited(_refreshFrameIptc());
  }

  void nextFrame() => goToIndex(currentIndex + 1);
  void prevFrame() => goToIndex(currentIndex - 1);

  /// Re-read the current frame after an external IPTC or file operation.
  Future<void> refreshCurrentFrameMetadata() => _refreshFrameIptc();

  Future<Map<String, String>> readIptcPanelValues(String path) async {
    final metadata = await IptcTemplateImportService.readMetadata(path);
    if (metadata == null) return {};
    return IptcTemplateImportService.panelValuesFromExiftool(metadata);
  }

  Future<bool> writeIptcPanelValues(
    String path,
    Map<String, String> values, {
    Set<String>? fieldsToClear,
  }) async {
    final existing = await IptcTemplateImportService.readMetadata(path);
    final result = await IptcTemplateApplyService.applyToImage(
      path,
      values,
      skipInAppGenerated: false,
      existingMetadata: existing,
      fieldsToClear: fieldsToClear,
    );
    if (!result.success) return false;
    if (path == currentPath) await _refreshFrameIptc();
    notifyListeners();
    return true;
  }

  Future<bool> applySelectedIptcTemplate(String path) async {
    final preset = await _loadSelectedIptcPreset();
    final cleared = await _loadIptcClearedFields();
    if (preset.isEmpty && cleared.isEmpty) return false;
    final result = await IptcTemplateApplyService.applyToImage(
      path,
      preset,
      imageIndex: imagePaths.indexOf(path),
      fieldsToClear: cleared.isEmpty ? null : cleared,
    );
    if (!result.success) return false;
    if (path == currentPath) await _refreshFrameIptc();
    notifyListeners();
    return true;
  }

  Future<bool> renameImage(String oldPath, String newFileName) async {
    final nextPath = p.join(p.dirname(oldPath), newFileName);
    if (await File(nextPath).exists()) return false;
    try {
      await File(oldPath).rename(nextPath);
    } catch (_) {
      return false;
    }
    final index = imagePaths.indexOf(oldPath);
    if (index >= 0) imagePaths[index] = nextPath;
    final captured = captureByPath.remove(oldPath);
    if (captured != null) captureByPath[nextPath] = captured;
    if (savedImages.remove(oldPath)) savedImages.add(nextPath);
    if (captionedImages.remove(oldPath)) captionedImages.add(nextPath);
    if (sentImages.remove(oldPath)) sentImages.add(nextPath);
    if (selectedImagePaths.remove(oldPath)) selectedImagePaths.add(nextPath);
    await _persistSaved();
    notifyListeners();
    if (currentPath == nextPath) await _refreshFrameIptc();
    return true;
  }

  Future<bool> deleteImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      await file.delete();
    } catch (_) {
      return false;
    }
    final removedIndex = imagePaths.indexOf(path);
    imagePaths.remove(path);
    captureByPath.remove(path);
    savedImages.remove(path);
    captionedImages.remove(path);
    sentImages.remove(path);
    selectedImagePaths.remove(path);
    if (imagePaths.isEmpty) {
      currentIndex = 0;
    } else if (removedIndex >= 0 && removedIndex < currentIndex) {
      currentIndex--;
    } else if (removedIndex >= 0 && currentIndex >= imagePaths.length) {
      currentIndex = imagePaths.length - 1;
    }
    await _persistSaved();
    notifyListeners();
    await _refreshFrameIptc();
    return true;
  }

  Future<void> transmitPath(String path) => _transmitPaths([path]);

  void clearSentStatus(String path) {
    if (!sentImages.remove(path)) return;
    savedImages.add(path);
    queuedCount = savedNotSentCount;
    notifyListeners();
  }

  String? _metaFirst(List<String> keys) {
    for (final k in keys) {
      final v = currentIptcMeta[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _stringFromMeta(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      for (final item in value) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return null;
    }
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Load the current frame's header EXIF plus caption-related IPTC.
  Future<void> _refreshFrameIptc() async {
    final path = currentPath;
    final gen = ++_iptcLoadGen;
    if (path == null) {
      currentIptcMeta = {};
      photographerName = '';
      agencyName = '';
      notifyListeners();
      return;
    }

    try {
      final proc = await ExiftoolHelper.run([
        '-a',
        '-j',
        '-DateTimeOriginal',
        '-CreateDate',
        '-ModifyDate',
        '-IPTC:Description',
        '-Description',
        '-Caption-Abstract',
        '-IPTC:Caption-Abstract',
        '-ImageDescription',
        '-XMP:Description',
        '-Model',
        '-Make',
        '-ImageWidth',
        '-ImageHeight',
        '-ExifImageWidth',
        '-ExifImageHeight',
        '-ShutterSpeed',
        '-FNumber',
        '-ISO',
        '-LensID',
        '-LensModel',
        '-Lens',
        '-FocalLength',
        '-IPTC:By-line',
        '-By-line',
        '-Byline',
        '-Creator',
        '-XMP:Creator',
        '-Artist',
        '-Photographer',
        '-IPTC:Photographer',
        '-XMP:Photographer',
        '-IPTC:Credit',
        '-Credit',
        '-IPTC:City',
        '-City',
        '-XMP:City',
        '-IPTC:ProvinceState',
        '-Province-State',
        '-ProvinceState',
        '-XMP:State',
        '-IPTC:CountryPrimaryLocationName',
        '-CountryPrimaryLocationName',
        '-Country',
        '-XMP:Country',
        '-IPTC:CountryPrimaryLocationCode',
        '-CountryPrimaryLocationCode',
        '-CountryCode',
        '-IPTC:SubLocation',
        '-Sub-location',
        '-SubLocation',
        '-XMP:Location',
        '-XMP-getty:Personality',
        '-Personality',
        '-IPTC:Headline',
        '-Headline',
        '-XMP:Headline',
        '-IPTC:Keywords',
        '-Keywords',
        '-XMP:Subject',
        '-XMP-dc:Subject',
        path,
      ]);
      if (gen != _iptcLoadGen) return;
      if (!proc.isSuccess) {
        currentIptcMeta = {};
        photographerName = '';
        agencyName = '';
        notifyListeners();
        return;
      }
      final List data = jsonDecode(proc.stdoutText);
      if (data.isEmpty || data.first is! Map) {
        currentIptcMeta = {};
        photographerName = '';
        agencyName = '';
        notifyListeners();
        return;
      }
      final raw = Map<String, dynamic>.from(data.first as Map);
      final meta = <String, String>{};
      raw.forEach((key, value) {
        if (key == 'SourceFile') return;
        final s = _stringFromMeta(value);
        if (s != null) meta[key.toString()] = s;
      });
      currentIptcMeta = meta;
      photographerName = _stringFromMeta(raw['Creator']) ??
          _stringFromMeta(raw['Artist']) ??
          _stringFromMeta(raw['Photographer']) ??
          _stringFromMeta(raw['IPTC:Photographer']) ??
          _stringFromMeta(raw['XMP:Photographer']) ??
          _stringFromMeta(raw['IPTC:By-line']) ??
          _stringFromMeta(raw['By-line']) ??
          _stringFromMeta(raw['Byline']) ??
          _stringFromMeta(raw['XMP:Creator']) ??
          '';
      agencyName = _stringFromMeta(raw['IPTC:Credit']) ??
          _stringFromMeta(raw['Credit']) ??
          '';
      personality = _metadataListFromRaw(
        raw['XMP-getty:Personality'] ?? raw['Personality'],
        separator: ';',
      );
      _basePersonalityNames
        ..clear()
        ..addAll(_parseMetadataList(personality));
      headline = _stringFromMeta(raw['IPTC:Headline']) ??
          _stringFromMeta(raw['Headline']) ??
          _stringFromMeta(raw['XMP:Headline']) ??
          '';
      keywords = _metadataListFromRaw(
        raw['IPTC:Keywords'] ??
            raw['Keywords'] ??
            raw['XMP:Subject'] ??
            raw['XMP-dc:Subject'],
        separator: ', ',
      );
      _baseKeywordKeys
        ..clear()
        ..addAll(_parseMetadataList(keywords).map((e) => e.toLowerCase()));
      _managedKeywordKeys.clear();

      // Prefer EXIF capture time from IPTC if we don't already have one.
      final dto = _stringFromMeta(raw['DateTimeOriginal']) ??
          _stringFromMeta(raw['CreateDate']);
      final parsed = dto == null ? null : _parseExifDate(dto);
      if (parsed != null) {
        captureByPath[path] = parsed;
      }
      notifyListeners();
      if (mlbTimestampAvailable &&
          mlbTimestampEnabled &&
          sport.toLowerCase() == 'baseball') {
        unawaited(applyMlbTimestamp());
      }
    } catch (_) {
      if (gen != _iptcLoadGen) return;
      currentIptcMeta = {};
      photographerName = '';
      agencyName = '';
      notifyListeners();
    }
  }

  static String _metadataListFromRaw(
    dynamic value, {
    required String separator,
  }) {
    if (value == null) return '';
    final values =
        value is List ? value.map((e) => e.toString()) : [value.toString()];
    return _dedupeMetadataList(values.join(separator), separator: separator);
  }

  // ---------------------------------------------------------------------------
  // Save / burst / transmit
  // ---------------------------------------------------------------------------

  Future<void> _storePreviousCaption({
    required String caption,
    required String personality,
  }) async {
    final payload = CaptionTransferPayload(
      caption: caption,
      personality: personality,
    );
    previousCaption = payload;
    await _prefs?.saveLastSavedMetadata(payload.toJson());
  }

  Future<bool> saveCurrent({bool advance = false}) async {
    final path = currentPath;
    if (path == null) {
      statusMessage = 'No image to save';
      notifyListeners();
      return false;
    }
    final result = await savePaths([path]);
    if (result.anySucceeded && advance) nextFrame();
    return result.anySucceeded;
  }

  Future<CaptionSaveResult> savePaths(List<String> paths) async {
    final targets = <String>[];
    for (final path in paths) {
      if (imagePaths.contains(path) && !targets.contains(path)) {
        targets.add(path);
      }
    }
    if (targets.isEmpty) {
      statusMessage = 'No image to save';
      notifyListeners();
      return const CaptionSaveResult(
        requestedPaths: [],
        succeededPaths: [],
      );
    }

    final captionUnchanged = selectedPlayer == null &&
        !hasVerbSelection &&
        manualCaptionOverride == null;
    if (captionUnchanged && !metadataDirty && originalCaption.trim().isEmpty) {
      statusMessage = 'Select a player and verb first';
      notifyListeners();
      return CaptionSaveResult(
        requestedPaths: targets,
        succeededPaths: const [],
      );
    }

    final generatedCaption = selectedPlayer != null && hasVerbSelection;
    if (generatedCaption && selectedVerb != null) rememberCombo();
    final manualCaption = manualCaptionOverride?.trim().isNotEmpty == true;
    final shouldWriteCaption = !captionUnchanged;
    final shouldWriteValues = shouldWriteCaption || metadataDirty;
    final values =
        shouldWriteValues ? captionValues() : const <String, String>{};
    if (!shouldWriteCaption && shouldWriteValues) {
      for (final key in const [
        'IPTC:Caption-Abstract',
        'Caption-Abstract',
        'IPTC:Description',
        'Description',
        'XMP:Description',
      ]) {
        values[key] = originalCaption;
      }
    }
    final templateSucceeded = <String>[];
    for (final pth in targets) {
      if (await _applyIptcTemplateOnSaveIfEnabled(pth)) {
        templateSucceeded.add(pth);
      }
    }

    final succeeded = shouldWriteValues
        ? await _writer.writeCaptionToPaths(paths: targets, values: values)
        : templateSucceeded;
    if (succeeded.isNotEmpty) {
      savedImages.addAll(succeeded);
      if (generatedCaption || manualCaption) {
        captionedImages.addAll(succeeded);
      }
      await _persistSaved();
      metadataDirty = false;
      await _storePreviousCaption(
        caption: shouldWriteCaption
            ? values['IPTC:Caption-Abstract'] ?? ''
            : originalCaption,
        personality: shouldWriteCaption
            ? values['XMP-getty:Personality'] ?? ''
            : personality,
      );
    }

    final result = CaptionSaveResult(
      requestedPaths: List.unmodifiable(targets),
      succeededPaths: List.unmodifiable(succeeded),
    );
    if (!result.anySucceeded) {
      statusMessage = targets.length == 1
          ? 'Save failed (exiftool?)'
          : 'Save failed for all ${targets.length} frames';
    } else if (!result.allSucceeded) {
      statusMessage = 'Saved ${succeeded.length} of ${targets.length}; '
          '${result.failedPaths.length} failed';
    } else {
      statusMessage =
          targets.length == 1 ? 'Saved' : 'Saved ${targets.length} frames';
    }
    notifyListeners();
    return result;
  }

  Future<bool> applyCaptionToBurst() async {
    final result = await savePaths(forwardBurstChain);
    return result.anySucceeded;
  }

  void advancePastHandledChain(List<String> chain) {
    if (imagePaths.isEmpty || chain.isEmpty) return;
    var lastIndex = -1;
    for (final path in chain) {
      final index = imagePaths.indexOf(path);
      if (index > lastIndex) lastIndex = index;
    }
    if (lastIndex < 0) return;
    goToIndex((lastIndex + 1).clamp(0, imagePaths.length - 1));
  }

  Future<bool> saveAndNext() async {
    final saved = await saveCurrent(advance: true);
    if (saved) {
      _clearCaptionSelection();
      notifyListeners();
    }
    return saved;
  }

  void _clearCaptionSelection() {
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = pinnedVerb;
    if (!customVerbPinned) customVerbPhrase = '';
    celebrationType = null;
    personality = '';
    manualCaptionOverride = null;
    rbi = 0;
    selectedBase = null;
  }

  Future<void> enterComboSaveAdvance() async {
    applyLastUsed();
    await saveAndNext();
  }

  Future<void> transmitQueued() async {
    final toSend =
        imagePaths.where((p) => frameStateFor(p) == FrameState.saved).toList();
    if (toSend.isEmpty) {
      statusMessage = 'Nothing queued';
      notifyListeners();
      return;
    }
    await _transmitPaths(toSend);
  }

  Future<void> transmitCurrent() async {
    final path = currentPath;
    if (path == null) return;
    // Ensure saved first.
    if (frameStateFor(path) == FrameState.todo) {
      final ok = await saveCurrent();
      if (!ok) return;
    }
    await _transmitPaths([path]);
  }

  Future<void> _transmitPaths(List<String> paths) async {
    transmitting = true;
    queuedCount = paths.length;
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) {
      sentImages.addAll(paths);
      savedImages.addAll(paths);
      lastSentLabel = _formatTime(DateTime.now());
      queuedCount = 0;
      transmitting = false;
      statusMessage = 'Marked sent (prefs unavailable)';
      notifyListeners();
      return;
    }

    final profileName = await prefs.getCurrentFtpProfile();
    final profiles = await prefs.getFtpProfiles();
    final profile = profileName == null ? null : profiles[profileName];

    if (profile == null) {
      // Soft success for UI review when FTP isn't configured.
      sentImages.addAll(paths);
      savedImages.addAll(paths);
      lastSentLabel = _formatTime(DateTime.now());
      queuedCount = 0;
      transmitting = false;
      statusMessage = 'Marked sent (no FTP profile)';
      notifyListeners();
      return;
    }

    final host = profile['host']?.toString() ?? '';
    final user = profile['username']?.toString() ?? '';
    final pass = profile['password']?.toString() ?? '';
    final port = int.tryParse(profile['port']?.toString() ?? '') ?? 21;
    final remoteDir = profile['remotePath']?.toString() ?? '/';

    var ok = 0;
    for (final path in paths) {
      final remote = p.join(remoteDir, p.basename(path));
      final result = await FtpClientService.uploadFile(
        host: host,
        username: user,
        password: pass,
        localFilePath: path,
        remoteFilePath: remote,
        port: port,
      );
      if (result.success) {
        ok++;
        sentImages.add(path);
        savedImages.add(path);
      }
    }

    lastSentLabel = _formatTime(DateTime.now());
    queuedCount = savedNotSentCount;
    transmitting = false;
    statusMessage = 'Sent $ok / ${paths.length}';
    notifyListeners();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  // ---------------------------------------------------------------------------
  // Search hits
  // ---------------------------------------------------------------------------

  List<RosterHit> get filteredHome {
    return _filterRoster(homeRoster, isHome: true);
  }

  List<RosterHit> get filteredAway {
    return _filterRoster(awayRoster, isHome: false);
  }

  List<RosterHit> _filterRoster(
    List<Player> roster, {
    required bool isHome,
  }) {
    final rawQuery = searchQuery.trim().toLowerCase();
    if (searchIsTeamPrefixOnly) return const [];
    final command =
        RegExp(r'^([hv])?\s*#?(\d+)(?:\s+.+)?$').firstMatch(rawQuery);
    final side = command?.group(1);
    if ((side == 'h' && !isHome) || (side == 'v' && isHome)) {
      return const [];
    }
    final q = command?.group(2) ?? rawQuery;
    final numericQuery = RegExp(r'^\d+$').hasMatch(q);
    final list = roster.where((pl) {
      if (q.isEmpty) return true;
      if (numericQuery) {
        return (pl.jerseyNumber ?? '').trim() == q;
      }
      return pl.fullName.toLowerCase().contains(q) ||
          (pl.jerseyNumber ?? '').contains(q) ||
          pl.displayName.toLowerCase().contains(q);
    });
    return list.map((pl) => RosterHit(player: pl, isHome: isHome)).toList();
  }

  List<String> get filteredVerbs {
    final rawQuery = searchQuery.trim().toLowerCase();
    if ((searchIsTeamPrefixOnly && !searchAwaitingVerb) || searchIsJerseyOnly) {
      return const [];
    }
    final command = RegExp(r'^(?:[hv]\s*)?#?\d+\s+(.+)$').firstMatch(rawQuery);
    final commandText = command?.group(1)?.trim() ?? rawQuery;
    final q = commandText.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
    final all = _verbCatalog.byKey.values.toList();
    if (q.isEmpty) return verbsInCategory;
    final exact =
        all.where((verb) => _verbExactlyMatchesQuery(verb, q)).toList();
    final matches = exact.isNotEmpty
        ? exact
        : all.where((verb) => _verbMatchesQuery(verb, q));
    return matches.map((verb) => verb.key).toList();
  }

  bool _verbExactlyMatchesQuery(EffectiveVerb verb, String input) {
    final query = _normalizeCommandText(input);
    final compactQuery = query.replaceAll(' ', '');
    return _verbSearchTerms(verb, includeKeywords: query.length >= 3).any(
      (term) => term == query || term.replaceAll(' ', '') == compactQuery,
    );
  }

  bool _verbMatchesQuery(EffectiveVerb verb, String input) {
    final query = _normalizeCommandText(input);
    if (query.isEmpty) return true;
    final compactQuery = query.replaceAll(' ', '');
    for (final term
        in _verbSearchTerms(verb, includeKeywords: query.length >= 3)) {
      if (term.startsWith(query) ||
          term.replaceAll(' ', '').startsWith(compactQuery)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _verbSearchTerms(
    EffectiveVerb verb, {
    required bool includeKeywords,
  }) {
    final terms = <String>{
      _normalizeCommandText(verb.key),
      _normalizeCommandText(verb.label),
    };
    for (final value in [verb.key, verb.label]) {
      final normalized = _normalizeCommandText(value);
      final words = normalized.split(' ').where((word) => word.isNotEmpty);
      if (words.length > 1) terms.add(words.map((word) => word[0]).join());
    }
    if (includeKeywords) {
      terms.addAll(verb.keywords.map(_normalizeCommandText));
    }
    const aliases = <String, List<String>>{
      'Home Run': ['hr', 'homer', 'homerun'],
      'Single': ['1b'],
      'Double': ['2b'],
      'Triple': ['3b'],
      'Walks': ['bb'],
      'Strikeout': ['k'],
      'Hit by Pitch': ['hbp', 'hitbypitch'],
      'Steals': ['sb'],
      'Double Play': ['dp'],
      'Triple Play': ['tp'],
      'Batting Practice': ['bp'],
      'Fielding Practice': ['fp'],
    };
    terms.addAll(aliases[verb.key] ?? const []);
    return terms;
  }

  /// Parses commands such as `27 home run`. Returns true when the input was
  /// handled as either a new command or an answer to a guided prompt.
  bool submitSearchCommand(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return false;

    if (searchGuided) {
      final answer = _normalizeCommandText(input);
      for (final hit in _guidedSearchHits) {
        final candidates = [hit.label, ...hit.aliases];
        if (candidates.any((candidate) {
          final normalized = _normalizeCommandText(candidate);
          return normalized == answer ||
              normalized.startsWith(answer) ||
              answer.startsWith(normalized);
        })) {
          hit.apply();
          return true;
        }
      }
      statusMessage = 'Choose one of the options below';
      notifyListeners();
      return true;
    }

    final timedMatch = RegExp(r'^\s*([hv])?\s*#?(\d+)\s+(.+?)\s+(\d+)\s*$',
            caseSensitive: false)
        .firstMatch(input);
    final match = timedMatch ??
        RegExp(r'^\s*([hv])?\s*#?(\d+)\s+(.+?)\s*$', caseSensitive: false)
            .firstMatch(input);
    if (match == null) return false;
    final side = match.group(1)?.toLowerCase();
    final jersey = match.group(2)!;
    final verbInput = match.group(3)!;
    _pendingCommandInning =
        timedMatch == null ? null : int.tryParse(timedMatch.group(4)!);
    final verb = _matchCommandVerb(verbInput);
    if (verb == null) {
      statusMessage = 'No verb matched “$verbInput”';
      notifyListeners();
      return true;
    }

    final players = <RosterHit>[
      ...homeRoster
          .where((p) => side != 'v' && (p.jerseyNumber ?? '').trim() == jersey)
          .map((p) => RosterHit(player: p, isHome: true)),
      ...awayRoster
          .where((p) => side != 'h' && (p.jerseyNumber ?? '').trim() == jersey)
          .map((p) => RosterHit(player: p, isHome: false)),
    ];
    if (players.isEmpty) {
      statusMessage = 'No player wearing #$jersey';
      notifyListeners();
      return true;
    }

    searchOpen = true;
    if (players.length == 1) {
      _chooseCommandPlayer(players.first, verb);
      return true;
    }

    guidedSearchPrompt = 'Which team for #$jersey?';
    _guidedSearchHits = players.map((row) {
      final team = row.isHome ? homeTeam : awayTeam;
      final side = row.isHome ? 'Home' : 'Away';
      return SearchHit(
        kind: 'team',
        label: '$side · ${row.player.fullName}',
        shortcutLabel: row.isHome ? 'H' : 'V',
        aliases: [
          side,
          team,
          row.isHome ? homeAbbr : awayAbbr,
          row.player.fullName,
        ],
        apply: () => _chooseCommandPlayer(row, verb),
      );
    }).toList();
    notifyListeners();
    return true;
  }

  String? _matchCommandVerb(String input) {
    final normalized = _normalizeCommandText(input);
    const aliases = <String, String>{
      'hr': 'Home Run',
      'homer': 'Home Run',
      'homers': 'Home Run',
      'homerun': 'Home Run',
      'home run': 'Home Run',
      'grand slam': 'Grand Slam',
      'hbp': 'Hit by Pitch',
      'hitbypitch': 'Hit by Pitch',
      '1b': 'Single',
      '2b': 'Double',
      '3b': 'Triple',
      'bb': 'Walks',
      'k': 'Strikeout',
      'sb': 'Steals',
      'dp': 'Double Play',
      'tp': 'Triple Play',
      'bp': 'Batting Practice',
      'fp': 'Fielding Practice',
    };
    final aliased = aliases[normalized];
    if (aliased != null) return aliased;

    final all = verbsByCategory.values.expand((e) => e).toSet();
    for (final verb in all) {
      final definition = verbDefinition(verb);
      final candidates = <String>[
        verb,
        _verbChip(verb),
        definition?.label ?? '',
        definition?.singularPhrase ?? VerbCaptionWording.defaultWording(verb),
        definition?.pluralPhrase ?? '',
        ...?definition?.keywords,
      ];
      if (candidates.any(
        (candidate) => _normalizeCommandText(candidate) == normalized,
      )) {
        return verb;
      }
    }
    final prefixMatches = _verbCatalog.byKey.values
        .where((verb) => _verbMatchesQuery(verb, normalized))
        .map((verb) => verb.key)
        .toSet();
    if (prefixMatches.length == 1) return prefixMatches.single;
    return null;
  }

  static String _normalizeCommandText(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _onCaptionFieldVisibilityChanged() {
    final prefs = _prefs;
    if (prefs == null) return;
    showKeywordsField = prefs.captionFieldKeywordsVisibleSync;
    showPersonalityField = prefs.captionFieldPersonalityVisibleSync;
    if (showKeywordsField) _syncKeywords();
    if (showPersonalityField) _syncPersonality();
    notifyListeners();
  }

  static List<String> _parseMetadataList(String value) => value
      .split(RegExp(r'[,;]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  static String _dedupeMetadataList(
    String value, {
    required String separator,
  }) {
    final seen = <String>{};
    return _parseMetadataList(value)
        .where((item) => seen.add(item.toLowerCase()))
        .join(separator);
  }

  void _syncKeywords() {
    if (!showKeywordsField) return;
    final previous = keywords;
    final retained = _parseMetadataList(keywords).where((item) {
      final key = item.toLowerCase();
      return !_managedKeywordKeys.contains(key) ||
          _baseKeywordKeys.contains(key);
    }).toList();
    final desired = <String>[];
    if (applyVerbKeywords && selectedVerb != null) {
      desired.addAll(verbDefinition(selectedVerb!)?.keywords ??
          defaultKeywordsForVerbLabel(selectedVerb!));
      if (VerbSubOptions.isCelebrationVerb(selectedVerb!) ||
          selectedVerb == 'Celebration') {
        desired.addAll(const [
          'celebrate',
          'celebration',
          'jubilation',
          'jubo',
        ]);
      }
      if (selectedVerb == 'Grand Slam' ||
          (selectedVerb == 'Home Run' && rbi == 4)) {
        desired.add('grand slam');
      }
    }
    if (applyPlayerNamesToKeywords) {
      desired.addAll(selectedPlayers.map(
        (row) => CaptionTextNormalize.stripDiacritics(row.player.fullName),
      ));
    }
    _managedKeywordKeys
      ..clear()
      ..addAll(desired.map((item) => item.trim().toLowerCase()));
    keywords = mergeVerbKeywordFieldText(retained.join(', '), desired);
    if (keywords != previous) metadataDirty = true;
  }

  void _chooseCommandPlayer(RosterHit row, String verb) {
    captionSelectionStarted = true;
    selectedPlayers
      ..clear()
      ..add(row);
    _syncPrimaryPlayer();
    selectedVerb = verb;
    customVerbPhrase = '';
    customVerbPinned = false;
    verbCategory = _categoryForVerb(verb) ?? verbCategory;
    rbi = 0;
    selectedBase = null;

    if (verb == 'Home Run') {
      guidedSearchPrompt = '';
      _guidedSearchHits = [
        SearchHit(
          kind: 'option',
          label: '1R',
          aliases: const ['solo', '1r', 'one run', '1 run', '1'],
          apply: () => _finishCommand(rbiValue: 1),
        ),
        SearchHit(
          kind: 'option',
          label: '2R',
          aliases: const ['two run', '2 run', '2r', '2'],
          apply: () => _finishCommand(rbiValue: 2),
        ),
        SearchHit(
          kind: 'option',
          label: '3R',
          aliases: const ['three run', '3 run', '3r', '3'],
          apply: () => _finishCommand(rbiValue: 3),
        ),
        SearchHit(
          kind: 'option',
          label: 'GS',
          aliases: const ['grand slam', 'four run', '4 run', 'gs', '4'],
          apply: () => _finishCommand(verbOverride: 'Grand Slam'),
        ),
      ];
      notifyListeners();
      return;
    }

    if (_verbNeedsRbi(verb) && verb != 'Grand Slam' && verb != 'Home Run') {
      guidedSearchPrompt = 'How many RBI?';
      _guidedSearchHits = [
        SearchHit(
          kind: 'option',
          label: '0',
          shortcutLabel: '0',
          aliases: const ['none', 'no', '0'],
          apply: () => _finishCommand(rbiValue: 0),
        ),
        for (var count = 1; count <= 3; count++)
          SearchHit(
            kind: 'option',
            label: '$count',
            shortcutLabel: '$count',
            aliases: ['$count'],
            apply: () => _finishCommand(rbiValue: count),
          ),
      ];
      notifyListeners();
      return;
    }

    if (_verbNeedsBase(verb)) {
      guidedSearchPrompt = 'Which base?';
      _guidedSearchHits = [
        SearchHit(
          kind: 'option',
          label: '1B',
          aliases: const ['1b', 'first', '1st', 'first base', '1'],
          apply: () => _finishCommand(baseValue: '1B'),
        ),
        SearchHit(
          kind: 'option',
          label: '2B',
          aliases: const ['2b', 'second', '2nd', 'second base', '2'],
          apply: () => _finishCommand(baseValue: '2B'),
        ),
        SearchHit(
          kind: 'option',
          label: '3B',
          aliases: const ['3b', 'third', '3rd', 'third base', '3'],
          apply: () => _finishCommand(baseValue: '3B'),
        ),
        SearchHit(
          kind: 'option',
          label: 'Home',
          aliases: const ['home', 'home plate', 'plate', '4'],
          apply: () => _finishCommand(baseValue: 'Home'),
        ),
      ];
      notifyListeners();
      return;
    }

    _finishCommand();
  }

  void _finishCommand({int? rbiValue, String? baseValue, String? verbOverride}) {
    if (verbOverride != null) {
      selectedVerb = verbOverride;
      customVerbPhrase = '';
      customVerbPinned = false;
      verbCategory = _categoryForVerb(verbOverride) ?? verbCategory;
    }
    if (rbiValue != null) rbi = rbiValue;
    if (baseValue != null) selectedBase = baseValue;
    _syncKeywords();
    final commandInning = _pendingCommandInning;
    if (commandInning != null) {
      _pendingCommandInning = null;
      _completeCommandTiming(inningValue: commandInning);
      return;
    }
    _promptForCommandInning();
  }

  void _promptForCommandInning() {
    guidedSearchPrompt = 'What inning?';
    final isBaseball = sport.toLowerCase() == 'baseball';
    final regulationEnd = timingRegulationCount;
    _guidedSearchHits = [
      SearchHit(
        kind: 'option',
        label: 'Pre',
        aliases: const ['pre', 'pregame', 'before'],
        apply: () => _completeCommandTiming(pre: true),
      ),
      for (var value = 1; value <= (isBaseball ? timingMaxInning : regulationEnd);
          value++)
        SearchHit(
          kind: 'option',
          label: _ordinal(value),
          aliases: [
            '$value',
            _ordinal(value),
            _ordinalWord(value),
            if (isBaseball && value == regulationEnd + 1) ...[
              'extra',
              'extras',
              'extra innings',
            ],
          ],
          apply: () => _completeCommandTiming(inningValue: value),
        ),
      if (!isBaseball)
        SearchHit(
          kind: 'option',
          label: 'Extras',
          aliases: const ['extra', 'extras', 'extra innings'],
          apply: () =>
              _completeCommandTiming(inningValue: timingRegulationCount + 1),
        ),
      SearchHit(
        kind: 'option',
        label: 'Post',
        aliases: const ['post', 'postgame', 'after'],
        apply: () => _completeCommandTiming(post: true),
      ),
    ];
    notifyListeners();
  }

  void previewCommandInning(int value) {
    if (value < 1) return;
    inning = value;
    preGame = false;
    postGame = false;
    notifyListeners();
  }

  void completeCommandInning(int value) {
    if (value < 1) return;
    _completeCommandTiming(inningValue: value);
  }

  void _completeCommandTiming({
    int? inningValue,
    bool pre = false,
    bool post = false,
  }) {
    if (inningValue != null) inning = inningValue;
    preGame = pre;
    postGame = post;
    statusMessage = selectedPlayer == null || selectedVerb == null
        ? null
        : '$playerChipLabel · ${_verbChip(selectedVerb!)}';
    _promptForCommandDestination();
  }

  void _promptForCommandDestination() {
    guidedSearchPrompt = 'Save or FTP?';
    _guidedSearchHits = [
      SearchHit(
        kind: 'action',
        label: 'Save',
        aliases: const ['save'],
        apply: () => unawaited(_finishCommandAction(transmit: false)),
      ),
      SearchHit(
        kind: 'action',
        label: 'FTP',
        aliases: const ['ftp', 'send', 'transmit'],
        apply: () => unawaited(_finishCommandAction(transmit: true)),
      ),
    ];
    notifyListeners();
  }

  Future<void> _finishCommandAction({required bool transmit}) async {
    final path = currentPath;
    guidedSearchPrompt = null;
    _guidedSearchHits = const [];
    searchQuery = '';
    notifyListeners();
    if (path == null) return;

    final saved = await saveCurrent();
    if (!saved) return;
    if (transmit) await transmitPath(path);
    if (currentPath == path) nextFrame();
  }

  List<SearchHit> topSearchHits() {
    if (searchGuided) return _guidedSearchHits;
    final hits = <SearchHit>[];
    if (!searchAwaitingVerb) {
      for (final row in [...filteredHome, ...filteredAway]) {
        if (hits.length >= 9) break;
        final pl = row.player;
        final jersey = pl.jerseyNumber ?? '';
        final label = jersey.isEmpty ? pl.fullName : '$jersey ${pl.fullName}';
        hits.add(SearchHit(
          kind: 'player',
          label: label,
          shortcutLabel: row.isHome ? 'H' : 'V',
          apply: () => selectPlayer(pl, isHome: row.isHome),
        ));
      }
    }
    for (final verb in filteredVerbs) {
      if (hits.length >= 9) break;
      hits.add(SearchHit(
        kind: 'verb',
        label: verbDefinition(verb)?.label ?? verb,
        apply: () {
          final player = selectedPlayers.isEmpty ? null : selectedPlayers.first;
          if ((searchHasJerseyAndVerb || searchAwaitingVerb) &&
              player != null) {
            _pendingCommandInning = int.tryParse(
              RegExp(r'\s+(\d+)\s*$').firstMatch(searchQuery)?.group(1) ?? '',
            );
            _chooseCommandPlayer(player, verb);
          } else {
            selectVerb(verb);
          }
        },
      ));
    }
    return hits;
  }

  void applySearchHitByNumber(int n) {
    final hits = topSearchHits();
    if (n < 1 || n > hits.length) return;
    hits[n - 1].apply();
    if (!searchGuided) setSearchOpen(false);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<Player> _sortPlayers(List<Player> list) {
    final copy = List<Player>.from(list);
    copy.sort(_comparePlayers);
    return copy;
  }

  int _comparePlayers(Player a, Player b) {
    late final int cmp;
    switch (rosterSort) {
      case RosterSortMode.number:
        final na = int.tryParse(a.jerseyNumber ?? '') ?? 9999;
        final nb = int.tryParse(b.jerseyNumber ?? '') ?? 9999;
        final byNumber = na.compareTo(nb);
        cmp = byNumber != 0 ? byNumber : a.fullName.compareTo(b.fullName);
        break;
      case RosterSortMode.firstName:
        final byFirst = a.firstName
            .toLowerCase()
            .compareTo(b.firstName.toLowerCase());
        cmp = byFirst != 0
            ? byFirst
            : playerLastName(a)
                .toLowerCase()
                .compareTo(playerLastName(b).toLowerCase());
        break;
      case RosterSortMode.lastName:
        final byLast = playerLastName(a)
            .toLowerCase()
            .compareTo(playerLastName(b).toLowerCase());
        cmp = byLast != 0
            ? byLast
            : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        break;
    }
    return rosterSortAscending ? cmp : -cmp;
  }

  String _shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return full;
    // Drop given name → "Guerrero Jr."
    return parts.sublist(1).join(' ');
  }

  static List<Player> _demoRoster(String team) {
    if (team.contains('Toronto')) {
      return [
        Player(
            fullName: 'George Springer',
            firstName: 'George',
            jerseyNumber: '4',
            displayName: 'George Springer #4'),
        Player(
            fullName: 'Bo Bichette',
            firstName: 'Bo',
            jerseyNumber: '11',
            displayName: 'Bo Bichette #11'),
        Player(
            fullName: 'Vladimir Guerrero Jr.',
            firstName: 'Vladimir',
            jerseyNumber: '27',
            displayName: 'Vladimir Guerrero Jr. #27'),
        Player(
            fullName: 'Alejandro Kirk',
            firstName: 'Alejandro',
            jerseyNumber: '30',
            displayName: 'Alejandro Kirk #30'),
        Player(
            fullName: 'Daulton Varsho',
            firstName: 'Daulton',
            jerseyNumber: '25',
            displayName: 'Daulton Varsho #25'),
      ];
    }
    return [
      Player(
          fullName: 'Gunnar Henderson',
          firstName: 'Gunnar',
          jerseyNumber: '2',
          displayName: 'Gunnar Henderson #2'),
      Player(
          fullName: 'Adley Rutschman',
          firstName: 'Adley',
          jerseyNumber: '35',
          displayName: 'Adley Rutschman #35'),
      Player(
          fullName: 'Anthony Santander',
          firstName: 'Anthony',
          jerseyNumber: '25',
          displayName: 'Anthony Santander #25'),
      Player(
          fullName: 'Jordan Westburg',
          firstName: 'Jordan',
          jerseyNumber: '11',
          displayName: 'Jordan Westburg #11'),
      Player(
          fullName: 'Colton Cowser',
          firstName: 'Colton',
          jerseyNumber: '17',
          displayName: 'Colton Cowser #17'),
    ];
  }

  @override
  void dispose() {
    _prefs?.captionFieldVisibilityRevision.removeListener(
      _onCaptionFieldVisibilityChanged,
    );
    super.dispose();
  }
}
