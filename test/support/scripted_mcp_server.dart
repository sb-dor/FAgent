// A scripted stdio MCP server for tests, run as a real child process.
//
// The first argument selects the behaviour:
//   tools <n>        answer `initialize` and `tools/list` (n tools named tool1, tool2, …)
//   silent <file>    never answer. Writes its pid to <file> and the pid of a `sleep` child it
//                    started in the same process group to <file>.child.
//   stderr <text>    write <text> to stderr and exit with code 2
//   env <NAME>…      write NAME=value of each variable to stderr and exit with code 2

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final mode = arguments.isEmpty ? 'tools' : arguments.first;
  switch (mode) {
    case 'silent':
      final file = arguments[1];
      final child = await Process.start('sleep', const <String>['300']);
      File(file).writeAsStringSync('$pid');
      File('$file.child').writeAsStringSync('${child.pid}');
      await stdin.drain<void>();
    case 'stderr':
      stderr.writeln(arguments[1]);
      exit(2);
    case 'env':
      stderr.writeln(
        [for (final name in arguments.skip(1)) '$name=${Platform.environment[name]}'].join(' '),
      );
      exit(2);
    default:
      final count = arguments.length > 1 ? int.parse(arguments[1]) : 0;
      await stdin.transform(utf8.decoder).transform(const LineSplitter()).forEach((line) {
        final message = jsonDecode(line) as Map<String, Object?>;
        final id = message['id'];
        if (id == null) return;
        Object? result;
        switch (message['method']) {
          case 'initialize':
            result = <String, Object?>{
              'protocolVersion': (message['params']! as Map<String, Object?>)['protocolVersion'],
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
              'serverInfo': <String, Object?>{'name': 'scripted', 'version': '1.0.0'},
            };
          case 'tools/list':
            result = <String, Object?>{
              'tools': <Object?>[
                for (var i = 1; i <= count; i++)
                  <String, Object?>{
                    'name': 'tool$i',
                    'description': 'Tool $i',
                    'inputSchema': <String, Object?>{'type': 'object'},
                  },
              ],
            };
        }
        stdout.writeln(
          jsonEncode(
            result == null
                ? <String, Object?>{
                    'jsonrpc': '2.0',
                    'id': id,
                    'error': <String, Object?>{'code': -32601, 'message': 'Method not found'},
                  }
                : <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result},
          ),
        );
      });
  }
}
