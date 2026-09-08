import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Verb list tile: monospace code + label.
///
/// Selected verbs use only a leading accent bar beside the number.
class VerbTile extends StatelessWidget {
  const VerbTile({
    super.key,
    required this.code,
    required this.label,
    required this.selected,
    this.height,
    this.focused = false,
    this.pinned = false,
    this.favorite = false,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final String code;
  final String label;
  final bool selected;
  final double? height;
  final bool focused;
  final bool pinned;
  final bool favorite;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final tileHeight = height ?? (isMobile ? 44.0 : 28.0);
    final veryCompact = tileHeight < 24;

    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: tileHeight,
            padding: EdgeInsets.symmetric(
              horizontal: veryCompact ? 4 : 6,
              vertical: veryCompact ? 1 : 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: focused
                  ? Border.all(
                      color: t.accent,
                      width: FfTokens.focusOutlineWidth,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: veryCompact ? 14 : 18,
                  decoration: BoxDecoration(
                    color: selected ? t.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: veryCompact ? 4 : 6),
                SizedBox(
                  width: veryCompact ? 18 : 22,
                  child: Text(
                    code,
                    style: t.jerseyStyle.copyWith(
                      fontSize:
                          veryCompact ? t.textSizeMicro : t.textSizeJersey,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                SizedBox(width: veryCompact ? 4 : 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: t.metaStyle.copyWith(
                        color: t.text,
                        fontWeight: FfTokens.weightRegular,
                      ),
                    ),
                  ),
                ),
                if (favorite)
                  Icon(Icons.star_rounded, size: 13, color: t.accent),
                if (pinned) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.push_pin_rounded, size: 13, color: t.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
