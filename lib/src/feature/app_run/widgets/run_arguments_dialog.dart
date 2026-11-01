import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// {@template run_arguments_dialog}
/// Edits what a project adds to every `flutter run`: the flavor, the `--dart-define`s (one per
/// line) and the user's own flags (in a monospace field).
///
/// What is wrong with the input ([RunArguments.problem]) is explained under the field it is about
/// and keeps "Save" off. The dialog closes when the arguments are saved, on Esc and on "Cancel";
/// a failed save leaves it open with a message.
/// {@endtemplate}
class RunArgumentsDialog extends StatefulWidget {
  /// {@macro run_arguments_dialog}
  const RunArgumentsDialog({
    required this.projectId,
    required this.arguments,
    required this.controller,
    super.key,
  });

  /// Shows the dialog for [projectId], starting from its current [arguments].
  ///
  /// The dialog is on a route above the window, so it gets the [controller] handed over.
  static Future<void> show(
    BuildContext context, {
    required int projectId,
    required RunArguments arguments,
    required RunConfigController controller,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        RunArgumentsDialog(projectId: projectId, arguments: arguments, controller: controller),
  );

  /// The project whose arguments are edited.
  final int projectId;

  /// The arguments the fields start with.
  final RunArguments arguments;

  /// Saves the arguments.
  final RunConfigController controller;

  @override
  State<RunArgumentsDialog> createState() => _RunArgumentsDialogState();
}

class _RunArgumentsDialogState extends State<RunArgumentsDialog> {
  late final TextEditingController _flavor = TextEditingController(
    text: widget.arguments.flavor ?? '',
  );
  late final TextEditingController _defines = TextEditingController(
    text: widget.arguments.dartDefines.join('\n'),
  );
  late final TextEditingController _extra = TextEditingController(text: widget.arguments.extraArgs);

  /// Whether this dialog has asked for a save; the controller is shared with the window.
  bool _submitted = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSaved);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSaved);
    _flavor.dispose();
    _defines.dispose();
    _extra.dispose();
    super.dispose();
  }

  /// What the fields say now: a blank flavor is none, blank define lines are dropped.
  RunArguments get _current {
    final flavor = _flavor.text.trim();
    return RunArguments(
      flavor: flavor.isEmpty ? null : flavor,
      dartDefines: _defines.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      extraArgs: _extra.text.trim(),
    );
  }

  void _onSaved() {
    if (!_submitted) return;
    switch (widget.controller.state) {
      case RunConfig$CompletedState():
        Navigator.of(context).pop();
      case RunConfig$ErrorState():
        setState(() {
          _submitted = false;
          _saveFailed = true;
        });
      case RunConfig$InitialState() || RunConfig$InProgressState():
        break;
    }
  }

  void _save() {
    final arguments = _current;
    if (_submitted || arguments.problem != null) return;
    setState(() {
      _submitted = true;
      _saveFailed = false;
    });
    widget.controller.save(widget.projectId, arguments);
  }

  Widget _field({
    required String id,
    required TextEditingController controller,
    required String label,
    required String hint,
    String? error,
    bool multiline = false,
    bool autofocus = false,
  }) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: ValueKey<String>('run-arguments-$id'),
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 6 : 1,
      style: AppText.mono(context, size: 13).copyWith(color: colors.text),
      cursorColor: colors.accent,
      onChanged: (_) => setState(() => _saveFailed = false),
      onSubmitted: multiline ? null : (_) => _save(),
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
    final problem = _current.problem;
    const gap = SizedBox(height: 16);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      title: Text(localization.runArgumentsTitle),
      content: SizedBox(
        key: const ValueKey<String>('run-arguments-content'),
        width: 480,
        child: SingleChildScrollView(
          // Room for the floating labels above the first field.
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                localization.runArgumentsIntro,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
              gap,
              _field(
                id: 'flavor',
                controller: _flavor,
                label: localization.runArgumentsFlavor,
                hint: localization.runArgumentsFlavorHint,
                autofocus: true,
              ),
              gap,
              _field(
                id: 'defines',
                controller: _defines,
                label: localization.runArgumentsDefinesField,
                hint: localization.runArgumentsDefinesHint,
                error: problem == RunArgumentsProblem.badDefine
                    ? localization.runArgumentsBadDefine
                    : null,
                multiline: true,
              ),
              gap,
              _field(
                id: 'extra',
                controller: _extra,
                label: localization.runArgumentsExtra,
                hint: localization.runArgumentsExtraHint,
                error: switch (problem) {
                  RunArgumentsProblem.reservedFlag => localization.runArgumentsReservedFlag,
                  RunArgumentsProblem.unbalancedQuotes => localization.runArgumentsUnbalancedQuotes,
                  _ => null,
                },
              ),
              if (_saveFailed) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  localization.runArgumentsSaveFailed,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localization.cancel)),
        FilledButton(
          onPressed: problem == null && !_submitted ? _save : null,
          child: Text(localization.save),
        ),
      ],
    );
  }
}
