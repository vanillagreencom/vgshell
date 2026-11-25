# Open split readings (VGS-2674): each place a surface opens is opened on a
# fresh shell of a harness copy that scripts/smoke/open-split.py stamps,
# three times, its first open and two reopens, each after the surface
# before it was destroyed. Each open's reading splits component load,
# object creation, the instance's lending row, the shell-tool attachment
# with every binding it runs, the rest of the build, the plugin's own
# open(), the host's synchronous handler and the first frame Qt queued for
# the opened window, as separate figures. The row prints them,
# `open-split: place=... part=build|open ...`, and writes each reading to
# open-split/<place>-<open>.json under the run's log directory, with the
# world's CPU pressure over that open's window beside it.
# The places, each on its own shell except Jarvis Chat and the Settings
# Voice page, which share one Jarvis fixture shell: Jarvis Chat, opened
# first, and the Settings Voice page its Voice settings link opens under a
# speech-only (duplex) voice; the VPN panel; System opened on Displays;
# the VPN, Power and Displays panes selected in an open System window
# opened on another of them; Add Widget; the Themes panel; and the Theme
# browser's initial view, whose figure is its open() span. The device fakes device-fakes.sh leaves stand
# under VPN, Power and Displays; the nested output draws at 1x. Each
# shell of the harness copy opens nothing until the Themes service holds
# its catalog answer, which its views draw.
# After each open's first frame the row waits for every FirstView in the
# shell (shell/Ui/layout/FirstView.qml) to settle, and prints from that
# frame to the settle the longest deferred step, `longest_step_ms`, judged
# against nothing, since a step builds at least one whole row or block,
# such as one Settings group, the smallest unit a page defers. A block's
# step runs from its start to the end of the block's load, which the
# engine's incubation pauses only once the block's objects are created and
# between their bindings and completion handlers, so the figure bounds
# from above the longest span the block holds the GUI thread. No gap
# between frames is judged: the nested window draws only when asked,
# so a gap holds idle time (an idle Theme browser read p99 148 ms and an
# idle Power pane 289-457 ms in run 20261121T103920Z-5534). The content
# the first frame shows must be the content shown once the views settle,
# and the initial focus target must be built at that frame and hold active
# focus once settled: a first view that leaves part of the viewport to the
# steps, or an empty first frame, fails. The Settings Voice page opens
# through a link that reveals a field. An open that carries a reveal
# target builds every Settings group before its first frame (vgs.settings
# PluginPage `buildWhole`), so the target and
# everything above it are laid out before the reveal scrolls, and no
# class ceiling applies to it. It is read at its top: the link's reveal scrolls the page in a callLater after
# positioning, after the first frame. Its frame must show what the page
# shows at its top once settled, with the same focus target; the reveal
# itself is the Settings rows' check. An instance that builds through no
# FirstView defers nothing and takes no content check
# (scripts/smoke/open-split.py `content`).
# The class ceilings apply to every other measured place: sync_ms at most
# 460 and first_content_ms at most 380, each the highest reading of those
# places in run tmp/dev-validate-20261121T103920Z-5534 (head b347f835d,
# the nested sandbox at 1x on cachy, AMD Ryzen 9 9950X, 2026-11-21, world
# CPU pressure 0.0-0.2 %) times 1.25, rounded up to 10 ms: System's sync
# of 361 ms and its first content of 301 ms. harness.sh's
# latency_pressure_check judges each figure by the world CPU pressure over
# its open: an open above latency_pressure_limit is not measured, and one
# whose pressure is unread fails. Its control: a copy whose FirstView
# builds every shown part in its first view must take System opened on
# Displays over one ceiling at or below that pressure, and above it is not
# measured, never a pass; System read sync 484-541 ms and first content
# 410-416 ms on the base tree (run 20261121T095055Z-1376923-11154). The
# second control,
# a System copy whose shell attachment runs a planted 300 ms busy wait,
# must read attach_ms of at least 300. The row fails an open that answers
# no ok and a reading missing a figure. Teardown probes hide System in
# the turn after its summon and while its views build, turn the Themes
# plugin off while its panel builds (System is always on, and the Themes
# panel builds in steps for over a second after its first frame), and
# switch a System pane while its views build; the teardown shell's log,
# read whole as the next shell starts, must then hold no lifetime refusal
# and no script error.
# The class sweep reads `shell listPlugins`, each plugin's source from the
# probe and the summonable kinds from PluginLogic.js (open-split.py
# `sweep`):
# every bundled plugin a present requirement set allows is enabled on one
# fresh shell, and every summonable entry and every pane it finds is
# opened once with `{}`, each pane in a System window, and read; every
# host command a default-set service runs at start reaches the default
# set's stand-ins (harness.sh default_set_world), as on a default-set
# start. The polkit, sudo and lock plugins stay off, since the sandbox cannot meet
# the host authentication each needs, and Jarvis, measured on its fixture
# shell; a plugin a missing requirement keeps off is named with it. The
# places above are the discovery's floor: a listing that does not show one
# fails. Each sweep open must answer ok and stamp its first frame, and the
# sweep shell's log is read as every other shell's is; the readings are
# printed and judged against nothing, since no before reading exists for
# them. A surface added later comes under the sweep with no row edit, and
# its first reading is its before reading. Since the sweep opens what the
# listing holds, the input line names the plugin tree.
# Figures are the shell's own GUI-thread Date.now() stamps in integer ms.
# The row waits for each frame and settle stamp with expect_poll's 200 ms
# interval, which enters no figure. A frame is Qt queueing it, not the compositor
# presenting it, and a pane mounted in a shown window can read one frame
# early when a frame already in flight swaps after its build. A fresh shell
# starts with the QML disk cache the earlier shells of its tree left, as a
# second login does.
# loads: scripts/smoke/rows/device-fakes.sh -- state another row leaves
# loads: shell/plugins/vgs.jarvis/backend/skills/*.md -- a run-time load: a page, view or entry the core builds by a computed name
# loads: .agents/skills/jarvis/* -- a load past a process the row runs, or a copy
# loads: shell/plugins/* -- a startup file the row observes
# loads: scripts/fixtures/jarvis/* -- a fixture a harness function the row calls starts or reads
set -euo pipefail
source "$source_repo/scripts/smoke/jarvis-console.sh"
# The Jarvis fixtures log the set jarvis.sh declares.
expected_errors+=("${jarvis_provoked_errors[@]}")
devices_ready open-split || return 0

