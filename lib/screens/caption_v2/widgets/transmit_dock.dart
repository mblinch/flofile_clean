import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import 'frame_status_dot.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Dark teal fill for caption action chips (Save / Copy / Paste / FTP).
const LinearGradient _kActionTealGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF243848), // top highlight
    Color(0xFF15242E), // mid
    Color(0xFF0E181F), // bottom shade
  ],
  stops: [0.0, 0.45, 1.0],
);

/// Outer height of Save / Copy / FTP. Inner chips sit inside a 2px shell.
const double _kActionRowHeight = 38;
const double _kActionChipHeight = 34;

/// FTP stays content-sized up to this width as the window grows.
const double _kFtpButtonMaxWidth = 280;

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
    this.hideOrangeActions = false,
    this.onFtpHistory,
    this.onFtpProgress,
    this.ftpProgress,
    this.ftpActive = false,
    this.ftpThumbPath,
    this.ftpQueued = 0,
    this.ftpBatchIndex = 0,
    this.ftpBatchTotal = 0,
    this.onFtpCancel,
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

  /// Firebar is open, so Save & Next and FTP stay off this row.
  final bool hideOrangeActions;
  final VoidCallback? onFtpHistory;

  /// Opens the live list of files on the wire and waiting behind them.
  final VoidCallback? onFtpProgress;

  /// 0.0–1.0 while an upload is running. Shown to the right of the FTP button.
  final double? ftpProgress;
  final bool ftpActive;

  /// File currently uploading. The bar keeps the last path after it finishes.
  final String? ftpThumbPath;

  /// Photos waiting behind the one currently uploading.
  final int ftpQueued;

  /// 1-based place of the file on the wire, and the batch size.
  final int ftpBatchIndex;
  final int ftpBatchTotal;
  final VoidCallback? onFtpCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width <= 1060;
        final narrow = width <= 640;
        final pad = compact ? 12.0 : 16.0;
        final prev = _NavButton(
          label: 'Save & Prev',
          tooltip: 'Save & Prev',
          icon: PhosphorIconsRegular.caretLeft,
          iconAtEnd: false,
          padding: EdgeInsets.symmetric(horizontal: pad),
          leadingPad: compact ? pad : 12,
          onPressed: onSavePrevious,
        );
        final clip = _ClipGroup(
          compact: compact,
          onCopy: onCopy,
          onPaste: onPaste,
          onPasteLast: onPastePrevious,
          pasteEnabled: pasteEnabled,
        );
        final next = hideOrangeActions
            ? null
            : _NavButton(
          label: 'Save & Next',
          tooltip: 'Save & Next',
          icon: PhosphorIconsRegular.caretRight,
          enabled: saveNextEnabled,
          padding: EdgeInsets.symmetric(horizontal: pad),
          trailingPad: compact ? pad : 12,
          onPressed: onSaveNext,
        );
        final ftp = showTransmit && !hideOrangeActions
            ? _FtpGroup(
                narrow: narrow,
                label: transmitLabel,
                enabled: transmitEnabled,
                onTransmit: onTransmit,
                onHistory: ftpActive ? null : onFtpHistory,
              )
            : null;

        final openActive = ftpActive ? onFtpProgress : null;
        final progress = showTransmit
            ? _FtpProgressTrack(
                active: ftpActive,
                progress: ftpProgress,
                queued: ftpQueued,
                batchIndex: ftpBatchIndex,
                batchTotal: ftpBatchTotal,
                onTap: openActive,
              )
            : null;
        final bar = narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      prev,
                      clip,
                      if (next != null) next,
                      if (ftp != null) ftp,
                      if (ftpActive &&
                          ftpThumbPath != null &&
                          ftpThumbPath!.trim().isNotEmpty)
                        _FtpUploadPreview(
                          path: ftpThumbPath!.trim(),
                          onTap: openActive,
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    progress,
                  ],
                ],
              )
            : Row(
                children: [
                  prev,
                  const SizedBox(width: 8),
                  clip,
                  if (next != null) ...[
                    const SizedBox(width: 8),
                    next,
                  ],
                  if (ftp != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, slot) {
                          final thumb = ftpActive &&
                              ftpThumbPath != null &&
                              ftpThumbPath!.trim().isNotEmpty;
                          // The profile name gives up space first. The photo
                          // drops next so Sending and the thumbnail never
                          // paint on top of the button.
                          final showThumb = thumb && slot.maxWidth >= 168;
                          return Row(
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: _FtpGroup(
                                  narrow: true,
                                  label: transmitLabel,
                                  enabled: transmitEnabled,
                                  onTransmit: onTransmit,
                                  onHistory: ftpActive ? null : onFtpHistory,
                                ),
                              ),
                              if (showThumb) ...[
                                const SizedBox(width: 8),
                                _FtpUploadPreview(
                                  path: ftpThumbPath!.trim(),
                                  onTap: openActive,
                                ),
                              ],
                              if (ftpActive && progress != null) ...[
                                const SizedBox(width: 8),
                                Flexible(child: progress),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ] else if (ftpActive && progress != null) ...[
                    const SizedBox(width: 8),
                    Expanded(child: progress),
                  ],
                ],
              );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FfTokens.nocturneEl,
            borderRadius: BorderRadius.circular(14),
          ),
          child: bar,
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.padding,
    this.shortcut,
    this.iconAtEnd = true,
    this.filled = false,
    this.fire = false,
    this.enabled = true,
    this.leadingPad,
    this.trailingPad,
  });

  final String label;
  final String? shortcut;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final bool iconAtEnd;
  final bool filled;
  final bool fire;
  final bool enabled;
  final double? leadingPad;
  final double? trailingPad;

  @override
  Widget build(BuildContext context) {
    final resolved = padding.copyWith(
      left: leadingPad ?? padding.left,
      right: trailingPad ?? padding.right,
    );
    return _BarTap(
      tooltip: tooltip,
      enabled: enabled && onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final bg = fire
            ? (hovered ? const Color(0xFFFF7340) : FfTokens.firebar)
            : filled
                ? (hovered ? FfTokens.accentHover : FfTokens.nocturneAc)
                : (hovered ? FfTokens.nocturneHv : FfTokens.nocturneSunken);
        final fg = fire
            ? Colors.white
            : filled
                ? FfTokens.nocturneBg
                : FfTokens.nocturneTx;
        return _BarShell(
          height: _kActionRowHeight,
          padding: resolved,
          background: bg,
          pressed: pressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconAtEnd) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(label, style: _barLabel(fg)),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                Text(shortcut!, style: _shortcutStyle(fg)),
              ],
              if (iconAtEnd) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: fg),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ClipGroup extends StatelessWidget {
  const _ClipGroup({
    required this.compact,
    required this.onCopy,
    required this.onPaste,
    required this.onPasteLast,
    required this.pasteEnabled,
  });

  final bool compact;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPasteLast;
  final bool pasteEnabled;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 10.0 : 12.0;
    final gap = compact ? 6.0 : 8.0;
    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      required bool enabled,
    }) {
      return _BarTap(
        tooltip: label,
        enabled: enabled && onPressed != null,
        onTap: onPressed,
        builder: (hovered, pressed) {
          final fg = hovered ? FfTokens.nocturneTx : FfTokens.nocturneT2;
          final iconColor = hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3;
          return _BarShell(
            height: _kActionChipHeight,
            padding: EdgeInsets.symmetric(horizontal: pad),
            background: hovered ? FfTokens.nocturneHv : Colors.transparent,
            pressed: pressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: iconColor),
                SizedBox(width: gap),
                Text(
                  label,
                  style: _barLabel(fg, weight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FfTokens.nocturneBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(
            icon: PhosphorIconsRegular.copy,
            label: 'Copy',
            onPressed: onCopy,
            enabled: true,
          ),
          const SizedBox(width: 2),
          item(
            icon: PhosphorIconsRegular.clipboardText,
            label: 'Paste',
            onPressed: onPaste,
            enabled: pasteEnabled,
          ),
          const SizedBox(width: 2),
          item(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            label: 'Paste last',
            onPressed: onPasteLast,
            enabled: true,
          ),
        ],
      ),
    );
  }
}

