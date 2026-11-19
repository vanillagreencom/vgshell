# Synthetic manager/status proof for the real core and Glass pane. This
# proves the core transaction and generated calls, never native plugin
# loading, recursive reload lifetime or rendered glass. A refused reload
# or a clean reload without the VGS loader must keep Clear opaque even
# with eligible shaders. A disposable shell restores the broken gates.
# Polls use expect_poll's 200 ms interval; the manager fixture's 120 s
# hang guard polls its release file every 50 ms. No latency is measured.
# inputs: shell/plugins/vgs.glass/* shell/plugins/vgs.system/* shell/Core/Capabilities.qml shell/Core/HyprlandState.* shell/Core/HyprlandLayer.* shell/Core/HyprctlReader.qml shell/Core/TuiRunner.qml shell/Core/TuiRecords.qml shell/Core/Notices.qml shell/Commons/ThemeLogic.js shell/Commons/Theme.qml scripts/smoke/fixtures/plugins/acme.appearance/* scripts/smoke/fixtures/tui/vgs.glass/tui/layer-glass.sh scripts/smoke/rows/hyprland-consent.sh shell/plugins/vgs.launcher/manifest.json bin/vgshell bin/vgshell-hypr-judge
set -euo pipefail

lg_read() { ipc smoke readInstance service acme.appearance "$1"; }
lg_choose() { ipc smoke invokeInstance service acme.appearance chooseLayerGlass "$1"; }
lg_state() { lg_read layerGlass | py_reply 'import json,sys; x=json.load(sys.stdin); print(x["observed"]["kind"]+"|"+x["operation"]["phase"]+"|"+str(x["requested"]).lower())'; }
lg_setup_disabled() { lg_read layerGlass | py_reply 'import json,sys; print(bool(json.load(sys.stdin)["disabledReason"]))'; }
lg_fresh_observation() { lg_read layerGlass | py_reply 'import json,sys; state=json.load(sys.stdin)["observed"]; print("stale" if state["stale"] else state["kind"])'; }
lg_saved() { python3 -c 'import json,sys; print(json.dumps((json.load(open(sys.argv[1])).get("appearance") or {}).get("layerGlass")))' "$home/.config/vgshell/shell.json"; }
lg_block() { if grep -q 'hl.plugin.hyprglass' "$home/.local/state/vgshell/hypr/vgs.lua"; then echo present; else echo absent; fi; }
lg_refresh() { ipc smoke invokeInstance service acme.appearance refreshLayerGlass ""; }
lg_order() { py_reply 'import sys
rows=sys.stdin.read().splitlines()
cursor=-1
try:
    for step in ["prepare", "declare", "config", "layer", "enable"]:
        cursor=rows.index(step, cursor+1)
    print(True)
except ValueError:
    print(False)' <"$lg_dir/calls"; }
lg_reason() { lg_read layerGlass | py_reply 'import json,sys; print(json.load(sys.stdin)["observed"]["reason"])'; }
lg_cause_retained() { lg_read layerGlass | py_reply 'import json,sys; print(bool(sys.argv[1]) and sys.argv[1] in json.load(sys.stdin)["operation"]["reason"])' "$lg_failure"; }
lg_assert_setup_blocked() {
  expect_poll 'the operation lends the pane its disabled reason' True lg_setup_disabled
  expect 'On cannot wait for an excluded draw' 'refused: layer-glass=glass-off' lg_choose true
}
lg_assert_clear_solid() {
  expect "$1: eligibility cannot authorize Clear" false ipc smoke themeValue layerGlassReady
}
lg_confirm_eligible() {
  expect 'plugin status is read again' ok lg_refresh
  expect_poll 'the plugin still reports eligible on a fresh read' eligible lg_fresh_observation
}
lg_unwire() { "${shell_env[@]}" "$repo/bin/vgshell" hypr unwire; }
lg_shadow_warning() {
  python3 -c 'import re,sys; print(r"WARN qml: plugins: hidden by a higher-precedence plugin with the same id: vgs\.glass at " + re.escape(sys.argv[1]) + "$")' "$1/shell/plugins/vgs.glass"
}
lg_unsource() {
  expect 'unwire removes the sandbox loader' "ok hypr=unwired path=$home/.config/hypr/hyprland.lua" lg_unwire
  expect 'the generated declaration stays on disk' present lg_block
  expect 'a clean external reload no longer sources the generated layer' ok hypr reload config-only
  expect 'the active Lua state has no material receipt' 'vgs-layer-glass=absent' hypr repl 'hl.__vgs_layer_glass or "vgs-layer-glass=absent"'
  lg_confirm_eligible
}
lg_source() {
  # Keep the fake plugin loader before the VGS include. The CLI's wire
  # would put the include first and allow a native plugin-load request.
  hypr_lua_restore layer-glass-wired || fail 'the synthetic loader and include are restored in order'
  expect 'a clean external reload sources the restored layer' ok hypr reload config-only
  expect_poll 'the sourced Clear rules and shaders are ready' true ipc smoke themeValue layerGlassReady
}
lg_dir="$home/.local/state/vgshell/layer-glass-fixture"
lg_copy="$home/.config/vgshell/plugins/vgs.glass"
lg_fixture="$home/.config/vgshell/plugins/acme.appearance"
lg_user="$home/.config/vgshell/shell.json"
lg_managed="/var/cache/hyprpm/$(id -un)/HyprGlass/hyprglass.so"
lg_setting() {
  python3 - "$lg_user" "$1" "$2" <<'LGSETTING' || return
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())
appearance = config.setdefault("appearance", {})
value = json.loads(sys.argv[3])
if value is None:
    appearance.pop(sys.argv[2], None)
else:
    appearance[sys.argv[2]] = value
pending = path.with_suffix(".json.next")
pending.write_text(json.dumps(config) + "\n")
pending.replace(path)
LGSETTING
  ipc shell reloadConfig
}
cp -- "$lg_user" "$sandbox/layer-glass-before.json"
hypr_lua_save layer-glass
# Hyprland 0.57.1 reinitializes Lua on reload, and hl.plugin is an ordinary
# table (ConfigManager.cpp registerPluginLuaFunctionInState). A fixture
# namespace and declaration-only loader prevent any real binary load.
# Until the unwire case, the core's exact loading line stays present; its
# wiring judge observes line presence. The namespace is a stand-in, not something the
# declaration creates. The fixture event and status shim own synthetic
# compositor facts; they do not model native loading or recursive reloads.
{
  cat <<EOF
do
    local state = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$lg_dir")
    local managed = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$lg_managed")
    local function write(name, text)
        local file = assert(io.open(state .. "/" .. name, "w"))
        file:write(text .. "\\n")
        file:close()
    end
    local function record(step)
        local file = assert(io.open(state .. "/calls", "a"))
        file:write(step .. "\\n")
        file:close()
    end
    local module = { config = function(_) record("config") end, layer = function(_, _) record("layer") end, preset = function(_, _) record("preset") end }
    local declared = false
    hl.plugin.hyprglass = module
    hl.plugin.load = function(path)
        assert(path == managed, "unexpected synthetic plugin path")
        record("declare")
        declared = true
    end
    hl.on("config.reloaded", function()
        local withheld = io.open(state .. "/withhold-load", "r")
        if withheld then withheld:close(); return end
        if declared then write("loaded", "true") end
    end)
end
EOF
  cat -- "$home/.config/hypr/hyprland.lua"
} >"$home/.config/hypr/hyprland.lua.next"
mv -- "$home/.config/hypr/hyprland.lua.next" "$home/.config/hypr/hyprland.lua"
hypr_lua_save layer-glass-wired
expect 'the nested compositor loads the synthetic Lua namespace' ok hypr reload config-only
lg_glass_was="$(plugin_enabled vgs.glass | tr '[:upper:]' '[:lower:]')"
lg_system_was="$(plugin_enabled vgs.system | tr '[:upper:]' '[:lower:]')"
mkdir -p "$lg_dir/saved-tools" "$lg_copy" "$lg_fixture"
for tool in hyprpm cpio cmake pkg-config g++ gcc; do
  [[ ! -e $shim/$tool ]] || mv -- "$shim/$tool" "$lg_dir/saved-tools/$tool"
  printf '#!/bin/sh\nexit 0\n' >"$shim/$tool"; chmod 755 "$shim/$tool"
