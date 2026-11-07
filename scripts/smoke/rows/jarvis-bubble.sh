# Runs inside jarvis-keys' private scripted ports and physical keyboard.
# Its engine copy selects the scripted chained plan, so each thinking turn
# runs through the real chained engine and its words are the engine's own
# captions. No real audio, provider, authentication or network runs.
# Presentation and state poll once per IPC round trip; no latency budget is
# claimed. The motion readings count the layer window's swapped frames
# after the look settles: each moving state swaps one within 0.2 s, read
# again until it does (the motion model), and at motion scale 0, which
# stills every state, the fault's look swaps none over 3 s, counted once
# the layer is quiet, and none within the moving states' 0.2 s, so a
# reader that counts nothing fails the moving states and a still state
# fails them. The quiet wait reads the moving fault as swapped, and a
# redraw planted after it fails the still reading.
# The waiting orb swaps at most its look's frame rate over 2 s, and
# speaking, which draws every frame, swaps more in the same reader.
# Jarvis's words are read as the bubble hands them to Words, published at
# once, so the reveal's restart cannot hide a user's line. The icon row
# shows only while the pointer rests on the active orb, so a click on an
# icon hovers the orb first.
# Hidden capture reads the core host's completed badge frames and the
# Session observation at the scripted capture port's actual open call.
# Widget removal, bar unmapping and a widget on only the unfocused output
# must withdraw capture. These are state/order probes, not timing budgets.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* bin/lib/qml-library.js shell/plugins/vgs.bar/* shell/Ui/controls/Button.qml shell/Ui/controls/IconButton.qml shell/Ui/feedback/LinkText.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Core/Layers.qml shell/Hosts/BarHost.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml scripts/smoke/toplevel/* scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/diagnostics.sh
set -euo pipefail
jarvis_bubble_snapshots="$(mktemp -d "$sandbox/jarvis-bubble-snapshots.XXXXXX")"
jarvis_bubble_row_config="$jarvis_bubble_snapshots/shell.json"
jarvis_bubble_focus_output=false
jarvis_bubble_client=""
jarvis_bubble_row_focus="$(hypr -j activewindow | py_reply 'import json,sys; print(json.load(sys.stdin).get("address", ""))')"
cp -p -- "$home/.config/vgshell/shell.json" "$jarvis_bubble_row_config"
jarvis_bubble_probe_before="$(plugin_enabled acme.probe)"
case "$jarvis_bubble_probe_before" in
  True) jarvis_bubble_probe_before=true ;;
  False) jarvis_bubble_probe_before=false ;;
  *) fail "the bubble's compositor fixture enablement is unreadable: $jarvis_bubble_probe_before"; return 0 ;;
esac
jarvis_bubble_restore_probe() {
  expect "the bubble row restores its compositor fixture" ok ipc shell setPluginEnabled acme.probe "$jarvis_bubble_probe_before"
}
jarvis_bubble_close_client() {
  [[ -n $jarvis_bubble_client ]] || return 0
  close_toplevel "$jarvis_bubble_client" "the client below Jarvis exits" || return 1
  jarvis_bubble_client=""
}
jarvis_bubble_abandon() {
  local before target
  jarvis_key_talk_up
  jarvis_key_stop
  jarvis_disable
  ipc shell hide window vgs.jarvis >/dev/null
  # These snapshots are acquired before each corresponding control plant.
  while read -r before target; do
    if [[ -f $before ]]; then cp -- "$before" "$target"; fi
  done <<EOF
$jarvis_bubble_snapshots/engine $repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js
$jarvis_bubble_snapshots/backend $jarvis_key_backend
$jarvis_bubble_snapshots/bubble $repo/shell/plugins/vgs.jarvis/Bubble.qml
$jarvis_bubble_snapshots/words $repo/shell/plugins/vgs.jarvis/Words.qml
$jarvis_bubble_snapshots/widget $repo/shell/plugins/vgs.jarvis/Widget.qml
$jarvis_bubble_snapshots/fixture $repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js
$sandbox/jarvis-key-service-before $jarvis_key_service
EOF
  if [[ -f $jarvis_bubble_snapshots/focus ]]; then
    cp -- "$jarvis_bubble_snapshots/focus" "$home/.config/hypr/hyprland.lua"
    if [[ $jarvis_bubble_focus_output == true ]]; then
      expect "the bubble row removes its extra focus output" ok hypr output remove SMOKE-JARVIS
    fi
    expect "the bubble row restores its focus rules" ok hypr reload config-only
  fi
  cp -p -- "$jarvis_bubble_row_config" "$home/.config/vgshell/shell.json.next"
  mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
  expect "the bubble row restores its configuration" ok ipc shell reloadConfig
  # Voice mute persists in its own record; the row leaves it off.
  rm -f -- "${home:?}/.local/state/vgshell/jarvis/voice-mute.json"
  rm -f -- "${home:?}/.local/state/vgshell/jarvis/hidden.json"
  expect "the bubble row reveals its temporarily hidden bar" ok ipc vgs.bar invoke reveal ''
  # Early geometry failure can leave the source snapshots unchanged.
  rescan "the bubble row rescans its restored sources"
  jarvis_enable
  jarvis_bubble_close_client
  if [[ -n $jarvis_bubble_row_focus ]]; then
    expect "the bubble row restores its previous focus" ok hypr dispatch "hl.dsp.focus({ window = \"address:$jarvis_bubble_row_focus\" })"
  fi
  jarvis_bubble_restore_probe
}
smoke_row_abandon=(jarvis_bubble_abandon)
expect "the bubble row enables its compositor dispatch fixture" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the bubble's compositor fixture answers before positioning" bubble probe echo bubble

