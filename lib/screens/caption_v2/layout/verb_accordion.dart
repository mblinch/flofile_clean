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

/// Verb keys already listed under another open category.
/// All is the full catalog, so those keys are omitted there.
Set<String> verbKeysAlreadyShownOutsideAll({
  required Set<String> openCategories,
  required Map<String, Iterable<String>> keysByCategory,
}) {
  final shown = <String>{};
  for (final category in openCategories) {
    if (category == 'All') continue;
    shown.addAll(keysByCategory[category] ?? const <String>[]);
  }
  return shown;
}

List<EffectiveVerb> verbsForOpenCategory({
  required String category,
  required bool open,
  required Map<String, List<EffectiveVerb>> verbsByCategory,
  required Set<String> openCategories,
}) {
  if (!open) return const <EffectiveVerb>[];
  final verbs = verbsByCategory[category] ?? const <EffectiveVerb>[];
  if (category != 'All') return verbs;
  final hidden = verbKeysAlreadyShownOutsideAll(
    openCategories: openCategories,
    keysByCategory: {
      for (final entry in verbsByCategory.entries)
        entry.key: entry.value.map((verb) => verb.key),
    },
  );
  if (hidden.isEmpty) return verbs;
  return [
    for (final verb in verbs)
      if (!hidden.contains(verb.key)) verb,
  ];
}

/// Drop the oldest open extras so at most [limit] categories stay open.
/// The current category is not in [extras].
void trimOpenVerbCategories(Set<String> extras, int limit) {
  final maxExtras = limit - 1;
  if (maxExtras <= 0) {
    extras.clear();
    return;
  }
  while (extras.length > maxExtras) {
    extras.remove(extras.first);
  }
}

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
  static const verbRowH = 20.0;
  static const laneHeaderH = 28.0;
  static const pinnedBarH = 22.0;
  static const categoryFontSize = 15.0;
  static const verbFontSize = 13.5;

  @override
  State<DefaultVerbAccordion> createState() => DefaultVerbAccordionState();
}

class DefaultVerbAccordionState extends State<DefaultVerbAccordion> {
  late String _openCategory;
  final Set<String> _extraOpen = {};

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

  bool _isOpen(String category) {
    if (controller.cascadeLimitFor(_categories.length) <= 0) return false;
    if (!controller.verbMultiOpen) return category == _openCategory;
    return category == _openCategory || _extraOpen.contains(category);
  }

  void _trimExtras() {
    trimOpenVerbCategories(
      _extraOpen,
      controller.cascadeLimitFor(_categories.length),
    );
  }

  void _open(String category) {
    if (category == _openCategory) return;
    setState(() {
      if (controller.verbMultiOpen) _extraOpen.add(_openCategory);
      _extraOpen.remove(category);
      _openCategory = category;
      _trimExtras();
    });
    controller.setVerbCategory(category);
  }

  void _toggle(String category) {
    if (!controller.verbMultiOpen) {
      _open(category);
      return;
    }
    setState(() {
      if (_extraOpen.contains(category)) {
        _extraOpen.remove(category);
        return;
      }
      if (category != _openCategory) {
        _extraOpen.add(category);
        _trimExtras();
        return;
      }
      if (_extraOpen.isEmpty) return;
      _openCategory = _extraOpen.first;
      _extraOpen.remove(_openCategory);
    });
    if (controller.verbCategory != _openCategory) {
      controller.setVerbCategory(_openCategory);
    }
  }

