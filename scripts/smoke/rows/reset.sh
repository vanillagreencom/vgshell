# `vgshell reset` and its restore, end to end in the sandbox's own home.
# The row starts a copy of the sandbox's tree, tree-reset, since a reset
# restarts the shell from the tree it runs from and the shell after a reset
# runs the shipped plugin set: the copy's vgs.updates check is a stand-in
# that lists nothing, and devtools_stand_ins answers vgs.devtools, so that
# set reaches no host package manager and no network, as start-order.sh's
# default set does. It plants a user layer with a custom bar entry, the
# installed fixture acme.tick and a disabled vgs.launcher, and a custom
# theme file; welcome-seen is present, the consent row having answered the
# welcome. Every directory the reset acts on is checked to lie under the
# sandbox before the first ask.
#
# `vgshell reset` with no terminal and no --yes asks the running shell,
# which draws the reset question as the restart notice is drawn: Cancel,
# which holds the keyboard, Reset, and `vgshell reset --yes` behind Show
# command. Escape closes it and nothing moves: the control. The Settings
# window's Reset VGS button asks again; Reset, pressed only on the
# sandbox's own shell, brings a new shell over what a fresh install has:
# the backup holds the planted files, the shipped set runs with no user
# plugin and vgs.launcher enabled, the theme is the default, the welcome is
# unseen and the "VGS was reset" notice offers Restore previous settings,
# Keep these holding the keyboard, its command behind Show command.
# Hyprland lists no config error. Escape hides that notice and keeps its
# marker, so the shell `vgshell restart` brings next offers the restore
# again. Restore previous settings, pressed while another theme command
# holds the theme lock, as the follow after that shell's first scan can,
# waits on that lock and brings another
# new shell over the planted files, the theme file byte for byte: the user
# layer is in effect, the welcome is seen, no notice shows and Hyprland
# lists no config error. The row then puts back the user file and theme
# file it found, removes the backups and starts the sandbox's own tree
# again. Every key goes through one virtual keyboard with the us layout,
# the harness's keyboard helper, that lives through every restart: a shell
# that had just started read a key wtype typed with the keymap of the
# keyboard before it, its Return as Escape, so Escape hid the notice in
# place of Restore previous settings, in 1 of 4 runs of this row on host
# cachy on 2026-10-06.
# inputs: bin/vgshell bin/vgshell-theme-judge shell/shell.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Core/Capabilities.qml shell/Core/HyprlandLayer.qml shell/plugins/vgs.settings/* shell/plugins/vgs.updates/bin/check config/shell.json themes/vgs/theme.json scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/keyboard/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
reset_tree="$sandbox/tree-reset"
reset_config="$home/.config/vgshell"
reset_state="$home/.local/state/vgshell"
reset_data="$home/.local/share/vgshell"
reset_user="$reset_config/shell.json"
reset_theme="$reset_config/theme.json"
reset_marker="$reset_state/reset-backup"
reset_theme_lock="$reset_config/theme.lock"
reset_hold="$sandbox/reset-hold"
reset_keyboard_log="$sandbox/reset-keyboard.log"
reset_keyboard_fifo="$sandbox/reset-keyboard.fifo"
reset_keyboard_pid=""
reset_syncs=0
reset_saved="$sandbox/reset-saved"
mkdir -p -- "$reset_saved"

