# AI Usage over a Claude Code and a Codex account the row plants in the
# sandbox HOME. The sandbox's copy of the usage helper reaches the stand-in
# endpoint scripts/fixtures/ai-usage/endpoint.js on 127.0.0.1, its origin
# constant edited through scripts/smoke/fixtures/ai-usage/edit.py, and the
# shell's PATH finds the stand-in scripts/fixtures/ai-usage/codex first. It
# reads the widget's share, tone and hidden state, the panel's rows and
# reset times and the Settings page's Sign in, whose TUI the stand-in
# terminal records, from the running instances, and that no read changed a
# credential file's bytes or modification time. Controls: a helper copy
# that writes the credential file, one that reads a failed request as 0 %,
# and a widget copy shown with no account each fail their reading.
# This row has no latency ceiling; every reading polls through expect_poll.
# inputs: shell/plugins/vgs.ai-usage/* bin/lib/account-folders.js bin/lib/anchored.js bin/lib/qml-library.js shell/Commons/AccountDirectories.js scripts/fixtures/ai-usage/* scripts/smoke/fixtures/ai-usage/* shell/plugins/vgs.settings/* shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml shell/Core/Capabilities.qml bin/vgshell-tui
set -euo pipefail
usage_dir="$sandbox/ai-usage"
mkdir -p -- "$usage_dir"
usage_plugin="$repo/shell/plugins/vgs.ai-usage"
usage_helper="$usage_plugin/backend/usage.js"
usage_widget="$usage_plugin/Widget.qml"
usage_saved="$usage_dir/shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$usage_saved"
cp -- "$usage_helper" "$usage_dir/usage.js.original"
cp -- "$usage_widget" "$usage_dir/Widget.qml.original"
usage_edit() { python3 "$source_repo/scripts/smoke/fixtures/ai-usage/edit.py" "$@"; }
usage_mode() { printf '%s\n' "$1" >"$usage_dir/mode"; }
usage_mode ok
"$node_bin" "$source_repo/scripts/fixtures/ai-usage/endpoint.js" "$usage_dir/port" "$usage_dir/mode" "$usage_dir/requests" &
usage_endpoint=$!
usage_port() { if [[ -s $usage_dir/port ]]; then echo ready; else echo waiting; fi; }
expect_poll "the stand-in usage endpoint listens" ready usage_port
usage_origin="http://127.0.0.1:$(cat -- "$usage_dir/port")"
usage_edit "$usage_helper" 'const ORIGIN = "https://api.anthropic.com";' "const ORIGIN = \"$usage_origin\";" || fail "the helper copy's origin edit failed"
cp -- "$usage_helper" "$usage_dir/usage.js.stand-in"
ln -sfn -- "$source_repo/scripts/fixtures/ai-usage/codex" "$shim/codex"
expect "the shell finds the stand-in codex first" "$shim/codex" shell_resolves codex

