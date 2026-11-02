import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'custom_agent_draft.freezed.dart';

/// A custom ACP agent to add or save: what the user typed.
@freezed
abstract class CustomAgentDraft with _$CustomAgentDraft {
  /// Creates a draft.
  const factory CustomAgentDraft({
    required String name,
    required String executable,
    @Default(<String>[]) List<String> arguments,
    @Default(<String, String>{}) Map<String, String> environment,
    @Default(RulesChannel.firstMessage) RulesChannel rulesChannel,
  }) = _CustomAgentDraft;
}
