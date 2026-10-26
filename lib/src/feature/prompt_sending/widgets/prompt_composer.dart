import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template prompt_composer}
/// The prompt field: Enter sends, Shift+Enter adds a line. While a turn runs
/// the send button becomes Stop.
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

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<PromptComposer> {
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.enter)
      return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (widget.canSend) widget.onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Focus(
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
                        contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: widget.canStop
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
