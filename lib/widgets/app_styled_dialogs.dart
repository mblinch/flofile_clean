import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';

/// Matches [KeyboardFirePanel] FTP / burst primary actions (`keyboard_fire_dialog.dart`).
const Color kAppDialogPrimaryBlue = Color(0xFF0052CC);

/// Square, white dialogs consistent with burst caption UI
/// (`burst_caption_confirm_dialog.dart`) — not default M3 rounded/surface tint.
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'OK',
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final screenW = MediaQuery.sizeOf(ctx).width;
      // Burst dialog uses `math.min(880.0, screenW * 0.92)`; confirm is half that.
      final burstDialogW = math.min(880.0, screenW * 0.92);
      final dialogW = burstDialogW / 2;
      return Center(
        child: SizedBox(
          width: dialogW,
          child: AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.35,
              ),
            ),
            content: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actionsOverflowAlignment: OverflowBarAlignment.end,
            actions: [
              ElevatedGreyButton(
                label: cancelLabel,
                fontSize: 11,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(width: 8),
              ElevatedGreyButton(
                label: confirmLabel,
                fontSize: 11,
                isPrimary: true,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// App-wide right-click context menu (square corners, grey→white gradient).
/// Default row height for [AppPopupMenu.tile] in context menus.
const double kAppContextMenuItemHeight = 26;

/// Matches thumbnail toolbar / startup panel surfaces.
const LinearGradient kAppContextMenuGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFF8F8F8), Color(0xFFFEFEFE)],
);

const TextStyle kAppContextMenuTextStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 11,
  fontWeight: FontWeight.w500,
  height: 1.1,
  color: Colors.black87,
);

Future<T?> showAppContextMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  Color? color,
  double? elevation,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<T>(
    _AppContextMenuRoute<T>(
      position: position,
      items: items,
      panelColor: color,
      elevation: elevation ?? 0,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

class _AppContextMenuRoute<T> extends PopupRoute<T> {
  _AppContextMenuRoute({
    required this.position,
    required this.items,
    this.panelColor,
    this.elevation = 0,
    required this.capturedThemes,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final Color? panelColor;
  final double elevation;
  final CapturedThemes capturedThemes;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      CustomSingleChildLayout(
        delegate: _AppContextMenuLayoutDelegate(position),
        child: IntrinsicWidth(
          child: _AppContextMenuPanel<T>(
            items: items,
            panelColor: panelColor,
            elevation: elevation,
          ),
        ),
      ),
    );
  }
}

class _AppContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _AppContextMenuLayoutDelegate(this.position);

  final RelativeRect position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.left;
    double y = position.top;

    if (x + childSize.width > size.width - position.right) {
      x = size.width - position.right - childSize.width;
    }
    if (y + childSize.height > size.height - position.bottom) {
      y = size.height - position.bottom - childSize.height;
    }

    return Offset(x.clamp(0.0, size.width - childSize.width),
        y.clamp(0.0, size.height - childSize.height));
  }

  @override
  bool shouldRelayout(_AppContextMenuLayoutDelegate oldDelegate) {
    return position != oldDelegate.position;
  }
}

class _AppContextMenuPanel<T> extends StatelessWidget {
  const _AppContextMenuPanel({
    required this.items,
    this.panelColor,
    this.elevation = 0,
  });

  final List<PopupMenuEntry<T>> items;
  final Color? panelColor;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: elevation,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 148),
        decoration: BoxDecoration(
          color: panelColor,
          gradient: panelColor == null ? kAppContextMenuGradient : null,
          border: Border.all(color: const Color(0xFFD0D0D0)),
        ),
        child: DefaultTextStyle(
          style: kAppContextMenuTextStyle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) _buildEntry(context, item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, PopupMenuEntry<T> item) {
    if (item is PopupMenuDivider) {
      return Divider(
        height: item.height,
        thickness: item.thickness ?? 1,
        indent: item.indent ?? 0,
        endIndent: item.endIndent ?? 0,
        color: item.color ?? const Color(0xFFE8E8E8),
      );
    }
    if (item is PopupMenuItem<T>) {
      return _AppContextMenuItemRow<T>(item: item);
    }
    return SizedBox(height: item.height);
  }
}

class _AppContextMenuItemRow<T> extends StatefulWidget {
  const _AppContextMenuItemRow({required this.item});

  final PopupMenuItem<T> item;

  @override
  State<_AppContextMenuItemRow<T>> createState() =>
      _AppContextMenuItemRowState<T>();
}

