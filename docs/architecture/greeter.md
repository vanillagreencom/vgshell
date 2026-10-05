# Login screen

Covers: shell/greeter.qml, shell/plugins/vgs.greeter/**, config/system/greeter/**, scripts/test-greeter-logic.js, scripts/test-greeter-helpers.sh, scripts/test-greeter-compositor.sh, scripts/smoke/rows/greeter.sh, scripts/smoke/fixtures/greeter/**

The login screen: greetd runs Hyprland with `config/system/greeter/hyprland.lua` as the greeter account, `greeter` or `_greetd`, Hyprland runs the core's greeter host `shell/greeter.qml`, and the host draws `vgs.greeter`'s view. [D101](../decisions/D101-greeter-host-and-greeter-system-step.md) records the choice and where VGS differs from Omarchy. The `greeter` row of the system-step table sets it up: [tui-system.md](tui-system.md).

## Vocabulary

- **Greeter host**: `shell/greeter.qml`, a second Quickshell root beside `shell.qml`. It holds no registry, plugin scan, capability or runner guard.
- **View**: `shell/plugins/vgs.greeter/Greeter.qml`, a plain file of the plugin and no entry point, as `vgs.lock`'s `pam/` and `bin/` are. `GreeterLogic.js` holds every decision it makes.
- **Theme copy**: `theme.json` and the current background image under `/var/lib/vgs/greeter/theme/vgs`, which the plugin's service writes and the greeter reads as its `Paths.configDir`. The step makes `theme` root's and only `vgs` the owner's.

## The host

- The greetd configuration the step renders sets `VGS_GREETER_VIEW` to the view, `VGS_GREETER_ROOT` to the install tree, and `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` to the greeter's directories, so `Paths`, `ThemeSource` and `Theme` read the theme copy unchanged.
- The host resolves the view and the plugin directory with `realpath -e` and accepts only a regular file ending `.qml` inside `<shellDir>/plugins`. It then builds one `PanelWindow` per screen on the overlay layer, namespace `vgs:greeter`, covering the output in the theme's background colour as the lock host's surface does, and loads the view with its `screen` and `interactive`. The first screen alone takes exclusive keyboard focus and talks to greetd; the others draw the background and the time.
- A refused view, and one that fails to load, print `greeter: refused: view=<unset|missing|outside|not-a-file|unloadable> path=<value>` and exit 1 with no surface. Each refusal comes from the resolver's exit or the loader's status, after the root loaded, since `Qt.exit` does nothing before that ([runtime.md](runtime.md)). The host draws nothing of its own: Hyprland's configuration exits Hyprland when qs ends, and greetd starts the greeter again.
- The host assigns the view's `screen` and `interactive` itself, the one host that assigns a plugin file's properties: [plugins.md § What the core builds and hands over](plugins.md#what-the-core-builds-and-hands-over).

## The compositor

- `config/system/greeter/hyprland.lua` sets no logo, no splash and no animations, and runs the host, then exits Hyprland when qs ends.
- The login screen types with the system keyboard layout: `XKBLAYOUT`, `XKBVARIANT`, `XKBMODEL` and `XKBOPTIONS` from `/etc/vconsole.conf`, which `localectl set-x11-keymap` writes on systemd systems, else `us`. A layout that cannot type Latin letters gets `us` first, with `grp:alts_toggle` beside its options, as Omarchy's greeter does.

## The view

- Accounts come from `getent passwd`: uids 1000 to 59999 whose shell is not `nologin` or `false`. With none listed, a text field takes the account name.
- Sessions come from `bin/sessions list` over the `XDG_DATA_DIRS` entries, `/usr/local/share:/usr/share` when unset. The view reads the `[Desktop Entry]` group alone, without localized keys. An earlier directory's file of the same name and kind wins, and a `Hidden` one deletes it. A `NoDisplay` entry and one whose `TryExec` `bin/sessions which` does not find are left out. `Exec` is split at spaces outside double quotes, with the string escapes read first, and field codes are removed. An X entry reads unavailable while `startx` is not found.
- On first use the view chooses the entry whose `Exec` runs `uwsm start` and starts Hyprland, by `DesktopNames` or by the argument uwsm starts. After that it chooses the last account and that account's last session, kept in `Paths.stateDir/greeter.json`, which it writes before `launch`.
- Enter in the password field calls `Greetd.createSession`. The typed password answers greetd's first prompt that hides what is typed, and only that one: `GreeterLogic.promptAnswer` returns the password still held, null once a prompt took it, and the view keeps that. A prompt that shows what is typed, and a hidden prompt with the field empty, wait for the person. A message without a prompt shows under the field, `authFailure` clears the field, and `readyToLaunch` launches the session: a Wayland entry with `XDG_SESSION_TYPE=wayland`, an X entry through `startx /usr/bin/env`, each with `XDG_SESSION_DESKTOP` and `XDG_CURRENT_DESKTOP` from `DesktopNames`.
- Suspend, Restart and Shut down run `systemctl suspend`, `reboot` and `poweroff` through `Quickshell.execDetached`.
- The view prints the lines its header names, for the journal and for the smoke row, the theme and the background it loaded among them.

## The service

- The service publishes `greeter`, the step's reading, with Set up offered while it reads `needed` or `nixos`, and `theme`, the last copy's result.
- While the step reads ready, `bin/copy-theme` copies `Paths.configDir/theme.json` and the image `Paths.stateDir/background` links to into `GreeterLogic.THEME_DIR/vgs`, with the arguments `GreeterLogic.copyArguments` gives, null while the step reads anything else: once when the step turns ready, and again after each change to `theme.json` or `backgrounds.json`, which the theme runner replaces on every background change. Each file is copied byte for byte, mode 0644, to a temporary file renamed into place, only when its bytes differ; a source that is gone removes its copy. One copy runs at a time.

## The login conversation in the sandbox

`scripts/smoke/rows/greeter.sh` runs the view's login against `scripts/smoke/fixtures/greeter/greetd.py`, a stand-in greetd that knows one password, starts no session and reaches no PAM. It rests on how Quickshell 0.3.1's `Greetd` speaks greetd's IPC (`src/services/greetd/connection.cpp`). The singleton reads `GREETD_SOCK` once, when it is first built: empty or unset, `available` is false; otherwise `available` is true at once and the client connects once and never retries, so the stand-in listens before the host starts. Each message both ways is a 4-byte length in host byte order, then that much compact UTF-8 JSON. The client sends `create_session`, `post_auth_message_response`, `start_session` and `cancel_session`, and reads `success`, `error` with `error_type` `auth_error` or `error`, and `auth_message`, whose `secret` type asks for a response that is not echoed. After an `auth_error` the client emits `authFailure` and sends `cancel_session` itself. greetd answers every `cancel_session` with `success`, which the client, inactive by then, logs as an unexpected response; a `success` it reads only after the next `create_session` passes as that session's authentication, so the row waits for that line before each new try. `Greetd.launch` with two arguments quits qs once greetd answers `success` to `start_session`, so the host ends on its own after the right password. The row does not prove PAM, a boot into the greeter or the step's greetd drop-in; the owner tests those by hand.

## Invariants

1. The host loads no view outside the installed plugin tree, builds no surface for one, and names no plugin. Enforced by `scripts/smoke/rows/greeter.sh`, whose control hands it a view reached through `..` outside the tree, and by `scripts/check-plugin-boundary.py` for the plugin name.
2. The view chooses the uwsm-managed Hyprland entry on first use by its command, then each account's last session; it lists what the Desktop Entry Specification lists; and the typed password answers only the first hidden prompt. Enforced by `scripts/test-greeter-logic.js`, a control per rule, and in the nested sandbox by `scripts/smoke/rows/greeter.sh`, over fixture session directories and again over a `greeter.json` that names the last session, whose login it runs against the stand-in greetd: a wrong password, an empty field cancelled with Escape, then the right password and the chosen session's `start_session`.
3. The service copies only while the step reads ready, the theme file, the background link and the step's directory in that order; the copy changes only when its source's bytes change, lands by rename, and never follows a link at the copy; and the view loads the copy's theme and background. Enforced by `scripts/test-greeter-logic.js` and `scripts/test-greeter-helpers.sh`, a control per rule, and by `scripts/smoke/rows/greeter.sh`, which reads the host load a planted copy.
4. The login screen types with the system keyboard layout. Enforced by `scripts/test-greeter-compositor.sh`, a control per rule.
5. The plugin's status follows the step's reading, and disabling it drops its status and its hold on `system`. Enforced by `scripts/smoke/rows/greeter.sh`, whose control masks greetd and reads both change.
6. The step writes only VGS's files, runs the greeter only from a tree root alone can change, and enables greetd without starting it: [tui-system.md § Invariants](tui-system.md#invariants).

## Not tested here

A boot into the greeter, a real greetd login, the keyring unlock and the session's `graphical-session.target` need a machine that boots with the step applied. No row starts greetd, PAM or sudo; the row's greetd is the stand-in above. No row reaches the service's copy in a running shell: the smoke's step reads absent, so the service's watchers of `theme.json` and `backgrounds.json`, its one-copy-at-a-time queue and the theme status after a copy are read by no test; the decision to copy and its arguments are `copyArguments`'s, and the copy itself is `bin/copy-theme`'s.
