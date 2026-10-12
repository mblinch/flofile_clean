import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';

/// Whole-side subjects. Quoted labels are the exact words written into the caption.
class TeamPlayersButton extends StatelessWidget {
  const TeamPlayersButton({
    super.key,
    required this.controller,
    required this.isHome,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final active = controller.teamPlayersIsHome == isHome;
    final stack = MediaQuery.sizeOf(context).width < 1100;
    final nickname = _nickname(controller.teamNameLabel(isHome: isHome));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: stack
          ? Column(
              children: [
                _SubjectChip(
                  label: '$nickname player',
                  selected: active && controller.teamSubjectAsPlayers,
                  tokens: tokens,
                  onTap: () => controller.toggleTeamSubject(
                    isHome: isHome,
                    asPlayers: true,
                  ),
                ),
                const SizedBox(height: 6),
                _SubjectChip(
                  label: nickname,
                  selected: active && !controller.teamSubjectAsPlayers,
                  tokens: tokens,
                  onTap: () => controller.toggleTeamSubject(
                    isHome: isHome,
                    asPlayers: false,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _SubjectChip(
                    label: '$nickname player',
                    selected: active && controller.teamSubjectAsPlayers,
                    tokens: tokens,
                    onTap: () => controller.toggleTeamSubject(
                      isHome: isHome,
                      asPlayers: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SubjectChip(
                    label: nickname,
                    selected: active && !controller.teamSubjectAsPlayers,
                    tokens: tokens,
                    onTap: () => controller.toggleTeamSubject(
                      isHome: isHome,
                      asPlayers: false,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

String _nickname(String teamName) {
  final parts = teamName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'Team';
  if (parts.length == 1) return parts.first;
  const two = <String>{
    'maple leafs',
    'blue jays',
    'blue jackets',
    'red sox',
    'white sox',
    'red wings',
    'golden knights',
    'trail blazers',
  };
  final lastTwo =
      '${parts[parts.length - 2]} ${parts[parts.length - 1]}'.toLowerCase();
  if (two.contains(lastTwo)) {
    return '${parts[parts.length - 2]} ${parts[parts.length - 1]}';
  }
  return parts.last;
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          height: 38,
          decoration: BoxDecoration(
            color: selected ? tokens.text : tokens.sunken,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.labelStyle.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? tokens.bg : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
