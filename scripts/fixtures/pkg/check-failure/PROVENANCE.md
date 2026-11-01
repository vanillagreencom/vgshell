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
