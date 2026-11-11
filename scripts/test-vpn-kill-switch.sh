#!/usr/bin/env bash
# Controls for config/system/kill-switch/vgs-kill-switch, the VPN kill
# switch's root script, run unmodified in network namespaces: nothing here
# reaches the host's interfaces, routes, firewall, NetworkManager or units.
#
#   scripts/test-vpn-kill-switch.sh
#
# Prints one `  ok    <check>` or `  FAIL  <check>` line per check, then
# `test-vpn-kill-switch: passed` with exit 0, or
# `test-vpn-kill-switch: failed=<count>` with exit 1. A host that cannot hold
# the namespaces prints `test-vpn-kill-switch: status=not-measured
# reason=<key>` and exits 77, and so does one that cannot build the unit's
# read-only view, reason=limited-view, once every other check has passed.
#
# `unshare --user --map-root-user --net --mount` makes the laptop. tmpfs
# mounts there give it its own /run, /var/lib and /usr/local, so the
# script's fixed paths and its PATH reach only this suite's files: from
# /usr/local/sbin, a stand-in nmcli answers the fixture profiles, a stand-in
# systemctl answers whether NetworkManager runs and what state
# vgs-kill-switch.path is in, a stand-in setpriv records its argv, and an
# nft wrapper fails on demand, refuses the egress table's check or its arm
# on demand, or disarms before a counter read. The
# must-fail controls run copies of the script missing one rule each.
# `ip netns add hotel` makes
# the hotel, joined to the laptop's wlan0 by a netkit pair in layer-2 mode:
# a veth would be passed by kind at egress, where a netkit device, like a
# network card, is judged. The hotel holds
# the gateway and DNS server 192.168.50.1, the internet hosts 203.0.113.10
# and 2001:db8:ff::10, and the capture of every frame wlan0 sends
# (scripts/fixtures/kill-switch/hotel.py). A second veth pair stands in for
# tailscale0, with 100.100.100.100 on its far end. A third namespace, the
# box, is a container on the laptop's bridge lbox, masqueraded as Docker
# masquerades its containers. Guests that reach wlan0 at layer 2, each in a
# namespace of its own, send through a macvlan, a macvtap and an ipvlan on
# wlan0, and through a bridge that holds wlan0. A macvtap guest sends
# through the device's own network side: its tap file, which a virtual
# machine opens, belongs to an id the namespace does not map. A relay
# behind a tun device resends what reaches it through a UDP socket, as a
# userspace VPN does. The status socket is served by
# systemd-socket-activate, as vgs-kill-switch-status.socket serves it, and
# read by a process with every capability dropped.
#
# The armed and control rounds send every probe, in order: an IPv4 ping and
# TCP connects to ports 80 and 443, an IPv6 ping and TCP connect, dig over
# UDP and TCP to the hotel's resolver, a ping to the hotel's gateway, a ping
# and TCP connect over tailscale0, a loopback ping, UDP to each WireGuard
# peer, a DHCPv4 and a DHCPv6 client datagram to the gateway, and a DHCPv4
# broadcast sent through a packet socket, as a client with no address sends
# it, which no inet hook sees. Every
# other round sends only the probes its table checks. Each round ends with a
# ping marked as Tailscale marks its packets; the capture holding it proves
# every earlier frame was read.
#
# The last checks start sync as vgs-kill-switch.service does, under the
# limits its unit file names, read from that file: the capability bounding
# set, through the real setpriv with no new privileges, and in a mount
# namespace of its own a file system read-only but for the paths the unit
# keeps writable. Their controls drop a capability the unit keeps.
#
# The VPN plugin's leak judge (shell/plugins/vgs.vpn/VpnLogic.js
# leakCheck) runs under node, loaded as scripts/test-vpn-logic.js loads it,
# over readings taken in the laptop with the VPN meant on and its tunnel
# removed: the status line the unprivileged reader gets, and the
# plugin's own route and systemd-resolved reads, run in the namespace. No
# NetworkManager runs here, so the tunnel's interface reads as nmcli
# answers for a profile that is not active: nothing.
set -euo pipefail

suite=test-vpn-kill-switch
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
script="$repo/config/system/kill-switch/vgs-kill-switch"
hotel_py="$repo/scripts/fixtures/kill-switch/hotel.py"

not_measured() { printf '%s: status=not-measured reason=%s\n' "$suite" "$1"; exit 77; } # KEY

if [[ ${1-} != --laptop ]]; then
  (($# == 0)) || exit 2
  for tool in unshare ip nft setpriv python3 dig ping timeout flock mount systemd-socket-activate node awk; do
    command -v "$tool" >/dev/null || not_measured "missing-$tool"
  done
  # The binary itself, not a version manager's shim, which reads the
  # caller's home: the laptop's PATH is fixed and its /usr/local is its own.
  node_bin="$(node -e 'process.stdout.write(process.execPath)')" || not_measured node-unresolved
  unshare --user --map-root-user --net --mount true 2>/dev/null || not_measured user-namespaces
  TMP_ROOT="$(mktemp -d)" || { echo "$suite: scratch=mktemp-failed" >&2; exit 1; }
  [[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "$suite: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
  TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "$suite: scratch=resolve-failed" >&2; exit 1; }
  trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
  status=0
  env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 HOME="$TMP_ROOT" NODE_BIN="$node_bin" \
    unshare --user --map-root-user --net --mount --propagation private -- "$BASH" "$self" --laptop "$TMP_ROOT" || status=$?
  exit "$status"
fi

# ---------------------------------------------------------------- the laptop

tmp="$2"
state=/var/lib/vgshell/vpn/state
pending=/var/lib/vgshell/vpn/pending
cache=/var/lib/vgshell/kill-switch/profile
lock=/run/vgs-kill-switch.lock
sock=/run/vgs-kill-switch.sock
frames="$tmp/frames.log"
uuid=2f0c7b1e-5d3a-4c8e-9b6f-1a2b3c4d5e6f
other_uuid=9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d
key_a=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
key_b=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
peers="$key_a endpoint=203.0.113.51:51820 allowed-ips=0.0.0.0/0 persistent-keepalive=25, $key_b endpoint=[2001:db8:ff::51]:51820 allowed-ips=::/0"
# The prefix root's reads and writes of the state file take: the directory
# owner's uid and gid, here the namespace's root, with no groups.
as_owner="--reuid=0 --regid=0 --clear-groups --inh-caps=-all --"

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
check() { # NAME COMMAND...
  local name="$1"
  shift
  if "$@"; then ok "$name"; else fail "$name"; fi
}

hotel_pid="" status_pid=""
laptop_cleanup() {
  local pid
  for pid in "$status_pid" "$hotel_pid"; do
    [[ -z $pid ]] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
  done
}
trap laptop_cleanup EXIT

# Waits up to five seconds for COMMAND to succeed.
await() { # COMMAND...
  local tenth
  for ((tenth = 0; tenth < 50; tenth++)); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

real_setpriv="$(command -v setpriv)"
real_nft="$(command -v nft)"
for dir in /run /var/lib /usr/local; do
  mount -t tmpfs -o mode=0755 tmpfs "$dir" || not_measured "mount-$dir"
done
mkdir -p /usr/local/sbin /var/lib/vgshell/vpn

# nmcli answers the two reads the script makes from $tmp/nm/<uuid>.{type,ifname,peers}
# and exits 10, nmcli's no-such-connection status, for a uuid with no type
# file; every call lands in $tmp/nmcli.log. While $tmp/nm-writes holds
# `<meant-on>|<kill-switch>` lines, each type read first writes the first of
# them as the state file, as a writer would while a sync runs, and drops it.
mkdir -p "$tmp/nm"
cat >/usr/local/sbin/nmcli <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/nmcli.log"
[ "\$1 \$2 \$3" = "--escape no -g" ] && [ "\$5 \$6 \$7" = "connection show uuid" ] && [ \$# = 8 ] || exit 2
if [ -s "$tmp/nm-writes" ] && [ "\$4" = connection.type,connection.interface-name ]; then
  IFS='|' read -r meant kill <"$tmp/nm-writes"
  sed -i 1d "$tmp/nm-writes"
  printf 'version=1\nmeant-on=%s\nkill-switch=%s\nportal-until=0\n' "\$meant" "\$kill" >/var/lib/vgshell/vpn/.state.nmcli
  mv -f /var/lib/vgshell/vpn/.state.nmcli $state
  touch $pending
fi
nm="$tmp/nm/\$8"
[ -f "\$nm.type" ] || exit 10
case "\$4" in
  connection.type,connection.interface-name) cat "\$nm.type" "\$nm.ifname" ;;
  wireguard.peers) cat "\$nm.peers" ;;
  *) exit 2 ;;
esac
EOF
# systemctl answers whether NetworkManager runs: yes, unless
# $tmp/nm-inactive exists; and vgs-kill-switch.path's ActiveState: the
# word in $tmp/watcher, else active, and no answer while
# $tmp/watcher-unread exists.
cat >/usr/local/sbin/systemctl <<EOF
#!/bin/sh
case "\$*" in
  "is-active --quiet NetworkManager.service") [ ! -e "$tmp/nm-inactive" ] ;;
  "show --property=ActiveState --value vgs-kill-switch.path")
    [ ! -e "$tmp/watcher-unread" ] || exit 1
    if [ -e "$tmp/watcher" ]; then cat "$tmp/watcher"; else echo active; fi ;;
  *) exit 64 ;;
