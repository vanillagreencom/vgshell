# Every channel installs one shared tree

Read before touching the licence, `VERSION`, `vgshell --version`, a package recipe, the installer, the flake, the autostart entry, or anything that packages or installs VGS.

## The approach

Every channel, the Arch packages, the Fedora packages, the flake and the curl installer, runs one installer, `packaging/install-system.sh`, into one tree, `/usr/share/vgshell` or a versioned user tree, packs one tarball builder, prints one first-install text, and derives its dependencies from the core and plugin declarations plus the shipped portals.conf through one offline recipe check, `scripts/check-packaging.js`. A channel is an entry in that check's `CHANNELS` table, never a branch on its id. Every bash script under the installed `bin/` sets its own runtime `PATH`, because a process Hyprland or a single-instance terminal starts inherits no wrapper. A system package starts the shell after a first install and autostarts it through an XDG entry for uwsm sessions, and never writes a line into the user's `hyprland.lua`. The choice is [D040](../decisions/D040-one-shared-install-tree.md).

## Why

One installer gives every channel the same file set, and the install method decides who owns the tree. The tree is scripts and data, not architecture-specific binaries, so it lives under `/usr/share`. A recipe that hand-lists its dependencies drifts from the declarations the scan probes. Debian, Ubuntu, openSUSE, Gentoo and Void get no channel until their repositories carry Quickshell 0.3.1 and Lua Hyprland. Publishing runs from the maintainer's machine, so no signing or AUR key sits in the repository.

## Rules

- Do install through `packaging/install-system.sh` with `DESTDIR` and `PREFIX`; it writes only under `DESTDIR` from a read-only source. `scripts/test-install-tree.sh` pins it.
- Do commit `packaging/install-tree.manifest` after adding a shipped file, through `scripts/check-install-tree.sh --write`; every package build and the read-only-prefix smoke row run the check.
- The SPDX licence expression of a VGS package is `MIT AND OFL-1.1 AND ISC AND Apache-2.0 AND CC-BY-SA-4.0`.
- Do keep that expression in every recipe, and raise a `preflight_floor` in `bin/vgshell` and every recipe together; `scripts/check-packaging.js` reads the expression from the line above and refuses a recipe that differs.
- Do read the version from `VERSION` beside `bin/`, never from a package manager; `scripts/test-vgshell-version.sh` pins it.
- Do pack a commit, never the working tree, through `scripts/lib/release-tarball.sh`; `scripts/test-release.sh` pins the parity.
- Do print `bin/lib/post-install.txt` from a scriptlet on a first install only; a scriptlet holds no text of its own. `scripts/check-packaging.js` pins it.
- Never add a required plugin command without a package on every channel or a row in `packaging/channel-gaps.json`. `scripts/check-packaging.js` pins it.
- Never give a recipe `conflicts`, `replaces` or `provides`; the two packages own the same files. `scripts/check-packaging.js` pins it.
- Do set `SYSCONFDIR` only in a system package; it installs the browser-policy sudoers rule, the autostart entry and the Hyprland portal preference, which the flake and the curl installer must not ship. `scripts/test-install-tree.sh` pins it.
- Do name the autostart entry's `Exec` by absolute path, keep `OnlyShowIn=Hyprland;`, and never write a user entry from the installer. `scripts/test-install-tree.sh` runs the host generator.
- Do write a Fedora node floor with its epoch, `nodejs >= 1:18`, keep `quickshell >= 0.3.1`, and compute the `Requires` block between its markers from data. `scripts/check-packaging.js` and `scripts/fedora-container.sh` pin them.
- Do clone `vgshell-git` in `prepare()` with a single-branch filtered clone, never a `git+` source, which mirrors every advertised ref. `scripts/check-packaging.js` pins it.
- Do insert the one `# vgs-nix-path` line after each script's leading comment block, and never put Hyprland on the runtime `PATH`. `scripts/test-flake.sh` pins both.

## The canonical example

`packaging/arch/vgshell/PKGBUILD`: the shortest recipe, no build step, one install line, the licence expression, and the floor read from the check. Copy it for a new channel.

## Revisit when

VGS ships architecture-specific binaries, a distribution's repositories reach the floor, the owner reinstates CI, or autostart settles enough for a Home Manager module.

## Not governed

How an installed tree learns it is behind and updates itself, which is [distribution-methods.md](distribution-methods.md); the release flow, which is `docs/RELEASING.md`.
