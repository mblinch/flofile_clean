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

/// Content padding that reserves [kFloScrollbarGutter] on the right.
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

/// App scrollbar — use with [floScrollPadding] / [kFloScrollbarGutter] on the
/// scrollable's *content* padding so the thumb does not overlap list items.
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
      child: child,
    );
  }
}

/// Desktop scrollbars use [FloScrollbar]. Pair vertical scrollables with
/// [floScrollPadding] so content clears [kFloScrollbarGutter].
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

/// FloFile teal accent (MLB clock, selections, primary actions).
const Color kFloTealLight = Color(0xFF4A7A96);
const Color kFloTealDark = Color(0xFF2A4858);
const Color kFloTealMid = Color(0xFF3A5F78);

/// Light fill behind selected chips / player cells.
const Color kFloTealSelectedFill = Color(0xFFE4EEF2);

/// Submenu strip beside verb options (RBI, reactions, base, etc.).
const Color kFloTealSubmenuFill = Color(0xFFD6E8F0);

const LinearGradient kFloTealGradientHorizontal = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kFloTealLight, kFloTealDark],
);

/// Lighter teal row fill for selected verbs (parent category uses [kFloTealGradientHorizontal]).
const LinearGradient kFloTealGradientHorizontalLight = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFC8DDE8), Color(0xFFE2EDF3)],
);

/// Mid-light teal for Edit Verb section headers (darker than [kFloTealGradientHorizontalLight]).
const LinearGradient kFloTealGradientHorizontalHeader = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF6F9CB4), Color(0xFF8FB4C8)],
);

/// Light teal fill for idle category rows in Keyboard Fire.
const LinearGradient kFloCategoryRowGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFDCEBF2), Color(0xFFF0F7FA)],
);

const LinearGradient kFloTealGradientVertical = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kFloTealLight, kFloTealDark],
);

/// Admin-only control chrome (gold).
const Color kFloAdminGoldLight = Color(0xFFF5E08A);
const Color kFloAdminGoldDark = Color(0xFFB8922A);
const Color kFloAdminGoldText = Color(0xFF3D3208);

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

/// Solid or gradient decoration for a selected toggle chip / inning cell.
BoxDecoration floTealSelectedDecoration({
  BorderRadius? borderRadius,
  bool gradient = true,
}) {
  return BoxDecoration(
    gradient: gradient ? kFloTealGradientHorizontal : null,
    color: gradient ? null : kFloTealMid,
    borderRadius: borderRadius ?? BorderRadius.circular(kFloInningButtonRadius),
    border: Border.all(color: kFloTealDark, width: 0.7),
  );
}

/// Light selected row/chip (player grid, verb list).
BoxDecoration floTealSelectedChipDecoration({BorderRadius? borderRadius}) {
  return BoxDecoration(
    color: kFloTealSelectedFill,
    borderRadius: borderRadius ?? BorderRadius.circular(3),
    border: Border.all(color: kFloTealLight, width: 1.5),
  );
}

/// Horizontal progress fill: white track with teal gradient growing left → right.
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
