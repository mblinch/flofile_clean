import 'package:flutter/material.dart';

import '../../../caption_style/verb_sub_options.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/full_verb_edit_dialog.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';

/// Opens the shared verb editor dialog for Caption V2.
Future<void> showCaptionV2VerbEditor(
  BuildContext context,
  CaptionV2Controller controller,
  String initialVerb, {
  bool createOnOpen = false,
}) async {
  final categories = controller.verbCategories
      .where((category) => category != 'Favorites')
      .toList();
  if (categories.isEmpty) return;
  final definitions = controller.verbDefinitionsByCategory;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => AppDialogFfStyle(
      enabled: true,
      child: FullVerbEditDialog(
        initialVerb: initialVerb,
        createOnOpen: createOnOpen,
        useFfTokens: true,
        sport: controller.sport,
        categories: categories,
        verbsByCategory: {
          for (final category in categories)
            category: (definitions[category] ?? const <EffectiveVerb>[])
                .map((verb) => verb.key)
                .toList(),
        },
        favoriteVerbs: Set<String>.from(controller.verbCatalog.favoriteKeys),
        loadInitialData: controller.verbEditorInitialData,
        hasSavedDefault: (_) => false,
        isAdmin: false,
        homeTeamName: controller.homeTeam,
        awayTeamName: controller.awayTeam,
        homePlayer1Name: controller.homeRoster.isEmpty
            ? null
            : controller.homeRoster.first.fullName,
        homePlayer1Jersey: controller.homeRoster.isEmpty
            ? null
            : controller.homeRoster.first.jerseyNumber,
        awaySampleName: controller.awayRoster.isEmpty
            ? null
            : controller.awayRoster.first.fullName,
        awaySampleJersey: controller.awayRoster.isEmpty
            ? null
            : controller.awayRoster.first.jerseyNumber,
        isCustomVerb: (verb) =>
            controller.verbDefinition(verb)?.isCustom == true,
        onFavoriteChanged: (verb, _) => controller.toggleVerbFavorite(verb),
        onCategoryOrderChanged: controller.saveCategoryOrder,
        onVerbOrderChanged: controller.saveVerbOrder,
        onReset: controller.resetBuiltInVerb,
        onCreateCustomVerb: ({
          required String label,
          required String singular,
          required String pluralText,
          required String ingText,
          required bool usePluralPhrase,
          required List<String> keywords,
          required bool wantsOpponent,
          required String selectedCategory,
          required VerbSubOptions subOptions,
        }) =>
            controller.createCustomVerb(
          label: label,
          singular: singular,
          pluralText: pluralText,
          ingText: ingText,
          usePluralPhrase: usePluralPhrase,
          keywords: keywords,
          wantsOpponent: wantsOpponent,
          category: selectedCategory,
          subOptions: subOptions,
        ),
        onUpdateCustomVerb: ({
          required String previousLabel,
          required String label,
          required String singular,
          required String pluralText,
          required String ingText,
          required bool usePluralPhrase,
          required List<String> keywords,
          required bool wantsOpponent,
          required String selectedCategory,
          required VerbSubOptions subOptions,
        }) =>
            controller.updateCustomVerb(
          previousLabel: previousLabel,
          label: label,
          singular: singular,
          pluralText: pluralText,
          ingText: ingText,
          usePluralPhrase: usePluralPhrase,
          keywords: keywords,
          wantsOpponent: wantsOpponent,
          category: selectedCategory,
          subOptions: subOptions,
        ),
        onSave: ({
          required String overrideKey,
          required String newLabel,
          required String newSingular,
          required String pluralText,
          required String ingText,
          required bool usePluralPhrase,
          required List<String> keywords,
          required bool wantsOpponent,
          required String selectedCategory,
          required VerbSubOptions subOptions,
          required bool asDefault,
          required bool asAppDefault,
        }) =>
            controller.saveBuiltInVerb(
          key: overrideKey,
          label: newLabel,
          singular: newSingular,
          pluralText: pluralText,
          ingText: ingText,
          usePluralPhrase: usePluralPhrase,
          keywords: keywords,
          wantsOpponent: wantsOpponent,
          category: selectedCategory,
          subOptions: subOptions,
          asDefault: asDefault,
        ),
      ),
    ),
  );
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