class _FtpGroup extends StatelessWidget {
  const _FtpGroup({
    required this.narrow,
    required this.label,
    required this.enabled,
    required this.onTransmit,
    this.onHistory,
  });

  final bool narrow;
  final String label;
  final bool enabled;
  final VoidCallback? onTransmit;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final send = _FtpSendButton(
      label: label,
      enabled: enabled,
      expand: narrow,
      onPressed: onTransmit,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kFtpButtonMaxWidth),
      child: Row(
      mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (narrow) Expanded(child: send) else send,
        if (onHistory != null) ...[
          const SizedBox(width: 8),
          _BarTap(
            tooltip: 'FTP history',
            enabled: true,
            onTap: onHistory,
            builder: (hovered, pressed) {
              final color =
                  hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3;
              return _BarShell(
                height: _kActionRowHeight,
                width: _kActionRowHeight,
                padding: EdgeInsets.zero,
                background:
                    hovered ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
                pressed: pressed,
                child: Icon(
                  PhosphorIconsRegular.clockCounterClockwise,
                  size: 18,
                  color: color,
                ),
              );
            },
          ),
        ],
      ],
      ),
    );
  }
}

class _FtpUploadPreview extends StatelessWidget {
  const _FtpUploadPreview({required this.path, this.onTap});

