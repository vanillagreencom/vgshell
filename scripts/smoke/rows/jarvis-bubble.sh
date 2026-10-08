# Runs inside jarvis-keys' private scripted ports and physical keyboard.
# Its engine copy selects the scripted chained plan, so each thinking turn
# runs through the real chained engine and its words are the engine's own
# captions. No real audio, provider, authentication or network runs.
# Presentation and state poll once per IPC round trip; no latency budget is
# claimed.
# inputs: shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* shell/plugins/vgs.bar/* shell/Ui/feedback/VoiceOrb.qml shell/Core/Layers.qml scripts/smoke/toplevel/* scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/diagnostics.sh
set -euo pipefail

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
jarvis_bubble_geometry() {
  local box window margin
  box="$(control_box vgs:layer vgs.jarvis Surface level raised)" &&
    window="$(surface_box vgs:layer)" &&
    margin="$(ipc smoke themeValue voiceBubble.margin)" || return 1
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
jarvis_bubble_pixels() {
  local box colour socket geometry count
  box="$(control_box vgs:layer vgs.jarvis VoiceOrb active true)" &&
    colour="$(ipc smoke themeValue voiceOrb.tone.accent | py_reply 'import json,sys; print(json.load(sys.stdin)[-6:])')" &&
    socket="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")" || return 1
  [[ $box == \[* ]] || { echo absent; return; }
  geometry="$(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print("%d,%d %dx%d"%(x,y,w,h))' "$box")" || return 1
  count="$(shot_grim "$socket" "$rt_dir" -g "$geometry" -t ppm - | python3 -c '
import sys
d=sys.stdin.buffer.read().split(b"\n",3)
if len(d)!=4 or d[0]!=b"P6" or d[2]!=b"255": sys.exit("jarvis-bubble: pixels=unreadable")
w,h=map(int,d[1].split()); pixels=d[3]
if len(pixels)!=w*h*3: sys.exit("jarvis-bubble: pixels=incomplete")
c=bytes.fromhex(sys.argv[1])
print(sum(pixels[i:i+3]==c for i in range(0,len(pixels),3)))
' "$colour")" || return 1
  [[ $count =~ ^[0-9]+$ ]] || return 1
  [[ $count -gt 0 ]] && echo drawn || echo blank
}
# The fixture's assistant caption as the bubble draws it: one visible label
# holding the whole text, longer than the token's three lines, inside one
# clipping window of exactly that height. The label's bottom on the window's
# bottom draws the text's end; its top on the window's top draws its start.
jarvis_bubble_words() {
  local labels windows lines
  labels="$(ipc smoke layerItems vgs.jarvis Label text,visible,lineCount,lineBox)" &&
    windows="$(ipc smoke layerItems vgs.jarvis QQuickItem clip,visible)" &&
    lines="$(ipc smoke themeValue voiceBubble.textLines)" || return 1
  [[ $labels == \[* && $windows == \[* ]] || { printf 'jarvis-bubble: words-reader=unreadable labels=%s windows=%s\n' "$labels" "$windows" >&2; return 1; }
  python3 -c '
import json,sys
labels,windows=map(json.loads,sys.argv[1:3]); lines=int(sys.argv[3]); text=sys.argv[4]
shown=[(s,r,v) for s,r,v in labels if v["visible"] and v["text"]==text]
if not shown: print("absent"); sys.exit()
if len(shown)!=1: print("unbounded"); sys.exit()
screen,(x,y,w,h),label=shown[0]
held=[r for s,r,v in windows if s==screen and v["visible"] and v["clip"] and r[0]==x and r[2]==w]
bounded=(len(held)==1 and label["lineCount"]>lines and abs(held[0][3]-lines*label["lineBox"])<=1
         and abs(h-label["lineCount"]*label["lineBox"])<=1)
if not bounded: print("unbounded"); sys.exit()
top,height=held[0][1],held[0][3]
print("latest-lines" if abs(y+h-top-height)<=1 else "first-lines" if abs(y-top)<=1 else "unbounded")
' "$labels" "$windows" "$lines" "$jarvis_bubble_reply"
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
    clips="$(ipc smoke layerItems vgs.jarvis QQuickItem clip,visible)" &&
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
    // The scrolling container also clips. The caption window sits above
    // the held question and aligns its body label at its bottom edge.
    const [screen, question] = questions[0];
    const captions = JSON.parse(rawClips).filter(([clipScreen, box, value]) => value.clip === true
        && clipScreen === screen && box[1] + box[3] <= question[1]
        && labels.some(([labelScreen, labelBox, label]) => labelScreen === clipScreen && label.role === "body"
            && labelBox[0] === box[0] && labelBox[2] === box[2]
            && Math.abs(labelBox[1] + labelBox[3] - box[1] - box[3]) <= 1));
    assert.equal(captions.length, 1);
    assert.equal(captions[0][2].visible, false);
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

jarvis_bubble_engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
cp -- "$jarvis_bubble_engine" "$sandbox/jarvis-bubble-engine-before"
cp -- "$jarvis_key_backend" "$sandbox/jarvis-bubble-backend-before"
jarvis_disable
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --held-approvals "$jarvis_key_backend"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --chained-engine "$jarvis_bubble_engine"
# Every sandbox shell lacks a required Jarvis command (tesseract is in
# qml-smoke.sh's shell_hidden_commands), so an enable raises the core
# requirement notice, which under the pointer keeps the keyboard from the
# client opened below. The stand-ins rows/jarvis-setup.sh stands let the
# enables here raise none, and the scan that finds them closes a notice an
# earlier enable left.
jarvis_setup_requirements
jarvis_rescan
jarvis_enable
expect_poll "no requirement notice stands over the bubble's client" null notice_shown
expect_poll "ready idle maps no bubble" 0 layer_count vgs:layer
expect "the Jarvis widget unplaces without disabling its service" ok ipc shell setPluginPlaced vgs.jarvis false
expect "the build contains no Jarvis bar widget" 0 jarvis_bubble_widgets
if ! open_other "$sandbox/toplevel-jarvis-bubble.log"; then fail "the client below Jarvis maps"; exit 1; fi
expect_poll "the client below Jarvis has keyboard focus" '["smoke.other", "Other window"]' active_window
jarvis_bubble_begin
geometry expect_poll "the bubble clears reserved space and sits at bottom centre" bottom-centre jarvis_bubble_geometry
expect "the bubble takes no keyboard focus" '["smoke.other", "Other window"]' active_window
geometry expect_poll "the orb draws without a Jarvis bar widget" drawn jarvis_bubble_pixels
expect "control: hide only the bubble's shader" ok ipc smoke layerShaderSet vgs.jarvis false
geometry expect_poll "control: the same pixel reader sees the hidden shader" blank jarvis_bubble_pixels
expect "the shader is restored" ok ipc smoke layerShaderSet vgs.jarvis true
geometry expect_poll "the restored orb draws" drawn jarvis_bubble_pixels
expect "the bar disables independently of Jarvis" ok jarvis_bubble_hide_bar
expect_poll "the orb still presents without any bar" presented jarvis_bubble_state
geometry expect_poll "the bubble follows the free area without a bar" bottom-centre jarvis_bubble_geometry
expect "the bar returns without restarting Jarvis" ok ipc shell setPluginEnabled vgs.bar true
expect_poll "the bubble follows the restored reserved space" presented jarvis_bubble_state

read -r orb_x orb_y orb_w orb_h < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$(control_box vgs:layer vgs.jarvis VoiceOrb active true)")
read -r mute_x mute_y mute_w mute_h < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$(control_box vgs:layer vgs.jarvis IconButton label 'Mute Jarvis')")
read -r stop_x stop_y stop_w stop_h < <(python3 -c 'import json,sys; print(*json.loads(sys.argv[1]))' "$(control_box vgs:layer vgs.jarvis IconButton label 'Stop Jarvis')")
read -r orb_cx orb_cy mute_gap_x mute_gap_y < <(python3 -c '
import sys
orb = [float(v) for v in sys.argv[1:5]]
mute = [float(v) for v in sys.argv[5:9]]
ox, oy, ow, oh = orb
mx, my, mw, mh = mute
gap_left = ox + ow
gap_right = mx
if gap_right - gap_left < 1:
    print("absent absent absent absent")
else:
    print(round(ox + ow / 2), round(oy + oh / 2), round((gap_left + gap_right) / 2), round(my + mh / 2))
' "$orb_x" "$orb_y" "$orb_w" "$orb_h" "$mute_x" "$mute_y" "$mute_w" "$mute_h")
if [[ $mute_gap_x == absent ]]; then
  fail "the decorative gap between the Jarvis orb and Mute button is absent"
fi
jarvis_bubble_pass "$orb_cx" "$orb_cy"
jarvis_bubble_pass "$(((mute_x + mute_w + stop_x) / 2))" "$((mute_y + mute_h / 2))"
[[ $mute_gap_x == absent ]] || jarvis_bubble_pass "$mute_gap_x" "$mute_gap_y"
expect "decorative clicks cannot mute" off jarvis_key_state mute
expect "decorative clicks keep capture live" open jarvis_key_state capture
jarvis_bubble_click "Stop Jarvis"
jarvis_key_talk_up
jarvis_key_stop_assertion
expect_poll "Stop removes the idle bubble" 0 layer_count vgs:layer
jarvis_bubble_begin
jarvis_bubble_click "Mute Jarvis"
expect_poll "the labelled Mute button turns privacy mute on" on jarvis_key_state mute
expect_poll "the Mute button closes capture before hiding" closed jarvis_key_state capture
jarvis_key_talk_up
jarvis_key_mute
expect_poll "explicit unmute does not restore capture" off jarvis_key_state mute
expect "unmute still leaves no capture" closed jarvis_key_state capture

for jarvis_bubble_answer in key Confirm Cancel Yes No; do
  jarvis_bubble_purpose=action
  case "$jarvis_bubble_answer" in Yes|No) jarvis_bubble_purpose=release ;; esac
  jarvis_bubble_effect=tool-start
  case "$jarvis_bubble_answer" in Cancel|No) jarvis_bubble_effect=approval-ended ;; Yes) jarvis_bubble_effect=release-confirmed ;; esac
  jarvis_bubble_before="$(jarvis_key_effects "$jarvis_bubble_effect")"
  jarvis_bubble_approval "$jarvis_bubble_purpose"
  expect_poll "the held request receives a drawn-frame acknowledgment" drawn jarvis_bubble_acknowledged
  expect "the drawn hold binds its typed call and ordered button roles without a duplicate caption" 1 jarvis_bubble_request
  expect "drawing a hold starts no request" "$jarvis_bubble_before" jarvis_key_effects "$jarvis_bubble_effect"
  expect "approval keeps the application's keyboard focus" '["smoke.other", "Other window"]' active_window
  geometry expect_poll "the held request stays inside its surface" bottom-centre jarvis_bubble_geometry
  jarvis_bubble_accept "$jarvis_bubble_answer" "$jarvis_bubble_effect" "$((jarvis_bubble_before + 1))"
  jarvis_key_stop
  jarvis_key_stop_assertion
done

jarvis_bubble_reply="$(python3 -c 'print(" ".join(["scripted reply"] * 24))')"
jarvis_bubble_begin
jarvis_key_gate partial
expect_poll "the user's partial draws while capture stays open" drawn jarvis_bubble_text 'scripted draft'
expect "a drawn partial leaves the utterance collecting" collecting jarvis_key_state turn
jarvis_bubble_think
expect_poll "the final replaces the user's draft while the brain thinks" drawn jarvis_bubble_text 'scripted utterance'
expect "the replaced draft leaves the bubble" absent jarvis_bubble_text 'scripted draft'
jarvis_key_gate reply
expect_poll "the reply replaces the user's final" latest-lines jarvis_bubble_words
jarvis_bubble_earlier="$(ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["transcript"]))')"
jarvis_key_stop
jarvis_key_stop_assertion
jarvis_bubble_begin
jarvis_bubble_think caption
expect_poll "the bubble draws the latest three lines of Jarvis's words" latest-lines jarvis_bubble_words
expect "the worded bubble keeps its presented indicator" presented jarvis_bubble_state
geometry expect_poll "the worded bubble stays at bottom centre" bottom-centre jarvis_bubble_geometry
read -r words_x words_y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(round(x+w/2),round(y+h/2))' "$(control_box vgs:layer vgs.jarvis QQuickItem clip true)")
jarvis_bubble_pass "$words_x" "$words_y"
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
cp -- "$jarvis_bubble_lua" "$sandbox/jarvis-bubble-focus-before.lua"
jarvis_bubble_first="$(hypr -j monitors | py_reply 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))')"
printf '%s\n' 'hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true }, misc = { mouse_move_focuses_monitor = false } })' >>"$jarvis_bubble_lua"
expect "the nested configuration holds monitor focus" ok hypr reload config-only
expect "the nested compositor adds another focus target" ok hypr output create headless SMOKE-JARVIS
expect "the physical-key fixture focuses the other monitor" ok probe dispatch "focusMonitor SMOKE-JARVIS"
expect_poll "the service observes the other focused output" '"SMOKE-JARVIS"' ipc smoke readInstance service vgs.jarvis focusedOutput
expect_poll "only the focused output requests a bubble" focused jarvis_bubble_focused
expect "focus returns to the original monitor" ok probe dispatch "focusMonitor $jarvis_bubble_first"
expect_poll "the service observes restored monitor focus" "\"$jarvis_bubble_first\"" ipc smoke readInstance service vgs.jarvis focusedOutput
expect_poll "the restored focused output owns the visual" focused jarvis_bubble_focused
expect "the nested compositor removes the focus target" ok hypr output remove SMOKE-JARVIS
cp -- "$sandbox/jarvis-bubble-focus-before.lua" "$jarvis_bubble_lua"
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
cp -- "$jarvis_bubble_file" "$sandbox/jarvis-bubble-before"
# Row.layoutDirection reverses rendered positions (Qt Quick Row reference).
# The position reader must reject that reversal, regardless of button copy.
jarvis_bubble_fixture="$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
cp -- "$jarvis_bubble_fixture" "$sandbox/jarvis-bubble-fixture-before"
for jarvis_bubble_mutant in geometry focus words lines head generation approval-key approval-button approval-cancel approval-shown approval-caption approval-kind approval-path approval-role approval-order; do
  jarvis_bubble_mutation_file="$jarvis_bubble_file"
  if [[ $jarvis_bubble_mutant == approval-key || $jarvis_bubble_mutant == approval-shown ]]; then
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
    "geometry": ("anchors.bottomMargin: Theme.voiceBubble.margin", "anchors.bottomMargin: Theme.voiceBubble.margin + Theme.voiceBubble.gap"),
    "focus": ("screen.name === service.focusedOutput", "true"),
    "words": ('caption !== null && caption.gen', "false && caption.gen"),
    "lines": ("Theme.voiceBubble.textLines * tail.lineBox", "(Theme.voiceBubble.textLines + 1) * tail.lineBox"),
    "head": ("y: parent.height - height", "y: 0"),
    "generation": ("caption.gen === state.gen", "true"),
    "approval-key": ('() => confirmApproval(displayedApproval(), "key")', '() => {}'),
    "approval-button": ('root.service.confirmApproval(root.displayedHold, "button")', 'void root.displayedHold'),
    "approval-cancel": ('root.service.cancelApproval(root.displayedHold)', 'void root.displayedHold'),
    "approval-shown": ('send({ type: "shown", id: hold.id });', 'void hold;'),
    "approval-caption": ('state === null || root.hold !== null ? ""', 'state === null ? ""'),
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
      cp -- "$sandbox/jarvis-bubble-before" "$jarvis_bubble_file"
      cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
      cp -- "$sandbox/jarvis-bubble-fixture-before" "$jarvis_bubble_fixture"
      continue ;;
  esac
  jarvis_bubble_begin
  case "$jarvis_bubble_mutant" in
    geometry)
      expect "control: a wrong bottom margin fails the same geometry reader" wrong-geometry jarvis_bubble_geometry
      jarvis_key_talk_up ;;
    focus)
      expect "control: add another output without changing focus" ok hypr output create headless SMOKE-JARVIS
      expect_poll "control: ignoring focus fails the same output reader" wrong-output jarvis_bubble_focused
      expect "control: remove the second output" ok hypr output remove SMOKE-JARVIS
      jarvis_key_talk_up ;;
    words)
      jarvis_bubble_think caption
      expect "control: dropping the consumer fails the same words reader" absent jarvis_bubble_words ;;
    lines)
      jarvis_bubble_think caption
      expect_poll "control: a fourth line fails the same words reader" unbounded jarvis_bubble_words ;;
    head)
      jarvis_bubble_think caption
      expect_poll "control: the first three lines fail the same words reader" first-lines jarvis_bubble_words ;;
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
  cp -- "$sandbox/jarvis-bubble-before" "$jarvis_bubble_file"
