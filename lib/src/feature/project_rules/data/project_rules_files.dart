import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';

/// Opens the app's section in a project's `AGENTS.md`.
const String rulesSectionStart = '<!-- flutter_code_agent:rules -->';

/// Closes the app's section in a project's `AGENTS.md`.
const String rulesSectionEnd = '<!-- /flutter_code_agent:rules -->';

/// The folder of the rules, relative to the project.
const String projectRulesFolder = 'docs/rules';

/// The line that opens the app's section of `AGENTS.md`.
const String _rulesIntro =
    'Before changing code, read the rules in `$projectRulesFolder/` that apply to the task. They '
    "are this project's conventions:";

/// [existing] `AGENTS.md` (`null`: there is none) with the app's section listing [rules]: the
/// section between [rulesSectionStart] and [rulesSectionEnd] is replaced, or added after the text,
/// which stays as it was. The file's own line break (`\r\n` or `\n`) is kept.
String agentsMdWithRules(String? existing, List<ProjectRule> rules) {
  final lineBreak = existing != null && existing.contains('\r\n') ? '\r\n' : '\n';
  final section = <String>[
    rulesSectionStart,
    _rulesIntro,
    '',
    for (final rule in rules) '- `$projectRulesFolder/${rule.name}.md` — ${rule.description}',
    rulesSectionEnd,
    '',
  ].join(lineBreak);
  if (existing == null || existing.isEmpty) return section;
  final start = existing.indexOf(rulesSectionStart);
  final end = existing.indexOf(rulesSectionEnd);
  if (start >= 0 && end > start) {
    var after = end + rulesSectionEnd.length;
    if (existing.startsWith(lineBreak, after)) after += lineBreak.length;
    return existing.replaceRange(start, after, section);
  }
  // One empty line between the file's own text and the section.
  final text = existing.endsWith(lineBreak) ? existing : '$existing$lineBreak';
  return '$text$lineBreak$section';
}

final RegExp _agentsImport = RegExp(r'^\s*@(\./)?AGENTS\.md\s*$', multiLine: true);

/// [existing] `CLAUDE.md` (`null`: there is none) with a line `@AGENTS.md`, unless it already
/// imports `AGENTS.md`.
String claudeMdWithAgents(String? existing) {
  if (existing == null || existing.isEmpty) return '@AGENTS.md\n';
  if (_agentsImport.hasMatch(existing)) return existing;
  final lineBreak = existing.contains('\r\n') ? '\r\n' : '\n';
  final text = existing.endsWith(lineBreak) ? existing : '$existing$lineBreak';
  return '$text$lineBreak@AGENTS.md$lineBreak';
}

final RegExp _frontmatter = RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n(\r?\n)?');

/// [text] of a rule file without its frontmatter.
String ruleBody(String text) => text.replaceFirst(_frontmatter, '');
