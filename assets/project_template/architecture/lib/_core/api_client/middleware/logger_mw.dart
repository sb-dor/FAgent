import 'package:l/l.dart';
import 'package:meta/meta.dart';
import 'package:{{package}}/_core/api_client/api_client.dart';

/// Logs every request of the `ApiClient` through `l`, so it is in the error log and the archive
/// (docs/rules/controllers.md, "Reporting an error"). It only logs: a failure goes on to the
/// caller, and the controller observer reports it. Never log headers or bodies: they carry tokens.
@immutable
class ApiClient$LoggerMiddleware {
  const ApiClient$LoggerMiddleware({
    this.logRequest = false,
    this.logResponse = true,
    this.logError = true,
  });

  final bool logRequest;
  final bool logResponse;
  final bool logError;

  ApiClientHandler call(ApiClientHandler innerHandler) => (request, context) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (logRequest) l.d('http | [${request.method}] ${request.url.path}');
      final response = await innerHandler(request, context);
      if (logResponse) {
        l.d(
          'http | [${request.method}] ${request.url.path} -> ok | '
          '${stopwatch.elapsedMilliseconds}ms',
        );
      }
      return response;
    } on APIClientException catch (error) {
      if (logError) {
        l.w(
          'http | [${request.method}] ${request.url.path} -> ${switch (error.statusCode) {
            501 => 'unimplemented',
            500 => 'internalError',
            409 => 'aborted',
            404 => 'notFound',
            403 => 'permissionDenied',
            401 => 'unauthenticated',
            400 => 'failedPrecondition',
            < 400 => 'unknownError',
            int statusCode => '$statusCode',
          }} | ${stopwatch.elapsedMilliseconds}ms',
        );
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  };
}
