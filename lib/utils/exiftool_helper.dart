import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../services/crash_reporting_service.dart';

class ExiftoolResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;
  ExiftoolResult(
      {required this.exitCode,
      required this.stdoutText,
      required this.stderrText});
  bool get isSuccess => exitCode == 0;
}

class ExiftoolHelper {
  static String? _cachedPath;
  static bool _hasShownError = false;

  static String get _bundledExiftoolPath {
    final executablePath = Platform.resolvedExecutable;
    final appBundlePath =
        path.dirname(path.dirname(path.dirname(executablePath)));
    return path.join(appBundlePath, 'Contents', 'Resources', 'exiftool');
  }

  static String get _bundledLibDir =>
      path.join(path.dirname(_bundledExiftoolPath), 'exiftool_lib');

  /// True when the app bundle has both the script and its Perl libs.
  /// Debug builds often ship the script alone — skip it so we don't pay for
  /// a failed launch on every photo metadata read.
  static Future<bool> _bundledExiftoolIsUsable() async {
    if (!Platform.isMacOS) return false;
    if (!await File(_bundledExiftoolPath).exists()) return false;
    return Directory(_bundledLibDir).exists();
  }

  // Prefer a complete bundled install, then common absolute paths.
  static Future<List<String>> _candidatePaths() async {
    final paths = <String>[];
    if (await _bundledExiftoolIsUsable()) {
      paths.add(_bundledExiftoolPath);
    }
    paths.addAll(const [
      '/opt/homebrew/bin/exiftool',
      '/usr/local/bin/exiftool',
      '/usr/bin/exiftool',
    ]);
    return paths;
  }

  static Future<String?> _resolveExiftoolPath() async {
    if (_cachedPath != null) return _cachedPath;

    print('DEBUG: Resolving exiftool path...');
    print('DEBUG: Executable path: ${Platform.resolvedExecutable}');

    for (final candidate in await _candidatePaths()) {
      try {
        print('DEBUG: Checking path: $candidate');
        final exists = await File(candidate).exists();
        print('DEBUG: Path exists: $exists');
        if (exists) {
          _cachedPath = candidate;
          print('DEBUG: Using exiftool at: $_cachedPath');
          return _cachedPath;
        }
      } catch (e) {
        print('DEBUG: Error checking path $candidate: $e');
      }
    }
    // As a last resort, try relying on PATH
    try {
      print('DEBUG: Trying which exiftool...');
      final proc = await Process.run('which', ['exiftool']);
      print('DEBUG: which exit code: ${proc.exitCode}');
      if (proc.exitCode == 0) {
        final found = (proc.stdout as String).trim();
        print('DEBUG: which found: $found');
        if (found.isNotEmpty) {
          _cachedPath = found;
          print('DEBUG: Using system exiftool at: $_cachedPath');
          return _cachedPath;
        }
      }
    } catch (e) {
      print('DEBUG: Error with which: $e');
    }
    print('DEBUG: No exiftool found!');
    return null;
  }

  static void _rememberWorkingPath(String workingPath) {
    if (_cachedPath == workingPath) return;
    _cachedPath = workingPath;
    print('DEBUG: Cached working exiftool at: $_cachedPath');
  }

  // Show user-friendly error message (only once per session)
  static void _showErrorIfNeeded(String errorMessage) {
    if (!_hasShownError) {
      _hasShownError = true;
      print('EXIFTOOL ERROR: $errorMessage');
      // In a real app, you might want to show a dialog or notification here
    }
  }

  // On macOS, run the bundled exiftool (Perl script) via /usr/bin/perl and
  // inject include paths to bundled Perl libraries under Resources/exiftool_lib
  static Future<ExiftoolResult?> _runBundledOnMac(
      String scriptPath, List<String> args) async {
    try {
      if (!Platform.isMacOS) return null;

      // Resolve Resources directory and potential lib dir
      final resourcesDir = path.dirname(scriptPath);
      final libDir = path.join(resourcesDir, 'exiftool_lib');

      final includeArgs = <String>[];
      // Always include the root lib dir if present
      if (await Directory(libDir).exists()) {
        includeArgs.addAll(['-I', libDir]);
        // Also include immediate subdirectories (e.g., arch-specific dirs)
        try {
          await for (final entity in Directory(libDir).list()) {
            if (entity is Directory) {
              includeArgs.addAll(['-I', entity.path]);
            }
          }
        } catch (_) {
          // Ignore listing errors; rely on root lib dir only
        }
      }

      final perlArgs = <String>[];
      perlArgs.addAll(includeArgs);
      perlArgs.add(scriptPath);
      perlArgs.addAll(args);

      final proc = await Process.run('/usr/bin/perl', perlArgs);
      return ExiftoolResult(
        exitCode: proc.exitCode,
        stdoutText: (proc.stdout is String)
            ? proc.stdout as String
            : utf8.decode((proc.stdout as List<int>)),
        stderrText: (proc.stderr is String)
            ? proc.stderr as String
            : utf8.decode((proc.stderr as List<int>)),
      );
    } catch (e) {
      // If perl invocation fails, return null to allow fallback handling
      print('DEBUG: _runBundledOnMac failed: $e');
      return null;
    }
  }

  static void _reportFailure(ExiftoolResult result) {
    if (result.isSuccess) return;
    // Never forward args (may include paths / IPTC values) — scrub stderr only.
    unawaited(
      CrashReportingService.reportMetadataWriteFailure(
        exitCode: result.exitCode,
        stderrText: result.stderrText,
      ),
    );
  }

