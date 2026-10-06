import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/mac_spell_check_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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

/// Inline footer field matching the custom-verb bar: jersey + name + last + pin.
class CustomNameField extends StatelessWidget {
  const CustomNameField({
    super.key,
    required this.nameController,
    required this.jerseyController,
    required this.nameFocusNode,
    required this.jerseyFocusNode,
    required this.tokens,
    required this.pinned,
    required this.canUseLast,
    required this.onSubmit,
    required this.onTogglePin,
    required this.onUseLast,
    this.onChanged,
  });

  final TextEditingController nameController;
  final TextEditingController jerseyController;
  final FocusNode nameFocusNode;
  final FocusNode jerseyFocusNode;
  final FfTokens tokens;
  final bool pinned;
  final bool canUseLast;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePin;
  final VoidCallback onUseLast;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final canPin = nameController.text.trim().isNotEmpty || pinned;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: tokens.sunken,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: pinned ? FfTokens.pinned : tokens.divider,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: TextField(
                controller: jerseyController,
                focusNode: jerseyFocusNode,
                readOnly: pinned,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                  LengthLimitingTextInputFormatter(3),
                ],
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.next,
                onChanged: (_) => onChanged?.call(),
                onSubmitted: (_) => nameFocusNode.requestFocus(),
                style: tokens.jerseyStyle.copyWith(
                  fontSize: 12,
                  color: tokens.text,
                  height: 1.1,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '#',
                  hintStyle: tokens.jerseyStyle.copyWith(
                    fontSize: 12,
                    color: tokens.textSecondary,
                    height: 1.1,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  border: InputBorder.none,
                ),
              ),
            ),
            Container(width: 1, height: 16, color: tokens.divider),
            Expanded(
              child: TextField(
                controller: nameController,
                focusNode: nameFocusNode,
                readOnly: pinned,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onChanged: (_) => onChanged?.call(),
                onSubmitted: (_) => onSubmit(),
                spellCheckConfiguration: floSpellCheckConfiguration(),
                contextMenuBuilder: floSpellCheckContextMenuBuilder,
                style: tokens.labelStyle.copyWith(
                  fontSize: 11.5,
                  color: tokens.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Custom name',
                  hintStyle: tokens.labelStyle.copyWith(
                    fontSize: 11.5,
                    color: tokens.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                  border: InputBorder.none,
                ),
              ),
            ),
            _CustomNameAction(
              icon: PhosphorIconsRegular.clockCounterClockwise,
              tooltip: 'Use last custom name',
              tokens: tokens,
              enabled: canUseLast,
              onTap: onUseLast,
            ),
            _CustomNameAction(
              icon: PhosphorIconsRegular.check,
              tooltip: 'Add custom player',
              tokens: tokens,
              enabled: !pinned && nameController.text.trim().isNotEmpty,
              selected: false,
              onTap: onSubmit,
            ),
            _CustomNameAction(
              icon: pinned ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
              tooltip: pinned ? 'Unpin custom name' : 'Pin custom name',
              tokens: tokens,
              enabled: canPin,
              selected: pinned,
              onTap: onTogglePin,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomNameAction extends StatelessWidget {
  const _CustomNameAction({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.enabled,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final FfTokens tokens;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 25,
          height: 28,
          child: PhosphorIcon(
            icon,
            size: 14,
            color: enabled
                ? (selected ? FfTokens.pinned : tokens.textSecondary)
                : tokens.divider,
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
