import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';

/// {@template session_config_bar}
/// The agent's settings as compact menus above the composer. The permission
/// mode is coloured when it acts without asking; choosing
/// `bypassPermissions` asks first.
/// {@endtemplate}
class SessionConfigBar extends StatelessWidget {
  /// {@macro session_config_bar}
  const SessionConfigBar({
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  /// Settings to show.
  final List<ConfigOption> options;

  /// Changes are possible now.
  final bool enabled;

  /// Called with the option id and the new value.
  final void Function(String configId, Object value) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final option in options)
                switch (option) {
                  final SelectConfigOption select => _SelectChip(
                    option: select,
                    enabled: enabled,
                    onSelected: (value) => _select(context, select, value),
                  ),
                  final BooleanConfigOption boolean => FilterChip(
                    label: Text(boolean.name),
                    tooltip: boolean.description,
                    selected: boolean.currentValue,
                    onSelected: enabled ? (value) => onChanged(boolean.id, value) : null,
                  ),
                  UnknownConfigOption(:final name) => Chip(label: Text(name)),
                },
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _select(BuildContext context, SelectConfigOption option, String value) async {
    if (value == option.currentValue) return;
    if (option.isMode && value == bypassPermissionMode) {
      final localization = Localization.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localization.bypassTitle),
          content: Text(localization.bypassBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(localization.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(localization.bypassAllow),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    onChanged(option.id, value);
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({required this.option, required this.enabled, required this.onSelected});

  final SelectConfigOption option;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warning = option.isMode && unattendedPermissionModes.contains(option.currentValue);
    final danger = option.isMode && option.currentValue == bypassPermissionMode;
    return PopupMenuButton<String>(
      enabled: enabled && option.choices.isNotEmpty,
      tooltip: option.description ?? option.name,
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final choice in option.choices)
          CheckedPopupMenuItem<String>(
            value: choice.value,
            checked: choice.value == option.currentValue,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(choice.name),
              subtitle: choice.description == null ? null : Text(choice.description!),
            ),
          ),
      ],
      child: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: danger
            ? colors.errorContainer
            : warning
            ? colors.tertiaryContainer
            : null,
        avatar: Icon(option.isMode ? Icons.shield_outlined : Icons.tune, size: 16),
        label: Text('${option.name}: ${option.currentName}'),
      ),
    );
  }
}