done
# The private Glass copy replaces its manager script below and deliberately
# shadows the shipped plugin. Declare only that shipped path's collision.
lg_shadow="$(lg_shadow_warning "$repo")"
expected_errors+=("$lg_shadow")
cp -R -- "$repo/shell/plugins/vgs.glass/." "$lg_copy/"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.glass/tui/layer-glass.sh" "$lg_copy/tui/layer-glass.sh"
cp -- "$lg_copy/tui/layer-glass.sh" "$lg_dir/manager.sh"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.appearance/." "$lg_fixture/"
printf 'false\n' >"$lg_dir/loaded"
printf '[""]\n' >"$lg_dir/errors"
printf 'pending\n' >"$lg_dir/shaders"
cat >"$shim/hyprctl.layer-glass" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state=$(printf '%q' "$lg_dir")
case "\$*" in
  '-j plugin list')
    if [[ \$(<"\$state/loaded") == true ]]; then printf '%s\n' '[{"name":"hyprglass","author":"hyprnux","handle":"synthetic","version":"1.1.1","description":"Synthetic state fixture"}]'; else echo '[]'; fi ;;
  '-j hyprglass status')
    windows=false
    [[ ! -f \$state/unsafe ]] || windows=true
    printf '{"schema":1,"version":"1.1.1","versionCheck":"match","active":true,"shaders":"%s","features":{"windows":{"enabled":%s,"active":false,"reason":"disabled"},"layers":{"enabled":true,"active":true,"reason":null}}}\n' "\$(<"\$state/shaders")" "\$windows" ;;
  '-j configerrors') cat "\$state/errors" ;;
  'reload config-only')
    if [[ -f \$state/refuse-reload ]]; then echo 'synthetic layer-glass refusal'; exit 1; fi
    exec $(printf '%q' "$shim/hyprctl.real") "\$@" ;;
  *) exec $(printf '%q' "$shim/hyprctl.real") "\$@" ;;
