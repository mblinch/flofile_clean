import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shared card/panel shell: [AppTokens.surface] background, 1px
/// [AppTokens.cardBorder], [AppTokens.radiusCard] corners, and
/// [AppTokens.cardShadow].
///
/// Not yet adopted anywhere — later passes migrate panels onto it one at a
/// time so each visual change can be reviewed in isolation.
class CardContainer extends StatelessWidget {
  const CardContainer({
    super.key,
    required this.child,
    this.padding,
    this.header,
    this.trailingHeader,
    this.headerHeight = 40,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.headerBackground,
    this.accentTopBorder = false,
    this.accentTopBorderWidth = 3,
    this.background = AppTokens.surface,
  });

  final Widget child;

  /// Padding around [child] (the header row is never padded by this).
  final EdgeInsetsGeometry? padding;

  /// Optional 40px header row rendered in [AppTokens.panelHeading] with a
  /// bottom border.
  final Widget? header;

  /// Optional widget aligned to the right end of the header row.
  final Widget? trailingHeader;

  /// Header row height. Defaults to the standard 40px panel header.
  final double headerHeight;

  /// Header content padding.
  final EdgeInsetsGeometry headerPadding;

  /// Optional fill behind the header row.
  final Color? headerBackground;

  /// Adds a 3px accent strip clipped within the card's top corners.
  final bool accentTopBorder;

  /// Stroke width used when [accentTopBorder] is enabled.
  final double accentTopBorderWidth;

  /// Card fill. Defaults to the standard surface, but fixed-purpose surrounds
  /// such as the photo viewer can supply their own neutral.
  final Color background;

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (padding != null) {
      body = Padding(padding: padding!, child: body);
    }

    final hasHeader = header != null || trailingHeader != null;
    final Widget content;
    if (!accentTopBorder && !hasHeader) {
      content = body;
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accentTopBorder) SizedBox(height: accentTopBorderWidth),
          if (hasHeader)
            Container(
              height: headerHeight,
              padding: headerPadding,
              decoration: BoxDecoration(
                color: headerBackground,
                border: const Border(
                  bottom: BorderSide(color: AppTokens.cardBorder),
                ),
              ),
              child: Row(
                children: [
                  if (header != null)
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: AppTokens.panelHeading.copyWith(
                          color: AppTokens.ink,
                        ),
                        child: header!,
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailingHeader != null) trailingHeader!,
                ],
              ),
            ),
          body,
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.cardShadow,
      ),
      child: CustomPaint(
        foregroundPainter: accentTopBorder
            ? _AccentTopBorderPainter(accentTopBorderWidth)
            : null,
        child: content,
      ),
    );
  }
}

class _AccentTopBorderPainter extends CustomPainter {
  const _AccentTopBorderPainter(this.strokeWidth);

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    const radius = AppTokens.radiusControl;
    final path = Path()
      ..moveTo(inset, radius)
      ..quadraticBezierTo(inset, inset, radius, inset)
      ..lineTo(size.width - radius, inset)
      ..quadraticBezierTo(
        size.width - inset,
        inset,
        size.width - inset,
        radius,
      );
    final paint = Paint()
      ..color = AppTokens.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AccentTopBorderPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}
