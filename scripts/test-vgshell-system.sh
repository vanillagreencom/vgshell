#!/usr/bin/env bash
# Controls for bin/vgshell-system, the closed table of system steps reached
# through `vgshell system`: the verbs and their arguments, each step's probe,
# root commands and record bytes, the one question before any write, the
# refusal of a destination VGS did not write, an undo that reverts only
# what VGS changed, the record's owner, and the NixOS configuration-only
# path. Every row runs a copy of vgshell and of the helper whose `prefix` is a
# temporary tree, so its /etc, /sys, /dev, /proc, /var and /usr are that
# tree's: sudo, gum, stat, udevadm, systemctl, modprobe, tailscale, getent,
# greetd and start-hyprland are stand-ins there, and the sudo stand-in runs
# each command under `unshare -r`, where the tree reads as root's and
# nothing outside it is writable, so no row reaches the real /etc, /dev,
# sudo, udev, systemd, greetd, PAM or tailscaled. NixOS rows bind a fixture
# over /etc/os-release in a private mount namespace, as
# scripts/test-vgshell-sudo-grant.sh does. The controls are copies of the
# helper missing one rule each.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
suite=test-vgshell-system
source_file="$repo/bin/vgshell-system"
uid="$(id -u)"; gid="$(id -g)"; user="$(id -un)"
((uid != 0)) || { echo "$suite: status=not-measured reason=runs-as-root"; exit 77; }
for tool in unshare setsid script find mount sh sha256sum; do
  command -v "$tool" >/dev/null || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
done
unshare_bin="$(command -v unshare)"; setsid_bin="$(command -v setsid)"; script_bin="$(command -v script)"
mount_bin="$(command -v mount)"; sh_bin="$(command -v sh)"; stat_bin="$(command -v stat)"
"$unshare_bin" -r true 2>/dev/null || { echo "$suite: status=not-measured missing=user-namespaces"; exit 77; }

root="$tmp/root"; bin="$root/usr/bin"
vgs="$tmp/vgshell"; helper="$vgs/bin/vgshell-system"
rule_src="$vgs/config/system/udev/60-vgs-apple-displays.rules"
rule="$root/etc/udev/rules.d/60-vgs-apple-displays.rules"
records="$root/var/lib/vgshell/system"
hidraw="$root/dev/hidraw0"
greeter_src="$vgs/config/system/greeter"
greeter_toml="$root/etc/greetd/vgshell.toml"
greeter_pam="$root/etc/pam.d/vgs-greeter"
dropin_dir="$root/etc/systemd/system/greetd.service.d"
greeter_dropin="$dropin_dir/vgs.conf"
greeter_dir="$root/var/lib/vgshell/greeter"
mkdir -p "$bin" "$vgs/bin" "$vgs/shell/Core" "$vgs/shell/plugins/vgs.greeter" "$vgs/config/system/udev" "$tmp/home"
cp -- "$repo/bin/vgshell" "$vgs/bin/vgshell"
cp -- "$repo/bin/vgshell-pkg" "$vgs/bin/vgshell-pkg"
cp -R -- "$repo/bin/lib" "$vgs/bin/lib"
cp -- "$repo/shell/Core/PackageManagers.js" "$vgs/shell/Core/PackageManagers.js"
cp -- "$repo/config/system/udev/60-vgs-apple-displays.rules" "$rule_src"
cp -R -- "$repo/config/system/greeter" "$greeter_src"
cp -- "$repo/shell/plugins/vgs.greeter/Greeter.qml" "$vgs/shell/plugins/vgs.greeter/Greeter.qml"
cp -- "$repo/shell/greeter.qml" "$vgs/shell/greeter.qml"
# The greeter account runs the install tree, so only its owner, root as the
# stat stand-in reads it, may write it, and other users read it.
chmod -R go-w "$vgs"
chmod 0755 "$vgs" "$vgs/shell" "$vgs/config" "$vgs/config/system" "$greeter_src"
for tool in awk cat chmod chown env flock id install mkdir mv readlink rm rmdir sed sha256sum sleep kill tee touch; do
  tool_bin="$(command -v "$tool")" || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$bin/$tool"
done
# stat reports owner 0 for the suite's own files in an owner-and-mode read,
# as the tree reads under unshare -r, and the owner a line `<uid> <path>`
# of $tmp/owners names for that path in any read. A directory above the
# suite's tree, $tmp itself included, reads `0 755`, as the directories
# above an install under /usr do, so the greeter's install-untrusted rows
# turn on the tree's own owners and modes alone.
cat >"$bin/stat" <<EOF
#!/bin/sh
for last; do :; done
if [ "\$1 \$2" = "-c %u %a" ]; then
  case "$tmp/" in "\$last"/*) echo "0 755"; exit 0 ;; esac
  [ "\$last" = / ] && { echo "0 755"; exit 0; }
fi
out="\$($stat_bin "\$@")" || exit \$?
owner=""
[ -f "$tmp/owners" ] && owner="\$(awk -v p="\$last" '{ u = \$1; sub(/^[^ ]* /, ""); if (\$0 == p) o = u } END { print o }' "$tmp/owners")"
if [ -n "\$owner" ]; then printf '%s\n' "\$out" | sed "s/^[0-9][0-9]*/\$owner/"; else printf '%s\n' "\$out" | sed 's/^$uid /0 /'; fi
EOF
# sudo: -k and -n are recorded and answer at once; any other call is
# recorded, exits with $tmp/sudo-exit when present, else runs its command
# as the namespace's root. Only root maps under unshare -r, so an install's
# -o and -g owner reads 0 there, which is the suite's own account outside;
# the log keeps the owner the step asked for.
cat >"$bin/sudo" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/sudo.log"
case "\$1" in -k|-n) exit 0 ;; esac
[ "\$1" = -- ] && shift
if [ -f "$tmp/sudo-exit" ]; then read -r st <"$tmp/sudo-exit"; exit "\$st"; fi
if [ "\${1##*/}" = install ]; then
  args="" prev=""
  for a; do
    case "\$prev" in -o|-g) a=0 ;; esac
    args="\$args '\$a'"
    prev="\$a"
  done
  eval "set -- \$args"
fi
exec $unshare_bin -r "\$@"
EOF
# udevadm: a trigger gives the Apple node the access the rule grants while
# the VGS rule or $tmp/other-rule exists, and takes it away otherwise; it
# fails while $tmp/udev-fail exists.
cat >"$bin/udevadm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/udevadm.log"
[ -e "$tmp/udev-fail" ] && exit 1
if [ "\$1" = trigger ]; then
  if [ -e "$rule" ] || [ -e "$tmp/other-rule" ]; then chmod 0600 "$hidraw"; else chmod 0000 "$hidraw"; fi
fi
exit 0
EOF
# systemctl answers from $tmp/units/<unit>.{active,enabled,masked,missing};
# display-manager.service is an alias of the unit $tmp/units/display-manager
# names, else of an enabled greetd.service, else of no unit; the default
# target is the one $tmp/units/default-target names, else graphical.target.
cat >"$bin/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/systemctl.log"
u="$tmp/units"
case "\$1 \$2" in
  "is-active --quiet") [ -e "\$u/\$3.active" ] ;;
  "is-enabled --quiet") [ -e "\$u/\$3.enabled" ] ;;
  "show --property=LoadState")
    if [ -e "\$u/\$4.missing" ]; then echo not-found; elif [ -e "\$u/\$4.masked" ]; then echo masked; else echo loaded; fi ;;
  "show --property=Id")
    [ "\$4" = display-manager.service ] || exit 64
    if [ -e "\$u/display-manager" ]; then cat "\$u/display-manager"; elif [ -e "\$u/greetd.service.enabled" ]; then echo greetd.service; else echo display-manager.service; fi ;;
  "enable --now") touch "\$u/\$3.enabled" "\$u/\$3.active" ;;
  "enable "*) touch "\$u/\$2.enabled" ;;
  "disable "*) rm -f "\$u/\$2.enabled" ;;
  "stop "*) rm -f "\$u/\$2.active" ;;
  "daemon-reload ") ;;
  "get-default ") if [ -e "\$u/default-target" ]; then cat "\$u/default-target"; else echo graphical.target; fi ;;
  "set-default "*) printf '%s\n' "\$2" >"\$u/default-target" ;;
  *) exit 64 ;;
esac
EOF
# getent answers one greeter account, the one $tmp/greeter-name names, else
# `greeter`; none while $tmp/no-greeter exists, and it fails while
# $tmp/getent-fail exists.
cat >"$bin/getent" <<EOF
#!/bin/sh
[ -e "$tmp/getent-fail" ] && exit 3
[ "\$1" = passwd ] || exit 64
[ -e "$tmp/no-greeter" ] && exit 2
name=greeter
[ -e "$tmp/greeter-name" ] && read -r name <"$tmp/greeter-name"
[ "\$2" = "\$name" ] || exit 2
echo "\$name:x:958:958:greetd greeter user:/:/bin/bash"
EOF
# greetd and start-hyprland are only found; no row runs them.
printf '#!/bin/sh\nexit 64\n' >"$bin/greetd"
printf '#!/bin/sh\nexit 64\n' >"$bin/start-hyprland"
# These stand-ins store capability text beside the fixture binary. They
# never read or write security.capability, and bandwhich never captures.
cat >"$bin/getcap" <<EOF
#!/bin/sh
[ -e "$tmp/getcap-fail" ] && exit 1
for last; do :; done
printf '%s\n' "\$last" >>"$tmp/capture-probes"
caps="$tmp/capture-caps"
case "\$last" in "$root/run/wrappers/"*) caps="$tmp/wrapper-caps" ;; esac
[ -s "\$caps" ] || exit 0
printf '%s %s\n' "\$last" "\$(cat "\$caps")"
EOF
cat >"$bin/setcap" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/setcap.log"
[ -e "$records/bandwhich-capture" ] || exit 64
[ -e "$tmp/setcap-fail" ] && exit 1
case "\$1" in
  -r) : >"$tmp/capture-caps" ;;
  *) printf '%s\n' 'cap_dac_read_search,cap_net_admin,cap_net_raw,cap_sys_ptrace=ep' >"$tmp/capture-caps" ;;
esac
EOF
# modprobe i2c-dev registers the class and the display adapter's node,
# readable while $tmp/i2c-rule exists; -r takes both away.
cat >"$bin/modprobe" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/modprobe.log"
case "\$*" in
  i2c-dev)
    mkdir -p "$root/sys/class/i2c-dev"; : >"$root/dev/i2c-5"
    if [ -e "$tmp/i2c-rule" ]; then chmod 0600 "$root/dev/i2c-5"; else chmod 0000 "$root/dev/i2c-5"; fi ;;
  "-r i2c-dev") rm -rf "$root/sys/class/i2c-dev" "$root/dev/i2c-5" ;;
  *) exit 64 ;;
esac
EOF
# tailscale: the operator lives in $tmp/operator; get fails while
# $tmp/tailscaled-down exists.
cat >"$bin/tailscale" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/tailscale.log"
[ -e "$tmp/tailscaled-down" ] && { echo 'failed to connect to local tailscaled' >&2; exit 1; }
case "\$1" in
  get) [ "\$2" = operator ] || exit 64; cat "$tmp/operator" ;;
  set) case "\$2" in --operator=*) printf '%s' "\${2#--operator=}" >"$tmp/operator" ;; *) exit 64 ;; esac ;;
  *) exit 64 ;;
esac
EOF
# gum confirm records its arguments, runs $tmp/gum-hook when present and
# answers with $tmp/gum-answer.
cat >"$bin/gum" <<EOF
#!/bin/sh
[ "\$1" = confirm ] || exit 0
printf '%s\n' "\$@" >"$tmp/gum.log"
[ -x "$tmp/gum-hook" ] && "$tmp/gum-hook"
read -r st <"$tmp/gum-answer"
exit "\$st"
EOF
chmod +x "$bin"/stat "$bin"/sudo "$bin"/udevadm "$bin"/systemctl "$bin"/modprobe "$bin"/tailscale "$bin"/gum "$bin"/getent "$bin"/greetd "$bin"/start-hyprland
chmod +x "$bin/getcap" "$bin/setcap"

