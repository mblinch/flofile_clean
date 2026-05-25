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
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(cancelLabel, style: const TextStyle(fontSize: 11)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kAppDialogPrimaryBlue,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.grey.shade400,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel, style: const TextStyle(fontSize: 11)),
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
