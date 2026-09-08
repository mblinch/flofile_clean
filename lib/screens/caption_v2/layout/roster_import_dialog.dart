import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/mlb_api_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/roster_text_parser.dart';

class RosterImportResult {
  const RosterImportResult({
    this.homeTeamName,
    this.homePlayers,
    this.awayTeamName,
    this.awayPlayers,
  });

  final String? homeTeamName;
  final List<Player>? homePlayers;
  final String? awayTeamName;
  final List<Player>? awayPlayers;
}

class _SingleRosterResult {
  const _SingleRosterResult({
    required this.teamName,
    required this.players,
  });

  final String teamName;
  final List<Player> players;
}

Future<RosterImportResult?> showRosterImportDialog(
  BuildContext context, {
  required String sport,
  String? homeTeamLabel,
  String? awayTeamLabel,
  List<Player>? homePlayers,
  List<Player>? awayPlayers,
}) {
  return showDialog<RosterImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RosterManagerDialog(
      sport: sport,
      homeTeamLabel: homeTeamLabel,
      awayTeamLabel: awayTeamLabel,
      homePlayers: homePlayers,
      awayPlayers: awayPlayers,
    ),
  );
}

class _SingleRosterImportDialog extends StatefulWidget {
  const _SingleRosterImportDialog({
    required this.sport,
    required this.teamLabel,
    required this.sideLabel,
  });

  final String sport;
  final String teamLabel;
  final String sideLabel;

  @override
  State<_SingleRosterImportDialog> createState() =>
      _SingleRosterImportDialogState();
}

class _SingleRosterImportDialogState extends State<_SingleRosterImportDialog> {
  late final TextEditingController _teamNameController;
  final TextEditingController _textController = TextEditingController();
  final RosterTextParser _parser = const RosterTextParser();

  RosterParseResult? _parsed;
  RosterNameOrder _nameOrder = RosterNameOrder.firstLast;

  @override
  void initState() {
    super.initState();
    _teamNameController = TextEditingController(text: widget.teamLabel);
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    _textController.text = text;
    _analyze();
  }

  void _analyze() {
    final parsed = _parser.parse(_textController.text, sport: widget.sport);
    setState(() {
      _parsed = parsed;
      _nameOrder = parsed.detectedNameOrder;
    });
  }

