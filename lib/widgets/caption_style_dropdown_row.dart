import 'package:flutter/material.dart';

import '../theme/ff_tokens.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// One row in the caption-style dropdown (label + optional lock/saved icon + star).
class CaptionStyleDropdownListRow extends StatelessWidget {
  const CaptionStyleDropdownListRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isFavorite,
    required this.showSavedIcon,
    required this.onSelect,
    required this.onToggleFavorite,
    this.showDividerAbove = false,
    this.showLockIcon = false,
  });

  final String label;
  final bool isSelected;
  final bool isFavorite;
  final bool showSavedIcon;
  final VoidCallback onSelect;
  final VoidCallback onToggleFavorite;
  final bool showDividerAbove;
  final bool showLockIcon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final row = InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (showLockIcon)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: PhosphorIcon(PhosphorIconsRegular.lock,
                  size: 13,
                  color: t.textSecondary,
                ),
              )
            else if (showSavedIcon)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: PhosphorIcon(PhosphorIconsRegular.bookmarkSimple,
                  size: 14,
                  color: t.textSecondary,
                ),
              ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: showLockIcon ? t.textSecondary : t.text,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onSelect();
                onToggleFavorite();
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isFavorite ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                  size: 16,
                  color: isFavorite
                      ? const Color(0xFFE6B84A)
                      : t.text.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!showDividerAbove) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 1, thickness: 1, color: t.divider),
              const SizedBox(height: 4),
              Text(
                'CUSTOM',
                style: FfTokens.railLabel.copyWith(
                  fontSize: 9,
                  color: t.text.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
        row,
      ],
    );
  }
}
