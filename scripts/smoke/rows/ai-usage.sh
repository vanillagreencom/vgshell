# AI Usage over a Claude Code and a Codex account the row plants in the
# sandbox HOME. The sandbox's copy of the usage helper reaches the stand-in
# endpoint scripts/fixtures/ai-usage/endpoint.js on 127.0.0.1, its origin
# constant edited through scripts/smoke/fixtures/ai-usage/edit.py, and the
# shell's PATH, which holds no host claude or codex (qml-smoke.sh's
# shell_hidden_commands), finds the stand-in scripts/fixtures/ai-usage/codex
# and a claude the row plants. Both stand-ins answer reset times relative
# to each request. It reads the Settings page's Sign in per tool, withheld
# while that tool is missing, whose TUI the stand-in terminal records; the
# widget's share, tone and hidden state; the panel's rows, notes, figure
# ages, reset times and height cap, half its output's logical height; that
# opening the panel publishes no read and sends the endpoint no request;
# the panel's Settings gear, which always-on Plugins gives every panel,
# clicked with the nested pointer, which opens the Settings window on AI Usage's page and closes the panel;
# the panel's Check now, clicked with the nested pointer, which publishes a
# read and sends the endpoint a request; a 429 from the endpoint's limited
# mode on that Check now, which keeps the figures, marked limited, with a
# plain note and no warning, then ten opens and closes of the panel that
# send no request; a refused token's expired warning and a failed
# request's stale figures; and that no read changed a credential file's
# bytes or modification time.
# Controls: a widget copy shown with no account, a panel copy capped at its
# output's whole height, a panel copy whose open asks for a read, a panel
# copy whose Check now asks for none, a helper copy that writes the
# credential file, one that reads a failed request as 0 % and a panel host
# copy whose slot opens Settings with no page each fail their own reading.
# This row has no latency ceiling; every reading polls through expect_poll.
# inputs: shell/plugins/vgs.ai-usage/* bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js bin/lib/qml-library.js shell/Commons/AccountDirectories.js scripts/fixtures/ai-usage/* scripts/smoke/fixtures/ai-usage/* shell/plugins/vgs.settings/* shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml shell/Core/Capabilities.qml shell/Core/Registry.qml shell/Hosts/PluginSlot.qml shell/Hosts/SummonPopup.qml shell/Ui/layout/Pane.qml shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Ui/feedback/Badge.qml shell/Ui/feedback/ProgressBar.qml shell/Commons/Time.qml config/shell.json bin/vgshell-tui scripts/qml-smoke.sh shell/Commons/Duration.js shell/Commons/qmldir
set -euo pipefail
usage_dir="$sandbox/ai-usage"
mkdir -p -- "$usage_dir"
usage_plugin="$repo/shell/plugins/vgs.ai-usage"
usage_helper="$usage_plugin/backend/usage.js"
usage_widget="$usage_plugin/Widget.qml"
usage_panel_qml="$usage_plugin/Panel.qml"
usage_saved="$usage_dir/shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$usage_saved"
cp -- "$usage_helper" "$usage_dir/usage.js.original"
cp -- "$usage_widget" "$usage_dir/Widget.qml.original"
cp -- "$usage_panel_qml" "$usage_dir/Panel.qml.original"
usage_edit() { python3 "$source_repo/scripts/smoke/fixtures/ai-usage/edit.py" "$@"; }
usage_mode() { printf '%s\n' "$1" >"$usage_dir/mode"; }
usage_mode relative
"$node_bin" "$source_repo/scripts/fixtures/ai-usage/endpoint.js" "$usage_dir/port" "$usage_dir/mode" "$usage_dir/requests" &
usage_endpoint=$!
usage_port() { if [[ -s $usage_dir/port ]]; then echo ready; else echo waiting; fi; }
expect_poll "the stand-in usage endpoint listens" ready usage_port
usage_origin="http://127.0.0.1:$(cat -- "$usage_dir/port")"
usage_edit "$usage_helper" 'const ORIGIN = "https://api.anthropic.com";' "const ORIGIN = \"$usage_origin\";" || fail "the helper copy's origin edit failed"
cp -- "$usage_helper" "$usage_dir/usage.js.stand-in"
expect "the shell finds no host claude" none shell_resolves claude
expect "the shell finds no host codex" none shell_resolves codex