esac
EOF
chmod 755 "$shim/hyprctl.layer-glass"
shim_hyprctl layer-glass
terminal_stand_in
rescan 'the synthetic layer-glass fixtures are discovered'
expect 'the layer-glass capability fixture enables' ok ipc shell setPluginEnabled acme.appearance true
expect_poll 'the layer-glass capability fixture builds' True record_exists acme.appearance
expect 'the Glass pane enables for layer glass' ok ipc shell setPluginEnabled vgs.glass true
expect 'System enables for layer glass' ok ipc shell setPluginEnabled vgs.system true
expect 'the synthetic absence is read' ok lg_refresh
expect_poll 'synthetic absence starts off by default' 'not-loaded|idle|false' lg_state
expect 'unset layer glass contributes no plugin declaration' absent lg_block
expect 'the main Glass switch is turned off' ok lg_setting glassEnabled false
lg_assert_setup_blocked
expect 'Rebuild cannot wait for an excluded draw' 'refused: layer-glass=glass-off' ipc smoke invokeInstance service acme.appearance rebuildLayerGlass ""
expect 'Off remains available with the main switch off' ok lg_choose false
expect_poll 'Off leaves the plugin unloaded and the operation idle' 'not-loaded|idle|false' lg_state
expect 'the main Glass switch is restored' ok lg_setting glassEnabled null
expect_poll 'the layer-glass prerequisite is satisfied' False lg_setup_disabled
expect 'the actual Glass pane opens for layer glass' ok ipc shell summon window vgs.system '{"pane":"vgs.glass"}'
expect_poll 'the Glass pane mounts for layer glass' '["vgs.glass"]' window_panes
: >"$lg_dir/hold"
lg_shown="$(ipc smoke revealScopedText window vgs.system FormRow 'Layer glass' Switch '')"
if [[ $lg_shown =~ ^[0-9.]+$ ]]; then
  click_item 'scoped:System Settings' window vgs.glass FormRow 'Layer glass' Switch ''
