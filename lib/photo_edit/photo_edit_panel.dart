import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../screens/caption_v2/data/caption_v2_controller.dart';
import '../screens/caption_v2/widgets/mobile_photo_filmstrip.dart';
import '../screens/caption_v2/widgets/photo_preview_bar.dart';
import '../theme/ff_tokens.dart';
import '../widgets/oriented_file_preview.dart';
import 'photo_adjust_config.dart';
import 'photo_crop.dart';
import 'photo_crop_overlay.dart';
import 'photo_edit_session.dart';
import 'photo_histogram.dart';

/// Edit-mode toggle. Sits on the photo; the sheet covers the thumbnails.
class PhotoEditModeButton extends StatelessWidget {
  const PhotoEditModeButton({
    super.key,
    required this.session,
    required this.controller,
    this.compact = false,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final on = session.editing;
        final dirty = session.isDirty(path);
        final enabled = path != null && !session.saving;
        if (compact) {
          final emphasized = dirty || on;
          return Tooltip(
            message: on ? 'Close edit' : 'Edit photo',
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: _ViewerBarActionButton(
                icon: PhosphorIconsRegular.slidersHorizontal,
                label: on ? 'Done' : 'Edit',
                emphasized: emphasized,
                onTap: enabled ? session.toggleEditing : null,
              ),
            ),
          );
        }
        final fg = on ? tokens.inkOnAccent : tokens.text;
        return Tooltip(
          message: on ? 'Close edit' : 'Edit photo',
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Material(
              color: on ? tokens.accent : tokens.bg.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: enabled ? session.toggleEditing : null,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: on ? tokens.accent : tokens.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIconsRegular.sliders,
                        size: 15,
                        color: fg,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        on ? 'Done' : 'Edit',
                        style: tokens.metaStyle.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      if (dirty && !on) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            shape: BoxShape.circle,
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
      },
    );
  }
}

