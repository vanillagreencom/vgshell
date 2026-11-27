---
name: linear
description: "Load for any Linear read or write: issues, projects, cycles, milestones, initiatives, labels."
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

- VGS hosts code on GitHub and tracks work in Linear: the GitHub and Linear skills stay available to the generic planning, management, research and implementation agents, tpm and frontend included, when their task uses those services. (catalog-declarations-10)
- Linear, orch and project-management share one state-role map: the VGS team's live state names and lifecycle roles (Backlog, Todo, In Progress, In Review, Verifying, Done and Canceled where the team uses those names) in planning, audit, cycle, roadmap, activation, completion and research-completion operations. Read the live issue and its team's states before a transition. Verifying is post-merge evidence work. (LIN-027, ORCH-M09, PM-038)
- In implementation, planned and review-created issues and review findings, the numeric estimate is the project-management package's relative size class, and the time beside an item is one nonstop-hours-to-merge figure, per `.agents/skills/project-management/SKILL.md` § Disposition. Reassess the estimate when implementation changes the scope. (DV17, ORCH-M22, RV20)

## Tracker policy: Linear is canonical; GitHub Issues is intake-only

Create, label, and work issues ONLY in Linear (team vgs, identifiers VGS-<n>). GitHub Issues stays as intake, and nothing syncs back. Before creating a Linear issue, dedupe across BOTH trackers (`gh issue list --search` + live Linear search) — never file the same problem twice.

GitHub intake is mirrored manually. When selecting work, compare the open GitHub issues with the team's Linear issues. For an unmatched issue, create the Linear issue with the complete GitHub body and a link to its source. Stop and report an unreadable listing, empty body or failed create; none means that intake is complete. Keep work in Linear. Do not add synchronization automation as part of triage.

Link work to its issue through the branch name: `vgs-<n>-<slug>`. Linear's GitHub integration matches that to attach the PR, and `GH_ISSUE_PATTERN` in kendex.settings.toml reads the same shape. Commit subjects carry the identifier as the scope: `area(VGS-12): imperative summary`.

Issue labels are live Linear issue labels. Inventory source of truth:

```bash
.agents/skills/linear/scripts/linear.sh labels list
```

Use the project-management label taxonomy when assigning labels. If the taxonomy and live inventory disagree, stop before mutation and report the missing/extra label; do not substitute a nearby label. Never create labels without explicit user authorization.

`issues create/update --labels` replaces the full issue label set. For label updates, compute the intended final full set from current labels: replace only the target exclusive category (`agent:*`), preserve unrelated classification/workflow labels, then pass the full validated set.

Kept from KEN-3470:

- Keep tracker state writes in team vgs. Validate the issue's team before a write, and route another team's work to that repository's overseer through lane-mail peer send. Comments and traceability links grant no authority to change another team's state. (LIN-029)
<!-- kendex:project-instructions:end -->

# Linear CLI

```bash
.agents/skills/linear/scripts/linear.sh <resource> <action> [options]
```

`linear.sh <resource> --help` prints the options of each resource.

`--format` takes these values:

- `safe`: the default, flat and null-safe.
- `compact`: a smaller shape for workflow routing.
- `ids`: identifiers only.
- `table`.
- `raw`: the GraphQL nesting. Never assume top-level jq paths in it.

`safe` renames fields: `identifier`→`id`, `id`→`uuid`, `state.name`→`state`, `state.type`→`state_type`, `sortOrder`→`sort_order`.

## Commands

- `issues get <ID>` answers the issue with its children to three levels.
- Safe output flattens those children into `children` rows. Each row carries its `depth`, 0 for a direct child.
- `pending_count` counts the open children.
- A field `issues get` does not carry, such as the GitHub issues Linear's GitHub sync links the issue to (`syncedWith`), is a `graphql` read.
- Safe `issues get` and `issues list` rows carry `in_pr_bundle`. It is true when the description holds `**In-PR bundle**: yes`.
- Look up several issues with one `issues bulk-get <ID1> <ID2> ...`. It is also the route to verify a write.
- Read the comments of several issues with one `comments bulk-list <ID1> <ID2> ...` call, never a loop or parallel `comments list` readers. `--stdin` takes one identifier per line.
- Read links for known comment IDs with one `comments bulk-get <COMMENT_ID> ...` call.
- `comments create` opens every new comment with `> Posted by Agent: NAME, Model: MODEL, Effort: EFFORT`, read through the orch skill's `orch-runtime session`, with `unknown` for each value it does not read; `--no-attribution` posts the body as supplied. A safe read returns the body without that line, and `--format=raw` keeps it (`comments --help`).

Schema reference over ctx7: `/websites/studio_apollographql_public_linear-api_variant_current` (API), `/linear/linear` (SDK), `/websites/linear_app_developers` (guides).

## Read when

