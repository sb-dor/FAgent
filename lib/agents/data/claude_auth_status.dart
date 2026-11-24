import 'dart:convert';

/// Result of `claude auth status --json`.
typedef ClaudeAuth = ({bool loggedIn, String? account});

/// Parses the output of `claude auth status --json`.
///
/// Returns `null` when [stdout] is not a JSON object with a boolean `loggedIn`. The user counts as
/// signed in with `loggedIn`, an API key (`apiKeySource`) or a provider other than `firstParty`
/// (Bedrock, Vertex, …); `account` is the first of `email`, `orgName`, `apiKeySource`, `apiProvider`.
ClaudeAuth? parseClaudeAuthStatus(String stdout) {
  final Object? json;
  try {
    json = jsonDecode(stdout.trim());
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final object = json;
  final loggedIn = object['loggedIn'];
  if (loggedIn is! bool) return null;
  String? text(String key) => switch (object[key]) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };
  final apiKeySource = text('apiKeySource');
  final apiProvider = text('apiProvider');
  final viaProvider = apiProvider != null && apiProvider != 'firstParty';
  return (
    loggedIn: loggedIn || apiKeySource != null || viaProvider,
    account: text('email') ?? text('orgName') ?? apiKeySource ?? apiProvider,
  );
}