# Readers: the service's published usage, the widget's state and the
# panel's rows, each from the running instance.
usage_read() { ipc smoke readInstance service vgs.ai-usage usage; }
usage_states() { usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print("none" if u is None else json.dumps([[a["provider"], a["label"], a["state"]] for a in u["accounts"]]))'; }
usage_windows() { # PROVIDER
  usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print(json.dumps([[a["state"], [[w["name"], w["usedPercent"]] for w in a["windows"]]] for a in (u or {"accounts": []})["accounts"] if a["provider"] == sys.argv[1]]))' "$1"
}
usage_read_at() { usage_read | py_reply 'import json,sys; u=json.load(sys.stdin); print(0 if u is None or u["readAt"] is None else u["readAt"])'; }
# usage_read_after T: `new` once the service published a read after T.
usage_read_after() { local at; at="$(usage_read_at)" || return; if ((at > $1)); then echo new; else echo "readAt=$at"; fi; }
usage_widget_state() {
  local key visible width percent tone
  key="$(bar_key)"
  visible="$(ipc smoke readInstance "$key" vgs.ai-usage visible)" || return
  width="$(ipc smoke readInstance "$key" vgs.ai-usage implicitWidth)" || return
  percent="$(ipc smoke readInstance "$key" vgs.ai-usage percent)" || return
  tone="$(ipc smoke readInstance "$key" vgs.ai-usage tone)" || return
  python3 -c 'import json,sys; v,w,p,t=(json.loads(a) for a in sys.argv[1:]); print(json.dumps([v, w > 0, p, t]))' "$visible" "$width" "$percent" "$tone"
}
# The bytes' digest and the modification time of each planted credential file.
usage_credentials() {
  python3 - "$home/.claude/.credentials.json" "$home/.codex/auth.json" <<'PY'
import hashlib, os, sys
print(" ".join("%s:%d" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), os.stat(p).st_mtime_ns) for p in sys.argv[1:]))
PY
}
usage_credentials_kept() { if [[ $(usage_credentials) == "$usage_credentials_before" ]]; then echo kept; else echo changed; fi; }
# The panel's rows, with each reset line set beside the line the view
# words for its window at the panel's own clock: `matched` when every one
# agrees.
usage_panel() { ipc smoke readInstance panel vgs.ai-usage rows; }
usage_panel_rows() { usage_panel | py_reply 'import json,sys; print(json.dumps([[r["title"], [d.strip() for d in r["detail"].split("\u00b7")], [[w["label"], w["text"], w["tone"]] for w in r["windows"]]] for r in json.load(sys.stdin)]))'; }
usage_panel_resets() {
  local rows published now
  rows="$(usage_panel)" || return
  published="$(usage_read)" || return
  now="$(ipc smoke readInstance panel vgs.ai-usage now)" || return
  "$node_bin" -e '
const View = require(process.argv[1]).load(process.argv[2]);
const rows = JSON.parse(process.argv[3]), usage = JSON.parse(process.argv[4]), now = JSON.parse(process.argv[5]);
const want = usage.accounts.filter(a => a.state !== "signed-out").map(a => a.windows.map(w => View.resetText(w.resetsAt, now)));
const got = rows.map(r => r.windows.map(w => w.reset));
process.stdout.write(JSON.stringify(got) === JSON.stringify(want) ? "matched\n" : JSON.stringify(got) + "\n");' \
    "$source_repo/bin/lib/qml-library.js" "$usage_plugin/UsageView.js" "$rows" "$published" "$now"
}
usage_refresh() { # LABEL
  local before
  before="$(usage_read_at)" || before=0
  expect "$1: the service takes a check" ok ipc vgs.ai-usage invoke refresh ''
  expect_poll "$1: the check is published" new usage_read_after "$before"
}

rescan "the AI Usage stand-ins are scanned"
expect "AI Usage is enabled" ok ipc shell setPluginEnabled vgs.ai-usage true
expect "AI Usage's widget is placed" ok ipc shell setPluginPlaced vgs.ai-usage true
expect_poll "AI Usage's service is built" True record_exists vgs.ai-usage

# No account: the widget takes no room, and Settings offers each Sign in,
# whose TUI the stand-in terminal records.
expect_poll "with no account the service publishes none" '[]' usage_states
expect_poll "with no account the widget is hidden and empty" '[false, false, null, "normal"]' usage_widget_state
expect "enabling the Settings plugin for AI Usage's rows is allowed" ok ipc shell setPluginEnabled vgs.settings true
expect_poll "the Settings service is built" True record_exists vgs.settings
expect "the Settings window is summoned" ok ipc shell summon window vgs.settings '{}'
expect_poll "with no account each tool offers Sign in" '[["claude", "Sign in", true], ["codex", "Sign in", true]]' offered_actions vgs.ai-usage
forget_record
expect "Sign in to Claude Code is pressed" ok settings_act vgs.ai-usage claude
expect_poll "Sign in opens Claude Code's sign-in TUI" '["vgs.ai-usage/sign-in-claude", "tui/sign-in-claude.sh"]' recorded_tail
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect "disabling the Settings plugin after the rows is allowed" ok ipc shell setPluginEnabled vgs.settings false
# A widget copy shown with no account fails the hidden reading.
usage_edit "$usage_widget" "    visible: shown
    implicitWidth: shown ? item.implicitWidth : 0" "    visible: true
    implicitWidth: item.implicitWidth" || fail "the shown-widget control's edit failed"
