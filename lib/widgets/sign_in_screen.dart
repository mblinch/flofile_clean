import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../theme/auth_ui_constants.dart';
import 'app_styled_dialogs.dart';
import 'flo_chrome_header.dart';

/// Full-screen sign-in gate: Google → Firebase Auth.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

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
      setState(() => _error = e.description ?? e.toString());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleReady = AuthService.instance.isGoogleSignInConfigured;
    final user = AuthService.instance.currentUser;
    final signOutHint = user?.email?.trim().isNotEmpty == true
        ? 'Signed in as ${user!.email} — sign out to switch accounts'
        : 'Sign out';

    return Scaffold(
      backgroundColor: AuthUiColors.scaffold,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FloChromeHeader(
            showSignOut: AuthService.instance.isFirebaseReady,
            signOutTooltip: signOutHint,
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 400,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                decoration: BoxDecoration(
                  color: AuthUiColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AuthUiColors.panelBorder, width: 0.7),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sign in',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AuthUiColors.title,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use your Google account to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AuthUiColors.subtitle,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AuthUiColors.errorFill,
                          border: Border.all(color: AuthUiColors.errorBorder),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: AuthUiColors.errorText,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedGreyButton(
                        label: 'Continue with Google',
                        icon: Icons.g_mobiledata_rounded,
                        fontSize: 12,
                        fullWidth: true,
                        isTealGradient: googleReady && !_busy,
                        onPressed: googleReady && !_busy
                            ? () => _run(AuthService.instance.signInWithGoogle)
                            : null,
                      ),
                    ),
                    if (!googleReady) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Google Sign-In is not configured on this build.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          color: AuthUiColors.subtitle,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 20),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4A7A96),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
