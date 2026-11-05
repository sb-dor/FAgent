# Rules in the Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the built-in skills into their rules, stop sending built-in rules in the system prompt, and give projects `docs/rules/*.md` plus `AGENTS.md`/`CLAUDE.md` pointers: automatically for new projects, through a once-per-project dialog for others.

**Architecture:**
- **Content:** the rule files in `assets/knowledge/rules/` absorb the skills, and `assets/knowledge/skills/` goes away.
- **Prompt:** `promptRules` skips the built-in rules.
- **The new `feature/project_rules`:**
  - pure text helpers for `AGENTS.md` and `CLAUDE.md`;
  - an `IProjectRulesRepository` that writes the files and remembers that the offer was made (new column `projects.rules_offered`, schema 12);
  - a controller and dialog that the workspace scope shows when a project is selected.
- **Project creation:** gets a `rules` step before the first commit.

**Tech Stack:** Flutter macOS, drift (schema 12, `drift_dev make-migrations`), control, freezed, gen-l10n en/ru.

**Spec:** `docs/superpowers/specs/2026-11-05-rules-in-project-design.md` (Russian).

## Global Constraints

- Follow CLAUDE.md and `docs/AI_INSTRUCTIONS.md`:
  - colors only from `context.colors`;
  - repositories take services through the constructor;
  - new app-wide services are added as initialization steps.
- No new dependency.
- The merge table (spec §1):
  - `feature-architecture` → `architecture`;
  - `controller-patterns` and `paginated-controller` → `controllers`;
  - `dependency-injection` → `dependencies`;
  - `repository-streams` and `drift-migration` → `repositories`;
  - `pub-freshness` → `package-freshness`;
  - `widget-test` → `widgets`.
  - `generated-files` and `localization` stay as they are.
- Code examples go inside the rules as fenced `dart` blocks whose first line is `// file: <name>.dart`.
- Project files:
  - `docs/rules/<name>.md` holds the rule text without its frontmatter.
  - `AGENTS.md` gets a section between `<!-- flutter_code_agent:rules -->` and `<!-- /flutter_code_agent:rules -->`. It opens with "Before changing code, read the rules in `docs/rules/` that apply to the task. They are this project's conventions:", then one line per rule: "- `docs/rules/<name>.md` — <description>".
  - `CLAUDE.md` gets an `@AGENTS.md` line, only when no such line exists yet.
- Copy, en / ru:
  - `projectRulesTitle`: "Add the project rules?" / «Добавить правила в проект?»;
  - `projectRulesExplain`: "Agents will read them from docs/rules, so they live and change with the project." / «Агент будет читать их из docs/rules — так они видны в проекте и меняются вместе с ним.»;
  - `projectRulesAdd`: "Add" / «Добавить»;
  - `projectRulesNotNow`: "Not now" / «Не сейчас»;
  - `projectRulesButton`: "Add rules to project" / «Добавить правила в проект»;
  - `creationStepRules`: "Project rules" / «Правила проекта»;
  - `skillsBuiltinRuleHint`: "Added to new projects" / «Добавляется в новые проекты»;
  - `skillsRulesNote`: "Your rules apply to new and reopened chats; built-in rules are added to projects in docs/rules" / «Ваши правила применятся к новым и заново открытым чатам; встроенные добавляются в проект в docs/rules».
- Nothing is committed in the user's project except by the creation's own first commit.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Writing twice.** Adding rules twice to one project leaves one marked section in `AGENTS.md` and one `@AGENTS.md` in `CLAUDE.md`. The second run replaces the section rather than appending a copy (Task 4).
2. **Someone else's `AGENTS.md`.** An existing `AGENTS.md` with CRLF line breaks and no trailing newline keeps its own text byte for byte; the section goes after it on its own lines (Task 4).
3. **`CLAUDE.md` already pointing at it.** A `CLAUDE.md` that already has `@AGENTS.md`, also with spaces around it or as `@./AGENTS.md`, gets no second line (Task 4).
4. **A failed write.** If writing fails (a read-only folder), the user sees the error, `rules_offered` stays `false`, and the offer comes again (Task 6).
5. **Switching projects fast.** Switching between two projects without `docs/rules` shows one dialog at a time, for the project that is selected when it opens. An answer for one project is never written to the other (Task 6).

