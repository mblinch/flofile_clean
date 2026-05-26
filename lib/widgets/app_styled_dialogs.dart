import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Matches [KeyboardFirePanel] FTP / burst primary actions (`keyboard_fire_dialog.dart`).
const Color kAppDialogPrimaryBlue = Color(0xFF0052CC);

/// Square, white dialogs consistent with burst caption UI
/// (`burst_caption_confirm_dialog.dart`) — not default M3 rounded/surface tint.
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'OK',
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final screenW = MediaQuery.sizeOf(ctx).width;
      // Burst dialog uses `math.min(880.0, screenW * 0.92)`; confirm is half that.
      final burstDialogW = math.min(880.0, screenW * 0.92);
      final dialogW = burstDialogW / 2;
      return Center(
        child: SizedBox(
          width: dialogW,
          child: AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.35,
              ),
            ),
            content: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actionsOverflowAlignment: OverflowBarAlignment.end,
            actions: [
              ElevatedGreyButton(
                label: cancelLabel,
                fontSize: 11,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(width: 8),
              ElevatedGreyButton(
                label: confirmLabel,
                fontSize: 11,
                isPrimary: true,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      );
    },
  );
}


/// App-wide right-click context menu (square corners, white surface — matches
/// [showAppConfirmDialog] and Keyboard Fire menus).
Future<T?> showAppContextMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  Color? color,
  double? elevation,
}) {
  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    color: color ?? Colors.white,
    elevation: elevation ?? 0,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black.withValues(alpha: 0.12),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: Color(0xFFD0D0D0)),
    ),
  );
}

/// Grey bordered action used on startup (Pick folder, Metadata Preset, etc.).
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: enabled ? Colors.grey.shade100 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (!enabled || onTap == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

/// Elevated grey button with hover lift, press feedback, and optional danger state.
class ElevatedGreyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDanger;
  final bool fullWidth;
  final double fontSize;
  final IconData? icon;

  const ElevatedGreyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isDanger = false,
    this.fullWidth = false,
    this.fontSize = 13,
    this.icon,
  });

  @override
  State<ElevatedGreyButton> createState() => _ElevatedGreyButtonState();
}

class _ElevatedGreyButtonState extends State<ElevatedGreyButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final danger = widget.isDanger && _hovered && enabled;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.fullWidth ? double.infinity : null,
          transform: Matrix4.translationValues(
              0, enabled && !_pressed && _hovered ? -1 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !enabled
                  ? const Color(0x1A000000)
                  : danger
                      ? const Color(0x33C0392B)
                      : const Color(0x2E000000),
              width: 0.5,
            ),
            gradient: !enabled
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _pressed
                        ? [const Color(0xFFE0E0E0), const Color(0xFFF0F0F0)]
                        : danger
                            ? [const Color(0xFFFFF5F5), const Color(0xFFFFE8E8)]
                            : _hovered
                                ? [const Color(0xFFFFFFFF), const Color(0xFFFAFAFA)]
                                : [const Color(0xFFFFFFFF), const Color(0xFFFAFAFA)],
                  ),
            color: !enabled ? const Color(0xFFF0F0F0) : null,
            boxShadow: !enabled
                ? null
                : _pressed
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 1.5,
                          offset: const Offset(0, 0.75),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _hovered ? 0.18 : 0.13),
                          blurRadius: _hovered ? 4.5 : 2.5,
                          offset: Offset(0, _hovered ? 1.5 : 1.25),
                        ),
                      ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isPrimary ? 10 : 8,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize, color: !enabled
                    ? const Color(0xFFAAAAAA)
                    : danger ? const Color(0xFFC0392B) : const Color(0xFF555555)),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: widget.fontSize,
                    fontVariations: const [FontVariation('wght', 500)],
                    letterSpacing: -0.5,
                    color: !enabled
                        ? const Color(0xFFAAAAAA)
                        : danger
                            ? const Color(0xFFC0392B)
                            : const Color(0xFF555555),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact [PopupMenuItem] rows for [showAppContextMenu].
class AppPopupMenu {
  AppPopupMenu._();

  static PopupMenuItem<T> tile<T>({
    required T value,
    required String label,
    IconData? icon,
    bool destructive = false,
    double height = 34,
  }) {
    final Color c =
        destructive ? const Color(0xFFC62828) : Colors.black87;
    return PopupMenuItem<T>(
      value: value,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: c,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
