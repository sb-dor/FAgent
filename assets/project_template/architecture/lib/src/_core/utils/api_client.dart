// The HTTP client of the app (PlugFox's template): one instance, created in
// `initialize_dependencies.dart` with the base URL and the middlewares (authentication, retry,
// logging), is passed to every data provider. It returns the decoded JSON body, and every failure
// leaves it as an [APIClientException]: data providers map the server's codes in
// [APIClientException.data] to the app's own exceptions (see docs/rules/repositories.md).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http_package;

/// A function that takes a [http_package.BaseRequest] and returns a [http_package.StreamedResponse].
/// The [context] parameter is a map that can be used to store data that should be available to all middleware.
typedef ApiClientHandler = Future<APIClientResponse> Function(
  APIClientRequest request,
  Map<String, Object?> context,
);

/// A function that takes a [ApiClientHandler] and returns a [ApiClientHandler].
typedef ApiClientMiddleware = ApiClientHandler Function(ApiClientHandler innerHandler);

/// A wrapper for [ApiClientMiddleware] that allows for optional handlers.
extension type ApiClientMiddlewareWrapper._(ApiClientMiddleware _fn) {
  /// Creates a new [ApiClientMiddleware] from the given callbacks.
  factory ApiClientMiddlewareWrapper({
    Future<void> Function(APIClientRequest request, Map<String, Object?> context)? onRequest,
    Future<void> Function(APIClientResponse response, Map<String, Object?> context)? onResponse,
    Future<void> Function(Object error, StackTrace stackTrace, Map<String, Object?> context)?
    onError,
  }) => ApiClientMiddlewareWrapper._(
    (innerHandler) => (request, context) async {
      await onRequest?.call(request, context);
      try {
        final response = await innerHandler(request, context);
        await onResponse?.call(response, context);
        return response;
      } on Object catch (error, stackTrace) {
        await onError?.call(error, stackTrace, context);
        rethrow;
      }
    },
  );

  /// Merges the given [middlewares] into a single [ApiClientMiddleware].
  factory ApiClientMiddlewareWrapper.merge(List<ApiClientMiddleware> middlewares) =>
      ApiClientMiddlewareWrapper._(
        middlewares.length == 1
            ? middlewares.single
            : (handler) =>
                  middlewares.reversed.fold(handler, (handler, middleware) => middleware(handler)),
      );

  /// Call the wrapped [ApiClientMiddleware] with the given [innerHandler].
  ApiClientHandler call(ApiClientHandler innerHandler) => _fn(innerHandler);
}

/// An HTTP request with a JSON-encoded body.
extension type APIClientRequest(http_package.BaseRequest _request)
    implements http_package.BaseRequest {}

/// An HTTP response with a JSON-encoded body.
final class APIClientResponse {
  /// Create a new HTTP response with a JSON-encoded body.
  APIClientResponse.json(
    this.body, {
    required this.statusCode,
    required this.headers,
    required this.contentLength,
    required this.persistentConnection,
    required this.request,
  });

  final int statusCode;

  final Map<String, String> headers;

  final int contentLength;

  final Map<String, Object?> body;

  final bool persistentConnection;

  final APIClientRequest request;
}

/// {@template api_client}
/// An HTTP client that sends requests to a REST API.
/// {@endtemplate}
class ApiClient /* with http_package.BaseClient implements http_package.Client */ {
  ApiClient({
    required String baseUrl,
    http_package.Client? client,
    Iterable<ApiClientMiddleware>? middlewares,
  }) : _baseUrl = Uri.parse(
         baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       ),
       assert(!baseUrl.endsWith('//'), 'Invalid base URL.') {
    // Create the HTTP client.
    final internalClient = _client = client ?? http_package.Client();

    // Create the final middleware.
    final mw = ApiClientMiddlewareWrapper.merge([
      /* default middlewares before custom middlewares */
      ...?middlewares,
      /* default middlewares after custom middlewares */
    ]);

    // Create the handler.
    _handler = _createHandler(internalClient, mw.call);
  }

  final Uri _baseUrl;

  late final http_package.Client _client;

  late final ApiClientHandler _handler;

  /// Closes the connections. Call it in `$disposeApp`; the client is unusable afterwards.
  void close() => _client.close();

  /// Merges the given [path] with the base URL.
  static Uri _mergePath(Uri base, String path, [Map<String, String>? query]) {
    final Uri url;
    if (path.startsWith('http')) {
      url = Uri.parse(path);
    } else {
      var method = path;
      while (method.startsWith('/')) method = method.substring(1);
      url = base.replace(path: '${base.path}/$method');
    }
    return query == null || query.isEmpty
        ? url
        : url.replace(queryParameters: <String, String>{...url.queryParameters, ...query});
  }

