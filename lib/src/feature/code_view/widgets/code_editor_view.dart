import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_find_panel.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_highlight.dart';
import 'package:re_editor/re_editor.dart';

/// {@template code_editor_view}
/// The editor on one text [document]: line numbers, folding, highlighting in the app's colors and
/// find (⌘F). [find] and [scroll] belong to the document's tab, so they outlive this widget when
/// another tab is shown.
/// {@endtemplate}
class CodeEditorView extends StatefulWidget {
  /// {@macro code_editor_view}
  const CodeEditorView({
    required this.document,
    required this.find,
    required this.scroll,
    required this.onSave,
    super.key,
  });

  /// The shown file.
  final CodeDocument document;

  /// Find state of the tab.
  final CodeFindController find;

  /// Scroll position of the tab.
  final CodeScrollController scroll;

  /// ⌘S inside the editor.
  final VoidCallback onSave;

  /// Font size of the code.
  static const double fontSize = 13;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  @override
  void initState() {
    super.initState();
    _revealCaret();
  }

  @override
  void didUpdateWidget(CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) _revealCaret();
  }

  /// A file opened at a line before the editor was laid out scrolls there once it is.
  void _revealCaret() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.document.editing.makeCursorCenterIfInvisible();
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = AppText.mono(
      context,
      size: CodeEditorView.fontSize,
    ).copyWith(color: colors.muted);
    return CodeEditor(
      controller: widget.document.editing,
      findController: widget.find,
      scrollController: widget.scroll,
      wordWrap: false,
      style: CodeEditorStyle(
        fontSize: CodeEditorView.fontSize,
        fontFamily: AppText.monoFamily,
        textColor: colors.text,
        hintTextColor: colors.muted,
        backgroundColor: colors.bg,
        selectionColor: colors.accentSoft,
        highlightColor: colors.warnSoft,
        cursorColor: colors.accent,
        cursorLineColor: colors.surfaceAlt,
        chunkIndicatorColor: colors.muted,
        codeTheme: codeHighlightTheme(colors, widget.document.path),
      ),
      indicatorBuilder: (context, editing, chunks, notifier) => Row(
        children: <Widget>[
          DefaultCodeLineNumber(
            controller: editing,
            notifier: notifier,
            textStyle: muted,
            focusedTextStyle: muted.copyWith(color: colors.text),
          ),
          DefaultCodeChunkIndicator(width: 18, controller: chunks, notifier: notifier),
        ],
      ),
      findBuilder: (context, find, readOnly) => CodeFindPanel(controller: find, readOnly: readOnly),
      shortcutOverrideActions: <Type, Action<Intent>>{
        CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
          onInvoke: (_) {
            widget.onSave();
            return null;
          },
        ),
      },
    );
  }
}