jarvis_bubble_required_box() { # TYPE PROPERTY VALUE
  local box
  box="$(control_box vgs:layer vgs.jarvis "$@")" || { echo unreadable; return 1; }
  [[ $box == \[* ]] || { printf '%s\n' "$box"; return 1; }
  printf '%s\n' "$box"
}
jarvis_bubble_box_control() { # BOX STATUS
  (
    local reply="$1" transport_status="$2"
    control_box() { printf '%s\n' "$reply"; return "$transport_status"; }
    local box status=0
    # Replace only the geometry transport; the reader still runs unchanged.
    box="$(jarvis_bubble_required_box "$1" "$2")" || status=$?
    printf 'status=%s box=%s\n' "$status" "$box"
  )
}
expect "absent bubble geometry is a failed reading" 'status=1 box=absent' jarvis_bubble_box_control absent 0
expect "failed bubble geometry transport is a failed reading" 'status=1 box=unreadable' jarvis_bubble_box_control absent 1
expect "present bubble geometry remains readable" 'status=0 box=[1, 2, 3, 4]' jarvis_bubble_box_control '[1, 2, 3, 4]' 0

jarvis_bubble_state() {
  ipc smoke layerWindows vgs.jarvis | py_reply '
import json,sys
rows=json.load(sys.stdin)
shown=[r for r in rows if r["visible"] and r["presented"] and r["width"]>0 and r["height"]>0]
print("presented" if len(shown)==1 else "not-presented")
'
}
jarvis_bubble_widgets() {
  ipc shell built | py_reply '
import json,sys
bars=[r for host,rows in json.load(sys.stdin).items() if host.startswith("bar:") for r in rows]
if not any(r["id"]=="acme.tick" for r in bars):
    sys.exit("jarvis-bubble: bar-reader=missing-tick")
print(sum(r["id"]=="vgs.jarvis" for r in bars))
'
}
jarvis_bubble_hide_bar() {
  local answer
  answer="$(ipc shell setPluginEnabled vgs.bar false)" || return 1
  case "$answer" in
    ok|ok\ hidden=*) echo ok ;;
    *) printf '%s\n' "$answer" ;;
  esac
}
# A value of the overlay's own look (Appearance.js), as JSON, read from the
# bubble that binds it.
jarvis_bubble_look_value() { # DOTTED_PATH
  ipc smoke layerItems vgs.jarvis Bubble look | py_reply '
import json,sys
rows=json.load(sys.stdin)
if not rows: sys.exit("jarvis-bubble: look=absent")
value=rows[0][2]["look"]
for key in sys.argv[1].split("."): value=value[key]
print(json.dumps(value))
' "$1"
}
jarvis_bubble_geometry() {
  local box window margin
  box="$(control_box vgs:layer vgs.jarvis QQuickItem objectName overlay)" &&
    window="$(surface_box vgs:layer)" &&
    margin="$(jarvis_bubble_look_value layout.margin)" || return 1
  [[ $box == \[* && $window == \[* ]] || { echo absent; return; }
  python3 -c '
import json,sys
b,w=map(json.loads,sys.argv[1:3]); margin=float(sys.argv[3])
ok=(b[2]>0 and b[3]>0 and b[0]>=w[0] and b[1]>=w[1]
    and b[0]+b[2]<=w[0]+w[2] and b[1]+b[3]<=w[1]+w[3]
    and abs((b[0]+b[2]/2)-(w[0]+w[2]/2))<=1
    and abs((w[1]+w[3])-(b[1]+b[3])-margin)<=1)
print("bottom-centre" if ok else "wrong-geometry")
' "$box" "$window" "$margin"
}
# The orb's core, the square inside its ring, against the colour most of
# its pixels hold: `drawn` when at least 2% of them differ from it by more
# than 48 in a channel sum, `blank` when under 0.1% do, `faint` between.
# Under a hidden shader the core holds only what lies below the layer.
jarvis_bubble_pixels() {
  local box socket geometry verdict
  box="$(control_box vgs:layer vgs.jarvis ParticleOrb active true)" &&
    socket="$(shot_socket "$rt_dir" "$nested_socket")" || return 1
  [[ $box == \[* ]] || { echo absent; return; }
  geometry="$(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); s=round(w*0.4); print("%d,%d %dx%d"%(x+w/2-s/2,y+h/2-s/2,s,s))' "$box")" || return 1
  verdict="$(shot_grim "$socket" "$rt_dir" -g "$geometry" -t ppm - | python3 -c '
import sys
from collections import Counter
d=sys.stdin.buffer.read().split(b"\n",3)
if len(d)!=4 or d[0]!=b"P6" or d[2]!=b"255": sys.exit("jarvis-bubble: pixels=unreadable")
w,h=map(int,d[1].split()); pixels=d[3]
if len(pixels)!=w*h*3 or w*h==0: sys.exit("jarvis-bubble: pixels=incomplete")
cells=[pixels[i:i+3] for i in range(0,len(pixels),3)]
base=Counter(cells).most_common(1)[0][0]
off=sum(sum(abs(a-b) for a,b in zip(c,base))>48 for c in cells)/len(cells)
print("drawn" if off>=0.02 else "blank" if off<0.001 else "faint")
')" || return 1
  printf '%s\n' "$verdict"
}
# Jarvis's words as the bubble draws them while its voice is muted: one
# visible Words view whose revealed words are the whole caption and whose
# reveal has ended, longer than the look's line count. Its drawn lines are
# the visible Labels inside its box, each line's words read left to right
# and the lines top to bottom. `latest-lines` when exactly the look's line
# count draws and, read in order, they are the caption's last words;
# `unbounded` when another count draws; `wrong-order` otherwise;
# `progressing` while words still appear.
jarvis_bubble_words() {
  local views labels lines
  views="$(ipc smoke layerItems vgs.jarvis Words shown,settled,lineCount,visible)" &&
    labels="$(ipc smoke layerItems vgs.jarvis Label text,visible)" || return 1
  [[ $views == \[* && $labels == \[* ]] || { printf 'jarvis-bubble: words-reader=unreadable views=%s labels=%s\n' "$views" "$labels" >&2; return 1; }
  if [[ $views == '[]' ]]; then echo absent; return; fi
  lines="$(jarvis_bubble_look_value words.lines)" || return 1
  python3 -c '
import json,sys
views,labels=map(json.loads,sys.argv[1:3]); lines=int(json.loads(sys.argv[3])); text=" ".join(sys.argv[4].split())
shown=[(s,b,v) for s,b,v in views if v["visible"]]
if not shown: print("absent"); sys.exit()
if len(shown)!=1: print("unbounded"); sys.exit()
screen,(x,y,w,h),view=shown[0]
if not view["settled"] or view["shown"]!=text: print("progressing"); sys.exit()
if view["lineCount"]<=lines: print("short"); sys.exit()
# Boxes are rounded apart, so an edge may stand one pixel out.
drawn={}
for s,b,v in labels:
    if s==screen and v["visible"] and v["text"]!="" and b[2]>0 and b[0]>=x-1 and b[0]+b[2]<=x+w+1 and b[1]>=y-1 and b[1]+b[3]<=y+h+1:
        drawn.setdefault(b[1],[]).append((b[0],v["text"]))
if len(drawn)!=lines: print("unbounded"); sys.exit()
rows=[" ".join(t for _,t in sorted(drawn[top])) for top in sorted(drawn)]
print("latest-lines" if text.endswith(" "+" ".join(rows)) else "wrong-order")
' "$views" "$labels" "$lines" "$jarvis_bubble_reply"
}
# The phase whose look the shown orb draws: the orb's phase once each
# uniform of its shader holds what that phase's look in the shipped table
# (Appearance.js, read through the shell's library loader) sets: the six
# palette stops, the tone (interior, rim, saturation, presence) and the
# radius and brightness, which a driving level and a throb move only
# within the look's own drive and throb depth. Else the phase and the
# uniforms still easing toward it, or `uniforms=unreadable`.
jarvis_bubble_look() {
  local orbs shaders
  orbs="$(ipc smoke layerItems vgs.jarvis ParticleOrb phase,active)" &&
    shaders="$(ipc smoke layerItems vgs.jarvis QQuickShaderEffect uTop,uUpper,uLower,uBottom,uCore,uHot,uShape,uTone,uExtra)" || return 1
  "$node_bin" - "$orbs" "$shaders" "$repo/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.jarvis/Appearance.js" <<'JS'
const [rawOrbs, rawShaders, library, table] = process.argv.slice(2);
const looks = require(library).load(table).TOKENS.state;
const orbs = JSON.parse(rawOrbs).filter(([, , value]) => value.active);
if (orbs.length !== 1) { console.log("orbs=" + orbs.length); process.exit(0); }
const [screen, box, orb] = orbs[0];
const effects = JSON.parse(rawShaders).filter(([at, place]) => at === screen && JSON.stringify(place) === JSON.stringify(box));
if (effects.length !== 1) { console.log("shaders=" + effects.length); process.exit(0); }
const want = looks[orb.phase];
if (want === undefined) { console.log("unknown=" + orb.phase); process.exit(0); }
const u = effects[0][2];
// A vector4d reads as its x, y, z and w, or as Qt's QVector4D(...) text.
const vector = value => {
    if (value !== null && typeof value === "object" && ["x", "y", "z", "w"].every(k => typeof value[k] === "number"))
        return [value.x, value.y, value.z, value.w];
    const text = typeof value === "string" ? /^QVector4D\(([^)]*)\)$/.exec(value) : null;
    const parts = text === null ? [] : text[1].split(",").map(Number);
    return parts.length === 4 && parts.every(Number.isFinite) ? parts : null;
};
const [shape, tone, extra] = [u.uShape, u.uTone, u.uExtra].map(vector);
if (shape === null || tone === null || extra === null) { console.log("uniforms=unreadable"); process.exit(0); }
const v = key => want[key].value;
const near = (a, b) => Math.abs(a - b) <= 1e-3;
const within = (a, low, high) => a >= low - 1e-3 && a <= high + 1e-3;
const easing = ["top", "upper", "lower", "bottom", "core", "hot"].filter(stop =>
    u["u" + stop[0].toUpperCase() + stop.slice(1)].toLowerCase().slice(-6) !== v(stop).toLowerCase().slice(1, 7));
["interior", "rim", "saturation", "presence"].forEach((key, i) => { if (!near(tone[i], v(key))) easing.push(key); });
if (!within(shape[0], v("radius"), v("radius") * (1 + v("driveRadius")))) easing.push("radius");
if (!within(extra[0], v("brightness") - v("throbDepth"), v("brightness") + v("driveBright") + v("throbDepth"))) easing.push("brightness");
console.log(easing.length === 0 ? orb.phase : orb.phase + ":easing=" + easing.join(","));
JS
}
# `quiet` when the Jarvis layer window the probe watches swaps no frame
# over 3 s, counted from the first moment the window is quiet: two reads
# 0.1 s apart that agree, within 20 such reads. A change that just
# happened, such as a theme flip, redraws the layer a few times however
# short its scaled transition is, so the count waits for those swaps
# rather than for a duration. `swapped` when the window swaps inside the
# 3 s or never goes quiet within the 20 reads. At motion scale 0 every
# state reads `quiet`. A PLANT command runs between the quiet wait and the
# count, where the control plants a redraw.
jarvis_bubble_still() { # [PLANT...]
  local before after reads quiet=false
  before="$(ipc smoke layerFrames)" || return 1
  for reads in $(seq 1 20); do
    sleep 0.1
    after="$(ipc smoke layerFrames)" || return 1
    [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
    if ((after == before)); then quiet=true; break; fi
    before="$after"
  done
  if [[ $quiet != true ]]; then
    printf '        jarvis_layer_quiet=none reads=%s last=%s\n' "$reads" "$after" >&2
    echo swapped
    return
  fi
  if (($# > 0)); then "$@" || return 1; fi
  # The acceptance interval is a real 3 s presentation observation.
  sleep 3
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
  printf '        jarvis_layer_frames_before=%s after=%s interval_s=3\n' "$before" "$after" >&2
  if ((after == before)); then echo quiet; else echo swapped; fi
}
# `advancing` when the Jarvis layer window the probe watches swaps a frame
# within 0.2 s, read after the look's transition and two frames at 60 Hz,
# as voice.sh's voice_frames_advancing reads; `stopped` otherwise.
jarvis_bubble_advancing() {
  local transition before after
  transition="$(jarvis_bubble_look_value orb.transition)" || return 1
  sleep "$(python3 -c 'import sys; print((int(sys.argv[1]) + 34) / 1000)' "$transition")"
  before="$(ipc smoke layerFrames)" || return 1
  sleep 0.2
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
  if ((after > before)); then echo advancing; else echo stopped; fi
}
# `paced` when the Jarvis layer window the probe watches swaps at most
# 15% over RATE frames a second across 2 s, read after the look's
# transition; `unpaced` otherwise. RATE is the waiting look's
# `frameRate`, which the waiting orb must hold and the speaking orb, which
# draws every frame of the nested output's 60, must pass. The rate prints
# to stderr.
jarvis_bubble_paced() { # RATE
  local transition before after
  transition="$(jarvis_bubble_look_value orb.transition)" || return 1
  sleep "$(python3 -c 'import sys; print((int(sys.argv[1]) + 34) / 1000)' "$transition")"
  before="$(ipc smoke layerFrames)" || return 1
  # The reading is a real 2 s of presented frames.
  sleep 2
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ && $1 =~ ^[1-9][0-9]*$ ]] || { echo "unreadable before=$before after=$after rate=$1"; return; }
  printf '        jarvis_layer_frames_per_s=%s rate=%s interval_s=2\n' "$(((after - before) / 2))" "$1" >&2
  if (((after - before) * 100 <= $1 * 2 * 115)); then echo paced; else echo unpaced; fi
}
# Flip the scheme's mode and keep motion at 0: every ink the bubble draws
# changes, so the still layer redraws once the theme reloads, well inside
# the 3 s count (theme-latency.sh holds a theme change to 292 ms).
jarvis_bubble_flip_mode() {
  local mode
  mode="$(ipc smoke themeValue scheme.mode)" || return 1
  case "$mode" in
    '"dark"') mode=light ;;
    '"light"') mode=dark ;;
    *) printf 'jarvis-bubble: scheme-mode=%s\n' "$mode" >&2; return 1 ;;
  esac
  printf '{"schemaVersion":1,"name":"jarvis-bubble-motion-off","tokens":{"scheme":{"mode":"%s"},"motion":{"scale":0}}}\n' "$mode" >"${home:?}/.config/vgshell/theme.json.tmp" &&
    mv -T -- "${home:?}/.config/vgshell/theme.json.tmp" "${home:?}/.config/vgshell/theme.json"
}
jarvis_bubble_voice_key() { hold_send "down 133" "down 37" "down 58" "up 58" "up 37" "up 133"; }
jarvis_bubble_buttons() { ipc smoke layerItemsWith vgs.jarvis RowButton label "$1"; }
# The words a visible Words view has revealed, `none` with none shown.
jarvis_bubble_shown() {
  ipc smoke layerItems vgs.jarvis Words shown,settled,visible | py_reply '
import json,sys
rows=[v for _,_,v in json.load(sys.stdin) if v["visible"]]
print("none" if not rows else rows[0]["shown"] if rows[0]["settled"] else "progressing")
'
}
jarvis_bubble_caption() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
s=json.load(sys.stdin)["status"]; t=s.get("transcript")
print("none" if t is None else "current" if t["gen"]==s["detail"]["state"]["gen"] and t["role"]=="assistant" else "stale")
'
}
# The words each bubble hands its Words view, which Words publishes at once
# while its reveal starts over: with PHRASE, `handed` when a bubble hands
# words holding it and `absent` when none does; with none, `empty` when
# every bubble hands none and `words` otherwise. `no-words` when no Words
# view is read.
jarvis_bubble_handed() { # [PHRASE]
  ipc smoke layerItems vgs.jarvis Words text | py_reply '
import json,sys
texts=[v["text"] for _,_,v in json.load(sys.stdin)]
phrase=sys.argv[1]
if not texts: print("no-words")
elif phrase: print("handed" if any((" "+t+" ").find(" "+phrase+" ")!=-1 for t in texts) else "absent")
else: print("empty" if all(t.strip()=="" for t in texts) else "words")
' "${1:-}"
}
# The committed words of the current conversation as Session publishes
# them on each chained request, a role-user caption, written through the
# held status writer so no assistant line can come first.
jarvis_bubble_user_caption() {
  local gen
  gen="$(ipc smoke jarvisProcess | py_reply 'import json,sys; print(json.load(sys.stdin)["status"]["detail"]["state"]["gen"])')" ||
    { fail "the current conversation is readable"; return 0; }
  expect "the service status writer is held for the user caption" held ipc smoke holdStatus service vgs.jarvis
  expect "the user's committed words reach the caption" ok ipc smoke heldStatusSet transcript \
    "{\"gen\": $gen, \"role\": \"user\", \"text\": \"scripted utterance\", \"stage\": \"final\", \"rev\": 1}"
}
# What the scripted voice was asked to say since record FROM, each sentence
# named: the long request's two stated steps, its answer, and any other line,
# which in that turn is the acknowledgement.
jarvis_bubble_said() { # FROM|count
  python3 - "$jarvis_key_gates/effects.jsonl" "$1" <<'PY'
import json,sys
try:
    rows=[json.loads(line) for line in open(sys.argv[1]) if line.strip()]
except (OSError, ValueError):
    rows=[]
said=[row.get("text","") for row in rows if row.get("kind")=="speech-speak"]
if sys.argv[2]=="count":
    print(len(said))
    sys.exit(0)
names=[]
for text in said[int(sys.argv[2]):]:
    if "Reading the Fidelity pages" in text: names.append("step1")
    elif "Searching records" in text: names.append("step2")
    elif "The balance is ready" in text: names.append("answer")
    else: names.append("ack")
print(",".join(names) or "none")
PY
}
# Re-publish a real caption from the ended conversation to test the generation
# consumer after the next turn has supplied its own authoritative user text.
jarvis_bubble_old_caption() {
  expect "the service status writer is held for the old-caption control" held ipc smoke holdStatus service vgs.jarvis
  expect "the earlier caption reaches the existing status input" ok ipc smoke heldStatusSet transcript "$jarvis_bubble_earlier"
}
# After jarvis_bubble_begin: one thinking turn; on request, the engine's
# scripted reply releases its words.
jarvis_bubble_think() { # [caption]
  jarvis_key_talk_up
  jarvis_key_commit
  [[ ${1-} == caption ]] || return 0
  jarvis_key_gate reply
  expect_poll "the service publishes this conversation's assistant caption" current jarvis_bubble_caption
}
jarvis_bubble_no_capture() {
  expect_poll "an unavailable indicator releases capture" closed jarvis_key_state capture
  expect "the daemon records indicator gone" gone jarvis_key_state indicator
}
jarvis_bubble_focused() {
  local rows focused
  rows="$(ipc smoke layerWindows vgs.jarvis)" &&
    focused="$(ipc smoke readInstance service vgs.jarvis focusedOutput)" || return 1
  py_reply '
import json,sys
rows=json.load(sys.stdin); focused=json.loads(sys.argv[1])
ok=any(r["screen"]==focused for r in rows) and all(
    r["screen"]==focused for r in rows if r["shown"] or r["visible"])
print("focused" if ok else "wrong-output")
' "$focused" <<<"$rows"
}
jarvis_bubble_loss_control() {
  (failures=0 behaviour_failures=0
   jarvis_bubble_no_capture >"$sandbox/jarvis-bubble-loss-control.log"
   echo "$failures")
}
jarvis_bubble_pass() { # X Y
  local down up
  down="$(other_events '^button 272 pressed$')" &&
    up="$(other_events '^button 272 released$')" || return 1
  hover "$1" "$2" && click "$1" "$2" || return 1
  expect_poll "a decorative point delivers press to the client below" "$((down + 1))" other_events '^button 272 pressed$'
  expect_poll "a decorative point delivers release to the client below" "$((up + 1))" other_events '^button 272 released$'
  rest_pointer || fail "the pointer returns to rest after a decorative click"
}
# The active orb's centre, where the pointer shows the icon row and a
# right click opens the Jarvis menu: "X Y", or a failed reading.
jarvis_bubble_orb_centre() {
  local box
  box="$(jarvis_bubble_required_box ParticleOrb active true)" || return 1
  python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(round(x+w/2), round(y+h/2))' "$box"
}
# The open Jarvis menu's entries, [] while it is closed.
jarvis_bubble_menu() {
  ipc smoke layerItems vgs.jarvis Bubble menuTexts | py_reply '
import json,sys
rows=[v["menuTexts"] for _,_,v in json.load(sys.stdin) if v["menuTexts"]]
print(json.dumps(rows[0] if len(rows)==1 else [] if not rows else "menus=%d" % len(rows)))
'
}
jarvis_bubble_menu_open() {
  ipc smoke layerItems vgs.jarvis Bubble menuOpened | py_reply 'import json,sys; print(str(any(v["menuOpened"] for _,_,v in json.load(sys.stdin))).lower())'
}
jarvis_bubble_menu_choose() { # LABEL [TYPE PROPERTY VALUE]
  local point box x y index step
  if (($# == 1)); then point="$(jarvis_bubble_orb_centre)" || return 1
  else
    box="$(jarvis_bubble_required_box "$2" "$3" "$4")" || return 1
    point="$(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(round(x+w/2),round(y+h/2))' "$box")" || return 1
  fi
  read -r x y <<<"$point" || return 1
  right_click "$x" "$y" || return 1
  expect_poll "the overlay opens its shared menu" true jarvis_bubble_menu_open
  index="$(jarvis_bubble_menu | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows.index(sys.argv[1]) if sys.argv[1] in rows else "absent")' "$1")" || return 1
  [[ $index =~ ^[0-9]+$ ]] || { fail "the overlay menu has no $1: $index"; return 1; }
  type_keys -k Home || return 1
  for ((step = 0; step < index; step++)); do type_keys -k Down || return 1; done
  type_keys -k Return || return 1
  expect_poll "$1 closes the overlay menu" '[]' jarvis_bubble_menu
  rest_pointer
}
# The observation is the service's read-only, scoped core publication, not
# the widget's requested key or a configured placement.
jarvis_bubble_bar_frame() { # present|listening|other-output
  local frames focus process
  frames="$(ipc smoke readInstance service vgs.jarvis barPresentations)" &&
    focus="$(ipc smoke readInstance service vgs.jarvis focusedOutput)" &&
    process="$(ipc smoke jarvisProcess)" || return 1
  py_reply '
import json,sys
rows=json.load(sys.stdin); focus=json.loads(sys.argv[1])
s=json.loads(sys.argv[2])["status"]["detail"]["state"]; want=sys.argv[3]
current=[r for r in rows if r["key"] in (str(s["gen"])+":present",str(s["gen"])+":listening")]
focused=[r for r in current if r["output"]==focus]
if want=="other-output":
    ok=not focused and any(r["output"]!=focus and r["key"]==str(s["gen"])+":listening" and r["dot"]=="success" for r in current)
elif want=="listening":
    ok=any(r["key"]==str(s["gen"])+":listening" and r["dot"]=="success" for r in focused)
else: ok=bool(focused)
print(want if ok else "pending")
' "$focus" "$process" "$1" <<<"$frames"
}
jarvis_bubble_hide_blocked() {
  ipc smoke layerItems vgs.jarvis Bubble menuEntries | py_reply '
import json,sys
rows=json.load(sys.stdin)
entries=[e for _,_,v in rows for e in v["menuEntries"] if e.get("intent")=="hide"]
print("blocked" if entries and all(e.get("disabledReason") for e in entries) else "unavailable")
'
}
# Read all built copies, including the unmapped ones: hidden ordinary
# content must not hand Words a caption or retain an orb field.
jarvis_bubble_hidden() { # quiet|required
  local bubbles orbs
  bubbles="$(ipc smoke layerItems vgs.jarvis Bubble hidden,words,capturePresented,iconsShown,fieldBoxes,presented,shown)" &&
    orbs="$(ipc smoke layerItems vgs.jarvis ParticleOrb visible,active)" || return 1
  py_reply '
import json,sys
rows=json.load(sys.stdin); orbs=json.loads(sys.argv[1]); required=sys.argv[2]=="required"
ok=bool(rows) and bool(orbs) and all(v["hidden"] and v["words"]=="" and not v["capturePresented"] and not v["iconsShown"] for _,_,v in rows)
ok=ok and all(not v["visible"] and not v["active"] for _,_,v in orbs)
if required: ok=ok and any(v["shown"] and v["presented"] and len(v["fieldBoxes"])==1 for _,_,v in rows)
else: ok=ok and all(len(v["fieldBoxes"])==0 and not v["shown"] for _,_,v in rows)
print("required" if ok and required else "quiet" if ok else "wrong-content")
' "$orbs" "$1" <<<"$bubbles"
}
jarvis_bubble_hidden_loss() {
  expect_poll "loss of the focused bar badge retires capture" closed jarvis_key_state capture
  expect_poll "the daemon observes the bar indicator withdrawn" gone jarvis_key_state barIndicator
  expect "hidden required text grants no orb indicator" gone jarvis_key_state indicator
  expect "indicator withdrawal preserves the hidden choice" hidden jarvis_key_state visibility
}
# The fixture records Session's state before calling the capture port.
# Require at least one hidden open, and no hidden open before its own
# generation's listening observation or with an orb observation.
jarvis_bubble_hidden_opens() {
  python3 - "$jarvis_key_gates/effects.jsonl" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
try: rows=[json.loads(line) for line in p.read_text().splitlines()]
except (OSError,ValueError): print("unreadable"); sys.exit()
if not all(isinstance(r,dict) for r in rows): print("unaccepted"); sys.exit()
opens=[r for r in rows if r.get("kind")=="capture-open" and r.get("visibility",{}).get("kind")=="hidden"]
ok=bool(opens) and all(r.get("barIndicator")=={"kind":"listening","gen":r.get("gen")} and r.get("indicator")=={"kind":"gone"} for r in opens)
print("framed-before-open" if ok else "unframed")
PY
}
jarvis_bubble_click() { # LABEL
  local point x y
  if ! point="$(jarvis_bubble_orb_centre)"; then
    fail "the orb under the $1 button is readable"
    return 0
  fi
  read -r x y <<<"$point"
  hover "$x" "$y" || { fail "the pointer reaches the orb under the $1 button"; return 0; }
  expect_poll "the pointer on the orb shows the $1 button" 1 jarvis_bubble_buttons "$1"
  if ! point="$(point_item vgs:layer vgs.jarvis RowButton label "$1")"; then
    fail "the labelled $1 button reports hover before click"
    printf 'jarvis-bubble: pointer-not-ready=%s\n' "$1"
    ipc smoke layerItems vgs.jarvis RowButton label,hovered,visible >&2 || true
    ipc smoke layerWindows vgs.jarvis >&2 || true
    return 0
  fi
  read -r x y <<<"$point" || { fail "the labelled $1 button point is unreadable"; return 0; }
  click "$x" "$y" || fail "the labelled $1 button click is not delivered"
}
jarvis_bubble_begin() {
  if [[ $(jarvis_key_state conversation) != ended ]]; then
    jarvis_key_talk_up
    # Stop after a retry pauses automatic input. Its next Talk resumes;
    # only a second fresh press closes that still-active conversation.
    if [[ $(jarvis_key_state holdToTalk) == false && $(jarvis_key_state input) == stopped ]]; then
      jarvis_key_tap
      expect_poll "Talk resumes the stopped automatic input" listening jarvis_key_state phase
      expect_poll "the resumed automatic input is a conversation" conversation jarvis_key_state input
      jarvis_key_wait_past "$jarvis_key_tapped_at" 300
    fi
    [[ $(jarvis_key_state holdToTalk) != true ]] || jarvis_key_gate silent-capture
    jarvis_key_tap
    expect_poll "the prior conversation closes through Talk" ended jarvis_key_state conversation
    rm -f -- "$jarvis_key_gates/silent-capture"
    # Session collapses presses within 250 ms; this next physical down
    # must be distinct from the closing tap, not a fabricated admission.
    jarvis_key_wait_past "$jarvis_key_tapped_at" 300
  fi
  jarvis_key_talk_down
  expect_poll "capture waits for its selected indicator then listens" listening jarvis_key_state phase
  if [[ $(jarvis_key_state visibility) == hidden ]]; then
    expect_poll "hidden listening has a focused host-framed badge" listening jarvis_bubble_bar_frame listening
    expect_poll "hidden listening draws no ordinary overlay" quiet jarvis_bubble_hidden quiet
  else
    expect_poll "the listening bubble has presented on its own host" presented jarvis_bubble_state
  fi
}

# The real service acknowledges the frame, then Session applies its draw
# interval. Repeated physical presses exercise that interval without a sleep.
jarvis_bubble_approval() { # action|release
  jarvis_bubble_begin
  jarvis_bubble_think
  jarvis_key_gate "approve-$1"
  expect_poll "the scripted request reaches the held region" held jarvis_key_state approval
}
jarvis_bubble_acknowledged() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
a=json.load(sys.stdin)["status"]["detail"]["state"]["approval"]
print("drawn" if a["kind"]=="held" and a["shownAt"] is not None else "pending")
'
}
jarvis_bubble_request() {
  local state buttons clips fields
  state="$(ipc smoke jarvisProcess)" &&
    buttons="$(ipc smoke layerItems vgs.jarvis Answer variant,visible)" &&
    clips="$(ipc smoke layerItems vgs.jarvis Words text)" &&
    fields="$(ipc smoke layerItems vgs.jarvis Label role,visible)" || return 1
  "$node_bin" - "$state" "$buttons" "$clips" "$fields" "$jarvis_key_gates/effects.jsonl" "$repo/shell/plugins/vgs.jarvis/backend/ToolRouter.js" <<'JS'
const [rawState, rawButtons, rawClips, rawFields, effects, file] = process.argv.slice(2);
const fs = require("node:fs"), assert = require("node:assert/strict"), crypto = require("node:crypto");
const state = JSON.parse(rawState).status.detail.state, held = state.approval;
const calls = fs.readFileSync(effects, "utf8").trim().split("\n").map(JSON.parse);
const canonical = require("node:vm").runInNewContext(fs.readFileSync(file, "utf8") + "\ncanonical",
    { require: require("node:module").createRequire(file), module: { exports: {} }, Buffer });
try {
    assert.equal(held.kind, "held");
    assert.notEqual(held.shownAt, null);
    const call = calls.find(row => row.kind === "approval-call" && row.id === held.id);
    assert.ok(call);
    assert.equal(call.gen, state.gen);
    assert.equal(call.op, held.brain);
    assert.equal(call.purpose, held.purpose);
    if (held.purpose === "action") {
        assert.deepEqual(call.call, { id: "files.delete", args: { path: "/home/fixture/draft.txt" } });
        assert.equal(held.tool, "files.delete");
        assert.equal(held.physical, true);
        assert.equal(held.digest, crypto.createHash("sha256").update(call.call.id + "\n" + canonical(call.call.args)).digest("hex"));
    } else {
        assert.equal(held.purpose, "release");
        assert.equal(call.call, null);
        assert.equal(held.tool, "fixture");
        assert.equal(held.physical, false);
    }
    const buttons = JSON.parse(rawButtons).filter(([, , value]) => value.visible).sort((a, b) => a[1][0] - b[1][0]);
    assert.deepEqual(buttons.map(([, , value]) => value.variant), ["ghost", "secondary"]);
    const [left, right] = buttons.map(([, box]) => box);
    assert.ok(left[2] > 0 && right[2] > 0 && left[0] + left[2] < right[0]);
    assert.equal(left[1], right[1]);
    const labels = JSON.parse(rawFields);
    const fields = labels.filter(([, , value]) => value.visible);
    const questions = fields.filter(([, box, value]) => value.role === "bodyStrong" && box[1] < left[1]);
    assert.equal(questions.length, 1);
    assert.ok(questions[0][1][2] > 0 && questions[0][1][3] > 0);
    if (held.purpose === "action") {
        const paths = fields.filter(([, box, value]) => value.role === "hint" && box[1] >= questions[0][1][1] + questions[0][1][3] && box[1] < left[1]);
        assert.ok(paths.length > 0);
        paths.sort((a, b) => a[1][1] - b[1][1]);
        assert.ok(paths[0][1][2] > 0 && paths[0][1][3] > 0);
    }
    // Jarvis's words, which voice mute draws above the orb, give way to
    // the held question: no bubble hands its Words view a word beside it.
    // The handed text, not the revealed words: Words reveals one word each
    // `words.step` and is hidden until the first, so a read of `shown`
    // can land before a word that would draw.
    const clips = JSON.parse(rawClips);
    assert.ok(clips.length > 0);
    assert.deepEqual(clips.filter(([, , value]) => value.text.trim() !== "").map(([, , value]) => value.text), []);
    console.log(1);
} catch (error) {
    if (!(error instanceof assert.AssertionError)) throw error;
    console.error("jarvis-bubble: held-contract=" + error.message);
    console.log(0);
}
JS
}
jarvis_bubble_confirm_key() {
  hold_send "down 133" "down 37" "down 29" "up 29" "up 37" "up 133"
  jarvis_key_state approval
}
jarvis_bubble_answer_button() { # BUTTON
  local point x y
  point="$(point_item vgs:layer vgs.jarvis Answer variant "$([[ $1 == Cancel || $1 == No ]] && echo ghost || echo secondary)")" || return 1
  read -r x y <<<"$point" || return 1
  click "$x" "$y" || return 1
  jarvis_key_state approval
}
jarvis_bubble_accept() { # key|BUTTON EFFECT EXPECTED
  if [[ $1 == key ]]; then
    expect_poll "the effective key confirms the drawn request" none jarvis_bubble_confirm_key
  else
    expect_poll "the bubble button answers its drawn request" none jarvis_bubble_answer_button "$1"
  fi
  expect "the answer reaches the request owner exactly once" "$3" jarvis_key_effects "$2"
}
# The console's message field and hint line against the bubble's card, in
# layout pixels: `clear` when the card meets neither and both lie whole
# inside the focused output, `overlap` or `outside` otherwise. The field is
# the console's empty message TextArea: no draft is typed.
jarvis_bubble_console() {
  local field hint card output
  field="$(control_box window:Jarvis window vgs.jarvis TextArea '')" &&
    hint="$(control_box window:Jarvis window vgs.jarvis Label 'Jarvis is waiting for your answer. Confirm or cancel the request first.')" &&
    card="$(control_box vgs:layer vgs.jarvis QQuickItem objectName overlay)" &&
    output="$(hypr -j monitors | py_reply 'import json,sys; m=next(m for m in json.load(sys.stdin) if m["focused"]); print(json.dumps([m["x"], m["y"], m["width"] / m["scale"], m["height"] / m["scale"]]))')" || return 1
  [[ $field == \[* && $hint == \[* && $card == \[* ]] || { echo absent; return; }
  python3 -c '
import json,sys
field,hint,card,out=map(json.loads,sys.argv[1:5])
inside=lambda r: r[0]>=out[0] and r[1]>=out[1] and r[0]+r[2]<=out[0]+out[2] and r[1]+r[3]<=out[1]+out[3]
meets=lambda a,b: a[0]<b[0]+b[2] and b[0]<a[0]+a[2] and a[1]<b[1]+b[3] and b[1]<a[1]+a[3]
print("outside" if not (inside(field) and inside(hint)) else "overlap" if meets(card,field) or meets(card,hint) else "clear")
' "$field" "$hint" "$card" "$output"
}
# The console's address and the position that puts its bottom edge on its
# output's work-area bottom, inside the band the card draws in at the
# bottom, whatever size the nested output has: `ADDRESS X Y`.
jarvis_bubble_console_low() {
  local client monitors
  client="$(window_of Jarvis address at size monitor)" && monitors="$(hypr -j monitors)" || return 1
  python3 -c '
import json,sys
(address,at,size,monitor),ms=map(json.loads,sys.argv[1:3])
m=next(m for m in ms if m["id"]==monitor)
print(address, at[0], int(m["y"] + m["height"] / m["scale"] - m["reserved"][3] - size[1]))
' "$client" "$monitors"
}
jarvis_bubble_console_hold() {
  local address x y
  expect "the Jarvis console summons over the bubble's client" ok ipc shell summon window vgs.jarvis '{}'
  expect_poll "the Jarvis console maps" 1 window_count Jarvis
  read -r address x y < <(jarvis_bubble_console_low) || { fail "the console's low position is readable"; return 0; }
  expect "the console moves into the bubble's bottom band" ok probe dispatch "moveWindow $address $x $y"
  geometry expect_poll "the console's low position is read back" "[[$x, $y]]" window_of Jarvis at
  jarvis_bubble_approval action
  expect_poll "the held request over the console is drawn" drawn jarvis_bubble_acknowledged
}
# The console closes while the request is still held: only the closewindow
# read brings the card back to the bottom.
jarvis_bubble_console_unmap() {
  expect "the Jarvis console hides" ok ipc shell hide window vgs.jarvis
  expect_poll "the Jarvis console unmaps" 0 window_count Jarvis
}
jarvis_bubble_console_return() {
  geometry expect_poll "closing the console returns the held request to bottom centre" bottom-centre jarvis_bubble_geometry
}
jarvis_bubble_console_close() {
  jarvis_bubble_console_unmap
  jarvis_bubble_console_return
  jarvis_key_stop
  jarvis_key_stop_assertion
}

jarvis_bubble_engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
cp -- "$jarvis_bubble_engine" "$jarvis_bubble_snapshots/engine.next"
mv -T -- "$jarvis_bubble_snapshots/engine.next" "$jarvis_bubble_snapshots/engine"
cp -- "$jarvis_key_backend" "$jarvis_bubble_snapshots/backend.next"
mv -T -- "$jarvis_bubble_snapshots/backend.next" "$jarvis_bubble_snapshots/backend"
jarvis_disable
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --held-approvals "$jarvis_key_backend"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --chained-engine "$jarvis_bubble_engine"
# Instrument only this row's disposable scripted port, not the daemon or
# the production admission judge.
python3 - "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='record("capture-open", e);'
assert s.count(needle)==1
changed=s.replace(needle, 'record("capture-open", { ...e, visibility: state().visibility, barIndicator: state().barIndicator, indicator: state().indicator });')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect_poll "no requirement notice stands over the bubble's client" null notice_shown
expect_poll "ready idle maps no bubble" 0 layer_count vgs:layer
expect "the Jarvis widget unplaces without disabling its service" ok ipc shell setPluginPlaced vgs.jarvis false
expect "the build contains no Jarvis bar widget" 0 jarvis_bubble_widgets
if ! open_other "$sandbox/toplevel-jarvis-bubble.log"; then fail "the client below Jarvis maps"; exit 1; fi
jarvis_bubble_client="$other_pid"
expect_poll "the client below Jarvis has keyboard focus" '["smoke.other", "Other window"]' active_window
jarvis_bubble_begin
geometry expect_poll "the bubble clears reserved space and sits at bottom centre" bottom-centre jarvis_bubble_geometry
expect_poll "listening draws its own look" listening jarvis_bubble_look
expect "the bubble takes no keyboard focus" '["smoke.other", "Other window"]' active_window
geometry expect_poll "the orb draws without a Jarvis bar widget" drawn jarvis_bubble_pixels
expect "control: hide only the bubble's shader" ok ipc smoke layerShaderSet vgs.jarvis ParticleOrb false
geometry expect_poll "control: the same pixel reader sees the hidden shader" blank jarvis_bubble_pixels
expect "the shader is restored" ok ipc smoke layerShaderSet vgs.jarvis ParticleOrb true
geometry expect_poll "the restored orb draws" drawn jarvis_bubble_pixels
expect "the bar disables independently of Jarvis" ok jarvis_bubble_hide_bar
expect_poll "the orb still presents without any bar" presented jarvis_bubble_state
geometry expect_poll "the bubble follows the free area without a bar" bottom-centre jarvis_bubble_geometry
expect "the bar returns without restarting Jarvis" ok ipc shell setPluginEnabled vgs.bar true
expect_poll "the bubble follows the restored reserved space" presented jarvis_bubble_state
expect_poll "Hide explains the missing focused bar widget" blocked jarvis_bubble_hide_blocked
expect "Hide refuses without a presented widget" 'refused: hide=indicator' ipc vgs.jarvis invoke hide ''
expect "a refused Hide leaves the orb choice shown" shown jarvis_key_state visibility

expect "the icon row hides while the pointer is away from the orb" 0 jarvis_bubble_buttons "Stop Jarvis"
if ! orb_box="$(jarvis_bubble_required_box ParticleOrb active true)"; then
  fail "the bubble's orb is unreadable: $orb_box"
  jarvis_bubble_abandon
  return 0
fi
# A box can sit at a half pixel, as the overlay's height adds the orb's
# ring, 87.975 px; bash arithmetic takes whole numbers.
read -r orb_x orb_y orb_w orb_h < <(python3 -c 'import json,sys; print(*map(round, json.loads(sys.argv[1])))' "$orb_box")
# The listening orb takes the pointer on its centre alone: its canvas left
# of the ring is decorative.
jarvis_bubble_pass "$((orb_x + orb_w / 20))" "$((orb_y + orb_h / 2))"
hover "$((orb_x + orb_w / 2))" "$((orb_y + orb_h / 2))" || fail "the pointer reaches the listening orb's centre"
expect_poll "the pointer on the listening orb shows the icon row" 1 jarvis_bubble_buttons "Stop Jarvis"
if ! mute_box="$(jarvis_bubble_required_box RowButton label 'Mute microphone')"; then
  fail "the shown icon row is unreadable: $mute_box"
  jarvis_bubble_abandon
  return 0
fi
read -r mute_x mute_y mute_w mute_h < <(python3 -c 'import json,sys; print(*map(round, json.loads(sys.argv[1])))' "$mute_box")
# The canvas just above the shown icon row is decorative too.
if ((mute_y - 6 > orb_y)); then
  jarvis_bubble_pass "$((mute_x + mute_w / 2))" "$((mute_y - 6))"
else
  fail "the orb's canvas reaches above the icon row: orb=$orb_box mute=$mute_box"
fi
expect_poll "the icon row hides once the pointer leaves the orb" 0 jarvis_bubble_buttons "Stop Jarvis"
# A right click on the listening orb's centre opens the Jarvis menu at the
# click, with the shared Jarvis entries; Escape closes it.
right_click "$((orb_x + orb_w / 2))" "$((orb_y + orb_h / 2))" || fail "the right click on the listening orb is not delivered"
expect_poll "a right click on the listening orb opens the Jarvis menu" "[\"Mute Jarvis's voice\", \"Mute microphone\", \"Stop Jarvis\", \"New conversation\", \"Hide Jarvis\", \"Key hints\"]" jarvis_bubble_menu
type_keys -k Escape || fail "Escape on the Jarvis menu failed"
expect_poll "Escape closes the Jarvis menu" "[]" jarvis_bubble_menu
rest_pointer || fail "the pointer returns to rest after the Jarvis menu"
expect "decorative clicks and the menu keep capture live" open jarvis_key_state capture
jarvis_bubble_click "Stop Jarvis"
jarvis_key_talk_up
jarvis_key_stop_assertion
expect_poll "Stop keeps the open conversation visible" presented jarvis_bubble_state

# The capture fake loses its device after opening, then holds the retry's
# open callback. The real daemon/Session owns the fault and cancellation.
for jarvis_bubble_hold in true false; do
  for jarvis_bubble_stop_trigger in button key ipc; do
    jarvis_key_hold "$jarvis_bubble_hold"
    jarvis_bubble_begin
    jarvis_key_gate device-lost
    expect_poll "device loss enters retry before $jarvis_bubble_stop_trigger Stop in $jarvis_bubble_hold" retrying jarvis_key_state fault
    expect_poll "the retry card remains presented" presented jarvis_bubble_state
    case "$jarvis_bubble_stop_trigger" in
      button) jarvis_bubble_click "Stop Jarvis" ;;
      key) jarvis_key_stop ;;
      ipc) expect "Stop IPC is accepted during retry" ok ipc vgs.jarvis invoke stop '' ;;
    esac
    jarvis_key_stop_assertion
    expect_poll "Stop keeps the conversation after clearing retry in $jarvis_bubble_hold" presented jarvis_bubble_state
    expect "Stop clears the retry fault" none jarvis_key_state fault
    jarvis_key_gate device-back
    expect "a late device callback cannot reopen capture" closed jarvis_key_state capture
    jarvis_key_talk_up
    rm -f -- "$jarvis_key_gates/device-gone" "$jarvis_key_gates/device-back"
  done
done
jarvis_key_hold true
# Voice mute stays on from here through the mutation controls, so Jarvis's
# words draw; the words section turns it off and on again.
jarvis_bubble_begin
jarvis_bubble_click "Mute Jarvis's voice"
expect_poll "the voice button mutes Jarvis's voice" on jarvis_key_state voiceMute
expect_poll "the voice button names its next action" 1 jarvis_bubble_buttons "Unmute Jarvis's voice"
expect "voice mute keeps capture live" open jarvis_key_state capture
jarvis_key_talk_up
jarvis_key_stop
jarvis_key_stop_assertion

for jarvis_bubble_answer in key Confirm Cancel Yes No; do
  jarvis_bubble_purpose=action
  case "$jarvis_bubble_answer" in Yes|No) jarvis_bubble_purpose=release ;; esac
  jarvis_bubble_effect=tool-start
  case "$jarvis_bubble_answer" in Cancel|No) jarvis_bubble_effect=approval-ended ;; Yes) jarvis_bubble_effect=release-confirmed ;; esac
  jarvis_bubble_before="$(jarvis_key_effects "$jarvis_bubble_effect")"
  jarvis_bubble_approval "$jarvis_bubble_purpose"
  expect_poll "the held request receives a drawn-frame acknowledgment" drawn jarvis_bubble_acknowledged
  expect_poll "a held request draws the confirming look" confirming jarvis_bubble_look
  expect "the drawn hold binds its typed call and ordered button roles without a duplicate caption" 1 jarvis_bubble_request
  expect "drawing a hold starts no request" "$jarvis_bubble_before" jarvis_key_effects "$jarvis_bubble_effect"
  expect "approval keeps the application's keyboard focus" '["smoke.other", "Other window"]' active_window
  geometry expect_poll "the held request stays inside its surface" bottom-centre jarvis_bubble_geometry
  # A confirmed action runs until the tool gate, so its look is read.
  [[ $jarvis_bubble_answer != Confirm ]] || jarvis_key_gate hold-tool
  jarvis_bubble_accept "$jarvis_bubble_answer" "$jarvis_bubble_effect" "$((jarvis_bubble_before + 1))"
  if [[ $jarvis_bubble_answer == Confirm ]]; then
    expect_poll "the confirmed action runs" acting jarvis_key_state phase
    expect_poll "a running action draws the acting look" acting jarvis_bubble_look
    rm -- "${jarvis_key_gates:?}/hold-tool"
    jarvis_key_gate tool
    expect_poll "the held action completes" none jarvis_key_state action
  fi
  jarvis_key_stop
  jarvis_key_stop_assertion
