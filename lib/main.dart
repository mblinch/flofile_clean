import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'intents.dart';
import 'screens/caption_builder_screen.dart';

// Global navigator key so the pre-focus keyboard handler can dispatch to the app.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Intercepts Cmd+Shift+K at the ServicesBinding level, before Flutter's focus
/// system (and any MenuAnchor / Shortcuts widget) gets a chance to beep.
/// Returns true to consume the event; false to let it propagate normally.
bool _globalKeyboardFireInterceptor(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
  final hw = HardwareKeyboard.instance;
  if (!(hw.isMetaPressed || hw.isControlPressed) || !hw.isShiftPressed) {
    return false;
  }
  // Dispatch an intent via the navigator's overlay context so Actions can find
  // the CaptionBuilderScreen's action.
  final ctx = appNavigatorKey.currentContext;
  if (ctx != null) {
    Actions.maybeInvoke(ctx, const KeyboardFireIntent());
  }
  return true; // consume — prevents macOS beep regardless of focus
}

void main() {
  // Suppress debug output in console
  debugPrint = (String? message, {int? wrapWidth}) {
    // Suppress all debug output
  };

  // Register the Cmd+Shift+K interceptor before any widget is built.
  WidgetsFlutterBinding.ensureInitialized();
  HardwareKeyboard.instance.addHandler(_globalKeyboardFireInterceptor);

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
    return MaterialApp(
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
    );
  }
}
