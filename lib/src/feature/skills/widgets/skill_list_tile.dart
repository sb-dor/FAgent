import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/source_tag.dart';

/// {@template skill_list_tile}
/// A row of the skills list: the name in monospace, where the item comes from, its description
/// (two lines at most) and a switch that turns it on or off.
/// {@endtemplate}
class SkillListTile extends StatelessWidget {
  /// {@macro skill_list_tile}
  const SkillListTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    super.key,
  });

  /// The skill or rule.
  final KnowledgeItem item;

  /// Whether the row is the open item.
  final bool selected;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  /// Called with the new state of the switch.
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context).textTheme;
    return Material(
      color: selected ? colors.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selected ? colors.accent : Colors.transparent, width: 3),
              bottom: BorderSide(color: colors.border),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 10, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono(context).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SourceTag(source: item.source),
                        ],
                      ),
                      if (item.description.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall!.copyWith(color: colors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: item.title,
                  child: Switch(
                    value: item.enabled,
                    onChanged: onToggle,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