open_split_py="$source_repo/scripts/smoke/open-split.py"
open_split_out="$smoke_log_dir/open-split"
open_split_config="$sandbox/open-split-shell.json"
open_split_tree="$sandbox/tree-open-split"
open_split_own=""
mkdir -p -- "$open_split_out"
cp -- "$home/.config/vgshell/shell.json" "$open_split_config"

# The Jarvis places' state, undone by open_split_jarvis_end: words of
# requirements, asks and enabled.
open_split_jarvis_state=""
open_split_jarvis_end() {
  [[ $open_split_jarvis_state != *enabled* ]] || jarvis_disable
  [[ $open_split_jarvis_state != *asks* ]] || jarvis_asks_restore
  if [[ -n $open_split_jarvis_state ]]; then
    user_config_restore "$open_split_config" || fail "open-split: jarvis: the configuration copy is not restored"
    expect "open-split: jarvis: the fixture shell's configuration is restored" ok ipc shell reloadConfig
  fi
  [[ $open_split_jarvis_state != *requirements* ]] || jarvis_restore_requirements "$jarvis_fixture_shim"
  open_split_jarvis_state=""
}
# The default set's stand-ins, which the sweep plants and the restore
# takes back.
open_split_world="$sandbox/open-split-world"
open_split_restore() {
  open_split_jarvis_end
  [[ -z $open_split_own ]] || row_log_read "open-split: $open_split_own shell log" "$instance_log"
  open_split_own=""
  stop_shell || return 1
  default_set_world_restore "$open_split_world" || return 1
  user_config_restore "$open_split_config" || return 1
  start_shell "$repo" "$smoke_log_dir/open-split-restored.log"
}
smoke_row_abandon=(open_split_restore)

