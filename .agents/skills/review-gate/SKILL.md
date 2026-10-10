---
name: review-gate
description: "Load to watch pull requests, report the organization standard, or adopt consumer refresh."
summary: "GitHub review-state reducer, organization-standard report, environment provisioning and consumer refresh."
license: MIT
user-invocable: true
dependencies:
  required: [harness-ci]
  optional: [orch]
metadata:
  author: vanillagreen
  source: kendex
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
tags: [review]
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

# Review operations

GitHub rulesets enforce approvals, stale-approval dismissal and review-thread resolution. This package watches pull requests, reports repository configuration and refreshes consumer installs. It posts no review status.

## Watching pull requests

Run `scripts/pr-watch.sh` through the harness's wake-up mechanism. Read its attention lines rather than watching review-state transitions. Output and exit codes: `pr-watch.sh --help`.

## Organization standard

Run `scripts/validate-standard.sh` for a read-only report. Run `scripts/provision-environment.sh --org ORG` from the organization owner's machine to provision app-secret environments, adding `--repo ORG/NAME` to provision one repository. Settings and repository wiring: [references/adoption.md](references/adoption.md).

## Consumer refresh

An existing consumer first follows [references/adoption.md § Trusted removal for an existing consumer](references/adoption.md#trusted-removal-for-an-existing-consumer). Automatic refresh runs only after that normally reviewed removal merges. Fresh installs run `refresh/adopt-refresh.sh` from a kendex checkout at a release tag. Each consumer calls the shared workflow, which runs its scripts from that release checkout. Environment and token requirements: [references/adoption.md § Automatic consumer refresh](references/adoption.md#automatic-consumer-refresh).

Consumers refresh on a schedule or a manual run. An organization managed by fleet uses `fleet repos kendex-refresh` for immediate refresh dispatch. Dispatch requirements: [references/adoption.md § Immediate refresh](references/adoption.md#immediate-refresh).

## 4. Operations

A pull request with no automatic review needs a Copilot request. When orch is present, request through its mode owner, `approval-wait <PR#> --request-review --base-checkout PATH`, per orch's `references/gates.md` § Copilot requests, which routes its `off` and `fallback` answers. Without orch, request directly: `gh pr edit <PR#> --add-reviewer @copilot`. Ruleset targeting and request failures: [references/automatic-review.md](references/automatic-review.md).

The overseer's fallback approval and emergency merge follow the managing repository's merge workflow. This package grants no bypass and changes no ruleset.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/pr-watch.sh` | Reduce open pull requests to attention lines from GitHub's review state. |
| `scripts/validate-standard.sh` | Report rulesets, required checks, app installation and secret placement. |
| `scripts/provision-environment.sh` | Provision the organization's declared app-secret environment. |
| `refresh/adopt-refresh.sh` in the release checkout | Adopt the refresh workflow. `--retire-writer` opts into trusted retirement. |
| `scripts/install-latest.sh` | Install the latest stable release for kendex CI and the retained writer template. |
| `refresh/refresh-consumer.sh` in the release checkout | Rebuild the rolling refresh branch from the default branch and open or update its pull request at any measured class or an unmeasured standard class. Run the classifier from the same release checkout. Refuse held render edits before workflow adoption or publication. Preserve workflow edits under the [adoption contract](references/adoption.md#automatic-consumer-refresh). Disarm an armed pull request before pushing a new head; a disarm GitHub refuses stops the run unless the pull request is queued, merged or closed. Wait for GitHub to show the published head before arming app-token auto-merge. A head that stays unseen produces an unarmed warning. If GitHub refuses the arm and calls the pull request clean, merge it directly on the pushed head. Confirm that the arm enabled auto-merge, queued or merged the pull request. The merge queue merges it once the required approval, thread resolution and checks pass. The body names the class, classifier cause and path. An unmeasured standard class uses full review and CI. A failed classifier or missing class line stops publication. Render publication requires measurement. |
| `refresh/refresh-reviews.sh` in the release checkout | Handle automatic review findings under the [thread-resolution rules](references/adoption.md#automatic-consumer-refresh). |

Reviewer routing for installed packages: [references/vendored-paths.md](references/vendored-paths.md).
