import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/ff_tokens.dart';
import 'ff_menu.dart';

/// Compact dropdown. Opens the same overlay menu as the New Session team picker.
class FfDropdownButton<T> extends StatelessWidget {
  const FfDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.isExpanded = false,
    this.style,
    this.icon,
    this.menuColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final bool isExpanded;
  final TextStyle? style;
  final Widget? icon;
  final Color? menuColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final selected = _match(value);
    final label = selected?.child ?? hint ?? const SizedBox.shrink();
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFamily: style?.fontFamily ?? FfTokens.fontFamily,
    );
    final closed = DefaultTextStyle(
      style: base,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      child: IconTheme(
        data: IconThemeData(size: 16, color: base.color),
        child: label,
      ),
    );
    return InkWell(
      onTap: onChanged == null ? null : () => _open(context),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (isExpanded) Expanded(child: closed) else Flexible(child: closed),
            icon ??
                PhosphorIcon(
                  PhosphorIconsRegular.caretDown,
                  size: 12,
                  color: (base.color ?? FfTokens.sessionT3).withValues(
                    alpha: 0.85,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  DropdownMenuItem<T>? _match(T? current) {
    for (final item in items) {
      if (item.value == current) return item;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final width = box.size.width < 160 ? 220.0 : box.size.width;
    final picked = await showFfMenu<T>(
      context: context,
      anchorGlobal: origin & box.size,
      width: width,
      color: menuColor,
      choices: [
        for (final item in items)
          if (item.child is Divider)
            FfMenuChoice<T>.divider()
          else
            FfMenuChoice<T>(
              value: item.value,
              enabled: item.enabled,
              selected: item.value == value,
              child: item.child,
            ),
      ],
    );
    if (picked == null) return;
    onChanged?.call(picked.value);
  }
}
