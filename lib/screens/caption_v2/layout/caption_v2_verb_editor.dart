import 'package:flutter/material.dart';

import '../../../widgets/ff_menu.dart';
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
      onVerbCatalogChanged: (sport, bundle) {
        if (sport == controller.sport) {
          controller.showVerbBundle(bundle);
        }
      },
      onVerbCatalogPersisted: (sport) async {
        if (sport == controller.sport) {
          await controller.commitVerbBundleFromDisk();
        }
      },
    ),
  );
  await controller.reloadVerbCatalog();
}

/// Right-click menu, using the caption workspace colors.
Future<T?> showCaptionV2PopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  double width = 240,
}) {
  final choices = <FfMenuChoice<T>>[
    for (final item in items)
      if (item is PopupMenuDivider)
        FfMenuChoice<T>.divider()
      else if (item is PopupMenuItem<T>)
        FfMenuChoice<T>(
          value: item.value,
          enabled: item.enabled,
          child: item.child ?? const SizedBox.shrink(),
        ),
  ];
  return showFfMenu<T>(
    context: context,
    anchorGlobal: Rect.fromLTWH(position.left, position.top, 0, 0),
    width: width,
    choices: choices,
  ).then((result) => result == null ? null : result.value);
}
