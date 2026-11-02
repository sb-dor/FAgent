import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException, CancellationSource;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_sign_in.dart';
import 'package:flutter_code_agent/src/feature/agents/data/claude_auth_status.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
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

/// The agents the app knows, their state on this machine and the actions the Settings screen offers.
abstract interface class IAgentsRepository {
  /// The built-in agents (Claude, Codex, Gemini CLI), then the custom ones: the last known state at
  /// once, then every change (a check, a sign-in, a custom agent added, changed or removed, the
  /// settings catalog). Watching checks nothing by itself. Closes when cancelled.
  Stream<List<AgentInfo>> watchAgents();

  /// The last known state of every agent, in the order of [watchAgents].
  List<AgentInfo> get agents;

  /// Checks [agentId] again: Claude through its CLI, every other agent with an ACP handshake.
  Future<void> refresh(String agentId);

  /// Checks every agent again.
  Future<void> refreshAll();

  /// Signs [agentId] in with [methodId]; once that succeeds the agent is checked again.
  ///
  /// A terminal login (Claude) is started and returned at once; its output and result follow in
  /// the [AgentLogin]. Any other method is ACP `authenticate` without a time limit: the call
  /// returns `null` once it succeeded and throws a [CancellationException] after [cancelLogin].
  /// One such sign-in per agent runs at a time; a request while one runs joins it, whatever its
  /// method. Throws [UnsupportedError] for a method set up in the agent itself.
  Future<AgentLogin?> login(String agentId, String methodId);

  /// Stops the running ACP sign-in of [agentId] (its connection closes); without one, nothing.
  Future<void> cancelLogin(String agentId);

  /// Signs [agentId] out and checks it again: Claude through its CLI, any other agent with ACP
  /// `logout`, which also closes the agent's connection, so a busy chat of it fails.
  ///
  /// Throws [UnsupportedError] for an agent that cannot sign out.
  Future<void> logout(String agentId);

  /// Whether a chat of [agentId] has a turn or a setup in flight.
  Future<bool> hasBusyChats(String agentId);

  /// Adds a custom ACP agent; it shows up in [watchAgents] and is checked.
  Future<void> addCustom(CustomAgentDraft draft);

  /// Replaces the custom agent [id]; its process restarts once no chat of it is busy.
  Future<void> updateCustom(String id, CustomAgentDraft draft);

  /// Removes the custom agent [id]; its process stops and its chats cannot continue.
  Future<void> removeCustom(String id);

  /// Opens Claude's settings file in the default editor; without the file, its folder in Finder.
  ///
  /// Throws [AgentSettingsMissingException] when neither exists and [ArgumentError] for any other
  /// agent.
  Future<void> openSettings(String agentId);
}

/// {@template agents_repository_impl}
/// [IAgentsRepository] over the agents of the [AgentHub] and the custom agents.
///
/// Claude is checked through its CLI (`npx`, Node.js, `claude auth status`); every other agent is
/// probed with a short ACP handshake ([IAgentProbe]), and Codex and Gemini CLI are then checked for
/// a sign-in. The results are kept in memory.
/// {@endtemplate}
final class AgentsRepositoryImpl implements IAgentsRepository {
  /// {@macro agents_repository_impl}
  ///
  /// [runProcess], [preflight], [statusTimeout] and [homeDirectory] are replaced in tests.
  AgentsRepositoryImpl({
    required this._hub,
    required this._environment,
    required this._catalog,
    required this._customAgents,
    required this._probe,
    ProcessRunner? runProcess,
    Future<String> Function(AgentDefinition, ShellEnvironment)? preflight,
    this._statusTimeout = const Duration(seconds: 30),
    this._homeDirectory,
  }) : _runProcess = runProcess ?? runProcessKillingOnTimeout,
       _preflight = preflight ?? AgentPreflight.check;

