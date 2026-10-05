# D101: The login screen is a core greeter host over greetd, set up by the `greeter` system step

[← Decision Index](INDEX.md)

**Date**: 2026-10-04

**Status**: Active

**Research**: [VGS-756](https://linear.app/vanillagreen/issue/VGS-756) and its design comment

**Refines**: [D081](D081-system-steps-closed-core-table.md), [D003](D003-everything-is-a-plugin.md), [D061](D061-no-manual-commands.md)

**Context**: VGS has no login screen. A machine boots to a bare tty or to the distribution's display manager, and a session started by hand is not uwsm-managed: the systemd user manager gets no `WAYLAND_DISPLAY`, and `graphical-session.target` stays inactive, so user services start without a display. The issue asks for a `vgs.greeter` plugin with a session picker that defaults to the uwsm-managed Hyprland session, set up and removed in one step, that unlocks the login keyring and leaves another display manager alone. A greeter runs before any user logs in, as greetd's `greeter` account, so it reads no user's home. A plugin may not build a window ([plugins.md § Isolation](../architecture/plugins.md#isolation)), and Quickshell resolves `qs.Ui` and `qs.Commons` only under the config root `shell/`.

**Decision**: greetd runs Hyprland with a static VGS configuration, Hyprland runs a second Quickshell root, `shell/greeter.qml`, and that host draws the plugin's view. One new row of D081's closed table sets it up.

- **The host.** `shell/greeter.qml` is a core root beside `shell.qml`, with no registry, plugin scan, capability or runner guard, and it names no plugin. It loads the one view `VGS_GREETER_VIEW` names, only a regular file inside `<shellDir>/plugins` once `..` and links are resolved, on one overlay layer surface per screen. The first screen alone takes the keyboard and talks to greetd. Any other view, an unset one included, or one that fails to load, is refused with one line, no surface and exit 1, so Hyprland ends and greetd starts the greeter again; each refusal comes from an event after the root loaded, since `Qt.exit` does nothing before that ([runtime.md](../architecture/runtime.md)). The host assigns the view's `screen` and `interactive` itself: the view is a plain file it loads with a `Loader`, with no registry or slot to hand them over, an exception to [plugins.md § What the core builds and hands over](../architecture/plugins.md#what-the-core-builds-and-hands-over).
- **The plugin.** `vgs.greeter` is a service plugin with capabilities `status` and `system`. Its service publishes the step's state with Set up offered while it reads needed or nixos, and, while it reads ready, copies `theme.json` and the current background image into the directory the step made, byte for byte, by rename, only when they changed. Its view, `Greeter.qml`, is a plain file of the plugin; `GreeterLogic.js` holds every decision the view makes.
- **Sessions.** The view lists every `.desktop` file under `wayland-sessions` and `xsessions` of each `XDG_DATA_DIRS` entry, by the Desktop Entry Specification: the `[Desktop Entry]` group, `Hidden`, `NoDisplay`, `TryExec`, and `Exec` split by its quoting rules with field codes removed. On first use it chooses the entry whose `Exec` runs `uwsm start` for Hyprland, matched by its command; after that, each user's last choice. An X entry starts through `startx /usr/bin/env`.
- **The step.** `greeter` writes only VGS's files, every path from the script's `prefix=` line: `/etc/greetd/vgshell.toml`, whose `[general] service` names `/etc/pam.d/vgs-greeter`, a copy of `config/system/greeter/vgs-greeter.pam` (the distribution's `login` stack and `pam_gnome_keyring`), and the drop-in `/etc/systemd/system/greetd.service.d/vgs.conf`, whose `ExecStart` runs greetd with that configuration. The configuration runs the greeter as the first account of `greeter` (Arch, Fedora) and `_greetd` (Debian) that exists, on the VT the packaged `/etc/greetd/config.toml` names when it names a number, else 1; the step reads that file and never writes it. It makes `/var/lib/vgshell/greeter/theme`, root's, with its `vgs` directory the caller's, and `/var/lib/vgshell/greeter/state`, the greeter account's, then runs `systemctl daemon-reload` after a new drop-in, `systemctl enable greetd.service`, never with `--now`, and `systemctl set-default graphical.target` while another target is the default. Its record holds each file's hash, whether VGS enabled greetd, the default target it replaced and each directory it made, and `undo` reverts only that. While greetd runs, undo keeps the PAM service and the directories greetd's next greeter needs until a later boot's undo.
- **Its probe.** Ready when the three files hold the bytes apply would write now, the directories exist, greetd is enabled and `graphical.target` is the default. Absent without greetd, Hyprland or a greeter account. Denied while `display-manager.service` names another unit, with `fix=disable-<unit>` on the refusal and nothing disabled; for an install path outside `[A-Za-z0-9._/+-]`; unless the install tree, every directory above it and what the greeter runs from it are root's and writable by no one else (`install-untrusted`); and while another account owns the theme copy's directory. On NixOS the snippet runs the VGS flake's package and declares the directories, and the probe reads ready once `display-manager.service` names greetd and the directories exist with their owners.
- **`vgshell doctor`** adds one line for the user manager's `graphical-session.target`, naming "Hyprland (uwsm-managed)" while it is inactive.

[greeter.md](../architecture/greeter.md) holds the contract and its invariants.

**Rationale**:

- The greeter account runs the greeter where every account's password is typed, so it runs only files root alone can change. A checkout or a per-user install is its owner's to rewrite, and a per-user install's version directory is removed by the next update, so the step needs VGS installed from a package. On NixOS the store holds the package the snippet names for as long as the configuration names it.
- The view composes `qs.Ui` with `Theme`, so boot, lock and unlock share one look and one theme engine. A host in the core keeps the rule that a plugin builds no window, and the plugin still owns everything it draws.
- A second root names no plugin; the view path comes from the configuration the step renders, and the host refuses a path outside the installed plugin tree, so greetd's configuration cannot point the greeter account at another file.
- Writing only VGS-owned files, and pointing greetd at them through a drop-in, leaves the packaged `/etc/greetd/config.toml` and `/etc/pam.d/greetd` untouched, so undo restores any greetd setup VGS did not make.
- Enable without start: starting greetd inside a running session takes the console from it.
- The theme copy lives in a directory the owner owns and the greeter account reads, so a theme change needs no password. Its parent, the greeter's `XDG_CONFIG_HOME`, is root's, so the owner controls no other file a library in the greeter reads from there, such as fontconfig's or libxkbcommon's.
- greetd reads its configuration when it starts, and only `graphical.target` pulls in the display manager, so undo keeps what a running greetd still uses and apply sets the default target the login screen needs.
- Matching the uwsm entry by its command, not its name, survives a translated or renamed entry.

## Where VGS differs from Omarchy

Omarchy (`basecamp/omarchy`, branch `quattro`) logs in through SDDM: `etc/sddm.conf.d/10-wayland.conf` runs SDDM's greeter under Hyprland with `default/sddm/hyprland.lua` (no logo, no splash, no animations, the keyboard layout of `/etc/vconsole.conf`), `default/sddm/omarchy/Main.qml` preselects the first session whose name contains `uwsm`, and its own session entry runs `uwsm start -g -1 -e -D Hyprland hyprland.desktop`. VGS takes Hyprland as the greeter's compositor with the same minimal configuration and the same keyboard layout read, the uwsm-managed Hyprland session as the first choice, and a theme copy outside the owner's home.

| Omarchy | VGS | Why |
|---|---|---|
| SDDM with a QML theme loaded by SDDM's own runtime | greetd with a Quickshell greeter (`Quickshell.Services.Greetd`) | The greeter is drawn with `qs.Ui` and `Theme`, so boot, lock and unlock share one look and one theme engine. An SDDM theme cannot load Quickshell types and would be a second copy of the design system. |
| `Main.qml` preselects the session whose name contains `uwsm` | The entry whose `Exec` runs `uwsm start` for Hyprland | A translated or renamed entry still matches. The Arch `hyprland` package ships `hyprland-uwsm.desktop`, so VGS ships no session entry. |
| Overwrites `/etc/sddm.conf.d` and edits `/etc/pam.d/sddm` in place | Writes only `/etc/greetd/vgshell.toml`, `/etc/pam.d/vgs-greeter` and a greetd drop-in | Undo removes exactly what VGS wrote and restores what was there before. |
| `install/login/sddm.sh` removes the `-auth` and `-password` `pam_gnome_keyring` lines of `/etc/pam.d/sddm` (autologin, passwordless keyring) and leaves its `-session ... auto_start` line | The VGS PAM service keeps `pam_gnome_keyring` in `auth` and in `session ... auto_start` | A password login unlocks the login keyring. VGS has no autologin. |
| `default/sddm/hyprland.lua` reads `XKBLAYOUT` and `XKBVARIANT` from `/etc/vconsole.conf`, else `us`, and puts `us` first with `grp:alts_toggle` for a non-Latin layout | `config/system/greeter/hyprland.lua` does the same, and also reads `XKBMODEL` and `XKBOPTIONS`, keeping those options beside `grp:alts_toggle` | `localectl set-x11-keymap` writes all four keys there on systemd systems, so the login screen types with the system keyboard layout, its model and options included. |
| `omarchy-plymouth-set` republishes root-owned theme copies through sudo on every change | The step makes one directory the owner owns and the greeter account reads, inside a root-owned one; the service copies the theme into it | A theme change needs no password. |
| `omarchy-plymouth-set --refresh-sddm-default` copies the SDDM theme through sudo to root-owned files, and SDDM's compositor reads `/usr/share/sddm/hyprland.lua` | The greeter runs the install tree in place, which must be root's and writable by no one else; a checkout or per-user install reads `install-untrusted` | A package install is already root's, so nothing is copied. Root never copies a tree its owner can change, and the greeter, which receives every account's password, runs nothing an account's own processes can rewrite. |
| Setup is part of the installer | One click on the plugin's Settings page runs the `greeter` step in the core's floating TUI | [D061](D061-no-manual-commands.md) and [D081](D081-system-steps-closed-core-table.md). |
| No check for another display manager | The step refuses with `fix=` while `display-manager.service` names another unit, and never disables it | Another display manager stays the owner's choice; its "Hyprland (uwsm-managed)" entry starts the same session. |

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| An SDDM theme, as Omarchy ships | It cannot load `qs.Ui` or `Theme`, so it would be a second design system and a second theme engine. |
| tuigreet or another text greeter | It cannot show the theme, so boot would not look like lock and unlock. |
| The plugin builds its own window under a greeter mode of `shell.qml` | A plugin may not build a window, and `shell.qml` carries the registry, the scan and the runner guard a greeter has no use for. |
| Edit `/etc/greetd/config.toml` and `/etc/pam.d/greetd` in place | Undo could not tell VGS's lines from the distribution's or another setup's, and a package update overwrites or conflicts with them. |
| Copy the theme as root on every change | Every theme change would ask for a password. |
| Disable another display manager during setup | It takes away a choice the owner made, and it is not VGS's to undo. |

**Revisit When**: greetd gains a way to run a greeter without a compositor that Quickshell supports, Quickshell resolves modules outside its config root, a distribution names the greeter account other than `greeter` or `_greetd`, or VGS ships a package that can own the greetd configuration.

**Verification**: `scripts/test-vgshell-system.sh` runs the step under a temporary prefix with stand-in `sudo`, `stat`, `systemctl`, `getent`, `greetd` and `start-hyprland`, with a copy per rule: [tui-system.md § Invariants](../architecture/tui-system.md#invariants) lists them. `scripts/test-greeter-logic.js`, `scripts/test-greeter-helpers.sh` and `scripts/test-greeter-compositor.sh` hold the view's and the service's decisions, the plugin's helpers and the keyboard layout, a control per rule; `scripts/test-vgshell-requirements.sh` holds the doctor line; `scripts/smoke/rows/greeter.sh` runs the plugin and the host in the nested sandbox, over a theme copy and a remembered session, with a view outside the plugin tree as its control.

**References**: [D001](D001-hyprland-only.md), [D003](D003-everything-is-a-plugin.md), [D033](D033-floating-tuis-are-core.md), [D061](D061-no-manual-commands.md), [D062](D062-native-lock-and-polkit-plugins.md), [D081](D081-system-steps-closed-core-table.md), [greeter.md](../architecture/greeter.md), [tui-system.md](../architecture/tui-system.md)