esac
EOF
# setpriv records the argv the script passes and runs the real setpriv with
# --keep-groups for --clear-groups: an unprivileged namespace may never call
# setgroups(2) (user_namespaces(7), /proc/[pid]/setgroups), and it maps no
# supplementary group to keep. So the argv rows below are the only proof of
# the owner-credential drop; no namespace here holds a second uid.
cat >/usr/local/sbin/setpriv <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/setpriv.log"
args=""
for a; do [ "\$a" = --clear-groups ] && a=--keep-groups; args="\$args '\$a'"; done
eval "set -- \$args"
exec $real_setpriv "\$@"
EOF
# nft refuses every transaction while $tmp/nft-fail exists. While
# $tmp/nft-check-refused exists it refuses every check, as a kernel that
# cannot hold the wildcard egress hook refuses the egress table's; while
# $tmp/nft-egress-fail exists it refuses every transaction that declares
# that hook, its check excepted. Once after $tmp/nft-disarm-between is
# created, a counter read first deletes the cache and then the table, as a
# sync's disarm can between status's listing and that read. Otherwise it is
# the real nft.
cat >/usr/local/sbin/nft <<EOF
#!/bin/sh
[ "\$1" = -f ] && [ -e "$tmp/nft-fail" ] && { echo "nft: planted failure" >&2; exit 1; }
[ "\$1" = -c ] && [ -e "$tmp/nft-check-refused" ] && { echo "nft: planted check refusal" >&2; exit 1; }
if [ "\$1" = -f ] && [ -e "$tmp/nft-egress-fail" ]; then
  input="\$(cat)"
  case "\$input" in *"hook egress"*) echo "nft: planted egress failure" >&2; exit 1 ;; esac
  printf '%s\n' "\$input" | $real_nft "\$@"
  exit
fi
if [ "\$1 \$2" = "list counter" ] && rm -- "$tmp/nft-disarm-between" 2>/dev/null; then
  rm -f -- $cache || exit 1
  printf 'delete table inet vgshell_kill_switch\ndelete table netdev vgshell_kill_switch\n' | $real_nft -f - || exit 1
fi
exec $real_nft "\$@"
EOF
chmod 0755 /usr/local/sbin/nmcli /usr/local/sbin/systemctl /usr/local/sbin/setpriv /usr/local/sbin/nft
profile() { # UUID TYPE IFNAME PEERS
  printf '%s\n' "$2" >"$tmp/nm/$1.type"
  printf '%s\n' "$3" >"$tmp/nm/$1.ifname"
  printf '%s\n' "$4" >"$tmp/nm/$1.peers"
}

# The topology. Static IPv4 neighbours keep address resolution out of the
# capture and out of the probes' time; IPv6 resolves through neighbour
# discovery, which the armed rule must pass.
ip link set lo up
ip netns add hotel
ip link add wlan0 type netkit mode l2 peer name hotel0 || not_measured netkit-link
ip link set hotel0 netns hotel
ip link add tailscale0 type veth peer name tspeer netns hotel
ip link add wgnord type wireguard || not_measured wireguard-link
{ ip link add l2probe link wlan0 type macvtap && ip link del l2probe; } || not_measured macvtap-link
ip addr add 192.168.50.2/24 dev wlan0
ip -6 addr add 2001:db8:50::2/64 dev wlan0 nodad
ip link set wlan0 up
ip route add default via 192.168.50.1
ip -6 route add default via 2001:db8:50::1
ip addr add 100.101.1.2/32 dev tailscale0
ip link set tailscale0 up
ip route add 100.64.0.0/10 dev tailscale0
# The box, a container on the bridge lbox; the laptop masquerades what it
# sends anywhere else, as Docker's rule for docker0 does.
ip netns add box
ip link add lbox type veth peer name box0 netns box
ip addr add 10.88.0.1/24 dev lbox
ip link set lbox up
echo 1 >/proc/sys/net/ipv4/ip_forward
nft -f - <<'EOF'
table ip boxnat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.88.0.0/24 oifname != "lbox" masquerade
  }
}
EOF
ip netns exec box sh -e -c '
  ip link set lo up
  ip addr add 10.88.0.2/24 dev box0
  ip link set box0 up
  ip route add default via 10.88.0.1
'
ip netns exec hotel sh -e -c '
  ip link set lo up
  ip addr add 192.168.50.1/24 dev hotel0
  ip -6 addr add 2001:db8:50::1/64 dev hotel0 nodad
  ip link set hotel0 up
  for a in 203.0.113.10/32 203.0.113.20/32 203.0.113.51/32; do ip addr add "$a" dev lo; done
  for a in 2001:db8:ff::10/128 2001:db8:ff::51/128; do ip -6 addr add "$a" dev lo; done
  ip addr add 100.100.100.100/32 dev tspeer
  ip link set tspeer up
  ip route add 100.101.1.2/32 dev tspeer
