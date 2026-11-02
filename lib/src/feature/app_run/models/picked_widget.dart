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
    this.column = 0,
    this.id,
    this.screenshot,
  });

  /// The widget's class, for example `BookingCard`.
  final String name;

  /// The path of the file that creates it, relative to the project (absolute when it is outside).
  final String file;

  /// The 1-based line in [file].
  final int line;

  /// The 1-based column in [file]; `0` when it is not known.
  final int column;

  /// The project's widgets around it, from the nearest one outwards; itself not included.
  final List<PickedAncestor> ancestors;

  /// The inspector's id of the widget, valid until the next pick or the end of the run; `null` when
  /// it is not known.
  final String? id;

  /// The path of a PNG of the widget, relative to the project; `null` when there is none.
  final String? screenshot;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedWidget &&
          other.name == name &&
          other.file == file &&
          other.line == line &&
          other.column == column &&
          other.id == id &&
          other.screenshot == screenshot &&
          listEquals(other.ancestors, ancestors);

  @override
  int get hashCode =>
      Object.hash(name, file, line, column, id, screenshot, Object.hashAll(ancestors));

  @override
  String toString() => 'PickedWidget($name, $file:$line:$column)';
}

/// A widget of the project around a [PickedWidget], which the user can switch the card to.
@immutable
final class PickedAncestor {
  /// Creates an ancestor.
  const PickedAncestor({
    required this.name,
    required this.file,
    required this.line,
    required this.id,
    this.column = 0,
  });

  /// The widget's class, for example `BookingList`.
  final String name;

  /// The path of the file that creates it, relative to the project (absolute when it is outside).
  final String file;

  /// The 1-based line in [file].
  final int line;

  /// The 1-based column in [file]; `0` when it is not known.
  final int column;

  /// The inspector's id of the widget, as [PickedWidget.id].
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedAncestor &&
          other.name == name &&
          other.file == file &&
          other.line == line &&
          other.column == column &&
          other.id == id;

  @override
  int get hashCode => Object.hash(name, file, line, column, id);

  @override
  String toString() => 'PickedAncestor($name, $file:$line:$column)';
}
