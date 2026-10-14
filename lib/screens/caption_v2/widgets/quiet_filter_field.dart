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
    this.hideIconWhenFilled = false,
  });

  final TextEditingController controller;
  final FfTokens tokens;
  final ValueChanged<String>? onChanged;
  final double height;
  final String hint;

  /// Empty width kept at the start of the field so a pinned jersey can sit
  /// there without changing the field's size.
  final double leadingInset;

  /// Player search: drop the magnifying glass and [leadingInset] once the
  /// field has text, so the caret starts at the field's normal left padding.
  final bool hideIconWhenFilled;

  @override
  State<QuietFilterField> createState() => _QuietFilterFieldState();
}

class _QuietFilterFieldState extends State<QuietFilterField> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    _filled = widget.controller.text.isNotEmpty;
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(QuietFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onTextChanged);
    _filled = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
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

  void _onTextChanged() {
    if (!widget.hideIconWhenFilled) return;
    final filled = widget.controller.text.isNotEmpty;
    if (filled == _filled) return;
    setState(() => _filled = filled);
  }

  bool get _showLeading => !widget.hideIconWhenFilled || !_filled;

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
            if (_showLeading && widget.leadingInset > 0)
              SizedBox(width: widget.leadingInset),
            if (_showLeading) ...[
              PhosphorIcon(
                PhosphorIconsRegular.magnifyingGlass,
                size: 14,
                color: t.textTertiary,
              ),
              const SizedBox(width: 5),
            ],
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
