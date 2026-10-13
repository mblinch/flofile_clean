import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../photo_edit/photo_edit_panel.dart';
import '../../../photo_edit/photo_edit_session.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import 'frame_status_dot.dart';

/// Filename, exposure, and the admin edit button. Sits on the top of the photo.
class PhotoPreviewInfoBar extends StatelessWidget {
  const PhotoPreviewInfoBar({
    super.key,
    required this.controller,
    required this.editSession,
    this.showExposure = true,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession editSession;
  final bool showExposure;

  String _meta(List<String> keys) {
    for (final key in keys) {
      final value = controller.currentIptcMeta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final iso = _meta(const ['ISO']);
    final shutter = _formatShutter(_meta(const ['ShutterSpeed']));
    final fNumber = double.tryParse(_meta(const ['FNumber']));
    final focalRaw =
        _meta(const ['FocalLength']).replaceAll(RegExp(r'm+$'), '').trim();
    final focal = double.tryParse(focalRaw);
    final exposure = [
      if (iso.isNotEmpty) 'ISO $iso',
      if (shutter.isNotEmpty) shutter,
      if (fNumber != null) 'f/${fNumber.toStringAsFixed(1)}',
      if (focalRaw.isNotEmpty)
        focal == null ? '${focalRaw}mm' : '${focal.toInt()}mm',
    ].join(' · ');
    final style = tokens.metaStyle.copyWith(
      fontSize: 12,
      height: 1.2,
      color: tokens.textTertiary,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.46,
                ),
                child: Text(
                  controller.currentFileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (showExposure && exposure.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    exposure,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ] else
                const Spacer(),
              PhotoEditModeButton(
                session: editSession,
                controller: controller,
                compact: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

String _formatShutter(String raw) {
  if (raw.isEmpty || raw.contains('/')) return raw;
  final value = double.tryParse(raw);
  if (value == null || value <= 0) return raw;
  return value < 1
      ? '1/${(1 / value).round()}s'
      : '${value.toStringAsFixed(1)}s';
}

/// Saved and uploaded marks. Sits on the bottom of the photo.
class PhotoPreviewActionBar extends StatelessWidget {
  const PhotoPreviewActionBar({
    super.key,
    required this.controller,
    required this.path,
  });

  final CaptionV2Controller controller;
  final String path;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          const Spacer(),
          PhotoPreviewStatusIcons(
            state: controller.frameStateFor(path),
            tokens: tokens,
          ),
        ],
      ),
    );
  }
}

class PhotoPreviewStatusIcons extends StatelessWidget {
  const PhotoPreviewStatusIcons({
    super.key,
    required this.state,
    required this.tokens,
    this.bare = true,
  });

  final FrameState state;
  final FfTokens tokens;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final saved = state != FrameState.todo;
    final sent = state == FrameState.sent;
    final icons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: saved ? 'Saved' : 'Not saved',
          child: PhosphorIcon(
            PhosphorIconsRegular.floppyDisk,
            size: 15,
            color: saved ? FrameStatusColors.saved : tokens.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: sent ? "FTP'd" : 'Not uploaded',
          child: PhosphorIcon(
            PhosphorIconsRegular.cloudArrowUp,
            size: 15,
            color: sent ? FrameStatusColors.sent : tokens.textTertiary,
          ),
        ),
      ],
    );
    if (bare) return icons;
    return Material(
      color: FfTokens.viewerChrome,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: tokens.divider),
        ),
        child: icons,
      ),
    );
  }
}
