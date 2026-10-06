# A theme target is declarative data

Read before touching a theme target, a template, an encoder, the wiring text, a target's `select` or `setup` key, or an application's one-time step.

## The approach

A target is one `target.json` plus templates under `themes/targets/<name>/`, rendered by the pure renderer `bin/lib/theme-render.js` from the package's resolved tokens, with no code and no I/O in the target. A landed file reaches its application through a managed form that proves itself: an include line matched as a whole line, a symlink whose target is exactly a file in `theme/`, or a copy whose bytes match a render ([D030](../decisions/D030-managed-copies-for-watched-theme-directories.md)). A `select` sets one theme key in the application's own settings file and never creates the file ([D024](../decisions/D024-theme-apply-sets-one-theme-key-in-an-application-settings-file.md)). A `setup` names a privileged helper the target waits for, installed by one click. A per-application fact, such as how it reloads or which file it reads first, is a comment at the target's template.

## Why

A pure renderer makes a token path mean what it means to the shell, because the judge and the table are its arguments. A managed form that proves itself needs no marker file, and nothing the user placed is ever replaced. A CLI selects a theme by name in its own settings, so without the key the user sees nothing change, and the CLI's own default must stand until the user has a settings file.

## Rules

- Do render through `bin/lib/theme-render.js` with text in and text out; `scripts/test-theme-render.js` pins the renderer.
- Do name every placeholder from the token table or a terminal slot; an unknown one refuses the target, and `bin/vgshell-theme-judge packages` renders every shipped target offline.
- Do write a colour only through the target's encoder; no encoder writes `#`, the template does. `scripts/test-theme-render.js` pins it.
- Do give each destination a unique `<target>.<ext>`, so no two targets write one file. `scripts/test-theme-render.js` pins it.
- Never run a `detect` command; an entry is met by an executable in an absolute PATH directory. `scripts/test-vgshell.sh` pins it.
- Do render the template even when a curated file is taken, so a curated file never hides a bad placeholder, and take a `curatedKeys` file only when it is a JSON object holding one of the keys. `scripts/test-theme-render.js` and `scripts/test-vgshell-editor-entries.sh` pin both.
- Do match an include line as one whole line and place a sectioned line right after its section header, so TOML never declares a table twice. `scripts/test-theme-render.js` pins both.
- Never replace anything at an entry path that is not the managed form; skip it as `entry-occupied`, and use a copy where the application watches its directory. `scripts/test-vgshell-entries.sh` pins both.
- Never wire a profile a stale `profiles.ini` names; wire only existing profile directories. `scripts/test-vgshell-targets.sh` pins it.
- Never create an absent settings file for a `select`; skip the target as `selection-file-absent`, set the key on every landing apply, and leave every other byte. `scripts/test-vgshell-agents.sh` and `scripts/test-theme-select.js` pin both.
- Do skip a target whose `setup` command is absent as `setup-absent`, grant a privileged writer its narrowest argument grammar, and offer the install only while the application is found without the writer. `scripts/test-vgshell-browsers.sh`, `scripts/test-vgshell-browser-policy.sh` and `scripts/test-themes-setup.js` pin them.
- Do run a hook that asserts a desktop setting on every apply and set nothing when the value already holds; never set an icon theme that is not installed. `scripts/test-vgshell-toolkits.sh` pins both.
- Never source `gum.env`; the floating TUI parses it at each launch and refuses the whole file on a key outside its pattern. `scripts/test-theme-gum.js` pins it with a command-substitution control.
- Never add a Hyprland target; its colours come from the generated Hyprland layer.

## The canonical example

`themes/targets/kitty/`: one `target.json` with an include wiring, one template, and a reload hook that counts a stopped application as success. Copy it. `themes/targets/pi/` is the smallest `select` target, and `themes/targets/chromium/` the one `setup` target.

## Revisit when

An application reads its configuration through a hard link, needs its theme key in a form the line edit refuses, or needs a privileged step a one-click helper cannot carry.

## Not governed

The list of shipped targets and each one's one-time step, which is `themes/targets/` and the `vgs.themes` README; the apply's order and the follow, which is [theme-apply.md](theme-apply.md).
