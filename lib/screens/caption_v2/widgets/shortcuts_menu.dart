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
  });

  final FfTokens tokens;
  final bool ftpMode;

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
      (keys: '$mod K', label: 'Focus Firebar shorthand line'),
      (keys: 'Esc', label: 'Exit Firebar (keep selection)'),
      (keys: 'Tab', label: 'Pick Firebar dropdown row'),
      (keys: '↵', label: 'Apply Firebar line'),
      (keys: 'Tab / ⇧Tab', label: 'Cycle Home → Verbs → Away'),
      (keys: '← →', label: 'Previous / next frame'),
      (keys: 'I', label: 'Open IPTC (thumbnails focused)'),
      (keys: '$mod ↵', label: 'Save & next'),
      (keys: '$mod S', label: 'Save & next'),
      (keys: '⇧↵', label: 'Save & next'),
      (keys: '$mod ⇧ ↵', label: 'Save & previous'),
      if (ftpMode) (keys: '$mod U', label: 'Save, FTP & next'),
      if (ftpMode) (keys: '⇧ F', label: 'Transmit current'),
      (keys: '$mod ⇧ V', label: 'Paste previous caption'),
      (keys: '$mod Z', label: 'Undo Firebar change'),
      (keys: 'Ctrl + #', label: 'Home jersey number'),
      (
        keys: Platform.isMacOS ? '⌘ / ⌥ + #' : 'Alt + #',
        label: 'Away jersey number',
      ),
      (keys: '⇧ + #', label: 'Select verb by number'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final rows = _rowsFor(widget.ftpMode);
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
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(9),
            hoverColor: t.hover,
            child: Tooltip(
              message: 'Keyboard shortcuts',
              child: SizedBox(
                width: 32,
                height: 32,
                child: PhosphorIcon(
                  PhosphorIconsRegular.keyboard,
                  size: 18,
                  color: t.textSecondary,
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
