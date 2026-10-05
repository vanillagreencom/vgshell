#!/usr/bin/env bash
# Controls for the requirement reports of bin/vgshell: the offer `plugin add`
# ends with, `plugin requirements`, `doctor`, `plugin rescan` and the rescan
# `vgshell pkg run` asks a running shell for once its steps end. Plugins come
# from local bare repositories. Detection reads /etc/os-release, so every
# row runs under `unshare -rm` with an Arch os-release bound over it, and
# the managers it finds are stubs ahead of the host's PATH: pacman and paru
# record their argv, sudo records its own and runs the rest, and qs records
# each IPC call a lock file naming this suite's pid sends. No row reaches a
# real package manager, a real elevation command or a live shell. Without
# user namespaces or script(1) the suite exits 77.
#
# Each control runs a row against a copy of the tree with one rule removed
# from bin/vgshell, bin/vgshell-pkg or bin/vgshell-plugin-judge, and that row must
# fail.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
for tool in script unshare; do
  command -v "$tool" >/dev/null || { echo "test-vgshell-requirements: status=not-measured missing=$tool"; exit 77; }
done
if ! unshare -rm true 2>/dev/null; then
  echo "test-vgshell-requirements: status=not-measured missing=user-namespaces"
  exit 77
fi
script_bin="$(command -v script)"

# Stubs. Each writes one line per call to $LOG: its name, then each argument
# in brackets. pacman fails with 7 when its first argument is $STUB_FAIL.
stubs="$tmp/stubs"; mkdir -p "$stubs"
record='printf "%s" "${0##*/}" >>"$LOG"; for a; do printf " [%s]" "$a" >>"$LOG"; done; echo >>"$LOG"'
stub() { # NAME BODY
  printf '#!/bin/sh\n%s\n%s\n' "$record" "$2" >"$stubs/$1"
  chmod +x "$stubs/$1"
}
# sudo -k and the keepalive's -n take no command to run.
stub sudo 'case "$1" in -k) exit 0 ;; -n) shift ;; esac
exec "$@"'
stub pacman '[ "${STUB_FAIL:-}" != "$1" ] || exit 7'
stub paru ''
stub flatpak ''
stub nix ''
stub qs 'echo "ok scan=1"'
# systemctl answers the user manager's graphical-session.target for the
# doctor rows: $STUB_SESSION, `active` when unset; an empty value fails as
# a manager that does not answer.
printf '#!/bin/sh\n[ "$*" = "--user is-active graphical-session.target" ] || exit 64\nstate="${STUB_SESSION-active}"\n[ -n "$state" ] || exit 1\necho "$state"\n[ "$state" = active ]\n' >"$stubs/systemctl"
chmod +x "$stubs/systemctl"
# The qs the usage rows reach through $tmp, first on their PATH: it records
# its arguments in $STUB_ARGS and answers $STUB_REPLY.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"${STUB_ARGS:-/dev/null}"\nprintf "%%s\\n" "${STUB_REPLY:-ok}"\n' >"$tmp/qs"
chmod +x "$tmp/qs"

