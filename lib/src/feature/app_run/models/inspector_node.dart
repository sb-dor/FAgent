import 'package:freezed_annotation/freezed_annotation.dart';

part 'inspector_node.freezed.dart';

/// {@template inspector_node}
/// A widget as the widget inspector of a running app describes it: its name and the place that
/// creates it in the source.
/// {@endtemplate}
@freezed
abstract class InspectorNode with _$InspectorNode {
  /// {@macro inspector_node}
  const factory InspectorNode({
    /// The widget's description, for example `BookingCard`.
    required String name,

    /// The inspector's id of the widget (`valueId`); valid until its object group is disposed.
    required String id,

    /// The file that creates the widget, as the app names it (a `file://` URI); `null` when the
    /// app does not track widget creation.
    String? fileUri,

    /// The 1-based line in [fileUri].
    int? line,

    /// The 1-based column in [fileUri].
    int? column,

    /// Whether the user's own project creates the widget (`createdByLocalProject`), not Flutter or
    /// a package.
    @Default(false) bool local,
  }) = _InspectorNode;

  const InspectorNode._();

  /// The node of the inspector's JSON [json]: `description`, `valueId`, `creationLocation`
  /// (`file`, `line`, `column`) and `createdByLocalProject`.
  factory InspectorNode.fromJson(Map<String, Object?> json) {
    final location = json['creationLocation'];
    final place = location is Map ? Map<String, Object?>.from(location) : null;
    final file = place?['file'];
    final line = place?['line'];
    final column = place?['column'];
    final description = json['description'];
    final valueId = json['valueId'];
    return InspectorNode(
      name: description is String ? description : '',
      id: valueId is String ? valueId : '',
      fileUri: file is String ? file : null,
      line: line is int ? line : null,
      column: column is int ? column : null,
      local: json['createdByLocalProject'] == true,
    );
  }
}
