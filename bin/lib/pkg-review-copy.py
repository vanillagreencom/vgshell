#!/usr/bin/env python3
"""Copy a recipe's committed regular files: CLONE EMPTY_PRIVATE_DEST.

Print {tree, files, symlinks}; callers list the links beside the snapshots.
The destination receives no links, Git metadata or untracked build output.
"""

import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile


def snapshot(clone, destination):
    destination = Path(destination)
    info = destination.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o077 or destination.resolve() != destination
            or any(destination.iterdir())):
        raise ValueError("destination-not-empty-private-directory")

    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null", GIT_ATTR_NOSYSTEM="1")
    git = ["git", "--no-replace-objects", "-C", clone,
           "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
           "-c", "core.attributesFile=/dev/null"]

    def read(*args):
        return subprocess.run([*git, *args], env=env, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()

    commit = read("rev-parse", "--verify", "HEAD^{commit}")
    tree = read("rev-parse", "--verify", commit + "^{tree}")
    object_format = read("rev-parse", "--show-object-format")
    objects = read("rev-parse", "--path-format=absolute", "--git-path", "objects")
    files, symlinks = [], []
    # Committed and local attributes may omit or transform archive files.
    # Fresh bare metadata has neither info attributes nor a worktree; this
    # option also prevents archive from reading attributes through its index.
    # https://github.com/git/git/blob/v2.56.0/archive.c#L525-L545
    # https://github.com/git/git/blob/v2.56.0/attr.c#L841-L871
    with tempfile.TemporaryDirectory(dir=destination.parent) as metadata, \
            tempfile.TemporaryFile(dir=destination.parent) as stream:
        subprocess.run(["git", "init", "--bare", "--quiet", "--template=",
                        "--object-format=" + object_format, metadata],
                       env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # Only this read-only archive receives the source object directory.
        # Initialization writes solely into the new private metadata folder.
        subprocess.run(["git", "--no-replace-objects", "--git-dir", metadata,
                        "-c", "core.attributesFile=/dev/null", "archive",
                        "--worktree-attributes", "--format=tar", commit, "--"],
                       env={**env, "GIT_OBJECT_DIRECTORY": objects}, check=True,
                       stdout=stream, stderr=subprocess.PIPE)
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode="r:") as archive:
            for member in archive:
                name = member.name.rstrip("/")
                parts = PurePosixPath(name).parts
                if (not parts or name.startswith("/") or ".." in parts
                        or ".git" in parts or "/".join(parts) != name):
                    raise ValueError("archive-path-unsafe")
                target = destination.joinpath(*parts)
                if member.issym():
                    symlinks.append({"path": name, "target": member.linkname})
                elif member.isdir():
                    # Gitlinks appear as empty directories; no submodule is read.
                    target.mkdir(mode=0o700, parents=True, exist_ok=True)
                elif member.isreg():
                    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    # extractfile reads archive bytes. extract/extractall also
                    # materialize links and must not receive these recipes.
                    # https://docs.python.org/3/library/tarfile.html#tarfile.TarFile.extractfile
                    with archive.extractfile(member) as source, target.open("xb") as output:
                        os.chmod(target, 0o600)
                        shutil.copyfileobj(source, output)
                    files.append(name)
                else:
                    raise ValueError("archive-entry-unsupported")
    return {"tree": tree, "files": files, "symlinks": symlinks}


def main():
    if len(sys.argv) != 3:
        print("pkg-review-copy: snapshot=arguments", file=sys.stderr)
        return 2
    try:
        print(json.dumps(snapshot(sys.argv[1], sys.argv[2])))
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print("pkg-review-copy: snapshot=failed cause=" + type(error).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
