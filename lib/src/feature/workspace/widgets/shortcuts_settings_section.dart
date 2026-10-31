import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';

/// {@template shortcuts_settings_section}
/// The "Keyboard shortcuts" section of Settings: a read-only list of the app's shortcuts.
/// {@endtemplate}
class ShortcutsSettingsSection extends StatelessWidget {
  /// {@macro shortcuts_settings_section}
  const ShortcutsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final shortcuts = <(String label, String keys)>[
      (localization.shortcutNewChat, '⌘N'),
      (localization.shortcutSearchChats, '⌘K'),
      (localization.shortcutSidebar, r'⌘\'),
      (localization.shortcutRightPane, '⌘J'),
      (localization.shortcutSettings, '⌘,'),
      (localization.shortcutHotReload, '⌘R'),
      (localization.shortcutHotRestart, '⇧⌘R'),
      (localization.shortcutPermissionMode, '⇧Tab'),
      (localization.shortcutPermissionCard, '↵ / Esc'),
      (localization.shortcutClose, 'Esc'),
    ];
    return SettingsCard(
      children: <Widget>[
        for (final (label, keys) in shortcuts) _ShortcutRow(label: label, keys: keys),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text),
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(keys, style: AppText.mono(context)),
            ),
          ),
        ],
      ),
    );
  }
}
