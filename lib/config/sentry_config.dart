/// Sentry DSN for beta crash / error reporting.
///
/// Pass at build/run time:
/// `--dart-define=SENTRY_DSN=https://…@….ingest.sentry.io/…`
///
/// Leave empty to disable network reporting (local / CI without a project).
const String kSentryDsn = String.fromEnvironment('SENTRY_DSN');

String? get sentryDsn {
  final trimmed = kSentryDsn.trim();
  return trimmed.isEmpty ? null : trimmed;
}
