import 'package:flutter/material.dart';

import '../theme/ff_tokens.dart';

/// Compact dropdown. Material [DropdownButton] menus cannot be shorter than
/// 48px, so this opens a [showMenu] with short rows instead.
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

  static const double menuItemHeight = 26;

  @override
  Widget build(BuildContext context) {
    final selected = _match(value);
    final label = selected?.child ??
        hint ??
        const SizedBox.shrink();
    final base = style ?? DefaultTextStyle.of(context).style;
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
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: base.color?.withValues(alpha: 0.7),
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
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final picked = await showMenu<_Pick<T>>(
      context: context,
      color: menuColor ?? Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: const Color(0x80000000),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: FfTokens.panelOutline, width: 0.5),
      ),
      constraints: BoxConstraints(
        minWidth: width,
        maxWidth: width < 160 ? 220 : width,
        maxHeight: 320,
      ),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy + box.size.height, width, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<_Pick<T>>(
            value: _Pick(item.value),
            enabled: item.enabled,
            height: item.child is Divider ? 8 : menuItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DefaultTextStyle(
              style: style ?? DefaultTextStyle.of(context).style,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: item.child,
            ),
          ),
      ],
    );
    if (picked == null) return;
    onChanged?.call(picked.value);
  }
}

class _Pick<T> {
  const _Pick(this.value);
  final T? value;
}