# SOURCE's `prefix=` line, which must occur once, names the tree.
place() { # SOURCE
  check "the helper's prefix line occurs once" test "$(grep -c '^prefix=$' "$1")" == 1
  sed "s|^prefix=\$|prefix=$root|" "$1" >"$helper"
  chmod +x "$helper"
  check "the placed helper names the tree" test "$(grep -c "^prefix=$root\$" "$helper")" == 1
}
boot_a=11111111-2222-3333-4444-555555555555
boot_b=99999999-8888-7777-6666-555555555555
# A tree with one Apple display whose hidraw node is closed to the user,
# one other HID device, one display-class i2c adapter beside one that is
# not, no i2c-dev module, bluetooth installed and stopped, no tailscaled,
# no operator, greetd installed and disabled with no display manager
# enabled, and every record cleared.
fresh() {
  rm -rf -- "${root:?}/etc" "${root:?}/sys" "${root:?}/dev" "${root:?}/var" "${root:?}/proc" "${root:?}/run" "$tmp/units"
  mkdir -p "$root/etc/udev/rules.d" "$root/etc/greetd" "$root/etc/pam.d" "$root/etc/systemd/system" "$root/dev" "$root/var/lib" "$root/proc/sys/kernel/random" "$tmp/units"
  chmod 0755 "$root/etc" "$root/etc/udev" "$root/etc/udev/rules.d" "$root/etc/greetd" "$root/etc/pam.d" "$root/etc/systemd" "$root/etc/systemd/system" "$root/var" "$root/var/lib"
  mkdir -p "$root/sys/class/hidraw/hidraw0/device" "$root/sys/class/hidraw/hidraw1/device"
  printf 'DRIVER=hid-generic\nHID_ID=0003:000005AC:00009243\nHID_NAME=Apple Inc. Pro Display XDR\n' >"$root/sys/class/hidraw/hidraw0/device/uevent"
  printf 'HID_ID=0003:0000046D:0000C52B\n' >"$root/sys/class/hidraw/hidraw1/device/uevent"
  : >"$hidraw"; : >"$root/dev/hidraw1"; chmod 0000 "$hidraw"; chmod 0600 "$root/dev/hidraw1"
  local gpu="$root/sys/devices/pci0000:00/0000:00:01.0"
  mkdir -p "$gpu/drm/card1/card1-DP-1/i2c-5" "$root/sys/devices/platform/i2c-0" "$root/sys/bus/i2c/devices"
  printf '0x030000\n' >"$gpu/class"
  ln -s ../../../devices/pci0000:00/0000:00:01.0/drm/card1/card1-DP-1/i2c-5 "$root/sys/bus/i2c/devices/i2c-5"
  ln -s ../../../devices/platform/i2c-0 "$root/sys/bus/i2c/devices/i2c-0"
  printf '%s\n' "$boot_a" >"$root/proc/sys/kernel/random/boot_id"
  touch "$tmp/units/tailscaled.service.missing"
  : >"$tmp/operator"
  rm -f -- "$tmp"/{sudo.log,udevadm.log,systemctl.log,modprobe.log,tailscale.log,gum.log,gum-hook,foreign,sudo-exit,udev-fail,other-rule,i2c-rule,tailscaled-down,before-tree,after-tree,no-greeter,getent-fail,owners,greeter-name}
  printf '0\n' >"$tmp/gum-answer"
  rm -f -- "$bin/bandwhich" "$tmp/capture-caps" "$tmp/wrapper-caps" "$tmp/capture-probes" "$tmp/getcap-fail" "$tmp/setcap-fail" "$tmp/setcap.log"
}
capture_fixture() { printf '#!/bin/sh\nexit 64\n' >"$bin/bandwhich"; chmod 0755 "$bin/bandwhich"; }
# NixOS activation publishes its generated wrapper directory through bin.
capture_wrapper="$root/run/wrappers/wrappers.fixture/bandwhich"
capture_wrapper_fixture() {
  mkdir -p -- "${capture_wrapper%/*}"
  chmod 0755 "$root/run" "$root/run/wrappers" "${capture_wrapper%/*}"
  ln -s -- wrappers.fixture "$root/run/wrappers/bin"
  printf '#!/bin/sh\nexit 64\n' >"$capture_wrapper"
  chmod 0755 "$capture_wrapper"
}
caller="$tmp/caller"; mkdir -p "$caller"
ln -s -- "$node_bin" "$caller/node"
nixos_path="$tmp/nixos-path"; mkdir -p "$nixos_path"
printf '#!/bin/sh\nexit 0\n' >"$nixos_path/nix"; chmod +x "$nixos_path/nix"
no_node_path="$tmp/no-node-path"; mkdir -p "$no_node_path"
for tool in bash readlink dirname id; do
  tool_bin="$(command -v "$tool")" || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$no_node_path/$tool"
