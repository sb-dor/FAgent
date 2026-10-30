import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_text_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_error_message.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

/// {@template skill_editor}
/// The text of the `SKILL.md` (or the rule file) of [item] in a monospace field, with a Save button.
///
/// A built-in item can only be read. Save is on while the text differs from the one that was read
/// or saved last; the screen is told about such edits, so it can ask before they are lost. Give
/// the editor a key of the item's id: it belongs to one item.
/// {@endtemplate}
class SkillEditor extends StatefulWidget {
  /// {@macro skill_editor}
  const SkillEditor({required this.item, super.key});

  /// The skill or rule.
  final KnowledgeItem item;

  @override
  State<SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends State<SkillEditor> {
  late final SkillsConfigWidgetState _scope = SkillsConfigInhWidget.of(context);
  final TextEditingController _text = TextEditingController();

  /// The text last read from or saved to the file; `null` until the first read arrives.
  String? _loaded;

  /// The text being saved; `null` when no save runs.
  String? _saving;
  bool _requested = false;

  String get _id => widget.item.id;

  bool get _dirty => _loaded != null && _text.text != _loaded;

  bool get _canSave =>
      !widget.item.readOnly &&
      _dirty &&
      _saving == null &&
      _scope.actions.state is! SkillActions$ProcessingState;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onEdit);
    _scope.text.addListener(_onRead);
    _scope.actions.addListener(_onAction);
    // Reading changes the state of the controller, which is not allowed while the tree is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requested = true;
      _scope.text.load(_id, projectRoot: _scope.project?.path);
    });
  }

  @override
  void dispose() {
    _scope.hasUnsavedEdits = false;
    _scope.actions.removeListener(_onAction);
    _scope.text.removeListener(_onRead);
    _text.dispose();
    super.dispose();
  }

  void _onEdit() {
    _scope.hasUnsavedEdits = _dirty;
    setState(() {});
  }

  void _onRead() {
    if (!_requested || _loaded != null) return;
    switch (_scope.text.state) {
      case SkillText$LoadedState(:final id, :final text) when id == _id:
        _loaded = text;
        _text.value = TextEditingValue(text: text);
        setState(() {});
      case SkillText$FailedState(:final id) when id == _id:
        setState(() {});
      default:
        break;
    }
  }

  void _onAction() {
    final saving = _saving;
    if (saving == null) return;
    switch (_scope.actions.state) {
      case SkillActions$CompletedState():
        _loaded = saving;
        _saving = null;
        _scope.hasUnsavedEdits = _dirty;
        setState(() {});
      case SkillActions$FailedState():
        _saving = null;
        setState(() {});
      case SkillActions$IdleState() || SkillActions$ProcessingState():
        break;
    }
  }

  void _save() {
    if (!_canSave) return;
    _saving = _text.text;
    _scope.actions.save(_id, _text.text, projectRoot: _scope.project?.path);
  }

  Widget _status(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    if (_scope.text.state case SkillText$FailedState(:final id, :final error) when id == _id) {
      return Text(
        skillErrorMessage(localization, error),
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.danger),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final readOnly = widget.item.readOnly;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                localization.skillEditorLabel,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
              ),
            ),
            if (!readOnly)
              CompactButton(
                label: localization.skillSave,
                primary: true,
                onPressed: _canSave ? _save : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loaded == null)
          _status(context)
        else
          TextField(
            key: const ValueKey<String>('skill-editor'),
            controller: _text,
            readOnly: readOnly,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: AppText.mono(context),
            cursorColor: colors.accent,
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.surfaceAlt,
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: border(colors.border),
              focusedBorder: border(readOnly ? colors.border : colors.accent),
            ),
          ),
      ],
    );
  }
}
