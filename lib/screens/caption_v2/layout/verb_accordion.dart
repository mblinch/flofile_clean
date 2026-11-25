import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_sort_mode.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/aa_text_size_control.dart';
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

/// Starting letter for alphabetical verb banding (A–Z, else #).
String verbListInitial(EffectiveVerb verb) {
  final label = verb.label.trim();
  if (label.isEmpty) return '#';
  final ch = label[0].toUpperCase();
  if (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) return ch;
  return '#';
}

/// Label a verb band from the initials actually in it, e.g. "A" or "M–P".
String verbLetterRangeLabel(List<EffectiveVerb> group) {
  if (group.isEmpty) return '';
  final first = verbListInitial(group.first);
  var last = first;
  for (final verb in group) {
    last = verbListInitial(verb);
  }
  if (first == last) return first;
  return '$first–$last';
}

/// Groups an alphabetically sorted verb list into letter bands.
///
/// Same idea as the player number roster's "29–45" row labels: each band gets
/// a compact range header from the initials it contains.
List<(String, List<EffectiveVerb>)> verbLetterBands(List<EffectiveVerb> verbs) {
  if (verbs.isEmpty) return const [];
  final bands = <(String, List<EffectiveVerb>)>[];
  String? currentLetter;
  var current = <EffectiveVerb>[];
  for (final verb in verbs) {
    final letter = verbListInitial(verb);
    if (currentLetter == null || letter != currentLetter) {
      if (current.isNotEmpty && currentLetter != null) {
        bands.add((verbLetterRangeLabel(current), List.of(current)));
      }
      currentLetter = letter;
      current = [verb];
    } else {
      current.add(verb);
    }
  }
  if (current.isNotEmpty) {
    bands.add((verbLetterRangeLabel(current), current));
  }
  return bands;
}

/// Packs letter bands into [columnCount] columns, reading down the left then
/// the right — groups stay intact (CSS `break-inside: avoid`).
List<List<(String, List<EffectiveVerb>)>> verbLetterBandColumns(
  List<(String, List<EffectiveVerb>)> bands, {
  int columnCount = 2,
}) {
  if (bands.isEmpty) return const [];
  if (columnCount <= 1) return [bands];
  final total = bands.fold<int>(0, (n, band) => n + band.$2.length);
  final target = (total + 1) ~/ 2;
  final left = <(String, List<EffectiveVerb>)>[];
  final right = <(String, List<EffectiveVerb>)>[];
  var leftCount = 0;
  var fillLeft = true;
  for (final band in bands) {
    if (fillLeft && (left.isEmpty || leftCount < target)) {
      left.add(band);
      leftCount += band.$2.length;
      if (leftCount >= target) fillLeft = false;
    } else {
      right.add(band);
    }
  }
  if (right.isEmpty) return [left];
  return [left, right];
}

/// Fixed-width letter glyph on the first verb of an A–Z band (empty for the rest).
class VerbBandLetter extends StatelessWidget {
  const VerbBandLetter({
    super.key,
    required this.letter,
    required this.tokens,
  });

  /// Null hides the lane. Empty string reserves the lane with no glyph.
  final String? letter;
  final FfTokens tokens;

  static const double width = 12;