os_release="$tmp/os-release"; printf 'NAME="Arch Linux"\nID=arch\n' >"$os_release"
nixos_release="$tmp/os-release-nixos"; printf 'NAME=NixOS\nID=nixos\n' >"$nixos_release"
rt_live="$tmp/rt-live"; mkdir -p "$rt_live"; printf '%s\n' "$$" >"$rt_live/vgshell.lock"
log="$tmp/log"
# The doctor rows' PATH: the stubs, then only what bin/vgshell, the scan and
# the judge run, so the core's other commands are missing on every host.
tools="$tmp/tools"; mkdir -p "$tools"
for tool in bash readlink dirname python3; do
  found="$(command -v "$tool")" || { echo "test-vgshell-requirements: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$(readlink -f -- "$found")" "$tools/$tool"
done
ln -s -- "$node_bin" "$tools/node"

# req BIN MODE ANSWER CFG RT [VAR=VALUE...] -- ARGS: BIN with ARGS under the
# fixture os-release, with a fresh $LOG. MODE `plain` gives it /dev/null on
# stdin, stdout in $tmp/out and stderr in $tmp/err; `terminal` runs it on a
# pseudo-terminal script(1) opens with ANSWER typed, both streams in
# $tmp/out. REQ_PATH replaces the PATH after the stubs and REQ_OS_RELEASE
# the bound os-release. The exit status lands in $status.
req() {
  local bin="$1" mode="$2" answer="$3" cfg="$4" rt="$5" extra=() words
  shift 5
  while [[ $1 != -- ]]; do extra+=("$1"); shift; done
  shift
  : >"$log"
  words=("${base_env[@]}" PATH="$stubs:${REQ_PATH:-$base_path}" XDG_CONFIG_HOME="$cfg" XDG_RUNTIME_DIR="$rt" LOG="$log" "${extra[@]}")
  local bound=(unshare -rm sh -c 'mount --bind "$1" /etc/os-release && shift && exec "$@"' sh "${REQ_OS_RELEASE:-$os_release}")
  status=0
  : >"$tmp/err"
  if [[ $mode == plain ]]; then
    "${bound[@]}" "${words[@]}" "$bin" "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
  else
    "${bound[@]}" "${words[@]}" SHELL="$BASH" timeout 60 "$script_bin" -qec "$(printf '%q ' "$bin" "$@")" /dev/null <<<"$answer" >"$tmp/out" 2>&1 || status=$?
  fi
}
out_is() { [[ "$(cat -- "$tmp/out")" == "$1" ]] || { printf 'out: [%s]\nwant: [%s]\n' "$(cat -- "$tmp/out")" "$1" >"$tmp/why"; return 1; }; }
# A pseudo-terminal ends each line with a carriage return.
out_has() { tr -d '\r' <"$tmp/out" | grep -qxF -- "$1"; }
err_is() { [[ "$(cat -- "$tmp/err")" == "$1" ]]; }
log_is() { [[ "$(cat -- "$log")" == "$1" ]] || { printf 'log: [%s]\nwant: [%s]\n' "$(cat -- "$log")" "$1" >"$tmp/why"; return 1; }; }
log_has() { grep -qxF -- "$1" "$log"; }
lines() { printf '%s\n' "$@"; }
rescans() { grep -cxF "qs [ipc] [--pid] [$$] [call] [shell] [rescanPlugins]" "$log" || true; }

check "every command a row elevates, installs or reaches the shell with is a stub" \
  test "$("${base_env[@]}" PATH="$stubs:$base_path" sh -c 'for c in sudo pacman paru flatpak nix qs; do command -v "$c"; done')" == "$(lines "$stubs/sudo" "$stubs/pacman" "$stubs/paru" "$stubs/flatpak" "$stubs/nix" "$stubs/qs")"

# The fixture plugin: missing commands with a pacman package, an AUR-only
# package, no package, an optional one, one sharing another's package and
# one whose package name a shell would read as two commands, and git,
# which is present.
need() { # COMMAND PACKAGES PURPOSE [OPTIONAL]
  printf '{ "command": "%s", "packages": %s, "purpose": "%s"%s }' "$1" "$2" "$3" "${4:+, \"optional\": true}"
}
requirements="$(need vgs-need-one '{ "pacman": "need-one", "apt": "need-one-deb" }' First),
$(need vgs-need-two '{ "aur": "need-two" }' Second),
$(need vgs-need-bare '{}' "No package"),
$(need vgs-need-opt '{ "pacman": "need-opt" }' Optional yes),
$(need git '{ "pacman": "git" }' Present),
$(need vgs-need-dup '{ "pacman": "need-one" }' "Same package"),
$(need vgs-need-quote '{ "pacman": "need;one" }' Quoted)"
source_repo needs "$(manifest acme.needs 0.1.0 ", \"requirements\": [ $requirements ]")"
source_repo probe "$(manifest acme.probe 0.1.0)"
# A plugin whose owner-only extra, off by default, alone runs an optional
# command.
source_repo extras "$(manifest acme.extras 0.1.0 ", \"settings\": { \"photos\": false }, \"requirements\": [ $(need vgs-need-extra '{ "pacman": "need-extra" }' Extra yes) ], \"extras\": { \"photos\": { \"requirements\": [ \"vgs-need-extra\" ] } }")"
# On NixOS: a package for nix, which installs nothing through vgshell, beside
# one for the Flatpak overlay.
source_repo nixos "$(manifest acme.nixos 0.1.0 ", \"requirements\": [ $(need vgs-nix-one '{ "nix": "nix-one" }' Nix), $(need vgs-flat '{ "flatpak": "org.flat" }' Flat) ]")"