'
link_mac() { # LINK: the laptop link's address, read through netlink, never /sys, which shows the host's links
  local out
  out="$(ip -o link show dev "$1")" && [[ $out =~ link/ether\ ([^ ]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}
hotel_mac="$(ip netns exec hotel cat /sys/class/net/hotel0/address)"
wlan_mac="$(link_mac wlan0)"
ip neigh replace 192.168.50.1 lladdr "$hotel_mac" dev wlan0 nud permanent
ip netns exec hotel ip neigh replace 192.168.50.2 lladdr "$wlan_mac" dev hotel0 nud permanent

: >"$frames"
ip netns exec hotel python3 -I "$hotel_py" serve hotel0 "$frames" "$tmp/hotel-ready" &
hotel_pid=$!
await test -e "$tmp/hotel-ready" || not_measured hotel-start
# Serves the status socket with COMMAND..., the shipped status by default.
serve_status() { # [COMMAND...]
  (($# > 0)) || set -- "$script" status
  rm -f -- /run/vgs-kill-switch.sock
  systemd-socket-activate --inetd -a -l "$sock" "$@" 2>>"$tmp/status.err" &
  status_pid=$!
  await test -S "$sock"
}
stop_status() { kill "$status_pid" 2>/dev/null || true; wait "$status_pid" 2>/dev/null || true; status_pid=""; }
serve_status || not_measured status-socket

# A process with no capability: the user, and the shell reading the status.
unprivileged() { "$real_setpriv" --bounding-set=-all --inh-caps=-all -- "$@"; } # COMMAND...

# ---------------------------------------------------------------- helpers

write_state() { # MEANT_ON KILL_SWITCH [PORTAL_UNTIL]
  printf 'version=1\nmeant-on=%s\nkill-switch=%s\nportal-until=%s\n' "$1" "$2" "${3:-0}" >"$state"
}
sync_out=""
sync_status=0
run_sync() {
  sync_status=0
  sync_out="$("$script" sync 2>"$tmp/sync.err")" || sync_status=$?
}
synced() { # armed|disarmed
  [[ $sync_status == 0 && $sync_out == "ok sync=$1" ]] && return
  printf '        sync: exit=%s out=[%s] err=[%s]\n' "$sync_status" "$sync_out" "$(head -c 400 "$tmp/sync.err")"
  return 1
}
refused() { # FILE STATUS KEY: STATUS is 1 and FILE's first line is the refusal KEY
  [[ $2 == 1 && "$(head -n 1 "$1")" == "vgs-kill-switch: refused: $3" ]] && return
  printf '        exit=%s err=[%s]\n' "$2" "$(head -c 400 "$1")"
  return 1
}
# Like refused, for a refusal after a command that may print its own
# message first, as the script's header allows: the first keyed line.
refused_keyed() { # FILE STATUS KEY
  local first
  first="$(grep -m 1 '^vgs-kill-switch: refused: ' "$1")" || first=""
  [[ $2 == 1 && $first == "vgs-kill-switch: refused: $3" ]] && return
  printf '        exit=%s err=[%s]\n' "$2" "$(head -c 400 "$1")"
  return 1
}
# Sets line to the status line the socket serves to the unprivileged reader,
# and blocked to its count.
read_status() {
  line="$(unprivileged "$script" status 2>"$tmp/status-read.err")" || line="unreadable"
  blocked=-1
  [[ $line =~ \ blocked=([0123456789]+)\  ]] && blocked="${BASH_REMATCH[1]}"
  return 0
}
# Whether the line holds all five keys in order, with its state and reason,
# tunnel and, when PROFILE is given, profile as named.
status_is() { # "state=… reason=…" tunnel=… [profile=…]
  read_status
  [[ $line =~ ^(state=[^\ ]+\ reason=[^\ ]+)\ blocked=[0123456789]+\ (tunnel=[^\ ]*)\ (profile=[^\ ]*)$ ]] || return 1
  [[ ${BASH_REMATCH[1]} == "$1" && ${BASH_REMATCH[2]} == "$2" && (-z ${3-} || ${BASH_REMATCH[3]} == "$3") ]]
}
table_listed() { local out; out="$(nft list tables)" && [[ $'\n'$out$'\n' == *$'\n'"table $1 vgshell_kill_switch"$'\n'* ]]; } # FAMILY
table_armed() { table_listed inet && table_listed netdev; }
table_absent() { local out; out="$(nft list tables)" && [[ $out != *vgshell_kill_switch* ]]; }
delete_tables() { nft -f - <<<$'table inet vgshell_kill_switch {}\ndelete table inet vgshell_kill_switch\ntable netdev vgshell_kill_switch {}\ndelete table netdev vgshell_kill_switch'; }
fails() { ! "$@" >/dev/null 2>&1; } # COMMAND...
succeeds() { "$@" >/dev/null 2>&1; } # COMMAND...
lacks() { local out; out="$(<"$2")" && [[ $out != *"$1"* ]]; } # TEXT FILE: FILE reads, and holds no TEXT
# nft wraps a long element list, so both sides are read without whitespace.
set_holds() { local out; out="$(nft list set inet vgshell_kill_switch "$1")" && [[ ${out//[[:space:]]/} == *"${2//[[:space:]]/}"* ]]; } # SET TEXT
set_empty() { local out; out="$(nft list set inet vgshell_kill_switch "$1")" && [[ $out != *elements* ]]; } # SET
# The setpriv calls since the log was last emptied, the random part of a
# temporary name read as T.
setpriv_calls() { sed -E 's/\.state\.[A-Za-z0-9]{10}/.state.T/g' "$tmp/setpriv.log" 2>/dev/null || true; }
# Whether a TCP connect to ADDRESS port PORT fails within 0.3 s: a reset ends
# it at once, where the ICMP refusal took about 1 s.
tcp_refused_at_once() { # ADDRESS PORT
  local start=${EPOCHREALTIME/./} status=0
  timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null || status=$?
  ((status != 0 && ${EPOCHREALTIME/./} - start < 300000))
}
# Sets mutant to a copy of the script with NEEDLE, which must occur once,
# replaced by REPLACEMENT: a must-fail control.
mutant() { # NAME NEEDLE REPLACEMENT
  mutant="$tmp/mutant-$1"
  check "the $1 control's text occurs once" test "$(python3 -I -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$script" "$2")" == 1
  python3 -I -c 'import sys; p, o, a, b = sys.argv[1:]; s = open(p).read(); open(o, "w").write(s.replace(a, b))' "$script" "$mutant" "$2" "$3"
  chmod 0755 "$mutant"
  check "the $1 mutant differs" test "$(cmp -s -- "$script" "$mutant"; echo $?)" == 1
}
gateway6_resolved() { local out; out="$(ip -6 neigh show 2001:db8:50::1 dev wlan0)" && [[ $out == *lladdr* ]]; }
# leak_check STATUS_LINE BEFORE OUT: the leak judge over STATUS_LINE and
# the routes and name lookup links read now, with BEFORE the judge's
# earlier result file or -, writing its result to OUT and printing
# `kill=<state> rising=<bool> blocked=<count> previous=<count>
# ipv4=<verdict> ipv6=<verdict> dns=<verdict>`.
cat >"$tmp/leak-check.js" <<'JS'
"use strict";
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const [repo, uuid, statusLine, beforeFile, outFile] = process.argv.slice(2);
const { load } = require(path.join(repo, "bin/lib/qml-library.js"));
const commons = { "qs.Commons 1.0": { Nmcli: load(path.join(repo, "shell/Commons/Nmcli.js")),
    SettingValues: load(path.join(repo, "shell/Commons/SettingValues.js")) } };
const logic = load(path.join(repo, "shell/plugins/vgs.vpn/VpnLogic.js"), commons);
// The plugin's own argv, as its readers run it: PATH and LC_ALL alone.
const run = argv => {
    const ran = spawnSync(argv[0], argv.slice(1), { encoding: "utf8", env: { PATH: process.env.PATH, LC_ALL: "C" } });
    return [ran.error || ran.status === null ? -1 : ran.status, ran.stdout || "", ran.stderr || ""];
};
const result = logic.leakCheck({
    uuid, link: logic.linkRead(0, ""), status: logic.killStatus(0, statusLine + "\n"),
    ipv4: logic.routeRead(...run(logic.routeArgv("ipv4"))), ipv6: logic.routeRead(...run(logic.routeArgv("ipv6"))),
    dns: logic.dnsRead(...run(logic.DNS_ARGV).slice(0, 2)), public: null
}, beforeFile === "-" ? null : JSON.parse(fs.readFileSync(beforeFile, "utf8")).kill);
fs.writeFileSync(outFile, JSON.stringify(result));
const k = result.kill;
console.log(`kill=${k.state} rising=${k.rising} blocked=${k.blocked} previous=${k.previous} ipv4=${result.ipv4.verdict} ipv6=${result.ipv6.verdict} dns=${result.dns.verdict}`);
JS
leak_check() { "$NODE_BIN" "$tmp/leak-check.js" "$repo" "$uuid" "$1" "$2" "$3" 2>>"$tmp/leak-check.err" || echo "judge=failed"; } # STATUS_LINE BEFORE OUT

# A DHCPv4 discover's shape, from 0.0.0.0 port 68 to 255.255.255.255 port
# 67, written through a packet socket on the link the first argument names.
dhcp4_packet='import socket, struct, sys
udp = struct.pack("!HHHH", 68, 67, 12, 0) + b"dhcp"
ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 0, 0, 64, 17, 0, bytes(4), bytes([255] * 4))
total = sum(struct.unpack("!10H", ip))
total = (total >> 16) + (total & 0xFFFF)
ip = ip[:10] + struct.pack("!H", ~(total + (total >> 16)) & 0xFFFF) + ip[12:]
s = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(0x0800))
s.sendto(ip + udp, (sys.argv[1], 0x0800, 0, 0, bytes([255] * 6)))'
# probe_round NAME [DNS_SECONDS [PROBE...]]: runs the PROBEs, every probe
# from the list in the header when none is named, then the marked barrier;
# writes `<probe>=pass|fail` lines to $tmp/NAME.results and the capture's
# `<probe>=<frames>` lines to $tmp/NAME.frames. dig waits out its whole
# timeout on a refused UDP query, so a round whose DNS must pass gives the
# threaded resolver 3 s, and one whose DNS is refused 1 s.
probe_round() { # NAME [DNS_SECONDS [PROBE...]]
  local name="$1" dns_time="${2:-1}" start results="$tmp/$1.results" probe only=""
  (($# < 3)) || only=" ${*:3} marked "
  start=$(($(wc -l <"$frames") + 1))
  : >"$results"
  probe() { # PROBE COMMAND...
    local probe="$1"
    shift
    [[ -z $only || $only == *" $probe "* ]] || return 0
    if "$@" >/dev/null 2>&1; then echo "$probe=pass" >>"$results"; else echo "$probe=fail" >>"$results"; fi
  }
  probe ping4 ping -n -c1 -W1 203.0.113.10
  probe tcp4 timeout 2 bash -c 'exec 3<>/dev/tcp/203.0.113.10/80'
  probe tcp4-443 timeout 2 bash -c 'exec 3<>/dev/tcp/203.0.113.10/443'
  probe ping6 ping -6 -n -c1 -W1 2001:db8:ff::10
  probe tcp6 timeout 2 bash -c 'exec 3<>/dev/tcp/2001:db8:ff::10/80'
  probe dns-udp dig +notcp +tries=1 +time="$dns_time" @192.168.50.1 example.com
  probe dns-tcp dig +tcp +tries=1 +time="$dns_time" @192.168.50.1 example.com
  probe lan-ping ping -n -c1 -W1 192.168.50.1
  probe ts-ping ping -n -c1 -W1 100.100.100.100
  probe ts-tcp timeout 2 bash -c 'exec 3<>/dev/tcp/100.100.100.100/80'
  probe lo-ping ping -n -c1 -W1 127.0.0.1
  probe peer4 bash -c 'printf x >/dev/udp/203.0.113.51/51820'
  probe peer6 bash -c 'printf x >/dev/udp/2001:db8:ff::51/51820'
  probe dhcp4 python3 -I -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("0.0.0.0", 68)); s.sendto(b"x", ("192.168.50.1", 67))'
  probe dhcp6 python3 -I -c 'import socket; s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM); s.bind(("::", 546)); s.sendto(b"x", ("2001:db8:50::1", 547))'
  probe dhcp4-packet python3 -I -c "$dhcp4_packet" wlan0
  probe marked ping -n -c1 -W1 -m 524288 203.0.113.20
  await marked_seen "$start" || echo "barrier=missing" >>"$results"
  python3 -I "$hotel_py" count "$frames" "$start" >"$tmp/$name.frames"
}
marked_seen() { [[ $(python3 -I "$hotel_py" count "$frames" "$1") == *$'\nmarked='[123456789]* ]]; } # START
# expect_round NAME TABLE: each TABLE row is `<probe> <pass|fail> <frames>`,
# frames 0, `some`, or `-` for a probe whose route never reaches wlan0.
expect_round() { # NAME TABLE
  local name="$1" probe result want_frames got
  check "$name: the capture read every frame" test "$(grep -c '^barrier=' "$tmp/$name.results" || true)" == 0
  while read -r probe result want_frames; do
    [[ -n $probe ]] || continue
    check "$name: the $probe probe ${result/%s/ses}" grep -qx -- "$probe=$result" "$tmp/$name.results"
    got="$(sed -n "s/^$probe=//p" "$tmp/$name.frames")"
    if [[ $want_frames == - ]]; then
      continue
    elif [[ $want_frames == 0 ]]; then
      check "$name: the capture holds no $probe frame" test "$got" == 0
    else
      check "$name: the capture holds the $probe frames" test "${got:-0}" -gt 0
    fi
  done <<<"$2"
}

# ---------------------------------------------------------------- the checks

profile "$uuid" wireguard wgnord "$peers"

check "with no state file the status socket reads off" status_is "state=off reason=disarmed" "tunnel=" "profile="
check "the status line names no count but zero while off" test "$blocked" == 0

# A lock an older copy made 0644 is narrowed to root's alone.
install -m 0644 /dev/null "$lock"
write_state "$uuid" block
run_sync
check "sync arms for a meant-on WireGuard profile" synced armed
check "sync reads the state file only as its owner, with no groups" test "$(setpriv_calls | sort -u)" == "$as_owner head -c 4097 -- $state"
check "the sync lock is root's alone, mode 0600" test "$(stat -c '%u %a' -- "$lock")" == "0 600"
check "the tunnels set holds the profile's interface and tailscale0" set_holds tunnel_links '"tailscale0", "wgnord"'
check "the profile reading is cached root's, mode 0600" test "$(stat -c '%u %a' -- "$cache")" == "0 600"
check "with the tunnel up the status reads passing for the profile it armed" status_is "state=passing reason=tunnel-up" "tunnel=wgnord" "profile=$uuid"

ip link del wgnord
check "with the tunnel gone the status reads holding" status_is "state=holding reason=tunnel-down" "tunnel=wgnord"
blocked_before="$blocked"
leak_before="$(leak_check "$line" - "$tmp/leak-before.json")"
check "with the tunnel gone the leak check reads the kill switch holding" test "${leak_before%% *}" == kill=holding
# No neighbour entry for the IPv6 gateway, so the peer6 datagram that
# follows resolves it through the armed rule.
ip -6 neigh flush dev wlan0
bash -c 'printf x >/dev/udp/2001:db8:ff::51/51820' 2>/dev/null || true
check "with the switch armed, neighbour discovery resolves the IPv6 gateway" await gateway6_resolved
probe_round armed
expect_round armed "
ping4 fail 0
tcp4 fail 0
tcp4-443 fail 0
ping6 fail 0
tcp6 fail 0
dns-udp fail 0
dns-tcp fail 0
lan-ping fail 0
ts-ping pass -
ts-tcp pass -
lo-ping pass -
peer4 pass some
peer6 pass some
dhcp4 pass some
dhcp6 pass some
dhcp4-packet pass some
marked pass some"
read_status
check "the blocked count rose with the refused probes" test "$blocked" -gt "$blocked_before"
# Name lookups read unknown: no systemd-resolved answers in the laptop.
leak_after="$(leak_check "$line" "$tmp/leak-before.json" "$tmp/leak-after.json")"
check "the leak check reads the kill switch holding, its count rising between two reads around the probes" test "$leak_after" == \
  "kill=holding rising=true blocked=$blocked previous=$blocked_before ipv4=blocked ipv6=blocked dns=unknown"
[[ $leak_after == "kill=holding rising=true blocked=$blocked previous=$blocked_before ipv4=blocked ipv6=blocked dns=unknown" ]] \
  || printf '        leak check: before=[%s] after=[%s] err=[%s]\n' "$leak_before" "$leak_after" "$(head -c 400 "$tmp/leak-check.err" 2>/dev/null)"
blocked_armed="$blocked"
check "the status still reads holding after the probes" status_is "state=holding reason=tunnel-down" "tunnel=wgnord"
check "the unprivileged reader cannot list the rule itself" fails unprivileged nft list ruleset
check "the same listing with CAP_NET_ADMIN succeeds" succeeds nft list ruleset
check "block refuses the laptop's own traffic to its container bridge" fails ping -n -c1 -W1 10.88.0.2
check "a refused TCP connect fails at once" tcp_refused_at_once 203.0.113.10 80
check "a refused DNS-over-TCP connect fails at once" tcp_refused_at_once 192.168.50.1 53

# A container routed through the laptop: what it sends out the Wi-Fi is
# refused, and what it reaches through a tunnel answers.
start=$(($(wc -l <"$frames") + 1))
ip netns exec box ping -n -c1 -W1 203.0.113.10 >/dev/null 2>&1 || true
check "a masqueraded forwarded ping through tailscale0 is answered" succeeds ip netns exec box ping -n -c1 -W1 100.100.100.100
ping -n -c1 -W1 -m 524288 203.0.113.20 >/dev/null 2>&1 || true
check "the capture read every forwarded frame" await marked_seen "$start"
check "the capture holds no forwarded ping" test "$(python3 -I "$hotel_py" count "$frames" "$start" | sed -n 's/^ping4=//p')" == 0
# With the box masqueraded out the Wi-Fi alone and a far end that routes the
# box's network back, the tunnel's reply is to a flow no NAT rewrote. The
# masquerade keeps conntrack tracking, as Docker's and ufw's rules do on a
# real host; an empty NAT chain would not.
nft flush chain ip boxnat postrouting
nft add rule ip boxnat postrouting ip saddr 10.88.0.0/24 oifname wlan0 masquerade
ip netns exec hotel ip route add 10.88.0.0/24 via 100.101.1.2 dev tspeer onlink
check "a tunnel's reply to a forwarded flow no NAT rewrote is refused" fails ip netns exec box ping -n -c1 -W1 100.100.100.100

run_sync
read_status
check "a sync while armed keeps the blocked count" test "$blocked" -ge "$blocked_armed"

# Guests on the uplink at layer 2 meet no inet hook of the laptop: the
# egress chain on wlan0 judges their frames.
guest() { # NS ADDRESS LINK: moves LINK into the new namespace NS, addressed, routed through the hotel's gateway
  ip netns add "$1"
  ip link set "$3" netns "$1"
  ip netns exec "$1" sh -e -c "
    ip link set lo up
    ip addr add $2/24 dev $3
    ip link set $3 up
    ip route add default via 192.168.50.1
    ip neigh replace 192.168.50.1 lladdr $hotel_mac dev $3 nud permanent
  "
}
# Prints how many pings to the hotel's internet host the capture holds
# after NS sends one with PING_OPTIONs, or `barrier-missing`.
guest_frames() { # NS [PING_OPTION...]
  local start=$(($(wc -l <"$frames") + 1)) counts
  ip netns exec "$1" ping -n -c1 -W1 "${@:2}" 203.0.113.10 >/dev/null 2>&1 || true
  ping -n -c1 -W1 -m 524288 203.0.113.20 >/dev/null 2>&1 || true
  await marked_seen "$start" || { echo barrier-missing; return; }
  counts="$(python3 -I "$hotel_py" count "$frames" "$start")" || { echo count-failed; return; }
  sed -n 's/^ping4=//p' <<<"$counts"
}
egress_drops() { local out; out="$(nft list counter netdev vgshell_kill_switch blocked)" && [[ $out =~ packets\ ([0123456789]+) ]] && echo "${BASH_REMATCH[1]}"; }
# Whether NS's ping met the egress hook and was dropped there: the egress
# count rose, so the frame reached it, and the capture holds none.
guest_held() { # NS [PING_OPTION...]
  local before after got
  before="$(egress_drops)" || return 1
  got="$(guest_frames "$@")" || got=send-failed
  after="$(egress_drops)" || return 1
  [[ $got == 0 ]] && ((after > before)) && return
  printf '        frames=%s egress drops %s to %s\n' "$got" "$before" "$after"
  return 1
}
ip link add l2mv link wlan0 type macvlan mode bridge
guest l2macvlan 192.168.50.11 l2mv
# The controls run first: each arms from no table, as a copy's declarations
# never reshape a chain the shipped script hooked.
mutant egress-less 'chain egress { type filter hook egress devices = { \"*\" } priority filter; policy accept; }' 'chain egress {}'
delete_tables
"$mutant" sync >/dev/null 2>&1 || true
check "the egress-less control arms both tables" table_armed
check "the egress-less control's macvlan guest reaches the hotel" test "$(guest_frames l2macvlan)" -gt 0
check "with no device holding the egress hook the status reads device-uncovered" status_is "state=unavailable reason=device-uncovered" "tunnel=wgnord" "profile=$uuid"
mutant device-blind '    [[ -z $uncovered ]] || state=unavailable why=device-uncovered' '    true'
check "the device-blind control reads an uncovered device as holding" test "$("$mutant" status 2>&1 | cut -d' ' -f1-2)" == "state=holding reason=tunnel-down"
mutant mark-unscoped ' meta mark & 0xff0000 == 0x80000 meta skuid >= 0 accept' ' meta mark & 0xff0000 == 0x80000 accept'
delete_tables
"$mutant" sync >/dev/null 2>&1 || true
check "the mark-unscoped control passes a macvlan guest's marked packet" test "$(guest_frames l2macvlan -m 524288)" -gt 0
run_sync
check "arm again after the layer-2 controls" synced armed
check "with every device hooked the status reads holding" status_is "state=holding reason=tunnel-down" "tunnel=wgnord" "profile=$uuid"
blocked_l2="$blocked"
check "a macvlan guest on the uplink is dropped at its egress hook" guest_held l2macvlan
check "a macvlan guest's packet with Tailscale's mark is dropped too" guest_held l2macvlan -m 524288
ip -n l2macvlan link del l2mv
ip link add l2mvt link wlan0 type macvtap mode bridge
guest l2macvtap 192.168.50.12 l2mvt
check "a macvtap guest on the uplink is dropped at its egress hook" guest_held l2macvtap
ip -n l2macvtap link del l2mvt
ip link add l2iv link wlan0 type ipvlan mode l2
guest l2ipvlan 192.168.50.13 l2iv
check "an ipvlan guest on the uplink is dropped at its egress hook" guest_held l2ipvlan
ip -n l2ipvlan link del l2iv
# What passing a bridge by kind rests on: a guest's frame the bridge
# forwards out the uplink meets the uplink's own hook.
ip link add l2br type bridge
ip link set wlan0 master l2br
ip link set l2br up
ip link add l2bv type veth peer name l2bg
ip link set l2bv master l2br
ip link set l2bv up
guest l2bridge 192.168.50.14 l2bg
check "a guest on a bridge that holds the uplink is dropped at the uplink's egress hook" guest_held l2bridge
ip link set wlan0 nomaster
ip link del l2bv
ip link del l2br
read_status
check "the blocked count rose with the layer-2 guests' packets" test "$blocked" -gt "$blocked_l2"
# A netdev table gone by another hand, as by an `nft delete table`, leaves
# every device unjudged at egress; the next sync adds it again.
nft delete table netdev vgshell_kill_switch
check "with the egress table deleted the status reads device-uncovered" status_is "state=unavailable reason=device-uncovered" "tunnel=wgnord" "profile=$uuid"
run_sync
check "the next sync arms the egress table again" table_listed netdev

# Kernel WireGuard sends its outer packets with DF clear, so an uplink whose
# MTU is below their size splits them, and a later fragment carries no UDP
# header. peer_fragments sends one such 1450-byte datagram to each peer
# and prints the capture's peer and later-fragment counts, then the egress
# drops it added. IP_MTU_DISCOVER is 10 and IPV6_MTU_DISCOVER 23, and 0 is
# PMTUDISC_DONT for both (linux/in.h, linux/in6.h).
big_datagrams='import socket
for family, address, level, option in ((socket.AF_INET, "203.0.113.51", socket.IPPROTO_IP, 10), (socket.AF_INET6, "2001:db8:ff::51", socket.IPPROTO_IPV6, 23)):
    s = socket.socket(family, socket.SOCK_DGRAM)
    s.setsockopt(level, option, 0)
    s.sendto(b"x" * 1450, (address, 51820))'
peer_fragments() {
  local start=$(($(wc -l <"$frames") + 1)) before after counts
  before="$(egress_drops)" || { echo drops-unread; return; }
  python3 -I -c "$big_datagrams" || { echo send-failed; return; }
  ping -n -c1 -W1 -m 524288 203.0.113.20 >/dev/null 2>&1 || true
  await marked_seen "$start" || { echo barrier-missing; return; }
  after="$(egress_drops)" || { echo drops-unread; return; }
  counts="$(python3 -I "$hotel_py" count "$frames" "$start")" || { echo count-failed; return; }
  counts="$(grep -E '^peer(4|6)(-frag)?=' <<<"$counts")" || { echo count-failed; return; }
  printf '%s drops=%s\n' "${counts//$'\n'/ }" "$((after - before))"
}
ip link set wlan0 mtu 1400
mutant frag-blind 'add rule netdev $table egress ip frag-off & 0x1fff != 0 ip daddr @peer_addrs4 accept
add rule netdev $table egress frag frag-off != 0 ip6 daddr @peer_addrs6 accept
' ''
delete_tables
"$mutant" sync >/dev/null 2>&1 || true
check "the frag-blind control drops each datagram's later fragment" test "$(peer_fragments)" == "peer4=1 peer6=1 peer4-frag=0 peer6-frag=0 drops=2"
run_sync
check "arm again after the fragment control" synced armed
check "with the uplink's MTU below a peer datagram every fragment leaves, and none is dropped" test "$(peer_fragments)" == "peer4=1 peer6=1 peer4-frag=1 peer6-frag=1 drops=0"
ip link set wlan0 mtu 1500

# A tun device's frames pass the egress chain by kind: what the program
# behind it sends on, as a userspace VPN does, leaves through a socket the
# inet table judges. The relay stands in for that program: it reads the
# first IPv4 packet from the tun device NAME and sends it through a UDP
# socket to HOST port PORT, after creating READY.
tun_relay='import fcntl, os, socket, struct, sys
fd = os.open("/dev/net/tun", os.O_RDWR)
fcntl.ioctl(fd, 0x400454CA, struct.pack("16sH", sys.argv[1].encode(), 0x0001 | 0x1000))
open(sys.argv[4], "w").close()
while True:
    packet = os.read(fd, 65535)
    if packet[0] >> 4 == 4:
        break
socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(packet, (sys.argv[2], int(sys.argv[3])))'
# Prints how many of the relay's datagrams, the capture's KIND, the capture
# holds after one ping into the tun device, or why it holds no reading.
tun_frames() { # HOST PORT KIND
  local start=$(($(wc -l <"$frames") + 1)) ready="$tmp/relay-ready-$1" pid counts
  timeout 5 python3 -I -c "$tun_relay" l2tun "$1" "$2" "$ready" 2>/dev/null &
  pid=$!
  await test -e "$ready" || { wait "$pid" || true; echo relay-missing; return; }
  ip addr add 10.99.0.1/24 dev l2tun
  ip link set l2tun up
  # Marked as Tailscale marks its packets, so the inet table passes the ping
  # into the tun device, and only the relay's datagram meets its refusal.
  ping -n -c1 -W1 -m 524288 10.99.0.2 >/dev/null 2>&1 || true
  wait "$pid" || true
  ping -n -c1 -W1 -m 524288 203.0.113.20 >/dev/null 2>&1 || true
  await marked_seen "$start" || { echo barrier-missing; return; }
  counts="$(python3 -I "$hotel_py" count "$frames" "$start")" || { echo count-failed; return; }
  sed -n "s/^$3=//p" <<<"$counts"
}
check "a tun device's packet relayed to a WireGuard peer leaves" test "$(tun_frames 203.0.113.51 51820 peer4)" -gt 0
inet_drops() { local out; out="$(nft list counter inet vgshell_kill_switch blocked)" && [[ $out =~ packets\ ([0123456789]+) ]] && echo "${BASH_REMATCH[1]}"; }
# Whether the relay's datagram to a host no pass names met the inet
# table's refusal and left nothing on the uplink.
tun_refused() {
  local before after got
  before="$(inet_drops)" || return 1
  got="$(tun_frames 203.0.113.10 4789 relay)" || got=send-failed
  after="$(inet_drops)" || return 1
  [[ $got == 0 ]] && ((after > before)) && return
  printf '        frames=%s inet drops %s to %s\n' "$got" "$before" "$after"
  return 1
}
check "a tun device's packet relayed anywhere else is refused by the inet table" tun_refused

# The local-network allowance passes the hotel's own hosts but never its DNS.
write_state "$uuid" block-lan
run_sync
check "block-lan arms" synced armed
# With no neighbour entry for the gateway, the lan ping resolves it by ARP
# through the armed rule.
ip neigh del 192.168.50.1 dev wlan0
probe_round lan 1 lan-ping dns-udp dns-tcp ping4
ip neigh replace 192.168.50.1 lladdr "$hotel_mac" dev wlan0 nud permanent
expect_round lan "
lan-ping pass some
dns-udp fail 0
dns-tcp fail 0
ping4 fail 0"
check "block-lan passes the laptop's own traffic to its container bridge" succeeds ping -n -c1 -W1 10.88.0.2

# The control: the same probes with the switch off leave and are captured.
write_state "$uuid" off
run_sync
check "kill-switch=off disarms" synced disarmed
check "kill-switch=off leaves no table" table_absent
check "kill-switch=off removes the profile cache" test ! -e "$cache"
check "the status reads off with the switch off" status_is "state=off reason=disarmed" "tunnel=" "profile="
probe_round control 3
expect_round control "
ping4 pass some
tcp4 pass some
tcp4-443 pass some
ping6 pass some
tcp6 pass some
dns-udp pass some
dns-tcp pass some
lan-ping pass some
ts-ping pass -
lo-ping pass -
marked pass some"

# A flow the tunnel's far end opened to the box while the switch was off,
# masqueraded onto the box's bridge as a subnet router or exit node
# masquerades its peers' flows: once armed, its next packet in that, the
# original, direction meets the rule, NAT or not.
nft add rule ip boxnat postrouting ip saddr 100.64.0.0/10 oifname lbox masquerade
check "with the switch off the tunnel's far end reaches the box" succeeds ip netns exec hotel python3 -I "$hotel_py" echo 10.88.0.2 22017 1
write_state "$uuid" block
run_sync
check "arm under a flow from before" synced armed
check "a tunnel's packet in a flow's original direction is refused" fails ip netns exec hotel python3 -I "$hotel_py" echo 10.88.0.2 22017 2

# Off on purpose: meant-on cleared, as the VPN panel and off write it.
write_state "" block
run_sync
check "meant-on cleared disarms" synced disarmed
check "meant-on cleared leaves no table" table_absent
probe_round off 3 ping4 dns-udp
expect_round off "
ping4 pass some
dns-udp pass some"

# A table an older copy declared another way is replaced whole.
delete_tables
nft -f - <<<'table inet vgshell_kill_switch { set lan4 { type ipv4_addr; }; }'
write_state "$uuid" block-lan 0
run_sync
check "sync replaces a table an older copy declared differently" synced armed
check "the replaced table holds the local ranges" set_holds lan4 "192.168.0.0/16"

# The one-command clear: `sudo vgs-kill-switch off`, with no unit running.
: >"$tmp/setpriv.log"
clear_out="$("$script" off 2>"$tmp/off.err")" || clear_out="exit=$?"
check "the root clear reports off" test "$clear_out" == "ok state=off"
check "the root clear deletes the table at once" table_absent
check "the root clear removes the cache" test ! -e "$cache"
check "the root clear writes meant-on= and keeps the other keys" test "$(cat "$state")" == "$(printf 'version=1\nmeant-on=\nkill-switch=block-lan\nportal-until=0')"
check "the root clear writes as the file's owner, through a renamed temporary file, then the pending mark" test "$(setpriv_calls)" == "$(printf '%s\n' \
  "$as_owner head -c 4097 -- $state" \
  "$as_owner mktemp -- /var/lib/vgshell/vpn/.state.T" \
  "$as_owner tee -- /var/lib/vgshell/vpn/.state.T" \
  "$as_owner chmod 0644 -- /var/lib/vgshell/vpn/.state.T" \
  "$as_owner mv -fT -- /var/lib/vgshell/vpn/.state.T $state" \
  "$as_owner touch -- $pending")"
check "the root clear leaves the pending mark" test -e "$pending"
: >"$tmp/setpriv.log"
run_sync
check "sync removes the pending mark as the file's owner before it reads" test "$(setpriv_calls | head -n 2)" == "$(printf '%s\n' "$as_owner rm -f -- $pending" "$as_owner head -c 4097 -- $state")"
check "no pending mark is left after the sync" test ! -e "$pending"

# The root clear deletes the table even when it cannot write the state file.
write_state "$uuid" block
run_sync
check "arm before a clear that cannot write" synced armed
head -c 5000 /dev/zero | tr '\0' x >"$state"
clear_status=0
"$script" off >/dev/null 2>"$tmp/off.err" || clear_status=$?
check "a root clear that cannot write the state file still deletes the table" table_absent
check "it still removes the cache" test ! -e "$cache"
check "it refuses after the clear, naming the write" refused "$tmp/off.err" "$clear_status" "state=too-large path=$state"

# The user's off: it writes the file, and the sync the path unit would run
# lets its status wait end.
write_state "$uuid" block
run_sync
check "arm before the user's off" synced armed
unprivileged "$script" off >"$tmp/user-off.out" 2>"$tmp/user-off.err" &
user_off_pid=$!
check "the user's off writes meant-on=" await grep -qx 'meant-on=' "$state"
check "the user's off leaves the pending mark" await test -e "$pending"
run_sync
user_off_status=0
wait "$user_off_pid" || user_off_status=$?
check "after the sync the user's off reports off" test "$user_off_status $(cat "$tmp/user-off.out")" == "0 ok state=off"
check "the user's off left a file of the state grammar, mode 0644" test "$(stat -c %a -- "$state") $(cat "$state")" == "644 $(printf 'version=1\nmeant-on=\nkill-switch=block\nportal-until=0')"

# A sign-in page opens DNS, HTTP and HTTPS for at most five minutes; a time
# further ahead or past opens nothing.
printf -v now '%(%s)T' -1
write_state "$uuid" block $((now + 300))
run_sync
check "a sign-in time five minutes ahead arms" synced armed
for port in 53 80 443; do
  check "a sign-in time opens port $port with a timeout" set_holds portal "$port timeout"
done
probe_round portal 3 tcp4 tcp4-443 dns-udp ping4
expect_round portal "
tcp4 pass some
tcp4-443 pass some
dns-udp pass some
ping4 fail 0"
write_state "$uuid" block $((now + 3600))
run_sync
check "a sign-in time more than five minutes ahead opens nothing" set_empty portal
write_state "$uuid" block $((now - 10))
run_sync
check "a past sign-in time opens nothing" set_empty portal

# Profiles the switch cannot pass read unavailable and stay closed.
nmcli_calls() { wc -l <"$tmp/nmcli.log" 2>/dev/null || echo 0; }
write_state "$uuid" block
run_sync
ip link add wgnord type wireguard
check "the WireGuard profile arms again" status_is "state=passing reason=tunnel-up" "tunnel=wgnord"
touch "$tmp/nm-inactive"
calls_before="$(nmcli_calls)"
run_sync
check "with NetworkManager stopped the cache arms the same peers" set_holds peers4 "203.0.113.51 . 51820"
check "with NetworkManager stopped nmcli is never asked" test "$(nmcli_calls)" == "$calls_before"
check "the cached tunnel still passes" status_is "state=passing reason=tunnel-up" "tunnel=wgnord"
# At boot on a read-only /var, with a pending mark left from a write.
touch "$pending"
delete_tables
mount --bind -o ro /var/lib/vgshell/vpn /var/lib/vgshell/vpn
run_sync
umount /var/lib/vgshell/vpn
check "a pending mark sync cannot remove still lets it arm from the cache" synced armed
check "the armed table holds the cached peers" set_holds peers4 "203.0.113.51 . 51820"
check "the failed removal is a journal line" grep -qx "vgs-kill-switch: pending=remove-failed path=$pending" "$tmp/sync.err"
rm -f -- /var/lib/vgshell/vpn/pending
# The cache holds the passing reading for $uuid; another profile never gets it.
write_state "$other_uuid" block
run_sync
check "a cache for another profile is not read" status_is "state=unavailable reason=profile-unread" "tunnel="
check "the status names the profile the table is now armed for" status_is "state=unavailable reason=profile-unread" "tunnel=" "profile=$other_uuid"
check "the other profile arms with no peer" set_empty peers4
check "the other profile passes only tailscale0" set_holds tunnel_links 'elements = { "tailscale0" }'
write_state "$uuid" block
rm -f -- /var/lib/vgshell/kill-switch/profile
run_sync
check "with no cache the switch arms closed" synced armed
check "with no cache only tailscale0 passes" set_holds tunnel_links 'elements = { "tailscale0" }'
check "with no cache the status names why" status_is "state=unavailable reason=profile-unread" "tunnel="
rm -f -- "$tmp/nm-inactive"
# Each row: setup, the status it reads; none passes a peer or a tunnel.
write_state "$other_uuid" block
while IFS='|' read -r row kind ifname peer_text want_status want_tunnel; do
  [[ -n $row ]] || continue
  profile "$other_uuid" "$kind" "$ifname" "$peer_text"
  run_sync
  check "$row: arms closed" synced armed
  check "$row: the status names why" status_is "$want_status" "$want_tunnel"
  check "$row: no peer passes" set_empty peers4
  check "$row: only tailscale0 passes" set_holds tunnel_links 'elements = { "tailscale0" }'
done <<EOF
not WireGuard|vpn|tun0|$peers|state=unavailable reason=profile-not-wireguard|tunnel=
host name endpoint|wireguard|wgnord|$key_a endpoint=vpn.example.com:51820|state=unavailable reason=endpoint-hostname|tunnel=
host name after an address|wireguard|wgnord|$key_a endpoint=203.0.113.51:51820, $key_b endpoint=vpn.example.com:51820|state=unavailable reason=endpoint-hostname|tunnel=
out of range port|wireguard|wgnord|$key_a endpoint=203.0.113.51:70000|state=unavailable reason=endpoint-invalid|tunnel=
zone in an IPv6 endpoint|wireguard|wgnord|$key_a endpoint=[fe80::1%wlan0]:51820|state=unavailable reason=endpoint-invalid|tunnel=
peer key the parser refuses|wireguard|wgnord|notakey endpoint=203.0.113.51:51820|state=unavailable reason=profile-unread|tunnel=
interface name with a slash|wireguard|wg/0|$peers|state=unavailable reason=interface-invalid|tunnel=
EOF
rm -f -- "$tmp/nm/$other_uuid".*
run_sync
check "a deleted profile arms closed" status_is "state=unavailable reason=profile-missing" "tunnel="

# A failed arm leaves no cache, so status never names a reading the kernel
# does not hold.
write_state "$uuid" block
run_sync
check "the profile passes before nft fails" status_is "state=passing reason=tunnel-up" "tunnel=wgnord"
touch "$tmp/nft-fail"
write_state "$uuid" block-lan
run_sync
rm -f -- "$tmp/nft-fail"
check "a failed arm refuses" refused "$tmp/sync.err" "$sync_status" "nft=failed verb=arm"
check "a failed arm leaves no cache" test ! -e "$cache"
check "after a failed arm the status names no tunnel and no profile" status_is "state=unavailable reason=cache-unreadable" "tunnel=" "profile="

# A kernel that cannot hold the wildcard egress hook, as Linux before 6.16,
# refuses the egress table's check; the planted refusal stands in for it.
# The inet table arms alone, and status says a device is not judged.
write_state "" block
run_sync
touch "$tmp/nft-check-refused"
write_state "$uuid" block
run_sync
check "with the egress check refused sync arms" synced armed
check "with the egress check refused the inet table is armed" table_listed inet
check "with the egress check refused no egress table is armed" fails table_listed netdev
check "with the egress check refused the status reads device-uncovered" status_is "state=unavailable reason=device-uncovered" "tunnel=wgnord" "profile=$uuid"
check "with the egress check refused the laptop's own traffic is still refused" tcp_refused_at_once 203.0.113.10 80
mutant check-ignored 'if nft_check "table netdev $table {}' 'if true || nft_check "table netdev $table {}'
delete_tables
"$mutant" sync >/dev/null 2>&1 || true
check "the check-ignored control arms the egress table the check refused" table_listed netdev
rm -f -- "$tmp/nft-check-refused"

# A two-table arm nft refuses after its check passed is the arm's failure:
# no transaction with the inet table alone follows it.
write_state "" block
run_sync
touch "$tmp/nft-egress-fail"
write_state "$uuid" block
run_sync
check "a two-table arm refused after its check passed refuses" refused "$tmp/sync.err" "$sync_status" "nft=failed verb=arm"
check "that refused arm leaves no inet table" fails table_listed inet
check "with neither table armed the status reads off" status_is "state=off reason=disarmed" "tunnel=" "profile="
mutant arm-falls-back '  nft_apply "$delete_tables$text" || refuse' '  nft_apply "$delete_tables$text" || nft_apply "$inet_text" || refuse'
"$mutant" sync >/dev/null 2>&1 || true
check "the arm-falls-back control arms the inet table alone" table_listed inet
rm -f -- "$tmp/nft-egress-fail"
delete_tables

# A write during each pass: sync applies until a read matches what it
# applied, and refuses a file that never settles.
write_state "$uuid" block
run_sync
printf '%s\n' "$uuid|block-lan" "|block" >"$tmp/nm-writes"
run_sync
check "a state written during each of two passes reaches the kernel" synced disarmed
check "the last state written leaves no table" table_absent
for _ in 1 2 3 4 5 6; do printf '%s\n' "$uuid|block-lan" "$uuid|block"; done >"$tmp/nm-writes"
write_state "$uuid" block
run_sync
: >"$tmp/nm-writes"
check "a state that changes during every pass is refused" refused "$tmp/sync.err" "$sync_status" "state=unsettled path=$state"

# A disarm that lands between status's listing of the table and its counter
# read reads off, never a failed read.
write_state "$uuid" block
run_sync
check "arm before a disarm between status's reads" synced armed
touch "$tmp/nft-disarm-between"
check "a table deleted between status's two reads reads off" status_is "state=off reason=disarmed" "tunnel=" "profile="
check "the deletion landed between status's two reads" test ! -e "$tmp/nft-disarm-between"

# The status read tells no connection from a connection with no line, and
# the user's off waits on a deadline whatever the read does.
stop_status
read_status
check "with no listener the status read refuses unreachable" refused "$tmp/status-read.err" 1 "status=unreachable path=$sock"
serve_status true
read_status
check "a connection with no status line refuses unreadable" refused "$tmp/status-read.err" 1 "status=unreadable path=$sock"
stop_status
serve_status sleep 4
write_state "$uuid" block
user_off_status=0
timeout 8 "$real_setpriv" --bounding-set=-all --inh-caps=-all -- "$script" off >/dev/null 2>"$tmp/user-off.err" || user_off_status=$?
check "the user's off ends at its deadline and names the unreadable read" refused "$tmp/user-off.err" "$user_off_status" "off=pending status=unreadable"
stop_status
# A status instance that answers armed, slowly, for the whole wait: the
# verdict comes from a read that finished, never one the deadline cut.
serve_status bash -c 'sleep 0.2; exec "$0" status' "$script"
write_state "$uuid" block
run_sync
user_off_status=0
timeout 8 "$real_setpriv" --bounding-set=-all --inh-caps=-all -- "$script" off >/dev/null 2>"$tmp/user-off.err" || user_off_status=$?
check "the user's off names an armed reading, not a read its deadline cut" refused "$tmp/user-off.err" "$user_off_status" "off=pending"
stop_status
serve_status

# A flush of the whole ruleset, as a root `nft -f` of a file that starts
# with `flush ruleset` does, removes the rule and no unit sees it: status
# reads the rule missing while the cache says the last sync armed it.
write_state "$uuid" block
run_sync
check "arm before a flush of the whole ruleset" synced armed
nft flush ruleset
check "after a flush the status reads the rule missing, not disarmed" status_is "state=off reason=rule-missing" "tunnel=" "profile="
echo failed >"$tmp/watcher"
check "a missing rule outranks a failed watcher" status_is "state=off reason=rule-missing" "tunnel=" "profile="
mutant flush-blind '  if [[ ! -e $cache_file && ! -L $cache_file ]]; then' '  if true; then'
echo active >"$tmp/watcher"
check "the flush-blind control reads a flushed rule as disarmed" test "$("$mutant" status 2>&1)" == "state=off reason=disarmed blocked=0 tunnel= profile="
run_sync
check "the next sync arms the flushed rule again" synced armed

# A failed vgs-kill-switch.path applies no write until it watches again:
# status names it in place of the tunnel's reason or disarmed, and names a
# reading systemctl did not give.
echo failed >"$tmp/watcher"
check "with the watcher failed the status says so in place of tunnel-up" status_is "state=passing reason=watcher-failed" "tunnel=wgnord" "profile=$uuid"
mutant watcher-blind '    watcher_reason
    why="${watcher_why:-$why}"' '    watcher_why=""
    why="${watcher_why:-$why}"'
check "the watcher-blind control reads tunnel-up" test "$("$mutant" status 2>&1 | cut -d' ' -f1-2)" == "state=passing reason=tunnel-up"
touch "$tmp/watcher-unread"
check "a watcher systemctl cannot read is named, never passed" status_is "state=passing reason=watcher-unread" "tunnel=wgnord" "profile=$uuid"
rm -f -- "$tmp/watcher-unread"
write_state "" block
run_sync
check "disarm with the watcher failed" synced disarmed
check "with the watcher failed an off reads watcher-failed" status_is "state=off reason=watcher-failed" "tunnel=" "profile="
echo active >"$tmp/watcher"
check "a watching path unit reads disarmed again" status_is "state=off reason=disarmed" "tunnel=" "profile="

# A state file outside the grammar is never printed. It arms from the cache
# of the last armed sync, at boot too.
write_state "$uuid" block
run_sync
printf 'version=1\nmeant-on=leaked-text-%s\nkill-switch=block\nportal-until=0\n' "$uuid" >"$state"
run_sync
check "a malformed state file is refused" refused "$tmp/sync.err" "$sync_status" "state=malformed path=$state"
check "the refusal never prints the file" lacks leaked-text "$tmp/sync.err"
check "the rule stays armed past a malformed file" table_armed
delete_tables
run_sync
check "a malformed file at boot is refused" refused "$tmp/sync.err" "$sync_status" "state=malformed path=$state"
check "a malformed file at boot arms from the last armed sync's cache" set_holds tunnel_links '"tailscale0", "wgnord"'

# A damaged state with no cache and no table, as at boot after a sync that
# disarmed, arms closed though the last intent was off: no tunnel, no peer,
# and a status reason that names the state. Root keeps no cache under a
# parent it cannot trust, so there status reads cache-unreadable.
damage() { # KIND
  case "$1" in
    malformed) printf 'version=1\nmeant-on=leaked-text-%s\nkill-switch=block\nportal-until=0\n' "$uuid" >"$state" ;;
    too-large) head -c 5000 /dev/zero | tr '\0' x >"$state" ;;
    unreadable) rm -f -- "$state"; mkdir -- "$state" ;;
    not-a-directory) mv -- /var/lib/vgshell/vpn "$tmp/vpn-away"; : >/var/lib/vgshell/vpn ;;
    untrusted) chmod 0777 /var/lib/vgshell ;;
  esac
}
repair() { # KIND
  case "$1" in
    unreadable) rmdir -- "$state" ;;
    not-a-directory) rm -f -- /var/lib/vgshell/vpn; mv -- "$tmp/vpn-away" /var/lib/vgshell/vpn ;;
    untrusted) chmod 0755 /var/lib/vgshell ;;
  esac
  write_state "" block
}
closed_no_peer() { set_holds tunnel_links 'elements = { "tailscale0" }' && set_empty peers4 && set_empty peers6; }
while IFS='|' read -r kind key why; do
  [[ -n $kind ]] || continue
  write_state "" block
  run_sync
  damage "$kind"
  run_sync
  check "$kind: sync refuses, naming the damage" refused_keyed "$tmp/sync.err" "$sync_status" "$key"
  check "$kind: the table arms with no cache and the last intent off" table_armed
  check "$kind: only tailscale0 passes, and no peer" closed_no_peer
  check "$kind: the status names why" status_is "state=unavailable reason=$why" "tunnel=" "profile="
  repair "$kind"
