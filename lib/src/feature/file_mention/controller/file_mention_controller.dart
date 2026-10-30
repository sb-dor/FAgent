import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/file_mention/data/project_files_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'file_mention_controller.freezed.dart';

@freezed
sealed class FileMentionState with _$FileMentionState {
  const factory FileMentionState.initial() = FileMention$InitialState;

  /// Loading; [files] is the previous list.
  const factory FileMentionState.inProgress({@Default(<String>[]) List<String> files}) =
      FileMention$InProgressState;

  /// The list could not be read; [files] is the previous list.
  const factory FileMentionState.error({@Default(<String>[]) List<String> files, Object? error}) =
      FileMention$ErrorState;

  const factory FileMentionState.completed({required List<String> files}) =
      FileMention$CompletedState;
}

/// The project's files for `@` mentions. Reloaded when a mention starts, so
/// files the agent created show up. Droppable, not Sequential: each `@`
/// asks for a reload, and one already running gives the same answer.
final class FileMentionController extends StateController<FileMentionState>
    with DroppableControllerHandler {
  FileMentionController({
    required this._repository,
    super.initialState = const FileMentionState.initial(),
  });

  final IProjectFilesRepository _repository;

  /// Current list (possibly stale while loading).
  List<String> get files => switch (state) {
    FileMention$InitialState() => const <String>[],
    FileMention$InProgressState(:final files) => files,
    FileMention$ErrorState(:final files) => files,
    FileMention$CompletedState(:final files) => files,
  };

  /// Those of [paths] that are files inside [root] (links resolved). A query,
  /// not a state change: sending a prompt waits for it.
  Future<List<String>> insideProject(String root, List<String> paths) => paths.isEmpty
      ? Future<List<String>>.value(const <String>[])
      : _repository.insideProject(root, paths);

  /// Loads the files of [root]; a load already running wins.
  void load(String root) => handle(
    () async {
      setState(FileMentionState.inProgress(files: files));
      final loaded = await _repository.list(root);
      setState(FileMentionState.completed(files: loaded));
    },
    error: (error, stackTrace) async =>
        setState(FileMentionState.error(files: files, error: error)),
  );
}
