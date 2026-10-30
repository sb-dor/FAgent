import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// How `claude-agent-acp` titles a call of its Skill tool (`SkillReporter`): `Load skill: <name>`.
const String _prefix = 'Load skill:';

/// The name of the skill [item] loads; `null` when [item] is any other tool call.
String? skillNameOf(ToolCallItem item) {
  final title = item.title;
  if (!title.startsWith(_prefix)) return null;
  final name = title.substring(_prefix.length).trim();
  return name.isEmpty ? null : name;
}
