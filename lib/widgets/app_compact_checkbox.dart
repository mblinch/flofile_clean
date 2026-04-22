import 'package:custom_checkbox_plus/custom_checkbox_plus.dart';
import 'package:flutter/material.dart';

/// Compact on/off control used app-wide (matches Keyboard Fire keyword toggles).
class AppCompactCheckbox extends StatelessWidget {
  const AppCompactCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.accentColor = const Color(0xFF0052CC),
    this.size = 12,
    this.iconSize = 8,
    this.minTapTargetSize = 18,
  });

  final bool value;
  /// When null, the control is non-interactive (dimmed), e.g. placeholders.
  final ValueChanged<bool>? onChanged;
  final Color accentColor;
  final double size;
  final double iconSize;
  final double minTapTargetSize;

  @override
  Widget build(BuildContext context) {
    return CustomCheckBox(
      value: value,
      onChanged: onChanged,
      size: size,
      iconSize: iconSize,
      minTapTargetSize: minTapTargetSize,
      borderRadius: 2,
      borderWidth: 1,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      borderColor: Colors.grey.shade400,
      activeBorderColor: accentColor,
      fillColor: Colors.white,
      activeFillColor: accentColor,
      iconColor: Colors.white,
    );
  }
}