---

### Task 1: Merge the skills into the rules

**Files:**
- Modify: `assets/knowledge/rules/{architecture,controllers,dependencies,repositories,package-freshness,widgets}.md`
- Delete: `assets/knowledge/skills/` (everything)
- Modify: `pubspec.yaml` (drop every `assets/knowledge/skills/...` line)
- Test:
  - `test/feature/skills/builtin_knowledge_content_test.dart`
  - `test/feature/skills/builtin_knowledge_test.dart`
  - any test that reads the real built-in skills, found with `grep -rln "assets/knowledge/skills\|IBuiltinKnowledge\|AssetBuiltinKnowledge" test`

**Interfaces:**
- Produces: 8 rule files with frontmatter `name` and a new one-line `description`, and no `SKILL.md` anywhere under `assets/knowledge/`.

- [ ] **Step 1:** Before deleting anything, record the `## ` headings of each `SKILL.md` and the file names of each `templates/` folder. They're the expectations of the tests below.
- [ ] **Step 2: Rewrite the content tests:**
  - `'the built-in rules are the expected set'`: unchanged.
  - `'no built-in skills ship'`: `assets/knowledge/skills` doesn't exist, and `pubspec.yaml` doesn't contain `assets/knowledge/skills`.
  - `'every merged rule keeps the sections of its skills'`: for each pair in the merge table, every recorded heading of the skill appears in the rule, as a `## ` or `### ` heading.
  - `'the code examples compile'`: the old template test, but its sources are the `dart` blocks of all rules whose first line is `// file: <name>.dart`, each written to `<name>.dart` in the fixture. The set of names equals the recorded template names.
  - `'every rule has frontmatter with its name and a description'`: unchanged.
  - `'no built-in file carries this repository's own overrides'`: unchanged.
  - Removed: the skill frontmatter test, `'every skill mentions the templates it ships'`, and `'the rules stay within the system prompt budget'`, since rules no longer go into the prompt.
- [ ] **Step 3:** Run `flutter test test/feature/skills/builtin_knowledge_content_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 4: Merge each skill into its rule:**
  - Turn it into one guide with sections. Keep the rule's short list as an opening "Rules" section, then the skill's sections. Don't repeat a point already stated.
  - Inline every template as a `// file:` block.
  - Remove any reference to a skill by name (for example in `dependencies.md` and `repositories.md`).
  - Write a new one-line `description` for each rule.
  - Delete `assets/knowledge/skills/` and its `pubspec.yaml` lines.
- [ ] **Step 5:** Run `flutter pub get && flutter test test/feature/skills`, then the files found by the grep in **Files**. Expected: PASS. Update every test that expected a real built-in skill to expect none.
- [ ] **Step 6:** Commit with `feat(knowledge): the built-in skills merge into their rules`.

### Task 2: Built-in rules leave the system prompt

**Files:**
- Modify: `lib/src/feature/session_context/data/session_context_repository.dart` (`promptRules`)
- Test: `test/feature/session_context/session_context_repository_test.dart`

**Interfaces:**
- Produces: `promptRules` returns only enabled rules whose `source != SkillSource.builtin`. The rest is as today: `AGENTS.md` is still left out, and for Claude so are its `.claude/rules`.

