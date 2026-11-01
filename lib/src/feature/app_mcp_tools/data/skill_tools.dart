import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skills_for_chat.dart';
import 'package:path/path.dart' as p;

/// How many bytes of a skill file `read_skill_file` returns; a bigger file is refused.
const int skillFileLimit = 256 * 1024;

/// The skills the app serves to the agent: the built-in and the user's. The project's own skills
/// (`.claude/skills`) are the agent's to read, so they are not served.
bool _served(KnowledgeItem skill) =>
    skill.source == SkillSource.builtin || skill.source == SkillSource.user;

/// What the skill tools share: which skills a chat sees and how a name is looked up.
final class ChatSkillCatalog {
  /// Creates the catalog over the [skills] library and the chats' choices in [chatSkills].
  const ChatSkillCatalog({required this._skills, required this._chatSkills});

  final ISkillsRepository _skills;
  final IChatSkillsRepository _chatSkills;

  Future<SkillLibrary> _library(AppMcpCaller caller) =>
      _skills.watch(projectId: caller.projectId).first;

  /// The served skills that are on for the chat of [caller].
  Future<List<KnowledgeItem>> forChat(AppMcpCaller caller) async => skillsForChat(
    await _library(caller),
    await _chatSkills.current(caller.sessionId),
  ).where(_served).toList();

  /// The skill [name] when it is on for the chat of [caller], else the error to give the agent.
  Future<({KnowledgeItem? skill, AppMcpError? error})> find(
    AppMcpCaller caller,
    Object? name,
  ) async {
    if (name is! String || name.trim().isEmpty) {
      return (skill: null, error: const AppMcpError('The name argument is required'));
    }
    final wanted = name.trim();
    final library = await _library(caller);
    final skill = library.skills.where(_served).where((it) => it.name == wanted).firstOrNull;
    if (skill == null) return (skill: null, error: AppMcpError('Skill not found: $wanted'));
    final chatStates = await _chatSkills.current(caller.sessionId);
    if (!skillsForChat(library, chatStates).any((on) => on.id == skill.id)) {
      return (skill: null, error: AppMcpError('Skill $wanted is off for this chat'));
    }
    return (skill: skill, error: null);
  }
}

/// `list_skills`: the skills that are on for the chat.
final class ListSkillsTool implements AppMcpTool {
  /// Creates the tool.
  const ListSkillsTool({required this._catalog});

  final ChatSkillCatalog _catalog;

  @override
  String get name => 'list_skills';

  @override
  String get description =>
      'Lists the skills of the app that are on for this chat: name, source and when to use '
      'each. Call load_skill with a name to read one.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final skills = await _catalog.forChat(caller);
    if (skills.isEmpty) return const AppMcpText('No skills are on for this chat');
    return AppMcpText(
      skills
          .map((skill) {
            final when = skill.whenToUse;
            return '- ${skill.name} (${skill.source.name}): ${skill.description}'
                '${when == null || when.isEmpty ? '' : ' Use when: $when'}';
          })
          .join('\n'),
    );
  }
}

/// `load_skill`: the `SKILL.md` of a skill and the list of its files.
final class LoadSkillTool implements AppMcpTool {
  /// Creates the tool.
  const LoadSkillTool({required this._catalog, required this._skills});

  final ChatSkillCatalog _catalog;
  final ISkillsRepository _skills;

  @override
  String get name => 'load_skill';

  @override
  String get description =>
      'Returns the SKILL.md of a skill that is on for this chat and the list of its other '
      'files; read those with read_skill_file.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'name': {'type': 'string', 'description': 'The skill name from list_skills.'},
    },
    'required': <String>['name'],
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final (:skill, :error) = await _catalog.find(caller, arguments['name']);
    if (skill == null) return error!;
    final String text;
    try {
      text = await _skills.read(skill.id);
    } on KnowledgeNotFoundException {
      return AppMcpError('Skill not found: ${skill.name}');
    }
    return AppMcpText('$text\n\nFiles:\n${skill.files.map((file) => '- $file').join('\n')}');
  }
}

/// `read_skill_file`: one text file of a skill.
final class ReadSkillFileTool implements AppMcpTool {
  /// Creates the tool.
  const ReadSkillFileTool({required this._catalog, required this._builtin});

  final ChatSkillCatalog _catalog;
  final IBuiltinKnowledge _builtin;

  static const AppMcpError _outside = AppMcpError('Path is outside the skill');

  @override
  String get name => 'read_skill_file';

  @override
  String get description =>
      'Reads a text file of a skill that is on for this chat, for example a template listed '
      'by load_skill. The path is relative to the skill folder.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'name': {'type': 'string', 'description': 'The skill name from list_skills.'},
      'path': {'type': 'string', 'description': 'File path relative to the skill folder.'},
    },
    'required': <String>['name', 'path'],
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final (:skill, :error) = await _catalog.find(caller, arguments['name']);
    if (skill == null) return error!;
    final path = arguments['path'];
    if (path is! String || path.isEmpty) return const AppMcpError('The path argument is required');
    // Neither an absolute path nor one that climbs out of the folder, whatever it is joined to.
    final relative = p.normalize(path);
    if (p.isAbsolute(path) ||
        p.isAbsolute(relative) ||
        relative == '..' ||
        relative.startsWith('..${p.separator}') ||
        path.contains('\u0000')) {
      return _outside;
    }
    return skill.source == SkillSource.builtin
        ? _readBuiltin(skill, relative)
        : _readFile(skill, relative);
  }

  Future<AppMcpResult> _readBuiltin(KnowledgeItem skill, String relative) async {
    final key = p.posix.joinAll(<String>[skill.path, ...p.split(relative)]);
    final text = (await _builtin.load())[key];
    if (text == null) return AppMcpError('File not found: $relative');
    if (utf8.encode(text).length > skillFileLimit) return const AppMcpError('File is too large');
    return AppMcpText(text);
  }

  Future<AppMcpResult> _readFile(KnowledgeItem skill, String relative) async {
    try {
      final root = await Directory(skill.path).resolveSymbolicLinks();
      final String target;
      try {
        target = await File(p.join(skill.path, relative)).resolveSymbolicLinks();
      } on FileSystemException {
        return AppMcpError('File not found: $relative');
      }
      // A link inside the skill may point anywhere; only what it resolves to counts.
      if (!p.isWithin(root, target)) return _outside;
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.file) {
        return AppMcpError('Not a file: $relative');
      }
      final file = File(target);
      if (await file.length() > skillFileLimit) return const AppMcpError('File is too large');
      try {
        return AppMcpText(utf8.decode(await file.readAsBytes()));
      } on FormatException {
        return const AppMcpError('Not a text file');
      }
    } on FileSystemException catch (error) {
      return AppMcpError('Cannot read the file: ${error.osError?.message ?? error.message}');
    }
  }
}