  /// Sends a non-streaming [http_package.Request] and returns a non-streaming [http_package.Response].
  static Future<APIClientResponse> _sendUnstreamed({
    required ApiClientHandler handler,
    required String method,
    required Uri url,
    required Map<String, String>? headers,
    required Map<String, Object?>? body,
    required Map<String, Object?> context,
  }) {
    final request = http_package.Request(method, url)..maxRedirects = 5;
    request.headers['Accept'] = 'application/json';
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      // Setting `bodyBytes` sets the content length too; a `Request` throws if it is set directly.
      request
        ..headers['Content-Type'] = 'application/json; charset=UTF-8'
        ..bodyBytes = const JsonEncoder().fuse(const Utf8Encoder()).convert(body);
    }
    return handler(APIClientRequest(request), context);
  }

  /// Sends a GET request to the given [path], with [query] added to the URL.
  Future<APIClientResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => _send('GET', path, query: query, headers: headers);

  /// Sends a POST request to the given [path].
  Future<APIClientResponse> post(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) => _send('POST', path, headers: headers, body: body);

  /// Sends a PUT request to the given [path].
  Future<APIClientResponse> put(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) => _send('PUT', path, headers: headers, body: body);

  /// Sends a PATCH request to the given [path].
  Future<APIClientResponse> patch(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) => _send('PATCH', path, headers: headers, body: body);

  /// Sends a DELETE request to the given [path], with [query] added to the URL.
  Future<APIClientResponse> delete(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) => _send('DELETE', path, query: query, headers: headers, body: body);

  Future<APIClientResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) => _sendUnstreamed(
    handler: _handler,
    method: method,
    url: _mergePath(_baseUrl, path, query),
    headers: headers,
    body: body,
    context: <String, Object?>{},
  );
}

/// Creates a new [ApiClientHandler] from the given [internalClient] and [middleware].
ApiClientHandler _createHandler(
  http_package.Client internalClient,
  ApiClientMiddleware middleware,
) {
  // Check if the completer is completed and throw an error if it is.
  void throwError(Completer<APIClientResponse> completer, Object error, StackTrace stackTrace) {
    if (completer.isCompleted)
      return;
    else if (error is APIClientException)
      completer.completeError(error, stackTrace);
    else
      completer.completeError(
        APIClientException$Client(
          code: 'unknown_error',
          message: 'Unknown error.',
          statusCode: 0,
          error: error,
          data: null,
        ),
        stackTrace,
      );
  }

  // JSON decoder.
  final jsonDecoder = const Utf8Decoder()
      .fuse(const JsonDecoder())
      .cast<Object?, Map<String, Object?>>();

  // HTTP handler.
  Future<APIClientResponse> httpHandler(APIClientRequest request, Map<String, Object?> context) {
    final completer = Completer<APIClientResponse>();
    // Handle top level errors.
    runZonedGuarded<void>(
      () async {
        assert(request.url.scheme.startsWith('http'), 'Invalid URL: ${request.url}');

        // Send a base request.
        final http_package.StreamedResponse streamedResponse;
        try {
          streamedResponse = await internalClient.send(request._request);
        } on Object catch (error, stackTrace) {
          throwError(
            completer,
            APIClientException$Network(
              code: 'network_error',
              message: 'Failed to send request due to a network error.',
              statusCode: 0,
              error: error,
              data: null,
            ),
            stackTrace,
          );
          return;
        }

        // Check response.
        int statusCode;
        try {
          statusCode = streamedResponse.statusCode;
          // The server's error body (`{"code": "email_taken", "message": "..."}`) goes into the
          // exception's `data`, so a data provider can map the code to the app's exception.
          final errorBody = statusCode > 399 && statusCode < 500
              ? await _readErrorBody(streamedResponse, jsonDecoder)
              : null;
          switch (statusCode) {
            case > 499:
              throw APIClientException$Network(
                code: 'internal_server_error',
                message: 'Internal server error.',
                statusCode: statusCode,
                error: null,
                data: null,
              );
            case 401 || 403:
              throw APIClientException$Authorization(
                code: 'unauthorized_error',
                message: 'User is not authorized.',
                statusCode: statusCode,
                error: null,
                data: errorBody,
              );
            case > 399:
              throw APIClientException$Client(
                code: 'bad_request_error',
                message: 'Bad request.',
                statusCode: statusCode,
                error: null,
                data: errorBody,
              );
            case > 299:
              throw APIClientException$Client(
                code: 'redirection_error',
                message: 'Request was redirected.',
                statusCode: statusCode,
                error: null,
                data: null,
              );
            default:
              break;
          }
        } on Object catch (error, stackTrace) {
          throwError(completer, error, stackTrace);
          return;
        }

        // Read the response stream. A chunked or compressed response has no content length, so
        // the body is read whenever the length is unknown, and its type is checked once it is
        // known not to be empty.
        int contentLength;
        Uint8List bytes;
        try {
          bytes = streamedResponse.contentLength == 0
              ? Uint8List(0)
              : await streamedResponse.stream.toBytes();
          contentLength = bytes.length;
          final contentType = streamedResponse.headers['content-type']?.toLowerCase() ?? '';
          if (bytes.isNotEmpty && !contentType.contains('application/json')) {
            throwError(
              completer,
              APIClientException$Client(
                code: 'invalid_content_type_error',
                message: 'Response content type is not application/json.',
                statusCode: statusCode,
                error: null,
                data: null,
              ),
              StackTrace.current,
            );
            return;
          }
        } on Object catch (error, stackTrace) {
          throwError(
            completer,
            APIClientException$Network(
              code: 'body_stream_error',
              message: 'Failed to read response stream.',
              statusCode: streamedResponse.statusCode,
              error: error,
              data: null,
            ),
            stackTrace,
          );
          return;
        }

        // Decode the response.
        APIClientResponse response;
        try {
          final body = bytes.isEmpty ? <String, Object?>{} : jsonDecoder.convert(bytes);
          response = APIClientResponse.json(
            body,
            statusCode: streamedResponse.statusCode,
            headers: streamedResponse.headers,
            contentLength: contentLength,
            persistentConnection: streamedResponse.persistentConnection,
            request: request,
          );
        } on Object catch (error, stackTrace) {
          throwError(
            completer,
            APIClientException$Client(
              code: 'decoding_error',
              message: 'Failed to decode response.',
              statusCode: streamedResponse.statusCode,
              error: error,
              data: bytes,
            ),
            stackTrace,
          );
          return;
        }

        // Complete the completer.
        if (!completer.isCompleted) completer.complete(response);
      },
      (error, stackTrace) {
        throwError(completer, error, stackTrace);
      },
    );
    return completer.future;
  }

  return middleware(httpHandler);
}

