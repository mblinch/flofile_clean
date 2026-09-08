import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';

/// Global search accelerator (⌘K). Columns keep working when closed.
class CaptionV2SearchBar extends StatelessWidget {
  const CaptionV2SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.textController,
  });

  final CaptionV2Controller controller;
  final FocusNode focusNode;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final hits = controller.topSearchHits();
    final players = hits.where((h) => h.kind == 'player').length;
    final verbs = hits.where((h) => h.kind == 'verb').length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: focusNode.hasFocus ? t.accent : t.divider,
          width: focusNode.hasFocus ? FfTokens.focusOutlineWidth : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: t.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              focusNode: focusNode,
              controller: textController,
              style: t.bodyStyle,
              cursorColor: t.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: controller.guidedSearchPrompt ??
                    'Try “27 home run” or search everything at once',
                hintStyle: t.secondaryLabelStyle,
                isDense: true,
              ),
              onChanged: controller.setSearchQuery,
              onSubmitted: (value) {
                final handled = controller.submitSearchCommand(value);
                if (handled) {
                  textController.clear();
                  controller.setSearchQuery('');
                  if (!controller.searchGuided) {
                    controller.setSearchOpen(false);
                  }
                  return;
                }
                if (hits.isNotEmpty) {
                  hits.first.apply();
                  controller.setSearchOpen(false);
                  textController.clear();
                }
              },
            ),
          ),
          if (controller.searchGuided)
            Text('Answer or choose below', style: t.metaStyle)
          else if (controller.searchQuery.isNotEmpty)
            Text(
              '$players players · $verbs verbs',
              style: t.metaStyle,
            ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: t.badgeFill,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('⌘K', style: t.keyHintStyle),
          ),
        ],
      ),
    );
  }
}

/// Overlay list of numbered search hits (1–9).
class CaptionV2SearchResults extends StatelessWidget {
  const CaptionV2SearchResults({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final CaptionV2Controller controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final hits = controller.topSearchHits();
    if (!controller.searchOpen ||
        (!controller.searchGuided && controller.searchQuery.isEmpty)) {
      return const SizedBox.shrink();
    }
    if (hits.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          border: Border.all(color: t.divider),
        ),
        child: Text('No matches', style: t.secondaryLabelStyle),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.guidedSearchPrompt != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.selectedFill,
                border: Border(
                  bottom: BorderSide(color: t.divider),
                ),
              ),
              child: Text(
                controller.guidedSearchPrompt!,
                style: t.labelStyle.copyWith(color: t.text),
              ),
            ),
          for (var i = 0; i < hits.length; i++)
            InkWell(
              canRequestFocus: false,
              onTapDown: (_) {
                final hit = hits[i];
                final guided = controller.searchGuided;
                hit.apply();
                if (!guided) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onClose();
                  });
                }
              },
              onTap: () {},
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}', style: t.keyHintStyle),
                    ),
                    Text(
                      hits[i].kind.toUpperCase(),
                      style: t.microStyle,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(hits[i].label, style: t.bodyStyle),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
