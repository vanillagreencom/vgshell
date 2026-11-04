#!/usr/bin/env python3
"""The computers this user's SSH configuration names, as one JSON line.

Prints {"hosts": [{"alias", "hostname", "user", "known"}]}: one entry per
`Host` line of ~/.ssh/config and the files its `Include` lines name, by the
line's first pattern with no wildcard or negation, in file order. `hostname`
and `user` are that block's own `HostName` and `User`, "" when it sets none;
`known` is true when ~/.ssh/known_hosts holds the alias or the host name,
plain or hashed, as [name]:port for a block whose Port is not 22. This
computer's own name is left out. Only names leave this helper: it never
reads a key file or a key line's key field.

Include follows ssh_config(5): a relative path is under ~/.ssh, `~` and the
tokens %d, %u, %L, %l and %% are expanded, and a glob takes its matches in
order. On cachy the main file includes ~/.ssh/config.d/%L.conf, so a reader
without tokens would miss every host there. A missing file names nothing;
exit 0. A file that exists and cannot be read exits 2 with
`hosts: unreadable=<path>`.
"""
import base64
import glob
import hashlib
import hmac
import json
import os
import pwd
import socket
import sys

SSH_DIR = os.path.expanduser("~/.ssh")
FULL_NAME = socket.gethostname()
SHORT_NAME = FULL_NAME.split(".")[0]
TOKENS = {"d": os.path.expanduser("~"), "u": pwd.getpwuid(os.getuid()).pw_name, "L": SHORT_NAME, "l": FULL_NAME, "%": "%"}


class Unreadable(Exception):
    pass


def lines_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []
    except OSError:
        raise Unreadable(path)


def expand(word):
    out, i = "", 0
    while i < len(word):
        if word[i] == "%" and i + 1 < len(word) and word[i + 1] in TOKENS:
            out, i = out + TOKENS[word[i + 1]], i + 2
        else:
            out, i = out + word[i], i + 1
    out = os.path.expanduser(out)
    return out if os.path.isabs(out) else os.path.join(SSH_DIR, out)


def read_config(path, hosts, depth=0):
    block = None
    for line in lines_of(path):
        words = line.strip().replace("=", " ", 1).split()
        if not words or words[0].startswith("#"):
            continue
        key = words[0].lower()
        if key == "include" and depth < 16:
            for pattern in words[1:]:
                for found in sorted(glob.glob(expand(pattern))):
                    read_config(found, hosts, depth + 1)
        elif key == "host":
            concrete = [w for w in words[1:] if not any(c in w for c in "*?!")]
            block = {"alias": concrete[0], "hostname": "", "user": "", "port": "", "known": False} if concrete else None
            if block is not None and block["alias"].lower() not in (SHORT_NAME.lower(), FULL_NAME.lower()):
                hosts.append(block)
        elif key == "match":
            block = None
        elif block is not None and key in ("hostname", "user", "port") and len(words) > 1 and block[key] == "":
            block[key] = words[1]


def known_names():
    plain, hashed = set(), []
    for line in lines_of(os.path.join(SSH_DIR, "known_hosts")):
        words = line.split()
        if words and words[0].startswith("@"):
            words = words[1:]
        if not words or words[0].startswith("#"):
            continue
        for name in words[0].split(","):
            if name.startswith("|1|"):
                parts = name.split("|")
                try:
                    hashed.append((base64.b64decode(parts[2], validate=True), base64.b64decode(parts[3], validate=True)))
                except (IndexError, ValueError):
                    continue  # a malformed hashed name matches nothing
            else:
                plain.add(name)
    return plain, hashed


def is_known(name, plain, hashed):
    if name == "":
        return False
    if name in plain:
        return True
    return any(hmac.compare_digest(hmac.new(salt, name.encode(), hashlib.sha1).digest(), digest) for salt, digest in hashed)


def main():
    hosts = []
    try:
        read_config(os.path.join(SSH_DIR, "config"), hosts)
        plain, hashed = known_names()
    except Unreadable as e:
        print("hosts: unreadable=" + str(e), file=sys.stderr)
        return 2
    seen = set()
    out = []
    for host in hosts:
        if host["alias"] in seen:
            continue
        seen.add(host["alias"])
        # ssh records a host on another port than 22 as [name]:port.
        port = host.pop("port")
        names = [host["alias"], host["hostname"]] if port in ("", "22") else ["[%s]:%s" % (n, port) for n in (host["alias"], host["hostname"]) if n]
        host["known"] = any(is_known(name, plain, hashed) for name in names)
        out.append(host)
    print(json.dumps({"hosts": out}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
