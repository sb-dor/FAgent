import 'package:shared_preferences/shared_preferences.dart';
import 'package:{{package}}/src/_core/utils/api_client.dart';

/// Adds the `Authorization` header to every request of the `ApiClient`, from
/// [AuthenticationHeaders] in memory: no storage is read per request.
///
/// ```dart
/// final authenticationHeaders = AuthenticationHeaders(sharedPreferences: sharedPreferences);
/// final apiClient = ApiClient(
///   baseUrl: Config.apiBaseUrl,
///   middlewares: <ApiClientMiddleware>[
///     const ApiClient$LoggerMiddleware().call,
///     AuthenticationInterceptor(authenticationHeaders: authenticationHeaders).call,
///   ],
/// );
/// ```
class AuthenticationInterceptor {
  AuthenticationInterceptor({required this._authenticationHeaders});

  final AuthenticationHeaders _authenticationHeaders;

  ApiClientHandler call(ApiClientHandler innerHandler) => (request, context) async {
    final headers = _authenticationHeaders.headers();
    if (headers.isNotEmpty) request.headers.addAll(headers);
    return innerHandler(request, context);
  };
}

/// The token of the signed-in user, in memory.
///
/// It is read from [SharedPreferences] once, when this object is created, and stays in memory:
/// requests read the field, never the storage. [update] (sign-in, a refreshed token) and [clear]
/// (sign-out, an expired session) change memory and storage together, so the next request
/// already carries the new value. Create one instance at startup and pass it to whatever signs
/// in, refreshes and signs out.
class AuthenticationHeaders {
  AuthenticationHeaders({required SharedPreferences sharedPreferences})
    : _sharedPreferences = sharedPreferences,
      _token = sharedPreferences.getString(_tokenKey);

  /// The key of the token in [SharedPreferences].
  static const String _tokenKey = 'token';

  final SharedPreferences _sharedPreferences;

  String? _token;

  /// The current token, or `null` when signed out.
  String? get token => _token;

  /// Keeps [token] (after sign-in or a refresh): in memory at once, then in the storage.
  Future<void> update(String token) async {
    _token = token;
    await _sharedPreferences.setString(_tokenKey, token);
  }

  /// Forgets the token (sign-out, an expired session): in memory at once, then in the storage.
  Future<void> clear() async {
    _token = null;
    await _sharedPreferences.remove(_tokenKey);
  }

  /// The headers of an authenticated request; empty when signed out. Never log them: they carry
  /// the token.
  Map<String, String> headers() => <String, String>{
    if (_token case final String token) 'Authorization': 'Bearer $token',
  };
}
