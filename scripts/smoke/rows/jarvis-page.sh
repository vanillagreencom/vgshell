# The Jarvis page's steps with nothing found: Add key under the key list
# and Accounts under the account list are offered and each opens its
# terminal, every text that names one of them has it offered, with nothing
# found and in a partial search whose row names Accounts, and the AI model
# setting reads its empty text, closed, beside Add key; without a command
# only Accounts needs, the search row offers Install requirements and Add
# key stays offered. With a Copilot account, and only then, Setup shows the
# Copilot Memory step and its link to GitHub. With the fixture's key stored,
# the Setup section of the Settings tab draws the key list, a line per key
# with its chip, and Details draws none; a manifest copy that groups the
# list outside Setup fails both Setup readings. With a Claude Code account
# chosen, and only then, the page offers that account's models and effort
# levels, each led by what its unset setting runs, a choice is saved and
# reaches the daemon, and a model that takes no effort draws no effort
# field. No latency budget.
# Poll once per nested IPC round trip. Only J09's process double and the
# allow-listed TUI fixtures run here.
# inputs: shell/plugins/vgs.jarvis/* bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js shell/plugins/vgs.settings/* shell/Ui/controls/Select.qml shell/Ui/controls/InputWidth.qml shell/Ui/overlay/* shell/Core/PluginLogic.js shell/Core/Capabilities.qml shell/Commons/Reply.js scripts/fixtures/jarvis/* scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml bin/vgshell-tui scripts/smoke/rows/jarvis.sh shell/Commons/AnchorTracker.qml
set -euo pipefail
page_tuis="$repo/shell/plugins/vgs.jarvis/tui"
page_manifest="$repo/shell/plugins/vgs.jarvis/manifest.json"
cp -- "$page_tuis/add-key.sh" "$sandbox/page-add-key-original"
cp -- "$page_tuis/accounts.sh" "$sandbox/page-accounts-original"
cp -- "$page_manifest" "$sandbox/page-manifest-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/add-key.sh" "$page_tuis/add-key.sh"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/accounts.sh" "$page_tuis/accounts.sh"
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
printf 'none\n' >"$sandbox/jarvis-world/key-mode"
terminal_stand_in
terminal_ready "Jarvis page"
jarvis_rescan
jarvis_enable
settings_page_open vgs.jarvis

# KEY's action as the page offers it, and its row's tone; `pending` until
# a rescanned service has reported the row.
page_offered() { status_row vgs.jarvis "$1" | py_reply '
import json,sys
r=json.load(sys.stdin)
reported=r.get("report") == "reported" and isinstance(r.get("value"), dict)
print(json.dumps([r["action"]["label"], r["action"]["offered"], r["value"]["tone"]]) if reported else "pending")
'; }
# Settings starts KEY's action, which hands the terminal TUI's declared
# fixture script under TITLE.
page_open() { # KEY TUI TITLE
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  expect "Settings starts $1's declared action" ok settings_act vgs.jarvis "$1"
  expect_poll "$1's action hands the terminal its declared script" \
    "$(words --app-id=org.vgs.tui "--title=VGS · $3" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record "vgs.jarvis/$2" --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · $3" -- "tui/$2.sh")" recorded
  expect_run_end "the fixture $2 terminal ends" "vgs.jarvis/$2"
}
expect_poll "with no key stored the keyring row offers Add key" '["Add key", true, "info"]' page_offered keyStore
expect_poll "with no account found the search row offers Accounts" '["Accounts", true, "info"]' page_offered accountSearch
page_open keyStore add-key "Add Jarvis key"
page_open accountSearch accounts "Jarvis accounts"