done
nixos_os_release="$tmp/os-release-nixos"
printf 'NAME=NixOS\nID=nixos\n' >"$nixos_os_release"
nixos_mount_script="$mount_bin --bind \"\$1\" /etc/os-release && shift && exec $unshare_bin --user --map-user=$uid --map-group=$gid \"\$@\""
nixos_probe=0
"$unshare_bin" -rm "$sh_bin" -c "$nixos_mount_script" sh "$nixos_os_release" "$sh_bin" -c "[ \"\$(id -u)\" = \"$uid\" ] && grep -qx ID=nixos /etc/os-release" 2>/dev/null || nixos_probe=$?
((nixos_probe == 0)) || { echo "$suite: status=not-measured missing=nixos-os-release-namespace"; exit 77; }
row_env=(env -i HOME="$tmp/home" PATH="$caller:/usr/bin:/bin" LANG=C.UTF-8)
verdict() { # NAME WANT_EXIT WANT_FIRST_STDERR STATUS
  local err=""
  [[ -s $tmp/err ]] && IFS= read -r err <"$tmp/err"
  if [[ $4 == "$2" && ($3 == "*" || $err == "$3") ]]; then ok "$1"; else fail "$1: exit=$4 want=$2 stderr=[$err] want=[$3]"; fi
}
# run NAME WANT_EXIT WANT_FIRST_STDERR ARGS...: vgshell system ARGS in a
# session with no terminal; `*` takes any stderr. Stdout lands in $tmp/out.
run() {
  local name="$1" want_exit="$2" want_err="$3" status=0
  shift 3
  "${row_env[@]}" "$setsid_bin" -w "$vgs/bin/vgshell" system "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  verdict "$name" "$want_exit" "$want_err" "$status"
}
# run_tty NAME WANT_EXIT ARGS...: the same on a pseudo-terminal; stdout and
# stderr together land in $tmp/out, carriage returns dropped.
tty_env=()
run_tty() {
  local name="$1" want_exit="$2" status=0
  shift 2
  "${row_env[@]}" SHELL="$BASH" "${tty_env[@]}" "$script_bin" -qec "$(printf '%q ' "$vgs/bin/vgshell" system "$@")" /dev/null </dev/null >"$tmp/raw" 2>&1 || status=$?
  tr -d '\r' <"$tmp/raw" >"$tmp/out"
  if [[ $status == "$want_exit" ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit output=[$(cat "$tmp/out")]"; fi
}
tree_snapshot() { find "$root" "$tmp/units" -printf '%P %y %s %m %T@\n' | sort; }
# run_nixos NAME WANT_EXIT WANT_FIRST_STDERR PATH ARGS...: vgshell system with
# NixOS's os-release bound, the tree snapshotted around it.
run_nixos() {
  local name="$1" want_exit="$2" want_err="$3" path_value="$4" status=0
  shift 4
  tree_snapshot >"$tmp/before-tree"
  env -i HOME="$tmp/home" PATH="$path_value" LANG=C.UTF-8 \
    "$unshare_bin" -rm "$sh_bin" -c "$nixos_mount_script" sh "$nixos_os_release" "$setsid_bin" -w "$vgs/bin/vgshell" system "$@" \
    </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  tree_snapshot >"$tmp/after-tree"
  verdict "$name" "$want_exit" "$want_err" "$status"
}
untouched() { cmp -s -- "$tmp/before-tree" "$tmp/after-tree"; }
out_has() { grep -qF -- "$1" "$tmp/out"; }
out_is() { test "$(cat "$tmp/out")" == "$1"; }
last_out_is() { test "$(tail -n 1 "$tmp/out")" == "$1"; }
sudo_calls() { cat -- "$tmp/sudo.log" 2>/dev/null; }
no_sudo() { test ! -e "$tmp/sudo.log"; }
state_json() { # STATE-REASON per step, table order
  printf '{"steps":{"apple-displays":{"state":"%s","reason":"%s"},"i2c-dev":{"state":"%s","reason":"%s"},"service-bluetooth":{"state":"%s","reason":"%s"},"service-tailscaled":{"state":"%s","reason":"%s"},"tailscale-operator":{"state":"%s","reason":"%s"},"greeter":{"state":"%s","reason":"%s"},"bandwhich-capture":{"state":"absent","reason":"bandwhich-missing"}}}' "$@"
}
step_state() { # STEP: the state status --json reads for it
  "${row_env[@]}" "$vgs/bin/vgshell" system status --json </dev/null 2>/dev/null |
    python3 -c 'import json,sys; s=json.load(sys.stdin)["steps"][sys.argv[1]]; print(s["state"] + " " + s["reason"])' "$1"
}
# The sudo calls one session makes: the cold start, the password check,
# each COMMAND as one line, and the credential dropped at the end.
session() { printf '%s\n' -k /usr/bin/true "$@" -k; }
p() { printf '%s' "$bin/$1"; }
place "$source_file"

# vgshell's own refusal of a subcommand it does not route.
fresh
run "vgshell system with no subcommand is refused" 2 "vgshell: refused: system-subcommand=missing"
run "an unknown system subcommand is refused" 2 "vgshell: refused: system-subcommand=grant" grant

# Arguments, refused before any probe or sudo.
run "apply with no step is refused" 2 "vgs-system: refused: count=0 verb=apply" apply
run "apply takes one step" 2 "vgs-system: refused: count=2 verb=apply" apply apple-displays i2c-dev
run "an unknown step is refused" 2 "vgs-system: refused: step=etc-shadow" apply etc-shadow
run "undo refuses an unknown step" 2 "vgs-system: refused: step=apple" undo apple
run "a step name with a path is refused" 2 "vgs-system: refused: step=../apple-displays" apply ../apple-displays
run "status takes only --json" 2 "vgs-system: refused: argument=x" status x
check "a refused invocation runs no sudo" no_sudo
check "a refused invocation asks nothing" test ! -e "$tmp/gum.log"

# status: each probe reads real access, in table order.
run "status reads every step" 0 "" status --json
check "status names each step's state and reason" out_is "$(state_json needed hidraw-denied needed module-not-loaded needed inactive absent unit-missing needed operator-unset needed not-set-up)"
# The manifest judge names steps from PluginLogic.SYSTEM_STEPS; the
# script's own table must be that list, in that order.
table_keys() { python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["steps"]))' "$tmp/out"; }
judge_steps() { "$node_bin" -e 'const { load } = require(process.argv[1]); process.stdout.write(load(process.argv[2]).SYSTEM_STEPS.join(" "))' "$repo/bin/lib/qml-library.js" "$repo/shell/Core/PluginLogic.js"; }
check "the script's step table is the manifest judge's" test "$(table_keys)" == "$(judge_steps)"
run "status prints one line per step" 0 "" status
check "the line form names the Apple step first" test "$(head -n 1 "$tmp/out")" == "system=apple-displays state=needed reason=hidraw-denied"
check "status runs no sudo" no_sudo
chmod 0600 "$hidraw"; : >"$tmp/other-rule"; printf 'other rule\n' >"$root/etc/udev/rules.d/60-other-apple-displays.rules"
check "an Apple node another rule opened reads ready" test "$(step_state apple-displays)" == "ready granted"
rm -f -- "$hidraw"
check "an Apple display with no node reads unknown" test "$(step_state apple-displays)" == "unknown node-missing"
rm -rf -- "$root/sys/class/hidraw/hidraw0"
check "no Apple display reads absent" test "$(step_state apple-displays)" == "absent no-device"
fresh; chmod 0000 "$root/sys/class/hidraw/hidraw0/device/uevent"
check "an unreadable HID device reads unknown, never ready" test "$(step_state apple-displays)" == "unknown sysfs-unreadable"
fresh; mkdir -p "$root/sys/class/i2c-dev"; : >"$root/dev/i2c-5"; chmod 0000 "$root/dev/i2c-5"
check "a loaded module with a closed display node reads denied" test "$(step_state i2c-dev)" == "denied no-uaccess-rule"
chmod 0600 "$root/dev/i2c-5"
check "an open display node reads ready" test "$(step_state i2c-dev)" == "ready granted"
rm -f -- "$root/sys/bus/i2c/devices/i2c-5"
check "no display-class adapter reads absent" test "$(step_state i2c-dev)" == "absent no-adapter"
fresh; touch "$tmp/units/bluetooth.service.masked"
check "a masked unit reads denied" test "$(step_state service-bluetooth)" == "denied unit-masked"
touch "$tmp/units/bluetooth.service.active"
check "an active unit reads ready" test "$(step_state service-bluetooth)" == "ready active"
fresh; printf 'someone' >"$tmp/operator"
check "another user's operator reads denied" test "$(step_state tailscale-operator)" == "denied operator-other"
printf '%s' "$user" >"$tmp/operator"
check "the caller as operator reads ready" test "$(step_state tailscale-operator)" == "ready granted"
touch "$tmp/tailscaled-down"
check "an unreachable tailscaled reads unknown" test "$(step_state tailscale-operator)" == "unknown tailscaled-unreachable"
# A login name the operator cannot take reads that step unknown, the rest
# as before; id answers -un with it while $tmp/odd-user exists.
id_real="$(readlink -- "$bin/id")"
rm -f -- "${bin:?}/id"
printf '#!/bin/sh\nif [ -e %q ] && [ "$1" = -un ]; then echo john.doe; exit 0; fi\nexec %q "$@"\n' "$tmp/odd-user" "$id_real" >"$bin/id"
chmod +x "$bin/id"
fresh; touch "$tmp/odd-user"
run "status with an unsupported login name" 0 "" status --json
check "an unsupported login name reads only the operator unknown" out_is "$(state_json needed hidraw-denied needed module-not-loaded needed inactive absent unit-missing unknown user-unsupported needed not-set-up)"
run "apply refuses the operator for an unsupported login name" 1 "vgs-system: refused: state=unknown reason=user-unsupported step=tailscale-operator" apply tailscale-operator
check "the refused operator runs no sudo" no_sudo
rm -f -- "${tmp:?}/odd-user"

# apply asks before anything: with no terminal, declined or cancelled,
# nothing is written and no sudo runs.
fresh; tree_snapshot >"$tmp/before-tree"
run "apply with no terminal is refused at the question" 2 "*" apply apple-displays
check "the no-terminal refusal is the library's" grep -qxF -- "vgs-tui: refused: confirm=no-terminal" "$tmp/err"
tree_snapshot >"$tmp/after-tree"
check "apply with no answer writes nothing" untouched
check "apply with no answer runs no sudo" no_sudo
fresh; printf '1\n' >"$tmp/gum-answer"; tree_snapshot >"$tmp/before-tree"
run_tty "a declined apply is refused" 1 apply apple-displays
check "a declined apply names the decline" out_has "vgs-system: refused: declined=apply step=apple-displays"
tree_snapshot >"$tmp/after-tree"
check "a declined apply writes nothing" untouched
check "a declined apply runs no sudo" no_sudo
fresh; printf '130\n' >"$tmp/gum-answer"; tree_snapshot >"$tmp/before-tree"
run_tty "a cancelled apply exits 130" 130 apply apple-displays
tree_snapshot >"$tmp/after-tree"
check "a cancelled apply writes nothing" untouched
check "a cancelled apply runs no sudo" no_sudo
fresh; tty_env=(VGS_TUI_UNATTENDED=1); printf '1\n' >"$tmp/gum-answer"
run_tty "an unattended apply is still asked" 1 apply apple-displays
check "the unattended apply asked gum" test -e "$tmp/gum.log"
check "the unattended decline runs no sudo" no_sudo
tty_env=()

# apple-displays: the rule's bytes, the record's bytes and each root command.
fresh
run_tty "apply apple-displays succeeds" 0 apply apple-displays
hash="$(sha256sum <"$rule_src")"; hash="${hash%% *}"
check "apply shows the rule's install before asking" out_has "  sudo $(p install) -m 0644 -o root -g root -T -- $rule_src $rule"
check "apply asks one question" test "$(cat "$tmp/gum.log")" == "$(printf '%s\n' confirm -- "Run these commands as root?")"
check "apple-displays runs its commands in one sudo session" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.apple-displays" \
  "-- $(p mv) -fT -- $records/.apple-displays $records/apple-displays" \
  "-- $(p install) -m 0644 -o root -g root -T -- $rule_src $rule" \
  "-- $(p udevadm) control --reload" \
  "-- $(p udevadm) trigger --subsystem-match=hidraw --action=change --settle")"
check "the installed rule is the shipped file byte for byte" cmp -s -- "$rule_src" "$rule"
check "the rule is mode 0644" test "$("$stat_bin" -c %a -- "$rule")" == 644
check "the record names the caller and the rule's hash" test "$(cat "$records/apple-displays")" == "$(printf 'uid=%s\nrule=%s' "$uid" "$hash")"
check "no staged record is left" test "$(ls -A -- "$records")" == apple-displays
check "apply reports the step ready" last_out_is "ok system=apple-displays state=ready"
check "status reads the Apple step ready" test "$(step_state apple-displays)" == "ready granted"
rm -f -- "$tmp/sudo.log"
run "apply on a ready step runs nothing" 0 "" apply apple-displays
check "a ready apply says so" out_is "ok system=apple-displays state=ready"
check "a ready apply runs no sudo" no_sudo
# The shipped rule: the two hidraw lines, uaccess only.
check "the shipped rule holds only the two hidraw lines" test "$(grep -v '^#' "$repo/config/system/udev/60-vgs-apple-displays.rules" | grep -v '^$')" == 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="1114", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="9243", TAG+="uaccess"'

# undo of the VGS rule removes it and its record, and reloads udev.
rm -f -- "$tmp/sudo.log"
run_tty "undo apple-displays succeeds" 0 undo apple-displays
check "undo removes the rule, reloads, then drops the record" test "$(sudo_calls)" == "$(session \
  "-- $(p rm) -f -- $rule" \
  "-- $(p udevadm) control --reload" \
  "-- $(p udevadm) trigger --subsystem-match=hidraw --action=change --settle" \
  "-- $(p rm) -f -- $records/apple-displays")"
check "undo leaves no rule and no record" test ! -e "$rule" -a ! -e "$records/apple-displays"
check "undo reports it" last_out_is "ok system=apple-displays state=undone"
rm -f -- "$tmp/sudo.log"
run "undo with no record changes nothing" 0 "" undo apple-displays
check "an untouched undo says so" out_is "ok system=apple-displays state=untouched"
check "an untouched undo runs no sudo" no_sudo

# A rule file VGS did not write is refused before the question, never overwritten.
fresh; printf 'someone else\n' >"$rule"
run "apply refuses a foreign rule file" 1 "vgs-system: refused: destination=foreign path=$rule" apply apple-displays
check "the foreign rule keeps its bytes" test "$(cat "$rule")" == "someone else"
check "a foreign rule asks nothing" test ! -e "$tmp/gum.log"
check "a foreign rule runs no sudo" no_sudo
fresh; ln -s /dev/null "$rule"
run "apply refuses a symbolic link at the destination" 1 "vgs-system: refused: destination=symlink path=$rule" apply apple-displays
check "a symlinked destination runs no sudo" no_sudo
fresh; chmod 0777 "$root/etc/udev/rules.d"
run "apply refuses a rules directory others can write" 1 "vgs-system: refused: untrusted=$root/etc/udev/rules.d" apply apple-displays
# A rule edited after VGS wrote it is foreign to undo, and the record stays.
fresh
run_tty "apply before an edit" 0 apply apple-displays
printf '# edited\n' >>"$rule"
run "undo refuses an edited rule" 1 "vgs-system: refused: destination=foreign path=$rule" undo apple-displays
check "the edited rule stays" grep -qxF '# edited' "$rule"
check "the record stays for the edited rule" test -e "$records/apple-displays"
# A command that fails after the record leaves the record, so undo still
# owns what was written.
fresh; touch "$tmp/udev-fail"
run_tty "a failing udevadm fails apply" 1 apply apple-displays
check "the failure names the command" out_has "vgs-system: refused: command=failed exit=1 argv="
check "the rule written before the failure is on record" test -e "$rule" -a -e "$records/apple-displays"
rm -f -- "$tmp/udev-fail"
run_tty "undo after a failed apply removes the rule" 0 undo apple-displays
check "the failed apply's rule is gone" test ! -e "$rule"
# A plan that changes while the question waits is not run.
fresh; printf '#!/bin/sh\ntouch %q\n' "$tmp/units/bluetooth.service.enabled" >"$tmp/gum-hook"; chmod +x "$tmp/gum-hook"
run_tty "a plan that changed under the question is refused" 1 apply service-bluetooth
check "the refusal names the changed plan" out_has "vgs-system: refused: plan=changed step=service-bluetooth"
check "a changed plan runs no command of the step" test "$(grep -c 'systemctl\|tee' "$tmp/sudo.log")" == 0

# i2c-dev: a record, then modprobe; undo unloads only in the boot that loaded it.
fresh; touch "$tmp/i2c-rule"
run_tty "apply i2c-dev succeeds" 0 apply i2c-dev
check "i2c-dev records, then loads the module" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.i2c-dev" \
  "-- $(p mv) -fT -- $records/.i2c-dev $records/i2c-dev" \
  "-- $(p modprobe) i2c-dev" \
  "-- $(p udevadm) settle")"
check "the i2c-dev record names the boot" test "$(cat "$records/i2c-dev")" == "$(printf 'uid=%s\nloaded=1\nboot=%s' "$uid" "$boot_a")"
check "i2c-dev reports ready" last_out_is "ok system=i2c-dev state=ready"
rm -f -- "$tmp/sudo.log"
run_tty "undo i2c-dev in the same boot" 0 undo i2c-dev
check "undo unloads the module in the boot that loaded it" grep -qxF -- "-- $(p modprobe) -r i2c-dev" "$tmp/sudo.log"
fresh; touch "$tmp/i2c-rule"
run_tty "apply i2c-dev before a reboot" 0 apply i2c-dev
printf '%s\n' "$boot_b" >"$root/proc/sys/kernel/random/boot_id"; rm -f -- "$tmp/sudo.log"
run_tty "undo i2c-dev after a reboot" 0 undo i2c-dev
check "after a reboot undo leaves the module the system loaded" test "$(sudo_calls)" == "$(session "-- $(p rm) -f -- $records/i2c-dev")"
fresh
run_tty "i2c-dev without the package's rule loads the module but fails" 1 apply i2c-dev
check "the refusal names the denied access" out_has "vgs-system: refused: state=denied reason=no-uaccess-rule step=i2c-dev"

# Services: enable --now; undo disables only a unit VGS enabled and stops
# only a unit VGS started in this boot.
fresh
run_tty "apply service-bluetooth succeeds" 0 apply service-bluetooth
check "service-bluetooth records, then enables the unit now" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.service-bluetooth" \
  "-- $(p mv) -fT -- $records/.service-bluetooth $records/service-bluetooth" \
  "-- $(p systemctl) enable --now bluetooth.service")"
check "the service record names what VGS changed" test "$(cat "$records/service-bluetooth")" == "$(printf 'uid=%s\nenabled=1\nstarted=1\nboot=%s' "$uid" "$boot_a")"
rm -f -- "$tmp/sudo.log"
run_tty "undo service-bluetooth" 0 undo service-bluetooth
check "undo disables and stops the unit VGS enabled" test "$(sudo_calls)" == "$(session \
  "-- $(p systemctl) disable bluetooth.service" \
  "-- $(p systemctl) stop bluetooth.service" \
  "-- $(p rm) -f -- $records/service-bluetooth")"
fresh; touch "$tmp/units/bluetooth.service.enabled"
run_tty "apply a service that was enabled but stopped" 0 apply service-bluetooth
check "the record of an enabled unit claims only the start" test "$(cat "$records/service-bluetooth")" == "$(printf 'uid=%s\nstarted=1\nboot=%s' "$uid" "$boot_a")"
rm -f -- "$tmp/sudo.log"
run_tty "undo a service VGS only started" 0 undo service-bluetooth
check "undo never disables a unit VGS did not enable" test "$(sudo_calls)" == "$(session \
  "-- $(p systemctl) stop bluetooth.service" \
  "-- $(p rm) -f -- $records/service-bluetooth")"
check "the unit stays enabled" test -e "$tmp/units/bluetooth.service.enabled"
fresh
run_tty "apply a service VGS will enable" 0 apply service-bluetooth
rm -f -- "${tmp:?}/units/bluetooth.service.active"
run_tty "apply the same service again once it stopped" 0 apply service-bluetooth
check "a second apply keeps that VGS enabled the unit" test "$(cat "$records/service-bluetooth")" == "$(printf 'uid=%s\nenabled=1\nstarted=1\nboot=%s' "$uid" "$boot_a")"
rm -f -- "${tmp:?}/sudo.log"
run_tty "undo after the second apply" 0 undo service-bluetooth
check "undo still disables the unit VGS enabled first" grep -qxF -- "-- $(p systemctl) disable bluetooth.service" "$tmp/sudo.log"
fresh
run_tty "apply before another uid's record" 0 apply service-bluetooth
sed -i "s/^uid=$uid\$/uid=4242/" "$records/service-bluetooth"; rm -f -- "${tmp:?}/units/bluetooth.service.active" "${tmp:?}/sudo.log"
run "apply refuses over another uid's record" 1 "vgs-system: refused: record=other-uid uid=4242 path=$records/service-bluetooth" apply service-bluetooth
check "the other uid's record stays" grep -qx "uid=4242" "$records/service-bluetooth"
check "a refused record asks nothing and runs no sudo" no_sudo
fresh; touch "$tmp/units/bluetooth.service.enabled"
run_tty "apply before a reboot" 0 apply service-bluetooth
printf '%s\n' "$boot_b" >"$root/proc/sys/kernel/random/boot_id"; rm -f -- "$tmp/sudo.log"
run_tty "undo after a reboot" 0 undo service-bluetooth
check "after a reboot undo stops nothing it did not start" test "$(sudo_calls)" == "$(session "-- $(p rm) -f -- $records/service-bluetooth")"
fresh
run "apply refuses a unit that is not installed" 1 "vgs-system: refused: state=absent reason=unit-missing step=service-tailscaled" apply service-tailscaled
touch "$tmp/units/bluetooth.service.masked"
run "apply refuses a masked unit" 1 "vgs-system: refused: state=denied reason=unit-masked step=service-bluetooth" apply service-bluetooth
check "a refused step runs no sudo" no_sudo
fresh; rm -f -- "$tmp/units/tailscaled.service.missing"
run_tty "apply service-tailscaled succeeds" 0 apply service-tailscaled
check "service-tailscaled enables its unit now" grep -qxF -- "-- $(p systemctl) enable --now tailscaled.service" "$tmp/sudo.log"

# The operator: the caller's own login name; undo resets it only while it
# still names the caller.
fresh
run_tty "apply tailscale-operator succeeds" 0 apply tailscale-operator
check "tailscale-operator records, then sets the caller" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.tailscale-operator" \
  "-- $(p mv) -fT -- $records/.tailscale-operator $records/tailscale-operator" \
  "-- $(p tailscale) set --operator=$user")"
check "the operator record names the caller and the empty previous operator" test "$(cat "$records/tailscale-operator")" == "$(printf 'uid=%s\noperator=%s\nprevious=' "$uid" "$user")"
check "the operator is the caller" test "$(cat "$tmp/operator")" == "$user"
rm -f -- "$tmp/sudo.log"
run_tty "undo tailscale-operator" 0 undo tailscale-operator
check "undo resets the operator VGS set" grep -qxF -- "-- $(p tailscale) set --operator=" "$tmp/sudo.log"
check "the operator is unset again" test ! -s "$tmp/operator"
fresh
run_tty "apply the operator before another change" 0 apply tailscale-operator
printf 'someone' >"$tmp/operator"; rm -f -- "$tmp/sudo.log"
run_tty "undo after someone else set the operator" 0 undo tailscale-operator
check "undo never resets an operator it did not set" test "$(sudo_calls)" == "$(session "-- $(p rm) -f -- $records/tailscale-operator")"
check "the other operator stays" test "$(cat "$tmp/operator")" == someone
fresh; printf 'someone' >"$tmp/operator"
run "apply refuses another user's operator" 1 "vgs-system: refused: state=denied reason=operator-other step=tailscale-operator" apply tailscale-operator

# bandwhich capture: the real helper probes the resolved binary, requires
# every grant, records before setcap and uses only the isolated stand-ins.
capture_want=cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep
capture_all=cap_dac_read_search,cap_net_admin,cap_net_raw,cap_sys_ptrace=ep
fresh
check "capture without bandwhich reads absent" test "$(step_state bandwhich-capture)" == "absent bandwhich-missing"
run "capture refuses apply without bandwhich" 1 "vgs-system: refused: state=absent reason=bandwhich-missing step=bandwhich-capture" apply bandwhich-capture
capture_fixture
check "capture with no capabilities reads needed" test "$(step_state bandwhich-capture)" == "needed capture-needed"
for caps in \
  cap_dac_read_search,cap_net_admin,cap_net_raw=ep \
  cap_sys_ptrace,cap_net_admin,cap_net_raw=ep \
  cap_sys_ptrace,cap_dac_read_search,cap_net_raw=ep \
  cap_sys_ptrace,cap_dac_read_search,cap_net_admin=ep \
  cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=p \
  cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=e \
  '=ep cap_net_admin-p' \
  '=ep cap_net_admin=' \
  'cap_dac_read_search,cap_net_admin,cap_net_raw,cap_sys_ptrace=ep [rootid=1000]'; do
  printf '%s\n' "$caps" >"$tmp/capture-caps"
  check "capture rejects incomplete or namespaced grants [$caps]" test "$(step_state bandwhich-capture)" == "needed capture-needed"
done
printf '%s\n' "$capture_all" >"$tmp/capture-caps"
check "capture with every effective and permitted grant reads ready" test "$(step_state bandwhich-capture)" == "ready granted"
for caps in '=ep' 'all=ep' 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=p+e-i'; do
  printf '%s\n' "$caps" >"$tmp/capture-caps"
  check "capture reads all granted capability text forms [$caps]" test "$(step_state bandwhich-capture)" == "ready granted"
done
run "capture already granted runs nothing" 0 "" apply bandwhich-capture
check "a ready capture apply runs no sudo" no_sudo
printf 'cap_net_raw=ep cap_sys_ptrace,cap_dac_read_search,cap_net_admin=ep\n' >"$tmp/capture-caps"
check "capture reads capabilities in multiple groups" test "$(step_state bandwhich-capture)" == "ready granted"
printf '%s %s\n' "$uid" "$bin/bandwhich" >"$tmp/owners"
check "a bandwhich binary not owned by root reads denied" test "$(step_state bandwhich-capture)" == "denied install-untrusted"
run "capture refuses an untrusted binary" 1 "vgs-system: refused: state=denied reason=install-untrusted step=bandwhich-capture" apply bandwhich-capture
check "an untrusted capture apply runs no sudo" no_sudo
rm -f -- "$tmp/owners"
for mode in 0775 0777; do
  chmod "$mode" "$bin/bandwhich"
  check "a writable bandwhich binary reads denied [$mode]" test "$(step_state bandwhich-capture)" == "denied install-untrusted"
done
chmod 0755 "$bin/bandwhich"; chmod 0775 "$bin"
check "a writable parent of bandwhich reads denied" test "$(step_state bandwhich-capture)" == "denied install-untrusted"
chmod 0755 "$bin"
touch "$tmp/getcap-fail"
check "a failed getcap reads unknown" test "$(step_state bandwhich-capture)" == "unknown getcap-failed"
rm -f -- "$tmp/getcap-fail"
printf 'unrecognized\n' >"$tmp/capture-caps"
check "an unreadable capability report reads unknown" test "$(step_state bandwhich-capture)" == "unknown capabilities-unreadable"
fresh; capture_fixture
tree_snapshot >"$tmp/before-tree"
run "capture with no terminal stops at its question" 2 "*" apply bandwhich-capture
tree_snapshot >"$tmp/after-tree"
check "capture before consent writes nothing" untouched
check "capture before consent runs no sudo" no_sudo
run_tty "capture apply grants the resolved binary" 0 apply bandwhich-capture
check "capture apply shows the capability command before asking" out_has "  sudo $(p setcap) $(printf '%q' "$capture_want") $bin/bandwhich"
check "capture records before the stand-in grants capabilities" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.bandwhich-capture" \
  "-- $(p mv) -fT -- $records/.bandwhich-capture $records/bandwhich-capture" \
  "-- $(p setcap) $capture_want $bin/bandwhich")"
check "capture reports ready after its command" last_out_is "ok system=bandwhich-capture state=ready"
check "capture records the caller and binary identity" test "$(cat "$records/bandwhich-capture")" == "$(printf 'uid=%s\nbinary=%s\nhash=%s' "$uid" "$bin/bandwhich" "$(sha256sum "$bin/bandwhich" | cut -d ' ' -f1)")"
rm -f -- "$tmp/sudo.log"
run_tty "capture undo removes its grant" 0 undo bandwhich-capture
check "capture undo runs setcap -r then drops the record" test "$(sudo_calls)" == "$(session \
  "-- $(p setcap) -r $bin/bandwhich" \
  "-- $(p rm) -f -- $records/bandwhich-capture")"
check "capture after undo needs its grant" test "$(step_state bandwhich-capture)" == "needed capture-needed"
fresh; capture_fixture; touch "$tmp/setcap-fail"
run_tty "a failed capture grant fails apply" 1 apply bandwhich-capture
check "a failed capture grant leaves its record" test -e "$records/bandwhich-capture"
check "a failed capture grant remains needed" test "$(step_state bandwhich-capture)" == "needed capture-needed"
fresh; capture_fixture
run_tty "capture apply before a package replacement" 0 apply bandwhich-capture
printf '# replacement\n' >>"$bin/bandwhich"; : >"$tmp/capture-caps"; rm -f -- "$tmp/sudo.log"
check "a package replacement drops capture readiness" test "$(step_state bandwhich-capture)" == "needed capture-needed"
run "undo preserves a replacement binary" 1 "vgs-system: refused: record=binary-changed step=bandwhich-capture" undo bandwhich-capture
check "a replacement undo runs no sudo" no_sudo
run_tty "capture applies to the package replacement" 0 apply bandwhich-capture
check "the replacement capture grant reads ready" test "$(step_state bandwhich-capture)" == "ready granted"
capture_nixos_contract() { out_has "\"bandwhich-capture\":{\"state\":\"$1\",\"reason\":\"$2\"}"; }
fresh
run_nixos "capture on NixOS without the package" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
check "NixOS without bandwhich reads absent" capture_nixos_contract absent bandwhich-missing
capture_fixture
run_nixos "capture on NixOS without a wrapper" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
check "NixOS with the package but no configured wrapper needs configuration" capture_nixos_contract nixos capture-needed
run_nixos "capture apply on NixOS prints a wrapper" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply bandwhich-capture
check "the NixOS wrapper grants every capability" out_has "  capabilities = \"$capture_want\";"
check "the NixOS wrapper uses the package binary" out_has '  source = "${pkgs.bandwhich}/bin/bandwhich";'
check "capture on NixOS writes nothing" untouched
check "capture on NixOS runs no sudo" no_sudo
check "capture on NixOS asks nothing" test ! -e "$tmp/gum.log"
capture_wrapper_fixture
# The wrapper's extra cap_setpcap is part of NixOS's actual grant.
capture_wrapper_all="cap_setpcap,${capture_all}"
printf '%s\n' "$capture_wrapper_all" >"$tmp/wrapper-caps"
run_nixos "capture on NixOS with the configured wrapper" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
check "the configured wrapper reads ready" capture_nixos_contract ready granted
check "the probe reads the resolved configured wrapper" test "$(tail -n 1 "$tmp/capture-probes")" == "$capture_wrapper"
run_nixos "the configured NixOS capture apply runs nothing" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply bandwhich-capture
check "the configured NixOS capture apply reads ready" out_is 'ok system=bandwhich-capture state=ready'
check "the configured NixOS capture apply writes nothing" untouched
check "the configured NixOS capture apply runs no sudo" no_sudo
check "the configured NixOS capture apply asks nothing" test ! -e "$tmp/gum.log"
printf '%s\n' "$capture_all" >"$tmp/capture-caps"
for caps in '' cap_setpcap,cap_dac_read_search,cap_net_admin,cap_net_raw=ep \
  cap_setpcap,cap_sys_ptrace,cap_net_admin,cap_net_raw=ep \
  cap_setpcap,cap_sys_ptrace,cap_dac_read_search,cap_net_raw=ep \
  cap_setpcap,cap_sys_ptrace,cap_dac_read_search,cap_net_admin=ep \
  cap_setpcap,cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=p \
  cap_setpcap,cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=e \
  "$capture_wrapper_all [rootid=1000]"; do
  printf '%s\n' "$caps" >"$tmp/wrapper-caps"
  run_nixos "capture on NixOS with an incomplete wrapper [$caps]" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
  check "the incomplete wrapper needs configuration despite a granted package binary [$caps]" capture_nixos_contract nixos capture-needed
done
printf '%s\n' "$capture_wrapper_all" >"$tmp/wrapper-caps"
printf '%s %s\n' "$uid" "$capture_wrapper" >"$tmp/owners"
run_nixos "capture on NixOS with another account's wrapper" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
check "the wrapper must belong to root" capture_nixos_contract denied install-untrusted
rm -- "$tmp/owners"
for path in "$capture_wrapper" "${capture_wrapper%/*}"; do
  chmod 0775 "$path"
  run_nixos "capture on NixOS with a writable wrapper path [$path]" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
  check "the wrapper and its parents must be trusted [$path]" capture_nixos_contract denied install-untrusted
  chmod 0755 "$path"
done

# greeter: VGS's own greetd configuration, PAM service and drop-in, the
# theme, theme copy and state directories, then greetd enabled and never
# started, and graphical.target the default.
greeter_view="$vgs/shell/plugins/vgs.greeter/Greeter.qml"
greeter_command="/usr/bin/env VGS_GREETER_ROOT=$vgs VGS_GREETER_VIEW=$greeter_view XDG_CONFIG_HOME=/var/lib/vgshell/greeter/theme XDG_STATE_HOME=/var/lib/vgshell/greeter/state XDG_CACHE_HOME=/var/lib/vgshell/greeter/state/cache /usr/bin/start-hyprland -- --config $vgs/config/system/greeter/hyprland.lua"
want_toml_of() { printf '# Written by vgshell system apply greeter; vgshell system undo greeter removes it.\n[terminal]\nvt = %s\n\n[general]\nservice = "vgs-greeter"\n\n[default_session]\nuser = "%s"\ncommand = "%s"' "$1" "$2" "$greeter_command"; } # VT ACCOUNT
want_toml="$(want_toml_of 1 greeter)"
want_dropin="$(printf '# Written by vgshell system apply greeter; vgshell system undo greeter removes it.\n[Service]\nExecStart=\nExecStart=/usr/bin/greetd --config /etc/greetd/vgshell.toml')"
file_hash() { local s; s="$(sha256sum <"$1")"; printf '%s' "${s%% *}"; }
holds_text() { cmp -s -- "$1" <(printf '%s\n' "$2"); } # FILE TEXT: the file is TEXT and one newline
greeter_never_started() { ! grep -qE -- '--now|systemctl start ' "$tmp/sudo.log" && test ! -e "$tmp/units/greetd.service.active"; }
default_target() { cat -- "$tmp/units/default-target" 2>/dev/null || echo graphical.target; }
fresh
check "a greetd VGS did not set up reads needed" test "$(step_state greeter)" == "needed not-set-up"
run_tty "apply greeter succeeds" 0 apply greeter
check "greeter writes its files, makes its directories, reloads and enables greetd in one sudo session" test "$(sudo_calls)" == "$(session \
  "-- $(p install) -d -m 0755 -o root -g root -- $records" \
  "-- $(p tee) -- $records/.greeter" \
  "-- $(p mv) -fT -- $records/.greeter $records/greeter" \
  "-- $(p tee) -- $root/etc/greetd/.vgshell.toml" \
  "-- $(p mv) -fT -- $root/etc/greetd/.vgshell.toml $greeter_toml" \
  "-- $(p install) -m 0644 -o root -g root -T -- $greeter_src/vgs-greeter.pam $greeter_pam" \
  "-- $(p install) -d -m 0755 -o root -g root -- $dropin_dir" \
  "-- $(p tee) -- $dropin_dir/.vgs.conf" \
  "-- $(p mv) -fT -- $dropin_dir/.vgs.conf $greeter_dropin" \
  "-- $(p install) -d -m 0755 -o root -g root -- $greeter_dir" \
  "-- $(p install) -d -m 0755 -o root -g root -- $greeter_dir/theme" \
  "-- $(p install) -d -m 0755 -o $uid -g $gid -- $greeter_dir/theme/vgshell" \
  "-- $(p install) -d -m 0700 -o 958 -g 958 -- $greeter_dir/state" \
  "-- $(p systemctl) daemon-reload" \
  "-- $(p systemctl) enable greetd.service")"
check "apply shows the greetd configuration it writes before asking" out_has "  sudo $(p tee) -- $root/etc/greetd/.vgshell.toml <<<"
check "the greetd configuration names the VGS PAM service, the greeter account and the greeter's command" holds_text "$greeter_toml" "$want_toml"
check "the PAM service is the shipped file byte for byte" cmp -s -- "$greeter_src/vgs-greeter.pam" "$greeter_pam"
check "the drop-in runs greetd with the VGS configuration" holds_text "$greeter_dropin" "$want_dropin"
check "the theme and copy directories are mode 0755 and the state directory 0700" test "$("$stat_bin" -c %a -- "$greeter_dir/theme") $("$stat_bin" -c %a -- "$greeter_dir/theme/vgshell") $("$stat_bin" -c %a -- "$greeter_dir/state")" == "755 755 700"
check "the record names each file's hash, the enable and each directory made" test "$(cat "$records/greeter")" == "$(printf 'uid=%s\nconfig=%s\npam=%s\ndropin=%s\nenabled=1\ndropin-dir=1\ngreeter-dir=1\ntheme-dir=1\ncopy-dir=1\nstate-dir=1' \
  "$uid" "$(file_hash "$greeter_toml")" "$(file_hash "$greeter_pam")" "$(file_hash "$greeter_dropin")")"
check "apply enables greetd and never starts it" greeter_never_started
check "greetd is enabled" test -e "$tmp/units/greetd.service.enabled"
check "a graphical default target stays as it is" test ! -e "$tmp/units/default-target"
check "apply reports the greeter ready" last_out_is "ok system=greeter state=ready"
check "status reads the greeter ready" test "$(step_state greeter)" == "ready granted"
check "the packaged greetd configuration and PAM service are not written" test ! -e "$root/etc/greetd/config.toml" -a ! -e "$root/etc/pam.d/greetd"
rm -f -- "${tmp:?}/sudo.log"
run "apply on a ready greeter runs nothing" 0 "" apply greeter
check "a ready greeter's apply runs no sudo" no_sudo
# The shipped PAM service: the distribution's login stack and the keyring.
check "the shipped PAM service holds the login stack and the keyring" test "$(grep -v '^#' "$repo/config/system/greeter/vgs-greeter.pam" | grep -v '^$')" == "$(printf '%s\n' \
  'auth       include      login' \
  '-auth      optional     pam_gnome_keyring.so' \
  'account    include      login' \
  'password   include      login' \
  'session    include      login' \
  '-session   optional     pam_gnome_keyring.so auto_start')"
# The plugin copies the theme into the directory the step makes.
plugin_theme_dir() { "$node_bin" -e 'const { load } = require(process.argv[1]); process.stdout.write(load(process.argv[2]).THEME_DIR)' "$repo/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.greeter/GreeterLogic.js"; }
check "the plugin's theme directory is the step's" test "$(plugin_theme_dir)" == "/var/lib/vgshell/greeter/theme"

# undo removes what VGS wrote and made, disables greetd it enabled, reloads.
rm -f -- "${tmp:?}/sudo.log"
run_tty "undo greeter succeeds" 0 undo greeter
check "undo removes the files, the directories it made, then disables greetd and reloads" test "$(sudo_calls)" == "$(session \
  "-- $(p rm) -f -- $greeter_toml" \
  "-- $(p rm) -f -- $greeter_pam" \
  "-- $(p rm) -f -- $greeter_dropin" \
  "-- $(p rm) -rf -- $greeter_dir/theme/vgshell" \
  "-- $(p rm) -rf -- $greeter_dir/state" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $greeter_dir/theme" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $greeter_dir" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $dropin_dir" \
  "-- $(p systemctl) disable greetd.service" \
  "-- $(p systemctl) daemon-reload" \
  "-- $(p rm) -f -- $records/greeter")"