done <<EOF
malformed|state=malformed path=$state|state-unusable
too-large|state=too-large path=$state|state-unusable
unreadable|state=unreadable path=$state|state-unusable
not-a-directory|state-dir=not-a-directory path=/var/lib/vgshell/vpn|state-unusable
untrusted|untrusted=/var/lib/vgshell|cache-unreadable
EOF
run_sync
check "a repaired state disarms the closed arm" synced disarmed
damage malformed
run_sync
clear_out="$("$script" off 2>"$tmp/off.err")" || clear_out="exit=$?"
check "the root off clears a closed arm from a file that does not parse" test "$clear_out" == "ok state=off"
run_sync
check "after that off the next sync disarms" synced disarmed
mutant refuse-open '  read_cache || reason=state-unusable' '  read_cache || refuse "$error"'
damage malformed
"$mutant" sync >/dev/null 2>&1 || true
check "the refuse-open control leaves no table" table_absent
repair malformed

# A cache root cannot remove, as on a /var the kernel remounted read-only,
# never keeps the table from changing: the root off still deletes it, and a
# sync at boot, with the cache of the last armed sync, still arms. Each
# refuses after, naming the cache.
write_state "$uuid" block
run_sync
check "arm before the cache turns read-only" synced armed
mount --bind -o ro /var/lib/vgshell/kill-switch /var/lib/vgshell/kill-switch
clear_status=0
"$script" off >/dev/null 2>"$tmp/off.err" || clear_status=$?
check "a root off with a read-only cache leaves no table" table_absent
check "that off refuses after the delete, naming the cache" refused_keyed "$tmp/off.err" "$clear_status" "cache=remove-failed path=$cache"
check "that off still writes meant-on=" grep -qx 'meant-on=' "$state"
write_state "$uuid" block
run_sync
check "a sync with a read-only cache and no table arms" table_armed
check "that sync refuses after the arm, naming the cache" refused_keyed "$tmp/sync.err" "$sync_status" "cache=remove-failed path=$cache"
mutant disarm-refuses-first '  rm -f -- "$cache_file" || cache_kept=1' '  rm -f -- "$cache_file" || refuse "cache=remove-failed path=$cache_file"'
"$mutant" off >/dev/null 2>&1 || true
check "the disarm-refuses-first control's root off leaves the table" table_armed
mutant off-exits-early '  disarm || true
  try_lock' '  disarm || refuse "$disarm_error" "$disarm_note"
  try_lock'
