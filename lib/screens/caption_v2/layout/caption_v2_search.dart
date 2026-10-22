import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import 'caption_v2_firebar_menu.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Inline Firebar. The three workspace columns are its result list.
class CaptionV2SearchBar extends StatefulWidget {
  const CaptionV2SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.textController,
    required this.onActivate,
    required this.onExit,
    this.onSave,
    this.onTransmit,
  });

  final CaptionV2Controller controller;
  final FocusNode focusNode;
  final TextEditingController textController;
  final VoidCallback onActivate;
  final VoidCallback onExit;
  final VoidCallback? onSave;
  final VoidCallback? onTransmit;

  @override
  State<CaptionV2SearchBar> createState() => _CaptionV2SearchBarState();
}

class _CaptionV2SearchBarState extends State<CaptionV2SearchBar> {
  final GlobalKey _selectedChipKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();
  final LayerLink _menuLink = LayerLink();
  final OverlayPortalController _menuPortal = OverlayPortalController();
  final ScrollController _menuScroll = ScrollController();
  String? _scrolledSelection;
  int? _scrolledMenuIndex;
  Offset? _menuPointer;
  String? _completionQuery;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncText);
    widget.focusNode.addListener(_syncMenu);
    widget.controller.addListener(_syncMenu);
  }

  @override
  void didUpdateWidget(covariant CaptionV2SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncText);
      oldWidget.controller.removeListener(_syncMenu);
      widget.controller.addListener(_syncText);
      widget.controller.addListener(_syncMenu);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncMenu);
      widget.focusNode.addListener(_syncMenu);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncText);
    widget.controller.removeListener(_syncMenu);
    widget.focusNode.removeListener(_syncMenu);
    _menuScroll.dispose();
    super.dispose();
  }

  void _syncMenu() {
    final controller = widget.controller;
    final query = controller.searchQuery;
    if (_completionQuery != query) {
      _completionQuery = query;
      final verb = controller.firebarWordCompletionResult;
      if (verb != null && verb.kind == FirebarResultKind.verb) {
        final index = controller.firebarMenuResults
            .indexWhere((result) => result.key == verb.key);
        if (index >= 0 && index != controller.firebarMenuIndex) {
          controller.hoverFirebarMenu(index);
        }
      }
      if (mounted) setState(() {});
    }
    final show = widget.focusNode.hasFocus && controller.firebarMenuOpen;
    if (show && !_menuPortal.isShowing) {
      _menuPortal.show();
    } else if (!show && _menuPortal.isShowing) {
      _menuPortal.hide();
    }
    if (show) _revealMenuRow();
  }

  void _revealMenuRow() {
    final index = widget.controller.firebarMenuIndex;
    if (index == _scrolledMenuIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_menuScroll.hasClients) return;
      if (index == _scrolledMenuIndex) return;
      _scrolledMenuIndex = index;
      final position = _menuScroll.position;
      const row = 28.0;
      const header = 22.0;
      final top = header + index * (row + 2);
      final bottom = top + row;
      final viewTop = position.pixels + 30;
      final viewBottom = position.pixels + position.viewportDimension - 44;
      if (top < viewTop) {
        position.jumpTo((top - 30).clamp(0.0, position.maxScrollExtent));
      } else if (bottom > viewBottom) {
        position.jumpTo(
          (bottom - position.viewportDimension + 44)
              .clamp(0.0, position.maxScrollExtent),
        );
      }
    });
  }

  bool _tapInsideMenu(Offset global) {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return false;
    final local = box.globalToLocal(global);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  void _syncText() {
    final query = widget.controller.searchQuery;
    if (widget.textController.text == query) return;
    widget.textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.searchOpen || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final queryEmpty = widget.textController.text.isEmpty;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      // The hardware handler already steps the number menu. Handling it
      // here too skipped a row on every press.
      if (controller.firebarMenuOpen) return KeyEventResult.handled;
      controller.moveFirebarSelection(
        event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1,
      );
      return KeyEventResult.handled;
    }
    if (queryEmpty && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      controller.moveFirebarChipCursor(-1);
      return KeyEventResult.handled;
    }
    if (queryEmpty && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      controller.moveFirebarChipCursor(1);
      return KeyEventResult.handled;
    }
    if (controller.firebarJerseySideChoiceOpen &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyH) {
        controller.chooseFirebarJerseySide(isHome: true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        controller.chooseFirebarJerseySide(isHome: false);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Shift+Enter / ⌘Enter / ⌘⇧Enter are handled globally as FTP (and may
      // commit the highlighted player first). Don't also insert here.
      final keys = HardwareKeyboard.instance;
      if (keys.isShiftPressed || keys.isMetaPressed || keys.isControlPressed) {
        return KeyEventResult.ignored;
      }
      if (controller.firebarMenuOpen) {
        controller.commitFirebarMenu();
      } else {
        controller.commitSelectedFirebarResult();
      }
      widget.textController.clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.textController.text.isEmpty) {
      controller.backspaceFirebarChip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final active = controller.searchOpen;
    final searching = active &&
        controller.searchQuery.trim().isNotEmpty &&
        controller.firebarOptions.isEmpty;
    final typingVerbs = searching &&
        (controller.firebarVerbResults.isNotEmpty ||
            controller.firebarCustomVerbOffer != null);
    final committedKeys =
        controller.firebarCommitted.map((chip) => chip.key).toSet();
    final suggestions = searching
        ? controller.firebarOrderedResults
            .where((result) => !committedKeys.contains(result.key))
            .toList(growable: false)
        : const <FirebarResult>[];
    final selectedKey = controller.firebarSelectedResult?.key;
    if (selectedKey != null &&
        selectedKey != _scrolledSelection &&
        (committedKeys.contains(selectedKey) ||
            suggestions.any((result) => result.key == selectedKey))) {
      _scrolledSelection = selectedKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chipContext = _selectedChipKey.currentContext;
        if (chipContext == null || !chipContext.mounted) return;
        Scrollable.ensureVisible(
          chipContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    }

    final showMenu =
        widget.focusNode.hasFocus && controller.firebarMenuOpen;
    if (showMenu != _menuPortal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final still = widget.focusNode.hasFocus &&
            widget.controller.firebarMenuOpen;
        if (still && !_menuPortal.isShowing) {
          _menuPortal.show();
        } else if (!still && _menuPortal.isShowing) {
          _menuPortal.hide();
        }
      });
    }

    return OverlayPortal(
      controller: _menuPortal,
      overlayChildBuilder: (context) {
        // Read matches from the controller here so the overlay stays in sync
        // even when the portal was opened before a later query rebuild.
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final menuResults = controller.firebarMenuResults;
            final menuIndex = menuResults.isEmpty
                ? 0
                : controller.firebarMenuIndex
                    .clamp(0, menuResults.length - 1);
            return CompositedTransformFollower(
              link: _menuLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: FirebarAutocompleteMenu(
                key: _menuKey,
                controller: controller,
                tokens: tokens,
                results: menuResults,
                selectedIndex: menuIndex,
                scrollController: _menuScroll,
                onHover: (index, position) {
                  if (_menuPointer == position) return;
                  _menuPointer = position;
                  controller.hoverFirebarMenu(index);
                },
                onCommit: (index) {
                  controller.hoverFirebarMenu(index);
                  controller.commitFirebarMenu();
                  widget.textController.clear();
                  widget.focusNode.requestFocus();
                },
              ),
            );
          },
        );
      },
      child: CompositedTransformTarget(
        link: _menuLink,
        child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!active) widget.onActivate();
        widget.focusNode.requestFocus();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: FfTokens.firebar.withValues(alpha: 0.35),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortcutWidth = _shortcutClusterWidth(controller);
            final compactIndexes = _compactPlayerIndexes(
              maxWidth: (constraints.maxWidth - shortcutWidth)
                  .clamp(0.0, double.infinity),
              controller: controller,
              tokens: tokens,
              typed: widget.textController.text,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(PhosphorIconsRegular.flame,
                  size: 15,
                  color: FfTokens.firebar,
                ),
                const SizedBox(width: 5),
                Text(
                  'Firebar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    height: 1,
                    color: FfTokens.firebar,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tokens.divider),
                  ),
                  child: Text(
                    '⌘K',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                      height: 1,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: tokens.divider),
              ],
            ),
            _FirebarTypingField(
              active: active,
              focusNode: widget.focusNode,
              textController: widget.textController,
              tokens: tokens,
              onKey: _handleKey,
              onChanged: controller.setSearchQuery,
              onTapOutside: (event) {
                if (_tapInsideMenu(event.position)) {
                  widget.focusNode.requestFocus();
                  return;
                }
                widget.focusNode.unfocus();
              },
              onSubmitted: () {
                if (controller.firebarMenuOpen) {
                  controller.commitFirebarMenu();
                } else {
                  controller.commitSelectedFirebarResult();
                }
                widget.textController.clear();
              },
            ),
            for (var index = 0;
                index < controller.firebarCommitted.length;
                index++)
              _FirebarChip(
                key: index == controller.firebarChipCursor
                    ? _selectedChipKey
                    : null,
                result: controller.firebarCommitted[index],
                controller: controller,
                tokens: tokens,
                compact: compactIndexes.contains(index),
                subdued: _pinnedVerbIsPaused(
                  controller,
                  controller.firebarCommitted[index],
                  typingVerbs,
                ),
                selected: index == controller.firebarChipCursor,
                onSelect: typingVerbs &&
                        controller.firebarCommitted[index].kind ==
                            FirebarResultKind.verb
                    ? () => controller.commitFirebarResultAndClose(
                          controller.firebarCommitted[index],
                        )
                    : null,
              ),
            if (controller.firebarOptions.isNotEmpty) ...[
              Text(
                controller.firebarOptionPrompt ?? 'Choose:',
                style: tokens.metaStyle.copyWith(
                  color: tokens.text,
                  fontSize: 12,
                ),
              ),
              for (var index = 0;
                  index < controller.filteredFirebarOptions.length;
                  index++)
                _FirebarOptionButton(
                  option: controller.filteredFirebarOptions[index],
                  selected: index == controller.firebarOptionIndex,
                  controller: controller,
                  tokens: tokens,
                ),
            ],
          ],
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 1, height: 18, color: tokens.divider),
                      const SizedBox(width: 6),
                      _FirebarShortcutHint(
                        keys: '⌘S',
                        action: 'save',
                        tokens: tokens,
                        onTap: widget.onSave,
                      ),
                      if (controller.ftpModeEnabled) ...[
                        const SizedBox(width: 4),
                        _FirebarShortcutHint(
                          keys: '⌘↵',
                          action: 'ftp',
                          tokens: tokens,
                          onTap: widget.onTransmit,
                        ),
                      ],
                      const SizedBox(width: 4),
                      _FirebarShortcutHint(
                        keys: 'esc',
                        action: 'exit',
                        tokens: tokens,
                        onTap: widget.onExit,
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
        ),
      ),
    );
  }
}

