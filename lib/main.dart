import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'screens/caption_builder_screen.dart';

void main() {
  // Suppress debug output in console
  debugPrint = (String? message, {int? wrapWidth}) {
    // Suppress all debug output
  };

  // Check if running from a mounted volume (DMG) and warn user
  final executablePath = Platform.resolvedExecutable;
  if (executablePath.contains('/Volumes/')) {
    print(
        'WARNING: App is running from a mounted volume. Please copy to Applications first.');
    // Show a dialog warning the user
    WidgetsFlutterBinding.ensureInitialized();
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
      // home: const ApiTestWidget(), // Temporarily show API test
      // home: const FtpUploadWidget(), // Show FTP test interface
    );
  }
}