# The page's buttons its texts name, and of those the ones it does not
# offer: every row's hint, each list item's hint and each state's text.
page_named_buttons() {
  status_rows vgs.jarvis | py_reply '
import json,sys
rows=json.load(sys.stdin)
offered={r["action"]["label"] for r in rows if r["action"] is not None and r["action"]["offered"]}
texts=[r.get("hint") or "" for r in rows]
for r in rows:
    value=r.get("value")
    if r["type"] == "presenceList" and isinstance(value, list): texts+=[item.get("hint") or "" for item in value]
    if r["type"] == "state" and isinstance(value, dict): texts+=[value.get("text") or ""]+list(value.get("lines") or [])
named=sorted({button for button in ("Add key", "Accounts") for text in texts if button in text})
print(json.dumps([named, [button for button in named if button not in offered]]))
'
}
expect_poll "every text that names Add key has the button offered" '[["Add key"], []]' page_named_buttons
# Rename every page action for the key TUI, so no other row can supply
# the button the unchanged keyring hint names.
python3 - "$page_manifest" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
manifest=json.loads(s)
changed_keys=[]
for key,row in manifest["status"].items():
    for action in [row.get("action", {})] + list(row.get("actions", {}).values()):
        if action.get("tui") == "add-key":
            action["label"]="Add an API key"
            changed_keys.append(key)
assert "keyStore" in changed_keys
changed=json.dumps(manifest, indent=2)+"\n"
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the label control offers its own step" '["Add an API key", true, "info"]' page_offered keyStore
page_button_control() {
  (failures=0 behaviour_failures=0
   expect "a hint must name only a button the page offers" '[["Add key"], []]' page_named_buttons >"$sandbox/jarvis-page-button-control.log"
   echo "$failures")
}
expect "a hint that names a missing button breaks the named-button read" 1 page_button_control
cp -- "$sandbox/page-manifest-original" "$page_manifest"
jarvis_rescan
expect_poll "the restored page offers Add key again" '["Add key", true, "info"]' page_offered keyStore
# A partial search's row names Accounts, which it offers.
printf 'parent-unreadable\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "a partial search warns and offers Accounts" '["Accounts", true, "warning"]' page_offered accountSearch
expect_poll "every text that names Add key or Accounts has the button offered" '[["Accounts", "Add key"], []]' page_named_buttons
# A manifest copy whose search step reads another label: the search
# row's text then names a button the page lacks.
python3 - "$page_manifest" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='"accountSearch": { "type": "state", "label": "Account search", "group": "AI model", "action": { "label": "Accounts", "tui": "accounts" } }'
assert s.count(needle)==1
changed=s.replace(needle, needle.replace('"label": "Accounts"', '"label": "Find accounts"'))
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the search label control offers its own step" '["Find accounts", true, "warning"]' page_offered accountSearch
page_accounts_control() {
  (failures=0 behaviour_failures=0
   expect "a text must name only a button the page offers" '[["Accounts", "Add key"], []]' page_named_buttons >"$sandbox/jarvis-page-accounts-control.log"
   echo "$failures")
}
expect "a search text that names a missing button breaks the named-button read" 1 page_accounts_control
cp -- "$sandbox/page-manifest-original" "$page_manifest"
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "the restored search finds nothing and offers Accounts" '["Accounts", true, "info"]' page_offered accountSearch

page_field() { ipc smoke invokeInstance window vgs.settings fieldChoice '{"id":"vgs.jarvis","key":"brain"}'; }
page_field_state() { page_field | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["model"], d["value"], d["list"]["open"], d["list"]["empty"] != "" and d["shown"] == d["list"]["empty"]]))'; }
expect_poll "with nothing found the closed AI model setting reads its empty text" '[[], "", false, true]' page_field_state
expect "Add key is offered beside it" '["Add key", true, "info"]' page_offered keyStore