done
jarvis_bubble_console_hold
geometry expect_poll "a held request leaves the console's field and hint line whole" clear jarvis_bubble_console
jarvis_bubble_console_close
expect_poll "the client below Jarvis has keyboard focus again" '["smoke.other", "Other window"]' active_window

# The chained engine speaks its acknowledgement of "scripted utterance"
# before the reply, and the caption carries both.
jarvis_bubble_reply="On it. $("$node_bin" -e 'process.stdout.write(require(process.argv[1]).REPLY)' "$source_repo/scripts/fixtures/jarvis/scripted.js")" ||
  fail "the scripted reply is readable"
jarvis_bubble_begin
jarvis_key_gate partial
expect_poll "a partial leaves the utterance collecting" collecting jarvis_key_state turn
expect "the user's partial words are not drawn" absent jarvis_bubble_handed 'scripted draft'
jarvis_bubble_think
expect "the user's committed words are not drawn while the brain thinks" absent jarvis_bubble_handed 'scripted utterance'
expect_poll "Jarvis's acknowledgement draws while the brain thinks" "On it." jarvis_bubble_shown
expect_poll "thinking draws its own look" thinking jarvis_bubble_look
jarvis_bubble_user_caption
expect_poll "a caption of the user's words clears Jarvis's words" empty jarvis_bubble_handed
jarvis_key_gate reply
expect_poll "the reply draws the latest lines of Jarvis's words" latest-lines jarvis_bubble_words
jarvis_bubble_earlier="$(ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["transcript"]))')"
# Jarvis's words draw only while its voice is muted: the button turns the
# voice on and the words go, the key mutes it again and they return.
jarvis_bubble_click "Unmute Jarvis's voice"
expect_poll "the voice button turns Jarvis's voice on" off jarvis_key_state voiceMute
expect_poll "with its voice on, Jarvis's words are not drawn" absent jarvis_bubble_words
jarvis_bubble_voice_key
expect_poll "the Voice mute key mutes Jarvis's voice" on jarvis_key_state voiceMute
expect_poll "with its voice muted, Jarvis's words draw again" latest-lines jarvis_bubble_words
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_bubble_begin
jarvis_bubble_think caption
expect_poll "the bubble draws the latest three lines of Jarvis's words" latest-lines jarvis_bubble_words
expect "the worded bubble keeps its presented indicator" presented jarvis_bubble_state
geometry expect_poll "the worded bubble stays at bottom centre" bottom-centre jarvis_bubble_geometry
if ! words_box="$(jarvis_bubble_required_box Words visible true)"; then
  fail "the bubble's words target is unreadable: got $words_box"
  jarvis_bubble_abandon
  return 0
