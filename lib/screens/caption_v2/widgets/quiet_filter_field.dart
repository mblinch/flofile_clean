import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';

/// Quiet roster filter: transparent until hover/focus (not a black box).
class QuietFilterField extends StatefulWidget {
  const QuietFilterField({
    super.key,
    required this.controller,
    required this.tokens,
    this.onChanged,
    this.height = 26,
    this.hint = 'Search',
    this.leadingInset = 0,
  });

  final TextEditingController controller;
  final FfTokens tokens;
  final ValueChanged<String>? onChanged;
  final double height;
  final String hint;

  /// Empty width kept at the start of the field so a pinned jersey can sit
  /// there without changing the field's size.
  final double leadingInset;

  @override
  State<QuietFilterField> createState() => _QuietFilterFieldState();
}

class _QuietFilterFieldState extends State<QuietFilterField> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final next = _focusNode.hasFocus;
    if (next == _focused) return;
    setState(() => _focused = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final fill = _focused || _hovered ? t.bg : t.bg;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(7),
          border: _focused
              ? Border.all(color: t.accent, width: 1)
              : null,
        ),
        child: Row(
          children: [
            if (widget.leadingInset > 0) SizedBox(width: widget.leadingInset),
            PhosphorIcon(
              PhosphorIconsRegular.magnifyingGlass,
              size: 14,
              color: t.textTertiary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FfTokens.weightRegular,
                  color: t.text,
                  height: 1,
                ),
                cursorColor: t.accent,
                cursorHeight: 12,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    color: t.textTertiary,
                  ),
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
