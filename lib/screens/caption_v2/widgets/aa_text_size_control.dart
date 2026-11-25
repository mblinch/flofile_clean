import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Grouped "small A / big A" text-size control (option A visual spec).
///
/// Callers keep their own step/limit/persistence logic; this only renders the
/// buttons and forwards taps. Optional [onFit] adds a third "Fit" action that
/// sizes content to the on-screen box. [height] should match the adjacent
/// search field so the control lines up in the panel header.
class AaTextSizeControl extends StatelessWidget {
  const AaTextSizeControl({
    super.key,
    required this.canSmaller,
    required this.canLarger,
    required this.onSmaller,
    required this.onLarger,
    this.onFit,
    this.height = 26,
  });

  final bool canSmaller;
  final bool canLarger;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;

  /// When set, shows a third "Fit" button after the A/A pair.
  final VoidCallback? onFit;

  /// Total outer height (padding included). Match the search bar beside it.
  final double height;

  static const double _pad = 2;

  @override
  Widget build(BuildContext context) {
    final buttonSize = height - _pad * 2;
    // Wider than tall so the A/A hits aren't cramped beside Expanded search.
    final buttonWidth = (buttonSize + 6).clamp(22.0, 28.0);
    final dividerInset = (buttonSize * 0.18).clamp(2.0, 5.0);
    final smallA = height <= 24 ? 9.0 : 10.0;
    final bigA = height <= 24 ? 13.0 : 15.0;
    final fitLabel = height <= 24 ? 9.0 : 10.0;
    final showFit = onFit != null;
    // "Fit" needs a bit more width than a single A.
    final fitWidth = showFit ? (buttonWidth + 10).clamp(32.0, 40.0) : 0.0;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FfTokens.nocturneSunken,
          borderRadius: BorderRadius.circular(height >= 30 ? 7 : 6),
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
                  fontSize: smallA,
                  width: buttonWidth,
                  height: buttonSize,
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
                  fontSize: bigA,
                  width: buttonWidth,
                  height: buttonSize,
                  tooltip: 'Larger text',
                  enabled: canLarger,
                  onTap: onLarger,
                ),
                if (showFit) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: dividerInset),
                    child: const SizedBox(
                      width: 1,
                      child: ColoredBox(color: FfTokens.nocturneLn),
                    ),
                  ),
                  _AaButton(
                    label: 'Fit',
                    fontSize: fitLabel,
                    width: fitWidth,
                    height: buttonSize,
                    tooltip: 'Fit to box',
                    enabled: true,
                    onTap: onFit!,
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

class _AaButton extends StatefulWidget {
  const _AaButton({
    required this.label,
    required this.fontSize,
    required this.width,
    required this.height,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final double fontSize;
  final double width;
  final double height;
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
              width: widget.width,
              height: widget.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius:
                    BorderRadius.circular(widget.height >= 26 ? 5 : 4),
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
