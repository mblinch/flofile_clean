import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/burst_groups.dart';
import 'frame_status_dot.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Primary Save & next fill (Nocturne action bar).
const LinearGradient _kActionTealGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF243848),
    Color(0xFF15242E),
    Color(0xFF0E181F),
  ],
  stops: [0.0, 0.55, 1.0],
);

const LinearGradient _kActionTealGradientHover = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF2E4658),
    Color(0xFF1A2E3A),
    Color(0xFF121F28),
  ],
  stops: [0.0, 0.55, 1.0],
);

const LinearGradient _kActionTealGradientPressed = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF1A2A36),
    Color(0xFF0C141A),
    Color(0xFF080E12),
  ],
  stops: [0.0, 0.55, 1.0],
);

/// Match Firebar outer bar (minHeight 34 in caption_v2_search.dart).
/// Grouped clip chips sit inside a 2px shell → 30 so the group is also 34.
const double _kActionRowHeight = 34;
const double _kActionChipHeight = 30;

const Color _kActionSecondaryBg = Color(0xFF1E242A);
const Color _kActionHairline = Color(0x1EE8EEF4); // rgba(232,238,244,.12)
const Color _kActionPressedBg = Color(0xFF20313C);
const Color _kActionPressedEdge = Color(0xFF3A6076);
const Color _kActionPrimaryEdge = Color(0xF24A7A96); // rgba(74,122,150,.95)
const Color _kActionPrimaryEdgeHover = Color(0xD9E8EEF4); // rgba(232,238,244,.85)

String get _modKey =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';

