# Package build failure transcripts

Each `<tool>-<case>.out` is the bytes one build printed on a pseudo-terminal, as `script(1)` logged them, with the log's own header and footer lines removed. They are the classifier corpus for `PackageReview.classifyInstallFailure`, read by `scripts/fixtures/pkg-review/failure-test.js`.

Recorded on 2026-10-31 on the development host (CachyOS, `LANG=en_US.UTF-8`, `/etc/makepkg.conf` with `BUILDENV=(... color check ...)`) with makepkg (pacman) 7.1.0 and paru v2.1.0 +git (libalpm v16.0.1). yay is not installed, so no yay transcript exists.

Each recipe is a trivial PKGBUILD written for this corpus: `pkgname=vgs-fixture-<case>`, `pkgver=1.0`, `pkgrel=1`, `arch=(any)`, no dependency but the one `dependency` names and no remote source. Nothing was installed:

- makepkg ran as `makepkg -f` in the recipe's directory, never with `-i`, `-s` or `-r`, with `BUILDDIR`, `PKGDEST`, `SRCDEST` and `LOGDEST` in a scratch directory.
- paru ran as `paru --sudo /usr/bin/false --skipreview --noconfirm -B <dir>...`, which builds without installing, from a directory holding only the recipes named.
- Every run was `timeout 120 script -qef --log-out <file> -c <command>`.

| Case | Recipe | makepkg exit | paru exit |
| --- | --- | --- | --- |
| check-only | `check()` prints a failed test and returns 1 | 4 | 1 |
| build-fail | `build()` returns 1 | 4 | 1 |
| prepare-fail | `prepare()` returns 1 | 4 | |
| pkgver-fail | `pkgver()` returns 1 | 4 | |
| package-fail | `package()` returns 1 after a passing `check()` | 4 | 1 |
| source-missing | `source=(fixture-missing.txt)`, absent | 1 | 1 |
| integrity | `source=(integrity.txt)` with a wrong sha256 | 1 | 1 |
| dependency | `depends=(vgs-fixture-absent-dependency)` | 8 | 1 |
| misleading | `build()` prints the check failure line, `check()` passes printing it again, `package()` returns 1 | 4 | |
| spoof-in-check | `check()` prints a build failure line and returns 1 | 4 | |
| check-pass | every function passes | 0 | 0 |
| multi | check-only and a second base whose `check()` returns 1 | | 1 |
| mixed | check-only and build-fail | | 1 |
| retry | check-only with makepkg's `--nocheck` (`makepkg -f --nocheck`, `paru ... --nocheck -B`) | 0 | 0 |
| interrupted | `check()` sleeps; `timeout -s INT 3 makepkg -f` sent SIGINT | 124 | |

paru's `check-pass` skipped its build because the package file from makepkg's run was already in `PKGDEST`. The transcripts hold no user name or home path.

## paru 2.2 capture

The `paru-2.2-<case>.out` files were recorded on 2026-11-01 in a throwaway rootless Podman `docker.io/library/archlinux:latest` container (image digest `sha256:dfb01267da058e5d08ffdc543bf484c9b404655b0bac1d0201d972bf950cdfd0`). The capture used makepkg (pacman) 7.1.0 (`pacman 7.1.0.r9.g54d9411-3`) and paru v2.2.0 with libalpm v16.0.1, built from the unmodified AUR paru 2.2.0-1 recipe at commit `675b2c0803072a523f2ea9f5a9372ec271b74f8d`. Its upstream source archive has SHA256 `213d55a67605ff69faefa523917fee7168ea5bf143be8cef800fb48c9759f348`. This differs from the 2.1 capture above, which ran on the development host.

The route follows `scripts/arch-packages.sh`: only container root installs dependencies, and an unprivileged container user builds the AUR recipe without `--syncdeps`. The following setup commands run **inside the disposable container**:

```sh
sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf
pacman -Syu --noconfirm --needed base-devel git rust clang python
useradd -m builder
mkdir -p /build
chown builder:builder /build
runuser -u builder -- git clone --depth 1 https://aur.archlinux.org/paru.git /build/paru
runuser -u builder -- /usr/bin/bash -c 'cd /build/paru && makepkg --printsrcinfo'
```

Container root installs the recipe's `depends` and `makedepends` from that metadata with `pacman -S --noconfirm --needed --asdeps`. Then the container builds and installs paru there:

```sh
runuser -u builder -- /usr/bin/bash -c 'cd /build/paru && export MAKEFLAGS=-j4 CARGO_BUILD_JOBS=4 && makepkg --noconfirm --nocheck'
pacman -U --noconfirm /build/paru/paru-*.pkg.tar.zst
paru --version
makepkg --version
```

The unprivileged user's capture environment was `PATH=/usr/bin`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, `TERM=xterm-256color`, with its container home. Each recipe has the common fields and behavior in the table above. `check-two` uses `pkgname=vgs-fixture-check-two`, a passing `build()` and a failing `check()`. `integrity.txt` contains `fixture` followed by a newline; its declared SHA256 is 64 zeroes. Each capture starts from a directory containing only the recipes its command names; retry reuses check-only's failed build tree. All recipe packages are build-only; none is installed. The ten commands use this form, with the output filename and recipe arguments from the table:

```sh
timeout 120 script -qef --log-out paru-2.2-check-only.raw \
  -c 'paru --sudo /usr/bin/false --skipreview --noconfirm -B ./check-only'
```

| Output case | Recipe arguments after `-B` | Extra paru flag before `-B` | Exit |
| --- | --- | --- | --- |
| check-only | `./check-only` | | 1 |
| build-fail | `./build-fail` | | 1 |
| package-fail | `./package-fail` | | 1 |
| source-missing | `./source-missing` | | 1 |
| integrity | `./integrity` | | 1 |
| dependency | `./dependency` | | 1 |
| check-pass | `./check-pass` | | 0 |
| multi | `./check-only ./check-two` | | 1 |
| mixed | `./check-only ./build-fail` | | 1 |
| retry | `./check-only` | `--nocheck` | 0 |

Unlike 2.1's cached `check-pass`, the 2.2 passing recipe is built from scratch. Each `.out` retains the PTY bytes, including ANSI sequences and CRLF, after removing only `script`'s first header and final footer. Captures are inspected for usernames, hostnames, home paths and tokens before retention. No host package manager or live shell participates.

## Admit the next paru minor

Build its AUR recipe in a fresh rootless Arch container by the same route. Record the recipe revision, source checksum, image digest and both reported tool versions. Capture all ten cases above with the same recipes, bounded PTY command and build-only flags. If makepkg is outside the admitted 7.1.x range, use 7.1.x or retain that makepkg version's complete corpus before admitting it. Keep every sanitized interval under a distinct versioned filename. Add per-version evidence rows for every interval to `failure-test.js`: only the check-only case qualifies, every negative case refuses retry, and successful builds stay ordinary. Compare all answers with the admitted corpus, amend messages at the single `classifyInstallFailure` owner if needed, and only then extend `SUPPORTED_BUILDERS` to the captured minor. Keep an out-of-corpus version refusal and a control that removes the new minor's admission. A version number alone never admits new messages; yay requires its own evidence and stays unsupported.
