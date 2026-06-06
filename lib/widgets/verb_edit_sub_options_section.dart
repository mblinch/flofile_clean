import 'package:flutter/material.dart';

import '../caption_style/verb_sub_options.dart';
import '../flo_layout_constants.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';

/// RBI + celebration options for the verb editor (app + admin).
class VerbEditSubOptionsSection extends StatefulWidget {
  const VerbEditSubOptionsSection({
    super.key,
    required this.verbLabel,
    required this.value,
    required this.onChanged,
    this.showBorder = true,
  });

  final String verbLabel;
  final VerbSubOptions value;
  final ValueChanged<VerbSubOptions> onChanged;
  final bool showBorder;

  @override
  State<VerbEditSubOptionsSection> createState() =>
      _VerbEditSubOptionsSectionState();
}

class _VerbEditSubOptionsSectionState extends State<VerbEditSubOptionsSection> {
  late final TextEditingController _rbiWord;
  late final TextEditingController _celebrationPhrase;
  late final TextEditingController _celebrationTypes;

  @override
  void initState() {
    super.initState();
    _rbiWord = TextEditingController(text: widget.value.rbiWord);
    _celebrationPhrase =
        TextEditingController(text: widget.value.celebrationPhrase);
    _celebrationTypes =
        TextEditingController(text: widget.value.celebrationTypes);
  }

  @override
  void didUpdateWidget(VerbEditSubOptionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.rbiWord != widget.value.rbiWord &&
        _rbiWord.text != widget.value.rbiWord) {
      _rbiWord.text = widget.value.rbiWord;
    }
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
    _rbiWord.dispose();
    _celebrationPhrase.dispose();
    _celebrationTypes.dispose();
    super.dispose();
  }

  void _patch(VerbSubOptions Function(VerbSubOptions) fn) {
    widget.onChanged(fn(widget.value));
  }

  @override
  Widget build(BuildContext context) {
    final defaults = VerbSubOptions.defaultsFor(widget.verbLabel);
    final showCelebrationTypes = defaults.celebrationEnabled &&
        const {
          'Celebration',
          'Celebrates',
          'Celebrates With',
          'Celebrates Against',
          'Celebrates a Goal',
        }.contains(widget.verbLabel);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Options', style: kAppDialogFieldLabelStyle),
        const SizedBox(height: 4),
        const Text(
          'RBI counts and celebration wording for this verb.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            color: Color(0xFF888888),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _optionBlock(
          label: 'RBI',
          enabled: widget.value.rbiEnabled,
          defaultOn: defaults.rbiEnabled,
          onEnabledChanged: (v) => _patch((o) => o.copyWith(rbiEnabled: v)),
          children: [
            AppDialogLabeledTextField(
              label: 'RBI label in caption',
              controller: _rbiWord,
              hintText: 'e.g., RBI',
              enabled: widget.value.rbiEnabled,
              bottomGap: 0,
              onChanged: (_) =>
                  _patch((o) => o.copyWith(rbiWord: _rbiWord.text)),
            ),
            const SizedBox(height: 4),
            Text(
              'Example: hits a ${_rbiWord.text.trim().isEmpty ? 'RBI' : _rbiWord.text.trim()} single, '
              'two-${_rbiWord.text.trim().isEmpty ? 'RBI' : _rbiWord.text.trim()}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                color: Color(0xFF999999),
                height: 1.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _optionBlock(
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
                (o) => o.copyWith(celebrationPhrase: _celebrationPhrase.text),
              ),
            ),
            if (showCelebrationTypes)
              AppDialogLabeledTextField(
                label: 'Celebration chips (comma-separated)',
                controller: _celebrationTypes,
                hintText: VerbSubOptions.defaultCelebrationTypes,
                maxLines: 2,
                enabled: widget.value.celebrationEnabled,
                bottomGap: 0,
                onChanged: (_) => _patch(
                  (o) => o.copyWith(celebrationTypes: _celebrationTypes.text),
                ),
              ),
            if (!showCelebrationTypes) ...[
              const SizedBox(height: 4),
              Text(
                'Used for the Cele button on hitting verbs (Keyboard Fire).',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  color: Color(0xFF999999),
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    if (!widget.showBorder) return body;

    return Container(
      width: kVerbEditDialogSubOptionsWidth,
      padding: const EdgeInsets.all(14),
      decoration: appDialogCardDecoration(),
      child: body,
    );
  }

  Widget _optionBlock({
    required String label,
    required bool enabled,
    required bool defaultOn,
    required ValueChanged<bool> onEnabledChanged,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: appDialogCardDecoration(radius: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            ...children,
          ],
        ],
      ),
    );
  }
}
