import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../services/mlb_api_service.dart';
import '../../../theme/ff_glow.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/custom_name_entry.dart';
import '../widgets/pinned_player_bar.dart';
import '../widgets/player_row.dart';
import '../widgets/quiet_filter_field.dart';
import 'caption_v2_verb_editor.dart';
import 'duplicate_jersey_dialog.dart';
import 'player_data_issue_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum RosterViewMode { classic, wheel, infinite }

/// Home or away roster column — reused on desktop Row and mobile PageView.
class RosterColumn extends StatefulWidget {
  const RosterColumn({
    super.key,
    required this.controller,
    required this.isHome,
    required this.focused,
    this.onEditRosters,
    this.onDrumRequested,
    this.onInfiniteRequested,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final bool focused;
  final VoidCallback? onEditRosters;
  final VoidCallback? onDrumRequested;
  final VoidCallback? onInfiniteRequested;

  @override
  State<RosterColumn> createState() => _RosterColumnState();
}

class _RosterColumnState extends State<RosterColumn> {
  final _filter = TextEditingController();
  final _columnFocusNode = FocusNode(debugLabel: 'Roster column');
  final _scrollController = ScrollController();
  final _customNameController = TextEditingController();
  final _customJerseyController = TextEditingController();
  final _customNameFocusNode = FocusNode(debugLabel: 'Custom name');
  final _customJerseyFocusNode = FocusNode(debugLabel: 'Custom jersey');
  RosterViewMode _viewMode = RosterViewMode.classic;
  String? _lastFirebarSelectionKey;
  int _seenPlayerSearchClearGeneration = -1;

  @override
  void initState() {
    super.initState();
    _seenPlayerSearchClearGeneration =
        widget.controller.playerSearchClearGeneration;
    widget.controller.addListener(_onController);
    _syncCustomNameFromPin();
  }

  @override
  void didUpdateWidget(covariant RosterColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _seenPlayerSearchClearGeneration =
          widget.controller.playerSearchClearGeneration;
      _syncCustomNameFromPin();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _columnFocusNode.dispose();
    _scrollController.dispose();
    _filter.dispose();
    _customNameController.dispose();
    _customJerseyController.dispose();
    _customNameFocusNode.dispose();
    _customJerseyFocusNode.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncCustomNameFromPin();
    final generation = widget.controller.playerSearchClearGeneration;
    if (generation == _seenPlayerSearchClearGeneration) return;
    _seenPlayerSearchClearGeneration = generation;
    if (_filter.text.isEmpty) return;
    _filter.clear();
    setState(() {});
  }

  bool get _customNamePinned {
    final pinned = widget.controller.pinnedPlayer;
    if (pinned == null || pinned.isHome != widget.isHome) return false;
    final id = pinned.player.playerId?.trim();
    if (id != null && id.isNotEmpty) return false;
    final name = _customNameController.text.trim();
    if (name.isEmpty) return false;
    final jersey = _customJerseyController.text.trim();
    final player = widget.controller.findRosterPlayer(
      isHome: widget.isHome,
      fullName: name,
      jerseyNumber: jersey.isEmpty ? null : jersey,
    );
    if (player == null) return false;
    return widget.controller.isPlayerPinned(player, isHome: widget.isHome);
  }

  void _syncCustomNameFromPin() {
    final pinned = widget.controller.pinnedPlayer;
    if (pinned == null || pinned.isHome != widget.isHome) return;
    // Only mirror *custom* pins into the footer field. Roster pins use the
    // pinned player bar and must not lock/overwrite this text field.
    final id = pinned.player.playerId?.trim();
    if (id != null && id.isNotEmpty) return;
    if (_customNameFocusNode.hasFocus || _customJerseyFocusNode.hasFocus) {
      return;
    }
    final name = pinned.player.fullName;
    final jersey = pinned.player.jerseyNumber ?? '';
    if (_customNameController.text == name &&
        _customJerseyController.text == jersey) {
      return;
    }
    _customNameController.text = name;
    _customJerseyController.text = jersey;
  }

  void _showCustomNameError(String? error) {
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
    );
  }

  void _submitCustomName() {
    final name = _customNameController.text.trim();
    if (name.isEmpty) return;
    final jersey = _customJerseyController.text.trim();
    final error = widget.controller.commitCustomPlayer(
      isHome: widget.isHome,
      fullName: name,
      jerseyNumber: jersey.isEmpty ? null : jersey,
    );
    _showCustomNameError(error);
    setState(() {});
  }

  void _useLastCustomName() {
    final c = widget.controller;
    if (!c.canUseLastCustomPlayer) return;
    _customNameController.text = c.lastCustomPlayerName;
    _customJerseyController.text = c.lastCustomPlayerJersey;
    setState(() {});
    _customNameFocusNode.requestFocus();
  }

  void _toggleCustomNamePin() {
    final name = _customNameController.text.trim();
    if (name.isEmpty && widget.controller.canUseLastCustomPlayer) {
      _customNameController.text = widget.controller.lastCustomPlayerName;
      _customJerseyController.text = widget.controller.lastCustomPlayerJersey;
    }
    final error = widget.controller.toggleCustomPlayerPin(
      isHome: widget.isHome,
      fullName: _customNameController.text,
      jerseyNumber: _customJerseyController.text.trim().isEmpty
          ? null
          : _customJerseyController.text.trim(),
    );
    _showCustomNameError(error);
    setState(() {});
  }

  Future<void> _reportPlayerDataIssue(
    BuildContext context,
    CaptionV2Controller c,
    Player player,
  ) async {
    final teamName =
        (widget.isHome ? c.homeTeam : c.awayTeam).trim().isEmpty
            ? (widget.isHome ? c.homeAbbr : c.awayAbbr)
            : (widget.isHome ? c.homeTeam : c.awayTeam);
    await submitPlayerDataIssueReport(
      context: context,
      teamName: teamName,
      sportId: c.sport,
      side: widget.isHome ? 'home' : 'away',
      player: player,
    );
  }

  Future<void> _playerContextMenu(
    BuildContext context,
    CaptionV2Controller c,
    Player player,
    Offset position,
  ) async {
    final pinned = c.isPlayerPinned(player, isHome: widget.isHome);
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
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'pin') {
      c.togglePlayerPin(player, isHome: widget.isHome);
      return;
    }
    if (action == 'google') {
      await openPlayerGoogleSearch(
        fullName: player.fullName,
        sportId: c.sport,
      );
      return;
    }
    if (action != 'edit') return;
    final result = await showCustomNameEntryDialog(
      context: context,
      teamLabel: widget.isHome ? c.homeAbbr : c.awayAbbr,
      title: 'Edit player',
      confirmLabel: 'Save',
      initialName: player.fullName,
      initialJersey: player.jerseyNumber,
    );
    if (!mounted || result == null) return;
    final error = c.updatePlayer(
      isHome: widget.isHome,
      original: player,
      fullName: result.name,
      jerseyNumber: result.jersey,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = widget.controller;
    final firebarActive = c.searchOpen;
    final abbr = widget.isHome ? c.homeAbbr : c.awayAbbr;
    final roster = widget.isHome ? c.homeRoster : c.awayRoster;
    final firebarResults =
        widget.isHome ? c.firebarHomeResults : c.firebarAwayResults;
    final q = _filter.text.trim();
    final List<Player> filtered;
    if (firebarActive) {
      final players = firebarResults.map((result) => result.player!).toList();
      filtered = q.isEmpty ? players : c.filterAndRankPlayers(players, q);
    } else {
      filtered = c.filterAndRankPlayers(roster, q);
    }

    return Focus(
      focusNode: _columnFocusNode,
      child: CaptionV2ColumnCard(
        focused: widget.focused,
        accentOutline: true,
        header: _RosterHeaderBar(
          abbr: abbr,
          tokens: t,
          onEditRosters: widget.onEditRosters,
          trailing: _RosterViewToggle(
            mode: _viewMode,
            tokens: t,
            supportsInfinite: widget.onInfiniteRequested != null,
            onChanged: (mode) {
              if (mode == RosterViewMode.wheel &&
                  widget.onDrumRequested != null) {
                widget.onDrumRequested!();
                return;
              }
              if (mode == RosterViewMode.infinite &&
                  widget.onInfiniteRequested != null) {
                widget.onInfiniteRequested!();
                return;
              }
              setState(() {
                if (mode == RosterViewMode.wheel &&
                    _viewMode == RosterViewMode.wheel) {
                  _viewMode = RosterViewMode.classic;
                } else {
                  _viewMode = mode;
                }
              });
            },
          ),
          onSort: c.cycleRosterSortField,
          sortLabel: c.rosterSortFieldLabel(),
          onSortDirection: c.toggleRosterSortDirection,
          sortDirectionLabel: c.rosterSortDirectionLabel(),
        ),
        child: Column(
          children: [
            Expanded(
              child: Listener(
                onPointerDown: (_) {
                  if (firebarActive) return;
                  _columnFocusNode.requestFocus();
                  c.setColumnFocus(widget.isHome ? 0 : 2);
                },
                child: Column(
                  children: [
                    if (!firebarActive)
                      PinnedPlayerBar(
                        controller: c,
                        isHome: widget.isHome,
                        tokens: t,
                        filter: QuietFilterField(
                          controller: _filter,
                          tokens: t,
                          height: 24,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    if (!firebarActive)
                      _RosterPlayerIssuesBar(
                        roster: roster,
                        tokens: t,
                        onEditPlayer: (player) async {
                          final result = await showCustomNameEntryDialog(
                            context: context,
                            teamLabel: abbr,
                            title: 'Set jersey number',
                            confirmLabel: 'Save',
                            initialName: player.fullName,
                            initialJersey: player.jerseyNumber,
                          );
                          if (!mounted || result == null) return;
                          final error = c.updatePlayer(
                            isHome: widget.isHome,
                            original: player,
                            fullName: result.name,
                            jerseyNumber: result.jersey,
                          );
                          if (error != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(error),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                    if (filtered.isEmpty) {
                      return Center(
                        child: FfGlow(
                          glowW: 240,
                          glowH: 150,
                          child: Text(
                            firebarActive || q.isNotEmpty
                                ? 'No match'
                                : 'No players',
                            style: t.metaStyle.copyWith(
                              color: firebarActive || q.isNotEmpty
                                  ? t.text.withValues(alpha: 0.34)
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }

                    if (!firebarActive && _viewMode == RosterViewMode.wheel) {
                      return _PlayerWheel(
                        players: filtered,
                        controller: c,
                        isHome: widget.isHome,
                      );
                    }

                    // Fit the complete roster whenever a readable row height can
                    // do so. Only retain scrolling on exceptionally short windows.
                    final isMobile = MediaQuery.sizeOf(context).width < 1100;
                    final minRowHeight = isMobile ? 26.0 : 20.0;
                    // When the roster fits, let each row use the leftover
                    // height so names can grow instead of sitting in a gap.
                    final maxRowHeight = isMobile ? 56.0 : 48.0;
                    final fittedHeight =
                        (constraints.maxHeight / filtered.length)
                            .clamp(minRowHeight, maxRowHeight);
                    final allFit = fittedHeight * filtered.length <=
                        constraints.maxHeight + 0.5;
                    final selectedResult =
                        firebarActive ? c.firebarSelectedResult : null;
                    final selectedIndex = firebarActive
                        ? filtered.indexWhere(
                            (player) =>
                                selectedResult?.player?.fullName ==
                                    player.fullName &&
                                selectedResult?.player?.jerseyNumber ==
                                    player.jerseyNumber,
                          )
                        : -1;
                    if (selectedIndex >= 0 &&
                        selectedResult?.key != _lastFirebarSelectionKey) {
                      _lastFirebarSelectionKey = selectedResult!.key;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_scrollController.hasClients) return;
                        final target = selectedIndex * fittedHeight;
                        _scrollController.animateTo(
                          target.clamp(
                            0,
                            _scrollController.position.maxScrollExtent,
                          ),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                        );
                      });
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      itemExtent: fittedHeight,
                      physics: allFit
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      itemBuilder: (context, i) {
                        final pl = filtered[i];
                        final selected = c.isPlayerSelected(
                          pl,
                          isHome: widget.isHome,
                        );
                        final firebarResult = firebarActive
                            ? firebarResults
                                .where(
                                  (result) =>
                                      result.player!.fullName == pl.fullName &&
                                      result.player!.jerseyNumber ==
                                          pl.jerseyNumber,
                                )
                                .firstOrNull
                            : null;
                        final selectedRowIndex = c.selectedPlayers.indexWhere(
                            (row) =>
                                row.isHome == widget.isHome &&
                                row.player.fullName == pl.fullName &&
                                row.player.jerseyNumber == pl.jerseyNumber);
                        final isOpponent = selectedRowIndex >= 0 &&
                            c.selectedPlayers.isNotEmpty &&
                            c.selectedPlayers.first.isHome != widget.isHome;
                        final roleIndex = selectedRowIndex < 0
                            ? 0
                            : c.selectedPlayers
                                .take(selectedRowIndex + 1)
                                .where((row) => row.isHome == widget.isHome)
                                .length;
                        final isPrimarySelected = !firebarActive &&
                            selectedRowIndex == 0 &&
                            c.selectedPlayers.isNotEmpty;
                        return PlayerRow(
                          jersey: pl.jerseyNumber ?? '—',
                          name: c.playerListName(pl),
                          selected: firebarActive ? false : selected,
                          pinned: c.isPlayerPinned(
                            pl,
                            isHome: widget.isHome,
                          ),
                          firebarSelected: firebarActive &&
                              firebarResult?.key == selectedResult?.key,
                          highlightQuery: firebarActive
                              ? c.searchQuery.trim().replaceFirst(
                                    RegExp(r'^[hHvV](?=\d)'),
                                    '',
                                  )
                              : q,
                          primarySelected: isPrimarySelected,
                          selectionRole: !firebarActive && selected
                              ? (isOpponent
                                  ? 'OPP $roleIndex'
                                  : 'SUBJ $roleIndex')
                              : null,
                          height: fittedHeight,
                          onTap: firebarActive
                              ? () {
                                  if (firebarResult != null) {
                                    c.commitFirebarResultAndClose(
                                        firebarResult);
                                  }
                                }
                              : () => c.selectPlayer(pl, isHome: widget.isHome),
                          onPinTap: () => c.togglePlayerPin(
                                pl,
                                isHome: widget.isHome,
                              ),
                          onGoogleTap: () => openPlayerGoogleSearch(
                                fullName: pl.fullName,
                                sportId: c.sport,
                              ),
                          onReportTap: () =>
                              _reportPlayerDataIssue(context, c, pl),
                          onSecondaryTapDown: (details) => _playerContextMenu(
                            context,
                            c,
                            pl,
                            details.globalPosition,
                          ),
                        );
                      },
                    );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!firebarActive)
              CustomNameField(
                nameController: _customNameController,
                jerseyController: _customJerseyController,
                nameFocusNode: _customNameFocusNode,
                jerseyFocusNode: _customJerseyFocusNode,
                tokens: t,
                pinned: _customNamePinned,
                canUseLast: c.canUseLastCustomPlayer,
                onChanged: () => setState(() {}),
                onSubmit: _submitCustomName,
                onTogglePin: _toggleCustomNamePin,
                onUseLast: _useLastCustomName,
              ),
          ],
        ),
      ),
    );
  }
}

class _RosterViewToggle extends StatelessWidget {
  const _RosterViewToggle({
    required this.mode,
    required this.tokens,
    required this.supportsInfinite,
    required this.onChanged,
  });

  final RosterViewMode mode;
  final FfTokens tokens;
  final bool supportsInfinite;
  final ValueChanged<RosterViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required RosterViewMode value,
      required IconData icon,
      required String tooltip,
    }) {
      final selected = mode == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: ValueKey('roster-${value.name}'),
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 24,
            height: 22,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(
                  icon,
                  size: 16,
                  color: selected ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(height: 1),
                Container(
                  width: 12,
                  height: 1.5,
                  color: selected ? tokens.accent : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'View Options',
      child: Row(
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
          const SizedBox(width: 2),
          button(
            value: RosterViewMode.wheel,
            icon: PhosphorIconsRegular.arrowsDownUp,
            tooltip: 'Default',
          ),
          if (supportsInfinite)
            button(
              value: RosterViewMode.infinite,
              icon: PhosphorIconsRegular.infinity,
              tooltip: 'Drum wheel',
            ),
        ],
      ),
    );
  }
}

class _PlayerWheel extends StatefulWidget {
  const _PlayerWheel({
    required this.players,
    required this.controller,
    required this.isHome,
  });

  final List<Player> players;
  final CaptionV2Controller controller;
  final bool isHome;

  @override
  State<_PlayerWheel> createState() => _PlayerWheelState();
}

class _PlayerWheelState extends State<_PlayerWheel> {
  static const _itemExtent = 48.0;

  late FixedExtentScrollController _scrollController;
  late int _centerIndex;
  late String _playersKey;

  @override
  void initState() {
    super.initState();
    _playersKey = _keyFor(widget.players);
    _centerIndex = _initialIndex();
    _scrollController = FixedExtentScrollController(
      initialItem: _centerIndex,
    );
  }

  @override
  void didUpdateWidget(covariant _PlayerWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget.players);
    if (nextKey == _playersKey) return;
    _playersKey = nextKey;
    _centerIndex = _initialIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpToItem(_centerIndex);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Slight center emphasis for the default player wheel.
  double _scaleFor(int index) {
    final position = _scrollController.hasClients
        ? _scrollController.offset / _itemExtent
        : _centerIndex.toDouble();
    final distance = (index - position).abs();
    if (distance <= 1) {
      final eased = distance * distance * (3 - 2 * distance);
      return 1.08 - 0.08 * eased;
    }
    return 1;
  }

  String _keyFor(List<Player> players) => players
      .map((player) => '${player.playerId}|${player.jerseyNumber}|'
          '${player.fullName}')
      .join('||');

  int _initialIndex() {
    final selected = widget.controller.selectedPlayers.indexWhere(
      (row) =>
          row.isHome == widget.isHome &&
          widget.players.any((player) => identical(player, row.player)),
    );
    if (selected < 0) return 0;
    final player = widget.controller.selectedPlayers[selected].player;
    final index = widget.players.indexWhere((item) => identical(item, player));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.elevated.withValues(alpha: 0.92),
                  t.surface,
                  t.elevated.withValues(alpha: 0.92),
                ],
                stops: const [0, 0.5, 1],
              ),
              borderRadius: BorderRadius.circular(FfTokens.radiusCard),
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.08),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 0.8,
                          colors: [
                            t.accent.withValues(alpha: 0.11),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0, 0.22, 0.78, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: ScrollConfiguration(
                      behavior: const _WheelScrollBehavior(),
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (_) => false,
                        child: ListWheelScrollView.useDelegate(
                          key: const ValueKey('player-wheel'),
                          controller: _scrollController,
                          itemExtent: _itemExtent,
                          diameterRatio: 1.7,
                          perspective: 0.0025,
                          physics: const FixedExtentScrollPhysics(),
                          overAndUnderCenterOpacity: 0.55,
                          onSelectedItemChanged: (index) {
                            setState(() => _centerIndex = index);
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: widget.players.length,
                            builder: (context, index) {
                              final player = widget.players[index];
                              final selected =
                                  widget.controller.isPlayerSelected(
                                player,
                                isHome: widget.isHome,
                              );
                              final centered = index == _centerIndex;
                              return Semantics(
                                button: true,
                                selected: selected,
                                label:
                                    '${player.jerseyNumber ?? ''} ${player.fullName}',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    if (!centered) {
                                      await _scrollController.animateToItem(
                                        index,
                                        duration:
                                            const Duration(milliseconds: 260),
                                        curve: Curves.easeOutCubic,
                                      );
                                    }
                                    if (!mounted) return;
                                    widget.controller.selectPlayer(
                                      player,
                                      isHome: widget.isHome,
                                    );
                                  },
                                  child: AnimatedBuilder(
                                    animation: _scrollController,
                                    builder: (context, child) {
                                      final scale = _scaleFor(index);
                                      final availableWidth =
                                          (constraints.maxWidth - 20)
                                              .clamp(40.0, double.infinity);
                                      return Center(
                                        child: Transform.scale(
                                          scale: scale,
                                          child: SizedBox(
                                            width: availableWidth / scale,
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Transform.translate(
                                            offset: const Offset(0, 1),
                                            child: AnimatedDefaultTextStyle(
                                              duration: const Duration(
                                                  milliseconds: 150),
                                              curve: Curves.easeOutCubic,
                                              style: t.jerseyStyle.copyWith(
                                                color: centered
                                                    ? t.accent
                                                    : t.textSecondary,
                                              ),
                                              child: Text(
                                                player.jerseyNumber ?? '—',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: AnimatedDefaultTextStyle(
                                                duration: const Duration(
                                                    milliseconds: 150),
                                                curve: Curves.easeOutCubic,
                                                style: FfTokens.captionTitle
                                                    .copyWith(
                                                  color: centered
                                                      ? t.text
                                                      : t.textSecondary,
                                                  fontSize:
                                                      centered ? 13.5 : 12.5,
                                                  letterSpacing: -0.25,
                                                ),
                                                child: Text(
                                                  widget.controller
                                                      .playerListName(player),
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (selected) ...[
                                            const SizedBox(width: 6),
                                            PhosphorIcon(PhosphorIconsRegular.check,
                                              size: 14,
                                              color: t.accent,
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
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Container(
                    height: _itemExtent,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          t.selectedFill.withValues(alpha: 0.28),
                          t.accent.withValues(alpha: 0.12),
                          t.selectedFill.withValues(alpha: 0.28),
                        ],
                      ),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: t.selectedBorder.withValues(alpha: 0.9),
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
    );
  }
}

class _WheelScrollBehavior extends MaterialScrollBehavior {
  const _WheelScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _RosterHeaderBar extends StatelessWidget {
  const _RosterHeaderBar({
    required this.abbr,
    required this.tokens,
    required this.trailing,
    required this.onSort,
    required this.sortLabel,
    required this.onSortDirection,
    required this.sortDirectionLabel,
    this.onEditRosters,
  });

  static const double _controlHeight = 24;
  static const double headerHeight = 32;

  final String abbr;
  final FfTokens tokens;
  final Widget trailing;
  final VoidCallback onSort;
  final String sortLabel;
  final VoidCallback onSortDirection;
  final String sortDirectionLabel;
  final VoidCallback? onEditRosters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            abbr.toUpperCase(),
            style: FfTokens.teamAbbrLabel(color: tokens.text),
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),
          if (onEditRosters != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 2),
              child: _RosterGhostIcon(
                tooltip: 'Rename team',
                icon: PhosphorIconsRegular.pencilSimple,
                tokens: tokens,
                onTap: onEditRosters!,
              ),
            ),
          const Spacer(),
          SizedBox(
            height: _controlHeight,
            child: Center(child: trailing),
          ),
          const SizedBox(width: 2),
          _RosterGhostIcon(
            tooltip: 'Sort by number',
            label: sortLabel,
            tokens: tokens,
            onTap: onSort,
          ),
          _RosterGhostIcon(
            tooltip: sortDirectionLabel == '↑' ? 'Ascending' : 'Descending',
            label: sortDirectionLabel,
            tokens: tokens,
            onTap: onSortDirection,
          ),
        ],
      ),
    );
  }
}

class _RosterGhostIcon extends StatefulWidget {
  const _RosterGhostIcon({
    required this.tooltip,
    required this.tokens,
    required this.onTap,
    this.icon,
    this.label,
  });

  final String tooltip;
  final FfTokens tokens;
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;

  @override
  State<_RosterGhostIcon> createState() => _RosterGhostIconState();
}

class _RosterGhostIconState extends State<_RosterGhostIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        _hovered ? widget.tokens.text : widget.tokens.textSecondary;
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

class _RosterPlayerIssueRow {
  const _RosterPlayerIssueRow({
    required this.player,
    required this.summary,
  });

  final Player player;
  final String summary;
}

/// Expandable strip for missing / duplicate jersey numbers on this roster.
class _RosterPlayerIssuesBar extends StatefulWidget {
  const _RosterPlayerIssuesBar({
    required this.roster,
    required this.tokens,
    required this.onEditPlayer,
  });

  final List<Player> roster;
  final FfTokens tokens;
  final Future<void> Function(Player player) onEditPlayer;

  @override
  State<_RosterPlayerIssuesBar> createState() => _RosterPlayerIssuesBarState();
}

class _RosterPlayerIssuesBarState extends State<_RosterPlayerIssuesBar> {
  bool _expanded = false;

  List<_RosterPlayerIssueRow> _issues() {
    final missing = <_RosterPlayerIssueRow>[];
    final byJersey = <String, List<Player>>{};
    for (final player in widget.roster) {
      final jersey = (player.jerseyNumber ?? '').trim();
      if (jersey.isEmpty) {
        missing.add(_RosterPlayerIssueRow(
          player: player,
          summary: 'Missing jersey',
        ));
        continue;
      }
      byJersey.putIfAbsent(jersey, () => []).add(player);
    }
    final duplicates = <_RosterPlayerIssueRow>[];
    final jerseyKeys = byJersey.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a) ?? 999;
        final bi = int.tryParse(b) ?? 999;
        return ai.compareTo(bi);
      });
    for (final jersey in jerseyKeys) {
      final group = byJersey[jersey]!;
      if (group.length < 2) continue;
      for (final player in group) {
        final others = group
            .where((p) => !identical(p, player))
            .map((p) => p.fullName)
            .join(', ');
        duplicates.add(_RosterPlayerIssueRow(
          player: player,
          summary: others.isEmpty
              ? 'Duplicate #$jersey'
              : 'Duplicate #$jersey · also $others',
        ));
      }
    }
    return [...missing, ...duplicates];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _issues();
    if (rows.isEmpty) return const SizedBox.shrink();
    final t = widget.tokens;
    final missingCount =
        rows.where((r) => r.summary.startsWith('Missing')).length;
    final duplicateCount = rows.length - missingCount;
    final parts = <String>[];
    if (missingCount > 0) {
      parts.add(
        '$missingCount missing jersey${missingCount == 1 ? '' : 's'}',
      );
    }
    if (duplicateCount > 0) {
      parts.add(
        '$duplicateCount duplicate number'
        '${duplicateCount == 1 ? '' : 's'}',
      );
    }

    return Material(
      color: t.accent.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIconsRegular.warning,
                    size: 14,
                    color: t.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      parts.join(' · '),
                      style: t.metaStyle.copyWith(
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? PhosphorIconsRegular.caretUp : PhosphorIconsRegular.caretDown,
                    size: 16,
                    color: t.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: t.divider,
                ),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      row.player.fullName,
                      style: t.labelStyle.copyWith(fontSize: 12),
                    ),
                    subtitle: Text(
                      row.summary,
                      style: t.metaStyle.copyWith(
                        fontSize: 10,
                        color: t.textSecondary,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => widget.onEditPlayer(row.player),
                      child: const Text('Set #'),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class CaptionV2ColumnCard extends StatelessWidget {
  const CaptionV2ColumnCard({
    super.key,
    required this.header,
    required this.child,
    required this.focused,
    this.showHeader = true,
    this.accentOutline = false,
  });

  final Widget header;
  final Widget child;
  final bool focused;
  final bool showHeader;

  /// When true, use the teal accent border even when not focused.
  final bool accentOutline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final outlined = accentOutline || focused;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(
          color: outlined ? t.accent : t.divider,
          width: 1,
        ),
        boxShadow: outlined ? FfTokens.accentButtonGlow(t.accent) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Container(
              height: _RosterHeaderBar.headerHeight,
              padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.divider),
                ),
              ),
              child: header,
            ),
          Expanded(
            child: Padding(
              padding: showHeader
                  ? const EdgeInsets.fromLTRB(6, 0, 6, 6)
                  : const EdgeInsets.all(6),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
