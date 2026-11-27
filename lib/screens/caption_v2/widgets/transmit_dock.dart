import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/burst_groups.dart';
import '../data/caption_history.dart';
import '../layout/caption_v2_photo_actions.dart';
import 'frame_status_dot.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Primary Save & next fill (Nocturne action bar — Action Bar.html).
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

const double _kActionRowHeight = 32;
const double _kActionChipHeight = 28;
const double _kToolIconSize = 28;

/// Icon-only tool cluster width (5×28 + divider + pad).
const double _kToolsIconsWidth = 149;

/// Icon+label tool cluster (Copy/Paste/Paste last/History/Refresh).
const double _kToolsLabeledWidth = 310;

/// Approx widths used when deciding whether labels fit with Burst reserved.
const double _kApproxSavePrevWidth = 72;
const double _kApproxSaveNextWidth = 130; // Save + ⌘↵ keycap + caret
const double _kApproxBurstWidth = 100; // lightning + Burst + count
const double _kApproxFtpWidth = 155;
const double _kApproxFtpHistoryWidth = 40;
const double _kApproxThumbsWidth = 48;
const double _kActionBarPad = 10;
const double _kActionGap = 8;
const double _kMinActionSpacer = 16;

const Color _kActionBarBg = Color(0xFF14181C);
const Color _kActionSecondaryBg = Color(0xFF1E242A);
const Color _kActionHairline = Color(0x1EE8EEF4); // rgba(232,238,244,.12)
const Color _kSavePrevBg = Color(0xFF15222B);
const Color _kSavePrevBgHover = Color(0xFF1C2D38);
const Color _kSavePrevInk = Color(0xFFBFD3DF);
const Color _kSaveInset = Color(0x994A7A96); // rgba(74,122,150,.6)
const Color _kSaveNextInset = Color(0xF24A7A96); // rgba(74,122,150,.95)
const Color _kSaveNextGlow = Color(0x404A7A96); // rgba(74,122,150,.25)
const Color _kBurstFill = Color(0x0FE8C547); // rgba(232,197,71,.06)
const Color _kBurstFillHover = Color(0x1EE8C547); // rgba(232,197,71,.12)
const Color _kBurstInset = Color(0x73E8C547); // rgba(232,197,71,.45)
const Color _kVerbAccent = Color(0xFF9FC3D6);
const Color _kHistoryRest = Color(0xFFD8DEE4);

String get _modKey =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';

String get _saveNextShortcut => '$_modKey ↵';
String get _savePrevShortcut => '$_modKey ⇧ ↵';
String get _saveToBurstShortcut => '$_modKey B';
String get _pasteLastShortcut => '$_modKey ⇧ V';
String get _ftpShortcut => '$_modKey U';

