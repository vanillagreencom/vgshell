# Runs inside jarvis-keys' private scripted ports and physical keyboard.
# Its engine copy selects the scripted chained plan, so each thinking turn
# runs through the real chained engine and its words are the engine's own
# captions. No real audio, provider, authentication or network runs.
# Presentation and state poll once per IPC round trip; no latency budget is
# claimed. The stillness reading counts the layer window's swapped frames
# over 3 s of real time after the look settles, its own control the
# speaking look in the same window, which must swap frames.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* shell/plugins/vgs.bar/* shell/Ui/controls/IconButton.qml shell/Ui/feedback/LinkText.qml shell/Core/Layers.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml scripts/smoke/toplevel/* scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/diagnostics.sh
set -euo pipefail
jarvis_bubble_snapshots="$(mktemp -d "$sandbox/jarvis-bubble-snapshots.XXXXXX")"
jarvis_bubble_row_config="$jarvis_bubble_snapshots/shell.json"
jarvis_bubble_focus_output=false
jarvis_bubble_client=""
jarvis_bubble_row_focus="$(hypr -j activewindow | py_reply 'import json,sys; print(json.load(sys.stdin).get("address", ""))')"
cp -p -- "$home/.config/vgshell/shell.json" "$jarvis_bubble_row_config"
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
  # Early geometry failure can leave the source snapshots unchanged.
  rescan "the bubble row rescans its restored sources"
  jarvis_enable
  jarvis_bubble_close_client
  if [[ -n $jarvis_bubble_row_focus ]]; then
    expect "the bubble row restores its previous focus" ok hypr dispatch "hl.dsp.focus({ window = \"address:$jarvis_bubble_row_focus\" })"
  fi
}
smoke_row_abandon=(jarvis_bubble_abandon)

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
# reveal has ended, longer than the look's line count, in exactly that many
# visible clipping windows inside it. `latest-lines` when the bottom window
# draws the text's last line, `wrong-order` otherwise; `progressing` while
# words still appear.
jarvis_bubble_words() {
  local views windows labels lines
  views="$(ipc smoke layerItems vgs.jarvis Words shown,settled,lineCount,visible)" &&
    windows="$(ipc smoke layerItems vgs.jarvis QQuickItem clip,visible)" &&
    labels="$(ipc smoke layerItems vgs.jarvis Label visible,lineCount)" || return 1
  [[ $views == \[* && $windows == \[* && $labels == \[* ]] || { printf 'jarvis-bubble: words-reader=unreadable views=%s windows=%s\n' "$views" "$windows" >&2; return 1; }
  if [[ $views == '[]' ]]; then echo absent; return; fi
  lines="$(jarvis_bubble_look_value words.lines)" || return 1
  python3 -c '
import json,sys
views,windows,labels=map(json.loads,sys.argv[1:4]); lines=int(json.loads(sys.argv[4])); text=" ".join(sys.argv[5].split())
shown=[(s,b,v) for s,b,v in views if v["visible"]]
if not shown: print("absent"); sys.exit()
if len(shown)!=1: print("unbounded"); sys.exit()
screen,(x,y,w,h),view=shown[0]
if not view["settled"] or view["shown"]!=text: print("progressing"); sys.exit()
held=[b for s,b,v in windows if s==screen and v["visible"] and v["clip"] and b[0]==x and b[2]==w and b[1]>=y and b[1]+b[3]<=y+h]
if view["lineCount"]<=lines or len(held)!=lines: print("unbounded"); sys.exit()
bottom=max(held,key=lambda b:b[1])
inside=[b for s,b,v in labels if s==screen and v["visible"] and b[0]==x and b[2]==w and b[1]<=bottom[1] and b[1]+b[3]>=bottom[1]+bottom[3]]
if len(inside)!=1: print("unbounded"); sys.exit()
print("latest-lines" if abs(inside[0][1]+inside[0][3]-bottom[1]-bottom[3])<=1 else "wrong-order")
' "$views" "$windows" "$labels" "$lines" "$jarvis_bubble_reply"
}
# The phase whose look the shown orb draws: the orb's phase once each
# palette uniform of its shader holds that phase's colour in the shipped
# table (Appearance.js, read through the shell's library loader), else the
# phase and the uniforms still easing toward it.
jarvis_bubble_look() {
  local orbs shaders
  orbs="$(ipc smoke layerItems vgs.jarvis ParticleOrb phase,active)" &&
    shaders="$(ipc smoke layerItems vgs.jarvis QQuickShaderEffect uTop,uUpper,uLower,uBottom,uCore,uHot)" || return 1
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
const easing = ["top", "upper", "lower", "bottom", "core", "hot"].filter(stop =>
    effects[0][2]["u" + stop[0].toUpperCase() + stop.slice(1)].toLowerCase().slice(-6) !== want[stop].value.toLowerCase().slice(1, 7));
console.log(easing.length === 0 ? orb.phase : orb.phase + ":easing=" + easing.join(","));
JS
}
# `quiet` when the Jarvis layer window the probe watches swaps no frame
# over 3 s, read after the look's transition and two frames at 60 Hz;
# `swapped` otherwise.
jarvis_bubble_still() {
  local transition before after
  transition="$(jarvis_bubble_look_value orb.transition)" || return 1
  sleep "$(python3 -c 'import sys; print((int(sys.argv[1]) + 34) / 1000)' "$transition")"
  before="$(ipc smoke layerFrames)" || return 1
  # The acceptance interval is a real 3 s presentation observation.
  sleep 3
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
  printf '        jarvis_layer_frames_before=%s after=%s interval_s=3\n' "$before" "$after" >&2
  if ((after == before)); then echo quiet; else echo swapped; fi
}
jarvis_bubble_voice_key() { hold_send "down 133" "down 64" "down 44" "up 44" "up 64" "up 133"; }
jarvis_bubble_buttons() { ipc smoke layerItemsWith vgs.jarvis IconButton label "$1"; }
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
jarvis_bubble_text() { # TEXT
  ipc smoke layerItems vgs.jarvis Label text,visible | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("drawn" if any(v["visible"] and v["text"]==sys.argv[1] and box[2]>0 and box[3]>0 for _,box,v in rows) else "absent")
' "$1"
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
jarvis_bubble_click() { # LABEL
  local point x y
  if ! point="$(point_item vgs:layer vgs.jarvis IconButton label "$1")"; then
    fail "the labelled $1 button reports hover before click"
    printf 'jarvis-bubble: pointer-not-ready=%s\n' "$1"
    ipc smoke layerItems vgs.jarvis IconButton label,hovered,visible >&2 || true
    ipc smoke layerWindows vgs.jarvis >&2 || true
    return 0
  fi
  read -r x y <<<"$point" || { fail "the labelled $1 button point is unreadable"; return 0; }
  click "$x" "$y" || fail "the labelled $1 button click is not delivered"
}
jarvis_bubble_begin() {
  jarvis_key_talk_down
  expect_poll "capture waits for the bubble then listens" listening jarvis_key_state phase
  expect_poll "the listening bubble has presented on its own host" presented jarvis_bubble_state
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
    buttons="$(ipc smoke layerItems vgs.jarvis Button variant,visible)" &&
    clips="$(ipc smoke layerItems vgs.jarvis Words visible,shown)" &&
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
    assert.deepEqual(buttons.map(([, , value]) => value.variant), ["secondary", "primary"]);
    const [left, right] = buttons.map(([, box]) => box);
    assert.ok(left[2] > 0 && right[2] > 0 && left[0] + left[2] < right[0]);
    assert.equal(left[1], right[1]);
    const labels = JSON.parse(rawFields);
    const fields = labels.filter(([, , value]) => value.visible);
    const questions = fields.filter(([, box, value]) => value.role === "body" && box[1] < left[1]);
    assert.equal(questions.length, 1);
    assert.ok(questions[0][1][2] > 0 && questions[0][1][3] > 0);
    if (held.purpose === "action") {
        const paths = fields.filter(([, box, value]) => value.role === "hint" && box[1] >= questions[0][1][1] + questions[0][1][3] && box[1] < left[1]);
        assert.ok(paths.length > 0);
        paths.sort((a, b) => a[1][1] - b[1][1]);
        assert.ok(paths[0][1][2] > 0 && paths[0][1][3] > 0);
    }
    // Jarvis's words, which voice mute draws above the orb, give way to
    // the held question: no Words view shows a word beside it.
    const captions = JSON.parse(rawClips).filter(([, , value]) => value.visible && value.shown !== "");
    assert.equal(captions.length, 0);
    console.log(1);
} catch (error) {
    if (!(error instanceof assert.AssertionError)) throw error;
    console.error("jarvis-bubble: held-contract=" + error.message);
    console.log(0);
}
JS
}
jarvis_bubble_confirm_key() {
  hold_send "down 133" "down 64" "down 29" "up 29" "up 64" "up 133"
  jarvis_key_state approval
}
jarvis_bubble_answer_button() { # BUTTON
  local point x y
  point="$(point_item vgs:layer vgs.jarvis Button variant "$([[ $1 == Cancel || $1 == No ]] && echo secondary || echo primary)")" || return 1
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
# the console's one TextField, read by its empty text: no draft is typed.
jarvis_bubble_console() {
  local field hint card output
  field="$(control_box window:Jarvis window vgs.jarvis TextField '')" &&
    hint="$(control_box window:Jarvis window vgs.jarvis Label 'Confirm or cancel the request first')" &&
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

if ! orb_box="$(jarvis_bubble_required_box ParticleOrb active true)" ||
   ! mute_box="$(jarvis_bubble_required_box IconButton label 'Mute microphone')" ||
   ! stop_box="$(jarvis_bubble_required_box IconButton label 'Stop Jarvis')"; then
  fail "the bubble's decorative targets are unreadable: orb=$orb_box mute=${mute_box-unread} stop=${stop_box-unread}"
  jarvis_bubble_abandon
  return 0
fi
read -r orb_x orb_y orb_w orb_h < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$orb_box")
read -r mute_x mute_y mute_w mute_h < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$mute_box")
# The orb's centre, its canvas left of the ring, and its canvas just above
# the icon row: none is an input item.
jarvis_bubble_pass "$((orb_x + orb_w / 2))" "$((orb_y + orb_h / 2))"
jarvis_bubble_pass "$((orb_x + orb_w / 20))" "$((orb_y + orb_h / 2))"
if ((mute_y - 6 > orb_y)); then
  jarvis_bubble_pass "$((mute_x + mute_w / 2))" "$((mute_y - 6))"
else
  fail "the orb's canvas reaches above the icon row: orb=$orb_box mute=$mute_box"
fi
expect "decorative clicks cannot mute" off jarvis_key_state mute
expect "decorative clicks keep capture live" open jarvis_key_state capture
jarvis_bubble_click "Stop Jarvis"
jarvis_key_talk_up
jarvis_key_stop_assertion
expect_poll "Stop removes the idle bubble" 0 layer_count vgs:layer

# The capture fake loses its device after opening, then holds the retry's
# open callback. The real daemon/Session owns the fault and cancellation.
for jarvis_bubble_stop_mode in hold toggle always; do
  for jarvis_bubble_stop_trigger in button key ipc; do
    jarvis_key_mode "$jarvis_bubble_stop_mode"
    jarvis_bubble_begin
    jarvis_key_gate device-lost
    expect_poll "device loss enters retry before $jarvis_bubble_stop_trigger Stop in $jarvis_bubble_stop_mode" retrying jarvis_key_state fault
    expect_poll "the retry card remains presented" presented jarvis_bubble_state
    case "$jarvis_bubble_stop_trigger" in
      button) jarvis_bubble_click "Stop Jarvis" ;;
      key) jarvis_key_stop ;;
      ipc) expect "Stop IPC is accepted during retry" ok ipc vgs.jarvis invoke stop '' ;;
    esac
    jarvis_key_stop_assertion
    expect_poll "Stop closes the retry card in $jarvis_bubble_stop_mode" 0 layer_count vgs:layer
    expect "Stop clears the retry fault" none jarvis_key_state fault
    jarvis_key_gate device-back
    expect "a late device callback cannot reopen capture" closed jarvis_key_state capture
    jarvis_key_talk_up
    rm -f -- "$jarvis_key_gates/device-gone" "$jarvis_key_gates/device-back"
  done
done
jarvis_key_mode hold
jarvis_bubble_begin
jarvis_bubble_click "Mute microphone"
expect_poll "the labelled Mute button turns privacy mute on" on jarvis_key_state mute
expect_poll "the Mute button closes capture before hiding" closed jarvis_key_state capture
jarvis_key_talk_up
jarvis_key_mute
expect_poll "explicit unmute does not restore capture" off jarvis_key_state mute
expect "unmute still leaves no capture" closed jarvis_key_state capture
# Voice mute stays on from here through the mutation controls, so Jarvis's
# words draw; the words section turns it off and on again.
jarvis_bubble_begin
jarvis_bubble_click "Mute Jarvis's voice"
expect_poll "the voice button mutes Jarvis's voice" on jarvis_key_state voiceMute
expect_poll "the voice button names its next action" 1 jarvis_bubble_buttons "Turn on Jarvis's voice"
expect "voice mute leaves the microphone on" off jarvis_key_state mute
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
  jarvis_bubble_accept "$jarvis_bubble_answer" "$jarvis_bubble_effect" "$((jarvis_bubble_before + 1))"
  jarvis_key_stop
  jarvis_key_stop_assertion
done
jarvis_bubble_console_hold
geometry expect_poll "a held request leaves the console's field and hint line whole" clear jarvis_bubble_console
jarvis_bubble_console_close
expect_poll "the client below Jarvis has keyboard focus again" '["smoke.other", "Other window"]' active_window

# The chained engine speaks its acknowledgement of "scripted utterance"
# before the reply, and the caption carries both.
jarvis_bubble_reply="$(python3 -c 'print("On it. " + " ".join(["scripted reply"] * 24))')"
jarvis_bubble_begin
jarvis_key_gate partial
expect_poll "a partial leaves the utterance collecting" collecting jarvis_key_state turn
expect "the user's words are not drawn" absent jarvis_bubble_text 'scripted draft'
jarvis_bubble_think
expect_poll "Jarvis's acknowledgement draws while the brain thinks" "On it." jarvis_bubble_shown
expect "the user's final words are not drawn" absent jarvis_bubble_text 'scripted draft'
jarvis_key_gate reply
expect_poll "the reply draws the latest lines of Jarvis's words" latest-lines jarvis_bubble_words
jarvis_bubble_earlier="$(ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["transcript"]))')"
# Jarvis's words draw only while its voice is muted: the button turns the
# voice on and the words go, the key mutes it again and they return.
jarvis_bubble_click "Turn on Jarvis's voice"
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
jarvis_bubble_pass "$words_x" "$words_y"
# Stillness. The reply speaks behind the played gate: its look has a clock
# of its own, so the layer window swaps frames, the control for the
# readings below in the same window. Each look a phase with no deadline
# draws then stands still once its transition ends. Muting shows only
# while capture closes, after which the bubble unmaps, so no reading holds
# it for 3 s; scripts/qml-tests/tst_jarvis_orb.qml pins that its look has
# no clock.
expect_poll "the reply speaks behind the played gate" speaking jarvis_key_state phase
expect_poll "speaking draws its own look" speaking jarvis_bubble_look
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect "control: speaking swaps frames in the window the stillness readings use" swapped jarvis_bubble_still
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_key_mode always
expect_poll "Always mode waits for the word" armed jarvis_key_state phase
expect_poll "the waiting bubble has presented on its own host" presented jarvis_bubble_state
expect_poll "waiting draws the armed look" armed jarvis_bubble_look
expect "the waiting bubble shows no words" none jarvis_bubble_shown
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect "the waiting orb swaps no frame over 3 s" quiet jarvis_bubble_still
jarvis_key_mode hold
expect_poll "Hold mode ends the wait" 0 layer_count vgs:layer
jarvis_bubble_begin
jarvis_key_gate device-lost
expect_poll "device loss shows the fault" retrying jarvis_key_state fault
expect_poll "the fault draws the error look" error jarvis_bubble_look
expect "observe the Jarvis layer's own window" ok ipc smoke watchLayerFrames vgs.jarvis
expect "the fault's orb swaps no frame over 3 s" quiet jarvis_bubble_still
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
expect "the nested compositor removes the focus target" ok hypr output remove SMOKE-JARVIS
jarvis_bubble_focus_output=false
cp -- "$jarvis_bubble_snapshots/focus" "$jarvis_bubble_lua"
expect "the nested pointer configuration is restored" ok hypr reload config-only
jarvis_key_talk_up
jarvis_key_stop
jarvis_key_stop_assertion

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
# Row.layoutDirection reverses rendered positions (Qt Quick Row reference).
# The position reader must reject that reversal, regardless of button copy.
jarvis_bubble_fixture="$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
cp -- "$jarvis_bubble_fixture" "$jarvis_bubble_snapshots/fixture.next"
mv -T -- "$jarvis_bubble_snapshots/fixture.next" "$jarvis_bubble_snapshots/fixture"
for jarvis_bubble_mutant in geometry console console-close focus words lines head generation approval-key approval-button approval-cancel approval-shown approval-caption approval-kind approval-path approval-role approval-order; do
  jarvis_bubble_mutation_file="$jarvis_bubble_file"
  if [[ $jarvis_bubble_mutant == lines || $jarvis_bubble_mutant == head ]]; then
    jarvis_bubble_mutation_file="$jarvis_bubble_words_file"
  fi
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
    "words": ('caption !== null && caption.gen', "false && caption.gen"),
    "lines": ("model: root.look.words.lines", "model: root.look.words.lines + 1"),
    "head": ("y: (last - index) * root.lineBox", "y: index * root.lineBox"),
    "generation": ("caption.gen === state.gen", "true"),
    "approval-key": ('() => confirmApproval(displayedApproval(), "key")', '() => {}'),
    "approval-button": ('root.service.confirmApproval(root.displayedHold, "button")', 'void root.displayedHold'),
    "approval-cancel": ('root.service.cancelApproval(root.displayedHold)', 'void root.displayedHold'),
    "approval-shown": ('send({ type: "shown", id: hold.id });', 'void hold;'),
    "approval-caption": ('|| root.hold !== null || phase === "armed" ? ""', '|| phase === "armed" ? ""'),
    "approval-kind": ('id: "files.delete", args:', 'id: "files.read", args:'),
    "approval-path": ('path: "/home/fixture/draft.txt"', 'path: "/home/fixture/other.txt"'),
    "approval-role": ('variant: "secondary"', 'variant: "primary"'),
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
cp -- "$jarvis_bubble_snapshots/bubble" "$jarvis_bubble_file"
cp -- "$jarvis_bubble_snapshots/engine" "$jarvis_bubble_engine"
cp -- "$jarvis_bubble_snapshots/backend" "$jarvis_key_backend"
jarvis_rescan
jarvis_enable
jarvis_key_mode hold
jarvis_bubble_close_client
