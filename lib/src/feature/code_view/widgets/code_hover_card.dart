import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_diagnostic_spans.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Splits hover [markdown] into its first fenced `dart` block (the declaration) and the rest (the
/// dartdoc); the declaration is `null` without such a block.
({String? declaration, String docs}) splitHoverMarkdown(String markdown) {
  final match = RegExp(r'```(?:dart)?\n([\s\S]*?)\n```').firstMatch(markdown);
  if (match == null) return (declaration: null, docs: markdown.trim());
  final docs = (markdown.substring(0, match.start) + markdown.substring(match.end))
      .replaceFirst(RegExp(r'^\s*---\s*'), '')
      .trim();
  return (declaration: match.group(1)!.trim(), docs: docs);
}

/// {@template code_hover_card}
/// The hover card of the Code view: the errors and warnings under the pointer in their colors,
/// the name's declaration in code font and its dartdoc as markdown; at most [maxWidth] ×
/// [maxHeight], the rest scrolls. The pointer entering and leaving it reports to [onEnter] and
/// [onExit], so it stays while the pointer is inside.
/// {@endtemplate}
class CodeHoverCard extends StatelessWidget {
  /// {@macro code_hover_card}
  const CodeHoverCard({required this.info, required this.onEnter, required this.onExit, super.key});

  /// What the card shows.
  final CodeHoverInfo info;

  /// The pointer entered the card.
  final VoidCallback onEnter;

  /// The pointer left the card.
  final VoidCallback onExit;

  /// Widest card.
  static const double maxWidth = 480;

  /// Tallest card; longer docs scroll.
  static const double maxHeight = 300;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final small = textTheme.bodySmall?.copyWith(color: colors.text);
    final doc = info.doc == null ? null : splitHoverMarkdown(info.doc!.markdown);
    final border = info.diagnostics.isEmpty
        ? colors.border
        : diagnosticColor(colors, info.diagnostics.first.severity);
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AppRadius.small),
            boxShadow: <BoxShadow>[BoxShadow(color: colors.shadow, blurRadius: 6)],
          ),
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final diagnostic in info.diagnostics)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        diagnostic.code == null
                            ? diagnostic.message
                            : '${diagnostic.message} (${diagnostic.code})',
                        style: small?.copyWith(color: diagnosticColor(colors, diagnostic.severity)),
                      ),
                    ),
                  if (doc?.declaration case final declaration?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        declaration,
                        style: AppText.mono(context, size: 12).copyWith(color: colors.text),
                      ),
                    ),
                  if (doc != null && doc.docs.isNotEmpty)
                    MarkdownBody(
                      data: doc.docs,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: small,
                        code: AppText.mono(context, size: 12).copyWith(color: colors.text),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
