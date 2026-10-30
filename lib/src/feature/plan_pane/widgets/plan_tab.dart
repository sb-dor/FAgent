import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// {@template plan_tab}
/// The Plan tab of the right pane: the agent's latest plan of the chat as a checklist with a
/// progress line.
///
/// Without a plan (or with an empty one) it explains that there is none yet.
/// {@endtemplate}
class PlanTab extends StatelessWidget {
  /// {@macro plan_tab}
  const PlanTab({required this.items, super.key});

  /// The feed of the open chat; the last [PlanItem] in it is shown.
  final List<ChatItem> items;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final entries = items.whereType<PlanItem>().lastOrNull?.entries ?? const <PlanEntry>[];
    if (entries.isEmpty) {
      return EmptyState(icon: Icons.checklist, title: localization.planEmpty);
    }
    final done = entries.where((entry) => entry.status == 'completed').length;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          localization.planProgress(done, entries.length),
          style: textTheme.labelLarge!.copyWith(color: colors.text),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: LinearProgressIndicator(
            value: done / entries.length,
            minHeight: 4,
            color: colors.ok,
            backgroundColor: colors.border,
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in entries) _PlanEntryRow(entry: entry),
      ],
    );
  }
}

class _PlanEntryRow extends StatelessWidget {
  const _PlanEntryRow({required this.entry});

  final PlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium!;
    final (leading, textStyle) = switch (entry.status) {
      'completed' => (
        Icon(Icons.check_circle, size: 18, color: colors.ok),
        style.copyWith(color: colors.muted),
      ),
      'in_progress' => (
        SizedBox.square(
          dimension: 18,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
          ),
        ),
        style.copyWith(color: colors.text, fontWeight: FontWeight.w600),
      ),
      _ => (
        Icon(Icons.radio_button_unchecked, size: 18, color: colors.muted),
        style.copyWith(color: colors.text),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          leading,
          const SizedBox(width: 8),
          Expanded(child: Text(entry.content, style: textStyle)),
        ],
      ),
    );
  }
}
