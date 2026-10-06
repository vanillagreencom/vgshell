# vgs.updates, the service that owns every update probe, its bar widget
# and its window. A copy of the plugin in the user directory, which wins
# the id over the shipped one, runs the shipped Service.qml, Widget.qml,
# Window.qml and bin/check against the shipped bin/vgshell, with two changes
# only: one fixture `tui` script beside the declared update TUIs,
# scripts/smoke/fixtures/tui/vgs.updates/tui/finish.sh, a run of which the
# row holds open until it opens a gate, listed with an entry so `openTui`
# reaches it; and the vgshell it runs, a wrapper that confines each verb:
#
# - `pkg` runs the shipped `vgshell pkg` in an unprivileged mount namespace
#   whose /etc/os-release names the identity this row picks, `arch` or
#   `none`, with a PATH that holds the stand-ins under
#   scripts/smoke/fixtures/updates-bin and the few tools vgshell needs, so
#   bin/vgshell-pkg's own detection and parsers read stub output and no host
#   package manager runs;
# - every other verb runs the shipped vgshell with only the stand-in git ahead
#   of the shell's PATH: it answers for this checkout and the plugin copy
#   alone, so `self status` and `plugin outdated` reach no remote.
#
# The stand-in terminal runs the fixture alone: the declared `update`,
# `update-source` and `log` scripts, which would run package managers, it
# replaces with `true` (terminal_stand_in in harness.sh). The pipeline's
# own controls are scripts/test-updates-pipeline.sh.
#
# Read back from the accepted status record: every source's count, one
# probe run per check however often it is read, a failing source named and
# kept, a list past the status ceiling cut with its count kept, a request
# during a check queued once, a TUI run's end starting one check, the
# pipeline listed in the launcher's Update group, and only
# the VGS rows where no manager is detected. The control is a bar widget
# that runs the check itself: on two bars it probes twice for one check.
#
# The widget and the window are read back from what they draw: the icon,
# its colour, the spinner and the badge for pending, checking, failed,
# stale and current values, `hideWhenCurrent` hiding the widget only while
# current, the tooltip's lines, the window's rows and a row's packages, the
# argv each button hands the terminal, and Refresh starting one check of
# the service. The window is read as every application window is
# (app_window_rows, scripts/smoke/app-window.sh). The pending, checking and
# failed values come from real
# checks; the stale and current ones are written through the service's own
# status provider, since the service marks a snapshot stale only after
# twice the interval, and a rebuild of the plugin publishes the real ones
# again, with no check of its own. Its control is a copy of the widget's
# judge that hides on a failed check, which the visibility readback reads
# hidden. The reader of a button's argv answers absent with no record and
# partial for a record planted empty or cut before its script; its control
# is a reader of the old shape, which raises on an absent record, and
# expect_poll fails once on its traceback. The controls of smoke_row's
# traceback rule run here too, over rows planted in the sandbox that read
# the status record outside every expect.
#
# The third-party review's window: the service's `review` handler opens
# the shipped tui/review.sh in the review TUI's window, which runs a
# stand-in agent from the stable review start directory with a prompt that
# names the per-run directory. Its end lands in the directory as the run's
# code. The stand-in terminal runs a plugin script only when it is byte for
# byte a fixture's, so
# scripts/smoke/fixtures/tui/vgs.updates/tui/review.sh is an exact copy of
# the shipped script, read equal first: the script the presenter runs is
# the shipped one. Its end starts no check, and a run that ends after its
# directory went makes none. The presenter has the shell's environment, not this
# row's PATH, so the review directory's command names the stand-in agent
# by its absolute path, as an edited review command may. The pipeline's
# side of the review is scripts/test-updates-pipeline.sh's.
# inputs: shell/plugins/vgs.updates/* shell/Hosts/AppWindow.qml shell/Ui/overlay/OverlayState.qml shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/fixtures/updates-bin/* scripts/smoke/fixtures/tui/vgs.updates/* bin/vgshell bin/vgshell-pkg bin/lib/qml-library.js shell/Core/PackageManagers.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml bin/lib/self.js scripts/smoke/rows/manager.sh scripts/smoke/rows/capabilities.sh bin/vgshell-tui
set -euo pipefail
updates_dir="$home/.config/vgshell/plugins/vgs.updates"
updates_state="$home/.local/state/vgshell/updates-smoke"
updates_fixtures="$repo/scripts/smoke/fixtures/updates-bin"
if ! command -v unshare >/dev/null 2>&1 || ! unshare -rm true 2>/dev/null; then
  printf 'qml-smoke: status=not-measured missing=unprivileged-mount-namespace\n'
  exit 77
fi
mkdir -p "$updates_dir" "$updates_state"
cp -R "$repo/shell/plugins/vgs.updates/." "$updates_dir/"
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.updates')

# The stand-in git, alone in its own directory.
mkdir -p "$updates_state/git-bin"
cp -- "$updates_fixtures/git" "$updates_state/git-bin/git"

# One directory per identity: its os-release and the PATH `vgshell pkg` gets.
# `arch` holds the stand-in managers; `none` holds no manager at all.
updates_identity() { # NAME OS_ID STAND_INS...
  local dir="$updates_state/identity-$1" tool
  mkdir -p "$dir/bin"
  printf 'ID=%s\n' "$2" >"$dir/os-release"
  for tool in bash env readlink dirname flock setsid timeout mkdir cat sleep seq; do ln -sf -- "$(command -v "$tool")" "$dir/bin/$tool"; done
  ln -sf -- "$node_bin" "$dir/bin/node"
  shift 2
  for tool; do cp -- "$updates_fixtures/$tool" "$dir/bin/$tool"; done
}
updates_identity arch arch pacman checkupdates paru flatpak mise
updates_identity none opensuse-tumbleweed
use_identity() { printf '%s\n' "$1" >"$updates_state/identity"; }
use_identity arch

# The wrapper the service copy runs as its vgshell. bin/check finds the core's
# library loader beside the vgshell it is given, so the loader is linked in.
updates_vgshell="$updates_state/vgshell-bin/vgshell"
mkdir -p "$updates_state/vgshell-bin/lib"
ln -sf -- "$repo/bin/lib/qml-library.js" "$updates_state/vgshell-bin/lib/qml-library.js"
cat >"$updates_vgshell" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == pkg ]]; then
  identity="$updates_state/identity-\$(<"$updates_state/identity")"
  exec unshare -rm "\$identity/bin/bash" -c 'mount --bind "\$1/os-release" /etc/os-release && export PATH="\$1/bin" && shift && exec "\$@"' \\
    bash "\$identity" "$repo/bin/vgshell" "\$@"