  @override
  Widget build(BuildContext context) {
    if (letter == null) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: letter!.isEmpty
          ? null
          : Text(
              letter!,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: FfTokens.nocturneT3,
                height: 1,
              ),
            ),
    );
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
  static const verbRowH = 18.0;
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
  final _bodyKey = GlobalKey(debugLabel: 'DefaultVerbAccordion body');

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

  /// Largest font step whose open category still fits the body height.
  Future<void> fitToBox() async {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final bodyH = box.size.height;
    if (bodyH <= 0) return;

    final categories = _categories;
    final openVerbs = _verbsFor(_openCategory);
    final pinnedH = DefaultVerbAccordion.pinnedBarH;

    double contentHeight(int step) {
      final scale = 1 +
          step *
              (CaptionV2Controller.verbFontStepPx /
                  CaptionV2Controller.verbFontBasePx);
      var headerH = DefaultVerbAccordion.headerH * scale;
      var verbRowH = DefaultVerbAccordion.verbRowH * scale;
      final worstOneUp =
          headerH * categories.length + openVerbs.length * verbRowH;
      if (worstOneUp > bodyH) {
        headerH = 28 * scale;
        verbRowH = DefaultVerbAccordion.verbRowH * scale;
      }
      final availableForVerbs =
          (bodyH - categories.length * headerH - pinnedH).clamp(0.0, bodyH);
      final maxRowsOneUp =
          verbRowH <= 0 ? 0 : (availableForVerbs / verbRowH).floor();
      final twoUp = openVerbs.length > maxRowsOneUp && openVerbs.length > 1;
      if (controller.verbListAll) {
        return pinnedH + openVerbs.length * verbRowH;
      }
      if (twoUp) {
        return categories.length * headerH +
            pinnedH +
            ((openVerbs.length + 1) ~/ 2) * verbRowH;
      }
      return categories.length * headerH +
          pinnedH +
          openVerbs.length * verbRowH;
    }

    var best = CaptionV2Controller.verbFontStepMin;
    for (var step = CaptionV2Controller.verbFontStepMax;
        step >= CaptionV2Controller.verbFontStepMin;
        step--) {
      if (contentHeight(step) <= bodyH + 2) {
        best = step;
        break;
      }
    }
    await controller.setVerbFontStep(best);
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
                VerbMenuTools(
                  controller: controller,
                  tokens: t,
                  onFit: () {
                    fitToBox();
                  },
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: t.divider),
        Expanded(
          key: _bodyKey,
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
                verbRowH = DefaultVerbAccordion.verbRowH * controller.verbFontScale;
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
    this.onFit,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  /// Fit verbs to the on-screen box (Index or A–Z list).
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VerbTextSizeControl(controller: controller, onFit: onFit),
        const SizedBox(width: 4),
        _VerbCascadeLimitMenu(controller: controller),
      ],
    );
  }
}

/// Compact small-A / big-A for verb text size, shown beside the gear.
class _VerbTextSizeControl extends StatelessWidget {
  const _VerbTextSizeControl({required this.controller, this.onFit});

  final CaptionV2Controller controller;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.verbListAll) {
          final step = controller.verbFontStep;
          return AaTextSizeControl(
            height: 24,
            canSmaller: step > CaptionV2Controller.verbFontStepMin,
            canLarger: step < CaptionV2Controller.verbFontStepMax,
            onSmaller: () => controller.nudgeVerbFont(-1),
            onLarger: () => controller.nudgeVerbFont(1),
            onFit: onFit,
          );
        }
        final step = controller.verbIndexFontStep.clamp(0, 2);
        return AaTextSizeControl(
          height: 24,
          canSmaller: step > 0,
          canLarger: step < 2,
          onSmaller: () => controller.nudgeVerbIndexFont(-1),
          onLarger: () => controller.nudgeVerbIndexFont(1),
          onFit: onFit,
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
  static const _menuWidth = 272.0;

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
    const gap = 8.0;
    // Prefer opening to the right of the gear so the popover doesn't cover
    // the verb list. Fall back to the left when the window is too tight.
    final rightLeft = origin.dx + box.size.width + gap;
    final leftLeft = origin.dx - gap - _menuWidth;
    final maxLeft = overlayBox.size.width - 8 - _menuWidth;
    final opensRight = rightLeft <= maxLeft;
    final left = (opensRight ? rightLeft : leftLeft)
        .clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft);
    final top = origin.dy;

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
              delegate: _VerbGearMenuBeside(
                top: top,
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
                  child: _VerbSettingsCard(
                    controller: widget.controller,
                    caretOnLeft: opensRight,
                  ),
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
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.gearSix,
            size: 14,
            color: active ? FfTokens.nocturneTx : FfTokens.nocturneT2,
          ),
        ),
      ),
    );
  }
}

class _VerbGearMenuBeside extends SingleChildLayoutDelegate {
  _VerbGearMenuBeside({
    required this.top,
    required this.left,
    required this.width,
  });

