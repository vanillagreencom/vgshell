# Real launcher: twelve separate 50 ms o presses, cold then warm providers,
# on sixty harmless desktop fixtures and the shipped menu. The capture
# controller rejects preceding queued blank frames through glyph pixels.
# Values are capture-return upper bounds from the FIFO request, including
# helper dispatch and capture cost; no presentation timestamp is claimed.
# Ceiling 212 ms: twice ceil(105.572 ms), the highest of twelve normal
# readings in runtime-control-run-2, launcher-latency.py, cachy (Ryzen
# 9 9950X, 16 physical cores), 2026-11-06. Normal bounds 36.392–105.572 ms;
# direct repeated-solver control 252.103–436.682 ms on every press.
# Load1 3.96–4.69, load5 12.02–12.98; CPU pressure 0.20–1.29%.
# Engine 0.3.2.r7.g2b4501a-4, Hyprland 0.57.0-1.1, default
# dark Theme, 115 apps (60 fixtures), 132 menu items, 111 o-result rows.
# No capture sleep; normal capture median 16.568 ms, maximum 21.732 ms;
# largest glyph observation bracket 38.392 ms. These are final-glyph-like
# capture-return upper bounds, including FIFO/helper dispatch, not scanout.
# CPU/load exclusions use harness.sh's shared 2.8%/1.00-per-core limits;
# an unread or busy population cannot pass. All raw samples stay retained.
# Merged TextField remeasurement: launcher-latency.py, observer-merged-field-run-2
# on the same cachy/engine/compositor, 2026-11-06: twelve normal bounds
# 36.468–117.167 ms; direct-solver bounds 287.655–382.073 ms, all measured
# below 1.125% window CPU PSI, load1 <=8.98 and load5 <=7.83.
# Probe reports leftPadding=24; character rectangles give 8.984375 advance.
# The discriminator uses its first 8 pixel columns, not the adjacent caret.
# Normal capture median 16.540 ms, max 24.096 ms; bracket max 39.342 ms,
# with no capture sleep. The 212 ms ceiling and all old receipts stand.
# inputs: shell/plugins/vgs.launcher/Launcher.qml shell/plugins/vgs.launcher/manifest.json shell/plugins/vgs.launcher/menu.json shell/plugins/vgs.launcher/Service.qml shell/Commons/Theme.qml scripts/smoke/launcher-latency.py scripts/smoke/shot.sh scripts/smoke/keyboard/keyboard.c scripts/smoke/user-config.sh
set -euo pipefail

launcher_latency_budget_ms=212
launcher_latency_saved="$sandbox/launcher-latency-saved"
mkdir -p -- "$launcher_latency_saved/launcher"
stop_shell
for launcher_latency_file in shell.json theme.json launcher/menu.json; do
  if [[ -e $home/.config/vgshell/$launcher_latency_file ]]; then
    cp -p -- "$home/.config/vgshell/$launcher_latency_file" "$launcher_latency_saved/$launcher_latency_file"
  fi
done
# The private fixture selects default dark Theme and default Appearance.
# Keeping the rest of the harness seed preserves its owned registrations.
user_config_write python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text())
value.pop("appearance", None)
value["plugins"] = [p for p in value.get("plugins", []) if p["id"] != "vgs.launcher"]
print(json.dumps(value))
PY
rm -f -- "$home/.config/vgshell/theme.json" "$home/.config/vgshell/launcher/menu.json"
mkdir -p -- "$home/.local/share/applications"
for launcher_latency_index in {000..059}; do
  printf '[Desktop Entry]\nType=Application\nName=Latency o %s\nExec=/usr/bin/false\nIcon=application-x-executable\n' \
    "$launcher_latency_index" >"$home/.local/share/applications/vgs-latency-o-$launcher_latency_index.desktop"
done
expect "latency fixture sets nested repeat" ok hypr eval 'hl.config({input={repeat_delay=250,repeat_rate=40}})'
hypr -j getoption input:repeat_delay
hypr -j getoption input:repeat_rate

