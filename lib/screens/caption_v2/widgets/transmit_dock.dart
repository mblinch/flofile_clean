import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import 'frame_status_dot.dart';

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
    this.pasteEnabled = true,
    this.saveNextEnabled = true,
    this.transmitEnabled = true,
  });

  final VoidCallback? onSavePrevious;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPastePrevious;
  final VoidCallback? onSaveNext;
  final VoidCallback? onTransmit;
  final bool pasteEnabled;
  final bool saveNextEnabled;
  final bool transmitEnabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final buttons = <Widget>[
      _UtilityButton(
        label: 'Save',
        icon: Icons.chevron_left,
        tokens: t,
        onPressed: onSavePrevious,
      ),
      _UtilityButton(
        label: 'Copy',
        icon: Icons.copy_outlined,
        tokens: t,
        onPressed: onCopy,
      ),
      _UtilityButton(
        label: 'Paste',
        icon: Icons.content_paste,
        tokens: t,
        enabled: pasteEnabled,
        dimWhenDisabled: false,
        onPressed: onPaste,
      ),
      _UtilityButton(
        label: 'Paste\nPrevious',
        icon: Icons.history,
        tokens: t,
        onPressed: onPastePrevious,
      ),
      _UtilityButton(
        label: 'Save',
        icon: Icons.chevron_right,
        iconTrailing: true,
        tokens: t,
        enabled: saveNextEnabled,
        onPressed: onSaveNext,
      ),
      _UtilityButton(
        label: 'FTP',
        icon: Icons.send_outlined,
        tokens: t,
        enabled: transmitEnabled,
        emphasized: true,
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
          ],
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
              icon: Icons.copy_outlined,
              tokens: t,
              onPressed: onCopy,
            ),
            const SizedBox(width: 6),
          ],
          if (onPaste != null) ...[
            _UtilityButton(
              label: 'Paste',
              icon: Icons.content_paste,
              tokens: t,
              enabled: pasteEnabled,
              onPressed: onPaste,
            ),
            const SizedBox(width: 6),
          ],
          if (onPastePrevious != null) ...[
            _UtilityButton(
              label: 'Paste prev',
              icon: Icons.history,
              tokens: t,
              onPressed: onPastePrevious,
            ),
            const SizedBox(width: 8),
          ],
          _OutlinedActionButton(
            label: 'Save & next',
            trailingIcon: Icons.chevron_right,
            tokens: t,
            minHeight: btnMinH,
            emphasized: true,
            enabled: saveNextEnabled,
            onPressed: onSaveNext,
          ),
          const SizedBox(width: 10),
          _OutlinedActionButton(
            label: 'Transmit',
            hint: '⇧F',
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

class _UtilityButton extends StatelessWidget {
  const _UtilityButton({
    required this.label,
    required this.icon,
    required this.tokens,
    required this.onPressed,
    this.enabled = true,
    this.iconTrailing = false,
    this.dimWhenDisabled = true,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final FfTokens tokens;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool iconTrailing;
  final bool dimWhenDisabled;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: tokens.accent.withValues(alpha: 0.45),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          foregroundColor: emphasized ? tokens.inkOnAccent : tokens.text,
          disabledForegroundColor: emphasized
              ? (dimWhenDisabled
                  ? tokens.inkOnAccent.withValues(alpha: 0.55)
                  : tokens.inkOnAccent)
              : (dimWhenDisabled ? tokens.textSecondary : tokens.text),
          backgroundColor: emphasized ? tokens.accent : tokens.surface,
          disabledBackgroundColor: emphasized
              ? (dimWhenDisabled
                  ? tokens.accent.withValues(alpha: 0.45)
                  : tokens.accent)
              : (dimWhenDisabled
                  ? tokens.badgeFill.withValues(alpha: 0.45)
                  : tokens.surface),
          side: BorderSide(
            color: emphasized
                ? (enabled || !dimWhenDisabled
                    ? tokens.text
                    : tokens.text.withValues(alpha: 0.45))
                : (enabled || !dimWhenDisabled
                    ? tokens.divider
                    : tokens.divider.withValues(alpha: .5)),
            width: emphasized ? 1.5 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!iconTrailing) ...[
              Icon(icon, size: 15),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: label.contains('\n') ? 2 : 1,
                  textAlign: TextAlign.center,
                  style: tokens.labelStyle.copyWith(
                    fontSize: 11.5,
                    fontWeight: FfTokens.weightMedium,
                    color: emphasized ? tokens.inkOnAccent : tokens.text,
                    height: 1,
                  ),
                ),
              ),
            ),
            if (iconTrailing) ...[
              const SizedBox(width: 5),
              Icon(icon, size: 15),
            ],
          ],
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

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.label,
    required this.tokens,
    required this.minHeight,
    this.hint,
    this.trailingIcon,
    this.emphasized = false,
    this.enabled = true,
    this.onPressed,
  });

  final String label;
  final FfTokens tokens;
  final double minHeight;
  final String? hint;
  final IconData? trailingIcon;
  final bool emphasized;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        enabled ? tokens.accent : tokens.accent.withValues(alpha: 0.35);
    final textColor = enabled ? tokens.text : tokens.textSecondary;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        type: emphasized ? MaterialType.canvas : MaterialType.transparency,
        color: emphasized ? tokens.badgeFill : null,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
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
                  label,
                  style: tokens.labelStyle.copyWith(color: textColor),
                ),
                if (hint != null) ...[
                  const SizedBox(width: 8),
                  Text(hint!, style: tokens.keyHintStyle),
                ],
                if (trailingIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(trailingIcon, size: 18, color: textColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