  final AgentHub _hub;
  final ShellEnvironment _environment;
  final IAgentOptionsCatalog _catalog;
  final ICustomAgentsRepository _customAgents;
  final IAgentProbe _probe;
  final ProcessRunner _runProcess;
  final Future<String> Function(AgentDefinition, ShellEnvironment) _preflight;
  final Duration _statusTimeout;
  final String? _homeDirectory;

  final Set<StreamController<List<AgentInfo>>> _watchers = <StreamController<List<AgentInfo>>>{};

  /// Check results by agent id.
  final Map<String, AgentInfo> _infos = <String, AgentInfo>{};

  /// The definition each agent was last checked with; an edited custom agent is checked again.
  final Map<String, AgentDefinition> _checked = <String, AgentDefinition>{};

  /// The agents as the custom agents last came in while watched; the hub's agents otherwise.
  List<AgentDefinition>? _watched;
  final Map<String, Future<void>> _checking = <String, Future<void>>{};
  final Set<String> _checkAgain = <String>{};
  final Map<String, _SignIn> _signIns = <String, _SignIn>{};
  Map<String, List<ConfigOption>> _options = const <String, List<ConfigOption>>{};
  String _catalogJson = '{}';

  List<AgentDefinition> get _definitions => _watched ?? _hub.agents.toList(growable: false);

  AgentDefinition? _definitionOf(String agentId) =>
      _definitions.where((definition) => definition.id == agentId).firstOrNull;

  AgentDefinition _require(String agentId) =>
      _definitionOf(agentId) ?? (throw ArgumentError.value(agentId, 'agentId', 'unknown agent'));

  static bool _isClaude(AgentDefinition definition) => definition.id == AgentDefinition.claude.id;

  String? get _home =>
      _homeDirectory ?? _environment.variables['HOME'] ?? Platform.environment['HOME'];

  static CustomAgentDraft? _draftOf(AgentDefinition definition) =>
      definition.source == AgentSource.custom
      ? CustomAgentDraft(
          name: definition.displayName,
          executable: definition.executable,
          arguments: definition.arguments,
          environment: definition.environment,
          rulesChannel: definition.rulesChannel,
        )
      : null;

  /// What is known of [definition] before it is checked.
  static AgentInfo _initial(AgentDefinition definition) => AgentInfo(
    id: definition.id,
    name: definition.displayName,
    version: _isClaude(definition) ? AgentDefinition.claudeAdapterVersion : null,
    source: definition.source,
    methods: _isClaude(definition)
        ? agentLoginMethods(definition, const [], const <String, String>{})
        : const <AgentLoginMethod>[],
    canSignOut: _isClaude(definition),
  );

  @override
  List<AgentInfo> get agents => <AgentInfo>[
    for (final definition in _definitions)
      (_infos[definition.id] ?? _initial(definition)).copyWith(
        name: definition.displayName,
        custom: _draftOf(definition),
        options: _options[definition.id] ?? const <ConfigOption>[],
      ),
  ];

  void _emit() {
    final snapshot = agents;
    for (final watcher in _watchers.toList()) {
      if (!watcher.isClosed) watcher.add(snapshot);
    }
  }

  @override
  Stream<List<AgentInfo>> watchAgents() {
    final controller = StreamController<List<AgentInfo>>();
    StreamSubscription<Map<String, List<Map<String, Object?>>>>? catalog;
    StreamSubscription<List<AgentDefinition>>? custom;
    controller
      ..onListen = () {
        _watchers.add(controller);
        controller.add(agents);
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
        custom = _customAgents.watch().listen(
          _onCustomAgents,
          onError: (Object error, StackTrace stackTrace) =>
              l.w('Agents | the custom agents failed: $error', stackTrace),
        );
      }
      ..onCancel = () async {
        _watchers.remove(controller);
        if (_watchers.isEmpty) _watched = null;
        await catalog?.cancel();
        await custom?.cancel();
        await controller.close();
      };
    return controller.stream;
  }

