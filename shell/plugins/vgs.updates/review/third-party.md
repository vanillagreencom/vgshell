# Review third-party packages

A VGS system update is about to install packages from outside the distribution's official repositories. Review them for supply-chain risk before the update installs them. Work fast: batch your commands and keep your output short.

You only review. Do not install, upgrade or remove a package. Do not run a command as root. The update installs the packages after you finish, and only as your verdict allows.

## Files

The current directory is the review directory.

- `packages.txt` lists what to review, one item per line:
  - `helper <command>`: the AUR helper of this system, paru or yay.
  - `aur <package> <installed version> <new version>`: a package from the Arch User Repository.
  - `repo <repository> <package> <installed version> <new version>`: a package from a pacman repository that is not official.
  - `server <repository> <url>`: one server of that repository.
  - `siglevel <repository> <level>`: the signature level pacman applies to it.
- `build/` holds the build files you fetch. Make it, and remove it when you finish.
- `verdict` is the file you write last.

## Steps

1. Read `packages.txt`.
2. For the AUR packages, fetch every build file in one call, from inside `build/`: `<helper> -G <package>...`.
3. Read each `PKGBUILD`, and each `.install` file it names. Report real supply-chain risk only:
   - a `source=()` entry from an unexpected or unofficial domain, or a download from an arbitrary host;
   - an obfuscated or encoded payload, a download piped to a shell, or base64 decoded into a shell;
   - an `install=` script that does privileged or destructive work, sets the setuid bit or writes outside the build directory;
   - a new change since the last build: compare each `PKGBUILD` with the copy the helper cached when it last built the package, `~/.cache/paru/clone/<package>/PKGBUILD` for paru and `~/.cache/yay/<package>/PKGBUILD` for yay, and look hardest at what changed.

   A version, `pkgver` or checksum bump and an ordinary build change are not concerns.
4. A repository package has no build file to read, so review its origin: whether each server belongs to the project the repository is named for, whether its signature level requires a signature, and whether the package is one that repository is known to publish.
5. Write `verdict` in exactly this form, and nothing else:
   - line 1 is `verdict clean` when no package has a real risk, else `verdict flagged`;
   - after a `verdict flagged` line, one line `flag <package> <concern>` per package with a real risk, the package named as `packages.txt` names it and the concern in one plain sentence.

   Flag a package you cannot verify. A package you do not flag installs.
6. Remove `build/`.
7. Show one line per package with what you found. Then tell the user: "The review is done. Close this window to continue the update."

The user can talk to you in this window. Answer their questions. Change the verdict only when they show you that a concern is wrong.
