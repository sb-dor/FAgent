import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

/// {@template skill_name_dialog}
/// Asks for the name of a new skill or rule and creates it.
///
/// A name the repository refuses (not allowed, or taken) is explained under the field and the
/// dialog stays open. The dialog closes when the item is created, or when the action fails for a
/// reason the name does not explain; the screen tells the user about that.
/// {@endtemplate}
class SkillNameDialog extends StatefulWidget {
  /// {@macro skill_name_dialog}
  const SkillNameDialog({required this.scope, required this.kind, super.key});

  /// The screen the item is created on. The dialog is on a route above the screen, so it cannot
  /// look the screen up.
  final SkillsConfigWidgetState scope;

  /// What is created.
  final KnowledgeKind kind;

  @override
  State<SkillNameDialog> createState() => _SkillNameDialogState();
}

class _SkillNameDialogState extends State<SkillNameDialog> {
  SkillsConfigWidgetState get _scope => widget.scope;
  final TextEditingController _name = TextEditingController();
  String? _error;

  bool get _busy => _scope.actions.state is SkillActions$ProcessingState;

  @override
  void initState() {
    super.initState();
    _scope.actions.addListener(_onAction);
  }

  @override
  void dispose() {
    _scope.actions.removeListener(_onAction);
    _name.dispose();
    super.dispose();
  }

  void _onAction() {
    switch (_scope.actions.state) {
      case SkillActions$CompletedState():
        Navigator.of(context).pop();
      case SkillActions$FailedState(:final error):
        if (error is InvalidKnowledgeNameException) {
          setState(() => _error = Localization.of(context).skillNameInvalid);
        } else if (error is KnowledgeExistsException) {
          setState(() => _error = Localization.of(context).skillNameTaken);
        } else {
          Navigator.of(context).pop();
        }
      case SkillActions$ProcessingState():
        setState(() {});
      case SkillActions$IdleState():
        break;
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    _scope.actions.create(widget.kind, name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final style = AppText.mono(context, size: 13);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      title: Text(localization.skillsAddCreate),
      content: SizedBox(
        width: 360,
        child: ListenableBuilder(
          listenable: _name,
          builder: (context, _) => TextField(
            controller: _name,
            autofocus: true,
            style: style,
            cursorColor: colors.accent,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: localization.skillName,
              helperText: localization.skillNameHint,
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 3,
              enabledBorder: border(colors.border),
              focusedBorder: border(colors.accent),
              errorBorder: border(colors.danger),
              focusedErrorBorder: border(colors.danger),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localization.cancel)),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _name.text.trim().isEmpty || _busy ? null : _submit,
            child: Text(localization.skillsAddCreate),
          ),
        ),
      ],
    );
  }
}
