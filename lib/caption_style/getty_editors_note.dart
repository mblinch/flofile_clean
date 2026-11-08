import 'package:flutter/material.dart';

import '../theme/ff_tokens.dart';

/// Optional Getty wire editors-note inserted after the opening date colon,
/// immediately before the caption body.
///
/// Example:
/// `SYDNEY, AUSTRALIA - NOVEMBER 08: (EDITORS NOTE: …) George Plusnin …`
enum GettyEditorsNote {
  blackAndWhite,
  tiltShift,
  fisheye,
  custom;

  /// Full parenthetical for a preset note.
  String get captionText {
    switch (this) {
      case GettyEditorsNote.blackAndWhite:
        return '(EDITORS NOTE: This image has been converted to black and white.)';
      case GettyEditorsNote.tiltShift:
        return '(EDITORS NOTE: This image was created using a tilt-shift lens.)';
      case GettyEditorsNote.fisheye:
        return '(EDITORS NOTE: This image was created using a fisheye lens.)';
      case GettyEditorsNote.custom:
        return '';
    }
  }

  /// Resolved caption insert, including [customBody] for [custom].
  String captionTextFor(String customBody) {
    if (this == GettyEditorsNote.custom) {
      return formatCustomCaption(customBody);
    }
    return captionText;
  }

  /// Compact label when a note is already selected on the period bar.
  String get chipLabel {
    switch (this) {
      case GettyEditorsNote.blackAndWhite:
        return 'B&W';
      case GettyEditorsNote.tiltShift:
        return 'Tilt-shift';
      case GettyEditorsNote.fisheye:
        return 'Fisheye';
      case GettyEditorsNote.custom:
        return 'Custom';
    }
  }

  /// Menu row label in the Add Editors Note dropdown.
  String get menuLabel {
    switch (this) {
      case GettyEditorsNote.blackAndWhite:
        return 'Black and White';
      case GettyEditorsNote.tiltShift:
        return 'Tilt-shift';
      case GettyEditorsNote.fisheye:
        return 'Fisheye';
      case GettyEditorsNote.custom:
        return 'Custom…';
    }
  }

  /// Wraps typed body text as `(EDITORS NOTE: ….)`.
  static String formatCustomCaption(String raw) {
    var body = raw.trim();
    if (body.isEmpty) return '';

    final lower = body.toLowerCase();
    if (lower.startsWith('(editors note:')) {
      if (!body.endsWith(')')) body = '$body)';
      return body;
    }
    if (lower.startsWith('editors note:')) {
      body = body.substring('editors note:'.length).trim();
    }
    if (body.isEmpty) return '';
    if (!body.endsWith('.')) body = '$body.';
    return '(EDITORS NOTE: $body)';
  }
}

/// Popup to enter a custom Getty editors note body (text after `EDITORS NOTE:`).
///
/// Returns:
/// - trimmed note text when Add/Update is pressed
/// - empty string when Clear is pressed
/// - null when Cancelled
Future<String?> showGettyCustomEditorsNoteDialog({
  required BuildContext context,
  String initialText = '',
}) {
  final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  final controller = TextEditingController(text: initialText);
  final hasExisting = initialText.trim().isNotEmpty;
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
          side: BorderSide(color: t.divider),
        ),
        title: Text('Editors Note', style: t.labelStyle.copyWith(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EDITORS NOTE',
                style: FfTokens.panelLabel(color: t.textSecondary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                style: t.bodyStyle,
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.of(dialogContext).pop(trimmed);
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: t.sunken,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    borderSide: BorderSide(color: t.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: Text(
              'Clear',
              style: TextStyle(color: t.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(dialogContext).pop(trimmed);
            },
            style: FilledButton.styleFrom(
              backgroundColor: FfTokens.gold,
              foregroundColor: FfTokens.inkOnGold,
            ),
            child: Text(hasExisting ? 'Update' : 'Add'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