  void _moveVerbSelection(int delta) {
    if (controller.verbListAll) {
      _moveFlatVerbSelection(delta);
      return;
    }
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

  void _moveFlatVerbSelection(int delta) {
    final verbs = _verbsFor('All');
    if (verbs.isEmpty) return;
    final selected = controller.selectedVerb;
    var index = verbs.indexWhere((verb) => verb.key == selected);
    if (index < 0) {
      index = delta > 0 ? 0 : verbs.length - 1;
    } else {
      final next = (index + delta).clamp(0, verbs.length - 1);
      if (next == index) return;
      index = next;
    }
    controller.selectVerb(verbs[index].key);
    widget.onVerbArmed?.call();
  }

  void _stepCategory(int delta) {
    if (controller.verbListAll) return;
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
    _trimExtras();
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final categories = _categories;
    final openVerbs = _verbsFor(_openCategory);
    final pinned = _pinnedVerb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                _VerbSortMenu(controller: controller, tokens: t),
                const Spacer(),
                VerbMenuTools(controller: controller, tokens: t),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: t.divider),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bodyH = constraints.maxHeight;
              var verbRowH = DefaultVerbAccordion.verbRowH * controller.verbFontScale;
              var headerH = DefaultVerbAccordion.headerH * controller.verbFontScale;

              // Tighten metrics when the body is short.
              final worstOneUp = headerH * categories.length +
                  openVerbs.length * verbRowH;
              if (worstOneUp > bodyH && bodyH > 0) {
                headerH = 28 * controller.verbFontScale;
                verbRowH = 20 * controller.verbFontScale;
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

              if (controller.verbListAll) {
                final verbs = _verbsFor('All');
                final verbRow =
                    DefaultVerbAccordion.verbRowH * controller.verbFontScale;
                return Column(
                  children: [
                    _PinnedVerbSlot(
                      height: DefaultVerbAccordion.pinnedBarH,
                      tokens: t,
                      controller: controller,
                      verb: pinned,
                      onEditVerb: widget.onEditVerb,
                      onVerbArmed: widget.onVerbArmed,
                    ),
                    _AllVerbsTitle(tokens: t),
                    Expanded(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: _VerbBoard(
                            category: 'All',
                            verbs: verbs,
                            rowHeight: verbRow,
                            twoUp: false,
                            rearrangeable: false,
                            tokens: t,
                            controller: controller,
                            onEditVerb: widget.onEditVerb,
                            onVerbArmed: widget.onVerbArmed,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (controller.verbMultiOpen) {
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
                    Expanded(
                      child: ListView(
                        children: [
                          for (final category in categories)
                            _AccordionSection(
                              category: category,
                              displayName: _displayName(category),
                              open: _isOpen(category),
                              headerH: headerH,
                              verbRowH: verbRowH * controller.verbFontScale,
                              verbs: verbsForOpenCategory(
                                category: category,
                                open: _isOpen(category),
                                verbsByCategory: {
                                  for (final name in categories)
                                    name: _verbsFor(name),
                                },
                                openCategories: {
                                  for (final name in categories)
                                    if (_isOpen(name)) name,
                                },
                              ),
                              twoUp: false,
                              rearrangeable: false,
                              tokens: t,
                              controller: controller,
                              onOpen: () => _toggle(category),
                              onEditVerb: widget.onEditVerb,
                              onVerbArmed: widget.onVerbArmed,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              }

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
                        onOpen: () => _toggle(category),
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
                          verbRowH: verbRowH * controller.verbFontScale,
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
                          onOpen: () => _toggle(category),
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

class VerbMenuTools extends StatelessWidget {
  const VerbMenuTools({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VerbTextSizeControl(controller: controller),
        const SizedBox(width: 2),
        _VerbCascadeLimitMenu(controller: controller),
      ],
    );
  }
}

/// Compact minus and plus for verb text size, shown beside the gear.
class _VerbTextSizeControl extends StatelessWidget {
  const _VerbTextSizeControl({required this.controller});

  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final step = controller.verbFontStep.clamp(
          CaptionV2Controller.verbFontStepMin,
          CaptionV2Controller.verbFontStepMax,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderStepButton(
              icon: PhosphorIconsRegular.minus,
              enabled: step > CaptionV2Controller.verbFontStepMin,
              onTap: () => controller.nudgeVerbFont(-1),
            ),
            const SizedBox(width: 6),
            _HeaderStepButton(
              icon: PhosphorIconsRegular.plus,
              enabled: step < CaptionV2Controller.verbFontStepMax,
              onTap: () => controller.nudgeVerbFont(1),
            ),
          ],
        );
      },
    );
  }
}

class _VerbCascadeLimitMenu extends StatefulWidget {
  const _VerbCascadeLimitMenu({required this.controller});

  final CaptionV2Controller controller;

  @override
  State<_VerbCascadeLimitMenu> createState() => _VerbCascadeLimitMenuState();
}

class _VerbCascadeLimitMenuState extends State<_VerbCascadeLimitMenu> {
  static const _menuWidth = 360.0;

  OverlayEntry? _entry;
  bool _open = false;
  bool _hovered = false;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _show();
    }
  }

  void _close() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    if (!mounted) return;
    setState(() => _open = false);
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    final overlayBox = overlayState?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlayBox == null || !overlayBox.hasSize) {
      return;
    }
    final origin = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    const overhang = 8.0;
    var left = origin.dx + box.size.width - _menuWidth + overhang;
    final maxLeft = overlayBox.size.width - 8 - _menuWidth;
    left = left.clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft);

    _entry = OverlayEntry(
      builder: (menuContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CustomSingleChildLayout(
              delegate: _VerbGearMenuAbove(
                anchorTop: origin.dy,
                left: left,
                width: _menuWidth,
              ),
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _close();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: DefaultTextStyle.merge(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: _VerbSettingsCard(controller: widget.controller),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState!.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final active = _open || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.gearSix,
            size: 18,
            color: active ? FfTokens.nocturneTx : FfTokens.nocturneT3,
          ),
        ),
      ),
    );
  }
}

class _VerbGearMenuAbove extends SingleChildLayoutDelegate {
  _VerbGearMenuAbove({
    required this.anchorTop,
    required this.left,
    required this.width,
  });

  final double anchorTop;
  final double left;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxHeight = (constraints.maxHeight - 16).clamp(0.0, constraints.maxHeight);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight > 0 ? maxHeight : constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var top = anchorTop - childSize.height;
    if (top < 8) top = 8;
    final maxTop = size.height - 8 - childSize.height;
    if (top > maxTop) top = maxTop < 8 ? 8.0 : maxTop;
    var x = left;
    final maxLeft = size.width - 8 - childSize.width;
    if (x > maxLeft) x = maxLeft < 8 ? 8.0 : maxLeft;
    if (x < 8) x = 8;
    return Offset(x, top);
  }

  @override
  bool shouldRelayout(covariant _VerbGearMenuAbove oldDelegate) {
    return anchorTop != oldDelegate.anchorTop ||
        left != oldDelegate.left ||
        width != oldDelegate.width;
  }
}

class _VerbSettingsCard extends StatelessWidget {
  const _VerbSettingsCard({required this.controller});

