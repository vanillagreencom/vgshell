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
# members and that only the fixture holds them, the fixture's three events
# as the page lists them, and each answer of a play: an event plays its
# manifest default, one that is off by default answers `off` and starts no
# player, one the plugin sounds itself and an undeclared one are refused,
# and three plays of one event in one turn start one player. It writes a
# choice and reads it in the user file, in the fixture's own choices and in
# the next play; off silences the event; the manifest's default removes the
# choice from the file; a sound outside the core's set, an unknown plugin
# and a disabled one are refused and write nothing. Test plays a sound of
# the set and refuses another.
#
# After hyprland-consent, which answers the first-start notice that would
# keep the keyboard from the section. In the Sounds section it reads the
# fixture's rows under its name, the keyboard on the first picker with no
# ring, Down choosing the next sound, which is saved and played while the
# picker keeps the keyboard, a click on that row's Test playing it again,
# no Test for the off event and none for the plugin's own sound, whose
# picker offers Off and that sound alone.
#
# Control run on 2026-10-09, host cachy, through this row after
# hyprland-consent on a source_tree copy of the shell whose
# PluginLogic.soundRequest plays the chime for an event that is off: "an
# event that is off by default answers off" and "an event the user turned
# off answers off" failed, each reading ok, and "an off event starts no
# player" failed, reading one player more.
#
# No latency is budgeted: each reading polls through expect_poll every
# 0.2 s for up to the harness's poll bound. The row leaves the user file,
# the plugins directory and every enablement as it found them.
# inputs: shell/Core/Sounds.qml shell/Core/PluginLogic.js shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/Plugins.qml shell/assets/sounds/* shell/plugins/vgs.sounds/* shell/plugins/vgs.system/* scripts/smoke/fixtures/plugins/acme.sounds/* shell/Hosts/PaneHost.qml shell/Ui/controls/FormRow.qml shell/Ui/controls/Select.qml shell/Ui/controls/RowAction.qml shell/Ui/layout/SectionHeader.qml scripts/smoke/Probe.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

snd_file="$home/.config/vgshell/shell.json"
snd_fixture="$home/.config/vgshell/plugins/acme.sounds"
cp -- "$snd_file" "$sandbox/shell-before-sounds-row.json"
snd_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
snd_page_was="$(plugin_enabled vgs.sounds)" || fail "vgs.sounds's enabled state is unreadable"

