import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_server_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_input.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';

/// {@template add_mcp_server_dialog}
/// Asks for a new MCP server over [transport]: a command with arguments and variables for `stdio`,
/// an address with headers for `http`.
///
/// What the repository refuses (a bad or taken name, no command, a bad address) is explained under
/// the field it is about and the dialog stays open. The dialog closes when the server is added, or
/// when the action fails for another reason; the section tells the user about that.
/// {@endtemplate}
class AddMcpServerDialog extends StatefulWidget {
  /// {@macro add_mcp_server_dialog}
  const AddMcpServerDialog({required this.scope, required this.transport, super.key});

  /// The section the server is added to. The dialog is on a route above the section, so it cannot
  /// look the section up.
  final McpServersConfigWidgetState scope;

  /// What kind of server is added.
  final McpTransport transport;

  @override
  State<AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

class _AddMcpServerDialogState extends State<AddMcpServerDialog> {
  McpServersConfigWidgetState get _scope => widget.scope;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _command = TextEditingController();
  final TextEditingController _args = TextEditingController();
  final TextEditingController _env = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _headers = TextEditingController();

  /// Whether this dialog has asked for the server; the actions are shared with the section.
  bool _submitted = false;
  bool _busy = false;
  McpServerProblem? _problem;
  bool _badEnv = false;
  bool _badHeaders = false;

  bool get _stdio => widget.transport == McpTransport.stdio;

  @override
  void initState() {
    super.initState();
    _scope.actions.addListener(_onAction);
  }

  @override
  void dispose() {
    _scope.actions.removeListener(_onAction);
    for (final controller in <TextEditingController>[
      _name,
      _command,
      _args,
      _env,
      _url,
      _headers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onAction() {
    if (!_submitted) return;
    switch (_scope.actions.state) {
      case McpServerActions$CompletedState():
        Navigator.of(context).pop();
      case McpServerActions$FailedState(error: InvalidMcpServerException(:final problem)):
        setState(() {
          _submitted = false;
          _busy = false;
          _problem = problem;
        });
      case McpServerActions$FailedState():
        Navigator.of(context).pop();
      case McpServerActions$ProcessingState():
        setState(() => _busy = true);
      case McpServerActions$IdleState():
        break;
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    final env = _stdio ? parseKeyValueLines(_env.text, '=') : const <String, String>{};
    final headers = _stdio ? const <String, String>{} : parseKeyValueLines(_headers.text, ':');
    if (env == null || headers == null) {
      setState(() {
        _badEnv = env == null;
        _badHeaders = headers == null;
      });
      return;
    }
    setState(() {
      _problem = null;
      _submitted = true;
    });
    _scope.actions.add(
      _stdio
          ? McpServerDraft(
              name: name,
              transport: McpTransport.stdio,
              command: _command.text.trim(),
              args: splitArguments(_args.text),
              env: env,
            )
          : McpServerDraft(
              name: name,
              transport: McpTransport.http,
              url: _url.text.trim(),
              headers: headers,
            ),
    );
  }

  /// Forgets the explanation under a field once the user edits it.
  void _edited({
    Set<McpServerProblem> problems = const {},
    bool env = false,
    bool headers = false,
  }) {
    setState(() {
      if (problems.contains(_problem)) _problem = null;
      if (env) _badEnv = false;
      if (headers) _badHeaders = false;
    });
  }

  String? _errorFor(Set<McpServerProblem> problems) {
    final problem = _problem;
    if (problem == null || !problems.contains(problem)) return null;
    final localization = Localization.of(context);
    return switch (problem) {
      McpServerProblem.invalidName => localization.mcpErrorInvalidName,
      McpServerProblem.duplicateName => localization.mcpErrorDuplicateName,
      McpServerProblem.missingCommand => localization.mcpErrorMissingCommand,
      McpServerProblem.invalidUrl => localization.mcpErrorInvalidUrl,
    };
  }

  Widget _field({
    required String id,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? error,
    bool mono = true,
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
      key: ValueKey<String>('mcp-field-$id'),
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 4 : 1,
      style: mono
          ? AppText.mono(context, size: 13).copyWith(color: colors.text)
          : Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text),
      cursorColor: colors.accent,
      onChanged: (_) => onChanged?.call(),
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
    const gap = SizedBox(height: 16);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      title: Text(_stdio ? localization.mcpDialogStdioTitle : localization.mcpDialogHttpTitle),
      content: SizedBox(
        width: 440,
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
                label: localization.mcpFieldName,
                hint: localization.mcpFieldNameHint,
                error: _errorFor(const {
                  McpServerProblem.invalidName,
                  McpServerProblem.duplicateName,
                }),
                autofocus: true,
                onChanged: () => _edited(
                  problems: const {McpServerProblem.invalidName, McpServerProblem.duplicateName},
                ),
              ),
              gap,
              if (_stdio) ...<Widget>[
                _field(
                  id: 'command',
                  controller: _command,
                  label: localization.mcpFieldCommand,
                  error: _errorFor(const {McpServerProblem.missingCommand}),
                  onChanged: () => _edited(problems: const {McpServerProblem.missingCommand}),
                ),
                gap,
                _field(
                  id: 'args',
                  controller: _args,
                  label: localization.mcpFieldArgs,
                  hint: localization.mcpFieldArgsHint,
                ),
                gap,
                _field(
                  id: 'env',
                  controller: _env,
                  label: localization.mcpFieldEnv,
                  hint: localization.mcpFieldEnvHint,
                  error: _badEnv ? localization.mcpErrorEnvLine : null,
                  multiline: true,
                  onChanged: () => _edited(env: true),
                ),
              ] else ...<Widget>[
                _field(
                  id: 'url',
                  controller: _url,
                  label: localization.mcpFieldUrl,
                  error: _errorFor(const {McpServerProblem.invalidUrl}),
                  onChanged: () => _edited(problems: const {McpServerProblem.invalidUrl}),
                ),
                gap,
                _field(
                  id: 'headers',
                  controller: _headers,
                  label: localization.mcpFieldHeaders,
                  hint: localization.mcpFieldHeadersHint,
                  error: _badHeaders ? localization.mcpErrorHeaderLine : null,
                  multiline: true,
                  onChanged: () => _edited(headers: true),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localization.cancel)),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _busy ? null : _submit,
          child: Text(localization.mcpDialogAdd),
        ),
      ],
    );
  }
}
