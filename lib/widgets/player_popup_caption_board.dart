import 'dart:async';
import 'package:flutter/material.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import '../utils/default_verb_keywords.dart';
import 'package:flutter/services.dart';
import '../services/mlb_api_service.dart';
import '../services/preferences_service.dart';

class PlayerPopupCaptionBoard extends StatefulWidget {
  final String? homeTeamName;
  final String? awayTeamName;
  final List<Player>? homeRoster;
  final List<Player>? awayRoster;
  final String? venue;
  final DateTime? gameDate;
  final String? period;
  final Map<String, dynamic>? metadata;
  final Function(Player player, String verb, bool isHome)? onCaptionGenerated;
  final void Function(
    Set<Player> homePlayers,
    Set<Player> awayPlayers,
    Player? firstPlayer,
    bool? firstIsHome,
  )? onSelectionChanged;
  final ValueChanged<String>? onCustomVerbChanged;
  final ValueChanged<String?>? onPeriodChanged;
  /// Baseball only: inning 1–9 (or null). Clears when Pre-Game/Post Game is chosen.
  final ValueChanged<int?>? onInningChanged;
  final VoidCallback? onSwitchTeams;
  final bool homeOnLeft; // Which team is on the left
  final VoidCallback? onSaveIptc;
  final VoidCallback? onNextImage;
  final VoidCallback? onCopyMetadata;
  final VoidCallback? onFtp;
  final bool isFtpDisabled;
  final Map<String, double>? uploadProgress;
  final String? currentImagePath;
  final Set<String>? queuedUploads;
  final Set<String>? currentlyUploading;
  /// When set, drives inning vs period label (e.g. baseball → "Inning").
  final String? sport;

  const PlayerPopupCaptionBoard({
    super.key,
    this.homeTeamName,
    this.awayTeamName,
    this.homeRoster,
    this.awayRoster,
    this.venue,
    this.gameDate,
    this.period,
    this.metadata,
    this.onCaptionGenerated,
    this.onSelectionChanged,
    this.onCustomVerbChanged,
    this.onPeriodChanged,
    this.onInningChanged,
    this.onSwitchTeams,
    this.homeOnLeft = true,
    this.onSaveIptc,
    this.onNextImage,
    this.onCopyMetadata,
    this.onFtp,
    this.isFtpDisabled = false,
    this.uploadProgress,
    this.currentImagePath,
    this.queuedUploads,
    this.currentlyUploading,
    this.sport,
  });

  @override
  State<PlayerPopupCaptionBoard> createState() =>
      _PlayerPopupCaptionBoardState();
}

class _PlayerPopupCaptionBoardState extends State<PlayerPopupCaptionBoard> {
  // Height calculation: 2 rows of buttons (22px each) + spacing (2px) + vertical padding (8px) + 3px buffer = 57px
  static const double _periodSelectorHeight = 57;
  final Set<Player> _selectedHomePlayers = {};
  final Set<Player> _selectedAwayPlayers = {};
  final Set<Player> _stickyHomePlayers = {}; // Sticky players that persist
  final Set<Player> _stickyAwayPlayers = {}; // Sticky players that persist
  Player? _firstPlayerSelected;
  bool? _firstTeamSelectedIsHome;
  bool _showPlayoffOvertimes =
      false; // Track whether playoff OT periods are visible
  /// Baseball: 0 = innings 1–9, 1 = 10–18, 2 = 19–27.
  int _baseballInningPage = 0;
  String? _selectedHeaderPeriod; // Track period selected from header bar
  String? _draggingCategory;
  String? _dragTargetCategory;
  Timer? _longPressTimer;
  String? _pendingDragCategory;
  final Map<String, GlobalKey> _categoryRowKeys = {};

  GlobalKey _rowKey(String cat) =>
      _categoryRowKeys.putIfAbsent(cat, () => GlobalKey());

  String? _findCategoryAtGlobalY(double y) {
    for (final cat in _categoryOrder) {
      final ctx = _categoryRowKeys[cat]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      if (y >= topLeft.dy && y <= topLeft.dy + box.size.height) return cat;
    }
    return null;
  }

  String? _categoryAtGlobalY(double y) {
    for (final cat in _categoryOrder) {
      final ctx = _categoryRowKeys[cat]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      if (y >= pos.dy && y < pos.dy + box.size.height) return cat;
    }
    return null;
  }
  final Set<String> _expandedCategories =
      {}; // Track which categories are expanded
  String?
      _expandedVerb; // Track which verb is expanded (format: "category_verb")
  VerbOption? _pendingVerb; // Store verb selected before players
  VerbOption?
      _stickyVerb; // Store verb that stays on until turned off (Cmd+click)
  String?
      _lastUsedVerbLabel; // Track the last verb that was used (for highlighting after save)
  final Map<String, TextEditingController> _customVerbControllers = {};
  bool _showCustomVerbButtons =
      false; // Track if custom verb buttons should be shown
  // Search controllers for each team
  final TextEditingController _homeSearchController = TextEditingController();
  final TextEditingController _awaySearchController = TextEditingController();
  String _homeSearchText = '';
  String _awaySearchText = '';

  // Number input controllers for quick player selection
  final TextEditingController _homeNumberController = TextEditingController();
  final TextEditingController _awayNumberController = TextEditingController();
  final List<String> _enteredHomeNumbers = [];
  final List<String> _enteredAwayNumbers = [];

  // Sort options (shared for both teams)
  String _sortBy = 'number'; // 'number', 'lastName', 'firstName'
  bool _sortAscending = true;

  // View style (shared for both teams)
  String _viewStyle = 'grid'; // 'grid' or 'list'

  // Favorites
  Set<String> _favoriteVerbs = {};
  PreferencesService? _preferencesService;

  // Custom verbs and overrides
  List<VerbOption> _customVerbs = [];
  Map<String, Map<String, dynamic>> _verbOverrides = {};
  Set<String> _deletedVerbs = {}; // Track deleted built-in verbs

  // Category order for drag-to-reorder
  List<String> _categoryOrder = [];

  final FocusNode _verbListFocusNode = FocusNode();

