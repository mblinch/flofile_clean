import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/ftp_rename_template.dart';
import '../services/number_sequence_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';

/// Configure the app-wide `{n}` number sequence (digit width + next value).
class NumberSequenceDialog extends StatefulWidget {
  const NumberSequenceDialog({super.key});

  /// Returns `true` when the user saved.
  static Future<bool?> show(BuildContext context) {
    final tokens =
        Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        child: const AppDialogFfStyle(
          enabled: true,
          child: NumberSequenceDialog(),
        ),
      ),
    );
  }

  @override
  State<NumberSequenceDialog> createState() => _NumberSequenceDialogState();
}

class _NumberSequenceDialogState extends State<NumberSequenceDialog> {
  bool _loading = true;
  int _digits = PreferencesService.numberSequenceDigitsDefault;
  late final TextEditingController _nextCtrl;

  @override
  void initState() {
    super.initState();
    _nextCtrl = TextEditingController(text: '0');
    _load();
  }

  Future<void> _load() async {
    final seq = NumberSequenceService.instance;
    await seq.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _digits = seq.digitsOrDefault;
      _nextCtrl.text = '${seq.nextOrDefault}';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nextCtrl.dispose();
    super.dispose();
  }

  int get _nextValue {
    final parsed = int.tryParse(_nextCtrl.text.trim());
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  String get _preview =>
      FtpRenameTemplate.formatSequence(_nextValue, width: _digits);

  Future<void> _save() async {
    await NumberSequenceService.instance.save(
      digits: _digits,
      next: _nextValue,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: t.surface,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            side: BorderSide(color: t.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(bottom: BorderSide(color: t.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'NUMBER SEQUENCE',
                        style: FfTokens.railLabel.copyWith(
                          color: t.text.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(false),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: PhosphorIcon(
                            PhosphorIconsRegular.x,
                            size: 16,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Digits',
                        style: TextStyle(
                          fontFamily: FfTokens.labelFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.text.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var d =
                                  PreferencesService.numberSequenceDigitsMin;
                              d <= PreferencesService.numberSequenceDigitsMax;
                              d++)
                            _DigitChip(
                              digits: d,
                              selected: _digits == d,
                              onTap: () => setState(() => _digits = d),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      AppDialogLabeledTextField(
                        label: 'Next number',
                        controller: _nextCtrl,
                        keyboardType: TextInputType.number,
                        bottomGap: 0,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: t.sunken,
                          borderRadius:
                              BorderRadius.circular(FfTokens.radiusChip),
                          border: Border.all(color: t.divider),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Preview',
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 12,
                                color: t.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _preview,
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 12,
                            onPressed: () =>
                                Navigator.of(context).pop(false),
                          ),
                          const SizedBox(width: 8),
                          ElevatedGreyButton(
                            label: 'Save',
                            fontSize: 12,
                            isPrimary: true,
                            onPressed: _save,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitChip extends StatefulWidget {
  const _DigitChip({
    required this.digits,
    required this.selected,
    required this.onTap,
  });

  final int digits;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DigitChip> createState() => _DigitChipState();
}

class _DigitChipState extends State<_DigitChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 36,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? t.selectedFill
                : (_hover ? t.hover : t.sunken),
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(
              color: selected ? t.accent : t.divider,
            ),
          ),
          child: Text(
            '${widget.digits}',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? t.accent : t.text,
            ),
          ),
        ),
      ),
    );
  }
}
