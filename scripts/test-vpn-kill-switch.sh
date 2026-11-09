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
# reason=<key>` and exits 77.
#
# `unshare --user --map-root-user --net --mount` makes the laptop. tmpfs
# mounts there give it its own /run, /var/lib and /usr/local, so the
# script's fixed paths and its PATH reach only this suite's files: a stand-in
# nmcli answers the fixture profiles and a stand-in systemctl answers
# whether NetworkManager runs, from /usr/local/sbin. `ip netns add hotel`
# makes the hotel, joined to the laptop's wlan0 by a veth pair. The hotel
# holds the gateway and DNS server 192.168.50.1, the internet hosts
# 203.0.113.10 and 2001:db8:ff::10, and the capture of every frame wlan0
# sends (scripts/fixtures/kill-switch/hotel.py). A second veth pair stands
# in for tailscale0, with 100.100.100.100 on its far end. A third namespace,
# the box, routes through the laptop as a container would. The status socket
# is served by systemd-socket-activate, as vgs-kill-switch-status.socket
# serves it, and read by a process with every capability dropped.
#
# Each probe round sends, in order, an IPv4 ping and TCP connect, an IPv6
# ping and TCP connect, dig over UDP and TCP to the hotel's resolver, a
# ping to the hotel's gateway, a ping and TCP connect over tailscale0, a loopback ping, UDP to each
# WireGuard peer and last a ping marked as Tailscale marks its packets. The
# capture holding that last ping proves every earlier frame was read.
set -euo pipefail

suite=test-vpn-kill-switch
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
script="$repo/config/system/kill-switch/vgs-kill-switch"
hotel_py="$repo/scripts/fixtures/kill-switch/hotel.py"

not_measured() { printf '%s: status=not-measured reason=%s\n' "$suite" "$1"; exit 77; } # KEY

