import 'package:flutter/material.dart';
import '../services/mlb_api_service.dart';

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
  });

  @override
  State<PlayerPopupCaptionBoard> createState() =>
      _PlayerPopupCaptionBoardState();
}

class _PlayerPopupCaptionBoardState extends State<PlayerPopupCaptionBoard> {
  // Height calculation: 2 rows of buttons (22px each) + spacing (2px) + vertical padding (4px) + 3px buffer = 53px
  static const double _periodSelectorHeight = 53;
  final Set<Player> _selectedHomePlayers = {};
  final Set<Player> _selectedAwayPlayers = {};
  Player? _firstPlayerSelected;
  bool? _firstTeamSelectedIsHome;
  bool _showPlayoffOvertimes =
      false; // Track whether playoff OT periods are visible
  String? _selectedHeaderPeriod; // Track period selected from header bar
  final Set<String> _expandedCategories =
      {}; // Track which categories are expanded
  String?
      _expandedVerb; // Track which verb is expanded (format: "category_verb")
  VerbOption? _pendingVerb; // Store verb selected before players
  final Map<String, TextEditingController> _customVerbControllers = {};
  bool _showCustomVerbButtons =
      false; // Track if custom verb buttons should be shown
  // Search controllers for each team
  final TextEditingController _homeSearchController = TextEditingController();
  final TextEditingController _awaySearchController = TextEditingController();
  String _homeSearchText = '';
  String _awaySearchText = '';
  
  // Sort options (shared for both teams)
  String _sortBy = 'number'; // 'number', 'lastName', 'firstName'
  bool _sortAscending = true;
  
  // View style (shared for both teams)
  String _viewStyle = 'grid'; // 'grid' or 'list'

  // Verb categories matching the existing system
  final Map<String, List<VerbOption>> _verbCategories = {
    'Offense': [
      VerbOption('Skates', 'skates'),
      VerbOption('Shoots', 'shoots'),
      VerbOption('Battles', 'battles against', wantsOpponent: true),
      VerbOption('Scores', 'scores', wantsOpponent: true),
      VerbOption('Goes to the Net', 'goes to the net against',
          wantsOpponent: true),
      VerbOption('Faceoff', 'takes a faceoff', wantsOpponent: true),
    ],
    'Defense': [
      VerbOption('Blocks', 'blocks a shot'),
      VerbOption('Clears', 'clears the puck'),
      VerbOption('Checks', 'checks', wantsOpponent: true),
      VerbOption('Defends', 'defends', wantsOpponent: true),
      VerbOption('Penalty Kill', 'on the penalty kill'),
    ],
    'Goalie': [
      VerbOption('Saves', 'makes a save'),
      VerbOption('Handles the Puck', 'handles the puck'),
      VerbOption('Stands in Net', 'stands in net'),
      VerbOption('Guards the Net', 'guards the net'),
    ],
    'Non Game-Action': [
      VerbOption('Looks On', 'looks on'),
      VerbOption('Warm Ups', 'warms up prior to play'),
      VerbOption('Takes the Ice', 'takes the ice prior to play'),
      VerbOption('Walks to the Ice', 'walks to the ice'),
      VerbOption('Comes Off the Ice', 'comes off the ice'),
      VerbOption('National Anthem',
          'looks on during the national anthem prior to play'),
      VerbOption('Stretching', 'stretches prior to play'),
      VerbOption('Bench', 'on the bench'),
    ],
    'Reactions': [
      VerbOption('Celebrates', 'celebrates'),
      VerbOption('Celebrates a Goal', 'celebrates a goal'),
      VerbOption('Dejection', 'reacts with dejection'),
      VerbOption('Post Game Win', 'celebrates after the win'),
      VerbOption('Post Game Loss', 'reacts after the loss'),
    ],
  };

