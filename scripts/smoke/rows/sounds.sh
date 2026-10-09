# The core's sound service: a manifest's `sounds` events, capability
# `sounds`, which plays a plugin's own event through the one player,
# capability `soundSettings`, the one writer of shell.json `sounds`, and
# the Sounds section of the System window that sets each event's sound.
#
# The player is the pw-play stand-in of scripts/smoke/devices.sh, which
# records the file it was asked to play and plays nothing, so the row reads
# what would sound and no speaker does.
#
# Through the acme.sounds fixture the row reads the two capabilities'
# members and that the fixture holds them, the page's alone, the fixture's
# four events as the page lists them with the values each takes, and each
# answer of a play: an event plays its manifest default, one that is off by
# default answers `off` and starts no player, one the plugin sounds itself
# and an undeclared one are refused, and three plays of one event in one
# turn start one player. It writes a choice and reads it in the user file,
# in the fixture's own choices and in the next play; off silences the
# event; the manifest's default removes the choice from the file; a sound
# outside the core's set and an unknown plugin are refused and write
# nothing. Test plays a sound of the set and refuses another.
#
# The run limit: the row stands over the player with one that records its
# process and then sleeps, as a pw-play that PipeWire never answers. The
# play answers ok and the sound shows as playing; a second play in a later
# turn answers busy; then the service's own `runLimit` timer, 10 s of real
# time, must stop that process, log the unplayed sound and empty the
# playing list, and with the stand-in back the event plays again. This is
# a reading of the timer's wiring, which only elapsed time shows: it waits
# those 10 s inside expect_poll's bound and budgets no latency.
#
# The held event, `relay`, whose value the fixture holds: the page lists no
# value for it until the holder states one; a choice with no holder, a
# hold of an event the core stores, a second hold and a statement from an
# instance that holds nothing are refused; the page's choice reaches the
# holder, answers what the holder answers and writes no user file; the
# page lists the stated value and the holder's problem line; refresh, and
# opening the Sounds section, each have the holder read once.
#
# After hyprland-consent, which answers the first-start notice that would
# keep the keyboard from the section. In the Sounds section it reads the
# fixture's rows under its name, which sorts before every shipped plugin
# with a sound, so its Ping row is the first whatever else is enabled; the
# keyboard on that row's picker with no ring; Down choosing the next sound,
# which is saved and played while the picker keeps the keyboard; a click on
# that row's Test playing it again; no Test for the off event and none for
# the plugin's own sound, whose picker offers Off and that sound alone;
# the held event's row with the stated value, the holder's line in the
# warning tone, and a picker that takes no choice while the value is
# unread.
#
# Control run on 2026-10-09, host cachy, through this row after
# hyprland-consent on a source_tree copy of the shell whose
# PluginLogic.soundRequest plays the chime for an event that is off: "an
# event that is off by default answers off" and "an event the user turned
# off answers off" failed, each reading ok, and "an off event starts no
# player" failed, reading one player more.
# Control run on 2026-10-09, host cachy, through this row on a source_tree
# copy of the shell whose run limit timer does nothing when it fires: "the
# run limit empties the playing list" failed, reading ["chime"], "the run
# limit stopped the player's process" failed, reading alive, and "the
# stopped run is logged as unplayed" failed, reading no line.
#
# No latency is budgeted: each reading polls through expect_poll every
# 0.2 s for up to the harness's poll bound. The row leaves the user file,
# the plugins directory and every enablement as it found them.
# inputs: shell/Core/Sounds.qml shell/Core/PluginLogic.js shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/Plugins.qml shell/Core/Registry.qml shell/assets/sounds/* shell/plugins/vgs.sounds/* shell/plugins/vgs.system/* scripts/smoke/fixtures/plugins/acme.sounds/* shell/Hosts/PaneHost.qml shell/Ui/controls/FormRow.qml shell/Ui/controls/Select.qml shell/Ui/controls/RowAction.qml shell/Ui/layout/Section.qml shell/Ui/layout/SectionHeader.qml scripts/smoke/Probe.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

sfx_file="$home/.config/vgshell/shell.json"
sfx_fixture="$home/.config/vgshell/plugins/acme.sounds"
cp -- "$sfx_file" "$sandbox/shell-before-sounds-row.json"
sfx_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
sfx_page_was="$(plugin_enabled vgs.sounds)" || fail "vgs.sounds's enabled state is unreadable"

