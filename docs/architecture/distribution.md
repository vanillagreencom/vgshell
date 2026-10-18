# Every channel installs one shared tree

Read before touching the licence, `VERSION`, `vgshell --version`, a package recipe, the installer, the flake, the autostart entry, `vgshell self`, `bin/lib/self.js`, a tree's `current` link, or anything else that packages, installs or updates VGS.

## The approach

Every channel runs one installer, `packaging/install-system.sh`, into one tree, packs one tarball builder, prints one first-install text, and derives its dependencies from the core and plugin declarations through one offline recipe check, `scripts/check-packaging.js`. A channel is an entry in that check's `CHANNELS` table, never a branch on its id. Every bash script under the installed `bin/` sets its own runtime `PATH`, because a process Hyprland or a single-instance terminal starts inherits no wrapper. A system package starts the shell after a first install and autostarts it through an XDG entry, and never writes a line into the user's `hyprland.lua`. The choice is [D040](../decisions/D040-one-shared-install-tree.md).

The install method decides who owns the tree, and `bin/lib/self.js` is the one judge of that method, a checkout, a package, a curl install or a Nix tree, and of whether the tree is behind. VGS updates only an installation it laid out itself: `vgshell self update` fast-forwards a checkout or replaces a curl install, and refuses a package or Nix tree, naming the step that updates it. The curl installer and the self-update write VGS trees only under a directory VGS owns, under one lock, `.self.lock`, and only a verified archive reaches it; the installer starts no shell, writes no unit and edits no `hyprland.lua`.

`vgshell self repair --plan` reads the same installation owner without checking for an update. `self repair` asks before replacing edited files and restores the installation under `.self.lock`. A checkout restores tracked files from its current commit. A curl install downloads that version's verified release into a fresh versioned tree, switches `current` by rename and restarts through the repaired tree. Its directory name includes `-repair-` and a unique suffix so the previous and running trees remain available. A package uses the existing package runner's reinstall action and its AUR helper where required. Its repository or recipe supplies the available package version. A missing AUR helper uses the terminal-only `vgshell-pkg ensure-helper` operation before reinstall. `bin/lib/aur-helper.sh` owns the helper installer; Updates delegates to the same operation. Package and build questions stay in that terminal. Nix or an unknown installation owner supplies a by-hand plan with its cause. The Home step calls this owner and never writes the install itself. `scripts/test-vgshell-self.sh` and `scripts/test-vgshell-pkg-table.js` pin the routes with stand-ins.

## Why

One installer gives every channel the same file set. The tree is scripts and data, not architecture-specific binaries, so it lives under `/usr/share`. A recipe that hand-lists its dependencies drifts from the declarations the scan probes. Publishing runs from the maintainer's machine, so no signing or AUR key sits in the repository.

A package manager or Nix owns the tree it installed, and its next update would overwrite whatever VGS wrote there. A checkout fast-forwards with no diff and no question because VGS is the program the user runs, not third-party code. An AUR helper reports a `-git` package behind only when its recipe's version changes, so VGS reads `vgshell-git`'s commit itself. Most commits on main change no file the package installs, so VGS counts the package behind only when GitHub's compare of its commit with main's lists a changed installed path. `Hyprland --version` aborts when `XDG_RUNTIME_DIR` is unset, so the installer probes under a private empty one.

## Rules

### Channels

