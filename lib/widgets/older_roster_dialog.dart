import 'package:flutter/material.dart';

import '../services/roster_history_service.dart';

/// One dialog for the game. Returns true to use the game-date roster.
class OlderRosterDialog {
  OlderRosterDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String gameDate,
    required List<OlderRosterTeam> teams,
  }) async {
    final useGameDate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Older roster found'),
          content: Text(
            RosterHistoryService.promptBody(gameDate: gameDate, teams: teams),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Use today's roster"),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use roster from game date'),
            ),
          ],
        );
      },
    );
    return useGameDate ?? true;
  }
}
