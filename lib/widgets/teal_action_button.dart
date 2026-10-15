import 'package:flutter/material.dart';

import '../theme/ff_tokens.dart';

/// Teal caption action button (Save / FTP / Done).
class TealActionButton extends StatefulWidget {
  const TealActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  State<TealActionButton> createState() => _TealActionButtonState();
}

class _TealActionButtonState extends State<TealActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  static const LinearGradient _rest = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF243848),
      Color(0xFF15242E),
      Color(0xFF0E181F),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient _hover = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF2E4658),
      Color(0xFF1A2E3A),
      Color(0xFF121F28),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient _down = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1A2A36),
      Color(0xFF0C141A),
      Color(0xFF080E12),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    final border = !enabled
        ? FfTokens.nocturneLn
        : _hovered
            ? Colors.white.withValues(alpha: 0.92)
            : FfTokens.nocturneAc.withValues(alpha: 0.95);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled
          ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
          : null,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: enabled
                ? null
                : const Color(0xFF15242E).withValues(alpha: 0.55),
            gradient: !enabled
                ? null
                : _pressed
                    ? _down
                    : _hovered
                        ? _hover
                        : _rest,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: border),
            boxShadow: enabled
                ? FfTokens.accentButtonGlow(
                    _hovered ? Colors.white : FfTokens.nocturneAc,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.icon,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: enabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
