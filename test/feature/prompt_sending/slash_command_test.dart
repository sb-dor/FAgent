import 'package:flutter_code_agent/src/common/localization/generated/generated_localization_en.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final localization = GeneratedLocalizationEn();
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

  group('appCommandsFor', () {
    List<String> enabled(RunMentions? run) => [
      for (final c in appCommandsFor(run, localization))
        if (c.enabled) c.name,
    ];

    test('are run, reload, restart and screenshot, all from the app', () {
      final commands = appCommandsFor(null, localization);

      expect(names(commands), <String>['run', 'reload', 'restart', 'screenshot']);
      expect(commands.every((c) => c.source == SlashSource.app), isTrue);
    });

    test('without a run all are disabled; run asks for a device, the others for a run', () {
      final commands = appCommandsFor(null, localization);

      expect(commands.every((c) => !c.enabled), isTrue);
      expect(commands.first.hint, 'Choose a device');
      expect(commands.skip(1).map((c) => c.hint), everyElement('App is not running'));
    });

    test(
      'run is on with canStart, reload and restart with canReload, screenshot with canScreenshot',
      () {
        expect(enabled(const RunMentions(canStart: true)), <String>['run']);
        expect(enabled(const RunMentions(canReload: true)), <String>['reload', 'restart']);
        expect(enabled(const RunMentions(canScreenshot: true)), <String>['screenshot']);
        expect(enabled(const RunMentions(canReload: true, canScreenshot: true)), <String>[
          'reload',
          'restart',
          'screenshot',
        ]);
      },
    );

    test('outside a debug run reload, restart and screenshot ask for a debug run', () {
      final commands = appCommandsFor(const RunMentions(isRunning: true), localization);

      expect(commands.skip(1).every((c) => !c.enabled), isTrue);
      expect(commands.skip(1).map((c) => c.hint), everyElement('Works in a debug run'));
    });

    test('a command that is on has no hint', () {
      final commands = appCommandsFor(const RunMentions(canStart: true), localization);

      expect(commands.first.hint, isNull);
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

      final shown = slashSuggestions(appCommandsFor(null, localization), all, '');

      expect(shown, hasLength(12));
      expect(names(shown).take(4), <String>['run', 'reload', 'restart', 'screenshot']);
      expect(shown[4].name, 'c0');
    });

    test('a section without matches is empty', () {
      final shown = slashSuggestions(appCommandsFor(null, localization), <SlashCommand>[
        agent('compact'),
      ], 'comp');
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
