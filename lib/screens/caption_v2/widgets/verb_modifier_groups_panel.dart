import 'package:flutter/material.dart';

import '../../../caption_style/verb_authoring_model.dart';
import '../../../theme/ff_tokens.dart';

class VerbModifierGroupsPanel extends StatelessWidget {
  const VerbModifierGroupsPanel({
    super.key,
    required this.groups,
    required this.selections,
    required this.onSelected,
    this.compact = true,
  });

  final List<VerbModifierGroup> groups;
  final Map<String, String?> selections;
  final void Function(String groupId, String optionId) onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) SizedBox(height: compact ? 8 : 10),
          _Group(
            group: groups[index],
            selectedId:
                selections[groups[index].id] ?? groups[index].defaultOptionId,
            tokens: tokens,
            compact: compact,
            onSelected: (optionId) => onSelected(groups[index].id, optionId),
          ),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.selectedId,
    required this.tokens,
    required this.compact,
    required this.onSelected,
  });

  final VerbModifierGroup group;
  final String? selectedId;
  final FfTokens tokens;
  final bool compact;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.name.toUpperCase(),
          style: TextStyle(
            fontFamily: FfTokens.labelFamily,
            fontWeight: FontWeight.w600,
            fontSize: 9,
            letterSpacing: 0.8,
            color: tokens.text.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 5),
        if (group.options.isEmpty)
          Container(
            height: 27,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.error),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'No options configured',
              style: tokens.metaStyle.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          )
        else
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final option in group.options)
                _Option(
                  option: option,
                  kind: group.kind,
                  selected: selectedId == option.id,
                  tokens: tokens,
                  onTap: () => onSelected(option.id),
                ),
            ],
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.option,
    required this.kind,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final VerbModifierOption option;
  final VerbModifierKind kind;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: kind == VerbModifierKind.tokens
            ? const BoxConstraints(minWidth: 46, maxWidth: 104)
            : null,
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.selectedFill : tokens.elevated,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border(left: BorderSide(color: tokens.accent, width: 2))
              : Border.all(color: tokens.divider),
        ),
        child: Text(
          option.label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: kind == VerbModifierKind.tokens
                ? FfTokens.monoFamily
                : FfTokens.fontFamily,
            fontSize: kind == VerbModifierKind.tokens ? 11.5 : 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: tokens.text,
          ),
        ),
      ),
    );
  }
}
