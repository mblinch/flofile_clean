import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';

Future<void> showFtpActiveDialog(
  BuildContext context,
  CaptionV2Controller controller,
) {
  final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                border: Border.all(color: tokens.divider),
              ),
              child: _FtpActiveSheet(controller: controller, tokens: tokens),
            ),
          ),
        ),
      );
    },
  );
}

class _FtpActiveSheet extends StatelessWidget {
  const _FtpActiveSheet({required this.controller, required this.tokens});

  final CaptionV2Controller controller;
  final FfTokens tokens;

  void _focus(BuildContext context, String path) {
    final index = controller.imagePaths.indexOf(path);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That image is not in this session')),
      );
      return;
    }
    controller.goToIndex(index);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller.ftpPreviewPath;
        final sending = controller.transmitting &&
            active != null &&
            active.trim().isNotEmpty;
        final queued = controller.ftpQueuedPaths;
        final rows = <_ActiveRow>[
          if (sending)
            _ActiveRow(
              path: active,
              sending: true,
              progress: controller.ftpFileProgress,
            ),
          for (final path in queued)
            if (path != active) _ActiveRow(path: path, sending: false),
        ];
        final batch = controller.ftpBatchTotal > 1 &&
                controller.ftpBatchIndex > 0
            ? 'Picture ${controller.ftpBatchIndex} of ${controller.ftpBatchTotal}'
            : null;
        final profile = controller.ftpProfileName?.trim();
        final subtitle = [
          if (batch != null) batch,
          if (profile != null && profile.isNotEmpty) profile,
        ].join(' · ');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sending', style: tokens.labelStyle),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, style: tokens.microStyle),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: PhosphorIcon(
                      PhosphorIconsRegular.x,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.divider),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nothing sending.', style: tokens.metaStyle),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: tokens.divider),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _ActiveFileRow(
                          row: row,
                          tokens: tokens,
                          onOpen: () => _focus(context, row.path),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveRow {
  const _ActiveRow({
    required this.path,
    required this.sending,
    this.progress,
  });

  final String path;
  final bool sending;
  final double? progress;
}

class _ActiveFileRow extends StatelessWidget {
  const _ActiveFileRow({
    required this.row,
    required this.tokens,
    required this.onOpen,
  });

  final _ActiveRow row;
  final FfTokens tokens;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final percent =
        '${((row.progress ?? 0).clamp(0.0, 1.0) * 100).round()}%';
    final detail = row.sending ? 'Sending · $percent' : 'Waiting';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onDoubleTap: onOpen,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 84,
                height: 56,
                child: OrientedFilePreview(
                  path: row.path,
                  fit: BoxFit.cover,
                  cacheWidth: 252,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              row.sending
                  ? PhosphorIconsRegular.cloudArrowUp
                  : PhosphorIconsRegular.clock,
              size: 16,
              color: row.sending
                  ? const Color(0xFF3DDC84)
                  : tokens.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(row.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metaStyle.copyWith(color: tokens.text),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.microStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
