import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../caption_style/caption_formula_renderer.dart';
import '../../../caption_style/caption_session_context.dart';
import '../../../caption_style/caption_style_catalog.dart';
import '../../../caption_style/getty_note_variant.dart';
import '../../../caption_style/caption_template.dart';
import '../../../caption_style/caption_text_normalize.dart';
import '../../../caption_style/game_info.dart';
import '../../../caption_style/sport_verb_categories.dart';
import '../../../caption_style/verb_authoring_model.dart';
import '../../../caption_style/verb_category_colors.dart';
import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_sort_mode.dart';
import '../../../caption_style/verb_sub_options.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/api_manager.dart';
import '../../../services/ftp_complete_sound.dart';
import '../../../services/ftpclient_service.dart';
import '../../../services/flo_caption_mark.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/jersey_ocr_channel.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/mlb_inning_feature_gate.dart';
import '../../../services/mlb_inning_from_timestamp_service.dart';
import '../../../services/preferences_service.dart';
import '../../../services/roster_history_service.dart';
import '../../../services/camera_serial_service.dart';
import '../../../services/admin_service.dart';
import '../../../config/tank01_config.dart';
import '../../../utils/exiftool_helper.dart';
import '../../../utils/default_verb_keywords.dart';
import '../../../utils/image_file_ready.dart';
import '../../../utils/native_file_picker.dart';
import '../../../utils/oriented_image_bytes.dart';
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

/// How a player was added to the caption selection.
enum PlayerInputSource {
  /// Clicked in roster / drum / jersey keypad / search.
  user,

  /// Chosen from on-photo text recognition (OCR).
  textRecognition,

  /// Typed as a custom name.
  typed,
}

class RosterHit {
  const RosterHit({
    required this.player,
    required this.isHome,
    this.source = PlayerInputSource.user,
    this.recognitionDetail,
  });

  final Player player;
  final bool isHome;
  final PlayerInputSource source;

  /// Extra OCR detail for tips, e.g. `Jersey #44` or `Name "Matthews"`.
  final String? recognitionDetail;

  RosterHit copyWith({
    Player? player,
    bool? isHome,
    PlayerInputSource? source,
    String? recognitionDetail,
    bool clearRecognitionDetail = false,
  }) =>
      RosterHit(
        player: player ?? this.player,
        isHome: isHome ?? this.isHome,
        source: source ?? this.source,
        recognitionDetail: clearRecognitionDetail
            ? null
            : (recognitionDetail ?? this.recognitionDetail),
      );
}

/// A caption substring with a hover tip explaining where it came from.
class CaptionProvenanceSpan {
  const CaptionProvenanceSpan({
    required this.phrase,
    required this.tip,
    this.background,
  });

  final String phrase;
  final String tip;

  /// Soft fill behind the phrase. Used for inserted verbs.
  final Color? background;
}

enum _BylineProvenance { none, iptc, serial, serialAssigned }

class _FrameSerialScan {
  const _FrameSerialScan({
    required this.serial,
    required this.hasCreator,
    this.body = '',
  });

  final String serial;
  final bool hasCreator;
  final String body;
}

class _SerialPrompt {
  const _SerialPrompt({required this.serial, this.imagePath, this.body = ''});

  final String serial;
  final String? imagePath;
  final String body;
}

/// How an OCR token matched a roster player.
enum JerseyOcrMatchKind { jersey, name }

/// Roster player matched from on-device OCR on the current frame.
class JerseyOcrSuggestion {
  const JerseyOcrSuggestion({
    required this.player,
    required this.isHome,
    required this.confidence,
    required this.matchedText,
    required this.matchKind,
    this.box,
    this.jerseyTone,
    this.region,
    this.confirmed = false,
  });

  final Player player;
  final bool isHome;
  final double confidence;

  /// Raw OCR token that produced this match.
  final String matchedText;
  final JerseyOcrMatchKind matchKind;

  /// Vision-normalized box of [matchedText] (origin bottom-left).
  final JerseyOcrRegion? box;

  /// Fabric tone under the read (`dark` / `light`), when Vision sampled it.
  final String? jerseyTone;

  /// `torso` / `sleeve` / `helmet` / `body` / `loupe`.
  final String? region;

  /// Both the number and the name were read and agree on this player.
  final bool confirmed;

  String get jersey => (player.jerseyNumber ?? '').trim();

  JerseyOcrSuggestion copyWith({double? confidence, bool? confirmed}) =>
      JerseyOcrSuggestion(
        player: player,
        isHome: isHome,
        confidence: confidence ?? this.confidence,
        matchedText: matchedText,
        matchKind: matchKind,
        box: box,
        jerseyTone: jerseyTone,
        region: region,
        confirmed: confirmed ?? this.confirmed,
      );
}

/// A roster pick the user confirmed on a recent frame — players on the ice
/// together in one shift tend to be in the next frame too.
class _RecentPick {
  const _RecentPick({
    required this.playerKey,
    required this.isHome,
    required this.capturedAt,
    required this.frameIndex,
  });

  final String playerKey;
  final bool isHome;
  final DateTime? capturedAt;
  final int frameIndex;
}

/// Result of a manual OCR test scan on the current frame.
class OcrScanResult {
  const OcrScanResult({
    required this.supported,
    required this.hits,
    required this.matches,
  });

  final bool supported;
  final List<JerseyOcrHit> hits;
  final List<JerseyOcrSuggestion> matches;
}

enum FirebarResultKind { player, verb }

enum FirebarOptionKind {
  homeRun,
  rbi,
  celebration,
  base,
  destination,
  jerseySide,
}

enum RosterSortMode { number, firstName, lastName }

/// Whole-side caption subject on the Other row.
enum TeamSubjectKind { players, name, teammates }

class FirebarOption {
  const FirebarOption(
    this.label, {
    this.rbi,
    this.verbOverride,
    this.celebration,
    this.base,
    this.transmit,
    this.jerseyIsHome,
  });

  final String label;
  final int? rbi;
  final String? verbOverride;
  final String? celebration;
  final String? base;

  /// Destination actions only: `false` = Save, `true` = FTP.
  final bool? transmit;

  /// Jersey-side prompt only: `true` = home, `false` = visitor.
  final bool? jerseyIsHome;
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

class _FirebarMenuHit {
  const _FirebarMenuHit({
    required this.result,
    required this.score,
    required this.name,
  });

  final FirebarResult result;
  final int score;
  final String name;
}

class _FirebarJerseyToken {
  const _FirebarJerseyToken({this.side, required this.jersey});

  final String? side;
  final String jersey;
}

class _PendingJerseySideQuery {
  const _PendingJerseySideQuery({
    required this.prefix,
    required this.jersey,
    required this.suffix,
  });

  /// Sided jersey tokens already typed before the ambiguous number.
  final String prefix;

  final String jersey;

  /// Verb text or later jersey tokens after the ambiguous number.
  final String suffix;
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
class _FtpSendJob {
  const _FtpSendJob({
    required this.path,
    required this.host,
    required this.username,
    required this.password,
    required this.port,
    required this.remoteDir,
    required this.passive,
    required this.renameAs,
    required this.duplicateFolder,
    required this.profileName,
  });

  final String path;
  final String host;
  final String username;
  final String password;
  final int port;
  final String remoteDir;
  final bool passive;
  final String renameAs;
  final String duplicateFolder;
  final String profileName;
}

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

  /// Bumps on each editor preview so a disk reload cannot paint over a newer save.
  int _verbPreviewToken = 0;
  VerbSortMode verbSortMode = VerbSortMode.alphabetical;

  /// How many verb categories can stay open at once.
  /// 0 is none, [verbCascadeAll] is every category.
  int verbCascadeLimit = 1;

  static const int verbCascadeNone = 0;
  static const int verbCascadeAll = 99;

  bool get verbMultiOpen => verbCascadeLimit > 1;

  int cascadeLimitFor(int categoryCount) {
    final max = categoryCount < 1 ? 1 : categoryCount;
    if (verbCascadeLimit <= verbCascadeNone) return 0;
    if (verbCascadeLimit >= verbCascadeAll) return max;
    return verbCascadeLimit > max ? max : verbCascadeLimit;
  }

  /// Steps from the default verb-menu type size. Each step is 10%.
  /// Range is 80%–140% (default 100%).
  int verbFontStep = 0;

  /// False keeps categories. True lists every verb once, A–Z.
  bool verbListAll = false;

  static const int verbFontStepMin = -2;
  static const int verbFontStepMax = 4;

  double get verbFontScale => 1 + verbFontStep * 0.10;
  Map<String, int> _verbUsageCounts = {};

  // --- Game / teams ---
  String homeTeam = '';
  String awayTeam = '';

  /// Session has one roster only ([homeTeam]); captions omit opponent clauses.
  bool singleTeamMode = false;

  /// True when captions can name an opposing team for the current subjects.
  bool get hasOpponentTeam {
    if (singleTeamMode) return false;
    final subjects = subjectPlayers;
    final subjectIsHome =
        subjects.isEmpty ? selectedIsHome : subjects.first.isHome;
    final opponent = subjectIsHome ? awayTeam : homeTeam;
    return opponent.trim().isNotEmpty;
  }

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

  /// Longest-side pixel threshold for the low-resolution warning. `0` is off.
  int resolutionWarningThreshold = 3000;
  bool metadataDirty = false;
  final Set<String> _basePersonalityNames = {};
  final Set<String> _managedKeywordKeys = {};
  final Set<String> _baseKeywordKeys = {};
  int _iptcLoadGen = 0;

  /// How [photographerName] was resolved for the current frame (hover tips).
  _BylineProvenance _photographerProvenance = _BylineProvenance.none;
  String? _photographerSerialUsed;

  /// When serial bylines is on and a camera serial is not in the app yet,
  /// set to that EXIF serial (or '' if the file has none) so the UI can prompt.
  /// One prompt per distinct serial; the head of [_serialBylinesQueue].
  String? pendingSerialBylinesPrompt;

  /// Photo the current prompt's serial was read from.
  String? get pendingSerialBylinesImagePath => _serialBylinesQueue.isEmpty
      ? null
      : _serialBylinesQueue.first.imagePath;

  /// Camera body (make/model) read from the same EXIF as the pending serial.
  String? get pendingSerialBylinesBody {
    if (_serialBylinesQueue.isEmpty) return null;
    final body = _serialBylinesQueue.first.body.trim();
    return body.isEmpty ? null : body;
  }

  final List<_SerialPrompt> _serialBylinesQueue = [];
  final Set<String> _serialBylinesHandled = {};
  final Set<String> _serialBylinesPromptDismissed = {};
  Completer<void>? _serialBylinesGate;

  /// Skip the prompt UI while the session is still scanning the folder, then
  /// ask once for every unmapped serial before [sessionReady].
  bool _deferSerialBylinesUi = false;

  /// Folder had no pictures at session start, so each file is checked as it
  /// lands instead of in the pre-session scan.
  bool _scanSerialsOnArrival = false;

  /// Active caption style from prefs (Getty / Imagn / AP / …).
  CaptionTemplate captionTemplate = CaptionTemplate.getty();

  /// Getty note to user includes the NBAE copyright line.
  bool gettyNoteIsNbae = false;
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

  /// When set, the caption subject is the whole side instead of named athletes.
  bool? teamPlayersIsHome;

  /// Players, the team name, or teammates.
  TeamSubjectKind teamSubjectKind = TeamSubjectKind.players;

  /// Teammates is an extra pick on this side: the selected player stays the
  /// subject and the caption gains a trailing "with teammates".
  bool? withTeammatesIsHome;
  String? selectedVerb;
  final Map<String, String?> verbModifierSelections = {};

  String customVerbPhrase = '';
  String lastCustomVerbPhrase = '';
  bool customVerbPinned = false;
  String lastCustomPlayerName = '';
  String lastCustomPlayerJersey = '';
  bool captionSelectionStarted = false;
  String? celebrationType;
  String? pinnedVerb;
  RosterHit? pinnedPlayer;
  String? verbCategory = 'Offense';
  String personality = '';
  String? manualCaptionOverride;
  CaptionTransferPayload? previousCaption;

  /// Button clicks that built a caption, kept per picture so opening that
  /// picture, copy, and paste press the same buttons again.
  final Map<String, CaptionClickSnapshot> _clicksByPath = {};

  /// Pictures that should press their saved clicks when that frame is opened.
  final Set<String> _restoreClicksOnOpen = {};
  int rbi = 0;

  /// Running-verb base: `1B`, `2B`, `3B`, `Home`, or null.
  String? selectedBase;
  int inning = 2;
  bool preGame = false;
  bool postGame = false;

  /// True when this game offered a game-date roster that differs from today.
  bool rosterHistoryCanSwitch = false;

  /// True when the session is showing the roster from the game date.
  bool usingGameDateRoster = false;

  bool _homeRosterPasted = false;
  bool _awayRosterPasted = false;
  String? _rosterHistoryGameDate;
  bool _rosterHistoryApplied = false;

  /// Basketball/WNBA half selection (`1H` / `2H`); null = use quarter/OT via [inning].
  String? timingHalf;

  /// Basketball/WNBA period bar. True shows quarters; false shows halves.
  bool timingByQuarter = false;

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
  bool burstDetectionEnabled = false;
  bool serialBylinesEnabled = false;
  bool loadingImages = false;
  bool refreshingFolder = false;
  bool _folderScanInFlight = false;
  bool _folderScanAgain = false;
  StreamSubscription<FileSystemEvent>? _folderWatch;
  Timer? _folderIngestTimer;
  Timer? _folderPollTimer;
  int _folderWatchGeneration = 0;
  int _previewWarmGeneration = 0;
  /// Independent of [_previewWarmGeneration] so flipping frames doesn't cancel
  /// the full-folder thumb preload.
  int _thumbWarmGeneration = 0;
  String? _watchedFolder;
  final Set<String> _pendingIngest = {};
  final Map<String, int> _imageContentStamp = {};
  final Map<String, int> _fileLength = {};
  final Map<String, int> _fileModifiedMs = {};
  final Map<String, int> _fileChangedMs = {};

  /// OCR roster matches for [currentPath].
  List<JerseyOcrSuggestion> jerseySuggestions = const [];

  /// Which bench wears the dark jersey. Null → use the sport default
  /// (hockey: home dark; basketball/baseball: home light) until picks teach us.
  bool? homeWearsDarkOverride;

  /// +1 per pick that says "home is dark", −1 per pick that says "home is light".
  int _homeDarkVotes = 0;

  /// Recent confirmed picks (newest last) for shift continuity across frames.
  final List<_RecentPick> _recentPicks = [];

  /// True when the user answered the jersey-colour question at startup
  /// (even with "not sure") — then the sport default is not assumed.
  bool _homeWearsDarkAnswered = false;