  /// A custom agent was added, changed or removed: the new ones and the edited ones are checked.
  void _onCustomAgents(List<AgentDefinition> custom) {
    final next = <AgentDefinition>[
      ..._hub.agents.where((definition) => definition.source == AgentSource.builtin),
      ...custom,
    ];
    final changed = !const ListEquality<AgentDefinition>().equals(next, _definitions);
    _watched = next;
    final ids = <String>{for (final definition in next) definition.id};
    _infos.removeWhere((id, _) => !ids.contains(id));
    _checked.removeWhere((id, _) => !ids.contains(id));
    for (final definition in custom) {
      if (_checked[definition.id] != definition) {
        unawaited(refresh(definition.id));
      }
    }
    if (changed) _emit();
  }

  @override
  Future<void> refresh(String agentId) {
    final running = _checking[agentId];
    if (running != null) {
      // The answer being computed may predate what changed; ask once more.
      _checkAgain.add(agentId);
      return running;
    }
    return _checking[agentId] = _checkUntilSettled(agentId);
  }

  @override
  Future<void> refreshAll() =>
      Future.wait(<Future<void>>[for (final definition in _definitions) refresh(definition.id)]);

  Future<void> _checkUntilSettled(String agentId) async {
    try {
      do {
        _checkAgain.remove(agentId);
        final definition = _definitionOf(agentId);
        if (definition == null) return;
        _checked[agentId] = definition;
        final AgentInfo info;
        try {
          info = _isClaude(definition)
              ? await _checkClaude(definition)
              : await _checkAgent(definition);
        } on Object catch (error, stackTrace) {
          l.w('Agents | checking $agentId failed: $error', stackTrace);
          return;
        }
        // Removed while it was checked.
        if (_definitionOf(agentId) == null) return;
        if (info != _infos[agentId]) {
          _infos[agentId] = info;
          _emit();
        }
      } while (_checkAgain.contains(agentId));
    } finally {
      _checking.remove(agentId);
    }
  }

  Future<AgentInfo> _checkClaude(AgentDefinition definition) async {
    final base = _initial(definition);
    final String executable;
    try {
      executable = await _preflight(definition, _environment);
    } on AgentPreflightException catch (error) {
      return base.copyWith(
        status: AgentStatus.notInstalled,
        problem: error.message,
        hint: error.hint,
      );
    } on Object catch (error, stackTrace) {
      l.w('Agents | the Claude check failed: $error', stackTrace);
      return base.copyWith(status: AgentStatus.notInstalled, problem: '$error');
    }
    final runtime = await _nodeRuntime();
    final auth = await _authStatus(definition, executable);
    return base.copyWith(
      runtime: runtime,
      status: auth != null && !auth.loggedIn ? AgentStatus.needsLogin : AgentStatus.ready,
      account: auth?.account,
    );
  }