rescan "the shown-widget copy is scanned"
expect_poll "the shown-widget copy's service is built" '[]' usage_states
usage_shown_control() {
  (failures=0 behaviour_failures=0
   expect "the widget must stay hidden with no account" '[false, false, null, "normal"]' usage_widget_state >"$usage_dir/shown-control.log"
   echo "$failures")
}
expect "a widget shown with no account breaks the hidden reading" 1 usage_shown_control
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
usage_credentials_before="$(usage_credentials)"
usage_refresh "the planted accounts"
expect_poll "both accounts read as signed in" '[["claude", "default", "ok"], ["codex", "default", "ok"]]' usage_states
expect "Claude Code's windows are the endpoint's" '[["ok", [["five_hour", 42], ["seven_day", 83], ["seven_day_opus", 12]]]]' usage_windows claude
expect "Codex's windows are the program's" '[["ok", [["five_hour", 27], ["seven_day", 64]]]]' usage_windows codex
expect_poll "the widget shows the highest share in the warning tone" '[true, true, 83, "warning"]' usage_widget_state
expect "the read changed no credential file" kept usage_credentials_kept
click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage from its widget failed"
expect_poll "the widget opens its panel" '[["Claude Code", ["Max plan"], [["5-hour limit", "42%", "normal"], ["Weekly limit", "83%", "warning"], ["Weekly Opus limit", "12%", "normal"]]], ["Codex", ["person@example.invalid", "Plus plan"], [["5-hour limit", "27%", "normal"], ["Weekly limit", "64%", "normal"]]]]' usage_panel_rows
expect_poll "the panel words each window's reset time" matched usage_panel_resets
summon_drawn panel vgs.ai-usage || fail "the panel never drew a frame"
usage_panel_box() { ipc smoke instanceGeometry panel vgs.ai-usage | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[2] > 0 and r[3] > 0)'; }
expect "the panel has a size" True usage_panel_box
expect "AI Usage's panel hides" ok ipc shell hide panel vgs.ai-usage
expect_poll "the hidden panel is gone" absent usage_panel
expect "opening the panel changed no credential file" kept usage_credentials_kept

# A helper copy that writes the credential file it read fails that reading.
usage_edit "$usage_helper" '    if (file.kind === "refused") return failed(file.reason);' '    if (file.kind === "refused") return failed(file.reason);
    fs.writeFileSync(path.join(directory, ".credentials.json"), file.text);' || fail "the writing control's edit failed"
rescan "the writing copy is scanned"
usage_refresh "the writing copy"
usage_written_control() {
  (failures=0 behaviour_failures=0
   expect "no read may change a credential file" kept usage_credentials_kept >"$usage_dir/written-control.log"
   echo "$failures")
}
expect "a helper that writes the credential file breaks the unchanged reading" 1 usage_written_control
cp -- "$usage_dir/usage.js.stand-in" "$usage_helper"
rescan "the restored helper is scanned"
usage_refresh "the restored helper"
usage_credentials_before="$(usage_credentials)"

# A failed read keeps the last figures, marked stale, never 0 %.
expected_errors+=('ai-usage: account=claude-[0-9a-f]+ failed=http-500')
usage_mode error
usage_refresh "a failed Claude request"
usage_stale='[["stale", [["five_hour", 42], ["seven_day", 83], ["seven_day_opus", 12]]]]'
expect "a failed request keeps the last figures, marked stale" "$usage_stale" usage_windows claude
expect "the widget keeps the stale share" '[true, true, 83, "warning"]' usage_widget_state
expect "the failed read changed no credential file" kept usage_credentials_kept
# A helper copy that reads a failed request as 0 % fails that reading: its
# service, rebuilt, first reads the figures, then the failure.
usage_edit "$usage_helper" '    if (reply.status !== 200) return failed("http-" + reply.status);' '    if (reply.status !== 200) return { state: "ok", plan, windows: [{ name: "five_hour", usedPercent: 0, resetsAt: null }] };' || fail "the zero control's edit failed"
usage_mode ok
rescan "the zero copy is scanned"
usage_refresh "the zero copy's first read"
usage_mode error
usage_refresh "the zero copy's failed read"
usage_zero_control() {
  (failures=0 behaviour_failures=0
   expect "a failed request must keep the last figures" "$usage_stale" usage_windows claude >"$usage_dir/zero-control.log"
   echo "$failures")
}
expect "a helper that reads a failure as 0 % breaks the stale reading" 1 usage_zero_control
usage_mode ok

expect "AI Usage is disabled after the row" ok ipc shell setPluginEnabled vgs.ai-usage false
expect_poll "disabled AI Usage releases its service" False record_exists vgs.ai-usage
cp -- "$usage_dir/usage.js.original" "$usage_helper"
rm -rf -- "${home:?}/.claude" "${home:?}/.codex"
rm -f -- "${shim:?}/codex"
kill "$usage_endpoint" 2>/dev/null || true
wait "$usage_endpoint" 2>/dev/null || true
cp -- "$usage_saved" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
rescan "the AI Usage cleanup is rescanned"