check "undo leaves no greeter file, directory or record" test ! -e "$greeter_toml" -a ! -e "$greeter_pam" -a ! -e "$dropin_dir" -a ! -e "$greeter_dir" -a ! -e "$records/greeter"
check "undo disabled greetd" test ! -e "$tmp/units/greetd.service.enabled"
check "undo reports the greeter undone" last_out_is "ok system=greeter state=undone"

# greetd reads its configuration when it starts: while it runs, undo keeps
# the PAM service and the directories its next greeter needs, and a later
# boot's undo removes them.
fresh
run_tty "apply before an undo while greetd runs" 0 apply greeter
touch "$tmp/units/greetd.service.active"; rm -f -- "${tmp:?}/sudo.log"
run_tty "undo while greetd runs" 0 undo greeter
check "undo while greetd runs keeps the PAM service and the directories" test "$(sudo_calls)" == "$(session \
  "-- $(p rm) -f -- $greeter_toml" \
  "-- $(p rm) -f -- $greeter_dropin" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $dropin_dir" \
  "-- $(p systemctl) disable greetd.service" \
  "-- $(p systemctl) daemon-reload" \
  "-- $(p tee) -- $records/.greeter" \
  "-- $(p mv) -fT -- $records/.greeter $records/greeter")"
check "the kept record names the PAM service, the directories and the boot" test "$(cat "$records/greeter")" == "$(printf 'uid=%s\npam=%s\ngreeter-dir=1\ntheme-dir=1\ncopy-dir=1\nstate-dir=1\ndeferred=%s' "$uid" "$(file_hash "$greeter_pam")" "$boot_a")"
check "undo while greetd runs says the login screen returns after a restart" test "$(grep -c '^ok system=greeter state=deferred$' "$tmp/out") $(grep -c 'returns to the previous setup after a restart' "$tmp/out")" == "1 1"
check "a deferred greeter reads needed" test "$(step_state greeter)" == "needed not-set-up"
rm -f -- "${tmp:?}/sudo.log"
run "undo again in the same boot keeps them and runs nothing" 0 "" undo greeter
check "the second undo in the same boot reports the deferral" test "$(head -n 1 "$tmp/out")" == "ok system=greeter state=deferred"
check "the second undo in the same boot runs no sudo" no_sudo
printf '%s\n' "$boot_b" >"$root/proc/sys/kernel/random/boot_id"
run_tty "undo after a restart" 0 undo greeter
check "undo after a restart removes what was kept" test "$(sudo_calls)" == "$(session \
  "-- $(p rm) -f -- $greeter_pam" \
  "-- $(p rm) -rf -- $greeter_dir/theme/vgshell" \
  "-- $(p rm) -rf -- $greeter_dir/state" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $greeter_dir/theme" \
  "-- $(p rmdir) --ignore-fail-on-non-empty -- $greeter_dir" \
  "-- $(p rm) -f -- $records/greeter")"
