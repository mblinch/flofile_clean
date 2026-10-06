import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/ftp_history.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

Future<void> showFtpHistoryDialog(
  BuildContext context,
  CaptionV2Controller controller,
) {
  final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      final entries = controller.ftpHistory;
      return Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                border: Border.all(color: tokens.divider),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'FTP history',
                            style: tokens.labelStyle,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: PhosphorIcon(PhosphorIconsRegular.x, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.divider),
                  Flexible(
                    child: entries.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No uploads yet.',
                              style: tokens.metaStyle,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: tokens.divider),
                            itemBuilder: (context, index) {
                              return _HistoryRow(
                                entry: entries[index],
                                tokens: tokens,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.tokens});

  final FtpHistoryEntry entry;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(entry.at);
    final clock = time.format(context);
    final detail = [
      clock,
      if (entry.profile.isNotEmpty) entry.profile,
      if (!entry.success && (entry.error ?? '').isNotEmpty) entry.error!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            entry.success ? PhosphorIconsRegular.cloudCheck : PhosphorIconsRegular.cloudSlash,
            size: 16,
            color: entry.success
                ? const Color(0xFF3DDC84)
                : const Color(0xFFF07167),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metaStyle.copyWith(color: tokens.text),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.microStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
