#!/usr/bin/env bash
# Controls for config/system/kill-switch/vgs-kill-switch.service's sandbox:
# `systemd-analyze security --offline=yes --json=short` judges the shipped
# unit file with no service manager, and each limit the unit sets on sync
# must read set. The analyzer reads the file from a root of this suite's
# own, so no drop-in installed on the host reaches the reading.
#
#   scripts/test-vpn-kill-switch-unit.sh
#   scripts/test-vpn-kill-switch-unit.sh --start
#
# Prints one `  ok    <check>` or `  FAIL  <check>` line per check, then
# `test-vpn-kill-switch-unit: passed` with exit 0, or
# `test-vpn-kill-switch-unit: failed=<count>` with exit 1. A host with no
# systemd-analyze or python3, or whose analyzer gives no reading of a
# minimal unit, prints `test-vpn-kill-switch-unit: status=not-measured
# reason=<key>` and exits 77.
#
# The unit runs before network-pre.target with DefaultDependencies=no, and
# for such a unit the analyzer judges none of PrivateTmp=, ProtectHome= and
# ProtectSystem= ("set":null, "Service runs in special boot phase"). Those
# three are read from a copy with that one line removed, which the analyzer
# then judges as it would any service; the line changes no other directive.
#
# The capability bounding set is judged by the analyzer's groups: every
# group reads removed but the four that hold a capability the unit keeps.
# The must-fail control is a copy with CapabilityBoundingSet= removed.
# scripts/test-vpn-kill-switch.sh runs a sync under the unit's capability
# set and writable paths.
#
# --start starts transient units belonging only to this suite, through a
# real user manager. It copies the shipped Service properties, translating
# system paths to disposable user paths and replacing the sync executable
# with a lock-opening recorder. The namespace proof is the same manager
# setup as for system services; PrivateUsers=yes enables that setup in a
# user service (systemd.exec(5), v262, SANDBOXING). RuntimeDirectory= uses
# XDG_RUNTIME_DIR there instead of /run. No network program runs. A control
# restores the missing unprefixed lock and pre-start touch and must fail
# specifically at 226/NAMESPACE before either command can run. A manager
# that cannot run a mount-sandboxed probe, or no user bus, exits 77.
# A user manager needs PrivateUsers=yes for mount privileges. '+' bypasses
# that setup, so only this test drops the pre-touch's '+' credential prefix.
# ReadWritePaths takes the same missing-path resolver with either prefix
# (systemd v262 exec-invoke.c, apply_mount_namespace). The privileged root
# command's evidence is the px13 reading on 2026-11-21 (VGS-2413) and the
# installed-service Jarvis check after merge, not this user-manager run.
set -euo pipefail

suite=test-vpn-kill-switch-unit
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
unit="$repo/config/system/kill-switch/vgs-kill-switch.service"
name="${unit##*/}"

not_measured() { printf '%s: status=not-measured reason=%s\n' "$suite" "$1"; exit 77; } # KEY

