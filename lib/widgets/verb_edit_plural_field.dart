import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';

/// Plural phrase field — checkbox beside the title, fields align with Singular.
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
      labelLeading: AppCompactCheckbox(
        value: usePluralPhrase,
        accentColor: kFloTealLight,
        onChanged: onUsePluralChanged,
        minTapTargetSize: 14,
      ),
      child: AppDialogControlShell(
        enabled: usePluralPhrase,
        child: TextField(
          controller: pluralController,
          enabled: usePluralPhrase,
          style: kAppDialogFieldTextStyle.copyWith(
            color: usePluralPhrase
                ? kAppDialogFieldTextStyle.color
                : const Color(0xFFB0B0B0),
          ),
          onChanged: onPluralChanged,
          decoration: appDialogBareFieldDecoration(
            hintText: 'e.g., hit a single, skate, celebrate',
          ),
        ),
      ),
    );
  }
}
