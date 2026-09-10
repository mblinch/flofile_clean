import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/mlb_api_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/base_row.dart';
import '../widgets/celebration_dropdown.dart';
import '../widgets/rbi_row.dart';

enum DrumLane { home, verbs, away }

enum DrumPickerMode { scroll, infinite }

class DesktopDrumPicker extends StatefulWidget {
  const DesktopDrumPicker({
    super.key,
    required this.controller,
    this.mode = DrumPickerMode.scroll,
    this.onModeChanged,
    required this.onExit,
  });

  final CaptionV2Controller controller;
  final DrumPickerMode mode;
  final ValueChanged<DrumPickerMode>? onModeChanged;
  final VoidCallback onExit;

  @override
  State<DesktopDrumPicker> createState() => _DesktopDrumPickerState();
}

class _DesktopDrumPickerState extends State<DesktopDrumPicker> {
  DrumLane _armedLane = DrumLane.verbs;
  int _homeIndex = 0;
  int _verbIndex = 0;
  int _awayIndex = 0;
  String? _homeLetterFilter;
  String? _awayLetterFilter;
  bool _verbAccordionCollapsed = false;
  final _homeFilter = TextEditingController();
  final _awayFilter = TextEditingController();

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories {
    final categories = controller.verbCategories
        .where(
          (category) => (controller.verbDefinitionsByCategory[category] ??
                  const <EffectiveVerb>[])
              .isNotEmpty,
        )
        .toList();
    const order = {
      'favorites': -1,
      'offense': 0,
      'running': 1,
      'defense': 2,
      'nongameaction': 3,
      'nongame': 3,
      'reactions': 4,
      'pitching': 5,
    };
    int rank(String category) {
      final key = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
      return order[key] ?? order.length;
    }

    categories.sort((a, b) => rank(a).compareTo(rank(b)));
    return categories;
  }

  String get _category {
    final categories = _categories;
    if (categories.contains(controller.verbCategory)) {
      return controller.verbCategory!;
    }
    return categories.first;
  }

  List<EffectiveVerb> get _verbs => _verbsForCategory(_category);

  List<EffectiveVerb> _verbsForCategory(String category) {
    final verbs = controller.verbDefinitionsByCategory[category] ??
        const <EffectiveVerb>[];
    return [
      ...verbs.where((verb) => verb.isFavorite),
      ...verbs.where((verb) => !verb.isFavorite),
    ];
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _homeIndex = _selectedPlayerIndex(controller.homeRoster, true);
    _awayIndex = _selectedPlayerIndex(controller.awayRoster, false);
    _verbIndex = _selectedVerbIndex();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _homeFilter.dispose();
    _awayFilter.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
  }

  int _selectedPlayerIndex(List<Player> players, bool isHome) {
    final selected = controller.selectedPlayers.where(
      (row) => row.isHome == isHome,
    );
    if (selected.isEmpty) return 0;
    final player = selected.first.player;
    final index = players.indexWhere(
      (item) =>
          item.playerId == player.playerId &&
          item.fullName == player.fullName &&
          item.jerseyNumber == player.jerseyNumber,
    );
    return index < 0 ? 0 : index;
  }

  int _selectedVerbIndex() {
    final index =
        _verbs.indexWhere((verb) => verb.key == controller.selectedVerb);
    return index < 0 ? 0 : index;
  }

  void _selectCategory(String category) {
    if (category == _category) {
      setState(
        () => _verbAccordionCollapsed = !_verbAccordionCollapsed,
      );
      return;
    }
    controller.setVerbCategory(category);
    setState(() {
      _verbIndex = 0;
      _verbAccordionCollapsed = false;
    });
  }

  Future<void> _toggleVerbFavorite(String key) async {
    final selectedKey = _verbs.isEmpty
        ? null
        : _verbs[_verbIndex.clamp(0, _verbs.length - 1)].key;
    await controller.toggleVerbFavorite(key);
    if (!mounted) return;
    setState(() {
      if (selectedKey == null) {
        _verbIndex = 0;
      } else {
        final nextIndex = _verbs.indexWhere((verb) => verb.key == selectedKey);
        _verbIndex = nextIndex < 0 ? 0 : nextIndex;
      }
    });
  }

  int _indexFor(DrumLane lane) {
    switch (lane) {
      case DrumLane.home:
        return _homeIndex;
      case DrumLane.verbs:
        return _verbIndex;
      case DrumLane.away:
        return _awayIndex;
    }
  }

  int _lengthFor(DrumLane lane) {
    switch (lane) {
      case DrumLane.home:
        return controller.homeRoster.length;
      case DrumLane.verbs:
        return _verbs.length;
      case DrumLane.away:
        return controller.awayRoster.length;
    }
  }

  void _setIndex(DrumLane lane, int index) {
    setState(() {
      switch (lane) {
        case DrumLane.home:
          _homeIndex = index;
          break;
        case DrumLane.verbs:
          _verbIndex = index;
          break;
        case DrumLane.away:
          _awayIndex = index;
          break;
      }
    });
  }

  void _spin(DrumLane lane, int delta) {
    final length = _lengthFor(lane);
    if (length == 0) return;
    if (lane == DrumLane.verbs) {
      if (widget.mode == DrumPickerMode.infinite) {
        final next = (_verbIndex + delta).clamp(0, length - 1);
        if (next == _verbIndex) return;
        _setIndex(lane, next);
        return;
      }
      if (_verbAccordionCollapsed) {
        setState(() => _verbAccordionCollapsed = false);
      }
      final next = _verbIndex + delta;
      if (next >= 0 && next < length) {
        _setIndex(lane, next);
        return;
      }
      final categoryIndex = _categories.indexOf(_category);
      final nextCategoryIndex = categoryIndex + (delta.isNegative ? -1 : 1);
      if (nextCategoryIndex < 0 || nextCategoryIndex >= _categories.length) {
        return;
      }
      final nextCategory = _categories[nextCategoryIndex];
      final nextVerbs = _verbsForCategory(nextCategory);
      controller.setVerbCategory(nextCategory);
      setState(() {
        _verbIndex =
            delta.isNegative && nextVerbs.isNotEmpty ? nextVerbs.length - 1 : 0;
      });
      return;
    }

    final visible = _visiblePlayersFor(lane);
    if (visible.isEmpty) return;
    final roster = _rosterFor(lane);
    final current = roster[_indexFor(lane).clamp(0, roster.length - 1)];
    var visibleIndex = visible.indexWhere(
      (player) =>
          player.fullName == current.fullName &&
          player.jerseyNumber == current.jerseyNumber,
    );
    if (visibleIndex < 0) visibleIndex = 0;
    final nextVisible =
        (visibleIndex + delta).clamp(0, visible.length - 1);
    if (nextVisible == visibleIndex) return;
    final nextPlayer = visible[nextVisible];
    final nextIndex = roster.indexWhere(
      (player) =>
          player.fullName == nextPlayer.fullName &&
          player.jerseyNumber == nextPlayer.jerseyNumber,
    );
    if (nextIndex < 0 || nextIndex == _indexFor(lane)) return;
    _setIndex(lane, nextIndex);
  }

