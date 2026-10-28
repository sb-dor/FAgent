import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_shortcuts}
/// Window shortcuts: ⌘N starts a chat, ⌘K searches the chats, ⌘\ toggles the sidebar, ⌘J the right pane, ⌘, opens
/// Settings, and Esc leaves Skills or Settings for the chat.
///
/// They are bound above the whole window, so they work while a text field has focus. Esc is bound
/// only on those screens, so the chat keeps it. A menu or dialog handles Esc before it gets here.
/// {@endtemplate}
class WorkspaceShortcuts extends StatelessWidget {
  /// {@macro workspace_shortcuts}
  const WorkspaceShortcuts({required this.child, super.key});

  /// The window.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: scope.dataController,
      builder: (context, _) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): scope.createChat,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): scope.openChatSearch,
          const SingleActivator(LogicalKeyboardKey.backslash, meta: true): scope.toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): () =>
              scope.toggleRightPane(windowWidth: MediaQuery.sizeOf(context).width),
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
              scope.dataController.openView(WorkspaceView.settings),
          if (scope.dataController.view != WorkspaceView.chat)
            const SingleActivator(LogicalKeyboardKey.escape): scope.dataController.backToChat,
        },
        // Something in the window must hold focus, or key events never reach the bindings above.
        child: Focus(autofocus: true, skipTraversal: true, child: child),
      ),
    );
  }
}