if [[ ${1-} != --laptop ]]; then
  (($# == 0)) || exit 2
  for tool in unshare ip nft setpriv python3 dig ping timeout flock mount systemd-socket-activate; do
    command -v "$tool" >/dev/null || not_measured "missing-$tool"
  done
  unshare --user --map-root-user --net --mount true 2>/dev/null || not_measured user-namespaces
  TMP_ROOT="$(mktemp -d)" || { echo "$suite: scratch=mktemp-failed" >&2; exit 1; }
  [[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "$suite: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
  TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "$suite: scratch=resolve-failed" >&2; exit 1; }
  trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
  status=0
  env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 HOME="$TMP_ROOT" \
    unshare --user --map-root-user --net --mount --propagation private -- "$BASH" "$self" --laptop "$TMP_ROOT" || status=$?
  exit "$status"
fi

# ---------------------------------------------------------------- the laptop

tmp="$2"
state=/var/lib/vgshell/vpn/state
cache=/var/lib/vgshell/kill-switch/profile
frames="$tmp/frames.log"
uuid=2f0c7b1e-5d3a-4c8e-9b6f-1a2b3c4d5e6f
other_uuid=9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d
key_a=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
key_b=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
peers="$key_a endpoint=203.0.113.51:51820 allowed-ips=0.0.0.0/0 persistent-keepalive=25, $key_b endpoint=[2001:db8:ff::51]:51820 allowed-ips=::/0"

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
for dir in /run /var/lib /usr/local; do
  mount -t tmpfs -o mode=0755 tmpfs "$dir" || not_measured "mount-$dir"
done
mkdir -p /usr/local/sbin /var/lib/vgshell/vpn

# nmcli answers the two reads the script makes from $tmp/nm/<uuid>.{type,ifname,peers}
# and exits 10, nmcli's no-such-connection status, for a uuid with no type
# file; every call lands in $tmp/nmcli.log.
mkdir -p "$tmp/nm"
cat >/usr/local/sbin/nmcli <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/nmcli.log"
[ "\$1 \$2 \$3" = "--escape no -g" ] && [ "\$5 \$6 \$7" = "connection show uuid" ] && [ \$# = 8 ] || exit 2
nm="$tmp/nm/\$8"
[ -f "\$nm.type" ] || exit 10
case "\$4" in
  connection.type,connection.interface-name) cat "\$nm.type" "\$nm.ifname" ;;
  wireguard.peers) cat "\$nm.peers" ;;
  *) exit 2 ;;
esac
EOF
# systemctl answers only whether NetworkManager runs: yes, unless
# $tmp/nm-inactive exists.
cat >/usr/local/sbin/systemctl <<EOF
#!/bin/sh
[ "\$*" = "is-active --quiet NetworkManager.service" ] || exit 64
[ ! -e "$tmp/nm-inactive" ]
EOF
# setpriv records the argv the script passes and runs the real setpriv with
# --keep-groups for --clear-groups: an unprivileged namespace may never call
# setgroups(2) (user_namespaces(7), /proc/[pid]/setgroups), and it maps no
# supplementary group to keep.
cat >/usr/local/sbin/setpriv <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/setpriv.log"
args=""
for a; do [ "\$a" = --clear-groups ] && a=--keep-groups; args="\$args '\$a'"; done
eval "set -- \$args"
exec $real_setpriv "\$@"
EOF
chmod 0755 /usr/local/sbin/nmcli /usr/local/sbin/systemctl /usr/local/sbin/setpriv
profile() { # UUID TYPE IFNAME PEERS
  printf '%s\n' "$2" >"$tmp/nm/$1.type"
  printf '%s\n' "$3" >"$tmp/nm/$1.ifname"
  printf '%s\n' "$4" >"$tmp/nm/$1.peers"
}

# The topology. Static neighbours keep address resolution out of the
# capture and out of the probes' time.
ip link set lo up
ip netns add hotel
ip link add wlan0 type veth peer name hotel0 netns hotel
ip link add tailscale0 type veth peer name tspeer netns hotel
ip link add wgnord type wireguard || not_measured wireguard-link
ip addr add 192.168.50.2/24 dev wlan0
ip -6 addr add 2001:db8:50::2/64 dev wlan0 nodad
ip link set wlan0 up
ip route add default via 192.168.50.1
ip -6 route add default via 2001:db8:50::1
ip addr add 100.101.1.2/32 dev tailscale0
ip link set tailscale0 up
ip route add 100.64.0.0/10 dev tailscale0
# The box, a container routed through the laptop.
ip netns add box
ip link add lbox type veth peer name box0 netns box
ip addr add 10.88.0.1/24 dev lbox
ip link set lbox up
echo 1 >/proc/sys/net/ipv4/ip_forward
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
  ip route add 10.88.0.0/24 via 100.101.1.2 dev tspeer onlink
'
link_mac() { # LINK: the laptop link's address, read through netlink, never /sys, which shows the host's links
  local out
  out="$(ip -o link show dev "$1")" && [[ $out =~ link/ether\ ([^ ]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}
hotel_mac="$(ip netns exec hotel cat /sys/class/net/hotel0/address)"
wlan_mac="$(link_mac wlan0)"
ip neigh replace 192.168.50.1 lladdr "$hotel_mac" dev wlan0 nud permanent
ip -6 neigh replace 2001:db8:50::1 lladdr "$hotel_mac" dev wlan0 nud permanent
ip netns exec hotel ip neigh replace 192.168.50.2 lladdr "$wlan_mac" dev hotel0 nud permanent
ip netns exec hotel ip -6 neigh replace 2001:db8:50::2 lladdr "$wlan_mac" dev hotel0 nud permanent

: >"$frames"
ip netns exec hotel python3 -I "$hotel_py" serve hotel0 "$frames" "$tmp/hotel-ready" &
hotel_pid=$!
await test -e "$tmp/hotel-ready" || not_measured hotel-start
systemd-socket-activate --inetd -a -l /run/vgs-kill-switch.sock "$script" status 2>"$tmp/status.err" &
status_pid=$!
await test -S /run/vgs-kill-switch.sock || not_measured status-socket

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
# Sets line to the status line the socket serves to the unprivileged reader,
# and blocked to its count.
read_status() {
  line="$(unprivileged "$script" status 2>"$tmp/status-read.err")" || line="unreadable"
  blocked=-1
  [[ $line =~ \ blocked=([0123456789]+)\  ]] && blocked="${BASH_REMATCH[1]}"
  return 0
}
status_is() { read_status; [[ ${line% blocked=*} == "$1" && ${line##* } == "$2" ]]; } # "state=… reason=…" tunnel=…
table_armed() { local out; out="$(nft list tables inet)" && [[ $out == *"table inet vgshell_kill_switch"* ]]; }
table_absent() { local out; out="$(nft list tables inet)" && [[ $out != *vgshell_kill_switch* ]]; }
fails() { ! "$@" >/dev/null 2>&1; } # COMMAND...
succeeds() { "$@" >/dev/null 2>&1; } # COMMAND...
lacks() { local out; out="$(<"$2")" && [[ $out != *"$1"* ]]; } # TEXT FILE: FILE reads, and holds no TEXT
# nft wraps a long element list, so both sides are read without whitespace.
set_holds() { local out; out="$(nft list set inet vgshell_kill_switch "$1")" && [[ ${out//[[:space:]]/} == *"${2//[[:space:]]/}"* ]]; } # SET TEXT
set_empty() { local out; out="$(nft list set inet vgshell_kill_switch "$1")" && [[ $out != *elements* ]]; } # SET

# probe_round NAME: runs every probe from the list in the header, writes
# `<probe>=pass|fail` lines to $tmp/NAME.results and the capture's
# `<probe>=<frames>` lines to $tmp/NAME.frames.
probe_round() { # NAME
  local name="$1" start results="$tmp/$1.results" probe
  start=$(($(wc -l <"$frames") + 1))
  : >"$results"
  probe() { # PROBE COMMAND...
    local probe="$1"
    shift
    if "$@" >/dev/null 2>&1; then echo "$probe=pass" >>"$results"; else echo "$probe=fail" >>"$results"; fi
  }
  probe ping4 ping -n -c1 -W1 203.0.113.10
  probe tcp4 timeout 2 bash -c 'exec 3<>/dev/tcp/203.0.113.10/80'
  probe ping6 ping -6 -n -c1 -W1 2001:db8:ff::10
  probe tcp6 timeout 2 bash -c 'exec 3<>/dev/tcp/2001:db8:ff::10/80'
  probe dns-udp dig +notcp +tries=1 +time=1 @192.168.50.1 example.com
  probe dns-tcp dig +tcp +tries=1 +time=1 @192.168.50.1 example.com
  probe lan-ping ping -n -c1 -W1 192.168.50.1
  probe ts-ping ping -n -c1 -W1 100.100.100.100
  probe ts-tcp timeout 2 bash -c 'exec 3<>/dev/tcp/100.100.100.100/80'
  probe lo-ping ping -n -c1 -W1 127.0.0.1
  probe peer4 bash -c 'printf x >/dev/udp/203.0.113.51/51820'
  probe peer6 bash -c 'printf x >/dev/udp/2001:db8:ff::51/51820'
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

check "with no state file the status socket reads off" status_is "state=off reason=disarmed" "tunnel="
check "the status line names no count but zero while off" test "$blocked" == 0

write_state "$uuid" block
run_sync
check "sync arms for a meant-on WireGuard profile" synced armed
check "the table holds each IPv4 peer endpoint" set_holds peers4 "203.0.113.51 . 51820"
check "the table holds each IPv6 peer endpoint" set_holds peers6 "2001:db8:ff::51 . 51820"
check "the tunnels set holds the profile's interface and tailscale0" set_holds tunnel_links '"tailscale0", "wgnord"'
check "block leaves the local network out" set_empty lan4
check "the profile reading is cached root's, mode 0600" test "$(stat -c '%u %a' -- "$cache")" == "0 600"
check "with the tunnel up the status reads passing" status_is "state=passing reason=tunnel-up" "tunnel=wgnord"

ip link del wgnord
check "with the tunnel gone the status reads holding" status_is "state=holding reason=tunnel-down" "tunnel=wgnord"
blocked_before="$blocked"
probe_round armed
expect_round armed "
ping4 fail 0
tcp4 fail 0
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
marked pass some"
read_status
check "the blocked count rose with the refused probes" test "$blocked" -gt "$blocked_before"
blocked_armed="$blocked"
check "the status still reads holding after the probes" status_is "state=holding reason=tunnel-down" "tunnel=wgnord"
check "the unprivileged reader cannot list the rule itself" fails unprivileged nft list ruleset
check "the same listing with CAP_NET_ADMIN succeeds" succeeds nft list ruleset

# A container or virtual machine routed through the laptop: what it sends
# out the Wi-Fi is refused, and what it reaches through a tunnel answers.
start=$(($(wc -l <"$frames") + 1))
check "a forwarded ping out the Wi-Fi is refused" fails ip netns exec box ping -n -c1 -W1 203.0.113.10
check "a forwarded ping through tailscale0 is answered" succeeds ip netns exec box ping -n -c1 -W1 100.100.100.100
ping -n -c1 -W1 -m 524288 203.0.113.20 >/dev/null 2>&1 || true
check "the capture read every forwarded frame" await marked_seen "$start"
check "the capture holds no forwarded ping" test "$(python3 -I "$hotel_py" count "$frames" "$start" | sed -n 's/^ping4=//p')" == 0

run_sync
read_status
check "a sync while armed keeps the blocked count" test "$blocked" -ge "$blocked_armed"

# The local-network allowance passes the hotel's own hosts but never its DNS.
write_state "$uuid" block-lan
run_sync
check "block-lan arms" synced armed
check "block-lan fills the local ranges" set_holds lan4 "192.168.0.0/16"
probe_round lan
expect_round lan "
lan-ping pass some
dns-udp fail 0
dns-tcp fail 0
ping4 fail 0"

# The control: the same probes with the switch off leave and are captured.
write_state "$uuid" off
run_sync
check "kill-switch=off disarms" synced disarmed
check "kill-switch=off leaves no table" table_absent
check "kill-switch=off removes the profile cache" test ! -e "$cache"
check "the status reads off with the switch off" status_is "state=off reason=disarmed" "tunnel="
probe_round control
expect_round control "
ping4 pass some
tcp4 pass some
ping6 pass some
tcp6 pass some
dns-udp pass some
dns-tcp pass some
lan-ping pass some
ts-ping pass -
lo-ping pass -
marked pass some"

# Off on purpose: meant-on cleared, as the VPN panel and off write it.
write_state "$uuid" block
run_sync
check "a second arm succeeds" synced armed
write_state "" block
run_sync
check "meant-on cleared disarms" synced disarmed
check "meant-on cleared leaves no table" table_absent
probe_round off
expect_round off "
ping4 pass some
dns-udp pass some"

# The one-command clear: `sudo vgs-kill-switch off`, with no unit running.
write_state "$uuid" block-lan 0
run_sync
check "arm before the clear" synced armed
clear_out="$("$script" off 2>"$tmp/off.err")" || clear_out="exit=$?"
check "the root clear reports off" test "$clear_out" == "ok state=off"
check "the root clear deletes the table at once" table_absent
check "the root clear removes the cache" test ! -e "$cache"
check "the root clear writes meant-on= and keeps the other keys" test "$(cat "$state")" == "$(printf 'version=1\nmeant-on=\nkill-switch=block-lan\nportal-until=0')"

# The user's off: it writes the file, and the sync the path unit would run
# lets its status wait end.
write_state "$uuid" block
run_sync
check "arm before the user's off" synced armed
unprivileged "$script" off >"$tmp/user-off.out" 2>"$tmp/user-off.err" &
user_off_pid=$!
check "the user's off writes meant-on=" await grep -qx 'meant-on=' "$state"
run_sync
user_off_status=0
wait "$user_off_pid" || user_off_status=$?
check "after the sync the user's off reports off" test "$user_off_status $(cat "$tmp/user-off.out")" == "0 ok state=off"
check "the user's off left a file of the state grammar, mode 0644" test "$(stat -c %a -- "$state") $(cat "$state")" == "644 $(printf 'version=1\nmeant-on=\nkill-switch=block\nportal-until=0')"

# A sign-in page opens DNS, HTTP and HTTPS for at most five minutes; a past
# time opens nothing.
printf -v now '%(%s)T' -1
write_state "$uuid" block $((now + 3600))
run_sync
check "a sign-in time arms" synced armed
check "a sign-in time opens DNS, HTTP and HTTPS" set_holds portal "53 timeout 5m"
check "a sign-in time opens HTTPS" set_holds portal "443 timeout 5m"
write_state "$uuid" block $((now - 10))
run_sync
check "a past sign-in time opens nothing" set_empty portal

# Profiles the switch cannot pass read unavailable and stay closed. Each row:
# setup, the status it reads, then the peers4 element it must or must not hold.
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
rm -f -- "$cache"
run_sync
check "with no cache the switch arms closed" synced armed
check "with no cache only tailscale0 passes" set_holds tunnel_links 'elements = { "tailscale0" }'
check "with no cache the status names why" status_is "state=unavailable reason=profile-unread" "tunnel="
write_state "$other_uuid" block
run_sync
check "a cache for another profile is not read" status_is "state=unavailable reason=profile-unread" "tunnel="
rm -f -- "$tmp/nm-inactive"
while IFS='|' read -r row kind ifname peer_text want_status want_tunnel; do
  [[ -n $row ]] || continue
  profile "$other_uuid" "$kind" "$ifname" "$peer_text"
  run_sync
  check "$row: arms closed" synced armed
  check "$row: the status names why" status_is "$want_status" "$want_tunnel"
  check "$row: no peer passes" set_empty peers4
done <<EOF
not WireGuard|vpn|tun0|$peers|state=unavailable reason=profile-not-wireguard|tunnel=
host name endpoint|wireguard|wgnord|$key_a endpoint=vpn.example.com:51820|state=unavailable reason=endpoint-hostname|tunnel=wgnord
out of range port|wireguard|wgnord|$key_a endpoint=203.0.113.51:70000|state=unavailable reason=endpoint-invalid|tunnel=wgnord
zone in an IPv6 endpoint|wireguard|wgnord|$key_a endpoint=[fe80::1%wlan0]:51820|state=unavailable reason=endpoint-invalid|tunnel=wgnord
interface name with a slash|wireguard|wg/0|$peers|state=unavailable reason=interface-invalid|tunnel=
EOF
rm -f -- "$tmp/nm/$other_uuid".*
run_sync
check "a deleted profile arms closed" status_is "state=unavailable reason=profile-missing" "tunnel="

# A state file outside the grammar changes nothing and is never printed.
write_state "$uuid" block
run_sync
printf 'version=1\nmeant-on=leaked-text-%s\nkill-switch=block\nportal-until=0\n' "$uuid" >"$state"
run_sync
check "a malformed state file is refused" test "$sync_status $(head -n 1 "$tmp/sync.err")" == "1 vgs-kill-switch: refused: state=malformed path=$state"
check "the refusal never prints the file" lacks leaked-text "$tmp/sync.err"
check "the rule stays armed past a malformed file" table_armed
printf 'version=1\nmeant-on=\nkill-switch=block\nportal-until=0\nextra=1\n' >"$state"
run_sync
check "an unknown key is refused" test "$sync_status" == 1
unprivileged "$script" sync >/dev/null 2>"$tmp/unprivileged-sync.err" || true
check "sync refuses an unprivileged caller" test "$(head -n 1 "$tmp/unprivileged-sync.err")" == "vgs-kill-switch: refused: caller=unprivileged"
check "no status instance refused" lacks "vgs-kill-switch: refused" "$tmp/status.err"

if ((failures)); then printf '%s: failed=%s\n' "$suite" "$failures"; exit 1; fi
printf '%s: passed\n' "$suite"
