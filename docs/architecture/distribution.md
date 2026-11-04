# Every channel installs one shared tree

Read before touching the licence, version, package recipes, installer, flake, autostart, self-update, repair or an installation's `current` link.

## The approach

All channels install the same tree through `packaging/install-system.sh` ([D040](../decisions/D040-one-shared-install-tree.md)). `scripts/check-packaging.js` judges recipes against runtime and plugin declarations through its `CHANNELS` table. `bin/lib/self.js` alone judges installation ownership and update eligibility.

The installation owner controls replacement. VGS updates its checkout and curl layouts; package managers and Nix own theirs. Repair uses that same ownership decision and asks before replacing edited files.

## Why

A shared installer prevents channels from shipping different files. Dependency declarations must match what the runtime requires. An update must not write over a tree another package owner will replace. Release credentials remain on the maintainer's machine.

## Rules

### Channels

- Add a package-manager row only for a distribution with a working install path. Keep `install.sh` and `shell/Core/PackageManagers.js` aligned. Review holds support claims.
- Stage packages from a read-only source through `packaging/install-system.sh`, writing only under `DESTDIR` and `PREFIX`. The exact curl engine-migration exception is below. `scripts/test-install-tree.sh` checks staging.
- Update `packaging/install-tree.manifest` for shipped-file changes through its generator. `scripts/check-install-tree.sh` checks the installed set.
- Raise runtime floors in `bin/vgshell` and every recipe together. A README floor note names only a supported distribution that does not yet ship it and changes with the floor. `scripts/check-packaging.js` checks recipe parity.
- Derive dependencies from declarations. Every required plugin command needs a package on every channel or a `packaging/channel-gaps.json` entry. An on-request command remains optional in every recipe and uses the existing Tools notice. `scripts/check-packaging.js` checks these contracts.
- Keep shell recipes free of conflicts, replacements and provisions, including Fedora `Obsoletes`. The engine has a separate replacement contract. `scripts/check-packaging.js` checks both.
- Print `bin/lib/post-install.txt` only on first package install; scriptlets keep no separate copy. `scripts/check-packaging.js` checks the text source.
- Set `SYSCONFDIR` only for system packages. Keep their system integration out of curl and Nix installs. Use an absolute Hyprland-only autostart entry and create no user entry. `scripts/test-install-tree.sh` checks this boundary.
- Generate Fedora requirements from data with package epochs. Keep the AUR git source a single-branch filtered clone in `prepare()`. `scripts/check-packaging.js` checks recipes.
- Give each installed Bash script its runtime PATH. Keep Nix's generated path line after its leading comments and keep Hyprland off that PATH. `scripts/test-flake.sh` checks Nix substitution.

### Quickshell engine

