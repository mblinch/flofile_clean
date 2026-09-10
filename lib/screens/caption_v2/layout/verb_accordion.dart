import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/base_row.dart';
import '../widgets/rbi_row.dart';
import '../widgets/celebration_dropdown.dart';

/// Default no-scroll verb accordion (Favorites kept as a category).
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
  static const verbRowH = 22.0;
  static const laneHeaderH = 28.0;
  static const categoryFontSize = 15.0;
  static const verbFontSize = 12.0;
  static const verbHoverFontSize = 14.0;

  @override
  State<DefaultVerbAccordion> createState() => DefaultVerbAccordionState();
}

class DefaultVerbAccordionState extends State<DefaultVerbAccordion> {
  late String _openCategory;

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories {
    final available = controller.verbCategories;
    const preferred = [
      'Favorites',
      'Offense',
      'Running',
      'Defense',
      'Non Game-Action',
      'Reactions',
      'Pitching',
    ];
    final ordered = <String>[
      for (final name in preferred)
        if (available.contains(name)) name,
      for (final name in available)
        if (!preferred.contains(name)) name,
    ];
    return ordered;
  }

  List<EffectiveVerb> _verbsFor(String category) =>
      controller.verbDefinitionsByCategory[category] ?? const [];

  int get _favoriteCount =>
      controller.verbCatalog.favoriteKeys.length;

