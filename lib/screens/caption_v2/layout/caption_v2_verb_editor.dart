import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/preferences_dialog.dart';
import '../data/caption_v2_controller.dart';

/// Opens Preferences on the Verbs tab for personal verb customization.
///
/// Same editor as Preferences → Verbs. Saves go to PreferencesService and sync
/// to the signed-in user's Firebase prefs — never app-default originals.
Future<void> showCaptionV2VerbEditor(
  BuildContext context,
  CaptionV2Controller controller,
  String initialVerb, {
  bool createOnOpen = false,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => PreferencesDialog(
      openVerbs: true,
      initialVerbKey: initialVerb,
      createVerbOnOpen: createOnOpen,
      onVerbCatalogChanged: (sport) async {
        if (sport == controller.sport) {
          await controller.reloadVerbCatalog();
        }
      },
    ),
  );
  await controller.reloadVerbCatalog();
}

/// V2-themed popup menu used for verb right-clicks.
Future<T?> showCaptionV2PopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return showMenu<T>(
    context: context,
    position: position,
    color: tokens.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusRow),
      side: BorderSide(color: tokens.divider),
    ),
    items: [
      for (final item in items)
        if (item is PopupMenuItem<T>)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            height: item.height,
            padding: item.padding,
            child: DefaultTextStyle(
              style: tokens.metaStyle.copyWith(
                color: item.enabled ? tokens.text : tokens.textSecondary,
                fontSize: 13,
              ),
              child: item.child!,
            ),
          )
        else
          item,
    ],
  );
}
