import 'package:flutter/material.dart';

import '../../../caption_style/caption_text_normalize.dart';
import '../../../theme/ff_tokens.dart';
import 'verb_tile.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Roster row: jersey badge + name.
///
/// Selected: --sf fill + 2px --ac left bar, --text @ 600, 5px radius.
/// Hover: --hv. Long names ellipsize.
class PlayerRow extends StatefulWidget {
  const PlayerRow({
    super.key,
    required this.jersey,
    required this.name,
    required this.selected,
    this.height,
    this.usageCount,
    this.selectionRole,
    this.focused = false,
    this.pinned = false,
    this.firebarSelected = false,
    this.highlightQuery = '',
    this.onTap,
    this.onPinTap,
    this.onGoogleTap,
    this.onReportTap,
    this.onSecondaryTapDown,
  });

  final String jersey;
  final String name;
  final bool selected;
  final double? height;
  final int? usageCount;
  final String? selectionRole;
  final bool focused;
  final bool pinned;
  final bool firebarSelected;
  final String highlightQuery;
  final VoidCallback? onTap;
  final VoidCallback? onPinTap;
  final VoidCallback? onGoogleTap;
  final VoidCallback? onReportTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<PlayerRow> createState() => _PlayerRowState();
}

class _PlayerRowState extends State<PlayerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final enabled = widget.onTap != null || widget.onPinTap != null;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final rowHeight = widget.height ?? (isMobile ? 44.0 : 28.0);
    final veryCompact = rowHeight < 24;
    final iconSize = veryCompact ? 15.0 : 17.0;
    final showActions = _hovered &&
        (widget.onPinTap != null ||
            widget.onGoogleTap != null ||
            widget.onReportTap != null);
    final showPin =
        widget.pinned || (_hovered && widget.onPinTap != null);

    Color? fill;
    if (widget.firebarSelected) {
      fill = FfTokens.firebar.withValues(alpha: 0.16);
    } else if (widget.selected) {
      fill = t.selected;
    } else if (_hovered) {
      fill = t.hover;
    }

    return Semantics(
      button: enabled,
      enabled: enabled,
      selected: widget.selected,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        opaque: false,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: CmdClick(
          onTap: widget.onTap,
          onCmdTap: widget.onPinTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: rowHeight,
              padding: EdgeInsets.symmetric(
                horizontal: veryCompact ? 4 : 6,
                vertical: veryCompact ? 1 : 2,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(FfTokens.radiusRow),
                border: widget.firebarSelected
                    ? Border.all(
                        color: FfTokens.firebar.withValues(alpha: 0.42),
                      )
                    : widget.selected
                        ? const Border(
                            left: BorderSide(
                              color: FfTokens.nocturneAc,
                              width: 2,
                            ),
                          )
                        : widget.focused
                            ? Border.all(
                                color: t.accent,
                                width: FfTokens.focusOutlineWidth,
                              )
                            : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      widget.jersey,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: FfTokens.rosterJersey(color: t.textTertiary),
                    ),
                  ),
                  SizedBox(width: veryCompact ? 5 : 8),
                  Expanded(
                    child: Text.rich(
                      _highlightedText(
                        widget.name,
                        widget.highlightQuery,
                        normal: FfTokens.rosterName(
                          color: t.text,
                          selected: widget.selected,
                        ),
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.usageCount != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${widget.usageCount}x',
                      style: t.microStyle,
                    ),
                  ],
                  if (widget.selected && widget.selectionRole != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      widget.selectionRole!,
                      style: t.microStyle.copyWith(
                        color: t.textSecondary,
                        fontWeight: FfTokens.weightMedium,
                      ),
                    ),
                  ],
                  if (showPin && !showActions) ...[
                    const SizedBox(width: 3),
                    PhosphorIcon(PhosphorIconsFill.pushPin,
                      size: veryCompact ? 15 : 17,
                      color: FfTokens.pinned,
                    ),
                  ],
                  if (showActions) ...[
                    const SizedBox(width: 2),
                    if (widget.onPinTap != null)
                      _PlayerHoverAction(
                        tooltip: widget.pinned
                            ? 'Unpin for next frames'
                            : 'Pin for next frames',
                        icon: PhosphorIconsFill.pushPin,
                        color: FfTokens.pinned,
                        size: iconSize,
                        onTap: widget.onPinTap!,
                      ),
                    if (widget.onGoogleTap != null)
                      _PlayerHoverAction(
                        tooltip: 'Google this player',
                        icon: PhosphorIconsRegular.magnifyingGlass,
                        color: t.textSecondary,
                        size: iconSize,
                        onTap: widget.onGoogleTap!,
                      ),
                    if (widget.onReportTap != null)
                      _PlayerHoverAction(
                        tooltip: 'Report wrong number or spelling',
                        icon: PhosphorIconsRegular.flag,
                        color: t.textSecondary,
                        size: iconSize,
                        onTap: widget.onReportTap!,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerHoverAction extends StatelessWidget {
  const _PlayerHoverAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: PhosphorIcon(icon, size: size, color: color),
          ),
        ),
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