"$mutant" off >/dev/null 2>&1 || true
check "the off-exits-early control's root off leaves the state meant on" grep -qx "meant-on=$uuid" "$state"
mutant arm-refuses-first '  rm -f -- "$cache_file" || cache_error="cache=remove-failed path=$cache_file"
  arm
' '  rm -f -- "$cache_file" || refuse "cache=remove-failed path=$cache_file"
  arm
'
delete_tables
"$mutant" sync >/dev/null 2>&1 || true
check "the arm-refuses-first control's sync leaves no table" table_absent
umount /var/lib/vgshell/kill-switch
write_state "" block
run_sync
check "with the cache writable again a sync disarms" synced disarmed
printf 'version=1\nmeant-on=\nkill-switch=block\nportal-until=0\nextra=1\n' >"$state"
run_sync
check "an unknown key is refused" refused "$tmp/sync.err" "$sync_status" "state=malformed path=$state"
unprivileged "$script" sync >/dev/null 2>"$tmp/unprivileged-sync.err" || true
check "sync refuses an unprivileged caller" test "$(head -n 1 "$tmp/unprivileged-sync.err")" == "vgs-kill-switch: refused: caller=unprivileged"

# ---------------------------------------------------------------- the unit's limits

# A start of vgs-kill-switch.service as at boot, under the limits its unit
# file names, read from that file: ExecStartPre= as root with every
# capability and the unit's UMask=, onto a /run that holds no lock, then
# sync in a mount namespace of its own, read-only but for each
# ReadWritePaths= entry, the StateDirectory=, /tmp, which PrivateTmp= keeps
# writable, and this suite's own directory, where the stand-ins log; through
# setpriv, with no new privileges and the unit's capability bounding set.
# The owner setpriv takes here is uid 0, the namespace's only one, so no
# control shows CAP_SETUID, CAP_SETGID or CAP_KILL needed: each acts only
# toward a second uid. The controls drop CAP_NET_ADMIN, and
# CAP_DAC_READ_SEARCH with the state directory at mode 0000, which denies
# root, its owner here, the search an owner's mode 0700 denies root.
unit_file="$repo/config/system/kill-switch/vgs-kill-switch.service"
service_value() { awk -v key="$1=" '/^\[/ { inside = ($0 == "[Service]") } inside && index($0, key) == 1 { print substr($0, length(key) + 1) }' "$unit_file"; } # KEY
unit_caps="$(service_value CapabilityBoundingSet)"
unit_writable="$(service_value ReadWritePaths)"
unit_state_dir="$(service_value StateDirectory)"
unit_state_mode="$(service_value StateDirectoryMode)"
unit_pre="$(service_value ExecStartPre)"
unit_umask="$(service_value UMask)"
one_line() { [[ -n $1 && $1 != *$'\n'* ]]; } # VALUE
for key in caps writable state_dir state_mode pre umask; do
  value="unit_$key"
  check "the unit names its $key once" one_line "${!value}"
