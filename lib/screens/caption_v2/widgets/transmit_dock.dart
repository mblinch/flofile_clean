import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import 'frame_status_dot.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Compact caption actions shown beneath the all-at-once search field.
class CaptionV2ActionRow extends StatelessWidget {
  const CaptionV2ActionRow({
    super.key,
    required this.onSavePrevious,
    required this.onCopy,
    required this.onPaste,
    required this.onPastePrevious,
    required this.onSaveNext,
    required this.onTransmit,
    this.transmitLabel = 'FTP',
    this.pasteEnabled = true,
    this.saveNextEnabled = true,
    this.transmitEnabled = true,
    this.showTransmit = true,
    this.onFtpHistory,
  });

  final VoidCallback? onSavePrevious;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPastePrevious;
  final VoidCallback? onSaveNext;
  final VoidCallback? onTransmit;
  final String transmitLabel;
  final bool pasteEnabled;
  final bool saveNextEnabled;
  final bool transmitEnabled;
  final bool showTransmit;
  final VoidCallback? onFtpHistory;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final hideHints = MediaQuery.sizeOf(context).width < 1100;
    final buttons = <Widget>[
      _UtilityButton(
        label: '‹ Save & Prev',
        tokens: t,
        onPressed: onSavePrevious,
      ),
      _UtilityButton(
        label: 'Copy',
        tokens: t,
        onPressed: onCopy,
      ),
      _UtilityButton(
        label: 'Paste',
        tokens: t,
        enabled: pasteEnabled,
        dimWhenDisabled: false,
        onPressed: onPaste,
      ),
      _UtilityButton(
        label: 'Paste Last',
        tokens: t,
        onPressed: onPastePrevious,
      ),
      _UtilityButton(
        label: 'Save & Next',
        hint: hideHints ? null : '⌘S ›',
        tokens: t,
        enabled: saveNextEnabled,
        onPressed: onSaveNext,
      ),
      if (showTransmit)
        _UtilityButton(
          label: transmitLabel,
          tokens: t,
          enabled: transmitEnabled,
          onPressed: onTransmit,
        ),
    ];

    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: buttons[i]),
            if (showTransmit &&
                onFtpHistory != null &&
                i == buttons.length - 1) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'FTP history',
                onPressed: onFtpHistory,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: PhosphorIcon(
                  PhosphorIconsRegular.clockCounterClockwise,
                  size: 18,
                  color: t.textSecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class FtpModeToggle extends StatelessWidget {
  const FtpModeToggle({
    super.key,
    required this.enabled,
    required this.tokens,
    required this.onChanged,
  });

  final bool enabled;
  final FfTokens tokens;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled
          ? 'FTP mode on — FTP buttons and shortcuts are available'
          : 'FTP mode off — FTP buttons and shortcuts are hidden',
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FTP Mode',
            style: tokens.metaStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          Transform.scale(
            scale: 0.55,
            alignment: Alignment.centerLeft,
            child: Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeTrackColor: tokens.accent,
              inactiveTrackColor: tokens.hover,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return tokens.bg;
                }
                return tokens.textTertiary;
              }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned bottom dock: modes, destination, queue, Transmit, Save & next.
///
/// Primary actions are always OUTLINED (accent border, transparent fill).
class TransmitDock extends StatelessWidget {
  const TransmitDock({
    super.key,
    this.modesLabel,
    this.sessionMeta,
    this.sentCount,
    this.savedCount,
    this.todoCount,
    this.destination,
    this.queueLabel,
    this.onPastePrevious,
    this.onCopy,
    this.onPaste,
    this.pasteEnabled = true,
    this.onTransmit,
    this.onSaveNext,
    this.transmitEnabled = true,
    this.saveNextEnabled = true,
  });

  /// e.g. "Modes 2 on"
  final String? modesLabel;

  /// e.g. "Burst detection"
  final String? sessionMeta;

  final int? sentCount;
  final int? savedCount;
  final int? todoCount;

  /// e.g. "Photoshelter · FTP"
  final String? destination;

  /// e.g. "4 queued · last sent 7:08 PM"
  final String? queueLabel;

  final VoidCallback? onPastePrevious;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final bool pasteEnabled;
  final VoidCallback? onTransmit;
  final VoidCallback? onSaveNext;
  final bool transmitEnabled;
  final bool saveNextEnabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final isMobile = MediaQuery.sizeOf(context).width < 1100;
    final btnMinH = isMobile ? FfTokens.hitDockButtonMobile : 32.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          if (sentCount != null && savedCount != null && todoCount != null) ...[
            Text('SESSION', style: t.microStyle),
            const SizedBox(width: 12),
            _SessionCount(
              state: FrameState.sent,
              label: '$sentCount sent',
              tokens: t,
            ),
            const SizedBox(width: 14),
            _SessionCount(
              state: FrameState.saved,
              label: '$savedCount saved',
              tokens: t,
            ),
            const SizedBox(width: 14),
            _SessionCount(
              state: FrameState.todo,
              label: '$todoCount to do',
              tokens: t,
            ),
          ] else if (modesLabel != null) ...[
            Text(modesLabel!, style: t.secondaryLabelStyle),
          ],
          if (sessionMeta != null)
            Flexible(
              child: Text(
                sessionMeta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.metaStyle,
              ),
            ),
          const Spacer(),
          if (destination != null) ...[
            Text(destination!, style: t.secondaryLabelStyle),
            const SizedBox(width: 12),
          ],
          if (queueLabel != null) ...[
            Text(queueLabel!, style: t.metaStyle),
            const SizedBox(width: 16),
          ],
          if (onCopy != null) ...[
            _UtilityButton(
              label: 'Copy',
              tokens: t,
              onPressed: onCopy,
            ),
            const SizedBox(width: 6),
          ],
          if (onPaste != null) ...[
            _UtilityButton(
              label: 'Paste',
              tokens: t,
              enabled: pasteEnabled,
              onPressed: onPaste,
            ),
            const SizedBox(width: 6),
          ],
          if (onPastePrevious != null) ...[
            _UtilityButton(
              label: 'Paste Last',
              tokens: t,
              onPressed: onPastePrevious,
            ),
            const SizedBox(width: 8),
          ],
          _OutlinedActionButton(
            label: 'Save & Next',
            hint: isMobile ? null : '⌘S ›',
            tokens: t,
            minHeight: btnMinH,
            enabled: saveNextEnabled,
            onPressed: onSaveNext,
          ),
          const SizedBox(width: 10),
          _OutlinedActionButton(
            label: 'Transmit',
            hint: isMobile ? null : '⇧F',
            tokens: t,
            minHeight: btnMinH,
            enabled: transmitEnabled,
            onPressed: onTransmit,
          ),
        ],
      ),
    );
  }
}

