import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// {@template plan_card}
/// The agent's plan as a checklist.
/// {@endtemplate}
class PlanCard extends StatelessWidget {
  /// {@macro plan_card}
  const PlanCard({required this.entries, super.key});

  /// Plan steps.
  final List<PlanEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(Localization.of(context).plan, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(switch (entry.status) {
                      'completed' => Icons.check_box_outlined,
                      'in_progress' => Icons.indeterminate_check_box_outlined,
                      _ => Icons.check_box_outline_blank,
                    }, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.content,
                        style: entry.status == 'completed'
                            ? theme.textTheme.bodyMedium?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