# The nested Hyprland writes a 1x scale as the integer 1 in its monitors JSON.
open_split_scale() { hypr -j monitors | py_reply 'import json,sys; s={m["scale"] for m in json.load(sys.stdin)}; print("1x" if s == {1} else json.dumps(sorted(s)))'; }
# open_split_shell PLACE TREE: a fresh shell of TREE for PLACE, behind the
# device guard, with the plugins the places open enabled, once, as the user
# file then keeps them, and their services built.
open_split_plugins=(vgs.vpn vgs.system vgs.displays vgs.power vgs.themes)
open_split_enabled=false
open_split_shell() { # PLACE TREE
  local id
  [[ -z $open_split_own ]] || row_log_read "open-split: $open_split_own shell log" "$instance_log"
  open_split_own=""
  stop_shell || return 1
  start_shell "$2" "$smoke_log_dir/open-split-$1.log" || return 1
  open_split_own="$1"
  devices_ready "open-split: $1" || return 1
  expect "open-split: $1: the nested output draws at 1x" 1x open_split_scale
  for id in "${open_split_plugins[@]}"; do
    [[ $open_split_enabled == true ]] || expect "open-split: $1: enabling $id is allowed" ok ipc shell setPluginEnabled "$id" true
    expect_poll "open-split: $1: the $id service is built" True record_exists "$id"
  done
  # The Themes service reads its catalog once it starts, and a view that
  # opens before the answer draws its catalog rows when it lands, after
  # the first frame; the open waits for the answer, so the first frame
  # reads the build, not the read.
  expect_poll "open-split: $1: the Themes service holds its catalog answer" read open_split_themes_read
  open_split_enabled=true
}
# open_split_themes_read: `read` once the Themes service holds a catalog
# answer, its entries or its refusal, else `pending`.
open_split_themes_read() {
  ipc smoke readInstance service vgs.themes catalog | py_reply 'import json,sys
v=json.load(sys.stdin)
print("read" if isinstance(v, dict) and (isinstance(v.get("entries"), list) or v.get("reason") is not None) else "pending")'
}

