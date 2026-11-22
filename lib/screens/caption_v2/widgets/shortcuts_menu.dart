import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';

/// Top-bar keyboard shortcuts reference for an active caption session.
class CaptionV2ShortcutsMenuButton extends StatefulWidget {
  const CaptionV2ShortcutsMenuButton({
    super.key,
    required this.tokens,
    this.ftpMode = false,
    this.compact = false,
  });

  final FfTokens tokens;
  final bool ftpMode;
  final bool compact;

  @override
  State<CaptionV2ShortcutsMenuButton> createState() =>
      _CaptionV2ShortcutsMenuButtonState();
}

class _CaptionV2ShortcutsMenuButtonState
    extends State<CaptionV2ShortcutsMenuButton> {
  final MenuController _menu = MenuController();

  static String get _mod => Platform.isMacOS ? '⌘' : 'Ctrl';

  List<({String keys, String label})> _rowsFor(bool ftpMode) {
    final mod = _mod;
    return [
      (keys: '$mod K', label: 'Open Firebar search'),
      (keys: 'Esc', label: 'Close Firebar / clear search'),
      (keys: 'Tab / ⇧Tab', label: 'Cycle Home → Verbs → Away'),
      (keys: '← →', label: 'Previous / next frame'),
      (keys: '$mod S', label: 'Save & next'),
      (
        keys: '⇧↵',
        label: ftpMode ? 'Save, FTP & next' : 'Save & next',
      ),
      if (ftpMode) (keys: '$mod ↵', label: 'Save, FTP & next'),
      if (ftpMode) (keys: '⇧ F', label: 'Transmit current'),
      (keys: '$mod ⇧ V', label: 'Paste previous caption'),
      (keys: '↵', label: 'Apply last combo & save next'),
      (keys: '$mod Z', label: 'Undo Firebar change'),
      (keys: 'Ctrl + #', label: 'Home jersey number'),
      (
        keys: Platform.isMacOS ? '⌘ / ⌥ + #' : 'Alt + #',
        label: 'Away jersey number',
      ),
      (keys: '⇧ + #', label: 'Select verb by number'),
      (keys: '1–9', label: 'Pick Firebar result'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final rows = _rowsFor(widget.ftpMode);
    final compact = widget.compact;
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: t.divider),
          ),
        ),
      ),
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(9),
            child: Tooltip(
              message: 'Keyboard shortcuts',
              child: Container(
                height: 32,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
                decoration: BoxDecoration(
                  color: open ? t.hover : t.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: open ? Border.all(color: t.divider) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.keyboard,
                      size: 16,
                      color: open ? t.text : t.textSecondary,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Shortcuts',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1,
                          color: open ? t.text : t.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 300,
            maxWidth: 340,
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.keyboard,
                      size: 14,
                      color: t.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Keyboard shortcuts',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 7),
                  _ShortcutRow(keys: rows[i].keys, label: rows[i].label),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: t.divider),
          ),
          child: Text(
            keys,
            style: TextStyle(
              fontFamily: FfTokens.monoFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: t.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: t.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
