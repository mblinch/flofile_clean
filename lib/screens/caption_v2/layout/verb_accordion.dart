import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_sort_mode.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/base_row.dart';
import '../widgets/rbi_row.dart';
import '../widgets/celebration_dropdown.dart';
import '../widgets/verb_tile.dart';
import 'caption_v2_verb_editor.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Favorites stays first and All stays last. Everything else keeps saved order.
List<String> verbCategoriesForDisplay(Iterable<String> categories) {
  final list = categories.toList();
  return [
    if (list.contains('Favorites')) 'Favorites',
    for (final name in list)
      if (name != 'Favorites' && name != 'All') name,
    if (list.contains('All')) 'All',
  ];
}

bool verbCategoryOrderLocked(String category) =>
    category == 'Favorites' || category == 'All';

/// Header chrome that accepts a category drop. Favorites and All are fixed.
class VerbCategoryDropTarget extends StatelessWidget {
  const VerbCategoryDropTarget({
    required this.category,
    required this.controller,
    required this.child,
  });

  final String category;
  final CaptionV2Controller controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (verbCategoryOrderLocked(category)) return child;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != category && !verbCategoryOrderLocked(details.data),
      onAcceptWithDetails: (details) {
        controller.reorderVerbCategory(details.data, category);
      },
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return child;
        return DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: FfTokens.nocturneAc, width: 2),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class VerbCategoryDragHandle extends StatelessWidget {
  const VerbCategoryDragHandle({
    required this.category,
    required this.color,
  });

  final String category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (verbCategoryOrderLocked(category)) return const SizedBox.shrink();
    return Tooltip(
      message: 'Drag to reorder category',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<String>(
          data: category,
          feedback: Material(
            color: const Color(0xFF15242E),
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                category,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          childWhenDragging: PhosphorIcon(
            PhosphorIconsRegular.dotsSixVertical,
            size: 12,
            color: color.withValues(alpha: 0.25),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.dotsSixVertical,
            size: 12,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Default no-scroll verb accordion. Favorites is a pinned virtual category.
class DefaultVerbAccordion extends StatefulWidget {
  const DefaultVerbAccordion({
    super.key,
    required this.controller,
    required this.onEditVerb,
    this.onVerbArmed,
  });

  final CaptionV2Controller controller;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  static const headerH = 32.0;
  static const verbRowH = 24.0;
  static const laneHeaderH = 28.0;
  static const pinnedBarH = 22.0;
  static const categoryFontSize = 15.0;
  static const verbFontSize = 13.5;

  @override
  State<DefaultVerbAccordion> createState() => DefaultVerbAccordionState();
}

class DefaultVerbAccordionState extends State<DefaultVerbAccordion> {
  late String _openCategory;

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories =>
      verbCategoriesForDisplay(controller.verbCategories);

  List<EffectiveVerb> _verbsFor(String category) {
    return controller.verbDefinitionsByCategory[category] ??
        const <EffectiveVerb>[];
  }

  EffectiveVerb? get _pinnedVerb => controller.pinnedVerbDefinition;

  @override
  void initState() {
    super.initState();
    final categories = _categories;
    final current = controller.verbCategory;
    if (current != null && categories.contains(current)) {
      _openCategory = current;
    } else if (categories.contains('Offense')) {
      _openCategory = 'Offense';
    } else if (categories.contains('Favorites')) {
      _openCategory = 'Favorites';
    } else {
      _openCategory = categories.isEmpty ? 'Offense' : categories.first;
    }
    if (controller.verbCategory != _openCategory) {
      controller.setVerbCategory(_openCategory);
    }
  }

  @override
  void didUpdateWidget(covariant DefaultVerbAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final categories = _categories;
    final current = controller.verbCategory;
    if (current != null &&
        categories.contains(current) &&
        current != _openCategory) {
      _openCategory = current;
    } else if (!categories.contains(_openCategory) && categories.isNotEmpty) {
      _openCategory =
          categories.contains('Offense') ? 'Offense' : categories.first;
    }
  }

  String _displayName(String category) {
    if (category == 'Non Game-Action') return 'Non-game';
    return category;
  }

  void _open(String category) {
    if (category == _openCategory) return;
    setState(() => _openCategory = category);
    controller.setVerbCategory(category);
  }

  void _moveVerbSelection(int delta) {
    final categories = _categories;
    if (categories.isEmpty) return;
    var catIndex = categories.indexOf(_openCategory);
    if (catIndex < 0) catIndex = 0;
    var verbs = _verbsFor(categories[catIndex]);
    if (verbs.isEmpty) return;

    final selected = controller.selectedVerb;
    var index = verbs.indexWhere((verb) => verb.key == selected);

    if (index < 0) {
      index = delta > 0 ? 0 : verbs.length - 1;
      controller.selectVerb(verbs[index].key);
      widget.onVerbArmed?.call();
      return;
    }

    final next = index + delta;
    if (next >= 0 && next < verbs.length) {
      controller.selectVerb(verbs[next].key);
      widget.onVerbArmed?.call();
      return;
    }

    // Walk into adjacent category.
    final nextCat = catIndex + (delta > 0 ? 1 : -1);
    if (nextCat < 0 || nextCat >= categories.length) return;
    final neighbor = categories[nextCat];
    final neighborVerbs = _verbsFor(neighbor);
    if (neighborVerbs.isEmpty) {
      _open(neighbor);
      return;
    }
    _open(neighbor);
    final pick = delta > 0 ? neighborVerbs.first : neighborVerbs.last;
    controller.selectVerb(pick.key);
    widget.onVerbArmed?.call();
  }

  void _stepCategory(int delta) {
    final categories = _categories;
    if (categories.isEmpty) return;
    final current = categories.indexOf(_openCategory);
    final start = current < 0 ? 0 : current;
    final next = (start + delta).clamp(0, categories.length - 1);
    _open(categories[next]);
  }

  KeyEventResult onKeyEvent(KeyEvent event) {
    if (controller.searchOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveVerbSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveVerbSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _stepCategory(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _stepCategory(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final categories = _categories;
    final openVerbs = _verbsFor(_openCategory);
    final pinned = _pinnedVerb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Spacer(),
                _VerbSortMenu(controller: controller, tokens: t),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: t.divider),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bodyH = constraints.maxHeight;
              final headerTotal =
                  categories.length * DefaultVerbAccordion.headerH;
              var verbRowH = DefaultVerbAccordion.verbRowH;
              var headerH = DefaultVerbAccordion.headerH;

              // Tighten metrics when the body is short.
              final worstOneUp = headerTotal + openVerbs.length * verbRowH;
              if (worstOneUp > bodyH && bodyH > 0) {
                headerH = 28;
                verbRowH = 20;
              }

              // Always show the pinned bar (title + verb on one row).
              final pinnedH = DefaultVerbAccordion.pinnedBarH;
              final availableForVerbs =
                  (bodyH - categories.length * headerH - pinnedH)
                      .clamp(0.0, bodyH);
              final maxRowsOneUp =
                  verbRowH <= 0 ? 0 : (availableForVerbs / verbRowH).floor();
              final twoUp =
                  openVerbs.length > maxRowsOneUp && openVerbs.length > 1;

              assert(() {
                final fitted = twoUp
                    ? categories.length * headerH +
                        ((openVerbs.length + 1) ~/ 2) * verbRowH
                    : categories.length * headerH + openVerbs.length * verbRowH;
                if (bodyH > 0 && fitted > bodyH + 0.5) {
                  debugPrint(
                    'DefaultVerbAccordion: lane body ${bodyH.toStringAsFixed(0)}px '
                    'cannot fit fitted=${fitted.toStringAsFixed(0)}px '
                    '(${categories.length} headers × $headerH + '
                    '${openVerbs.length} verbs × $verbRowH'
                    '${twoUp ? ', two-up' : ''})',
                  );
                }
                return true;
              }());

              return Column(
                children: [
                  _PinnedVerbSlot(
                    height: pinnedH,
                    tokens: t,
                    controller: controller,
                    verb: pinned,
                    onEditVerb: widget.onEditVerb,
                    onVerbArmed: widget.onVerbArmed,
                  ),
                  for (final category in categories)
                    if (category != _openCategory)
                      _AccordionSection(
                        category: category,
                        displayName: _displayName(category),
                        open: false,
                        headerH: headerH,
                        verbRowH: verbRowH,
                        verbs: const <EffectiveVerb>[],
                        twoUp: false,
                        rearrangeable: false,
                        tokens: t,
                        controller: controller,
                        onOpen: () => _open(category),
                        onEditVerb: widget.onEditVerb,
                        onVerbArmed: widget.onVerbArmed,
                      )
                    else
                      Expanded(
                        child: _AccordionSection(
                          category: category,
                          displayName: _displayName(category),
                          open: true,
                          scrollBody: true,
                          headerH: headerH,
                          verbRowH: verbRowH,
                          verbs: openVerbs,
                          // All is the full catalog — always one scrolling column.
                          twoUp: category == 'All' ||
                                  controller.verbSortMode == VerbSortMode.custom
                              ? false
                              : twoUp,
                          rearrangeable:
                              controller.verbSortMode == VerbSortMode.custom &&
                                  category != 'Favorites' &&
                                  category != 'All',
                          tokens: t,
                          controller: controller,
                          onOpen: () => _open(category),
                          onEditVerb: widget.onEditVerb,
                          onVerbArmed: widget.onVerbArmed,
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VerbSortMenu extends StatelessWidget {
  const _VerbSortMenu({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  String get _shortLabel {
    switch (controller.verbSortMode) {
      case VerbSortMode.alphabetical:
        return 'A–Z';
      case VerbSortMode.mostUsed:
        return 'Most used';
      case VerbSortMode.custom:
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Verb sort',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 24),
      onSelected: (value) async {
        switch (value) {
          case 'alphabetical':
            await controller.setVerbSortMode(VerbSortMode.alphabetical);
            break;
          case 'mostUsed':
            await controller.setVerbSortMode(VerbSortMode.mostUsed);
            break;
          case 'custom':
            await controller.setVerbSortMode(VerbSortMode.custom);
            break;
          case 'reset':
            await controller.resetVerbsToFactoryDefaults();
            break;
        }
      },
      itemBuilder: (context) => [
        for (final mode in VerbSortMode.values)
          CheckedPopupMenuItem<String>(
            value: mode.storageValue,
            checked: controller.verbSortMode == mode,
            child: Text(mode.menuLabel),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'reset',
          child: Text('Reset verbs to defaults'),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _shortLabel,
            style: TextStyle(
              fontFamily: FfTokens.labelFamily,
              fontWeight: FontWeight.w500,
              fontSize: 10.5,
              color: tokens.text.withValues(alpha: 0.62),
            ),
          ),
          PhosphorIcon(PhosphorIconsRegular.caretDown,
            size: 16,
            color: tokens.text.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }
}

class _AccordionSection extends StatelessWidget {
  const _AccordionSection({
    required this.category,
    required this.displayName,
    required this.open,
    required this.headerH,
    required this.verbRowH,
    required this.verbs,
    required this.twoUp,
    required this.rearrangeable,
    required this.tokens,
    required this.controller,
    required this.onOpen,
    required this.onEditVerb,
    this.onVerbArmed,
    this.scrollBody = false,
  });

  final String category;
  final String displayName;
  final bool open;
  final bool scrollBody;
  final double headerH;
  final double verbRowH;
  final List<EffectiveVerb> verbs;
  final bool twoUp;
  final bool rearrangeable;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final VoidCallback onOpen;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  @override
  Widget build(BuildContext context) {
    final header = VerbCategoryDropTarget(
      category: category,
      controller: controller,
      child: _CategoryHeader(
        label: displayName,
        open: open,
        height: headerH,
        tokens: tokens,
        onTap: onOpen,
        gold: category == 'Favorites',
        trailing: VerbCategoryDragHandle(
          category: category,
          color: tokens.textSecondary,
        ),
      ),
    );
    if (!open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header],
      );
    }

    final board = _VerbBoard(
      category: category,
      verbs: verbs,
      rowHeight: verbRowH,
      twoUp: twoUp,
      rearrangeable: rearrangeable,
      tokens: tokens,
      controller: controller,
      onEditVerb: onEditVerb,
      onVerbArmed: onVerbArmed,
    );

    if (!scrollBody) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, board],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: rearrangeable
              ? board
              : Scrollbar(
                  child: SingleChildScrollView(
                    child: board,
                  ),
                ),
        ),
      ],
    );
  }
}

class _PinnedVerbSlot extends StatelessWidget {
  const _PinnedVerbSlot({
    required this.height,
    required this.tokens,
    required this.controller,
    required this.verb,
    required this.onEditVerb,
    this.onVerbArmed,
  });

  final double height;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final EffectiveVerb? verb;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  @override
  Widget build(BuildContext context) {
    final hasVerb = verb != null;
    final armed = hasVerb && controller.selectedVerb == verb!.key;
    final showRbi = armed && controller.verbNeedsRbi(verb!.key);
    final showBase = armed && controller.verbNeedsBase(verb!.key);
    final showCelebration =
        armed && controller.verbNeedsCelebration(verb!.key);

    final bar = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: hasVerb ? FfTokens.pinnedDivider : tokens.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasVerb ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
            size: 10,
            color: FfTokens.pinned,
          ),
          const SizedBox(width: 4),
          Text(
            'Pinned',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.labelFamily,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.0,
              letterSpacing: 0.1,
              color: FfTokens.pinned,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: hasVerb
                ? CmdClick(
                    onTap: () {
                      onVerbArmed?.call();
                      controller.selectVerb(verb!.key);
                    },
                    onCmdTap: () {
                      onVerbArmed?.call();
                      controller.toggleVerbPin(verb!.key);
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        verb!.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.labelFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: DefaultVerbAccordion.verbFontSize,
                          height: 1.0,
                          color: armed
                              ? tokens.text
                              : tokens.text.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '(CMD ⌘ click a verb in the menu to pin)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                        height: 1.0,
                        color: FfTokens.pinnedHint,
                      ),
                    ),
                  ),
          ),
          if (hasVerb)
            TextButton(
              onPressed: () => controller.toggleVerbPin(verb!.key),
              style: TextButton.styleFrom(
                foregroundColor: FfTokens.pinned,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Unpin',
                style: TextStyle(
                  fontFamily: FfTokens.labelFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: FfTokens.pinned,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (armed && (showRbi || showBase || showCelebration))
          VerbExtrasPanel(
            controller: controller,
            verbKey: verb!.key,
            showRbi: showRbi,
            showBase: showBase,
            showCelebration: showCelebration,
            showSaveActions: false,
            tokens: tokens,
          ),
      ],
    );
  }
}

class _CategoryHeader extends StatefulWidget {
  const _CategoryHeader({
    required this.label,
    required this.open,
    required this.height,
    required this.tokens,
    required this.onTap,
    this.gold = false,
    this.trailing,
  });

  final String label;
  final bool open;
  final double height;
  final FfTokens tokens;
  final VoidCallback onTap;
  final bool gold;
  final Widget? trailing;

  @override
  State<_CategoryHeader> createState() => _CategoryHeaderState();
}

class _CategoryHeaderState extends State<_CategoryHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final open = widget.open;
    final gold = widget.gold;
    final labelColor = gold
        ? FfTokens.favorites
        : (open ? t.text : t.textSecondary);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: gold
                ? FfTokens.favoritesFill
                : open
                    ? t.selected.withValues(alpha: 0.55)
                    : (_hovered ? t.hover : Colors.transparent),
            borderRadius:
                open ? BorderRadius.circular(FfTokens.radiusRow) : null,
            boxShadow: open
                ? FfTokens.selectionGlow(
                    gold ? FfTokens.favorites : t.accent,
                  )
                : null,
            border: Border(
              bottom: BorderSide(
                color: gold ? FfTokens.favoritesBorder : t.divider,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                open ? PhosphorIconsRegular.caretDown : PhosphorIconsRegular.caretRight,
                size: 11,
                color: labelColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.label.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: FfTokens.categoryLabel(color: labelColor),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _VerbBoard extends StatelessWidget {
  const _VerbBoard({
    required this.category,
    required this.verbs,
    required this.rowHeight,
    required this.twoUp,
    required this.rearrangeable,
    required this.tokens,
    required this.controller,
    required this.onEditVerb,
    this.onVerbArmed,
  });

  final String category;
  final List<EffectiveVerb> verbs;
  final double rowHeight;
  final bool twoUp;
  final bool rearrangeable;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    final keys = verbs.map((verb) => verb.key).toList();
    final moved = keys.removeAt(oldIndex);
    keys.insert(newIndex, moved);
    await controller.rearrangeVerbsInCategory(category, keys);
  }

  @override
  Widget build(BuildContext context) {
    if (verbs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No verbs', style: tokens.metaStyle),
      );
    }
    if (rearrangeable) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: verbs.length,
        onReorderItem: _onReorderItem,
        itemBuilder: (context, index) {
          final verb = verbs[index];
          return ReorderableDragStartListener(
            key: ValueKey(verb.key),
            index: index,
            child: _AccordionVerbRow(
              controller: controller,
              verb: verb,
              index: index,
              rowHeight: rowHeight,
              tokens: tokens,
              onEditVerb: onEditVerb,
              onVerbArmed: onVerbArmed,
              showDragHandle: true,
            ),
          );
        },
      );
    }
    if (!twoUp) {
      return Column(
        children: [
          for (var i = 0; i < verbs.length; i++)
            _AccordionVerbRow(
              controller: controller,
              verb: verbs[i],
              index: i,
              rowHeight: rowHeight,
              tokens: tokens,
              onEditVerb: onEditVerb,
              onVerbArmed: onVerbArmed,
            ),
        ],
      );
    }

    final mid = (verbs.length + 1) ~/ 2;
    final left = verbs.sublist(0, mid);
    final right = verbs.sublist(mid);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < left.length; i++)
                _AccordionVerbRow(
                  controller: controller,
                  verb: left[i],
                  index: i,
                  rowHeight: rowHeight,
                  tokens: tokens,
                  onEditVerb: onEditVerb,
                  onVerbArmed: onVerbArmed,
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < right.length; i++)
                _AccordionVerbRow(
                  controller: controller,
                  verb: right[i],
                  index: mid + i,
                  rowHeight: rowHeight,
                  tokens: tokens,
                  onEditVerb: onEditVerb,
                  onVerbArmed: onVerbArmed,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccordionVerbRow extends StatefulWidget {
  const _AccordionVerbRow({
    required this.controller,
    required this.verb,
    required this.index,
    required this.rowHeight,
    required this.tokens,
    required this.onEditVerb,
    this.onVerbArmed,
    this.showDragHandle = false,
    this.showSaveActions = true,
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final int index;
  final double rowHeight;
  final FfTokens tokens;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;
  final bool showDragHandle;
  final bool showSaveActions;

  @override
  State<_AccordionVerbRow> createState() => _AccordionVerbRowState();
}

class _AccordionVerbRowState extends State<_AccordionVerbRow> {
  CaptionV2Controller get controller => widget.controller;
  EffectiveVerb get verb => widget.verb;
  FfTokens get tokens => widget.tokens;

  Future<void> _contextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showCaptionV2PopupMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            verb.isFavorite
                ? 'Remove from Favorites'
                : 'Add to Favorites',
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(
            controller.isVerbPinned(verb.key) ? 'Unpin Verb' : 'Pin Verb',
          ),
        ),
        const PopupMenuItem(value: 'edit', child: Text('Edit verb…')),
      ],
    );
    if (action == null) return;
    switch (action) {
      case 'favorite':
        await controller.toggleVerbFavorite(verb.key);
        break;
      case 'pin':
        controller.toggleVerbPin(verb.key);
        break;
      case 'edit':
        widget.onEditVerb(verb.key);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final armed = controller.selectedVerb == verb.key;
    final showRbi = armed && controller.verbNeedsRbi(verb.key);
    final showBase = armed && controller.verbNeedsBase(verb.key);
    final showCelebration = armed && controller.verbNeedsCelebration(verb.key);

    final label = Row(
                  children: [
                    if (widget.showDragHandle)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: PhosphorIcon(PhosphorIconsRegular.dotsSixVertical,
                          size: 14,
                          color: tokens.text.withValues(alpha: 0.40),
                        ),
                      )
                    else
                      SizedBox(
                        width: 16,
                        child: controller.isVerbPinned(verb.key)
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: PhosphorIcon(PhosphorIconsFill.pushPin,
                                  size: 10,
                                  color: FfTokens.pinned,
                                ),
                              )
                            : null,
                      ),
                    Expanded(
                      child: Text(
                        verb.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FfTokens.rosterName(
                          color: tokens.text,
                          selected: armed,
                        ),
                      ),
                    ),
                    if (controller.verbSortMode == VerbSortMode.mostUsed &&
                        controller.verbUsageCount(verb.key) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '${controller.verbUsageCount(verb.key)}',
                          style: TextStyle(
                            fontFamily: FfTokens.monoFamily,
                            fontSize: 9.5,
                            color: tokens.text.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    if (armed)
                      Text(
                        '⏎',
                        style: TextStyle(
                          fontFamily: FfTokens.monoFamily,
                          fontSize: 9.5,
                          color: tokens.accent,
                        ),
                      ),
                  ],
    );

    final extras = armed &&
            (showRbi ||
                showBase ||
                showCelebration ||
                widget.showSaveActions)
        ? VerbExtrasPanel(
            controller: controller,
            verbKey: verb.key,
            showRbi: showRbi,
            showBase: showBase,
            showCelebration: showCelebration,
            showSaveActions: widget.showSaveActions,
            tokens: tokens,
            embedded: true,
          )
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: armed ? 4 : 0,
        vertical: armed ? 2 : 1,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(armed ? 8 : 12, 0, armed ? 8 : 4, 0),
        decoration: BoxDecoration(
          color: armed ? tokens.selected : null,
          borderRadius: BorderRadius.circular(FfTokens.radiusRow),
          border: armed ? Border.all(color: tokens.accent, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: CmdClick(
                useInkWell: true,
                onTap: () {
                  widget.onVerbArmed?.call();
                  controller.selectVerb(verb.key);
                },
                onCmdTap: () {
                  widget.onVerbArmed?.call();
                  controller.toggleVerbPin(verb.key);
                },
                onSecondaryTapDown: (details) =>
                    _contextMenu(context, details),
                child: SizedBox(
                  height: armed ? 34 : widget.rowHeight,
                  child: label,
                ),
              ),
            ),
            if (extras != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: extras,
              ),
          ],
        ),
      ),
    );
  }
}

/// Nested RUNNERS ON / BASE / REACTION panel under an armed verb,
/// ending with Save / FTP once the option rows are shown.
///
/// Authored modifier groups are edited in Admin → Verb authoring only;
/// the live caption session keeps these classic RBI / base / celebration rows.
class VerbExtrasPanel extends StatelessWidget {
  const VerbExtrasPanel({
    super.key,
    required this.controller,
    required this.verbKey,
    required this.showRbi,
    required this.showBase,
    required this.showCelebration,
    required this.tokens,
    this.showSaveActions = true,
    this.embedded = false,
  });

  final CaptionV2Controller controller;
  final String verbKey;
  final bool showRbi;
  final bool showBase;
  final bool showCelebration;
  final bool showSaveActions;
  final FfTokens tokens;

  /// Drawn inside the selected verb border, without a second card.
  final bool embedded;

  bool get _hasOptionRows => showRbi || showBase || showCelebration;

  bool get _optionsComplete {
    if (showRbi && verbKey == 'Home Run' && controller.rbi < 1) return false;
    if (showBase &&
        (controller.selectedBase == null ||
            controller.selectedBase!.trim().isEmpty)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final homeRun = verbKey == 'Home Run';
    final reactionChips = controller.reactionOptionsFor(verbKey);
    final celebrationTypes = controller.celebrationTypeOptionsFor(verbKey);
    final showActions =
        showSaveActions && (!_hasOptionRows || _optionsComplete);
    if (!_hasOptionRows && !showActions) {
      return const SizedBox.shrink();
    }

    final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showRbi) ...[
              Text(
                homeRun ? 'RUNNERS ON' : 'RBI',
                style: TextStyle(
                  fontFamily: FfTokens.labelFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: tokens.text.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 5),
              RbiRow(
                value: controller.rbi,
                compact: true,
                homeRunStyle: homeRun,
                onChanged: controller.setRbi,
              ),
            ],
            if (showRbi && (showBase || showCelebration))
              const SizedBox(height: 8),
            if (showBase) ...[
              Text(
                'BASE',
                style: TextStyle(
                  fontFamily: FfTokens.labelFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: tokens.text.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 5),
              BaseRow(
                value: controller.selectedBase,
                compact: true,
                onChanged: controller.setSelectedBase,
              ),
            ],
            if (showBase && showCelebration) const SizedBox(height: 8),
            if (showCelebration)
              CelebrationDropdown(
                compact: true,
                reactions: reactionChips,
                celebrations: celebrationTypes,
                selected: controller.celebrationType,
                onChanged: controller.setCelebrationType,
              ),
            if (showActions) ...[
              if (_hasOptionRows) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _VerbActionButton(
                        label: 'Save',
                        tokens: tokens,
                        onTap: () => controller.saveOrTransmitFromVerbMenu(
                          transmit: false,
                        ),
                      ),
                    ),
                    if (controller.ftpModeEnabled) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _VerbActionButton(
                          label: 'FTP',
                          tokens: tokens,
                          onTap: () => controller.saveOrTransmitFromVerbMenu(
                            transmit: true,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
    );

    if (embedded) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: body,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 10, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.divider),
        ),
        child: body,
      ),
    );
  }
}

class _VerbActionButton extends StatelessWidget {
  const _VerbActionButton({
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF243848),
                Color(0xFF15242E),
                Color(0xFF0E181F),
              ],
              stops: [0.0, 0.45, 1.0],
            ),
            border: Border.all(
              color: FfTokens.nocturneAc.withValues(alpha: 0.95),
            ),
            boxShadow: FfTokens.accentButtonGlow(FfTokens.nocturneAc),
          ),
          child: Center(
            child: Text(
              label,
              style: tokens.labelStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
