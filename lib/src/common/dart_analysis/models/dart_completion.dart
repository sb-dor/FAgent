import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:meta/meta.dart';

export 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';

/// What a completion is, for its icon.
enum DartCompletionKind {
  /// A class, mixin, extension type or type parameter.
  classType,

  /// A method.
  method,

  /// A top-level function.
  function,

  /// A field or an enum value.
  field,

  /// A local variable, parameter or constant.
  variable,

  /// A keyword (`final`, `class`).
  keyword,

  /// A snippet (`stful`, `for`).
  snippet,

  /// An enum.
  enumType,

  /// A constructor.
  constructor,

  /// A getter or setter.
  property,

  /// A library or import prefix.
  module,

  /// Anything else.
  other;

  /// The kind of the LSP `CompletionItemKind` [value].
  static DartCompletionKind ofLsp(int? value) => switch (value) {
    2 => method,
    3 => function,
    4 => constructor,
    5 || 20 => field,
    6 || 21 => variable,
    7 || 8 || 22 || 25 => classType,
    9 => module,
    10 => property,
    13 => enumType,
    14 => keyword,
    15 => snippet,
    _ => other,
  };
}

/// {@template dart_completion}
/// One entry of the analysis server's completion list.
/// {@endtemplate}
@immutable
final class DartCompletion {
  /// {@macro dart_completion}
  const DartCompletion({
    required this.label,
    required this.kind,
    required this.insertText,
    this.detail,
    String? filterText,
    this.sortText,
    this.isSnippet = false,
    this.edit,
    this.additionalEdits = const <LspTextEdit>[],
    this.data,
  }) : filterText = filterText ?? label;

  /// Parses an LSP `CompletionItem`.
  factory DartCompletion.fromJson(Map<String, Object?> json) {
    final label = '${json['label'] ?? ''}';
    final textEdit = json['textEdit'];
    // An InsertReplaceEdit (`insert`/`replace`) is not asked for; take `insert` should one come.
    final edit = switch (textEdit) {
      {'range': final Object range} => LspTextEdit.fromJson(<String, Object?>{
        'range': range,
        'newText': textEdit['newText'],
      }),
      {'insert': final Object insert} => LspTextEdit(
        range: LspRange.fromJson(insert),
        newText: '${textEdit['newText'] ?? ''}',
      ),
      _ => null,
    };
    return DartCompletion(
      label: label,
      kind: DartCompletionKind.ofLsp((json['kind'] as num?)?.toInt()),
      detail: json['detail'] as String?,
      filterText: json['filterText'] as String?,
      sortText: json['sortText'] as String?,
      insertText: edit?.newText ?? json['insertText'] as String? ?? label,
      isSnippet: json['insertTextFormat'] == 2,
      edit: edit,
      additionalEdits: <LspTextEdit>[
        for (final entry in (json['additionalTextEdits'] as List<Object?>?) ?? const <Object?>[])
          LspTextEdit.fromJson(entry),
      ],
      data: json['data'],
    );
  }

  /// What the list shows.
  final String label;

  /// Its kind.
  final DartCompletionKind kind;

  /// The type or signature shown after the label.
  final String? detail;

  /// What typing is matched against.
  final String filterText;

  /// The server's order.
  final String? sortText;

  /// What is inserted: plain text, or a snippet body when [isSnippet].
  final String insertText;

  /// [insertText] has `$1` / `${1:name}` placeholders.
  final bool isSnippet;

  /// The exact range to replace; `null` replaces the word before the caret.
  final LspTextEdit? edit;

  /// More edits elsewhere, such as an `import`.
  final List<LspTextEdit> additionalEdits;

  /// What `completionItem/resolve` needs back.
  final Object? data;

  /// The item as LSP sends it back for `completionItem/resolve`.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'insertText': insertText,
    'insertTextFormat': isSnippet ? 2 : 1,
    'filterText': filterText,
    'sortText': ?sortText,
    'detail': ?detail,
    'data': ?data,
  };

  /// A copy with the [additionalEdits] (and [detail]) of a resolved item.
  DartCompletion withResolved(DartCompletion resolved) => DartCompletion(
    label: label,
    kind: kind,
    insertText: insertText,
    detail: resolved.detail ?? detail,
    filterText: filterText,
    sortText: sortText,
    isSnippet: isSnippet,
    edit: edit,
    additionalEdits: resolved.additionalEdits.isNotEmpty
        ? resolved.additionalEdits
        : additionalEdits,
    data: data,
  );

  @override
  String toString() => 'DartCompletion($label, ${kind.name})';
}
