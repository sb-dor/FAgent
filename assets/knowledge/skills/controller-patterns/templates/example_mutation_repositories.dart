import 'example.dart';

/// Writes a record. Create versus update is decided here, not in the controller or the widget.
abstract interface class IExampleCreationRepository {
  /// Creates an example, or updates [existing] when it is given.
  Future<Example> save({required String title, required String content, Example? existing});
}

/// Deletes a record.
abstract interface class IExampleDeletionRepository {
  /// Deletes the example with [id].
  Future<void> delete(int id);
}
