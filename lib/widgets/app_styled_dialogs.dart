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


/// App-wide right-click context menu style used across panels.
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
    color: color ?? Colors.grey.shade50,
    elevation: elevation ?? 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: Colors.grey.shade300),
    ),
  );
}
