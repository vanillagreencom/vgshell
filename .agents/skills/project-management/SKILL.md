---
name: project-management
description: "Load to plan a cycle, audit issues, build a roadmap, or decompose research into issues."
license: MIT
user-invocable: true
metadata:
  author: "vanillagreen"
  source: "kendex"
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
---

<!-- kendex:project-instructions:start -->
## Project Instructions

Kendex workflow policy VGS keeps (KEN-3470):

- Linear, orch and project-management share one state-role map: the VGS team's live state names and lifecycle roles (Backlog, Todo, In Progress, In Review, Verifying, Done and Canceled where the team uses those names) in planning, audit, cycle, roadmap, activation, completion and research-completion operations. Read the live issue and its team's states before a transition. Verifying is post-merge evidence work. (LIN-027, ORCH-M09, PM-038)
- In implementation, planned and review-created issues and review findings, the numeric estimate is the project-management package's relative size class, and the time beside an item is one nonstop-hours-to-merge figure, per `.agents/skills/project-management/SKILL.md` § Disposition. Reassess the estimate when implementation changes the scope. (DV17, ORCH-M22, RV20)

## Linear projects

Every new issue, including manually mirrored GitHub intake, belongs to team vgs and the `VGS` project.

| Project | Scope |
|---------|-------|
| `VGS` | The plugin-first Hyprland shell on Quickshell: core, plugins, surfaces, configuration, themes, validation and repository tooling. |

Legacy projects are reference-only; do not route new work there. Creating a new project is an owner decision: propose it, do not create it unprompted.

## Project issue label taxonomy

Use this taxonomy with the linear skill's label-inventory preflight for roadmap creation, audit-created issues, research issues, and any other issue create/update path.

Required for new non-historical issues:

- Exactly one Agent label.
- Classification and Workflow labels are optional and additive.
- Domain labels apply when the work clearly sits in that domain.

Label creation rule: if a label listed here is missing from live Linear inventory, stop and ask for explicit user authorization to create it. Do not create labels automatically and do not silently omit or substitute labels.

### Agent labels (exclusive; choose exactly one)

| Label | Use when |
|-------|----------|
| `agent:frontend` | Quickshell QML and its JavaScript: a plugin's view, a surface, a component of `qs.Ui`, a Settings field. |
| `agent:runtime` | Non-UI shell, Python, TypeScript and Go code: a plugin helper, a script under `scripts/`, the smoke harness and its rows, a service's process logic. |
| `agent:maintainer` | Maintenance, docs cleanup, tooling/workflow tasks, repository organization, or mixed low-risk work. |
| `agent:multi` | Bundle parent or coordination issue whose children span 2+ domains. Avoid on leaf implementation issues unless the issue is truly orchestration-only. |
| `agent:human` | Manual/user-owned work, external dependency/vendor action, or work intentionally not delegated to an AI agent. |
| `agent:researcher` | Research issue owned by the researcher workflow/agent. Must be paired with `research`. |

`agent:iced` and `agent:rust` are workspace-level labels inherited by every team; they serve other projects (hyprtrade), so never assign them in VGS.

### Domain labels (non-exclusive; choose all that apply)

| Label | Use when |
|-------|----------|
| `ci-infra` | CI, review gates, runners, and repo tooling — the validation suite, `.github/workflows/`, packaging automation. |
| `test` | Testing itself: coverage, harnesses, fixtures, flakes. Pairs with `ci-infra` when the harness is CI-owned. |
| `app` | UI-surface work: shell surfaces under `shell/Hosts/` and plugin interfaces under `shell/plugins/`. |
| `design` | Visual design, tokens, typography and surface layout; theme rules are in `docs/architecture/configuration.md`. |
| `component` | Reusable widget/control work, especially primitives in `shell/Ui/`. |
| `releases` | Cutting a release, versioning, and publishing to the distribution channels. |
| `vpn` | The VPN plugin, `shell/plugins/vgs.vpn`, and its connections. |
| `power` | The power plugin, `shell/plugins/vgs.power`: idle stages, inhibitors, energy settings and power keys. |

### Work priority

Priority rule: performance, optimization, efficiency, scalability, maintainability, architecture and CI issues precede product/features. Run CI first, then Verifying items. Exceptions require the owner's word on a named item, a production outage, a security or data-loss defect, or a hard deadline. Launch eligible work up to ORCH_OVERSEER_LANES while accounts and local smoke capacity permit it. Keep the existing eligibility and ownership gates. Select eligible work. Never invent tasks to fill slots.

`ci-infra` implies Urgent unless the issue deliberately records why it is lower. Everything VGS uses to decide whether a change is safe to merge lives in that category, so a defect there invalidates the evidence behind every other issue's "verified" claim.

Source: Jarvis delegate note 1792036738-329613-10972 quotes owner Slack 1792036693 on 2026-10-15 and extends the 2026-10-11 instruction.

### Classification labels (non-exclusive; additive)

| Label | Use when |
|-------|----------|
| `bug` | Defect in shipped behavior. |
| `feature` | New feature or request. |
| `chore` | Mechanical/maintenance work, no behavior change. |
| `docs` | Documentation work. |
| `security` | Security-relevant surface or hardening work. |
| `refactor` | Restructure/migration/cleanup where behavior should mostly remain unchanged. |
| `research` | Research spike/issue whose primary output is findings/decision support. Pair with `agent:researcher`. |
| `baseline` | Establishes a measurement baseline, benchmark fixture, golden data, or pre-optimization reference. |

