import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_index_filter_mode.dart';
import '../../../flo_layout_constants.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/mac_spell_check_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/aa_text_size_control.dart';
import '../widgets/base_row.dart';
import '../widgets/celebration_dropdown.dart';
import '../widgets/custom_name_entry.dart';
import '../widgets/pinned_player_bar.dart';
import '../widgets/team_players_button.dart';
import '../widgets/quiet_filter_field.dart';
import '../widgets/rbi_row.dart';
import '../widgets/verb_tile.dart';
import 'caption_v2_verb_editor.dart';
import 'verb_accordion.dart';
import 'verb_index_panel.dart';
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
    this.compactMobile = false,
    this.numberColumns,
  });

  final CaptionV2Controller controller;
  final DrumPickerMode mode;
  final DrumLayout layout;
  final ValueChanged<DrumPickerMode>? onModeChanged;
  final VoidCallback? onExit;
  final VoidCallback? onEditRosters;
  final PageController? pageController;
  final ValueChanged<int>? onPageChanged;

  /// Mobile stack: denser roster grid (5×56) and taller verb rows.
  final bool compactMobile;

  /// Override numbers-mode column count (mobile mock uses 5).
  final int? numberColumns;

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
  /// Squares across each numbers-mode row. Fewer columns means larger squares.
  late int _numberColumns;
  bool? _wasCompactForNumberFit;
  bool _verbAccordionCollapsed = false;
  int? _appliedCascadeLimit;
  final Set<String> _extraOpenVerbCategories = {};
  final _homeFilter = TextEditingController();
  final _awayFilter = TextEditingController();
  final _verbFilter = TextEditingController();
  final _verbFilterFocus = FocusNode(debugLabel: 'Drum verb filter');
  final _verbIndexKey = GlobalKey<VerbIndexPanelState>();
  final _azListBodyKey = GlobalKey(debugLabel: 'Drum A–Z verb list body');
  final _homeRosterBodyKey = GlobalKey(debugLabel: 'Drum home roster body');
  final _awayRosterBodyKey = GlobalKey(debugLabel: 'Drum away roster body');
  final _customVerbController = TextEditingController();
  final _customVerbFocusNode = FocusNode(debugLabel: 'Drum custom verb');
  int _seenPlayerSearchClearGeneration = -1;
  int _verbMatchCount = 0;

  CaptionV2Controller get controller => widget.controller;

  List<String> get _categories => controller.verbListAll
      ? const ['All']
      : verbCategoriesForDisplay(controller.verbCategories);

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
    final query = _verbFilter.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? verbs
        : verbs
            .where((verb) => verb.label.toLowerCase().contains(query))
            .toList(growable: false);
    final sorted = [...filtered]..sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    _numberColumns = widget.numberColumns ??
        (widget.compactMobile ? 5 : _NumberRoster.defaultColumns);
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
    _verbFilter.dispose();
    _verbFilterFocus.dispose();
    _customVerbFocusNode.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncCustomVerbField();
    final generation = controller.playerSearchClearGeneration;
    if (generation != _seenPlayerSearchClearGeneration) {
      _seenPlayerSearchClearGeneration = generation;
      if (_homeFilter.text.isNotEmpty) _homeFilter.clear();
      if (_awayFilter.text.isNotEmpty) _awayFilter.clear();
      _homeLetterFilter = null;
      _awayLetterFilter = null;
    }
    if (_appliedCascadeLimit != controller.verbCascadeLimit) {
      _appliedCascadeLimit = controller.verbCascadeLimit;
      if (controller.verbCascadeLimit <= CaptionV2Controller.verbCascadeNone) {
        _verbAccordionCollapsed = true;
        _extraOpenVerbCategories.clear();
      } else {
        _trimOpenCategories();
      }
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

  void _trimOpenCategories() {
    trimOpenVerbCategories(
      _extraOpenVerbCategories,
      controller.cascadeLimitFor(_categories.length),
    );
  }

  Set<String> get _openVerbCategories {
    if (controller.verbListAll) return {'All'};
    if (!controller.verbMultiOpen) {
      if (_verbAccordionCollapsed) return {};
      return {_category};
    }
    return {
      if (!_verbAccordionCollapsed) _category,
      ..._extraOpenVerbCategories,
    };
  }

  void _selectCategory(String category) {
    if (controller.verbMultiOpen && category != _category) {
      setState(() {
        if (!_extraOpenVerbCategories.remove(category)) {
          _extraOpenVerbCategories.add(category);
          _trimOpenCategories();
        }
      });
      return;
    }
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
      _extraOpenVerbCategories.remove(category);
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
      final previous = _category;
      controller.setVerbCategory(nextCategory);
      setState(() {
        if (controller.verbMultiOpen) {
          _extraOpenVerbCategories.add(previous);
          _extraOpenVerbCategories.remove(nextCategory);
          _trimOpenCategories();
        }
        _verbAccordionCollapsed = false;
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

  void _stepNumberColumns(int delta) {
    setState(() {
      _numberColumns = (_numberColumns + delta).clamp(
        _NumberRoster.minColumns,
        _NumberRoster.maxColumns,
      );
    });
  }

  /// Pick the fewest columns (largest squares) that still fit the taller
  /// roster into the on-screen player box.
  void _fitNumberColumns() {
    final homeBox =
        _homeRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final awayBox =
        _awayRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final box = (homeBox != null && homeBox.hasSize)
        ? homeBox
        : (awayBox != null && awayBox.hasSize)
            ? awayBox
            : null;
    if (box == null) return;

    final homePlayers = _visiblePlayersFor(DrumLane.home);
    final awayPlayers = _visiblePlayersFor(DrumLane.away);
    final players = homePlayers.length >= awayPlayers.length
        ? homePlayers
        : awayPlayers;
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortest / 1000.0).clamp(0.62, 1.0);
    final best = _NumberRoster.bestColumnsFor(
      width: box.size.width,
      height: box.size.height,
      players: players,
      includeOtherRow: true,
      showSubjects: true,
      scale: scale,
    );
    if (best == _numberColumns) return;
    setState(() => _numberColumns = best);
  }

  void _fitNumberColumnsWhenReady({int attempt = 0}) {
    if (!_numberMode || !mounted) return;
    final homeBox =
        _homeRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final awayBox =
        _awayRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final ready = (homeBox != null && homeBox.hasSize) ||
        (awayBox != null && awayBox.hasSize);
    if (!ready) {
      if (attempt >= 8) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitNumberColumnsWhenReady(attempt: attempt + 1),
      );
      return;
    }
    _fitNumberColumns();
  }

  Future<void> _fitVerbText() async {
    if (controller.verbListAll) {
      await _fitAzVerbFont();
    } else {
      await _verbIndexKey.currentState?.fitToBox();
    }
  }

  /// Largest A–Z list font step whose rows still fit the verb list height.
  Future<void> _fitAzVerbFont() async {
    final box =
        _azListBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final available = box.size.height;
    if (available <= 0) return;

    final dens = floVerbIndexDensity(
      MediaQuery.sizeOf(context),
      controller.verbIndexDensity,
    );
    final heightScale = switch (dens) {
      0 => 0.88,
      2 => 1.18,
      _ => 1.0,
    };
    final searching = _verbFilter.text.trim().isNotEmpty;
    final applyModeFilter = !searching;
    final byCategory = controller.verbIndexSortByCategory;
    final bands = byCategory
        ? _azCategoryBands(applyFilter: applyModeFilter)
        : null;
    final listVerbs = byCategory
        ? [for (final band in bands!) ...band.$2]
        : (applyModeFilter ? _azApplyFilterMode(_verbs) : _verbs);
    if (listVerbs.isEmpty) return;

    final headerCount = byCategory
        ? (bands?.length ?? 0)
        : verbLetterBands(listVerbs).length;
    const headerH = 14.0;

    var best = CaptionV2Controller.verbFontStepMin;
    for (var step = CaptionV2Controller.verbFontStepMax;
        step >= CaptionV2Controller.verbFontStepMin;
        step--) {
      final scale = 1 +
          step *
              (CaptionV2Controller.verbFontStepPx /
                  CaptionV2Controller.verbFontBasePx);
      final rowH = _VerbAccordion.rowHeight * scale * heightScale;
      final needed = listVerbs.length * rowH +
          headerCount * (_VerbAccordion.letterGroupGap + headerH);
      if (needed <= available + 2) {
        best = step;
        break;
      }
    }
    await controller.setVerbFontStep(best);
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

  /// Arrow / Enter while the verb search field is focused in A–Z list layout.
  KeyEventResult _onAzListFilterKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _arm(DrumLane.verbs);
      _spin(DrumLane.verbs, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _arm(DrumLane.verbs);
      _spin(DrumLane.verbs, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _arm(DrumLane.verbs);
      if (_verbs.isEmpty) return KeyEventResult.handled;
      final index = _verbIndex.clamp(0, _verbs.length - 1);
      controller.selectVerb(_verbs[index].key);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_verbFilter.text.isNotEmpty) {
        _verbFilter.clear();
        setState(() => _verbMatchCount = 0);
        return KeyEventResult.handled;
      }
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
        // No teal outline around the verb pane.
        armed: false,
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
    _trimOpenCategories();
    _repairIndices();
    if (controller.singleTeamMode && _armedLane == DrumLane.away) {
      _armedLane = DrumLane.verbs;
    }
    final compact = floWindowIsCompact(MediaQuery.sizeOf(context));
    final firstCompactPass = _wasCompactForNumberFit == null && compact;
    final compactChanged =
        _wasCompactForNumberFit != null && _wasCompactForNumberFit != compact;
    _wasCompactForNumberFit = compact;
    if (_numberMode && (firstCompactPass || compactChanged)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitNumberColumnsWhenReady(),
      );
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
        : LayoutBuilder(
            builder: (context, constraints) {
              final narrow = MediaQuery.sizeOf(context).width < 1100 &&
                  lanes.length > 2;
              if (narrow) {
                return Column(
                  key: const ValueKey('desktop-drum-picker-stacked'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: lanes.first),
                          const SizedBox(width: 10),
                          Expanded(child: lanes.last),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(height: 280, child: lanes[1]),
                  ],
                );
              }
              return Row(
            key: ValueKey(
              controller.singleTeamMode
                  ? 'desktop-drum-picker-single'
                  : 'desktop-drum-picker',
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lanes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  // 5.5 : 5 : 5 — flex is int-only, so 11 : 10 : 10.
                  flex: i == 1 ? 11 : 10,
                  child: lanes[i],
                ),
              ],
            ],
          );
            },
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
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: armed
            ? Border.all(color: tokens.accent, width: FfTokens.focusOutlineWidth)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        child: child,
      ),
    );
  }

  Widget _verbTopLine(FfTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match team PinnedPlayerBar height (28) so columns align.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: 27,
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 118),
                    child: QuietFilterField(
                      controller: _verbFilter,
                      focusNode: _verbFilterFocus,
                      tokens: tokens,
                      height: 27,
                      hint: 'Search',
                      fillColor: FfTokens.nocturneSunken,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      borderRadius: 8,
                      iconSize: 14,
                      iconColor: FfTokens.nocturneT3,
                      showFocusBorder: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      trailing: _verbMatchCount > 0
                          ? Text(
                              '$_verbMatchCount',
                              style: const TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: FfTokens.nocturneT3,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            )
                          : null,
                      onChanged: (_) {
                        final query = _verbFilter.text.trim();
                        setState(() {
                          if (controller.verbListAll) {
                            _verbMatchCount =
                                query.isEmpty ? 0 : _verbs.length;
                          }
                        });
                      },
                      onKeyEvent: (node, event) {
                        if (controller.verbListAll) {
                          return _onAzListFilterKey(event);
                        }
                        final panel = _verbIndexKey.currentState;
                        if (panel == null) return KeyEventResult.ignored;
                        return panel.onFilterKey(node, event);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                VerbMenuTools(
                  controller: controller,
                  tokens: tokens,
                  onFit: () {
                    _fitVerbText();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
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
      final names = !_numberMode;
      return Expanded(
        key: lane == DrumLane.home ? _homeRosterBodyKey : _awayRosterBodyKey,
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
            : _numberMode
                ? _NumberRoster(
                    players: visiblePlayers,
                    columns: _numberColumns,
                    includeOtherRow: true,
                    tokens: tokens,
                    playersSubjectSelected: controller.teamPlayersIsHome ==
                            isHome &&
                        controller.teamSubjectKind == TeamSubjectKind.players,
                    teamNameSubjectSelected: controller.teamPlayersIsHome ==
                            isHome &&
                        controller.teamSubjectKind == TeamSubjectKind.name,
                    teammatesSubjectSelected:
                        controller.withTeammatesIsHome == isHome,
                    onPlayersSubject: () => controller.toggleTeamSubject(
                      isHome: isHome,
                      kind: TeamSubjectKind.players,
                    ),
                    onTeamNameSubject: () => controller.toggleTeamSubject(
                      isHome: isHome,
                      kind: TeamSubjectKind.name,
                    ),
                    onTeammatesSubject: () => controller.toggleTeamSubject(
                      isHome: isHome,
                      kind: TeamSubjectKind.teammates,
                    ),
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
                : names &&
                        widget.mode == DrumPickerMode.scroll &&
                        letterFilter != null
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
                : _HoverPlayerList(
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
        PinnedPlayerBar(
          controller: controller,
          isHome: isHome,
          tokens: tokens,
          height: 28,
          leading: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.5,
              height: 1,
              color: tokens.text,
            ),
          ),
          filter: QuietFilterField(
            key: ValueKey('drum-search-${lane.name}'),
            controller: _filterFor(lane),
            tokens: tokens,
            height: 24,
            hint: '',
            hideIconWhenFilled: true,
            onChanged: (_) => _onRosterFilterChanged(lane),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_numberMode)
                _SquareSizeStepper(
                  canShrink: _numberColumns < _NumberRoster.maxColumns,
                  canGrow: _numberColumns > _NumberRoster.minColumns,
                  onShrink: () => _stepNumberColumns(1),
                  onGrow: () => _stepNumberColumns(-1),
                  onFit: _fitNumberColumns,
                )
              else ...[
                _GhostHeaderIcon(
                  tooltip: 'Sort by number',
                  tokens: tokens,
                  label: controller.rosterSortFieldLabel(),
                  onTap: controller.cycleRosterSortField,
                ),
                _GhostHeaderIcon(
                  tooltip: controller.rosterSortAscending
                      ? 'Ascending'
                      : 'Descending',
                  tokens: tokens,
                  label: controller.rosterSortDirectionLabel(),
                  onTap: controller.toggleRosterSortDirection,
                ),
              ],
              PlayerGearMenu(
                numberMode: _numberMode,
                onNumbers: () => setState(() {
                  _numberMode = true;
                  _homeLetterFilter = null;
                  _awayLetterFilter = null;
                }),
                onNames: () => setState(() {
                  _numberMode = false;
                }),
                onEditTeam: widget.onEditRosters,
                onReset: () {
                  setState(() {
                    _numberMode = true;
                    _numberColumns = _NumberRoster.defaultColumns;
                    _homeLetterFilter = null;
                    _awayLetterFilter = null;
                  });
                },
              ),
            ],
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
        if (!_numberMode)
          TeamPlayersButton(
            controller: controller,
            isHome: isHome,
            tokens: tokens,
          ),
      ],
    );
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
        const PopupMenuItem(value: 'google', child: Text('Google')),
        const PopupMenuItem(value: 'edit', child: Text('Edit player…')),
        const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'pin') {
      controller.togglePlayerPin(player, isHome: isHome);
      return;
    }
    if (action == 'remove') {
      controller.removePlayer(isHome: isHome, player: player);
      return;
    }
    if (action == 'google') {
      await openPlayerGoogleSearch(
        fullName: player.fullName,
        sportId: controller.sport,
      );
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
    void selectPinnedVerb(EffectiveVerb verb) {
      _arm(DrumLane.verbs);
      controller.selectVerb(verb.key);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showCustom = constraints.maxHeight >= 140;
        final selectedKey = controller.selectedVerb;
        final showRbi =
            selectedKey != null && controller.verbNeedsRbi(selectedKey);
        final showBase =
            selectedKey != null && controller.verbNeedsBase(selectedKey);
        final showCelebration = selectedKey != null &&
            controller.verbNeedsCelebration(selectedKey);
        // Panel: 8px top/bottom, 6px gaps (header → filter → … → custom).
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _verbTopLine(tokens),
              Expanded(
                child: controller.verbListAll
                    ? _azListLane(
                        tokens: tokens,
                        onPinnedVerbTap: selectPinnedVerb,
                      )
                    : VerbIndexPanel(
                        key: _verbIndexKey,
                        controller: controller,
                        filterController: _verbFilter,
                        filterFocusNode: _verbFilterFocus,
                        tokens: tokens,
                        onMatchCountChanged: (count) {
                          if (_verbMatchCount == count) return;
                          setState(() => _verbMatchCount = count);
                        },
                        onVerbArmed: (verb) {
                          _arm(DrumLane.verbs);
                          final index =
                              _verbs.indexWhere((v) => v.key == verb.key);
                          if (index >= 0) {
                            _setIndex(DrumLane.verbs, index);
                          }
                          // selectVerb already ran inside VerbIndexPanel._pick.
                        },
                        onToggleFavorite: _toggleVerbFavorite,
                        onAddCustom: (raw) {
                          controller.setCustomVerbPhrase(raw);
                          _verbFilter.clear();
                          setState(() => _verbMatchCount = 0);
                        },
                      ),
              ),
              if (showRbi || showBase || showCelebration)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showRbi)
                        RbiRow(
                          value: controller.rbi,
                          compact: true,
                          homeRunStyle: selectedKey == 'Home Run',
                          onChanged: controller.setRbi,
                        ),
                      if (showBase)
                        BaseRow(
                          value: controller.selectedBase,
                          compact: true,
                          onChanged: controller.setSelectedBase,
                        ),
                      if (showCelebration)
                        CelebrationDropdown(
                          compact: true,
                          reactions:
                              controller.reactionOptionsFor(selectedKey!),
                          celebrations: const <String>[],
                          selected: controller.celebrationType,
                          onChanged: controller.setCelebrationType,
                        ),
                    ],
                  ),
                ),
              if (showCustom)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: _DrumCustomVerbField(
                    textController: _customVerbController,
                    focusNode: _customVerbFocusNode,
                    tokens: tokens,
                    pinned: controller.customVerbPinned,
                    canUseLast:
                        controller.lastCustomVerbPhrase.trim().isNotEmpty,
                    onChanged: controller.setCustomVerbPhrase,
                    onTogglePin: controller.toggleCustomVerbPin,
                    onUseLast: controller.useLastCustomVerb,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Simple list layout (Layout → A–Z): pinned + optional history + mode bar +
  /// letter or category bands, honoring the same prefs as Index.
  Widget _azListLane({
    required FfTokens tokens,
    required ValueChanged<EffectiveVerb> onPinnedVerbTap,
  }) {
    final pinned = controller.pinnedVerbDefinition;
    final pinnedSelected =
        pinned != null && controller.selectedVerb == pinned.key;
    final dens = floVerbIndexDensity(
      MediaQuery.sizeOf(context),
      controller.verbIndexDensity,
    );
    final baseFont = 13 * controller.verbFontScale;
    final fontSize = switch (dens) {
      0 => baseFont * 0.92,
      2 => baseFont * 1.08,
      _ => baseFont,
    };
    final heightScale = switch (dens) {
      0 => 0.88,
      2 => 1.18,
      _ => 1.0,
    };
    final searching = _verbFilter.text.trim().isNotEmpty;
    final applyModeFilter = !searching;
    final byCategory = controller.verbIndexSortByCategory;
    final bands = byCategory
        ? _azCategoryBands(applyFilter: applyModeFilter)
        : null;
    final listVerbs = byCategory
        ? [for (final band in bands!) ...band.$2]
        : (applyModeFilter ? _azApplyFilterMode(_verbs) : _verbs);
    final selectedIndex = listVerbs.isEmpty
        ? 0
        : listVerbs
            .indexWhere((v) => v.key == controller.selectedVerb)
            .clamp(0, listVerbs.length - 1);
    final history = _azHistoryVerbs();
    final mode = controller.verbIndexFilterMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PinnedVerbSlot(
          height: _VerbAccordion.pinnedBarHeight,
          tokens: tokens,
          controller: controller,
          verb: pinned,
          selected: pinnedSelected,
          committed: pinnedSelected,
          showRbi: false,
          showBase: false,
          showCelebration: false,
          rbi: controller.rbi,
          selectedBase: controller.selectedBase,
          celebrationType: controller.celebrationType,
          reactionOptions: const <String>[],
          onTap: pinned == null ? null : () => onPinnedVerbTap(pinned),
          onRbiChanged: controller.setRbi,
          onBaseChanged: controller.setSelectedBase,
          onCelebrationChanged: controller.setCelebrationType,
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 3),
          _AzHistoryStrip(
            verbs: history,
            tokens: tokens,
            selectedKey: controller.selectedVerb,
            onPick: (verb) {
              _arm(DrumLane.verbs);
              final index = listVerbs.indexWhere((v) => v.key == verb.key);
              if (index >= 0) _setIndex(DrumLane.verbs, index);
              controller.selectVerb(verb.key);
            },
          ),
        ],
        if (!searching) ...[
          const SizedBox(height: 6),
          VerbIndexModeBar(
            controller: controller,
            showPinned: false,
          ),
          const SizedBox(height: 6),
        ],
        Expanded(
          key: _azListBodyKey,
          child: listVerbs.isEmpty && !searching
              ? _azEmptyFilter(mode, tokens)
              : _VerbRows(
                  controller: controller,
                  verbs: listVerbs,
                  selectedIndex: selectedIndex,
                  selectedVerbKey: controller.selectedVerb,
                  armed: _armedLane == DrumLane.verbs,
                  tokens: tokens,
                  leadingPadding: 4,
                  fontSize: fontSize,
                  heightScale: heightScale,
                  letterBands: !byCategory,
                  categoryBands: byCategory,
                  bands: bands,
                  oneColumn: true,
                  scrollable: true,
                  onVerbArmed: (index) {
                    _arm(DrumLane.verbs);
                    if (index < 0 || index >= listVerbs.length) return;
                    final key = listVerbs[index].key;
                    final allIndex = _verbs.indexWhere((v) => v.key == key);
                    _setIndex(
                      DrumLane.verbs,
                      allIndex >= 0 ? allIndex : index,
                    );
                    controller.selectVerb(key);
                  },
                  onToggleFavorite: _toggleVerbFavorite,
                ),
        ),
      ],
    );
  }

  Widget _azEmptyFilter(VerbIndexFilterMode mode, FfTokens tokens) {
    final message = switch (mode) {
      VerbIndexFilterMode.faves =>
        'No favorites yet — right-click a verb to add one',
      VerbIndexFilterMode.mostUsed =>
        'No usage yet — save captions to rank verbs',
      VerbIndexFilterMode.all => 'No verbs',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: tokens.metaStyle,
        ),
      ),
    );
  }

  List<EffectiveVerb> _azApplyFilterMode(List<EffectiveVerb> verbs) {
    switch (controller.verbIndexFilterMode) {
      case VerbIndexFilterMode.all:
        return verbs;
      case VerbIndexFilterMode.faves:
        return [for (final v in verbs) if (v.isFavorite) v];
      case VerbIndexFilterMode.mostUsed:
        return [
          for (final v in verbs)
            if (controller.verbMostUsedTier(v.key) > 0) v,
        ];
    }
  }

  List<EffectiveVerb> _azHistoryVerbs() {
    if (!controller.verbIndexShowHistory) return const [];
    final limit = controller.verbIndexHistoryLimit.clamp(1, 10);
    final out = <EffectiveVerb>[];
    for (final key in controller.verbIndexHistory) {
      final verb = controller.verbDefinition(key);
      if (verb == null) continue;
      out.add(verb);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<(String, List<EffectiveVerb>)> _azCategoryBands({
    bool applyFilter = true,
  }) {
    final query = _verbFilter.text.trim().toLowerCase();
    final out = <(String, List<EffectiveVerb>)>[];
    for (final name in verbCategoriesForDisplay(controller.verbCategories)) {
      if (name == 'All') continue;
      var verbs = controller.verbDefinitionsByCategory[name] ??
          const <EffectiveVerb>[];
      if (query.isNotEmpty) {
        verbs = [
          for (final v in verbs)
            if (v.label.toLowerCase().contains(query)) v,
        ];
      }
      if (applyFilter) {
        verbs = _azApplyFilterMode(verbs);
      }
      if (verbs.isEmpty) continue;
      final sorted = [...verbs]..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
      out.add((name, sorted));
    }
    return out;
  }
}

class _AzHistoryStrip extends StatelessWidget {
  const _AzHistoryStrip({
    required this.verbs,
    required this.tokens,
    required this.selectedKey,
    required this.onPick,
  });

  final List<EffectiveVerb> verbs;
  final FfTokens tokens;
  final String? selectedKey;
  final ValueChanged<EffectiveVerb> onPick;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FfTokens.nocturneLn, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PhosphorIcon(
                PhosphorIconsRegular.clockCounterClockwise,
                size: 12,
                color: FfTokens.accentHover,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final verb in verbs)
                    GestureDetector(
                      onTap: () => onPick(verb),
                      child: Text(
                        verb.label,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selectedKey == verb.key
                              ? tokens.text
                              : tokens.text.withValues(alpha: 0.78),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerbHeaderIconButton extends StatefulWidget {
  const _VerbHeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.selectedColor,
    this.onTap,
    this.onCmdTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback? onTap;
  final VoidCallback? onCmdTap;

  @override
  State<_VerbHeaderIconButton> createState() => _VerbHeaderIconButtonState();
}

class _VerbHeaderIconButtonState extends State<_VerbHeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onCmdTap != null;
    final hot = _hovered && enabled;
    final active = hot || widget.selected;
    final iconColor = widget.selected && widget.selectedColor != null
        ? widget.selectedColor!
        : active
            ? FfTokens.nocturneTx
            : FfTokens.nocturneT2;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: CmdClick(
          onTap: widget.onTap,
          onCmdTap: widget.onCmdTap,
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
              widget.icon,
              size: 13,
              color: iconColor,
            ),
          ),
        ),
      ),
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
      height: 21,
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(9),
        border: pinned
            ? Border.all(color: FfTokens.pinned.withValues(alpha: 0.55))
            : null,
      ),
      child: Row(
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.plus,
            size: 14,
            color: FfTokens.nocturneT3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              readOnly: pinned,
              maxLines: 1,
              onChanged: onChanged,
              spellCheckConfiguration: floSpellCheckConfiguration(),
              contextMenuBuilder: floSpellCheckContextMenuBuilder,
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: FfTokens.nocturneTx,
                height: 1,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 0),
                border: InputBorder.none,
                hintText: 'Custom verb',
                hintStyle: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: FfTokens.nocturneT3,
                  height: 1,
                ),
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
            icon: pinned
                ? PhosphorIconsFill.pushPin
                : PhosphorIconsRegular.pushPin,
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
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 20,
          height: 17,
          child: PhosphorIcon(
            icon,
            size: 14,
            color: enabled
                ? (selected ? FfTokens.pinned : FfTokens.nocturneT3)
                : FfTokens.nocturneT3.withValues(alpha: 0.35),
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
    this.showHeaders = true,
    required this.verbsByCategory,
    required this.selectedCategory,
    required this.openCategories,
    required this.selectedIndex,
    required this.selectedVerbKey,
    required this.armed,
    required this.tokens,
    required this.onCategorySelected,
    required this.onPinnedVerbTap,
    this.showPinnedBar = true,
    required this.onVerbArmed,
    required this.onToggleFavorite,
  });

  static const preferredHeaderHeight = 26.0;
  static const minHeaderHeight = 26.0;
  /// Must match [_PinnedHintBar] fixed height (padding + label + bottom border).
  static const pinnedBarHeight = 26.0;
  static const rowHeight = 22.0;
  static const selectedRowHeight = 22.0;
  /// Vertical padding around an unselected row.
  static const rowOuterPadding = 0.0;
  /// Vertical padding around a selected row.
  static const selectedRowOuterPadding = 0.0;
  /// Gap under each letter group in the two-column All list.
  static const letterGroupGap = 1.0;
  /// Fall back to one column only when the lane is too narrow for two chips.
  static const twoColumnMinWidth = 200.0;
  static const rbiExtrasHeight = 26.0;
  static const baseExtrasHeight = 26.0;
  static const celebrationExtrasHeight = 28.0;
  static const extrasDividerHeight = 4.0;

  final CaptionV2Controller controller;
  final List<String> categories;
  final bool showHeaders;
  final Map<String, List<EffectiveVerb>> verbsByCategory;
  final String selectedCategory;
  final Set<String> openCategories;
  final int selectedIndex;
  final String? selectedVerbKey;
  final bool armed;
  final FfTokens tokens;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<EffectiveVerb> onPinnedVerbTap;
  final bool showPinnedBar;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;

  String _displayCategory(String category) {
    final normalized = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return normalized.contains('nongame') ? 'Non-game' : category;
  }

  List<EffectiveVerb> _visibleVerbs(String category) {
    return verbsForOpenCategory(
      category: category,
      open: openCategories.contains(category),
      verbsByCategory: verbsByCategory,
      openCategories: openCategories,
    );
  }

  double _extrasHeightFor(String? key) {
    if (key == null) return 0;
    final needsRbi = controller.verbNeedsRbi(key);
    final needsBase = controller.verbNeedsBase(key);
    final needsCelebration = controller.verbNeedsCelebration(key);
    if (!needsRbi && !needsBase && !needsCelebration) return 0;
    var height = extrasDividerHeight;
    if (needsRbi) height += rbiExtrasHeight;
    if (needsBase) height += baseExtrasHeight;
    if (needsCelebration) height += celebrationExtrasHeight;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinned = controller.pinnedVerbDefinition;
        final pinnedSelected =
            pinned != null && selectedVerbKey == pinned.key;
        final scale = controller.verbFontScale;
        final preferredHeader = preferredHeaderHeight * scale;
        final minHeader = minHeaderHeight * scale;
        final openVerbs = _visibleVerbs(selectedCategory);
        final selectedInOpen = selectedVerbKey != null &&
            !pinnedSelected &&
            openVerbs.any((verb) => verb.key == selectedVerbKey);
        final extrasHeight =
            selectedInOpen ? _extrasHeightFor(selectedVerbKey) : 0.0;
        final pinnedExtras =
            pinnedSelected ? _extrasHeightFor(selectedVerbKey) : 0.0;
        // The top line owns the pinned bar when [showPinnedBar] is false.
        final pinnedHeight =
            (showPinnedBar ? pinnedBarHeight : 0) + pinnedExtras;
        // Each row's padding sits outside [rowHeight]. Leaving it out made a
        // long All list look like it fit, then overflow by 2px per verb.
        var openBodyHeight = extrasHeight;
        for (final category in categories) {
          if (!openCategories.contains(category)) continue;
          final verbs = _visibleVerbs(category);
          for (final verb in verbs) {
            final selected = verb.key == selectedVerbKey;
            openBodyHeight += selected
                ? selectedRowHeight * scale + selectedRowOuterPadding
                : rowHeight * scale + rowOuterPadding;
          }
          if (category == 'All' && verbs.isNotEmpty) {
            openBodyHeight +=
                verbLetterBands(verbs).length * letterGroupGap;
          }
          if (category != selectedCategory &&
              !pinnedSelected &&
              selectedVerbKey != null &&
              verbs.any((verb) => verb.key == selectedVerbKey)) {
            openBodyHeight += _extrasHeightFor(selectedVerbKey);
          }
        }
        final headerSlots = showHeaders ? categories.length : 0;
        final minContentHeight = headerSlots * minHeader +
            openBodyHeight +
            pinnedHeight;
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        // Prefer scroll when within a few pixels — letter headers / rounding
        // used to leave a Column that overflowed by 2–3px instead of scrolling.
        const scrollSlack = 4.0;
        final needsScroll = bounded &&
            minContentHeight > constraints.maxHeight - scrollSlack;

        final double headerHeight;
        if (!showHeaders || categories.isEmpty) {
          headerHeight = 0;
        } else if (needsScroll) {
          headerHeight = minHeader;
        } else {
          final availableForHeaders =
              constraints.maxHeight - openBodyHeight - pinnedHeight;
          headerHeight = (availableForHeaders / categories.length)
              .clamp(minHeader, preferredHeader);
        }

        // Re-check with the resolved header height — float/rounding can leave
        // a couple of pixels short of what the Column actually paints.
        final resolvedHeight = pinnedHeight +
            (showHeaders ? categories.length * headerHeight : 0.0) +
            openBodyHeight;
        final stillOverflows = bounded &&
            resolvedHeight > constraints.maxHeight - scrollSlack;

        if (needsScroll || stillOverflows) {
          return ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
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
                onTap: pinned == null ? null : () => onPinnedVerbTap(pinned),
                onRbiChanged: controller.setRbi,
                onBaseChanged: controller.setSelectedBase,
                onCelebrationChanged: controller.setCelebrationType,
                showBar: showPinnedBar,
              ),
              for (final category in categories)
                _VerbAccordionSection(
                  controller: controller,
                  category: category,
                  displayCategory: _displayCategory(category),
                  verbs: _visibleVerbs(category),
                  headerHeight: headerHeight,
                  showHeader: showHeaders,
                  open: openCategories.contains(category),
                  fontSize: 13 * scale,
                  selectedIndex: selectedIndex,
                  selectedVerbKey: selectedVerbKey,
                  armed: armed,
                  tokens: tokens,
                  onOpen: () => onCategorySelected(category),
                  onVerbArmed: onVerbArmed,
                  onToggleFavorite: onToggleFavorite,
                ),
            ],
            ),
          );
        }

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
              showBar: showPinnedBar,
            ),
            for (final category in categories)
              _VerbAccordionSection(
                controller: controller,
                category: category,
                displayCategory: _displayCategory(category),
                verbs: _visibleVerbs(category),
                headerHeight: stillOverflows ? minHeader : headerHeight,
                showHeader: showHeaders,
                open: openCategories.contains(category),
                fontSize: 13 * scale,
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

        return column;
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
    this.showHeader = true,
    required this.open,
    required this.selectedIndex,
    required this.selectedVerbKey,
    required this.armed,
    required this.tokens,
    required this.onOpen,
    required this.onVerbArmed,
    required this.onToggleFavorite,
    this.scrollable = false,
    this.fontSize = 13,
  });

  final CaptionV2Controller controller;
  final String category;
  final String displayCategory;
  final List<EffectiveVerb> verbs;
  final double headerHeight;
  final bool showHeader;
  final bool open;
  final bool scrollable;
  final int selectedIndex;
  final String? selectedVerbKey;
  final bool armed;
  final FfTokens tokens;
  final VoidCallback onOpen;
  final ValueChanged<int> onVerbArmed;
  final Future<void> Function(String) onToggleFavorite;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final isFavorites = category == 'Favorites';
    final labelColor = isFavorites
        ? FfTokens.favoritesLight
        : (open ? tokens.text : tokens.textTertiary);
    return Column(
      children: [
        if (showHeader)
        VerbCategoryDropTarget(
          category: category,
          controller: controller,
          child: _VerbCategoryButton(
            key: ValueKey('verb-accordion-$category'),
            height: headerHeight,
            tokens: tokens,
            accent: null,
            onTap: onOpen,
            child: Row(
              children: [
                Transform.rotate(
                  angle: open ? 1.5708 : 0,
                  child: Icon(
                    PhosphorIconsRegular.caretRight,
                    size: 12 * controller.verbFontScale,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayCategory.toUpperCase(),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: fontSize + 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            height: 1,
                            color: labelColor,
                          ),
                        ),
                      ),
                      if (isFavorites) ...[
                        const SizedBox(width: 4),
                        PhosphorIcon(
                          PhosphorIconsFill.star,
                          size: 11 * controller.verbFontScale,
                          color: FfTokens.favoritesLight,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _HoverOnly(
                  child: VerbCategoryDragHandle(
                    category: category,
                    color: tokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open && verbs.isEmpty)
          const SizedBox.shrink()
        else if (open && scrollable)
          Expanded(
            child: _VerbRows(
              controller: controller,
              verbs: verbs,
              selectedIndex: selectedIndex,
              selectedVerbKey: selectedVerbKey,
              armed: armed,
              tokens: tokens,
              leadingPadding: 4,
              fontSize: fontSize,
              gold: isFavorites,
              letterBands: category == 'All',
              scrollable: true,
              onVerbArmed: onVerbArmed,
              onToggleFavorite: onToggleFavorite,
            ),
          )
        else
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
                    leadingPadding: 4,
                    fontSize: fontSize,
                    gold: isFavorites,
                    letterBands: category == 'All',
                    onVerbArmed: onVerbArmed,
                    onToggleFavorite: onToggleFavorite,
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class _VerbCategoryButton extends StatelessWidget {
  const _VerbCategoryButton({
    super.key,
    required this.height,
    required this.tokens,
    required this.onTap,
    required this.child,
    this.accent,
  });

  final double height;
  final FfTokens tokens;
  final VoidCallback onTap;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: tokens.hover,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (accent != null) ...[
                  Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverOnly extends StatefulWidget {
  const _HoverOnly({required this.child});

  final Widget child;

  @override
  State<_HoverOnly> createState() => _HoverOnlyState();
}

class _HoverOnlyState extends State<_HoverOnly> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _on = true),
      onExit: (_) => setState(() => _on = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _on ? 1 : 0,
        child: widget.child,
      ),
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
    this.leadingPadding = 4,
    this.fontSize = 13,
    this.scrollable = false,
    this.gold = false,
    this.letterBands = false,
    this.categoryBands = false,
    this.bands,
    this.oneColumn = false,
    this.heightScale = 1,
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
  final bool gold;
  /// Inline A–Z marker on the first verb of each letter band.
  final bool letterBands;
  /// Category title above each group (simple A–Z layout, Sort → Category).
  final bool categoryBands;
  /// Optional prebuilt bands; when null and [letterBands], derived from verbs.
  final List<(String, List<EffectiveVerb>)>? bands;
  /// When true with letter/category bands, never split into two columns.
  final bool oneColumn;
  /// Multiplies row height (Density: compact / cozy / comfortable).
  final double heightScale;

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

  Widget _row(int index, {String? bandLetter}) {
    final verb = widget.verbs[index];
    // Only the committed/caption verb gets the selected fill.
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
      heightScale: widget.heightScale,
      gold: widget.gold,
      tokens: widget.tokens,
      bandLetter: bandLetter,
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

  Widget _letterGroup(
    String letter,
    List<EffectiveVerb> verbs,
    int startIndex,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _VerbAccordion.letterGroupGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: VerbBandLetter.width,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: VerbBandLetter(letter: letter, tokens: widget.tokens),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < verbs.length; i++)
                  _row(startIndex + i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryGroup(
    String title,
    List<EffectiveVerb> verbs,
    int startIndex,
  ) {
    final display = title.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    final label = display.contains('nongame') ? 'Non-game' : title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: widget.fontSize - 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                height: 1,
                color: widget.tokens.textTertiary,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          for (var i = 0; i < verbs.length; i++) _row(startIndex + i),
        ],
      ),
    );
  }

  List<Widget> _groupsForBands(
    List<(String, List<EffectiveVerb>)> bands,
    int startIndex,
  ) {
    final out = <Widget>[];
    var index = startIndex;
    for (final band in bands) {
      if (widget.categoryBands) {
        out.add(_categoryGroup(band.$1, band.$2, index));
      } else {
        out.add(_letterGroup(band.$1, band.$2, index));
      }
      index += band.$2.length;
    }
    return out;
  }

  Widget _bandedBody({required bool twoColumns}) {
    final bands = widget.bands ?? verbLetterBands(widget.verbs);
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _groupsForBands(bands, 0),
      );
    }

    final columns = verbLetterBandColumns(bands);
    var running = 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns.length; c++) ...[
          if (c > 0) const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: () {
                final start = running;
                for (final band in columns[c]) {
                  running += band.$2.length;
                }
                return _groupsForBands(columns[c], start);
              }(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _wrapScroll(Widget child) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.verbs.isEmpty) {
      return Center(
        child: Text('No verbs', style: widget.tokens.metaStyle),
      );
    }
    if (widget.letterBands || widget.categoryBands) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Two columns down to ~200px; only collapse when the lane is too
          // narrow for two readable chips (or width is unbounded).
          final twoColumns = !widget.oneColumn &&
              !widget.categoryBands &&
              width.isFinite &&
              width >= _VerbAccordion.twoColumnMinWidth;
          final body = _bandedBody(twoColumns: twoColumns);
          if (widget.scrollable) return _wrapScroll(body);
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
            child: body,
          );
        },
      );
    }
    if (widget.scrollable) {
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
          itemCount: widget.verbs.length,
          itemBuilder: (context, index) => _row(index),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
      child: Column(
        children: [
          for (var index = 0; index < widget.verbs.length; index++)
            _row(index),
        ],
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
    this.showBar = true,
    this.trailing,
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
  final bool showBar;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasVerb = verb != null;
    final hasOptionRows = showRbi || showBase || showCelebration;
    final bar = _PinnedHintBar(
      height: height,
      tokens: tokens,
      hasContent: hasVerb,
      trailing: trailing,
      child: trailing == null
          ? Row(
              children: [
                Icon(
                  hasVerb
                      ? PhosphorIconsFill.pushPin
                      : PhosphorIconsRegular.pushPin,
                  size: 11,
                  color: tokens.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: hasVerb
                      ? CmdClick(
                          key: ValueKey('verb-pinned-inline-${verb!.key}'),
                          onTap: onTap ??
                              () => controller.toggleVerbPin(verb!.key),
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
                                  PhosphorIcon(
                                    PhosphorIconsRegular.check,
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
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasVerb) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: CmdClick(
                      onTap: onTap ?? () => controller.toggleVerbPin(verb!.key),
                      onCmdTap: () => controller.toggleVerbPin(verb!.key),
                      child: Text(
                        verb!.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 12,
                          height: 1.0,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? tokens.text
                              : tokens.text.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  hasVerb
                      ? PhosphorIconsFill.pushPin
                      : PhosphorIconsRegular.pushPin,
                  size: 13,
                  color: hasVerb ? tokens.textSecondary : tokens.textTertiary,
                ),
              ],
            ),
    );

    if (!showBar && !hasOptionRows) return const SizedBox.shrink();
    if (!showBar) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
    this.heightScale = 1,
    this.gold = false,
    required this.tokens,
    this.bandLetter,
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

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final bool selected;
  final bool committed;
  final double leadingPadding;
  final double fontSize;
  final double heightScale;
  final bool gold;
  final FfTokens tokens;
  final String? bandLetter;
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
    // Extras sit under the verb chip; match its horizontal padding.
    final insetLeft = widget.leadingPadding;

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
            heightScale: widget.heightScale,
            leadingPadding: widget.leadingPadding,
            gold: widget.gold,
            tokens: widget.tokens,
            bandLetter: widget.bandLetter,
            onTap: widget.onTap,
            onToggleFavorite: widget.onToggleFavorite,
          ),
          if (hasOptionRows) ...[
            if (widget.showRbi)
              Padding(
                padding: EdgeInsets.fromLTRB(insetLeft, 3, 8, 1),
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
                  insetLeft,
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
                  insetLeft,
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
          ],
        ],
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
    this.heightScale = 1,
    this.leadingPadding = 4,
    this.gold = false,
    this.bandLetter,
  });

  final CaptionV2Controller controller;
  final EffectiveVerb verb;
  final bool selected;
  final bool committed;
  final bool hovered;
  final double fontSize;
  final double heightScale;
  final FfTokens tokens;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final double leadingPadding;
  final bool gold;
  final String? bandLetter;

  @override
  Widget build(BuildContext context) {
    final Color? fill;
    if (selected) {
      fill = FfTokens.nocturneAccentSoft;
    } else if (hovered) {
      fill = FfTokens.nocturneHv;
    } else {
      fill = null;
    }
    final labelColor = gold
        ? FfTokens.favoritesVerb
        : (selected ? Colors.white : FfTokens.nocturneTx);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: CmdClick(
        key: ValueKey('verb-accordion-row-${verb.key}'),
        useInkWell: true,
        onTap: onTap,
        onCmdTap: () => controller.toggleVerbPin(verb.key),
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Tooltip(
          message: verb.label,
          waitDuration: const Duration(milliseconds: 600),
          child: Container(
            height: (selected
                    ? _VerbAccordion.selectedRowHeight
                    : _VerbAccordion.rowHeight) *
                controller.verbFontScale *
                heightScale,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(7),
              border: selected
                  ? Border.all(
                      color: FfTokens.nocturneAccentEdge,
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                if (bandLetter != null) ...[
                  VerbBandLetter(letter: bandLetter, tokens: tokens),
                  const SizedBox(width: 4),
                ],
                if (controller.isVerbPinned(verb.key)) ...[
                  PhosphorIcon(
                    PhosphorIconsFill.pushPin,
                    size: 10,
                    color: FfTokens.pinned,
                  ),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: Text(
                    verb.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: fontSize,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1.05,
                      color: labelColor,
                    ),
                  ),
                ),
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

class _NumberRoster extends StatelessWidget {
  const _NumberRoster({
    required this.players,
    required this.columns,
    required this.includeOtherRow,
    required this.tokens,
    this.playersSubjectSelected = false,
    this.teamNameSubjectSelected = false,
    this.teammatesSubjectSelected = false,
    this.onPlayersSubject,
    this.onTeamNameSubject,
    this.onTeammatesSubject,
    required this.isSelected,
    required this.onCommit,
    this.onPin,
    this.onSecondaryTap,
  });

  final List<Player> players;
  final int columns;
  final bool includeOtherRow;
  final FfTokens tokens;
  final bool playersSubjectSelected;
  final bool teamNameSubjectSelected;
  final bool teammatesSubjectSelected;
  final VoidCallback? onPlayersSubject;
  final VoidCallback? onTeamNameSubject;
  final VoidCallback? onTeammatesSubject;
  final bool Function(Player player) isSelected;
  final ValueChanged<Player> onCommit;
  final ValueChanged<Player>? onPin;
  final void Function(Player player, Offset globalPosition)? onSecondaryTap;

  /// User-chosen squares across each row. Plus grows squares by dropping a column.
  static const int minColumns = 4;
  static const int defaultColumns = 6;
  static const int maxColumns = 8;
  static const double columnGap = 2.0;
  static const double maxCell = 140.0;
  /// Wider-than-tall aspect used at small sizes (W/H).
  static const double smallAspect = 1.28;
  /// Below this width → full rectangle; above → full square.
  static const double rectBlendStart = 58.0;
  static const double squareBlendEnd = 96.0;

  static double _aspectForCellWidth(double cellW) {
    if (cellW <= rectBlendStart) return smallAspect;
    if (cellW >= squareBlendEnd) return 1.0;
    final t = (cellW - rectBlendStart) / (squareBlendEnd - rectBlendStart);
    return smallAspect + (1.0 - smallAspect) * t;
  }

  /// Fewest columns (largest tiles) that still fit [height].
  ///
  /// Uses the minimum readable cell height so Fit can pick a wider tile even
  /// when the natural square would overflow; [build] then grows cells to fill.
  static int bestColumnsFor({
    required double width,
    required double height,
    required List<Player> players,
    required bool includeOtherRow,
    required bool showSubjects,
    required double scale,
  }) {
    var best = maxColumns;
    for (var cols = minColumns; cols <= maxColumns; cols++) {
      final metrics = layoutMetrics(
        width: width,
        columns: cols,
        players: players,
        includeOtherRow: includeOtherRow,
        showSubjects: showSubjects,
        scale: scale,
      );
      final needed = metrics.chromeHeight +
          metrics.jerseyRowCount * metrics.contentH;
      if (needed <= height + 2) {
        best = cols;
        break;
      }
      best = cols;
    }
    return best;
  }

  /// Shared roster geometry for Fit estimates and [build].
  static ({
    double cellW,
    double contentH,
    double naturalH,
    double jerseySize,
    double nameSize,
    int numberedRows,
    int otherRows,
    int jerseyRowCount,
    int subjectRows,
    double chromeHeight,
  }) layoutMetrics({
    required double width,
    required int columns,
    required List<Player> players,
    required bool includeOtherRow,
    required bool showSubjects,
    required double scale,
  }) {
    const horizontalPad = 4.0;
    final innerWidth = (width - horizontalPad * 2).clamp(1.0, width);
    final cols = columns.clamp(minColumns, maxColumns);
    final cellW =
        cols <= 1 ? innerWidth : (innerWidth - columnGap * (cols - 1)) / cols;

    final numbered = _sortedNumbered(players);
    final other = [
      for (final player in players)
        if (!_isNumbered(player)) player,
    ];
    final numberedRows =
        numbered.isEmpty ? 0 : (numbered.length / cols).ceil();
    final otherRows = includeOtherRow && other.isNotEmpty
        ? (other.length / cols).ceil().clamp(1, 1000)
        : 0;
    final subjectRows = showSubjects ? 1 : 0;
    final jerseyRowCount = numberedRows + otherRows;

    final numberSize = 26.0 * scale;
    final nameSize = 13.0 * scale;
    const comfortableCell = 72.0;
    final fit = (cellW / comfortableCell).clamp(0.72, 1.15);
    final jerseySize = numberSize * fit;
    final fittedName = nameSize * fit;
    final squareH =
        (cellW / _aspectForCellWidth(cellW)).clamp(40.0, maxCell);
    final contentH = (fittedName - 0.5) * 1.05 + 4 + jerseySize + 8;
    final naturalH = squareH < contentH ? contentH : squareH;

    // Pads + range labels + subject row; jersey cell heights are separate.
    const labelBlock = 14.0;
    var chrome = 4.0; // list bottom pad
    var bandIndex = 0;
    void addBandTopPad() {
      if (bandIndex > 0) chrome += 4;
      bandIndex++;
    }

    if (numberedRows > 0) {
      for (var i = 0; i < numberedRows; i++) {
        addBandTopPad();
        chrome += labelBlock;
      }
    }
    if (otherRows > 0) {
      addBandTopPad();
      chrome += labelBlock + (otherRows - 1) * columnGap;
    }
    if (subjectRows > 0) {
      addBandTopPad();
      chrome += labelBlock + 40.0;
    }

    return (
      cellW: cellW,
      contentH: contentH,
      naturalH: naturalH,
      jerseySize: jerseySize,
      nameSize: fittedName,
      numberedRows: numberedRows,
      otherRows: otherRows,
      jerseyRowCount: jerseyRowCount,
      subjectRows: subjectRows,
      chromeHeight: chrome,
    );
  }

  static int? _jersey(Player player) {
    var raw = player.jerseyNumber?.trim() ?? '';
    while (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    final number = int.tryParse(raw);
    if (number == null || number < 0 || number > 99) return null;
    return number;
  }

  static String _lastName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return player.fullName;
    return parts.sublist(1).join(' ');
  }

  static List<List<Player>> _chunk(List<Player> players, int perRow) {
    if (players.isEmpty) return const [];
    final out = <List<Player>>[];
    for (var i = 0; i < players.length; i += perRow) {
      final end = i + perRow;
      out.add(players.sublist(i, end > players.length ? players.length : end));
    }
    return out;
  }

  static bool _isNumbered(Player player) {
    final number = _jersey(player);
    return number != null && number >= 0 && number <= 99;
  }

  static int _compareNumbered(Player a, Player b) {
    final byNumber = _jersey(a)!.compareTo(_jersey(b)!);
    if (byNumber != 0) return byNumber;
    return a.fullName.compareTo(b.fullName);
  }

  /// Label a full row from the jerseys actually in it, e.g. "3–22".
  static String _rangeLabel(List<Player> group) {
    var min = _jersey(group.first)!;
    var max = min;
    for (final player in group) {
      final number = _jersey(player)!;
      if (number < min) min = number;
      if (number > max) max = number;
    }
    if (min == max) return '$min';
    return '$min–$max';
  }

  /// Numbered players, lowest jersey first.
  static List<Player> _sortedNumbered(List<Player> players) {
    final numbered = [for (final player in players) if (_isNumbered(player)) player];
    numbered.sort(_compareNumbered);
    return numbered;
  }

  @override
  Widget build(BuildContext context) {
    final numbered = _sortedNumbered(players);
    final other = [for (final player in players) if (!_isNumbered(player)) player]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    final showSubjects = onPlayersSubject != null;

    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortest / 1000.0).clamp(0.62, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Thin even inset so tiles aren't flush against the pane edge.
        const horizontalPad = 4.0;
        final cols = columns.clamp(minColumns, maxColumns);
        final metrics = layoutMetrics(
          width: constraints.maxWidth,
          columns: cols,
          players: players,
          includeOtherRow: includeOtherRow,
          showSubjects: showSubjects,
          scale: scale,
        );
        final bands = <(String, List<Player>)>[
          for (final group in _chunk(numbered, cols))
            (_rangeLabel(group), group),
        ];
        if (includeOtherRow && other.isNotEmpty) {
          bands.add(('No number', other));
        }
        if (showSubjects) {
          bands.add(('Other', const <Player>[]));
        }

        // Grow jersey tiles into leftover panel height (compact Fit especially).
        // Shrink toward contentH when the natural square would overflow.
        var fittedH = metrics.naturalH;
        if (constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite &&
            metrics.jerseyRowCount > 0) {
          final fillH =
              (constraints.maxHeight - metrics.chromeHeight - 1.0) /
                  metrics.jerseyRowCount;
          fittedH = fillH.clamp(metrics.contentH, maxCell);
        }
        final fontGrow =
            (fittedH / metrics.naturalH).clamp(0.85, 1.45);
        final jerseySize = metrics.jerseySize * fontGrow;
        final fittedName = metrics.nameSize * fontGrow;

        Widget cellAt((String, List<Player>) band, int index) {
          final cellH = band.$1 == 'Other' ? 40.0 : fittedH;
          if (index >= band.$2.length) {
            final subject = index - band.$2.length;
            final playersButton = subject == 0;
            final teamNameButton = subject == 1;
            return _TeamSubjectCell(
              label: playersButton
                  ? 'Players'
                  : teamNameButton
                      ? 'Team name'
                      : 'Teammates',
              icon: playersButton
                  ? PhosphorIconsRegular.usersThree
                  : teamNameButton
                      ? PhosphorIconsRegular.shield
                      : PhosphorIconsRegular.users,
              selected: playersButton
                  ? playersSubjectSelected
                  : teamNameButton
                      ? teamNameSubjectSelected
                      : teammatesSubjectSelected,
              onTap: playersButton
                  ? onPlayersSubject!
                  : teamNameButton
                      ? onTeamNameSubject!
                      : onTeammatesSubject!,
            );
          }
          final player = band.$2[index];
          return _NumberCell(
            key: ValueKey(
              '${player.playerId ?? player.fullName}|${player.jerseyNumber ?? ''}',
            ),
            player: player,
            lastName: _lastName(player),
            selected: isSelected(player),
            tokens: tokens,
            width: double.infinity,
            height: cellH,
            nameSize: fittedName,
            jerseySize: jerseySize,
            onTap: () => onCommit(player),
            onPin: onPin == null ? null : () => onPin!(player),
            onSecondaryTap: onSecondaryTap == null
                ? null
                : (position) => onSecondaryTap!(player, position),
          );
        }

        return ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              horizontalPad,
              0,
              horizontalPad,
              4,
            ),
            children: [
              for (var i = 0; i < bands.length; i++) ...[
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 4, bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        bands[i].$1,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: tokens.textTertiary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(height: 1, color: tokens.divider),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    final band = bands[i];
                    final isOther = band.$1 == 'Other';
                    final subjectCount = isOther && showSubjects ? 3 : 0;
                    final count = band.$2.length + subjectCount;
                    // Other: one row of 3 equal subject buttons (Players / Team
                    // name / Teammates). Number bands keep jersey square columns.
                    final bandCols = isOther ? 3 : cols;
                    final gap = isOther ? 4.0 : columnGap;
                    final rowCount =
                        count == 0 ? 0 : (count / bandCols).ceil();
                    final rowH = isOther ? 40.0 : fittedH;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var row = 0; row < rowCount; row++) ...[
                          if (row > 0) SizedBox(height: gap),
                          SizedBox(
                            height: rowH,
                            child: Row(
                              children: [
                                for (var col = 0; col < bandCols; col++) ...[
                                  if (col > 0) SizedBox(width: gap),
                                  Expanded(
                                    child: row * bandCols + col < count
                                        ? cellAt(
                                            band,
                                            row * bandCols + col,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
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

class _TeamSubjectCell extends StatefulWidget {
  const _TeamSubjectCell({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TeamSubjectCell> createState() => _TeamSubjectCellState();
}

class _TeamSubjectCellState extends State<_TeamSubjectCell> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final pressed = _pressed || selected;
    final Color fill;
    final Color border;
    final Color iconColor;
    if (pressed) {
      fill = FfTokens.nocturneAccentSoft;
      border = FfTokens.nocturneAccentEdge;
      iconColor = FfTokens.accentHover;
    } else if (_hovered) {
      fill = FfTokens.nocturneHv;
      border = FfTokens.nocturneLn;
      iconColor = FfTokens.accentHover;
    } else {
      fill = FfTokens.nocturneSf;
      border = FfTokens.nocturneLn;
      iconColor = FfTokens.nocturneT2;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(
                  widget.icon,
                  size: 14,
                  color: iconColor,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: FfTokens.nocturneTx,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberCell extends StatefulWidget {
  const _NumberCell({
    super.key,
    required this.player,
    required this.lastName,
    required this.selected,
    required this.tokens,
    required this.width,
    required this.height,
    required this.nameSize,
    required this.jerseySize,
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
    final hovering = _hovered;
    final fill = selected
        ? tokens.text
        : (hovering ? tokens.hover : tokens.sunken);
    final nameColor = selected
        ? tokens.bg.withValues(alpha: 0.7)
        : tokens.textSecondary;
    final numberColor = selected ? tokens.bg : tokens.text;
    final name = widget.lastName.toUpperCase();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CmdClick(
        onTap: widget.onTap,
        onCmdTap: widget.onPin,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: SizedBox(
          height: widget.height,
          width: widget.width,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FfTokens.labelFamily,
                    fontSize: widget.nameSize - 0.5,
                    height: 1.05,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w700,
                    color: nameColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.player.jerseyNumber ?? '—',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: widget.jerseySize,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -1.2,
                    color: numberColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: [
                      Shadow(
                        color: numberColor.withValues(alpha: 0.75),
                        blurRadius: 6,
                      ),
                      Shadow(
                        color: numberColor.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ],
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
  static const _itemExtent = 26.0;
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
              child: SizedBox(
                height: _itemExtent,
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
                      width: 28,
                      child: Text(
                        player.jerseyNumber ?? '—',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                        style: FfTokens.rosterJersey(
                          color: widget.tokens.textTertiary,
                        ).copyWith(fontSize: 14, height: 1),
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
                        ).copyWith(fontSize: 15, height: 1),
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
                  width: 28,
                  child: Text(
                    widget.jersey,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    style: FfTokens.rosterJersey(
                      color: widget.tokens.textTertiary,
                    ).copyWith(fontSize: 14),
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
                    ).copyWith(fontSize: 15),
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

class _PinnedHintBar extends StatelessWidget {
  const _PinnedHintBar({
    required this.tokens,
    required this.hasContent,
    required this.child,
    this.height,
    this.trailing,
  });

  final FfTokens tokens;
  final bool hasContent;
  final Widget child;
  final double? height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height ?? _VerbAccordion.pinnedBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: hasContent ? FfTokens.pinnedDivider : tokens.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          if (trailing == null)
            Expanded(child: child)
          else ...[
            child,
            const SizedBox(width: 8),
            Expanded(child: trailing!),
          ],
        ],
      ),
    );
  }
}

class PlayerGearMenu extends StatefulWidget {
  const PlayerGearMenu({
    this.numberMode,
    this.onNumbers,
    this.onNames,
    this.onEditTeam,
    this.onReset,
  });

  /// Null hides the layout rows and leaves Edit rosters.
  final bool? numberMode;
  final VoidCallback? onNumbers;
  final VoidCallback? onNames;
  final VoidCallback? onEditTeam;
  final VoidCallback? onReset;

  @override
  State<PlayerGearMenu> createState() => _PlayerGearMenuState();
}

class _PlayerGearMenuState extends State<PlayerGearMenu> {
  static const _menuWidth = 280.0;

  OverlayEntry? _entry;
  bool _open = false;
  bool _hovered = false;

  bool get _layout => widget.numberMode != null;

  @override
  void didUpdateWidget(covariant PlayerGearMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Names/Numbers update this widget while it is still building. Marking
    // the overlay dirty has to wait until that build finishes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry?.markNeedsBuild();
    });
  }

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
    final overlaySize = overlayBox.size;
    const gap = 8.0;
    // Prefer opening to the right of the gear so the popover doesn't cover
    // the player list. Fall back to the left when the window is too tight.
    final rightLeft = origin.dx + box.size.width + gap;
    final leftLeft = origin.dx - gap - _menuWidth;
    final maxLeft = overlaySize.width - 8 - _menuWidth;
    final opensRight = rightLeft <= maxLeft;
    final left = (opensRight ? rightLeft : leftLeft)
        .clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft);

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
              delegate: _GearMenuBeside(
                top: origin.dy,
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: _PlayerGearCard(
                      numberMode: widget.numberMode,
                      onNumbers: widget.onNumbers,
                      onNames: widget.onNames,
                      onEditTeam: widget.onEditTeam == null
                          ? null
                          : () {
                              final edit = widget.onEditTeam;
                              _close();
                              edit?.call();
                            },
                      showReset: false,
                      onReset: widget.onReset,
                      onClose: _close,
                    ),
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
    if (!_layout && widget.onEditTeam == null) return const SizedBox.shrink();
    final active = _open || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
            color: active ? FfTokens.nocturneTx : FfTokens.nocturneT3,
          ),
        ),
      ),
    );
  }
}

class _GearMenuBeside extends SingleChildLayoutDelegate {
  _GearMenuBeside({
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
    if (y < 8) y = 8;
    final maxTop = size.height - 8 - childSize.height;
    if (y > maxTop) y = maxTop < 8 ? 8.0 : maxTop;
    var x = left;
    final maxLeft = size.width - 8 - childSize.width;
    if (x > maxLeft) x = maxLeft < 8 ? 8.0 : maxLeft;
    if (x < 8) x = 8;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _GearMenuBeside oldDelegate) {
    return top != oldDelegate.top ||
        left != oldDelegate.left ||
        width != oldDelegate.width;
  }
}

class _PlayerGearCard extends StatelessWidget {
  const _PlayerGearCard({
    required this.numberMode,
    required this.onNumbers,
    required this.onNames,
    required this.onEditTeam,
    required this.showReset,
    required this.onReset,
    required this.onClose,
  });

  final bool? numberMode;
  final VoidCallback? onNumbers;
  final VoidCallback? onNames;
  final VoidCallback? onEditTeam;
  final bool showReset;
  final VoidCallback? onReset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final showLayout = numberMode != null;
    final show = numberMode == false ? _PlayerShow.names : _PlayerShow.numbers;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'PLAYER PANEL',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.88,
                        color: FfTokens.nocturneT3,
                      ),
                    ),
                  ),
                  _GearCloseButton(onTap: onClose),
                ],
              ),
            ),
            if (showLayout) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Show',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FfTokens.nocturneTx,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ShowSegments(
                      selected: show,
                      onChanged: (next) {
                        switch (next) {
                          case _PlayerShow.numbers:
                            onNumbers?.call();
                          case _PlayerShow.names:
                            onNames?.call();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (showReset || onEditTeam != null) ...[
              const SizedBox(height: 2),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: FfTokens.nocturneLn),
                  child: SizedBox(height: 1),
                ),
              ),
              if (showReset) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GearLink(
                    icon: PhosphorIconsRegular.arrowCounterClockwise,
                    label: 'Reset to default',
                    onTap: onReset ?? () {},
                  ),
                ),
              ],
              if (onEditTeam != null) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GearLink(
                    icon: PhosphorIconsRegular.pencilSimple,
                    label: 'Edit rosters',
                    onTap: onEditTeam!,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

enum _PlayerShow { numbers, names }

/// Joined Numbers / Names control, same pattern as the
/// caption-strip Half / Quarter toggle.
class _ShowSegments extends StatelessWidget {
  const _ShowSegments({
    required this.selected,
    required this.onChanged,
  });

  final _PlayerShow selected;
  final ValueChanged<_PlayerShow> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FfTokens.nocturneBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: FfTokens.nocturneLn2),
      ),
      child: Row(
        children: [
          for (final option in _PlayerShow.values)
            Expanded(
              child: _ShowSegment(
                label: switch (option) {
                  _PlayerShow.numbers => 'Numbers',
                  _PlayerShow.names => 'Names',
                },
                selected: option == selected,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShowSegment extends StatelessWidget {
  const _ShowSegment({
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
          ),
        ),
      ),
    );
  }
}

const _gearValueStyle = TextStyle(
  fontFamily: FfTokens.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: FfTokens.nocturneTx,
  decoration: TextDecoration.none,
  fontFeatures: [FontFeature.tabularFigures()],
);

class _GearSettingRow extends StatelessWidget {
  const _GearSettingRow({
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
          Expanded(
            child: Column(
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
                    color: FfTokens.nocturneT3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}

class _GearStepper extends StatelessWidget {
  const _GearStepper({
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
            _GearStepButton(enabled: !atMin, onTap: onMinus, child: minus),
            const SizedBox(width: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Center(child: value),
            ),
            const SizedBox(width: 2),
            _GearStepButton(enabled: !atMax, onTap: onPlus, child: plus),
          ],
        ),
      ),
    );
  }
}

class _GearStepButton extends StatefulWidget {
  const _GearStepButton({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_GearStepButton> createState() => _GearStepButtonState();
}

class _GearStepButtonState extends State<_GearStepButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hot = _hovered && widget.enabled;
    final color = hot ? FfTokens.nocturneTx : FfTokens.nocturneT2;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _GearCloseButton extends StatefulWidget {
  const _GearCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GearCloseButton> createState() => _GearCloseButtonState();
}

class _GearCloseButtonState extends State<_GearCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.x,
            size: 14,
            color: _hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3,
          ),
        ),
      ),
    );
  }
}

class _GearLink extends StatefulWidget {
  const _GearLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_GearLink> createState() => _GearLinkState();
}

class _GearLinkState extends State<_GearLink> {
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
              PhosphorIcon(widget.icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
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

class _SquareSizeStepper extends StatelessWidget {
  const _SquareSizeStepper({
    required this.canShrink,
    required this.canGrow,
    required this.onShrink,
    required this.onGrow,
    this.onFit,
  });

  final bool canShrink;
  final bool canGrow;
  final VoidCallback onShrink;
  final VoidCallback onGrow;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    return AaTextSizeControl(
      height: 24,
      canSmaller: canShrink,
      canLarger: canGrow,
      onSmaller: onShrink,
      onLarger: onGrow,
      onFit: onFit,
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
        hitTestBehavior: HitTestBehavior.opaque,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            constraints: const BoxConstraints(minWidth: 14, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? widget.tokens.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: widget.icon != null
                ? PhosphorIcon(widget.icon!, size: 12, color: color)
                : Text(
                    widget.label ?? '',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
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
    return SizedBox(
      width: 24,
      child: ListView(
        padding: EdgeInsets.zero,
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