check "undo after a restart reports the greeter undone" last_out_is "ok system=greeter state=undone"

# A greetd setup VGS did not make, the distribution's or another: never ready,
# kept enabled, and in force again after undo.
fresh; touch "$tmp/units/greetd.service.enabled"
printf 'other config\n' >"$root/etc/greetd/config.toml"; printf 'other pam\n' >"$root/etc/pam.d/greetd"
check "a greetd another setup enabled reads needed, never ready" test "$(step_state greeter)" == "needed not-set-up"
run_tty "apply over another greetd setup" 0 apply greeter
check "apply over an enabled greetd records no enable" test "$(grep -c '^enabled=' "$records/greeter")" == 0
check "apply over an enabled greetd runs no enable" test "$(grep -c 'enable greetd.service' "$tmp/sudo.log")" == 0
rm -f -- "${tmp:?}/sudo.log"
run_tty "undo over another greetd setup" 0 undo greeter
check "undo never disables a greetd VGS did not enable" test "$(grep -c 'disable greetd.service' "$tmp/sudo.log")" == 0
check "the greetd VGS did not enable stays enabled" test -e "$tmp/units/greetd.service.enabled"
check "the other setup's configuration and PAM service keep their bytes" test "$(cat "$root/etc/greetd/config.toml") $(cat "$root/etc/pam.d/greetd")" == "other config other pam"
check "the drop-in is gone, so greetd reads the other setup again" test ! -e "$greeter_dropin"

