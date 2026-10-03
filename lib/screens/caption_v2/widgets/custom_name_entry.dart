import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';

class CustomNameEntryResult {
  const CustomNameEntryResult({required this.name, this.jersey});
  final String name;
  final String? jersey;
}

Future<CustomNameEntryResult?> showCustomNameEntryDialog({
  required BuildContext context,
  required String teamLabel,
  String title = 'Custom name',
  String confirmLabel = 'Add',
  String? initialName,
  String? initialJersey,
}) {
  return showDialog<CustomNameEntryResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _CustomNameDialog(
      teamLabel: teamLabel,
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialJersey: initialJersey,
    ),
  );
}

/// Compact footer control used under roster / drum lanes.
class CustomNameEntryButton extends StatelessWidget {
  const CustomNameEntryButton({
    super.key,
    required this.tokens,
    required this.onTap,
  });

  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: tokens.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1, size: 13, color: tokens.accent),
                const SizedBox(width: 5),
                Text(
                  'Custom name',
                  style: tokens.metaStyle.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.accent,
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

class _CustomNameDialog extends StatefulWidget {
  const _CustomNameDialog({
    required this.teamLabel,
    required this.title,
    required this.confirmLabel,
    this.initialName,
    this.initialJersey,
  });

  final String teamLabel;
  final String title;
  final String confirmLabel;
  final String? initialName;
  final String? initialJersey;

  @override
  State<_CustomNameDialog> createState() => _CustomNameDialogState();
}

class _CustomNameDialogState extends State<_CustomNameDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _jerseyCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _jerseyCtrl = TextEditingController(text: widget.initialJersey ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _jerseyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final jersey = _jerseyCtrl.text.trim();
    Navigator.pop(
      context,
      CustomNameEntryResult(
        name: name,
        jersey: jersey.isEmpty ? null : jersey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final canAdd = _nameCtrl.text.trim().isNotEmpty;

    return AppDialogFfStyle(
      enabled: true,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                border: Border.all(color: t.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                      decoration: BoxDecoration(
                        color: t.bg,
                        border: Border(
                          bottom: BorderSide(color: t.divider),
                        ),
                      ),
                      child: Text(
                        '${widget.title} · ${widget.teamLabel}',
                        style: t.labelStyle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Name', style: t.microStyle),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _nameCtrl,
                            autofocus: true,
                            style: t.metaStyle.copyWith(color: t.text),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (canAdd) _submit();
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Full name',
                              hintStyle: t.metaStyle
                                  .copyWith(color: t.textSecondary),
                              filled: true,
                              fillColor: t.sunken,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.divider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.divider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.accent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('Jersey (optional)', style: t.microStyle),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _jerseyCtrl,
                            style: t.metaStyle.copyWith(color: t.text),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (canAdd) _submit();
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '#',
                              hintStyle: t.metaStyle
                                  .copyWith(color: t.textSecondary),
                              filled: true,
                              fillColor: t.sunken,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.divider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.divider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(FfTokens.radiusChip),
                                borderSide: BorderSide(color: t.accent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedGreyButton(
                            label: 'Cancel',
                            fontSize: 11,
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          ElevatedGreyButton(
                            label: widget.confirmLabel,
                            fontSize: 11,
                            isPrimary: true,
                            onPressed: canAdd ? _submit : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