done
check "the unit's pre-start runs with full privileges" test "${unit_pre:0:1}" == +
read -r -a unit_pre_argv <<<"${unit_pre#+}"
read -r -a unit_cap_list <<<"$unit_caps"
read -r -a unit_writable_list <<<"$unit_writable"
unit_state_path="/var/lib/$unit_state_dir"
# setpriv's --bounding-set form of the unit's capabilities, less DROPPED.
bounding_set() { # [DROPPED]
  local cap set=-all
  for cap in "${unit_cap_list[@]}"; do
    [[ $cap != "${1-}" ]] || continue
    cap="${cap#CAP_}"
    set+=",+${cap,,}"
  done
  printf '%s' "$set"
}
# setattr.py ro|rw PATH: adds the read-only attribute to the mount at PATH
# and every mount below it, or clears it from that mount alone, through
# mount_setattr(2), which sets and clears only the attributes it names. A
# mount flag propagated from a more privileged mount namespace is locked
# (mount_namespaces(7)), and under scripts/validate's world, whose mounts
# reach this one through two user namespaces, `mount -o
# remount,bind,ro=recursive /` was refused (`mount: /: permission denied`,
# 2026-11-11).
cat >"$tmp/setattr.py" <<'EOF'
import ctypes, os, sys
class MountAttr(ctypes.Structure):
    _fields_ = [("attr_set", ctypes.c_uint64), ("attr_clr", ctypes.c_uint64),
                ("propagation", ctypes.c_uint64), ("userns_fd", ctypes.c_uint64)]
