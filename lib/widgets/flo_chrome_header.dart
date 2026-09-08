import 'dart:io';

import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import '../services/admin_service.dart';
import '../theme/app_tokens.dart';
import '../theme/ff_tokens.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'app_styled_dialogs.dart';

/// Top chrome bar matching [AppHeaderWidget] (teal gradient,
/// [kFloAppHeaderHeight]).
class FloChromeHeader extends StatelessWidget {
  const FloChromeHeader({
    super.key,
    this.showSignOut = false,
    this.signOutTooltip,
    this.accountOnly = false,
  });

  /// When true, shows the account menu (with Sign out) on the right.
  final bool showSignOut;

  /// Kept for callers; account email is shown in the menu trigger.
  final String? signOutTooltip;

  /// Slim bar: account menu (+ admin badge). No title, size, or restart.
  final bool accountOnly;

  static const double toolbarHeight = kFloAppHeaderHeight;

  @override
  Widget build(BuildContext context) {
    final ff = Theme.of(context).extension<FfTokens>();
    final useV2Chrome = accountOnly && ff != null;

    final Decoration decoration;
    if (useV2Chrome) {
      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [ff.surface, ff.bg],
        ),
        border: Border(bottom: BorderSide(color: ff.divider)),
      );
    } else {
      decoration = const BoxDecoration(
        gradient: AppTokens.topBarGradient,
        border: Border(
          bottom: BorderSide(color: AppTokens.topBarBorder),
        ),
      );
    }

    final onBar = useV2Chrome ? ff.text : AppTokens.onAccent;
    final onBarMuted = useV2Chrome ? ff.textSecondary : AppTokens.onAccentMuted;

    return Container(
      height: toolbarHeight,
      decoration: decoration,
      child: Row(
        children: [
          if (!accountOnly) ...[
            const SizedBox(width: 20),
            const Text(
              'FLO FILE',
              style: TextStyle(
                fontFamily: AppTokens.titleFontFamily,
                fontFamilyFallback: AppTokens.titleFontFallback,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTokens.onAccent,
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
            Builder(
              builder: (context) {
                final size = MediaQuery.sizeOf(context);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: 'App window size',
                    child: Text(
                      '${size.width.round()}×${size.height.round()}',
                      style: AppTokens.mono.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.onAccent,
                        letterSpacing: 0.2,
                        height: 1.0,
                      ),
                    ),
                  ),
                );
              },
            ),
            const FloHeaderRestartButton(),
          ] else ...[
            if (AdminService.isCurrentUserAdminSync()) ...[
              const SizedBox(width: 12),
              AdminBadgeButton(
                child: _chromeBadge(
                  'Admin',
                  emphasized: true,
                  onDark: useV2Chrome,
                ),
              ),
            ],
            const Spacer(),
          ],
          if (showSignOut)
            FloHeaderSignedInAs(
              foreground: onBar,
              foregroundMuted: onBarMuted,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  static Widget _chromeBadge(
    String label, {
    bool emphasized = false,
    bool onDark = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized
            ? AppTokens.adminTint
            : (onDark ? const Color(0x26FFFFFF) : AppTokens.topBarBadgeFill),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? AppTokens.adminAccent
              : (onDark ? const Color(0x40FFFFFF) : AppTokens.onAccentSubtle),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: emphasized
              ? AppTokens.adminText
              : (onDark ? const Color(0xFFE9E9ED) : AppTokens.onAccent),
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
            foregroundColor: AppTokens.onAccent,
            overlayColor: AppTokens.onAccentOverlay,
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
                  fontSize: 10,
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
  const FloHeaderSignedInAs({
    this.foreground,
    this.foregroundMuted,
    this.compact = false,
  });

  /// Account email / icon color. Defaults to [AppTokens.onAccent].
  final Color? foreground;

  /// Unused currently; reserved for secondary account chrome.
  final Color? foregroundMuted;

  /// Shows only the account icon and menu arrow in space-constrained chrome.
  final bool compact;

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
              color: AppTokens.inkSecondary,
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

    final fg = widget.foreground ?? AppTokens.onAccent;
    final avatarFill = widget.foreground != null
        ? fg.withValues(alpha: 0.18)
        : AppTokens.accent;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Account',
        waitDuration: const Duration(milliseconds: 350),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAccountMenu(account),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            hoverColor: AppTokens.onAccentOverlay,
            splashColor: AppTokens.onAccentSubtle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: avatarFill,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: fg.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      Icons.person,
                      color: fg,
                      size: 11,
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        account,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: fg,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    key: _arrowKey,
                    color: fg,
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