# open_split_figure READING_JSON FIGURE: the open's FIGURE in ms, or
# nothing when the reading holds no whole number there, which
# latency_pressure_verdict reads as unread.
open_split_figure() { # READING_JSON FIGURE
  python3 -c 'import json,sys; o=json.load(open(sys.argv[1]))["open"] or {}; v=o.get(sys.argv[2]); print(v if isinstance(v, int) and not isinstance(v, bool) else "")' "$1" "$2"
}
# open_split_pressure READING_JSON: the world CPU pressure over the open.
open_split_pressure() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cpu_some_pct"])' "$1"; }
# The class ceilings, in ms; the header names their readings.
open_split_sync_ceiling=460
open_split_content_ceiling=380
# open_split_content OFFSET KIND ID HOST_KEY: `held` when the open's first
# frame shows its settled content and focus target, or the instance builds
# through no FirstView, else the reader's verdict.
open_split_content() { # OFFSET KIND ID HOST_KEY
  local settled_content verdict
  settled_content="$(ipc smoke openSplitContent "$4" "$3")" || settled_content=unread
  verdict="$(python3 "$open_split_py" content "$instance_log" "$1" "$2" "$3" "$settled_content")" || return 1
  [[ $verdict == equal || $verdict == no-view ]] && echo held || echo "$verdict"
}
# open_split_content_top OFFSET KIND ID HOST_KEY TEXT: open_split_content
# against the page at its top: once the instance settles, the view holding
# TEXT scrolls to its top and the probe reads the instance there.
open_split_content_top() { # OFFSET KIND ID HOST_KEY TEXT
  local scrolled
  scrolled="$(ipc smoke scrollHoldingToTop "$4" "$3" "$5")" || { echo "top=unread"; return 0; }
  [[ $scrolled =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { echo "top=$scrolled"; return 0; }
  open_split_content "$1" "$2" "$3" "$4"
}
# open_split_read PLACE OPEN KIND ID OPEN_FN: one open of PLACE through
# OPEN_FN, read from the running shell's log after its size before the
# open into open-split/PLACE-OPEN.json; `open_split_offset` keeps that
# size. Nonzero when a figure is missing.
open_split_offset=0
open_split_read() { # PLACE OPEN KIND ID OPEN_FN
  local place="$1" open="$2" kind="$3" id="$4" start_us start_ms pressure
  open_split_offset="$(stat -c %s -- "$instance_log")" || { fail "open-split: $place $open: the shell log is unreadable"; return 1; }
  start_us="$(cpu_some_us)"
  start_ms="$(now_ms)"
  if ! "$5"; then fail "open-split: $place $open: the open was refused"; return 1; fi
  expect_poll "open-split: $place $open: the opened window's first frame is stamped" framed \
    python3 "$open_split_py" framed "$instance_log" "$open_split_offset" "$kind" "$id"
  expect_poll "open-split: $place $open: every first view settles" settled \
    python3 "$open_split_py" settled "$instance_log" "$open_split_offset"
  pressure="$(cpu_some_pct "$start_us" "$(cpu_some_us)" "$(( $(now_ms) - start_ms ))")"
  if python3 "$open_split_py" reading "$instance_log" "$open_split_offset" "$kind" "$id" "$place" "$open" "$pressure" "$open_split_out/$place-$open.json"; then
    ok "open-split: $place $open: every split figure is read"
  else
    fail "open-split: $place $open: a split figure is missing"
    return 1
  fi
}
# open_split_measure PLACE OPEN KIND ID OPEN_FN HOST_KEY [LINK_TEXT]: one
# judged open: the class ceilings and the first frame's content. A linked
# open, LINK_TEXT given, builds its page whole and takes no ceiling; its
# first frame is judged against the page at its top through the view
# holding LINK_TEXT.
open_split_measure() { # PLACE OPEN KIND ID OPEN_FN HOST_KEY [LINK_TEXT]
  local place="$1" open="$2" reading="$open_split_out/$1-$2.json" pressure
  if open_split_read "$1" "$2" "$3" "$4" "$5" && [[ -z ${7:-} ]]; then
    pressure="$(open_split_pressure "$reading")" || pressure=unread
    latency_pressure_check open-split "${place}_${open}_sync" "$(open_split_figure "$reading" sync_ms)" "$pressure" "$open_split_sync_ceiling"
    latency_pressure_check open-split "${place}_${open}_first_content" "$(open_split_figure "$reading" first_content_ms)" "$pressure" "$open_split_content_ceiling"
  fi
  if [[ -n ${7:-} ]]; then
    expect "open-split: $place $open: the first frame shows the page top and its focus target" held \
      open_split_content_top "$open_split_offset" "$3" "$4" "$6" "$7"
  else
    expect "open-split: $place $open: the first frame shows the settled content and its focus target" held \
      open_split_content "$open_split_offset" "$3" "$4" "$6"
  fi
}
# open_split_place PLACE KIND ID HOST_KEY OPEN_FN CLOSE_FN [LINK_TEXT]: the
# first open and two reopens, the surface destroyed after each.
open_split_place() { # PLACE KIND ID HOST_KEY OPEN_FN CLOSE_FN [LINK_TEXT]
  local open
  for open in first reopen-1 reopen-2; do
    open_split_measure "$1" "$open" "$2" "$3" "$5" "$4" "${7:-}" || return 1
    if ! "$6"; then fail "open-split: $1 $open: the close was refused"; return 1; fi
    expect_poll "open-split: $1 $open: the surface is destroyed before the next open" 0 ipc smoke pluginInstances "$4" "$3"
  done
}

open_split_summon() { [[ $(ipc shell summon "$1" "$2" "$3") == ok ]]; } # KIND ID PAYLOAD
open_split_hide() { [[ $(ipc shell hide "$1" "$2") == ok ]]; } # KIND ID
open_split_enter() { [[ $(ipc smoke invokeInstance window vgs.system enterPane "$1") == ok ]]; } # PANE
open_split_chat_open() { open_split_summon window vgs.jarvis '{}'; }
open_split_chat_close() { open_split_hide window vgs.jarvis; }
open_split_voice_open() { click_item window:Jarvis window vgs.jarvis RowAction "Voice settings"; }
open_split_voice_close() { open_split_hide window vgs.settings; }
open_split_vpn_open() { open_split_summon panel vgs.vpn '{}'; }
open_split_vpn_close() { open_split_hide panel vgs.vpn; }
open_split_system_open() { open_split_summon window vgs.system '{"pane":"vgs.displays"}'; }
open_split_system_close() { open_split_hide window vgs.system; }
open_split_widget_open() { open_split_summon window vgs.bar "{\"screen\":\"$(first_name)\",\"x\":40}"; }
open_split_widget_close() { open_split_hide window vgs.bar; }
open_split_panel_open() { open_split_summon panel vgs.themes '{}'; }
open_split_panel_close() { open_split_hide panel vgs.themes; }
open_split_browser_open() { open_split_summon overlay vgs.themes '{}'; }
open_split_browser_close() { open_split_hide overlay vgs.themes; }
open_split_pane_target=""
open_split_pane_holder=""
open_split_pane_open() { open_split_enter "$open_split_pane_target"; }
open_split_pane_close() { open_split_enter "$open_split_pane_holder"; }

# open_split_pane PLACE PANE HOLDER: PANE selected three times in a System
# window opened on HOLDER, which each close selects again.
open_split_pane() { # PLACE PANE HOLDER
  open_split_shell "$1" "$open_split_tree" || return 1
  expect "open-split: $1: System opens on $3" ok ipc shell summon window vgs.system "{\"pane\":\"$3\"}"
  expect_poll "open-split: $1: System mounts $3" "[\"$3\"]" window_panes
  open_split_pane_target="$2"
  open_split_pane_holder="$3"
  open_split_place "$1" pane "$2" window open_split_pane_open open_split_pane_close || return 1
  expect "open-split: $1: System closes" ok ipc shell hide window vgs.system
}

# The fixture copies the harness tree, $repo, which carries the probe and
# the Jarvis fixture world; $source_repo is the checkout and carries neither.
open_split_jarvis() {
  jarvis_fixture_copy open-split-jarvis "$repo" "" || return 1
  python3 "$open_split_py" prepare "$sandbox/tree-open-split-jarvis" || return 1
  jarvis_fixture_begin "$sandbox/tree-open-split-jarvis" || return 1
  open_split_own=jarvis
  devices_ready "open-split: jarvis" || return 1
  expect "open-split: jarvis: the nested output draws at 1x" 1x open_split_scale
  open_split_jarvis_state=requirements
  jarvis_setup_requirements "$jarvis_fixture_shim" || return 1
  open_split_jarvis_state+=" asks"
  jarvis_asks_fixture "$source_repo" || return 1
  expect "open-split: jarvis: the fixture shell selects its private package Home" ok ipc shell reloadConfig
  "$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" \
    "$jarvis_fixture_tree/shell/plugins/vgs.jarvis/backend/jarvisd.js" "$sandbox/open-split-gates" --duplex || return 1
  jarvis_rescan || return 1
  open_split_jarvis_state+=" enabled"
  jarvis_enable
  open_split_place jarvis-chat window vgs.jarvis window open_split_chat_open open_split_chat_close || return 1
  expect "open-split: Jarvis Chat opens for its Voice settings link" ok ipc shell summon window vgs.jarvis '{}'
  expect_poll "open-split: Chat shows the Voice settings link under a speech-only voice" true ipc smoke readInstance window vgs.jarvis speechOnly
  # The link reveals a field of the AI model group's page, which holds
  # that heading once settled.
  open_split_place voice-settings window vgs.settings window open_split_voice_open open_split_voice_close "AI model" || return 1
  expect "open-split: Jarvis Chat closes" ok ipc shell hide window vgs.jarvis
}

open_split_jarvis || fail "open-split: the Jarvis places were not measured"
open_split_jarvis_end

copy_tree open-split
python3 "$open_split_py" prepare "$open_split_tree"
if open_split_shell vpn-panel "$open_split_tree"; then
  open_split_place vpn-panel panel vgs.vpn panel open_split_vpn_open open_split_vpn_close || true
fi
if open_split_shell system-displays "$open_split_tree"; then
  open_split_place system-displays window vgs.system window open_split_system_open open_split_system_close || true
fi
open_split_pane pane-vpn vgs.vpn vgs.displays || true
open_split_pane pane-power vgs.power vgs.vpn || true
open_split_pane pane-displays vgs.displays vgs.power || true
if open_split_shell add-widget "$open_split_tree"; then
  open_split_place add-widget window vgs.bar window open_split_widget_open open_split_widget_close || true
fi
if open_split_shell themes-panel "$open_split_tree"; then
  open_split_place themes-panel panel vgs.themes panel open_split_panel_open open_split_panel_close || true
fi
if open_split_shell theme-browser "$open_split_tree"; then
  open_split_place theme-browser overlay vgs.themes overlay open_split_browser_open open_split_browser_close || true
fi

# The control: a System window whose shell attachment runs a planted
# 300 ms busy wait. The attachment span must hold it, so attach_ms covers
# the bindings the assignment runs and no neighbouring span takes them.
open_split_attach() { # READING_JSON
  python3 -c 'import json,sys; b=[r for r in json.load(open(sys.argv[1]))["builds"] if (r["kind"], r["id"]) == ("window", "vgs.system")]; print(b[0]["attach_ms"] if b and b[0]["attach_ms"] is not None else "absent")' "$1"
}
copy_tree open-split-control
python3 "$open_split_py" prepare "$sandbox/tree-open-split-control"
if edit_tree open-split-control shell/plugins/vgs.system/Window.qml '    property var shell: null' '    property var shell: null
    onShellChanged: { const end = Date.now() + 300; while (Date.now() < end) {} }' \
    && open_split_shell control "$sandbox/tree-open-split-control"; then
  open_split_read control first window vgs.system open_split_system_open || true
  open_split_control_attach="$(open_split_attach "$open_split_out/control-first.json")" || open_split_control_attach=unread
  if [[ $open_split_control_attach =~ ^[0-9]+$ ]] && (( open_split_control_attach >= 300 )); then
    ok "control: a planted 300 ms attachment cost reads in attach_ms ($open_split_control_attach ms)"
  else
    fail "control: the planted attachment cost read attach_ms=$open_split_control_attach, want at least 300"
  fi
  open_split_system_close || fail "open-split: control: the System close was refused"
fi

# The control: a copy whose FirstView builds every shown part in its
# first view, so System builds whole before its first frame, must take
# System over a class ceiling. Each figure takes latency_pressure_verdict,
# the judge of the ceilings: above the pressure limit the control is not
# measured, never a pass.
# open_split_over READING_JSON: `over` when a figure is over its ceiling,
# else `unmeasured`, `unread` or `within` with what was read.
open_split_over() { # READING_JSON
  local pressure sync content
  pressure="$(open_split_pressure "$1")" || pressure=unread
  sync="$(latency_pressure_verdict "$(open_split_figure "$1" sync_ms)" "$pressure" "$open_split_sync_ceiling")"
  content="$(latency_pressure_verdict "$(open_split_figure "$1" first_content_ms)" "$pressure" "$open_split_content_ceiling")"
  if [[ $sync == unread || $content == unread ]]; then echo "unread sync=$sync first_content=$content cpu_some_pct=$pressure"
  elif [[ $sync == unmeasured ]]; then echo "unmeasured cpu_some_pct=$pressure"
  elif [[ $sync == over || $content == over ]]; then echo over
  else echo "within sync=$sync first_content=$content"
  fi
}
copy_tree open-split-eager
python3 "$open_split_py" prepare "$sandbox/tree-open-split-eager"
if edit_tree open-split-eager shell/Ui/layout/FirstView.qml \
    '                if (!(above || next <= target || (isFinite(cap) && height < Math.max(cap, targetBottom() + cap)))) break;' '' \
    && open_split_shell eager "$sandbox/tree-open-split-eager"; then
  if open_split_read eager first window vgs.system open_split_system_open; then
    open_split_eager="$(open_split_over "$open_split_out/eager-first.json")" || open_split_eager=unread
    case "$open_split_eager" in
      over) ok "control: a first view that builds the whole System window fails a class ceiling" ;;
      unmeasured*) not_measured open-split "control-eager-${open_split_eager#unmeasured }-above-$latency_pressure_limit" ;;
      *) fail "control: a first view that builds the whole System window fails a class ceiling: got $open_split_eager" ;;
    esac
  else
    fail "control: the eager System window was not read"
  fi
  open_split_system_close || fail "open-split: eager: the System close was refused"
