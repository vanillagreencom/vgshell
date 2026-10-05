# Install guide

Covers: README.md, scripts/check-readme.js, scripts/test-check-readme.js, scripts/readme-install.sh, scripts/test-readme-install.sh

`README.md` § Install is the install guide users read, and § Plugins lists the shipped plugins. This file states what the README must say, where each fact comes from, and the two scripts that hold it to those sources. The README holds the title, the description and a screenshot, then § Features, § Install, § How it works, § Plugins, § Setup, § Writing a plugin and § Licence, in that order, and no other `## ` section. Each install route is one or two lines to paste. § Install ends with a link to [distribution.md](distribution.md) and its channel files, which hold the longer install options, updates, removal and the outlook for other distributions.

## What the README says

| Fact | Source |
|---|---|
| Arch: `paru -S <pkg>`, each package in its own fence | the recipes under `packaging/arch/` |
| Fedora: `sudo dnf copr enable <project>`, then `sudo dnf install <pkg>` | the `project` line of `packaging/fedora/copr-project`, and the specs under `packaging/fedora/` |
| The install script: `curl -fsSL <main install.sh> \| bash`, and `bash -s -- <options>` | the option parser of `install.sh`; a `--version` value is `v` plus `VERSION` |
| Nix: `nix run github:vanillagreencom/vgshell -- <vgshell args>`, the flake on `main`, or the tag with `vgshell/v<VERSION>` | the usage header of `bin/vgshell` for the command, and `VERSION` for a tag |
| A checkout: `git clone https://github.com/vanillagreencom/vgshell`, then `vgshell/bin/vgshell <args>` | the usage header of `bin/vgshell` |
| § Setup: the autostart line, in one `lua` fence | the autostart sentence in [runtime.md § Process](runtime.md#process), the line `install.sh` prints with `vgshell` for its absolute path, and the line of `bin/lib/post-install.txt` ([distribution.md § First-install text](distribution.md#first-install-text)) |
| § Plugins: one row per plugin directory, its manifest's `name` linked to its README and its `description` | the directories `bin/vgshell-scan` lists under `shell/plugins/`, and their manifests |

Every line of a `bash` fence in § Install is one command of one channel. A line that fits no channel above is refused, so a new install path needs a channel in the check first.

## The check

`scripts/check-readme.js` is the offline check. `scripts/test-check-readme.js`, a row in the `cli` area of `scripts/validate`, runs it on a scratch copy of the working tree's files the check reads before its controls. Its header lists each rule and the finding it prints: `section`, `heading`, `command`, `autostart` and `plugin`. `section` requires § Install, § Plugins and § Setup; `heading` admits only the sections the first paragraph names, in that order, each once. A `VERSION` bump under a tagged command, an option `install.sh` no longer takes, or a new, removed or renamed plugin fails the check until the README follows. The README names the Arch AUR helper prerequisite. The package detector supplies the accepted helper names. The README states no runtime floor. `vgshell run` checks the floor, and `scripts/check-packaging.js` holds the package recipes to it ([runtime.md § Process](runtime.md#process)).

The plugin table is generated, never written by hand. `check-readme.js --write-plugins` rewrites § Plugins from the manifests, and the `plugin` rule fails while the section differs from that render by one byte. A plugin the table cannot carry, with a name or description that is missing, not a string, empty, or holds `|` or a line break, or with no README, is refused, not skipped.

`scripts/test-check-readme.js` plants one defect per rule in a scratch copy and pins every output line.

`check-readme.js --commands` prints one JSON line per command: its fence, its README line, its channel, its needs, its `vgshell` arguments and its Arch helper prerequisites. The runner reads these lines, never the README.

## The runner

`scripts/readme-install.sh` runs each command as the README prints it, in clean podman containers:

- The aur, curl and checkout commands run in an `archlinux:latest` image with Quickshell, Hyprland, node, python and git. The image adds the AUR helper named by the README. They run as an unprivileged user with a controlling terminal and a login session's `HOME` and `XDG_RUNTIME_DIR`.
- The nix command runs in `nixos/nix`.
- The fedora commands run in a `fedora:44` image with sudo, as the same unprivileged user. dnf's prompts default to no, so the runner answers `y` to each, as the README tells the user to.
- Each fence runs top to bottom in one fresh container, so each alternative goes in its own fence. Outside the Fedora image every prompt gets an empty answer, so it takes its default.
- A command runs under `pipefail`, so a `curl ... | bash` whose download fails fails too, though bash exits 0 on an empty script.
- After an install or a shell command, the runner checks the installed version against `VERSION`: packaged installs print it with `--version`; checkout installs report it with `version --json`, and their displayed version must match that report.
- A command passes on exit 0. A command that runs `vgshell run` passes when it exits 78 at the Hyprland floor, because no Hyprland runs in a container.

The curl, untagged nix and checkout commands read `main` on GitHub, so the runner checks what users get, not the working tree. It needs podman and the network, so it runs by hand, not in `scripts/validate`. `scripts/test-readme-install.sh` covers its host side with stubs.

### Needs and unpublished commands

- A curl release install and a nix run of the tag need the tag `v<VERSION>`. The runner asks `git ls-remote --tags`.
- An AUR install needs its package in the AUR. The runner asks the AUR RPC info query.
- The COPR enable needs the COPR project, and a dnf install needs a succeeded build of its package there. The runner asks the COPR API; a 404 is unpublished.
- A command whose need is not published is not measured. The rest of its fence still runs. The runner names each such command and exits 77, which is not a pass.
- A probe that fails is not measured either. It is never read as unpublished.

The README's commands need no tag. `paru -S vgshell-git` needs its AUR package, and the Fedora fence needs COPR `vanillagreen/vgshell` with a `vgshell` build; every other command needs nothing published.
