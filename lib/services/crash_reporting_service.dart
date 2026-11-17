import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/sentry_config.dart';
import 'iptc_template_apply_service.dart';
import 'preferences_service.dart';

/// Crash / error reporting for FloFile beta (macOS + Windows).
///
/// Uses **Sentry** because Firebase Crashlytics does not support Flutter
/// Windows desktop. Reports include only non-PII session tags (app version,
/// OS, selected wire, IPTC mode, league). Caption text, IPTC values, paths,
/// photos, and email are scrubbed before send.
class CrashReportingService {
  CrashReportingService._();

  static bool _initialized = false;
  static bool _enabled = true;

  static String? _wire;
  static String? _iptcMode;
  static String? _league;
  static String? _appVersion;

  static bool get isInitialized => _initialized;
  static bool get isEnabled => _enabled;

  /// Absolute / home paths, Windows paths, emails, image basenames.
  static final RegExp _pathUnix = RegExp(
    r'(?:(?:/Users|/home|/var|/tmp|/private|/Volumes|~)/\S+)',
    caseSensitive: false,
  );
  static final RegExp _pathWindows = RegExp(
    r'(?:[A-Za-z]:\\\S+|\\\\\S+)',
  );
  static final RegExp _email = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final RegExp _imageFile = RegExp(
    r'\b[\w.\-]+\.(?:jpe?g|png|tiff?|heic|webp|cr2|cr3|nef|arw|dng)\b',
    caseSensitive: false,
  );

  /// Scrub free-text before it can leave the device.
  static String scrubText(String input) {
    var out = input;
    out = out.replaceAll(_pathUnix, '[path]');
    out = out.replaceAll(_pathWindows, '[path]');
    out = out.replaceAll(_email, '[email]');
    out = out.replaceAll(_imageFile, '[file]');
    return out;
  }

  static Map<String, String> get sessionTags {
    final tags = <String, String>{
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
    };
    final version = _appVersion;
    if (version != null && version.isNotEmpty) {
      tags['app_version'] = version;
    }
    final wire = _wire;
    if (wire != null && wire.isNotEmpty) tags['wire'] = wire;
    final iptc = _iptcMode;
    if (iptc != null && iptc.isNotEmpty) tags['iptc_mode'] = iptc;
    final league = _league;
    if (league != null && league.isNotEmpty) tags['league'] = league;
    return tags;
  }

  static void _applyTagsToScope(Scope scope) {
    for (final entry in sessionTags.entries) {
      scope.setTag(entry.key, entry.value);
    }
  }

  /// Update non-PII session tags (wire / IPTC mode / league names only).
  static void updateSessionContext({
    String? wire,
    String? iptcMode,
    String? league,
  }) {
    if (wire != null) _wire = wire.trim().isEmpty ? null : wire.trim();
    if (iptcMode != null) {
      _iptcMode = iptcMode.trim().isEmpty ? null : iptcMode.trim();
    }
    if (league != null) {
      _league = league.trim().isEmpty ? null : league.trim();
    }
    if (!_initialized || !_enabled) return;
    unawaited(
      Future(() async {
        await Sentry.configureScope(_applyTagsToScope);
      }),
    );
  }