- Do keep a package manager row, in `install.sh` and `shell/Core/PackageManagers.js`, only for a distribution with a working install path; a distribution without one is named nowhere.
- Do install through `packaging/install-system.sh` with `DESTDIR` and `PREFIX`; ordinary package staging writes only under `DESTDIR` from a read-only source. The curl self-update exception is under Quickshell engine. `scripts/test-install-tree.sh` pins ordinary staging.
- Do commit `packaging/install-tree.manifest` after adding a shipped file, through `scripts/check-install-tree.sh --write`; every package build and the read-only-prefix smoke row run the check.
- Do raise a `preflight_floor` in `bin/vgshell` and every recipe together, and state no runtime floor in the README; `vgshell run` checks the floor, and `scripts/check-packaging.js` refuses a recipe that differs.
- Do print `bin/lib/post-install.txt` from a scriptlet on a first install only; a scriptlet holds no text of its own. `scripts/check-packaging.js` pins it.
- Never add a required plugin command without a package on every channel or a row in `packaging/channel-gaps.json`. `scripts/check-packaging.js` pins it.
- Do mark a required command `"install": "on-request"` only when its package must stay an optional dependency of every recipe; its plugin's Tools step on Setup opens the existing all-tools notice to install it. `scripts/check-packaging.js` pins it.
- Never give a VGS shell recipe `conflicts`, `replaces` or `provides`; `vgshell` and `vgshell-git` own the same files. The separate Quickshell engine follows the contract below. `scripts/check-packaging.js` checks both contracts.
- Never give a Fedora shell spec `Obsoletes`. `scripts/check-packaging.js` checks this separately from the engine.
- Do set `SYSCONFDIR` only in a system package; it installs the browser-policy sudoers rule, the autostart entry and the Hyprland portal preference, which the flake and the curl installer must not ship. `scripts/test-install-tree.sh` pins it.
- Do name the autostart entry's `Exec` by absolute path, keep `OnlyShowIn=Hyprland;`, and never write a user entry from the installer. `scripts/test-install-tree.sh` runs the host generator.
- Do compute the Fedora `Requires` block between its markers from data, and write each floor with its package's epoch. `scripts/check-packaging.js` and `scripts/fedora-container.sh` pin them.
- Do clone `vgshell-git` in `prepare()` with a single-branch filtered clone, never a `git+` source, which mirrors every advertised ref. `scripts/check-packaging.js` pins it.
- Do insert the one `# vgs-nix-path` line after each script's leading comment block, and never put Hyprland on the runtime `PATH`. `scripts/test-flake.sh` pins both.

### Quickshell engine

VGS carries the Hyprland request-socket lifetime fix and the log-filter mutex fix on pinned upstream Quickshell. The lifetime defect can crash the whole shell during a request reply. Without memory poisoning, the crash is rare and delayed. The logging patch protects the filter hashes from concurrent readers and writers. VGS keeps the fixes with its package recipes, without a separate engine repository or an upstream pull request.

| Channel | Engine | Reason |
| --- | --- | --- |
| AUR release and `-git` | `vgshell-quickshell` | Both shell packages depend on the named engine, so a satisfactory stock version cannot bypass the patches. |
| Fedora COPR | `vgshell-quickshell` in `vanillagreen/vgshell` | Both shell packages use the named engine from the VGS project. Repository priority does not select the engine. `errornointernet/quickshell` remains a build and runtime repository dependency for cpptrace. |
| Nix flake | Quickshell overridden in the VGS closure | The flake pins upstream and applies the same local patches. It does not replace a host package. |
| New curl installations on Arch | `vgshell-quickshell` | The installer's existing package presenter installs the named AUR engine. |
| New curl installations on Fedora | `vgshell-quickshell` | The existing package presenter requires the engine from a configured repository. Publication belongs to the overseer. |
| Existing curl installations on Arch and Fedora | `vgshell-quickshell` | The next self-update replaces the stock engine before it changes the active VGS tree. |
| Curl installer apt row | Stock Quickshell | VGS has no Debian engine package or publication channel. The installer does not build an engine or add a compiler. |
| Curl installer on NixOS | Stock nixpkgs Quickshell | The curl package table cannot apply the flake's derivation override. The VGS flake supplies the patched Nix path. |

The stock channels retain the rare shell crash risk. A stock engine that meets the runtime version floor does not prove that either patch is present.

The git channels and Nix receive the patched engine through publication after landing. The AUR and Fedora release packages receive the changed dependency at the next VGS release tag containing this change. Jarvis cuts a patch release (`X.Y.Z`, `Z > 0`) or a minor release for the owner when the work needs it, after one clean main batch run with measured timings. The release runs on the maintainer's machine. Only an `x.0` release waits for the owner. Group any steps that need the owner's own hand, such as a passphrase or a sign-in, into one question to the owner. Keep the Fedora release tag check in `packaging/fedora/srpm.sh`; a recipe-only rebuild does not bypass it.