offer="$(lines \
  "requires vgs-need-one (need-one)" \
  "requires vgs-need-two (need-two)" \
  "requires vgs-need-bare" \
  "requires vgs-need-opt (need-opt) optional" \
  "requires vgs-need-dup (need-one)" \
  "requires vgs-need-quote (need;one)" \
  "install: vgshell pkg run install need-one need-opt need\\;one" \
  "install: vgshell pkg run install --manager aur need-two")"
report="$(lines \
  "missing vgs-need-one (need-one): First" \
  "missing vgs-need-two (need-two): Second" \
  "missing vgs-need-bare: No package" \
  "missing vgs-need-opt (need-opt) optional: Optional" \
  "present git (git): Present" \
  "missing vgs-need-dup (need-one): Same package" \
  "missing vgs-need-quote (need;one): Quoted")"

# Each row takes the vgshell it runs and a fresh configuration directory, and
# answers 0 when every expectation holds.
row_offer_no_terminal() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/needs.git"
  [[ $status == 0 ]] && err_is "" && log_is "" && out_is "$(lines "ok added=acme.needs path=$2/vgshell/plugins/acme.needs config=unchanged" "shell=not-running" "$offer")"
}
row_offer_declined() {
  req "$1" terminal n "$2" "$rt_empty" -- plugin add "$tmp/src/needs.git"
  [[ $status == 0 ]] && log_is "" && grep -qF "Install now? [y/N]" "$tmp/out" && out_has "install: vgshell pkg run install --manager aur need-two"
}
# y installs each manager's packages as argv, pacman's behind one sudo
# session and paru's with none. A running shell hears the landing as
# pluginInstalled with the new plugin's id, which rescans and raises its
# notice, and rescans after each install.
row_offer_accepted() {
  req "$1" terminal y "$2" "$rt_live" -- plugin add "$tmp/src/needs.git"
  [[ $status == 0 ]] && log_has "sudo [pacman] [-S] [--needed] [--] [need-one] [need-opt] [need;one]" \
    && log_has "pacman [-S] [--needed] [--] [need-one] [need-opt] [need;one]" \
    && log_has "paru [-S] [--needed] [--] [need-two]" && [[ $(rescans) == 2 ]] \
    && [[ $(grep -cxF "qs [ipc] [--pid] [$$] [call] [shell] [pluginInstalled] [acme.needs]" "$log") == 1 ]]
}
row_offer_silent() {
  req "$1" terminal y "$2" "$rt_empty" -- plugin add "$tmp/src/probe.git"
  [[ $status == 0 ]] && log_is "" && ! grep -qF "Install now?" "$tmp/out"
}
row_install_failure() {
  req "$1" terminal y "$2" "$rt_empty" STUB_FAIL=-S -- plugin add "$tmp/src/needs.git"
  [[ $status == 7 ]] && log_has "pacman [-S] [--needed] [--] [need-one] [need-opt] [need;one]" && ! grep -q "^paru " "$log"
}
row_nix_by_hand() {
  REQ_OS_RELEASE="$nixos_release" req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/nixos.git"
  [[ $status == 0 ]] && err_is "" && log_is "" && out_is "$(lines "ok added=acme.nixos path=$2/vgshell/plugins/acme.nixos config=unchanged" "shell=not-running" \
    "requires vgs-nix-one (nix-one)" "requires vgs-flat (org.flat)" "by-hand nix nix-one" "install: vgshell pkg run install --manager flatpak org.flat")" || return 1
  rm -rf -- "${2:?}/vgshell/plugins/acme.nixos"
  REQ_OS_RELEASE="$nixos_release" req "$1" terminal y "$2" "$rt_empty" -- plugin add "$tmp/src/nixos.git"
  [[ $status == 0 ]] && log_is "flatpak [install] [org.flat]"
}
row_run_rescans() {
  req "$1" terminal "" "$2" "$rt_live" -- pkg run install --manager pacman foo
  [[ $status == 0 && $(rescans) == 1 ]] && grep -qF "shell=rescan-started" "$tmp/out"
}
row_failed_run_rescans() {
  req "$1" terminal "" "$2" "$rt_live" STUB_FAIL=-S -- pkg run install --manager pacman foo
  [[ $status == 7 && $(rescans) == 1 ]]
}
row_refused_run_leaves_shell() {
  req "$1" plain "" "$2" "$rt_live" VGSHELL_RUNNER_PID=4242 -- pkg run install --manager pacman foo
  [[ $status == 1 && $(rescans) == 0 ]]
}
row_requirements() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/needs.git"
  req "$1" plain "" "$2" "$rt_empty" -- plugin requirements acme.needs
  [[ $status == 0 ]] && err_is "" && out_is "$report"
}
row_requirements_json() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/needs.git"
  req "$1" plain "" "$2" "$rt_empty" -- plugin requirements --json acme.needs
  [[ $status == 0 ]] && json_is "$tmp/out" 'd[0] == {"command": "vgs-need-one", "packages": {"pacman": "need-one", "apt": "need-one-deb"}, "optional": False, "purpose": "First", "state": "missing", "package": {"manager": "pacman", "name": "need-one"}} and d[1]["package"] == {"manager": "aur", "name": "need-two"} and d[2]["package"] is None and d[4]["state"] == "present" and len(d) == 7'
}
# A plugin add lands disabled is left out; enabled, it is reported beside
# the core, whose commands this PATH lacks apart from node and python3.
row_doctor() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/needs.git"
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" '"acme.needs" not in d["plugins"]' || return 1
  printf '{ "version": 1, "plugins": [ { "id": "acme.needs" } ] }\n' >"$2/vgshell/shell.json"
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" '[r["state"] for r in d["plugins"]["acme.needs"]] == ["missing"] * 7 and {r["command"]: r["state"] for r in d["core"]}["node"] == "present" and {r["command"]: r["state"] for r in d["core"]}["git"] == "missing" and {r["command"]: r["package"] for r in d["core"]}["python3"] == {"manager": "pacman", "name": "python"}' || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" -- doctor
  [[ $status == 0 ]] && err_is "" && out_has "acme.needs missing vgs-need-two (need-two): Second" \
    && out_has "acme.needs missing git (git): Present" && grep -qx "core present node (nodejs): .*" "$tmp/out" \
    && grep -qx "core missing git (git): .*" "$tmp/out" && grep -qx "core missing gum (gum): .*" "$tmp/out"
}
# The session line: a hand-started session, graphical-session.target
# inactive, reads as a missing uwsm-managed session that names what breaks
# and the entry to log in with; a managed one reads as met. Each form is
# matched as a whole line, in the text and the JSON form.
row_doctor_session() {
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" STUB_SESSION=inactive -- doctor
  [[ $status == 0 ]] && out_has 'session missing uwsm-managed: the systemd user manager has no XDG_SESSION_TYPE and graphical-session.target stays inactive, so user services that want it never start; log out and log in with "Hyprland (uwsm-managed)"' || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" STUB_SESSION=inactive -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" 'd["session"] == {"graphicalSession": "inactive"}' || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" STUB_SESSION=active -- doctor
  [[ $status == 0 ]] && out_has "session present uwsm-managed: user services get the session's WAYLAND_DISPLAY and graphical-session.target" || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" STUB_SESSION= -- doctor
  [[ $status == 0 ]] && out_has "session unknown uwsm-managed: the systemd user manager did not answer" || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" STUB_SESSION= -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" 'd["session"] == {"graphicalSession": "unknown"}'
}
# An extra that is off leaves its command out of add's offer, the plugin's
# report and doctor; the user's plugins row turning it on brings it back.
row_extra_off() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/extras.git"
  [[ $status == 0 ]] && err_is "" && out_is "$(lines "ok added=acme.extras path=$2/vgshell/plugins/acme.extras config=unchanged" "shell=not-running")" || return 1
  req "$1" plain "" "$2" "$rt_empty" -- plugin requirements acme.extras
  [[ $status == 0 ]] && err_is "" && out_is "" || return 1
  printf '{ "version": 1, "plugins": [ { "id": "acme.extras" } ] }\n' >"$2/vgshell/shell.json"
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" 'd["plugins"]["acme.extras"] == []'
}
row_extra_on() {
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/extras.git"
  printf '{ "version": 1, "plugins": [ { "id": "acme.extras", "photos": true } ] }\n' >"$2/vgshell/shell.json"
  req "$1" plain "" "$2" "$rt_empty" -- plugin requirements acme.extras
  [[ $status == 0 ]] && err_is "" && out_is "missing vgs-need-extra (need-extra) optional: Extra" || return 1
  REQ_PATH="$tools" req "$1" plain "" "$2" "$rt_empty" -- doctor --json
  [[ $status == 0 ]] && json_is "$tmp/out" '[r["command"] for r in d["plugins"]["acme.extras"]] == ["vgs-need-extra"]' || return 1
  rm -rf -- "${2:?}/vgshell/plugins/acme.extras"
  req "$1" plain "" "$2" "$rt_empty" -- plugin add "$tmp/src/extras.git"
  [[ $status == 0 ]] && out_has "requires vgs-need-extra (need-extra) optional"
}