done
# Restore the independent bindings in one disposable source copy. Clearing
# its hold must make the diagnostics row fail. Only that copy's source URI
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
jarvis_bubble_control_pattern="$(python3 - "$sandbox/jarvis-bubble-bindings-errors.log" <<'PY'
import re,sys
rows=open(sys.argv[1]).read().splitlines()
assert rows
uris=[]
for row in rows:
    match=re.search(r' WARN scene: (file://[^ ]+/Bubble\.qml)\[[0-9]+:[0-9]+\]:',row)
    assert match,row
    uris.append(match[1])
assert len(set(uris))==1
print(re.escape(uris[0])+r'\[[0-9]+:[0-9]+\]:')
PY
)"
# This reader consumes check_unexpected_log's failure block. Other
# diagnostics failures do not change whether it holds this copy's warning.
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
  # The real row appends sampler output; keep this control's files private.
  sandbox="$jarvis_bubble_binding_dir"
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
jarvis_disable
cp -- "$sandbox/jarvis-bubble-before" "$jarvis_bubble_file"
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
# Before the copies go back: its scan would take the source change the
# rescan below reads.
jarvis_restore_requirements
cp -- "$sandbox/jarvis-bubble-before" "$jarvis_bubble_file"
cp -- "$sandbox/jarvis-bubble-engine-before" "$jarvis_bubble_engine"
cp -- "$sandbox/jarvis-bubble-backend-before" "$jarvis_key_backend"
jarvis_rescan
jarvis_enable
jarvis_key_mode hold
close_other "the client below Jarvis exits"