- Keep the engine on pinned upstream with both patches and a VGS distributor identity. Keep the patches and Qt compatibility hook in `packaging/arch/vgshell-quickshell/`. The Fedora source builder and Nix flake use the same patch files. Keep local source checksums verified. `scripts/check-packaging.js` checks the recipes and the flake.
- Give the Arch engine a versioned `quickshell` provision and conflicts with both `quickshell` and `quickshell-git`. Keep matching generated source metadata. Give the Fedora engine its versioned provision and conflicts with both stock engine names. Its `Obsoletes` entries replace `quickshell` and `quickshell-git` below `0.3.3`. Without them, an ordinary dnf upgrade skips the shell update. `scripts/check-packaging.js` checks the engine contracts separately from the shell recipes.
- Route an Arch package migration through the existing VGS Updates terminal. The shell package dependency selects the engine. The package manager asks about the old engine in that terminal. An owner machine's package hold remains an owner action.
- Keep the curl engine migration in `bin/lib/self.js::migrateEngine`. Replace stock `quickshell` or versionless `quickshell-git` on Arch and Fedora through the existing package table and runner. An engine already owned by `vgshell-quickshell` needs no package action. A same-version self-update still checks the engine. `scripts/test-vgshell-self.sh` pins the migration.
- Let `packaging/install-system.sh` invoke `bin/lib/self.js::migrateCurlStage` only for the exact curl self-update staging layout. The downloaded installer must migrate an older client's engine before that client changes `current`. Ordinary package staging, other prefixes and a missing curl `current` must cause no host package action. `scripts/test-vgshell-self.sh` and `scripts/test-install-tree.sh` hold this boundary.
- Keep elevation and package conflict questions in the floating terminal through the existing presenter and package runner. An older updater can capture the installer's standard streams, so the migration must connect prompts to its controlling terminal. Without one, open the existing floating terminal and wait for its result before removing the staged source. `scripts/test-vgshell-self.sh` pins this path.
- Enable Fedora's fixed `vanillagreen/vgshell` repository through the `vgs-quickshell-repository` step in `bin/vgshell-system` before installing the engine. Keep `errornointernet/quickshell` enabled for cpptrace. Show the root plan in the same terminal. An enabled VGS repository needs no change; an unknown probe refuses the migration. `scripts/test-vgshell-system.sh` holds the repository step.
- Verify that the engine's package owner is `vgshell-quickshell` after installation. A successful package-manager exit alone cannot prove replacement. Refuse the VGS tree switch on cancellation, package failure or an unknown owner. Keep completed package changes; a retry observes them and resumes. Replace the engine in place without a migration marker or a second engine path ([D107](../decisions/D107-format-change-ships-its-migration.md)). `scripts/test-vgshell-self.sh` pins failure and retry.
- Keep publication in the existing overseer route. `DEVELOPMENT.md` § Release names the source recipes and publication steps.
- Keep the patches until an upstream release contains the fixes for upstream issues #947 and #1285. VGS-996 tracks that condition. Then raise the runtime floor, remove the patches and dedicated engine recipes, and move the patched channels to stock in one change. Prove package replacement from `vgshell-quickshell` before retiring it. Review holds this retirement rule.

### Licence

- The SPDX licence expression of a VGS shell package is `MIT AND OFL-1.1 AND ISC AND Apache-2.0 AND CC-BY-SA-4.0`.
- Do keep that expression in every shell recipe; `scripts/check-packaging.js` reads it from the line above and refuses a shell recipe that differs. The engine keeps Quickshell's own licence.

### Version

- Do read the version from `VERSION` beside `bin/`, never from a package manager; `scripts/test-vgshell-version.sh` pins it.
- Do report the checkout's describe form beside the running shell's start reading in `vgshell version`, with `restart=needed|none`; no running shell prints `running=none`. `version --json` adds `running` and `restart`, both null with no shell.

