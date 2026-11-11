#!/usr/bin/env bash
# Controls for config/system/kill-switch/vgs-kill-switch.service's sandbox:
# `systemd-analyze security --offline=yes --json=short` judges the shipped
# unit file with no service manager, and each limit the unit sets on sync
# must read set. The analyzer reads the file from a root of this suite's
# own, so no drop-in installed on the host reaches the reading.
#
#   scripts/test-vpn-kill-switch-unit.sh
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
set -euo pipefail

suite=test-vpn-kill-switch-unit
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
unit="$repo/config/system/kill-switch/vgs-kill-switch.service"
name="${unit##*/}"

not_measured() { printf '%s: status=not-measured reason=%s\n' "$suite" "$1"; exit 77; } # KEY

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
