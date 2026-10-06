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
  });

  final TextEditingController controller;
  final FfTokens tokens;
  final ValueChanged<String>? onChanged;
  final double height;

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
    final fill = _focused
        ? t.sunken
        : (_hovered
            ? t.sunken.withValues(alpha: 0.85)
            : t.sunken.withValues(alpha: 0.65));
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
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
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
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
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
