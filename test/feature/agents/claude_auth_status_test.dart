import 'package:flutter_code_agent/src/feature/agents/data/claude_auth_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a signed-in account is reported by its email', () {
    expect(parseClaudeAuthStatus('{"loggedIn":true,"email":"a@b.c"}'), (
      loggedIn: true,
      account: 'a@b.c',
    ));
  });

  test('the organization stands in for a missing email', () {
    expect(parseClaudeAuthStatus('{"loggedIn":true,"orgName":"Acme"}'), (
      loggedIn: true,
      account: 'Acme',
    ));
  });

  test('a signed-out CLI is not logged in', () {
    final auth = parseClaudeAuthStatus('{"loggedIn":false}');

    expect(auth?.loggedIn, isFalse);
    expect(auth?.account, isNull);
  });

  test('an API key counts as signed in and names its source', () {
    expect(parseClaudeAuthStatus('{"loggedIn":false,"apiKeySource":"ANTHROPIC_API_KEY"}'), (
      loggedIn: true,
      account: 'ANTHROPIC_API_KEY',
    ));
  });

  test('another provider counts as signed in, the first-party one does not', () {
    expect(parseClaudeAuthStatus('{"loggedIn":false,"apiProvider":"bedrock"}'), (
      loggedIn: true,
      account: 'bedrock',
    ));
    expect(parseClaudeAuthStatus('{"loggedIn":false,"apiProvider":"firstParty"}')?.loggedIn, false);
  });

  test('anything but a JSON object with loggedIn is unknown', () {
    expect(parseClaudeAuthStatus('not json'), isNull);
    expect(parseClaudeAuthStatus('{"email":"x"}'), isNull);
    expect(parseClaudeAuthStatus('{"loggedIn":"yes"}'), isNull);
    expect(parseClaudeAuthStatus('[true]'), isNull);
    expect(parseClaudeAuthStatus(''), isNull);
  });
}
