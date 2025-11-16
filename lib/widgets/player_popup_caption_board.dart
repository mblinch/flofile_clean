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
  final ValueChanged<String>? onPeriodChanged;
  final VoidCallback? onSaveIptc;
  final VoidCallback? onNextImage;
  final VoidCallback? onCopyMetadata;
  final VoidCallback? onFtp;
  final bool isFtpDisabled;

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
    this.onSaveIptc,
    this.onNextImage,
    this.onCopyMetadata,
    this.onFtp,
    this.isFtpDisabled = false,
  });

  @override
  State<PlayerPopupCaptionBoard> createState() =>
      _PlayerPopupCaptionBoardState();
}

class _PlayerPopupCaptionBoardState extends State<PlayerPopupCaptionBoard> {
  static const double _headerHeight = 44;
  final Set<Player> _selectedHomePlayers = {};
  final Set<Player> _selectedAwayPlayers = {};
  Player? _firstPlayerSelected;
  bool? _firstTeamSelectedIsHome;
  bool _showOvertimePeriods = false;
  bool _showPlayoffOvertimes = false; // Track whether playoff OT periods are visible
  Offset? _lastTapPosition;
  String? _selectedPeriodInDialog; // Track selected period in dialog
  String? _selectedHeaderPeriod; // Track period selected from header bar
  final Set<String> _expandedCategories = {}; // Track which categories are expanded
  final Map<String, TextEditingController> _customVerbControllers = {};