  static Future<ExiftoolResult> run(List<String> args) async {
    final exiftoolPath = await _resolveExiftoolPath();
    if (exiftoolPath == null) {
      final missing = ExiftoolResult(
        exitCode: 127,
        stdoutText: '',
        stderrText:
            'exiftool not found. Please install exiftool (brew install exiftool).',
      );
      _reportFailure(missing);
      return missing;
    }

    print('DEBUG: exiftool ${args.length} args -> ${args.isEmpty ? '' : args.last}');

    try {
      // If using bundled script on macOS, prefer invoking via /usr/bin/perl
      if (Platform.isMacOS &&
          exiftoolPath.contains('/Contents/Resources/exiftool')) {
        final bundledResult = await _runBundledOnMac(exiftoolPath, args);
        if (bundledResult != null) {
          if (bundledResult.exitCode == 0) {
            return bundledResult;
          }
          // Fall through to fallback handling below with captured stderr
          print(
              'DEBUG: Bundled perl run failed with code: ${bundledResult.exitCode}');
          print('DEBUG: Bundled perl stderr: ${bundledResult.stderrText}');
        }
      }

      final proc = await Process.run(exiftoolPath, args);
      print('DEBUG: exiftool exit code: ${proc.exitCode}');

      if (proc.exitCode != 0) {
        final stderrText = (proc.stderr is String)
            ? proc.stderr as String
            : utf8.decode((proc.stderr as List<int>));
        print('DEBUG: exiftool stderr: $stderrText');

        // If bundled exiftool fails, try system exiftool as fallback
        if (exiftoolPath.contains('Resources')) {
          print('DEBUG: Bundled exiftool failed, trying system fallback...');
          final candidates = await _candidatePaths();
          for (final fallbackPath in candidates) {
            if (fallbackPath == exiftoolPath) continue;
            try {
              if (await File(fallbackPath).exists()) {
                print('DEBUG: Trying fallback: $fallbackPath');
                final fallbackProc = await Process.run(fallbackPath, args);
                if (fallbackProc.exitCode == 0) {
                  print('DEBUG: Fallback succeeded!');
                  _rememberWorkingPath(fallbackPath);
                  return ExiftoolResult(
                    exitCode: fallbackProc.exitCode,
                    stdoutText: (fallbackProc.stdout is String)
                        ? fallbackProc.stdout as String
                        : utf8.decode((fallbackProc.stdout as List<int>)),
                    stderrText: (fallbackProc.stderr is String)
                        ? fallbackProc.stderr as String
                        : utf8.decode((fallbackProc.stderr as List<int>)),
                  );
                } else {
                  print(
                      'DEBUG: Fallback failed with exit code: ${fallbackProc.exitCode}');
                }
              }
            } catch (e) {
              print('DEBUG: Fallback $fallbackPath failed: $e');
            }
          }
        }

        // If we get here, all attempts failed
        final errorMessage =
            'ExifTool failed. Bundled version error: $stderrText\n\n'
            'Please ensure exiftool is installed system-wide:\n'
            'brew install exiftool';
        _showErrorIfNeeded(errorMessage);
        final failed = ExiftoolResult(
          exitCode: proc.exitCode,
          stdoutText: '',
          stderrText: errorMessage,
        );
        _reportFailure(failed);
        return failed;
      }

      return ExiftoolResult(
        exitCode: proc.exitCode,
        stdoutText: (proc.stdout is String)
            ? proc.stdout as String
            : utf8.decode((proc.stdout as List<int>)),
        stderrText: (proc.stderr is String)
            ? proc.stderr as String
            : utf8.decode((proc.stderr as List<int>)),
      );
    } on ProcessException catch (e) {
      print('DEBUG: ProcessException: ${e.message}');

      // Try system fallback even on ProcessException
      if (exiftoolPath.contains('Resources')) {
        print(
            'DEBUG: ProcessException on bundled exiftool, trying system fallback...');
        final candidates = await _candidatePaths();
        for (final fallbackPath in candidates) {
          if (fallbackPath == exiftoolPath) continue;
          try {
            if (await File(fallbackPath).exists()) {
              print('DEBUG: Trying fallback: $fallbackPath');
              final fallbackProc = await Process.run(fallbackPath, args);
              if (fallbackProc.exitCode == 0) {
                print('DEBUG: Fallback succeeded after ProcessException!');
                _rememberWorkingPath(fallbackPath);
                return ExiftoolResult(
                  exitCode: fallbackProc.exitCode,
                  stdoutText: (fallbackProc.stdout is String)
                      ? fallbackProc.stdout as String
                      : utf8.decode((fallbackProc.stdout as List<int>)),
                  stderrText: (fallbackProc.stderr is String)
                      ? fallbackProc.stderr as String
                      : utf8.decode((fallbackProc.stderr as List<int>)),
                );
              }
            }
          } catch (e) {
            print('DEBUG: Fallback $fallbackPath failed: $e');
          }
        }
      }

      final errorMessage = 'ProcessException: ${e.message}\n\n'
          'This usually means the bundled exiftool cannot run in the sandboxed environment.\n'
          'Please install exiftool system-wide: brew install exiftool';
      _showErrorIfNeeded(errorMessage);
      final failed = ExiftoolResult(
          exitCode: 126, stdoutText: '', stderrText: errorMessage);
      _reportFailure(failed);
      return failed;
    } catch (e) {
      print('DEBUG: Unexpected error: $e');
      final failed = ExiftoolResult(
          exitCode: 1, stdoutText: '', stderrText: 'Unexpected error: $e');
      _reportFailure(failed);
      return failed;
    }
  }
}
