import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/mention_suggestions.dart';

/// {@template prompt_composer}
/// The prompt field: Enter sends, Shift+Enter adds a line. While a turn runs
/// the send button becomes Stop. Shift+Tab calls [onCycleMode]. [toolbar] (the chips) sits under
/// the field, the send button on its right. Typing `@` suggests project files (arrows
/// choose, Enter or Tab inserts, Escape closes).
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

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<PromptComposer> {
  ({int start, String query})? _mention;
  List<String> _suggestions = const <String>[];
  int _highlighted = 0;

  /// Start of a mention closed with Escape: it stays closed while typed on.
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
    // The file list loads after the mention starts.
    if (oldWidget.mentionFiles != widget.mentionFiles && _mention != null) {
      _suggestions = searchFiles(widget.mentionFiles ?? const <String>[], _mention!.query);
      _highlighted = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final files = widget.mentionFiles;
    final value = widget.controller.value;
    final mention = files == null || !value.selection.isCollapsed
        ? null
        : mentionQueryAt(value.text, value.selection.baseOffset);
    if (mention == null || mention.start == _dismissedAt) {
      if (mention == null) _dismissedAt = null;
      if (_mention != null) setState(_close);
      return;
    }
    if (_mention?.start != mention.start) widget.onMentionStart?.call();
    setState(() {
      _mention = mention;
      _suggestions = searchFiles(files!, mention.query);
      _highlighted = 0;
    });
  }

  void _close() {
    _mention = null;
    _suggestions = const <String>[];
  }

  /// Replaces the typed mention with `@path `.
  void _insert(String path) {
    final mention = _mention;
    if (mention == null) return;
    final value = widget.controller.value;
    final end = value.selection.baseOffset;
    final inserted = '@$path ';
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(mention.start, end, inserted),
      selection: TextSelection.collapsed(offset: mention.start + inserted.length),
    );
    setState(_close);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        setState(() => _highlighted = (_highlighted + step) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _insert(_suggestions[_highlighted]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _dismissedAt = _mention?.start;
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
                if (_suggestions.isNotEmpty)
                  TextFieldTapRegion(
                    child: MentionSuggestions(
                      files: _suggestions,
                      highlighted: _highlighted,
                      onSelected: _insert,
                    ),
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
