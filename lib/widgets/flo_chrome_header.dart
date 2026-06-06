import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';

/// Top chrome bar matching [AppHeaderWidget] (teal gradient, 34px).
class FloChromeHeader extends StatelessWidget {
  const FloChromeHeader({
    super.key,
    this.showSignOut = false,
    this.signOutTooltip,
  });

  /// When true, shows Sign out on the right (clears Firebase / Google session).
  final bool showSignOut;

  final String? signOutTooltip;

  static const double toolbarHeight = 34;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: toolbarHeight,
      decoration: const BoxDecoration(
        gradient: kFloTealGradientHorizontal,
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          const Text(
            'FLO FILE',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.white70,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          _chromeBadge('Beta'),
          if (AdminService.isCurrentUserAdminSync()) ...[
            const SizedBox(width: 6),
            AdminBadgeButton(
              child: _chromeBadge('Admin', emphasized: true),
            ),
          ],
          const Spacer(),
          if (showSignOut)
            FloHeaderSignOutButton(
              tooltip: signOutTooltip ?? 'Sign out',
            ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  static Widget _chromeBadge(String label, {bool emphasized = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(0xFFE8C547).withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasized ? const Color(0xFFE8C547) : Colors.white24,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: emphasized ? const Color(0xFFFFF3C4) : Colors.white70,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Sign out control for [FloChromeHeader] and [AppHeaderWidget].
class FloHeaderSignOutButton extends StatelessWidget {
  const FloHeaderSignOutButton({this.tooltip = 'Sign out'});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: TextButton(
        onPressed: () => AuthService.instance.signOut(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Colors.white70,
          overlayColor: Colors.white.withValues(alpha: 0.08),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout, size: 14),
            SizedBox(width: 5),
            Text(
              'Sign out',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