# rows: label | function. Each runs against the tree under test with a
# configuration directory of its own.
declare -a ROWS=(
  "add without a terminal prints each missing command and the install commands|row_offer_no_terminal"
  "add declined on a terminal installs nothing|row_offer_declined"
  "add accepted on a terminal installs each manager's packages and rescans|row_offer_accepted"
  "add of a plugin that requires nothing asks nothing|row_offer_silent"
  "a failed install ends add with its status|row_install_failure"
  "nix's packages are named for its own configuration, and the overlay's installed|row_nix_by_hand"
  "a run asks a running shell to rescan|row_run_rescans"
  "a failed run still asks for the rescan|row_failed_run_rescans"
  "a refused run asks for no rescan|row_refused_run_leaves_shell"
  "plugin requirements names each requirement's state and package|row_requirements"
  "plugin requirements --json carries the package pick|row_requirements_json"
  "doctor reports the core and the enabled plugins only|row_doctor"
  "doctor says whether the session is uwsm-managed|row_doctor_session"
  "an extra that is off leaves its commands out of every report|row_extra_off"
  "an extra the user turns on reports its commands|row_extra_on"
)
config_count=0
# run_row FN BIN: row FN through BIN with a configuration directory of its
# own.
run_row() {
  config_count=$((config_count + 1))
  rm -f -- "$tmp/why"
  "$1" "$2" "$tmp/cfg-$config_count"
}
row_fns=" "
for row in "${ROWS[@]}"; do
  IFS='|' read -r name fn <<<"$row"
  row_fns+="$fn "
  if run_row "$fn" "$repo/bin/vgshell"; then ok "$name"; else fail "$name: exit=$status $(cat -- "$tmp/why" 2>/dev/null || true)"; fi