AT_FDCWD, AT_RECURSIVE, MOUNT_ATTR_RDONLY = -100, 0x8000, 0x1
mode, path = sys.argv[1:]
libc = ctypes.CDLL(None, use_errno=True)
if mode == "ro":
    attr, flags = MountAttr(MOUNT_ATTR_RDONLY, 0, 0, 0), AT_RECURSIVE
else:
    attr, flags = MountAttr(0, MOUNT_ATTR_RDONLY, 0, 0), 0
if libc.mount_setattr(AT_FDCWD, path.encode(), flags, ctypes.byref(attr), ctypes.c_size_t(ctypes.sizeof(attr))) != 0:
    sys.exit("setattr: %s %s: %s" % (mode, path, os.strerror(ctypes.get_errno())))
EOF
# limited.sh SETPRIV CAPS PATH... -- COMMAND...: COMMAND in the caller's new
# mount namespace, made read-only but for each PATH, one with a leading -
# skipped while missing, as ReadWritePaths= skips it; through SETPRIV, with
# CAPS as its --bounding-set and no new privileges. Exits 75 when it cannot
# build that view.
cat >"$tmp/limited.sh" <<EOF
set -uo pipefail
setattr="$tmp/setattr.py"
EOF
cat >>"$tmp/limited.sh" <<'EOF'
setpriv="$1" caps="$2"
shift 2
python3 -I "$setattr" ro / || exit 75
while [[ $1 != -- ]]; do
  path="${1#-}"
  if [[ $1 != -* || -e $path ]]; then
    mount --rbind "$path" "$path" && python3 -I "$setattr" rw "$path" || exit 75
  fi
  shift