- Require the delivered VGS engine on every channel. Judge its release and package floors in `bin/lib/engine.js`, before taking the shell lock. An upstream version alone is insufficient. Preserve upstream's version and identify VGS through supported `DISTRIBUTOR` metadata. `scripts/test-vgshell.sh` checks refusal; `scripts/check-packaging.js` checks channel parity.
- Keep one pinned upstream and shared local patches under `packaging/arch/vgshell-quickshell/` for Arch, Fedora, Debian and Nix. Verify local source checksums. The fixes cover request-socket lifetime, log-filter synchronization, managed child lifetime and FileView read-error handling. `scripts/check-packaging.js` checks the shared inputs.
- Preserve FileView's `printErrors` control and distinguish confirmed absence from an existing or unconfirmed read failure. Preserve managed child lifetime under [runtime.md](runtime.md#process). Review holds these engine guarantees.
- Keep versioned `quickshell` provisions and conflicts with both stock engine names. Keep Fedora's stock-engine `Obsoletes` bounds in its recipe so normal upgrades replace the engine. `scripts/check-packaging.js` checks the engine contract separately from shell recipes.
- Publish a coherent committed engine candidate before its floor reaches main. Every git channel must obtain it, and the public Nix revision must contain matching locked inputs and patches. The fleet owner installs it on nested executors and checks the selected executable before nested work. `scripts/check-packaging.js --engine-availability` and `--installed-engine` judge these prerequisites; unknown evidence exits 77. The default recipe check stays offline. VGS has no server-side publication gate.
- Judge Debian availability for the requesting tree's exact version tag and signed assets. Tagged installers use their own archive's engine declaration. Release packages take a dependency change at the next containing release tag; a recipe-only Fedora rebuild does not bypass `packaging/fedora/srpm.sh`'s tag check. `DEVELOPMENT.md` § Release owns publication procedure.
- Keep Nix installation and graphics ownership on NixOS. Refuse a Nix-store engine on other hosts before invoking it. Keep builds pure and add no non-NixOS graphics bridge. `scripts/test-vgshell.sh` checks the host refusal.
- Migrate engines through `self.js::migrateEngine` and the existing package runner, including unchanged-HEAD and same-version retries. Prepare the target engine before changing the VGS tree. Keep package and elevation questions in the floating terminal; helper installation uses `bin/lib/aur-helper.sh`. `scripts/test-vgshell-self.sh` checks migration and retries.
- Permit `packaging/install-system.sh` to call `migrateCurlStage` only for the exact curl self-update layout. Ordinary staging, other prefixes and a missing curl `current` authorize no host package action. Keep migration payloads owned by the terminal presenter until completion, including late launch or caller cancellation; do not lend it the self lock. `scripts/test-install-tree.sh` and `scripts/test-vgshell-tui.sh` check these boundaries.
- Enable Fedora's fixed VGS repository through the closed system step, keeping its cpptrace repository dependency. An unknown repository probe refuses migration. `scripts/test-vgshell-system.sh` checks the step.
- Verify package ownership and VGS distributor identity after installation. Package-manager success alone permits no tree switch. Cancellation, failure, unknown ownership or an old release refuses it; retain completed package changes for retry. Use no migration marker or second engine path ([D107](../decisions/D107-format-change-ships-its-migration.md)). `scripts/test-vgshell-self.sh` checks this boundary.
- Verify Debian assets with apt's `sqv`, a temporary public-only keyring and the pinned fingerprint in `engine.js`. Require the exact declared amd64 version and VGS identity. Bootstrap no gpg and read no user keyring. `scripts/test-install-sh.sh` checks this trust boundary.
- Keep Nix engine roots immutable and outside staging. Bind release roots to release identity and checkout roots to original path plus exact commit. Retain current, previous and running roots, and checkout roots when the running revision is unknown. Never modify profiles, retarget roots, delete store paths or collect garbage. `scripts/test-flake.sh` and `scripts/test-vgshell-self.sh` check retention.
- Make no retroactive trust claim for older clients: they trust downloaded installer bytes under their existing contract. Signed engine verification applies only to clients that implement it; Nix dependency identity comes from pinned inputs. Review holds this limit.
- Adopt each upstream release in one work item: move the pin, reapply local patches and pass package and runtime checks. Identify patches removed because upstream carries their fixes. The overseer reports the newest upstream release against the pin and files a pin-move item the same day a release passes it. Review holds this maintenance rule.
- Retire patches and dedicated recipes only when upstream fixes request-socket and log-filter defects (#947, #1285), supplies managed child lifetime and honors FileView error and absence semantics. Raise the floor and prove replacement from `vgshell-quickshell` in that same change. Review holds retirement.

### Licence

- The SPDX licence expression of a VGS shell package is `MIT AND OFL-1.1 AND ISC AND Apache-2.0 AND CC-BY-SA-4.0`.
- Keep that expression in every shell recipe. `scripts/check-packaging.js` reads the declaration above and checks parity. The engine retains Quickshell's licence.

### Version

- Read the version from `VERSION` beside `bin/`, never a package manager. `scripts/test-vgshell-version.sh` checks it.
- Retain the runner's start version for running-versus-installed comparisons. `scripts/test-vgshell-version.sh` checks the report; the CLI owns its output fields.

### Release tarball

- Pack a commit, never the working tree, through `scripts/lib/release-tarball.sh`. `scripts/test-release.sh` checks parity.

### Installation ownership

- Make git calls in `bin/vgshell` and give their facts to `self.js` for decisions. A failed status step remains an error with earlier facts intact; never infer currentness from a failed compare. `scripts/test-vgshell-self.sh` checks the result.
- Judge a git package behind by changed installed paths through `self.js`'s one list. Incomplete compare evidence or lost ancestry counts as behind. `scripts/test-vgshell-self.sh` checks this conservative boundary.
- Let Updates run only the action the status judge selects. Keep release-package updates with the package manager and Nix updates with the owning system or home configuration. Offer helper installation only for a behind pacman git package without an AUR helper. `scripts/test-updates-pipeline.sh` checks routing.
- Keep the new, previous and running shell trees after update. Repair a checkout from its current commit; repair curl into a fresh versioned tree; repair a package through reinstall. Keep Nix and unknown-owner plans by hand with the cause. `scripts/test-vgshell-self.sh` checks repair and retention.
- Fetch without hooks, prompts, askpass or `FETCH_HEAD`, and with a timeout. `scripts/test-vgshell-outdated.sh` checks isolation.
- Keep the curl installer one brace group so an incomplete download executes nothing. Refuse root, non-Linux hosts, system packages and foreign user entrypoints before writing. `scripts/test-install-sh.sh` checks these boundaries.
- Fetch over HTTPS with TLS verification, verify the matching checksum and switch `current` only by rename. The installer removes no version directory and starts no shell, writes no unit and edits no Hyprland configuration. `scripts/test-install-sh.sh` checks installation.
- Install required runtime packages before the engine so every prompt has its tools. Use the staged tree's presenter and runner for required installs. Keep installer floor and package tables aligned with their runtime declarations. `scripts/test-install-sh.sh` checks these boundaries.
- Admit `VGS_RELEASE_API` overrides only in tests and only under the installer's local-file or self-update's loopback contract. `scripts/test-install-sh.sh` and `scripts/test-vgshell-self.sh` check refusal elsewhere.

## The canonical example

Copy `packaging/arch/vgshell/PKGBUILD` for a channel. Add ownership and update outcomes to `scripts/test-vgshell-self.sh` when extending installation methods.

## Revisit when

VGS ships architecture-specific binaries, a supported distribution reaches a runtime floor, autostart warrants a Home Manager module, or self-update gains the installer's signature check.

## Not governed

Release operations belong to `DEVELOPMENT.md` § Release. `scripts/check-readme.js` owns README installation consistency. Runtime lifecycle belongs to [runtime.md](runtime.md).
