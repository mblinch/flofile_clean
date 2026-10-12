import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../../../widgets/oriented_file_preview.dart';
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
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                border: Border.all(color: tokens.divider),
              ),
              child: _FtpHistorySheet(
                controller: controller,
                entries: entries,
                tokens: tokens,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FtpHistorySheet extends StatefulWidget {
  const _FtpHistorySheet({
    required this.controller,
    required this.entries,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final List<FtpHistoryEntry> entries;
  final FfTokens tokens;

  @override
  State<_FtpHistorySheet> createState() => _FtpHistorySheetState();
}

class _FtpHistorySheetState extends State<_FtpHistorySheet> {
  int? _openIndex;

  void _focusEntry(FtpHistoryEntry entry) {
    final index = widget.controller.imagePaths.indexOf(entry.path);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That image is not in this session')),
      );
      return;
    }
    widget.controller.goToIndex(index);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final entries = widget.entries;
    return Column(
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
                      enlarged: _openIndex == index,
                      onThumbTap: () => setState(() {
                        _openIndex = _openIndex == index ? null : index;
                      }),
                      onOpen: () => _focusEntry(entries[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.tokens,
    required this.enlarged,
    required this.onThumbTap,
    required this.onOpen,
  });

  final FtpHistoryEntry entry;
  final FfTokens tokens;
  final bool enlarged;
  final VoidCallback onThumbTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(entry.at);
    final clock = time.format(context);
    final detail = [
      clock,
      if (entry.profile.isNotEmpty) entry.profile,
      if (!entry.success && (entry.error ?? '').isNotEmpty) entry.error!,
    ].join(' · ');
    final thumbWidth = enlarged ? 280.0 : 84.0;
    final thumbHeight = enlarged ? 188.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onDoubleTap: onOpen,
        child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onThumbTap,
              onDoubleTap: onOpen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: thumbWidth,
                height: thumbHeight,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: entry.path.isEmpty
                      ? ColoredBox(color: tokens.sunken)
                      : OrientedFilePreview(
                          path: entry.path,
                          fit: BoxFit.cover,
                          cacheWidth: enlarged ? 840 : 252,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
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
      ),
    );
  }
}
