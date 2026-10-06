import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../services/auth_service.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/roster_issue_report_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';

/// Result from [showPlayerDataIssueDialog].
class PlayerDataIssueDialogResult {
  const PlayerDataIssueDialogResult({
    required this.wrongNumber,
    required this.spelling,
    required this.dontUsePlayer,
    required this.note,
  });

  final bool wrongNumber;
  final bool spelling;
  final bool dontUsePlayer;
  final String note;
}

/// Asks which roster data problem to report, with an optional note.
Future<PlayerDataIssueDialogResult?> showPlayerDataIssueDialog({
  required BuildContext context,
  required String playerName,
  required String jersey,
  required String teamName,
}) {
  return showDialog<PlayerDataIssueDialogResult>(
    context: context,
    builder: (context) => _PlayerDataIssueDialog(
      playerName: playerName,
      jersey: jersey,
      teamName: teamName,
    ),
  );
}

/// Full report flow: sign-in gate → dialog → Firestore write → snackbar.
Future<void> submitPlayerDataIssueReport({
  required BuildContext context,
  required String teamName,
  required String sportId,
  required String side,
  required Player player,
}) async {
  if (!AuthService.instance.isSignedIn) {
    await showPlayerDataIssueSignInRequiredDialog(context);
    return;
  }
  final result = await showPlayerDataIssueDialog(
    context: context,
    playerName: player.fullName,
    jersey: player.jerseyNumber ?? '',
    teamName: teamName,
  );
  if (result == null || !context.mounted) return;

  final reportResult = await RosterIssueReportService.reportPlayerDataIssue(
    teamName: teamName,
    sportId: sportId,
    side: side,
    player: player,
    wrongNumber: result.wrongNumber,
    spelling: result.spelling,
    dontUsePlayer: result.dontUsePlayer,
    note: result.note,
  );
  if (!context.mounted) return;
  late final String message;
  switch (reportResult) {
    case RosterIssueReportResult.success:
      message = 'Report sent to admin';
      break;
    case RosterIssueReportResult.notSignedIn:
      message = 'Sign in to report roster issues';
      break;
    case RosterIssueReportResult.failed:
      message = 'Could not send report';
      break;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

/// Short notice when the user must sign in before filing a report.
Future<void> showPlayerDataIssueSignInRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
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
              width: 360,
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sign in required',
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Email alerts for wrong numbers or spelling mistakes '
                      'require a signed-in account.',
                      style: t.metaStyle.copyWith(
                        color: t.text.withValues(alpha: 0.70),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedGreyButton(
                        label: 'OK',
                        fontSize: 11,
                        isPrimary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PlayerDataIssueDialog extends StatefulWidget {
  const _PlayerDataIssueDialog({
    required this.playerName,
    required this.jersey,
    required this.teamName,
  });

  final String playerName;
  final String jersey;
  final String teamName;

  @override
  State<_PlayerDataIssueDialog> createState() => _PlayerDataIssueDialogState();
}

class _PlayerDataIssueDialogState extends State<_PlayerDataIssueDialog> {
  bool _wrongNumber = false;
  bool _spelling = false;
  bool _dontUsePlayer = false;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _wrongNumber || _spelling || _dontUsePlayer;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      PlayerDataIssueDialogResult(
        wrongNumber: _wrongNumber,
        spelling: _spelling,
        dontUsePlayer: _dontUsePlayer,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final jerseyLabel =
        widget.jersey.trim().isEmpty ? '—' : widget.jersey.trim();
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
            width: 400,
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
                            'Report player data',
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Jersey number',
                          style: appDialogFieldLabelStyleOf(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          jerseyLabel,
                          style: t.metaStyle.copyWith(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Player name',
                          style: appDialogFieldLabelStyleOf(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.playerName,
                          style: t.metaStyle.copyWith(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.teamName.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Team',
                            style: appDialogFieldLabelStyleOf(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.teamName,
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.78),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'What’s wrong?',
                          style: appDialogFieldLabelStyleOf(context),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          value: _wrongNumber,
                          onChanged: (v) =>
                              setState(() => _wrongNumber = v ?? false),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: t.accent,
                          title: Text(
                            'Wrong jersey number',
                            style: t.metaStyle.copyWith(color: t.text),
                          ),
                        ),
                        CheckboxListTile(
                          value: _spelling,
                          onChanged: (v) =>
                              setState(() => _spelling = v ?? false),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: t.accent,
                          title: Text(
                            'Spelling mistake',
                            style: t.metaStyle.copyWith(color: t.text),
                          ),
                        ),
                        CheckboxListTile(
                          value: _dontUsePlayer,
                          onChanged: (v) =>
                              setState(() => _dontUsePlayer = v ?? false),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: t.accent,
                          title: Text(
                            "Don't use this player",
                            style: t.metaStyle.copyWith(color: t.text),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Optional note',
                          style: appDialogFieldLabelStyleOf(context),
                        ),
                        const SizedBox(height: 6),
                        AppDialogControlShell(
                          child: TextField(
                            controller: _noteController,
                            maxLines: 3,
                            minLines: 2,
                            style: t.metaStyle.copyWith(
                              fontSize: 12,
                              color: t.text,
                              height: 1.25,
                            ),
                            cursorColor: t.accent,
                            decoration: appDialogBareFieldDecoration(
                              hintText: 'Correct number, spelling, etc.',
                            ).copyWith(
                              hintStyle: t.metaStyle.copyWith(
                                fontSize: 12,
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                          label: 'Send report',
                          fontSize: 11,
                          isPrimary: true,
                          onPressed: _canSubmit ? _submit : null,
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
}
