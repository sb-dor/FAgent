import 'package:flutter/foundation.dart';

/// A domain entity: immutable, final fields, `copyWith` for functional updates.
@immutable
class Example {
  /// Creates the entity.
  const Example({required this.id, required this.name, this.description});

  /// Server id.
  final int id;

  /// Display name.
  final String name;

  /// Optional text; `null` when absent.
  final String? description;

  /// A copy with the given fields replaced. Nullable fields take a [ValueGetter], so passing
  /// `() => null` clears them while omitting the argument keeps the old value.
  Example copyWith({int? id, String? name, ValueGetter<String?>? description}) => Example(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description != null ? description() : this.description,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Example && other.id == id && other.name == name && other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);
}
