---
name: dep-radar
description: "Load to run or tune a dependency sweep."
summary: "Sweeps every pinned version in the repo (deps, SDKs, vendored forks, model weights), checks upstream, and lands upgrades with their fallout in one PR per surface."
license: MIT
user-invocable: true
dependencies:
  required: [github]
  optional: [worktree]
metadata:
  author: vanillagreen
  source: kendex
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
tags: [release]
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

# dep-radar

**inventory → detect → research → classify → upgrade-with-fixes → report the owner tier**.

Generic engine only: concrete package names, pinned binaries, and fork lists live in the per-repo inventory, never here.

Load `github` before Phase 4 (PR creation, CI status, merges). Load `worktree` when a run applies more than one surface, one working copy per surface branch.

## Operating policy (the contract with the product owner)

Rule keys are the contract; an inventory owner-rule cites them. Dropping or renaming a key changes the contract.

| Rule | Contract |
|---|---|
| `auto-with-fixes` | The default. Security fixes; patch/minor bumps; pinned-binary version+SHA refreshes from OFFICIAL manifests only; SDK, agent-tooling, and runtime-binary bumps and npm/cargo majors, doing the bump AND fixing its fallout (API migrations, re-vendored bundled-extension bridges, tests, CI) in the SAME per-surface workstream; bundled-extension fork updates and local patch rebases when the consuming repo's full test suite gates the sync. |
| `report-never-auto` | Model-weight swaps; changes to durable/recorded data scope; anything an inventory owner-rule explicitly demotes. Nothing else is report-by-default. |
| `uncertain` | Attempt the upgrade; report only what actually failed, with error output. |
| `defer` | Only on a strong concrete blocker you actually hit, such as a dropped capability with no migration path or a transitive that does not support the new version. Never a generic "it's a major" risk or any other anticipated one. |
| `one-pr-per-surface` | One PR per surface; never batch surfaces. A surface's fallout fixes go in THAT surface's PR. |
| `upstream-check-required` | Every pinned surface must have a wired upstream check command; a surface lacking one is an inventory defect the run must fix. |
| `dated-report` | Every run ends with a dated report. |
| `demote-only` | Inventory owner-rules may demote auto→report, never promote report→auto. |

## Phase 0: inventory (self-maintaining)

`docs/dep-radar/inventory.md` carries one row per pinned surface: pin location, upstream check command, refresh procedure, verify command, risk tier, applicable playbook, and any repo-specific owner rules.

**First run** (no inventory): sweep the repo for pins in package manifests and lockfiles, `vendor/` dirs, SHA-256 constants near download or pin code, model manifest scripts, and version constants referencing upstream releases. Write the inventory, wire an upstream check per surface, and have the owner review the tiers.

**Every run**: diff discovered pins against the inventory, add new surfaces (each with a check), drop removed ones, and note the change in the run report.

## Phase 1: detect

Read `docs/dep-radar/last-seen.json` (create if absent) and run each surface's upstream check. If nothing moved since last-seen, update `checked_at`, write a one-line report, and stop.

## Phase 2: research

For each changed surface, read the changelog or release notes, never infer from version numbers. Extract breaking changes, deprecations, security fixes, new capabilities, and anything touching a contract the inventory names for that surface.

## Phase 3: classify

Sort every finding per the operating policy plus the inventory's per-surface tier and owner rules.

## Phase 4: apply the auto tier

Apply the inventory's refresh procedure, then fix the fallout in that surface's PR: migrate changed APIs, re-vendor bundled-extension bridges, repair broken tests and CI. Run the verify command; open the PR only once it passes locally, following the repo's review and merge-queue conventions. PR body: old→new version, changelog summary with links, fallout fixed, what was verified.

A blocker mid-apply or a failed verification stops the surface and makes it a report item with the exact error output, never ship a partial bump.

## Phase 5: report

Write `docs/dep-radar/report-<YYYY-MM-DD>.md`, committed with the last-seen update: auto-applied bumps with PR links; blocked bumps with exact error output; the owner-decision tier; new capabilities unlocked. Each awaiting-decision item names the capability, what it unlocks, estimated effort and risk, and a recommendation. Surface the report to the owner (PR description or handoff doc), not just the file.

## Technology playbooks

The inventory records which apply and every concrete package, binary, and fork name.

| Surface | Upstream check | Tier and handling | Verify |
|---|---|---|---|
| Pinned AI/agent SDK | Registry `latest` + release notes | Auto-with-fixes, majors included: migrate changed auth, runtime, and tooling APIs in the same PR. New provider models a bump exposes are report-tier; the bump itself ships. | Build + test suites; confirm expected models and features appear |
| Pinned runtime binary with SHA constants | Official release manifest for the exact version, never a third party, never hand-computed from a local download alone | Auto-with-fixes: migrate auth, protocol, and contract changes | Pin unit tests + a live download smoke on the host platform |
| npm/pnpm deps | `pnpm -r outdated`, `pnpm audit` | Auto-with-fixes, including majors: fix the mechanical fallout (renamed APIs, config, broken tests) in the same PR | Typecheck + tests |
| cargo deps | `cargo update --dry-run`, `cargo audit` when installed | Auto-with-fixes, including majors | Workspace tests at the repo's CI feature parity |
| Bundled-extension forks, a small upstream synced in by script, provenance tracked, local patches on top | The sync script's upstream ref | Auto-with-fixes **only when the consuming repo's full test suite gates the sync**: take the update, rebase the local patches, fix fallout in the same PR. | That full test suite plus the sync script's own checks |
| Patched vendor forks of large upstreams, with no script-gated sync | Upstream releases | Report, owner-decided | none |
| Model weights and artifact SHA pins | Upstream manifest | Report, never swap weights automatically | The repo's own integrity-verify scripts |
| Pinned GitHub Actions SHAs | Tag → SHA for the same action | Auto for patch/minor tag moves, refreshing the SHA comment too; majors auto-with-fixes, migrating the workflow in the same PR | Workflow run |

## Guardrails

- Migration-bearing dep bumps (DB or storage tooling) carry merge-order and version-gap hazards; check the repo's before merging.
- Shell commands follow orch SKILL.md § Harness-Safe Shell.
