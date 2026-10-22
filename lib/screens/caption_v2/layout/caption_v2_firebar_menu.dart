import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';

class FirebarAutocompleteMenu extends StatelessWidget {
  const FirebarAutocompleteMenu({
    super.key,
    required this.controller,
    required this.tokens,
    required this.results,
    required this.selectedIndex,
    required this.scrollController,
    required this.onHover,
    required this.onCommit,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final List<FirebarResult> results;
  final int selectedIndex;
  final ScrollController scrollController;
  final void Function(int index, Offset position) onHover;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    final query = controller.searchQuery.trim();
    final maxHeight =
        (MediaQuery.sizeOf(context).height - 180).clamp(120.0, 280.0);
    const labelStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: FfTokens.nocturneT3,
    );
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FfTokens.nocturneEl.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FfTokens.nocturneLn),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MatchParentWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                        child: Row(
                          children: [
                            Text(
                              controller.firebarMenuLabel.toUpperCase(),
                              style: labelStyle,
                            ),
                            const Spacer(),
                            if (results.isNotEmpty)
                              Text(
                                '${selectedIndex + 1} / ${results.length}',
                                style: labelStyle,
                              ),
                          ],
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight - 28),
                      child: results.isEmpty
                          ? Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 8, 10, 14),
                              child: Text(
                                'No match for “$query”. Enter adds it as free text.',
                                style: tokens.metaStyle.copyWith(
                                  fontSize: 13,
                                  color: FfTokens.nocturneT3,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: scrollController,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var index = 0;
                                      index < results.length;
                                      index++)
                                    _FirebarMenuRow(
                                      result: results[index],
                                      controller: controller,
                                      query: query,
                                      selected: index == selectedIndex,
                                      onHover: (position) =>
                                          onHover(index, position),
                                      onCommit: () => onCommit(index),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays out at the menu width without making the menu wider.
class _MatchParentWidth extends SingleChildRenderObjectWidget {
  const _MatchParentWidth({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMatchParentWidth();
  }
}

class _RenderMatchParentWidth extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}

class _FirebarMenuRow extends StatelessWidget {
  const _FirebarMenuRow({
    required this.result,
    required this.controller,
    required this.query,
    required this.selected,
    required this.onHover,
    required this.onCommit,
  });

  final FirebarResult result;
  final CaptionV2Controller controller;
  final String query;
  final bool selected;
  final ValueChanged<Offset> onHover;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final player = result.player;
    final isPlayer = result.kind == FirebarResultKind.player && player != null;
    final name = isPlayer
        ? player.fullName
        : controller.verbDefinition(result.verbKey ?? '')?.label ??
            result.verbKey ??
            '';
    final meta = isPlayer
        ? controller.teamNameLabel(isHome: result.isHome == true)
        : 'Verb';
    // Jersey-only digits skip name marks. Compound `3 battles` marks the
    // verb fragment on verb rows and leaves player names unmarked.
    final markQuery = () {
      if (RegExp(r'^\d+$').hasMatch(query)) return '';
      final parts = query.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && RegExp(r'^(?:[hv])?\d+$').hasMatch(parts.first)) {
        if (result.kind == FirebarResultKind.verb) {
          return parts.skip(1).join(' ');
        }
        return '';
      }
      return query;
    }();
    return MouseRegion(
      onHover: (event) => onHover(event.position),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onCommit(),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                child: isPlayer
                    ? Text(
                        player.jerseyNumber ?? '',
                        style: TextStyle(
                          fontFamily: FfTokens.monoFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? FfTokens.firebar
                              : FfTokens.nocturneT3,
                        ),
                      )
                    : const PhosphorIcon(
                        PhosphorIconsRegular.lightning,
                        size: 14,
                        color: FfTokens.nocturneT3,
                      ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? FfTokens.nocturneTx
                          : FfTokens.nocturneT2,
                    ),
                    children: _markedName(name, markQuery),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                meta,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: FfTokens.nocturneT3,
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: selected ? 1 : 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: FfTokens.nocturneEl.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '↵',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: FfTokens.nocturneT3,
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

  List<InlineSpan> _markedName(String name, String query) {
    if (query.isEmpty) return [TextSpan(text: name)];
    final index = name.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) return [TextSpan(text: name)];
    return [
      TextSpan(text: name.substring(0, index)),
      TextSpan(
        text: name.substring(index, index + query.length),
        style: const TextStyle(
          color: FfTokens.nocturneTx,
          fontWeight: FontWeight.w700,
        ),
      ),
      TextSpan(text: name.substring(index + query.length)),
    ];
  }
}
