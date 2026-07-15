import 'package:flutter/material.dart';

import '../caption_style/verb_sub_options.dart';
import '../flo_layout_constants.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';

/// RBI + celebration modifiers for the verb editor (app + admin).
///
/// RBI is baseball-only. Celebration is cross-sport. Returns [SizedBox.shrink]
/// when neither block applies to the current verb/sport.
/// Caption previews live in the main editor's variant menu.
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

    final rbiBlock = showRbi
        ? _optionBlock(
            label: 'RBI',
            enabled: widget.value.rbiEnabled,
            defaultOn: defaults.rbiEnabled,
            onEnabledChanged: (v) => _patch((o) => o.copyWith(rbiEnabled: v)),
            children: [
              AppDialogLabeledDropdown<RbiCaptionStyle>(
                label: 'RBI style',
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
            label: 'Celebration',
            enabled: widget.value.celebrationEnabled,
            defaultOn: defaults.celebrationEnabled,
            onEnabledChanged: (v) =>
                _patch((o) => o.copyWith(celebrationEnabled: v)),
            children: [
              AppDialogLabeledTextField(
                label: 'Celebration verb',
                controller: _celebrationPhrase,
                hintText: 'e.g., celebrates',
                enabled: widget.value.celebrationEnabled,
                bottomGap: showCelebrationTypes ? 8 : 0,
                onChanged: (_) => _patch(
                  (o) =>
                      o.copyWith(celebrationPhrase: _celebrationPhrase.text),
                ),
              ),
              if (showCelebrationTypes)
                AppDialogLabeledTextField(
                  label: 'Celebration chips (comma-separated)',
                  controller: _celebrationTypes,
                  hintText: chipsHint,
                  maxLines: 2,
                  enabled: widget.value.celebrationEnabled,
                  bottomGap: 0,
                  onChanged: (_) => _patch(
                    (o) =>
                        o.copyWith(celebrationTypes: _celebrationTypes.text),
                  ),
                )
              else if (!isHit) ...[
                const SizedBox(height: 4),
                Text(
                  VerbSubOptions.isBaseballSport(widget.sport)
                      ? 'Used for the Cele button on hitting verbs (Keyboard Fire).'
                      : 'Used when this verb triggers a celebration caption.',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    color: Color(0xFF999999),
                    height: 1.3,
                  ),
                ),
              ],
            ],
          )
        : null;

    final Widget blocks;
    if (rbiBlock != null && celebrationBlock != null && !widget.showBorder) {
      blocks = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: rbiBlock),
          const SizedBox(width: 12),
          Expanded(child: celebrationBlock),
        ],
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

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Modifiers', style: kAppDialogFieldLabelStyle),
        const SizedBox(height: 4),
        Text(
          blurb,
          style: const TextStyle(
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
    required bool enabled,
    required bool defaultOn,
    required ValueChanged<bool> onEnabledChanged,
    required List<Widget> children,
  }) {
    final header = Row(
      children: [
        AppCompactCheckbox(
          value: enabled,
          accentColor: kFloTealLight,
          onChanged: onEnabledChanged,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: kAppDialogFieldTextStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        if (enabled != defaultOn) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: kFloTealDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    return DecoratedBox(
      decoration: enabled
          ? BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE4E4E4)),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: enabled ? 8 : 0,
          vertical: enabled ? 8 : 2,
        ),
        child: enabled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 8),
                  ...children,
                ],
              )
            : SizedBox(
                height: 28,
                child: Align(alignment: Alignment.centerLeft, child: header),
              ),
      ),
    );
  }
}
