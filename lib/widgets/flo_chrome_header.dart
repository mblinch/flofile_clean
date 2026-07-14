import 'dart:io';

import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'app_styled_dialogs.dart';

/// Top chrome bar matching [AppHeaderWidget] (teal gradient, 34px).
class FloChromeHeader extends StatelessWidget {
  const FloChromeHeader({
    super.key,
    this.showSignOut = false,
    this.signOutTooltip,
  });

  /// When true, shows the account menu (with Sign out) on the right.
  final bool showSignOut;

  /// Kept for callers; account email is shown in the menu trigger.
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
          const FloHeaderRestartButton(),
          if (showSignOut) const FloHeaderSignedInAs(),
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

/// Compact top-bar control that confirms, then relaunches the process.
class FloHeaderRestartButton extends StatelessWidget {
  const FloHeaderRestartButton();

  static Future<void> confirmAndRestart(BuildContext context) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Restart app?',
      message:
          'Are you sure you want to restart the app? All metadata entered will '
          'be saved, but it can be overwritten if you reload the app with '
          'settings to overwrite IPTC.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Restart',
    );
    if (ok != true) return;

    try {
      await Process.start(
        Platform.resolvedExecutable,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // Fall through to exit even if relaunch fails.
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Restart app',
        waitDuration: const Duration(milliseconds: 350),
        child: TextButton(
          onPressed: () => confirmAndRestart(context),
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
              Icon(Icons.restart_alt, size: 14),
              SizedBox(width: 5),
              Text(
                'Restart app',
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
      ),
    );
  }
}

/// Account label that opens the app-styled context menu (Sign out).
class FloHeaderSignedInAs extends StatefulWidget {
  const FloHeaderSignedInAs();

  @override
  State<FloHeaderSignedInAs> createState() => _FloHeaderSignedInAsState();
}

class _FloHeaderSignedInAsState extends State<FloHeaderSignedInAs> {
  final GlobalKey _arrowKey = GlobalKey();

  Future<void> _openAccountMenu(String account) async {
    final arrowBox = _arrowKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (arrowBox == null || overlay == null) return;

    // Anchor under the dropdown arrow; prefer aligning to the arrow's right edge.
    final arrowTopLeft = arrowBox.localToGlobal(Offset.zero);
    final arrowBottomRight = arrowBox.localToGlobal(
      Offset(arrowBox.size.width, arrowBox.size.height),
    );
    final position = RelativeRect.fromLTRB(
      arrowTopLeft.dx,
      arrowBottomRight.dy,
      overlay.size.width - arrowBottomRight.dx,
      overlay.size.height - arrowBottomRight.dy,
    );

    final result = await showAppContextMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: kAppContextMenuItemHeight + 2,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          child: Text(
            account,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kAppContextMenuTextStyle.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w400,
              fontSize: 10,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        AppPopupMenu.tile(
          value: 'sign_out',
          label: 'Sign out',
          icon: Icons.logout,
        ),
      ],
    );

    if (result == 'sign_out') {
      await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final account = user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Account');

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Account',
        waitDuration: const Duration(milliseconds: 350),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAccountMenu(account),
            borderRadius: BorderRadius.circular(4),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashColor: Colors.white.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      account,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    key: _arrowKey,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