  List<Player> _rosterFor(DrumLane lane) =>
      lane == DrumLane.home ? controller.homeRoster : controller.awayRoster;

  TextEditingController _filterFor(DrumLane lane) =>
      lane == DrumLane.home ? _homeFilter : _awayFilter;

  List<Player> _visiblePlayersFor(DrumLane lane) {
    final roster = _rosterFor(lane);
    final query = _filterFor(lane).text;
    var visible = controller.filterAndRankPlayers(roster, query);
    final letter =
        lane == DrumLane.home ? _homeLetterFilter : _awayLetterFilter;
    if (widget.mode == DrumPickerMode.scroll && letter != null) {
      visible = [
        for (final player in visible)
          if (_surnameInitial(player) == letter) player,
      ];
    }
    return visible;
  }

  void _onRosterFilterChanged(DrumLane lane) {
    setState(() {
      if (_filterFor(lane).text.trim().isNotEmpty) {
        if (lane == DrumLane.home) {
          _homeLetterFilter = null;
        } else {
          _awayLetterFilter = null;
        }
      }
    });
  }

  void _arm(DrumLane lane) {
    if (_armedLane == lane) return;
    setState(() => _armedLane = lane);
    controller.setColumnFocus(lane.index);
  }

  void _moveGate(int delta) {
    final next =
        (_armedLane.index + delta).clamp(0, DrumLane.values.length - 1);
    _arm(DrumLane.values[next]);
  }

