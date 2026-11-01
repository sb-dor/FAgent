import 'example.dart';
import 'example_json_converter.dart';

/// Stand-in for the app's shared service (an API client, a database, the file system).
/// A real project already has one; the repository receives it through its constructor.
abstract interface class ExampleService {
  /// Reads [path] and returns the decoded JSON body.
  Future<Map<String, Object?>> get(String path, {Map<String, Object?>? queryParameters});
}

/// Reads examples. Controllers depend on this interface, so tests can pass a fake.
abstract interface class IExampleRepository {
  /// Examples whose name contains [query]; all of them when it is empty.
  Future<List<Example>> examples({String query = ''});
}

/// [IExampleRepository] over [ExampleService]. There is no datasource layer between the two:
/// the implementation sends the request and converts the response itself.
final class ExampleRepositoryImpl implements IExampleRepository {
  /// Creates the repository.
  ExampleRepositoryImpl({required this._service});

  final ExampleService _service;

  static const ExampleJsonConverter _converter = ExampleJsonConverter();

  @override
  Future<List<Example>> examples({String query = ''}) async {
    final body = await _service.get('/examples', queryParameters: {'q': query});
    final data = body['data'];
    if (data is! List<Object?>) return const <Example>[];
    return data.whereType<Map<String, Object?>>().map(_converter.convert).toList();
  }
}
