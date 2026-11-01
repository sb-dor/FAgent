import 'dart:convert';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';

/// The most bytes (UTF-8) of a user rule, a project rule or `AGENTS.md` that go into the prompt.
const int ruleFileLimit = 32 * 1024;

/// The text of an enabled rule file, with its frontmatter still in place.
typedef RuleText = ({SkillSource source, String name, String text});

/// The name and the description of a skill the agent can load.
typedef SkillSummary = ({String name, String description});

const String _firstLine = 'Later rules override earlier ones.';
const String _truncated = '[truncated]';
const String _agentsHeading = 'AGENTS.md';
const String _skillsHeading = 'Skills from flutter_code_agent';

/// Builds the rules text that is appended to the system prompt of an agent session.
///
/// The text starts with a line that says later rules win. Then come the [rules], built-in first,
/// then the user's and the project's (the order of [SkillSource], and the order of [rules] within
/// one source), then the project's [agentsMd] and a list of the [skills]. A rule becomes a
/// `## <name>` section without its frontmatter.
///
/// Built-in rules go in whole; any other rule and [agentsMd] are cut at [ruleFileLimit] bytes, and
/// the cut is marked with a line `[truncated]`. [agentsMd] is left out when it is blank or when
/// [claudeMd] has a line `@AGENTS.md` (it imports the file itself, so the agent would read it
/// twice). The skills section is left out when [skills] is empty.
String buildRulesPrompt({
  required List<RuleText> rules,
  required List<SkillSummary> skills,
  String? agentsMd,
  String? claudeMd,
}) {
  final sections = <String>[_firstLine];
  // `List.sort` is not stable, so the sources are walked one by one.
  for (final source in SkillSource.values) {
    for (final rule in rules.where((rule) => rule.source == source)) {
      sections.add(_section(rule.name, _body(rule.text), limited: source != SkillSource.builtin));
    }
  }
  if (agentsMd != null && agentsMd.trim().isNotEmpty && !_importsAgents(claudeMd)) {
    sections.add(_section(_agentsHeading, agentsMd.trim(), limited: true));
  }
  if (skills.isNotEmpty) {
    sections.add(
      [
        '## $_skillsHeading',
        for (final skill in skills)
          '- ${skill.name} — ${skill.description.trim().replaceAll(RegExp(r'\s+'), ' ')}',
      ].join('\n'),
    );
  }
  return '${sections.join('\n\n')}\n';
}

String _section(String heading, String body, {required bool limited}) =>
    '## $heading\n${limited ? _limit(body) : body}';

/// [text] without its frontmatter; a text with no or a broken header is kept as it is.
String _body(String text) {
  try {
    return (parseFrontmatter(text)?.body ?? text).trim();
  } on FrontmatterException {
    return text.trim();
  }
}

bool _importsAgents(String? claudeMd) =>
    claudeMd != null &&
    const LineSplitter().convert(claudeMd).any((line) => line.trim() == '@AGENTS.md');

/// [text] cut at [ruleFileLimit] bytes (on a character boundary), then the `[truncated]` line.
String _limit(String text) {
  final bytes = utf8.encode(text);
  if (bytes.length <= ruleFileLimit) return text;
  var end = ruleFileLimit;
  // A byte `10xxxxxx` continues a character, so step back to the start of the one that is cut.
  while (end > 0 && bytes[end] & 0xC0 == 0x80) {
    end--;
  }
  return '${utf8.decode(bytes.sublist(0, end))}\n$_truncated';
}