  void _commit(DrumLane lane, [int? checkedIndex]) {
    switch (lane) {
      case DrumLane.home:
        if (controller.homeRoster.isNotEmpty) {
          final index = (checkedIndex ?? _homeIndex)
              .clamp(0, controller.homeRoster.length - 1);
          final player = controller.homeRoster[index];
          controller.selectPlayer(player, isHome: true);
        }
        break;
      case DrumLane.verbs:
        if (_verbs.isNotEmpty) {
          final index =
              (checkedIndex ?? _verbIndex).clamp(0, _verbs.length - 1);
          final key = _verbs[index].key;
          if (controller.selectedVerb == key) {
            controller.clearSelectedVerb();
          } else {
            controller.selectVerb(key);
          }
        }
        break;
      case DrumLane.away:
        if (controller.awayRoster.isNotEmpty) {
          final index = (checkedIndex ?? _awayIndex)
              .clamp(0, controller.awayRoster.length - 1);
          final player = controller.awayRoster[index];
          controller.selectPlayer(player, isHome: false);
        }
        break;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _spin(_armedLane, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _spin(_armedLane, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveGate(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.tab) {
      _moveGate(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commit(_armedLane);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _repairIndices() {
    final nextHome = controller.homeRoster.isEmpty
        ? 0
        : _homeIndex.clamp(0, controller.homeRoster.length - 1);
    final nextVerb =
        _verbs.isEmpty ? 0 : _verbIndex.clamp(0, _verbs.length - 1);
    final nextAway = controller.awayRoster.isEmpty
        ? 0
        : _awayIndex.clamp(0, controller.awayRoster.length - 1);
    if (nextHome == _homeIndex &&
        nextVerb == _verbIndex &&
        nextAway == _awayIndex) {
      return;
    }
    _homeIndex = nextHome;
    _verbIndex = nextVerb;
    _awayIndex = nextAway;
  }

  @override
  void didUpdateWidget(covariant DesktopDrumPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _verbIndex = _selectedVerbIndex();
    }
  }

  @override
  Widget build(BuildContext context) {
    _repairIndices();
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Row(
        key: const ValueKey('desktop-drum-picker'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 100,
            child: _columnShell(
              tokens: tokens,
              armed: _armedLane == DrumLane.home,
              child: _rosterLane(
                tokens: tokens,
                lane: DrumLane.home,
                title: controller.homeAbbr,
                players: controller.homeRoster,
                selectedIndex: _homeIndex,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 100,
            child: _columnShell(
              tokens: tokens,
              armed: _armedLane == DrumLane.verbs,
              child: _verbLane(tokens),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 100,
            child: _columnShell(
              tokens: tokens,
              armed: _armedLane == DrumLane.away,
              child: _rosterLane(
                tokens: tokens,
                lane: DrumLane.away,
                title: controller.awayAbbr,
                players: controller.awayRoster,
                selectedIndex: _awayIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _columnShell({
    required FfTokens tokens,
    required bool armed,
    required Widget child,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(
          color: armed ? tokens.accent : tokens.divider,
          width: armed ? FfTokens.focusOutlineWidth : 1,
        ),
      ),
      child: child,
    );
  }

  Widget _header(
    FfTokens tokens,
    DrumLane lane,
    String title,
  ) {
    final armed = _armedLane == lane;
    final isRoster = lane != DrumLane.verbs;
    return Container(
      height: isRoster ? 34 : 30,
      padding: EdgeInsets.symmetric(horizontal: isRoster ? 8 : 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isRoster) ...[
            Text(
              title,
              style: FfTokens.captionTitle.copyWith(
                color: armed ? tokens.accent : tokens.text,
                fontSize: 15,
                letterSpacing: -0.45,
                height: 1,
              ),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: tokens.sunken,
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                ),
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 14,
                  width: double.infinity,
                  child: TextField(
                    key: ValueKey('drum-search-${lane.name}'),
                    controller: _filterFor(lane),
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FfTokens.weightRegular,
                      color: tokens.text,
                      height: 1,
                    ),
                    cursorColor: tokens.accent,
                    cursorHeight: 12,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => _onRosterFilterChanged(lane),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              key: ValueKey('drum-sort-${lane.name}'),
              onTap: controller.cycleRosterSortField,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  controller.rosterSortFieldLabel(),
                  style: tokens.metaStyle.copyWith(
                    color: tokens.textSecondary,
                    height: 1,
                    fontSize: 12,
                  ),
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                ),
              ),
            ),
            InkWell(
              key: ValueKey('drum-sort-dir-${lane.name}'),
              onTap: controller.toggleRosterSortDirection,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  controller.rosterSortDirectionLabel(),
                  style: tokens.metaStyle.copyWith(
                    color: tokens.textSecondary,
                    height: 1,
                    fontSize: 12,
                  ),
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                ),
              ),
            ),
          ],
          if (lane == DrumLane.verbs) ...[
            Tooltip(
              message: 'Default',
              child: InkWell(
                key: const ValueKey('drum-scroll-toggle'),
                onTap: () => widget.onModeChanged?.call(DrumPickerMode.scroll),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(
                    Icons.swap_vert,
                    size: 14,
                    color: widget.mode == DrumPickerMode.scroll
                        ? tokens.accent
                        : tokens.textSecondary,
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Drum wheel',
              child: InkWell(
                key: const ValueKey('drum-infinite-toggle'),
                onTap: () =>
                    widget.onModeChanged?.call(DrumPickerMode.infinite),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(
                    Icons.all_inclusive,
                    size: 14,
                    color: widget.mode == DrumPickerMode.infinite
                        ? tokens.accent
                        : tokens.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _rosterLane({
    required FfTokens tokens,
    required DrumLane lane,
    required String title,
    required List<Player> players,
    required int selectedIndex,
  }) {
    final letterFilter =
        lane == DrumLane.home ? _homeLetterFilter : _awayLetterFilter;
    final visiblePlayers = _visiblePlayersFor(lane);
    final selectedPlayer = players.isEmpty
        ? null
        : players[selectedIndex.clamp(0, players.length - 1)];
    final visibleSelectedIndex = selectedPlayer == null
        ? 0
        : visiblePlayers.indexWhere(
            (player) =>
                player.fullName == selectedPlayer.fullName &&
                player.jerseyNumber == selectedPlayer.jerseyNumber,
          );

    int rosterIndexOf(Player player) => players.indexWhere(
          (item) =>
              item.fullName == player.fullName &&
              item.jerseyNumber == player.jerseyNumber,
        );

    Widget playerList() {
      return Expanded(
        child: visiblePlayers.isEmpty
            ? Center(
                child: Text(
                  _filterFor(lane).text.trim().isNotEmpty || letterFilter != null
                      ? 'No match'
                      : 'No players',
                  style: tokens.metaStyle.copyWith(
                    color: tokens.text.withValues(alpha: 0.34),
                  ),
                ),
              )
            : widget.mode == DrumPickerMode.scroll && letterFilter != null
                ? _FilteredPlayerList(
                    letter: letterFilter,
                    players: visiblePlayers,
                    tokens: tokens,
                    nameFor: controller.playerListName,
                    onBack: () => setState(() {
                      if (lane == DrumLane.home) {
                        _homeLetterFilter = null;
                      } else {
                        _awayLetterFilter = null;
                      }
                    }),
                    onSelect: (player) => _commit(lane, rosterIndexOf(player)),
                  )
                : widget.mode == DrumPickerMode.scroll
                    ? _HoverPlayerList(
                        laneKey: lane.name,
                        players: visiblePlayers,
                        selectedIndex: visibleSelectedIndex < 0
                            ? 0
                            : visibleSelectedIndex,
                        armed: _armedLane == lane,
                        tokens: tokens,
                        nameFor: controller.playerListName,
                        isSelected: (player) => controller.isPlayerSelected(
                          player,
                          isHome: lane == DrumLane.home,
                        ),
                        onTarget: (index) =>
                            _setIndex(lane, rosterIndexOf(visiblePlayers[index])),
                        onCommit: (index) =>
                            _commit(lane, rosterIndexOf(visiblePlayers[index])),
                      )
                    : _DrumWheel<Player>(
                        laneKey: lane.name,
                        items: visiblePlayers,
                        selectedIndex: visibleSelectedIndex < 0
                            ? 0
                            : visibleSelectedIndex,
                        looping: false,
                        armed: _armedLane == lane,
                        tokens: tokens,
                        jerseyFor: (player) => player.jerseyNumber ?? '—',
                        labelFor: controller.playerListName,
                        isSelected: (player) => controller.isPlayerSelected(
                          player,
                          isHome: lane == DrumLane.home,
                        ),
                        onMove: (delta) => _spin(lane, delta),
                        onCommit: (index) {
                          final rosterIndex =
                              rosterIndexOf(visiblePlayers[index]);
                          _setIndex(lane, rosterIndex);
                          _commit(lane, rosterIndex);
                        },
                      ),
      );
    }

    final scrubber = _RosterScrubber(
      players: players,
      activeIndex: selectedIndex,
      onLeft: lane == DrumLane.home,
      activeLetter:
          widget.mode == DrumPickerMode.scroll ? (letterFilter ?? '#') : null,
      armed: _armedLane == lane,
      tokens: tokens,
      onSelect: (letter, index) {
        if (widget.mode == DrumPickerMode.scroll) {
          setState(() {
            if (lane == DrumLane.home) {
              _homeLetterFilter = letter == '#' ? null : letter;
            } else {
              _awayLetterFilter = letter == '#' ? null : letter;
            }
          });
        }
        _setIndex(lane, index);
      },
    );

    return Column(
      children: [
        _header(tokens, lane, title),
        Expanded(
          child: Row(
            children: [
              if (lane == DrumLane.home) scrubber,
              playerList(),
              if (lane == DrumLane.away) scrubber,
            ],
          ),
        ),
      ],
    );
  }

  String _surnameInitial(Player player) {
    final surname = player.fullName.trim().split(RegExp(r'\s+')).last;
    return surname.isEmpty ? '#' : surname.characters.first.toUpperCase();
  }

  String _displayCategory(String category) {
    final normalized = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return normalized.contains('nongame') ? 'Non-game' : category;
  }

  void _jumpToVerbCategory(String category) {
    _arm(DrumLane.verbs);
    if (category == _category) {
      _setIndex(DrumLane.verbs, 0);
      return;
    }
    controller.setVerbCategory(category);
    setState(() => _verbIndex = 0);
  }

  Widget _verbLane(FfTokens tokens) {
    final armed = _armedLane == DrumLane.verbs;
    final orderedVerbsByCategory = {
      for (final category in _categories) category: _verbsForCategory(category),
    };
    final selectedKey = controller.selectedVerb;
    final categoryVerbs = _verbs;
    final verbIndex = _verbIndex.clamp(
      0,
      categoryVerbs.isEmpty ? 0 : categoryVerbs.length - 1,
    );

    Widget verbBody() {
      if (widget.mode == DrumPickerMode.infinite) {
        final scrubber = _VerbCategoryScrubber(
          categories: _categories,
          activeCategory: _category,
          armed: armed,
          tokens: tokens,
          labelFor: _displayCategory,
          onSelect: _jumpToVerbCategory,
        );
        if (categoryVerbs.isEmpty) {
          return Row(
            children: [
              scrubber,
              Expanded(
                child: Center(
                  child: Text('No verbs', style: tokens.metaStyle),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            scrubber,
            Expanded(
              child: _VerbRows(
                key: const ValueKey('verb-side-list'),
                controller: controller,
                verbs: categoryVerbs,
                selectedIndex: verbIndex,
                selectedVerbKey: selectedKey,
                armed: armed,
                tokens: tokens,
                leadingPadding: 10,
                scrollable: true,
                onVerbArmed: (index) {
                  _arm(DrumLane.verbs);
                  _setIndex(DrumLane.verbs, index);
                  _commit(DrumLane.verbs, index);
                },
                onToggleFavorite: _toggleVerbFavorite,
              ),
            ),
          ],
        );
      }
      return _VerbAccordion(
        controller: controller,
        categories: _categories,
        verbsByCategory: orderedVerbsByCategory,
        selectedCategory: _category,
        collapsed: _verbAccordionCollapsed,
        selectedIndex: _verbIndex,
        selectedVerbKey: selectedKey,
        armed: armed,
        tokens: tokens,
        onCategorySelected: _selectCategory,
        onVerbArmed: (index) {
          _arm(DrumLane.verbs);
          _setIndex(DrumLane.verbs, index);
          _commit(DrumLane.verbs, index);
        },
        onToggleFavorite: _toggleVerbFavorite,
      );
    }

    return Column(
      children: [
        _header(tokens, DrumLane.verbs, 'VERBS'),
        Expanded(child: verbBody()),
      ],
    );
  }
}

class _VerbAccordion extends StatelessWidget {
  const _VerbAccordion({
    required this.controller,
    required this.categories,
    required this.verbsByCategory,
    required this.selectedCategory,
    required this.collapsed,
    required this.selectedIndex,
    required this.selectedVerbKey,
    required this.armed,
    required this.tokens,
    required this.onCategorySelected,
    required this.onVerbArmed,
    required this.onToggleFavorite,
  });

  static const preferredHeaderHeight = 34.0;
  static const minHeaderHeight = 28.0;
  static const rowHeight = 20.0;
  static const rbiExtrasHeight = 32.0;
  static const baseExtrasHeight = 32.0;
  static const celebrationExtrasHeight = 32.0;
  static const extrasDividerHeight = 8.0;

  final CaptionV2Controller controller;
  final List<String> categories;
  final Map<String, List<EffectiveVerb>> verbsByCategory;
  final String selectedCategory;
  final bool collapsed;
  final int selectedIndex;
  final String? selectedVerbKey;
  final bool armed;
  final FfTokens tokens;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;

  String _displayCategory(String category) {
    final normalized = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return normalized.contains('nongame') ? 'Non-game' : category;
  }

  double _extrasHeightFor(String? key) {
    if (key == null) return 0;
    var height = 0.0;
    final needsRbi = controller.verbNeedsRbi(key);
    final needsBase = controller.verbNeedsBase(key);
    final needsCelebration = controller.verbNeedsCelebration(key);
    if (!needsRbi && !needsBase && !needsCelebration) return 0;
    height += extrasDividerHeight;
    if (needsRbi) height += rbiExtrasHeight;
    if (needsBase) height += baseExtrasHeight;
    if (needsCelebration) height += celebrationExtrasHeight;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final openVerbs = collapsed
            ? const <EffectiveVerb>[]
            : (verbsByCategory[selectedCategory] ?? const <EffectiveVerb>[]);
        final openVerbCount = openVerbs.length;
        final selectedInOpen = !collapsed &&
            selectedVerbKey != null &&
            openVerbs.any((verb) => verb.key == selectedVerbKey);
        final extrasHeight =
            selectedInOpen ? _extrasHeightFor(selectedVerbKey) : 0.0;
        final openBodyHeight = openVerbCount * rowHeight + extrasHeight;
        final minContentHeight =
            categories.length * minHeaderHeight + openBodyHeight;
        final bounded = constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite;
        final needsScroll =
            bounded && minContentHeight > constraints.maxHeight + 0.5;

        final double headerHeight;
        if (categories.isEmpty) {
          headerHeight = preferredHeaderHeight;
        } else if (needsScroll) {
          headerHeight = minHeaderHeight;
        } else {
          final availableForHeaders =
              constraints.maxHeight - openBodyHeight;
          headerHeight = (availableForHeaders / categories.length)
              .clamp(minHeaderHeight, preferredHeaderHeight);
        }

        final column = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in categories)
              _VerbAccordionSection(
                controller: controller,
                category: category,
                displayCategory: _displayCategory(category),
                verbs: verbsByCategory[category] ?? const <EffectiveVerb>[],
                headerHeight: headerHeight,
                open: !collapsed && category == selectedCategory,
                selectedIndex: selectedIndex,
                selectedVerbKey: selectedVerbKey,
                armed: armed,
                tokens: tokens,
                onOpen: () => onCategorySelected(category),
                onVerbArmed: onVerbArmed,
                onToggleFavorite: onToggleFavorite,
              ),
          ],
        );

        if (!needsScroll) return column;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: column,
        );
      },
    );
  }
}

class _VerbAccordionSection extends StatelessWidget {
  const _VerbAccordionSection({
    required this.controller,
    required this.category,
    required this.displayCategory,
    required this.verbs,
    required this.headerHeight,
    required this.open,
    required this.selectedIndex,
    required this.selectedVerbKey,
    required this.armed,
    required this.tokens,
    required this.onOpen,
    required this.onVerbArmed,
    required this.onToggleFavorite,
  });

  final CaptionV2Controller controller;
  final String category;
  final String displayCategory;
  final List<EffectiveVerb> verbs;
  final double headerHeight;
  final bool open;
  final int selectedIndex;
  final String? selectedVerbKey;
  final bool armed;
  final FfTokens tokens;
  final VoidCallback onOpen;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final divider =
        open ? tokens.accent.withValues(alpha: 0.34) : tokens.divider;
    return Column(
      children: [
        Material(
          color:
              open ? tokens.accent.withValues(alpha: 0.13) : Colors.transparent,
          child: InkWell(
            key: ValueKey('verb-accordion-$category'),
            onTap: onOpen,
            hoverColor: tokens.text.withValues(alpha: 0.06),
            child: Container(
              height: headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: divider)),
              ),
              child: Row(
                children: [
                  Icon(
                    open
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: open
                        ? tokens.accent
                        : tokens.text.withValues(alpha: 0.38),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayCategory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: open
                            ? FfTokens.labelFamily
                            : FfTokens.fontFamily,
                        fontSize: 15,
                        height: 1.0,
                        fontWeight: open ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: open ? -0.2 : 0,
                        color: open
                            ? tokens.accent
                            : tokens.text.withValues(alpha: 0.76),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? _VerbRows(
                  controller: controller,
                  verbs: verbs,
                  selectedIndex: selectedIndex,
                  selectedVerbKey: selectedVerbKey,
                  armed: armed,
                  tokens: tokens,
                  leadingPadding: 34,
                  fontSize: 12,
                  onVerbArmed: onVerbArmed,
                  onToggleFavorite: onToggleFavorite,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _VerbRows extends StatefulWidget {
  const _VerbRows({
    super.key,
    required this.controller,
    required this.verbs,
    required this.selectedIndex,
    required this.selectedVerbKey,
    required this.armed,
    required this.tokens,
    required this.onVerbArmed,
    required this.onToggleFavorite,
    this.leadingPadding = 26,
    this.fontSize = 12,
    this.scrollable = false,
  });

  final CaptionV2Controller controller;
  final List<EffectiveVerb> verbs;
  final int selectedIndex;
  final String? selectedVerbKey;
  final bool armed;
  final FfTokens tokens;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;
  final double leadingPadding;
  final double fontSize;
  final bool scrollable;

  @override
  State<_VerbRows> createState() => _VerbRowsState();
}

class _VerbRowsState extends State<_VerbRows> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _VerbRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollable &&
        widget.selectedVerbKey != null &&
        widget.selectedVerbKey != oldWidget.selectedVerbKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final index = widget.verbs
            .indexWhere((verb) => verb.key == widget.selectedVerbKey);
        if (index < 0) return;
        // Approximate: row + optional extras; keep the selected verb near top.
        final offset = (index * _VerbAccordion.rowHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _row(int index) {
    final verb = widget.verbs[index];
    final committed = widget.selectedVerbKey == verb.key;
    final selected = committed ||
        (widget.selectedVerbKey == null &&
            widget.armed &&
            index == widget.selectedIndex);
    final showRbi = committed && widget.controller.verbNeedsRbi(verb.key);
    final showBase = committed && widget.controller.verbNeedsBase(verb.key);
    final showCelebration =
        committed && widget.controller.verbNeedsCelebration(verb.key);

    return _HoverVerbBlock(
      key: ValueKey('verb-hover-${verb.key}'),
      selected: selected,
      committed: committed,
      verb: verb,
      leadingPadding: widget.leadingPadding,
      fontSize: widget.fontSize,
      tokens: widget.tokens,
      showRbi: showRbi,
      showBase: showBase,
      showCelebration: showCelebration,
      rbi: widget.controller.rbi,
      selectedBase: widget.controller.selectedBase,
      celebrationType: widget.controller.celebrationType,
      reactionOptions: showCelebration
          ? widget.controller.reactionOptionsFor(verb.key)
          : const <String>[],
      celebrationTypeOptions: const <String>[],
      onTap: () => widget.onVerbArmed(index),
      onToggleFavorite: () => widget.onToggleFavorite(verb.key),
      onRbiChanged: widget.controller.setRbi,
      onBaseChanged: widget.controller.setSelectedBase,
      onCelebrationChanged: widget.controller.setCelebrationType,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.verbs.isEmpty) {
      return Center(
        child: Text('No verbs', style: widget.tokens.metaStyle),
      );
    }
    if (widget.scrollable) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: widget.verbs.length,
        itemBuilder: (context, index) => _row(index),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < widget.verbs.length; index++) _row(index),
      ],
    );
  }
}

class _HoverVerbBlock extends StatefulWidget {
  const _HoverVerbBlock({
    super.key,
    required this.verb,
    required this.selected,
    required this.committed,
    required this.leadingPadding,
    required this.fontSize,
    required this.tokens,
    required this.showRbi,
    required this.showBase,
    required this.showCelebration,
    required this.rbi,
    required this.selectedBase,
    required this.celebrationType,
    required this.reactionOptions,
    required this.celebrationTypeOptions,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onRbiChanged,
    required this.onBaseChanged,
    required this.onCelebrationChanged,
  });

  final EffectiveVerb verb;
  final bool selected;
  final bool committed;
  final double leadingPadding;
  final double fontSize;
  final FfTokens tokens;
  final bool showRbi;
  final bool showBase;
  final bool showCelebration;
  final int rbi;
  final String? selectedBase;
  final String? celebrationType;
  final List<String> reactionOptions;
  final List<String> celebrationTypeOptions;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final ValueChanged<int> onRbiChanged;
  final ValueChanged<String?> onBaseChanged;
  final ValueChanged<String?> onCelebrationChanged;

  @override
  State<_HoverVerbBlock> createState() => _HoverVerbBlockState();
}

class _HoverVerbBlockState extends State<_HoverVerbBlock> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    // Defer so layout changes from selecting RBI verbs don't nest inside
    // MouseTracker's device-update phase (that freezes the picker).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VerbAccordionRow(
            verb: widget.verb,
            selected: widget.selected,
            committed: widget.committed,
            hovered: _hovered,
            fontSize: widget.fontSize,
            leadingPadding: widget.leadingPadding,
            tokens: widget.tokens,
            onTap: widget.onTap,
            onToggleFavorite: widget.onToggleFavorite,
          ),
          if (widget.showRbi ||
              widget.showBase ||
              widget.showCelebration) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(widget.leadingPadding, 2, 8, 0),
              child: Divider(
                height: 1,
                thickness: 1,
                color: widget.tokens.divider,
              ),
            ),
            if (widget.showRbi)
              Padding(
                padding: EdgeInsets.fromLTRB(widget.leadingPadding, 3, 8, 1),
                child: RbiRow(
                  value: widget.rbi,
                  compact: true,
                  homeRunStyle: widget.verb.key == 'Home Run',
                  onChanged: widget.onRbiChanged,
                ),
              ),
            if (widget.showBase)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.leadingPadding,
                  widget.showRbi ? 4 : 3,
                  8,
                  1,
                ),
                child: BaseRow(
                  value: widget.selectedBase,
                  compact: true,
                  onChanged: widget.onBaseChanged,
                ),
              ),
            if (widget.showCelebration)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.leadingPadding,
                  (widget.showRbi || widget.showBase) ? 4 : 3,
                  8,
                  2,
                ),
                child: CelebrationDropdown(
                  compact: true,
                  reactions: widget.reactionOptions,
                  celebrations: widget.celebrationTypeOptions,
                  selected: widget.celebrationType,
                  onChanged: widget.onCelebrationChanged,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(widget.leadingPadding, 2, 8, 2),
              child: Divider(
                height: 1,
                thickness: 1,
                color: widget.tokens.divider,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerbAccordionRow extends StatelessWidget {
  const _VerbAccordionRow({
    required this.verb,
    required this.selected,
    required this.committed,
    required this.hovered,
    required this.fontSize,
    required this.tokens,
    required this.onTap,
    required this.onToggleFavorite,
    this.leadingPadding = 26,
  });

  final EffectiveVerb verb;
  final bool selected;
  final bool committed;
  final bool hovered;
  final double fontSize;
  final FfTokens tokens;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final double leadingPadding;

  @override
  Widget build(BuildContext context) {
    final bright = selected || hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          key: ValueKey('verb-accordion-row-${verb.key}'),
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          child: Container(
            height: _VerbAccordion.rowHeight,
            padding: EdgeInsets.only(left: leadingPadding, right: 10),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontFamily: FfTokens.labelFamily,
                      fontSize: hovered ? 14.0 : fontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: bright ? -0.4 : 0,
                      color: bright
                          ? tokens.text
                          : tokens.text.withValues(alpha: 0.68),
                    ),
                    child: Text(
                      verb.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (committed) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check,
                    size: 12,
                    color: tokens.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            verb.isFavorite ? 'Remove favorite' : 'Add favorite',
          ),
        ),
      ],
    );
    if (action == 'favorite') onToggleFavorite();
  }
}

class _FilteredPlayerList extends StatelessWidget {
  const _FilteredPlayerList({
    required this.letter,
    required this.players,
    required this.tokens,
    required this.nameFor,
    required this.onBack,
    required this.onSelect,
  });

  final String letter;
  final List<Player> players;
  final FfTokens tokens;
  final String Function(Player) nameFor;
  final VoidCallback onBack;
  final ValueChanged<Player> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: TextButton.icon(
            key: const ValueKey('player-filter-back'),
            onPressed: onBack,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: tokens.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.arrow_back, size: 13),
            label: Text(
              'Back · $letter',
              style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
            ),
          ),
        ),
        Divider(height: 1, color: tokens.divider),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('filtered-player-list'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            itemCount: players.length,
            itemExtent: 20,
            itemBuilder: (context, index) {
              final player = players[index];
              return InkWell(
                onTap: () => onSelect(player),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          player.jerseyNumber ?? '—',
                          textAlign: TextAlign.right,
                          style: tokens.jerseyStyle.copyWith(fontSize: 10.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nameFor(player),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FfTokens.labelFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: tokens.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HoverPlayerList extends StatefulWidget {
  const _HoverPlayerList({
    required this.laneKey,
    required this.players,
    required this.selectedIndex,
    required this.armed,
    required this.tokens,
    required this.nameFor,
    required this.isSelected,
    required this.onTarget,
    required this.onCommit,
  });

  final String laneKey;
  final List<Player> players;
  final int selectedIndex;
  final bool armed;
  final FfTokens tokens;
  final String Function(Player) nameFor;
  final bool Function(Player) isSelected;
  final ValueChanged<int> onTarget;
  final ValueChanged<int> onCommit;

  @override
  State<_HoverPlayerList> createState() => _HoverPlayerListState();
}

class _HoverPlayerListState extends State<_HoverPlayerList> {
  static const _itemExtent = 20.0;
  final ScrollController _scrollController = ScrollController();
  int? _hoveredIndex;
  double? _pointerY;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncFocalToPointer);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncFocalToPointer)
      ..dispose();
    super.dispose();
  }

  void _trackPointer(PointerEvent event) {
    _hovering = true;
    _pointerY = event.localPosition.dy;
    _syncFocalToPointer();
  }

  void _syncFocalToPointer() {
    if (!_hovering || _pointerY == null || widget.players.isEmpty) return;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0;
    final index = ((offset + _pointerY! - 2) / _itemExtent)
        .floor()
        .clamp(0, widget.players.length - 1);
    if (_hoveredIndex != index && mounted) {
      setState(() => _hoveredIndex = index);
    }
    if (index != widget.selectedIndex) widget.onTarget(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.players.isEmpty) {
      return Center(
        child: Text('No players', style: widget.tokens.metaStyle),
      );
    }
    return MouseRegion(
      onEnter: _trackPointer,
      onHover: _trackPointer,
      onExit: (_) => setState(() {
        _hovering = false;
        _hoveredIndex = null;
      }),
      cursor: SystemMouseCursors.click,
      child: ListView.builder(
        key: ValueKey('scroll-list-${widget.laneKey}'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: widget.players.length,
        itemExtent: _itemExtent,
        physics: const ClampingScrollPhysics(),
        itemBuilder: (context, index) {
          final player = widget.players[index];
          final targeted = index == widget.selectedIndex;
          final selected = widget.isSelected(player);
          final playerFontSize = index == _hoveredIndex ? 17.0 : 13.5;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onTarget(index);
              widget.onCommit(index);
            },
            child: AnimatedContainer(
              key: ValueKey(
                'scroll-${widget.laneKey}-player-$index',
              ),
              duration: const Duration(milliseconds: 70),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              color: selected
                  ? widget.tokens.accent.withValues(alpha: 0.22)
                  : targeted && widget.armed
                      ? widget.tokens.accent.withValues(alpha: 0.15)
                      : Colors.transparent,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 210),
                      curve: Curves.easeOutQuart,
                      style: widget.tokens.jerseyStyle.copyWith(
                        fontSize: 10.5,
                        color: targeted
                            ? widget.tokens.accent
                            : widget.tokens.textSecondary,
                      ),
                      child: Text(
                        player.jerseyNumber ?? '—',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: playerFontSize,
                        fontWeight: FontWeight.w500,
                        letterSpacing: targeted ? -0.4 : 0,
                        color: targeted
                            ? widget.tokens.text
                            : widget.tokens.text.withValues(alpha: 0.74),
                      ),
                      child: Text(
                        widget.nameFor(player),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 12,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: selected || (targeted && _hovering) ? 1 : 0,
                      child: Center(
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 12,
                                color: widget.armed
                                    ? widget.tokens.accent
                                    : widget.tokens.textSecondary,
                              )
                            : Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: widget.armed
                                      ? widget.tokens.accent
                                      : widget.tokens.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DrumWheel<T> extends StatefulWidget {
  const _DrumWheel({
    required this.laneKey,
    required this.items,
    required this.selectedIndex,
    required this.looping,
    required this.armed,
    required this.tokens,
    required this.labelFor,
    required this.onMove,
    required this.onCommit,
    this.jerseyFor,
    this.categoryFor,
    this.isSelected,
  });

  final String laneKey;
  final List<T> items;
  final int selectedIndex;
  final bool looping;
  final bool armed;
  final FfTokens tokens;
  final String Function(T item) labelFor;
  final String Function(T item)? jerseyFor;
  final String Function(T item)? categoryFor;
  final bool Function(T item)? isSelected;
  final ValueChanged<int> onMove;
  final ValueChanged<int> onCommit;

  @override
  State<_DrumWheel<T>> createState() => _DrumWheelState<T>();
}

class _DrumWheelState<T> extends State<_DrumWheel<T>> {
  static const _animationDuration = Duration(milliseconds: 180);
  double _dragDistance = 0;

  _DrumMetrics _metrics(int distance) {
    final playerRow = widget.jerseyFor != null;
    if (distance == 0) {
      return playerRow
          ? const _DrumMetrics(44, 18.5, 1, FontWeight.w700)
          : const _DrumMetrics(52, 18, 1, FontWeight.w700);
    }
    if (distance == 1) {
      return playerRow
          ? const _DrumMetrics(30, 14.5, 0.86, FontWeight.w400)
          : const _DrumMetrics(36, 15, 0.86, FontWeight.w400);
    }
    if (distance == 2) {
      return playerRow
          ? const _DrumMetrics(26, 13, 0.72, FontWeight.w400)
          : const _DrumMetrics(31, 14, 0.72, FontWeight.w400);
    }
    if (distance == 3) {
      return playerRow
          ? const _DrumMetrics(22, 12, 0.60, FontWeight.w400)
          : const _DrumMetrics(28, 13, 0.60, FontWeight.w400);
    }
    return playerRow
        ? const _DrumMetrics(20, 11.5, 0.50, FontWeight.w400)
        : const _DrumMetrics(26, 12.5, 0.50, FontWeight.w400);
  }

  double _gateTop(double laneHeight, double gateHeight) {
    final fraction = widget.laneKey == 'verbs' ? 0.10 : 0.5;
    return (laneHeight * fraction - gateHeight / 2)
        .clamp(0.0, laneHeight - gateHeight)
        .toDouble();
  }

  /// Verbs sit at 10% from the top; roster lanes stay slightly above center.
  double _finiteGateTop(
    double laneHeight,
    double gateHeight,
    int selected,
    int count,
  ) {
    final fraction = widget.laneKey == 'verbs' ? 0.10 : 0.38;
    return (laneHeight * fraction - gateHeight / 2)
        .clamp(0.0, laneHeight - gateHeight)
        .toDouble();
  }

  Widget _selectionWindow({
    required double top,
    required double height,
    required int selected,
  }) {
    return Positioned(
      key: ValueKey('drum-target-${widget.laneKey}'),
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onCommit(selected),
        child: DecoratedBox(
          key: ValueKey('drum-gate-${widget.laneKey}'),
          decoration: BoxDecoration(
            color: widget.tokens.accent.withValues(
              alpha: widget.armed ? 0.18 : 0.12,
            ),
            border: Border.symmetric(
              horizontal: BorderSide(
                color: widget.tokens.accent.withValues(
                  alpha: widget.armed ? 1 : 0.72,
                ),
                width: widget.armed ? 1.5 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _edgeFade() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.tokens.surface,
                widget.tokens.surface.withValues(alpha: 0),
                widget.tokens.surface.withValues(alpha: 0),
                widget.tokens.surface,
              ],
              stops: const [0, 0.12, 0.88, 1],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text('No items', style: widget.tokens.metaStyle),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final selected = widget.selectedIndex.clamp(0, widget.items.length - 1);
        if (widget.looping) {
          return _buildLooping(constraints, selected);
        }
        return _buildFinite(constraints, selected);
      },
    );
  }

  Widget _buildFinite(BoxConstraints constraints, int selected) {
    final laneHeight = constraints.maxHeight;
    final gateHeight = _metrics(0).height;
    final gateY = _finiteGateTop(
      laneHeight,
      gateHeight,
      selected,
      widget.items.length,
    );
    final metrics = List<_DrumMetrics>.generate(
      widget.items.length,
      (index) => _metrics((index - selected).abs()),
    );
    final tops = List<double>.filled(widget.items.length, 0);
    tops[selected] = gateY;
    var above = gateY;
    for (var index = selected - 1; index >= 0; index--) {
      above -= metrics[index].height;
      tops[index] = above;
    }
    var below = gateY + gateHeight;
    for (var index = selected + 1; index < widget.items.length; index++) {
      tops[index] = below;
      below += metrics[index].height;
    }

    return Listener(
      key: ValueKey('drum-${widget.laneKey}'),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          widget.onMove(event.scrollDelta.dy > 0 ? 1 : -1);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _dragDistance = 0,
        onVerticalDragUpdate: (details) {
          _dragDistance += details.delta.dy;
          while (_dragDistance.abs() >= 30) {
            widget.onMove(_dragDistance < 0 ? -1 : 1);
            _dragDistance += _dragDistance < 0 ? 30 : -30;
          }
        },
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 300) return;
          final rows = (velocity.abs() / 500).round().clamp(1, 12);
          widget.onMove(velocity < 0 ? -rows : rows);
        },
        child: ClipRect(
          child: Stack(
            children: [
              for (var index = 0; index < widget.items.length; index++)
                AnimatedPositioned(
                  key: ValueKey(
                    'drum-${widget.laneKey}-row-$index',
                  ),
                  duration: _animationDuration,
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: tops[index],
                  height: metrics[index].height,
                  child: _row(
                    item: widget.items[index],
                    metrics: metrics[index],
                    atGate: index == selected,
                    index: index,
                  ),
                ),
              _selectionWindow(
                top: gateY,
                height: gateHeight,
                selected: selected,
              ),
              _edgeFade(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLooping(BoxConstraints constraints, int selected) {
    final laneHeight = constraints.maxHeight;
    final gateHeight = _metrics(0).height;
    final gateY = _gateTop(laneHeight, gateHeight);
    final aboveCount = widget.items.length ~/ 2;
    final firstDistance = -aboveCount;
    final lastDistance = widget.items.length - aboveCount - 1;
    const boundaryGap = 10.0;
    var selectedOffset = 0.0;
    for (var distance = firstDistance; distance < 0; distance++) {
      final itemIndex = (selected + distance) % widget.items.length;
      if (itemIndex == 0) selectedOffset += boundaryGap;
      selectedOffset += _metrics(distance.abs()).height;
    }
    if (selected == 0) selectedOffset += boundaryGap;
    var top = gateY - selectedOffset;
    double? boundaryTop;
    final rows = <_LoopingDrumRow<T>>[];
    for (var distance = firstDistance; distance <= lastDistance; distance++) {
      final metrics = _metrics(distance.abs());
      final itemIndex = (selected + distance) % widget.items.length;
      if (itemIndex == 0) {
        boundaryTop = top;
        top += boundaryGap;
      }
      rows.add(
        _LoopingDrumRow(
          item: widget.items[itemIndex],
          itemIndex: itemIndex,
          distance: distance,
          top: top,
          metrics: metrics,
        ),
      );
      top += metrics.height;
    }

    return Listener(
      key: ValueKey('drum-${widget.laneKey}'),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          widget.onMove(event.scrollDelta.dy > 0 ? 1 : -1);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _dragDistance = 0,
        onVerticalDragUpdate: (details) {
          _dragDistance += details.delta.dy;
          while (_dragDistance.abs() >= 30) {
            widget.onMove(_dragDistance < 0 ? -1 : 1);
            _dragDistance += _dragDistance < 0 ? 30 : -30;
          }
        },
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 300) return;
          final rowsToMove = (velocity.abs() / 500).round().clamp(1, 12);
          widget.onMove(velocity < 0 ? -rowsToMove : rowsToMove);
        },
        child: ClipRect(
          child: Stack(
            children: [
              for (final row in rows)
                AnimatedPositioned(
                  key: ValueKey(
                    'drum-${widget.laneKey}-loop-${row.distance}',
                  ),
                  duration: _animationDuration,
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: row.top,
                  height: row.metrics.height,
                  child: _row(
                    item: row.item,
                    metrics: row.metrics,
                    atGate: row.distance == 0,
                    index: row.itemIndex,
                  ),
                ),
              if (boundaryTop != null)
                AnimatedPositioned(
                  key: ValueKey(
                    'drum-${widget.laneKey}-roster-boundary',
                  ),
                  duration: _animationDuration,
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: boundaryTop,
                  height: boundaryGap,
                  child: const SizedBox.expand(),
                ),
              _selectionWindow(
                top: gateY,
                height: gateHeight,
                selected: selected,
              ),
              _edgeFade(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required T item,
    required _DrumMetrics metrics,
    required bool atGate,
    required int index,
  }) {
    final textColor = atGate
        ? widget.tokens.text
        : widget.tokens.text.withValues(alpha: metrics.opacity);
    final jerseyColor = atGate
        ? widget.tokens.accent
        : widget.tokens.text.withValues(alpha: metrics.opacity);
    final committed = widget.isSelected?.call(item) ?? false;

    return Semantics(
      button: true,
      selected: committed || atGate,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!atGate) {
            final length = widget.items.length;
            var step = index - widget.selectedIndex;
            if (widget.looping && length > 1) {
              final wrapped = step > 0 ? step - length : step + length;
              if (wrapped.abs() < step.abs()) step = wrapped;
            }
            if (step != 0) widget.onMove(step);
          }
          widget.onCommit(index);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (widget.jerseyFor != null) ...[
                SizedBox(
                  width: 28,
                  child: Text(
                    widget.jerseyFor!(item),
                    textAlign: TextAlign.right,
                    style: widget.tokens.jerseyStyle.copyWith(
                      fontSize: metrics.fontSize,
                      fontWeight: atGate ? FontWeight.w700 : FontWeight.w500,
                      color: jerseyColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.labelFor(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.labelFamily,
                    fontSize: metrics.fontSize,
                    fontWeight: metrics.weight,
                    letterSpacing: atGate ? -0.55 : 0,
                    color: textColor,
                  ),
                ),
              ),
              if (committed) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check,
                  size: atGate ? 14 : 12,
                  color: widget.armed
                      ? widget.tokens.accent
                      : widget.tokens.textSecondary,
                ),
              ] else if (atGate) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.tokens.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              if (atGate && widget.categoryFor != null) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 64),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.tokens.accent.withValues(
                        alpha: widget.armed ? 0.24 : 0.14,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      widget.categoryFor!(item).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: widget.tokens.accent.withValues(
                          alpha: widget.armed ? 1 : 0.85,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DrumMetrics {
  const _DrumMetrics(this.height, this.fontSize, this.opacity, this.weight);

  final double height;
  final double fontSize;
  final double opacity;
  final FontWeight weight;
}

class _LoopingDrumRow<T> {
  const _LoopingDrumRow({
    required this.item,
    required this.itemIndex,
    required this.distance,
    required this.top,
    required this.metrics,
  });

  final T item;
  final int itemIndex;
  final int distance;
  final double top;
  final _DrumMetrics metrics;
}

class _VerbCategoryScrubber extends StatelessWidget {
  const _VerbCategoryScrubber({
    required this.categories,
    required this.activeCategory,
    required this.armed,
    required this.tokens,
    required this.labelFor,
    required this.onSelect,
  });

  final List<String> categories;
  final String? activeCategory;
  final bool armed;
  final FfTokens tokens;
  final String Function(String category) labelFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: tokens.divider)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                height: 1,
                color: tokens.text.withValues(alpha: 0.28),
              ),
            InkWell(
              key: ValueKey('verb-drum-index-${categories[i]}'),
              onTap: () => onSelect(categories[i]),
              child: SizedBox(
                width: 96,
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      labelFor(categories[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: armed && activeCategory == categories[i]
                            ? tokens.accent
                            : tokens.text.withValues(
                                alpha: activeCategory == categories[i]
                                    ? 0.78
                                    : 0.46,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RosterScrubber extends StatelessWidget {
  const _RosterScrubber({
    required this.players,
    required this.activeIndex,
    required this.onLeft,
    this.activeLetter,
    required this.armed,
    required this.tokens,
    required this.onSelect,
  });

  final List<Player> players;
  final int activeIndex;
  final bool onLeft;
  final String? activeLetter;
  final bool armed;
  final FfTokens tokens;
  final void Function(String letter, int index) onSelect;

  String _initial(Player player) {
    final number = player.jerseyNumber;
    final surname = player.fullName.trim().split(RegExp(r'\s+')).last;
    if (surname.isEmpty) return number ?? '#';
    return surname.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final starts = <String, int>{if (players.isNotEmpty) '#': 0};
    for (var index = 0; index < players.length; index++) {
      starts.putIfAbsent(_initial(players[index]), () => index);
    }
    final active = activeLetter ??
        (players.isEmpty
            ? ''
            : _initial(players[activeIndex.clamp(0, players.length - 1)]));
    return Container(
      width: 24,
      decoration: BoxDecoration(
        border: Border(
          left: onLeft ? BorderSide.none : BorderSide(color: tokens.divider),
          right: onLeft ? BorderSide(color: tokens.divider) : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final entry in starts.entries)
            InkWell(
              key: ValueKey('drum-index-${entry.key}'),
              onTap: () => onSelect(entry.key, entry.value),
              child: SizedBox(
                width: 24,
                height: 20,
                child: Center(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontFamily: FfTokens.labelFamily,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: armed && active == entry.key
                          ? tokens.accent
                          : tokens.text.withValues(alpha: 0.46),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

