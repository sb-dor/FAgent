import 'package:flutter/foundation.dart';

/// What the window shows besides the chat.
enum WorkspaceView {
  /// Sidebar, chat and the right pane.
  chat,

  /// The Skills and rules screen.
  skills,

  /// The Settings screen.
  settings,
}

/// Tabs of the right pane.
enum RightPaneTab {
  /// Files changed in the chat.
  changes,

  /// Running app, devices and logs.
  run,

  /// The agent's plan.
  plan,
}

/// Which project and chat the window shows, and which screen and pane tab are open.
class WorkspaceDataController with ChangeNotifier {
  int? _projectId;
  int? _sessionId;
  WorkspaceView _view = WorkspaceView.chat;
  String? _section;
  RightPaneTab _paneTab = RightPaneTab.changes;

  /// Selected project.
  int? get projectId => _projectId;

  /// Selected chat (inside [projectId]).
  int? get sessionId => _sessionId;

  /// The open screen; the chat selection is kept while another screen is open.
  WorkspaceView get view => _view;

  /// Open section of the Skills or Settings screen; `null` means its first one.
  String? get section => _section;

  /// Selected tab of the right pane.
  RightPaneTab get paneTab => _paneTab;

  /// Selects [projectId]; the chat selection is cleared when it changes.
  void selectProject(int projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    _sessionId = null;
    notifyListeners();
  }

  /// Forgets the selected project and chat, e.g. when the project is removed.
  void clearSelection() {
    if (_projectId == null && _sessionId == null) return;
    _projectId = null;
    _sessionId = null;
    notifyListeners();
  }

  /// Selects chat [sessionId].
  void selectSession(int? sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    notifyListeners();
  }

  /// Shows [view], on its [section] if given.
  void openView(WorkspaceView view, {String? section}) {
    if (_view == view && _section == section) return;
    _view = view;
    _section = section;
    notifyListeners();
  }

  /// Returns from Skills or Settings to the same chat.
  void backToChat() => openView(WorkspaceView.chat);

  /// Selects a tab of the right pane.
  void selectPaneTab(RightPaneTab tab) {
    if (_paneTab == tab) return;
    _paneTab = tab;
    notifyListeners();
  }
}
