# The Jarvis page's steps with nothing found: Add key under the key list
# and Accounts under the account list are offered and each opens its
# terminal, every text that names one of them has it offered, with nothing
# found and in a partial search whose row names Accounts, and the AI model
# setting reads its empty text and opens on one empty line from a Space
# press, beside Add key; without a command only Accounts needs, the search
# row offers Install requirements and Add key stays offered. No latency
# budget.
# Poll once per nested IPC round trip. Only J09's process double and the
# allow-listed TUI fixtures run here.
# inputs: shell/plugins/vgs.jarvis/* bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js shell/plugins/vgs.settings/* shell/Ui/controls/Select.qml shell/Ui/overlay/* shell/Core/PluginLogic.js shell/Core/Capabilities.qml shell/Commons/Reply.js scripts/fixtures/jarvis/* scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml bin/vgshell-tui scripts/smoke/rows/jarvis.sh
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
    action=row.get("action", {})
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

# The open list as one empty line: open, no entry to choose, and one drawn
# line reading the Select's own emptyText.
page_empty_line() { py_reply 'import json,sys; d=json.load(sys.stdin); print("one-line" if d["open"] and d["entries"] == 0 and d["empty"] != "" and d["lines"] == [d["empty"]] else "no-line")'; }
page_copy_line() { ipc smoke popupSelectList "$1" | page_empty_line; }
# Copies of the shipped Select, one as shipped and one whose empty line
# never draws, an empty popup. The type loader keeps the listing of a
# directory it has read, so a .qml file written later beside the shipped
# ones is refused as a file name case mismatch: the copies
# go in a fresh folder under overlay/, named as the types they make, and
# import the two directories whose internal types the Select draws
# (AnchorTracker and ListMask, ScrollBar and ListCursorRow). Each closes
# with its drop before the next opens.
page_copy_dir="$repo/shell/Ui/overlay/jarvis-page-copies"
mkdir -- "$page_copy_dir"
page_copies=("$page_copy_dir/SelectEmptyLine.qml" "$page_copy_dir/SelectNoEmptyLine.qml")
python3 - "$repo/shell/Ui/controls/Select.qml" "${page_copies[@]}" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
assert source.count("import qs.Ui\n") == 1
copy = source.replace("import qs.Ui\n", "import qs.Ui\nimport \"..\"\nimport \"../../layout\"\n")
needle = "            visible: root.showsEmpty\n"
assert copy.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(copy)
pathlib.Path(sys.argv[3]).write_text(copy.replace(needle, "            visible: false\n"))
PY
page_props='{"emptyText":"None found yet"}'
expect "the probe builds the shipped Select copy" ok ipc smoke popupLoad page-empty-line "${page_copies[0]}" window vgs.settings "$page_props"
expect "the shipped copy opens with nothing to choose" ok ipc smoke popupCall page-empty-line openList
expect_poll "the shipped copy draws one empty line" one-line page_copy_line page-empty-line
expect "the probe drops the shipped copy" ok ipc smoke popupDrop page-empty-line
expect "the probe builds the copy without the empty line" ok ipc smoke popupLoad page-no-line "${page_copies[1]}" window vgs.settings "$page_props"
expect "the control copy opens with nothing to choose" ok ipc smoke popupCall page-no-line openList
expect_poll "the control copy's list is open" true ipc smoke popupRead page-no-line listOpen
page_line_control() {
  (failures=0 behaviour_failures=0
   expect "the open list must draw its empty line" one-line page_copy_line page-no-line >"$sandbox/jarvis-page-line-control.log"
   echo "$failures")
}
expect "an empty popup breaks the empty-line read" 1 page_line_control
expect "the probe drops the control copy" ok ipc smoke popupDrop page-no-line
rm -- "${page_copies[@]}" && rmdir -- "$page_copy_dir" || fail "removing the Select copies failed"

page_field() { ipc smoke invokeInstance window vgs.settings fieldChoice '{"id":"vgs.jarvis","key":"brain"}'; }
page_field_state() { page_field | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["model"], d["value"], d["list"]["open"], d["list"]["empty"] != "" and d["shown"] == d["list"]["empty"]]))'; }
page_field_line() { page_field | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["list"]))' | page_empty_line; }
expect_poll "with nothing found the closed AI model setting reads its empty text" '[[], "", false, true]' page_field_state
# The terminals the row opened held the keyboard, so a focus dispatch
# hands it back to the Settings window before the field takes Qt's focus
# and the key is typed.
page_settings_address="$(window_address Plugins)" || page_settings_address=""
[[ $page_settings_address == 0x* ]] || fail "the Settings window's address is unreadable: $page_settings_address"
expect "a focus dispatch aimed at the Settings window answers ok" ok hypr dispatch "hl.dsp.focus({ window = \"address:$page_settings_address\" })"
expect_poll "the Settings window has the keyboard" "[\"$shell_class\", \"Plugins\"]" active_window
expect "the AI model setting takes the focus" focused ipc smoke invokeInstance window vgs.settings focusField '{"id":"vgs.jarvis","key":"brain"}'
type_keys -k space || fail "Space on the AI model setting failed"
expect_poll "the AI model setting draws one empty line" one-line page_field_line
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
settings_page_close vgs.jarvis

cp -- "$sandbox/page-add-key-original" "$page_tuis/add-key.sh"
cp -- "$sandbox/page-accounts-original" "$page_tuis/accounts.sh"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "the restored world publishes its fixture key" matched jarvis_key_value present
jarvis_disable
jarvis_notice_close