# Each step is withheld only for a command its own terminal needs. Every
# sandbox shell lacks tesseract, which neither step needs, so both are
# offered above. Without ss, which Accounts needs and Add key does not,
# the partial search, whose own text names Accounts, offers Install
# requirements, and no text names a step the page lacks.
expect "the sandbox shell lacks tesseract" none shell_resolves tesseract
printf 'parent-unreadable\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "the partial search offers Accounts before ss goes" '["Accounts", true, "warning"]' page_offered accountSearch
page_ss="$(shell_resolves ss)"
[[ $page_ss == "$sandbox/host-path/ss" ]] || fail "ss resolves outside the sandbox's host links: $page_ss"
mv -- "$page_ss" "$sandbox/page-ss"
rescan "the page rescans without ss"
expect_poll "without ss the search row offers Install requirements" '["Install requirements", true, "warning"]' page_offered accountSearch
expect_poll "without ss Add key is still offered" '["Add key", true, "info"]' page_offered keyStore
expect_poll "without ss every text that names Add key or Accounts has the button offered" '[["Add key"], []]' page_named_buttons
mv -- "$sandbox/page-ss" "$page_ss"
rescan "the page rescans with ss back"
expect_poll "with ss back the partial search offers Accounts" '["Accounts", true, "warning"]' page_offered accountSearch
# Copilot Memory lives in the GitHub account, where only the user can turn
# it off: the Setup section shows that step, with its link to GitHub and no
# action of its own, only while a Copilot account is found. The accounts
# screen's end reads the accounts again.
page_copilot() { status_rows vgs.jarvis | py_reply '
import json,sys
rows=[r for r in json.load(sys.stdin) if r["key"] == "copilotMemory"]
print(json.dumps([[r["group"], r["report"], r["tone"], r["link"]["url"], r["link"]["text"] in r["hint"], r["action"]] for r in rows]))
'; }
expect_poll "with no Copilot account the page draws no Copilot Memory row" '[]' page_copilot
printf 'copilot\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "with a Copilot account Setup shows Copilot Memory and its link to GitHub" '[["Setup", "reported", "info", "https://github.com/settings/copilot/features", true, null]]' page_copilot
# A click on the row's link opens GitHub's page through the desktop open
# route. `gio open` reaches the device fakes' stand-in, which records its
# argv, so no browser starts. The hint line's box is read until two reads
# 100 ms apart agree; the link's words follow the hint's first word, so the
# pointer steps along the line's first row until the link reads it.
page_link="GitHub Copilot settings"
page_hint="$(status_row vgs.jarvis copilotMemory | py_reply 'import json,sys; print(json.load(sys.stdin)["hint"])')" || page_hint=unread
page_link_before="$(device_calls gio | py_reply 'import json,sys; print(len(json.load(sys.stdin)))')" || page_link_before=0
device_reply gio 0 "" open https://github.com/settings/copilot/features
page_link_opens() { device_calls gio | py_reply 'import json,sys; print(json.dumps([" ".join(c) for c in json.load(sys.stdin)[int(sys.argv[1]):]]))' "$page_link_before"; }
page_link_click() {
  local rect last="" x y step
  for _ in $(seq 1 50); do
    rect="$(ipc smoke windowGeometry window vgs.settings LinkText "$page_hint")" || return 1
    [[ $rect == \[* && $rect == "$last" ]] && break
    last="$rect"
    sleep 0.1
  done
  [[ $rect == \[* && $rect == "$last" ]] || { echo "page_link_click: no still hint line: $rect" >&2; return 1; }
  for step in $(seq 1 20); do
    read -r x y < <(at_centre window:Plugins "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(json.dumps([r[0] + 8 * int(sys.argv[2]), r[1], 2, 16]))' "$rect" "$step")") || return 1
    hover "$x" "$y" || return 1
    sleep 0.1
    [[ "$(ipc smoke readMatchingDescendant window vgs.settings LinkText link "$page_link" hoveredLink)" == true ]] && { click "$x" "$y"; return; }
  done
  echo "page_link_click: the pointer found no link words on the hint line" >&2
  return 1
}
page_link_click || fail "the click on the Copilot Memory link failed"
expect_poll "a click on the Copilot Memory link opens GitHub's Copilot settings" '["open https://github.com/settings/copilot/features"]' page_link_opens
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "without the Copilot account the row leaves the page" '[]' page_copilot

# The model and effort of the chosen sign-in. The world's claude stand-in
# lists Opus 5.5, its own default, Fable 5.1 and Haiku 4.5, which takes no
# effort. The fields are read on the Settings tab, which the page opens on.
page_choice() { ipc smoke invokeInstance window vgs.settings fieldChoice "{\"id\":\"vgs.jarvis\",\"key\":\"$1\"}"; }
page_choice_state() { page_choice "$1" | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[m["label"] for m in d["model"]], d["text"], d["value"]]))'; }
page_choose() { ipc smoke invokeInstance window vgs.settings chooseField "{\"id\":\"vgs.jarvis\",\"key\":\"$1\",\"index\":$2}"; }
# The model and effort settings as the user file holds them.
page_saved() { python3 -c 'import json,sys; row=next((r for r in json.load(open(sys.argv[1]))["plugins"] if r["id"]=="vgs.jarvis"), {}); print(json.dumps([row.get("model", ""), row.get("effort", "")]))' "$home/.config/vgshell/shell.json"; }
# The model and effort the running daemon's Session holds.
page_daemon_choice() { ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
detail=d.get("status",{}).get("detail") if isinstance(d,dict) else None
print(json.dumps([detail["state"]["settings"]["model"], detail["state"]["settings"]["effort"]]) if isinstance(detail,dict) else "none")
'; }
page_choice_clear() {
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
for row in value.get("plugins", []):
    if row["id"] == "vgs.jarvis":
        for key in ("brain", "model", "effort"): row.pop(key, None)
p.write_text(json.dumps(value))
PY
  expect "the Jarvis AI model settings are put back" ok ipc shell reloadConfig
}
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "the signed-in Claude Code account is offered as the AI model" '[["Claude Code"], "", ""]' page_choice_state brain
expect "with no sign-in chosen the page draws no model field" absent page_choice model
expect "with no sign-in chosen the page draws no effort field" absent page_choice effort
expect "choosing the Claude Code account is allowed" chosen page_choose brain 0
expect_poll "the page offers the account's models, Fable 5.1 standing for the unset setting" \
  '[["Fable 5.1", "Opus 5.5", "Haiku 4.5"], "Fable 5.1", ""]' page_choice_state model
expect_poll "the page offers Fable 5.1's effort levels, High standing for the unset setting" \
  '[["High", "Low", "Medium", "Extra high", "Max"], "High", ""]' page_choice_state effort
expect_poll "with nothing chosen the daemon gets Fable 5.1 at high" '["claude-fable-5-1", "high"]' page_daemon_choice
expect "nothing chosen saves no model and no effort" '["", ""]' page_saved
expect "choosing Opus 5.5 is allowed" chosen page_choose model 1
expect_poll "the file stores the chosen model as its program names it" '["claude-opus-5-5[1m]", ""]' page_saved
expect_poll "the daemon gets the chosen model at its default effort" '["claude-opus-5-5[1m]", "high"]' page_daemon_choice
expect "choosing the Max effort is allowed" chosen page_choose effort 4
expect_poll "the file stores the chosen effort" '["claude-opus-5-5[1m]", "max"]' page_saved
expect_poll "the daemon gets the chosen effort" '["claude-opus-5-5[1m]", "max"]' page_daemon_choice
expect_poll "the model field shows the saved model" '[["Fable 5.1", "Opus 5.5", "Haiku 4.5"], "Opus 5.5", "claude-opus-5-5[1m]"]' page_choice_state model
expect_poll "the effort field shows the saved effort" '[["High", "Low", "Medium", "Extra high", "Max"], "Max", "max"]' page_choice_state effort
# A model that takes no effort: the effort field leaves the page and no
# effort reaches the daemon, whatever is saved.
expect "choosing Haiku 4.5 is allowed" chosen page_choose model 2
expect_poll "a model that takes no effort draws no effort field" absent page_choice effort
expect_poll "the daemon gets no effort for it" '["claude-haiku-4-5", ""]' page_daemon_choice
expect "the saved effort stays in the file" '["claude-haiku-4-5", "max"]' page_saved
# Without hideEmpty on the effort setting the page keeps the field, with
# only the saved level, marked unavailable.
python3 - "$page_manifest" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='"optionsFrom": "efforts", "hideEmpty": true,'
assert s.count(needle)==1
p.write_text(s.replace(needle, '"optionsFrom": "efforts",'))
PY
jarvis_rescan
expect_poll "the control's page keeps the effort field" '[["max (unavailable)"], "max (unavailable)", "max"]' page_choice_state effort
page_effort_control() {
  (failures=0 behaviour_failures=0
   expect "a model that takes no effort draws no effort field" absent page_choice effort >"$sandbox/jarvis-page-effort-control.log"
   echo "$failures")
}
expect "an effort field with nothing to offer breaks the hidden-field read" 1 page_effort_control
cp -- "$sandbox/page-manifest-original" "$page_manifest"
jarvis_rescan
expect_poll "the restored page draws no effort field for Haiku 4.5" absent page_choice effort
# The first choice of each field returns to the unset setting.
expect "returning to Fable 5.1 is allowed" chosen page_choose model 0
expect_poll "the unset model saves nothing and keeps the saved effort" '["", "max"]' page_saved
expect_poll "the daemon gets Fable 5.1 at the saved effort" '["claude-fable-5-1", "max"]' page_daemon_choice
expect_poll "the effort field is back with the saved level" '[["High", "Low", "Medium", "Extra high", "Max"], "Max", "max"]' page_choice_state effort
expect "returning to High is allowed" chosen page_choose effort 0
expect_poll "the unset effort saves nothing" '["", ""]' page_saved
expect_poll "the daemon gets Fable 5.1 at high again" '["claude-fable-5-1", "high"]' page_daemon_choice
page_choice_clear
expect_poll "with the sign-in unchosen the model field leaves the page" absent page_choice model
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
settings_page_close vgs.jarvis

cp -- "$sandbox/page-add-key-original" "$page_tuis/add-key.sh"
cp -- "$sandbox/page-accounts-original" "$page_tuis/accounts.sh"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "the restored world publishes its fixture key" matched jarvis_key_value present

# The key list with the fixture's key stored. The Settings tab draws it in
# its Setup section, beside Add key: the list's label and hint, then the
# key's line with its chip. Details draws no key list.
page_keys_want="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["status"]["keys"]; print(json.dumps([e["label"], e["hint"], "fixture / test", "Present"]))' "$page_manifest")"
# The key list's row as the shown tab draws it, `rows=0` where it draws none.
page_keys_drawn() { ipc smoke itemTexts window vgs.settings StatusRow | py_reply 'import json,sys; label=json.load(open(sys.argv[1]))["status"]["keys"]["label"]; r=[r for r in json.load(sys.stdin) if r and r[0] == label]; print(json.dumps(r[0]) if len(r) == 1 else "rows=%d" % len(r))' "$page_manifest"; }
# Whether the shown Setup section holds the key's line, its chip and Add key.
page_keys_in_setup() { ipc smoke setupSection window vgs.settings | py_reply 'import json,sys; t=sys.stdin.read(); s=json.loads(t) if t.startswith("{") else {"lines": [], "chips": [], "buttons": []}; print(str("fixture / test" in s["lines"] and ["Present", "success"] in s["chips"] and "Add key" in [b[0] for b in s["buttons"]]).lower())'; }
settings_page_open vgs.jarvis
expect_poll "the page opens on its Settings tab for the key list" 0 settings_tab
expect_poll "the Settings tab draws the key list with the stored key's chip" "$page_keys_want" page_keys_drawn
expect "the key's line and chip stand in the Setup section, with Add key" true page_keys_in_setup
settings_details
expect "Details draws no key list" rows=0 page_keys_drawn
# The control: a manifest copy that groups the key list under AI model, so
# the page draws it on Details. The same readers then find it there and
# not under Setup.
python3 - "$page_manifest" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='"keys": { "type": "presenceList", "label": "Provider keys", "group": "Setup",'
assert s.count(needle)==1
changed=s.replace(needle, needle.replace('"group": "Setup"', '"group": "AI model"'))
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "control: a key list grouped outside Setup draws on Details" "$page_keys_want" page_keys_drawn
settings_tab_click Settings || fail "control: the click back to the Settings tab failed"
expect_poll "control: the copy's page shows its Settings tab" 0 settings_tab
page_keys_control() {
  (failures=0 behaviour_failures=0
   expect "the Settings tab draws the key list" "$page_keys_want" page_keys_drawn >"$sandbox/jarvis-page-keys-control.log"
   expect "the key's line stands in the Setup section" true page_keys_in_setup >>"$sandbox/jarvis-page-keys-control.log"
   echo "$failures")
}
expect "a key list grouped outside Setup breaks both Setup readings" 2 page_keys_control
cp -- "$sandbox/page-manifest-original" "$page_manifest"
jarvis_rescan
expect_poll "the restored page draws the key list under Setup again" "$page_keys_want" page_keys_drawn
expect "the restored key's line stands in the Setup section" true page_keys_in_setup
settings_page_close vgs.jarvis
jarvis_disable
jarvis_notice_close