  final String path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _kActionChipHeight,
        height: _kActionChipHeight,
        child: OrientedFilePreview(
          path: path,
          fit: BoxFit.cover,
          cacheWidth: 120,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
    if (onTap == null) return thumb;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: thumb),
    );
  }
}

class _FtpProgressTrack extends StatelessWidget {
  const _FtpProgressTrack({
    required this.active,
    required this.queued,
    this.progress,
    this.batchIndex = 0,
    this.batchTotal = 0,
    this.onTap,
  });

  final bool active;
  final double? progress;
  final int queued;
  final int batchIndex;
  final int batchTotal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox(height: _kActionChipHeight);
    final value = (progress ?? 0).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()}%';
    final showQueue = queued > 0 && batchTotal > 1 && batchIndex > 0;
    const sendingStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: FfTokens.nocturneT2,
      height: 1,
    );
    const percentStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: FfTokens.nocturneTx,
      height: 1,
    );
    final status = SizedBox(
      height: _kActionChipHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Sending', style: sendingStyle),
                  const TextSpan(text: '  '),
                  TextSpan(text: percent, style: percentStyle),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showQueue) ...[
              const SizedBox(height: 3),
              Text(
                'Picture $batchIndex of $batchTotal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: FfTokens.nocturneT3,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return status;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: status),
    );
  }
}