if [[ ${1-} == --start ]]; then
  (($# == 1)) || exit 2
  for tool in python3 systemd-run systemctl journalctl; do
    command -v "$tool" >/dev/null || not_measured "missing-$tool"
  done
  # The ordinary validation world hides the caller's bus. This row's
  # control owner runs outside that world, only where a bus is available.
  [[ -n ${XDG_RUNTIME_DIR-} && -S $XDG_RUNTIME_DIR/bus ]] || not_measured user-bus
  exec python3 -I - "$unit" "$repo/config/system/kill-switch/vgs-kill-switch" <<'PY'
import configparser
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile

suite = "test-vpn-kill-switch-unit"
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
config = configparser.ConfigParser(interpolation=None, strict=True)
config.optionxform = str
config.read(sys.argv[1])
service = dict(config["Service"])
assert shlex.split(service.pop("ExecStart")) == ["/usr/local/bin/vgs-kill-switch", "sync"]
lock_line = [line for line in Path(sys.argv[2]).read_text().splitlines() if line.startswith("lock_file=")]
assert len(lock_line) == 1
shipped_lock = Path(lock_line[0].split("=", 1)[1])
state_base = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
state_base.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="vgs-unit-", dir=runtime) as scratch, \
     tempfile.TemporaryDirectory(prefix="vgs-unit-", dir=state_base) as state_scratch:
    root = Path(scratch)
    token = root.name
    cache_name = Path(state_scratch).name + "/cache"
    run_name = token + "/" + service.get("RuntimeDirectory", "vgs-kill-switch")
    lock = runtime / token / shipped_lock.relative_to("/run")
    visible_lock = Path("/tmp") / token / shipped_lock.relative_to("/run")
    stale_lock = visible_lock.parent.parent / "vgs-kill-switch.lock"
    state = root / "vpn"
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "HOME": scratch,
           "XDG_CONFIG_HOME": scratch, "XDG_DATA_HOME": scratch,
           "XDG_STATE_HOME": state_scratch, "XDG_CACHE_HOME": scratch,
           "XDG_RUNTIME_DIR": str(runtime), "VGS_TEST_RUN": "1",
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(runtime / "bus")}
    names = []

    def invoke(label, properties, command):
        name = token + "-" + label + ".service"
        names.append(name)
        argv = ["systemd-run", "--user", "--quiet", "--wait", "--collect", "--pipe",
                "--slice=agents.slice", "--unit=" + name,
                "--property=PrivateUsers=yes", "--property=DefaultDependencies=no"]
        argv += ["--property=" + key + "=" + value for key, value in properties.items()]
        return name, subprocess.run(argv + ["--"] + command, env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

    try:
        _, probe = invoke("probe", {"ProtectSystem": "strict", "PrivateTmp": "yes"}, ["/usr/bin/true"])
        if probe.returncode:
            print(suite + ": status=not-measured reason=systemd-mount-sandbox")
            sys.exit(77)

        properties = dict(service)
        if "RuntimeDirectory" in properties:
            properties["RuntimeDirectory"] = run_name
        # ProtectHome=yes hides /run/user, including the user manager's
        # runtime prefix. BindPaths sources refer to the host tree and
        # destinations to the unit view (systemd.exec(5), v262, BindPaths=).
        # Alias only the manager-created directory inside the private /tmp;
        # the source must still be absent until RuntimeDirectory creates it.
        properties["BindPaths"] = str(lock.parent) + ":" + str(visible_lock.parent)
        properties["StateDirectory"] = cache_name
        properties["ReadWritePaths"] = properties["ReadWritePaths"].replace(
            "/var/lib/vgshell/vpn", str(state))
        # This records entry to sync and opens its fixed lock after translation.
        # It exercises no firewall or bus operation from the production root script.
        recorder = '''import os, sys
assert sys.argv[1] == "sync"
lock = sys.argv[2]
fd = os.open(lock, os.O_WRONLY | os.O_CREAT, 0o600)
os.close(fd)
print("sync=executed", flush=True)
'''
        command = ["/usr/bin/python3", "-I", "-c", recorder, "sync", str(visible_lock)]
        assert not lock.exists()
        for label in ("fresh", "again"):
            _, result = invoke(label, properties, command)
            assert result.returncode == 0 and result.stdout.strip() == "sync=executed", (
                label, result.returncode, result.stdout, result.stderr)
            assert stat.S_IMODE(lock.stat().st_mode) == 0o600
            assert stat.S_IMODE(lock.parent.stat().st_mode) == 0o700
            identity = (lock.stat().st_dev, lock.stat().st_ino)
            if label == "fresh":
                first_identity = identity
            else:
                assert identity == first_identity, "lock replaced between oneshots"
            print("  ok    real systemd " + label + " start executes sync and preserves its lock")

        control = {key: value for key, value in properties.items() if not key.startswith("RuntimeDirectory")}
        control["ReadWritePaths"] = str(stale_lock) + " -" + str(state)
        control["ExecStartPre"] = "/usr/bin/touch " + str(stale_lock)
        control_name, result = invoke("missing-lock", control, command)
        reading = subprocess.run(["journalctl", "--user", "--user-unit=" + control_name,
                                  "--boot", "--quiet", "--no-pager", "--output=cat"],
                                 env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert reading.returncode == 0, reading.stderr
        assert result.returncode != 0 and "sync=executed" not in result.stdout
        assert "status=226/NAMESPACE" in reading.stdout, reading.stdout
        assert stale_lock.name in reading.stdout and "No such file or directory" in reading.stdout, reading.stdout
        print("  ok    real systemd missing-lock control fails status=226/NAMESPACE before sync")
    finally:
        for name in names:
            subprocess.run(["systemctl", "--user", "stop", "--", name], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
print(suite + ": passed")
PY
fi
(($# == 0)) || exit 2

for tool in systemd-analyze python3; do
  command -v "$tool" >/dev/null || not_measured "missing-$tool"
done
tmp="$(mktemp -d)" || { echo "$suite: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "$suite: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "$suite: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${tmp:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
check() { # NAME COMMAND...
  local name="$1"
  shift
  if "$@"; then ok "$name"; else fail "$name"; fi
}

# readings FILE OUT: the analyzer's judgement of the unit file FILE, installed
# alone in a fresh root, as `<json_field>=true|false|null` lines in OUT.
# Returns 1 when the analyzer gives no reading: it exits 0 even for a unit
# it cannot load, so a reading is its JSON list, not its status.
readings() { # FILE OUT
  local root json
  root="$(mktemp -d -p "$tmp")" json="$tmp/analyzer.json"
  mkdir -p "$root/etc/systemd/system"
  cp -- "$1" "$root/etc/systemd/system/${1##*/}"
  systemd-analyze security --offline=yes --root="$root" --json=short "${1##*/}" >"$json" 2>"$tmp/analyzer.err" || return 1
  python3 -I -c '
import json, sys
entries = json.load(open(sys.argv[1]))
assert isinstance(entries, list) and entries
for entry in entries:
    print("%s=%s" % (entry["json_field"], json.dumps(entry["set"])))
' "$json" >"$2" 2>>"$tmp/analyzer.err"
}
reads() { grep -qx -- "$2=$3" "$1"; } # OUT FIELD true|false|null
fails_quietly() { ! "$@" >/dev/null 2>&1; } # COMMAND...
# Like readings, printing the analyzer's error when it gives none.
analyzer_reads() { # FILE OUT
  readings "$@" && return
  printf '        err=[%s]\n' "$(head -c 400 "$tmp/analyzer.err")"
  return 1
}

# A minimal unit the analyzer must judge, or this host's cannot.
printf '[Service]\nExecStart=/usr/bin/true\n' >"$tmp/probe.service"
readings "$tmp/probe.service" "$tmp/probe.readings" && reads "$tmp/probe.readings" NoNewPrivileges false || not_measured analyzer-unusable

# Each row: a json_field the shipped unit must read set. A directive with
# one field per member it denies, RestrictNamespaces=, has every member's.
set_fields="NoNewPrivileges AmbientCapabilities PrivateDevices ProtectKernelTunables
ProtectKernelModules ProtectKernelLogs ProtectControlGroups ProtectClock ProtectHostname
RestrictSUIDSGID RestrictRealtime LockPersonality SystemCallArchitectures IPAddressDeny UMask
RestrictNamespaces_user RestrictNamespaces_pid RestrictNamespaces_net RestrictNamespaces_uts
RestrictNamespaces_mnt RestrictNamespaces_cgroup RestrictNamespaces_ipc
RestrictAddressFamilies_AF_INET_INET6 RestrictAddressFamilies_AF_PACKET RestrictAddressFamilies_OTHER"
# The families sync opens, which RestrictAddressFamilies= keeps.
kept_families="RestrictAddressFamilies_AF_UNIX RestrictAddressFamilies_AF_NETLINK"
# The analyzer's capability groups that hold CAP_NET_ADMIN, CAP_SETUID and
# CAP_SETGID, CAP_KILL, and CAP_DAC_READ_SEARCH.
kept_caps="CapabilityBoundingSet_CAP_NET_ADMIN CapabilityBoundingSet_CAP_SET_UID_GID_PCAP
CapabilityBoundingSet_CAP_KILL CapabilityBoundingSet_CAP_DAC_FOWNER_IPC_OWNER"
boot_phase="PrivateTmp ProtectHome ProtectSystem"

# Whether OUT reads every capability group removed but the kept ones, which
# read kept; the groups come from the reading, and CAP_SYS_ADMIN's must be
# among them, so a reading with no groups never passes.
caps_exact() { # OUT
  local line field value groups=0 bad=0
  while IFS= read -r line; do
    field="${line%%=*}" value="${line#*=}"
    [[ $field == CapabilityBoundingSet_* ]] || continue
    groups=$((groups + 1))
    if [[ " ${kept_caps//$'\n'/ } " == *" $field "* ]]; then
      [[ $value == false ]] || { printf '        %s=%s, kept\n' "$field" "$value"; bad=1; }
    else
      [[ $value == true ]] || { printf '        %s=%s, removed\n' "$field" "$value"; bad=1; }
    fi
  done <"$1"
  for field in $kept_caps CapabilityBoundingSet_CAP_SYS_ADMIN; do
    grep -q -- "^$field=" "$1" || { printf '        %s unread\n' "$field"; bad=1; }
  done
  ((groups > 0 && bad == 0))
}

# A copy of the unit with the line LINE removed, which must occur once, at
# $tmp/NAME/<unit name>.
without_line() { # NAME LINE
  mkdir -p "$tmp/$1"
  check "the $1 copy's line occurs once" test "$(grep -cx -- "$2" "$unit")" == 1
  grep -vx -- "$2" "$unit" >"$tmp/$1/$name" || true
  check "the $1 copy is the unit less one line" test "$(diff -- "$unit" "$tmp/$1/$name" | grep -c '^<')" == 1
}

check "the analyzer reads the shipped unit" analyzer_reads "$unit" "$tmp/shipped.readings"
for field in $set_fields; do
  check "the shipped unit sets $field" reads "$tmp/shipped.readings" "$field" true
done
for field in $kept_families; do
  check "the shipped unit keeps ${field#RestrictAddressFamilies_}" reads "$tmp/shipped.readings" "$field" false
done
check "the shipped unit keeps exactly its four capability groups" caps_exact "$tmp/shipped.readings"
for field in $boot_phase; do
  check "the shipped unit's boot phase leaves $field unjudged" reads "$tmp/shipped.readings" "$field" null
done

without_line default-dependencies DefaultDependencies=no
check "the analyzer reads the default-dependencies copy" analyzer_reads "$tmp/default-dependencies/$name" "$tmp/default-dependencies.readings"
for field in $boot_phase; do
  check "the unit sets $field, read without its boot phase" reads "$tmp/default-dependencies.readings" "$field" true
done

without_line bounding-set-less "$(grep -m 1 '^CapabilityBoundingSet=' "$unit" || echo CapabilityBoundingSet=)"
check "the analyzer reads the bounding-set-less copy" analyzer_reads "$tmp/bounding-set-less/$name" "$tmp/bounding-set-less.readings"
check "the bounding-set-less control fails the capability check" fails_quietly caps_exact "$tmp/bounding-set-less.readings"

if ((failures)); then printf '%s: failed=%s\n' "$suite" "$failures"; exit 1; fi
printf '%s: passed\n' "$suite"