sfx_read() { ipc smoke readInstance service acme.sounds "$1"; }
sfx_play() { ipc smoke invokeInstance service acme.sounds play "$1"; }
sfx_choose() { ipc smoke invokeInstance service acme.sounds choose "$1"; }
sfx_test() { ipc smoke invokeInstance service acme.sounds test "$1"; }
sfx_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get(sys.argv[1], [])))' "$1"; }
# Whether the fixture holds capability NAME: another row may leave a
# plugin with sound events of its own enabled.
sfx_holds() { ipc shell lent | py_reply 'import json,sys; print("acme.sounds" in json.load(sys.stdin)["holders"].get(sys.argv[1], []))' "$1"; }
sfx_playing() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["sounds"]["playing"]))'; }
# The user file's `sounds`, `null` for none.
sfx_saved() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("sounds"), sort_keys=True))' "$sfx_file"; }
# How many players the stand-in recorded, and the last one's sound: its
# options and the name of the file it was handed, `none` before the first.
sfx_calls() { device_calls pw-play | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
sfx_last() { device_calls pw-play | py_reply 'import json,os,sys; c=json.load(sys.stdin); print(json.dumps(c[-1][:-1] + [os.path.basename(c[-1][-1])]) if c else "none")'; }
# Whether the last player was handed a file the shell's tree ships.
sfx_last_shipped() { device_calls pw-play | py_reply 'import json,os,sys; c=json.load(sys.stdin); p=c[-1][-1] if c else ""; print(p.endswith("/shell/assets/sounds/" + os.path.basename(p)) and os.path.isfile(p))'; }
sfx_refresh() { ipc smoke invokeInstance service acme.sounds refresh ""; }
sfx_hold() { ipc smoke invokeInstance service acme.sounds hold "$1"; }
sfx_report() { ipc smoke invokeInstance service acme.sounds report "$1"; }
# The fixture's rows as the page lists them: event, value, testable,
# problem; sfx_event EVENT is one of them.
sfx_events() { sfx_read events | py_reply 'import json,sys; print(json.dumps([[r["event"], r["value"], r["testable"], r["problem"]] for r in json.load(sys.stdin) if r["id"] == "acme.sounds"]))'; }
sfx_event() { sfx_read events | py_reply 'import json,sys; print(json.dumps([[r["event"], r["value"], r["testable"], r["problem"]] for r in json.load(sys.stdin) if r["id"] == "acme.sounds" and r["event"] == sys.argv[1]][0]))' "$1"; }
# Whether the Ping row offers Off first, not playable, then the sounds the
# row plays, each playable, and every offer with a name to show.
sfx_offers() { sfx_read events | py_reply 'import json,sys; o=[r for r in json.load(sys.stdin) if r["id"] == "acme.sounds" and r["event"] == "ping"][0]["offers"]; print([o[0]["value"], o[0]["playable"]] == ["", False] and {"chime", "ping", "pop"} <= {x["value"] for x in o if x["playable"]} and all(isinstance(x["label"], str) and x["label"] for x in o))'; }
# One row of the Sounds section, by its label: PROPERTY as JSON, and what
# its picker offers, [[value, label], ...].
sfx_row() { ipc smoke readMatchingDescendant window vgs.sounds FormRow label "$1" "$2"; }
sfx_row_offers() { sfx_row "$1" modelData | py_reply 'import json,sys; print(json.dumps([[o["value"], o["label"]] for o in json.load(sys.stdin)["offers"]]))'; }
# A row's line under its value and the tone it is drawn in.
sfx_row_note() { printf '[%s,%s]\n' "$(sfx_row "$1" warning)" "$(sfx_row "$1" warningTone)"; }
# The section's picker that has no choice: whether it shows its
# placeholder and whether it takes a choice, or `absent` while every
# picker has one.
sfx_unread_picker() {
  local placeholder
  placeholder="$(ipc smoke readMatchingDescendant window vgs.sounds Select currentText "" showsPlaceholder)" || return
  if [[ $placeholder == absent ]]; then echo absent; else printf '[%s,%s]\n' "$placeholder" "$(ipc smoke readMatchingDescendant window vgs.sounds Select currentText "" enabled)"; fi
}
# The process the sleeping player recorded, which this row started:
# `alive`, `gone`, or `unread` before it recorded one.
sfx_hung="$sandbox/sounds-hung.pid"
sfx_hung_state() {
  [[ -s $sfx_hung ]] || { echo unread; return; }
  if kill -0 "$(cat "$sfx_hung")" 2>/dev/null; then echo alive; else echo gone; fi
}
sfx_focus() { ipc smoke activeFocusItem window vgs.sounds; }

# The capabilities, through the fixture.
mkdir -p "$sfx_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.sounds/." "$sfx_fixture/"
rescan "rescan discovers the sounds fixture"
expect_poll "the sounds fixture is known" True plugin_known acme.sounds
expect "enabling the sounds fixture is allowed" ok ipc shell setPluginEnabled acme.sounds true
expect_poll "the sounds fixture builds" True record_exists acme.sounds
expect_poll "the fixture reads back the exact sounds members it was given" '"choices,hold,play,report"' sfx_read soundsMembers
expect "the fixture reads back the exact soundSettings members it was given" '"choose,events,refresh,test"' sfx_read settingsMembers
expect "the fixture holds the sounds capability" True sfx_holds sounds
expect "only the fixture holds the soundSettings capability" '["acme.sounds"]' sfx_holders soundSettings
expect "the page lists the fixture's events with what each sounds, the held one with no value yet" '[["ping", "chime", true, ""], ["quiet", "", true, ""], ["tone", "own", false, ""], ["relay", null, false, ""]]' sfx_events
expect "the fixture reads its own choices, the held event not among them" '{"ping":"chime","quiet":"","tone":"own"}' sfx_read choices
expect "a played event offers Off, then the core's sounds, each with a name" True sfx_offers
sfx_before="$(sfx_calls)" || sfx_before=unread
expect "an event plays" ok sfx_play ping
expect_poll "the player is started once for the event" "$((sfx_before + 1))" sfx_calls
expect "the player is handed the event role and the manifest's default sound" '["--media-role", "Notification", "chime.wav"]' sfx_last
expect "the player is handed a file the shell ships" True sfx_last_shipped
expect_poll "the run ends and leaves no player" '[]' sfx_playing
expect "an event that is off by default answers off" off sfx_play quiet
expect "an event the plugin sounds itself is refused" "refused: sound=tone reason=own" sfx_play tone
expect "an undeclared event is refused" "refused: sound=gong reason=undeclared" sfx_play gong
expect "an off event starts no player" "$((sfx_before + 1))" sfx_calls
expect "three plays of one event in one turn start one player" '["ok","busy","busy"]' ipc smoke invokeBurst service acme.sounds play ping 3
expect_poll "the burst leaves no player" '[]' sfx_playing
expect "the burst started one player" "$((sfx_before + 2))" sfx_calls

# The run limit, over a player that does not exit.
expected_errors+=('sounds: unplayed sound=chime origin=acme\.sounds/ping exit=')
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$$" >%q\nexec sleep 600\n' "$sfx_hung" | sentinel_stand_over "$shim/pw-play"
expect "a play over a player that does not exit answers ok" ok sfx_play ping
expect_poll "the sleeping player runs" alive sfx_hung_state
expect "the sound shows as playing" '["chime"]' sfx_playing
expect "a second play of the event in a later turn answers busy" busy sfx_play ping
expect_poll "the run limit empties the playing list" '[]' sfx_playing
expect_poll "the run limit stopped the player's process" gone sfx_hung_state
expect_log "the stopped run is logged as unplayed" 1 'sounds: unplayed sound=chime origin=acme\.sounds/ping exit='
sentinel_restore "$shim/pw-play"
sfx_before="$(sfx_calls)" || sfx_before=unread
expect "the event plays again after the stopped run" ok sfx_play ping
expect_poll "the player is started for the play after the limit" "$((sfx_before + 1))" sfx_calls
expect_poll "the play after the limit leaves no player" '[]' sfx_playing

# The page's authority, through the fixture.
expect "a choice is written" ok sfx_choose '{"id":"acme.sounds","event":"ping","value":"pop"}'
expect "the user file holds the choice" '{"acme.sounds": {"ping": "pop"}}' sfx_saved
expect_poll "the fixture reads the choice back" '{"ping":"pop","quiet":"","tone":"own"}' sfx_read choices
expect "the event plays after the choice" ok sfx_play ping
expect_poll "the player is handed the chosen sound" '["--media-role", "Notification", "pop.wav"]' sfx_last
expect_poll "the chosen sound's run ends" '[]' sfx_playing
expect "off is written" ok sfx_choose '{"id":"acme.sounds","event":"ping","value":""}'
expect_poll "the fixture reads the event off" '{"ping":"","quiet":"","tone":"own"}' sfx_read choices
expect "an event the user turned off answers off" off sfx_play ping
expect "the plugin's own sound is turned off" ok sfx_choose '{"id":"acme.sounds","event":"tone","value":""}'
expect "the user file holds both choices" '{"acme.sounds": {"ping": "", "tone": ""}}' sfx_saved
expect "the plugin's own sound is turned on again" ok sfx_choose '{"id":"acme.sounds","event":"tone","value":"own"}'
expect "the manifest's default removes the choice" ok sfx_choose '{"id":"acme.sounds","event":"ping","value":"chime"}'
expect "the user file holds no sound choice" null sfx_saved
expect "a sound outside the core's set is refused" "refused: sound=ping reason=value" sfx_choose '{"id":"acme.sounds","event":"ping","value":"gong"}'
expect "a core sound for the plugin's own event is refused" "refused: sound=tone reason=value" sfx_choose '{"id":"acme.sounds","event":"tone","value":"pop"}'
expect "an unknown plugin is refused" "unknown: acme.gone" sfx_choose '{"id":"acme.gone","event":"ping","value":"pop"}'
expect "a refused choice leaves the user file as it was" null sfx_saved
sfx_before="$(sfx_calls)" || sfx_before=unread
expect "Test plays a sound of the set" ok sfx_test pop
expect_poll "Test starts the player" "$((sfx_before + 1))" sfx_calls
expect "Test hands the player that sound" '["--media-role", "Notification", "pop.wav"]' sfx_last
expect "Test refuses a sound outside the set" "refused: sound=gong reason=unknown" sfx_test gong
expect_poll "Test leaves no player" '[]' sfx_playing

# The held event, whose value the fixture holds.
sfx_relay_off='{"id":"acme.sounds","event":"relay","value":""}'
sfx_relay_on='{"id":"acme.sounds","event":"relay","value":"own"}'
expect "a choice for a held event no instance holds is refused" "refused: sound=relay reason=unheld" sfx_choose "$sfx_relay_off"
expect "a statement from an instance that holds nothing is refused" "refused: sound=relay reason=unheld" sfx_report '{"event":"relay","value":"own","problem":""}'
expect "an event the core stores takes no holder" "refused: sound=ping reason=stored" sfx_hold ping
expect "an undeclared event takes no holder" "refused: sound=gong reason=undeclared" sfx_hold gong
expect "the fixture holds its held event" ok sfx_hold relay
expect "a second hold of the event is refused" "refused: sound=relay reason=held" sfx_hold relay
expect "the holder states the value" ok sfx_report '{"event":"relay","value":"own","problem":""}'
expect_poll "the page lists the stated value" '["relay", "own", false, ""]' sfx_event relay
expect "a stated value the event does not take is refused" "refused: sound=relay reason=value" sfx_report '{"event":"relay","value":"pop","problem":""}'
expect "the page's choice for the held event answers the holder's ok" ok sfx_choose "$sfx_relay_off"
expect "the holder was handed the choice" '[""]' sfx_read relayAsked
expect "a held event's choice writes no user file" null sfx_saved
expect "the page lists the stated value until the holder states another" '["relay", "own", false, ""]' sfx_event relay
expect "the holder states off and why" ok sfx_report '{"event":"relay","value":"","problem":"The relay is stuck."}'
expect_poll "the page lists the value and the holder's line" '["relay", "", false, "The relay is stuck."]' sfx_event relay
expect "the holder answers its next choice with a refusal" ok ipc smoke invokeInstance service acme.sounds answer "refused: relay=stuck"
expect "the holder's refusal is the choice's answer" "refused: relay=stuck" sfx_choose "$sfx_relay_on"
expect "a core sound for the held event is refused" "refused: sound=relay reason=value" sfx_choose '{"id":"acme.sounds","event":"relay","value":"pop"}'
expect "a refused value never reaches the holder" '["","own"]' sfx_read relayAsked
sfx_reads="$(sfx_read relayReads)" || sfx_reads=unread
expect "refresh is allowed" ok sfx_refresh
expect "refresh has the holder read once" "$((sfx_reads + 1))" sfx_read relayReads

# The Sounds section.
expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling vgs.sounds is allowed" ok ipc shell setPluginEnabled vgs.sounds true
expect "the Sounds section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.sounds"}'
expect_poll "the Sounds section is mounted" '["vgs.sounds"]' window_panes
expect_poll "opening the section has the holder read once more" "$((sfx_reads + 2))" sfx_read relayReads
expect_poll "the section lists the fixture's events under its name, first" '"Acme sounds"' ipc smoke readDescendant window vgs.sounds SectionHeader text
expect_poll "the Ping row shows the manifest's default, after Off" 1 sfx_row Ping chosen
expect "the Quiet row shows Off" 0 sfx_row Quiet chosen
expect "the plugin's own sound offers Off and that sound alone" '[["", "Off"], ["own", "Acme tone"]]' sfx_row_offers Tone
expect "the held event's row shows the stated value, Off" 0 sfx_row Relay chosen
expect "the held event's row shows the holder's line in the warning tone" '["The relay is stuck.","warning"]' sfx_row_note Relay
expect "a row with no line shows its description, muted" '["Plays when the row pings.","muted"]' sfx_row_note Ping
expect "no picker is without a choice while every value is read" absent sfx_unread_picker
expect "the holder states that it cannot read the value" ok sfx_report '{"event":"relay","value":null,"problem":"The relay is gone."}'
expect_poll "the held event's row shows no choice" -1 sfx_row Relay chosen
expect "the held event's picker shows its placeholder and takes no choice while its value is unread" '[true,false]' sfx_unread_picker
expect "the holder states the value again" ok sfx_report '{"event":"relay","value":"own","problem":""}'
expect_poll "the held event's row shows the stated value, the plugin's own sound" 1 sfx_row Relay chosen
expect "every picker has a choice again" absent sfx_unread_picker
expect_poll "the keyboard starts on the first picker" '["Select",""]' sfx_focus
expect "a section the summon opens shows no focus ring" false ipc smoke readShownDescendant window vgs.sounds Select visualFocus
sfx_before="$(sfx_calls)" || sfx_before=unread
type_keys -k Down || fail "Down on the Ping picker failed"
expect_poll "Down chooses the next sound and saves it" '{"acme.sounds": {"ping": "ping"}}' sfx_saved
expect_poll "the Ping row shows the choice" 2 sfx_row Ping chosen
expect_poll "the choice plays once" "$((sfx_before + 1))" sfx_calls
expect "the choice hands the player the chosen sound" '["--media-role", "Notification", "ping.wav"]' sfx_last
expect "the picker keeps the keyboard after the choice" '["Select",""]' sfx_focus
expect_poll "the choice's run ends" '[]' sfx_playing
# The held event's picker, by the keyboard: Tab passes the Ping row's Test,
# the Quiet row's picker, whose Test takes no press, and the Tone row's
# picker; Up on the Relay row's picker chooses Off, which the page hands
# to the holder.
expect "the holder answers its next choice with ok" ok ipc smoke invokeInstance service acme.sounds answer ok
type_keys -k Tab -k Tab -k Tab -k Tab -k Up || fail "Tab to the Relay picker and Up failed"
expect_poll "Up on the held event's picker hands the holder Off" '["","own",""]' sfx_read relayAsked
expect "the page's choice for the held event writes no user file" '{"acme.sounds": {"ping": "ping"}}' sfx_saved
expect "the held event's row shows the stated value until the holder states another" 1 sfx_row Relay chosen
expect "the holder states the chosen value" ok sfx_report '{"event":"relay","value":"","problem":""}'
expect_poll "the held event's row shows the value the holder stated" 0 sfx_row Relay chosen
sfx_test_box="$(ipc smoke scopedWindowGeometry window vgs.sounds FormRow Ping RowAction Test)" || sfx_test_box=""
if read -r tx ty < <(at_centre "window:System Settings" "$sfx_test_box"); then
  hover "$tx" "$ty" || fail "hovering the Ping row's Test failed"
  click "$tx" "$ty" || fail "clicking the Ping row's Test failed"
  expect_poll "Test on the Ping row plays its sound again" "$((sfx_before + 2))" sfx_calls
  expect "Test hands the player the row's sound" '["--media-role", "Notification", "ping.wav"]' sfx_last
else
  fail "the Ping row's Test has no box: $sfx_test_box"
fi
expect "the off event offers no Test to press" absent ipc smoke scopedWindowGeometry window vgs.sounds FormRow Quiet RowAction Test
expect "the plugin's own sound offers no Test" absent ipc smoke scopedWindowGeometry window vgs.sounds FormRow Tone RowAction Test
expect_poll "the page's plays leave no player" '[]' sfx_playing

expect "the System window hides after the Sounds section" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after the Sounds section" 0 window_count 'System Settings'
expect "disabling the sounds fixture is allowed" ok ipc shell setPluginEnabled acme.sounds false
expect_poll "the sounds fixture is disabled" False plugin_enabled acme.sounds
rm -rf -- "${sfx_fixture:?}"
rescan "rescan removes the sounds fixture"
cp -- "$sandbox/shell-before-sounds-row.json" "$sfx_file.next" && mv -T -- "$sfx_file.next" "$sfx_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "vgs.system's enablement is as the row found it" "$sfx_system_was" plugin_enabled vgs.system
expect_poll "vgs.sounds's enablement is as the row found it" "$sfx_page_was" plugin_enabled vgs.sounds
expect_poll "the fixture holds the sounds capability no more" False sfx_holds sounds
