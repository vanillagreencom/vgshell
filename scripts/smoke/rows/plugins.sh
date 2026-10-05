# A fixture plugin in the sandbox user directory: kind service plus a bar
# widget, naming every capability. Proves user-directory discovery, the
# service host, that each instance receives exactly the capabilities its
# manifest names, that a settings change reaches a running instance without
# a rebuild, and that every capability delivers its object and releases it
# on disable. The service registers through its capabilities once and
# answers IPC calls that drive the rest. The rows read the fixture's own
# properties back through readInstance, never the build records.
# A rescan answers with the scan revision its scan ends at, and the
# harness's rescan reads the shell's state only once that scan has landed.
# Its controls hold a scan behind a gate: the revision stays short of the
# one named and the listing keeps the last scan's state until the gate
# opens; a copy of rescan that does not wait reads that old state; a
# rescan queued behind a held scan that read the files before a change
# names the revision after it and reads the change; and a copy of the
# tree whose Registry names the revision before its scan, run as the
# guarded shell, lets rescan read the last scan's state. That copy stops
# the row's shell and the row starts the sandbox's tree again after it.
# inputs: shell/Core/PluginLogic.js scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.bare/* scripts/smoke/fixtures/plugins/acme.tick/* shell/plugins/vgs.bar/* shell/shell.qml shell/Core/Plugins.qml shell/Core/Registry.qml shell/Core/Capabilities.qml shell/Hosts/ServiceHost.qml bin/vgshell bin/vgshell-scan bin/vgshell-plugin-judge
set -euo pipefail
fixture="$sandbox/src/acme.probe"
mkdir -p "$fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.probe/." "$fixture/"
# A second user plugin naming no capability, beside the fixture.
bare="$home/.config/vgshell/plugins/acme.bare"
mkdir -p "$bare"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.bare/." "$bare/"
# The fixture reaches the user directory the way a user's plugin does:
# committed to a repository and installed with `vgshell plugin add`.
fixture_git() { "${sandbox_env[@]}" git -C "$fixture" -c user.name=smoke -c user.email=smoke@invalid "$@" >>"$sandbox/git.log" 2>&1; }
if fixture_git init -q && fixture_git add -A && fixture_git commit -q -m fixture; then ok "fixture committed to a local repository"; else fail "fixture repository: $(tail -n 3 "$sandbox/git.log")"; fi
add_out=""
# --yes answers the add question; the plugin has a bar widget, so add says
# it lands shown and writes its placement before the rescan.
if add_out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin add --yes "file://$fixture" 2>>"$sandbox/ipc.log")" \
  && [[ $add_out == $'ok added=acme.probe path='"$home/.config/vgshell/plugins/acme.probe"$' config=written lands=shown\nshell=rescan-started' ]]; then
  ok "vgshell plugin add installs the fixture shown and rescans the shell"
else
  fail "vgshell plugin add: $add_out"
