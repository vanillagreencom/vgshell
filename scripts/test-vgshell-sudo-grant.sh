#!/usr/bin/env bash
# Controls for bin/vgshell-sudo-grant, the passwordless sudo grant, timed or
# indefinite, reached through `vgshell sudo`: the verbs and their bounds,
# install, the install a grant runs first and uninstall, the status read of
# sudo's own listing, the rule texts and the deadline, the visudo check, the
# expiry timer, publication by rename, the boot cleanup's glob, the NixOS
# configuration-only path, the toggle, the questions, the refusals of the
# root half and its startup.
# Every row runs a copy of vgshell and of the
# helper whose `prefix` is a temporary tree, so its /etc, /run and /usr are
# that tree's. sudo, visudo, systemd-run, systemctl, getent and gum are
# stand-ins there; the sudo stand-in runs the root half under `unshare -r`,
# where the tree reads as root's and nothing outside it is writable, so no
# row reaches the real /etc, the system's sudo or systemd. NixOS rows bind
# a fixture over /etc/os-release in a private mount namespace, keep the
# helper as the non-root user, and assert that the tree and sudo log stay
# untouched; their controls plant a forbidden write and remove the NixOS
# dispatch.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
suite=test-vgshell-sudo-grant
source_file="$repo/bin/vgshell-sudo-grant"
uid="$(id -u)"; gid="$(id -g)"
((uid != 0)) || { echo "$suite: status=not-measured reason=runs-as-root"; exit 77; }
for tool in unshare setsid script find mount sh; do
  command -v "$tool" >/dev/null || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
done
unshare_bin="$(command -v unshare)"; setsid_bin="$(command -v setsid)"; script_bin="$(command -v script)"
mount_bin="$(command -v mount)"; sh_bin="$(command -v sh)"
"$unshare_bin" -r true 2>/dev/null || { echo "$suite: status=not-measured missing=user-namespaces"; exit 77; }
stat_bin="$(command -v stat)"; date_bin="$(command -v date)"

root="$tmp/root"; bin="$root/usr/bin"; installed="$root/usr/local/bin/vgs-sudo-grant"
vgs="$tmp/vgshell"; helper="$vgs/bin/vgshell-sudo-grant"
rule="$root/etc/sudoers.d/99-vgs-nopasswd-$uid"; boot="$root/etc/tmpfiles.d/vgs-sudo-grant.conf"
perm="$root/etc/sudoers.d/99-vgs-permanent-nopasswd-$uid"
unit="vgs-sudo-grant-expire-$uid"
mkdir -p "$bin" "$vgs/bin" "$vgs/shell/Core" "$tmp/home"
cp -- "$repo/bin/vgshell" "$vgs/bin/vgshell"
cp -- "$repo/bin/vgshell-pkg" "$vgs/bin/vgshell-pkg"
cp -R -- "$repo/bin/lib" "$vgs/bin/lib"
cp -- "$repo/shell/Core/PackageManagers.js" "$vgs/shell/Core/PackageManagers.js"
template="$vgs/bin/lib/tmpfiles.d/vgs-sudo-grant.conf"
for tool in awk cat chmod chown cmp cp env find flock grep id install mkdir mktemp mv readlink rm sed touch; do
  tool_bin="$(command -v "$tool")" || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$bin/$tool"
done
# stat reports owner 1234 for the path $tmp/foreign names.
cat >"$bin/stat" <<EOF
#!/bin/sh
out="\$($stat_bin "\$@")" || exit \$?
for last; do :; done
if [ -f "$tmp/foreign" ] && [ "\$last" = "\$(cat "$tmp/foreign")" ]; then printf '%s\n' "\$out" | sed 's/^[0-9]* /1234 /'; else printf '%s\n' "\$out"; fi
EOF
# date prints a malformed deadline for `-d @<epoch>` while $tmp/date-junk exists.
cat >"$bin/date" <<EOF
#!/bin/sh
case "\$*" in *"-d @"*) [ -e "$tmp/date-junk" ] && { echo 2026-01-01; exit 0; } ;; esac
exec $date_bin "\$@"
EOF
# sudo: -h prints a usage with or without -N; -k is recorded and drops the
# credential, which every other call without -n or -N caches, as an
# install's does. `-n -l -l` prints $tmp/sudo-list-raw and exits with
# $tmp/sudo-list-exit when that file exists; else, while a grant file holds
# NOPASSWD, it lists the grant files as sudo 1.9.17 does, without their
# `Sudoers entry:` lines while $tmp/sudo-unnamed exists, and otherwise
# refuses: a password is required. Any other -n runs its command while the
# credential is cached, or while a grant file exists and $tmp/sudo-ignores
# is absent. Any other call exits with $tmp/sudo-exit when present, else
# runs its command as the namespace's root with SUDO_UID set.
cat >"$bin/sudo" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/sudo.log"
case "\$1" in
  -h)
    echo 'usage: sudo -h | -K | -k | -V'
    if [ -e "$tmp/sudo-old" ]; then echo 'usage: sudo [-ABbEHPSn] [-C num]'; else echo 'usage: sudo -v [-ABkNnS] [-g group]'; fi
    exit 0 ;;
  -k) rm -f "$tmp/sudo-cached"; exit 0 ;;
esac
if [ "\$*" = "-n -l -l" ]; then
  if [ -e "$tmp/sudo-list-exit" ]; then read -r st <"$tmp/sudo-list-exit"; cat "$tmp/sudo-list-raw"; exit "\$st"; fi
  if ! cat "$rule" "$perm" 2>/dev/null | grep -q NOPASSWD; then echo 'sudo: a password is required' >&2; exit 1; fi
  printf 'User vgsuser may run the following commands on host:\n\n'
  for f in "$rule" "$perm"; do
    [ -e "\$f" ] || continue
    [ -e "$tmp/sudo-unnamed" ] || echo "Sudoers entry: \$f"
    printf '    RunAsUsers: ALL\n    Options: !authenticate\n'
    na="\$(sed -n 's/.*NOTAFTER=\([0-9]*Z\).*/\1/p' "\$f")"
    [ -z "\$na" ] || echo "    NotAfter: \$na"
    printf '    Commands:\n\tALL\n\n'
  done
  exit 0
fi
nonint=0 keep=0
while :; do case "\$1" in -n) nonint=1; shift ;; -N) keep=1; shift ;; --) shift; break ;; *) break ;; esac; done
if [ \$nonint = 1 ]; then
  if [ -e "$tmp/sudo-cached" ]; then exec "\$@"; fi
  if [ -e "$rule" ] || [ -e "$perm" ]; then [ -e "$tmp/sudo-ignores" ] || exec "\$@"; fi
  echo 'sudo: a password is required' >&2; exit 1
fi
if [ -f "$tmp/sudo-exit" ]; then read -r st <"$tmp/sudo-exit"; exit "\$st"; fi
[ \$keep = 1 ] || touch "$tmp/sudo-cached"
exec $unshare_bin -r env SUDO_UID="\${STUB_SUDO_UID:-$uid}" "\$@"
EOF
# visudo keeps the file it checked and its environment, and exits with $tmp/visudo-exit, 0 when absent.
cat >"$bin/visudo" <<EOF
#!/bin/sh
for a; do f="\$a"; done
cp -- "\$f" "$tmp/checked-rule"
env >"$tmp/visudo-env"
st=0; [ -f "$tmp/visudo-exit" ] && read -r st <"$tmp/visudo-exit"
exit "\$st"
EOF
# systemd-run records its argv and arms the timer unless $tmp/arm-exit holds a status.
cat >"$bin/systemd-run" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/systemd-run.log"
[ -f "$tmp/arm-exit" ] && { read -r st <"$tmp/arm-exit"; exit "\$st"; }
touch "$tmp/timer-active"
EOF
# systemctl: stop exits 5 for a unit not loaded; is-active answers the timer's state.
cat >"$bin/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/systemctl.log"
case "\$1 \$2" in
  "stop $unit.timer") [ -e "$tmp/timer-active" ] || exit 5; rm -f "$tmp/timer-active" ;;
  "stop $unit.service") exit 5 ;;
  "is-active --quiet") [ "\$3" = "$unit.timer" ] && [ -e "$tmp/timer-active" ] ;;
  *) exit 64 ;;