/// True when the tool cluster can show text labels without colliding once
/// Burst pops in (burst width is always reserved when orange actions are
/// visible, so labels do not flicker on/off as you enter a burst).
bool _canShowToolLabels({
  required double width,
  required bool reserveBurst,
  required bool showTransmit,
  required bool hasThumbs,
  required bool hideOrangeActions,
}) {
  // Layout: [thumbs?] prev · tools · [next?] [burst?] · spacer · [ftp?] [hist?]
  // Compare leftover with icon tools against the extra labeled tools need.
  var fixed = _kActionBarPad + _kApproxSavePrevWidth + _kActionGap;
  // tools slot measured separately
  fixed += _kActionGap;
  if (!hideOrangeActions) {
    fixed += _kApproxSaveNextWidth;
    if (reserveBurst) fixed += _kActionGap + _kApproxBurstWidth;
  }
  if (hasThumbs) fixed += _kApproxThumbsWidth + _kActionGap;
  if (showTransmit && !hideOrangeActions) {
    fixed += _kActionGap + _kApproxFtpWidth + _kActionGap + _kApproxFtpHistoryWidth;
  }
  final leftoverWithIcons = width - fixed - _kToolsIconsWidth;
  final extraForLabels = _kToolsLabeledWidth - _kToolsIconsWidth;
  return leftoverWithIcons >= extraForLabels + _kMinActionSpacer;
}

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
    this.captionHistory = const [],
    this.onCaptionHistorySelect,
    this.onRefresh,
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

  /// Last 5 user-built captions (newest first) for the history dropdown.
  final List<CaptionHistoryEntry> captionHistory;
  final ValueChanged<CaptionHistoryEntry>? onCaptionHistorySelect;

  /// Reset / refresh the current caption selection.
  final VoidCallback? onRefresh;

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
        final showShortcuts = !singleRow && width > 720;
        // Reserve burst even when it is not currently showing so labels do not
        // disappear the moment Save to Burst pops onto a multi-frame photo.
        final showToolLabels = !singleRow &&
            _canShowToolLabels(
              width: width,
              reserveBurst: !hideOrangeActions,
              showTransmit: showTransmit,
              hasThumbs: onThumbs != null,
              hideOrangeActions: hideOrangeActions,
            );
        final prev = _SavePrevButton(
          tooltip: 'Save & previous (${_savePrevShortcut})',
          onPressed: onSavePrevious,
        );
        final tools = _ToolGroup(
          onCopy: onCopy,
          onPaste: onPaste,
          onPasteLast: onPastePrevious,
          pasteEnabled: pasteEnabled,
          pasteLastShortcut: _pasteLastShortcut,
          captionHistory: captionHistory,
          onCaptionHistorySelect: onCaptionHistorySelect,
          onRefresh: onRefresh,
          showLabels: showToolLabels,
        );
        final next = hideOrangeActions
            ? null
            : _SaveNextButton(
                enabled: saveNextEnabled,
                tooltip: 'Save & next (${_saveNextShortcut})',
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

        final leading = <Widget>[
          if (thumbs != null) ...[
            thumbs,
            const SizedBox(width: 8),
          ],
          prev,
          const SizedBox(width: 8),
          tools,
          if (next != null) ...[
            const SizedBox(width: 8),
            next,
          ],
          if (burst != null) ...[
            const SizedBox(width: 8),
            burst,
          ],
        ];

        final trailing = <Widget>[
          if (showTransmit && !hideOrangeActions) ...[
            _FtpGroup(
              narrow: false,
              label: transmitLabel,
              enabled: transmitEnabled,
              onTransmit: onTransmit,
              onHistory: ftpActive ? null : onFtpHistory,
              shortcut: showShortcuts ? _ftpShortcut : null,
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
        ];

        // Prefer one row with FTP right-aligned; wrap when narrow.
        // Do not FittedBox-scale the left cluster — that made Save/tools
        // look tiny next to full-size FTP on the right.
        final useRow = width > 720 && !singleRow;
        final child = useRow
            ? Row(
                children: [
                  ...leading,
                  const SizedBox(width: 8),
                  const Spacer(),
                  ...trailing,
                  if (ftpActive && progress != null) ...[
                    const SizedBox(width: 8),
                    Flexible(child: progress),
                  ],
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...leading,
                  ...trailing,
                  if (!singleRow && ftpActive && progress != null)
                    SizedBox(width: 120, child: progress),
                ],
              );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(singleRow ? 4 : 5),
          decoration: BoxDecoration(
            color: _kActionBarBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x1AE8EEF4)),
          ),
          child: child,
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
                    label: 'Paste last',
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

/// Save to burst — gold accent button + filmstrip popover (hover/click).
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
              final bg = pressed || hovered ? _kBurstFillHover : _kBurstFill;
              // No LayoutBuilder here — OverlayPortal + hover setState
              // otherwise hits debugNeedsLayout asserts (red flashes).
              return _BarShell(
                height: _kActionRowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                background: bg,
                radius: 8,
                outline: _kBurstInset,
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
                    const SizedBox(width: 6),
                    Text(
                      'Burst',
                      style: _barLabel(FfTokens.nocturneTx, size: 13),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
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
                          height: 17 / 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: _goldInk,
                        ),
                      ),
                    ),
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