class _UtilityButton extends StatefulWidget {
  const _UtilityButton({
    required this.label,
    required this.tokens,
    required this.onPressed,
    this.hint,
    this.enabled = true,
    this.dimWhenDisabled = true,
    this.primary = false,
  });

  final String label;
  final FfTokens tokens;
  final VoidCallback? onPressed;
  final String? hint;
  final bool enabled;
  final bool dimWhenDisabled;
  final bool primary;

  @override
  State<_UtilityButton> createState() => _UtilityButtonState();
}

class _UtilityButtonState extends State<_UtilityButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final primary = widget.primary;
    final enabled = widget.enabled;
    final dimWhenDisabled = widget.dimWhenDisabled;
    final hovering = enabled && _hovered;

    // Primary (Save & Next) = dark teal fill + white glowing outline.
    // Hover: white rim + white glow for all variants.
    final fg = primary ? Colors.white : tokens.text;
    final bg = primary ? FfTokens.nocturneAccentSoft : tokens.surface;
    final border = hovering || primary
        ? Colors.white.withValues(alpha: 0.92)
        : tokens.accent;
    final disabledFill = primary
        ? FfTokens.nocturneAccentSoft.withValues(alpha: 0.45)
        : bg.withValues(alpha: 0.4);
    final glowColor = hovering || primary ? Colors.white : tokens.accent;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: enabled ? FfTokens.accentButtonGlow(glowColor) : null,
        ),
        child: OutlinedButton(
          onPressed: enabled ? widget.onPressed : null,
          style: OutlinedButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: fg,
            disabledForegroundColor: dimWhenDisabled
                ? (primary
                    ? Colors.white.withValues(alpha: 0.45)
                    : tokens.textSecondary)
                : fg,
            backgroundColor: bg,
            disabledBackgroundColor: dimWhenDisabled ? disabledFill : bg,
            side: BorderSide(
              color: enabled || !dimWhenDisabled
                  ? border
                  : border.withValues(alpha: 0.4),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11.5,
                    letterSpacing: -0.2,
                    fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    height: 1,
                    shadows: enabled
                        ? [
                            Shadow(
                              color: glowColor.withValues(alpha: 0.55),
                              blurRadius: 7,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              if (widget.hint != null) ...[
                const SizedBox(width: 4),
                Text(
                  widget.hint!,
                  softWrap: false,
                  style: tokens.keyHintStyle.copyWith(
                    fontSize: 10,
                    color: primary
                        ? Colors.white.withValues(alpha: 0.78)
                        : tokens.textSecondary,
                    shadows: enabled
                        ? [
                            Shadow(
                              color: glowColor.withValues(alpha: 0.4),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCount extends StatelessWidget {
  const _SessionCount({
    required this.state,
    required this.label,
    required this.tokens,
  });

  final FrameState state;
  final String label;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FrameStatusDot(state: state),
        const SizedBox(width: 5),
        Text(label, style: tokens.metaStyle),
      ],
    );
  }
}

class _OutlinedActionButton extends StatefulWidget {
  const _OutlinedActionButton({
    required this.label,
    required this.tokens,
    required this.minHeight,
    this.hint,
    this.emphasized = false,
    this.enabled = true,
    this.onPressed,
  });

  final String label;
  final FfTokens tokens;
  final double minHeight;
  final String? hint;
  final bool emphasized;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<_OutlinedActionButton> createState() => _OutlinedActionButtonState();
}

class _OutlinedActionButtonState extends State<_OutlinedActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final emphasized = widget.emphasized;
    final enabled = widget.enabled;
    final hovering = enabled && _hovered;
    final glowColor = hovering || emphasized ? Colors.white : tokens.accent;

    // Emphasized (Save & Next): dark teal fill + white glowing outline.
    // Secondary (Transmit): transparent + teal outline glow.
    // Hover: white rim + white glow.
    final borderColor = emphasized
        ? (enabled
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.35))
        : (enabled
            ? (hovering
                ? Colors.white.withValues(alpha: 0.92)
                : tokens.accent)
            : tokens.accent.withValues(alpha: 0.35));
    final textColor = emphasized
        ? (enabled
            ? Colors.white
            : Colors.white.withValues(alpha: 0.45))
        : (enabled ? tokens.text : tokens.textSecondary);
    final fill = emphasized
        ? (enabled
            ? FfTokens.nocturneAccentSoft
            : FfTokens.nocturneAccentSoft.withValues(alpha: 0.45))
        : Colors.transparent;
    final glow = !enabled ? null : FfTokens.accentButtonGlow(glowColor);

    return Opacity(
      opacity: emphasized ? 1 : (enabled ? 1 : 0.55),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            boxShadow: glow,
          ),
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              child: Container(
                constraints:
                    BoxConstraints(minHeight: widget.minHeight, minWidth: 0),
                padding: EdgeInsets.symmetric(
                  horizontal: emphasized ? 16 : 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.labelStyle.copyWith(
                        color: textColor,
                        fontWeight: emphasized ? FontWeight.w600 : null,
                        shadows: enabled
                            ? [
                                Shadow(
                                  color: glowColor.withValues(alpha: 0.55),
                                  blurRadius: 7,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    if (widget.hint != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        widget.hint!,
                        softWrap: false,
                        style: tokens.keyHintStyle.copyWith(
                          color: emphasized
                              ? Colors.white.withValues(alpha: 0.78)
                              : null,
                          shadows: enabled
                              ? [
                                  Shadow(
                                    color: glowColor.withValues(alpha: 0.4),
                                    blurRadius: 5,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
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
