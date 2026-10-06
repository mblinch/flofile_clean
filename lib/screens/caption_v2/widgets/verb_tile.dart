import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/caption_text_normalize.dart';
import '../../../theme/ff_tokens.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Tap target that runs [onCmdTap] for Cmd-click and [onTap] otherwise.
///
/// Cmd is read on pointer-down. By the time [onTap] fires the key is often
/// already up, so that later tap is skipped when the down event pinned.
class CmdClick extends StatefulWidget {
  const CmdClick({
    super.key,
    required this.child,
    this.onTap,
    this.onCmdTap,
    this.onSecondaryTapDown,
    this.useInkWell = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onCmdTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool useInkWell;

  @override
  State<CmdClick> createState() => _CmdClickState();
}

class _CmdClickState extends State<CmdClick> {
  bool _handledByCmd = false;

  void _onTapDown(TapDownDetails _) {
    _handledByCmd =
        HardwareKeyboard.instance.isMetaPressed && widget.onCmdTap != null;
  }

  void _onTapCancel() {
    _handledByCmd = false;
  }

  void _onTap() {
    if (_handledByCmd) {
      _handledByCmd = false;
      widget.onCmdTap!();
      return;
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useInkWell) {
      return InkWell(
        onTapDown: _onTapDown,
        onTap: _onTap,
        onTapCancel: _onTapCancel,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTap: _onTap,
      onTapCancel: _onTapCancel,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      child: widget.child,
    );
  }
}

/// Verb list tile: monospace code + label.
///
/// Selected verbs use only a leading accent bar beside the number.
class VerbTile extends StatefulWidget {
  const VerbTile({
    super.key,
    required this.code,
    required this.label,
    required this.selected,
    this.height,
    this.focused = false,
    this.pinned = false,
    this.dimmed = false,
    this.firebarSelected = false,
    this.highlightQuery = '',
    this.onTap,
    this.onPinTap,
    this.onSecondaryTapDown,
  });

  final String code;
  final String label;
  final bool selected;
  final double? height;
  final bool focused;
  final bool pinned;
  final bool dimmed;
  final bool firebarSelected;
  final String highlightQuery;
  final VoidCallback? onTap;
  final VoidCallback? onPinTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<VerbTile> createState() => _VerbTileState();
}

class _VerbTileState extends State<VerbTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final tileHeight = widget.height ?? (isMobile ? 44.0 : 28.0);
    final veryCompact = tileHeight < 24;
    final labelColor = widget.dimmed
        ? t.text.withValues(alpha: 0.38)
        : t.text;

    Color? fill;
    if (widget.firebarSelected) {
      fill = FfTokens.firebar.withValues(alpha: 0.16);
    } else if (widget.selected) {
      fill = t.selected;
    } else if (_hovered) {
      fill = t.hover;
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
              height: tileHeight,
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
                  if (widget.code.isNotEmpty) ...[
                    SizedBox(
                      width: veryCompact ? 18 : 22,
                      child: Text(
                        widget.code,
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
                    child: Text.rich(
                      _highlightedVerb(
                        widget.label,
                        widget.highlightQuery,
                        normal: FfTokens.rosterName(
                          color: labelColor,
                          selected: widget.selected,
                        ),
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.pinned) ...[
                    const SizedBox(width: 3),
                    if (widget.onPinTap != null)
                      IconButton(
                        onPressed: widget.onPinTap,
                        tooltip: 'Unpin for next frames',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tightFor(
                          width: veryCompact ? 24 : 28,
                          height: veryCompact ? 20 : 24,
                        ),
                        visualDensity: VisualDensity.compact,
                        iconSize: veryCompact ? 12 : 14,
                        color: widget.dimmed
                            ? t.text.withValues(alpha: 0.38)
                            : FfTokens.pinned,
                        icon: const PhosphorIcon(PhosphorIconsFill.pushPin),
                      )
                    else
                      PhosphorIcon(PhosphorIconsFill.pushPin,
                        size: 13,
                        color: widget.dimmed
                            ? t.text.withValues(alpha: 0.38)
                            : FfTokens.pinned,
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
