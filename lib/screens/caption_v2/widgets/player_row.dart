import 'package:flutter/material.dart';

import '../../../caption_style/caption_text_normalize.dart';
import '../../../theme/ff_tokens.dart';

/// Roster row: monospace jersey badge + name.
///
/// Selected: accent tint fill, 1px accent@50% border, badge inverted to accent
/// fill with [FfTokens.inkOnAccent] text, trailing check.
class PlayerRow extends StatelessWidget {
  const PlayerRow({
    super.key,
    required this.jersey,
    required this.name,
    required this.selected,
    this.height,
    this.usageCount,
    this.selectionRole,
    this.focused = false,
    this.firebarSelected = false,
    this.highlightQuery = '',
    this.onTap,
  });

  final String jersey;
  final String name;
  final bool selected;
  final double? height;
  final int? usageCount;
  final String? selectionRole;
  final bool focused;
  final bool firebarSelected;
  final String highlightQuery;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = onTap != null;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final rowHeight = height ?? (isMobile ? 44.0 : 28.0);
    final veryCompact = rowHeight < 24;
    final nameFontSize =
        (t.textSizeMeta + ((rowHeight - 24) / 4)).clamp(11.0, 16.0).toDouble();

    return Semantics(
      button: enabled,
      enabled: enabled,
      selected: selected,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: rowHeight,
            padding: EdgeInsets.symmetric(
              horizontal: veryCompact ? 4 : 6,
              vertical: veryCompact ? 1 : 2,
            ),
            decoration: BoxDecoration(
              color: firebarSelected
                  ? FfTokens.firebar.withValues(alpha: 0.16)
                  : selected
                      ? t.selectedFill
                      : null,
              borderRadius: BorderRadius.circular(6),
              border: firebarSelected
                  ? Border.all(
                      color: FfTokens.firebar.withValues(alpha: 0.42),
                    )
                  : selected || focused
                      ? Border.all(
                          color: selected ? t.selectedBorder : t.accent,
                          width: focused && !selected
                              ? FfTokens.focusOutlineWidth
                              : 1,
                        )
                      : null,
            ),
            child: Row(
              children: [
                _JerseyBadge(
                  jersey: jersey,
                  selected: selected,
                  highlightQuery: highlightQuery,
                  tokens: t,
                ),
                SizedBox(width: veryCompact ? 5 : 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      _highlightedText(
                        name,
                        highlightQuery,
                        normal: t.metaStyle.copyWith(
                          fontSize: nameFontSize,
                          color: t.text,
                          fontWeight: selected
                              ? FfTokens.weightMedium
                              : FfTokens.weightRegular,
                        ),
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
                if (usageCount != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${usageCount}x',
                    style: t.microStyle,
                  ),
                ],
                if (selected && selectionRole != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    selectionRole!,
                    style: t.microStyle.copyWith(
                      color: t.accent,
                      fontWeight: FfTokens.weightMedium,
                    ),
                  ),
                ],
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check,
                    size: 14,
                    color: t.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JerseyBadge extends StatelessWidget {
  const _JerseyBadge({
    required this.jersey,
    required this.selected,
    required this.highlightQuery,
    required this.tokens,
  });

  final String jersey;
  final bool selected;
  final String highlightQuery;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? tokens.accent : tokens.badgeFill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text.rich(
        _highlightedText(
          jersey,
          RegExp(r'^\d+$').hasMatch(highlightQuery) ? highlightQuery : '',
          normal: tokens.jerseyStyle.copyWith(
            fontSize: tokens.textSizeMicro,
            color: selected ? tokens.inkOnAccent : tokens.text,
            height: 1.1,
          ),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

TextSpan _highlightedText(
  String text,
  String query, {
  required TextStyle normal,
}) {
  final normalizedQuery =
      CaptionTextNormalize.stripDiacritics(query).toLowerCase();
  final normalizedText =
      CaptionTextNormalize.stripDiacritics(text).toLowerCase();
  final start =
      normalizedQuery.isEmpty ? -1 : normalizedText.indexOf(normalizedQuery);
  if (start < 0) return TextSpan(text: text, style: normal);
  final end = (start + normalizedQuery.length).clamp(0, text.length);
  return TextSpan(
    style: normal,
    children: [
      if (start > 0) TextSpan(text: text.substring(0, start)),
      TextSpan(
        text: text.substring(start, end),
        style: normal.copyWith(
          color: FfTokens.firebar,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (end < text.length) TextSpan(text: text.substring(end)),
    ],
  );
}
