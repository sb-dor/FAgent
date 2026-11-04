import 'package:flutter/foundation.dart';

/// Files edited in the Code view and not saved yet, app-wide (the Code view keeps them; the chat
/// warns before sending and quitting asks first while any of them is unsaved). Listeners hear
/// every change of [count].
abstract interface class IUnsavedFiles implements Listenable {
  /// Unsaved files of project [projectId] (`projects.id`), or of every project when `null`.
  int count({int? projectId});

  /// Saves the unsaved files of [projectId], or of every project when `null`; `true` when all of
  /// them were saved (a file changed on disk or a failed write stays unsaved).
  Future<bool> saveAll({int? projectId});

  /// Closes the files of project [projectId] without saving: the project was removed.
  void discard(int projectId);
}
