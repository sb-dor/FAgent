import 'package:flutter_code_agent/src/common/utils/url_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9100/?uri=ws://127.0.0.1:5000/abc=/ws');
  final text = url.toString();

  group('openCommand', () {
    test('macOS uses open', () {
      final (executable, arguments) = openCommand(url, operatingSystem: 'macos');
      expect(executable, 'open');
      expect(arguments, <String>[text]);
    });

    test('Linux uses xdg-open', () {
      final (executable, arguments) = openCommand(url, operatingSystem: 'linux');
      expect(executable, 'xdg-open');
      expect(arguments, <String>[text]);
    });

    test('Windows uses cmd /c start with an empty window title', () {
      final (executable, arguments) = openCommand(url, operatingSystem: 'windows');
      expect(executable, 'cmd');
      expect(arguments, <String>['/c', 'start', '', text]);
    });

    test('an unknown system has no command', () {
      expect(() => openCommand(url, operatingSystem: 'fuchsia'), throwsUnsupportedError);
    });
  });
}
