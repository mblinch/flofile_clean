import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/sport_verb_categories.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/roster_issue_report_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';

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

String duplicateJerseyPlayerKey(Player player, int indexInGroup) {
  final id = (player.playerId ?? '').trim();
  if (id.isNotEmpty) return 'id:$id';
  return 'row:${player.fullName}|${(player.jerseyNumber ?? '').trim()}|$indexInGroup';
}

/// Applies session-only jersey edits keyed by [duplicateJerseyPlayerKey].
List<Player> applySessionJerseyEdits(
  List<Player> players,
  Map<String, String> jerseyByPlayerKey,
) {
  if (jerseyByPlayerKey.isEmpty) return players;
  final keyForPlayer = <Player, String>{};
  final groups = duplicateJerseyGroups(players);
  for (final group in groups) {
    for (var i = 0; i < group.length; i++) {
      keyForPlayer[group[i]] = duplicateJerseyPlayerKey(group[i], i);
    }
  }

  return [
    for (final player in players)
      () {
        final key = keyForPlayer[player];
        if (key == null || !jerseyByPlayerKey.containsKey(key)) return player;
        final next = jerseyByPlayerKey[key]!.trim();
        if (next == (player.jerseyNumber ?? '').trim()) return player;
        if (next.isEmpty) {
          return player.copyWith(clearJerseyNumber: true);
        }
        return player.copyWith(jerseyNumber: next);
      }(),
  ];
}

class _DuplicateJerseyDialogResult {
  const _DuplicateJerseyDialogResult({
    required this.jerseyByPlayerKey,
    required this.dontUseKeys,
  });

  final Map<String, String> jerseyByPlayerKey;
  final Set<String> dontUseKeys;
}

/// Asks the user to set session jersey numbers for shared duplicates.
///
/// Returns [players] unchanged when there are no duplicates. Returns null when
/// the user cancels, and the edited roster when they apply.
Future<List<Player>?> confirmDuplicateJerseys(
  BuildContext context, {
  required List<Player> players,
  required String teamName,
  String sportId = '',
}) async {
  final groups = duplicateJerseyGroups(players);
  if (groups.isEmpty) return players;

  unawaited(
    RosterIssueReportService.reportDuplicateJerseys(
      teamName: teamName,
      sportId: sportId,
      groups: groups,
    ),
  );

  final result = await showDialog<_DuplicateJerseyDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DuplicateJerseyDialog(
      teamName: teamName.trim().isEmpty ? 'this team' : teamName.trim(),
      sportId: sportId,
      groups: groups,
    ),
  );
  if (result == null) return null;

  final playerByKey = <String, Player>{};
  for (final group in groups) {
    for (var i = 0; i < group.length; i++) {
      playerByKey[duplicateJerseyPlayerKey(group[i], i)] = group[i];
    }
  }

  final changes = <Map<String, dynamic>>[];
  for (final entry in result.jerseyByPlayerKey.entries) {
    if (result.dontUseKeys.contains(entry.key)) continue;
    final player = playerByKey[entry.key];
    if (player == null) continue;
    final from = (player.jerseyNumber ?? '').trim();
    final to = entry.value.trim();
    if (from == to) continue;
    changes.add({
      'fullName': player.fullName,
      'playerId': player.playerId,
      'position': player.position,
      'fromJersey': from,
      'toJersey': to,
    });
  }
  if (changes.isNotEmpty) {
    unawaited(
      RosterIssueReportService.reportSessionJerseyEdits(
        teamName: teamName,
        sportId: sportId,
        changes: changes,
      ),
    );
  }

  for (final key in result.dontUseKeys) {
    final player = playerByKey[key];
    if (player == null) continue;
    unawaited(
      RosterIssueReportService.reportPlayerDataIssue(
        teamName: teamName,
        sportId: sportId,
        side: 'unknown',
        player: player,
        wrongNumber: false,
        spelling: false,
        dontUsePlayer: true,
        note: 'Marked “don’t use” in duplicate jersey dialog',
      ),
    );
  }

  final dontUsePlayers = {
    for (final key in result.dontUseKeys)
      if (playerByKey[key] != null) playerByKey[key]!,
  };
  final edited = applySessionJerseyEdits(players, result.jerseyByPlayerKey);
  if (dontUsePlayers.isEmpty) return edited;

  bool matches(Player a, Player b) {
    final aId = (a.playerId ?? '').trim();
    final bId = (b.playerId ?? '').trim();
    if (aId.isNotEmpty && bId.isNotEmpty) return aId == bId;
    return a.fullName == b.fullName &&
        (a.jerseyNumber ?? '').trim() == (b.jerseyNumber ?? '').trim();
  }

  return [
    for (final player in edited)
      if (!dontUsePlayers.any((excluded) => matches(player, excluded))) player,
  ];
}

Future<void> openPlayerGoogleSearch({
  required String fullName,
  required String sportId,
}) async {
  final sport = sportId.toLowerCase().trim();
  String league;
  switch (sport) {
    case 'hockey':
      league = 'NHL';
      break;
    case 'baseball':
      league = 'MLB';
      break;
    case 'basketball':
      league = 'NBA';
      break;
    case 'wnba':
      league = 'WNBA';
      break;
    case 'soccer':
      league = 'soccer';
      break;
    default:
      league = sport.isEmpty
          ? 'player'
          : SportVerbCategories.displayLabel(sport);
  }
  final name = fullName.trim();
  final query = name.isEmpty ? '$league player' : '$league player $name';
  final url = Uri.https('www.google.com', '/search', {'q': query}).toString();
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {
    // Best-effort only.
  }
}