fi
read -r words_x words_y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(round(x+w/2),round(y+h/2))' "$words_box")
# Jarvis's words take the pointer while they show in an active state: a
# right click on them opens the Jarvis menu.
hover "$words_x" "$words_y" && right_click "$words_x" "$words_y" || fail "the right click on Jarvis's words is not delivered"
expect_poll "a right click on Jarvis's words opens the Jarvis menu" "[\"Unmute Jarvis's voice\", \"Mute microphone\", \"Stop Jarvis\", \"New conversation\", \"Hide Jarvis\", \"Key hints\"]" jarvis_bubble_menu
type_keys -k Escape || fail "Escape on the Jarvis menu over the words failed"
expect_poll "Escape closes the Jarvis menu over the words" "[]" jarvis_bubble_menu
rest_pointer || fail "the pointer returns to rest after the words' menu"
# Motion uses the active reply, the open quiet conversation and a fault.
# Motion scale 0 must still the same fault look.
expect_poll "the reply speaks behind the played gate" speaking jarvis_key_state phase
expect_poll "speaking draws its own look" speaking jarvis_bubble_look
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect_poll "speaking swaps frames" advancing jarvis_bubble_advancing
jarvis_bubble_rate="$(jarvis_bubble_look_value state.idle.frameRate)" || fail "the waiting look's frame rate is unreadable"
expect "control: speaking swaps faster than the waiting look's rate" unpaced jarvis_bubble_paced "$jarvis_bubble_rate"
jarvis_key_stop
jarvis_key_stop_assertion
expect_poll "the open conversation keeps its bubble" presented jarvis_bubble_state
expect_poll "the quiet conversation draws the idle look" idle jarvis_bubble_look
expect "observe the quiet conversation's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect_poll "the quiet orb swaps frames" advancing jarvis_bubble_advancing
expect "the quiet orb swaps at most its look's rate" paced jarvis_bubble_paced "$jarvis_bubble_rate"
jarvis_bubble_begin
jarvis_key_gate device-lost
expect_poll "device loss shows the fault" retrying jarvis_key_state fault
expect_poll "the fault draws the error look" error jarvis_bubble_look
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect_poll "the fault's orb swaps frames" advancing jarvis_bubble_advancing
expect "control: the quiet wait reads the moving fault's orb as swapped" swapped jarvis_bubble_still
# Motion scale 0 stills every state: the same reading over the same look
# swaps nothing, the planted still state the readings above must tell
# from a moving one.
jarvis_bubble_motion="$(ipc smoke themeValue motion.scale)" || fail "the theme's motion scale is unreadable before the motion-off reading"
jarvis_bubble_had_theme=false
if [[ -f ${home:?}/.config/vgshell/theme.json ]]; then
  cp -- "${home:?}/.config/vgshell/theme.json" "$sandbox/jarvis-bubble-theme.json"
  jarvis_bubble_had_theme=true
