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
  ({String? itemId, int? projectId})? _skillsTarget;

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
  ///
  /// Going from one screen to another asks [leaveGuard] first (see [whenMayLeave]), so the change
  /// can come a little later than the call, or not at all.
  void openView(WorkspaceView view, {String? section}) {
    if (_view == view && _section == section) return;
    if (_view == view) return _show(view, section);
    whenMayLeave(() => _show(view, section));
  }

  void _show(WorkspaceView view, String? section) {
    _navigations++;
    _view = view;
    _section = section;
    notifyListeners();
  }

  /// Shows the Skills screen on the skill or rule [itemId] (its section follows the id) and, when
  /// [projectId] is given, for that project instead of the selected one. The screen collects the
  /// request with [takeSkillsTarget].
  void openSkills({String? itemId, int? projectId}) {
    _skillsTarget = (itemId: itemId, projectId: projectId);
    if (itemId != null) {
      _section = itemId.startsWith('rule:') ? 'rules' : 'skills';
    } else if (_view != WorkspaceView.skills) {
      _section = null;
    }
    _navigations++;
    _view = WorkspaceView.skills;
    notifyListeners();
  }

  /// The pending [openSkills] request, once: the Skills screen takes it and the next call gets
  /// `null`.
  ({String? itemId, int? projectId})? takeSkillsTarget() {
    final target = _skillsTarget;
    _skillsTarget = null;
    return target;
  }

  /// Returns from Skills or Settings to the same chat (after [leaveGuard] agrees).
  void backToChat() => openView(WorkspaceView.chat);

  /// Asked before the window leaves the open screen, whatever the way out (the back button, Esc,
  /// a shortcut, a new chat); the screen may set it to ask about unsaved work. `false` keeps the
  /// screen open.
  Future<bool> Function()? leaveGuard;

  bool _leaveApproved = false;

  /// Counts the changes of the open screen, so a leaving that waited for the guard can tell that
  /// the window went elsewhere in the meantime.
  int _navigations = 0;

  /// Runs [leave], which moves the window off the open screen: at once when the chat is open or
  /// nothing guards the screen, else once [leaveGuard] agrees. It is dropped when the guard says
  /// no, or when the open screen changed while it was asking. Whatever [leave] does to the view is
  /// not asked about again.
  void whenMayLeave(VoidCallback leave) {
    final guard = leaveGuard;
    if (_view == WorkspaceView.chat || guard == null || _leaveApproved) return leave();
    final navigations = _navigations;
    guard().then((agreed) {
      if (!agreed || navigations != _navigations) return;
      _leaveApproved = true;
      try {
        leave();
      } finally {
        _leaveApproved = false;
      }
    }).ignore();
  }

  /// Selects a tab of the right pane.
  void selectPaneTab(RightPaneTab tab) {
    if (_paneTab == tab) return;
    _paneTab = tab;
    notifyListeners();
  }
}