### Release tarball

- Do pack a commit, never the working tree, through `scripts/lib/release-tarball.sh`, the one builder of a source tarball; `scripts/test-release.sh` pins the parity.

### Installation ownership

- Do make every git call in `bin/vgshell` and hand `bin/lib/self.js` the facts; `self.js` decides. Review holds it.
- Never refuse `vgshell self` on a failed step; it becomes `error`, exit 0, and the fields read before it stay. A compare GitHub cannot answer is such a step. `scripts/test-vgshell-self.sh` pins it.
- Do judge `vgshell-git` behind only by a changed path in the one installed-path list in `self.js`, read from GitHub's compare API. A file list GitHub may have cut short, or a main that no longer holds the package's commit, reads behind. `scripts/test-vgshell-self.sh` pins it with a control of the commit-hash compare, and holds the list to what the recipe installs with a control that drops a path.
- Do name in the status the step an update runs, `self`, `rebuild`, `install-helper` or `none`, and for a tree that is behind with `none`, the reason. The Updates pipeline runs the step the status names and nothing else. `scripts/test-vgshell-self.sh` and `scripts/test-updates-pipeline.sh` pin it.
- Do offer `install-helper` only for a behind `vgshell-git` package under pacman with no AUR helper. The floating TUI installs paru before the update rebuilds the package. `scripts/test-vgshell-self.sh` and `scripts/test-updates-pipeline.sh` check that boundary.
- Do judge a release package's reason by its manager. Under pacman the release package comes from the AUR, so with no AUR helper it reads `no-aur-helper`, and with one it reads `package-manager` because the helper's upgrade installs it. A package under any other manager reads `package-manager`. `scripts/test-vgshell-self.sh` pins it.
- Do keep the release `vgshell` and Nix rows at `none`, with no separate VGS action. The normal package-manager upgrade owns the release package's update. The system or home configuration owns the Nix package and its dependencies, so VGS must not alter that configuration to update itself. Review holds these ownership rules.
- Do keep three trees after an update: the new one, the one the command ran from, and the one the running shell started from. `scripts/test-vgshell-self.sh` pins it with a control that removes the running shell's tree.
- Do fetch with no hook, no prompt, no askpass, no `FETCH_HEAD` and a timeout. `scripts/test-vgshell-outdated.sh` and `scripts/test-vgshell-self.sh` pin each.
- Do keep the whole installer one brace group, so a cut download runs nothing. `scripts/test-install-sh.sh` pins it.
- Do refuse root, a non-Linux host, a system package and a foreign `~/.local/bin/vgshell` before writing. `scripts/test-install-sh.sh` pins each.
- Do fetch with `curl --proto =https --tlsv1.2`, match the one `SHA256SUMS` line, replace `current` by rename only, and never remove a version directory from the installer. `scripts/test-install-sh.sh` pins each.
- Do run required installs through the staged tree's presenter and package runner, which owns elevation. `scripts/test-install-sh.sh` pins it with a fake presenter.
- Do hold the installer's floor and package tables to `bin/vgshell` and `config/requirements.json`; the drift rows of `scripts/test-install-sh.sh` pin them.
- Do accept `VGS_RELEASE_API` only in a test run: a `file://` base in the installer, a loopback base in `self.js` for the release and the compare reads. `scripts/test-install-sh.sh` and `scripts/test-vgshell-self.sh` pin it.

## The canonical example

`packaging/arch/vgshell/PKGBUILD` for a new channel, `scripts/test-vgshell-self.sh` for a new install method or update outcome. Copy them.

## Revisit when

VGS ships architecture-specific binaries, a distribution's repositories reach the floor, the owner reinstates CI, autostart settles enough for a Home Manager module, the self-update gains the installer's signature check.

## Not governed

The release flow, which is `DEVELOPMENT.md` § Release; the README's install section, which `scripts/check-readme.js` holds.
