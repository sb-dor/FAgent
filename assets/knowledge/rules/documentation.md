---
name: documentation
description: "What goes into docs/*.md and READMEs, docs updated with the code, agent instructions with a table of docs, checkable acceptance criteria, and plans in self-contained steps."
---

# Documentation

## Rules

- Write down what the code cannot say: why it is done this way, what was tried and rejected,
  links (the design frame, the spec, the ticket), traps and platform bugs worked around. Never a
  retelling of the code in prose: it drifts from the code with the next change, and then misleads
  whoever reads it, a person or an agent.
- A pull request that makes a document untrue corrects it in the same pull request, and the review
  checks that. See "Docs change with the code".
- A pull request that changes what users see, or what developers must know, adds its entry to
  `CHANGELOG.md` under `[Unreleased]` (see "Changelog" in `docs/rules/configuration.md`).
- A feature gets a `README.md` next to its code only when something about it is not obvious from
  the code: a protocol, an order that must be kept, a workaround. A plain list or form feature gets
  none; the code says it.
- Keep documents that change at different speeds apart. Decisions and architecture change
  rarely and stay in `docs/`; plans, progress and to-do lists change every day and live in issues
  and pull requests, or in one roadmap whose steps are ticked off when they are accepted. Not in
  a file an agent rewrites after every step.
- Every task starts as an issue (or a task file) with its acceptance criteria, and its pull request
  is reviewed against them. See "A task".
- Large work is planned, split into steps that can each be accepted, and done step by step, with
  each step reviewed. Not handed to an agent in a loop until something passes. Each step is
  written so it can start a fresh agent session. See "A plan".
- Agent instructions (`CLAUDE.md`, `AGENTS.md`) are short and point to `docs/rules/` and `docs/`
  with a table from topic to file, and tell the agent to read the doc of an area before changing
  it. See "Agent instructions". A skill is worth having only for a kind of task that comes up
  often and needs real instructions; similar ones are merged into one. Every skill's name and
  description sit in the agent's prompt all the time, so a pile of skills is noise in every
  conversation.

## Docs change with the code

Building a step teaches what the plan did not know: a library behaves differently than expected,
an order turns out to matter, a decision has an edge case that needs another approach. Write that
into the document it concerns, in the same pull request as the code:

- What stays only in the code is invisible to the next agent session. The agent reads the doc,
  trusts it, and builds on what is no longer true.
- The change is usually small: a paragraph added, a sentence corrected, a section removed.
- The review checks the docs like an acceptance criterion: does anything the pull request touches
  now say something false?
- After the merge, read the next planned steps again. If what was learned changes them, change
  them now, while it is fresh.
- The agent instructions carry this as a standing instruction (see "Agent instructions"), so
  every session is reminded.

## Agent instructions

`CLAUDE.md` or `AGENTS.md` is loaded into every session. It holds what every session needs and
points to the rest:

- What the project is, in one or two sentences.
- The commands: get dependencies, generate code, format, analyze, test, run.
- The structure: what each top folder or package is for.
- The project's own rules and what is off limits (a pinned dependency, a folder nobody edits, a
  rule of `docs/rules/` the project does differently), and what tests it expects.
- A table from topic to file, covering `docs/rules/` and the project's own `docs/`, so the agent
  knows where to look:

  | Topic | File |
  |---|---|
  | Layers, features, repositories | `docs/rules/architecture.md` |
  | Offline sync and conflict handling | `docs/sync.md` |
  | Payment flow and its states | `docs/payments.md` |

- Standing instructions:
  - Before changing an area, read its doc from the table. Explore the source only when the doc
    does not answer the question.
  - If a doc was missing something or is out of date, correct it before finishing the task.

The detail stays in the docs. An instruction file that grows into a manual costs context in every
session and goes stale like any other copy.

## A plan

Large work is a sequence of steps, each one done, reviewed and accepted before the next:

- Each step is self-contained: its description, its acceptance criteria and links to the docs it
  needs, so it can be pasted into a fresh agent session as the whole brief. Nothing in it depends
  on an earlier conversation.
- A step is small enough to finish and review in one pull request.
- A document of goals (what the project should become) is not a plan: it has no order and no
  criteria. The plan holds the ordered steps.

## A task

An issue that an agent (or a colleague) can build from without asking:

- **Context**: what and why, the parent issue, what is still open and does not block this part.
- **Design**: the link to the exact frame, and the numbers read off it: sizes, spacing, radii,
  each colour mapped to the palette's token. A colour or size the design system does not have yet
  is named as missing, not hard-coded.
- **Scope**: what is in, and what is explicitly out (the server contract, the modals that come
  later), so the work does not grow on its own.
- **Interface**: for a component, what it takes and what it reports (value in, callback out);
  where the value comes from and goes to belongs to the parent.
- **Acceptance criteria**: statements that can be checked: states, edge cases, platforms, tests.
  "Sync handles a lost connection" is not one. "With the network cut during sync, the list keeps
  showing the cached items with the offline banner, and the sync finishes after the network
  returns; `sync_reconnect_test.dart` covers it and passes on Android and iOS" is.

The pull request links the issue, says what was done and what was not, and the review checks each
criterion.
