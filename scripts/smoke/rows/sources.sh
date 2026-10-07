# Source revisions: an edit to a plugin's own files, including a sibling
# file its entry point imports, reaches a new build of that plugin alone;
# a build that failed is not tried again until the source changes; two
# rescans asked for back to back both complete; and an unchanged plugin's
# files stay readable after the sources of others were replaced. Every
# fixture write is a rename, so the scan never reads half a file.
# inputs: scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/Plugins.qml shell/Core/Registry.qml bin/vgshell-scan scripts/smoke/rows/plugins.sh
set -euo pipefail
tick_revision() { ipc shell listPlugins | py_reply 'import json,sys; print([p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.tick"][0])'; }
write_tick() { # FILE CONTENT: replace one file of the placed widget whole
  printf '%s' "$2" >"$tick/$1.tmp" && mv -T -- "$tick/$1.tmp" "$tick/$1"
}
tick_sibling() { # VALUE: the sibling's exported value
  write_tick Tick.js ".pragma library
var VALUE = \"$1\";
"
}
# The build records list a rebuilt widget last; the drawn order is the
# order of the section's children, read from each widget's own index.
widget_index() { ipc smoke childIndex "$(bar_key)" "$1"; }
source_widgets_present() { bar_widget_ids | py_reply 'import json,sys; bars=json.load(sys.stdin); print(bool(bars) and all(sorted(ids)==["acme.probe","acme.tick"] for ids in bars))'; }
probe_at_right_edge() {
  local probe bar padding
  probe="$(ipc smoke instanceGeometry "$(bar_key)" acme.probe)" || return
  bar="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar)" || return
  padding="$(ipc smoke themeValue bar.padding)" || return
  py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); bx,by,bw,bh=json.loads(sys.argv[1]); print(w>0 and abs(x+w+float(sys.argv[2])-bx-bw)<=1)' "$bar" "$padding" <<<"$probe"
}
tick_before_probe() { python3 -c 'import sys; a, b = int(sys.argv[1]), int(sys.argv[2]); print(a >= 0 and b >= 0 and a < b)' "$(widget_index acme.tick)" "$(widget_index acme.probe)"; }

expect "the placed widget reads its sibling import" '"one"' read_tick sibling
tick_widget_original="$(cat "$tick/Widget.qml")"
revision_one="$(tick_revision)"
if before="$(builds)"; then
  tick_sibling two
  rescan "a rescan after editing a sibling file answers ok"
  expect_poll "the edited sibling reaches the rebuilt widget" '"two"' read_tick sibling
  expect "the edit rebuilt the widget on every screen and nothing else" "$((before + monitors))" builds
  if revision_two="$(tick_revision)" && [[ -n $revision_one && -n $revision_two && $revision_one != "$revision_two" ]]; then ok "the edit gave the plugin a new revision"; else fail "revisions before and after the edit: $revision_one ${revision_two:-unreadable}"; fi
  expect "the rebuilt widget keeps its layout entry" '"HH:mm:ss"' read_tick format
else
  fail "buildCount unreadable before the source rows"
fi
if before="$(builds)"; then
  python3 - "$tick/Widget.qml" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "    readonly property string sibling: Tick.VALUE\n"
new = "    readonly property string sibling: \"stale\"\n"
if text.count(old) != 1:
    raise SystemExit(f"sibling-control matches={text.count(old)}")
changed = text.replace(old, new)
if changed == text:
    raise SystemExit("sibling-control unchanged")
path.write_text(changed)
PY
  tick_sibling control
  rescan "control: a rescan after editing a sibling ignored by the widget answers ok"
  expect_poll "control: a widget that ignores its sibling import stays stale after the sibling edit" '"stale"' read_tick sibling
  write_tick Widget.qml "$tick_widget_original"
  tick_sibling two
  rescan "the sibling-import control restores the widget source"
  expect_poll "the restored widget reads its sibling import again" '"two"' read_tick sibling
else
  fail "buildCount unreadable before the sibling control"
fi

# A rebuilt widget keeps its place among its section's widgets: the
# fixture widget is moved beside the placed widget for the check and back.
move_probe() { # SECTION: move the fixture widget's layout entry to that section
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, os, sys
p, section = sys.argv[1], sys.argv[2]
d = json.load(open(p))
layout = d["bar"]["layout"]
entry = [e for s in layout.values() for e in s if e["id"] == "acme.probe"][0]
for s in layout.values():
    s[:] = [e for e in s if e["id"] != "acme.probe"]
layout[section].append(entry)
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
}
move_probe center
expect_poll "both widgets remain mounted after moving to centre" True source_widgets_present
expect_poll "the placed widget precedes the fixture widget in the section" True tick_before_probe
if before="$(builds)"; then
  tick_sibling three
  rescan "a rescan after a second edit answers ok"
  expect_poll "the second edit reaches the rebuilt widget" '"three"' read_tick sibling
  expect "the second edit rebuilt the widget alone" "$((before + monitors))" builds
  expect_poll "the rebuilt widget keeps its place before its neighbour" True tick_before_probe
else
  fail "buildCount unreadable before the order rows"
fi
move_probe right
geometry expect_poll "the fixture widget returns to the right section" True probe_at_right_edge

