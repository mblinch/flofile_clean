import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Compact celebrate/react control: party toggle + mode dropdown.
///
/// The 🎉 button turns celebration on/off. The dropdown picks the mode and
/// defaults to **Celebrates**.
class CelebrationDropdown extends StatelessWidget {
  const CelebrationDropdown({
    super.key,
    required this.reactions,
    required this.celebrations,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<String> reactions;
  final List<String> celebrations;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool compact;

  List<String> get _options {
    final seen = <String>{};
    final out = <String>[];
    for (final option in [...reactions, ...celebrations]) {
      final value = option.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      out.add(value);
    }
    return out;
  }

  String get _defaultOption {
    final options = _options;
    for (final option in options) {
      if (option.toLowerCase() == 'celebrates') return option;
    }
    return options.isEmpty ? 'Celebrates' : options.first;
  }

  bool get _on {
    final value = selected?.trim();
    return value != null && value.isNotEmpty;
  }

  String get _dropdownValue {
    if (_on) return selected!.trim();
    return _defaultOption;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final height = compact ? 26.0 : 34.0;
    final options = _options;

    return Row(
      children: [
        Tooltip(
          message: _on ? 'Turn off celebrate / react' : 'Turn on celebrate / react',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (_on) {
                  onChanged(null);
                } else {
                  onChanged(_dropdownValue);
                }
              },
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: height,
                width: compact ? 52 : 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _on ? t.selectedFill : t.sunken,
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  border: Border.all(
                    color: _on ? t.selectedBorder : t.divider,
                  ),
                ),
                child: ColorFiltered(
                  colorFilter: _on
                      ? const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        )
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: Center(
                    child: Text(
                      '🎉',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Celebrate / React',
            padding: EdgeInsets.zero,
            offset: const Offset(0, 28),
            color: t.surface,
            enabled: options.isNotEmpty,
            onSelected: (value) => onChanged(value),
            itemBuilder: (context) => [
              for (final option in options)
                PopupMenuItem<String>(
                  value: option,
                  child: Text(
                    option,
                    style: t.metaStyle.copyWith(
                      color: _dropdownValue == option ? t.accent : t.text,
                      fontWeight: _dropdownValue == option
                          ? FfTokens.weightMedium
                          : FfTokens.weightRegular,
                    ),
                  ),
                ),
            ],
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _on ? 1 : 0.72,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: t.sunken,
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  border: Border.all(color: t.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dropdownValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.metaStyle.copyWith(
                          fontSize: compact ? t.textSizeMeta : t.textSizeBody,
                          color: _on ? t.text : t.textSecondary,
                          fontWeight: _on
                              ? FfTokens.weightMedium
                              : FfTokens.weightRegular,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 16,
                      color: t.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
