import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/command_suggestions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/mention_suggestions.dart';

/// {@template prompt_composer}
/// The prompt field: Enter sends, Shift+Enter adds a line. While a turn runs
/// the send button becomes Stop. Shift+Tab calls [onCycleMode]. [toolbar] (the chips) sits under
/// the field, the send button on its right. Typing `@` suggests project files (arrows
/// choose, Enter or Tab inserts, Escape closes); a `/` at the start of the text suggests the
/// app's and the agent's [commands] the same way. While a permission request waits, Enter and
/// Escape in an empty field call [onAcceptPending] and [onRejectPending].
/// {@endtemplate}
class PromptComposer extends StatefulWidget {
  /// {@macro prompt_composer}
  const PromptComposer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.canStop,
    required this.onSend,
    required this.onStop,
    this.mentionFiles,
    this.onMentionStart,
    this.toolbar = const <Widget>[],
    this.onCycleMode,
    this.commands = const <SlashCommand>[],
    this.onAcceptPending,
    this.onRejectPending,
    super.key,
  });

  /// Prompt text.
  final TextEditingController controller;

  /// Focus of the field.
  final FocusNode focusNode;

  /// A prompt can be sent now.
  final bool canSend;

  /// A turn can be stopped now.
  final bool canStop;

  /// Sends the text.
  final VoidCallback onSend;

  /// Stops the turn.
  final VoidCallback onStop;

  /// Project files to mention; `null` turns mentions off.
  final List<String>? mentionFiles;

  /// A new `@` mention started (time to refresh the file list).
  final VoidCallback? onMentionStart;

  /// Widgets under the field, left of the send button.
  final List<Widget> toolbar;

  /// Switches the permission mode (Shift+Tab); `null` leaves Shift+Tab to the focus.
  final VoidCallback? onCycleMode;

  /// Commands of the agent for the `/` menu (the app's own are added by the menu).
  final List<SlashCommand> commands;

  /// Enter in an empty field allows the waiting permission request; `null` when none waits.
  final VoidCallback? onAcceptPending;

  /// Escape in an empty field rejects the waiting permission request; `null` when none waits.
  final VoidCallback? onRejectPending;

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

/// What the open suggestion list completes.
enum _Trigger { mention, command }

class _PromptComposerState extends State<PromptComposer> {
  _Trigger? _trigger;

  /// Where the typed `@…` or `/…` starts.
  int _start = 0;
  String _query = '';
  List<String> _files = const <String>[];
  List<SlashCommand> _commands = const <SlashCommand>[];
  int _highlighted = 0;

