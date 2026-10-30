import 'package:flutter/foundation.dart';

/// Which project and chat the window shows.
class WorkspaceDataController with ChangeNotifier {
  int? _projectId;
  int? _sessionId;

  /// Selected project.
  int? get projectId => _projectId;

  /// Selected chat (inside [projectId]).
  int? get sessionId => _sessionId;

  /// Selects [projectId]; the chat selection is cleared when it changes.
  void selectProject(int projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    _sessionId = null;
    notifyListeners();
  }

  /// Selects chat [sessionId].
  void selectSession(int? sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    notifyListeners();
  }
}