class _SavePrevButton extends StatelessWidget {
  const _SavePrevButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _BarTap(
      tooltip: tooltip,
      enabled: onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final bg = hovered || pressed ? _kSavePrevBgHover : _kSavePrevBg;
        final ink = hovered || pressed ? Colors.white : _kSavePrevInk;
        return _BarShell(
          height: _kActionRowHeight,
          padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
          background: bg,
          radius: 8,
          outline: _kSaveInset,
          pressed: pressed,
          nudge: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.caretLeft, size: 13, color: ink),
              const SizedBox(width: 5),
              Text(
                'Save',
                style: _barLabel(ink, size: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SaveNextButton extends StatelessWidget {
  const _SaveNextButton({
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _BarTap(
      tooltip: tooltip,
      enabled: enabled && onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final gradient = pressed
            ? _kActionTealGradientPressed
            : hovered
                ? _kActionTealGradientHover
                : _kActionTealGradient;
        return _BarShell(
          height: _kActionRowHeight,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          gradient: gradient,
          radius: 8,
          outline: _kSaveNextInset,
          glow: _kSaveNextGlow,
          pressed: pressed,
          nudge: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Save',
                style: _barLabel(Colors.white, size: 13, weight: FontWeight.w700),
              ),
              const SizedBox(width: 7),
              _ShortcutKeycap(label: _saveNextShortcut),
              const SizedBox(width: 6),
              const Icon(
                PhosphorIconsBold.caretRight,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShortcutKeycap extends StatelessWidget {
  const _ShortcutKeycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x0FE8EEF4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x2EE8EEF4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: _kSavePrevInk,
          height: 1.2,
        ),
      ),
    );
  }
}

class _ToolGroup extends StatelessWidget {
  const _ToolGroup({
    required this.onCopy,
    required this.onPaste,
    required this.onPasteLast,
    required this.pasteEnabled,
    required this.pasteLastShortcut,
    required this.captionHistory,
    this.onCaptionHistorySelect,
    this.onRefresh,
    this.showLabels = false,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPasteLast;
  final bool pasteEnabled;
  final String pasteLastShortcut;
  final List<CaptionHistoryEntry> captionHistory;
  final ValueChanged<CaptionHistoryEntry>? onCaptionHistorySelect;
  final VoidCallback? onRefresh;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kActionRowHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _kActionSecondaryBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x14E8EEF4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolIconButton(
            icon: PhosphorIconsRegular.copy,
            label: showLabels ? 'Copy' : null,
            tooltip: 'Copy caption',
            onPressed: onCopy,
          ),
          _ToolIconButton(
            icon: PhosphorIconsRegular.clipboardText,
            label: showLabels ? 'Paste' : null,
            tooltip: 'Paste caption',
            onPressed: pasteEnabled ? onPaste : null,
          ),
          _ToolIconButton(
            icon: PhosphorIconsRegular.arrowBendDownLeft,
            label: showLabels ? 'Paste last' : null,
            tooltip: 'Paste last caption ($pasteLastShortcut)',
            onPressed: onPasteLast,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              width: 1,
              height: 16,
              child: ColoredBox(color: Color(0x1AE8EEF4)),
            ),
          ),
          _CaptionHistoryButton(
            entries: captionHistory,
            onSelect: onCaptionHistorySelect,
            showLabel: showLabels,
          ),
          _ToolIconButton(
            icon: PhosphorIconsRegular.arrowClockwise,
            label: showLabels ? 'Refresh' : null,
            tooltip: 'Refresh',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.selected = false,
  });

  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final labeled = label != null;
    return _BarTap(
      tooltip: tooltip,
      enabled: onPressed != null,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final active = selected || hovered || pressed;
        final fg = active ? FfTokens.nocturneTx : FfTokens.nocturneT2;
        return Container(
          width: labeled ? null : _kToolIconSize,
          height: _kToolIconSize,
          padding: labeled
              ? const EdgeInsets.symmetric(horizontal: 6)
              : EdgeInsets.zero,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: labeled
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      label!,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        height: 1,
                      ),
                    ),
                  ],
                )
              : Icon(icon, size: 15, color: fg),
        );
      },
    );
  }
}