fi
# The added plugin, which has a bar widget, is placed in its default section
# and enabled with no further step (PluginLogic.landsShown); one without a
# widget, the bare fixture, stays disabled until enabled.
probe_listed() { ipc shell listPlugins | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin)["plugins"] if p["id"] == sys.argv[1]]; print(json.dumps([r[0]["enabled"], r[0]["placed"]]) if r else "absent")' "$1"; }
expect_poll "the installed fixture with a widget is enabled and placed with no further step" '[true, true]' probe_listed acme.probe
expect "the user-directory plugin without a widget is discovered disabled" False plugin_enabled acme.bare
expect "enabling the bare fixture is allowed" ok ipc shell setPluginEnabled acme.bare true
# The scan probes each declared command on the shell's PATH: `sh` is on
# every sandbox's, `vgs-smoke-absent` on none. listPlugins carries the
# states and `vgshell plugin list` names the missing one. It is optional, so
# enabling the fixture raises no requirement notice over the later rows.
bare_requirements() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps([[r["command"], r["state"]] for p in json.load(sys.stdin)["plugins"] if p["id"] == "acme.bare" for r in p["requirements"]]))'; }
expect_poll "listPlugins reports each declared command's state" '[["sh", "present"], ["vgs-smoke-absent", "missing"]]' bare_requirements
bare_missing_line() { "${shell_env[@]}" "$repo/bin/vgshell" plugin list | grep -F 'missing acme.' || true; }
expect "vgshell plugin list names the missing command" "missing acme.bare vgs-smoke-absent optional" bare_missing_line
# A command that appears on the shell's PATH is present after the next
# rescan, and missing again once it goes; the plugin's files did not
# change, so neither rescan builds anything. $shim leads the shell's PATH.
if before="$(builds)"; then
  printf '#!/bin/sh\nexit 0\n' >"$shim/vgs-smoke-absent"; chmod 755 "$shim/vgs-smoke-absent"
  rescan "a rescan after the command appears starts"
  expect "the command on PATH is reported present after the rescan" '[["sh", "present"], ["vgs-smoke-absent", "present"]]' bare_requirements
  rm -f -- "$shim/vgs-smoke-absent"
  rescan "a rescan after the command goes starts"
  expect "the removed command is reported missing after the rescan" '[["sh", "present"], ["vgs-smoke-absent", "missing"]]' bare_requirements
  expect "a requirement's state change rebuilds nothing" "$before" builds
else
  fail "buildCount unreadable before the requirement rescan rows"
fi

service_built() { ipc shell built | py_reply 'import json,sys; d=json.load(sys.stdin); print(any(r["id"]=="acme.probe" and r["kind"]=="service" for r in d.get("service",[])))'; }
read_widget() { ipc smoke readInstance "$(bar_key)" acme.probe "$1"; }
read_service() { ipc smoke readInstance service acme.probe "$1"; }
read_clock() { ipc smoke readInstance "$(bar_key)" vgs.bar/center-clock "$1"; }
read_tick() { ipc smoke readInstance "$(bar_key)" acme.tick "$1"; }
got=""
for _ in $(seq 1 25); do if got="$(service_built)" && [[ $got == True ]]; then break; fi; sleep 0.2; done
if [[ $got == True ]]; then ok "the service host built the fixture service"; else fail "service host: built=$got"; fi
expect_widgets "the fixture widget joined the right section" '["acme.tick","acme.probe"]'
expect "the fixture widget can call its compositor capability" true read_widget hasCompositor
expect "the fixture widget's settings array stayed an array" true read_widget tagsAreArray
all_caps='"compositor,configure,idle,ipc,lock,manifest,notifications,polkit,run,screens,settings,shortcut,theme,toasts,tui"'
expect "the fixture widget's shell holds exactly what it named" "$all_caps" read_widget shellKeys
expect "the fixture service's shell holds exactly what it named" "$all_caps" read_service shellKeys
expect_poll "a plugin naming no capability receives none" '"manifest,settings"' ipc smoke readInstance service acme.bare shellKeys
expect "the fixture service reads the manifest default" '"probe"' read_service label
expect "a placed widget reads its layout entry" '"ddd d MMM  HH:mm"' read_tick format
expect "the built-in clock reads the bar's clock format" '"ddd d MMM  HH:mm"' read_clock format

# The built-in receives the bar's capability, independently of fixture grants.
expect "the built-in workspaces receive a callable compositor action" true ipc smoke hasWorkspaceAction "$(bar_key)" vgs.bar/left-workspaces
active_ws() { hypr -j activeworkspace | py_reply 'import json,sys; print(json.load(sys.stdin)["id"])'; }

