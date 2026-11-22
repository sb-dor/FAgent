/// Build-time configuration, read from `--dart-define` / `--dart-define-from-file`.
abstract final class Config {
  /// The Sentry DSN for crash reports; empty (no `config/sentry.local.json`) means nothing is sent,
  /// the log and the queue are still kept.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// The app version in crash reports; the `pubspec.yaml` version unless the build passes
  /// `APP_VERSION`.
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1');
}