- [ ] **Step 1:** Write the failing test `'built-in rules are not in the prompt; own rules are'`. A library holds one enabled built-in rule and one enabled user rule; `promptRules` returns only the user rule, and the built `systemPrompt` contains the user rule's text and not the built-in one's.
- [ ] **Step 2:** Run the test file. Expected: FAIL.
- [ ] **Step 3:** Implement. Update the doc comment of `promptRules`.
- [ ] **Step 4:** Run `flutter test test/feature/session_context`. Expected: PASS. Existing tests that expected built-in rules in the prompt now expect them absent.
- [ ] **Step 5:** Commit with `feat(session_context): built-in rules are no longer sent in the prompt`.

### Task 3: Remember that the rules were offered (schema 12)

**Files:**
- Modify:
  - `lib/src/common/database/tables/projects_table.dart`
  - `lib/src/common/database/database.dart` (`schemaVersion: 12`, `from11To12`)
  - `lib/src/feature/projects/models/project.dart`
  - `lib/src/feature/projects/data/projects_repository.dart`
- Generated: `drift_schemas/drift_schema_v12.json`, `lib/src/common/database/database.steps.dart` and `test/generated_migrations/schema_v12.dart`, all via `dart run drift_dev make-migrations`
- Test: `test/common/database/migration_test.dart`, `test/feature/projects/` (the repository test)

**Interfaces:**
- Produces:
  - the column `BoolColumn get rulesOffered => boolean().withDefault(const Constant(false))();`;
  - `Project.rulesOffered` (`bool`);
  - `Future<void> IProjectsRepository.markRulesOffered(int projectId)`.

- [ ] **Step 1:** Write the failing tests:
  - `'v11 → v12 adds rules_offered false and keeps projects'`, in the style of the v10 → v11 test;
  - `'markRulesOffered sets rulesOffered'`, in the projects repository test.
- [ ] **Step 2:** Run both. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - add the column and bump the schema;
  - run `dart run drift_dev make-migrations`;
  - write `from11To12` with `m.addColumn(schema.projects, schema.projects.rulesOffered)`;
  - add the model field (`fromRow`, `==`, `hashCode`) and the repository method;
  - run `dart run build_runner build -d`.
- [ ] **Step 4:** Run the migration test and `flutter test test/feature/projects`. Expected: PASS.
- [ ] **Step 5:** Commit with `feat(projects): remember that the project rules were offered`.

### Task 4: Writing the rules into a project

**Files:**
- Create:
  - `lib/src/feature/project_rules/models/project_rule.dart`
  - `lib/src/feature/project_rules/data/project_rules_files.dart`
  - `lib/src/feature/project_rules/data/project_rules_repository.dart`
- Modify: `lib/src/feature/initialization/data/initialize_dependencies.dart`, `lib/src/feature/initialization/models/dependencies.dart`, `test/support/test_app.dart`
- Test: `test/feature/project_rules/project_rules_files_test.dart`, `test/feature/project_rules/project_rules_repository_test.dart`

**Interfaces:**
- Consumes:
  - `ISkillsRepository.watch()` (its first value) and `ISkillsRepository.read(id)`;
  - `parseFrontmatter` (`feature/skills/data/frontmatter.dart`);
  - Task 3's `IProjectsRepository.markRulesOffered`.
- Produces:
  - `final class ProjectRule { const ProjectRule({required String id, required String name, required String description, required bool enabled}); }`, a value class.
  - `String agentsMdWithRules(String? existing, List<ProjectRule> rules)`:
    - with no existing text, it returns the section alone;
    - otherwise it replaces the text between the markers, or appends `\n\n` plus the section;
    - it keeps the file's own line break (`\r\n` when the file uses it).
  - `String claudeMdWithAgents(String? existing)`. It leaves the text unchanged when a line matches `^\s*@(\./)?AGENTS\.md\s*$`, and otherwise appends `@AGENTS.md` on a line of its own.
  - `abstract interface class IProjectRulesRepository`:
    - `Future<bool> hasRules(String projectRoot)`: whether `docs/rules` exists as a directory;
    - `Future<List<ProjectRule>> builtinRules()`: the built-in rules in library order;
    - `Future<void> write(String projectRoot, List<ProjectRule> rules)`: throws `FileSystemException` on failure;
    - `Future<void> markOffered(int projectId)`.
  - `ProjectRulesRepositoryImpl({required ISkillsRepository skills, required IProjectsRepository projects})`.
  - `Dependencies.projectRulesRepository`, created in a new init step `'Create project rules repository'` after the skills repository.

