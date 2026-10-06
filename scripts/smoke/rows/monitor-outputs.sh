# The outputs a plugin reads through the `monitors` capability: Hyprland's
# own list, read by the core while a plugin holds the capability and read
# again after each `configreloaded`, compared with what the nested Hyprland
# answers hyprctl. The capability hands a plugin `outputs`, the panel
# `support` `hyprctl systeminfo` prints, the `wantSupport` hold, and to the
# owner of `hyprland.monitors` alone the trial calls. The core reads no
# support until the fixture holds it; held, it reads the nested WAYLAND-1,
# which has no EDID, so its support reads all false and offers sRGB alone,
# reads a headless output that comes, and drops it when it goes. Released,
# it reads none for an output that comes. The row reads the Hyprland layer before any saved display rule and
# finds no `hl.monitor` call (docs/architecture/hyprland.md). The row runs on the first nested
# output alone, WAYLAND-1, which takes any mode and lists none.
#
# The change the fixture must follow is the harness's own: hold_mode gives
# the output double its sized mode at scale 2, as rows/hidpi.sh holds it,
# through `hyprctl eval`. The configuration reload after it runs the hold
# file, so the held mode stands, and posts `configreloaded`, the event the
# core reads the outputs again on. The readings under the
# hold count as a mode reset when the host moved the output off it
# (docs/architecture/validation.md § Faults). At the end the row gives the output its own
# mode at scale 1 again, puts shell.json back and disables the fixture.
#
# No latency is budgeted: each reading polls through expect_poll every
# 0.2 s for up to 5 s.
#
# Control run on 2026-10-02, host cachy, through this row alone after the
# bar and consent rows, on a source copy of the tree whose MonitorState.qml
# reads the outputs on no `configreloaded`: "the fixture's outputs follow
# the reload to the held mode and scale" failed.
# inputs: scripts/smoke/fixtures/plugins/acme.monitors/* shell/Core/MonitorState.qml shell/Core/MonitorLogic.js shell/Core/HyprlandLayer.js shell/Core/HyprctlReader.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
user_config="$home/.config/vgshell/shell.json"
fixture_dir="$home/.config/vgshell/plugins/acme.monitors"
mkdir -p "$fixture_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.monitors/." "$fixture_dir/"
cp -- "$user_config" "$sandbox/shell-before-monitors.json"

read_monitors() { ipc smoke readInstance service acme.monitors "$1"; }
reads_active() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["monitors"]["active"]))'; }
# How many lines of the Hyprland layer hold an `hl.monitor` call, or
# `layer=unread` for a layer that is not there to read.
layer_monitor_calls() {
  [[ -r $hypr_layer ]] || { echo layer=unread; return; }
  grep -c -E -- 'hl\.monitor[[:space:]]*\(' "$hypr_layer" || true
}
# The output NAME as the fixture's `outputs` holds it, `WxH scale=S`.
output_read() { read_monitors outputs | py_reply 'import json,sys; m=[o for o in json.load(sys.stdin) if o["name"]==sys.argv[1]]; print("%dx%d scale=%g" % (m[0]["width"], m[0]["height"], m[0]["scale"])) if len(m)==1 else print("outputs=%d" % len(m))' "$1"; }
# The names Hyprland lists, and the names and identifiers the fixture's
# `outputs` hold, each as a JSON list in Hyprland's order.
listed_names() { hypr -j monitors all | py_reply 'import json,sys; print(json.dumps([o["name"] for o in json.load(sys.stdin)]))'; }
read_names() { read_monitors outputs | py_reply 'import json,sys; print(json.dumps([o["name"] for o in json.load(sys.stdin)]))'; }
# The fixture's `support` entry for output NAME, its flags and modes,
# `absent` for none and `unread` while the core holds no support.
support_read() { read_monitors support | py_reply 'import json,sys; s=json.load(sys.stdin); e=None if s is None else s.get(sys.argv[1]); print("unread" if s is None else "absent" if e is None else "hdr=%s chroma=%s bt2020=%s modes=%s" % (e["hdr"], e["chroma"], e["bt2020"], ",".join(e["colourModes"])))' "$1"; }
output_listed() { read_monitors outputs | py_reply 'import json,sys; print("yes" if any(o["name"] == sys.argv[1] for o in json.load(sys.stdin) or []) else "no")' "$1"; }
invoke_monitors() { ipc smoke invokeInstance service acme.monitors "$1" ""; }
support_output=SMOKE-SUPPORT
read_identifiers() { read_monitors outputs | py_reply 'import json,sys; print(json.dumps([o["identifier"] for o in json.load(sys.stdin)]))'; }

