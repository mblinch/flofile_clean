import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';

/// One editable value chip inside [CaptionStrip].
class CaptionChipData {
  const CaptionChipData({
    required this.id,
    this.label,
    this.placeholder = '…',
  });

  final String id;

  /// Filled chip text. Null/empty → dashed empty chip with [placeholder].
  final String? label;
  final String placeholder;

  bool get isEmpty => label == null || label!.trim().isEmpty;
}

/// Caption sentence with player / verb / RBI / inning as inline editable chips.
///
/// A dashed outlined chip means that value is still empty.
class CaptionStrip extends StatelessWidget {
  const CaptionStrip({
    super.key,
    required this.leading,
    required this.chips,
    required this.trailing,
    this.fullCaption,
    this.onChipTap,
    this.inningLabel,
    this.onInningDecrement,
    this.onInningIncrement,
    this.inningDisabled = false,
    this.onInningActivate,
    this.preSelected = false,
    this.postSelected = false,
    this.onPreTap,
    this.onPostTap,
    this.mlbTimestampVisible = false,
    this.mlbTimestampEnabled = false,
    this.mlbTimestampLoading = false,
    this.mlbTimestampMatched = false,
    this.onMlbTimestampTap,
    this.personality,
    this.onPersonalityChanged,
    this.headline,
    this.onHeadlineChanged,
    this.keywords,
    this.onKeywordsChanged,
    this.onEditTap,
  });

  /// Static text before the first chip (e.g. "Toronto Blue Jays ").
  final String leading;

  /// Ordered editable chips (player, verb, RBI, …).
  final List<CaptionChipData> chips;

  /// Static text after the chips (e.g. " in the … against …").
  final String trailing;

  /// When set (complete selection + caption style), show the full rendered
  /// caption instead of the chip sentence.
  final String? fullCaption;

  final ValueChanged<String>? onChipTap;

  /// Current inning display (e.g. "2nd"). Null hides the stepper.
  final String? inningLabel;
  final VoidCallback? onInningDecrement;
  final VoidCallback? onInningIncrement;
  final bool inningDisabled;
  final VoidCallback? onInningActivate;

  final bool preSelected;
  final bool postSelected;
  final VoidCallback? onPreTap;
  final VoidCallback? onPostTap;
  final bool mlbTimestampVisible;
  final bool mlbTimestampEnabled;
  final bool mlbTimestampLoading;
  final bool mlbTimestampMatched;
  final VoidCallback? onMlbTimestampTap;
  final String? personality;
  final ValueChanged<String>? onPersonalityChanged;
  final String? headline;
  final ValueChanged<String>? onHeadlineChanged;
  final String? keywords;
  final ValueChanged<String>? onKeywordsChanged;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CaptionPanel(
            tokens: t,
            onTap: onEditTap,
            headerTrailing:
                inningLabel != null || onPreTap != null || onPostTap != null
                    ? _InningCard(
                        inningLabel: inningLabel,
                        onInningDecrement: onInningDecrement,
                        onInningIncrement: onInningIncrement,
                        inningDisabled: inningDisabled,
                        onInningActivate: onInningActivate,
                        preSelected: preSelected,
                        postSelected: postSelected,
                        onPreTap: onPreTap,
                        onPostTap: onPostTap,
                        mlbTimestampVisible: mlbTimestampVisible,
                        mlbTimestampEnabled: mlbTimestampEnabled,
                        mlbTimestampLoading: mlbTimestampLoading,
                        mlbTimestampMatched: mlbTimestampMatched,
                        onMlbTimestampTap: onMlbTimestampTap,
                        tokens: t,
                      )
                    : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fullCaption != null && fullCaption!.trim().isNotEmpty)
                  Text(fullCaption!, style: t.captionStyle)
                else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      Text(leading, style: t.captionStyle),
                      for (final chip in chips)
                        _CaptionChip(
                          data: chip,
                          tokens: t,
                          onTap: onChipTap == null
                              ? null
                              : () => onChipTap!(chip.id),
                        ),
                      if (trailing.isNotEmpty)
                        Text(trailing, style: t.captionStyle),
                    ],
                  ),
                if (onPersonalityChanged != null) ...[
                  const SizedBox(height: 10),
                  _PersonalityBar(
                    value: personality ?? '',
                    tokens: t,
                    onChanged: onPersonalityChanged!,
                  ),
                ],
              ],
            ),
          ),
          if (onHeadlineChanged != null) ...[
            const SizedBox(height: 6),
            _MetadataBar(
              label: 'HEADLINE',
              hintText: 'Enter headline',
              value: headline ?? '',
              tokens: t,
              onChanged: onHeadlineChanged!,
            ),
          ],
          if (onKeywordsChanged != null) ...[
            const SizedBox(height: 6),
            _MetadataBar(
              label: 'KEYWORDS',
              hintText: 'Comma-separated keywords',
              value: keywords ?? '',
              tokens: t,
              onChanged: onKeywordsChanged!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptionPanel extends StatefulWidget {
  const _CaptionPanel({
    required this.tokens,
    required this.child,
    this.headerTrailing,
    this.onTap,
  });

  final FfTokens tokens;
  final Widget child;
  final Widget? headerTrailing;
  final VoidCallback? onTap;

  @override
  State<_CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<_CaptionPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Tooltip(
                  message: 'Edit caption style',
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Caption',
                            style: FfTokens.captionTitle.copyWith(
                              color: t.text,
                              fontSize: 26,
                              letterSpacing: -0.78,
                            ),
                          ),
                          const SizedBox(width: 10),
                          PhosphorIcon(
                            PhosphorIconsRegular.notePencil,
                            size: 19,
                            color:
                                t.text.withValues(alpha: _hovered ? 1 : 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.headerTrailing != null) ...[
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 22,
                  color: t.divider,
                ),
                const SizedBox(width: 12),
                widget.headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 8),
          widget.child,
        ],
      ),
    );
  }
}