fi

# Teardown while views build: each probe ends a surface the frame after its
# open, or in the turn after it. A lifetime refusal (shell/Core/Lifetime.js)
# throws, and a thrown error is a script error line the harness's log
# check fails (harness.sh row_log_read), which reads this shell's log whole
# as the next shell starts.
open_split_teardown() { # LABEL OPEN_FN END_FN HOST_KEY KIND ID WAIT_FRAME
  local offset
  offset="$(stat -c %s -- "$instance_log")" || { fail "open-split: teardown $1: the shell log is unreadable"; return 1; }
  if ! "$2"; then fail "open-split: teardown $1: the open was refused"; return 1; fi
  [[ $7 != true ]] || expect_poll "open-split: teardown $1: the first frame is stamped" framed python3 "$open_split_py" framed "$instance_log" "$offset" "$5" "$6"
  if ! "$3"; then fail "open-split: teardown $1: the end was refused"; return 1; fi
  expect_poll "open-split: teardown $1: the surface is gone" 0 ipc smoke pluginInstances "$4" "$6"
}
open_split_themes_off() { [[ $(ipc shell setPluginEnabled vgs.themes false) == ok ]]; }
if open_split_shell teardown "$open_split_tree"; then
  open_split_teardown "hide in the summon's turn" open_split_system_open open_split_system_close window window vgs.system false || true
  open_split_teardown "hide while System builds" open_split_system_open open_split_system_close window window vgs.system true || true
  open_split_teardown "turn Themes off while its panel builds" open_split_panel_open open_split_themes_off panel panel vgs.themes true || true
  expect "open-split: teardown: Themes turns back on" ok ipc shell setPluginEnabled vgs.themes true
  expect_poll "open-split: teardown: the vgs.themes service is built again" True record_exists vgs.themes
  expect "open-split: teardown: System opens on VPN" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
  expect_poll "open-split: teardown: System mounts VPN" '["vgs.vpn"]' window_panes
  open_split_pane_target=vgs.displays
  open_split_pane_holder=vgs.power
  open_split_teardown "switch the pane while Displays builds" open_split_pane_open open_split_pane_close window pane vgs.displays true || true
  expect "open-split: teardown: System closes" ok ipc shell hide window vgs.system
