---
name: worktree
description: "Load to create, list, remove, push, or repair a git worktree."
license: MIT
user-invocable: true
argument-hint: "create <ID> [<branch>] [--base <branch>|--from <ref>|--pr <N>] [--reuse [--keep-on-conflict]|--restack] [--replay] [--hosted] | create <ID> --transfer <branch> (not with <branch>, --base, --from, --pr, --reuse, --restack, or --replay) | restack continue|skip|abort <ID|path> | list | remove <ID|path>"
metadata:
  author: "vanillagreen"
  source: "kendex"
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
---

<!-- kendex:project-instructions:start -->
## Project Instructions

Work targets main. Direct pushes and immediate PR merges are allowed. Do not wait for CI or a merge queue, request bot review, or arm commit/push guards. Run one internal review, the orch review panel, only for a change where a defect would affect performance, stability, races, leaks or lifetimes. Layout, copy, styling, tokens, docs and settings-field-only changes run no review round. Run no UI review round. Google Drive lanes run no review round. The lane checks changed views with its dark/light before-and-after sandbox screenshots under docs/architecture/validation.md § Screenshot baselines. Name the applicable review choice and screenshot check in the done line. Run scripts/validate once on the final relevant diff; use --changed <last-validated-commit> for a fix round and reuse passing results while inputs are unchanged. Do not rerun a full battery at commit, push or submission. Use --full only for an explicit full sweep or an unmapped dependency. Keep the live-session safety rules.

Kendex workflow policy VGS keeps (KEN-3470):

- A worktree or Pi session in an explicitly recorded orch lane leaves kendex refresh and apply to the overseer in the base checkout after merge; an ordinary linked worktree keeps its own project resolution and complete drift repair guidance, and a linked Git directory alone is not a lane record. After an authorized documentation rewrite changes kendex-owned inputs, use that refresh and verification route and respect a launched lane's refresh restriction. (hook-session-drift-check-04, pi-hooks-M01, DW22)

VGS uses GitHub pull requests. Worktree ownership discovery checks the live GitHub pull requests as well as native Git refs before reuse or creation, and resolves the default branch, main, from WORKTREE_DEFAULT_BRANCH or the provider. (KEN-3470: WT-026)
<!-- kendex:project-instructions:end -->

# Worktree Management

```bash
.agents/skills/worktree/scripts/worktree <command> [options]
```

Every command's contract is its `--help`: flags, exit codes, failure semantics and recovery. The top-level `worktree --help` gives the command index, the path and issue-ID rules, the configuration variables and setup-path hardening.

## Commands

| Command | Description |
|---------|-------------|
| `create` | Claim a new issue worktree |
| `restack` | Guardedly continue, skip, or abort a tool-created paused restack |
| `list` | List all worktrees |
| `remove` | Remove worktree, clean symlinks, prune branches |
| `cleanup` | Remove worktrees whose branches are merged |
| `path` | Print the worktree path for an issue ID |
| `path --hosted` | Print the hosted lane path |
| `exists` | Check the worktree path for an issue ID |
| `merged` | Print the commit the issue tree's pull request merged as |
| `check` | Pre-create git state check (JSON: uncommitted, unpushed) |
| `push` | Push worktree branch to remote |
| `fix-links` | Restore configured symlinks |
| `repair-links` | Restore configured symlinks, run by the git hooks |
| `codex-setup` / `codex-branch` / `codex-cleanup`, `claude-setup` / `claude-cleanup` | App-created worktree hooks |

- `repair-links` never destroys untracked data.
- `create` is a new-work claim, not a discovery command. Existing ownership exits 75.
- Inspect or monitor owned work. Never give it a second implementer.
- Rebase a branch through `worktree push`, `create --restack` or `create --reuse`.

## Policy-blocked rebase (cherry-pick replay fallback)

When an execution policy rejects top-level `git rebase` porcelain:

- Never retry the porcelain.
- Never substitute a raw `--force` push.
- Add `--replay` to the guarded restack (`create --help`). The controls stay `restack continue|skip|abort <ID>`.

## Read when

- When wiring Codex Desktop or Claude Code to run the app-created worktree hooks, read [references/hooks.md](references/hooks.md).
- When a worktree's `.agents` entry is broken, follow [workflows/repair-agent-links.md](workflows/repair-agent-links.md).
- When claiming, refreshing or releasing a worktree lease, or judging whether one is stale, read [references/session-guard.md](references/session-guard.md). `worktree-session-guard --help` gives the guard's commands, exit codes and `--repo` scope.
- Before installing JS dependencies in a worktree, read `worktree --help` § Dependencies. It owns install and linked-`node_modules` behavior.

## Session guard (ownership leases)

`scripts/worktree-session-guard` stops cleanup from destroying a claimed worktree. Its lease is a native Git worktree lock whose reason line carries the owner and a heartbeat.

## Recovering a failed removal

- Keep the first `remove` failure's diagnostic with the lane owner's records. It names the repository, worktree path, retained branch and observed registration and directory state.
- Follow the failure or refusal's manual recovery steps from the main checkout.

## Reclaiming build output

`cleanup --targets-only` prunes build output. It keeps the worktree, its branch and every tracked and untracked source file. It previews by default and deletes only under `--apply`.

1. Run it from the main checkout.
2. Read the preview.
3. Repeat with `--apply`.

It skips every leased worktree, with one exception: `--worktree PATH --owner ID` lets the session holding a worktree's lease prune that one worktree's Cargo profiles, with no retention window.

## Configuration

**Symlink only what git does not carry.**