# greetd disabled after setup reads needed, and apply enables it alone.
fresh
run_tty "apply before greetd is disabled" 0 apply greeter
rm -f -- "${tmp:?}/units/greetd.service.enabled" "${tmp:?}/sudo.log"
check "greetd disabled after setup reads needed" test "$(step_state greeter)" == "needed greetd-disabled"
run_tty "apply over a disabled greetd" 0 apply greeter
check "apply over a disabled greetd rewrites its record and enables greetd alone" test "$(sudo_calls)" == "$(session \
  "-- $(p tee) -- $records/.greeter" \
  "-- $(p mv) -fT -- $records/.greeter $records/greeter" \
  "-- $(p systemctl) enable greetd.service")"

# The greeter starts only under graphical.target: apply makes it the
# default, and undo restores the default it replaced while it is still
# graphical.target.
fresh; printf 'multi-user.target\n' >"$tmp/units/default-target"
run_tty "apply over a multi-user default" 0 apply greeter
check "apply makes graphical.target the default last" test "$(tail -n 2 "$tmp/sudo.log" | head -n 1)" == "-- $(p systemctl) set-default graphical.target"
check "the record names the default it replaced" grep -qx 'target=multi-user.target' "$records/greeter"
check "the default is graphical.target" test "$(default_target)" == graphical.target
printf 'multi-user.target\n' >"$tmp/units/default-target"
check "another default after setup reads needed" test "$(step_state greeter)" == "needed not-graphical-target"
printf 'graphical.target\n' >"$tmp/units/default-target"; rm -f -- "${tmp:?}/sudo.log"
run_tty "undo restores the default" 0 undo greeter
check "undo restores the default it replaced" grep -qxF -- "-- $(p systemctl) set-default multi-user.target" "$tmp/sudo.log"
check "the default is multi-user.target again" test "$(default_target)" == multi-user.target
fresh; printf 'multi-user.target\n' >"$tmp/units/default-target"
run_tty "apply before another default is chosen" 0 apply greeter
printf 'rescue.target\n' >"$tmp/units/default-target"; rm -f -- "${tmp:?}/sudo.log"
run_tty "undo after another default was chosen" 0 undo greeter
check "undo keeps a default chosen after apply" test "$(grep -c 'set-default' "$tmp/sudo.log") $(default_target)" == "0 rescue.target"

# The greeter account and the VT follow the distribution's greetd package.
fresh; printf '_greetd\n' >"$tmp/greeter-name"
check "Debian's _greetd account is the greeter account" test "$(step_state greeter)" == "needed not-set-up"
run_tty "apply with the _greetd account" 0 apply greeter
check "the greetd configuration runs the greeter as _greetd" holds_text "$greeter_toml" "$(want_toml_of 1 _greetd)"
fresh; printf '[terminal]\nvt = 7 # the packaged VT\n\n[default_session]\nvt = 3\n' >"$root/etc/greetd/config.toml"
run_tty "apply with the packaged VT 7" 0 apply greeter
check "the greetd configuration takes the packaged VT" holds_text "$greeter_toml" "$(want_toml_of 7 greeter)"
check "the packaged configuration keeps its bytes" test "$(cat "$root/etc/greetd/config.toml")" == "$(printf '[terminal]\nvt = 7 # the packaged VT\n\n[default_session]\nvt = 3')"
fresh; printf '[terminal]\nvt = "next"\n' >"$root/etc/greetd/config.toml"
run_tty "apply with a VT that is no number" 0 apply greeter
check "a VT that is no number reads 1" holds_text "$greeter_toml" "$want_toml"

# A directory VGS did not make stays.
fresh; mkdir -p "$greeter_dir/theme"; chmod 0755 "$greeter_dir" "$greeter_dir/theme"
run_tty "apply over a theme directory already there" 0 apply greeter
check "the record claims only the directories apply made" test "$(grep -- '-dir=' "$records/greeter")" == "$(printf 'dropin-dir=1\ncopy-dir=1\nstate-dir=1')"
rm -f -- "${tmp:?}/sudo.log"
run_tty "undo over a theme directory VGS did not make" 0 undo greeter
check "undo keeps a directory VGS did not make" test -d "$greeter_dir/theme" -a ! -e "$greeter_dir/theme/vgshell"

# VGS's own file from an older release is rewritten, and nothing else.
fresh
run_tty "apply before a newer release" 0 apply greeter
printf '# a newer release\n' >>"$greeter_src/vgs-greeter.pam"
check "a VGS file an older release wrote reads needed" test "$(step_state greeter)" == "needed not-set-up"
rm -f -- "${tmp:?}/sudo.log"
run_tty "apply rewrites VGS's own file" 0 apply greeter
check "apply rewrites only the changed file" test "$(sudo_calls)" == "$(session \
  "-- $(p tee) -- $records/.greeter" \
  "-- $(p mv) -fT -- $records/.greeter $records/greeter" \
  "-- $(p install) -m 0644 -o root -g root -T -- $greeter_src/vgs-greeter.pam $greeter_pam")"
check "a second apply keeps that VGS enabled greetd" grep -qx 'enabled=1' "$records/greeter"
cp -- "$repo/config/system/greeter/vgs-greeter.pam" "$greeter_src/vgs-greeter.pam"; chmod go-w "$greeter_src/vgs-greeter.pam"
# A file edited after VGS wrote it is foreign to undo, and the record stays.
fresh
run_tty "apply before an edit of the PAM service" 0 apply greeter
printf '# edited\n' >>"$greeter_pam"
run "undo refuses an edited PAM service" 1 "vgs-system: refused: destination=foreign path=$greeter_pam" undo greeter
check "the edited PAM service stays" grep -qxF '# edited' "$greeter_pam"
check "the record stays for the edited PAM service" test -e "$records/greeter"

# Files VGS did not write are refused before the question.
fresh; printf 'someone else\n' >"$greeter_toml"
run "apply refuses a greetd configuration VGS did not write" 1 "vgs-system: refused: destination=foreign path=$greeter_toml" apply greeter
check "the foreign greetd configuration keeps its bytes" test "$(cat "$greeter_toml")" == "someone else"
check "a foreign greetd configuration asks nothing and runs no sudo" test ! -e "$tmp/gum.log" -a ! -e "$tmp/sudo.log"
fresh; ln -s /dev/null "$greeter_pam"
run "apply refuses a symbolic link at the PAM service" 1 "vgs-system: refused: destination=symlink path=$greeter_pam" apply greeter
check "a symlinked PAM service runs no sudo" no_sudo
fresh; mkdir -p "$greeter_dir"; chmod 0755 "$greeter_dir"; ln -s /tmp "$greeter_dir/state"
run "apply refuses a symbolic link at the state directory" 1 "vgs-system: refused: destination=symlink path=$greeter_dir/state" apply greeter
fresh; mkdir -p "$greeter_dir/theme"; chmod 0755 "$greeter_dir"; chmod 0777 "$greeter_dir/theme"
run "apply refuses a theme directory others can write" 1 "vgs-system: refused: untrusted=$greeter_dir/theme" apply greeter

# Another display manager is never fought.
fresh; printf 'sddm.service\n' >"$tmp/units/display-manager"
check "another display manager reads denied" test "$(step_state greeter)" == "denied other-display-manager"
run "apply refuses while another display manager is enabled" 1 "vgs-system: refused: state=denied reason=other-display-manager step=greeter fix=disable-sddm.service" apply greeter
check "the refusal names the display manager VGS leaves alone" grep -qF "sddm.service is the enabled display manager, and VGS never disables it." "$tmp/err"
check "the other display manager's refusal runs no sudo" no_sudo
check "the other display manager is never disabled" test "$(grep -c '^disable' "$tmp/systemctl.log")" == 0

