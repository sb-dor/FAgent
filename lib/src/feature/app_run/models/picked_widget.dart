import 'package:flutter/foundation.dart';

/// A widget the user pointed at in the running app.
@immutable
final class PickedWidget {
  /// Creates a picked widget.
  const PickedWidget({
    required this.name,
    required this.file,
    required this.line,
    required this.ancestors,
  });

  /// The widget's class, for example `BookingCard`.
  final String name;

  /// The project-relative path of the file that creates it.
  final String file;

  /// The line in [file].
  final int line;

  /// The widget chain around it, in the order the picker reports it.
  final List<String> ancestors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedWidget &&
          other.name == name &&
          other.file == file &&
          other.line == line &&
          listEquals(other.ancestors, ancestors);

  @override
  int get hashCode => Object.hash(name, file, line, Object.hashAll(ancestors));

  @override
  String toString() => 'PickedWidget($name, $file:$line)';
}
