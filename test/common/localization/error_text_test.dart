import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_code_agent/src/common/acp/agent_exceptions.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/localization/error_text.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_start_arguments.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/models/permission_rules_exceptions.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lcl = lookupGeneratedLocalization(const Locale('en'));

  test('a file error names the path and the OS reason', () {
    final text = errorText(
      lcl,
      const FileSystemException('Cannot open', '/p/a.txt', OSError('Permission denied', 13)),
    );
    expect(text, contains('/p/a.txt'));
    expect(text, contains('Permission denied'));
    expect(text, isNot(contains('FileSystemException')));
  });

  test('a process that cannot start names the command', () {
    expect(errorText(lcl, const ProcessException('npx', <String>[])), contains('npx'));
  });

  test('a failed flutter doctor shows what it printed', () {
    expect(errorText(lcl, const FlutterDoctorFailedException(1, 'no git')), contains('no git'));
  });

  test('a stopped agent has its own sentence', () {
    expect(errorText(lcl, const AgentStoppedException()), lcl.errorAgentStopped);
  });

  test('a timeout has its own sentence', () {
    expect(errorText(lcl, TimeoutException('x')), lcl.errorTimeout);
  });

  test('Flutter not found, a busy chat and a busy project have their own sentences', () {
    expect(errorText(lcl, const FlutterNotFoundException()), lcl.errorFlutterNotFound);
    expect(errorText(lcl, const ChatBusyException(1)), lcl.errorChatBusy);
    expect(errorText(lcl, const ProjectBusyException(1)), lcl.errorProjectBusy);
  });

  group('every expected failure has its own sentence', () {
    final ru = lookupGeneratedLocalization(const Locale('ru'));
    final errors = <Object>[
      const OpenPathRefusedException('/nowhere'),
      const InvalidMcpServerException(McpServerProblem.invalidName),
      const McpJsonException('bad json'),
      const ReadOnlyKnowledgeException('rule:dart'),
      const InvalidKnowledgeNameException('Bad Name'),
      const KnowledgeExistsException('skill:x'),
      const KnowledgeNotFoundException('skill:x'),
      const InvalidKnowledgeException('no SKILL.md'),
      const KnowledgeConflictException('skill:x'),
      const AgentSettingsMissingException('codex'),
      const RunConfigNotStartable.unsupported('Home', LaunchUnsupportedVariable(r'${env:HOME}')),
      const FileNotTextException('/p/a.bin'),
      const FileTooLargeException('/p/big.txt', 1),
      const FileChangedOnDiskException('/p/a.txt', null),
      const BypassNotAllowedException(),
      const PermissionRulesUnreadableException('/p/.claude/settings.local.json'),
    ];
    for (final error in errors) {
      test('${error.runtimeType}', () {
        final en = errorText(lcl, error, debug: false);
        expect(en, isNot(lcl.errorUnknown));
        expect(errorText(ru, error, debug: false), isNot(en));
      });
    }

    test('a message the user needs is in the sentence', () {
      expect(
        errorText(lcl, const McpJsonException('bad json'), debug: false),
        contains('bad json'),
      );
      expect(
        errorText(lcl, const KnowledgeExistsException('skill:x'), debug: false),
        contains('x'),
      );
      expect(
        errorText(lcl, const FileTooLargeException('/p/big.txt', 1), debug: false),
        contains('/p/big.txt'),
      );
    });
  });

  test('an unknown error is its toString in debug', () {
    expect(errorText(lcl, StateError('boom'), debug: true), contains('boom'));
  });

  test('an unknown error is a generic sentence in release', () {
    expect(errorText(lcl, StateError('boom'), debug: false), lcl.errorUnknown);
  });

  test('Russian has every key', () {
    final ru = lookupGeneratedLocalization(const Locale('ru'));
    final errors = <Object>[
      const FileSystemException('Cannot open', '/p/a.txt', OSError('Permission denied', 13)),
      const ProcessException('npx', <String>[]),
      TimeoutException('x'),
      const FlutterDoctorFailedException(1, 'x'),
      const FlutterNotFoundException(),
      const ChatBusyException(1),
      const ProjectBusyException(1),
      const AgentStoppedException(),
      StateError('boom'),
    ];
    for (final error in errors) {
      final text = errorText(ru, error, debug: false);
      expect(text, isNotEmpty);
      // A file error is "path: reason" in every language, so only its text must exist.
      if (error is! FileSystemException) expect(text, isNot(errorText(lcl, error, debug: false)));
    }
  });
}
