import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';
import 'package:flutter_code_agent/_core/design/markdown_style.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The color of the first span that holds [text].
Color? _colorOf(WidgetTester tester, String text) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    Color? found;
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.contains(text) ?? false)) {
        found = span.style?.color;
        return false;
      }
      return true;
    });
    if (found != null) return found;
  }
  return null;
}

void main() {
  for (final (name, theme, colors) in <(String, ThemeData, AppColors)>[
    ('light', AppTheme.light(), AppColors.light),
    ('dark', AppTheme.dark(), AppColors.dark),
  ]) {
    testWidgets('in the $name theme Markdown text takes the app colors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => MarkdownBody(
                data: 'plain [link](https://dart.dev)',
                styleSheet: appMarkdownStyle(context),
              ),
            ),
          ),
        ),
      );
      expect(_colorOf(tester, 'plain'), colors.text);
      expect(_colorOf(tester, 'link'), colors.accent);
    });
  }
}
