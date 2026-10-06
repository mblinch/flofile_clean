import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/mlb_api_service.dart';
import '../../../services/mac_spell_check_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/base_row.dart';
import '../widgets/celebration_dropdown.dart';
import '../widgets/custom_name_entry.dart';
import '../widgets/pinned_player_bar.dart';
import '../widgets/quiet_filter_field.dart';
import '../widgets/rbi_row.dart';
import '../widgets/verb_tile.dart';
import 'caption_v2_verb_editor.dart';
import 'duplicate_jersey_dialog.dart';
import 'player_data_issue_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum DrumLane { home, verbs, away }

enum DrumPickerMode { scroll, infinite }

/// Desktop shows all three lanes; mobile swipes one lane at a time.
enum DrumLayout { sideBySide, paged }

/// Shared drum UI for desktop (side-by-side) and mobile (paged swipe).
class DrumPicker extends StatefulWidget {
  const DrumPicker({
    super.key,
    required this.controller,
    this.mode = DrumPickerMode.scroll,
    this.layout = DrumLayout.sideBySide,
    this.onModeChanged,
    this.onExit,
    this.onEditRosters,
    this.pageController,
    this.onPageChanged,
  });

  final CaptionV2Controller controller;
  final DrumPickerMode mode;
  final DrumLayout layout;
  final ValueChanged<DrumPickerMode>? onModeChanged;
  final VoidCallback? onExit;
  final VoidCallback? onEditRosters;
  final PageController? pageController;
  final ValueChanged<int>? onPageChanged;

  @override
  State<DrumPicker> createState() => _DrumPickerState();
}

/// Back-compat alias for existing desktop call sites and tests.
typedef DesktopDrumPicker = DrumPicker;

class _DrumPickerState extends State<DrumPicker> {
  DrumLane _armedLane = DrumLane.verbs;
  int _homeIndex = 0;
  int _verbIndex = 0;
  int _awayIndex = 0;
  String? _homeLetterFilter;
  String? _awayLetterFilter;
  bool _numberMode = true;
  bool _verbAccordionCollapsed = false;
  final _homeFilter = TextEditingController();
  final _awayFilter = TextEditingController();
  final _customVerbController = TextEditingController();
  final _customVerbFocusNode = FocusNode(debugLabel: 'Drum custom verb');
  final _homeCustomNameController = TextEditingController();
  final _homeCustomJerseyController = TextEditingController();
  final _homeCustomNameFocus = FocusNode(debugLabel: 'Home custom name');
  final _homeCustomJerseyFocus = FocusNode(debugLabel: 'Home custom jersey');
  final _awayCustomNameController = TextEditingController();
  final _awayCustomJerseyController = TextEditingController();
  final _awayCustomNameFocus = FocusNode(debugLabel: 'Away custom name');
  final _awayCustomJerseyFocus = FocusNode(debugLabel: 'Away custom jersey');
  int _seenPlayerSearchClearGeneration = -1;

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories {
    final categories = controller.verbCategories
        .where(
          (category) =>
              category == 'Favorites' ||
              (controller.verbDefinitionsByCategory[category] ??
                      const <EffectiveVerb>[])
                  .isNotEmpty,
        )
        .toList();
    final sport = controller.sport.toLowerCase();
    final Map<String, int> order;
    if (sport == 'hockey') {
      order = const {
        'favorites': -1,
        'offense': 0,
        'defense': 1,
        'goalie': 2,
        'reactions': 3,
        'nongameaction': 4,
        'nongame': 4,
      };
    } else if (sport == 'soccer') {
      order = const {
        'favorites': -1,
        'offense': 0,
        'defense': 1,
        'goalkeeper': 2,
        'setpieces': 3,
        'reactions': 4,
        'nongameaction': 5,
        'nongame': 5,
      };
    } else {
      order = const {
        'favorites': -1,
        'offense': 0,
        'running': 1,
        'defense': 2,
        'nongameaction': 3,
        'nongame': 3,
        'reactions': 4,
        'pitching': 5,
      };
    }
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
    // Favorites first within the open category; pinned stays in-list too.
    return [
      ...verbs.where((verb) => verb.isFavorite),
      ...verbs.where((verb) => !verb.isFavorite),
    ];
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _seenPlayerSearchClearGeneration = controller.playerSearchClearGeneration;
    _customVerbController.text = controller.customVerbPhrase;
    _homeIndex = _selectedPlayerIndex(controller.homeRoster, true);
    _awayIndex = _selectedPlayerIndex(controller.awayRoster, false);
    _verbIndex = _selectedVerbIndex();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _homeFilter.dispose();
    _awayFilter.dispose();
    _customVerbController.dispose();
    _customVerbFocusNode.dispose();
    _homeCustomNameController.dispose();
    _homeCustomJerseyController.dispose();
    _homeCustomNameFocus.dispose();
    _homeCustomJerseyFocus.dispose();
    _awayCustomNameController.dispose();
    _awayCustomJerseyController.dispose();
    _awayCustomNameFocus.dispose();
    _awayCustomJerseyFocus.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncCustomVerbField();
    _syncCustomNameFromPin(isHome: true);
    _syncCustomNameFromPin(isHome: false);
    final generation = controller.playerSearchClearGeneration;
    if (generation != _seenPlayerSearchClearGeneration) {
      _seenPlayerSearchClearGeneration = generation;
      if (_homeFilter.text.isNotEmpty) _homeFilter.clear();
      if (_awayFilter.text.isNotEmpty) _awayFilter.clear();
      _homeLetterFilter = null;
      _awayLetterFilter = null;
    }
    setState(() {});
  }