  final double top;
  final double left;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxHeight =
        (constraints.maxHeight - 16).clamp(0.0, constraints.maxHeight);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight > 0 ? maxHeight : constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var y = top;
    final maxTop = size.height - 8 - childSize.height;
    if (y > maxTop) y = maxTop < 8 ? 8.0 : maxTop;
    if (y < 8) y = 8;
    var x = left;
    final maxLeft = size.width - 8 - childSize.width;
    if (x > maxLeft) x = maxLeft < 8 ? 8.0 : maxLeft;
    if (x < 8) x = 8;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _VerbGearMenuBeside oldDelegate) {
    return top != oldDelegate.top ||
        left != oldDelegate.left ||
        width != oldDelegate.width;
  }
}

/// Verb Index / A–Z settings popover (gear menu). Spec: Verb Settings Menu.html
class _VerbSettingsCard extends StatelessWidget {
  const _VerbSettingsCard({
    required this.controller,
    this.caretOnLeft = false,
  });

  final CaptionV2Controller controller;

  /// When the menu opens to the right of the gear, point the caret left.
  final bool caretOnLeft;

  static const _densityNames = ['Compact', 'Cozy', 'Comfortable'];

  Future<void> _resetDefaults() async {
    await controller.setVerbListAll(false);
    await controller.setVerbIndexSortByCategory(false);
    await controller.setVerbIndexDensity(1);
    await controller.setVerbIndexShowHistory(true);
    await controller.setVerbIndexHistoryLimit(3);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final listAll = controller.verbListAll;
        final dens = controller.verbIndexDensity.clamp(0, 2);
        final historyOn = controller.verbIndexShowHistory;
        final historyN = controller.verbIndexHistoryLimit.clamp(1, 10);

        return Padding(
          // Leave room for the caret diamond on the open side.
          padding: EdgeInsets.only(
            top: caretOnLeft ? 0 : 5,
            left: caretOnLeft ? 5 : 0,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: FfTokens.nocturneSf,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x24E8EEF4), // ≈ .14
                      blurRadius: 0,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Color(0x8C000000), // .55
                      blurRadius: 44,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _VsSectionLabel('LIST'),
                      _VsRow(
                        label: 'Layout',
                        trailing: _VsSegmented(
                          children: [
                            _VsSegItem(
                              label: 'Index',
                              icon: PhosphorIconsRegular.rows,
                              selected: !listAll,
                              onTap: () => controller.setVerbListAll(false),
                            ),
                            _VsSegItem(
                              label: 'A–Z',
                              icon: PhosphorIconsRegular.list,
                              selected: listAll,
                              onTap: () => controller.setVerbListAll(true),
                            ),
                          ],
                        ),
                      ),
                      IgnorePointer(
                        ignoring: listAll,
                        child: Opacity(
                          opacity: listAll ? 0.4 : 1,
                          child: _VsRow(
                            label: 'Group by',
                            trailing: _VsSegmented(
                              children: [
                                _VsSegItem(
                                  label: 'Letter',
                                  selected:
                                      !controller.verbIndexSortByCategory,
                                  onTap: () => controller
                                      .setVerbIndexSortByCategory(false),
                                ),
                                _VsSegItem(
                                  label: 'Category',
                                  selected:
                                      controller.verbIndexSortByCategory,
                                  onTap: () => controller
                                      .setVerbIndexSortByCategory(true),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _VsRow(
                        label: 'Density',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _densityNames[dens],
                              style: const TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: FfTokens.nocturneT2,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _VsSegmented(
                              iconOnly: true,
                              children: [
                                for (var i = 0; i < 3; i++)
                                  _VsSegItem(
                                    tooltip: _densityNames[i],
                                    selected: dens == i,
                                    iconWidget: _DensityLinesIcon(lines: const [
                                      5,
                                      3,
                                      2,
                                    ][i]),
                                    onTap: () =>
                                        controller.setVerbIndexDensity(i),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const _VsDivider(),
                      const _VsSectionLabel('SHOW'),
                      _VsHistoryRow(
                        value: historyOn,
                        onChanged: controller.setVerbIndexShowHistory,
                      ),
                      ClipRect(
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          curve: const Cubic(0.2, 0.8, 0.2, 1),
                          alignment: Alignment.topCenter,
                          heightFactor: historyOn ? 1 : 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: historyOn ? 1 : 0,
                            child: _VsRow(
                              indent: true,
                              label: 'Verbs shown',
                              labelColor: FfTokens.nocturneT2,
                              labelWeight: FontWeight.w400,
                              labelSize: 12.5,
                              trailing: _VsStepper(
                                value: historyN,
                                onDelta: (d) => controller
                                    .setVerbIndexHistoryLimit(historyN + d),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const _VsDivider(),
                      _VsFooter(onReset: _resetDefaults),
                    ],
                  ),
                ),
              ),
              // Caret toward the gear: left edge when opened right, else top.
              Positioned(
                left: caretOnLeft ? -5 : null,
                right: caretOnLeft ? null : 10,
                top: caretOnLeft ? 10 : -5,
                child: Transform.rotate(
                  angle: 0.78539816339, // 45°
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: FfTokens.nocturneSf,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x24E8EEF4),
                          offset: caretOnLeft
                              ? const Offset(-1, 1)
                              : const Offset(-1, -1),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VsSectionLabel extends StatelessWidget {
  const _VsSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.84, // .08em ≈ 10.5 * 0.08
          color: FfTokens.nocturneT3,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _VsDivider extends StatelessWidget {
  const _VsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ColoredBox(
        color: Color(0x14E8EEF4),
        child: SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}

class _VsRow extends StatelessWidget {
  const _VsRow({
    required this.label,
    required this.trailing,
    this.indent = false,
    this.labelColor = FfTokens.nocturneTx,
    this.labelWeight = FontWeight.w500,
    this.labelSize = 13,
    this.subtext,
    this.onTap,
  });

  final String label;
  final Widget trailing;
  final bool indent;
  final Color labelColor;
  final FontWeight labelWeight;
  final double labelSize;
  final String? subtext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 20 : 8, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: labelSize,
                      fontWeight: labelWeight,
                      color: labelColor,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (subtext != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtext!,
                      style: const TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: FfTokens.nocturneT3,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return _VsHoverTap(
      onTap: onTap!,
      child: row,
    );
  }
}

class _VsHoverTap extends StatefulWidget {
  const _VsHoverTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_VsHoverTap> createState() => _VsHoverTapState();
}

class _VsHoverTapState extends State<_VsHoverTap> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: _hovered ? FfTokens.nocturneSunken : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _VsHistoryRow extends StatelessWidget {
  const _VsHistoryRow({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _VsRow(
      label: 'History',
      subtext: 'Recent verbs above the list',
      onTap: () => onChanged(!value),
      trailing: _VsSwitch(value: value, onChanged: onChanged),
    );
  }
}

class _VsSwitch extends StatelessWidget {
  const _VsSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 18,
        decoration: BoxDecoration(
          color: value ? FfTokens.nocturneAc : const Color(0xFF2F363C),
          borderRadius: BorderRadius.circular(9),
          boxShadow: value
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x1EE8EEF4), // .12
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.2, 0.8, 0.2, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: value ? Colors.white : FfTokens.nocturneT2,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VsSegItem {
  const _VsSegItem({
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
    this.iconWidget,
    this.tooltip,
  });

  final String? label;
  final IconData? icon;
  final Widget? iconWidget;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;
}

class _VsSegmented extends StatelessWidget {
  const _VsSegmented({
    required this.children,
    this.iconOnly = false,
  });

  final List<_VsSegItem> children;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151A1E),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14E8EEF4),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _VsSegButton(item: children[i], iconOnly: iconOnly),
            ],
          ],
        ),
      ),
    );
  }
}

class _VsSegButton extends StatefulWidget {
  const _VsSegButton({required this.item, required this.iconOnly});

  final _VsSegItem item;
  final bool iconOnly;

  @override
  State<_VsSegButton> createState() => _VsSegButtonState();
}

class _VsSegButtonState extends State<_VsSegButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = item.selected;
    final color = selected
        ? Colors.white
        : (_hovered ? FfTokens.nocturneTx : FfTokens.nocturneT2);
    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 24,
      width: widget.iconOnly ? 30 : null,
      padding: widget.iconOnly
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? FfTokens.nocturneAccentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: selected ? FfTokens.nocturneAccentEdge : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.iconWidget != null)
            IconTheme(
              data: IconThemeData(color: color, size: 14),
              child: item.iconWidget!,
            )
          else if (item.icon != null) ...[
            PhosphorIcon(item.icon!, size: 14, color: color),
            if (item.label != null) const SizedBox(width: 5),
          ],
          if (item.label != null)
            Text(
              item.label!,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
    if (item.tooltip != null) {
      child = Tooltip(
        message: item.tooltip!,
        waitDuration: const Duration(milliseconds: 400),
        child: child,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: item.onTap,
        child: child,
      ),
    );
  }
}

class _DensityLinesIcon extends StatelessWidget {
  const _DensityLinesIcon({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? FfTokens.nocturneT2;
    return CustomPaint(
      size: const Size(14, 14),
      painter: _DensityLinesPainter(lines: lines, color: color),
    );
  }
}

class _DensityLinesPainter extends CustomPainter {
  _DensityLinesPainter({required this.lines, required this.color});

  final int lines;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // Match design SVG: 11×1.6 bars, rx .8, x=1.5
    const barW = 11.0;
    const barH = 1.6;
    const x = 1.5;
    final List<double> ys;
    switch (lines) {
      case 5:
        ys = const [2.2, 4.6, 7.0, 9.4, 11.8];
        break;
      case 2:
        ys = const [3.0, 10.0];
        break;
      case 3:
      default:
        ys = const [2.5, 6.2, 9.9];
        break;
    }
    for (final y in ys) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barH),
        const Radius.circular(0.8),
      );
      canvas.drawRRect(rr, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DensityLinesPainter oldDelegate) =>
      lines != oldDelegate.lines || color != oldDelegate.color;
}

class _VsStepper extends StatelessWidget {
  const _VsStepper({
    required this.value,
    required this.onDelta,
  });

  final int value;
  final ValueChanged<int> onDelta;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151A1E),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14E8EEF4),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VsStepBtn(
              icon: PhosphorIconsBold.minus,
              onTap: value > 1 ? () => onDelta(-1) : null,
            ),
            SizedBox(
              width: 22,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: FfTokens.nocturneTx,
                  decoration: TextDecoration.none,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _VsStepBtn(
              icon: PhosphorIconsBold.plus,
              onTap: value < 10 ? () => onDelta(1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _VsStepBtn extends StatefulWidget {
  const _VsStepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_VsStepBtn> createState() => _VsStepBtnState();
}

class _VsStepBtnState extends State<_VsStepBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = !enabled
        ? FfTokens.nocturneT3.withValues(alpha: 0.45)
        : (_hovered ? Colors.white : FfTokens.nocturneT2);
    return MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 26,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled && _hovered
                ? FfTokens.nocturneSunken
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: PhosphorIcon(widget.icon, size: 12, color: color),
        ),
      ),
    );
  }
}

class _VsFooter extends StatefulWidget {
  const _VsFooter({required this.onReset});

  final Future<void> Function() onReset;

  @override
  State<_VsFooter> createState() => _VsFooterState();
}

class _VsFooterState extends State<_VsFooter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => widget.onReset(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hovered ? FfTokens.nocturneSunken : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Reset to defaults',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x1EE8EEF4)),
            ),
            child: const Text(
              'Esc',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: FfTokens.nocturneT3,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
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
      if (category == 'All') {
        final bands = verbLetterBands(verbs);
        var index = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final band in bands) ...[
              for (var i = 0; i < band.$2.length; i++)
                _AccordionVerbRow(
                  controller: controller,
                  verb: band.$2[i],
                  index: index++,
                  rowHeight: rowHeight,
                  gold: false,
                  tokens: tokens,
                  onEditVerb: onEditVerb,
                  onVerbArmed: onVerbArmed,
                  // Letter shares the first verb's row; later verbs keep the lane.
                  bandLetter: i == 0 ? band.$1 : '',
                ),
            ],
          ],
        );
      }
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
    this.bandLetter,
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
  /// Inline A–Z marker on the first verb of a letter band (`''` = empty lane).
  final String? bandLetter;

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
                    if (widget.bandLetter != null) ...[
                      VerbBandLetter(
                        letter: widget.bandLetter,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 4),
                    ],
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
                          height: 1.05,
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

    final leftPad = armed
        ? 8.0
        : (widget.bandLetter != null ? 8.0 : 12.0);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: armed ? 4 : 0,
        vertical: armed ? 2 : 0,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(leftPad, 0, armed ? 8 : 4, 0),
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
