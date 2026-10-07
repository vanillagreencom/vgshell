# VGS

This is Kendex's first extensive Copilot consumer workload; report package or workflow failures with `kendex report`, using temporary consumer-side workarounds without editing Kendex-owned files.

A desktop shell for Hyprland, built on Quickshell 0.3.1. A small fixed core starts the shell, talks to Hyprland, hosts surfaces and loads plugins. Everything outside the core is a plugin: one directory with a `manifest.json`, shown on the surfaces the core hosts, landed with the validation row that proves it is built and handed what it asked for. `docs/architecture/overview.md` holds the idea and its rules.

## Commands

- `scripts/validate [AREA]`: run only checks affected by changes from the newest commit holding what last passed AREA in this worktree, else the default branch's merge base, including uncommitted files. `--changed BASE` selects a fix round; `--list` previews commands; `--full` opts into the whole area. `unit` needs Qt and no Wayland session; `package` needs rootless podman and the Arch mirrors; `qml` needs the nested sandbox. Exit 77 means a check could not run and is not a pass.
- `scripts/qml-smoke.sh`: the nested sandbox row alone. It needs `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` in the environment.
- `scripts/landing-times.py [--last N]`: the median time from open (first commit, or pull request creation) to landing on `main` over the last N landings, direct pushes and pull requests both, plus the median wait from ready to land.
- `bin/vgshell`: the runner (`run`, `restart`), the plugin manager and the theme commands (`theme list`, `theme apply <name>`, `theme reload`, `theme background next`, `theme add <git url>`, `theme update <name>`, `theme remove <name>`; `theme apply vgs` restores the defaults). Run it with no arguments for the command list.

## Conventions

- No migration, shim, fallback, alias or compatibility path, ever. A format change rewrites the owner's files once, as a cutover step the master runs. No decision record may require an old form.

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
- Follow `docs/decisions/D075-consumer-features-need-no-developer-setup.md` for automated setup, user-only steps with a clear Settings path, and existing unsupported extras. Add no new hidden extra.
- Before writing or changing code, load the code-quality skill. Before writing a plugin, load the vgs-plugin skill.

## Read when

- Before structural work, writing a plugin, a host or a capability provider, or adding a kind, a capability or a manifest key: `docs/architecture/overview.md`.
- Before touching the configuration files or their judge: `docs/architecture/configuration.md`.
- Before touching a token, the theme judge, `Theme`, a component of `qs.Ui`, a plugin-owned look, a pointer, keyboard or focus path, a Settings field, text a user reads, or any value a surface draws with: `docs/architecture/design-system.md`.
- Before touching anything that starts, stops, measures or talks to the shell, or adding a watcher, a poller, a cache or a subprocess: `docs/architecture/runtime.md`.
- Before touching the Hyprland layer, a dispatch, `Compositor`, `Dispatch.js` or a shortcut: `docs/architecture/hyprland.md`.
- Before touching the `tui` capability, a floating TUI, a package step, a system step, or any place text could become a command: `docs/architecture/commands-are-data.md`.
- Before touching a password field, a stored token or any text that could carry a secret: `docs/architecture/secrets.md`.
- Before touching a theme package, its judge, a theme target, apply, follow or reload, the theme catalog, a wallpaper download, the wallpaper state or the background, `ThemeRunner` or a theme view: `docs/architecture/themes.md`.
- Before touching the licence, `VERSION`, a package recipe, the installer, `vgshell self` or an update: `docs/architecture/distribution.md`.
- Before touching the Jarvis daemon, its wire, a brain or a tool executor: `docs/architecture/jarvis.md`; before any path by which content or a credential leaves it: `docs/architecture/jarvis-outbound.md`.
- Before touching `scripts/validate`, a row, its inputs or its verdict, a test's environment, the nested sandbox and its harness, a fault the smoke excuses, a latency or resident-size budget, or a Jarvis test: `docs/architecture/validation.md`.
- Before writing a plugin, running validation, regenerating the README's plugin table or images, or changing a licence: `DEVELOPMENT.md`.
- When working under `shell/`, `shell/plugins/`, `shell/Ui/`, `shell/Commons/` or `scripts/`: that directory's `AGENTS.md`, which Claude Code loads through the `CLAUDE.md` beside it. Pi and Codex load only the root-to-cwd chain, so an agent there reads the nested file first.

## Code Review Rules

<!-- generated by bot-instructions 2.6.0 from kendex.toml, .kendex-generated.json, SKILL.md, schemas/renders.md, AGENTS.md. Edit [bot-instructions] in the effective manifest or the spec copy, then re-render. -->

If you are a review agent reviewing code, read .github/instructions/code-review.md before you comment.