done
shift
exec "$setpriv" --bounding-set="$caps" --inh-caps=-all --no-new-privs -- "$@"
EOF
# COMMAND as the unit's ExecStart= runs, with CAPS for its bounding set.
limited() { # CAPS COMMAND...
  unshare --mount --propagation private -- "$BASH" "$tmp/limited.sh" "$real_setpriv" "$1" \
    /tmp "$tmp" "$unit_state_path" "${unit_writable_list[@]}" -- "${@:2}"
}
# What systemd does before ExecStart=: the state directory, root's, with
# the unit's mode, then ExecStartPre= with the unit's umask.
pre_start() {
  mkdir -p -- "$unit_state_path"
  chmod -- "$unit_state_mode" "$unit_state_path"
  (umask "$unit_umask" && "${unit_pre_argv[@]}")
}
# A start with CAPS for the bounding set, setting sync_status and sync_out
# as run_sync does.
unit_sync() { # CAPS
  pre_start || true
  sync_status=0
  sync_out="$(limited "$1" "$script" sync 2>"$tmp/sync.err")" || sync_status=$?
}
# The errno name a create of PATH meets under the unit's limits, or created.
create_errno='import errno, os, sys
try:
    os.close(os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
    print("created")
except OSError as error:
    print(errno.errorcode[error.errno])'
limited_create() { limited "$(bounding_set)" python3 -I -c "$create_errno" "$1" 2>/dev/null || echo run-failed; } # PATH

# The checks under the unit's limits, which run once the view builds.
unit_limits() {
  write_state "$uuid" block
  delete_tables
  rm -f -- "$lock"
  pre_start || true
  check "the unit's pre-start makes the missing lock root's alone before sync opens it" test "$(stat -c '%u %a' -- "$lock")" == "0 600"
  touch "$pending"
  unit_sync "$(bounding_set)"
  check "under the unit's limits sync arms" synced armed
  check "under the unit's limits both tables are armed" table_armed
  check "under the unit's limits sync removes the pending mark" test ! -e "$pending"
  check "under the unit's limits the status reads passing for the profile it cached" status_is "state=passing reason=tunnel-up" "tunnel=wgnord" "profile=$uuid"
  check "under the unit's limits a file in /run is refused as read-only" test "$(limited_create /run/vgs-limited-probe)" == EROFS
  check "under the unit's limits a file beside the state directories is refused as read-only" test "$(limited_create /var/lib/vgshell/limited-probe)" == EROFS
  delete_tables
  unit_sync "$(bounding_set CAP_NET_ADMIN)"
  check "the net-admin-less control refuses as an unprivileged caller" refused "$tmp/sync.err" "$sync_status" caller=unprivileged
  check "the net-admin-less control leaves no table" table_absent
  chmod 0000 /var/lib/vgshell/vpn
  unit_sync "$(bounding_set)"
  check "under the unit's limits a state directory root may not search arms" synced armed
  delete_tables
  unit_sync "$(bounding_set CAP_DAC_READ_SEARCH)"
  check "the read-search-less control reads that state as missing and disarms" synced disarmed
  check "the read-search-less control leaves no table" table_absent
  chmod 0755 /var/lib/vgshell/vpn
}
# A host that cannot build the read-only view, as one whose kernel or
# seccomp policy refuses mount_setattr(2), holds no reading of the
# limits: the suite reads not-measured at its end, after its other checks.
limited_view=0
limited "$(bounding_set)" true 2>"$tmp/limited.err" || limited_view=$?
case "$limited_view" in
  0) unit_limits ;;
  75) printf '        limited view: err=[%s]\n' "$(head -c 400 "$tmp/limited.err")" ;;
  *) fail "the limited view runs a command"; printf '        exit=%s err=[%s]\n' "$limited_view" "$(head -c 400 "$tmp/limited.err")" ;;
esac
check "no status instance refused" lacks "vgs-kill-switch: refused" "$tmp/status.err"

if ((failures)); then printf '%s: failed=%s\n' "$suite" "$failures"; exit 1; fi
((limited_view != 75)) || { printf '%s: status=not-measured reason=limited-view\n' "$suite"; exit 77; }
printf '%s: passed\n' "$suite"
