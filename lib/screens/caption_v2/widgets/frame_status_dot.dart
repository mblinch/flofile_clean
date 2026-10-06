import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Frame progress state — single source of truth for session counts.
enum FrameState {
  /// Not yet captioned / saved.
  todo,

  /// Saved locally, not transmitted.
  saved,

  /// Transmitted successfully.
  sent,
}

/// Shared status colors for save / FTP icons and dots.
class FrameStatusColors {
  FrameStatusColors._();
  static const Color saved = FfTokens.statusSaved;
  static const Color pending = FfTokens.favorites;
  static const Color sent = FfTokens.statusSaved;
}

/// Hollow/amber (todo) / disk (saved) / disk (sent).
class FrameStatusDot extends StatelessWidget {
  const FrameStatusDot({
    super.key,
    required this.state,
    this.size = 10,
  });

  final FrameState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case FrameState.todo:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: FrameStatusColors.pending,
          ),
        );
      case FrameState.saved:
      case FrameState.sent:
        return PhosphorIcon(PhosphorIconsRegular.floppyDisk,
          size: size + 2,
          color: FrameStatusColors.saved,
        );
    }
  }
}

/// Compact status badges for thumbnails (disk / amber pending / cloud).
class FrameStatusBadges extends StatelessWidget {
  const FrameStatusBadges({
    super.key,
    required this.saved,
    required this.sent,
    this.iconSize = 11,
    this.badgeSize = 18,
  });

  final bool saved;
  final bool sent;
  final double iconSize;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    if (!saved && !sent) {
      return _circle(
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: FrameStatusColors.pending,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (saved)
          _circle(
            child: PhosphorIcon(PhosphorIconsRegular.floppyDisk,
              size: iconSize,
              color: FrameStatusColors.saved,
            ),
          ),
        if (saved && sent) const SizedBox(width: 3),
        if (sent)
          _circle(
            child: PhosphorIcon(PhosphorIconsRegular.cloudArrowUp,
              size: iconSize,
              color: t.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _circle({required Widget child}) {
    return Tooltip(
      message: 'Status',
      child: Container(
        width: badgeSize,
        height: badgeSize,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: FfTokens.thumbStatusChrome,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }
}
