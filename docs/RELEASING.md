# Releasing

The maintainer cuts every release from their own machine, with their own gpg key, GitHub login and AUR SSH key. VGS has no CI workflow for releases or package publication: [D040](decisions/D040-one-shared-install-tree.md). The package recipes live beside the source under `packaging/`, so one checkout both tags the release and publishes the recipes that build it. Two scripts do the work. Their headers, which `--help` prints, state every refusal, output line and exit status.

- `scripts/release X.Y.Z` makes the GitHub release `vX.Y.Z` from the pushed tag: the source archive `vgshell-X.Y.Z.tar.gz`, `install.sh`, `SHA256SUMS` and its detached signature `SHA256SUMS.asc`, written to `dist/`.
- `scripts/publish-aur.sh vgshell vgshell-git` pushes the recipes under `packaging/arch/` to the AUR. It holds `vgshell` back until the release asset's sha256 is the one the recipe pins.

Both take `--dry-run`, which makes every check and changes nothing outside `dist/`. `scripts/test-release.sh` and `scripts/test-publish-aur.sh` prove them with stub `gh`, `gpg` and `ssh`, in the `cli` area of `scripts/validate`.

## Before the first release

- Set `release_key` in `install.sh` to the full upper-case fingerprint of the release signing key, the `fpr` value `gpg --list-keys --with-colons` prints. The release signs `SHA256SUMS` with that key, and the curl installer verifies the signature against the same value. `scripts/release` refuses while it is empty.
- Log in with `gh auth login`, as an account that may create releases in `vanillagreencom/vgshell`.
- Register the SSH public key of the AUR account that maintains `vgshell` and `vgshell-git`. The publisher reads the private key from `AUR_SSH_KEY_FILE` and nothing under `~/.ssh`. It pins the AUR's host keys in `packaging/aur-known-hosts`.

## Versions

- `VERSION` holds the release's SemVer version, and the tag is `v` followed by it: [distribution.md § Version](architecture/distribution.md).
- While VGS is at 0.x, a minor bump marks a breaking change to `shell.json`, the plugin API, the manifest or the theme package format. A patch bump marks fixes only.
- Plugin manifest versions change independently of `VERSION`.
- The archive name carries no architecture.

## Flow

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

2. Run `scripts/validate --full` once. A release is an explicit full sweep. Then commit on `main` and push.
3. Tag and push the tag:

   ```bash
   git tag -s vX.Y.Z -m "VGS X.Y.Z"
   git push origin vX.Y.Z
   ```

4. Make the release. The last lines name the archive's sha256.

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

6. Publish both recipes. Exit 75 means a package was held back; its `deferred` line names the reason.

   ```bash
   scripts/publish-aur.sh --dry-run vgshell vgshell-git
   AUR_SSH_KEY_FILE=<the AUR account's private key> scripts/publish-aur.sh vgshell vgshell-git
   ```

7. Rebuild the Fedora package: set `vgshell.spec`'s `Version`, `Release` and `%changelog` with `VERSION`, then run `copr-cli edit-package-scm vgshell --name vgshell --commit vX.Y.Z` and `copr-cli build-package vgshell --name vgshell`. The GitHub webhook rebuilds `vgshell-git` on every push to `main`: [§ Fedora](#fedora).
8. Verify every channel, as below.

## Fedora

The COPR project `vanillagreen/vgshell` holds two packages, `vgshell` from a release tag and `vgshell-git` from `main`, and depends on the two third-party COPRs that ship Quickshell and Hyprland. These commands, run with a COPR API token, set up the project and its packages, and recreate them:

```bash
copr-cli create vgshell --chroot fedora-44-x86_64 --chroot fedora-44-aarch64 \
  --repo copr://errornointernet/quickshell --repo copr://sdegler/hyprland \
  --runtime-repo-dependency copr://errornointernet/quickshell \
  --runtime-repo-dependency copr://sdegler/hyprland
copr-cli add-package-scm vgshell --name vgshell-git --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit main --spec packaging/fedora/vgshell-git.spec --method make_srpm --webhook-rebuild on
copr-cli add-package-scm vgshell --name vgshell --clone-url https://github.com/vanillagreencom/vgshell.git \
  --commit v0.1.0 --spec packaging/fedora/vgshell.spec --method make_srpm
copr-cli build-package vgshell --name vgshell
copr-cli build-package vgshell --name vgshell-git
```

Add the repository's GitHub webhook for `vgshell-git` only after the `v0.1.0` tag exists: `packaging/fedora/srpm.sh` builds `vgshell-git` without a release tag, so a webhook added earlier publishes a pre-tag build whose version sorts above the first builds after the tag, and a user who installed it gets no update. A user installs with `sudo dnf copr enable vanillagreen/vgshell`, then `sudo dnf install vgshell`. Once the first build installs in a clean container from the published project, the README gains a Fedora install command.

## Verification

Each check reads the published channel, never the checkout.

```bash
# The release's assets and their signature.
gh release download vX.Y.Z --repo vanillagreencom/vgshell --dir /tmp/vgshell-X.Y.Z
(cd /tmp/vgshell-X.Y.Z && sha256sum -c SHA256SUMS && gpg --verify SHA256SUMS.asc SHA256SUMS)

# The AUR's view of both packages.
curl -fsS 'https://aur.archlinux.org/rpc/v5/info?arg[]=vgshell&arg[]=vgshell-git'

# Each AUR package, installed through paru in a clean Arch container, as a
# user does: paru also builds the depends only the AUR holds.
for pkg in vgshell vgshell-git; do
  podman run --rm docker.io/library/archlinux:latest bash -euc '
    pacman -Syu --noconfirm --needed base-devel git sudo
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
    runuser -u builder -- bash -c "cd && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm"
    runuser -u builder -- bash -c "cd && paru -S --noconfirm --skipreview $1"
    vgshell --version' _ "$pkg"
done

# The README's published installs, including curl in its prepared Arch image.
scripts/readme-install.sh

# The flake at the tag.
podman run --rm -e NIX_CONFIG='experimental-features = nix-command flakes' docker.io/nixos/nix:2.35.2 \
  nix run github:vanillagreencom/vgshell/vX.Y.Z -- --version
```

Packaged installs print `vgshell X.Y.Z`; checkout installs report `X.Y.Z` in `version --json` and print that report's `describe` value when present. Then run `vgshell run` from each install inside the nested sandbox: [validation-smoke.md](architecture/validation-smoke.md).
