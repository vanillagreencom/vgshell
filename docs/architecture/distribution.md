# Distribution

Covers: LICENSE, VERSION, bin/lib/post-install.txt, packaging/install-system.sh, packaging/install-tree.manifest, packaging/install-tree-system.manifest, packaging/runtime-libraries.json, packaging/channel-gaps.json, scripts/check-install-tree.sh, scripts/test-install-tree.sh, scripts/smoke/rows/read-only-prefix.sh, scripts/check-packaging.js, scripts/test-check-packaging.js, scripts/release, scripts/lib/release-tarball.sh, scripts/test-release.sh

This file holds how VGS is licensed and versioned, the install tree every channel shares, the release tarball every channel builds from, the text every package prints on a first install and the check every package recipe passes. Each channel and the install-method judge have their own file:

- [distribution-autostart.md](distribution-autostart.md): the XDG autostart entry a system package ships.
- [distribution-methods.md](distribution-methods.md): `vgshell self status` and `vgshell self update`, and how an install knows it is behind.
- [distribution-curl.md](distribution-curl.md): `install.sh` and the curl layout.
- [distribution-arch.md](distribution-arch.md): the `vgshell` and `vgshell-git` Arch recipes and their AUR publication.
- [distribution-fedora.md](distribution-fedora.md): the Fedora specs and COPR `vanillagreen/vgshell`.
- [distribution-nix.md](distribution-nix.md): the Nix flake.
- [RELEASING.md](../RELEASING.md): the release flow, `scripts/release` and `scripts/publish-aur.sh`.