  void _accept() {
    final parsed = _parsed;
    if (parsed == null ||
        parsed.entries.isEmpty ||
        _teamNameController.text.trim().isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      _SingleRosterResult(
        teamName: _teamNameController.text.trim(),
        players: parsed.players(_nameOrder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final parsed = _parsed;

    return Dialog(
      insetPadding: const EdgeInsets.all(48),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: BorderSide(color: t.divider),
      ),
      child: SizedBox(
        width: 760,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paste ${widget.sideLabel} roster',
                      style: t.labelStyle.copyWith(fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: t.textSecondary),
                  ),
                ],
              ),
              Text(
                'Copy a roster table from a web page or other source and paste it below.',
                style: t.metaStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _teamNameController,
                onChanged: (_) => setState(() {}),
                style: t.bodyStyle,
                decoration: InputDecoration(
                  hintText: '${widget.sideLabel} team name',
                  hintStyle: t.metaStyle,
                  filled: true,
                  fillColor: t.sunken,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide(color: t.divider),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: parsed == null ? 235 : 110,
                child: TextField(
                  controller: _textController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: t.metaStyle.copyWith(color: t.text),
                  decoration: InputDecoration(
                    hintText: 'Paste roster text here…',
                    hintStyle: t.metaStyle,
                    filled: true,
                    fillColor: t.sunken,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                      borderSide: BorderSide(color: t.divider),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Paste from clipboard'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _analyze,
                    child: Text(
                      parsed == null ? 'Analyze roster' : 'Analyze again',
                    ),
                  ),
                ],
              ),
              if (parsed != null) ...[
                const SizedBox(height: 14),
                if (parsed.entries.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No player names and jersey numbers were found.',
                        style: t.bodyStyle,
                      ),
                    ),
                  )
                else ...[
                  _NameOrderConfirmation(
                    parsed: parsed,
                    nameOrder: _nameOrder,
                    onChanged: (value) => setState(() => _nameOrder = value),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${parsed.entries.length} players found'
                    '${parsed.ignoredLineCount == 0 ? '' : ' · '
                        '${parsed.ignoredLineCount} non-player lines ignored'}',
                    style: t.metaStyle,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.sunken,
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusChip),
                      ),
                      child: ListView.builder(
                        itemCount: parsed.entries.length,
                        itemBuilder: (context, index) {
                          final entry = parsed.entries[index];
                          return ListTile(
                            dense: true,
                            leading: SizedBox(
                              width: 36,
                              child: Text(
                                '#${entry.jerseyNumber}',
                                style: t.monoMetaStyle.copyWith(color: t.text),
                              ),
                            ),
                            title: Text(
                              entry.nameFor(_nameOrder),
                              style: t.metaStyle.copyWith(color: t.text),
                            ),
                            trailing: entry.position == null
                                ? null
                                : Text(entry.position!, style: t.metaStyle),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _teamNameController.text.trim().isEmpty
                          ? null
                          : _accept,
                      child: const Text('Use this roster'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterManagerDialog extends StatefulWidget {
  const _RosterManagerDialog({
    required this.sport,
    required this.homeTeamLabel,
    required this.awayTeamLabel,
    required this.homePlayers,
    required this.awayPlayers,
  });

  final String sport;
  final String? homeTeamLabel;
  final String? awayTeamLabel;
  final List<Player>? homePlayers;
  final List<Player>? awayPlayers;

  @override
  State<_RosterManagerDialog> createState() => _RosterManagerDialogState();
}

class _RosterManagerDialogState extends State<_RosterManagerDialog> {
  late String _homeTeamName;
  late String _awayTeamName;
  List<Player>? _homePlayers;
  List<Player>? _awayPlayers;

  @override
  void initState() {
    super.initState();
    _homeTeamName = widget.homeTeamLabel ?? '';
    _awayTeamName = widget.awayTeamLabel ?? '';
    _homePlayers = widget.homePlayers == null
        ? null
        : List<Player>.of(widget.homePlayers!);
    _awayPlayers = widget.awayPlayers == null
        ? null
        : List<Player>.of(widget.awayPlayers!);
  }

  Future<void> _openPasteWindow({required bool isHome}) async {
    final result = await showDialog<_SingleRosterResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SingleRosterImportDialog(
        sport: widget.sport,
        teamLabel: isHome ? _homeTeamName : _awayTeamName,
        sideLabel: isHome ? 'Home' : 'Away',
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (isHome) {
        _homeTeamName = result.teamName;
        _homePlayers = result.players;
      } else {
        _awayTeamName = result.teamName;
        _awayPlayers = result.players;
      }
    });
  }

  void _clear({required bool isHome}) {
    setState(() {
      if (isHome) {
        _homePlayers = null;
      } else {
        _awayPlayers = null;
      }
    });
  }

  Future<void> _addPlayer({required bool isHome}) async {
    final player = await showDialog<Player>(
      context: context,
      builder: (_) => _AddPlayerDialog(sport: widget.sport),
    );
    if (!mounted || player == null) return;
    setState(() {
      if (isHome) {
        _homePlayers = [...?_homePlayers, player];
      } else {
        _awayPlayers = [...?_awayPlayers, player];
      }
    });
  }

  Future<void> _useRosters() async {
    final hasHome = _homePlayers != null;
    final hasAway = _awayPlayers != null;

    if (hasHome != hasAway) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use only one team?'),
          content: const Text(
            'Are you sure you only want to use one team?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep adding'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use one team'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    Navigator.pop(
      context,
      RosterImportResult(
        homeTeamName: hasHome ? _homeTeamName : null,
        homePlayers: _homePlayers,
        awayTeamName: hasAway ? _awayTeamName : null,
        awayPlayers: _awayPlayers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final hasAnyRoster = _homePlayers != null || _awayPlayers != null;
    final canSave = hasAnyRoster ||
        widget.homePlayers != null ||
        widget.awayPlayers != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: BorderSide(color: t.divider),
      ),
      child: SizedBox(
        width: 980,
        height: 760,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Custom rosters',
                      style: t.labelStyle.copyWith(fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: t.textSecondary),
                  ),
                ],
              ),
              Text(
                'Add a pasted roster for either or both teams.',
                style: t.metaStyle,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RosterColumn(
                        sideLabel: 'Away',
                        teamName: _awayTeamName,
                        players: _awayPlayers,
                        onPaste: () => _openPasteWindow(isHome: false),
                        onClear: () => _clear(isHome: false),
                        onAddPlayer: () => _addPlayer(isHome: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RosterColumn(
                        sideLabel: 'Home',
                        teamName: _homeTeamName,
                        players: _homePlayers,
                        onPaste: () => _openPasteWindow(isHome: true),
                        onClear: () => _clear(isHome: true),
                        onAddPlayer: () => _addPlayer(isHome: true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSave ? _useRosters : null,
                    child: const Text('Use rosters'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddPlayerDialog extends StatefulWidget {
  const _AddPlayerDialog({required this.sport});

  final String sport;

  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  static const _baseballPositions = [
    'Pitcher',
    'Catcher',
    'First Baseman',
    'Second Baseman',
    'Third Baseman',
    'Shortstop',
    'Left Fielder',
    'Center Fielder',
    'Right Fielder',
    'Outfielder',
    'Designated Hitter',
    'Utility',
    'Pinch Hitter',
    'Pinch Runner',
  ];

  final _nameController = TextEditingController();
  final _jerseyController = TextEditingController();
  final _positionController = TextEditingController();
  String? _baseballPosition;

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  void _add() {
    final fullName = _nameController.text.trim();
    if (fullName.isEmpty) return;
    final jersey = _jerseyController.text.trim();
    final position = widget.sport.toLowerCase() == 'baseball'
        ? _baseballPosition
        : _positionController.text.trim();
    Navigator.pop(
      context,
      Player(
        fullName: fullName,
        firstName: fullName.split(RegExp(r'\s+')).first,
        jerseyNumber: jersey.isEmpty ? null : jersey,
        displayName: jersey.isEmpty ? fullName : '$fullName #$jersey',
        position: position == null || position.isEmpty ? null : position,
      ),
    );
  }

  InputDecoration _fieldDecoration(FfTokens t, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: t.metaStyle,
      filled: true,
      fillColor: t.sunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        borderSide: BorderSide(color: t.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        borderSide: BorderSide(color: t.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final baseball = widget.sport.toLowerCase() == 'baseball';

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: BorderSide(color: t.divider),
      ),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add player',
                      style: t.labelStyle.copyWith(fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: t.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: t.bodyStyle,
                decoration: _fieldDecoration(t, 'Player name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _jerseyController,
                keyboardType: TextInputType.number,
                style: t.bodyStyle,
                decoration: _fieldDecoration(t, 'Jersey number'),
              ),
              const SizedBox(height: 10),
              if (baseball)
                DropdownButtonFormField<String>(
                  initialValue: _baseballPosition,
                  isExpanded: true,
                  dropdownColor: t.surface,
                  style: t.bodyStyle,
                  decoration: _fieldDecoration(t, 'Position'),
                  items: [
                    for (final position in _baseballPositions)
                      DropdownMenuItem(
                        value: position,
                        child: Text(position),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _baseballPosition = value),
                )
              else
                TextField(
                  controller: _positionController,
                  style: t.bodyStyle,
                  decoration: _fieldDecoration(t, 'Position'),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _nameController.text.trim().isEmpty ? null : _add,
                    child: const Text('Add player'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterColumn extends StatelessWidget {
  const _RosterColumn({
    required this.sideLabel,
    required this.teamName,
    required this.players,
    required this.onPaste,
    required this.onClear,
    required this.onAddPlayer,
  });

  final String sideLabel;
  final String teamName;
  final List<Player>? players;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onAddPlayer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final roster = players;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sideLabel.toUpperCase(), style: t.microStyle),
                    const SizedBox(height: 3),
                    Text(
                      teamName.isEmpty ? 'No team entered' : teamName,
                      style: t.labelStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (roster != null)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (roster == null)
            Expanded(
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste_outlined, size: 16),
                  label: const Text('Paste roster'),
                ),
              ),
            )
          else ...[
            Text('${roster.length} players', style: t.metaStyle),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddPlayer,
                icon: const Icon(Icons.person_add_alt_1, size: 15),
                label: const Text('Add player'),
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: ListView.separated(
                itemCount: roster.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: t.divider),
                itemBuilder: (context, index) {
                  final player = roster[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 36,
                      child: Text(
                        '#${player.jerseyNumber}',
                        style: t.monoMetaStyle.copyWith(color: t.text),
                      ),
                    ),
                    title: Text(
                      player.fullName,
                      style: t.metaStyle.copyWith(color: t.text),
                    ),
                    trailing: player.position == null
                        ? null
                        : Text(player.position!, style: t.metaStyle),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RosterImportDialog extends StatefulWidget {
  const _RosterImportDialog({
    required this.homeTeamLabel,
    required this.awayTeamLabel,
    required this.initialHomePlayers,
    required this.initialAwayPlayers,
    required this.initialIsHome,
    required this.allowAddToCurrent,
  });

  final String? homeTeamLabel;
  final String? awayTeamLabel;
  final List<Player>? initialHomePlayers;
  final List<Player>? initialAwayPlayers;
  final bool initialIsHome;
  final bool allowAddToCurrent;

  @override
  State<_RosterImportDialog> createState() => _RosterImportDialogState();
}

class _RosterImportDialogState extends State<_RosterImportDialog> {
  late final TextEditingController _teamNameController;
  final TextEditingController _textController = TextEditingController();
  final RosterTextParser _parser = const RosterTextParser();

  RosterParseResult? _parsed;
  RosterNameOrder _nameOrder = RosterNameOrder.firstLast;
  bool _replaceExisting = true;
  bool _isHome = true;
  late String _homeTeamName;
  late String _awayTeamName;
  List<Player>? _homePlayers;
  List<Player>? _awayPlayers;

  @override
  void initState() {
    super.initState();
    _homeTeamName = widget.homeTeamLabel ?? '';
    _awayTeamName = widget.awayTeamLabel ?? '';
    _homePlayers = widget.initialHomePlayers;
    _awayPlayers = widget.initialAwayPlayers;
    _isHome = widget.initialIsHome;
    _teamNameController = TextEditingController(
      text: _isHome ? _homeTeamName : _awayTeamName,
    );
  }

  void _selectSide(bool isHome) {
    setState(() {
      if (_isHome) {
        _homeTeamName = _teamNameController.text;
      } else {
        _awayTeamName = _teamNameController.text;
      }
      _isHome = isHome;
      _teamNameController.text = isHome ? _homeTeamName : _awayTeamName;
      _textController.clear();
      _parsed = null;
    });
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    _textController.text = text;
    _analyze();
  }

  void _analyze() {
    final parsed = _parser.parse(_textController.text);
    setState(() {
      _parsed = parsed;
      _nameOrder = parsed.detectedNameOrder;
    });
  }

  void _finish() {
    Navigator.pop(
      context,
      RosterImportResult(
        homeTeamName: _homePlayers == null ? null : _homeTeamName.trim(),
        homePlayers: _homePlayers,
        awayTeamName: _awayPlayers == null ? null : _awayTeamName.trim(),
        awayPlayers: _awayPlayers,
      ),
    );
  }

  void _acceptCurrentRoster() {
    final parsed = _parsed;
    if (parsed == null || parsed.entries.isEmpty) return;

    if (_isHome) {
      _homeTeamName = _teamNameController.text.trim();
      _homePlayers = parsed.players(_nameOrder);
    } else {
      _awayTeamName = _teamNameController.text.trim();
      _awayPlayers = parsed.players(_nameOrder);
    }

    final otherRoster = _isHome ? _awayPlayers : _homePlayers;
    if (otherRoster == null) {
      _selectSide(!_isHome);
    } else {
      _finish();
    }
  }

  Future<void> _finishWithOneTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use only one team?'),
        content: const Text(
          'Are you sure you only want to use one team?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep adding'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use one team'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _finish();
  }

  Future<void> _close() async {
    if ((_homePlayers == null) != (_awayPlayers == null)) {
      await _finishWithOneTeam();
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final parsed = _parsed;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: BorderSide(color: t.divider),
      ),
      child: SizedBox(
        width: 980,
        height: 760,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Import custom roster',
                      style: t.labelStyle.copyWith(fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _close,
                    icon: Icon(Icons.close, color: t.textSecondary),
                  ),
                ],
              ),
              Text(
                'Copy a roster table from a web page and paste it below.',
                style: t.metaStyle,
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Away')),
                  ButtonSegment(value: true, label: Text('Home')),
                ],
                selected: {_isHome},
                onSelectionChanged: (values) => _selectSide(values.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _teamNameController,
                onChanged: (_) => setState(() {}),
                style: t.bodyStyle,
                decoration: InputDecoration(
                  hintText: '${_isHome ? 'Home' : 'Away'} team name',
                  hintStyle: t.metaStyle,
                  filled: true,
                  fillColor: t.sunken,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide(color: t.divider),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: parsed == null ? 235 : 110,
                child: TextField(
                  controller: _textController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: t.metaStyle.copyWith(color: t.text),
                  decoration: InputDecoration(
                    hintText: 'Paste roster text here…',
                    hintStyle: t.metaStyle,
                    filled: true,
                    fillColor: t.sunken,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                      borderSide: BorderSide(color: t.divider),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Paste from clipboard'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _analyze,
                    child: Text(
                        parsed == null ? 'Analyze roster' : 'Analyze again'),
                  ),
                ],
              ),
              if ((_homePlayers == null) != (_awayPlayers == null)) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: t.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _homePlayers != null
                            ? 'Home roster ready · ${_homePlayers!.length} players'
                            : 'Away roster ready · ${_awayPlayers!.length} players',
                        style: t.metaStyle.copyWith(color: t.text),
                      ),
                    ),
                  ],
                ),
              ],
              if (parsed != null) ...[
                const SizedBox(height: 14),
                if (parsed.entries.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No player names and jersey numbers were found.',
                        style: t.bodyStyle,
                      ),
                    ),
                  )
                else ...[
                  _NameOrderConfirmation(
                    parsed: parsed,
                    nameOrder: _nameOrder,
                    onChanged: (value) => setState(() => _nameOrder = value),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${parsed.entries.length} players found'
                    '${parsed.ignoredLineCount == 0 ? '' : ' · '
                        '${parsed.ignoredLineCount} non-player lines ignored'}',
                    style: t.metaStyle,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.sunken,
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusChip),
                      ),
                      child: ListView.builder(
                        itemCount: parsed.entries.length,
                        itemBuilder: (context, index) {
                          final entry = parsed.entries[index];
                          return ListTile(
                            dense: true,
                            leading: SizedBox(
                              width: 36,
                              child: Text(
                                '#${entry.jerseyNumber}',
                                style: t.monoMetaStyle.copyWith(color: t.text),
                              ),
                            ),
                            title: Text(
                              entry.nameFor(_nameOrder),
                              style: t.metaStyle.copyWith(color: t.text),
                            ),
                            trailing: entry.position == null
                                ? null
                                : Text(entry.position!, style: t.metaStyle),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (widget.allowAddToCurrent)
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Replace current'),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Add to current'),
                            ),
                          ],
                          selected: {_replaceExisting},
                          onSelectionChanged: (values) => setState(
                            () => _replaceExisting = values.first,
                          ),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _teamNameController.text.trim().isEmpty
                            ? null
                            : _acceptCurrentRoster,
                        child: Text(
                          (_isHome ? _awayPlayers : _homePlayers) == null
                              ? 'Use this roster & add other team'
                              : 'Use this roster',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NameOrderConfirmation extends StatelessWidget {
  const _NameOrderConfirmation({
    required this.parsed,
    required this.nameOrder,
    required this.onChanged,
  });

  final RosterParseResult parsed;
  final RosterNameOrder nameOrder;
  final ValueChanged<RosterNameOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final examples = parsed.entries.take(3).map((entry) {
      final parts = entry.nameFor(nameOrder).trim().split(RegExp(r'\s+'));
      return <String>[
        parts.first,
        parts.length > 1 ? parts.sublist(1).join(' ') : '—',
      ];
    }).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.selectedFill,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(color: t.selectedBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Does this name interpretation look right?',
                    style: t.labelStyle),
                const SizedBox(height: 6),
                Text(
                  'First names: ${examples.map((e) => e[0]).join(', ')}',
                  style: t.metaStyle.copyWith(color: t.text),
                ),
                Text(
                  'Last names: ${examples.map((e) => e[1]).join(', ')}',
                  style: t.metaStyle.copyWith(color: t.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<RosterNameOrder>(
            segments: const [
              ButtonSegment(
                value: RosterNameOrder.firstLast,
                label: Text('First Last'),
              ),
              ButtonSegment(
                value: RosterNameOrder.lastFirst,
                label: Text('Last First'),
              ),
            ],
            selected: {nameOrder},
            onSelectionChanged: (values) => onChanged(values.first),
          ),
        ],
      ),
    );
  }
}
