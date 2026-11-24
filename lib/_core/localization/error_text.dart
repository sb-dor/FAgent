import 'dart:async';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' show JsonRpcRequestException;
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/_core/acp/agent_connection.dart';
import 'package:flutter_code_agent/_core/acp/agent_exceptions.dart';
import 'package:flutter_code_agent/_core/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/_core/acp/agent_preflight.dart';
import 'package:flutter_code_agent/_core/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/_core/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/app_run/models/run_start_arguments.dart';
import 'package:flutter_code_agent/code_view/models/code_file.dart';
import 'package:flutter_code_agent/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/initialization/models/initialization_exception.dart';
import 'package:flutter_code_agent/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/permission_rules/models/permission_rules_exceptions.dart';
import 'package:flutter_code_agent/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/skills/models/knowledge_exceptions.dart';

/// Turns any error the app can meet into a localized sentence.
///
/// Cases go from specific to general. An unknown error is its `toString()` in debug builds, to see
/// what was missed ([debug]), and a generic sentence otherwise.
String errorText(GeneratedLocalization lcl, Object? error, {bool debug = kDebugMode}) =>
    switch (error) {
      InitializationException(:final cause) => errorText(lcl, cause, debug: debug),
      FileSystemException(:final String path, :final message, :final osError)
          when path.isNotEmpty =>
        lcl.errorFile(path, osError?.message ?? message),
      FileSystemException(:final message, :final osError) => osError?.message ?? message,
      ProcessException(:final executable, :final errorCode, :final message)
          when errorCode != 0 && message.isNotEmpty =>
        lcl.errorProcessFailed(executable, message),
      ProcessException(:final executable) => lcl.errorProcess(executable),
      TimeoutException() => lcl.errorTimeout,
      FlutterNotFoundException() => lcl.errorFlutterNotFound,
      FlutterDoctorFailedException(:final output) => lcl.errorFlutterDoctorFailed(output),
      ChatBusyException() => lcl.errorChatBusy,
      AgentStoppedException() => lcl.errorAgentStopped,
      AgentPreflightException(:final message, hint: final String hint) =>
        lcl.errorAgentPreflightHint(message, hint),
      AgentPreflightException(:final message) => lcl.errorAgentPreflight(message),
      AgentStartException(:final message) => lcl.errorAgentStart(message),
      JsonRpcRequestException(:final message) => lcl.errorAgentRequest(message),
      ProjectBusyException() => lcl.errorProjectBusy,
      OpenPathRefusedException(:final path) => lcl.errorOpenPathRefused(path),
      InvalidMcpServerException() => lcl.errorInvalidMcpServer,
      McpJsonException(:final message) => lcl.errorMcpJson(message),
      ReadOnlyKnowledgeException() => lcl.errorReadOnlyKnowledge,
      InvalidKnowledgeNameException(:final name) => lcl.errorInvalidKnowledgeName(name),
      KnowledgeExistsException(:final id) => lcl.errorKnowledgeExists(id),
      KnowledgeNotFoundException(:final id) => lcl.errorKnowledgeNotFound(id),
      InvalidKnowledgeException(:final message) => lcl.errorInvalidKnowledge(message),
      KnowledgeConflictException(:final id) => lcl.errorKnowledgeConflict(id),
      AgentSettingsMissingException() => lcl.errorAgentSettingsMissing,
      RunConfigNotStartable(:final name) => lcl.errorRunConfigNotStartable(name),
      FileNotTextException(:final path) => lcl.errorFileNotText(path),
      FileTooLargeException(:final path) => lcl.errorFileTooLarge(path),
      FileChangedOnDiskException(:final path) => lcl.errorFileChangedOnDisk(path),
      BypassNotAllowedException() => lcl.errorBypassNotAllowed,
      PermissionRulesUnreadableException(:final path) => lcl.errorPermissionRulesUnreadable(path),
      _ => debug ? '$error' : lcl.errorUnknown,
    };
