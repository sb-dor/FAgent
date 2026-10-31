import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_json.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a stdio server with args and env', () {
    final result = parseMcpJson('''
{"mcpServers": {"local": {"command": "npx", "args": ["-y", "figma-mcp"], "env": {"TOKEN": "x"}}}}
''');
    expect(result.skipped, isEmpty);
    expect(
      result.servers.single,
      const McpServerDraft(
        name: 'local',
        transport: McpTransport.stdio,
        command: 'npx',
        args: ['-y', 'figma-mcp'],
        env: {'TOKEN': 'x'},
      ),
    );
  });

  test('a url without a type is http', () {
    final result = parseMcpJson('{"mcpServers": {"figma": {"url": "https://mcp.figma.com/mcp"}}}');
    expect(
      result.servers.single,
      const McpServerDraft(
        name: 'figma',
        transport: McpTransport.http,
        url: 'https://mcp.figma.com/mcp',
      ),
    );
  });

  test('type http keeps headers', () {
    final result = parseMcpJson(
      '{"mcpServers": {"a": {"type": "http", "url": "https://x.dev", "headers": {"Authorization": "t"}}}}',
    );
    expect(result.servers.single.headers, {'Authorization': 't'});
    expect(result.servers.single.transport, McpTransport.http);
  });

  test('sse and empty entries are skipped with a reason', () {
    final result = parseMcpJson('''
{"mcpServers": {
  "events": {"type": "sse", "url": "https://x.dev/sse"},
  "empty": {},
  "text": "oops",
  "ok": {"command": "dart"}
}}
''');
    expect(result.servers.map((s) => s.name), ['ok']);
    expect(result.skipped, [
      ('events', 'sse is not supported'),
      ('empty', 'no command or url'),
      ('text', 'no command or url'),
    ]);
  });

  test('text that is not an mcpServers object throws', () {
    expect(() => parseMcpJson('[]'), throwsA(isA<McpJsonException>()));
    expect(() => parseMcpJson('{}'), throwsA(isA<McpJsonException>()));
    expect(() => parseMcpJson('{"mcpServers": []}'), throwsA(isA<McpJsonException>()));
    expect(() => parseMcpJson('not json'), throwsA(isA<McpJsonException>()));
  });
}