fi

# The class sweep. The floor is the places measured above.
open_split_floor=(window/vgs.jarvis window/vgs.settings panel/vgs.vpn window/vgs.system
  pane/vgs.vpn pane/vgs.power pane/vgs.displays window/vgs.bar panel/vgs.themes overlay/vgs.themes)
# open_split_until WANT CMD...: 0 once CMD prints WANT, polled every 200 ms
# for 10 s; 1 when it never does, after printing CMD's last answer; 2 when
# CMD fails, after printing its output and errors, so a reader that fails
# reads apart from a place that never draws.
open_split_until() { # WANT CMD...
  local want="$1" err="$sandbox/open-split-until.err" i got
  shift
  for i in $(seq 1 50); do
    if ! got="$("$@" 2>"$err")"; then
      printf '%s %s\n' "$got" "$(tr '\n' ' ' <"$err")"
      return 2
    fi
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  printf '%s\n' "$got"
  return 1
}
# open_split_sweep_open PLACE KIND ID OPEN...: one sweep open, which must
# answer ok and stamp its first frame; its figures are printed and judged
# against nothing. Nonzero only when the open did not answer ok, so the
# caller hides every surface it opened.
open_split_sweep_open() { # PLACE KIND ID OPEN...
  local place="$1" kind="$2" id="$3" offset reply got status=0
  shift 3
  offset="$(stat -c %s -- "$instance_log")" || { fail "open-split: sweep: $place: the shell log is unreadable"; return 1; }
  reply="$("$@" 2>&1)" || reply="failed: $reply"
  if [[ $reply != ok ]]; then fail "open-split: sweep: $place: the open answers ok: got $reply"; return 1; fi
  got="$(open_split_until framed python3 "$open_split_py" framed "$instance_log" "$offset" "$kind" "$id")" || status=$?
  case $status in
    0) ;;
    2) fail "open-split: sweep: $place: the frame reader failed: $got"; return 0 ;;
    *) fail "open-split: sweep: $place: the opened window's first frame is stamped within 10 s: got $got"; return 0 ;;
  esac
  got="$(open_split_until settled python3 "$open_split_py" settled "$instance_log" "$offset")" \
    || echo "open-split: sweep: place=$place settle=unread $got"
  python3 "$open_split_py" reading "$instance_log" "$offset" "$kind" "$id" "$place" first "-" "$open_split_out/$place.json" || true
}
open_split_sweep() {
  local plan sources line verb id rest kind reply got lines=() panes=()
  sources="$(ipc smoke pluginSources)" || { fail "open-split: sweep: the plugin sources are unreadable"; return 1; }
  plan="$(ipc shell listPlugins | python3 "$open_split_py" sweep "$open_split_tree" "$sources" "${open_split_floor[@]}")" \
    || { fail "open-split: sweep: discovery is incomplete"; return 1; }
  ok "open-split: sweep: discovery finds every measured place"
  # The plan is read whole first, so no command in a loop reads its lines.
  mapfile -t lines <<<"$plan"
  for line in "${lines[@]}"; do
    read -r verb id rest <<<"$line"
    case "$verb" in
      excluded|off) echo "open-split: sweep: $line" ;;
      enable)
        reply="$(ipc shell setPluginEnabled "$id" true 2>&1)" || reply="failed: $reply"
        [[ $reply == ok ]] || echo "open-split: sweep: enable $id refused: $reply"
        ;;
      pane) panes+=("$id") ;;
    esac
  done
  for line in "${lines[@]}"; do
    read -r verb kind id <<<"$line"
    [[ $verb == entry ]] || continue
    open_split_sweep_open "sweep-$kind-$id" "$kind" "$id" ipc shell summon "$kind" "$id" '{}' || continue
    reply="$(ipc shell hide "$kind" "$id" 2>&1)" || reply="failed: $reply"
    [[ $reply == ok ]] || echo "open-split: sweep: place=$kind/$id hide=$reply"
    got="$(open_split_until 0 ipc smoke pluginInstances "$kind" "$id")" || echo "open-split: sweep: place=$kind/$id close=unread $got"
  done
  (( ${#panes[@]} > 0 )) || return 0
  reply="$(ipc shell summon window vgs.system "{\"pane\":\"${panes[0]}\"}" 2>&1)" || reply="failed: $reply"
  if [[ $reply != ok ]]; then fail "open-split: sweep: System opens on ${panes[0]}: got $reply"; return 1; fi
  got="$(open_split_until "[\"${panes[0]}\"]" window_panes)" || echo "open-split: sweep: System did not mount ${panes[0]} $got"
  # System opened on the first pane; entering it again last mounts it as
  # the others are.
  for id in "${panes[@]:1}" "${panes[0]}"; do
    open_split_sweep_open "sweep-pane-$id" pane "$id" ipc smoke invokeInstance window vgs.system enterPane "$id" || true
  done
  ipc shell hide window vgs.system >/dev/null 2>&1 || true
}
# The sweep enables every bundled plugin, so its shell starts over the
# default set's stand-ins.
if default_set_world "$open_split_world" && open_split_shell sweep "$open_split_tree"; then
  open_split_sweep || true
fi

# Give later rows the stock configuration and the uninstrumented shell.
open_split_restore