# `contained` when every directory the reset acts on, as the shell's
# environment names it, lies under the sandbox, and its runtime directory
# is the sandbox's own.
reset_contained() {
  local word
  for word in "${shell_env[@]}"; do
    case "$word" in
      HOME=* | XDG_CONFIG_HOME=* | XDG_STATE_HOME=* | XDG_DATA_HOME=* | XDG_CACHE_HOME=*)
        [[ ${word#*=} == "$sandbox/"* ]] || { echo "outside: $word"; return; }
        ;;
      XDG_RUNTIME_DIR=*)
        [[ ${word#*=} == "$rt_dir" ]] || { echo "outside: $word"; return; }
        ;;
    esac
  done
  echo contained
}
reset_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["reset"]))'; }
reset_welcome() { ipc shell lent | py_reply 'import json,sys; print(json.load(sys.stdin)["notices"]["welcome"]["state"])'; }
reset_drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]))' "$1"; }
reset_file() { [[ -e $1 ]] && echo present || echo absent; }
# The row's keyboard: started once, its first key a lone Shift, which
# answers nothing under any keymap. Returns 1, with the row failed, when it
# does not connect.
reset_keyboard_start() {
  mkfifo -- "$reset_keyboard_fifo"
  exec {reset_keyboard_fd}<>"$reset_keyboard_fifo"
  spawn "$reset_keyboard_log" "${shell_env[@]}" "$sandbox/keyboard" "$reset_keyboard_fifo" us ""
  reset_keyboard_pid="$spawn_pid"
  expect_poll "the row's keyboard connects to the nested seat" 1 log_lines '^ready$' "$reset_keyboard_log"
  grep -qxF ready -- "$reset_keyboard_log" || return 1
  reset_send "down 50" "up 50"
}
# reset_send COMMAND...: the keyboard's commands, `down CODE` and `up CODE`
# with XKB codes, then the wait for its round trip after them. Returns 1
# when that round trip does not come within 5 s.
reset_send() {
  [[ -n $reset_keyboard_pid ]] || return 1
  printf '%s\n' "$@" sync >&"$reset_keyboard_fd" || return 1
  reset_syncs=$((reset_syncs + 1))
  for _ in $(seq 1 50); do
    (($(grep -cxF sync -- "$reset_keyboard_log") >= reset_syncs)) && return 0
    sleep 0.1
  done
  return 1
}
reset_keyboard_stop() {
  [[ -n $reset_keyboard_pid ]] || return 0
  printf 'quit\n' >&"$reset_keyboard_fd" || :
  exec {reset_keyboard_fd}>&-
  wait "$reset_keyboard_pid" || fail "the row's keyboard exited with status $?"
  reset_keyboard_pid=""
}
# Holds the theme lock as another theme command does and prints `held`,
# then releases it once another process waits on it, printing `waited`, or
# after timeout_s, printing `none`. The waiter is a flock(1) with the lock
# file open and no -n: while this holds the lock it cannot have taken it.
# /proc/locks cannot tell: read from this row on host cachy on 2026-10-06,
# it listed neither this hold nor the restore's waiting request.
reset_hold_theme_lock() {
  local fd lock_path proc comm arg link blocking
  exec {fd}>>"$reset_theme_lock"
  flock -n "$fd" || { echo busy; return 0; }
  lock_path="$(realpath -e -- "$reset_theme_lock")"
  echo held
  for _ in $(seq 1 $((timeout_s * 5))); do
    for proc in /proc/[0-9]*; do
      { IFS= read -r comm <"$proc/comm"; } 2>/dev/null || continue
      [[ $comm == flock ]] || continue
      blocking=true
      while IFS= read -r -d '' arg; do [[ $arg != -n ]] || blocking=false; done <"$proc/cmdline" 2>/dev/null || continue
      [[ $blocking == true ]] || continue
      for link in "$proc"/fd/*; do
        if [[ $(readlink -- "$link" 2>/dev/null) == "$lock_path" ]]; then
          echo waited
          return 0
        fi
      done
    done
    sleep 0.2
  done
  echo none
}
reset_hold_first() { head -n 1 -- "$reset_hold"; }
reset_hold_last() { tail -n 1 -- "$reset_hold"; }
reset_same() { cmp -s -- "$1" "$2" && echo same || echo differs; }
# The live pid the sandbox's lock names once it is no longer OLD_PID, else
# `none`.
reset_relaunched() { # OLD_PID
  local pid
  if IFS= read -r pid 2>/dev/null <"$rt_dir/vgshell.lock" && [[ $pid =~ ^[0-9]+$ && $pid != "$1" && -d /proc/$pid ]]; then echo "$pid"; else echo none; fi
}
# `sandboxed` when the shell the row addresses has the sandbox's runtime
# directory in its environment and is the pid the sandbox's lock names.
reset_sandboxed() {
  local held
  grep -q -z -x -F -e "XDG_RUNTIME_DIR=$rt_dir" -- "/proc/$shell_qs_pid/environ" || { echo "runtime-dir=other"; return; }
  IFS= read -r held <"$rt_dir/vgshell.lock" || held=""
  if [[ $held == "$shell_qs_pid" ]]; then echo sandboxed; else echo "lock=[$held] shell=$shell_qs_pid"; fi
}
# reset_press LABEL: Return on the notice's action LABEL once the shell is
# the sandbox's own, then the new shell taken up as reset_adopt does.
# Returns 1, with the row failed, when no new shell answers.
reset_press() { # LABEL
  local old="$shell_qs_pid" where
  where="$(reset_sandboxed)" || where=unreadable
  if [[ $where != sandboxed ]]; then
    fail "$1 is not pressed: $where"
    return 1
  fi
  expect_poll "$1 holds the keyboard" "\"$1\"" reset_drawn focused
  reset_send "down 36" "up 36" || { fail "sending Return to $1 failed"; return 1; }
  reset_adopt "$old" "$1"
}
# reset_adopt OLD_PID LABEL: the shell that replaced OLD_PID, taken up as
# start_shell takes one: its runner's process group joins the teardown's,
# as in rows/core-drift.sh. Returns 1, with the row failed, when no new
# shell answers.
reset_adopt() { # OLD_PID LABEL
  local old="$1" new=none runner pgid
  shift
  for _ in $(seq 1 $((timeout_s * 5))); do
    new="$(reset_relaunched "$old")"
    [[ $new == none ]] || break
    sleep 0.2
  done
  if [[ $new == none ]]; then
    fail "$1 brought no new shell within ${timeout_s}s: the lock names [$(cat -- "$rt_dir/vgshell.lock" 2>/dev/null)]"
    return 1
  fi
  ok "$1 brought a new shell: pid=$new replaced pid=$old"
  runner="$(awk '$1 == "PPid:" { print $2 }' "/proc/$new/status")" || runner=""
  if [[ $runner =~ ^[0-9]+$ ]] && pgid="$(ps -o pgid= -p "$runner")"; then pgids+=("${pgid// /}"); else fail "the new shell's runner is unreadable: [$runner]"; fi
  shell_pid="$runner"
  shell_answers "$reset_tree" "$shell_log"
}
# `true` once `vgshell restart` of the reset tree brought a shell other
# than OLD_PID, stdin closed; else what it printed.
reset_restart() { # OLD_PID
  local out
  out="$("${shell_env[@]}" "$reset_tree/bin/vgshell" restart </dev/null 2>&1)" || { echo "exit: $out"; return 0; }
  [[ $out =~ ^ok\ pid=([0-9]+)$ && ${BASH_REMATCH[1]} != "$1" ]] && echo true || echo "$out"
}
# `vgshell reset` from no terminal, stdin closed, as a key bind runs it.
reset_ask() { "${shell_env[@]}" "$reset_tree/bin/vgshell" reset </dev/null; }
reset_button() { ipc smoke windowGeometry window vgs.settings Button "$1" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
# The fixture's bar widget is in every bar, `[true]`, or in none, `[false]`.
reset_tick_in_bars() { bar_widget_ids | py_reply 'import json,sys; print(json.dumps(sorted(set("acme.tick" in ids for ids in json.load(sys.stdin)))))'; }
# What the user file holds of the planted layer: acme.tick anywhere in it,
# and vgs.launcher among the disabled plugins.
reset_layer() {
  [[ -e $reset_user ]] || { echo '{"tick": false, "launcherOff": false}'; return; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"tick": "acme.tick" in json.dumps(d), "launcherOff": "vgs.launcher" in d.get("disabledPlugins", [])}))' "$reset_user"
}

reset_run_row() {
  local file name reset_folder reset_where reset_old reset_back reset_themed reset_holder=""
  # What the row puts back at its end: the user file, the theme file and the
  # stand-ins the shim held.
  for file in "$reset_user" "$reset_theme"; do
    if [[ -e $file ]]; then cp -p -- "$file" "$reset_saved/${file##*/}"; fi
  done
  reset_shim_names=(mise docker podman pacman)
  mkdir -p -- "$reset_saved/shim"
  for name in "${reset_shim_names[@]}"; do
    if [[ -e $shim/$name ]]; then cp -p -- "$shim/$name" "$reset_saved/shim/$name"; fi
  done

  copy_tree reset
  printf '%s\n' '#!/usr/bin/env bash' \
    '# The reset row'"'"'s stand-in: a check that ran now and listed nothing.' \
    'state="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/updates"' \
    'mkdir -p -- "$state"' \
    'printf '"'"'{"checkedAt":%s,"sources":[]}\n'"'"' "$(( $(date +%s%N) / 1000000 ))" | tee -- "$state/status.json"' \
    >"$reset_tree/shell/plugins/vgs.updates/bin/check"
  chmod 755 "$reset_tree/shell/plugins/vgs.updates/bin/check"

  # The planted user layer and theme file.
  if [[ ! -d $reset_config/plugins/acme.tick ]]; then
    mkdir -p -- "$reset_config/plugins/acme.tick"
    cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.tick/." "$reset_config/plugins/acme.tick/"
  fi
  default_set_prepare '["acme.tick"]' '["vgs.launcher"]'
  python3 - "$reset_user" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["bar"] = {"id": "vgs.bar", "layout": {"left": [{"id": "acme.tick", "format": "HH:mm"}], "center": [], "right": [{"id": "vgs.settings"}]}}
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
  printf '%s\n' '{ "schemaVersion": 1, "name": "reset-probe", "tokens": { "palette": { "foreground": "#123456" } } }' >"$reset_theme.tmp"
  mv -T -- "$reset_theme.tmp" "$reset_theme"
  cp -p -- "$reset_theme" "$reset_saved/planted-theme.json"
  rm -rf -- "${reset_data:?}/backups"
  rm -f -- "${reset_marker:?}"

  if stop_shell && start_shell "$reset_tree" "$sandbox/reset-qs.log" && reset_keyboard_start; then
    expect "the planted shell draws the custom theme" reset-probe ipc smoke themeName
    expect_poll "the planted layer puts the fixture's widget in the bar" '[true]' reset_tick_in_bars
    expect "the planted layer turns vgs.launcher off" False plugin_enabled vgs.launcher
    expect "welcome-seen is present before the reset" present reset_file "$reset_state/welcome-seen"

    # The terminal-less ask, and its control: Escape moves nothing.
    # Taken once the planted shell has settled, since its first presence may
    # rewrite the user file at start.
    cp -p -- "$reset_user" "$reset_saved/planted-shell.json"
    reset_themed="$(reset_file "$reset_state/theme.name")"
    expect "reset with no terminal and no --yes asks the running shell" shell=asked reset_ask
    expect_poll "the reset question is owed" '{"asked": true, "backup": null}' reset_record
    expect_poll "the reset question is the one notice surface" 1 layer_count vgs:notice
    expect_poll "the reset question names the reset" '"Reset VGS?"' reset_drawn title
    expect "the reset question offers Cancel and Reset" '["Cancel", "Reset"]' reset_drawn actions
    expect "the reset question's command is behind Show command, closed" '{"toggle": "Show command", "expanded": false, "text": "vgshell reset --yes"}' reset_drawn command
    expect_poll "the reset question holds the keyboard" true ipc smoke noticeFocused
    expect_poll "Cancel holds the keyboard first" '"Cancel"' reset_drawn focused
    reset_send "down 9" "up 9" || fail "sending Escape to the reset question failed"
    expect_poll "control: Escape closes the reset question" '{"asked": false, "backup": null}' reset_record
    expect_poll "control: the closed question leaves no surface" 0 layer_count vgs:notice
    expect "control: Escape moves no user file" same reset_same "$reset_saved/planted-shell.json" "$reset_user"
    expect "control: Escape makes no backup" absent reset_file "$reset_data/backups"

    # The Settings row asks the same question.
    expect "the Settings window summons" ok ipc shell summon window vgs.settings '{}'
    expect_poll "the Settings window maps" 1 window_count Plugins
    expect_poll "the list's heading draws Reset VGS" drawn reset_button "Reset VGS"
    click_in window:Plugins window vgs.settings Button "Reset VGS" || fail "the click on Reset VGS failed"
    expect_poll "Reset VGS in Settings asks the reset question" '{"asked": true, "backup": null}' reset_record
    expect_poll "the asked question holds the keyboard" true ipc smoke noticeFocused
    reset_send "down 23" "up 23" || fail "sending Tab to the reset question failed"

    if reset_press Reset; then
      reset_folder="$(cat -- "$reset_marker" 2>/dev/null)" || reset_folder=""
      if [[ $reset_folder == "$reset_data/backups/"* && -d $reset_folder ]]; then ok "the reset marker names its backup folder: $reset_folder"; else fail "the reset marker names no backup folder: [$reset_folder]"; fi
      expect "the backup holds the planted user file byte for byte" same reset_same "$reset_saved/planted-shell.json" "$reset_folder/config/shell.json"
      expect "the backup holds the planted theme file byte for byte" same reset_same "$reset_saved/planted-theme.json" "$reset_folder/config/theme.json"
      expect "the backup holds the installed fixture" present reset_file "$reset_folder/config/plugins/acme.tick/manifest.json"
      expect "the backup holds welcome-seen" present reset_file "$reset_folder/state/welcome-seen"
      expect "the backup holds the Hyprland layer" present reset_file "$reset_folder/state/hypr/vgs.lua"
      # The defaults are applied only over a state that named an applied
      # package; with none, no theme file is written, as on a fresh install.
      if [[ $reset_themed == present ]]; then
        expect "the theme file holds the shipped defaults" same reset_same "$repo/themes/vgs/theme.json" "$reset_theme"
      else
        expect "a state with no applied package gets no theme file" absent reset_file "$reset_theme"
      fi
      expect "the reset shell draws the default theme" vgs ipc smoke themeName
      expect "the reset shell finds no installed plugin" False plugin_known acme.tick
      expect_poll "the reset shell's bars draw no user widget" '[false]' reset_tick_in_bars
      expect "the shipped set runs vgs.launcher again" True plugin_enabled vgs.launcher
      expect "the user file holds nothing of the planted layer" '{"tick": false, "launcherOff": false}' reset_layer
      expect_poll "the welcome is unseen after the reset" unseen reset_welcome
      expect_poll "the reset shell offers the restore" "{\"asked\": false, \"backup\": \"$reset_folder\"}" reset_record
      expect_poll "the reset's notice is the one notice surface" 1 layer_count vgs:notice
      expect_poll "the reset's notice names the reset" '"VGS was reset"' reset_drawn title
      expect "the reset's notice offers Restore previous settings and Keep these" '["Restore previous settings", "Keep these"]' reset_drawn actions
      expect "the restore's command is behind Show command, closed" "{\"toggle\": \"Show command\", \"expanded\": false, \"text\": \"vgshell reset restore --yes $reset_folder\"}" reset_drawn command
      expect_poll "Keep these holds the keyboard first" '"Keep these"' reset_drawn focused
      expect_poll "the reset shell writes the Hyprland layer again" present reset_file "$reset_state/hypr/vgs.lua"
      expect_poll "Hyprland lists no config error after the reset" '[]' hypr_config_errors

      # Escape hides the notice for this run and keeps the marker, so the
      # next start offers the restore again; only Keep these forgets it.
      reset_send "down 9" "up 9" || fail "sending Escape to the reset's notice failed"
      expect_poll "Escape hides the reset's notice" '{"asked": false, "backup": null}' reset_record
      expect_poll "the welcome the reset's notice held back shows next" '"Welcome to VGS"' reset_drawn title
      expect "Escape keeps the reset marker" present reset_file "$reset_marker"
      reset_back=false
      reset_where="$(reset_sandboxed)" || reset_where=unreadable
      if [[ $reset_where == sandboxed ]]; then
        reset_old="$shell_qs_pid"
        expect "the sandbox's shell restarts over the kept marker" true reset_restart "$reset_old"
        reset_adopt "$reset_old" "the restart" && reset_back=true
      else
        fail "the shell is not restarted: $reset_where"
      fi
      if [[ $reset_back == true ]]; then
        expect_poll "the next start offers the restore again" "{\"asked\": false, \"backup\": \"$reset_folder\"}" reset_record
        expect_poll "the reset's notice shows again" '"VGS was reset"' reset_drawn title
        expect_poll "Keep these holds the keyboard again" '"Keep these"' reset_drawn focused
        # Tab past Show command; this keyboard's Shift+Tab moved no focus.
        reset_send "down 23" "up 23" "down 23" "up 23" || fail "sending Tab to the reset's notice failed"
        reset_hold_theme_lock >"$reset_hold" &
        reset_holder=$!
        expect_poll "another theme command holds the theme lock at the press" held reset_hold_first
      fi
      if [[ $reset_back == true ]] && reset_press "Restore previous settings"; then
        expect "the restore waited for the theme lock" waited reset_hold_last
        expect "the restore puts the user file back byte for byte" same reset_same "$reset_saved/planted-shell.json" "$reset_user"
        expect "the restore puts the theme file back byte for byte" same reset_same "$reset_saved/planted-theme.json" "$reset_theme"
        expect "the restore puts the installed fixture back" present reset_file "$reset_config/plugins/acme.tick/manifest.json"
        expect "the restore puts welcome-seen back" present reset_file "$reset_state/welcome-seen"
        expect "the restore removes the backup it took" absent reset_file "$reset_folder"
        expect "the restore leaves no reset marker" absent reset_file "$reset_marker"
        expect "the restored shell draws the custom theme" reset-probe ipc smoke themeName
        expect_poll "the restored layer puts the fixture's widget in the bar" '[true]' reset_tick_in_bars
        expect "the restored layer turns vgs.launcher off" False plugin_enabled vgs.launcher
        expect_poll "the welcome is seen after the restore" seen reset_welcome
        expect_poll "the restored shell offers no restore" '{"asked": false, "backup": null}' reset_record
        expect_poll "the restored shell shows no notice" 0 layer_count vgs:notice
        expect_poll "Hyprland lists no config error after the restore" '[]' hypr_config_errors
      fi
      [[ -z $reset_holder ]] || wait "$reset_holder" || :
    fi
  fi

  reset_keyboard_stop
  # The files and stand-ins the row found, and the sandbox's own tree.
  for file in "$reset_user" "$reset_theme"; do
    if [[ -e $reset_saved/${file##*/} ]]; then cp -p -- "$reset_saved/${file##*/}" "$file.tmp" && mv -T -- "$file.tmp" "$file"; else rm -f -- "$file"; fi
  done
  for name in "${reset_shim_names[@]}"; do
    if [[ -e $reset_saved/shim/$name ]]; then cp -p -- "$reset_saved/shim/$name" "$shim/$name"; else rm -f -- "${shim:?}/$name"; fi
  done
  rm -rf -- "${reset_data:?}/backups"
  rm -f -- "${reset_marker:?}"
  if stop_shell && start_shell "$repo" "$sandbox/reset-end-qs.log"; then
    expect "the sandbox's own shell offers no restore" '{"asked": false, "backup": null}' reset_record
  fi
}

expect "every directory the reset acts on lies under the sandbox" contained reset_contained
if [[ $(reset_contained) == contained ]]; then reset_run_row; else fail "the row runs nothing: the reset would act outside the sandbox"; fi
