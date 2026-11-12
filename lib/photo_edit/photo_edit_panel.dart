import 'dart:math' as math;

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

/// Full-window edit mode: 288px tools rail, photo panel, filmstrip below.
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
  bool _zoomFit = true;

  _EditTool get _tool {
    return widget.session.cropping ? _EditTool.crop : _EditTool.adjust;
  }

  void _selectTool(_EditTool tool) {
    final s = widget.session;
    switch (tool) {
      case _EditTool.adjust:
        if (s.cropping) s.finishCropping();
      case _EditTool.crop:
        if (!s.cropping) s.toggleCropping();
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final controller = widget.controller;
    return _CompareKeyBinder(
      session: session,
      child: ColoredBox(
        color: FfTokens.nocturneBg,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 288,
                child: _EditSidePanel(
                  session: session,
                  controller: controller,
                  tool: _tool,
                  onSelectTool: _selectTool,
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
                        zoomFit: _zoomFit,
                        onZoomFitChanged: (fit) =>
                            setState(() => _zoomFit = fit),
                        onDone: _done,
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
class _CompareKeyBinder extends StatefulWidget {
  const _CompareKeyBinder({
    required this.session,
    required this.child,
  });

  final PhotoEditSession session;
  final Widget child;

  @override
  State<_CompareKeyBinder> createState() => _CompareKeyBinderState();
}

class _CompareKeyBinderState extends State<_CompareKeyBinder> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    widget.session.setComparing(false);
    super.dispose();
  }

  bool _editingTextField() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!widget.session.editing || _editingTextField()) return false;
    if (event.logicalKey != LogicalKeyboardKey.backslash) return false;
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

  @override
  Widget build(BuildContext context) => widget.child;
}

class _EditStage extends StatelessWidget {
  const _EditStage({
    required this.session,
    required this.controller,
    required this.zoomFit,
    required this.onZoomFitChanged,
    required this.onDone,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final bool zoomFit;
  final ValueChanged<bool> onZoomFitChanged;
  final Future<void> Function() onDone;

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
                        fit: zoomFit,
                        onChanged: onZoomFitChanged,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FfTokens.photoHeader,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: path == null
                          ? Center(
                              child: PhosphorIcon(
                                PhosphorIconsRegular.image,
                                color: FfTokens.nocturneT3,
                                size: 36,
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final odd = turns.isOdd;
                                // Keep full-frame framing in the edit stage so
                                // leaving crop doesn't jump-zoom into the crop.
                                // Crop + straighten still apply on Done.
                                final rawPreview = OrientedFilePreview(
                                  key: ValueKey(
                                    'edit-stage-$path-$version',
                                  ),
                                  path: path,
                                  version: version,
                                  fit: zoomFit
                                      ? BoxFit.contain
                                      : BoxFit.none,
                                  cacheWidth:
                                      PhotoAdjustConfig.previewLongEdge,
                                  adjustments:
                                      grade.isNeutral ? null : grade,
                                  compareOriginal: session.comparing,
                                );
                                final preview = StraightenPhotoLayer(
                                  crop: PhotoCrop.full,
                                  degrees: straighten,
                                  imageAspect: imageAspect,
                                  editingCrop: true,
                                  child: rawPreview,
                                );
                                final showCropFrame =
                                    cropping || !draftCrop.isFull;
                                final stage = Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    zoomFit
                                        ? preview
                                        : InteractiveViewer(
                                            minScale: 0.5,
                                            maxScale: 8,
                                            child: Center(child: preview),
                                          ),
                                    if (showCropFrame)
                                      PhotoCropOverlay(
                                        session: session,
                                        path: path,
                                        version: version,
                                        fit: BoxFit.contain,
                                        interactive: cropping,
                                      ),
                                    if (session.comparing)
                                      const Positioned(
                                        left: 12,
                                        top: 12,
                                        child: _BeforeBadge(),
                                      ),
                                  ],
                                );
                                if (turns == 0) return stage;
                                return Center(
                                  child: RotatedBox(
                                    quarterTurns: turns,
                                    child: SizedBox(
                                      width: odd
                                          ? constraints.maxHeight
                                          : constraints.maxWidth,
                                      height: odd
                                          ? constraints.maxWidth
                                          : constraints.maxHeight,
                                      child: stage,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  child: Row(
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
                              const SizedBox(width: 10),
                              const _EditedMark(),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _DoneButton(
                        saving: saving,
                        enabled: path != null && !saving,
                        onPressed: onDone,
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
  const _ZoomToggle({required this.fit, required this.onChanged});

  final bool fit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool on, VoidCallback tap) {
      return GestureDetector(
        onTap: tap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? FfTokens.nocturneTx : FfTokens.nocturneT2,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('Fit', fit, () => onChanged(true)),
          chip('100%', !fit, () => onChanged(false)),
        ],
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
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
                    PhosphorIconsRegular.check,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '↵',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xBFFFFFFF),
                      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                '$index / $total',
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  color: FfTokens.nocturneT3,
                ),
              ),
              const SizedBox(width: 8),
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
    required this.onSelectTool,
    required this.onClose,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final _EditTool tool;
  final ValueChanged<_EditTool> onSelectTool;
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _ToolSegment(
                  tool: tool,
                  onSelect: onSelectTool,
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
                    if (tool == _EditTool.crop && path != null) ...[
                      const _SectionLabel('Crop'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          PhotoRotateButtons(
                            session: session,
                            controller: controller,
                            compact: true,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CropAspectRow(
                              selected: session.aspectFor(path),
                              tokens: Theme.of(context).extension<FfTokens>() ??
                                  FfTokens.dark,
                              onSelected: (aspect) =>
                                  session.chooseAspect(path, aspect),
                            ),
                          ),
                        ],
                      ),
                      _GradeSlider(
                        label: 'Angle',
                        value: session.straightenFor(path),
                        min: straightenMinDegrees,
                        max: straightenMaxDegrees,
                        displayScale: 1,
                        fractionDigits: 1,
                        enabled: enabled,
                        onChanged: (v) => session.setStraighten(path, v),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Drag the frame. Use Angle to level the horizon. Double-click or Enter shows the crop.',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 12,
                          color: FfTokens.nocturneT3,
                        ),
                      ),
                    ] else if (path != null) ...[
                      const _SectionLabel('White balance'),
                      _GradeSlider(
                        label: 'Temp',
                        value: adjustments.temperature,
                        min: PhotoAdjustConfig.sliderUiMin,
                        max: PhotoAdjustConfig.sliderUiMax,
                        displayScale: 1,
                        track: _GradeTrack.temp,
                        enabled: enabled,
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
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              color: FfTokens.nocturneT3,
                            ),
                          ),
                          SizedBox(width: 6),
                          _KbdChip('\\'),
                          SizedBox(width: 6),
                          Text(
                            'for before',
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              color: FfTokens.nocturneT3,
                            ),
                          ),
                        ],
                      ),
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

class _ToolSegment extends StatelessWidget {
  const _ToolSegment({required this.tool, required this.onSelect});

  final _EditTool tool;
  final ValueChanged<_EditTool> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget seg({
      required _EditTool value,
      required IconData icon,
      required String label,
      String? kbd,
    }) {
      final on = tool == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(value),
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: on ? FfTokens.nocturneAccentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: on
                  ? Border.all(color: FfTokens.nocturneAccentEdge)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(
                  icon,
                  size: 14,
                  color: on ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? FfTokens.nocturneTx : FfTokens.nocturneT2,
                  ),
                ),
                if (kbd != null) ...[
                  const SizedBox(width: 6),
                  _KbdChip(kbd),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          seg(
            value: _EditTool.adjust,
            icon: PhosphorIconsRegular.slidersHorizontal,
            label: 'Adjust',
          ),
          seg(
            value: _EditTool.crop,
            icon: PhosphorIconsRegular.crop,
            label: 'Crop',
            kbd: 'C',
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
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
            onSelectTool: (tool) {
              switch (tool) {
                case _EditTool.adjust:
                  if (session.cropping) session.finishCropping();
                case _EditTool.crop:
                  if (!session.cropping) session.toggleCropping();
              }
            },
            onClose: () {
              if (session.editing) session.toggleEditing();
            },
          ),
        ),
      ),
    );
  }
}

class _CropAspectRow extends StatelessWidget {
  const _CropAspectRow({
    required this.selected,
    required this.tokens,
    required this.onSelected,
  });

  final double? selected;
  final FfTokens tokens;
  final ValueChanged<double?> onSelected;

  @override
  Widget build(BuildContext context) {
    const choices = <(String, double?)>[
      ('Free', null),
      ('1:1', 1),
      ('4:5', 4 / 5),
      ('3:2', 3 / 2),
      ('2:3', 2 / 3),
      ('16:9', 16 / 9),
    ];
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: choices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final choice = choices[index];
          final on = choice.$2 == null
              ? selected == null
              : selected != null && (selected! - choice.$2!).abs() < 0.001;
          return InkWell(
            onTap: () => onSelected(choice.$2),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? tokens.accent : tokens.sunken,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? tokens.accent : tokens.divider),
              ),
              child: Text(
                choice.$1,
                style: tokens.metaStyle.copyWith(
                  color: on ? tokens.inkOnAccent : tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          );
        },
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

  void _reset() {
    if (!widget.enabled) return;
    widget.onChanged(0);
    _text.text = _display(0);
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
    widget.onChanged(stored);
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
                            onChanged:
                                widget.enabled ? widget.onChanged : null,
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
