# Fedora

Covers: packaging/fedora/, .copr/Makefile, scripts/test-fedora-srpm.sh, scripts/fedora-container.sh

VGS ships to Fedora in 0.1.x, not 0.1.0, through COPR `vanillagreen/vgshell`. On 2026-10-02 the COPR API listed only that project for the owner: it has the chroots and repos of `packaging/fedora/copr-project` and the packages `vgshell` and `vgshell-git`, and no build has run. The first builds wait for the `v0.1.0` tag, the 0.1.0 release tarball and a passing `scripts/fedora-container.sh`.

## Packages

- `packaging/fedora/vgshell.spec` builds `vgshell` from the release tarball, `vgshell-<VERSION>.tar.gz` of release `v<VERSION>`. Its `Version` is `VERSION`'s line, and its newest `%changelog` entry is that version.
- `packaging/fedora/vgshell-git.spec` builds `vgshell-git` from a commit of `main`. Its version is `X.Y.Z^<count>.git<hash>`, the RPM form of the describe form `vgshell --version` prints in the same checkout, so `0.1.0.r215.gcffc73` becomes `0.1.0^215.gitcffc73`. RPM sorts `X.Y.Z^<count>` above `X.Y.Z` and below the next release, Fedora's rule for a snapshot after a release. Before the first release tag the count runs from the first commit and falls to 0 at the tag, so `vgshell-git` is published only after `v0.1.0` exists; from then on the count only grows.
- Neither spec has `Conflicts`, `Obsoletes` or `Provides`, and `scripts/check-packaging.js` refuses any such tag. The two packages own the same files, so dnf refuses to install one beside the other until the user removes the installed one.
- Both are `BuildArch: noarch`, install through `packaging/install-system.sh` with `PREFIX=/usr` and `SYSCONFDIR=/etc`, and run `scripts/check-install-tree.sh` with both in `%check`. A shipped file missing from the manifest fails the build.
- `%files` lists the browser theme writer `%{_bindir}/vgshell-browser-policy` and its sudoers rule `%{_sysconfdir}/sudoers.d/vgshell-theme-browser` with `%attr(0440,root,root) %config(noreplace)`, so every user recolours Chromium-family browsers with no setup step ([theme-browsers.md § Chromium](theme-browsers.md#chromium)). The `sudoers.d` directory stays sudo's. It also lists the XDG autostart entry `%{_sysconfdir}/xdg/autostart/vgshell.desktop` with `%config(noreplace)` ([distribution-autostart.md](distribution-autostart.md)). `scripts/check-packaging.js` refuses a spec without any of the three lines.
- `%post` is the same in both specs. It prints the [first-install text](distribution.md#first-install-text) from `%{_datadir}/vgshell/bin/lib/post-install.txt` when `$1` is 1, a first install, and nothing on an upgrade.
- Fedora's build rewrites `#!/usr/bin/env bash`, `node` and `python3` to absolute interpreter paths, and RPM derives requirements on those interpreters. The manifest check lists files, not their content, so the rewrite passes it.

## Dependencies

- The block between `# begin runtime dependencies` and `# end runtime dependencies` is the same in both specs. `scripts/check-packaging.js` computes its `Requires` and `Recommends` lines from data and fails on a missing, extra or different line ([distribution.md § Recipe check](distribution.md#recipe-check)).
- Each row of the preflight floor in `bin/vgshell` is a `Requires`, with `>=` its floor: `quickshell >= 0.3.1`, `hyprland >= 0.56`, `nodejs >= 1:18`, `python3` and `git`. The package name is the `dnf` name `config/requirements.json` gives the row's probe command, else the row's tool name.
- Every other required entry of `config/requirements.json` and of the shipped plugins' `requirements` is a `Requires` by its `dnf` name: `util-linux-core` for `flock` and `util-linux` for `setpriv`, which Fedora ships only in the full package. Every optional one is a `Recommends`, which dnf installs by default and lets a user remove. A required requirement with no `dnf` name is an explicit channel gap beside [the recipe check](distribution.md#recipe-check). An optional requirement with no `dnf` name has no Fedora line.
- The shared [recipe check](distribution.md#recipe-check) also requires the declared runtime library packages.
- Fedora's `nodejs` packages carry epoch 1, as `nodejs22` 1:22.23.1 does, so the node floor is written `1:18`. Written `18`, it reads as epoch 0, and any epoch-1 node would pass it, 1:16 included. The `epochs` field of the checker's `dnf` channel holds each non-zero epoch and refuses a floor with another, and the container test compares every floor's epoch with the installed package's.
- The Quickshell floor matters on Fedora: Fedora itself ships `quickshell` `0.2.1^git20260209.dacfa9d`, and without `>= 0.3.1` dnf would take it.

## Third-party COPRs

Fedora carries no Quickshell at the floor and no Hyprland at all, so the project depends on two COPRs VGS does not control. `packaging/fedora/copr-project` lists them with the project's chroots.

| COPR | Package | On 2026-09-28 | Risk |
|---|---|---|---|
| `errornointernet/quickshell` | `quickshell` | 0.3.1-2, built 2026-09-27, fedora-43 to rawhide | One maintainer. A late 0.3.x or 0.4 build holds Fedora users back. |
| `sdegler/hyprland` | `hyprland` | 0.56.2-2, built 2026-08-29, fedora-43 to rawhide | One maintainer. The older `solopasha/hyprland` stopped at 0.49.0, below the Lua floor. |

- The versioned `Requires` stop dnf from pairing VGS with an older Quickshell or Hyprland from any repository, and `vgshell run`'s preflight names a floor miss at start.
- The project lists both as `additional_repos`, which reach the build chroot, and as runtime dependencies, which `dnf copr enable vanillagreen/vgshell` offers to enable with it. The noarch build itself needs neither.
- A new Fedora release's chroots join the project only after `scripts/fedora-container.sh --image registry.fedoraproject.org/fedora:<N>` passes.

## Source RPMs

- `packaging/fedora/srpm.sh --spec SPEC --outdir DIR` writes a package's source RPM from the checkout it sits in. For `vgshell` the checkout must sit at `v<VERSION>`; it downloads the release tarball over HTTPS, or takes `--tarball FILE`, and refuses a tarball whose `vgshell-<VERSION>/VERSION` is another version. For `vgshell-git` it packs `HEAD` with the release tarball builder ([distribution.md § Release tarball](distribution.md#release-tarball)), prepends `vgs_version` and `vgs_commit` to a spec copy and appends one `%changelog` entry of the commit's author and UTC date. That date is the build's `SOURCE_DATE_EPOCH`. It refuses a shallow clone, whose commit count is short.
- `.copr/Makefile` is COPR's `make_srpm` entry. COPR runs it as root in a chroot over a clone another user owns, so `srpm.sh` trusts its own checkout through `GIT_CONFIG_*` and keeps any the caller set.

## Validation

- `scripts/validate` runs `scripts/check-packaging.js`, its controls `scripts/test-check-packaging.js`, and `scripts/test-fedora-srpm.sh`, which drives `srpm.sh`, `.copr/Makefile` and the container runner's host side with stub RPM tools, since the host has none.
- `scripts/fedora-container.sh` is the install test. It needs podman and the network, so it runs by hand, not in `validate`, and exits 77 when it cannot run. On the host it packs the release tarball of `HEAD` with the release's builder. In a clean `fedora:44` container it enables the listed COPRs, writes the `vgshell-git` source RPM through `.copr/Makefile`, tags its scratch clone and writes the `vgshell` source RPM from that tarball, rebuilds both as an unprivileged user and fails on any RPM warning. Then it installs `sudo` and `vgshell`, checks that dnf's output holds every line of the first-install text, checks `vgshell --version`, the `/usr/bin/vgshell` link and `rpm -V`, and runs the preflight twice. It checks the browser theme writer and its rule as the Arch test does: owner, mode, `visudo -cf`, the grant to every user and `vgshell theme setup` with and without a stand-in `chromium`. `vgshell run` must refuse at `preflight=hyprland have=unknown`, since no Hyprland runs, so the installed Quickshell met its floor. A stand-in `hyprctl` reporting the installed Hyprland package's version lets `vgshell restart` pass the whole floor and refuse at `shell=not-running`. Last it removes `vgshell` with `dnf remove`, installs `vgshell-git`, checks its version and runs the same checks.
- On 2026-09-28 it passed on `fedora:44` with Quickshell 0.3.1-2 and Hyprland 0.56.2-2, for `vgshell` 0.1.0 and a `vgshell-git` `0.1.0^<count>.git<hash>` snapshot of the change that added it.

## Publication

These commands, run with a COPR API token, set up the project and its two packages. They also recreate it:

```bash
copr-cli create vgshell --chroot fedora-44-x86_64 --chroot fedora-44-aarch64 \
  --repo copr://errornointernet/quickshell --repo copr://sdegler/hyprland \
  --runtime-repo-dependency copr://errornointernet/quickshell \
  --runtime-repo-dependency copr://sdegler/hyprland
copr-cli add-package-scm vgshell --name vgshell-git --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit main --spec packaging/fedora/vgshell-git.spec --method make_srpm --webhook-rebuild on
copr-cli add-package-scm vgshell --name vgshell --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit v0.1.0 --spec packaging/fedora/vgshell.spec --method make_srpm
```

Once the three conditions of the opening paragraph hold, the owner runs the first builds:

```bash
copr-cli build-package vgshell --name vgshell
copr-cli build-package vgshell --name vgshell-git
```

- `vgshell-git` has webhook rebuild on, but on 2026-10-02 the GitHub repository does not yet send the project's webhook. The owner adds it in the repository's webhook settings only after the `v0.1.0` tag exists. `packaging/fedora/srpm.sh` builds `vgshell-git` without a release tag, so a webhook added earlier publishes a pre-tag `vgshell-git` on the next push to `main`. Its count sorts above the first builds after the tag ([§ Packages](#packages)), and a user who installed it gets no update until the count passes it.
- Each later release sets `vgshell.spec`'s `Version`, `Release` and `%changelog` with `VERSION`, then runs `copr-cli edit-package-scm vgshell --name vgshell --commit vX.Y.Z` and `copr-cli build-package vgshell --name vgshell`. The GitHub webhook, added after the `v0.1.0` tag, rebuilds `vgshell-git` on every push to `main`.
- A user installs with `sudo dnf copr enable vanillagreen/vgshell`, accepting its two dependencies, then `sudo dnf install vgshell`.
- Once the first build installs in a clean container from the published project, the README gains a Fedora install command.

## Omarchy comparison

- Omarchy is Arch-only. It publishes its packages to its own pacman repository, `pkgs.omarchy.org`, in stable, rc and edge channels (`default/pacman/pacman-*.conf` at `basecamp/omarchy` `main`, read 2026-09-28), and has no Fedora channel. VGS takes the same shape on Fedora: one repository the project owns, COPR `vanillagreen/vgshell`, with a release package and a `main` package in place of channels. Unlike Omarchy, VGS does not package its runtime there: it depends on the two third-party COPRs, and its versioned `Requires` catch a lag.
