import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/admin_service.dart';
import '../theme/app_tokens.dart';
import '../theme/ff_tokens.dart';

/// Top-bar control for real admin accounts: turn admin UI off to preview the
/// product as a non-admin. Stays visible while previewing so you can flip back.
class AdminModeToggle extends StatelessWidget {
  const AdminModeToggle({
    super.key,
    this.compact = false,
    this.onDarkChrome = false,
  });

  final bool compact;

  /// Teal / accent top bars (caption builder) use light-on-dark chrome.
  final bool onDarkChrome;

  @override
  Widget build(BuildContext context) {
    if (!AdminService.isActuallyAdminSync()) {
      return const SizedBox.shrink();
    }
    final ff = Theme.of(context).extension<FfTokens>();
    return ValueListenableBuilder<bool>(
      valueListenable: AdminService.previewAsNonAdmin,
      builder: (context, preview, _) {
        final adminOn = !preview;
        final tooltip = adminOn
            ? 'Admin mode on — turn off to preview as a regular user'
            : 'Admin mode off — turn on to restore admin tools';

        if (onDarkChrome) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 350),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      AdminService.setPreviewAsNonAdmin(adminOn),
                  borderRadius: BorderRadius.circular(999),
                  hoverColor: AppTokens.onAccentOverlay,
                  child: Container(
                    height: compact ? 22 : 24,
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    decoration: BoxDecoration(
                      color: adminOn
                          ? AppTokens.adminTint
                          : AppTokens.topBarBadgeFill,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Admin Mode',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: adminOn
                                ? AppTokens.adminAccent
                                : AppTokens.onAccentMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 28,
                          width: 36,
                          child: Transform.scale(
                            scale: 0.65,
                            child: Switch(
                              value: adminOn,
                              onChanged: (on) =>
                                  AdminService.setPreviewAsNonAdmin(!on),
                              activeThumbColor: AppTokens.adminText,
                              activeTrackColor: AppTokens.adminAccent,
                              inactiveThumbColor: AppTokens.onAccent,
                              inactiveTrackColor: AppTokens.onAccentSubtle,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final t = ff ?? FfTokens.dark;
        final labelColor = adminOn ? FfTokens.gold : t.textSecondary;
        return Padding(
          padding: EdgeInsets.only(right: compact ? 6 : 8),
          child: Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: () => AdminService.setPreviewAsNonAdmin(adminOn),
                borderRadius: BorderRadius.circular(999),
                hoverColor: t.hover,
                child: Container(
                  height: compact ? 28 : 32,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    color: adminOn ? t.elevated : t.sunken,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIconsFill.shieldCheck,
                        size: 13,
                        color: labelColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Admin Mode',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 30,
                        width: 40,
                        child: Transform.scale(
                          scale: 0.7,
                          child: Switch(
                            value: adminOn,
                            onChanged: (on) =>
                                AdminService.setPreviewAsNonAdmin(!on),
                            activeThumbColor: FfTokens.gold,
                            activeTrackColor:
                                FfTokens.gold.withValues(alpha: 0.45),
                            inactiveThumbColor: t.textSecondary,
                            inactiveTrackColor: t.divider,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