fi
exec env PATH="$updates_state/git-bin:\$PATH" UPDATES_SMOKE_CHECKOUTS="$repo:$updates_dir" "$repo/bin/vgshell" "\$@"
EOF
chmod 755 "$updates_vgshell"

# The copy's two changes, each checked to apply once.
python3 - "$updates_dir" "$updates_vgshell" <<'PY'
import json, pathlib, sys
plugin, vgshell = pathlib.Path(sys.argv[1]), sys.argv[2]
manifest = plugin / "manifest.json"
doc = json.loads(manifest.read_text())
assert "finish" not in doc["tui"], doc["tui"]
doc["tui"]["finish"] = {"script": "tui/finish.sh", "title": "Updates smoke", "size": "default", "presentation": "plain", "entry": {"label": "Updates smoke", "icon": "terminal", "group": "Smoke"}}
manifest.write_text(json.dumps(doc))
assert sorted(doc["tui"]) == ["finish", "log", "review", "update", "update-source"], sorted(doc["tui"])
service = plugin / "Service.qml"
text = service.read_text()
needle = "    property var reported: ({})\n"
assert text.count(needle) == 1, text.count(needle)
text = text.replace(needle, needle + "    property int smokeReviewEndWrites: 0\n")
needle = '        onExited: (code, status) => {\n            if (code !== 0) console.error("updates: review end write exit=" + code);\n        }\n'
assert text.count(needle) == 1, text.count(needle)
text = text.replace(needle, '        onExited: (code, status) => {\n            root.smokeReviewEndWrites += 1;\n            if (code !== 0) console.error("updates: review end write exit=" + code);\n        }\n')
lines = text.splitlines()
hits = [i for i, line in enumerate(lines) if line.startswith("    readonly property string vgshellPath:")]
assert len(hits) == 1, hits
lines[hits[0]] = "    readonly property string vgshellPath: " + json.dumps(vgshell)
service.write_text("\n".join(lines) + "\n")
PY
mkdir -p "$updates_dir/tui"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.updates/tui/finish.sh" "$updates_dir/tui/finish.sh"
chmod 755 "$updates_dir/tui/finish.sh"

# The stand-in terminal with no window; the widget's rows below write it
# again with its window.
terminal_stand_in windowless