- Before a multi-step change built from these commands, such as a cancel, an absorb, a parent rebuild, a label update from a workflow or a held write: [patterns/workflow-actions.md](patterns/workflow-actions.md).
- Before changing a label definition: [patterns/workflow-actions.md § Shared label maintenance](patterns/workflow-actions.md#shared-label-maintenance).
- When a brief cites a repository path that does not exist: [patterns/workflow-actions.md § Resolve a cited artifact](patterns/workflow-actions.md#resolve-a-cited-artifact).
- When selecting, checking or renewing the credential a command uses, or when a write's attribution matters: [references/authentication.md](references/authentication.md).
- When starting, stopping or reading the request journal: [references/request-journal.md](references/request-journal.md).
- Before a write that attaches a file, records a relation, depends on an option's behavior or checks completion before merge: [references/writes.md](references/writes.md).

## Reads

Read the time an issue entered a state from its history:

1. Use Linear's API or activity history. `issues get` exposes no history field.
2. Read every history page needed to identify the latest transition into that state.
3. Take the matching `toState` row's `createdAt`.
4. If the transition is unavailable, report its time as unread.

`updated_at` records the issue's latest update, which can be a different change.

- `issues list --all-projects` enumerates every project in one command. Each row carries its `project` name.
- `--no-project` returns only unassigned issues.
- Both are mutually exclusive with `--project`.
- To read across projects, use `--all-projects`; never loop per project.
- Repeated `--label` flags, and `--labels a,b`, require ALL named labels.

A list of issues, projects, labels, project labels, teams, users, cycles, documents or initiatives has these limits:

- It returns its first `--limit` rows, 75 by default, a positive whole number.
- It prints a `linear-list: truncated` line on stderr when rows were left unread.
- `--max` reads every page.
- `milestones list`, `statuses list`, `comments list` and `attachments list` always read every row and take neither option.

Every read is whole or fails:

- A read follows each nested collection (labels, relations, children, comments) to its end.
- A read that cannot finish its chain exits nonzero with no output, never a partial result. A failed later page, a missing or repeated cursor, or a chain still open after 400 pages each end the chain.
- An audit that must see the whole backlog passes `--max`.
- A text search over issues uses `issues list --search TERMS`, which Linear filters by title and description server-side, never a `--max` list piped to a local filter.

A quota refusal exits nonzero with JSON stderr `code:"RATELIMITED"`.

- Its `quota` receipt supplies the selected deadline.
- `requests_reset` keeps the raw request-header time.
- Same-binding GraphQL calls share a private hold on this host.
- Receipt fields, storage failures and held writes: [Quota Holds](patterns/workflow-actions.md#quota-holds).

The transport retries a rate refusal, a 5xx query or download, or an unanswered query or download, at most twice. A 5xx or unanswered mutation is sent once with `linear-http: write=unconfirmed`. Read its result before resending.

## Team Target

`LINEAR_TEAM` has no default.

- Existing-issue writes, including `comments create`, route by the issue identifier and need no configured team.
- Other writes refuse when it is unset.
- Reads drop the team filter when it is unset.
- `--team <key-or-name>` overrides `LINEAR_TEAM` for one call only on `issues create`, `projects create`, `cycles create`, `labels create`, `labels audit`, `projects audit`, `cycles list`, `statuses list` and `statuses get`.
- The `--team` filter of `issues list`, `projects list` and `labels list` takes a key or name too.
- Run `auth-check --strict` before the first mutation that needs a configured team in a project.

An issue write outside `LINEAR_TEAM` refuses before any write with `linear: refused=cross-team ... route=peer-mail`. Its `fix=` line names where the work goes.

## Issue Creation Routing

- Orchestration and review sessions file through the TPM pipeline (project-management skill), which owns labels, project, priority, estimate, and relations.
- An owner-authorized, well-specified single filing is judged in the filing session, with no analysis agent or audit JSON: project-management workflows/audit-issues.md § 4.1.

`issues create`, `update` and `bulk-update` refuse a body before any write. The forms a retry needs:

- `issues create` needs a `LINEAR_AGENT_LABELS` label where that key is set. `--no-agent-label` allows a bare create.
- A create body needs `Reached by:`, a `Supersession:` record and, with `--review-born --priority 2`, `Symptom:`. The fields: project-management references/filing.md § Name what reaches it.
- An authored body opens with nonempty quoted `> **Story:**` and `> **Why this matters:**` blocks, and holds its checkboxes under `## Done when`.
- A label refusal names the undeclared label and the taxonomy file (project-management references/labels.md § Project Taxonomy Contract).

`issues create`, `issues update --project` and `issues bulk-update --project` check no project's admission lines. `--project` takes a project UUID as given, or a name, which resolves to the one project of that name in the issue's team that takes issues, every state but completed and canceled; a name matching none or several refuses. Each project states what it admits in the `Admits:`, `Kind:` and `Ends when:` lines that open its content, and `projects audit` lists those lines and every item in a project that admits nothing: the project-management skill's references/project-map.md § Admission lines and § Audit.