class _AppContextMenuItemRowState<T> extends State<_AppContextMenuItemRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                item.onTap?.call();
                Navigator.pop<T>(context, item.value);
              }
            : null,
        child: Container(
          height: item.height,
          color: _hovered ? const Color(0x0A000000) : null,
          padding: item.padding ??
              const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          alignment: Alignment.centerLeft,
          child: item.child,
        ),
      ),
    );
  }
}

/// Grey bordered action used on startup (Pick folder, Metadata Preset, etc.).
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: enabled ? Colors.grey.shade100 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (!enabled || onTap == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

/// Elevated grey button with hover lift, press feedback, and optional danger state.
class ElevatedGreyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isTealGradient;
  final bool isDanger;
  final bool fullWidth;
  final double fontSize;
  final IconData? icon;

  const ElevatedGreyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isTealGradient = false,
    this.isDanger = false,
    this.fullWidth = false,
    this.fontSize = 13,
    this.icon,
  });

  @override
  State<ElevatedGreyButton> createState() => _ElevatedGreyButtonState();
}

class _ElevatedGreyButtonState extends State<ElevatedGreyButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final danger = widget.isDanger && _hovered && enabled;
    final teal = widget.isTealGradient;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.fullWidth ? double.infinity : null,
          transform: Matrix4.translationValues(
              0, enabled && !_pressed && _hovered ? -1 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !enabled
                  ? (teal ? Colors.grey.shade300 : const Color(0x1A000000))
                  : danger
                      ? const Color(0x33C0392B)
                      : teal
                          ? kFloTealDark
                          : const Color(0x2E000000),
              width: teal ? 0.7 : 0.5,
            ),
            gradient: !enabled
                ? null
                : teal
                    ? (_pressed
                        ? kFloTealGradientVertical
                        : (_hovered
                            ? kFloTealGradientHorizontal
                            : kFloTealGradientHorizontal))
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _pressed
                            ? [const Color(0xFFE0E0E0), const Color(0xFFF0F0F0)]
                            : danger
                                ? [
                                    const Color(0xFFFFF5F5),
                                    const Color(0xFFFFE8E8)
                                  ]
                                : _hovered
                                    ? [
                                        const Color(0xFFFFFFFF),
                                        const Color(0xFFFAFAFA)
                                      ]
                                    : [
                                        const Color(0xFFFFFFFF),
                                        const Color(0xFFFAFAFA)
                                      ],
                      ),
            color: !enabled
                ? (teal ? Colors.grey.shade300 : const Color(0xFFF0F0F0))
                : null,
            boxShadow: !enabled
                ? null
                : _pressed
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 1.5,
                          offset: const Offset(0, 0.75),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: _hovered ? 0.18 : (teal ? 0.14 : 0.13)),
                          blurRadius: _hovered ? 4.5 : (teal ? 3.5 : 2.5),
                          offset:
                              Offset(0, _hovered ? 1.5 : (teal ? 1.5 : 1.25)),
                        ),
                      ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: teal ? 14 : (widget.isPrimary ? 10 : 8),
            vertical: teal ? 6 : 5,
          ),
          child: Row(
            mainAxisSize:
                widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.fontSize,
                  color: !enabled
                      ? (teal ? Colors.grey.shade600 : const Color(0xFFAAAAAA))
                      : danger
                          ? const Color(0xFFC0392B)
                          : teal
                              ? Colors.white
                              : const Color(0xFF555555),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: widget.fontSize,
                    fontVariations: const [FontVariation('wght', 500)],
                    letterSpacing: -0.5,
                    color: !enabled
                        ? (teal
                            ? Colors.grey.shade600
                            : const Color(0xFFAAAAAA))
                        : danger
                            ? const Color(0xFFC0392B)
                            : teal
                                ? Colors.white
                                : const Color(0xFF555555),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact [PopupMenuItem] rows for [showAppContextMenu].
class AppPopupMenu {
  AppPopupMenu._();

  static PopupMenuItem<T> tile<T>({
    required T value,
    required String label,
    IconData? icon,
    bool destructive = false,
    double height = kAppContextMenuItemHeight,
  }) {
    final Color c = destructive ? const Color(0xFFC62828) : Colors.black87;
    return PopupMenuItem<T>(
      value: value,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kAppContextMenuTextStyle.copyWith(color: c),
          ),
        ],
      ),
    );
  }
}
