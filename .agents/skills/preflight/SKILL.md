---
name: preflight
description: "Load to run, tune, or debug preflight."
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

Work targets main. Direct pushes and immediate PR merges are allowed. Do not wait for CI or a merge queue, request bot review, or arm commit/push guards. Run one internal review, the orch review panel, only for a change where a defect would affect performance, stability, races, leaks or lifetimes. Layout, copy, styling, tokens, docs and settings-field-only changes run no review round. Run no UI review round. Google Drive lanes run no review round. The lane checks changed views with its dark/light before-and-after sandbox screenshots under docs/architecture/validation.md § Screenshot baselines. Name the applicable review choice and screenshot check in the done line. Run scripts/validate once on the final relevant diff; use --changed <last-validated-commit> for a fix round and reuse passing results while inputs are unchanged. Do not rerun a full battery at commit, push or submission. Use --full only for an explicit full sweep or an unmapped dependency. Keep the live-session safety rules.
<!-- kendex:project-instructions:end -->

# Preflight

Run preflight in the validate step, before the project's own validation command.

```bash
.agents/skills/preflight/scripts/preflight              # vs the default branch's merge base
.agents/skills/preflight/scripts/preflight --staged     # staged changes (pre-commit)
.agents/skills/preflight/scripts/preflight --all        # every tracked file, every line
```

Fix what a finding reports. Never widen a lane's exclusions to clear it.

`preflight --help` gives the lanes, scopes, settings, output and exit codes.

- When setting a `PREFLIGHT_*_GLOBS` value, or when a finding turns on how the diff is taken or how `unwired-suite` reads a runner, read [references/lanes.md](references/lanes.md).
- When wiring preflight into a Git hook or CI, read [references/wiring.md](references/wiring.md).