class _FtpSendButton extends StatelessWidget {
  const _FtpSendButton({
    required this.label,
    required this.enabled,
    required this.expand,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool expand;
  final VoidCallback? onPressed;

  String get _destination {
    final trimmed = label.trim();
    final lower = trimmed.toLowerCase();
    if (lower == 'ftp') return '';
    if (lower.startsWith('ftp:')) return trimmed.substring(4).trim();
    if (lower.startsWith('ftp ')) return trimmed.substring(4).trim();
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && onPressed != null;
    final status = _destination;

    return _BarTap(
      tooltip: 'FTP · $label',
      enabled: canSend,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final fg = FfTokens.nocturneTx;
        return _BarShell(
          height: _kActionRowHeight,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          background: hovered ? FfTokens.nocturneHv : FfTokens.nocturneSunken,
          pressed: pressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIconsRegular.cloudArrowUp,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text('FTP', style: _barLabel(fg)),
              if (status.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _barLabel(fg),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

TextStyle _shortcutStyle(Color color) {
  return TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: color.withValues(alpha: 0.9),
    height: 1,
  );
}

class _BarTap extends StatefulWidget {
  const _BarTap({
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.builder,
    this.dimWhenDisabled = true,
  });

  final String tooltip;
  final bool enabled;
  final bool dimWhenDisabled;
  final VoidCallback? onTap;
  final Widget Function(bool hovered, bool pressed) builder;

  @override
  State<_BarTap> createState() => _BarTapState();
}

class _BarTapState extends State<_BarTap> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Tooltip(
      message: widget.tooltip,
      child: Opacity(
        opacity: enabled || !widget.dimWhenDisabled ? 1 : 0.4,
        child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onTap : null,
          child: widget.builder(enabled && _hovered, enabled && _pressed),
        ),
      ),
      ),
    );
  }
}

class _BarShell extends StatelessWidget {
  const _BarShell({
    required this.height,
    required this.padding,
    required this.background,
    required this.pressed,
    required this.child,
    this.width,
    this.outline,
    this.nudge = true,
  });

  final double height;
  final double? width;
  final EdgeInsets padding;
  final Color background;
  final bool pressed;
  final Widget child;
  final Color? outline;
  final bool nudge;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, pressed && nudge ? 1 : 0, 0),
      height: height,
      width: width,
      padding: padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: outline == null ? null : Border.all(color: outline!),
      ),
      child: child,
    );
  }
}

TextStyle _barLabel(Color color, {FontWeight weight = FontWeight.w600}) {
  return TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: 12,
    fontWeight: weight,
    color: color,
    height: 1,
  );
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
              thumbColor: const WidgetStatePropertyAll(Colors.white),
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
            hint: isMobile ? null : '⇧↵',
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
  bool _pressed = false;

  static List<Shadow> _textGlow(Color color) => [
        Shadow(color: color.withValues(alpha: 0.95), blurRadius: 2),
        Shadow(color: color.withValues(alpha: 0.75), blurRadius: 6),
        Shadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
        Shadow(color: color.withValues(alpha: 0.22), blurRadius: 18),
      ];

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final primary = widget.primary;
    final enabled = widget.enabled;
    final dimWhenDisabled = widget.dimWhenDisabled;
    final hovering = enabled && _hovered;
    final pressing = enabled && _pressed;

    // Teal gradient fill for the caption action row; hover brightens the rim.
    final fg =
        Colors.white.withValues(alpha: enabled || !dimWhenDisabled ? 1 : 0.55);
    final border = hovering || primary
        ? Colors.white.withValues(alpha: 0.92)
        : tokens.accent
            .withValues(alpha: enabled || !dimWhenDisabled ? 0.95 : 0.4);
    final glowColor = hovering || primary ? Colors.white : tokens.accent;
    final gradient = pressing
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A2A36),
              Color(0xFF0C141A),
              Color(0xFF080E12),
            ],
            stops: [0.0, 0.45, 1.0],
          )
        : hovering
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2E4658),
                  Color(0xFF1A2E3A),
                  Color(0xFF121F28),
                ],
                stops: [0.0, 0.45, 1.0],
              )
            : _kActionTealGradient;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled
          ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
          : null,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: enabled || !dimWhenDisabled ? 1 : 0.55,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: gradient,
              border: Border.all(color: border),
              boxShadow: enabled ? FfTokens.accentButtonGlow(glowColor) : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: Alignment.center,
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
                      shadows: enabled ? _textGlow(glowColor) : null,
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
                      color: Colors.white.withValues(alpha: 0.85),
                      shadows: enabled ? _textGlow(glowColor) : null,
                    ),
                  ),
                ],
              ],
            ),
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
            ? (hovering ? Colors.white.withValues(alpha: 0.92) : tokens.accent)
            : tokens.accent.withValues(alpha: 0.35));
    final textColor = emphasized
        ? (enabled ? Colors.white : Colors.white.withValues(alpha: 0.45))
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