  final CaptionV2Controller controller;

  int get _categoryCount {
    final count = verbCategoriesForDisplay(controller.verbCategories).length;
    return count < 1 ? 1 : count;
  }

  bool get _allOpen {
    final limit = controller.verbCascadeLimit;
    final count = _categoryCount;
    if (limit >= CaptionV2Controller.verbCascadeAll) return true;
    return count > 1 && limit >= count;
  }

  int get _shownOpen {
    if (_allOpen) return _categoryCount;
    final limit = controller.verbCascadeLimit;
    if (limit < 1) return 1;
    return limit;
  }

  String get _openHint {
    if (_allOpen) return 'Categories stay open';
    if (_shownOpen <= 1) return 'One at a time';
    return 'Oldest closes after $_shownOpen';
  }

  bool get _isDefault =>
      controller.verbCascadeLimit == 1 && !controller.verbListAll;

  void _fewerCategories() {
    if (_allOpen) {
      final previous = _categoryCount - 1;
      controller.setVerbCascadeLimit(previous < 1 ? 1 : previous);
      return;
    }
    if (_shownOpen <= 1) return;
    controller.setVerbCascadeLimit(_shownOpen - 1);
  }

  void _moreCategories() {
    if (_allOpen) return;
    final next = _shownOpen + 1;
    controller.setVerbCascadeLimit(
      next >= _categoryCount ? CaptionV2Controller.verbCascadeAll : next,
    );
  }

