import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Segmented base picker for running verbs (1B / 2B / 3B / Home).
class BaseRow extends StatelessWidget {
  const BaseRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  /// Selected base key: `1B`, `2B`, `3B`, `Home`, or null/empty for none.
  final String? value;

  /// Called when the user picks a segment (null clears).
  final ValueChanged<String?> onChanged;

  final bool compact;

  static const optionKeys = ['1B', '2B', '3B', 'Home'];
  static const optionLabels = ['1B', '2B', '3B', 'Home'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final selected = value?.trim();

    return Container(
      padding: EdgeInsets.all(compact ? 2 : 4),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      ),
      child: Row(
        children: [
          for (var i = 0; i < optionKeys.length; i++)
            Expanded(
              child: _BaseSegment(
                label: optionLabels[i],
                selected: selected == optionKeys[i],
                tokens: t,
                compact: compact,
                onTap: () => onChanged(
                  selected == optionKeys[i] ? null : optionKeys[i],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BaseSegment extends StatelessWidget {
  const _BaseSegment({
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
              border:
                  selected ? Border.all(color: tokens.selectedBorder) : null,
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
