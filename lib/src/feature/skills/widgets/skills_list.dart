import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_list_tile.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

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
              SkillLibrary$LoadedState() => _items(context),
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
          onTap: () => view.select(item.id),
          onToggle: (enabled) =>
              _scope.actions.setEnabled(item.id, enabled: enabled, projectId: view.projectId),
        );
      },
    );
  }
}