  // Verb categories matching the existing system
  final Map<String, List<VerbOption>> _verbCategories = {
    'Offense': [
      VerbOption('Skates', 'skates',
          keywords: defaultKeywordsForVerbLabel('Skates')),
      VerbOption('Shoots', 'shoots',
          keywords: defaultKeywordsForVerbLabel('Shoots')),
      VerbOption('Battles', 'battles against',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Battles')),
      VerbOption('Scores', 'scores',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Scores')),
      VerbOption('Goes to the Net', 'goes to the net against',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Goes to the Net')),
      VerbOption('Faceoff', 'takes a faceoff',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Faceoff')),
      VerbOption('Celebrates a Goal', 'celebrates a goal',
          keywords: defaultKeywordsForVerbLabel('Celebrates a Goal')),
      VerbOption('Celebrates', 'celebrates',
          keywords: defaultKeywordsForVerbLabel('Celebrates')),
    ],
    'Defense': [
      VerbOption('Blocks', 'blocks a shot',
          keywords: defaultKeywordsForVerbLabel('Blocks')),
      VerbOption('Clears', 'clears the puck',
          keywords: defaultKeywordsForVerbLabel('Clears')),
      VerbOption('Checks', 'checks',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Checks')),
      VerbOption('Defends', 'defends',
          wantsOpponent: true,
          keywords: defaultKeywordsForVerbLabel('Defends')),
    ],
    'Goalie': [
      VerbOption('Saves', 'makes a save',
          keywords: defaultKeywordsForVerbLabel('Saves')),
      VerbOption('Handles the Puck', 'handles the puck',
          keywords: defaultKeywordsForVerbLabel('Handles the Puck')),
      VerbOption('Stands in Net', 'stands in net',
          keywords: defaultKeywordsForVerbLabel('Stands in Net')),
      VerbOption('Guards the Net', 'guards the net',
          keywords: defaultKeywordsForVerbLabel('Guards the Net')),
    ],
    'Non Game-Action': [
      VerbOption('Looks On', 'looks on',
          keywords: defaultKeywordsForVerbLabel('Looks On')),
      VerbOption('Warm Ups', 'warms up prior to play',
          keywords: defaultKeywordsForVerbLabel('Warm Ups')),
      VerbOption('Takes the Ice', 'takes the ice prior to play',
          keywords: defaultKeywordsForVerbLabel('Takes the Ice')),
      VerbOption('Walks to the Ice', 'walks to the ice',
          keywords: defaultKeywordsForVerbLabel('Walks to the Ice')),
      VerbOption('Comes Off the Ice', 'comes off the ice',
          keywords: defaultKeywordsForVerbLabel('Comes Off the Ice')),
      VerbOption('National Anthem',
          'looks on during the national anthem prior to play',
          keywords: defaultKeywordsForVerbLabel('National Anthem')),
      VerbOption('Stretching', 'stretches prior to play',
          keywords: defaultKeywordsForVerbLabel('Stretching')),
      VerbOption('Bench', 'on the bench',
          keywords: defaultKeywordsForVerbLabel('Bench')),
      VerbOption('Post Game Win', 'celebrates',
          keywords: defaultKeywordsForVerbLabel('Post Game Win')),
      VerbOption('Post Game Loss', 'reacts',
          keywords: defaultKeywordsForVerbLabel('Post Game Loss')),
      VerbOption('Dejection', 'reacts with dejection',
          keywords: defaultKeywordsForVerbLabel('Dejection')),
    ],
  };

  void _selectPlayer(Player player, bool isHome) {
    // Check if Cmd/Ctrl key is pressed
    final isMetaPressed = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaRight) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlRight);

    final Set<Player> stickySet =
        isHome ? _stickyHomePlayers : _stickyAwayPlayers;
    final Set<Player> selectedSet =
        isHome ? _selectedHomePlayers : _selectedAwayPlayers;

    // Check if player was selected before (including sticky)
    final wasSelectingBefore =
        !selectedSet.contains(player) && !stickySet.contains(player);

    setState(() {
      if (isMetaPressed) {
        // Cmd+click: toggle sticky state
        if (stickySet.contains(player)) {
          // Remove from sticky
          stickySet.remove(player);
        } else {
          // Add to sticky
          stickySet.add(player);
          // Also add to selected if not already selected
          if (!selectedSet.contains(player)) {
            selectedSet.add(player);
          }
        }
      } else {
        // Normal click: toggle selection (but sticky players stay sticky)
        if (selectedSet.contains(player)) {
          // Only deselect if not sticky
          if (!stickySet.contains(player)) {
            selectedSet.remove(player);
          }
        } else {
          // Select player
          selectedSet.add(player);
        }
      }

      // Update first player tracking
      final allSelected = {
        ..._selectedHomePlayers,
        ..._selectedAwayPlayers,
        ..._stickyHomePlayers,
        ..._stickyAwayPlayers,
      };

      if (allSelected.isEmpty) {
        _firstPlayerSelected = null;
        _firstTeamSelectedIsHome = null;
      } else if (_firstPlayerSelected == null ||
          !allSelected.contains(_firstPlayerSelected)) {
        _firstPlayerSelected = allSelected.first;
        _firstTeamSelectedIsHome =
            _selectedHomePlayers.contains(_firstPlayerSelected) ||
                _stickyHomePlayers.contains(_firstPlayerSelected);
      }

      _syncEnteredNumbersFromSelection();
    });

    // Get merged selection (selected + sticky)
    final mergedHomePlayers = {..._selectedHomePlayers, ..._stickyHomePlayers};
    final mergedAwayPlayers = {..._selectedAwayPlayers, ..._stickyAwayPlayers};
    final mergedAllSelected = {...mergedHomePlayers, ...mergedAwayPlayers};

    // If a sticky verb is set and we just selected a player, generate caption with sticky verb
    if (_stickyVerb != null &&
        wasSelectingBefore &&
        mergedAllSelected.isNotEmpty) {
      final periodLabel = _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
      _confirmCaptionGeneration(_stickyVerb!, periodLabel);
    }
    // If a verb was pending and we just selected a player, generate caption
    // This ensures the verb is set when players are selected after a verb
    else if (_pendingVerb != null &&
        wasSelectingBefore &&
        mergedAllSelected.isNotEmpty) {
      final periodLabel = _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
      _confirmCaptionGeneration(_pendingVerb!, periodLabel);
      // Clear pending verb after using it so it doesn't interfere with future selections
      _pendingVerb = null;
    }

    widget.onSelectionChanged?.call(
      mergedHomePlayers,
      mergedAwayPlayers,
      _firstPlayerSelected,
      _firstTeamSelectedIsHome,
    );
  }

  Player? _findPlayerByNumber(String number, bool isHome) {
    final roster = isHome
        ? (widget.homeRoster ?? _getMockHomePlayers())
        : (widget.awayRoster ?? _getMockAwayPlayers());

    if (roster.isEmpty) return null;

    try {
      final jerseyNum = int.parse(number.trim());
      try {
        return roster.firstWhere(
          (player) => player.jerseyNumber == jerseyNum.toString(),
        );
      } catch (e) {
        // Try matching as string if int match fails
        try {
          return roster.firstWhere(
            (player) => player.jerseyNumber == number.trim(),
          );
        } catch (e2) {
          return null;
        }
      }
    } catch (e) {
      // If parsing fails, try to match as string
      try {
        return roster.firstWhere(
          (player) => player.jerseyNumber == number.trim(),
        );
      } catch (e2) {
        return null;
      }
    }
  }

  void _handleNumberInput(String value, bool isHome) {
    if (value.trim().isEmpty) return;

    final player = _findPlayerByNumber(value, isHome);
    if (player != null) {
      // _selectPlayer handles toggling selection automatically
      _selectPlayer(player, isHome);
    }
  }

  void _handleNumberInputList(String value, bool isHome) {
    final raw = value.trim();
    if (raw.isEmpty) return;

    final parts = raw.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty);
    for (final part in parts) {
      _handleNumberInput(part, isHome);
    }
  }

  void _syncEnteredNumbersFromSelection() {
    _enteredHomeNumbers
      ..clear()
      ..addAll(_collectUniqueNumbers(
          {..._selectedHomePlayers, ..._stickyHomePlayers}));
    _enteredAwayNumbers
      ..clear()
      ..addAll(_collectUniqueNumbers(
          {..._selectedAwayPlayers, ..._stickyAwayPlayers}));
  }

  List<String> _collectUniqueNumbers(Set<Player> players) {
    final numbers = <String>[];
    for (final player in players) {
      final jersey = (player.jerseyNumber ?? '').trim();
      if (jersey.isNotEmpty && !numbers.contains(jersey)) {
        numbers.add(jersey);
      }
    }
    return numbers;
  }

  Widget _buildNumberChips(bool isHome, {bool isCenter = false}) {
    final numbers = isHome ? _enteredHomeNumbers : _enteredAwayNumbers;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: numbers.map((number) {
        return GestureDetector(
          onTap: () => _removePlayerByNumber(number, isHome),
          child: Container(
            constraints: const BoxConstraints(minWidth: 24),
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: isHome ? Colors.grey.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Text(
              number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleSearchSubmit(bool isHome) {
    final controller = isHome ? _homeSearchController : _awaySearchController;
    final value = controller.text;
    if (value.trim().isEmpty) return;

    final tokens = value
        .toLowerCase()
        .split(RegExp(r'[,\s]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return;

    final roster = isHome
        ? (widget.homeRoster ?? _getMockHomePlayers())
        : (widget.awayRoster ?? _getMockAwayPlayers());

    bool hadAmbiguousName = false;
    bool processedAny = false;
    final nameSelections = <Player>[];

    for (final token in tokens) {
      final isNumeric = int.tryParse(token) != null;
      if (isNumeric) {
        _handleNumberInputList(token, isHome);
        processedAny = true;
        continue;
      }

      final matches = roster
          .where((player) => _isPlayerSearchMatch(player, token))
          .toList();
      if (matches.isEmpty) continue;
      processedAny = true;
      if (matches.length > 1) {
        hadAmbiguousName = true;
        continue;
      }

      nameSelections.add(matches.first);
    }

    if (nameSelections.isNotEmpty) {
      setState(() {
        final selectedSet =
            isHome ? _selectedHomePlayers : _selectedAwayPlayers;
        final stickySet = isHome ? _stickyHomePlayers : _stickyAwayPlayers;

        for (final player in nameSelections) {
          if (!selectedSet.contains(player) && !stickySet.contains(player)) {
            selectedSet.add(player);
          }
        }

        final allSelected = {
          ..._selectedHomePlayers,
          ..._selectedAwayPlayers,
          ..._stickyHomePlayers,
          ..._stickyAwayPlayers,
        };

        if (allSelected.isEmpty) {
          _firstPlayerSelected = null;
          _firstTeamSelectedIsHome = null;
        } else if (_firstPlayerSelected == null ||
            !allSelected.contains(_firstPlayerSelected)) {
          _firstPlayerSelected = allSelected.first;
          _firstTeamSelectedIsHome =
              _selectedHomePlayers.contains(_firstPlayerSelected) ||
                  _stickyHomePlayers.contains(_firstPlayerSelected);
        }

        _syncEnteredNumbersFromSelection();
      });

      final mergedHomePlayers = {
        ..._selectedHomePlayers,
        ..._stickyHomePlayers
      };
      final mergedAwayPlayers = {
        ..._selectedAwayPlayers,
        ..._stickyAwayPlayers
      };
      widget.onSelectionChanged?.call(
        mergedHomePlayers,
        mergedAwayPlayers,
        _firstPlayerSelected,
        _firstTeamSelectedIsHome,
      );
    }

    if (processedAny) {
      setState(() {
        controller.clear();
        if (isHome) {
          _homeSearchText = '';
        } else {
          _awaySearchText = '';
        }
      });
    }

    if (hadAmbiguousName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('More than one player selected in search term'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool _matchesJerseyNumber(Player player, String number) {
    final trimmed = number.trim();
    if (trimmed.isEmpty) return false;

    final jersey = (player.jerseyNumber ?? '').trim();
    if (jersey.isNotEmpty && jersey == trimmed) return true;

    final parsedInput = int.tryParse(trimmed);
    final parsedJersey = int.tryParse(jersey);
    if (parsedInput != null &&
        parsedJersey != null &&
        parsedInput == parsedJersey) {
      return true;
    }

    // Fallback: match against display name token like "#12"
    return player.displayName.contains('#$trimmed');
  }

  bool _isPlayerSearchMatch(Player player, String searchText) {
    if (searchText.isEmpty) return false;
    final tokens = searchText
        .toLowerCase()
        .split(RegExp(r'[,\s]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return false;

    final name = (player.fullName ?? '').toLowerCase();
    final jersey = (player.jerseyNumber ?? '').toLowerCase();
    final display = player.displayName.toLowerCase();

    for (final token in tokens) {
      final isNumeric = int.tryParse(token) != null;
      if (isNumeric) {
        if (jersey == token) return true;
      } else {
        if (name.contains(token) || display.contains(token)) return true;
      }
    }

    return false;
  }

  void _removePlayerByNumber(String number, bool isHome) {
    final trimmed = number.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      final selectedSet = isHome ? _selectedHomePlayers : _selectedAwayPlayers;
      final stickySet = isHome ? _stickyHomePlayers : _stickyAwayPlayers;

      selectedSet
          .removeWhere((player) => _matchesJerseyNumber(player, trimmed));
      stickySet.removeWhere((player) => _matchesJerseyNumber(player, trimmed));
      _syncEnteredNumbersFromSelection();

      final allSelected = {
        ..._selectedHomePlayers,
        ..._selectedAwayPlayers,
        ..._stickyHomePlayers,
        ..._stickyAwayPlayers,
      };

      if (allSelected.isEmpty) {
        _firstPlayerSelected = null;
        _firstTeamSelectedIsHome = null;
      } else if (_firstPlayerSelected != null &&
          !allSelected.contains(_firstPlayerSelected)) {
        _firstPlayerSelected = allSelected.first;
        _firstTeamSelectedIsHome =
            _selectedHomePlayers.contains(_firstPlayerSelected) ||
                _stickyHomePlayers.contains(_firstPlayerSelected);
      }
    });

    final mergedHomePlayers = {..._selectedHomePlayers, ..._stickyHomePlayers};
    final mergedAwayPlayers = {..._selectedAwayPlayers, ..._stickyAwayPlayers};
    widget.onSelectionChanged?.call(
      mergedHomePlayers,
      mergedAwayPlayers,
      _firstPlayerSelected,
      _firstTeamSelectedIsHome,
    );
  }

  Widget _buildGlobalCustomVerbInput() {
    final controller = _customVerbControllers.putIfAbsent(
      'GLOBAL',
      () => TextEditingController(),
    );
    final bool hasPlayersSelected =
        _selectedHomePlayers.isNotEmpty || _selectedAwayPlayers.isNotEmpty;
    return TextField(
      controller: controller,
      enabled:
          true, // Always enabled, but caption only generated if players selected
      decoration: InputDecoration(
        hintText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      style: const TextStyle(fontSize: 11),
      onChanged: (value) {
        if (!hasPlayersSelected) return;
        final hasText = value.trim().isNotEmpty;
        setState(() {
          _showCustomVerbButtons = hasText;
          // Collapse any expanded verb and clear pending verb when typing custom verb
          if (hasText) {
            _expandedVerb = null;
            _pendingVerb =
                null; // Clear pending category verb when using custom verb
          }
        });
        widget.onCustomVerbChanged?.call(value.trim());
        // Generate caption with custom verb when text is entered
        if (hasText) {
          final periodLabel =
              _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
          final customVerb = VerbOption(value.trim(), value.trim());
          _confirmCaptionGeneration(customVerb, periodLabel,
              showSnackBar: false);
        }
      },
    );
  }

  /// Baseball: innings 1–27 (paged by 9) + Pre-Game / Post Game (no hockey periods).
  Widget _buildBaseballInningHeaderSelector() {
    const double inningCellW = 26.0;
    final page = _baseballInningPage.clamp(0, 2);
    final startInning = page * 9 + 1;
    final inningLabels =
        List<String>.generate(9, (i) => '${startInning + i}');

    Widget inningButton(String label) {
      final isSelected = _selectedHeaderPeriod == label;
      final isWide = label == 'Pre-Game' || label == 'Post Game';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: isWide ? 58 : inningCellW,
          height: 22,
          child: OutlinedButton(
            onPressed: () => _handleHeaderPeriodSelect(label),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: isSelected
                    ? Colors.blue.shade500
                    : Colors.grey.shade400,
              ),
              backgroundColor:
                  isSelected ? Colors.blue.shade50 : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isWide ? 7.5 : 8.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.blue.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      );
    }

    Widget pageButton({
      required IconData icon,
      required bool enabled,
      required VoidCallback? onPressed,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: inningCellW,
          height: 22,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: enabled
                    ? Colors.grey.shade400
                    : Colors.grey.shade300,
              ),
              backgroundColor: enabled ? Colors.white : Colors.grey.shade100,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Icon(
              icon,
              size: 12,
              color: enabled
                  ? Colors.grey.shade700
                  : Colors.grey.shade400,
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Inning:',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                inningButton('Pre-Game'),
                ...inningLabels.map(inningButton),
                pageButton(
                  icon: Icons.remove,
                  enabled: page > 0,
                  onPressed: page > 0
                      ? () => setState(() {
                            _baseballInningPage =
                                (_baseballInningPage - 1).clamp(0, 2);
                          })
                      : null,
                ),
                pageButton(
                  icon: Icons.add,
                  enabled: page < 2,
                  onPressed: page < 2
                      ? () => setState(() {
                            _baseballInningPage =
                                (_baseballInningPage + 1).clamp(0, 2);
                          })
                      : null,
                ),
                inningButton('Post Game'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact period selector for the header area (always visible)
  Widget _buildHeaderPeriodSelector() {
    if (widget.sport?.toLowerCase() == 'baseball') {
      return _buildBaseballInningHeaderSelector();
    }
    // Toggle between regular periods and playoff OT periods
    final List<String> firstRowPeriods = _showPlayoffOvertimes
        ? ['1OT', '2OT', '3OT', '4OT', '5OT']
        : ['1', '2', '3', 'OT', 'SO'];

    // Second row always has Pre-Game and Post Game
    final List<String> secondRowPeriods = ['Pre-Game', 'Post Game'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // "Period:" label
            Text(
              'Period:',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(width: 6),
            // First row of period buttons (1, 2, 3, OT, SO or playoff OTs)
            Expanded(
              child: Row(
                children: firstRowPeriods.map(
                  (label) {
                    final bool isSelected = _selectedHeaderPeriod == label;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: SizedBox(
                          height: 22,
                          child: OutlinedButton(
                            onPressed: () => _handleHeaderPeriodSelect(label),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.blue.shade500
                                    : Colors.grey.shade400,
                              ),
                              backgroundColor: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
            const SizedBox(width: 4),
            // Plus button to toggle playoff overtime periods (on first row)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: SizedBox(
                width: 24,
                height: 22,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _showPlayoffOvertimes = !_showPlayoffOvertimes;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: _showPlayoffOvertimes
                          ? Colors.blue.shade500
                          : Colors.grey.shade400,
                    ),
                    backgroundColor: _showPlayoffOvertimes
                        ? Colors.blue.shade50
                        : Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: Icon(
                    _showPlayoffOvertimes ? Icons.remove : Icons.add,
                    size: 12,
                    color: _showPlayoffOvertimes
                        ? Colors.blue.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
        // Second row of period buttons (Pre-Game, Post Game)
        const SizedBox(height: 2),
        Row(
          children: [
            // Spacer to align with first row (accounting for "Period:" label width)
            SizedBox(
              width: 48, // Approximate width of "Period:" label + spacing
            ),
            Expanded(
              child: Row(
                children: secondRowPeriods.map(
                  (label) {
                    final bool isSelected = _selectedHeaderPeriod == label;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: SizedBox(
                          height: 22,
                          child: OutlinedButton(
                            onPressed: () => _handleHeaderPeriodSelect(label),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.blue.shade500
                                    : Colors.grey.shade400,
                              ),
                              backgroundColor: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
            // Spacer to match the plus button width on first row
            const SizedBox(width: 28),
          ],
        ),
      ],
    );
  }

  void _handleHeaderPeriodSelect(String period) {
    if (widget.sport?.toLowerCase() == 'baseball') {
      if (period == 'Pre-Game' || period == 'Post Game') {
        setState(() {
          _selectedHeaderPeriod =
              _selectedHeaderPeriod == period ? null : period;
        });
        widget.onPeriodChanged?.call(_selectedHeaderPeriod);
        widget.onInningChanged?.call(null);
        return;
      }
      final n = int.tryParse(period);
      if (n != null) {
        setState(() {
          _selectedHeaderPeriod =
              _selectedHeaderPeriod == period ? null : period;
        });
        final inning = int.tryParse(_selectedHeaderPeriod ?? '');
        widget.onInningChanged?.call(inning);
        widget.onPeriodChanged?.call(null);
      }
      return;
    }
    setState(() {
      // Toggle: if clicking the same period, deselect it (set to null)
      _selectedHeaderPeriod = _selectedHeaderPeriod == period ? null : period;
    });
    // Notify parent so CaptionFieldsWidget can track the hockey period
    // Pass null if deselecting, otherwise pass the period
    widget.onPeriodChanged?.call(_selectedHeaderPeriod);
  }

  Widget _buildSwitchTeamsButton() {
    return SizedBox(
      height: 18,
      width: 18,
      child: OutlinedButton(
        onPressed: () {
          print('DEBUG: Switch teams button pressed');
          widget.onSwitchTeams?.call();
        },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: Colors.grey.shade400),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        child: Icon(
          Icons.swap_horiz,
          size: 12,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  void resetSelections() {
    setState(() {
      _selectedHomePlayers.clear();
      _selectedAwayPlayers.clear();
      // Note: sticky players persist - they are not cleared
      _firstPlayerSelected = null;
      _firstTeamSelectedIsHome = null;
      _enteredHomeNumbers.clear();
      _enteredAwayNumbers.clear();
      for (final controller in _customVerbControllers.values) {
        controller.clear();
      }
      _showCustomVerbButtons = false;
      _pendingVerb = null; // Clear pending verb
    });
    // Don't call onCustomVerbChanged here - it would trigger a caption rebuild
    // and overwrite the saved caption from metadata
    // Include sticky players in the callback
    widget.onSelectionChanged?.call(
      Set<Player>.from(_stickyHomePlayers),
      Set<Player>.from(_stickyAwayPlayers),
      _stickyHomePlayers.isNotEmpty
          ? _stickyHomePlayers.first
          : (_stickyAwayPlayers.isNotEmpty ? _stickyAwayPlayers.first : null),
      _stickyHomePlayers.isNotEmpty ? true : null,
    );
  }

  Widget _buildVerbMenu() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade300, width: 1),
          right: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Player chips (row of buttons) first
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildNumberChips(true, isCenter: true)),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.grey.shade300,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
                Expanded(child: _buildNumberChips(false, isCenter: true)),
              ],
            ),
          ),
          // Period picker under the row of buttons
          Container(
            height: _periodSelectorHeight,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: _buildHeaderPeriodSelector(),
          ),
          // Expandable verb categories (Cmd+1..6 to expand category)
          Expanded(
            child: Listener(
              onPointerDown: (_) => _verbListFocusNode.requestFocus(),
              child: Focus(
                focusNode: _verbListFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final k = event.logicalKey;
                  int? digit;
                  if (k == LogicalKeyboardKey.digit1 ||
                      k == LogicalKeyboardKey.numpad1)
                    digit = 1;
                  else if (k == LogicalKeyboardKey.digit2 ||
                      k == LogicalKeyboardKey.numpad2)
                    digit = 2;
                  else if (k == LogicalKeyboardKey.digit3 ||
                      k == LogicalKeyboardKey.numpad3)
                    digit = 3;
                  else if (k == LogicalKeyboardKey.digit4 ||
                      k == LogicalKeyboardKey.numpad4)
                    digit = 4;
                  else if (k == LogicalKeyboardKey.digit5 ||
                      k == LogicalKeyboardKey.numpad5)
                    digit = 5;
                  else if (k == LogicalKeyboardKey.digit6 ||
                      k == LogicalKeyboardKey.numpad6) digit = 6;
                  if (digit == null) return KeyEventResult.ignored;
                  final isCmd = HardwareKeyboard.instance.isMetaPressed;
                  if (!isCmd) return KeyEventResult.ignored;
                  final d = digit!;
                  setState(() {
                    _expandedCategories.clear();
                    if (d == 1) {
                      _expandedCategories.add('Favorites');
                    } else if (d >= 2 &&
                        d <= 6 &&
                        _categoryOrder.length >= d - 1) {
                      _expandedCategories.add(_categoryOrder[d - 2]);
                    }
                  });
                  return KeyEventResult.handled;
                },
                child: _categoryOrder.isEmpty
                    ? const SizedBox() // Show nothing while loading
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          // Favorites category (always show first, not draggable)
                          Theme(
                            key: const ValueKey('Favorites'),
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              key: ValueKey(
                                  'Favorites_${_expandedCategories.contains('Favorites')}'),
                              initiallyExpanded:
                                  _expandedCategories.contains('Favorites'),
                              onExpansionChanged: (expanding) {
                                setState(() {
                                  if (expanding) {
                                    // If expanding, check if we already have 1 open
                                    if (_expandedCategories.length >= 1) {
                                      // Remove the first (oldest) expanded category
                                      _expandedCategories
                                          .remove(_expandedCategories.first);
                                    }
                                    _expandedCategories.add('Favorites');
                                  } else {
                                    // If collapsing, just remove it
                                    _expandedCategories.remove('Favorites');
                                  }
                                });
                              },
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                              minTileHeight: 24,
                              childrenPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Text(
                                    '1. Favorites',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.star,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                Icons.expand_more,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              backgroundColor: Colors.grey.shade50,
                              collapsedBackgroundColor: Colors.grey.shade50,
                              children: _getFavoriteVerbs().isEmpty
                                  ? [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          'No favorites yet. Right-click any verb to add it to favorites.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ]
                                  : _getFavoriteVerbs()
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((e) {
                                      final verb = e.value;
                                      final verbNumber = e.key + 1;
                                      final verbKey = 'Favorites_${verb.label}';
                                      final isExpanded =
                                          _expandedVerb == verbKey;
                                      final isLastUsed =
                                          _lastUsedVerbLabel == verb.label;
                                      final isSticky =
                                          _stickyVerb?.label == verb.label;

                                      return Column(
                                        children: [
                                          GestureDetector(
                                            onSecondaryTapDown: (details) {
                                              _showVerbContextMenu(context,
                                                  details.globalPosition, verb);
                                            },
                                            child: InkWell(
                                              onTap: () =>
                                                  _handleVerbTap(verb, verbKey),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSticky
                                                      ? Colors.orange.shade50
                                                      : Colors.white,
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color:
                                                          Colors.grey.shade200,
                                                      width: 0.5,
                                                    ),
                                                    left: isSticky
                                                        ? BorderSide(
                                                            color: Colors.orange
                                                                .shade400,
                                                            width: 3,
                                                          )
                                                        : BorderSide.none,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const SizedBox(width: 12),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 6),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 4,
                                                                vertical: 1),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .grey.shade500,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(3),
                                                        ),
                                                        child: Text(
                                                          '$verbNumber',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 9,
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (isSticky)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 4),
                                                        child: Icon(
                                                          Icons.push_pin,
                                                          size: 12,
                                                          color: Colors
                                                              .orange.shade700,
                                                        ),
                                                      ),
                                                    Expanded(
                                                      child: Text(
                                                        verb.label,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontSize: 11,
                                                          color: isSticky
                                                              ? Colors.orange
                                                                  .shade700
                                                              : Colors.grey
                                                                  .shade700,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isLastUsed)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 4),
                                                        child: Text(
                                                          '<- Last Used',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                      ),
                                                    Icon(
                                                      isExpanded
                                                          ? Icons.expand_less
                                                          : Icons.expand_more,
                                                      size: 14,
                                                      color:
                                                          Colors.grey.shade400,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Show action buttons when expanded OR when sticky verb is active
                                          // Check both regular selected players and sticky players
                                          if ((isExpanded || isSticky) &&
                                              (_selectedHomePlayers
                                                      .isNotEmpty ||
                                                  _selectedAwayPlayers
                                                      .isNotEmpty ||
                                                  _stickyHomePlayers
                                                      .isNotEmpty ||
                                                  _stickyAwayPlayers
                                                      .isNotEmpty))
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: Colors.grey.shade200,
                                                    width: 0.5,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  if (widget.onFtp != null)
                                                    TextButton(
                                                      onPressed:
                                                          widget.isFtpDisabled
                                                              ? null
                                                              : () {
                                                                  widget.onFtp
                                                                      ?.call();
                                                                  // Collapse expanded verb after FTP
                                                                  setState(() {
                                                                    _expandedVerb =
                                                                        null;
                                                                    _showCustomVerbButtons =
                                                                        false;
                                                                  });
                                                                },
                                                      style:
                                                          TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        minimumSize:
                                                            const Size(0, 24),
                                                        tapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                      child: const Text(
                                                        'FTP',
                                                        style: TextStyle(
                                                            fontSize: 10),
                                                      ),
                                                    ),
                                                  if (widget.onSaveIptc !=
                                                      null) ...[
                                                    const SizedBox(width: 4),
                                                    TextButton(
                                                      onPressed: () {
                                                        widget.onSaveIptc
                                                            ?.call();
                                                        // Collapse expanded verb after Save
                                                        setState(() {
                                                          _expandedVerb = null;
                                                          _showCustomVerbButtons =
                                                              false;
                                                        });
                                                      },
                                                      style:
                                                          TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        minimumSize:
                                                            const Size(0, 24),
                                                        tapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                      child: const Text(
                                                        'Save',
                                                        style: TextStyle(
                                                            fontSize: 10),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                        ],
                                      );
                                    }).toList(),
                            ),
                          ),
                          ..._categoryOrder.map((categoryName) {
                            if (!_verbCategories.containsKey(categoryName)) {
                              return SizedBox.shrink(
                                  key: ValueKey('missing_$categoryName'));
                            }
                            final isCatExpanded =
                                _expandedCategories.contains(categoryName);
                            final categoryIndex =
                                _categoryOrder.indexOf(categoryName);

                            // Build the verb list for this category.
                            final verbWidgets = [
                              ..._getVerbsForCategory(categoryName)
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final verb = e.value;
                                final verbNumber = e.key + 1;
                                final verbKey =
                                    '${categoryName}_${verb.label}';
                                final isVerbExpanded =
                                    _expandedVerb == verbKey;
                                final isLastUsed =
                                    _lastUsedVerbLabel == verb.label;
                                final isSticky =
                                    _stickyVerb?.label == verb.label;

                                return Column(
                                  key: ValueKey('verb_${verb.label}'),
                                  children: [
                                    GestureDetector(
                                      onSecondaryTapDown: (details) {
                                        _showVerbContextMenu(context,
                                            details.globalPosition, verb);
                                      },
                                      child: InkWell(
                                        onTap: () =>
                                            _handleVerbTap(verb, verbKey),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSticky
                                                ? Colors.orange.shade50
                                                : Colors.white,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                                width: 0.5,
                                              ),
                                              left: isSticky
                                                  ? BorderSide(
                                                      color: Colors
                                                          .orange.shade400,
                                                      width: 3,
                                                    )
                                                  : BorderSide.none,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 12),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        right: 6),
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.grey.shade500,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            3),
                                                  ),
                                                  child: Text(
                                                    '$verbNumber',
                                                    style: const TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (isSticky)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 4),
                                                  child: Icon(
                                                    Icons.push_pin,
                                                    size: 12,
                                                    color: Colors
                                                        .orange.shade700,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  verb.label,
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    fontSize: 11,
                                                    color: isSticky
                                                        ? Colors
                                                            .orange.shade700
                                                        : Colors
                                                            .grey.shade700,
                                                  ),
                                                ),
                                              ),
                                              if (isLastUsed)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 4),
                                                  child: Text(
                                                    '<- Last Used',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              Icon(
                                                isVerbExpanded
                                                    ? Icons.expand_less
                                                    : Icons.expand_more,
                                                size: 14,
                                                color: Colors.grey.shade400,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if ((isVerbExpanded || isSticky) &&
                                        (_selectedHomePlayers.isNotEmpty ||
                                            _selectedAwayPlayers.isNotEmpty ||
                                            _stickyHomePlayers.isNotEmpty ||
                                            _stickyAwayPlayers.isNotEmpty))
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 24),
                                            Expanded(
                                              child: _buildActionButtonsRow(
                                                  collapseOnAction: true),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              }),
                              // Add Verb button
                              InkWell(
                                onTap: () =>
                                    _showAddVerbDialog(categoryName),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.add,
                                          size: 14,
                                          color: Colors.blue.shade600),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Add New Verb',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ];

                            final isBeingDragged =
                                _draggingCategory == categoryName;
                            final isDragTarget =
                                _dragTargetCategory == categoryName &&
                                    !isBeingDragged;

                            return Container(
                              key: ValueKey('cat_$categoryName'),
                              decoration: BoxDecoration(
                                color: isBeingDragged
                                    ? Colors.blue.shade100
                                    : isDragTarget
                                        ? Colors.blue.shade50
                                        : Colors.grey.shade50,
                                border: Border(
                                  bottom: BorderSide(
                                      color: Colors.grey.shade200, width: 0.5),
                                  top: isDragTarget
                                      ? BorderSide(
                                          color: Colors.blue.shade400, width: 2)
                                      : BorderSide.none,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Raw Listener bypasses the gesture arena
                                  // entirely — pointer events fire before any
                                  // GestureDetector / InkWell can steal them.
                                  Listener(
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: (e) {
                                      _pendingDragCategory = categoryName;
                                      _longPressTimer?.cancel();
                                      _longPressTimer =
                                          Timer(const Duration(milliseconds: 500), () {
                                        setState(() {
                                          _draggingCategory = categoryName;
                                          _dragTargetCategory = categoryName;
                                        });
                                      });
                                    },
                                    onPointerMove: (e) {
                                      if (_draggingCategory != null) {
                                        final target =
                                            _categoryAtGlobalY(e.position.dy);
                                        if (target != null &&
                                            target != _dragTargetCategory) {
                                          setState(() =>
                                              _dragTargetCategory = target);
                                        }
                                      }
                                    },
                                    onPointerUp: (e) {
                                      _longPressTimer?.cancel();
                                      if (_draggingCategory != null &&
                                          _dragTargetCategory != null &&
                                          _draggingCategory !=
                                              _dragTargetCategory) {
                                        final from = _categoryOrder
                                            .indexOf(_draggingCategory!);
                                        final to = _categoryOrder
                                            .indexOf(_dragTargetCategory!);
                                        setState(() {
                                          _categoryOrder.removeAt(from);
                                          _categoryOrder.insert(
                                              to, _draggingCategory!);
                                          _draggingCategory = null;
                                          _dragTargetCategory = null;
                                        });
                                        _saveCategoryOrder();
                                      } else if (_draggingCategory == null) {
                                        // Short tap → expand / collapse
                                        setState(() {
                                          if (isCatExpanded) {
                                            _expandedCategories
                                                .remove(categoryName);
                                          } else {
                                            if (_expandedCategories
                                                .isNotEmpty) {
                                              _expandedCategories.remove(
                                                  _expandedCategories.first);
                                            }
                                            _expandedCategories
                                                .add(categoryName);
                                          }
                                        });
                                      } else {
                                        setState(() {
                                          _draggingCategory = null;
                                          _dragTargetCategory = null;
                                        });
                                      }
                                      _pendingDragCategory = null;
                                    },
                                    onPointerCancel: (_) {
                                      _longPressTimer?.cancel();
                                      _pendingDragCategory = null;
                                      setState(() {
                                        _draggingCategory = null;
                                        _dragTargetCategory = null;
                                      });
                                    },
                                    child: MouseRegion(
                                      cursor: _draggingCategory != null
                                          ? SystemMouseCursors.grabbing
                                          : SystemMouseCursors.grab,
                                      child: Container(
                                        key: _rowKey(categoryName),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        child: Opacity(
                                          opacity: isBeingDragged ? 0.5 : 1.0,
                                          child: Row(
                                            children: [
                                              Icon(Icons.drag_indicator,
                                                  size: 16,
                                                  color:
                                                      Colors.grey.shade400),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  '${categoryIndex + 2}. $categoryName',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color:
                                                        Colors.grey.shade800,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                isCatExpanded
                                                    ? Icons.expand_less
                                                    : Icons.expand_more,
                                                size: 16,
                                                color: Colors.grey.shade600,
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isCatExpanded) ...verbWidgets,
                                ],
                              ),
                            );
                          }).toList(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Custom Verb',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildGlobalCustomVerbInput(),
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 8),
                                // Upload progress monitor
                                _buildUploadMonitor(),
                                // Show action buttons when custom verb has text
                                // Check both regular selected players and sticky players
                                if (_showCustomVerbButtons &&
                                    (_selectedHomePlayers.isNotEmpty ||
                                        _selectedAwayPlayers.isNotEmpty ||
                                        _stickyHomePlayers.isNotEmpty ||
                                        _stickyAwayPlayers.isNotEmpty)) ...[
                                  const SizedBox(height: 8),
                                  _buildActionButtonsRow(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsRow({bool collapseOnAction = false}) {
    return Row(
      children: [
        // Save button
        Expanded(
          child: SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: () {
                widget.onSaveIptc?.call();
                widget.onNextImage?.call();
                // Always collapse the expanded verb menu and custom verb buttons when saving
                setState(() {
                  _expandedVerb = null;
                  _showCustomVerbButtons = false;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade100,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              child: Text(
                'Save →',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Copy button
        Expanded(
          child: SizedBox(
            height: 28,
            child: ElevatedButton.icon(
              onPressed: () {
                widget.onCopyMetadata?.call();
                // Always collapse the expanded verb menu and custom verb buttons when copying
                if (collapseOnAction) {
                  setState(() {
                    _expandedVerb = null;
                    _showCustomVerbButtons = false;
                  });
                }
              },
              icon: Icon(
                Icons.copy,
                size: 12,
                color: Colors.grey.shade700,
              ),
              label: Text(
                'Copy',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade100,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // FTP button
        Expanded(
          child: SizedBox(
            height: 28,
            child: ElevatedButton.icon(
              onPressed: widget.isFtpDisabled
                  ? null
                  : () {
                      widget.onFtp?.call();
                      // Always collapse the expanded verb menu and custom verb buttons when FTPing
                      if (collapseOnAction) {
                        setState(() {
                          _expandedVerb = null;
                          _showCustomVerbButtons = false;
                        });
                      }
                    },
              icon: Icon(
                Icons.cloud_upload,
                size: 12,
                color:
                    widget.isFtpDisabled ? Colors.grey.shade400 : Colors.white,
              ),
              label: Text(
                'FTP',
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isFtpDisabled
                      ? Colors.grey.shade400
                      : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isFtpDisabled
                    ? Colors.grey.shade300
                    : Colors.blue.shade600,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadMonitor() {
    // Always show the monitor section, but with different states
    final isQueued = widget.currentImagePath != null &&
        (widget.queuedUploads?.contains(widget.currentImagePath) ?? false);
    final isUploading = widget.currentImagePath != null &&
        (widget.currentlyUploading?.contains(widget.currentImagePath) ?? false);

    // Get progress value
    double? progress;
    String statusText = 'This picture has not been uploaded';
    bool showProgress = false;

    if (widget.currentImagePath != null && widget.uploadProgress != null) {
      progress = widget.uploadProgress![widget.currentImagePath];
    }

    if (isQueued && !isUploading) {
      statusText = 'Queued...';
      showProgress = true;
      progress = progress ?? 0.0;
    } else if (isUploading ||
        (progress != null && progress > 0 && progress < 1.0)) {
      statusText = 'Uploading...';
      showProgress = true;
      progress = progress ?? 0.0;
    } else if (progress != null && progress >= 1.0) {
      statusText = 'This picture has been uploaded.';
      showProgress = false;
    } else {
      statusText = 'This picture has not been uploaded';
      showProgress = false;
    }

    if (statusText == 'This picture has been uploaded.') {
      return const SizedBox.shrink();
    }

    // Determine colors based on state
    Color containerColor;
    Color borderColor;
    Color textColor;
    Color iconColor;

    if (statusText == 'This picture has been uploaded.') {
      containerColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      textColor = Colors.green.shade700;
      iconColor = Colors.green.shade700;
    } else if (statusText == 'This picture has not been uploaded') {
      containerColor = Colors.grey.shade50;
      borderColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
      iconColor = Colors.grey.shade600;
    } else {
      containerColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      textColor = Colors.blue.shade700;
      iconColor = Colors.blue.shade700;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                statusText == 'This picture has been uploaded.'
                    ? Icons.check_circle
                    : statusText == 'This picture has not been uploaded'
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_upload,
                size: 12,
                color: iconColor,
              ),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (showProgress && progress != null) ...[
                const Spacer(),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress != null && progress > 0
                  ? progress
                  : null, // Indeterminate if queued
              backgroundColor: Colors.blue.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(
                  statusText == 'This picture has been uploaded.'
                      ? Colors.green.shade600
                      : Colors.blue.shade600),
              minHeight: 4,
            ),
          ],
        ],
      ),
    );
  }

  void _handleVerbTap(VerbOption verb, String verbKey) {
    // Check if Cmd/Ctrl key is pressed
    final isMetaPressed = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.metaRight) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlRight);

    // Check if any players are selected (including sticky players)
    final hasAnyPlayers = _selectedHomePlayers.isNotEmpty ||
        _selectedAwayPlayers.isNotEmpty ||
        _stickyHomePlayers.isNotEmpty ||
        _stickyAwayPlayers.isNotEmpty;

    setState(() {
      if (isMetaPressed) {
        // Cmd+click: toggle sticky verb
        if (_stickyVerb?.label == verb.label) {
          // If clicking the same sticky verb, clear it
          _stickyVerb = null;
        } else {
          // Set as sticky verb
          _stickyVerb = verb;
          // Also generate caption if players are selected (including sticky players)
          if (hasAnyPlayers) {
            _generateCaption(verb);
          }
        }
      } else {
        // Normal click: use existing behavior
        // Clear any pinned verb when selecting a new verb normally
        if (_stickyVerb != null) {
          _stickyVerb = null;
        }
        // Store verb as pending
        _pendingVerb = verb;
        // Clear custom verb buttons when selecting a category verb
        _showCustomVerbButtons = false;

        // If players are already selected (including sticky players), generate caption immediately
        if (hasAnyPlayers) {
          _generateCaption(verb);
          // Clear pending verb after generating caption
          _pendingVerb = null;
        }
      }

      // Toggle expansion/collapse
      if (_expandedVerb == verbKey) {
        _expandedVerb = null; // Collapse if already expanded
      } else {
        _expandedVerb = verbKey; // Expand this verb (closes any other)
      }
    });
  }

  void _generateCaption(VerbOption verb) {
    // Generate caption immediately (period is already selected in header)
    final periodLabel = _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
    _confirmCaptionGeneration(verb, periodLabel);
  }

  String _ordinalSuffix(int n) {
    if (n <= 0) return '$n';
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

  String _getPeriodDisplayText(String selection) {
    if (widget.sport?.toLowerCase() == 'baseball') {
      final n = int.tryParse(selection);
      if (n != null && n >= 1 && n <= 27) {
        return '${_ordinalSuffix(n)} inning';
      }
    }
    switch (selection) {
      case '1':
        return '1st';
      case '2':
        return '2nd';
      case '3':
        return '3rd';
      case 'PRIOR':
        return 'Prior to game';
      default:
        return selection;
    }
  }

  void _confirmCaptionGeneration(VerbOption verb, String period,
      {bool showSnackBar = true}) {
    // Track the last used verb for highlighting after save
    setState(() {
      _lastUsedVerbLabel = verb.label;
    });

    // If players are already selected, update verb via onCustomVerbChanged to preserve all selections
    final playerCount =
        _selectedHomePlayers.length + _selectedAwayPlayers.length;
    if (playerCount > 0 && widget.onCustomVerbChanged != null) {
      // Use custom verb callback to preserve all selected players.
      // Pass [VerbOption.label] (may be an edited display name); caption_fields
      // resolves it to the built-in verb key via overrides so switch cases match.
      widget.onCustomVerbChanged!(verb.label);
    } else if (_firstPlayerSelected != null &&
        widget.onCaptionGenerated != null) {
      // Only use onCaptionGenerated if no players are selected yet (legacy behavior)
      widget.onCaptionGenerated!(
        _firstPlayerSelected!,
        verb.label,
        _firstTeamSelectedIsHome ?? true,
      );
    }

    // Show brief confirmation only if requested
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            playerCount == 1
                ? '${_firstPlayerSelected!.fullName} - ${verb.label} ($period)'
                : '$playerCount players - ${verb.label} ($period)',
          ),
          duration: const Duration(milliseconds: 800),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Load custom verbs first, then favorites (which needs custom verbs for migration)
    await _loadCustomVerbs();
    await _loadCategoryOrder();
    // Reset favorites (one-time reset requested by user)
    await _resetFavorites();
    await _loadFavorites();
  }

  Future<void> _loadCategoryOrder() async {
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }
    final order = await _preferencesService!.getCategoryOrder(sport: 'hockey');
    // Ensure all categories from _verbCategories are in the order
    final allCategories = _verbCategories.keys.toList();
    final orderedCategories = <String>[];

    // Add categories in saved order
    for (final cat in order) {
      if (allCategories.contains(cat) && !orderedCategories.contains(cat)) {
        orderedCategories.add(cat);
      }
    }

    // Add any missing categories at the end
    for (final cat in allCategories) {
      if (!orderedCategories.contains(cat)) {
        orderedCategories.add(cat);
      }
    }

    setState(() {
      _categoryOrder = orderedCategories;
    });
  }

  Future<void> _saveCategoryOrder() async {
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }
    await _preferencesService!
        .saveCategoryOrder(_categoryOrder, sport: 'hockey');
  }

  Future<void> _resetFavorites() async {
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }
    await _preferencesService!.saveFavoriteVerbs(<String>{}, sport: 'hockey');
    setState(() {
      _favoriteVerbs = <String>{};
    });
  }

  Future<void> _loadFavorites() async {
    _preferencesService = await PreferencesService.getInstance();
    final favorites =
        await _preferencesService!.getFavoriteVerbs(sport: 'hockey');

    // Migrate favorites from verbPhrase to label if needed
    final migratedFavorites = <String>{};
    final allVerbs = <VerbOption>[];
    for (final category in _verbCategories.values) {
      allVerbs.addAll(category);
    }

    // Also include custom verbs and overridden verbs
    allVerbs.addAll(_customVerbs);
    for (final override in _verbOverrides.values) {
      allVerbs.add(VerbOption.fromJson(override));
    }

    // Try to match each favorite by verbPhrase and convert to label
    for (final favorite in favorites) {
      // Check if it's already a label (by checking if any verb has this label)
      final foundByLabel = allVerbs.any((v) => v.label == favorite);
      if (foundByLabel) {
        // Already using label, keep it
        migratedFavorites.add(favorite);
      } else {
        // Try to find by verbPhrase and convert to label
        final foundVerb = allVerbs.firstWhere(
          (v) => v.verbPhrase == favorite,
          orElse: () => VerbOption('', ''),
        );
        if (foundVerb.label.isNotEmpty) {
          migratedFavorites.add(foundVerb.label);
        }
        // If not found, skip it (verb might have been deleted)
      }
    }

    // Save migrated favorites if they changed
    if (migratedFavorites != favorites) {
      await _preferencesService!
          .saveFavoriteVerbs(migratedFavorites, sport: 'hockey');
    }

    setState(() {
      _favoriteVerbs = migratedFavorites;
    });
  }

  Future<void> _toggleFavorite(VerbOption verb) async {
    // Ensure preferences service is loaded
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }

    final verbKey = verb
        .label; // Use label as unique identifier (more stable than verbPhrase)
    setState(() {
      if (_favoriteVerbs.contains(verbKey)) {
        _favoriteVerbs.remove(verbKey);
      } else {
        _favoriteVerbs.add(verbKey);
      }
    });

    // Save favorites
    await _preferencesService!
        .saveFavoriteVerbs(_favoriteVerbs, sport: 'hockey');
  }

  List<VerbOption> _getFavoriteVerbs() {
    // Get all verbs from all categories, applying overrides like _getVerbsForCategory does
    final allVerbs = <VerbOption>[];

    // Process each category to apply overrides
    for (final category in _verbCategories.keys) {
      final categoryVerbs = _getVerbsForCategory(category);
      allVerbs.addAll(categoryVerbs);
    }

    // Filter to only favorite verbs (using label as identifier)
    return allVerbs
        .where((verb) => _favoriteVerbs.contains(verb.label))
        .toList();
  }

  void _showVerbContextMenu(
      BuildContext context, Offset position, VerbOption verb) {
    final isFavorite = _favoriteVerbs.contains(verb.label);

    showAppContextMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'toggle_favorite',
          height: 32,
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.star : Icons.star_border,
                size: 16,
                color: isFavorite ? Colors.amber : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'edit_verb',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: 16,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Edit Verb',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete_verb',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.delete,
                size: 16,
                color: Colors.red.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete Verb',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'toggle_favorite') {
        _toggleFavorite(verb);
      } else if (value == 'edit_verb') {
        _showVerbEditorDialog(verb);
      } else if (value == 'delete_verb') {
        _showDeleteVerbConfirmation(context, verb);
      }
    });
  }

  void _showVerbEditorDialog(VerbOption verb, {String? targetCategory}) {
    // Look up the latest override data to ensure we show current values
    VerbOption effectiveVerb = verb;
    if (!verb.isCustom) {
      // For built-in verbs, check if there's an override saved
      final overrideData =
          _verbOverrides[verb.label] ?? _verbOverrides[verb.verbPhrase];
      if (overrideData != null) {
        effectiveVerb = VerbOption.fromJson(overrideData);
        if (effectiveVerb.keywords.isEmpty && verb.keywords.isNotEmpty) {
          effectiveVerb = effectiveVerb.copyWith(keywords: verb.keywords);
        }
      }
    }

    final labelController = TextEditingController(text: effectiveVerb.label);
    final singularController =
        TextEditingController(text: effectiveVerb.verbPhrase);
    final pluralController = TextEditingController(
        text: effectiveVerb.pluralPhrase ?? effectiveVerb.verbPhrase);
    bool usePluralPhrase = effectiveVerb.usePluralPhrase;
    bool wantsOpponent = effectiveVerb.wantsOpponent;
    bool omitAgainst = effectiveVerb.omitAgainst;
    bool removePlayerFromExample = false;
    String selectedCategory =
        targetCategory ?? verb.category ?? _verbCategories.keys.first;
    final keywordsController = TextEditingController(
        text: effectiveVerb.keywords.join(', '));
    bool showKeywordsEditor = effectiveVerb.keywords.isNotEmpty;

    // Get random players for example captions
    final homePlayers = widget.homeRoster ?? _getMockHomePlayers();
    final awayPlayers = widget.awayRoster ?? _getMockAwayPlayers();
    final homeTeamName = widget.homeTeamName ?? 'Home Team';
    final awayTeamName = widget.awayTeamName ?? 'Away Team';

    // Pick random players
    final random = DateTime.now().millisecondsSinceEpoch;
    final homePlayer1 = homePlayers.isNotEmpty
        ? homePlayers[random % homePlayers.length]
        : null;
    final homePlayer2 = homePlayers.length > 1
        ? homePlayers[(random + 1) % homePlayers.length]
        : null;
    final awayPlayer = awayPlayers.isNotEmpty
        ? awayPlayers[random % awayPlayers.length]
        : null;

    // Helper to build example caption
    // Uses omitAgainst setting to conditionally include "against"
    // Uses removePlayerFromExample to conditionally remove opposing player
    String buildExampleCaption(String verbPhrase, int playerCount) {
      final player1Name = homePlayer1?.fullName ?? 'Player One';
      final player2Name = homePlayer2?.fullName ?? 'Player Two';
      final opponentName = awayPlayer?.fullName ?? 'Opponent';
      final againstText = omitAgainst ? '' : ' against';

      if (removePlayerFromExample) {
        // Remove opposing player, just show "against the [team]"
        if (playerCount == 1) {
          return '$player1Name #${homePlayer1?.jerseyNumber ?? '00'} of the $homeTeamName $verbPhrase$againstText the $awayTeamName';
        } else {
          return '$player1Name #${homePlayer1?.jerseyNumber ?? '00'} and $player2Name #${homePlayer2?.jerseyNumber ?? '00'} of the $homeTeamName $verbPhrase$againstText the $awayTeamName';
        }
      } else {
        // Show full caption with opposing player
        if (playerCount == 1) {
          return '$player1Name #${homePlayer1?.jerseyNumber ?? '00'} of the $homeTeamName $verbPhrase$againstText $opponentName #${awayPlayer?.jerseyNumber ?? '00'} of the $awayTeamName';
        } else {
          return '$player1Name #${homePlayer1?.jerseyNumber ?? '00'} and $player2Name #${homePlayer2?.jerseyNumber ?? '00'} of the $homeTeamName $verbPhrase$againstText $opponentName #${awayPlayer?.jerseyNumber ?? '00'} of the $awayTeamName';
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: Colors.black, width: 1),
              ),
              child: Container(
                width: 500,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        verb.isCustom ? 'Edit Custom Verb' : 'Edit Verb',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Label field
                      Text(
                        'Display Name',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: labelController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'e.g., Skates',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Singular phrase field
                      Text(
                        'Singular Phrase (1 player)',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: singularController,
                        style: const TextStyle(fontSize: 12),
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'e.g., skates, battles, shoots',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Example with 1 player
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Example (1 player):',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              buildExampleCaption(singularController.text, 1),
                              style: TextStyle(
                                  fontSize: 10, color: Colors.blue.shade900),
                              softWrap: true,
                              overflow: TextOverflow.visible,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Plural phrase field
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Plural Phrase (2+ players)',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ),
                          Text(
                            'Use plural',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                          const SizedBox(width: 4),
                          AppCompactCheckbox(
                            value: usePluralPhrase,
                            onChanged: (v) {
                              setDialogState(() => usePluralPhrase = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: pluralController,
                        style: const TextStyle(fontSize: 12),
                        enabled: usePluralPhrase,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'e.g., skate, battle, shoot',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Example with 2+ players
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Example (2+ players):',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              buildExampleCaption(
                                  usePluralPhrase
                                      ? pluralController.text
                                      : singularController.text,
                                  2),
                              style: TextStyle(
                                  fontSize: 10, color: Colors.green.shade900),
                              softWrap: true,
                              overflow: TextOverflow.visible,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Keywords (comma-separated; IPTC-style tags for this verb)
                      Text(
                        'Keywords',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: showKeywordsEditor
                                ? TextField(
                                    controller: keywordsController,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      hintText:
                                          'e.g., pitch, pitcher, pitching (comma-separated)',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                      isDense: true,
                                    ),
                                  )
                                : Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey.shade50,
                                    ),
                                    child: Text(
                                      keywordsController.text.trim().isEmpty
                                          ? '—'
                                          : keywordsController.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: keywordsController.text
                                                .trim()
                                                .isEmpty
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 2),
                          Tooltip(
                            message: showKeywordsEditor
                                ? 'Hide keywords editor'
                                : 'Show keywords editor',
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                              icon: Icon(
                                showKeywordsEditor
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 22,
                                color: Colors.grey.shade700,
                              ),
                              onPressed: () => setDialogState(
                                  () => showKeywordsEditor =
                                      !showKeywordsEditor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Category dropdown
                      Text(
                        'Category',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCategory,
                            isExpanded: true,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade800),
                            items: _verbCategories.keys.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedCategory = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Omit "against" checkbox
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppCompactCheckbox(
                            value: omitAgainst,
                            onChanged: (value) {
                              setDialogState(() {
                                omitAgainst = value;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Omit "against" (e.g., "${singularController.text.isNotEmpty ? singularController.text : (verb.verbPhrase.isNotEmpty ? verb.verbPhrase : verb.label.toLowerCase())} player" instead of "${singularController.text.isNotEmpty ? singularController.text : (verb.verbPhrase.isNotEmpty ? verb.verbPhrase : verb.label.toLowerCase())} against player")',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade700),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Remove opposing player from example checkbox
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppCompactCheckbox(
                            value: removePlayerFromExample,
                            onChanged: (value) {
                              setDialogState(() {
                                removePlayerFromExample = value;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Remove opposing player from caption',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade700),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (verb.isCustom)
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _deleteCustomVerb(verb);
                              },
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red.shade600),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              print(
                                  'DEBUG: ========== SAVE BUTTON PRESSED ==========');
                              // First save, then close dialog
                              await _saveVerbEdit(
                                verb,
                                labelController.text,
                                singularController.text,
                                pluralController.text.isEmpty
                                    ? null
                                    : pluralController.text,
                                usePluralPhrase,
                                wantsOpponent,
                                omitAgainst,
                                parseVerbKeywordsField(
                                    keywordsController.text),
                                selectedCategory,
                              );
                              print('DEBUG: Save completed, closing dialog');
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0052CC),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                            child: const Text(
                              'Save',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveVerbEdit(
    VerbOption originalVerb,
    String newLabel,
    String newSingular,
    String? newPlural,
    bool usePluralPhrase,
    bool wantsOpponent,
    bool omitAgainst,
    List<String> newKeywords,
    String category,
  ) async {
    print('DEBUG: ========== _saveVerbEdit CALLED ==========');
    print('DEBUG: originalVerb.label = "${originalVerb.label}"');
    print('DEBUG: originalVerb.verbPhrase = "${originalVerb.verbPhrase}"');
    print('DEBUG: originalVerb.isCustom = ${originalVerb.isCustom}');
    print('DEBUG: newLabel = "$newLabel"');
    print('DEBUG: newSingular = "$newSingular"');
    print('DEBUG: newPlural = "$newPlural"');
    print('DEBUG: omitAgainst = $omitAgainst');
    print('DEBUG: category = "$category"');

    if (newLabel.isEmpty || newSingular.isEmpty) {
      print('DEBUG: RETURNING EARLY - newLabel or newSingular is empty!');
      return;
    }

    final newVerb = VerbOption(
      newLabel,
      newSingular,
      pluralPhrase: newPlural,
      usePluralPhrase: usePluralPhrase,
      keywords: newKeywords,
      wantsOpponent: wantsOpponent,
      omitAgainst: omitAgainst,
      isCustom: originalVerb.isCustom,
      category: category,
    );

    print('DEBUG: Created newVerb with verbPhrase = "${newVerb.verbPhrase}"');

    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
      print('DEBUG: Initialized _preferencesService');
    }

    // Check if label changed - if so, update favorites
    final labelChanged = originalVerb.label != newLabel;
    String? oldLabel;
    if (labelChanged) {
      oldLabel = originalVerb.label;
      print('DEBUG: Label changed from "$oldLabel" to "$newLabel"');
    }

    // Use the original label as the key for built-in verbs (more reliable than verbPhrase)
    final overrideKey =
        originalVerb.isCustom ? originalVerb.verbPhrase : originalVerb.label;
    print('DEBUG: overrideKey = "$overrideKey"');

    if (originalVerb.isCustom) {
      // Update custom verb
      print('DEBUG: Updating custom verb...');
      await _preferencesService!
          .removeCustomVerb(originalVerb.verbPhrase, sport: 'hockey');
      await _preferencesService!
          .addCustomVerb(newVerb.toJson(), sport: 'hockey');
      print('DEBUG: Custom verb updated');
    } else {
      // Save as override for built-in verb
      print('DEBUG: Saving verb override...');
      print('DEBUG: Saving override with key: "$overrideKey"');
      print('DEBUG: newVerb.toJson() = ${newVerb.toJson()}');
      await _preferencesService!.saveVerbOverride(
        overrideKey,
        newVerb.toJson(),
        sport: 'hockey',
      );

      // Verify it was saved
      final savedOverrides =
          await _preferencesService!.getVerbOverrides(sport: 'hockey');
      print('DEBUG: Verification - all saved overrides: $savedOverrides');
      print(
          'DEBUG: Verification - override for "$overrideKey": ${savedOverrides[overrideKey]}');
    }

    // Update favorites if label changed
    if (labelChanged && oldLabel != null) {
      if (_favoriteVerbs.contains(oldLabel)) {
        _favoriteVerbs.remove(oldLabel);
        _favoriteVerbs.add(newLabel);
        await _preferencesService!
            .saveFavoriteVerbs(_favoriteVerbs, sport: 'hockey');
      }
    }

    await _loadCustomVerbs();
    setState(() {});

    // If players are selected and this verb is currently being used, trigger caption update
    // Check if we have players selected and if the verb label matches what might be in use
    if ((_selectedHomePlayers.isNotEmpty || _selectedAwayPlayers.isNotEmpty) &&
        widget.onCustomVerbChanged != null) {
      // Trigger caption update with the new verb label to reload overrides and regenerate caption
      widget.onCustomVerbChanged!(newLabel);
    }
  }

  Future<void> _showDeleteVerbConfirmation(
      BuildContext context, VerbOption verb) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Verb'),
        content: Text(
            'Are you sure you want to delete "${verb.label}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteCustomVerb(verb);
    }
  }

  Future<void> _deleteCustomVerb(VerbOption verb) async {
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }

    if (verb.isCustom) {
      // Delete custom verb - try both verbPhrase and label to find it
      final customVerbs =
          await _preferencesService!.getCustomVerbs(sport: 'hockey');
      Map<String, dynamic>? verbToDelete;
      try {
        verbToDelete = customVerbs.firstWhere(
          (v) =>
              (v['verbPhrase'] as String?) == verb.verbPhrase ||
              (v['label'] as String?) == verb.label,
        );
      } catch (e) {
        // Verb not found, will try alternative deletion method
        verbToDelete = null;
      }

      if (verbToDelete != null && verbToDelete.isNotEmpty) {
        await _preferencesService!.removeCustomVerb(
          verbToDelete['verbPhrase'] as String,
          sport: 'hockey',
        );
      } else {
        // If not found as custom verb, try deleting by label as a fallback
        // This handles cases where the verb might be stored differently
        await _preferencesService!.addDeletedVerb(verb.label, sport: 'hockey');
      }
    } else {
      // Mark built-in verb as deleted - use original verbPhrase from built-in list
      // Find the original verb in the built-in list to get its original verbPhrase
      String? originalVerbPhrase;
      for (final category in _verbCategories.values) {
        try {
          final found = category.firstWhere(
            (v) => v.label == verb.label,
          );
          originalVerbPhrase = found.verbPhrase;
          break;
        } catch (e) {
          // Continue searching
        }
      }

      // If we found the original, use it; otherwise try verbPhrase, then label
      final deleteKey = originalVerbPhrase ?? verb.verbPhrase ?? verb.label;
      await _preferencesService!.addDeletedVerb(deleteKey, sport: 'hockey');
    }

    await _loadCustomVerbs();
    setState(() {});
  }

  Future<void> _loadCustomVerbs() async {
    print('DEBUG: ========== _loadCustomVerbs CALLED ==========');
    if (_preferencesService == null) {
      _preferencesService = await PreferencesService.getInstance();
    }

    // Load custom verbs from preferences
    final customVerbsJson =
        await _preferencesService!.getCustomVerbs(sport: 'hockey');
    _customVerbs =
        customVerbsJson.map((json) => VerbOption.fromJson(json)).toList();
    print('DEBUG: Loaded ${_customVerbs.length} custom verbs');

    // Load verb overrides
    _verbOverrides =
        await _preferencesService!.getVerbOverrides(sport: 'hockey');
    print(
        'DEBUG: Loaded ${_verbOverrides.length} verb overrides: ${_verbOverrides.keys.toList()}');
    for (final entry in _verbOverrides.entries) {
      print('DEBUG:   Override "${entry.key}": ${entry.value}');
    }

    // Load deleted verbs
    _deletedVerbs = await _preferencesService!.getDeletedVerbs(sport: 'hockey');
    print('DEBUG: Loaded ${_deletedVerbs.length} deleted verbs');
  }

  void _showAddVerbDialog(String category) {
    final newVerb = VerbOption(
      '',
      '',
      isCustom: true,
      category: category,
    );
    _showVerbEditorDialog(newVerb, targetCategory: category);
  }

  // Get all verbs for a category, including custom verbs and applying overrides
  List<VerbOption> _getVerbsForCategory(String category) {
    final builtInVerbs = _verbCategories[category] ?? [];

    // Apply overrides to built-in verbs and filter out deleted verbs
    // Check deletion by original verbPhrase, label, and overridden verbPhrase/label
    final processedBuiltIn = builtInVerbs
        .where((verb) =>
            !_deletedVerbs.contains(verb.verbPhrase) &&
            !_deletedVerbs.contains(verb.label))
        .map((verb) {
          // Check for override by BOTH verbPhrase AND label (to handle both key types)
          Map<String, dynamic>? overrideData;
          if (_verbOverrides.containsKey(verb.verbPhrase)) {
            overrideData = _verbOverrides[verb.verbPhrase];
          } else if (_verbOverrides.containsKey(verb.label)) {
            overrideData = _verbOverrides[verb.label];
          }

          if (overrideData != null) {
            final overriddenVerb = VerbOption.fromJson(overrideData);
            // Also check if the overridden verb's label or new verbPhrase is deleted
            if (_deletedVerbs.contains(overriddenVerb.verbPhrase) ||
                _deletedVerbs.contains(overriddenVerb.label)) {
              return null; // Skip this verb
            }
            return overriddenVerb;
          }
          return verb;
        })
        .whereType<VerbOption>()
        .toList();

    // Add custom verbs for this category (also filter out deleted custom verbs)
    // Check by both verbPhrase and label
    final customForCategory = _customVerbs
        .where((v) =>
            v.category == category &&
            !_deletedVerbs.contains(v.verbPhrase) &&
            !_deletedVerbs.contains(v.label))
        .toList();

    return [...processedBuiltIn, ...customForCategory];
  }

  @override
  Widget build(BuildContext context) {
    final homePlayers = widget.homeRoster ?? _getMockHomePlayers();
    final awayPlayers = widget.awayRoster ?? _getMockAwayPlayers();

    // Determine which team goes on left and right based on homeOnLeft
    final leftTeamPlayers = widget.homeOnLeft ? homePlayers : awayPlayers;
    final rightTeamPlayers = widget.homeOnLeft ? awayPlayers : homePlayers;
    final leftTeamName = widget.homeOnLeft
        ? (widget.homeTeamName ?? 'Home Team')
        : (widget.awayTeamName ?? 'Away Team');
    final rightTeamName = widget.homeOnLeft
        ? (widget.awayTeamName ?? 'Away Team')
        : (widget.homeTeamName ?? 'Home Team');
    final leftIsHome = widget.homeOnLeft;
    final rightIsHome = !widget.homeOnLeft;

    return Row(
      children: [
        // Left team (home or away depending on homeOnLeft)
        Expanded(
          flex: 3,
          child: _buildPlayerList(
            leftTeamPlayers,
            leftTeamName,
            leftIsHome,
            Colors.grey,
            isLeftSide: true,
          ),
        ),
        // Verb menu in the center
        SizedBox(
          width: 250,
          child: _buildVerbMenu(),
        ),
        // Right team (away or home depending on homeOnLeft)
        Expanded(
          flex: 3,
          child: _buildPlayerList(
            rightTeamPlayers,
            rightTeamName,
            rightIsHome,
            Colors.grey,
            isLeftSide: false,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerList(
    List<Player> players,
    String teamName,
    bool isHome,
    MaterialColor teamColor, {
    bool isLeftSide = false,
  }) {
    return Column(
      children: [
        // Team header
        Container(
          height: _periodSelectorHeight,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: isLeftSide
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: isLeftSide
                    ? [
                        _buildSwitchTeamsButton(),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isHome ? Icons.home : Icons.flight,
                                size: 14,
                                color: Colors.grey.shade800,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  teamName,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                    : [
                        Icon(
                          isHome ? Icons.home : Icons.flight,
                          size: 14,
                          color: Colors.grey.shade800,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            teamName,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Switch teams button on the right
                        _buildSwitchTeamsButton(),
                      ],
              ),
              const SizedBox(height: 4),
              // View style toggle, sort direction, and sort dropdown under team name
              Row(
                mainAxisAlignment: isLeftSide
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  // View style toggle (first) - shows "Grid" or "List" text with icon
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _viewStyle = _viewStyle == 'grid' ? 'list' : 'grid';
                      });
                    },
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _viewStyle == 'grid'
                                ? Icons.view_module
                                : Icons.view_list,
                            size: 12,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _viewStyle == 'grid' ? 'Grid' : 'List',
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
                  const SizedBox(width: 4),
                  // Sort direction toggle (always visible, after grid/list)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sortAscending = !_sortAscending;
                      });
                    },
                    child: Container(
                      height: 22,
                      width: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  // Sort dropdown (only show in list mode)
                  if (_viewStyle == 'list') ...[
                    const SizedBox(width: 4),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButton<String>(
                        value: _sortBy,
                        isDense: true,
                        underline: const SizedBox(),
                        icon: Icon(Icons.arrow_drop_down,
                            size: 13, color: Colors.grey.shade700),
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade700),
                        items: ['number', 'lastName', 'firstName']
                            .map((String value) {
                          String label;
                          switch (value) {
                            case 'number':
                              label = 'Number';
                              break;
                            case 'lastName':
                              label = 'Last Name';
                              break;
                            case 'firstName':
                              label = 'First Name';
                              break;
                            default:
                              label = value;
                          }
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _sortBy = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Search bar and options row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 28,
                child: TextField(
                  controller:
                      isHome ? _homeSearchController : _awaySearchController,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    setState(() {
                      if (isHome) {
                        _homeSearchText = value.toLowerCase();
                      } else {
                        _awaySearchText = value.toLowerCase();
                      }
                    });
                  },
                  onSubmitted: (_) => _handleSearchSubmit(isHome),
                  onEditingComplete: () => _handleSearchSubmit(isHome),
                  decoration: InputDecoration(
                    hintText: 'Type name(s) or number(s) followed by Enter',
                    hintStyle:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.dialpad_outlined,
                        size: 14, color: Colors.grey.shade600),
                    suffixIcon:
                        (isHome ? _homeSearchText : _awaySearchText).isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 14),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    if (isHome) {
                                      _homeSearchController.clear();
                                      _homeSearchText = '';
                                    } else {
                                      _awaySearchController.clear();
                                      _awaySearchText = '';
                                    }
                                  });
                                },
                              )
                            : null,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.blue.shade400),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        // Player grid
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Match period button dimensions (44x38)
              const double buttonWidth = 44;
              const double buttonHeight = 38;
              const double spacing = 4;
              const double padding = 10;

              // Note: crossAxisCount no longer needed - using Wrap for automatic layout

              // Search text for highlighting (do not filter the list)
              final searchText = isHome ? _homeSearchText : _awaySearchText;
              final displayPlayers = List<Player>.from(players);

              // Apply sorting (shared for both teams)
              final sortBy = _sortBy;
              final sortAscending = _sortAscending;
              final viewStyle = _viewStyle;

              displayPlayers.sort((a, b) {
                int comparison = 0;
                switch (sortBy) {
                  case 'number':
                    final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
                    final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
                    comparison = aNum.compareTo(bNum);
                    break;
                  case 'lastName':
                    final aLastName = _getLastName(a.fullName ?? '');
                    final bLastName = _getLastName(b.fullName ?? '');
                    comparison = aLastName.compareTo(bLastName);
                    break;
                  case 'firstName':
                    final aFirstName = _getFirstName(a.fullName ?? '');
                    final bFirstName = _getFirstName(b.fullName ?? '');
                    comparison = aFirstName.compareTo(bFirstName);
                    break;
                }
                return sortAscending ? comparison : -comparison;
              });

              // Return grid or list view based on view style
              if (viewStyle == 'list') {
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: padding, vertical: 4),
                  itemCount: displayPlayers.length,
                  itemBuilder: (context, index) {
                    final player = displayPlayers[index];
                    final stickySet =
                        isHome ? _stickyHomePlayers : _stickyAwayPlayers;
                    final selectedSet =
                        isHome ? _selectedHomePlayers : _selectedAwayPlayers;
                    final isSticky = stickySet.contains(player);
                    final isSelected = selectedSet.contains(player) || isSticky;
                    final isFirstPlayer = player == _firstPlayerSelected;
                    final isSearchMatch =
                        _isPlayerSearchMatch(player, searchText);

                    // Format player name based on sort option
                    String displayName;
                    final jerseyNumber = player.jerseyNumber ?? '0';
                    final fullName = player.fullName ?? '';
                    final firstName = _getFirstName(fullName);
                    final lastName = _getLastName(fullName);

                    if (sortBy == 'lastName') {
                      displayName = '$lastName, $firstName #$jerseyNumber';
                    } else if (sortBy == 'firstName') {
                      displayName = '$firstName $lastName #$jerseyNumber';
                    } else {
                      // number sort - show number first
                      displayName = '#$jerseyNumber $fullName';
                    }

                    final shouldDim = searchText.isNotEmpty &&
                        !isSearchMatch &&
                        !isSelected &&
                        !isSticky;
                    return InkWell(
                      onTap: () => _selectPlayer(player, isHome),
                      child: Opacity(
                        opacity: shouldDim ? 0.5 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: isSearchMatch && !isSelected && !isSticky
                              ? BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                )
                              : null,
                          child: Row(
                            children: [
                              // First player indicator on left for left side
                              if (isFirstPlayer && isLeftSide)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              // Sticky player pin icon
                              if (isSticky)
                                Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 10,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  displayName,
                                  textAlign: isLeftSide
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSticky
                                        ? Colors.orange.shade700
                                        : (isSelected
                                            ? Colors.grey.shade700
                                            : (isSearchMatch
                                                ? Colors.blueGrey.shade700
                                                : Colors.grey.shade600)),
                                  ),
                                ),
                              ),
                              // First player indicator on right for right side
                              if (isFirstPlayer && !isLeftSide)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }

              // Group players by jersey number ranges (0-9, 10-19, 20-29, etc.)
              final Map<int, List<Player>> groupedPlayers = {};
              for (final player in displayPlayers) {
                final jerseyNum =
                    int.tryParse(player.jerseyNumber ?? '999') ?? 999;
                final range = (jerseyNum ~/ 10) *
                    10; // Group by tens (0, 10, 20, 30, etc.)
                groupedPlayers.putIfAbsent(range, () => []).add(player);
              }

              // Sort ranges and players within each range
              final sortedRanges = groupedPlayers.keys.toList()..sort();
              for (final range in sortedRanges) {
                groupedPlayers[range]!.sort((a, b) {
                  final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
                  final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
                  return aNum.compareTo(bNum);
                });
              }

              return ListView.builder(
                padding: const EdgeInsets.all(padding),
                itemCount: sortedRanges.length,
                itemBuilder: (context, rangeIndex) {
                  final range = sortedRanges[rangeIndex];
                  final playersInRange = groupedPlayers[range]!;

                  return Column(
                    crossAxisAlignment: isLeftSide
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      // Players in this range
                      Wrap(
                        alignment: isLeftSide
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        spacing: spacing,
                        runSpacing: spacing,
                        children: playersInRange.map((player) {
                          final stickySet =
                              isHome ? _stickyHomePlayers : _stickyAwayPlayers;
                          final selectedSet = isHome
                              ? _selectedHomePlayers
                              : _selectedAwayPlayers;
                          final isSticky = stickySet.contains(player);
                          final isSelected =
                              selectedSet.contains(player) || isSticky;
                          final isFirstPlayer = player == _firstPlayerSelected;
                          final isSearchMatch =
                              _isPlayerSearchMatch(player, searchText);
                          final shouldDim = searchText.isNotEmpty &&
                              !isSearchMatch &&
                              !isSelected &&
                              !isSticky;

                          return SizedBox(
                            width: buttonWidth,
                            height: buttonHeight,
                            child: InkWell(
                              onTap: () => _selectPlayer(player, isHome),
                              child: Opacity(
                                opacity: shouldDim ? 0.5 : 1,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isSticky
                                              ? Colors.orange.shade50
                                              : (isSelected
                                                  ? (isHome
                                                      ? Colors.grey.shade100
                                                      : Colors.white)
                                                  : (isSearchMatch
                                                      ? Colors.blueGrey.shade50
                                                      : Colors.white)),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSticky
                                                ? Colors.orange.shade400
                                                : (isSelected
                                                    ? Colors.grey.shade400
                                                    : (isSearchMatch
                                                        ? Colors
                                                            .blueGrey.shade200
                                                        : Colors
                                                            .grey.shade300)),
                                            width: (isSelected || isSticky)
                                                ? 2
                                                : 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 2,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              player.jerseyNumber ?? '0',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: isSticky
                                                    ? Colors.orange.shade700
                                                    : (isSelected
                                                        ? Colors.grey.shade700
                                                        : Colors.grey.shade700),
                                                height: 1.0,
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 2),
                                              child: Text(
                                                _getLastName(player.fullName),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: isSticky
                                                      ? Colors.orange.shade600
                                                      : (isSelected
                                                          ? Colors.grey.shade700
                                                          : Colors
                                                              .grey.shade600),
                                                  height: 1.0,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Blue circle for first player
                                    if (isFirstPlayer)
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    // Pin icon for sticky player
                                    if (isSticky)
                                      Positioned(
                                        top: 2,
                                        left: 2,
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 10,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      // Add spacing between ranges
                      if (rangeIndex < sortedRanges.length - 1)
                        const SizedBox(height: spacing),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<Player> _getMockHomePlayers() {
    return [
      Player(
          fullName: 'Connor McDavid',
          firstName: 'Connor',
          jerseyNumber: '97',
          displayName: 'Connor McDavid'),
      Player(
          fullName: 'Leon Draisaitl',
          firstName: 'Leon',
          jerseyNumber: '29',
          displayName: 'Leon Draisaitl'),
      Player(
          fullName: 'Ryan Nugent-Hopkins',
          firstName: 'Ryan',
          jerseyNumber: '93',
          displayName: 'Ryan Nugent-Hopkins'),
      Player(
          fullName: 'Zach Hyman',
          firstName: 'Zach',
          jerseyNumber: '18',
          displayName: 'Zach Hyman'),
      Player(
          fullName: 'Evan Bouchard',
          firstName: 'Evan',
          jerseyNumber: '2',
          displayName: 'Evan Bouchard'),
      Player(
          fullName: 'Stuart Skinner',
          firstName: 'Stuart',
          jerseyNumber: '74',
          displayName: 'Stuart Skinner'),
      Player(
          fullName: 'Darnell Nurse',
          firstName: 'Darnell',
          jerseyNumber: '25',
          displayName: 'Darnell Nurse'),
      Player(
          fullName: 'Mattias Ekholm',
          firstName: 'Mattias',
          jerseyNumber: '14',
          displayName: 'Mattias Ekholm'),
    ];
  }

  List<Player> _getMockAwayPlayers() {
    return [
      Player(
          fullName: 'Auston Matthews',
          firstName: 'Auston',
          jerseyNumber: '34',
          displayName: 'Auston Matthews'),
      Player(
          fullName: 'Mitch Marner',
          firstName: 'Mitch',
          jerseyNumber: '16',
          displayName: 'Mitch Marner'),
      Player(
          fullName: 'William Nylander',
          firstName: 'William',
          jerseyNumber: '88',
          displayName: 'William Nylander'),
      Player(
          fullName: 'John Tavares',
          firstName: 'John',
          jerseyNumber: '91',
          displayName: 'John Tavares'),
      Player(
          fullName: 'Morgan Rielly',
          firstName: 'Morgan',
          jerseyNumber: '44',
          displayName: 'Morgan Rielly'),
      Player(
          fullName: 'Joseph Woll',
          firstName: 'Joseph',
          jerseyNumber: '60',
          displayName: 'Joseph Woll'),
      Player(
          fullName: 'Max Domi',
          firstName: 'Max',
          jerseyNumber: '11',
          displayName: 'Max Domi'),
      Player(
          fullName: 'TJ Brodie',
          firstName: 'TJ',
          jerseyNumber: '78',
          displayName: 'TJ Brodie'),
    ];
  }

  String _getLastName(String fullName) {
    final parts = fullName.split(' ');
    return parts.length > 1 ? parts.last : fullName;
  }

  String _getFirstName(String fullName) {
    final parts = fullName.split(' ');
    return parts.isNotEmpty ? parts.first : fullName;
  }

  @override
  void dispose() {
    for (final controller in _customVerbControllers.values) {
      controller.dispose();
    }
    _homeSearchController.dispose();
    _awaySearchController.dispose();
    _homeNumberController.dispose();
    _awayNumberController.dispose();
    _verbListFocusNode.dispose();
    super.dispose();
  }
}

class VerbOption {
  final String label;
  final String verbPhrase; // Used as singular phrase
  final String?
      pluralPhrase; // Phrase for multiple players (null = same as singular)
  /// When false, captions always use [verbPhrase] even with 2+ players.
  final bool usePluralPhrase;
  /// IPTC-style search terms for this verb (comma-separated in editors).
  final List<String> keywords;
  final bool wantsOpponent;
  final bool omitAgainst; // If true, don't include "against" in caption
  final bool isCustom;
  final String? category; // Category this verb belongs to

  VerbOption(
    this.label,
    this.verbPhrase, {
    this.pluralPhrase,
    this.usePluralPhrase = true,
    List<String>? keywords,
    this.wantsOpponent = false,
    this.omitAgainst = false,
    this.isCustom = false,
    this.category,
  }) : keywords = keywords ?? const [];

  // Get the appropriate phrase based on player count
  String getPhraseForPlayerCount(int count) {
    if (!usePluralPhrase) return verbPhrase;
    if (count > 1 &&
        pluralPhrase != null &&
        pluralPhrase!.isNotEmpty) {
      return pluralPhrase!;
    }
    return verbPhrase;
  }

  // Create a copy with modifications
  VerbOption copyWith({
    String? label,
    String? verbPhrase,
    String? pluralPhrase,
    bool? usePluralPhrase,
    List<String>? keywords,
    bool? wantsOpponent,
    bool? omitAgainst,
    bool? isCustom,
    String? category,
  }) {
    return VerbOption(
      label ?? this.label,
      verbPhrase ?? this.verbPhrase,
      pluralPhrase: pluralPhrase ?? this.pluralPhrase,
      usePluralPhrase: usePluralPhrase ?? this.usePluralPhrase,
      keywords: keywords ?? this.keywords,
      wantsOpponent: wantsOpponent ?? this.wantsOpponent,
      omitAgainst: omitAgainst ?? this.omitAgainst,
      isCustom: isCustom ?? this.isCustom,
      category: category ?? this.category,
    );
  }

  // Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'verbPhrase': verbPhrase,
      'pluralPhrase': pluralPhrase,
      'usePluralPhrase': usePluralPhrase,
      'keywords': keywords,
      'wantsOpponent': wantsOpponent,
      'omitAgainst': omitAgainst,
      'isCustom': isCustom,
      'category': category,
    };
  }

  // Create from JSON
  factory VerbOption.fromJson(Map<String, dynamic> json) {
    return VerbOption(
      json['label'] as String,
      json['verbPhrase'] as String,
      pluralPhrase: json['pluralPhrase'] as String?,
      usePluralPhrase: json['usePluralPhrase'] as bool? ?? true,
      keywords: verbKeywordsFromJson(json['keywords']),
      wantsOpponent: json['wantsOpponent'] as bool? ?? false,
      omitAgainst: json['omitAgainst'] as bool? ?? false,
      isCustom: json['isCustom'] as bool? ?? true,
      category: json['category'] as String?,
    );
  }
}
