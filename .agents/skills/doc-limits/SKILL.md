---
name: doc-limits
description: "Load to add, tune, or debug document byte ceilings and DOC_LIMITS_* settings."
summary: "Byte limits for the Markdown a harness loads at every turn: an AGENTS.md, CLAUDE.md, GEMINI.md or SKILL.md over its limit fails. Path classes set the limits, with reasoned exclusions."
license: MIT
user-invocable: true
dependencies:
  required: [commit-guards]
metadata:
  author: vanillagreen
  source: kendex
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
tags: [automation]
---

<!-- kendex:project-instructions:start -->
## Project Instructions

<!-- kendex:shared-instructions:start -->
Problems with a kendex-owned skill go through `kendex report`; check ownership in the file first.

VGS delivery policy overrides the shared workflow's mandatory review, CI-wait, branch-size and commit-hook gates. Work targets main. PRs are optional; push directly or merge a PR immediately with gh, with no queue or CI wait. Review goes by risk: a change to code where a defect shows as a performance, stability, race, leak or lifetime problem (services, Quickshell or Hyprland IPC, processes and timers, file or socket watchers, object ownership and destruction, caches, concurrency, the plugin scan and publish path, the sandbox and smoke harness) runs one internal review round, the orch review panel, before the push; a change that is only layout, copy, styling, tokens, docs or a settings field runs none. The done line names which applied and why. Do not arm git guards. Run scripts/validate once on the final relevant diff; use --changed <last-validated-commit> for a fix round, and reuse passing results while those inputs are unchanged. Do not rerun a full battery at commit, push or submission. Use --full only for an explicit full sweep or an unmapped dependency. Keep the live-session safety rules.

Kendex workflow policy VGS keeps (KEN-3470):

- Plans, research reports, measurements and handoffs go under tmp/ (a report at the path its caller names) or on the owning tracker issue, and the caller attaches the final artifact to that issue; none is committed under docs/. Before a rewrite removes a tracked copy, preserve its evidence on that issue. Durable product and architecture documentation stays in the repository. (agent-planner-06, deep-research-10, DW12)
- VGS hosts code on GitHub and tracks work in Linear: the GitHub and Linear skills stay available to the generic planning, management, research and implementation agents, tpm and frontend included, when their task uses those services. (catalog-declarations-10)
- Linear, orch and project-management share one state-role map: the VGS team's live state names and lifecycle roles (Backlog, Todo, In Progress, In Review, Verifying, Done and Canceled where the team uses those names) in planning, audit, cycle, roadmap, activation, completion and research-completion operations. Read the live issue and its team's states before a transition. Verifying is post-merge evidence work. (LIN-027, ORCH-M09, PM-038)
- The VGS estimate scale, in implementation, planned and review-created issues and review findings: 1 means hours, 2 half a day, 3 a day, 4 two to three days, 5 a week or more. The numeric field keeps this consumer-defined meaning. Reassess the estimate when implementation changes the scope. (DV17, ORCH-M22, RV20)
- A worktree or Pi session in an explicitly recorded orch lane leaves kendex refresh and apply to the overseer in the base checkout after merge; an ordinary linked worktree keeps its own project resolution and complete drift repair guidance, and a linked Git directory alone is not a lane record. After an authorized documentation rewrite changes kendex-owned inputs, use that refresh and verification route and respect a launched lane's refresh restriction. (hook-session-drift-check-04, pi-hooks-M01, DW22)
- Never kill a process by its name or argv pattern. Kill a PID recorded when you launched that process, or, on Linux, read /proc/PID/cwd and kill that PID only when the path is inside your own worktree; the /proc route is an alternative, not an extra condition on the recorded PID. (hook-block-argv-kill-03)

<!-- kendex:shared-instructions:end -->
<!-- kendex:project-instructions:end -->

# Doc Limits

Run the document byte-ceiling check before review and in CI. The commit-guards pre-commit and pre-push chains use the staged mode; at push the index is held equal to HEAD first, so that mode measures the tree being pushed.

```bash
.agents/skills/doc-limits/scripts/doc-limits
.agents/skills/doc-limits/scripts/doc-limits --staged
```

The check measures `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` and `SKILL.md`, at the root and at any depth, and no other file. A document over its limit fails the check. [references/policy.md § Path classes](references/policy.md#path-classes) says how a class sets a ceiling among those files.

A document that must stay whole gets a row in the configured excludes file with its reason. Class selection and the exclusion format are [references/policy.md](references/policy.md). Flags, settings and exit codes are in `doc-limits --help`.
