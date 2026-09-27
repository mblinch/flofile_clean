import 'package:flutter/material.dart';

import '../../../services/mlb_api_service.dart';
import '../../../theme/ff_tokens.dart';

/// Groups of two or more players who share a jersey number.
List<List<Player>> duplicateJerseyGroups(Iterable<Player> players) {
  final grouped = <String, List<Player>>{};
  for (final player in players) {
    final number = (player.jerseyNumber ?? '').trim();
    if (number.isEmpty) continue;
    grouped.putIfAbsent(number, () => []).add(player);
  }
  final groups = grouped.values.where((group) => group.length > 1).toList();
  groups.sort((a, b) {
    final aNumber = int.tryParse(a.first.jerseyNumber ?? '') ?? 999;
    final bNumber = int.tryParse(b.first.jerseyNumber ?? '') ?? 999;
    return aNumber.compareTo(bNumber);
  });
  return groups;
}

/// [keep] maps a jersey number to the one player to retain. A null value keeps
/// every player who wears that number. Numbers that are absent are unchanged.
List<Player> applyDuplicateJerseyChoices(
  List<Player> players,
  Map<String, Player?> keep,
) {
  final chosen = <Player>[];
  for (final player in players) {
    final number = (player.jerseyNumber ?? '').trim();
    if (number.isEmpty || !keep.containsKey(number)) {
      chosen.add(player);
      continue;
    }
    final only = keep[number];
    if (only == null || identical(only, player)) {
      chosen.add(player);
    }
  }
  return chosen;
}

/// Asks how to handle shared jersey numbers.
///
/// Returns [players] unchanged when there are no duplicates. Returns null when
/// the user cancels a prompt, and the filtered roster when they choose.
Future<List<Player>?> confirmDuplicateJerseys(
  BuildContext context, {
  required List<Player> players,
  required String teamName,
}) async {
  final groups = duplicateJerseyGroups(players);
  if (groups.isEmpty) return players;
  final keep = await showDialog<Map<String, Player?>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DuplicateJerseyDialog(
      teamName: teamName.trim().isEmpty ? 'this team' : teamName.trim(),
      groups: groups,
    ),
  );
  if (keep == null) return null;
  return applyDuplicateJerseyChoices(players, keep);
}

class _DuplicateJerseyDialog extends StatefulWidget {
  const _DuplicateJerseyDialog({
    required this.teamName,
    required this.groups,
  });

  final String teamName;
  final List<List<Player>> groups;

  @override
  State<_DuplicateJerseyDialog> createState() => _DuplicateJerseyDialogState();
}

class _DuplicateJerseyDialogState extends State<_DuplicateJerseyDialog> {
  /// Jersey → choice. -2 is unset, -1 keeps everyone, 0+ keeps that player.
  late final Map<String, int> _choice;

  @override
  void initState() {
    super.initState();
    _choice = {
      for (final group in widget.groups)
        (group.first.jerseyNumber ?? '').trim(): -2,
    };
  }

  bool get _ready => _choice.values.every((choice) => choice != -2);

  Map<String, Player?> _result() {
    final keep = <String, Player?>{};
    for (final group in widget.groups) {
      final number = (group.first.jerseyNumber ?? '').trim();
      final choice = _choice[number] ?? -2;
      keep[number] = choice < 0 ? null : group[choice];
    }
    return keep;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AlertDialog(
      backgroundColor: tokens.surface,
      title: const Text('Duplicate jersey numbers'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More than one player on ${widget.teamName} wears the same number. What should be loaded?',
                style: tokens.bodyStyle,
              ),
              const SizedBox(height: 12),
              for (final group in widget.groups) ...[
                Text(
                  '#${(group.first.jerseyNumber ?? '').trim()}',
                  style: tokens.labelStyle,
                ),
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: -1,
                  groupValue: _choice[(group.first.jerseyNumber ?? '').trim()],
                  title: const Text('Keep all of them'),
                  onChanged: (value) => setState(() {
                    _choice[(group.first.jerseyNumber ?? '').trim()] =
                        value ?? -1;
                  }),
                ),
                for (var i = 0; i < group.length; i++)
                  RadioListTile<int>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: i,
                    groupValue:
                        _choice[(group.first.jerseyNumber ?? '').trim()],
                    title: Text('Keep only ${group[i].fullName}'),
                    onChanged: (value) => setState(() {
                      _choice[(group.first.jerseyNumber ?? '').trim()] =
                          value ?? i;
                    }),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ready ? () => Navigator.pop(context, _result()) : null,
          child: const Text('Use this roster'),
        ),
      ],
    );
  }
}
