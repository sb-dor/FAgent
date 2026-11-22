/// The HTTP client of the apps of this repository, its middlewares, and the failures a feature
/// expects (`ExpectedException`, `RejectedException`).
library;

export 'package:api_client/src/api_client.dart';
export 'package:api_client/src/expected_exception.dart';
export 'package:api_client/src/middleware/authentication_interceptor.dart';
export 'package:api_client/src/middleware/logger_mw.dart';
