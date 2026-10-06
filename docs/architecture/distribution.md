# Every channel installs one shared tree

Read before touching the licence, `VERSION`, `vgshell --version`, a package recipe, the installer, the flake, the autostart entry, `vgshell self`, `bin/lib/self.js`, a tree's `current` link, a one-time migration, `bin/vgshell-migrate`, or anything else that packages, installs or updates VGS.

## The approach

Every channel, the Arch packages, the Fedora packages, the flake and the curl installer, runs one installer, `packaging/install-system.sh`, into one tree, `/usr/share/vgshell` or a versioned user tree, packs one tarball builder, prints one first-install text, and derives its dependencies from the core and plugin declarations plus the shipped portals.conf through one offline recipe check, `scripts/check-packaging.js`. A channel is an entry in that check's `CHANNELS` table, never a branch on its id. Every bash script under the installed `bin/` sets its own runtime `PATH`, because a process Hyprland or a single-instance terminal starts inherits no wrapper. A system package starts the shell after a first install and autostarts it through an XDG entry for uwsm sessions, and never writes a line into the user's `hyprland.lua`. The choice is [D040](../decisions/D040-one-shared-install-tree.md).

The install method decides who owns the tree, and `bin/lib/self.js` is the one judge of that method, a checkout, a package, a curl install or a Nix tree, and of whether the tree is behind. VGS updates only an installation it laid out itself: `vgshell self update` fast-forwards a checkout or replaces a curl install, and refuses a package or Nix tree, naming the step that updates it. The curl installer and the self-update write only under a directory VGS owns, under one lock, `.self.lock`, and only a verified archive reaches it; the installer starts no shell, writes no unit and edits no `hyprland.lua`.

A change to a user's own files ships as a one-time migration, which `bin/vgshell-migrate` runs once per user, from `vgshell run` before the shell starts and from `vgshell self update` before its restart. A migration applies once and never asks. A failed one stops the run, shows a notice and runs again at the next start, and the shell starts whatever it answered, so a migration never blocks startup. The choice is [D076](../decisions/D076-one-time-migrations.md).

## Why

One installer gives every channel the same file set. The tree is scripts and data, not architecture-specific binaries, so it lives under `/usr/share`. A recipe that hand-lists its dependencies drifts from the declarations the scan probes. Debian, Ubuntu, openSUSE, Gentoo and Void get no channel until their repositories carry Quickshell 0.3.1 and Lua Hyprland. Publishing runs from the maintainer's machine, so no signing or AUR key sits in the repository.

A package manager or Nix owns the tree it installed, and its next update would overwrite whatever VGS wrote there. A checkout fast-forwards with no diff and no question because VGS is the program the user runs, not third-party code. An AUR helper reports a `-git` package behind only when its recipe's version changes, so VGS reads `vgshell-git`'s commit itself. `Hyprland --version` aborts when `XDG_RUNTIME_DIR` is unset, so the installer probes under a private empty one.

`vgshell run` is the only path every install method reaches, so a package hook or a unit would miss installs. A broken migration must never leave the user without a bar. `setpriv --no-new-privs` keeps a program a migration starts from gaining a privilege, and the per-migration timeout sits below the time `vgshell restart` waits for the new shell.

## Rules

### Channels

- Do install through `packaging/install-system.sh` with `DESTDIR` and `PREFIX`; it writes only under `DESTDIR` from a read-only source. `scripts/test-install-tree.sh` pins it.
- Do commit `packaging/install-tree.manifest` after adding a shipped file, through `scripts/check-install-tree.sh --write`; every package build and the read-only-prefix smoke row run the check.
- Do raise a `preflight_floor` in `bin/vgshell` and every recipe together, and state no runtime floor in the README; `vgshell run` checks the floor, and `scripts/check-packaging.js` refuses a recipe that differs.
- Do print `bin/lib/post-install.txt` from a scriptlet on a first install only; a scriptlet holds no text of its own. `scripts/check-packaging.js` pins it.
- Never add a required plugin command without a package on every channel or a row in `packaging/channel-gaps.json`. `scripts/check-packaging.js` pins it.
- Never give a recipe `conflicts`, `replaces` or `provides`; the two packages own the same files. `scripts/check-packaging.js` pins it.
- Do set `SYSCONFDIR` only in a system package; it installs the browser-policy sudoers rule, the autostart entry and the Hyprland portal preference, which the flake and the curl installer must not ship. `scripts/test-install-tree.sh` pins it.
- Do name the autostart entry's `Exec` by absolute path, keep `OnlyShowIn=Hyprland;`, and never write a user entry from the installer. `scripts/test-install-tree.sh` runs the host generator.
- Do write a Fedora node floor with its epoch, `nodejs >= 1:18`, keep `quickshell >= 0.3.1`, and compute the `Requires` block between its markers from data. `scripts/check-packaging.js` and `scripts/fedora-container.sh` pin them.
- Do clone `vgshell-git` in `prepare()` with a single-branch filtered clone, never a `git+` source, which mirrors every advertised ref. `scripts/check-packaging.js` pins it.
- Do insert the one `# vgs-nix-path` line after each script's leading comment block, and never put Hyprland on the runtime `PATH`. `scripts/test-flake.sh` pins both.