else
  fail "the layer glass row could not be revealed: $lg_shown"
fi
expect_poll 'the pane press starts the core-owned manager' 'not-loaded|manager|false' lg_state
expect 'the pane closes while its manager is held' ok ipc shell hide window vgs.system
rm -- "$lg_dir/hold"
expect_poll 'first On waits for a matching layer draw without unloading' 'shaders-pending|verifying|false' lg_state
expect 'the core transaction declares and configures before its enable stage' True lg_order
expect 'pending shaders leave the On preference unsaved' null lg_saved
expect 'pending shaders retain the applied layer configuration' present lg_block
printf '10\n' >"$lg_dir/exit"
expect 'Off supersedes a pending first draw' ok lg_choose false
expect_poll 'canceled pending Off reports the still-loaded plugin' 'residual|idle|false' lg_state
expect 'canceled pending Off retains its safe layer configuration' present lg_block
rm -- "$lg_dir/exit"
expect 'Off retries the canceled pending unload' ok lg_choose false
expect_poll 'pending Off verifies the unloaded plugin' 'not-loaded|idle|false' lg_state
expect 'pending Off removes its applied configuration' absent lg_block
expect 'On can wait for shaders with Glass enabled' ok lg_choose true
expect_poll 'there is a pending verification to cancel' 'shaders-pending|verifying|false' lg_state
expect 'the main switch turns off during verification' ok lg_setting glassEnabled false
expect_poll 'turning Glass off cancels the verification and cleans up its first load' 'not-loaded|idle|false' lg_state
expect 'cancellation does not save On' null lg_saved
expect 'Glass is restored for the next On' ok lg_setting glassEnabled null
expect_poll 'On can start again' False lg_setup_disabled
expect 'Clear is selected for the launcher warm-up' ok lg_setting glassStyle '"clear"'
expect_poll 'the launcher will map under a whitelisted namespace' '"clear"' ipc smoke themeValue glassStyle
expect 'On starts again from the unloaded state' ok lg_choose true
expect_poll 'On waits for its first layer draw' 'shaders-pending|verifying|false' lg_state
printf 'ready\n' >"$lg_dir/shaders"
expect 'ready shaders are not read before a layer maps' 'shaders-pending|verifying|false' lg_state
# A layer that maps and unmaps while shaders read pending has layer glass
# read again once it has drawn, with no Check again.
expect 'the launcher enables to map a layer' ok ipc shell setPluginEnabled vgs.launcher true
expect_poll "the launcher's service is built for the layer" True record_exists vgs.launcher
expect 'a launcher layer maps while shaders read pending' ok ipc shell summon overlay vgs.launcher '{}'
expect_poll 'a mapped layer completes On after shaders are ready' 'eligible|idle|true' lg_state
expect 'the launcher layer unmaps' ok ipc shell hide overlay vgs.launcher
expect 'the launcher disables after the layer' ok ipc shell setPluginEnabled vgs.launcher false
expect 'On preference is saved after verification' true lg_saved
expect 'the one writer contributes its plugin declaration' present lg_block
lg_refusal='hyprland: reload=failed status=1 reply="synthetic layer-glass refusal"'
expected_errors+=("$lg_refusal")
lg_refuse_clear() {
  expect 'explicit Dark config reaches the writer' ok lg_setting glassStyle '"dark"'
  expect_poll 'the previous style is Dark' '"dark"' ipc smoke themeValue glassStyle
  expect_poll 'Dark rules are acknowledged and the plugin is eligible' true ipc smoke themeValue layerGlassReady
  : >"$lg_dir/refuse-reload"
  expect 'Clear is requested while its reload is refused' ok lg_setting glassStyle '"clear"'
  expect_poll 'the new style is Clear' '"clear"' ipc smoke themeValue glassStyle
  expect_log 'the Clear reload was refused' 1 "$lg_refusal"
  lg_confirm_eligible
}
lg_retry_clear() {
  rm -- "$lg_dir/refuse-reload"
  expect 'the current generated layer is retried' ok ipc shell renderHyprland
  expect_poll 'Clear becomes ready after the matching reload' true ipc smoke themeValue layerGlassReady
}
lg_refuse_clear
lg_assert_clear_solid 'refused reload'
lg_retry_clear
lg_unsource
lg_assert_clear_solid 'clean unwired reload'
lg_source
expect 'the explicit style is removed' ok lg_setting glassStyle null
# A queued shell reload may still replay the declaration after the
# preference is saved. Withhold the synthetic load until the test asks
# the compositor to replay it.
: >"$lg_dir/withhold-load"
printf 'false\n' >"$lg_dir/loaded"
expect 'the synthetic unload is read' ok lg_refresh
expect_poll 'an unloaded plugin retains requested On' 'not-loaded|idle|true' lg_state
rm -- "$lg_dir/withhold-load"
expect 'external reload advances the synthetic declaration event' ok hypr reload config-only
expect_poll 'the synthetic loaded fact is read fresh' 'eligible|idle|true' lg_state
expect 'Off starts whole-plugin cleanup' ok lg_choose false
expect_poll 'Off verifies unloaded state before committing' 'not-loaded|idle|false' lg_state
expect 'Off removes its saved On preference' null lg_saved
expect 'Off removes every VGS hyprglass declaration' absent lg_block
: >"$lg_dir/unsafe"
: >"$lg_dir/disable-hold"
printf '10\n' >"$lg_dir/disable-exit"
expect 'On with failed layer-only verification starts' ok lg_choose true
expect_poll 'failed verification starts compensating unload' 'layers-disabled|manager|false' lg_state
lg_failure="$(lg_reason)"
rm -- "$lg_dir/disable-hold"
expect_poll 'declined compensating unload reports the residual plugin' 'residual|idle|false' lg_state
expect 'declined compensation retains the original verification cause' True lg_cause_retained
expect 'declined compensation retains the safe generated block' present lg_block
rm -- "$lg_dir/unsafe" "$lg_dir/disable-exit"
expect 'Off cleans the declined compensation' ok lg_choose false
expect_poll 'compensation cleanup verifies unloaded state' 'not-loaded|idle|false' lg_state
expect 'compensation cleanup removes the generated block' absent lg_block

