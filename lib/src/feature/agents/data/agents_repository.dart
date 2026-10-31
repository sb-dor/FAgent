import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/claude_auth_status.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// Runs [executable] and returns its result. With a [timeout] the process is killed when it runs
/// longer and a [TimeoutException] is thrown.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration? timeout,
});

/// The [ProcessRunner] of the app: the process runs in its own process group ([GroupedProcess]),
/// stdout and stderr are read as text, and when it outlives [timeout] the whole group is killed
/// (`npx` leaves `node` children behind otherwise) and a [TimeoutException] is thrown.
///
/// Whatever the group still holds after the process ends is killed too, so nothing is left running.
/// With an [environment] only that environment is passed to the process.
Future<ProcessResult> runProcessKillingOnTimeout(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  final process = await GroupedProcess.start(executable, arguments, environment: environment);
  process.stdin.close().ignore();
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final stdoutSubscription = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(stdout.write);
  final stderrSubscription = process.stderrLines.listen(stderr.writeln);
  try {
    final exitCode = timeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            timeout,
            onTimeout: () => throw TimeoutException('$executable did not finish', timeout),
          );
    // A background process of the group may hold the pipes open; do not wait for it for long.
    await Future.wait<void>(<Future<void>>[
      stdoutSubscription.asFuture<void>(),
      stderrSubscription.asFuture<void>(),
    ]).timeout(const Duration(seconds: 1), onTimeout: () => const <void>[]);
    return ProcessResult(process.pgid, exitCode, stdout.toString(), stderr.toString());
  } finally {
    process.signalGroup(ProcessSignal.sigkill);
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

/// Codex until it is supported for real (M5): only shown, nothing runs.
const AgentInfo previewCodexAgent = AgentInfo(
  id: 'codex',
  name: 'Codex',
  status: AgentStatus.notInstalled,
  problem: 'codex-acp · Node 22+',
  isPreview: true,
);

/// Gemini CLI until it is supported for real (M5): only shown, nothing runs.
const AgentInfo previewGeminiAgent = AgentInfo(
  id: 'gemini',
  name: 'Gemini CLI',
  version: '0.9.2',
  status: AgentStatus.needsLogin,
  loginMethods: <String>['google'],
  isPreview: true,
);

/// The agents the app knows, their state on this machine and the actions the Settings screen offers.
abstract interface class IAgentsRepository {
  /// Claude, Codex and Gemini in this order: the last known state at once, then the result of
  /// checking Claude, then every change (a check, a login, the settings catalog). Closes when
  /// cancelled.
  Stream<List<AgentInfo>> watchAgents();

  /// Checks [agentId] again. A preview agent has nothing to check.
  Future<void> refresh(String agentId);

  /// Starts the login [methodId] of [agentId]; once it succeeds the agent is checked again.
  ///
  /// Throws [AgentPreviewException] for a preview agent.
  Future<AgentLogin> login(String agentId, String methodId);

  /// Signs [agentId] out and checks it again.
  ///
  /// Throws [AgentPreviewException] for a preview agent.
  Future<void> logout(String agentId);

  /// Installs [agentId]. Claude runs through `npx` and needs no install, so for now this throws
  /// [AgentPreviewException] for every agent.
  Future<void> install(String agentId);

  /// Opens the settings file of [agentId] in the default editor; without the file, its folder in
  /// Finder.
  ///
  /// Throws [AgentSettingsMissingException] when neither exists and [AgentPreviewException] for a
  /// preview agent.
  Future<void> openSettings(String agentId);
}

/// {@template agents_repository_impl}
/// [IAgentsRepository] that checks Claude for real (`npx`, Node.js, `claude auth status`) and
/// shows Codex and Gemini as previews.
/// {@endtemplate}
final class AgentsRepositoryImpl implements IAgentsRepository {
  /// {@macro agents_repository_impl}
  ///
  /// [runProcess], [preflight], [statusTimeout] and [homeDirectory] are replaced in tests.
  AgentsRepositoryImpl({
    required this._hub,
    required this._environment,
    required this._catalog,
    ProcessRunner? runProcess,
    Future<String> Function(AgentDefinition, ShellEnvironment)? preflight,
    this._statusTimeout = const Duration(seconds: 30),
    this._homeDirectory,
  }) : _runProcess = runProcess ?? runProcessKillingOnTimeout,
       _preflight = preflight ?? AgentPreflight.check;

  static const AgentDefinition _claudeDefinition = AgentDefinition.claude;

  final AgentHub _hub;
  final ShellEnvironment _environment;
  final IAgentOptionsCatalog _catalog;
  final ProcessRunner _runProcess;
  final Future<String> Function(AgentDefinition, ShellEnvironment) _preflight;
  final Duration _statusTimeout;
  final String? _homeDirectory;

  final Set<StreamController<List<AgentInfo>>> _watchers = <StreamController<List<AgentInfo>>>{};
  AgentInfo _claude = AgentInfo(
    id: _claudeDefinition.id,
    name: _claudeDefinition.displayName,
    version: AgentDefinition.claudeAdapterVersion,
    loginMethods: _claudeDefinition.loginArguments.keys.toList(growable: false),
    canStartChats: true,
  );
  Map<String, List<ConfigOption>> _options = const <String, List<ConfigOption>>{};
  String _catalogJson = '{}';
  Future<void>? _checking;
  bool _checkAgain = false;

  List<AgentInfo> _snapshot() => <AgentInfo>[
    for (final info in <AgentInfo>[_claude, previewCodexAgent, previewGeminiAgent])
      info.copyWith(options: _options[info.id] ?? const <ConfigOption>[]),
  ];

  void _emit() {
    final agents = _snapshot();
    for (final watcher in _watchers.toList()) {
      if (!watcher.isClosed) watcher.add(agents);
    }
  }

  @override
  Stream<List<AgentInfo>> watchAgents() {
    final controller = StreamController<List<AgentInfo>>();
    StreamSubscription<Map<String, List<Map<String, Object?>>>>? catalog;
    controller
      ..onListen = () {
        _watchers.add(controller);
        controller.add(_snapshot());
        catalog = _catalog.watch().listen(
          (raw) {
            final json = jsonEncode(raw);
            if (json == _catalogJson) return;
            _catalogJson = json;
            _options = <String, List<ConfigOption>>{
              for (final MapEntry(:key, :value) in raw.entries) key: ConfigOption.parseAll(value),
            };
            _emit();
          },
          onError: (Object error, StackTrace stackTrace) =>
              l.w('Agents | the options catalog failed: $error', stackTrace),
        );
        unawaited(refresh(_claudeDefinition.id));
      }
      ..onCancel = () async {
        _watchers.remove(controller);
        await catalog?.cancel();
        await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> refresh(String agentId) {
    if (agentId != _claudeDefinition.id) return Future<void>.value();
    final running = _checking;
    if (running != null) {
      // The answer being computed may predate what changed; ask once more.
      _checkAgain = true;
      return running;
    }
    return _checking = _checkClaudeUntilSettled();
  }

  Future<void> _checkClaudeUntilSettled() async {
    try {
      do {
        _checkAgain = false;
        final info = await _checkClaude();
        if (info != _claude) {
          _claude = info;
          _emit();
        }
      } while (_checkAgain);
    } finally {
      _checking = null;
    }
  }

  Future<AgentInfo> _checkClaude() async {
    final base = _claude.copyWith(
      status: AgentStatus.checking,
      account: null,
      problem: null,
      hint: null,
    );
    final String executable;
    try {
      executable = await _preflight(_claudeDefinition, _environment);
    } on AgentPreflightException catch (error) {
      return base.copyWith(
        status: AgentStatus.notInstalled,
        runtime: null,
        problem: error.message,
        hint: error.hint,
      );
    } on Object catch (error, stackTrace) {
      l.w('Agents | the Claude check failed: $error', stackTrace);
      return base.copyWith(status: AgentStatus.notInstalled, runtime: null, problem: '$error');
    }
    final runtime = await _nodeRuntime();
    final auth = await _authStatus(executable);
    return base.copyWith(
      runtime: runtime,
      status: auth != null && !auth.loggedIn ? AgentStatus.needsLogin : AgentStatus.ready,
      account: auth?.account,
    );
  }

  /// `Node 22.11` from `node --version`, or `null` when it cannot be read.
  Future<String?> _nodeRuntime() async {
    try {
      final result = await _runProcess(
        _environment.which('node') ?? 'node',
        const <String>['--version'],
        environment: _environment.variables,
        timeout: _statusTimeout,
      );
      final match = RegExp(r'^v(\d+)\.(\d+)').firstMatch('${result.stdout}'.trim());
      return match == null ? null : 'Node ${match.group(1)}.${match.group(2)}';
    } on Object catch (error) {
      l.w('Agents | node --version failed: $error');
      return null;
    }
  }

  /// The sign-in state, or `null` when it cannot be told (a hung or unreadable `auth status`).
  Future<ClaudeAuth?> _authStatus(String executable) async {
    try {
      final result = await _runProcess(
        executable,
        <String>[..._claudeDefinition.arguments, '--cli', 'auth', 'status', '--json'],
        environment: _claudeEnvironment,
        timeout: _statusTimeout,
      );
      // A signed-out CLI may exit with a non-zero code and still print the JSON.
      return parseClaudeAuthStatus('${result.stdout}');
    } on Object catch (error) {
      l.w('Agents | claude auth status failed: $error');
      return null;
    }
  }

  Map<String, String> get _claudeEnvironment => <String, String>{
    ..._environment.variables,
    ..._claudeDefinition.environment,
  };

  @override
  Future<AgentLogin> login(String agentId, String methodId) async {
    _requireClaude(agentId);
    final login = await _hub.login(agentId, methodId);
    unawaited(
      login.succeeded.then((succeeded) => succeeded ? refresh(agentId) : null).onError<Object>((
        error,
        stackTrace,
      ) {
        l.w('Agents | the check after login failed: $error', stackTrace);
      }),
    );
    return login;
  }

  @override
  Future<void> logout(String agentId) async {
    _requireClaude(agentId);
    try {
      final executable = await _preflight(_claudeDefinition, _environment);
      final arguments = <String>[..._claudeDefinition.arguments, '--cli', 'auth', 'logout'];
      final result = await _runProcess(
        executable,
        arguments,
        environment: _claudeEnvironment,
        timeout: _statusTimeout,
      );
      if (result.exitCode != 0) {
        throw ProcessException(executable, arguments, '${result.stderr}'.trim(), result.exitCode);
      }
    } finally {
      await refresh(agentId);
    }
  }

  @override
  Future<void> install(String agentId) => Future<void>.error(const AgentPreviewException('M5'));

  @override
  Future<void> openSettings(String agentId) async {
    _requireClaude(agentId);
    final home = _homeDirectory ?? _environment.variables['HOME'] ?? Platform.environment['HOME'];
    if (home == null) throw AgentSettingsMissingException(agentId);
    final folder = p.join(home, '.claude');
    final file = p.join(folder, 'settings.json');
    final List<String> arguments;
    if (File(file).existsSync()) {
      arguments = <String>['-t', file];
    } else if (Directory(folder).existsSync()) {
      arguments = <String>[folder];
    } else {
      throw AgentSettingsMissingException(agentId);
    }
    await _runProcess('open', arguments);
  }

  /// Throws for a preview agent (and for an unknown id); returns for Claude.
  void _requireClaude(String agentId) {
    if (agentId == _claudeDefinition.id) return;
    if (agentId == previewCodexAgent.id || agentId == previewGeminiAgent.id) {
      throw const AgentPreviewException('M5');
    }
    throw ArgumentError.value(agentId, 'agentId', 'unknown agent');
  }
}
