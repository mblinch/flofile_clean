import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';

/// Plural phrase row with "Use plural" toggle — shared by verb editors.
class VerbEditPluralPhraseField extends StatelessWidget {
  const VerbEditPluralPhraseField({
    super.key,
    required this.pluralController,
    required this.usePluralPhrase,
    required this.onUsePluralChanged,
    this.onPluralChanged,
    this.bottomGap = 0,
  });

  final TextEditingController pluralController;
  final bool usePluralPhrase;
  final ValueChanged<bool> onUsePluralChanged;
  final ValueChanged<String>? onPluralChanged;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return AppDialogLabeledField(
      label: 'Plural phrase (2+ players)',
      bottomGap: bottomGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Use plural',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(width: 4),
              AppCompactCheckbox(
                value: usePluralPhrase,
                accentColor: kFloTealLight,
                onChanged: onUsePluralChanged,
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: pluralController,
            enabled: usePluralPhrase,
            style: kAppDialogFieldTextStyle,
            onChanged: onPluralChanged,
            decoration: appDialogFieldDecoration(
              hintText: 'e.g., hit a single, skate, celebrate',
            ),
          ),
        ],
      ),
    );
  }
}
