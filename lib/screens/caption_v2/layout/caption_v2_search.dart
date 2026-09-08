import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';

/// Global search accelerator (⌘K). Columns keep working when closed.
class CaptionV2SearchBar extends StatefulWidget {
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
  State<CaptionV2SearchBar> createState() => _CaptionV2SearchBarState();
}

class _CaptionV2SearchBarState extends State<CaptionV2SearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_clearTextWhenSearchCloses);
  }

  @override
  void didUpdateWidget(covariant CaptionV2SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_clearTextWhenSearchCloses);
      widget.controller.addListener(_clearTextWhenSearchCloses);
    }
  }

  void _clearTextWhenSearchCloses() {
    if (widget.controller.searchQuery.isEmpty &&
        widget.textController.text.isNotEmpty) {
      widget.textController.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_clearTextWhenSearchCloses);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
          color: widget.focusNode.hasFocus ? t.accent : t.divider,
          width: widget.focusNode.hasFocus ? FfTokens.focusOutlineWidth : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department,
            size: 17,
            color: Color(0xFFFF7A24),
          ),
          const SizedBox(width: 5),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFFB347), Color(0xFFFF5A1F)],
            ).createShader(bounds),
            child: Text(
              'FIREBAR',
              style: FfTokens.captionTitle.copyWith(
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: t.badgeFill,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '⌘K',
              style: t.keyHintStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: t.divider),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              focusNode: widget.focusNode,
              controller: widget.textController,
              style: t.bodyStyle,
              cursorColor: t.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: controller.guidedSearchPrompt,
                hintStyle: t.secondaryLabelStyle,
                isDense: true,
              ),
              onChanged: controller.setSearchQuery,
              onSubmitted: (value) {
                final finalAction =
                    controller.guidedSearchPrompt == 'Save or FTP?';
                final submittedValue = finalAction && value.trim().isEmpty
                    ? (HardwareKeyboard.instance.isShiftPressed
                        ? 'ftp'
                        : 'save')
                    : value;
                final handled = controller.submitSearchCommand(submittedValue);
                if (handled) {
                  widget.textController.clear();
                  controller.setSearchQuery('');
                  if (!controller.searchGuided) {
                    controller.setSearchOpen(false);
                  }
                  return;
                }
                if (hits.isNotEmpty) {
                  hits.first.apply();
                  controller.setSearchOpen(false);
                  widget.textController.clear();
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
          Tooltip(
            message: 'Type a jersey number and verb, for example: 27 home run',
            child: Icon(
              Icons.help_outline,
              size: 15,
              color: t.textSecondary,
            ),
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
                final keepOpenForVerb = !guided &&
                    hit.kind == 'player' &&
                    controller.searchHasJerseyAndVerb;
                hit.apply();
                if (!keepOpenForVerb && !controller.searchGuided) {
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
