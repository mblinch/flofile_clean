import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../photo_edit/photo_edit_panel.dart';
import '../../../photo_edit/photo_edit_session.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import 'frame_status_dot.dart';

/// Capture time and exposure. Sits on the top of the photo.
class PhotoPreviewInfoBar extends StatelessWidget {
  const PhotoPreviewInfoBar({
    super.key,
    required this.controller,
    this.showExposure = true,
  });

  final CaptionV2Controller controller;
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
    final taken = _formatTaken(
      _meta(const ['DateTimeOriginal', 'CreateDate']),
    );
    final info = [
      if (taken.isNotEmpty) taken,
      if (showExposure && exposure.isNotEmpty) exposure,
    ].join('  ·  ');
    if (info.isEmpty) return const SizedBox.shrink();
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
      child: Text(
        info,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

String _formatTaken(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return raw.trim();
  final dateParts = parts[0].split(':');
  final timeParts = parts[1].split(':');
  if (dateParts.length != 3 || timeParts.length < 2) return raw.trim();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final year = dateParts[0];
  final monthIdx = int.tryParse(dateParts[1]) ?? 0;
  final day = int.tryParse(dateParts[2]) ?? 0;
  if (monthIdx < 1 || monthIdx > 12 || day <= 0) return raw.trim();
  final hour24 = int.tryParse(timeParts[0]) ?? 0;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final period = hour24 < 12 ? 'AM' : 'PM';
  final minute = timeParts[1].padLeft(2, '0');
  final second = timeParts.length > 2 ? timeParts[2].padLeft(2, '0') : '00';
  return '${months[monthIdx - 1]} $day, $year · $hour12:$minute:$second $period';
}

String _formatShutter(String raw) {
  if (raw.isEmpty || raw.contains('/')) return raw;
  final value = double.tryParse(raw);
  if (value == null || value <= 0) return raw;
  return value < 1
      ? '1/${(1 / value).round()}s'
      : '${value.toStringAsFixed(1)}s';
}

/// Filename, saved and uploaded marks, and the edit button.
/// Sits on the bottom of the photo.
class PhotoPreviewActionBar extends StatelessWidget {
  const PhotoPreviewActionBar({
    super.key,
    required this.controller,
    required this.editSession,
    required this.path,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession editSession;
  final String path;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final nameStyle = tokens.metaStyle.copyWith(
      fontSize: 12,
      height: 1.2,
      color: tokens.textSecondary,
      fontWeight: FontWeight.w500,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              controller.currentFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: nameStyle,
            ),
          ),
          const SizedBox(width: 8),
          PhotoPreviewStatusIcons(
            state: controller.frameStateFor(path),
            tokens: tokens,
          ),
          const SizedBox(width: 8),
          PhotoEditModeButton(
            session: editSession,
            controller: controller,
            compact: true,
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