fi
printf '%s\n' '{"schemaVersion":1,"name":"jarvis-bubble-motion-off","tokens":{"motion":{"scale":0}}}' >"${home:?}/.config/vgshell/theme.json.tmp"
mv -T -- "${home:?}/.config/vgshell/theme.json.tmp" "${home:?}/.config/vgshell/theme.json"
expect_poll "the theme stills motion for the motion-off reading" 0 ipc smoke themeValue motion.scale
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect "control: at motion scale 0 the fault's orb swaps no frame over 3 s" quiet jarvis_bubble_still
expect "control: at motion scale 0 the advancing reader reads stopped over the fault's look" stopped jarvis_bubble_advancing
expect "control: a redraw after the quiet wait fails the same still reader" swapped jarvis_bubble_still jarvis_bubble_flip_mode
if [[ $jarvis_bubble_had_theme == true ]]; then
  cp -- "$sandbox/jarvis-bubble-theme.json" "${home:?}/.config/vgshell/theme.json.tmp"
  mv -T -- "${home:?}/.config/vgshell/theme.json.tmp" "${home:?}/.config/vgshell/theme.json"
else
  rm -f -- "${home:?}/.config/vgshell/theme.json"
fi
expect_poll "the theme's motion returns after the motion-off reading" "$jarvis_bubble_motion" ipc smoke themeValue motion.scale
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_key_gate device-back
jarvis_key_talk_up
rm -f -- "${jarvis_key_gates:?}/device-gone" "${jarvis_key_gates:?}/device-back"
jarvis_bubble_begin
# One long request: the scripted brain states a step at once, a second step
# behind its gate and the answer behind the reply gate. Each line's playback
# ends at the played gate. The first step waits for the engine's progress
# threshold, so it polls past it; a step is spoken once, and the answer
# follows the lines.
said_from="$(jarvis_bubble_said count)"
touch "$jarvis_key_gates/long-request"
jarvis_bubble_think
expect_poll "a long Jarvis request speaks its acknowledgement at once" ack jarvis_bubble_said "$said_from"
jarvis_key_gate played
expect_poll "past the threshold the long request speaks its stated step" ack,step1 jarvis_bubble_said "$said_from"
jarvis_key_gate second-step
jarvis_key_gate played
expect_poll "a changed step is spoken once" ack,step1,step2 jarvis_bubble_said "$said_from"
jarvis_key_gate reply
jarvis_key_gate played
expect_poll "the answer follows the progress lines with no line repeated" ack,step1,step2,answer jarvis_bubble_said "$said_from"
rm -f -- "${jarvis_key_gates:?}/long-request"
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_bubble_begin
jarvis_bubble_think
jarvis_bubble_old_caption
expect "the status still holds the ended conversation's caption" stale jarvis_bubble_caption
expect "a new conversation draws none of the last one's words" absent jarvis_bubble_words
jarvis_key_stop
jarvis_key_stop_assertion