  // Verb categories matching the existing system
  final Map<String, List<VerbOption>> _verbCategories = {
    'Offense': [
      VerbOption('Skates', 'skates with the puck'),
      VerbOption('Shoots', 'shoots'),
      VerbOption('Battles', 'battles for the puck', wantsOpponent: true),
      VerbOption('Scores', 'scores', wantsOpponent: true),
      VerbOption('Goes to the Net Against', 'goes to the net against',
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
      enabled: hasPlayersSelected,
      decoration: InputDecoration(
        hintText: 'Type custom verb...',
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      style: const TextStyle(fontSize: 11),
      onChanged: (value) {
        if (!hasPlayersSelected) return;
        widget.onCustomVerbChanged?.call(value.trim());
      },
    );
  }

  Widget _buildPeriodQuickBar() {
    final List<String> quickPeriods = ['1st', '2nd', '3rd', 'OT', 'SO'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: quickPeriods.map((label) {
        return OutlinedButton(
          onPressed: () => _handlePeriodQuickSelect(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            side: BorderSide(color: Colors.grey.shade400),
            minimumSize: const Size(0, 32),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Compact period selector for the header area (always visible)
  Widget _buildHeaderPeriodSelector() {
    // Toggle between regular periods and playoff OT periods
    final List<String> displayPeriods = _showPlayoffOvertimes
        ? ['1OT', '2OT', '3OT', '4OT', '5OT']
        : ['1', '2', '3', 'OT', 'SO'];

    return Row(
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
        // Square buttons for periods (regular or playoff OT)
        Expanded(
          child: Row(
            children: displayPeriods.map(
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
        // Plus button to toggle playoff overtime periods
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
    );
  }

  void _handleHeaderPeriodSelect(String period) {
    setState(() {
      _selectedHeaderPeriod = period;
    });
    // Notify parent so CaptionFieldsWidget can track the hockey period
    widget.onPeriodChanged?.call(period);
  }

  void _handlePeriodQuickSelect(String label) {
    final hasPlayersSelected =
        _selectedHomePlayers.isNotEmpty || _selectedAwayPlayers.isNotEmpty;
    if (!hasPlayersSelected) return;

    final controller = _customVerbControllers['GLOBAL'];
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    _selectedPeriodInDialog = _mapQuickLabelToPeriod(label);
    _generateCaption(VerbOption(text, text));
  }

  String _mapQuickLabelToPeriod(String label) {
    switch (label) {
      case '1st':
        return '1';
      case '2nd':
        return '2';
      case '3rd':
        return '3';
      default:
        return label;
    }
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
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          // If expanding, check if we already have 2 open
                          if (_expandedCategories.length >= 2) {
                            // Remove the first (oldest) expanded category
                            _expandedCategories.remove(_expandedCategories.first);
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
                    collapsedBackgroundColor: Colors.white,
                    children: entry.value.asMap().entries.map((verbEntry) {
                      final index = verbEntry.key;
                      final verb = verbEntry.value;
                      return InkWell(
                        onTapDown: (details) {
                          _lastTapPosition = details.globalPosition;
                        },
                        onTap: (_selectedHomePlayers.isNotEmpty ||
                                _selectedAwayPlayers.isNotEmpty)
                            ? () => _generateCaption(verb)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (_selectedHomePlayers.isNotEmpty ||
                                    _selectedAwayPlayers.isNotEmpty)
                                ? Colors.white
                                : Colors.grey.shade50,
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
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  verb.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                    color: (_selectedHomePlayers.isNotEmpty ||
                                            _selectedAwayPlayers.isNotEmpty)
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              if (_selectedHomePlayers.isNotEmpty ||
                                  _selectedAwayPlayers.isNotEmpty)
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 10,
                                  color: Colors.grey.shade400,
                                ),
                            ],
                          ),
                        ),
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
                    const SizedBox(height: 12),
                    _buildPeriodQuickBar(),
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

  void _generateCaption(VerbOption verb) {
    // Show period selection dialog
    _showPeriodSelector(verb, _lastTapPosition);
  }

  void _showPeriodSelector(VerbOption verb, Offset? position) {
    _showOvertimePeriods = false;
    _selectedPeriodInDialog = null; // Reset period selection when dialog opens
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        final mediaQuery = MediaQuery.of(context);
        const double padding = 10;
        const double estimatedWidth = 190;
        final double estimatedHeight =
            _showOvertimePeriods ? 240 : 170; // rough estimate
        double left =
            (position?.dx ?? mediaQuery.size.width / 2) - estimatedWidth / 2;
        double top =
            (position?.dy ?? mediaQuery.size.height / 2) - estimatedHeight / 2;

        if (left < padding) left = padding;
        if (left + estimatedWidth > mediaQuery.size.width - padding) {
          left = mediaQuery.size.width - estimatedWidth - padding;
        }
        if (top < padding) top = padding;
        if (top + estimatedHeight > mediaQuery.size.height - padding) {
          top = mediaQuery.size.height - estimatedHeight - padding;
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: left,
                  top: top,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(4),
                    child: IntrinsicWidth(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Period',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => Navigator.of(dialogContext).pop(),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Period buttons column
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _buildPeriodButton('1', verb, setDialogState),
                                        const SizedBox(width: 4),
                                        _buildPeriodButton('2', verb, setDialogState),
                                        const SizedBox(width: 4),
                                        _buildPeriodButton('3', verb, setDialogState),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _buildPeriodButton('OT', verb, setDialogState),
                                        const SizedBox(width: 4),
                                        _buildPeriodButton('SO', verb, setDialogState),
                                        const SizedBox(width: 4),
                                        _buildPriorButton(verb, setDialogState),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    _buildOvertimeToggleButton(setDialogState),
                                    if (_showOvertimePeriods) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildPeriodButton('1OT', verb, setDialogState),
                                          const SizedBox(width: 4),
                                          _buildPeriodButton('2OT', verb, setDialogState),
                                          const SizedBox(width: 4),
                                          _buildPeriodButton('3OT', verb, setDialogState),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildPeriodButton('4OT', verb, setDialogState),
                                          const SizedBox(width: 4),
                                          _buildPeriodButton('5OT', verb, setDialogState),
                                          const SizedBox(width: 4),
                                          _buildPeriodButton('6OT', verb, setDialogState),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(width: 8),
                                // Action buttons column
                                SizedBox(
                                  width: 100,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Save button
                                      SizedBox(
                                        height: 49,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            widget.onSaveIptc?.call();
                                            Navigator.of(dialogContext).pop();
                                            widget.onNextImage?.call();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.grey.shade100,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            side: BorderSide(color: Colors.grey.shade400),
                                          ),
                                          child: Text(
                                            'Save →',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Copy button
                                      SizedBox(
                                        height: 49,
                                        child: ElevatedButton.icon(
                                          onPressed: widget.onCopyMetadata,
                                          icon: Icon(
                                            Icons.copy,
                                            size: 16,
                                            color: Colors.grey.shade700,
                                          ),
                                          label: Text(
                                            'Copy',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.grey.shade100,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            side: BorderSide(color: Colors.grey.shade400),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // FTP button
                                      SizedBox(
                                        height: 49,
                                        child: ElevatedButton.icon(
                                          onPressed: widget.isFtpDisabled ? null : widget.onFtp,
                                          icon: Icon(
                                            Icons.cloud_upload,
                                            size: 16,
                                            color: widget.isFtpDisabled
                                                ? Colors.grey.shade400
                                                : Colors.white,
                                          ),
                                          label: Text(
                                            'FTP',
                                            style: TextStyle(
                                              fontSize: 12,
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
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
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
                      ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPeriodButton(String period, VerbOption verb, Function setDialogState) {
    final isSelected = _selectedPeriodInDialog == period;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setDialogState(() {
            _handlePeriodSelection(verb, period);
          });
        },
        child: Container(
          width: 44,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 0.5,
            ),
          ),
          child: Text(
            period,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorButton(VerbOption verb, Function setDialogState) {
    final isSelected = _selectedPeriodInDialog == 'PRIOR';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setDialogState(() {
            _handlePeriodSelection(verb, 'PRIOR');
          });
        },
        child: Container(
          width: 44,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 0.5,
            ),
          ),
          child: Text(
            'Prior',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOvertimeToggleButton(
    void Function(void Function()) setDialogState,
  ) {
    return GestureDetector(
      onTap: () {
        setDialogState(() {
          _showOvertimePeriods = !_showOvertimePeriods;
        });
      },
      child: Container(
        width: 44,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              _showOvertimePeriods ? Colors.grey.shade400 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Icon(
          _showOvertimePeriods ? Icons.expand_less : Icons.expand_more,
          size: 18,
          color: _showOvertimePeriods ? Colors.white : Colors.grey.shade700,
        ),
      ),
    );
  }

  void _handlePeriodSelection(VerbOption verb, String selection) {
    setState(() {
      _selectedPeriodInDialog = selection;
    });
    // Don't close dialog - let user click Save or close manually
    final periodLabel = _getPeriodDisplayText(selection);
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
    // Pass the first selected player, verb, and period to the parent
    if (_firstPlayerSelected != null && widget.onCaptionGenerated != null) {
      widget.onCaptionGenerated!(
        _firstPlayerSelected!,
        verb.label,
        _firstTeamSelectedIsHome ?? true,
      );
    }

    // Show brief confirmation
    final playerCount =
        _selectedHomePlayers.length + _selectedAwayPlayers.length;
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

    return Row(
      children: [
        // Home team
        Expanded(
          flex: 3,
          child: _buildPlayerList(
            homePlayers,
            widget.homeTeamName ?? 'Home Team',
            true,
            Colors.grey,
          ),
        ),
        // Verb menu in the center
        SizedBox(
          width: 250,
          child: _buildVerbMenu(),
        ),
        // Away team
        Expanded(
          flex: 3,
          child: _buildPlayerList(
            awayPlayers,
            widget.awayTeamName ?? 'Away Team',
            false,
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
          height: _headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            teamName,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
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
              final crossAxisCount = ((availableWidth + spacing) / (buttonWidth + spacing)).floor().clamp(1, 20);
              
              return GridView.builder(
                padding: const EdgeInsets.all(padding),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: buttonWidth / buttonHeight,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: players.length,
                itemBuilder: (context, index) {
              final player = players[index];
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
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
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
                              padding: const EdgeInsets.symmetric(horizontal: 2),
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

  @override
  void dispose() {
    for (final controller in _customVerbControllers.values) {
      controller.dispose();
    }
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
