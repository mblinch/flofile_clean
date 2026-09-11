import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../theme/ff_tokens.dart';

/// Full-screen sign-in gate: Google → Firebase Auth.
///
/// Styled to match Caption V2 (dark FfTokens), not the classic light chrome.
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
  bool _googleHovered = false;

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
    final t = FfTokens.dark;
    final googleReady = AuthService.instance.isGoogleSignInConfigured;
    final canGoogle = googleReady && !_busy;

    return Scaffold(
      backgroundColor: t.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.bg,
              t.sunken,
              t.bg,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'FLO FILE',
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                        height: 1,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Caption workspace',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sign in',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.35,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use your Google account to continue.',
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 13,
                              height: 1.45,
                              color: t.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_error != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A2228),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF7A3A44),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 12,
                                  height: 1.4,
                                  color: Color(0xFFE8B4B8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          MouseRegion(
                            cursor: canGoogle
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            onEnter: canGoogle
                                ? (_) => setState(() => _googleHovered = true)
                                : null,
                            onExit: canGoogle
                                ? (_) => setState(() => _googleHovered = false)
                                : null,
                            child: GestureDetector(
                              onTap: canGoogle
                                  ? () => _run(
                                        AuthService.instance.signInWithGoogle,
                                      )
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                height: 46,
                                decoration: BoxDecoration(
                                  color: !canGoogle
                                      ? t.badgeFill
                                      : (_googleHovered
                                          ? t.text.withValues(alpha: 0.92)
                                          : t.text),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.g_mobiledata_rounded,
                                      size: 26,
                                      color: !canGoogle
                                          ? t.textSecondary
                                          : t.bg,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        fontFamily: FfTokens.labelFamily,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: !canGoogle
                                            ? t.textSecondary
                                            : t.bg,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!googleReady) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Google Sign-In is not configured on this build.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 11.5,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                          if (_busy) ...[
                            const SizedBox(height: 20),
                            Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: t.accent,
                                ),
                              ),
                            ),
                          ],
                          if (widget.onSkipSignIn != null) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await widget.onSkipSignIn?.call();
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: t.textSecondary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              child: Text(
                                'Skip sign in',
                                style: TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