class _InningCard extends StatelessWidget {
  const _InningCard({
    required this.inningLabel,
    required this.onInningDecrement,
    required this.onInningIncrement,
    required this.inningDisabled,
    required this.onInningActivate,
    required this.preSelected,
    required this.postSelected,
    required this.onPreTap,
    required this.onPostTap,
    required this.mlbTimestampVisible,
    required this.mlbTimestampEnabled,
    required this.mlbTimestampLoading,
    required this.mlbTimestampMatched,
    required this.onMlbTimestampTap,
    required this.tokens,
  });

  final String? inningLabel;
  final VoidCallback? onInningDecrement;
  final VoidCallback? onInningIncrement;
  final bool inningDisabled;
  final VoidCallback? onInningActivate;
  final bool preSelected;
  final bool postSelected;
  final VoidCallback? onPreTap;
  final VoidCallback? onPostTap;
  final bool mlbTimestampVisible;
  final bool mlbTimestampEnabled;
  final bool mlbTimestampLoading;
  final bool mlbTimestampMatched;
  final VoidCallback? onMlbTimestampTap;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPreTap != null) ...[
            SizedBox(
              width: 42,
              height: 24,
              child: _ToggleChip(
                label: 'Pre',
                selected: preSelected,
                tokens: t,
                onTap: onPreTap,
              ),
            ),
            if (inningLabel != null) const SizedBox(width: 6),
          ],
          if (inningLabel != null) ...[
            SizedBox(
              width: 108,
              child: _InningStepper(
                label: '${inningLabel!} INN',
                tokens: t,
                onDecrement: onInningDecrement,
                onIncrement: onInningIncrement,
                disabled: inningDisabled,
                onActivate: onInningActivate,
              ),
            ),
          ],
          if (onPostTap != null) ...[
            if (inningLabel != null) const SizedBox(width: 6),
            SizedBox(
              width: 42,
              height: 24,
              child: _ToggleChip(
                label: 'Post',
                selected: postSelected,
                tokens: t,
                onTap: onPostTap,
              ),
            ),
          ],
          if (mlbTimestampVisible) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 94,
              height: 24,
              child: _MlbTimestampChip(
                enabled: mlbTimestampEnabled,
                loading: mlbTimestampLoading,
                matched: mlbTimestampMatched,
                tokens: t,
                onTap: onMlbTimestampTap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataBar extends StatefulWidget {
  const _MetadataBar({
    required this.label,
    required this.hintText,
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  final String label;
  final String hintText;
  final String value;
  final FfTokens tokens;
  final ValueChanged<String> onChanged;

  @override
  State<_MetadataBar> createState() => _MetadataBarState();
}

class _MetadataBarState extends State<_MetadataBar> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _MetadataBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return SizedBox(
      height: 28,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        style: t.metaStyle.copyWith(color: t.text),
        cursorColor: t.accent,
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Text(widget.label, style: t.microStyle),
          ),
          prefixIconConstraints: const BoxConstraints(),
          hintText: widget.hintText,
          hintStyle: t.metaStyle,
          filled: true,
          fillColor: t.sunken,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: t.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: t.divider),
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _PersonalityBar extends StatefulWidget {
  const _PersonalityBar({
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  final String value;
  final FfTokens tokens;
  final ValueChanged<String> onChanged;

  @override
  State<_PersonalityBar> createState() => _PersonalityBarState();
}

class _PersonalityBarState extends State<_PersonalityBar> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PersonalityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focusNode.hasFocus ? t.accent : t.divider,
          width: _focusNode.hasFocus ? FfTokens.focusOutlineWidth : 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            'PERSONALITY',
            softWrap: false,
            style: FfTokens.railLabel.copyWith(
              color: t.text.withValues(alpha: 0.50),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 1,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: t.text,
              ),
              cursorColor: t.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Person shown in image',
                hintStyle: t.metaStyle,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionChip extends StatelessWidget {
  const _CaptionChip({
    required this.data,
    required this.tokens,
    this.onTap,
  });

  final CaptionChipData data;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = data.isEmpty;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        empty ? data.placeholder : data.label!,
        style: tokens.chipStyle.copyWith(
          color: empty ? tokens.textSecondary : tokens.text,
          fontWeight: empty ? FfTokens.weightRegular : FfTokens.weightMedium,
        ),
      ),
    );

    if (empty) {
      return GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: tokens.accent.withValues(alpha: 0.55),
            radius: FfTokens.radiusChip,
          ),
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.badgeFill,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(color: tokens.divider),
        ),
        child: child,
      ),
    );
  }
}

