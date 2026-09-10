import 'package:flutter/material.dart';

import '../../../caption_style/caption_text_normalize.dart';
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
    this.firebarSelected = false,
    this.highlightQuery = '',
    this.onTap,
    this.onSecondaryTapDown,
  });

  final String code;
  final String label;
  final bool selected;
  final double? height;
  final bool focused;
  final bool pinned;
  final bool firebarSelected;
  final String highlightQuery;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final tileHeight = height ?? (isMobile ? 44.0 : 28.0);
    final veryCompact = tileHeight < 24;
    final labelFontSize =
        (t.textSizeMeta + ((tileHeight - 24) / 4)).clamp(11.0, 16.0).toDouble();

    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
              color: firebarSelected
                  ? FfTokens.firebar.withValues(alpha: 0.16)
                  : null,
              borderRadius: BorderRadius.circular(6),
              border: firebarSelected
                  ? Border.all(
                      color: FfTokens.firebar.withValues(alpha: 0.42),
                    )
                  : focused
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
                if (code.isNotEmpty) ...[
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
                ],
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      _highlightedVerb(
                        label,
                        highlightQuery,
                        normal: t.metaStyle.copyWith(
                          fontSize: labelFontSize,
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

TextSpan _highlightedVerb(
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
  final highlighted = normal.copyWith(
    color: FfTokens.firebar,
    fontWeight: FontWeight.w600,
  );
  if (start >= 0) {
    final end = (start + normalizedQuery.length).clamp(0, text.length);
    return TextSpan(
      style: normal,
      children: [
        if (start > 0) TextSpan(text: text.substring(0, start)),
        TextSpan(text: text.substring(start, end), style: highlighted),
        if (end < text.length) TextSpan(text: text.substring(end)),
      ],
    );
  }

  final wordStarts = RegExp(r'[a-z0-9]+')
      .allMatches(normalizedText)
      .map((match) => match.start)
      .toList();
  final initials = wordStarts.map((index) => normalizedText[index]).join();
  if (normalizedQuery.isEmpty || !initials.startsWith(normalizedQuery)) {
    return TextSpan(text: text, style: normal);
  }
  final highlightIndexes = wordStarts.take(normalizedQuery.length).toSet();
  return TextSpan(
    style: normal,
    children: [
      for (var index = 0; index < text.length; index++)
        TextSpan(
          text: text[index],
          style: highlightIndexes.contains(index) ? highlighted : null,
        ),
    ],
  );
}
