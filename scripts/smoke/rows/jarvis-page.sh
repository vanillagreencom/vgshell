# The Jarvis page's steps with nothing found: Add key on the API keys
# step and Accounts on the Account search step, both optional Setup steps,
# are offered and each opens its terminal, every text that names one of them has it offered, with nothing
# found and in a partial search whose row names Accounts, and the AI model
# setting reads its empty text, closed, while Add key stays offered on the
# API keys row; without a command
# only Accounts needs, both stay offered, since a press asks for what its
# terminal lacks. With a Copilot account, and only then, Details shows the
# Copilot Memory step and its link to GitHub. The AI model status hint
# draws a link that opens Settings; plain words fail the link reading.
# The Microphone field's info dialog
# links to the Sounds page. With the fixture's key stored,
# Details draws the key list, a line per key with its chip; Settings and
# Setup draw none. Setup draws the API keys, Account search and Personality
# steps, and Details draws none of them. Local servers appear beside
# the signed-in Claude Code account. With that account chosen, and only
# then, the page offers that account's models and effort
# levels and saves the list's default, a choice is saved and reaches the
# daemon, and a model that takes no effort draws no effort field. The list
# is read only while the page is open: a reader that ignores the page fails
# both closed-page readings. With nothing saved and no list read the daemon
# gets Fable 5.1 at high for the Claude Code account. A list that is not
# read leaves the saved model, marked. With nothing saved it offers the
# daemon's default, marked but unselected. The shell's log holds no
# unexpected line from these steps.
# Two backup models added through the list's Add action sit the group
# list's gap apart, with the hairline in that gap. A fresh profile saves
# no Voice provider and reads Local; a stored Realtime shows the
# Microphone field and survives a shell restart, and with it taken out
# the page reads Local again.
# No latency budget.
# Poll once per nested IPC round trip. Only J09's process double and the
# allow-listed TUI fixtures run here.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.jarvis/backend/Home.js shell/plugins/vgs.jarvis/backend/jarvisd.js shell/Ui/layout/GroupList.qml bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Ui/controls/Select.qml shell/Ui/controls/InputWidth.qml shell/Ui/overlay/* shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Commons/Reply.js scripts/fixtures/jarvis/* scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml bin/vgshell-tui scripts/smoke/rows/jarvis.sh scripts/smoke/rows/settings.sh shell/Commons/AnchorTracker.qml shell/plugins/vgs.sounds/* shell/plugins/vgs.system/* shell/Hosts/PaneHost.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js
set -euo pipefail
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")
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

# The Voice provider: the user file's saved value, from the plugin's row,
# "absent" when it holds none; and the value the page draws, the core's
# merge of the file over the manifest default.
page_voice_saved() {
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
entries=list(value.get("plugins", []))
saved=[row["voiceProvider"] for row in entries if isinstance(row, dict) and row.get("id") == "vgs.jarvis" and "voiceProvider" in row]
print(json.dumps(sorted(set(saved))) if saved else "absent")
PY
}
page_voice() { ipc smoke readInstance window vgs.settings plugins | py_reply 'import json,sys; r=[p["settings"].get("voiceProvider") for p in json.load(sys.stdin) if p["id"] == "vgs.jarvis"]; print(json.dumps(r[0]) if r else "absent")'; }
expect "a fresh profile saves no Voice provider" absent page_voice_saved
expect_poll "a fresh profile reads Local as the Voice provider" '"local"' page_voice

page_home_field() { ipc smoke invokeInstance window vgs.settings fieldChoice '{"id":"vgs.jarvis","key":"home"}'; }
page_home_text() { page_home_field | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["text"]))'; }
page_home_model() { page_home_field | py_reply 'import json,sys; print(json.dumps([row["label"] for row in json.load(sys.stdin)["model"]]))'; }
expect_poll "the Home folder starts with None and the default home" '["None", "~/Jarvis", "Custom\u2026"]' page_home_model
expect "the Settings page writes a fixture Jarvis home" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"home","value":"~/SmokeJarvis"}'
expect_poll "the Home folder offers None, the accepted fixture home, the default home and Custom" '["None", "~/SmokeJarvis", "~/Jarvis", "Custom\u2026"]' page_home_model
# The page leaves no home set for the later steps and rows, and returns to
# its top, which the Custom… editor scrolled from while the written home
# was not yet offered.
expect "the Settings page clears the fixture Jarvis home" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"home","value":""}'
expect_poll "the cleared Home folder still offers the used fixture home" '["None", "~/SmokeJarvis", "~/Jarvis", "Custom\u2026"]' page_home_model
expect_poll "the Home folder reads None" '"None"' page_home_text
ipc smoke scrollTo window vgs.settings 0 >/dev/null || fail "the Jarvis page did not return to its top"

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
# The Voice key field's Add a key entry, as its select calls the page,
# opens the add-key window with its declared argument: the window then adds
# the key of the chosen cloud voice.
forget_record
expect "Add a key on the Voice key field starts its screen" ok \
  ipc smoke invokeInstanceArgs window vgs.settings addChoice '{"args":["vgs.jarvis","voiceAccount"]}'
