import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Dim overlay + progress bar for FTP uploads on preview / thumbnails.
class TransmitProgressOverlay extends StatelessWidget {
  const TransmitProgressOverlay({
    super.key,
    required this.progress,
    this.status,
    this.compact = false,
  });

  /// 0.0–1.0
  final double progress;
  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    final label = status?.trim().isNotEmpty == true ? status! : 'Uploading…';

    if (compact) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$pct%',
                  style: t.microStyle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    color: t.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelStyle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: t.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$pct%',
                  style: t.metaStyle.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
