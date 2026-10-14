import 'package:flutter/material.dart';

import '../theme/ff_tokens.dart';

/// One photographer field. It stays blank until a name is typed or chosen.
class PhotographerNameField extends StatefulWidget {
  const PhotographerNameField({
    super.key,
    required this.controller,
    required this.names,
    this.onSelected,
    this.decoration,
    this.style,
    this.strutStyle,
  });

  final TextEditingController controller;
  final List<String> names;
  final ValueChanged<String>? onSelected;
  final InputDecoration? decoration;
  final TextStyle? style;
  final StrutStyle? strutStyle;

  @override
  State<PhotographerNameField> createState() => _PhotographerNameFieldState();
}

class _PhotographerNameFieldState extends State<PhotographerNameField> {
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final Object _tapGroup = Object();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(PhotographerNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus && widget.names.isNotEmpty) {
      _portal.show();
    } else {
      _portal.hide();
    }
    setState(() {});
  }

  void _onText() {
    if (_focus.hasFocus && widget.names.isNotEmpty) {
      _portal.show();
    }
    setState(() {});
  }

  List<String> get _matches {
    final query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.names;
    return [
      for (final name in widget.names)
        if (name.toLowerCase().contains(query)) name,
    ];
  }

  void _choose(String name) {
    widget.controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    widget.onSelected?.call(name);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      borderSide: BorderSide(color: t.divider),
    );
    final matches = _matches;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        if (matches.isEmpty) return const SizedBox.shrink();
        return CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _link.leaderSize?.width,
              child: TapRegion(
                groupId: _tapGroup,
                child: Material(
                  color: t.surface,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: t.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: t.divider),
                      itemBuilder: (context, index) {
                        final name = matches[index];
                        return Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) => _choose(name),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyStyle.copyWith(fontSize: 13),
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
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          groupId: _tapGroup,
          maxLines: 1,
          style: widget.style ??
              t.bodyStyle.copyWith(
                fontSize: 13,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
          strutStyle: widget.strutStyle,
          cursorColor: t.accent,
          textAlignVertical: TextAlignVertical.center,
          decoration: widget.decoration ??
              InputDecoration(
                isDense: true,
                isCollapsed: true,
                filled: true,
                fillColor: t.sunken,
                hintStyle: t.metaStyle.copyWith(color: t.textTertiary),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: border,
                enabledBorder: border,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  borderSide: BorderSide(color: t.accent, width: 1.2),
                ),
              ),
        ),
      ),
    );
  }
}
