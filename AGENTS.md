# VGS

This is Kendex's first extensive Copilot consumer workload; report package or workflow failures with `kendex report`, using temporary consumer-side workarounds without editing Kendex-owned files.

A desktop shell for Hyprland, built on Quickshell 0.3.1. A small fixed core starts the shell, talks to Hyprland, hosts surfaces and loads plugins. Everything outside the core is a plugin: one directory with a `manifest.json`, shown on the surfaces the core hosts, landed with the validation row that proves it is built and handed what it asked for. `docs/architecture/overview.md` holds the idea and its rules.

## Commands

- `scripts/validate [AREA]`: run only checks affected by changes from the newest commit holding what last passed AREA in this worktree, else the default branch's merge base, including uncommitted files. `--changed BASE` selects a fix round; `--list` previews commands; `--full` opts into the whole area. `unit` needs Qt and no Wayland session; `package` needs rootless podman and the Arch mirrors; `qml` needs the nested sandbox. Exit 77 means a check could not run and is not a pass.
- `scripts/qml-smoke.sh`: the nested sandbox row alone. It needs `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` in the environment.
- `scripts/landing-times.py [--last N]`: the median time from open (first commit, or pull request creation) to landing on `main` over the last N landings, direct pushes and pull requests both, plus the median wait from ready to land.
- `bin/vgshell`: the runner (`run`, `restart`), the plugin manager and the theme commands (`theme list`, `theme apply <name>`, `theme reload`, `theme background next`, `theme add <git url>`, `theme update <name>`, `theme remove <name>`; `theme apply vgs` restores the defaults). Run it with no arguments for the command list.

## Conventions

- Work targets `main`.
- No branch protection, merge queue or commit/push gates. One GitHub workflow exists, `.github/workflows/nightly.yml`, which runs `scripts/validate --full` on `main` on a schedule, while the repository variable `NIGHTLY` is `on`, for the areas a hosted runner can run and reports only; no workflow runs on a push or a pull request. PRs are optional and may merge immediately; direct pushes are welcome. Do not arm Kendex guards or wait for absent CI.
- Review by risk. A change to code where a defect shows as a performance, stability, race, leak or lifetime problem (services, Quickshell or Hyprland IPC, processes and timers, file or socket watchers, object ownership and destruction, caches, concurrency, the plugin scan and publish path, the sandbox and smoke harness) runs one internal review round before the push to main. A change that is only layout, copy, styling, tokens, docs or a settings field runs none; the owner judges those by use. The lane's done line names which applied and why.
- No bot review. No vgs lane or pull request requests or waits for a Copilot, Codex or other bot review: `PR_REVIEW_GATE` and `REVIEW_GATE_MODE` in `kendex.settings.toml` stay `off`. A bot review request that comes from Kendex code goes to `kendex report`.
- Validate the final relevant diff once. After fixes, use `--changed <last-validated-commit>` and reuse results for unchanged inputs; do not repeat a full suite at commit, push or PR submission. Unknown source inputs select the full area rather than silently skipping coverage. Shared workflow gate requirements do not apply here.
- A lane runs the fast areas `scripts/validate` selects and, of the nested smoke, only the rows its change names with the rows those read. A batch run, `scripts/main-run.sh`, runs the full unit and qml areas on main, reports and gates nothing; the nightly run is `nightly.yml` plus `scripts/main-run.sh qml`, the area a hosted runner cannot run. A lane whose files no other landing lane shares lands without an order: `docs/decisions/D100-validation-selects-by-inputs.md`.

