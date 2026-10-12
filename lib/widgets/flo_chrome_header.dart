import 'dart:io';

import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';
import '../services/admin_service.dart';
import '../theme/app_tokens.dart';
import '../theme/ff_tokens.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'app_styled_dialogs.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
        color: Colors.transparent,
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
              : (onDark ? const Color(0xFFE4EAF2) : AppTokens.onAccent),
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
              PhosphorIcon(PhosphorIconsRegular.arrowClockwise, size: 14),
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

String _accountInitials({String? displayName, String? email}) {
  final name = displayName?.trim() ?? '';
  if (name.isNotEmpty) {
    final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final letters = parts.map((part) => part[0]).take(2).join();
    if (letters.isNotEmpty) return letters.toUpperCase();
  }
  final local = (email ?? '').split('@').first.trim();
  if (local.length >= 2) return local.substring(0, 2).toUpperCase();
  if (local.isNotEmpty) return local.toUpperCase();
  return '•';
}

/// Account label that opens the app-styled context menu (Sign out).
class FloHeaderSignedInAs extends StatefulWidget {
  const FloHeaderSignedInAs({
    this.foreground,
    this.foregroundMuted,
    this.compact = false,
    this.initials = false,
    this.showStatusDot = true,
    this.avatarFill,
    this.initialsDiameter = 28,
    this.initialsBorder = true,
  });

  /// Account email / icon color. Defaults to [AppTokens.onAccent].
  final Color? foreground;

  /// Unused currently; reserved for secondary account chrome.
  final Color? foregroundMuted;

  /// Shows only the account icon and menu arrow in space-constrained chrome.
  final bool compact;

  /// Circle with the account initials, a signed-in dot, and the menu arrow.
  final bool initials;

  /// Gold status dot on the initials avatar. The session bar draws its own
  /// admin dot, so it passes false.
  final bool showStatusDot;

  /// Fill behind the initials. Defaults to a tint of [foreground].
  final Color? avatarFill;

  /// Diameter of the initials circle.
  final double initialsDiameter;

  /// Hairline ring around the initials circle.
  final bool initialsBorder;

  @override
  State<FloHeaderSignedInAs> createState() => _FloHeaderSignedInAsState();
}

class _FloHeaderSignedInAsState extends State<FloHeaderSignedInAs> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final account = user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Account');

    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final fg = widget.foreground ?? AppTokens.onAccent;
    final avatarFill = widget.avatarFill ??
        (widget.foreground != null
            ? fg.withValues(alpha: 0.18)
            : AppTokens.accent);
    final initialsSize = widget.initialsDiameter;
    final initials = widget.initials
        ? _accountInitials(
            displayName: user.displayName,
            email: user.email,
          )
        : '';

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MenuAnchor(
        controller: _menu,
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: t.divider),
            ),
          ),
        ),
        menuChildren: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Text(
                account,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textSecondary,
                  height: 1.2,
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: t.divider),
          MenuItemButton(
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(t.text),
              overlayColor: WidgetStatePropertyAll(
                t.text.withValues(alpha: 0.06),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            onPressed: () => AuthService.instance.signOut(),
            leadingIcon: PhosphorIcon(
              PhosphorIconsRegular.signOut,
              size: 15,
              color: t.text,
            ),
            child: Text(
              'Sign out',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.text,
              ),
            ),
          ),
        ],
        builder: (context, controller, child) {
          return Tooltip(
            message: 'Account',
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                hoverColor: AppTokens.onAccentOverlay,
                splashColor: AppTokens.onAccentSubtle,
                child: child,
              ),
            ),
          );
        },
        child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.initials ? 0 : 8,
                vertical: widget.initials ? 0 : 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.initials
                      ? SizedBox(
                          width: initialsSize,
                          height: initialsSize,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: initialsSize,
                                height: initialsSize,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: avatarFill,
                                  shape: BoxShape.circle,
                                  border: widget.initialsBorder
                                      ? Border.all(
                                          color: fg.withValues(alpha: 0.28),
                                        )
                                      : null,
                                ),
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    fontSize: initialsSize >= 32 ? 12 : 11,
                                    fontWeight: FontWeight.w600,
                                    color: fg,
                                    height: 1,
                                  ),
                                ),
                              ),
                              if (widget.showStatusDot)
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5C451),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF1A1D24),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: avatarFill,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: fg.withValues(alpha: 0.35),
                            ),
                          ),
                          child: PhosphorIcon(
                            PhosphorIconsRegular.user,
                            color: fg,
                            size: 11,
                          ),
                        ),
                  if (!widget.compact && !widget.initials) ...[
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
                  if (!widget.initials) ...[
                    const SizedBox(width: 2),
                    PhosphorIcon(
                      PhosphorIconsRegular.caretDown,
                      color: fg,
                      size: 16,
                    ),
                  ],
                ],
              ),
            ),
      ),
    );
  }
}