  int get _totalVerbCount {
    var total = 0;
    for (final category in _categories) {
      if (category == 'Favorites') continue;
      total += _verbsFor(category).length;
    }
    return total;
  }

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
    if (!categories.contains(_openCategory) && categories.isNotEmpty) {
      _openCategory = categories.contains('Offense')
          ? 'Offense'
          : categories.first;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: DefaultVerbAccordion.laneHeaderH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text(
                  'VERBS',
                  style: TextStyle(
                    fontFamily: FfTokens.labelFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: t.text.withValues(alpha: 0.70),
                  ),
                ),
                const Spacer(),
                Text(
                  '$_totalVerbCount · $_favoriteCount favourites',
                  style: TextStyle(
                    fontFamily: FfTokens.monoFamily,
                    fontSize: 10.5,
                    color: t.text.withValues(alpha: 0.44),
                  ),
                ),
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
              final worstOneUp =
                  headerTotal + openVerbs.length * verbRowH;
              if (worstOneUp > bodyH && bodyH > 0) {
                headerH = 28;
                verbRowH = 20;
              }

              final availableForVerbs =
                  (bodyH - categories.length * headerH).clamp(0.0, bodyH);
              final maxRowsOneUp = verbRowH <= 0
                  ? 0
                  : (availableForVerbs / verbRowH).floor();
              final twoUp = openVerbs.length > maxRowsOneUp &&
                  openVerbs.length > 1;

              assert(() {
                final fitted = twoUp
                    ? categories.length * headerH +
                        ((openVerbs.length + 1) ~/ 2) * verbRowH
                    : categories.length * headerH +
                        openVerbs.length * verbRowH;
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
                  for (final category in categories)
                    _AccordionSection(
                      category: category,
                      displayName: _displayName(category),
                      count: _verbsFor(category).length,
                      open: category == _openCategory,
                      headerH: headerH,
                      verbRowH: verbRowH,
                      verbs: category == _openCategory
                          ? openVerbs
                          : const <EffectiveVerb>[],
                      twoUp: category == _openCategory && twoUp,
                      tokens: t,
                      controller: controller,
                      onOpen: () => _open(category),
                      onEditVerb: widget.onEditVerb,
                      onVerbArmed: widget.onVerbArmed,
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

class _AccordionSection extends StatelessWidget {
  const _AccordionSection({
    required this.category,
    required this.displayName,
    required this.count,
    required this.open,
    required this.headerH,
    required this.verbRowH,
    required this.verbs,
    required this.twoUp,
    required this.tokens,
    required this.controller,
    required this.onOpen,
    required this.onEditVerb,
    this.onVerbArmed,
  });

  final String category;
  final String displayName;
  final int count;
  final bool open;
  final double headerH;
  final double verbRowH;
  final List<EffectiveVerb> verbs;
  final bool twoUp;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final VoidCallback onOpen;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryHeader(
          label: displayName,
          count: count,
          open: open,
          height: headerH,
          tokens: tokens,
          onTap: onOpen,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? _VerbBoard(
                  verbs: verbs,
                  rowHeight: verbRowH,
                  twoUp: twoUp,
                  tokens: tokens,
                  controller: controller,
                  onEditVerb: onEditVerb,
                  onVerbArmed: onVerbArmed,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CategoryHeader extends StatefulWidget {
  const _CategoryHeader({
    required this.label,
    required this.count,
    required this.open,
    required this.height,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool open;
  final double height;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_CategoryHeader> createState() => _CategoryHeaderState();
}

class _CategoryHeaderState extends State<_CategoryHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final open = widget.open;
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
            color: open
                ? t.accent.withValues(alpha: 0.13)
                : (_hovered
                    ? t.text.withValues(alpha: 0.06)
                    : Colors.transparent),
            border: Border(
              bottom: BorderSide(
                color: open
                    ? t.accent.withValues(alpha: 0.34)
                    : t.divider,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 11,
                color: open
                    ? t.accent
                    : t.text.withValues(alpha: 0.38),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: open
                        ? FfTokens.labelFamily
                        : FfTokens.fontFamily,
                    fontWeight: open ? FontWeight.w600 : FontWeight.w400,
                    fontSize: DefaultVerbAccordion.categoryFontSize,
                    letterSpacing: open ? -0.2 : 0,
                    color: open
                        ? t.accent
                        : t.text.withValues(alpha: 0.76),
                  ),
                ),
              ),
              Text(
                '${widget.count}',
                style: TextStyle(
                  fontFamily: FfTokens.monoFamily,
                  fontSize: 10,
                  color: open
                      ? t.accent
                      : t.text.withValues(alpha: 0.44),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerbBoard extends StatelessWidget {
  const _VerbBoard({
    required this.verbs,
    required this.rowHeight,
    required this.twoUp,
    required this.tokens,
    required this.controller,
    required this.onEditVerb,
    this.onVerbArmed,
  });

  final List<EffectiveVerb> verbs;
  final double rowHeight;
  final bool twoUp;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  @override
  Widget build(BuildContext context) {
    if (verbs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No verbs', style: tokens.metaStyle),
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
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final int index;
  final double rowHeight;
  final FfTokens tokens;
  final ValueChanged<String> onEditVerb;
  final VoidCallback? onVerbArmed;

  @override
  State<_AccordionVerbRow> createState() => _AccordionVerbRowState();
}

class _AccordionVerbRowState extends State<_AccordionVerbRow> {
  bool _hovered = false;

  CaptionV2Controller get controller => widget.controller;
  EffectiveVerb get verb => widget.verb;
  FfTokens get tokens => widget.tokens;

  Future<void> _contextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showMenu<String>(
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
          child: Text(verb.isFavorite ? 'Remove favorite' : 'Add favorite'),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(
            controller.isVerbPinned(verb.key)
                ? 'Unpin'
                : 'Pin for session',
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
    final showCelebration =
        armed && controller.verbNeedsCelebration(verb.key);
    final bright = armed || _hovered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: Material(
            color: armed
                ? tokens.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            child: InkWell(
              onTap: () {
                widget.onVerbArmed?.call();
                controller.selectVerb(verb.key);
              },
              onSecondaryTapDown: (details) => _contextMenu(context, details),
              child: Container(
                height: widget.rowHeight,
                padding: const EdgeInsets.only(left: 12, right: 10),
                decoration: BoxDecoration(
                  border: armed
                      ? Border.symmetric(
                          horizontal: BorderSide(
                            color: tokens.accent.withValues(alpha: 0.55),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontFamily: FfTokens.labelFamily,
                          fontSize: _hovered
                              ? DefaultVerbAccordion.verbHoverFontSize
                              : DefaultVerbAccordion.verbFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: bright ? -0.4 : 0,
                          color: bright
                              ? tokens.text
                              : tokens.text.withValues(alpha: 0.84),
                        ),
                        child: Text(
                          verb.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                ),
              ),
            ),
          ),
        ),
        if (showRbi || showBase || showCelebration)
          VerbExtrasPanel(
            controller: controller,
            verbKey: verb.key,
            showRbi: showRbi,
            showBase: showBase,
            showCelebration: showCelebration,
            tokens: tokens,
          ),
      ],
    );
  }
}

/// Nested RUNNERS ON / BASE / REACTION panel under an armed verb.
class VerbExtrasPanel extends StatelessWidget {
  const VerbExtrasPanel({
    super.key,
    required this.controller,
    required this.verbKey,
    required this.showRbi,
    required this.showBase,
    required this.showCelebration,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final String verbKey;
  final bool showRbi;
  final bool showBase;
  final bool showCelebration;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final homeRun = verbKey == 'Home Run';
    final reactionChips = controller.reactionOptionsFor(verbKey);
    final celebrationTypes = controller.celebrationTypeOptionsFor(verbKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 10, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        decoration: BoxDecoration(
          color: tokens.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.divider),
        ),
        child: Column(
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
        ),
      ),
    );
  }
}