# What the greeter needs to start, and the install tree it runs.
fresh; touch "$tmp/units/greetd.service.missing"
check "no greetd unit reads absent" test "$(step_state greeter)" == "absent greetd-missing"
fresh; touch "$tmp/no-greeter"
check "no greeter account reads absent" test "$(step_state greeter)" == "absent greeter-user-missing"
fresh; touch "$tmp/getent-fail"
check "an account lookup that fails reads unknown" test "$(step_state greeter)" == "unknown getent-failed"
fresh; printf '%s %s\n' "$uid" "$vgs" >"$tmp/owners"
check "an install tree its owner can write reads denied" test "$(step_state greeter)" == "denied install-untrusted"
run "apply refuses an install tree its owner can write" 1 "vgs-system: refused: state=denied reason=install-untrusted step=greeter" apply greeter
check "the refused install tree runs no sudo" no_sudo
fresh; printf '%s %s\n' "$uid" "$vgs/config/system/greeter/hyprland.lua" >"$tmp/owners"
check "a greeter compositor configuration its owner can write reads denied" test "$(step_state greeter)" == "denied install-untrusted"
fresh; chmod 0775 "$vgs/shell"
check "a shell directory its group can write reads denied" test "$(step_state greeter)" == "denied install-untrusted"
chmod 0755 "$vgs/shell"
# An install path with a space never reaches the greeter's command line.
spaced="$tmp/v gs"
spaced_state() { rm -rf -- "${spaced:?}"; cp -R -- "$vgs" "$spaced"; "${row_env[@]}" "$spaced/bin/vgshell-system" status --json </dev/null 2>/dev/null | python3 -c 'import json,sys; s=json.load(sys.stdin)["steps"]["greeter"]; print(s["state"] + " " + s["reason"])'; }
fresh
check "an install path with a space reads denied" test "$(spaced_state)" == "denied install-path-unsupported"
fresh; mkdir -p "$greeter_dir/theme/vgshell"; printf '1234 %s\n' "$greeter_dir/theme/vgshell" >"$tmp/owners"
check "a theme copy directory another account owns reads denied" test "$(step_state greeter)" == "denied other-account"

# The record: root's, of its step's keys, and the caller's own.
fresh
run_tty "apply before the record rows" 0 apply service-bluetooth
sed -i "s/^uid=$uid\$/uid=4242/" "$records/service-bluetooth"
run "undo refuses another uid's record" 1 "vgs-system: refused: record=other-uid uid=4242 path=$records/service-bluetooth" undo service-bluetooth
printf 'uid=%s\nenabled=yes\n' "$uid" >"$records/service-bluetooth"
run "undo refuses a malformed record" 1 "vgs-system: refused: record=malformed path=$records/service-bluetooth" undo service-bluetooth
printf 'uid=%s\nrule=%s\n' "$uid" "$hash" >"$records/service-bluetooth"
run "undo refuses a key of another step" 1 "vgs-system: refused: record=malformed path=$records/service-bluetooth" undo service-bluetooth
printf 'uid=%s\nenabled=1\n' "$uid" >"$records/service-bluetooth"; printf '1234 %s\n' "$records/service-bluetooth" >"$tmp/owners"
run "undo refuses a record root does not own" 1 "vgs-system: refused: record=untrusted path=$records/service-bluetooth" undo service-bluetooth
check "a refused record runs no sudo" test "$(grep -c systemctl "$tmp/sudo.log")" == 1

# Root is refused: the steps act for the caller's own account.
fresh
caller_root() {
  local status=0 err
  err="$("${row_env[@]}" "$unshare_bin" -r "$helper" status 2>&1 >/dev/null </dev/null)" || status=$?
  test "${err%%$'\n'*} exit=$status" == "vgs-system: refused: caller=root exit=1"
}
check "root is refused" caller_root

# NixOS: a needed step reads nixos; apply prints the snippet; nothing is
# written and no sudo runs.
fresh
run_nixos "nixos status" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
check "nixos reads each needed step as nixos" out_is "$(state_json nixos hidraw-denied nixos module-not-loaded nixos inactive absent unit-missing nixos operator-unset nixos not-set-up)"
check "nixos status writes nothing" untouched
run_nixos "nixos apply prints the configuration" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply apple-displays
check "nixos apply reports the skip first" test "$(head -n 1 "$tmp/out")" == "ok system=apple-displays skipped=nixos-config"
check "nixos apply prints the hidraw lines as udev extraRules" out_has '  SUBSYSTEM=="hidraw", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="9243", TAG+="uaccess"'
check "nixos apply opens services.udev.extraRules" out_has "services.udev.extraRules = ''"
check "nixos apply writes nothing" untouched
check "nixos apply runs no sudo" no_sudo
check "nixos apply asks nothing" test ! -e "$tmp/gum.log"
run_nixos "nixos apply of the operator" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply tailscale-operator
check "nixos operator snippet names the caller" out_has "services.tailscale.extraSetFlags = [ \"--operator=$user\" ];"
run_nixos "nixos apply of the greeter" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply greeter
check "nixos greeter snippet enables greetd" out_has "services.greetd.enable = true;"
nixos_command="${greeter_command//"$vgs"/'${vgshell}'}"
check "nixos greeter snippet runs the VGS package, never this tree" out_has "  command = \"$nixos_command\";"
check "nixos greeter snippet names the package the flake exposes" out_has '  vgshell = "${inputs.vgshell.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/vgshell";'
check "nixos greeter snippet makes the theme copy directory the caller's" out_has "  \"d /var/lib/vgshell/greeter/theme/vgshell 0755 $uid - -\""
check "nixos greeter snippet makes the state directory the greeter account's" out_has '  "d /var/lib/vgshell/greeter/state 0700 greeter greeter -"'
check "nixos greeter apply writes nothing" untouched
# NixOS's greetd module makes greetd the display manager: with the
# snippet's directories and their owners the greeter reads ready.
# Its verdict line goes to stderr, since the reading is the caller's stdout.
greeter_nixos_state() { run_nixos "$1" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json >&2; python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["steps"]["greeter"]; print(s["state"] + " " + s["reason"])' "$tmp/out"; }
touch "$tmp/units/greetd.service.enabled"
check "nixos greetd without the snippet's directories reads nixos" test "$(greeter_nixos_state "nixos greetd without the directories")" == "nixos not-set-up"
mkdir -p "$greeter_dir/theme/vgshell" "$greeter_dir/state"; printf '958 %s\n' "$greeter_dir/state" >"$tmp/owners"
check "nixos greetd with the snippet's directories reads ready" test "$(greeter_nixos_state "nixos greetd with the directories")" == "ready granted"
printf '958 %s\n1234 %s\n' "$greeter_dir/state" "$greeter_dir/theme/vgshell" >"$tmp/owners"
check "nixos greetd with another account's theme copy directory reads nixos" test "$(greeter_nixos_state "nixos greetd with another account's directory")" == "nixos not-set-up"
fresh
run_nixos "nixos undo" 0 "" "$nixos_path:$caller:/usr/bin:/bin" undo service-bluetooth
check "nixos undo reports the skip" test "$(head -n 1 "$tmp/out")" == "ok system=service-bluetooth skipped=nixos-config"
check "nixos undo writes nothing" untouched
check "nixos rows run no sudo" no_sudo
run_nixos "a failed detection fails apply" 1 "vgs-system: refused: system=undetected exit=127" "$nixos_path:$no_node_path" apply apple-displays
check "a failed detection writes nothing" untouched
run_nixos "a failed detection reads needed steps unknown" 0 "" "$nixos_path:$no_node_path" status --json
check "an undetected system never reads needed as ready" out_is "$(state_json unknown system-undetected unknown system-undetected unknown system-undetected absent unit-missing unknown system-undetected unknown system-undetected)"
check "an undetected system runs no sudo" no_sudo

# Must-fail controls, each a copy of the helper missing one rule.
control() { # NAME NEEDLE REPLACEMENT
  local copy="$tmp/control-$1"
  check "the $1 control's text occurs once" test "$(python3 -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$source_file" "$2")" == 1
  python3 -c 'import sys; p, o, a, b = sys.argv[1:]; s = open(p).read(); open(o, "w").write(s.replace(a, b))' "$source_file" "$copy" "$2" "$3"
  check "the $1 mutant differs" test "$(cmp -s "$source_file" "$copy"; echo $?)" == 1
  place "$copy"
  fresh
}
control writes-before-question '  # A root command is never answered for the user, unattended or not.' '  vgs_tui_sudo_session start; mode=run; plan "$verb" "$step"; mode=show
  # A root command is never answered for the user, unattended or not.'
printf '1\n' >"$tmp/gum-answer"
run_tty "the writes-before-question mutant's declined apply" 1 apply apple-displays
check "the writes-before-question mutant runs root commands before the answer" grep -qF -- "-- $(p tee) -- $records/.apple-displays" "$tmp/sudo.log"
control undeclared-step '      known_step "$1" || bad_invocation' '      true || bad_invocation'
run "the undeclared-step mutant accepts a step outside the table" 1 "vgs-system: refused: internal=probe step=etc-shadow" apply etc-shadow
control file-presence '    opens_rw "$node" || denied=1' '    [[ -e $node ]] || denied=1'
check "the file-presence mutant reads a closed node ready" test "$(step_state apple-displays)" == "ready granted"
control disable-blind '  [[ -z ${record[enabled]+set} ]] || cmd "$systemctl" disable "$unit"' '  cmd "$systemctl" disable "$unit"'
touch "$tmp/units/bluetooth.service.enabled"
run_tty "the disable-blind mutant applies" 0 apply service-bluetooth
run_tty "the disable-blind mutant undoes" 0 undo service-bluetooth
check "the disable-blind mutant disables a unit VGS did not enable" grep -qxF -- "-- $(p systemctl) disable bluetooth.service" "$tmp/sudo.log"
control foreign-blind '  [[ -n $2 && $sum == "$2" ]] ||' '  true ||'
printf 'someone else\n' >"$rule"
run_tty "the foreign-blind mutant applies over a foreign rule" 0 apply apple-displays
check "the foreign-blind mutant overwrites the foreign rule" cmp -s -- "$rule_src" "$rule"
control symlink-blind 'no_symlink() { [[ ! -L $1 ]] ||' 'no_symlink() { true ||'
printf 'elsewhere\n' >"$tmp/elsewhere"; ln -s "$tmp/elsewhere" "$rule"
run "the symlink-blind mutant reaches the foreign check" 1 "vgs-system: refused: destination=foreign path=$rule" apply apple-displays
control unattended "VGS_TUI_UNATTENDED='' vgs_tui_confirm" 'vgs_tui_confirm'
tty_env=(VGS_TUI_UNATTENDED=1); printf '1\n' >"$tmp/gum-answer"
run_tty "the unattended mutant applies unasked" 0 apply apple-displays
check "the unattended mutant asks nothing" test ! -e "$tmp/gum.log"
tty_env=()
control plan-blind '  [[ $shown == "$planned" ]] ||' '  true ||'
printf '#!/bin/sh\ntouch %q\n' "$tmp/units/bluetooth.service.enabled" >"$tmp/gum-hook"; chmod +x "$tmp/gum-hook"
run_tty "the plan-blind mutant runs a plan it did not show" 0 apply service-bluetooth
control uid-blind '  [[ ${record[uid]} == "$uid" ]] ||' '  true ||'
mkdir -p "$records"; printf 'uid=4242\nenabled=1\n' >"$records/service-bluetooth"
run_tty "the uid-blind mutant undoes another uid's record" 0 undo service-bluetooth
control operator-blind '  [[ $operator != "${record[operator]}" ]] ||' '  false ||'
mkdir -p "$records"; printf 'uid=%s\noperator=%s\nprevious=\n' "$uid" "$user" >"$records/tailscale-operator"; printf 'someone' >"$tmp/operator"
run_tty "the operator-blind mutant undoes" 0 undo tailscale-operator
check "the operator-blind mutant resets another user's operator" test ! -s "$tmp/operator"
control boot-blind '  [[ -z ${record[started]+set} || ${record[boot]} != "$boot" ]] ||' '  [[ -z ${record[started]+set} ]] ||'
mkdir -p "$records"; printf 'uid=%s\nstarted=1\nboot=%s\n' "$uid" "$boot_b" >"$records/service-bluetooth"
run_tty "the boot-blind mutant undoes" 0 undo service-bluetooth
check "the boot-blind mutant stops a unit an earlier boot's VGS started" grep -qxF -- "-- $(p systemctl) stop bluetooth.service" "$tmp/sudo.log"
control nixos-write "    printf 'NixOS builds the system from its configuration, so VGS changes nothing here.\\n'" "    : >\"\$rule_dest\"
    printf 'NixOS builds the system from its configuration, so VGS changes nothing here.\\n'"
