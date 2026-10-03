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
import '../../../caption_style/verb_authoring_model.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_sort_mode.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/api_manager.dart';
import '../../../services/ftpclient_service.dart';
import '../../../services/flo_caption_mark.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/mlb_inning_feature_gate.dart';
import '../../../services/mlb_inning_from_timestamp_service.dart';
import '../../../services/preferences_service.dart';
import '../../../services/admin_service.dart';
import '../../../config/tank01_config.dart';
import '../../../utils/exiftool_helper.dart';
import '../../../utils/default_verb_keywords.dart';
import '../../../utils/image_file_ready.dart';
import '../../../utils/native_file_picker.dart';
import '../widgets/frame_status_dot.dart';
import 'burst_groups.dart';
import 'caption_transfer_payload.dart';
import 'caption_v2_caption_domain.dart';
import 'effective_verb_catalog.dart';
import 'ftp_history.dart';
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

enum FirebarOptionKind { homeRun, rbi, celebration, base, destination }

enum RosterSortMode { number, firstName, lastName }

class FirebarOption {
  const FirebarOption(
    this.label, {
    this.rbi,
    this.verbOverride,
    this.celebration,
    this.base,
    this.transmit,
  });

  final String label;
  final int? rbi;
  final String? verbOverride;
  final String? celebration;
  final String? base;

  /// Destination actions only: `false` = Save, `true` = FTP.
  final bool? transmit;
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

class _FirebarJerseyToken {
  const _FirebarJerseyToken({this.side, required this.jersey});

  final String? side;
  final String jersey;
}

class _FirebarJerseyVerbCompound {
  const _FirebarJerseyVerbCompound({
    required this.jerseys,
    required this.verbQuery,
  });

  /// One or more jersey tokens (`88`, `h4 v3`, …) before the verb text.
  final List<_FirebarJerseyToken> jerseys;
  final String verbQuery;
}

class _CaptionJerseyExpansion {
  const _CaptionJerseyExpansion({
    required this.text,
    required this.players,
    required this.clearManual,
  });

  final String text;
  final List<RosterHit> players;
  final bool clearManual;
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
  VerbSortMode verbSortMode = VerbSortMode.alphabetical;
  Map<String, int> _verbUsageCounts = {};

  // --- Game / teams ---
  String homeTeam = '';
  String awayTeam = '';

  /// Session has one roster only ([homeTeam]); captions omit opponent clauses.
  bool singleTeamMode = false;

  bool get hasOpponentTeam => !singleTeamMode && awayTeam.trim().isNotEmpty;

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
  final Map<String, String?> verbModifierSelections = {};
  String customVerbPhrase = '';
  String lastCustomVerbPhrase = '';
  bool customVerbPinned = false;
  bool captionSelectionStarted = false;
  String? celebrationType;
  String? pinnedVerb;
  RosterHit? pinnedPlayer;
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

  /// Basketball/WNBA half selection (`1H` / `2H`); null = use quarter/OT via [inning].
  String? timingHalf;

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
  bool refreshingFolder = false;
  bool _folderScanInFlight = false;
  bool _folderScanAgain = false;
  StreamSubscription<FileSystemEvent>? _folderWatch;
  Timer? _folderIngestTimer;
  Timer? _folderPollTimer;
  int _folderWatchGeneration = 0;
  String? _watchedFolder;
  final Set<String> _pendingIngest = {};
  final Map<String, int> _imageContentStamp = {};
  final Map<String, int> _fileLength = {};
  final Map<String, int> _fileModifiedMs = {};
  final Map<String, int> _fileChangedMs = {};

  static const _sessionImageExtensions = {
    '.jpg',
    '.jpeg',
    '.tif',
    '.tiff',
    '.png',
  };

  /// When false, FTP buttons/shortcuts/menu items are hidden.
  bool ftpModeEnabled = true;

  // --- Search / focus ---
  String searchQuery = '';
  bool searchOpen = false;
  String? guidedSearchPrompt;
  List<SearchHit> _guidedSearchHits = const [];
  int? _pendingCommandInning;
  int columnFocus = 1; // 0 home, 1 verbs, 2 away, 3 thumbnails
  RosterSortMode rosterSort = RosterSortMode.number;
  bool rosterSortAscending = true;

  /// Bumped when advancing frames so roster/drum player search fields clear.
  int playerSearchClearGeneration = 0;
  int firebarSelectionIndex = -1;
  final List<FirebarResult> _firebarCommitted = [];

  /// Player keys auto-applied while Firebar search narrows to roster match(es).
  final Set<String> _firebarAutoPreviewKeys = {};

  /// Verb key auto-applied while Firebar search narrows to a single verb match.
  /// Does not clear [pinnedVerb] — preview is a one-frame override.
  String? _firebarVerbPreviewKey;
  String? _firebarVerbPreviewPriorSelected;
  String? firebarOptionPrompt;
  FirebarOptionKind? _firebarOptionKind;
  List<FirebarOption> firebarOptions = const [];
  int firebarOptionIndex = 0;

  /// Screen asks before re-uploading paths already in [sentImages].
  /// Return true to upload those paths again.
  Future<bool> Function(List<String> alreadySent)? confirmRetransmit;

  /// Screen-provided save path so verb-menu / Firebar Save/FTP can show burst alerts.
  Future<void> Function({required bool transmit})? onSaveTransmit;

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
    final compound = _parseFirebarJerseyVerbCompound(query);
    final verbQuery = compound?.verbQuery ?? query;
    if (compound == null) {
      if (RegExp(r'^(?:[hv])?\d+$').hasMatch(query)) return const [];
      if (_parseFirebarJerseyTokens(query) != null) return const [];
    }
    final seen = <String>{};
    final results = <FirebarResult>[];
    for (final category in verbCategories) {
      for (final verb
          in verbDefinitionsByCategory[category] ?? const <EffectiveVerb>[]) {
        if (!seen.add(verb.key)) continue;
        if (verbQuery.isEmpty || _firebarVerbMatches(verb, verbQuery)) {
          results.add(FirebarResult.verb(verb.key));
        }
      }
    }
    return results;
  }

  List<FirebarResult> get firebarOrderedResults {
    final home = firebarHomeResults;
    final away = firebarAwayResults;
    final custom = firebarCustomVerbOffer;
    final extras =
        custom == null ? const <FirebarResult>[] : [FirebarResult.verb(custom)];
    return selectedIsHome
        ? [...home, ...firebarVerbResults, ...away, ...extras]
        : [...away, ...firebarVerbResults, ...home, ...extras];
  }

  /// Typed wording that isn't a catalog verb, offered as its own Firebar chip.
  String? get firebarCustomVerbOffer {
    if (!searchOpen || firebarOptions.isNotEmpty) return null;
    final raw = searchQuery.trim();
    if (raw.isEmpty) return null;
    final normalized = _normalizedFirebarQuery;
    if (RegExp(r'^(?:[hv])?\d+$').hasMatch(normalized)) return null;
    if (_parseFirebarJerseyVerbCompound(normalized) == null &&
        _parseFirebarJerseyTokens(normalized) != null) {
      return null;
    }
    final verbQuery = firebarVerbHighlightQuery;
    if (verbQuery.length < 2) return null;
    if (_catalogVerbExactlyMatches(verbQuery)) return null;
    if (_queryMatchesPlayerName(verbQuery)) return null;
    final catalogHits = firebarVerbResults.isNotEmpty;
    final playerHits =
        firebarHomeResults.isNotEmpty || firebarAwayResults.isNotEmpty;
    final hasSpace = verbQuery.contains(' ');
    if (catalogHits && !hasSpace) return null;
    if (!catalogHits && !hasSpace && playerHits) return null;
    final tail = _typedVerbTail(raw);
    return tail.length < 2 ? null : tail;
  }

  bool _catalogVerbExactlyMatches(String query) {
    for (final result in firebarVerbResults) {
      final verb = verbDefinition(result.verbKey ?? '');
      if (verb == null) continue;
      if (_normalizeFirebarText(verb.label) == query ||
          _normalizeFirebarText(verb.key) == query ||
          _normalizeFirebarText(verb.singularPhrase) == query) {
        return true;
      }
    }
    return false;
  }

  bool _queryMatchesPlayerName(String query) {
    bool matches(List<Player> roster) {
      for (final player in roster) {
        if (_normalizeFirebarText(player.fullName) == query) return true;
      }
      return false;
    }

    return matches(homeRoster) || matches(awayRoster);
  }

