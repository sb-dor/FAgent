import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';

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
  final Set<int> _collapsedProjects = <int>{};
  final ValueNotifier<ChatHandle?> _chatHandle = ValueNotifier<ChatHandle?>(null);
  String? _selectedChangePath;

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

  /// What the selected chat offers the workspace; `null` without a chat or before it has loaded.
  /// Changes with every new chat view, so it notifies on its own and not through this controller.
  ValueListenable<ChatHandle?> get chatHandle => _chatHandle;

  /// File (absolute path) shown in the Changes tab; `null` means none is chosen.
  String? get selectedChangePath => _selectedChangePath;

  /// Projects whose chats the sidebar hides. Lives with the window, so hiding the sidebar does
  /// not forget it.
  Set<int> get collapsedProjects => Set<int>.unmodifiable(_collapsedProjects);

  @override
  void dispose() {
    _chatHandle.dispose();
    super.dispose();
  }

  /// The chat changed: its handle and the file chosen in Changes no longer apply.
  void _forgetChat() {
    _selectedChangePath = null;
    _chatHandle.value = null;
  }

  /// Stores [handle] of the open chat; a handle of any other chat than the selected one is
  /// ignored.
  void publishChatHandle(ChatHandle handle) {
    if (handle.sessionId != _sessionId) return;
    _chatHandle.value = handle;
  }

  /// Chooses the file the Changes tab shows; `null` clears the choice.
  void selectChange(String? path) {
    if (_selectedChangePath == path) return;
    _selectedChangePath = path;
    notifyListeners();
  }

  /// Collapses project [projectId] in the sidebar, or expands it if it is collapsed.
  void toggleCollapsed(int projectId) {
    if (!_collapsedProjects.remove(projectId)) _collapsedProjects.add(projectId);
    notifyListeners();
  }

  /// Selects [projectId]; the chat selection is cleared when it changes.
  void selectProject(int projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    _sessionId = null;
    _forgetChat();
    notifyListeners();
  }

  /// Forgets the selected project and chat, e.g. when the project is removed.
  void clearSelection() {
    if (_projectId == null && _sessionId == null) return;
    _projectId = null;
    _sessionId = null;
    _forgetChat();
    notifyListeners();
  }

  /// Selects chat [sessionId].
  void selectSession(int? sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    _forgetChat();
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
