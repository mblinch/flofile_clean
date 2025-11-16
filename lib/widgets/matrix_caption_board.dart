import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mlb_api_service.dart';

class MatrixCaptionBoard extends StatefulWidget {
  final String? homeTeamName;
  final String? awayTeamName;
  final String? homeTeamAbbr;
  final String? awayTeamAbbr;
  final List<Player>? homeRoster;
  final List<Player>? awayRoster;
  final String? venue;
  final DateTime? gameDate;
  final String? period;
  final Map<String, dynamic>? metadata;
  final Function(String caption)? onCaptionGenerated;

  const MatrixCaptionBoard({
    super.key,
    this.homeTeamName,
    this.awayTeamName,
    this.homeTeamAbbr,
    this.awayTeamAbbr,
    this.homeRoster,
    this.awayRoster,
    this.venue,
    this.gameDate,
    this.period,
    this.metadata,
    this.onCaptionGenerated,
  });

  @override
  State<MatrixCaptionBoard> createState() => _MatrixCaptionBoardState();
}

class _MatrixCaptionBoardState extends State<MatrixCaptionBoard> {
  // Active team: true = home, false = away
  bool _isHomeActive = true;

  // Selected cell
  int? _selectedPlayerIndex;
  int? _selectedVerbIndex;

  // Opponent player
  Player? _opponentPlayer;

  // Hover state
  int? _hoveredPlayerIndex;
  int? _hoveredVerbIndex;

  // Keyboard focus
  final FocusNode _focusNode = FocusNode();

  // Verb definitions
  final List<VerbDef> _verbs = [
    VerbDef(key: 'scores', label: 'Scores', wantsOpponent: true),
    VerbDef(key: 'skates', label: 'Skates', wantsOpponent: false),
    VerbDef(key: 'shoots', label: 'Shoots', wantsOpponent: false),
    VerbDef(key: 'celebrates', label: 'Celebrates', wantsOpponent: false),
    VerbDef(key: 'looks_on', label: 'Looks On', wantsOpponent: false),
    VerbDef(key: 'saves', label: 'Saves', wantsOpponent: true),
  ];

  // Mock data for testing
  List<Player> get _mockHomePlayers => [
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
        Player(
            fullName: 'Corey Perry',
            firstName: 'Corey',
            jerseyNumber: '94',
            displayName: 'Corey Perry'),
        Player(
            fullName: 'Adam Henrique',
            firstName: 'Adam',
            jerseyNumber: '19',
            displayName: 'Adam Henrique'),
      ];