# A settings change reaches the running instance and builds nothing: the
# service's plugins[] row, then the clock's layout entry.
if before="$(builds)"; then
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "acme.probe"] + [{"id": "acme.probe", "label": "changed-service-setting"}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  expect_poll "the running service received its changed setting" '"changed-service-setting"' read_service label
  expect "the fixture widget keeps the manifest default its entry does not override" '"probe"' read_widget label
  expect "a service settings change rebuilds nothing" "$before" builds
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
center = d["bar"]["layout"]["center"]
[e for e in center if e["id"] == "acme.tick"][0]["format"] = "HH:mm:ss"
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  expect_poll "the running widget received its changed layout entry" '"HH:mm:ss"' read_tick format
  expect "a widget settings change rebuilds nothing" "$before" builds
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "vgs.bar"] + [{"id": "vgs.bar", "clockFormat": "HH:mm:ss"}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  expect_poll "the built-in clock received the bar's changed setting" '"HH:mm:ss"' read_clock format
  # The shared clock ticks seconds only while a format shows them: three
  # readings across 2.2 s change at least twice at second precision.
  clock_changes=0; clock_last=""
  for _ in 1 2 3; do
    if clock_now="$(ipc smoke textOf "$(bar_key)" vgs.bar/center-clock)"; then
      [[ -n $clock_last && $clock_now != "$clock_last" ]] && clock_changes=$((clock_changes + 1))
      clock_last="$clock_now"
    fi
    sleep 1.1
  done
  if [[ $clock_changes -ge 2 ]]; then ok "the shared clock ticks seconds for a seconds format"; else fail "clock text changed $clock_changes times in 2.2 s"; fi
  expect "a bar settings change rebuilds nothing" "$before" builds
  expect_builtins "the built-ins stay registered across a bar settings change" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
else
  fail "buildCount unreadable before the settings rows"
fi

# Controls: bin/vgshell-scan, in the sandbox copy, held behind a gate file.
# gated_scanner PATH MODE makes PATH a vgshell-scan that touches
# $scan_started and then waits for $scan_gate, up to 60 s: before it scans
# when MODE is `before`, so the held scan reads the files the gate opens
# on, and after it scans when MODE is `after`, so it hands over what it
# read before the gate opened. The real scanner is kept in $scan_real.
scan_bin="$repo/bin/vgshell-scan"
scan_real="$sandbox/vgshell-scan.plugins-kept"
scan_gate="${sandbox:?}/plugins-scan-gate"
scan_started="${sandbox:?}/plugins-scan-started"
scan_asked="${sandbox:?}/plugins-scan-asked"
scan_opened="${sandbox:?}/plugins-scan-opened"
bare_present='[["sh", "present"], ["vgs-smoke-absent", "present"]]'
bare_absent='[["sh", "present"], ["vgs-smoke-absent", "missing"]]'
cp -p -- "$scan_bin" "$scan_real"
gated_scanner() { # PATH MODE
  local hold
  hold="$(printf ': >%q\nn=0\nwhile [ ! -e %q ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done' "$scan_started" "$scan_gate")"
  case $2 in
    before) printf '#!/bin/sh\n%s\nexec %q "$@"\n' "$hold" "$scan_real" >"$1" ;;
    after) printf '#!/bin/sh\nout="$(%q "$@")"\nstatus=$?\n%s\nprintf "%%s\\n" "$out"\nexit "$status"\n' "$scan_real" "$hold" >"$1" ;;
    *) fail "gated_scanner: refused: mode=$2 want=before|after"; return 1 ;;
  esac
}
scan_hold() { rm -f -- "${sandbox:?}/plugins-scan-gate" "${sandbox:?}/plugins-scan-started" "${sandbox:?}/plugins-scan-asked" "${sandbox:?}/plugins-scan-opened"; }
scan_started_seen() { if [[ -e $scan_started ]]; then echo started; else echo waiting; fi; }
# true when the opener read the named scan unreached, else what it read.
scan_opened_short() { local read; read="$(cat -- "$scan_opened")" || return; if [[ $read == scan=* ]]; then echo true; else echo "read=$read"; fi; }
plant_absent() { printf '#!/bin/sh\nexit 0\n' >"$shim/vgs-smoke-absent" && chmod 755 "$shim/vgs-smoke-absent"; }
# While a row runs plugins_rescan, plugins_scan_ipc also writes each
# rescanPlugins reply to $scan_asked. scan_open_when_asked, in the
# background, opens the gate once that reply is in and scanRevision still
# reads short of the scan it names, and writes what it read to
# $scan_opened; at its bound it opens the gate all the same, so no scan
# stays held past the row.
scan_ipc_vgshell="$repo/bin/vgshell"
plugins_scan_ipc() {
  local reply status=0
  reply="$(ipc_via "$scan_ipc_vgshell" "$@")" || status=$?
  if [[ ${2:-} == rescanPlugins ]]; then printf '%s\n' "$reply" >"$scan_asked"; fi
  printf '%s\n' "$reply"
  return "$status"
}
# Keep the harness's rescan body and change only the private IPC caller
# that records the scan reply for the opener.
scan_ipc_call='$(ipc shell rescanPlugins)'
if scan_helper="$(declare -f rescan)" && [[ $scan_helper == "rescan ()"* && ${scan_helper#*"$scan_ipc_call"} != "$scan_helper" && ${scan_helper#*"$scan_ipc_call"} != *"$scan_ipc_call"* ]]; then
  scan_helper="plugins_rescan ()${scan_helper#rescan ()}"
  eval "${scan_helper/"$scan_ipc_call"/\$(plugins_scan_ipc shell rescanPlugins)}"
else
  fail "the harness's rescan does not call ipc shell rescanPlugins once"
  return 1
fi
scan_open_when_asked() {
  local reply short
  for _ in $(seq 1 200); do
    if [[ -s $scan_asked ]] && reply="$(cat -- "$scan_asked")" && [[ $reply =~ ^(ok|busy)\ scan=([0-9]+)$ ]]; then
      short="$(scan_landed "${BASH_REMATCH[2]}")" || short=unread
      printf '%s\n' "$short" >"$scan_opened"
      : >"$scan_gate"
      return
    fi
    sleep 0.05
  done
  echo unasked >"$scan_opened"
  : >"$scan_gate"
}

# The reply names the next revision, which stays unreached, and the
# listing keeps the last scan's state, while the scan is held.
scan_hold
gated_scanner "$scan_bin" before
plant_absent
if held_before="$(ipc shell scanRevision)" && [[ $held_before =~ ^[0-9]+$ ]]; then
  expect "control held scan: the reply names the next scan revision" "ok scan=$((held_before + 1))" plugins_scan_ipc shell rescanPlugins
  expect_poll "control held scan: the held scanner has started" started scan_started_seen
  expect "control held scan: scanRevision stays short of the named scan while it is held" "$held_before" ipc shell scanRevision
  expect "control held scan: listPlugins keeps the last scan's state while it is held" "$bare_absent" bare_requirements
  : >"$scan_gate"
  expect_poll "control held scan: the scan let end reaches the named revision" landed scan_landed "$((held_before + 1))"
  expect "control held scan: the landed scan lists the planted command" "$bare_present" bare_requirements
else
  fail "control held scan: scanRevision unreadable: ${held_before:-}"
fi

# The harness's rescan with its wait taken out, from its own text, reads
# the last scan's state while the scan is held; rescan itself, its gate
# opened only once its reply is in and the scan it names is unreached,
# reads the new one.
scan_hold
rm -f -- "${shim:?}/vgs-smoke-absent"
scan_poll='expect_poll "$1" landed scan_landed'
if scan_helper="$(declare -f plugins_rescan)" && [[ $scan_helper == "plugins_rescan ()"* && ${scan_helper#*"$scan_poll"} != "$scan_helper" && ${scan_helper#*"$scan_poll"} != *"$scan_poll"* ]]; then
  scan_helper="rescan_unwaited ()${scan_helper#plugins_rescan ()}"
  eval "${scan_helper/"$scan_poll"/ok \"\$1\"; :}"
  rescan_unwaited "control unwaited: the rescan without its wait is accepted"
  expect "control: a rescan that does not wait reads the last scan's state while the scan is held" "$bare_present" bare_requirements
  unset -f rescan_unwaited
else
  fail "control unwaited: the harness's rescan does not poll once with: $scan_poll"
fi
rm -f -- "${sandbox:?}/plugins-scan-asked"
scan_open_when_asked &
scan_opener=$!
plugins_rescan "a rescan over a held scan waits for it"
wait "$scan_opener" || true
expect "the gate opened while the scan the rescan named was unreached" true scan_opened_short
expect "the waited rescan lists the removed command missing" "$bare_absent" bare_requirements

# A rescan asked for while a held scan runs is queued, and the scan that
# lands it is the queued one: the held scan here read the files before the
# command was planted, so a reply naming the held scan's end reads the
# command missing.
scan_hold
gated_scanner "$scan_bin" after
if busy_before="$(ipc shell scanRevision)" && [[ $busy_before =~ ^[0-9]+$ ]]; then
  expect "control busy: the held scan's reply names the next scan revision" "ok scan=$((busy_before + 1))" plugins_scan_ipc shell rescanPlugins
  expect_poll "control busy: the held scan has read the files" started scan_started_seen
  plant_absent
  rm -f -- "${sandbox:?}/plugins-scan-asked"
  scan_open_when_asked &
  scan_opener=$!
  plugins_rescan "a rescan behind a held scan waits for the queued scan"
  wait "$scan_opener" || true
  expect "the rescan behind the held scan was queued for the revision after it" "busy scan=$((busy_before + 2))" cat -- "$scan_asked"
  expect "the gate opened while the queued scan was unreached" true scan_opened_short
  expect "the queued scan lists the planted command" "$bare_present" bare_requirements
else
  fail "control busy: scanRevision unreadable: ${busy_before:-}"
fi
cp -p -- "$scan_real" "$scan_bin"
rm -f -- "${shim:?}/vgs-smoke-absent"
plugins_rescan "a rescan after the busy control's command goes"
expect "the busy control's command reads missing again" "$bare_absent" bare_requirements

# Control: a copy of the tree whose Registry names, for a scan it starts,
# the revision before that scan ends, run as the guarded shell over the
# held scanner, its gate open while it starts. rescan then takes the
# scan as landed at once and reads the last scan's state.
copy_tree rescan-current
if edit_tree rescan-current shell/Core/Registry.qml '        const scan = requirementsRevision + 1;' '        const scan = requirementsRevision;'; then
  gated_scanner "$sandbox/tree-rescan-current/bin/vgshell-scan" before
  scan_hold
  : >"$scan_gate"
  scan_ipc_vgshell="$sandbox/tree-rescan-current/bin/vgshell"
  if stop_shell && start_shell "$sandbox/tree-rescan-current" "$sandbox/plugins-rescan-current-qs.log"; then
    expect "control rescan-current: the copy is the guarded shell" true ipc shell guarded
    expect "control rescan-current: the copy's first scan reads the command missing" "$bare_absent" bare_requirements
    scan_hold
    plant_absent
    plugins_rescan "control rescan-current: the copy's rescan is accepted"
    expect "control: a Registry naming the revision before its scan lets rescan read the last scan's state" "$bare_absent" bare_requirements
    : >"$scan_gate"
    expect_poll "control rescan-current: the held scan lists the planted command once let end" "$bare_present" bare_requirements
  fi
  scan_ipc_vgshell="$repo/bin/vgshell"
  stop_shell || :
  start_shell "$repo" "$sandbox/plugins-restart-qs.log" || fail "the shell starts again after the rescan-current control"
  expect "the restarted shell lists the planted command" "$bare_present" bare_requirements
fi
rm -f -- "${shim:?}/vgs-smoke-absent"
plugins_rescan "a rescan after the controls' command goes"
expect "the controls' command reads missing again" "$bare_absent" bare_requirements
scan_hold
unset -f plugins_rescan