- Hyprland is the only compositor. No compositor abstraction and no second compositor: `docs/decisions/D001-hyprland-only.md`.
- Never start a second shell against the live session and never kill Quickshell processes by name. Validation runs in the nested sandbox only.
- A change that adds a surface, a service or a plugin adds its validation row under `scripts/smoke/rows/` in the same PR.
- No manual commands: a user-facing setup step is automatic or one click, a step that asks or elevates runs in a floating TUI or the requirement notice that button starts, a secret goes into a masked field VGS stores in libsecret, and the interface shows no command except a by-hand requirement notice for a step VGS cannot run on this system. A plugin README keeps commands behind Show command details. `scripts/check-user-commands.py` enforces the text: `docs/decisions/D061-no-manual-commands.md`.
- Consumer features need no developer setup. A feature that needs an app, API key or token the user must create first is an owner-only extra: declared in the manifest's `extras`, off by default, absent from the Settings page and documented only under "Extras (not supported)" in its plugin's README: `docs/decisions/D075-consumer-features-need-no-developer-setup.md`.
- Before writing or changing code, load the code-quality skill. Before writing a plugin, load the vgs-plugin skill.

## Read when

- Before structural work: adding a surface, a service, a kind, a capability, a host or a core module: `docs/architecture/overview.md`.
- Before writing a plugin or a host, choosing between an application window and an overlay, or touching the summon host, a capability's provider, a requirement, a manifest key, enablement, placement, plugin status, install, update, remove or the manager's panel: `docs/architecture/overview.md`.
- Before touching the configuration files or their judge: `docs/architecture/configuration.md`.
- Before touching a token, the theme judge, `Theme`, a component of `qs.Ui`, a plugin-owned look, a container's inset, a Settings field, or any value a surface draws with: `docs/architecture/design-system.md`.
- Before touching a pointer handler, a cursor, a scroll, a hover reading, a popup, a focusable control, a keyboard path or a list's selection: `docs/architecture/design-system.md`.
- Before writing text a user reads: a plugin description, a Settings row, a tooltip, a message or a setup screen: `docs/architecture/design-system.md`.
- Before touching anything that starts, stops, measures or talks to the shell, or adding a watcher, a poller, a cache or a subprocess: `docs/architecture/runtime.md`.
- Before touching the Hyprland layer, a dispatch, `Compositor` or `Dispatch.js`, a shortcut, a manifest's `hyprland` key or the key capture: `docs/architecture/hyprland.md`.
- Before touching the `tui` capability, a floating TUI, `vgshell pkg` or the package table, a system step or `vgshell sudo grant`, the Dev Tools catalog, the requirement notice's install, or any place a plugin's or a user's text could become a command or a flow asks the user a question or a password: `docs/architecture/commands-are-data.md`.
- Before touching a password field, a stored token, a clipboard reader, a probe of a credential, or any text that could carry a secret: `docs/architecture/secrets.md`.
- Before touching a theme package, the package judge, the theme runner, the apply, the theme catalog, a theme target, the backgrounds or the `theme` capability: `docs/architecture/themes.md`.
- Before touching the licence, `VERSION`, a package recipe, the installer, the flake, `vgshell self`, a one-time migration or `bin/vgshell-migrate`: `docs/architecture/distribution.md`.
- Before touching the Jarvis service, its daemon, a child it starts, its wire, a brain or speech adapter, the tool bridge or a tool executor: `docs/architecture/jarvis.md`.
- Before touching Jarvis release, the network door, a key lookup, or any path by which content or a credential could leave the daemon: `docs/architecture/jarvis-outbound.md`.
- Before touching `scripts/validate` or one of its rows, a test's environment, the nested sandbox, its harness, a smoke row's verdict, a sandbox fault the smoke excuses, a latency or resident-size budget, or the Jarvis test world: `docs/architecture/validation.md`.
- Before writing a plugin, running validation, regenerating the README's plugin table or images, or changing a licence: `DEVELOPMENT.md`.
- When working under `shell/`, `shell/plugins/`, `shell/Ui/`, `shell/Commons/` or `scripts/`: the `AGENTS.md` in that directory. Claude Code loads each through the `CLAUDE.md` shim beside it. Pi and Codex load only the root-to-cwd chain at launch, so an agent on those harnesses reads the nested file before working under the directory.

## Code Review Rules

<!-- generated by bot-instructions 2.4.0 from kendex.toml, .kendex-generated.json, SKILL.md, schemas/renders.md, AGENTS.md. Edit [bot-instructions] in the effective manifest or the spec copy, then re-render. -->

If you are a review agent reviewing code, read .github/instructions/code-review.md before you comment.
