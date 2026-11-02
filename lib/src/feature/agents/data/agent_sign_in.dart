import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:path/path.dart' as p;

/// Sign-in methods the app leaves to the agent's own settings.
const Set<String> _unsupportedMethods = <String>{'vertex-ai', 'gateway'};

/// The sign-in methods of [agent]: its terminal logins ([AgentDefinition.loginArguments]), then
/// the methods of its `initialize` answer ([authMethods]).
///
/// A method with an API-key provider or with [AgentDefinition.keyVariables] signs in with a key;
/// it has its key when one of those variables is set in [environment] (or when the agent names
/// none, so the agent is left to find it). Vertex AI and gateways are not offered; the rest open
/// the browser.
List<AgentLoginMethod> agentLoginMethods(
  AgentDefinition agent,
  List<AcpAuthMethod> authMethods,
  Map<String, String> environment,
) => <AgentLoginMethod>[
  for (final id in agent.loginArguments.keys)
    AgentLoginMethod(id: id, name: id, kind: AgentLoginKind.terminal),
  for (final method in authMethods)
    if (!agent.loginArguments.containsKey(method.id)) _method(agent, method, environment),
];

AgentLoginMethod _method(
  AgentDefinition agent,
  AcpAuthMethod method,
  Map<String, String> environment,
) {
  if (_unsupportedMethods.contains(method.id)) {
    return AgentLoginMethod(id: method.id, name: method.name, kind: AgentLoginKind.unsupported);
  }
  final variables = agent.keyVariables[method.id];
  if (variables == null && method.apiKeyProvider == null) {
    return AgentLoginMethod(id: method.id, name: method.name, kind: AgentLoginKind.browser);
  }
  final known = variables ?? const <String>[];
  return AgentLoginMethod(
    id: method.id,
    name: method.name,
    kind: AgentLoginKind.apiKey,
    keyVariables: known,
    keyPresent: known.isEmpty || _setVariable(known, environment) != null,
  );
}

/// The first of [variables] that is set to something in [environment].
String? _setVariable(Iterable<String> variables, Map<String, String> environment) {
  for (final variable in variables) {
    if ((environment[variable] ?? '').isNotEmpty) return variable;
  }
  return null;
}

/// Whether an agent is signed in, and as whom (a plan, or the variable of the key).
typedef AgentSignIn = ({bool signedIn, String? account});

/// The sign-in of the built-in Codex or Gemini CLI; `null` for any other agent.
///
/// Codex: the status it pushed after `initialize` ([authStatus]; any kind but `none` is signed
/// in), else `~/.codex/auth.json` or a key variable. Gemini CLI: `~/.gemini/oauth_creds.json` or
/// `GEMINI_API_KEY`. [home] is the user's home folder; without it only the variables count.
AgentSignIn? builtinSignIn(
  AgentDefinition agent, {
  required Map<String, String> environment,
  required String? home,
  AcpAuthStatus? authStatus,
}) {
  final String credentials;
  if (agent.id == AgentDefinition.codex.id) {
    if (authStatus != null) {
      final signedIn = authStatus.kind != 'none';
      return (signedIn: signedIn, account: signedIn ? authStatus.label : null);
    }
    credentials = p.join('.codex', 'auth.json');
  } else if (agent.id == AgentDefinition.gemini.id) {
    credentials = p.join('.gemini', 'oauth_creds.json');
  } else {
    return null;
  }
  if (home != null && File(p.join(home, credentials)).existsSync()) {
    return (signedIn: true, account: null);
  }
  final variable = _setVariable(agent.keyVariables.values.expand((names) => names), environment);
  return (signedIn: variable != null, account: variable);
}