# These mutations affect separate gates. The same predicates used above
# must fail at the named assertions, not because a fixture failed to load.
copy_tree layer-glass-regressions
edit_tree layer-glass-regressions shell/Core/HyprlandState.qml \
  'readonly property string layerGlassSetupDisabledReason: State.layerGlassSetupDisabledReason(Theme.appearanceState.values.glassEnabled)' \
  'readonly property string layerGlassSetupDisabledReason: ""'
edit_tree layer-glass-regressions shell/Core/HyprlandState.qml \
  'value: root.layerGlassIntent && root.layerGlassApplication !== null
            && root.layerGlassApplication === root.layerGlassReadApplication
            && root.layerGlassApplication.style === Theme.glassStyle
            && root.layerGlassSetupDisabledReason === ""
            && !root.layerGlass.observed.stale && root.layerGlass.observed.kind === "eligible"' \
  'value: root.layerGlassIntent && !root.layerGlass.observed.stale && root.layerGlass.observed.kind === "eligible"'
stop_shell
lg_shadow="$(lg_shadow_warning "$sandbox/tree-layer-glass-regressions")"
expected_errors+=("$lg_shadow")
start_shell "$sandbox/tree-layer-glass-regressions" "$smoke_log_dir/layer-glass-regressions-shell.log"
expect_poll 'the mutant can reach the same capability fixture' True record_exists acme.appearance
expect 'the main Glass switch is off in the setup control' ok lg_setting glassEnabled false
expect_poll 'the setup control observes Glass off' false ipc smoke themeValue appearanceState.values.glassEnabled
printf 'pending\n' >"$lg_dir/shaders"
lg_control_log="$smoke_log_dir/layer-glass-regressions.log"
(
  failures=0; behaviour_failures=0
  lg_assert_setup_blocked
) >"$lg_control_log"
expect 'control: the disabled-reason assertion fails' 1 grep -c '^  FAIL  the operation lends the pane its disabled reason: got False ' "$lg_control_log"
expect 'control: On is wrongly accepted with Glass off' 1 grep -c '^  FAIL  On cannot wait for an excluded draw: got ok$' "$lg_control_log"
expect_poll 'the admitted setup really waits for an excluded draw' 'shaders-pending|verifying|false' lg_state
expect 'Off cancels the setup control' ok lg_choose false
expect_poll 'the setup control leaves the plugin unloaded' 'not-loaded|idle|false' lg_state
expect 'the main Glass switch returns for the Clear control' ok lg_setting glassEnabled null
printf 'ready\n' >"$lg_dir/shaders"
expect 'the Clear control starts with saved layer glass' ok lg_setting layerGlass true
expect_poll 'the Clear control starts from a loaded plugin' 'eligible|idle|true' lg_state
lg_refuse_clear
(
  failures=0; behaviour_failures=0
  lg_assert_clear_solid 'refused reload'
) >>"$lg_control_log"
expect 'control: the refused-reload assertion detects the regression' 1 grep -c '^  FAIL  refused reload: eligibility cannot authorize Clear: got true$' "$lg_control_log"
lg_retry_clear
lg_unsource
(
  failures=0; behaviour_failures=0
  lg_assert_clear_solid 'clean unwired reload'
) >>"$lg_control_log"
expect 'control: the clean-reload assertion detects the regression' 1 grep -c '^  FAIL  clean unwired reload: eligibility cannot authorize Clear: got true$' "$lg_control_log"
control_output "$lg_control_log"
lg_source
stop_shell
start_shell "$repo" "$smoke_log_dir/layer-glass-restored-shell.log"
expect_poll 'the real shell has its layer-glass fixture again' True record_exists acme.appearance
expect 'the real shell turns off the Clear control plugin' ok lg_choose false
expect_poll 'the Clear control leaves the plugin unloaded' 'not-loaded|idle|false' lg_state

