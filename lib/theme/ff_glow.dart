import 'package:flutter/material.dart';

import 'ff_tokens.dart';

/// Soft radial “spotlight” behind a heading.
///
/// Mirrors the website `.glow` utility: background only — no text-shadow,
/// no colour change on [child], and never intercepts pointer events.
///
/// Tune per call site with [glowX], [glowY], [glowW], [glowH], [glowColor]
/// (same knobs as the CSS variables).
class FfGlow extends StatelessWidget {
  const FfGlow({
    super.key,
    required this.child,
    this.glowX = -0.15,
    this.glowY = -0.60,
    this.glowW = 220,
    this.glowH = 140,
    this.glowColor,
  });

  final Widget child;

  /// Left offset as a fraction of the wrapper width (CSS `--glow-x`).
  final double glowX;

  /// Top offset as a fraction of the wrapper height (CSS `--glow-y`).
  final double glowY;

  /// Glow ellipse width in logical pixels (CSS `--glow-w`).
  final double glowW;

  /// Glow ellipse height in logical pixels (CSS `--glow-h`).
  final double glowH;

  /// Glow colour; defaults to teal accent @ ~0.18.
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final color = glowColor ?? FfTokens.glow;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
                return const SizedBox.shrink();
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: w * glowX,
                    top: h * glowY,
                    width: glowW,
                    height: glowH,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              color,
                              color.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}