jarvis_bubble_begin
jarvis_bubble_launcher="$(ipc smoke jarvisProcess | jarvis_launcher_pid)" || exit 1
jarvis_bubble_daemon="$(jarvis_descendants "$jarvis_bubble_launcher")" || exit 1
kill -KILL "$jarvis_bubble_daemon"
expect_poll "daemon death immediately removes its listening visual" 0 layer_count vgs:layer
expect "the service recovers through its existing allowance" ready jarvis_wait_ready 1
expect_poll "the recovered daemon has no capture demand" closed jarvis_key_state capture
jarvis_key_talk_up
jarvis_key_stop
jarvis_disable
jarvis_enable

jarvis_bubble_begin
jarvis_bubble_lua="$home/.config/hypr/hyprland.lua"
cp -- "$jarvis_bubble_lua" "$jarvis_bubble_snapshots/focus.next"
mv -T -- "$jarvis_bubble_snapshots/focus.next" "$jarvis_bubble_snapshots/focus"
jarvis_bubble_first="$(hypr -j monitors | py_reply 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))')"
printf '%s\n' 'hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true }, misc = { mouse_move_focuses_monitor = false } })' >>"$jarvis_bubble_lua"
expect "the nested configuration holds monitor focus" ok hypr reload config-only
expect "the nested compositor adds another focus target" ok create_output SMOKE-JARVIS
jarvis_bubble_focus_output=true
expect "the physical-key fixture focuses the other monitor" ok probe dispatch "focusMonitor SMOKE-JARVIS"
expect_poll "the service observes the other focused output" '"SMOKE-JARVIS"' ipc smoke readInstance service vgs.jarvis focusedOutput
expect_poll "only the focused output requests a bubble" focused jarvis_bubble_focused
expect "focus returns to the original monitor" ok probe dispatch "focusMonitor $jarvis_bubble_first"
expect_poll "the service observes restored monitor focus" "\"$jarvis_bubble_first\"" ipc smoke readInstance service vgs.jarvis focusedOutput
expect_poll "the restored focused output owns the visual" focused jarvis_bubble_focused

# Give this fixture a real widget only on the first output. Core still
# owns its frame observation; neither Service nor Session is patched.
jarvis_key_talk_up
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_disable
cp -- "$repo/shell/plugins/vgs.jarvis/Widget.qml" "$jarvis_bubble_snapshots/widget"
python3 - "$repo/shell/plugins/vgs.jarvis/Widget.qml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='    id: root'
assert s.count(needle)==1
# Plugins.createWidget hands the widget its actual owning bar, whose
# screen is assigned by the core. This fixture hides only one copy.
changed=s.replace(needle, needle+'\n    visible: bar === null || bar.screen === null || bar.screen.name !== "SMOKE-JARVIS"')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect "the indicator fixture places the real Jarvis widget" ok ipc shell setPluginPlaced vgs.jarvis true
expect_poll "the focused host completes the widget frame before Hide" present jarvis_bubble_bar_frame present
expect "the placed widget's bar hides before the refusal check" ok ipc vgs.bar invoke hide ''
expect_poll "an unmapped bar withdraws the placed widget's observation" gone jarvis_key_state barIndicator
expect "the hidden bar retains the actual widget instance" '"vgs.jarvis"' ipc smoke readInstance "bar:$jarvis_bubble_first" vgs.jarvis moduleName
expect_poll "Hide explains why a built but unmapped widget is insufficient" blocked jarvis_bubble_hide_blocked
expect "Hide refuses a built but unmapped bar widget" 'refused: hide=indicator' ipc vgs.jarvis invoke hide ''
expect "the refusal keeps the shown choice" shown jarvis_key_state visibility
expect "the placed widget's bar reveals after the refusal check" ok ipc vgs.bar invoke reveal ''
expect_poll "the focused host completes the revealed widget frame" present jarvis_bubble_bar_frame present
jarvis_bubble_begin
expect_poll "the focused host completes the listening badge before Hide" listening jarvis_bubble_bar_frame listening
jarvis_bubble_before="$(jarvis_key_received count)"
jarvis_bubble_menu_choose "Hide Jarvis" || fail "the overlay Hide menu action is delivered"
expect_poll "the overlay Hide route stores the hidden choice" hidden jarvis_key_state visibility
expect "the overlay menu sends only the direct Hide intent" '["hide"]' jarvis_key_received "$jarvis_bubble_before"
expect_poll "hidden listening keeps the real focused badge" listening jarvis_bubble_bar_frame listening
expect_poll "Hide withdraws the orb observation" gone jarvis_key_state indicator
expect_poll "Hide leaves capture open behind that badge" open jarvis_key_state capture
expect_poll "hidden listening removes orb, words, controls and field" quiet jarvis_bubble_hidden quiet
jarvis_key_talk_up
jarvis_key_stop
jarvis_key_stop_assertion
expect "Stop keeps the hidden choice" hidden jarvis_key_state visibility

# Bootstrap with capture closed and an unmapped bar. Demand must draw the
# listening dot without a microphone, then the host's swap admits capture.
expect "the bar hides before hidden capture is requested" ok ipc vgs.bar invoke hide ''
expect_poll "the hidden bar withdraws its observation" gone jarvis_key_state barIndicator
jarvis_bubble_initial_opens="$(jarvis_key_effects capture-open)"
jarvis_key_talk_down
expect_poll "hidden demand selects the listening badge before capture" '"success"' ipc smoke readDescendant "bar:$jarvis_bubble_first" vgs.jarvis BarItem stateDot
expect "an unmapped badge opens no microphone" closed jarvis_key_state capture
expect "capture has not reached its scripted open port" "$jarvis_bubble_initial_opens" jarvis_key_effects capture-open
expect "the unmapped bar reveals without changing Jarvis's choice" ok ipc vgs.bar invoke reveal ''
expect_poll "the real focused listening frame reaches the service" listening jarvis_bubble_bar_frame listening
expect_poll "that frame admits hidden capture" open jarvis_key_state capture
expect "the admitted port observes the same generation's badge first" framed-before-open jarvis_bubble_hidden_opens

# Returning a badge cannot bypass an outstanding close acknowledgment.
jarvis_key_gate hold-close
jarvis_key_gate silent-capture
expect "removing the actual widget withdraws the hidden indicator" ok ipc shell setPluginPlaced vgs.jarvis false
expect_poll "widget removal starts resource retirement" closing jarvis_key_state capture
expect_poll "widget removal reaches Session as gone" gone jarvis_key_state barIndicator
jarvis_bubble_initial_opens="$(jarvis_key_effects capture-open)"
expect "the widget returns while the old resource is retiring" ok ipc shell setPluginPlaced vgs.jarvis true
expect_poll "the returned widget completes a listening frame" listening jarvis_bubble_bar_frame listening
expect "a returned frame cannot bypass close acknowledgment" closing jarvis_key_state capture
expect "a returned frame starts no replacement capture early" "$jarvis_bubble_initial_opens" jarvis_key_effects capture-open
jarvis_key_gate close
expect_poll "matching close acknowledgment permits replacement capture" open jarvis_key_state capture
expect "only one replacement reaches the capture port" "$((jarvis_bubble_initial_opens + 1))" jarvis_key_effects capture-open
rm -f -- "$jarvis_key_gates/hold-close"
jarvis_key_gate silent-capture
expect "the mapped bar hides during hidden capture" ok ipc vgs.bar invoke hide ''
jarvis_bubble_hidden_loss
expect "the bar reveals after hidden capture withdrawal" ok ipc vgs.bar invoke reveal ''
expect_poll "the revealed host presents the listening badge" listening jarvis_bubble_bar_frame listening
expect_poll "the revealed badge permits capture again" open jarvis_key_state capture

