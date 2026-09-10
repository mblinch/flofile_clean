import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_sub_options.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/full_verb_edit_dialog.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/verb_tile.dart';
import 'roster_column.dart';
import 'verb_accordion.dart';

/// Verbs column with cascaded category headers and inline RBI controls.
class VerbsColumn extends StatefulWidget {
  const VerbsColumn({
    super.key,
    required this.controller,
    required this.focused,
    this.onDrumRequested,
    this.onInfiniteRequested,
  });

  final CaptionV2Controller controller;
  final bool focused;
  final VoidCallback? onDrumRequested;
  final VoidCallback? onInfiniteRequested;

  @override
  State<VerbsColumn> createState() => _VerbsColumnState();
}

class _VerbsColumnState extends State<VerbsColumn> {
  final _columnFocusNode = FocusNode(debugLabel: 'Verbs column');
  final _customVerbFocusNode = FocusNode(debugLabel: 'Custom verb');
  final _customVerbController = TextEditingController();
  final _accordionKey = GlobalKey<DefaultVerbAccordionState>();
  final _categoryFocusNodes = List.generate(
    12,
    (i) => FocusNode(debugLabel: 'Verb category $i'),
  );
  bool _wheelMode = false;

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories {
    return controller.verbCategories;
  }

  Future<void> _showVerbEditor(
    String initialVerb, {
    bool createOnOpen = false,
  }) async {
    final categories =
        _categories.where((category) => category != 'Favorites').toList();
    if (categories.isEmpty) return;
    final definitions = controller.verbDefinitionsByCategory;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => FullVerbEditDialog(
        initialVerb: initialVerb,
        createOnOpen: createOnOpen,
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
    );
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _customVerbController.text = controller.customVerbPhrase;
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _columnFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VerbsColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) {
      _columnFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _columnFocusNode.dispose();
    _customVerbFocusNode.dispose();
    _customVerbController.dispose();
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (controller.searchOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_customVerbFocusNode.hasFocus) return KeyEventResult.ignored;

    if (!_wheelMode) {
      final accordion = _accordionKey.currentState;
      if (accordion != null) {
        final handled = accordion.onKeyEvent(event);
        if (handled == KeyEventResult.handled) return handled;
      }
    }

    final digit = _digitForKey(event.logicalKey);
    final keyboard = HardwareKeyboard.instance;
    if (digit != null &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed) {
      final verbs = controller.verbsInCategory;
      if (digit <= verbs.length) controller.selectVerb(verbs[digit - 1]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  int? _digitForKey(LogicalKeyboardKey key) {
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = keys.indexOf(key);
    return index < 0 ? null : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final categories = _categories;
    if (!_customVerbFocusNode.hasFocus &&
        _customVerbController.text != controller.customVerbPhrase) {
      _customVerbController.value = TextEditingValue(
        text: controller.customVerbPhrase,
        selection: TextSelection.collapsed(
          offset: controller.customVerbPhrase.length,
        ),
      );
    }

    return Focus(
      focusNode: _columnFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerDown: (_) {
          if (controller.searchOpen) return;
          _columnFocusNode.requestFocus();
          controller.setColumnFocus(1);
        },
        child: CaptionV2ColumnCard(
          focused: widget.focused,
          header: Text('VERBS', style: t.labelStyle),
          showHeader: false,
          child: controller.searchOpen
              ? _FirebarVerbReference(
                  categories: categories,
                  controller: controller,
                  tokens: t,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 26,
                      child: Row(
                        children: [
                          const Spacer(),
                          _VerbViewToggle(
                            wheelMode: _wheelMode,
                            tokens: t,
                            onInfinite: widget.onInfiniteRequested,
                            onChanged: (value) {
                              if (value && widget.onDrumRequested != null) {
                                widget.onDrumRequested!();
                                return;
                              }
                              setState(() {
                                if (value && _wheelMode) {
                                  _wheelMode = false;
                                } else {
                                  _wheelMode = value;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: t.divider),
                    Expanded(
                      child: _wheelMode
                          ? _VerbWheel(controller: controller, tokens: t)
                          : ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) => DefaultVerbAccordion(
                                key: _accordionKey,
                                controller: controller,
                                onEditVerb: _showVerbEditor,
                                onVerbArmed: _columnFocusNode.requestFocus,
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VerbRailItem extends StatefulWidget {
  const _VerbRailItem({
    required this.focusNode,
    required this.category,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final FocusNode focusNode;
  final String category;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_VerbRailItem> createState() => _VerbRailItemState();
}

class _VerbRailItemState extends State<_VerbRailItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final display = widget.category == 'Non Game-Action'
        ? 'Non game-action'
        : widget.category;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('verb-rail-${widget.category}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? widget.tokens.accent.withValues(alpha: 0.18)
                  : (_hovered
                      ? widget.tokens.text.withValues(alpha: 0.06)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: widget.selected
                  ? Border.all(
                      color: widget.tokens.accent.withValues(alpha: 0.50),
                    )
                  : null,
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: widget.tokens.accent,
                        spreadRadius: FfTokens.focusOutlineOffset,
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              display,
              softWrap: true,
              style: widget.tokens.labelStyle.copyWith(
                fontSize: 14,
                height: 1.15,
                fontWeight: widget.selected
                    ? FfTokens.weightMedium
                    : FfTokens.weightRegular,
                color: widget.selected
                    ? widget.tokens.text
                    : widget.tokens.text.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerbViewToggle extends StatelessWidget {
  const _VerbViewToggle({
    required this.wheelMode,
    required this.tokens,
    required this.onChanged,
    this.onInfinite,
  });

  final bool wheelMode;
  final FfTokens tokens;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onInfinite;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required bool wheel,
      required IconData icon,
      required String tooltip,
    }) {
      final selected = wheelMode == wheel;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: ValueKey(wheel ? 'verb-wheel-toggle' : 'verb-classic-toggle'),
          onTap: () => onChanged(wheel),
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 28,
            height: 26,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(height: 1),
                Container(
                  width: 14,
                  height: 1.5,
                  color: selected ? tokens.accent : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'View Options',
          style: tokens.metaStyle.copyWith(
            fontSize: 11,
            height: 1,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        button(
          wheel: true,
          icon: Icons.swap_vert,
          tooltip: 'Default',
        ),
        if (onInfinite != null)
          Tooltip(
            message: 'Drum wheel',
            child: InkWell(
              key: const ValueKey('verb-infinite-toggle'),
              onTap: onInfinite,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 28,
                height: 26,
                child: Icon(
                  Icons.all_inclusive,
                  size: 18,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VerbWheel extends StatefulWidget {
  const _VerbWheel({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  State<_VerbWheel> createState() => _VerbWheelState();
}

class _VerbWheelState extends State<_VerbWheel> {
  static const _itemExtent = 42.0;

  late final FixedExtentScrollController _scrollController;
  late String _category;
  late int _centerIndex;

  List<String> get _categories => widget.controller.verbCategories
      .where(
        (category) => (widget.controller.verbDefinitionsByCategory[category] ??
                const <EffectiveVerb>[])
            .isNotEmpty,
      )
      .toList();

  List<EffectiveVerb> get _verbs {
    return widget.controller.verbDefinitionsByCategory[_category] ??
        const <EffectiveVerb>[];
  }

  @override
  void initState() {
    super.initState();
    final categories = _categories;
    _category = categories.contains(widget.controller.verbCategory)
        ? widget.controller.verbCategory!
        : categories.first;
    final verbs = _verbs;
    final selected =
        verbs.indexWhere((verb) => verb.key == widget.controller.selectedVerb);
    _centerIndex = selected < 0 ? 0 : selected;
    _scrollController = FixedExtentScrollController(initialItem: _centerIndex);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final verbs = _verbs;
    if (verbs.isEmpty) {
      return Center(
        child: Text('No verbs', style: widget.tokens.metaStyle),
      );
    }
    return Column(
      children: [
        Container(
          height: 30,
          margin: const EdgeInsets.fromLTRB(2, 3, 2, 0),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.tokens.badgeFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: widget.tokens.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('verb-wheel-category'),
              value: _category,
              isExpanded: true,
              isDense: true,
              icon: Icon(
                Icons.expand_more,
                size: 16,
                color: widget.tokens.textSecondary,
              ),
              dropdownColor: widget.tokens.surface,
              style: widget.tokens.labelStyle.copyWith(
                color: widget.tokens.text,
                fontSize: 14,
              ),
              items: [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category,
                    child: Text(
                      category == 'Non Game-Action'
                          ? 'Non game-action'
                          : category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (category) {
                if (category == null || category == _category) return;
                setState(() {
                  _category = category;
                  _centerIndex = 0;
                });
                widget.controller.setVerbCategory(category);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scrollController.hasClients) {
                    _scrollController.jumpToItem(0);
                  }
                });
              },
            ),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  behavior: const _VerbWheelScrollBehavior(),
                  child: ListWheelScrollView.useDelegate(
                    key: const ValueKey('verb-wheel'),
                    controller: _scrollController,
                    itemExtent: _itemExtent,
                    diameterRatio: 1.8,
                    perspective: 0.002,
                    physics: const FixedExtentScrollPhysics(),
                    overAndUnderCenterOpacity: 0.48,
                    useMagnifier: true,
                    magnification: 1.3,
                    onSelectedItemChanged: (index) {
                      setState(() => _centerIndex = index);
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: verbs.length,
                      builder: (context, index) {
                        final verb = verbs[index];
                        final centered = index == _centerIndex;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              if (!centered) {
                                await _scrollController.animateToItem(
                                  index,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              if (!mounted) return;
                              widget.controller.selectVerb(verb.key);
                            },
                            child: Center(
                              child: Text(
                                verb.label,
                                maxLines: 1,
                                style: widget.tokens.metaStyle.copyWith(
                                  color: centered
                                      ? widget.tokens.text
                                      : widget.tokens.textSecondary,
                                  fontSize: centered ? 14 : 12,
                                  fontWeight: centered
                                      ? FfTokens.weightMedium
                                      : FfTokens.weightRegular,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  height: _itemExtent,
                  decoration: BoxDecoration(
                    color: widget.tokens.selectedFill.withValues(alpha: 0.45),
                    border: Border.symmetric(
                      horizontal:
                          BorderSide(color: widget.tokens.selectedBorder),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerbWheelScrollBehavior extends MaterialScrollBehavior {
  const _VerbWheelScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _FirebarVerbReference extends StatefulWidget {
  const _FirebarVerbReference({
    required this.categories,
    required this.controller,
    required this.tokens,
  });

  final List<String> categories;
  final CaptionV2Controller controller;
  final FfTokens tokens;

  @override
  State<_FirebarVerbReference> createState() => _FirebarVerbReferenceState();
}

class _FirebarVerbReferenceState extends State<_FirebarVerbReference> {
  final _scrollController = ScrollController();
  String? _lastSelectedKey;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = widget.tokens;
    final matches = controller.firebarVerbResults;
    final matchKeys = matches.map((result) => result.verbKey).toSet();
    final entries = <_FirebarVerbEntry>[];
    for (final category in widget.categories) {
      if (category == 'Favorites') continue;
      final verbs = (controller.verbDefinitionsByCategory[category] ??
              const <EffectiveVerb>[])
          .where((verb) => matchKeys.contains(verb.key))
          .toList();
      if (verbs.isEmpty) continue;
      entries.add(_FirebarVerbEntry.heading(category));
      entries.addAll(verbs.map(_FirebarVerbEntry.verb));
    }
    final selected = controller.firebarSelectedResult;
    if (selected?.kind == FirebarResultKind.verb &&
        selected?.key != _lastSelectedKey) {
      _lastSelectedKey = selected!.key;
      var selectedOffset = 0.0;
      for (final entry in entries) {
        if (entry.verb?.key == selected.verbKey) break;
        selectedOffset += entry.verb == null ? 24 : 26;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            selectedOffset.clamp(
              0,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Semantics(
      label: 'Verb shortcut reference',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 27,
            child: Row(
              children: [
                const Spacer(),
                Text(
                  controller.searchQuery.trim().isEmpty
                      ? '${controller.firebarVerbTotal}'
                      : '${matches.length} / ${controller.firebarVerbTotal}',
                  style: tokens.monoMetaStyle,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.divider),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'No match',
                      style: tokens.metaStyle.copyWith(
                        color: tokens.text.withValues(alpha: 0.34),
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('firebar-verb-reference'),
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 2),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      if (entry.verb == null) {
                        final category = entry.category!;
                        return Container(
                          height: 24,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            category == 'Non Game-Action'
                                ? 'NON GAME-ACTION'
                                : category.toUpperCase(),
                            style: tokens.microStyle.copyWith(fontSize: 10),
                          ),
                        );
                      }
                      final verb = entry.verb!;
                      final result = matches.firstWhere(
                        (candidate) => candidate.verbKey == verb.key,
                      );
                      return VerbTile(
                        code: '',
                        label: verb.label,
                        selected: false,
                        firebarSelected: result.key == selected?.key,
                        highlightQuery: controller.searchQuery.trim(),
                        pinned: controller.isVerbPinned(verb.key),
                        height: 26,
                        onTap: () => controller.commitFirebarResult(result),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FirebarVerbEntry {
  const _FirebarVerbEntry.heading(this.category) : verb = null;
  const _FirebarVerbEntry.verb(this.verb) : category = null;

  final String? category;
  final EffectiveVerb? verb;
}

class _CascadeCategory extends StatefulWidget {
  const _CascadeCategory({
    required this.focusNode,
    required this.number,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
    this.child,
  });

  final FocusNode focusNode;
  final int number;
  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;
  final Widget? child;

  @override
  State<_CascadeCategory> createState() => _CascadeCategoryState();
}

class _CascadeCategoryState extends State<_CascadeCategory> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusableActionDetector(
          focusNode: widget.focusNode,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? t.accent.withValues(alpha: 0.18)
                      : (_hovered || _focused
                          ? t.text.withValues(alpha: 0.10)
                          : t.badgeFill),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${widget.number}',
                        style: t.monoMetaStyle.copyWith(
                          fontSize: 10,
                          color: t.text.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    Icon(
                      widget.selected ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: widget.selected
                          ? t.text
                          : t.text.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: t.labelStyle.copyWith(
                          fontSize: 14,
                          height: 1.15,
                          fontWeight: widget.selected
                              ? FfTokens.weightMedium
                              : FfTokens.weightRegular,
                          color: widget.selected
                              ? t.text
                              : t.text.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.child != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 1, 0, 0),
            child: widget.child!,
          ),
      ],
    );
  }
}

class _VerbList extends StatelessWidget {
  const _VerbList({
    required this.controller,
    required this.tokens,
    required this.onVerbTap,
    required this.onEditVerb,
    this.rowHeight = 26,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final VoidCallback onVerbTap;
  final ValueChanged<String> onEditVerb;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final verbs =
        controller.verbDefinitionsByCategory[controller.verbCategory] ??
            const <EffectiveVerb>[];
    if (verbs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: Text('No verbs', style: tokens.metaStyle)),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < verbs.length; i++) ...[
          if (i > 0) const SizedBox(height: 1),
          _VerbListItem(
            controller: controller,
            verb: verbs[i],
            index: i,
            onVerbTap: onVerbTap,
            onEditVerb: onEditVerb,
            rowHeight: rowHeight,
          ),
        ],
      ],
    );
  }
}

class _VerbListItem extends StatelessWidget {
  const _VerbListItem({
    required this.controller,
    required this.verb,
    required this.index,
    required this.onVerbTap,
    required this.onEditVerb,
    required this.rowHeight,
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final int index;
  final VoidCallback onVerbTap;
  final ValueChanged<String> onEditVerb;
  final double rowHeight;

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final controller = this.controller;
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
            value: 'pin',
            child: Text(controller.isVerbPinned(verb.key)
                ? 'Unpin'
                : 'Pin for session')),
        PopupMenuItem(
            value: 'favorite',
            child: Text(verb.isFavorite ? 'Remove favorite' : 'Add favorite')),
        const PopupMenuItem(value: 'edit', child: Text('Edit verb…')),
        if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
        if (index <
            (controller.verbDefinitionsByCategory[controller.verbCategory]
                        ?.length ??
                    0) -
                1)
          const PopupMenuItem(value: 'down', child: Text('Move down')),
        for (final category in controller.verbCategories)
          if (category != 'Favorites' && category != verb.category)
            PopupMenuItem(
              value: 'move:$category',
              child: Text('Move to ${_displayCategoryLabel(category)}'),
            ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete verb')),
      ],
    );
    if (action == null) return;
    switch (action) {
      case 'pin':
        controller.toggleVerbPin(verb.key);
        break;
      case 'favorite':
        await controller.toggleVerbFavorite(verb.key);
        break;
      case 'edit':
        onEditVerb(verb.key);
        break;
      case 'up':
        await controller.moveVerb(verb.key, verb.category, index - 1);
        break;
      case 'down':
        await controller.moveVerb(verb.key, verb.category, index + 1);
        break;
      case 'delete':
        await controller.deleteVerb(verb.key);
        break;
      default:
        if (action.startsWith('move:')) {
          await controller.moveVerb(
            verb.key,
            action.substring('move:'.length),
            9999,
          );
        }
    }
  }

  String _displayCategoryLabel(String category) =>
      category == 'Non Game-Action' ? 'Non game-action' : category;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedVerb == verb.key;
    final showRbi = selected && controller.verbNeedsRbi(verb.key);
    final showBase = selected && controller.verbNeedsBase(verb.key);
    final showCelebration =
        selected && controller.verbNeedsCelebration(verb.key);
    return Column(
      children: [
        VerbTile(
          code: '${index + 1}',
          label: verb.label,
          selected: selected,
          pinned: controller.isVerbPinned(verb.key),
          height: rowHeight,
          onTap: () {
            onVerbTap();
            controller.selectVerb(verb.key);
          },
          onSecondaryTapDown: (details) => _showContextMenu(context, details),
        ),
        if (showRbi || showBase || showCelebration)
          VerbExtrasPanel(
            controller: controller,
            verbKey: verb.key,
            showRbi: showRbi,
            showBase: showBase,
            showCelebration: showCelebration,
            tokens: Theme.of(context).extension<FfTokens>() ?? FfTokens.dark,
          ),
      ],
    );
  }
}

class _AddVerbButton extends StatelessWidget {
  const _AddVerbButton({required this.tokens, required this.onTap});

  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedRRectPainter(color: tokens.accent),
          child: SizedBox(
            height: 28,
            width: double.infinity,
            child: Center(
              child: Text(
                '+ Verb',
                style: tokens.labelStyle.copyWith(
                  fontSize: 11.5,
                  color: tokens.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomVerbField extends StatelessWidget {
  const _CustomVerbField({
    required this.textController,
    required this.focusNode,
    required this.tokens,
    required this.pinned,
    required this.canUseLast,
    required this.onChanged,
    required this.onTogglePin,
    required this.onUseLast,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final FfTokens tokens;
  final bool pinned;
  final bool canUseLast;
  final ValueChanged<String> onChanged;
  final VoidCallback onTogglePin;
  final VoidCallback onUseLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: tokens.badgeFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: pinned ? tokens.accent : tokens.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              readOnly: pinned,
              onChanged: onChanged,
              style: tokens.labelStyle.copyWith(
                fontSize: 11.5,
                color: tokens.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Custom verb',
                hintStyle: tokens.labelStyle.copyWith(
                  fontSize: 11.5,
                  color: tokens.textSecondary,
                ),
                contentPadding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                border: InputBorder.none,
              ),
            ),
          ),
          _CustomVerbAction(
            icon: Icons.history,
            tooltip: 'Use last custom verb',
            tokens: tokens,
            enabled: canUseLast,
            onTap: onUseLast,
          ),
          _CustomVerbAction(
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: pinned ? 'Unpin custom verb' : 'Pin custom verb',
            tokens: tokens,
            enabled: textController.text.trim().isNotEmpty,
            selected: pinned,
            onTap: onTogglePin,
          ),
        ],
      ),
    );
  }
}

class _CustomVerbAction extends StatelessWidget {
  const _CustomVerbAction({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.enabled,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final FfTokens tokens;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 25,
          height: 28,
          child: Icon(
            icon,
            size: 14,
            color: enabled
                ? (selected ? tokens.accent : tokens.textSecondary)
                : tokens.divider,
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(8),
        ),
      );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + 4),
          paint,
        );
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