  /// Any agent but Claude: an ACP handshake, then, for Codex and Gemini CLI, their sign-in.
  Future<AgentInfo> _checkAgent(AgentDefinition definition) async {
    // Only Codex pushes its sign-in after `initialize`; nobody else is waited for.
    final result = await _probe.probe(
      definition,
      authStatusWait: definition.id == AgentDefinition.codex.id ? null : Duration.zero,
    );
    final base = _initial(definition).copyWith(version: result.version);
    if (result.notInstalled) {
      return base.copyWith(
        status: AgentStatus.notInstalled,
        problem: result.notInstalledReason,
        hint: result.notInstalledHint,
      );
    }
    if (result.failure case final failure?) {
      return base.copyWith(status: AgentStatus.failed, problem: failure);
    }
    final environment = <String, String>{..._environment.variables, ...definition.environment};
    final signIn = builtinSignIn(
      definition,
      environment: environment,
      home: _home,
      authStatus: result.authStatus,
    );
    return base.copyWith(
      runtime: definition.minimumNodeMajor == null ? null : await _nodeRuntime(),
      // A custom agent says it needs a sign-in in its first chat.
      status: signIn == null || signIn.signedIn ? AgentStatus.ready : AgentStatus.needsLogin,
      account: signIn?.account,
      methods: agentLoginMethods(definition, result.authMethods, environment),
      canSignOut: result.canLogout,
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
  Future<ClaudeAuth?> _authStatus(AgentDefinition claude, String executable) async {
    try {
      final result = await _runProcess(
        executable,
        <String>[...claude.arguments, '--cli', 'auth', 'status', '--json'],
        environment: _environmentOf(claude),
        timeout: _statusTimeout,
      );
      // A signed-out CLI may exit with a non-zero code and still print the JSON.
      return parseClaudeAuthStatus('${result.stdout}');
    } on Object catch (error) {
      l.w('Agents | claude auth status failed: $error');
      return null;
    }
  }

  Map<String, String> _environmentOf(AgentDefinition definition) => <String, String>{
    ..._environment.variables,
    ...definition.environment,
  };

  @override
  Future<AgentLogin?> login(String agentId, String methodId) async {
    final definition = _require(agentId);
    if (definition.loginArguments.containsKey(methodId)) {
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
    final method = _infos[agentId]?.methods.where((m) => m.id == methodId).firstOrNull;
    if (method?.kind == AgentLoginKind.unsupported) {
      throw UnsupportedError('$methodId is set up in ${definition.displayName} itself');
    }
    await _signIn(agentId, methodId);
    return null;
  }

  /// ACP `authenticate`, one per agent at a time.
  Future<void> _signIn(String agentId, String methodId) {
    if (_signIns[agentId] case final running?) return running.done;
    final signIn = _SignIn();
    _signIns[agentId] = signIn;
    return signIn.done = _hub
        .authenticate(agentId, methodId, cancel: signIn.source.token)
        .whenComplete(() {
          if (identical(_signIns[agentId], signIn)) _signIns.remove(agentId);
        })
        .then((_) => unawaited(refresh(agentId)));
  }

  @override
  Future<void> cancelLogin(String agentId) async {
    final running = _signIns[agentId];
    if (running == null) return;
    running.source.cancel('Sign-in cancelled');
    try {
      await running.done;
    } on Object catch (_) {
      // The caller of `login` gets the cancellation.
    }
  }

  @override
  Future<void> logout(String agentId) async {
    final definition = _require(agentId);
    if (_isClaude(definition)) {
      try {
        final executable = await _preflight(definition, _environment);
        final arguments = <String>[...definition.arguments, '--cli', 'auth', 'logout'];
        final result = await _runProcess(
          executable,
          arguments,
          environment: _environmentOf(definition),
          timeout: _statusTimeout,
        );
        if (result.exitCode != 0) {
          throw ProcessException(executable, arguments, '${result.stderr}'.trim(), result.exitCode);
        }
      } finally {
        await refresh(agentId);
      }
      return;
    }
    if (!(_infos[agentId]?.canSignOut ?? false)) {
      throw UnsupportedError('${definition.displayName} cannot sign out from the app');
    }
    try {
      await _hub.logout(agentId);
    } finally {
      await refresh(agentId);
    }
  }

  @override
  Future<bool> hasBusyChats(String agentId) async =>
      (await _hub.busySessions()).any((session) => session.agentId == agentId);

  @override
  Future<void> addCustom(CustomAgentDraft draft) => _customAgents.add(draft);

  @override
  Future<void> updateCustom(String id, CustomAgentDraft draft) => _customAgents.update(id, draft);

  @override
  Future<void> removeCustom(String id) => _customAgents.remove(id);

  @override
  Future<void> openSettings(String agentId) async {
    if (agentId != AgentDefinition.claude.id) {
      throw ArgumentError.value(agentId, 'agentId', 'only Claude has a settings file');
    }
    final home = _home;
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
}

/// One ACP sign-in in flight.
final class _SignIn {
  final CancellationSource source = CancellationSource();
  late final Future<void> done;
}
