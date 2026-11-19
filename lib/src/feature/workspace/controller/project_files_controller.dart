import 'package:flutter_code_agent/src/feature/file_mention/data/project_files_repository.dart';

/// {@template project_files_controller}
/// The files of a project for the Code view's ⌘P: listed again on every call, so files created
/// since show up.
/// {@endtemplate}
final class ProjectFilesController {
  /// {@macro project_files_controller}
  ProjectFilesController({required this._repository});

  final IProjectFilesRepository _repository;

  /// The files of the project in [root], relative to it and without ignored ones.
  Future<List<String>> list(String root) => _repository.list(root);
}