snd_read() { ipc smoke readInstance service acme.sounds "$1"; }
snd_play() { ipc smoke invokeInstance service acme.sounds play "$1"; }
snd_choose() { ipc smoke invokeInstance service acme.sounds choose "$1"; }
snd_test() { ipc smoke invokeInstance service acme.sounds test "$1"; }
snd_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get(sys.argv[1], [])))' "$1"; }
snd_playing() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["sounds"]["playing"]))'; }
# The user file's `sounds`, `null` for none.
snd_saved() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("sounds"), sort_keys=True))' "$snd_file"; }
# How many players the stand-in recorded, and the last one's sound: its
# options and the name of the file it was handed, `none` before the first.
snd_calls() { device_calls pw-play | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
snd_last() { device_calls pw-play | py_reply 'import json,os,sys; c=json.load(sys.stdin); print(json.dumps(c[-1][:-1] + [os.path.basename(c[-1][-1])]) if c else "none")'; }
# Whether the last player was handed a file the shell's tree ships.
snd_last_shipped() { device_calls pw-play | py_reply 'import json,os,sys; c=json.load(sys.stdin); p=c[-1][-1] if c else ""; print(p.endswith("/shell/assets/sounds/" + os.path.basename(p)) and os.path.isfile(p))'; }
# The fixture's rows as the page lists them: event, own, value, fallback.
snd_events() { snd_read events | py_reply 'import json,sys; print(json.dumps([[r["event"], r["own"], r["value"], r["fallback"]] for r in json.load(sys.stdin) if r["id"] == "acme.sounds"]))'; }
# Whether the library the page reads holds the manifest defaults the row
# plays, each entry with a name to show.
snd_library() { snd_read library | py_reply 'import json,sys; rows=json.load(sys.stdin); print({"chime", "pop", "bloop-low"} <= {r["id"] for r in rows} and all(isinstance(r["label"], str) and r["label"] for r in rows))'; }
# One row of the Sounds section, by its label: PROPERTY as JSON.
snd_row() { ipc smoke readMatchingDescendant window vgs.sounds FormRow label "$1" "$2"; }
snd_focus() { ipc smoke activeFocusItem window vgs.sounds; }

# The capabilities, through the fixture.
mkdir -p "$snd_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.sounds/." "$snd_fixture/"
rescan "rescan discovers the sounds fixture"
expect_poll "the sounds fixture is known" True plugin_known acme.sounds
expect "enabling the sounds fixture is allowed" ok ipc shell setPluginEnabled acme.sounds true
expect_poll "the sounds fixture builds" True record_exists acme.sounds
expect_poll "the fixture reads back the exact sounds members it was given" '"choices,play"' snd_read soundsMembers
expect "the fixture reads back the exact soundSettings members it was given" '"choose,events,library,test"' snd_read settingsMembers
expect "only the fixture holds the sounds capability" '["acme.sounds"]' snd_holders sounds
expect "only the fixture holds the soundSettings capability" '["acme.sounds"]' snd_holders soundSettings
expect "the page lists the fixture's events with what each sounds" '[["ping", "", "chime", "chime"], ["quiet", "", "", ""], ["tone", "Acme tone", "own", "own"]]' snd_events
expect "the fixture reads its own choices" '{"ping":"chime","quiet":"","tone":"own"}' snd_read choices
expect "the core offers its sounds to the page, each with a name" True snd_library
snd_before="$(snd_calls)" || snd_before=unread
expect "an event plays" ok snd_play ping
expect_poll "the player is started once for the event" "$((snd_before + 1))" snd_calls
expect "the player is handed the event role and the manifest's default sound" '["--media-role", "Notification", "chime.wav"]' snd_last
expect "the player is handed a file the shell ships" True snd_last_shipped
expect_poll "the run ends and leaves no player" '[]' snd_playing
expect "an event that is off by default answers off" off snd_play quiet
expect "an event the plugin sounds itself is refused" "refused: sound=tone reason=own" snd_play tone
expect "an undeclared event is refused" "refused: sound=gong reason=undeclared" snd_play gong
expect "an off event starts no player" "$((snd_before + 1))" snd_calls
expect "three plays of one event in one turn start one player" '["ok","busy","busy"]' ipc smoke invokeBurst service acme.sounds play ping 3
expect_poll "the burst leaves no player" '[]' snd_playing
expect "the burst started one player" "$((snd_before + 2))" snd_calls

# The page's authority, through the fixture.
expect "a choice is written" ok snd_choose '{"id":"acme.sounds","event":"ping","value":"pop"}'
expect "the user file holds the choice" '{"acme.sounds": {"ping": "pop"}}' snd_saved
expect_poll "the fixture reads the choice back" '{"ping":"pop","quiet":"","tone":"own"}' snd_read choices
expect "the event plays after the choice" ok snd_play ping
expect_poll "the player is handed the chosen sound" '["--media-role", "Notification", "pop.wav"]' snd_last
expect_poll "the chosen sound's run ends" '[]' snd_playing
expect "off is written" ok snd_choose '{"id":"acme.sounds","event":"ping","value":""}'
expect_poll "the fixture reads the event off" '{"ping":"","quiet":"","tone":"own"}' snd_read choices
expect "an event the user turned off answers off" off snd_play ping
expect "the plugin's own sound is turned off" ok snd_choose '{"id":"acme.sounds","event":"tone","value":""}'
expect "the user file holds both choices" '{"acme.sounds": {"ping": "", "tone": ""}}' snd_saved
expect "the plugin's own sound is turned on again" ok snd_choose '{"id":"acme.sounds","event":"tone","value":"own"}'
expect "the manifest's default removes the choice" ok snd_choose '{"id":"acme.sounds","event":"ping","value":"chime"}'
expect "the user file holds no sound choice" null snd_saved
expect "a sound outside the core's set is refused" "refused: sound=ping reason=value" snd_choose '{"id":"acme.sounds","event":"ping","value":"gong"}'
expect "a core sound for the plugin's own event is refused" "refused: sound=tone reason=value" snd_choose '{"id":"acme.sounds","event":"tone","value":"pop"}'
expect "an unknown plugin is refused" "unknown: acme.gone" snd_choose '{"id":"acme.gone","event":"ping","value":"pop"}'
expect "a refused choice leaves the user file as it was" null snd_saved
snd_before="$(snd_calls)" || snd_before=unread
expect "Test plays a sound of the set" ok snd_test bloop-low
expect_poll "Test starts the player" "$((snd_before + 1))" snd_calls
expect "Test hands the player that sound" '["--media-role", "Notification", "bloop-low.wav"]' snd_last
expect "Test refuses a sound outside the set" "refused: sound=gong reason=unknown" snd_test gong
expect_poll "Test leaves no player" '[]' snd_playing

# The Sounds section.
expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling vgs.sounds is allowed" ok ipc shell setPluginEnabled vgs.sounds true
expect "the Sounds section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.sounds"}'
expect_poll "the Sounds section is mounted" '["vgs.sounds"]' window_panes
expect_poll "the section lists the fixture's events under its name" 1 ipc smoke itemTextCount window vgs.sounds SectionHeader "Sound events"
expect_poll "the Ping row shows the manifest's default, after Off" 1 snd_row Ping chosen
expect "the Quiet row shows Off" 0 snd_row Quiet chosen
expect "the plugin's own sound offers Off and that sound alone" '[{"value":"","label":"Off"},{"value":"own","label":"Acme tone"}]' snd_row Tone offers
expect_poll "the keyboard starts on the first picker" '["Select",""]' snd_focus
expect "a section the summon opens shows no focus ring" false ipc smoke readShownDescendant window vgs.sounds Select visualFocus
snd_before="$(snd_calls)" || snd_before=unread
type_keys -k Down || fail "Down on the Ping picker failed"
expect_poll "Down chooses the next sound and saves it" '{"acme.sounds": {"ping": "ping"}}' snd_saved
expect_poll "the Ping row shows the choice" 2 snd_row Ping chosen
expect_poll "the choice plays once" "$((snd_before + 1))" snd_calls
expect "the choice hands the player the chosen sound" '["--media-role", "Notification", "ping.wav"]' snd_last
expect "the picker keeps the keyboard after the choice" '["Select",""]' snd_focus
expect_poll "the choice's run ends" '[]' snd_playing
snd_test_box="$(ipc smoke scopedWindowGeometry window vgs.sounds FormRow Ping RowAction Test)" || snd_test_box=""
if read -r tx ty < <(at_centre "window:System Settings" "$snd_test_box"); then
  hover "$tx" "$ty" || fail "hovering the Ping row's Test failed"
  click "$tx" "$ty" || fail "clicking the Ping row's Test failed"
  expect_poll "Test on the Ping row plays its sound again" "$((snd_before + 2))" snd_calls
  expect "Test hands the player the row's sound" '["--media-role", "Notification", "ping.wav"]' snd_last
else
  fail "the Ping row's Test has no box: $snd_test_box"
fi
expect "the off event offers no Test to press" absent ipc smoke scopedWindowGeometry window vgs.sounds FormRow Quiet RowAction Test
expect "the plugin's own sound offers no Test" absent ipc smoke scopedWindowGeometry window vgs.sounds FormRow Tone RowAction Test
expect_poll "the page's plays leave no player" '[]' snd_playing

expect "the System window hides after the Sounds section" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after the Sounds section" 0 window_count 'System Settings'
expect "disabling the sounds fixture is allowed" ok ipc shell setPluginEnabled acme.sounds false
expect_poll "the sounds fixture is disabled" False plugin_enabled acme.sounds
rm -rf -- "${snd_fixture:?}"
rescan "rescan removes the sounds fixture"
cp -- "$sandbox/shell-before-sounds-row.json" "$snd_file.next" && mv -T -- "$snd_file.next" "$snd_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "vgs.system's enablement is as the row found it" "$snd_system_was" plugin_enabled vgs.system
expect_poll "vgs.sounds's enablement is as the row found it" "$snd_page_was" plugin_enabled vgs.sounds
expect_poll "no plugin holds the sounds capability after the row" '[]' snd_holders sounds
