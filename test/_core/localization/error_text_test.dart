import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' show JsonRpcRequestException;
import 'package:flutter_code_agent/_core/acp/agent_connection.dart';
import 'package:flutter_code_agent/_core/acp/agent_exceptions.dart';
import 'package:flutter_code_agent/_core/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/_core/acp/agent_preflight.dart';
import 'package:flutter_code_agent/_core/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/_core/localization/error_text.dart';
import 'package:flutter_code_agent/_core/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/_core/utils/expected_exception.dart';
import 'package:flutter_code_agent/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/app_run/models/run_start_arguments.dart';
import 'package:flutter_code_agent/code_view/models/code_file.dart';
import 'package:flutter_code_agent/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/permission_rules/models/permission_rules_exceptions.dart';
import 'package:flutter_code_agent/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/skills/models/knowledge_exceptions.dart';
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

  test('a process that started and failed shows what it printed', () {
    final text = errorText(
      lcl,
      const ProcessException('claude', <String>['auth', 'logout'], 'not signed in', 1),
      debug: false,
    );
    expect(text, contains('not signed in'));
    expect(text, isNot(lcl.errorProcess('claude')));
  });

  group('agent errors', () {
    test('a preflight failure shows its message and its hint', () {
      final text = errorText(
        lcl,
        const AgentPreflightException('Node.js 20+ is required.', hint: 'Install Node.js 20'),
        debug: false,
      );
      expect(text, contains('Node.js 20+ is required.'));
      expect(text, contains('Install Node.js 20'));
      expect(text, isNot(contains('AgentPreflightException')));
    });

    test('a preflight failure without a hint shows its message', () {
      final text = errorText(lcl, const AgentPreflightException('no claude'), debug: false);
      expect(text, contains('no claude'));
      expect(text, isNot(contains('AgentPreflightException')));
    });

    test('a preflight failure is expected, not a crash', () {
      expect(const AgentPreflightException('x'), isA<ExpectedException>());
    });

    test('a start failure shows its message', () {
      final text = errorText(lcl, const AgentStartException('Claude failed'), debug: false);
      expect(text, contains('Claude failed'));
      expect(text, isNot(contains('AgentStartException')));
    });

    test('a failed agent request shows its message', () {
      final text = errorText(lcl, JsonRpcRequestException.authenticationRequired(), debug: false);
      expect(text, contains('Authentication required'));
      expect(text, isNot(contains('JsonRpcRequestException')));
    });
  });

  test('a failed flutter doctor shows what it printed', () {
    expect(errorText(lcl, const FlutterDoctorFailedException(1, 'no git')), contains('no git'));
  });

  test('a stopped agent has its own sentence', () {
    expect(errorText(lcl, const AgentStoppedException()), lcl.errorAgentStopped);
  });

  test('a timeout has its own sentence', () {
    expect(errorText(lcl, TimeoutException('x')), lcl.errorTimeout);
    expect(
      errorText(lcl, const FlutterDoctorTimeoutException(Duration(minutes: 2))),
      lcl.errorTimeout,
    );
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
      const AgentPreflightException('no node', hint: 'install node'),
      const AgentPreflightException('no node'),
      const AgentStartException('failed'),
      JsonRpcRequestException.internalError(),
      const ProcessException('claude', <String>[], 'not signed in', 1),
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
