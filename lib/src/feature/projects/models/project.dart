import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:meta/meta.dart';

/// {@template project}
/// A folder opened in the app.
/// {@endtemplate}
@immutable
class Project {
  /// {@macro project}
  const Project({
    required this.id,
    required this.path,
    required this.name,
    required this.isFlutter,
    this.trustedAt,
  });

  /// Maps a database row.
  factory Project.fromRow(ProjectRow row) => Project(
    id: row.id,
    path: row.path,
    name: row.name,
    isFlutter: row.isFlutter,
    trustedAt: row.trustedAt,
  );

  /// `projects.id`.
  final int id;

  /// Absolute folder path.
  final String path;

  /// Folder name shown in the sidebar.
  final String name;

  /// Has a `pubspec.yaml` depending on `flutter`.
  final bool isFlutter;

  /// When the user allowed agents to run the folder's settings and hooks.
  final DateTime? trustedAt;

  /// Whether agent sessions may start here.
  bool get isTrusted => trustedAt != null;

  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.path == path &&
      other.name == name &&
      other.isFlutter == isFlutter &&
      other.trustedAt == trustedAt;

  @override
  int get hashCode => Object.hash(id, path, name, isFlutter, trustedAt);
}