class _CaptionHistoryButton extends StatefulWidget {
  const _CaptionHistoryButton({
    required this.entries,
    this.onSelect,
    this.showLabel = false,
  });

  final List<CaptionHistoryEntry> entries;
  final ValueChanged<CaptionHistoryEntry>? onSelect;
  final bool showLabel;

  @override
  State<_CaptionHistoryButton> createState() => _CaptionHistoryButtonState();
}

class _CaptionHistoryButtonState extends State<_CaptionHistoryButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode(debugLabel: 'CaptionHistory');
  final GlobalKey _buttonKey = GlobalKey();
  int _keyboardIndex = -1;
  /// Row whose full-size preview was just closed — kept lit so the user can
  /// apply that caption next.
  int _viewedIndex = -1;
  bool _openUp = true;
  bool _openingZoom = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.dispose();
    if (_portal.isShowing) _portal.hide();
    super.dispose();
  }

  bool get _open => _portal.isShowing;

  List<CaptionHistoryEntry> get _entries =>
      widget.entries.take(5).toList(growable: false);

  bool _onKey(KeyEvent event) {
    if (!_open || event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    final digit = event.logicalKey.keyLabel;
    if (digit.length == 1) {
      final n = int.tryParse(digit);
      if (n != null && n >= 1 && n <= _entries.length) {
        _pick(_entries[n - 1]);
        return true;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _keyboardIndex = (_keyboardIndex + 1).clamp(0, _entries.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _keyboardIndex = (_keyboardIndex - 1).clamp(0, _entries.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_keyboardIndex >= 0 && _keyboardIndex < _entries.length) {
        _pick(_entries[_keyboardIndex]);
        return true;
      }
    }
    return false;
  }

  void _resolveDirection() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _openUp = true;
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    _openUp = top > 280;
  }

  void _openMenu({int? focusIndex}) {
    _keyboardIndex = focusIndex ?? -1;
    _resolveDirection();
    if (!_portal.isShowing) {
      _portal.show();
      _focus.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _close({bool clearViewed = true}) {
    if (_portal.isShowing) _portal.hide();
    _keyboardIndex = -1;
    if (clearViewed) _viewedIndex = -1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openMenu();
    }
  }

  void _pick(CaptionHistoryEntry entry) {
    _close();
    widget.onSelect?.call(entry);
  }

  Future<void> _openZoom(String path, int entryIndex) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || _openingZoom) return;
    _openingZoom = true;
    // Close first so this menu's ESC handler does not steal the zoom dialog.
    // Keep the viewed index so we can restore + highlight on return.
    _viewedIndex = entryIndex;
    _close(clearViewed: false);
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await showCaptionV2Zoom(context, trimmed);
    } finally {
      _openingZoom = false;
    }
    if (!mounted) return;
    _viewedIndex = entryIndex;
    _openMenu(focusIndex: entryIndex);
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
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
              targetAnchor:
                  _openUp ? Alignment.topCenter : Alignment.bottomCenter,
              followerAnchor:
                  _openUp ? Alignment.bottomCenter : Alignment.topCenter,
              offset: Offset(0, _openUp ? -6 : 6),
              child: Focus(
                focusNode: _focus,
                child: _CaptionHistoryMenu(
                  entries: _entries,
                  keyboardIndex: _keyboardIndex,
                  viewedIndex: _viewedIndex,
                  onHoverIndex: (i) {
                    if (_keyboardIndex != i) {
                      setState(() => _keyboardIndex = i);
                    }
                  },
                  onSelect: _pick,
                  onClose: _close,
                  onOpenZoom: _openZoom,
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: KeyedSubtree(
          key: _buttonKey,
          child: _ToolIconButton(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            label: widget.showLabel ? 'History' : null,
            tooltip: 'Caption history',
            selected: open,
            onPressed: widget.onSelect == null ? null : _toggle,
          ),
        ),
      ),
    );
  }
}