run_nixos "the nixos-write mutant's apply" 0 "" "$nixos_path:$caller:/usr/bin:/bin" apply apple-displays
check "the nixos-write mutant changes the tree" test "$(untouched; echo $?)" == 1
control nixos-blind '  if [[ $detected_system == nix ]]; then
    printf '"'"'ok system=%s skipped=nixos-config\n'"'"' "$step"
    printf '"'"'NixOS builds' '  if false; then
    printf '"'"'ok system=%s skipped=nixos-config\n'"'"' "$step"
    printf '"'"'NixOS builds'
run_nixos "the nixos-blind mutant's apply" 2 "*" "$nixos_path:$caller:/usr/bin:/bin" apply apple-displays
check "the nixos-blind mutant reaches the question" grep -qxF -- "vgs-tui: refused: confirm=no-terminal" "$tmp/err"
control undetected-ready '      [[ ${state_of[$step]} != needed ]] || state_of[$step]=unknown reason_of[$step]=system-undetected' '      :'
run_nixos "the undetected-ready mutant's status" 0 "" "$nixos_path:$no_node_path" status --json
check "the undetected-ready mutant reports needed without a system" out_has '"apple-displays":{"state":"needed"'

control greeter-start '  systemctl is-enabled --quiet greetd.service || cmd "$systemctl" enable greetd.service' '  systemctl is-enabled --quiet greetd.service || cmd "$systemctl" enable --now greetd.service'
run_tty "the greeter-start mutant applies" 0 apply greeter
check "the greeter-start mutant starts greetd" test "$(greeter_never_started; echo $?)" == 1
control greeter-other-manager '  case "$manager" in' '  case greetd.service in'
printf 'sddm.service\n' >"$tmp/units/display-manager"
run_tty "the greeter-other-manager mutant applies beside another display manager" 0 apply greeter
control greeter-disable-blind '  [[ -z ${record[enabled]+set} ]] || cmd "$systemctl" disable greetd.service' '  cmd "$systemctl" disable greetd.service'
touch "$tmp/units/greetd.service.enabled"
run_tty "the greeter-disable-blind mutant applies" 0 apply greeter
run_tty "the greeter-disable-blind mutant undoes" 0 undo greeter
check "the greeter-disable-blind mutant disables a greetd VGS did not enable" grep -qxF -- "-- $(p systemctl) disable greetd.service" "$tmp/sudo.log"
control greeter-trust-blind '  install_trusted || { set_probe denied install-untrusted; return; }' '  true || { set_probe denied install-untrusted; return; }'
printf '%s %s\n' "$uid" "$vgs" >"$tmp/owners"
check "the greeter-trust-blind mutant reads an install tree its owner can write needed" test "$(step_state greeter)" == "needed not-set-up"
control greeter-path-blind '  [[ $install_root =~ $install_path_pattern ]] ||' '  true ||'
check "the greeter-path-blind mutant reads an install path with a space needed" test "$(spaced_state)" == "needed not-set-up"
control greeter-ready-blind '  greeter_in_place || status=$?' '  true || status=$?'
touch "$tmp/units/greetd.service.enabled"
check "the greeter-ready-blind mutant reads another greetd setup ready" test "$(step_state greeter)" == "ready granted"
control greeter-enabled-blind '  systemctl is-enabled --quiet greetd.service || { set_probe needed greetd-disabled; return; }' '  true || { set_probe needed greetd-disabled; return; }'
run_tty "the greeter-enabled-blind mutant applies" 0 apply greeter
rm -f -- "${tmp:?}/units/greetd.service.enabled"
check "the greeter-enabled-blind mutant reads a disabled greetd ready" test "$(step_state greeter)" == "ready granted"
control greeter-target-blind '  [[ $default_target == graphical.target ]] || { set_probe needed not-graphical-target; return; }' '  true || { set_probe needed not-graphical-target; return; }'
run_tty "the greeter-target-blind mutant applies" 0 apply greeter
printf 'multi-user.target\n' >"$tmp/units/default-target"
check "the greeter-target-blind mutant reads a multi-user default ready" test "$(step_state greeter)" == "ready granted"
control greeter-restore-blind '    [[ $default_target != graphical.target ]] || cmd "$systemctl" set-default "${record[target]}"' '    cmd "$systemctl" set-default "${record[target]}"'
printf 'multi-user.target\n' >"$tmp/units/default-target"
run_tty "the greeter-restore-blind mutant applies" 0 apply greeter
printf 'rescue.target\n' >"$tmp/units/default-target"
run_tty "the greeter-restore-blind mutant undoes" 0 undo greeter
check "the greeter-restore-blind mutant replaces a default chosen after apply" test "$(default_target)" == multi-user.target
control greeter-defer-blind '  if [[ $dest_state == own ]] && greetd_runs_vgs; then keep=1; fi' '  :'
run_tty "the greeter-defer-blind mutant applies" 0 apply greeter
touch "$tmp/units/greetd.service.active"
run_tty "the greeter-defer-blind mutant undoes while greetd runs" 0 undo greeter
check "the greeter-defer-blind mutant removes the PAM service greetd still uses" test ! -e "$greeter_pam"
control greeter-boot-blind '  [[ -z ${record[deferred]+set} || ${record[deferred]} == "$boot" ]]' '  true'
run_tty "the greeter-boot-blind mutant applies" 0 apply greeter
touch "$tmp/units/greetd.service.active"
run_tty "the greeter-boot-blind mutant undoes while greetd runs" 0 undo greeter
printf '%s\n' "$boot_b" >"$root/proc/sys/kernel/random/boot_id"
run_tty "the greeter-boot-blind mutant undoes after a restart" 0 undo greeter
check "the greeter-boot-blind mutant keeps the PAM service after a restart" test -e "$greeter_pam"
control greeter-account-list '  for name in greeter _greetd; do' '  for name in greeter; do'
printf '_greetd\n' >"$tmp/greeter-name"
check "the greeter-account-list mutant reads the _greetd account missing" test "$(step_state greeter)" == "absent greeter-user-missing"
control greeter-vt-blind '    if [[ $section == terminal &&' '    if false && [[ $section == terminal &&'
printf '[terminal]\nvt = 7\n' >"$root/etc/greetd/config.toml"
run_tty "the greeter-vt-blind mutant applies" 0 apply greeter
check "the greeter-vt-blind mutant ignores the packaged VT" holds_text "$greeter_toml" "$want_toml"
control greeter-nixos-dirs-blind '  if [[ $manager == greetd.service ]] && owned_by "$greeter_copy" "$uid" && owned_by "$greeter_state" "$greeter_uid"; then' '  if [[ $manager == greetd.service ]]; then'
touch "$tmp/units/greetd.service.enabled"
check "the greeter-nixos-dirs-blind mutant reads NixOS ready without the directories" test "$(greeter_nixos_state "the greeter-nixos-dirs-blind mutant's status")" == "ready granted"
control greeter-dirs-blind '    [[ -z ${record[${dir##*:}]+set} || ! -e ${dir%:*} ]] || cmd "$rm" -rf -- "${dir%:*}"' '    [[ ! -e ${dir%:*} ]] || cmd "$rm" -rf -- "${dir%:*}"'
mkdir -p "$greeter_dir/theme/vgshell"; chmod 0755 "$greeter_dir" "$greeter_dir/theme" "$greeter_dir/theme/vgshell"
run_tty "the greeter-dirs-blind mutant applies" 0 apply greeter
run_tty "the greeter-dirs-blind mutant undoes" 0 undo greeter
check "the greeter-dirs-blind mutant removes a directory VGS did not make" test ! -e "$greeter_dir/theme/vgshell"
control greeter-account-blind '    owned_by "$greeter_copy" "$uid" || { set_probe denied other-account; return; }' '    true || { set_probe denied other-account; return; }'
mkdir -p "$greeter_dir/theme/vgshell"; printf '1234 %s\n' "$greeter_dir/theme/vgshell" >"$tmp/owners"
check "the greeter-account-blind mutant reads another account's theme copy directory needed" test "$(step_state greeter)" == "needed not-set-up"

# These assertions use the same state contract as the probe rows above.
# A mutant must make that contract fail, not merely produce some output.
capture_contract() { test "$(step_state bandwhich-capture)" == "$1"; }
capture_control_rejected() {
  local status=0
  capture_contract "$1" || status=$?
  printf 'control: capture=%s expected=%s exit=%s\n' "$2" "$1" "$status"
  test "$status" == 1
}
control capture-three-caps 'capture_caps=cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin' 'capture_caps=cap_dac_read_search,cap_net_raw,cap_net_admin'
capture_fixture; printf 'cap_dac_read_search,cap_net_admin,cap_net_raw=ep\n' >"$tmp/capture-caps"
check "the three-cap mutant fails the needed contract" capture_control_rejected "needed capture-needed" three-caps
control capture-flags '    [[ ${granted[$cap]-} == *e* && ${granted[$cap]-} == *p* ]] ||' '    [[ -n ${granted[$cap]+set} ]] ||'
capture_fixture; printf 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin=p\n' >"$tmp/capture-caps"
check "the flag-blind mutant fails the effective-grant contract" capture_control_rejected "needed capture-needed" flags
control capture-ready '  IFS=, read -r -a members <<<"$capture_caps"
  for cap in' '  set_probe needed capture-needed; return
  IFS=, read -r -a members <<<"$capture_caps"
  for cap in'
capture_fixture; printf '%s\n' "$capture_all" >"$tmp/capture-caps"
check "the ready mutant fails the ready contract" capture_control_rejected "ready granted" ready
control capture-absent 'found="$(PATH="$search_path" command -v bandwhich)" || { set_probe absent bandwhich-missing; return 1; }' 'found="$(PATH="$search_path" command -v bandwhich)" || { set_probe needed capture-needed; return 1; }'
check "the absent mutant fails the absent contract" capture_control_rejected "absent bandwhich-missing" absent
control capture-trust '    trusted "${dir:-/}" || { set_probe denied install-untrusted; return 1; }' '    true || { set_probe denied install-untrusted; return 1; }'
capture_fixture; printf '%s %s\n' "$uid" "$bin/bandwhich" >"$tmp/owners"
check "the trust mutant fails the ownership contract" capture_control_rejected "denied install-untrusted" owner
rm -f -- "$tmp/owners"; chmod 0775 "$bin/bandwhich"
check "the trust mutant fails the writable binary contract" capture_control_rejected "denied install-untrusted" mode
chmod 0755 "$bin/bandwhich"; chmod 0775 "$bin"
check "the trust mutant fails the writable parent contract" capture_control_rejected "denied install-untrusted" parent
chmod 0755 "$bin"
capture_nixos_control_rejected() {
  local status=0
  capture_nixos_contract ready granted || status=$?
  printf 'control: capture=%s expected=ready exit=%s\n' "$1" "$status"
  test "$status" == 1
}
for mutation in wrapper-path wrapper-probe; do
  case "$mutation" in
    wrapper-path) control capture-wrapper-path '  if [[ $detected_system == nix ]]; then search_path="$prefix/run/wrappers/bin:$search_path"; fi' '  if false; then search_path="$prefix/run/wrappers/bin:$search_path"; fi' ;;
    wrapper-probe) control capture-wrapper-probe '  ((system_known == 1)) ||' '  if [[ $detected_system == nix ]]; then set_probe needed capture-needed; return; fi
  ((system_known == 1)) ||' ;;
  esac
  capture_fixture; capture_wrapper_fixture
  printf '%s\n' "$capture_wrapper_all" >"$tmp/wrapper-caps"
  run_nixos "the capture NixOS $mutation mutant's status" 0 "" "$nixos_path:$caller:/usr/bin:/bin" status --json
  check "the NixOS $mutation mutant fails the ready contract" capture_nixos_control_rejected "$mutation"
done

rows_done "$suite"