# The accepted status record, as every instance reads it.
updates_values() { ipc vgs.updates invoke status ''; }
updates_field() { updates_values | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }
updates_sources() { updates_values | py_reply 'import json,sys; print(json.dumps([[s["source"], s["count"], s["error"]] for s in json.load(sys.stdin).get("sources", [])]))'; }
updates_source_names() { updates_values | py_reply 'import json,sys; print(json.dumps([s["source"] for s in json.load(sys.stdin).get("sources", [])]))'; }
updates_failure_status() { updates_values | py_reply 'import json,sys
v=json.load(sys.stdin)
failed=[s["source"] for s in v.get("sources", []) if s.get("error")]
print(json.dumps([v.get("checkState", {}).get("tone"), failed]))'; }
# Whether the failing system row stays listed, with no count, beside AUR's.
updates_keeps_failed_row() { updates_sources | py_reply 'import json,sys; r=json.load(sys.stdin); print(any(s[0] == "pacman" and s[1] is None and s[2] for s in r) and ["aur", 1, None] in r)'; }
# SOURCE's [count, listed packages, more] in the accepted record.
updates_listed() { updates_values | py_reply 'import json,sys; r=[s for s in json.load(sys.stdin).get("sources", []) if s["source"]==sys.argv[1]]; print(json.dumps([r[0]["count"], len(r[0]["packages"]), r[0]["more"]] if r else None))' "$1"; }
# SOURCE's [count, packages] in status.json on disk.
updates_cached() { python3 -c 'import json,sys; r=[s for s in json.load(open(sys.argv[1]))["sources"] if s["source"]==sys.argv[2]]; print(json.dumps([r[0]["count"], len(r[0]["packages"])] if r else None))' "$home/.local/state/vgshell/updates/status.json" "$1"; }
updates_idle() { updates_values | py_reply 'import json,sys; print("checking" if json.load(sys.stdin).get("checking") else "idle")'; }
updates_status_rows() { settings_rows | py_reply 'import json,sys; rows=[p for p in json.load(sys.stdin) if p["id"]=="vgs.updates"][0]["status"]; print(json.dumps([[r["key"], r["report"]] for r in rows]))'; }
updates_widget_section() { ipc shell listShellConfig | py_reply 'import json,sys; l=json.load(sys.stdin)["bar"]["layout"]; print(([s for s in ("left","center","right") if any(e["id"]=="vgs.updates" for e in l.get(s,[]))] + ["none"])[0])'; }
updates_tui_running() { lent tui.runs | py_reply 'import json,sys; r=(json.load(sys.stdin) or {}).get("vgs.updates/finish"); print(json.dumps(r is not None and r.get("running") is not None))'; }
# Runs of one stand-in, from the log every stand-in appends to.
runs_of() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(0 if not p.exists() else sum(1 for l in p.read_text().splitlines() if l.split(" ")[0] == sys.argv[2]))' "$updates_state/calls.log" "$1"; }
package_queries() { echo "$(runs_of checkupdates) $(runs_of paru) $(runs_of flatpak) $(runs_of mise)"; }
checks() { runs_of checkupdates; }
# STEADY once the service is idle with WANT checks, else the current state.
checks_settle_at() { # WANT
  local got state
  state="$(updates_idle)" || return
  got="$(checks)"
  if [[ $state != idle ]]; then echo "$got ($state)"; return; fi
  if [[ $got != "$1" ]]; then echo "$got"; return; fi
  echo STEADY
}

# First check: no snapshot exists, so the service checks at start.
rm -rf -- "$home/.local/state/vgshell/updates"
rescan "rescan after adding the updates copy answers ok"
expect_poll "the updates copy is discovered" True plugin_known vgs.updates
# The first check runs `vgshell theme outdated`, which holds the theme lock
# shared, so it starts once the scan's theme follow has ended.
expect_poll "the scan's theme follow ends before the first check" idle theme_idle
expect "enabling the updates service is allowed" ok ipc shell setPluginEnabled vgs.updates true
expect_poll "the updates service is built" True record_exists vgs.updates
updates_tui_rows() { ipc shell listTuis | py_reply 'import json,sys; print(json.dumps(sorted([r["key"], r["group"]] for r in json.load(sys.stdin) if r["plugin"] == "vgs.updates")))'; }
expect "the pipeline is listed in the Update group and the one-source TUI is not listed" '[["vgs.updates/finish", "Smoke"], ["vgs.updates/update", "Update"]]' updates_tui_rows
expect_poll "the first check publishes every source vgshell reports" \
  '[["pacman", 2, null], ["aur", 1, null], ["flatpak", 1, null], ["mise", 1, null], ["vgs", 1, null], ["plugins", 1, null], ["themes", 0, null]]' updates_sources
expect "pending sums every source" 7 updates_field pending
expect "the first check ran each package query once" "1 1 1 1" package_queries
expect "status.json holds the same system rows" '[2, 2]' updates_cached pacman

# Reads are not checks.
for _ in 1 2 3; do updates_values >/dev/null; done
expect_poll "three reads start no check" STEADY checks_settle_at 1
expect "the Settings window opens for the updates rows" ok ipc shell summon window vgs.settings '{}'
expect_poll "the Settings window is open for the updates rows" open settings_open
expect "the Settings window opens the updates page" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.updates
expect_poll "the Settings page reads the four status rows" '[["pending", "reported"], ["lastCheck", "reported"], ["checkState", "reported"], ["reviewAgent", "reported"]]' updates_status_rows
expect_poll "the Settings page started no check" STEADY checks_settle_at 1
expect "the Settings window closes" ok ipc shell hide window vgs.settings

# A request during a check is queued once, not run beside it.
touch "$updates_state/slow-checkupdates"
expect "an on-demand check starts" started ipc vgs.updates invoke check ''
expect "a request during the check is queued" queued ipc vgs.updates invoke check ''
expect "a third request during the check joins the queued one" queued ipc vgs.updates invoke check ''
rm -f -- "$updates_state/slow-checkupdates"
expect_poll "the check and the one queued check both run" 3 checks
expect_poll "no third check follows" STEADY checks_settle_at 3
expect_poll "the service is idle after the queued check" idle updates_idle

# A failing source is named and kept beside the others.
touch "$updates_state/fail-checkupdates"
expect "a check with a failing system source starts" started ipc vgs.updates invoke check ''
expect_poll "the check state marks the failing source by typed source key" '["warning", ["pacman"]]' updates_failure_status
expect "the failing source stays listed with no count" True updates_keeps_failed_row
rm -f -- "$updates_state/fail-checkupdates"

# A list past the status ceiling: the record lists the first packages and
# counts the rest; status.json keeps every one.
touch "$updates_state/many-checkupdates"
expect "a check with 1400 system updates starts" started ipc vgs.updates invoke check ''
expect_poll "the record lists the first packages and counts the rest" '[1400, 12, 1388]' updates_listed pacman
expect "pending keeps the full count" 1405 updates_field pending
expect "status.json keeps every package" '[1400, 1400]' updates_cached pacman
rm -f -- "$updates_state/many-checkupdates"

# A TUI run's end starts one check; a running TUI starts none.
expect_poll "the TUI startup probe has answered" false lent tui.probing
if [[ "$(lent tui.launcher)" == '"missing"' ]]; then
  expect "a request on a host without a terminal refreshes the launcher" "refused: tui=vgs.updates/finish reason=launcher-missing" ipc shell openTui vgs.updates/finish
fi
expect_poll "the launcher state is present" '"present"' lent tui.launcher
expect_poll "the launcher refresh is idle" false lent tui.probing
rm -f -- "$updates_state/tui-gate"
before="$(checks)"
expect "opening the updates TUI answers ok" ok ipc shell openTui vgs.updates/finish
expect_poll "the updates TUI is running" true updates_tui_running
expect_poll "a running TUI starts no check" STEADY checks_settle_at "$before"
touch "$updates_state/tui-gate"
expect_run_end "the updates TUI's run ends" vgs.updates/finish
expect_poll "the TUI's end starts a check" "$((before + 1))" checks
expect_poll "the TUI's end starts exactly one check" STEADY checks_settle_at "$((before + 1))"
expect_poll "the service is idle after the TUI check" idle updates_idle

# ---- The bar widget and the window ------------------------------------------
# Enabling the plugin placed its widget in its default section. The
# stand-in terminal runs each TUI a button opens as `true`, which exits at
# once; its end starts one check of
# the service, so every button waits for its run to end and the service to
# go idle before the next.
terminal_stand_in
terminal_ready "updates widget"
widget_key="$(bar_key)"
expect "the updates widget is placed in its default section" right updates_widget_section
expect_poll "the updates widget is built on the bar" '"vgs.updates"' ipc smoke readInstance "$widget_key" vgs.updates moduleName
# The widget as it judges itself: [state, icon, tone, badge, badge tone].
widget_view() { ipc smoke readInstance "$widget_key" vgs.updates view | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v["state"], v["icon"], v["tone"], v["badge"], v["badgeTone"]]))'; }
# The widget as drawn: [the icon it shows, or `spinner`, the tone its
# colour is, the count it shows beside the icon, or ""]. A colour is read as the theme
# writes it and matched against the three the widget draws with.
widget_drawn() {
  local colours accent warning calm icon spinning badge
  colours="$(ipc smoke itemColours "$widget_key" vgs.updates BarItem Icon)" && accent="$(ipc smoke themeValue color.accent)" \
    && warning="$(ipc smoke themeValue color.warning)" && calm="$(ipc smoke themeValue bar.foreground)" \
    && icon="$(ipc smoke readDescendant "$widget_key" vgs.updates Icon name)" && spinning="$(ipc smoke readDescendant "$widget_key" vgs.updates Spinner visible)" \
    && badge="$(ipc smoke readDescendant "$widget_key" vgs.updates BarItem count)" || return
  python3 -c '
import json, sys
colours, accent, warning, calm, icon, spinning, badge = (json.loads(a) for a in sys.argv[1:])
portable = lambda c: "#" + c[3:] + c[1:3]
tones = {portable(accent): "accent", portable(warning): "warning", portable(calm): "calm"}
drawn = [c for button in colours for c in button]
if spinning:
    print(json.dumps(["spinner", None if not drawn else drawn, badge]))
else:
    print(json.dumps([icon, tones.get(drawn[0], drawn[0]) if len(drawn) == 1 else drawn, badge]))' \
    "$colours" "$accent" "$warning" "$calm" "$icon" "$spinning" "$badge"
}
widget_visible() { ipc smoke readInstance "$widget_key" vgs.updates visible; }
# The tooltip's title and details but the last detail, the check's time,
# which moves; and whether that last detail names a time.
widget_tip_values() { ipc smoke readDescendant "$widget_key" vgs.updates Tooltip details | py_reply 'import json,sys
d=json.load(sys.stdin)
print(json.dumps([row.get("value") for row in d[:-1] if isinstance(row, dict)]))'; }
widget_tip_failed_indexes() { ipc smoke readDescendant "$widget_key" vgs.updates Tooltip details | py_reply 'import json,sys
d=json.load(sys.stdin)
print(json.dumps([i for i, row in enumerate(d[:-1]) if isinstance(row, dict) and not isinstance(row.get("value"), (int, float))]))'; }
widget_tip_last() { ipc smoke readDescendant "$widget_key" vgs.updates Tooltip details | py_reply 'import json,sys; d=json.load(sys.stdin); print(bool(d and isinstance(d[-1], str) and d[-1]))'; }
updates_focused() { ipc smoke focused window vgs.updates | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(t if not t.startswith("[") else json.dumps([json.loads(t)[2], json.loads(t)[3], json.loads(t)[4]]))'; }
# hideWhenCurrent in the widget's layout entry of the user file, written
# whole and moved into place.
widget_hide_when_current() { # true|false
  python3 -c '
import json, os, sys
path, want = sys.argv[1], sys.argv[2] == "true"
doc = json.load(open(path))
entries = [e for e in doc["bar"]["layout"]["right"] if e["id"] == "vgs.updates"]
assert len(entries) == 1, entries
entries[0]["hideWhenCurrent"] = want
open(path + ".next", "w").write(json.dumps(doc))
os.replace(path + ".next", path)' "$home/.config/vgshell/shell.json" "$1"
}
widget_setting() { ipc smoke readInstance "$widget_key" vgs.updates settings | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("hideWhenCurrent")))'; }
updates_rows() { ipc smoke readInstance window vgs.updates rows | py_reply 'import json,sys
rows=json.load(sys.stdin)
print(json.dumps([[r["source"], r["updatable"], len(r["lines"]), bool(r["more"])] for r in rows]))'; }
updates_package_lines() { ipc smoke descendantGeometry window vgs.updates | py_reply 'import json,sys
rows=json.load(sys.stdin)
print(sum(1 for r in rows if r["type"] == "Label" and r.get("role") == "itemCode" and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0))'; }
updates_open() { [[ $(ipc smoke readInstance window vgs.updates rows) != absent ]] && echo open || echo closed; }
# Open the window with a click on the widget, unless it is open: the
# click toggles it, and a TUI's window leaves it open.
open_updates() {
  [[ $(updates_open) == open ]] && return 0
  click_centre "$widget_key" vgs.updates || fail "the click on the updates widget failed"
  expect_poll "the widget's click opens the Updates window" open updates_open
}
# A fresh Updates window, summoned over IPC, with the keyboard: an open
# one keeps the focus item its last key left, so it is hidden first.
fresh_updates() { # LABEL
  expect "the Updates window is closed before $1" ok ipc shell hide window vgs.updates
  expect_poll "no Updates window is left before $1" 0 window_count Updates
  expect "the Updates window opens for $1" ok ipc shell summon window vgs.updates '{}'
  updates_keyboard "$1"
}
updates_keyboard() { # LABEL
  expect_poll "the Updates window is focused for $1" "[\"$shell_class\", \"Updates\"]" active_window
  expect_poll "the shell reads the Updates window holding the keyboard for $1" true window_keyboard vgs.updates
}
# The words after the presenter's `--`, the last `--` in the record: the
# script's file name and its arguments, as JSON; `absent` before a record
# exists, and `partial` for a record with no `--` or nothing after it.
launched() { recorded | py_reply 'import json,os,sys
w=json.load(sys.stdin)
a=w[len(w) - w[::-1].index("--"):] if "--" in w else []
if not a: print("partial"); sys.exit()
print(json.dumps([os.path.basename(a[0])] + a[1:]))'; }
# Click the window's button reading TEXT, read the argv it launched, WANT,
# and wait for its run of KEY, and the check its end starts, to end.
press_and_launch() { # TEXT KEY WANT
  local before
  open_updates
  forget_record
  before="$(checks)"
  click_in window:Updates window vgs.updates Button "$1" || fail "the click on the window's $1 failed"
  expect_poll "the window's $1 opens its TUI with its argv" "$3" launched
  expect_run_end "the window's $1 run ends" "$2"
  expect_poll "the $1 run's end starts one check" "$((before + 1))" checks
  expect_poll "the service is idle after the $1 run" idle updates_idle
}

# Controls for launched and for the pollers' traceback rule. Until the
# terminal stand-in writes its record the reader answers absent, and a
# record cut before the script, or an empty one, answers partial, so a
# poll that starts before the record is written retries on a state word.
# A reader of the old shape parses `absent` as JSON and raises; the poll
# over it runs in a subshell whose failure count is its answer, its lines
# kept aside, so the traceback lands there and not in the smoke's log.
forget_record
expect "with no record the launch reader answers absent" absent launched
printf '%s\n' "--app-id=vgs-tui" "--title=VGS · Updates" >"$tui_record"
expect "a record cut before its script reads partial" partial launched
printf '%s\n' "--app-id=vgs-tui" "--title=VGS · Updates" -- >"$tui_record"
expect "a record that ends at its separator reads partial" partial launched
: >"$tui_record"
expect "an empty record reads partial" partial launched
forget_record
old_launched() { python3 -c 'import json,os,sys; w=json.loads(sys.argv[1]); a=w[len(w) - 1 - w[::-1].index("--") + 1:]; print(json.dumps([os.path.basename(a[0])] + a[1:]))' "$(recorded)"; }
old_reader_poll() { (failures=0 behaviour_failures=0; expect_poll "the old launch reader" '["update.sh"]' old_launched >"$sandbox/reader-traceback-control.log"; echo "$failures"); }
expect "control: a poll whose reader raises on an absent record fails once" 1 old_reader_poll
expect "control: the failed poll names the reader's traceback" 1 grep -c -F -- "the old launch reader: the reader raised a Python traceback" "$sandbox/reader-traceback-control.log"
expect "control: the failed poll prints the traceback under its row" 1 grep -c -x -F -- "        Traceback (most recent call last):" "$sandbox/reader-traceback-control.log"

# Controls for smoke_row's traceback rule (harness.sh), over rows planted
# in the sandbox: a reader of a planted reply run outside every expect that raises
# fails its row once, naming it; the same reader answering a state word
# fails nothing; a row that sends its own output elsewhere hides the end
# marker, and the bound fails it. Each runs in a subshell whose failure
# count is its answer and whose lines go to their own file, so the
# planted traceback never reaches this row's output.
row_plants="$sandbox/row-plants"
mkdir -p -- "$row_plants"
cat >"$row_plants/updates-traceback-plant.sh" <<'SH'
printf '{}\n' | py_reply 'import json,sys; print(json.load(sys.stdin)["no-such-field"])' || true
SH
cat >"$row_plants/updates-traceback-clean.sh" <<'SH'
printf '{}\n' | py_reply 'import json,sys; print(json.load(sys.stdin).get("no-such-field", "absent"))' || true
SH
cat >"$row_plants/updates-undrained.sh" <<'SH'
exec >/dev/null 2>&1
SH
planted_row() { # NAME
  (failures=0 behaviour_failures=0 smoke_row_drain_s=1; smoke_row "$1" "$row_plants" >"$sandbox/row-plant-$1.log" 2>&1; echo "$failures")
}
expect "control: a planted row whose reader raises outside every expect fails once" 1 planted_row updates-traceback-plant
expect "control: the planted row's failure names it and its traceback count" 1 grep -c -F -- "FAIL  updates-traceback-plant: its output holds 1 Python traceback(s)" "$sandbox/row-plant-updates-traceback-plant.log"
expect "control: the same reader answering a state word fails nothing" 0 planted_row updates-traceback-clean
expect "control: a planted row that hides its end marker fails once at the bound" 1 planted_row updates-undrained
expect "control: the undrained row's failure names it" 1 grep -c -F -- "FAIL  updates-undrained: its output did not drain within 1s" "$sandbox/row-plant-updates-undrained.log"

# Pending, from the last real check.
expect_poll "a pending check draws the accent count" '["pending", "refresh-cw", "accent", "7", "accent"]' widget_view
expect "the widget draws the icon in the accent colour with the count" '["refresh-cw", "accent", "7"]' widget_drawn
expect "the tooltip lists every source's count" '[2, 1, 1, 1, 1, 1, 0]' widget_tip_values
expect "the tooltip ends with the check's time" True widget_tip_last

# The window: one row per source with its count and its own Update when it
# has updates; a click on a row lists its packages.
# Keyboard-only path.
expect "the Updates window is closed before the keyboard path" ok ipc shell hide window vgs.updates
expect "the updates shortcut opens the window" ok hypr dispatch 'hl.dsp.global("vgs.updates:toggle")'
updates_keyboard "the shortcut's keys"
expect_poll "the shortcut opens with a visible focus ring in view" '[true, true, true]' updates_focused
forget_record
type_keys -k Left || fail "sending Left to the updates row control failed"
type_keys -k Space || fail "sending Space to expand the first updates row failed"
expect_poll "Space expands the first updates row's package lines" 2 updates_package_lines
expect "control: Left on the source row runs no TUI" absent launched
forget_record
type_keys -k Tab -k Return || fail "sending Tab and Return to the source Update button failed"
expect_poll "Return on the source Update button opens the source update TUI" '["update-source.sh", "pacman"]' launched
expect_run_end "the keyboard source Update run ends" vgs.updates/update-source
expect_poll "the service is idle after the keyboard source update run" idle updates_idle
fresh_updates "the Update everything keyboard path"
expect_poll "the reopened Updates window starts with a visible focus ring in view" '[true, true, true]' updates_focused
forget_record
type_keys -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Tab -k Return || fail "sending Tab and Return to Update everything failed"
expect_poll "Return on Update everything opens the update TUI with no argument" '["update.sh"]' launched
expect_run_end "the keyboard Update everything run ends" vgs.updates/update
expect_poll "the service is idle after the keyboard update run" idle updates_idle
fresh_updates "Escape"
type_keys -k Escape || fail "sending Escape to the Updates window failed"
expect_poll "Escape closes the Updates window" closed updates_open
# The window is a Hyprland window like any other: its border, a move and
# the keyboard, as app_window_rows reads every application window.
expect "the Updates window opens for the window rows" ok ipc shell summon window vgs.updates '{}'
app_window_rows Updates vgs.updates
open_updates
expect_poll "the window draws one row per source" \
  '[["pacman", true, 2, false], ["aur", true, 1, false], ["flatpak", true, 1, false], ["mise", true, 1, false], ["vgs", true, 1, false], ["plugins", true, 1, false], ["themes", false, 0, false]]' updates_rows
click_in window:Updates window vgs.updates ListItem System || fail "the click on the window's System row failed"
expect_poll "a click on a row lists its packages" 2 updates_package_lines
# The window's geometry with a row expanded: each source row's last
# trailing item, the chevron, the Update button or the count badge, ends on
# that row's right content edge. The footer's buttons lie inside the
# window, below its body, while the body scrolls. Each check holds within
# one pixel. The footer's controls are the unit mutations of tst_pane (the
# footer outside the body); the row-edge control moves one trailing item 8
# px left in a copy of the same reading, which the check refuses. `[]` is
# the pass.
updates_geometry() {
  local rows
  rows="$(ipc smoke descendantGeometry window vgs.updates)" || return
  python3 - "$rows" "${1:-}" <<'PY'
import json, sys
# A failure word from the probe is the answer, never a traceback.
if not sys.argv[1].startswith("["):
    print(json.dumps(["unread=%s" % sys.argv[1]])); sys.exit()
rows, plant = json.loads(sys.argv[1]), sys.argv[2] == "shift"
out = []
def inside(j, i):
    while j != -1:
        if j == i: return True
        j = rows[j]["parent"]
    return False
def shown(r): return r["box"][2] > 0 and r["box"][3] > 0
# A hidden item keeps its last box, so a drawn item is shown and visible.
def drawn(r): return shown(r) and r.get("visible", True)
panel = rows[0]["box"]
sources = [i for i, r in enumerate(rows) if r["type"] == "Disclosure" and shown(r)]
bad = []
for n, i in enumerate(sources):
    items = [j for j, r in enumerate(rows) if r["type"] == "ListItem" and inside(j, i) and shown(r)]
    if len(items) != 1: out.append("row%d listItems=%d" % (n, len(items))); continue
    item = rows[items[0]]
    controls = [(j, rows[j]) for j, r in enumerate(rows) if r["type"] in ("Badge", "Button", "Icon") and inside(j, items[0]) and drawn(r)]
    icons = [r for _, r in controls if r["type"] == "Icon"]
    if not icons: out.append("row%d icons=0" % n); continue
    lead = min(icons, key=lambda r: r["box"][0])
    pad = lead["box"][0] - item["box"][0]
    want = item["box"][0] + item["box"][2] - pad
    trailing = [r for _, r in controls if r is not lead]
    if not trailing: out.append("row%d trailing=0" % n); continue
    got = max(r["box"][0] + r["box"][2] for r in trailing) - (8 if plant and n == 0 else 0)
    if abs(got - want) > 1: bad.append("row%d.trailing=%.2f want=%.2f" % (n, got, want))
if len(sources) < 2: out.append("rows=%d" % len(sources))
out += bad
buttons = [r for j, r in enumerate(rows) if r["type"] == "Button" and shown(r) and not any(inside(j, i) for i in sources)]
if len(buttons) < 3: out.append("buttons=%d" % len(buttons))
for n, r in enumerate(buttons):
    b = r["box"]
    if b[1] < panel[1] - 1 or b[1] + b[3] > panel[1] + panel[3] + 1:
        out.append("button%d.y=%.2f-%.2f panel=%.2f-%.2f" % (n, b[1], b[1] + b[3], panel[1], panel[1] + panel[3]))
print(json.dumps(out))
PY
}
geometry expect_poll "the window's trailing items end on their row edge and its footer stays inside it" '[]' updates_geometry
updates_shifted() { updates_geometry shift | py_reply 'import json,sys; print(any(".trailing=" in e for e in json.load(sys.stdin)))'; }
expect "control: a trailing item moved off its row edge is refused" True updates_shifted

# A monitor too short and narrow for the window, 480 by 360: the window
# asks for the output less `size.window.gutter` a side, lays out at that
# size, its body scrolls and its footer stays inside it. The held mode is released after, so later rows meet the
# monitor they read at the start. The size rule's control widens the
# window's reading by 8 px, which the check refuses. `[]` is the pass.
mode_logical_size() { # MODE SCALE
  python3 -c 'import sys; w,h=map(int, sys.argv[1].split("x")); scale=float(sys.argv[2]); print(round(w / scale), round(h / scale))' "$1" "$2"
}
short_mode=480x360
short_scale=1
read -r short_logical_w short_logical_h < <(mode_logical_size "$short_mode" "$short_scale")
short_monitor="$(first_name)" || fail "the monitor is unreadable"
short_main_mode="$(first_mode)" || fail "the monitor's mode is unreadable"
short_gutter="$(ipc smoke themeValue size.window.gutter)" || { fail "the gutter token is unreadable"; short_gutter=unreadable; }
short_saved_logical_w="$(first_width)" || short_saved_logical_w=unreadable
expect "the window hides before the short monitor" ok ipc shell hide window vgs.updates
expect_poll "the window is closed before the short monitor" closed updates_open
hold_mode "the nested compositor makes its monitor short and narrow" "$short_monitor" "$short_mode" "$short_scale"
expect_poll "the monitor is the held logical width" "$short_logical_w" first_width
# The pointer helpers take the held size while it holds.
short_saved_w="$mon_w" short_saved_h="$mon_h"
mon_w="$short_logical_w" mon_h="$short_logical_h"
open_updates
window_room() { # [PLANT]
  python3 - "$(ipc smoke instanceGeometry window vgs.updates)" "$short_gutter" "$short_logical_w" "$short_logical_h" "${1:-}" <<'PY'
import json, sys
if not sys.argv[1].startswith("[") or not sys.argv[2].isdigit() or not sys.argv[3].isdigit() or not sys.argv[4].isdigit():
    print(json.dumps(["window=%s gutter=%s monitor=%sx%s" % (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])])); sys.exit()
box, gutter, monitor_w, monitor_h, plant = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5] == "wide"
x, y, w, h = json.loads(box)
if plant: w += 8
out = []
if w > monitor_w - 2 * gutter + 1: out.append("width=%d room=%d" % (w, monitor_w - 2 * gutter))
if h > monitor_h - 2 * gutter + 1: out.append("height=%d room=%d" % (h, monitor_h - 2 * gutter))
print(json.dumps(out))
PY
}
window_widened() { window_room wide | py_reply 'import json,sys; print(any(e.startswith("width=") for e in json.load(sys.stdin)))'; }
geometry expect_poll "the window keeps the room of a short, narrow monitor" '[]' window_room
expect "control: a window wider than the room is refused" True window_widened
geometry expect_poll "the window's footer stays inside it on the short monitor" '[]' updates_geometry
expect "the window hides before the monitor's mode returns" ok ipc shell hide window vgs.updates
expect_poll "the window is closed before the monitor's mode returns" closed updates_open
release_mode "the nested compositor restores its monitor's mode" "$short_monitor" "$short_main_mode"
mon_w="$short_saved_w" mon_h="$short_saved_h"
expect_poll "the monitor has its logical width back" "$short_saved_logical_w" first_width

# Each button's argv, as the terminal stand-in records it. The first
# Update is the System row's.
press_and_launch Update vgs.updates/update-source '["update-source.sh", "pacman"]'
press_and_launch "Update everything" vgs.updates/update '["update.sh"]'
press_and_launch "Open last log" vgs.updates/log '["log.sh"]'
before="$(checks)"
forget_record
expect "the widget's middle-click function opens the update TUI" ok ipc smoke invokeInstance "$widget_key" vgs.updates updateAll ''
expect_poll "the widget opens the update TUI with no argument" '["update.sh"]' launched
expect_run_end "the widget's update run ends" vgs.updates/update
expect_poll "the widget's run's end starts one check" "$((before + 1))" checks
expect_poll "the service is idle after the widget's run" idle updates_idle
open_updates
before="$(checks)"
click_in window:Updates window vgs.updates Button Refresh || fail "the click on the window's Refresh failed"
expect_poll "Refresh starts the service's check" "$((before + 1))" checks
expect_poll "Refresh starts one check" STEADY checks_settle_at "$((before + 1))"
expect_poll "the service is idle after Refresh" idle updates_idle
expect "the window closes" ok ipc shell hide window vgs.updates

# Checking: the spinner stands in for the icon, the count stays.
touch "$updates_state/slow-checkupdates"
expect "a held check starts" started ipc vgs.updates invoke check ''
expect_poll "a running check spins" '["checking", "refresh-cw", "calm", "7", "accent"]' widget_view
expect "the widget draws the spinner with the count" '["spinner", null, "7"]' widget_drawn
rm -f -- "$updates_state/slow-checkupdates"
expect_poll "the service is idle after the held check" idle updates_idle

# Failed: a failing source draws the warning tone, and hideWhenCurrent
# does not hide it.
touch "$updates_state/fail-checkupdates"
expect "a check with a failing system source starts for the widget" started ipc vgs.updates invoke check ''
expect_poll "a failed source draws the warning" '["attention", "triangle-alert", "warning", "5", "warning"]' widget_view
expect "the widget draws the warning icon with the count" '["triangle-alert", "warning", "5"]' widget_drawn
expect "the tooltip marks the failed source at its source order" '[0]' widget_tip_failed_indexes
widget_hide_when_current true
expect_poll "the widget reads hideWhenCurrent" true widget_setting
expect "hideWhenCurrent leaves a failed check shown" true widget_visible

# Control: a copy of the widget's judge that hides on a failed check reads
# hidden, so the readback above catches a widget that hides it.
updates_logic="$updates_dir/UpdatesLogic.js"
cp -- "$updates_logic" "$updates_state/UpdatesLogic.js.shipped"
python3 -c '
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "hidden: hideWhenCurrent === true && state === \"current\""
assert text.count(needle) == 1, text.count(needle)
path.write_text(text.replace(needle, "hidden: hideWhenCurrent === true && state !== \"checking\""))' "$updates_logic"
before="$(checks)"
rescan "rescan after planting the hiding widget answers ok"
expect_poll "the hiding widget reads the failed check" '["attention", "triangle-alert", "warning", "5", "warning"]' widget_view
expect_poll "the control: a widget that hides on a failed check reads hidden" false widget_visible
cp -- "$updates_state/UpdatesLogic.js.shipped" "$updates_logic"
rescan "rescan after restoring the widget answers ok"
expect_poll "the restored widget shows the failed check" true widget_visible
expect_poll "the restored service publishes the failed check" '["attention", "triangle-alert", "warning", "5", "warning"]' widget_view
# A rebuilt service publishes its cache and starts no check: not for the
# TUI runs an earlier instance saw end, and not while its cache read has not
# answered. The controls of both are scripts/test-updates-logic.js's.
expect_poll "a rebuilt service starts no check" STEADY checks_settle_at "$before"
rm -f -- "$updates_state/fail-checkupdates"

# Stale and current, written through the service's own provider.
expect "the probe keeps the updates service's status provider" held ipc smoke holdStatus service vgs.updates
expect "a stale check is written" ok ipc smoke heldStatusSet checkState '{"tone":"warning","text":"Check stale"}'
expect "nothing waiting is written" ok ipc smoke heldStatusSet pending 0
expect_poll "a stale check draws the warning" '["attention", "triangle-alert", "warning", "", "warning"]' widget_view
expect "the widget draws the warning icon with no count" '["triangle-alert", "warning", ""]' widget_drawn
expect "hideWhenCurrent leaves a stale check shown" true widget_visible
expect "a current check is written" ok ipc smoke heldStatusSet checkState '{"tone":"ok","text":"Up to date"}'
expect_poll "hideWhenCurrent hides a current widget" false widget_visible
expect "a current widget judges itself calm" '["current", "refresh-cw", "calm", "", "neutral"]' widget_view
widget_hide_when_current false
expect_poll "the widget reads hideWhenCurrent off" false widget_setting
expect_poll "a current widget shows with hideWhenCurrent off" true widget_visible
expect "the widget draws the calm icon with no count" '["refresh-cw", "calm", ""]' widget_drawn

# A rebuild publishes the cached snapshot, the failed check's, again, and a
# check brings the rows below back to the stand-ins' answers.
expect "disabling the updates plugin drops the written values" ok ipc shell setPluginEnabled vgs.updates false
expect "enabling the updates plugin again is allowed" ok ipc shell setPluginEnabled vgs.updates true
expect_poll "the rebuilt service publishes the cached failed check" '["attention", "triangle-alert", "warning", "5", "warning"]' widget_view
expect "a check after the rebuild starts" started ipc vgs.updates invoke check ''
expect_poll "the check publishes the pending count again" '["pending", "refresh-cw", "accent", "7", "accent"]' widget_view
expect_poll "the service is idle after the rebuild's check" idle updates_idle

# Control: a copy that checks per widget probes once per bar.
updates_control="$home/.config/vgshell/plugins/acme.updates-control"
mkdir -p "$updates_control"
cat >"$updates_control/manifest.json" <<'JSON'
{ "schemaVersion": 1, "id": "acme.updates-control", "name": "Updates control", "version": "0.1.0", "author": "acme", "description": "A copy of the updates check that every widget runs itself", "kinds": ["bar-widget"], "entryPoints": { "bar-widget": "Widget.qml" }, "defaultSection": "right" }
JSON
control_command="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$updates_dir/bin/check" --vgshell "$updates_vgshell")"
cat >"$updates_control/Widget.qml" <<EOF
import QtQuick
import qs.Ui
import Quickshell.Io
BarWidget {
    property var shell: null
    Process {
        running: true
        command: $control_command
    }
}
EOF
# A new bar widget lands enabled and placed on discovery, so its widgets
# check as the scan builds them: the monitor and its bar come first and
# the count is read before the scan.
control_output=SMOKE-UPDATES-CONTROL
expect "the nested compositor adds a monitor for the control" ok hypr output create headless "$control_output"
expect_poll "the control monitor gets a bar" "$((monitors + 1))" bar_count
before="$(checks)"
rescan "rescan after adding the per-widget control answers ok"
expect_poll "the per-widget control lands enabled, as a new bar widget does" True plugin_enabled acme.updates-control
expect_poll "the scan's theme follow ends before the per-widget control checks" idle theme_idle
control_widgets() { ipc shell built | py_reply 'import json,sys; print(sum(1 for rows in json.load(sys.stdin).values() for r in rows if r["id"] == "acme.updates-control"))'; }
expect_poll "the control is built on every bar" "$((monitors + 1))" control_widgets
expect_poll "the control probes once per widget, not once per check" "$((before + monitors + 1))" checks
expect "disabling the per-widget control is allowed" ok ipc shell setPluginEnabled acme.updates-control false
expect "the nested compositor removes the control monitor" ok hypr output remove "$control_output"
expect_poll "the control monitor's bar is gone" "$monitors" bar_count

# ---- The third-party review's window ----------------------------------------
# The stand-in agent takes this row's state directory as its first word,
# records the rest of its argv but the prompt, whether the prompt is the
# bundled one with the review directory filled in, and the directory it
# runs in, and then waits for the gate,
# up to 2400 polls of 0.05 s, a ceiling past the reads below and not a
# measurement, before it writes a clean verdict and exits.
review_fixture="$repo/scripts/smoke/fixtures/tui/vgs.updates/tui/review.sh"
same_review_script() { if cmp -s -- "$review_fixture" "$repo/shell/plugins/vgs.updates/tui/review.sh"; then echo same; else echo differs; fi; }
expect "the review fixture is the shipped review script, byte for byte" same same_review_script
review_start="$updates_state/review"
review_dir="$review_start/smoke"
review_bin="$updates_state/review-bin"
rm -rf -- "${review_start:?}" "${review_bin:?}"
rm -f -- "$updates_state/review-gate" "$updates_state/review-argv" "$updates_state/review-prompt" "$updates_state/review-cwd"
mkdir -p -- "$review_dir" "$review_bin"
python3 - "$updates_dir/review/third-party.md" "$review_dir" "$updates_state/review-prompt.expected" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[3]).write_text(pathlib.Path(sys.argv[1]).read_text().replace("{review_dir}", sys.argv[2]))
PY
cat >"$review_bin/agent" <<'SH'
#!/bin/sh
state="$1"
shift
n=$#
i=0
: >"$state/review-argv.next"
for a; do i=$((i + 1)); [ "$i" -lt "$n" ] && printf '%s\n' "$a" >>"$state/review-argv.next"; done
mv -f -- "$state/review-argv.next" "$state/review-argv"
eval "last=\${$n}"
if [ "$last" = "$(cat "$state/review-prompt.expected")" ]; then echo same; else echo differs; fi >"$state/review-prompt"
pwd >"$state/review-cwd"
review_dir="$(printf '%s\n' "$last" | sed -n 's|^The review directory is `\(.*\)`. The files below are in it\. Read and write paths relative to that directory\.$|\1|p' | sed -n '1p')"
polls=0
while [ ! -e "$state/review-gate" ] && [ "$polls" -lt 2400 ]; do sleep 0.05; polls=$((polls + 1)); done
[ -z "$review_dir" ] || printf 'verdict clean\n' >"$review_dir/verdict"
SH
chmod 755 "$review_bin/agent"
printf '%s\n' "$review_bin/agent" "$updates_state" --effort medium >"$review_dir/command"
printf 'aur tool-bin 1.0-1 1.1-1\n' >"$review_dir/packages.txt"
review_file() { if [[ -f $1 ]]; then cat -- "$1"; else echo absent; fi; } # FILE
review_argv() { python3 -c 'import json,os,sys; p=sys.argv[1]; print(json.dumps(open(p).read().split("\n")[:-1]) if os.path.exists(p) else "absent")' "$updates_state/review-argv"; }
review_window() { hypr -j clients | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui.tall" and c["title"] == "VGS · Review third-party packages"))'; }
review_started() { if [[ -e $review_dir/started ]]; then echo started; else echo waiting; fi; }
review_end_writes() { ipc smoke readInstance service vgs.updates smokeReviewEndWrites; }
before="$(checks)"
expect "the review handler opens the review TUI" ok ipc vgs.updates invoke review "$review_dir"
expect_poll "the shipped review script holds its lock and says it started" started review_started
expect_poll "the review TUI's window is open" 1 review_window
expect_poll "the agent runs from the review start directory" "$review_start" review_file "$updates_state/review-cwd"
expect "the agent gets the command's words" '["--effort", "medium"]' review_argv
expect "the agent's last argument is the bundled prompt" same review_file "$updates_state/review-prompt"
expect "no end is written while the review runs" absent review_file "$review_dir/ended"
touch -- "$updates_state/review-gate"
expect_run_end "the review run ends" vgs.updates/review
expect_poll "the review TUI's window closes with its run" 0 review_window
expect_poll "the service writes the run's code into the review directory" code=0 review_file "$review_dir/ended"
expect_poll "the review end writer exited" 1 review_end_writes
expect "the agent's verdict is in the review directory" "verdict clean" review_file "$review_dir/verdict"
expect_poll "the review run's end starts no check, which the update run's own end starts" STEADY checks_settle_at "$before"
# A run that ends after the pipeline removed its directory, as one the user
# leaves from the agent's closing prompt does, leaves no directory behind:
# the service writes `ended` only into a directory that is there. The copied
# service counts that guarded writer's exit, so the absence read follows it.
rm -f -- "${updates_state:?}/review-gate"
mkdir -p -- "$review_dir"
printf '%s\n' "$review_bin/agent" "$updates_state" --effort medium >"$review_dir/command"
review_writes_before="$(review_end_writes)"
expect "the review handler opens a second review" ok ipc vgs.updates invoke review "$review_dir"
expect_poll "the second review's script started" started review_started
rm -rf -- "${review_dir:?}"
touch -- "$updates_state/review-gate"
expect_run_end "the second review run ends" vgs.updates/review
expect_poll "the second review TUI's window closes with its run" 0 review_window
expect_poll "the second review end writer exited" "$((review_writes_before + 1))" review_end_writes
review_gone() { if [[ -e $review_dir ]]; then echo present; else echo absent; fi; }
expect "the run's end does not make its removed directory again" absent review_gone
rm -rf -- "${review_start:?}" "${review_bin:?}"
rm -f -- "$updates_state/review-gate" "$updates_state/review-argv" "$updates_state/review-prompt" "$updates_state/review-prompt.expected" "$updates_state/review-cwd"

# No manager detected: only the VGS rows remain.
use_identity none
before="$(checks)"
expect "a check with no package manager starts" started ipc vgs.updates invoke check ''
expect_poll "with no manager detected only the VGS rows remain" '["vgs", "plugins", "themes"]' updates_source_names
expect_poll "no package query ran" STEADY checks_settle_at "$before"

# Leave the later rows the shipped plugin, disabled.
expect "disabling the updates service is allowed" ok ipc shell setPluginEnabled vgs.updates false
rm -rf -- "$updates_dir" "$updates_control"
rescan "rescan after removing the updates copies answers ok"
expect_poll "the updates control is gone" False plugin_known acme.updates-control
