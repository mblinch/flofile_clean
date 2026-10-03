import 'package:flutter/material.dart';

import '../caption_style/verb_sub_options.dart';
import '../flo_layout_constants.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';

/// RBI + celebration modifiers for the verb editor (app + admin).
///
/// RBI is baseball-only and shown for every baseball verb (defaults off for
/// non-hits). Celebration is always available in baseball; other sports keep
/// hit / celebration / custom rules. Returns [SizedBox.shrink] when neither
/// block applies. Caption previews live in the main editor's variant menu.
class VerbEditSubOptionsSection extends StatefulWidget {
  const VerbEditSubOptionsSection({
    super.key,
    required this.verbLabel,
    required this.value,
    required this.onChanged,
    this.sport,
    this.showBorder = true,
  });

  final String verbLabel;
  final VerbSubOptions value;
  final ValueChanged<VerbSubOptions> onChanged;
  final String? sport;
  final bool showBorder;

  @override
  State<VerbEditSubOptionsSection> createState() =>
      _VerbEditSubOptionsSectionState();
}

class _VerbEditSubOptionsSectionState extends State<VerbEditSubOptionsSection> {
  late final TextEditingController _celebrationPhrase;
  late final TextEditingController _celebrationTypes;

  @override
  void initState() {
    super.initState();
    _celebrationPhrase =
        TextEditingController(text: widget.value.celebrationPhrase);
    _celebrationTypes =
        TextEditingController(text: widget.value.celebrationTypes);
  }

