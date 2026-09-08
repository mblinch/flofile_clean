import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../widgets/player_row.dart';

/// Home or away roster column — reused on desktop Row and mobile PageView.
class RosterColumn extends StatefulWidget {
  const RosterColumn({
    super.key,
    required this.controller,
    required this.isHome,
    required this.focused,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final bool focused;

  @override
  State<RosterColumn> createState() => _RosterColumnState();
}

class _RosterColumnState extends State<RosterColumn> {
  final _filter = TextEditingController();
  final _columnFocusNode = FocusNode(debugLabel: 'Roster column');

  @override
  void dispose() {
    _columnFocusNode.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = widget.controller;
    final abbr = widget.isHome ? c.homeAbbr : c.awayAbbr;
    final roster = widget.isHome ? c.homeRoster : c.awayRoster;
    final q = _filter.text.trim().toLowerCase();
    final filtered = roster.where((pl) {
      if (q.isEmpty) return true;
      return pl.fullName.toLowerCase().contains(q) ||
          (pl.jerseyNumber ?? '').contains(q);
    }).toList();

    return Focus(
      focusNode: _columnFocusNode,
      child: Listener(
        onPointerDown: (_) {
          _columnFocusNode.requestFocus();
          c.setColumnFocus(widget.isHome ? 0 : 2);
        },
        child: CaptionV2ColumnCard(
          focused: widget.focused,
          header: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(abbr, style: t.labelStyle),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _filter,
                    style: t.metaStyle.copyWith(color: t.text),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filter $abbr…',
                      hintStyle: t.metaStyle,
                      filled: true,
                      fillColor: t.sunken,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusChip),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: c.toggleSort,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  foregroundColor: t.textSecondary,
                ),
                child: Text(
                  c.sortByNumber ? '#  A–Z' : 'A–Z  #',
                  style: t.metaStyle,
                ),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text('No players', style: t.metaStyle),
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

                    return ListView.builder(
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
                          name: pl.fullName,
                          selected: selected,
                          selectionRole: selected
                              ? (isOpponent
                                  ? 'OPP $roleIndex'
                                  : 'SUBJ $roleIndex')
                              : null,
                          height: fittedHeight,
                          onTap: () =>
                              c.selectPlayer(pl, isHome: widget.isHome),
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
              padding: const EdgeInsets.fromLTRB(8, 3, 5, 0),
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
