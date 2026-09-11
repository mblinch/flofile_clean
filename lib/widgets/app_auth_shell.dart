import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/ff_tokens.dart';
import 'sign_in_screen.dart';

/// Top-level auth gate: [StreamBuilder] on [FirebaseAuth.instance.authStateChanges].
///
/// Firebase Auth persists sessions between launches. When Firebase is not
/// initialized (e.g. unsupported platform), [child] is shown without sign-in.
class AppAuthShell extends StatefulWidget {
  const AppAuthShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppAuthShell> createState() => _AppAuthShellState();
}

class _AppAuthShellState extends State<AppAuthShell> {
  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return widget.child;
    }

    final skipped = AuthService.instance.signInSkipped;
    final t = FfTokens.dark;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null &&
            !skipped) {
          return Scaffold(
            backgroundColor: t.bg,
            body: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              ),
            ),
          );
        }

        if (snapshot.data == null && !skipped) {
          return SignInScreen(
            onSkipSignIn: () async {
              await AuthService.instance.skipSignIn();
              if (mounted) setState(() {});
            },
          );
        }

        return widget.child;
      },
    );
  }
}