- [ ] **Step 1: Write the failing tests:**
  - `project_rules_files_test`:
    - `'a new AGENTS.md is the section alone'`: the exact text from **Global Constraints** for two rules.
    - `'existing text stays and the section is appended once'`: running `agentsMdWithRules` twice gives a result with exactly one opening marker.
    - `'the section is replaced, not duplicated'`: with other rules, the old list is gone.
    - `'a CRLF file keeps CRLF and its own bytes'`.
    - `'CLAUDE.md gets @AGENTS.md once'`: the input `"# Notes"` gives `"# Notes\n\n@AGENTS.md\n"`.
    - `'an existing @AGENTS.md, spaced or as @./AGENTS.md, adds nothing'`.
  - `project_rules_repository_test`, with a temp dir and a fake skills repository holding two built-in rules and one user rule:
    - `'builtinRules lists the built-in rules only'`;
    - `'write puts each rule in docs/rules without frontmatter and updates AGENTS.md and CLAUDE.md'`;
    - `'hasRules is true once docs/rules exists'`;
    - `'a read-only folder throws'`: `chmod 555`, then reset in tear-down.
- [ ] **Step 2:** Run both. Expected: FAIL.
- [ ] **Step 3:** Implement. `write` creates `docs/rules`, writes each body, then reads, transforms and writes `AGENTS.md` and `CLAUDE.md`. Wire the init step and the test dependencies.
- [ ] **Step 4:** Run `flutter test test/feature/project_rules` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(project_rules): write the rules, AGENTS.md and CLAUDE.md into a project`.

### Task 5: New projects get the rules

**Files:**
- Modify:
  - `lib/src/feature/project_creation/models/creation_step.dart` (`CreationStepKind.rules`, before `firstCommit`, in `creationStepsFor` for both templates)
  - `lib/src/feature/project_creation/data/project_creation_repository_impl.dart`
  - the creation step labels widget (find it with `grep -rn "CreationStepKind.firstCommit" lib/src/feature/project_creation/widgets`)
  - `initialize_dependencies.dart`
  - arb files: `creationStepRules`
- Test: `test/feature/project_creation/project_creation_repository_impl_test.dart`, `creation_progress_test.dart`

**Interfaces:**
- Consumes: Task 4's `IProjectRulesRepository` (`builtinRules`, `write`, `markOffered`).
- Produces: `ProjectCreationRepositoryImpl(..., required IProjectRulesRepository projectRules)`.
  - The `rules` step writes the enabled built-in rules, and writes nothing when none is enabled.
  - Once the project is added, `markOffered(id)` runs.

- [ ] **Step 1: Write the failing tests:**
  - `'the rules step writes docs/rules, AGENTS.md and CLAUDE.md before the first commit'`: the fake process records `git add -A` after the files exist.
  - `'no enabled rule writes nothing'`.
  - `'a created project is marked as offered'`.
  - `'the progress lists Project rules'`, in `creation_progress_test`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/feature/project_creation`. Expected: PASS.
- [ ] **Step 5:** Commit with `feat(project_creation): new projects get docs/rules, AGENTS.md and CLAUDE.md`.

### Task 6: The offer dialog and the Rules button

**Files:**
- Create:
  - `lib/src/feature/project_rules/controller/project_rules_controller.dart` (freezed state)
  - `lib/src/feature/project_rules/widgets/project_rules_dialog.dart`