/// Crop-tool toggle for the photo bottom bar.
class PhotoCropModeButton extends StatelessWidget {
  const PhotoCropModeButton({
    super.key,
    required this.session,
    required this.controller,
    this.compact = false,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final on = session.cropping;
        final enabled = path != null && !session.saving;
        VoidCallback? onTap;
        if (enabled) {
          onTap = () {
            if (on) {
              session.finishCropping();
            } else {
              session.toggleCropping();
            }
          };
        }
        if (compact) {
          return Tooltip(
            message: on ? 'Finish crop' : 'Crop photo',
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: _ViewerBarActionButton(
                icon: PhosphorIconsRegular.crop,
                label: 'Crop',
                kbd: 'C',
                emphasized: on,
                onTap: onTap,
              ),
            ),
          );
        }
        final fg = on ? tokens.inkOnAccent : tokens.text;
        return Tooltip(
          message: on ? 'Finish crop' : 'Crop photo',
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Material(
              color: on ? tokens.accent : tokens.bg.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: on ? tokens.accent : tokens.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIconsRegular.crop,
                        size: 15,
                        color: fg,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Crop',
                        style: tokens.metaStyle.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 90° rotate buttons for the photo bottom bar.
class PhotoRotateButtons extends StatelessWidget {
  const PhotoRotateButtons({
    super.key,
    required this.session,
    required this.controller,
    this.compact = false,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final enabled = path != null && !session.saving;
        final active = session.rotationFor(path) != 0;
        final rotatePath = path;

        if (compact) {
          Widget seg({
            required String tip,
            required IconData icon,
            required VoidCallback? onTap,
          }) {
            return Tooltip(
              message: tip,
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(7),
                    hoverColor: FfTokens.nocturneHv,
                    child: SizedBox(
                      width: 32,
                      height: 30,
                      child: Center(
                        child: PhosphorIcon(
                          icon,
                          size: 16,
                          color: FfTokens.nocturneT2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: FfTokens.nocturneSunken,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg(
                  tip: 'Rotate left',
                  icon: PhosphorIconsRegular.arrowCounterClockwise,
                  onTap: enabled && rotatePath != null
                      ? () => session.rotateCounterClockwise(rotatePath)
                      : null,
                ),
                const SizedBox(width: 2),
                seg(
                  tip: 'Rotate right',
                  icon: PhosphorIconsRegular.arrowClockwise,
                  onTap: enabled && rotatePath != null
                      ? () => session.rotateClockwise(rotatePath)
                      : null,
                ),
              ],
            ),
          );
        }

        Widget button({
          required String tip,
          required IconData icon,
          required VoidCallback? onTap,
        }) {
          return Tooltip(
            message: tip,
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Material(
                color: active
                    ? tokens.accent.withValues(alpha: 0.22)
                    : tokens.bg.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? tokens.accent : tokens.divider,
                      ),
                    ),
                    child: PhosphorIcon(
                      icon,
                      size: 15,
                      color: tokens.text,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              tip: 'Rotate left',
              icon: PhosphorIconsRegular.arrowCounterClockwise,
              onTap: enabled && rotatePath != null
                  ? () => session.rotateCounterClockwise(rotatePath)
                  : null,
            ),
            const SizedBox(width: 4),
            button(
              tip: 'Rotate right',
              icon: PhosphorIconsRegular.arrowClockwise,
              onTap: enabled && rotatePath != null
                  ? () => session.rotateClockwise(rotatePath)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// Crop / Edit control for the main photo viewer bar.
class _ViewerBarActionButton extends StatefulWidget {
  const _ViewerBarActionButton({
    required this.icon,
    required this.label,
    required this.emphasized,
    required this.onTap,
    this.kbd,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final String? kbd;
  final bool emphasized;
  final bool showDot;
  final VoidCallback? onTap;

  @override
  State<_ViewerBarActionButton> createState() => _ViewerBarActionButtonState();
}

class _ViewerBarActionButtonState extends State<_ViewerBarActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final emphasized = widget.emphasized;
    final hover = _hover && !emphasized;
    final fill = emphasized
        ? FfTokens.nocturneAccentSoft
        : hover
            ? FfTokens.nocturneHv
            : FfTokens.nocturneSf;
    final edge = emphasized
        ? FfTokens.nocturneAccentEdge
        : hover
            ? FfTokens.nocturneLn2
            : FfTokens.nocturneLn;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(9),
          hoverColor: Colors.transparent,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: edge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  widget.icon,
                  size: 16,
                  color: emphasized ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: FfTokens.nocturneTx,
                  ),
                ),
                if (widget.showDot) ...[
                  const SizedBox(width: 7),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: FfTokens.nocturneAc,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: FfTokens.nocturneEl,
                          blurRadius: 0,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.kbd != null) ...[
                  const SizedBox(width: 7),
                  _KbdChip(
                    widget.kbd!,
                    emphasized: emphasized,
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

enum _EditTool { adjust, crop }

/// Full-window edit mode: tools rail, photo panel, filmstrip below.
class PhotoEditWorkspace extends StatefulWidget {
  const PhotoEditWorkspace({
    super.key,
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  State<PhotoEditWorkspace> createState() => _PhotoEditWorkspaceState();
}

class _PhotoEditWorkspaceState extends State<PhotoEditWorkspace> {
  /// `null` = Fit. Otherwise scale vs fit-sized preview (1.0 = 100%).
  double? _zoomScale;
  final TransformationController _zoomTransform = TransformationController();

  /// Stage size used to scale about the centre (not the top-left).
  Size _zoomViewport = Size.zero;

  static const _zoomPresets = <double>[0.25, 0.50, 0.75, 1.0];

  /// Sticky zoom tool (Z). When off, the stage defaults to hand/pan.
  bool _zoomTool = false;

  /// Tracks crop mode so exiting can reset zoom to Fit.
  late bool _wasCropping = widget.session.cropping;

  _EditTool get _tool {
    return widget.session.cropping ? _EditTool.crop : _EditTool.adjust;
  }

  /// Pan is the default over the picture outside crop / zoom-tool.
  bool get _handActive =>
      !widget.session.cropping && !_zoomTool && _zoomScale != null;

  bool get _zoomToolActive =>
      !widget.session.cropping && _zoomTool;

  void _ensureZoomedForNav() {
    if (_zoomScale == null) _setZoomScale(1.0);
  }

  void _toggleZoomTool() {
    final s = widget.session;
    if (s.cropping) s.finishCropping();
    setState(() => _zoomTool = !_zoomTool);
    if (_zoomTool) _ensureZoomedForNav();
  }

  void _selectTool(_EditTool tool) {
    final s = widget.session;
    switch (tool) {
      case _EditTool.adjust:
        if (s.cropping) s.finishCropping();
      case _EditTool.crop:
        if (!s.cropping) s.toggleCropping();
        setState(() => _zoomTool = false);
    }
  }

  Future<void> _done() async {
    final s = widget.session;
    final path = widget.controller.currentPath;
    if (path != null &&
        s.isDirty(path) &&
        !s.saving &&
        !widget.controller.ftpUploadingPath(path)) {
      await s.apply(path);
    }
    if (s.editing) s.toggleEditing();
  }

  void _applyZoomMatrix(double scale) {
    final vp = _zoomViewport;
    if (vp.isEmpty) {
      _zoomTransform.value =
          Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
      return;
    }
    final cx = vp.width / 2;
    final cy = vp.height / 2;
    // Scale about the stage centre so the photo stays centred at any zoom.
    _zoomTransform.value = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }

  void _setZoomScale(double? scale) {
    if (scale == null) {
      setState(() => _zoomScale = null);
      _zoomTransform.value = Matrix4.identity();
      return;
    }
    final next = scale.clamp(0.10, 8.0);
    setState(() => _zoomScale = next);
    _applyZoomMatrix(next);
  }

  void _scrollZoom(double scrollDy) {
    if (widget.session.cropping) return;
    // Fine wheel steps (~5%); dropdown jumps in 25% increments.
    final base = _zoomScale ?? 1.0;
    final step = 0.05;
    final next = scrollDy > 0 ? base - step : base + step;
    _setZoomScale(next.clamp(0.10, 8.0));
  }

  void _zoomToolTap({required bool zoomOut}) {
    if (widget.session.cropping) return;
    final base = _zoomScale ?? 1.0;
    final next = zoomOut ? base / 1.25 : base * 1.25;
    _setZoomScale(next.clamp(0.10, 8.0));
  }

  void _syncZoomFromTransform() {
    final s = _zoomTransform.value.getMaxScaleOnAxis();
    if (_zoomScale == null) return;
    final next = s.clamp(0.10, 8.0);
    if ((next - _zoomScale!).abs() < 0.001) {
      // Hand tool pans freely — don't snap translation back to centre.
      if (_handActive) return;
      _applyZoomMatrix(next);
      return;
    }
    setState(() => _zoomScale = next);
    if (_handActive) return;
    _applyZoomMatrix(next);
  }

  void _onZoomViewport(Size size) {
    if (size == _zoomViewport || size.isEmpty) return;
    _zoomViewport = size;
    final scale = _zoomScale;
    if (scale != null) _applyZoomMatrix(scale);
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionNav);
  }

  void _onSessionNav() {
    final cropping = widget.session.cropping;
    if (_wasCropping && !cropping) {
      // After crop, show the framed photo fitted — not stuck at 100%+.
      _wasCropping = false;
      _zoomTool = false;
      _setZoomScale(null);
      return;
    }
    _wasCropping = cropping;
    if (cropping && _zoomTool) {
      setState(() => _zoomTool = false);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionNav);
    _zoomTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final controller = widget.controller;
    return _CompareKeyBinder(
      session: session,
      controller: controller,
      onZoomToolShortcut: _toggleZoomTool,
      child: ColoredBox(
        color: FfTokens.nocturneBg,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: _EditSidePanel(
                  session: session,
                  controller: controller,
                  tool: _tool,
                  onClose: () {
                    if (session.editing) session.toggleEditing();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _EditStage(
                        session: session,
                        controller: controller,
                        zoomScale: _zoomScale,
                        zoomPresets: _zoomPresets,
                        zoomTransform: _zoomTransform,
                        onZoomScaleChanged: _setZoomScale,
                        onScrollZoom: _scrollZoom,
                        onZoomInteraction: _syncZoomFromTransform,
                        onZoomViewport: _onZoomViewport,
                        handActive: _handActive,
                        zoomToolActive: _zoomToolActive,
                        onZoomToolTap: _zoomToolTap,
                        onToggleCrop: () => _selectTool(
                          session.cropping ? _EditTool.adjust : _EditTool.crop,
                        ),
                        onSelectZoomTool: _toggleZoomTool,
                        onDone: _done,
                        onClose: () {
                          if (session.editing) session.toggleEditing();
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EditFilmstripBar(
                      session: session,
                      controller: controller,
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

/// Hold backslash to flash the ungraded original while editing.
/// ⌘Z / Ctrl+Z undoes; ⇧⌘Z / Ctrl+Y redoes. Z toggles the zoom tool.
class _CompareKeyBinder extends StatefulWidget {
  const _CompareKeyBinder({
    required this.session,
    required this.child,
    this.controller,
    this.onZoomToolShortcut,
  });

  final PhotoEditSession session;
  final CaptionV2Controller? controller;
  final Widget child;
  final VoidCallback? onZoomToolShortcut;

  @override
  State<_CompareKeyBinder> createState() => _CompareKeyBinderState();
}

class _CompareKeyBinderState extends State<_CompareKeyBinder> {
  final FocusNode _focus = FocusNode(debugLabel: 'photoEditKeys');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void reassemble() {
    super.reassemble();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    widget.session.setComparing(false);
    _focus.dispose();
    super.dispose();
  }

  bool _editingTextField() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _isPlainC(KeyEvent event) {
    final isC = event.logicalKey == LogicalKeyboardKey.keyC ||
        event.character?.toLowerCase() == 'c';
    if (!isC) return false;
    final keys = HardwareKeyboard.instance;
    return !keys.isMetaPressed &&
        !keys.isControlPressed &&
        !keys.isAltPressed &&
        !keys.isShiftPressed;
  }

  KeyEventResult _onFocusKey(FocusNode node, KeyEvent event) {
    if (!widget.session.editing || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!_isPlainC(event)) return KeyEventResult.ignored;
    widget.session.shortcutToggleCrop();
    return KeyEventResult.handled;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!widget.session.editing) return false;
    if (event.logicalKey == LogicalKeyboardKey.backslash) {
      if (_editingTextField()) return false;
      if (event is KeyDownEvent) {
        widget.session.setComparing(true);
        return true;
      }
      if (event is KeyUpEvent) {
        widget.session.setComparing(false);
        return true;
      }
      return false;
    }
    if (event is! KeyDownEvent) return false;
    // C is handled here (and debounced on the session) so it still works
    // when a slider number box or the firebar has focus.
    if (_isPlainC(event)) {
      if (_editingTextField()) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return widget.session.shortcutToggleCrop();
    }
    if (_editingTextField()) return false;
    final mods = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = mods.contains(LogicalKeyboardKey.metaLeft) ||
        mods.contains(LogicalKeyboardKey.metaRight) ||
        mods.contains(LogicalKeyboardKey.controlLeft) ||
        mods.contains(LogicalKeyboardKey.controlRight);
    final shift = mods.contains(LogicalKeyboardKey.shiftLeft) ||
        mods.contains(LogicalKeyboardKey.shiftRight);
    // Plain Z → zoom tool (⌘Z stays undo).
    if (!meta &&
        !shift &&
        !HardwareKeyboard.instance.isAltPressed &&
        (event.logicalKey == LogicalKeyboardKey.keyZ ||
            event.character?.toLowerCase() == 'z')) {
      widget.onZoomToolShortcut?.call();
      return true;
    }
    final path = widget.controller?.currentPath;
    if (path == null) return false;
    if (!meta) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (shift) {
        if (!widget.session.canRedo(path)) return false;
        return widget.session.redo(path);
      }
      if (!widget.session.canUndo(path)) return false;
      return widget.session.undo(path);
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY && !shift) {
      if (!widget.session.canRedo(path)) return false;
      return widget.session.redo(path);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onFocusKey,
      // Don't autofocus — stealing focus on open ate the first crop drag.
      child: widget.child,
    );
  }
}

class _EditStage extends StatelessWidget {
  const _EditStage({
    required this.session,
    required this.controller,
    required this.zoomScale,
    required this.zoomPresets,
    required this.zoomTransform,
    required this.onZoomScaleChanged,
    required this.onScrollZoom,
    required this.onZoomInteraction,
    required this.onZoomViewport,
    required this.handActive,
    required this.zoomToolActive,
    required this.onZoomToolTap,
    required this.onToggleCrop,
    required this.onSelectZoomTool,
    required this.onDone,
    required this.onClose,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  /// `null` = Fit.
  final double? zoomScale;
  final List<double> zoomPresets;
  final TransformationController zoomTransform;
  final ValueChanged<double?> onZoomScaleChanged;
  final ValueChanged<double> onScrollZoom;
  final VoidCallback onZoomInteraction;
  final ValueChanged<Size> onZoomViewport;
  final bool handActive;
  final bool zoomToolActive;
  final void Function({required bool zoomOut}) onZoomToolTap;
  final VoidCallback onToggleCrop;
  final VoidCallback onSelectZoomTool;
  final Future<void> Function() onDone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final grade = session.adjustmentsFor(path);
        final cropping = session.cropping;
        final straighten = session.straightenFor(path);
        final draftCrop = path == null ? PhotoCrop.full : session.cropFor(path);
        final version = path == null ? 0 : controller.imageContentStamp(path);
        final turns = session.rotationFor(path);
        final dirty = path != null && session.isDirty(path);
        final saving = session.saving;
        final imageAspect = session.imageAspectFor(path) ?? 1.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: FfTokens.nocturneEl,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: PhotoPreviewInfoBar(
                          controller: controller,
                          bare: true,
                        ),
                      ),
                      _ZoomToggle(
                        scale: cropping ? null : zoomScale,
                        presets: zoomPresets,
                        enabled: !cropping,
                        onChanged: onZoomScaleChanged,
                      ),
                      const SizedBox(width: 4),
                      _IconChip(
                        icon: PhosphorIconsRegular.x,
                        tip: 'Close (Esc)',
                        onTap: onClose,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  // Keep the photo / crop clear of the filmstrip below.
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        onScrollZoom(event.scrollDelta.dy);
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Stage chrome only (letterbox). Crop dim is separate.
                        color: session.backdrop.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: path == null
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTapUp: (details) =>
                                    _showBackdropMenu(
                                  context,
                                  session,
                                  details.globalPosition,
                                ),
                                child: Center(
                                  child: PhosphorIcon(
                                    PhosphorIconsRegular.image,
                                    color: FfTokens.nocturneT3,
                                    size: 36,
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final odd = turns.isOdd;
                                  // Always letterbox from the real image pixels
                                  // (BoxFit.contain). Never fill a guessed aspect.
                                  final useFit = cropping || zoomScale == null;
                                  // Inset so crop handles / rotate zones aren't
                                  // clipped by the stage chrome or ClipRRect.
                                  final inset = cropping ? 28.0 : 10.0;
                                  final stageSize = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  // Photo pixel bounds (not crop dim) — right-click
                                  // outside this recolors stage chrome only.
                                  final photoHit = _stagePhotoHitRect(
                                    stageSize: stageSize,
                                    inset: inset,
                                    imageAspect: imageAspect,
                                    straightenDegrees: straighten,
                                  );
                                  final rawPreview = OrientedFilePreview(
                                    key: ValueKey(
                                      'edit-stage-$path-$version',
                                    ),
                                    path: path,
                                    version: version,
                                    fit: BoxFit.contain,
                                    cacheWidth:
                                        PhotoAdjustConfig.previewLongEdge,
                                    adjustments:
                                        grade.isNeutral ? null : grade,
                                    compareOriginal: session.comparing,
                                  );
                                  final preview = StraightenPhotoLayer(
                                    crop: cropping
                                        ? PhotoCrop.full
                                        : draftCrop,
                                    degrees: straighten,
                                    imageAspect: imageAspect,
                                    editingCrop: cropping,
                                    child: RepaintBoundary(child: rawPreview),
                                  );
                                  final stage = Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (cropping) ...[
                                        preview,
                                        PhotoCropOverlay(
                                          session: session,
                                          path: path,
                                          version: version,
                                          fit: BoxFit.contain,
                                          interactive: true,
                                          onChromeSecondaryTap: (global) =>
                                              _showBackdropMenu(
                                            context,
                                            session,
                                            global,
                                          ),
                                        ),
                                      ] else if (useFit)
                                        preview
                                      else
                                        LayoutBuilder(
                                          builder: (context, zoomConstraints) {
                                            final vp = Size(
                                              zoomConstraints.maxWidth,
                                              zoomConstraints.maxHeight,
                                            );
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              onZoomViewport(vp);
                                            });
                                            Widget viewer = InteractiveViewer(
                                              transformationController:
                                                  zoomTransform,
                                              minScale: 0.10,
                                              maxScale: 8,
                                              // Hand pans; scroll / Z-tool clicks
                                              // change scale (dropdown is 25%).
                                              panEnabled: handActive,
                                              scaleEnabled: false,
                                              onInteractionUpdate: (_) =>
                                                  onZoomInteraction(),
                                              onInteractionEnd: (_) =>
                                                  onZoomInteraction(),
                                              child: Center(child: preview),
                                            );
                                            if (zoomToolActive) {
                                              viewer = MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.zoomIn,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.translucent,
                                                  onDoubleTap: () =>
                                                      onZoomScaleChanged(null),
                                                  // onTap so double-tap can still win.
                                                  onTap: () {
                                                    onZoomToolTap(
                                                      zoomOut: HardwareKeyboard
                                                          .instance
                                                          .isAltPressed,
                                                    );
                                                  },
                                                  child: viewer,
                                                ),
                                              );
                                            } else if (handActive) {
                                              // Double-tap on the hand tool
                                              // must sit here — InteractiveViewer
                                              // swallows the outer stage detector.
                                              viewer = MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.grab,
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onDoubleTap: () =>
                                                      onZoomScaleChanged(null),
                                                  child: viewer,
                                                ),
                                              );
                                            }
                                            return viewer;
                                          },
                                        ),
                                      if (session.comparing)
                                        const Positioned(
                                          left: 12,
                                          top: 12,
                                          child: _BeforeBadge(),
                                        ),
                                    ],
                                  );
                                  final padded = Padding(
                                    padding: EdgeInsets.all(inset),
                                    child: stage,
                                  );
                                  final body = turns == 0
                                      ? padded
                                      : Center(
                                          child: RotatedBox(
                                            quarterTurns: turns,
                                            child: SizedBox(
                                              width: odd
                                                  ? constraints.maxHeight
                                                  : constraints.maxWidth,
                                              height: odd
                                                  ? constraints.maxWidth
                                                  : constraints.maxHeight,
                                              child: Padding(
                                                padding: EdgeInsets.all(inset),
                                                child: stage,
                                              ),
                                            ),
                                          ),
                                        );
                                  return GestureDetector(
                                    // Translucent so crop pan/resize on the
                                    // overlay wins the arena for primary drags.
                                    behavior: HitTestBehavior.translucent,
                                    onDoubleTap: cropping
                                        ? null
                                        : () => onZoomScaleChanged(null),
                                    onSecondaryTapUp: (details) {
                                      // Ignore right-clicks on the photo /
                                      // crop mask — only stage chrome.
                                      if (photoHit.contains(
                                        details.localPosition,
                                      )) {
                                        return;
                                      }
                                      _showBackdropMenu(
                                        context,
                                        session,
                                        details.globalPosition,
                                      );
                                    },
                                    child: body,
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    path == null
                                        ? ''
                                        : controller.currentFileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: FfTokens.fontFamily,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: FfTokens.nocturneTx,
                                    ),
                                  ),
                                ),
                                if (dirty) ...[
                                  const SizedBox(width: 12),
                                  const _EditedMark(),
                                ],
                              ],
                            ),
                          ),
                          _SaveButton(
                            saving: saving,
                            enabled: path != null && !saving,
                            onPressed: onDone,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cropping && path != null) ...[
                            _CropRatioDropdown(
                              selected: session.aspectFor(path),
                              onSelected: (aspect) =>
                                  session.chooseAspect(path, aspect),
                              onSwap: () => session.swapOrientation(path),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _CropBarButton(
                            active: cropping,
                            enabled: path != null && !saving,
                            onTap:
                                path == null || saving ? null : onToggleCrop,
                          ),
                          const SizedBox(width: 8),
                          _StageNavToolButton(
                            icon: PhosphorIconsRegular.magnifyingGlass,
                            tip: 'Zoom tool (Z) — click in, ⌥ click out',
                            kbd: 'Z',
                            active: zoomToolActive,
                            enabled: path != null && !saving,
                            onTap: path == null || saving
                                ? null
                                : onSelectZoomTool,
                          ),
                          const SizedBox(width: 8),
                          PhotoRotateButtons(
                            session: session,
                            controller: controller,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fitted photo AABB inside the stage (letterbox around this is chrome).
Rect _stagePhotoHitRect({
  required Size stageSize,
  required double inset,
  required double imageAspect,
  required double straightenDegrees,
}) {
  if (stageSize.isEmpty) return Rect.zero;
  final inner = Rect.fromLTWH(
    inset,
    inset,
    math.max(0, stageSize.width - inset * 2),
    math.max(0, stageSize.height - inset * 2),
  );
  if (inner.isEmpty) return Rect.zero;
  final aspect = imageAspect <= 0 ? 1.5 : imageAspect;
  final upright = containRect(Size(aspect, 1), inner.size);
  final rad = straightenDegrees * math.pi / 180.0;
  final aabb = rad.abs() <= 1e-6 ? upright : rotatedAabb(upright, rad);
  if (aabb.isEmpty) return Rect.zero;
  return aabb.shift(inner.topLeft);
}

Future<void> _showBackdropMenu(
  BuildContext context,
  PhotoEditSession session,
  Offset globalPosition,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
  final selected = await showMenu<PhotoEditBackdrop>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlaySize.width - globalPosition.dx,
      overlaySize.height - globalPosition.dy,
    ),
    color: const Color(0xFF1A1E24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    // Drop the default ~112px menu min width — just the swatch row.
    constraints: const BoxConstraints(),
    items: [
      PopupMenuItem<PhotoEditBackdrop>(
        enabled: false,
        height: 0,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < PhotoEditBackdrop.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _BackdropSwatch(
                  option: PhotoEditBackdrop.values[i],
                  selected:
                      session.backdrop == PhotoEditBackdrop.values[i],
                  onTap: () => Navigator.of(context)
                      .pop(PhotoEditBackdrop.values[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
  if (selected == null) return;
  session.setBackdrop(selected);
}

class _BackdropSwatch extends StatelessWidget {
  const _BackdropSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PhotoEditBackdrop option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = option.color.computeLuminance() > 0.72;
    return Tooltip(
      message: option.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Ink(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: option.color,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected
                    ? (light ? const Color(0xFF111111) : Colors.white)
                    : (light
                        ? const Color(0x66000000)
                        : const Color(0x55FFFFFF)),
                width: selected ? 2.2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeforeBadge extends StatelessWidget {
  const _BeforeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xD1101418),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIconsRegular.eye,
            size: 13,
            color: FfTokens.nocturneTx,
          ),
          SizedBox(width: 6),
          Text(
            'Before',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FfTokens.nocturneTx,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditedMark extends StatelessWidget {
  const _EditedMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(
          PhosphorIconsFill.circle,
          size: 8,
          color: FfTokens.gold,
        ),
        SizedBox(width: 5),
        Text(
          'Edited',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: FfTokens.gold,
          ),
        ),
      ],
    );
  }
}

class _ZoomToggle extends StatelessWidget {
  const _ZoomToggle({
    required this.scale,
    required this.presets,
    required this.onChanged,
    this.enabled = true,
  });

  /// `null` = Fit.
  final double? scale;
  final List<double> presets;
  final ValueChanged<double?> onChanged;
  final bool enabled;

  static const _fitToken = '__fit__';

  static String _labelFor(double scale) {
    if ((scale - 1.0).abs() < 0.005) return '100%';
    final pct = (scale * 100).round();
    return '$pct%';
  }

  bool _matches(double preset) {
    final s = scale;
    if (s == null) return false;
    return (s - preset).abs() <= 0.02 ||
        (preset >= 0.99 && (s - preset).abs() <= 0.04);
  }

  String get _buttonLabel {
    final s = scale;
    if (s == null) return 'Fit';
    for (final preset in presets) {
      if (_matches(preset)) return _labelFor(preset);
    }
    return _labelFor(s);
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final selectedValue = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
        Offset.zero & overlay.size,
      ),
      color: FfTokens.nocturneSf,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: FfTokens.nocturneLn),
      ),
      constraints: const BoxConstraints(minWidth: 96),
      items: [
        PopupMenuItem<String>(
          value: _fitToken,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _ZoomMenuRow(
            label: 'Fit',
            selected: scale == null,
          ),
        ),
        for (final preset in presets)
          PopupMenuItem<String>(
            value: '$preset',
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _ZoomMenuRow(
              label: _labelFor(preset),
              selected: scale != null && _matches(preset),
            ),
          ),
      ],
    );
    if (selectedValue == null) return;
    if (selectedValue == _fitToken) {
      onChanged(null);
      return;
    }
    onChanged(double.tryParse(selectedValue));
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Zoom',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: FfTokens.nocturneSunken,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: enabled ? () => _open(context) : null,
            borderRadius: BorderRadius.circular(9),
            hoverColor: FfTokens.nocturneHv,
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _buttonLabel,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FfTokens.nocturneTx,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const PhosphorIcon(
                    PhosphorIconsRegular.caretDown,
                    size: 12,
                    color: FfTokens.nocturneT2,
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

class _ZoomMenuRow extends StatelessWidget {
  const _ZoomMenuRow({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: selected
              ? const PhosphorIcon(
                  PhosphorIconsRegular.check,
                  size: 14,
                  color: FfTokens.nocturneAc,
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: FfTokens.nocturneTx,
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.saving,
    required this.enabled,
    required this.onPressed,
  });

  final bool saving;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onPressed() : null,
          borderRadius: BorderRadius.circular(9),
          child: Ink(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xF24A7A96)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF243848),
                  Color(0xFF15242E),
                  Color(0xFF0E181F),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x384A7A96),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (saving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else ...[
                  const PhosphorIcon(
                    PhosphorIconsRegular.floppyDisk,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Save',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

/// Secondary Crop toggle for the photo bottom bar.
class _CropBarButton extends StatelessWidget {
  const _CropBarButton({
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: active
            ? FfTokens.nocturneAccentSoft
            : FfTokens.nocturneSf,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          hoverColor: FfTokens.nocturneHv,
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: active
                    ? FfTokens.nocturneAccentEdge
                    : FfTokens.nocturneLn,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.crop,
                  size: 15,
                  color: active ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                ),
                const SizedBox(width: 7),
                const Text(
                  'Crop',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.nocturneTx,
                  ),
                ),
                const SizedBox(width: 7),
                _KbdChip('C', emphasized: active),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hand / Zoom tool chip beside Crop.
class _StageNavToolButton extends StatelessWidget {
  const _StageNavToolButton({
    required this.icon,
    required this.tip,
    required this.kbd,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final String kbd;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: active
              ? FfTokens.nocturneAccentSoft
              : FfTokens.nocturneSf,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            hoverColor: FfTokens.nocturneHv,
            child: Container(
              height: 34,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: active
                      ? FfTokens.nocturneAccentEdge
                      : FfTokens.nocturneLn,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    icon,
                    size: 15,
                    color: active ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                  ),
                  const SizedBox(width: 6),
                  _KbdChip(kbd, emphasized: active),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aspect-ratio menu for crop mode (opens upward).
class _CropRatioDropdown extends StatelessWidget {
  const _CropRatioDropdown({
    required this.selected,
    required this.onSelected,
    required this.onSwap,
  });

  final double? selected;
  final ValueChanged<double?> onSelected;
  final VoidCallback onSwap;

  static const _freeToken = '__free__';
  static const _swapToken = '__swap__';

  static const _choices = <(String, double?, String, Size?)>[
    ('Free', null, '', null),
    ('1:1', 1, 'Square', Size(12, 12)),
    ('4:5', 4 / 5, 'Portrait', Size(11, 14)),
    ('3:2', 3 / 2, '', Size(15, 10)),
    ('2:3', 2 / 3, '', Size(10, 15)),
    ('16:9', 16 / 9, 'Wide', Size(16, 9)),
  ];

  bool _isOn(double? value) {
    if (value == null) return selected == null;
    return selected != null && (selected! - value).abs() < 0.001;
  }

  String get _label {
    for (final choice in _choices) {
      if (_isOn(choice.$2)) return choice.$1;
    }
    return 'Free';
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    // Prefer above the trigger (bottom bar sits low on the stage).
    final selectedValue = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
        Offset.zero & overlay.size,
      ),
      color: FfTokens.nocturneSf,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: FfTokens.nocturneLn),
      ),
      items: [
        for (final choice in _choices)
          PopupMenuItem<String>(
            value: choice.$2 == null ? _freeToken : '${choice.$2}',
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _RatioMenuRow(
              label: choice.$1,
              descriptor: choice.$3,
              shape: choice.$4,
              selected: _isOn(choice.$2),
            ),
          ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem<String>(
          value: _swapToken,
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.swap,
                size: 14,
                color: FfTokens.nocturneT2,
              ),
              SizedBox(width: 10),
              Text(
                'Swap orientation',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: FfTokens.nocturneTx,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (selectedValue == null) return;
    if (selectedValue == _swapToken) {
      onSwap();
      return;
    }
    if (selectedValue == _freeToken) {
      onSelected(null);
      return;
    }
    onSelected(double.tryParse(selectedValue));
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Crop ratio',
      child: Material(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(9),
          hoverColor: FfTokens.nocturneHv,
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(
                  PhosphorIconsRegular.frameCorners,
                  size: 15,
                  color: FfTokens.nocturneT2,
                ),
                const SizedBox(width: 8),
                Text(
                  _label,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.nocturneTx,
                  ),
                ),
                const SizedBox(width: 8),
                const PhosphorIcon(
                  PhosphorIconsRegular.caretUpDown,
                  size: 13,
                  color: FfTokens.nocturneT2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatioMenuRow extends StatelessWidget {
  const _RatioMenuRow({
    required this.label,
    required this.descriptor,
    required this.shape,
    required this.selected,
  });

  final String label;
  final String descriptor;
  final Size? shape;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: selected
              ? const PhosphorIcon(
                  PhosphorIconsRegular.check,
                  size: 13,
                  color: Color(0xFF5A8EAB),
                )
              : null,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 18,
          child: Center(
            child: shape == null
                ? const PhosphorIcon(
                    PhosphorIconsRegular.dotsNine,
                    size: 14,
                    color: FfTokens.nocturneT2,
                  )
                : Container(
                    width: shape!.width,
                    height: shape!.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF5A8EAB)
                            : FfTokens.nocturneT2,
                        width: 1.5,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : FfTokens.nocturneTx,
          ),
        ),
        if (descriptor.isNotEmpty) ...[
          const Spacer(),
          Text(
            descriptor,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.nocturneT3,
            ),
          ),
        ],
      ],
    );
  }
}

class _EditFilmstripBar extends StatelessWidget {
  const _EditFilmstripBar({
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final total = controller.imagePaths.length;
        final index = total == 0 ? 0 : controller.currentIndex + 1;
        return Container(
          height: 92,
          decoration: BoxDecoration(
            color: FfTokens.nocturneEl,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FfTokens.nocturneSunken,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$index / $total',
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.nocturneT2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MobilePhotoFilmstrip(
                  controller: controller,
                  editSession: session,
                  editStyle: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Slider sheet that slides up over the thumbnail strip or grid.
class PhotoEditCover extends StatelessWidget {
  const PhotoEditCover({
    super.key,
    required this.session,
    required this.controller,
    required this.child,
    this.sheetOnly = false,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  /// Thumbnail strip or grid that stays underneath the sheet.
  final Widget child;

  /// When true, the sheet is only as tall as the sliders and anchors to the
  /// top of [child] (mobile filmstrip). Otherwise it covers [child] entirely.
  final bool sheetOnly;

  @override
  Widget build(BuildContext context) {
    return _CompareKeyBinder(
      session: session,
      controller: controller,
      child: Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: sheetOnly ? null : 0,
            child: AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final open = session.editing;
                return IgnorePointer(
                  ignoring: !open,
                  child: ClipRect(
                    child: AnimatedSlide(
                      offset: open ? Offset.zero : const Offset(0, 1),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: sheetOnly
                          ? _PhotoEditSheet(
                              session: session,
                              controller: controller,
                            )
                          : ColoredBox(
                              color: (Theme.of(context).extension<FfTokens>() ??
                                      FfTokens.dark)
                                  .surface,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: _PhotoEditSheet(
                                  session: session,
                                  controller: controller,
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditSidePanel extends StatelessWidget {
  const _EditSidePanel({
    required this.session,
    required this.controller,
    required this.tool,
    required this.onClose,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final _EditTool tool;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final adjustments = session.adjustmentsFor(path);
        final saving = session.saving;
        final dirty = path != null && session.isDirty(path);
        final enabled = path != null && !saving;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: FfTokens.nocturneEl,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Edit photo',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: FfTokens.nocturneTx,
                        ),
                      ),
                    ),
                    _IconChip(
                      icon: PhosphorIconsRegular.x,
                      tip: 'Close (Esc)',
                      onTap: onClose,
                    ),
                  ],
                ),
              ),
              if (path != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: PhotoHistogram(
                    session: session,
                    controller: controller,
                    tall: true,
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  children: [
                    if (session.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          session.error!,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            color: FfTokens.danger,
                          ),
                        ),
                      ),
                    if (path != null) ...[
                      // Angle stays available while cropping (corner-drag also works).
                      if (tool == _EditTool.crop) ...[
                        const _SectionLabel('Crop'),
                        _GradeSlider(
                          label: 'Angle',
                          value: session.straightenFor(path),
                          min: straightenMinDegrees,
                          max: straightenMaxDegrees,
                          displayScale: 1,
                          fractionDigits: 1,
                          enabled: enabled,
                          editSession: session,
                          editPath: path,
                          onChanged: (v) => session.setStraighten(path, v),
                        ),
                      ],
                      const _SectionLabel('White balance'),
                      _GradeSlider(
                        label: 'Temp',
                        value: adjustments.temperature,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        track: _GradeTrack.temp,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(temperature: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Tint',
                        value: adjustments.tint,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        track: _GradeTrack.tint,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(tint: v),
                        ),
                      ),
                      const _SectionLabel('Light'),
                      _GradeSlider(
                        label: 'Exposure',
                        value: adjustments.exposure,
                        min: PhotoAdjustConfig.exposureStopsMin,
                        max: PhotoAdjustConfig.exposureStopsMax,
                        fractionDigits: 2,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(exposure: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Contrast',
                        value: adjustments.contrast,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(contrast: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Highlights',
                        value: adjustments.highlights,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(highlights: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Shadows',
                        value: adjustments.shadows,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(shadows: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Whites',
                        value: adjustments.whites,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(whites: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Blacks',
                        value: adjustments.blacks,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(blacks: v),
                        ),
                      ),
                      const _SectionLabel('Color'),
                      _GradeSlider(
                        label: 'Vibrance',
                        value: adjustments.vibrance,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(vibrance: v),
                        ),
                      ),
                      _GradeSlider(
                        label: 'Saturation',
                        value: adjustments.saturation,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        enabled: enabled,
                        editSession: session,
                        editPath: path,
                        onChanged: (v) => session.update(
                          path,
                          adjustments.copyWith(saturation: v),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: FfTokens.nocturneLn),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Text(
                            'Hold',
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              color: FfTokens.nocturneT3,
                            ),
                          ),
                          SizedBox(width: 6),
                          _KbdChip('\\'),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'for before',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 12,
                                color: FfTokens.nocturneT3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconChip(
                      icon: PhosphorIconsRegular.arrowUUpLeft,
                      tip: 'Undo (⌘Z)',
                      onTap: path != null &&
                              session.canUndo(path) &&
                              !saving
                          ? () => session.undo(path)
                          : null,
                    ),
                    _IconChip(
                      icon: PhosphorIconsRegular.arrowUUpRight,
                      tip: 'Redo (⇧⌘Z)',
                      onTap: path != null &&
                              session.canRedo(path) &&
                              !saving
                          ? () => session.redo(path)
                          : null,
                    ),
                    _GhostButton(
                      label: 'Reset all',
                      icon: PhosphorIconsRegular.arrowCounterClockwise,
                      enabled: dirty && !saving,
                      onPressed: path == null || saving
                          ? null
                          : () => session.reset(path),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: FfTokens.nocturneT3,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: ColoredBox(
              color: FfTokens.nocturneLn,
              child: SizedBox(height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.tip,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tip,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: PhosphorIcon(
                  icon,
                  size: 16,
                  color: FfTokens.nocturneT2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KbdChip extends StatelessWidget {
  const _KbdChip(this.label, {this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(0x404A7A96) // nocturneAc @ ~25%
            : FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: FfTokens.nocturneT2,
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(icon, size: 14, color: FfTokens.nocturneT2),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.nocturneT2,
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

/// Compact sheet used by [PhotoEditCover] (mobile overlay).
class _PhotoEditSheet extends StatelessWidget {
  const _PhotoEditSheet({
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FfTokens.nocturneEl,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 420,
          child: _EditSidePanel(
            session: session,
            controller: controller,
            tool: session.cropping ? _EditTool.crop : _EditTool.adjust,
            onClose: () {
              if (session.editing) session.toggleEditing();
            },
          ),
        ),
      ),
    );
  }
}


enum _GradeTrack { plain, temp, tint }

class _GradeSlider extends StatefulWidget {
  const _GradeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.displayScale = 100,
    this.fractionDigits = 0,
    this.track = _GradeTrack.plain,
    this.editSession,
    this.editPath,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  /// Multiplier from the stored value to the number shown and typed.
  final double displayScale;
  final int fractionDigits;
  final _GradeTrack track;

  /// When set, slider drags checkpoint undo history once per gesture.
  final PhotoEditSession? editSession;
  final String? editPath;

  @override
  State<_GradeSlider> createState() => _GradeSliderState();
}

class _GradeSliderState extends State<_GradeSlider> {
  late final TextEditingController _text;
  late final FocusNode _focus;
  DateTime? _lastSliderTap;
  Offset? _lastSliderTapAt;
  bool _resetAfterPointer = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _display(widget.value));
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _GradeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _text.text = _display(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
    if (mounted) setState(() {});
  }

  String _display(double stored) {
    return _signed(stored * widget.displayScale, digits: widget.fractionDigits);
  }

  void _beginEdit() {
    final session = widget.editSession;
    final path = widget.editPath;
    if (session == null || path == null) return;
    session.beginGesture(path);
  }

  void _endEdit() {
    widget.editSession?.endGesture();
  }

  void _reset() {
    if (!widget.enabled) return;
    _beginEdit();
    widget.onChanged(0);
    _text.text = _display(0);
    _endEdit();
  }

  void _commit() {
    if (!widget.enabled) {
      _text.text = _display(widget.value);
      return;
    }
    final parsed = double.tryParse(_text.text.trim().replaceAll('+', ''));
    if (parsed == null) {
      _text.text = _display(widget.value);
      return;
    }
    final places = widget.fractionDigits;
    final rounded = places == 0
        ? parsed.roundToDouble()
        : (parsed * _pow10(places)).roundToDouble() / _pow10(places);
    final stored =
        (rounded / widget.displayScale).clamp(widget.min, widget.max);
    _beginEdit();
    widget.onChanged(stored);
    _endEdit();
    _text.text = _display(stored);
  }

  double _pow10(int places) {
    var scale = 1.0;
    for (var i = 0; i < places; i++) {
      scale *= 10;
    }
    return scale;
  }

  @override
  Widget build(BuildContext context) {
    final changed = widget.value.abs() > 1e-9;
    final labelColor =
        changed ? FfTokens.nocturneTx : FfTokens.nocturneT2;
    final t = ((widget.value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);
    final gradient = switch (widget.track) {
      _GradeTrack.temp => const LinearGradient(
          colors: [Color(0xFF3E6A9A), Color(0xFF8A8F94), Color(0xFFC9A24A)],
        ),
      _GradeTrack.tint => const LinearGradient(
          colors: [Color(0xFF4E9A5E), Color(0xFF8A8F94), Color(0xFFA65AA0)],
        ),
      _GradeTrack.plain => null,
    };

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: GestureDetector(
              onDoubleTap: widget.enabled ? _reset : null,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (!widget.enabled) return;
                final now = DateTime.now();
                final previous = _lastSliderTap;
                final previousAt = _lastSliderTapAt;
                _lastSliderTap = now;
                _lastSliderTapAt = event.localPosition;
                if (previous == null || previousAt == null) return;
                final closeInTime =
                    now.difference(previous).inMilliseconds < 350;
                final closeInPlace =
                    (event.localPosition - previousAt).distance < 18;
                _resetAfterPointer = closeInTime && closeInPlace;
              },
              onPointerUp: (_) {
                if (!_resetAfterPointer) return;
                _resetAfterPointer = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _reset();
                });
              },
              child: SizedBox(
                height: 18,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final fillLeft = math.min(0.5, t) * w;
                    final fillWidth = (t - 0.5).abs() * w;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (gradient != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: gradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          )
                        else ...[
                          Positioned(
                            left: 0,
                            right: 0,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: FfTokens.nocturneLn2,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Positioned(
                            left: fillLeft,
                            width: fillWidth,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: FfTokens.nocturneAc,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const Positioned(
                            child: SizedBox(
                              width: 1,
                              height: 9,
                              child: ColoredBox(color: FfTokens.nocturneLn2),
                            ),
                          ),
                        ],
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            trackShape: const _InvisibleSliderTrack(),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                            thumbColor: FfTokens.nocturneTx,
                            overlayColor: FfTokens.nocturneAc
                                .withValues(alpha: 0.22),
                          ),
                          child: Slider(
                            value:
                                widget.value.clamp(widget.min, widget.max),
                            min: widget.min,
                            max: widget.max,
                            onChangeStart: widget.enabled
                                ? (_) => _beginEdit()
                                : null,
                            onChanged:
                                widget.enabled ? widget.onChanged : null,
                            onChangeEnd: widget.enabled
                                ? (_) => _endEdit()
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: widget.enabled,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: labelColor,
              ),
              cursorColor: FfTokens.nocturneAc,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: FfTokens.nocturneSunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: FfTokens.nocturneAc),
                ),
              ),
              onSubmitted: (_) {
                _commit();
                _focus.unfocus();
              },
              onTapOutside: (_) => _focus.unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvisibleSliderTrack extends SliderTrackShape {
  const _InvisibleSliderTrack();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 3;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {}
}

String _signed(double value, {int digits = 0}) {
  final rounded = digits == 0 ? value.roundToDouble() : value;
  final text = digits == 0
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(digits);
  if (rounded > 0) return '+$text';
  return text;
}
