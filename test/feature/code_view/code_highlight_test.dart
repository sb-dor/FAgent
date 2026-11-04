import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the language map picks dart, yaml, Podfile ruby, unknown plaintext', () {
    expect(codeLanguageOf('/p/lib/main.dart'), 'dart');
    expect(codeLanguageOf('/p/pubspec.yaml'), 'yaml');
    expect(codeLanguageOf('/p/analysis_options.yml'), 'yaml');
    expect(codeLanguageOf('/p/lib/l10n/app_en.arb'), 'json');
    expect(codeLanguageOf('/p/ios/Podfile'), 'ruby');
    expect(codeLanguageOf('/p/android/app/build.gradle.kts'), 'kotlin');
    expect(codeLanguageOf('/p/macos/Runner/AppDelegate.SWIFT'), 'swift');
    expect(codeLanguageOf('/p/LICENSE'), 'plaintext');
    expect(codeLanguageOf('/p/notes.unknown'), 'plaintext');
  });

  test('every language has a highlight mode', () {
    for (final path in <String>['a.dart', 'a.yaml', 'Podfile', 'a.toml', 'a.html', 'x']) {
      final theme = codeHighlightTheme(AppColors.light, path);

      expect(theme.languages.keys, <String>[codeLanguageOf(path)]);
    }
  });

  test('the theme uses only syntax tokens in light and dark', () {
    for (final colors in <AppColors>[AppColors.light, AppColors.dark]) {
      final allowed = <Color>{
        colors.text,
        colors.syntaxKeyword,
        colors.syntaxType,
        colors.syntaxFunction,
        colors.syntaxString,
        colors.syntaxNumber,
        colors.syntaxComment,
        colors.syntaxMeta,
      };
      final styles = codeHighlightTheme(colors, 'a.dart').theme;

      expect(styles['root']?.color, colors.text);
      expect(styles['keyword']?.color, colors.syntaxKeyword);
      expect(styles['string']?.color, colors.syntaxString);
      expect(styles['comment']?.color, colors.syntaxComment);
      expect(styles.values.map((style) => style.color), everyElement(isIn(allowed)));
    }
  });
}
