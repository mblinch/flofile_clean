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
    this.leading,
    this.filter,
    this.trailing,
  });

  /// Compact pinned row height (padding is applied inside).
  static const pinnedBarHeight = 32.0;

  final CaptionV2Controller controller;
  final bool isHome;
  final FfTokens tokens;
  final double? height;

  /// Team code or other label shown at the start of the same row.
  final Widget? leading;

  /// Optional filter field shown on the right of this bar.
  final Widget? filter;

  /// Icon button after the filter, still on this row.
  final Widget? trailing;

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
    final label = jersey == null || jersey.isEmpty ? '—' : jersey;

    return Container(
      height: widget.height ?? PinnedPlayerBar.pinnedBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: hasPlayer ? 'Unpin' : 'No pinned player',
            waitDuration: const Duration(milliseconds: 400),
            child: Icon(
              hasPlayer
                  ? PhosphorIconsFill.pushPin
                  : PhosphorIconsRegular.pushPin,
              size: 13,
              color: hasPlayer ? tokens.textSecondary : tokens.textTertiary,
            ),
          ),
          if (widget.filter != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  widget.filter!,
                  if (hasPlayer)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: CmdClick(
                        onTap: () => widget.controller.togglePlayerPin(
                          player,
                          isHome: widget.isHome,
                        ),
                        onCmdTap: () => widget.controller.togglePlayerPin(
                          player,
                          isHome: widget.isHome,
                        ),
                        child: SizedBox(
                          width: 22,
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.0,
                              color: selected
                                  ? tokens.text
                                  : tokens.text.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