  void _selectPlayer(Player player, bool isHome) {
    final bool wasSelecting =
        !(isHome ? _selectedHomePlayers : _selectedAwayPlayers)
            .contains(player);

    setState(() {
      final Set<Player> targetSet =
          isHome ? _selectedHomePlayers : _selectedAwayPlayers;

      if (targetSet.contains(player)) {
        // Deselect player
        targetSet.remove(player);

        // Clear first player tracking if deselecting the first player
        if (_firstPlayerSelected == player) {
          _firstPlayerSelected = null;
          _firstTeamSelectedIsHome = null;

          // Set new first player if there are still players selected
          final allSelected = {
            ..._selectedHomePlayers,
            ..._selectedAwayPlayers
          };
          if (allSelected.isNotEmpty) {
            _firstPlayerSelected = allSelected.first;
            _firstTeamSelectedIsHome =
                _selectedHomePlayers.contains(_firstPlayerSelected);
          }
        }
      } else {
        // Select player
        targetSet.add(player);

        // Track first selection
        if (_firstPlayerSelected == null) {
          _firstPlayerSelected = player;
          _firstTeamSelectedIsHome = isHome;
        }
      }
    });

    // If a verb was pending and we just selected a player, generate caption
    // This ensures the verb is set when players are selected after a verb
    if (_pendingVerb != null && wasSelecting && _firstPlayerSelected != null) {
      final periodLabel = _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
      _confirmCaptionGeneration(_pendingVerb!, periodLabel);
      // Clear pending verb after using it so it doesn't interfere with future selections
      _pendingVerb = null;
    }

    widget.onSelectionChanged?.call(
      Set<Player>.from(_selectedHomePlayers),
      Set<Player>.from(_selectedAwayPlayers),
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
          _confirmCaptionGeneration(customVerb, periodLabel);
        }
      },
    );
  }

  /// Compact period selector for the header area (always visible)
  Widget _buildHeaderPeriodSelector() {
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
                              backgroundColor:
                                  isSelected ? Colors.blue.shade50 : Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    isSelected ? FontWeight.w600 : FontWeight.w500,
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
                    backgroundColor:
                        _showPlayoffOvertimes ? Colors.blue.shade50 : Colors.white,
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
                              backgroundColor:
                                  isSelected ? Colors.blue.shade50 : Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    isSelected ? FontWeight.w600 : FontWeight.w500,
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
      _firstPlayerSelected = null;
      _firstTeamSelectedIsHome = null;
      for (final controller in _customVerbControllers.values) {
        controller.clear();
      }
      _showCustomVerbButtons = false;
      _pendingVerb = null; // Clear pending verb
    });
    // Don't call onCustomVerbChanged here - it would trigger a caption rebuild
    // and overwrite the saved caption from metadata
    widget.onSelectionChanged?.call(
      const <Player>{},
      const <Player>{},
      null,
      null,
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
          // Header for verb list - now contains a permanent period selector
          Container(
            height: _periodSelectorHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: _buildHeaderPeriodSelector(),
          ),
          // Expandable verb categories
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ..._verbCategories.entries.map((entry) {
                  final isExpanded = _expandedCategories.contains(entry.key);
                  return Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      key: ValueKey('${entry.key}_$isExpanded'),
                      initiallyExpanded: isExpanded,
                      onExpansionChanged: (expanding) {
                        setState(() {
                          if (expanding) {
                            // If expanding, check if we already have 1 open
                            if (_expandedCategories.length >= 1) {
                              // Remove the first (oldest) expanded category
                              _expandedCategories
                                  .remove(_expandedCategories.first);
                            }
                            _expandedCategories.add(entry.key);
                          } else {
                            // If collapsing, just remove it
                            _expandedCategories.remove(entry.key);
                          }
                        });
                      },
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      minTileHeight: 24,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                          height: 1.0,
                        ),
                      ),
                      trailing: Icon(
                        Icons.expand_more,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      backgroundColor: Colors.grey.shade50,
                      collapsedBackgroundColor: Colors.grey.shade50,
                      children: entry.value.map((verb) {
                        final verbKey = '${entry.key}_${verb.label}';
                        final isExpanded = _expandedVerb == verbKey;

                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  // Store verb as pending
                                  _pendingVerb = verb;
                                  // Clear custom verb buttons when selecting a category verb
                                  _showCustomVerbButtons = false;

                                  // If players are already selected, generate caption immediately
                                  if (_selectedHomePlayers.isNotEmpty ||
                                      _selectedAwayPlayers.isNotEmpty) {
                                    _generateCaption(verb);
                                    // Clear pending verb after generating caption
                                    _pendingVerb = null;
                                  }

                                  // Toggle expansion/collapse
                                  if (_expandedVerb == verbKey) {
                                    _expandedVerb =
                                        null; // Collapse if already expanded
                                  } else {
                                    _expandedVerb =
                                        verbKey; // Expand this verb (closes any other)
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
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
                                child: Row(
                                  children: [
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        verb.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Show action buttons when expanded
                            if (isExpanded &&
                                (_selectedHomePlayers.isNotEmpty ||
                                    _selectedAwayPlayers.isNotEmpty))
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
                                    const SizedBox(
                                        width: 24), // Indent to match verb text
                                    Expanded(
                                      child: _buildActionButtonsRow(
                                          collapseOnAction: true),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }).toList(),
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
                      if (_showCustomVerbButtons &&
                          (_selectedHomePlayers.isNotEmpty ||
                              _selectedAwayPlayers.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        _buildActionButtonsRow(),
                      ],
                    ],
                  ),
                ),
              ],
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

  void _generateCaption(VerbOption verb) {
    // Generate caption immediately (period is already selected in header)
    final periodLabel = _getPeriodDisplayText(_selectedHeaderPeriod ?? '');
    _confirmCaptionGeneration(verb, periodLabel);
  }

  String _getPeriodDisplayText(String selection) {
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

  void _confirmCaptionGeneration(VerbOption verb, String period) {
    // If players are already selected, update verb via onCustomVerbChanged to preserve all selections
    final playerCount =
        _selectedHomePlayers.length + _selectedAwayPlayers.length;
    if (playerCount > 0 && widget.onCustomVerbChanged != null) {
      // Use custom verb callback to preserve all selected players
      // Pass the label (e.g., "Goes to the Net Against") instead of verbPhrase
      // so the switch statement in caption_fields_widget can match it correctly
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

    // Show brief confirmation
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
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerList(
    List<Player> players,
    String teamName,
    bool isHome,
    MaterialColor teamColor,
  ) {
    return Column(
      children: [
        // Team header
        Container(
          height: _periodSelectorHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                children: [
                  Icon(
                    isHome ? Icons.home : Icons.flight,
                    size: 14,
                    color: Colors.grey.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      teamName,
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
                mainAxisAlignment: MainAxisAlignment.start,
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
                        icon: Icon(Icons.arrow_drop_down, size: 13, color: Colors.grey.shade700),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                        items: ['number', 'lastName', 'firstName'].map((String value) {
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Search bar (half width)
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller:
                        isHome ? _homeSearchController : _awaySearchController,
                    onChanged: (value) {
                      setState(() {
                        if (isHome) {
                          _homeSearchText = value.toLowerCase();
                        } else {
                          _awaySearchText = value.toLowerCase();
                        }
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search players...',
                      hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      prefixIcon:
                          Icon(Icons.search, size: 14, color: Colors.grey.shade600),
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
              const double spacing = 8;
              const double padding = 10;

              // Calculate how many buttons fit in the available width
              final availableWidth = constraints.maxWidth - (2 * padding);
              final crossAxisCount =
                  ((availableWidth + spacing) / (buttonWidth + spacing))
                      .floor()
                      .clamp(1, 20);

              // Filter players based on search text
              final searchText = isHome ? _homeSearchText : _awaySearchText;
              List<Player> filteredPlayers = searchText.isEmpty
                  ? List.from(players)
                  : players.where((player) {
                      final name = player.fullName?.toLowerCase() ?? '';
                      final jersey = player.jerseyNumber?.toLowerCase() ?? '';
                      final displayName =
                          player.displayName?.toLowerCase() ?? '';
                      
                      // Check if search text is numeric - if so, do exact match on jersey number
                      final isNumeric = int.tryParse(searchText) != null;
                      if (isNumeric) {
                        return jersey == searchText;
                      }
                      
                      // For non-numeric searches, use contains for names
                      return name.contains(searchText) ||
                          displayName.contains(searchText);
                    }).toList();

              // Apply sorting (shared for both teams)
              final sortBy = _sortBy;
              final sortAscending = _sortAscending;
              final viewStyle = _viewStyle;
              
              filteredPlayers.sort((a, b) {
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
                  padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 4),
                  itemCount: filteredPlayers.length,
                  itemBuilder: (context, index) {
                    final player = filteredPlayers[index];
                    final isSelected =
                        (isHome ? _selectedHomePlayers : _selectedAwayPlayers)
                            .contains(player);
                    final isFirstPlayer = player == _firstPlayerSelected;

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

                    return InkWell(
                      onTap: () => _selectPlayer(player, isHome),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.blue.shade600
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            if (isFirstPlayer)
                              Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.orange,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(padding),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: buttonWidth / buttonHeight,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: filteredPlayers.length,
                itemBuilder: (context, index) {
                  final player = filteredPlayers[index];
                  final isSelected =
                      (isHome ? _selectedHomePlayers : _selectedAwayPlayers)
                          .contains(player);
                  final isFirstPlayer = player == _firstPlayerSelected;

                  return InkWell(
                    onTap: () => _selectPlayer(player, isHome),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue.shade400
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  player.jerseyNumber ?? '0',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.blue.shade700
                                        : Colors.grey.shade700,
                                    height: 1.0,
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  child: Text(
                                    _getLastName(player.fullName),
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: isSelected
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade600,
                                      height: 1.0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Red star for first player
                        if (isFirstPlayer)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                      ],
                    ),
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
    super.dispose();
  }
}

class VerbOption {
  final String label;
  final String verbPhrase;
  final bool wantsOpponent;

  VerbOption(
    this.label,
    this.verbPhrase, {
    this.wantsOpponent = false,
  });
}
