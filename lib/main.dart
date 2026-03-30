import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'screens/caption_builder_screen.dart';
import 'widgets/preferences_dialog.dart';
import 'intents.dart';

// Global navigator key so native menus / dialogs can reach the app context.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Suppress debug output in console
  debugPrint = (String? message, {int? wrapWidth}) {
    // Suppress all debug output
  };

  WidgetsFlutterBinding.ensureInitialized();

  // Handle native app menu "Preferences…" (Cmd+,) — open Preferences dialog
  const prefsChannel = MethodChannel('caption_writer/preferences');
  prefsChannel.setMethodCallHandler((MethodCall call) async {
    if (call.method == 'openPreferences') {
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await showDialog<void>(
          context: ctx,
          builder: (context) => const PreferencesDialog(),
        );
      }
    }
    return null;
  });

  // Check if running from a mounted volume (DMG) and warn user
  final executablePath = Platform.resolvedExecutable;
  if (executablePath.contains('/Volumes/')) {
    print(
        'WARNING: App is running from a mounted volume. Please copy to Applications first.');
    runApp(const DmgWarningApp());
    return;
  }

  runApp(const MyApp());
}

class DmgWarningApp extends StatelessWidget {
  const DmgWarningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please Install First',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This app is running from a disk image. Please drag it to your Applications folder before using it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => exit(0),
                  child: const Text('Quit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            OpenPreferencesIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenPreferencesIntent: CallbackAction<OpenPreferencesIntent>(
            onInvoke: (_) {
              final ctx = appNavigatorKey.currentContext;
              if (ctx != null && ctx.mounted) {
                showDialog<void>(
                  context: ctx,
                  builder: (context) => const PreferencesDialog(),
                );
              }
              return null;
            },
          ),
        },
        child: MaterialApp(
          title: 'Caption Writer',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E3A59),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          home: const CaptionBuilderScreen(),
        ),
      ),
    );
  }
}
