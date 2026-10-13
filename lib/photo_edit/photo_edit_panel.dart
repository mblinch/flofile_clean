import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../screens/caption_v2/data/caption_v2_controller.dart';
import '../services/admin_service.dart';
import '../screens/caption_v2/widgets/mobile_photo_filmstrip.dart';
import '../screens/caption_v2/widgets/photo_preview_bar.dart';
import '../theme/ff_tokens.dart';
import '../widgets/oriented_file_preview.dart';
import 'photo_adjustments.dart';
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
        if (!AdminService.isCurrentUserAdminSync()) {
          return const SizedBox.shrink();
        }
        final path = controller.currentPath;
        final on = session.editing;
        final dirty = session.isDirty(path);
        final enabled = path != null && !session.saving;
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
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: compact ? 4 : 6,
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
                        size: compact ? 13 : 15,
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

/// Full-window edit mode: sliders on the left, the frame large, filmstrip below.
class PhotoEditWorkspace extends StatelessWidget {
  const PhotoEditWorkspace({
    super.key,
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return ColoredBox(
      color: tokens.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final railWidth = constraints.maxWidth < 760 ? 216.0 : 280.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: railWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          border: Border(
                            right: BorderSide(color: tokens.divider),
                          ),
                        ),
                        child: _PhotoEditSheet(
                          session: session,
                          controller: controller,
                          rail: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _EditStage(
                        session: session,
                        controller: controller,
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  border: Border(top: BorderSide(color: tokens.divider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: MobilePhotoFilmstrip(controller: controller),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditStage extends StatelessWidget {
  const _EditStage({
    required this.session,
    required this.controller,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final grade = session.adjustmentsFor(path);
        final cropping = session.cropping;
        final viewCrop = path == null || cropping ? null : session.cropFor(path);
        final version = path == null ? 0 : controller.imageContentStamp(path);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (path != null)
                    PhotoPreviewInfoBar(
                      controller: controller,
                      editSession: session,
                    ),
                  Expanded(
                    child: path == null
                        ? Center(
                            child: PhosphorIcon(
                              PhosphorIconsRegular.image,
                              color: tokens.textTertiary,
                              size: 36,
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              OrientedFilePreview(
                                key: ValueKey('edit-stage-$path-$version'),
                                path: path,
                                version: version,
                                fit: BoxFit.contain,
                                cacheWidth: 1800,
                                adjustments: grade.isNeutral ? null : grade,
                                viewCrop: viewCrop != null && !viewCrop.isFull
                                    ? viewCrop
                                    : null,
                              ),
                              if (cropping)
                                PhotoCropOverlay(
                                  session: session,
                                  path: path,
                                  version: version,
                                  fit: BoxFit.contain,
                                ),
                            ],
                          ),
                  ),
                  if (path != null)
                    PhotoPreviewActionBar(
                      controller: controller,
                      path: path,
                    ),
                ],
              ),
            ),
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
    return Stack(
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
    );
  }
}

class _PhotoEditSheet extends StatelessWidget {
  const _PhotoEditSheet({
    required this.session,
    required this.controller,
    this.rail = false,
  });

  final PhotoEditSession session;
  final CaptionV2Controller controller;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return AnimatedBuilder(
      animation: Listenable.merge([session, controller]),
      builder: (context, _) {
        final path = controller.currentPath;
        final adjustments = session.adjustmentsFor(path);
        final saving = session.saving;
        final canApply = path != null &&
            session.isDirty(path) &&
            !saving &&
            !(controller.transmitting && controller.transmittingPath == path);
        final controls = Padding(
          padding: EdgeInsets.fromLTRB(rail ? 12 : 12, rail ? 12 : 8, rail ? 12 : 8, rail ? 16 : 10),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Edit photo',
                        style: tokens.labelStyle.copyWith(color: tokens.text),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: path == null || saving
                            ? null
                            : session.toggleCropping,
                        child: Text(
                          'Crop',
                          style: tokens.metaStyle.copyWith(
                            color: session.cropping
                                ? tokens.accent
                                : tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: path == null || saving
                            ? null
                            : () => session.reset(path),
                        child: Text(
                          'Reset',
                          style: tokens.metaStyle.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: canApply ? () => session.apply(path) : null,
                        child: saving
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.accent,
                                ),
                              )
                            : Text(
                                'Apply',
                                style: tokens.metaStyle.copyWith(
                                  color: canApply
                                      ? tokens.accent
                                      : tokens.textTertiary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (session.cropping && path != null) ...[
                    const SizedBox(height: 2),
                    _CropAspectRow(
                      selected: session.aspectFor(path),
                      tokens: tokens,
                      onSelected: (aspect) =>
                          session.chooseAspect(path, aspect),
                    ),
                  ],
                  if (session.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          session.error!,
                          style: tokens.metaStyle.copyWith(
                            color: FfTokens.danger,
                          ),
                        ),
                      ),
                    ),
                  if (path != null) ...[
                    PhotoHistogram(
                      session: session,
                      controller: controller,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _GradeSlider(
                    label: 'Exposure',
                    value: adjustments.exposure,
                    min: -5,
                    max: 5,
                    fractionDigits: 1,
                    displayScale: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(exposure: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Contrast',
                    value: adjustments.contrast,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(contrast: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Shadows',
                    value: adjustments.shadows,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(shadows: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Highlights',
                    value: adjustments.highlights,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(highlights: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Whites',
                    value: adjustments.whites,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(whites: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Blacks',
                    value: adjustments.blacks,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(blacks: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Color temp',
                    value: adjustments.temperature,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(temperature: v),
                    ),
                  ),
                  _GradeSlider(
                    label: 'Tint',
                    value: adjustments.tint,
                    min: -1,
                    max: 1,
                    tokens: tokens,
                    enabled: path != null && !saving,
                    onChanged: (v) => session.update(
                      path!,
                      adjustments.copyWith(tint: v),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          session.cropping
                              ? 'Drag the frame. Double-click or Enter shows the crop.'
                              : 'Apply saves into the JPEG and keeps the caption.',
                        style: tokens.metaStyle.copyWith(
                          color: tokens.textTertiary,
                          fontSize: tokens.textSizeMicro,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
        if (rail) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [controls],
          );
        }
        return Material(
          color: tokens.surface,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.divider)),
            ),
            child: controls,
          ),
        );
      },
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

class _GradeSlider extends StatefulWidget {
  const _GradeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.tokens,
    required this.enabled,
    required this.onChanged,
    this.displayScale = 100,
    this.fractionDigits = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final FfTokens tokens;
  final bool enabled;
  final ValueChanged<double> onChanged;

  /// Multiplier from the stored value to the number shown and typed.
  final double displayScale;
  final int fractionDigits;

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
    final stored = (rounded / widget.displayScale).clamp(widget.min, widget.max);
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
    final tokens = widget.tokens;
    final editing = _focus.hasFocus;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: GestureDetector(
              onDoubleTap: widget.enabled ? _reset : null,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
          ),
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
                final closeInTime = now.difference(previous).inMilliseconds < 350;
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
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: tokens.accent,
                  inactiveTrackColor: tokens.divider,
                  thumbColor: tokens.text,
                  overlayColor: tokens.accent.withValues(alpha: 0.16),
                ),
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  onChanged: widget.enabled ? widget.onChanged : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: widget.enabled,
              textAlign: TextAlign.right,
              style: tokens.monoMetaStyle.copyWith(color: tokens.text),
              cursorColor: tokens.accent,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: editing,
                fillColor: tokens.sunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: tokens.accent),
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

String _signed(double value, {int digits = 0}) {
  final rounded = digits == 0 ? value.roundToDouble() : value;
  final text = digits == 0
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(digits);
  if (rounded > 0) return '+$text';
  return text;
}
