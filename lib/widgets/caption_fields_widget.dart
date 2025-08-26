import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/mlb_api_service.dart';
import '../services/api_manager.dart';
import '../services/ftpclient_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

// TextEditingController that can render inline highlights accurately inside the
// TextField by overriding buildTextSpan. This keeps caret/selection perfectly
// aligned with the painted text since EditableText uses this span directly.
class HighlightingTextEditingController extends TextEditingController {
  HighlightingTextEditingController({List<TextRange>? highlightedRanges})
      : _highlightedRanges = highlightedRanges ?? <TextRange>[],
        _invalidRanges = <TextRange>[];

  List<TextRange> _highlightedRanges;
  List<TextRange> _invalidRanges;

  List<TextRange> get highlightedRanges => _highlightedRanges;
  set highlightedRanges(List<TextRange> ranges) {
    _highlightedRanges = ranges;
    // notifyListeners is called when text changes; for style-only changes we
    // still need to notify so the widget rebuilds with new spans
    notifyListeners();
  }

  List<TextRange> get invalidRanges => _invalidRanges;
  set invalidRanges(List<TextRange> ranges) {
    _invalidRanges = ranges;
    // notifyListeners is called when text changes; for style-only changes we
    // still need to notify so the widget rebuilds with new spans
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool withComposing = false,
  }) {
    final TextStyle baseStyle = style ?? const TextStyle();
    final TextStyle validHighlightStyle = baseStyle.copyWith(
      backgroundColor: Colors.lightBlue.withOpacity(0.2),
      fontWeight: FontWeight.w500,
    );
    final TextStyle invalidHighlightStyle = baseStyle.copyWith(
      backgroundColor: Colors.grey.withOpacity(0.3),
      fontWeight: FontWeight.w500,
      color: Colors.grey.shade600,
    );

    final String fullText = text;
    if (_highlightedRanges.isEmpty && _invalidRanges.isEmpty ||
        fullText.isEmpty) {
      return TextSpan(style: baseStyle, text: fullText);
    }

    // Combine and sort all ranges
    final List<TextRange> allRanges = <TextRange>[];
    for (final range in _highlightedRanges) {
      allRanges.add(range);
    }
    for (final range in _invalidRanges) {
      allRanges.add(range);
    }
    allRanges.sort((a, b) => a.start.compareTo(b.start));

    final List<InlineSpan> children = <InlineSpan>[];
    int cursor = 0;
    for (final TextRange r in allRanges) {
      final int start = r.start.clamp(0, fullText.length);
      final int end = r.end.clamp(0, fullText.length);
      if (start > cursor) {
        children.add(TextSpan(
            style: baseStyle, text: fullText.substring(cursor, start)));
      }
      if (end > start) {
        // Determine if this range is valid or invalid
        bool isValid = _highlightedRanges.contains(r);
        final TextStyle highlightStyle =
            isValid ? validHighlightStyle : invalidHighlightStyle;
        children.add(TextSpan(
            style: highlightStyle, text: fullText.substring(start, end)));
      }
      cursor = end;
    }
    if (cursor < fullText.length) {
      children
          .add(TextSpan(style: baseStyle, text: fullText.substring(cursor)));
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

// Formatter that converts any backspace/delete within a highlighted range into
// deletion of the entire highlighted token. This guarantees single-keypress
// removal of a token without relying on heuristics in listeners.
class HighlightedTokenDeletionFormatter extends TextInputFormatter {
  HighlightedTokenDeletionFormatter({
    required this.getRanges,
    required this.onTokenDeleted,
  });

  // Supplies the current highlight ranges from the owning State
  final List<TextRange> Function() getRanges;
  // Callback with the deleted range (indices relative to OLD text) and its text
  final void Function(TextRange deletedRange, String deletedText)
      onTokenDeleted;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only care about deletions
    if (newValue.text.length >= oldValue.text.length) {
      return newValue;
    }

    final List<TextRange> ranges = getRanges();
    if (ranges.isEmpty) return newValue;

    // Determine deletion window
    // Typical backspace: selection moved left by 1; forward delete: stays
    final int delta = oldValue.text.length - newValue.text.length;
    int startIndex;
    if (newValue.selection.baseOffset < oldValue.selection.baseOffset) {
      // Backspace
      startIndex = newValue.selection.baseOffset;
    } else {
      // Delete
      startIndex = oldValue.selection.baseOffset;
    }
    final int endIndex = startIndex + delta;

    // If any range intersects the deleted window, delete the entire range
    for (final TextRange r in ranges) {
      final bool intersects = !(endIndex <= r.start || startIndex >= r.end);
      if (intersects) {
        final String tokenText = oldValue.text.substring(r.start, r.end);
        onTokenDeleted(r, tokenText);
        final String replaced = oldValue.text.replaceRange(r.start, r.end, '');
        return newValue.copyWith(
          text: replaced,
          selection: TextSelection.collapsed(offset: r.start),
          composing: TextRange.empty,
        );
      }
    }

    return newValue;
  }
}

// Custom button widget with cursor styling and press feedback
class CustomButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const CustomButton({
    super.key,
    required this.onTap,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _isPressed
              ? Matrix4.translationValues(0, 2, 0)
              : Matrix4.translationValues(0, 0, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: _isPressed ? 0.8 : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class CaptionFieldsWidget extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>?)? onMetadataUpdated;
  final String? homeTeam;
  final String? awayTeam;
  final VoidCallback? onNextImage;
  final VoidCallback? onPreviousImage;
  final VoidCallback? onReset;
  final String? personalityOverride;
  final Function(List<String>)? onImagesLoaded;
  final List<Player>? preloadedHomeRoster;
  final List<Player>? preloadedAwayRoster;
  final String? currentImagePath;
  final int? currentIndex;
  final int? totalImages;
  final Future<void> Function()? onSaveIptc;
  final Future<void> Function()? onSaveIptcBackground;
  final Function(String)? onImageUploaded; // Callback when image is uploaded
  final Function(String, double)?
      onUploadProgress; // Callback for upload progress

  const CaptionFieldsWidget({
    super.key,
    this.metadata,
    this.onMetadataUpdated,
    this.homeTeam,
    this.awayTeam,
    this.onNextImage,
    this.onPreviousImage,
    this.onReset,
    this.personalityOverride,
    this.onImagesLoaded,
    this.preloadedHomeRoster,
    this.preloadedAwayRoster,
    this.currentImagePath,
    this.currentIndex,
    this.totalImages,
    this.onSaveIptc,
    this.onSaveIptcBackground,
    this.onImageUploaded,
    this.onUploadProgress,
  });

  @override
  State<CaptionFieldsWidget> createState() => _CaptionFieldsWidgetState();
}

class _CaptionFieldsWidgetState extends State<CaptionFieldsWidget> {
  // Controllers
  final HighlightingTextEditingController captionController =
      HighlightingTextEditingController();
  final TextEditingController personalityController = TextEditingController();
  final TextEditingController _homeSearchController = TextEditingController();
  final TextEditingController _awaySearchController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController provinceController = TextEditingController();
  final TextEditingController stadiumController = TextEditingController();
  // Creator field is now handled by metadata widget only
  final TextEditingController customCelebrationController =
      TextEditingController();
  final TextEditingController customDejectionController =
      TextEditingController();
  // Magic bar controller (kept to satisfy existing references in UI)
  final TextEditingController customBetweenPlayersController =
      TextEditingController();
  final TextEditingController _managerNameController = TextEditingController();
  String _homeSearchText = '';
  String _awaySearchText = '';
  String _managerName = '';

  // Prevent recursive onChanged updates for caption shortcuts
  bool _isProcessingCaptionShortcut = false;

  // Highlighting state for expanded tokens
  List<TextRange> _highlightedRanges = [];
  final Map<String, String> _tokenToPlayerName =
      {}; // Maps expanded text to player name for personality field

  // Track previous caption text to detect deletions (e.g., backspace)
  final String _prevCaptionText = '';
  TextSelection? _prevCaptionSelection;

  // Magic input team hint (true = home, false = away) used to disambiguate same-number players
  bool? _magicTeamHint;
  // Track last auto-selected jersey per team so we can swap as user continues typing
  String? _autoSelectedHomeJersey;
  String? _autoSelectedAwayJersey;
  // Track last auto-typed token context to detect progressive typing
  String? _lastAutoTokenNumber;
  bool? _lastAutoTokenIsHome;
  String?
      _lastAutoTokenText; // Track the exact token text that caused selection

  // Date
  DateTime selectedDate = DateTime.now();

  // Verb selection
  String? _selectedVerb;
  String? _selectedActionVerb; // Stores the verb for caption generation
  String? _selectedHittingAction;
  bool _showExtraInnings = false;
  int _extraInningsPage = 0;

  String? _selectedHomeRunType;
  String? _selectedTagsAction; // For Tags submenu
  String? _selectedBase; // Track which base is selected for options
  String?
      _selectedBaseBeforeTaggedOut; // Track base before Tagged Out was selected
  int? _rbiCount;
  bool _isBatterRunning = false;
  bool _isSliding = false;
  bool _showFieldingOptions = false;
  final bool _removeAccent = false; // Disabled diacritic removal
  final bool _disableFtp = false; // Default to false (FTP enabled)
  final int _ftpPictureNumber =
      1; // Counter for FTP picture number, starting at 001

  // FTP Settings
  String _ftpHost = 'ftp.photoshelter.com';
  String _ftpUsername = 'mb1';
  String _ftpPassword = '';
  int _ftpPort = 21;
  String _ftpRemotePath = '';
  bool _ftpPassiveMode = true;

  // FTP Profile Management
  Map<String, Map<String, dynamic>> _ftpProfiles = {};
  String? _currentFtpProfile;
  String? _selectedFieldingAction;
  String? _selectedBaseRunningAction;
  String? _selectedStealBase;
  bool _showStealAgainstPlayer = false;
  bool _isSoloCelebration = false;
  Set<String> celebrateWith = {};
  Set<String> celebrateAgainst = {};
  String? _selectedCelebrationType;
  String? _selectedDejectionType;
  bool _isCelebratingScoring = false;
  bool _isCelebratingWithTeammates = false;
  bool _cameFromCelebration =
      false; // Track if we came from celebration section
  String? _selectedAtBatAction;
  String? _selectedBattingAction;

  // Custom text inning selector
  bool _showCustomTextInningSelector = false;
  String? _originalCaptionBeforeCustomVerb; // Store original caption

  // Smart custom text field state
  bool _isPlayerSearchMode = true;
  List<Player> _filteredPlayers = [];
  final Set<String> _selectedPlayerNumbers = {};
  String _playerSearchText = '';
  bool _noPlayersFound = false;

  // Magic input player selection state
  List<Player> _magicInputMatchingPlayers = [];
  String _magicInputActionText = '';
  bool _showMagicInputPlayerOptions = false;
  // Live text typed in the magic bar used to drive verb highlighting
  String _magicBarVerbInput = '';
  // Controller for the Firebar to allow programmatic clearing on reset
  final TextEditingController _magicBarController = TextEditingController();
  // Focus node for Firebar to control when verb bolding is visible
  final FocusNode _magicBarFocusNode = FocusNode();

  bool _shouldShowRbiInlineHint() {
    const verbsWithRbi = {
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'Sacrifice Fly',
    };
    return verbsWithRbi.contains(_selectedVerb);
  }

  String _rbiShortcutExample() {
    // Map selected verb to its firebar shortcut letters
    const Map<String, String> verbToShortcut = {
      'Single': 'sin',
      'Double': 'dou',
      'Triple': 'tri',
      'Home Run': 'hr',
      'Sacrifice Fly': 'sf',
    };
    final String letters = verbToShortcut[_selectedVerb] ?? 'hr';
    return '${letters}3';
  }

  String _rbiHintNoun() {
    // Use "runs" for Home Run, otherwise "RBI"
    return _selectedVerb == 'Home Run' ? 'runs' : 'RBI';
  }

  // Whether the user is currently typing the first magic player token (e.g., "h27")
  bool _typingFirstMagicToken = false;
  bool _waitingForHomeVisitorChoice = false;

  // Team data
  final bool _isConnectedToApi = false;
  String? homeTeamStadium;
  String? awayTeamStadium;

  // Caption building data
  String? selectedHomeTeam;
  String? selectedAwayTeam;
  Set<String> selectedHomePlayers = {};
  Set<String> selectedAwayPlayers = {};

  // Sort options for player lists
  String _homeSortOption = 'number'; // 'number', 'lastName', 'firstName'
  String _awaySortOption = 'number';
  bool _homeSortAscending = true; // true = ascending, false = descending
  bool _awaySortAscending = true;

  // Player display mode - list or grid
  bool _homePlayerGridMode = true; // false = list, true = grid
  bool _awayPlayerGridMode = true;

  String? selectedCaptionVerb;

  // Track which team was selected first (for determining main subject)
  bool? _firstTeamSelected;

  // Track the first player selected (for star indicator)
  String? _firstPlayerSelected;

  // API Manager and roster data
  final ApiManager _apiManager = ApiManager();
  List<Player> _homeRoster = [];
  List<Player> _awayRoster = [];
  bool _isLoadingRosters = false;

  // Static teams list for dropdown
  final List<String> teamsList = [
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

  // Additional verb building state
  int? _selectedRbiInning;
  bool _isDivingCatch = false;
  bool _walkOff = false;
  bool _isPriorToGame = false; // Track if "prior to the game" is selected

  // Preserve per-hit-type selections
  final Map<String, int?> _rbiCountByHit = {};
  final Map<String, String?> _homeRunTypeByHit = {};
  final Map<String, int?> _inningByHit = {};
  final Map<String, bool?> _batterRunningByHit = {};

  // Caption state
  final String _lastCaption = '';

  // Verb categories
  final Map<String, List<String>> verbCategories = {
    'Offense': [
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'Sacrifice Fly',
      'At Bat',
      'Swings',
      'Bunts',
      'Hit by Pitch'
    ],
    'Defense': [
      'Pitching',
      'Catches',
      'Throws',
      'Tags',
      'Groundball',
      'Fielding Position',
      'Double Play',
      'Triple Play'
    ],
    'Running': ['Steals', 'Slides', 'Runs', 'Rounds'],
    'Reactions': ['Celebrates', 'Dejection', 'Post Game Win', 'Post Game Loss'],
    'Non Game-Action': [
      'Looks On',
      'Batting Practice',
      'Fielding Practice',
      'Takes the Field',
      'Comes Off the Field',
      'National Anthem',
      'Stretching',
      'Warm Ups',
      'Pitching Change'
    ],
  };

  // Match a magic-bar verb token to a canonical verb using the following rules:
  // - Single-word verbs: the first 2–3 letters are accepted (require at least 2)
  // - Multi-word verbs: use the acronym of the first letters of each word, excluding "the".
  //   Accept the full acronym or a prefix of it with length >= 2 (e.g., "pgw" for Post Game Win, "pg" also acceptable).
  String? _matchVerbToken(String rawToken) {
    if (rawToken.isEmpty) return null;
    final token = rawToken.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (token.length < 2) return null; // require at least two letters

    // Build a flat list of verbs
    final List<String> allVerbs = [];
    for (final entry in verbCategories.entries) {
      for (final v in entry.value) {
        if (!allVerbs.contains(v)) allVerbs.add(v);
      }
    }

    for (final verb in allVerbs) {
      final words = verb.split(' ');
      final filtered = words
          .where((w) => w.trim().isNotEmpty && w.toLowerCase() != 'the')
          .toList();
      if (filtered.length > 1) {
        final acronym = filtered.map((w) => w[0].toLowerCase()).join();
        if (token.length <= acronym.length && acronym.startsWith(token)) {
          return verb;
        }
      } else {
        final first = filtered.first.toLowerCase();
        // Accept first 2-3 letters
        if (token.length <= 3 && first.startsWith(token)) {
          return verb;
        }
      }
    }

    return null;
  }

  final bool _isResetting = false;

  // Add a flag to track if the user has manually reset the fields.
  bool _hasBeenReset = false;

  // Track team positioning (true = home on left, false = home on right)
  bool _homeOnLeft = true;

  // Build team dropdown widget
  Widget _buildTeamDropdown({
    required bool isHome,
    required String? selectedTeam,
    required ValueChanged<String?> onTeamChanged,
  }) {
    // Filter out the other team
    final availableTeams = isHome
        ? teamsList.where((team) => team != selectedAwayTeam).toList()
        : teamsList.where((team) => team != selectedHomeTeam).toList();

    final dropdown = Material(
      elevation: 2.0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white,
        ),
        child: PopupMenuButton<String>(
          initialValue: selectedTeam,
          onSelected: onTeamChanged,
          constraints: const BoxConstraints(maxHeight: 600),
          itemBuilder: (context) => availableTeams
              .map(
                (item) => PopupMenuItem<String>(
                  value: item,
                  height: 14,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  child: Container(
                    height: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Row(
                      children: [
                        // Home/Away symbol
                        if (isHome)
                          Icon(Icons.home,
                              size: 12, color: Colors.grey.shade700),
                        if (!isHome)
                          Icon(Icons.flight,
                              size: 12, color: Colors.grey.shade700),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                // Label
                Text(
                  '${isHome ? "Home" : "Away"}: ',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                // Home/Away symbol for selected item
                if (selectedTeam != null) ...[
                  if (isHome)
                    Icon(Icons.home, size: 11, color: Colors.grey.shade700),
                  if (!isHome)
                    Icon(Icons.flight, size: 11, color: Colors.grey.shade700),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      selectedTeam,
                      style: const TextStyle(fontSize: 11, color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  const Expanded(
                    child: Text(
                      'Select Team',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ),
    );

    return dropdown;
  }

  // Team color mapping
  Color _getTeamColor(String? teamName) {
    if (teamName == null) return Colors.grey.shade700;

    final teamColors = {
      'New York Yankees': Colors.blue.shade900,
      'Boston Red Sox': Colors.red.shade700,
      'Toronto Blue Jays': Colors.blue.shade600,
      'Baltimore Orioles': Colors.orange.shade700,
      'Tampa Bay Rays': Colors.blue.shade400,
      'Cleveland Guardians': Colors.red.shade800,
      'Minnesota Twins': Colors.blue.shade700,
      'Detroit Tigers': Colors.orange.shade600,
      'Chicago White Sox': Colors.black,
      'Kansas City Royals': Colors.amber.shade600, // Gold
      'Houston Astros': Colors.blue.shade800, // Navy blue
      'Texas Rangers': Colors.blue.shade800, // Navy blue
      'Seattle Mariners': Colors.teal.shade600, // Teal
      'Los Angeles Angels': Colors.white, // White
      'Oakland Athletics': Colors.yellow.shade600, // Yellow
      'Atlanta Braves': Colors.red.shade700,
      'Philadelphia Phillies': Colors.red.shade600,
      'New York Mets': Colors.blue.shade600,
      'Washington Nationals': Colors.red.shade700,
      'Miami Marlins': Colors.orange.shade600,
      'Milwaukee Brewers': Colors.blue.shade700,
      'Chicago Cubs': Colors.blue.shade800,
      'St. Louis Cardinals': Colors.red.shade700,
      'Cincinnati Reds': Colors.red.shade600,
      'Pittsburgh Pirates': Colors.black,
      'Los Angeles Dodgers': Colors.blue.shade800,
      'San Francisco Giants': Colors.orange.shade600,
      'San Diego Padres': Colors.brown.shade600,
      'Colorado Rockies': Colors.purple.shade700,
      'Arizona Diamondbacks': Colors.red.shade700,
    };

    return teamColors[teamName] ?? Colors.grey.shade700;
  }

  // Secondary team color mapping for contrast
  Color _getTeamSecondaryColor(String? teamName) {
    if (teamName == null) return Colors.grey.shade500;

    final teamSecondaryColors = {
      'New York Yankees': Colors.white, // White pinstripes
      'Boston Red Sox': Colors.blue.shade800, // Navy blue
      'Toronto Blue Jays': Colors.white, // White
      'Baltimore Orioles': Colors.black, // Black
      'Tampa Bay Rays': Colors.yellow.shade600, // Yellow
      'Cleveland Guardians': Colors.blue.shade800, // Navy blue
      'Minnesota Twins': Colors.red.shade600, // Red
      'Detroit Tigers': Colors.white, // White
      'Chicago White Sox': Colors.white, // White
      'Kansas City Royals': Colors.amber.shade600, // Gold
      'Houston Astros': Colors.blue.shade800, // Navy blue
      'Texas Rangers': Colors.blue.shade800, // Navy blue
      'Seattle Mariners': Colors.teal.shade600, // Teal
      'Los Angeles Angels': Colors.white, // White
      'Oakland Athletics': Colors.yellow.shade600, // Yellow
      'Atlanta Braves': Colors.blue.shade800, // Navy blue
      'Philadelphia Phillies': Colors.blue.shade800, // Navy blue
      'New York Mets': Colors.orange.shade600, // Orange
      'Washington Nationals': Colors.blue.shade800, // Navy blue
      'Miami Marlins': Colors.black, // Black
      'Milwaukee Brewers': Colors.yellow.shade600, // Gold
      'Chicago Cubs': Colors.red.shade600, // Red
      'St. Louis Cardinals': Colors.white, // White
      'Cincinnati Reds': Colors.white, // White
      'Pittsburgh Pirates': Colors.yellow.shade600, // Gold
      'Los Angeles Dodgers': Colors.white, // White
      'San Francisco Giants': Colors.black, // Black
      'San Diego Padres': Colors.yellow.shade600, // Gold
      'Colorado Rockies': Colors.black, // Black
      'Arizona Diamondbacks': Colors.teal.shade600, // Teal
    };

    return teamSecondaryColors[teamName] ?? Colors.grey.shade500;
  }

  // Opens a dialog that allows editing of the current team's settings
  // - Change the team entirely (dropdown)
  // - Edit player jersey numbers and names
  Future<void> _showTeamEditorDialog({required bool isHome}) async {
    String? tempSelectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
    List<Player> tempRoster =
        List<Player>.from(isHome ? _homeRoster : _awayRoster);
    bool isLoading = false;

    // Sort roster by jersey number
    tempRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '') ?? 999;
      return aNum.compareTo(bNum);
    });

    final Map<int, String> indexToEditedName = {};
    final Map<int, String> indexToEditedNumber = {};

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(
                'Edit Teams',
                style: const TextStyle(fontSize: 14),
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Team switcher
                    Row(
                      children: [
                        const Text('Team:', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 8),
                        // Home team tab
                        GestureDetector(
                          onTap: () async {
                            setDialogState(() {
                              tempSelectedTeam = selectedHomeTeam;
                              isLoading = true;
                            });
                            try {
                              final fetched = await _apiManager
                                  .fetchTeamRoster(selectedHomeTeam!);
                              setDialogState(() {
                                tempRoster = List<Player>.from(fetched);
                                // Sort roster by jersey number
                                tempRoster.sort((a, b) {
                                  final aNum =
                                      int.tryParse(a.jerseyNumber ?? '') ?? 999;
                                  final bNum =
                                      int.tryParse(b.jerseyNumber ?? '') ?? 999;
                                  return aNum.compareTo(bNum);
                                });
                                indexToEditedName.clear();
                                indexToEditedNumber.clear();
                                isLoading = false;
                              });
                            } catch (_) {
                              // Leave roster as is on error
                              setDialogState(() {
                                isLoading = false;
                              });
                            }
                          },
                          child: Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: tempSelectedTeam == selectedHomeTeam
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade100,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                bottomLeft: Radius.circular(4),
                              ),
                              border: Border.all(
                                color: tempSelectedTeam == selectedHomeTeam
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.home,
                                    size: 10,
                                    color: tempSelectedTeam == selectedHomeTeam
                                        ? Colors.black87
                                        : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _getTeamAbbreviation(
                                        selectedHomeTeam ?? 'Home'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          tempSelectedTeam == selectedHomeTeam
                                              ? Colors.black87
                                              : Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Away team tab
                        GestureDetector(
                          onTap: () async {
                            setDialogState(() {
                              tempSelectedTeam = selectedAwayTeam;
                              isLoading = true;
                            });
                            try {
                              final fetched = await _apiManager
                                  .fetchTeamRoster(selectedAwayTeam!);
                              setDialogState(() {
                                tempRoster = List<Player>.from(fetched);
                                // Sort roster by jersey number
                                tempRoster.sort((a, b) {
                                  final aNum =
                                      int.tryParse(a.jerseyNumber ?? '') ?? 999;
                                  final bNum =
                                      int.tryParse(b.jerseyNumber ?? '') ?? 999;
                                  return aNum.compareTo(bNum);
                                });
                                indexToEditedName.clear();
                                indexToEditedNumber.clear();
                                isLoading = false;
                              });
                            } catch (_) {
                              // Leave roster as is on error
                              setDialogState(() {
                                isLoading = false;
                              });
                            }
                          },
                          child: Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: tempSelectedTeam == selectedAwayTeam
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade100,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(4),
                                bottomRight: Radius.circular(4),
                              ),
                              border: Border.all(
                                color: tempSelectedTeam == selectedAwayTeam
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.flight,
                                    size: 10,
                                    color: tempSelectedTeam == selectedAwayTeam
                                        ? Colors.black87
                                        : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _getTeamAbbreviation(
                                        selectedAwayTeam ?? 'Away'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          tempSelectedTeam == selectedAwayTeam
                                              ? Colors.black87
                                              : Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Column headers
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              'Number',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Name',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Editable roster
                    SizedBox(
                      height: 380,
                      child: isLoading
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Loading roster...',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : Scrollbar(
                              child: ListView.separated(
                                itemCount: tempRoster.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final player = tempRoster[index];
                                  final currentName =
                                      indexToEditedName[index] ??
                                          player.fullName;
                                  final currentNumber =
                                      indexToEditedNumber[index] ??
                                          (player.jerseyNumber ?? '');
                                  return Row(
                                    children: [
                                      SizedBox(
                                        width: 64,
                                        child: TextField(
                                          controller: TextEditingController(
                                              text: currentNumber)
                                            ..selection =
                                                TextSelection.collapsed(
                                                    offset:
                                                        currentNumber.length),
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade400),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 6),
                                          ),
                                          onChanged: (v) => setDialogState(() {
                                            indexToEditedNumber[index] = v;
                                          }),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: TextEditingController(
                                              text: currentName)
                                            ..selection =
                                                TextSelection.collapsed(
                                                    offset: currentName.length),
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade400),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 6),
                                          ),
                                          onChanged: (v) => setDialogState(() {
                                            indexToEditedName[index] = v;
                                          }),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child:
                        const Text('Cancel', style: TextStyle(fontSize: 11))),
                TextButton(
                  onPressed: () {
                    final List<Player> updated = [];
                    for (int i = 0; i < tempRoster.length; i++) {
                      final base = tempRoster[i];
                      final editedName =
                          (indexToEditedName[i] ?? base.fullName).trim();
                      final editedNumber =
                          (indexToEditedNumber[i] ?? base.jerseyNumber ?? '')
                              .trim();
                      final jerseyNumber =
                          editedNumber.isEmpty ? null : editedNumber;
                      final displayName = jerseyNumber != null
                          ? '$editedName #$jerseyNumber'
                          : editedName;
                      updated.add(Player(
                        fullName: editedName,
                        firstName: editedName.split(' ').first,
                        jerseyNumber: jerseyNumber,
                        displayName: displayName,
                      ));
                    }

                    setState(() {
                      if (isHome) {
                        selectedHomeTeam = tempSelectedTeam;
                        _homeRoster = updated;
                      } else {
                        selectedAwayTeam = tempSelectedTeam;
                        _awayRoster = updated;
                      }
                    });
                    _updateCaption();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save', style: TextStyle(fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Method to get current values from caption-related controllers
  Map<String, String> getCurrentCaptionValues() {
    return {
      'Caption-Abstract': captionController.text,
      'XMP:Description':
          captionController.text, // Photo Mechanic compatible caption field
      'ImageDescription': captionController.text, // EXIF description field
      'XMP-getty:Personality': personalityController.text,
      'Sub-location': stadiumController.text,
      'City': cityController.text,
      'Province-State': provinceController.text,
    };
  }

  @override
  void initState() {
    super.initState();
    // Rebuild when magic bar focus changes to toggle verb bolding
    _magicBarFocusNode.addListener(() {
      setState(() {});
    });
    _homeSearchController.addListener(() {
      setState(() {
        _homeSearchText = _homeSearchController.text;
      });
    });
    _awaySearchController.addListener(() {
      setState(() {
        _awaySearchText = _awaySearchController.text;
      });
    });
    _initializeSampleData();
    if (widget.personalityOverride != null) {
      personalityController.text = widget.personalityOverride!;
    }
    _loadFtpProfiles();
  }

  @override
  void dispose() {
    _homeSearchController.dispose();
    _awaySearchController.dispose();
    _magicBarController.dispose();
    _magicBarFocusNode.dispose();
    super.dispose();
  }

  void _initializeSampleData() {
    // Initialize with teams from app bar, or null if not provided
    selectedHomeTeam = widget.homeTeam;
    selectedAwayTeam = widget.awayTeam;

    // Don't initialize controllers with default values - only load from EXIF data

    // Load rosters from MLB API only if both teams are provided
    if (selectedHomeTeam != null && selectedAwayTeam != null) {
      _loadTeamRosters();
    }
  }

  Future<void> _fetchAndSetVenueForGame() async {
    if (selectedHomeTeam == null || selectedAwayTeam == null) return;

    // Get the photo date from metadata
    DateTime gameDate = DateTime.now();
    if (widget.metadata != null) {
      final dateTimeOriginal = widget.metadata!['DateTimeOriginal']?.toString();
      final createDate = widget.metadata!['CreateDate']?.toString();
      final modifyDate = widget.metadata!['ModifyDate']?.toString();

      // Try to parse the date from EXIF data
      final dateString = dateTimeOriginal ?? createDate ?? modifyDate;
      if (dateString != null && dateString.isNotEmpty) {
        try {
          // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
          final parts = dateString.split(' ');
          if (parts.isNotEmpty) {
            final datePart = parts[0];
            final dateComponents = datePart.split(':');
            if (dateComponents.length >= 3) {
              final year = int.parse(dateComponents[0]);
              final month = int.parse(dateComponents[1]);
              final day = int.parse(dateComponents[2]);
              gameDate = DateTime(year, month, day);
              print(
                  'DEBUG: Venue fetch - Parsed game date: ${gameDate.toIso8601String().split('T')[0]}');
            }
          }
        } catch (e) {
          print('Error parsing photo date: $e');
          // Fallback to current date
        }
      } else {
        print(
            'DEBUG: Venue fetch - No date string found in metadata, using current date');
      }
    } else {}

    try {
      final venue = await _apiManager.fetchVenueForGame(
          selectedHomeTeam!, selectedAwayTeam!, gameDate);
      // Removed auto-population of stadium and city/state from venue data
      // Only load values from EXIF metadata, not from API
    } catch (e) {
      print('Error fetching venue for game: $e');
    }
  }

  // Removed _setCityFromStadium function - no auto-population of city/state

  Future<void> _loadTeamRosters() async {
    if (selectedHomeTeam == null || selectedAwayTeam == null) return;

    // Check if we have preloaded roster data
    if (widget.preloadedHomeRoster != null &&
        widget.preloadedAwayRoster != null) {
      setState(() {
        _homeRoster = widget.preloadedHomeRoster!;
        _awayRoster = widget.preloadedAwayRoster!;
        _isLoadingRosters = false;

        // Clear any existing selections since rosters have changed
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection
        print(
            'DEBUG: Using preloaded rosters: ${_homeRoster.length} home players, ${_awayRoster.length} away players');
      });

      // Fetch venue information for the specific game and update stadium field
      if (selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          stadiumController.text.isEmpty) {
        _fetchAndSetVenueForGame();
      }

      return; // Skip API calls since we have preloaded data
    }

    setState(() {
      _isLoadingRosters = true;
    });

    try {
      // Load both team rosters and team info in parallel
      final futures = await Future.wait([
        _apiManager.fetchTeamRoster(selectedHomeTeam!),
        _apiManager.fetchTeamRoster(selectedAwayTeam!),
        _apiManager.fetchTeams().then((teams) => teams.firstWhere(
              (team) => team.name == selectedHomeTeam,
              orElse: () => throw Exception('Team not found'),
            )),
        _apiManager.fetchTeams().then((teams) => teams.firstWhere(
              (team) => team.name == selectedAwayTeam,
              orElse: () => throw Exception('Team not found'),
            )),
      ]);

      setState(() {
        _homeRoster = futures[0] as List<Player>;
        _awayRoster = futures[1] as List<Player>;
        final homeTeamInfo = futures[2] as TeamInfo?;
        final awayTeamInfo = futures[3] as TeamInfo?;

        // Set stadium names from API (will be fetched separately for balldontlie)
        homeTeamStadium = null; // Will be fetched separately
        awayTeamStadium = null; // Will be fetched separately

        // Fetch venue information for the specific game and update stadium field
        if (selectedHomeTeam != null &&
            selectedAwayTeam != null &&
            stadiumController.text.isEmpty) {
          _fetchAndSetVenueForGame();
        }

        _isLoadingRosters = false;

        // Clear any existing selections since rosters have changed
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection
      });

      print(
          'Successfully loaded rosters: ${_homeRoster.length} home players, ${_awayRoster.length} away players');
      print('Home team stadium: $homeTeamStadium');
      print('Away team stadium: $awayTeamStadium');
    } catch (e) {
      print('Error loading team rosters: $e');
      setState(() {
        _isLoadingRosters = false;
      });

      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load team rosters: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(CaptionFieldsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.personalityOverride != null &&
        widget.personalityOverride != oldWidget.personalityOverride) {
      personalityController.text = widget.personalityOverride!;
    }
    if (widget.metadata != oldWidget.metadata) {
      // Reset selections when metadata changes (new image loaded)
      resetCaptionSelections();
      _loadMetadata();
    }

    // Check if teams have changed
    if (oldWidget.homeTeam != widget.homeTeam ||
        oldWidget.awayTeam != widget.awayTeam) {
      setState(() {
        selectedHomeTeam = widget.homeTeam;
        selectedAwayTeam = widget.awayTeam;

        // Clear existing selections and rosters
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection

        _homeRoster.clear();
        _awayRoster.clear();
      });

      // Load new rosters if both teams are selected
      if (selectedHomeTeam != null && selectedAwayTeam != null) {
        _loadTeamRosters();
      }
    }
  }

  void _loadMetadata() {
    // If a reset has been performed, do not load metadata again.
    if (_hasBeenReset) return;

    if (widget.metadata == null) return;
    final meta = widget.metadata!;

    // Load Caption: Prefer IPTC "Caption-Abstract", fallback to EXIF "ImageDescription"
    final dynamic captionAbstract = meta['Caption-Abstract'];
    final dynamic imageDescription = meta['ImageDescription'];
    final extractedCaption =
        (captionAbstract is String ? captionAbstract : '') ??
            (imageDescription is String ? imageDescription : '') ??
            '';

    // Load Personality: Read from XMP-getty:Personality
    final dynamic extractedPersonality =
        meta['XMP-getty:Personality'] ?? meta['Personality'];
    final personInImageText = (extractedPersonality is List)
        ? extractedPersonality.join(';')
        : (extractedPersonality is String ? extractedPersonality : '');

    // Load location fields from metadata
    final dynamic subLocation = meta['Sub-location'];
    final dynamic city = meta['City'];
    final dynamic province = meta['Province-State'];
    final extractedStadium = subLocation is String ? subLocation : '';
    final extractedCity = city is String ? city : '';
    final extractedProvince = province is String ? province : '';

    // Creator field is now handled by metadata widget only

    setState(() {
      captionController.text = extractedCaption;
      personalityController.text = personInImageText;

      // Only set personality from metadata if the user hasn't manually reset.
      if (!_hasBeenReset) {
        personalityController.text = personInImageText;
      }

      // Load location fields from metadata
      stadiumController.text = extractedStadium;
      cityController.text = extractedCity;
      provinceController.text = extractedProvince;

      // Creator field is now handled by metadata widget only
    });
  }

  // Reset all caption building selections when navigating to a new image
  void resetCaptionSelections() {
    setState(() {
      // Clear player selections
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();
      _firstPlayerSelected = null;
      _firstTeamSelected = null;

      // Clear verb selections
      _selectedVerb = null;
      _selectedActionVerb = null;
      _selectedHittingAction = null;

      // Clear celebration settings
      _isCelebratingWithTeammates = false;

      // Clear other selections
      _rbiCount = null;
      _selectedRbiInning = null;

      // Clear search states
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = true; // Reset to player search mode
      _showCustomTextInningSelector = false; // Hide inning selector
      _magicInputMatchingPlayers.clear();
      _magicInputActionText = '';
      _waitingForHomeVisitorChoice = false;

      // Clear custom text fields
      customCelebrationController.clear();
      customDejectionController.clear();
      // Magic bar removed: no-op placeholder

      // Clear search bars
      _homeSearchController.clear();
      _awaySearchController.clear();
      _homeSearchText = '';
      _awaySearchText = '';

      // Reset hasBeenReset flag to allow metadata loading
      _hasBeenReset = false;
    });
  }

  // Public method to reset caption selections (can be called from parent)
  void resetSelections() {
    resetCaptionSelections();
  }

  // Process player token found in caption box
  void _processCaptionPlayerToken(
      String value, RegExpMatch match, Player player, bool isHome) {
    _isProcessingCaptionShortcut = true;

    // Replace the token with the player name
    final beforeToken = value.substring(0, match.start);
    final afterToken = value.substring(match.end);
    final replacement = '${player.displayName ?? 'Unknown Player'} ';

    final newText = beforeToken + replacement + afterToken;
    captionController.text = newText;

    // Use the caption box's built-in highlighting system for a lighter color
    final replacementStart = beforeToken.length;
    final replacementEnd =
        replacementStart + replacement.length - 1; // Exclude the trailing space

    setState(() {
      _highlightedRanges.clear();
      _highlightedRanges.add(TextRange(
        start: replacementStart,
        end: replacementEnd,
      ));
    });

    // Position cursor at the end of the highlighted text
    captionController.selection = TextSelection.fromPosition(
      TextPosition(offset: replacementEnd + 1), // +1 to go after the space
    );

    // Visually select the player in the picker
    _selectPlayerChipByNumber(
      isHomeTeam: isHome,
      jerseyNumber: player.jerseyNumber ?? '',
      isProgressive: true,
    );

    // Update personality field
    final current = personalityController.text.trim();
    final parts = current.isEmpty
        ? <String>[]
        : current
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    if (!parts.contains(player.fullName ?? '')) {
      parts.add(player.fullName ?? '');
      personalityController.text = parts.join(';');
    }

    _isProcessingCaptionShortcut = false;
  }

  // Handle hNN / vNN shorthand typed in the caption box
  void _onCaptionChanged(String value) {
    if (_isProcessingCaptionShortcut) return;

    // Check for magic input patterns that should be processed when space is pressed
    if (value.isNotEmpty) {
      // Get cursor position to find if a space was just typed
      final selection = captionController.selection;
      if (selection.isValid) {
        final cursorPos = selection.baseOffset;

        // Check if there's a space just before the cursor position
        if (cursorPos > 0 && value[cursorPos - 1] == ' ') {
          print(
              'DEBUG: Space detected at cursor position $cursorPos in: "$value"');

          // Look for player tokens that end just before the cursor (just before the space)
          final playerTokenMatches =
              RegExp(r'([hv])(\d{1,3}) ').allMatches(value);
          print(
              'DEBUG: Found ${playerTokenMatches.length} potential player tokens');

          // Find the token that ends right at the cursor position
          RegExpMatch? bestMatch;

          for (final match in playerTokenMatches) {
            print(
                'DEBUG: Token at ${match.start}-${match.end} (${match.group(0)?.trim()}), ends at: ${match.end}, cursor at: $cursorPos');
            if (match.end == cursorPos) {
              // Token ends exactly where cursor is
              bestMatch = match;
              break;
            }
          }

          if (bestMatch != null) {
            print('DEBUG: Processing exact match: ${bestMatch.group(0)}');
            final prefix = bestMatch.group(1)!.toLowerCase();
            final number = bestMatch.group(2)!;
            final isHome = prefix == 'h';
            final roster = isHome ? _homeRoster : _awayRoster;

            // Find the player
            Player? found;
            for (final p in roster) {
              if (p.jerseyNumber == number) {
                found = p;
                break;
              }
            }

            if (found != null) {
              print(
                  'DEBUG: Found player in caption box after space: ${found.displayName}');
              // Process the player token
              _processCaptionPlayerToken(value, bestMatch, found, isHome);
              return;
            }
          }
        }
      }
    }

    // Only proceed with expansion if the last character typed was a space
    if (value.isEmpty || value.codeUnitAt(value.length - 1) != 32) {
      // Check for potential tokens to highlight immediately (only when not expanding)
      _highlightPotentialTokens(value);
      return;
    }

    // Only proceed if rosters are available (except for ag and team tokens)
    if (_homeRoster.isEmpty &&
        _awayRoster.isEmpty &&
        !value.contains(RegExp(r'\b(ag|ht|vt) '))) {
      return;
    }

    // Normalize reversed forms first so subsequent matching works for both orders
    // e.g., `4i` -> `i4`, `27v` -> `v27`, `27vv` -> `vv27`
    final normalizedValue = value.replaceAllMapped(
      RegExp(r'(?:^|\b)(\d{1,3})((?:[hH]{1,2})|(?:[vV]{1,2})|[iI]) '),
      (m) => '${m.group(2)}${m.group(1)} ',
    );

    // Pattern tokens (require space after):
    // - hNN / hhNN / vNN / vvNN → player tokens
    // - iNN → inning token → "during the first inning" (requires at least 1 digit)
    // - h / v → team names (home / away)
    // - ht / vt → team names (home / visiting)
    // - ag → "against the [opposite team]" (based on first selected player)
    final regex = RegExp(
        r'(?:^|\b)((?:[hH]{1,2})|(?:[vV]{1,2})|[hH][tT]|[vV][tT]|[hH]|[vV]|(?<!a)[aA][gG](?!a))(\d{0,3}) ');
    final inningRegex = RegExp(r'(?:^|\b)[iI](\d{1,3}) ');

    // Check if there are any valid tokens to process
    if (!regex.hasMatch(normalizedValue) &&
        !inningRegex.hasMatch(normalizedValue)) return;

    String newText = value;
    bool replacedAny = false;
    int? caretAfterReplacement;
    final selection = captionController.selection;

    // Normalize reversed forms handled earlier via normalizedValue

    // Convert numbers to written ordinals for innings (1 -> first, 4 -> fourth, 21 -> 21st)
    String ordinalWord(int n) {
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
        case 10:
          return 'tenth';
        case 11:
          return 'eleventh';
        case 12:
          return 'twelfth';
        case 13:
          return 'thirteenth';
        case 14:
          return 'fourteenth';
        case 15:
          return 'fifteenth';
        case 16:
          return 'sixteenth';
        case 17:
          return 'seventeenth';
        case 18:
          return 'eighteenth';
        case 19:
          return 'nineteenth';
        case 20:
          return 'twentieth';
        default:
          if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
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
    }

    final buffer = StringBuffer();
    int lastIndex = 0;
    final List<TextRange> newHighlightedRanges = [];

    // Process inning tokens first (they require at least 1 digit)
    for (final match in inningRegex.allMatches(normalizedValue)) {
      if (match.start > lastIndex) {
        buffer.write(normalizedValue.substring(lastIndex, match.start));
      }
      final number = match.group(1)!;

      replacedAny = true;
      final inningNum = int.tryParse(number) ?? 0;
      // Don't process inning 0
      if (inningNum == 0) {
        lastIndex = match.end;
        continue;
      }
      final ord = ordinalWord(inningNum);
      final replacement = 'during the $ord inning ';
      buffer.write(replacement);
      // Highlight the entire inserted phrase
      newHighlightedRanges.add(
        TextRange(
            start: buffer.length - replacement.length, end: buffer.length),
      );
      if (selection.baseOffset >= match.start &&
          selection.baseOffset <= match.end) {
        caretAfterReplacement = buffer.length;
      }
      lastIndex = match.end - 1; // Skip the space that triggered the expansion
    }

    // Process other tokens
    for (final match in regex.allMatches(normalizedValue)) {
      if (match.start > lastIndex) {
        buffer.write(normalizedValue.substring(lastIndex, match.start));
      }
      final prefix = match.group(1)!; // h, hh, v, vv, ht, vt, ag
      final number = match.group(2)!;
      final lower = prefix.toLowerCase();

      // Against token: ag -> "against the [opposite team]"
      if (lower == 'ag') {
        print('DEBUG: ag token detected, processing...');
        replacedAny = true;
        String oppositeTeam = '';

        // Scan the caption text to see which team is already mentioned
        final captionText = captionController.text;
        final homeTeamMentioned =
            selectedHomeTeam != null && captionText.contains(selectedHomeTeam!);
        final awayTeamMentioned =
            selectedAwayTeam != null && captionText.contains(selectedAwayTeam!);

        if (homeTeamMentioned && !awayTeamMentioned) {
          // Home team is mentioned, so opposite is away team
          oppositeTeam = selectedAwayTeam ?? '';
        } else if (awayTeamMentioned && !homeTeamMentioned) {
          // Away team is mentioned, so opposite is home team
          oppositeTeam = selectedHomeTeam ?? '';
        } else if (selectedHomePlayers.isNotEmpty &&
            selectedAwayPlayers.isEmpty) {
          // Fallback: Home player selected first, so opposite is away team
          oppositeTeam = selectedAwayTeam ?? '';
        } else if (selectedAwayPlayers.isNotEmpty &&
            selectedHomePlayers.isEmpty) {
          // Fallback: Away player selected first, so opposite is home team
          oppositeTeam = selectedHomeTeam ?? '';
        } else {
          // Default to away team as opposite
          oppositeTeam = selectedAwayTeam ?? '';
        }

        final replacement = oppositeTeam.isNotEmpty
            ? 'against the $oppositeTeam '
            : 'against the opposing team ';
        buffer.write(replacement);
        newHighlightedRanges.add(
          TextRange(
              start: buffer.length - replacement.length, end: buffer.length),
        );
        if (selection.baseOffset >= match.start &&
            selection.baseOffset <= match.end) {
          caretAfterReplacement = buffer.length;
        }
        lastIndex = match
            .end; // Don't skip the space - let it be part of the replacement
        continue;
      }

      // Team tokens: ht / vt -> full team name
      if (lower == 'ht' || lower == 'vt') {
        replacedAny = true;
        final teamName = lower == 'ht' ? selectedHomeTeam : selectedAwayTeam;
        final replacement = (teamName != null && teamName.isNotEmpty)
            ? '$teamName '
            : (lower == 'ht' ? 'Home Team ' : 'Visiting Team ');
        buffer.write(replacement);
        newHighlightedRanges.add(
          TextRange(
              start: buffer.length - replacement.length, end: buffer.length),
        );
        if (selection.baseOffset >= match.start &&
            selection.baseOffset <= match.end) {
          caretAfterReplacement = buffer.length;
        }
        lastIndex =
            match.end - 1; // Skip the space that triggered the expansion
        continue;
      }

      // Single team tokens: h / v -> full team name
      if (lower == 'h' || lower == 'v') {
        replacedAny = true;
        final teamName = lower == 'h' ? selectedHomeTeam : selectedAwayTeam;
        final replacement = (teamName != null && teamName.isNotEmpty)
            ? '$teamName '
            : (lower == 'h' ? 'Home Team ' : 'Away Team ');
        buffer.write(replacement);
        newHighlightedRanges.add(
          TextRange(
              start: buffer.length - replacement.length, end: buffer.length),
        );
        if (selection.baseOffset >= match.start &&
            selection.baseOffset <= match.end) {
          caretAfterReplacement = buffer.length;
        }
        lastIndex =
            match.end - 1; // Skip the space that triggered the expansion
        continue;
      }

      final isHome = lower.startsWith('h');
      final isDouble = lower.length == 2; // hh or vv

      final roster = isHome ? _homeRoster : _awayRoster;
      Player? found;
      for (final p in roster) {
        if (p.jerseyNumber == number) {
          found = p;
          break;
        }
      }

      if (found != null) {
        replacedAny = true;
        // Visually select the player in the picker below when a valid token is entered
        _selectPlayerChipByNumber(
          isHomeTeam: isHome,
          jerseyNumber: number,
          isProgressive:
              true, // don't override existing red star on subsequent tokens
        );
        // Update personality field with clean full name (no number), de-duplicated
        final current = personalityController.text.trim();
        final parts = current.isEmpty
            ? <String>[]
            : current
                .split(';')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
        if (!parts.contains(found.fullName)) {
          parts.add(found.fullName);
          personalityController.text = parts.join(';');
        }

        String replacement = found.displayName;
        if (!isDouble) {
          final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;
          if (teamName != null && teamName.isNotEmpty) {
            replacement = '$replacement of the $teamName';
          }
        }
        replacement = '$replacement ';
        buffer.write(replacement);
        newHighlightedRanges.add(
          TextRange(
              start: buffer.length - replacement.length, end: buffer.length),
        );
        // Record mapping so deletion can remove from personality
        _tokenToPlayerName[replacement.trim()] = found.fullName;
        // If caret is within or at end of this token, place it at end of replacement
        if (selection.baseOffset >= match.start &&
            selection.baseOffset <= match.end) {
          caretAfterReplacement = buffer.length;
        }
      } else {
        // No match found; keep token
        buffer.write(normalizedValue.substring(match.start, match.end));
      }
      lastIndex = match.end; // Consume the space that triggered the expansion
    }

    // Append remaining tail
    if (lastIndex < normalizedValue.length) {
      buffer.write(normalizedValue.substring(lastIndex));
    }
    newText = buffer.toString();
    // Safety: remove any stray newlines so subsequent typing doesn't auto-trigger expansions
    if (newText.contains('\n')) {
      newText = newText.replaceAll('\n', '');
    }

    if (replacedAny && newText != value) {
      _isProcessingCaptionShortcut = true;
      captionController.text = newText;
      if (caretAfterReplacement != null) {
        captionController.selection =
            TextSelection.collapsed(offset: caretAfterReplacement);
      } else if (selection.baseOffset >= 0) {
        final clamped = selection.baseOffset.clamp(0, newText.length);
        captionController.selection = TextSelection.collapsed(offset: clamped);
      }
      // Update highlight ranges for newly inserted phrases
      _highlightedRanges = newHighlightedRanges;
      captionController.highlightedRanges = newHighlightedRanges;
      captionController.invalidRanges = [];
      _isProcessingCaptionShortcut = false;
    }
  }

  // Remove a player's full name from the personality field text (semicolon-separated, de-duplicated)
  void _removePlayerFromPersonality(String playerName) {
    final current = personalityController.text.trim();
    final parts = current.isEmpty
        ? <String>[]
        : current
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    parts.removeWhere((p) => p == playerName);
    personalityController.text = parts.join(';');
  }

  // Highlight potential tokens as they are typed, including reversed numeric forms
  void _highlightPotentialTokens(String value) {
    if (value.isEmpty) {
      captionController.highlightedRanges = [];
      captionController.invalidRanges = [];
      setState(() {});
      return;
    }

    final List<TextRange> validRanges = [];
    final List<TextRange> invalidRanges = [];

    // Forward tokens: h, hh, v, vv, i, ht, vt, ag + optional number (for player/inning)
    final forward = RegExp(
        r'(?:^|\b)((?:[hH]{1,2})|(?:[vV]{1,2})|[iI]|[hH][tT]|[vV][tT]|(?<!a)[aA][gG](?!a))(\d{0,3})');
    for (final m in forward.allMatches(value)) {
      final prefix = m.group(1)!.toLowerCase();
      final number = m.group(2) ?? '';

      bool isPlayerToken =
          (prefix == 'h' || prefix == 'hh' || prefix == 'v' || prefix == 'vv');
      bool isValid = false;
      if (prefix == 'i') {
        isValid = number.isNotEmpty; // inning requires a number
      } else if (prefix == 'ht' || prefix == 'vt' || prefix == 'ag') {
        isValid = true; // no number required
      } else if (isPlayerToken && number.isNotEmpty) {
        final isHome = prefix.startsWith('h');
        final roster = isHome ? _homeRoster : _awayRoster;
        isValid = roster.any((p) => p.jerseyNumber == number);
      }

      final range = TextRange(start: m.start, end: m.end);
      if (isValid) {
        validRanges.add(range);
      } else if (isPlayerToken && number.isNotEmpty) {
        invalidRanges.add(range);
      }
    }

    // Reversed numeric tokens at the end: NN(h|hh|v|vv|i)
    final reverse = RegExp(r'(?:^|\b)(\d{1,3})(([hH]{1,2})|([vV]{1,2})|[iI])');
    for (final m in reverse.allMatches(value)) {
      final number = m.group(1) ?? '';
      final suffix = (m.group(2) ?? '').toLowerCase();

      bool isPlayerToken =
          (suffix == 'h' || suffix == 'hh' || suffix == 'v' || suffix == 'vv');
      bool isValid = false;
      if (suffix == 'i') {
        isValid = number.isNotEmpty;
      } else if (isPlayerToken && number.isNotEmpty) {
        final isHome = suffix.startsWith('h');
        final roster = isHome ? _homeRoster : _awayRoster;
        isValid = roster.any((p) => p.jerseyNumber == number);
      }

      final range = TextRange(start: m.start, end: m.end);
      if (isValid) {
        validRanges.add(range);
      } else if (isPlayerToken) {
        invalidRanges.add(range);
      }
    }

    captionController.highlightedRanges = validRanges;
    captionController.invalidRanges = invalidRanges;
    _highlightedRanges = validRanges;

    // Progressive auto-selection: when a valid trailing player token is being typed,
    // select that player in the visual pickers below in real time.
    try {
      final trailingForward =
          RegExp(r'(?:^|\b)((?:h{1,2})|(?:v{1,2}))(\d{1,3})\s*$');
      final trailingReverse =
          RegExp(r'(?:^|\b)(\d{1,3})((?:h{1,2})|(?:v{1,2}))\s*$');
      String? teamToken;
      String? jersey;
      final m1 = trailingForward.firstMatch(value.toLowerCase());
      if (m1 != null) {
        teamToken = m1.group(1);
        jersey = m1.group(2);
      } else {
        final m2 = trailingReverse.firstMatch(value.toLowerCase());
        if (m2 != null) {
          jersey = m2.group(1);
          teamToken = m2.group(2);
        }
      }

      if (teamToken != null && jersey != null && jersey.isNotEmpty) {
        final bool isHome = teamToken.startsWith('h');
        final roster = isHome ? _homeRoster : _awayRoster;
        final exists = roster.any((p) => p.jerseyNumber == jersey);
        if (exists) {
          // If a different jersey was previously auto-selected for this team,
          // DO NOT unselect it. We want to keep previously selected players
          // when adding additional players via shortcodes.
          final lastAuto =
              isHome ? _autoSelectedHomeJersey : _autoSelectedAwayJersey;
          // Intentionally keep lastAuto selected to allow multiple selections
          // Select the current jersey
          _selectPlayerChipByNumber(
            isHomeTeam: isHome,
            jerseyNumber: jersey,
            isProgressive: true,
          );
        }
      }
    } catch (_) {
      // Best-effort progressive selection; ignore errors
    }

    setState(() {});
  }

  void _handleHrOptionInput(String value) {
    final token = value.trim().toLowerCase();
    if (token.isEmpty) return;
    final normalized = token.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Accept partials to be forgiving
    String? hrType;
    if ('solo'.startsWith(normalized)) {
      hrType = 'Solo';
    } else if ('tworun'.startsWith(normalized) ||
        normalized == '2' ||
        normalized == '2run') {
      hrType = 'Two-Run';
    } else if ('threerun'.startsWith(normalized) ||
        normalized == '3' ||
        normalized == '3run') {
      hrType = 'Three-Run';
    } else if ('grandslam'.startsWith(normalized) ||
        normalized == 'grand' ||
        normalized == 'gs') {
      hrType = 'Grand Slam';
    }

    if (hrType != null) {
      setState(() {
        _selectedVerb = 'Home Run';
        _selectedActionVerb = 'Home Run';
        _selectedHomeRunType = hrType;
        switch (hrType) {
          case 'Solo':
            _rbiCount = 1;
            break;
          case 'Two-Run':
            _rbiCount = 2;
            break;
          case 'Three-Run':
            _rbiCount = 3;
            break;
          case 'Grand Slam':
            _rbiCount = 4;
            break;
        }
      });
      _updateCaption();
    }
  }

  // Minimal chip selection helpers (safe no-ops if roster/players missing)
  void _selectPlayerChipByNumber({
    required bool isHomeTeam,
    required String jerseyNumber,
    bool isProgressive = false,
    bool affectFirstStar = true,
  }) {
    final roster = isHomeTeam ? _homeRoster : _awayRoster;
    final name = roster
        .firstWhere(
          (p) => p.jerseyNumber == jerseyNumber,
          orElse: () => Player(
              fullName: '', firstName: '', displayName: '', jerseyNumber: ''),
        )
        .displayName;
    if (name.isEmpty) return;
    final set = isHomeTeam ? selectedHomePlayers : selectedAwayPlayers;
    set.add(name);

    // Optionally affect first star tracking
    if (affectFirstStar) {
      if (_firstTeamSelected == null) {
        _firstTeamSelected = isHomeTeam;
      }
      _firstPlayerSelected ??= _removeJerseyNumberFromName(name);
    }

    // Red star is determined by caption text order

    if (isHomeTeam) {
      _autoSelectedHomeJersey = jerseyNumber;
    } else {
      _autoSelectedAwayJersey = jerseyNumber;
    }
    setState(() {});
  }

  void _unselectAutoSelectedByToken({
    required bool isHomeTeam,
    required String jerseyNumber,
  }) {
    final roster = isHomeTeam ? _homeRoster : _awayRoster;
    final name = roster
        .firstWhere(
          (p) => p.jerseyNumber == jerseyNumber,
          orElse: () => Player(
              fullName: '', firstName: '', displayName: '', jerseyNumber: ''),
        )
        .displayName;
    if (name.isEmpty) return;
    final set = isHomeTeam ? selectedHomePlayers : selectedAwayPlayers;
    set.remove(name);
    // Only clear the red star if this was truly the first selected player AND
    // we're removing the last remaining player, not just switching auto-selections
    // Red star tracking removed - determined by caption text order only
    if (isHomeTeam && _autoSelectedHomeJersey == jerseyNumber) {
      _autoSelectedHomeJersey = null;
    }
    if (!isHomeTeam && _autoSelectedAwayJersey == jerseyNumber) {
      _autoSelectedAwayJersey = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Caption Builder Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: Row(
                children: [
                  // Left side: Caption, Personality, and Player/Verb area (70%)
                  Expanded(
                    flex: 8,
                    child: Column(
                      children: [
                        // Caption and Personality boxes side by side
                        Row(
                          children: [
                            // Caption Preview (Left side) - Moderate width
                            Expanded(
                              flex: 5,
                              child: TextField(
                                controller: captionController,
                                maxLines: 3,
                                onChanged: _onCaptionChanged,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Caption',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText:
                                      'Generated caption will appear here...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                        color: Colors.blue.shade400, width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.all(8),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  labelStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                inputFormatters: [
                                  HighlightedTokenDeletionFormatter(
                                    getRanges: () => _highlightedRanges,
                                    onTokenDeleted: (deletedRange, tokenText) {
                                      // Update personality if this was a player expansion
                                      final playerName =
                                          _tokenToPlayerName[tokenText.trim()];
                                      if (playerName != null) {
                                        _removePlayerFromPersonality(
                                            playerName);
                                        // Remove mapping for this exact token text
                                        _tokenToPlayerName
                                            .remove(tokenText.trim());
                                      }

                                      // Rebuild highlight ranges after deletion
                                      final int removedLen =
                                          deletedRange.end - deletedRange.start;
                                      final List<TextRange> updated = [];
                                      for (final r in _highlightedRanges) {
                                        // Skip the deleted range itself
                                        if (r.start >= deletedRange.start &&
                                            r.end <= deletedRange.end) {
                                          continue;
                                        }
                                        if (r.start >= deletedRange.end) {
                                          updated.add(TextRange(
                                              start: r.start - removedLen,
                                              end: r.end - removedLen));
                                        } else {
                                          updated.add(r);
                                        }
                                      }
                                      _highlightedRanges = updated;
                                      (captionController
                                              as HighlightingTextEditingController)
                                          .highlightedRanges = updated;
                                      (captionController
                                              as HighlightingTextEditingController)
                                          .invalidRanges = [];
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            // Personality Box (Right side) - Reduced to make room for caption
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: personalityController,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Personality',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText: 'Personality tags...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                        color: Colors.blue.shade400, width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.all(8),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  labelStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Action buttons are now beside the magic bar
                        // (Old action button container removed)

                        const SizedBox(height: 1),

                        // New container spanning bottom left quadrant
                        Container(
                          width: double.infinity,
                          height: 40, // Single line height
                          padding: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.grey.shade400,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // First column - Magic bar
                              Expanded(
                                flex: 6,
                                child: Container(
                                  padding:
                                      const EdgeInsets.only(left: 4, right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(6),
                                      bottomLeft: Radius.circular(6),
                                    ),
                                  ),
                                  child: TextField(
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(
                                            color: Colors.blue.shade400),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                      isDense: true,
                                      hintText: _waitingForHomeVisitorChoice
                                          ? 'Press H for Home or V for Away'
                                          : '🔥 Firebar',
                                      suffixText: _waitingForHomeVisitorChoice
                                          ? null
                                          : _shouldShowRbiInlineHint()
                                              ? ' Add # for ' +
                                                  _rbiHintNoun() +
                                                  ' (e.g., ' +
                                                  _rbiShortcutExample() +
                                                  ')'
                                              : null,
                                      suffixStyle: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    controller: _magicBarController,
                                    focusNode: _magicBarFocusNode,
                                    onChanged: (value) {
                                      // Handle H/V input when waiting for home/visitor choice
                                      if (_waitingForHomeVisitorChoice) {
                                        print(
                                            'DEBUG: In choice mode, value: "$value"');
                                        // Check if user typed 'h' or 'v' anywhere in the text
                                        final lowerValue = value.toLowerCase();
                                        print(
                                            'DEBUG: Checking for h or v in: "$lowerValue"');

                                        // Look for 'h' or 'v' at the end of the input (user's choice)
                                        final hMatch = RegExp(r'h$')
                                            .firstMatch(lowerValue);
                                        final vMatch = RegExp(r'v$')
                                            .firstMatch(lowerValue);

                                        if (hMatch != null) {
                                          print(
                                              'DEBUG: Found H, calling _processHomeVisitorChoice');
                                          _processHomeVisitorChoice('h');
                                          return;
                                        } else if (vMatch != null) {
                                          print(
                                              'DEBUG: Found V, calling _processHomeVisitorChoice');
                                          _processHomeVisitorChoice('v');
                                          return;
                                        }
                                        print(
                                            'DEBUG: No H or V found, restoring prompt if needed');
                                        // Restore the prompt text if user tries to edit it
                                        if (!value.contains(
                                            'Press H for Home or V for Away')) {
                                          final numberPart =
                                              _magicInputMatchingPlayers
                                                  .first.jerseyNumber;
                                          print('DEBUG: Restoring prompt text');

                                          // Create player choice text with last names and numbers
                                          final homePlayer =
                                              _magicInputMatchingPlayers
                                                  .firstWhere(
                                            (p) => _homeRoster.contains(p),
                                            orElse: () =>
                                                _magicInputMatchingPlayers
                                                    .first,
                                          );
                                          final awayPlayer =
                                              _magicInputMatchingPlayers
                                                  .firstWhere(
                                            (p) => !_homeRoster.contains(p),
                                            orElse: () =>
                                                _magicInputMatchingPlayers
                                                    .first,
                                          );

                                          final homeLastName = homePlayer
                                              .fullName
                                              .split(' ')
                                              .last;
                                          final awayLastName = awayPlayer
                                              .fullName
                                              .split(' ')
                                              .last;

                                          _magicBarController.text =
                                              '$numberPart - Press H for $homeLastName #${homePlayer.jerseyNumber} or V for $awayLastName #${awayPlayer.jerseyNumber}';
                                          _magicBarController.selection =
                                              TextSelection.fromPosition(
                                            TextPosition(
                                                offset: _magicBarController
                                                    .text.length),
                                          );
                                        }
                                        return;
                                      }

                                      // Track magic bar input for verb highlighting
                                      _magicBarVerbInput =
                                          value.trim().toLowerCase();
                                      // Track if we're typing a first magic token (no space yet)
                                      _typingFirstMagicToken =
                                          !value.contains(' ');
                                      // Magic bar functionality
                                      if (value.isEmpty) {
                                        // Don't reset caption when magic bar is empty
                                        // This preserves player selections during multi-player input
                                        setState(() {}); // refresh highlighting
                                        return;
                                      }
                                      // If user is typing a single player token (no space yet),
                                      // highlight progressively and postpone parsing until token completes.
                                      final raw = value;
                                      final token = raw.trim().toLowerCase();
                                      final hasSpace = raw.contains(' ');
                                      final String lastToken =
                                          raw.trimRight().isEmpty
                                              ? ''
                                              : raw
                                                  .trimRight()
                                                  .split(' ')
                                                  .last
                                                  .toLowerCase();

                                      // Ensure caption updates on deletion of shortcuts (run early before any returns)
                                      {
                                        final List<String> tokens = raw
                                            .trim()
                                            .toLowerCase()
                                            .split(RegExp(r'\s+'))
                                            .where((t) => t.isNotEmpty)
                                            .toList();
                                        final bool hasHrToken = tokens.any(
                                            (t) =>
                                                RegExp(r'^hr([1-4])$',
                                                        caseSensitive: false)
                                                    .hasMatch(t) ||
                                                t == 'gs');
                                        final bool hasRbiToken = RegExp(
                                                r'(?:^|\s)(\d{1,2})\s*[rR][bB]?[iI]?(?:\s|$)')
                                            .hasMatch(raw.trim());
                                        final bool hasExplicitInningToken =
                                            RegExp(r'(?:^|\b)[iI]\d+')
                                                .hasMatch(raw);
                                        final List<String> bareNums = tokens
                                            .where((t) => RegExp(r'^\d{1,2}$')
                                                .hasMatch(t))
                                            .toList();
                                        final bool hasBareInningToken =
                                            raw.contains(' ') &&
                                                bareNums.isNotEmpty;

                                        bool anyChanged = false;
                                        setState(() {
                                          // If inning token removed, clear inning selection
                                          if (!hasExplicitInningToken &&
                                              !hasBareInningToken &&
                                              _selectedRbiInning != null) {
                                            _selectedRbiInning = null;
                                            anyChanged = true;
                                          }
                                          // If HR shortcut removed, clear Home Run selections
                                          if (!hasHrToken &&
                                              _selectedVerb == 'Home Run') {
                                            _selectedVerb = null;
                                            _selectedActionVerb = null;
                                            _selectedHomeRunType = null;
                                            _rbiCount = null;
                                            anyChanged = true;
                                          }
                                          // If RBI shortcut removed (and not HR), clear RBI count
                                          if (!hasRbiToken &&
                                              _selectedVerb != 'Home Run' &&
                                              _rbiCount != null) {
                                            _rbiCount = null;
                                            anyChanged = true;
                                          }
                                        });
                                        if (anyChanged) {
                                          _updateCaption();
                                        }
                                      }

                                      // Quick-select Home Run with type via magic bar from the LAST token
                                      // Support: hr1/hr2/hr3/hr4 and gs (works even when there are prior tokens)
                                      // Only work when NOT in a submenu (to avoid conflicts)
                                      if (lastToken.isNotEmpty &&
                                          _selectedVerb == null) {
                                        final hrNum = RegExp(r'^hr([1-4])$',
                                                caseSensitive: false)
                                            .firstMatch(lastToken);
                                        if (hrNum != null) {
                                          final n =
                                              int.tryParse(hrNum.group(1)!);
                                          String? hrType;
                                          switch (n) {
                                            case 1:
                                              hrType = 'Solo';
                                              break;
                                            case 2:
                                              hrType = 'Two-Run';
                                              break;
                                            case 3:
                                              hrType = 'Three-Run';
                                              break;
                                            case 4:
                                              hrType = 'Grand Slam';
                                              break;
                                          }
                                          if (hrType != null) {
                                            setState(() {
                                              _selectedVerb = 'Home Run';
                                              _selectedActionVerb = 'Home Run';
                                              _selectedHomeRunType = hrType;
                                              _rbiCount = n; // keep in sync
                                            });
                                            _updateCaption();
                                            return;
                                          }
                                        }
                                        if (lastToken == 'gs') {
                                          setState(() {
                                            _selectedVerb = 'Home Run';
                                            _selectedActionVerb = 'Home Run';
                                            _selectedHomeRunType = 'Grand Slam';
                                            _rbiCount = 4;
                                          });
                                          _updateCaption();
                                          return;
                                        }
                                      }

                                      // Bare inning number without 'i' suffix: set inning from last token if numeric (e.g., "5")
                                      // Only trigger when there is at least one space (to avoid conflicting with first player token)
                                      // Only work when NOT in a submenu (to avoid conflicts)
                                      if (hasSpace &&
                                          RegExp(r'^\d{1,2}$')
                                              .hasMatch(lastToken) &&
                                          _selectedVerb == null) {
                                        final int inningNum =
                                            int.parse(lastToken);
                                        if (inningNum > 0 && inningNum <= 20) {
                                          setState(() {
                                            _selectedRbiInning = inningNum;
                                          });
                                          _updateCaption();
                                          return;
                                        }
                                      }

                                      final singlePlayerRegex =
                                          RegExp(r'^(h{1,2}|v{1,2})?\d+$');
                                      // Exclude hr patterns from single player regex
                                      final hrPattern = RegExp(r'^hr\d+$');
                                      if (_typingFirstMagicToken &&
                                          !hasSpace &&
                                          singlePlayerRegex.hasMatch(token) &&
                                          !hrPattern.hasMatch(token)) {
                                        String numberPart = token.replaceAll(
                                            RegExp(r'^(h{1,2}|v{1,2})'), '');
                                        bool isHomeHint = token.startsWith('h');

                                        // If no explicit h/v and both teams have this jersey number,
                                        // prompt for Home/Away choice inline.
                                        if (!isHomeHint &&
                                            !token.startsWith('v')) {
                                          final homeMatches = _homeRoster
                                              .where((p) =>
                                                  p.jerseyNumber == numberPart)
                                              .toList();
                                          final awayMatches = _awayRoster
                                              .where((p) =>
                                                  p.jerseyNumber == numberPart)
                                              .toList();
                                          if (homeMatches.isNotEmpty &&
                                              awayMatches.isNotEmpty) {
                                            setState(() {
                                              _filteredPlayers.clear();
                                              _noPlayersFound = false;
                                              _isPlayerSearchMode = false;
                                              _magicInputMatchingPlayers = [
                                                ...homeMatches,
                                                ...awayMatches
                                              ];
                                              _magicInputActionText = '';
                                              _waitingForHomeVisitorChoice =
                                                  true;
                                            });
                                            // Set the text to show the choice prompt with player names
                                            final homePlayer =
                                                _magicInputMatchingPlayers
                                                    .firstWhere(
                                              (p) => _homeRoster.contains(p),
                                              orElse: () =>
                                                  _magicInputMatchingPlayers
                                                      .first,
                                            );
                                            final awayPlayer =
                                                _magicInputMatchingPlayers
                                                    .firstWhere(
                                              (p) => !_homeRoster.contains(p),
                                              orElse: () =>
                                                  _magicInputMatchingPlayers
                                                      .first,
                                            );

                                            final homeLastName = homePlayer
                                                .fullName
                                                .split(' ')
                                                .last;
                                            final awayLastName = awayPlayer
                                                .fullName
                                                .split(' ')
                                                .last;

                                            _magicBarController.text =
                                                '$numberPart - Press H for $homeLastName #${homePlayer.jerseyNumber} or V for $awayLastName #${awayPlayer.jerseyNumber}';
                                            _magicBarController.selection =
                                                TextSelection.fromPosition(
                                              TextPosition(
                                                  offset: _magicBarController
                                                      .text.length),
                                            );
                                            return;
                                          }
                                        }

                                        // Choose team when no explicit h/v was provided:
                                        // 1) If only one team has players selected, use that team
                                        // 2) Else if a team was selected first, use that
                                        // 3) Else fall back to UI side (_homeOnLeft)
                                        final bool inferredIsHome = isHomeHint
                                            ? true
                                            : (selectedHomePlayers.isNotEmpty &&
                                                    selectedAwayPlayers.isEmpty)
                                                ? true
                                                : (selectedAwayPlayers
                                                            .isNotEmpty &&
                                                        selectedHomePlayers
                                                            .isEmpty)
                                                    ? false
                                                    : (_firstTeamSelected ??
                                                        _homeOnLeft);

                                        // If a different jersey was previously auto-selected for this team, unselect it
                                        final prevAuto = inferredIsHome
                                            ? _autoSelectedHomeJersey
                                            : _autoSelectedAwayJersey;
                                        if (prevAuto != null &&
                                            prevAuto != numberPart) {
                                          _unselectAutoSelectedByToken(
                                            isHomeTeam: inferredIsHome,
                                            jerseyNumber: prevAuto,
                                          );
                                        }
                                        _selectPlayerChipByNumber(
                                          isHomeTeam: inferredIsHome,
                                          jerseyNumber: numberPart,
                                          isProgressive: true,
                                          affectFirstStar: false,
                                        );
                                        setState(() {});
                                        return;
                                      }

                                      // Home Run sub-menu: special letters shortcut "gs" -> Grand Slam
                                      final RegExpMatch? hrLettersMatch0 =
                                          RegExp(r'([a-zA-Z]+)$')
                                              .firstMatch(value);
                                      final String hrLetters0 = hrLettersMatch0
                                              ?.group(1)
                                              ?.toLowerCase() ??
                                          '';
                                      if (_selectedVerb == 'Home Run' &&
                                          hrLetters0 == 'gs') {
                                        setState(() {
                                          _selectedHomeRunType = 'Grand Slam';
                                        });
                                        _updateCaption();
                                        return;
                                      }

                                      // Try to match typed letters to a verb shortcut and auto-select the verb
                                      // Only work when NOT in a submenu (to avoid conflicts)
                                      if (_selectedVerb == null) {
                                        final RegExpMatch? lettersMatch =
                                            RegExp(r'([a-zA-Z]+)$')
                                                .firstMatch(value);
                                        final String typedLetters = lettersMatch
                                                ?.group(1)
                                                ?.toLowerCase() ??
                                            '';
                                        if (typedLetters.length >= 2) {
                                          final matchedVerb =
                                              _matchVerbToken(typedLetters);
                                          if (matchedVerb != null) {
                                            setState(() {
                                              _selectedVerb = matchedVerb;
                                              _selectedActionVerb = matchedVerb;
                                              _clearVerbSubSelections();
                                            });
                                            _updateCaption();
                                            return;
                                          }
                                        }
                                      }

                                      // Parse RBI shortcuts (e.g., "3r", "3rb", "3rbi") in sub-menus
                                      final RegExpMatch? statMatch = RegExp(
                                              r'(\d{1,2})\s*([rR][bB]?[iI]?)$')
                                          .firstMatch(value.trim());
                                      if (statMatch != null) {
                                        final int number =
                                            int.tryParse(statMatch.group(1)!) ??
                                                0;
                                        final String suffix =
                                            (statMatch.group(2) ?? '')
                                                .toLowerCase();
                                        if (suffix == 'r' ||
                                            suffix == 'rb' ||
                                            suffix == 'rbi') {
                                          if (_selectedVerb == 'Home Run') {
                                            String? hrType;
                                            if (number <= 1) {
                                              hrType = 'Solo';
                                            } else if (number == 2) {
                                              hrType = 'Two-Run';
                                            } else if (number == 3) {
                                              hrType = 'Three-Run';
                                            } else if (number >= 4) {
                                              hrType = 'Grand Slam';
                                            }
                                            if (hrType != null) {
                                              setState(() {
                                                _selectedHomeRunType = hrType;
                                              });
                                              _updateCaption();
                                              return;
                                            }
                                          } else {
                                            setState(() {
                                              _rbiCount = number;
                                            });
                                            _updateCaption();
                                            return;
                                          }
                                        }
                                      }

                                      // Parse inning numbers in sub-menus (e.g., "5" for 5th inning)
                                      if (_selectedVerb != null) {
                                        final RegExpMatch? inningMatch =
                                            RegExp(r'^(\d{1,2})$')
                                                .firstMatch(lastToken);
                                        if (inningMatch != null) {
                                          final int inningNum = int.tryParse(
                                                  inningMatch.group(1)!) ??
                                              0;
                                          if (inningNum > 0 &&
                                              inningNum <= 20) {
                                            setState(() {
                                              _selectedRbiInning = inningNum;
                                            });
                                            _updateCaption();
                                            return;
                                          }
                                        }
                                      }

                                      // Cleanup: if user deletes shortcuts, clear derived selections and update caption
                                      final List<String> tokens = raw
                                          .trim()
                                          .toLowerCase()
                                          .split(RegExp(r'\s+'))
                                          .where((t) => t.isNotEmpty)
                                          .toList();
                                      final bool hasHrToken = tokens.any((t) =>
                                          RegExp(r'^hr([1-4])$',
                                                  caseSensitive: false)
                                              .hasMatch(t) ||
                                          t == 'gs');
                                      final bool hasRbiToken = RegExp(
                                              r'(?:^|\s)(\d{1,2})\s*[rR][bB]?[iI]?(?:\s|$)')
                                          .hasMatch(raw.trim());
                                      final bool hasExplicitInningToken =
                                          RegExp(r'(?:^|\b)[iI]\d+')
                                              .hasMatch(raw);
                                      final List<String> bareNums = tokens
                                          .where((t) =>
                                              RegExp(r'^\d{1,2}$').hasMatch(t))
                                          .toList();
                                      final bool hasBareInningToken =
                                          raw.contains(' ') &&
                                              bareNums.isNotEmpty;

                                      bool anyChanged = false;
                                      setState(() {
                                        // If HR shortcut removed, clear Home Run selections
                                        if (!hasHrToken &&
                                            _selectedVerb == 'Home Run') {
                                          _selectedVerb = null;
                                          _selectedActionVerb = null;
                                          _selectedHomeRunType = null;
                                          _rbiCount = null;
                                          anyChanged = true;
                                        }
                                        // If RBI shortcut removed (and not HR), clear RBI count
                                        if (!hasRbiToken &&
                                            _selectedVerb != 'Home Run' &&
                                            _rbiCount != null) {
                                          _rbiCount = null;
                                          anyChanged = true;
                                        }
                                        // If inning token removed, clear inning selection
                                        if (!hasExplicitInningToken &&
                                            !hasBareInningToken &&
                                            _selectedRbiInning != null) {
                                          _selectedRbiInning = null;
                                          anyChanged = true;
                                        }
                                      });
                                      if (anyChanged) {
                                        _updateCaption();
                                      }

                                      print(
                                          'DEBUG: About to check _isMagicInput for: "$value"');
                                      if (_isMagicInput(value)) {
                                        print(
                                            'DEBUG: _isMagicInput returned true, calling _parseMagicInput');
                                        _parseMagicInput(value);
                                        return;
                                      }

                                      // Handle multiple player numbers (e.g., "27 23")
                                      _handleMultiplePlayerInput(value);
                                      setState(
                                          () {}); // refresh highlighting while typing
                                    },
                                  ),
                                ),
                              ),

                              // Middle column - Navigation buttons and FTP/Settings
                              Expanded(
                                flex: 11,
                                child: Container(
                                  decoration: BoxDecoration(),
                                  child: _buildNavigationButtons(),
                                ),
                              ),
                              // Third column - FTP and Settings buttons (flex: 3)
                              Expanded(
                                flex: 3,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(6),
                                      bottomRight: Radius.circular(6),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // FTP button
                                      CustomButton(
                                        onTap:
                                            _disableFtp ? null : _onFtpPressed,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _disableFtp
                                                ? Colors.grey.shade300
                                                : const Color(0xFF0052CC),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: _disableFtp
                                                    ? Colors.grey.shade300
                                                    : const Color(0xFF0052CC)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.rocket_launch,
                                                  size: 14,
                                                  color: _disableFtp
                                                      ? Colors.grey.shade600
                                                      : Colors.white),
                                              const SizedBox(width: 2),
                                              Text(
                                                  _disableFtp
                                                      ? 'FTP OFF'
                                                      : (_currentFtpProfile !=
                                                              null
                                                          ? 'FTP: $_currentFtpProfile'
                                                          : 'FTP'),
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: _disableFtp
                                                          ? Colors.grey.shade600
                                                          : Colors.white,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Settings button
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 4),
                                        child: CustomButton(
                                          onTap: _showFtpSettings,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4A90E2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF4A90E2)),
                                            ),
                                            child: const Icon(Icons.settings,
                                                size: 14, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 1),

                        // Player and Verb Selection Area
                        Expanded(
                          child: _buildCaptionBuildingSection(),
                        ),
                      ],
                    ),
                  ),

                  // Right side removed - personality box is now beside caption box
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionBuildingSection() {
    return Container(
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        children: [
          // Left Team (Home or Away depending on _homeOnLeft)
          Expanded(
            flex: 3,
            child: _buildCompactTeamColumn(_homeOnLeft ? true : false),
          ),

          const SizedBox(width: 4),

          // Verbs (Center) - 70% of space
          Expanded(
            flex: 7,
            child: _buildCompactVerbColumn(),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamColumn(String title, String? teamName, bool isHome) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Team name display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
                color: isHome ? Colors.grey.shade700 : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: isHome ? Colors.grey.shade700 : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isHome ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                teamName ?? 'No Team Selected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isHome ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Player selection area
        Container(
          width: double.infinity,
          height: 80,
          padding: const EdgeInsets.only(left: 8, right: 8, top: 0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: _isLoadingRosters
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Loading roster...',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Add players button
                    GestureDetector(
                      onTap: () => _showPlayerSelectionDialog(isHome),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 14,
                              color: isHome
                                  ? Colors.blue.shade600
                                  : Colors.orange.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add Players',
                              style: TextStyle(
                                fontSize: 10,
                                color: isHome
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Selected player chips
                    if ((isHome ? selectedHomePlayers : selectedAwayPlayers)
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _sortPlayersByNumber(isHome
                                ? selectedHomePlayers
                                : selectedAwayPlayers)
                            .map((playerName) =>
                                _buildPlayerChip(playerName, isHome))
                            .toList(),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildVerbColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Action',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main verb selection
              _buildMainVerbSelector(),

              // Hit type options (when "hit" is selected)
              if (_selectedVerb == 'Single' ||
                  _selectedVerb == 'Double' ||
                  _selectedVerb == 'Triple' ||
                  _selectedVerb == 'Home Run' ||
                  _selectedVerb == 'Grand Slam') ...[
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: Colors.black87),
              SizedBox(width: 8),
              Text(
                'Generated Caption:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              captionController.text.isEmpty
                  ? 'No caption generated yet...'
                  : captionController.text,
              style: TextStyle(
                fontSize: 12,
                color: captionController.text.isEmpty
                    ? Colors.grey.shade600
                    : Colors.black87,
                fontStyle: captionController.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
          if (captionController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactTeamColumn(bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final selectedPlayers = isHome ? selectedHomePlayers : selectedAwayPlayers;
    final searchController =
        isHome ? _homeSearchController : _awaySearchController;
    final searchText = isHome ? _homeSearchText : _awaySearchText;

    // Filtered roster
    final filteredRosterUnsorted = searchText.isEmpty
        ? roster
        : roster
            .where((player) => player.displayName
                .toLowerCase()
                .contains(searchText.toLowerCase()))
            .toList();

    // Sort the filtered roster by current sort option
    final sortOption = isHome ? _homeSortOption : _awaySortOption;
    final ascending = isHome ? _homeSortAscending : _awaySortAscending;
    final filteredRoster =
        _sortPlayerObjects(filteredRosterUnsorted, sortOption, ascending);

    // Debug output
    // print(
    //     '${isHome ? "HOME" : "AWAY"} Search: "$searchText", Roster: ${roster.length}, Filtered: ${filteredRoster.length}');

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Team header with symbol and search bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                // Show team dropdown when no team selected, or team name + controls when team selected
                if (_homeOnLeft
                    ? selectedHomeTeam == null
                    : selectedAwayTeam == null) ...[
                  // Team selection area when no team selected
                  Expanded(
                    child: _buildTeamDropdown(
                      isHome: _homeOnLeft,
                      selectedTeam:
                          _homeOnLeft ? selectedHomeTeam : selectedAwayTeam,
                      onTeamChanged: (String? newValue) async {
                        if (newValue == null) return;
                        setState(() {
                          if (_homeOnLeft) {
                            selectedHomeTeam = newValue;
                          } else {
                            selectedAwayTeam = newValue;
                          }
                        });

                        // Load rosters and show debug popup
                        await _loadTeamRosters();
                        _showTeamSelectionDebug(newValue, _homeOnLeft);
                      },
                    ),
                  ),
                ] else ...[
                  // Team name and controls when team is selected
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team name row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () =>
                                    _showTeamEditorDialog(isHome: _homeOnLeft),
                                child: SizedBox(
                                  height: 0,
                                  width: 0,
                                  child: Center(
                                    child: SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 0),
                            // Team tabs
                            Row(
                              children: [
                                // Home team tab
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _homeOnLeft = true;
                                    });
                                    _updateCaption();
                                  },
                                  child: Container(
                                    height: 22,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: _homeOnLeft
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade100,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(4),
                                        bottomLeft: Radius.circular(4),
                                      ),
                                      border: Border.all(
                                        color: _homeOnLeft
                                            ? Colors.grey.shade500
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.home,
                                            size: 10,
                                            color: _homeOnLeft
                                                ? Colors.black87
                                                : Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _getTeamAbbreviation(
                                                selectedHomeTeam ?? 'Home'),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _homeOnLeft
                                                  ? Colors.black87
                                                  : Colors.grey.shade500,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Away team tab
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _homeOnLeft = false;
                                    });
                                    _updateCaption();
                                  },
                                  child: Container(
                                    height: 22,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: !_homeOnLeft
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade100,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(4),
                                        bottomRight: Radius.circular(4),
                                      ),
                                      border: Border.all(
                                        color: !_homeOnLeft
                                            ? Colors.grey.shade500
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.flight,
                                            size: 10,
                                            color: !_homeOnLeft
                                                ? Colors.black87
                                                : Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _getTeamAbbreviation(
                                                selectedAwayTeam ?? 'Away'),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: !_homeOnLeft
                                                  ? Colors.black87
                                                  : Colors.grey.shade500,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            // Display options to the right of switch button
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Display title
                                    Text(
                                      'Display:',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 1),
                                    // Type button
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (_homeOnLeft) {
                                              _homePlayerGridMode =
                                                  !_homePlayerGridMode;
                                              // Reset sort order when switching to grid mode
                                              if (_homePlayerGridMode) {
                                                _homeSortOption = 'number';
                                                _homeSortAscending = true;
                                              }
                                            } else {
                                              _awayPlayerGridMode =
                                                  !_awayPlayerGridMode;
                                              // Reset sort order when switching to grid mode
                                              if (_awayPlayerGridMode) {
                                                _awaySortOption = 'number';
                                                _awaySortAscending = true;
                                              }
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
                                          child: Text(
                                            _homeOnLeft
                                                ? (_homePlayerGridMode
                                                    ? 'Grid'
                                                    : 'List')
                                                : (_awayPlayerGridMode
                                                    ? 'Grid'
                                                    : 'List'),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Sort by options (only show when in List mode)
                                    if (!(_homeOnLeft
                                        ? _homePlayerGridMode
                                        : _awayPlayerGridMode)) ...[
                                      Text(
                                        'Sort:',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              if (_homeOnLeft) {
                                                if (_homeSortOption ==
                                                    'number') {
                                                  _homeSortOption = 'lastName';
                                                } else if (_homeSortOption ==
                                                    'lastName') {
                                                  _homeSortOption = 'firstName';
                                                } else {
                                                  _homeSortOption = 'number';
                                                }
                                              } else {
                                                if (_awaySortOption ==
                                                    'number') {
                                                  _awaySortOption = 'lastName';
                                                } else if (_awaySortOption ==
                                                    'lastName') {
                                                  _awaySortOption = 'firstName';
                                                } else {
                                                  _awaySortOption = 'number';
                                                }
                                              }
                                            });
                                          },
                                          child: Text(
                                            _homeOnLeft
                                                ? (_homeSortOption == 'number'
                                                    ? 'Player Numbers'
                                                    : _homeSortOption ==
                                                            'lastName'
                                                        ? 'Last Name'
                                                        : 'First Name')
                                                : (_awaySortOption == 'number'
                                                    ? 'Player Numbers'
                                                    : _awaySortOption ==
                                                            'lastName'
                                                        ? 'Last Name'
                                                        : 'First Name'),
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    // Ascending/Descending button
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (_homeOnLeft) {
                                              _homeSortAscending =
                                                  !_homeSortAscending;
                                            } else {
                                              _awaySortAscending =
                                                  !_awaySortAscending;
                                            }
                                          });
                                        },
                                        child: Text(
                                          _homeOnLeft
                                              ? (_homeSortAscending ? '↑' : '↓')
                                              : (_awaySortAscending
                                                  ? '↑'
                                                  : '↓'),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Edit Teams button
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          _showTeamEditorDialog(
                                              isHome: _homeOnLeft);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                          ),
                                          child: Text(
                                            'Edit Teams',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 0),
                        // small spacer above the player search bar
                        const SizedBox(height: 4),
                        // Search bar below team names and controls
                        SizedBox(
                          height: 24,
                          child: TextField(
                            controller: searchController,
                            cursorWidth: 1.5,
                            cursorHeight: 20,
                            style: const TextStyle(fontSize: 11, height: 1.1),
                            onChanged: (value) {
                              setState(() {
                                if (_homeOnLeft) {
                                  _homeSearchText = value;
                                } else {
                                  _awaySearchText = value;
                                }
                              });
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.only(
                                  left: 6, right: 6, top: 2, bottom: 2),
                              prefixIcon: const Icon(Icons.search,
                                  size: 14, color: Colors.grey),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 24),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade400),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade400),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                    color: Colors.blue.shade400, width: 1),
                              ),
                              hintText: 'Search players...',
                              hintStyle: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Player list
          Expanded(
            child: _isLoadingRosters
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : filteredRoster.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'No players',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      )
                    : (_homeOnLeft ? _homePlayerGridMode : _awayPlayerGridMode)
                        ? _buildPlayerGrid(
                            filteredRoster, selectedPlayers, _homeOnLeft)
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredRoster.length,
                              itemBuilder: (context, index) {
                                final player = filteredRoster[index];
                                final isSelected = selectedPlayers
                                    .contains(player.displayName);
                                final isHomePlayer = _homeOnLeft
                                    ? selectedHomePlayers
                                        .contains(player.displayName)
                                    : selectedAwayPlayers
                                        .contains(player.displayName);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        if (isHome) {
                                          selectedHomePlayers
                                              .remove(player.displayName);
                                        } else {
                                          selectedAwayPlayers
                                              .remove(player.displayName);
                                        }
                                      } else {
                                        // Track which team was selected first
                                        if (_firstTeamSelected == null) {
                                          _firstTeamSelected = isHome;
                                          _firstPlayerSelected =
                                              _removeJerseyNumberFromName(
                                                  player.displayName);
                                        } else {}
                                        if (isHome) {
                                          selectedHomePlayers
                                              .add(player.displayName);
                                        } else {
                                          selectedAwayPlayers
                                              .add(player.displayName);
                                        }

                                        // Switch to custom verb mode when a player is selected
                                        _isPlayerSearchMode = false;
                                        print(
                                            'FUCK: Player selected from list: ${player.displayName}, switching to custom verb mode');
                                      }
                                    });
                                    _updateCaption();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isHomePlayer
                                              ? Colors.grey.shade700
                                              : Colors.white)
                                          : Colors.grey.shade100,
                                      border: Border(
                                        bottom: BorderSide(
                                            color: isSelected
                                                ? (isHomePlayer
                                                    ? Colors.grey.shade700
                                                    : Colors.grey.shade400)
                                                : Colors.grey.shade200,
                                            width: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Red star for first selected player
                                        if (isSelected &&
                                            _isFirstSelectedPlayer(
                                                player.displayName))
                                          Container(
                                            margin:
                                                const EdgeInsets.only(right: 4),
                                            padding: const EdgeInsets.all(1),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                            child: const Icon(
                                              Icons.star,
                                              size: 8,
                                              color: Colors.white,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            _getFormattedPlayerName(
                                                player.displayName,
                                                isHome
                                                    ? _homeSortOption
                                                    : _awaySortOption),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isSelected
                                                  ? (isHomePlayer
                                                      ? Colors.white
                                                      : Colors.grey.shade800)
                                                  : Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerGrid(
      List<Player> roster, Set<String> selectedPlayers, bool isHome) {
    // Create a map to track which numbers have players
    Map<int, Player> playersByNumber = {};
    for (Player player in roster) {
      int jerseyNum = int.tryParse(player.jerseyNumber ?? '0') ?? 0;
      playersByNumber[jerseyNum] = player;
    }

    // Get sorted list based on current sort option
    List<int> jerseyNumbers;
    final sortOption = isHome ? _homeSortOption : _awaySortOption;
    final ascending = isHome ? _homeSortAscending : _awaySortAscending;

    if (sortOption == 'number') {
      // Sort by jersey number
      jerseyNumbers = playersByNumber.keys.toList();
      if (ascending) {
        jerseyNumbers.sort();
      } else {
        jerseyNumbers.sort((a, b) => b.compareTo(a));
      }
    } else {
      // For lastName and firstName, sort the roster first, then get jersey numbers in that order
      List<Player> sortedRoster = List.from(roster);
      if (sortOption == 'lastName') {
        sortedRoster.sort((a, b) {
          String lastNameA = a.fullName.split(' ').skip(1).join(' ');
          String lastNameB = b.fullName.split(' ').skip(1).join(' ');
          return ascending
              ? lastNameA.compareTo(lastNameB)
              : lastNameB.compareTo(lastNameA);
        });
      } else if (sortOption == 'firstName') {
        sortedRoster.sort((a, b) {
          String firstNameA = a.fullName.split(' ').first;
          String firstNameB = b.fullName.split(' ').first;
          return ascending
              ? firstNameA.compareTo(firstNameB)
              : firstNameB.compareTo(firstNameA);
        });
      }

      // Get jersey numbers in the sorted order
      jerseyNumbers = sortedRoster.map((player) {
        return int.tryParse(player.jerseyNumber ?? '0') ?? 0;
      }).toList();
    }

    // Group players by jersey number ranges (0-9, 10-19, 20-29, etc.)
    Map<int, List<int>> playersByRange = {};
    for (int jerseyNum in jerseyNumbers) {
      int range = (jerseyNum ~/ 10) * 10; // 0, 10, 20, 30, etc.
      playersByRange.putIfAbsent(range, () => []).add(jerseyNum);
    }

    // Sort jersey numbers within each range by number (not by name)
    for (int range in playersByRange.keys) {
      playersByRange[range]!.sort();
      // print('DEBUG: Range $range contains: ${playersByRange[range]}');
    }

    // Create rows with dynamic number of columns, grouped by ranges
    List<Widget> rows = [];
    List<int> sortedRanges = playersByRange.keys.toList()..sort();
    // Determine max players in any range to set consistent columns per row
    int columnsPerRow = playersByRange.values.isNotEmpty
        ? playersByRange.values
            .map((list) => list.length)
            .reduce((a, b) => a > b ? a : b)
        : 1;
    if (columnsPerRow < 1) columnsPerRow = 1;

    for (int range in sortedRanges) {
      List<int> rangeJerseyNumbers = playersByRange[range]!;
      List<Widget> allPlayersInRange = [];

      // First, create all player widgets for this range
      for (int jerseyNum in rangeJerseyNumbers) {
        Player player = playersByNumber[jerseyNum]!;
        bool isSelected = selectedPlayers.contains(player.displayName);
        bool isHomePlayer = selectedHomePlayers.contains(player.displayName);

        allPlayersInRange.add(
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    if (isHome) {
                      selectedHomePlayers.remove(player.displayName);
                    } else {
                      selectedAwayPlayers.remove(player.displayName);
                    }
                  } else {
                    // Track which team was selected first; set first player if not set
                    if (_firstTeamSelected == null) {
                      _firstTeamSelected = isHome;
                      _firstPlayerSelected =
                          _removeJerseyNumberFromName(player.displayName);
                    }
                    if (isHome) {
                      selectedHomePlayers.add(player.displayName);
                    } else {
                      selectedAwayPlayers.add(player.displayName);
                    }

                    // Switch to custom verb mode when a player is selected
                    _isPlayerSearchMode = false;
                  }
                });
                _updateCaption();

                // Store the original caption AFTER it's been updated (for grid selection)
                _originalCaptionBeforeCustomVerb = captionController.text;
              },
              child: Container(
                margin: const EdgeInsets.all(1),
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isHomePlayer ? Colors.grey.shade700 : Colors.white)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                        ? (isHomePlayer
                            ? Colors.grey.shade700
                            : Colors.grey.shade400)
                        : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            jerseyNum.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? (isHomePlayer
                                      ? Colors.white
                                      : Colors.black87)
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            player.fullName.split(' ').skip(1).join(' '),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? (isHomePlayer
                                      ? Colors.white
                                      : Colors.black87)
                                  : Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    // Red star for first selected player
                    if (isSelected &&
                        _isFirstSelectedPlayer(player.displayName))
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Icon(
                            Icons.star,
                            size: 8,
                            color: Colors.white,
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

      // Now create rows from all players in this range
      for (int i = 0; i < allPlayersInRange.length; i += columnsPerRow) {
        List<Widget> currentRow = [];

        // Add players for this row
        for (int j = 0;
            j < columnsPerRow && i + j < allPlayersInRange.length;
            j++) {
          currentRow.add(allPlayersInRange[i + j]);
        }

        // Fill remaining slots with placeholder squares
        while (currentRow.length < columnsPerRow) {
          currentRow.add(
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                ),
                child: Container(), // Empty placeholder square
              ),
            ),
          );
        }

        rows.add(Row(children: currentRow));
      }
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: rows,
      ),
    );
  }

  Widget _buildCompactVerbColumn() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verb categories with compact layout
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: _selectedVerb == 'Single' ||
                      _selectedVerb == 'Double' ||
                      _selectedVerb == 'Triple'
                  ? _buildHittingSubOptions()
                  : _selectedVerb == 'Sacrifice Fly'
                      ? _buildSacrificeFlySubOptions()
                      : _selectedVerb == 'Home Run'
                          ? _buildHomeRunSubOptions()
                          : _selectedVerb == 'Tags'
                              ? _buildTagsSubOptions()
                              : _selectedVerb == 'Catches'
                                  ? _buildCatchesSubOptions()
                                  : _selectedVerb == 'Groundball'
                                      ? _buildGroundballSubOptions()
                                      : (_selectedVerb == 'At Bat' ||
                                              _selectedVerb == 'Pitching' ||
                                              _selectedVerb == 'Swings' ||
                                              _selectedVerb == 'Throws' ||
                                              _selectedVerb ==
                                                  'Fielding Position' ||
                                              _selectedVerb == 'Bunts' ||
                                              _selectedVerb == 'Walks' ||
                                              _selectedVerb == 'Hit by Pitch' ||
                                              _selectedVerb == 'Strikeout' ||
                                              _selectedVerb == 'Looks On' ||
                                              _selectedVerb ==
                                                  'Walks Off Field' ||
                                              _selectedVerb ==
                                                  'Runs Off Field' ||
                                              _selectedVerb ==
                                                  'Takes the Field' ||
                                              _selectedVerb ==
                                                  'Comes Off the Field' ||
                                              _selectedVerb ==
                                                  'Post Game Win' ||
                                              _selectedVerb == 'Post Game Loss')
                                          ? _buildInningOnlyInterface()
                                          : (_selectedVerb ==
                                                      'Batting Practice' ||
                                                  _selectedVerb ==
                                                      'Fielding Practice')
                                              ? _buildPracticeInterface()
                                              : (_selectedVerb ==
                                                          'Steals' ||
                                                      _selectedVerb ==
                                                          'Slides' ||
                                                      _selectedVerb == 'Runs' ||
                                                      _selectedVerb ==
                                                          'Rounds' ||
                                                      _selectedVerb ==
                                                          'Double Play' ||
                                                      _selectedVerb ==
                                                          'Triple Play')
                                                  ? _buildBaseSelectionInterface()
                                                  : (_selectedVerb ==
                                                              'Celebration' ||
                                                          _selectedVerb ==
                                                              'Celebrates' ||
                                                          _selectedVerb ==
                                                              'Celebrates With' ||
                                                          _selectedVerb ==
                                                              'Celebrates Against')
                                                      ? _buildCelebrationInterface()
                                                      : (_selectedVerb ==
                                                              'Dejection')
                                                          ? _buildDejectionInterface()
                                                          : (_selectedVerb ==
                                                                      'National Anthem' ||
                                                                  _selectedVerb ==
                                                                      'Stretching' ||
                                                                  _selectedVerb ==
                                                                      'Warm Ups')
                                                              ? _buildNationalAnthemInterface()
                                                              : (_selectedVerb ==
                                                                      'Pitching Change')
                                                                  ? _buildPitchingChangeInterface()
                                                                  : Column(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        // Player chips row (moved from above caption building section)
                                                                        // TODO: Player chips bar temporarily removed - keep code for later
                                                                        // Container(
                                                                        //   width:
                                                                        //       double.infinity,
                                                                        //   height:
                                                                        //       32,
                                                                        //   padding: const EdgeInsets
                                                                        //       .symmetric(
                                                                        //       horizontal: 12,
                                                                        //       vertical: 6),
                                                                        //   decoration:
                                                                        //       BoxDecoration(
                                                                        //     color:
                                                                        //         Colors.grey.shade50,
                                                                        //     borderRadius:
                                                                        //         BorderRadius.circular(6),
                                                                        //     border:
                                                                        //         Border.all(color: Colors.grey.shade300),
                                                                        //   ),
                                                                        //   child:
                                                                        //       _buildPlayerChipsHeader(),
                                                                        // ),
                                                                        // TODO: Player chips bar temporarily removed - keep code for later
                                                                        // const SizedBox(
                                                                        //     height:
                                                                        //         4),
                                                                        // // Custom text field for between players

                                                                        // Player selection overlay
                                                                        if (_filteredPlayers.isNotEmpty ||
                                                                            _noPlayersFound)
                                                                          Material(
                                                                            elevation:
                                                                                8,
                                                                            borderRadius:
                                                                                BorderRadius.circular(4),
                                                                            child:
                                                                                Container(
                                                                              decoration: BoxDecoration(
                                                                                color: Colors.white,
                                                                                borderRadius: BorderRadius.circular(4),
                                                                                border: Border.all(color: Colors.grey.shade300),
                                                                              ),
                                                                              child: Column(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  if (_noPlayersFound)
                                                                                    Container(
                                                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                                                      child: Row(
                                                                                        children: [
                                                                                          Icon(Icons.info_outline, size: 16, color: Colors.orange.shade600),
                                                                                          const SizedBox(width: 8),
                                                                                          Text(
                                                                                            'No player with number $_playerSearchText',
                                                                                            style: TextStyle(
                                                                                              fontSize: 12,
                                                                                              color: Colors.orange.shade700,
                                                                                              fontWeight: FontWeight.w500,
                                                                                            ),
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                    )
                                                                                  else ...[
                                                                                    ..._filteredPlayers.map(
                                                                                      (player) => GestureDetector(
                                                                                        onTap: () => _selectPlayer(player),
                                                                                        child: Container(
                                                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                                                          child: Row(
                                                                                            children: [
                                                                                              Text(
                                                                                                '#${player.jerseyNumber}',
                                                                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                                                                              ),
                                                                                              const SizedBox(width: 2),
                                                                                              Text(
                                                                                                _getTeamAbbreviation(_isHomePlayer(player) ? selectedHomeTeam ?? '' : selectedAwayTeam ?? '') ?? '',
                                                                                                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                                                                                              ),
                                                                                              const SizedBox(width: 2),
                                                                                              Icon(
                                                                                                _isHomePlayer(player) ? Icons.home : Icons.flight,
                                                                                                size: 11,
                                                                                                color: _isHomePlayer(player) ? Colors.blue.shade600 : Colors.red.shade600,
                                                                                              ),
                                                                                              const SizedBox(width: 2),
                                                                                              Expanded(
                                                                                                child: Text(
                                                                                                  _removeJerseyNumberFromName(player.displayName ?? 'Unknown'),
                                                                                                  style: const TextStyle(fontSize: 10),
                                                                                                  overflow: TextOverflow.ellipsis,
                                                                                                ),
                                                                                              ),
                                                                                            ],
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                  if (_selectedPlayerNumbers.isNotEmpty)
                                                                                    GestureDetector(
                                                                                      onTap: _finishPlayerSelection,
                                                                                      child: Container(
                                                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                                                        decoration: BoxDecoration(
                                                                                          color: Colors.blue.shade50,
                                                                                          border: Border(top: BorderSide(color: Colors.grey.shade200)),
                                                                                        ),
                                                                                        child: Row(
                                                                                          children: [
                                                                                            Icon(Icons.check, size: 16, color: Colors.blue.shade700),
                                                                                            const SizedBox(width: 8),
                                                                                            Text(
                                                                                              'Done selecting players (${_selectedPlayerNumbers.length})',
                                                                                              style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                ],
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        // Inning selector - moved outside the magic bar container
                                                                        if (_showCustomTextInningSelector) ...[
                                                                          SizedBox(
                                                                            height:
                                                                                100,
                                                                            child:
                                                                                _buildReusableInningSelector(),
                                                                          ),
                                                                          const SizedBox(
                                                                              height: 4),
                                                                        ],

                                                                        const SizedBox(
                                                                            height:
                                                                                4), // Padding between Magic Bar and verb categories

                                                                        // Verb categories (always visible now that magic bar is removed)
                                                                        if (!_showCustomTextInningSelector) ...[
                                                                          SizedBox(
                                                                            height:
                                                                                500, // Increased height for verb area
                                                                            // Removed debug background for cleaner appearance
                                                                            child:
                                                                                SingleChildScrollView(
                                                                              child: Padding(
                                                                                padding: const EdgeInsets.all(0),
                                                                                child: LayoutBuilder(
                                                                                  builder: (context, constraints) {
                                                                                    // Calculate width for exactly 3 columns
                                                                                    final columnWidth = (constraints.maxWidth - 8) / 3; // Subtract spacing between columns (4px * 2 gaps)

                                                                                    return Container(
                                                                                      // 6 columns in one row
                                                                                      child: Row(
                                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                                        children: [
                                                                                          // Offense column
                                                                                          Expanded(
                                                                                            child: _buildVerbCategory('Offense', [
                                                                                              'Single',
                                                                                              'Double',
                                                                                              'Triple',
                                                                                              'Home Run',
                                                                                              'Sacrifice Fly',
                                                                                              'At Bat',
                                                                                              'Swings',
                                                                                              'Bunts',
                                                                                              'Walks',
                                                                                              'Hit by Pitch'
                                                                                            ]),
                                                                                          ),
                                                                                          const SizedBox(width: 2),
                                                                                          // Defense column
                                                                                          Expanded(
                                                                                            child: _buildVerbCategory('Defense', [
                                                                                              'Pitching',
                                                                                              'Pitching Change',
                                                                                              'Catches',
                                                                                              'Throws',
                                                                                              'Tags',
                                                                                              'Groundball',
                                                                                              'Fielding Position',
                                                                                              'Double Play',
                                                                                              'Triple Play',
                                                                                              ''
                                                                                            ]),
                                                                                          ),
                                                                                          const SizedBox(width: 2),
                                                                                          // Running column
                                                                                          Expanded(
                                                                                            child: _buildVerbCategory('Running', [
                                                                                              'Steals',
                                                                                              'Slides',
                                                                                              'Runs',
                                                                                              'Rounds',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              ''
                                                                                            ]),
                                                                                          ),
                                                                                          const SizedBox(width: 2),
                                                                                          // Reactions column
                                                                                          Expanded(
                                                                                            child: _buildVerbCategory('Reactions', [
                                                                                              'Celebrates',
                                                                                              'Dejection',
                                                                                              'Post Game Win',
                                                                                              'Post Game Loss',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              '',
                                                                                              ''
                                                                                            ]),
                                                                                          ),
                                                                                          const SizedBox(width: 2),
                                                                                          // Non Game-Action column
                                                                                          Expanded(
                                                                                            child: _buildVerbCategory('Non Game-Action', [
                                                                                              'Looks On',
                                                                                              'Batting Practice',
                                                                                              'Fielding Practice',
                                                                                              'Takes the Field',
                                                                                              'Comes Off the Field',
                                                                                              'National Anthem',
                                                                                              'Stretching',
                                                                                              'Warm Ups',
                                                                                              '',
                                                                                              ''
                                                                                            ]),
                                                                                          ),
                                                                                          const SizedBox(width: 2),
                                                                                        ],
                                                                                      ),
                                                                                    ); // Close Container for Wrap
                                                                                  },
                                                                                ),
                                                                              ),
                                                                            ), // Close SingleChildScrollView
                                                                          ),
                                                                        ],

                                                                        const SizedBox(
                                                                            height:
                                                                                4),
                                                                        // Third row: Dynamic content
                                                                        Expanded(
                                                                          // Fills remaining space after verb area takes what it needs
                                                                          child:
                                                                              Row(
                                                                            children: [
                                                                              Expanded(
                                                                                child: Container(), // Empty space
                                                                              ),
                                                                              const SizedBox(width: 1),
                                                                              Expanded(
                                                                                child: Container(), // Empty space
                                                                              ),
                                                                              const SizedBox(width: 1),
                                                                              Expanded(
                                                                                child: Column(
                                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                                  children: [
                                                                                    // Home run types (when home run is selected)
                                                                                    if (_selectedVerb == 'Home Run')
                                                                                      _buildVerbCategory('Home Run Types', [
                                                                                        'Solo',
                                                                                        'Two-Run',
                                                                                        'Three-Run',
                                                                                        'Grand Slam'
                                                                                      ]),

                                                                                    // Inning only (when simple verbs are selected)
                                                                                    if (_selectedVerb == 'At Bat' || _selectedVerb == 'Pitching' || _selectedVerb == 'Swings' || _selectedVerb == 'Catches' || _selectedVerb == 'Throws' || _selectedVerb == 'Groundball' || _selectedVerb == 'Fielding Position') ...[
                                                                                      const SizedBox(height: 1),
                                                                                      Container(
                                                                                        decoration: BoxDecoration(
                                                                                          border: Border.all(color: Colors.grey.shade400),
                                                                                          borderRadius: BorderRadius.circular(2),
                                                                                        ),
                                                                                        child: Column(
                                                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                                                          children: [
                                                                                            Container(
                                                                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                              child: const Text(
                                                                                                'INN',
                                                                                                style: TextStyle(
                                                                                                  fontSize: 8,
                                                                                                  fontWeight: FontWeight.w500,
                                                                                                  color: Colors.grey,
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                            GestureDetector(
                                                                                              onTap: _showCompactInningSelector,
                                                                                              child: Container(
                                                                                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                                child: Text(
                                                                                                  _selectedRbiInning != null ? _getOrdinalSuffix(_selectedRbiInning!) : '',
                                                                                                  style: const TextStyle(fontSize: 8),
                                                                                                  textAlign: TextAlign.center,
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                    ],

                                                                                    // RBI & Inning (when any hitting verb is selected)
                                                                                    if (_selectedVerb == 'Single' || _selectedVerb == 'Double' || _selectedVerb == 'Triple' || _selectedVerb == 'Home Run' || _selectedVerb == 'Grand Slam' || _selectedVerb == 'Walks') ...[
                                                                                      const SizedBox(height: 1),
                                                                                      Row(
                                                                                        children: [
                                                                                          Expanded(
                                                                                            child: Container(
                                                                                              decoration: BoxDecoration(
                                                                                                border: Border.all(color: Colors.grey.shade400),
                                                                                                borderRadius: BorderRadius.circular(2),
                                                                                              ),
                                                                                              child: Column(
                                                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                                                children: [
                                                                                                  Container(
                                                                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                                    child: const Text(
                                                                                                      'RBI',
                                                                                                      style: TextStyle(
                                                                                                        fontSize: 8,
                                                                                                        fontWeight: FontWeight.w500,
                                                                                                        color: Colors.grey,
                                                                                                      ),
                                                                                                    ),
                                                                                                  ),
                                                                                                  DropdownButtonFormField<int>(
                                                                                                    value: _rbiCount,
                                                                                                    decoration: const InputDecoration(
                                                                                                      isDense: true,
                                                                                                      contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                                      border: InputBorder.none,
                                                                                                      labelText: null,
                                                                                                    ),
                                                                                                    items: [0, 1, 2, 3, 4].map((rbi) {
                                                                                                      return DropdownMenuItem(
                                                                                                        value: rbi,
                                                                                                        child: Text(rbi == 0 ? '0' : '$rbi', style: const TextStyle(fontSize: 8)),
                                                                                                      );
                                                                                                    }).toList(),
                                                                                                    onChanged: (value) {
                                                                                                      setState(() {
                                                                                                        _rbiCount = value;
                                                                                                      });
                                                                                                      _updateCaption();
                                                                                                    },
                                                                                                  ),
                                                                                                ],
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                          const SizedBox(width: 1),
                                                                                          Expanded(
                                                                                            child: Container(
                                                                                              decoration: BoxDecoration(
                                                                                                border: Border.all(color: Colors.grey.shade400),
                                                                                                borderRadius: BorderRadius.circular(2),
                                                                                              ),
                                                                                              child: Column(
                                                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                                                children: [
                                                                                                  Container(
                                                                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                                    child: const Text(
                                                                                                      'INN',
                                                                                                      style: TextStyle(
                                                                                                        fontSize: 8,
                                                                                                        fontWeight: FontWeight.w500,
                                                                                                        color: Colors.grey,
                                                                                                      ),
                                                                                                    ),
                                                                                                  ),
                                                                                                  GestureDetector(
                                                                                                    onTap: _showCompactInningSelector,
                                                                                                    child: Container(
                                                                                                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                                      child: Text(
                                                                                                        _selectedRbiInning != null ? _getOrdinalSuffix(_selectedRbiInning!) : '',
                                                                                                        style: const TextStyle(fontSize: 8),
                                                                                                        textAlign: TextAlign.center,
                                                                                                      ),
                                                                                                    ),
                                                                                                  ),
                                                                                                ],
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                    ],
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerbCategory(String title, List<String> verbs) {
    return Container(
      // Removed debug background for cleaner appearance
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with background span
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Verb options
          ...verbs.map((verb) => _buildVerbOption(verb)).toList(),
        ],
      ),
    );
  }

  // Function to find the shortest unique prefix for a verb
  String _getShortestUniquePrefix(String verb, List<String> allVerbs) {
    for (int i = 1; i <= verb.length; i++) {
      String prefix = verb.substring(0, i).toLowerCase();
      bool isUnique = true;

      for (String otherVerb in allVerbs) {
        if (otherVerb != verb && otherVerb.toLowerCase().startsWith(prefix)) {
          isUnique = false;
          break;
        }
      }

      if (isUnique) {
        return verb.substring(0, i);
      }
    }
    return verb; // Fallback to full verb if no unique prefix found
  }

  Widget _buildVerbOption(String verb) {
    // Don't show anything for empty placeholder verbs
    if (verb.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSelected = _selectedVerb == verb;

    // Get all verbs for prefix calculation
    List<String> allVerbs = [];
    for (List<String> verbs in verbCategories.values) {
      allVerbs.addAll(verbs);
    }

    // Get the shortest unique prefix for this verb
    String shortestPrefix = _getShortestUniquePrefix(verb, allVerbs);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;

            // Clear magic bar text for Home Run to ensure verb categories are hidden
            if (verb == 'Home Run') {
              // Magic bar removed: no-op
              print('DEBUG: Home Run selected - cleared magic bar text');
              print('DEBUG: _selectedVerb = $_selectedVerb');
              print('DEBUG: customBetweenPlayersController.text = ""');
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        width: double.infinity, // Dynamic width to fit container
        height: 34, // Optimal height to accommodate wrapped text
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Builder(builder: (context) {
            String typed = _magicBarVerbInput;
            // Only use trailing letters for verb matching (ignore digits like in "h27")
            final RegExpMatch? lettersMatch =
                RegExp(r'([a-zA-Z]+)$').firstMatch(typed);
            final String typedLetters =
                lettersMatch?.group(1)?.toLowerCase() ?? '';

            // Debug output
            // print(
            //     'DEBUG: Verb: $verb, Typed: "$typed", Letters: "$typedLetters"');

            // Calculate the shortcut letters for this verb
            String shortcutLetters = '';
            final words = verb.split(' ');
            final filtered = words
                .where((w) => w.trim().isNotEmpty && w.toLowerCase() != 'the')
                .toList();

            if (filtered.isEmpty) {
              // Fallback if no valid words found
              shortcutLetters = verb.length >= 3
                  ? verb.substring(0, 3).toLowerCase()
                  : verb.toLowerCase();
            } else if (filtered.length > 1) {
              // Multi-word verb: use acronym
              shortcutLetters = filtered.map((w) => w[0].toLowerCase()).join();
            } else {
              // Single word verb: use first 2-3 letters
              final first = filtered.first.toLowerCase();
              shortcutLetters =
                  first.length >= 3 ? first.substring(0, 3) : first;
            }

            // Determine what to highlight based on what's typed
            String displayPrefix;
            List<int> firstLetterPositions = [];

            if (filtered.length > 1) {
              // Multi-word verb: find positions of first letters to highlight
              int currentPos = 0;

              for (int i = 0; i < words.length; i++) {
                String word = words[i].trim();
                if (word.isNotEmpty && word.toLowerCase() != 'the') {
                  // Find the position of the first letter in this word
                  int wordStart = currentPos +
                      (i > 0 ? 1 : 0); // Account for space before word
                  int firstLetterPos = wordStart + word.indexOf(word[0]);
                  firstLetterPositions.add(firstLetterPos);
                }
                currentPos +=
                    word.length + (i > 0 ? 1 : 0); // Add word length + space
              }

              if (typedLetters.isNotEmpty &&
                  shortcutLetters.startsWith(typedLetters)) {
                // User is typing the shortcut - highlight the first letters they've typed
                int lettersToHighlight = typedLetters.length;
                if (lettersToHighlight <= firstLetterPositions.length) {
                  displayPrefix = verb.substring(
                      0, firstLetterPositions[lettersToHighlight - 1] + 1);
                } else {
                  displayPrefix =
                      verb.substring(0, firstLetterPositions.last + 1);
                }
              } else {
                // Show all first letters
                displayPrefix =
                    verb.substring(0, firstLetterPositions.last + 1);
              }
            } else {
              // Single word verb: use first 2-3 letters
              if (typedLetters.isNotEmpty &&
                  shortcutLetters.startsWith(typedLetters)) {
                // User is typing the shortcut - highlight what they've typed
                final int len = typedLetters.length < verb.length
                    ? typedLetters.length
                    : verb.length;
                displayPrefix = verb.substring(0, len);
              } else if (typedLetters.isEmpty) {
                // No typing - show the shortcut letters
                displayPrefix = verb.substring(0, shortcutLetters.length);
              } else {
                // User typed something else - show shortcut letters
                displayPrefix = verb.substring(0, shortcutLetters.length);
              }
            }

            if (filtered.length > 1) {
              // Multi-word verb: show fire emoji with shortcut after word
              if (_magicBarFocusNode.hasFocus) {
                return RichText(
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: verb,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      TextSpan(
                        text: ' 🔥$shortcutLetters',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Text(
                  verb,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                );
              }
            } else {
              // Single word verb: show fire emoji with shortcut after word
              if (_magicBarFocusNode.hasFocus) {
                return RichText(
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: verb,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      TextSpan(
                        text: ' 🔥$shortcutLetters',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                // Firebar inactive – normal styling
                return Text(
                  verb,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                );
              }
            }
          }),
        ),
      ),
    );
  }

  Widget _buildCompactVerbChip(String verb, String label) {
    final isSelected = _selectedVerb == verb;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHomeRunTypeChip(String hrType, String label) {
    final isSelected = _selectedHomeRunType == hrType;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHomeRunType = null;
          } else {
            _selectedHomeRunType = hrType;
            switch (hrType) {
              case 'Solo':
                _rbiCount = 1;
                break;
              case 'Two-Run':
                _rbiCount = 2;
                break;
              case 'Three-Run':
                _rbiCount = 3;
                break;
              case 'Grand Slam':
                _rbiCount = 4;
                break;
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  void _showCompactInningSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Inning', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 200,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 13,
            itemBuilder: (context, index) {
              final inning = index + 1;
              final isSelected = _selectedRbiInning == inning;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRbiInning = inning;
                    _isPriorToGame = false;
                  });
                  _updateCaption();
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.grey.shade300
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? Colors.grey.shade400
                          : Colors.grey.shade400,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      inning == 13
                          ? 'Prior to Game'
                          : _getOrdinalSuffix(inning),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.grey.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCaptionPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note, size: 12, color: Colors.black87),
              SizedBox(width: 4),
              Text(
                'Caption:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              captionController.text.isEmpty
                  ? 'No caption generated yet...'
                  : captionController.text,
              style: TextStyle(
                fontSize: 10,
                color: captionController.text.isEmpty
                    ? Colors.grey.shade600
                    : Colors.black87,
                fontStyle: captionController.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainVerbSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Main Action:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildVerbChip('Offense', 'Offense')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Defense', 'Defense')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Running', 'Running')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Reactions', 'Reactions')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Magic', 'Magic')),
          ],
        ),
      ],
    );
  }

  Widget _buildVerbChip(String verb, String label) {
    final isSelected = _selectedVerb == verb;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            // Reset other states when selecting a new verb
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          }
          _updateCaption();
        });
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeRunOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Home Run Type:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _buildHomeRunTypeChip('Solo', 'Solo HR'),
            _buildHomeRunTypeChip('Two-Run', '2-Run HR'),
            _buildHomeRunTypeChip('Three-Run', '3-Run HR'),
            _buildHomeRunTypeChip('Grand Slam', 'Grand Slam'),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeRunTypeChip(String hrType, String label) {
    final isSelected = _selectedHomeRunType == hrType;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHomeRunType = null;
          } else {
            _selectedHomeRunType = hrType;
            // Set RBI count based on HR type
            switch (hrType) {
              case 'Solo':
                _rbiCount = 1;
                break;
              case 'Two-Run':
                _rbiCount = 2;
                break;
              case 'Three-Run':
                _rbiCount = 3;
                break;
              case 'Grand Slam':
                _rbiCount = 4;
                break;
            }
          }
          _updateCaption();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildRbiAndInningOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RBI & Inning:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // RBI Count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RBI:', style: TextStyle(fontSize: 10)),
                  const SizedBox(height: 2),
                  DropdownButtonFormField<int>(
                    value: _rbiCount,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    items: [0, 1, 2, 3, 4].map((rbi) {
                      return DropdownMenuItem(
                        value: rbi,
                        child: Text(rbi == 0 ? 'No RBI' : '$rbi RBI',
                            style: const TextStyle(fontSize: 10)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _rbiCount = value;
                      });
                      _updateCaption();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Inning
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inning:', style: TextStyle(fontSize: 10)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _showInningSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedRbiInning != null
                                  ? _getOrdinalSuffix(_selectedRbiInning!)
                                  : 'Select',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showInningSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Inning'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12, // 1-9 + 10, 11, 12
            itemBuilder: (context, index) {
              final inning = index < 9 ? index + 1 : index + 1;
              final isSelected = _selectedRbiInning == inning;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRbiInning = inning;
                  });
                  _updateCaption();
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade300
                          : Colors.grey.shade400,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getOrdinalSuffix(inning),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _getOrdinalSuffix(int number) {
    switch (number) {
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
      case 10:
        return 'tenth';
      case 11:
        return 'eleventh';
      case 12:
        return 'twelfth';
      case 13:
        return 'thirteenth';
      case 14:
        return 'fourteenth';
      case 15:
        return 'fifteenth';
      case 16:
        return 'sixteenth';
      case 17:
        return 'seventeenth';
      case 18:
        return 'eighteenth';
      case 19:
        return 'nineteenth';
      case 20:
        return 'twentieth';
      case 21:
        return 'twenty-first';
      case 22:
        return 'twenty-second';
      case 23:
        return 'twenty-third';
      case 24:
        return 'twenty-fourth';
      case 25:
        return 'twenty-fifth';
      case 26:
        return 'twenty-sixth';
      case 27:
        return 'twenty-seventh';
      case 28:
        return 'twenty-eighth';
      case 29:
        return 'twenty-ninth';
      case 30:
        return 'thirtieth';
      default:
        return '${number}th';
    }
  }

  // Handle multiple player numbers input (e.g., "27 23")
  void _handleMultiplePlayerInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // If input cleared, deselect all players and update caption
      setState(() {
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstPlayerSelected = null;
        _firstTeamSelected = null;
        _filteredPlayers.clear();
      });
      _updateCaption();
      return;
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final lastPart = parts.isNotEmpty ? parts.last : '';

    // Build target selections from tokens so UI reflects exactly what's typed
    final Set<String> nextHome = {};
    final Set<String> nextAway = {};
    bool? firstTeamIsHome;
    String? firstPlayerCleaned;

    for (int i = 0; i < parts.length; i++) {
      final token = parts[i].toLowerCase();
      if (token.isEmpty) continue;
      // Match hNN / hhNN / vNN / vvNN or plain NN
      final match = RegExp(r'^(h{1,2}|v{1,2})?(\d+)$').firstMatch(token);
      if (match == null) continue;
      final prefix = match.group(1);
      final num = match.group(2)!;

      // Find matching players in rosters
      List<Player> candidates;
      if (prefix == null) {
        candidates = [
          ..._homeRoster.where((p) => p.jerseyNumber == num),
          ..._awayRoster.where((p) => p.jerseyNumber == num),
        ];
      } else if (prefix.startsWith('h')) {
        candidates = _homeRoster.where((p) => p.jerseyNumber == num).toList();
      } else {
        candidates = _awayRoster.where((p) => p.jerseyNumber == num).toList();
      }
      if (candidates.isEmpty) continue;
      final player = candidates.first;
      final display = player.displayName;
      final cleaned = _removeJerseyNumberFromName(display);
      final isHome = prefix == null
          ? selectedHomePlayers.contains(display) // fall back to current
          : prefix.startsWith('h');

      if (isHome) {
        nextHome.add(display);
      } else {
        nextAway.add(display);
      }
      firstTeamIsHome ??= isHome;
      firstPlayerCleaned ??= cleaned;
    }

    // Apply computed selections so deletions are reflected
    setState(() {
      selectedHomePlayers
        ..clear()
        ..addAll(nextHome);
      selectedAwayPlayers
        ..clear()
        ..addAll(nextAway);
      _firstTeamSelected = firstTeamIsHome;
      _firstPlayerSelected = firstPlayerCleaned;

      // Update filtered players for live highlight of the last numeric token
      if (_isNumeric(lastPart)) {
        _filterPlayersByNumber(lastPart);
      } else {
        _filteredPlayers.clear();
      }
    });
    _updateCaption();
  }

  // Magic input parsing methods
  bool _isMagicInput(String input) {
    print('DEBUG: _isMagicInput called with: "$input"');
    if (input.isEmpty) return false;

    final parts = input.trim().toLowerCase().split(' ');
    // Allow single-token inputs that are:
    // - HR type tokens like "solo"
    // - A plain jersey number (e.g., "27")
    // - A team-prefixed jersey number (e.g., "h27", "v23", "hh12", "vv45")
    if (parts.length == 1) {
      final token = parts[0];
      const hrTypeTokens = {
        'solo',
        'two-run',
        'tworun',
        'three-run',
        'threerun',
        'grand',
        'grandslam',
        'gs',
      };
      if (hrTypeTokens.contains(token)) return true;
      if (_isNumeric(token)) return true;
      final teamPrefixMatch = RegExp(r'^(h{1,2}|v{1,2})\d+$').hasMatch(token);
      print(
          'DEBUG: _isMagicInput checking token "$token", teamPrefixMatch: $teamPrefixMatch');
      if (teamPrefixMatch) return true;
      return false;
    }

    // Check if first part is a number OR a team prefix + number (like h27, v23)
    String firstPart = parts[0];
    bool isValidFirstPart = false;

    // Check if it's just a number
    if (_isNumeric(firstPart)) {
      isValidFirstPart = true;
    } else {
      // Check if it's a team prefix + number (h27, v23, hh27, vv23)
      final teamPrefixRegex = RegExp(r'^(h{1,2}|v{1,2})(\d+)$');
      final match = teamPrefixRegex.firstMatch(firstPart);
      print('DEBUG: Checking team prefix for "$firstPart", match: $match');
      if (match != null) {
        isValidFirstPart = true;
        print('DEBUG: Valid team prefix + number found');
      }
    }

    if (!isValidFirstPart) return false;

    // Check if there's an action word
    final actionWords = [
      'hr',
      'homerun',
      'homer',
      'single',
      '1b',
      'double',
      '2b',
      'triple',
      '3b',
      // Support HR type tokens as actions in multi-part inputs too
      'solo', 'two-run', 'tworun', 'three-run', 'threerun', 'grand',
      'grandslam', 'gs',
      'walks',
      'walk',
      'bb',
      'strikeout',
      'k',
      'steals',
      'steal',
      'sb',
      'catches',
      'catch',
      'throws',
      'throw',
      'tags',
      'tag',
      'pitches',
      'pitch',
      'pitching',
      'swings',
      'swing',
      'bunts',
      'bunt',
      'hbp',
      'hitbypitch',
      'celebrates',
      'celebrate',
      'dejection',
      'dejected',
      'looks',
      'look',
      'runs',
      'run',
      'slides',
      'slide',
      'rounds',
      'round',
      'groundball',
      'ground',
      'doubleplay',
      'dp',
      'tripleplay',
      'tp',
      'atbat',
      'at-bat',
      'bat',
      'fielding',
      'field',
      'warmup',
      'warm',
      'stretching',
      'stretch',
      'battingpractice',
      'bp',
      'fieldingpractice',
      'fp',
      'takesthefield',
      'takesfield',
      'comesofffield',
      'offfield',
      'nationalanthem',
      'anthem',
      'pitchingchange',
      'pitchchange',
      'postgamewin',
      'win',
      'postgameloss',
      'loss',
      'walksoffield',
      'walksoff',
      'runsoffield',
      'runsoff',
      'sacrificefly',
      'sf'
    ];

    for (int i = 1; i < parts.length; i++) {
      if (actionWords.contains(parts[i])) {
        return true;
      }
    }

    return false;
  }

  void _parseMagicInput(String input) {
    // print('DEBUG: _parseMagicInput called with: "$input"');
    if (input.isEmpty) return;

    // Reset only action-related state, but DO NOT clear players or first selection
    setState(() {
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;

      // Clear player search state to prevent conflicts
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = false;
    });

    // Show a brief success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Processing magic input: "$input"'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );

    // Parse the magic input
    final parts = input.trim().toLowerCase().split(' ');
    // print('DEBUG: Parts: $parts');
    // Handle single-token inputs
    if (parts.length == 1) {
      final token = parts[0];
      // HR type tokens like "solo", etc.
      if ({
        'solo',
        'two-run',
        'tworun',
        'three-run',
        'threerun',
        'grand',
        'grandslam',
        'gs'
      }.contains(token)) {
        setState(() {
          _selectedVerb = 'Home Run';
          _selectedActionVerb = 'Home Run';
          if (token == 'solo') {
            _selectedHomeRunType = 'Solo';
            _rbiCount = 1;
          } else if (token == 'two-run' || token == 'tworun') {
            _selectedHomeRunType = 'Two-Run';
            _rbiCount = 2;
          } else if (token == 'three-run' || token == 'threerun') {
            _selectedHomeRunType = 'Three-Run';
            _rbiCount = 3;
          } else {
            _selectedHomeRunType = 'Grand Slam';
            _rbiCount = 4;
          }
        });
        _updateCaption();
        return;
      }

      // Single player code (numeric or team-prefixed like h27)
      String singleFirstPart = token;
      String playerNumber;
      bool? isHomeHint;
      if (_isNumeric(singleFirstPart)) {
        playerNumber = singleFirstPart;
        isHomeHint = null;
      } else {
        final teamPrefixRegex = RegExp(r'^(h{1,2}|v{1,2})(\d+)$');
        final match = teamPrefixRegex.firstMatch(singleFirstPart);
        if (match != null) {
          playerNumber = match.group(2)!;
          final teamPrefix = match.group(1)!;
          isHomeHint = teamPrefix.startsWith('h');
        } else {
          print('DEBUG: Single token not recognized as player code');
          return;
        }
      }

      // Find and select/highlight player immediately
      List<Player> matching = [];
      if (isHomeHint != null) {
        final roster = isHomeHint ? _homeRoster : _awayRoster;
        matching = roster.where((p) => p.jerseyNumber == playerNumber).toList();
      } else {
        matching = [
          ..._homeRoster.where((p) => p.jerseyNumber == playerNumber),
          ..._awayRoster.where((p) => p.jerseyNumber == playerNumber),
        ];
      }
      if (matching.isEmpty) return;
      final found = matching.first;
      final isHomePlayer = _homeRoster.contains(found);
      _selectPlayerChipByNumber(
        isHomeTeam: isHomePlayer,
        jerseyNumber: playerNumber,
        isProgressive: true,
      );
      setState(() {
        final display = found.displayName ?? '';
        if (display.isNotEmpty) {
          if (isHomePlayer) {
            selectedHomePlayers.add(display);
          } else {
            selectedAwayPlayers.add(display);
          }
          // Do not set _firstPlayerSelected here if already set (preserve red star)
          _firstTeamSelected ??= isHomePlayer;
          _firstPlayerSelected ??= _removeJerseyNumberFromName(display);
        }
      });
      _updateCaption();
      return;
    }

    // Extract player number and team hint
    final firstPart = parts[0];
    String playerNumber;
    bool? isHomeHint;

    if (_isNumeric(firstPart)) {
      // Format: "27 hr 1st" - just a number
      playerNumber = firstPart;
      isHomeHint = null; // No team hint
    } else {
      // Format: "h27 hr 1st" or "v23 hr 1st" - team prefix + number
      final teamPrefixRegex = RegExp(r'^(h{1,2}|v{1,2})(\d+)$');
      final match = teamPrefixRegex.firstMatch(firstPart);
      if (match != null) {
        playerNumber = match.group(2)!; // Extract the number part
        final teamPrefix = match.group(1)!;
        isHomeHint =
            teamPrefix.startsWith('h'); // h or hh = home, v or vv = away
      } else {
        print('DEBUG: Invalid format, returning');
        return;
      }
    }

    print('DEBUG: Player number: $playerNumber, isHomeHint: $isHomeHint');

    // Find players with this number
    List<Player> matchingPlayers = [];
    print(
        'DEBUG: Home roster size: ${_homeRoster.length}, Away roster size: ${_awayRoster.length}');

    if (isHomeHint != null) {
      // Team hint provided, search only in the specified team
      final roster = isHomeHint! ? _homeRoster : _awayRoster;
      for (final player in roster) {
        if (player.jerseyNumber == playerNumber) {
          matchingPlayers.add(player);
        }
      }
    } else {
      // No team hint, search in both rosters
      for (final player in _homeRoster) {
        if (player.jerseyNumber == playerNumber) {
          matchingPlayers.add(player);
        }
      }
      for (final player in _awayRoster) {
        if (player.jerseyNumber == playerNumber) {
          matchingPlayers.add(player);
        }
      }
    }

    print('DEBUG: Found ${matchingPlayers.length} matching players');
    for (final player in matchingPlayers) {
      print(
          'DEBUG: Matching player: ${player.displayName} (${player.jerseyNumber}) - ${_homeRoster.contains(player) ? 'Home' : 'Away'}');
    }
    if (matchingPlayers.isEmpty) {
      print('DEBUG: No matching players found, returning');
      return;
    }

    // If multiple players found, ask for home/visitor choice
    if (matchingPlayers.length > 1) {
      print('DEBUG: Multiple players found, asking for home/visitor choice');
      setState(() {
        // Clear regular player search state to prevent conflicts
        _filteredPlayers.clear();
        _noPlayersFound = false;
        _isPlayerSearchMode = false;

        _magicInputMatchingPlayers = matchingPlayers;
        _magicInputActionText = parts.sublist(1).join(' ');
        _waitingForHomeVisitorChoice = true;

        // Store the original magic input text before showing dialog
        const originalText = '';
        print('DEBUG: Storing original text: "$originalText"');

        // Show popup dialog for home/visitor choice
        print('DEBUG: Set _waitingForHomeVisitorChoice = true');
        print('DEBUG: Will show Home/Visitor choice dialog');
        _showHomeVisitorChoiceDialog(originalText);
      });
      return;
    }

    // Single player found, proceed normally
    final foundPlayer = matchingPlayers.first;
    final isHomePlayer = _homeRoster.contains(foundPlayer);

    // Highlight the player in the player picker
    _selectPlayerChipByNumber(
      isHomeTeam: isHomePlayer,
      jerseyNumber: playerNumber,
      isProgressive:
          true, // Don't override existing red star on subsequent selections
      affectFirstStar:
          false, // Do not set first-star when auto-selecting via magic bar
    );

    // Select the player
    setState(() {
      final display = foundPlayer.displayName ?? 'Unknown Player';
      final cleaned = _removeJerseyNumberFromName(display);
      if (isHomePlayer) {
        selectedHomePlayers.add(display);
      } else {
        selectedAwayPlayers.add(display);
      }
      // On token completion, if no first-star yet, set it to this player
      if (_firstPlayerSelected == null) {
        _firstTeamSelected = isHomePlayer;
        _firstPlayerSelected = cleaned;
      }
    });

    // Ensure the original main player remains selected in its team list
    _ensureMainPlayerStillSelected();

    // Parse action and inning
    String action = '';
    int? inning;
    String? homeRunType; // Solo / Two-Run / Three-Run / Grand Slam

    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];

      // Check for inning number (supports ordinals like 1st, 2nd, etc.)
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }
      final ord = RegExp(r'^(\d+)(st|nd|rd|th)$').firstMatch(part);
      if (ord != null) {
        inning = int.parse(ord.group(1)!);
        continue;
      }

      // Check for home run type tokens
      if (part == 'solo' ||
          part == 'two-run' ||
          part == 'tworun' ||
          part == 'three-run' ||
          part == 'threerun' ||
          part == 'grand' ||
          part == 'grandslam' ||
          part == 'gs') {
        // Ensure action is Home Run if HR type is provided
        if (action.isEmpty) {
          action = 'Home Run';
        }
        if (part == 'solo') {
          homeRunType = 'Solo';
        } else if (part == 'two-run' || part == 'tworun') {
          homeRunType = 'Two-Run';
        } else if (part == 'three-run' || part == 'threerun') {
          homeRunType = 'Three-Run';
        } else {
          homeRunType = 'Grand Slam';
        }
        continue;
      }

      // Parse action
      // First try flexible 2–3 letter/acronym matching
      final matchedVerb = _matchVerbToken(part);
      if (matchedVerb != null) {
        action = matchedVerb;
        continue;
      }

      switch (part) {
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        case 'single':
        case '1b':
          action = 'Single';
          break;
        case 'double':
        case '2b':
          action = 'Double';
          break;
        case 'triple':
        case '3b':
          action = 'Triple';
          break;
        case 'walks':
        case 'walk':
        case 'bb':
          action = 'Walks';
          break;
        case 'strikeout':
        case 'k':
          action = 'Strikeout';
          break;
        case 'steals':
        case 'steal':
        case 'sb':
          action = 'Steals';
          break;
        case 'catches':
        case 'catch':
          action = 'Catches';
          break;
        case 'throws':
        case 'throw':
          action = 'Throws';
          break;
        case 'tags':
        case 'tag':
          action = 'Tags';
          break;
        case 'pitches':
        case 'pitch':
        case 'pitching':
          action = 'Pitching';
          break;
        case 'swings':
        case 'swing':
          action = 'Swings';
          break;
        case 'bunts':
        case 'bunt':
          action = 'Bunts';
          break;
        case 'hbp':
        case 'hitbypitch':
          action = 'Hit by Pitch';
          break;
        case 'sacrificefly':
        case 'sf':
          action = 'Sacrifice Fly';
          break;
        case 'celebrates':
        case 'celebrate':
          action = 'Celebrates';
          break;
        case 'dejection':
        case 'dejected':
          action = 'Dejection';
          break;
        case 'looks':
        case 'look':
          action = 'Looks On';
          break;
        case 'runs':
        case 'run':
          action = 'Runs';
          break;
        case 'slides':
        case 'slide':
          action = 'Slides';
          break;
        case 'rounds':
        case 'round':
          action = 'Rounds';
          break;
        case 'groundball':
        case 'ground':
          action = 'Groundball';
          break;
        case 'doubleplay':
        case 'dp':
          action = 'Double Play';
          break;
        case 'tripleplay':
        case 'tp':
          action = 'Triple Play';
          break;
        case 'atbat':
        case 'at-bat':
        case 'bat':
          action = 'At Bat';
          break;
        case 'fielding':
        case 'field':
          action = 'Fielding Position';
          break;
        case 'warmup':
        case 'warm':
          action = 'Warm Ups';
          break;
        case 'stretching':
        case 'stretch':
          action = 'Stretching';
          break;
        case 'battingpractice':
        case 'bp':
          action = 'Batting Practice';
          break;
        case 'fieldingpractice':
        case 'fp':
          action = 'Fielding Practice';
          break;
        case 'takesthefield':
        case 'takesfield':
          action = 'Takes the Field';
          break;
        case 'comesofffield':
        case 'offfield':
          action = 'Comes Off the Field';
          break;
        case 'nationalanthem':
        case 'anthem':
          action = 'National Anthem';
          break;
        case 'pitchingchange':
        case 'pitchchange':
          action = 'Pitching Change';
          break;
        case 'postgamewin':
        case 'win':
          action = 'Post Game Win';
          break;
        case 'postgameloss':
        case 'loss':
          action = 'Post Game Loss';
          break;
        case 'walksoffield':
        case 'walksoff':
          action = 'Walks Off Field';
          break;
        case 'runsoffield':
        case 'runsoff':
          action = 'Runs Off Field';
          break;
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        // Only set inning if explicitly provided in the input
        // Don't automatically set inning for shortcodes
        if (inning != null) {
          _selectedRbiInning = inning;
        }

        // Apply Home Run type if provided
        if (homeRunType != null) {
          _selectedHomeRunType = homeRunType;
          // Set RBI count based on HR type
          switch (homeRunType) {
            case 'Solo':
              _rbiCount = 1;
              break;
            case 'Two-Run':
              _rbiCount = 2;
              break;
            case 'Three-Run':
              _rbiCount = 3;
              break;
            case 'Grand Slam':
              _rbiCount = 4;
              break;
          }
        } else {
          // For shortcodes, interpret trailing numbers as RBI count, not inning
          // This prevents automatic inning writing for shortcodes
          if (inning != null &&
              (action == 'Home Run' ||
                  action == 'Single' ||
                  action == 'Double' ||
                  action == 'Triple')) {
            _rbiCount = inning; // Interpret trailing number as RBI count
            // Don't set inning for shortcodes - only set inning if explicitly provided as inning
            // _selectedRbiInning remains null for shortcodes
          } else {
            _rbiCount = null;
          }
        }
      });
    }

    // Update caption
    _updateCaption();

    // Keep the magic input visible in the field
    // (The magic input text is filtered out in _updateCaption)
  }

  void _showMagicInputPlayerSelectionDialog(
      List<Player> players, String actionText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Player'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Multiple players found with this number:'),
            const SizedBox(height: 16),
            ...players.map((player) {
              final isHome = _homeRoster.contains(player);
              final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;
              final teamAbbr = _getTeamAbbreviation(teamName ?? '') ?? '';

              return ListTile(
                leading: Icon(
                  isHome ? Icons.home : Icons.flight,
                  color: isHome ? Colors.blue.shade600 : Colors.red.shade600,
                ),
                title: Text('${player.fullName} #${player.jerseyNumber}'),
                subtitle: Text('$teamAbbr (${isHome ? 'Home' : 'Away'})'),
                onTap: () {
                  Navigator.of(context).pop();
                  _processMagicInputWithPlayer(player, actionText);
                },
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showHomeVisitorChoiceDialog(String originalText) {
    // Find home and visitor players
    Player? homePlayer = _magicInputMatchingPlayers.firstWhere(
      (player) => _homeRoster.contains(player),
      orElse: () => _magicInputMatchingPlayers.first,
    );
    Player? visitorPlayer = _magicInputMatchingPlayers.firstWhere(
      (player) => _awayRoster.contains(player),
      orElse: () => _magicInputMatchingPlayers.first,
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => RawKeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            final key = event.logicalKey;
            print('DEBUG: Key pressed in dialog: ${key.keyLabel}');

            if (key.keyLabel.toLowerCase() == 'h') {
              print('DEBUG: H key detected, closing dialog and selecting home');
              Navigator.of(context).pop();
              _processHomeVisitorChoiceAndRestore('h', originalText);
              return; // Prevent the key from reaching other listeners
            } else if (key.keyLabel.toLowerCase() == 'v') {
              print(
                  'DEBUG: V key detected, closing dialog and selecting visitor');
              Navigator.of(context).pop();
              _processHomeVisitorChoiceAndRestore('v', originalText);
              return; // Prevent the key from reaching other listeners
            }
          }
        },
        child: AlertDialog(
          title: const Text('Select Player'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Multiple players found with this number.'),
              const SizedBox(height: 16),
              // Home player option
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processHomeVisitorChoiceAndRestore('h', originalText);
                  },
                  icon: const Icon(Icons.home, size: 20),
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${homePlayer.fullName} #${homePlayer.jerseyNumber}'),
                      Text(
                        'Home Team',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue.shade100),
                      ),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Visitor player option
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processHomeVisitorChoiceAndRestore('v', originalText);
                  },
                  icon: const Icon(Icons.flight, size: 20),
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${visitorPlayer.fullName} #${visitorPlayer.jerseyNumber}'),
                      Text(
                        'Visitor Team',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade100),
                      ),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Column(
                  children: [
                    Text(
                      'Keyboard shortcuts:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Press H for Home, V for Visitor',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reset the waiting state
                setState(() {
                  _waitingForHomeVisitorChoice = false;
                  _magicInputMatchingPlayers.clear();
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _processHomeVisitorChoice(String choice) {
    print('DEBUG: Processing home/visitor choice: $choice');
    print(
        'DEBUG: Available players: ${_magicInputMatchingPlayers.map((p) => '${p.fullName} (${_homeRoster.contains(p) ? 'Home' : 'Away'})').join(', ')}');

    // Find the appropriate player based on choice
    Player? selectedPlayer;
    if (choice == 'h') {
      // Find home player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _homeRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected home player: ${selectedPlayer.fullName}');
    } else if (choice == 'v') {
      // Find away player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _awayRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected away player: ${selectedPlayer.fullName}');
    }

    if (selectedPlayer != null) {
      print('DEBUG: Clearing waiting state and selecting player');

      final isHomePlayer = _homeRoster.contains(selectedPlayer);
      final jerseyNumber = selectedPlayer.jerseyNumber ?? '';

      // Clear the waiting state and clear the firebar
      setState(() {
        _waitingForHomeVisitorChoice = false;
        _magicInputMatchingPlayers.clear();

        // Switch player picker to show the selected player's team on the left
        _homeOnLeft = isHomePlayer;
      });

      // Set the firebar to show the choice that was made (e.g., "v7" for visitor #7)
      final choicePrefix = isHomePlayer ? 'h' : 'v';
      _magicBarController.text = '$choicePrefix$jerseyNumber ';

      // Position cursor at the end (after the space)
      _magicBarController.selection = TextSelection.fromPosition(
        TextPosition(offset: _magicBarController.text.length),
      );

      // Select the player using the existing method
      _selectPlayerChipByNumber(
        isHomeTeam: isHomePlayer,
        jerseyNumber: jerseyNumber,
        isProgressive: false,
        affectFirstStar: true,
      );

      // Update the caption
      _updateCaption();
    } else {
      print('DEBUG: No player found for choice: $choice');
    }
  }

  void _processHomeVisitorChoiceAndRestore(String choice, String originalText) {
    print(
        'DEBUG: Processing home/visitor choice: $choice with original text: "$originalText"');
    print(
        'DEBUG: Available players: ${_magicInputMatchingPlayers.map((p) => '${p.fullName} (${_homeRoster.contains(p) ? 'Home' : 'Away'})').join(', ')}');

    // Find the appropriate player based on choice
    Player? selectedPlayer;
    if (choice == 'h') {
      // Find home player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _homeRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected home player: ${selectedPlayer.fullName}');
    } else if (choice == 'v') {
      // Find away player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _awayRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected away player: ${selectedPlayer.fullName}');
    }

    if (selectedPlayer != null) {
      print('DEBUG: Clearing waiting state and selecting player');

      final isHomePlayer = _homeRoster.contains(selectedPlayer);
      final jerseyNumber = selectedPlayer.jerseyNumber ?? '';

      // Clear the waiting state and clear the firebar
      setState(() {
        _waitingForHomeVisitorChoice = false;
        _magicInputMatchingPlayers.clear();

        // Switch player picker to show the selected player's team on the left
        _homeOnLeft = isHomePlayer;
      });

      // Set the firebar to show the choice that was made (e.g., "v7" for visitor #7)
      final choicePrefix = isHomePlayer ? 'h' : 'v';
      _magicBarController.text = '$choicePrefix$jerseyNumber ';

      // Position cursor at the end (after the space)
      _magicBarController.selection = TextSelection.fromPosition(
        TextPosition(offset: _magicBarController.text.length),
      );

      // Select the player using the existing method
      _selectPlayerChipByNumber(
        isHomeTeam: isHomePlayer,
        jerseyNumber: jerseyNumber,
        isProgressive: false,
        affectFirstStar: true,
      );

      // Update the caption
      _updateCaption();
    } else {
      print('DEBUG: No player found for choice: $choice');
    }
  }

  void _selectMagicInputPlayer(Player selectedPlayer) {
    // Clear the magic input options
    setState(() {
      _showMagicInputPlayerOptions = false;
      _magicInputMatchingPlayers.clear();
    });

    // Process the magic input with the selected player
    _processMagicInputWithPlayer(selectedPlayer, _magicInputActionText);
  }

  void _processMagicInputWithPlayer(Player selectedPlayer, String actionText) {
    // Reset only action-related state; keep existing selections and main player
    setState(() {
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;

      // Clear player search state to prevent conflicts
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = false;
    });

    // Select the chosen player
    final isHomePlayer = _homeRoster.contains(selectedPlayer);
    setState(() {
      final display = selectedPlayer.displayName ?? 'Unknown Player';
      final cleaned = _removeJerseyNumberFromName(display);
      if (isHomePlayer) {
        selectedHomePlayers.add(display);
        _firstTeamSelected ??= true;
        _firstPlayerSelected ??= cleaned;
      } else {
        selectedAwayPlayers.add(display);
        _firstTeamSelected ??= false;
        _firstPlayerSelected ??= cleaned;
      }
    });

    // Ensure the original main player remains selected in its team list
    _ensureMainPlayerStillSelected();

    // Parse the action text
    final parts = actionText.trim().toLowerCase().split(' ');
    print('DEBUG: actionText: "$actionText", parts: $parts');
    String action = '';
    int? inning;
    bool rbiSetByAbbreviation = false; // Track if RBI was set by abbreviation

    for (final part in parts) {
      // Check for RBI abbreviations first (sin3, dou2, tri4, hr5)
      final rbiMatch = RegExp(r'^(sin|dou|tri|hr)(\d+)$').firstMatch(part);
      print(
          'DEBUG: Checking part "$part" for RBI abbreviation, match: $rbiMatch');
      if (rbiMatch != null) {
        final actionType = rbiMatch.group(1)!;
        final rbiCount = int.parse(rbiMatch.group(2)!);
        print(
            'DEBUG: Found RBI abbreviation - actionType: $actionType, rbiCount: $rbiCount');

        // Set the action based on the abbreviation
        switch (actionType) {
          case 'sin':
            action = 'Single';
            break;
          case 'dou':
            action = 'Double';
            break;
          case 'tri':
            action = 'Triple';
            break;
          case 'hr':
            action = 'Home Run';
            break;
        }

        // Set both action and RBI count with validation
        setState(() {
          _selectedVerb = action;
          _selectedActionVerb = action;

          // Limit RBI count based on hit type (max 3 for buttons)
          if ((actionType == 'sin' ||
                  actionType == 'dou' ||
                  actionType == 'tri') &&
              rbiCount > 3) {
            _rbiCount =
                3; // Singles, doubles, and triples can only have up to 3 RBI
          } else if (actionType == 'hr') {
            // Home runs: cap at 3 for button display
            if (rbiCount >= 1 && rbiCount <= 3) {
              _rbiCount = rbiCount; // Show on buttons
            } else {
              _rbiCount =
                  null; // 4+ RBI - no button selected but caption will show correct count
            }
          } else {
            _rbiCount = rbiCount <= 3 ? rbiCount : null; // Default case
          }
        });

        rbiSetByAbbreviation = true; // Mark that RBI was set by abbreviation
        continue;
      }

      // Check for inning number
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }

      // Parse action (same switch statement as in _parseMagicInput)
      switch (part) {
        case 'gs':
          action = 'Home Run';
          setState(() {
            _selectedVerb = action;
            _selectedActionVerb = action;
            _rbiCount =
                null; // Grand slam (4 RBI) - no button selected but caption will show correct count
          });
          break;
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        case 'single':
        case '1b':
          action = 'Single';
          break;
        case 'double':
        case '2b':
          action = 'Double';
          break;
        case 'triple':
        case '3b':
          action = 'Triple';
          break;
        case 'walks':
        case 'walk':
        case 'bb':
          action = 'Walks';
          break;
        case 'strikeout':
        case 'k':
          action = 'Strikeout';
          break;
        case 'steals':
        case 'steal':
        case 'sb':
          action = 'Steals';
          break;
        case 'catches':
        case 'catch':
          action = 'Catches';
          break;
        case 'throws':
        case 'throw':
          action = 'Throws';
          break;
        case 'tags':
        case 'tag':
          action = 'Tags';
          break;
        case 'pitches':
        case 'pitch':
        case 'pitching':
          action = 'Pitching';
          break;
        case 'swings':
        case 'swing':
          action = 'Swings';
          break;
        case 'bunts':
        case 'bunt':
          action = 'Bunts';
          break;
        case 'hbp':
        case 'hitbypitch':
          action = 'Hit by Pitch';
          break;
        case 'sacrificefly':
        case 'sf':
          action = 'Sacrifice Fly';
          break;
        case 'celebrates':
        case 'celebrate':
          action = 'Celebrates';
          break;
        case 'dejection':
        case 'dejected':
          action = 'Dejection';
          break;
        case 'looks':
        case 'look':
          action = 'Looks On';
          break;
        case 'runs':
        case 'run':
          action = 'Runs';
          break;
        case 'slides':
        case 'slide':
          action = 'Slides';
          break;
        case 'rounds':
        case 'round':
          action = 'Rounds';
          break;
        case 'groundball':
        case 'ground':
          action = 'Groundball';
          break;
        case 'doubleplay':
        case 'dp':
          action = 'Double Play';
          break;
        case 'tripleplay':
        case 'tp':
          action = 'Triple Play';
          break;
        case 'atbat':
        case 'at-bat':
        case 'bat':
          action = 'At Bat';
          break;
        case 'fielding':
        case 'field':
          action = 'Fielding Position';
          break;
        case 'warmup':
        case 'warm':
          action = 'Warm Ups';
          break;
        case 'stretching':
        case 'stretch':
          action = 'Stretching';
          break;
        case 'battingpractice':
        case 'bp':
          action = 'Batting Practice';
          break;
        case 'fieldingpractice':
        case 'fp':
          action = 'Fielding Practice';
          break;
        case 'takesthefield':
        case 'takesfield':
          action = 'Takes the Field';
          break;
        case 'comesofffield':
        case 'offfield':
          action = 'Comes Off the Field';
          break;
        case 'nationalanthem':
        case 'anthem':
          action = 'National Anthem';
          break;
        case 'pitchingchange':
        case 'pitchchange':
          action = 'Pitching Change';
          break;
        case 'postgamewin':
        case 'win':
          action = 'Post Game Win';
          break;
        case 'postgameloss':
        case 'loss':
          action = 'Post Game Loss';
          break;
        case 'walksoffield':
        case 'walksoff':
          action = 'Walks Off Field';
          break;
        case 'runsoffield':
        case 'runsoff':
          action = 'Runs Off Field';
          break;
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        // Only set inning if explicitly provided in the input
        // Don't automatically set inning for shortcodes
        if (inning != null) {
          _selectedRbiInning = inning;
        }

        // For shortcodes, interpret trailing numbers as RBI count, not inning
        // This prevents automatic inning writing for shortcodes
        // But only if RBI wasn't already set by abbreviation
        if (!rbiSetByAbbreviation) {
          if (inning != null &&
              (action == 'Home Run' ||
                  action == 'Single' ||
                  action == 'Double' ||
                  action == 'Triple')) {
            _rbiCount = inning; // Use the inning number as RBI count
            // Don't set inning for shortcodes - only set inning if explicitly provided as inning
            // _selectedRbiInning remains null for shortcodes
          } else {
            _rbiCount = null; // Don't set RBI count for solo actions
          }
        }
      });
    }

    // Update caption
    _updateCaption();
  }

  void _processMagicInputWithPlayerKeepBar(
      Player selectedPlayer, String actionText) {
    // Reset only action-related state; keep players and first selection intact
    setState(() {
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;
    });

    // Select the chosen player
    final isHomePlayer = _homeRoster.contains(selectedPlayer);
    setState(() {
      final display = selectedPlayer.displayName ?? 'Unknown Player';
      final cleaned = _removeJerseyNumberFromName(display);
      if (isHomePlayer) {
        selectedHomePlayers.add(display);
        _firstTeamSelected ??= true;
        _firstPlayerSelected ??= cleaned;
      } else {
        selectedAwayPlayers.add(display);
        _firstTeamSelected ??= false;
        _firstPlayerSelected ??= cleaned;
      }
    });

    // Ensure the original main player remains selected in its team list
    _ensureMainPlayerStillSelected();

    // Parse the action text (same as original method)
    final parts = actionText.trim().toLowerCase().split(' ');
    String action = '';
    int? inning;
    bool rbiSetByAbbreviation = false; // Track if RBI was set by abbreviation

    for (final part in parts) {
      // Check for RBI abbreviations first (sin3, dou2, tri4, hr5)
      final rbiMatch = RegExp(r'^(sin|dou|tri|hr)(\d+)$').firstMatch(part);
      print(
          'DEBUG: Checking part "$part" for RBI abbreviation, match: $rbiMatch');
      if (rbiMatch != null) {
        final actionType = rbiMatch.group(1)!;
        final rbiCount = int.parse(rbiMatch.group(2)!);
        print(
            'DEBUG: Found RBI abbreviation - actionType: $actionType, rbiCount: $rbiCount');

        // Set the action based on the abbreviation
        switch (actionType) {
          case 'sin':
            action = 'Single';
            break;
          case 'dou':
            action = 'Double';
            break;
          case 'tri':
            action = 'Triple';
            break;
          case 'hr':
            action = 'Home Run';
            break;
        }

        // Set both action and RBI count with validation
        setState(() {
          _selectedVerb = action;
          _selectedActionVerb = action;

          // Limit RBI count based on hit type (max 3 for buttons)
          if ((actionType == 'sin' ||
                  actionType == 'dou' ||
                  actionType == 'tri') &&
              rbiCount > 3) {
            _rbiCount =
                3; // Singles, doubles, and triples can only have up to 3 RBI
          } else if (actionType == 'hr') {
            // Home runs: cap at 3 for button display
            if (rbiCount >= 1 && rbiCount <= 3) {
              _rbiCount = rbiCount; // Show on buttons
            } else {
              _rbiCount =
                  null; // 4+ RBI - no button selected but caption will show correct count
            }
          } else {
            _rbiCount = rbiCount <= 3 ? rbiCount : null; // Default case
          }
        });

        rbiSetByAbbreviation = true; // Mark that RBI was set by abbreviation
        continue;
      }

      // Check for inning number
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }

      // Parse action (using same switch as original)
      switch (part) {
        case 'gs':
          action = 'Home Run';
          setState(() {
            _selectedVerb = action;
            _selectedActionVerb = action;
            _rbiCount =
                null; // Grand slam (4 RBI) - no button selected but caption will show correct count
          });
          break;
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        case 'single':
        case '1b':
          action = 'Single';
          break;
        case 'double':
        case '2b':
          action = 'Double';
          break;
        case 'triple':
        case '3b':
          action = 'Triple';
          break;
        case 'walks':
        case 'walk':
        case 'bb':
          action = 'Walks';
          break;
        case 'strikeout':
        case 'k':
          action = 'Strikeout';
          break;
        case 'steals':
        case 'steal':
        case 'sb':
          action = 'Steals';
          break;
        case 'catches':
        case 'catch':
          action = 'Catches';
          break;
        case 'throws':
        case 'throw':
          action = 'Throws';
          break;
        case 'tags':
        case 'tag':
          action = 'Tags';
          break;
        case 'pitches':
        case 'pitch':
        case 'pitching':
          action = 'Pitching';
          break;
        case 'swings':
        case 'swing':
          action = 'Swings';
          break;
        case 'bunts':
        case 'bunt':
          action = 'Bunts';
          break;
        case 'hbp':
        case 'hitbypitch':
          action = 'Hit by Pitch';
          break;
        case 'sacrificefly':
        case 'sf':
          action = 'Sacrifice Fly';
          break;
        case 'celebrates':
        case 'celebrate':
          action = 'Celebrates';
          break;
        case 'dejection':
        case 'dejected':
          action = 'Dejection';
          break;
        case 'looks':
        case 'look':
          action = 'Looks On';
          break;
        case 'runs':
        case 'run':
          action = 'Runs';
          break;
        case 'slides':
        case 'slide':
          action = 'Slides';
          break;
        case 'rounds':
        case 'round':
          action = 'Rounds';
          break;
        case 'groundball':
        case 'ground':
          action = 'Groundball';
          break;
        case 'doubleplay':
        case 'dp':
          action = 'Double Play';
          break;
        case 'tripleplay':
        case 'tp':
          action = 'Triple Play';
          break;
        case 'atbat':
        case 'at-bat':
        case 'bat':
          action = 'At Bat';
          break;
        case 'fielding':
        case 'field':
          action = 'Fielding Position';
          break;
        case 'warmup':
        case 'warm':
          action = 'Warm Ups';
          break;
        case 'stretching':
        case 'stretch':
          action = 'Stretching';
          break;
        case 'battingpractice':
        case 'bp':
          action = 'Batting Practice';
          break;
        case 'fieldingpractice':
        case 'fp':
          action = 'Fielding Practice';
          break;
        case 'takesthefield':
        case 'takesfield':
          action = 'Takes the Field';
          break;
        case 'comesofffield':
        case 'offfield':
          action = 'Comes Off the Field';
          break;
        case 'nationalanthem':
        case 'anthem':
          action = 'National Anthem';
          break;
        case 'pitchingchange':
        case 'pitchchange':
          action = 'Pitching Change';
          break;
        case 'postgamewin':
        case 'win':
          action = 'Post Game Win';
          break;
        case 'postgameloss':
        case 'loss':
          action = 'Post Game Loss';
          break;
        case 'walksoffield':
        case 'walksoff':
          action = 'Walks Off Field';
          break;
        case 'runsoffield':
        case 'runsoff':
          action = 'Runs Off Field';
          break;
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        _selectedRbiInning = inning;

        // Only set RBI count if inning is provided
        if (inning != null &&
            (action == 'Home Run' ||
                action == 'Single' ||
                action == 'Double' ||
                action == 'Triple')) {
          _rbiCount = inning;
        } else {
          _rbiCount = null;
        }
      });
    }

    // Update caption but DON'T clear the magic bar
    _updateCaption();
  }

  void _showTeamSelectionDebug(String teamName, bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final teamType = isHome ? 'HOME' : 'AWAY';

    String debugInfo = '=== TEAM SELECTION DEBUG ===\n\n';
    debugInfo += 'TEAM: $teamName ($teamType)\n';
    debugInfo += 'API: ${_apiManager.currentApi}\n';
    debugInfo += 'TOTAL PLAYERS: ${roster.length}\n\n';

    // Add API debugging info
    debugInfo += '=== API DEBUG ===\n';
    debugInfo += 'Current API: ${_apiManager.currentApi}\n';
    debugInfo +=
        'Connection Status: ${_apiManager.getConnectionStatusMessage()}\n\n';

    // Count players with jersey numbers
    int playersWithNumbers = 0;
    int playersWithoutNumbers = 0;

    // Sort roster by jersey number for easier reading
    final sortedRoster = List<Player>.from(roster);
    sortedRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    debugInfo += 'ALL PLAYERS (sorted by jersey number):\n';
    for (final player in sortedRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) {
        playersWithNumbers++;
        debugInfo += '  #${player.jerseyNumber}: ${player.fullName}\n';
      } else {
        playersWithoutNumbers++;
        debugInfo += '  #N/A: ${player.fullName}\n';
      }
    }

    debugInfo += '\n=== SUMMARY ===\n';
    debugInfo += 'Players WITH jersey numbers: $playersWithNumbers\n';
    debugInfo += 'Players WITHOUT jersey numbers: $playersWithoutNumbers\n';
    debugInfo += 'Total players: ${roster.length}\n';

    // Show popup
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Team Selection: $teamName'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Team info copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _debugRosters() {
    String debugInfo = '=== ROSTER DEBUG INFO ===\n\n';

    // API info
    debugInfo += 'CURRENT API: ${_apiManager.currentApi}\n';
    debugInfo += 'API STATUS: ${_apiManager.getConnectionStatusMessage()}\n\n';

    // Home team info
    debugInfo += 'HOME TEAM: ${selectedHomeTeam ?? "Not selected"}\n';
    debugInfo += 'Home roster count: ${_homeRoster.length}\n';
    debugInfo += 'Home players with jersey numbers:\n';

    // Sort home roster by jersey number for easier reading
    final sortedHomeRoster = List<Player>.from(_homeRoster);
    sortedHomeRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    int homePlayersWithNumbers = 0;
    for (final player in sortedHomeRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) homePlayersWithNumbers++;
      debugInfo += '  #${player.jerseyNumber ?? "N/A"}: ${player.fullName}\n';
    }

    debugInfo +=
        '\nHome players WITH jersey numbers: $homePlayersWithNumbers\n';
    debugInfo +=
        'Home players WITHOUT jersey numbers: ${_homeRoster.length - homePlayersWithNumbers}\n';

    debugInfo += '\nAWAY TEAM: ${selectedAwayTeam ?? "Not selected"}\n';
    debugInfo += 'Away roster count: ${_awayRoster.length}\n';
    debugInfo += 'Away players with jersey numbers:\n';

    // Sort away roster by jersey number for easier reading
    final sortedAwayRoster = List<Player>.from(_awayRoster);
    sortedAwayRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    int awayPlayersWithNumbers = 0;
    for (final player in sortedAwayRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) awayPlayersWithNumbers++;
      debugInfo += '  #${player.jerseyNumber ?? "N/A"}: ${player.fullName}\n';
    }

    debugInfo +=
        '\nAway players WITH jersey numbers: $awayPlayersWithNumbers\n';
    debugInfo +=
        'Away players WITHOUT jersey numbers: ${_awayRoster.length - awayPlayersWithNumbers}\n';

    debugInfo += '\n=== END DEBUG INFO ===';

    // Show debug info in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster Debug Info'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Debug info copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _testApiDirectly() async {
    String debugInfo = '=== DIRECT API TEST ===\n\n';

    try {
      debugInfo += 'Testing API: ${_apiManager.currentApi}\n\n';

      // Test fetching all teams
      debugInfo += '1. Testing team fetch...\n';
      final teams = await _apiManager.fetchTeams();
      debugInfo += 'Found ${teams.length} teams\n';
      debugInfo += 'Sample teams:\n';
      for (int i = 0; i < teams.length.clamp(0, 5); i++) {
        debugInfo += '  - ${teams[i].name}\n';
      }

      // Test fetching players for a specific team (Toronto Blue Jays)
      debugInfo += '\n2. Testing player fetch for Toronto Blue Jays...\n';
      try {
        final players = await _apiManager.fetchTeamRoster('Toronto Blue Jays');
        debugInfo += 'Found ${players.length} players for Toronto Blue Jays\n';
        debugInfo += 'Players with jersey numbers:\n';

        int playersWithNumbers = 0;
        for (final player in players) {
          if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
            playersWithNumbers++;
            debugInfo += '  #${player.jerseyNumber}: ${player.fullName}\n';
          }
        }

        debugInfo += '\nSummary for Toronto Blue Jays:\n';
        debugInfo += 'Players WITH jersey numbers: $playersWithNumbers\n';
        debugInfo +=
            'Players WITHOUT jersey numbers: ${players.length - playersWithNumbers}\n';
        debugInfo += 'Total players: ${players.length}\n';

        // Check for player #27 specifically
        final player27 = players.where((p) => p.jerseyNumber == '27').toList();
        if (player27.isNotEmpty) {
          debugInfo += '\nPlayer #27 found: ${player27.first.fullName}\n';
        } else {
          debugInfo += '\nPlayer #27 NOT found in roster\n';
        }
      } catch (e) {
        debugInfo += 'Error fetching Toronto Blue Jays players: $e\n';
      }
    } catch (e) {
      debugInfo += 'Error during API test: $e\n';
    }

    // Show debug info in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Direct API Test Results'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('API test results copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _updateCaption() {
    // Safety check: if either team is not selected, don't try to generate captions
    if (selectedHomeTeam == null || selectedAwayTeam == null) {
      captionController.clear();
      return;
    }

    // Get photo date from metadata, fallback to current date
    DateTime photoDate = DateTime.now();
    if (widget.metadata != null) {
      final dateTimeOriginal = widget.metadata!['DateTimeOriginal']?.toString();
      final createDate = widget.metadata!['CreateDate']?.toString();
      final modifyDate = widget.metadata!['ModifyDate']?.toString();

      // Try to parse the date from EXIF data
      final dateString = dateTimeOriginal ?? createDate ?? modifyDate;
      if (dateString != null && dateString.isNotEmpty) {
        try {
          // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
          final parts = dateString.split(' ');
          if (parts.isNotEmpty) {
            final datePart = parts[0];
            final dateComponents = datePart.split(':');
            if (dateComponents.length >= 3) {
              final year = int.parse(dateComponents[0]);
              final month = int.parse(dateComponents[1]);
              final day = int.parse(dateComponents[2]);
              photoDate = DateTime(year, month, day);
            }
          }
        } catch (e) {
          print('Error parsing photo date: $e');
          // Fallback to current date
        }
      } else {}
    } else {}

    // Get date components
    final city = cityController.text;
    final prov = provinceController.text;
    final monLC = _month(photoDate.month);
    final day = photoDate.day;
    final year = photoDate.year;
    final monthUpper = monLC.toUpperCase();
    final formattedDate = '$monLC $day, $year';
    final dateline = _formatDateline(city, prov, monthUpper, day);
    final locationSuffix = _formatLocationSuffix(city, prov, formattedDate);

    // Determine which team the selected players belong to
    // First player selected = Main focus, opposite team players = always "against"
    Set<String> activePlayers;
    Set<String> opponentPlayers;
    String? opponentTeamName;

    if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
      // Only away team players are selected
      activePlayers = selectedAwayPlayers;
      opponentPlayers = <String>{};
      opponentTeamName = selectedHomeTeam;
    } else if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
      // Only home team players are selected
      activePlayers = selectedHomePlayers;
      opponentPlayers = <String>{};
      opponentTeamName = selectedAwayTeam;
    } else if (selectedHomePlayers.isNotEmpty &&
        selectedAwayPlayers.isNotEmpty) {
      // Both teams have players - use the first team selected as main focus

      if (_firstTeamSelected == true) {
        // Home team was selected first, so they're the main focus

        activePlayers = selectedHomePlayers;
        opponentPlayers = selectedAwayPlayers;
        opponentTeamName = selectedAwayTeam;
      } else if (_firstTeamSelected == false) {
        // Away team was selected first, so they're the main focus

        activePlayers = selectedAwayPlayers;
        opponentPlayers = selectedHomePlayers;
        opponentTeamName = selectedHomeTeam;
      } else {
        // Fallback: if _firstTeamSelected is null, use home team as default

        activePlayers = selectedHomePlayers;
        opponentPlayers = selectedAwayPlayers;
        opponentTeamName = selectedAwayTeam;
      }
    } else {
      // No players selected
      captionController.clear();
      _updatePersonalityField(); // Clear personality field when no players selected
      return;
    }

    if (activePlayers.isEmpty) {
      captionController.clear();
      return;
    }

    // Get the verb to use for player formatting
    final verbToUse = _selectedActionVerb ?? _selectedVerb;

    // Format the main player(s)
    String playerName;

    if ((_selectedHittingAction == 'celebrates' ||
            _selectedHittingAction == 'celebrates_in_dugout' ||
            verbToUse == 'Celebration' ||
            verbToUse == 'Celebrates' ||
            verbToUse == 'Celebrates With' ||
            verbToUse == 'Celebrates Against') &&
        _firstPlayerSelected != null) {
      // For celebration actions, check if "with teammates" is selected OR if we're in a hit interface OR celebration interface with multiple players
      final isHitInterface = (verbToUse == 'Single' ||
          verbToUse == 'Double' ||
          verbToUse == 'Triple' ||
          verbToUse == 'Home Run' ||
          verbToUse == 'Grand Slam');
      final isCelebrationInterface = (verbToUse == 'Celebration' ||
          verbToUse == 'Celebrates' ||
          verbToUse == 'Celebrates With' ||
          verbToUse == 'Celebrates Against');
      final hasMultiplePlayers = activePlayers.length > 1;

      // print(
      //     'DEBUG: _isCelebratingWithTeammates = $_isCelebratingWithTeammates');
      // print(
      //     'DEBUG: isHitInterface = $isHitInterface, isCelebrationInterface = $isCelebrationInterface, hasMultiplePlayers = $hasMultiplePlayers');

      if (_isCelebratingWithTeammates ||
          (isHitInterface && hasMultiplePlayers) ||
          (isCelebrationInterface && hasMultiplePlayers)) {
        // If "with teammates" is selected OR we're in a hit interface with multiple players, only use the main player
        final mainPlayerTeam =
            selectedHomePlayers.contains(_firstPlayerSelected)
                ? selectedHomeTeam
                : selectedAwayTeam;
        playerName = '$_firstPlayerSelected of the $mainPlayerTeam';
      } else {
        // If "with teammates" is NOT selected and not a multi-player hit interface, use all active players
        playerName = _combinePlayersWithSingleTeam(activePlayers.toList());
      }
    } else {
      // For Pitching Change, don't set playerName since it's handled in actionPhrase
      if (verbToUse == 'Pitching Change') {
        playerName = '';
      } else {
        // For other actions, use all active players
        playerName = _combinePlayersWithSingleTeam(activePlayers.toList());
      }
    }

    // Build the action phrase based on selected verb
    String actionPhrase = '';

    final verbForAction = _selectedActionVerb ?? _selectedVerb;
    if (verbForAction != null) {
      actionPhrase = _buildActionPhrase();
    }

    // Handle opponent players if selected
    String opponentPart = '';
    if (actionPhrase.contains('against') ||
        _selectedHittingAction == 'celebrates' ||
        _selectedHittingAction == 'celebrates_in_dugout' ||
        _selectedHittingAction == 'trots_the_bases' ||
        verbToUse == 'At Bat' ||
        verbToUse == 'Pitching' ||
        verbToUse == 'Swings' ||
        verbToUse == 'Fielding Position' ||
        verbToUse == 'Catches' ||
        verbToUse == 'Throws' ||
        verbToUse == 'Tags' ||
        verbToUse == 'Groundball' ||
        verbToUse == 'Steals' ||
        verbToUse == 'Slides' ||
        verbToUse == 'Runs' ||
        verbToUse == 'Rounds' ||
        verbToUse == 'Double Play' ||
        verbToUse == 'Triple Play' ||
        verbToUse == 'Celebration' ||
        verbToUse == 'Celebrates' ||
        verbToUse == 'Celebrates With' ||
        verbToUse == 'Celebrates Against' ||
        verbToUse == 'Walks' ||
        verbToUse == 'Dejection' ||
        verbToUse == 'Looks On' ||
        verbToUse == 'Walks Off Field' ||
        verbToUse == 'Runs Off Field' ||
        verbToUse == 'Takes the Field' ||
        verbToUse == 'Comes Off the Field' ||
        verbToUse == 'National Anthem' ||
        verbToUse == 'Post Game Win' ||
        verbToUse == 'Post Game Loss' ||
        verbToUse == 'Batting Practice' ||
        verbToUse == 'Fielding Practice' ||
        verbToUse == 'Warm Ups' ||
        verbToUse == 'Walks On Field' ||
        verbToUse == 'Runs On Field' ||
        verbToUse == 'Stretching' ||
        verbToUse == 'Pitching Change' ||
        customCelebrationController.text.isNotEmpty ||
        customDejectionController.text.isNotEmpty) {
      // For these actions, don't add opponent part here - it's handled in the action phrase
      opponentPart = '';
    } else {
      // For other actions, include specific players if selected
      if (opponentPlayers.isNotEmpty) {
        final opponentNames =
            _combinePlayersWithSingleTeam(opponentPlayers.toList());
        opponentPart = ' against $opponentNames';
      } else if (opponentTeamName != null) {
        opponentPart = ' against the $opponentTeamName';
      }
    }

    // Add inning if specified (but not for post-game verbs or Pitching Change)
    String inningPart = '';
    final isPostGameVerb =
        _selectedVerb == 'Post Game Win' || _selectedVerb == 'Post Game Loss';
    final isPitchingChange = _selectedVerb == 'Pitching Change';

    if (!isPostGameVerb && !isPitchingChange) {
      if (_selectedRbiInning != null) {
        inningPart =
            ' during the ${_getOrdinalSuffix(_selectedRbiInning!)} inning';
      } else if (_isPriorToGame) {
        inningPart = ' prior to the game';
      }
      // Note: _isPriorToGame is handled separately in the gamePart logic
    }

    // Use home team stadium from API, fallback to controller if not available
    final stadium = homeTeamStadium ?? stadiumController.text;
    // Get creator and credit from metadata widget or use default
    final creatorValue = widget.metadata?['Creator'];
    final creditValue = widget.metadata?['Credit'];
    String photoBy;
    if (creatorValue is List) {
      // If it's a list, take the first value only
      photoBy = creatorValue.isNotEmpty
          ? creatorValue.first.toString()
          : 'Mark Blinch';
    } else {
      photoBy = creatorValue?.toString() ?? 'Mark Blinch';
    }

    // Build the byline with Getty Images style
    String byline;
    if (creditValue != null && creditValue.toString().isNotEmpty) {
      byline = 'Photo by $photoBy/$creditValue';
    } else {
      byline = 'Photo by $photoBy/Getty Images';
    }

    // Add custom text between players if provided (but not magic input)
    String customTextPart = '';
    // Magic bar removed: no custom text part from magic bar
    if (false) {
      customTextPart = '';
    }

    // Build the final caption
    String gamePart;
    String opponentPartModified;

    if (_isPriorToGame) {
      gamePart = 'in their MLB game';
      // For "prior to game", we need to extract just the team name from opponentPart
      String teamName = '';
      if (opponentPart.contains('against the ')) {
        teamName = opponentPart.replaceAll(' against the ', '');
      } else if (opponentPart.contains('against ')) {
        teamName = opponentPart.replaceAll(' against ', '');
      }

      // If teamName is empty, try to get it from the opponent team
      if (teamName.isEmpty && opponentTeamName != null) {
        teamName = opponentTeamName;
      }

      // Check if action phrase already contains "against" or "playing" to avoid duplication
      if (actionPhrase.contains('against') ||
          actionPhrase.contains('playing')) {
        opponentPartModified = ' prior to play';
      } else {
        opponentPartModified = ' prior to play against the $teamName';
      }
    } else {
      gamePart = 'in their MLB game';
      opponentPartModified = opponentPart;
    }

    final caption = '$dateline '
        '$playerName$customTextPart${actionPhrase.isNotEmpty ? ' $actionPhrase' : ''}$opponentPartModified${_isPriorToGame ? '' : inningPart} '
        '$gamePart at $stadium on $formattedDate $locationSuffix. ($byline)';

    // Set caption text directly (no diacritic removal)
    captionController.text = caption;

    // Update personality field with all selected players (always call to handle empty case)
    _updatePersonalityField();
  }

  Future<void> _onFtpPressed() async {
    // Save IPTC metadata before uploading
    if (widget.onSaveIptc != null) {
      await widget.onSaveIptc!();
    }

    // Check if FTP settings are configured
    if (_ftpHost.isEmpty || _ftpUsername.isEmpty || _ftpPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure FTP settings first!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Check if an image is selected
    print('DEBUG: FTP Upload - currentImagePath: "${widget.currentImagePath}"');
    print(
        'DEBUG: FTP Upload - currentImagePath is null: ${widget.currentImagePath == null}');
    print(
        'DEBUG: FTP Upload - currentImagePath is empty: ${widget.currentImagePath?.isEmpty}');

    if (widget.currentImagePath == null || widget.currentImagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Use original filename
    final originalFileName = p.basename(widget.currentImagePath!);
    final remoteFileName = originalFileName;

    // Build full remote path
    final fullRemotePath = _ftpRemotePath.isNotEmpty
        ? '${_ftpRemotePath.endsWith('/') ? _ftpRemotePath : '$_ftpRemotePath/'}$remoteFileName'
        : remoteFileName;

    print('FTP: Generated remote filename: $remoteFileName');
    print('FTP: Remote path: $_ftpRemotePath');
    print('FTP: Full remote path: $fullRemotePath');

    // Progress will be shown over the thumbnail instead of a dialog
    String statusText = 'Connecting to FTP server...';
    String? errorText;

    try {
      // Folder watching disabled - no need to signal

      final result = await FtpClientService.uploadFile(
        host: _ftpHost,
        username: _ftpUsername,
        password: _ftpPassword,
        localFilePath: widget.currentImagePath!,
        remoteFilePath: fullRemotePath,
        port: _ftpPort,
        passiveMode: _ftpPassiveMode,
        onProgress: (status, progress, error) {
          statusText = status;
          errorText = error;
          // Notify parent about upload progress for overlay
          if (widget.onUploadProgress != null &&
              widget.currentImagePath != null) {
            widget.onUploadProgress!(widget.currentImagePath!, progress);
          }
        },
      );

      if (result.success) {
        setState(() {
          // No need to increment picture number when using original filenames
        });

        // Notify parent that image was uploaded successfully
        if (widget.onImageUploaded != null && widget.currentImagePath != null) {
          widget.onImageUploaded!(widget.currentImagePath!);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully uploaded: $remoteFileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${result.error}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // Folder picking functionality
  Future<void> _pickFolder() async {
    print('Starting folder picker...');
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) {
      print('No folder selected');
      return;
    }

    print('Selected folder: $dirPath');

    // List image files
    final files = await _listImageFiles(dirPath);

    if (files.isNotEmpty) {
      // Notify parent about loaded images
      if (widget.onImagesLoaded != null) {
        widget.onImagesLoaded!(files);
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded ${files.length} images from folder'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Test API connection
  Future<bool> _testApiConnection() async {
    try {
      final teams = await _apiManager.fetchTeams();
      return teams.isNotEmpty;
    } catch (e) {
      print('Error testing API connection: $e');
      return false;
    }
  }

  // Helper method to list image files
  Future<List<String>> _listImageFiles(String dirPath) async {
    try {
      final directory = Directory(dirPath);
      final files = directory.listSync();

      final imageExtensions = [
        '.jpg',
        '.jpeg',
        '.png',
        '.tiff',
        '.bmp',
        '.JPG',
        '.JPEG',
        '.PNG',
        '.TIFF',
        '.BMP'
      ];

      final imageFiles = files
          .where((file) {
            if (file is! File) return false;

            final path = file.path;
            final extension = path.split('.').last.toLowerCase();
            return imageExtensions.contains('.$extension');
          })
          .map((file) => file.path)
          .toList();

      // Sort files by date taken (DateTimeOriginal from EXIF)
      await _sortImagesByDateTaken(imageFiles);

      return imageFiles;
    } catch (e) {
      print('Error listing image files: $e');
      return [];
    }
  }

  // Sort images by date taken from EXIF DateTimeOriginal
  Future<void> _sortImagesByDateTaken(List<String> imageFiles) async {
    print('Sorting ${imageFiles.length} images by date taken...');

    // Create a list of maps with file path and date taken
    List<Map<String, dynamic>> filesWithDates = [];

    for (String filePath in imageFiles) {
      try {
        final proc = await Process.run('exiftool', [
          '-j',
          '-DateTimeOriginal',
          '-CreateDate',
          '-ModifyDate',
          filePath,
        ]);

        DateTime? dateTime;
        if (proc.exitCode == 0) {
          final List data = jsonDecode(proc.stdout as String);
          if (data.isNotEmpty) {
            final meta = data.first as Map<String, dynamic>;
            String? dateStr = meta['DateTimeOriginal']?.toString() ??
                meta['CreateDate']?.toString() ??
                meta['ModifyDate']?.toString();

            if (dateStr != null) {
              try {
                // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
                dateTime = DateTime.parse(
                    dateStr.replaceFirst(':', '-').replaceFirst(':', '-'));
              } catch (e) {
                print('Error parsing date for $filePath: $e');
              }
            }
          }
        }

        // If no EXIF date found, use file modification date as fallback
        if (dateTime == null) {
          try {
            final file = File(filePath);
            dateTime = await file.lastModified();
          } catch (e) {
            print('Error getting file date for $filePath: $e');
            dateTime = DateTime.now(); // Ultimate fallback
          }
        }

        filesWithDates.add({
          'path': filePath,
          'date': dateTime,
        });
      } catch (e) {
        print('Error processing $filePath: $e');
        // Add file with current date as fallback
        filesWithDates.add({
          'path': filePath,
          'date': DateTime.now(),
        });
      }
    }

    // Sort by date (earliest to latest)
    filesWithDates.sort((a, b) => a['date'].compareTo(b['date']));

    // Update the imageFiles list with sorted paths
    imageFiles.clear();
    imageFiles.addAll(filesWithDates.map((item) => item['path'] as String));

    print('Images sorted by date taken (earliest to latest)');
  }

  void _updatePersonalityField() {
    // Combine all selected players from both teams
    final allSelectedPlayers = <String>[];
    allSelectedPlayers.addAll(selectedHomePlayers);
    allSelectedPlayers.addAll(selectedAwayPlayers);

    // If no players are selected, clear the personality field
    if (allSelectedPlayers.isEmpty) {
      personalityController.text = '';
      return;
    }

    // Remove jersey numbers and # symbols from player names
    final cleanPlayerNames = allSelectedPlayers.map((playerName) {
      // Remove numbers, # symbols, and extra spaces, keep only the name
      return playerName.replaceAll(RegExp(r'\s*[#\d]+\s*'), '').trim();
    }).toList();

    // Add manager name if available and Pitching Change is selected
    if (_selectedVerb == 'Pitching Change' && _managerName.isNotEmpty) {
      cleanPlayerNames.add(_managerName);
    }

    // Join players with semicolons, no semicolon after the last player
    final personalityText = cleanPlayerNames.join(';');

    // Update the personality field directly (no diacritic removal)
    personalityController.text = personalityText;
  }

  String _getTeamAbbreviation(String teamName) {
    // Map of full team names to their abbreviations
    const Map<String, String> teamAbbreviations = {
      'Arizona Diamondbacks': 'ARI',
      'Atlanta Braves': 'ATL',
      'Baltimore Orioles': 'BAL',
      'Boston Red Sox': 'BOS',
      'Chicago Cubs': 'CHC',
      'Chicago White Sox': 'CWS',
      'Cincinnati Reds': 'CIN',
      'Cleveland Guardians': 'CLE',
      'Colorado Rockies': 'COL',
      'Detroit Tigers': 'DET',
      'Houston Astros': 'HOU',
      'Kansas City Royals': 'KC',
      'Los Angeles Angels': 'LAA',
      'Los Angeles Dodgers': 'LAD',
      'Miami Marlins': 'MIA',
      'Milwaukee Brewers': 'MIL',
      'Minnesota Twins': 'MIN',
      'New York Mets': 'NYM',
      'New York Yankees': 'NYY',
      'Oakland Athletics': 'OAK',
      'Philadelphia Phillies': 'PHI',
      'Pittsburgh Pirates': 'PIT',
      'San Diego Padres': 'SD',
      'San Francisco Giants': 'SF',
      'Seattle Mariners': 'SEA',
      'St. Louis Cardinals': 'STL',
      'Tampa Bay Rays': 'TB',
      'Texas Rangers': 'TEX',
      'Toronto Blue Jays': 'TOR',
      'Washington Nationals': 'WSH',
    };

    final abbreviation = teamAbbreviations[teamName];
    // print('DEBUG: Converting team name "$teamName" to abbreviation: "$abbreviation"');
    return abbreviation ?? teamName;
  }

  Widget _buildPlayerChip(String playerName, bool isHome) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHome ? Colors.blue.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHome ? Colors.blue.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatChipName(playerName),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isHome ? Colors.blue.shade700 : Colors.orange.shade700,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() {
                // Check if this is the first selected player (main player)
                final isMainPlayer = _isFirstSelectedPlayer(playerName);

                if (isHome) {
                  selectedHomePlayers.remove(playerName);
                } else {
                  selectedAwayPlayers.remove(playerName);
                }

                // If removing the main player, reset everything
                if (isMainPlayer) {
                  _resetCaption();
                  return; // _resetCaption already calls _updateCaption and _updatePersonalityField
                }
              });
              _updateCaption();
              _updatePersonalityField();
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isHome ? Colors.blue.shade200 : Colors.orange.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                size: 10,
                color: isHome ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCaptionVerbPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Action Verb'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView(
            children: verbCategories.entries.map((category) {
              return ExpansionTile(
                title: Text(
                  category.key,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                children: category.value.map((verb) {
                  return ListTile(
                    title: Text(verb),
                    onTap: () {
                      setState(() {
                        selectedCaptionVerb = verb;
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPlayerSelectionDialog(bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final selectedPlayers = isHome ? selectedHomePlayers : selectedAwayPlayers;
    final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${teamName ?? 'Team'} Players'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: roster.isEmpty
              ? const Center(
                  child: Text('No players available'),
                )
              : ListView.builder(
                  itemCount: roster.length,
                  itemBuilder: (context, index) {
                    final player = roster[index];
                    final isSelected =
                        selectedPlayers.contains(player.displayName);

                    return CheckboxListTile(
                      title: Text(
                        player.displayName,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Position: Unknown', // Could add position data later
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            // Track which team was selected first
                            if (_firstTeamSelected == null) {
                              _firstTeamSelected = isHome;
                              _firstPlayerSelected =
                                  _removeJerseyNumberFromName(
                                      player.displayName);
                              // print(
                              //     'DEBUG: First team selected (dialog): ${isHome ? "HOME" : "AWAY"}');
                              // print(
                              //     'DEBUG: First player selected (dialog): ${player.displayName}');
                            } else {}
                            if (isHome) {
                              selectedHomePlayers.add(player.displayName);
                            } else {
                              selectedAwayPlayers.add(player.displayName);
                            }
                          } else {
                            if (isHome) {
                              selectedHomePlayers.remove(player.displayName);
                            } else {
                              selectedAwayPlayers.remove(player.displayName);
                            }
                          }
                        });
                        _updateCaption();
                        Navigator.of(context).pop();
                      },
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerbSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: const Text(
            'Verb Selection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Verb categories
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: verbCategories.entries.map((category) {
            return FilterChip(
              label: Text(
                category.key,
                style: const TextStyle(fontSize: 9),
              ),
              selected: _selectedVerb != null &&
                  category.value.contains(_selectedVerb),
              onSelected: (_) => _showVerbPicker(category.key),
              backgroundColor: Colors.grey.shade100,
              selectedColor: Colors.blue.shade100,
              checkmarkColor: Colors.blue.shade700,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        // Selected verb display
        if (_selectedVerb != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 12, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Selected: $_selectedVerb',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVerb = null;
                      _clearVerbSubSelections();
                    });
                  },
                  child: const Icon(Icons.close, size: 12, color: Colors.blue),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Prev button
            CustomButton(
              onTap: () async {
                if (widget.onSaveIptc != null) {
                  await widget.onSaveIptc!();
                }
                widget.onPreviousImage?.call();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Prev',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Copy button
            CustomButton(
              onTap: () {
                _copyMetadataFromCaptionWidget();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Paste button
            CustomButton(
              onTap: _pasteMetadataToCaptionWidget,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Paste',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Next button
            CustomButton(
              onTap: () async {
                if (widget.onSaveIptc != null) {
                  await widget.onSaveIptc!();
                }
                widget.onNextImage?.call();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _onFtpPressed,
                icon: const Icon(Icons.rocket_launch, size: 14),
                label: const Text('FTP Upload', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _showFtpSettings,
                icon: const Icon(Icons.settings, size: 18),
                label:
                    const Text('FTP Settings', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()), // Empty space for alignment
          ],
        ),
      ],
    );
  }

  void _showVerbPicker(String category) {
    final verbs = verbCategories[category] ?? [];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select $category Verb'),
        content: SizedBox(
          width: 200,
          height: 200,
          child: ListView.builder(
            itemCount: verbs.length,
            itemBuilder: (context, index) {
              final verb = verbs[index];
              return ListTile(
                title: Text(verb),
                onTap: () {
                  setState(() {
                    _selectedVerb = verb;
                    _selectedActionVerb = verb; // Store for caption generation
                    _clearVerbSubSelections();
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _clearVerbSubSelections() {
    _selectedHomeRunType = null;
    _rbiCount = null;
    _isBatterRunning = false;
    _isSliding = false;
    _showFieldingOptions = false;
    _selectedFieldingAction = null;
    _selectedBaseRunningAction = null;
    _selectedStealBase = null;
    _showStealAgainstPlayer = false;
    _isSoloCelebration = false;
    celebrateWith.clear();
    celebrateAgainst.clear();
    _selectedCelebrationType = null;
    _selectedAtBatAction = null;
    _selectedBattingAction = null;
  }

  void _onCopyPressed() {
    final captionText = captionController.text;
    final personalityText = personalityController.text;

    String clipboardText = captionText;
    if (personalityText.isNotEmpty) {
      clipboardText += '\n\nPERSONALITY:\n$personalityText';
    }

    Clipboard.setData(ClipboardData(text: clipboardText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caption and personality copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onPastePressed() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      final text = clipboardData.text!;

      // Try to parse caption and personality
      if (text.contains('PERSONALITY:')) {
        final parts = text.split('PERSONALITY:');
        captionController.text = parts[0].trim();
        if (parts.length > 1) {
          personalityController.text = parts[1].trim();
        }
      } else {
        captionController.text = text;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Content pasted from clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Copy metadata from caption widget (excluding date/time)
  void _copyMetadataFromCaptionWidget() {
    print('=== COPY FUNCTION CALLED ===');

    // Build complete metadata from all sources
    final allMetadata = <String, String>{};

    // Add metadata from widget if available
    if (widget.metadata != null) {
      // Convert all values to strings to handle int/string mixed types
      widget.metadata!.forEach((key, value) {
        if (value is String) {
          allMetadata[key] = value;
        } else if (value is List) {
          // For Keywords field, preserve commas; for other fields, use semicolons
          if (key == 'Keywords') {
            allMetadata[key] = value.join(', ');
          } else {
            allMetadata[key] = value.join(';');
          }
        } else if (value != null) {
          allMetadata[key] = value.toString();
        } else {
          allMetadata[key] = '';
        }
      });
    }

    // Add caption fields from controllers
    allMetadata['Caption-Abstract'] = captionController.text;
    allMetadata['XMP:Description'] = captionController.text;
    allMetadata['ImageDescription'] = captionController.text;
    allMetadata['XMP-getty:Personality'] = personalityController.text;
    allMetadata['Sub-location'] = stadiumController.text;
    allMetadata['City'] = cityController.text;
    allMetadata['Province-State'] = provinceController.text;

    print(
        'DEBUG: personalityController.text = "${personalityController.text}"');
    print(
        'DEBUG: allMetadata["XMP-getty:Personality"] = "${allMetadata['XMP-getty:Personality']}"');
    print(
        'DEBUG: personalityController.text length: ${personalityController.text.length}');
    print(
        'DEBUG: personalityController.text isEmpty: ${personalityController.text.isEmpty}');

    print('DEBUG: All metadata before filtering: $allMetadata');

    // Remove date and time fields
    allMetadata.remove('Date');
    allMetadata.remove('Time');
    allMetadata.remove('DateTimeOriginal');
    allMetadata.remove('CreateDate');
    allMetadata.remove('ModifyDate');

    print('DEBUG: Metadata after filtering: $allMetadata');

    final jsonString = jsonEncode(allMetadata);
    print('DEBUG: JSON being copied: ${jsonString.substring(0, 200)}...');

    Clipboard.setData(ClipboardData(text: jsonString));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Metadata copied (${allMetadata.length} fields)!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Paste metadata to caption widget (excluding date/time)
  Future<void> _pasteMetadataToCaptionWidget() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);

      if (clipboardData != null && clipboardData.text != null) {
        final Map<String, dynamic> metadataMap =
            jsonDecode(clipboardData.text!);

        // Update the metadata in the parent widget
        if (widget.onMetadataUpdated != null) {
          final updatedMetadata =
              Map<String, dynamic>.from(widget.metadata ?? {});

          // Apply all fields except date and time
          if (metadataMap['TransmissionReference'] != null) {
            updatedMetadata['TransmissionReference'] =
                metadataMap['TransmissionReference'].toString();
          }
          if (metadataMap['CaptionWriter'] != null) {
            updatedMetadata['CaptionWriter'] =
                metadataMap['CaptionWriter'].toString();
          }
          if (metadataMap['Headline'] != null) {
            updatedMetadata['Headline'] = metadataMap['Headline'].toString();
          }
          if (metadataMap['Keywords'] != null) {
            updatedMetadata['Keywords'] = metadataMap['Keywords'].toString();
          }

          if (metadataMap['AuthorsPosition'] != null) {
            updatedMetadata['AuthorsPosition'] =
                metadataMap['AuthorsPosition'].toString();
          }
          if (metadataMap['Credit'] != null) {
            updatedMetadata['Credit'] = metadataMap['Credit'].toString();
          }
          if (metadataMap['Copyright'] != null) {
            updatedMetadata['Copyright'] = metadataMap['Copyright'].toString();
          }
          if (metadataMap['Source'] != null) {
            updatedMetadata['Source'] = metadataMap['Source'].toString();
          }
          if (metadataMap['Urgency'] != null) {
            updatedMetadata['Urgency'] = metadataMap['Urgency'].toString();
          }
          if (metadataMap['Country'] != null) {
            updatedMetadata['Country'] = metadataMap['Country'].toString();
          }
          if (metadataMap['CountryCode'] != null) {
            updatedMetadata['CountryCode'] =
                metadataMap['CountryCode'].toString();
          }
          if (metadataMap['Sub-location'] != null) {
            final stadiumValue = metadataMap['Sub-location'].toString();
            updatedMetadata['Sub-location'] = stadiumValue;
            // Update the stadium controller directly
            stadiumController.text = stadiumValue;
          }
          if (metadataMap['City'] != null) {
            final cityValue = metadataMap['City'].toString();
            updatedMetadata['City'] = cityValue;
            // Update the city controller directly
            cityController.text = cityValue;
          }
          if (metadataMap['Province-State'] != null) {
            final provinceValue = metadataMap['Province-State'].toString();
            updatedMetadata['Province-State'] = provinceValue;
            // Update the province controller directly
            provinceController.text = provinceValue;
          }
          if (metadataMap['ObjectName'] != null) {
            updatedMetadata['ObjectName'] =
                metadataMap['ObjectName'].toString();
          }
          if (metadataMap['Category'] != null) {
            updatedMetadata['Category'] = metadataMap['Category'].toString();
          }
          if (metadataMap['SupplementalCategories1'] != null) {
            updatedMetadata['SupplementalCategories1'] =
                metadataMap['SupplementalCategories1'].toString();
          }
          if (metadataMap['SupplementalCategories2'] != null) {
            updatedMetadata['SupplementalCategories2'] =
                metadataMap['SupplementalCategories2'].toString();
          }
          if (metadataMap['SupplementalCategories3'] != null) {
            updatedMetadata['SupplementalCategories3'] =
                metadataMap['SupplementalCategories3'].toString();
          }
          if (metadataMap['SpecialInstructions'] != null) {
            updatedMetadata['SpecialInstructions'] =
                metadataMap['SpecialInstructions'].toString();
          }

          // Caption and personality fields
          if (metadataMap['Caption-Abstract'] != null) {
            final captionValue = metadataMap['Caption-Abstract'].toString();
            updatedMetadata['Caption-Abstract'] = captionValue;
            // Update the caption controller directly
            captionController.text = captionValue;
          }
          if (metadataMap['XMP:Description'] != null) {
            updatedMetadata['XMP:Description'] =
                metadataMap['XMP:Description'].toString();
          }
          if (metadataMap['ImageDescription'] != null) {
            updatedMetadata['ImageDescription'] =
                metadataMap['ImageDescription'].toString();
          }
          if (metadataMap['XMP-getty:Personality'] != null) {
            final personalityValue =
                metadataMap['XMP-getty:Personality'].toString();
            updatedMetadata['XMP-getty:Personality'] = personalityValue;
            // Update the personality controller directly
            personalityController.text = personalityValue;
            print('DEBUG: Pasting personality value: "$personalityValue"');
            print(
                'DEBUG: Updated personalityController.text to: "${personalityController.text}"');
          } else {
            print('DEBUG: No XMP-getty:Personality found in metadataMap');
            print(
                'DEBUG: Available keys in metadataMap: ${metadataMap.keys.toList()}');
          }

          // Date and time are intentionally NOT pasted

          widget.onMetadataUpdated!(updatedMetadata);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metadata pasted (date/time preserved)!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error pasting metadata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pasting metadata: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetCaption() {
    setState(() {
      captionController.clear();
      personalityController.clear();
      customCelebrationController.clear();
      // Magic bar removed
      _homeSearchController.clear();
      _awaySearchController.clear();
      _showCustomTextInningSelector = false;

      // Reset all verb-related state
      _selectedVerb = null;
      _selectedActionVerb = null; // Clear action verb
      _selectedHittingAction = null;
      _selectedHomeRunType = null;
      _selectedTagsAction = null; // Clear tags action
      _selectedBase = null; // Clear selected base
      _selectedFieldingAction = null;
      _selectedBaseRunningAction = null;
      _selectedStealBase = null;
      _selectedCelebrationType = null;
      _isCelebratingScoring = false; // Reset scoring celebration selection
      _isCelebratingWithTeammates =
          false; // Reset teammates celebration selection
      _selectedAtBatAction = null;
      _selectedBattingAction = null;
      _selectedRbiInning = null;

      // Reset other verb-related state
      _rbiCount = null;
      _isBatterRunning = false;
      _isSliding = false;
      _showFieldingOptions = false;
      _showStealAgainstPlayer = false;
      _isSoloCelebration = false;
      _isDivingCatch = false;
      _walkOff = false;
      _showExtraInnings = false;
      _extraInningsPage = 0;
      _isPriorToGame = false; // Reset "prior to the game" selection

      // Clear collections
      celebrateWith.clear();
      celebrateAgainst.clear();

      // Clear per-hit-type selections
      _rbiCountByHit.clear();
      _homeRunTypeByHit.clear();
      _inningByHit.clear();
      _batterRunningByHit.clear();

      _clearVerbSubSelections();
      // Don't clear player selections when resetting caption
      // This preserves multi-player selections when using magic bar
      // _firstTeamSelected = null;
      // _firstPlayerSelected = null;
      // selectedHomePlayers.clear();
      // selectedAwayPlayers.clear();

      // Clear magic input related state
      _isPlayerSearchMode = true;
      _filteredPlayers.clear();
      _selectedPlayerNumbers.clear();
      _playerSearchText = '';
      _noPlayersFound = false;
      _homeSearchText = '';
      _awaySearchText = '';

      // Clear magic input player selection state
      _showMagicInputPlayerOptions = false;
      _magicInputMatchingPlayers.clear();
      _magicInputActionText = '';
      _waitingForHomeVisitorChoice = false;

      // Don't clear custom text or magic bar text for multiple player selection
      // customBetweenPlayersController.clear();
    });

    // Update the UI
    _updateCaption();
    _updatePersonalityField();
  }

  void _fullReset() {
    setState(() {
      captionController.clear();
      personalityController.clear();
      customCelebrationController.clear();
      // Magic bar removed
      _homeSearchController.clear();
      _awaySearchController.clear();
      _showCustomTextInningSelector = false;

      // Reset all verb-related state
      _selectedVerb = null;
      _selectedActionVerb = null; // Clear action verb
      _selectedHittingAction = null;
      _selectedHomeRunType = null;
      _selectedTagsAction = null; // Clear tags action
      _selectedBase = null; // Clear selected base
      _selectedFieldingAction = null;
      _selectedBaseRunningAction = null;
      _selectedStealBase = null;
      _selectedCelebrationType = null;
      _isCelebratingScoring = false; // Reset scoring celebration selection
      _isCelebratingWithTeammates =
          false; // Reset teammates celebration selection
      _selectedAtBatAction = null;
      _selectedBattingAction = null;
      _selectedRbiInning = null;

      // Reset other verb-related state
      _rbiCount = null;
      _isBatterRunning = false;
      _isSliding = false;
      _showFieldingOptions = false;
      _showStealAgainstPlayer = false;
      _isSoloCelebration = false;
      _isDivingCatch = false;
      _walkOff = false;
      _showExtraInnings = false;
      _extraInningsPage = 0;
      _isPriorToGame = false; // Reset "prior to the game" selection

      // Clear collections
      celebrateWith.clear();
      celebrateAgainst.clear();

      // Clear per-hit-type selections
      _rbiCountByHit.clear();
      _homeRunTypeByHit.clear();
      _inningByHit.clear();
      _batterRunningByHit.clear();

      _clearVerbSubSelections();
      // Clear player selections for full reset
      _firstTeamSelected = null;
      _firstPlayerSelected = null;
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();

      // Clear magic input related state
      _isPlayerSearchMode = true;
      _filteredPlayers.clear();
      _selectedPlayerNumbers.clear();
      _playerSearchText = '';
      _noPlayersFound = false;
      _homeSearchText = '';
      _awaySearchText = '';

      // Clear magic input player selection state
      _showMagicInputPlayerOptions = false;
      _magicInputMatchingPlayers.clear();
      _magicInputActionText = '';
      _waitingForHomeVisitorChoice = false;

      // Clear custom text and magic bar text for full reset
      customBetweenPlayersController.clear();
      _magicBarController.clear();
      _magicBarVerbInput = '';
      _typingFirstMagicToken = false;
    });

    // Update the UI
    _updateCaption();
    _updatePersonalityField();

    if (widget.onReset != null) widget.onReset!();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caption fields reset!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // FTP Profile Management Methods
  void _saveFtpProfile(
    String profileName, {
    String? host,
    String? username,
    String? password,
    int? port,
    String? remotePath,
    bool? passiveMode,
  }) {
    // Use provided values or fall back to current state values
    final profileData = {
      'host': host ?? _ftpHost,
      'username': username ?? _ftpUsername,
      'password': password ?? _ftpPassword,
      'port': port ?? _ftpPort,
      'remotePath': remotePath ?? _ftpRemotePath,
      'passiveMode': passiveMode ?? _ftpPassiveMode,
    };

    setState(() {
      _ftpProfiles[profileName] = profileData;
      _currentFtpProfile = profileName;

      // Update current state with the saved values
      _ftpHost = profileData['host'] as String;
      _ftpUsername = profileData['username'] as String;
      _ftpPassword = profileData['password'] as String;
      _ftpPort = profileData['port'] as int;
      _ftpRemotePath = profileData['remotePath'] as String;
      _ftpPassiveMode = profileData['passiveMode'] as bool;
    });

    // Save to persistent storage
    _saveFtpProfilesToStorage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FTP profile "$profileName" saved successfully!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _loadFtpProfile(String profileName) {
    final profile = _ftpProfiles[profileName];
    if (profile != null) {
      setState(() {
        _ftpHost = profile['host'] ?? '';
        _ftpUsername = profile['username'] ?? '';
        _ftpPassword = profile['password'] ?? '';
        _ftpPort = profile['port'] ?? 21;
        _ftpRemotePath = profile['remotePath'] ?? '';
        _ftpPassiveMode = profile['passiveMode'] ?? true;
        _currentFtpProfile = profileName;
      });

      // Save the current profile selection to persistent storage
      _saveFtpProfilesToStorage();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('FTP profile "$profileName" loaded successfully!'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _deleteFtpProfile(String profileName) {
    setState(() {
      _ftpProfiles.remove(profileName);
      if (_currentFtpProfile == profileName) {
        _currentFtpProfile = null;
      }
    });

    // Save to persistent storage
    _saveFtpProfilesToStorage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FTP profile "$profileName" deleted successfully!'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // FTP Profile Persistence Methods
  Future<void> _saveFtpProfilesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = jsonEncode(_ftpProfiles);
      final currentProfile = _currentFtpProfile;

      await prefs.setString('ftp_profiles', profilesJson);
      if (currentProfile != null) {
        await prefs.setString('current_ftp_profile', currentProfile);
        print('DEBUG: Saved current FTP profile "$currentProfile" to storage');
      }
    } catch (e) {
      print('Error saving FTP profiles: $e');
    }
  }

  Future<void> _loadFtpProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString('ftp_profiles');
      final currentProfile = prefs.getString('current_ftp_profile');

      print('DEBUG: Loading FTP profiles - currentProfile: $currentProfile');
      print('DEBUG: Available profiles: ${_ftpProfiles.keys.toList()}');

      if (profilesJson != null) {
        final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
        setState(() {
          _ftpProfiles = Map<String, Map<String, dynamic>>.from(profiles);
          _currentFtpProfile = currentProfile;
        });

        // Automatically load the current profile data if one exists
        if (currentProfile != null &&
            _ftpProfiles.containsKey(currentProfile)) {
          final profile = _ftpProfiles[currentProfile];
          if (profile != null) {
            setState(() {
              _ftpHost = profile['host'] ?? '';
              _ftpUsername = profile['username'] ?? '';
              _ftpPassword = profile['password'] ?? '';
              _ftpPort = profile['port'] ?? 21;
              _ftpRemotePath = profile['remotePath'] ?? '';
              _ftpPassiveMode = profile['passiveMode'] ?? true;
            });
            print('DEBUG: Loaded FTP profile "$currentProfile" on app startup');
          }
        } else {
          print('DEBUG: No current FTP profile found or profile not in list');
        }
      }
    } catch (e) {
      print('Error loading FTP profiles: $e');
    }
  }

  void _showFtpProfileManager() {
    final profileNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FTP Profile Manager'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            children: [
              // Profile List
              Expanded(
                child: _ftpProfiles.isEmpty
                    ? const Center(
                        child: Text(
                          'No saved profiles yet.\nCreate your first profile below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _ftpProfiles.length,
                        itemBuilder: (context, index) {
                          final profileName =
                              _ftpProfiles.keys.elementAt(index);
                          final profile = _ftpProfiles[profileName]!;
                          final isCurrent = _currentFtpProfile == profileName;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color:
                                isCurrent ? Colors.blue.withOpacity(0.1) : null,
                            child: ListTile(
                              leading: Icon(
                                isCurrent ? Icons.check_circle : Icons.storage,
                                color: isCurrent ? Colors.blue : Colors.grey,
                              ),
                              title: Text(
                                profileName,
                                style: TextStyle(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle:
                                  Text('${profile['host']}:${profile['port']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isCurrent)
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () =>
                                          _loadFtpProfile(profileName),
                                      tooltip: 'Load Profile',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _deleteFtpProfile(profileName),
                                    tooltip: 'Delete Profile',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              // Create New Profile Section
              const Text(
                'Create New Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: profileNameController,
                      decoration: const InputDecoration(
                        labelText: 'Profile Name',
                        hintText: 'e.g., Work Server, Home Server',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _saveFtpProfile(value.trim());
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final profileName = profileNameController.text.trim();
                      if (profileName.isNotEmpty) {
                        _saveFtpProfile(profileName);
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save Current Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCreateNewProfileDialog() {
    final profileNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New FTP Profile'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a name for your new FTP profile. The current FTP settings will be saved with this name.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: profileNameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'e.g., Work Server, Home Server',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _saveFtpProfile(value.trim());
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final profileName = profileNameController.text.trim();
              if (profileName.isNotEmpty) {
                _saveFtpProfile(profileName);
                Navigator.pop(context);
              }
            },
            child: const Text('Create Profile'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(String profileName) {
    final profile = _ftpProfiles[profileName];
    if (profile == null) return;

    final hostController = TextEditingController(text: profile['host'] ?? '');
    final usernameController =
        TextEditingController(text: profile['username'] ?? '');
    final passwordController =
        TextEditingController(text: profile['password'] ?? '');
    final portController =
        TextEditingController(text: (profile['port'] ?? 21).toString());
    final remotePathController =
        TextEditingController(text: profile['remotePath'] ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            width: 450,
            height: 500,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.edit, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Edit Profile: $profileName',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Server Settings
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Settings',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Host field
                      TextField(
                        controller: hostController,
                        style: const TextStyle(fontSize: 12, height: 2.3),
                        decoration: InputDecoration(
                          hintText: 'ftp.example.com',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(
                                color: Colors.grey.shade400, width: 1.5),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          isDense: true,
                          labelText: 'FTP Host',
                          labelStyle: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Username and Port row
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: usernameController,
                              style: const TextStyle(fontSize: 12, height: 2.3),
                              decoration: InputDecoration(
                                hintText: 'username',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 11),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade400, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                isDense: true,
                                labelText: 'Username',
                                labelStyle: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade600),
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.auto,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: portController,
                              style: const TextStyle(fontSize: 12, height: 2.3),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '21',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 11),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade400, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                isDense: true,
                                labelText: 'Port',
                                labelStyle: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade600),
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.auto,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Password field
                      TextField(
                        controller: passwordController,
                        style: const TextStyle(fontSize: 12, height: 2.3),
                        obscureText: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(
                                color: Colors.grey.shade400, width: 1.5),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          isDense: true,
                          labelText: 'Password',
                          labelStyle: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Remote path field
                      TextField(
                        controller: remotePathController,
                        style: const TextStyle(fontSize: 12, height: 2.3),
                        decoration: InputDecoration(
                          hintText: 'Leave blank for root directory',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                            borderSide: BorderSide(
                                color: Colors.grey.shade400, width: 1.5),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          isDense: true,
                          labelText: 'Remote Path (optional)',
                          labelStyle: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Passive mode checkbox
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: Transform.scale(
                              scale: 0.8,
                              child: Checkbox(
                                value: profile['passiveMode'] ?? true,
                                onChanged: (value) {
                                  setDialogState(() {
                                    // Update the profile's passive mode
                                  });
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                activeColor: Colors.grey.shade600,
                                checkColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Use Passive Mode',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context); // Close edit dialog
                        _showFtpSettings(); // Return to main FTP settings screen
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        // Update the profile with new values
                        _ftpProfiles[profileName] = {
                          'host': hostController.text,
                          'username': usernameController.text,
                          'password': passwordController.text,
                          'port': int.tryParse(portController.text) ?? 21,
                          'remotePath': remotePathController.text,
                          'passiveMode': profile['passiveMode'] ?? true,
                        };
                        Navigator.pop(context); // Close edit dialog
                        // Reopen FTP settings dialog with success message
                        _showFtpSettingsWithSuccess(
                            'Profile "$profileName" updated successfully!');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // FTP Methods
  void _showFtpSettingsWithSuccess(String message) {
    final hostController = TextEditingController(text: _ftpHost);
    final usernameController = TextEditingController(text: _ftpUsername);
    final passwordController = TextEditingController(text: _ftpPassword);
    final portController = TextEditingController(text: _ftpPort.toString());
    final remotePathController = TextEditingController(text: _ftpRemotePath);
    final profileNameController = TextEditingController();
    bool showProfileManager = false; // Track which view to show
    String? successMessage = message; // Set the success message

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            width: 450,
            height: 500,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(showProfileManager ? Icons.folder : Icons.settings,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      showProfileManager
                          ? 'FTP Profile Manager'
                          : 'FTP Server Settings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _showCreateNewProfileDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Create New Profile',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              showProfileManager = !showProfileManager;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    showProfileManager
                                        ? Icons.settings
                                        : Icons.folder,
                                    size: 12,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  showProfileManager
                                      ? 'Back to Settings'
                                      : 'Manage Profiles',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Success Message
                if (successMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 16, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            successMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              successMessage = null;
                            });
                          },
                          child: Icon(Icons.close,
                              size: 14, color: Colors.green.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Content - either settings or profile manager
                if (!showProfileManager) ...[
                  // Profile Selection
                  Text(
                    'Select Profile',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _currentFtpProfile,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: false,
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'No Profile Selected',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                        ..._ftpProfiles.keys
                            .map((profileName) => DropdownMenuItem<String>(
                                  value: profileName,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          profileName,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showEditProfileDialog(profileName);
                                        },
                                        child: Icon(
                                          Icons.settings,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ],
                      onChanged: (String? newValue) {
                        setDialogState(() {
                          if (newValue != null) {
                            _loadFtpProfile(newValue);
                            // Update the text controllers with loaded profile data
                            hostController.text = _ftpHost;
                            usernameController.text = _ftpUsername;
                            passwordController.text = _ftpPassword;
                            portController.text = _ftpPort.toString();
                            remotePathController.text = _ftpRemotePath;
                          } else {
                            _currentFtpProfile = null;
                          }
                        });
                      },
                      icon: Icon(Icons.arrow_drop_down,
                          size: 16, color: Colors.grey.shade600),
                      dropdownColor: Colors.white,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Upload Options
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload Options',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Rename uploaded file option
                        TextField(
                          style: const TextStyle(fontSize: 12, height: 2.3),
                          decoration: InputDecoration(
                            hintText: 'Enter custom filename (optional)',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: BorderSide(
                                  color: Colors.grey.shade400, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            labelText: 'Rename uploaded file as',
                            labelStyle: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Save duplicate option
                        TextField(
                          style: const TextStyle(fontSize: 12, height: 2.3),
                          decoration: InputDecoration(
                            hintText:
                                'Enter folder path for duplicate (optional)',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: BorderSide(
                                  color: Colors.grey.shade400, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            labelText:
                                'Save a duplicate version in another folder',
                            labelStyle: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Enable duplicate checkbox
                        Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: Transform.scale(
                                scale: 0.8,
                                child: Checkbox(
                                  value: false, // Placeholder value
                                  onChanged: (value) {
                                    setDialogState(() {
                                      // Placeholder functionality
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  activeColor: Colors.grey.shade600,
                                  checkColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Enable duplicate file saving',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  // Profile Manager View
                  Text(
                    'Profile Manager',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Profile List
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _ftpProfiles.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved profiles yet.\nCreate your first profile using the settings above.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _ftpProfiles.length,
                            itemBuilder: (context, index) {
                              final profileName =
                                  _ftpProfiles.keys.elementAt(index);
                              final profile = _ftpProfiles[profileName]!;
                              final isCurrent =
                                  _currentFtpProfile == profileName;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: isCurrent
                                    ? Colors.blue.withOpacity(0.1)
                                    : null,
                                child: ListTile(
                                  leading: Icon(
                                    isCurrent
                                        ? Icons.check_circle
                                        : Icons.storage,
                                    color:
                                        isCurrent ? Colors.blue : Colors.grey,
                                    size: 16,
                                  ),
                                  title: Text(
                                    profileName,
                                    style: TextStyle(
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${profile['host']}:${profile['port']}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isCurrent)
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow,
                                              size: 16),
                                          onPressed: () {
                                            setDialogState(() {
                                              _loadFtpProfile(profileName);
                                              // Update the text controllers with loaded profile data
                                              hostController.text = _ftpHost;
                                              usernameController.text =
                                                  _ftpUsername;
                                              passwordController.text =
                                                  _ftpPassword;
                                              portController.text =
                                                  _ftpPort.toString();
                                              remotePathController.text =
                                                  _ftpRemotePath;
                                            });
                                          },
                                          tooltip: 'Load Profile',
                                        ),
                                      IconButton(
                                        icon:
                                            const Icon(Icons.delete, size: 16),
                                        onPressed: () {
                                          setDialogState(() {
                                            _deleteFtpProfile(profileName);
                                          });
                                        },
                                        tooltip: 'Delete Profile',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context); // Close edit dialog
                        _showFtpSettings(); // Return to main FTP settings screen
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _ftpHost = hostController.text;
                          _ftpUsername = usernameController.text;
                          _ftpPassword = passwordController.text;
                          _ftpPort = int.tryParse(portController.text) ?? 21;
                          _ftpRemotePath = remotePathController.text;
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('FTP settings saved!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade500),
                        ),
                        child: const Text(
                          'Save Settings',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFtpSettings() {
    final hostController = TextEditingController(text: _ftpHost);
    final usernameController = TextEditingController(text: _ftpUsername);
    final passwordController = TextEditingController(text: _ftpPassword);
    final portController = TextEditingController(text: _ftpPort.toString());
    final remotePathController = TextEditingController(text: _ftpRemotePath);
    final profileNameController = TextEditingController();
    bool showProfileManager = false; // Track which view to show
    String? successMessage; // Track success message

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            width: 450,
            height: 500,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(showProfileManager ? Icons.folder : Icons.settings,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      showProfileManager
                          ? 'FTP Profile Manager'
                          : 'FTP Server Settings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _showCreateNewProfileDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Create New Profile',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              showProfileManager = !showProfileManager;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    showProfileManager
                                        ? Icons.settings
                                        : Icons.folder,
                                    size: 12,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  showProfileManager
                                      ? 'Back to Settings'
                                      : 'Manage Profiles',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Success Message
                if (successMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 16, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            successMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              successMessage = null;
                            });
                          },
                          child: Icon(Icons.close,
                              size: 14, color: Colors.green.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Content - either settings or profile manager
                if (!showProfileManager) ...[
                  // Profile Selection
                  Text(
                    'Select Profile',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _currentFtpProfile,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: false,
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'No Profile Selected',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                        ..._ftpProfiles.keys
                            .map((profileName) => DropdownMenuItem<String>(
                                  value: profileName,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          profileName,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showEditProfileDialog(profileName);
                                        },
                                        child: Icon(
                                          Icons.settings,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ],
                      onChanged: (String? newValue) {
                        setDialogState(() {
                          if (newValue != null) {
                            _loadFtpProfile(newValue);
                            // Update the text controllers with loaded profile data
                            hostController.text = _ftpHost;
                            usernameController.text = _ftpUsername;
                            passwordController.text = _ftpPassword;
                            portController.text = _ftpPort.toString();
                            remotePathController.text = _ftpRemotePath;
                          } else {
                            _currentFtpProfile = null;
                          }
                        });
                      },
                      icon: Icon(Icons.arrow_drop_down,
                          size: 16, color: Colors.grey.shade600),
                      dropdownColor: Colors.white,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Upload Options
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload Options',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Rename uploaded file option
                        TextField(
                          style: const TextStyle(fontSize: 12, height: 2.3),
                          decoration: InputDecoration(
                            hintText: 'Enter custom filename (optional)',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: BorderSide(
                                  color: Colors.grey.shade400, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            labelText: 'Rename uploaded file as',
                            labelStyle: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Save duplicate option
                        TextField(
                          style: const TextStyle(fontSize: 12, height: 2.3),
                          decoration: InputDecoration(
                            hintText:
                                'Enter folder path for duplicate (optional)',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(2),
                              borderSide: BorderSide(
                                  color: Colors.grey.shade400, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            labelText:
                                'Save a duplicate version in another folder',
                            labelStyle: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Enable duplicate checkbox
                        Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: Transform.scale(
                                scale: 0.8,
                                child: Checkbox(
                                  value: false, // Placeholder value
                                  onChanged: (value) {
                                    setDialogState(() {
                                      // Placeholder functionality
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  activeColor: Colors.grey.shade600,
                                  checkColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Enable duplicate file saving',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  const SizedBox(height: 12),
                ] else ...[
                  // Profile Manager View
                  Text(
                    'Profile Manager',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Profile List
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _ftpProfiles.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved profiles yet.\nCreate your first profile using the settings above.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _ftpProfiles.length,
                            itemBuilder: (context, index) {
                              final profileName =
                                  _ftpProfiles.keys.elementAt(index);
                              final profile = _ftpProfiles[profileName]!;
                              final isCurrent =
                                  _currentFtpProfile == profileName;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: isCurrent
                                    ? Colors.blue.withOpacity(0.1)
                                    : null,
                                child: ListTile(
                                  leading: Icon(
                                    isCurrent
                                        ? Icons.check_circle
                                        : Icons.storage,
                                    color:
                                        isCurrent ? Colors.blue : Colors.grey,
                                    size: 16,
                                  ),
                                  title: Text(
                                    profileName,
                                    style: TextStyle(
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${profile['host']}:${profile['port']}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isCurrent)
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow,
                                              size: 16),
                                          onPressed: () {
                                            setDialogState(() {
                                              _loadFtpProfile(profileName);
                                              // Update the text controllers with loaded profile data
                                              hostController.text = _ftpHost;
                                              usernameController.text =
                                                  _ftpUsername;
                                              passwordController.text =
                                                  _ftpPassword;
                                              portController.text =
                                                  _ftpPort.toString();
                                              remotePathController.text =
                                                  _ftpRemotePath;
                                            });
                                          },
                                          tooltip: 'Load Profile',
                                        ),
                                      IconButton(
                                        icon:
                                            const Icon(Icons.delete, size: 16),
                                        onPressed: () {
                                          setDialogState(() {
                                            _deleteFtpProfile(profileName);
                                          });
                                        },
                                        tooltip: 'Delete Profile',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _ftpHost = hostController.text;
                          _ftpUsername = usernameController.text;
                          _ftpPassword = passwordController.text;
                          _ftpPort = int.tryParse(portController.text) ?? 21;
                          _ftpRemotePath = remotePathController.text;
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('FTP settings saved!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Text(
                          'Save Settings',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods for caption building
  String _month(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  String _formatDateline(
      String city, String stateOrProvince, String monthUpper, int day) {
    if (_isGameInUnitedStates()) {
      // US format: CITY, STATE - DATE
      return '${city.toUpperCase()}, ${stateOrProvince.toUpperCase()} - $monthUpper $day:';
    } else {
      // Canadian format: CITY, PROVINCE_ABBREVIATION - DATE
      final provAbbr = _abbr(stateOrProvince);
      return '${city.toUpperCase()}, $provAbbr - $monthUpper $day:';
    }
  }

  String _formatLocationSuffix(
      String city, String stateOrProvince, String formattedDate) {
    if (_isGameInUnitedStates()) {
      // US format: in City, State (no country needed)
      // Special case for Washington DC - keep DC capitalized
      final formattedState =
          stateOrProvince == 'DC' ? 'DC' : _capitalize(stateOrProvince);
      return 'in ${_capitalize(city)}, $formattedState';
    } else {
      // Canadian format: in City, Province, Canada
      return 'in ${_capitalize(city)}, ${_capitalize(stateOrProvince)}, Canada';
    }
  }

  bool _isGameInUnitedStates() {
    // Check if the province/state is a Canadian province
    final canadianProvinces = {
      'Ontario',
      'Quebec',
      'British Columbia',
      'Alberta',
      'Saskatchewan',
      'Manitoba',
      'New Brunswick',
      'Nova Scotia',
      'Prince Edward Island',
      'Newfoundland and Labrador',
      'Northwest Territories',
      'Nunavut',
      'Yukon'
    };

    return !canadianProvinces.contains(provinceController.text);
  }

  String _abbr(String province) {
    const abbreviations = {
      'Ontario': 'ON',
      'Quebec': 'QC',
      'British Columbia': 'BC',
      'Alberta': 'AB',
      'Manitoba': 'MB',
      'Saskatchewan': 'SK',
      'Nova Scotia': 'NS',
      'New Brunswick': 'NB',
      'Newfoundland and Labrador': 'NL',
      'Prince Edward Island': 'PE',
      'Northwest Territories': 'NT',
      'Nunavut': 'NU',
      'Yukon': 'YT',
    };
    return abbreviations[province] ?? province;
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    // Handle multi-word cities like "New York"
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _combinePlayersWithSingleTeam(List<String> players) {
    if (players.isEmpty) return '';

    // Get full player names
    final playerNames = players.toList();

    // Determine the team from the first player's selection context
    final isHomeTeamPlayer = selectedHomePlayers.contains(players.first);
    final teamName = isHomeTeamPlayer ? selectedHomeTeam : selectedAwayTeam;

    if (teamName == null) {
      // Fallback to just player names if team is not available
      if (playerNames.length == 1) {
        return playerNames.first;
      } else if (playerNames.length == 2) {
        return '${playerNames[0]} and ${playerNames[1]}';
      } else {
        final last = playerNames.removeLast();
        return '${playerNames.join(', ')}, and $last';
      }
    }

    if (playerNames.length == 1) {
      return '${playerNames.first} of the $teamName';
    } else if (playerNames.length == 2) {
      // Two players: "Player1 and Player2 of the team"
      return '${playerNames[0]} and ${playerNames[1]} of the $teamName';
    } else {
      // Three or more players: "Player1, Player2, and Player3 of the team"
      final last = playerNames.removeLast();
      return '${playerNames.join(', ')}, and $last of the $teamName';
    }
  }

  String _buildActionPhrase() {
    String baseAction = '';
    final verbToUse = _selectedActionVerb ?? _selectedVerb;
    if (verbToUse == null) return '';

    // Get the count of active players for plural/singular verb forms
    final activePlayerCount =
        selectedHomePlayers.length + selectedAwayPlayers.length;

    switch (verbToUse) {
      case 'Single':
        baseAction = 'single';
        break;
      case 'Double':
        baseAction = 'double';
        break;
      case 'Triple':
        baseAction = 'triple';
        break;
      case 'Home Run':
        baseAction = _buildHomeRunPhrase();
        break;
      case 'Sacrifice Fly':
        baseAction = 'sacrifice fly';
        break;
      case 'Strikeout':
        baseAction = 'strikeout';
        break;
      case 'Grand Slam':
        baseAction = 'grand slam';
        break;
      case 'At Bat':
        return 'takes an at bat in his batting stance against the ${_getOpposingTeamName()}';
      case 'Pitching':
        return 'delivers a pitch against the ${_getOpposingTeamName()}';
      case 'Swings':
        return 'swings against the ${_getOpposingTeamName()}';
      case 'Bunts':
        return 'bunts against the ${_getOpposingTeamName()}';
      case 'Hit by Pitch':
        // Check if opposing players are selected
        final opposingPlayers = _getOpposingPlayers();
        if (opposingPlayers.isNotEmpty) {
          final pitcherName = _formatPlayersWithTeam(opposingPlayers);
          return 'is hit by a pitch by $pitcherName';
        } else {
          final opposingTeam = _getOpposingTeamName();
          return 'gets hit by a pitch against the $opposingTeam';
        }
      case 'Walks':
        // Check if opposing players are selected
        final opposingPlayersWalks = _getOpposingPlayers();
        if (opposingPlayersWalks.isNotEmpty) {
          final pitcherName = _formatPlayersWithTeam(opposingPlayersWalks);
          return 'takes a walk against $pitcherName';
        } else {
          final opposingTeam = _getOpposingTeamName();
          return 'takes a walk against the $opposingTeam';
        }
      case 'Fielding Position':
        return 'takes fielding position against the ${_getOpposingTeamName()}';

      case 'Looks On':
        // Check if multiple players are selected
        final activePlayers = selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayers = activePlayers.length > 1;

        if (_isPriorToGame) {
          return isMultiplePlayers ? 'look on' : 'looks on';
        } else {
          final action = isMultiplePlayers ? 'look on' : 'looks on';
          return '$action against the ${_getOpposingTeamName()}';
        }
      case 'Walks Off Field':
        return 'walks off the field against the ${_getOpposingTeamName()}';
      case 'Runs Off Field':
        return 'runs off the field against the ${_getOpposingTeamName()}';
      case 'Takes the Field':
        if (_isPriorToGame) {
          return 'takes the field';
        } else {
          return 'takes the field against the ${_getOpposingTeamName()}';
        }
      case 'Comes Off the Field':
        if (_isPriorToGame) {
          return 'comes off the field';
        } else {
          return 'comes off the field against the ${_getOpposingTeamName()}';
        }
      case 'National Anthem':
        // Check if multiple players are selected
        final activePlayers = selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayers = activePlayers.length > 1;

        final action = isMultiplePlayers ? 'look on' : 'looks on';
        return '$action during the national anthem prior to play against the ${_getOpposingTeamName()}';
      case 'Stretching':
        // Check if multiple players are selected
        final activePlayersStretching =
            selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayersStretching = activePlayersStretching.length > 1;

        final actionStretching =
            isMultiplePlayersStretching ? 'stretch' : 'stretches';
        return '$actionStretching prior to play against the ${_getOpposingTeamName()}';
      case 'Warm Ups':
        // Check if multiple players are selected
        final activePlayersWarmUps =
            selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayersWarmUps = activePlayersWarmUps.length > 1;

        final actionWarmUps = isMultiplePlayersWarmUps
            ? 'take part in warm ups'
            : 'takes part in warm ups';
        return '$actionWarmUps prior to play against the ${_getOpposingTeamName()}';
      case 'Pitching Change':
        String inningText = '';
        if (_selectedRbiInning != null) {
          inningText =
              ' during the ${_getOrdinalSuffix(_selectedRbiInning!)} inning';
        }

        // Get selected players
        final selectedPlayers = selectedHomePlayers.isNotEmpty
            ? selectedHomePlayers
            : selectedAwayPlayers;

        if (selectedPlayers.isNotEmpty) {
          final firstPlayer = selectedPlayers.first;
          // Get team name for the first player
          final isHomeTeamPlayer = selectedHomePlayers.contains(firstPlayer);
          final teamName =
              isHomeTeamPlayer ? selectedHomeTeam : selectedAwayTeam;
          final firstPlayerName = '$firstPlayer of the $teamName';

          // Get remaining players for "stand on the mound" part
          final remainingPlayers = selectedPlayers.skip(1).toList();

          if (_managerName.isNotEmpty) {
            if (remainingPlayers.isNotEmpty) {
              final remainingPlayerNames = remainingPlayers.length == 1
                  ? remainingPlayers.first
                  : '${remainingPlayers.take(remainingPlayers.length - 1).join(', ')}, and ${remainingPlayers.last}';
              return '$firstPlayerName is taken out of the game by manager $_managerName as $remainingPlayerNames stand on the mound in a break in play$inningText against the ${_getOpposingTeamName()}';
            } else {
              return '$firstPlayerName is taken out of the game by manager $_managerName in a break in play$inningText against the ${_getOpposingTeamName()}';
            }
          } else {
            if (remainingPlayers.isNotEmpty) {
              final remainingPlayerNames = remainingPlayers.length == 1
                  ? remainingPlayers.first
                  : '${remainingPlayers.take(remainingPlayers.length - 1).join(', ')}, and ${remainingPlayers.last}';
              return '$firstPlayerName is taken out of the game as $remainingPlayerNames stand on the mound in a break in play$inningText against the ${_getOpposingTeamName()}';
            } else {
              return '$firstPlayerName is taken out of the game in a break in play$inningText against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          if (_managerName.isNotEmpty) {
            return 'pitcher taken out of the game by manager $_managerName$inningText against the ${_getOpposingTeamName()}';
          } else {
            return 'pitcher taken out of the game$inningText against the ${_getOpposingTeamName()}';
          }
        }
      case 'Catches':
        if (_selectedFieldingAction == 'Diving Catch' || _isDivingCatch) {
          return 'makes a diving catch against the ${_getOpposingTeamName()}';
        } else {
          return 'catches a ball against the ${_getOpposingTeamName()}';
        }
      case 'Throws':
        return 'throws a ball against the ${_getOpposingTeamName()}';
      case 'Tags':
        if (_selectedTagsAction != null) {
          // Handle On the Base Path as a special case first
          if (_selectedTagsAction == 'Tags Runner Out at: On the Base Path') {
            final opposingTeam = _getOpposingTeamName();
            final secondPlayer = _getSecondPlayer();
            if (secondPlayer != null) {
              return 'tags $secondPlayer out on the base path against the $opposingTeam';
            } else {
              return 'tags a runner out on the base path against the $opposingTeam';
            }
          }

          // Parse the tags action to build proper caption
          final parts = _selectedTagsAction!.split(' - ');
          if (parts.length == 2) {
            final base = parts[0].replaceAll('Tags Runner Out at: ', '');
            final action = parts[1].toLowerCase();

            // Convert base to full word
            String fullBaseName;
            switch (base) {
              case '1st':
                fullBaseName = 'first base';
                break;
              case '2nd':
                fullBaseName = 'second base';
                break;
              case '3rd':
                fullBaseName = 'third base';
                break;
              case 'Home':
                fullBaseName = 'home plate';
                break;
              case 'On the Base Path':
                fullBaseName = 'on the base path';
                break;
              default:
                fullBaseName = base.toLowerCase();
            }

            // Get the second player (the one being tagged out)
            final secondPlayer = _getSecondPlayer();
            if (secondPlayer != null) {
              if (action == 'stealing') {
                return 'tags $secondPlayer out at $fullBaseName on a stealing attempt';
              } else if (action == 'pickoff') {
                return 'tags $secondPlayer out at $fullBaseName on a pickoff';
              } else if (action == 'attempting to advance') {
                return 'tags $secondPlayer out at $fullBaseName attempting to advance';
              } else if (action == 'attempting to score') {
                return 'tags $secondPlayer out at $fullBaseName attempting to score';
              } else if (fullBaseName == 'on the base path') {
                final opposingTeam = _getOpposingTeamName();
                return 'tags $secondPlayer out on the base path against the $opposingTeam';
              } else {
                return 'tags $secondPlayer out at $fullBaseName $action';
              }
            } else {
              if (action == 'stealing') {
                return 'tags a runner out at $fullBaseName on a stealing attempt';
              } else if (action == 'pickoff') {
                return 'tags a runner out at $fullBaseName on a pickoff';
              } else if (action == 'attempting to advance') {
                return 'tags a runner out at $fullBaseName attempting to advance';
              } else if (action == 'attempting to score') {
                return 'tags a runner out at $fullBaseName attempting to score';
              } else if (fullBaseName == 'on the base path') {
                final opposingTeam = _getOpposingTeamName();
                return 'tags a runner out on the base path against the $opposingTeam';
              } else {
                return 'tags a runner out at $fullBaseName $action';
              }
            }
          }
          return _selectedTagsAction!.toLowerCase();
        }
        return 'tags a player out of the ${_getOpposingTeamName()}';
      case 'Groundball':
        if (_isDivingCatch) {
          return 'dives for a groundball against the ${_getOpposingTeamName()}';
        } else {
          return 'fields a groundball against the ${_getOpposingTeamName()}';
        }
      case 'Double Play':
        // Check if opposing players are selected
        final opposingPlayers = _getOpposingPlayers();
        if (_selectedBase != null) {
          final baseName = _getFullBaseName(_selectedBase!);
          if (opposingPlayers.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers);
            return 'turns a double play at $baseName against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a double play at $baseName against the $opposingTeam';
          }
        } else {
          if (opposingPlayers.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers);
            return 'turns a double play against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a double play against the $opposingTeam';
          }
        }
      case 'Triple Play':
        // Check if opposing players are selected
        final opposingPlayers2 = _getOpposingPlayers();
        if (_selectedBase != null) {
          final baseName = _getFullBaseName(_selectedBase!);
          if (opposingPlayers2.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers2);
            return 'turns a triple play at $baseName against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a triple play at $baseName against the $opposingTeam';
          }
        } else {
          if (opposingPlayers2.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers2);
            return 'turns a triple play against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a triple play against the $opposingTeam';
          }
        }
      case 'Steals':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            // Use the stored base that was selected before Tagged Out
            final baseName = _selectedBaseBeforeTaggedOut != null
                ? _getFullBaseName(_selectedBaseBeforeTaggedOut!)
                : 'a base';
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'is tagged out attempting to steal $baseName against $playerNames';
            } else {
              return 'is tagged out attempting to steal $baseName against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'steals $baseName against $playerNames';
            } else {
              return 'steals $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'steals a base against $playerNames';
          } else {
            return 'steals a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Slides':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'gets tagged out sliding against $playerNames';
            } else {
              return 'gets tagged out sliding against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'slides into $baseName against $playerNames';
            } else {
              return 'slides into $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'slides into a base against $playerNames';
          } else {
            return 'slides into a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Runs':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'gets tagged out running against $playerNames';
            } else {
              return 'gets tagged out running against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'runs to $baseName against $playerNames';
            } else {
              return 'runs to $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'runs to a base against $playerNames';
          } else {
            return 'runs to a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Rounds':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Home') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'crosses home plate to score against $playerNames';
            } else {
              return 'crosses home plate to score against the ${_getOpposingTeamName()}';
            }
          } else if (_selectedBase == 'Tagged Out') {
            // Use the stored base that was selected before Tagged Out
            final baseName = _selectedBaseBeforeTaggedOut != null
                ? _getFullBaseName(_selectedBaseBeforeTaggedOut!)
                : 'a base';
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'is tagged out attempting to round $baseName against $playerNames';
            } else {
              return 'is tagged out attempting to round $baseName against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'rounds $baseName against $playerNames';
            } else {
              return 'rounds $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'rounds a base against $playerNames';
          } else {
            return 'rounds a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Celebration':
      case 'Celebrates':
      case 'Celebrates With':
      case 'Celebrates Against':
        // Check if custom celebration text is provided
        if (customCelebrationController.text.isNotEmpty) {
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          // Use custom celebration text
          String customCelebration = customCelebrationController.text.trim();

          // Add teammates if there are multiple players
          Set<String> activePlayers;
          if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
            activePlayers = selectedAwayPlayers;
          } else if (selectedHomePlayers.isNotEmpty &&
              selectedAwayPlayers.isEmpty) {
            activePlayers = selectedHomePlayers;
          } else if (selectedHomePlayers.isNotEmpty &&
              selectedAwayPlayers.isNotEmpty) {
            activePlayers = (_firstTeamSelected == true)
                ? selectedHomePlayers
                : selectedAwayPlayers;
          } else {
            activePlayers = <String>{};
          }

          if (activePlayers.length > 1) {
            final teammates = _getTeammates();
            if (teammates.isNotEmpty) {
              final teammateWord =
                  teammates.length == 1 ? 'teammate' : 'teammates';
              customCelebration +=
                  ' with $teammateWord ${_formatPlayerNames(teammates)}';
            }
          }

          // Add opponent
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return '$customCelebration against $playerNames';
          } else {
            return '$customCelebration against the $opposingTeam';
          }
        }

        final opposingPlayers = _getOpposingPlayers();
        final opposingTeam = _getOpposingTeamName();

        // Build the celebration phrase - always use main player format when multiple players are selected
        // Determine the active players (same logic as in _updateCaption)
        Set<String> activePlayers;
        if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
          activePlayers = selectedAwayPlayers;
        } else if (selectedHomePlayers.isNotEmpty &&
            selectedAwayPlayers.isEmpty) {
          activePlayers = selectedHomePlayers;
        } else if (selectedHomePlayers.isNotEmpty &&
            selectedAwayPlayers.isNotEmpty) {
          // Use first team selected as main focus
          activePlayers = (_firstTeamSelected == true)
              ? selectedHomePlayers
              : selectedAwayPlayers;
        } else {
          activePlayers = <String>{};
        }

        // Always use singular "celebrates" since we're using main player format
        String celebrationPhrase = 'celebrates';

        // Add scoring if selected
        if (_isCelebratingScoring) {
          celebrationPhrase += ' scoring';
        }

        // Add teammates only if there are actual teammates (other players besides main player), but not for solo home runs
        if (_selectedHomeRunType != 'Solo') {
          final teammates = _getTeammates();
          if (teammates.isNotEmpty) {
            final teammateWord =
                teammates.length == 1 ? 'teammate' : 'teammates';
            celebrationPhrase +=
                ' with $teammateWord ${_formatPlayerNames(teammates)}';
          }
        }

        // Add opponent
        if (opposingPlayers.isNotEmpty) {
          final playerNames = _formatPlayersWithTeam(opposingPlayers);
          return '$celebrationPhrase against $playerNames';
        } else {
          return '$celebrationPhrase against the $opposingTeam';
        }
      case 'Dejection':
        // Check if custom dejection text is provided
        if (customDejectionController.text.isNotEmpty) {
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          // Use custom dejection text
          String customDejection = customDejectionController.text.trim();

          // Add opponent
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return '$customDejection against $playerNames';
          } else {
            return '$customDejection against the $opposingTeam';
          }
        }

        // Handle specific dejection types
        final opposingPlayers = _getOpposingPlayers();
        final opposingTeam = _getOpposingTeamName();

        if (_selectedDejectionType == 'Strikeout') {
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts to striking out against $playerNames';
          } else {
            return 'reacts to striking out against the $opposingTeam';
          }
        } else if (_selectedDejectionType == 'Pitcher Taken Out') {
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts to being taken out of the game against $playerNames';
          } else {
            return 'reacts to being taken out of the game against the $opposingTeam';
          }
        } else {
          // Default dejection
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts with dejection against $playerNames';
          } else {
            return 'reacts with dejection against the $opposingTeam';
          }
        }
      case 'Post Game Win':
        final opposingTeam = _getOpposingTeamName();
        final activePlayerCount =
            selectedHomePlayers.length + selectedAwayPlayers.length;
        if (activePlayerCount > 1) {
          return 'celebrate after their team defeated the $opposingTeam';
        } else {
          return 'celebrates their team defeating the $opposingTeam';
        }
      case 'Post Game Loss':
        final opposingTeam2 = _getOpposingTeamName();
        final activePlayerCount2 =
            selectedHomePlayers.length + selectedAwayPlayers.length;
        if (activePlayerCount2 > 1) {
          return 'react to their team losing to the $opposingTeam2';
        } else {
          return 'reacts to their team losing to the $opposingTeam2';
        }
      case 'Stretches':
        if (activePlayerCount >= 2) {
          return 'stretch prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'stretches prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Batting Practice':
        if (activePlayerCount >= 2) {
          return 'take batting practice prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'takes batting practice prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Fielding Practice':
        if (activePlayerCount >= 2) {
          return 'take fielding practice prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'takes fielding practice prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Walks On Field':
        if (activePlayerCount >= 2) {
          return 'walk on the field prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'walks on the field prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Runs On Field':
        if (activePlayerCount >= 2) {
          return 'run on the field prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'runs on the field prior to playing the ${_getOpposingTeamName()}';
        }
      default:
        baseAction = verbToUse.toLowerCase();
    }

    // Build the hit phrase
    String hitPhrase = '';
    final bool isHomeRunAction = verbToUse == 'Home Run';
    if (!isHomeRunAction && _rbiCount != null && _rbiCount! > 0) {
      final rbiText =
          _rbiCount == 1 ? 'RBI' : '${_numberToWord(_rbiCount!)}-RBI';
      hitPhrase = 'hits a $rbiText $baseAction';
    } else {
      hitPhrase = 'hits a $baseAction';
    }

    // Add celebration action if specified
    if (_selectedHittingAction != null) {
      switch (_selectedHittingAction!) {
        case 'celebrates':
        case 'celebrates_in_dugout':
          // Get teammates (other players from the same team as the main player)
          final teammates = _getTeammates();

          // For dugout celebration, if no teammates, don't include teammate phrase
          final teammatePhrase = (_selectedHittingAction ==
                      'celebrates_in_dugout' &&
                  teammates.isEmpty)
              ? ''
              : (teammates.isNotEmpty
                  ? ' with ${teammates.length == 1 ? 'teammate' : 'teammates'} ${_formatPlayerNames(teammates)}'
                  : '');

          // Include opposing players if selected, otherwise use opposing team
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();
          final againstPhrase = opposingPlayers.isNotEmpty
              ? ' against ${_formatPlayerNames(opposingPlayers)}${opposingTeam != null ? ' of the $opposingTeam' : ''}'
              : (opposingTeam != null ? ' against the $opposingTeam' : '');

          const celebrationType = 'celebrates';
          final dugoutPhrase = _selectedHittingAction == 'celebrates_in_dugout'
              ? ' in the dugout'
              : '';

          if (_rbiCount != null && _rbiCount! > 0) {
            final rbiText =
                _rbiCount == 1 ? 'RBI' : '${_numberToWord(_rbiCount!)}-RBI';
            return '$celebrationType a $rbiText $baseAction$dugoutPhrase$teammatePhrase$againstPhrase';
          } else {
            return '$celebrationType a $baseAction$dugoutPhrase$teammatePhrase$againstPhrase';
          }
        case 'runs_base_paths':
          return 'runs the base path on $baseAction';
        case 'runs to first base':
          return 'runs to first base on a $baseAction';
        case 'trots_the_bases':
          // Get opposing players if any are selected
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          if (opposingPlayers.isNotEmpty) {
            // If opposing players are selected, use "past [player names] of the [team]"
            final playerNames = _formatPlayerNames(opposingPlayers);
            final teamPhrase =
                opposingTeam != null ? ' of the $opposingTeam' : '';
            return 'trots the bases on his $baseAction past $playerNames$teamPhrase';
          } else if (opposingTeam != null) {
            // If no opposing players but team is available, use "against the [team]"
            return 'trots the bases on his $baseAction against the $opposingTeam';
          } else {
            // Fallback
            return 'trots the bases on his $baseAction';
          }
        case 'slides_into_base':
          final baseToSlideInto = _getBaseToSlideInto(baseAction);
          return 'slides into $baseToSlideInto on a $baseAction';
        default:
          return hitPhrase;
      }
    }

    return hitPhrase;
  }

  String _numberToWord(int number) {
    switch (number) {
      case 1:
        return 'one';
      case 2:
        return 'two';
      case 3:
        return 'three';
      case 4:
        return 'four';
      case 5:
        return 'five';
      case 6:
        return 'six';
      case 7:
        return 'seven';
      case 8:
        return 'eight';
      case 9:
        return 'nine';
      case 10:
        return 'ten';
      default:
        return number.toString();
    }
  }

  String _getBaseToSlideInto(String hitType) {
    switch (hitType) {
      case 'single':
        return 'first base';
      case 'double':
        return 'second base';
      case 'triple':
        return 'third base';
      case 'home run':
      case 'solo home run':
      case 'two-run home run':
      case 'three-run home run':
      case 'grand slam':
        return 'home plate';
      default:
        return 'base';
    }
  }

  List<String> _getTeammates() {
    // Get teammates (other players from the same team as the main player)
    if (_firstPlayerSelected == null) return [];

    // Determine which team the main player is from using normalized comparison
    final isMainPlayerHome = selectedHomePlayers.any((player) =>
        _removeJerseyNumberFromName(player) == _firstPlayerSelected);

    // Get all players from the same team, excluding the main player (normalized)
    final Iterable<String> source =
        isMainPlayerHome ? selectedHomePlayers : selectedAwayPlayers;
    final teammates = source
        .where((player) =>
            _removeJerseyNumberFromName(player) != _firstPlayerSelected)
        .toList();

    return teammates;
  }

  String? _getOpposingTeamName() {
    // Debug prints to see what's happening
    print('DEBUG: _firstPlayerSelected: $_firstPlayerSelected');
    print('DEBUG: selectedHomeTeam: $selectedHomeTeam');
    print('DEBUG: selectedAwayTeam: $selectedAwayTeam');
    print('DEBUG: selectedHomePlayers: $selectedHomePlayers');
    print('DEBUG: selectedAwayPlayers: $selectedAwayPlayers');

    // Get the opposing team name based on the main player's team
    if (_firstPlayerSelected == null) {
      // Fallback: if no main player is selected, use the first team logic
      if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
        print('DEBUG: Using selectedAwayTeam as fallback: $selectedAwayTeam');
        return selectedAwayTeam;
      } else if (selectedAwayPlayers.isNotEmpty &&
          selectedHomePlayers.isEmpty) {
        print('DEBUG: Using selectedHomeTeam as fallback: $selectedHomeTeam');
        return selectedHomeTeam;
      } else if (_firstTeamSelected == true) {
        print(
            'DEBUG: Using selectedAwayTeam as fallback (firstTeamSelected): $selectedAwayTeam');
        return selectedAwayTeam;
      } else if (_firstTeamSelected == false) {
        print(
            'DEBUG: Using selectedHomeTeam as fallback (firstTeamSelected): $selectedHomeTeam');
        return selectedHomeTeam;
      }
      print('DEBUG: Using final fallback selectedAwayTeam: $selectedAwayTeam');
      return selectedAwayTeam; // Final fallback
    }

    // Determine which team the main player is from
    // Check if any home player contains the first player's name
    final isMainPlayerHome = selectedHomePlayers.any((player) =>
        _removeJerseyNumberFromName(player) == _firstPlayerSelected);
    print('DEBUG: isMainPlayerHome: $isMainPlayerHome');

    // Return the opposing team name
    final opposingTeam = isMainPlayerHome ? selectedAwayTeam : selectedHomeTeam;
    final mainTeam = isMainPlayerHome ? selectedHomeTeam : selectedAwayTeam;
    print('DEBUG: opposingTeam: $opposingTeam');
    print('DEBUG: mainTeam: $mainTeam');

    // If the opposing team is the same as the main player's team,
    // we need to find a different team from the teams list
    if (opposingTeam == mainTeam || opposingTeam == null) {
      print('DEBUG: Teams are the same or null, finding alternative');
      // Find a team from the list that's not the main team
      final alternativeTeam = teamsList.firstWhere(
        (team) => team != mainTeam,
        orElse: () => "the opposing team",
      );
      print('DEBUG: alternativeTeam: $alternativeTeam');
      return alternativeTeam;
    }

    print('DEBUG: Returning opposingTeam: $opposingTeam');
    return opposingTeam;
  }

  String? _getSecondPlayer() {
    // Get all selected players
    final allPlayers = {...selectedHomePlayers, ...selectedAwayPlayers};

    // If we have exactly 2 players, return the second one (not the first selected)
    if (allPlayers.length == 2 && _firstPlayerSelected != null) {
      final secondPlayer = allPlayers.firstWhere(
        (player) => player != _firstPlayerSelected,
        orElse: () => _firstPlayerSelected!,
      );

      // Get the full player name and team
      final isSecondPlayerHome = selectedHomePlayers.contains(secondPlayer);
      final teamName = isSecondPlayerHome ? selectedHomeTeam : selectedAwayTeam;

      if (teamName != null) {
        return '$secondPlayer of the $teamName';
      } else {
        return secondPlayer;
      }
    }

    return null;
  }

  List<String> _getOpposingPlayers() {
    // Get opposing players based on the current caption logic
    // If home team is the main subject (active players), then away players are opposing
    // If away team is the main subject (active players), then home players are opposing

    // Determine which team is the main subject based on current logic
    bool isHomeTeamMainSubject;

    if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
      // Only away team players are selected - away team is main subject
      isHomeTeamMainSubject = false;
    } else if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
      // Only home team players are selected - home team is main subject
      isHomeTeamMainSubject = true;
    } else if (selectedHomePlayers.isNotEmpty &&
        selectedAwayPlayers.isNotEmpty) {
      // Both teams have players - use the first team selected as main subject
      isHomeTeamMainSubject = _firstTeamSelected == true;
    } else {
      // No players selected
      return [];
    }

    // Return the opposing team's players
    return isHomeTeamMainSubject
        ? selectedAwayPlayers.toList()
        : selectedHomePlayers.toList();
  }

  String _formatPlayerNames(List<String> players) {
    if (players.isEmpty) return '';
    if (players.length == 1) return players.first;
    if (players.length == 2) return '${players.first} and ${players.last}';

    // For 3+ players, use commas and "and"
    final allButLast = players.take(players.length - 1).join(', ');
    return '$allButLast and ${players.last}';
  }

  String _formatPlayersWithTeam(List<String> players) {
    if (players.isEmpty) return '';

    // Determine which team these players belong to
    final isHomeTeamPlayers = selectedHomePlayers.contains(players.first);
    final teamName = isHomeTeamPlayers ? selectedHomeTeam : selectedAwayTeam;

    if (teamName == null) {
      // Fallback to just player names if team is not available
      return _formatPlayerNames(players);
    }

    if (players.length == 1) {
      return '${players.first} of the $teamName';
    } else if (players.length == 2) {
      return '${players.first} and ${players.last} of the $teamName';
    } else {
      // For 3+ players, use commas and "and"
      final allButLast = players.take(players.length - 1).join(', ');
      return '$allButLast and ${players.last} of the $teamName';
    }
  }

  Widget _buildPlayerChipsHeader() {
    if (selectedHomePlayers.isEmpty && selectedAwayPlayers.isEmpty) {
      return Center(
        child: Text(
          'No players selected',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Row(
      children: [
        // Left side (Home or Away depending on _homeOnLeft)
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            alignment: _homeOnLeft ? WrapAlignment.start : WrapAlignment.end,
            children: _sortPlayersByNumber(
                    _homeOnLeft ? selectedHomePlayers : selectedAwayPlayers)
                .map((playerName) {
              final isFirstSelected = _isFirstSelectedPlayer(playerName);
              final isHomePlayer = selectedHomePlayers.contains(playerName);

              return Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isHomePlayer ? Colors.grey.shade700 : Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isHomePlayer
                        ? Colors.grey.shade700
                        : Colors.grey.shade400,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star for first selected player
                    if (isFirstSelected) ...[
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // Team icon
                    Icon(
                      isHomePlayer ? Icons.home : Icons.flight,
                      size: 10,
                      color: isHomePlayer ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 2),
                    // Player name
                    Text(
                      _formatChipName(playerName),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: isHomePlayer ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // X button to remove player
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          // Check if this is the first selected player (main player)
                          final isMainPlayer =
                              _isFirstSelectedPlayer(playerName);

                          if (isHomePlayer) {
                            selectedHomePlayers.remove(playerName);
                          } else {
                            selectedAwayPlayers.remove(playerName);
                          }

                          // If removing the main player, reset everything
                          if (isMainPlayer) {
                            _resetCaption();
                            return;
                          }
                        });
                        _updateCaption();
                        _updatePersonalityField();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isHomePlayer
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 8,
                          color: isHomePlayer ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(width: 8),

        // Right side (Away or Home depending on _homeOnLeft)
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            alignment: _homeOnLeft ? WrapAlignment.end : WrapAlignment.start,
            children: _sortPlayersByNumber(
                    _homeOnLeft ? selectedAwayPlayers : selectedHomePlayers)
                .map((playerName) {
              final isFirstSelected = _isFirstSelectedPlayer(playerName);
              final isHomePlayer = selectedHomePlayers.contains(playerName);

              return Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isHomePlayer ? Colors.grey.shade700 : Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isHomePlayer
                        ? Colors.grey.shade700
                        : Colors.grey.shade400,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star for first selected player
                    if (isFirstSelected) ...[
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // Team icon
                    Icon(
                      isHomePlayer ? Icons.home : Icons.flight,
                      size: 10,
                      color: isHomePlayer ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 2),
                    // Player name
                    Text(
                      _formatChipName(playerName),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: isHomePlayer ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // X button to remove player
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          // Check if this is the first selected player (main player)
                          final isMainPlayer =
                              _isFirstSelectedPlayer(playerName);

                          if (isHomePlayer) {
                            selectedHomePlayers.remove(playerName);
                          } else {
                            selectedAwayPlayers.remove(playerName);
                          }

                          // If removing the main player, reset everything
                          if (isMainPlayer) {
                            _resetCaption();
                            return;
                          }
                        });
                        _updateCaption();
                        _updatePersonalityField();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isHomePlayer
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 8,
                          color: isHomePlayer ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  bool _isFirstSelectedPlayer(String playerName) {
    // Always keep the red star on the very first player the user picked
    if (_firstPlayerSelected == null) return false;
    return _removeJerseyNumberFromName(playerName) == _firstPlayerSelected;
  }

  Widget _buildHomeRunSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Magic bar (always visible) - COMMENTED OUT for Home Run to hide magic bar
        /* Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              // Text field
              TextField(
                // Magic bar removed
                controller: TextEditingController(),
                enabled:
                    !_waitingForHomeVisitorChoice, // Disable when waiting for choice
                cursorWidth: 1.5,
                cursorHeight: 16,
                style: const TextStyle(fontSize: 12, height: 2.3),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  isDense: true,
                ),
                onChanged: (value) {
                  // Debug output
                          // print('DEBUG: Magic bar onChanged: "$value"');
        // print('DEBUG: _isMagicInput: ${_isMagicInput(value)}');
                  print(
                      'DEBUG: _waitingForHomeVisitorChoice: $_waitingForHomeVisitorChoice');

                  // If magic bar is completely cleared, don't reset
                  // This preserves player selections during multi-player input
                  if (value.isEmpty) {
                    return;
                  }

                  // If we're waiting for home/visitor choice, ignore all input
                  // The dialog will handle the choice selection
                  if (_waitingForHomeVisitorChoice) {
                    print(
                        'DEBUG: Ignoring input while waiting for dialog choice: "$value"');
                    // Restore the original text if it was changed
                    final expectedText =
                        '${_magicInputMatchingPlayers.first.jerseyNumber} ${_magicInputActionText}';
                    if (value != expectedText) {
                      // print('DEBUG: Restoring original text: "$expectedText"');
                      Future.microtask(() {
                        customBetweenPlayersController.text = expectedText;
                        customBetweenPlayersController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: expectedText.length),
                        );
                      });
                    }
                    return;
                  }

                  // Check for magic input format (e.g., "27 hr 1")
                  if (_isMagicInput(value)) {
                    // print('DEBUG: Processing magic input: "$value"');
                    _parseMagicInput(value);
                    return; // Return to prevent additional setState calls
                  }

                  setState(() {
                    if (_isPlayerSearchMode && _isNumeric(value)) {
                      _filterPlayersByNumber(value);
                    } else if (_isPlayerSearchMode && value.isEmpty) {
                      _filteredPlayers.clear();
                    } else if (!_isPlayerSearchMode) {
                      print('FUCK: In custom verb mode, typing: "$value"');
                      // When in custom verb mode, update caption with custom verb
                      if (value.isNotEmpty) {
                        print('FUCK: value.isNotEmpty = true, value = "$value"');
                        String currentCaption = captionController.text;
                        List<String> allSelectedPlayers = [];
                        allSelectedPlayers.addAll(selectedHomePlayers);
                        allSelectedPlayers.addAll(selectedAwayPlayers);
                        
                        print('FUCK: currentCaption = "$currentCaption"');
                        print('FUCK: allSelectedPlayers = $allSelectedPlayers');
                        
                        if (allSelectedPlayers.isNotEmpty) {
                          String playerName = allSelectedPlayers.first;
                          print('FUCK: playerName = "$playerName"');
                          
                          // Find the player in the caption and insert custom verb after team
                          if (currentCaption.contains(playerName)) {
                            int playerIndex = currentCaption.indexOf(playerName);
                            if (playerIndex != -1) {
                              String beforePlayer = currentCaption.substring(0, playerIndex);
                              String afterPlayer = currentCaption.substring(playerIndex + playerName.length);
                              
                              // Find "against" to insert before it
                              int againstIndex = afterPlayer.indexOf(' against ');
                              if (againstIndex != -1) {
                                String beforeAgainst = afterPlayer.substring(0, againstIndex);
                                String afterAgainst = afterPlayer.substring(againstIndex);
                                captionController.text = '$beforePlayer$playerName$beforeAgainst $value$afterAgainst';
                              } else {
                                // Fallback
                                captionController.text = '$beforePlayer$playerName $value';
                              }
                            }
                          }
                        }
                      }
                    }
                  });
                },
                onEditingComplete: () {
                  // Update caption when editing is complete
                   if (!_isPlayerSearchMode) {
                     String customText = '';
                    String currentCaption = captionController.text;
                    
                    // Find the selected player name
                    List<String> allSelectedPlayers = [];
                    allSelectedPlayers.addAll(selectedHomePlayers);
                    allSelectedPlayers.addAll(selectedAwayPlayers);
                    
                    if (allSelectedPlayers.isNotEmpty) {
                      String playerName = allSelectedPlayers.first;
                      
                      // Find where the player name is in the caption
                      if (currentCaption.contains(playerName)) {
                        int playerIndex = currentCaption.indexOf(playerName);
                        if (playerIndex != -1) {
                          String beforePlayer = currentCaption.substring(0, playerIndex);
                          String afterPlayer = currentCaption.substring(playerIndex + playerName.length);
                          
                          // Find where the team name ends
                          int ofTheIndex = afterPlayer.indexOf(' of the ');
                          if (ofTheIndex != -1) {
                            int againstIndex = afterPlayer.indexOf(' against ');
                            if (againstIndex != -1) {
                              String beforeTeam = afterPlayer.substring(0, againstIndex);
                              String afterTeam = afterPlayer.substring(againstIndex);
                              captionController.text = '$beforePlayer$playerName$beforeTeam $customText$afterTeam';
                            }
                          }
                        }
                      }
                    }
                  }
                },
              ),

              // Magic input player selection overlay
              if (_showMagicInputPlayerOptions)
                Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors
                          .yellow.shade100, // Bright background for debugging
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline,
                                  size: 16, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              Text(
                                'Multiple players found - select one:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._magicInputMatchingPlayers.map(
                          (player) => GestureDetector(
                            onTap: () => _selectMagicInputPlayer(player),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    '#${player.jerseyNumber}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _getTeamAbbreviation(_isHomePlayer(player)
                                            ? selectedHomeTeam ?? ''
                                            : selectedAwayTeam ?? '') ??
                                        '',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isHomePlayer(player)
                                        ? Icons.home
                                        : Icons.flight,
                                    size: 10,
                                    color: _isHomePlayer(player)
                                        ? Colors.blue.shade600
                                        : Colors.red.shade600,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      _removeJerseyNumberFromName(
                                          player.displayName ?? 'Unknown'),
                                      style: const TextStyle(fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Player selection overlay
              if (_filteredPlayers.isNotEmpty || _noPlayersFound)
                Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_noPlayersFound)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: Colors.orange.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  'No player with number ${_playerSearchText}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          ..._filteredPlayers.map(
                            (player) => GestureDetector(
                              onTap: () => _selectPlayer(player),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      '#${player.jerseyNumber}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      _getTeamAbbreviation(_isHomePlayer(player)
                                              ? selectedHomeTeam ?? ''
                                              : selectedAwayTeam ?? '') ??
                                          '',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      _isHomePlayer(player)
                                          ? Icons.home
                                          : Icons.flight,
                                      size: 10,
                                      color: _isHomePlayer(player)
                                          ? Colors.blue.shade600
                                          : Colors.red.shade600,
                                    ),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: Text(
                                        _removeJerseyNumberFromName(
                                            player.displayName ?? 'Unknown'),
                                        style: const TextStyle(fontSize: 10),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (_selectedPlayerNumbers.isNotEmpty)
                          GestureDetector(
                            onTap: _finishPlayerSelection,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border(
                                    top: BorderSide(
                                        color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check,
                                      size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Done selecting players (${_selectedPlayerNumbers.length})',
                                    style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              // Inning selector
              if (_showCustomTextInningSelector)

            ],
          ),
        ), */

        // const SizedBox(height: 4), // Commented out with magic bar

        // Selected home run type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedHomeRunType ?? 'Home Run',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Home Run Type section with buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'Home Run Type',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: ['Solo', 'Two-Run', 'Three-Run', 'Grand Slam']
                          .map((hrType) {
                        final isSelected = _selectedHomeRunType == hrType;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedHomeRunType =
                                  _selectedHomeRunType == hrType
                                      ? null
                                      : hrType;
                            });
                            _updateCaption();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                            child: Builder(builder: (context) {
                              final String typed = _magicBarVerbInput;
                              final RegExpMatch? lettersMatch =
                                  RegExp(r'([a-zA-Z]+)$').firstMatch(typed);
                              final String typedLetters =
                                  lettersMatch?.group(1)?.toLowerCase() ?? '';

                              // Build shortcut: multi-word -> acronym, single-word -> first 2-3
                              List<String> words = RegExp(r'[A-Za-z]+')
                                  .allMatches(hrType)
                                  .map((m) => m.group(0)!)
                                  .toList();
                              String shortcut;
                              if (words.length > 1) {
                                shortcut =
                                    words.map((w) => w[0].toLowerCase()).join();
                              } else {
                                final w = words.first.toLowerCase();
                                shortcut =
                                    w.length >= 2 ? w.substring(0, 2) : w;
                              }

                              String boldPart = '';
                              if (_magicBarFocusNode.hasFocus &&
                                  typedLetters.isNotEmpty &&
                                  shortcut.startsWith(typedLetters)) {
                                boldPart = hrType.substring(
                                    0,
                                    typedLetters.length
                                        .clamp(0, hrType.length));
                              } else if (_magicBarFocusNode.hasFocus) {
                                boldPart = hrType.substring(
                                    0, shortcut.length.clamp(0, hrType.length));
                              }

                              return RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(children: [
                                  if (boldPart.isNotEmpty)
                                    TextSpan(
                                      text: boldPart,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  TextSpan(
                                    text: hrType.substring(boldPart.length),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ]),
                              );
                            }),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Options section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'Options',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  // Celebrates option
                  _buildSubOption('Celebrates', 'celebrates'),

                  // Celebrates in dugout option
                  _buildSubOption(
                      'Celebrates in Dugout', 'celebrates_in_dugout'),

                  // Trots the bases option
                  _buildSubOption('Trots the Bases', 'trots_the_bases'),
                ],
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              const SizedBox(height: 8),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAtBatSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? 'At Bat',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Inning section with buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Innings',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    // Back arrow for extra innings
                    if (_showExtraInnings)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_extraInningsPage > 0) {
                              _extraInningsPage--;
                            } else {
                              // Go back to regular innings
                              _showExtraInnings = false;
                              _extraInningsPage = 0;
                              _selectedRbiInning = null;
                            }
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '←',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    // Innings (regular or extra based on state)
                    ...(_showExtraInnings
                            ? _getExtraInningsForPage()
                            : List.generate(9, (index) => index + 1))
                        .map((inning) {
                      final isSelected = _selectedRbiInning == inning;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRbiInning =
                                _selectedRbiInning == inning ? null : inning;
                          });
                          _updateCaption();
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.grey.shade300
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '$inning',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }),
                    // EXT button that cycles through extra innings
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_showExtraInnings) {
                            // If already showing extra innings, go to next page
                            if (_extraInningsPage < 3) {
                              _extraInningsPage++;
                            } else {
                              // Go back to regular innings
                              _showExtraInnings = false;
                              _extraInningsPage = 0;
                              _selectedRbiInning = null;
                            }
                          } else {
                            // Start showing extra innings
                            _showExtraInnings = true;
                            _extraInningsPage = 0;
                            _selectedRbiInning = null;
                          }
                        });
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _showExtraInnings
                              ? Colors.grey.shade300
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          'XTRA',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
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
      ],
    );
  }

  Widget _buildTagsSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected tags action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedTagsAction ?? 'Tags',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // All tag options listed vertically
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1st Base options
                      _buildTagOptionWithChevron(
                          '1st Base', ['Pickoff', 'Stealing']),

                      // 2nd Base options
                      _buildTagOptionWithChevron('2nd Base', [
                        'Pickoff',
                        'Stealing',
                        'Attempting to Stretch a Single',
                        'Attempting to Tag Up',
                        'Attempting to Advance'
                      ]),

                      // 3rd Base options
                      _buildTagOptionWithChevron('3rd Base', [
                        'Pickoff',
                        'Stealing',
                        'Attempting to Stretch a Double',
                        'Attempting to Tag Up',
                        'Attempting to Advance'
                      ]),

                      // Home Base options
                      _buildTagOptionWithChevron('Home Plate', [
                        'Stealing',
                        'Attempting to Stretch a Triple',
                        'Attempting to Tag Up',
                        'Attempting to Score'
                      ]),

                      // On the Base Path (direct selection)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            final isSelected = _selectedTagsAction ==
                                'Tags Runner Out at: On the Base Path';
                            _selectedTagsAction = isSelected
                                ? null
                                : 'Tags Runner Out at: On the Base Path';
                            _selectedBase = null;
                          });
                          _updateCaption();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: _selectedTagsAction ==
                                    'Tags Runner Out at: On the Base Path'
                                ? Colors.grey.shade300
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'On the Base Path',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                const SizedBox(height: 8),

                // Inning selection section using reusable widget
                SizedBox(
                  height: 100, // Increased height to accommodate Prior button
                  child: _buildReusableInningSelector(),
                ),

                // Back button
                _buildVerbOptionsBackButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showBaseOptions(String base) {
    setState(() {
      _selectedBase = base;
      _selectedTagsAction = null; // Clear any previous selection
    });
  }

  Widget _buildTagOptionWithChevron(String baseName, List<String> options) {
    final isExpanded = _selectedBase ==
        baseName.replaceAll(' Base', '').replaceAll(' Plate', '');
    final hasSelection = _selectedTagsAction != null &&
        _selectedTagsAction!.startsWith(
            'Tags Runner Out at: ${baseName.replaceAll(' Base', '').replaceAll(' Plate', '')}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _selectedBase = null;
                _selectedTagsAction = null;
              } else {
                _selectedBase =
                    baseName.replaceAll(' Base', '').replaceAll(' Plate', '');
                _selectedTagsAction = null;
              }
            });
            _updateCaption();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: (isExpanded || hasSelection)
                  ? Colors.grey.shade300
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    baseName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),

        // Show options when expanded
        if (isExpanded) ...[
          Container(
            margin: const EdgeInsets.only(left: 12, right: 8, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: options.map((option) {
                final tagAction =
                    'Tags Runner Out at: ${baseName.replaceAll(' Base', '').replaceAll(' Plate', '')} - $option';
                final isSelected = _selectedTagsAction == tagAction;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTagsAction = isSelected ? null : tagAction;
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.grey.shade200
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBaseOptions() {
    if (_selectedBase == null) return const SizedBox.shrink();

    List<String> options = [];

    switch (_selectedBase) {
      case '1st':
        options = ['Pickoff'];
        break;
      case '2nd':
        options = [
          'Pickoff',
          'Stealing',
          'Attempting to Stretch a Single',
          'Attempting to Tag Up',
          'Attempting to Advance'
        ];
        break;
      case '3rd':
        options = [
          'Pickoff',
          'Stealing',
          'Attempting to Stretch a Double',
          'Attempting to Tag Up',
          'Attempting to Advance'
        ];
        break;
      case 'Home':
        options = [
          'Stealing',
          'Attempting to Stretch a Triple',
          'Attempting to Tag Up',
          'Attempting to Score'
        ];
        break;
      case 'On the Base Path':
        options = [];
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
          child: Text(
            '$_selectedBase Base Options',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: options.map((option) {
              final tagAction = 'Tags Runner Out at: $_selectedBase - $option';
              final isSelected = _selectedTagsAction == tagAction;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTagsAction = isSelected ? null : tagAction;
                  });
                  _updateCaption();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAtBatInterface() {
    return Stack(
      children: [
        // Background with greyed out verb categories
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Offense, Defense, Running (greyed out)
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Offense', [
                          'Single',
                          'Double',
                          'Triple',
                          'Home Run',
                          'At Bat',
                          'Swings'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Defense', [
                          'Pitching',
                          'Catches',
                          'Throws',
                          'Tags',
                          'Groundball',
                          'Fielding Position'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory(
                            'Running', ['Steals', 'Slides', 'Runs', 'Rounds']),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Bottom row: Reactions and Non Game-Action
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Reactions', [
                          'Celebrates',
                          'Dejection',
                          'Post Game Win',
                          'Post Game Loss',
                          '',
                          '',
                          ''
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Non Game-Action', [
                          'Looks On',
                          'Batting Practice',
                          'Fielding Practice',
                          'Takes the Field',
                          'Comes Off the Field',
                          'National Anthem',
                          'Stretching',
                          'Warm Ups',
                          'Pitching Change'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  const Expanded(child: SizedBox()), // Empty space
                ],
              ),
            ),
          ],
        ),

        // Click outside to close overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              // Close when clicking outside the overlay
              setState(() {
                _selectedVerb = null;
                _selectedRbiInning = null;
              });
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // Inning picker overlay
        Positioned(
          top: 80, // Adjust this to position over the At Bat button
          left: 20, // Adjust this to position over the At Bat button
          child: GestureDetector(
            onTap: () {
              // Prevent closing when clicking inside the overlay
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SizedBox(
                width: 300, // Adjust width as needed
                height: 200, // Adjust height as needed
                child: _buildReusableInningSelector(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildHomeRunPhrase() {
    if (_selectedHomeRunType == null) return 'home run';

    switch (_selectedHomeRunType!) {
      case 'Solo':
        return 'solo home run';
      case 'Two-Run':
        return 'two-run home run';
      case 'Three-Run':
        return 'three-run home run';
      case 'Grand Slam':
        return 'grand slam home run';
      default:
        return 'home run';
    }
  }

  Widget _buildSacrificeFlySubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected hit type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Options header
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Celebrates option
              _buildSubOption('Celebrates', 'celebrates'),

              // Runs to first base option
              _buildSubOption('Runs to First Base', 'runs to first base'),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHittingSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected hit type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // RBI section with buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'RBI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [1, 2, 3].map((rbi) {
                        final isSelected = _rbiCount == rbi;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _rbiCount = _rbiCount == rbi ? null : rbi;
                            });
                            _updateCaption();
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              '$rbi',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Options header
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),

              // Celebrates option
              _buildSubOption('Celebrates', 'celebrates'),

              // Runs the base paths option
              _buildSubOption('Runs the Base Paths', 'runs_base_paths'),

              // Slides into base option (not for Single)
              if (_selectedVerb != 'Single')
                _buildSubOption('Slides into Base', 'slides_into_base'),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubOption(String label, String action) {
    final isSelected = _selectedHittingAction == action;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHittingAction = null;
          } else {
            _selectedHittingAction = action;
          }
        });
        _updateCaption();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.grey.shade800
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            const Expanded(flex: 1, child: SizedBox()),
          ],
        ),
      ),
    );
  }

  List<int> _getExtraInningsForPage() {
    if (_extraInningsPage == 0) {
      return [10, 11, 12, 13, 14, 15, 16];
    } else if (_extraInningsPage == 1) {
      return [17, 18, 19, 20, 21, 22, 23];
    } else if (_extraInningsPage == 2) {
      return [24, 25, 26, 27, 28, 29, 30];
    } else {
      return [24, 25, 26, 27, 28, 29, 30];
    }
  }

  String _formatChipName(String playerName) {
    // Extract jersey number
    final numberMatch = RegExp(r'#(\d+)').firstMatch(playerName);
    final number = numberMatch?.group(1) ?? '';

    // Remove jersey number from name for processing
    final nameWithoutNumber = playerName.replaceAll(RegExp(r'\s*#\d+'), '');

    // Split by spaces and get everything after first name
    final nameParts = nameWithoutNumber.split(' ');
    if (nameParts.length > 1) {
      final lastName = nameParts.skip(1).join(' ');
      return '#$number $lastName';
    }

    // Fallback if no last name found
    return playerName;
  }

  // Extract jersey number from player name for sorting
  int _extractJerseyNumber(String playerName) {
    // Try to match jersey number at the end of the string
    final nameMatch = RegExp(r'#(\d+)$').firstMatch(playerName);
    if (nameMatch != null) {
      final number = int.tryParse(nameMatch.group(1) ?? '0') ?? 0;
      return number;
    }
    return 999; // Return high number for players without numbers to put them at end
  }

  // Sort players by jersey number
  List<String> _sortPlayersByNumber(Set<String> players) {
    if (players.isEmpty) return [];

    final sortedPlayers = players.toList();
    sortedPlayers.sort((a, b) {
      final numberA = _extractJerseyNumber(a);
      final numberB = _extractJerseyNumber(b);
      return numberA.compareTo(numberB);
    });

    return sortedPlayers;
  }

  // Sort Player objects by different criteria
  List<Player> _sortPlayerObjects(
      List<Player> players, String sortOption, bool ascending) {
    if (players.isEmpty) return [];

    final sortedPlayers = List<Player>.from(players);

    switch (sortOption) {
      case 'number':
        sortedPlayers.sort((a, b) {
          final numberA = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
          final numberB = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
          return ascending
              ? numberA.compareTo(numberB)
              : numberB.compareTo(numberA);
        });
        break;
      case 'lastName':
        sortedPlayers.sort((a, b) {
          final lastNameA = _extractLastName(a.displayName ?? '');
          final lastNameB = _extractLastName(b.displayName ?? '');
          return ascending
              ? lastNameA.compareTo(lastNameB)
              : lastNameB.compareTo(lastNameA);
        });
        break;
      case 'firstName':
        sortedPlayers.sort((a, b) {
          final firstNameA = _extractFirstName(a.displayName ?? '');
          final firstNameB = _extractFirstName(b.displayName ?? '');
          return ascending
              ? firstNameA.compareTo(firstNameB)
              : firstNameB.compareTo(firstNameA);
        });
        break;
    }

    return sortedPlayers;
  }

  // Extract last name from display name (e.g., "John Smith #23" -> "Smith")
  String _extractLastName(String displayName) {
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      // Remove jersey number if present
      final nameParts = parts.where((part) => !part.startsWith('#')).toList();
      return nameParts.isNotEmpty ? nameParts.last : displayName;
    }
    return displayName;
  }

  // Extract first name from display name (e.g., "John Smith #23" -> "John")
  String _extractFirstName(String displayName) {
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      // Remove jersey number if present
      final nameParts = parts.where((part) => !part.startsWith('#')).toList();
      return nameParts.isNotEmpty ? nameParts.first : displayName;
    }
    return displayName;
  }

  // Get appropriate icon widget for current sort option
  Widget _getSortIconWidget(String sortOption) {
    switch (sortOption) {
      case 'number':
        return Icon(
          Icons.numbers,
          size: 12,
          color: Colors.grey.shade600,
        );
      case 'lastName':
        return Text(
          'ZA',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        );
      case 'firstName':
        return Text(
          'AZ',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        );
      default:
        return Icon(
          Icons.sort,
          size: 12,
          color: Colors.grey.shade600,
        );
    }
  }

  // Get sort text for button display
  String _getSortText(String sortOption) {
    switch (sortOption) {
      case 'number':
        return 'Number';
      case 'lastName':
        return 'Last Name';
      case 'firstName':
        return 'First Name';
      default:
        return 'Number';
    }
  }

  // Format player name based on current sort option
  String _getFormattedPlayerName(String displayName, String sortOption) {
    final parts = displayName.split(' ');
    final jerseyNumber = parts.last.startsWith('#') ? parts.last : '';
    final nameParts = parts.where((part) => !part.startsWith('#')).toList();

    if (sortOption == 'number') {
      // Extract jersey number and put it at the beginning
      final nameWithoutNumber = nameParts.join(' ');

      if (jerseyNumber.isNotEmpty) {
        return '$jerseyNumber $nameWithoutNumber';
      }
    } else if (sortOption == 'lastName' && nameParts.length >= 2) {
      // Format as "Last Name, First Name #"
      final firstName = nameParts.first;
      final lastName = nameParts.last;

      if (jerseyNumber.isNotEmpty) {
        return '$lastName, $firstName $jerseyNumber';
      } else {
        return '$lastName, $firstName';
      }
    }
    // For other sort options, return original format
    return displayName;
  }

  // Helper functions for smart text field
  bool _isNumeric(String text) {
    return text.isNotEmpty && int.tryParse(text) != null;
  }

  void _filterPlayersByNumber(String number) {
    // Debug output
    print('DEBUG: Searching for player #$number');
    print('DEBUG: Home roster count: ${_homeRoster.length}');
    print('DEBUG: Away roster count: ${_awayRoster.length}');

    // Count players with jersey numbers
    int homeWithNumbers = 0;
    int awayWithNumbers = 0;
    for (Player player in _homeRoster) {
      if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
        homeWithNumbers++;
      }
    }
    for (Player player in _awayRoster) {
      if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
        awayWithNumbers++;
      }
    }
    print('DEBUG: Home players with jersey numbers: $homeWithNumbers');
    print('DEBUG: Away players with jersey numbers: $awayWithNumbers');

    setState(() {
      _playerSearchText = number;
      _filteredPlayers = [];
      _noPlayersFound = false;

      // Search in both home and away rosters for exact matches only
      for (Player player in _homeRoster) {
        if (player.jerseyNumber == number) {
          _filteredPlayers.add(player);
          print(
              'DEBUG: Found player in home roster: ${player.fullName} #${player.jerseyNumber}');
        }
      }
      for (Player player in _awayRoster) {
        if (player.jerseyNumber == number) {
          _filteredPlayers.add(player);
          print(
              'DEBUG: Found player in away roster: ${player.fullName} #${player.jerseyNumber}');
        }
      }

      // Set flag if no players found
      if (_filteredPlayers.isEmpty) {
        _noPlayersFound = true;
        print('DEBUG: No players found with number $number');

        // Show some sample players for debugging
        print('DEBUG: Sample home players:');
        for (int i = 0; i < _homeRoster.length.clamp(0, 3); i++) {
          final player = _homeRoster[i];
          print('DEBUG: - ${player.fullName} #${player.jerseyNumber ?? "N/A"}');
        }
        print('DEBUG: Sample away players:');
        for (int i = 0; i < _awayRoster.length.clamp(0, 3); i++) {
          final player = _awayRoster[i];
          print('DEBUG: - ${player.fullName} #${player.jerseyNumber ?? "N/A"}');
        }
      } else {
        print(
            'DEBUG: Found ${_filteredPlayers.length} players with number $number');
      }
    });
  }

  void _selectPlayer(Player player) {
    setState(() {
      if (player.jerseyNumber != null) {
        _selectedPlayerNumbers.add(player.jerseyNumber!);
      }

      // Add player to the appropriate team's selected players
      final playerName = player.displayName ?? 'Unknown';
      final cleanedPlayerName = _removeJerseyNumberFromName(playerName);

      if (_isHomePlayer(player)) {
        selectedHomePlayers
            .add(playerName); // Use original display name for side lists
        // Set as first player selected if none selected yet
        _firstPlayerSelected ??= cleanedPlayerName;
      } else {
        selectedAwayPlayers
            .add(playerName); // Use original display name for side lists
        // Set as first player selected if none selected yet
        _firstPlayerSelected ??= cleanedPlayerName;
      }

      _playerSearchText = '';
      // Don't clear the magic bar text when adding additional players
      // customBetweenPlayersController.clear();
      _filteredPlayers.clear();

      // Automatically switch to custom verb writer mode when a player is selected
      _isPlayerSearchMode = false;
    });

    // Update caption when player is selected from Magic Bar
    _updateCaption();

    // Ensure the original main player remains selected
    _ensureMainPlayerStillSelected();

    // Store the original caption AFTER it's been updated
    _originalCaptionBeforeCustomVerb = captionController.text;
  }

  void _finishPlayerSelection() {
    setState(() {
      _isPlayerSearchMode = false;
      // Magic bar removed
      // Clear any existing inning selection when switching to custom verb mode
      _showCustomTextInningSelector = false;
    });
  }

  void _resetSmartTextField() {
    setState(() {
      _isPlayerSearchMode = true;
      _filteredPlayers.clear();
      _selectedPlayerNumbers.clear();
      _playerSearchText = '';
      // Magic bar removed
      // Clear custom verb mode state
      _showCustomTextInningSelector = false;
      _originalCaptionBeforeCustomVerb = null; // Clear stored caption
    });
  }

  bool _isHomePlayer(Player player) {
    return _homeRoster.contains(player);
  }

  String _removeJerseyNumberFromName(String playerName) {
    // Remove jersey number patterns like "#23" or " #23" from the end of the name
    return playerName.replaceAll(RegExp(r'\s*#\d+\s*$'), '').trim();
  }

  void _ensureMainPlayerStillSelected() {
    if (_firstPlayerSelected == null) return;
    final normalized = _firstPlayerSelected!;
    // Find the display name that corresponds to the normalized main player in rosters
    String? homeDisplay;
    String? awayDisplay;
    for (final p in _homeRoster) {
      if (_removeJerseyNumberFromName(p.displayName ?? 'Unknown') ==
          normalized) {
        homeDisplay = p.displayName;
        break;
      }
    }
    for (final p in _awayRoster) {
      if (_removeJerseyNumberFromName(p.displayName ?? 'Unknown') ==
          normalized) {
        awayDisplay = p.displayName;
        break;
      }
    }
    // Ensure it's present in the correct selected set
    if (homeDisplay != null &&
        selectedHomePlayers.isNotEmpty &&
        _firstTeamSelected == true) {
      selectedHomePlayers.add(homeDisplay);
    } else if (awayDisplay != null &&
        selectedAwayPlayers.isNotEmpty &&
        _firstTeamSelected == false) {
      selectedAwayPlayers.add(awayDisplay);
    }
  }

  Widget _buildNavigationButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Prev
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: CustomButton(
              onTap: (widget.currentIndex != null && widget.currentIndex! > 0)
                  ? () async {
                      if (widget.onSaveIptc != null) {
                        widget.onSaveIptc!();
                      }
                      widget.onPreviousImage?.call();
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      (widget.currentIndex != null && widget.currentIndex! > 0)
                          ? Colors.grey.shade100
                          : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: (widget.currentIndex != null &&
                              widget.currentIndex! > 0)
                          ? Colors.grey.shade300
                          : Colors.grey.shade400),
                ),
                child: Text(
                  'Prev',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Copy
          CustomButton(
            onTap: _copyMetadataFromCaptionWidget,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                'Copy',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Paste
          CustomButton(
            onTap: _pasteMetadataToCaptionWidget,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                'Paste',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Next
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: CustomButton(
              onTap: (widget.currentIndex != null &&
                      widget.totalImages != null &&
                      widget.currentIndex! < widget.totalImages! - 1)
                  ? () async {
                      if (widget.onSaveIptc != null) {
                        widget.onSaveIptc!();
                      }
                      widget.onNextImage?.call();
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: (widget.currentIndex != null &&
                          widget.totalImages != null &&
                          widget.currentIndex! < widget.totalImages! - 1)
                      ? Colors.grey.shade100
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: (widget.currentIndex != null &&
                              widget.totalImages != null &&
                              widget.currentIndex! < widget.totalImages! - 1)
                          ? Colors.grey.shade300
                          : Colors.grey.shade400),
                ),
                child: Text(
                  'Next',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Reset button
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: CustomButton(
              onTap: _fullReset,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, size: 14, color: Colors.grey.shade700),
                    const SizedBox(width: 2),
                    Text('Reset',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Reset button (aligned to left)
          CustomButton(
            onTap: _fullReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, size: 12, color: Colors.grey.shade700),
                  const SizedBox(width: 2),
                  Text('Reset',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton({VoidCallback? onPressed}) {
    return _buildBackButtonWithWidth(MediaQuery.of(context).size.width * 0.5,
        onPressed: onPressed);
  }

  Widget _buildBackButtonWithWidth(double width, {VoidCallback? onPressed}) {
    return Column(
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: width, // Use passed width parameter
            margin: const EdgeInsets.symmetric(
                horizontal: 5), // 5px padding from left and right
            child: CustomButton(
              onTap: onPressed ??
                  () {
                    setState(() {
                      if (_cameFromCelebration) {
                        // Return to celebration section
                        _selectedVerb = 'Celebration';
                        _selectedActionVerb =
                            null; // Reset action verb to clear caption
                        _selectedHittingAction = null;
                        _selectedCelebrationType =
                            null; // Reset celebration type
                        _isCelebratingScoring =
                            false; // Reset scoring celebration
                        _isCelebratingWithTeammates =
                            false; // Reset teammates celebration
                        _cameFromCelebration = false; // Reset the flag
                        // Reset all menu items
                        _rbiCount = null;
                        _selectedRbiInning = null;
                        _showExtraInnings = false;
                        _extraInningsPage = 0;
                      } else {
                        // Return to main verb menu
                        _selectedVerb = null;
                        _selectedActionVerb =
                            null; // Reset action verb to clear caption
                        _selectedHittingAction = null;
                        _rbiCount = null;
                        _selectedRbiInning = null;
                        _showExtraInnings = false;
                        _extraInningsPage = 0;
                      }
                    });
                    _updateCaption();
                  },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(
                        width: 15), // 15px padding from the left edge
                    Icon(
                      Icons.arrow_back,
                      size: 14,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerbOptionsBackButton({VoidCallback? onPressed}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildBackButtonWithWidth(constraints.maxWidth * 0.5,
            onPressed: onPressed);
      },
    );
  }

  // Reusable inning selector widget
  Widget _buildReusableInningSelector() {
    // Determine which innings to show based on the current state
    List<int> inningsToShow;
    int currentPage =
        _extraInningsPage; // Use existing _extraInningsPage variable

    if (currentPage == 0) {
      inningsToShow = List.generate(9, (index) => index + 1); // 1-9
    } else if (currentPage == 1) {
      inningsToShow = List.generate(9, (index) => index + 10); // 10-18
    } else {
      inningsToShow = List.generate(9, (index) => index + 19); // 19-27
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
          child: const Text(
            'Inning',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Innings section (changes content based on state)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Innings row
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  // Current set of innings
                  ...inningsToShow.map((inning) {
                    final isSelected = _selectedRbiInning == inning;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRbiInning =
                              _selectedRbiInning == inning ? null : inning;
                          if (_selectedRbiInning != null) {
                            _isPriorToGame = false;
                          }
                        });
                        _updateCaption();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.grey.shade300
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '$inning',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Minus button (go back to previous set)
                  GestureDetector(
                    onTap: currentPage > 0
                        ? () {
                            setState(() {
                              _extraInningsPage--;
                              if (_extraInningsPage == 0) {
                                _showExtraInnings = false;
                              }
                              _selectedRbiInning =
                                  null; // Clear selection when switching
                              _isPriorToGame = false; // Clear prior selection
                            });
                            _updateCaption();
                          }
                        : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentPage > 0
                            ? Colors.grey.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: currentPage > 0
                              ? Colors.grey.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),

                  // Plus button (go to next set)
                  GestureDetector(
                    onTap: currentPage < 2
                        ? () {
                            setState(() {
                              _extraInningsPage++;
                              _showExtraInnings = true;
                              _selectedRbiInning =
                                  null; // Clear selection when switching
                              _isPriorToGame = false; // Clear prior selection
                            });
                            _updateCaption();
                          }
                        : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentPage < 2
                            ? Colors.grey.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '+',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: currentPage < 2
                              ? Colors.grey.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Prior to the game option (for "Looks On", "Takes the Field", "Comes Off the Field", and custom text) - placed below innings
              if (_selectedVerb == 'Looks On' ||
                  _selectedVerb == 'Takes the Field' ||
                  _selectedVerb == 'Comes Off the Field' ||
                  _showCustomTextInningSelector) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPriorToGame = !_isPriorToGame;
                      if (_isPriorToGame) {
                        _selectedRbiInning = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: 100,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _isPriorToGame
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Prior to Game',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _isPriorToGame
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Base selection interface for running verbs
  Widget _buildBaseSelectionInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Base selection section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Base',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    if (_selectedVerb != 'Steals')
                      _buildBaseChip('1st', '1st Base'),
                    _buildBaseChip('2nd', '2nd Base'),
                    _buildBaseChip('3rd', '3rd Base'),
                    _buildBaseChip('Home', 'Home Plate'),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Optional section
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Optional',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    if (_selectedVerb != 'Double Play' &&
                        _selectedVerb != 'Triple Play')
                      _buildBaseChip('Tagged Out', 'Tagged Out'),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Inning selection section using reusable widget
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBaseChip(String base, String label) {
    // For regular bases, check if it's selected OR if it's the stored base when Tagged Out is selected
    final isSelected = _selectedBase == base ||
        (base != 'Tagged Out' &&
            _selectedBase == 'Tagged Out' &&
            _selectedBaseBeforeTaggedOut == base);
    // For Tagged Out, check if it's directly selected
    final isTaggedOutSelected =
        base == 'Tagged Out' && _selectedBase == 'Tagged Out';

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected || isTaggedOutSelected) {
            _selectedBase = null;
            if (base == 'Tagged Out') {
              _selectedBaseBeforeTaggedOut = null;
            }
          } else {
            if (base == 'Tagged Out') {
              // Store the current base before selecting Tagged Out
              _selectedBaseBeforeTaggedOut = _selectedBase;
              _selectedBase = base;
            } else {
              // When selecting a regular base, keep Tagged Out selected if it was already selected
              if (_selectedBase == 'Tagged Out') {
                _selectedBaseBeforeTaggedOut = base;
                // Keep Tagged Out selected
              } else {
                // Normal case - select the new base
                _selectedBase = base;
                _selectedBaseBeforeTaggedOut = null;
              }
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // Helper function to convert base shorthand to full name
  String _getFullBaseName(String base) {
    switch (base) {
      case '1st':
        return 'first base';
      case '2nd':
        return 'second base';
      case '3rd':
        return 'third base';
      case 'Home':
        return 'home plate';
      case 'Tagged Out':
        return 'tagged out';
      default:
        return '$base base';
    }
  }

  // Celebration interface for celebration verbs
  Widget _buildCelebrationInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Celebration options section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Celebrating:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    _buildCelebrationChip('Scoring', 'Scoring'),
                    _buildCelebrationChip('Single', 'Single'),
                    _buildCelebrationChip('Double', 'Double'),
                    _buildCelebrationChip('Triple', 'Triple'),
                    _buildCelebrationChip('Home Run', 'Home Run'),
                    _buildCelebrationChip('Strikeout', 'Strikeout'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Custom celebration text field
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Or write custom celebration:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: customCelebrationController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'e.g., celebrates a walk-off hit',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade500),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      onTap: () {
                        // When text field is tapped, insert "celebrates " if empty
                        if (customCelebrationController.text.isEmpty) {
                          customCelebrationController.text = 'celebrates ';
                          customCelebrationController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset:
                                    customCelebrationController.text.length),
                          );
                          setState(() {
                            // Clear selected celebration chips when custom text is entered
                            _selectedCelebrationType = null;
                            _isCelebratingScoring = false;
                          });
                          _updateCaption();
                        }
                      },
                      onChanged: (value) {
                        setState(() {
                          // Clear selected celebration chips when custom text is entered
                          if (value.isNotEmpty) {
                            _selectedCelebrationType = null;
                            _isCelebratingScoring = false;
                          }
                        });
                        _updateCaption();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Inning section
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  // Dejection interface for dejection verbs
  Widget _buildDejectionInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Dejection options section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Dejection Type:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    _buildDejectionChip('Strikeout', 'Strikeout'),
                    _buildDejectionChip(
                        'Pitcher Taken Out', 'Pitcher Taken Out'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Custom dejection text field
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Or write custom dejection:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: customDejectionController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'e.g., reacts to a bad call',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade500),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      onTap: () {
                        // When text field is tapped, insert "reacts to " if empty
                        if (customDejectionController.text.isEmpty) {
                          customDejectionController.text = 'reacts to ';
                          customDejectionController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset: customDejectionController.text.length),
                          );
                          setState(() {
                            // Clear selected dejection chips when custom text is entered
                            _selectedDejectionType = null;
                          });
                          _updateCaption();
                        }
                      },
                      onChanged: (value) {
                        setState(() {
                          // Clear selected dejection chips when custom text is entered
                          if (value.isNotEmpty) {
                            _selectedDejectionType = null;
                          }
                        });
                        _updateCaption();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Inning section
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDejectionChip(String dejection, String label) {
    final isSelected = _selectedDejectionType == dejection;

    return GestureDetector(
      onTap: () {
        setState(() {
          // Clear custom dejection text when chips are selected
          customDejectionController.clear();

          if (isSelected) {
            _selectedDejectionType = null;
          } else {
            _selectedDejectionType = dejection;
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationChip(String celebration, String label) {
    bool isSelected;
    if (celebration == 'Scoring') {
      isSelected = _isCelebratingScoring;
    } else if (celebration == 'With Teammates') {
      isSelected = _isCelebratingWithTeammates;
    } else if (celebration == 'Hit') {
      isSelected = _selectedCelebrationType == celebration;
    } else {
      isSelected = _selectedCelebrationType == celebration;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          // Clear custom celebration text when chips are selected
          customCelebrationController.clear();

          if (celebration == 'Scoring') {
            _isCelebratingScoring = !_isCelebratingScoring;
          } else if (celebration == 'With Teammates') {
            _isCelebratingWithTeammates = !_isCelebratingWithTeammates;
          } else if (celebration == 'Hit') {
            // Navigate to hit submenu with celebration selected
            _selectedVerb = 'Hit';
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
          } else if (celebration == 'Single' ||
              celebration == 'Double' ||
              celebration == 'Triple' ||
              celebration == 'Home Run') {
            // Set up for hit type celebration - keep current inning selection
            _selectedVerb = celebration;
            _selectedActionVerb =
                celebration; // Also set action verb to ensure it's used
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
            _cameFromCelebration = true; // Mark that we came from celebration
            // Don't clear inning selection - let it carry over
          } else if (celebration == 'Strikeout') {
            // Handle strikeout as a simple celebration action
            _selectedVerb = 'Celebration'; // Keep in celebration interface
            _selectedActionVerb = celebration; // Set action verb to Strikeout
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
            // Don't navigate to submenu - stay in celebration interface
          } else {
            if (isSelected) {
              _selectedCelebrationType = null;
            } else {
              _selectedCelebrationType = celebration;
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // Practice interface for Batting Practice and Fielding Practice (no inning selection)
  Widget _buildPracticeInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Back button
        _buildVerbOptionsBackButton(),
      ],
    );
  }

  // National Anthem interface
  Widget _buildNationalAnthemInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Back button with compact action buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  // Pitching Change interface
  Widget _buildPitchingChangeInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Manager name input
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.10,
                      child: TextField(
                        controller: _managerNameController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Manager Name',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          hintText: 'Enter manager name...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: Colors.blue.shade400, width: 2),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _managerName = value;
                          });
                          _updateCaption();
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 80,
                      child: _buildReusableInningSelector(),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Protip: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text:
                                  'Select other players that are on the mound',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Back button
                    _buildVerbOptionsBackButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Add this new function right before _buildAtBatInterface()
  Widget _buildInningOnlyInterface() {
    // Check if this is a post-game verb that shouldn't show inning selector
    final isPostGameVerb =
        _selectedVerb == 'Post Game Win' || _selectedVerb == 'Post Game Loss';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Inning section with reusable widget (only for non-post-game verbs)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isPostGameVerb) ...[
                SizedBox(
                  height: 100, // Increased height to accommodate Prior button
                  child: _buildReusableInningSelector(),
                ),
              ],

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatchesSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected catch action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Catches',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDivingCatch = !_isDivingCatch;
                      if (_isDivingCatch) {
                        _selectedFieldingAction = 'Diving Catch';
                      } else {
                        _selectedFieldingAction = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isDivingCatch
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'Diving Catch',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroundballSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected groundball action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Groundball',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDivingCatch = !_isDivingCatch;
                      if (_isDivingCatch) {
                        _selectedFieldingAction = 'Diving Groundball';
                      } else {
                        _selectedFieldingAction = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isDivingCatch
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'Diving Play',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }
}
