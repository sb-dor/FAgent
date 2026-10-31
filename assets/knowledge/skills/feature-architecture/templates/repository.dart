/// Reads and writes examples.
abstract interface class IExampleRepository {
  /// Every example.
  Future<List<Example>> examples();

  /// The examples now, then after every change. Closes when the subscription is cancelled.
  Stream<List<Example>> watch();
}

/// [IExampleRepository] backed by the database. Services come through the constructor.
final class ExampleRepositoryImpl implements IExampleRepository {
  /// Creates the repository.
  ExampleRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<List<Example>> examples() async {
    final rows = await _database.select(_database.exampleTable).get();
    return rows.map(_toExample).toList();
  }

  @override
  Stream<List<Example>> watch() => _database
      .select(_database.exampleTable)
      .watch()
      .map((rows) => rows.map(_toExample).toList());

  Example _toExample(ExampleTableData row) => Example(id: row.id, name: row.name);
}