class _CaptionHistoryMenu extends StatelessWidget {
  const _CaptionHistoryMenu({
    required this.entries,
    required this.keyboardIndex,
    required this.viewedIndex,
    required this.onHoverIndex,
    required this.onSelect,
    required this.onClose,
    required this.onOpenZoom,
  });

  final List<CaptionHistoryEntry> entries;
  final int keyboardIndex;
  final int viewedIndex;
  final ValueChanged<int> onHoverIndex;
  final ValueChanged<CaptionHistoryEntry> onSelect;
  final VoidCallback onClose;
  final void Function(String path, int entryIndex) onOpenZoom;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 48;
    final width = maxW < 820 ? maxW.clamp(320.0, 820.0) : 820.0;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: _kActionSecondaryBg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x24E8EEF4)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 44,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 4, 5),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'RECENT CAPTIONS',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.84,
                        color: FfTokens.nocturneT3,
                        height: 1,
                      ),
                    ),
                  ),
                  const Text(
                    'Last 5',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: FfTokens.nocturneT3,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _OverlaySafeTap(
                    enabled: true,
                    onTap: onClose,
                    builder: (hovered, pressed) {
                      return Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hovered || pressed
                              ? FfTokens.nocturneSunken
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 14,
                          color: hovered || pressed
                              ? FfTokens.nocturneTx
                              : FfTokens.nocturneT3,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(9, 8, 9, 12),
                child: Text(
                  'No saved captions yet',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    color: FfTokens.nocturneT3,
                  ),
                ),
              )
            else
              for (var i = 0; i < entries.length; i++)
                _CaptionHistoryRow(
                  index: i + 1,
                  entry: entries[i],
                  focused: keyboardIndex == i,
                  viewed: viewedIndex == i,
                  onHover: () => onHoverIndex(i),
                  onTap: () => onSelect(entries[i]),
                  onOpenZoom: (path) => onOpenZoom(path, i),
                ),
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0x14E8EEF4)),
                ),
              ),
              child: const Text(
                'Template text (dateline, venue, credit) is added automatically',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: FfTokens.nocturneT3,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionHistoryRow extends StatelessWidget {
  const _CaptionHistoryRow({
    required this.index,
    required this.entry,
    required this.focused,
    required this.viewed,
    required this.onHover,
    required this.onTap,
    required this.onOpenZoom,
  });

  final int index;
  final CaptionHistoryEntry entry;
  final bool focused;
  final bool viewed;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final ValueChanged<String> onOpenZoom;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: _OverlaySafeTap(
        enabled: true,
        onTap: onTap,
        builder: (hovered, pressed) {
          final active = focused || viewed || hovered || pressed;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: viewed
                  ? const Color(0x244A7A96)
                  : active
                      ? FfTokens.nocturneSunken
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: viewed
                  ? Border.all(color: const Color(0x664A7A96))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: viewed
                          ? FfTokens.nocturneAc
                          : const Color(0x1EE8EEF4),
                    ),
                    color: viewed ? const Color(0x334A7A96) : null,
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: viewed ? FfTokens.nocturneTx : FfTokens.nocturneT3,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Absorb so the loupe / thumb hit area does not apply the
                // caption via the parent row tap.
                GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  child: _CaptionHistoryThumb(
                    path: entry.imagePath,
                    highlighted: viewed,
                    onOpenZoom: () {
                      final path = entry.imagePath?.trim() ?? '';
                      if (path.isEmpty) return;
                      onOpenZoom(path);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: _bodySpans(entry)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${formatCaptionHistoryAgo(entry.savedAt)} ago',
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    color: FfTokens.nocturneT3,
                    height: 19 / 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static List<InlineSpan> _bodySpans(CaptionHistoryEntry entry) {
    const base = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 15,
      height: 21 / 15,
      color: _kHistoryRest,
      fontWeight: FontWeight.w400,
    );
    final body = entry.body;
    if (body.isEmpty) return [const TextSpan(text: '', style: base)];

    final players = entry.playersText.trim();
    final verb = entry.verbText.trim();
    if (players.isEmpty && verb.isEmpty) {
      return [TextSpan(text: body, style: base)];
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    void emitPlain(int end) {
      if (end <= cursor) return;
      spans.add(TextSpan(text: body.substring(cursor, end), style: base));
      cursor = end;
    }

    void emitMatch(String needle, TextStyle style) {
      if (needle.isEmpty || cursor >= body.length) return;
      final from = body.toLowerCase().indexOf(needle.toLowerCase(), cursor);
      if (from < 0) return;
      emitPlain(from);
      spans.add(
        TextSpan(
          text: body.substring(from, from + needle.length),
          style: style,
        ),
      );
      cursor = from + needle.length;
    }

    emitMatch(
      players,
      base.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
    );
    emitMatch(
      verb,
      base.copyWith(color: _kVerbAccent, fontWeight: FontWeight.w400),
    );
    emitPlain(body.length);
    return spans.isEmpty ? [TextSpan(text: body, style: base)] : spans;
  }
}

class _CaptionHistoryThumb extends StatefulWidget {
  const _CaptionHistoryThumb({
    this.path,
    this.highlighted = false,
    this.onOpenZoom,
  });

  final String? path;
  final bool highlighted;
  final VoidCallback? onOpenZoom;

  static const double _w = 100;
  static const double _h = 70;

  /// Same tile, scaled up from its center on hover.
  static const double _previewScale = 2.4;

  @override
  State<_CaptionHistoryThumb> createState() => _CaptionHistoryThumbState();
}

class _CaptionHistoryThumbState extends State<_CaptionHistoryThumb> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _hoverTimer;
  int _hoverGen = 0;
  bool _wantHover = false;
  bool _hover = false;

  void _removePreview() {
    _entry?.remove();
    _entry = null;
  }

  void _showPreview(String filePath) {
    _removePreview();
    const scale = _CaptionHistoryThumb._previewScale;
    final pw = _CaptionHistoryThumb._w * scale;
    final ph = _CaptionHistoryThumb._h * scale;

    _entry = OverlayEntry(
      builder: (context) {
        // Pin to the thumb via LayerLink — same center, same crop, just bigger.
        return CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.center,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              child: SizedBox(
                width: pw,
                height: ph,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF262D35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0x66E8EEF4),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: OrientedFilePreview(
                      path: filePath,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _applyHover(bool hover, String filePath) {
    if (!mounted) return;
    if (_hover != hover) setState(() => _hover = hover);
    if (hover) {
      _showPreview(filePath);
    } else {
      _removePreview();
    }
  }

  void _setHover(bool hover, String filePath) {
    if (_wantHover == hover) return;
    _wantHover = hover;
    _hoverTimer?.cancel();
    final gen = ++_hoverGen;
    final delay = hover
        ? const Duration(milliseconds: 60)
        : const Duration(milliseconds: 40);
    _hoverTimer = Timer(delay, () {
      if (!mounted || gen != _hoverGen) return;
      _applyHover(hover, filePath);
    });
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removePreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.path?.trim() ?? '';
    final exists = filePath.isNotEmpty && File(filePath).existsSync();
    final canZoom = exists && widget.onOpenZoom != null;
    final ring = widget.highlighted
        ? FfTokens.nocturneAc
        : _hover
            ? const Color(0x66E8EEF4)
            : const Color(0x1EE8EEF4);

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: canZoom ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: exists ? (_) => _setHover(true, filePath) : null,
        onExit: (_) => _setHover(false, filePath),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canZoom ? widget.onOpenZoom : null,
          child: SizedBox(
            width: _CaptionHistoryThumb._w,
            height: _CaptionHistoryThumb._h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: ring,
                        width: widget.highlighted || _hover ? 1.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ColoredBox(
                        color: const Color(0xFF262D35),
                        child: exists
                            ? OrientedFilePreview(
                                path: filePath,
                                fit: BoxFit.cover,
                                cacheWidth: 160,
                                filterQuality: FilterQuality.medium,
                              )
                            : filePath.isEmpty
                                ? null
                                : const Center(
                                    child: PhosphorIcon(
                                      PhosphorIconsRegular.imageBroken,
                                      size: 14,
                                      color: FfTokens.nocturneT3,
                                    ),
                                  ),
                      ),
                    ),
                  ),
                ),
                if (canZoom)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hover || widget.highlighted
                              ? FfTokens.nocturneAc
                              : const Color(0xE0181D22),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _hover || widget.highlighted
                                ? FfTokens.nocturneAc
                                : const Color(0x40E8EEF4),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: PhosphorIcon(
                          PhosphorIconsRegular.magnifyingGlass,
                          size: 11,
                          color: _hover || widget.highlighted
                              ? Colors.white
                              : FfTokens.nocturneTx,
                        ),
                      ),
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
              final bg = hovered || pressed
                  ? FfTokens.nocturneSunken
                  : _kActionSecondaryBg;
              return _BarShell(
                height: _kActionRowHeight,
                width: _kActionRowHeight,
                padding: EdgeInsets.zero,
                background: bg,
                radius: 8,
                outline: _kActionHairline,
                pressed: pressed,
                nudge: false,
                child: const Icon(
                  PhosphorIconsRegular.clockClockwise,
                  size: 15,
                  color: FfTokens.nocturneT2,
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
    final tip = shortcut == null
        ? (status.isEmpty ? 'FTP' : 'FTP · $status')
        : 'FTP · $shortcut';

    return _BarTap(
      tooltip: tip,
      semanticLabel: 'FTP',
      enabled: canSend,
      onTap: onPressed,
      builder: (hovered, pressed) {
        final bg = hovered || pressed
            ? FfTokens.nocturneSunken
            : _kActionSecondaryBg;
        // Avoid LayoutBuilder inside _BarTap — hover setState under
        // OverlayPortal/action-row rebuilds asserts debugNeedsLayout.
        return _BarShell(
          height: _kActionRowHeight,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          background: bg,
          radius: 8,
          outline: _kActionHairline,
          pressed: pressed,
          nudge: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsRegular.cloudArrowUp,
                size: 14,
                color: FfTokens.nocturneT2,
              ),
              const SizedBox(width: 6),
              Text(
                'FTP:',
                style: _barLabel(
                  FfTokens.nocturneT2,
                  weight: FontWeight.w500,
                  size: 12.5,
                ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  status,
                  maxLines: 1,
                  softWrap: false,
                  style: _barLabel(FfTokens.nocturneTx, size: 12.5),
                ),
              ],
            ],
          ),
        );
      },
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
    this.glow,
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
  final Color? glow;
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
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow!,
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: child,
    );
  }
}

TextStyle _barLabel(
  Color color, {
  FontWeight weight = FontWeight.w600,
  double size = 13,
}) {
  return TextStyle(
    fontFamily: FfTokens.fontFamily,
    fontSize: size,
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
              label: 'Paste last',
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
        ? _kActionTealGradientPressed
        : hovering
            ? _kActionTealGradientHover
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