### Licence

- The SPDX licence expression of a VGS package is `MIT AND OFL-1.1 AND ISC AND Apache-2.0 AND CC-BY-SA-4.0`.
- Do keep that expression in every recipe; `scripts/check-packaging.js` reads it from the line above and refuses a recipe that differs.

### Version

- Do read the version from `VERSION` beside `bin/`, never from a package manager; `scripts/test-vgshell-version.sh` pins it.

### Release tarball

- Do pack a commit, never the working tree, through `scripts/lib/release-tarball.sh`, the one builder of a source tarball; `scripts/test-release.sh` pins the parity.

### Installation ownership

- Do make every git call in `bin/vgshell` and hand `bin/lib/self.js` the facts; `self.js` decides.
- Never refuse `vgshell self` on a failed step; it becomes `error`, exit 0, and the fields read before it stay. `scripts/test-vgshell-self.sh` pins it.
- Do keep three trees after an update: the new one, the one the command ran from, and the one the running shell started from. `scripts/test-vgshell-self.sh` pins it with a control that removes the running shell's tree.
- Do fetch with no hook, no prompt, no askpass and no `FETCH_HEAD`, ended at 10 s, and run `bin/vgshell-migrate` from the updated tree after an update.
- Do keep the whole installer one brace group, so a cut download runs nothing. `scripts/test-install-sh.sh` truncates it at every line end and every byte of the last 256.
- Do refuse root, a non-Linux host, a system package and a foreign `~/.local/bin/vgshell` before writing. `scripts/test-install-sh.sh` pins each.
- Do fetch with `curl --proto =https --tlsv1.2`, match the one `SHA256SUMS` line, replace `current` by rename only, and never remove a version directory from the installer. `scripts/test-install-sh.sh` pins each.
- Do run required installs through the staged tree's presenter and package runner, which owns elevation. `scripts/test-install-sh.sh` pins it with a fake presenter.
- Do hold the installer's floor and package tables to `bin/vgshell` and `config/requirements.json`; the drift rows of `scripts/test-install-sh.sh` pin them.
- Do accept `VGS_RELEASE_API` only in a test run: a `file://` base in the installer, a loopback base in `self.js`. `scripts/test-install-sh.sh` and `scripts/test-vgshell-self.sh` pin it.

### Migrations

- Do name a migration under `bin/migrations/` by the pattern `bin/vgshell-migrate` states; a name outside it refuses the whole run. `scripts/test-vgshell-migrate.sh` pins it.
- Do make a migration idempotent: read the state, change nothing when there is nothing to change. Review holds it.
- Never use the network, ask for a privilege, prompt, or edit `/etc` from a migration; the runner gives no new privileges, no stdin and a bounded time. `scripts/test-vgshell-migrate.sh` pins each.
- Do write a setting through `vgshell-plugin-judge seed-setting`, which keeps a symlink a link and leaves a key the user set.
- Never read a secret from a credential store; read presence and unlock nothing. `scripts/test-migration-slack-photos.sh` pins it.
- Do show a failure as a notice that names no command. `scripts/check-user-commands.py` refuses one ([D061](../decisions/D061-no-manual-commands.md)).

## The canonical example

`packaging/arch/vgshell/PKGBUILD`: the shortest recipe, no build step, one install line, the licence expression, and the floor read from the check. Copy it for a new channel. For a new install method or update outcome, copy the shape of `scripts/test-vgshell-self.sh`; for a migration, copy `bin/migrations/1790801764-slack-photos-extra.sh`, a presence read and one seeded setting.

## Revisit when

VGS ships architecture-specific binaries, a distribution's repositories reach the floor, the owner reinstates CI, autostart settles enough for a Home Manager module, the self-update gains the installer's signature check, VGS ships a systemd user unit or a package hook that could run migrations earlier, or a migration needs a privilege or a question.

## Not governed

The release flow, which is `docs/RELEASING.md`; the README's install section, which `scripts/check-readme.js` holds; the migration runner's own lifetime, which is [runtime.md](runtime.md).
