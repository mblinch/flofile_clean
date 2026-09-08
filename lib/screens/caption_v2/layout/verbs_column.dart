import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_sub_options.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/full_verb_edit_dialog.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/rbi_row.dart';
import '../widgets/verb_tile.dart';
import 'roster_column.dart';

/// Verbs column with cascaded category headers and inline RBI controls.
class VerbsColumn extends StatefulWidget {
  const VerbsColumn({
    super.key,
    required this.controller,
    required this.focused,
  });

  final CaptionV2Controller controller;
  final bool focused;

  @override
  State<VerbsColumn> createState() => _VerbsColumnState();
}

class _VerbsColumnState extends State<VerbsColumn> {
  final _columnFocusNode = FocusNode(debugLabel: 'Verbs column');
  final _customVerbFocusNode = FocusNode(debugLabel: 'Custom verb');
  final _customVerbController = TextEditingController();
  final _categoryFocusNodes = List.generate(
    12,
    (i) => FocusNode(debugLabel: 'Verb category $i'),
  );
  String? _expandedCategory;
  String? _lastControllerCategory;

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
    _expandedCategory = controller.verbCategory;
    _lastControllerCategory = controller.verbCategory;
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_customVerbFocusNode.hasFocus) return KeyEventResult.ignored;

    final digit = _digitForKey(event.logicalKey);
    final keyboard = HardwareKeyboard.instance;
    if (digit != null &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed) {
      if (_expandedCategory == null) return KeyEventResult.handled;
      final verbs = controller.verbsInCategory;
      if (digit <= verbs.length) controller.selectVerb(verbs[digit - 1]);
      return KeyEventResult.handled;
    }

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
      _moveCategory(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveCategory(1);
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

  void _moveVerbSelection(int delta) {
    if (_expandedCategory == null) return;
    final verbs = controller.verbsInCategory;
    if (verbs.isEmpty) return;

    final current = verbs.indexOf(controller.selectedVerb ?? '');
    final next = current < 0
        ? (delta > 0 ? 0 : verbs.length - 1)
        : (current + delta).clamp(0, verbs.length - 1);
    controller.selectVerb(verbs[next]);
  }

  void _moveCategory(int delta) {
    final categories = _categories;
    if (categories.isEmpty) return;

    final current = categories.indexOf(controller.verbCategory ?? '');
    final start = current < 0 ? 0 : current;
    final next = (start + delta + categories.length) % categories.length;
    _openCategory(categories[next], next);
  }

  void _selectCategory(String category, int index) {
    setState(() {
      _expandedCategory = _expandedCategory == category ? null : category;
    });
    _lastControllerCategory = category;
    controller.setVerbCategory(category);
    _categoryFocusNodes[index].requestFocus();
  }

  void _openCategory(String category, int index) {
    setState(() => _expandedCategory = category);
    _lastControllerCategory = category;
    controller.setVerbCategory(category);
    _categoryFocusNodes[index].requestFocus();
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
    if (controller.verbCategory != _lastControllerCategory) {
      _lastControllerCategory = controller.verbCategory;
      _expandedCategory = controller.verbCategory;
    }

    return Focus(
      focusNode: _columnFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerDown: (_) {
          _columnFocusNode.requestFocus();
          controller.setColumnFocus(1);
        },
        child: CaptionV2ColumnCard(
          focused: widget.focused,
          header: Text('VERBS', style: t.labelStyle),
          showHeader: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    2,
                    2,
                    2,
                    2,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = _expandedCategory == category;
                    return Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 1),
                      child: _CascadeCategory(
                        focusNode: _categoryFocusNodes[index],
                        number: index + 1,
                        label: _displayCategory(category),
                        selected: selected,
                        tokens: t,
                        onTap: () => _selectCategory(category, index),
                        child: selected
                            ? _VerbList(
                                controller: controller,
                                tokens: t,
                                onVerbTap: _columnFocusNode.requestFocus,
                                onEditVerb: _showVerbEditor,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
                child: _CustomVerbField(
                  textController: _customVerbController,
                  focusNode: _customVerbFocusNode,
                  tokens: t,
                  pinned: controller.customVerbPinned,
                  canUseLast: controller.lastCustomVerbPhrase.isNotEmpty,
                  onChanged: controller.setCustomVerbPhrase,
                  onTogglePin: controller.toggleCustomVerbPin,
                  onUseLast: controller.useLastCustomVerb,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
                child: _AddVerbButton(
                  tokens: t,
                  onTap: () {
                    final keys = controller.verbCatalog.byKey.keys;
                    final first = keys.isEmpty ? null : keys.first;
                    if (first != null) {
                      _showVerbEditor(first, createOnOpen: true);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayCategory(String category) {
    return category == 'Non Game-Action' ? 'Non game-action' : category;
  }
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
                        fontSize: 11.5,
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
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final VoidCallback onVerbTap;
  final ValueChanged<String> onEditVerb;

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
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final int index;
  final VoidCallback onVerbTap;
  final ValueChanged<String> onEditVerb;

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
    final showCelebration =
        selected && controller.verbNeedsCelebration(verb.key);
    return Column(
      children: [
        VerbTile(
          code: '${index + 1}',
          label: verb.label,
          selected: selected,
          pinned: controller.isVerbPinned(verb.key),
          favorite: verb.isFavorite,
          height: 26,
          onTap: () {
            onVerbTap();
            controller.selectVerb(verb.key);
          },
          onSecondaryTapDown: (details) => _showContextMenu(context, details),
        ),
        if (showRbi) ...[
          const SizedBox(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: RbiRow(
              value: controller.rbi,
              compact: true,
              homeRunStyle: verb.key == 'Home Run',
              onChanged: controller.setRbi,
            ),
          ),
        ],
        if (showCelebration) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _CelebrationRow(
              heading: VerbSubOptions.isHitVerb(verb.key)
                  ? 'REACTION'
                  : 'CELEBRATING',
              options: controller.celebrationOptionsFor(verb.key),
              selected: controller.celebrationType,
              onChanged: controller.setCelebrationType,
            ),
          ),
        ],
      ],
    );
  }
}

class _CelebrationRow extends StatelessWidget {
  const _CelebrationRow({
    required this.heading,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String heading;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(color: t.divider),
      ),
      child: Row(
        children: [
          Text(
            heading,
            style: t.microStyle.copyWith(fontSize: 8.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _CelebrationChip(
                      label: options[i],
                      selected: selected == options[i],
                      tokens: t,
                      onTap: () => onChanged(options[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CelebrationChip extends StatelessWidget {
  const _CelebrationChip({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tokens.selectedFill : tokens.badgeFill,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 23,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? tokens.accent : tokens.divider,
            ),
          ),
          child: Text(
            label,
            style: tokens.microStyle.copyWith(
              color: selected ? tokens.accent : tokens.textSecondary,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
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
