import 'package:freezed_annotation/freezed_annotation.dart';

part 'code_view_state.freezed.dart';

/// What the chat column of a project shows.
enum CodeViewMode {
  /// The selected chat.
  chat,

  /// The explorer and the editor.
  code,
}

/// {@template code_view_state}
/// The remembered Code view of one project.
/// {@endtemplate}
@freezed
abstract class CodeViewState with _$CodeViewState {
  /// {@macro code_view_state}
  const factory CodeViewState({
    @Default(CodeViewMode.chat) CodeViewMode mode,

    /// Open files relative to the project, in tab order.
    @Default(<String>[]) List<String> tabs,

    /// The active tab, relative to the project.
    String? activeTab,

    /// The explorer's width in logical pixels.
    @Default(240) double explorerWidth,
  }) = _CodeViewState;
}