# Readers: the service's published usage, the widget's state and the
# panel's rows, each from the running instance.
usage_read() { ipc smoke readInstance service vgs.ai-usage usage; }
usage_states() { usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print("none" if u is None else json.dumps([[a["provider"], a["label"], a["state"]] for a in u["accounts"]]))'; }
usage_windows() { # PROVIDER
  usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print(json.dumps([[a["state"], [[w["name"], w["usedPercent"]] for w in a["windows"]]] for a in (u or {"accounts": []})["accounts"] if a["provider"] == sys.argv[1]]))' "$1"
}
usage_read_at() { usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print(0 if u is None or u["readAt"] is None else u["readAt"])'; }
# usage_account_read_at PROVIDER: when each of PROVIDER's accounts had its
# figures read, null for one that holds none.
usage_account_read_at() { # PROVIDER
  usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print(json.dumps([a["readAt"] for a in (u or {"accounts": []})["accounts"] if a["provider"] == sys.argv[1]]))' "$1"
}
# usage_requests: the count of requests the stand-in endpoint logged;
# usage_requests_since N: `none` while it logged none past the first N,
# else `requests=+K` for the K past them.
usage_requests() { if [[ -s $usage_dir/requests ]]; then wc -l <"$usage_dir/requests"; else echo 0; fi; }
usage_requests_since() { local n; n="$(usage_requests)" || return; if ((n == $1)); then echo none; else echo "requests=+$((n - $1))"; fi; }
# usage_read_after T: `new` once the service published a read after T.
usage_read_after() { local at; at="$(usage_read_at)" || return; if ((at > $1)); then echo new; else echo "readAt=$at"; fi; }
# usage_idle: `idle` while the service holds no queued read and no helper of
# the sandbox's snapshots runs, so the next read is one a caller asked for.
usage_idle() {
  local pending
  pending="$(ipc smoke readInstance service vgs.ai-usage pending)" || return
  python3 - "$rt_dir/vgshell-sources-" "$pending" <<'PY'
import os, sys
prefix, pending = sys.argv[1], sys.argv[2]
running = False
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        words = open("/proc/%s/cmdline" % pid, "rb").read().split(b"\0")
    except OSError:
        continue
    running = running or any(w.decode(errors="replace").startswith(prefix) and w.endswith(b"/backend/usage.js") for w in words)
print("running" if running else "pending" if pending != "false" else "idle")
PY
}
usage_widget_state() {
  local key visible width percent tone
  key="$(bar_key)"
  visible="$(ipc smoke readInstance "$key" vgs.ai-usage visible)" || return
  width="$(ipc smoke readInstance "$key" vgs.ai-usage implicitWidth)" || return
  percent="$(ipc smoke readInstance "$key" vgs.ai-usage percent)" || return
  tone="$(ipc smoke readInstance "$key" vgs.ai-usage tone)" || return
  python3 -c 'import json,sys; v,w,p,t=(json.loads(a) for a in sys.argv[1:]); print(json.dumps([v, w > 0, p, t]))' "$visible" "$width" "$percent" "$tone"
}
# Each sign-in row's step as the Settings page draws it: [key, `sign-in`
# while its button is the manifest's own Sign in, else `withheld`, offered].
usage_steps() {
  offered_actions vgs.ai-usage | py_reply 'import json,sys
labels = {k: v["action"]["label"] for k, v in json.load(open(sys.argv[1]))["status"].items() if "action" in v}
print(json.dumps([[k, "sign-in" if label == labels[k] else "withheld", offered] for k, label, offered in json.load(sys.stdin)]))' "$usage_plugin/manifest.json"
}
# The bytes' digest and the modification time of each planted credential file.
usage_credentials() {
  python3 - "$home/.claude/.credentials.json" "$home/.codex/auth.json" <<'PY'
import hashlib, os, sys
print(" ".join("%s:%d" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), os.stat(p).st_mtime_ns) for p in sys.argv[1:]))
PY
}
usage_credentials_kept() { if [[ $(usage_credentials) == "$usage_credentials_before" ]]; then echo kept; else echo changed; fi; }
usage_panel() { ipc smoke readInstance panel vgs.ai-usage rows; }
usage_panel_colours() {
  local windows labels success warning danger
  windows="$(usage_panel)" || return
  labels="$(ipc smoke itemValues panel vgs.ai-usage Label text,color)" || return
  success="$(ipc smoke themeValue badge.tone.success.foreground)" || return
  warning="$(ipc smoke themeValue badge.tone.warning.foreground)" || return
  danger="$(ipc smoke themeValue badge.tone.danger.foreground)" || return
  ipc smoke itemColours panel vgs.ai-usage ProgressBar QQuickRectangle | py_reply 'import json,sys
bars=json.load(sys.stdin)
windows=[w for a in json.loads(sys.argv[1]) for w in a["windows"]]
labels=[r for r in json.loads(sys.argv[2]) if r.get("text", "").endswith("%")]
def qt_colour(c):
    return c + "ff" if len(c)==7 else "#" + c[3:] + c[1:3]
tokens=dict(zip(["success","warning","danger"], [qt_colour(json.loads(c)) for c in sys.argv[3:]]))
matched=len(bars)==len(windows)==len(labels)==5 and {w["tone"] for w in windows}==set(tokens)
for w,bar in zip(windows,bars):
    colour=tokens[w["tone"]]
    matched=matched and len(bar)==2 and bar[-1]==colour and any(r["text"]==w["text"] and qt_colour(r["color"])==colour for r in labels)
print("matched" if matched else "mismatch")' "$windows" "$labels" "$success" "$warning" "$danger"
}
# usage_click WHAT BOX: one real click on the centre of BOX, a control's
# box, the pointer moved there a pixel off first, since a popup mapped
# while the pointer rests on the bar takes no click until the pointer
# moves. The panel's Settings gear: its box, or `absent` with no shown
# gear; usage_gear_shown reads `shown` once it has one. usage_gear_click
# and usage_check_now_click click the gear and Check now. usage_settings_page: the
# page the Settings window shows, `""` for its list, or `absent` with no
# window.
usage_click() { # WHAT BOX
  local x y
  [[ $2 == \[* ]] || { echo "usage_click: no $1: $2" >&2; return 1; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$2") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
usage_gear() { ipc smoke labelledGeometry panel vgs.ai-usage IconButton Settings; }
usage_gear_shown() { local box; box="$(usage_gear)" || return; if [[ $box == \[* ]]; then echo shown; else echo "$box"; fi; }
usage_gear_click() { local box; box="$(usage_gear)" || return 1; usage_click gear "$box"; }
usage_check_now_click() { local box; box="$(ipc smoke itemGeometry panel vgs.ai-usage Button "Check now")" || return 1; usage_click "Check now" "$box"; }
usage_settings_page() { ipc smoke readInstance window vgs.settings page; }
# Each card's state, whether it holds no note, the note's tone and whether
# it says how long ago its figures were read.
usage_panel_notes() { usage_panel | py_reply 'import json,sys; print(json.dumps([[r["provider"], r["state"], r["note"] == "", r["noteTone"], r["checked"] != ""] for r in json.load(sys.stdin)]))'; }
usage_panel_rows() { usage_panel | py_reply 'import json,sys; print(json.dumps([[r["provider"], r["label"], r["email"], [[w["name"], w["percent"], w["tone"]] for w in r["windows"]]] for r in json.load(sys.stdin)]))'; }

usage_panel_details() { usage_panel | py_reply 'import json,sys; print(json.dumps([[r["provider"], r["label"], [[d["label"], d["value"]] for d in r["details"]]] for r in json.load(sys.stdin)]))'; }
usage_panel_view() { ipc smoke readInstance panel vgs.ai-usage fullView; }
# usage_panel_cap: `matched` while the open panel's height cap is half the
# logical height of the output its bar is on, else both figures.
usage_panel_cap() {
  local cap screen
  cap="$(ipc smoke readInstance panel vgs.ai-usage heightCap)" || return
  screen="$(bar_key)" || return
  hypr -j monitors | py_reply 'import json,sys
cap, name = float(sys.argv[1]), sys.argv[2][len("bar:"):]
m = [m for m in json.load(sys.stdin) if m["name"] == name][0]
want = m["height"] / m["scale"] / 2
print("matched" if abs(cap - want) < 0.5 else "cap=%g want=%g" % (cap, want))' "$cap" "$screen"
}
usage_choices() { ipc smoke statusValues vgs.ai-usage | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([c["label"] for c in v["accounts"]]))'; }
usage_apply_setting() { ipc smoke invokeInstance window vgs.settings applySetting "{\"id\":\"vgs.ai-usage\",\"key\":\"$1\",\"value\":$2}"; }
# The time left on each window the panel shows, against the stand-ins'
# answer of 5 h 30 min and 3 d 6 h after the request: `matched` while every
# window reads within the minutes since the request and the panel clock's
# one-minute step, else what the panel reads.
usage_panel_resets() {
  usage_panel | py_reply 'import json,sys
rows = json.load(sys.stdin)
got = [[w["name"], w["resetIn"]] for r in rows for w in r["windows"]]
def fits(name, left):
    if left["kind"] != "in":
        return False
    total = left["days"] * 1440 + left["hours"] * 60 + left["minutes"]
    want = {"five_hour": 330, "seven_day": 4680, "seven_day_fable": 4680}[name]
    return want - 10 <= total <= want + 1
names = [name for name, _ in got]
print("matched" if names == ["five_hour", "seven_day", "seven_day_fable", "five_hour", "seven_day"] and all(fits(n, l) for n, l in got) else json.dumps(got))'
}
# usage_refresh LABEL: one check the row asks for, once the service is idle,
# read back once the service published it.
usage_refresh() { # LABEL
  local before
  expect_poll "$1: the service is idle" idle usage_idle
  before="$(usage_read_at)" || before=0
  expect "$1: the service takes a check" ok ipc vgs.ai-usage invoke refresh ''
  expect_poll "$1: the check is published" new usage_read_after "$before"
}
# usage_control LOG LABEL WANT CMD...: the failures one expect of a planted
# control makes, its lines kept in LOG, where the row finds the reading the
# defect itself produces.
usage_control() { # LOG LABEL WANT CMD...
  local log="$1"
  shift
  (failures=0 behaviour_failures=0
   expect "$@" >"$log"
   echo "$failures")
}
# usage_poll_control LOG LABEL WANT CMD...: the same for an expect_poll,
# which in this subshell polls for the harness's control bound.
usage_poll_control() { # LOG LABEL WANT CMD...
  local log="$1"
  shift
  (failures=0 behaviour_failures=0
   expect_poll "$@" >"$log"
   echo "$failures")
}

# Sign in per tool: with claude present and codex missing, Settings offers
# Claude Code's Sign in and withholds Codex's; with both present, both.
printf '#!/bin/sh\nexit 9\n' >"$usage_dir/claude"
chmod 755 "$usage_dir/claude"
ln -sfn -- "$usage_dir/claude" "$shim/claude"
rescan "the AI Usage stand-ins are scanned"
expect "the shell finds the stand-in claude" "$shim/claude" shell_resolves claude
expect "AI Usage is enabled" ok ipc shell setPluginEnabled vgs.ai-usage true
expect "AI Usage's widget is placed" ok ipc shell setPluginPlaced vgs.ai-usage true
expect_poll "AI Usage's service is built" True record_exists vgs.ai-usage
expect_poll "with no account the service publishes none" '[]' usage_states
expect_poll "with no account the widget is hidden and empty" '[false, false, null, "normal"]' usage_widget_state
expect "the Settings window is summoned" ok ipc shell summon window vgs.settings '{}'
expect_poll "a missing codex withholds Codex's Sign in and not Claude Code's" '[["claude", "sign-in", true], ["codex", "withheld", true]]' usage_steps
ln -sfn -- "$source_repo/scripts/fixtures/ai-usage/codex" "$shim/codex"
rescan "the stand-in codex is scanned"
expect "the shell finds the stand-in codex" "$shim/codex" shell_resolves codex
expect_poll "with both tools present each offers Sign in" '[["claude", "sign-in", true], ["codex", "sign-in", true]]' usage_steps
forget_record
expect "Sign in to Claude Code is pressed" ok settings_act vgs.ai-usage claude
expect_poll "Sign in opens Claude Code's sign-in TUI" '["vgs.ai-usage/sign-in-claude", "tui/sign-in-claude.sh"]' recorded_tail
expect_run_end "Claude Code's sign-in TUI ends" vgs.ai-usage/sign-in-claude
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone" 0 window_count Plugins

# A widget copy shown with no account fails the hidden reading with the
# shown widget's own reading.
usage_edit "$usage_widget" "    visible: shown
    implicitWidth: shown ? item.implicitWidth : 0" "    visible: true
    implicitWidth: item.implicitWidth" || fail "the shown-widget control's edit failed"
rescan "the shown-widget copy is scanned"
expect_poll "the shown-widget copy draws its widget with no account" '[true, true, null, "normal"]' usage_widget_state
expect "a widget shown with no account breaks the hidden reading" 1 \
  usage_control "$usage_dir/shown-control.log" "the widget must stay hidden with no account" '[false, false, null, "normal"]' usage_widget_state
expect "the hidden reading fails on the shown widget" 1 grep -c -F -- 'the widget must stay hidden with no account: got [true, true, null, "normal"]' "$usage_dir/shown-control.log"
cp -- "$usage_dir/Widget.qml.original" "$usage_widget"
rescan "the restored widget is scanned"
expect_poll "the restored widget is hidden again" '[false, false, null, "normal"]' usage_widget_state

# Both accounts, read through the stand-ins: each state, the widget's
# highest share in the warning tone, the panel's rows and reset times, and
# credential files that no read changed.
mkdir -p -- "$home/.claude" "$home/.codex"
python3 - "$home/.claude/.credentials.json" <<'PY'
import json, sys, time
token = "sk-ant-oat01-smoke-" + "0" * 24
json.dump({"claudeAiOauth": {"accessToken": token, "refreshToken": "smoke-refresh", "expiresAt": int(time.time() * 1000) + 3600000,
           "scopes": ["user:inference"], "subscriptionType": "max"}}, open(sys.argv[1], "w"))
PY
printf '{"OPENAI_API_KEY": null, "tokens": {"access_token": "smoke-access"}}\n' >"$home/.codex/auth.json"
printf 'relative\n' >"$home/.codex/stand-in-mode"
usage_credentials_before="$(usage_credentials)"
usage_refresh "the planted accounts"
expect_poll "both accounts read as signed in" '[["claude", "default", "ok"], ["codex", "default", "ok"]]' usage_states
expect "Claude Code's windows are the endpoint's" '[["ok", [["five_hour", 42], ["seven_day", 83], ["seven_day_fable", 12]]]]' usage_windows claude
expect "Codex's windows are the program's" '[["ok", [["five_hour", 27], ["seven_day", 64]]]]' usage_windows codex
expect_poll "the widget shows the highest share in the warning tone" '[true, true, 83, "warning"]' usage_widget_state
expect "the read changed no credential file" kept usage_credentials_kept
expect_poll "the service is idle before the panel opens" idle usage_idle
usage_before_panel="$(usage_read_at)" || usage_before_panel=0
usage_sent_before_panel="$(usage_requests)"
usage_notes_ok='[["claude", "ok", true, "normal", true], ["codex", "ok", true, "normal", true]]'
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage from its widget failed"
expect_poll "the widget opens its panel" '[["claude", "default", "", [["five_hour", 42, "success"], ["seven_day", 83, "danger"], ["seven_day_fable", 12, "success"]]], ["codex", "default", "person@example.invalid", [["five_hour", 27, "success"], ["seven_day", 64, "warning"]]]]' usage_panel_rows
expect_poll "the panel's reset times are the stand-ins'" matched usage_panel_resets
expect "the full panel is selected by default" true usage_panel_view
expect "the full panel carries provider details" '[["claude", "default", [["Extra usage", "$123.45 of $500.00"]]], ["codex", "default", [["Codex credits", "12,345 available"]]]]' usage_panel_details
summon_drawn panel vgs.ai-usage || fail "the panel never drew a frame"
expect_poll "each usage value and progress fill share their theme tier" matched usage_panel_colours
usage_panel_box() { ipc smoke instanceGeometry panel vgs.ai-usage | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[2] > 0 and r[3] > 0)'; }
expect "the panel has a size" True usage_panel_box
expect_poll "the panel's height cap is half its output's height" matched usage_panel_cap
expect "each card holds no note and says how long ago it was read" "$usage_notes_ok" usage_panel_notes
expect "opening the panel publishes no read" "readAt=$usage_before_panel" usage_read_after "$usage_before_panel"
expect "opening the panel sends the endpoint no request" none usage_requests_since "$usage_sent_before_panel"
expect "AI Usage's panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the hidden panel is gone" absent usage_panel
# The caller's tone binding is what gives the bar the value's tier. A
# disposable panel without it still draws bars, in the accent colour.
usage_edit "$usage_panel_qml" '; tone: modelData.tone' '' || fail "the accent progress control edit failed"
rescan "the accent progress control is scanned"
usage_refresh "the accent progress control"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the accent progress control failed"
summon_drawn panel vgs.ai-usage || fail "the accent progress control never drew a frame"
expect "an accent progress fill fails the shared tier reading" 1 usage_control "$usage_dir/progress-tier-control.log" "usage fill must share the value tier" matched usage_panel_colours
expect "the accent progress control hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the accent progress control is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"
rescan "the tier progress binding is restored"
usage_refresh "the restored tier progress binding"
# A panel copy capped at its output's whole height fails the cap reading
# with its own figure.
usage_edit "$usage_panel_qml" 'output.height * Theme.size.window.heightShare' 'output.height' || fail "the whole-height control's edit failed"
rescan "the whole-height panel copy is scanned"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the whole-height panel copy failed"
summon_drawn panel vgs.ai-usage || fail "the whole-height panel copy never drew a frame"
expect "a panel capped at its output's whole height breaks the cap reading" 1 \
  usage_control "$usage_dir/cap-control.log" "the panel's cap must be half its output's height" matched usage_panel_cap
expect "the cap reading fails on the whole height" 1 grep -c -F -- "the panel's cap must be half its output's height: got cap=" "$usage_dir/cap-control.log"
expect "the whole-height panel copy hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the whole-height panel copy is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"
rescan "the restored panel is scanned"
# A panel copy whose open asks for a read fails the no-request reading
# with its own request. The service may be rebuilt by the rescan, so a
# check it publishes first ends any read it starts.
usage_edit "$usage_panel_qml" '    function open(payloadJson) {}' '    function open(payloadJson) { refresh(); }' || fail "the reading-panel control's edit failed"
rescan "the reading-panel copy is scanned"
usage_refresh "the reading-panel copy's service"
usage_sent_before_control="$(usage_requests)"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the reading-panel copy failed"
summon_drawn panel vgs.ai-usage || fail "the reading-panel copy never drew a frame"
expect_poll "the reading-panel copy sends a request when it opens" "requests=+1" usage_requests_since "$usage_sent_before_control"
expect "a panel that reads when it opens breaks the no-request reading" 1 \
  usage_control "$usage_dir/open-control.log" "opening the panel must send no request" none usage_requests_since "$usage_sent_before_control"
expect "the no-request reading fails on the panel's request" 1 grep -c -F -- "opening the panel must send no request: got requests=+1" "$usage_dir/open-control.log"
expect "the reading-panel copy hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the reading-panel copy is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"
rescan "the panel restored after the reading control is scanned"
expect "the Settings window is summoned for AI Usage settings edits" ok ipc shell summon window vgs.settings '{}'
expect "the account choices list all read accounts" '["Claude Code \u00b7 default", "Codex \u00b7 person@example.invalid"]' usage_choices
expect "choosing compact view is allowed" ok usage_apply_setting view '"compact"'
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage for compact view failed"
expect_poll "the compact panel is selected" false usage_panel_view
expect_poll "the compact panel still shows every limit" '[["claude", "default", "", [["five_hour", 42, "success"], ["seven_day", 83, "danger"], ["seven_day_fable", 12, "success"]]], ["codex", "default", "person@example.invalid", [["five_hour", 27, "success"], ["seven_day", 64, "warning"]]]]' usage_panel_rows
expect "the compact panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the compact panel is gone" absent usage_panel
expect "hiding Codex by provider is allowed" ok usage_apply_setting showCodex false
expect_poll "the widget recomputes without Codex" '[true, true, 83, "warning"]' usage_widget_state
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage with Codex filtered failed"
expect_poll "the provider filter leaves Claude only" '[["claude", "default", "", [["five_hour", 42, "success"], ["seven_day", 83, "danger"], ["seven_day_fable", 12, "success"]]]]' usage_panel_rows
expect "the filtered panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the filtered panel is gone" absent usage_panel
expect "hiding the first offered account is allowed" ok usage_apply_setting hidden '[{"name":"item-1","account":""}]'
expect_poll "the widget hides when all visible accounts are filtered" '[false, false, null, "normal"]' usage_widget_state
expect "restoring hidden accounts is allowed" ok usage_apply_setting hidden '[]'
expect "restoring Codex provider is allowed" ok usage_apply_setting showCodex true
expect "restoring full view is allowed" ok usage_apply_setting view '"full"'
expect "the Settings window used for setting edits hides" ok ipc shell hide window vgs.settings
expect_poll "the Settings window used for setting edits is gone" 0 window_count Plugins

# The panel's gear, which Plugins, always on, gives every panel: a click
# opens the Settings window on AI Usage's page and closes the panel.
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage from its widget for the gear failed"
expect_poll "the panel draws its gear" shown usage_gear_shown
summon_drawn panel vgs.ai-usage || fail "the panel with the gear never drew a frame"
usage_gear_click || fail "the click on the panel's gear failed"
expect_poll "the gear opens the Settings window on AI Usage's page" '"vgs.ai-usage"' usage_settings_page
expect_poll "the gear closes the panel" absent usage_panel
expect "the Settings window the gear opened hides" ok ipc shell hide window vgs.settings
expect_poll "the hidden Settings window is gone" absent usage_settings_page
# A panel host copy whose slot opens Settings with no page fails the page
# reading on the Settings list. The copies sit in a fresh directory, written
# before the first is built, so the host copy's PluginSlot is the slot copy
# beside it (validation-smoke-input.md).
usage_gear_dir="$repo/shell/Hosts/SettingsGearControl"
mkdir -p -- "$usage_gear_dir"
cp -- "$repo/shell/Hosts/SummonPopup.qml" "$repo/shell/Hosts/PluginSlot.qml" "$usage_gear_dir/"
usage_edit "$usage_gear_dir/PluginSlot.qml" 'JSON.stringify({ plugin: settingsPage })' '"{}"' || fail "the pageless gear control's edit failed"
expect "the probe builds the panel host copy whose gear opens no page" ok ipc smoke popupLoad usage-gear-control "$usage_gear_dir/SummonPopup.qml" "$(bar_key)" vgs.ai-usage '{"pluginId":"vgs.ai-usage","kind":"panel","request":{"anchor":"@instance","anchored":true,"payloadJson":"{}"}}'
expect_poll "the host copy's panel draws its gear" shown usage_gear_shown
summon_drawn panel vgs.ai-usage || fail "the host copy's panel never drew a frame"
usage_gear_click || fail "the click on the host copy's gear failed"
expect_poll "the host copy's gear opens the Settings list" '""' usage_settings_page
expect "a gear that opens no page breaks the page reading" 1 \
  usage_control "$usage_dir/gear-control.log" "the gear must open AI Usage's page" '"vgs.ai-usage"' usage_settings_page
expect "the page reading fails on the Settings list" 1 grep -c -F -- "the gear must open AI Usage's page: got \"\"" "$usage_dir/gear-control.log"
expect "the probe drops the panel host copy" ok ipc smoke popupDrop usage-gear-control
expect_poll "the host copy's panel is gone" absent usage_panel
expect "the Settings list the copy opened hides" ok ipc shell hide window vgs.settings
expect_poll "the hidden Settings list is gone" absent usage_settings_page

# A helper copy that writes the credential file it read fails that reading.
usage_edit "$usage_helper" '    try { file = readHeld(Anchored, opened.fd, ".credentials.json"); }
    finally { fs.closeSync(opened.fd); }
    if (file.kind === "absent") return { state: "signed-out" };
    if (file.kind === "refused") return failed(file.reason);' '    try { file = readHeld(Anchored, opened.fd, ".credentials.json"); }
    finally { fs.closeSync(opened.fd); }
    if (file.kind === "absent") return { state: "signed-out" };
    if (file.kind === "refused") return failed(file.reason);
    fs.writeFileSync(path.join(directory, ".credentials.json"), file.text);' || fail "the writing control's edit failed"
rescan "the writing copy is scanned"
usage_refresh "the writing copy"
expect "a helper that writes the credential file breaks the unchanged reading" 1 \
  usage_control "$usage_dir/written-control.log" "no read may change a credential file" kept usage_credentials_kept
expect "the unchanged reading fails on the written file" 1 grep -c -F -- "no read may change a credential file: got changed" "$usage_dir/written-control.log"
cp -- "$usage_dir/usage.js.stand-in" "$usage_helper"
rescan "the restored helper is scanned"
usage_refresh "the restored helper"
usage_credentials_before="$(usage_credentials)"

# Claude's endpoint turns away frequent reads with 429, as the stand-in's
# limited mode does inside 60 s of the answer it served. The panel's Check
# now inside that window publishes a read and sends a request, whose 429
# keeps the figures, marked limited, with their read time and a plain note,
# and ten opens and closes of the panel send no request at all.
expected_errors+=('ai-usage: account=claude-[0-9a-f]+ limited=http-429')
usage_figures='[["ok", [["five_hour", 42], ["seven_day", 83], ["seven_day_fable", 12]]]]'
usage_kept='[["limited", [["five_hour", 42], ["seven_day", 83], ["seven_day_fable", 12]]]]'
usage_notes_limited='[["claude", "limited", false, "normal", true], ["codex", "ok", true, "normal", true]]'
usage_mode limited
usage_refresh "the first read under the limit"
expect "the first read under the limit is served" "$usage_figures" usage_windows claude
usage_claude_read_at="$(usage_account_read_at claude)"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage for Check now failed"
summon_drawn panel vgs.ai-usage || fail "the panel for Check now never drew a frame"
expect_poll "the service is idle before Check now" idle usage_idle
usage_before_check="$(usage_read_at)" || usage_before_check=0
usage_sent_before_check="$(usage_requests)"
usage_check_now_click || fail "the click on the panel's Check now failed"
expect_poll "the panel's Check now publishes a read" new usage_read_after "$usage_before_check"
expect "the panel's Check now sends the endpoint one request" "requests=+1" usage_requests_since "$usage_sent_before_check"
expect "a Check now inside the limit keeps the figures, marked limited" "$usage_kept" usage_windows claude
expect "a Check now inside the limit keeps the figures' read time" "$usage_claude_read_at" usage_account_read_at claude
expect_poll "the limited card draws a plain note and no warning" "$usage_notes_limited" usage_panel_notes
expect "the Check now panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the Check now panel is gone" absent usage_panel
usage_sent_before_cycles="$(usage_requests)"
for usage_cycle in 1 2 3 4 5 6 7 8 9 10; do
  click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage under the limit, time $usage_cycle, failed"
  expect_poll "under the limit the panel opens with no stale note, time $usage_cycle" "$usage_notes_limited" usage_panel_notes
  expect "under the limit the panel hides, time $usage_cycle" ok ipc shell hide panel vgs.ai-usage
  expect_poll "under the limit the panel is gone, time $usage_cycle" absent usage_panel
done
expect "ten opens of the panel send the endpoint no request" none usage_requests_since "$usage_sent_before_cycles"
expect "ten opens of the panel keep the figures" "$usage_kept" usage_windows claude
expect "the limited reads changed no credential file" kept usage_credentials_kept
# A panel copy whose Check now asks for no read fails the published-read
# reading on the read time before the click. The rescan may rebuild the
# service, so a check it publishes first ends any read that starts.
usage_edit "$usage_panel_qml" '                onClicked: root.refresh()' '                onClicked: {}' || fail "the dead Check now control's edit failed"
rescan "the dead Check now copy is scanned"
usage_refresh "the dead Check now copy's service"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the dead Check now copy failed"
summon_drawn panel vgs.ai-usage || fail "the dead Check now copy never drew a frame"
expect_poll "the service is idle before the dead Check now" idle usage_idle
usage_before_dead="$(usage_read_at)" || usage_before_dead=0
usage_check_now_click || fail "the click on the dead Check now failed"
expect "a Check now that asks for no read breaks the published-read reading" 1 \
  usage_poll_control "$usage_dir/check-now-control.log" "the panel's Check now must publish a read" new usage_read_after "$usage_before_dead"
expect "the published-read reading fails on the old read time" 1 grep -c -F -- "the panel's Check now must publish a read: got readAt=$usage_before_dead want new" "$usage_dir/check-now-control.log"
expect "the dead Check now copy hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the dead Check now copy is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"
rescan "the panel restored after the Check now control is scanned"
# The rescans rebuilt the service, whose first read under the limit holds
# no figures; a served read gives the next readings their figures.
usage_mode relative
usage_refresh "the panel restored after the Check now control"
expect "the restored panel's service reads the figures" "$usage_figures" usage_windows claude

# A failed read keeps the last figures, marked stale, never 0 %.
expected_errors+=('ai-usage: account=claude-[0-9a-f]+ failed=http-500')
usage_mode error
usage_refresh "a failed Claude request"
usage_stale='[["stale", [["five_hour", 42], ["seven_day", 83], ["seven_day_fable", 12]]]]'
expect_poll "a failed request keeps the last figures, marked stale" "$usage_stale" usage_windows claude
expect_poll "the widget keeps the stale share" '[true, true, 83, "warning"]' usage_widget_state
expect "the failed read changed no credential file" kept usage_credentials_kept
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage on stale figures failed"
expect_poll "the stale card warns that its figures may be old" '[["claude", "stale", false, "warning", true], ["codex", "ok", true, "normal", true]]' usage_panel_notes
expect "the stale panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the stale panel is gone" absent usage_panel
# A refused token reads expired, with the expired warning.
usage_mode refused
usage_refresh "a refused Claude token"
expect "a refused token reads expired with no figures" '[["expired", []]]' usage_windows claude
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage on an expired sign-in failed"
expect_poll "the expired card warns" '[["claude", "expired", false, "warning", false], ["codex", "ok", true, "normal", true]]' usage_panel_notes
expect "the expired panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the expired panel is gone" absent usage_panel
# A helper copy that reads a failed request as 0 % fails that reading: its
# service, rebuilt, first reads the figures, then the failure.
usage_edit "$usage_helper" '    if (reply.status === 429) return { state: "limited", email };
    if (reply.status !== 200) return lost("http-" + reply.status);' '    if (reply.status === 429) return { state: "limited", email };
    if (reply.status !== 200) return { state: "ok", email, windows: [{ name: "five_hour", usedPercent: 0, resetsAt: null }] };' || fail "the zero control's edit failed"
usage_mode relative
rescan "the zero copy is scanned"
usage_refresh "the zero copy's first read"
expect_poll "the zero copy reads the figures first" '[["ok", [["five_hour", 42], ["seven_day", 83], ["seven_day_fable", 12]]]]' usage_windows claude
usage_mode error
usage_refresh "the zero copy's failed read"
expect "a helper that reads a failure as 0 % breaks the stale reading" 1 \
  usage_control "$usage_dir/zero-control.log" "a failed request must keep the last figures" "$usage_stale" usage_windows claude
expect "the stale reading fails on the 0 % window" 1 grep -c -F -- 'a failed request must keep the last figures: got [["ok", [["five_hour", 0]]]]' "$usage_dir/zero-control.log"
usage_mode relative

# A gateway-shaped published reading is API billing. Plant it in the
# disposable helper so the real service, merge and panel draw its card,
# without a live keyring or Vercel request.
usage_edit "$usage_helper" '    return { accounts, partial, gatewayKey };' '    accounts.push({ id: "gateway-planted", provider: "gateway", label: "AI Gateway", email: "", state: "ok", windows: [{ name: "credits", usedPercent: 25, resetsAt: null }], credits: null, details: { gateway: { balance: 75, totalUsed: 25 } } });
    return { accounts, partial, gatewayKey };' || fail "planting the gateway API reading failed"
rescan "the gateway API reading is scanned"
usage_refresh "the gateway API reading"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the gateway API card failed"
summon_drawn panel vgs.ai-usage || fail "the gateway API card never drew a frame"
ipc smoke scrollTo panel vgs.ai-usage 99999 >/dev/null || fail "the gateway API card did not scroll into view"
usage_gateway_api() { usage_panel | py_reply 'import json,sys; r=json.load(sys.stdin); print(any(a["provider"] == "gateway" and a["api"] is True for a in r))'; }
usage_api_chip() {
  ipc smoke descendantGeometry panel vgs.ai-usage | py_reply 'import json,sys
rows=json.load(sys.stdin)
def card_of(index):
    while index >= 0:
        if rows[index]["type"] == "Card": return index
        index=rows[index]["parent"]
    return -1
cards={card_of(i) for i,r in enumerate(rows) if r["type"] == "Label" and r.get("text") == "AI Gateway"}
views=[r["box"] for r in rows if r["type"] == "ScrollArea" and r["visible"]]
def drawn(r):
    x,y,w,h=r["box"]
    return r["visible"] and w>0 and h>0 and any(x>=vx and y>=vy and x+w<=vx+vw and y+h<=vy+vh for vx,vy,vw,vh in views)
print(str(any(r["type"] == "Badge" and r.get("text") == "[API]" and card_of(i) in cards and drawn(r) for i,r in enumerate(rows))).lower())'
}
usage_gateway_logo() { ipc smoke images panel vgs.ai-usage | py_reply 'import json,re,sys; print(any("m12 1.608 12 20.784H0Z" in r[0] and r[1] == "ready" and re.search(r"fill=\"#[0-9a-fA-F]{6}\"", r[0]) is not None for r in json.load(sys.stdin)))'; }
expect_poll "the gateway card carries API billing" True usage_gateway_api
expect_poll "the gateway card draws its API chip" true usage_api_chip
expect_poll "the gateway card draws its published Vercel mark" True usage_gateway_logo
expect "the API card panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the API card panel is gone" absent usage_panel
usage_edit "$usage_panel_qml" 'visible: modelData.api;' 'visible: false;' || fail "the hidden API chip control edit failed"
rescan "the hidden API chip control is scanned"
usage_refresh "the hidden API chip control"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the hidden API chip control failed"
summon_drawn panel vgs.ai-usage || fail "the hidden API chip control never drew a frame"
expect "a hidden API chip fails the drawn chip reading" 1 usage_control "$usage_dir/api-chip-control.log" "API chip must draw" true usage_api_chip
expect "the hidden API chip panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the hidden API chip panel is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"
usage_edit "$usage_panel_qml" 'source: View.logo(modelData.provider, Theme.color.text)' 'source: ""' || fail "the absent logo control edit failed"
rescan "the absent logo control is scanned"
usage_refresh "the absent logo control"
click_centre "$(bar_key)" vgs.ai-usage || fail "opening the absent logo control failed"
summon_drawn panel vgs.ai-usage || fail "the absent logo control never drew a frame"
expect "an absent logo fails the ready mark reading" 1 usage_control "$usage_dir/logo-control.log" "Vercel mark must draw" True usage_gateway_logo
expect "the absent logo panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the absent logo panel is gone" absent usage_panel
cp -- "$usage_dir/Panel.qml.original" "$usage_panel_qml"

expect "AI Usage is disabled after the row" ok ipc shell setPluginEnabled vgs.ai-usage false
expect_poll "disabled AI Usage releases its service" False record_exists vgs.ai-usage
cp -- "$usage_dir/usage.js.original" "$usage_helper"
rm -rf -- "${home:?}/.claude" "${home:?}/.codex"
rm -f -- "${shim:?}/codex" "${shim:?}/claude"
kill "$usage_endpoint" 2>/dev/null || true
wait "$usage_endpoint" 2>/dev/null || true
cp -- "$usage_saved" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
rescan "the AI Usage cleanup is rescanned"