jarvis_key_gate silent-capture
expect "focus leaves the only presented Jarvis widget" ok probe dispatch "focusMonitor SMOKE-JARVIS"
expect_poll "Service observes focus on the widgetless output" '"SMOKE-JARVIS"' ipc smoke readInstance service vgs.jarvis focusedOutput
expect_poll "the original output still presents the actual listening badge" other-output jarvis_bubble_bar_frame other-output
jarvis_bubble_hidden_loss
expect "focus returns to the presented badge" ok probe dispatch "focusMonitor $jarvis_bubble_first"
expect_poll "the focused badge permits capture after output mismatch" open jarvis_key_state capture
jarvis_key_gate silent-capture
expect "removing the widget again leaves Show as a recovery route" ok ipc shell setPluginPlaced vgs.jarvis false
jarvis_bubble_hidden_loss
expect "Show needs no bar widget" ok ipc vgs.jarvis invoke show ''
expect_poll "Show restores the orb's own host presentation" presented jarvis_bubble_state
expect_poll "Show restores orb capture admission without a widget" open jarvis_key_state capture
expect "Show keeps the independent voice mute" on jarvis_key_state voiceMute
jarvis_key_talk_up
jarvis_key_stop
jarvis_key_stop_assertion

# The retained required content uses the same approval/frame and menu
# routes, but never substitutes for the hidden capture indicator.
expect "the widget returns for another explicit Hide" ok ipc shell setPluginPlaced vgs.jarvis true
expect_poll "the idle widget has a presented frame" present jarvis_bubble_bar_frame present
jarvis_bubble_menu_choose "Hide Jarvis" || fail "the second overlay Hide reaches its owner"
jarvis_bubble_approval action
expect_poll "the hidden held request receives its real frame acknowledgment" drawn jarvis_bubble_acknowledged
expect_poll "the hidden held request keeps only required content" required jarvis_bubble_hidden required
expect "the hidden hold retains its typed call and ordered answer buttons" 1 jarvis_bubble_request
jarvis_bubble_before="$(jarvis_key_effects approval-ended)"
jarvis_bubble_accept Cancel approval-ended "$((jarvis_bubble_before + 1))"
expect_poll "answering the hidden hold removes its required content" quiet jarvis_bubble_hidden quiet
expect "answering the hidden hold never shows the orb" hidden jarvis_key_state visibility
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_bubble_begin
jarvis_bubble_before="$(jarvis_key_effects playback-start)"
jarvis_bubble_think caption
expect_poll "hidden Jarvis still reaches reply playback" speaking jarvis_key_state phase
expect_poll "the hidden reply reaches the scripted playback port" "$((jarvis_bubble_before + 1))" jarvis_key_effects playback-start
expect "hidden speaking keeps independent voice mute" on jarvis_key_state voiceMute
expect_poll "an assistant caption and playback draw no hidden words or orb" quiet jarvis_bubble_hidden quiet
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_bubble_begin
jarvis_key_gate device-lost
expect_poll "hidden device loss enters the real retry fault" retrying jarvis_key_state fault
expect_poll "the hidden fault keeps its required text and field" required jarvis_bubble_hidden required
jarvis_bubble_before="$(jarvis_key_received count)"
jarvis_bubble_menu_choose "Show Jarvis" Label role bodyStrong || fail "the hidden fault's menu Show is delivered"
expect_poll "Show from the required fault restores the orb choice" shown jarvis_key_state visibility
expect "the hidden fault menu sends only the direct Show intent" '["show"]' jarvis_key_received "$jarvis_bubble_before"
expect_poll "Show restores the fault's orb" error jarvis_bubble_look
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_key_gate device-back
jarvis_key_talk_up
rm -f -- "$jarvis_key_gates/device-gone" "$jarvis_key_gates/device-back"
expect "every hidden capture opened behind its own listening frame" framed-before-open jarvis_bubble_hidden_opens
jarvis_disable
cp -- "$jarvis_bubble_snapshots/widget" "$repo/shell/plugins/vgs.jarvis/Widget.qml"
jarvis_rescan
jarvis_enable
expect "the visible-orb controls start without a bar widget" ok ipc shell setPluginPlaced vgs.jarvis false
expect "the hidden scenario leaves the persisted choice shown" shown jarvis_key_state visibility
expect "the nested compositor removes the focus target" ok hypr output remove SMOKE-JARVIS
jarvis_bubble_focus_output=false
cp -- "$jarvis_bubble_snapshots/focus" "$jarvis_bubble_lua"
expect "the nested pointer configuration is restored" ok hypr reload config-only
jarvis_key_talk_up
jarvis_key_stop

jarvis_bubble_begin
expect "losing the mapped host hides the indicator" ok ipc smoke layerWindowSet vgs.jarvis visible false
jarvis_bubble_no_capture
jarvis_key_talk_up
jarvis_key_stop
jarvis_disable
expect_poll "disable destroys the bubble registration" '[]' ipc smoke layerWindows vgs.jarvis
jarvis_enable
jarvis_bubble_begin
expect "a screen loss reaches the content binding" ok ipc smoke layerWindowSet vgs.jarvis screen false
jarvis_bubble_no_capture
expect_poll "no screen maps no bubble surface" 0 layer_count vgs:layer
jarvis_key_talk_up
jarvis_key_stop
jarvis_disable

# Retain the actual host and key. Ignore only mapping/presentation in a
# disposable plugin copy; the same lost-host assertion must turn red. The
# words controls keep the caption on the wire and break one bubble rule each.
jarvis_bubble_file="$repo/shell/plugins/vgs.jarvis/Bubble.qml"
cp -- "$jarvis_bubble_file" "$jarvis_bubble_snapshots/bubble.next"
mv -T -- "$jarvis_bubble_snapshots/bubble.next" "$jarvis_bubble_snapshots/bubble"
jarvis_bubble_words_file="$repo/shell/plugins/vgs.jarvis/Words.qml"
cp -- "$jarvis_bubble_words_file" "$jarvis_bubble_snapshots/words.next"
mv -T -- "$jarvis_bubble_snapshots/words.next" "$jarvis_bubble_snapshots/words"
jarvis_bubble_orb_file="$repo/shell/plugins/vgs.jarvis/ParticleOrb.qml"
cp -- "$jarvis_bubble_orb_file" "$jarvis_bubble_snapshots/orb.next"
mv -T -- "$jarvis_bubble_snapshots/orb.next" "$jarvis_bubble_snapshots/orb"
# Row.layoutDirection reverses rendered positions (Qt Quick Row reference).
# The position reader must reject that reversal, regardless of button copy.
jarvis_bubble_fixture="$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
cp -- "$jarvis_bubble_fixture" "$jarvis_bubble_snapshots/fixture.next"
mv -T -- "$jarvis_bubble_snapshots/fixture.next" "$jarvis_bubble_snapshots/fixture"
for jarvis_bubble_mutant in geometry console console-close focus words role lines head generation look approval-key approval-button approval-cancel approval-shown approval-caption approval-kind approval-path approval-role approval-order; do
  jarvis_bubble_mutation_file="$jarvis_bubble_file"
  if [[ $jarvis_bubble_mutant == lines || $jarvis_bubble_mutant == head ]]; then
    jarvis_bubble_mutation_file="$jarvis_bubble_words_file"
  fi
  [[ $jarvis_bubble_mutant != look ]] || jarvis_bubble_mutation_file="$jarvis_bubble_orb_file"
  if [[ $jarvis_bubble_mutant == approval-key || $jarvis_bubble_mutant == approval-shown || $jarvis_bubble_mutant == console-close ]]; then
    jarvis_bubble_mutation_file="$jarvis_key_service"
  fi
  if [[ $jarvis_bubble_mutant == approval-kind || $jarvis_bubble_mutant == approval-path ]]; then
    jarvis_bubble_mutation_file="$jarvis_bubble_fixture"
  fi
  python3 - "$jarvis_bubble_mutation_file" "$jarvis_bubble_mutant" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
