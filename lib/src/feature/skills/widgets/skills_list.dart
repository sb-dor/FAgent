import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_list_tile.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_add_menu.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';
import 'package:l/l.dart';

/// {@template skills_list}
/// The middle column of the Skills screen: a search field over the items of the open section that
/// pass the source filter and the search.
/// {@endtemplate}
class SkillsList extends StatefulWidget {
  /// {@macro skills_list}
  const SkillsList({super.key});

  @override
  State<SkillsList> createState() => _SkillsListState();
}

class _SkillsListState extends State<SkillsList> {
  late final SkillsConfigWidgetState _scope = SkillsConfigInhWidget.of(context);
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = _scope.view.query;
    _scope.view.addListener(_followQuery);
  }

  @override
  void dispose() {
    _scope.view.removeListener(_followQuery);
    _search.dispose();
    super.dispose();
  }

  /// The query changes from outside the field too, e.g. when the screen opens on an item.
  void _followQuery() {
    if (_search.text != _scope.view.query) _search.text = _scope.view.query;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _search,
                      onChanged: _scope.view.setQuery,
                      style: style,
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: localization.skillsSearch,
                        hintStyle: style.copyWith(color: colors.muted),
                        prefixIcon: Icon(Icons.search, size: 16, color: colors.muted),
                        prefixIconConstraints: const BoxConstraints.tightFor(width: 32),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: _border(colors.border),
                        enabledBorder: _border(colors.border),
                        focusedBorder: _border(colors.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const SkillsAddMenu(),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_scope.library, _scope.view]),
            builder: (context, _) => switch (_scope.library.state) {
              SkillLibrary$IdleState() || SkillLibrary$LoadingState() => const Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              SkillLibrary$FailedState() => EmptyState(
                icon: Icons.error_outline,
                title: localization.somethingWentWrong,
              ),
              SkillLibrary$LoadedState() => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _items(context)),
                  ValueListenableBuilder<Set<int>>(
                    valueListenable: _scope.projectsWithoutRules,
                    builder: (context, without, _) => switch (_scope.project) {
                      final project? when without.contains(project.id) => Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextButton.icon(
                            key: const ValueKey<String>('skills-add-project-rules'),
                            icon: const Icon(Icons.rule_folder_outlined, size: 16),
                            label: Text(localization.projectRulesButton),
                            onPressed: _scope.offerProjectRules,
                          ),
                        ),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                  _RulesNote(
                    text: localization.skillsRulesNote,
                    source: _scope.view.kind == KnowledgeKind.rule ? const _RulesSource() : null,
                  ),
                ],
              ),
            },
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.medium),
    borderSide: BorderSide(color: color),
  );

  Widget _items(BuildContext context) {
    final view = _scope.view;
    final items = view.visibleItems(_scope.library.library);
    if (items.isEmpty) {
      return EmptyState(icon: Icons.search_off, title: Localization.of(context).skillsNothingFound);
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return SkillListTile(
          item: item,
          selected: item.id == view.selectedId,
          onTap: () => _scope.select(item.id),
          onToggle: (enabled) =>
              _scope.actions.setEnabled(item.id, enabled: enabled, projectId: view.projectId),
        );
      },
    );
  }
}

/// Under the list: when a changed rule reaches the chats.
class _RulesNote extends StatelessWidget {
  const _RulesNote({required this.text, this.source});

  final String text;

  /// Shown under [text] in the same footer: where the built-in rules come from.
  final Widget? source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(text, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted)),
            if (source case final source?) ...<Widget>[const SizedBox(height: 6), source],
          ],
        ),
      ),
    );
  }
}

/// In the rules footer: where the built-in rules come from, with a link to the community chat.
class _RulesSource extends StatelessWidget {
  const _RulesSource();

  /// The Telegram chat whose discussions the built-in rules are collected from.
  static final Uri chat = Uri.parse('https://t.me/ru_dart');

  /// The chat's name as Telegram shows it.
  static const String chatName = 'Flutter 🎯 Dart';

  Future<void> _open(BuildContext context) async {
    try {
      await Dependencies.of(context).openUrl(chat);
    } on Object catch (error, stackTrace) {
      l.w('Could not open $chat: $error', stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          Localization.of(context).skillsRulesSource,
          style: style.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 2),
        Semantics(
          link: true,
          linkUrl: chat,
          child: Tooltip(
            message: chat.toString(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey<String>('skills-rules-source-link'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(context),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: <Widget>[
                    Icon(Icons.forum_outlined, size: 14, color: colors.accent),
                    Text(
                      chatName,
                      style: style.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.accent,
                      ),
                    ),
                    Text('t.me/ru_dart', style: style.copyWith(color: colors.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
