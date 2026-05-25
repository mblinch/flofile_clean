import 'package:flutter/material.dart';

/// One row in the caption-style dropdown (label + optional saved icon + star).
class CaptionStyleDropdownListRow extends StatelessWidget {
  const CaptionStyleDropdownListRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isFavorite,
    required this.showSavedIcon,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  final String label;
  final bool isSelected;
  final bool isFavorite;
  final bool showSavedIcon;
  final VoidCallback onSelect;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (showSavedIcon)
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
                  color: Colors.grey.shade800,
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
  }
}
