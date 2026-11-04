import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/dart_completion_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_completion_list.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_diagnostic_spans.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_find_panel.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_highlight.dart';
import 'package:re_editor/re_editor.dart';

/// {@template code_editor_view}
/// The editor on one text [document]: line numbers, folding, highlighting in the app's colors and
/// find (⌘F); for a Dart file with an [analysis], completion at the caret. [find] and [scroll]
/// belong to the document's tab, so they outlive this widget when another tab is shown.
/// {@endtemplate}
class CodeEditorView extends StatefulWidget {
  /// {@macro code_editor_view}
  const CodeEditorView({
    required this.document,
    required this.find,
    required this.scroll,
    required this.onSave,
    this.analysis,
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

  /// The project's Dart analysis; completion needs it and a `.dart` file.
  final IDartAnalysisRepository? analysis;

  /// Font size of the code.
  static const double fontSize = 13;

  /// The editor's line height, as re_editor's default `fontHeight`.
  static const double lineHeight = 1.4;

  /// The editor's padding, as re_editor's default.
  static const double padding = 5;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

/// ⌃Space: open the completion list.
final class _CompleteIntent extends Intent {
  const _CompleteIntent();
}

/// Esc outside the editor's own handling: close the list or end the snippet.
final class _DismissIntent extends Intent {
  const _DismissIntent();
}

/// A [CallbackAction] that takes its key only while [enabled] says so; otherwise the editor
/// handles the key as always.
final class _WhenAction<T extends Intent> extends CallbackAction<T> {
  _WhenAction({required this.enabled, required super.onInvoke, this.consumes});

  final bool Function() enabled;
  final bool Function(T intent)? consumes;

  @override
  bool get isActionEnabled => enabled();

  @override
  bool isEnabled(T intent) => enabled() && (consumes?.call(intent) ?? true);

  @override
  bool consumesKey(T intent) => enabled() && (consumes?.call(intent) ?? true);
}

class _CodeEditorViewState extends State<CodeEditorView> {
  final GlobalKey _editorKey = GlobalKey();
  final GlobalKey _gutterKey = GlobalKey();
  final OverlayPortalController _overlay = OverlayPortalController();
  final OverlayPortalController _hoverOverlay = OverlayPortalController();
  DartCompletionController? _completion;

  /// The diagnostic under the pointer and where the pointer is (global).
  (DartDiagnostic, Offset)? _hover;

  @override
  void initState() {
    super.initState();
    _attach();
    _revealCaret();
  }

  @override
  void didUpdateWidget(CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        !identical(oldWidget.analysis, widget.analysis)) {
      _detach();
      _attach();
    }
    if (!identical(oldWidget.document, widget.document)) _revealCaret();
  }

  void _attach() {
    final analysis = widget.analysis;
    if (analysis == null || !widget.document.path.endsWith('.dart')) return;
    _completion = DartCompletionController(document: widget.document, analysis: analysis)
      ..addListener(_onCompletion);
    final document = widget.document;
    document.decorator =
        ({
          required context,
          required index,
          required codeLine,
          required textSpan,
          required style,
        }) => diagnosticSpans(
          textSpan: textSpan,
          line: index,
          diagnostics: document.diagnostics.value,
          colors: context.colors,
          onEnter: _showHover,
          onExit: _hideHover,
        );
    document.editing.forceRepaint();
  }

  void _showHover(DartDiagnostic diagnostic, Offset position) {
    if (!mounted) return;
    setState(() => _hover = (diagnostic, position));
    if (!_hoverOverlay.isShowing) _hoverOverlay.show();
  }

  void _hideHover() {
    if (!mounted || _hover == null) return;
    setState(() => _hover = null);
    if (_hoverOverlay.isShowing) _hoverOverlay.hide();
  }

  Widget _buildHover(BuildContext overlayContext) {
    final hover = _hover;
    final overlay = Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
    if (hover == null || overlay == null) return const SizedBox.shrink();
    final (diagnostic, position) = hover;
    final colors = overlayContext.colors;
    final at = overlay.globalToLocal(position);
    const width = 420.0;
    return Positioned(
      left: at.dx.clamp(0.0, (overlay.size.width - width).clamp(0.0, double.infinity)),
      top: at.dy + 18,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: diagnosticColor(colors, diagnostic.severity)),
              borderRadius: BorderRadius.circular(AppRadius.small),
              boxShadow: <BoxShadow>[BoxShadow(color: colors.shadow, blurRadius: 6)],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                diagnostic.code == null
                    ? diagnostic.message
                    : '${diagnostic.message} (${diagnostic.code})',
                style: Theme.of(overlayContext).textTheme.bodySmall?.copyWith(color: colors.text),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _detach() {
    _completion
      ?..removeListener(_onCompletion)
      ..dispose();
    _completion = null;
    if (_overlay.isShowing) _overlay.hide();
    if (_hoverOverlay.isShowing) _hoverOverlay.hide();
    _hover = null;
    widget.document.decorator = null;
  }

  void _onCompletion() {
    if (!mounted) return;
    final open = _completion?.open ?? false;
    if (open && !_overlay.isShowing) {
      _overlay.show();
    } else if (!open && _overlay.isShowing) {
      _overlay.hide();
    }
    setState(() {});
  }

  /// A file opened at a line before the editor was laid out scrolls there once it is.
  void _revealCaret() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.document.editing.makeCursorCenterIfInvisible();
  });

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  TextStyle get _codeStyle => const TextStyle(
    fontFamily: AppText.monoFamily,
    fontSize: CodeEditorView.fontSize,
    height: CodeEditorView.lineHeight,
  );

  /// Where the list goes in the overlay: under the caret, above it when there is no room below.
  Offset? _listPosition(BuildContext overlayContext, double listHeight) {
    final editor = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    final gutter = _gutterKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = overlayContext.findRenderObject() as RenderBox?;
    if (editor == null || overlay == null || !editor.attached) return null;
    final editing = widget.document.editing;
    final selection = editing.selection;
    final line = editing.codeLines[selection.extentIndex].text;
    final prefix = line.substring(0, selection.extentOffset.clamp(0, line.length));
    final prefixPainter = TextPainter(
      text: TextSpan(text: prefix, style: _codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final linePainter = TextPainter(
      text: TextSpan(text: 'M', style: _codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineHeight = linePainter.height;
    final find = widget.find.value;
    final findHeight = find == null ? 0.0 : (find.replaceMode ? 72.0 : 36.0) + 8;
    final vertical = widget.scroll.verticalScroller;
    final horizontal = widget.scroll.horizontalScroller;
    final x =
        (gutter?.size.width ?? 0) +
        CodeEditorView.padding +
        prefixPainter.width -
        (horizontal.hasClients ? horizontal.offset : 0);
    final y =
        CodeEditorView.padding +
        findHeight +
        selection.extentIndex * lineHeight -
        (vertical.hasClients ? vertical.offset : 0);
    final caretTop = overlay.globalToLocal(editor.localToGlobal(Offset(x, y)));
    final below = caretTop.dy + lineHeight;
    final top = below + listHeight > overlay.size.height ? caretTop.dy - listHeight : below;
    final left = caretTop.dx.clamp(0.0, overlay.size.width - CodeCompletionList.width);
    return Offset(left, top.clamp(0.0, overlay.size.height - listHeight));
  }

  Widget _buildList(BuildContext overlayContext) {
    final completion = _completion;
    if (completion == null || !completion.open) return const SizedBox.shrink();
    final height = CodeCompletionList.heightFor(completion.items.length);
    final position = _listPosition(overlayContext, height);
    if (position == null) return const SizedBox.shrink();
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: TapRegion(
        onTapOutside: (_) => completion.dismiss(),
        child: CodeCompletionList(
          items: completion.items,
          highlighted: completion.highlighted,
          onSelected: (item) => completion.select(item).ignore(),
        ),
      ),
    );
  }

  Map<Type, Action<Intent>> _completionActions(DartCompletionController completion) =>
      <Type, Action<Intent>>{
        CodeShortcutCursorMoveIntent: _WhenAction<CodeShortcutCursorMoveIntent>(
          enabled: () => completion.open,
          consumes: (intent) =>
              intent.direction == AxisDirection.up || intent.direction == AxisDirection.down,
          onInvoke: (intent) {
            completion.move(intent.direction == AxisDirection.up ? -1 : 1);
            return null;
          },
        ),
        CodeShortcutNewLineIntent: _WhenAction<CodeShortcutNewLineIntent>(
          enabled: () => completion.open,
          onInvoke: (_) {
            completion.accept().ignore();
            return null;
          },
        ),
        CodeShortcutIndentIntent: _WhenAction<CodeShortcutIndentIntent>(
          enabled: () => completion.open || completion.snippet != null,
          onInvoke: (_) {
            completion.open ? completion.accept().ignore() : completion.nextStop();
            return null;
          },
        ),
        CodeShortcutOutdentIntent: _WhenAction<CodeShortcutOutdentIntent>(
          enabled: () => completion.snippet != null,
          onInvoke: (_) {
            completion.previousStop();
            return null;
          },
        ),
        CodeShortcutEscIntent: _WhenAction<CodeShortcutEscIntent>(
          enabled: () => completion.open || completion.snippet != null,
          onInvoke: (_) {
            _dismiss(completion);
            return null;
          },
        ),
      };

  void _dismiss(DartCompletionController completion) {
    if (completion.open) {
      completion.dismiss();
    } else {
      completion.endSnippet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = AppText.mono(
      context,
      size: CodeEditorView.fontSize,
    ).copyWith(color: colors.muted);
    final completion = _completion;
    final editor = CodeEditor(
      controller: widget.document.editing,
      findController: widget.find,
      scrollController: widget.scroll,
      wordWrap: false,
      padding: const EdgeInsets.all(CodeEditorView.padding),
      style: CodeEditorStyle(
        fontSize: CodeEditorView.fontSize,
        fontFamily: AppText.monoFamily,
        fontHeight: CodeEditorView.lineHeight,
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
        key: _gutterKey,
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
    if (completion == null) return KeyedSubtree(key: _editorKey, child: editor);
    // The editor asks the nearest `Actions` above it before its own handling, so these take ↑↓,
    // Enter, Tab, ⇧Tab and Esc only while the list or a snippet is there.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space, control: true): _CompleteIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ..._completionActions(completion),
          _CompleteIntent: CallbackAction<_CompleteIntent>(
            onInvoke: (_) {
              completion.trigger();
              return null;
            },
          ),
          _DismissIntent: _WhenAction<_DismissIntent>(
            enabled: () => completion.open || completion.snippet != null,
            onInvoke: (_) {
              _dismiss(completion);
              return null;
            },
          ),
        },
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (overlayContext) => Positioned.fill(
            child: Builder(
              builder: (context) =>
                  Stack(children: <Widget>[_buildList(Overlay.of(overlayContext).context)]),
            ),
          ),
          child: OverlayPortal(
            controller: _hoverOverlay,
            overlayChildBuilder: (overlayContext) =>
                Positioned.fill(child: Stack(children: <Widget>[_buildHover(overlayContext)])),
            child: KeyedSubtree(key: _editorKey, child: editor),
          ),
        ),
      ),
    );
  }
}
