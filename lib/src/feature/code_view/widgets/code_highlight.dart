import 'package:flutter/painting.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// The highlight rules of each language name [codeLanguageOf] returns.
final Map<String, Mode> _modes = <String, Mode>{
  'dart': langDart,
  'yaml': langYaml,
  'json': langJson,
  'swift': langSwift,
  'kotlin': langKotlin,
  'gradle': langGradle,
  'groovy': langGroovy,
  'xml': langXml,
  'markdown': langMarkdown,
  'objectivec': langObjectivec,
  'cpp': langCpp,
  'bash': langBash,
  'properties': langProperties,
  'ini': langIni,
  'css': langCss,
  'javascript': langJavascript,
  'typescript': langTypescript,
  'ruby': langRuby,
  'plaintext': langPlaintext,
};

/// Language names by lower-case extension.
const Map<String, String> _byExtension = <String, String>{
  'dart': 'dart',
  'yaml': 'yaml',
  'yml': 'yaml',
  'json': 'json',
  'arb': 'json',
  'swift': 'swift',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'gradle': 'gradle',
  'groovy': 'groovy',
  'xml': 'xml',
  'plist': 'xml',
  'html': 'xml',
  'md': 'markdown',
  'm': 'objectivec',
  'mm': 'objectivec',
  'h': 'objectivec',
  'c': 'cpp',
  'cc': 'cpp',
  'cpp': 'cpp',
  'hpp': 'cpp',
  'sh': 'bash',
  'zsh': 'bash',
  'bash': 'bash',
  'properties': 'properties',
  'ini': 'ini',
  'toml': 'ini',
  'css': 'css',
  'js': 'javascript',
  'ts': 'typescript',
  'rb': 'ruby',
};

/// Language names of files known by their name alone.
const Map<String, String> _byName = <String, String>{'Podfile': 'ruby', 'Gemfile': 'ruby'};

/// The highlight language of the file at [path]; `plaintext` for anything else.
String codeLanguageOf(String path) {
  final name = p.basename(path);
  return _byName[name] ??
      _byExtension[p.extension(name).replaceFirst('.', '').toLowerCase()] ??
      'plaintext';
}

/// The highlighting of the file at [path] in the colors of [colors].
CodeHighlightTheme codeHighlightTheme(AppColors colors, String path) {
  final language = codeLanguageOf(path);
  return CodeHighlightTheme(
    languages: <String, CodeHighlightThemeMode>{
      language: CodeHighlightThemeMode(mode: _modes[language]!),
    },
    theme: codeThemeStyles(colors),
  );
}

/// The highlight.js classes in the syntax colors of [colors].
Map<String, TextStyle> codeThemeStyles(AppColors colors) {
  TextStyle style(Color color) => TextStyle(color: color);
  final keyword = style(colors.syntaxKeyword);
  final type = style(colors.syntaxType);
  final function = style(colors.syntaxFunction);
  final number = style(colors.syntaxNumber);
  final comment = style(colors.syntaxComment);
  return <String, TextStyle>{
    'root': style(colors.text),
    'keyword': keyword,
    'built_in': keyword,
    'type': type,
    'class': type,
    'title.class_': type,
    'title.function_': function,
    'function': function,
    'string': style(colors.syntaxString),
    'number': number,
    'literal': number,
    'comment': comment,
    'doc': comment,
    'meta': style(colors.syntaxMeta),
  };
}