- Modify:
  - `lib/src/feature/workspace/widgets/workspace_config_widget.dart`
  - `lib/src/feature/skills/widgets/skills_list.dart`
  - the skills widget with a rule's switch
  - arb files: the `projectRules*`, `skillsBuiltinRuleHint` and `skillsRulesNote` copy from **Global Constraints**
- Test:
  - `test/feature/project_rules/project_rules_controller_test.dart`
  - `test/feature/project_rules/project_rules_dialog_test.dart`
  - `test/feature/workspace/workspace_project_rules_test.dart`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces:
  - `ProjectRulesState`:
    - `idle()`;
    - `offer({required int projectId, required String root, required List<ProjectRule> rules})`;
    - `writing()`;
    - `written({required int projectId})`;
    - `failed({required Object error})`.
  - `ProjectRulesController({required IProjectRulesRepository repository})`, using a sequential handler:
    - `check(Project project)`: offers when `!project.rulesOffered && !await hasRules(project.path)`;
    - `offer(Project project)`: offers regardless of `rulesOffered` (used by the button);
    - `add(int projectId, String root, List<ProjectRule> chosen)`: writes, then `markOffered`, then `written`; on failure it moves to `failed` and leaves `rulesOffered` as it is;
    - `dismiss(int projectId)`: `markOffered`, then `idle`.
  - `Future<List<ProjectRule>?> ProjectRulesDialog.show(BuildContext context, List<ProjectRule> rules)`:
    - one row per rule, with a `CheckboxListTile`, the name as title and the description as subtitle;
    - initially checked when `rule.enabled`;
    - **Add** is disabled while nothing is checked;
    - it returns the checked rules, or `null` for **Not now**.
  - The workspace scope:
    - It owns the controller.
    - It calls `check` when the selected project changes.
    - On `offer`, it shows the dialog only if that project is still selected, and only one dialog at a time.
    - **Add** calls `add` and **Not now** calls `dismiss`.
    - `failed` shows the error with the existing `_showError`.
  - `skills_list.dart`: when the selected project has no `docs/rules`, a `TextButton` labelled `projectRulesButton` above the rules note calls `offer`.
  - The switch of a built-in rule shows `skillsBuiltinRuleHint` as its hint. Find the switch with `grep -rn "setEnabled" lib/src/feature/skills/widgets`.

- [ ] **Step 1: Write the failing tests:**
  - controller:
    - `'check offers a project without docs/rules once'`;
    - `'check skips a project with docs/rules or already offered'`;
    - `'add writes and marks offered'`;
    - `'a failed write is failed and not marked'`;
    - `'dismiss marks offered'`.
  - dialog:
    - `'enabled rules start checked; unchecking all disables Add'`;
    - `'Add returns the checked rules'`;
    - `'Not now returns null'`;
    - `'the dialog fits at 900×600 in en and ru, light and dark'`.
  - workspace:
    - `'selecting a project without docs/rules shows the dialog once'`;
    - `'Add writes the chosen rules into the project'`;
    - `'switching projects while it loads offers only the selected one'`;
    - `'the Rules section shows Add rules to project for such a project'`;
    - `'a built-in rule's switch says Added to new projects'`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. Run `flutter pub get` and `dart run build_runner build -d`.
- [ ] **Step 4:** Run `flutter test test/feature/project_rules test/feature/workspace test/feature/skills` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(project_rules): offer the rules to projects without docs/rules`.

### Task 7: Docs and the full suite

**Files:**
- Modify: `docs/PLAN.md`. Under M3, add a line saying built-in rules are written to the project (`docs/rules`, `AGENTS.md`, `CLAUDE.md`) and no longer go into the system prompt, with a link to the spec.

- [ ] **Step 1:** Edit `docs/PLAN.md`.
- [ ] **Step 2:** Run `flutter analyze` and the full `flutter test` in the background. Expected: no issues, all tests pass.
- [ ] **Step 3:** Commit with `docs: rules live in the project`.