class _FirebarTypingField extends StatelessWidget {
  const _FirebarTypingField({
    required this.active,
    required this.focusNode,
    required this.textController,
    required this.tokens,
    required this.onKey,
    required this.onChanged,
    required this.onSubmitted,
    this.onTapOutside,
  });

  final bool active;
  final FocusNode focusNode;
  final TextEditingController textController;
  final FfTokens tokens;
  final FocusOnKeyEventCallback onKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final TapRegionCallback? onTapOutside;

  @override
  Widget build(BuildContext context) {
    final style = tokens.metaStyle.copyWith(
      color: tokens.text,
      fontSize: 12,
    );
    final typed = textController.text;
    final field = Focus(
      onKeyEvent: onKey,
      child: TextField(
        key: const ValueKey('firebar-input'),
        enabled: active,
        focusNode: focusNode,
        controller: textController,
        maxLines: 1,
        style: style,
        cursorColor: FfTokens.firebar,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        onTapOutside: onTapOutside,
      ),
    );
    // Always the same Stack. Dropping it when the ending appears or
    // disappears was disposing the field mid-Backspace, and macOS beeped.
    // The orange ending is painted above the field so the field cannot cover it.
    final ghost = Stack(
      alignment: Alignment.centerLeft,
      children: [
        field,
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(
                    text: typed.isEmpty ? ' ' : typed,
                    style: const TextStyle(color: Colors.transparent),
                  ),
                  const TextSpan(text: ''),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
        ),
      ],
    );
    // Keep this field in a SizedBox. Swapping that box for Expanded or Flexible
    // disposed the field mid-keystroke, and macOS beeped.
    // Only the letters the user typed. The rest of a match waits for Enter.
    final visible = typed;
    final painter = TextPainter(
      text: TextSpan(
        text: visible.isEmpty ? ' ' : visible,
        style: tokens.metaStyle.copyWith(fontSize: 12),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    // Always a small slot. It grows with the letters the user typed,
    // which pushes chips and shortcuts along the line.
    final tightWidth = visible.isEmpty ? 18.0 : painter.width + 10;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final width = maxWidth.isFinite && tightWidth > maxWidth
            ? maxWidth
            : tightWidth;
        return SizedBox(
          width: width,
          height: 28,
          child: ghost,
        );
      },
    );
  }
}

