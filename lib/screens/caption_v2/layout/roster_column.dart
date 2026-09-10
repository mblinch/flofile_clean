import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../services/mlb_api_service.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/player_row.dart';

enum RosterViewMode { classic, wheel, infinite }

/// Home or away roster column — reused on desktop Row and mobile PageView.
class RosterColumn extends StatefulWidget {
  const RosterColumn({
    super.key,
    required this.controller,
    required this.isHome,
    required this.focused,
    this.onDrumRequested,
    this.onInfiniteRequested,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final bool focused;
  final VoidCallback? onDrumRequested;
  final VoidCallback? onInfiniteRequested;

  @override
  State<RosterColumn> createState() => _RosterColumnState();
}

class _RosterColumnState extends State<RosterColumn> {
  final _filter = TextEditingController();
  final _columnFocusNode = FocusNode(debugLabel: 'Roster column');
  final _scrollController = ScrollController();
  RosterViewMode _viewMode = RosterViewMode.classic;
  String? _lastFirebarSelectionKey;

  @override
  void dispose() {
    _columnFocusNode.dispose();
    _scrollController.dispose();
    _filter.dispose();
    super.dispose();
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
      final players =
          firebarResults.map((result) => result.player!).toList();
      filtered = q.isEmpty ? players : c.filterAndRankPlayers(players, q);
    } else {
      filtered = c.filterAndRankPlayers(roster, q);
    }

    return Focus(
      focusNode: _columnFocusNode,
      child: Listener(
        onPointerDown: (_) {
          if (firebarActive) return;
          _columnFocusNode.requestFocus();
          c.setColumnFocus(widget.isHome ? 0 : 2);
        },
        child: CaptionV2ColumnCard(
          focused: widget.focused,
          header: _RosterHeaderBar(
            abbr: abbr,
            filter: _filter,
            tokens: t,
            trailing: firebarActive
                ? Text(
                    c.searchQuery.trim().isEmpty && q.isEmpty
                        ? '${roster.length}'
                        : '${filtered.length} / ${roster.length}',
                    style: t.monoMetaStyle.copyWith(height: 1),
                  )
                : _RosterViewToggle(
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
            onFilterChanged: () => setState(() {}),
          ),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (filtered.isEmpty) {
                      return Center(
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
                    final maxRowHeight = isMobile ? 40.0 : 28.0;
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
                        return PlayerRow(
                          jersey: pl.jerseyNumber ?? '—',
                          name: c.playerListName(pl),
                          selected: firebarActive ? false : selected,
                          firebarSelected: firebarActive &&
                              firebarResult?.key == selectedResult?.key,
                          highlightQuery: firebarActive
                              ? c.searchQuery.trim().replaceFirst(
                                    RegExp(r'^[hHvV](?=\d)'),
                                    '',
                                  )
                              : q,
                          selectionRole: !firebarActive && selected
                              ? (isOpponent
                                  ? 'OPP $roleIndex'
                                  : 'SUBJ $roleIndex')
                              : null,
                          height: fittedHeight,
                          onTap: firebarActive
                              ? () {
                                  if (firebarResult != null) {
                                    c.commitFirebarResult(firebarResult);
                                  }
                                }
                              : () => c.selectPlayer(pl, isHome: widget.isHome),
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
          const SizedBox(width: 4),
          button(
            value: RosterViewMode.wheel,
            icon: Icons.swap_vert,
            tooltip: 'Default',
          ),
          if (supportsInfinite)
            button(
              value: RosterViewMode.infinite,
              icon: Icons.all_inclusive,
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

  double _scaleFor(int index) {
    final position = _scrollController.hasClients
        ? _scrollController.offset / _itemExtent
        : _centerIndex.toDouble();
    final distance = (index - position).abs();
    if (distance <= 1) {
      final eased = distance * distance * (3 - 2 * distance);
      return 2 - 0.5 * eased;
    }
    if (distance <= 2) {
      final progress = distance - 1;
      final eased = progress * progress * (3 - 2 * progress);
      return 1.5 - 0.5 * eased;
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
                  t.sunken.withValues(alpha: 0.92),
                  t.surface,
                  t.sunken.withValues(alpha: 0.92),
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
                                                      centered ? 15 : 10.5,
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
                                            Icon(
                                              Icons.check,
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
    required this.filter,
    required this.tokens,
    required this.trailing,
    required this.onSort,
    required this.sortLabel,
    required this.onSortDirection,
    required this.sortDirectionLabel,
    required this.onFilterChanged,
  });

  static const double _controlHeight = 24;

  final String abbr;
  final TextEditingController filter;
  final FfTokens tokens;
  final Widget trailing;
  final VoidCallback onSort;
  final String sortLabel;
  final VoidCallback onSortDirection;
  final String sortDirectionLabel;
  final VoidCallback onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          abbr,
          style: FfTokens.captionTitle.copyWith(
            color: tokens.text,
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
            height: _controlHeight,
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
                controller: filter,
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
                onChanged: (_) => onFilterChanged(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: _controlHeight,
          child: Center(child: trailing),
        ),
        const SizedBox(width: 2),
        InkWell(
          onTap: onSort,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(
              sortLabel,
              style: tokens.metaStyle.copyWith(
                color: tokens.textSecondary,
                height: 1,
              ),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          ),
        ),
        InkWell(
          onTap: onSortDirection,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              sortDirectionLabel,
              style: tokens.metaStyle.copyWith(
                color: tokens.textSecondary,
                height: 1,
              ),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          ),
        ),
      ],
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
  });

  final Widget header;
  final Widget child;
  final bool focused;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FfTokens.radiusCard),
        border: Border.all(
          color: focused ? t.accent : t.divider,
          width: focused ? FfTokens.focusOutlineWidth : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(8, 0, 5, 0),
              alignment: Alignment.centerLeft,
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
