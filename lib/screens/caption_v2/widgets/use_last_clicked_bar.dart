import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../theme/ff_tokens.dart';

/// Thin full-width control that restores the previous picture's clicks.
class UseLastClickedBar extends StatelessWidget {
  const UseLastClickedBar({
    super.key,
    required this.tokens,
    required this.onTap,
    this.onClear,
  });

  final FfTokens tokens;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tokens.divider),
                    color: tokens.hover,
                  ),
                  child: Text(
                    'Use last clicked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.labelFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      height: 1,
                      color: tokens.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Clear caption',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: tokens.divider),
                      color: tokens.hover,
                    ),
                    child: PhosphorIcon(
                      PhosphorIconsRegular.x,
                      size: 12,
                      color: tokens.text.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