  /// Start of a list closed with Escape: it stays closed while typed on.
  int? _dismissedAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(PromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    // The file and command lists load after the trigger is typed.
    if (_trigger != null &&
        (oldWidget.mentionFiles != widget.mentionFiles || oldWidget.commands != widget.commands)) {
      _search(refresh: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// Number of rows in the open list.
  int get _count => switch (_trigger) {
    _Trigger.mention => _files.length,
    _Trigger.command => _commands.length,
    null => 0,
  };

  bool _selectable(int index) => switch (_trigger) {
    _Trigger.mention => true,
    _Trigger.command => _commands[index].enabled,
    null => false,
  };

  /// Fills the rows for the current trigger; the first selectable one is highlighted.
  ///
  /// With [refresh] the lists were reloaded under an open menu: nothing changes when the rows
  /// are the same, and the highlight stays on its item while that is still listed.
  void _search({bool refresh = false}) {
    final highlightedBefore = _highlighted;
    int keep;
    switch (_trigger) {
      case _Trigger.mention:
        final found = searchFiles(widget.mentionFiles ?? const <String>[], _query);
        if (refresh && listEquals(found, _files)) return;
        keep = refresh && highlightedBefore >= 0 && highlightedBefore < _files.length
            ? found.indexOf(_files[highlightedBefore])
            : -1;
        _files = found;
      case _Trigger.command:
        final found = slashSuggestions(appCommands, widget.commands, _query);
        if (refresh && listEquals(found, _commands)) return;
        keep = refresh && highlightedBefore >= 0 && highlightedBefore < _commands.length
            ? found.indexOf(_commands[highlightedBefore])
            : -1;
        _commands = found;
      case null:
        return;
    }
    _highlighted = keep >= 0
        ? keep
        : List<int>.generate(_count, (i) => i).firstWhere(_selectable, orElse: () => -1);
  }

  void _onText() {
    final value = widget.controller.value;
    final caret = value.selection.baseOffset;
    final collapsed = value.selection.isCollapsed;
    final command = collapsed ? slashQueryAt(value.text, caret) : null;
    final mention = collapsed && widget.mentionFiles != null
        ? mentionQueryAt(value.text, caret)
        : null;
    final trigger = command != null
        ? (_Trigger.command, 0, command)
        : mention != null
        ? (_Trigger.mention, mention.start, mention.query)
        : null;
    if (trigger == null || trigger.$2 == _dismissedAt) {
      if (trigger == null) _dismissedAt = null;
      if (_trigger != null) setState(_close);
      return;
    }
    if (trigger.$1 == _Trigger.mention && (_trigger != _Trigger.mention || _start != trigger.$2)) {
      widget.onMentionStart?.call();
    }
    setState(() {
      _trigger = trigger.$1;
      _start = trigger.$2;
      _query = trigger.$3;
      _search();
    });
  }

  void _close() {
    _trigger = null;
    _files = const <String>[];
    _commands = const <SlashCommand>[];
    _highlighted = 0;
  }

  /// Replaces the typed `@…` or `/…` with [inserted].
  void _insert(String inserted) {
    if (_trigger == null) return;
    final value = widget.controller.value;
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(_start, value.selection.baseOffset, inserted),
      selection: TextSelection.collapsed(offset: _start + inserted.length),
    );
    setState(_close);
  }

  /// Inserts the row at [index] unless it is disabled; the list stays open then.
  void _pick(int index) {
    if (index < 0 || index >= _count || !_selectable(index)) return;
    _insert(_trigger == _Trigger.mention ? '@${_files[index]} ' : '/${_commands[index].name} ');
  }

  /// Moves the highlight [step] rows, skipping the ones that cannot be chosen.
  void _move(int step) {
    for (var i = 1; i <= _count; i++) {
      final index = (_highlighted + step * i) % _count;
      if (_selectable(index)) {
        setState(() => _highlighted = index);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_count > 0) {
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        _move(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _pick(_highlighted);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _dismissedAt = _start;
          _close();
        });
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
      final cycle = widget.onCycleMode;
      if (cycle == null) return KeyEventResult.ignored;
      if (event is KeyDownEvent) cycle();
      return KeyEventResult.handled;
    }
    // A waiting permission request is answered from an empty field only (any text, even a
    // space, is a draft the key must not skip over).
    if (event is KeyDownEvent && widget.controller.text.isEmpty) {
      final answer = key == LogicalKeyboardKey.escape
          ? widget.onRejectPending
          : key == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed
          ? widget.onAcceptPending
          : null;
      if (answer != null) {
        answer();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent || key != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (widget.canSend) widget.onSend();
    return KeyEventResult.handled;
  }

  Widget _sendButton(GeneratedLocalization localization) => widget.canStop
      ? IconButton.filledTonal(
          tooltip: localization.stop,
          onPressed: widget.onStop,
          icon: const Icon(Icons.stop_rounded),
        )
      : ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => IconButton.filled(
            tooltip: localization.send,
            onPressed: widget.canSend && widget.controller.text.trim().isNotEmpty
                ? widget.onSend
                : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Part of the field's tap region: a click keeps the caret.
                if (_count > 0)
                  TextFieldTapRegion(
                    child: switch (_trigger!) {
                      _Trigger.mention => MentionSuggestions(
                        files: _files,
                        highlighted: _highlighted,
                        onSelected: (file) => _pick(_files.indexOf(file)),
                      ),
                      _Trigger.command => CommandSuggestions(
                        commands: _commands,
                        highlighted: _highlighted,
                        onSelected: (command) => _pick(_commands.indexOf(command)),
                      ),
                    },
                  ),
                Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: localization.promptHint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: widget.toolbar,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _sendButton(localization),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