String get _saveNextShortcut => '$_modKey ↵';
String get _savePrevShortcut => '$_modKey ⇧ ↵';
String get _saveToBurstShortcut => '$_modKey B';
String get _pasteLastShortcut => '$_modKey ⇧ V';
String get _ftpShortcut => '$_modKey U';

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
    this.burstPaths = const [],
    this.onSaveToBurst,
    this.onFtpHistory,
    this.onFtpProgress,
    this.ftpProgress,
    this.ftpActive = false,
    this.ftpThumbPath,
    this.ftpQueued = 0,
    this.ftpBatchIndex = 0,
    this.ftpBatchTotal = 0,
    this.onFtpCancel,
    this.singleRow = false,
    this.mobileDock = false,
    this.onThumbs,
    this.thumbsSelected = false,
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

  /// Forward burst chain from the current photo (first path = current). When
  /// length > 1 and [onSaveToBurst] is set, shows Save to burst left of Save & next.
  final List<String> burstPaths;

  /// [selected] frames to write; [chain] is the full burst shown in the popover
  /// (used to land on the first deselected frame after save).
  final void Function(List<String> selected, List<String> chain)? onSaveToBurst;
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

  /// Keep save / copy / paste / next on one horizontal row (mobile).
  final bool singleRow;

  /// Mobile captioning mock: 56px Prev/Next squares + icon-over-label mid.
  final bool mobileDock;

  /// Optional filmstrip toggle (mobile).
  final VoidCallback? onThumbs;
  final bool thumbsSelected;

  @override
  Widget build(BuildContext context) {
    if (mobileDock) {
      return _MobileDockBar(
        onSavePrevious: onSavePrevious,
        onCopy: onCopy,
        onPaste: onPaste,
        onPastePrevious: onPastePrevious,
        pasteEnabled: pasteEnabled,
        onSaveNext: onSaveNext,
        saveNextEnabled: saveNextEnabled,
        onThumbs: onThumbs,
        thumbsSelected: thumbsSelected,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showBurst = !hideOrangeActions &&
            burstPaths.length > 1 &&
            onSaveToBurst != null;
        // Burst adds another chip; tighten earlier so Copy/Paste don't overflow.
        final compact = singleRow || width <= 1060 || (showBurst && width <= 1320);
        // Stay on one horizontal line always — never Wrap/stack when the
        // photo pane takes width. Compact earlier instead.
        final tight = !singleRow &&
            (width <= 720 ||
                (showTransmit && !hideOrangeActions && width <= 900) ||
                (showBurst && width <= 1000));
        final clipIconOnly =
            singleRow || tight || (showBurst && width <= 1180);
        final pad = singleRow || tight ? 8.0 : 13.0;
        final showShortcuts = !tight;
        final prev = _NavButton(
          label: 'Save',
          tooltip: 'Save & Prev',
          icon: PhosphorIconsRegular.caretLeft,
          iconAtEnd: false,
          shortcut: showShortcuts ? _savePrevShortcut : null,
          padding: EdgeInsets.symmetric(horizontal: pad),
          onPressed: onSavePrevious,
        );
        final clip = _ClipGroup(
          compact: compact || tight,
          iconOnly: clipIconOnly,
          onCopy: onCopy,
          onPaste: onPaste,
          onPasteLast: onPastePrevious,
          pasteEnabled: pasteEnabled,
          pasteLastShortcut: showShortcuts ? _pasteLastShortcut : null,
        );
        final next = hideOrangeActions
            ? null
            : _NavButton(
                label: 'Save',
                tooltip: 'Save & Next',
                icon: PhosphorIconsRegular.caretRight,
                enabled: saveNextEnabled,
                primary: true,
                shortcut: showShortcuts ? _saveNextShortcut : null,
                padding: EdgeInsets.symmetric(horizontal: tight ? 10 : 16),
                onPressed: onSaveNext,
              );
        final burst = showBurst
            ? _SaveToBurstButton(
                paths: burstPaths,
                shortcut: showShortcuts ? _saveToBurstShortcut : null,
                onSave: (selected) => onSaveToBurst!(selected, burstPaths),
              )
            : null;
        final thumbs = onThumbs == null
            ? null
            : _ThumbsButton(
                selected: thumbsSelected,
                onPressed: onThumbs,
              );

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
        // Always one horizontal line. Scale the chip cluster down when the
        // caption column shrinks (photo pane dragged wider) instead of wrapping.
        final bar = Row(
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (thumbs != null) ...[
                      thumbs,
                      const SizedBox(width: 8),
                    ],
                    prev,
                    const SizedBox(width: 8),
                    clip,
                    if (next != null) ...[
                      const SizedBox(width: 8),
                      next,
                    ],
                    if (burst != null) ...[
                      const SizedBox(width: 8),
                      burst,
                    ],
                    if (showTransmit && !hideOrangeActions) ...[
                      const SizedBox(width: 8),
                      _FtpGroup(
                        narrow: false,
                        label: transmitLabel,
                        enabled: transmitEnabled,
                        onTransmit: onTransmit,
                        onHistory: ftpActive ? null : onFtpHistory,
                        shortcut: showShortcuts && width >= 860
                            ? _ftpShortcut
                            : null,
                      ),
                    ],
                    if (!singleRow &&
                        ftpActive &&
                        ftpThumbPath != null &&
                        ftpThumbPath!.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _FtpUploadPreview(
                        path: ftpThumbPath!.trim(),
                        onTap: openActive,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!singleRow && ftpActive && progress != null) ...[
              const SizedBox(width: 8),
              Flexible(child: progress),
            ],
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(singleRow ? 6 : 8),
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

class _ThumbsButton extends StatelessWidget {
  const _ThumbsButton({
    required this.onPressed,
    required this.selected,
  });

  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return _BarTap(
      tooltip: selected ? 'Hide thumbs' : 'Show thumbs',
      semanticLabel: 'Thumbnails',
      enabled: onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final bg = selected
            ? (hovered ? FfTokens.accentHover : FfTokens.nocturneAc)
            : (hovered ? FfTokens.nocturneHv : FfTokens.nocturneSunken);
        final fg = selected ? FfTokens.nocturneBg : FfTokens.nocturneTx;
        return _BarShell(
          height: _kActionRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          background: bg,
          pressed: pressed,
          child: Icon(
            PhosphorIconsRegular.images,
            size: 18,
            color: fg,
          ),
        );
      },
    );
  }
}

/// Mobile mock action bar — same callbacks as [CaptionV2ActionRow].
class _MobileDockBar extends StatelessWidget {
  const _MobileDockBar({
    required this.onSavePrevious,
    required this.onCopy,
    required this.onPaste,
    required this.onPastePrevious,
    required this.pasteEnabled,
    required this.onSaveNext,
    required this.saveNextEnabled,
    this.onThumbs,
    this.thumbsSelected = false,
  });

  final VoidCallback? onSavePrevious;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPastePrevious;
  final bool pasteEnabled;
  final VoidCallback? onSaveNext;
  final bool saveNextEnabled;
  final VoidCallback? onThumbs;
  final bool thumbsSelected;

  static const _on = Color(0xFF7FB3E8);

  @override
  Widget build(BuildContext context) {
    Widget nav({
      required IconData icon,
      required String tip,
      required VoidCallback? onTap,
      required bool filled,
      required bool enabled,
    }) {
      return _BarTap(
        tooltip: tip,
        enabled: enabled && onTap != null,
        onTap: onTap,
        builder: (hovered, pressed) {
          final bg = filled
              ? (hovered ? const Color(0xFF95C0EC) : _on)
              : (hovered ? FfTokens.nocturneHv : FfTokens.nocturneEl);
          final fg = filled ? const Color(0xFF0C1016) : FfTokens.nocturneTx;
          return Container(
            width: 56,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: fg),
          );
        },
      );
    }

    Widget mid({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      required bool enabled,
    }) {
      return Expanded(
        child: _BarTap(
          tooltip: label,
          enabled: enabled && onTap != null,
          onTap: onTap,
          builder: (hovered, pressed) {
            return SizedBox(
              height: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hovered ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (onThumbs != null) ...[
            _ThumbsButton(onPressed: onThumbs, selected: thumbsSelected),
            const SizedBox(width: 6),
          ],
          nav(
            icon: PhosphorIconsBold.caretLeft,
            tip: 'Save & Prev',
            onTap: onSavePrevious,
            filled: false,
            enabled: true,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: FfTokens.nocturneBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  mid(
                    icon: PhosphorIconsRegular.copy,
                    label: 'Copy',
                    onTap: onCopy,
                    enabled: true,
                  ),
                  mid(
                    icon: PhosphorIconsRegular.clipboardText,
                    label: 'Paste',
                    onTap: onPaste,
                    enabled: pasteEnabled,
                  ),
                  mid(
                    icon: PhosphorIconsRegular.clockCounterClockwise,
                    label: 'Last',
                    onTap: onPastePrevious,
                    enabled: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          nav(
            icon: PhosphorIconsBold.caretRight,
            tip: 'Save & Next',
            onTap: onSaveNext,
            filled: true,
            enabled: saveNextEnabled,
          ),
        ],
      ),
    );
  }
}

/// Save to burst — gold-bordered button + filmstrip popover (hover/click).
class _SaveToBurstButton extends StatefulWidget {
  const _SaveToBurstButton({
    required this.paths,
    required this.onSave,
    this.shortcut,
  });

  /// Coherent burst with current first (Original); remaining frames — including
  /// those before current in capture order — are optional extras.
  final List<String> paths;
  final ValueChanged<List<String>> onSave;
  final String? shortcut;

  @override
  State<_SaveToBurstButton> createState() => _SaveToBurstButtonState();
}

class _SaveToBurstButtonState extends State<_SaveToBurstButton> {
  static const _gold = Color(0xFFE8C547);
  static const _goldEdge = Color(0x8CE8C547); // rgba(232,197,71,.55)
  static const _goldInk = Color(0xFF1A1606);

  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode(debugLabel: 'SaveToBurst');

  late Set<String> _checked;

  @override
  void initState() {
    super.initState();
    _checked = _defaultChecked();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(covariant _SaveToBurstButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths)) {
      _checked = _defaultChecked();
      _close();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.dispose();
    if (_portal.isShowing) _portal.hide();
    super.dispose();
  }

  /// Every non-Original frame (earlier and later) starts checked.
  Set<String> _defaultChecked() => defaultCheckedBurstExtras(widget.paths);

  int get _count => _checked.length;

  /// Current frame is always included; extras are optional (hold-burst parity).
  bool get _canSave => widget.paths.isNotEmpty;

  /// Total frames that will be written (current + checked extras).
  int get _saveTotal => widget.paths.isEmpty
      ? 0
      : resolveBurstSaveTargets(
          dockPaths: widget.paths,
          checkedExtras: _checked,
        ).length;

  bool _onKey(KeyEvent event) {
    if (!_portal.isShowing) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    _close();
    return true;
  }

  void _open() {
    if (!_portal.isShowing) {
      _portal.show();
      _focus.requestFocus();
    }
    // Defer rebuild so OverlayPortal show + setState don't race layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleOpen() {
    if (_portal.isShowing) {
      _close();
    } else {
      _open();
    }
  }

  void _toggle(String path) {
    setState(() {
      if (_checked.contains(path)) {
        _checked.remove(path);
      } else {
        _checked.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() => _checked = _defaultChecked());
  }

  void _selectNone() {
    setState(() => _checked = <String>{});
  }

  void _commit() {
    if (!_canSave || widget.paths.isEmpty) return;
    final paths = resolveBurstSaveTargets(
      dockPaths: widget.paths,
      checkedExtras: _checked,
    );
    _close();
    widget.onSave(paths);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: Focus(
                focusNode: _focus,
                child: _BurstFilmstripPopover(
                  paths: widget.paths,
                  checked: _checked,
                  canSave: _canSave,
                  saveCount: _saveTotal,
                  onToggle: _toggle,
                  onAll: _selectAll,
                  onNone: _selectNone,
                  onSave: _commit,
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Opacity(
          opacity: _canSave ? 1 : 0.5,
          child: _BarTap(
            tooltip: _canSave
                ? 'Choose burst frames to save'
                    '${widget.shortcut == null ? '' : '  ·  ${widget.shortcut}'}'
                : 'Select burst frames to save',
            enabled: true,
            dimWhenDisabled: false,
            onTap: _toggleOpen,
            builder: (hovered, pressed) {
              final bg = pressed || hovered
                  ? FfTokens.nocturneHv
                  : _kActionSecondaryBg;
              // No LayoutBuilder here — OverlayPortal + hover setState
              // otherwise hits debugNeedsLayout asserts (red flashes).
              return _BarShell(
                height: _kActionRowHeight,
                padding: const EdgeInsets.fromLTRB(8, 0, 5, 0),
                background: bg,
                outline: _goldEdge,
                radius: 9,
                pressed: pressed,
                nudge: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      PhosphorIconsFill.lightning,
                      size: 13,
                      color: _gold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Save to Burst',
                      style: _barLabel(FfTokens.nocturneTx),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$_count',
                        style: const TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: _goldInk,
                        ),
                      ),
                    ),
                    if (widget.shortcut != null) ...[
                      const SizedBox(width: 6),
                      _ShortcutBadge(widget.shortcut!),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BurstFilmstripPopover extends StatelessWidget {
  const _BurstFilmstripPopover({
    required this.paths,
    required this.checked,
    required this.canSave,
    required this.saveCount,
    required this.onToggle,
    required this.onAll,
    required this.onNone,
    required this.onSave,
  });

  final List<String> paths;
  final Set<String> checked;
  final bool canSave;
  final int saveCount;
  final ValueChanged<String> onToggle;
  final VoidCallback onAll;
  final VoidCallback onNone;
  final VoidCallback onSave;

  static const _gold = Color(0xFFE8C547);
  static const _goldInk = Color(0xFF1A1606);

  @override
  Widget build(BuildContext context) {
    final n = paths.length;
    // 180px cells + 4px gaps — at most 6 thumbs visible; longer bursts scroll.
    const cell = 180.0;
    const gap = 4.0;
    const maxVisible = 6;
    const panelPad = 8.0;
    const panelBorder = 1.0; // Border.all on the panel
    final stripNatural =
        n <= 0 ? 0.0 : n * cell + (n - 1) * gap;
    final maxByCount = maxVisible * cell + (maxVisible - 1) * gap;
    final maxByScreen = MediaQuery.sizeOf(context).width - 48;
    final maxStrip = maxByCount < maxByScreen ? maxByCount : maxByScreen;
    final stripWidth =
        stripNatural <= maxStrip ? stripNatural : maxStrip;
    final scroll = stripNatural > stripWidth;
    // Padding + border both inset content; omit either and the strip overflows.
    final panelWidth =
        stripWidth + panelPad * 2 + panelBorder * 2;
    final saveLabel = saveCount <= 0
        ? 'Save'
        : 'Save · $saveCount frame${saveCount == 1 ? '' : 's'}';

    final strip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < paths.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _BurstFrameThumb(
            path: paths[i],
            isCurrent: i == 0,
            selected: i == 0 || checked.contains(paths[i]),
            onTap: i == 0 ? null : () => onToggle(paths[i]),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        padding: const EdgeInsets.all(panelPad),
        decoration: BoxDecoration(
          color: _kActionSecondaryBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kActionHairline, width: panelBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.lightning,
                  size: 12,
                  color: _gold,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Burst · $n frames',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.88,
                      height: 1,
                      color: FfTokens.nocturneT3,
                    ),
                  ),
                ),
                _GhostChip(label: 'All', onTap: onAll),
                const SizedBox(width: 2),
                _GhostChip(label: 'None', onTap: onNone),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: stripWidth,
              child: scroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: strip,
                    )
                  : strip,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                // Overlay-safe: no Tooltip/_BarTap (those assert under OverlayPortal).
                _OverlaySafeTap(
                  enabled: canSave,
                  onTap: onSave,
                  builder: (hovered, pressed) {
                    final bg = !canSave
                        ? const Color(0xFF3A3420)
                        : pressed
                            ? const Color(0xFFC9A93A)
                            : hovered
                                ? const Color(0xFFF0D15C)
                                : _gold;
                    final fg = canSave ? _goldInk : FfTokens.nocturneT3;
                    return _BarShell(
                      height: _kActionRowHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      background: bg,
                      radius: 8,
                      pressed: pressed,
                      nudge: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsFill.lightning,
                            size: 13,
                            color: fg,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            saveLabel,
                            style: _barLabel(fg),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hover tap without Tooltip — safe inside [OverlayPortal] (avoids nested
/// overlay + hover setState `debugNeedsLayout` red flashes).
class _OverlaySafeTap extends StatefulWidget {
  const _OverlaySafeTap({
    required this.enabled,
    required this.onTap,
    required this.builder,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final Widget Function(bool hovered, bool pressed) builder;

  @override
  State<_OverlaySafeTap> createState() => _OverlaySafeTapState();
}

class _OverlaySafeTapState extends State<_OverlaySafeTap> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled
          ? (_) {
              if (!_hovered) setState(() => _hovered = true);
            }
          : null,
      onExit: (_) {
        if (_hovered || _pressed) {
          setState(() {
            _hovered = false;
            _pressed = false;
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: widget.builder(enabled && _hovered, enabled && _pressed),
        ),
      ),
    );
  }
}

class _GhostChip extends StatelessWidget {
  const _GhostChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _OverlaySafeTap(
      enabled: true,
      onTap: onTap,
      builder: (hovered, pressed) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: hovered || pressed
                ? FfTokens.nocturneHv
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
              color: hovered || pressed
                  ? FfTokens.nocturneTx
                  : FfTokens.nocturneT2,
            ),
          ),
        );
      },
    );
  }
}

class _BurstFrameThumb extends StatefulWidget {
  const _BurstFrameThumb({
    required this.path,
    required this.isCurrent,
    required this.selected,
    this.onTap,
  });

  final String path;
  final bool isCurrent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_BurstFrameThumb> createState() => _BurstFrameThumbState();
}

class _BurstFrameThumbState extends State<_BurstFrameThumb> {
  static const _gold = Color(0xFFE8C547);
  static const _goldInk = Color(0xFF1A1606);
  static const _nowMount = Color(0xFF20313C);
  static const _cell = Color(0xFF262D35);
  static const _size = 180.0;
  static const _pad = 12.0;
  static const _loupeSize = 78.0;
  static const _magnification = 2.6;

  Offset? _cursor;
  bool _loupeArmed = false;

  Rect get _imageRect =>
      const Rect.fromLTWH(_pad, _pad, _size - _pad * 2, _size - _pad * 2);

  void _toggleLoupe() {
    setState(() {
      _loupeArmed = !_loupeArmed;
      if (!_loupeArmed) _cursor = null;
    });
  }

  void _setCursor(Offset? pos) {
    // Defer — setState from MouseRegion during overlay/layout rebuilds
    // trips LayoutBuilder ('debugNeedsLayout' asserts / red flashes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pos == null) {
        if (_cursor == null && !_loupeArmed) return;
        setState(() {
          _cursor = null;
          _loupeArmed = false;
        });
        return;
      }
      if (_cursor == pos) return;
      setState(() => _cursor = pos);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.isCurrent;
    final selected = widget.selected;
    final borderColor = isCurrent
        ? FfTokens.nocturneAc
        : selected
            ? _gold
            : const Color(0x0FE8EEF4);
    final borderWidth = isCurrent || selected ? 1.5 : 1.0;
    Widget thumb = OrientedFilePreview(
      path: widget.path,
      fit: BoxFit.contain,
      cacheWidth: 400,
      filterQuality: FilterQuality.medium,
    );
    if (!isCurrent && !selected) {
      thumb = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          // Approx grayscale(.6) — HTML unchecked state
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: Opacity(opacity: 0.35, child: thumb),
      );
    }

    final imageRect = _imageRect;
    final cursor = _cursor;
    final overImage =
        _loupeArmed && cursor != null && imageRect.contains(cursor);
    final sampleAt = overImage
        ? Offset(
            cursor.dx.clamp(imageRect.left, imageRect.right),
            cursor.dy.clamp(imageRect.top, imageRect.bottom),
          )
        : null;

    final cell = SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isCurrent ? _nowMount : _cell,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(_pad),
                    child: thumb,
                  ),
                  if (isCurrent)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: FfTokens.nocturneAc,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'Original',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.54,
                            height: 1.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? _gold : const Color(0xFF181D22),
                          borderRadius: BorderRadius.circular(4),
                          border: selected
                              ? null
                              : Border.all(color: const Color(0x40E8EEF4)),
                        ),
                        child: selected
                            ? const Icon(
                                PhosphorIconsBold.check,
                                size: 10,
                                color: _goldInk,
                              )
                            : null,
                      ),
                    ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleLoupe,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _loupeArmed
                                ? FfTokens.nocturneAc
                                : const Color(0xCC181D22),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _loupeArmed
                                  ? FfTokens.nocturneAc
                                  : const Color(0x40E8EEF4),
                            ),
                          ),
                          child: Icon(
                            PhosphorIconsRegular.magnifyingGlass,
                            size: 11,
                            color: _loupeArmed
                                ? Colors.white
                                : FfTokens.nocturneT2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (sampleAt != null) _buildLoupe(sampleAt, imageRect),
        ],
      ),
    );

    return MouseRegion(
      cursor: _loupeArmed
          ? SystemMouseCursors.zoomIn
          : (widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic),
      onHover: _loupeArmed
          ? (event) => _setCursor(event.localPosition)
          : null,
      onExit: (_) => _setCursor(null),
      child: widget.onTap == null
          ? cell
          : GestureDetector(onTap: widget.onTap, child: cell),
    );
  }

  Widget _buildLoupe(Offset sampleAt, Rect imageRect) {
    const loupe = _loupeSize;
    const mag = _magnification;
    final maxLeft = (_size - loupe - 2).clamp(2.0, double.infinity);
    final maxTop = (_size - loupe - 2).clamp(2.0, double.infinity);
    final left = (sampleAt.dx - loupe / 2).clamp(2.0, maxLeft);
    final top = (sampleAt.dy - loupe / 2).clamp(2.0, maxTop);
    final localX = sampleAt.dx - imageRect.left;
    final localY = sampleAt.dy - imageRect.top;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: loupe,
          height: loupe,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.92),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: ColoredBox(
              color: _cell,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: loupe / 2 - localX * mag,
                    top: loupe / 2 - localY * mag,
                    width: imageRect.width * mag,
                    height: imageRect.height * mag,
                    child: OrientedFilePreview(
                      path: widget.path,
                      fit: BoxFit.fill,
                      cacheWidth: 720,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final String? shortcut;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final bool iconAtEnd;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _BarTap(
      tooltip: tooltip,
      enabled: enabled && onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        if (primary) {
          final gradient = pressed
              ? _kActionTealGradientPressed
              : hovered
                  ? _kActionTealGradientHover
                  : _kActionTealGradient;
          final border = hovered || pressed
              ? _kActionPrimaryEdgeHover
              : _kActionPrimaryEdge;
          return _BarShell(
            height: _kActionRowHeight,
            padding: padding,
            gradient: gradient,
            outline: border,
            radius: 9,
            pressed: pressed,
            nudge: false,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: _barLabel(Colors.white)),
                if (iconAtEnd) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 16, color: Colors.white),
                ],
                if (shortcut != null) ...[
                  const SizedBox(width: 8),
                  _ShortcutBadge(shortcut!, onPrimary: true),
                ],
              ],
            ),
          );
        }

        final bg = pressed
            ? _kActionPressedBg
            : hovered
                ? FfTokens.nocturneHv
                : _kActionSecondaryBg;
        final edge = pressed ? _kActionPressedEdge : _kActionHairline;
        const iconColor = FfTokens.nocturneT2;
        return _BarShell(
          height: _kActionRowHeight,
          padding: padding,
          background: bg,
          outline: edge,
          radius: 9,
          pressed: pressed,
          nudge: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconAtEnd) ...[
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 7),
              ],
              Text(label, style: _barLabel(FfTokens.nocturneTx)),
              if (shortcut != null) ...[
                const SizedBox(width: 7),
                _ShortcutBadge(shortcut!),
              ],
              if (iconAtEnd) ...[
                const SizedBox(width: 7),
                Icon(icon, size: 16, color: iconColor),
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
    this.iconOnly = false,
    this.pasteLastShortcut,
  });

  final bool compact;
  final bool iconOnly;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPasteLast;
  final bool pasteEnabled;
  final String? pasteLastShortcut;

  @override
  Widget build(BuildContext context) {
    final pad = iconOnly ? 8.0 : 11.0;
    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      required bool enabled,
      String? shortcut,
    }) {
      final tip = shortcut == null ? label : '$label  ·  $shortcut';
      return _BarTap(
        tooltip: tip,
        enabled: enabled && onPressed != null,
        onTap: onPressed,
        builder: (hovered, pressed) {
          return _BarShell(
            height: _kActionChipHeight,
            padding: EdgeInsets.symmetric(horizontal: pad),
            background:
                hovered || pressed ? FfTokens.nocturneHv : Colors.transparent,
            radius: 7,
            pressed: pressed,
            nudge: false,
            child: iconOnly
                ? Icon(icon, size: 16, color: FfTokens.nocturneT2)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: FfTokens.nocturneT2),
                      const SizedBox(width: 6),
                      Text(label, style: _barLabel(FfTokens.nocturneTx)),
                      if (shortcut != null) ...[
                        const SizedBox(width: 6),
                        _ShortcutBadge(shortcut),
                      ],
                    ],
                  ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _kActionSecondaryBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kActionHairline),
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
          item(
            icon: PhosphorIconsRegular.clipboardText,
            label: 'Paste',
            onPressed: onPaste,
            enabled: pasteEnabled,
          ),
          item(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            label: 'Paste last',
            onPressed: onPasteLast,
            enabled: true,
            shortcut: pasteLastShortcut,
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
    this.shortcut,
  });

  final bool narrow;
  final String label;
  final bool enabled;
  final VoidCallback? onTransmit;
  final VoidCallback? onHistory;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final send = _FtpSendButton(
      label: label,
      enabled: enabled,
      expand: narrow,
      onPressed: onTransmit,
      shortcut: shortcut,
    );
    return Row(
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
              final bg = pressed
                  ? _kActionPressedBg
                  : hovered
                      ? FfTokens.nocturneHv
                      : _kActionSecondaryBg;
              final edge = pressed ? _kActionPressedEdge : _kActionHairline;
              final color =
                  hovered ? FfTokens.nocturneTx : FfTokens.nocturneT2;
              return _BarShell(
                height: _kActionRowHeight,
                width: _kActionRowHeight,
                padding: EdgeInsets.zero,
                background: bg,
                outline: edge,
                radius: 9,
                pressed: pressed,
                nudge: false,
                child: Icon(
                  PhosphorIconsRegular.clockClockwise,
                  size: 16,
                  color: color,
                ),
              );
            },
          ),
        ],
      ],
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
    this.shortcut,
  });

  final String label;
  final bool enabled;
  final bool expand;
  final VoidCallback? onPressed;
  final String? shortcut;

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
    final display = status.isEmpty ? 'FTP' : label;
    final tip = shortcut == null ? 'FTP · $label' : 'FTP · $shortcut';

    return _BarTap(
      tooltip: tip,
      semanticLabel: 'FTP',
      enabled: canSend,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final bg = pressed
            ? _kActionPressedBg
            : hovered
                ? FfTokens.nocturneHv
                : _kActionSecondaryBg;
        final edge = pressed ? _kActionPressedEdge : _kActionHairline;
        // Avoid LayoutBuilder inside _BarTap — hover setState under
        // OverlayPortal/action-row rebuilds asserts debugNeedsLayout.
        return _BarShell(
          height: _kActionRowHeight,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          background: bg,
          outline: edge,
          radius: 9,
          pressed: pressed,
          nudge: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsRegular.cloudArrowUp,
                size: 16,
                color: FfTokens.nocturneT2,
              ),
              const SizedBox(width: 7),
              Text(
                display,
                maxLines: 1,
                softWrap: false,
                style: _barLabel(FfTokens.nocturneTx),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 7),
                _ShortcutBadge(shortcut!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge(this.keys, {this.onPrimary = false});

  final String keys;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final fill = onPrimary
        ? const Color(0x1AFFFFFF) // rgba(255,255,255,.1)
        : FfTokens.nocturneSunken; // #262D35
    final ink = onPrimary
        ? const Color(0xBFFFFFFF) // rgba(255,255,255,.75)
        : FfTokens.nocturneT2; // #959AA0
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        keys,
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1,
        ),
      ),
    );
  }
}