  @override
  void didUpdateWidget(VerbEditSubOptionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.celebrationPhrase != widget.value.celebrationPhrase &&
        _celebrationPhrase.text != widget.value.celebrationPhrase) {
      _celebrationPhrase.text = widget.value.celebrationPhrase;
    }
    if (oldWidget.value.celebrationTypes != widget.value.celebrationTypes &&
        _celebrationTypes.text != widget.value.celebrationTypes) {
      _celebrationTypes.text = widget.value.celebrationTypes;
    }
  }

  @override
  void dispose() {
    _celebrationPhrase.dispose();
    _celebrationTypes.dispose();
    super.dispose();
  }

  void _patch(VerbSubOptions Function(VerbSubOptions) fn) {
    widget.onChanged(fn(widget.value));
  }

  @override
  Widget build(BuildContext context) {
    final showRbi = VerbSubOptions.showRbiEditor(
      sport: widget.sport,
      verbLabel: widget.verbLabel,
      value: widget.value,
    );
    final showCelebration = VerbSubOptions.showCelebrationEditor(
      verbLabel: widget.verbLabel,
      value: widget.value,
      sport: widget.sport,
    );
    if (!showRbi && !showCelebration) {
      return const SizedBox.shrink();
    }

    final defaults =
        VerbSubOptions.defaultsFor(widget.verbLabel, sport: widget.sport);
    final showCelebrationTypes = showCelebration &&
        VerbSubOptions.isCelebrationVerb(widget.verbLabel);
    final isHit = VerbSubOptions.isHitVerb(widget.verbLabel);
    final chipsHint =
        VerbSubOptions.defaultCelebrationTypesForSport(widget.sport);

    final blurb = showRbi && showCelebration
        ? 'Optional RBI and celebration wording for this verb.'
        : showRbi
            ? 'Optional RBI counts for this verb (baseball).'
            : 'Optional celebration wording for this verb.';

    final isHomeRun = widget.verbLabel == 'Home Run';
    final rbiBlock = showRbi
        ? _optionBlock(
            label: isHomeRun ? 'Home run' : 'RBI',
            explanation: isHomeRun
                ? 'Style — default for all run situations'
                : 'Style — default for all RBI situations',
            enabled: widget.value.rbiEnabled,
            defaultOn: defaults.rbiEnabled,
            onEnabledChanged: (v) => _patch((o) => o.copyWith(rbiEnabled: v)),
            children: [
              if (isHomeRun)
                AppDialogLabeledDropdown<HomeRunCaptionStyle>(
                  label: '',
                  value: widget.value.homeRunStyle,
                  items: HomeRunCaptionStyle.values
                      .map(
                        (s) => DropdownMenuItem<HomeRunCaptionStyle>(
                          value: s,
                          child: Text(s.menuLabel),
                        ),
                      )
                      .toList(),
                  onChanged: widget.value.rbiEnabled
                      ? (v) {
                          if (v != null) {
                            _patch((o) => o.copyWith(homeRunStyle: v));
                          }
                        }
                      : null,
                  bottomGap: 0,
                )
              else
                AppDialogLabeledDropdown<RbiCaptionStyle>(
                  label: '',
                  value: widget.value.rbiStyle,
                  items: RbiCaptionStyle.values
                      .map(
                        (s) => DropdownMenuItem<RbiCaptionStyle>(
                          value: s,
                          child: Text(s.menuLabel),
                        ),
                      )
                      .toList(),
                  onChanged: widget.value.rbiEnabled
                      ? (v) {
                          if (v != null) {
                            _patch((o) => o.copyWith(rbiStyle: v));
                          }
                        }
                      : null,
                  bottomGap: 0,
                ),
            ],
          )
        : null;

    final celebrationBlock = showCelebration
        ? _optionBlock(
            label: 'Reactions',
            explanation: 'Comma-separated phrases',
            enabled: widget.value.celebrationEnabled,
            defaultOn: defaults.celebrationEnabled,
            onEnabledChanged: (v) =>
                _patch((o) => o.copyWith(celebrationEnabled: v)),
            children: [
              AppDialogLabeledTextField(
                label: '',
                controller: _celebrationPhrase,
                hintText: VerbSubOptions.suggestedReactionPhrases,
                maxLines: 1,
                enabled: widget.value.celebrationEnabled,
                bottomGap: showCelebrationTypes ? 8 : 0,
                onChanged: (_) => _patch(
                  (o) =>
                      o.copyWith(celebrationPhrase: _celebrationPhrase.text),
                ),
              ),
              if (showCelebrationTypes)
                AppDialogLabeledTextField(
                  label: '',
                  controller: _celebrationTypes,
                  hintText: chipsHint,
                  maxLines: 1,
                  enabled: widget.value.celebrationEnabled,
                  bottomGap: 0,
                  onChanged: (_) => _patch(
                    (o) =>
                        o.copyWith(celebrationTypes: _celebrationTypes.text),
                  ),
                )
              else if (!isHit) ...[
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final tokens = appDialogTokens(context);
                    return Text(
                      VerbSubOptions.isBaseballSport(widget.sport)
                          ? 'Each reaction becomes a chip in Keyboard Fire (Cele, React, …).'
                          : 'Each reaction becomes a chip when this verb is selected.',
                      style: tokens != null
                          ? tokens.metaStyle.copyWith(
                              fontSize: 9,
                              color: tokens.textSecondary,
                              height: 1.3,
                            )
                          : const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              color: Color(0xFF999999),
                              height: 1.3,
                            ),
                    );
                  },
                ),
              ],
            ],
          )
        : null;

    final Widget blocks;
    if (rbiBlock != null && celebrationBlock != null && !widget.showBorder) {
      blocks = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: rbiBlock),
            const SizedBox(width: 12),
            Expanded(child: celebrationBlock),
          ],
        ),
      );
    } else if (rbiBlock != null && celebrationBlock != null) {
      blocks = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rbiBlock,
          const Divider(height: 12, color: Color(0xFFE8E8E8)),
          celebrationBlock,
        ],
      );
    } else {
      blocks = rbiBlock ?? celebrationBlock!;
    }

    final t = appDialogTokens(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MODIFIERS',
          style: t != null
              ? FfTokens.railLabel.copyWith(
                  color: t.text.withValues(alpha: 0.70),
                )
              : kAppDialogFieldLabelStyle,
        ),
        const SizedBox(height: 4),
        Text(
          blurb,
          style: t != null
              ? t.metaStyle.copyWith(
                  fontSize: 10,
                  color: t.textSecondary,
                  height: 1.35,
                )
              : const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: Color(0xFF888888),
                  height: 1.35,
                ),
        ),
        const SizedBox(height: 6),
        blocks,
      ],
    );

    if (!widget.showBorder) return body;

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE4E4E4)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: kVerbEditDialogSubOptionsWidth,
          maxWidth: kVerbEditDialogSubOptionsWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: body,
        ),
      ),
    );
  }

  Widget _optionBlock({
    required String label,
    required String explanation,
    required bool enabled,
    required bool defaultOn,
    required ValueChanged<bool> onEnabledChanged,
    required List<Widget> children,
  }) {
    final t = appDialogTokens(context);
    final accent = t?.accent ?? kFloTealLight;
    final labelStyle = t != null
        ? TextStyle(
            fontFamily: FfTokens.labelFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: enabled ? t.text : t.text.withValues(alpha: 0.42),
          )
        : kAppDialogFieldTextStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: enabled ? null : const Color(0xFFB0B0B0),
          );
    final explanationStyle = t != null
        ? t.metaStyle.copyWith(
            fontSize: 10.5,
            color: enabled
                ? t.textSecondary
                : t.text.withValues(alpha: 0.32),
          )
        : TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            color: enabled ? const Color(0xFF888888) : const Color(0xFFB0B0B0),
          );

    final header = Row(
      children: [
        SizedBox(
          width: 34,
          height: 20,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch.adaptive(
              value: enabled,
              onChanged: onEnabledChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: labelStyle),
        if (enabled != defaultOn) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: t != null ? t.accent : kFloTealDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            explanation,
            style: explanationStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final fill = t != null
        ? (enabled ? t.surface : t.surface.withValues(alpha: 0.45))
        : (enabled ? const Color(0xFFF9FAFB) : const Color(0xFFF0F0F0));
    final border = t != null
        ? (enabled ? t.divider : t.divider.withValues(alpha: 0.55))
        : (enabled ? const Color(0xFFE4E4E4) : const Color(0xFFE8E8E8));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          t != null ? FfTokens.radiusChip : 6,
        ),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          Opacity(
            opacity: enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