# A widget whose code fails to load is logged once per bar and not tried
# again for a settings change; the repaired code is tried on its rescan.
widget_good="$(cat "$tick/Widget.qml")"
expected_errors+=('plugins: acme\.tick failed to load: ')
loads_before="$(log_lines 'plugins: acme\.tick failed to load: ')" || fail "instance log unreadable: $instance_log"
write_tick Widget.qml 'import QtQuick
import qs.Ui
BarWidget { broken
'
rescan "a rescan after breaking the widget answers ok"
expect_log "the core logged the failed load on every bar" "$((loads_before + monitors))" 'plugins: acme\.tick failed to load: '
expect_widgets "the broken widget leaves the bar" '["acme.probe"]'
if before="$(builds)"; then
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
[e for e in d["bar"]["layout"]["center"] if e["id"] == "acme.tick"][0]["format"] = "retry-check"
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  tick_format_effective() { ipc shell listShellConfig | py_reply 'import json,sys; print([e["format"] for e in json.load(sys.stdin)["bar"]["layout"]["center"] if e["id"]=="acme.tick"][0])'; }
  expect_poll "the shell read the settings change for the broken widget" retry-check tick_format_effective
  expect "a settings change does not try the failed code again" "$((loads_before + monitors))" log_lines 'plugins: acme\.tick failed to load: '
  expect "a settings change builds nothing for the failed code" "$before" builds
else
  fail "buildCount unreadable before the retry rows"
fi
write_tick Widget.qml "$widget_good"
rescan "a rescan after repairing the widget answers ok"
expect_widgets "the repaired widget returns to the bar" '["acme.probe","acme.tick"]'
expect_poll "the repaired widget reads its layout entry" '"retry-check"' read_tick format

# Two rescans asked for back to back: the second is queued while the first
# runs, or starts after it. Either way one answers `ok` for the scan ending
# at the next revision and the other names the end after it, and both
# complete.
if back_to_back_revision="$(ipc shell scanRevision)" && [[ $back_to_back_revision =~ ^[0-9]+$ ]]; then
  ipc shell rescanPlugins >"$sandbox/rescan-first.out" &
  rescan_first=$!
  second="$(ipc shell rescanPlugins)" || second="failed"
  wait "$rescan_first" || true
  first="$(cat "$sandbox/rescan-first.out")" || first="unreadable"
  scans_named="$(printf '%s\n' "$first" "$second" | sort)"
  if [[ $scans_named == "ok scan=$((back_to_back_revision + 1))"$'\n'"ok scan=$((back_to_back_revision + 2))" || $scans_named == "busy scan=$((back_to_back_revision + 2))"$'\n'"ok scan=$((back_to_back_revision + 1))" ]]; then
    ok "two back-to-back rescans name the next two scan ends ($first, $second)"
  else
    fail "back-to-back rescans after revision $back_to_back_revision answered $first and $second"
  fi
  expect_poll "both back-to-back rescans completed" landed scan_landed "$((back_to_back_revision + 2))"
else
  fail "the scan revision before the back-to-back rescans is unreadable: ${back_to_back_revision:-}"
fi
expect "an unchanged plugin's files stay readable after the rescans" lazy ipc smoke invokeInstance "$(bar_key)" acme.tick lazy ''
# The rescans above changed only the placed widget, so the fixture
# service's in-memory state stayed: its shortcut counter, pressed once here.
expect "the compositor triggers the fixture's shortcut before the state check" ok hypr dispatch 'hl.dsp.global("acme.probe:ping")'
expect_poll "the fixture service counted the press" 1 read_service presses
rescan "a rescan that changes nothing answers ok before the state check"
expect "the running service kept its in-memory state across the rescans" 1 read_service presses

# The scanner's output is usable only after a successful exit. Each bad
# scanner is installed in the sandbox copy, never in the live checkout.
scan_error() { ipc shell listPlugins | py_reply 'import json,sys; print(json.load(sys.stdin)["scanError"])'; }
cp -p -- "$repo/bin/vgshell-scan" "$sandbox/vgshell-scan.good"
scan_plugins_before="$(ipc shell listPlugins | py_reply 'import json,sys; print(json.load(sys.stdin)["plugins"])')" || scan_plugins_before=""
scan_plugins() { ipc shell listPlugins | py_reply 'import json,sys; print(json.load(sys.stdin)["plugins"])'; }
expected_errors+=('plugins: vgshell-scan exited 9 status=0' 'plugins: vgshell-scan did not start' 'plugins: scan output does not parse: ')
printf '#!/bin/sh\nprintf "[]\\n"\nexit 9\n' >"$repo/bin/vgshell-scan"
rescan "a scanner that exits nonzero accepts the scan request"
expect "control: the nonzero scanner exit is reported" 'vgshell-scan exited 9 status=0' scan_error
expect "control: valid-looking output from a failed scanner keeps the registry" "$scan_plugins_before" scan_plugins
chmod 000 "$repo/bin/vgshell-scan"
rescan "an unstartable scanner accepts the scan request"
expect "control: the scanner failed start is reported" 'vgshell-scan did not start' scan_error
expect "control: a failed start keeps the registry" "$scan_plugins_before" scan_plugins
chmod 755 "$repo/bin/vgshell-scan"
printf '#!/bin/sh\nprintf "{}\\n"\n' >"$repo/bin/vgshell-scan"
rescan "a malformed scanner accepts the scan request"
expect "control: a non-list scan result is reported" 'scan output does not parse: expected an entry list' scan_error
expect "control: a malformed result keeps the registry" "$scan_plugins_before" scan_plugins
mv -T -- "$sandbox/vgshell-scan.good" "$repo/bin/vgshell-scan"
rescan "a repaired scanner accepts the scan request"
expect "a successful scan clears the error" '' scan_error
expect "the repaired scan preserves the plugin list" "$scan_plugins_before" scan_plugins