  /// Resolve IPTC mode tag from prefs (apply / fill / files / off). No field values.
  static Future<void> syncIptcModeFromPrefs(PreferencesService prefs) async {
    final String mode;
    if (await prefs.getIptcAppliedElsewhere()) {
      mode = 'files';
    } else if (await prefs.getIptcFillGapsOnly()) {
      mode = 'fill';
    } else {
      final apply = await prefs.getIptcApplyMode();
      mode = apply == IptcApplyMode.none ? 'off' : 'apply';
    }
    updateSessionContext(iptcMode: mode);
  }

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      if (_initialized) {
        await Sentry.close();
        _initialized = false;
      }
      return;
    }
    await init();
  }

  /// Initialize Sentry when a DSN is configured and the user has not opted out.
  static Future<void> init() async {
    final dsn = sentryDsn;
    if (dsn == null) {
      if (kDebugMode) {
        print('[CrashReporting] No SENTRY_DSN; reporting disabled.');
      }
      return;
    }

    final prefs = await PreferencesService.getInstance();
    _enabled = await prefs.getSendCrashReports();
    if (!_enabled) {
      if (kDebugMode) {
        print('[CrashReporting] Opted out via Settings.');
      }
      return;
    }

    if (_initialized) return;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = null;
    }

    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.environment = 'beta';
      options.release = _appVersion;
      options.sendDefaultPii = false;
      options.attachScreenshot = false;
      options.enableAutoSessionTracking = true;
      options.beforeSend = (event, hint) {
        if (!_enabled) return null;
        return scrubEvent(event);
      };
      options.beforeBreadcrumb = (breadcrumb, hint) {
        if (breadcrumb == null) return null;
        final message = breadcrumb.message;
        if (message != null) {
          breadcrumb.message = scrubText(message);
        }
        final data = breadcrumb.data;
        if (data != null) {
          breadcrumb.data = {
            for (final e in data.entries)
              e.key: e.value is String ? scrubText(e.value as String) : e.value,
          };
        }
        return breadcrumb;
      };
    });

    await Sentry.configureScope((scope) {
      _applyTagsToScope(scope);
      // Never attach user email / id.
      scope.setUser(null);
    });

    _initialized = true;
    if (kDebugMode) {
      print('[CrashReporting] Sentry initialized (beta).');
    }
  }

  /// Scrub an outbound event: drop user PII and sanitize messages / extras.
  @visibleForTesting
  static SentryEvent? scrubEvent(SentryEvent event) {
    event.user = null;
    event.serverName = null;
    event.request = null;

    final exceptions = event.exceptions;
    if (exceptions != null) {
      for (final ex in exceptions) {
        final value = ex.value;
        if (value != null) {
          ex.value = scrubText(value);
        }
      }
    }

    final message = event.message;
    if (message != null && message.formatted.isNotEmpty) {
      event.message = SentryMessage(scrubText(message.formatted));
    }

    final extras = event.extra;
    if (extras != null && extras.isNotEmpty) {
      final next = <String, dynamic>{};
      for (final e in extras.entries) {
        final key = e.key.toLowerCase();
        if (_blockedExtraKey(key)) continue;
        final value = e.value;
        next[e.key] = value is String ? scrubText(value) : value;
      }
      event.extra = next;
    }

    final tags = Map<String, String>.from(event.tags ?? const {});
    tags.addAll(sessionTags);
    event.tags = tags;

    return event;
  }

  static bool _blockedExtraKey(String key) {
    return key.contains('caption') ||
        key.contains('path') ||
        key.contains('file') ||
        key.contains('photo') ||
        key.contains('email') ||
        key.contains('user') ||
        (key.contains('iptc') && !key.contains('iptc_mode'));
  }

  /// Report a failed metadata write. [stderrText] is scrubbed; paths never sent.
  static Future<void> reportMetadataWriteFailure({
    required int exitCode,
    String? stderrText,
  }) async {
    if (!_enabled || !_initialized) return;

    final scrubbed = scrubText(stderrText ?? '');
    // Truncate so wire payloads never include long IPTC dumps.
    final snippet =
        scrubbed.length > 240 ? scrubbed.substring(0, 240) : scrubbed;

    await Sentry.captureMessage(
      'Metadata write failed (exiftool exit $exitCode)',
      level: SentryLevel.error,
      withScope: (scope) {
        _applyTagsToScope(scope);
        scope.setTag('exiftool_exit', '$exitCode');
        if (snippet.isNotEmpty) {
          scope.setContexts('exiftool', {
            'stderr_scrubbed': snippet,
          });
        }
      },
    );
  }

  /// Capture an unexpected exception (already scrubbed via beforeSend).
  static Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
  }) async {
    if (!_enabled || !_initialized) return;
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}
