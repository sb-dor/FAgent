import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_roles.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/bypass_confirm_dialog.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/model_menu_footer.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/chat_skills_chip.dart';

/// {@template composer_toolbar}
/// The chips under the prompt: attach, agent, model (with effort in its menu), permission
/// mode and any other setting the agent offers, then the skills of the project. The mode is coloured when it acts without
/// asking; choosing `bypassPermissions` asks first.
/// {@endtemplate}
class ComposerToolbar extends StatelessWidget {
  /// {@macro composer_toolbar}
  const ComposerToolbar({
    required this.agentName,
    required this.agentLocked,
    required this.options,
    required this.enabled,
    required this.onChanged,
    required this.onAttach,
    required this.onMakeDefault,
    this.chatSkills = ChatSkills.empty,
    this.onOpenSkillLibrary,
    super.key,
  });

  /// Name of the chat's agent.
  final String agentName;

  /// The chat has a message already, so its agent can no longer be changed.
  final bool agentLocked;

  /// Settings to show; empty until the agent has started.
  final List<ConfigOption> options;

  /// Settings can be changed now.
  final bool enabled;

  /// Called with the option id and the new value.
  final void Function(String configId, Object value) onChanged;

  /// The attach button was pressed.
  final VoidCallback onAttach;

  /// "Make default for new chats" was ticked in the model menu.
  final VoidCallback onMakeDefault;

  /// The skills of the chat's project, for the 🧩 chip.
  final ChatSkills chatSkills;

  /// The skill library was asked for from the 🧩 chip; `null` hides the chip.
  final VoidCallback? onOpenSkillLibrary;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final mode = permissionModeOf(options);
    final model = modelOption(options);
    // Without a model chip the effort has no menu to live in and is a chip of its own.
    final effort = model == null ? null : effortOption(options);
    final taken = <ConfigOption?>{mode, model, effort};
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SelectorChip<String>(label: '＋', tooltip: localization.attach, onPressed: onAttach),
        _agentChip(localization),
        if (options.isEmpty) ...<Widget>[
          SelectorChip<String>(
            label: localization.modelLabel,
            icon: Icons.auto_awesome_outlined,
            tooltip: localization.availableAfterStart,
          ),
          SelectorChip<String>(
            label: localization.modeLabel,
            icon: Icons.shield_outlined,
            tooltip: localization.availableAfterStart,
          ),
        ] else ...<Widget>[
          if (model != null) _modelChip(localization, model, effort),
          if (mode != null) _modeChip(context, mode),
          for (final option in options)
            if (!taken.contains(option)) _otherChip(option),
        ],
        if (onOpenSkillLibrary != null)
          ChatSkillsChip(skills: chatSkills, onOpenLibrary: onOpenSkillLibrary!),
      ],
    );
  }

  Widget _agentChip(GeneratedLocalization localization) => SelectorChip<String>(
    label: agentName,
    icon: Icons.smart_toy_outlined,
    tooltip: localization.agentLabel,
    sections: <AppMenuSection<String>>[
      AppMenuSection<String>(
        title: localization.agentLabel,
        items: <AppMenuItem<String>>[
          AppMenuItem<String>(
            value: agentName,
            title: agentName,
            icon: Icons.smart_toy_outlined,
            selected: true,
            enabled: !agentLocked,
          ),
          for (final other in const <String>['Codex', 'Gemini CLI'])
            AppMenuItem<String>(
              value: other,
              title: other,
              subtitle: localization.comingInMilestone('M5'),
              enabled: false,
            ),
        ],
      ),
    ],
  );

  Widget _modelChip(
    GeneratedLocalization localization,
    SelectConfigOption model,
    SelectConfigOption? effort,
  ) => SelectorChip<String>(
    label: model.currentName,
    icon: Icons.auto_awesome_outlined,
    tooltip: model.description ?? model.name,
    sections: !enabled
        ? null
        : <AppMenuSection<String>>[
            AppMenuSection<String>(
              title: localization.modelLabel,
              items: <AppMenuItem<String>>[
                for (final choice in model.choices)
                  AppMenuItem<String>(
                    value: choice.value,
                    title: choice.name,
                    subtitle: choice.description,
                    selected: choice.value == model.currentValue,
                  ),
              ],
            ),
          ],
    menuWidth: 360,
    searchable: true,
    footerBuilder: (context, close) => ModelMenuFooter(
      effort: effort,
      onEffort: (value) {
        if (value != effort!.currentValue) onChanged(effort.id, value);
        close(null);
      },
      onMakeDefault: () {
        onMakeDefault();
        close(null);
      },
    ),
    onSelected: (value) => _change(model, value),
  );

  Widget _modeChip(BuildContext context, SelectConfigOption mode) => SelectorChip<String>(
    label: mode.currentName,
    icon: Icons.shield_outlined,
    tone: _tone(mode.currentValue),
    tooltip: mode.description ?? mode.name,
    sections: !enabled
        ? null
        : <AppMenuSection<String>>[
            AppMenuSection<String>(
              items: <AppMenuItem<String>>[
                for (final choice in mode.choices)
                  AppMenuItem<String>(
                    value: choice.value,
                    title: choice.name,
                    subtitle: choice.description,
                    icon: _modeIcon(choice.value),
                    tone: _tone(choice.value),
                    selected: choice.value == mode.currentValue,
                  ),
              ],
            ),
          ],
    onSelected: (value) => _selectMode(context, mode, value),
  );

  Widget _otherChip(ConfigOption option) => switch (option) {
    final SelectConfigOption select => SelectorChip<String>(
      label: '${select.name}: ${select.currentName}',
      icon: Icons.tune,
      tooltip: select.description,
      sections: !enabled || select.choices.isEmpty
          ? null
          : <AppMenuSection<String>>[
              AppMenuSection<String>(
                items: <AppMenuItem<String>>[
                  for (final choice in select.choices)
                    AppMenuItem<String>(
                      value: choice.value,
                      title: choice.name,
                      subtitle: choice.description,
                      selected: choice.value == select.currentValue,
                    ),
                ],
              ),
            ],
      onSelected: (value) => _change(select, value),
    ),
    final BooleanConfigOption boolean => SelectorChip<String>(
      label: boolean.name,
      icon: boolean.currentValue ? Icons.check : null,
      tooltip: boolean.description,
      onPressed: enabled ? () => onChanged(boolean.id, !boolean.currentValue) : null,
    ),
    UnknownConfigOption(:final name, :final description) => SelectorChip<String>(
      label: name,
      tooltip: description,
    ),
  };

  void _change(SelectConfigOption option, String value) {
    if (value != option.currentValue) onChanged(option.id, value);
  }

  Future<void> _selectMode(BuildContext context, SelectConfigOption mode, String value) async {
    if (value == mode.currentValue) return;
    if (value == bypassPermissionMode && !await confirmBypass(context)) return;
    onChanged(mode.id, value);
  }

  AppTone _tone(String mode) => switch (mode) {
    bypassPermissionMode => AppTone.danger,
    _ when unattendedPermissionModes.contains(mode) => AppTone.warn,
    _ => AppTone.neutral,
  };

  IconData _modeIcon(String mode) => switch (mode) {
    'acceptEdits' => Icons.edit_outlined,
    'plan' => Icons.checklist_outlined,
    'auto' => Icons.autorenew,
    bypassPermissionMode => Icons.warning_amber_outlined,
    _ => Icons.shield_outlined,
  };
}
