import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Grouped "small A / big A" text-size control (option A visual spec).
///
/// Callers keep their own step/limit/persistence logic; this only renders the
/// two buttons and forwards taps. [height] should match the adjacent search
/// field so the control lines up in the panel header.
class AaTextSizeControl extends StatelessWidget {
  const AaTextSizeControl({
    super.key,
    required this.canSmaller,
    required this.canLarger,
    required this.onSmaller,
    required this.onLarger,
    this.height = 26,
  });

  final bool canSmaller;
  final bool canLarger;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;

  /// Total outer height (padding included). Match the search bar beside it.
  final double height;

  static const double _pad = 2;

  @override
  Widget build(BuildContext context) {
    final buttonSize = height - _pad * 2;
    final dividerInset = (buttonSize * 0.2).clamp(3.0, 6.0);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FfTokens.nocturneSunken,
          borderRadius: BorderRadius.circular(height >= 32 ? 8 : 7),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AaButton(
                  label: 'A',
                  fontSize: 10,
                  size: buttonSize,
                  tooltip: 'Smaller text',
                  enabled: canSmaller,
                  onTap: onSmaller,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dividerInset),
                  child: const SizedBox(
                    width: 1,
                    child: ColoredBox(color: FfTokens.nocturneLn),
                  ),
                ),
                _AaButton(
                  label: 'A',
                  fontSize: 15,
                  size: buttonSize,
                  tooltip: 'Larger text',
                  enabled: canLarger,
                  onTap: onLarger,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AaButton extends StatefulWidget {
  const _AaButton({
    required this.label,
    required this.fontSize,
    required this.size,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final double fontSize;
  final double size;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_AaButton> createState() => _AaButtonState();
}

class _AaButtonState extends State<_AaButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final Color background;
    final Color foreground;
    if (!enabled) {
      background = Colors.transparent;
      foreground = FfTokens.nocturneT2;
    } else if (_pressed) {
      background = FfTokens.nocturneAccentSoft;
      foreground = Colors.white;
    } else if (_hovered) {
      background = FfTokens.nocturneHv;
      foreground = FfTokens.nocturneTx;
    } else {
      background = Colors.transparent;
      foreground = FfTokens.nocturneT2;
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        hitTestBehavior: HitTestBehavior.opaque,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: enabled
              ? (_) {
                  setState(() => _pressed = true);
                  widget.onTap();
                }
              : null,
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(widget.size >= 28 ? 6 : 5),
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
