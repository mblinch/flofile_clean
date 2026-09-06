import 'package:flutter/material.dart';

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
    final row = InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (showLockIcon)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
              )
            else if (showSavedIcon)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.bookmark_outline,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: showLockIcon
                      ? Colors.grey.shade600
                      : Colors.grey.shade800,
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
                  isFavorite ? Icons.star : Icons.star_border,
                  size: 16,
                  color: isFavorite ? Colors.amber : Colors.grey.shade400,
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
              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
              const SizedBox(height: 4),
              Text(
                'CUSTOM',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.grey.shade500,
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