done

# The usage rows need no fixture.
inst "plugin requirements refuses an id no plugin has" "$tmp/cfg-usage" "$rt_empty" 1 "" "vgshell: refused: unknown=acme.absent" plugin requirements acme.absent
inst "plugin requirements without an id is exit 2" "$tmp/cfg-usage" "$rt_empty" 2 "" "vgshell: refused: id=missing" plugin requirements
inst "plugin requirements refuses a second argument" "$tmp/cfg-usage" "$rt_empty" 2 "" "vgshell: refused: argument=more" plugin requirements acme.absent more
inst "doctor refuses an argument" "$tmp/cfg-usage" "$rt_empty" 2 "" "vgshell: refused: argument=more" doctor more
inst "plugin rescan with no shell says so" "$tmp/cfg-usage" "$rt_empty" 0 "shell=not-running" "" plugin rescan
INST_REPLY="ok scan=1" inst "plugin rescan asks a running shell" "$tmp/cfg-usage" "$rt_live" 0 "shell=rescan-started" "" plugin rescan
check "the rescan names the shell's pid from the lock file" test "$(cat "$tmp/args")" == "ipc --pid $$ call shell rescanPlugins"
mkdir -p "$tmp/cfg-bad/vgshell"; printf '{ "version": 1, "plugins": [ "junk" ] }\n' >"$tmp/cfg-bad/vgshell/shell.json"
inst "doctor refuses a user file the config judge refuses" "$tmp/cfg-bad" "$rt_empty" 1 "" "vgshell: refused: user-config=malformed path=$tmp/cfg-bad/vgshell/shell.json error=plugins.0 must be an object with a string id" doctor

