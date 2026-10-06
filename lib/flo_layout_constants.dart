import 'package:flutter/material.dart';

/// Main app top bar ([AppHeaderWidget] / [FloChromeHeader]) and dialog title bars.
const double kFloAppHeaderHeight = 34.0;

/// Pic preview top/bottom bars, caption (CAPTION) title row, thumbnail toolbar,
/// and Keyboard Fire caption strip header — keep heights aligned (compact strip).
const double kFloChromeHeaderHeight = 22.0;

/// Inning / period / quarter selector buttons, +/− page nav, MLB clock chip,
/// Prior/Post-Game toggles, and overtime expand buttons.
const double kFloInningButtonHeight = 22.0;

/// Border radius for inning / period / +/− buttons.
const double kFloInningButtonRadius = 5.0;

/// Trailing inset on scrollable content so the scrollbar thumb never covers rows.
const double kFloScrollbarGutter = 12.0;

/// Visible scrollbar thickness (pairs with [kFloScrollbarGutter]).
const double kFloScrollbarThickness = 8.0;

/// Optional content padding for scrollables that need additional trailing room.
EdgeInsets floScrollPadding({
  double left = 0,
  double top = 0,
  double bottom = 0,
  double? right,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top,
    right ?? kFloScrollbarGutter,
    bottom,
  );
}

/// App scrollbar with a reserved trailing gutter so its thumb never overlaps
/// the scrollable content.
class FloScrollbar extends StatelessWidget {
  const FloScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility = true,
    this.trackVisibility = false,
    this.thickness = kFloScrollbarThickness,
  });

  final Widget child;
  final ScrollController? controller;
  final bool thumbVisibility;
  final bool trackVisibility;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      trackVisibility: trackVisibility,
      thickness: thickness,
      radius: const Radius.circular(4),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          end: kFloScrollbarGutter,
        ),
        child: child,
      ),
    );
  }
}

/// Desktop vertical scrollbars use [FloScrollbar], which reserves its own
/// gutter outside the scrollable viewport.
class FloScrollBehavior extends MaterialScrollBehavior {
  const FloScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (axisDirectionToAxis(details.direction)) {
      case Axis.horizontal:
        return child;
      case Axis.vertical:
        return FloScrollbar(
          controller: details.controller,
          child: child,
        );
    }
  }
}

/// Nocturne accent / surfaces (teal palette).
/// Names retain historical `Teal` identifiers for call-site compatibility.
const Color kFloTealLight = Color(0xFF4A7A96); // --color-accent
const Color kFloTealDark = Color(0xFF3A6076); // --color-accent-edge
const Color kFloTealMid = Color(0xFF6A6E73); // --color-text-muted approx

/// Selected chip / player cell fill (--color-accent-soft).
const Color kFloTealSelectedFill = Color(0xFF20313C);

/// Submenu strip beside verb options (RBI, reactions, base, etc.) (--color-surface).
const Color kFloTealSubmenuFill = Color(0xFF1E242A);

/// Flat Nocturne fills — gradients kept as API but resolve to solid accent / soft.
const LinearGradient kFloTealGradientHorizontal = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kFloTealLight, kFloTealLight],
);

/// Selected verb row fill (--color-accent-soft).
const LinearGradient kFloTealGradientHorizontalLight = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kFloTealSelectedFill, kFloTealSelectedFill],
);

/// Edit Verb section headers (--color-hover).
const LinearGradient kFloTealGradientHorizontalHeader = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF2A3035), Color(0xFF2A3035)],
);

/// Idle category rows in Keyboard Fire (--color-elevated).
const LinearGradient kFloCategoryRowGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF181D22), Color(0xFF181D22)],
);

const LinearGradient kFloTealGradientVertical = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kFloTealLight, kFloTealLight],
);

/// Admin-only control chrome (gold).
const Color kFloAdminGoldLight = Color(0xFFE8C547); // --gold
const Color kFloAdminGoldDark = Color(0xFFE8C547);
const Color kFloAdminGoldText = Color(0xFF1A1606); // ink on gold

const LinearGradient kFloAdminGoldGradientHorizontal = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kFloAdminGoldLight, kFloAdminGoldDark],
);

const LinearGradient kFloAdminGoldGradientVertical = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kFloAdminGoldLight, kFloAdminGoldDark],
);

/// Selected toggle chip / inning cell: --sf fill + 2px --ac left bar.
BoxDecoration floTealSelectedDecoration({
  BorderRadius? borderRadius,
  bool gradient = true,
}) {
  return BoxDecoration(
    color: kFloTealSelectedFill,
    borderRadius: borderRadius ?? BorderRadius.circular(kFloInningButtonRadius),
    border: const Border(
      left: BorderSide(color: kFloTealLight, width: 2),
    ),
  );
}

/// Selected row/chip: --sf fill + 2px --ac left bar (no coloured wash).
BoxDecoration floTealSelectedChipDecoration({BorderRadius? borderRadius}) {
  return BoxDecoration(
    color: kFloTealSelectedFill,
    borderRadius: borderRadius ?? BorderRadius.circular(3),
    border: const Border(
      left: BorderSide(color: kFloTealLight, width: 2),
    ),
  );
}

/// Horizontal progress fill: track with --ac growing left → right.
class FloTealGradientProgressBar extends StatelessWidget {
  const FloTealGradientProgressBar({
    super.key,
    required this.value,
    this.height = 14,
    this.trackColor = Colors.white,
    this.borderColor = const Color(0xFFD0D0D0),
    this.borderRadius,
    this.animationDuration = const Duration(milliseconds: 220),
  });

  final double value;
  final double height;
  final Color trackColor;
  final Color borderColor;
  final BorderRadius? borderRadius;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(height / 2);
    final fill = value.clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 0.7),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final fillWidth = trackWidth * fill;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: trackColor),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: animationDuration,
                      curve: Curves.easeOutCubic,
                      width: fillWidth,
                      height: height,
                      decoration: const BoxDecoration(
                        gradient: kFloTealGradientHorizontal,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
