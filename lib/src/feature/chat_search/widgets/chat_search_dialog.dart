import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat_search/controller/chat_search_controller.dart';
import 'package:flutter_code_agent/src/feature/chat_search/data/chat_search_repository.dart';
import 'package:flutter_code_agent/src/feature/chat_search/models/chat_search_result.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// Asks which chat to open. Resolves to the chosen chat, or `null` when the dialog was dismissed.
Future<ChatSearchResult?> showChatSearch(BuildContext context) =>
    showDialog<ChatSearchResult>(context: context, builder: (context) => const ChatSearchDialog());

/// {@template chat_search_dialog}
/// A search field over the titles of all chats. ↑ and ↓ move through the results, Enter picks the
/// highlighted one, Esc closes the dialog.
/// {@endtemplate}
class ChatSearchDialog extends StatefulWidget {
  /// {@macro chat_search_dialog}
  const ChatSearchDialog({super.key});

  /// Width of the dialog.
  static const double width = 560;

  /// Height of one result.
  static const double rowHeight = 52;

  /// Results shown without scrolling.
  static const int visibleRows = 8;

  @override
  State<ChatSearchDialog> createState() => _ChatSearchDialogState();
}

class _ChatSearchDialogState extends State<ChatSearchDialog> {
  late final ChatSearchController _controller;
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _highlighted = 0;

  /// The latest completed answer; stays on screen while the next one is searched.
  List<ChatSearchResult> _results = const <ChatSearchResult>[];
  bool _completedOnce = false;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    _controller = ChatSearchController(
      repository: ChatSearchRepositoryImpl(database: Dependencies.of(context).database),
    )..search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onState(ChatSearchState state) {
    if (state is! ChatSearch$CompletedState) return;
    setState(() {
      _results = state.results;
      _completedOnce = true;
      _highlighted = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() => _highlighted = (_highlighted + delta).clamp(0, _results.length - 1));
    _reveal();
  }

  void _reveal() {
    if (!_scroll.hasClients) return;
    const height = ChatSearchDialog.rowHeight;
    final top = _highlighted * height;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + height > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + height - position.viewportDimension);
    }
  }

  void _pick(int index) {
    // Enter reaches here as a key and as the field's action; the dialog must close only once.
    if (_picked || index < 0 || index >= _results.length) return;
    _picked = true;
    Navigator.pop(context, _results[index]);
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ChatSearchDialog.width),
        child: StateConsumer<ChatSearchController, ChatSearchState>(
          controller: _controller,
          listener: (context, controller, previous, current) => _onState(current),
          builder: (context, state, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                  const SingleActivator(LogicalKeyboardKey.enter): () => _pick(_highlighted),
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _pick(_highlighted),
                },
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  style: theme.textTheme.bodyMedium,
                  textInputAction: TextInputAction.search,
                  onChanged: _controller.search,
                  onSubmitted: (_) => _pick(_highlighted),
                  decoration: InputDecoration(
                    hintText: localization.searchChats,
                    prefixIcon: Icon(Icons.search, size: 16, color: colors.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
              Divider(height: 1, color: colors.border),
              if (state is ChatSearch$ErrorState)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    localization.somethingWentWrong,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                  ),
                )
              else if (_completedOnce && _results.isEmpty && state is! ChatSearch$InProgressState)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    localization.noSearchResults,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                )
              else if (_results.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: ChatSearchDialog.rowHeight * ChatSearchDialog.visibleRows,
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemExtent: ChatSearchDialog.rowHeight,
                    itemCount: _results.length,
                    itemBuilder: (context, index) => _ResultRow(
                      result: _results[index],
                      highlighted: index == _highlighted,
                      onTap: () => _pick(index),
                      onHover: () => setState(() => _highlighted = index),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final ChatSearchResult result;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final title = result.title.isEmpty ? Localization.of(context).untitledChat : result.title;
    final date = MaterialLocalizations.of(context).formatShortDate(result.updatedAt);
    return Semantics(
      button: true,
      selected: highlighted,
      child: Material(
        color: highlighted ? colors.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onHover: (hovering) {
            if (hovering) onHover();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${result.projectName} · $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