class _DuplicateJerseyDialog extends StatefulWidget {
  const _DuplicateJerseyDialog({
    required this.teamName,
    required this.sportId,
    required this.groups,
  });

  final String teamName;
  final String sportId;
  final List<List<Player>> groups;

  @override
  State<_DuplicateJerseyDialog> createState() => _DuplicateJerseyDialogState();
}

class _DuplicateJerseyDialogState extends State<_DuplicateJerseyDialog> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, Player> _playerByKey;
  final Set<String> _dontUseKeys = {};

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _playerByKey = {};
    for (final group in widget.groups) {
      for (var i = 0; i < group.length; i++) {
        final player = group[i];
        final key = duplicateJerseyPlayerKey(player, i);
        _playerByKey[key] = player;
        _controllers[key] = TextEditingController(
          text: (player.jerseyNumber ?? '').trim(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? get _validationError {
    final seen = <String, String>{};
    for (final entry in _controllers.entries) {
      if (_dontUseKeys.contains(entry.key)) continue;
      final jersey = entry.value.text.trim();
      if (jersey.isEmpty) {
        return 'Enter a jersey number for every player you keep.';
      }
      if (int.tryParse(jersey) == null) {
        return 'Jersey numbers must be numeric.';
      }
      final other = seen[jersey];
      if (other != null) {
        final a = _playerByKey[entry.key]?.fullName ?? 'Player';
        final b = _playerByKey[other]?.fullName ?? 'Player';
        return '#$jersey is still shared by $a and $b.';
      }
      seen[jersey] = entry.key;
    }
    final kept = _controllers.keys.where((k) => !_dontUseKeys.contains(k));
    if (kept.isEmpty) {
      return 'Keep at least one player, or cancel.';
    }
    return null;
  }

  void _submit() {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(
      context,
      _DuplicateJerseyDialogResult(
        jerseyByPlayerKey: {
          for (final entry in _controllers.entries)
            if (!_dontUseKeys.contains(entry.key))
              entry.key: entry.value.text.trim(),
        },
        dontUseKeys: Set<String>.from(_dontUseKeys),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(
          extensions: <ThemeExtension<dynamic>>[t],
        ),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
              boxShadow: [
                BoxShadow(
                  color: t.bg.withValues(alpha: 0.55),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Duplicate jersey numbers',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: t.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                          icon: PhosphorIcon(
                            PhosphorIconsRegular.x,
                            size: 16,
                            color: t.text.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.divider),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'More than one player on ${widget.teamName} shares a '
                            'number. Set session numbers below (not saved to the '
                            'shared roster). Use Google to check, or Don’t use to '
                            'drop a player for this session.',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.70),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final group in widget.groups) ...[
                            Text(
                              'Conflict · #${(group.first.jerseyNumber ?? '').trim()}',
                              style: appDialogFieldLabelStyleOf(context),
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < group.length; i++) ...[
                              _playerRow(
                                tokens: t,
                                player: group[i],
                                playerKey: duplicateJerseyPlayerKey(group[i], i),
                              ),
                              if (i < group.length - 1)
                                const SizedBox(height: 8),
                            ],
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedGreyButton(
                          label: 'Use for this session',
                          fontSize: 11,
                          isPrimary: true,
                          onPressed: _submit,
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
    );
  }

  Widget _playerRow({
    required FfTokens tokens,
    required Player player,
    required String playerKey,
  }) {
    final controller = _controllers[playerKey]!;
    final position = (player.position ?? '').trim();
    final dontUse = _dontUseKeys.contains(playerKey);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dontUse
              ? tokens.text.withValues(alpha: 0.22)
              : tokens.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metaStyle.copyWith(
                      color: tokens.text.withValues(alpha: dontUse ? 0.45 : 1),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      decoration: dontUse ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (position.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      position,
                      style: tokens.metaStyle.copyWith(
                        fontSize: 11,
                        color: tokens.text.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: AppDialogControlShell(
                child: TextField(
                  controller: controller,
                  enabled: !dontUse,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: tokens.metaStyle.copyWith(
                    fontSize: 12,
                    color: tokens.text.withValues(alpha: dontUse ? 0.35 : 1),
                    height: 1.25,
                  ),
                  cursorColor: tokens.accent,
                  decoration: appDialogBareFieldDecoration(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => openPlayerGoogleSearch(
                fullName: player.fullName,
                sportId: widget.sportId,
              ),
              child: Text(
                'Google',
                style: tokens.metaStyle.copyWith(
                  fontSize: 11,
                  color: tokens.text.withValues(alpha: 0.75),
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                if (dontUse) {
                  _dontUseKeys.remove(playerKey);
                } else {
                  _dontUseKeys.add(playerKey);
                }
              }),
              child: Text(
                dontUse ? 'Keep' : "Don't use",
                style: tokens.metaStyle.copyWith(
                  fontSize: 11,
                  color: dontUse
                      ? tokens.accent
                      : tokens.text.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
