import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> names(List<SlashCommand> commands) => <String>[for (final c in commands) c.name];

  SlashCommand agent(String name, [String? description]) =>
      SlashCommand(name: name, description: description, source: SlashSource.agent);

  group('agentCommands', () {
    test('agent commands are parsed and broken entries skipped', () {
      final commands = agentCommands(<Map<String, Object?>>[
        <String, Object?>{'name': 'compact', 'description': 'Compact'},
        <String, Object?>{'name': 5},
        <String, Object?>{'description': 'x'},
        <String, Object?>{'name': 'compact'},
        <String, Object?>{'name': 'init'},
      ]);

      expect(names(commands), <String>['compact', 'init']);
      expect(commands.first.description, 'Compact');
      expect(commands.first.source, SlashSource.agent);
      expect(commands.first.enabled, isTrue);
      expect(commands.last.description, isNull);
    });

    test('names with spaces or no text are skipped, odd descriptions become null', () {
      final commands = agentCommands(<Map<String, Object?>>[
        <String, Object?>{'name': 'two words'},
        <String, Object?>{'name': ''},
        <String, Object?>{'name': 'ok', 'description': 7},
        <String, Object?>{'name': 'blank', 'description': ''},
      ]);

      expect(names(commands), <String>['ok', 'blank']);
      expect(commands.map((c) => c.description), everyElement(isNull));
    });
  });

  group('appCommands', () {
    test('are run, reload, restart and screenshot, all disabled until M2', () {
      expect(names(appCommands), <String>['run', 'reload', 'restart', 'screenshot']);
      expect(appCommands.every((c) => !c.enabled && c.hint == 'M2'), isTrue);
      expect(appCommands.every((c) => c.source == SlashSource.app), isTrue);
    });
  });

  group('searchCommands', () {
    test('search ranks name prefix, then name, then description', () {
      final all = <SlashCommand>[
        agent('init', 'Review the code'),
        agent('preview'),
        agent('review'),
        agent('other', 'nothing'),
      ];

      expect(names(searchCommands(all, 'rev')), <String>['review', 'preview', 'init']);
      expect(names(searchCommands(all, 'REV')), <String>['review', 'preview', 'init']);
    });

    test('an empty query keeps the order and the limit applies', () {
      final all = <SlashCommand>[for (var i = 0; i < 20; i++) agent('c$i')];
      expect(names(searchCommands(all, '')), names(all.take(12).toList()));
      expect(searchCommands(all, '', limit: 3), hasLength(3));
    });

    test('commands of the same rank keep their order', () {
      final all = <SlashCommand>[agent('b1'), agent('b3'), agent('b2')];
      expect(names(searchCommands(all, 'b')), <String>['b1', 'b3', 'b2']);
    });

    test('a large command list filters quickly', () {
      final all = <SlashCommand>[
        for (var i = 0; i < 600; i++) agent(i.isEven ? 'review$i' : 'cmd$i', 'does thing $i'),
      ];

      final found = searchCommands(all, 'rev');

      expect(found.length, lessThanOrEqualTo(12));
      expect(found, isNotEmpty);
      expect(found.every((c) => c.name.startsWith('review')), isTrue);
    });
  });

  group('slashSuggestions', () {
    test('app commands come first and the total stays within the limit', () {
      final all = <SlashCommand>[for (var i = 0; i < 20; i++) agent('c$i')];

      final shown = slashSuggestions(appCommands, all, '');

      expect(shown, hasLength(12));
      expect(names(shown).take(4), <String>['run', 'reload', 'restart', 'screenshot']);
      expect(shown[4].name, 'c0');
    });

    test('a section without matches is empty', () {
      final shown = slashSuggestions(appCommands, <SlashCommand>[agent('compact')], 'comp');
      expect(names(shown), <String>['compact']);
    });
  });

  group('slashQueryAt', () {
    test('only a slash at the start with no whitespace after it is a query', () {
      expect(slashQueryAt('/', 1), '');
      expect(slashQueryAt('/comp', 5), 'comp');
      expect(slashQueryAt('/comp', 3), 'co');
      expect(slashQueryAt('/compact ', 9), isNull);
      expect(slashQueryAt('see /comp', 9), isNull);
      expect(slashQueryAt(' /comp', 6), isNull);
      expect(slashQueryAt('hello', 5), isNull);
      expect(slashQueryAt('', 0), isNull);
      expect(slashQueryAt('/a\nb', 4), isNull);
      expect(slashQueryAt('/a', 9), isNull);
      expect(slashQueryAt('/a', -1), isNull);
    });
  });
}
