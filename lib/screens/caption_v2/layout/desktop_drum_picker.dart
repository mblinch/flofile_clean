import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../caption_style/verb_index_filter_mode.dart';
import '../../../services/mlb_api_service.dart';
import '../../../services/mac_spell_check_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import '../widgets/base_row.dart';
import '../widgets/celebration_dropdown.dart';
import '../widgets/custom_name_entry.dart';
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
  /// Grid columns — polish mock is fixed at 4; A/A adjusts tile height instead.
  static const int _gridColumns = 4;
  double _tileHeight = 44;
  double _listRowHeight = 26;
  double _jerseyFontSize = 20;
  bool _groupByPosition = false;
  bool _favoritesFilterOn = false;
  final Set<String> _favoritePlayerKeys = {};
  bool _verbAccordionCollapsed = false;
  int? _appliedCascadeLimit;
  final Set<String> _extraOpenVerbCategories = {};
  final _homeFilter = TextEditingController();
  final _awayFilter = TextEditingController();
  final _homeFilterFocus = FocusNode(debugLabel: 'Drum home roster filter');
  final _awayFilterFocus = FocusNode(debugLabel: 'Drum away roster filter');
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
  Size? _lastVerbLaneSize;
  bool _verbFitScheduled = false;
  Size? _lastWindowSizeForPlayerFit;
  Size? _lastRosterBodySize;
  bool _playerFitScheduled = false;

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
    _homeFilterFocus.dispose();
    _awayFilterFocus.dispose();
    _customVerbController.dispose();
    _verbFilter.dispose();
    _verbFilterFocus.dispose();
    _customVerbFocusNode.dispose();
    super.dispose();
  }

  FocusNode _filterFocusFor(DrumLane lane) =>
      lane == DrumLane.home ? _homeFilterFocus : _awayFilterFocus;

  bool _isPlayerFavorite(Player player, {required bool isHome}) =>
      controller.isPlayerFavorite(player, isHome: isHome);

  Future<void> _togglePlayerFavorite(
    Player player, {
    required bool isHome,
  }) {
    return controller.togglePlayerFavorite(player, isHome: isHome);
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

  static const double _minTileHeight = 42;
  static const double _maxTileHeight = 64;

  void _stepTileHeight(int delta) {
    setState(() {
      _tileHeight =
          (_tileHeight + delta * 2).clamp(_minTileHeight, _maxTileHeight);
      _jerseyFontSize = (_tileHeight * 0.48).clamp(17.0, 26.0);
    });
  }

  void _stepListRowHeight(int delta) {
    setState(() {
      _listRowHeight = (_listRowHeight + delta * 2).clamp(20.0, 34.0);
    });
  }

  /// Roster Polish autofit: grow/shrink tile or list-row height to fill the
  /// body without scrolling (grid cols stay at 4).
  void _fitRosterMetrics() {
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
    // Players/Team/Teammates under the boxes (26 + top gap + bottom pad).
    const subjectDockH = 40.0;
    final avail = box.size.height - subjectDockH;
    if (avail <= 0 || players.isEmpty) return;

    if (_numberMode) {
      final cols = widget.numberColumns ??
          (widget.compactMobile ? 5 : _gridColumns);
      final tileRows = _RosterPolish.gridTileRows(
        players: players,
        columns: cols,
        groupByPosition: _groupByPosition,
        includeAddPlayer: !_groupByPosition,
      );
      if (tileRows <= 0) return;
      // Position headers XOR range labels — never both.
      final chrome = _groupByPosition
          ? 2 * 16.0 + (tileRows - 1) * 3.0
          : tileRows * 12.0 + (tileRows - 1) * 3.0;
      // Prefer taller tiles; scroll rather than going pancake-flat.
      final th =
          ((avail - chrome) / tileRows).clamp(_minTileHeight, _maxTileHeight);
      final nf = (th * 0.48).clamp(17.0, 26.0);
      if ((th - _tileHeight).abs() < 0.5 &&
          (nf - _jerseyFontSize).abs() < 0.5) {
        return;
      }
      setState(() {
        _tileHeight = th;
        _jerseyFontSize = nf;
      });
      return;
    }

    final sections = _RosterPolish.sections(
      players: players,
      groupByPosition: _groupByPosition,
    );
    final rowCount = players.length;
    if (rowCount <= 0) return;
    // Section titles + inter-section gap.
    const headerH = 16.0;
    const sectionGap = 4.0;
    final chrome = sections.length * headerH +
        (sections.length > 1 ? (sections.length - 1) * sectionGap : 0);
    final rh = ((avail - chrome) / rowCount).clamp(20.0, 34.0);
    if ((rh - _listRowHeight).abs() < 0.5) return;
    setState(() => _listRowHeight = rh);
  }

  void _fitRosterWhenReady({int attempt = 0}) {
    if (!mounted) return;
    final homeBox =
        _homeRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final awayBox =
        _awayRosterBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final ready = (homeBox != null && homeBox.hasSize) ||
        (awayBox != null && awayBox.hasSize);
    if (!ready) {
      if (attempt >= 8) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitRosterWhenReady(attempt: attempt + 1),
      );
      return;
    }
    _fitRosterMetrics();
  }

  void _schedulePlayerFit() {
    if (_playerFitScheduled) return;
    _playerFitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playerFitScheduled = false;
      if (!mounted) return;
      _fitRosterWhenReady();
    });
  }

  void _onRosterBodySizeMaybeChanged(Size size) {
    if (_lastRosterBodySize != null &&
        (_lastRosterBodySize!.width - size.width).abs() < 0.5 &&
        (_lastRosterBodySize!.height - size.height).abs() < 0.5) {
      return;
    }
    final first = _lastRosterBodySize == null;
    _lastRosterBodySize = size;
    if (!first) _schedulePlayerFit();
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

    const heightScale = 1.0; // cozy
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
    final window = MediaQuery.sizeOf(context);
    final windowChanged =
        _lastWindowSizeForPlayerFit != null && _lastWindowSizeForPlayerFit != window;
    final firstWindow = _lastWindowSizeForPlayerFit == null;
    _lastWindowSizeForPlayerFit = window;
    if (firstWindow || windowChanged) {
      _schedulePlayerFit();
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
                          const SizedBox(width: 6),
                          Expanded(child: lanes.last),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
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
                if (i > 0) const SizedBox(width: 6),
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
    return VerbIndexTopBar(
      controller: controller,
      filterController: _verbFilter,
      filterFocusNode: _verbFilterFocus,
      tokens: tokens,
      onFilterChanged: (_) {
        final query = _verbFilter.text.trim();
        setState(() {
          if (controller.verbListAll) {
            _verbMatchCount = query.isEmpty ? 0 : _verbs.length;
          }
        });
      },
      onFilterKey: (node, event) {
        if (controller.verbListAll) {
          return _onAzListFilterKey(event);
        }
        final panel = _verbIndexKey.currentState;
        if (panel == null) return KeyEventResult.ignored;
        return panel.onFilterKey(node, event);
      },
    );
  }

  int get _effectiveGridColumns =>
      widget.numberColumns ?? (widget.compactMobile ? 5 : _gridColumns);

  Future<void> _addRosterPlayer({required bool isHome}) async {
    final result = await showCustomNameEntryDialog(
      context: context,
      teamLabel: isHome ? controller.homeAbbr : controller.awayAbbr,
      title: 'Add player',
      confirmLabel: 'Add',
    );
    if (result == null || !mounted) return;
    final error = controller.addCustomPlayer(
      isHome: isHome,
      fullName: result.name,
      jerseyNumber: result.jersey,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
      );
      return;
    }
    _schedulePlayerFit();
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
    final pinnedHit = controller.pinnedPlayer;
    final pinnedForLane = pinnedHit != null && pinnedHit.isHome == isHome
        ? pinnedHit.player
        : null;

    int rosterIndexOf(Player player) => players.indexWhere(
          (item) =>
              item.fullName == player.fullName &&
              item.jerseyNumber == player.jerseyNumber,
        );

    Widget subjectDock() => _RosterSubjectDock(
          controller: controller,
          isHome: isHome,
          tokens: tokens,
        );

    Widget playerList() {
      return Expanded(
        key: lane == DrumLane.home ? _homeRosterBodyKey : _awayRosterBodyKey,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final box = (lane == DrumLane.home
                      ? _homeRosterBodyKey
                      : _awayRosterBodyKey)
                  .currentContext
                  ?.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                _onRosterBodySizeMaybeChanged(box.size);
              }
            });
            return false;
          },
          child: SizeChangedLayoutNotifier(
            child: visiblePlayers.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            _filterFor(lane).text.trim().isNotEmpty ||
                                    letterFilter != null
                                ? 'No match'
                                : 'No players',
                            style: tokens.metaStyle.copyWith(
                              color: tokens.text.withValues(alpha: 0.34),
                            ),
                          ),
                        ),
                      ),
                      subjectDock(),
                    ],
                  )
                : _numberMode
                    ? _PolishNumberRoster(
                        players: visiblePlayers,
                        columns: _effectiveGridColumns,
                        tileHeight: _tileHeight,
                        jerseyFontSize: _jerseyFontSize,
                        groupByPosition: _groupByPosition,
                        tokens: tokens,
                        footer: subjectDock(),
                        favoritesMode: _favoritesFilterOn,
                        isFavorite: (player) => _isPlayerFavorite(
                          player,
                          isHome: isHome,
                        ),
                        isSelected: (player) => controller.isPlayerSelected(
                          player,
                          isHome: isHome,
                        ),
                        isPinned: (player) => controller.isPlayerPinned(
                          player,
                          isHome: isHome,
                        ),
                        onCommit: (player) =>
                            _commit(lane, rosterIndexOf(player)),
                        onPin: (player) => controller.togglePlayerPin(
                          player,
                          isHome: isHome,
                        ),
                        onSecondaryTap: (player, position) =>
                            _editRosterPlayer(
                          context,
                          player: player,
                          isHome: isHome,
                          position: position,
                        ),
                        onAddPlayer: _groupByPosition
                            ? null
                            : () => _addRosterPlayer(isHome: isHome),
                      )
                    : letterFilter != null &&
                            widget.mode == DrumPickerMode.scroll
                        ? _FilteredPlayerList(
                            letter: letterFilter,
                            players: visiblePlayers,
                            tokens: tokens,
                            nameFor: controller.playerListName,
                            footer: subjectDock(),
                            isPinned: (player) => controller.isPlayerPinned(
                              player,
                              isHome: isHome,
                            ),
                            onBack: () => setState(() {
                              if (lane == DrumLane.home) {
                                _homeLetterFilter = null;
                              } else {
                                _awayLetterFilter = null;
                              }
                            }),
                            onSelect: (player) =>
                                _commit(lane, rosterIndexOf(player)),
                            onPin: (player) => controller.togglePlayerPin(
                              player,
                              isHome: isHome,
                            ),
                            onGoogle: (player) => openPlayerGoogleSearch(
                              fullName: player.fullName,
                              sportId: controller.sport,
                            ),
                            onReport: (player) => _reportRosterPlayer(
                              player: player,
                              isHome: isHome,
                            ),
                            onEdit: (player, position) => _editRosterPlayer(
                              context,
                              player: player,
                              isHome: isHome,
                              position: position,
                            ),
                          )
                        : _PolishListRoster(
                            players: visiblePlayers,
                            rowHeight: _listRowHeight,
                            groupByPosition: _groupByPosition,
                            sortByNumber:
                                controller.rosterSort == RosterSortMode.number,
                            tokens: tokens,
                            footer: subjectDock(),
                            favoritesMode: _favoritesFilterOn,
                            isFavorite: (player) => _isPlayerFavorite(
                              player,
                              isHome: isHome,
                            ),
                            isSelected: (player) =>
                                controller.isPlayerSelected(
                              player,
                              isHome: isHome,
                            ),
                            isPinned: (player) => controller.isPlayerPinned(
                              player,
                              isHome: isHome,
                            ),
                            onCommit: (player) =>
                                _commit(lane, rosterIndexOf(player)),
                            onPin: (player) => controller.togglePlayerPin(
                              player,
                              isHome: isHome,
                            ),
                            onSecondaryTap: (player, position) =>
                                _editRosterPlayer(
                              context,
                              player: player,
                              isHome: isHome,
                              position: position,
                            ),
                            onCycleSort: () {
                              controller.cycleRosterSortField();
                              _schedulePlayerFit();
                            },
                          ),
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

    final textSizeValue = _numberMode
        ? _jerseyFontSize.round()
        : _listRowHeight.round();

    return Column(
      children: [
        _RosterTopBar(
          abbr: title.toUpperCase(),
          filterController: _filterFor(lane),
          filterFocusNode: _filterFocusFor(lane),
          pinnedPlayer: pinnedForLane,
          favoritesOn: _favoritesFilterOn,
          onFavoritesToggle: () =>
              setState(() => _favoritesFilterOn = !_favoritesFilterOn),
          onFilterChanged: (_) => _onRosterFilterChanged(lane),
          onUnpin: pinnedForLane == null
              ? null
              : () => controller.togglePlayerPin(
                    pinnedForLane,
                    isHome: isHome,
                  ),
          onSelectPinned: pinnedForLane == null
              ? null
              : () => _commit(lane, rosterIndexOf(pinnedForLane)),
          gear: PlayerGearMenu(
            textSizeValue: textSizeValue,
            canTextSmaller: _numberMode
                ? _tileHeight > _minTileHeight
                : _listRowHeight > 20,
            canTextLarger: _numberMode
                ? _tileHeight < _maxTileHeight
                : _listRowHeight < 34,
            onTextSmaller: () => _numberMode
                ? _stepTileHeight(-1)
                : _stepListRowHeight(-1),
            onTextLarger: () => _numberMode
                ? _stepTileHeight(1)
                : _stepListRowHeight(1),
            onTextFit: _schedulePlayerFit,
            groupByPosition: _groupByPosition,
            onGroupByPosition: (grouped) {
              setState(() => _groupByPosition = grouped);
              _schedulePlayerFit();
            },
            numberMode: _numberMode,
            onNumbers: () {
              setState(() {
                _numberMode = true;
                _homeLetterFilter = null;
                _awayLetterFilter = null;
              });
              _schedulePlayerFit();
            },
            onNames: () {
              setState(() => _numberMode = false);
              _schedulePlayerFit();
            },
            onEditTeam: widget.onEditRosters,
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
    final favorite = _isPlayerFavorite(player, isHome: isHome);
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
          value: 'favorite',
          child: Text(
            favorite ? 'Remove from Favorites' : 'Add to Favorites',
          ),
        ),
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
    if (action == 'favorite') {
      _togglePlayerFavorite(player, isHome: isHome);
      return;
    }
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

  void _scheduleVerbFitOnLaneResize(BoxConstraints constraints) {
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    if (_lastVerbLaneSize != null &&
        (_lastVerbLaneSize!.width - size.width).abs() < 0.5 &&
        (_lastVerbLaneSize!.height - size.height).abs() < 0.5) {
      return;
    }
    final first = _lastVerbLaneSize == null;
    _lastVerbLaneSize = size;
    if (first || _verbFitScheduled) return;
    _verbFitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _verbFitScheduled = false;
      if (!mounted) return;
      await _fitVerbText();
    });
  }

  Widget _verbLane(FfTokens tokens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleVerbFitOnLaneResize(constraints);
        final showCustom = constraints.maxHeight >= 140;
        final selectedKey = controller.selectedVerb;
        final showRbi =
            selectedKey != null && controller.verbNeedsRbi(selectedKey);
        final showBase =
            selectedKey != null && controller.verbNeedsBase(selectedKey);
        final showCelebration = selectedKey != null &&
            controller.verbNeedsCelebration(selectedKey);
        // Flush with roster lanes — same 36px top bar, no extra top pad, so
        // the first jersey-range rule lines up with History.
        return Column(
          children: [
            _verbTopLine(tokens),
            Expanded(
              child: controller.verbListAll
                  ? _azListLane(tokens: tokens)
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
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
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
        );
      },
    );
  }

  /// Simple list layout (Layout → A–Z): optional history + letter or category
  /// bands. Pin lives in [VerbIndexTopBar] (same as Index) — no second pin row.
  Widget _azListLane({
    required FfTokens tokens,
  }) {
    final baseFont = 13 * controller.verbFontScale;
    final fontSize = baseFont; // cozy
    const heightScale = 1.0; // cozy
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
        if (history.isNotEmpty)
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
    final limit = controller.verbIndexHistoryLimit.clamp(
      1,
      CaptionV2Controller.verbIndexHistoryLimitMax,
    );
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
      height: 26,
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
  /// Multiplies row height (fixed at cozy = 1.0).
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
                      fontWeight: FontWeight.w400,
                      fontVariations: [
                        const FontVariation('wght', 400),
                        FontVariation('opsz', fontSize.clamp(14.0, 32.0)),
                      ],
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
    this.footer,
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
  final Widget? footer;
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
            itemCount: players.length + (footer != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (footer != null && index == players.length) {
                return footer!;
              }
              final player = players[index];
              return SizedBox(
                height: 22,
                child: _HoverablePlayerActionsRow(
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


/// Shared position grouping + autofit math for Roster Polish.
class _RosterPolish {
  static bool isGoalie(Player player) {
    final pos = (player.position ?? '').toUpperCase().trim();
    return pos == 'G' || pos == 'GK' || pos == 'GOALIE';
  }

  static bool isForward(Player player) {
    final pos = (player.position ?? '').toUpperCase().trim();
    return const {
      'F',
      'C',
      'LW',
      'RW',
      'W',
      'FW',
      'FORWARD',
      'CENTRE',
      'CENTER',
    }.contains(pos);
  }

  static bool isDefense(Player player) {
    final pos = (player.position ?? '').toUpperCase().trim();
    return const {
      'D',
      'LD',
      'RD',
      'DEF',
      'DEFENSE',
      'DEFENCE',
    }.contains(pos);
  }

  static String lastName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return player.fullName.trim();
    return parts.sublist(1).join(' ');
  }

  static String firstName(Player player) {
    final first = player.firstName.trim();
    if (first.isNotEmpty) return first;
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  static int? jersey(Player player) {
    var raw = player.jerseyNumber?.trim() ?? '';
    while (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    final number = int.tryParse(raw);
    if (number == null || number < 0 || number > 99) return null;
    return number;
  }

  static List<({String title, List<Player> players})> sections({
    required List<Player> players,
    required bool groupByPosition,
  }) {
    if (!groupByPosition) {
      return [(title: 'All players', players: List<Player>.from(players))];
    }
    final forwards = <Player>[];
    final defenseGoalies = <Player>[];
    final other = <Player>[];
    for (final player in players) {
      if (isForward(player)) {
        forwards.add(player);
      } else if (isDefense(player) || isGoalie(player)) {
        defenseGoalies.add(player);
      } else {
        other.add(player);
      }
    }
    if (forwards.isEmpty && defenseGoalies.isEmpty) {
      return [(title: 'All players', players: List<Player>.from(players))];
    }
    final out = <({String title, List<Player> players})>[];
    if (forwards.isNotEmpty) {
      out.add((title: 'Forwards', players: forwards));
    }
    if (defenseGoalies.isNotEmpty) {
      out.add((title: 'Defense · Goalies', players: defenseGoalies));
    }
    if (other.isNotEmpty) {
      out.add((title: 'Other', players: other));
    }
    return out;
  }

  static int gridTileRows({
    required List<Player> players,
    required int columns,
    required bool groupByPosition,
    required bool includeAddPlayer,
  }) {
    final cols = columns.clamp(1, 12);
    final secs = sections(players: players, groupByPosition: groupByPosition);
    var rows = 0;
    for (final section in secs) {
      final numbered = section.players.where((p) => jersey(p) != null).length;
      final other = section.players.length - numbered;
      if (numbered > 0) rows += (numbered / cols).ceil();
      if (other > 0) rows += (other / cols).ceil();
    }
    if (includeAddPlayer && !groupByPosition) rows += 1;
    return rows;
  }

  static List<Player> sortPlayers(
    List<Player> players, {
    required bool byNumber,
  }) {
    final out = List<Player>.from(players);
    out.sort((a, b) {
      if (byNumber) {
        final an = jersey(a);
        final bn = jersey(b);
        if (an != null && bn != null && an != bn) return an.compareTo(bn);
        if (an != null && bn == null) return -1;
        if (an == null && bn != null) return 1;
      }
      return lastName(a).toLowerCase().compareTo(lastName(b).toLowerCase());
    });
    return out;
  }

  /// Dense number-sorted rows with a range label from the jerseys in that row
  /// (e.g. "8–28"). Fills every column — no empty decade gaps.
  static List<({String title, List<Player> players})> numberSortedRows({
    required List<Player> players,
    required int columns,
  }) {
    final cols = columns.clamp(1, 12);
    final numbered = <Player>[];
    final other = <Player>[];
    for (final player in sortPlayers(players, byNumber: true)) {
      if (jersey(player) != null) {
        numbered.add(player);
      } else {
        other.add(player);
      }
    }
    final out = <({String title, List<Player> players})>[];
    for (var i = 0; i < numbered.length; i += cols) {
      final end = i + cols > numbered.length ? numbered.length : i + cols;
      final row = numbered.sublist(i, end);
      out.add((title: _rangeLabel(row), players: row));
    }
    if (other.isNotEmpty) {
      out.add((title: 'No number', players: other));
    }
    return out;
  }

  static String _rangeLabel(List<Player> row) {
    var min = jersey(row.first)!;
    var max = min;
    for (final player in row) {
      final n = jersey(player)!;
      if (n < min) min = n;
      if (n > max) max = n;
    }
    if (min == max) return '$min';
    return '$min–$max';
  }
}

class _PolishNumberRoster extends StatelessWidget {
  const _PolishNumberRoster({
    required this.players,
    required this.columns,
    required this.tileHeight,
    required this.jerseyFontSize,
    required this.groupByPosition,
    required this.tokens,
    required this.isSelected,
    required this.isPinned,
    required this.onCommit,
    this.footer,
    this.onPin,
    this.onSecondaryTap,
    this.onAddPlayer,
    this.favoritesMode = false,
    this.isFavorite,
  });

  final List<Player> players;
  final int columns;
  final double tileHeight;
  final double jerseyFontSize;
  final bool groupByPosition;
  final FfTokens tokens;
  final bool Function(Player player) isSelected;
  final bool Function(Player player) isPinned;
  final ValueChanged<Player> onCommit;
  final Widget? footer;
  final ValueChanged<Player>? onPin;
  final void Function(Player player, Offset globalPosition)? onSecondaryTap;
  final bool favoritesMode;
  final bool Function(Player player)? isFavorite;
  final VoidCallback? onAddPlayer;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, 12);
    // Position headers XOR number-range labels — never both.
    if (groupByPosition) {
      final sections = _RosterPolish.sections(
        players: players,
        groupByPosition: true,
      );
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              _RosterSectionHeader(
                title: sections[i].title,
                tokens: tokens,
                topPad: i == 0 ? 0 : 4,
              ),
              _PolishTileGrid(
                players: _RosterPolish.sortPlayers(
                  sections[i].players,
                  byNumber: true,
                ),
                columns: cols,
                tileHeight: tileHeight,
                jerseyFontSize: jerseyFontSize,
                tokens: tokens,
                isSelected: isSelected,
                isPinned: isPinned,
                favoritesMode: favoritesMode,
                isFavorite: isFavorite,
                onCommit: onCommit,
                onPin: onPin,
                onSecondaryTap: onSecondaryTap,
              ),
            ],
            if (footer != null) footer!,
          ],
        ),
      );
    }

    final rows = _RosterPolish.numberSortedRows(
      players: players,
      columns: cols,
    );
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _RosterRangeLabel(
              title: rows[i].title,
              tokens: tokens,
              isFirst: i == 0,
            ),
            _PolishTileGrid(
              players: rows[i].players,
              columns: cols,
              tileHeight: tileHeight,
              jerseyFontSize: jerseyFontSize,
              tokens: tokens,
              isSelected: isSelected,
              isPinned: isPinned,
              favoritesMode: favoritesMode,
              isFavorite: isFavorite,
              onCommit: onCommit,
              onPin: onPin,
              onSecondaryTap: onSecondaryTap,
              onAddPlayer: i == rows.length - 1 ? onAddPlayer : null,
            ),
          ],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _PolishTileGrid extends StatelessWidget {
  const _PolishTileGrid({
    required this.players,
    required this.columns,
    required this.tileHeight,
    required this.jerseyFontSize,
    required this.tokens,
    required this.isSelected,
    required this.isPinned,
    required this.onCommit,
    this.onPin,
    this.onSecondaryTap,
    this.onAddPlayer,
    this.favoritesMode = false,
    this.isFavorite,
  });

  final List<Player> players;
  final int columns;
  final double tileHeight;
  final double jerseyFontSize;
  final FfTokens tokens;
  final bool Function(Player player) isSelected;
  final bool Function(Player player) isPinned;
  final ValueChanged<Player> onCommit;
  final ValueChanged<Player>? onPin;
  final void Function(Player player, Offset globalPosition)? onSecondaryTap;
  final VoidCallback? onAddPlayer;
  final bool favoritesMode;
  final bool Function(Player player)? isFavorite;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (final player in players)
        _PolishGridTile(
          key: ValueKey(
            '${player.playerId ?? player.fullName}|${player.jerseyNumber ?? ''}',
          ),
          player: player,
          height: tileHeight,
          jerseyFontSize: jerseyFontSize,
          selected: isSelected(player),
          pinned: isPinned(player),
          favorite: isFavorite?.call(player) ?? false,
          favoritesMode: favoritesMode,
          tokens: tokens,
          onTap: () => onCommit(player),
          onPin: onPin == null ? null : () => onPin!(player),
          onSecondaryTap: onSecondaryTap == null
              ? null
              : (position) => onSecondaryTap!(player, position),
        ),
      if (onAddPlayer != null)
        _PolishAddPlayerTile(
          height: tileHeight,
          tokens: tokens,
          onTap: onAddPlayer!,
        ),
    ];
    final rowCount = cells.isEmpty ? 0 : (cells.length / columns).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: 3),
          SizedBox(
            height: tileHeight,
            child: Row(
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 3),
                  Expanded(
                    child: row * columns + col < cells.length
                        ? cells[row * columns + col]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PolishGridTile extends StatefulWidget {
  const _PolishGridTile({
    super.key,
    required this.player,
    required this.height,
    required this.jerseyFontSize,
    required this.selected,
    required this.pinned,
    required this.tokens,
    required this.onTap,
    this.onPin,
    this.onSecondaryTap,
    this.favorite = false,
    this.favoritesMode = false,
  });

  final Player player;
  final double height;
  final double jerseyFontSize;
  final bool selected;
  final bool pinned;
  final bool favorite;
  final bool favoritesMode;
  final FfTokens tokens;
  final VoidCallback onTap;
  final VoidCallback? onPin;
  final ValueChanged<Offset>? onSecondaryTap;

  @override
  State<_PolishGridTile> createState() => _PolishGridTileState();
}

class _PolishGridTileState extends State<_PolishGridTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected || widget.pinned;
    final goalie = _RosterPolish.isGoalie(widget.player);
    final fill = selected
        ? FfTokens.nocturneAccentSoft
        : (_hovered ? const Color(0xFF2A3138) : const Color(0xFF232A31));
    final border = selected
        ? FfTokens.nocturneAccentEdge
        : const Color(0x0DE8EEF4);
    final nameColor =
        selected ? const Color(0xFF9FC3D6) : FfTokens.nocturneT2;
    final favGlow = widget.favoritesMode && widget.favorite;
    final numberColor = favGlow
        ? FfTokens.gold
        : (selected ? Colors.white : const Color(0xFFF2F6FA));
    final last = _RosterPolish.lastName(widget.player).toUpperCase();
    final jersey = widget.player.jerseyNumber?.trim();
    final jerseyLabel =
        (jersey == null || jersey.isEmpty) ? '—' : jersey;
    final faded = widget.favoritesMode && !widget.favorite;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CmdClick(
        onTap: widget.onTap,
        onCmdTap: widget.onPin,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: widget.height,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0DFFFFFF),
                    blurRadius: 0,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FittingLastName(
                    text: last,
                    color: nameColor,
                  ),
                  Text(
                    jerseyLabel,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: widget.jerseyFontSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      color: numberColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(
                          color: favGlow
                              ? const Color(0x8CE8C547)
                              : numberColor.withValues(alpha: 0.35),
                          blurRadius: favGlow ? 8 : (selected ? 10 : 6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.pinned)
              const Positioned(
                right: 2,
                top: 2,
                child: PhosphorIcon(
                  PhosphorIconsFill.pushPin,
                  size: 9,
                  color: FfTokens.accentHover,
                ),
              ),
            if (goalie)
              Positioned(
                right: 2,
                bottom: 2,
                child: Opacity(
                  opacity: 0.7,
                  child: Container(
                    width: 10,
                    height: 10,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FfTokens.nocturneAccentEdge,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'G',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (faded) return Opacity(opacity: 0.32, child: tile);
    return tile;
  }
}

class _FittingLastName extends StatelessWidget {
  const _FittingLastName({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  static const double _baseSize = 8.5;
  static const double _minSize = 5.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const style = TextStyle(
          fontFamily: FfTokens.labelFamily,
          fontSize: _baseSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          height: 1.15,
        );
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        var size = _baseSize;
        if (maxW > 0 && painter.width > maxW) {
          size = (_baseSize * maxW / painter.width).clamp(_minSize, _baseSize);
        }
        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: FfTokens.labelFamily,
            fontSize: size,
            fontWeight: FontWeight.w500,
            letterSpacing: size < _baseSize ? 0.15 : 0.3,
            height: 1.15,
            color: color,
          ),
        );
      },
    );
  }
}

class _PolishAddPlayerTile extends StatefulWidget {
  const _PolishAddPlayerTile({
    required this.height,
    required this.tokens,
    required this.onTap,
  });

  final double height;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_PolishAddPlayerTile> createState() => _PolishAddPlayerTileState();
}

class _PolishAddPlayerTileState extends State<_PolishAddPlayerTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        _hovered ? widget.tokens.text : widget.tokens.textTertiary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: color.withValues(alpha: _hovered ? 0.3 : 0.14),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PhosphorIcon(PhosphorIconsRegular.plus, size: 15, color: color),
              const SizedBox(height: 2),
              Text(
                'Player',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
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

class _PolishListRoster extends StatelessWidget {
  const _PolishListRoster({
    required this.players,
    required this.rowHeight,
    required this.groupByPosition,
    required this.sortByNumber,
    required this.tokens,
    required this.isSelected,
    required this.isPinned,
    required this.onCommit,
    this.footer,
    this.onPin,
    this.onSecondaryTap,
    this.onCycleSort,
    this.favoritesMode = false,
    this.isFavorite,
  });

  final List<Player> players;
  final double rowHeight;
  final bool groupByPosition;
  final bool sortByNumber;
  final FfTokens tokens;
  final bool Function(Player player) isSelected;
  final bool Function(Player player) isPinned;
  final ValueChanged<Player> onCommit;
  final Widget? footer;
  final ValueChanged<Player>? onPin;
  final void Function(Player player, Offset globalPosition)? onSecondaryTap;
  final VoidCallback? onCycleSort;
  final bool favoritesMode;
  final bool Function(Player player)? isFavorite;

  @override
  Widget build(BuildContext context) {
    final sections = _RosterPolish.sections(
      players: players,
      groupByPosition: groupByPosition,
    );
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            _RosterSectionHeader(
              title: sections[i].title,
              tokens: tokens,
              topPad: i == 0 ? 0 : 4,
              trailing: i == 0 && onCycleSort != null
                  ? _RosterSortChip(
                      sortByNumber: sortByNumber,
                      tokens: tokens,
                      onTap: onCycleSort!,
                    )
                  : null,
            ),
            for (final player in _RosterPolish.sortPlayers(
              sections[i].players,
              byNumber: sortByNumber,
            ))
              _PolishListRow(
                player: player,
                height: rowHeight,
                selected: isSelected(player),
                pinned: isPinned(player),
                favorite: isFavorite?.call(player) ?? false,
                favoritesMode: favoritesMode,
                tokens: tokens,
                onTap: () => onCommit(player),
                onPin: onPin == null ? null : () => onPin!(player),
                onSecondaryTap: onSecondaryTap == null
                    ? null
                    : (position) => onSecondaryTap!(player, position),
              ),
          ],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _PolishListRow extends StatefulWidget {
  const _PolishListRow({
    required this.player,
    required this.height,
    required this.selected,
    required this.pinned,
    required this.tokens,
    required this.onTap,
    this.onPin,
    this.onSecondaryTap,
    this.favorite = false,
    this.favoritesMode = false,
  });

  final Player player;
  final double height;
  final bool selected;
  final bool pinned;
  final bool favorite;
  final bool favoritesMode;
  final FfTokens tokens;
  final VoidCallback onTap;
  final VoidCallback? onPin;
  final ValueChanged<Offset>? onSecondaryTap;

  @override
  State<_PolishListRow> createState() => _PolishListRowState();
}

class _PolishListRowState extends State<_PolishListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected || widget.pinned;
    final goalie = _RosterPolish.isGoalie(widget.player);
    final first = _RosterPolish.firstName(widget.player);
    final last = _RosterPolish.lastName(widget.player);
    final jersey = widget.player.jerseyNumber?.trim();
    final jerseyLabel =
        (jersey == null || jersey.isEmpty) ? '—' : jersey;
    // Scale type with autofit row height (base design is 26px).
    final scale = (widget.height / 26.0).clamp(0.78, 1.25);
    final jerseySize = 14.0 * scale;
    final nameSize = 13.5 * scale;
    final favGlow = widget.favoritesMode && widget.favorite;
    final faded = widget.favoritesMode && !widget.favorite;
    final jerseyColor = favGlow ? FfTokens.gold : const Color(0xFFF2F6FA);

    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CmdClick(
        onTap: widget.onTap,
        onCmdTap: widget.onPin,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: widget.height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              decoration: BoxDecoration(
                color: selected
                    ? FfTokens.nocturneAccentSoft
                    : (_hovered
                        ? const Color(0x0FE8EEF4)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(7),
                border: selected
                    ? Border.all(color: FfTokens.nocturneAccentEdge)
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      jerseyLabel,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: jerseySize,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: jerseyColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: [
                          Shadow(
                            color: favGlow
                                ? const Color(0x8CE8C547)
                                : Colors.white.withValues(
                                    alpha: selected ? 0.55 : 0.35,
                                  ),
                            blurRadius: favGlow ? 8 : (selected ? 10 : 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (first.isNotEmpty)
                            TextSpan(
                              text: '$first ',
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: nameSize,
                                fontWeight: FontWeight.w400,
                                height: 1,
                                color: FfTokens.nocturneT2,
                              ),
                            ),
                          TextSpan(
                            text: last,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: nameSize,
                              fontWeight: FontWeight.w500,
                              height: 1,
                              color: selected
                                  ? Colors.white
                                  : FfTokens.nocturneTx,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (goalie)
                    Opacity(
                      opacity: 0.7,
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 10 * scale,
                        height: 10 * scale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: FfTokens.nocturneAccentEdge,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.pinned)
              Positioned(
                right: 5,
                top: 3,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: FfTokens.accentHover,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF181D22),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (faded) return Opacity(opacity: 0.32, child: row);
    return row;
  }
}

class _RosterSectionHeader extends StatelessWidget {
  const _RosterSectionHeader({
    required this.title,
    required this.tokens,
    this.topPad = 0,
    this.trailing,
  });

  final String title;
  final FfTokens tokens;
  final double topPad;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 2, left: 2, right: 2),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              height: 1.2,
              color: tokens.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: tokens.text.withValues(alpha: 0.08),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Compact jersey-range label above each dense number row (e.g. "8–28").
class _RosterRangeLabel extends StatelessWidget {
  const _RosterRangeLabel({
    required this.title,
    required this.tokens,
    this.isFirst = false,
  });

  final String title;
  final FfTokens tokens;

  /// First row sits flush under the top bar (aligned with verb History).
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      title,
      style: TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1,
        color: tokens.textTertiary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final rule = Container(
      height: 1,
      color: tokens.text.withValues(alpha: 0.06),
    );

    // First rule pins to the content top — same Y as History's top edge.
    if (isFirst) {
      return Padding(
        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 2),
        child: SizedBox(
          height: 11,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(width: 6),
              Expanded(child: rule),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 1, left: 2, right: 2),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            label,
            const SizedBox(width: 6),
            Expanded(child: rule),
          ],
        ),
      ),
    );
  }
}

class _RosterSortChip extends StatefulWidget {
  const _RosterSortChip({
    required this.sortByNumber,
    required this.tokens,
    required this.onTap,
  });

  final bool sortByNumber;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_RosterSortChip> createState() => _RosterSortChipState();
}

class _RosterSortChipState extends State<_RosterSortChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        _hovered ? widget.tokens.text : widget.tokens.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: FfTokens.nocturneHv,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.sortByNumber ? '#' : 'A–Z',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: color,
                ),
              ),
              const SizedBox(width: 3),
              PhosphorIcon(
                PhosphorIconsBold.arrowDown,
                size: 9,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Roster panel top bar — TOR · 🔍 · ☆ · | pin | · ⚙
class _RosterTopBar extends StatefulWidget {
  const _RosterTopBar({
    required this.abbr,
    required this.filterController,
    required this.filterFocusNode,
    required this.favoritesOn,
    required this.onFavoritesToggle,
    required this.onFilterChanged,
    required this.gear,
    this.pinnedPlayer,
    this.onUnpin,
    this.onSelectPinned,
  });

  final String abbr;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;
  final bool favoritesOn;
  final VoidCallback onFavoritesToggle;
  final ValueChanged<String> onFilterChanged;
  final Widget gear;
  final Player? pinnedPlayer;
  final VoidCallback? onUnpin;
  final VoidCallback? onSelectPinned;

  static const double barHeight = 36;

  @override
  State<_RosterTopBar> createState() => _RosterTopBarState();
}

class _RosterTopBarState extends State<_RosterTopBar>
    with SingleTickerProviderStateMixin {
  static const _expandMs = Duration(milliseconds: 220);
  static const _ease = Cubic(0.2, 0.8, 0.2, 1);

  bool _searchOpen = false;
  bool _searchHovered = false;
  bool _favHovered = false;
  late final AnimationController _expand;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(vsync: this, duration: _expandMs);
    widget.filterController.addListener(_onFilterText);
    widget.filterFocusNode.addListener(_onFilterFocus);
    if (widget.filterController.text.isNotEmpty ||
        widget.filterFocusNode.hasFocus) {
      _searchOpen = true;
      _expand.value = 1;
    }
  }

  @override
  void dispose() {
    widget.filterController.removeListener(_onFilterText);
    widget.filterFocusNode.removeListener(_onFilterFocus);
    _expand.dispose();
    super.dispose();
  }

  void _onFilterText() {
    widget.onFilterChanged(widget.filterController.text);
    if (widget.filterController.text.isNotEmpty && !_searchOpen) {
      _openSearch(requestFocus: false);
    }
    setState(() {});
  }

  void _onFilterFocus() {
    if (widget.filterFocusNode.hasFocus) {
      if (!_searchOpen) _openSearch(requestFocus: false);
    } else if (widget.filterController.text.isEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        if (!widget.filterFocusNode.hasFocus &&
            widget.filterController.text.isEmpty) {
          _closeSearch();
        }
      });
    }
  }

  void _openSearch({bool requestFocus = true}) {
    if (_searchOpen && _expand.value == 1) {
      if (requestFocus) widget.filterFocusNode.requestFocus();
      return;
    }
    setState(() => _searchOpen = true);
    _expand.forward();
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.filterFocusNode.requestFocus();
      });
    }
  }

  void _closeSearch() {
    widget.filterController.clear();
    widget.filterFocusNode.unfocus();
    _expand.reverse().whenComplete(() {
      if (mounted) setState(() => _searchOpen = false);
    });
    setState(() {});
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final searchVisible = _searchOpen || _expand.value > 0;
    final pinned = widget.pinnedPlayer;
    final hideChrome = searchVisible;

    return SizedBox(
      height: _RosterTopBar.barHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: LayoutBuilder(
            builder: (context, constraints) {
              // Team label ~40px; gear 26 + gap → search spans the middle.
              const gearReserve = 30.0;
              final teamW = _measureTeamWidth(widget.abbr);
              final searchLeft = teamW;
              final searchFullW = math.max(
                28.0,
                constraints.maxWidth - searchLeft - gearReserve,
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          widget.abbr,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            height: 1,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: hideChrome,
                        child: Opacity(
                          opacity: hideChrome ? 0 : 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RosterIconButton(
                                width: 26,
                                height: 26,
                                hovered: _searchHovered,
                                onHover: (v) =>
                                    setState(() => _searchHovered = v),
                                onTap: () => _openSearch(),
                                tooltip: 'Search players',
                                child: PhosphorIcon(
                                  PhosphorIconsRegular.magnifyingGlass,
                                  size: 14,
                                  color: _searchHovered
                                      ? FfTokens.nocturneTx
                                      : FfTokens.nocturneT2,
                                ),
                              ),
                              const _RosterVSep(tight: true),
                              _RosterIconButton(
                                width: 26,
                                height: 26,
                                hovered: _favHovered || widget.favoritesOn,
                                active: widget.favoritesOn,
                                activeColor: const Color(0x1FE8C547),
                                onHover: (v) =>
                                    setState(() => _favHovered = v),
                                onTap: widget.onFavoritesToggle,
                                tooltip: 'Favorite players',
                                child: PhosphorIcon(
                                  widget.favoritesOn
                                      ? PhosphorIconsFill.star
                                      : PhosphorIconsRegular.star,
                                  size: 14,
                                  color: widget.favoritesOn
                                      ? FfTokens.gold
                                      : (_favHovered
                                          ? FfTokens.nocturneTx
                                          : FfTokens.nocturneT2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: hideChrome,
                        child: Opacity(
                          opacity: hideChrome ? 0 : 1,
                          child: const _RosterVSep(),
                        ),
                      ),
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: hideChrome ? 0 : 1,
                          child: IgnorePointer(
                            ignoring: hideChrome,
                            child: Align(
                              alignment: pinned == null
                                  ? Alignment.center
                                  : Alignment.centerLeft,
                              child: _RosterPinSlot(
                                player: pinned,
                                onSelect: widget.onSelectPinned,
                                onUnpin: widget.onUnpin,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: hideChrome,
                        child: Opacity(
                          opacity: hideChrome ? 0 : 1,
                          child: const _RosterVSep(),
                        ),
                      ),
                      widget.gear,
                    ],
                  ),
                  if (searchVisible)
                    Positioned(
                      left: searchLeft,
                      top: 5,
                      height: 26,
                      child: AnimatedBuilder(
                        animation: _expand,
                        builder: (context, child) {
                          final t = _ease.transform(_expand.value);
                          final w = 28 + (searchFullW - 28) * t;
                          return SizedBox(
                            width: w,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                maxWidth: searchFullW,
                                minWidth: searchFullW,
                                child: SizedBox(
                                  width: searchFullW,
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: _RosterExpandingSearch(
                          controller: widget.filterController,
                          focusNode: widget.filterFocusNode,
                          onKeyEvent: _onSearchKey,
                          onClose: _closeSearch,
                        ),
                      ),
                    ),
                ],
              );
            },
        ),
      ),
    );
  }

  double _measureTeamWidth(String abbr) {
    final painter = TextPainter(
      text: TextSpan(
        text: abbr,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 6 + 2; // left pad + breathing room
  }
}

class _RosterVSep extends StatelessWidget {
  const _RosterVSep({this.tight = false});

  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tight ? 1 : 3),
      child: const SizedBox(
        width: 1,
        height: 18,
        child: ColoredBox(color: Color(0x1EE8EEF4)), // .12
      ),
    );
  }
}

class _RosterIconButton extends StatelessWidget {
  const _RosterIconButton({
    required this.width,
    required this.height,
    required this.hovered,
    required this.onHover,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.active = false,
    this.activeColor,
  });

  final double width;
  final double height;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? (activeColor ?? FfTokens.nocturneHv)
        : (hovered ? FfTokens.nocturneHv : Colors.transparent);
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: child,
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }
}

class _RosterExpandingSearch extends StatelessWidget {
  const _RosterExpandingSearch({
    required this.controller,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x594A7A96), // rgba(74,122,150,.35)
            blurRadius: 0,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SizedBox(
        height: 26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsRegular.magnifyingGlass,
                size: 14,
                color: FfTokens.nocturneT2,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Focus(
                  onKeyEvent: onKeyEvent,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: FfTokens.nocturneTx,
                      height: 1,
                    ),
                    cursorColor: FfTokens.nocturneAc,
                    cursorHeight: 13,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search players',
                      hintStyle: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: FfTokens.nocturneT3,
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Close (Esc)',
                waitDuration: const Duration(milliseconds: 400),
                child: _RosterSearchClose(onTap: onClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterSearchClose extends StatefulWidget {
  const _RosterSearchClose({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RosterSearchClose> createState() => _RosterSearchCloseState();
}

class _RosterSearchCloseState extends State<_RosterSearchClose> {
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
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x14E8EEF4) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.x,
            size: 11,
            color: _hovered ? FfTokens.nocturneTx : const Color(0xFF6A6E73),
          ),
        ),
      ),
    );
  }
}

class _RosterPinSlot extends StatefulWidget {
  const _RosterPinSlot({
    this.player,
    this.onSelect,
    this.onUnpin,
  });

  final Player? player;
  final VoidCallback? onSelect;
  final VoidCallback? onUnpin;

  @override
  State<_RosterPinSlot> createState() => _RosterPinSlotState();
}

class _RosterPinSlotState extends State<_RosterPinSlot> {
  bool _closeHovered = false;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    if (player == null) {
      return const SizedBox(
        height: 24,
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsRegular.pushPin,
              size: 12,
              color: FfTokens.pinnedHint,
            ),
            SizedBox(width: 5),
            Flexible(
              child: Text(
                'CMD+Click to pin player',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  color: FfTokens.pinnedHint,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final jersey = player.jerseyNumber?.trim();
    final jerseyLabel =
        (jersey == null || jersey.isEmpty) ? '—' : jersey;
    final last = _RosterPolish.lastName(player);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x1F4A7A96), // .12
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D4A7A96), // .30
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: SizedBox(
        height: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 0, 2, 0),
          child: Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsFill.pushPin,
                size: 11,
                color: FfTokens.accentHover,
              ),
              const SizedBox(width: 5),
              Text(
                jerseyLabel,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                  fontFeatures: [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(
                      color: Color(0xCC5A8EAB),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onSelect,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    last,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Unpin',
                waitDuration: const Duration(milliseconds: 400),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _closeHovered = true),
                  onExit: (_) => setState(() => _closeHovered = false),
                  child: GestureDetector(
                    onTap: widget.onUnpin,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 11,
                          color: _closeHovered
                              ? FfTokens.nocturneTx
                              : const Color(0xFF6A6E73),
                        ),
                      ),
                    ),
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


class _RosterSubjectDock extends StatelessWidget {
  const _RosterSubjectDock({
    required this.controller,
    required this.isHome,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final playersOn = controller.teamPlayersIsHome == isHome &&
        controller.teamSubjectKind == TeamSubjectKind.players;
    final teamOn = controller.teamPlayersIsHome == isHome &&
        controller.teamSubjectKind == TeamSubjectKind.name;
    final teammatesOn = controller.withTeammatesIsHome == isHome ||
        (controller.teamPlayersIsHome == isHome &&
            controller.teamSubjectKind == TeamSubjectKind.teammates);
    // Match _DrumCustomVerbField height (26). Gap above separates from last player.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
      child: Container(
        height: 26,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: FfTokens.nocturneSf,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.text.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SubjectDockButton(
                label: 'Players',
                icon: PhosphorIconsRegular.usersThree,
                selected: playersOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.players,
                ),
              ),
            ),
            Expanded(
              child: _SubjectDockButton(
                label: 'Team',
                icon: PhosphorIconsRegular.shield,
                selected: teamOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.name,
                ),
              ),
            ),
            Expanded(
              child: _SubjectDockButton(
                label: 'Teammates',
                icon: PhosphorIconsRegular.users,
                selected: teammatesOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.teammates,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectDockButton extends StatefulWidget {
  const _SubjectDockButton({
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
  State<_SubjectDockButton> createState() => _SubjectDockButtonState();
}

class _SubjectDockButtonState extends State<_SubjectDockButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected || _hovered
        ? FfTokens.nocturneTx
        : FfTokens.nocturneT2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          decoration: BoxDecoration(
            color: selected
                ? FfTokens.nocturneAccentSoft
                : (_hovered ? FfTokens.nocturneHv : Colors.transparent),
            borderRadius: BorderRadius.circular(5),
            border: selected
                ? Border.all(color: FfTokens.nocturneAccentEdge)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PhosphorIcon(widget.icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: color,
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
    this.groupByPosition,
    this.onNumbers,
    this.onNames,
    this.onGroupByPosition,
    this.onEditTeam,
    this.onReset,
    this.textSizeValue,
    this.canTextSmaller,
    this.canTextLarger,
    this.onTextSmaller,
    this.onTextLarger,
    this.onTextFit,
  });

  /// Null hides the layout rows and leaves Edit rosters.
  final bool? numberMode;
  final bool? groupByPosition;
  final VoidCallback? onNumbers;
  final VoidCallback? onNames;
  final ValueChanged<bool>? onGroupByPosition;
  final VoidCallback? onEditTeam;
  final VoidCallback? onReset;

  /// Compact Roster Top Bar gear: text size · group by · view.
  final int? textSizeValue;
  final bool? canTextSmaller;
  final bool? canTextLarger;
  final VoidCallback? onTextSmaller;
  final VoidCallback? onTextLarger;
  final VoidCallback? onTextFit;

  @override
  State<PlayerGearMenu> createState() => _PlayerGearMenuState();
}

class _PlayerGearMenuState extends State<PlayerGearMenu> {
  static const _menuWidth = 272.0;
  static const _legacyMenuWidth = 280.0;

  bool get _compactRosterMenu =>
      widget.textSizeValue != null &&
      widget.onTextSmaller != null &&
      widget.onTextLarger != null;

  OverlayEntry? _entry;
  bool _open = false;
  bool _hovered = false;
  bool _textFitOn = false;

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
    final menuW = _compactRosterMenu ? _menuWidth : _legacyMenuWidth;
    final origin = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    final overlaySize = overlayBox.size;
    const gap = 8.0;
    // Compact roster gear: open above, right-aligned to the gear.
    // Flip below only when there isn't room. Legacy: prefer beside/below.
    final preferLeft = origin.dx + box.size.width - menuW;
    final rightLeft = origin.dx + box.size.width + gap;
    final leftLeft = origin.dx - gap - menuW;
    final maxLeft = overlaySize.width - 8 - menuW;
    final opensRight = !_compactRosterMenu && rightLeft <= maxLeft;
    final left = (opensRight
            ? rightLeft
            : (_compactRosterMenu ? preferLeft : leftLeft))
        .clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft);
    final gearTop = origin.dy;
    final gearBottom = origin.dy + box.size.height;
    // Rough menu height (header + up to 3 rows + edit) for flip decision.
    const estimatedH = 220.0;
    final opensAbove =
        _compactRosterMenu && gearTop - gap - estimatedH >= 8;
    final double? top;
    final double? bottom;
    if (_compactRosterMenu) {
      top = opensAbove ? null : gearBottom + gap;
      bottom = opensAbove ? gearTop - gap : null;
    } else {
      top = origin.dy;
      bottom = null;
    }

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
                top: top,
                bottom: bottom,
                left: left,
                width: menuW,
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
                    child: _compactRosterMenu
                        ? _RosterGearCard(
                            opensAbove: opensAbove,
                            textSizeValue: widget.textSizeValue!,
                            textFitOn: _textFitOn,
                            canTextSmaller: widget.canTextSmaller ?? true,
                            canTextLarger: widget.canTextLarger ?? true,
                            onTextSmaller: () {
                              _textFitOn = false;
                              widget.onTextSmaller!();
                              _entry?.markNeedsBuild();
                            },
                            onTextLarger: () {
                              _textFitOn = false;
                              widget.onTextLarger!();
                              _entry?.markNeedsBuild();
                            },
                            onTextFit: widget.onTextFit == null
                                ? null
                                : () {
                                    _textFitOn = !_textFitOn;
                                    if (_textFitOn) widget.onTextFit!();
                                    _entry?.markNeedsBuild();
                                  },
                            groupByPosition: widget.groupByPosition ?? false,
                            onGroupByPosition: widget.onGroupByPosition,
                            numberMode: widget.numberMode ?? true,
                            onNumbers: widget.onNumbers,
                            onNames: widget.onNames,
                            onEditTeam: widget.onEditTeam == null
                                ? null
                                : () {
                                    final edit = widget.onEditTeam;
                                    _close();
                                    edit?.call();
                                  },
                          )
                        : _PlayerGearCard(
                            numberMode: widget.numberMode,
                            groupByPosition: widget.groupByPosition,
                            onNumbers: widget.onNumbers,
                            onNames: widget.onNames,
                            onGroupByPosition: widget.onGroupByPosition,
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
    if (!_layout &&
        widget.onEditTeam == null &&
        !_compactRosterMenu) {
      return const SizedBox.shrink();
    }
    final active = _open || _hovered;
    final size = _compactRosterMenu ? 26.0 : 24.0;
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
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
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

/// Compact roster gear — View · Group by · Text size · Edit.
class _RosterGearCard extends StatelessWidget {
  const _RosterGearCard({
    required this.textSizeValue,
    required this.textFitOn,
    required this.canTextSmaller,
    required this.canTextLarger,
    required this.onTextSmaller,
    required this.onTextLarger,
    required this.groupByPosition,
    required this.numberMode,
    this.opensAbove = true,
    this.onTextFit,
    this.onGroupByPosition,
    this.onNumbers,
    this.onNames,
    this.onEditTeam,
  });

  /// Caret on the bottom edge when opened above; top edge when flipped below.
  final bool opensAbove;
  final int textSizeValue;
  final bool textFitOn;
  final bool canTextSmaller;
  final bool canTextLarger;
  final VoidCallback onTextSmaller;
  final VoidCallback onTextLarger;
  final VoidCallback? onTextFit;
  final bool groupByPosition;
  final bool numberMode;
  final ValueChanged<bool>? onGroupByPosition;
  final VoidCallback? onNumbers;
  final VoidCallback? onNames;
  final VoidCallback? onEditTeam;

  static const _controlW = 150.0;

  @override
  Widget build(BuildContext context) {
    final showGroup = onGroupByPosition != null;
    final showView = onNumbers != null && onNames != null;

    return Padding(
      // Leave room for the caret diamond toward the gear.
      padding: EdgeInsets.only(
        top: opensAbove ? 0 : 5,
        bottom: opensAbove ? 5 : 0,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1E242A),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24E8EEF4), // .14
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: Text(
                      'ROSTER',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.84, // .08em
                        color: Color(0xFF6A6E73),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (showView)
                    _RosterGearRow(
                      label: 'View',
                      trailing: SizedBox(
                        width: _controlW,
                        child: _RosterSegPills(
                          left: 'Grid',
                          right: 'List',
                          leftIcon: PhosphorIconsRegular.squaresFour,
                          rightIcon: PhosphorIconsRegular.list,
                          rightSelected: !numberMode,
                          onLeft: onNumbers!,
                          onRight: onNames!,
                        ),
                      ),
                    ),
                  if (showGroup)
                    _RosterGearRow(
                      label: 'Group by',
                      trailing: SizedBox(
                        width: _controlW,
                        child: _RosterSegPills(
                          left: 'Number',
                          right: 'Position',
                          rightSelected: groupByPosition,
                          onLeft: () => onGroupByPosition!(false),
                          onRight: () => onGroupByPosition!(true),
                        ),
                      ),
                    ),
                  _RosterGearRow(
                    label: 'Text size',
                    trailing: SizedBox(
                      width: _controlW,
                      child: _RosterTextSizeStepper(
                        value: textSizeValue,
                        fitOn: textFitOn,
                        canSmaller: canTextSmaller,
                        canLarger: canTextLarger,
                        onSmaller: onTextSmaller,
                        onLarger: onTextLarger,
                        onFit: onTextFit,
                      ),
                    ),
                  ),
                  if (onEditTeam != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: ColoredBox(
                        color: Color(0x14E8EEF4), // .08
                        child: SizedBox(height: 1),
                      ),
                    ),
                    _RosterGearAction(
                      icon: PhosphorIconsRegular.pencilSimple,
                      label: 'Edit rosters',
                      onTap: onEditTeam!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Caret on the edge toward the gear (bottom when above).
          Positioned(
            right: 10,
            top: opensAbove ? null : -5,
            bottom: opensAbove ? -5 : null,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E242A),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x24E8EEF4),
                      offset: opensAbove
                          ? const Offset(1, 1)
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
  }
}

class _RosterGearRow extends StatelessWidget {
  const _RosterGearRow({
    required this.label,
    required this.trailing,
  });

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFE8EEF4),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _RosterGearAction extends StatefulWidget {
  const _RosterGearAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_RosterGearAction> createState() => _RosterGearActionState();
}

class _RosterGearActionState extends State<_RosterGearAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF262D35) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                widget.icon,
                size: 15,
                color: const Color(0xFF959AA0),
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFE8EEF4),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented track for Group by / View — equal-width pills, fixed outer width.
class _RosterSegPills extends StatelessWidget {
  const _RosterSegPills({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onLeft,
    required this.onRight,
    this.leftIcon,
    this.rightIcon,
  });

  final String left;
  final String right;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final bool rightSelected;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151A1E),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14E8EEF4), // inset approx via outer stroke
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              Expanded(
                child: _RosterSegPill(
                  label: left,
                  icon: leftIcon,
                  selected: !rightSelected,
                  onTap: onLeft,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _RosterSegPill(
                  label: right,
                  icon: rightIcon,
                  selected: rightSelected,
                  onTap: onRight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterSegPill extends StatefulWidget {
  const _RosterSegPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RosterSegPill> createState() => _RosterSegPillState();
}

class _RosterSegPillState extends State<_RosterSegPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final ink = selected
        ? Colors.white
        : (_hovered ? const Color(0xFFE8EEF4) : const Color(0xFF959AA0));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF20313C) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0xFF3A6076),
                      blurRadius: 0,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                PhosphorIcon(widget.icon!, size: 14, color: ink),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    color: ink,
                    decoration: TextDecoration.none,
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

class _RosterTextSizeStepper extends StatelessWidget {
  const _RosterTextSizeStepper({
    required this.value,
    required this.fitOn,
    required this.canSmaller,
    required this.canLarger,
    required this.onSmaller,
    required this.onLarger,
    this.onFit,
  });

  final int value;
  final bool fitOn;
  final bool canSmaller;
  final bool canLarger;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;
  final VoidCallback? onFit;

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
          children: [
            _RosterAaBtn(
              label: 'A',
              fontSize: 10,
              enabled: canSmaller || fitOn,
              onTap: onSmaller,
            ),
            Expanded(
              child: Text(
                fitOn ? 'Auto' : '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE8EEF4),
                  decoration: TextDecoration.none,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _RosterAaBtn(
              label: 'A',
              fontSize: 15,
              enabled: canLarger || fitOn,
              onTap: onLarger,
            ),
            if (onFit != null) ...[
              const SizedBox(
                width: 1,
                height: 28,
                child: ColoredBox(color: Color(0x1AE8EEF4)), // .10
              ),
              _RosterFitBtn(
                selected: fitOn,
                onTap: onFit!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RosterFitBtn extends StatefulWidget {
  const _RosterFitBtn({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RosterFitBtn> createState() => _RosterFitBtnState();
}

class _RosterFitBtnState extends State<_RosterFitBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected
        ? Colors.white
        : (_hovered ? Colors.white : const Color(0xFF959AA0));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF20313C)
                : (_hovered ? const Color(0xFF262D35) : Colors.transparent),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(7),
            ),
          ),
          child: Text(
            'Fit',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1,
              color: color,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterAaBtn extends StatefulWidget {
  const _RosterAaBtn({
    required this.label,
    required this.fontSize,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final double fontSize;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RosterAaBtn> createState() => _RosterAaBtnState();
}

class _RosterAaBtnState extends State<_RosterAaBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final color = !enabled
        ? const Color(0xFF959AA0).withValues(alpha: 0.45)
        : (_hovered ? Colors.white : const Color(0xFF959AA0));
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 26,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered && enabled
                ? const Color(0xFF262D35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w700,
              height: 1,
              color: color,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _GearMenuBeside extends SingleChildLayoutDelegate {
  _GearMenuBeside({
    this.top,
    this.bottom,
    required this.left,
    required this.width,
  }) : assert(top != null || bottom != null);

  /// Top edge of the menu when opening below / beside.
  final double? top;

  /// Bottom edge of the menu when opening above the gear.
  final double? bottom;
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
    final maxTop = size.height - 8 - childSize.height;
    var y = bottom != null ? bottom! - childSize.height : top!;
    if (y < 8) y = 8;
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
        bottom != oldDelegate.bottom ||
        left != oldDelegate.left ||
        width != oldDelegate.width;
  }
}

class _PlayerGearCard extends StatelessWidget {
  const _PlayerGearCard({
    required this.numberMode,
    required this.groupByPosition,
    required this.onNumbers,
    required this.onNames,
    required this.onGroupByPosition,
    required this.onEditTeam,
    required this.showReset,
    required this.onReset,
    required this.onClose,
  });

  final bool? numberMode;
  final bool? groupByPosition;
  final VoidCallback? onNumbers;
  final VoidCallback? onNames;
  final ValueChanged<bool>? onGroupByPosition;
  final VoidCallback? onEditTeam;
  final bool showReset;
  final VoidCallback? onReset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final showLayout = numberMode != null;
    final show = numberMode == false ? _PlayerShow.names : _PlayerShow.numbers;
    final showGroup = groupByPosition != null && onGroupByPosition != null;

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
            if (showGroup) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Ordering:',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FfTokens.nocturneTx,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _GroupSegments(
                      grouped: groupByPosition!,
                      onChanged: onGroupByPosition!,
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

class _GroupSegments extends StatelessWidget {
  const _GroupSegments({
    required this.grouped,
    required this.onChanged,
  });

  final bool grouped;
  final ValueChanged<bool> onChanged;

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
          Expanded(
            child: _ShowSegment(
              label: 'By Position',
              selected: grouped,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ShowSegment(
              label: 'By Number',
              selected: !grouped,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

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