Debian, Ubuntu, openSUSE, Gentoo and Void get no channel until their repositories carry Quickshell 0.3.1 and Hyprland with Lua configuration: decision 5 of [the platform roadmap](https://linear.app/vanillagreen/issue/VGS-511). There, the install script or a checkout works once those tools are installed.

## Licence

- `LICENSE` is the MIT licence, `Copyright (c) 2026 VanillaGreen`. MIT is the owner's choice.
- Bundled files keep their own licences, in files beside them. The fonts JetBrains Mono and Inter are under the SIL Open Font License 1.1: `shell/assets/fonts/JetBrainsMono-OFL.txt` and `shell/assets/fonts/InterVariable-OFL.txt`. The Lucide icon data is under ISC: `shell/Ui/icons/LICENSE`. Jarvis's vendored browser skill is under the Apache License 2.0: `shell/plugins/vgs.jarvis/backend/skills/browser/LICENSE`.
- The SPDX licence expression of a VGS package is `MIT AND OFL-1.1 AND ISC AND Apache-2.0`.
- `scripts/check-packaging.js` refuses a recipe whose licence is not that expression.

## Version

- `VERSION` holds the release's version: one line `X.Y.Z` of digits and dots, ending in a newline. A release tag is `v` followed by that line.
- `vgshell --version` and `vgshell version` print `vgshell <version>`. They read `VERSION` beside `bin/`, so an exported tree and every package channel print the same version without asking a package manager. They need no shell running and never contact it.
- In a git checkout they print the describe form, `vgshell X.Y.Z.r<N>.g<hash>`. With a release tag reachable from `HEAD`, `X.Y.Z` is the newest such tag's version and `N` counts the commits since it: `git describe --long --tags` over tags of `v`, digits and dots only, so `v3-beta` and `nightly` never count. With no release tag, `X.Y.Z` is `VERSION`'s and `N` counts every commit. The hash has 7 hex digits, more only when 7 are ambiguous, whatever the repository's `core.abbrev` says. The form follows the AUR `-git` package version convention, `git describe --long --tags --abbrev=7`, so it agrees with the `vgshell-git` package's version and grows with every commit after the first tag.
- The tree is a checkout only when git's top level for it is the tree itself. An exported tree unpacked inside another repository never reports that repository's commits. `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and `GIT_COMMON_DIR` from the caller are unset first, so they cannot point the check at another repository. Without git the tree is not a checkout.
- `vgshell version --json` prints one line `{"version":"<VERSION>","describe":"X.Y.Z.r<N>.g<hash>"}`, with `describe` null outside a checkout. `version` is always `VERSION`'s line. The planned consumers are `vgshell self status` and the Updates plugin.
- Refusals exit 1 with a keyed first line on stderr and nothing on stdout: `version=missing` or `version=malformed path=<file>`, `tag=<tag> reason=not-a-version` for a tag of `v`, digits and dots that is not `v<X.Y.Z>`, and `git=describe` or `git=rev-list path=<tree>` for a failed git call, a checkout with no commit included. An extra argument exits 2. `scripts/test-vgshell-version.sh` holds the rows.
- Omarchy's `omarchy-version` prints `dev (<hash>)` for a checkout and the pacman package's version otherwise. VGS reads its own `VERSION` instead, so every channel prints one version, and a checkout adds the commit distance.

## Install tree

- `packaging/install-system.sh` is the one installer for system packages, the flake and the curl installer. Call it with `DESTDIR` and `PREFIX`. Package recipes use `PREFIX=/usr`, and a user-local installer can use `PREFIX=$HOME/.local`.
- The runtime tree is `$PREFIX/share/vgshell/`. It contains `bin/`, `shell/`, `config/`, `themes/` and `VERSION`.
- The installed `qs.Ui` module includes the public components its `qmldir` exports. Their contracts are in [components.md](components.md); the install manifest check catches a missing component file.
- `$PREFIX/bin/vgshell` is a symlink to `../share/vgshell/bin/vgshell`. `vgshell` resolves its root from the real script path, so the symlink starts the installed tree and reads that tree's `VERSION`.
- The installer copies `README.md` to `$PREFIX/share/doc/vgshell/README.md` and `LICENSE` to `$PREFIX/share/licenses/vgshell/LICENSE`.
- The installer drops developer markdown under `shell/`: `AGENTS.md`, `CLAUDE.md` and `README.md`. The runtime never reads those files. It preserves the [Jarvis voice assets](jarvis-voice.md) under `backend/skills/voice/` and [computer help](jarvis-input.md) under `backend/skills/computer/` because their runtime readers need them. The computer files include the [shell reference](jarvis-shell-tools.md). The root `README.md` still installs as documentation.
- `SYSCONFDIR`, which only a system package sets, also installs the browser theme writer and its sudoers rule: a copy of `bin/vgshell-browser-policy` at `$PREFIX/bin/vgshell-browser-policy`, mode 0755, and `$SYSCONFDIR/sudoers.d/vgshell-theme-browser`, mode 0440, in a `sudoers.d` of mode 0750 as sudo's own package makes it. The rule is what the writer prints with `package-rule $PREFIX` ([theme-targets.md](theme-targets.md)). The flake and the curl installer leave it unset, since a writer on `PATH` without its rule would read as set up while every apply fails. A `SYSCONFDIR` that is empty, relative or ends in a slash is refused as `sysconfdir=<value>`.
- `SYSCONFDIR` also installs the XDG autostart entry `$SYSCONFDIR/xdg/autostart/vgshell.desktop`, mode 0644: [distribution-autostart.md](distribution-autostart.md).
- The installer refuses an existing non-empty runtime tree. It also refuses an existing `$PREFIX/bin/vgshell` unless it is the expected symlink. An upgrade uses a fresh `DESTDIR`, or removes the old runtime tree and command path before installing.
- The installer writes only under `DESTDIR`. It must run from a read-only source tree, such as the Nix store.
- `scripts/check-install-tree.sh DESTDIR PREFIX` compares the installed files and symlinks with `packaging/install-tree.manifest`. Missing entries and extra entries fail with keyed lines. After a legitimate shipped file is added, install into a scratch `DESTDIR`, then run `scripts/check-install-tree.sh --write DESTDIR PREFIX` and commit the manifest update.
- `scripts/check-install-tree.sh DESTDIR PREFIX SYSCONFDIR` checks a system package's tree. The expected set adds `packaging/install-tree-system.manifest`, whose `SYSCONFDIR/` rows name files under `SYSCONFDIR`. The writer must be mode 0755, the rule mode 0440 holding exactly what the installed writer's `package-rule PREFIX` prints, and the autostart entry mode 0644; a mode is reported as `install-tree=mode` and the text as `install-tree=rule-differs`. `--write` refuses `SYSCONFDIR` as `write=system`: the system manifest is written by hand.
- `scripts/test-install-tree.sh` proves the installer, the manifest checker, the `vgshell` symlink, the markdown drop, runtime guidance retention, target freshness, the `--write` path and the `SYSCONFDIR` install and check. Its controls plant missing, extra, wrong-link, stale-target, enumerator-failure, shell-markdown and dropped-guidance defects, a widened rule, a rule other users can read, a writer installed as a link and an autostart entry the session cannot read.
- The nested smoke's `read-only-prefix` row installs into its sandbox, verifies the pristine tree against the manifest, replaces installed `themes/targets` with the sandbox's fixture targets, and instruments the disposable Jarvis service to use its isolated [test world](jarvis.md#evidence). It then removes prefix write bits, restarts the shell from `$PREFIX/bin/vgshell`, reads Jarvis's answer, runs `vgshell theme apply vgs`, checks the installed shell log, and compares the installed tree before and after. A root-owned prefix is not available in the test, so a user-owned non-writable tree is the stand-in. Any attempted write either fails on mode bits or changes the snapshot.
- The same row runs the installed [task-event producer](jarvis-tasks.md) from a private data copy. Its synthetic question, Stop and exit records use the J09 world, not the prefix.

## Release tarball

- `scripts/lib/release-tarball.sh COMMIT VERSION OUT` is the one builder of a VGS source tarball. `scripts/release`, `scripts/arch-packages.sh`, `scripts/fedora-container.sh` and `packaging/fedora/srpm.sh` call it. It prints the tarball's sha256.
- The tarball is `git archive --prefix=vgshell-VERSION/` of the commit through `gzip -n -9`. Its bytes depend only on the commit and `VERSION`. So a channel test that packs the commit a release tags packs the release asset, whose sha256 the `vgshell` recipe pins.
- The builder packs a commit, never the working tree. `scripts/arch-packages.sh` writes uncommitted files as a commit first, and `scripts/fedora-container.sh` refuses a dirty tree. Both pack on the host, so a container's `gzip` cannot change the bytes.
- The `vgshell-git` source RPM passes the commit id as `VERSION`, so its tarball unpacks to `vgshell-<commit>/`.
- `scripts/test-release.sh` holds the parity rows. For one commit, the tarball each container build hands its container must be the release asset, byte for byte, and the Arch recipe copy must pin its sha256. Its controls hand each channel a builder copy with another prefix or another compression, and a channel copy that passes another version. Each parity row must fail on each of them.

## First-install text

- `bin/lib/post-install.txt` is the text a package prints on a first install. It names the command, `vgshell`, and says that `vgs` is LVM's command from `lvm2`. It says that a uwsm session starts VGS at login, and names `vgshell run`, the autostart line a session without uwsm needs for `~/.config/hypr/hyprland.lua`, that Chromium, Chrome, Edge and Brave follow the theme, and the installed README's path. The install tree ships it at `share/vgshell/bin/lib/post-install.txt`.
- A package's scriptlet prints that file and holds no text of its own: `post_install` in the Arch recipes ([distribution-arch.md](distribution-arch.md)) and `%post` in the Fedora specs ([distribution-fedora.md](distribution-fedora.md)). `scripts/check-packaging.js` refuses a recipe whose scriptlet does not print it, and an install tree manifest without the file.
- A package prints it on a first install. An upgrade prints nothing: a user who upgrades has started the shell before.
- `scripts/check-readme.js` holds the README's autostart line to the file's line ([install-guide.md](install-guide.md)).
- `install.sh` prints its own line, because it fills in the absolute path of the `vgshell` it installed ([distribution-curl.md](distribution-curl.md)).

## Recipe check

- `scripts/check-packaging.js` is the one offline check of every package recipe in this repository, in the `cli` area. Its header lists every rule and its keyed refusals.
- One reader builds the requirement list. It reads the core list and every shipped plugin's requirements ([requirements.md](requirements.md)) through the manifest judge, and the `preflight_floor` rows of `bin/vgshell` ([runtime.md § Process](runtime.md#process)). A floor row attaches to the requirement whose command is its probe command, or adds one: Quickshell and Hyprland have no requirement entry. A floor makes its requirement required. Its package on a channel is the one the requirement names for that manager, else the row's tool name. A floor bump in `bin/vgshell` fails the check until every channel's recipes follow.
- The same reader adds required library and layout-data packages from `packaging/runtime-libraries.json`. Each row names one id and its package names by manager. These packages have no command probe. The shared dependency rules judge them as core requirements.
- `CHANNELS` in the checker holds the Arch recipes, Fedora specs, Nix flake and installer package lists. Each entry reads hard and soft dependencies and declares its package-manager keys, version-floor rules, recipe rules and generated-metadata check. A package recipe entry also reads the recipe's licence expression for the licence rule. Every required command is a hard dependency. The hard package set must equal the declarations' required set on every channel.
- Shared rules compare each channel with the same required set. Every recipe on a channel declares the same dependencies. Arch and Fedora carry version floors. Fedora also requires its soft dependency set to match the optional declarations. Nix and the installer include required packages only.
- Arch may suggest additional optional tools in `optdepends`. It cannot move a required plugin command into that list. Fedora uses exact floors, with `nodejs` at epoch 1. `packaging/channel-gaps.json` declares unavailable required commands by channel, with reason `no official package` or `official-package-broken`. A broken official package also names its pinned revision and failing test. The check rejects an undeclared gap or an entry whose command is no longer required or now has a package mapping.
- A new channel is one `CHANNELS` entry beside the others, with its reader, fields, rules and freshness check, and its rows in `ROWS` of `scripts/test-check-packaging.js`. It changes no shared rule and no reader. A channel whose semantics differ adds a field, never a branch on its id.
- `scripts/test-check-packaging.js` plants one defect per rule in a scratch copy. Each row reads its expected values from the copy it edits, so a release step, such as a VERSION bump, a pinned checksum or a raised floor, does not break it.

## Omarchy comparison

- Omarchy's user Hyprland file loads `(os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua"`. Its command layer and docs assume `/usr/share/omarchy`, with development overrides through `OMARCHY_PATH`.
- Omarchy installs as a whole distribution. It owns defaults, system package flows, migrations, theme templates and many helper commands under one `/usr/share/omarchy` tree.
- VGS installs one shell tree beside a user's own Hyprland configuration. It writes user state to XDG configuration and state directories, not beside the install tree.
- Omarchy's packages print no start text. Its installer writes `default/hypr/autostart.lua`, where `hl.on("hyprland.start", ...)` runs `omarchy-launch-shell`, and sets up the login manager, so nothing is left for the user to do (`basecamp/omarchy` `quattro` at `245630786c71`). VGS does not own the user's `hyprland.lua` and adds only its one consented line there, never a start line. So its packages ship an XDG autostart entry that a uwsm session starts ([distribution-autostart.md](distribution-autostart.md)), and print the line a session without uwsm needs ([§ First-install text](#first-install-text)).
- VGS uses `/usr/share/vgshell` rather than `/usr/lib/vgshell` because the shipped payload is architecture-independent scripts, QML, JSON, themes and fonts. It does not use `/etc/xdg/quickshell` because `vgshell` must own the instance lock, version read and install-method root.