  Future<void> _reset() async {
    await controller.setVerbListAll(false);
    await controller.setVerbCascadeLimit(1);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final atOpenMin = !_allOpen && _shownOpen <= 1;
        final atOpenMax = _allOpen;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: FfTokens.nocturneEl,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            boxShadow: [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
              BoxShadow(
                color: FfTokens.nocturneLn,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Text(
                    'VERB PANEL',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.88,
                      color: FfTokens.nocturneT3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                _VerbSettingRow(
                  name: 'Organization',
                  hint: controller.verbListAll
                      ? 'Alphabetical'
                      : 'By category',
                  child: _VerbOrgSegments(
                    listAll: controller.verbListAll,
                    onChanged: controller.setVerbListAll,
                  ),
                ),
                if (!controller.verbListAll) ...[
                const SizedBox(height: 2),
                _VerbSettingRow(
                  name: 'Open categories',
                  hint: _openHint,
                  child: _VerbStepper(
                    atMin: atOpenMin,
                    atMax: atOpenMax,
                    onMinus: _fewerCategories,
                    onPlus: _moreCategories,
                    minus: const PhosphorIcon(
                      PhosphorIconsRegular.minus,
                      size: 15,
                    ),
                    plus: const PhosphorIcon(
                      PhosphorIconsRegular.plus,
                      size: 15,
                    ),
                    value: Text(
                      _allOpen ? 'All' : '$_shownOpen',
                      style: _stepValueStyle,
                    ),
                  ),
                ),
                ],
                if (!_isDefault) ...[
                  const SizedBox(height: 2),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: FfTokens.nocturneLn),
                      child: SizedBox(height: 1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ResetVerbSettings(onTap: _reset),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

const _stepValueStyle = TextStyle(
  fontFamily: FfTokens.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: FfTokens.nocturneTx,
  decoration: TextDecoration.none,
  fontFeatures: [FontFeature.tabularFigures()],
);

class _VerbOrgSegments extends StatelessWidget {
  const _VerbOrgSegments({
    required this.listAll,
    required this.onChanged,
  });

  final bool listAll;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FfTokens.nocturneBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: FfTokens.nocturneLn2),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VerbOrgSegment(
              label: 'Cascade',
              selected: !listAll,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _VerbOrgSegment(
              label: 'All',
              selected: listAll,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerbOrgSegment extends StatelessWidget {
  const _VerbOrgSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? FfTokens.nocturneHv : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? FfTokens.nocturneTx : FfTokens.nocturneT3,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _VerbSettingRow extends StatelessWidget {
  const _VerbSettingRow({
    required this.name,
    required this.hint,
    required this.child,
  });

  final String name;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FfTokens.nocturneTx,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: FfTokens.nocturneT3,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}

class _VerbStepper extends StatelessWidget {
  const _VerbStepper({
    required this.atMin,
    required this.atMax,
    required this.onMinus,
    required this.onPlus,
    required this.minus,
    required this.plus,
    required this.value,
  });

  final bool atMin;
  final bool atMax;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final Widget minus;
  final Widget plus;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(enabled: !atMin, onTap: onMinus, child: minus),
            const SizedBox(width: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Center(child: value),
            ),
            const SizedBox(width: 2),
            _StepButton(enabled: !atMax, onTap: onPlus, child: plus),
          ],
        ),
      ),
    );
  }
}

/// Same bare minus and plus as the roster square-size control.
class _HeaderStepButton extends StatelessWidget {
  const _HeaderStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      hitTestBehavior: HitTestBehavior.opaque,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: enabled ? (_) => onTap() : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.3,
          child: SizedBox(
            width: 14,
            height: 22,
            child: Icon(icon, size: 12, color: FfTokens.nocturneT2),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hot = _hovered && widget.enabled;
    final color = hot ? FfTokens.nocturneTx : FfTokens.nocturneT2;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.3,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hot ? FfTokens.nocturneHv : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: IconTheme(
              data: IconThemeData(color: color, size: 15),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  color: color,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetVerbSettings extends StatefulWidget {
  const _ResetVerbSettings({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ResetVerbSettings> createState() => _ResetVerbSettingsState();
}

class _ResetVerbSettingsState extends State<_ResetVerbSettings> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: _hovered ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.arrowCounterClockwise,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                'Reset to default',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
        fontSize: DefaultVerbAccordion.verbFontSize *
                controller.verbFontScale +
            1,
        tokens: tokens,
        onTap: onOpen,
        gold: category == 'Favorites',
        trailing: VerbCategoryDragHandle(
          category: category,
          color: tokens.textSecondary,
        ),
      ),
    );
    if (!open || (category == 'All' && verbs.isEmpty)) {
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

class _AllVerbsTitle extends StatelessWidget {
  const _AllVerbsTitle({required this.tokens});

  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DefaultVerbAccordion.headerH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Text(
        'All verbs',
        style: FfTokens.categoryLabel(color: tokens.text),
      ),
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
          const SizedBox(width: 8),
          Expanded(
            child: hasVerb
                ? CmdClick(
                    onTap: () => controller.toggleVerbPin(verb!.key),
                    onCmdTap: () => controller.toggleVerbPin(verb!.key),
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
    required this.fontSize,
    required this.tokens,
    required this.onTap,
    this.gold = false,
    this.trailing,
  });

  final String label;
  final bool open;
  final double height;
  final double fontSize;
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
        ? FfTokens.favoritesLight
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
                    gold ? FfTokens.favoritesVerb : t.accent,
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
                  style: FfTokens.categoryLabel(color: labelColor).copyWith(
                    fontSize: widget.fontSize,
                  ),
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
              gold: category == 'Favorites',
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
              gold: category == 'Favorites',
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
                  gold: category == 'Favorites',
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
                  gold: category == 'Favorites',
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
    this.gold = false,
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final int index;
  final double rowHeight;
  final FfTokens tokens;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;
  final bool showDragHandle;
  final bool gold;

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
                          color: widget.gold ? FfTokens.favoritesVerb : tokens.text,
                          selected: armed,
                        ).copyWith(
                          fontSize: DefaultVerbAccordion.verbFontSize *
                              controller.verbFontScale,
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

    final extras = armed && (showRbi || showBase || showCelebration)
        ? VerbExtrasPanel(
            controller: controller,
            verbKey: verb.key,
            showRbi: showRbi,
            showBase: showBase,
            showCelebration: showCelebration,
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

/// Nested RUNNERS ON / BASE / REACTION panel under an armed verb.
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
    this.embedded = false,
  });

  final CaptionV2Controller controller;
  final String verbKey;
  final bool showRbi;
  final bool showBase;
  final bool showCelebration;
  final FfTokens tokens;

  /// Drawn inside the selected verb border, without a second card.
  final bool embedded;

  bool get _hasOptionRows => showRbi || showBase || showCelebration;

  @override
  Widget build(BuildContext context) {
    final homeRun = verbKey == 'Home Run';
    final reactionChips = controller.reactionOptionsFor(verbKey);
    final celebrationTypes = controller.celebrationTypeOptionsFor(verbKey);
    if (!_hasOptionRows) {
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
