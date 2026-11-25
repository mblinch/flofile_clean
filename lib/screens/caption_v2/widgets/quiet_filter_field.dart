import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';

/// Quiet roster filter: transparent until hover/focus (not a black box).
class QuietFilterField extends StatefulWidget {
  const QuietFilterField({
    super.key,
    required this.controller,
    required this.tokens,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.height = 26,
    this.hint = 'Search',
    this.leadingInset = 0,
    this.hideIconWhenFilled = false,
    this.fillColor,
    this.fontSize = 12.5,
    this.fontWeight = FfTokens.weightRegular,
    this.borderRadius = 7,
    this.iconSize = 14,
    this.iconColor,
    this.showFocusBorder = true,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 6),
    this.trailing,
    this.onKeyEvent,
  });

  final TextEditingController controller;
  final FfTokens tokens;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final double height;
  final String hint;

  /// Empty width kept at the start of the field before the magnifying glass.
  final double leadingInset;

  /// Player search: drop the magnifying glass and [leadingInset] once the
  /// field has text, so the caret starts at the field's normal left padding.
  final bool hideIconWhenFilled;

  /// When set, always paints this fill (verb panel search uses sunken).
  final Color? fillColor;
  final double fontSize;
  final FontWeight fontWeight;
  final double borderRadius;
  final double iconSize;
  final Color? iconColor;
  final bool showFocusBorder;
  final EdgeInsetsGeometry contentPadding;

  /// Optional trailing chip (e.g. match count) inside the field.
  final Widget? trailing;

  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  @override
  State<QuietFilterField> createState() => _QuietFilterFieldState();
}

class _QuietFilterFieldState extends State<QuietFilterField> {
  FocusNode? _ownedFocus;
  bool _hovered = false;
  bool _focused = false;
  bool _filled = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    _filled = widget.controller.text.isNotEmpty;
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(QuietFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      if (oldWidget.focusNode == null && widget.focusNode != null) {
        _ownedFocus
          ?..removeListener(_onFocusChanged)
          ..dispose();
        _ownedFocus = null;
      } else if (oldWidget.focusNode != null && widget.focusNode == null) {
        _ownedFocus = FocusNode();
      }
      _focusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onTextChanged);
    _filled = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _ownedFocus?.dispose();
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
    final fill = widget.fillColor ?? t.bg;
    final iconColor = widget.iconColor ?? t.textTertiary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: widget.height,
        padding: widget.contentPadding,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: widget.showFocusBorder && _focused
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
                size: widget.iconSize,
                color: iconColor,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Focus(
                onKeyEvent: widget.onKeyEvent,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: widget.fontSize,
                    fontWeight: widget.fontWeight,
                    color: t.text,
                    height: 1,
                  ),
                  cursorColor: t.accent,
                  cursorHeight: widget.fontSize,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: widget.fontSize,
                      fontWeight: widget.fontWeight,
                      color: iconColor,
                    ),
                  ),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 6),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