esac
EOF
# getent names the account $tmp/account holds, vgsuser when absent.
cat >"$bin/getent" <<EOF
#!/bin/sh
[ "\$1 \$2" = "passwd $uid" ] || exit 2
name=vgsuser; [ -f "$tmp/account" ] && read -r name <"$tmp/account"
echo "\$name:x:$uid:$gid::/home/\$name:/bin/sh"
EOF
# systemd-tmpfiles --remove --boot -- FILE runs FILE's `r!` lines inside the
# tree, unless $tmp/tmpfiles-exit holds a status.
cat >"$bin/systemd-tmpfiles" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/tmpfiles.log"
[ -f "$tmp/tmpfiles-exit" ] && { read -r st <"$tmp/tmpfiles-exit"; exit "\$st"; }
[ "\$1 \$2 \$3" = "--remove --boot --" ] || exit 64
awk '!/^[[:space:]]*(#|\$)/' "\$4" | while read -r type path; do
  [ "\$type" = 'r!' ] || exit 65
  for f in $root\$path; do rm -f -- "\$f"; done
done
EOF
# gum confirm appends its arguments to $tmp/gum.log and answers the Nth
# confirm with line N of $tmp/gum-answer, its last line past the end. gum
# choose keeps its arguments in $tmp/gum-choose.log and exits with
# $tmp/gum-choice-exit when present, else prints $tmp/gum-choice, or, with
# neither, the --selected option, as Enter answers.
cat >"$bin/gum" <<EOF
#!/bin/sh
case "\$1" in
  confirm)
    printf '%s\n' "\$@" >>"$tmp/gum.log"
    n="\$(grep -c '^confirm\$' "$tmp/gum.log")"
    st="\$(sed -n "\${n}p" "$tmp/gum-answer")"
    [ -n "\$st" ] || st="\$(sed -n '\$p' "$tmp/gum-answer")"
    exit "\$st" ;;
  choose)
    printf '%s\n' "\$@" >"$tmp/gum-choose.log"
    if [ -f "$tmp/gum-choice-exit" ]; then read -r st <"$tmp/gum-choice-exit"; exit "\$st"; fi
    if [ -f "$tmp/gum-choice" ]; then cat "$tmp/gum-choice"; exit 0; fi
    prev=""
    for a; do [ "\$prev" = --selected ] && printf '%s\n' "\$a"; prev="\$a"; done
    exit 0 ;;
esac
EOF
chmod +x "$bin"/stat "$bin"/date "$bin"/sudo "$bin"/visudo "$bin"/systemd-run "$bin"/systemctl "$bin"/getent "$bin"/gum "$bin"/systemd-tmpfiles

# SOURCE's `prefix=` line, which must occur once, names the tree.
place() { # SOURCE
  check "the helper's prefix line occurs once" test "$(grep -c '^prefix=$' "$1")" == 1
  sed "s|^prefix=\$|prefix=$root|" "$1" >"$helper"
  chmod +x "$helper"
  check "the placed helper names the tree" test "$(grep -c "^prefix=$root\$" "$helper")" == 1
}
# A new tree with nothing installed and every record cleared.
fresh() {
  rm -rf -- "${root:?}/etc" "${root:?}/run" "${root:?}/usr/local"
  mkdir -p "$root/etc/sudoers.d" "$root/etc/tmpfiles.d" "$root/run" "$root/usr/local/bin"
  chmod 0755 "$root/etc" "$root/etc/tmpfiles.d" "$root/run"; chmod 0750 "$root/etc/sudoers.d"
  rm -f -- "$tmp"/{sudo.log,systemd-run.log,systemctl.log,gum.log,gum-choose.log,gum-choice,gum-choice-exit,tmpfiles.log,checked-rule,visudo-env,timer-active,foreign,date-junk,sudo-old,sudo-exit,sudo-ignores,sudo-cached,sudo-unnamed,sudo-list-raw,sudo-list-exit,visudo-exit,arm-exit,tmpfiles-exit,account,before-tree,after-tree}
  printf '0\n' >"$tmp/gum-answer"
}
# fresh, then the placed helper installed as the root half with its boot cleanup.
installed() {
  fresh
  cp -- "$helper" "$installed"; chmod 0755 "$installed"
  cp -- "$template" "$boot"; chmod 0644 "$boot"
}
caller="$tmp/caller"; mkdir -p "$caller"
ln -s -- "$node_bin" "$caller/node"
nixos_path="$tmp/nixos-path"; mkdir -p "$nixos_path"
cat >"$nixos_path/nix" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$nixos_path/nix"
no_node_path="$tmp/no-node-path"; mkdir -p "$no_node_path"
for tool in bash readlink dirname id; do
  tool_bin="$(command -v "$tool")" || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$no_node_path/$tool"