  List<Player> get _mockAwayPlayers => [
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
        Player(
            fullName: 'Tyler Bertuzzi',
            firstName: 'Tyler',
            jerseyNumber: '59',
            displayName: 'Tyler Bertuzzi'),
        Player(
            fullName: 'Bobby McMann',
            firstName: 'Bobby',
            jerseyNumber: '74',
            displayName: 'Bobby McMann'),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<Player> get _activePlayers {
    if (widget.homeRoster != null && widget.awayRoster != null) {
      return _isHomeActive ? widget.homeRoster! : widget.awayRoster!;
    }
    return _isHomeActive ? _mockHomePlayers : _mockAwayPlayers;
  }

  List<Player> get _inactivePlayers {
    if (widget.homeRoster != null && widget.awayRoster != null) {
      return _isHomeActive ? widget.awayRoster! : widget.homeRoster!;
    }
    return _isHomeActive ? _mockAwayPlayers : _mockHomePlayers;
  }

  String get _activeTeamName {
    if (_isHomeActive) {
      return widget.homeTeamName ?? 'Edmonton Oilers';
    } else {
      return widget.awayTeamName ?? 'Toronto Maple Leafs';
    }
  }

  String get _inactiveTeamName {
    if (_isHomeActive) {
      return widget.awayTeamName ?? 'Toronto Maple Leafs';
    } else {
      return widget.homeTeamName ?? 'Edmonton Oilers';
    }
  }

  String get _activeTeamAbbr {
    if (_isHomeActive) {
      return widget.homeTeamAbbr ?? 'EDM';
    } else {
      return widget.awayTeamAbbr ?? 'TOR';
    }
  }

  String get _inactiveTeamAbbr {
    if (_isHomeActive) {
      return widget.awayTeamAbbr ?? 'TOR';
    } else {
      return widget.homeTeamAbbr ?? 'EDM';
    }
  }

  void _toggleActiveTeam() {
    setState(() {
      _isHomeActive = !_isHomeActive;
      _selectedPlayerIndex = null;
      _selectedVerbIndex = null;
      _opponentPlayer = null;
    });
  }

  void _handleCellClick(int playerIndex, int verbIndex,
      {bool isShiftClick = false}) {
    if (isShiftClick) {
      // Shift+Click sets opponent
      final opponent = _inactivePlayers[playerIndex];
      setState(() {
        _opponentPlayer = opponent;
      });
    } else {
      setState(() {
        _selectedPlayerIndex = playerIndex;
        _selectedVerbIndex = verbIndex;
      });
    }
    _updateCaption();
  }

  void _clearOpponent() {
    setState(() {
      _opponentPlayer = null;
    });
    _updateCaption();
  }

  void _updateCaption() {
    if (_selectedPlayerIndex == null || _selectedVerbIndex == null) return;

    final player = _activePlayers[_selectedPlayerIndex!];
    final verb = _verbs[_selectedVerbIndex!];

    final caption = _generateCaption(player, verb);

    if (widget.onCaptionGenerated != null) {
      widget.onCaptionGenerated!(caption);
    }
  }

  String _generateCaption(Player player, VerbDef verb) {
    final venue = widget.venue ?? 'Rogers Place';
    final date = widget.gameDate ?? DateTime.now();
    final period = widget.period ?? 'the first period';

    final formattedDate = _formatDate(date);
    final playerName = player.fullName;
    final playerNumber = player.jerseyNumber ?? '0';

    String verbPhrase;
    switch (verb.key) {
      case 'scores':
        verbPhrase = 'scores';
        break;
      case 'skates':
        verbPhrase = 'skates';
        break;
      case 'shoots':
        verbPhrase = 'shoots';
        break;
      case 'celebrates':
        verbPhrase = 'celebrates';
        break;
      case 'celebrates_a_goal':
        verbPhrase = 'celebrates a goal';
        break;
      case 'looks_on':
        verbPhrase = 'looks on';
        break;
      case 'saves':
        verbPhrase = 'makes a save';
        break;
      default:
        verbPhrase = verb.key.replaceAll('_', ' ');
    }

    // Build caption with or without opponent
    if (_opponentPlayer != null && verb.wantsOpponent) {
      final oppName = _opponentPlayer!.fullName;
      final oppNumber = _opponentPlayer!.jerseyNumber ?? '0';

      return '$playerName #$playerNumber of the $_activeTeamName $verbPhrase against $oppName #$oppNumber of the $_inactiveTeamName during $period at $venue on $formattedDate.';
    } else {
      return '$playerName #$playerNumber of the $_activeTeamName $verbPhrase during $period at $venue on $formattedDate.';
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      '',
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
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Tab - toggle active team
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _toggleActiveTeam();
      return;
    }

    // Escape - clear opponent
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearOpponent();
      return;
    }

    // Number keys 1-5 for verb shortcuts
    if (event.logicalKey == LogicalKeyboardKey.digit1 ||
        event.logicalKey == LogicalKeyboardKey.numpad1) {
      if (_selectedPlayerIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, 0);
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2 ||
        event.logicalKey == LogicalKeyboardKey.numpad2) {
      if (_selectedPlayerIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, 1);
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3 ||
        event.logicalKey == LogicalKeyboardKey.numpad3) {
      if (_selectedPlayerIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, 2);
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4 ||
        event.logicalKey == LogicalKeyboardKey.numpad4) {
      if (_selectedPlayerIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, 3);
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5 ||
        event.logicalKey == LogicalKeyboardKey.numpad5) {
      if (_selectedPlayerIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, 4);
      }
      return;
    }

