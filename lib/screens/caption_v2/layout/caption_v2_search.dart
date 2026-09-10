import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';

/// Inline Firebar. The three workspace columns are its result list.
class CaptionV2SearchBar extends StatefulWidget {
  const CaptionV2SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.textController,
    required this.onActivate,
    required this.onExit,
  });

  final CaptionV2Controller controller;
  final FocusNode focusNode;
  final TextEditingController textController;
  final VoidCallback onActivate;
  final VoidCallback onExit;

  @override
  State<CaptionV2SearchBar> createState() => _CaptionV2SearchBarState();
}

class _CaptionV2SearchBarState extends State<CaptionV2SearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncText);
  }

  @override
  void didUpdateWidget(covariant CaptionV2SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncText);
      widget.controller.addListener(_syncText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncText);
    super.dispose();
  }

  void _syncText() {
    if (widget.controller.searchQuery.isEmpty &&
        widget.textController.text.isNotEmpty) {
      widget.textController.clear();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.searchOpen || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.moveFirebarSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.moveFirebarSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      controller.commitSelectedFirebarResult();
      widget.textController.clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.textController.text.isEmpty) {
      controller.removeLastFirebarChip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final active = controller.searchOpen;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!active) widget.onActivate();
        widget.focusNode.requestFocus();
      },
      child: Container(
        height: active ? 80 : 38,
        padding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          size: 17,
                          color: FfTokens.firebar,
                        ),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 58,
                          child: Text(
                            'Firebar',
                            maxLines: 1,
                            softWrap: false,
                            style: FfTokens.captionTitle.copyWith(
                              fontSize: 16,
                              letterSpacing: 0.5,
                              height: 1,
                              foreground: Paint()
                                ..shader = const LinearGradient(
                                  colors: [
                                    Color(0xFFFFB347),
                                    Color(0xFFFF5A1F),
                                  ],
                                ).createShader(
                                  const Rect.fromLTWH(0, 0, 70, 20),
                                ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 40,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tokens.badgeFill,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '⌘K',
                            style: tokens.keyHintStyle.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 18, color: tokens.divider),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleKey,
                      child: TextField(
                        key: const ValueKey('firebar-input'),
                        enabled: active,
                        focusNode: widget.focusNode,
                        controller: widget.textController,
                        maxLines: 1,
                        style: tokens.metaStyle.copyWith(
                          color: tokens.text,
                          fontSize: 13,
                        ),
                        cursorColor: FfTokens.firebar,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          hintText: controller.firebarOptionPrompt ??
                              'Type a name, jersey number, or verb',
                          hintStyle: tokens.metaStyle.copyWith(
                            color: tokens.text.withValues(alpha: 0.38),
                            fontSize: 13,
                          ),
                        ),
                        onChanged: controller.setSearchQuery,
                        onSubmitted: (_) {
                          controller.commitSelectedFirebarResult();
                          widget.textController.clear();
                        },
                      ),
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 8),
                    Text(
                      '↑↓ move   ⏎ insert   esc exit',
                      style: tokens.metaStyle.copyWith(
                        color: tokens.text.withValues(alpha: 0.42),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (active) ...[
              Divider(height: 1, color: tokens.divider),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final chip in controller.firebarCommitted) ...[
                            _FirebarChip(
                              result: chip,
                              controller: controller,
                              tokens: tokens,
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (controller.firebarOptions.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(
                              controller.firebarOptionPrompt ?? 'Choose:',
                              style: tokens.metaStyle.copyWith(
                                color: tokens.text,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 7),
                            for (var index = 0;
                                index <
                                    controller.filteredFirebarOptions.length;
                                index++) ...[
                              _FirebarOptionButton(
                                option:
                                    controller.filteredFirebarOptions[index],
                                selected:
                                    index == controller.firebarOptionIndex,
                                controller: controller,
                                tokens: tokens,
                              ),
                              const SizedBox(width: 5),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FirebarChip extends StatelessWidget {
  const _FirebarChip({
    required this.result,
    required this.controller,
    required this.tokens,
  });

  final FirebarResult result;
  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final player = result.player;
    var label = result.kind == FirebarResultKind.player
        ? player!.fullName
        : controller.verbDefinition(result.verbKey!)?.label ?? result.verbKey!;
    if (result.kind == FirebarResultKind.verb &&
        result.verbKey == controller.selectedVerb) {
      if (result.verbKey == 'Home Run' && controller.rbi > 0) {
        label =
            '$label · ${controller.rbi}R';
      } else if (controller.verbNeedsRbi(result.verbKey!) &&
          controller.rbi > 0) {
        label = '$label · RBI ${controller.rbi}';
      } else if (controller.verbNeedsBase(result.verbKey!) &&
          (controller.selectedBase?.trim().isNotEmpty ?? false)) {
        label = '$label · ${controller.selectedBase}';
      }
      if (controller.celebrationType != null) {
        label = '$label · ${controller.celebrationType}';
      }
    }
    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(4, 3, 5, 3),
      decoration: BoxDecoration(
        color: FfTokens.firebar.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: FfTokens.firebar.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player != null) ...[
            Container(
              constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: FfTokens.firebar.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                player.jerseyNumber ?? '—',
                style: tokens.jerseyStyle.copyWith(
                  color: tokens.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            style: tokens.metaStyle.copyWith(
              color: tokens.text,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            canRequestFocus: false,
            onTap: () => controller.removeFirebarChip(result),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                '×',
                style: tokens.metaStyle.copyWith(
                  color: tokens.text.withValues(alpha: 0.50),
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebarOptionButton extends StatelessWidget {
  const _FirebarOptionButton({
    required this.option,
    required this.selected,
    required this.controller,
    required this.tokens,
  });

  final FirebarOption option;
  final bool selected;
  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      canRequestFocus: false,
      onTap: () => controller.chooseFirebarOption(option),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? FfTokens.firebar.withValues(alpha: 0.16)
              : tokens.badgeFill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? FfTokens.firebar.withValues(alpha: 0.42)
                : tokens.divider,
          ),
        ),
        child: Text(
          option.label,
          style: tokens.metaStyle.copyWith(
            color: selected ? FfTokens.firebar : tokens.text,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