expect_poll "Add a key opens the add-key window for the chosen cloud voice" '["vgs.jarvis/add-voice-key", "tui/add-key.sh", "voice"]' recorded_tail
expect_run_end "the fixture add-voice-key terminal ends" "vgs.jarvis/add-voice-key"

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
expect_poll "no text names a button the page does not offer" '[[], []]' page_named_buttons
# A partial search's row names Accounts, which it offers.
printf 'parent-unreadable\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "a partial search warns and offers Accounts" '["Accounts", true, "warning"]' page_offered accountSearch
expect_poll "every text that names Accounts has the button offered" '[["Accounts"], []]' page_named_buttons
# A manifest copy whose search step reads another label: the search
# row's text then names a button the page lacks.
python3 - "$page_manifest" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
manifest=json.loads(s)
assert manifest["status"]["accountSearch"]["action"]["label"] == "Accounts"
manifest["status"]["accountSearch"]["action"]["label"] = "Find accounts"
changed=json.dumps(manifest, indent=2)+"\n"
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the search label control offers its own step" '["Find accounts", true, "warning"]' page_offered accountSearch
page_accounts_control() {
  (failures=0 behaviour_failures=0
   expect "a text must name only a button the page offers" '[["Accounts"], []]' page_named_buttons >"$sandbox/jarvis-page-accounts-control.log"
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
expect "Add key is still offered on the API keys row" '["Add key", true, "info"]' page_offered keyStore

# A step stays offered whatever command its own terminal lacks: its press
# asks for that command first. Every sandbox shell lacks tesseract, which
# neither step needs. Without ss, which Accounts needs and Add key does
# not, the partial search, whose own text names Accounts, still offers
# Accounts, and no text names a step the page lacks.
expect "the sandbox shell lacks tesseract" none shell_resolves tesseract
printf 'parent-unreadable\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "the partial search offers Accounts before ss goes" '["Accounts", true, "warning"]' page_offered accountSearch
page_ss="$(shell_resolves ss)"
[[ $page_ss == "$sandbox/host-path/ss" ]] || fail "ss resolves outside the sandbox's host links: $page_ss"
mv -- "$page_ss" "$sandbox/page-ss"
rescan "the page rescans without ss"
expect_poll "without ss the search row still offers Accounts" '["Accounts", true, "warning"]' page_offered accountSearch
expect_poll "without ss Add key is still offered" '["Add key", true, "info"]' page_offered keyStore
expect_poll "without ss every text that names Accounts has the button offered" '[["Accounts"], []]' page_named_buttons
mv -- "$sandbox/page-ss" "$page_ss"
rescan "the page rescans with ss back"
expect_poll "with ss back the partial search offers Accounts" '["Accounts", true, "warning"]' page_offered accountSearch
# Copilot Memory lives in the GitHub account, where only the user can turn
# it off: Details shows that state, with its GitHub link and no action of
# its own, only while a Copilot account is found. The accounts screen's
# end reads the accounts again.
page_copilot() { status_rows vgs.jarvis | py_reply '
import json,sys
rows=[r for r in json.load(sys.stdin) if r["key"] == "copilotMemory"]
print(json.dumps([[r["report"], r["tone"], r["link"]["url"], r["link"]["text"] in r["hint"], r["action"]] for r in rows]))
'; }
expect_poll "with no Copilot account the page draws no Copilot Memory row" '[]' page_copilot
jarvis_notice_close
printf 'copilot\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "with a Copilot account the page shows Copilot Memory" '[["reported", "info", "https://github.com/settings/copilot/features", true, null]]' page_copilot
# A click on the row's link opens GitHub's page through the desktop open
# route. `gio open` reaches the device fakes' stand-in, which records its
# argv, so no browser starts. The page is scrolled first so the hint line
# lies in view, as a user scrolls to a row below the fold. That puts the line at
# the screen's centre, where the requirement notice that enabling Jarvis
# raised sits and takes the pointer, so the step closes the notice before
# it reads the accounts. The hint line's box is then read until two reads
# 100 ms apart agree. The pointer then steps along the first line of the
# link's words box (LinkText.linkBox), which spans the whole width when
# the words wrap, until the link reads it.
page_link="GitHub Copilot settings"
page_hint="$(status_row vgs.jarvis copilotMemory | py_reply 'import json,sys; print(json.load(sys.stdin)["hint"])')" || page_hint=unread
page_link_before="$(device_calls gio | py_reply 'import json,sys; print(len(json.load(sys.stdin)))')" || page_link_before=0
device_reply gio 0 "" open https://github.com/settings/copilot/features
page_link_opens() { device_calls gio | py_reply 'import json,sys; print(json.dumps([" ".join(c) for c in json.load(sys.stdin)[int(sys.argv[1]):]]))' "$page_link_before"; }
page_link_click() {
  local shown rect last="" words box x y step steps
  shown="$(ipc smoke revealText window vgs.settings LinkText "$page_hint")" || return 1
  [[ $shown =~ ^[0-9.]+$ ]] || { echo "page_link_click: no hint line to reveal: $shown" >&2; return 1; }
  for _ in $(seq 1 50); do
    rect="$(ipc smoke windowGeometry window vgs.settings LinkText "$page_hint")" || return 1
    [[ $rect == \[* && $rect == "$last" ]] && break
    last="$rect"
    sleep 0.1
  done
  [[ $rect == \[* && $rect == "$last" ]] || { echo "page_link_click: no still hint line: $rect" >&2; return 1; }
  # A rect value lists x, y, width and height as own keys, so the probe's
  # JSON carries them (Qt 6.11 qqmlvaluetypewrapper_p.h,
  # virtualOwnPropertyKeys).
  # Other tabs can hold a different hint with the same link words. Read
  # the box and hover state from the exact line whose geometry was read.
  words="$(ipc smoke readMatchingDescendant window vgs.settings LinkText text "$page_hint" words | py_reply 'import json,sys; print(json.load(sys.stdin))')" || return 1
  [[ $words == "$page_link" ]] || { echo "page_link_click: link words differ: $words" >&2; return 1; }
  box="$(ipc smoke readMatchingDescendant window vgs.settings LinkText text "$page_hint" linkBox)" || return 1
  [[ $box == \{* ]] || { echo "page_link_click: no link box: $box" >&2; return 1; }
  steps="$(python3 -c 'import json,sys; print(max(1, int(json.loads(sys.argv[1])["width"] // 8)))' "$box")" || return 1
  for step in $(seq 0 "$steps"); do
    read -r x y < <(at_centre window:Plugins "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); b=json.loads(sys.argv[2]); print(json.dumps([r[0] + b["x"] + 8 * int(sys.argv[3]), r[1] + b["y"], 2, 16]))' "$rect" "$box" "$step")") || return 1
    hover "$x" "$y" || return 1
    sleep 0.1
    [[ "$(ipc smoke readMatchingDescendant window vgs.settings LinkText text "$page_hint" hoveredLink)" == true ]] && { click "$x" "$y"; return; }
  done
  echo "page_link_click: the pointer found no link words in line=$rect box=$box" >&2
  return 1
}
settings_details
page_link_click || fail "the click on the Copilot Memory link failed"
expect_poll "a click on the Copilot Memory link opens GitHub's Copilot settings" '["open https://github.com/settings/copilot/features"]' page_link_opens
settings_tab_click Settings || fail "the click back to the Settings tab after the link failed"
expect_poll "the page shows its Settings tab again" 0 settings_tab
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "without the Copilot account the row leaves the page" '[]' page_copilot

# The AI model hint on Setup opens the Settings tab at its field.
# The control keeps its words and drops only their page reference.
page_gate="$repo/shell/plugins/vgs.jarvis/SetupGate.js"
cp -- "$page_gate" "$sandbox/page-gate-original"
expect "the page clears the chosen AI account" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"brain","value":""}'
page_model_hint() { status_row vgs.jarvis setupModel | py_reply 'import json,sys; print(json.load(sys.stdin).get("hint", "absent"))'; }
page_model_hint_link() {
  ipc smoke readMatchingDescendant window vgs.settings LinkText text "$page_hint" reference | py_reply '
import json,sys
r=json.load(sys.stdin)
print(json.dumps([r.get("page"), r.get("tab"), bool(r.get("words"))]))
'
}
page_model_link_assertion() { expect "the AI model hint draws its link to the field" '["vgs.jarvis", "Settings/brain", true]' page_model_hint_link; }
settings_setup
expect_poll "the AI model step links its field" 'Choose an AI model in [AI model](page:vgs.jarvis/Settings/brain)' page_model_hint
page_hint="$(page_model_hint)"
page_link="AI model"
ipc smoke revealText window vgs.settings LinkText "$page_hint" >/dev/null || fail "the AI model hint is not drawn"
page_model_link_assertion
page_link_click || fail "the click on the AI model hint failed"
expect_poll "the AI model hint opens the Settings tab" '"vgs.jarvis/Settings"' ipc smoke readInstance window vgs.settings shownPage
jarvis_disable
python3 - "$page_gate" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text()
needle='"brain=unselected": "Choose an AI model in [AI model](page:vgs.jarvis/Settings/brain)"'
assert s.count(needle)==1
changed=s.replace(needle, '"brain=unselected": "Choose an AI model in AI model"')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
settings_setup
expect_poll "the control keeps the AI model hint's plain words" 'Choose an AI model in AI model' page_model_hint
page_hint="$(page_model_hint)"
ipc smoke revealText window vgs.settings LinkText "$page_hint" >/dev/null || fail "the control's AI model hint is not drawn"
page_model_link_control() {
  (failures=0 behaviour_failures=0
   page_model_link_assertion >"$sandbox/jarvis-page-link-control.log"
   echo "$failures")
}
expect "plain AI model words fail the rendered-link assertion" 1 page_model_link_control
jarvis_disable
cp -- "$sandbox/page-gate-original" "$page_gate"
jarvis_rescan
jarvis_enable
jarvis_notice_close
settings_tab_click Settings || fail "the page did not return to Settings after the hint control"

# The model and effort of the chosen sign-in. The world's claude stand-in
# lists Opus 5.5, its own default, Fable 5.1 and Haiku 4.5, which takes no
# effort. The page reads the list only while it is open, and the world's
# worker writes a line beside its mode file for each read. The fields are
# read on the Settings tab, which the page opens on.
page_choice() { ipc smoke invokeInstance window vgs.settings fieldChoice "{\"id\":\"vgs.jarvis\",\"key\":\"$1\"}"; }
page_choice_state() { page_choice "$1" | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[m["label"] for m in d["model"]], d["text"], d["value"]]))'; }
page_choice_drawn() { if [[ "$(page_choice "$1")" == \{* ]]; then echo drawn; else echo absent; fi; }
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
# How many model list reads the world's worker has run.
page_reads() { if [[ -f "$sandbox/jarvis-world/model-reads" ]]; then wc -l <"$sandbox/jarvis-world/model-reads" | tr -d ' '; else echo 0; fi; }
# Take each named Jarvis setting out of the user file's plugin row, which
# the page and the service both read.
page_settings_drop() {
  user_config_write python3 - "$home/.config/vgshell/shell.json" "$@" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
for row in value.get("plugins", []):
    if isinstance(row, dict) and row.get("id") == "vgs.jarvis":
        for key in sys.argv[2:]: row.pop(key, None)
print(json.dumps(value))
PY
  expect "the user file's Jarvis settings are read again" ok ipc shell reloadConfig
}
# Where the shell's log stands before the model steps: they end with a
# check of what they logged.
page_log_start="$(wc -c <"$instance_log")"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
expect_poll "the AI model list offers Claude Code and local servers" '[["Claude Code, team@example.invalid", "LM Studio, local", "Ollama, local", "llama-server, local"], "", ""]' page_choice_state brain
expect "with no sign-in chosen the page draws no model field" absent page_choice model
expect "with no sign-in chosen the page draws no effort field" absent page_choice effort
page_reads_start="$(page_reads)"
expect "choosing the Claude Code account is allowed" chosen page_choose brain 0
expect_poll "the page saves the list's default, Fable 5.1 at high" '["claude-fable-5-1", "high"]' page_saved
expect_poll "the page offers the account's models, the saved one first" \
  '[["Fable 5.1", "Opus 5.5", "Haiku 4.5"], "Fable 5.1", "claude-fable-5-1"]' page_choice_state model
expect_poll "the page offers Fable 5.1's effort levels" \
  '[["High", "Low", "Medium", "Extra high", "Max"], "High", "high"]' page_choice_state effort
expect_poll "the daemon gets Fable 5.1 at high" '["claude-fable-5-1", "high"]' page_daemon_choice
expect "choosing Opus 5.5 is allowed" chosen page_choose model 1
expect_poll "the file stores the chosen model as its program names it" '["claude-opus-5-5[1m]", "high"]' page_saved
expect_poll "the daemon gets the chosen model" '["claude-opus-5-5[1m]", "high"]' page_daemon_choice
expect "choosing the Max effort is allowed" chosen page_choose effort 4
expect_poll "the file stores the chosen effort" '["claude-opus-5-5[1m]", "max"]' page_saved
expect_poll "the daemon gets the chosen effort" '["claude-opus-5-5[1m]", "max"]' page_daemon_choice
expect_poll "the model field shows the saved model" '[["Fable 5.1", "Opus 5.5", "Haiku 4.5"], "Opus 5.5", "claude-opus-5-5[1m]"]' page_choice_state model
expect_poll "the effort field shows the saved effort" '[["High", "Low", "Medium", "Extra high", "Max"], "Max", "max"]' page_choice_state effort
# A model that takes no effort: the effort field leaves the page and the
# saved effort goes with it.
expect "choosing Haiku 4.5 is allowed" chosen page_choose model 2
expect_poll "a model that takes no effort draws no effort field" absent page_choice effort
expect_poll "the page saves no effort for it" '["claude-haiku-4-5", ""]' page_saved
expect_poll "the daemon gets no effort for it" '["claude-haiku-4-5", ""]' page_daemon_choice
expect "the sign-in's choice read its list once, and no changed model or effort read it again" "$((page_reads_start + 1))" page_reads
# Without hideEmpty on the effort setting the page keeps the field, with
# nothing to choose.
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
expect_poll "the control's page keeps the effort field" drawn page_choice_drawn effort
page_effort_control() {
  (failures=0 behaviour_failures=0
   expect "a model that takes no effort draws no effort field" absent page_choice effort >"$sandbox/jarvis-page-effort-control.log"
   echo "$failures")
}
expect "an effort field with nothing to offer breaks the hidden-field read" 1 page_effort_control
cp -- "$sandbox/page-manifest-original" "$page_manifest"
jarvis_rescan
expect_poll "the restored page draws no effort field for Haiku 4.5" absent page_choice effort
# The first choice of the model field saves the list's default again.
expect_poll "the restored page reads the list again" '[["Fable 5.1", "Opus 5.5", "Haiku 4.5"], "Haiku 4.5", "claude-haiku-4-5"]' page_choice_state model
expect "returning to Fable 5.1 is allowed" chosen page_choose model 0
expect_poll "the first choice saves Fable 5.1 at high" '["claude-fable-5-1", "high"]' page_saved
expect_poll "the daemon gets Fable 5.1 at high again" '["claude-fable-5-1", "high"]' page_daemon_choice

# The list is read only while the Jarvis page is open. With the page closed
# a changed setting reads no list and nothing is saved, and for the Claude
# Code account with nothing saved the daemon gets Fable 5.1 at high. Opus
# 5.5 is saved first, so that reading follows the drop.
expect "choosing Opus 5.5 again is allowed" chosen page_choose model 1
expect_poll "the daemon gets Opus 5.5 while it is saved" '["claude-opus-5-5[1m]", "high"]' page_daemon_choice
settings_page_close vgs.jarvis
page_reads_closed="$(page_reads)"
page_settings_drop model effort
expect_poll "with nothing saved and no list read the daemon gets Fable 5.1 at high" '["claude-fable-5-1", "high"]' page_daemon_choice
expect "with the page closed nothing is saved" '["", ""]' page_saved
expect "a setting changed with the page closed reads no list" "$page_reads_closed" page_reads
# The control: a reader that wants the list whatever the page shows reads
# it with the page closed and saves its default.
page_reader="$repo/shell/plugins/vgs.jarvis/Accounts.qml"
cp -- "$page_reader" "$sandbox/page-reader-original"
python3 - "$page_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='readonly property string wanted: shell !== null && shell.status.viewed ? brain : ""'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'readonly property string wanted: brain'))
PY
jarvis_rescan
expect_poll "the control's reader reads the list with the page closed" '["claude-fable-5-1", "high"]' page_saved
page_closed_control() {
  (failures=0 behaviour_failures=0
   expect "with the page closed nothing is saved" '["", ""]' page_saved >"$sandbox/jarvis-page-closed-control.log"
   expect "a setting changed with the page closed reads no list" "$page_reads_closed" page_reads >>"$sandbox/jarvis-page-closed-control.log"
   echo "$failures")
}
expect "a list read with the page closed breaks both closed-page readings" 2 page_closed_control
cp -- "$sandbox/page-reader-original" "$page_reader"
jarvis_rescan
page_settings_drop model effort
expect_poll "the restored reader runs the unsaved default" '["claude-fable-5-1", "high"]' page_daemon_choice
expect "the restored reader saves nothing with the page closed" '["", ""]' page_saved
# Opening the page reads the list once and saves its default.
page_reads_closed="$(page_reads)"
settings_page_open vgs.jarvis
expect_poll "opening the page saves the list's default" '["claude-fable-5-1", "high"]' page_saved
expect "opening the page read the list once" "$((page_reads_closed + 1))" page_reads
# A list its program does not give: the page shows the saved model, marked,
# and with nothing saved offers the daemon's default, marked but unselected.
# The reader logs the read's cause.
settings_page_close vgs.jarvis
printf 'list-failed\n' >"$sandbox/jarvis-world/account-mode"
expected_errors+=('jarvis-accounts: models=harness-exit')
settings_page_open vgs.jarvis
expect_poll "a list that is not read leaves the saved model, marked" \
  '[["claude-fable-5-1 (list not read)"], "claude-fable-5-1 (list not read)", "claude-fable-5-1"]' page_choice_state model
expect "the saved choice stays in the file" '["claude-fable-5-1", "high"]' page_saved
page_settings_drop model effort
expect_poll "with nothing saved a failed list offers the marked default without selecting it" \
  '[["claude-fable-5-1 (list not read)"], "", ""]' page_choice_state model
expect "a list that is not read saves nothing" '["", ""]' page_saved
page_settings_drop brain
expect_poll "with the sign-in unchosen the model field leaves the page" absent page_choice model
printf 'none\n' >"$sandbox/jarvis-world/account-mode"
page_open accountSearch accounts "Jarvis accounts"
settings_page_close vgs.jarvis
# The model steps wrote the settings from the reader and from the page. The
# next row starts a new shell, so what this shell logged in those steps is
# read here.
tail -c "+$((page_log_start + 1))" -- "$instance_log" >"$sandbox/jarvis-page-model-steps.log"
check_unexpected_log "the shell's log of the model steps" "$sandbox/jarvis-page-model-steps.log"

cp -- "$sandbox/page-add-key-original" "$page_tuis/add-key.sh"
cp -- "$sandbox/page-accounts-original" "$page_tuis/accounts.sh"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "the restored world publishes its fixture key" matched jarvis_key_value present

# The provider key list is a Details reading: Jarvis stores its keys
# itself, so no masked field of the core's holds them and Settings and
# Setup draw no list. The Details reading proves the read sees the list.
page_keys_want="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["status"]["keys"]; print(json.dumps([e["label"], e["hint"], "fixture / test", "Present"]))' "$page_manifest")"
# API keys, Account search and Personality are optional Setup steps: each
# draws on Setup, and none of their labels heads a Details row.
page_moved=("keyStore" "accountSearch" "personality")
page_moved_setup() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; drawn={r["key"] for r in json.load(sys.stdin)}; print(json.dumps([k for k in sys.argv[1:] if k in drawn]))' "${page_moved[@]}"; }
page_moved_details() { ipc smoke itemTexts window vgs.settings StatusRow | py_reply 'import json,sys; status=json.load(open(sys.argv[1]))["status"]; labels=[status[k]["label"] for k in sys.argv[2:]]; print(json.dumps([r[0] for r in json.load(sys.stdin) if r and r[0] in labels]))' "$page_manifest" "${page_moved[@]}"; }
page_moved_want="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${page_moved[@]}")"
page_keys_drawn() { ipc smoke itemTexts window vgs.settings StatusRow | py_reply 'import json,sys; label=json.load(open(sys.argv[1]))["status"]["keys"]["label"]; r=[r for r in json.load(sys.stdin) if r and r[0] == label]; print(json.dumps(r[0]) if len(r) == 1 else "rows=%d" % len(r))' "$page_manifest"; }
settings_page_open vgs.jarvis
expect_poll "the page opens Settings with no provider key list" rows=0 page_keys_drawn
settings_setup
expect "Setup draws no provider key list" rows=0 page_keys_drawn
expect_poll "Setup draws the API keys, Account search and Personality steps" "$page_moved_want" page_moved_setup
settings_details
expect_poll "Details draws the provider key list" "$page_keys_want" page_keys_drawn
expect "Details draws no API keys, Account search or Personality row" '[]' page_moved_details
settings_tab_click Settings || fail "the click back to Settings after the key list failed"
expect_poll "the page shows Settings for the backup models" 0 settings_tab

# Two backup models, added through the list's Add action, sit
# `groupList.gap` apart, from the bottom of the first entry's last row to
# the top of the second entry's first row, with the one hairline in that
# gap; where in the gap it sits follows the drawn pixels, which
# tst_grouplist.qml reads from an image. Text inside a row, such as a
# hint's leading or a label centred in its row, is not gap. The controls
# plant the same reading with a trailing 8 px in the first entry, which
# moves the second entry and the hairline, and with the hairline 20 px
# low, inside the second entry. `[]` is the pass.
page_backups() { ipc smoke invokeInstance window vgs.settings listItems '{"id":"vgs.jarvis","key":"fallbacks"}' | py_reply 'import json,sys; t=sys.stdin.read(); print(json.dumps([i["name"] for i in json.loads(t)]) if t.startswith("[") else t)'; }
page_backup_gap() { # [trailing|hairline]
  local rows gap
  ipc smoke descendantGeometry window vgs.settings >"$sandbox/rows/jarvis-page.geometry.json" || return
  gap="$(ipc smoke themeValue groupList.gap)" || return
  python3 - "$sandbox/rows/jarvis-page.geometry.json" "$gap" "${1:-}" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
if not text.startswith("[") or not sys.argv[2][:1].isdigit():
    print(json.dumps(["unread=%s gap=%s" % (text[:40], sys.argv[2])])); sys.exit()
rows, gap = json.loads(text), json.loads(sys.argv[2])
plant = sys.argv[3]
def shown(i):
    while i != -1:
        if not rows[i]["visible"]: return False
        i = rows[i]["parent"]
    return True
def kids(i, sized=True): return [j for j, r in enumerate(rows) if r["parent"] == i and shown(j) and (not sized or r["box"][2] > 0 and r["box"][3] > 0)]
fields = [i for i, r in enumerate(rows) if r["type"] == "ListField" and shown(i)]
if len(fields) != 1: print(json.dumps(["list-fields=%d" % len(fields)])); sys.exit()
lists = [j for j in kids(fields[0]) if rows[j]["type"] == "GroupList"]
# The probe names the plain Item that holds the groups by its C++ type.
columns = [j for j in kids(lists[0]) if rows[j]["type"] == "QQuickItem"] if len(lists) == 1 else []
if len(columns) != 1: print(json.dumps(["group-lists=%d columns=%d" % (len(lists), len(columns))])); sys.exit()
entries = sorted(kids(columns[0]), key=lambda j: rows[j]["box"][1])
lines = sorted((rows[j]["box"][1], rows[j]["box"][3]) for j in kids(lists[0], False) if rows[j]["type"] == "Divider")
if len(entries) != 2 or len(lines) != 1: print(json.dumps(["entries=%d hairlines=%d" % (len(entries), len(lines))])); sys.exit()
bottom = max(rows[j]["box"][1] + rows[j]["box"][3] for j in kids(entries[0]))
top = min(rows[j]["box"][1] for j in kids(entries[1]))
line_top, line_height = lines[0]
if plant == "trailing": top, line_top = top + 8, line_top + 8
if plant == "hairline": line_top += 20
out = []
if abs(top - bottom - gap) > 1: out.append("gap=%.2f want=%d" % (top - bottom, gap))
if line_top < bottom or line_top + line_height > top: out.append("hairline=%.2f outside %.2f to %.2f" % (line_top, bottom, top))
print(json.dumps(out))
PY
}
expect "the first backup model is added" clicked ipc smoke invokeInstance window vgs.settings listAdd '{"id":"vgs.jarvis","key":"fallbacks"}'
expect "the second backup model is added" clicked ipc smoke invokeInstance window vgs.settings listAdd '{"id":"vgs.jarvis","key":"fallbacks"}'
expect_poll "the page draws two backup models" '["1", "2"]' page_backups
geometry expect_poll "two backup models sit groupList.gap apart with the hairline in the gap" '[]' page_backup_gap
page_backup_planted() { page_backup_gap "$1" | py_reply 'import json,sys; print(any(e.startswith(sys.argv[1]) for e in json.load(sys.stdin)))' "$2"; }
expect "control: a trailing 8 px in the first entry is refused" True page_backup_planted trailing gap=
expect "control: a hairline 20 px low is refused" True page_backup_planted hairline hairline=
expect "the first backup model is removed" clicked ipc smoke invokeInstance window vgs.settings listRemove '{"id":"vgs.jarvis","key":"fallbacks","name":"1"}'
expect_poll "the page draws one backup model" '["2"]' page_backups
expect "the second backup model is removed" clicked ipc smoke invokeInstance window vgs.settings listRemove '{"id":"vgs.jarvis","key":"fallbacks","name":"2"}'
expect_poll "the page draws no backup model" '[]' page_backups

# The Microphone field, shown under a cloud voice, keeps the feedback-tones
# link in its info dialog. The configuration file stores Realtime: a choice
# on the page would open Add a key, as this world stores no voice key. The
# System window starts disabled and is restored after this reading.
user_config_write python3 - "$home/.config/vgshell/shell.json" <<'PY' || fail "Realtime could not be stored"
import json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
row["voiceProvider"]="realtime"
print(json.dumps(value))
PY
expect "the stored Realtime reaches the shell" ok ipc shell reloadConfig
expect_poll "the page reads Realtime as the Voice provider" '"realtime"' page_voice
page_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
page_info_text="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["schema"]["microphone"]["info"])' "$repo/shell/plugins/vgs.jarvis/manifest.json")" ||
  fail "the Microphone info is unreadable"
expect_poll "no pane is mounted before the Sounds link's click" '[]' window_panes
settings_press --type InfoButton "About Microphone" SettingField Microphone || fail "the Microphone info did not open"
expect_poll "the Microphone info shows its page link" shown info_link_shown "$page_info_text"
info_link_click "$page_info_text" || fail "the Sounds page link did not activate"
expect_poll "the Microphone info link opens the Sounds page" '["vgs.sounds"]' window_panes
expect "the System window hides after the Sounds link" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after the Sounds link" 0 window_count 'System Settings'
[[ $page_system_was == True ]] && page_system_want=true || page_system_want=false
expect "the System window's enablement is put back" ok ipc shell setPluginEnabled vgs.system "$page_system_want"
expect_poll "vgs.system's enablement is as the row found it" "$page_system_was" plugin_enabled vgs.system

# The stored Voice provider survives a shell restart. After the restart
# the step takes it out and the page reads Local again.
expect_poll "the user file holds Realtime" '["realtime"]' page_voice_saved
settings_page_close vgs.jarvis
jarvis_disable
jarvis_notice_close
stop_shell || :
start_shell "$repo" "$sandbox/jarvis-page-restarted.log"
settings_page_open vgs.jarvis
expect_poll "the stored Realtime survives a shell restart" '"realtime"' page_voice
page_settings_drop voiceProvider
expect "the user file holds no Voice provider again" absent page_voice_saved
expect_poll "with nothing saved the Voice provider reads Local" '"local"' page_voice
settings_page_close vgs.jarvis
