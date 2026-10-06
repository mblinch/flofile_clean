import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import 'verb_tile.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Always-visible pinned player slot (mirrors the pinned verb bar).
class PinnedPlayerBar extends StatefulWidget {
  const PinnedPlayerBar({
    super.key,
    required this.controller,
    required this.isHome,
    required this.tokens,
    this.height,
    this.filter,
  });

  /// Compact pinned row height (padding is applied inside).
  static const pinnedBarHeight = 32.0;

  final CaptionV2Controller controller;
  final bool isHome;
  final FfTokens tokens;
  final double? height;

  /// Optional filter field shown on the right of this bar.
  final Widget? filter;

  @override
  State<PinnedPlayerBar> createState() => _PinnedPlayerBarState();
}

class _PinnedPlayerBarState extends State<PinnedPlayerBar> {
  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final pinned = widget.controller.pinnedPlayer;
    final player = pinned != null && pinned.isHome == widget.isHome
        ? pinned.player
        : null;
    final hasPlayer = player != null;
    final selected = hasPlayer &&
        widget.controller.isPlayerSelected(player, isHome: widget.isHome);
    final jersey = player?.jerseyNumber?.trim();
    final label = player == null
        ? ''
        : [
            if (jersey != null && jersey.isNotEmpty) jersey,
            widget.controller.playerListName(player),
          ].join(' ');

    return Container(
      height: widget.height ?? PinnedPlayerBar.pinnedBarHeight,
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: hasPlayer ? FfTokens.pinnedDivider : tokens.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasPlayer
                ? PhosphorIconsFill.pushPin
                : PhosphorIconsRegular.pushPin,
            size: 11,
            color: tokens.textTertiary,
          ),
          const SizedBox(width: 4),
          if (player != null) ...[
            Expanded(
              flex: widget.filter == null ? 1 : 3,
              child: CmdClick(
                onTap: () => widget.controller
                    .togglePlayerPin(player, isHome: widget.isHome),
                onCmdTap: () => widget.controller
                    .togglePlayerPin(player, isHome: widget.isHome),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                      height: 1.0,
                      color: selected
                          ? tokens.text
                          : tokens.text.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            Text(
              'No pinned player',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                height: 1.0,
                color: tokens.textTertiary,
              ),
            ),
            const Spacer(),
          ],
          if (widget.filter != null) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.filter!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
