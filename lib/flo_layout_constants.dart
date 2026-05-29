import 'package:flutter/material.dart';

/// Pic preview top/bottom bars, caption (CAPTION) title row, thumbnail toolbar,
/// and Keyboard Fire caption strip header — keep heights aligned (compact strip).
const double kFloChromeHeaderHeight = 22.0;

/// Inning / period / quarter selector buttons, +/− page nav, MLB clock chip,
/// Prior/Post-Game toggles, and overtime expand buttons.
const double kFloInningButtonHeight = 22.0;

/// Border radius for inning / period / +/− buttons.
const double kFloInningButtonRadius = 5.0;

/// FloFile teal accent (MLB clock, selections, primary actions).
const Color kFloTealLight = Color(0xFF4A7A96);
const Color kFloTealDark = Color(0xFF2A4858);
const Color kFloTealMid = Color(0xFF3A5F78);

/// Light fill behind selected chips / player cells.
const Color kFloTealSelectedFill = Color(0xFFE4EEF2);

/// Submenu strip beside verb options (was blue-tinted).
const Color kFloTealSubmenuFill = Color(0xFFF0F5F7);

const LinearGradient kFloTealGradientHorizontal = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kFloTealLight, kFloTealDark],
);

const LinearGradient kFloTealGradientVertical = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kFloTealLight, kFloTealDark],
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
