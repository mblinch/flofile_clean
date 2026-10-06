import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Segmented 0–1–2–3 RBI control in an elevated box.
///
/// Intended to sit directly under the selected [VerbTile], not in a dialog.
class RbiRow extends StatelessWidget {
  const RbiRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 3,
    this.compact = false,
    this.homeRunStyle = false,
  });

  /// Currently selected RBI count (0–[max]).
  final int value;

  /// Called when the user picks a segment.
  final ValueChanged<int> onChanged;

  /// Highest RBI option (inclusive). Default 3 → segments 0,1,2,3.
  final int max;
  final bool compact;
  final bool homeRunStyle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final options = homeRunStyle
        ? const [1, 2, 3, 4]
        : List<int>.generate(max, (i) => i + 1);

    return Container(
      padding: EdgeInsets.all(compact ? 2 : 4),
      decoration: BoxDecoration(
        color: t.elevated,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      ),
      child: Row(
        children: [
          if (!homeRunStyle)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                height: compact ? 20 : 32,
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    'RBI',
                    style: t.bodyStyle.copyWith(
                      fontSize:
                          compact ? t.textSizeMeta : t.textSizeBody,
                      fontFamily: FfTokens.monoFamily,
                      fontWeight: FfTokens.weightRegular,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          for (final n in options)
            Expanded(
              child: _RbiSegment(
                label: homeRunStyle
                    ? const {1: '1R', 2: '2R', 3: '3R', 4: 'GS'}[n]!
                    : '$n',
                selected: value == n,
                tokens: t,
                compact: compact,
                onTap: () => onChanged(value == n ? 0 : n),
              ),
            ),
        ],
      ),
    );
  }
}

class _RbiSegment extends StatelessWidget {
  const _RbiSegment({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip - 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: compact ? 20 : 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? tokens.selectedFill : null,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip - 2),
              border: selected
                  ? Border(left: BorderSide(color: tokens.accent, width: 2))
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: tokens.bodyStyle.copyWith(
                fontSize: compact ? 11 : tokens.textSizeBody,
                fontFamily: FfTokens.monoFamily,
                fontWeight:
                    selected ? FfTokens.weightMedium : FfTokens.weightRegular,
                color: selected ? tokens.text : tokens.textSecondary,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