### Workflow labels (non-exclusive; additive)

| Label | Use when |
|-------|----------|
| `needs-research` | Blocked on unresolved research. Prefer a blocking relation to a research issue when one exists. |
| `needs-review` | Requires an explicit review gate before execution/merge/close. |
| `needs-safety-audit` | Concurrency, lock-free, memory/thread safety, or safety-critical validation required. |
| `needs-perf-test` | Benchmark/profiling/performance validation required before acceptance. |
| `critical-path` | Blocks or enables major project progress; align priority accordingly. |
| `blocked` | External blocker only (vendor/license/access/manual dependency). For issue dependencies, use blocking relations instead. |
| `owner-gated` | Needs an owner decision or owner-only action to proceed. |
| `hardware-blocked` | Blocked on physical hardware or device/OS access — a second monitor, a fingerprint reader, an Apple display — rather than on a decision or another issue. |

`ci-nightly` marks CI-failure mirrors; the taxonomy above does not apply to mirrored issues — do not retitle or relabel them to satisfy it. Note there is no automated ingest: mirroring GitHub intake into Linear is manual, per the tracker policy in the linear skill instructions.

### Never-use labels

These are live in the workspace and must never be assigned in VGS. The reason matters as much as the verdict: a label omitted with no explanation reads as an oversight, and gets "fixed" by someone assigning it.

| Label | Why never |
|-------|-----------|
| `Agent` | Group/parent label. Assign one of its children, never the group itself. |
| `Platform` | Group/parent label, same rule. |
| `ios` | VGS is a Linux Wayland shell for Hyprland. Can never apply. |
| `macos` | Same. |
| `windows` | Same. |
| `cross-platform` | Same — VGS targets exactly one platform, so nothing here is cross-platform. |
| `linux` | Vacuously true for every VGS issue, so it carries no information. |
| `agent:iced` | Workspace-level label inherited by every team; serves hyprtrade. |
| `agent:rust` | Same. |
| `iced` | Same. |
| `rust-core` | Same. |
| `1.0` | Kendex's release label. It does not classify VGS work. |

## Verification scope (KEN-3470: PM-040)

Repository-wide verification uses VGS's own source roots and patterns, every supported language included: QML and JavaScript under shell/, and the shell and Python under bin/ and scripts/. Explicit changed-file and base-revision scope stays valid. Report an unreadable or empty source selection rather than treating it as complete.
<!-- kendex:project-instructions:end -->

# Project Management

This skill plans tracker work: cycles, issue audits, roadmaps and research decomposition. An agent that loads it has one of two roles:

- **Primary session.** It runs a wrapper command from § Commands. A wrapper owns the user dialog and every tracker write.
- **Analysis agent.** The `tpm` agent running a TPM workflow, or the [proposal sweep](workflows/proposal-sweep.md) subagent the overseer launches. It returns JSON inline: a TPM workflow to its wrapper, the sweep to the overseer.

## Goals

These goals decide a case that no workflow step covers:

1. The tracker holds only items that pass the creation bar, and containers that group the parts of one deliverable.
2. A lane can pick up, land and prove each item alone.
3. The user decides what work exists, once per decision. The workflow decides the mechanics.

## Disposition

The rules for an item are in [references/filing.md](references/filing.md). Read that file before you judge, write, split or file a tracked item, and at a launch read.

## Commands

| Command | Arguments | Workflow |
|---------|-----------|----------|
| `cycle-plan` | none | [cycle-plan](workflows/cycle-plan.md) |
| `audit-issues` | `project` \| `project "Name"` \| `team` \| `issue [IDs]` \| `--issues [file]` \| `--single [file]` \| `--analyzed [file]` \| `project-order` | [audit-issues](workflows/audit-issues.md) |
| `roadmap plan` | `[feature]` \| `[feature] @[research-or-plan-path]` | [roadmap-plan](workflows/roadmap-plan.md) |
| `roadmap create` | `@[plan-file]` | [roadmap-create](workflows/roadmap-create.md) |
| `research-spike` | none | [research-spike](workflows/research-spike.md) |
| `research-complete` | `[ISSUE_ID]` | [research-complete](workflows/research-complete.md) |
| `research-issue` | none | [research-issue](workflows/research-issue.md) |
| `proposal-sweep` | fleet brief | [proposal-sweep](workflows/proposal-sweep.md) |

- `research-issue` is internal: `research-spike` invokes it.
- `proposal-sweep` is internal: `oversee` invokes it.

## Execution Rules

- Run the sections of a workflow in order.
- Skip a section only on its explicit **Skip if** condition, never on your own judgement of scope.
- `<delegation_format>` and `<output_format>` are literal templates:
  - Fill each `[PLACEHOLDER]`.
  - Remove the lines whose placeholders are empty.
  - Add nothing.
- For a user-visible `<output_format>` report:
  1. Send the report as a normal assistant message first.
  2. Then invoke the question tool separately, with only the question and short option labels.
  3. Never paste the report into the question or its options.
- A failed Linear read halts the workflow with its diagnostic, never a partial result.

## Read when

- When a run writes, cites, hands over or cannot find a plan, research, roadmap or audit file: [references/planning-artifacts.md](references/planning-artifacts.md).
- Before you add or change a mode, a tracker read or a tracker route in a workflow of this package, and when a step resolves or checks the team scope: [references/tracker-reads.md](references/tracker-reads.md).
- When you decide what an initiative, a project or a label holds, which project kind applies, or which project an item goes in: [references/project-map.md](references/project-map.md).
