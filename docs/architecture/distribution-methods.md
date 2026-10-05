# Install methods

Covers: bin/lib/self.js, scripts/test-vgshell-self.sh

`vgshell self status` names how this tree was installed and whether its channel offers something newer. `vgshell self update` updates the tree where VGS owns it. `bin/lib/self.js` is the one judge of the method and of `behind`; `bin/vgshell` makes every git call and hands it the facts. The command's header in `bin/vgshell` states every output and refusal.

## The four methods

The judge tries each method in this order, on the real path of the tree beside `bin/`:

| Method | The tree is | `current` | `latest` | Behind while |
|---|---|---|---|---|
| `checkout` | the top level of its own git checkout, as `vgshell version` decides | `HEAD` in the describe form | the upstream commit in the describe form, after a fetch | the upstream holds commits `HEAD` lacks |
| `nix` | inside the Nix store: `$NIX_STORE_DIR`, else `/nix/store` | `VERSION` | the newest release | the newest release is newer |
| `curl` | the directory `${XDG_DATA_HOME:-~/.local/share}/vgshell/current` resolves to, a directory of `…/vgshell` | `VERSION` | the newest release | the newest release is newer |
| `package` | owned, through its `VERSION`, by the primary package manager, as the package `vgshell` or `vgshell-git` | the package's installed version | `vgshell`: the newest release; `vgshell-git`: the commit `main` points at | `vgshell`: the newest release is newer; `vgshell-git`: `main` is not the commit its version names |

- Any other tree is refused as `method=unknown path=<root>`. So is a package other than `vgshell` and `vgshell-git`, as `package=<name> manager=<id> reason=not-vgs`.
- The owner query is the package layer's: `vgshell pkg owner <path>` runs the primary manager's owner and installed queries from `shell/Core/PackageManagers.js` ([packages.md § Queries](packages.md#queries)). pacman, apt and dnf answer both; xbps and emerge name the owner only.
- A `vgshell-git` version ends in the commit it was built from: the AUR form `X.Y.Z.r<N>.g<hash>` and the COPR form `X.Y.Z^<N>.git<hash>`. Any other `vgshell-git` version is refused as `reason=not-a-version`.
- A checkout's fetch is `plugin outdated`'s fetch ([manager.md § Outdated](manager.md#outdated)): no hook, no prompt, no askpass, no `FETCH_HEAD`, ended at 10 s. `main`'s commit for `vgshell-git` is `git ls-remote https://github.com/vanillagreencom/vgshell.git refs/heads/main` under the same rules. The package recipe builds from that URL.
- The newest release is `GET https://api.github.com/repos/vanillagreencom/vgshell/releases/latest`, ended at 10 s. Its tag must be `v<X.Y.Z>`. A repository with no release is `release=none`.

## Output

- `vgshell self status --json` prints one line `{ version, method, package, current, latest, behind, error }`. `version` is `VERSION`'s line. `package` is `vgshell`, `vgshell-git` or null. `behind` is a boolean.
- The text form prints the same fields that are set, as `key=value` words on one line.
- A step that fails does not fail the command. Its keyed refusal line becomes `error`, `latest` and `behind` are null, and the exit status is 0. The fields read before the failure stay: a checkout whose fetch fails still names its `current`.
- The planned consumer is the Updates plugin's check, which reads the JSON form beside the other update sources.

## Update

- A checkout fast-forwards to its upstream, as `plugin update` does, with no diff and no question: VGS is the program the user runs, not third-party code. A modified checkout, a missing upstream and an upstream that rewrote its history are refused with `plugin update`'s keys.
- A curl install is replaced by the newest release under `${XDG_DATA_HOME:-~/.local/share}/vgshell/.self.lock`. A second update is refused `self=busy` with exit 75. The steps are the curl installer's: download `vgshell-X.Y.Z.tar.gz` and `SHA256SUMS` from the release's assets into a staging directory under `…/vgshell`, check the archive's sha256 against its one `SHA256SUMS` line, unpack it, require one top directory `vgshell-X.Y.Z` whose `VERSION` is `X.Y.Z`, run its own `packaging/install-system.sh`, move the runtime tree to `…/vgshell/X.Y.Z`, and rename a new `current` link over the old one. Three trees stay: the new one, the one the command ran from, and the one the running shell was started from, read from its command line (`qs -p <tree>/shell`). So a shell keeps its files until it restarts, even one whose earlier restart was refused. Every other version directory is removed. A running shell whose command line names no tree refuses the update as `shell=unreadable pid=<pid>`. A failure removes the staging directory and leaves `current` as it was.
- A download is https, at most 128 MiB for the archive, and ended at 120 s. VGS publishes no release signing key yet, so the update checks the sha256 alone.
- A package and a Nix tree are refused, `method=package package=<name> manager=<id>` and `method=nix`. The package manager or the flake owns the tree, and `vgshell self update` changes neither.
- After an update of a checkout or a curl install, the updated tree's `bin/vgshell-migrate` runs its pending one-time migrations; a failed one prints `vgshell: migrate=failed status=<n>` and runs again at the next `vgshell run`, and the update stands: [migrations.md](migrations.md).
- After an update, a running shell restarts from the updated tree's `vgshell`. The restart's status becomes the command's. With no shell running, the last line is `shell=not-running`.
- `VGS_RELEASE_API` replaces the API base only in a test run, and only with `http://127.0.0.1:<port>`. Any other value is refused, so no environment redirects a real update.

## Verification

`scripts/test-vgshell-self.sh` builds one fixture tree per method: a clone of a local bare repository, a curl layout under a fixture `XDG_DATA_HOME`, a package tree owned by a stub `pacman` under a fixture Arch os-release bound under `unshare -rm`, and a tree under a fixture `NIX_STORE_DIR`. The newest release is a local release fixture served on 127.0.0.1, and a stub `qs` whose pid sits in the instance lock stands in for a running shell. Its controls are copies of `self.js` that call every tree a checkout, accept a loopback API outside a test run, skip the checksum comparison, or remove the running shell's tree. `scripts/test-vgshell-pkg-table.js` pins the owner and installed queries.

## Omarchy comparison

- Omarchy's development channel is a git checkout at `$OMARCHY_PATH`. `omarchy-update-available` fetches it with a 10 s timeout and counts the commits behind its upstream, and `omarchy-update-dev` runs `git pull --ff-only`. For a package it filters `checkupdates` for `omarchy` or `omarchy-dev`. VGS takes the checkout flow, and supports three more install forms: the `vgshell` and `vgshell-git` packages, a curl install and a Nix tree. VGS reads `vgshell-git`'s commit itself, because an AUR helper reports a `-git` package behind only when its recipe's version changes. A checkout with no upstream is an error in VGS, where Omarchy skips it, so the Updates plugin never shows a silent "up to date".
