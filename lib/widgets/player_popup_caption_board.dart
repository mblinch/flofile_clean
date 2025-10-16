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
  });

  @override
  State<PlayerPopupCaptionBoard> createState() =>
      _PlayerPopupCaptionBoardState();
}

class _PlayerPopupCaptionBoardState extends State<PlayerPopupCaptionBoard> {
  Player? _selectedPlayer;
  bool _isSelectedPlayerHome = true;

  // Verb categories matching the existing system
  final Map<String, List<VerbOption>> _verbCategories = {
    'Offense': [
      VerbOption('Skates', 'skates with the puck'),
      VerbOption('Battles', 'battles for the puck', wantsOpponent: true),
      VerbOption('Scores', 'scores', wantsOpponent: true),
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
    ],
    'Non Game-Action': [
      VerbOption('Looks On', 'looks on'),
      VerbOption('Warm Ups', 'warms up prior to play'),
      VerbOption('Takes the Ice', 'takes the ice prior to play'),
      VerbOption('Comes Off the Ice', 'comes off the ice'),
      VerbOption('National Anthem',
          'looks on during the national anthem prior to play'),
      VerbOption('Stretching', 'stretches prior to play'),
      VerbOption('Bench', 'on the bench'),
    ],
    'Reactions': [
      VerbOption('Celebrates', 'celebrates'),
      VerbOption('Dejection', 'reacts with dejection'),
      VerbOption('Post Game Win', 'celebrates after the win'),
      VerbOption('Post Game Loss', 'reacts after the loss'),
    ],
  };

  void _selectPlayer(Player player, bool isHome) {
    setState(() {
      _selectedPlayer = player;
      _isSelectedPlayerHome = isHome;
    });
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
          // Header with selected player info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: _selectedPlayer != null
                ? Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Text(
                            _selectedPlayer!.jerseyNumber ?? '0',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPlayer!.fullName,
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _isSelectedPlayerHome
                                  ? (widget.homeTeamName ?? 'Home Team')
                                  : (widget.awayTeamName ?? 'Away Team'),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Select a player',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
          // Expandable verb categories
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _verbCategories.entries.map((entry) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
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
                        onTap: _selectedPlayer != null
                            ? () => _generateCaption(
                                  _selectedPlayer!,
                                  verb,
                                  _isSelectedPlayerHome,
                                )
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedPlayer != null
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
                                    color: _selectedPlayer != null
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              if (_selectedPlayer != null)
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
            ),
          ),
        ],
      ),
    );
  }

  void _generateCaption(Player player, VerbOption verb, bool isHome) {
    // Pass the player and verb to the parent to use the existing Getty caption system
    if (widget.onCaptionGenerated != null) {
      widget.onCaptionGenerated!(player, verb.label, isHome);
    }

    // Show brief confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${player.fullName} - ${verb.label}'),
        duration: const Duration(milliseconds: 800),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.sports_hockey, color: Colors.grey.shade700, size: 16),
              const SizedBox(width: 8),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${players.length}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Player grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              childAspectRatio: 1.1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players[index];
              final isSelected = _selectedPlayer == player;
              return InkWell(
                onTap: () => _selectPlayer(player, isHome),
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