rescan "rescan discovers the monitors fixture"
expect_poll "the monitors fixture is known" True plugin_known acme.monitors
expect "enabling the monitors fixture is allowed" ok ipc shell setPluginEnabled acme.monitors true
expect_poll "the monitors fixture builds" True record_exists acme.monitors
expect_poll "the fixture reads back the exact monitors members it was given" '"keep,outputs,overridden,revert,support,trial,trialState,wantSupport"' read_monitors members
expect_poll "the core reads the outputs while a plugin holds monitors" true reads_active

if ! outputs_names="$(listed_names)" || ! outputs_first="$(first_name)" || ! outputs_base="$(unscaled_mode_of "$outputs_first")" || ! outputs_double="$(hidpi_mode_of "$outputs_first")"; then
  fail "the monitor outputs row reads no sized mode at scale 1 on the first monitor ${outputs_first:-unread}"
else
  expect_poll "the fixture's outputs name every output Hyprland lists, in its order" "$outputs_names" read_names
  # The nested outputs carry no serial, so each is named by its connector.
  expect "an output with no serial is identified by its connector" "$outputs_names" read_identifiers
  expect_poll "the fixture's outputs list $outputs_first at its own mode" "$outputs_base scale=1" output_read "$outputs_first"
  expect "the core reads no panel support while nothing holds it" unread support_read "$outputs_first"
  expect "the fixture holds the panel support" ok invoke_monitors wantSupport
  expect_poll "the fixture's support reads $outputs_first with no EDID" "hdr=False chroma=False bt2020=False modes=srgb" support_read "$outputs_first"

  hold_mode "the nested compositor holds $outputs_first at double its mode and scale 2" "$outputs_first" "$outputs_double" 2
  if [[ ${#mode_hold[@]} -gt 0 ]]; then
    expect "the nested instance reloads its configuration under the hold" ok hypr reload config-only
    expect_poll "the fixture's outputs follow the reload to the held mode and scale" "$outputs_double scale=2" output_read "$outputs_first"
  fi
  release_mode "the nested compositor gives $outputs_first its own mode at scale 1 again" "$outputs_first" "$outputs_base"
  expect "the nested instance reloads its configuration without the hold" ok hypr reload config-only
  expect_poll "the fixture's outputs follow the reload back to the output's own mode" "$outputs_base scale=1" output_read "$outputs_first"
fi
if [[ -n ${outputs_first:-} ]]; then
  expect "the nested compositor adds an output while the support is held" ok hypr output create headless "$support_output"
  expect_poll "the held support reads the output that came" "hdr=False chroma=False bt2020=False modes=srgb" support_read "$support_output"
  expect "the nested compositor removes that output" ok hypr output remove "$support_output"
  expect_poll "the support drops the output that went" absent support_read "$support_output"
  expect "the fixture releases the panel support" ok invoke_monitors releaseSupport
  expect "the nested compositor adds an output while nothing holds the support" ok hypr output create headless "$support_output"
  expect_poll "the fixture's outputs list the output that came" yes output_listed "$support_output"
  # A read the outputs change started would answer within the 22-36 ms one
  # systeminfo call took in this sandbox on 2026-10-06; the wait gives it 1 s.
  sleep 1
  expect "the released support reads no output that came" absent support_read "$support_output"
  expect "the nested compositor removes the unheld output" ok hypr output remove "$support_output"
fi
expect "the Hyprland layer starts with no saved monitor rule" 0 layer_monitor_calls

cp -- "$sandbox/shell-before-monitors.json" "$user_config.next" && mv -T -- "$user_config.next" "$user_config"
expect "disabling the monitors fixture is allowed" ok ipc shell setPluginEnabled acme.monitors false
expect_poll "the monitors fixture is disabled" False plugin_enabled acme.monitors
expect_poll "the core stops reading the outputs once no plugin holds monitors" false reads_active