# controls: label, the file under bin/, its text and the replacement, and
# the function of the row the rule serves, one control per five entries.
# The copy replaces that file in a tree of its own, and that row must fail
# against it.
declare -a CONTROLS=(
  "add reports the missing requirements" vgshell '  offer_requirements "$id"' '' row_offer_no_terminal
  "add asks only on a terminal" vgshell '  [[ -t 0 ]] || return 0' '' row_offer_no_terminal
  "add installs only on yes" vgshell '    *) return 0 ;;' '    *) ;;' row_offer_declined
  "a run asks for the rescan" vgshell-pkg '            rescanShell();' '' row_run_rescans
  "doctor reports enabled plugins only" vgshell-plugin-judge '.filter(id => logic.isEnabled(effective, plugins.get(id).manifest, defaultBarId))' '' row_doctor
  "the core's commands are looked up on PATH" vgshell-plugin-judge '.filter(command => !onPath(command))' '.filter(command => false)' row_doctor
  "a row carries this system's package" vgshell-plugin-judge '{ package: logic.PackageManagers.packageFor(row.packages, found) }' '{ package: null }' row_requirements_json
  "nix gets no install command" vgshell-plugin-judge 'lines.push(group.installs ? ' 'lines.push(true ? ' row_nix_by_hand
  "add tells the shell which plugin it installed" vgshell '  rescan_if_running pluginInstalled "$id"' '  rescan_if_running rescanPlugins' row_offer_accepted
  "plugin requirements skips an extra that is off" vgshell-plugin-judge 'const requirements = activeManifest(config, plugin.manifest).requirements;' 'const requirements = plugin.manifest.requirements;' row_extra_off
  "add skips an extra that is off" vgshell-plugin-judge 'logic.requirementRows(activeManifest(config, plugin.manifest), plugin.missing)' 'logic.requirementRows(plugin.manifest, plugin.missing)' row_extra_off
  "doctor reads an inactive graphical session" vgshell '    inactive|failed) echo inactive ;;' '    inactive|failed) echo active ;;' row_doctor_session
  "the session line names the uwsm-managed entry" vgshell-plugin-judge 'log out and log in with \"Hyprland (uwsm-managed)\"' 'log out and log in again' row_doctor_session
  "the managed session reads as met" vgshell-plugin-judge 'active: "session present uwsm-managed:' 'active: "session unknown uwsm-managed:' row_doctor_session
  "doctor's JSON carries the session" vgshell-plugin-judge 'if (json) process.stdout.write(JSON.stringify(report) + "\n");' 'if (json) process.stdout.write(JSON.stringify({ ...report, session: { graphicalSession: "active" } }) + "\n");' row_doctor_session
  "doctor skips an extra that is off" vgshell-plugin-judge 'report.plugins[id] = reportRows(activeManifest(effective, plugins.get(id).manifest).requirements' 'report.plugins[id] = reportRows(plugins.get(id).manifest.requirements' row_extra_off
  "plugin requirements reads the user's settings" vgshell 'node "$judge" requirements "$format" "$root/config/shell.json" "$config_home/vgshell/shell.json"' 'node "$judge" requirements "$format" "$root/config/shell.json" "$config_home/vgshell/none.json"' row_extra_on
  "add reads the user's settings" vgshell 'node "$judge" unmet "$root/config/shell.json" "$config_home/vgshell/shell.json"' 'node "$judge" unmet "$root/config/shell.json" "$config_home/vgshell/none.json"' row_extra_on
)
for ((i = 0; i < ${#CONTROLS[@]}; i += 5)); do
  label="${CONTROLS[i]}" file="${CONTROLS[i + 1]}" fn="${CONTROLS[i + 4]}"
  [[ $row_fns == *" $fn "* ]] || { echo "test-vgshell-requirements: control=$((i / 5)) row=unknown value=[$fn]" >&2; exit 1; }
  copy_with "control-$((i / 5))" "$repo/bin/$file" "${CONTROLS[i + 2]}" "${CONTROLS[i + 3]}"
  tree="$tmp/tree-$((i / 5))"; mkdir -p "$tree/bin"
  cp -R -- "$repo/bin/." "$tree/bin/"
  cp -- "$copy" "$tree/bin/$file"
  for sibling in shell config; do ln -s -- "$repo/$sibling" "$tree/$sibling"; done
  if run_row "$fn" "$tree/bin/vgshell"; then fail "control: $label: $fn passes without the rule"; else ok "control: $fn fails without the rule: $label"; fi
done

# A fake installed prefix exposes commands only when the Arch dependency
# list installs their declared package. Real doctor code reads that PATH.
# No command stub starts a service, device probe, or authentication.
packaged="$tmp/packaged"
mkdir -p "$packaged"
cp -R -- "$repo/bin" "$repo/config" "$repo/shell" "$packaged/"
cp -- "$repo/packaging/arch/vgshell/.SRCINFO" "$packaged/dependencies"
provider_path() { # DEPENDENCY_FILE PATH_DIR
  mkdir -p "$2"
  python3 - "$packaged" "$1" "$2" <<'PY'
import json, pathlib, re, sys
root, dependency_file, farm = map(pathlib.Path, sys.argv[1:])
packages = {re.split(r"[<>=]", line.split(" = ", 1)[1])[0]
            for line in dependency_file.read_text().splitlines() if line.startswith("\tdepends = ")}
assert packages, "package dependency extractor is empty"
rows = json.loads((root / "config/requirements.json").read_text())
for manifest in sorted((root / "shell/plugins").glob("*/manifest.json")):
    rows += json.loads(manifest.read_text()).get("requirements", [])
for row in rows:
    package = row.get("packages", {}).get("pacman", row.get("packages", {}).get("aur"))
    command = row["command"]
    if package in packages and command not in {"node", "python3", "bash", "readlink", "systemctl"}:
        file = farm / command
        file.write_text("#!/bin/sh\nexit 0\n")
        file.chmod(0o755)
PY
}
provider_path "$packaged/dependencies" "$tmp/package-path"
REQ_PATH="$tmp/package-path:$tools" req "$packaged/bin/vgshell" plain "" "$tmp/packaged-config" "$rt_empty" -- doctor --json
check "an installed package's providers leave doctor with no missing required program" \
  test "$status" = 0
check "doctor reads all shipped required providers from the package list" json_is "$tmp/out" \
  '"vgs.capture" in d["plugins"] and "vgs.jarvis" in d["plugins"] and all(r["state"] == "present" for rows in [d["core"], *d["plugins"].values()] for r in rows if not r["optional"])'
provider_controls=(
  "tesseract|vgs.capture|tesseract"
  "pipewire-audio|vgs.jarvis|pw-record,pw-cat"
)
for row in "${provider_controls[@]}"; do
  IFS='|' read -r package owner commands <<<"$row"
  python3 - "$packaged/dependencies" "$packaged/missing-dependency" "$package" <<'PYCONTROL'
import pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:3])
text = source.read_text()
line = "\tdepends = " + sys.argv[3] + "\n"
assert text.count(line) == 1, "dependency removal must match exactly one row"
target.write_text(text.replace(line, ""))
PYCONTROL
  provider_path "$packaged/missing-dependency" "$tmp/package-path-control-$package"
  REQ_PATH="$tmp/package-path-control-$package:$tools" req "$packaged/bin/vgshell" plain "" "$tmp/packaged-config" "$rt_empty" -- doctor --json
  check "control: removing $package makes real doctor report $commands missing" \
    test "$status" = 0
  check "the missing package removes exactly its required command providers" json_is "$tmp/out" \
    "set('$commands'.split(',')) == {r['command'] for r in d['plugins']['$owner'] if r['state'] == 'missing' and not r['optional']}"
done

rows_done test-vgshell-requirements
