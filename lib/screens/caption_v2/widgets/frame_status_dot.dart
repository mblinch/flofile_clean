import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';

/// Frame progress state — single source of truth for session counts.
enum FrameState {
  /// Not yet captioned / saved.
  todo,

  /// Saved locally, not transmitted.
  saved,

  /// Transmitted successfully.
  sent,
}

/// Hollow ring (todo) / filled neutral (saved) / filled accent (sent).
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
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    switch (state) {
      case FrameState.todo:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.textSecondary, width: 1.5),
          ),
        );
      case FrameState.saved:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.statusNeutral,
          ),
        );
      case FrameState.sent:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.accent,
          ),
        );
    }
  }
}