    // Arrow keys for navigation
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_selectedPlayerIndex == null) {
          _selectedPlayerIndex = 0;
        } else if (_selectedPlayerIndex! > 0) {
          _selectedPlayerIndex = _selectedPlayerIndex! - 1;
        }
      });
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_selectedPlayerIndex == null) {
          _selectedPlayerIndex = 0;
        } else if (_selectedPlayerIndex! < _activePlayers.length - 1) {
          _selectedPlayerIndex = _selectedPlayerIndex! + 1;
        }
      });
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        if (_selectedVerbIndex == null) {
          _selectedVerbIndex = 0;
        } else if (_selectedVerbIndex! > 0) {
          _selectedVerbIndex = _selectedVerbIndex! - 1;
        }
      });
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() {
        if (_selectedVerbIndex == null) {
          _selectedVerbIndex = 0;
        } else if (_selectedVerbIndex! < _verbs.length - 1) {
          _selectedVerbIndex = _selectedVerbIndex! + 1;
        }
      });
      return;
    }

    // Enter - commit selection
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedPlayerIndex != null && _selectedVerbIndex != null) {
        _handleCellClick(_selectedPlayerIndex!, _selectedVerbIndex!);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: Column(
          children: [
            // Top bar with team buttons
            _buildTopBar(),
            const SizedBox(height: 16),
            // Matrix grid
            Expanded(
              child: _buildMatrixGrid(),
            ),
            const SizedBox(height: 16),
            // Caption preview bar
            _buildCaptionPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Home button
          _buildTeamButton(
            label: 'HOME: $_activeTeamAbbr',
            isActive: _isHomeActive,
            onTap: () {
              if (!_isHomeActive) _toggleActiveTeam();
            },
          ),
          const SizedBox(width: 16),
          // Away button
          _buildTeamButton(
            label: 'AWAY: $_inactiveTeamAbbr',
            isActive: !_isHomeActive,
            onTap: () {
              if (_isHomeActive) _toggleActiveTeam();
            },
          ),
          const SizedBox(width: 24),
          // Tab hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Text(
              'Press Tab to toggle',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.blue.shade700 : Colors.grey.shade400,
            width: 2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.blue.shade200,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey.shade700,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed tiny cell dimensions
        final columnHeaderHeight = 32.0;
        final rowHeaderWidth = 140.0;
        final cellWidth = 55.0; // Tiny fixed width for verb columns
        final cellHeight = 36.0; // Tiny fixed height for player rows

        return SingleChildScrollView(
          child: Container(
            width: constraints.maxWidth,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row with verbs
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Empty corner cell
                        Container(
                          width: rowHeaderWidth,
                          height: columnHeaderHeight,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade400),
                              bottom: BorderSide(color: Colors.grey.shade400),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Players',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                        // Verb headers
                        ...List.generate(_verbs.length, (index) {
                          final verb = _verbs[index];
                          final isHovered = _hoveredVerbIndex == index;

                          return MouseRegion(
                            onEnter: (_) =>
                                setState(() => _hoveredVerbIndex = index),
                            onExit: (_) =>
                                setState(() => _hoveredVerbIndex = null),
                            child: Container(
                              width: cellWidth,
                              height: columnHeaderHeight,
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? Colors.blue.shade50
                                    : Colors.grey.shade100,
                                border: Border(
                                  right: index < _verbs.length - 1
                                      ? BorderSide(color: Colors.grey.shade300)
                                      : BorderSide.none,
                                  bottom:
                                      BorderSide(color: Colors.grey.shade400),
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      verb.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    // Player rows
                    ...List.generate(_activePlayers.length, (playerIndex) {
                      final player = _activePlayers[playerIndex];
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Player name header
                          MouseRegion(
                            onEnter: (_) => setState(
                                () => _hoveredPlayerIndex = playerIndex),
                            onExit: (_) =>
                                setState(() => _hoveredPlayerIndex = null),
                            child: Container(
                              width: rowHeaderWidth,
                              height: cellHeight,
                              decoration: BoxDecoration(
                                color: _hoveredPlayerIndex == playerIndex
                                    ? Colors.blue.shade50
                                    : Colors.grey.shade50,
                                border: Border(
                                  right:
                                      BorderSide(color: Colors.grey.shade400),
                                  bottom: playerIndex <
                                          _activePlayers.length - 1
                                      ? BorderSide(color: Colors.grey.shade300)
                                      : BorderSide.none,
                                ),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    // Jersey number
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade700,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Center(
                                        child: Text(
                                          player.jerseyNumber ?? '0',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Player name
                                    Expanded(
                                      child: Text(
                                        player.fullName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Verb cells for this player
                          ...List.generate(_verbs.length, (verbIndex) {
                            final isSelected =
                                _selectedPlayerIndex == playerIndex &&
                                    _selectedVerbIndex == verbIndex;
                            final isHoveredRow =
                                _hoveredPlayerIndex == playerIndex;
                            final isHoveredCol = _hoveredVerbIndex == verbIndex;
                            final isHighlighted = isHoveredRow || isHoveredCol;

                            return MouseRegion(
                              onEnter: (_) {
                                setState(() {
                                  _hoveredPlayerIndex = playerIndex;
                                  _hoveredVerbIndex = verbIndex;
                                });
                              },
                              onExit: (_) {
                                setState(() {
                                  _hoveredPlayerIndex = null;
                                  _hoveredVerbIndex = null;
                                });
                              },
                              child: GestureDetector(
                                onTap: () =>
                                    _handleCellClick(playerIndex, verbIndex),
                                child: Container(
                                  width: cellWidth,
                                  height: cellHeight,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.green.shade300
                                        : isHighlighted
                                            ? Colors.blue.shade100
                                            : Colors.white,
                                    border: Border(
                                      right: verbIndex < _verbs.length - 1
                                          ? BorderSide(
                                              color: Colors.grey.shade300)
                                          : BorderSide.none,
                                      bottom: playerIndex <
                                              _activePlayers.length - 1
                                          ? BorderSide(
                                              color: Colors.grey.shade300)
                                          : BorderSide.none,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Center(
                                          child: Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 18,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCaptionPreview() {
    const hasSelectionDefault =
        'Select a player and verb to generate a caption';
    final hasSelection =
        _selectedPlayerIndex != null && _selectedVerbIndex != null;
    final caption = hasSelection
        ? _generateCaption(
            _activePlayers[_selectedPlayerIndex!],
            _verbs[_selectedVerbIndex!],
          )
        : hasSelectionDefault;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Caption Preview',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (_opponentPlayer != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Opponent: ${_opponentPlayer!.fullName} #${_opponentPlayer!.jerseyNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearOpponent,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 14,
                color: hasSelection ? Colors.black87 : Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Copy button
              ElevatedButton.icon(
                onPressed: hasSelection
                    ? () {
                        Clipboard.setData(ClipboardData(text: caption));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Caption copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 12),
              // Save button
              ElevatedButton.icon(
                onPressed: hasSelection
                    ? () {
                        // TODO: Implement save to metadata
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Caption saved'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Keyboard shortcuts hint
          Text(
            'Shortcuts: Arrow Keys (navigate) • Enter (select) • 1-5 (quick verb) • Esc (clear opponent)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class VerbDef {
  final String key;
  final String label;
  final bool wantsOpponent;

  VerbDef({
    required this.key,
    required this.label,
    required this.wantsOpponent,
  });
}