class _BarTap extends StatefulWidget {
  const _BarTap({
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.builder,
    this.semanticLabel,
    this.dimWhenDisabled = true,
  });

  final String tooltip;
  /// VoiceOver / test label. Defaults to [tooltip].
  final String? semanticLabel;
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

  void _setHover(bool hovered) {
    // Defer past the current frame so OverlayPortal/Tooltip updates don't
    // collide with LayoutBuilder scheduleLayoutCallback asserts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hovered == hovered && (hovered || !_pressed)) return;
      setState(() {
        _hovered = hovered;
        if (!hovered) _pressed = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.tooltip,
        child: Opacity(
          opacity: enabled || !widget.dimWhenDisabled ? 1 : 0.4,
          child: MouseRegion(
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: enabled ? (_) => _setHover(true) : null,
            onExit: (_) => _setHover(false),
            child: GestureDetector(
              onTapDown:
                  enabled ? (_) => setState(() => _pressed = true) : null,
              onTapUp:
                  enabled ? (_) => setState(() => _pressed = false) : null,
              onTapCancel:
                  enabled ? () => setState(() => _pressed = false) : null,
              onTap: enabled ? widget.onTap : null,
              child: widget.builder(enabled && _hovered, enabled && _pressed),
            ),
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
    required this.pressed,
    required this.child,
    this.background,
    this.gradient,
    this.width,
    this.outline,
    this.radius = 9,
    this.nudge = true,
  });

  final double height;
  final double? width;
  final EdgeInsets padding;
  final Color? background;
  final Gradient? gradient;
  final bool pressed;
  final Widget child;
  final Color? outline;
  final double radius;
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
        color: gradient == null ? background : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: outline == null ? null : Border.all(color: outline!),
      ),
      child: child,
    );
  }
}

TextStyle _barLabel(Color color, {FontWeight weight = FontWeight.w600}) {
  return TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: 13,
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
            tokens: t,
            minHeight: btnMinH,
            enabled: saveNextEnabled,
            onPressed: onSaveNext,
          ),
          const SizedBox(width: 10),
          _OutlinedActionButton(
            label: 'Transmit',
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

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
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

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Opacity(
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
      ),
    );
  }
}
