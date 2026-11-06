# VGS development

Use Linux with the runtime dependencies declared in [`bin/vgshell`](bin/vgshell). The runner checks them before starting. Package dependencies come from the recipes under [`packaging/`](packaging/).

## Run

```sh
bin/vgshell run                              # the shell from this checkout, in a Hyprland session that runs no other VGS
scripts/qml-smoke.sh --rows bar,launcher     # the shell inside the nested sandbox, running the named rows, the core rows and the rows those read
scripts/sandbox-shots.sh gallery settings    # PNGs of named scenes from the sandbox, under tmp/
```

Follow [runtime.md § Process](docs/architecture/runtime.md#process) for live-session safety and [validation.md § Test isolation](docs/architecture/validation.md#test-isolation) for sandbox entry.

## Test

```sh
scripts/validate                             # the checks the changes since the last pass reach
scripts/validate --list                      # the same selection, printed and not run
scripts/validate --changed <commit>          # a fix round: the checks the changes since that commit reach
scripts/validate unit --full                 # one whole area; unit needs Qt and no Wayland session
scripts/validate package                     # the Arch recipes in a rootless podman container
scripts/smoke/gpu-fence.sh -- scripts/test-x.sh # one test in its own world
```

Exit 77 means a check could not run and is not a pass. The [nested sandbox](docs/architecture/validation.md#nested-sandbox) needs `XDG_RUNTIME_DIR`, a non-AMD render node and no `WAYLAND_DISPLAY`. Before adding or changing a check, read [scripts/AGENTS.md](scripts/AGENTS.md) and [validation.md](docs/architecture/validation.md).

[`scripts/validate`](scripts/validate) owns check selection and result reuse. [validation.md § Selection](docs/architecture/validation.md#selection) states the boundary.

For detached validation outside an agent harness, keep HUP, INT and QUIT at their defaults so the signal tests receive them:

```sh
setsid env --default-signal=HUP,INT,QUIT bash -c 'echo $$ >tmp/run.pid; exec scripts/validate offline' </dev/null >tmp/run.log 2>&1 &
```

Wait with `tail --pid=PID -f /dev/null` on the recorded PID, not `$!` or a process-name match. `setsid` can return before the validation process ends.

Keep temporary scripts under `tmp/`: an untracked file under `scripts/` is an unmapped input and selects the full area. A copy of `scripts/sandbox-shots.sh` under `tmp/` pins its `repo=` line to the checkout, since the script finds the checkout from its own path.

The [nightly workflow](.github/workflows/nightly.yml) runs reporting-only validation on `main` while the repository variable `NIGHTLY` is `on`. Neither it nor the [kendex refresh workflow](.github/workflows/kendex-refresh.yml) runs on a push or pull request. The refresh workflow owns package updates; adopt it through kendex rather than edit it. Use [`scripts/main-run.sh`](scripts/main-run.sh) for the main-checkout batch, including checks that need a local graphics device.

## Debug

```sh
bin/vgshell log                              # the running shell's log, through qs log
scripts/qml-smoke.sh --keep --rows <row>     # keep the sandbox after the row; the shell's log is under its runtime dir
scripts/sample-shell-memory.sh               # sample the live shell's memory until interrupted, read-only
```

The [smoke harness](scripts/smoke/harness.sh) sets `MALLOC_CONF=junk:free` for Quickshell's jemalloc allocator. Use the same setting when reproducing a memory fault, then symbolize the crash with `gdb -iex 'set debuginfod enabled on'`.

## Smoke rows and shots

- Run a row through `scripts/validate qml --changed <base>` or name it to `scripts/qml-smoke.sh --rows`. The runner adds its core rows and the rows those read; do not invoke row files directly.
- Give a new row's helpers a prefix no other row uses, since rows share a Bash shell.
- Before enabling Jarvis in a row that reads focus or pixels, call `jarvis_setup_requirements` from `scripts/smoke/rows/jarvis.sh`. This supplies required command stand-ins so the requirement notice does not take focus.
- Compare the printed instance-log paths when scoped and full runs disagree. `diagnostics` reads the current shell's log; a shell restart changes which warnings it sees.
- Put scripted edits in a separate file so their quoting cannot end at a delimiter inside the edited script.
- Never edit a script while a run is reading it: bash reads a script as it runs.
- Name the before tree of `sandbox-shots.sh --rev` by the change's parent, `<change>^`. `origin/main` becomes the after tree once the change lands.
- A screenshot sheet's index and each caption state the capture mode (live shell, sandbox capture of the real page on the branch, or prototype stand-in), the viewport width and every known difference from the production page. A prototype that composes its own page header draws the real page frame or names the difference.
- For a pixel comparison, report a same-tree control beside the base-to-HEAD comparison: `magick A B -compose difference -composite -colorspace gray -threshold 0 -format '%[fx:round(mean*w*h)]' info:`.
- Take a motion frame from its own pixels. For a settled frame, require the probe reading to settle and the image to match the preceding frame.
- Shoot a real plugin's widget, not the empty `acme.probe` fixture.
- `bin/vgshell-system` reads the device fakes' tree in the sandbox, so a system step that probes a host file finds it absent. The scene plants that file under `$devices_system_root` before it enables the plugin.
- The stand-in terminal starts no terminal. A floating TUI shot starts `kitty` with the presenter's argv in its scene, one theme per run, and copies in only the `gum` target: the `kitty` target's reload signals every kitty the user runs.

## Jarvis self-test

Use [`scripts/jarvis-selftest.sh`](scripts/jarvis-selftest.sh) for a real Jarvis turn in the nested sandbox. Its header owns the inputs and record format; [validation.md § Jarvis self-test](docs/architecture/validation.md#jarvis-self-test) owns the rules. `scripts/validate` does not run it.

```sh
# Prepare the local voice under a scratch HOME. The small tier supplies the --tts voice.
env -u XDG_STATE_HOME -u XDG_DATA_HOME HOME="$PWD/tmp/jarvis-local" python3 -I shell/plugins/vgs.jarvis/setup-local install small
export JARVIS_LOCAL_MODELS="$PWD/tmp/jarvis-local/.local/share/vgshell/jarvis/local/models"
export JARVIS_LOCAL_PYTHON="$PWD/tmp/jarvis-local/.local/share/vgshell/jarvis/local/venv/bin/python"

node shell/plugins/vgs.jarvis/backend/accounts.js --tree "$PWD" sign-in-folders claude 120   # each Claude Code sign-in folder, then its id
scripts/jarvis-selftest.sh --wav shell/plugins/vgs.jarvis/fixtures/probe.wav --brain <id>   # a recorded voice
scripts/jarvis-selftest.sh --tts "What time is it?" --brain <id>                            # a sentence the pinned voice speaks
scripts/jarvis-selftest.sh --type "What time is it?" --brain <id>                           # a typed line
scripts/jarvis-selftest.sh --suite volume --brain <id>                                       # one acceptance case
```

Choose the account id from the `sign-in-folders` output. Prepare local voice inputs before the self-test; it reads that setup rather than installing it. Its header names the additional device-fake and filtered-bus dependencies.

## Regenerate

```sh
node scripts/check-readme.js --write-plugins   # README § Plugins
scripts/readme-shots.sh                        # README images from docs/images/plugins/shots.tsv
DESTDIR="$PWD/tmp/install-tree" PREFIX=/usr packaging/install-system.sh
scripts/check-install-tree.sh --write "$PWD/tmp/install-tree" /usr   # after a shipped file is added
scripts/measure-shader.sh --calibrate scripts/shader/ceilings.json --runs 3   # the shader ceilings
```

The plugin table comes from the manifests, including their descriptions. Regenerate it when a plugin is added, removed, renamed or its description changes. The root README uses the Themes browser image from the same screenshot table as the plugin READMEs. Regenerate affected scenes with `scripts/readme-shots.sh SCENE`; do not hand-edit the generated plugin table or rendered images. [`scripts/check-readme.js`](scripts/check-readme.js) and [`scripts/check-readme-images.py`](scripts/check-readme-images.py) check consistency.

Use a fresh scratch `DESTDIR` for install-tree staging.

## Containers

```sh
scripts/arch-packages.sh                     # build and install both Arch recipes
scripts/fedora-container.sh --image fedora:44   # install the Fedora package from its source RPM
scripts/test-flake.sh                        # build the flake in the nix container
scripts/readme-install.sh                    # every README install command, against what users get from main
```

Each needs podman and the network, and exits 77 when it cannot run. Run `scripts/readme-install.sh` by hand before a release.

## Write a plugin

Read the [plugin architecture](docs/architecture/overview.md), then load the `vgs-plugin` skill for scaffolding and validation.

## Release

The maintainer cuts every release from their own machine, with their own gpg key, GitHub login and AUR SSH key. VGS has no CI workflow for releases or package publication: [D040](docs/decisions/D040-one-shared-install-tree.md).

[`scripts/release`](scripts/release) owns GitHub release assets; [`scripts/publish-aur.sh`](scripts/publish-aur.sh) owns AUR publication. Their `--help` output defines prerequisites, dry-run behavior and refusals. Agents use `--dry-run` only; signing and publication remain with Jarvis.

At each landing on `main` that changes `packaging/arch/vgshell-git/`, the overseer publishes `vgshell-git` to the AUR through `scripts/publish-aur.sh` on the maintainer's machine. The landing notice names the AUR commit or the refusal. A refusal leaves the publication acceptance box open.

For an actual recipe change, follow [distribution.md § Channels](docs/architecture/distribution.md#channels): raise the stored pkgver to the current-main `pkgver()` output, or increase pkgrel when that output has not changed. Never publish a recipe just for a pkgver bump. From `packaging/arch/vgshell-git/`, run:

```sh
makepkg -od && makepkg --printsrcinfo > .SRCINFO
```

Commit the rewritten PKGBUILD and regenerated `.SRCINFO` with the recipe change. `scripts/publish-aur.sh` needs pacman's `vercmp` and refuses changed `vgshell-git` content whose version does not increase over AUR HEAD, including in a dry run.

The overseer also publishes `vgshell-quickshell` when its recipe or local sources change. Follow [distribution.md § Quickshell engine](docs/architecture/distribution.md#quickshell-engine) for the shared pin, patches and channel boundary. Before raising the engine floor on `main`, commit a coherent candidate and push its revision without advancing `main`. Run the offline recipe check, publish the AUR engine from that checkout, and build the COPR engine from that exact public revision for every target in `packaging/fedora/copr-project`. Wait for the RPMs to appear in repository metadata. The public candidate must also contain the matching flake lock and shared patches.

For Debian checkout consumers, publish the engine asset for the candidate tree's exact `VERSION` tag, with its signature and checksum assets, through the signed release before landing a new floor. Tagged installers retain their own archive's engine declaration. AUR `vgshell` and Fedora `vgshell` receive the dependency at the next VGS release tag containing the change.

Have the fleet owner install the published engine on every executor that will run nested validation. Check the actual executable and package ownership; an installer exit alone does not prove replacement. Then run the read-only checks:

```sh
node scripts/check-packaging.js --engine-availability --source-ref <candidate revision> # final candidate
node scripts/check-packaging.js --installed-engine                                    # each executor
```

Only after both checks pass does the landing workflow advance `main`. Exit 77 leaves publication or installation unverified. The default `node scripts/check-packaging.js` stays offline, including when the AUR publisher calls it before publication.

Jarvis cuts a patch release (`X.Y.Z`, `Z > 0`) or a minor release for the owner when the work needs it, after one clean main batch run with measured timings. Only an `x.0` release waits for the owner. Group steps that need the owner's hand, such as a passphrase or sign-in, into one question.

### Credentials

Use the signing key whose fingerprint `install.sh` declares and a GitHub account that may create releases in `vanillagreencom/vgshell`. Register the AUR account's RSA public key before publication; give the publisher its private-key path through `AUR_SSH_KEY_FILE`. The publisher uses the pinned host keys in `packaging/aur-known-hosts`, not the maintainer's SSH configuration.

### Versions

- `VERSION` holds the release's SemVer version, and the tag is `v` followed by it: [distribution.md § Version](docs/architecture/distribution.md#version).
- While VGS is at 0.x, a minor bump marks a breaking change to `shell.json`, the plugin API, the manifest or the theme package format. A patch bump marks fixes only.
- Plugin manifest versions change independently of `VERSION`.

### Flow

1. Prepare the version. `scripts/check-packaging.js` refuses a recipe whose version differs from `VERSION`, so every file below moves to `X.Y.Z` in the same commit:
   - `VERSION`: the one line `X.Y.Z`.
   - `packaging/arch/vgshell/PKGBUILD`: `pkgver=X.Y.Z`, `pkgrel=1` and `sha256sums=('SKIP')`. The sum stays `SKIP` until the archive exists; a sum left from the previous release passes the check but makes `scripts/publish-aur.sh` hold `vgshell` back.
   - `packaging/arch/vgshell/.SRCINFO`: regenerated from that PKGBUILD, which the check compares byte for byte.
   - `packaging/fedora/vgshell.spec`: `Version: X.Y.Z`, `Release: 1%{?dist}`, and a new first `%changelog` entry whose header line ends in `- X.Y.Z-1`.
   - The version's changelog entry.

   ```bash
   printf '%s\n' X.Y.Z >VERSION
   # packaging/arch/vgshell/PKGBUILD: pkgver=X.Y.Z, pkgrel=1, sha256sums=('SKIP')
   (cd packaging/arch/vgshell && makepkg --printsrcinfo > .SRCINFO)
   # packaging/fedora/vgshell.spec: Version, Release and the new %changelog entry
   node scripts/check-packaging.js
   ```

2. Run `scripts/validate --full` once. A release is an explicit full sweep. Then commit and push. When this release supplies a new engine floor, publish the candidate revision without advancing `main` and complete the engine availability and fleet installation order above before landing it.
3. Tag and push the tag:

   ```bash
   git tag -s vX.Y.Z -m "VGS X.Y.Z"
   git push origin vX.Y.Z
   ```

   The tag must be on `main`'s history: `bin/vgshell --version` in a checkout prints the newest release tag reachable from it. If you cut the release from an older commit, merge the release branch into `main` with `git merge -s ours --no-ff origin/release/vX.Y.Z` and push it. This merge keeps `main`'s tree unchanged. `git diff HEAD^1 HEAD` prints nothing, and `git merge-base --is-ancestor vX.Y.Z HEAD` exits 0. The release lane pushes this merge before its finish notice.

4. Make the release:

   ```bash
   scripts/release --dry-run X.Y.Z
   scripts/release X.Y.Z
   ```

5. Pin that sha256 in the `vgshell` recipe, check it and push it. `scripts/check-packaging.js` refuses `SKIP` once the tag exists.

   ```bash
   # packaging/arch/vgshell/PKGBUILD: sha256sums=('<the release: sha256 value>')
   (cd packaging/arch/vgshell && makepkg --printsrcinfo > .SRCINFO)
   node scripts/check-packaging.js
   git commit -am "packaging: pin the vgshell X.Y.Z tarball" && git push origin main
   ```

6. Publish the engine, then both shell recipes. A deferred package leaves publication incomplete.

   ```bash
   scripts/publish-aur.sh --dry-run vgshell-quickshell vgshell vgshell-git
   AUR_SSH_KEY_FILE=<the AUR account's private key> scripts/publish-aur.sh vgshell-quickshell vgshell vgshell-git
   ```

7. Publish the Fedora engine before the shell packages that depend on it: [§ Fedora](#fedora). Set `vgshell.spec`'s `Version`, `Release` and `%changelog` with `VERSION`, then run `copr-cli edit-package-scm vgshell --name vgshell --clone-url https://github.com/vanillagreencom/vgshell.git --commit vX.Y.Z --spec packaging/fedora/vgshell.spec --method make_srpm` and `copr-cli build-package vgshell --name vgshell`. The GitHub webhook rebuilds `vgshell-git` on every push to `main`.
8. Verify every channel, as below.

### Fedora

Use the project, build targets and additional repositories in [`packaging/fedora/copr-project`](packaging/fedora/copr-project). Keep both the cpptrace and Hyprland COPRs as runtime repository dependencies. With a COPR API token, create or recreate the project and its engine package:

```bash
copr-cli create vgshell --chroot fedora-44-x86_64 --chroot fedora-44-aarch64 \
  --repo copr://errornointernet/quickshell --repo copr://sdegler/hyprland \
  --runtime-repo-dependency copr://errornointernet/quickshell \
  --runtime-repo-dependency copr://sdegler/hyprland
copr-cli add-package-scm vgshell --name vgshell-quickshell --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit main --spec packaging/fedora/vgshell-quickshell.spec --method make_srpm
copr-cli build-package vgshell --name vgshell-quickshell
```

For a new engine candidate, set the engine package's SCM committish to its exact public candidate revision before building it. Wait for the engine build to succeed and its RPMs to appear in every declared target's repository metadata. Then add and build the shell packages:

```bash
copr-cli add-package-scm vgshell --name vgshell-git --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit main --spec packaging/fedora/vgshell-git.spec --method make_srpm --webhook-rebuild on
copr-cli add-package-scm vgshell --name vgshell --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit vX.Y.Z --spec packaging/fedora/vgshell.spec --method make_srpm
copr-cli build-package vgshell --name vgshell
copr-cli build-package vgshell --name vgshell-git
```

For an existing COPR project, add the engine package through the project settings. [`packaging/fedora/srpm.sh`](packaging/fedora/srpm.sh) owns source-RPM preparation and the release-tag check. The shell specs require the VGS engine.

Enable the repository's GitHub webhook for `vgshell-git` only after the first release tag exists, so pre-tag RPM versions do not sort above tagged builds. Prove a new published install route in a clean container before adding it to the README.

### Verification

Each check reads the published channel, never the checkout.

```bash
# The release's assets and their signature.
gh release download vX.Y.Z --repo vanillagreencom/vgshell --dir /tmp/vgshell-X.Y.Z
(cd /tmp/vgshell-X.Y.Z && sha256sum -c SHA256SUMS && gpg --verify SHA256SUMS.asc SHA256SUMS)

# The AUR's view of the engine and shell packages.
curl -fsS 'https://aur.archlinux.org/rpc/v5/info?arg[]=vgshell-quickshell&arg[]=vgshell&arg[]=vgshell-git'

# Each AUR package, installed through paru in a clean Arch container, as a
# user does: paru also builds the depends only the AUR holds.
for pkg in vgshell vgshell-git; do
  mkdir -p "tmp/release-installs/aur-$pkg"
  podman run --rm -v "$PWD/tmp/release-installs/aur-$pkg:/export" docker.io/library/archlinux:latest bash -euc '
    pacman -Syu --noconfirm --needed base-devel git sudo
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
    runuser -u builder -- bash -c "cd && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm"
    runuser -u builder -- bash -c "cd && paru -S --noconfirm --skipreview $1"
    vgshell --version
    entry="$(readlink -f -- "$(command -v vgshell)")"
    tree="$(dirname -- "$(dirname -- "$entry")")"
    cp -a -- "$tree/." /export/' _ "$pkg"
done

# The README's published installs, including curl in its prepared Arch image.
scripts/readme-install.sh --export tmp/release-installs

# The flake at the tag.
podman run --rm -e NIX_CONFIG='experimental-features = nix-command flakes' docker.io/nixos/nix:2.35.2 \
  nix run github:vanillagreencom/vgshell/vX.Y.Z -- --version
```

Use the export above and this loop to check installed-tree startup in the [nested sandbox](docs/architecture/validation.md#nested-sandbox). The README runner's NixOS identity fixture proves installation and version, not graphics. Nix startup needs a NixOS graphics host, through an exported NixOS curl tree or a NixOS-host flake install. Its exported store enters the world's private `/nix` ([D113](docs/decisions/D113-world-root-from-host-mounts.md)); the host driver paths must remain usable. On another host the runner reports `nixos-graphics-required`, exit 77. Record that startup proof as unavailable, never as a pass.

```bash
for tree in tmp/release-installs/*; do
  args=(--tree "$tree" --rows bar)
  [[ ! -d $tree/nix ]] || args+=(--nix-store "$tree/nix")
  scripts/qml-smoke.sh "${args[@]}"
done
```

## Licence

VGS is under the [MIT licence](LICENSE). The bundled fonts, Inter and JetBrains Mono, use SIL Open Font License 1.1: [Inter](shell/assets/fonts/InterVariable-OFL.txt), [JetBrains Mono](shell/assets/fonts/JetBrainsMono-OFL.txt). [Lucide icons](shell/Ui/icons/LICENSE) use ISC, and the [browser discovery stub](shell/plugins/vgs.jarvis/backend/skills/browser/LICENSE) uses Apache-2.0. [distribution.md § Licence](docs/architecture/distribution.md#licence) owns the combined package licence expression.