  bool? get homeWearsDark {
    if (homeWearsDarkOverride != null) return homeWearsDarkOverride;
    if (_homeDarkVotes >= 2) return true;
    if (_homeDarkVotes <= -2) return false;
    if (_homeWearsDarkAnswered) return null;
    switch (sport.trim().toLowerCase()) {
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

  /// Flip which bench wears dark (retro / third jerseys). Null clears to default.
  void setHomeWearsDark(bool? value) {
    homeWearsDarkOverride = value;
    _homeWearsDarkAnswered = true;
    _homeDarkVotes = 0;
    jerseySuggestions = _matchJerseyOcrHits(jerseyOcrHits);
    notifyListeners();
  }

  /// Eyedropper swatches. Compared to the torso colour on each OCR hit so
  /// two dark kits (navy vs black) can still be told apart.
  ui.Color? homeJerseySwatch;
  ui.Color? awayJerseySwatch;

  /// Store a colour the user sampled from a jersey, and say which bench it is.
  void setJerseySwatch({required bool isHome, required ui.Color color}) {
    if (isHome) {
      homeJerseySwatch = color;
    } else {
      awayJerseySwatch = color;
    }
    final home = homeJerseySwatch;
    final away = awayJerseySwatch;
    if (home != null && away != null) {
      final homeLuma = _swatchLuma(home);
      final awayLuma = _swatchLuma(away);
      if ((homeLuma - awayLuma).abs() >= 0.08) {
        setHomeWearsDark(homeLuma < awayLuma);
        return;
      }
    } else {
      final luma = _swatchLuma(color);
      if (luma < 0.42 || luma > 0.62) {
        final dark = luma < 0.42;
        setHomeWearsDark(isHome ? dark : !dark);
        return;
      }
    }
    jerseySuggestions = _matchJerseyOcrHits(jerseyOcrHits);
    notifyListeners();
  }

  static double _swatchLuma(ui.Color color) {
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }

  /// 0 = same colour, 1 = opposite.
  static double _jerseyColorDistance(ui.Color sample, ui.Color swatch) {
    final dr = sample.r - swatch.r;
    final dg = sample.g - swatch.g;
    final db = sample.b - swatch.b;
    return (math.sqrt(dr * dr + dg * dg + db * db) / math.sqrt(3))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Raw OCR tokens from the last scan (numbers + names).
  List<JerseyOcrHit> jerseyOcrHits = const [];
  bool jerseyOcrBusy = false;
  /// Frame-scan generation; bumped on frame change / full rescan.
  int _jerseyOcrToken = 0;
  /// Loupe-scan generation; a newer loupe position cancels the older one
  /// without touching the frame scan.
  int _loupeOcrToken = 0;
  int _jerseyOcrInflight = 0;
  Timer? _jerseyOcrTimer;
  final Map<String, List<JerseyOcrHit>> _jerseyOcrCache = {};
  /// Full-frame reads keyed by path, ignoring mtime. Metadata/IPTC writes
  /// must not force another Vision pass when the user changes frames.
  final Map<String, List<JerseyOcrHit>> _jerseyOcrByPath = {};
  /// Full-frame results for every image in the session can live here, so a
  /// pre-scanned folder never evicts itself (hit lists are tiny).
  static const int _jerseyOcrCacheMax = 1200;

  /// Background pre-scan: warms the OCR cache for upcoming frames while the
  /// user works, so each frame's suggestions appear instantly.
  bool _jerseyOcrPrescanRunning = false;
  final Set<String> _jerseyOcrPrescanned = {};
  int jerseyOcrPrescanDone = 0;
  int jerseyOcrPrescanTotal = 0;
  bool get jerseyOcrPrescanActive =>
      _jerseyOcrPrescanRunning && jerseyOcrPrescanDone < jerseyOcrPrescanTotal;

  /// User pressed Stop. Holds for this session so a later kick does not resume.
  bool _jerseyOcrPrescanStop = false;

  /// Preference gate for jersey OCR (UI + auto/loupe scans).
  /// Default off until the user enables it via the header OCR toggle.
  bool jerseyOcrEnabled = false;

  /// Raw preference value for the header toggle (ignores admin/platform gate).
  bool jerseyOcrPreferenceEnabled = false;

  static const _sessionImageExtensions = {
    '.jpg',
    '.jpeg',
    '.tif',
    '.tiff',
    '.png',
  };

  /// When false, FTP buttons/shortcuts/menu items are hidden.
  bool ftpModeEnabled = true;

  /// When true, the caption Firebar search row is hidden.
  bool hideFirebar = false;

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

  /// Highlighted row in the Firebar autocomplete menu. The first row starts
  /// selected whenever the query changes.
  int firebarMenuIndex = 0;

  /// Keyboard selection among committed chips. -1 means the text field.
  int firebarChipCursor = -1;

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
  _PendingJerseySideQuery? _pendingJerseySide;

  /// True after ↑↓ moves the Home / Visitor chips, so Enter is a real choice.
  bool _jerseySideChoiceArmed = false;

  /// Screen asks before re-uploading paths already in [sentImages].
  /// Return true to upload those paths again.
  Future<bool> Function(List<String> alreadySent)? confirmRetransmit;
  bool _retransmitPromptOpen = false;

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
    final verbQuery = compound?.verbQuery ?? _firebarFocusedQuery;
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
  /// Shift+Enter can commit that match and FTP without pressing Enter first.
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

  /// Show the Shift+Enter FTP hint in the Firebar chrome.
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

  /// Phrases in [displayedCaption] with hover tips explaining where they came from.
  List<CaptionProvenanceSpan> get captionProvenanceSpans {
    final caption = displayedCaption;
    if (caption.trim().isEmpty) return const [];

    final spans = <CaptionProvenanceSpan>[];
    final seen = <String>{};

    bool phraseFits(String captionText, String phrase) {
      var from = 0;
      while (from < captionText.length) {
        final index = captionText.indexOf(phrase, from);
        if (index < 0) return false;
        // Short tokens (state codes, etc.) need word edges so "ON" ≠ "Toronto".
        if (phrase.length > 3) return true;
        final beforeOk = index == 0 ||
            !RegExp(r'[A-Za-z0-9]').hasMatch(captionText[index - 1]);
        final after = index + phrase.length;
        final afterOk = after >= captionText.length ||
            !RegExp(r'[A-Za-z0-9]').hasMatch(captionText[after]);
        if (beforeOk && afterOk) return true;
        from = index + phrase.length;
      }
      return false;
    }

    void add(String raw, String tip, {Color? background}) {
      final base = raw.trim();
      if (base.isEmpty) return;
      for (final phrase in <String>[base, base.toUpperCase()]) {
        if (phrase.isEmpty || seen.contains(phrase)) continue;
        if (!phraseFits(caption, phrase)) continue;
        seen.add(phrase);
        spans.add(CaptionProvenanceSpan(
          phrase: phrase,
          tip: tip,
          background: background,
        ));
        return;
      }
    }

    final photographer = photographerName.trim();
    if (photographer.isNotEmpty) {
      add(photographer, _photographerProvenanceTip);
    }

    final agency = agencyName.trim();
    if (agency.isNotEmpty) {
      final fromIptc = (currentIptcMeta['IPTC:Credit'] ??
              currentIptcMeta['Credit'] ??
              '')
          .trim()
          .isNotEmpty;
      add(
        agency,
        fromIptc ? 'Photo IPTC · Credit' : 'Caption style · Agency',
      );
    }

    final game = currentGameInfoForCaption();
    if (game.city.trim().isNotEmpty) {
      add(
        game.city,
        city.trim().isNotEmpty ? 'Session · City' : 'Photo IPTC · City',
      );
    }
    if (game.region.trim().isNotEmpty) {
      add(
        game.region,
        region.trim().isNotEmpty
            ? 'Session · Province/State'
            : 'Photo IPTC · Province/State',
      );
      final short = game.resolvedRegionShort.trim();
      if (short.isNotEmpty && short != game.region.trim()) {
        add(
          short,
          region.trim().isNotEmpty
              ? 'Session · Province/State'
              : 'Photo IPTC · Province/State',
        );
      }
    }
    if (game.venue.trim().isNotEmpty) {
      add(
        game.venue,
        venue.trim().isNotEmpty ? 'Session · Stadium' : 'Photo IPTC · Stadium',
      );
    }

    final path = currentPath;
    final hasExifDate = path != null && captureByPath[path] != null;
    final dateLine = CaptionFormulaRenderer.formatTemplateDateLine(
      game,
      captionTemplate,
      uppercaseAll: captionTemplate.wireStyle == WireStyle.getty ||
          captionTemplate.wireStyle == WireStyle.gettyInternational,
    ).trim();
    if (dateLine.isNotEmpty && dateLine != '—') {
      add(
        dateLine,
        hasExifDate ? 'Photo EXIF · Date' : 'Session · Date',
      );
    }

    final nameFill =
        manualCaptionOverride == null ? captionPlayerHighlight : null;
    // One span for the whole subject clause ("Name #29 of the Team"), so the
    // fill is continuous through the jersey and "of the" instead of stopping
    // after the name.
    if (nameFill != null && hasCaptionSubject) {
      final lead = (hasTeamPlayersSubject
              ? _teamPlayersLead(captionTemplate)
              : _playerLead(captionTemplate))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final subjectTip = subjectPlayers
          .map(_playerProvenanceTip)
          .toSet()
          .join('\n');
      add(
        lead,
        subjectTip.isEmpty ? 'Session · Team' : subjectTip,
        background: nameFill,
      );
      if (opposingPlayers.isNotEmpty) {
        final opponents =
            _formatPlayersWithTeam(opposingPlayers, captionTemplate)
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
        final opponentTip = opposingPlayers
            .map(_playerProvenanceTip)
            .toSet()
            .join('\n');
        add(opponents, opponentTip, background: nameFill);
      }
    }
    for (final row in selectedPlayers) {
      var name = row.player.fullName.trim();
      if (name.isEmpty) continue;
      if (captionTemplate.removeDiacritics) {
        name = CaptionTextNormalize.stripDiacritics(name);
      }
      add(name, _playerProvenanceTip(row), background: nameFill);
      final jersey = row.player.jerseyNumber?.trim() ?? '';
      if (jersey.isNotEmpty) {
        final numText = captionTemplate.numberFormat == NumberFormatStyle.hash
            ? '#$jersey'
            : '($jersey)';
        add(numText, _playerProvenanceTip(row), background: nameFill);
      }
    }

    final verbFill =
        manualCaptionOverride == null ? captionVerbHighlight : null;
    if (customVerbPhrase.trim().isNotEmpty) {
      add(
        customVerbPhrase,
        'Verb · Custom text',
        background: verbFill,
      );
    } else {
      final verb = selectedVerb;
      if (verb != null) {
        final def = verbDefinition(verb);
        final category = def?.category.trim() ?? '';
        final label = def?.label ?? verb;
        final tip = category.isEmpty
            ? 'Verb · $label'
            : 'Verb · $category · $label';
        final fill = verbFill;
        add(def?.singularPhrase ?? '', tip, background: fill);
        add(def?.pluralPhrase ?? '', tip, background: fill);
        add(def?.ingPhrase ?? '', tip, background: fill);
        add(label, tip, background: fill);
      }
    }

    void addTeam(String raw, String tip) {
      var team = raw.trim();
      if (team.isEmpty) return;
      if (captionTemplate.removeDiacritics) {
        team = CaptionTextNormalize.stripDiacritics(team);
      }
      add(team, tip, background: nameFill);
    }

    addTeam(homeTeam, 'Session · Home team');
    addTeam(awayTeam, 'Session · Away team');

    return spans;
  }

  /// Tip for caption text that did not match a known player, verb, or field.
  String get captionUnmatchedTip {
    if (manualCaptionOverride != null) return 'Typed in the caption box';
    if (!hasCaptionSubject) return 'Photo · Existing caption';
    return 'Caption style';
  }

  Future<void> setVerbCascadeLimit(int value) async {
    final next = value <= verbCascadeNone
        ? verbCascadeNone
        : (value >= verbCascadeAll ? verbCascadeAll : value);
    if (next == verbCascadeLimit) return;
    verbCascadeLimit = next;
    notifyListeners();
    await _prefs?.saveVerbCascadeLimit(next);
  }

  Future<void> setVerbListAll(bool value) async {
    if (verbListAll == value) return;
    verbListAll = value;
    notifyListeners();
    await _prefs?.saveVerbListAll(value);
  }

  Future<void> nudgeVerbFont(int delta) async {
    final next =
        (verbFontStep + delta).clamp(verbFontStepMin, verbFontStepMax);
    if (next == verbFontStep) return;
    verbFontStep = next;
    notifyListeners();
    await _prefs?.saveVerbFontStep(next);
  }

  String _playerProvenanceTip(RosterHit row) {
    final side = row.isHome ? 'Home' : 'Away';
    final team = (row.isHome ? homeTeam : awayTeam).trim();
    final teamBit = team.isEmpty ? side : '$side ($team)';
    switch (row.source) {
      case PlayerInputSource.textRecognition:
        final detail = row.recognitionDetail?.trim() ?? '';
        return detail.isEmpty
            ? 'Text recognition · $teamBit'
            : 'Text recognition · $detail';
      case PlayerInputSource.typed:
        return 'User input · Typed name';
      case PlayerInputSource.user:
        return 'User input · $teamBit';
    }
  }

  String get _photographerProvenanceTip {
    final serial = _photographerSerialUsed?.trim() ?? '';
    switch (_photographerProvenance) {
      case _BylineProvenance.serial:
        return serial.isEmpty
            ? 'Serial bylines · Filled from camera serial'
            : 'Serial bylines · Filled from camera $serial';
      case _BylineProvenance.serialAssigned:
        return serial.isEmpty
            ? 'Serial bylines · Assigned for this camera'
            : 'Serial bylines · Assigned for camera $serial';
      case _BylineProvenance.iptc:
        return 'Photo IPTC · Creator';
      case _BylineProvenance.none:
        return 'Session · Photographer';
    }
  }

  String get _normalizedFirebarQuery =>
      firebarOptions.isNotEmpty ? '' : _normalizeFirebarText(searchQuery);

  /// Query the menu, roster, and verbs should match.
  ///
  /// A space starts a new word. The words stay together only while they are
  /// still the start of a player's name, so a last name can be typed after a
  /// first name. Any other new word searches names and verbs on its own.
  String get _firebarFocusedQuery {
    final raw = _normalizedFirebarQuery;
    if (!raw.contains(' ')) return raw;
    if (_parseFirebarJerseyVerbCompound(raw) != null ||
        _parseFirebarJerseyTokens(raw) != null) {
      return raw;
    }
    if (_firebarQueryExtendsPlayerName(raw)) return raw;
    final parts = raw.split(RegExp(r'\s+'));
    return parts.isEmpty ? raw : parts.last;
  }

  bool _firebarQueryExtendsPlayerName(String query) {
    for (final player in [...homeRoster, ...awayRoster]) {
      final name = _normalizeFirebarText(player.fullName);
      if (name.isNotEmpty && name.startsWith(query)) return true;
    }
    return false;
  }

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
    return compound?.verbQuery ?? _firebarFocusedQuery;
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
    final nameQuery = _firebarFocusedQuery;
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
      if (nameQuery.isEmpty) return true;
      if (jerseyQuery != null) {
        return (player.jerseyNumber ?? '').trim() == jerseyQuery;
      }
      return _playerMatchScore(player, nameQuery) < 900;
    }).toList();
    if (nameQuery.isNotEmpty) {
      matches.sort((a, b) {
        final score = _playerMatchScore(a, nameQuery)
            .compareTo(_playerMatchScore(b, nameQuery));
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
    final selected = orderedSelectedImagePaths.length;
    if (selected > 1) return 'FTP $selected images';
    final name = ftpProfileName?.trim();
    if (name == null || name.isEmpty) return 'FTP';
    return 'FTP: $name';
  }
  int queuedCount = 0;
  String? lastSentLabel;
  bool transmitting = false;
  final List<FtpHistoryEntry> ftpHistory = [];

  /// Caption session whose uploads the history panel shows. Null on a session
  /// that was already open before sessions were tagged.
  String? ftpSessionId;
  DateTime? ftpSessionStartedAt;

  /// 0.0–1.0 for the whole batch while [transmitting]; cleared when idle.
  double transmitProgress = 0;

  /// 0.0–1.0 for the file in [ftpPreviewPath]. Resets when the next file starts.
  double ftpFileProgress = 0;

  /// Human-readable phase, e.g. "Uploading…".
  String? transmitStatus;

  /// Paths uploading right now, with each file's own 0.0–1.0 progress.
  final Map<String, double> ftpActiveProgress = {};

  /// File whose bytes are on the wire. The upload preview follows this.
  String? ftpPreviewPath;

  /// Path shown on the dock thumbnail while an upload is running.
  String? get transmittingPath => ftpPreviewPath;

  /// Files in the current send, including the one on the wire.
  int get ftpBatchTotal => transmitting ? _ftpSessionTotal : 0;

  /// Paths still waiting behind the file on the wire.
  List<String> get ftpQueuedPaths =>
      [for (final job in _ftpWait) job.path];

  /// 1-based place of the file currently uploading.
  int get ftpBatchIndex {
    if (!transmitting || _ftpSessionTotal <= 0) return 0;
    final shown = _ftpSessionDone + ftpActiveProgress.length;
    if (shown <= 0) return 1;
    return shown.clamp(1, _ftpSessionTotal);
  }

  FtpCancelToken? _ftpCancelToken;
  bool _ftpUserCancelled = false;

  bool ftpUploadingPath(String? path) =>
      path != null && ftpActiveProgress.containsKey(path);

  static const int ftpConcurrency = 1;
  final List<_FtpSendJob> _ftpWait = [];
  bool _ftpDraining = false;
  bool _ftpSessionOpen = false;
  int _ftpSessionTotal = 0;
  int _ftpSessionDone = 0;
  int _ftpSessionOk = 0;
  String? _ftpSessionError;
  String? _ftpCopyError;
  String _ftpSessionDuplicateFolder = '';

  String? statusMessage;

  /// Set a status the screen shows as a snackbar, even if it was already showing.
  void _warnStatus(String message) {
    if (statusMessage == message) {
      statusMessage = null;
      notifyListeners();
    }
    statusMessage = message;
    notifyListeners();
  }

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

  /// The thumbnail grid mutates [selectedImagePaths] in place.
  void noteImageSelectionChanged() {
    notifyListeners();
  }

  Future<void> transmitPaths(List<String> paths) => _transmitPaths(paths);

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
    if (verbs.isEmpty) return const [];
    final ranked = List<EffectiveVerb>.from(verbs);
    ranked.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return ranked;
  }

  EffectiveVerb? get pinnedVerbDefinition {
    final key = pinnedVerb;
    if (key == null) return null;
    return verbDefinition(key);
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
    if (hasTeamPlayersSubject && selectedPlayers.isEmpty) {
      return teamSubjectLabel(isHome: teamPlayersIsHome!);
    }
    final names = selectedPlayers.map((row) {
      final j = row.player.jerseyNumber ?? '';
      final short = _shortName(row.player.fullName);
      return j.isEmpty ? short : '$j $short';
    }).join(' + ');
    if (_captionIncludesTeammates) {
      return names.isEmpty ? 'teammates' : '$names + teammates';
    }
    return names;
  }

  /// Selected player stays the subject; "teammates" is appended like another pick.
  bool get _captionIncludesTeammates {
    final side = withTeammatesIsHome;
    if (side == null || hasTeamPlayersSubject || selectedPlayers.isEmpty) {
      return false;
    }
    return _captionSubjectIsHome == side;
  }

  bool get hasTeamPlayersSubject => teamPlayersIsHome != null;

  /// Players button or Teammates, not the bare team name. Verbs use the plural form.
  bool get _playersButtonIsGroup =>
      hasTeamPlayersSubject && teamSubjectKind != TeamSubjectKind.name;

  bool get hasCaptionSubject =>
      selectedPlayer != null || hasTeamPlayersSubject;

  /// Team name used as a caption subject, e.g. "Toronto FC".
  String teamNameLabel({required bool isHome}) {
    final team = (isHome ? homeTeam : awayTeam).trim();
    final name = team.isEmpty ? (isHome ? homeAbbr : awayAbbr) : team;
    return name.isEmpty ? 'Team' : name;
  }

  /// Group subject, e.g. "Toronto FC players".
  String teamPlayersLabel({required bool isHome}) {
    final name = teamNameLabel(isHome: isHome);
    return '$name players';
  }

  /// Group subject, e.g. "Toronto FC teammates".
  String teamTeammatesLabel({required bool isHome}) {
    final name = teamNameLabel(isHome: isHome);
    return '$name teammates';
  }

  String teamSubjectLabel({required bool isHome}) {
    switch (teamSubjectKind) {
      case TeamSubjectKind.players:
        return teamPlayersLabel(isHome: isHome);
      case TeamSubjectKind.teammates:
        return teamTeammatesLabel(isHome: isHome);
      case TeamSubjectKind.name:
        return teamNameLabel(isHome: isHome);
    }
  }

  bool get _captionSubjectIsHome {
    if (teamPlayersIsHome != null) return teamPlayersIsHome!;
    if (selectedPlayers.isNotEmpty) return selectedPlayers.first.isHome;
    return selectedIsHome;
  }

  void toggleTeamSubject({
    required bool isHome,
    required TeamSubjectKind kind,
  }) {
    captionSelectionStarted = true;
    manualCaptionOverride = null;
    if (kind == TeamSubjectKind.teammates) {
      if (withTeammatesIsHome == isHome) {
        withTeammatesIsHome = null;
        captionSelectionStarted =
            selectedPlayers.isNotEmpty || hasTeamPlayersSubject;
      } else {
        withTeammatesIsHome = isHome;
        if (hasTeamPlayersSubject) {
          teamPlayersIsHome = null;
        }
      }
      _syncPersonality();
      _syncKeywords();
      notifyListeners();
      return;
    }
    withTeammatesIsHome = null;
    final same = hasTeamPlayersSubject &&
        teamPlayersIsHome == isHome &&
        teamSubjectKind == kind;
    if (same) {
      teamPlayersIsHome = null;
      captionSelectionStarted = selectedPlayers.isNotEmpty;
    } else {
      teamPlayersIsHome = isHome;
      teamSubjectKind = kind;
      selectedPlayers.clear();
      selectedPlayer = null;
      selectedIsHome = isHome;
      playerSearchClearGeneration++;
    }
    _syncPersonality();
    _syncKeywords();
    notifyListeners();
  }

  /// Teammates stays armed until the subject leaves that side.
  void _dropTeammatesIfSubjectLeft() {
    final side = withTeammatesIsHome;
    if (side == null) return;
    if (selectedPlayers.isEmpty) return;
    if (selectedPlayers.first.isHome != side &&
        !selectedPlayers.any((row) => row.isHome == side)) {
      withTeammatesIsHome = null;
    }
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
    if (hasCaptionSubject) return false;
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
      case 'football':
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
    final team = _captionSubjectIsHome ? homeTeam : awayTeam;
    return '$team ';
  }

  String get captionTrailing {
    final venueText = venue.trim().isNotEmpty
        ? venue
        : (_metaFirst(CaptionFormulaRenderer.stadiumMetadataKeys) ?? '');
    final venueBit = venueText.isEmpty ? '' : ' at $venueText';
    if (!hasOpponentTeam) {
      return ' $timingCaptionClause$venueBit.'.replaceAll(RegExp(r'\s+'), ' ');
    }
    final subjectIsHome = _captionSubjectIsHome;
    final opp = subjectIsHome ? awayTeam : homeTeam;
    return ' against the $opp $timingCaptionClause$venueBit.';
  }

  /// Location / venue / byline resolved the same way as [buildCaptionSentence].
  GameInfo currentGameInfoForCaption() {
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
        : (_metaFirst(CaptionFormulaRenderer.stadiumMetadataKeys) ?? '');

    return GameInfo(
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
  }

  /// IPTC fields the active caption style needs that are still empty.
  List<String> get missingCaptionIptcLabels =>
      CaptionFormulaRenderer.missingCaptionIptcLabels(
        template: captionTemplate,
        game: currentGameInfoForCaption(),
      );

  /// Player + action body that feeds [CaptionFormulaRenderer] (no location/credit).
  ///
  /// Builds as soon as a player is selected (even before a verb), so the
  /// configured caption style can still wrap date / venue / byline around a
  /// partial body — matching V1.
  String buildCaptionBody() {
    if (!hasCaptionSubject) return '';
    final lead = hasTeamPlayersSubject
        ? _teamPlayersLead(captionTemplate)
        : _playerLead(captionTemplate);
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

    final game = currentGameInfoForCaption();

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
        if (hasVerbSelection) _previewActionClause(),
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
      applyGettyNoteVariant: true,
      gettyNbaeNote: GettyNoteVariant.applies(
        enabled: gettyNoteIsNbae,
        wire: captionTemplate.wireStyle,
        sport: sport,
      ),
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
    final subjectIsHome = _captionSubjectIsHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final target = opposingPlayers.isEmpty
        ? 'the ${opponentTeam.trim()}'
        : _formatPlayersWithTeam(opposingPlayers, captionTemplate);

    if (preGame) return 'ahead of playing against $target';
    if (postGame) return 'following the game against $target';
    return 'against $target $timingCaptionClause';
  }

  bool get hasCompleteCaption => hasCaptionSubject && hasVerbSelection;

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
    // With-teammates verbs: first pick is the subject; later same-team picks
    // are named in a trailing "with …" clause.
    final leadRows =
        _verbUsesLeadWithTeammates(selectedVerb) ? [rows.first] : rows;
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

  String _teamPlayersLead(CaptionTemplate template) {
    var label = teamSubjectLabel(isHome: teamPlayersIsHome!);
    if (template.removeDiacritics) {
      label = CaptionTextNormalize.stripDiacritics(label);
    }
    return label;
  }

  /// Verbs where the first same-team pick is the action subject and later
  /// same-team picks are named in a trailing "with …" clause.
  bool _verbUsesLeadWithTeammates(String? verb) {
    if (verb == null || verb.trim().isEmpty) return false;
    return verbDefinition(verb)?.withTeammates ?? verb == 'Celebrates a Goal';
  }

  /// Action text for layout previews: the verb's written wording, not its title.
  String _previewActionClause() {
    if (customVerbPhrase.trim().isNotEmpty) return _customActionPhrase();
    if (selectedVerb != null) return _actionPhrase();
    return '';
  }

  String _actionPhrase() {
    final verb = selectedVerb!;
    final definition = verbDefinition(verb);
    final subjects = subjectPlayers;
    final subjectIsHome = _captionSubjectIsHome;
    final opponentTeam = subjectIsHome ? awayTeam : homeTeam;
    final withTeammates = _verbUsesLeadWithTeammates(verb);
    // The Players button stands in for two or more athletes.
    final plural = _playersButtonIsGroup
        ? true
        : (withTeammates ? false : subjects.length > 1);
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

    final genericTeammates = _captionIncludesTeammates &&
        !action.toLowerCase().contains('with teammates');
    if (withTeammates && !_playersButtonIsGroup && subjects.length > 1) {
      final teammates = subjects.skip(1).toList(growable: false);
      var names = _formatPlayerNamesOnly(teammates, captionTemplate);
      if (genericTeammates && names.isNotEmpty) {
        names = '$names and teammates';
      }
      if (names.isNotEmpty) {
        action = '$action with $names';
      } else if (genericTeammates) {
        action = '$action with teammates';
      }
    } else if (genericTeammates && !_playersButtonIsGroup) {
      action = '$action with teammates';
    }

    final namedOpponents = _namedOpponentsForCaption();
    final includeOpponent =
        (definition?.wantsOpponent ?? true) || namedOpponents.isNotEmpty;
    final opponentName = opponentTeam.trim();
    final opponentTarget = namedOpponents.isNotEmpty
        ? namedOpponents
        : (opponentName.isEmpty ? '' : 'the $opponentName');
    action = CaptionV2CaptionDomain.fillTheirTeam(action, opponentTarget);
    if (includeOpponent && opponentTarget.isNotEmpty) {
      final lower = action.toLowerCase();
      final alreadyNamed = namedOpponents.isNotEmpty &&
          lower.contains(namedOpponents.toLowerCase());
      final alreadyTeam = namedOpponents.isEmpty &&
          opponentName.isNotEmpty &&
          lower.contains(opponentName.toLowerCase());
      if (!alreadyNamed && !alreadyTeam) {
        final joiner = (definition?.opponentJoiner ?? 'against').trim();
        action = CaptionV2CaptionDomain.withOpponent(
          verb: verb,
          action: action,
          opponentTeam: opponentName,
          opposingPlayers: namedOpponents.isEmpty ? null : namedOpponents,
          omitAgainst: definition?.omitAgainst ?? joiner.isEmpty,
          opponentJoiner: joiner,
        );
      }
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
    if (_captionIncludesTeammates &&
        !action.toLowerCase().contains('with teammates')) {
      action = '$action with teammates';
    }
    final subjectIsHome = _captionSubjectIsHome;
    final namedOpponents = _namedOpponentsForCaption();
    final opponentName =
        (subjectIsHome ? awayTeam : homeTeam).trim();
    final opponentTarget = namedOpponents.isNotEmpty
        ? namedOpponents
        : (opponentName.isEmpty ? '' : 'the $opponentName');
    action = CaptionV2CaptionDomain.fillTheirTeam(action, opponentTarget);
    if (opponentTarget.isNotEmpty) {
      final lower = action.toLowerCase();
      final alreadyNamed = namedOpponents.isNotEmpty &&
          lower.contains(namedOpponents.toLowerCase());
      final alreadyTeam = namedOpponents.isEmpty &&
          opponentName.isNotEmpty &&
          lower.contains(opponentName.toLowerCase());
      if (!alreadyNamed && !alreadyTeam) {
        final alreadyJoined =
            lower.contains(' against ') || lower.contains(' playing ');
        action = alreadyJoined
            ? '$action ${namedOpponents.isNotEmpty ? namedOpponents : 'the $opponentName'}'
            : CaptionV2CaptionDomain.withOpponent(
                verb: action,
                action: action,
                opponentTeam: opponentName,
                opposingPlayers:
                    namedOpponents.isEmpty ? null : namedOpponents,
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

  /// Names of selected opposing players, without a blank "of the" when the
  /// other club has no stored name.
  String _namedOpponentsForCaption() {
    if (opposingPlayers.isEmpty) return '';
    return _formatPlayersWithTeam(opposingPlayers, captionTemplate);
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
    final names = _joinNames(labels);
    if (team.trim().isEmpty) return names;
    return '$names of the $team';
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
    verbCascadeLimit = await _prefs!.getVerbCascadeLimit();
    verbListAll = await _prefs!.getVerbListAll();
    verbFontStep = (await _prefs!.getVerbFontStep())
        .clamp(verbFontStepMin, verbFontStepMax);
    _verbUsageCounts = await _prefs!.getVerbUsageCountsForSport(sport);
    await _loadVerbCatalog();
    captionTemplate = await _prefs!.getCaptionTemplate();
    gettyNoteIsNbae = await _prefs!.getGettyNoteIsNbae();
    mlbTimestampEnabled = await _prefs!.getMlbInningFromClockEnabled();
    showKeywordsField = await _prefs!.getShowKeywordsField();
    showPersonalityField = await _prefs!.getShowPersonalityField();
    applyVerbKeywords = await _prefs!.getApplyVerbKeywords();
    applyPlayerNamesToKeywords = await _prefs!.getApplyPlayerNamesToKeywords();
    await reloadApplicationModes();
    await _refreshJerseyOcrEnabled();
    _prefs!.captionFieldVisibilityRevision.addListener(
      _onCaptionFieldVisibilityChanged,
    );
    _prefs!.ftpProfilesRevision.addListener(_onFtpProfilesChanged);
    _prefs!.jerseyOcrRevision.addListener(_onJerseyOcrPreferenceChanged);
    _prefs!.applicationModesRevision.addListener(_onApplicationModesChanged);
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
    gettyNoteIsNbae = await prefs.getGettyNoteIsNbae();
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
    final token = _verbPreviewToken;
    final catalog = await repository.load(sport);
    if (token != _verbPreviewToken) return;
    _verbCatalog = catalog;
    final prefs = _prefs;
    if (prefs != null) {
      _verbUsageCounts = await prefs.getVerbUsageCountsForSport(sport);
    }
    if (token != _verbPreviewToken) return;
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

  /// Prefer [setFirebarEnabled] from UI — [hidden] is the stored preference.
  Future<void> setHideFirebar(bool hidden) async {
    if (hidden == hideFirebar) return;
    hideFirebar = hidden;
    if (hidden && searchOpen) setSearchOpen(false);
    notifyListeners();
    await _prefs?.saveHideFirebar(hidden);
  }

  /// Positive Firebar on/off (inverse of [hideFirebar]).
  Future<void> setFirebarEnabled(bool enabled) => setHideFirebar(!enabled);

  Future<void> setSerialBylinesEnabled(bool enabled) async {
    if (enabled == serialBylinesEnabled) return;
    serialBylinesEnabled = enabled;
    if (!enabled) _releaseSerialBylinesGate();
    notifyListeners();
    await _prefs?.saveSerialNumberBylines(enabled);
  }

  Future<void> setBurstDetectionEnabled(bool enabled) async {
    if (enabled == burstDetectionEnabled) return;
    burstDetectionEnabled = enabled;
    notifyListeners();
    await _prefs?.saveBurstDetectionEnabled(enabled);
  }

  /// Re-read Application mode toggles (FTP / serial / burst / OCR) from prefs.
  Future<void> reloadApplicationModes() async {
    final prefs = _prefs ?? await PreferencesService.getInstance();
    _prefs = prefs;
    ftpModeEnabled = await prefs.getFtpModeEnabled();
    hideFirebar = await prefs.getHideFirebar();
    serialBylinesEnabled = await prefs.getSerialNumberBylines();
    if (!serialBylinesEnabled) _releaseSerialBylinesGate();
    burstDetectionEnabled = await prefs.getBurstDetectionEnabled();
    resolutionWarningThreshold = await prefs.getResolutionWarningThreshold();
    await _refreshJerseyOcrEnabled();
    if (currentPath != null) unawaited(_refreshFrameIptc());
    notifyListeners();
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
    bool? homeWearsDark,
    bool homeWearsDarkAnswered = false,
    Future<bool> Function(String gameDate, List<OlderRosterTeam> teams)?
        chooseOlderRoster,
  }) async {
    sessionGeneration++;
    ftpSessionId = '${DateTime.now().microsecondsSinceEpoch}';
    ftpSessionStartedAt = DateTime.now();
    _jerseyOcrPrescanStop = false;
    _serialBylinesHandled.clear();
    _serialBylinesPromptDismissed.clear();
    _releaseSerialBylinesGate();
    _scanSerialsOnArrival = false;
    _deferSerialBylinesUi = true;
    this.sport = sport;
    this.homeTeam = homeTeam;
    this.singleTeamMode = singleTeamMode;
    this.awayTeam = singleTeamMode ? '' : awayTeam;
    this.venue = venue;
    this.city = city;
    this.region = region;
    this.country = country;
    this.countryCode = countryCode;
    pinnedVerb = null;
    pinnedPlayer = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    lastCustomPlayerName = '';
    lastCustomPlayerJersey = '';
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    teamPlayersIsHome = null;
    withTeammatesIsHome = null;
    selectedIsHome = true;
    selectedVerb = null;
    celebrationType = null;
    personality = '';
    manualCaptionOverride = null;
    rbi = 0;
    selectedBase = null;
    inning = 1;
    timingByQuarter = false;
    timingHalf = supportsTimingHalves ? '1H' : null;
    preGame = false;
    postGame = false;
    _recentPicks.clear();
    _homeDarkVotes = 0;
    homeWearsDarkOverride = homeWearsDark;
    _homeWearsDarkAnswered = homeWearsDarkAnswered;
    rosterHistoryCanSwitch = false;
    usingGameDateRoster = false;
    _homeRosterPasted = homeRosterOverride != null;
    _awayRosterPasted = singleTeamMode || awayRosterOverride != null;
    _rosterHistoryGameDate = null;
    _rosterHistoryApplied = false;
    sessionLoading = true;
    sessionLoadingLabel = 'Loading rosters…';
    sessionReady = false;
    notifyListeners();

    _api.setSport(sport);
    await _prefs?.saveCurrentSport(sport);
    await reloadApplicationModes();
    await _loadVerbCatalog();
    await _loadCaptionStyleCatalog();

    await loadRosters(
      homeOverride: homeRosterOverride,
      awayOverride: singleTeamMode ? const <Player>[] : awayRosterOverride,
    );
    sessionLoadingLabel = 'Loading images…';
    notifyListeners();
    await loadFolder(folderPath);
    await _checkSerialBylinesBeforeSession();

    // loadFolder awaits saved/uploaded marks + preview EXIF before returning.
    // Still on the loading screen: pre-warm thumbs (+ OCR when enabled) so the
    // session opens snappy instead of catching up in the background.
    await _refreshJerseyOcrEnabled();
    await _preloadSessionDuringLoad();
    await applyDatedRosterHistory(chooseOlderRoster: chooseOlderRoster);

    sessionLoading = false;
    sessionLoadingLabel = null;
    sessionReady = true;
    notifyListeners();
    // Load already warmed thumbs + OCR. Only finish leftovers / neighbors.
    _schedulePreviewWarmup();
    if (_jerseyOcrPrescanned.length < imagePaths.length) {
      _kickJerseyOcrPrescan();
    }
  }

  /// Blocking folder warm while [sessionLoading] is true — updates the loading
  /// label. Thumbs always; jersey OCR only when text recognition is on.
  Future<void> _preloadSessionDuringLoad() async {
    if (imagePaths.isEmpty || !sessionLoading) return;
    final generation = sessionGeneration;

    // 1) Grid thumbs — kills the spinner circles when the strip opens.
    await _preloadThumbsDuringLoad(generation);
    if (generation != sessionGeneration || !sessionLoading) return;

    // 2) Current + neighbor main previews.
    _setSessionLoadingLabel('Preparing preview…');
    final previewGen = ++_previewWarmGeneration;
    await _warmPreviews(previewGen);
    if (generation != sessionGeneration || !sessionLoading) return;

    // 3) Sample home/away jersey colours before OCR so the first matches
    // already know which bench is which.
    await _awaitJerseyColorsIfNeeded(generation);
    if (generation != sessionGeneration || !sessionLoading) return;

    // 4) Text recognition for the frame they'll see first. The rest of the
    // folder keeps scanning after the session opens.
    if (jerseyOcrEnabled) {
      await _prescanJerseyOcrDuringLoad(generation);
    }
  }

  /// Shown on the loading screen when text recognition is on. Completes when
  /// the user picks both jerseys or skips.
  bool awaitingJerseyColors = false;
  Completer<void>? _jerseyColorGate;

  Future<void> _awaitJerseyColorsIfNeeded(int generation) async {
    if (!jerseyOcrEnabled || singleTeamMode || imagePaths.isEmpty) return;
    if (generation != sessionGeneration || !sessionLoading) return;
    awaitingJerseyColors = true;
    _setSessionLoadingLabel('Pick jersey colours');
    final gate = Completer<void>();
    _jerseyColorGate = gate;
    notifyListeners();
    await gate.future;
    if (generation != sessionGeneration) return;
    awaitingJerseyColors = false;
    _jerseyColorGate = null;
  }

  void finishJerseyColorGate() {
    final gate = _jerseyColorGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// Move the loading-screen photo without starting an OCR pass.
  void showColorPickFrame(int index) {
    if (imagePaths.isEmpty) return;
    currentIndex = index.clamp(0, imagePaths.length - 1);
    notifyListeners();
  }

  Future<void> _preloadThumbsDuringLoad(int generation) async {
    final paths = List<String>.from(imagePaths);
    if (paths.isEmpty) return;
    final index = currentIndex.clamp(0, paths.length - 1);
    final ordered = <String>[
      ...paths.sublist(index),
      ...paths.sublist(0, index),
    ];
    final thumbGen = ++_thumbWarmGeneration;
    const wave = 24;
    var done = 0;
    final total = ordered.length;
    _setSessionLoadingLabel('Warming thumbnails 0/$total…');

    for (var i = 0; i < ordered.length; i += wave) {
      if (generation != sessionGeneration ||
          thumbGen != _thumbWarmGeneration ||
          !sessionLoading) {
        return;
      }
      final end = (i + wave).clamp(0, ordered.length);
      final slice = ordered.sublist(i, end);
      await OrientedImageBytes.prefetchAll(
        [
          for (final path in slice)
            OrientedPrefetchJob(
              path: path,
              maxWidth: OrientedImageBytes.thumbMaxWidth,
            ),
        ],
        isCurrent: () =>
            generation == sessionGeneration &&
            thumbGen == _thumbWarmGeneration &&
            sessionLoading,
      );
      done = end;
      _setSessionLoadingLabel('Warming thumbnails $done/$total…');
    }
  }

  /// One frame on the loading screen. A stuck Vision pass must not hold the
  /// session shut — the background pre-scan picks up anything left unread.
  static const Duration _loadOcrTimeout = Duration(seconds: 12);

  Future<void> _prescanJerseyOcrDuringLoad(int generation) async {
    if (!jerseyOcrEnabled || imagePaths.isEmpty) return;
    if (_jerseyOcrPrescanRunning) return;
    _jerseyOcrPrescanRunning = true;
    final customWords = _ocrCustomWords();
    final sportKey = sport.trim().toLowerCase();
    try {
      if (generation != sessionGeneration ||
          !jerseyOcrEnabled ||
          !sessionLoading ||
          _jerseyOcrPrescanStop) {
        return;
      }
      final path = currentPath;
      if (path == null) return;
      _setSessionLoadingLabel('Text recognition…');

      int mtimeMs = 0;
      try {
        mtimeMs = (await File(path).lastModified()).millisecondsSinceEpoch;
      } catch (_) {
        return;
      }

      final key = _jerseyOcrCacheKey(
        path: path,
        mtimeMs: mtimeMs,
        roiKey: 'full',
        sportKey: sportKey,
        customWords: customWords,
      );
      if (!_jerseyOcrCache.containsKey(key)) {
        List<JerseyOcrHit> hits;
        try {
          hits = await JerseyOcrChannel.recognize(
            path: path,
            customWords: customWords,
            sport: sportKey,
            prescan: true,
          ).timeout(_loadOcrTimeout);
        } on TimeoutException {
          // Leave it unscanned so the background pass retries it.
          unawaited(JerseyOcrChannel.cancelPrescan());
          return;
        }
        if (generation != sessionGeneration ||
            !jerseyOcrEnabled ||
            _jerseyOcrPrescanStop) {
          return;
        }
        _putJerseyOcrCache(key, hits);
      }
      _jerseyOcrPrescanned.add(path);
      jerseyOcrPrescanDone = _jerseyOcrPrescanned.length;
      jerseyOcrPrescanTotal = imagePaths.length;

      if (generation == sessionGeneration &&
          jerseyOcrEnabled &&
          !_jerseyOcrPrescanStop) {
        await runOcrTestScan(force: false);
      }
    } finally {
      _jerseyOcrPrescanRunning = false;
    }
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
        kept.add(row.copyWith(player: match));
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
    return pinned.copyWith(player: match);
  }

  void resetToStartup() {
    _folderWatchGeneration++;
    ftpSessionId = null;
    ftpSessionStartedAt = null;
    _stopFolderWatch();
    _scanSerialsOnArrival = false;
    _deferSerialBylinesUi = false;
    _releaseSerialBylinesGate();
    sessionReady = false;
    sessionLoading = false;
    sessionLoadingLabel = null;
    imagePaths = [];
    currentIndex = 0;
    selectedImagePaths.clear();
    homeRoster = const [];
    awayRoster = const [];
    _clearJerseyOcrState(clearCache: true);
    singleTeamMode = false;
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    teamPlayersIsHome = null;
    withTeammatesIsHome = null;
    selectedVerb = null;
    pinnedVerb = null;
    pinnedPlayer = null;
    customVerbPhrase = '';
    lastCustomVerbPhrase = '';
    customVerbPinned = false;
    lastCustomPlayerName = '';
    lastCustomPlayerJersey = '';
    personality = '';
    manualCaptionOverride = null;
    notifyListeners();
    unawaited(reloadCaptionStyle());
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
      // Keep empty rosters on failure — never invent players from another sport.
      homeRoster = homeOverride == null ? const [] : _sortPlayers(homeOverride);
      if (singleTeamMode || !hasOpponentTeam) {
        awayRoster = const [];
      } else {
        awayRoster =
            awayOverride == null ? const [] : _sortPlayers(awayOverride);
      }
    } finally {
      rostersLoading = false;
      notifyListeners();
      _scheduleJerseyOcr();
    }
  }

  String? _sessionGameDateYmd() {
    DateTime? earliest;
    for (final captured in captureByPath.values) {
      if (earliest == null || captured.isBefore(earliest)) earliest = captured;
    }
    return RosterHistoryService.calendarDate(earliest);
  }

  /// One Firestore history pass per session, after photo dates are known.
  /// Tank01 sessions return before any rosterDays read.
  Future<void> applyDatedRosterHistory({
    Future<bool> Function(String gameDate, List<OlderRosterTeam> teams)?
        chooseOlderRoster,
  }) async {
    if (_rosterHistoryApplied) return;
    _rosterHistoryApplied = true;
    final gameDate = _sessionGameDateYmd();
    if (gameDate == null) return;
    if (await RosterHistoryService.servedByTank01(sport)) return;
    if (!await RosterHistoryService.useRosterHistory()) return;

    final homeSide = _homeRosterPasted
        ? null
        : await RosterHistoryService.loadTeam(
            sportId: sport,
            teamName: homeTeam,
            gameDate: gameDate,
            liveToday: false,
          );
    final awaySide = _awayRosterPasted || !hasOpponentTeam
        ? null
        : await RosterHistoryService.loadTeam(
            sportId: sport,
            teamName: awayTeam,
            gameDate: gameDate,
            liveToday: false,
          );

    final older = <OlderRosterTeam>[];
    void collect(SideHistory? side) {
      if (side == null || side.useExistingPath || !side.differsFromLatest) {
        return;
      }
      final on = side.effectiveOn;
      if (on == null || on.isEmpty) return;
      older.add(OlderRosterTeam(teamName: side.teamName, effectiveOn: on));
    }

    collect(homeSide);
    collect(awaySide);

    var useGameDate = true;
    if (older.isNotEmpty && chooseOlderRoster != null) {
      useGameDate = await chooseOlderRoster(gameDate, older);
    }
    usingGameDateRoster = useGameDate;
    rosterHistoryCanSwitch = older.isNotEmpty;
    _rosterHistoryGameDate = gameDate;

    if (older.isNotEmpty && !useGameDate) {
      await _loadLiveHistoryRosters();
      return;
    }
    _applyHistorySide(homeSide, isHome: true);
    _applyHistorySide(awaySide, isHome: false);
    notifyListeners();
    _scheduleJerseyOcr();
  }

  void _applyHistorySide(SideHistory? side, {required bool isHome}) {
    if (side == null || side.useExistingPath) return;
    if (isHome) {
      homeRoster = _sortPlayers(side.players);
    } else {
      awayRoster = _sortPlayers(side.players);
    }
  }

  Future<void> _loadLiveHistoryRosters() async {
    final gameDate = _rosterHistoryGameDate;
    if (gameDate == null) return;
    if (!_homeRosterPasted) {
      final side = await RosterHistoryService.loadTeam(
        sportId: sport,
        teamName: homeTeam,
        gameDate: gameDate,
        liveToday: true,
      );
      if (!side.useExistingPath && side.players.isNotEmpty) {
        homeRoster = _sortPlayers(side.players);
      }
    }
    if (!_awayRosterPasted && hasOpponentTeam) {
      final side = await RosterHistoryService.loadTeam(
        sportId: sport,
        teamName: awayTeam,
        gameDate: gameDate,
        liveToday: true,
      );
      if (!side.useExistingPath && side.players.isNotEmpty) {
        awayRoster = _sortPlayers(side.players);
      }
    }
    notifyListeners();
    _scheduleJerseyOcr();
  }

  /// Reloads both teams once from Firestore. Photos do not call this.
  Future<void> switchRosterHistorySource() async {
    if (!rosterHistoryCanSwitch || _rosterHistoryGameDate == null) return;
    usingGameDateRoster = !usingGameDateRoster;
    if (!usingGameDateRoster) {
      await _loadLiveHistoryRosters();
      return;
    }
    final gameDate = _rosterHistoryGameDate!;
    if (!_homeRosterPasted) {
      final side = await RosterHistoryService.loadTeam(
        sportId: sport,
        teamName: homeTeam,
        gameDate: gameDate,
        liveToday: false,
      );
      _applyHistorySide(side, isHome: true);
    }
    if (!_awayRosterPasted && hasOpponentTeam) {
      final side = await RosterHistoryService.loadTeam(
        sportId: sport,
        teamName: awayTeam,
        gameDate: gameDate,
        liveToday: false,
      );
      _applyHistorySide(side, isHome: false);
    }
    notifyListeners();
    _scheduleJerseyOcr();
  }

  /// Replaces a loaded roster after the user decides how to handle duplicates.
  void replaceLoadedRosters({List<Player>? home, List<Player>? away}) {
    if (home != null) homeRoster = _sortPlayers(home);
    if (away != null) awayRoster = _sortPlayers(away);
    notifyListeners();
    _scheduleJerseyOcr();
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

  void _setSessionLoadingLabel(String label) {
    if (!sessionLoading) return;
    if (sessionLoadingLabel == label) return;
    sessionLoadingLabel = label;
    notifyListeners();
  }

  Future<void> loadFolder(String dirPath) async {
    final blockingLoad = sessionReady;
    loadingImages = true;
    if (blockingLoad) {
      sessionLoading = true;
      sessionLoadingLabel = 'Loading images…';
    }
    notifyListeners();
    final generation = ++_folderWatchGeneration;
    _previewWarmGeneration++; // cancel neighbor preview warm for prior folder
    _thumbWarmGeneration++; // cancel full-folder thumb warm for prior folder
    _stopFolderWatch();
    try {
      await NativeFilePicker.ensureMediaReadPermission();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        imagePaths = [];
        currentIndex = 0;
        return;
      }
      _setSessionLoadingLabel('Scanning photo folder…');
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
      _resetJerseyOcrPrescan();
      currentIndex = 0;
      selectedImagePaths.clear();
      savedImages.clear();
      captionedImages.clear();
      sentImages.clear();
      captureByPath.clear();
      currentIptcMeta = {};
      _imageContentStamp.clear();
      _fileLength.clear();
      _fileModifiedMs.clear();
      _fileChangedMs.clear();
      _startFolderWatch(dirPath, generation);
      // Wait for saved/uploaded marks + preview EXIF before revealing the UI,
      // so header/footer and status icons don't pop in later.
      await _finishFolderMetadata(dirPath, generation);
      if (generation != _folderWatchGeneration) return;
      unawaited(_ingestFolderAdditions(generation));
      for (final path in pending) {
        unawaited(_addImageWhenReady(path, generation));
      }
    } finally {
      if (generation == _folderWatchGeneration) {
        loadingImages = false;
        if (blockingLoad) {
          sessionLoading = false;
          sessionLoadingLabel = null;
        }
        notifyListeners();
        // Startup keeps [sessionLoading] true and awaits blocking preload in
        // [applyStartup]. Mid-session folder reloads warm in the background.
        if (!sessionLoading) {
          _schedulePreviewWarmup();
          _scheduleThumbWarmup();
          _scheduleJerseyOcr();
          _kickJerseyOcrPrescan();
        }
      }
    }
  }

  /// Capture times, saved/uploaded marks, on-import IPTC, and current-frame
  /// EXIF for the preview header/footer. Awaited before the session UI opens.
  Future<void> _finishFolderMetadata(String dirPath, int generation) async {
    if (generation != _folderWatchGeneration) return;
    if (imagePaths.isEmpty) {
      currentIptcMeta = {};
      notifyListeners();
      return;
    }

    _setSessionLoadingLabel(
      'Reading capture times (${imagePaths.length} photos)…',
    );
    await _loadCaptureTimes();
    if (generation != _folderWatchGeneration) return;
    // [_loadCaptureTimes] re-sorts by capture time. Always keep the first
    // frame selected — restoring the pre-sort path jumped into the middle
    // when the alphabetically-first file wasn't the earliest capture.
    currentIndex = 0;
    notifyListeners();

    _setSessionLoadingLabel('Checking saved & uploaded status…');
    final marked = await FloCaptionMark.savedPaths(List<String>.from(imagePaths));
    if (generation != _folderWatchGeneration) return;
    savedImages.addAll(marked);
    captionedImages.addAll(marked);
    await _restoreSavedPrefs(dirPath);
    _restoreSentFromFtpHistory();
    await _applyIptcTemplateOnImportIfEnabled();
    if (generation != _folderWatchGeneration) return;

    _setSessionLoadingLabel('Loading photo details…');
    await _refreshFrameIptc();
    notifyListeners();
  }

  /// Re-apply successful FTP history onto [sentImages] for this folder.
  void _restoreSentFromFtpHistory() {
    if (imagePaths.isEmpty || ftpHistory.isEmpty) return;
    final inFolder = imagePaths.toSet();
    for (final entry in ftpHistory) {
      if (!entry.success) continue;
      if (!inFolder.contains(entry.path)) continue;
      sentImages.add(entry.path);
      savedImages.add(entry.path);
      captionedImages.add(entry.path);
    }
  }

  /// Decode nearby main previews into [OrientedImageBytes] (preview budget).
  /// Safe to call on every frame change — does **not** cancel thumb preload.
  void _schedulePreviewWarmup() {
    if (imagePaths.isEmpty) return;
    final gen = ++_previewWarmGeneration;
    unawaited(_warmPreviews(gen));
  }

  /// Decode every grid thumb into the thumb budget. Only cancelled when the
  /// folder changes — frame navigation leaves it running so the strip stays
  /// snappy all the way to the bottom.
  void _scheduleThumbWarmup() {
    if (imagePaths.isEmpty) return;
    final gen = ++_thumbWarmGeneration;
    unawaited(_warmThumbs(gen));
  }

  Future<void> _warmPreviews(int gen) async {
    final paths = List<String>.from(imagePaths);
    if (paths.isEmpty) return;
    final index = currentIndex.clamp(0, paths.length - 1);
    final jobs = <OrientedPrefetchJob>[];
    final seen = <String>{};

    void addJob(String path, int maxWidth) {
      final key = '$path|$maxWidth';
      if (!seen.add(key)) return;
      jobs.add(OrientedPrefetchJob(path: path, maxWidth: maxWidth));
    }

    // Current + neighbors at preview size (main photo pane).
    for (final i in [index, index + 1, index - 1, index + 2, index + 3]) {
      if (i < 0 || i >= paths.length) continue;
      addJob(paths[i], OrientedImageBytes.previewMaxWidth);
    }

    await OrientedImageBytes.prefetchAll(
      jobs,
      isCurrent: () => gen == _previewWarmGeneration,
    );
  }

  Future<void> _warmThumbs(int gen) async {
    final paths = List<String>.from(imagePaths);
    if (paths.isEmpty) return;
    final index = currentIndex.clamp(0, paths.length - 1);
    // From the current frame forward (what the user scrolls into next), then
    // wrap so the top of the strip finishes too.
    final ordered = <String>[
      ...paths.sublist(index),
      ...paths.sublist(0, index),
    ];
    final jobs = <OrientedPrefetchJob>[
      for (final path in ordered)
        OrientedPrefetchJob(
          path: path,
          maxWidth: OrientedImageBytes.thumbMaxWidth,
        ),
    ];
    await OrientedImageBytes.prefetchAll(
      jobs,
      isCurrent: () => gen == _thumbWarmGeneration,
    );
  }

  /// Warm grid thumbs for [paths] (scroll-ahead). Safe to call often.
  void warmThumbnailPaths(Iterable<String> paths) {
    final jobs = <OrientedPrefetchJob>[
      for (final path in paths)
        if (!OrientedImageBytes.isCached(
          path,
          maxWidth: OrientedImageBytes.thumbMaxWidth,
        ))
          OrientedPrefetchJob(
            path: path,
            maxWidth: OrientedImageBytes.thumbMaxWidth,
          ),
    ];
    if (jobs.isEmpty) return;
    unawaited(
      OrientedImageBytes.prefetchAll(jobs, isCurrent: () => true),
    );
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
        // Re-OCR only on an explicit Refresh — not on every mtime/IPTC churn
        // while shooting. Brand-new files are scanned in [_insertCompletedImage].
        if (announce && currentChanged) {
          _invalidateJerseyOcrCacheFor(current);
          _scheduleJerseyOcr();
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
    _clicksByPath.remove(path);
    _restoreClicksOnOpen.remove(path);
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
    if (_scanSerialsOnArrival) {
      unawaited(_checkArrivingSerial(path));
    }
    // Scan the new frame as soon as it lands — thumb + OCR (if on).
    warmThumbnailPaths([path]);
    if (path == currentPath) {
      // User is already on this frame (or just jumped to it): run the real
      // frame scan now so chips appear immediately.
      _scheduleJerseyOcr();
    } else if (jerseyOcrEnabled) {
      unawaited(_ocrScanOnArrival(path));
    }
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
      final preset = await _loadSelectedIptcPreset();
      if (preset.isEmpty) return;
      final index = imagePaths.indexOf(imagePath);
      final result = await IptcTemplateApplyService.applyToImage(
        imagePath,
        preset,
        imageIndex: index >= 0 ? index : null,
        replaceExisting: true,
      );
      if (result.success && !result.skipped) {
        captionedImages.remove(imagePath);
        savedImages.remove(imagePath);
        notifyListeners();
      }
      await _syncFileSig(imagePath);
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
      if (preset.isEmpty) return;
      final label = 'Writing IPTC template to ${imagePaths.length} images…';
      if (sessionLoading) {
        sessionLoadingLabel = label;
      } else {
        statusMessage = label;
      }
      notifyListeners();
      var i = 0;
      for (final path in imagePaths) {
        final result = await IptcTemplateApplyService.applyToImage(
          path,
          preset,
          imageIndex: i,
          replaceExisting: true,
        );
        if (result.success && !result.skipped) {
          captionedImages.remove(path);
          savedImages.remove(path);
        }
        await _syncFileSig(path);
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
      if (result.success) await _syncFileSig(imagePath);
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

  /// Sync length/mtime after *our* writes (IPTC, captions) so the folder
  /// watcher does not treat the change as a new picture and re-OCR.
  Future<void> _syncFileSig(String path) async {
    try {
      _rememberFileSig(path, await File(path).stat());
    } catch (_) {}
  }

  /// A graded JPEG replaced [path]. Drop cached previews and don't re-ingest.
  Future<void> noteImageFileReplaced(String path) async {
    OrientedImageBytes.evict(path);
    _imageContentStamp[path] = imageContentStamp(path) + 1;
    await _syncFileSig(path);
    notifyListeners();
    if (path == currentPath) unawaited(_refreshFrameIptc());
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

  void _onFtpProfilesChanged() {
    unawaited(() async {
      await _refreshFtpDestination();
      notifyListeners();
    }());
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void selectPlayer(
    Player player, {
    required bool isHome,
    PlayerInputSource source = PlayerInputSource.user,
    String? recognitionDetail,
  }) {
    captionSelectionStarted = true;
    teamPlayersIsHome = null;
    final existingIndex = selectedPlayers.indexWhere(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
    if (existingIndex >= 0) {
      selectedPlayers.removeAt(existingIndex);
    } else {
      selectedPlayers.add(RosterHit(
        player: player,
        isHome: isHome,
        source: source,
        recognitionDetail: recognitionDetail,
      ));
      _rememberRecentPick(player, isHome: isHome);
      _learnJerseyToneFromPick(player, isHome: isHome);
    }
    manualCaptionOverride = null;
    _syncPrimaryPlayer();
    _dropTeammatesIfSubjectLeft();
    _syncKeywords();
    notifyListeners();
  }

  static String _ocrPlayerKey(Player player, {required bool isHome}) =>
      '${isHome ? 'h' : 'a'}|${player.playerId ?? player.fullName}|'
      '${player.jerseyNumber ?? ''}';

  void _rememberRecentPick(Player player, {required bool isHome}) {
    final path = currentPath;
    if (path == null) return;
    final key = _ocrPlayerKey(player, isHome: isHome);
    _recentPicks.removeWhere((p) => p.playerKey == key);
    _recentPicks.add(_RecentPick(
      playerKey: key,
      isHome: isHome,
      capturedAt: captureByPath[path],
      frameIndex: currentIndex,
    ));
    while (_recentPicks.length > 40) {
      _recentPicks.removeAt(0);
    }
  }

  /// A pick that agrees with an OCR jersey read tells us which bench is dark.
  void _learnJerseyToneFromPick(Player player, {required bool isHome}) {
    if (homeWearsDarkOverride != null) return;
    final key = _ocrPlayerKey(player, isHome: isHome);
    final jersey = _normalizeJerseyKey(player.jerseyNumber);
    String? tone;
    for (final s in jerseySuggestions) {
      if (s.jerseyTone == null) continue;
      if (_ocrPlayerKey(s.player, isHome: s.isHome) == key) {
        tone = s.jerseyTone;
        break;
      }
      // Same number read on the other bench — the user corrected the side,
      // so the tone belongs to the picked side.
      if (jersey != null &&
          s.matchKind == JerseyOcrMatchKind.jersey &&
          _normalizeJerseyKey(s.jersey) == jersey) {
        tone = s.jerseyTone;
      }
    }
    if (tone == null) return;
    final saysHomeDark = (tone == 'dark') == isHome;
    _homeDarkVotes = (_homeDarkVotes + (saysHomeDark ? 1 : -1)).clamp(-6, 6);
  }

  /// Shift continuity: how strongly recent frames vouch for [playerKey].
  double _recentPickBoost(String playerKey) {
    final path = currentPath;
    if (path == null || _recentPicks.isEmpty) return 0;
    final now = captureByPath[path];
    var best = 0.0;
    for (final pick in _recentPicks) {
      if (pick.playerKey != playerKey) continue;
      double boost;
      if (now != null && pick.capturedAt != null) {
        final gap = now.difference(pick.capturedAt!).inMilliseconds.abs();
        if (gap <= 6000) {
          boost = 0.12;
        } else if (gap <= 25000) {
          boost = 0.07;
        } else if (gap <= 90000) {
          boost = 0.03;
        } else {
          boost = 0;
        }
      } else {
        final frames = (pick.frameIndex - currentIndex).abs();
        boost = frames <= 2 ? 0.10 : (frames <= 6 ? 0.05 : 0);
      }
      if (boost > best) best = boost;
    }
    return best;
  }

  /// Which bench the user has been working lately (−1 away … +1 home).
  double _recentSideLean() {
    final path = currentPath;
    if (path == null || _recentPicks.isEmpty) return 0;
    final now = captureByPath[path];
    var home = 0, away = 0;
    for (final pick in _recentPicks.reversed.take(8)) {
      if (now != null && pick.capturedAt != null) {
        if (now.difference(pick.capturedAt!).inMilliseconds.abs() > 180000) {
          continue;
        }
      } else if ((pick.frameIndex - currentIndex).abs() > 12) {
        continue;
      }
      if (pick.isHome) {
        home++;
      } else {
        away++;
      }
    }
    final total = home + away;
    if (total == 0) return 0;
    return (home - away) / total;
  }

  /// Select from an OCR / text-recognition suggestion.
  void selectPlayerFromTextRecognition(JerseyOcrSuggestion match) {
    final detail = match.matchKind == JerseyOcrMatchKind.jersey
        ? 'Jersey #${match.matchedText.trim()}'
        : 'Name “${match.matchedText.trim()}”';
    selectPlayer(
      match.player,
      isHome: match.isHome,
      source: PlayerInputSource.textRecognition,
      recognitionDetail: detail,
    );
  }

  bool get canUseLastCustomPlayer => lastCustomPlayerName.trim().isNotEmpty;

  void rememberLastCustomPlayer({
    required String fullName,
    String? jerseyNumber,
  }) {
    final name = fullName.trim();
    if (name.isEmpty) return;
    lastCustomPlayerName = name;
    lastCustomPlayerJersey = jerseyNumber?.trim() ?? '';
  }

  Player? findRosterPlayer({
    required bool isHome,
    required String fullName,
    String? jerseyNumber,
  }) {
    final name = fullName.trim();
    if (name.isEmpty) return null;
    final jersey = jerseyNumber?.trim();
    final jerseyKey = (jersey == null || jersey.isEmpty) ? null : jersey;
    final roster = isHome ? homeRoster : awayRoster;
    for (final player in roster) {
      if (player.fullName.trim() != name) continue;
      final playerJersey = (player.jerseyNumber ?? '').trim();
      final playerKey = playerJersey.isEmpty ? null : playerJersey;
      if (playerKey == jerseyKey) return player;
    }
    return null;
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
    final existing = findRosterPlayer(
      isHome: isHome,
      fullName: name,
      jerseyNumber: jerseyKey,
    );
    if (existing != null) {
      rememberLastCustomPlayer(fullName: name, jerseyNumber: jerseyKey);
      if (!isPlayerSelected(existing, isHome: isHome)) {
        selectPlayer(
          existing,
          isHome: isHome,
          source: PlayerInputSource.typed,
        );
      } else {
        notifyListeners();
      }
      return null;
    }
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
    rememberLastCustomPlayer(fullName: name, jerseyNumber: jerseyKey);
    // Always select the new custom name (don't toggle off if somehow present).
    final already = selectedPlayers.any(
      (row) => row.isHome == isHome && _samePlayer(row.player, player),
    );
    if (!already) {
      selectPlayer(
        player,
        isHome: isHome,
        source: PlayerInputSource.typed,
      );
    } else {
      notifyListeners();
    }
    _scheduleJerseyOcr();
    return null;
  }

  /// Adds/selects a typed custom player. When [pin] is true, also pins them.
  String? commitCustomPlayer({
    required bool isHome,
    required String fullName,
    String? jerseyNumber,
    bool pin = false,
  }) {
    final error = addCustomPlayer(
      isHome: isHome,
      fullName: fullName,
      jerseyNumber: jerseyNumber,
    );
    if (error != null) return error;
    if (!pin) return null;
    final player = findRosterPlayer(
      isHome: isHome,
      fullName: fullName,
      jerseyNumber: jerseyNumber,
    );
    if (player == null) return null;
    if (!isPlayerPinned(player, isHome: isHome)) {
      pinnedPlayer = RosterHit(player: player, isHome: isHome);
      notifyListeners();
    }
    return null;
  }

  /// Toggle pin for the typed custom player (commits first if needed).
  String? toggleCustomPlayerPin({
    required bool isHome,
    required String fullName,
    String? jerseyNumber,
  }) {
    final name = fullName.trim();
    if (name.isEmpty && lastCustomPlayerName.isEmpty) return null;
    final effectiveName = name.isEmpty ? lastCustomPlayerName : name;
    final effectiveJersey = name.isEmpty
        ? (lastCustomPlayerJersey.isEmpty ? null : lastCustomPlayerJersey)
        : jerseyNumber;
    final existing = findRosterPlayer(
      isHome: isHome,
      fullName: effectiveName,
      jerseyNumber: effectiveJersey,
    );
    if (existing != null && isPlayerPinned(existing, isHome: isHome)) {
      unpinPlayer();
      return null;
    }
    return commitCustomPlayer(
      isHome: isHome,
      fullName: effectiveName,
      jerseyNumber: effectiveJersey,
      pin: true,
    );
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
    final jerseyKey = _normalizeJerseyKey(jerseyNumber);
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
        selectedPlayers[i] = row.copyWith(player: updated);
      }
    }
    if (pinnedPlayer != null &&
        pinnedPlayer!.isHome == isHome &&
        _samePlayer(pinnedPlayer!.player, original)) {
      pinnedPlayer = pinnedPlayer!.copyWith(player: updated);
    }
    _syncPrimaryPlayer();
    manualCaptionOverride = null;
    notifyListeners();
    return null;
  }

  /// Drops [player] from the home or away roster for this session.
  ///
  /// A player with no jersey lives in the number view's "No number" band.
  /// Removing one clears every unnumbered player on that team, so the band
  /// goes away with them.
  void removePlayer({
    required bool isHome,
    required Player player,
  }) {
    final clearUnnumbered = !_hasRosterJersey(player);
    bool drop(Player candidate) {
      if (clearUnnumbered && !_hasRosterJersey(candidate)) return true;
      return _samePlayer(candidate, player);
    }

    final roster = isHome ? homeRoster : awayRoster;
    final next = [for (final item in roster) if (!drop(item)) item];
    if (isHome) {
      homeRoster = next;
    } else {
      awayRoster = next;
    }
    selectedPlayers.removeWhere(
      (row) => row.isHome == isHome && drop(row.player),
    );
    final pinned = pinnedPlayer;
    if (pinned != null && pinned.isHome == isHome && drop(pinned.player)) {
      pinnedPlayer = null;
    }
    manualCaptionOverride = null;
    _syncPrimaryPlayer();
    _dropTeammatesIfSubjectLeft();
    _syncKeywords();
    notifyListeners();
  }

  /// Jersey the number grid can place in a numbered row (0–99).
  bool _hasRosterJersey(Player player) {
    var raw = player.jerseyNumber?.trim() ?? '';
    while (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    final number = int.tryParse(raw);
    return number != null && number >= 0 && number <= 99;
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
    teamPlayersIsHome = null;
    selectedPlayers.clear();
    for (final row in players) {
      if (!isPlayerSelected(row.player, isHome: row.isHome)) {
        selectedPlayers.add(row);
      }
    }
    _syncPrimaryPlayer();
    _dropTeammatesIfSubjectLeft();
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
    // Paste replays the buttons that built the caption when they still match
    // this roster. Otherwise the copied text stays as a manual caption.
    // The copied byline names the source photographer — swap in this frame's
    // IPTC photographer so a shared moment keeps the right credit.
    final path = currentPath;
    if (path != null) {
      final fromFile = await photographerNameForPath(path);
      if (fromFile.isNotEmpty) {
        photographerName = fromFile;
        _photographerProvenance = _BylineProvenance.iptc;
      }
    }
    final clicks = payload.clicks;
    final applied = clicks != null && applyCaptionClicks(clicks);
    if (!applied) {
      manualCaptionOverride =
          CaptionTransferPayload.captionForDestinationPhotographer(
        caption: payload.caption,
        sourcePhotographer: payload.photographerName,
        destinationPhotographer: photographerName,
        removeDiacritics: captionTemplate.removeDiacritics,
      );
      personality = payload.personality;
      if (payload.keywords.isNotEmpty || showKeywordsField) {
        keywords = payload.keywords;
        _baseKeywordKeys
          ..clear()
          ..addAll(_parseMetadataList(keywords).map((e) => e.toLowerCase()));
        _managedKeywordKeys.clear();
      }
    }
    if (payload.headline.isNotEmpty || showHeadlineField) {
      headline = payload.headline;
    }
    metadataDirty = true;
    captionSelectionStarted = true;
    if (path != null) {
      if (applied && clicks != null) {
        _clicksByPath[path] = clicks;
        _restoreClicksOnOpen.add(path);
      } else {
        _clicksByPath.remove(path);
        _restoreClicksOnOpen.remove(path);
      }
    }
    notifyListeners();
  }

  /// Buttons behind the caption on [path]. The open picture uses the live
  /// buttons; other pictures use the clicks saved when you left them or pasted.
  CaptionClickSnapshot? clicksForTransfer(String path) {
    if (path == currentPath) {
      if (manualCaptionOverride != null) return null;
      return captionClicksForTransfer() ?? _clicksByPath[path];
    }
    return _clicksByPath[path];
  }

  /// Remember [clicks] on each pasted picture. A null snapshot clears them so
  /// a text-only paste does not resurrect old buttons.
  void rememberClicks(Iterable<String> paths, CaptionClickSnapshot? clicks) {
    final targets = paths.toList();
    for (final path in targets) {
      if (clicks == null) {
        _clicksByPath.remove(path);
        _restoreClicksOnOpen.remove(path);
      } else {
        _clicksByPath[path] = clicks;
        _restoreClicksOnOpen.add(path);
      }
    }
    final current = currentPath;
    if (clicks != null && current != null && targets.contains(current)) {
      applyCaptionClicks(clicks);
    }
  }

  void _rememberLeavingFrame(String? path) {
    if (path == null) return;
    if (manualCaptionOverride != null || !captionSelectionStarted) {
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
      return;
    }
    // A pin alone is the default for every picture, not this picture's buttons.
    if (!_frameHasUserClicks) {
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
      return;
    }
    final clicks = captionClicksForTransfer();
    if (clicks == null) {
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
      return;
    }
    _clicksByPath[path] = clicks;
    _restoreClicksOnOpen.add(path);
  }

  void _restoreRememberedClicks() {
    final path = currentPath;
    if (path == null || !_restoreClicksOnOpen.contains(path)) return;
    final stored = _clicksByPath[path];
    if (stored == null) return;
    applyCaptionClicks(stored);
  }

  /// True when this frame's buttons differ from the pins that return on every
  /// picture. Pin-only state is not stored, so a pin does not become a paste.
  bool get _frameHasUserClicks {
    if (teamPlayersIsHome != null || withTeammatesIsHome != null) return true;
    if (preGame || postGame) return true;
    if (celebrationType != null && celebrationType!.trim().isNotEmpty) {
      return true;
    }
    if (selectedBase != null && selectedBase!.trim().isNotEmpty) return true;
    if (rbi != 0) return true;
    if (customVerbPhrase.trim().isNotEmpty && !customVerbPinned) return true;
    if (selectedVerb != null && selectedVerb != pinnedVerb) return true;
    if (pinnedPlayer == null) return selectedPlayers.isNotEmpty;
    if (selectedPlayers.length != 1) return selectedPlayers.isNotEmpty;
    final only = selectedPlayers.first;
    return only.isHome != pinnedPlayer!.isHome ||
        !_samePlayer(only.player, pinnedPlayer!.player);
  }

  /// Buttons behind the caption currently on screen, when it was built from
  /// those buttons rather than typed over.
  CaptionClickSnapshot? captionClicksForTransfer() {
    if (manualCaptionOverride != null) return null;
    final players = <CaptionClickPlayer>[
      for (var i = 0; i < selectedPlayers.length; i++)
        CaptionClickPlayer(
          fullName: selectedPlayers[i].player.fullName,
          jerseyNumber: selectedPlayers[i].player.jerseyNumber,
          playerId: selectedPlayers[i].player.playerId,
          isHome: selectedPlayers[i].isHome,
          primary: i == 0,
        ),
    ];
    final custom = customVerbPhrase.trim();
    final verb = selectedVerb?.trim();
    final snapshot = CaptionClickSnapshot(
      players: players,
      verb: verb == null || verb.isEmpty ? null : verb,
      customVerb: custom,
      rbi: rbi,
      base: selectedBase,
      celebration: celebrationType,
      modifiers: {
        for (final entry in verbModifierSelections.entries)
          if (entry.value != null && entry.value!.trim().isNotEmpty)
            entry.key: entry.value!.trim(),
      },
      preGame: preGame,
      postGame: postGame,
      inning: inning,
      timingHalf: timingHalf,
      teamPlayersIsHome: teamPlayersIsHome,
      teamSubjectKind: teamPlayersIsHome == null ? null : teamSubjectKind.name,
      withTeammatesIsHome: withTeammatesIsHome,
    );
    return snapshot.hasButtons ? snapshot : null;
  }

  /// Press the copied buttons that still exist. Players and verbs that do not
  /// match this roster or catalog are left unselected.
  ///
  /// Returns false when nothing matched, leaving the current selection as it
  /// was.
  bool applyCaptionClicks(CaptionClickSnapshot clicks) {
    final nextPlayers = <RosterHit>[];
    RosterHit? primaryHit;
    for (final row in clicks.players) {
      final stub = Player(
        fullName: row.fullName,
        firstName: row.fullName.split(RegExp(r'\s+')).first,
        jerseyNumber: row.jerseyNumber,
        displayName: row.fullName,
        playerId: row.playerId,
      );
      final match = _findRosterPlayer(stub, isHome: row.isHome);
      if (match == null) continue;
      final already = nextPlayers.any(
        (item) => item.isHome == row.isHome && _samePlayer(item.player, match),
      );
      if (already) continue;
      final hit = RosterHit(player: match, isHome: row.isHome);
      nextPlayers.add(hit);
      if (row.primary && primaryHit == null) primaryHit = hit;
    }
    if (primaryHit != null) {
      final primaryAt = nextPlayers.indexOf(primaryHit);
      if (primaryAt > 0) {
        nextPlayers.removeAt(primaryAt);
        nextPlayers.insert(0, primaryHit);
      }
    }

    final custom = clicks.customVerb.trim();
    final verbKey = clicks.verb?.trim();
    final verbOk = custom.isEmpty &&
        verbKey != null &&
        verbKey.isNotEmpty &&
        verbDefinition(verbKey) != null;

    bool? teamSide;
    TeamSubjectKind? teamKind;
    if (clicks.teamPlayersIsHome != null) {
      final side = clicks.teamPlayersIsHome!;
      final team = side ? homeTeam : awayTeam;
      if (team.trim().isNotEmpty) {
        teamSide = side;
        teamKind = _teamSubjectKindFromName(clicks.teamSubjectKind);
      }
    }

    bool? teammatesSide;
    if (teamSide == null && clicks.withTeammatesIsHome != null) {
      final side = clicks.withTeammatesIsHome!;
      final team = side ? homeTeam : awayTeam;
      if (team.trim().isNotEmpty) teammatesSide = side;
    }

    final applied = nextPlayers.isNotEmpty ||
        verbOk ||
        custom.isNotEmpty ||
        teamSide != null ||
        teammatesSide != null;
    if (!applied) return false;

    selectedPlayers
      ..clear()
      ..addAll(nextPlayers);
    teamPlayersIsHome = teamSide;
    if (teamKind != null) teamSubjectKind = teamKind;
    withTeammatesIsHome = teammatesSide;
    _dropTeammatesIfSubjectLeft();

    if (custom.isNotEmpty) {
      final pinnedPhrase = customVerbPhrase.trim();
      if (customVerbPinned &&
          pinnedPhrase.isNotEmpty &&
          pinnedPhrase != custom) {
        lastCustomVerbPhrase = pinnedPhrase;
      }
      customVerbPhrase = custom;
      lastCustomVerbPhrase = custom;
      selectedVerb = null;
      celebrationType = null;
      verbModifierSelections.clear();
      rbi = 0;
      selectedBase = null;
    } else if (verbOk) {
      _stashCustomVerbIfNeeded();
      customVerbPhrase = '';
      selectedVerb = verbKey;
      _applyCopiedVerbExtras(verbKey, clicks);
      final category = _categoryForVerb(verbKey);
      if (category != null) verbCategory = category;
    } else {
      selectedVerb = null;
      if (!customVerbPinned) customVerbPhrase = '';
      celebrationType = null;
      verbModifierSelections.clear();
      rbi = 0;
      selectedBase = null;
    }

    preGame = clicks.preGame;
    postGame = clicks.postGame;
    if (preGame || postGame) {
      timingHalf = null;
    } else {
      final nextInning = clicks.inning;
      if (nextInning != null && nextInning > 0) inning = nextInning;
      timingHalf = clicks.timingHalf;
    }
    manualCaptionOverride = null;
    captionSelectionStarted = true;
    _syncPrimaryPlayer();
    _syncFirebarToSelection();
    _syncKeywords();
    _syncPersonality();
    return true;
  }

  void _applyCopiedVerbExtras(String verb, CaptionClickSnapshot clicks) {
    final groups = verbDefinition(verb)?.authoring.groups ?? const [];
    verbModifierSelections
      ..clear()
      ..addEntries(
        groups.map((group) => MapEntry(group.id, group.defaultOptionId)),
      );
    for (final group in groups) {
      final chosen = clicks.modifiers[group.id];
      if (chosen == null) continue;
      if (group.options.any((option) => option.id == chosen)) {
        verbModifierSelections[group.id] = chosen;
      }
    }
    rbi = _verbNeedsRbi(verb) ? clicks.rbi : 0;
    selectedBase = _verbNeedsBase(verb) ? clicks.base : null;
    celebrationType = null;
    final celebration = clicks.celebration?.trim();
    if (celebration != null &&
        celebration.isNotEmpty &&
        verbNeedsCelebration(verb) &&
        celebrationOptionsFor(verb).contains(celebration)) {
      celebrationType = celebration;
    }
  }

  TeamSubjectKind _teamSubjectKindFromName(String? raw) {
    for (final kind in TeamSubjectKind.values) {
      if (kind.name == raw) return kind;
    }
    return TeamSubjectKind.players;
  }

  void _syncFirebarToSelection() {
    _firebarCommitted.removeWhere(
      (item) =>
          item.kind == FirebarResultKind.player ||
          item.kind == FirebarResultKind.verb,
    );
    for (final row in selectedPlayers) {
      _firebarCommitted.add(
        FirebarResult.player(player: row.player, isHome: row.isHome),
      );
    }
    if (selectedVerb != null) {
      _firebarCommitted.add(FirebarResult.verb(selectedVerb));
    }
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
    final path = currentPath;
    if (path != null) {
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
    }
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
    final path = currentPath;
    if (path != null) {
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
    }
    captionSelectionStarted = false;
    selectedPlayers.clear();
    selectedPlayer = null;
    teamPlayersIsHome = null;
    withTeammatesIsHome = null;
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
    if (prefs == null || category == 'Favorites' || category == 'All') return;
    final order = {
      for (final entry in _verbCatalog.verbsByCategory.entries)
        if (entry.key != 'Favorites' && entry.key != 'All')
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
    if (!hasCaptionSubject) {
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
    // Team buttons ("All players" / the club name) count as a subject even
    // though no individual athlete is selected.
    if (!hasCaptionSubject) return originalCaption;
    return buildCaptionSentence();
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
    // Always tombstone so app-default / Firebase catalogs cannot resurrect it.
    await prefs.addDeletedVerb(verb, sport: sport);
    await prefs.removeVerbOverride(verb, sport: sport);
    if (definition.isCustom) {
      final customs = await prefs.getCustomVerbs(sport: sport)
        ..removeWhere((item) {
          final key = (item['key'] ?? item['label'] ?? '').toString();
          final label = item['label']?.toString() ?? '';
          final phrase = item['verbPhrase']?.toString() ?? '';
          final lower = verb.toLowerCase();
          return key == verb ||
              label == verb ||
              phrase == verb ||
              key.toLowerCase() == lower ||
              label.toLowerCase() == lower;
        });
      await prefs.saveCustomVerbs(customs, sport: sport);
    }
    final favorites = await prefs.getFavoriteVerbs(sport: sport)
      ..remove(verb)
      ..removeWhere((value) => value.toLowerCase() == verb.toLowerCase());
    await prefs.saveFavoriteVerbs(favorites, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  Future<void> moveVerb(String verb, String category, int index) async {
    final prefs = _prefs;
    if (prefs == null || !_verbCatalog.byKey.containsKey(verb)) return;
    if (category == 'All') return;
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
        if (entry.key != 'Favorites' && entry.key != 'All')
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
        final pins = await prefs.getVerbCategoryOverrides(sport: sport);
        final factoryCategory =
            SportVerbCategories.categoryForVerb(verb, sport: sport);
        if (factoryCategory != null && factoryCategory == category) {
          pins.remove(verb);
        } else {
          pins[verb] = category;
        }
        await prefs.saveVerbCategoryOverrides(pins, sport: sport);
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
    final cleaned = order
        .where((category) => category != 'Favorites' && category != 'All')
        .toList();
    await _prefs?.saveCategoryOrder(cleaned, sport: sport);
    await _loadVerbCatalog();
    notifyListeners();
  }

  /// Move [from] to the slot occupied by [to]. Favorites stays first and All
  /// stays last; neither can be dragged.
  Future<void> reorderVerbCategory(String from, String to) async {
    if (from == to) return;
    if (from == 'Favorites' ||
        from == 'All' ||
        to == 'Favorites' ||
        to == 'All') {
      return;
    }
    final order = verbCategories
        .where((category) => category != 'Favorites' && category != 'All')
        .toList();
    final fromIndex = order.indexOf(from);
    final toIndex = order.indexOf(to);
    if (fromIndex < 0 || toIndex < 0) return;
    order.removeAt(fromIndex);
    order.insert(toIndex, from);
    await saveCategoryOrder(order);
  }

  /// Paint [bundle] on the caption verb list before prefs finish writing.
  void showVerbBundle(Map<String, dynamic> bundle) {
    _verbPreviewToken++;
    _verbCatalog = EffectiveVerbRepository.fromBundle(sport: sport, bundle: bundle);
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
    notifyListeners();
  }

  Future<void> reloadVerbCatalog() async {
    final token = _verbPreviewToken;
    await _loadVerbCatalog();
    if (token != _verbPreviewToken) return;
    notifyListeners();
  }

  /// Disk now matches the latest editor bundle. Reload the caption verb list.
  Future<void> commitVerbBundleFromDisk() => reloadVerbCatalog();

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
        if (entry.key != 'Favorites' && entry.key != 'All')
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
    if (!VerbSubOptions.isBaseballSport(sport)) return false;
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
    return VerbSubOptions.isBaseballSport(sport) &&
        CaptionV2CaptionDomain.runningVerbs.contains(verb);
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
    timingByQuarter = false;
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

  void setTimingByQuarter(bool quarters) {
    if (!supportsTimingHalves) return;
    timingByQuarter = quarters;
    if (quarters) {
      if (timingHalf == '1H') {
        inning = 1;
      } else if (timingHalf == '2H') {
        inning = 3;
      }
      timingHalf = null;
    } else if (inning > timingRegulationCount) {
      timingHalf = null;
    } else {
      timingHalf = inning <= 2 ? '1H' : '2H';
      inning = timingHalf == '1H' ? 1 : 2;
    }
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
    firebarMenuIndex = 0;
    firebarChipCursor = -1;
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
      if (_firebarOptionKind == FirebarOptionKind.jerseySide) {
        final side = _jerseySideAnswer(q);
        if (side != null) {
          _applyJerseySideChoice(isHome: side);
          return;
        }
        // The prompt clears the field, so the next digit continues a longer
        // number (`9` then `0` is `90`) instead of answering home or visitor.
        final continued = _jerseySideDigitContinuation(q);
        if (continued != null) {
          _clearFirebarOptions();
          setSearchQuery(continued);
          return;
        }
        if (RegExp(r'^\d+$').hasMatch(q.trim())) {
          notifyListeners();
          return;
        }
      }
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
    if (open && hideFirebar) return;
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
      if (_firebarOptionKind == FirebarOptionKind.jerseySide) {
        _jerseySideChoiceArmed = true;
      }
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

  /// Same jersey on both teams, so the two player chips are a home/visitor choice.
  bool get firebarJerseySideChoiceOpen {
    if (!searchOpen || firebarOptions.isNotEmpty) return false;
    return _pendingJerseySideFor(_normalizedFirebarQuery) != null;
  }

  /// Pick the home or visitor chip for the number just typed.
  void chooseFirebarJerseySide({required bool isHome}) {
    final pending = _pendingJerseySideFor(_normalizedFirebarQuery);
    if (pending == null) return;
    _pendingJerseySide = pending;
    _applyJerseySideChoice(isHome: isHome);
  }

  /// Last committed chip is a player, so an empty query suggests verbs.
  bool get firebarMenuPrefersVerbs {
    if (_firebarCommitted.isEmpty) return false;
    return _firebarCommitted.last.kind == FirebarResultKind.player;
  }

  /// Sticky menu title: suggested verbs, players, a jersey, or matches.
  String get firebarMenuLabel {
    final query = searchQuery.trim();
    if (query.isEmpty) {
      return firebarMenuPrefersVerbs ? 'Suggested verbs' : 'Players';
    }
    if (RegExp(r'^\d+$').hasMatch(query)) return 'Jersey #$query';
    return 'Matches';
  }

  /// Dropdown opens once a number or verb text is typed. An empty field stays closed.
  bool get firebarMenuOpen {
    if (!searchOpen || firebarOptions.isNotEmpty) return false;
    return _normalizeFirebarText(searchQuery).isNotEmpty;
  }

  /// Up to 12 roster and verb matches for the autocomplete menu.
  List<FirebarResult> get firebarMenuResults {
    if (!firebarMenuOpen) return const [];
    final preferVerbs = firebarMenuPrefersVerbs;
    final normalized = _normalizedFirebarQuery;
    final compound = _parseFirebarJerseyVerbCompound(normalized);
    final jerseyTokens =
        compound?.jerseys ?? _parseFirebarJerseyTokens(normalized);

    // `3 battles` / `88 92 look` — menu uses the same jersey+verb split as the
    // roster and verb columns, not the full typed string as one blob.
    if (jerseyTokens != null) {
      final hits = <_FirebarMenuHit>[];
      for (final result in [...firebarHomeResults, ...firebarAwayResults]) {
        hits.add(
          _FirebarMenuHit(
            result: result,
            score: 100 + (preferVerbs ? 0 : 15),
            name: result.player?.fullName ?? '',
          ),
        );
      }
      if (compound != null) {
        final verbQuery = compound.verbQuery;
        for (final result in firebarVerbResults) {
          final label = verbDefinition(result.verbKey ?? '')?.label ??
              result.verbKey ??
              '';
          var score = _firebarMenuTextScore(label, verbQuery);
          if (score < 0) score = 70;
          hits.add(
            _FirebarMenuHit(
              result: result,
              score: score + (preferVerbs ? 15 : 0),
              name: label,
            ),
          );
        }
      }
      hits.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return [
        for (final hit in hits.take(12)) hit.result,
      ];
    }

    final query = _firebarFocusedQuery;
    final sideMatch = RegExp(r'^([hv])(\d+)$').firstMatch(query);
    final digitQuery = sideMatch?.group(2) ??
        (RegExp(r'^\d+$').hasMatch(query) ? query : null);
    final hits = <_FirebarMenuHit>[];
    if (digitQuery != null) {
      final side = sideMatch?.group(1);
      for (final result in _firebarCatalogPlayers()) {
        if (side == 'h' && result.isHome != true) continue;
        if (side == 'v' && result.isHome != false) continue;
        final jersey = (result.player?.jerseyNumber ?? '').trim();
        final score = jersey == digitQuery
            ? 100
            : jersey.startsWith(digitQuery)
                ? 60
                : -1;
        if (score < 0) continue;
        hits.add(
          _FirebarMenuHit(
            result: result,
            score: score + (preferVerbs ? 0 : 15),
            name: result.player?.fullName ?? '',
          ),
        );
      }
    } else {
      for (final result in _firebarCatalogPlayers()) {
        final player = result.player;
        if (player == null) continue;
        final nameScore = _firebarMenuTextScore(player.fullName, query);
        final teamScore = _firebarMenuTextScore(
          teamNameLabel(isHome: result.isHome == true),
          query,
        );
        final score = nameScore > teamScore ? nameScore : teamScore;
        if (score < 0) continue;
        hits.add(
          _FirebarMenuHit(
            result: result,
            score: score + (preferVerbs ? 0 : 15),
            name: player.fullName,
          ),
        );
      }
      for (final result in _firebarCatalogVerbs()) {
        final label =
            verbDefinition(result.verbKey ?? '')?.label ?? result.verbKey ?? '';
        final score = _firebarMenuTextScore(label, query);
        if (score < 0) continue;
        hits.add(
          _FirebarMenuHit(
            result: result,
            score: score + (preferVerbs ? 15 : 0),
            name: label,
          ),
        );
      }
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return [
      for (final hit in hits.take(12)) hit.result,
    ];
  }

  FirebarResult? get firebarMenuSelection {
    final results = firebarMenuResults;
    if (results.isEmpty) return null;
    final index = firebarMenuIndex.clamp(0, results.length - 1);
    return results[index];
  }

  /// When the typed text can only be one verb (or one row), the finished word.
  /// Enter still confirms it. Null while more than one verb is possible.
  String? get firebarWordCompletion {
    final result = firebarWordCompletionResult;
    if (result == null) return null;
    return _finishUniqueWord(
      searchQuery.trimRight(),
      _firebarMenuLabelText(result),
    );
  }

  /// The single verb the typed text can be, even if player rows are also listed.
  FirebarResult? get firebarWordCompletionResult {
    if (!firebarMenuOpen) return null;
    final typed = searchQuery.trimRight();
    if (typed.isEmpty) return null;
    if (RegExp(r'^([hv])?\d+$').hasMatch(_normalizeFirebarText(typed))) {
      return null;
    }
    final results = firebarMenuResults;
    final verbs = results
        .where((result) => result.kind == FirebarResultKind.verb)
        .toList(growable: false);
    if (verbs.length == 1) return verbs.single;
    if (results.length == 1) return results.single;
    return null;
  }

  String _firebarMenuLabelText(FirebarResult result) {
    if (result.kind == FirebarResultKind.player) {
      return result.player?.fullName ?? '';
    }
    final key = result.verbKey ?? '';
    return verbDefinition(key)?.label ?? key;
  }

  static String? _finishUniqueWord(String typed, String label) {
    if (label.isEmpty ||
        !label.toLowerCase().startsWith(typed.toLowerCase())) {
      return null;
    }
    final rest = label.substring(typed.length);
    if (rest.isEmpty) return null;
    if (rest.startsWith(' ')) {
      final next = rest.substring(1);
      final split = next.indexOf(' ');
      final word = split < 0 ? next : next.substring(0, split);
      if (word.isEmpty) return null;
      return '$typed $word';
    }
    final split = rest.indexOf(' ');
    final suffix = split < 0 ? rest : rest.substring(0, split);
    if (suffix.isEmpty) return null;
    return typed + suffix;
  }

  void moveFirebarMenu(int delta) {
    final results = firebarMenuResults;
    if (delta == 0 || results.isEmpty) return;
    final length = results.length;
    final current = firebarMenuIndex.clamp(0, length - 1);
    firebarMenuIndex = (current + delta) % length;
    if (firebarMenuIndex < 0) firebarMenuIndex += length;
    firebarChipCursor = -1;
    notifyListeners();
  }

  void hoverFirebarMenu(int index) {
    final results = firebarMenuResults;
    if (index < 0 || index >= results.length || index == firebarMenuIndex) {
      return;
    }
    firebarMenuIndex = index;
    firebarChipCursor = -1;
    notifyListeners();
  }

  /// Enter or a menu click. Tab and Space leave the query as typed.
  void commitFirebarMenu() {
    final compound = _parseFirebarJerseyVerbCompound(_normalizedFirebarQuery);
    if (compound != null) {
      // Prefer the highlighted menu row when home/away or verbs collide.
      final menuSel = firebarMenuSelection;
      if (menuSel != null) {
        final index = firebarOrderedResults
            .indexWhere((result) => result.key == menuSel.key);
        if (index >= 0) firebarSelectionIndex = index;
      }
      _commitFirebarJerseyVerbCompound(compound);
      firebarMenuIndex = 0;
      firebarChipCursor = -1;
      return;
    }
    final selected = firebarMenuSelection;
    if (selected != null) {
      commitFirebarResult(selected);
      firebarMenuIndex = 0;
      firebarChipCursor = -1;
      return;
    }
    final typed = searchQuery.trim();
    if (typed.isEmpty) return;
    commitFirebarResult(FirebarResult.verb(typed));
    firebarMenuIndex = 0;
    firebarChipCursor = -1;
  }

  /// First Backspace on an empty field outlines the last chip. The next one
  /// removes it.
  void backspaceFirebarChip() {
    if (searchQuery.isNotEmpty || _firebarCommitted.isEmpty) return;
    if (firebarChipCursor >= 0 &&
        firebarChipCursor < _firebarCommitted.length) {
      final chip = _firebarCommitted[firebarChipCursor];
      firebarChipCursor = -1;
      removeFirebarChip(chip);
      return;
    }
    firebarChipCursor = _firebarCommitted.length - 1;
    notifyListeners();
  }

  /// ← / → across committed chips while the field is empty.
  void moveFirebarChipCursor(int delta) {
    if (delta == 0 ||
        searchQuery.trim().isNotEmpty ||
        _firebarCommitted.isEmpty) {
      return;
    }
    if (delta > 0) {
      if (firebarChipCursor < 0) return;
      firebarChipCursor = firebarChipCursor >= _firebarCommitted.length - 1
          ? -1
          : firebarChipCursor + 1;
    } else {
      firebarChipCursor = firebarChipCursor < 0
          ? _firebarCommitted.length - 1
          : (firebarChipCursor - 1).clamp(0, _firebarCommitted.length - 1);
    }
    notifyListeners();
  }

  List<FirebarResult> _firebarCatalogPlayers() {
    return [
      for (final player in homeRoster)
        FirebarResult.player(player: player, isHome: true),
      for (final player in awayRoster)
        FirebarResult.player(player: player, isHome: false),
    ];
  }

  List<FirebarResult> _firebarCatalogVerbs() {
    final seen = <String>{};
    final results = <FirebarResult>[];
    for (final category in verbCategories) {
      for (final verb
          in verbDefinitionsByCategory[category] ?? const <EffectiveVerb>[]) {
        if (!seen.add(verb.key)) continue;
        results.add(FirebarResult.verb(verb.key));
      }
    }
    return results;
  }

  /// 80 name prefix, 70 word prefix, 40 contains, 35 initials, else no match.
  static int _firebarMenuTextScore(String value, String query) {
    final name = _normalizeFirebarText(value);
    if (name.isEmpty || query.isEmpty) return -1;
    if (name.startsWith(query)) return 80;
    final words = name
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.any((word) => word.startsWith(query))) return 70;
    if (name.contains(query)) return 40;
    if (words.isEmpty) return -1;
    final initials = words.map((word) => word[0]).join();
    if (initials.startsWith(query)) return 35;
    return -1;
  }

  /// Move between the two same-number players, not the rest of the Firebar list.
  void moveFirebarJerseySide(int delta) {
    if (delta == 0 || !firebarJerseySideChoiceOpen) {
      moveFirebarSelection(delta);
      return;
    }
    final players = firebarOrderedResults
        .where((result) => result.kind == FirebarResultKind.player)
        .toList(growable: false);
    if (players.length < 2) {
      moveFirebarSelection(delta);
      return;
    }
    final currentKey = firebarSelectedResult?.key;
    var index = players.indexWhere((result) => result.key == currentKey);
    if (index < 0) index = 0;
    final next = (index + delta).clamp(0, players.length - 1);
    if (next == index) return;
    firebarSelectionIndex = firebarOrderedResults
        .indexWhere((result) => result.key == players[next].key);
    notifyListeners();
  }

  void commitSelectedFirebarResult() {
    if (firebarJerseySideChoiceOpen) {
      final selected = firebarSelectedResult;
      if (selected?.kind == FirebarResultKind.player &&
          selected?.isHome != null) {
        chooseFirebarJerseySide(isHome: selected!.isHome!);
        return;
      }
    }
    if (firebarOptions.isNotEmpty) {
      if (_firebarOptionKind == FirebarOptionKind.jerseySide) {
        _commitJerseySideAnswer();
        return;
      }
      final options = filteredFirebarOptions;
      if (options.isEmpty) return;
      chooseFirebarOption(
        options[firebarOptionIndex.clamp(0, options.length - 1)],
      );
      return;
    }
    if (_beginJerseySidePrompt(searchQuery)) return;
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
  /// FTP (or Save when [transmit] is false) from the destination prompt.
  /// Returns true if save or FTP was already kicked off, or follow-up chips
  /// need a choice; false if the caller should still save or FTP.
  bool commitFirebarForShiftEnterSave({bool transmit = false}) {
    if (firebarShowingDestinationOptions) {
      final options = filteredFirebarOptions.isNotEmpty
          ? filteredFirebarOptions
          : firebarOptions;
      FirebarOption? chosen;
      for (final option in options) {
        final isFtp = option.transmit == true;
        if (transmit ? isFtp : !isFtp) {
          chosen = option;
          break;
        }
      }
      chooseFirebarOption(chosen ?? options.first);
      return true;
    }
    if (firebarCanQuickSavePlayer) {
      commitSelectedFirebarResult();
      return false;
    }
    if (firebarCanQuickSaveVerb) {
      commitSelectedFirebarResult();
      // Verb commit may open RBI/base/celebration chips — wait for those.
      // Destination Save/FTP chips are cleared so the caller still FTPs
      // (or saves when FTP mode is off), matching jersey quick-save.
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
        firebarMenuIndex = 0;
        firebarChipCursor = -1;
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
    firebarMenuIndex = 0;
    firebarChipCursor = -1;
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
    } else if (jerseyTokens.any(
      (token) =>
          token.side == null && _jerseyNumberIsOnlySideAmbiguous(token.jersey),
    )) {
      // Same number on home and visitor — wait for h/v. Don't pick a side.
      previewTargets = null;
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
    if (jerseyMatch.group(1) == null &&
        _jerseyNumberIsOnlySideAmbiguous(jersey)) {
      return null;
    }
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
      } else if (token.side == null &&
          _jerseyNumberIsOnlySideAmbiguous(token.jersey)) {
        return null;
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
      // A committed chip is a real pick. Clearing the search preview must
      // not drop that player while the chip stays on the Firebar.
      return keys.contains(candidate.key) &&
          !_firebarCommitted.any((item) => item.key == candidate.key);
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
      // Leave the field open so another jersey can be added after the verb.
      // Save and FTP stay on ⌘S and ⌘↵.
      _clearFirebarOptions();
      return;
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

    if (kind == FirebarOptionKind.jerseySide) {
      final isHome = option.jerseyIsHome;
      if (isHome == null) return;
      _applyJerseySideChoice(isHome: isHome);
      return;
    }

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
      _clearFirebarOptions();
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
    if (transmit) unawaited(transmitPath(path));
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
    _pendingJerseySide = null;
    _jerseySideChoiceArmed = false;
  }

  /// Exact jersey on one home player and one visitor.
  ///
  /// A longer number that starts with the same digits (`9` and `90`) does not
  /// skip the question. The next digit continues that longer number.
  bool _jerseyNumberIsOnlySideAmbiguous(String jersey) {
    var homeExact = 0;
    var awayExact = 0;
    for (final player in homeRoster) {
      if ((player.jerseyNumber ?? '').trim() == jersey) homeExact++;
    }
    for (final player in awayRoster) {
      if ((player.jerseyNumber ?? '').trim() == jersey) awayExact++;
    }
    return homeExact == 1 && awayExact == 1;
  }

  bool _rosterHasJerseyPrefix(String prefix) {
    bool hit(List<Player> roster) {
      for (final player in roster) {
        final number = (player.jerseyNumber ?? '').trim();
        if (number.startsWith(prefix)) return true;
      }
      return false;
    }

    return hit(homeRoster) || hit(awayRoster);
  }

  /// Digits typed while Home / Visitor is showing, appended to the number
  /// that opened the prompt.
  String? _jerseySideDigitContinuation(String raw) {
    final pending = _pendingJerseySide;
    if (pending == null) return null;
    final extra = raw.trim();
    if (!RegExp(r'^\d+$').hasMatch(extra)) return null;
    final next = '${pending.jersey}$extra';
    if (!_rosterHasJerseyPrefix(next)) return null;
    return [
      if (pending.prefix.isNotEmpty) pending.prefix,
      next,
      if (pending.suffix.isNotEmpty) pending.suffix,
    ].join(' ');
  }

  _PendingJerseySideQuery? _pendingJerseySideFor(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final prior = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final match =
          _firebarJerseyTokenPattern.firstMatch(parts[i].toLowerCase());
      if (match == null) return null;
      final side = match.group(1);
      final jersey = match.group(2)!;
      if (side == null && _jerseyNumberIsOnlySideAmbiguous(jersey)) {
        return _PendingJerseySideQuery(
          prefix: prior.join(' '),
          jersey: jersey,
          suffix: parts.sublist(i + 1).join(' '),
        );
      }
      prior.add(parts[i]);
    }
    return null;
  }

  /// Shows Home / Visitor chips and clears the field so the next key is the answer.
  bool _beginJerseySidePrompt(String raw) {
    if (!searchOpen) return false;
    final pending = _pendingJerseySideFor(raw);
    if (pending == null) return false;
    _clearFirebarAutoPlayerPreview();
    _clearFirebarVerbPreview();
    _pendingJerseySide = pending;
    firebarOptionPrompt = 'Which team for #${pending.jersey}?';
    _firebarOptionKind = FirebarOptionKind.jerseySide;
    firebarOptions = const [
      FirebarOption('h', jerseyIsHome: true),
      FirebarOption('v', jerseyIsHome: false),
    ];
    firebarOptionIndex = 0;
    _jerseySideChoiceArmed = false;
    searchQuery = '';
    firebarSelectionIndex = -1;
    notifyListeners();
    return true;
  }

  /// `h` / `home` pick home. `v` / `visitor` / `away` pick the visitor.
  bool? _jerseySideAnswer(String raw) {
    final answer = _normalizeFirebarText(raw);
    if (answer.isEmpty) return null;
    switch (answer) {
      case 'h':
      case 'home':
        return true;
      case 'v':
      case 'visitor':
      case 'away':
        return false;
    }
    final filtered = filteredFirebarOptions;
    if (filtered.length == 1) return filtered.single.jerseyIsHome;
    return null;
  }

  void _commitJerseySideAnswer() {
    final side = _jerseySideAnswer(searchQuery);
    if (side != null) {
      _applyJerseySideChoice(isHome: side);
      return;
    }
    final options = filteredFirebarOptions;
    if (options.isEmpty) return;
    final chosen = options[firebarOptionIndex.clamp(0, options.length - 1)];
    final isHome = chosen.jerseyIsHome;
    if (isHome == null) return;
    _applyJerseySideChoice(isHome: isHome);
  }

  void _applyJerseySideChoice({required bool isHome}) {
    final pending = _pendingJerseySide;
    _clearFirebarOptions();
    if (pending == null) {
      searchQuery = '';
      notifyListeners();
      return;
    }
    final roster = isHome ? homeRoster : awayRoster;
    Player? found;
    for (final player in roster) {
      if ((player.jerseyNumber ?? '').trim() == pending.jersey) {
        found = player;
        break;
      }
    }
    if (found != null) {
      // Enter (or h/v) commits the player so the chip stays after the field clears.
      commitFirebarResult(
        FirebarResult.player(player: found, isHome: isHome),
      );
    }
    final rest = [
      if (pending.prefix.trim().isNotEmpty) pending.prefix.trim(),
      if (pending.suffix.trim().isNotEmpty) pending.suffix.trim(),
    ].join(' ');
    if (rest.isEmpty) return;
    setSearchQuery(rest);
  }

  void toggleSort() {
    cycleRosterSortField();
  }

  /// Cycles # → First → Last → # (direction unchanged).
  void cycleRosterSortField() {
    const order = RosterSortMode.values;
    final index = order.indexOf(rosterSort);
    _applyRosterSort(order[(index + 1) % order.length], rosterSortAscending);
  }

  /// Steps the sort field without wrapping. Negative moves toward jersey number.
  void stepRosterSortField(int delta) {
    if (delta == 0) return;
    const order = RosterSortMode.values;
    final index = order.indexOf(rosterSort);
    final next = (index + delta).clamp(0, order.length - 1);
    if (next == index) return;
    _applyRosterSort(order[next], rosterSortAscending);
  }

  /// Toggles ascending ↔ descending without changing the sort field.
  void toggleRosterSortDirection() {
    _applyRosterSort(rosterSort, !rosterSortAscending);
  }

  void setRosterSortAscending(bool ascending) {
    if (rosterSortAscending == ascending) return;
    _applyRosterSort(rosterSort, ascending);
  }

  void resetRosterSort() {
    if (rosterSort == RosterSortMode.number && rosterSortAscending) return;
    _applyRosterSort(RosterSortMode.number, true);
  }

  void _applyRosterSort(RosterSortMode mode, bool ascending) {
    rosterSort = mode;
    rosterSortAscending = ascending;
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
      playerLabel: hasCaptionSubject ? playerChipLabel : null,
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
      if (e.key == 'Favorites' || e.key == 'All') continue;
      if (e.value.contains(verb)) return e.key;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void goToIndex(int index, {bool keepSearchOpen = false}) {
    if (imagePaths.isEmpty) return;
    _rememberLeavingFrame(currentPath);
    currentIndex = index.clamp(0, imagePaths.length - 1);
    _clearCaptionSelection();
    _restoreRememberedClicks();
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
    _schedulePreviewWarmup();
    unawaited(_refreshFrameIptc());
    // Already read this frame (preload or an earlier visit) — show it.
    // Only hit Vision when this photo has never been scanned.
    if (!_applyCachedFrameOcr()) {
      _scheduleJerseyOcr();
    }
  }

  /// Paint the current frame's cached OCR without a new Vision pass.
  bool _applyCachedFrameOcr() {
    if (!jerseyOcrEnabled) return false;
    final path = currentPath;
    if (path == null) return false;
    final hits = _cachedFullFrameOcr(path);
    if (hits == null) return false;
    _jerseyOcrTimer?.cancel();
    _jerseyOcrTimer = null;
    jerseyOcrHits = hits;
    jerseySuggestions = _matchJerseyOcrHits(hits);
    jerseyOcrBusy = false;
    notifyListeners();
    return true;
  }

  List<JerseyOcrHit>? _cachedFullFrameOcr(String path) {
    final direct = _jerseyOcrByPath[path];
    if (direct != null) return direct;
    for (final entry in _jerseyOcrCache.entries) {
      if (!entry.key.startsWith('$path|')) continue;
      if (!entry.key.contains('|full|')) continue;
      _jerseyOcrByPath[path] = entry.value;
      return entry.value;
    }
    return null;
  }

  void nextFrame({bool keepSearchOpen = false}) =>
      goToIndex(currentIndex + 1, keepSearchOpen: keepSearchOpen);
  void prevFrame({bool keepSearchOpen = false}) =>
      goToIndex(currentIndex - 1, keepSearchOpen: keepSearchOpen);

  /// Re-read the current frame after an external IPTC or file operation.
  Future<void> refreshCurrentFrameMetadata() => _refreshFrameIptc();

  // ---------------------------------------------------------------------------
  // Jersey / name OCR suggestions
  // ---------------------------------------------------------------------------

  void _clearJerseyOcrState({bool clearCache = false}) {
    _jerseyOcrTimer?.cancel();
    _jerseyOcrTimer = null;
    _jerseyOcrToken++;
    jerseySuggestions = const [];
    jerseyOcrHits = const [];
    jerseyOcrBusy = false;
    if (clearCache) {
      _jerseyOcrCache.clear();
      _jerseyOcrByPath.clear();
    }
  }

  void _invalidateJerseyOcrCacheFor(String path) {
    _jerseyOcrCache.removeWhere((key, _) => key.startsWith('$path|'));
    _jerseyOcrByPath.remove(path);
  }

  void _onJerseyOcrPreferenceChanged() {
    unawaited(_refreshJerseyOcrEnabled());
  }

  void _onApplicationModesChanged() {
    unawaited(reloadApplicationModes());
  }

  /// Reloads the preference gate. OCR is off by default; macOS only.
  Future<void> _refreshJerseyOcrEnabled() async {
    final prefOn = await _prefs?.getJerseyOcrEnabled() ?? false;
    final next = prefOn && JerseyOcrChannel.supported;
    final prefChanged = prefOn != jerseyOcrPreferenceEnabled;
    jerseyOcrPreferenceEnabled = prefOn;
    if (next == jerseyOcrEnabled) {
      if (!next &&
          (jerseySuggestions.isNotEmpty ||
              jerseyOcrHits.isNotEmpty ||
              jerseyOcrBusy)) {
        _clearJerseyOcrState();
        notifyListeners();
      } else if (prefChanged) {
        notifyListeners();
      }
      return;
    }
    jerseyOcrEnabled = next;
    if (!next) {
      _clearJerseyOcrState();
      notifyListeners();
      return;
    }
    notifyListeners();
    _scheduleJerseyOcr();
    _kickJerseyOcrPrescan();
  }

  /// Header toggle; effective OCR also needs macOS.
  Future<void> setJerseyOcrPreferenceEnabled(bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    jerseyOcrPreferenceEnabled = enabled;
    notifyListeners();
    await prefs.saveJerseyOcrEnabled(enabled);
  }

  /// Debounced auto-scan of the current frame for jersey numbers + names.
  void _scheduleJerseyOcr() {
    if (!jerseyOcrEnabled) {
      if (jerseySuggestions.isNotEmpty ||
          jerseyOcrHits.isNotEmpty ||
          jerseyOcrBusy) {
        jerseySuggestions = const [];
        jerseyOcrHits = const [];
        jerseyOcrBusy = false;
        notifyListeners();
      }
      return;
    }

    _jerseyOcrTimer?.cancel();
    // Drop stale matches immediately when the frame changes.
    if (jerseySuggestions.isNotEmpty || jerseyOcrHits.isNotEmpty) {
      jerseySuggestions = const [];
      jerseyOcrHits = const [];
      notifyListeners();
    }

    _jerseyOcrTimer = Timer(const Duration(milliseconds: 180), () {
      _jerseyOcrTimer = null;
      unawaited(runOcrTestScan(force: false));
    });
  }

  /// Manual / auto OCR on the current frame (numbers + names). macOS only.
  ///
  /// When [regionOfInterest] is set (loupe), Vision scans only that crop.
  /// Requires the Jersey OCR preference enabled.
  Future<OcrScanResult> runOcrTestScan({
    bool force = true,
    JerseyOcrRegion? regionOfInterest,
  }) async {
    if (!jerseyOcrEnabled) {
      jerseySuggestions = const [];
      jerseyOcrHits = const [];
      jerseyOcrBusy = false;
      notifyListeners();
      return OcrScanResult(
        supported: JerseyOcrChannel.supported,
        hits: const [],
        matches: const [],
      );
    }

    final path = currentPath;
    final isLoupe = regionOfInterest != null;
    // A loupe pass rides alongside the frame scan: it only cancels an older
    // loupe pass, never the frame scan (and a frame change cancels both).
    final token = isLoupe ? _jerseyOcrToken : ++_jerseyOcrToken;
    final loupeToken = isLoupe ? ++_loupeOcrToken : _loupeOcrToken;
    bool stale() =>
        token != _jerseyOcrToken || (isLoupe && loupeToken != _loupeOcrToken);
    if (path == null) {
      jerseySuggestions = const [];
      jerseyOcrHits = const [];
      jerseyOcrBusy = false;
      notifyListeners();
      return const OcrScanResult(
        supported: true,
        hits: [],
        matches: [],
      );
    }

    int mtimeMs = 0;
    try {
      mtimeMs = (await File(path).lastModified()).millisecondsSinceEpoch;
    } catch (_) {}
    if (stale()) {
      return OcrScanResult(
        supported: true,
        hits: jerseyOcrHits,
        matches: jerseySuggestions,
      );
    }

    final customWords = _ocrCustomWords();
    final roiKey = regionOfInterest == null
        ? 'full'
        : '${regionOfInterest.x.toStringAsFixed(3)},'
            '${regionOfInterest.y.toStringAsFixed(3)},'
            '${regionOfInterest.width.toStringAsFixed(3)},'
            '${regionOfInterest.height.toStringAsFixed(3)}';
    final sportKey = sport.trim().toLowerCase();
    final cacheKey = _jerseyOcrCacheKey(
      path: path,
      mtimeMs: mtimeMs,
      roiKey: roiKey,
      sportKey: sportKey,
      customWords: customWords,
    );
    late final List<JerseyOcrHit> hits;
    final cached = force
        ? null
        : (isLoupe ? _jerseyOcrCache[cacheKey] : _cachedFullFrameOcr(path));
    if (cached != null) {
      hits = cached;
    } else {
      _jerseyOcrInflight++;
      jerseyOcrBusy = true;
      notifyListeners();
      try {
        hits = await JerseyOcrChannel.recognize(
          path: path,
          customWords: customWords,
          regionOfInterest: regionOfInterest,
          sport: sportKey,
        );
      } finally {
        if (_jerseyOcrInflight > 0) _jerseyOcrInflight--;
      }
      if (stale()) {
        if (_jerseyOcrInflight == 0 && jerseyOcrBusy) {
          jerseyOcrBusy = false;
          notifyListeners();
        }
        return OcrScanResult(
          supported: true,
          hits: jerseyOcrHits,
          matches: jerseySuggestions,
        );
      }
      _putJerseyOcrCache(cacheKey, hits);
    }

    // Frame and loupe reads live in one list so neither wipes the other.
    //  • Frame scan: replaces earlier frame reads, keeps loupe reads.
    //  • Loupe scan: adds to the frame reads; only an older loupe read of
    //    the same spot is superseded (the fresh focused pass is better).
    final List<JerseyOcrHit> combined;
    if (!isLoupe) {
      combined = [
        for (final prior in jerseyOcrHits)
          if (prior.region == 'loupe') prior,
        ...hits,
      ];
    } else {
      final kept = <JerseyOcrHit>[
        for (final prior in jerseyOcrHits)
          if (!(prior.region == 'loupe' &&
              _hitCenterInside(prior, regionOfInterest, pad: 1.6)))
            prior,
      ];
      // Bound accumulation from a long hover session: drop oldest loupe reads.
      var loupeCount = kept.where((h) => h.region == 'loupe').length;
      if (loupeCount > 160) {
        kept.removeWhere((h) {
          if (loupeCount <= 160 || h.region != 'loupe') return false;
          loupeCount--;
          return true;
        });
      }
      combined = [...kept, ...hits];
    }
    final suggestions = _matchJerseyOcrHits(combined);
    if (stale()) {
      return OcrScanResult(
        supported: true,
        hits: jerseyOcrHits,
        matches: jerseySuggestions,
      );
    }
    jerseyOcrHits = combined;
    jerseySuggestions = suggestions;
    jerseyOcrBusy = _jerseyOcrInflight > 0;
    notifyListeners();
    return OcrScanResult(
      supported: true,
      hits: hits,
      matches: suggestions,
    );
  }

  /// OCR the loupe region (Vision-normalized ROI, origin bottom-left).
  /// Always a fresh Vision pass on that crop (no cache, no person gating).
  Future<OcrScanResult> runOcrLoupeScan(JerseyOcrRegion region) =>
      runOcrTestScan(force: true, regionOfInterest: region);

  static String _jerseyOcrCacheKey({
    required String path,
    required int mtimeMs,
    required String roiKey,
    required String sportKey,
    required List<String> customWords,
  }) =>
      '$path|$mtimeMs|$roiKey|$sportKey|${customWords.length}|${customWords.hashCode}';

  void _putJerseyOcrCache(String key, List<JerseyOcrHit> hits) {
    _jerseyOcrCache[key] = hits;
    // Full-frame reads are reused across mtime changes (saves, IPTC).
    final full = RegExp(r'\|full\|');
    if (full.hasMatch(key)) {
      final path = key.split('|full|').first;
      final pipe = path.lastIndexOf('|');
      if (pipe > 0) _jerseyOcrByPath[path.substring(0, pipe)] = hits;
    }
    while (_jerseyOcrCache.length > _jerseyOcrCacheMax) {
      _jerseyOcrCache.remove(_jerseyOcrCache.keys.first);
    }
  }

  // ---------------------------------------------------------------------------
  // Background pre-scan
  // ---------------------------------------------------------------------------

  /// Start (or resume) warming the OCR cache for the session's frames.
  /// No-op unless text recognition is on and the session is loaded.
  /// Stop the folder pre-scan (loading screen and background badge).
  void stopJerseyOcrPrescan() {
    if (_jerseyOcrPrescanStop) return;
    _jerseyOcrPrescanStop = true;
    unawaited(JerseyOcrChannel.cancelPrescan());
    notifyListeners();
  }

  void _kickJerseyOcrPrescan() {
    if (_jerseyOcrPrescanStop) return;
    if (!jerseyOcrEnabled || !sessionReady || imagePaths.isEmpty) return;
    if (_jerseyOcrPrescanRunning) return;
    if (_nextJerseyOcrPrescanPath() == null) return;
    unawaited(_runJerseyOcrPrescan());
  }

  /// OCR a single newly-arrived frame into the cache right away (no
  /// full-folder badge). Uses the normal Vision lane — not the slow
  /// background pre-scan queue — so chips are ready when you open it.
  Future<void> _ocrScanOnArrival(String path) async {
    if (!jerseyOcrEnabled || !sessionReady) return;
    if (_jerseyOcrPrescanned.contains(path)) return;

    int mtimeMs = 0;
    try {
      mtimeMs = (await File(path).lastModified()).millisecondsSinceEpoch;
    } catch (_) {
      _jerseyOcrPrescanned.add(path);
      return;
    }

    final customWords = _ocrCustomWords();
    final sportKey = sport.trim().toLowerCase();
    final key = _jerseyOcrCacheKey(
      path: path,
      mtimeMs: mtimeMs,
      roiKey: 'full',
      sportKey: sportKey,
      customWords: customWords,
    );
    if (!_jerseyOcrCache.containsKey(key)) {
      final hits = await JerseyOcrChannel.recognize(
        path: path,
        customWords: customWords,
        sport: sportKey,
        // Normal lane — land-and-scan should not sit behind utility pre-scan.
        prescan: false,
      );
      if (!jerseyOcrEnabled) return;
      _putJerseyOcrCache(key, hits);
    }
    _jerseyOcrPrescanned.add(path);
    jerseyOcrPrescanDone =
        _jerseyOcrPrescanned.intersection(imagePaths.toSet()).length;
    jerseyOcrPrescanTotal = imagePaths.length;

    // If the user switched onto this frame while we were scanning, surface it.
    if (path == currentPath && _jerseyOcrTimer == null) {
      unawaited(runOcrTestScan(force: false));
    }
  }

  void _resetJerseyOcrPrescan() {
    _jerseyOcrPrescanned.clear();
    jerseyOcrPrescanDone = 0;
    jerseyOcrPrescanTotal = 0;
  }

  /// Next frame to pre-scan: walk forward from the current frame (the ones
  /// the user will hit next), then wrap to the start.
  String? _nextJerseyOcrPrescanPath() {
    final n = imagePaths.length;
    if (n == 0) return null;
    final start = currentIndex.clamp(0, n - 1);
    for (var step = 0; step < n; step++) {
      final path = imagePaths[(start + step) % n];
      if (!_jerseyOcrPrescanned.contains(path)) return path;
    }
    return null;
  }

  Future<void> _runJerseyOcrPrescan() async {
    _jerseyOcrPrescanRunning = true;
    final generation = sessionGeneration;
    jerseyOcrPrescanTotal = imagePaths.length;
    jerseyOcrPrescanDone =
        _jerseyOcrPrescanned.intersection(imagePaths.toSet()).length;
    notifyListeners();
    var lastNotify = DateTime.now();
    try {
      while (jerseyOcrEnabled &&
          generation == sessionGeneration &&
          !_jerseyOcrPrescanStop) {
        // The user's own frame / loupe scans come first — idle while one
        // is in flight so Vision isn't fighting itself for the GPU.
        if (_jerseyOcrInflight > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final path = _nextJerseyOcrPrescanPath();
        if (path == null) break;

        int mtimeMs = 0;
        try {
          mtimeMs = (await File(path).lastModified()).millisecondsSinceEpoch;
        } catch (_) {
          _jerseyOcrPrescanned.add(path);
          jerseyOcrPrescanDone++;
          continue;
        }
        if (generation != sessionGeneration ||
            !jerseyOcrEnabled ||
            _jerseyOcrPrescanStop) {
          break;
        }

        final customWords = _ocrCustomWords();
        final sportKey = sport.trim().toLowerCase();
        final key = _jerseyOcrCacheKey(
          path: path,
          mtimeMs: mtimeMs,
          roiKey: 'full',
          sportKey: sportKey,
          customWords: customWords,
        );
        if (!_jerseyOcrCache.containsKey(key)) {
          // First notify so the Pre-scan badge appears before Vision starts.
          notifyListeners();
          final hits = await JerseyOcrChannel.recognize(
            path: path,
            customWords: customWords,
            sport: sportKey,
            prescan: true,
          );
          if (generation != sessionGeneration ||
              !jerseyOcrEnabled ||
              _jerseyOcrPrescanStop) {
            break;
          }
          _putJerseyOcrCache(key, hits);
          // If the user is sitting on this frame with no reads yet (frame
          // scan still pending / skipped), surface the result now.
          if (path == currentPath &&
              jerseyOcrHits.isEmpty &&
              _jerseyOcrInflight == 0 &&
              _jerseyOcrTimer == null) {
            unawaited(runOcrTestScan(force: false));
          }
        }
        _jerseyOcrPrescanned.add(path);
        jerseyOcrPrescanDone =
            _jerseyOcrPrescanned.intersection(imagePaths.toSet()).length;
        jerseyOcrPrescanTotal = imagePaths.length;

        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 400 ||
            jerseyOcrPrescanDone >= jerseyOcrPrescanTotal) {
          lastNotify = now;
          notifyListeners();
        }
        // Breathe between frames so UI work (thumbnails, EXIF) stays smooth.
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } finally {
      _jerseyOcrPrescanRunning = false;
      notifyListeners();
    }
  }

  /// True when [hit]'s centre lies within [roi] grown by [pad] about its centre.
  static bool _hitCenterInside(
    JerseyOcrHit hit,
    JerseyOcrRegion roi, {
    double pad = 1.0,
  }) {
    final cx = hit.x + hit.width * 0.5;
    final cy = hit.y + hit.height * 0.5;
    final w = roi.width * pad;
    final h = roi.height * pad;
    final left = roi.x + roi.width * 0.5 - w * 0.5;
    final bottom = roi.y + roi.height * 0.5 - h * 0.5;
    return cx >= left && cx <= left + w && cy >= bottom && cy <= bottom + h;
  }

  /// Roster last names + jersey numbers for Vision `customWords` bias.
  ///
  /// Vision caps at ~200 words and only applies them when language correction
  /// is on. Last names go first (jerseys are ALL CAPS surnames). First names
  /// are left out so they don't crowd the lexicon or false-match.
  List<String> _ocrCustomWords() {
    final lasts = <String>{};
    final jerseys = <String>{};
    void addRoster(List<Player> roster) {
      for (final player in roster) {
        final last = playerLastName(player).trim();
        if (last.length >= 2) {
          lasts.add(last);
          final upper = last.toUpperCase();
          if (upper != last) lasts.add(upper);
          // Hyphen / space / apostrophe variants ("O'Neill", "Van Meter").
          final compact = last.replaceAll(RegExp(r"[^A-Za-z]"), '');
          if (compact.length >= 3 &&
              compact.toLowerCase() != last.toLowerCase()) {
            lasts.add(compact);
            lasts.add(compact.toUpperCase());
          }
        }
        final jersey = (player.jerseyNumber ?? '').trim();
        if (RegExp(r'^\d{1,2}$').hasMatch(jersey)) {
          jerseys.add(jersey);
        }
      }
    }

    addRoster(homeRoster);
    addRoster(awayRoster);

    final lastList = lasts.toList()..sort();
    final jerseyList = jerseys.toList()..sort();
    final out = <String>[...lastList, ...jerseyList];
    if (out.length <= 200) return out;
    return out.sublist(0, 200);
  }

  List<JerseyOcrSuggestion> _matchJerseyOcrHits(List<JerseyOcrHit> hits) {
    if (hits.isEmpty) return const [];

    final bestByPlayerKey = <String, JerseyOcrSuggestion>{};
    // Players that got both a jersey and a nearby name hit — boost later.
    final jerseyHitPlayers = <String>{};
    final nameHitPlayers = <String>{};
    final jerseyHitsByPlayer = <String, List<JerseyOcrHit>>{};
    final nameHitsByPlayer = <String, List<JerseyOcrHit>>{};

    double hitSpatialBoost(JerseyOcrHit hit) {
      final cx = hit.x + hit.width * 0.5;
      final cy = hit.y + hit.height * 0.5;
      final centerDist = ((cx - 0.5) * (cx - 0.5) + (cy - 0.5) * (cy - 0.5));
      final centerFactor = (1.0 - (centerDist * 2.2)).clamp(0.0, 1.0);
      final area = (hit.width * hit.height).clamp(0.0, 0.25);
      final sizeFactor = (area / 0.02).clamp(0.0, 1.0);
      var boost = centerFactor * 0.10 + sizeFactor * 0.08;
      // Hockey: small digits high in frame are often helmet stickers.
      if (sport.trim().toLowerCase() == 'hockey') {
        final digits = hit.text.replaceFirst(RegExp(r'^#+'), '').trim();
        final isJersey = RegExp(r'^\d{1,2}$').hasMatch(digits);
        if (isJersey && cy >= 0.55 && area <= 0.045) {
          boost += 0.12;
        }
      }
      return boost;
    }

    final homeDark = homeWearsDark;
    final sideLean = _recentSideLean();

    /// Eyedropper colours first, then dark/light. Two navy kits still separate
    /// when the user has sampled both.
    double toneBoost(JerseyOcrHit hit, {required bool isHome}) {
      final sample = hit.fabricColor;
      final homeSwatch = homeJerseySwatch;
      final awaySwatch = awayJerseySwatch;
      if (sample != null && homeSwatch != null && awaySwatch != null) {
        final homeDist = _jerseyColorDistance(sample, homeSwatch);
        final awayDist = _jerseyColorDistance(sample, awaySwatch);
        if ((homeDist - awayDist).abs() >= 0.06) {
          final closerHome = homeDist < awayDist;
          return closerHome == isHome ? 0.18 : -0.16;
        }
      }
      if (homeDark == null || hit.jerseyTone == null) return 0;
      final hitSaysHome = hit.isDarkJersey == homeDark;
      return hitSaysHome == isHome ? 0.14 : -0.14;
    }

    void consider({
      required Player player,
      required bool isHome,
      required JerseyOcrHit hit,
      required JerseyOcrMatchKind kind,
      required int nameScore,
      double confidenceBoost = 0,
    }) {
      final playerKey = _ocrPlayerKey(player, isHome: isHome);
      if (kind == JerseyOcrMatchKind.jersey) {
        jerseyHitPlayers.add(playerKey);
        (jerseyHitsByPlayer[playerKey] ??= []).add(hit);
      } else {
        nameHitPlayers.add(playerKey);
        (nameHitsByPlayer[playerKey] ??= []).add(hit);
      }
      final existing = bestByPlayerKey[playerKey];
      // Prefer jersey matches, then tighter name scores, then confidence.
      final rank = kind == JerseyOcrMatchKind.jersey ? 0 : (10 + nameScore);
      final existingRank = existing == null
          ? 999
          : (existing.matchKind == JerseyOcrMatchKind.jersey
              ? 0
              : 10 + _ocrPlayerNameScore(
                  existing.player,
                  _normalizeFirebarText(existing.matchedText),
                ));
      final conf = (hit.confidence +
              confidenceBoost +
              hitSpatialBoost(hit) +
              toneBoost(hit, isHome: isHome) +
              _recentPickBoost(playerKey) +
              // Sticky bench: small nudge toward the side being worked.
              (isHome ? sideLean : -sideLean) * 0.05)
          .clamp(0.0, 1.0);
      if (existing != null && existingRank < rank) return;
      if (existing != null &&
          existingRank == rank &&
          existing.confidence >= conf) {
        return;
      }
      bestByPlayerKey[playerKey] = JerseyOcrSuggestion(
        player: player,
        isHome: isHome,
        confidence: conf,
        matchedText: hit.text,
        matchKind: kind,
        box: JerseyOcrRegion(
          x: hit.x,
          y: hit.y,
          width: hit.width,
          height: hit.height,
        ),
        jerseyTone: hit.jerseyTone,
        region: hit.region,
      );
    }

    Iterable<String> queryTokens(String raw) sync* {
      final cleaned = raw.replaceFirst(RegExp(r'^#+'), '').trim();
      if (cleaned.isEmpty) return;
      yield cleaned;
      final digitFixed = _ocrDigitConfusionFix(cleaned);
      if (digitFixed != null && digitFixed != cleaned) yield digitFixed;
      for (final part in cleaned.split(RegExp(r'[\s\-/]+'))) {
        final token = part.trim();
        if (token.isNotEmpty && token != cleaned) {
          yield token;
          final partFixed = _ocrDigitConfusionFix(token);
          if (partFixed != null && partFixed != token) yield partFixed;
        }
      }
      // "O'Neill21" / "Judge99" style glue.
      final glued = RegExp(r'^(.*?)(\d{1,2})$').firstMatch(cleaned);
      if (glued != null) {
        final name = glued.group(1)?.trim() ?? '';
        final digits = glued.group(2) ?? '';
        if (name.length >= 2) yield name;
        if (digits.isNotEmpty) yield digits;
      }
      // "21O'Neill" style prefix digits.
      final leading = RegExp(r'^(\d{1,2})([A-Za-z].+)$').firstMatch(cleaned);
      if (leading != null) {
        yield leading.group(1)!;
        final name = leading.group(2)?.trim() ?? '';
        if (name.length >= 2) yield name;
      }
    }

    bool boxesAreNear(List<JerseyOcrHit>? a, List<JerseyOcrHit>? b) {
      if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
      for (final left in a) {
        final lx = left.x + left.width * 0.5;
        final ly = left.y + left.height * 0.5;
        for (final right in b) {
          final dx = lx - (right.x + right.width * 0.5);
          final dy = ly - (right.y + right.height * 0.5);
          if (dx * dx + dy * dy <= 0.32 * 0.32) return true;
        }
      }
      return false;
    }

    void matchHit(JerseyOcrHit hit) {
      final cy = hit.y + hit.height * 0.5;
      final area = hit.width * hit.height;
      // Tiny text glued to the top scorebug or bottom ticker.
      if (area < 0.015 && (cy > 0.91 || cy < 0.055)) return;

      for (final raw in queryTokens(hit.text)) {
        final query = _normalizeFirebarText(raw);
        if (query.isEmpty) continue;

        // "B" inside "B Be" must not become jersey 8. Letter→digit fixes
        // apply only to the whole read ("B", "8B"). A split piece counts
        // as a number only when it is already digits ("23" in "JUDGE 23").
        final source = hit.text.replaceFirst(RegExp(r'^#+'), '').trim();
        final bare = raw.replaceFirst(RegExp(r'^#+'), '').trim();
        final isFragment = bare.toLowerCase() != source.toLowerCase();
        final String? jerseyKey;
        if (isFragment) {
          jerseyKey = RegExp(r'^\d{1,2}$').hasMatch(bare)
              ? int.parse(bare).toString()
              : null;
        } else {
          jerseyKey = _normalizeJerseyKey(raw);
        }
        // A jersey number is a compact block. A wide, short box is a board ad.
        // Loupe/focused scans already exclude boards — accept any 1–2 digits.
        // Frame and loupe hits now live in one list, so this is per hit.
        final focused = hit.region == 'loupe';
        final aspect = hit.height > 0.0001 ? hit.width / hit.height : 1.0;
        final compactNumber =
            focused || hit.height <= 0.004 || aspect <= 2.6;
        final isJerseyToken = compactNumber &&
            jerseyKey != null &&
            RegExp(r'^\d{1,2}$').hasMatch(jerseyKey);

        void scanRoster(List<Player> roster, {required bool isHome}) {
          for (final player in roster) {
            if (isJerseyToken) {
              // Loupe digit reads are often wrong on helmet stickers — need
              // a stronger Vision score before locking a jersey match.
              if (focused && hit.confidence < 0.42) continue;
              final playerJersey = _normalizeJerseyKey(player.jerseyNumber);
              if (playerJersey != null && playerJersey == jerseyKey) {
                consider(
                  player: player,
                  isHome: isHome,
                  hit: hit,
                  kind: JerseyOcrMatchKind.jersey,
                  nameScore: 0,
                );
                continue;
              }
            }

            // Skip very short name tokens (noise); allow 1–2 digit jerseys above.
            if (query.length < 3) continue;
            final score = _ocrPlayerNameScore(player, query);
            // Only surnames that clearly resemble the OCR text.
            if (!_ocrNameScoreOk(score, query)) continue;
            consider(
              player: player,
              isHome: isHome,
              hit: hit,
              kind: JerseyOcrMatchKind.name,
              nameScore: score,
            );
          }
        }

        scanRoster(homeRoster, isHome: true);
        scanRoster(awayRoster, isHome: false);
      }
    }

    for (final hit in hits) {
      matchHit(hit);
    }

    // A number and a name that both point at one roster player is as good as
    // it gets — the odds of that being a coincidence anywhere in the frame are
    // negligible, so distance between the two reads is a bonus, not a gate.
    bool confirmedByNameAndNumber(String key) =>
        jerseyHitPlayers.contains(key) && nameHitPlayers.contains(key);

    for (final key in jerseyHitPlayers.intersection(nameHitPlayers)) {
      final existing = bestByPlayerKey[key];
      if (existing == null) continue;
      final near = boxesAreNear(jerseyHitsByPlayer[key], nameHitsByPlayer[key]);
      bestByPlayerKey[key] = existing.copyWith(
        confidence: (existing.confidence + (near ? 0.22 : 0.14)).clamp(0.0, 1.0),
        confirmed: true,
      );
    }

    // Once someone is confirmed, the weak reads are noise: single-digit
    // jersey fragments and partial-name guesses for *other* players go.
    if (bestByPlayerKey.values.any((s) => s.confirmed)) {
      bestByPlayerKey.removeWhere((key, s) {
        if (s.confirmed) return false;
        final text = s.matchedText.replaceFirst(RegExp(r'^#+'), '').trim();
        if (s.matchKind == JerseyOcrMatchKind.jersey) {
          return !RegExp(r'^\d{2}$').hasMatch(text);
        }
        return _ocrPlayerNameScore(s.player, _normalizeFirebarText(text)) != 2;
      });
    }

    // Same number on both teams: keep the side whose name is also in frame.
    // Failing that, keep the side whose jersey tone matches the bench, or
    // the side seen on the previous frames of this shift.
    final keysByJersey = <String, List<String>>{};
    for (final entry in bestByPlayerKey.entries) {
      if (entry.value.matchKind != JerseyOcrMatchKind.jersey) continue;
      final jersey = _normalizeJerseyKey(entry.value.jersey);
      if (jersey == null || !RegExp(r'^\d{1,2}$').hasMatch(jersey)) continue;
      keysByJersey.putIfAbsent(jersey, () => []).add(entry.key);
    }
    for (final keys in keysByJersey.values) {
      if (keys.length < 2) continue;
      final confirmed = keys.where(confirmedByNameAndNumber).toList();
      if (confirmed.isNotEmpty) {
        for (final key in keys) {
          if (!confirmed.contains(key)) bestByPlayerKey.remove(key);
        }
        continue;
      }
      // Tone: both candidates share the hit, so tone picks exactly one side.
      if (homeDark != null) {
        final toneAgree = keys.where((key) {
          final s = bestByPlayerKey[key]!;
          if (s.jerseyTone == null) return false;
          final hitSaysHome = (s.jerseyTone == 'dark') == homeDark;
          return hitSaysHome == s.isHome;
        }).toList();
        if (toneAgree.length == 1) {
          for (final key in keys) {
            if (key != toneAgree.first) bestByPlayerKey.remove(key);
          }
          continue;
        }
      }
      // Shift continuity: one side was confirmed seconds ago.
      final recent = keys.where((k) => _recentPickBoost(k) >= 0.07).toList();
      if (recent.length == 1) {
        for (final key in keys) {
          if (key != recent.first) bestByPlayerKey.remove(key);
        }
      }
    }

    // A lone "B" that shares its box with "B Be" is the logo, not jersey 8.
    bestByPlayerKey.removeWhere((_, suggestion) {
      if (suggestion.matchKind != JerseyOcrMatchKind.jersey) return false;
      final text = suggestion.matchedText.replaceFirst(RegExp(r'^#+'), '').trim();
      if (text.length != 1 || RegExp(r'^\d$').hasMatch(text)) return false;
      final box = suggestion.box;
      if (box == null) return false;
      return hits.any((hit) {
        final other = hit.text.trim();
        if (other.length <= text.length) return false;
        if (!other.toLowerCase().contains(text.toLowerCase())) return false;
        return (box.x - hit.x).abs() < 0.03 &&
            (box.y - hit.y).abs() < 0.03 &&
            (box.width - hit.width).abs() < 0.03 &&
            (box.height - hit.height).abs() < 0.03;
      });
    });

    String playerKeyOf(JerseyOcrSuggestion suggestion) =>
        _ocrPlayerKey(suggestion.player, isHome: suggestion.isHome);

    final out = bestByPlayerKey.values.toList()
      ..sort((a, b) {
        final aBoth = confirmedByNameAndNumber(playerKeyOf(a));
        final bBoth = confirmedByNameAndNumber(playerKeyOf(b));
        if (aBoth != bBoth) return aBoth ? -1 : 1;
        final byKind = a.matchKind.index.compareTo(b.matchKind.index);
        if (byKind != 0) return byKind;
        final byConf = b.confidence.compareTo(a.confidence);
        if (byConf != 0) return byConf;
        final byJersey = (int.tryParse(a.jersey) ?? 999)
            .compareTo(int.tryParse(b.jersey) ?? 999);
        if (byJersey != 0) return byJersey;
        return a.player.fullName.compareTo(b.player.fullName);
      });

    String digitsOf(String text) =>
        text.replaceFirst(RegExp(r'^#+'), '').trim();
    bool isJerseyRead(JerseyOcrSuggestion s) =>
        s.matchKind == JerseyOcrMatchKind.jersey &&
        RegExp(r'^\d{1,2}$').hasMatch(digitsOf(s.matchedText));

    // "34" read as "3" / "4" too: a 2-digit read at the same spot owns the
    // 1-digit fragments inside it, so #3 / #4 players don't get invented.
    out.removeWhere((s) {
      if (!isJerseyRead(s)) return false;
      final frag = digitsOf(s.matchedText);
      if (frag.length != 1) return false;
      return out.any((o) {
        if (identical(o, s) || !isJerseyRead(o)) return false;
        final full = digitsOf(o.matchedText);
        return full.length == 2 &&
            full.contains(frag) &&
            _ocrBoxesOverlap(o.box, s.box);
      });
    });

    // One player per patch of fabric. A name + number read that agree on one
    // roster player owns that box — nothing else read there can be someone
    // else. Also a higher-ranked jersey read of a different number at the
    // same spot wins over a lower one (Vision alternates like 34 vs 84).
    final kept = <JerseyOcrSuggestion>[];
    for (final s in out) {
      final dominated = kept.any((k) {
        if (k.isHome == s.isHome && _samePlayer(k.player, s.player)) {
          return false;
        }
        // A confirmed player owns both the spot its number was read at and
        // the spot its name was read at.
        if (k.confirmed) {
          final kKey = playerKeyOf(k);
          final owned = <JerseyOcrHit>[
            ...?jerseyHitsByPlayer[kKey],
            ...?nameHitsByPlayer[kKey],
          ];
          for (final hit in owned) {
            final hitBox = JerseyOcrRegion(
              x: hit.x,
              y: hit.y,
              width: hit.width,
              height: hit.height,
            );
            if (_ocrBoxesOverlap(hitBox, s.box)) return true;
          }
        }
        if (!_ocrBoxesOverlap(k.box, s.box)) return false;
        if (k.confirmed) return true;
        // Same number on both benches, still unresolved: keep both choices.
        if (_normalizeJerseyKey(k.jersey) == _normalizeJerseyKey(s.jersey)) {
          return false;
        }
        return isJerseyRead(k) && isJerseyRead(s);
      });
      if (!dominated) kept.add(s);
    }

    if (kept.length <= 12) return kept;
    return kept.sublist(0, 12);
  }

  /// True when two OCR boxes cover mostly the same spot on the frame.
  static bool _ocrBoxesOverlap(JerseyOcrRegion? a, JerseyOcrRegion? b) {
    if (a == null || b == null) return false;
    final left = a.x > b.x ? a.x : b.x;
    final bottom = a.y > b.y ? a.y : b.y;
    final right = (a.x + a.width) < (b.x + b.width)
        ? (a.x + a.width)
        : (b.x + b.width);
    final top = (a.y + a.height) < (b.y + b.height)
        ? (a.y + a.height)
        : (b.y + b.height);
    if (right <= left || top <= bottom) {
      // Not touching — still "same spot" if one center sits inside the other.
      final acx = a.x + a.width / 2, acy = a.y + a.height / 2;
      final bcx = b.x + b.width / 2, bcy = b.y + b.height / 2;
      final aInB = acx >= b.x && acx <= b.x + b.width &&
          acy >= b.y && acy <= b.y + b.height;
      final bInA = bcx >= a.x && bcx <= a.x + a.width &&
          bcy >= a.y && bcy <= a.y + a.height;
      return aInB || bInA;
    }
    final inter = (right - left) * (top - bottom);
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final smaller = areaA < areaB ? areaA : areaB;
    if (smaller <= 0) return false;
    return inter / smaller >= 0.35;
  }

  static String? _normalizeJerseyKey(String? raw) {
    var trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    while (trimmed.startsWith('#')) {
      trimmed = trimmed.substring(1).trim();
    }
    final digitFixed = _ocrDigitConfusionFix(trimmed) ?? trimmed;
    final parsed = int.tryParse(digitFixed);
    if (parsed != null && parsed >= 0 && parsed <= 99) {
      return parsed.toString();
    }
    return trimmed.toLowerCase();
  }

  /// OCR name match — only when the read clearly resembles the last name.
  ///
  /// Lower is better. 900+ means no match. Rejects brand/noise like "Bauer".
  static int _ocrPlayerNameScore(Player player, String query) {
    final last = _ocrLettersOnly(playerLastName(player));
    final q = _ocrLettersOnly(query);
    if (last.length < 3 || q.length < 3) return 900;

    // Exact / strong prefix only when the OCR token covers most of the name.
    if (last == q) return 2;
    if (last.startsWith(q) && q.length >= 4) return 5;
    if (q.startsWith(last) && last.length >= 4) return 5;

    // Truncation / dropped first letter — token must still be a big chunk.
    if (last.contains(q) &&
        q.length >= 4 &&
        q.length * 2 >= last.length) {
      return 8;
    }
    if (q.contains(last) && last.length >= 4) return 5;

    // Shared prefix: "MATTH" ↔ "matthews" (not "auer" ↔ anything).
    final shared = _ocrSharedPrefixLen(last, q);
    if (shared >= 4 &&
        shared * 2 >= q.length &&
        shared * 2 >= last.length.clamp(0, shared * 3)) {
      return 5;
    }

    return 900;
  }

  static String _ocrLettersOnly(String raw) =>
      _normalizeFirebarText(raw).replaceAll(RegExp(r'[^a-z]'), '');

  static int _ocrSharedPrefixLen(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  /// Exact last name or a long, high-overlap last-name partial.
  ///
  /// First-name-only hits are rejected — OCR nameplates are surnames.
  static bool _ocrNameScoreOk(int score, String query) {
    final letters = _ocrLettersOnly(query);
    if (score == 2) return letters.length >= 3; // exact last
    if (score == 5 || score == 8) return letters.length >= 4; // strong partial
    return false;
  }

  /// Map common OCR letter↔digit confusions for 1–2 character jersey tokens.
  static String? _ocrDigitConfusionFix(String raw) {
    final text = raw.replaceFirst(RegExp(r'^#+'), '').trim();
    if (text.isEmpty || text.length > 2) return null;
    // "AI" and "B" are words on the boards, not jersey numbers. Only repair
    // a letter when the token already has a digit ("4I" → "41").
    if (!RegExp(r'\d').hasMatch(text)) return null;
    const map = {
      'O': '0',
      'o': '0',
      'Q': '0',
      'D': '0',
      'U': '0',
      'I': '1',
      'l': '1',
      '|': '1',
      'i': '1',
      'Z': '2',
      'z': '2',
      'E': '3',
      'A': '4',
      'H': '4',
      'S': '5',
      's': '5',
      'G': '6',
      'b': '6',
      'C': '6',
      'T': '7',
      'Y': '7',
      'B': '8',
      'g': '9',
      'q': '9',
      'P': '9',
    };
    const ambiguousAlone = {'A', 'H', 'E', 'Y', 'P', 'U', 'C'};
    if (text.length == 1 && ambiguousAlone.contains(text)) return null;
    final buf = StringBuffer();
    var changed = false;
    for (final ch in text.split('')) {
      if (RegExp(r'^\d$').hasMatch(ch)) {
        buf.write(ch);
      } else {
        final digit = map[ch];
        if (digit == null) return null;
        buf.write(digit);
        changed = true;
      }
    }
    if (!changed) return text;
    final out = buf.toString();
    return RegExp(r'^\d{1,2}$').hasMatch(out) ? out : null;
  }

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
    await _syncFileSig(path);
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
    await _syncFileSig(path);
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
    final movedClicks = _clicksByPath.remove(oldPath);
    if (movedClicks != null) _clicksByPath[nextPath] = movedClicks;
    if (_restoreClicksOnOpen.remove(oldPath)) {
      _restoreClicksOnOpen.add(nextPath);
    }
    if (captionedImages.remove(oldPath)) captionedImages.add(nextPath);
    if (sentImages.remove(oldPath)) sentImages.add(nextPath);
    if (selectedImagePaths.remove(oldPath)) selectedImagePaths.add(nextPath);
    await _persistSaved();
    notifyListeners();
    if (currentPath == nextPath) await _refreshFrameIptc();
    return true;
  }

  Future<bool> deleteImage(String path) async {
    return (await deleteImages([path])) == 1;
  }

  /// Deletes every path that still exists on disk. One persist / IPTC refresh.
  Future<int> deleteImages(List<String> paths) async {
    final unique = <String>{
      for (final path in paths)
        if (path.trim().isNotEmpty) path,
    };
    if (unique.isEmpty) return 0;

    final removed = <String>[];
    for (final path in unique) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        await file.delete();
        removed.add(path);
      } catch (_) {}
    }
    if (removed.isEmpty) return 0;

    final removedSet = removed.toSet();
    final previousPath = currentPath;
    final previousIndex = currentIndex;
    imagePaths.removeWhere(removedSet.contains);
    for (final path in removed) {
      captureByPath.remove(path);
      savedImages.remove(path);
      _clicksByPath.remove(path);
      _restoreClicksOnOpen.remove(path);
      captionedImages.remove(path);
      sentImages.remove(path);
      selectedImagePaths.remove(path);
    }

    if (imagePaths.isEmpty) {
      currentIndex = 0;
    } else if (previousPath != null && !removedSet.contains(previousPath)) {
      final kept = imagePaths.indexOf(previousPath);
      currentIndex = kept >= 0 ? kept : 0;
    } else {
      currentIndex = previousIndex.clamp(0, imagePaths.length - 1);
    }

    await _persistSaved();
    notifyListeners();
    await _refreshFrameIptc();
    _scheduleJerseyOcr();
    return removed.length;
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

  static String? serialNumberFromMetadata(Map<dynamic, dynamic> raw) {
    return _stringFromMeta(raw['SerialNumber']) ??
        _stringFromMeta(raw['BodySerialNumber']) ??
        _stringFromMeta(raw['InternalSerialNumber']) ??
        _stringFromMeta(raw['CameraSerialNumber']);
  }

  /// When serial bylines is enabled: map known serials to photographer, or
  /// flag the UI to ask who took the photo (missing / unknown serial).
  ///
  /// If Creator is already filled but matches the serial→name map, keep the
  /// name and mark provenance as serial so hover tips can say so.
  Future<void> _resolveSerialBylines(
    String path,
    Map<dynamic, dynamic> raw,
  ) async {
    final prefs = await PreferencesService.getInstance();
    final enabled = await prefs.getSerialNumberBylines();
    serialBylinesEnabled = enabled;
    if (!enabled) {
      _releaseSerialBylinesGate();
      return;
    }

    final camera = CameraSerialService.instance;
    await camera.initialize();

    final serial = serialNumberFromMetadata(raw)?.trim() ?? '';
    final body = CameraSerialService.bodyNameFromExif(raw);
    if (serial.isNotEmpty && !camera.isSerialNumberUnknown(serial)) {
      if (body.isNotEmpty) {
        await camera.rememberCameraBodies({serial: body});
      }
      final mapped = camera.getPhotographerForSerial(serial)?.trim() ?? '';
      if (mapped.isNotEmpty) {
        final current = photographerName.trim();
        if (current.isEmpty) {
          photographerName = mapped;
          _photographerProvenance = _BylineProvenance.serial;
          _photographerSerialUsed = serial;
          return;
        }
        if (current.toLowerCase() == mapped.toLowerCase()) {
          _photographerProvenance = _BylineProvenance.serial;
          _photographerSerialUsed = serial;
          return;
        }
      }
    }

    if (photographerName.trim().isNotEmpty) return;
    if (_deferSerialBylinesUi) return;
    if (_serialBylinesHandled.contains(_serialPromptKey(serial))) return;

    final dismissKey = '$path|${serial.isEmpty ? '_' : serial}';
    if (_serialBylinesPromptDismissed.contains(dismissKey)) return;
    _enqueueSerialPrompt(serial, imagePath: path, body: body);
  }

  /// Distinct unmapped serials in the open folder, before the session UI.
  /// An empty folder waits and checks each photo as it is ingested.
  Future<void> _checkSerialBylinesBeforeSession() async {
    _scanSerialsOnArrival = false;
    if (!serialBylinesEnabled) {
      _deferSerialBylinesUi = false;
      return;
    }
    if (imagePaths.isEmpty) {
      _scanSerialsOnArrival = true;
      _deferSerialBylinesUi = false;
      return;
    }
    _setSessionLoadingLabel('Checking camera serials…');
    final unknown = await _unknownSerialsForPaths(imagePaths);
    _deferSerialBylinesUi = false;
    if (unknown.isEmpty) return;
    final gate = Completer<void>();
    _serialBylinesGate = gate;
    for (final prompt in unknown) {
      _enqueueSerialPrompt(
        prompt.serial,
        imagePath: prompt.imagePath,
        body: prompt.body,
      );
    }
    if (_serialBylinesQueue.isEmpty) {
      if (identical(_serialBylinesGate, gate)) _serialBylinesGate = null;
      if (!gate.isCompleted) gate.complete();
      return;
    }
    _setSessionLoadingLabel('Assign camera serials…');
    await gate.future;
  }

  /// Read the serial on a photo that landed in a folder that started empty.
  Future<void> _checkArrivingSerial(String path) async {
    if (!_scanSerialsOnArrival || !serialBylinesEnabled) return;
    if (!imagePaths.contains(path)) return;
    final read = await _readFrameSerials([path]);
    if (read == null || !imagePaths.contains(path)) return;
    final frame = read[path];
    if (frame == null) return;
    final serial = frame.serial;
    if (serial.isNotEmpty) {
      final camera = CameraSerialService.instance;
      await camera.initialize();
      if (!camera.isSerialNumberUnknown(serial)) {
        if (frame.body.isNotEmpty) {
          await camera.rememberCameraBodies({serial: frame.body});
        }
        if (path == currentPath && photographerName.trim().isEmpty) {
          final mapped = camera.getPhotographerForSerial(serial)?.trim() ?? '';
          if (mapped.isNotEmpty) {
            photographerName = mapped;
            _photographerProvenance = _BylineProvenance.serial;
            _photographerSerialUsed = serial;
            notifyListeners();
          }
        }
        return;
      }
      _enqueueSerialPrompt(serial, imagePath: path, body: frame.body);
      return;
    }
    if (!frame.hasCreator) {
      _enqueueSerialPrompt('', imagePath: path, body: frame.body);
    }
  }

  Future<List<_SerialPrompt>> _unknownSerialsForPaths(List<String> paths) async {
    final camera = CameraSerialService.instance;
    await camera.initialize();
    final ordered = <_SerialPrompt>[];
    final seen = <String>{};
    final matchedBodies = <String, String>{};
    void consider(_FrameSerialScan frame, String path) {
      final serial = frame.serial;
      if (serial.isNotEmpty &&
          frame.body.isNotEmpty &&
          !camera.isSerialNumberUnknown(serial)) {
        matchedBodies.putIfAbsent(serial, () => frame.body);
      }
      final key = _serialPromptKey(serial);
      if (seen.contains(key) || _serialBylinesHandled.contains(key)) return;
      if (serial.isEmpty) {
        // A filled byline does not answer a later file that has neither.
        if (frame.hasCreator) return;
        seen.add(key);
        ordered.add(_SerialPrompt(serial: '', imagePath: path));
        return;
      }
      seen.add(key);
      if (!camera.isSerialNumberUnknown(serial)) return;
      ordered.add(
        _SerialPrompt(serial: serial, imagePath: path, body: frame.body),
      );
    }

    const chunk = 40;
    for (var i = 0; i < paths.length; i += chunk) {
      final end = i + chunk > paths.length ? paths.length : i + chunk;
      final slice = paths.sublist(i, end);
      final read = await _readFrameSerials(slice);
      if (read == null) continue;
      for (final path in slice) {
        final frame = read[path];
        if (frame == null) continue;
        consider(frame, path);
      }
    }
    if (matchedBodies.isNotEmpty) {
      await camera.rememberCameraBodies(matchedBodies);
    }
    return ordered;
  }

  /// Serial plus whether Creator/byline is already filled.
  /// Null when ExifTool could not read the batch.
  Future<Map<String, _FrameSerialScan>?> _readFrameSerials(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return {};
    try {
      final proc = await ExiftoolHelper.run([
        '-j',
        '-SerialNumber',
        '-BodySerialNumber',
        '-InternalSerialNumber',
        '-CameraSerialNumber',
        '-Make',
        '-Model',
        '-IPTC:By-line',
        '-By-line',
        '-Byline',
        '-Creator',
        '-XMP:Creator',
        '-Artist',
        '-Photographer',
        ...paths,
      ]);
      if (!proc.isSuccess || proc.stdoutText.trim().isEmpty) return null;
      final decoded = jsonDecode(proc.stdoutText);
      if (decoded is! List) return null;
      final bySource = <String, _FrameSerialScan>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final source = item['SourceFile']?.toString();
        if (source == null || source.isEmpty) continue;
        bySource[p.normalize(source)] = _FrameSerialScan(
          serial: serialNumberFromMetadata(item)?.trim() ?? '',
          hasCreator: photographerNameFromMetadata(item).trim().isNotEmpty,
          body: CameraSerialService.bodyNameFromExif(item),
        );
      }
      final out = <String, _FrameSerialScan>{};
      for (final path in paths) {
        final frame = bySource[p.normalize(path)];
        if (frame != null) out[path] = frame;
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  String _serialPromptKey(String serial) {
    final trimmed = serial.trim();
    return trimmed.isEmpty ? '_' : trimmed.toLowerCase();
  }

  void _enqueueSerialPrompt(
    String serial, {
    String? imagePath,
    String body = '',
  }) {
    final trimmed = serial.trim();
    final key = _serialPromptKey(trimmed);
    if (_serialBylinesHandled.contains(key)) return;
    if (_serialBylinesQueue.any((queued) => _serialPromptKey(queued.serial) == key)) {
      return;
    }
    _serialBylinesQueue.add(
      _SerialPrompt(serial: trimmed, imagePath: imagePath, body: body.trim()),
    );
    pendingSerialBylinesPrompt = _serialBylinesQueue.first.serial;
    notifyListeners();
  }

  void _popSerialPrompt() {
    if (_serialBylinesQueue.isNotEmpty) {
      _serialBylinesQueue.removeAt(0);
    }
    pendingSerialBylinesPrompt =
        _serialBylinesQueue.isEmpty ? null : _serialBylinesQueue.first.serial;
    if (_serialBylinesQueue.isEmpty) {
      final gate = _serialBylinesGate;
      _serialBylinesGate = null;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    notifyListeners();
  }

  void _releaseSerialBylinesGate() {
    _serialBylinesQueue.clear();
    pendingSerialBylinesPrompt = null;
    final gate = _serialBylinesGate;
    _serialBylinesGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void dismissSerialBylinesPrompt() {
    final serial = pendingSerialBylinesPrompt ?? '';
    final path = currentPath;
    if (path != null) {
      _serialBylinesPromptDismissed.add(
        '$path|${serial.isEmpty ? '_' : serial}',
      );
    }
    _serialBylinesHandled.add(_serialPromptKey(serial));
    _popSerialPrompt();
  }

  /// Apply a photographer chosen in the unknown-serial dialog for the current
  /// frame. Mapping is already saved by the dialog when a serial exists.
  void applySerialBylinesAssignment({
    required String name,
    String initials = '',
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      dismissSerialBylinesPrompt();
      return;
    }
    final serial = (pendingSerialBylinesPrompt ?? '').trim();
    final currentSerial = (_photographerSerialUsed ?? '').trim();
    final appliesToFrame = serial.isEmpty
        ? currentSerial.isEmpty
        : currentSerial.toLowerCase() == serial.toLowerCase();
    if (appliesToFrame) {
      photographerName = trimmed;
      _photographerProvenance = _BylineProvenance.serialAssigned;
      if (serial.isNotEmpty) _photographerSerialUsed = serial;
      metadataDirty = true;
    }
    final path = currentPath;
    if (path != null) {
      _serialBylinesPromptDismissed.add('$path|${serial.isEmpty ? '_' : serial}');
    }
    _serialBylinesHandled.add(_serialPromptKey(serial));
    _popSerialPrompt();
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

  /// Largest positive integer in a tag. Lists keep the full-size value
  /// instead of a thumbnail that appears first.
  static int? _largestPixelValue(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final n = value.round();
      return n > 0 ? n : null;
    }
    if (value is List) {
      int? best;
      for (final item in value) {
        final n = _largestPixelValue(item);
        if (n == null) continue;
        if (best == null || n > best) best = n;
      }
      return best;
    }
    int? best;
    for (final match in RegExp(r'\d+').allMatches(value.toString())) {
      final n = int.tryParse(match.group(0)!);
      if (n == null || n <= 0) continue;
      if (best == null || n > best) best = n;
    }
    return best;
  }

  static void _applyLargestExifDimensions(
    Map<String, dynamic> raw,
    Map<String, String> meta,
  ) {
    int? width;
    int? height;
    void consider(dynamic w, dynamic h) {
      final pw = _largestPixelValue(w);
      final ph = _largestPixelValue(h);
      if (pw == null || ph == null) return;
      final longest = pw > ph ? pw : ph;
      final current = width == null || height == null
          ? 0
          : (width! > height! ? width! : height!);
      if (longest < current) return;
      width = pw;
      height = ph;
    }

    consider(raw['ImageWidth'], raw['ImageHeight']);
    consider(raw['ExifImageWidth'], raw['ExifImageHeight']);
    consider(raw['PixelXDimension'], raw['PixelYDimension']);
    final size = _stringFromMeta(raw['ImageSize']);
    if (size != null) {
      final parts = size.split(RegExp(r'[xX×]'));
      if (parts.length >= 2) consider(parts[0], parts[1]);
    }
    if (width == null || height == null) return;
    meta['ImageWidth'] = '$width';
    meta['ImageHeight'] = '$height';
  }

  /// Pixel size of the file itself, not the camera's original EXIF size.
  Future<(int, int)?> _encodedPixelSize(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) return null;
      return (width, height);
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Load the current frame's header EXIF plus caption-related IPTC.
  Future<void> _refreshFrameIptc() async {
    final path = currentPath;
    final gen = ++_iptcLoadGen;
    if (path == null) {
      currentIptcMeta = {};
      photographerName = '';
      agencyName = '';
      _photographerProvenance = _BylineProvenance.none;
      _photographerSerialUsed = null;
      if (_serialBylinesQueue.isEmpty) pendingSerialBylinesPrompt = null;
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
        '-PixelXDimension',
        '-PixelYDimension',
        '-ImageSize',
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
        '-SerialNumber',
        '-BodySerialNumber',
        '-InternalSerialNumber',
        '-CameraSerialNumber',
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
        '-IPTC:Sub-location',
        '-Sub-location',
        '-SubLocation',
        '-Location',
        '-IPTC:Location',
        '-XMP:Location',
        '-XMP-iptcCore:Location',
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
        final pixels = await _encodedPixelSize(path);
        if (gen != _iptcLoadGen) return;
        currentIptcMeta = pixels == null
            ? {}
            : {
                'ImageWidth': '${pixels.$1}',
                'ImageHeight': '${pixels.$2}',
              };
        photographerName = '';
        agencyName = '';
        _photographerProvenance = _BylineProvenance.none;
        _photographerSerialUsed = null;
        notifyListeners();
        return;
      }
      final List data = jsonDecode(proc.stdoutText);
      if (data.isEmpty || data.first is! Map) {
        currentIptcMeta = {};
        photographerName = '';
        agencyName = '';
        _photographerProvenance = _BylineProvenance.none;
        _photographerSerialUsed = null;
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
      final pixels = await _encodedPixelSize(path);
      if (gen != _iptcLoadGen) return;
      if (pixels != null) {
        meta['ImageWidth'] = '${pixels.$1}';
        meta['ImageHeight'] = '${pixels.$2}';
        currentIptcMeta = meta;
      } else {
        _applyLargestExifDimensions(raw, meta);
        currentIptcMeta = meta;
      }
      photographerName = photographerNameFromMetadata(raw);
      _photographerSerialUsed = serialNumberFromMetadata(raw)?.trim();
      _photographerProvenance = photographerName.trim().isEmpty
          ? _BylineProvenance.none
          : _BylineProvenance.iptc;
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
      await _resolveSerialBylines(path, raw);
      if (gen != _iptcLoadGen) return;
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
      _photographerProvenance = _BylineProvenance.none;
      _photographerSerialUsed = null;
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
      clicks: captionClicksForTransfer(),
    );
    previousCaption = payload;
    await _prefs?.saveLastSavedMetadata(payload.toJson());
  }

  Future<bool> saveCurrent({bool advance = false}) async {
    final selected = orderedSelectedImagePaths;
    final path = currentPath;
    final targets = selected.length >= 2
        ? selected
        : (path == null ? const <String>[] : <String>[path]);
    if (targets.isEmpty) {
      statusMessage = 'No image to save';
      notifyListeners();
      return false;
    }
    final keepFirebar = searchOpen;
    final result = await savePaths(targets);
    if (selected.length >= 2) {
      setSelectedImagePaths(result.failedPaths);
    }
    if (result.anySucceeded && advance) {
      if (selected.length >= 2 && result.succeededPaths.isNotEmpty) {
        advancePastHandledChain(
          result.succeededPaths,
          keepSearchOpen: keepFirebar,
        );
      } else {
        nextFrame(keepSearchOpen: keepFirebar);
      }
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

    final captionUnchanged = !hasCaptionSubject &&
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

    final manualCaption = manualCaptionOverride?.trim().isNotEmpty == true;
    // A player without a verb writes an incomplete sentence and is not marked
    // captioned, so Needs caption keeps showing the photo after "Saved".
    if (hasCaptionSubject && !hasVerbSelection && !manualCaption) {
      _warnStatus('Select a verb before saving');
      return CaptionSaveResult(
        requestedPaths: targets,
        succeededPaths: const [],
      );
    }

    final generatedCaption = hasCaptionSubject && hasVerbSelection;
    if (generatedCaption && selectedVerb != null) rememberCombo();
    final openPath = currentPath;
    if (openPath != null && targets.contains(openPath)) {
      _rememberLeavingFrame(openPath);
    }
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
      for (final pth in succeeded) {
        await _syncFileSig(pth);
      }
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

  /// Write a previously captured caption [values] map to [paths].
  ///
  /// Used when applying a saved caption to the rest of a burst after the
  /// user opts in via Review burst (caption selection may already be cleared).
  Future<CaptionSaveResult> savePathsWithFixedValues(
    List<String> paths,
    Map<String, String> values,
  ) async {
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
    if (values.isEmpty) {
      statusMessage = 'No caption to apply';
      notifyListeners();
      return CaptionSaveResult(
        requestedPaths: targets,
        succeededPaths: const [],
      );
    }

    final templateSucceeded = <String>[];
    for (final pth in targets) {
      if (await _applyIptcTemplateOnSaveIfEnabled(pth)) {
        templateSucceeded.add(pth);
      }
    }

    final succeeded = await _writer.writeCaptionToPaths(
      paths: targets,
      values: values,
    );
    if (succeeded.isNotEmpty) {
      savedImages.addAll(succeeded);
      captionedImages.addAll(succeeded);
      unawaited(FloCaptionMark.markSaved(succeeded));
      await _persistSaved();
      for (final pth in succeeded) {
        await _syncFileSig(pth);
      }
      await _storePreviousCaption(
        caption: values['IPTC:Caption-Abstract'] ?? '',
        personality: values['XMP-getty:Personality'] ?? '',
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
      _restoreRememberedClicks();
      notifyListeners();
    }
    return saved;
  }

  void _clearCaptionSelection() {
    selectedPlayers.clear();
    selectedPlayer = null;
    teamPlayersIsHome = null;
    withTeammatesIsHome = null;
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

  bool _wasAlreadyFtpd(String path) {
    if (sentImages.contains(path)) return true;
    for (final entry in ftpHistory) {
      if (entry.success && entry.path == path) return true;
    }
    return false;
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
    if (_retransmitPromptOpen) {
      statusMessage = 'FTP already in progress';
      notifyListeners();
      return;
    }

    final busy = <String>{
      ..._ftpWait.map((job) => job.path),
      ...ftpActiveProgress.keys,
    };
    final fresh = paths.where((path) => !busy.contains(path)).toList();
    if (fresh.isEmpty) {
      statusMessage =
          _ftpSessionOpen ? 'Already in the FTP queue' : 'Nothing to FTP';
      notifyListeners();
      return;
    }

    final alreadySent = fresh.where(_wasAlreadyFtpd).toList();
    var toSend = fresh.where((path) => !_wasAlreadyFtpd(path)).toList();
    if (alreadySent.isNotEmpty) {
      _retransmitPromptOpen = true;
      bool allow = false;
      try {
        allow = await confirmRetransmit?.call(alreadySent) ?? false;
      } finally {
        _retransmitPromptOpen = false;
      }
      if (allow) toSend = [...toSend, ...alreadySent];
    }
    if (toSend.isEmpty) {
      statusMessage = alreadySent.isEmpty ? 'Nothing to FTP' : 'FTP cancelled';
      notifyListeners();
      return;
    }

    final prefs = _prefs;
    if (prefs == null) {
      sentImages.addAll(toSend);
      savedImages.addAll(toSend);
      lastSentLabel = _formatTime(DateTime.now());
      queuedCount = _ftpWait.length;
      statusMessage = 'Marked sent (prefs unavailable)';
      notifyListeners();
      return;
    }

    final profileName = await prefs.getCurrentFtpProfile();
    final profiles = await prefs.getFtpProfiles();
    final profile = profileName == null ? null : profiles[profileName];

    if (profile == null) {
      if (!_ftpSessionOpen) {
        queuedCount = savedNotSentCount;
        statusMessage = 'Configure an FTP profile first (Settings → FTP)';
        notifyListeners();
      }
      return;
    }

    final host = profile['host']?.toString() ?? '';
    final user = profile['username']?.toString() ?? '';
    final pass = profile['password']?.toString() ?? '';
    final port = int.tryParse(profile['port']?.toString() ?? '') ?? 21;
    final remoteDir = profile['remotePath']?.toString() ?? '/';
    final passive = profile['passiveMode'] != false;
    final renameAs = profile['renameAs']?.toString() ?? '';
    final duplicateFolder = profile['duplicateFolder']?.toString() ?? '';

    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      if (!_ftpSessionOpen) {
        statusMessage = 'FTP profile is incomplete';
        notifyListeners();
      }
      return;
    }

    final jobs = [
      for (final path in toSend)
        _FtpSendJob(
          path: path,
          host: host,
          username: user,
          password: pass,
          port: port,
          remoteDir: remoteDir,
          passive: passive,
          renameAs: renameAs,
          duplicateFolder: duplicateFolder,
          profileName: profileName ?? '',
        ),
    ];

    final starting = !_ftpSessionOpen;
    if (starting) {
      _ftpSessionOpen = true;
      _ftpSessionTotal = jobs.length;
      _ftpSessionDone = 0;
      _ftpSessionOk = 0;
      _ftpSessionError = null;
      _ftpCopyError = null;
      _ftpSessionDuplicateFolder = duplicateFolder;
      transmitting = true;
      transmitProgress = 0;
      transmitStatus = jobs.length > 1 ? 'Connecting…' : 'Uploading…';
    } else {
      _ftpSessionTotal += jobs.length;
    }
    _ftpWait.addAll(jobs);
    queuedCount = _ftpWait.length;
    statusMessage = starting
        ? (jobs.length == 1
            ? 'FTP starting'
            : 'FTP ${jobs.length} · ${ftpConcurrency} at a time')
        : 'Queued ${jobs.length} · ${_ftpWait.length} waiting';
    _publishFtpProgress(force: true);
    unawaited(_ensureFtpDrain());
  }

  void _publishFtpProgress({bool force = false}) {
    final activeSum =
        ftpActiveProgress.values.fold<double>(0, (sum, value) => sum + value);
    final next = _ftpSessionTotal == 0
        ? 0.0
        : ((_ftpSessionDone + activeSum) / _ftpSessionTotal).clamp(0.0, 1.0);
    final waiting = _ftpWait.length;
    final active = ftpActiveProgress.length;
    final shown = _ftpSessionDone + active;
    final status = _ftpSessionTotal <= 1
        ? 'Uploading…'
        : (waiting > 0
            ? 'Sending $shown/$_ftpSessionTotal · $waiting queued'
            : 'Sending $shown/$_ftpSessionTotal');
    final bumped = force ||
        (next - transmitProgress).abs() >= 0.01 ||
        status != transmitStatus;
    transmitProgress = next;
    transmitStatus = status;
    transmitting = true;
    queuedCount = waiting;
    if (bumped) notifyListeners();
  }

  Future<void> _ensureFtpDrain() async {
    if (_ftpDraining) return;
    _ftpDraining = true;
    try {
      final running = <Future<void>>[];
      while (_ftpWait.isNotEmpty || running.isNotEmpty) {
        if (_ftpUserCancelled) _ftpWait.clear();
        while (!_ftpUserCancelled &&
            running.length < ftpConcurrency &&
            _ftpWait.isNotEmpty) {
          final job = _ftpWait.removeAt(0);
          _ftpCancelToken = FtpCancelToken();
          ftpPreviewPath = job.path;
          ftpFileProgress = 0;
          ftpActiveProgress
            ..clear()
            ..[job.path] = 0;
          late final Future<void> task;
          task = _uploadFtpJob(job).whenComplete(() => running.remove(task));
          running.add(task);
          _publishFtpProgress(force: true);
        }
        if (running.isEmpty) break;
        await Future.any(List<Future<void>>.of(running));
      }
    } finally {
      _ftpDraining = false;
      if (_ftpWait.isNotEmpty || ftpActiveProgress.isNotEmpty) {
        await _ensureFtpDrain();
      } else if (_ftpSessionOpen) {
        _finishFtpSession();
      }
    }
  }

  Future<void> _uploadFtpJob(_FtpSendJob job) async {
    final path = job.path;
    String? error;
    var success = false;
    try {
      final fileName = ftpTransferFileName(path, job.renameAs);
      final remote = job.remoteDir.endsWith('/')
          ? '${job.remoteDir}$fileName'
          : '${job.remoteDir}/$fileName';
      final copied = await copyFtpDuplicate(
        sourcePath: path,
        folder: job.duplicateFolder,
        fileName: fileName,
      );
      if (copied != null) _ftpCopyError = copied;
      final result = await FtpClientService.uploadFile(
        host: job.host,
        username: job.username,
        password: job.password,
        localFilePath: path,
        remoteFilePath: remote,
        port: job.port,
        passiveMode: job.passive,
        cancelToken: _ftpCancelToken,
        onProgress: (status, progress, progressError) {
          if (ftpPreviewPath != path) return;
          final value = progress.clamp(0.0, 1.0);
          ftpActiveProgress[path] = value;
          ftpFileProgress = value;
          if (progressError != null && progressError.isNotEmpty) {
            _ftpSessionError = progressError;
          }
          _publishFtpProgress();
        },
      );
      final cancelled = _ftpUserCancelled ||
          _ftpCancelToken?.cancelled == true ||
          result.error == 'Cancelled';
      success = result.success && !cancelled;
      if (success) {
        _ftpSessionOk++;
        sentImages.add(path);
        savedImages.add(path);
      } else if (!cancelled) {
        error = result.details ?? result.error ?? 'Upload failed';
        _ftpSessionError = error;
      } else {
        error = 'Cancelled';
      }
      if (!cancelled) {
        await _recordFtpHistory(
          FtpHistoryEntry(
            at: DateTime.now(),
            fileName: p.basename(path),
            path: path,
            profile: job.profileName,
            success: success,
            error: success ? null : error,
            sessionId: ftpSessionId,
          ),
        );
      }
    } finally {
      ftpActiveProgress.remove(path);
      _ftpSessionDone++;
      if (_ftpSessionOpen) _publishFtpProgress(force: true);
    }
  }

  void cancelFtp() {
    if (!_ftpSessionOpen && !transmitting && _ftpWait.isEmpty) return;
    _ftpUserCancelled = true;
    _ftpWait.clear();
    _ftpCancelToken?.cancel();
    statusMessage = 'Cancelling FTP…';
    notifyListeners();
  }

  void _finishFtpSession() {
    final total = _ftpSessionTotal;
    final ok = _ftpSessionOk;
    final cancelled = _ftpUserCancelled;
    final lastError = _ftpSessionError;
    final copyError = _ftpCopyError;
    final duplicateFolder = _ftpSessionDuplicateFolder;
    _ftpSessionOpen = false;
    _ftpSessionTotal = 0;
    _ftpSessionDone = 0;
    _ftpSessionOk = 0;
    _ftpSessionError = null;
    _ftpCopyError = null;
    _ftpSessionDuplicateFolder = '';
    _ftpUserCancelled = false;
    _ftpCancelToken = null;
    ftpActiveProgress.clear();
    ftpPreviewPath = null;
    ftpFileProgress = 0;
    transmitting = false;
    transmitProgress = 0;
    transmitStatus = null;
    lastSentLabel = _formatTime(DateTime.now());
    queuedCount = savedNotSentCount;
    final copyNote = copyError == null
        ? (duplicateFolder.trim().isEmpty ? '' : ' · copy saved')
        : ' · copy failed: $copyError';
    if (cancelled) {
      statusMessage = ok == 0 ? 'FTP cancelled' : 'FTP cancelled · sent $ok';
    } else if (ok == total) {
      statusMessage =
          (total == 1 ? 'FTP complete' : 'Sent $ok / $total') + copyNote;
    } else if (ok == 0) {
      statusMessage =
          (lastError == null ? 'FTP failed' : 'FTP failed: $lastError') +
              copyNote;
    } else {
      statusMessage = 'Sent $ok / $total'
          '${lastError == null ? '' : ' — $lastError'}'
          '$copyNote';
    }
    notifyListeners();
    if (!cancelled && ok > 0) unawaited(FtpCompleteSound.play());
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
    notifyListeners();
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
    teamPlayersIsHome = null;
    selectedPlayers
      ..clear()
      ..add(row);
    _syncPrimaryPlayer();
    _dropTeammatesIfSubjectLeft();
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
    statusMessage = !hasCaptionSubject || selectedVerb == null
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
    if (transmit) unawaited(transmitPath(path));
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

  @override
  void dispose() {
    _folderWatchGeneration++;
    _stopFolderWatch();
    _jerseyOcrTimer?.cancel();
    _jerseyOcrTimer = null;
    _prefs?.captionFieldVisibilityRevision.removeListener(
      _onCaptionFieldVisibilityChanged,
    );
    _prefs?.ftpProfilesRevision.removeListener(_onFtpProfilesChanged);
    _prefs?.jerseyOcrRevision.removeListener(_onJerseyOcrPreferenceChanged);
    _prefs?.applicationModesRevision.removeListener(_onApplicationModesChanged);
    super.dispose();
  }
}