needle,replacement={
    "geometry": ("anchors.bottomMargin: root.look.layout.margin", "anchors.bottomMargin: root.look.layout.margin + root.look.layout.gap"),
    "console": ("when: root.overConsole", "when: false"),
    "console-close": ('event.name === "closewindow" || ', ""),
    "focus": ("screen.name === service.focusedOutput", "true"),
    "words": ('caption !== null && caption.role', "false && caption.role"),
    "role": ('&& caption.role === "assistant" &&', "&&"),
    "lines": ("readonly property int window: look.words.lines", "readonly property int window: look.words.lines + 1"),
    "head": ("y: (root.window - 1 - index) * root.lineBox + root.lift", "y: index * root.lineBox + root.lift"),
    "generation": ("caption.gen === state.gen", "true"),
    "look": ("readonly property var tone: look.state[phase]", "readonly property var tone: look.state.idle"),
    "approval-key": ('() => confirmApproval(displayedApproval(), "key")', '() => {}'),
    "approval-button": ('root.service.confirmApproval(root.displayedHold, "button")', 'void root.displayedHold'),
    "approval-cancel": ('root.service.cancelApproval(root.displayedHold)', 'void root.displayedHold'),
    "approval-shown": ('send({ type: "shown", id: hold.id });', 'void hold;'),
    "approval-caption": ('|| root.hold !== null ? ""', '? ""'),
    "approval-kind": ('id: "files.delete", args:', 'id: "files.read", args:'),
    "approval-path": ('path: "/home/fixture/draft.txt"', 'path: "/home/fixture/other.txt"'),
    "approval-role": ('variant: bare ? "ghost" : "secondary"', 'variant: bare ? "secondary" : "ghost"'),
    "approval-order": ('id: answerButtons', 'id: answerButtons\n                    layoutDirection: Qt.RightToLeft')
}[sys.argv[2]]
s=p.read_text(); assert s.count(needle)==1
changed=s.replace(needle,replacement); assert changed!=s
p.write_text(changed)
PY
  jarvis_rescan
  jarvis_enable
  case "$jarvis_bubble_mutant" in
    console)
      jarvis_bubble_console_hold
      geometry expect_poll "control: today's bottom placement fails the same console reader" overlap jarvis_bubble_console
      jarvis_bubble_console_close
      jarvis_disable
      cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
      continue ;;
    console-close)
      jarvis_bubble_console_hold
      geometry expect_poll "control: the held request over the console takes the top" clear jarvis_bubble_console
      jarvis_bubble_console_unmap
      jarvis_bubble_failures="$(
        failures=0 behaviour_failures=0
        jarvis_bubble_console_return >"$sandbox/$jarvis_bubble_mutant.log"
        echo "$failures"
      )"
      expect "control: ignoring the close event fails the same return check" 1 printf '%s\n' "$jarvis_bubble_failures"
      jarvis_key_stop
      jarvis_key_stop_assertion
      jarvis_disable
      cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
      continue ;;
    approval-*)
      jarvis_bubble_approval action
      case "$jarvis_bubble_mutant" in
        approval-caption|approval-kind|approval-path|approval-role|approval-order)
          expect_poll "control: the held request frame is acknowledged" drawn jarvis_bubble_acknowledged
          # Words draw only under voice mute, so the caption control needs it.
          [[ $jarvis_bubble_mutant != approval-caption ]] ||
            expect "control: voice mute is on while the request is held" on jarvis_key_state voiceMute
          jarvis_bubble_failures="$(
            failures=0 behaviour_failures=0
            expect "the drawn hold binds its typed call and ordered button roles without a duplicate caption" 1 jarvis_bubble_request >"$sandbox/$jarvis_bubble_mutant.log"
            echo "$failures"
          )"
          expect "control: $jarvis_bubble_mutant fails the same held contract" 1 printf '%s\n' "$jarvis_bubble_failures" ;;
        approval-shown)
          jarvis_bubble_failures="$(
            failures=0 behaviour_failures=0
            expect_poll "the held request receives a drawn-frame acknowledgment" drawn jarvis_bubble_acknowledged >"$sandbox/$jarvis_bubble_mutant.log"
            echo "$failures"
          )"
          expect "control: a dropped acknowledgment fails the same presented-frame assertion" 1 printf '%s\n' "$jarvis_bubble_failures" ;;
        *)
          expect_poll "control: the retained frame acknowledgment reaches Session" drawn jarvis_bubble_acknowledged
          jarvis_bubble_before="$(jarvis_key_effects tool-start)"
          jarvis_bubble_answer=Confirm
          jarvis_bubble_effect=tool-start
          [[ $jarvis_bubble_mutant != approval-key ]] || jarvis_bubble_answer=key
          if [[ $jarvis_bubble_mutant == approval-cancel ]]; then
            jarvis_bubble_answer=Cancel
            jarvis_bubble_effect=approval-ended
            jarvis_bubble_before="$(jarvis_key_effects "$jarvis_bubble_effect")"
          fi
          jarvis_bubble_failures="$(
            failures=0 behaviour_failures=0
            jarvis_bubble_accept "$jarvis_bubble_answer" "$jarvis_bubble_effect" "$((jarvis_bubble_before + 1))" >"$sandbox/$jarvis_bubble_mutant.log"
            echo "$failures"
          )"
          expect "control: dropping the confirmation path fails the same approval assertion" 2 printf '%s\n' "$jarvis_bubble_failures" ;;
      esac
      jarvis_key_stop
      jarvis_disable
      cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
      cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
      cp -- "$jarvis_bubble_snapshots/fixture" "$jarvis_bubble_fixture"
      continue ;;
  esac
  jarvis_bubble_begin
  case "$jarvis_bubble_mutant" in
    geometry)
      expect "control: a wrong bottom margin fails the same geometry reader" wrong-geometry jarvis_bubble_geometry
      jarvis_key_talk_up ;;
    focus)
      expect "control: add another output without changing focus" ok create_output SMOKE-JARVIS
      jarvis_bubble_focus_output=true
      expect_poll "control: ignoring focus fails the same output reader" wrong-output jarvis_bubble_focused
      expect "control: remove the second output" ok hypr output remove SMOKE-JARVIS
      jarvis_bubble_focus_output=false
      jarvis_key_talk_up ;;
    words)
      jarvis_bubble_think caption
      expect "control: dropping the consumer fails the same words reader" absent jarvis_bubble_words ;;
    role)
      jarvis_bubble_think
      expect_poll "control: the acknowledgement draws" "On it." jarvis_bubble_shown
      jarvis_bubble_user_caption
      jarvis_bubble_failures="$(
        failures=0 behaviour_failures=0
        expect_poll "a caption of the user's words clears Jarvis's words" empty jarvis_bubble_handed >"$sandbox/$jarvis_bubble_mutant.log"
        echo "$failures"
      )"
      expect "control: dropping the role check fails the same words assertion" 1 printf '%s\n' "$jarvis_bubble_failures" ;;
    look)
      jarvis_bubble_failures="$(
        failures=0 behaviour_failures=0
        expect_poll "listening draws its own look" listening jarvis_bubble_look >"$sandbox/$jarvis_bubble_mutant.log"
        echo "$failures"
      )"
      expect "control: a look bound to another state fails the same look reader" 1 printf '%s\n' "$jarvis_bubble_failures"
      jarvis_key_talk_up ;;
    lines)
      jarvis_bubble_think caption
      expect_poll "control: a fourth line fails the same words reader" unbounded jarvis_bubble_words ;;
    head)
      jarvis_bubble_think caption
      expect_poll "control: the newest line on top fails the same words reader" wrong-order jarvis_bubble_words ;;
    generation)
      jarvis_bubble_think caption
      jarvis_bubble_earlier="$(ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["transcript"]))')"
      jarvis_key_stop
      jarvis_key_stop_assertion
      jarvis_bubble_begin
      jarvis_bubble_think
      jarvis_bubble_old_caption
      expect_poll "control: ignoring the conversation fails the same words reader" latest-lines jarvis_bubble_words ;;
  esac
  jarvis_key_stop
  jarvis_disable
  cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
  cp -- "$jarvis_bubble_snapshots/words" "$jarvis_bubble_words_file"
  cp -- "$jarvis_bubble_snapshots/orb" "$jarvis_bubble_orb_file"
done
# Restore the independent bindings in one disposable source copy. Clearing
# its hold must make the shell log check fail. Only that copy's source URI
# is excused after the control; the normal bubble remains subject to the row.
check_unexpected_log "the bubble before the binding control" "$instance_log"
python3 - "$jarvis_bubble_file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text()
edits=[
    ('readonly property var prompt: View.approvalPrompt(root.hold)', '''readonly property bool filePrompt: root.hold !== null && root.hold.purpose === "action"
                    && (root.hold.tool === "apps.open" || root.hold.tool.startsWith("files.") || root.hold.tool === "harness.files")
                readonly property var lines: root.hold === null ? [] : root.hold.text.split("\\n")'''),
    ('prompt !== null && prompt.filePrompt', 'filePrompt'),
    ('prompt.detail', 'lines.length > 2'),
    ('approvalText.prompt === null ? "" : approvalText.prompt.question', 'approvalText.filePrompt ? approvalText.lines[0] : root.hold === null ? "" : root.hold.text'),
    ('approvalText.prompt === null ? "" : approvalText.prompt.path', 'approvalText.filePrompt ? approvalText.lines[1] : ""'),
    ('approvalText.prompt === null ? "" : approvalText.prompt.payload', 'approvalText.filePrompt ? approvalText.lines.slice(2).join("\\n") : ""')]
for needle,replacement in edits:
    assert s.count(needle)==1
    s=s.replace(needle,replacement)
needle='visible: text !== ""'
assert s.count(needle)==2
s=s.replace(needle,'visible: approvalText.filePrompt && text !== ""')
assert s!=p.read_text()
p.write_text(s)
PY
jarvis_rescan
jarvis_enable
jarvis_bubble_approval action
expect_poll "control: the two-binding request is drawn" drawn jarvis_bubble_acknowledged
jarvis_key_stop
expect_poll "control: clearing the two-binding hold ends approval" none jarvis_key_state approval
unexpected_log_errors "$instance_log" >"$sandbox/jarvis-bubble-bindings-errors.log"
jarvis_bubble_warning_pattern() { # LOG
  python3 - "$1" <<'PY'
import re,sys
try:
    rows=open(sys.argv[1]).read().splitlines()
except OSError:
    print("unreadable"); sys.exit()
if not rows:
    print("missing"); sys.exit()
uris=[]
for row in rows:
    match=re.search(r' WARN scene: (file://[^ ]+/Bubble\.qml)\[[0-9]+:[0-9]+\]:',row)
    if not match:
        print("unexpected"); sys.exit()
    uris.append(match[1])
if len(set(uris))!=1:
    print("ambiguous"); sys.exit()
print(re.escape(uris[0])+r'\[[0-9]+:[0-9]+\]:')
PY
}
jarvis_bubble_control_pattern="$(jarvis_bubble_warning_pattern "$sandbox/jarvis-bubble-bindings-errors.log")"
if [[ $jarvis_bubble_control_pattern == file://* ]]; then
cp -- "$sandbox/jarvis-bubble-bindings-errors.log" "$sandbox/jarvis-bubble-unexpected.log"
printf '%s\n' ' WARN quickshell.hyprland.ipc: Got removal for monitor "SMOKE-VOICE" which was not previously tracked.' >>"$sandbox/jarvis-bubble-unexpected.log"
expect "control: an unrelated warning answers a state without raising" unexpected jarvis_bubble_warning_pattern "$sandbox/jarvis-bubble-unexpected.log"
# This reader consumes check_unexpected_log's failure block. Other
# other failures do not change whether it holds this copy's warning.
jarvis_bubble_binding_failure() { # DIAGNOSTICS_LOG WARNING_PATTERN
  python3 - "$1" "$2" <<'PYREAD'
from pathlib import Path
import re,sys
warning=re.compile(r" WARN scene: " + sys.argv[2])
failed=False
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("  FAIL  "): failed=True
    elif line.startswith(("  ok    ","  SKIP  ")): failed=False
    if failed and warning.search(line):
        print("rejected")
        break
else:
    print("missing")
PYREAD
}
jarvis_bubble_binding_dir="$(mktemp -d "$sandbox/jarvis-bubble-bindings.XXXXXX")"
(
  failures=0 behaviour_failures=0
  # Force an unrelated failure too. It must not change the binding verdict.
  first_bar_ms=$((first_bar_budget_ms + 1))
  first_bar_cpu_some_pct=0.0
  # The real row appends sampler output; keep this control's files private.
  sandbox="$jarvis_bubble_binding_dir"
  check_unexpected_log "shell log" "$instance_log"
  source "$repo/scripts/smoke/rows/diagnostics.sh"
) >"$jarvis_bubble_binding_dir/diagnostics.log"
expect "control: the two-binding warning is among the diagnostics failures" rejected jarvis_bubble_binding_failure "$jarvis_bubble_binding_dir/diagnostics.log" "$jarvis_bubble_control_pattern"
# Remove only the injected warning from the real diagnostic output. The
# same assertion must then fail despite the remaining unrelated failure.
python3 - "$jarvis_bubble_binding_dir/diagnostics.log" "$jarvis_bubble_binding_dir/no-binding.log" "$jarvis_bubble_control_pattern" <<'PYFILTER'
from pathlib import Path
import re,sys
source,target=map(Path,sys.argv[1:3])
warning=re.compile(r" WARN scene: " + sys.argv[3])
rows=source.read_text().splitlines(keepends=True)
kept=[row for row in rows if not warning.search(row)]
assert len(kept)<len(rows)
target.write_text("".join(kept))
PYFILTER
jarvis_bubble_binding_control="$(
  failures=0 behaviour_failures=0
  expect "the injected binding warning is rejected" rejected jarvis_bubble_binding_failure "$jarvis_bubble_binding_dir/no-binding.log" "$jarvis_bubble_control_pattern" >"$jarvis_bubble_binding_dir/missing-warning.log"
  echo "$failures"
)"
expect "control: unrelated failures cannot stand in for the binding warning" 1 printf '%s\n' "$jarvis_bubble_binding_control"
expected_errors+=("$jarvis_bubble_control_pattern")
else
  fail "the binding control warning pattern is $jarvis_bubble_control_pattern"
fi
jarvis_disable
cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
python3 - "$jarvis_bubble_file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text()
needle='shown && visible && host !== null && host.presented === true'
assert s.count(needle)==1
changed=s.replace(needle, 'shown')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
jarvis_bubble_begin
expect "control: the same host disappears after acquisition" ok ipc smoke layerWindowSet vgs.jarvis visible false
expect "control: ignoring presentation fails lost-host capture teardown" 2 jarvis_bubble_loss_control
jarvis_key_talk_up
jarvis_key_stop
jarvis_disable
rm -f -- "${home:?}/.local/state/vgshell/jarvis/voice-mute.json"
rm -f -- "${home:?}/.local/state/vgshell/jarvis/hidden.json"
cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
cp -- "$jarvis_bubble_snapshots/engine" "$jarvis_bubble_engine"
cp -- "$jarvis_bubble_snapshots/backend" "$jarvis_key_backend"
jarvis_rescan
jarvis_enable
jarvis_key_hold true
jarvis_bubble_close_client
jarvis_bubble_restore_probe