done
nixos_os_release="$tmp/os-release-nixos"
printf 'NAME=NixOS\nID=nixos\n' >"$nixos_os_release"
nixos_mount_script="$mount_bin --bind \"\$1\" /etc/os-release && shift && exec $unshare_bin --user --map-user=$uid --map-group=$gid \"\$@\""
nixos_mount_probe_status=0
"$unshare_bin" -rm "$sh_bin" -c "$nixos_mount_script" sh "$nixos_os_release" "$sh_bin" -c "[ \"\$(id -u)\" = \"$uid\" ] && grep -qx ID=nixos /etc/os-release" 2>/dev/null || nixos_mount_probe_status=$?
((nixos_mount_probe_status == 0)) || { echo "$suite: status=not-measured missing=nixos-os-release-namespace"; exit 77; }
row_env=(env -i HOME="$tmp/home" PATH="$caller:/usr/bin:/bin" LANG=C.UTF-8 VGS_PLANTED=1)
# run NAME WANT_EXIT WANT_FIRST_STDERR ARGS...: vgshell sudo ARGS in a session
# with no terminal; `*` takes any stderr. Stdout lands in $tmp/out, stderr in $tmp/err.
run() {
  local name="$1" want_exit="$2" want_err="$3" status=0 err=""
  shift 3
  "${row_env[@]}" "$setsid_bin" -w "$vgs/bin/vgshell" sudo "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ -s $tmp/err ]] && IFS= read -r err <"$tmp/err"
  if [[ $status == "$want_exit" && ($want_err == "*" || $err == "$want_err") ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit stderr=[$err] want=[$want_err]"; fi
}
tree_snapshot() { find "$root" -printf '%P %y %s %m %T@\n' | sort; }
run_nixos_with_path() { # PATH_VALUE NAME WANT_EXIT WANT_FIRST_STDERR ARGS...
  local path_value="$1" name="$2" want_exit="$3" want_err="$4" status=0 err=""
  shift 4
  tree_snapshot >"$tmp/before-tree"
  env -i HOME="$tmp/home" PATH="$path_value" LANG=C.UTF-8 VGS_PLANTED=1 \
    "$unshare_bin" -rm "$sh_bin" -c "$nixos_mount_script" \
    sh "$nixos_os_release" "$setsid_bin" -w "$vgs/bin/vgshell" sudo "$@" \
    </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  tree_snapshot >"$tmp/after-tree"
  [[ -s $tmp/err ]] && IFS= read -r err <"$tmp/err"
  if [[ $status == "$want_exit" && ($want_err == "*" || $err == "$want_err") ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit stderr=[$err] want=[$want_err]"; fi
}
run_nixos_dirty() { # NAME WANT_EXIT WANT_FIRST_STDERR ARGS...
  local name="$1" want_exit="$2" want_err="$3"
  shift 3
  run_nixos_with_path "$nixos_path:$caller:/usr/bin:/bin" "$name" "$want_exit" "$want_err" "$@"
}
run_nixos() { # NAME WANT_EXIT WANT_FIRST_STDERR ARGS...
  local name="$1"
  run_nixos_dirty "$@"
  check "$name leaves the tree unchanged" cmp -s -- "$tmp/before-tree" "$tmp/after-tree"
  check "$name makes no sudo call" test ! -e "$tmp/sudo.log"
  check "$name writes no sudoers rule" no_rule
}
run_nixos_no_nix() { # NAME WANT_EXIT WANT_FIRST_STDERR ARGS...
  run_nixos_with_path "$caller:/usr/bin:/bin" "$@"
}
run_nixos_no_node() { # NAME WANT_EXIT WANT_FIRST_STDERR ARGS...
  run_nixos_with_path "$nixos_path:$no_node_path" "$@"
}
# run_tty NAME WANT_EXIT ARGS...: the same on a pseudo-terminal; stdout and
# stderr together land in $tmp/out, carriage returns dropped.
run_tty() {
  local name="$1" want_exit="$2" status=0
  shift 2
  "${row_env[@]}" SHELL="$BASH" "${tty_env[@]}" "$script_bin" -qec "$(printf '%q ' "$vgs/bin/vgshell" sudo "$@")" /dev/null </dev/null >"$tmp/raw" 2>&1 || status=$?
  tr -d '\r' <"$tmp/raw" >"$tmp/out"
  if [[ $status == "$want_exit" ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit output=[$(cat "$tmp/out")]"; fi
}
tty_env=()
# root NAME WANT_EXIT WANT_FIRST_STDERR ARGS...: the installed root half run
# directly as the namespace's root, SUDO_UID set to $root_caller.
root_caller="$uid"
root() {
  local name="$1" want_exit="$2" want_err="$3" status=0 err=""
  shift 3
  "${row_env[@]}" "$unshare_bin" -r env SUDO_UID="$root_caller" "$installed" "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ -s $tmp/err ]] && IFS= read -r err <"$tmp/err"
  if [[ $status == "$want_exit" && ($want_err == "*" || $err == "$want_err") ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit stderr=[$err] want=[$want_err]"; fi
}
out_has() { grep -qF -- "$1" "$tmp/out"; }
first_out_matches() { local first; IFS= read -r first <"$tmp/out"; [[ $first =~ $1 ]]; }
sudo_calls() { cat -- "$tmp/sudo.log" 2>/dev/null; }
no_rule() { [[ ! -e $rule && -z $(ls -A -- "$root/etc/sudoers.d") ]]; }
tree_changed() { ! cmp -s -- "$tmp/before-tree" "$tmp/after-tree"; }
# The epoch of a rule's NOTAFTER deadline, from the rule file's text.
deadline_epoch() {
  local text d file="${1:-$rule}"
  text="$(cat -- "$file")"
  [[ $text =~ NOTAFTER=([0-9]{14})Z ]] || return 1
  d="${BASH_REMATCH[1]}"
  "$date_bin" -u -d "${d:0:8} ${d:8:2}:${d:10:2}:${d:12:2}" +%s
}
# Whether the rule's deadline is MINUTES from START, within ten seconds.
deadline_in() { # START MINUTES
  local e want
  e="$(deadline_epoch "${3:-}")" || return 1
  want=$(($1 + $2 * 60))
  ((e >= want - 10 && e <= want + 10))
}
place "$source_file"

# vgshell's own refusal of a subcommand it does not route.
fresh
run "vgshell sudo with no subcommand is refused" 2 "vgshell: refused: sudo-subcommand=missing"
run "an unknown sudo subcommand is refused" 2 "vgshell: refused: sudo-subcommand=elevate" elevate

# Bounds and arguments, refused before any sudo.
for bad in 0 1441 00 -5 abc 1.5 "" " 15" 99999 Indefinite indefinitely; do
  run "grant [$bad] is refused" 2 "vgs-sudo-grant: refused: duration=$(printf '%q' "$bad")" grant "$bad"
done
run "grant takes one argument" 2 "vgs-sudo-grant: refused: argument=x" grant 15 x
run "status takes no argument" 2 "vgs-sudo-grant: refused: argument=x" status x
run "revoke takes no argument" 2 "vgs-sudo-grant: refused: argument=x" revoke x
check "a refused invocation runs no sudo" test ! -e "$tmp/sudo.log"

# Nothing installed: status says so without sudo; revoke refuses.
run "status with no root half" 0 "" status
check "status names the absent root half" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=absent"
run "revoke with no root half is refused" 1 "vgs-sudo-grant: refused: root-half=absent path=$installed" revoke
check "an absent root half's status and revoke run no sudo" test ! -e "$tmp/sudo.log"

# NixOS follows the package-manager table's nix row: VGS writes no sudo
# files and prints the configuration rule the user adds to NixOS.
fresh
run_nixos "nixos status on a fresh tree is skipped" 0 "" status
check "nixos status prints the skip reason" test "$(cat "$tmp/out")" == "sudo-grant=skipped=nixos-config"
installed
run_nixos "nixos status on an installed tree is skipped" 0 "" status
check "nixos installed status prints the skip reason" test "$(cat "$tmp/out")" == "sudo-grant=skipped=nixos-config"
fresh
start="$("$date_bin" +%s)"
run_nixos "nixos grant prints the configuration rule" 0 "" grant
check "nixos grant reports the default deadline first" first_out_matches '^ok sudo-grant=skipped=nixos-config minutes=15 until=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
check "nixos grant names the account in the snippet" out_has 'users = [ "vgsuser" ];'
check "nixos grant sets runAs to ALL" out_has 'runAs = "ALL";'
check "nixos grant writes the string command with NOTAFTER" grep -qxE -- '    commands = \[ "NOTAFTER=[0-9]{14}Z NOPASSWD: ALL" \];' "$tmp/out"
check "nixos grant default deadline is 15 minutes out" deadline_in "$start" 15 "$tmp/out"
installed
start="$("$date_bin" +%s)"
run_nixos "nixos grant 60 prints the configuration rule" 0 "" grant 60
check "nixos grant 60 reports the deadline first" first_out_matches '^ok sudo-grant=skipped=nixos-config minutes=60 until=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
check "nixos grant 60 deadline is 60 minutes out" deadline_in "$start" 60 "$tmp/out"
fresh
run_nixos "nixos grant indefinite prints the configuration rule" 0 "" grant indefinite
check "nixos grant indefinite reports no deadline first" test "$(head -n 1 "$tmp/out")" == "ok sudo-grant=skipped=nixos-config until=indefinite"
check "nixos grant indefinite writes the command without NOTAFTER" grep -qxF -- '    commands = [ "NOPASSWD: ALL" ];' "$tmp/out"
for verb in revoke install uninstall; do
  fresh
  run_nixos "nixos $verb is skipped" 0 "" "$verb"
  check "nixos $verb reports the skip reason" test "$(head -n 1 "$tmp/out")" == "ok sudo-grant=skipped=nixos-config"
done
fresh
run_nixos "nixos grant bad minutes is refused" 2 "vgs-sudo-grant: refused: duration=1441" grant 1441
fresh
printf 'Admin\n' >"$tmp/account"
run_nixos "nixos grant refuses an unsupported account" 1 "vgs-sudo-grant: refused: account=unsupported name=Admin" grant
fresh
run_nixos_no_nix "nixos os-release without nix uses the normal path" 0 "" status
check "nixos without nix reports the normal absent root half" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=absent"
check "nixos without nix still leaves the tree unchanged" cmp -s -- "$tmp/before-tree" "$tmp/after-tree"
check "nixos without nix makes no sudo call on a fresh status" test ! -e "$tmp/sudo.log"
fresh
run_nixos_no_node "nixos without node refuses detection" 1 "vgs-sudo-grant: refused: system=undetected exit=127" status
check "nixos without node makes no sudo call" test ! -e "$tmp/sudo.log"
check "nixos without node leaves the tree unchanged" cmp -s -- "$tmp/before-tree" "$tmp/after-tree"
check "nixos without node writes no sudoers rule" no_rule

# install prints what it places, then places the boot cleanup and then the
# root half, each root's, and drops the credential.
fresh
run "install succeeds" 0 "" install
check "install names the boot cleanup and its line" out_has "  $boot  the boot cleanup: r! /etc/sudoers.d/99-vgs-nopasswd-*"
check "install names the root half" out_has "  $installed  the part of passwordless sudo that runs as root"
check "install prints its paths last" test "$(tail -n 1 "$tmp/out")" == "ok sudo-grant=installed root-half=$installed boot-cleanup=$boot"
check "install places the boot cleanup, then the root half, then drops the credential" test "$(sudo_calls)" == "install -m 0644 -o root -g root -T -- $template $boot
install -m 0755 -o root -g root -T -- $helper $installed
-k"
check "the root half is this helper byte for byte" cmp -s -- "$helper" "$installed"
check "the boot cleanup is the template byte for byte" cmp -s -- "$template" "$boot"
check "the modes are 0755 and 0644" test "$("$stat_bin" -c %a -- "$installed") $("$stat_bin" -c %a -- "$boot")" == "755 644"
fresh; printf 'r /etc/sudoers.d/*\n' >>"$template"
run "a template with another line is not installed" 1 "vgs-sudo-grant: refused: template=malformed path=$template" install
check "a malformed template runs no sudo" test ! -e "$tmp/sudo.log"
cp -- "$repo/bin/lib/tmpfiles.d/vgs-sudo-grant.conf" "$template"
fresh; printf '1\n' >"$tmp/sudo-exit"
run "a failed boot cleanup install stops before the root half" 1 "vgs-sudo-grant: refused: install=boot-cleanup path=$boot" install
check "a failed install places no root half" test ! -e "$installed"

# status reads sudo's own listing: no password, no root action.
installed
run "status with nothing granted" 0 "" status
check "status reports inactive and a current root half" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=current"
check "status asks sudo for the listing alone" test "$(sudo_calls)" == "-n -l -l"

# Listings as sudo 1.9.17p2 prints them under LC_ALL=C, as an Arch
# container answered `sudo -n -l -l`, with this tree's paths: NAME, the
# status sudo exits with, the listing, then status's exit, its first stderr
# line and its stdout.
listing_head='Matching Defaults entries for vgsuser on host:
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/bin

User vgsuser may run the following commands on host:

Sudoers entry: '"$root"'/etc/sudoers.d/10-wheel
    RunAsUsers: ALL
    RunAsGroups: ALL
    Commands:
	ALL
'
timed_entry() { # FILE NOTAFTER
  printf '\nSudoers entry: %s\n    RunAsUsers: ALL\n    Options: !authenticate\n    NotAfter: %s\n    Commands:\n\tALL\n' "$1" "$2"
}
untimed_entry() { # FILE
  printf '\nSudoers entry: %s\n    RunAsUsers: ALL\n    Options: !authenticate\n    Commands:\n\tALL\n' "$1"
}
listings=(
  "a timed grant|0|$listing_head$(timed_entry "$rule" 29990101000000Z)|0||sudo-grant=active until=2999-01-01T00:00:00Z root-half=current"
  "an expired timed grant|0|$listing_head$(timed_entry "$rule" 20000101000000Z)|0||sudo-grant=inactive root-half=current"
  "an indefinite grant|0|$listing_head$(untimed_entry "$perm")|0||sudo-grant=active until=indefinite root-half=current"
  "no passwordless rule|1|sudo: a password is required|0||sudo-grant=inactive root-half=current"
  "another rule's NOPASSWD alone|0|$listing_head$(untimed_entry "$root/etc/sudoers.d/50-other")|0||sudo-grant=inactive root-half=current"
  "another account's grants|0|$listing_head$(timed_entry "$root/etc/sudoers.d/99-vgs-nopasswd-4242" 29990101000000Z)$(untimed_entry "$root/etc/sudoers.d/99-vgs-permanent-nopasswd-4242")|0||sudo-grant=inactive root-half=current"
  "a listing that names no file|0|User vgsuser may run the following commands on host:
    (ALL) NOPASSWD: ALL|1|vgs-sudo-grant: refused: sudo=unsupported|"
  "another sudo failure|1|sudo: unable to read the sudoers file|1|vgs-sudo-grant: refused: status=unreadable exit=1 reply=sudo:\\ unable\\ to\\ read\\ the\\ sudoers\\ file|"
  "an indefinite grant with a deadline|0|$listing_head$(timed_entry "$perm" 29990101000000Z)|1|vgs-sudo-grant: refused: grant=malformed path=$perm|"
  "a timed grant with no deadline|0|$listing_head$(untimed_entry "$rule")|1|vgs-sudo-grant: refused: grant=malformed path=$rule|"
)
for row in "${listings[@]}"; do
  IFS='|' read -r name list_exit text want_exit want_err want_out <<<"${row//$'\n'/$'\x1f'}"
  installed
  printf '%s' "${text//$'\x1f'/$'\n'}" >"$tmp/sudo-list-raw"
  printf '%s\n' "$list_exit" >"$tmp/sudo-list-exit"
  run "status reads $name" "$want_exit" "$want_err" status
  [[ -z $want_out ]] || check "status reads $name as its line" test "$(cat "$tmp/out")" == "$want_out"
done

# A grant with no terminal is refused at the first question and writes nothing.
installed
run "grant with no terminal is refused at the question" 2 "*" grant
check "the no-terminal refusal is the library's" grep -qxF -- "vgs-tui: refused: choose=no-terminal" "$tmp/err"
check "a grant with no answer writes no rule" no_rule
check "a grant with no answer arms no timer" test ! -e "$tmp/systemd-run.log"

# A grant: the duration question starting on the default, the warning, one
# question defaulting to no, the rule checked by visudo, the expiry armed
# for the deadline, the rule published by rename, and the grant proven
# effective with the credential dropped.
installed
start="$("$date_bin" +%s)"
run_tty "a granted grant succeeds" 0 grant
check "the duration question starts on the default among the four durations" test "$(cat "$tmp/gum-choose.log")" == "$(printf '%s\n' choose --header "Turn on passwordless sudo for how long?" --selected "15 minutes" "15 minutes" "1 hour" "1 day" Indefinitely)"
check "the grant asks once, defaulting to no" test "$(cat "$tmp/gum.log")" == "$(printf '%s\n' confirm --default=false -- "Enable passwordless sudo for 15 minutes? This is a significant security risk!")"
check "the rule is the one grant for the account" grep -qxE -- "vgsuser ALL=\(ALL\) NOTAFTER=[0-9]{14}Z NOPASSWD: ALL" "$rule"
check "the rule holds one line" test "$(wc -l <"$rule")" == 1
check "visudo checked the rule that was published" cmp -s -- "$tmp/checked-rule" "$rule"
check "the rule is mode 0440" test "$("$stat_bin" -c %a -- "$rule")" == 440
check "the default deadline is 15 minutes out" deadline_in "$start" 15
check "the staged file is gone" test "$(ls -A -- "$root/etc/sudoers.d")" == "99-vgs-nopasswd-$uid"
check "the expiry removes the rule at the deadline" test "$(cat "$tmp/systemd-run.log")" == "--quiet --collect --on-calendar=@$(deadline_epoch) --timer-property=AccuracySec=1s --unit=$unit -- $root/usr/bin/rm -f -- $rule"
check "the grant reads the listing, enables, drops the credential, then proves the rule" test "$(sudo_calls)" == "-h
-k
-n -l -l
-N -- $installed __enable $uid 15
-k
-n -N -- /usr/bin/true
-k"
check "the grant reports its deadline" out_has "ok sudo-grant=enabled minutes=15 until="
check "the root half's children see no caller variable" test -s "$tmp/visudo-env" -a "$(grep -c '^VGS_PLANTED=' "$tmp/visudo-env")" == 0
check "the root half's children see sudo's caller" grep -qxF -- "SUDO_UID=$uid" "$tmp/visudo-env"
run "status reports the active grant" 0 "" status
check "status names the deadline" grep -qxE -- "sudo-grant=active until=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z root-half=current" "$tmp/out"

# A second run revokes: no question, the timer stopped, the rule gone.
rm -f -- "$tmp/gum.log" "$tmp/gum-choose.log" "$tmp/systemctl.log"
run_tty "a second grant revokes" 0 grant
check "the second run reports the revoke" out_has "ok sudo-grant=revoked"
check "the second run asks nothing" test ! -e "$tmp/gum.log" -a ! -e "$tmp/gum-choose.log"
check "the revoke removes the rule" no_rule
check "the revoke stops the expiry" grep -qxF -- "stop $unit.timer" "$tmp/systemctl.log"
check "the stopped expiry is no longer active" test ! -e "$tmp/timer-active"
run "revoke with nothing granted" 0 "" revoke
check "revoke reports nothing to end" test "$(cat "$tmp/out")" == "ok sudo-grant=inactive"

# DURATION is the choice the question starts on; another number of minutes
# joins the offered durations in order. Each question is declined here.
durations=(
  "60|1 hour|15 minutes,1 hour,1 day,Indefinitely"
  "0060|1 hour|15 minutes,1 hour,1 day,Indefinitely"
  "90|90 minutes|15 minutes,1 hour,90 minutes,1 day,Indefinitely"
  "1|1 minute|1 minute,15 minutes,1 hour,1 day,Indefinitely"
  "1440|1 day|15 minutes,1 hour,1 day,Indefinitely"
  "indefinite|Indefinitely|15 minutes,1 hour,1 day,Indefinitely"
)
for row in "${durations[@]}"; do
  IFS='|' read -r duration selected offered <<<"$row"
  installed; printf '1\n' >"$tmp/gum-answer"
  run_tty "grant $duration asks, then is declined" 1 grant "$duration"
  IFS=, read -r -a labels <<<"$offered"
  check "grant $duration starts the question on $selected" test "$(cat "$tmp/gum-choose.log")" == "$(printf '%s\n' choose --header "Turn on passwordless sudo for how long?" --selected "$selected" "${labels[@]}")"
done

# The bounds are inclusive; another choice than the default is the one
# granted; an unattended caller is still asked.
for minutes in 1 1440; do
  installed; start="$("$date_bin" +%s)"
  run_tty "a grant of $minutes minutes succeeds" 0 grant "$minutes"
  check "a grant of $minutes minutes ends $minutes minutes out" deadline_in "$start" "$minutes"
done
installed; start="$("$date_bin" +%s)"; printf '1 day\n' >"$tmp/gum-choice"
run_tty "a grant answered 1 day over the default succeeds" 0 grant
check "a grant answered 1 day ends a day out" deadline_in "$start" 1440
installed; tty_env=(VGS_TUI_UNATTENDED=1)
run_tty "an unattended grant runs" 0 grant
check "an unattended grant is still asked" test -e "$tmp/gum.log"
tty_env=()

# An indefinite grant: two questions, each defaulting to no, one rule with
# no deadline outside the boot cleanup's names, and no expiry.
installed; printf 'Indefinitely\n' >"$tmp/gum-choice"
run_tty "an indefinite grant succeeds" 0 grant
check "an indefinite grant asks twice, each defaulting to no" test "$(grep -c '^confirm$' "$tmp/gum.log") $(grep -c '^--default=false$' "$tmp/gum.log")" == "2 2"
check "the indefinite rule is the one grant for the account" test "$(cat "$perm")" == "vgsuser ALL=(ALL) NOPASSWD: ALL"
check "visudo checked the indefinite rule" cmp -s -- "$tmp/checked-rule" "$perm"
check "the indefinite rule is mode 0440" test "$("$stat_bin" -c %a -- "$perm")" == 440
check "an indefinite grant arms no expiry" test ! -e "$tmp/systemd-run.log"
check "an indefinite grant writes no timed rule" test "$(ls -A -- "$root/etc/sudoers.d")" == "99-vgs-permanent-nopasswd-$uid"
check "an indefinite grant reports no deadline" out_has "ok sudo-grant=enabled until=indefinite"
run "status reports the indefinite grant" 0 "" status
check "status names no deadline" test "$(cat "$tmp/out")" == "sudo-grant=active until=indefinite root-half=current"
root "the root half reads the indefinite grant" 0 "" __status "$uid"
check "the root half prints active indefinite" test "$(cat "$tmp/out")" == "active indefinite"
root "the root half refuses a timed grant over the indefinite one" 1 "vgs-sudo-grant: refused: grant=active indefinite" __enable "$uid" 15
root "the root half refuses a second indefinite grant" 1 "vgs-sudo-grant: refused: grant=active indefinite" __enable "$uid" indefinite
check "a refused enable leaves the one indefinite rule" test "$(ls -A -- "$root/etc/sudoers.d")" == "99-vgs-permanent-nopasswd-$uid"
rm -f -- "$tmp/gum.log" "$tmp/gum-choose.log"
run_tty "a second grant revokes the indefinite grant" 0 grant
check "the indefinite revoke asks nothing" test ! -e "$tmp/gum.log" -a ! -e "$tmp/gum-choose.log"
check "the indefinite revoke removes the rule" no_rule
installed
run_tty "a timed grant before an indefinite one" 0 grant
root "the root half refuses an indefinite grant over the timed one" 1 "*" __enable "$uid" indefinite
check "the refusal names the active timed grant" grep -qE -- '^vgs-sudo-grant: refused: grant=active deadline=[0-9]{14}Z$' "$tmp/err"
check "the refused indefinite grant writes no rule" test ! -e "$perm"
installed; printf 'Indefinitely\n' >"$tmp/gum-choice"
run_tty "an indefinite grant before revoke" 0 grant
run "revoke ends the indefinite grant" 0 "" revoke
check "revoke reports the indefinite revoke" test "$(cat "$tmp/out")" == "ok sudo-grant=revoked"
check "revoke removes the indefinite rule" no_rule

# The boot cleanup's shipped line, as systemd-tmpfiles runs it at boot,
# removes a timed grant and keeps an indefinite one. Its control, a line
# whose glob is one name wider, removes both.
installed
printf 'vgsuser ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$rule"
printf 'vgsuser ALL=(ALL) NOPASSWD: ALL\n' >"$perm"
check "the boot cleanup runs its line" "$bin/systemd-tmpfiles" --remove --boot -- "$boot"
check "the boot cleanup removes the timed grant" test ! -e "$rule"
check "the boot cleanup keeps the indefinite grant" test -e "$perm"
printf 'r! /etc/sudoers.d/99-vgs-*\n' >"$tmp/wide-boot.conf"
check "control: a wider boot cleanup runs its line" "$bin/systemd-tmpfiles" --remove --boot -- "$tmp/wide-boot.conf"
check "control: a wider boot cleanup removes the indefinite grant" test ! -e "$perm"

# A declined or cancelled question and each failed step write nothing.
installed; printf '1\n' >"$tmp/gum-answer"
run_tty "a declined grant is refused" 1 grant
check "a declined grant names the decline" out_has "vgs-sudo-grant: refused: declined=grant"
check "a declined grant writes no rule" no_rule
installed; printf '130\n' >"$tmp/gum-answer"
run_tty "a cancelled grant exits 130" 130 grant
check "a cancelled grant writes no rule" no_rule
installed; printf '130\n' >"$tmp/gum-choice-exit"
run_tty "a cancelled duration question exits 130" 130 grant
check "a cancelled duration question asks nothing more" test ! -e "$tmp/gum.log"
check "a cancelled duration question writes no rule" no_rule
installed; printf 'Indefinitely\n' >"$tmp/gum-choice"; printf '0\n1\n' >"$tmp/gum-answer"
run_tty "an indefinite grant declined at the second question is refused" 1 grant
check "the second decline names the decline" out_has "vgs-sudo-grant: refused: declined=grant"
check "the second decline came after two questions" test "$(grep -c '^confirm$' "$tmp/gum.log")" == 2
check "the second decline writes no rule" no_rule
installed; printf '1\n' >"$tmp/visudo-exit"
run_tty "a rule visudo refuses fails the grant" 1 grant
check "the refusal names visudo" out_has "vgs-sudo-grant: refused: rule=refused"
check "a refused rule leaves no file" no_rule
check "a refused rule arms no timer" test ! -e "$tmp/systemd-run.log"
installed; printf 'Indefinitely\n' >"$tmp/gum-choice"; printf '1\n' >"$tmp/visudo-exit"
run_tty "an indefinite rule visudo refuses fails the grant" 1 grant
check "a refused indefinite rule leaves no file" no_rule
installed; printf '1\n' >"$tmp/arm-exit"
run_tty "a timer that cannot be armed fails the grant" 1 grant
check "the refusal names the timer" out_has "vgs-sudo-grant: refused: timer=arm-failed unit=$unit"
check "an unarmed timer leaves no file" no_rule
installed; touch "$tmp/date-junk"
run_tty "a malformed deadline fails the grant" 1 grant
check "the refusal names the deadline" out_has "vgs-sudo-grant: refused: deadline=malformed value=2026-01-01"
check "a malformed deadline leaves no file" no_rule
installed; touch "$tmp/sudo-ignores"
run_tty "a grant sudo does not honour is revoked" 1 grant
check "the refusal names the ineffective grant" out_has "vgs-sudo-grant: refused: grant=not-effective revoke-exit=0"
check "an ineffective grant leaves no file" no_rule
check "an ineffective grant's timer is stopped" test ! -e "$tmp/timer-active"
installed; rm -f -- "$boot"
root "the root half refuses a grant with no boot cleanup" 1 "vgs-sudo-grant: refused: boot-cleanup=absent path=$boot" __enable "$uid" 15
check "no boot cleanup, no rule" no_rule
installed; printf 'r /tmp/x\n' >>"$boot"
root "the root half refuses a boot cleanup with another line" 1 "vgs-sudo-grant: refused: boot-cleanup=absent path=$boot" __enable "$uid" 15
check "a changed boot cleanup leaves no file" no_rule
# A grant sets up again a boot cleanup that is gone or changed, so the
# click the root half's refusal names works.
for boot_case in gone changed; do
  installed
  if [[ $boot_case == gone ]]; then rm -f -- "$boot"; else printf 'r /tmp/x\n' >>"$boot"; fi
  run_tty "a grant with a $boot_case boot cleanup sets it up first" 0 grant
  check "the $boot_case boot cleanup is the template again" cmp -s -- "$template" "$boot"
  check "the grant after a $boot_case boot cleanup is published" test -e "$rule"
done
installed; printf '%s\n' "$boot" >"$tmp/foreign"
run_tty "a boot cleanup another user owns is refused" 1 grant
check "a foreign boot cleanup leaves no file" no_rule
installed; chmod 0777 "$root/etc/sudoers.d"
run_tty "a writable sudoers.d is refused" 1 grant
check "the refusal names the directory" out_has "vgs-sudo-grant: refused: untrusted=$root/etc/sudoers.d"
installed; printf 'Admin\n' >"$tmp/account"
run_tty "an account name sudoers would misread is refused" 1 grant
check "the refusal names the account" out_has "vgs-sudo-grant: refused: account=unsupported name=Admin"
check "a refused account leaves no file" no_rule
installed; touch "$tmp/sudo-old"
run "a sudo without -N is refused" 1 "vgs-sudo-grant: refused: sudo=no-update-unsupported" grant
check "a sudo without -N is asked nothing else" test "$(sudo_calls)" == "-h"

# A grant with no root half, or one that is not this helper, installs it
# first in the same terminal, then grants; the credential the install
# cached never answers the check that sudo honours the rule.
fresh
run_tty "a grant with no root half installs it first" 0 grant
check "the first grant placed the root half" cmp -s -- "$helper" "$installed"
check "the first grant placed the boot cleanup" cmp -s -- "$template" "$boot"
check "the first grant names what it places" out_has "  $installed  the part of passwordless sudo that runs as root"
check "the first grant's rule is published" test -e "$rule"
check "the first grant installs, then reads the listing" test "$(sed -n '3,5p' "$tmp/sudo.log")" == "install -m 0644 -o root -g root -T -- $template $boot
install -m 0755 -o root -g root -T -- $helper $installed
-n -l -l"
fresh; touch "$tmp/sudo-ignores"
run_tty "a first grant sudo does not honour is revoked" 1 grant
check "the install's credential does not answer the check" out_has "vgs-sudo-grant: refused: grant=not-effective revoke-exit=0"
check "the ineffective first grant leaves no file" no_rule
installed; printf '# changed\n' >>"$installed"
run "status reports a stale root half" 0 "" status
check "status names the stale root half" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=stale"
run_tty "a grant through a stale root half replaces it first" 0 grant
check "the stale root half is this helper again" cmp -s -- "$helper" "$installed"
check "the replaced root half's grant is published" test -e "$rule"

# A rule found: an expired one reads as no grant, and the root half removes
# it as found; one not of its form is reported and removed only by revoke.
installed
printf 'vgsuser ALL=(ALL) NOTAFTER=20000101000000Z NOPASSWD: ALL\n' >"$rule"
run "status with an expired rule" 0 "" status
check "an expired rule reads as inactive" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=current"
root "the root half reads an expired rule as inactive" 3 "" __status "$uid"
check "the root half removes an expired rule as found" test ! -e "$rule"
printf 'vgsuser ALL=(ALL) NOPASSWD: ALL\n' >"$rule"
run "status with a rule of another form fails" 1 "vgs-sudo-grant: refused: grant=malformed path=$rule" status
rm -f -- "$tmp/gum.log" "$tmp/gum-choose.log"
run_tty "a grant removes a rule of another form" 0 grant
check "a grant removes the other rule as it revokes a grant" test ! -e "$rule"
check "the grant that removes it asks nothing" test ! -e "$tmp/gum.log" -a ! -e "$tmp/gum-choose.log"
printf 'vgsuser ALL=(ALL) NOPASSWD: ALL\n' >"$rule"
run "revoke removes a rule of another form" 0 "" revoke
check "revoke reports the removal" test "$(cat "$tmp/out")" == "ok sudo-grant=revoked"
check "the other rule is gone" test ! -e "$rule"
printf 'vgsuser ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$rule"; chmod 0666 "$rule"
root "a rule others can write is not read as a grant" 1 "vgs-sudo-grant: refused: grant=malformed path=$rule" __status "$uid"
installed
printf 'other ALL=(ALL) NOPASSWD: ALL\n' >"$perm"
root "another account's rule in the indefinite name is not read as a grant" 1 "vgs-sudo-grant: refused: grant=malformed path=$perm" __status "$uid"
root "the root half enables nothing over it" 1 "vgs-sudo-grant: refused: grant=malformed path=$perm" __enable "$uid" 15
check "the root half wrote no timed rule beside it" test ! -e "$rule"

# The root half itself: its startup, its actions, its caller.
installed
root "the root half refuses the user's verbs" 1 "vgs-sudo-grant: refused: root=grant" grant
root "the root half refuses an action it does not know" 2 "vgs-sudo-grant: refused: argument=__expire count=2" __expire "$uid"
root "the root half refuses an extra argument" 2 "vgs-sudo-grant: refused: argument=__status count=3" __status "$uid" x
root "the root half refuses minutes past the bound" 2 "vgs-sudo-grant: refused: duration=1441" __enable "$uid" 1441
root "the root half refuses a duration it does not know" 2 "vgs-sudo-grant: refused: duration=forever" __enable "$uid" forever
root "the root half refuses a uid that is not a number" 2 "vgs-sudo-grant: refused: uid=x" __status x
root_caller=0
root "the root half refuses root's own uid" 2 "vgs-sudo-grant: refused: uid=0" __status 0
root_caller=4242
root "the root half refuses another user's uid" 1 "vgs-sudo-grant: refused: caller=mismatch uid=$uid sudo-uid=4242" __enable "$uid" 15
check "another user's enable writes no rule" no_rule
root_caller="$uid"
root "the root half answers its caller" 3 "" __status "$uid"
check "the root half prints inactive" test "$(cat "$tmp/out")" == inactive
unprivileged() {
  local status=0 err
  err="$("${row_env[@]}" "$unshare_bin" -r env SUDO_UID="$uid" "$BASH" "$installed" __status "$uid" 2>&1 >/dev/null </dev/null)" || status=$?
  test "${err%%$'\n'*} exit=$status" == "vgs-sudo-grant: refused: startup=unprivileged exit=2"
}
check "the root half refuses a bash started without -p" unprivileged

# uninstall revokes the user's grant, removes every account's timed grant
# through the boot cleanup's own line and every account's indefinite grant,
# then removes the root half and the boot cleanup.
other="$root/etc/sudoers.d/99-vgs-nopasswd-4242"
other_perm="$root/etc/sudoers.d/99-vgs-permanent-nopasswd-4242"
installed
run_tty "a grant before uninstall" 0 grant
printf 'other ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$other"
printf 'other ALL=(ALL) NOPASSWD: ALL\n' >"$other_perm"
rm -f -- "$tmp/sudo.log"
run "uninstall succeeds" 0 "" uninstall
check "uninstall drops the credential before it reaches the root half" test "$(sed -n 1,2p "$tmp/sudo.log")" == "-k
-- $installed __disable $uid"
check "uninstall reports it" test "$(tail -n 1 "$tmp/out")" == "ok sudo-grant=uninstalled"
check "uninstall revokes the grant" test ! -e "$rule"
check "uninstall runs the boot cleanup's line now" test "$(cat "$tmp/tmpfiles.log")" == "--remove --boot -- $boot"
check "uninstall removes another account's grant" test ! -e "$other"
check "uninstall removes another account's indefinite grant" test ! -e "$other_perm"
check "uninstall removes the root half and the boot cleanup" test ! -e "$installed" -a ! -e "$boot"
installed; printf 'Indefinitely\n' >"$tmp/gum-choice"
run_tty "an indefinite grant before uninstall" 0 grant
run "uninstall with an indefinite grant succeeds" 0 "" uninstall
check "uninstall revokes the indefinite grant" no_rule
installed
printf 'other ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$other"; printf '1\n' >"$tmp/tmpfiles-exit"
run "uninstall stops when the grants cannot be removed" 1 "vgs-sudo-grant: refused: uninstall=grants path=$boot" uninstall
check "a stopped uninstall keeps the root half and the boot cleanup" test -e "$installed" -a -e "$boot"

# Must-fail controls, each on a copy of the helper missing one rule, placed
# and installed as its own root half.
control() { # NAME NEEDLE REPLACEMENT
  local copy="$tmp/control-$1"
  check "the $1 control's text occurs once" test "$(python3 -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$source_file" "$2")" == 1
  python3 -c 'import sys; p, o, a, b = sys.argv[1:]; s = open(p).read(); open(o, "w").write(s.replace(a, b))' "$source_file" "$copy" "$2" "$3"
  check "the $1 mutant differs" test "$(cmp -s "$source_file" "$copy"; echo $?)" == 1
  place "$copy"
  installed
}
control nixos-write "  printf 'NixOS builds /etc from its configuration, so VGS writes no sudo rule here.\n'
  printf 'WARNING: until %s" "  : >\"\$(rule_path \"\$uid\")\"
  printf 'NixOS builds /etc from its configuration, so VGS writes no sudo rule here.\n'
  printf 'WARNING: until %s"
run_nixos_dirty "the nixos-write mutant grants" 0 "" grant
check "the nixos-write mutant changes the tree" tree_changed
check "the nixos-write mutant writes the rule path" test -e "$rule"
control nixos-blind 'if [[ $detected_system == nix ]]; then' 'if false; then'
run_nixos_dirty "the nixos-blind mutant reaches the normal status" 0 "" status
check "the nixos-blind mutant prints the normal status" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=current"
check "the nixos-blind mutant reaches sudo" test -e "$tmp/sudo.log"
control skip-visudo 'visudo -cqf "$enable_staged" >/dev/null ||' 'true ||'
printf '1\n' >"$tmp/visudo-exit"
run_tty "the skip-visudo mutant grants" 0 grant
check "the skip-visudo mutant publishes a rule visudo refused" test -e "$rule"
control wide-minutes '((10#$1 <= max_minutes))' '((10#$1 <= max_minutes + 1))'
root "the wide-minutes mutant's root half enables 1441 minutes" 0 "" __enable "$uid" 1441
check "the wide-minutes mutant publishes a 1441-minute rule" test -e "$rule"
control deadline-blind '[[ $deadline =~ ^[0-9]{14}Z$ ]] ||' 'true ||'
touch "$tmp/date-junk"
run_tty "the deadline-blind mutant's grant runs" 1 grant
check "the deadline-blind mutant publishes a malformed deadline" grep -qF "NOTAFTER=2026-01-01 " "$rule"
control caller-blind '[[ ${SUDO_UID:-} == "$1" ]] ||' 'true ||'
root_caller=4242
root "the caller-blind mutant enables for another user" 0 "" __enable "$uid" 15
root_caller="$uid"
control startup-blind '[[ $- == *p* ]] ||' 'true ||'
check "the startup-blind mutant runs under a plain bash" test "$(unprivileged; echo $?)" == 1
control unsanitized '  sanitize "$@"' '  :'
run_tty "the unsanitized mutant grants" 0 grant
check "the unsanitized mutant hands the caller's variable to visudo" grep -qxF VGS_PLANTED=1 "$tmp/visudo-env"
control boot-blind 'trusted "$tmpfiles_d" && trusted "$boot_file" && [[ $(boot_lines "$boot_file") == "$boot_rule" ]] ||' 'true ||'
rm -f -- "$boot"
root "the boot-blind mutant's root half enables with no boot cleanup" 0 "" __enable "$uid" 15
control boot-reinstall-blind '[[ $half != current ]] || ! cmp -s -- "$template" "$boot_file"' '[[ $half != current ]]'
rm -f -- "$boot"
run_tty "the boot-reinstall-blind mutant's grant fails with no boot cleanup" 1 grant
check "the boot-reinstall-blind mutant leaves the boot cleanup gone" test ! -e "$boot"
control malformed-kept 'if [[ $state == active || $state == malformed ]]; then' 'if [[ $state == active ]]; then'
printf 'vgsuser ALL=(ALL) NOPASSWD: ALL\n' >"$rule"
run_tty "the malformed-kept mutant's grant fails" 1 grant
check "the malformed-kept mutant keeps the other rule" test -e "$rule"
control mode-blind '(((8#${info#* } & 8#022) == 0))' 'true'
chmod 0777 "$root/etc/sudoers.d"
run_tty "the mode-blind mutant grants into a writable sudoers.d" 0 grant
control owner-blind '[[ $info == "0 "* ]] && ' ''
printf '%s\n' "$boot" >"$tmp/foreign"
run_tty "the owner-blind mutant grants with a foreign boot cleanup" 0 grant
control effect-blind 'if ! sudo -n -N -- /usr/bin/true' 'if false'
touch "$tmp/sudo-ignores"
run_tty "the effect-blind mutant reports an ineffective grant" 0 grant
control check-credential '  sudo -k || refuse 1 "sudo=reset-failed before=check"' '  true'
fresh; touch "$tmp/sudo-ignores"
run_tty "the check-credential mutant's install credential answers the check" 0 grant
control no-toggle 'if [[ $state == active || $state == malformed ]]; then' 'if false; then'
run_tty "the no-toggle mutant grants" 0 grant
rm -f -- "$tmp/gum.log"
run_tty "the no-toggle mutant fails the second run" 1 grant
check "the no-toggle mutant asks again instead of revoking" test -e "$tmp/gum.log"
control unattended "VGS_TUI_UNATTENDED='' vgs_tui_confirm" 'vgs_tui_confirm'
tty_env=(VGS_TUI_UNATTENDED=1)
run_tty "the unattended mutant grants" 0 grant
check "the unattended mutant asks nothing" test ! -e "$tmp/gum.log"
tty_env=()
control one-question '    confirm_grant "Passwordless sudo stays on after a restart, until you turn it off. Turn it on anyway?"
' ''
printf 'Indefinitely\n' >"$tmp/gum-choice"; printf '0\n1\n' >"$tmp/gum-answer"
run_tty "the one-question mutant grants indefinitely past a declined second question" 0 grant
check "the one-question mutant publishes the indefinite rule" test -e "$perm"
control preselect-blind '--selected "$(duration_label "$1")"' '--selected "15 minutes"'
printf '1\n' >"$tmp/gum-answer"
run_tty "the preselect-blind mutant asks grant 60, then is declined" 1 grant 60
check "the preselect-blind mutant's question starts elsewhere than 1 hour" test "$(grep -A1 -xF -- --selected "$tmp/gum-choose.log" | tail -n 1)" == "15 minutes"
control expiry-blind '[[ $now < $grant_deadline ]] && return 0' 'return 0'
printf 'vgsuser ALL=(ALL) NOTAFTER=20000101000000Z NOPASSWD: ALL\n' >"$rule"
root "the expiry-blind mutant's root half reads an expired rule" 0 "" __status "$uid"
check "the expiry-blind mutant reads an expired rule as active" test "$(cat "$tmp/out")" == "active deadline=20000101000000Z"
control listing-expiry-blind 'if [[ $now < $deadline ]]; then' 'if true; then'
printf 'vgsuser ALL=(ALL) NOTAFTER=20000101000000Z NOPASSWD: ALL\n' >"$rule"
run "the listing-expiry-blind mutant's status" 0 "" status
check "the listing-expiry-blind mutant reads an expired listing as active" grep -q "^sudo-grant=active until=2000-01-01T00:00:00Z" "$tmp/out"
control unnamed-blind "grep -q '^Sudoers entry: ' <<<\"\$listing\" ||" 'true ||'
printf 'vgsuser ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$rule"; touch "$tmp/sudo-unnamed"
run "the unnamed-blind mutant reads a listing that names no file" 0 "" status
check "the unnamed-blind mutant reads an active grant as inactive" test "$(cat "$tmp/out")" == "sudo-grant=inactive root-half=current"
control permanent-blind '[[ $contents == "$account ALL=(ALL) NOPASSWD: ALL" ]]' 'true'
printf 'other ALL=(ALL) NOPASSWD: ALL\n' >"$perm"
root "the permanent-blind mutant's root half reads another account's rule" 0 "" __status "$uid"
check "the permanent-blind mutant reads it as the caller's grant" test "$(cat "$tmp/out")" == "active indefinite"
control timed-over-indefinite '[[ $grant == none ]] || refuse 1 "grant=active $grant"' 'true || refuse 1 "grant=active $grant"'
run_tty "the timed-over-indefinite mutant grants" 0 grant
root "the timed-over-indefinite mutant enables an indefinite grant beside it" 0 "" __enable "$uid" indefinite
check "the timed-over-indefinite mutant holds both rules" test -e "$rule" -a -e "$perm"
control disable-one 'for file in "$(rule_path "$1")" "$(permanent_path "$1")"; do' 'for file in "$(rule_path "$1")"; do'
printf 'Indefinitely\n' >"$tmp/gum-choice"
run_tty "the disable-one mutant grants indefinitely" 0 grant
run "the disable-one mutant's revoke" 0 "" revoke
check "the disable-one mutant leaves the indefinite rule" test -e "$perm"
control inline-install-blind 'if [[ $half != current ]] || ! cmp -s -- "$template" "$boot_file"; then' 'if ! cmp -s -- "$template" "$boot_file"; then'
printf '# changed\n' >>"$installed"
run_tty "the inline-install-blind mutant grants through a stale root half" 0 grant
check "the inline-install-blind mutant keeps the stale root half" test "$(cmp -s -- "$helper" "$installed"; echo $?)" == 1
control no-update-blind "grep -Eq '^usage: sudo .*\[[^]]*N[^]]*\]' <<<\"\$help\" ||" 'true ||'
touch "$tmp/sudo-old"
run "the no-update-blind mutant reaches the root half" 0 "" revoke
control warm-sudo '  sudo -k || refuse 1 "sudo=reset-failed"
  trap' '  true
  trap'
run "the warm-sudo mutant's revoke" 0 "" revoke
check "the warm-sudo mutant keeps the cached credential" test "$(sed -n 2p "$tmp/sudo.log")" == "-N -- $installed __disable $uid"
control cold-uninstall '  sudo -k || refuse 1 "sudo=reset-failed before=uninstall"' '  true'
run "the cold-uninstall mutant uninstalls" 0 "" uninstall
check "the cold-uninstall mutant reaches the root half with the cached credential" test "$(sed -n 1p "$tmp/sudo.log")" == "-- $installed __disable $uid"
control grants-kept '    sudo systemd-tmpfiles --remove --boot -- "$boot_file" </dev/null ||' '    true ||'
printf 'other ALL=(ALL) NOTAFTER=29990101000000Z NOPASSWD: ALL\n' >"$other"
run "the grants-kept mutant uninstalls" 0 "" uninstall
check "the grants-kept mutant leaves another account's grant without its boot cleanup" test -e "$other" -a ! -e "$boot"
control indefinite-kept "  sudo find \"\$sudoers_d\" -maxdepth 1 -name '99-vgs-permanent-nopasswd-*' ! -type d -delete </dev/null ||" '  true ||'
printf 'other ALL=(ALL) NOPASSWD: ALL\n' >"$other_perm"
run "the indefinite-kept mutant uninstalls" 0 "" uninstall
check "the indefinite-kept mutant leaves another account's indefinite grant without its root half" test -e "$other_perm" -a ! -e "$installed"

rows_done "$suite"