launcher_latency_measure() { # normal|slow
  local kind="$1" socket rect padding surface output
  local -a control=()
  [[ $kind != slow ]] || control=(--slow)
  copy_tree "launcher-latency-$kind" || return 1
  python3 "$repo/scripts/smoke/launcher-latency.py" prepare "$sandbox/tree-launcher-latency-$kind" "${control[@]}" || return 1
  start_shell "$sandbox/tree-launcher-latency-$kind" "$sandbox/launcher-latency-$kind.log" || return 1
  expect "latency $kind enables launcher" ok ipc shell setPluginEnabled vgs.launcher true
  expect_poll "latency $kind service exists" True record_exists vgs.launcher
  expect "latency $kind summons launcher" ok ipc shell summon overlay vgs.launcher '{}'
  expect_poll "latency $kind holds keyboard focus" true ipc smoke activeFocusIn overlay vgs.launcher
  expect_poll "latency $kind reads its menu" true ipc smoke readInstance overlay vgs.launcher menusReady
  expect_poll "latency $kind window has queued its initial frame" drawn ipc smoke windowDrawn overlay vgs.launcher
  nested_input_check "$sandbox/keyboard" || return 1
  socket="$(shot_socket "$rt_dir" "$nested_socket")" || return 1
  rect="$(ipc smoke windowGeometry overlay vgs.launcher TextField "")" || return 1
  padding="$(ipc smoke readShownDescendant overlay vgs.launcher TextField leftPadding)" || return 1
  surface="$(surface_box vgs:overlay)" || return 1
  output="$smoke_log_dir/launcher-latency-$kind"
  "${shell_env[@]}" python3 "$repo/scripts/smoke/launcher-latency.py" measure \
    "$sandbox/keyboard" "$shell_qs_pid" "$socket" "$rect" "$padding" "$surface" "$output" || return 1
  cp -- "$instance_log" "$output/shell.log" || return 1
  cp -- "$sandbox/tree-launcher-latency-$kind/shell/Commons/Theme.qml" "$output/Theme.qml" || return 1
  cp -- "$sandbox/tree-launcher-latency-$kind/shell/plugins/vgs.launcher/Launcher.qml" "$output/Launcher.qml" || return 1
  stop_shell || return 1
}

launcher_latency_complete=true
if ! launcher_latency_measure normal; then
  fail "launcher-latency: normal observation incomplete"
  launcher_latency_complete=false
fi
if [[ $launcher_latency_complete == true ]] && ! launcher_latency_measure slow; then
  fail "launcher-latency: slow control observation incomplete"
  launcher_latency_complete=false
fi
launcher_latency_judge() {
  local launcher_latency_kind launcher_latency_summary launcher_latency_values
  local launcher_latency_min launcher_latency_max launcher_latency_pressure launcher_latency_load launcher_latency_single launcher_latency_pair
  local launcher_latency_per_core launcher_latency_verdict
  for launcher_latency_kind in normal slow; do
  launcher_latency_summary="$smoke_log_dir/launcher-latency-$launcher_latency_kind/summary.json"
  launcher_latency_values="$(python3 - "$launcher_latency_summary" <<'PY'
import json, math, sys
v = json.load(open(sys.argv[1]))
print(math.floor(v["minUpperMs"]), math.ceil(v["maxUpperMs"]),
      "%.1f" % v["maxCpuSomePct"], "%.2f" % v["maxLoad"],
      v["singleCharacter"], v["onePressRelease"])
PY
)" || return 1
  read -r launcher_latency_min launcher_latency_max launcher_latency_pressure launcher_latency_load launcher_latency_single launcher_latency_pair \
    <<<"$launcher_latency_values"
  launcher_latency_per_core="$(load_per_core "$launcher_latency_load")" || return 1
  launcher_latency_verdict="$(latency_load_verdict "$launcher_latency_max" "$launcher_latency_pressure" "$launcher_latency_per_core" "$launcher_latency_budget_ms")" || return 1
  printf 'launcher-latency: source=%s min_ms=%s max_ms=%s budget_ms=%s cpu_some_pct=%s load_per_core=%s result=%s proof=%s\n' \
    "$launcher_latency_kind" "$launcher_latency_min" "$launcher_latency_max" "$launcher_latency_budget_ms" \
    "$launcher_latency_pressure" "$launcher_latency_per_core" "$launcher_latency_verdict" "$launcher_latency_summary"
  if [[ $launcher_latency_verdict == unmeasured ]]; then
    not_measured launcher-latency "$(latency_busy_reason "$launcher_latency_pressure" "$launcher_latency_per_core")"
  elif [[ $launcher_latency_kind == slow ]]; then
    if [[ $launcher_latency_verdict == over && $launcher_latency_min -gt $launcher_latency_budget_ms ]]; then
      ok "control: repeated shared hint solving exceeds the glyph budget on every press"
    else
      fail "launcher-latency: slow control not over on every press"
    fi
  elif [[ $launcher_latency_verdict == within && $launcher_latency_single == True && $launcher_latency_pair == True ]]; then
    ok "one press inserts one character and its glyph capture meets the budget"
  else
    fail "launcher-latency: response=$launcher_latency_verdict single=$launcher_latency_single pair=$launcher_latency_pair"
  fi
done
}
if [[ $launcher_latency_complete == true ]]; then
  launcher_latency_judge || fail "launcher-latency: summary unreadable"
fi

# Give later rows the literal input files and uninstrumented harness shell.
stop_shell
for launcher_latency_file in shell.json theme.json launcher/menu.json; do
  if [[ -e $launcher_latency_saved/$launcher_latency_file ]]; then
    cp -p -- "$launcher_latency_saved/$launcher_latency_file" "$home/.config/vgshell/$launcher_latency_file"
  else
    rm -f -- "$home/.config/vgshell/$launcher_latency_file"
  fi
done
for launcher_latency_index in {000..059}; do
  rm -- "$home/.local/share/applications/vgs-latency-o-$launcher_latency_index.desktop"
done
expect "latency fixture restores nested repeat" ok hypr reload config-only
start_shell "$repo" "$sandbox/launcher-latency-restored.log"