class _FirebarChip extends StatelessWidget {
  const _FirebarChip({
    super.key,
    required this.result,
    required this.controller,
    required this.tokens,
    this.compact = false,
    this.subdued = false,
    this.selected = false,
    this.onSelect,
  });

  final FirebarResult result;
  final CaptionV2Controller controller;
  final FfTokens tokens;
  final bool compact;
  final bool subdued;
  final bool selected;
  final VoidCallback? onSelect;

  static String labelFor(
    FirebarResult result,
    CaptionV2Controller controller, {
    required bool compact,
  }) {
    final player = result.player;
    if (result.kind == FirebarResultKind.player && player != null) {
      return compact
          ? _compactPlayerLabel(player.fullName, player.jerseyNumber)
          : player.fullName;
    }
    var label =
        controller.verbDefinition(result.verbKey!)?.label ?? result.verbKey!;
    if (result.kind == FirebarResultKind.verb &&
        result.verbKey == controller.selectedVerb) {
      if (result.verbKey == 'Home Run' && controller.rbi > 0) {
        label = '$label · ${controller.rbi}R';
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
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final player = result.player;
    final label = labelFor(result, controller, compact: compact);
    final showJersey = player != null && !compact;
    final isVerb = result.kind == FirebarResultKind.verb;
    final fill = subdued
        ? tokens.badgeFill.withValues(alpha: 0.55)
        : isVerb
            ? const Color(0xFF322820)
            : FfTokens.nocturneEl;
    final border = subdued
        ? tokens.divider
        : selected
            ? FfTokens.firebar
            : isVerb
                ? const Color(0xFFC4A574).withValues(alpha: 0.7)
                : Colors.transparent;
    final textColor = subdued
        ? tokens.text.withValues(alpha: 0.38)
        : isVerb
            ? const Color(0xFFF6E7D2)
            : tokens.text;
    return Container(
      key: subdued ? const ValueKey('firebar-chip-subdued') : null,
      height: 28,
      padding: const EdgeInsets.fromLTRB(4, 3, 5, 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showJersey) ...[
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
                  color: FfTokens.firebar,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: Text(
              label,
              maxLines: 1,
              style: tokens.metaStyle.copyWith(
                color: textColor,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if ((result.kind == FirebarResultKind.verb &&
                  result.verbKey != null &&
                  controller.isVerbPinned(result.verbKey!)) ||
              (result.kind == FirebarResultKind.player &&
                  player != null &&
                  result.isHome != null &&
                  controller.isPlayerPinned(
                    player,
                    isHome: result.isHome!,
                  ))) ...[
            const SizedBox(width: 4),
            PhosphorIcon(PhosphorIconsFill.pushPin,
              size: 12,
              color: subdued
                  ? tokens.text.withValues(alpha: 0.38)
                  : FfTokens.pinned,
            ),
          ],
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              controller.removeFirebarChip(result);
            },
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: PhosphorIcon(
                PhosphorIconsBold.x,
                size: 12,
                color: FfTokens.nocturneT3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebarShortcutHint extends StatelessWidget {
  const _FirebarShortcutHint({
    required this.keys,
    required this.action,
    required this.tokens,
    this.onTap,
  });

  final String keys;
  final String action;
  final FfTokens tokens;
  final VoidCallback? onTap;

  static const double height = 38;

  static double widthFor(String keys, String action) {
    const keyStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    const actionStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    final keyWidth = _firebarTextWidth(keys.toUpperCase(), keyStyle);
    final actionWidth = _firebarTextWidth(action.toUpperCase(), actionStyle);
    final text = keyWidth > actionWidth ? keyWidth : actionWidth;
    const sidePadding = 20.0;
    return text + sidePadding < height ? height : text + sidePadding;
  }

  @override
  Widget build(BuildContext context) {
    final color = tokens.textSecondary;
    final label = action.toUpperCase();
    final shortcut = keys.toUpperCase();
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
      width: widthFor(keys, action),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shortcut,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              height: 1,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              height: 1,
              color: color,
            ),
          ),
        ],
      ),
        ),
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
    final fill = selected
        ? FfTokens.firebar.withValues(alpha: 0.16)
        : tokens.badgeFill;
    final border = selected
        ? FfTokens.firebar.withValues(alpha: 0.42)
        : tokens.divider;
    final textColor = selected ? FfTokens.firebar : tokens.text;

    return InkWell(
      canRequestFocus: false,
      onTap: () => controller.chooseFirebarOption(option),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Text(
          option.label,
          style: tokens.metaStyle.copyWith(
            color: textColor,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}


String _compactPlayerLabel(String fullName, String? jerseyNumber) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  final jersey = (jerseyNumber ?? '').trim();
  final number = jersey.isEmpty ? '' : '#$jersey ';
  if (parts.length <= 1) {
    return '$number$fullName'.trim();
  }
  final rest = parts.sublist(1).join(' ');
  return '$number${parts.first[0]}. $rest';
}

double _firebarTextWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

double _typingSlotWidth(String typed, TextStyle style) {
  if (typed.isEmpty) return 18;
  return _firebarTextWidth(typed, style) + 10;
}

bool _firebarChipPinned(CaptionV2Controller controller, FirebarResult result) {
  final player = result.player;
  if (result.kind == FirebarResultKind.verb &&
      result.verbKey != null &&
      controller.isVerbPinned(result.verbKey!)) {
    return true;
  }
  if (result.kind == FirebarResultKind.player &&
      player != null &&
      result.isHome != null &&
      controller.isPlayerPinned(player, isHome: result.isHome!)) {
    return true;
  }
  return false;
}

double _firebarChipWidth(
  CaptionV2Controller controller,
  FfTokens tokens,
  FirebarResult result, {
  required bool compact,
  required bool selected,
}) {
  final label = _FirebarChip.labelFor(result, controller, compact: compact);
  final nameStyle = tokens.metaStyle.copyWith(
    fontSize: 13,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
  );
  var width = 11.0;
  final player = result.player;
  if (player != null && !compact) {
    final jersey = player.jerseyNumber ?? '—';
    final jerseyWidth = _firebarTextWidth(
      jersey,
      tokens.jerseyStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
    );
    final badge = jerseyWidth + 8;
    width += (badge < 24 ? 24 : badge) + 5;
  }
  width += _firebarTextWidth(label, nameStyle);
  if (_firebarChipPinned(controller, result)) width += 16;
  width += 20;
  return width;
}

double _firebarContentWidth({
  required CaptionV2Controller controller,
  required FfTokens tokens,
  required String typed,
  required Set<int> compact,
}) {
  const titleStyle = TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  const keyStyle = TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
  final typingStyle = tokens.metaStyle.copyWith(fontSize: 12);
  var width = 15 +
      5 +
      _firebarTextWidth('Firebar', titleStyle) +
      6 +
      (_firebarTextWidth('⌘K', keyStyle) + 12) +
      8 +
      1;
  var children = 1;
  width += _typingSlotWidth(typed, typingStyle);
  children++;
  final chips = controller.firebarCommitted;
  for (var index = 0; index < chips.length; index++) {
    width += _firebarChipWidth(
      controller,
      tokens,
      chips[index],
      compact: compact.contains(index),
      selected: index == controller.firebarChipCursor,
    );
    children++;
  }
  if (controller.firebarOptions.isNotEmpty) {
    width += _firebarTextWidth(
      controller.firebarOptionPrompt ?? 'Choose:',
      tokens.metaStyle.copyWith(fontSize: 12),
    );
    children++;
    for (var index = 0;
        index < controller.filteredFirebarOptions.length;
        index++) {
      final option = controller.filteredFirebarOptions[index];
      width += _firebarTextWidth(
            option.label,
            tokens.metaStyle.copyWith(
              fontSize: 12,
              fontWeight: index == controller.firebarOptionIndex
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ) +
          22;
      children++;
    }
  }
  if (children > 1) width += (children - 1) * 6;
  return width;
}

double _shortcutClusterWidth(CaptionV2Controller controller) {
  if (!controller.searchOpen) return 0;
  var width = 8 + 1 + 6 + _FirebarShortcutHint.widthFor('⌘S', 'save');
  if (controller.ftpModeEnabled) {
    width += 4 + _FirebarShortcutHint.widthFor('⌘↵', 'ftp');
  }
  width += 4 + _FirebarShortcutHint.widthFor('esc', 'exit');
  return width;
}

Set<int> _compactPlayerIndexes({
  required double maxWidth,
  required CaptionV2Controller controller,
  required FfTokens tokens,
  required String typed,
}) {
  final players = <int>[
    for (var index = 0; index < controller.firebarCommitted.length; index++)
      if (controller.firebarCommitted[index].kind == FirebarResultKind.player)
        index,
  ];
  if (players.isEmpty || !maxWidth.isFinite) return const {};
  for (var count = 0; count <= players.length; count++) {
    final compact = players.take(count).toSet();
    final used = _firebarContentWidth(
      controller: controller,
      tokens: tokens,
      typed: typed,
      compact: compact,
    );
    if (used <= maxWidth) return compact;
  }
  return players.toSet();
}

bool _pinnedVerbIsPaused(
  CaptionV2Controller controller,
  FirebarResult chip,
  bool typingVerbs,
) {
  if (!typingVerbs || chip.kind != FirebarResultKind.verb) return false;
  final verb = chip.verbKey;
  if (verb == null || !controller.isVerbPinned(verb)) return false;
  return controller.firebarSelectedResult?.verbKey != verb;
}

