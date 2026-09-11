import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import '../theme/auth_ui_constants.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'flo_chrome_header.dart';

/// Full-screen sign-in gate: Google → Firebase Auth.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.onSkipSignIn});

  /// Temporary dev bypass — continues without Firebase auth.
  final Future<void> Function()? onSkipSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      setState(() => _error = _friendlyAuthError(e.description ?? e.toString()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = _friendlyAuthError(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _friendlyAuthError(String message) {
    if (!message.toLowerCase().contains('keychain')) return message;
    if (kDebugMode) {
      return 'Google Sign-In could not access the macOS Keychain.\n\n'
          '• Open macos/Runner.xcworkspace in Xcode\n'
          '• Runner target → Signing & Capabilities → select your Team\n'
          '• Rebuild with flutter run -d macos (Debug)\n\n'
          'If it still fails, open Keychain Access, delete any old "auth" '
          'entry for FloFile, then try again.';
    }
    return 'Google Sign-In couldn’t unlock the macOS Keychain.\n'
        'Quit FloFile, open Keychain Access, remove any old FloFile '
        '“auth” entries, then try again.';
  }

  @override
  Widget build(BuildContext context) {
    final googleReady = AuthService.instance.isGoogleSignInConfigured;
    final user = AuthService.instance.currentUser;
    final signOutHint = user?.email?.trim().isNotEmpty == true
        ? 'Signed in as ${user!.email} — sign out to switch accounts'
        : 'Sign out';

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8EEF2),
              Color(0xFFF4F5F4),
              Color(0xFFDDE7ED),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FloChromeHeader(
              showSignOut: AuthService.instance.isSignedIn,
              signOutTooltip: signOutHint,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(36, 40, 36, 28),
                      decoration: BoxDecoration(
                        color: AuthUiColors.panel.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AuthUiColors.brand.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AuthUiColors.brand.withValues(alpha: 0.10),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'FLO FILE',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              height: 1,
                              color: AuthUiColors.brand,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Sign in',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: AuthUiColors.title,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Use your Google account to continue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 13,
                              color: AuthUiColors.subtitle,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (_error != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(
                                color: AuthUiColors.errorFill,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AuthUiColors.errorBorder,
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 12,
                                  color: AuthUiColors.errorText,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedGreyButton(
                              label: 'Continue with Google',
                              icon: Icons.g_mobiledata_rounded,
                              fontSize: 14,
                              fullWidth: true,
                              isTealGradient: googleReady && !_busy,
                              onPressed: googleReady && !_busy
                                  ? () => _run(
                                        AuthService.instance.signInWithGoogle,
                                      )
                                  : null,
                            ),
                          ),
                          if (!googleReady) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Google Sign-In is not configured on this build.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 11,
                                color: AuthUiColors.subtitle,
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (_busy) ...[
                            const SizedBox(height: 22),
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTokens.midSlate,
                              ),
                            ),
                          ],
                          if (widget.onSkipSignIn != null) ...[
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await widget.onSkipSignIn?.call();
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: AuthUiColors.subtitle,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                'Skip sign in',
                                style: TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