class _InningStepper extends StatelessWidget {
  const _InningStepper({
    required this.label,
    required this.tokens,
    this.onDecrement,
    this.onIncrement,
    this.disabled = false,
    this.onActivate,
  });

  final String label;
  final FfTokens tokens;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final bool disabled;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? onActivate : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: disabled ? 0.20 : 1,
        child: IgnorePointer(
          ignoring: disabled,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: tokens.divider),
            ),
            child: Row(
              children: [
                _StepButton(
                    icon: Icons.remove, onTap: onDecrement, tokens: tokens),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: FfTokens.inningValue.copyWith(color: tokens.text),
                  ),
                ),
                _StepButton(
                    icon: Icons.add, onTap: onIncrement, tokens: tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tokens,
    this.onTap,
  });

  final IconData icon;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Icon(
          icon,
          size: 15,
          color: tokens.text.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _MlbTimestampChip extends StatelessWidget {
  const _MlbTimestampChip({
    required this.enabled,
    required this.loading,
    required this.matched,
    required this.tokens,
    this.onTap,
  });

  final bool enabled;
  final bool loading;
  final bool matched;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled || matched;
    return Tooltip(
      message: matched
          ? 'Inning matched from MLB timestamp. Click to turn off.'
          : active
              ? 'Match inning from this image’s EXIF timestamp.'
              : 'Turn on MLB timestamp matching.',
      child: Material(
        color: matched ? tokens.selectedFill : tokens.badgeFill,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.textSecondary,
                    ),
                  )
                else
                  Icon(
                    matched ? Icons.schedule : Icons.schedule_outlined,
                    size: 13,
                    color: matched ? tokens.accent : tokens.textSecondary,
                  ),
                const SizedBox(width: 6),
                Text(
                  loading ? 'MATCHING' : 'MLB TIME',
                  style: FfTokens.railLabel.copyWith(
                    color: matched ? tokens.accent : tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.tokens,
    this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.selectedFill : tokens.badgeFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? tokens.accent : tokens.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: FfTokens.labelFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? tokens.accent : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const double _strokeWidth = 1;
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