/// The JSON body of an error response, or `null` when it is empty, not JSON or unreadable.
Future<Map<String, Object?>?> _readErrorBody(
  http_package.StreamedResponse response,
  Converter<Object?, Map<String, Object?>> decoder,
) async {
  try {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('application/json')) return null;
    final bytes = await response.stream.toBytes();
    return bytes.isEmpty ? null : decoder.convert(bytes);
  } on Object {
    return null;
  }
}

// --- Errors --- //

@immutable
sealed class APIClientException implements Exception {
  const APIClientException();

  /// HTTP status code.
  /// If the request was not sent, this will be 0.
  abstract final int statusCode;

  /// Error code.
  abstract final String code;

  /// Error message.
  abstract final String message;

  /// The source error object.
  abstract final Object? error;

  /// Additional data: the server's decoded error body (a `Map<String, Object?>`) for a 4xx
  /// response that had one, the raw bytes of a body that failed to decode.
  abstract final Object? data;

  @override
  String toString() => message;
}

/// Client exception.
final class APIClientException$Client extends APIClientException {
  const APIClientException$Client({
    required this.code,
    required this.message,
    required this.statusCode,
    this.error,
    this.data,
  });

  @override
  final String code;

  @override
  final String message;

  @override
  final int statusCode;

  @override
  final Object? error;

  @override
  final Object? data;
}

/// Network exception.
final class APIClientException$Network extends APIClientException {
  const APIClientException$Network({
    required this.code,
    required this.message,
    required this.statusCode,
    this.error,
    this.data,
  });

  @override
  final String code;

  @override
  final String message;

  @override
  final int statusCode;

  @override
  final Object? error;

  @override
  final Object? data;
}

/// Authorization exception.
final class APIClientException$Authorization extends APIClientException {
  const APIClientException$Authorization({
    required this.code,
    required this.message,
    required this.statusCode,
    this.error,
    this.data,
  });

  @override
  final String code;

  @override
  final String message;

  @override
  final int statusCode;

  @override
  final Object? error;

  @override
  final Object? data;
}