  void _syncCustomVerbField() {
    final next = controller.customVerbPinned &&
            controller.customVerbPhrase.trim().isEmpty
        ? controller.lastCustomVerbPhrase
        : controller.customVerbPhrase;
    if (_customVerbController.text == next) return;
    // Apply clears even while focused so save / next-frame empty the box.
    // Keep pinned custom text visible while a catalog verb is selected.
    if (!_customVerbFocusNode.hasFocus ||
        next.isEmpty ||
        controller.customVerbPinned) {
      _customVerbController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
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
    final nextVisible = (visibleIndex + delta).clamp(0, visible.length - 1);
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

  /// Shared grid metrics so home/away number cells stay the same size.
  _NumberGridMetrics _numberModeMetrics() {
    final home = _NumberRoster.gridMetrics(_visiblePlayersFor(DrumLane.home));
    final away = _NumberRoster.gridMetrics(_visiblePlayersFor(DrumLane.away));
    final cols =
        home.columnCount > away.columnCount ? home.columnCount : away.columnCount;
    final rows = home.rowCount > away.rowCount ? home.rowCount : away.rowCount;
    return _NumberGridMetrics(
      columnCount: cols.clamp(1, _NumberRoster.maxColumns),
      rowCount: rows.clamp(1, 40),
      needsOtherRow: home.needsOtherRow || away.needsOtherRow,
    );
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

  void _arm(DrumLane lane, {bool syncPage = true}) {
    if (controller.singleTeamMode && lane == DrumLane.away) {
      lane = DrumLane.verbs;
    }
    if (_armedLane == lane) return;
    setState(() => _armedLane = lane);
    controller.setColumnFocus(lane.index);
    if (syncPage &&
        widget.layout == DrumLayout.paged &&
        widget.pageController != null &&
        widget.pageController!.hasClients &&
        widget.pageController!.page?.round() != lane.index) {
      widget.pageController!.animateToPage(
        lane.index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _moveGate(int delta) {
    final lanes = controller.singleTeamMode
        ? const [DrumLane.home, DrumLane.verbs]
        : DrumLane.values;
    var i = lanes.indexOf(_armedLane);
    if (i < 0) i = 1;
    final next = (i + delta).clamp(0, lanes.length - 1);
    _arm(lanes[next]);
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
      widget.onExit?.call();
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
  void didUpdateWidget(covariant DrumPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _verbIndex = _selectedVerbIndex();
    }
  }

  List<Widget> _laneChildren(FfTokens tokens) {
    final lanes = <Widget>[
      _columnShell(
        tokens: tokens,
        armed: _armedLane == DrumLane.home,
        whiteOutline: true,
        child: _rosterLane(
          tokens: tokens,
          lane: DrumLane.home,
          title: controller.homeAbbr,
          players: controller.homeRoster,
          selectedIndex: _homeIndex,
        ),
      ),
      _columnShell(
        tokens: tokens,
        armed: _armedLane == DrumLane.verbs,
        accentOutline: true,
        child: _verbLane(tokens),
      ),
    ];
    if (!controller.singleTeamMode) {
      lanes.add(
        _columnShell(
          tokens: tokens,
          armed: _armedLane == DrumLane.away,
          whiteOutline: true,
          child: _rosterLane(
            tokens: tokens,
            lane: DrumLane.away,
            title: controller.awayAbbr,
            players: controller.awayRoster,
            selectedIndex: _awayIndex,
          ),
        ),
      );
    }
    return lanes;
  }

  @override
  Widget build(BuildContext context) {
    _repairIndices();
    if (controller.singleTeamMode && _armedLane == DrumLane.away) {
      _armedLane = DrumLane.verbs;
    }
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final lanes = _laneChildren(tokens);
    final body = widget.layout == DrumLayout.paged
        ? PageView(
            key: ValueKey(
              controller.singleTeamMode
                  ? 'paged-drum-picker-single'
                  : 'paged-drum-picker',
            ),
            controller: widget.pageController,
            onPageChanged: (index) {
              final max = lanes.length - 1;
              final lane = DrumLane.values[index.clamp(0, max)];
              _arm(lane, syncPage: false);
              widget.onPageChanged?.call(index);
            },
            children: lanes,
          )
        : Row(
            key: ValueKey(
              controller.singleTeamMode
                  ? 'desktop-drum-picker-single'
                  : 'desktop-drum-picker',
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lanes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                // Player / verbs / player → 35 / 30 / 35.
                Expanded(
                  flex: i == 1 ? 30 : 35,
                  child: lanes[i],
                ),
              ],
            ],
          );
    return Focus(
      autofocus: widget.layout == DrumLayout.sideBySide,
      onKeyEvent: _handleKey,
      child: body,
    );
  }

  Widget _columnShell({
    required FfTokens tokens,
    required bool armed,
    required Widget child,
    bool accentOutline = false,
    bool whiteOutline = false,
  }) {
    final outlined = accentOutline || whiteOutline || armed;
    // Don't clip the outer shell — that would cut off the glow.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(
          color: outlined ? tokens.accent : tokens.divider,
          width: 1,
        ),
        boxShadow: outlined ? FfTokens.accentButtonGlow(tokens.accent) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        child: child,
      ),
    );
  }

  Widget _header(
    FfTokens tokens,
    DrumLane lane,
    String title,
  ) {
    final isRoster = lane != DrumLane.verbs;
    const headerHeight = 32.0;
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title.toUpperCase(),
            style: isRoster
                ? FfTokens.teamAbbrLabel(color: tokens.text)
                : FfTokens.panelLabel(color: tokens.text),
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),
          if (isRoster) ...[
            const Spacer(),
            _GhostHeaderIcon(
              key: ValueKey('drum-number-mode-${lane.name}'),
              tooltip: 'Grid view',
              icon: PhosphorIconsRegular.squaresFour,
              active: _numberMode,
              tokens: tokens,
              onTap: () => setState(() {
                _numberMode = !_numberMode;
                if (_numberMode) {
                  _homeLetterFilter = null;
                  _awayLetterFilter = null;
                }
              }),
            ),
            if (!_numberMode) ...[
              _GhostHeaderIcon(
                key: ValueKey('drum-sort-${lane.name}'),
                tooltip: 'Sort by number',
                label: controller.rosterSortFieldLabel(),
                tokens: tokens,
                onTap: controller.cycleRosterSortField,
              ),
              _GhostHeaderIcon(
                key: ValueKey('drum-sort-dir-${lane.name}'),
                tooltip: controller.rosterSortAscending
                    ? 'Ascending'
                    : 'Descending',
                label: controller.rosterSortDirectionLabel(),
                tokens: tokens,
                onTap: controller.toggleRosterSortDirection,
              ),
            ],
            if (widget.onEditRosters != null)
              _GhostHeaderIcon(
                tooltip: 'Rename team',
                icon: PhosphorIconsRegular.pencilSimple,
                tokens: tokens,
                onTap: widget.onEditRosters!,
              ),
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
    final isHome = lane == DrumLane.home;
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
      final numberMode = _numberMode;
      final numberMetrics = numberMode ? _numberModeMetrics() : null;
      return Expanded(
        child: visiblePlayers.isEmpty
            ? Center(
                child: Text(
                  _filterFor(lane).text.trim().isNotEmpty ||
                          letterFilter != null
                      ? 'No match'
                      : 'No players',
                  style: tokens.metaStyle.copyWith(
                    color: tokens.text.withValues(alpha: 0.34),
                  ),
                ),
              )
            : numberMode
                ? _NumberRoster(
                    players: visiblePlayers,
                    // Keep home/away on the same grid so names don't
                    // disappear on only one side when rosters differ.
                    columns: numberMetrics!.columnCount,
                    layoutRowCount: numberMetrics.rowCount,
                    includeOtherRow: numberMetrics.needsOtherRow,
                    tokens: tokens,
                    isSelected: (player) => controller.isPlayerSelected(
                      player,
                      isHome: lane == DrumLane.home,
                    ),
                    onCommit: (player) =>
                        _commit(lane, rosterIndexOf(player)),
                    onPin: (player) => controller.togglePlayerPin(
                      player,
                      isHome: lane == DrumLane.home,
                    ),
                    onSecondaryTap: (player, position) => _editRosterPlayer(
                      context,
                      player: player,
                      isHome: lane == DrumLane.home,
                      position: position,
                    ),
                  )
                : widget.mode == DrumPickerMode.scroll && letterFilter != null
                ? _FilteredPlayerList(
                    letter: letterFilter,
                    players: visiblePlayers,
                    tokens: tokens,
                    nameFor: controller.playerListName,
                    isPinned: (player) => controller.isPlayerPinned(
                      player,
                      isHome: lane == DrumLane.home,
                    ),
                    onBack: () => setState(() {
                      if (lane == DrumLane.home) {
                        _homeLetterFilter = null;
                      } else {
                        _awayLetterFilter = null;
                      }
                    }),
                    onSelect: (player) => _commit(lane, rosterIndexOf(player)),
                    onPin: (player) => controller.togglePlayerPin(
                      player,
                      isHome: lane == DrumLane.home,
                    ),
                    onGoogle: (player) => openPlayerGoogleSearch(
                      fullName: player.fullName,
                      sportId: controller.sport,
                    ),
                    onReport: (player) => _reportRosterPlayer(
                      player: player,
                      isHome: lane == DrumLane.home,
                    ),
                    onEdit: (player, position) => _editRosterPlayer(
                      context,
                      player: player,
                      isHome: lane == DrumLane.home,
                      position: position,
                    ),
                  )
                : widget.mode == DrumPickerMode.scroll
                    ? _HoverPlayerList(
                        laneKey: lane.name,
                        players: visiblePlayers,
                        selectedIndex:
                            visibleSelectedIndex < 0 ? 0 : visibleSelectedIndex,
                        armed: _armedLane == lane,
                        tokens: tokens,
                        nameFor: controller.playerListName,
                        isSelected: (player) => controller.isPlayerSelected(
                          player,
                          isHome: lane == DrumLane.home,
                        ),
                        isPinned: (player) => controller.isPlayerPinned(
                          player,
                          isHome: lane == DrumLane.home,
                        ),
                        onTarget: (index) => _setIndex(
                            lane, rosterIndexOf(visiblePlayers[index])),
                        onCommit: (index) =>
                            _commit(lane, rosterIndexOf(visiblePlayers[index])),
                        onPin: (player) => controller.togglePlayerPin(
                          player,
                          isHome: lane == DrumLane.home,
                        ),
                        onGoogle: (player) => openPlayerGoogleSearch(
                          fullName: player.fullName,
                          sportId: controller.sport,
                        ),
                        onReport: (player) => _reportRosterPlayer(
                          player: player,
                          isHome: lane == DrumLane.home,
                        ),
                        onEditPlayer: (player, position) => _editRosterPlayer(
                          context,
                          player: player,
                          isHome: lane == DrumLane.home,
                          position: position,
                        ),
                      )
                    : _DrumWheel<Player>(
                        laneKey: lane.name,
                        items: visiblePlayers,
                        selectedIndex:
                            visibleSelectedIndex < 0 ? 0 : visibleSelectedIndex,
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

    final sortByName = controller.rosterSort != RosterSortMode.number;
    final showLetterRail = !_numberMode && sortByName;
    final scrubber = _RosterScrubber(
      players: players,
      activeIndex: selectedIndex,
      onLeft: true,
      activeLetter:
          widget.mode == DrumPickerMode.scroll ? (letterFilter ?? '#') : null,
      armed: _armedLane == lane,
      tokens: tokens,
      onSelect: (letter, index) {
        if (widget.mode == DrumPickerMode.scroll) {
          setState(() {
            if (lane == DrumLane.home) {
              _homeLetterFilter = (letter == '#' || _homeLetterFilter == letter)
                  ? null
                  : letter;
            } else {
              _awayLetterFilter = (letter == '#' || _awayLetterFilter == letter)
                  ? null
                  : letter;
            }
          });
        }
        _setIndex(lane, index);
      },
    );

    return Column(
      children: [
        _header(tokens, lane, title),
        PinnedPlayerBar(
          controller: controller,
          isHome: isHome,
          tokens: tokens,
          filter: QuietFilterField(
            key: ValueKey('drum-search-${lane.name}'),
            controller: _filterFor(lane),
            tokens: tokens,
            height: 24,
            onChanged: (_) => _onRosterFilterChanged(lane),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              if (showLetterRail) scrubber,
              playerList(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: CustomNameField(
            nameController: isHome
                ? _homeCustomNameController
                : _awayCustomNameController,
            jerseyController: isHome
                ? _homeCustomJerseyController
                : _awayCustomJerseyController,
            nameFocusNode:
                isHome ? _homeCustomNameFocus : _awayCustomNameFocus,
            jerseyFocusNode:
                isHome ? _homeCustomJerseyFocus : _awayCustomJerseyFocus,
            tokens: tokens,
            pinned: _customNamePinned(isHome: isHome),
            canUseLast: controller.canUseLastCustomPlayer,
            onChanged: () => setState(() {}),
            onSubmit: () => _submitCustomName(isHome: isHome),
            onTogglePin: () => _toggleCustomNamePin(isHome: isHome),
            onUseLast: () => _useLastCustomName(isHome: isHome),
          ),
        ),
      ],
    );
  }

  bool _customNamePinned({required bool isHome}) {
    final pinned = controller.pinnedPlayer;
    if (pinned == null || pinned.isHome != isHome) return false;
    final id = pinned.player.playerId?.trim();
    if (id != null && id.isNotEmpty) return false;
    final nameController =
        isHome ? _homeCustomNameController : _awayCustomNameController;
    final jerseyController =
        isHome ? _homeCustomJerseyController : _awayCustomJerseyController;
    final name = nameController.text.trim();
    if (name.isEmpty) return false;
    final jersey = jerseyController.text.trim();
    final player = controller.findRosterPlayer(
      isHome: isHome,
      fullName: name,
      jerseyNumber: jersey.isEmpty ? null : jersey,
    );
    if (player == null) return false;
    return controller.isPlayerPinned(player, isHome: isHome);
  }

  void _syncCustomNameFromPin({required bool isHome}) {
    final pinned = controller.pinnedPlayer;
    if (pinned == null || pinned.isHome != isHome) return;
    // Only mirror custom pins (no league playerId) into the footer field.
    final id = pinned.player.playerId?.trim();
    if (id != null && id.isNotEmpty) return;
    final nameFocus = isHome ? _homeCustomNameFocus : _awayCustomNameFocus;
    final jerseyFocus =
        isHome ? _homeCustomJerseyFocus : _awayCustomJerseyFocus;
    if (nameFocus.hasFocus || jerseyFocus.hasFocus) return;
    final nameController =
        isHome ? _homeCustomNameController : _awayCustomNameController;
    final jerseyController =
        isHome ? _homeCustomJerseyController : _awayCustomJerseyController;
    final name = pinned.player.fullName;
    final jersey = pinned.player.jerseyNumber ?? '';
    if (nameController.text == name && jerseyController.text == jersey) return;
    nameController.text = name;
    jerseyController.text = jersey;
  }

  void _showCustomNameError(String? error) {
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
    );
  }

  void _submitCustomName({required bool isHome}) {
    final nameController =
        isHome ? _homeCustomNameController : _awayCustomNameController;
    final jerseyController =
        isHome ? _homeCustomJerseyController : _awayCustomJerseyController;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    final jersey = jerseyController.text.trim();
    final error = controller.commitCustomPlayer(
      isHome: isHome,
      fullName: name,
      jerseyNumber: jersey.isEmpty ? null : jersey,
    );
    _showCustomNameError(error);
    setState(() {});
  }

  void _useLastCustomName({required bool isHome}) {
    if (!controller.canUseLastCustomPlayer) return;
    final nameController =
        isHome ? _homeCustomNameController : _awayCustomNameController;
    final jerseyController =
        isHome ? _homeCustomJerseyController : _awayCustomJerseyController;
    final nameFocus = isHome ? _homeCustomNameFocus : _awayCustomNameFocus;
    nameController.text = controller.lastCustomPlayerName;
    jerseyController.text = controller.lastCustomPlayerJersey;
    setState(() {});
    nameFocus.requestFocus();
  }

  void _toggleCustomNamePin({required bool isHome}) {
    final nameController =
        isHome ? _homeCustomNameController : _awayCustomNameController;
    final jerseyController =
        isHome ? _homeCustomJerseyController : _awayCustomJerseyController;
    if (nameController.text.trim().isEmpty &&
        controller.canUseLastCustomPlayer) {
      nameController.text = controller.lastCustomPlayerName;
      jerseyController.text = controller.lastCustomPlayerJersey;
    }
    final jersey = jerseyController.text.trim();
    final error = controller.toggleCustomPlayerPin(
      isHome: isHome,
      fullName: nameController.text,
      jerseyNumber: jersey.isEmpty ? null : jersey,
    );
    _showCustomNameError(error);
    setState(() {});
  }

  Future<void> _reportRosterPlayer({
    required Player player,
    required bool isHome,
  }) async {
    final team = isHome ? controller.homeTeam : controller.awayTeam;
    final abbr = isHome ? controller.homeAbbr : controller.awayAbbr;
    final teamName = team.trim().isEmpty ? abbr : team;
    await submitPlayerDataIssueReport(
      context: context,
      teamName: teamName,
      sportId: controller.sport,
      side: isHome ? 'home' : 'away',
      player: player,
    );
  }

  Future<void> _editRosterPlayer(
    BuildContext context, {
    required Player player,
    required bool isHome,
    required Offset position,
  }) async {
    final pinned = controller.isPlayerPinned(player, isHome: isHome);
    final action = await showCaptionV2PopupMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(pinned ? 'Unpin Player' : 'Pin Player'),
        ),
        const PopupMenuItem(value: 'edit', child: Text('Edit player…')),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'pin') {
      controller.togglePlayerPin(player, isHome: isHome);
      return;
    }
    if (action != 'edit') return;
    final result = await showCustomNameEntryDialog(
      context: context,
      teamLabel: isHome ? controller.homeAbbr : controller.awayAbbr,
      title: 'Edit player',
      confirmLabel: 'Save',
      initialName: player.fullName,
      initialJersey: player.jerseyNumber,
    );
    if (result == null || !context.mounted) return;
    final error = controller.updatePlayer(
      isHome: isHome,
      original: player,
      fullName: result.name,
      jerseyNumber: result.jersey,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
      );
    }
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
    void selectPinnedVerb(EffectiveVerb verb) {
      _arm(DrumLane.verbs);
      controller.selectVerb(verb.key);
    }

    return Column(
      children: [
        _header(tokens, DrumLane.verbs, 'VERBS'),
        Expanded(
          child: _VerbAccordion(
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
            onPinnedVerbTap: selectPinnedVerb,
            onVerbArmed: (index) {
              _arm(DrumLane.verbs);
              _setIndex(DrumLane.verbs, index);
              _commit(DrumLane.verbs, index);
            },
            onToggleFavorite: _toggleVerbFavorite,
          ),
        ),
        Divider(height: 1, color: tokens.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: _DrumCustomVerbField(
            textController: _customVerbController,
            focusNode: _customVerbFocusNode,
            tokens: tokens,
            pinned: controller.customVerbPinned,
            canUseLast: controller.lastCustomVerbPhrase.trim().isNotEmpty,
            onChanged: controller.setCustomVerbPhrase,
            onTogglePin: controller.toggleCustomVerbPin,
            onUseLast: controller.useLastCustomVerb,
          ),
        ),
      ],
    );
  }
}

class _DrumCustomVerbField extends StatelessWidget {
  const _DrumCustomVerbField({
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
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: pinned ? FfTokens.pinned : tokens.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              readOnly: pinned,
              maxLines: 1,
              onChanged: onChanged,
              spellCheckConfiguration: floSpellCheckConfiguration(),
              contextMenuBuilder: floSpellCheckContextMenuBuilder,
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
          _DrumCustomVerbAction(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            tooltip: 'Use last custom verb',
            tokens: tokens,
            enabled: canUseLast,
            onTap: onUseLast,
          ),
          _DrumCustomVerbAction(
            icon: pinned ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
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

class _DrumCustomVerbAction extends StatelessWidget {
  const _DrumCustomVerbAction({
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
          child: PhosphorIcon(
            icon,
            size: 14,
            color: enabled
                ? (selected ? FfTokens.pinned : tokens.textSecondary)
                : tokens.divider,
          ),
        ),
      ),
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
    required this.onPinnedVerbTap,
    required this.onVerbArmed,
    required this.onToggleFavorite,
  });

  static const preferredHeaderHeight = 34.0;
  static const minHeaderHeight = 28.0;
  /// Must match [_PinnedHintBar] fixed height (padding + label + bottom border).
  static const pinnedBarHeight = 26.0;
  static const rowHeight = 24.0;
  static const rbiExtrasHeight = 32.0;
  static const baseExtrasHeight = 32.0;
  static const celebrationExtrasHeight = 32.0;
  static const actionExtrasHeight = 36.0;
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
  final ValueChanged<EffectiveVerb> onPinnedVerbTap;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;

  String _displayCategory(String category) {
    final normalized = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return normalized.contains('nongame') ? 'Non-game' : category;
  }

  double _extrasHeightFor(String? key, {bool includeActions = true}) {
    if (key == null) return 0;
    var height = extrasDividerHeight;
    final needsRbi = controller.verbNeedsRbi(key);
    final needsBase = controller.verbNeedsBase(key);
    final needsCelebration = controller.verbNeedsCelebration(key);
    if (needsRbi) height += rbiExtrasHeight;
    if (needsBase) height += baseExtrasHeight;
    if (needsCelebration) height += celebrationExtrasHeight;
    final optionsPending =
        (needsRbi && key == 'Home Run' && controller.rbi < 1) ||
            (needsBase &&
                (controller.selectedBase == null ||
                    controller.selectedBase!.trim().isEmpty));
    final hasOptionRows = needsRbi || needsBase || needsCelebration;
    if (includeActions && !optionsPending) {
      height += actionExtrasHeight;
    } else if (!includeActions && !hasOptionRows) {
      // Pinned verb without option rows has no extras panel at all.
      return 0;
    }
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinned = controller.pinnedVerbDefinition;
        final pinnedSelected =
            pinned != null && selectedVerbKey == pinned.key;
        final openVerbs = collapsed
            ? const <EffectiveVerb>[]
            : (verbsByCategory[selectedCategory] ?? const <EffectiveVerb>[]);
        final openVerbCount = openVerbs.length;
        final selectedInOpen = !collapsed &&
            selectedVerbKey != null &&
            !pinnedSelected &&
            openVerbs.any((verb) => verb.key == selectedVerbKey);
        final extrasHeight =
            selectedInOpen ? _extrasHeightFor(selectedVerbKey) : 0.0;
        final pinnedExtras = pinnedSelected
            ? _extrasHeightFor(selectedVerbKey, includeActions: false)
            : 0.0;
        // Always reserve the pinned bar (title + verb on one row).
        final pinnedHeight = pinnedBarHeight + pinnedExtras;
        final openBodyHeight = openVerbCount * rowHeight + extrasHeight;
        final minContentHeight = categories.length * minHeaderHeight +
            openBodyHeight +
            pinnedHeight;
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final needsScroll =
            bounded && minContentHeight > constraints.maxHeight + 0.5;

        final double headerHeight;
        if (categories.isEmpty) {
          headerHeight = preferredHeaderHeight;
        } else if (needsScroll) {
          headerHeight = minHeaderHeight;
        } else {
          final availableForHeaders =
              constraints.maxHeight - openBodyHeight - pinnedHeight;
          headerHeight = (availableForHeaders / categories.length)
              .clamp(minHeaderHeight, preferredHeaderHeight);
        }

        // Re-check with the resolved header height — float/rounding can leave
        // a couple of pixels short of what the Column actually paints.
        final resolvedHeight = pinnedHeight +
            categories.length * headerHeight +
            openBodyHeight;
        final stillOverflows =
            bounded && resolvedHeight > constraints.maxHeight + 0.5;

        final column = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinnedVerbSlot(
              height: pinnedBarHeight,
              tokens: tokens,
              controller: controller,
              verb: pinned,
              selected: pinnedSelected,
              committed: pinnedSelected,
              showRbi: pinned != null &&
                  pinnedSelected &&
                  controller.verbNeedsRbi(pinned.key),
              showBase: pinned != null &&
                  pinnedSelected &&
                  controller.verbNeedsBase(pinned.key),
              showCelebration: pinned != null &&
                  pinnedSelected &&
                  controller.verbNeedsCelebration(pinned.key),
              rbi: controller.rbi,
              selectedBase: controller.selectedBase,
              celebrationType: controller.celebrationType,
              reactionOptions: pinned != null &&
                      pinnedSelected &&
                      controller.verbNeedsCelebration(pinned.key)
                  ? controller.reactionOptionsFor(pinned.key)
                  : const <String>[],
              onTap: pinned == null
                  ? null
                  : () => onPinnedVerbTap(pinned),
              onRbiChanged: controller.setRbi,
              onBaseChanged: controller.setSelectedBase,
              onCelebrationChanged: controller.setCelebrationType,
            ),
            for (final category in categories)
              _VerbAccordionSection(
                controller: controller,
                category: category,
                displayCategory: _displayCategory(category),
                verbs: verbsByCategory[category] ?? const <EffectiveVerb>[],
                headerHeight: stillOverflows ? minHeaderHeight : headerHeight,
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

        if (!needsScroll && !stillOverflows) return column;

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
    final isFavorites = category == 'Favorites';
    final labelColor = isFavorites
        ? FfTokens.favorites
        : (open ? tokens.text : tokens.textSecondary);
    final divider = isFavorites
        ? FfTokens.favoritesBorder
        : tokens.divider;
    return Column(
      children: [
        Material(
          color: isFavorites ? FfTokens.favoritesFill : Colors.transparent,
          child: InkWell(
            key: ValueKey('verb-accordion-$category'),
            onTap: onOpen,
            hoverColor: tokens.hover,
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
                        ? PhosphorIconsRegular.caretDown
                        : PhosphorIconsRegular.caretRight,
                    size: 14,
                    color: labelColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayCategory.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: FfTokens.categoryLabel(color: labelColor),
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
                  leadingPadding: 30,
                  fontSize: 13.5,
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
    this.fontSize = 13.5,
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
    // Only the committed/caption verb gets the teal selected fill.
    // Do not highlight the keyboard cursor index (often 0) when nothing is
    // selected — that made the top cascade verb look permanently selected.
    final committed = widget.selectedVerbKey == verb.key;
    final selected = committed;
    final showRbi = committed && widget.controller.verbNeedsRbi(verb.key);
    final showBase = committed && widget.controller.verbNeedsBase(verb.key);
    final showCelebration =
        committed && widget.controller.verbNeedsCelebration(verb.key);

    return _HoverVerbBlock(
      key: ValueKey('verb-hover-${verb.key}'),
      controller: widget.controller,
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

class _PinnedVerbSlot extends StatelessWidget {
  const _PinnedVerbSlot({
    required this.height,
    required this.tokens,
    required this.controller,
    required this.verb,
    required this.selected,
    required this.committed,
    required this.showRbi,
    required this.showBase,
    required this.showCelebration,
    required this.rbi,
    required this.selectedBase,
    required this.celebrationType,
    required this.reactionOptions,
    required this.onTap,
    required this.onRbiChanged,
    required this.onBaseChanged,
    required this.onCelebrationChanged,
  });

  final double height;
  final FfTokens tokens;
  final CaptionV2Controller controller;
  final EffectiveVerb? verb;
  final bool selected;
  final bool committed;
  final bool showRbi;
  final bool showBase;
  final bool showCelebration;
  final int rbi;
  final String? selectedBase;
  final String? celebrationType;
  final List<String> reactionOptions;
  final VoidCallback? onTap;
  final ValueChanged<int> onRbiChanged;
  final ValueChanged<String?> onBaseChanged;
  final ValueChanged<String?> onCelebrationChanged;

  @override
  Widget build(BuildContext context) {
    final hasVerb = verb != null;
    final hasOptionRows = showRbi || showBase || showCelebration;
    final bar = _PinnedHintBar(
      height: height,
      tokens: tokens,
      hasContent: hasVerb,
      child: Row(
        children: [
          Icon(
            hasVerb ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
            size: 11,
            color: tokens.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            'Pinned',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11.5,
              height: 1.0,
              fontWeight: FontWeight.w600,
              color: tokens.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hasVerb
                ? CmdClick(
                    key: ValueKey('verb-pinned-inline-${verb!.key}'),
                    onTap: onTap,
                    onCmdTap: () => controller.toggleVerbPin(verb!.key),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              verb!.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 11.5,
                                height: 1.0,
                                fontWeight: FontWeight.w500,
                                color: selected
                                    ? tokens.text
                                    : tokens.text.withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                          if (committed) ...[
                            const SizedBox(width: 4),
                            PhosphorIcon(PhosphorIconsRegular.check,
                              size: 12,
                              color: tokens.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (hasVerb)
            TextButton(
              onPressed: () => controller.toggleVerbPin(verb!.key),
              style: TextButton.styleFrom(
                foregroundColor: tokens.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Unpin',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: tokens.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );

    if (!hasOptionRows) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (showRbi)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 8, 1),
            child: RbiRow(
              value: rbi,
              compact: true,
              homeRunStyle: verb?.key == 'Home Run',
              onChanged: onRbiChanged,
            ),
          ),
        if (showBase)
          Padding(
            padding: EdgeInsets.fromLTRB(10, showRbi ? 4 : 3, 8, 1),
            child: BaseRow(
              value: selectedBase,
              compact: true,
              onChanged: onBaseChanged,
            ),
          ),
        if (showCelebration)
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              (showRbi || showBase) ? 4 : 3,
              8,
              2,
            ),
            child: CelebrationDropdown(
              compact: true,
              reactions: reactionOptions,
              celebrations: const <String>[],
              selected: celebrationType,
              onChanged: onCelebrationChanged,
            ),
          ),
      ],
    );
  }
}

class _HoverVerbBlock extends StatefulWidget {
  const _HoverVerbBlock({
    super.key,
    required this.controller,
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
    this.showSaveActions = true,
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final bool selected;
  final bool committed;
  final double leadingPadding;
  final double fontSize;
  final FfTokens tokens;
  final bool showSaveActions;
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
    final hasOptionRows =
        widget.showRbi || widget.showBase || widget.showCelebration;
    final optionsComplete = !(widget.showRbi &&
            widget.verb.key == 'Home Run' &&
            widget.rbi < 1) &&
        !(widget.showBase &&
            (widget.selectedBase == null ||
                widget.selectedBase!.trim().isEmpty));
    final showActions = widget.showSaveActions &&
        widget.committed &&
        (!hasOptionRows || optionsComplete);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VerbAccordionRow(
            controller: widget.controller,
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
          if (hasOptionRows || showActions) ...[
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
            if (showActions)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.leadingPadding,
                  hasOptionRows ? 4 : 3,
                  8,
                  2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _DrumVerbActionButton(
                        label: 'Save',
                        tokens: widget.tokens,
                        emphasized: !widget.controller.ftpModeEnabled,
                        onTap: () => widget.controller
                            .saveOrTransmitFromVerbMenu(transmit: false),
                      ),
                    ),
                    if (widget.controller.ftpModeEnabled) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DrumVerbActionButton(
                          label: 'FTP',
                          tokens: widget.tokens,
                          emphasized: true,
                          onTap: () => widget.controller
                              .saveOrTransmitFromVerbMenu(transmit: true),
                        ),
                      ),
                    ],
                  ],
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

class _DrumVerbActionButton extends StatelessWidget {
  const _DrumVerbActionButton({
    required this.label,
    required this.tokens,
    required this.emphasized,
    required this.onTap,
  });

  final String label;
  final FfTokens tokens;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized
          ? tokens.accent.withValues(alpha: 0.22)
          : tokens.selectedFill,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: emphasized
                  ? tokens.accent.withValues(alpha: 0.65)
                  : tokens.divider,
            ),
          ),
          child: Text(
            label,
            style: tokens.labelStyle.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tokens.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _VerbAccordionRow extends StatelessWidget {
  const _VerbAccordionRow({
    required this.controller,
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

  final CaptionV2Controller controller;
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
    final fill = selected
        ? tokens.selected
        : (hovered ? tokens.hover : null);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: CmdClick(
        key: ValueKey('verb-accordion-row-${verb.key}'),
        useInkWell: true,
        onTap: onTap,
        onCmdTap: () => controller.toggleVerbPin(verb.key),
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            height: _VerbAccordion.rowHeight,
            padding: EdgeInsets.only(left: leadingPadding - 6, right: 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(FfTokens.radiusRow),
              // Same selected outline as player rows: 2px accent left bar.
              border: selected
                  ? Border(
                      left: BorderSide(color: tokens.accent, width: 2),
                    )
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: controller.isVerbPinned(verb.key)
                      ? PhosphorIcon(PhosphorIconsFill.pushPin,
                          size: 10,
                          color: FfTokens.pinned,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    verb.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: FfTokens.rosterName(
                      color: tokens.text,
                      selected: selected,
                    ),
                  ),
                ),
                if (committed) ...[
                  const SizedBox(width: 4),
                  PhosphorIcon(PhosphorIconsRegular.check,
                    size: 12,
                    color: tokens.textSecondary,
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
    final action = await showCaptionV2PopupMenu<String>(
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
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit verb…'),
        ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case 'favorite':
        onToggleFavorite();
        break;
      case 'pin':
        controller.toggleVerbPin(verb.key);
        break;
      case 'edit':
        await showCaptionV2VerbEditor(context, controller, verb.key);
        break;
    }
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
    this.isPinned,
    this.onPin,
    this.onGoogle,
    this.onReport,
    this.onEdit,
  });

  final String letter;
  final List<Player> players;
  final FfTokens tokens;
  final String Function(Player) nameFor;
  final VoidCallback onBack;
  final ValueChanged<Player> onSelect;
  final bool Function(Player)? isPinned;
  final ValueChanged<Player>? onPin;
  final ValueChanged<Player>? onGoogle;
  final ValueChanged<Player>? onReport;
  final void Function(Player player, Offset globalPosition)? onEdit;

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
            icon: const PhosphorIcon(PhosphorIconsRegular.arrowLeft, size: 13),
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
            itemExtent: 22,
            itemBuilder: (context, index) {
              final player = players[index];
              return _HoverablePlayerActionsRow(
                tokens: tokens,
                jersey: player.jerseyNumber ?? '—',
                name: nameFor(player),
                pinned: isPinned?.call(player) ?? false,
                onSelect: () => onSelect(player),
                onPin: onPin == null ? null : () => onPin!(player),
                onGoogle: onGoogle == null ? null : () => onGoogle!(player),
                onReport: onReport == null ? null : () => onReport!(player),
                onSecondaryTapDown: onEdit == null
                    ? null
                    : (details) => onEdit!(player, details.globalPosition),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NumberGridMetrics {
  const _NumberGridMetrics({
    required this.columnCount,
    required this.rowCount,
    required this.needsOtherRow,
  });

  final int columnCount;
  final int rowCount;
  final bool needsOtherRow;
}

class _NumberRoster extends StatelessWidget {
  const _NumberRoster({
    required this.players,
    required this.columns,
    required this.layoutRowCount,
    required this.includeOtherRow,
    required this.tokens,
    required this.isSelected,
    required this.onCommit,
    this.onPin,
    this.onSecondaryTap,
  });

  final List<Player> players;
  final int columns;
  final int layoutRowCount;
  final bool includeOtherRow;
  final FfTokens tokens;
  final bool Function(Player player) isSelected;
  final ValueChanged<Player> onCommit;
  final ValueChanged<Player>? onPin;
  final void Function(Player player, Offset globalPosition)? onSecondaryTap;

  /// Always 4 across. Small screens: slight rectangle; larger: square.
  static const int minColumns = 4;
  static const int maxColumns = 4;
  static const double minCell = 44.0;
  static const double maxCell = 140.0;
  static const double maxJerseyFont = 28.0;
  /// Wider-than-tall aspect used at small sizes (W/H).
  static const double smallAspect = 1.28;
  /// Below this width → full rectangle; above → full square.
  static const double rectBlendStart = 58.0;
  static const double squareBlendEnd = 96.0;

  static int? _jersey(Player player) =>
      int.tryParse(player.jerseyNumber?.trim() ?? '');

  static String _lastName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return player.fullName;
    return parts.sublist(1).join(' ');
  }

  static int _wrappedRows(int count, int perRow) =>
      count <= 0 ? 0 : ((count + perRow - 1) ~/ perRow);

  static List<List<Player>> _chunk(List<Player> players, int perRow) {
    if (players.isEmpty) return const [];
    final out = <List<Player>>[];
    for (var i = 0; i < players.length; i += perRow) {
      final end = i + perRow;
      out.add(players.sublist(i, end > players.length ? players.length : end));
    }
    return out;
  }

  /// Band key for 0–19, 20–39, … 80–99.
  static int _bandKey(int number) => (number ~/ 20) * 20;

  /// Double-decade bands (0–19 … 80–99) plus an optional catch-all.
  static _NumberGridMetrics gridMetrics(List<Player> players) {
    final bands = <int, int>{};
    var other = 0;
    for (final player in players) {
      final number = _jersey(player);
      if (number == null || number < 0 || number > 99) {
        other++;
        continue;
      }
      final key = _bandKey(number);
      bands[key] = (bands[key] ?? 0) + 1;
    }
    var columnCount = 1;
    for (final count in bands.values) {
      if (count > columnCount) columnCount = count;
    }
    if (other > columnCount) columnCount = other;
    // Estimate with minColumns; LayoutBuilder may use more when wide.
    const perRow = minColumns;
    var visualRows = 0;
    for (final count in bands.values) {
      visualRows += _wrappedRows(count, perRow);
    }
    if (other > 0) visualRows += _wrappedRows(other, perRow);
    return _NumberGridMetrics(
      columnCount: columnCount.clamp(1, maxColumns),
      rowCount: visualRows.clamp(1, 40),
      needsOtherRow: other > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final byBand = <int, List<Player>>{};
    final other = <Player>[];
    for (final player in players) {
      final number = _jersey(player);
      if (number == null || number < 0 || number > 99) {
        other.add(player);
        continue;
      }
      byBand.putIfAbsent(_bandKey(number), () => []).add(player);
    }
    for (final group in byBand.values) {
      group.sort((a, b) {
        final byNumber = _jersey(a)!.compareTo(_jersey(b)!);
        if (byNumber != 0) return byNumber;
        return a.fullName.compareTo(b.fullName);
      });
    }
    other.sort((a, b) => a.fullName.compareTo(b.fullName));

    // Unchunked band groups — wrap count decided from available width.
    final bandTitles = <String>[];
    final bandGroups = <List<Player>>[];
    for (var band = 0; band <= 80; band += 20) {
      final group = byBand[band];
      if (group == null || group.isEmpty) continue;
      bandTitles.add('$band–${band + 19}');
      bandGroups.add(group);
    }
    if (includeOtherRow && other.isNotEmpty) {
      bandTitles.add('Other');
      bandGroups.add(other);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 10.0;
        const gapX = 4.0;
        const gapY = 4.0;
        const dividerH = 1.0;
        const dividerPad = 6.0;
        const titleW = 20.0;
        const titleGap = 4.0;
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (!maxW.isFinite || !maxH.isFinite || maxW <= 0 || maxH <= 0) {
          return const SizedBox.shrink();
        }

        final availW = (maxW - pad * 2).clamp(1.0, 10000.0);
        // Tiny safety so rounding/padding can't push past the viewport.
        final availH = (maxH - pad * 2 - 2.0).clamp(1.0, 10000.0);
        final gridW = (availW - titleW - titleGap).clamp(1.0, 10000.0);

        // Always 4 across — slight rectangles when small, squares when large.
        final dividerCount =
            bandGroups.length > 1 ? bandGroups.length - 1 : 0;
        final dividerSpace = dividerCount * (dividerH + dividerPad * 2);
        const perRow = maxColumns;
        final bands = [
          for (final group in bandGroups) _chunk(group, perRow),
        ];

        var actualRows = 0;
        for (final band in bands) {
          actualRows += band.length;
        }
        final rows =
            layoutRowCount > actualRows ? layoutRowCount : actualRows;
        final rowGaps = gapY * (rows > 1 ? rows - 1 : 0);
        final colGaps = gapX * (perRow > 1 ? perRow - 1 : 0);
        final sideW = ((gridW - colGaps) / perRow).clamp(1.0, maxCell);
        final sideH =
            ((availH - rowGaps - dividerSpace) / rows).clamp(1.0, maxCell);

        // Rectangle: fill width, a bit shorter. Square: equal side.
        final rectW = sideW;
        final rectH = (sideH < sideW / smallAspect)
            ? sideH
            : (sideW / smallAspect).clamp(minCell, maxCell);
        final squareSide =
            (sideW < sideH ? sideW : sideH).clamp(minCell, maxCell);

        // 0 = small/rect, 1 = large/square.
        final blend = ((squareSide - rectBlendStart) /
                (squareBlendEnd - rectBlendStart))
            .clamp(0.0, 1.0);
        final cellW = rectW + (squareSide - rectW) * blend;
        final cellH = rectH + (squareSide - rectH) * blend;
        final showNames = cellH >= 20;
        // Bump type a bit once the window is wide enough (~1350+).
        final windowW = MediaQuery.sizeOf(context).width;
        final wideBoost = ((windowW - 1200) / (1350 - 1200)).clamp(0.0, 1.0);
        final nameScale = 0.16 + 0.04 * wideBoost;
        final jerseyScale = showNames
            ? 0.38 + 0.06 * wideBoost
            : 0.52 + 0.06 * wideBoost;
        final nameSize =
            (cellH * nameScale).clamp(8.0, 14.0 + 3.0 * wideBoost);
        // One shared size for every tile (no per-number FittedBox scaling).
        final jerseySize = (cellH * jerseyScale)
            .clamp(10.0, maxJerseyFont + 4.0 * wideBoost);

        if (bands.isEmpty) {
          return const SizedBox.expand();
        }

        Widget bandTitle(String title, double bandHeight) {
          // Rotated label must fit inside bandHeight or short bands overlap.
          return SizedBox(
            width: titleW,
            height: bandHeight,
            child: ClipRect(
              child: Center(
                // quarterTurns: 1 → reads top→bottom so lower number is on top.
                child: RotatedBox(
                  quarterTurns: 1,
                  child: SizedBox(
                    width: bandHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: tokens.microStyle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          height: 1,
                          fontSize: 13,
                          shadows: [
                            Shadow(
                              color: Colors.white.withValues(alpha: 0.45),
                              blurRadius: 7,
                            ),
                            Shadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Column(
            children: [
              for (var b = 0; b < bands.length; b++) ...[
                if (b > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: dividerPad),
                    child: Container(
                      height: dividerH,
                      width: double.infinity,
                      color: tokens.accent.withValues(alpha: 0.75),
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final bandRows = bands[b].length;
                    final bandHeight = cellH * bandRows +
                        gapY * (bandRows > 1 ? bandRows - 1 : 0);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bandTitle(bandTitles[b], bandHeight),
                        const SizedBox(width: titleGap),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var r = 0; r < bands[b].length; r++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: r == 0 ? 0 : gapY / 2,
                                    bottom: r == bands[b].length - 1
                                        ? 0
                                        : gapY / 2,
                                  ),
                                  child: SizedBox(
                                    height: cellH,
                                    child: Row(
                                      children: [
                                        for (var slot = 0;
                                            slot < bands[b][r].length;
                                            slot++) ...[
                                          if (slot > 0) SizedBox(width: gapX),
                                          SizedBox(
                                            width: cellW,
                                            height: cellH,
                                            child: _NumberCell(
                                              player: bands[b][r][slot],
                                              lastName: _lastName(
                                                bands[b][r][slot],
                                              ),
                                              selected: isSelected(
                                                bands[b][r][slot],
                                              ),
                                              tokens: tokens,
                                              width: cellW,
                                              height: cellH,
                                              nameSize: nameSize,
                                              jerseySize: jerseySize,
                                              showName: showNames,
                                              onTap: () => onCommit(
                                                bands[b][r][slot],
                                              ),
                                              onPin: onPin == null
                                                  ? null
                                                  : () => onPin!(
                                                        bands[b][r][slot],
                                                      ),
                                              onSecondaryTap:
                                                  onSecondaryTap == null
                                                      ? null
                                                      : (position) =>
                                                          onSecondaryTap!(
                                                            bands[b][r]
                                                                [slot],
                                                            position,
                                                          ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NumberCell extends StatefulWidget {
  const _NumberCell({
    required this.player,
    required this.lastName,
    required this.selected,
    required this.tokens,
    required this.width,
    required this.height,
    required this.nameSize,
    required this.jerseySize,
    required this.showName,
    required this.onTap,
    this.onPin,
    this.onSecondaryTap,
  });

  final Player player;
  final String lastName;
  final bool selected;
  final FfTokens tokens;
  final double width;
  final double height;
  final double nameSize;
  final double jerseySize;
  final bool showName;
  final VoidCallback onTap;
  final VoidCallback? onPin;
  final ValueChanged<Offset>? onSecondaryTap;

  @override
  State<_NumberCell> createState() => _NumberCellState();
}

class _NumberCellState extends State<_NumberCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final selected = widget.selected;
    final width = widget.width;
    final height = widget.height;
    final showName = widget.showName;
    final nameSize = widget.nameSize;
    final jerseySize = widget.jerseySize;
    final hovering = _hovered;
    final glowColor = hovering ? Colors.white : FfTokens.panelOutline;
    final borderColor = hovering
        ? Colors.white.withValues(alpha: 0.92)
        : FfTokens.panelOutline;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: FfTokens.accentButtonGlow(glowColor),
        ),
        child: Material(
          color: selected
              ? tokens.accent.withValues(alpha: 0.18)
              : tokens.elevated,
          borderRadius: BorderRadius.circular(4),
          child: CmdClick(
            onTap: widget.onTap,
            onCmdTap: widget.onPin,
            onSecondaryTapDown: widget.onSecondaryTap == null
                ? null
                : (details) =>
                    widget.onSecondaryTap!(details.globalPosition),
            child: SizedBox(
              height: height,
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: LayoutBuilder(
                    builder: (context, cell) {
                      const nameGap = 1.0;
                      final nameH = showName ? nameSize : 0.0;
                      // Keep a little inset so numbers don't fill the whole band.
                      final numberH = ((cell.maxHeight -
                                  nameH -
                                  (showName ? nameGap : 0.0)) *
                              0.88 -
                              5.0)
                          .clamp(1.0, cell.maxHeight);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: numberH,
                            width: cell.maxWidth,
                            child: Center(
                              child: Text(
                                widget.player.jerseyNumber ?? '—',
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: tokens.jerseyStyle.copyWith(
                                  fontSize: jerseySize,
                                  height: 1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: selected
                                      ? tokens.accent
                                      : tokens.text,
                                  shadows: [
                                    Shadow(
                                      color:
                                          glowColor.withValues(alpha: 0.85),
                                      blurRadius: 10,
                                    ),
                                    Shadow(
                                      color:
                                          glowColor.withValues(alpha: 0.45),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (showName) ...[
                            const SizedBox(height: nameGap),
                            SizedBox(
                              height: nameH,
                              width: cell.maxWidth,
                              child: Center(
                                child: Text(
                                  widget.lastName,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: FfTokens.labelFamily,
                                    fontSize: nameSize,
                                    height: 1,
                                    fontWeight: FontWeight.w500,
                                    color: selected
                                        ? tokens.text
                                        : tokens.textSecondary,
                                    shadows: [
                                      Shadow(
                                        color:
                                            glowColor.withValues(alpha: 0.45),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
    this.isPinned,
    this.onPin,
    this.onGoogle,
    this.onReport,
    this.onEditPlayer,
  });

  final String laneKey;
  final List<Player> players;
  final int selectedIndex;
  final bool armed;
  final FfTokens tokens;
  final String Function(Player) nameFor;
  final bool Function(Player) isSelected;
  final bool Function(Player)? isPinned;
  final ValueChanged<int> onTarget;
  final ValueChanged<int> onCommit;
  final ValueChanged<Player>? onPin;
  final ValueChanged<Player>? onGoogle;
  final ValueChanged<Player>? onReport;
  final void Function(Player player, Offset globalPosition)? onEditPlayer;

  @override
  State<_HoverPlayerList> createState() => _HoverPlayerListState();
}

class _HoverPlayerListState extends State<_HoverPlayerList> {
  static const _itemExtent = 22.0;
  static const _magDuration = Duration(milliseconds: 40);
  final ScrollController _scrollController = ScrollController();
  double? _pointerY;
  bool _hovering = false;
  /// Local focal row for instant mag — parent [selectedIndex] can lag a frame.
  int? _focalIndex;

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
    if (_focalIndex != index) {
      setState(() => _focalIndex = index);
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
        _focalIndex = null;
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
          final focal = index == (_focalIndex ?? widget.selectedIndex);
          final selected = widget.isSelected(player);
          final pinned = widget.isPinned?.call(player) ?? false;
          final showActions = focal && _hovering;
          return CmdClick(
            onTap: () {
              setState(() => _focalIndex = index);
              widget.onTarget(index);
              widget.onCommit(index);
            },
            onCmdTap: widget.onPin == null
                ? null
                : () {
                    setState(() => _focalIndex = index);
                    widget.onTarget(index);
                    widget.onPin!(player);
                  },
            onSecondaryTapDown: widget.onEditPlayer == null
                ? null
                : (details) =>
                    widget.onEditPlayer!(player, details.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedContainer(
                key: ValueKey(
                  'scroll-${widget.laneKey}-player-$index',
                ),
                duration: _magDuration,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? widget.tokens.selected
                      : (focal && _hovering
                          ? widget.tokens.hover
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(FfTokens.radiusRow),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        player.jerseyNumber ?? '—',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                        style: FfTokens.rosterJersey(
                          color: widget.tokens.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.nameFor(player),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: FfTokens.rosterName(
                          color: widget.tokens.text,
                          selected: selected,
                        ),
                      ),
                    ),
                    if (showActions) ...[
                      if (widget.onPin != null)
                        _PlayerMenuHoverAction(
                          tooltip: pinned
                              ? 'Unpin for next frames'
                              : 'Pin for next frames',
                          icon: PhosphorIconsFill.pushPin,
                          color: FfTokens.pinned,
                          onTap: () => widget.onPin!(player),
                        ),
                      if (widget.onGoogle != null)
                        _PlayerMenuHoverAction(
                          tooltip: 'Google this player',
                          icon: PhosphorIconsRegular.magnifyingGlass,
                          color: widget.tokens.textSecondary,
                          onTap: () => widget.onGoogle!(player),
                        ),
                      if (widget.onReport != null)
                        _PlayerMenuHoverAction(
                          tooltip: 'Report wrong number or spelling',
                          icon: PhosphorIconsRegular.flag,
                          color: widget.tokens.textSecondary,
                          onTap: () => widget.onReport!(player),
                        ),
                    ] else if (pinned) ...[
                      const SizedBox(width: 2),
                      PhosphorIcon(PhosphorIconsFill.pushPin,
                        size: 11,
                        color: FfTokens.pinned,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact hover actions for filtered letter lists.
class _HoverablePlayerActionsRow extends StatefulWidget {
  const _HoverablePlayerActionsRow({
    required this.tokens,
    required this.jersey,
    required this.name,
    required this.pinned,
    required this.onSelect,
    this.onPin,
    this.onGoogle,
    this.onReport,
    this.onSecondaryTapDown,
  });

  final FfTokens tokens;
  final String jersey;
  final String name;
  final bool pinned;
  final VoidCallback onSelect;
  final VoidCallback? onPin;
  final VoidCallback? onGoogle;
  final VoidCallback? onReport;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<_HoverablePlayerActionsRow> createState() =>
      _HoverablePlayerActionsRowState();
}

class _HoverablePlayerActionsRowState
    extends State<_HoverablePlayerActionsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showActions = _hovered &&
        (widget.onPin != null ||
            widget.onGoogle != null ||
            widget.onReport != null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: CmdClick(
        onTap: widget.onSelect,
        onCmdTap: widget.onPin,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _hovered ? widget.tokens.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(FfTokens.radiusRow),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    widget.jersey,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    style: FfTokens.rosterJersey(
                      color: widget.tokens.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: FfTokens.rosterName(
                      color: widget.tokens.text,
                      selected: false,
                    ),
                  ),
                ),
                if (showActions) ...[
                  if (widget.onPin != null)
                    _PlayerMenuHoverAction(
                      tooltip: widget.pinned
                          ? 'Unpin for next frames'
                          : 'Pin for next frames',
                      icon: PhosphorIconsFill.pushPin,
                      color: FfTokens.pinned,
                      onTap: widget.onPin!,
                    ),
                  if (widget.onGoogle != null)
                    _PlayerMenuHoverAction(
                      tooltip: 'Google this player',
                      icon: PhosphorIconsRegular.magnifyingGlass,
                      color: widget.tokens.textSecondary,
                      onTap: widget.onGoogle!,
                    ),
                  if (widget.onReport != null)
                    _PlayerMenuHoverAction(
                      tooltip: 'Report wrong number or spelling',
                      icon: PhosphorIconsRegular.flag,
                      color: widget.tokens.textSecondary,
                      onTap: widget.onReport!,
                    ),
                ] else if (widget.pinned) ...[
                  const SizedBox(width: 2),
                  PhosphorIcon(PhosphorIconsFill.pushPin,
                    size: 11,
                    color: FfTokens.pinned,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerMenuHoverAction extends StatelessWidget {
  const _PlayerMenuHoverAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: PhosphorIcon(icon, size: 12, color: color),
          ),
        ),
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
  static const _animationDuration = Duration(milliseconds: 110);
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
                PhosphorIcon(PhosphorIconsRegular.check,
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

class _PinnedHintBar extends StatefulWidget {
  const _PinnedHintBar({
    required this.tokens,
    required this.hasContent,
    required this.child,
    this.height,
    this.hint = '· ⌘-click a verb to pin',
  });

  final FfTokens tokens;
  final bool hasContent;
  final Widget child;
  final double? height;
  final String hint;

  @override
  State<_PinnedHintBar> createState() => _PinnedHintBarState();
}

class _PinnedHintBarState extends State<_PinnedHintBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: widget.height ?? _VerbAccordion.pinnedBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.hasContent
                  ? FfTokens.pinnedDivider
                  : widget.tokens.divider,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            widget.child,
            if (!widget.hasContent)
              Positioned(
                left: 72,
                right: 8,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 1 : 0,
                    child: Text(
                      widget.hint,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11.5,
                        height: 1.0,
                        fontWeight: FontWeight.w400,
                        color: widget.tokens.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GhostHeaderIcon extends StatefulWidget {
  const _GhostHeaderIcon({
    super.key,
    required this.tooltip,
    required this.tokens,
    required this.onTap,
    this.icon,
    this.label,
    this.active = false,
  });

  final String tooltip;
  final FfTokens tokens;
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final bool active;

  @override
  State<_GhostHeaderIcon> createState() => _GhostHeaderIconState();
}

class _GhostHeaderIconState extends State<_GhostHeaderIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered || widget.active
        ? widget.tokens.text
        : widget.tokens.textSecondary;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? widget.tokens.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: widget.icon != null
                ? PhosphorIcon(widget.icon!, size: 13, color: color)
                : Text(
                    widget.label ?? '',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: color,
                    ),
                  ),
          ),
        ),
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
                      fontFamily: FfTokens.fontFamily,
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
