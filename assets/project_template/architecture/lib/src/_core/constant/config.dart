// ignore_for_file: avoid_classes_with_only_static_members

/// Config for app.
abstract final class Config {
  // --- ENVIRONMENT --- //

  /// Environment flavor.
  /// e.g. development, staging, production
  static final EnvironmentFlavor environment = EnvironmentFlavor.from(
    const String.fromEnvironment('ENVIRONMENT', defaultValue: 'development'),
  );

  static const bool alpha = bool.fromEnvironment('ALPHA', defaultValue: false);

  static const bool beta = bool.fromEnvironment('BETA', defaultValue: false);

  // --- API --- //

  /// Base url for api.
  /// e.g. https://api.domain.tld
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.domain.tld',
  );

  /// Timeout for connecting to the server, for a timeout middleware of the `ApiClient`
  /// (the client has none of its own).
  /// e.g. 15000
  static const Duration apiConnectTimeout = Duration(
    milliseconds: int.fromEnvironment('API_CONNECT_TIMEOUT', defaultValue: 15000),
  );

  /// Timeout for receiving the response, for a timeout middleware of the `ApiClient`.
  /// e.g. 10000
  static const Duration apiReceiveTimeout = Duration(
    milliseconds: int.fromEnvironment('API_RECEIVE_TIMEOUT', defaultValue: 10000),
  );

  /// Cache lifetime.
  /// Refetch datasources from url when cache is expired.
  /// e.g. 1 hour
  static const Duration cacheLifetime = Duration(hours: 1);

  // --- DATABASE --- //

  /// Database file name by default.
  /// e.g. sqlite means "sqlite.db" for native platforms and "sqlite" for web platform.
  static const String databaseName = String.fromEnvironment(
    'DATABASE_NAME',
    defaultValue: 'sqlite',
  );

  /// Whether to use in-memory database.
  static const bool inMemoryDatabase = bool.fromEnvironment(
    'IN_MEMORY_DATABASE',
    defaultValue: false,
  );

  // --- AUTHENTICATION --- //

  /// Minimum length of password.
  /// e.g. 8
  static const int passwordMinLength = int.fromEnvironment('PASSWORD_MIN_LENGTH', defaultValue: 6);

  /// Maximum length of password.
  /// e.g. 32
  static const int passwordMaxLength = int.fromEnvironment('PASSWORD_MAX_LENGTH', defaultValue: 32);

  // --- LAYOUT --- //

  /// Maximum screen layout width for screen with list view.
  static const int maxScreenLayoutWidth = int.fromEnvironment(
    'MAX_LAYOUT_WIDTH',
    defaultValue: 768,
  );
}

/// Environment flavor.
/// e.g. development, staging, production
enum EnvironmentFlavor {
  /// Development
  development('development'),
  production('production');

  /// Create environment flavor.
  const EnvironmentFlavor(this.value);

  /// Create environment flavor from string.
  factory EnvironmentFlavor.from(String? value) => switch (value?.trim().toLowerCase()) {
    'development' || 'debug' || 'develop' || 'dev' => development,
    'production' || 'release' || 'prod' || 'prd' => production,
    _ => const bool.fromEnvironment('dart.vm.product') ? production : development,
  };

  /// development, staging, production
  final String value;

  /// Whether the environment is development.
  bool get isDevelopment => this == development;

  /// Whether the environment is production.
  bool get isProduction => this == production;
}
