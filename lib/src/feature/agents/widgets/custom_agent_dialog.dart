import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';

/// {@template custom_agent_dialog}
/// Asks for a custom ACP agent: its name, the command and its arguments (one per line, no shell),
/// `KEY=value` lines for its environment, and where the app's rules go.
///
/// The name and the command are required; a line that is not `KEY=value` is explained under the
/// field and the dialog stays open. It returns the draft, or `null` when the user cancels.
/// {@endtemplate}
class CustomAgentDialog extends StatefulWidget {
  /// {@macro custom_agent_dialog}
  const CustomAgentDialog({this.initial, super.key});

  /// The stored agent when it is edited; `null` adds a new one.
  final CustomAgentDraft? initial;

  /// Shows the dialog over [context]; the draft the user saved, or `null`.
  static Future<CustomAgentDraft?> show(BuildContext context, {CustomAgentDraft? initial}) =>
      showDialog<CustomAgentDraft>(
        context: context,
        builder: (context) => CustomAgentDialog(initial: initial),
      );

  @override
  State<CustomAgentDialog> createState() => _CustomAgentDialogState();
}

class _CustomAgentDialogState extends State<CustomAgentDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name);
  late final TextEditingController _command = TextEditingController(
    text: widget.initial?.executable,
  );
  late final TextEditingController _arguments = TextEditingController(
    text: widget.initial?.arguments.join('\n'),
  );
  late final TextEditingController _environment = TextEditingController(
    text: widget.initial?.environment.entries.map((e) => '${e.key}=${e.value}').join('\n'),
  );
  late RulesChannel _rules = widget.initial?.rulesChannel ?? RulesChannel.firstMessage;
  bool _badEnvironment = false;

  bool get _complete => _name.text.trim().isNotEmpty && _command.text.trim().isNotEmpty;

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _command, _arguments, _environment]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_complete) return;
    final environment = _parseEnvironment(_environment.text);
    if (environment == null) {
      setState(() => _badEnvironment = true);
      return;
    }
    Navigator.of(context).pop(
      CustomAgentDraft(
        name: _name.text.trim(),
        executable: _command.text.trim(),
        arguments: <String>[
          for (final line in _arguments.text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
        environment: environment,
        rulesChannel: _rules,
      ),
    );
  }

  /// `KEY=value` lines; blank lines are skipped. `null` when a line has no key.
  static Map<String, String>? _parseEnvironment(String text) {
    final variables = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final at = trimmed.indexOf('=');
      final key = at < 0 ? '' : trimmed.substring(0, at).trim();
      if (key.isEmpty) return null;
      variables[key] = trimmed.substring(at + 1).trim();
    }
    return variables;
  }

  Widget _field({
    required String id,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? error,
    bool multiline = false,
    bool autofocus = false,
    VoidCallback? onChanged,
  }) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: ValueKey<String>('custom-agent-$id'),
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 4 : 1,
      style: id == 'name'
          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text)
          : AppText.mono(context, size: 13).copyWith(color: colors.text),
      cursorColor: colors.accent,
      onChanged: (_) => setState(() => onChanged?.call()),
      onSubmitted: multiline ? null : (_) => _submit(),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 2,
        errorText: error,
        errorMaxLines: 3,
        enabledBorder: border(colors.border),
        focusedBorder: border(colors.accent),
        errorBorder: border(colors.danger),
        focusedErrorBorder: border(colors.danger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    const gap = SizedBox(height: 16);
    final editing = widget.initial != null;
    final channels = <RulesChannel, String>{
      RulesChannel.firstMessage: localization.agentRulesFirstMessage,
      RulesChannel.systemPrompt: localization.agentRulesSystemPrompt,
      RulesChannel.claudeMeta: localization.agentRulesClaudeMeta,
    };
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      title: Text(editing ? localization.agentCustomEditTitle : localization.agentCustomAddTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          // Room for the floating labels above the first field.
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _field(
                id: 'name',
                controller: _name,
                label: localization.agentFieldName,
                autofocus: true,
              ),
              gap,
              _field(
                id: 'command',
                controller: _command,
                label: localization.agentFieldCommand,
                hint: localization.agentFieldCommandHint,
              ),
              gap,
              _field(
                id: 'arguments',
                controller: _arguments,
                label: localization.agentFieldArguments,
                hint: localization.agentFieldArgumentsHint,
                multiline: true,
              ),
              gap,
              _field(
                id: 'environment',
                controller: _environment,
                label: localization.agentFieldEnvironment,
                hint: localization.agentFieldEnvironmentHint,
                error: _badEnvironment ? localization.agentErrorEnvironmentLine : null,
                multiline: true,
                onChanged: () => _badEnvironment = false,
              ),
              gap,
              Text(
                localization.agentFieldRules,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectorChip<RulesChannel>(
                  key: const ValueKey<String>('custom-agent-rules'),
                  label: channels[_rules]!,
                  menuWidth: 240,
                  sections: <AppMenuSection<RulesChannel>>[
                    AppMenuSection<RulesChannel>(
                      items: <AppMenuItem<RulesChannel>>[
                        for (final MapEntry(:key, :value) in channels.entries)
                          AppMenuItem<RulesChannel>(
                            value: key,
                            title: value,
                            selected: key == _rules,
                          ),
                      ],
                    ),
                  ],
                  onSelected: (channel) => setState(() => _rules = channel),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localization.cancel)),
        FilledButton(
          onPressed: _complete ? _submit : null,
          child: Text(editing ? localization.save : localization.agentCustomAdd),
        ),
      ],
    );
  }
}
