import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../photo_edit/photo_adjust_config.dart';
import '../../../photo_edit/photo_adjustments.dart';
import '../../../photo_edit/photo_crop_overlay.dart';
import '../../../photo_edit/photo_edit_session.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import 'mobile_design.dart';

/// Phone photo editor — layout from `design/mobile/screens/EditPhoto.dc.html`.
class MobileEditPhoto extends StatelessWidget {
  const MobileEditPhoto({
    super.key,
    required this.controller,
    required this.session,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, session]),
      builder: (context, _) {
        final path = controller.currentPath;
        final grade = session.adjustmentsFor(path);
        final name = controller.currentFileName;

        Future<void> save() async {
          if (path == null) return;
          await session.apply(path);
          if (session.editing) session.toggleEditing();
        }

        void cancel() {
          if (path != null && session.isDirty(path)) {
            session.reset(path);
          }
          if (session.editing) session.toggleEditing();
        }

        return ColoredBox(
          color: MobileDesign.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: MobileDesign.divider),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: cancel,
                          style: TextButton.styleFrom(
                            foregroundColor: MobileDesign.text,
                            minimumSize: const Size(44, 44),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Edit photo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: MobileDesign.text,
                            ),
                          ),
                        ),
                        Material(
                          color: MobileDesign.selectedBg,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: path == null || session.saving ? null : save,
                            borderRadius: BorderRadius.circular(8),
                            child: const SizedBox(
                              height: 36,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Center(
                                  child: Text(
                                    'Save',
                                    style: TextStyle(
                                      fontFamily: MobileDesign.font,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: MobileDesign.selectedFg,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 260,
                child: ColoredBox(
                  color: Colors.black,
                  child: path == null
                      ? const SizedBox.shrink()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            OrientedFilePreview(
                              key: ValueKey(
                                'mobile-edit-$path-${controller.imageContentStamp(path)}',
                              ),
                              path: path,
                              version: controller.imageContentStamp(path),
                              fit: session.cropping
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                              cacheWidth: 780,
                              adjustments: session.comparing || grade.isNeutral
                                  ? null
                                  : grade,
                              viewCrop: session.cropping
                                  ? null
                                  : () {
                                      final crop = session.cropFor(path);
                                      return crop.isFull ? null : crop;
                                    }(),
                            ),
                            if (session.cropping)
                              PhotoCropOverlay(
                                session: session,
                                path: path,
                                version: controller.imageContentStamp(path),
                                fit: BoxFit.contain,
                              ),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    _ToolButton(
                      icon: PhosphorIconsRegular.crop,
                      label: 'Crop',
                      selected: session.cropping,
                      onTap: path == null ? null : session.toggleCropping,
                    ),
                    const SizedBox(width: 6),
                    _ToolButton(
                      icon: PhosphorIconsRegular.arrowClockwise,
                      label: 'Rotate',
                      onTap: path == null
                          ? null
                          : () {
                              session.checkpoint(path);
                              session.rotateClockwise(path);
                            },
                    ),
                    const SizedBox(width: 6),
                    _ToolButton(
                      label: 'Before / after',
                      selected: session.comparing,
                      onTap: path == null
                          ? null
                          : () =>
                              session.setComparing(!session.comparing),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: path == null
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          for (final group in _groups) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 2),
                              child: Text(
                                group.$1,
                                style: const TextStyle(
                                  fontFamily: MobileDesign.font,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.08 * 11,
                                  color: MobileDesign.textSecondary,
                                ),
                              ),
                            ),
                            for (final item in group.$2)
                              _SliderRow(
                                label: item.$1,
                                value: item.$2(grade),
                                min: item.$3,
                                max: item.$4,
                                onChanged: (v) {
                                  session.beginGesture(path);
                                  session.update(
                                    path,
                                    item.$5(grade, v),
                                  );
                                },
                                onChangeEnd: session.endGesture,
                              ),
                          ],
                        ],
                      ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: MobileDesign.barBg,
                  border: Border(
                    top: BorderSide(color: MobileDesign.divider),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 12,
                              color: MobileDesign.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: path == null
                              ? null
                              : () => session.reset(path),
                          style: TextButton.styleFrom(
                            foregroundColor: MobileDesign.link,
                            minimumSize: const Size(44, 36),
                          ),
                          child: const Text(
                            'Reset all',
                            style: TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
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

typedef _AdjRead = double Function(PhotoAdjustments a);
typedef _AdjWrite = PhotoAdjustments Function(PhotoAdjustments a, double v);

final _groups = <(String, List<(String, _AdjRead, double, double, _AdjWrite)>)>[
  (
    'WHITE BALANCE',
    [
      (
        'Temp',
        (a) => a.temperature,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(temperature: v),
      ),
      (
        'Tint',
        (a) => a.tint,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(tint: v),
      ),
    ],
  ),
  (
    'LIGHT',
    [
      (
        'Exposure',
        (a) => a.exposure,
        PhotoAdjustConfig.exposureStopsMin,
        PhotoAdjustConfig.exposureStopsMax,
        (a, v) => a.copyWith(exposure: v),
      ),
      (
        'Contrast',
        (a) => a.contrast,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(contrast: v),
      ),
      (
        'Highlights',
        (a) => a.highlights,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(highlights: v),
      ),
      (
        'Shadows',
        (a) => a.shadows,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(shadows: v),
      ),
      (
        'Whites',
        (a) => a.whites,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(whites: v),
      ),
      (
        'Blacks',
        (a) => a.blacks,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(blacks: v),
      ),
    ],
  ),
  (
    'COLOR',
    [
      (
        'Vibrance',
        (a) => a.vibrance,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(vibrance: v),
      ),
      (
        'Saturation',
        (a) => a.saturation,
        PhotoAdjustConfig.sliderUiMin,
        PhotoAdjustConfig.sliderUiMax,
        (a, v) => a.copyWith(saturation: v),
      ),
    ],
  ),
];

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          color: selected ? MobileDesign.selectedBg : MobileDesign.input,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
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

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final shown = value.abs() < 0.05
        ? '0'
        : (max.abs() <= 5
            ? value.toStringAsFixed(1)
            : value.round().toString());
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: MobileDesign.font,
                fontSize: 13,
                color: MobileDesign.textSoft,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: MobileDesign.selectedBg,
                inactiveTrackColor: MobileDesign.input,
                thumbColor: MobileDesign.selectedBg,
                overlayColor: MobileDesign.selectedBg.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: (_) => onChangeEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              shown,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: MobileDesign.font,
                fontSize: 13,
                color: MobileDesign.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
