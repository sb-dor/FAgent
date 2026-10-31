import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/diff_lines_cache.dart';
import 'package:flutter_code_agent/src/feature/chat/models/skill_call.dart';
import 'package:flutter_code_agent/src/feature/chat/models/tool_row_label.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/expandable_row.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_path_text.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:path/path.dart' as p;

/// {@template tool_call_card}
/// A tool call as one compact row: icon, the agent's wording, the first touched file (name and
/// folder, relative to [projectRoot]), the `+N −M` counter for edits and the status. Expands to
/// diffs and output; edits start expanded, everything else collapsed.
///
/// The load of a skill is a line of its own ([skillNameOf]) that opens the skill from [skills].
/// {@endtemplate}
class ToolCallCard extends StatefulWidget {
  /// {@macro tool_call_card}
  const ToolCallCard({
    required this.call,
    this.projectRoot,
    this.onOpenChange,
    this.skills = ChatSkills.empty,
    this.onOpenSkill,
    super.key,
  });

  /// The tool call.
  final ToolCallItem call;

  /// The chat's project folder; paths inside it are shown relative to it.
  final String? projectRoot;

  /// Called with the absolute, normalized path of the first diff (a relative one is taken inside
  /// [projectRoot]) when the user clicks the row of an edit; with it the body
  /// opens with a separate chevron. `null`, or a call without diffs, keeps the whole header as the
  /// expander.
  final ValueChanged<String>? onOpenChange;

  /// The skills of the chat's project: the line of a loaded skill is clickable when it is among
  /// them.
  final ChatSkills skills;

  /// Called with the id of the skill when the user clicks the line of a loaded skill; `null` leaves
  /// the line plain.
  final ValueChanged<String>? onOpenSkill;

  /// Icon for an ACP tool [kind].
  static IconData toolIcon(String? kind) => switch (kind) {
    'read' => Icons.description_outlined,
    'edit' => Icons.edit_note,
    'delete' => Icons.delete_outline,
    'move' => Icons.drive_file_move_outline,
    'search' => Icons.search,
    'execute' => Icons.terminal,
    'think' => Icons.psychology_outlined,
    'fetch' => Icons.public,
    _ => Icons.build_outlined,
  };

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  static const int _maxOutputChars = 4000;

  final DiffLinesCache _diffLines = DiffLinesCache();

  /// [path] as the Changes tab knows the file: inside the project folder (the agent may report a
  /// path relative to it), normalized.
  String _absolutePath(String path) => p.normalize(p.join(widget.projectRoot ?? '', path));

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final skillName = skillNameOf(call);
    if (skillName != null) {
      final skill = widget.skills.byName(skillName);
      final onOpenSkill = widget.onOpenSkill;
      return _SkillLine(
        name: skillName,
        status: call.status,
        onTap: skill == null || onOpenSkill == null ? null : () => onOpenSkill(skill.id),
      );
    }
    final theme = Theme.of(context);
    final colors = context.colors;
    final diffs = call.diffs.toList();
    final lines = _diffLines.resolve(diffs);
    final texts = call.content.whereType<ToolTextContent>().toList();
    final output = call.rawOutput;
    final hasBody = diffs.isNotEmpty || texts.isNotEmpty || (output != null && output.isNotEmpty);
    final path = call.locations.isEmpty ? null : call.locations.first;
    final label = toolRowLabel(title: call.title, path: path, projectRoot: widget.projectRoot);
    final onOpenChange = widget.onOpenChange;
    return ExpandableRow(
      initiallyExpanded: diffs.isNotEmpty,
      onHeaderTap: onOpenChange == null || diffs.isEmpty
          ? null
          : () => onOpenChange(_absolutePath(diffs.first.path)),
      headerTooltip: Localization.of(context).openInChanges,
      header: Row(
        children: <Widget>[
          Icon(ToolCallCard.toolIcon(call.kind), size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: ToolPathText(
              label: label.title == null && label.name == null
                  ? ToolRowLabel(title: call.kind ?? 'tool')
                  : label,
            ),
          ),
          if (diffs.isNotEmpty) ...<Widget>[_DiffCounter(lines: lines), const SizedBox(width: 8)],
          _StatusIcon(status: call.status),
        ],
      ),
      body: !hasBody
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < diffs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DiffView(
                      path: diffs[i].path,
                      oldText: diffs[i].oldText,
                      newText: diffs[i].newText,
                      lines: lines[i],
                    ),
                  ),
                for (final text in texts)
                  SelectableText(text.text, style: theme.textTheme.bodySmall),
                if (output != null && output.isNotEmpty) ...<Widget>[
                  Text(Localization.of(context).toolOutput, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SelectableText(
                    output.length > _maxOutputChars
                        ? '${output.substring(0, _maxOutputChars)}…'
                        : output,
                    style: AppText.mono(context),
                  ),
                ],
              ],
            ),
    );
  }
}

/// `+N −M` summed over all diffs of a call.
class _DiffCounter extends StatelessWidget {
  const _DiffCounter({required this.lines});

  final List<List<DiffLine>> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    var added = 0;
    var removed = 0;
    for (final diffLines in lines) {
      final stats = LineDiff.stats(diffLines);
      added += stats.added;
      removed += stats.removed;
    }
    final mono = AppText.mono(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '+$added',
            style: TextStyle(color: colors.ok),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '−$removed',
            style: TextStyle(color: colors.danger),
          ),
        ],
      ),
      style: mono,
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (status) {
      'completed' => Icon(Icons.check_circle_outline, size: 16, color: colors.ok),
      'failed' => Icon(Icons.error_outline, size: 16, color: colors.danger),
      _ => const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }
}

/// The line of a loaded skill: 🧩, "Skill" and its name.
class _SkillLine extends StatelessWidget {
  const _SkillLine({required this.name, required this.status, required this.onTap});

  final String name;
  final String status;

  /// Opens the skill; `null` when it cannot be found.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted);
    Widget line = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.extension_outlined, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Text(localization.skillUsed, style: style),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(fontWeight: FontWeight.w600, color: colors.text),
            ),
          ),
          // A finished call needs no mark; one that runs or failed does.
          if (status != 'completed') ...<Widget>[
            const SizedBox(width: 8),
            _StatusIcon(status: status),
          ],
        ],
      ),
    );
    if (onTap != null) {
      line = Tooltip(
        message: localization.skillUsedTooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: line,
        ),
      );
    }
    return Align(alignment: Alignment.centerLeft, child: line);
  }
}