expect 'the layer-glass fixture disables' ok ipc shell setPluginEnabled acme.appearance false
expect 'the Glass fixture disables before removal' ok ipc shell setPluginEnabled vgs.glass false
expect_poll 'the appearance fixture is destroyed' False record_exists acme.appearance
rm -r -- "${lg_copy:?}" "${lg_fixture:?}"
shim_hyprctl real
rm -- "${shim:?}/hyprctl.layer-glass"
for tool in hyprpm cpio cmake pkg-config g++ gcc; do
  rm -- "$shim/$tool"
  [[ ! -e $lg_dir/saved-tools/$tool ]] || mv -- "$lg_dir/saved-tools/$tool" "$shim/$tool"
done
cp -- "$sandbox/layer-glass-before.json" "$lg_user.next"
mv -- "$lg_user.next" "$lg_user"
expect 'the user appearance is restored after layer glass' ok ipc shell reloadConfig
rescan 'the shipped Glass plugin returns after layer glass'
expect 'Glass enablement is restored after layer glass' ok ipc shell setPluginEnabled vgs.glass "$lg_glass_was"
expect 'System enablement is restored after layer glass' ok ipc shell setPluginEnabled vgs.system "$lg_system_was"
hypr_lua_restore layer-glass || fail 'hyprland.lua is restored after the synthetic namespace'
expect 'the nested compositor reloads without the synthetic namespace' ok hypr reload config-only
rm -r -- "${lg_dir:?}"