  static String _typedVerbTail(String raw) {
    final match = RegExp(
      r'^(?:(?:[hv])?\s*#?\d+\s+)+(.+)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    return (match?.group(1) ?? raw).trim();
  }

  FirebarResult? get firebarSelectedResult {
    final results = firebarOrderedResults;
    if (firebarSelectionIndex < 0 || firebarSelectionIndex >= results.length) {
      return null;
    }
    return results[firebarSelectionIndex];
  }

  /// True when Firebar has a highlighted player match (name or jersey), so
  /// Shift+Enter can commit that match and save without pressing Enter first.
  bool get firebarCanQuickSavePlayer {
    if (!searchOpen || firebarOptions.isNotEmpty) return false;
    if (searchQuery.trim().isEmpty) return false;
    return firebarSelectedResult?.kind == FirebarResultKind.player;
  }

  /// True when Firebar has a highlighted verb — commit as a one-frame override
  /// of any pinned verb, then save (or wait for RBI/base chips).
  bool get firebarCanQuickSaveVerb {
    if (!searchOpen || firebarOptions.isNotEmpty) return false;
    if (searchQuery.trim().isEmpty) return false;
    return firebarSelectedResult?.kind == FirebarResultKind.verb;
  }

  bool get firebarShowingDestinationOptions =>
      searchOpen && _firebarOptionKind == FirebarOptionKind.destination;

  /// Show the Shift+Enter save hint in the Firebar chrome.
  bool get firebarShowShiftEnterSaveHint =>
      firebarCanQuickSavePlayer ||
      firebarCanQuickSaveVerb ||
      firebarShowingDestinationOptions;

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

  /// Caption text Firebar just put into the sentence. Orange in the caption
  /// while Firebar is open; date, venue, and byline stay the normal color.
  List<String> get firebarInsertedHighlights {
    if (!searchOpen) return const [];
    final caption = displayedCaption;
    if (caption.trim().isEmpty) return const [];
    final body = buildCaptionBody().trim();
    if (body.isNotEmpty && caption.contains(body)) return [body];
    final found = <String>[];
    void add(String phrase) {
      final text = phrase.trim();
      if (text.isEmpty || found.contains(text)) return;
      if (caption.contains(text)) found.add(text);
    }

    for (final row in selectedPlayers) {
      add(row.player.fullName);
    }
    add(customVerbPhrase);
    final verb = selectedVerb;
    if (verb != null) {
      add(verbDefinition(verb)?.singularPhrase ?? '');
      add(verbDefinition(verb)?.label ?? verb);
    }
    return found;
  }

  String get _normalizedFirebarQuery =>
      firebarOptions.isNotEmpty ? '' : _normalizeFirebarText(searchQuery);

  static String _normalizeFirebarText(String value) =>
      CaptionTextNormalize.stripDiacritics(value).trim().toLowerCase();

  static bool _firebarVerbMatches(EffectiveVerb verb, String query) {
    if (_firebarTextMatches(verb.label, query, allowInitials: true)) {
      return true;
    }
    if (_firebarTextMatches(verb.singularPhrase, query)) return true;
    if (_firebarTextMatches(verb.pluralPhrase, query)) return true;
    if (_firebarTextMatches(verb.ingPhrase, query)) return true;
    for (final keyword in verb.keywords) {
      if (_firebarTextMatches(keyword, query, allowInitials: true)) {
        return true;
      }
    }
    final phraseText = verb.authoring.phrase.parts
        .whereType<VerbPhraseText>()
        .map((part) => part.text)
        .join();
    if (_firebarTextMatches(phraseText, query)) return true;
    for (final group in verb.authoring.groups) {
      if (_firebarTextMatches(group.name, query)) return true;
      for (final option in group.options) {
        if (_firebarTextMatches(option.label, query) ||
            _firebarTextMatches(option.value, query)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _firebarTextMatches(
    String value,
    String query, {
    bool allowInitials = false,
  }) {
    final normalized = _normalizeFirebarText(value);
    if (normalized.isEmpty) return false;
    if (normalized == query || normalized.startsWith(query)) return true;
    final words = normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.any((word) => word == query || word.startsWith(query))) {
      return true;
    }
    // Multi-word fragments like "hits a" should match inside a longer phrase.
    if (query.contains(' ') && normalized.contains(query)) return true;
    if (!allowInitials) return false;
    final initials = words.map((word) => word[0]).join();
    return initials.startsWith(query);
  }

  static final RegExp _firebarJerseyTokenPattern = RegExp(r'^([hv])?(\d+)$');

  /// Parses `88 looks`, `88 92 look`, or `h4 v3 home run` into jerseys + verb.
  _FirebarJerseyVerbCompound? _parseFirebarJerseyVerbCompound(String query) {
    final parts = query.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final jerseys = <_FirebarJerseyToken>[];
    var index = 0;
    for (; index < parts.length; index++) {
      final match = _firebarJerseyTokenPattern.firstMatch(parts[index]);
      if (match == null) break;
      jerseys.add(
        _FirebarJerseyToken(
          side: match.group(1)?.toLowerCase(),
          jersey: match.group(2)!,
        ),
      );
    }
    if (jerseys.isEmpty || index >= parts.length) return null;

    final verbQuery = _normalizeFirebarText(parts.sublist(index).join(' '));
    if (verbQuery.isEmpty) return null;
    return _FirebarJerseyVerbCompound(
      jerseys: jerseys,
      verbQuery: verbQuery,
    );
  }

  /// Verb-only fragment of the Firebar query (e.g. `look` from `88 92 look`).
  String get firebarVerbHighlightQuery {
    final compound = _parseFirebarJerseyVerbCompound(_normalizedFirebarQuery);
    return compound?.verbQuery ?? _normalizedFirebarQuery;
  }

  /// Parses space-separated jersey tokens like `11 27` or `h4 v3`.
  List<_FirebarJerseyToken>? _parseFirebarJerseyTokens(String query) {
    final parts = query.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final tokens = <_FirebarJerseyToken>[];
    for (final part in parts) {
      final match = _firebarJerseyTokenPattern.firstMatch(part);
      if (match == null) return null;
      tokens.add(
        _FirebarJerseyToken(
          side: match.group(1)?.toLowerCase(),
          jersey: match.group(2)!,
        ),
      );
    }
    return tokens;
  }

  List<_FirebarJerseyToken>? _firebarJerseyTokensForQuery(String query) {
    return _parseFirebarJerseyVerbCompound(query)?.jerseys ??
        _parseFirebarJerseyTokens(query);
  }

  List<FirebarResult> _firebarRosterResults(
    List<Player> roster, {
    required bool isHome,
  }) {
    final query = _normalizedFirebarQuery;
    final jerseyTokens = _firebarJerseyTokensForQuery(query);
    if (jerseyTokens != null) {
      final wantedJerseys = <String>{};
      for (final token in jerseyTokens) {
        if ((token.side == 'h' && !isHome) || (token.side == 'v' && isHome)) {
          continue;
        }
        wantedJerseys.add(token.jersey);
      }
      if (wantedJerseys.isEmpty) return const [];
      final matches = roster
          .where(
            (player) => wantedJerseys.contains(
              (player.jerseyNumber ?? '').trim(),
            ),
          )
          .toList()
        ..sort(_comparePlayers);
      return [
        for (final player in matches)
          FirebarResult.player(
            player: player,
            isHome: isHome,
          ),
      ];
    }
    final jerseyMatch = _firebarJerseyTokenPattern.firstMatch(query);
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
        final score =
            _playerMatchScore(a, query).compareTo(_playerMatchScore(b, query));
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
      final score = _playerMatchScore(a, q).compareTo(_playerMatchScore(b, q));
      if (score != 0) return score;
      return _comparePlayers(a, b);
    });
    return matches;
  }

  // --- Transmit ---
  String destinationLabel = 'Photoshelter · FTP';
  String? ftpProfileName;

  String get ftpButtonLabel {
    final name = ftpProfileName?.trim();
    if (name == null || name.isEmpty) return 'FTP';
    return 'FTP · $name';
  }
  int queuedCount = 0;
  String? lastSentLabel;
  bool transmitting = false;
  final List<FtpHistoryEntry> ftpHistory = [];

  /// 0.0–1.0 while [transmitting]; cleared when idle.
  double transmitProgress = 0;

  /// Human-readable phase, e.g. "Uploading…".
  String? transmitStatus;

  /// Path currently uploading (for preview/thumbnail overlays).
  String? transmittingPath;
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

  /// True when the loaded folder contains at least one multi-frame burst.
  bool get hasDetectedBursts => bursts.any((group) => group.length > 1);

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

  /// Returns the multi-frame burst that overlaps [paths] with 2+ frames, if any.
  List<String>? burstGroupOverlapping(Iterable<String> paths) {
    final selected = paths.toSet();
    if (selected.length < 2) return null;
    for (final group in bursts) {
      if (group.length < 2) continue;
      var overlap = 0;
      for (final path in group) {
        if (selected.contains(path)) overlap++;
        if (overlap >= 2) return group;
      }
    }
    return null;
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
        for (final entry in verbDefinitionsByCategory.entries)
          entry.key: entry.value.map((verb) => verb.key).toList(),
      };
  Map<String, List<EffectiveVerb>> get verbDefinitionsByCategory {
    final sorted = <String, List<EffectiveVerb>>{};
    for (final entry in _verbCatalog.verbsByCategory.entries) {
      sorted[entry.key] = _sortedVerbs(entry.value);
    }
    return sorted;
  }

  List<EffectiveVerb> _sortedVerbs(List<EffectiveVerb> verbs) {
    if (verbs.length <= 1) return List<EffectiveVerb>.from(verbs);
    switch (verbSortMode) {
      case VerbSortMode.custom:
        return List<EffectiveVerb>.from(verbs);
      case VerbSortMode.mostUsed:
        final ranked = List<EffectiveVerb>.from(verbs);
        ranked.sort((a, b) {
          final byCount =
              (_verbUsageCounts[b.key] ?? 0).compareTo(_verbUsageCounts[a.key] ?? 0);
          if (byCount != 0) return byCount;
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
        return ranked;
      case VerbSortMode.alphabetical:
        final ranked = List<EffectiveVerb>.from(verbs);
        ranked.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
        return ranked;
    }
  }

  EffectiveVerb? verbDefinition(String key) => _verbCatalog.byKey[key];
  bool isVerbFavorite(String key) => _verbCatalog.favoriteKeys.contains(key);
  bool isVerbPinned(String key) => pinnedVerb == key;
  int verbUsageCount(String key) => _verbUsageCounts[key] ?? 0;

  bool isPlayerPinned(Player player, {required bool isHome}) {
    final pinned = pinnedPlayer;
    if (pinned == null || pinned.isHome != isHome) return false;
    return _samePlayer(pinned.player, player);
  }

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

  /// Pinned verb is armed for the next frame, but don't compose a caption
  /// until a player is chosen. Manual (unpinned) verb picks still preview.
  bool get pinDefersCaptionUntilPlayer {
    if (selectedPlayer != null) return false;
    if (pinnedVerb != null && selectedVerb == pinnedVerb) return true;
    if (customVerbPinned &&
        selectedVerb == null &&
        customVerbPhrase.trim().isNotEmpty) {
      return true;
    }
    return false;
  }

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

  /// Strip title (basketball offers halves + quarters).
  String get timingUnitTitle {
    switch (sport.toLowerCase()) {
      case 'basketball':
      case 'wnba':
        return 'Half/Quarter';
      case 'hockey':
        return 'Period';
      case 'soccer':
        return 'Half';
      case 'baseball':
      default:
        return 'Inning';
    }
  }

  bool get supportsTimingHalves {
    final s = sport.toLowerCase();
    return s == 'basketball' || s == 'wnba';
  }

  /// Chip / stepper label (e.g. "2nd", "OT", "ET", "10th", "1H").
  String get inningLabel {
    if (timingHalf == '1H' || timingHalf == '2H') return timingHalf!;
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

  static final RegExp _inTheirGameId =
      RegExp(r'^in their\b', caseSensitive: false);

  /// When Pre/Post is on and the style uses an "in their … game/match"
  /// identifier, fold timing into that phrase ("ahead of their WNBA game")
  /// instead of stacking "before the game in their WNBA game".
  bool get _canFoldPrePostIntoGameIdentifier {
    if (!preGame && !postGame) return false;
    return _inTheirGameId.hasMatch(captionTemplate.gameIdentifierText.trim());
  }

  String? get _foldedGameIdentifierText {
    if (!_canFoldPrePostIntoGameIdentifier) return null;
    final id = captionTemplate.gameIdentifierText.trim();
    if (preGame) {
      return id.replaceFirst(_inTheirGameId, 'ahead of their');
    }
    if (postGame) {
      return id.replaceFirst(_inTheirGameId, 'following their');
    }
    return null;
  }

  /// Caption clause for the current timing selection (matches classic wording).
  String get timingCaptionClause {
    String phrase;
    if (preGame) {
      phrase = _canFoldPrePostIntoGameIdentifier ? '' : 'before the game';
    } else if (postGame) {
      phrase = _canFoldPrePostIntoGameIdentifier ? '' : 'following the game';
    } else if (timingHalf == '1H') {
      phrase = 'during the first half';
    } else if (timingHalf == '2H') {
      phrase = 'during the second half';
    } else {
      final max = timingRegulationCount;
      final s = sport.toLowerCase();
      if (inning > max && s != 'baseball') {
        switch (s) {
          case 'soccer':
            phrase = 'during extra time';
            break;
          default:
            phrase = 'during overtime';
            break;
        }
      } else {
        switch (s) {
          case 'hockey':
            phrase = 'during the ${_ordinalWord(inning)} period';
            break;
          case 'basketball':
          case 'wnba':
            phrase = 'during the ${_ordinalWord(inning)} quarter';
            break;
          case 'soccer':
            phrase = inning == 1
                ? 'during the first half'
                : 'during the second half';
            break;
          case 'baseball':
          default:
            phrase = 'during the ${_ordinalWord(inning)} inning';
            break;
        }
      }
    }
    if (phrase.isEmpty) return phrase;
    if (!captionTemplate.includeTimingPhrase) return '';
    return captionTemplate.timingPhraseCaps ? phrase.toUpperCase() : phrase;
  }

  /// Chip-mode leading text (used when the full style caption isn't ready yet).
  String get captionLeading {
    final team = selectedPlayers.isEmpty
        ? (selectedIsHome ? homeTeam : awayTeam)
        : (selectedPlayers.first.isHome ? homeTeam : awayTeam);
    return '$team ';
  }

  String get captionTrailing {
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
    if (!hasOpponentTeam) {
      return ' $timingCaptionClause$venueBit.'.replaceAll(RegExp(r'\s+'), ' ');
    }
    final subjectIsHome =
        selectedPlayers.isEmpty ? selectedIsHome : selectedPlayers.first.isHome;
    final opp = subjectIsHome ? awayTeam : homeTeam;
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

    final foldedGid = _foldedGameIdentifierText;
    final templateForRender = foldedGid == null
        ? captionTemplate
        : captionTemplate.copyWith(gameIdentifierText: foldedGid);

    var caption = CaptionFormulaRenderer.render(
      template: templateForRender,
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
    if (!hasOpponentTeam) {
      if (preGame) {
        return _canFoldPrePostIntoGameIdentifier ? '' : 'ahead of the game';
      }
      if (postGame) {
        return _canFoldPrePostIntoGameIdentifier ? '' : 'following the game';
      }
      return timingCaptionClause;
    }
    final subjects = subjectPlayers;
    final subjectIsHome =
        subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final target = opposingPlayers.isEmpty
        ? 'the ${opponentTeam.trim()}'
        : _formatPlayersWithTeam(opposingPlayers, captionTemplate);

    if (preGame) return 'ahead of playing against $target';
    if (postGame) return 'following the game against $target';
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
    // Celebrates a Goal: first pick is the scorer; teammates follow as "with…".
    final leadRows =
        _verbUsesScoringLeadWithTeammates(selectedVerb) ? [rows.first] : rows;
    var teamName = leadRows.first.isHome ? homeTeam : awayTeam;
    final playerLabels = leadRows.map((row) {
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

  /// Verbs where the first same-team pick is the action subject and later
  /// same-team picks are named in a trailing "with …" clause.
  static bool _verbUsesScoringLeadWithTeammates(String? verb) =>
      verb == 'Celebrates a Goal';

  String _actionPhrase() {
    final verb = selectedVerb!;
    final definition = verbDefinition(verb);
    final subjects = subjectPlayers;
    final subjectIsHome =
        subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final scoringLead = _verbUsesScoringLeadWithTeammates(verb);
    final plural = scoringLead ? false : subjects.length > 1;
    // Live captioning uses classic RBI / celebration controls. Authored
    // modifier phrases are edited in Admin → Verb authoring only for now.
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

    if (scoringLead && subjects.length > 1) {
      final teammates = subjects.skip(1).toList(growable: false);
      final names = _formatPlayerNamesOnly(teammates, captionTemplate);
      if (names.isNotEmpty) {
        action = '$action with $names';
      }
    }

    final includeOpponent = definition?.wantsOpponent ?? true;
    if (includeOpponent &&
        hasOpponentTeam &&
        !action.toLowerCase().contains(opponentTeam.trim().toLowerCase())) {
      action = CaptionV2CaptionDomain.withOpponent(
        verb: verb,
        action: action,
        opponentTeam: opponentTeam,
        opposingPlayers: opposingPlayers.isEmpty
            ? null
            : _formatPlayersWithTeam(opposingPlayers, captionTemplate),
        omitAgainst: definition?.omitAgainst ?? false,
        opponentJoiner: definition?.opponentJoiner ?? 'against',
      );
    }

    if (verb == 'Post Game Win' || verb == 'Post Game Loss') {
      return _canFoldPrePostIntoGameIdentifier
          ? action
          : '$action following the game';
    }
    if (preGame) {
      return _canFoldPrePostIntoGameIdentifier
          ? action
          : '$action before the game';
    }
    return '$action $timingCaptionClause'.trim();
  }

  String _customActionPhrase() {
    var action = customVerbPhrase.trim();
    if (hasOpponentTeam) {
      final subjects = subjectPlayers;
      final subjectIsHome =
          subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
      final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
      final lower = action.toLowerCase();
      if (!lower.contains(opponentTeam.trim().toLowerCase())) {
        final alreadyJoined =
            lower.contains(' against ') || lower.contains(' playing ');
        action = alreadyJoined
            ? '$action the ${opponentTeam.trim()}'
            : CaptionV2CaptionDomain.withOpponent(
                verb: action,
                action: action,
                opponentTeam: opponentTeam,
                opposingPlayers: opposingPlayers.isEmpty
                    ? null
                    : _formatPlayersWithTeam(opposingPlayers, captionTemplate),
              );
      }
    }
    if (preGame) {
      return _canFoldPrePostIntoGameIdentifier
          ? action
          : '$action before the game';
    }
    if (postGame) {
      return _canFoldPrePostIntoGameIdentifier
          ? action
          : '$action following the game';
    }
    return '$action $timingCaptionClause'.trim();
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

  /// Player names only (no team), for "with …" teammate clauses.
  String _formatPlayerNamesOnly(
    List<RosterHit> rows,
    CaptionTemplate template,
  ) {
    if (rows.isEmpty) return '';
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
    return _joinNames(labels);
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
    // Always open A–Z; usage counts + custom verbOrder still persist.
    verbSortMode = VerbSortMode.alphabetical;
    await _prefs!.saveVerbSortMode(VerbSortMode.alphabetical);
    _verbUsageCounts = await _prefs!.getVerbUsageCountsForSport(sport);
    await _loadVerbCatalog();
    // V2 always auto-detects bursts from capture times; no session toggle.
    burstDetectionEnabled = true;
    captionTemplate = await _prefs!.getCaptionTemplate();
    mlbTimestampEnabled = await _prefs!.getMlbInningFromClockEnabled();
    showKeywordsField = await _prefs!.getShowKeywordsField();
    showPersonalityField = await _prefs!.getShowPersonalityField();
    applyVerbKeywords = await _prefs!.getApplyVerbKeywords();
    applyPlayerNamesToKeywords = await _prefs!.getApplyPlayerNamesToKeywords();
    ftpModeEnabled = await _prefs!.getFtpModeEnabled();
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
    await _loadFtpHistory();
    notifyListeners();
  }

  Future<void> _loadCaptionStyleCatalog() async {
    final prefs = _prefs;
    if (prefs == null) return;
    // Always re-read the active template. Bootstrap may have loaded an older
    // copy before the startup Edit/Done path wrote Custom to prefs — without
    // this, Go Time kept the stale in-memory template.
    captionTemplate = await prefs.getCaptionTemplate();
    final catalog = await CaptionStyleCatalog.load(prefs, sport: sport);
    _captionStyleCatalog = catalog;
    _activeCaptionStyleToken = catalog.activeToken;

    // Keep the persisted working template. Resolving wire tokens via the catalog
    // returns the wire master and was wiping named-style / custom free-text after
    // Save as… or closing the layout editor. Only re-hydrate from the library
    // entry when that is the active menu selection (so library edits apply).
    if (catalog.activeToken.startsWith('saved:')) {
      captionTemplate = catalog.resolve(
        catalog.activeToken,
        refForCustom: captionTemplate,
      );
    } else {
      // Wire / custom working copy: fill empty game-ID, and swap known sport
      // defaults (MLB → NHL) without clobbering authored free-text.
      // Custom / named styles: only fill when empty (never replace authored text).
      captionTemplate = CaptionTemplate.withSportGameIdentifierDefault(
        captionTemplate,
        sport,
        replaceKnownDefaults: !captionTemplate.isUserAuthoredCaptionStyle,
      );
    }
  }

  Future<void> _loadVerbCatalog() async {
    final repository = _verbRepository;
    if (repository == null) return;
    _verbCatalog = await repository.load(sport);
    final prefs = _prefs;
    if (prefs != null) {
      _verbUsageCounts = await prefs.getVerbUsageCountsForSport(sport);
    }
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

  /// When false, captions omit the inning/period/quarter clause and the timing
  /// bar is greyed out. Persists on the working caption template.
  bool get includeTimingPhrase => captionTemplate.includeTimingPhrase;

  Future<void> setIncludeTimingPhrase(bool include) async {
    if (captionTemplate.includeTimingPhrase == include) return;
    captionTemplate = captionTemplate.copyWith(includeTimingPhrase: include);
    notifyListeners();
    await _prefs?.saveCaptionTemplate(captionTemplate);
  }

  Future<void> setFtpModeEnabled(bool enabled) async {
    if (enabled == ftpModeEnabled) return;
    ftpModeEnabled = enabled;
    notifyListeners();
    await _prefs?.saveFtpModeEnabled(enabled);
  }

  /// Apply startup choices, then load rosters via API and images from folder.
  /// Burst grouping is always detected from capture times in the loaded folder.
  Future<void> applyStartup({
    required String sport,
    required String homeTeam,
    required String awayTeam,
    required String folderPath,
    List<Player>? homeRosterOverride,
    List<Player>? awayRosterOverride,
    bool singleTeamMode = false,
    String venue = '',
    String city = '',
    String region = '',
    String country = '',
    String countryCode = '',
  }) async {
    sessionGeneration++;
    this.sport = sport;
    this.homeTeam = homeTeam;
    this.singleTeamMode = singleTeamMode;
    this.awayTeam = singleTeamMode ? '' : awayTeam;
    this.venue = venue;
    this.city = city;
    this.region = region;
    this.country = country;
    this.countryCode = countryCode;
    burstDetectionEnabled = true;
    pinnedVerb = null;
    pinnedPlayer = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedIsHome = true;
    selectedVerb = null;
    celebrationType = null;
    personality = '';
    manualCaptionOverride = null;
    rbi = 0;
    selectedBase = null;
    inning = 1;
    timingHalf = null;
    preGame = false;
    postGame = false;
    sessionLoading = true;
    sessionLoadingLabel = 'Loading rosters…';
    sessionReady = false;
    notifyListeners();

    _api.setSport(sport);
    await _prefs?.saveCurrentSport(sport);
    ftpModeEnabled = await _prefs?.getFtpModeEnabled() ?? true;
    await _loadVerbCatalog();
    await _loadCaptionStyleCatalog();

    await loadRosters(
      homeOverride: homeRosterOverride,
      awayOverride: singleTeamMode ? const <Player>[] : awayRosterOverride,
    );
    sessionLoadingLabel = 'Loading images…';
    notifyListeners();
    await loadFolder(folderPath);

    sessionLoading = false;
    sessionLoadingLabel = null;
    sessionReady = true;
    notifyListeners();
  }

  /// Apply roster / team-name edits from [showRosterImportDialog] without
  /// restarting the session.
  void applyRosterEdits({
    String? homeTeamName,
    List<Player>? homePlayers,
    String? awayTeamName,
    List<Player>? awayPlayers,
  }) {
    if (homePlayers != null) {
      homeRoster = _sortPlayers(homePlayers);
    }
    if (homeTeamName != null && homeTeamName.trim().isNotEmpty) {
      homeTeam = homeTeamName.trim();
    }

    if (awayPlayers != null) {
      awayRoster = _sortPlayers(awayPlayers);
      singleTeamMode = false;
      if (awayTeamName != null && awayTeamName.trim().isNotEmpty) {
        awayTeam = awayTeamName.trim();
      }
    } else if (awayTeamName != null && awayTeamName.trim().isNotEmpty) {
      awayTeam = awayTeamName.trim();
      singleTeamMode = false;
    } else if (homePlayers != null && awayPlayers == null) {
      singleTeamMode = true;
      awayTeam = '';
      awayRoster = const [];
    }

    _reconcileSelectedPlayersAfterRosterChange();
    notifyListeners();
  }

  void _reconcileSelectedPlayersAfterRosterChange() {
    pinnedPlayer = _resolvePinnedPlayer();
    if (selectedPlayers.isEmpty) {
      _syncPrimaryPlayer();
      return;
    }
    final kept = <RosterHit>[];
    for (final row in selectedPlayers) {
      final match = _findRosterPlayer(row.player, isHome: row.isHome);
      if (match != null) {
        kept.add(RosterHit(player: match, isHome: row.isHome));
      }
    }
    selectedPlayers
      ..clear()
      ..addAll(kept);
    if (selectedPlayers.isEmpty) {
      selectedPlayer = null;
    }
    _syncPrimaryPlayer();
    _syncPersonality();
    _syncKeywords();
  }

  Player? _findRosterPlayer(Player player, {required bool isHome}) {
    final roster = isHome ? homeRoster : awayRoster;
    for (final candidate in roster) {
      if (_samePlayer(candidate, player)) return candidate;
    }
    return null;
  }

  RosterHit? _resolvePinnedPlayer() {
    final pinned = pinnedPlayer;
    if (pinned == null) return null;
    final match = _findRosterPlayer(pinned.player, isHome: pinned.isHome);
    if (match == null) return null;
    return RosterHit(player: match, isHome: pinned.isHome);
  }

  void resetToStartup() {
    _folderWatchGeneration++;
    _stopFolderWatch();
    sessionReady = false;
    sessionLoading = false;
    sessionLoadingLabel = null;
    imagePaths = [];
    currentIndex = 0;
    selectedImagePaths.clear();
    homeRoster = const [];
    awayRoster = const [];
    singleTeamMode = false;
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = null;
    pinnedVerb = null;
    pinnedPlayer = null;
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
      final isAdmin = await AdminService.isCurrentUserAdmin();
      final useOfficial =
          isAdmin && (await _prefs?.getUseOfficialLeagueApis() ?? false);
      final useTank01Fb = tank01SupportsSport(sport) && !useOfficial;
      final apiSource = _rosterSourceFor(sport, useTank01Fb);
      if (singleTeamMode || !hasOpponentTeam) {
        rosterSourceLabel = homeOverride != null ? 'Pasted roster' : apiSource;
        final home = homeOverride ?? await _api.fetchTeamRoster(homeTeam);
        homeRoster = _sortPlayers(home);
        awayRoster = const [];
      } else {
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
      }
    } catch (e) {
      rosterError = e.toString();
      // Fallback demo roster so UI remains reviewable offline.
      homeRoster = homeOverride == null
          ? _demoRoster(homeTeam)
          : _sortPlayers(homeOverride);
      if (singleTeamMode || !hasOpponentTeam) {
        awayRoster = const [];
      } else {
        awayRoster = awayOverride == null
            ? _demoRoster(awayTeam)
            : _sortPlayers(awayOverride);
      }
    } finally {
      rostersLoading = false;
      notifyListeners();
    }
  }

  /// Replaces a loaded roster after the user decides how to handle duplicates.
  void replaceLoadedRosters({List<Player>? home, List<Player>? away}) {
    if (home != null) homeRoster = _sortPlayers(home);
    if (away != null) awayRoster = _sortPlayers(away);
    notifyListeners();
  }

  static String _rosterSourceFor(String sport, bool useTank01Firebase) {
    switch (sport.toLowerCase()) {
      case 'baseball':
        return useTank01Firebase ? 'Tank01 Firebase (MLB)' : 'MLB API';
      case 'hockey':
        return useTank01Firebase ? 'Tank01 Firebase (NHL)' : 'NHL API';
      case 'basketball':
        return useTank01Firebase ? 'Tank01 Firebase (NBA)' : 'ESPN NBA';
      case 'wnba':
        return useTank01Firebase ? 'Tank01 Firebase (WNBA)' : 'ESPN WNBA';
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
    final generation = ++_folderWatchGeneration;
    _stopFolderWatch();
    try {
      await NativeFilePicker.ensureMediaReadPermission();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        imagePaths = [];
        currentIndex = 0;
        return;
      }
      final listed = await _listSessionImages(dirPath);
      if (generation != _folderWatchGeneration) return;
      final ready = <String>[];
      final pending = <String>[];
      final recentCutoff = DateTime.now().subtract(const Duration(minutes: 2));
      for (final path in listed) {
        var includeNow = true;
        try {
          final modified = await File(path).lastModified();
          if (modified.isAfter(recentCutoff)) {
            includeNow = await isImageFileComplete(path);
          }
        } catch (_) {
          includeNow = false;
        }
        if (includeNow) {
          ready.add(path);
        } else {
          pending.add(path);
        }
      }
      if (generation != _folderWatchGeneration) return;
      ready.sort();
      imagePaths = ready;
      currentIndex = 0;
      selectedImagePaths.clear();
      savedImages.clear();
      captionedImages.clear();
      sentImages.clear();
      captureByPath.clear();
      _imageContentStamp.clear();
      _fileLength.clear();
      _fileModifiedMs.clear();
      _fileChangedMs.clear();
      _startFolderWatch(dirPath, generation);
      unawaited(_finishFolderMetadata(dirPath, generation));
      unawaited(_ingestFolderAdditions(generation));
      for (final path in pending) {
        unawaited(_addImageWhenReady(path, generation));
      }
    } finally {
      if (generation == _folderWatchGeneration) {
        loadingImages = false;
        notifyListeners();
      }
    }
  }

  /// Capture times, saved-caption marks, and an on-import IPTC template run
  /// after the pictures are already on screen.
  Future<void> _finishFolderMetadata(String dirPath, int generation) async {
    if (generation != _folderWatchGeneration) return;
    final keep = currentPath;
    await _loadCaptureTimes();
    if (generation != _folderWatchGeneration) return;
    imagePaths.sort((a, b) {
      final ta = captureByPath[a];
      final tb = captureByPath[b];
      if (ta != null && tb != null) return ta.compareTo(tb);
      return a.compareTo(b);
    });
    if (keep != null) {
      final index = imagePaths.indexOf(keep);
      if (index >= 0) currentIndex = index;
    }
    notifyListeners();
    final marked = await FloCaptionMark.savedPaths(List<String>.from(imagePaths));
    if (generation != _folderWatchGeneration) return;
    savedImages.addAll(marked);
    captionedImages.addAll(marked);
    await _restoreSavedPrefs(dirPath);
    await _applyIptcTemplateOnImportIfEnabled();
    if (generation != _folderWatchGeneration) return;
    await _refreshFrameIptc();
    notifyListeners();
  }

  bool _isSessionImagePath(String path) {
    final name = p.basename(path);
    if (name.startsWith('.') || name.startsWith('._')) return false;
    final lower = name.toLowerCase();
    if (lower.startsWith('tmp.') || lower.endsWith('.tmp')) return false;
    return _sessionImageExtensions.contains(p.extension(lower));
  }

  Future<List<String>> _listSessionImages(String dirPath) async {
    final files = <String>[];
    await for (final entity in Directory(dirPath).list(followLinks: false)) {
      if (entity is! File) continue;
      if (_isSessionImagePath(entity.path)) files.add(entity.path);
    }
    return files;
  }

  /// Keeps the open folder in sync: new photos are added, and a file saved
  /// over an existing name is redrawn. Uses the same scan as [refreshOpenFolder].
  void ensureLiveFolderRefresh() {
    if (_openFolderPath == null) return;
    _watchedFolder ??= _openFolderPath;
    if (_folderPollTimer != null) return;
    _folderPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_scanOpenFolder(announce: false));
    });
  }

  String? get _openFolderPath {
    final watched = _watchedFolder?.trim();
    if (watched != null && watched.isNotEmpty) {
      return _normalizeDir(watched);
    }
    if (imagePaths.isEmpty) return null;
    return _normalizeDir(p.dirname(imagePaths.first));
  }

  String _normalizeDir(String path) {
    var normalized = p.normalize(path);
    if (normalized.length > 1 && normalized.endsWith(p.separator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Reloads the open folder: new photos are added, and existing thumbnails
  /// are drawn again from disk so a save-over shows up.
  Future<void> refreshOpenFolder() => _scanOpenFolder(announce: true);

  Future<void> _scanOpenFolder({required bool announce}) async {
    if (_folderScanInFlight) {
      if (!announce) return;
      _folderScanAgain = true;
      return;
    }
    final folder = _openFolderPath;
    if (folder == null) {
      if (announce) {
        statusMessage = 'Open a photo folder first';
        notifyListeners();
      }
      return;
    }
    _watchedFolder = folder;
    _folderScanInFlight = true;
    if (announce) {
      refreshingFolder = true;
      notifyListeners();
    }
    var added = 0;
    var updated = 0;
    var removed = 0;
    try {
      final listed = await _listSessionImages(folder);
      final current = currentPath;
      removed = await _dropImagesMissingFrom(listed);
      var currentChanged = false;
      const batchSize = 32;
      for (var start = 0; start < listed.length; start += batchSize) {
        final end = start + batchSize > listed.length
            ? listed.length
            : start + batchSize;
        final stats = await Future.wait(
          listed.sublist(start, end).map((path) async {
            try {
              return MapEntry<String, FileStat?>(path, await File(path).stat());
            } catch (_) {
              return MapEntry<String, FileStat?>(path, null);
            }
          }),
        );
        for (final entry in stats) {
          final path = entry.key;
          final stat = entry.value;
          if (stat == null) continue;
          if (!imagePaths.contains(path)) {
            if (!await isImageFileComplete(path)) continue;
            await _insertCompletedImage(path);
            _rememberFileSig(path, stat);
            added++;
            continue;
          }
          final hadSig = _fileLength.containsKey(path);
          final modifiedMs = stat.modified.millisecondsSinceEpoch;
          // Caption writes keep the original clock (-P) and only change
          // size. A new picture from Photo Mechanic changes the clock.
          // Reloading on size alone re-decodes every photo you just saved.
          final mtimeChanged =
              hadSig && _fileModifiedMs[path] != modifiedMs;
          final sizeChanged = hadSig && _fileLength[path] != stat.size;
          final pixelsChanged =
              mtimeChanged || (announce && sizeChanged);
          _rememberFileSig(path, stat);
          if (!pixelsChanged) continue;
          _imageContentStamp[path] = imageContentStamp(path) + 1;
          updated++;
          if (path == current) currentChanged = true;
        }
      }
      if (current != null) {
        final index = imagePaths.indexOf(current);
        if (index >= 0) currentIndex = index;
        if (announce || currentChanged || removed > 0) {
          await _refreshFrameIptc();
        }
      }
      if (announce) {
        statusMessage = added == 0
            ? (removed == 0 ? 'Photos refreshed' : 'Removed $removed photo${removed == 1 ? '' : 's'}')
            : 'Added $added photo${added == 1 ? '' : 's'}';
      }
    } catch (_) {
      if (announce) statusMessage = 'Could not refresh photos';
    } finally {
      _folderScanInFlight = false;
      if (announce) refreshingFolder = false;
      if (announce || added > 0 || updated > 0 || removed > 0) notifyListeners();
      if (_folderScanAgain) {
        _folderScanAgain = false;
        unawaited(_scanOpenFolder(announce: announce));
      }
    }
  }

  /// Drops session photos that Photo Mechanic (or Finder) removed from the
  /// folder, so the filmstrip does not keep a blank frame.
  Future<int> _dropImagesMissingFrom(List<String> listed) async {
    final present = listed.toSet();
    final gone = <String>[];
    for (final path in imagePaths) {
      if (present.contains(path)) continue;
      if (await File(path).exists()) continue;
      gone.add(path);
    }
    if (gone.isEmpty) return 0;
    for (final path in gone) {
      _forgetImage(path);
    }
    await _persistSaved();
    return gone.length;
  }

  void _forgetImage(String path) {
    final removedIndex = imagePaths.indexOf(path);
    imagePaths.remove(path);
    captureByPath.remove(path);
    _imageContentStamp.remove(path);
    _fileLength.remove(path);
    _fileModifiedMs.remove(path);
    _fileChangedMs.remove(path);
    _pendingIngest.remove(path);
    savedImages.remove(path);
    captionedImages.remove(path);
    sentImages.remove(path);
    selectedImagePaths.remove(path);
    if (imagePaths.isEmpty) {
      currentIndex = 0;
    } else if (removedIndex >= 0 && removedIndex < currentIndex) {
      currentIndex--;
    } else if (currentIndex >= imagePaths.length) {
      currentIndex = imagePaths.length - 1;
    }
  }

  int imageContentStamp(String path) => _imageContentStamp[path] ?? 0;

  void _startFolderWatch(String dirPath, int generation) {
    _folderWatch?.cancel();
    _folderPollTimer?.cancel();
    _watchedFolder = dirPath;
    try {
      _folderWatch = Directory(dirPath).watch().listen(
        (_) {
          if (generation != _folderWatchGeneration) return;
          _scheduleFolderIngest(generation);
        },
        onError: (_) {},
      );
    } catch (_) {
      _folderWatch = null;
    }
    // External volumes often drop file-system events. The same scan as the
    // Refresh button runs on a timer so new and replaced photos show up.
    ensureLiveFolderRefresh();
  }

  void _stopFolderWatch() {
    _folderIngestTimer?.cancel();
    _folderIngestTimer = null;
    _folderPollTimer?.cancel();
    _folderPollTimer = null;
    _folderWatch?.cancel();
    _folderWatch = null;
    _watchedFolder = null;
    _pendingIngest.clear();
  }

  void _scheduleFolderIngest(int generation) {
    _folderIngestTimer?.cancel();
    _folderIngestTimer = Timer(const Duration(milliseconds: 400), () {
      if (generation != _folderWatchGeneration) return;
      unawaited(_scanOpenFolder(announce: false));
    });
  }

  /// Adds pictures saved into the open folder without replacing the list.
  /// Files still being written stay out until the image container is complete.
  Future<void> _ingestFolderAdditions(int generation) async {
    final folder = _watchedFolder;
    if (folder == null || generation != _folderWatchGeneration) return;
    List<String> listed;
    try {
      listed = await _listSessionImages(folder);
    } catch (_) {
      return;
    }
    if (generation != _folderWatchGeneration) return;
    for (final path in listed) {
      if (!imagePaths.contains(path)) {
        if (_pendingIngest.contains(path)) continue;
        unawaited(_addImageWhenReady(path, generation));
        continue;
      }
      unawaited(_refreshIfReplaced(path, generation));
    }
  }

  Future<void> _refreshIfReplaced(String path, int generation) async {
    if (generation != _folderWatchGeneration) return;
    if (_pendingIngest.contains(path)) return;
    FileStat stat;
    try {
      stat = await File(path).stat();
    } catch (_) {
      return;
    }
    if (generation != _folderWatchGeneration) return;
    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final known = _fileLength.containsKey(path);
    if (!known) {
      _fileLength[path] = stat.size;
      _fileModifiedMs[path] = modifiedMs;
      return;
    }
    if (_fileModifiedMs[path] == modifiedMs) {
      _fileLength[path] = stat.size;
      return;
    }
    if (!_pendingIngest.add(path)) return;
    try {
      final ready = await waitForImageFileReady(path);
      if (!ready || generation != _folderWatchGeneration) return;
      if (!imagePaths.contains(path)) return;
      final after = await File(path).stat();
      _fileLength[path] = after.size;
      _fileModifiedMs[path] = after.modified.millisecondsSinceEpoch;
      _imageContentStamp[path] = imageContentStamp(path) + 1;
      notifyListeners();
      if (path == currentPath) unawaited(_refreshFrameIptc());
    } catch (_) {
    } finally {
      if (generation == _folderWatchGeneration) {
        _pendingIngest.remove(path);
      }
    }
  }

  Future<void> _addImageWhenReady(String path, int generation) async {
    if (imagePaths.contains(path) || !_pendingIngest.add(path)) return;
    try {
      final ready = await waitForImageFileReady(path);
      if (!ready || generation != _folderWatchGeneration) return;
      if (imagePaths.contains(path)) return;
      final folder = _watchedFolder;
      if (folder == null || p.dirname(path) != folder) return;
      await _insertCompletedImage(path);
    } finally {
      if (generation == _folderWatchGeneration) {
        _pendingIngest.remove(path);
      }
    }
  }

  Future<void> _insertCompletedImage(String path) async {
    final current = currentPath;
    await _recordCaptureTime(path);
    if (imagePaths.contains(path)) return;
    imagePaths.add(path);
    imagePaths.sort((a, b) {
      final ta = captureByPath[a];
      final tb = captureByPath[b];
      if (ta != null && tb != null) return ta.compareTo(tb);
      return a.compareTo(b);
    });
    if (current != null) {
      final index = imagePaths.indexOf(current);
      if (index >= 0) currentIndex = index;
    }
    try {
      final stat = await File(path).stat();
      _fileLength[path] = stat.size;
      _fileModifiedMs[path] = stat.modified.millisecondsSinceEpoch;
      _fileChangedMs[path] = stat.changed.millisecondsSinceEpoch;
    } catch (_) {}
    notifyListeners();
    unawaited(() async {
      if (await FloCaptionMark.isSaved(path)) {
        savedImages.add(path);
        captionedImages.add(path);
        notifyListeners();
      }
      await _applyIptcTemplateOnImportToPath(path);
    }());
  }

  Future<void> _applyIptcTemplateOnImportToPath(String imagePath) async {
    if (_prefs == null || !imagePaths.contains(imagePath)) return;
    try {
      final mode = await _prefs!.getIptcApplyMode();
      if (mode != IptcApplyMode.onImport) return;
      var preset = await _loadSelectedIptcPreset();
      var cleared = await _loadIptcClearedFields();
      if (captionedImages.contains(imagePath)) {
        preset = FloCaptionMark.withoutProtectedFields(preset);
        cleared = FloCaptionMark.withoutProtectedClears(cleared);
      }
      if (preset.isEmpty && cleared.isEmpty) return;
      final index = imagePaths.indexOf(imagePath);
      await IptcTemplateApplyService.applyToImage(
        imagePath,
        preset,
        imageIndex: index >= 0 ? index : null,
        fieldsToClear: cleared.isNotEmpty ? cleared : null,
      );
    } catch (_) {}
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
      final label = 'Writing IPTC template to ${imagePaths.length} images…';
      if (sessionLoading) {
        sessionLoadingLabel = label;
      } else {
        statusMessage = label;
      }
      notifyListeners();
      var i = 0;
      for (final path in imagePaths) {
        final alreadyCaptioned = captionedImages.contains(path);
        await IptcTemplateApplyService.applyToImage(
          path,
          alreadyCaptioned
              ? FloCaptionMark.withoutProtectedFields(preset)
              : preset,
          imageIndex: i,
          fieldsToClear: alreadyCaptioned
              ? FloCaptionMark.withoutProtectedClears(cleared)
              : (cleared.isNotEmpty ? cleared : null),
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
    final paths = List<String>.from(imagePaths);
    const chunk = 40;
    for (var i = 0; i < paths.length; i += chunk) {
      final end = i + chunk > paths.length ? paths.length : i + chunk;
      final slice = paths.sublist(i, end);
      final parsed = await _captureTimesFor(slice);
      for (final path in slice) {
        final captured = parsed[path];
        if (captured != null) {
          captureByPath[path] = captured;
          continue;
        }
        try {
          captureByPath[path] = await File(path).lastModified();
        } catch (_) {}
      }
    }
    // Re-sort by capture time when available.
    imagePaths.sort((a, b) {
      final ta = captureByPath[a];
      final tb = captureByPath[b];
      if (ta != null && tb != null) return ta.compareTo(tb);
      return a.compareTo(b);
    });
  }

  /// One ExifTool process reads capture times for a batch of photos.
  Future<Map<String, DateTime>> _captureTimesFor(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final proc = await ExiftoolHelper.run([
        '-j',
        '-DateTimeOriginal',
        '-d',
        '%Y:%m:%d %H:%M:%S',
        ...paths,
      ]);
      if (!proc.isSuccess || proc.stdoutText.trim().isEmpty) return const {};
      final decoded = jsonDecode(proc.stdoutText);
      if (decoded is! List) return const {};
      final found = <String, DateTime>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final source = item['SourceFile']?.toString();
        final parsed = _parseExifDate(item['DateTimeOriginal']?.toString() ?? '');
        if (source == null || source.isEmpty || parsed == null) continue;
        found[source] = parsed;
      }
      return found;
    } catch (_) {
      return const {};
    }
  }

  void _rememberFileSig(String path, FileStat stat) {
    _fileLength[path] = stat.size;
    _fileModifiedMs[path] = stat.modified.millisecondsSinceEpoch;
    _fileChangedMs[path] = stat.changed.millisecondsSinceEpoch;
  }

  Future<void> _recordCaptureTime(String path) async {
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
          return;
        }
      }
    } catch (_) {}
    try {
      captureByPath[path] = await File(path).lastModified();
    } catch (_) {}
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
      ftpProfileName = current;
      destinationLabel = '$current · FTP';
    } else {
      ftpProfileName = null;
      destinationLabel = 'Photoshelter · FTP';
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

  /// Adds a typed custom name to the home/away roster and selects it.
  /// Returns an error message on jersey conflict; null on success.
  String? addCustomPlayer({
    required bool isHome,
    required String fullName,
    String? jerseyNumber,
    String? position,
  }) {
    final name = fullName.trim();
    if (name.isEmpty) return 'Enter a player name.';
    final jersey = jerseyNumber?.trim();
    final jerseyKey = (jersey == null || jersey.isEmpty) ? null : jersey;
    final roster = isHome ? homeRoster : awayRoster;
    if (jerseyKey != null) {
      final taken = roster.any(
        (p) => (p.jerseyNumber ?? '').trim() == jerseyKey,
      );
      if (taken) return 'Jersey #$jerseyKey is already on this team.';
    }
    final player = Player(
      fullName: name,
      firstName: name.split(RegExp(r'\s+')).first,
      jerseyNumber: jerseyKey,
      displayName: jerseyKey == null ? name : '$name #$jerseyKey',
      position: position?.trim().isEmpty ?? true ? null : position!.trim(),
    );
    final next = _sortPlayers([...roster, player]);
    if (isHome) {
      homeRoster = next;
    } else {
      awayRoster = next;
    }
    // Always select the new custom name (don't toggle off if somehow present).
    final already = selectedPlayers.any(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
    if (!already) {
      selectPlayer(player, isHome: isHome);
    } else {
      notifyListeners();
    }
    return null;
  }

  /// Replaces [original] on the home or away roster. Jersey conflicts with a
  /// different player are rejected. Selection follows the renamed player.
  String? updatePlayer({
    required bool isHome,
    required Player original,
    required String fullName,
    String? jerseyNumber,
  }) {
    final name = fullName.trim();
    if (name.isEmpty) return 'Enter a player name.';
    final jersey = jerseyNumber?.trim();
    final jerseyKey = (jersey == null || jersey.isEmpty) ? null : jersey;
    final roster = isHome ? homeRoster : awayRoster;
    if (jerseyKey != null) {
      final taken = roster.any(
        (player) =>
            (player.jerseyNumber ?? '').trim() == jerseyKey &&
            !_samePlayer(player, original),
      );
      if (taken) return 'Jersey #$jerseyKey is already on this team.';
    }
    final updated = Player(
      fullName: name,
      firstName: name.split(RegExp(r'\s+')).first,
      jerseyNumber: jerseyKey,
      displayName: jerseyKey == null ? name : '$name #$jerseyKey',
      playerId: original.playerId,
      position: original.position,
    );
    final next = _sortPlayers([
      for (final player in roster)
        _samePlayer(player, original) ? updated : player,
    ]);
    if (isHome) {
      homeRoster = next;
    } else {
      awayRoster = next;
    }
    for (var i = 0; i < selectedPlayers.length; i++) {
      final row = selectedPlayers[i];
      if (row.isHome == isHome && _samePlayer(row.player, original)) {
        selectedPlayers[i] = RosterHit(player: updated, isHome: isHome);
      }
    }
    if (pinnedPlayer != null &&
        pinnedPlayer!.isHome == isHome &&
        _samePlayer(pinnedPlayer!.player, original)) {
      pinnedPlayer = RosterHit(player: updated, isHome: isHome);
    }
    _syncPrimaryPlayer();
    manualCaptionOverride = null;
    notifyListeners();
    return null;
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

  /// Jersey shorthand typed in the caption box: `h34 `, `v88 `, `hh27 `.
  static final RegExp _captionJerseyTokenPattern = RegExp(
    r'(?:^|(?<=\s))([hH]{1,2}|[vV]{1,2})(\d{1,3}) ',
  );

  /// True when [value] is only home/visitor jersey codes (no free text).
  static final RegExp _captionJerseyOnlyPattern = RegExp(
    r'^([hv]{1,2}\d{1,3}\s*)+$',
    caseSensitive: false,
  );

  void setManualCaption(String? value) {
    if (value == null) {
      manualCaptionOverride = null;
      notifyListeners();
      return;
    }

    final expanded = _expandCaptionJerseyTokens(value);
    if (expanded != null) {
      for (final hit in expanded.players) {
        _ensurePlayerSelected(hit.player, isHome: hit.isHome);
      }
      captionSelectionStarted = true;
      if (expanded.clearManual) {
        manualCaptionOverride = null;
      } else {
        manualCaptionOverride = expanded.text;
      }
      _syncPrimaryPlayer();
      _syncKeywords();
      notifyListeners();
      return;
    }

    manualCaptionOverride = value;
    notifyListeners();
  }

  /// Expands completed `h34 ` / `v88 ` tokens in caption text.
  ///
  /// Returns null when nothing resolved. [clearManual] is true when the input
  /// was only jersey codes so the formula caption can take over.
  _CaptionJerseyExpansion? _expandCaptionJerseyTokens(String value) {
    final matches = _captionJerseyTokenPattern.allMatches(value).toList();
    if (matches.isEmpty) return null;

    final players = <RosterHit>[];
    final buffer = StringBuffer();
    var cursor = 0;
    var anyResolved = false;
    String? missingJersey;

    for (final match in matches) {
      buffer.write(value.substring(cursor, match.start));
      final prefix = match.group(1)!.toLowerCase();
      final jersey = match.group(2)!;
      final isHome = prefix.startsWith('h');
      final roster = isHome ? homeRoster : awayRoster;
      Player? found;
      for (final player in roster) {
        if ((player.jerseyNumber ?? '').trim() == jersey) {
          found = player;
          break;
        }
      }
      if (found != null) {
        anyResolved = true;
        players.add(RosterHit(player: found, isHome: isHome));
        buffer.write('${found.fullName} ');
      } else {
        missingJersey = jersey;
        buffer.write(value.substring(match.start, match.end));
      }
      cursor = match.end;
    }
    buffer.write(value.substring(cursor));

    if (!anyResolved) {
      if (missingJersey != null) {
        statusMessage = 'No player wearing #$missingJersey';
      }
      return null;
    }

    return _CaptionJerseyExpansion(
      text: buffer.toString(),
      players: players,
      clearManual: _captionJerseyOnlyPattern.hasMatch(value.trim()),
    );
  }

  void _ensurePlayerSelected(Player player, {required bool isHome}) {
    final exists = selectedPlayers.any(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
    if (!exists) {
      selectedPlayers.add(RosterHit(player: player, isHome: isHome));
    }
  }

  Future<void> applyTransferredCaption(CaptionTransferPayload payload) async {
    // Paste replaces the live caption as a manual override; keep roster/verb
    // pins so the next frame can restore them after save.
    // The copied byline names the source photographer — swap in this frame's
    // IPTC photographer so a shared moment keeps the right credit.
    final path = currentPath;
    if (path != null) {
      final fromFile = await photographerNameForPath(path);
      if (fromFile.isNotEmpty) photographerName = fromFile;
    }
    manualCaptionOverride =
        CaptionTransferPayload.captionForDestinationPhotographer(
      caption: payload.caption,
      sourcePhotographer: payload.photographerName,
      destinationPhotographer: photographerName,
      removeDiacritics: captionTemplate.removeDiacritics,
    );
    personality = payload.personality;
    if (payload.headline.isNotEmpty || showHeadlineField) {
      headline = payload.headline;
    }
    if (payload.keywords.isNotEmpty || showKeywordsField) {
      keywords = payload.keywords;
      _baseKeywordKeys
        ..clear()
        ..addAll(_parseMetadataList(keywords).map((e) => e.toLowerCase()));
      _managedKeywordKeys.clear();
    }
    metadataDirty = true;
    captionSelectionStarted = true;
    notifyListeners();
  }

  /// Right-click Paste Caption on a photo: drop live player/verb picks and show
  /// the pasted text immediately in the preview strip.
  void applyPastedPhotoCaption({
    required String caption,
    String personality = '',
    String keywords = '',
  }) {
    selectedPlayers.clear();
    selectedPlayer = null;
    selectedVerb = null;
    customVerbPhrase = '';
    celebrationType = null;
    verbModifierSelections.clear();
    rbi = 0;
    selectedBase = null;
    preGame = false;
    postGame = false;
    _firebarCommitted.clear();
    _clearFirebarOptions();
    searchQuery = '';
    selectedImagePaths.clear();

    manualCaptionOverride = caption;
    this.personality = personality;
    if (keywords.isNotEmpty || showKeywordsField) {
      this.keywords = keywords;
      _baseKeywordKeys
        ..clear()
        ..addAll(_parseMetadataList(keywords).map((e) => e.toLowerCase()));
      _managedKeywordKeys.clear();
    }
    metadataDirty = true;
    captionSelectionStarted = caption.trim().isNotEmpty;
    notifyListeners();
  }

  Future<bool> applyPreviousCaption() async {
    final previous = previousCaption;
    if (previous == null) return false;
    await applyTransferredCaption(previous);
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
    if (selectedVerb != verb) {
      celebrationType = null;
      verbModifierSelections
        ..clear()
        ..addEntries(
          (verbDefinition(verb)?.authoring.groups ?? const []).map(
            (group) => MapEntry(group.id, group.defaultOptionId),
          ),
        );
    }
    selectedVerb = verb;
    // Selecting a catalog verb for this frame must not drop a pinned custom
    // verb — stash the phrase and restore it after save / frame advance.
    _stashCustomVerbIfNeeded();
    customVerbPhrase = '';
    manualCaptionOverride = null;
    if (!_verbNeedsRbi(verb)) {
      rbi = 0;
    }
    if (!_verbNeedsBase(verb)) {
      selectedBase = null;
    }
    _syncKeywords();
    unawaited(_recordVerbUsage(verb));
    notifyListeners();
  }

  Future<void> _recordVerbUsage(String verb) async {
    final prefs = _prefs;
    if (prefs == null || verb.trim().isEmpty) return;
    final next = await prefs.incrementVerbUsage(sport, verb);
    _verbUsageCounts[verb] = next;
    if (verbSortMode == VerbSortMode.mostUsed) {
      notifyListeners();
    }
  }

  Future<void> setVerbSortMode(VerbSortMode mode) async {
    if (verbSortMode == mode) return;
    verbSortMode = mode;
    await _prefs?.saveVerbSortMode(mode);
    notifyListeners();
  }

  /// Persist a new within-category order and switch to Custom arrange.
  Future<void> rearrangeVerbsInCategory(
    String category,
    List<String> orderedKeys,
  ) async {
    final prefs = _prefs;
    if (prefs == null || category == 'Favorites') return;
    final order = {
      for (final entry in _verbCatalog.verbsByCategory.entries)
        if (entry.key != 'Favorites')
          entry.key: entry.value.map((item) => item.key).toList(),
    };
    order[category] = List<String>.from(orderedKeys);
    await prefs.saveVerbOrder(order, sport: sport);
    await prefs.saveVerbSortMode(VerbSortMode.custom);
    verbSortMode = VerbSortMode.custom;
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> resetVerbsToFactoryDefaults() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.resetSportVerbsToFactory(sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  void setVerbModifierOption(String groupId, String optionId) {
    final definition =
        selectedVerb == null ? null : verbDefinition(selectedVerb!);
    final matches =
        definition?.authoring.groups.where((item) => item.id == groupId) ??
            const [];
    final group = matches.isEmpty ? null : matches.first;
    if (group == null) return;
    if (!group.required && verbModifierSelections[groupId] == optionId) {
      verbModifierSelections[groupId] = null;
    } else {
      verbModifierSelections[groupId] = optionId;
    }
    manualCaptionOverride = null;
    notifyListeners();
  }

  bool get authoredVerbModifiersComplete {
    final definition =
        selectedVerb == null ? null : verbDefinition(selectedVerb!);
    if (definition == null || !definition.hasAuthoredModifiers) return true;
    return definition.authoring.groups.every((group) {
      if (!group.required) return true;
      final selected =
          verbModifierSelections[group.id] ?? group.defaultOptionId;
      return selected != null &&
          group.options.any((option) => option.id == selected);
    });
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
    verbModifierSelections.clear();
    if (!customVerbPinned) {
      customVerbPhrase = '';
    }
    celebrationType = null;
    rbi = 0;
    selectedBase = null;
    manualCaptionOverride = null;
    captionSelectionStarted =
        selectedPlayers.isNotEmpty || pinnedVerb != null || customVerbPinned;
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
      // Keep [pinnedVerb] — a one-off custom phrase is for this frame only;
      // the pinned catalog verb returns on the next picture.
      celebrationType = null;
      rbi = 0;
      selectedBase = null;
      manualCaptionOverride = null;
      _syncKeywords();
    } else {
      // Explicit clear of the custom field drops the custom pin; selectVerb
      // stashes the phrase without going through this setter so pins survive.
      customVerbPinned = false;
      if (selectedVerb == null && pinnedVerb != null) {
        selectedVerb = pinnedVerb;
      }
      captionSelectionStarted = selectedPlayers.isNotEmpty ||
          selectedVerb != null ||
          pinnedVerb != null;
    }
    notifyListeners();
  }

  void toggleCustomVerbPin() {
    if (customVerbPhrase.trim().isEmpty && lastCustomVerbPhrase.isEmpty) {
      return;
    }
    if (customVerbPhrase.trim().isEmpty && lastCustomVerbPhrase.isNotEmpty) {
      customVerbPhrase = lastCustomVerbPhrase;
    }
    customVerbPinned = !customVerbPinned;
    if (customVerbPinned) {
      pinnedVerb = null;
      selectedVerb = null;
      lastCustomVerbPhrase = customVerbPhrase.trim();
      captionSelectionStarted = selectedPlayers.isNotEmpty;
      manualCaptionOverride = null;
      _syncKeywords();
    }
    notifyListeners();
  }

  void useLastCustomVerb() {
    if (lastCustomVerbPhrase.isEmpty) return;
    setCustomVerbPhrase(lastCustomVerbPhrase);
  }

  void toggleVerbPin(String verb) {
    if (pinnedVerb == verb) {
      pinnedVerb = null;
      notifyListeners();
      return;
    }
    pinnedVerb = verb;
    // Catalog pin replaces a custom pin; keep the custom text for "last used".
    if (customVerbPhrase.trim().isNotEmpty) {
      lastCustomVerbPhrase = customVerbPhrase.trim();
    }
    customVerbPinned = false;
    customVerbPhrase = '';
    // Pinning also selects that verb for the current frame, but selecting a
    // *different* verb later must leave [pinnedVerb] untouched.
    if (selectedVerb != verb) {
      selectVerb(verb);
    } else {
      notifyListeners();
    }
    // Pin alone should not start a caption — wait for a player.
    if (selectedPlayer == null) {
      captionSelectionStarted = false;
      notifyListeners();
    }
  }

  void unpinVerb() {
    if (pinnedVerb == null) return;
    pinnedVerb = null;
    notifyListeners();
  }

  void togglePlayerPin(Player player, {required bool isHome}) {
    if (isPlayerPinned(player, isHome: isHome)) {
      pinnedPlayer = null;
      notifyListeners();
      return;
    }
    pinnedPlayer = RosterHit(player: player, isHome: isHome);
    // Pinning also selects that player for the current frame, but selecting a
    // *different* player later must leave [pinnedPlayer] untouched.
    if (!isPlayerSelected(player, isHome: isHome)) {
      selectPlayer(player, isHome: isHome);
    } else {
      notifyListeners();
    }
  }

  void unpinPlayer() {
    if (pinnedPlayer == null) return;
    pinnedPlayer = null;
    notifyListeners();
  }

  void _stashCustomVerbIfNeeded() {
    final custom = customVerbPhrase.trim();
    if (custom.isNotEmpty) {
      lastCustomVerbPhrase = custom;
    }
  }

  /// Caption text shown in the strip / used by Copy.
  String get displayedCaption {
    if (manualCaptionOverride != null) return manualCaptionOverride!;
    if (selectedPlayer == null) {
      // Never compose the "Team + verb" filler — wait for a player.
      return originalCaption;
    }
    if (hasVerbSelection || selectedPlayer != null) {
      return buildCaptionSentence();
    }
    return originalCaption;
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
    if (category == 'Favorites') {
      final favorites =
          (await prefs.getFavoriteVerbs(sport: sport)).toList(growable: true);
      favorites.remove(verb);
      favorites.insert(index.clamp(0, favorites.length), verb);
      await prefs.saveFavoriteVerbs(
        Set<String>.from(favorites),
        sport: sport,
      );
      await _loadVerbCatalog();
      verbCategory = 'Favorites';
      notifyListeners();
      return;
    }
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
    final cleaned = order.where((category) => category != 'Favorites').toList();
    await _prefs?.saveCategoryOrder(cleaned, sport: sport);
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
      'omitAgainst': definition.omitAgainst,
      'opponentJoiner': definition.opponentJoiner,
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
    required bool omitAgainst,
    required String opponentJoiner,
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
      'omitAgainst': omitAgainst,
      'opponentJoiner': opponentJoiner,
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
    required bool omitAgainst,
    required String opponentJoiner,
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
        omitAgainst: omitAgainst,
        opponentJoiner: opponentJoiner,
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
    required bool omitAgainst,
    required String opponentJoiner,
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
      omitAgainst: omitAgainst,
      opponentJoiner: opponentJoiner,
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
    required bool omitAgainst,
    required String opponentJoiner,
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
      omitAgainst: omitAgainst,
      opponentJoiner: opponentJoiner,
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
          sport: sport,
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
    celebrationType = celebrationType == value ? null : value;
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
      timingHalf = null;
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
    if (next == inning && timingHalf == null && !preGame && !postGame) {
      notifyListeners();
      return;
    }
    inning = next;
    timingHalf = null;
    manualCaptionOverride = null;
    preGame = false;
    postGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void setTimingHalf(String half) {
    if (!supportsTimingHalves) return;
    final normalized = half.trim().toUpperCase();
    if (normalized != '1H' && normalized != '2H') return;
    if (timingHalf == normalized && !preGame && !postGame) {
      notifyListeners();
      return;
    }
    timingHalf = normalized;
    inning = normalized == '1H' ? 1 : 2;
    manualCaptionOverride = null;
    preGame = false;
    postGame = false;
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void setPre(bool v) {
    preGame = v;
    manualCaptionOverride = null;
    if (v) {
      postGame = false;
      timingHalf = null;
    }
    mlbTimestampMatchedPath = null;
    notifyListeners();
  }

  void setPost(bool v) {
    postGame = v;
    manualCaptionOverride = null;
    if (v) {
      preGame = false;
      timingHalf = null;
    }
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
    if (mlbTimestampEnabled) {
      mlbTimestampEnabled = false;
      mlbTimestampMatchedPath = null;
      _mlbTimestampToken++;
      await _prefs?.setMlbInningFromClockEnabled(false);
      notifyListeners();
      return;
    }
    mlbTimestampEnabled = true;
    await _prefs?.setMlbInningFromClockEnabled(true);
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
    if (!hasOpponentTeam) {
      _mlbTimestampFailure(
        'MLB timestamp needs home and away teams.',
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
    final photoDay = DateTime(wall.year, wall.month, wall.day);
    final gameDay = gameInfo.gameDate ?? photoDay;
    final token = ++_mlbTimestampToken;
    mlbTimestampLoading = true;
    notifyListeners();

    try {
      final lookup = await _mlbTimestamp.lookupPhotoInning(
        userHomeName: homeTeam,
        userAwayName: awayTeam,
        gameCalendarDay: gameDay,
        photoCalendarDay: photoDay,
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
          timingHalf = null;
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
    preGame = false;
    postGame = false;
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
      firebarSelectionIndex = -1;
      _clearFirebarAutoPlayerPreview();
      _clearFirebarVerbPreview();
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
    if (q.trim().isEmpty) {
      // Full roster is visible for browsing — no orange caret until typing.
      firebarSelectionIndex = -1;
      _clearFirebarAutoPlayerPreview();
      _clearFirebarVerbPreview();
      notifyListeners();
      return;
    }
    final retained = selectedKey == null
        ? -1
        : results.indexWhere((r) => r.key == selectedKey);
    firebarSelectionIndex =
        retained >= 0 ? retained : (results.isEmpty ? -1 : 0);
    _syncFirebarPlayerPreview();
    _syncFirebarVerbPreview();
    notifyListeners();
  }

  void setSearchOpen(bool open) {
    if (open && !searchOpen) {
      searchQuery = '';
      guidedSearchPrompt = null;
      _guidedSearchHits = const [];
      _pendingCommandInning = null;
      _clearFirebarOptions();
      _firebarAutoPreviewKeys.clear();
      _discardFirebarVerbPreview(keepSelection: true);
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
      if (customVerbPhrase.trim().isNotEmpty) {
        _firebarCommitted.add(FirebarResult.verb(customVerbPhrase.trim()));
      } else if (selectedVerb != null) {
        _firebarCommitted.add(FirebarResult.verb(selectedVerb));
      }
    }
    searchOpen = open;
    // Empty Firebar lists the full roster for browsing, but don't orange-
    // highlight the first player until the user types or presses ↑↓.
    firebarSelectionIndex = -1;
    if (!open) {
      searchQuery = '';
      guidedSearchPrompt = null;
      _guidedSearchHits = const [];
      _pendingCommandInning = null;
      // Keep any match preview as a real selection when Firebar closes.
      _firebarAutoPreviewKeys.clear();
      _discardFirebarVerbPreview(keepSelection: true);
      _firebarCommitted.clear();
      _clearFirebarOptions();
    }
    notifyListeners();
  }

  /// Clicking a name or verb in Firebar commits it and leaves Firebar, unless
  /// the verb still needs a follow-up choice (RBI, base, celebration).
  void commitFirebarResultAndClose(FirebarResult result) {
    commitFirebarResult(result);
    if (searchOpen && firebarOptions.isEmpty) {
      setSearchOpen(false);
    }
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
    final int next;
    if (firebarSelectionIndex < 0) {
      next = delta > 0 ? 0 : results.length - 1;
    } else {
      next = (firebarSelectionIndex + delta).clamp(0, results.length - 1);
      if (next == firebarSelectionIndex) return;
    }
    firebarSelectionIndex = next;
    _syncFirebarPlayerPreview();
    _syncFirebarVerbPreview();
    notifyListeners();
  }

  void selectFirebarResult(FirebarResult result) {
    final index = firebarOrderedResults
        .indexWhere((candidate) => candidate.key == result.key);
    if (index < 0 || index == firebarSelectionIndex) return;
    firebarSelectionIndex = index;
    _syncFirebarPlayerPreview();
    _syncFirebarVerbPreview();
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
    final compound = _parseFirebarJerseyVerbCompound(_normalizedFirebarQuery);
    if (compound != null) {
      _commitFirebarJerseyVerbCompound(compound);
      return;
    }
    final result = firebarSelectedResult;
    if (result != null) commitFirebarResult(result);
  }

  /// Applies `88 looks` / `88 92 look` as player(s) + matching verb in one Enter.
  void _commitFirebarJerseyVerbCompound(_FirebarJerseyVerbCompound compound) {
    final resolved = _resolveFirebarJerseyPlayers(compound.jerseys);
    final verbs = firebarVerbResults;
    if (resolved == null || resolved.isEmpty || verbs.isEmpty) {
      final result = firebarSelectedResult;
      if (result != null) commitFirebarResult(result);
      return;
    }

    // Multi-jersey compounds commit every resolved player. Single-jersey with
    // home+away collisions still prefer the highlighted / subject-side player.
    List<FirebarResult> playersToCommit;
    if (compound.jerseys.length == 1 && resolved.length > 1) {
      final highlighted = firebarSelectedResult;
      if (highlighted?.kind == FirebarResultKind.player &&
          resolved.any((candidate) => candidate.key == highlighted!.key)) {
        playersToCommit = [highlighted!];
      } else if (selectedPlayers.isNotEmpty) {
        final preferredSide = selectedPlayers.first.isHome;
        final preferred = resolved
            .where((candidate) => candidate.isHome == preferredSide)
            .toList();
        playersToCommit = preferred.length == 1 ? preferred : [resolved.first];
      } else {
        if (highlighted?.kind != FirebarResultKind.player) {
          firebarSelectionIndex = firebarOrderedResults.indexWhere(
            (candidate) => candidate.kind == FirebarResultKind.player,
          );
          _syncFirebarPlayerPreview();
          _syncFirebarVerbPreview();
          notifyListeners();
        }
        return;
      }
    } else {
      playersToCommit = resolved;
    }

    final highlighted = firebarSelectedResult;
    final verbKey = _matchCommandVerb(compound.verbQuery);
    final FirebarResult verbResult;
    if (verbKey != null &&
        verbs.any((candidate) => candidate.verbKey == verbKey)) {
      verbResult = FirebarResult.verb(verbKey);
    } else if (verbs.length == 1) {
      verbResult = verbs.first;
    } else if (highlighted?.kind == FirebarResultKind.verb) {
      verbResult = highlighted!;
    } else {
      verbResult = verbs.first;
    }

    for (final playerResult in playersToCommit) {
      final player = playerResult.player!;
      final isHome = playerResult.isHome!;
      if (_firebarAutoPreviewKeys.remove(playerResult.key)) {
        // Already applied as a search preview — keep selection.
      } else if (!isPlayerSelected(player, isHome: isHome)) {
        selectedPlayers.add(RosterHit(player: player, isHome: isHome));
      }
      if (!_firebarCommitted.any((item) => item.key == playerResult.key)) {
        _firebarCommitted.add(playerResult);
      }
    }
    _syncPrimaryPlayer();
    _syncPersonality();
    commitFirebarResult(verbResult);
  }

  /// Shift+Enter from Firebar: commit the highlighted player/verb match, or pick
  /// Save from the destination prompt. Returns true if save was already
  /// kicked off (destination Save/FTP) or follow-up chips need a choice;
  /// false if the caller should still save.
  bool commitFirebarForShiftEnterSave() {
    if (firebarShowingDestinationOptions) {
      final options = filteredFirebarOptions.isNotEmpty
          ? filteredFirebarOptions
          : firebarOptions;
      FirebarOption? saveOpt;
      for (final option in options) {
        if (option.transmit != true) {
          saveOpt = option;
          break;
        }
      }
      chooseFirebarOption(saveOpt ?? options.first);
      return true;
    }
    if (firebarCanQuickSavePlayer) {
      commitSelectedFirebarResult();
      return false;
    }
    if (firebarCanQuickSaveVerb) {
      commitSelectedFirebarResult();
      // Verb commit may open RBI/base/celebration chips — wait for those.
      // Destination Save/FTP chips are cleared so Shift+Enter still saves,
      // matching jersey quick-save.
      if (firebarShowingDestinationOptions) {
        _clearFirebarOptions();
        return false;
      }
      if (firebarOptions.isNotEmpty) return true;
      return false;
    }
    return false;
  }

  void commitFirebarResult(FirebarResult result) {
    captionSelectionStarted = true;
    manualCaptionOverride = null;
    if (result.kind == FirebarResultKind.player) {
      final player = result.player!;
      final isHome = result.isHome!;
      if (_firebarAutoPreviewKeys.remove(result.key)) {
        // Already applied as a search preview — keep selection.
      } else if (!isPlayerSelected(player, isHome: isHome)) {
        selectedPlayers.add(RosterHit(player: player, isHome: isHome));
      }
      _syncPrimaryPlayer();
      _syncPersonality();
    } else {
      final verb = result.verbKey!;
      if (verbDefinition(verb) == null) {
        _discardFirebarVerbPreview(keepSelection: true);
        setCustomVerbPhrase(verb);
        _firebarCommitted
            .removeWhere((item) => item.kind == FirebarResultKind.verb);
        _clearFirebarOptions();
        if (!_firebarCommitted.any((item) => item.key == result.key)) {
          _firebarCommitted.add(result);
        }
        searchQuery = '';
        firebarSelectionIndex = -1;
        notifyListeners();
        return;
      }
      // One-frame override: keep [pinnedVerb] so the next frame restores it.
      _discardFirebarVerbPreview(keepSelection: true);
      selectedVerb = verb;
      _stashCustomVerbIfNeeded();
      customVerbPhrase = '';
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
    firebarSelectionIndex = -1;
    notifyListeners();
  }

  /// When Firebar search narrows to roster match(es), apply player(s) to the
  /// live caption immediately so the strip updates while typing.
  void _syncFirebarPlayerPreview() {
    if (!searchOpen || firebarOptions.isNotEmpty) {
      _clearFirebarAutoPlayerPreview();
      return;
    }
    final query = _normalizedFirebarQuery;
    if (query.isEmpty) {
      _clearFirebarAutoPlayerPreview();
      return;
    }

    final jerseyTokens = _firebarJerseyTokensForQuery(query);
    List<FirebarResult>? previewTargets;
    if (jerseyTokens == null) {
      previewTargets = _singleFirebarPreviewMatch();
    } else if (jerseyTokens.length == 1) {
      // One jersey (± verb): if both teams wear it, follow the highlight.
      final matches = [...firebarHomeResults, ...firebarAwayResults];
      previewTargets = matches.length > 1
          ? _preferredFirebarPlayerPreview(matches)
          : _resolveFirebarJerseyPlayers(jerseyTokens);
    } else {
      previewTargets = _resolveFirebarJerseyPlayers(jerseyTokens);
    }
    if (previewTargets == null || previewTargets.isEmpty) {
      _clearFirebarAutoPlayerPreview();
      return;
    }

    final targetKeys = previewTargets.map((result) => result.key).toSet();
    if (setEquals(targetKeys, _firebarAutoPreviewKeys)) return;

    _clearFirebarAutoPlayerPreview();
    for (final result in previewTargets) {
      final player = result.player!;
      final isHome = result.isHome!;
      if (!isPlayerSelected(player, isHome: isHome)) {
        selectedPlayers.add(RosterHit(player: player, isHome: isHome));
      }
      _firebarAutoPreviewKeys.add(result.key);
    }
    captionSelectionStarted = true;
    manualCaptionOverride = null;
    _syncPrimaryPlayer();
    _syncPersonality();
    _syncKeywords();
  }

  /// While Firebar narrows onto a verb, preview it as the active verb without
  /// clearing [pinnedVerb] (one-frame override while typing / arrowing).
  void _syncFirebarVerbPreview() {
    if (!searchOpen || firebarOptions.isNotEmpty) {
      _clearFirebarVerbPreview();
      return;
    }
    final query = _normalizedFirebarQuery;
    if (query.isEmpty || _parseFirebarJerseyTokens(query) != null) {
      _clearFirebarVerbPreview();
      return;
    }
    final compound = _parseFirebarJerseyVerbCompound(query);
    final matches = firebarVerbResults;
    final players = [...firebarHomeResults, ...firebarAwayResults];
    final highlighted = firebarSelectedResult;
    final String? verb;
    if (compound != null) {
      // Prefer the command resolver so `looks` picks Looks On over
      // National Anthem (whose wording also starts with "looks on").
      final resolved = _matchCommandVerb(compound.verbQuery);
      if (resolved != null &&
          matches.any((candidate) => candidate.verbKey == resolved)) {
        verb = resolved;
      } else if (matches.length == 1) {
        verb = matches.first.verbKey;
      } else {
        _clearFirebarVerbPreview();
        return;
      }
    } else if (matches.length == 1) {
      verb = matches.first.verbKey;
    } else if (players.isEmpty &&
        matches.isNotEmpty &&
        highlighted?.kind == FirebarResultKind.verb &&
        highlighted?.verbKey != null &&
        verbDefinition(highlighted!.verbKey!) != null) {
      // Verb-focused query with several hits — follow the highlight.
      verb = highlighted.verbKey;
    } else if (highlighted?.kind == FirebarResultKind.verb &&
        highlighted?.verbKey != null &&
        verbDefinition(highlighted!.verbKey!) == null) {
      // Custom wording is its own chip; don't treat it as a catalog verb.
      _clearFirebarVerbPreview();
      return;
    } else {
      _clearFirebarVerbPreview();
      return;
    }
    if (verb == null) {
      _clearFirebarVerbPreview();
      return;
    }
    if (_firebarVerbPreviewKey == verb && selectedVerb == verb) return;

    if (_firebarVerbPreviewKey == null) {
      _firebarVerbPreviewPriorSelected = selectedVerb;
    }
    _firebarVerbPreviewKey = verb;
    selectedVerb = verb;
    _stashCustomVerbIfNeeded();
    customVerbPhrase = '';
    celebrationType = null;
    if (!_verbNeedsRbi(verb)) rbi = 0;
    if (!_verbNeedsBase(verb)) selectedBase = null;
    manualCaptionOverride = null;
    if (selectedPlayer != null || pinnedVerb == null) {
      captionSelectionStarted = true;
    }
    _syncKeywords();
  }

  void _clearFirebarVerbPreview() {
    _discardFirebarVerbPreview(keepSelection: false);
  }

  void _discardFirebarVerbPreview({required bool keepSelection}) {
    final previewKey = _firebarVerbPreviewKey;
    final prior = _firebarVerbPreviewPriorSelected;
    if (previewKey == null) return;
    _firebarVerbPreviewKey = null;
    _firebarVerbPreviewPriorSelected = null;
    if (keepSelection) return;
    if (selectedVerb != previewKey) return;
    selectedVerb = prior;
    if (selectedVerb == null && pinnedVerb != null) {
      selectedVerb = pinnedVerb;
    }
  }

  List<FirebarResult>? _singleFirebarPreviewMatch() {
    final matches = [...firebarHomeResults, ...firebarAwayResults];
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches;

    final query = _normalizedFirebarQuery;
    final compound = _parseFirebarJerseyVerbCompound(query);
    if (compound != null) {
      // `88 skates` with home+away #88 — preview the highlighted player so
      // the caption starts writing; ↑↓ swaps sides.
      return _preferredFirebarPlayerPreview(matches);
    }

    final jerseyMatch = _firebarJerseyTokenPattern.firstMatch(query);
    if (jerseyMatch == null) return null;
    final jersey = jerseyMatch.group(2)!;
    final exactMatches = matches
        .where((match) => (match.player!.jerseyNumber ?? '').trim() == jersey)
        .toList();
    // Prefix hits like `4` → #4 and #40 stay unresolved until unique.
    if (exactMatches.isEmpty || exactMatches.length != matches.length) {
      return null;
    }
    return _preferredFirebarPlayerPreview(exactMatches);
  }

  List<FirebarResult> _preferredFirebarPlayerPreview(
    List<FirebarResult> matches,
  ) {
    final highlighted = firebarSelectedResult;
    if (highlighted?.kind == FirebarResultKind.player &&
        matches.any((match) => match.key == highlighted!.key)) {
      return [highlighted!];
    }
    return [matches.first];
  }

  List<FirebarResult>? _resolveFirebarJerseyPlayers(
    List<_FirebarJerseyToken> tokens,
  ) {
    final results = <FirebarResult>[];
    bool? teamBiasIsHome;

    for (final token in tokens) {
      final candidates = <FirebarResult>[];
      if (token.side != 'v') {
        for (final player in homeRoster) {
          if ((player.jerseyNumber ?? '').trim() == token.jersey) {
            candidates.add(FirebarResult.player(player: player, isHome: true));
          }
        }
      }
      if (token.side != 'h') {
        for (final player in awayRoster) {
          if ((player.jerseyNumber ?? '').trim() == token.jersey) {
            candidates.add(
              FirebarResult.player(player: player, isHome: false),
            );
          }
        }
      }
      if (candidates.isEmpty) return null;

      FirebarResult? chosen;
      if (candidates.length == 1) {
        chosen = candidates.first;
      } else if (teamBiasIsHome != null) {
        final preferred = candidates
            .where((candidate) => candidate.isHome == teamBiasIsHome)
            .toList();
        if (preferred.length == 1) chosen = preferred.first;
      } else if (selectedPlayers.isNotEmpty) {
        final subjectIsHome = selectedPlayers.first.isHome;
        final preferred = candidates
            .where((candidate) => candidate.isHome == subjectIsHome)
            .toList();
        if (preferred.length == 1) chosen = preferred.first;
      }

      chosen ??= candidates.first;
      results.add(chosen);
      teamBiasIsHome ??= chosen.isHome;
    }
    return results;
  }

  void _clearFirebarAutoPlayerPreview() {
    if (_firebarAutoPreviewKeys.isEmpty) return;
    final keys = Set<String>.from(_firebarAutoPreviewKeys);
    _firebarAutoPreviewKeys.clear();
    selectedPlayers.removeWhere((row) {
      final candidate = FirebarResult.player(
        player: row.player,
        isHome: row.isHome,
      );
      return keys.contains(candidate.key);
    });
    _syncPrimaryPlayer();
    _syncPersonality();
    _syncKeywords();
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
      celebrationType = null;
      rbi = 0;
      selectedBase = null;
      _clearFirebarOptions();
      if (pinnedVerb != null && pinnedVerb != result.verbKey) {
        // Cleared a one-frame override — restore the pinned verb for this frame.
        selectedVerb = pinnedVerb;
        if (!_firebarCommitted.any((item) => item.verbKey == pinnedVerb)) {
          _firebarCommitted.add(FirebarResult.verb(pinnedVerb));
        }
      } else {
        // Cleared this frame's verb (including the pinned chip) — pin stays
        // for the next frame via [_clearCaptionSelection].
        selectedVerb = null;
      }
    } else if (result.kind == FirebarResultKind.verb &&
        verbDefinition(result.verbKey ?? '') == null &&
        customVerbPhrase.trim() == (result.verbKey ?? '').trim()) {
      customVerbPhrase = '';
      customVerbPinned = false;
      if (pinnedVerb != null) selectedVerb = pinnedVerb;
    }
    if (_firebarCommitted.isEmpty) {
      captionSelectionStarted = false;
      manualCaptionOverride = null;
    }
    _syncKeywords();
    firebarSelectionIndex =
        searchQuery.trim().isEmpty || firebarOrderedResults.isEmpty
            ? -1
            : firebarSelectionIndex.clamp(0, firebarOrderedResults.length - 1);
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
      _prepareFirebarDestinationOptions();
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

  void _prepareFirebarDestinationOptions() {
    firebarOptionPrompt = ftpModeEnabled ? 'Save or FTP?' : 'Save?';
    _firebarOptionKind = FirebarOptionKind.destination;
    firebarOptions = ftpModeEnabled
        ? const [
            FirebarOption('Save', transmit: false),
            FirebarOption('FTP', transmit: true),
          ]
        : const [
            FirebarOption('Save', transmit: false),
          ];
    firebarOptionIndex = 0;
  }

  void chooseFirebarOption(FirebarOption option) {
    final kind = _firebarOptionKind;
    if (kind == null) return;

    if (kind == FirebarOptionKind.destination) {
      searchQuery = '';
      _clearFirebarOptions();
      notifyListeners();
      unawaited(_finishFirebarAction(transmit: option.transmit == true));
      return;
    }

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
    } else {
      _prepareFirebarDestinationOptions();
    }
    _syncKeywords();
    notifyListeners();
  }

  Future<void> _finishFirebarAction({required bool transmit}) async {
    final handler = onSaveTransmit;
    if (handler != null) {
      await handler(transmit: transmit);
      return;
    }
    final path = currentPath;
    if (path == null) return;
    final keepFirebar = searchOpen;
    final saved = await saveCurrent();
    if (!saved) return;
    if (transmit) await transmitPath(path);
    if (currentPath == path) nextFrame(keepSearchOpen: keepFirebar);
  }

  Future<void> saveOrTransmitFromVerbMenu({required bool transmit}) async {
    await _finishFirebarAction(transmit: transmit);
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
    _stashCustomVerbIfNeeded();
    customVerbPhrase = '';
    rbi = c.rbi;
    final cat = _categoryForVerb(c.verb);
    if (cat != null) verbCategory = cat;
    notifyListeners();
  }

  String? _categoryForVerb(String verb) {
    final definition = verbDefinition(verb);
    if (definition != null) return definition.category;
    for (final e in verbsByCategory.entries) {
      if (e.key == 'Favorites') continue;
      if (e.value.contains(verb)) return e.key;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void goToIndex(int index, {bool keepSearchOpen = false}) {
    if (imagePaths.isEmpty) return;
    currentIndex = index.clamp(0, imagePaths.length - 1);
    _clearCaptionSelection();
    searchQuery = '';
    // Stay in Firebar after Save → next so the user can keep typing.
    // Manual navigation (arrows / thumbnails) still closes it.
    if (!keepSearchOpen) {
      searchOpen = false;
    }
    guidedSearchPrompt = null;
    _guidedSearchHits = const [];
    _pendingCommandInning = null;
    mlbTimestampMatchedPath = null;
    mlbTimestampLoading = false;
    _mlbTimestampToken++;
    notifyListeners();
    unawaited(_refreshFrameIptc());
  }

  void nextFrame({bool keepSearchOpen = false}) =>
      goToIndex(currentIndex + 1, keepSearchOpen: keepSearchOpen);
  void prevFrame({bool keepSearchOpen = false}) =>
      goToIndex(currentIndex - 1, keepSearchOpen: keepSearchOpen);

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

  /// Photographer the caption byline should use for [path], read from that
  /// file's IPTC. A pasted caption calls this per photo so two shooters of the
  /// same moment are not credited with the source name.
  Future<String> photographerNameForPath(String path) async {
    final metadata = await IptcTemplateImportService.readMetadata(path);
    if (metadata == null) {
      return path == currentPath ? photographerName : '';
    }
    return photographerNameFromMetadata(metadata);
  }

  static String photographerNameFromMetadata(Map<dynamic, dynamic> raw) {
    return _stringFromMeta(raw['Creator']) ??
        _stringFromMeta(raw['Artist']) ??
        _stringFromMeta(raw['Photographer']) ??
        _stringFromMeta(raw['IPTC:Photographer']) ??
        _stringFromMeta(raw['XMP:Photographer']) ??
        _stringFromMeta(raw['IPTC:By-line']) ??
        _stringFromMeta(raw['By-line']) ??
        _stringFromMeta(raw['Byline']) ??
        _stringFromMeta(raw['XMP:Creator']) ??
        '';
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
      photographerName = photographerNameFromMetadata(raw);
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
      headline: headline,
      keywords: keywords,
      photographerName: photographerName,
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
    final keepFirebar = searchOpen;
    final result = await savePaths([path]);
    if (result.anySucceeded && advance) {
      nextFrame(keepSearchOpen: keepFirebar);
    }
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
        (!hasVerbSelection || pinDefersCaptionUntilPlayer) &&
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
        unawaited(FloCaptionMark.markSaved(succeeded));
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
      // Drop unpinned custom verbs after a successful save so the next frame
      // starts clean (pinned custom verbs intentionally survive).
      if (!customVerbPinned && customVerbPhrase.isNotEmpty) {
        customVerbPhrase = '';
      }
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

  void advancePastHandledChain(
    List<String> chain, {
    bool keepSearchOpen = false,
  }) {
    if (imagePaths.isEmpty || chain.isEmpty) return;
    var lastIndex = -1;
    for (final path in chain) {
      final index = imagePaths.indexOf(path);
      if (index > lastIndex) lastIndex = index;
    }
    if (lastIndex < 0) return;
    goToIndex(
      (lastIndex + 1).clamp(0, imagePaths.length - 1),
      keepSearchOpen: keepSearchOpen,
    );
  }

  /// After saving a subset of a burst, land on the first frame in [chain]
  /// that was not among [savedPaths]. If every frame was saved (or none of
  /// the unsaved frames remain in the folder), advance past the chain.
  void advanceAfterBurstSelection({
    required List<String> chain,
    required Iterable<String> savedPaths,
    bool keepSearchOpen = false,
  }) {
    final saved = savedPaths.toSet();
    for (final path in chain) {
      if (saved.contains(path)) continue;
      final index = imagePaths.indexOf(path);
      if (index >= 0) {
        goToIndex(index, keepSearchOpen: keepSearchOpen);
        return;
      }
    }
    advancePastHandledChain(chain, keepSearchOpen: keepSearchOpen);
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
    selectedPlayers.clear();
    selectedPlayer = null;
    playerSearchClearGeneration++;
    // Pinned catalog verb always comes back on the next frame, even if the
    // user picked a different verb for the frame they just saved.
    if (pinnedVerb != null) {
      selectedVerb = pinnedVerb;
      if (!customVerbPinned) {
        customVerbPhrase = '';
      }
    } else if (customVerbPinned && lastCustomVerbPhrase.isNotEmpty) {
      customVerbPhrase = lastCustomVerbPhrase;
      selectedVerb = null;
    } else {
      selectedVerb = null;
      customVerbPhrase = '';
    }
    celebrationType = null;
    personality = '';
    manualCaptionOverride = null;
    rbi = 0;
    selectedBase = null;
    // Pinned player always comes back on the next frame, even if the user
    // picked a different player for the frame they just saved.
    pinnedPlayer = _resolvePinnedPlayer();
    if (pinnedPlayer != null) {
      selectedPlayers.add(pinnedPlayer!);
      _syncPrimaryPlayer();
    }
    // Pinned verb alone waits for a player; a pinned player starts the caption.
    captionSelectionStarted = selectedPlayers.isNotEmpty;
    _firebarCommitted
        .removeWhere((item) => item.kind == FirebarResultKind.player);
    if (pinnedPlayer != null) {
      final playerChip = FirebarResult.player(
        player: pinnedPlayer!.player,
        isHome: pinnedPlayer!.isHome,
      );
      if (!_firebarCommitted.any((item) => item.key == playerChip.key)) {
        _firebarCommitted.add(playerChip);
      }
    }
    if (pinnedVerb != null) {
      _firebarCommitted
          .removeWhere((item) => item.kind == FirebarResultKind.verb);
      if (!_firebarCommitted.any((item) => item.verbKey == pinnedVerb)) {
        _firebarCommitted.add(FirebarResult.verb(pinnedVerb));
      }
      // A pinned favorite always comes back on the Favorites panel, even if
      // the user was browsing another category when they saved.
      if (isVerbFavorite(pinnedVerb!)) {
        verbCategory = 'Favorites';
      } else {
        final category = _categoryForVerb(pinnedVerb!);
        if (category != null) verbCategory = category;
      }
    } else if (customVerbPinned && customVerbPhrase.trim().isNotEmpty) {
      _firebarCommitted
          .removeWhere((item) => item.kind == FirebarResultKind.verb);
    } else {
      _firebarCommitted
          .removeWhere((item) => item.kind == FirebarResultKind.verb);
    }
    _clearFirebarOptions();
    _syncKeywords();
  }

  Future<void> enterComboSaveAdvance() async {
    applyLastUsed();
    await saveAndNext();
  }

  Future<void> transmitQueued() async {
    if (!ftpModeEnabled) {
      statusMessage = 'FTP mode is off';
      notifyListeners();
      return;
    }
    final toSend =
        imagePaths.where((p) => frameStateFor(p) == FrameState.saved).toList();
    if (toSend.isEmpty) {
      // Button / shortcut often fire with nothing pre-queued — save+send current.
      await transmitCurrent();
      return;
    }
    await _transmitPaths(toSend);
  }

  Future<void> transmitCurrent() async {
    if (!ftpModeEnabled) {
      statusMessage = 'FTP mode is off';
      notifyListeners();
      return;
    }
    final path = currentPath;
    if (path == null) {
      statusMessage = 'No image to FTP';
      notifyListeners();
      return;
    }
    // Ensure saved first.
    if (frameStateFor(path) == FrameState.todo) {
      final ok = await saveCurrent();
      if (!ok) return;
    }
    await _transmitPaths([path]);
  }

  Future<void> _transmitPaths(List<String> paths) async {
    if (!ftpModeEnabled) {
      statusMessage = 'FTP mode is off';
      notifyListeners();
      return;
    }
    if (paths.isEmpty) {
      statusMessage = 'Nothing to FTP';
      notifyListeners();
      return;
    }
    if (transmitting) {
      statusMessage = 'FTP already in progress';
      notifyListeners();
      return;
    }

    final alreadySent =
        paths.where((path) => sentImages.contains(path)).toList();
    var toSend = paths.where((path) => !sentImages.contains(path)).toList();
    if (alreadySent.isNotEmpty) {
      final allow = await confirmRetransmit?.call(alreadySent) ?? true;
      if (allow) toSend = [...toSend, ...alreadySent];
    }
    if (toSend.isEmpty) return;

    transmitting = true;
    transmitProgress = 0;
    transmitStatus = 'Connecting…';
    transmittingPath = toSend.first;
    queuedCount = toSend.length;
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) {
      sentImages.addAll(toSend);
      savedImages.addAll(toSend);
      lastSentLabel = _formatTime(DateTime.now());
      queuedCount = 0;
      transmitting = false;
      transmittingPath = null;
      transmitStatus = null;
      transmitProgress = 0;
      statusMessage = 'Marked sent (prefs unavailable)';
      notifyListeners();
      return;
    }

    final profileName = await prefs.getCurrentFtpProfile();
    final profiles = await prefs.getFtpProfiles();
    final profile = profileName == null ? null : profiles[profileName];

    if (profile == null) {
      transmitting = false;
      transmittingPath = null;
      transmitStatus = null;
      transmitProgress = 0;
      queuedCount = savedNotSentCount;
      statusMessage = 'Configure an FTP profile first (Settings → FTP)';
      notifyListeners();
      return;
    }

    final host = profile['host']?.toString() ?? '';
    final user = profile['username']?.toString() ?? '';
    final pass = profile['password']?.toString() ?? '';
    final port = int.tryParse(profile['port']?.toString() ?? '') ?? 21;
    final remoteDir = profile['remotePath']?.toString() ?? '/';
    final passive = profile['passiveMode'] != false;

    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      transmitting = false;
      transmittingPath = null;
      transmitStatus = null;
      transmitProgress = 0;
      statusMessage = 'FTP profile is incomplete';
      notifyListeners();
      return;
    }

    var ok = 0;
    String? lastError;
    for (var i = 0; i < toSend.length; i++) {
      final path = toSend[i];
      transmittingPath = path;
      transmitProgress = 0;
      transmitStatus = toSend.length > 1
          ? 'Uploading ${i + 1}/${toSend.length}…'
          : 'Uploading…';
      notifyListeners();

      final remote = remoteDir.endsWith('/')
          ? '$remoteDir${p.basename(path)}'
          : '$remoteDir/${p.basename(path)}';
      final result = await FtpClientService.uploadFile(
        host: host,
        username: user,
        password: pass,
        localFilePath: path,
        remoteFilePath: remote,
        port: port,
        passiveMode: passive,
        onProgress: (status, progress, error) {
          final next = progress.clamp(0.0, 1.0);
          final bumped = (next - transmitProgress).abs() >= 0.02 ||
              status != transmitStatus ||
              error != null;
          transmitStatus = status;
          transmitProgress = next;
          if (error != null && error.isNotEmpty) lastError = error;
          if (bumped) notifyListeners();
        },
      );
      if (result.success) {
        ok++;
        sentImages.add(path);
        savedImages.add(path);
      } else {
        lastError = result.details ?? result.error ?? 'Upload failed';
      }
      await _recordFtpHistory(
        FtpHistoryEntry(
          at: DateTime.now(),
          fileName: p.basename(path),
          path: path,
          profile: profileName ?? '',
          success: result.success,
          error: result.success ? null : lastError,
        ),
      );
    }

    lastSentLabel = _formatTime(DateTime.now());
    queuedCount = savedNotSentCount;
    transmitting = false;
    transmittingPath = null;
    transmitProgress = 0;
    transmitStatus = null;
    if (ok == toSend.length) {
      statusMessage =
          toSend.length == 1 ? 'FTP complete' : 'Sent $ok / ${toSend.length}';
    } else if (ok == 0) {
      statusMessage =
          lastError == null ? 'FTP failed' : 'FTP failed: $lastError';
    } else {
      statusMessage = 'Sent $ok / ${toSend.length}'
          '${lastError == null ? '' : ' — $lastError'}';
    }
    notifyListeners();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  static const _ftpHistoryKey = 'caption_v2_ftp_history';

  Future<void> _loadFtpHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ftpHistoryKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      ftpHistory
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map(
                (item) => FtpHistoryEntry.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              ),
        );
    } catch (_) {}
  }

  Future<void> _recordFtpHistory(FtpHistoryEntry entry) async {
    ftpHistory.insert(0, entry);
    if (ftpHistory.length > 80) {
      ftpHistory.removeRange(80, ftpHistory.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _ftpHistoryKey,
      jsonEncode(ftpHistory.map((item) => item.toJson()).toList()),
    );
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
      'look': 'Looks On',
      'looks': 'Looks On',
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
    _stashCustomVerbIfNeeded();
    customVerbPhrase = '';
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

  void _finishCommand(
      {int? rbiValue, String? baseValue, String? verbOverride}) {
    if (verbOverride != null) {
      selectedVerb = verbOverride;
      _stashCustomVerbIfNeeded();
      customVerbPhrase = '';
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
    guidedSearchPrompt = 'What $timingUnitNoun?';
    final isBaseball = sport.toLowerCase() == 'baseball';
    final isBasketball = supportsTimingHalves;
    final regulationEnd = timingRegulationCount;
    _guidedSearchHits = [
      SearchHit(
        kind: 'option',
        label: 'Pre',
        aliases: const ['pre', 'pregame', 'before'],
        apply: () => _completeCommandTiming(pre: true),
      ),
      if (isBasketball) ...[
        for (var value = 1; value <= regulationEnd; value++)
          SearchHit(
            kind: 'option',
            label: 'Q$value',
            aliases: [
              '$value',
              'q$value',
              'Q$value',
              _ordinal(value),
              _ordinalWord(value),
              'quarter $value',
            ],
            apply: () => _completeCommandTiming(inningValue: value),
          ),
        SearchHit(
          kind: 'option',
          label: '1H',
          aliases: const ['1h', 'first half', '1st half', 'half 1'],
          apply: () => _completeCommandTiming(half: '1H'),
        ),
        SearchHit(
          kind: 'option',
          label: '2H',
          aliases: const ['2h', 'second half', '2nd half', 'half 2'],
          apply: () => _completeCommandTiming(half: '2H'),
        ),
        SearchHit(
          kind: 'option',
          label: 'OT',
          aliases: const ['ot', 'overtime', 'extra', 'extras'],
          apply: () =>
              _completeCommandTiming(inningValue: timingRegulationCount + 1),
        ),
      ] else ...[
        for (var value = 1;
            value <= (isBaseball ? timingMaxInning : regulationEnd);
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
            label: sport.toLowerCase() == 'soccer' ? 'ET' : 'OT',
            aliases: sport.toLowerCase() == 'soccer'
                ? const ['et', 'extra', 'extras', 'extra time']
                : const ['ot', 'overtime', 'extra', 'extras'],
            apply: () =>
                _completeCommandTiming(inningValue: timingRegulationCount + 1),
          ),
      ],
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
    timingHalf = null;
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
    String? half,
    bool pre = false,
    bool post = false,
  }) {
    if (half != null) {
      timingHalf = half;
      inning = half == '1H' ? 1 : 2;
    } else if (inningValue != null) {
      inning = inningValue;
      timingHalf = null;
    }
    preGame = pre;
    postGame = post;
    if (pre || post) timingHalf = null;
    statusMessage = selectedPlayer == null || selectedVerb == null
        ? null
        : '$playerChipLabel · ${_verbChip(selectedVerb!)}';
    _promptForCommandDestination();
  }

  void _promptForCommandDestination() {
    if (!ftpModeEnabled) {
      unawaited(_finishCommandAction(transmit: false));
      return;
    }
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
    final keepFirebar = searchOpen;
    notifyListeners();
    if (path == null) return;

    final saved = await saveCurrent();
    if (!saved) return;
    if (transmit) await transmitPath(path);
    if (currentPath == path) nextFrame(keepSearchOpen: keepFirebar);
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
        final byFirst =
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
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
    _folderWatchGeneration++;
    _stopFolderWatch();
    _prefs?.captionFieldVisibilityRevision.removeListener(
      _onCaptionFieldVisibilityChanged,
    );
    super.dispose();
  }
}
