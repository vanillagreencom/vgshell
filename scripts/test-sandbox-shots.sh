#!/usr/bin/env bash
# Drive scripts/smoke/shot.sh, the sandbox capture helpers, with no
# sandbox: plain Unix sockets stand in for the host and nested Wayland
# sockets, and a stub grim on PATH writes the image each case needs. A stub
# hyprctl on PATH answers for the host compositor, so the cases of
# scripts/smoke/host-window.sh read a planted host world. Each
# case pins the exit status and the first line on stderr. The controls at
# the end plant one defect per guard in a copy of the file and require the
# case that guard owns to go red. The scene cases drive
# scripts/sandbox-shots.sh itself up to its harness, in a scratch git
# repository, and the export cases drive scripts/smoke/tree.sh, which
# sandbox-shots.sh and the harness share.
#
# Exit 0 when every case and control holds, 1 otherwise, 77 when the scene
# cases could not run because scripts/smoke/gpu-fence.sh reported
# not-measured.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
helper="$repo/scripts/smoke/shot.sh"

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
tmp="$(mktemp -d)" || { echo "test-sandbox-shots: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-sandbox-shots: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# These records come from the scene desktop before a modal scrim opens.
# Run the shot script's pair check itself without starting its sandbox.
mkdir -p "$tmp/desktop-before" "$tmp/desktop-after"
printf 'polkit\tlight\tbefore\t100\t100\t000000\n' >"$tmp/desktop-before/desktop.tsv"
desktop_pair_case() { # SCRIPT RGB EXPECTED_EXIT
  local status=0
  printf 'polkit\tlight\tafter\t100\t100\t%s\n' "$2" >"$tmp/desktop-after/desktop.tsv"
  "$BASH" "$1" --check-desktop-pair "$tmp/desktop-before" "$tmp/desktop-after" >"$tmp/desktop-pair.log" 2>&1 || status=$?
  [[ $status -eq $3 ]]
}
for spec in '000000 0' '111111 1' 'unreadable 1'; do
  read -r rgb expected <<<"$spec"
  if desktop_pair_case "$repo/scripts/sandbox-shots.sh" "$rgb" "$expected"; then
    ok "desktop pair: $rgb exits $expected"
  else
    fail "desktop pair: $rgb does not exit $expected"
  fi
done
desktop_mutant="$tmp/desktop-mutant.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$desktop_mutant" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '        if a != b:\n'
assert text.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(text.replace(needle, '        if False:\n'))
PY
if desktop_pair_case "$desktop_mutant" 111111 1; then
  fail "control: removing the desktop comparison leaves its differing-pair case green"
else
  ok "control: removing the desktop comparison fails its differing-pair case"
fi

# A newly mapped Settings window takes pointer presses only after a move.
# Exercise the harness's real coordinate and click helpers without a shell.
click_helper="$tmp/click-helper.sh"
sed -n '/^at_centre() {/,/^}/p; /^click_in() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$click_helper"
click_case() {
  env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
ipc() { printf "%s\n" "[20, 30, 40, 20]"; }
surface_box() { printf "%s\n" "[100, 200, 800, 600]"; }
hover() { [[ $1 == 141 && $2 == 240 ]] && moved=true; }
click() { [[ ${moved:-false} == true && $1 == 140 && $2 == 240 ]]; }
click_in window:Plugins window vgs.settings Button Install
' _ "$1"
}
if click_case "$click_helper"; then ok "a click moves the pointer before pressing in a newly mapped window"; else fail "the pointer press did not reach the mapped window"; fi
click_mutant="$tmp/click-mutant.sh"
python3 - "$click_helper" "$click_mutant" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '  hover "$((x + 1))" "$y" || return $?\n'
assert text.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(text.replace(needle, ""))
PY
if click_case "$click_mutant"; then fail "control: a click without a pointer move reached the mapped window"; else ok "control: a click without a pointer move misses the mapped window"; fi

# Pointer targets and reserved space use logical dimensions at every scale.
size_helper="$tmp/size-helper.sh"
sed -n '/^monitor_size() {/p; /^bar_settled_judge() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$size_helper"
size_case() {
  env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
py_reply() { python3 -c "$@"; }
for scale in 1 2; do
  monitors="[{\"name\":\"WAYLAND-1\",\"width\":$((1440 * scale)),\"height\":$((900 * scale)),\"scale\":$scale,\"reserved\":[0,36,0,0]}]"
  hypr() { printf "%s\n" "$monitors"; }
  [[ $(monitor_size) == "1440 900 36" ]] || exit 1
  layers="{\"WAYLAND-1\":{\"levels\":{\"2\":[{\"namespace\":\"vgs:bar\",\"pid\":123}]}}}"
  [[ $(printf "%s\n%s\n" "$monitors" "$layers" | bar_settled_judge WAYLAND-1) == "1440 900 36" ]] || exit 1
done
' _ "$1"
}
if size_case "$size_helper"; then ok "monitor and settled-bar readers return logical sizes at scales 1 and 2"; else fail "monitor or settled-bar reader returned a physical size"; fi
for reader in monitor_size bar_settled_judge; do
  size_mutant="$tmp/size-$reader-mutant.sh"
  python3 - "$size_helper" "$size_mutant" "$reader" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index(sys.argv[3] + '() {')
end = text.index('\n}', start) + 2 if sys.argv[3] == 'bar_settled_judge' else text.index('\n', start)
body = text[start:end]
assert body.count(' / m["scale"]') == 2
pathlib.Path(sys.argv[2]).write_text(text[:start] + body.replace(' / m["scale"]', '') + text[end:])
PY
  if size_case "$size_mutant"; then fail "control: $reader physical sizes passed the scale-2 pointer case"; else ok "control: $reader physical sizes fail the scale-2 pointer case"; fi
done

# The host's runtime dir with its socket, and the sandbox's beneath it, as
# the harness makes them.
host="$tmp/run"; rt="$host/vs.test"
mkdir -p "$rt" "$tmp/bin" "$tmp/checkout/tmp"
python3 - "$host/wayland-1" "$host/wayland-2" "$rt/wayland-1" <<'PY'
import socket, sys
for path in sys.argv[1:]:
    socket.socket(socket.AF_UNIX).bind(path)
PY
ln -s "$host/wayland-1" "$rt/wayland-9"
: >"$rt/wayland-file"

# The stub grim: the mode file beside it picks what it writes to its last
# argument, since shot.sh runs grim in an empty environment. fixed-a and
# fixed-b write one image each time; counter writes a new one each call;
# hang never returns; unsized-layout fails as grim 1.5.0 does when the
# layout holds an output with no size, unless -o names the sized output
# WAYLAND-1. pixel-scale2 follows grim's default output scale of 2,
# unless -s sets the image scale to 1. It records its environment in env.log.
cat >"$tmp/bin/grim" <<'SH'
#!/usr/bin/env bash
out="${!#}"
here="${0%/*}"
env | sort >"$here/env.log"
case "$(cat "$here/mode")" in
  fixed-a) printf 'image-a' >"$out" ;;
  fixed-b) printf 'image-b' >"$out" ;;
  counter) n=$(( $(cat "$here/count" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$here/count"; printf 'image-%s' "$n" >"$out" ;;
  hang) sleep 5 ;;
  unsized-layout) if [[ $1 == -o && $2 == WAYLAND-1 ]]; then printf 'image-b' >"$out"; else echo "failed to create buffer" >&2; exit 1; fi ;;
  pixel-scale2)
    if [[ $1 == -s && $2 == 1 ]]; then
      printf 'P6\n1 1\n255\n\x33\x66\x99'
    else
      printf 'P6\n2 2\n255\n\x33\x66\x99\x33\x66\x99\x33\x66\x99\x33\x66\x99'
    fi ;;
esac
SH
chmod 755 "$tmp/bin/grim"
# The stub hyprctl answers `-j clients` and `-j monitors` from the host
# world below, and fails after printing an empty list for the request a
# fail-<request> file beside it names. Two host monitors: DP-1 shows
# workspace 1, DP-2 shows workspace 2 and the special workspace -98.
# Windows: pid 41 on workspace 1, 42 on workspace 3, 43 on the shown
# special workspace, 44 on the special workspace -99 no monitor shows, 45
# on workspace 1 as a background group tab, which Hyprland lists with
# `visible: false` and `hidden: false`, 46 with no `visible` key and 47
# as a non-nested window.
cat >"$tmp/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
here="${0%/*}"
[[ $1 == -j && ( $2 == clients || $2 == monitors ) && $# -eq 2 ]] || exit 2
if [[ -e $here/fail-$2 ]]; then echo '[]'; exit 1; fi
cat -- "$here/host-$2.json"
SH
chmod 755 "$tmp/bin/hyprctl"
python3 - "$tmp/bin" <<'PY'
import json, sys
here = sys.argv[1]
def monitor(name, active, special):
    return {"name": name, "activeWorkspace": {"id": active, "name": str(active)}, "specialWorkspace": {"id": special, "name": "special:shown" if special else ""}}
def window(pid, workspace, visible=True, cls="aquamarine"):
    return {"stableId": f"stable-{pid}", "pid": pid, "class": cls, "mapped": True, "hidden": False,
            "visible": visible, "size": [800 + pid, 600 + pid], "workspace": {"id": workspace, "name": str(workspace)}}
unkeyed = window(46, 1)
del unkeyed["visible"]
json.dump([monitor("DP-1", 1, 0), monitor("DP-2", 2, -98)], open(f"{here}/host-monitors.json", "w"))
json.dump([window(41, 1), window(42, 3), window(43, -98), window(44, -99), window(45, 1, visible=False), unkeyed, window(47, 1, cls="ghostty")], open(f"{here}/host-clients.json", "w"))
PY
hash_a="$(printf 'image-a' | sha256sum | cut -d' ' -f1)"
# The hold cases run the real shot over the stub grim's fixed-b image.
# Their reader, hold, prints the hold's state, `reset` on the reads named
# in $D/resets (`1` for the first, `1 2` for the first two), and appends
# `read` to $D/log; their settle appends `settle` to the same log, so a
# case reads the order of the two around each capture. image_b_row NAME
# is the shots.tsv line of a settled fixed-b shot with no shot before it.
held_stubs='echo fixed-b >"$T/bin/mode"; hold() { local n; n=$(( $(cat "$D/reads" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$D/reads"; echo read >>"$D/log"; if [[ " $(cat "$D/resets" 2>/dev/null) " == *" $n "* ]]; then echo reset; else echo held; fi; }; settle() { echo settle >>"$D/log"; }; image_b_row() { printf "%s\t%s\t-\tsettled\t-\t-" "$1" "$(printf image-b | sha256sum | cut -d" " -f1)"; }; '

# run_case FILE LABEL SNIPPET STATUS LINE: true when the helper FILE gives
# the status and first stderr line. The snippet runs with the helper
# sourced, in an empty environment holding a marker that must never reach
# grim: T the test dir, RT the sandbox's runtime dir, HOST the host's, D
# an empty dir under the checkout's tmp/, and SHOT_DIR, SHOT_SOCKET and
# SHOT_RUNTIME_DIR and SHOT_OUTPUT set for `shot`.
run_case() {
  local file="$1" label="$2" snippet="$3" want_status="$4" want_line="$5" err status=0 dir
  dir="$tmp/checkout/tmp/case-$RANDOM$RANDOM"
  mkdir -p "$dir"
  env -i PATH="$tmp/bin:$PATH" HOST_MARKER=live T="$tmp" RT="$rt" HOST="$host" D="$dir" HASH_A="$hash_a" \
    SHOT_DIR="$dir" SHOT_SOCKET="$rt/wayland-1" SHOT_RUNTIME_DIR="$rt" SHOT_OUTPUT=WAYLAND-1 \
    bash -c 'set -euo pipefail; source "$1"; eval "$2"' _ "$file" "$snippet" >"$dir/out" 2>"$dir/err" || status=$?
  err="$(head -n 1 "$dir/err")"
  [[ $status -eq $want_status && $err == "$want_line" ]] && return 0
  printf '        %s: status=%s want=%s first stderr line: %s\n' "$label" "$status" "$want_status" "$err"
  return 1
}

# Cases, four fields each: label, snippet, status, first stderr line.
cases=(
  "the nested socket resolves"
  '[[ $(shot_socket "$RT" wayland-1 "$HOST/wayland-1") == "$RT/wayland-1" ]]' 0 ""
  "the host socket is refused"
  'shot_socket "$HOST" wayland-1 "$HOST/wayland-1"' 1 "shot: refused: reason=host-socket value=$host/wayland-1"
  "a link to the host socket is refused"
  'shot_socket "$RT" wayland-9 "$HOST/wayland-1"' 1 "shot: refused: reason=host-socket value=$host/wayland-1"
  "the host's runtime dir is refused"
  'shot_socket "$HOST" wayland-2 "$HOST/wayland-1"' 1 "shot: refused: reason=host-runtime-dir value=$host"
  "a path for a socket name is refused"
  'shot_socket "$RT" ../wayland-1 "$HOST/wayland-1"' 1 "shot: refused: reason=socket-not-a-name value=../wayland-1"
  "a file that is no socket is refused"
  'shot_socket "$RT" wayland-file "$HOST/wayland-1"' 1 "shot: refused: reason=not-a-socket value=$rt/wayland-file"
  "an output dir under tmp/ is made"
  '[[ $(shot_dir_under "$T/checkout" "$T/checkout/tmp/shots/a") == "$T/checkout/tmp/shots/a" ]]' 0 ""
  "an output dir outside tmp/ is refused"
  'shot_dir_under "$T/checkout" "$T/elsewhere"' 1 "shot: refused: reason=out-dir-outside-tmp value=$tmp/elsewhere"
  "a new settled capture is taken"
  'echo fixed-b >"$T/bin/mode"; shot one >/dev/null; want="$(printf "one\t%s\t-\tsettled\t-\t-" "$(printf image-b | sha256sum | cut -d" " -f1)")"; [[ $(cat "$D/shots.tsv") == "$want" && $(cat "$D/one.png") == image-b ]]' 0 ""
  "a capture equal to the previous shot is stale"
  'echo fixed-a >"$T/bin/mode"; shot_last_name=before; shot_last_hash="$HASH_A"; SHOT_SETTLE_S=1 shot two' 1 "shot: stale name=two previous=before sha256=$hash_a"
  "a capture that keeps changing is taken as animated"
  'echo counter >"$T/bin/mode"; SHOT_SETTLE_S=1 shot three >/dev/null; [[ $(cut -f1,4 "$D/shots.tsv") == $(printf "three\tanimated") ]]' 0 ""
  "a grim that never returns reads as no frame"
  'echo hang >"$T/bin/mode"; SHOT_GRIM_TIMEOUT_S=1 shot four' 2 "shot: capture-failed name=four grim-status=timeout"
  "grim sees only the nested socket"
  'echo fixed-b >"$T/bin/mode"; shot five >/dev/null; grep -qx WAYLAND_DISPLAY=wayland-1 "$T/bin/env.log"; grep -qx "XDG_RUNTIME_DIR=$RT" "$T/bin/env.log"; ! grep -q HOST_MARKER "$T/bin/env.log"' 0 ""
  "a layout pixel on a scale-2 output reads its colour"
  'echo pixel-scale2 >"$T/bin/mode"; [[ $(shot_pixel "$RT/wayland-1" "$RT" 10 20) == 336699 ]]' 0 ""
  "a capture under a hold held before and after is taken"
  "$held_stubs"'shot_held six hold settle >/dev/null; [[ $(cat "$D/log") == $(printf "settle\nread") && $(cat "$D/shots.tsv") == "$(image_b_row six)" && -e $D/six.png ]]' 0 ""
  "a held mode is settled before the capture"
  "$held_stubs"'echo 1 >"$D/resets"; settle() { echo settle >>"$D/log"; : >"$D/settled"; }; hold() { echo read >>"$D/log"; [[ -e $D/settled ]] && echo held || echo reset; }; shot_held seven hold settle >/dev/null; [[ $(cat "$D/log") == $(printf "settle\nread") && -e $D/seven.png ]]' 0 ""
  "a hold that cannot be settled refuses the shot untaken"
  "$held_stubs"'settle() { return 1; }; s=0; shot_held eight hold settle || s=$?; [[ ! -e $D/eight.png && ! -e $D/shots.tsv && ! -e $D/log ]] || exit 9; exit "$s"' 3 "shot: refused: reason=hold-not-settled value=eight"
  "a hold left during the capture is settled and the shot retaken once"
  "$held_stubs"'echo 1 >"$D/resets"; shot_held eightb hold settle >/dev/null; [[ $(cat "$D/log") == $(printf "settle\nread\nsettle\nread") && $(cat "$D/shots.tsv") == "$(image_b_row eightb)" && -e $D/eightb.png ]]' 0 "shot: refused: reason=hold-left-after value=reset"
  "a hold left during the retaken capture too refuses the shot"
  "$held_stubs"'echo "1 2" >"$D/resets"; s=0; shot_held eightc hold settle >/dev/null || s=$?; [[ ! -e $D/eightc.png && ! -e $D/shots.tsv && $(grep -c settle "$D/log") == 2 ]] || exit 9; exit "$s"' 4 "shot: refused: reason=hold-left-after value=reset"
  "a capture after which the hold reader reads a reset is refused"
  "$held_stubs"'echo 1 >"$D/resets"; s=0; shot_last_name=before; shot_last_hash=prior; SHOT_HOLD_READER=hold shot eightd >/dev/null || s=$?; [[ ! -e $D/eightd.png && ! -e $D/shots.tsv && $shot_last_name == before && $shot_last_hash == prior ]] || exit 9; exit "$s"' 4 "shot: refused: reason=hold-left-after value=reset"
  "a capture of its own output is taken while another output has no size"
  'echo unsized-layout >"$T/bin/mode"; shot nine >/dev/null; [[ $(cat "$D/nine.png") == image-b ]]' 0 ""
  "a shot with no output named is refused"
  'echo fixed-b >"$T/bin/mode"; SHOT_OUTPUT= shot ten' 1 "shot: refused: reason=output-unnamed value=ten"
  "a shot records the window state read around it"
  'echo fixed-b >"$T/bin/mode"; state() { echo hidden; }; SHOT_WINDOW_READER=state shot eleven >/dev/null; [[ $(cut -f5 "$D/shots.tsv") == hidden ]]' 0 ""
  "a window state that changes during a shot reads changed"
  'echo fixed-b >"$T/bin/mode"; state() { if [[ -e $D/read ]]; then echo shown; else : >"$D/read"; echo hidden; fi; }; SHOT_WINDOW_READER=state shot twelve >/dev/null; [[ $(cut -f5 "$D/shots.tsv") == changed ]]' 0 ""
  "a window reader that fails leaves its word"
  'echo fixed-b >"$T/bin/mode"; state() { echo unreadable; return 1; }; SHOT_WINDOW_READER=state shot thirteen >/dev/null; [[ $(cut -f5 "$D/shots.tsv") == unreadable ]]' 0 ""
  "a shot in the required window state is taken"
  'echo fixed-b >"$T/bin/mode"; state() { echo hidden; }; SHOT_WINDOW_READER=state SHOT_WINDOW_REQUIRE=hidden shot fourteen >/dev/null; [[ $(cut -f1,5 "$D/shots.tsv") == $(printf "fourteen\thidden") && -e $D/fourteen.png ]]' 0 ""
  "a shot in another window state is refused"
  'echo fixed-b >"$T/bin/mode"; state() { echo shown; }; s=0; SHOT_WINDOW_READER=state SHOT_WINDOW_REQUIRE=hidden shot fifteen >/dev/null || s=$?; [[ ! -e $D/shots.tsv && ! -e $D/fifteen.png ]] || exit 9; exit "$s"' 1 "shot: refused: reason=window-state value=shown"
  "a shot records clean chrome"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo clean; }; SHOT_CHROME_READER=chrome shot sixteen >/dev/null; [[ $(cut -f1,6 "$D/shots.tsv") == $(printf "sixteen\tclean") && -e $D/sixteen.png ]]' 0 ""
  "a shot with required clean chrome is taken"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo clean; }; SHOT_CHROME_READER=chrome SHOT_CHROME_REQUIRE=clean shot seventeen >/dev/null; [[ $(cut -f1,6 "$D/shots.tsv") == $(printf "seventeen\tclean") && -e $D/seventeen.png ]]' 0 ""
  "a shot with tooltip chrome is refused"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo tooltip; }; s=0; SHOT_CHROME_READER=chrome SHOT_CHROME_REQUIRE=clean shot eighteen >/dev/null || s=$?; [[ ! -e $D/shots.tsv && ! -e $D/eighteen.png ]] || exit 9; exit "$s"' 1 "shot: refused: reason=chrome value=tooltip"
)
# run_cases FILE CASES: every case of the array CASES against FILE.
run_cases() {
  local file="$1" i
  local -n rows="$2"
  for (( i = 0; i < ${#rows[@]}; i += 4 )); do
    if run_case "$file" "${rows[@]:i:4}"; then ok "${rows[i]}"; else fail "${rows[i]}"; fi
  done
}
run_cases "$helper" cases

# mutate FILE OLD NEW OUT: a copy of FILE with OLD, which must occur once,
# replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$1")"
  rest="${text//"$2"/}"
  count=$(( (${#text} - ${#rest}) / ${#2} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$2"
    return 1
  fi
  printf '%s\n' "${text/"$2"/"$3"}" >"$4"
  cmp -s -- "$1" "$4" && { printf '        mutation left the file unchanged: %s\n' "$2"; return 1; }
  return 0
}

# run_controls FILE CASES CONTROLS: each control of the array CONTROLS
# planted in a copy of FILE must turn its case of the array CASES red.
run_controls() {
  local file="$1" i j label target mutant row
  local -n rows="$2" plants="$3"
  for (( i = 0; i < ${#plants[@]}; i += 4 )); do
    label="${plants[i]}"; target="${plants[i + 3]}"
    mutant="$tmp/mutant-${file##*/}-$i.sh"
    if ! mutate "$file" "${plants[i + 1]}" "${plants[i + 2]}" "$mutant"; then fail "control: $label"; continue; fi
    row=()
    for (( j = 0; j < ${#rows[@]}; j += 4 )); do [[ ${rows[j]} == "$target" ]] && row=("${rows[@]:j:4}"); done
    if [[ ${#row[@]} -eq 0 ]]; then fail "control: $label names no case: $target"; continue; fi
    if run_case "$mutant" "${row[@]}" >/dev/null; then fail "control: $label left '$target' green"; else ok "control: $label"; fi
  done
}

# Controls, four fields each: label, text, replacement, and the case that
# must go red.
controls=(
  "the host socket is not compared"
  '[[ $path != "$host_real" ]] ||' 'true ||' "a link to the host socket is refused"
  "the host's runtime dir is not compared"
  '[[ $rt_real != "$(dirname -- "$host_real")" ]] ||' 'true ||' "the host's runtime dir is refused"
  "a socket name may be a path"
  '[[ -n $name && $name != */* && $name != . && $name != .. ]] ||' '[[ -n $name ]] ||' "a path for a socket name is refused"
  "the output dir may lie outside tmp/"
  '[[ $dir == "$root"/* ]] ||' 'true ||' "an output dir outside tmp/ is refused"
  "a capture is not compared with the previous shot"
  'if [[ $hash != "$shot_last_hash" ]]; then' 'if true; then' "a capture equal to the previous shot is stale"
  "a grim timeout reads as an error"
  '[[ $status -eq 124 ]] && return 2' 'true' "a grim that never returns reads as no frame"
  "grim inherits the caller's environment"
  'env -i PATH="$PATH"' 'env PATH="$PATH"' "grim sees only the nested socket"
  "a layout pixel uses the output scale"
  '-s 1 -g "$3,$4 1x1"' '-g "$3,$4 1x1"' "a layout pixel on a scale-2 output reads its colour"
  "the hold is not settled before the capture"
  'if ! "$settle"; then' 'if false; then' "a held mode is settled before the capture"
  "a capture the hold left is not retaken"
  '4) [[ $attempt -eq 2 ]] && return 4' '4) return 4' "a hold left during the capture is settled and the shot retaken once"
  "the hold is not read after the capture"
  'if [[ $hold != held ]]; then' 'if false; then' "a capture after which the hold reader reads a reset is refused"
  "the capture takes the whole layout"
  '-o "$3" -t png "$4"' '-t png "$4"' "a capture of its own output is taken while another output has no size"
  "an unnamed output goes on to grim"
  '[[ -n ${SHOT_OUTPUT:-} ]] ||' 'true ||' "a shot with no output named is refused"
  "the window state read is not recorded"
  '"$kind" "$window" "$chrome" >>' '"$kind" - "$chrome" >>' "a shot records the window state read around it"
  "the window state after the shot is not compared"
  '[[ $window_after == "$window_before" ]] ||' 'true ||' "a window state that changes during a shot reads changed"
  "a failing window reader ends the shot"
  '$SHOT_WINDOW_READER || true' '$SHOT_WINDOW_READER' "a window reader that fails leaves its word"
  "the required window state is not compared"
  'if [[ -n ${SHOT_WINDOW_REQUIRE:-} && $window != "$SHOT_WINDOW_REQUIRE" ]]; then' 'if false; then' "a shot in another window state is refused"
  "the required chrome state is not compared"
  'if [[ -n ${SHOT_CHROME_REQUIRE:-} && $chrome != "$SHOT_CHROME_REQUIRE" ]]; then' 'if false; then' "a shot with tooltip chrome is refused"
)
run_controls "$helper" cases controls

# Execute the Probe's actual JavaScript methods with a captured console and
# owner-data fixtures. This does not exercise QML bindings or signal wiring;
# the normal nested pair owns that evidence.
cat >"$tmp/probe-display-control.cjs" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
try {
    const source = fs.readFileSync(process.argv[2], 'utf8');
    function method(name, indent) {
        const pattern = new RegExp('^' + ' '.repeat(indent) + 'function ' + name
            + '\\([^\\n]*\\)(?:: string)? \\{[\\s\\S]*?^' + ' '.repeat(indent) + '\\}', 'gm');
        const matches = [...source.matchAll(pattern)];
        if (matches.length !== 1) throw new Error('Probe method extraction: ' + name);
        // Remove only QML's type annotations from the IPC signature.
        return matches[0][0].replace(/^([^\n]*?)\(reason: string\): string/m, '$1(reason)');
    }
    const methods = ['encodeDisplayEvent', 'displayEventEnvelope', 'emitDisplayEvent',
        'endDisplayEvents', 'detachDisplayEvents', 'armDisplayEvents', 'displayEventMonitorFacts',
        'displayEventQueueFacts', 'displayEventLayerFacts', 'displayEventReloaderFacts'].map(name => method(name, 4));
    methods.push(method('displayEventStop', 8));
    const capacities = {};
    for (const name of ['displayEventCapacityEvents', 'displayEventCapacityChars', 'displayEventTerminalReserve']) {
        const matches = [...source.matchAll(new RegExp('^    readonly property int ' + name + ': (\\d+)$', 'gm'))];
        if (matches.length !== 1) throw new Error('Probe capacity extraction: ' + name);
        capacities[name] = Number(matches[0][1]);
    }
    function fixture(status = 'armed') {
        const lines = [];
        let clock = 1000;
        const state = Object.assign({}, capacities, {
            displayEventInstance: 'fixture/instance', displayEventStatus: status,
            displayEventReason: '', displayEventSequence: 0, displayEventChars: 0,
            displayEventPriming: false,
            console: { log: line => lines.push(line) }, Date: { now: () => clock++ }
        });
        for (const name of ['Monitors', 'Compositor', 'Loader', 'Layer', 'Reloader', 'Hyprland', 'Quickshell'])
            state['displayEvent' + name] = { fixture: name };
        state.root = state;
        vm.createContext(state);
        vm.runInContext(methods.join('\n'), state);
        return { state, lines };
    }
    function record(f, expectedInstance = 'fixture/instance') {
        const prefix = 'VGS_DISPLAY_EVENT ';
        const events = f.lines.map(line => {
            assert.ok(line.startsWith(prefix), 'machine prefix');
            return JSON.parse(line.slice(prefix.length));
        });
        assert.ok(events.length <= f.state.displayEventCapacityEvents, 'finite event count');
        let chars = 0;
        for (const [index, event] of events.entries()) {
            assert.equal(event.sequence, index + 1, 'contiguous emitted sequence');
            assert.equal(event.instance, expectedInstance, 'instance survives delivery');
            assert.equal(event.schema, 'VGS-1714.display-event.v1', 'event schema');
            assert.equal(typeof event.realtimeMs, 'number', 'clock field');
            chars += f.lines[index].length - prefix.length;
        }
        assert.equal(chars, f.state.displayEventChars, 'aggregate JSON accounting');
        assert.ok(chars <= f.state.displayEventCapacityChars, 'finite JSON characters');
        return events;
    }
    function detached(f) {
        for (const name of ['Monitors', 'Compositor', 'Loader', 'Layer', 'Reloader', 'Hyprland', 'Quickshell'])
            assert.equal(f.state['displayEvent' + name], null, 'release ' + name);
        const count = f.lines.length;
        assert.equal(f.state.emitDisplayEvent('boundary', 'fixture', {}), false, 'terminal blocks later events');
        f.state.endDisplayEvents('interrupted', 'later');
        assert.equal(f.lines.length, count, 'terminal is emitted once');
    }
    {
        // Without the layer's reload Process the Probe refuses to arm.
        const f = fixture('absent');
        Object.assign(f.state, { LazyLoader: class {}, HyprlandLayer: class {}, Process: class {} });
        f.state.hyprland = Object.assign(new f.state.LazyLoader(), { active: true,
            item: Object.assign(new f.state.HyprlandLayer(), { reloadProcess: null }) });
        assert.equal(f.state.armDisplayEvents('no-reloader'), 'refused: display-events=reloader-identity', 'reloader refusal');
        assert.deepEqual(record(f).map(e => [e.kind, e.data.reason]), [['missing', 'reloader-identity']], 'reloader refusal terminal');
    }
    if (process.argv[3] !== undefined && process.argv[3] !== '--packets')
        throw new Error('unknown Probe control mode');
    if (process.argv[3] === '--packets') {
        // The collector consumes actual Probe output. Fixture owner values
        // drive the real arm/facts methods and notification handler bodies;
        // this does not simulate QML property binding or signal delivery.
        const f = fixture('absent');
        const state = f.state;
        Object.assign(state, { displayEventInstance: '73/100',
            LazyLoader: class {}, HyprlandLayer: class {}, Process: class {} });
        const monitors = { active: false, ownerId: '', outputs: [],
            trialState: { phase: 'idle', token: '', deadline: 0, failure: '' },
            tokenPath: '', trialLua: '', restoreLua: '', restoreRules: {}, keptRules: {} };
        const compositor = { queue: [], pending: null, pendingJudged: false, completion: null, reply: '' };
        const reloader = Object.assign(new state.Process(), {
            running: false, command: ['hyprctl', 'reload', 'config-only'], completion: null });
        const layer = Object.assign(new state.HyprlandLayer(), { reloadProcess: reloader,
            highestMonitorScale: 1, rendered: { text: 'fixture layer' }, machine: { phase: 'idle' } });
        Object.assign(state, {
            hyprland: Object.assign(new state.LazyLoader(), { active: true, item: layer }),
            Capabilities: { monitors }, Compositor: compositor, Hyprland: {}, Quickshell: {},
            displayEventGeometry: { screens: [], monitors: [] }
        });
        assert.equal(state.armDisplayEvents('collector-payloads'), 'ok', 'packet arm');
        function notify(owner, signal, field, value, args = []) {
            if (field !== null) state['displayEvent' + owner][field] = value;
            const matches = [...source.matchAll(new RegExp('^    Connections \\{\\n'
                + '        target: root\\.displayEvent' + owner + '\\n([\\s\\S]*?)^    \\}', 'gm'))];
            if (matches.length !== 1 || !matches[0][1].includes('function ' + signal + '('))
                throw new Error('Probe notification extraction: ' + owner + '.' + signal);
            state.fixtureSignalArguments = args;
            vm.runInContext('(function() {\n' + matches[0][1] + '\n' + signal
                + '(...fixtureSignalArguments);\n})()', state);
        }
        const trialLua = 'hl.monitor({ output = "WAYLAND-1", scale = 2 })';
        const restoreLua = 'hl.monitor({ output = "WAYLAND-1", scale = 1 })';
        const argv = ['hyprctl', 'eval', trialLua];
        for (const [signal, field, value] of [
            ['onActiveChanged', 'active', true],
            ['onOwnerIdChanged', 'ownerId', 'fixture.owner'],
            ['onTokenPathChanged', 'tokenPath', '/fixture/trial.token'],
            ['onTrialLuaChanged', 'trialLua', trialLua],
            ['onRestoreLuaChanged', 'restoreLua', restoreLua],
            ['onRestoreRulesChanged', 'restoreRules', { 'WAYLAND-1': { scale: 1 } }],
            ['onKeptRulesChanged', 'keptRules', { 'WAYLAND-1': { scale: 2 } }],
            ['onTrialStateChanged', 'trialState', { phase: 'arming', token: '/fixture/trial.token', deadline: 15, failure: '' }],
            ['onOutputsChanged', 'outputs', [{ name: 'WAYLAND-1', scale: 2 }]],
            ['onOutputsChanged', 'outputs', null]
        ]) notify('Monitors', signal, field, value);
        notify('Compositor', 'onQueueChanged', 'queue', [{ argv, judged: true }]);
        compositor.queue = [];
        notify('Compositor', 'onPendingChanged', 'pending', argv);
        notify('Compositor', 'onPendingJudgedChanged', 'pendingJudged', true);
        notify('Compositor', 'onReplyChanged', 'reply', 'ok');
        notify('Compositor', 'onCompletionChanged', 'completion', { code: 0, status: 0 });
        notify('Compositor', 'onCompletionChanged', 'completion', null);
        notify('Compositor', 'onPendingChanged', 'pending', null);
        notify('Layer', 'onHighestMonitorScaleChanged', 'highestMonitorScale', 2);
        notify('Layer', 'onRenderedChanged', 'rendered', { text: 'fixture scaled layer' });
        notify('Layer', 'onMachineChanged', 'machine', { phase: 'reloading', reloadOwner: 'layer' });
        state.displayEventGeometry = { screens: [{ name: 'WAYLAND-1', width: 1440, height: 900,
            x: 0, y: 0, devicePixelRatio: 2 }], monitors: [{ id: 0, name: 'WAYLAND-1',
            width: 2880, height: 1800, x: 0, y: 0, scale: 2, lastIpcObject: { scale: 2 } }] };
        const geometry = [...source.matchAll(/^    onDisplayEventGeometryChanged: \{\n([\s\S]*?)^    \}/gm)];
        if (geometry.length !== 1) throw new Error('Probe geometry notification extraction');
        vm.runInContext('(function() {\n' + geometry[0][1] + '\n})()', state);
        notify('Reloader', 'onRunningChanged', 'running', true);
        notify('Reloader', 'onCompletionChanged', 'completion', { code: 0, status: 0 });
        notify('Reloader', 'onExited', null, null, [0, 0]);
        notify('Reloader', 'onCompletionChanged', 'completion', null);
        notify('Reloader', 'onRunningChanged', 'running', false);
        notify('Reloader', 'onCommandChanged', 'command', ['hyprctl', 'reload', 'config-only']);
        notify('Compositor', 'onPendingJudgedChanged', 'pendingJudged', false);
        notify('Monitors', 'onActiveChanged', 'active', false);
        assert.equal(state.displayEventStop('fixture-end'), 'ok', 'packet stop');
        const packets = record(f, '73/100');
        assert.equal(packets[0].kind, 'arm', 'packet arm first');
        assert.equal(packets.at(-1).kind, 'stopped', 'packet stop last');
        detached(f);
        process.stdout.write(f.lines.join('\n') + '\n');
    } else {
    {
        const f = fixture();
        for (let i = 0; i < f.state.displayEventCapacityEvents; i++)
            f.state.emitDisplayEvent('boundary', 'fixture', { label: 'event ceiling' });
        const events = record(f);
        assert.equal(f.state.displayEventStatus, 'overflow', 'event ceiling stops capture');
        assert.equal(events.at(-1).kind, 'overflow', 'event ceiling retains terminal');
        assert.equal(events.at(-1).data.reason, 'capacity-events', 'event ceiling reason');
        detached(f);
    }
    {
        const f = fixture();
        const payload = 'x'.repeat(Math.ceil(f.state.displayEventCapacityChars / 16));
        // Enough payloads exceed the character budget before the event cap.
        for (let i = 0; i < 17 && f.state.displayEventStatus === 'armed'; i++)
            f.state.emitDisplayEvent('outputsChanged', 'MonitorState', { fixture: payload });
        const events = record(f);
        assert.equal(f.state.displayEventStatus, 'overflow', 'character ceiling stops capture');
        assert.equal(events.at(-1).data.reason, 'capacity-chars', 'character ceiling reason');
        detached(f);
    }
    for (const [initial, status, reason] of [
        ['armed', 'stopped', 'row-end'], ['armed', 'interrupted', 'probe-destroyed'],
        ['absent', 'missing', 'reloader-identity']
    ]) {
        const f = fixture(initial);
        if (status === 'stopped') assert.equal(f.state.displayEventStop(reason), 'ok', 'IPC stop');
        else f.state.endDisplayEvents(status, reason);
        const events = record(f);
        assert.equal(events.length, 1, 'terminal-only fixture');
        assert.equal(events[0].kind, status, 'terminal kind');
        assert.equal(events[0].data.reason, reason, 'terminal reason');
        assert.equal(f.state.displayEventStatus, status, 'terminal state');
        detached(f);
    }
    {
        const f = fixture();
        assert.equal(f.state.displayEventStop('x'.repeat(f.state.displayEventTerminalReserve)),
            'refused: display-events=overflow', 'long stop reason refuses');
        const events = record(f);
        assert.equal(events.at(-1).data.reason, 'capacity-stop-reason', 'long reason terminal');
        detached(f);
    }
    console.log('probe-display-control: pass');
    }
} catch (error) {
    if (error.code === 'ERR_ASSERTION') {
        console.error('probe-display-control: assertion-failed ' + error.message);
        process.exitCode = 1;
    } else {
        console.error('probe-display-control: unavailable ' + error.message);
        process.exitCode = 2;
    }
}
JS

# Exercise the actual embedded collector against owned original logs and public
# socket-shaped fixtures. This proves recording and failure states, not
# Hyprland delivery or QML notification wiring, which the smoke observes.
source "$repo/scripts/smoke/host-window.sh"
display_record_program >"$tmp/display-record.py"
if node "$tmp/probe-display-control.cjs" "$repo/scripts/smoke/Probe.qml" --packets >"$tmp/probe-display-packets.jsonl" &&
   python3 - "$tmp/display-record.py" "$tmp" "$repo/scripts/smoke/harness.sh" "$tmp/probe-display-packets.jsonl" <<'PY'
import contextlib, json, os, pathlib, re, runpy, signal, socket, subprocess, sys

program, root, harness, packet_path = map(pathlib.Path, sys.argv[1:])
text, harness_text = program.read_text(), harness.read_text()
fixture_directories = {}
packet_bytes = packet_path.read_bytes()
assert packet_bytes and packet_bytes.endswith(b'\n'), 'probe-source-packets-present'
packet_lines = packet_bytes.splitlines(keepends=True)
assert all(line.startswith(b'VGS_DISPLAY_EVENT ') for line in packet_lines), 'probe-source-packet-prefix'
source_packets = [json.loads(line[len(b'VGS_DISPLAY_EVENT '):]) for line in packet_lines]
assert [p['sequence'] for p in source_packets] == list(range(1, len(source_packets) + 1)), 'probe-source-packet-sequence'
assert source_packets[0]['kind'] == 'arm' and source_packets[-1]['kind'] == 'stopped', 'probe-source-packet-boundaries'

def payloads(producer, kind):
    return [p['data'] for p in source_packets if (p['producer'], p['kind']) == (producer, kind)]

assert payloads('MonitorState', 'tokenPathChanged') == ['/fixture/trial.token'], 'probe-source-string-present'
assert payloads('MonitorState', 'activeChanged') == [True, False], 'probe-source-booleans-present'
assert all(type(p) is bool for p in payloads('MonitorState', 'activeChanged')), 'probe-source-boolean-types'
assert payloads('HyprlandLayer', 'highestMonitorScaleChanged') == [2], 'probe-source-number-present'
assert type(payloads('HyprlandLayer', 'highestMonitorScaleChanged')[0]) is int, 'probe-source-number-type'
assert payloads('MonitorState', 'outputsChanged') == [[dict(name='WAYLAND-1', scale=2)], None], 'probe-source-array-null-present'
assert [p['completion'] for p in payloads('Compositor', 'completionChanged')] == [dict(code=0, status=0), None], 'probe-source-completion-reset-present'
assert payloads('HyprlandLayer.reloader', 'exited') == [dict(code=0, status=0)], 'probe-source-exit-present'

def fixture_directory(name):
    # Confined scratch prefixes are long. AF_UNIX names include this path.
    directory = root / ("r" + str(len(fixture_directories)))
    directory.mkdir()
    fixture_directories[name] = directory
    (directory / "fixture-name").write_text(name + "\n")
    return directory

def extract(source, name):
    match = re.search(r'^' + name + r'\(\) \{.*?^\}', source, re.M | re.S)
    assert match, 'source-extraction-' + name
    return match.group()

@contextlib.contextmanager
def server(name, source=text):
    directory = fixture_directory(name)
    recorder = directory / 'recorder.py'
    recorder.write_text(source)
    os.mkfifo(directory / 'ready')
    def expired(*_):
        raise TimeoutError('collector fixture: ' + (directory / 'stderr').read_text())
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(30)
    with (directory / 'stderr').open('wb') as err:
        child = subprocess.Popen([sys.executable, '-u', str(recorder), 'serve', str(directory)],
                                 env={}, stdout=subprocess.DEVNULL, stderr=err)
        try:
            with (directory / 'ready').open() as ready:
                assert ready.readline() == 'ready\n', 'collector-ready'
            def request(command, *args, error=None):
                with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as client:
                    client.settimeout(10)
                    client.connect(str(directory / 'control'))
                    client.sendall(json.dumps([command, *args]).encode())
                    reply = json.loads(client.recv(1048576))
                if error is not None:
                    assert not reply['ok'] and reply['error'] == error, ('expected-refusal', reply)
                    return
                assert reply['ok'], ('collector-runtime', reply)
                return reply['value']
            yield directory, recorder, child, request
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            signal.alarm(0)

def events(directory):
    return [json.loads(line) for line in (directory / 'events.jsonl').read_text().splitlines()]

def terminal(directory):
    rows = events(directory)
    assert rows[-1]['kind'] == 'terminal', 'terminal-retained'
    return rows[-1]['data']

# Actual shared launch/stop. Every signalled child belongs to this fixture.
def boundary(directory, recorder, mode='registered', source=harness_text):
    helper = directory / ('boundary-' + mode + '.sh')
    helper.write_text('\n'.join(extract(source, n) for n in ('spawn', 'stop_shell', 'shell_answers', 'py_reply')) + r'''
set -u
recorder=$1 fixture=$2 mode=$3
control=$fixture/control
pgids=()
trap 'for pid in $(jobs -pr); do kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done' EXIT
rt_dir=$fixture
stop_lock_wait_s=1
shell_memory_note() { :; }
fail() { printf '%s\n' "$*" >&2; }
lock_holders() { :; }
display_record_call() { python3 "$recorder" request "$control" "$@"; }
display_stream_kind=probe
[[ $mode != generic ]] || display_stream_kind=''
mkfifo "$fixture/ready-child"
spawn_pid=stale
spawn "$fixture/child.log" sh -c 'printf "stdout\n"; printf "stderr\n" >&2; printf "ready\n" >"$1"; exec sleep 60' _ "$fixture/ready-child"
IFS= read -r ready <"$fixture/ready-child"
shell_pid=$spawn_pid
printf '%s\n' "$shell_pid" "${pgids[-1]:-missing}" >"$fixture/pids"
if [[ $mode == adopted || $mode == direct-restart ]]; then
  kill -TERM "$shell_pid"
  wait "$shell_pid" 2>/dev/null || true
  setsid sh -c 'exec sleep 60' >"$fixture/adopted.log" 2>&1 &
  shell_pid=$!
  pgids+=("$shell_pid")
fi
shell_log=$fixture/child.log
if [[ $mode == supervised ]]; then
  shell_env=() shell_pids_started=()
  timeout_s=1 instance_log=''
  ok() { :; }
  ipc() { printf 'ok\n'; }
  qs_list() { printf '[{"id":"fixture","pid":%s}]\n' "$(<"$fixture/qs-pid")"; }
  mkdir -p "$fixture/bin" "$rt_dir/quickshell/by-id/fixture"
  : >"$rt_dir/quickshell/by-id/fixture/log.log"
  printf '#!/bin/sh\ncat "${0%%/bin/vgshell}/qs-pid"\n' >"$fixture/bin/vgshell"
  chmod +x "$fixture/bin/vgshell"
  cp -- "$(command -v sleep)" "$fixture/qs"
  for generation in 1 2; do
    "$fixture/qs" 60 &
    qs_child=$!
    printf '%s\n' "$qs_child" >"$fixture/qs-pid"
    for _ in $(seq 1 50); do
      [[ $(cat "/proc/$qs_child/comm") != qs ]] || break
    done
    shell_answers "$fixture" "$shell_log" || exit 2
    kill -TERM "$qs_child"
    wait "$qs_child" 2>/dev/null || true
  done
fi
if [[ $mode == already-reaped || $mode == clear-direct-reap ]]; then
  kill -TERM "$shell_pid"
  wait "$shell_pid" 2>/dev/null || true
  [[ $mode != clear-direct-reap ]] || shell_pid=''
fi
status=0
stop_shell || status=$?
printf '%s\n' "$status" "$shell_pid" >>"$fixture/pids"
stop_shell || true
for pid in "${pgids[@]}"; do wait "$pid" 2>/dev/null || true; done
''')
    if mode == 'many':
        body = helper.read_text().replace('spawn_pid=stale', 'for iteration in $(seq 1 130); do\ndisplay_stream_kind=probe\nspawn_pid=stale')
        body = body.replace('stop_shell || true\nfor pid', 'stop_shell || true\ndone\nfor pid')
        helper.write_text(body)
    result = subprocess.run(['bash', str(helper), str(recorder), str(directory), mode],
                            env={'PATH': os.getenv('PATH')}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
    assert result.returncode == 0, ('boundary-runtime', result.stderr)
    receipt = (directory / 'pids').read_text().splitlines()
    assert receipt[0].isdigit() and receipt[0] == receipt[1], 'original-launch-preserved'
    assert receipt[2:] == ['0', ''], 'stop-clears-ended-owner'
    assert (directory / 'child.log').read_bytes() == b'stdout\nstderr\n', 'original-output-preserved'

for mode in ('registered', 'generic', 'adopted', 'direct-restart', 'already-reaped', 'clear-direct-reap', 'supervised'):
    with server('boundary-' + mode) as (directory, recorder, child, request):
        boundary(directory, recorder, mode)
        current, rows = request('read'), events(directory)
        if mode in ('registered', 'already-reaped', 'supervised'):
            assert current['activeStreams'] == 0, 'typed-stop-retires'
            assert len([e for e in rows if e['kind'] == 'local-owner-end']) == 1, 'typed-stop-once'
            if mode == 'supervised':
                identities = [e['data']['registration'] for e in rows if e['kind'] == 'shell-observation-context']
                assert len(identities) == 2 and len(set(identities)) == 1, 'relaunch-keeps-acquired-generation'
        elif mode != 'clear-direct-reap':
            assert any(e['kind'] == 'unobserved-adoption-end' for e in rows), 'adoption-is-context'
            assert not any(e['kind'] == 'local-owner-end' for e in rows), 'adoption-cannot-end-registration'
            assert not current['problems'], 'adoption-no-false-missing'
        else:
            assert current['activeStreams'] == 1, 'direct-reap-retained-until-cleanup'
        request('close', '1', 'fixture-cleanup'); request('stop', 'normal'); child.wait(timeout=10)

# Capacity refusal executes the same real stop boundary and cannot stop
# the original spawn. Pending registrations are intentionally incomplete.
with server('full-original-launch') as (directory, recorder, child, request):
    with contextlib.ExitStack() as stack:
        for index in range(128):
            writer = stack.enter_context((directory / ('pending-' + str(index))).open('wb'))
            request('log', 'probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        boundary(directory, recorder)
        assert 'launch:expected-registration-refused' in request('read')['problems'], 'full-launch-explicit-refusal'
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
        assert terminal(directory)['localRecord'] == 'incomplete', 'full-launch-record-incomplete'

# Actual methods isolate generation rules. These flags are fixture context,
# not proof of a public subscription or a complete end-to-end record.
module = runpy.run_path(str(program))
def local(name, source=text):
    path = root / (name + '.py'); path.write_text(source)
    api = runpy.run_path(str(path))
    directory = fixture_directory(name)
    record = api['Record'](directory)
    record.bound = True
    record.set_scope('shader-context', 'fixture', '0')
    return record, api

def finish(record):
    record.close_window('1', 'fixture')
    record.stop_reason, record.stopping = 'normal', True
    record.run()
    return terminal(record.directory)

@contextlib.contextmanager
def acquired(record, index, bind=True, path=None):
    path = path or record.directory / ('log-' + str(index))
    with path.open('wb', buffering=0) as writer:
        key = record.watch_log('probe', str(path), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        child = subprocess.Popen(['sleep', '60'], stdout=writer, stderr=writer) if bind else None
        try:
            if child: record.launched('probe', key, str(child.pid), str(path))
            yield path, writer, key, child
        finally:
            if child is not None:
                if child.poll() is None: child.terminate()
                child.wait()

def end(record, child):
    context = record.owner_context(str(child.pid))
    child.terminate(); child.wait()
    record.end_owner(context, str(child.pid))

def many_stops(name, source=text):
    with server(name, source) as (directory, recorder, child, request):
        boundary(directory, recorder, 'many')
        assert request('read')['activeStreams'] == 0, 'completed-resource-retired'
        rows = events(directory)
        bindings = [e['data']['source'] for e in rows if e['kind'] == 'log-binding']
        assert len(bindings) == 130 and len(set(bindings)) == 130, 'unique-registration-generation'
        assert len([e for e in rows if e['kind'] == 'local-owner-end']) == 130, 'every-stop-owned-generation'
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
many_stops('retire-many')
record, _ = local('reader-close')
with acquired(record, 1) as (path, writer, key, child):
    writer.write(b'irrelevant\n'); record.drain()
    with path.open('rb') as reader: assert reader.read() == b'irrelevant\n'
    with path.open('ab'): pass
    record.drain()
    assert len(record.streams) == 1, 'reader-close-does-not-retire'
    assert not record.problems, 'ordinary-reader-preserved'
    end(record, child)
finish(record)

record, _ = local('capacity')
with contextlib.ExitStack() as stack:
    active = stack.enter_context(acquired(record, 0))
    for index in range(1, 128): stack.enter_context(acquired(record, index, bind=False))
    with (record.directory / 'refused.log').open('wb') as writer:
        try: record.watch_log('probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        except ValueError as error: assert str(error) == 'capacity-streams', 'capacity-refusal'
        else: raise AssertionError('capacity-refusal')
    end(record, active[3])
    stack.enter_context(acquired(record, 129, bind=False))
    assert len(record.streams) == 128, 'capacity-reacquired'
finish(record)

for mode in ('reuse', 'truncate', 'replace', 'wrong-owner', 'duplicate-end', 'required-no-event', 'missing-launch'):
    record, _ = local('identity-' + mode)
    with acquired(record, 1, bind=mode != 'missing-launch') as (path, writer, key, child):
        if mode == 'reuse':
            alias = path.with_name('alias'); os.link(path, alias)
            try: record.watch_log('probe', str(alias), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
            except ValueError as error: assert str(error) == 'log-inode-overlap-or-unproved-reuse', 'overlap-refused'
            else: raise AssertionError('overlap-refused')
            end(record, child)
            with acquired(record, 2, path=path) as (_, _, second, new_child):
                assert key != second, 'reuse-new-generation'
                end(record, new_child)
        elif mode in ('truncate', 'replace'):
            writer.write(b'x\n'); record.drain()
            if mode == 'truncate':
                os.ftruncate(writer.fileno(), 0); expected = ':truncated-history'
            else:
                path.rename(path.with_name('old')); path.write_bytes(b''); expected = ':replacement-or-watch-lost'
            record.drain()
            assert any(expected in p for p in record.problems), 'lost-history-rejected'
        elif mode in ('wrong-owner', 'duplicate-end'):
            context = record.owner_context(str(child.pid))
            if mode == 'wrong-owner':
                try: record.end_owner(context, str(os.getpid()))
                except ValueError as error: assert str(error) == 'owner-end-wrong-pid', 'wrong-owner-rejected'
                else: raise AssertionError('wrong-owner-rejected')
            child.terminate(); child.wait(); record.end_owner(context, str(child.pid))
            try: record.end_owner(context, str(child.pid))
            except ValueError as error: assert str(error) == 'owner-context-missing-or-ended', 'duplicate-end-rejected'
            else: raise AssertionError('duplicate-end-rejected')
        elif mode == 'required-no-event':
            record.scope = dict(role='display-smoke', displayRequired=True)
            record.shell_pids['fixture-qs'] = key
            record.require_display(str(child.pid), 'fixture-qs'); end(record, child)
            assert record.registrations[key]['fd'] is not None, 'required-reader-retained-before-event'
    result = finish(record)
    if mode == 'required-no-event': assert 'probe:missing' in result['problems'], 'missing-required-producer-rejected'
    if mode == 'missing-launch': assert any('registration:launch-missing:' in p for p in result['problems']), 'missing-expected-launch-rejected'

record, api = local('refused-and-unverified')
with subprocess.Popen(['sleep', '60'], stdout=subprocess.DEVNULL) as child:
    record.launched('probe', 'refused', str(child.pid), 'refused.log')
    assert record.resolve_owner(str(child.pid))['tag'] == 'expected-refused', 'refusal-is-expected'
    record.launches[0]['identity'] = dict(status='unavailable')
    assert record.resolve_owner(str(child.pid))['tag'] == 'expected-unverified', 'unknown-is-not-adoption'
    child.terminate(); child.wait()
assert 'launch:expected-registration-refused' in finish(record)['problems'], 'refusal-stays-incomplete'

def complete_case(name, source=text, omission=None, changed=False, context=False, packets=None, mixed=False):
    with server(name, source) as (directory, recorder, child, request):
        request('scope', 'shader-context' if context else 'display-smoke', 'fixture', '0', *([] if context else ['displays-modes']))
        connections = []
        for owner in ('host', 'nested'):
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(str(directory / owner)); listener.listen()
            request('host', str(directory / owner)) if owner == 'host' else request('bind', 'fixture', str(directory / owner), '71', 'wayland')
            peer, _ = listener.accept(); peer.sendall(b'monitoradded>>FIXTURE\n')
            connections.extend((peer, listener))
        with (directory / 'wayland.log').open('wb', buffering=0) as writer:
            key = request('log', 'wayland', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
            request('launched', 'wayland', key, str(os.getpid()), str(writer.name))
            writer.write(b'[100] xdg_toplevel@8.configure(100, 200, array[0])\n')
            writer.write(b'[100] wl_display#1.delete_id(26)\n')
            if omission == 'partial': writer.write(b'partial')
            if omission == 'line': writer.write(b'x' * 1048577 + b'\n')
        if not context and omission != 'arm-boundary':
            with (directory / 'probe.log').open('wb', buffering=0) as writer:
                key = request('log', 'probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
                producer = subprocess.Popen(['sleep', '60'], stdout=writer, stderr=writer)
                try:
                    request('launched', 'probe', key, str(producer.pid), str(writer.name))
                    request('mark', 'shell-identity', str(producer.pid), '73', 'fixture', str(writer.name))
                    request('require-display', str(producer.pid), '73')
                    request('mark', 'display-request', 'trialRules', '{}')
                    request('mark', 'display-reply', 'trialRules', '0', 'ok' if changed else 'refused: fixture')
                    notifications = [('Probe', 'arm', {})]
                    notifications += [(owner, 'initial-sample', {}) for owner in ('MonitorState', 'Compositor', 'HyprlandLayer', 'HyprlandLayer.reloader', 'Quickshell/Hyprland')]
                    if changed:
                        notifications += [('MonitorState', 'trialStateChanged', dict(phase='arming', token='fixture', deadline=100, failure='')), ('Compositor', 'completionChanged', dict(completion=dict(code=1, status=0))), ('HyprlandLayer.reloader', 'exited', dict(code=1, status=0))]
                    notifications += [('Probe', 'stopped', {})]
                    if packets is not None:
                        writer.write(packets)
                    else:
                        for sequence, (owner, kind, data) in enumerate(notifications, 1):
                            if omission == kind or omission == owner: continue
                            value = dict(schema='VGS-1714.display-event.v1', instance='73/100', sequence=sequence, realtimeMs=100, producer=owner, kind=kind, data=data)
                            writer.write(b'VGS_DISPLAY_EVENT ' + json.dumps(value).encode() + b'\n')
                    request('read')
                    context_key = request('owner-context', str(producer.pid))
                    producer.terminate(); producer.wait(); request('owner-end', context_key, str(producer.pid))
                    assert any(s['required'] for s in request('read')['streams']), 'required-reader-retained'
                finally:
                    if producer.poll() is None: producer.terminate(); producer.wait()
        request('close', '1', 'explicit'); request('close', '0', 'cleanup')
        if omission == 'interrupted': child.terminate()
        else: request('stop', 'normal')
        child.wait(timeout=10)
        for connection in connections: connection.close()
        result, rows = terminal(directory), events(directory)
        if mixed:
            # JSON text comparison preserves booleans versus numbers, nulls,
            # nested arrays, every metadata field and the producer clock.
            observed = [e['data'] for e in rows if e['kind'] == 'probe-observation']
            assert json.dumps(observed, sort_keys=True) == json.dumps(source_packets, sort_keys=True), 'probe-mixed-payloads-preserved'
        if omission != 'overflow':
            assert len([e for e in rows if e['kind'] == 'window-end']) == 1, ('window-end-first-fact', name, result)
            assert next(e for e in rows if e['kind'] == 'window-end')['data']['originalStatus'] == '1', 'window-end-original-status'
        if not omission:
            wayland = [e['data'] for e in rows if e['source'].startswith('wayland:')]
            assert any('xdg_toplevel@8.configure(' in d for d in wayland) and not any('delete_id' in d for d in wayland), 'wayland-bookkeeping-not-recorded'
        if omission: assert result['localRecord'] == 'incomplete', 'missing-or-lost-input-rejected'
        else:
            assert result['localRecord'] == 'complete', 'armed-zero-events-valid-collection'
            facts = result['factAvailability']
            if context: assert facts['queue-completion']['status'] == 'not-requested', 'context-facts-not-requested'
            else:
                assert facts['queue-completion']['status'] == ('observed' if changed else 'not-observed'), 'samples-are-not-history'
                assert result['displayOutcome'] == ('facts-observed' if changed else 'not-established'), 'fact-availability-separate'
                if changed and not mixed:
                    assert any(e['kind'] == 'probe-observation' and isinstance(e['data']['data'], dict) and e['data']['data'].get('code') == 1 for e in rows), 'failed-reload-exit-retained'
                if mixed:
                    assert all(facts[key]['observationCount'] == 1 for key in ('phase-token-deadline', 'trial-acceptance-publication', 'queue-completion', 'actual-layer-reload')), 'probe-event-specific-facts'
                    assert not any('probe-unparsed' in p or 'sequence-gap' in p for p in result['problems']), 'probe-valid-payload-continuity'
            cost = result['observationCost']
            prefix = (directory / 'events.jsonl').read_bytes().splitlines(keepends=True)[:-1]
            assert cost['prefixRecordEvents'] == len(prefix) and cost['prefixRecordBytes'] == sum(map(len, prefix)), 'cost-prefix-exact'
            assert cost['readBytes']['files'] > 0 and cost['userCpuSeconds'] >= 0 and cost['systemCpuSeconds'] >= 0 and cost['peakResidentKiB'] > 0, 'collector-cost-retained'
        return result

complete_case('complete-zero')
complete_case('complete-changes', changed=True)
complete_case('source-mixed', changed=True, packets=packet_bytes, mixed=True)
complete_case('context-no-probe', context=True)
for omission in ('arm-boundary', 'arm', 'MonitorState', 'stopped', 'partial', 'line', 'interrupted'):
    complete_case('missing-' + omission, omission=omission)
complete_case('event-overflow', text.replace('CAP_EVENTS = 65536', 'CAP_EVENTS = 3'), omission='overflow')

record, api = local('socket-eof')
left, right = socket.socketpair(); left.setblocking(False)
record.streams[left] = dict(source='nested-ipc', buffer=b'', kind='ipc', log=None, clipped=False, ended=False)
record.selector.register(left, api['selectors'].EVENT_READ, ('stream', left))
right.close(); record.read(left)
record.close_window('1', 'cleanup'); record.close_window('0', 'later')
assert 'nested-ipc:unexpected-eof' in finish(record)['problems'], 'preclose-eof-sticky'
record, api = local('notification-overflow')
record.notification(-1, api['IN_Q_OVERFLOW'], 0)
assert 'notification:overflow' in finish(record)['problems'], 'notification-overflow-rejected'
record, _ = local('missing-scope'); record.scope = None
assert 'scope:missing' in finish(record)['problems'], 'unknown-scope-incomplete'

def mutant(name, needle, replacement, check, assertion):
    assert text.count(needle) == 1, ('mutation-source', name)
    try: check(text.replace(needle, replacement))
    except AssertionError as error:
        assert str(error) == assertion, ('wrong-mutation-assertion', name, error)
        print('  CONTROL display collector: ' + name + ' fails ' + assertion)
    else: raise AssertionError(name + ' mutation survived')

# Every packet in this positive case came from actual Probe source. A global
# object-only filter must fail preservation, not an incidental runtime error.
mutant('object-only-payload', 'or not isinstance(value["kind"], str) or not value["kind"] or "data" not in value):',
       'or not isinstance(value["kind"], str) or not value["kind"] or "data" not in value or not isinstance(value["data"], dict)):',
       lambda source: complete_case('mut-object-only', source, changed=True, packets=packet_bytes, mixed=True), 'probe-mixed-payloads-preserved')

# Object-id release events outnumber the window facts in a full run and,
# recorded, fill the event cap before the facts arrive.
mutant('display-bookkeeping', 'wl_(?:compositor|surface|output)).*(?:configure|ack_configure|get_xdg_surface|get_toplevel|create_surface|enter\\(|leave\\(|destroy\\()', 'wl_(?:compositor|surface|output|display)).*(?:configure|ack_configure|get_xdg_surface|get_toplevel|create_surface|enter\\(|leave\\(|delete_id|destroy\\()',
       lambda source: complete_case('mut-bookkeeping', source), 'wayland-bookkeeping-not-recorded')

# Disposable envelope/fact mutations use the source-encoded positive packets.
# Invalid envelopes, sequence history, launch binding and event-specific fact
# errors have separate retained reasons. They never become no-change success.
def encode_packets(values):
    return b''.join(b'VGS_DISPLAY_EVENT ' + json.dumps(value).encode() + b'\n' for value in values)

def packet_variant():
    return json.loads(json.dumps(source_packets))

for name, field, value in (('schema', 'schema', 'wrong'), ('sequence-bool', 'sequence', True),
                           ('clock-bool', 'realtimeMs', True), ('clock-string', 'realtimeMs', '1000'),
                           ('clock-nan', 'realtimeMs', float('nan')), ('clock-inf', 'realtimeMs', float('inf'))):
    values = packet_variant(); values[0][field] = value
    result = complete_case('invalid-' + name, packets=encode_packets(values), omission='invalid-probe')
    assert any('probe-unparsed' in p for p in result['problems']), 'malformed-envelope-rejected'
values = packet_variant(); del values[0]['data']
assert any('probe-unparsed' in p for p in complete_case('invalid-data-absent', packets=encode_packets(values), omission='invalid-probe')['problems']), 'missing-payload-rejected'
values = packet_variant(); values[0]['realtimeMs'] = 1.0
huge = encode_packets(values).replace(b'"realtimeMs": 1.0', b'"realtimeMs": 1e9999', 1)
assert any('probe-unparsed' in p for p in complete_case('invalid-number-overflow', packets=huge, omission='invalid-probe')['problems']), 'nonfinite-json-number-rejected'
values = packet_variant(); del values[1]
assert any('probe:sequence-gap:' in p for p in complete_case('invalid-sequence-gap', packets=encode_packets(values), omission='invalid-probe')['problems']), 'probe-sequence-gap-rejected'
values = packet_variant()
for value in values: value['instance'] = '74/100'
assert any('probe:launch-unbound:' in p for p in complete_case('invalid-instance-binding', packets=encode_packets(values), omission='invalid-probe')['problems']), 'probe-instance-binding-rejected'

for producer, kind, fact, field, invalid in (
        ('MonitorState', 'trialStateChanged', 'phase-token-deadline', 'deadline', True),
        ('Compositor', 'completionChanged', 'queue-completion', 'completion', dict(code=True, status=0)),
        ('HyprlandLayer.reloader', 'exited', 'actual-layer-reload', 'status', '0')):
    for variant in ('wrong-type', 'missing-field', 'scalar'):
        values = packet_variant()
        target = next(p for p in values if (p['producer'], p['kind']) == (producer, kind))
        if variant == 'scalar': target['data'] = None
        elif variant == 'missing-field': del target['data'][field]
        else: target['data'][field] = invalid
        name = 'invalid-fact-' + producer + '-' + variant
        result = complete_case(name, packets=encode_packets(values), omission='invalid-probe')
        assert any('probe-fact-payload-invalid:' + producer + ':' + kind in p for p in result['problems']), 'invalid-fact-distinguished'
        assert not any('probe-unparsed' in p or 'sequence-gap' in p for p in result['problems']), 'valid-envelope-keeps-continuity'
        assert result['factAvailability'][fact]['status'] == 'not-observed', 'invalid-fact-not-observed'
        observed = [e['data'] for e in events(fixture_directories[name]) if e['kind'] == 'probe-observation']
        assert json.dumps(observed, sort_keys=True) == json.dumps(values, sort_keys=True), 'invalid-fact-raw-retained'
print('  CONTROL display collector: source-encoded mixed payloads and distinct invalid envelope/fact/history/binding cases pass')

mutant('retirement', 'if not registration["required"]:', 'if False:', lambda source: many_stops('mut-retirement', source), 'completed-resource-retired')
mutant('required-before-events', 'if not registration["required"]:', 'if True:', lambda s: complete_case('mut-required', s), 'required-reader-retained')
mutant('snapshots-not-history', 'observed = self.fact_counts[(self.display_registration, producer, kind)]', 'observed = 1', lambda s: complete_case('mut-snapshot', s), 'samples-are-not-history')
mutant('scope-required', 'expected = self.scope is not None and self.scope["displayRequired"]', 'expected = False', lambda s: complete_case('mut-scope', s, omission='arm-boundary'), 'missing-or-lost-input-rejected')
mutant('event-cap', 'if not terminal and (self.events >= CAP_EVENTS or self.bytes + len(text) > CAP_BYTES):', 'if False:', lambda s: complete_case('mut-cap', s.replace('CAP_EVENTS = 65536', 'CAP_EVENTS = 3'), omission='overflow'), 'missing-or-lost-input-rejected')

# Mutations at the shared stop authority cover every caller using it.
def stop_mutation():
    needle = 'display_record_call owner-end "$observation_owner" "$stopped_pid" >/dev/null || true'
    assert harness_text.count(needle) == 1, 'owner-end-mutation-source'
    with server('mut-stop') as (directory, recorder, child, request):
        boundary(directory, recorder, source=harness_text.replace(needle, ':'))
        assert request('read')['activeStreams'] == 0, 'typed-stop-retires'
try:
    stop_mutation()
except AssertionError as error:
    assert str(error) == 'typed-stop-retires', ('wrong-stop-mutation', error)
    print('  CONTROL display collector: stop authority fails typed-stop-retires')
else:
    raise AssertionError('stop mutation survived')

# The actual spawn on recorder refusal preserves output, status and fresh
# PID. A failed original open clears stale identity before returning.
def spawn_failure(source, name):
    directory = root / name; directory.mkdir()
    helper = directory / 'launch.sh'
    helper.write_text(extract(source, 'spawn') + r'''
set -u
fixture=$1
pgids=()
display_record_call() { return 1; }
spawn_pid=stale
display_stream_kind=probe
status=0
spawn "$fixture/original.log" sh -c 'printf "stdout\n"; printf "stderr\n" >&2; exit 23' || status=$?
printf '%s\n' "$status" "$spawn_pid" "${pgids[0]:-missing}" >"$fixture/receipt"
if [[ $spawn_pid =~ ^[0-9]+$ ]]; then
  status=0
  wait "$spawn_pid" || status=$?
  printf '%s\n' "$status" >>"$fixture/receipt"
fi
spawn_pid=stale
display_stream_kind=probe
status=0
spawn "$fixture/absent/log" true || status=$?
printf '%s\n' "$status" "$spawn_pid" >>"$fixture/receipt"
''')
    result = subprocess.run(['bash', str(helper), str(directory)], env={'PATH': os.getenv('PATH')},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, ('spawn-fixture-runtime', result.stderr)
    receipt = (directory / 'receipt').read_text().splitlines()
    assert receipt[0] == '0' and receipt[1].isdigit() and receipt[1] == receipt[2], 'refusal-launch-preserved'
    assert receipt[3:] == ['23', '1', ''], 'refusal-status-and-stale-pid'
    assert (directory / 'original.log').read_bytes() == b'stdout\nstderr\n', 'refusal-output-preserved'
spawn_failure(harness_text, 'spawn-refused')
needle = '|| registration=refused'
assert harness_text.count(needle) == 1, 'spawn-refusal-mutation-source'
try:
    spawn_failure(harness_text.replace(needle, '|| return 1'), 'mut-spawn-refused')
except AssertionError as error:
    assert str(error) == 'refusal-launch-preserved', ('wrong-spawn-mutation', error)
    print('  CONTROL display collector: refusal fails refusal-launch-preserved')
else:
    raise AssertionError('refusal mutation survived')

# Execute actual caller scope logic before producer launch. Selection is
# supplied by the caller's existing judge, not rebuilt from notifications.
scope_helper = root / 'scope.sh'
scope_helper.write_text(extract(harness_text, 'display_record_scope') + r'''
set -u
source_repo=/fixture
self=$1
first_bar_runs=$2
qml_smoke_only=$3
qml_smoke_rows=(start displays-modes finish)
argv=(--rows "$qml_smoke_only")
qml_smoke_wanted() { [[ -z $qml_smoke_only || $qml_smoke_only == *",$1,"* ]]; }
display_record_call() { printf '%s\n' "$@" >&2; }
display_record_scope
''')
for caller, first, selected, role in (
    ('qml-smoke.sh', '', '', 'display-smoke'),
    ('qml-smoke.sh', '', ',start,', 'smoke-context'),
    ('qml-smoke.sh', '1', '', 'first-bar-context'),
    ('measure-shader.sh', '', '', 'shader-context'),
    ('sandbox-shots.sh', '', '', 'screenshot-context'),
    ('unknown.sh', '', '', 'unknown')):
    output = subprocess.run(['bash', str(scope_helper), '/fixture/scripts/' + caller, first, selected],
                            env={'PATH': os.getenv('PATH')}, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert output.stderr.decode().splitlines()[:2] == ['scope', role], 'declared-scope-before-events'
assert harness_text.index('display_record_close()') < harness_text.index('display_record_pid="$spawn_pid"'), 'partial-bootstrap-close-defined'
assert harness_text.index('display_record_finish()') < harness_text.index('display_record_pid="$spawn_pid"'), 'partial-bootstrap-finish-defined'

# Execute the actual client-failure receipt without a listening collector.
client_directory = fixture_directory('missing-control-client')
(client_directory / 'recorder.py').write_text(text)
client_helper = root / 'client-failure.sh'
client_helper.write_text(extract(harness_text, 'display_record_call') + r'''
set -u
display_record_dir=$1
display_record_call close 1 cleanup
''')
client_result = subprocess.run(['bash', str(client_helper), str(client_directory)],
                               env={'PATH': os.getenv('PATH')}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
assert client_result.returncode == 1 and (client_directory / 'request-failed').read_text() == 'close\n', 'actual-client-failure-receipt'

for name, first, again, refusal in (
    ('unknown', None, ['unknown', 'fixture', '0'], 'scope-unknown'),
    ('repeated', ['shader-context', 'fixture', '0'], ['shader-context', 'fixture', '0'], 'scope-repeated'),
    ('mismatch', None, ['display-smoke', 'fixture', '0'], 'scope-selection-mismatch')):
    with server('scope-' + name) as (directory, recorder, child, request):
        if first: request('scope', *first)
        request('scope', *again, error=refusal)
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
        assert 'control:' + refusal in terminal(directory)['problems'], 'invalid-scope-incomplete'
record, _ = local('missing-close')
record.stopping, record.stop_reason = True, 'normal'
record.run()
assert 'window-end:missing' in terminal(record.directory)['problems'], 'missing-close-incomplete'

# A newly adopted runner never inherits a missing expected registration.
def adoption_check(source):
    with server('mut-adoption', source) as (directory, recorder, child, request):
        boundary(directory, recorder, 'adopted')
        assert not request('read')['problems'], 'adoption-no-false-missing'
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
mutant('adoption-type', 'return dict(tag="unobserved-adoption", pid=pid, snapshot=snapshot,',
       'return dict(tag="expected-unverified", pid=pid, snapshot=snapshot,', adoption_check, 'adoption-no-false-missing')

def failed_start(name, source):
    directory = fixture_directory(name)
    helper = directory / 'start.sh'
    helper.write_text('\n'.join(extract(source, n) for n in ('spawn', 'start_shell')) + r'''
set -u
fixture=$1
pgids=() shell_env=() shell_start_words=()
cpu_some_us() { echo 0; }
now_ms() { echo 0; }
fail() { :; }
shell_answers() { :; }
display_record_call() { printf '%s\n' "$1 $2" >>"$fixture/marks"; }
spawn_pid=stale shell_pid=stale
status=0
start_shell "$fixture" "$fixture/absent/log" no-bar || status=$?
printf '%s\n' "$status" "$spawn_pid" "$shell_pid" >"$fixture/receipt"
''')
    result = subprocess.run(['bash', str(helper), str(directory)], env={'PATH': os.getenv('PATH')},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, ('start-fixture-runtime', result.stderr)
    assert (directory / 'receipt').read_text().splitlines() == ['1', '', ''], 'failed-start-clears-identities'
    assert 'mark shell-runner' not in (directory / 'marks').read_text(), 'failed-start-no-runner-binding'
failed_start('failed-start', harness_text)
needle = '    fail "start_shell: launch=failed log=$log"\n    return 1'
assert harness_text.count(needle) == 1, 'failed-start-mutation-source'
try:
    failed_start('mut-start', harness_text.replace(needle, needle.replace('return 1', ':')))
except AssertionError as error:
    assert str(error) == 'failed-start-clears-identities', ('wrong-start-mutation', error)
    print('  CONTROL display collector: failed start fails failed-start-clears-identities')
else:
    raise AssertionError('failed-start mutation survived')

# A missing stdout descriptor is not proof that a process disappeared.
def missing_stdout(source, name):
    source_file = root / (name + '.py'); source_file.write_text(source)
    api = runpy.run_path(str(source_file))
    # The child closes stdout itself and never execs again: while an exec is
    # in flight, /proc/PID/fd reads EACCES, which also reads as unavailable.
    child = 'import os, sys, time; os.close(1); sys.stderr.write("ready\\n"); sys.stderr.flush(); time.sleep(60)'
    with subprocess.Popen([sys.executable, '-c', child], stderr=subprocess.PIPE) as process:
        assert process.stderr.readline() == b'ready\n', 'closed-stdout-ready'
        try:
            assert api['process_binding'](str(process.pid))['status'] == 'unavailable', 'missing-stdout-is-unavailable'
        finally:
            process.terminate(); process.wait()
missing_stdout(text, 'closed-stdout')
mutant('closed-stdout-identity',
       'return dict(status="gone") if not path.exists() else dict(status="unavailable", error="identity-component-missing")',
       'return dict(status="gone")', lambda source: missing_stdout(source, 'mut-closed-stdout'), 'missing-stdout-is-unavailable')
record, _ = local('missing-wayland-producer')
assert 'wayland-producer:missing' in finish(record)['problems'], 'missing-wayland-producer-incomplete'

def terminal_reserve(source, name):
    record, api = local(name, source)
    record.scope['argv'] = ['x' * api['CAP_LINE']]
    result = finish(record)
    assert 'terminal:overflow' in result['problems'], 'terminal-reserve-incomplete'
    assert len((record.directory / 'events.jsonl').read_bytes().splitlines()[-1]) < api['CAP_LINE'], 'terminal-reserve-bounded'
terminal_reserve(text, 'terminal-reserve')
mutant('terminal-reserve', 'if terminal and len(text) > CAP_LINE:', 'if False:',
       lambda source: terminal_reserve(source, 'mut-terminal-reserve'), 'terminal-reserve-incomplete')
mutant('cost-prefix', 'prefixRecordEvents=self.events, prefixRecordBytes=self.bytes,',
       'prefixRecordEvents=self.events + 1, prefixRecordBytes=self.bytes,',
       lambda source: complete_case('mut-cost-prefix', source), 'cost-prefix-exact')

# Finalization preserves failed control requests and partial final output.
retained = fixture_directories['complete-zero']
for name in ('scratch', 'runtime', 'home'): (root / ('retain-' + name)).mkdir()
scratch = root / 'retain-scratch'
(scratch / 'original.log').write_bytes(b'original bytes without newline')
(scratch / 'alias.log').symlink_to(scratch / 'original.log')
module['retain_record'](str(retained), str(scratch), str(root / 'retain-runtime'), str(root / 'retain-home'))
assert (retained / 'logs/sandbox/original.log').read_bytes() == b'original bytes without newline'
assert not (retained / 'logs/sandbox/alias.log').exists()
for errors, expected in (('0', 'complete'), ('1', 'incomplete')):
    module['complete_record'](str(retained), errors)
    assert json.loads((retained / 'completeness.json').read_text())['localRecord'] == expected, 'finalizer-failure-incomplete'
(retained / 'request-failed').write_text('close\n')
module['complete_record'](str(retained), '0')
assert 'control:client-request-failed' in json.loads((retained / 'completeness.json').read_text())['problems'], 'lost-client-receipt-incomplete'
for name, data, problem in (('partial', b'{"kind":', 'record:partial-final-record'), ('missing', b'{}\n', 'record:terminal-missing'), ('malformed', b'invalid\n', 'record:unreadable')):
    path = root / ('bad-' + name); path.write_bytes(data)
    assert problem in module['read_record'](path)['problems'], 'partial-terminal-incomplete'
PY
then ok "display collector preserves streams and rejects missing, interrupted, partial, truncated and overflow records"; else fail "display collector contract"; fi

# The host window reader, scripts/smoke/host-window.sh, against the stub
# hyprctl's host world. Cases and controls have the shape of the capture
# helper's above.
window_helper="$repo/scripts/smoke/host-window.sh"
# shellcheck disable=SC2016
window_cases=(
  "a window on a monitor's active workspace is shown"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-41) == shown ]]' 0 ""
  "a window on a workspace no monitor shows is hidden"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-42) == hidden ]]' 0 ""
  "a window on a shown special workspace is shown"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-43) == shown ]]' 0 ""
  "a window on a hidden special workspace is hidden"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-44) == hidden ]]' 0 ""
  "a background group tab is hidden"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-45) == hidden ]]' 0 ""
  "a window listed without the keys the reader needs is unreadable"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; out="$(host_window_state stable-46)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "a stableId the host does not list is absent"
  'HYPRLAND_INSTANCE_SIGNATURE=x; [[ $(host_window_state stable-99) == absent ]]' 0 ""
  "no host instance is unreadable"
  's=0; out="$(host_window_state stable-41)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "a failed clients read is unreadable"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; mkdir -p "$D/bin"; cp -- "$T/bin/hyprctl" "$T/bin/host-clients.json" "$T/bin/host-monitors.json" "$D/bin/"; : >"$D/bin/fail-clients"; out="$(PATH="$D/bin:$PATH" host_window_state stable-41)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "a failed monitors read is unreadable"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; mkdir -p "$D/bin"; cp -- "$T/bin/hyprctl" "$T/bin/host-clients.json" "$T/bin/host-monitors.json" "$D/bin/"; : >"$D/bin/fail-monitors"; out="$(PATH="$D/bin:$PATH" host_window_state stable-41)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "nested host windows list only aquamarine clients"
  'HYPRLAND_INSTANCE_SIGNATURE=x; printf -v want "%s\n%s\n%s\n%s\n%s\n%s" "stable-41 pid=41 size=841x641 workspace=1 mapped=true" "stable-42 pid=42 size=842x642 workspace=3 mapped=true" "stable-43 pid=43 size=843x643 workspace=-98 mapped=true" "stable-44 pid=44 size=844x644 workspace=-99 mapped=true" "stable-45 pid=45 size=845x645 workspace=1 mapped=true" "stable-46 pid=46 size=846x646 workspace=1 mapped=true"; [[ $(host_nested_windows) == "$want" ]]' 0 ""
  "nested host windows exclude non-aquamarine clients"
  'HYPRLAND_INSTANCE_SIGNATURE=x; out="$(host_nested_windows)"; [[ $out != *"pid=47"* && $out != *ghostty* ]]' 0 ""
  "nested host windows without a host instance are unreadable"
  's=0; out="$(host_nested_windows)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "nested host windows with a failed clients read are unreadable"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; mkdir -p "$D/bin"; cp -- "$T/bin/hyprctl" "$T/bin/host-clients.json" "$T/bin/host-monitors.json" "$D/bin/"; : >"$D/bin/fail-clients"; out="$(PATH="$D/bin:$PATH" host_nested_windows)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "nested host windows missing stableId are unreadable"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; mkdir -p "$D/bin"; cp -- "$T/bin/hyprctl" "$T/bin/host-clients.json" "$T/bin/host-monitors.json" "$D/bin/"; python3 -c "import json,sys; p=sys.argv[1]; data=json.load(open(p)); del data[0]['\''stableId'\'']; json.dump(data, open(p, '\''w'\''))" "$D/bin/host-clients.json"; out="$(PATH="$D/bin:$PATH" host_nested_windows)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
  "nested host windows with a later window missing stableId print nothing else"
  'HYPRLAND_INSTANCE_SIGNATURE=x; s=0; mkdir -p "$D/bin"; cp -- "$T/bin/hyprctl" "$T/bin/host-clients.json" "$T/bin/host-monitors.json" "$D/bin/"; python3 -c "import json,sys; p=sys.argv[1]; data=json.load(open(p)); del data[2]['\''stableId'\'']; json.dump(data, open(p, '\''w'\''))" "$D/bin/host-clients.json"; out="$(PATH="$D/bin:$PATH" host_nested_windows)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
)
run_cases "$window_helper" window_cases
# shellcheck disable=SC2016
window_controls=(
  "the stableId is not matched"
  'c["stableId"] == stable_id' 'True' "a stableId the host does not list is absent"
  "an active workspace does not count as shown"
  '{m["activeWorkspace"]["id"] for m in monitors} | ' '' "a window on a monitor's active workspace is shown"
  "a shown special workspace does not count as shown"
  ' | {m["specialWorkspace"]["id"] for m in monitors}' '' "a window on a shown special workspace is shown"
  "a background group tab counts as shown"
  'c["visible"] and ' '' "a background group tab is hidden"
  "a reply without the expected keys is not caught"
  'except (ValueError, KeyError, TypeError):' 'except (ValueError, TypeError):' "a window listed without the keys the reader needs is unreadable"
  "a missing host instance is read"
  $'host_window_state() {\n  local clients monitors\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi' $'host_window_state() {\n  local clients monitors\n  true' "no host instance is unreadable"
  "a failed clients read is parsed"
  $'host_window_state() {\n  local clients monitors\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi\n  clients="$(timeout 2 hyprctl -j clients 2>/dev/null)" || { echo unreadable; return 1; }' $'host_window_state() {\n  local clients monitors\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi\n  clients="$(timeout 2 hyprctl -j clients 2>/dev/null)" || true' "a failed clients read is unreadable"
  "a failed monitors read is parsed"
  'monitors="$(timeout 2 hyprctl -j monitors 2>/dev/null)" || { echo unreadable; return 1; }' 'monitors="$(timeout 2 hyprctl -j monitors 2>/dev/null)" || true' "a failed monitors read is unreadable"
  "nested windows are not filtered by class"
  $'        if c["class"] != "aquamarine":\n            continue' $'        if False:\n            continue' "nested host windows list only aquamarine clients"
  "nested windows ignore a missing host instance"
  $'host_nested_windows() {\n  local clients\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi' $'host_nested_windows() {\n  local clients\n  true' "nested host windows without a host instance are unreadable"
  "nested windows parse a failed clients read"
  $'host_nested_windows() {\n  local clients\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi\n  clients="$(timeout 2 hyprctl -j clients 2>/dev/null)" || { echo unreadable; return 1; }' $'host_nested_windows() {\n  local clients\n  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then echo unreadable; return 1; fi\n  clients="$(timeout 2 hyprctl -j clients 2>/dev/null)" || true' "nested host windows with a failed clients read are unreadable"
  "nested windows missing stableId is not caught"
  'except (ValueError, KeyError, TypeError, IndexError):' 'except (ValueError, TypeError, IndexError):' "nested host windows missing stableId are unreadable"
  "nested windows print rows before the whole reply parses"
  $'        rows.append("%s pid=%s size=%sx%s workspace=%s mapped=%s" % (' $'        print("%s pid=%s size=%sx%s workspace=%s mapped=%s" % (' "nested host windows with a later window missing stableId print nothing else"
)
run_controls "$window_helper" window_cases window_controls

# The shot runner's reader of its own nested window: scripts/sandbox-shots.sh's
# nested_window_id and nested_window_state over the harness's
# host_windows_since and the real host-window.sh, against the stub host
# world. compositor_pid=2 is an in-fence pid the host lists for no window.
shots_window_helper="$tmp/shots-window-helper.sh"
{
  sed -n '/^host_windows_since() {/,/^}/p' "$repo/scripts/smoke/harness.sh"
  sed -n '/^nested_window_id() {/,/^}/p; /^nested_window_state() {/,/^}/p' "$repo/scripts/sandbox-shots.sh"
  cat -- "$window_helper"
} >"$shots_window_helper"
shots_window_setup='HYPRLAND_INSTANCE_SIGNATURE=x; compositor_pid=2; before() { host_nested_windows | grep -v -e "^$1 " -e "^${2:-none} "; }; '
# shellcheck disable=SC2016
shots_window_cases=(
  "the runner reads its new hidden host window by stableId"
  "$shots_window_setup"'host_windows_before="$(before stable-42)"; nested_window="$(nested_window_id)"; [[ $nested_window == stable-42 && $(nested_window_state) == hidden ]]' 0 ""
  "the runner reads its new shown host window by stableId"
  "$shots_window_setup"'host_windows_before="$(before stable-41)"; nested_window="$(nested_window_id)"; [[ $nested_window == stable-41 && $(nested_window_state) == shown ]]' 0 ""
  "the runner takes the first-made of several new host windows"
  "$shots_window_setup"'host_windows_before="$(before stable-41 stable-42)"; eval "listed_$(declare -f host_nested_windows)"; host_nested_windows() { listed_host_nested_windows | tac; }; nested_window="$(nested_window_id)"; [[ $nested_window == stable-41 && $(nested_window_state) == shown ]]' 0 ""
  "no new host window leaves the runner's window unreadable"
  "$shots_window_setup"'host_windows_before="$(host_nested_windows)"; s=0; nested_window="$(nested_window_id)" || s=$?; [[ $s -eq 1 ]] || exit 9; nested_window=""; s=0; out="$(nested_window_state)" || s=$?; [[ $out == unreadable && $s -eq 1 ]]' 0 ""
)
run_cases "$shots_window_helper" shots_window_cases
# shellcheck disable=SC2016
shots_window_controls=(
  "the runner keys its window on the in-fence pid"
  'host_window_state "$nested_window"' 'host_window_state "$compositor_pid"' "the runner reads its new hidden host window by stableId"
  "the runner takes the last-made of several new windows"
  '[[ -z $id || $entry < $id ]]' '[[ -z $id || $entry > $id ]]' "the runner takes the first-made of several new host windows"
  "the runner reads a window when none is new"
  '[[ $new != none ]] || return 1' 'true' "no new host window leaves the runner's window unreadable"
)
run_controls "$shots_window_helper" shots_window_cases shots_window_controls

# The harness names a nested backend start where aquamarine has announced
# neither the host pointer nor a host window for the nested compositor.
harness_helper="$tmp/harness-backend-helper.sh"
python3 - "$repo/scripts/smoke/harness.sh" "$harness_helper" <<'PY'
import sys
text = open(sys.argv[1]).read()
blocks = []
for name in ("host_windows_since", "nested_mice", "nested_backend_unannounced"):
    start = text.index(name + "() {")
    end = text.index("\n}\n", start) + 3
    blocks.append(text[start:end])
open(sys.argv[2], "w").write("\n".join(blocks))
PY
# shellcheck disable=SC2016,SC2034
harness_cases=(
  "backend unannounced accepts no wl_pointer and no host window"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n" "$host_windows_before"; }; hypr() { printf "%s\n" "{\"mice\":[]}"; }; nested_backend_unannounced; [[ $nested_mice_seen == none && $host_windows_new == none ]]' 0 ""
  "backend rejects wl_pointer"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n" "$host_windows_before"; }; hypr() { printf "%s\n" "{\"mice\":[{\"name\":\"wl_pointer\"}]}"; }; if nested_backend_unannounced; then exit 1; fi; [[ $nested_mice_seen == wl_pointer && $host_windows_new == none ]]' 0 ""
  "backend rejects a new host window"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n%s\n" "$host_windows_before" "new pid=2 size=2x2 workspace=2 mapped=true"; }; hypr() { printf "%s\n" "{\"mice\":[]}"; }; if nested_backend_unannounced; then exit 1; fi; [[ $nested_mice_seen == none && $host_windows_new == "new pid=2 size=2x2 workspace=2 mapped=true" ]]' 0 ""
  "backend rejects unreadable host windows"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { echo unreadable; return 1; }; hypr() { printf "%s\n" "{\"mice\":[]}"; }; if nested_backend_unannounced; then exit 1; fi; [[ $nested_mice_seen == none && $host_windows_new == unreadable ]]' 0 ""
  "backend rejects unreadable before windows"
  'host_pointer=wl_pointer; host_windows_before=unreadable; host_nested_windows() { echo unreadable; return 1; }; hypr() { printf "%s\n" "{\"mice\":[]}"; }; if nested_backend_unannounced; then exit 1; fi; [[ $nested_mice_seen == none && $host_windows_new == unreadable ]]' 0 ""
  "backend rejects unreadable devices"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n" "$host_windows_before"; }; hypr() { return 1; }; if nested_backend_unannounced; then exit 1; fi; [[ $nested_mice_seen == unreadable && $host_windows_new == unreadable ]]' 0 ""
  "backend accepts mouse name that only contains wl_pointer"
  'host_pointer=wl_pointer; host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n" "$host_windows_before"; }; hypr() { printf "%s\n" "{\"mice\":[{\"name\":\"wl_pointer-virtual\"}]}"; }; nested_backend_unannounced; [[ $nested_mice_seen == wl_pointer-virtual && $host_windows_new == none ]]' 0 ""
  "backend unannounced accepts a host that showed no nested window before"
  'host_pointer=wl_pointer; host_windows_before=""; host_nested_windows() { :; }; hypr() { printf "%s\n" "{\"mice\":[]}"; }; nested_backend_unannounced; [[ $nested_mice_seen == none && $host_windows_new == none ]]' 0 ""
  "host windows since prints only new windows"
  'host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n%s\n" "$host_windows_before" "new pid=2 size=2x2 workspace=2 mapped=false"; }; [[ $(host_windows_since) == "new pid=2 size=2x2 workspace=2 mapped=false" ]]' 0 ""
  "host windows since prints none"
  'host_windows_before="old pid=1 size=1x1 workspace=1 mapped=true"; host_nested_windows() { printf "%s\n" "$host_windows_before"; }; [[ $(host_windows_since) == none ]]' 0 ""
)
run_cases "$harness_helper" harness_cases
# shellcheck disable=SC2016,SC2034
harness_controls=(
  "backend ignores the host pointer"
  '[[ ,$nested_mice_seen, != *,"$host_pointer",* ]] || return 1' 'true || return 1' "backend rejects wl_pointer"
  "backend ignores new host windows"
  '[[ $host_windows_new == none ]] || return 1' 'true || return 1' "backend rejects a new host window"
  "backend treats unreadable host windows as none"
  'current="$(host_nested_windows)" || { echo unreadable; return 1; }' 'current="$(host_nested_windows)" || current=' "backend rejects unreadable host windows"
  "backend treats a substring mouse as the host pointer"
  '[[ ,$nested_mice_seen, != *,"$host_pointer",* ]] || return 1' '[[ $nested_mice_seen != *"$host_pointer"* ]] || return 1' "backend accepts mouse name that only contains wl_pointer"
  "an empty before-reading counts as unreadable"
  '${host_windows_before-unreadable}' '${host_windows_before:-unreadable}' "backend unannounced accepts a host that showed no nested window before"
)
run_controls "$harness_helper" harness_cases harness_controls

# Drive the real screensaver missing-tool branch and the real scene loop
# and verdict, without a compositor. Capture's scene stands for the frame
# producer; the test proves the runner still reaches it after screensaver.
scene_continuation_case() {
  local script="$1" dir status=0 out
  dir="$(mktemp -d "$tmp/scene-continuation.XXXXXX")" || return 1
  mkdir -p "$dir/bin" "$dir/shots"
  for tool in wc awk tr; do ln -s "$(command -v "$tool")" "$dir/bin/$tool"; done
  python3 - "$script" "$dir/runner.sh" <<'PY'
import sys
text = open(sys.argv[1]).read()
start = text.index('scene_screensaver() {')
end = text.index('\n# The setup each scene needs', start)
tail = text.index('# The first shot is the bare desktop;')
open(sys.argv[2], 'w').write(text[start:end] + '\n' + text[tail:])
PY
  : >"$dir/auth.log"
  env -i PATH="$dir/bin" "$BASH" -c '
    set -euo pipefail
    SHOT_DIR="$1/shots"
    auth_log="$1/auth.log"
    failures=0 undrawn=0 unmeasured=0
    mode_list=(dark)
    scenes=(screensaver capture)
    enable_ids=() disable_ids=()
    park_pointer() { :; }
    set_mode() { :; }
    scene_desktop() { :; }
    capture_state_record() { :; }
    take() { printf "frame\n" >"$SHOT_DIR/$1.png"; printf "%s\ts\tp\tsettled\thidden\tclean\n" "$1" >>"$SHOT_DIR/shots.tsv"; }
    scene_capture() { take "capture-$1-panel"; }
    ok() { :; }
    fail() { failures=$((failures + 1)); }
    source "$1/runner.sh"
  ' _ "$dir" >"$dir/out" 2>"$dir/err" || status=$?
  out="$(cat -- "$dir/out")"
  [[ $status -eq 77 && -e $dir/shots/capture-dark-panel.png && ! -e $dir/shots/screensaver-dark-cover.png \
    && $out == *'scene=screensaver mode=dark status=not-measured missing=ttfx'* ]]
}
if scene_continuation_case "$repo/scripts/sandbox-shots.sh"; then
  ok "without ttfx, Capture still runs after screensaver and the run exits 77"
else
  fail "without ttfx, Capture still runs after screensaver and the run exits 77"
fi
continuation_controls=(
  'the old whole-run exit stops later Capture' '    return 0' '    exit 77'
  'a missing scene becomes a passing run' '[[ $unmeasured -eq 0 ]] || exit 77' 'true'
)
for (( i = 0; i < ${#continuation_controls[@]}; i += 3 )); do
  label="${continuation_controls[i]}"; needle="${continuation_controls[i + 1]}"; replacement="${continuation_controls[i + 2]}"
  continuation_mutant="$tmp/continuation-mutant.sh"
  # Limit the return mutation to the missing-tool branch, leaving other
  # scenes and every statement after that branch unchanged.
  python3 - "$repo/scripts/sandbox-shots.sh" "$continuation_mutant" "$needle" "$replacement" <<'PY'
import sys
source, destination, needle, replacement = sys.argv[1:]
text = open(source).read()
if needle == '    return 0':
    start = text.index('scene_screensaver() {')
    end = text.index('\n  python3', start)
else:
    start, end = 0, len(text)
block = text[start:end]
assert block.count(needle) == 1
changed = block.replace(needle, replacement)
assert changed != block
open(destination, 'w').write(text[:start] + changed + text[end:])
PY
  if scene_continuation_case "$continuation_mutant"; then fail "control: $label stayed green"; else ok "control: $label"; fi
done

# Run the System scene's geometry wait against a compositor fixture. A
# queued layer reload reads the active Lua configuration after both readers
# agree, before capture. A stale service or unapplied rule prevents capture.
displays_geometry_case() { # SCRIPT
  local script="$1" dir status=0
  dir="$(mktemp -d "$tmp/displays-geometry.XXXXXX")" || return 1
  python3 - "$script" "$repo/scripts/smoke/harness.sh" "$dir/scene.sh" <<'PY'
import sys
text = open(sys.argv[1]).read()
harness = open(sys.argv[2]).read()
blocks = [text[text.index('system_shown() {'):text.index('\nsound_lists_player() {')]]
for start, end in [('py_reply() {', '\n# jarvis_ready'), ('expect() {', '\n# rescan LABEL'), ('hypr_lua_save() {', '\n# The key capture rows')]:
    offset = harness.index(start)
    blocks.append(harness[offset:harness.index(end, offset)])
shim_functions = [line for line in harness.splitlines() if line.startswith('shim_hyprctl() {')]
assert len(shim_functions) == 1
blocks.extend(shim_functions)
open(sys.argv[3], 'w').write('\n'.join(blocks))
PY
  cat >"$dir/monitor.py" <<'PY'
import json, re, sys
rules = open(sys.argv[1]).read()
monitors = []
for body in re.findall(r'hl\.monitor\(\{([^}]+)\}\)', rules):
    fields = dict(re.findall(r'(\w+)\s*=\s*("[^"]*"|-?[\d.]+)', body))
    if json.loads(fields['output']) != 'VGS-PLANTED-VRR':
        continue
    width, height = map(int, json.loads(fields['mode']).split('@')[0].split('x'))
    x, y = map(int, json.loads(fields['position']).split('x'))
    monitors = [dict(name='VGS-PLANTED-VRR', identifier='VGS-PLANTED-VRR',
                     width=width, height=height, x=x, y=y,
                     scale=float(fields['scale']), transform=int(fields['transform']))]
print(json.dumps(monitors))
PY
  env -i PATH="$PATH" D="$dir" bash -c '
    set -euo pipefail
    source "$D/scene.sh"
    sandbox="$D" home="$D/home" shim="$D/shim"
    mkdir -p "$home/.local/state/vgshell/plugins/vgs.displays" "$home/.config/hypr" "$shim"
    printf "#!/usr/bin/env bash\nexit 1\n" >"$shim/hyprctl.real"
    printf "%s\n" '\''hl.monitor({ output = "VGS-PLANTED-VRR", mode = "5120x2880@60", position = "1755x0", scale = 2, transform = 0 })'\'' >"$D/original.lua"
    cp "$D/original.lua" "$home/.config/hypr/hyprland.lua"
    ok() { :; }
    fail() { failures=$((failures + 1)); }
    reader_stderr() { [[ ! -s $2 ]]; }
    smoke_poll_tries() { smoke_poll_n=5; }
    sleep() { :; }
    ships_plugin() { [[ $1 == vgs.displays ]]; }
    devices_up() { :; }
    devices_system_tree() { echo fixture; }
    park_pointer() { :; }
    take() {
      if [[ $1 == *-displays ]]; then
        # Receipts prove agreement before the queued reload. No eval can
        # repair the configuration between that reload and capture.
        assert_geometry "$D/compositor-read" -1440 -620 1
        assert_geometry "$D/service-read" -1440 -620 1
        hypr reload config-only >/dev/null
        : >"$D/reloaded"
        cp "$D/compositor" "$D/captured-compositor"
        cp "$D/service" "$D/captured-service"
      fi
    }
    assert_geometry() {
      python3 - "$@" <<PY
import json, sys
m, = json.load(open(sys.argv[1]))
assert (m["width"], m["height"], m["x"], m["y"], m["scale"], m["transform"]) == (5120, 2880, int(sys.argv[2]), int(sys.argv[3]), 2, int(sys.argv[4]))
PY
    }
    load_config() {
      if [[ -e $D/output ]]; then
        python3 "$D/monitor.py" "$1" >"$D/compositor"
      else
        echo "[]" >"$D/compositor"
      fi
    }
    emit_output() {
      cp "$1" "$1-read"
      cat "$1"
    }
    ipc() {
      if [[ $* == "smoke instanceGeometry window vgs.system" ]]; then cat "$D/window"
      elif [[ $* == "smoke readInstance service vgs.displays outputs" ]]; then emit_output "$D/service"
      elif [[ $* == "shell summon window vgs.system "* ]]; then echo shown >"$D/window"; echo ok
      elif [[ $* == "shell hide window vgs.system" ]]; then echo absent >"$D/window"; echo ok
      elif [[ $* == *"focusInstance"* ]]; then echo focused
      else echo ok
      fi
    }
    hypr() {
      case "$*" in
        eval*)
          if [[ $scenario != blocked ]]; then
            printf "%s\n" "$2" >"$D/eval.lua"
            load_config "$D/eval.lua"
          fi
          echo eval >>"$D/evals"; echo ok ;;
        "-j monitors all") emit_output "$D/compositor" ;;
        "output create wayland VGS-PLANTED-VRR") : >"$D/output"; echo ok ;;
        "output remove VGS-PLANTED-VRR-READ")
          if [[ $scenario == reload && ! -e $D/reset ]]; then
            : >"$D/reset"; load_config "$D/original.lua"
          fi
          [[ $scenario == stale ]] || cp "$D/compositor" "$D/service"
          echo ok ;;
        "output remove VGS-PLANTED-VRR")
          rm "$D/output"; echo "[]" >"$D/compositor"; echo "[]" >"$D/service"; echo ok ;;
        "reload config-only")
          load_config "$home/.config/hypr/hyprland.lua"
          cp "$D/compositor" "$D/service"; echo ok ;;
        *) echo ok ;;
      esac
    }
    displays_listed() { echo 3; }
    window_panes() { echo "[\"vgs.displays\"]"; }
    for scenario in reload stale blocked; do
      failures=0
      rm -f -- "${D:?}/captured-compositor" "${D:?}/captured-service" "${D:?}/reloaded" "${D:?}/reset" "${D:?}/evals" "${D:?}/compositor-read" "${D:?}/service-read"
      : >"$D/output"
      load_config "$D/original.lua"; cp "$D/compositor" "$D/service"; echo absent >"$D/window"
      scene_system dark
      cmp "$shim/hyprctl.real" "$shim/hyprctl" || exit 1
      cmp "$D/original.lua" "$home/.config/hypr/hyprland.lua" || exit 1
      [[ $(cat "$D/compositor") == "[]" && $(cat "$D/service") == "[]" && ! -e $D/output ]] || exit 1
      if [[ $scenario == reload ]]; then
        [[ $failures == 0 && -e $D/reset && -e $D/reloaded ]] || exit 1
        assert_geometry "$D/captured-compositor" -1440 -620 1
        assert_geometry "$D/captured-service" -1440 -620 1
      else
        [[ $failures -gt 0 && ! -e $D/captured-compositor && ! -e $D/reloaded && -s $D/evals ]] || exit 1
      fi
      hypr output create wayland VGS-PLANTED-VRR >/dev/null
      hypr reload config-only >/dev/null
      assert_geometry "$D/compositor" 1755 0 0
      assert_geometry "$D/service" 1755 0 0
    done
  ' >"$dir/out" 2>"$dir/err" || status=$?
  [[ $status == 0 ]]
}
if displays_geometry_case "$repo/scripts/sandbox-shots.sh"; then
  ok "Displays keeps exact geometry across a reload after agreement, restores it, and refuses capture without agreement"
else
  fail "Displays keeps exact geometry across a reload after agreement, restores it, and refuses capture without agreement"
fi
displays_mutant="$tmp/displays-without-wait.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$displays_mutant" <<'PY'
import sys
text = open(sys.argv[1]).read()
lines = text.splitlines(keepends=True)
matches = [i for i, line in enumerate(lines) if 'expect_poll "displays-geometry-not-applied:' in line]
assert len(matches) == 1
lines[matches[0]] = '      :\n'
changed = ''.join(lines)
assert changed != text
open(sys.argv[2], 'w').write(changed)
PY
if displays_geometry_case "$displays_mutant"; then
  fail "control: Displays without its wait stayed green"
else
  ok "control: Displays without its wait fails geometry"
fi
displays_mutant="$tmp/displays-without-saved-rule.sh"
if mutate "$repo/scripts/sandbox-shots.sh" '      printf '\''%s\n'\'' "$displays_output_rule" >>"$home/.config/hypr/hyprland.lua"' '      :' "$displays_mutant"; then
  if displays_geometry_case "$displays_mutant"; then
    fail "control: Displays without its saved rule stayed green"
  else
    ok "control: Displays without its saved rule fails geometry after the queued reload"
  fi
else
  fail "control: Displays saved-rule mutation"
fi

# The scene choice of scripts/sandbox-shots.sh, before any sandbox starts:
# a tree ships either the Settings plugin or the bar's manager built-in, a
# plugin scene needs its plugins' manifests, and a scene the tree does not
# ship is refused with exit 2. A scratch git
# repository holds the script, a link to the smoke directory, a revision
# with the bar's manager and a later one with vgs.settings, so --rev reads
# an older tree. A scene the tree ships passes the choice and reaches the
# harness, which, with no Wayland socket in the environment, exits 77.
shots_repo="$tmp/shots-repo"
mkdir -p "$shots_repo/scripts" "$shots_repo/shell/plugins/vgs.bar" "$shots_repo/bin" "$shots_repo/config" "$shots_repo/themes" "$shots_repo/tmp"
ln -s "$repo/scripts/smoke" "$shots_repo/scripts/smoke"
: >"$shots_repo/shell/plugins/vgs.bar/Manager.qml"; : >"$shots_repo/bin/vgshell"; : >"$shots_repo/config/shell.json"; : >"$shots_repo/themes/.keep"
git_quiet() { git -C "$shots_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
cp -- "$repo/VERSION" "$repo/LICENSE" "$repo/README.md" "$shots_repo/"
git_quiet init -q
git_quiet add shell bin config themes VERSION LICENSE README.md
git_quiet commit -q -m manager
old_rev="$(git -C "$shots_repo" rev-parse HEAD)"
mkdir -p "$shots_repo/shell/plugins/vgs.settings" "$shots_repo/shell/plugins/vgs.themes" "$shots_repo/shell/plugins/vgs.polkit" "$shots_repo/shell/plugins/vgs.capture"
: >"$shots_repo/shell/plugins/vgs.settings/manifest.json"
# The checkout ships the theme browsers, so their scene reaches the theme
# card check; it ships no Dev Tools, whose scene is refused. It ships the
# polkit prompt, which the earlier revision does not.
: >"$shots_repo/shell/plugins/vgs.themes/manifest.json"
: >"$shots_repo/shell/plugins/vgs.polkit/manifest.json"
: >"$shots_repo/shell/plugins/vgs.capture/manifest.json"
git -C "$shots_repo" rm -q shell/plugins/vgs.bar/Manager.qml
git_quiet add shell
git_quiet commit -q -m settings
# The harness loads bin/lib/ipc-reply.sh from the checkout it runs in.
ln -s "$repo/bin/lib" "$shots_repo/bin/lib"
# Only the checkout's working tree holds the demo catalog package, so a
# catalog mode reads it with no --rev and finds it absent from a revision.
mkdir -p "$shots_repo/themes/catalog/demo"
printf '{ "schemaVersion": 1, "name": "demo", "tokens": {} }\n' >"$shots_repo/themes/catalog/demo/theme.json"
# scene_case SCRIPT LABEL STATUS LINE ARG...: SCRIPT run from the scratch
# repository gives STATUS and LINE on stderr, or with STATUS 77 a stdout
# line starting LINE. On a host with an amdgpu node the run enters
# scripts/smoke/gpu-fence.sh, whose proof lines come first on stderr and
# are not the script's. Where the fence could not make or prove its
# namespace no scene case measured anything: the suite prints
# `test-sandbox-shots: status=not-measured` with the fence's own line and
# exits 77.
scene_case() {
  local script="$1" label="$2" want_status="$3" want_line="$4" status=0 out err
  shift 4
  cp -- "$script" "$shots_repo/scripts/sandbox-shots.sh"
  out="$(env -i PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$shots_repo/scripts/sandbox-shots.sh" --out "$shots_repo/tmp/shots-$RANDOM$RANDOM" "$@" 2>"$tmp/scene.err")" || status=$?
  err="$(sed -n '/^gpu-fence: \(absent\|present\) path=/!{p;q}' "$tmp/scene.err")"
  if [[ $status -eq 77 && $err == "gpu-fence: status=not-measured "* ]]; then
    printf 'test-sandbox-shots: status=not-measured %s\n' "$err"
    exit 77
  fi
  if [[ $status -eq $want_status && ( $err == "$want_line" || ( $want_status -eq 77 && $out == "$want_line"* ) ) ]]; then return 0; fi
  echo "$label: exit=$status stderr=$err stdout=$(head -n 1 <<<"$out")"
  return 1
}
scene_cases=(
  "a checkout with the Settings plugin refuses the manager scene" 2 "sandbox-shots: refused: scene=manager tree=checkout" manager
  "a revision before the Settings plugin refuses the settings scene" 2 "sandbox-shots: refused: scene=settings tree=$old_rev" --rev "$old_rev" settings
  "a revision before the Settings plugin takes the manager scene" 77 "qml-smoke: status=not-measured" --rev "$old_rev" manager
  "a checkout with the Settings plugin takes the settings scene" 77 "qml-smoke: status=not-measured" settings
  "a checkout with the Settings plugin takes the plugin-pages scene" 77 "qml-smoke: status=not-measured" plugin-pages
  "a revision before the Settings plugin refuses the plugin-pages scene" 2 "sandbox-shots: refused: scene=plugin-pages tree=$old_rev" --rev "$old_rev" plugin-pages
  "a scale other than 1 or 2 is refused" 2 "sandbox-shots: refused: scale=3" --scale 3 settings
  "scale 2 is taken" 77 "qml-smoke: status=not-measured" --scale 2 settings
  "a theme card that is no catalog name is refused" 2 "sandbox-shots: refused: theme-card=../x" --theme-card ../x settings
  "a theme card the catalog lacks is refused" 2 "sandbox-shots: refused: theme-card=nosuch tree=checkout" --theme-card nosuch theme-browser
  "a checkout without the Dev Tools plugin refuses the devtools scene" 2 "sandbox-shots: refused: scene=devtools tree=checkout" devtools
  "a checkout with the polkit plugin takes the polkit scene" 77 "qml-smoke: status=not-measured" polkit
  "a revision without the polkit plugin refuses the polkit scene" 2 "sandbox-shots: refused: scene=polkit tree=$old_rev" --rev "$old_rev" polkit
  "a checkout without the Gallery plugin refuses the focus scene" 2 "sandbox-shots: refused: scene=focus tree=checkout" focus
  "a checkout with the Capture plugin takes the capture scene" 77 "qml-smoke: status=not-measured" capture
  "a revision without the Capture plugin refuses the capture scene" 2 "sandbox-shots: refused: scene=capture tree=$old_rev" --rev "$old_rev" capture
  "a checkout without the AI Usage plugin refuses the ai-usage scene" 2 "sandbox-shots: refused: scene=ai-usage tree=checkout" ai-usage
  "a checkout with a catalog package takes its mode" 77 "qml-smoke: status=not-measured" --modes catalog-demo settings
  "a revision without a catalog package refuses its mode" 2 "sandbox-shots: refused: mode=catalog-demo" --rev "$old_rev" --modes catalog-demo manager
  "a malformed enable list is refused" 2 "sandbox-shots: refused: enable=vgs.themes," --enable vgs.themes, settings
  "a revision without the polkit plugin refuses enabling it" 2 "sandbox-shots: refused: enable=vgs.polkit tree=$old_rev" --rev "$old_rev" --enable vgs.polkit manager
  "a checkout with the polkit plugin takes enabling it" 77 "qml-smoke: status=not-measured" --enable vgs.polkit,vgs.themes settings
  "a malformed disable list is refused" 2 "sandbox-shots: refused: disable=vgs.themes," --disable vgs.themes, settings
  "a revision without the polkit plugin refuses disabling it" 2 "sandbox-shots: refused: disable=vgs.polkit tree=$old_rev" --rev "$old_rev" --disable vgs.polkit manager
  "a checkout with the polkit plugin takes disabling it" 77 "qml-smoke: status=not-measured" --disable vgs.polkit,vgs.themes settings
  "a plugin cannot be enabled and disabled together" 2 "sandbox-shots: refused: state=vgs.themes reason=enabled-and-disabled" --enable vgs.themes --disable vgs.themes settings
)
# Each case is label, status, line, then its arguments up to the next case,
# counted by the arguments each row above carries.
scene_arity=(1 3 3 1 1 3 3 3 3 3 1 1 3 1 1 3 1 3 5 3 5 3 3 5 3 5)
# Where each case starts in scene_cases and how many arguments it takes, by
# label, for the controls below.
declare -A scene_at scene_argc
at=0
for n in "${!scene_arity[@]}"; do
  label="${scene_cases[at]}"; status="${scene_cases[at + 1]}"; line="${scene_cases[at + 2]}"
  scene_at[$label]=$at; scene_argc[$label]=${scene_arity[n]}
  args=("${scene_cases[@]:at + 3:${scene_arity[n]}}")
  at=$((at + 3 + ${scene_arity[n]}))
  if scene_case "$repo/scripts/sandbox-shots.sh" "$label" "$status" "$line" "${args[@]}"; then ok "$label"; else fail "$label"; fi
done
# Controls, four fields each: label, the refusal's text, which must match
# once, its replacement, and the refused case. A copy with that refusal
# planted away must send the case's arguments on to the harness, which
# exits 77 here, as the scenes the tree ships do; a copy that still refuses
# them, or fails for another reason, leaves the control red.
shots_controls=(
  "an unshipped scene is not refused"
  "  if ! scene_ships \"\$scene\"; then" "  if false; then"
  "a checkout with the Settings plugin refuses the manager scene"
  "the manager's scene is not read"
  "    settings|manager) [[ \$1 == \"\$manager_scene\" ]] ;;" "    settings|manager) true ;;"
  "a checkout with the Settings plugin refuses the manager scene"
  "a scene's plugin is not looked for"
  "[[ -f \$tree/shell/plugins/\$id/manifest.json ]] || return 1" "true || return 1"
  "a checkout without the Dev Tools plugin refuses the devtools scene"
  "the polkit scene's plugin is not looked for"
  "    polkit) ships_plugin vgs.polkit ;;" "    polkit) true ;;"
  "a revision without the polkit plugin refuses the polkit scene"
  "a refused scale goes on to the harness"
  "refused: scale=%s\\n' \"\$scale\" >&2; exit 2; }" "refused: scale=%s\\n' \"\$scale\" >&2; }"
  "a scale other than 1 or 2 is refused"
  "a refused theme card goes on to the harness"
  "refused: theme-card=%s\\n' \"\$theme_card\" >&2; exit 2; }" "refused: theme-card=%s\\n' \"\$theme_card\" >&2; }"
  "a theme card that is no catalog name is refused"
  "a theme card the catalog lacks goes on to the harness"
  "if [[ \$scene == theme-browser && ! -f \$tree/themes/catalog/\$theme_card/theme.json ]]; then" "if false; then"
  "a theme card the catalog lacks is refused"
  "a catalog mode is looked for in the checkout"
  "-f \$tree/themes/catalog/\${mode#catalog-}/theme.json" "-f \$checkout/themes/catalog/\${mode#catalog-}/theme.json"
  "a revision without a catalog package refuses its mode"
  "a malformed enable list goes on to the harness"
  "refused: enable=%s\\n' \"\$enable_arg\" >&2; exit 2; }" "refused: enable=%s\\n' \"\$enable_arg\" >&2; }"
  "a malformed enable list is refused"
  "an enable id is not looked for in the tree"
  "ships_plugin \"\$id\" || { printf 'sandbox-shots: refused: enable=" "true || { printf 'sandbox-shots: refused: enable="
  "a revision without the polkit plugin refuses enabling it"
)
shots_mutant="$tmp/sandbox-shots-mutant.sh"
for (( i = 0; i < ${#shots_controls[@]}; i += 4 )); do
  label="${shots_controls[i]}"; target="${shots_controls[i + 3]}"
  if [[ -z ${scene_at[$target]+set} ]]; then fail "control: $label names no case: $target"; continue; fi
  args=("${scene_cases[@]:${scene_at[$target]} + 3:${scene_argc[$target]}}")
  if python3 -c '
import sys
src, dst, needle, replacement = sys.argv[1:]
text = open(src).read()
assert text.count(needle) == 1, "the refusal must match once"
open(dst, "w").write(text.replace(needle, replacement))' "$repo/scripts/sandbox-shots.sh" "$shots_mutant" "${shots_controls[i + 1]}" "${shots_controls[i + 2]}"; then
    if scene_case "$shots_mutant" "control: $label" 77 "qml-smoke: status=not-measured" "${args[@]}"; then ok "control: $label"; else fail "control: $label did not take '$target' on to the harness"; fi
  else
    fail "control: $label could not be planted"
  fi
done

# The Gallery title comes from the tree in the sandbox. Read the same
# helper block without starting the harness, against old and current
# snapshot fixtures. A fixed title must fail one of these readings.
gallery_reader="$tmp/gallery-reader.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$gallery_reader" <<'PY'
import sys
text = open(sys.argv[1]).read()
start = text.index('summoned_kind() {')
end = text.index('settings_kind=panel', start)
open(sys.argv[2], 'w').write(text[start:end])
PY
gallery_title_case() { # READER
  local reader="$1" root="$tmp/gallery-title" title surface
  mkdir -p "$root/shell/plugins/vgs.gallery"
  for title in Gallery 'VGS Components'; do
    python3 - "$root/shell/plugins/vgs.gallery/manifest.json" "$title" <<'PY'
import json, sys
with open(sys.argv[1], 'w') as out:
    json.dump({'name': sys.argv[2], 'kinds': ['window']}, out)
PY
    surface="$(env -i PATH="$PATH" bash -c 'set -euo pipefail; tree="$1"; fail() { exit 1; }; source "$2"; printf "%s" "$gallery_surface"' _ "$root" "$reader")" || return 1
    [[ $surface == "window:$title" ]] || return 1
  done
}
if gallery_title_case "$gallery_reader"; then ok "Gallery reads the title of each snapshot"; else fail "Gallery reads the title of each snapshot"; fi
gallery_mutant="$tmp/gallery-fixed-title.sh"
if python3 - "$gallery_reader" "$gallery_mutant" <<'PY'
import sys
text = open(sys.argv[1]).read()
needle = 'gallery_surface="$(summoned_surface "$gallery_kind" "$gallery_name")"'
assert text.count(needle) == 1, 'the title control must match once'
open(sys.argv[2], 'w').write(text.replace(needle, 'gallery_surface="$(summoned_surface "$gallery_kind" "VGS Components")"'))
PY
then
  if gallery_title_case "$gallery_mutant"; then fail "control: a fixed Gallery title stayed green"; else ok "control: a fixed Gallery title fails an older snapshot"; fi
else
  fail "control: a fixed Gallery title could not be planted"
fi

# A current revision exports its runtime helpers in bin/lib, its Jarvis base
# package and its installer files. The harness copies this revision's product
# files and this checkout's smoke scripts, without starting a compositor.
helper_repo="$tmp/helper-repo"
mkdir -p "$helper_repo/bin/lib" "$helper_repo/shell" "$helper_repo/config" "$helper_repo/themes" "$helper_repo/packaging/jarvis-home"
printf 'revision persona\n' >"$helper_repo/packaging/jarvis-home/persona.md"
printf 'module.exports = { where: "bin/lib" };\n' >"$helper_repo/bin/lib/qml-library.js"
printf 'process.stdout.write(require(require("path").join(__dirname, "lib", "qml-library.js")).where);\n' >"$helper_repo/bin/judge"
: >"$helper_repo/shell/shell.qml"; : >"$helper_repo/config/shell.json"; : >"$helper_repo/themes/.keep"
for file in VERSION LICENSE README.md; do printf 'revision %s\n' "$file" >"$helper_repo/$file"; done
helper_git() { git -C "$helper_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
helper_git init -q
helper_git add -A
helper_git commit -q -m product
product_rev="$(git -C "$helper_repo" rev-parse HEAD)"
harness_copy_case() { # LIB
  local lib="$1" dir target out status=0
  dir="$tmp/harness-export"; target="$tmp/harness-copy"
  rm -rf -- "${dir:?}" "${target:?}"
  mkdir -p -- "$dir" "$target"
  out="$({
    source "$lib"
    tree_export "$helper_repo" "$product_rev" "$dir" || { echo "tree_export failed"; exit 1; }
    tree_harness_copy "$repo" "$target" "$dir"
    [[ -e "$target/packaging/install-system.sh" ]] || { echo "packaging missing"; exit 1; }
    [[ -e "$target/scripts/qml-smoke.sh" ]] || { echo "scripts missing"; exit 1; }
    [[ $(node "$target/bin/judge") == bin/lib ]] || { echo "runtime helper missing"; exit 1; }
    cmp -s -- "$helper_repo/packaging/jarvis-home/persona.md" "$target/packaging/jarvis-home/persona.md" || { echo "revision base package missing"; exit 1; }
    for file in VERSION LICENSE README.md; do
      cmp -s -- "$helper_repo/$file" "$target/$file" || { echo "revision file missing: $file"; exit 1; }
    done
    echo ok
  } 2>&1)" || status=$?
  [[ $status -eq 0 && $out == ok ]] && return 0
  echo "exit=$status out=$(head -n 1 <<<"$out")"
  return 1
}
if harness_copy_case "$repo/scripts/smoke/tree.sh"; then ok "the harness copies the revision's product and current smoke scripts"; else fail "the harness copies the revision's product and current smoke scripts"; fi
# A control copies the wrong revision's installer files.
copy_mutant="$tmp/tree-copy-mutant.sh"
if python3 - "$repo/scripts/smoke/tree.sh" "$copy_mutant" <<'PYCONTROL'
import sys
src, dst = sys.argv[1:]
text = open(src).read()
needle = 'origin = tree / file_name'
assert text.count(needle) == 1, "installer file source must match once"
open(dst, "w").write(text.replace(needle, 'origin = source / file_name'))
PYCONTROL
then
  if harness_copy_case "$copy_mutant" >/dev/null; then fail "control: wrong revision installer files stayed green"; else ok "control: wrong revision installer files fail"; fi
else
  fail "control: wrong revision installer files could not be planted"
fi
# A control exports no base package, and one copies the checkout's.
package_controls=(
  'a revision exported without its base package|package+=("$at")|:'
  'the checkout base package|shutil.copytree(tree / package, target / package)|shutil.copytree(source / package, target / package)'
)
for spec in "${package_controls[@]}"; do
  IFS='|' read -r label needle replacement <<<"$spec"
  if ! mutate "$repo/scripts/smoke/tree.sh" "$needle" "$replacement" "$copy_mutant"; then
    fail "control: $label could not be planted"
  elif harness_copy_case "$copy_mutant" >/dev/null; then
    fail "control: $label stayed green"
  else
    ok "control: $label fails"
  fi
done

# With --rev, a shot's catalog package is the revision's: preview_package
# and set_mode read the sandbox copy the harness made, which outlives the
# export it came from. A scratch repository commits REV's package values
# and its working tree, the checkout, holds others; the real functions run
# against the sandbox copy after the export is removed, without a harness.
catalog_repo="$tmp/catalog-repo"
mkdir -p "$catalog_repo/shell" "$catalog_repo/bin" "$catalog_repo/config" \
  "$catalog_repo/themes/catalog/demo/targets/ghostty" "$catalog_repo/themes/catalog/flexoki-light"
: >"$catalog_repo/shell/shell.qml"; : >"$catalog_repo/bin/vgshell"; : >"$catalog_repo/config/shell.json"
for file in VERSION LICENSE README.md; do printf '%s\n' "$file" >"$catalog_repo/$file"; done
# catalog_plant VALUE: every catalog file the shot reads holds VALUE.
catalog_plant() {
  printf '{"name": "demo", "value": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/demo/theme.json"
  printf '{"background": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/demo/terminal.json"
  printf '%s\n' "$1" >"$catalog_repo/themes/catalog/demo/targets/ghostty/theme"
  printf '{"name": "flexoki-light", "value": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/flexoki-light/theme.json"
}
catalog_plant rev
catalog_git() { git -C "$catalog_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
catalog_git init -q
catalog_git add -A
catalog_git commit -q -m rev
catalog_rev="$(git -C "$catalog_repo" rev-parse HEAD)"
catalog_plant checkout
catalog_export="$tmp/catalog-export"; catalog_sandbox="$tmp/catalog-sandbox"
mkdir -p -- "$catalog_export" "$catalog_sandbox"
(
  source "$repo/scripts/smoke/tree.sh"
  tree_export "$catalog_repo" "$catalog_rev" "$catalog_export" &&
  tree_harness_copy "$repo" "$catalog_sandbox" "$catalog_export"
) || fail "the catalog revision could not be exported and copied"
rm -rf -- "${catalog_export:?}"
printf 'wallpaper\n' >"$tmp/catalog-wallpaper.png"
# catalog_extract NAME FILE: the body of the function NAME in sandbox-shots.sh.
catalog_extract() {
  python3 - "$repo/scripts/sandbox-shots.sh" "$1" "$2" <<'PY'
import sys
src, name, dst = sys.argv[1:]
text = open(src).read()
start_marker = name + "() {"
assert text.count(start_marker) == 1, name + " must be defined once"
start = text.index(start_marker)
end = text.index("\n}\n", start) + 3
open(dst, "w").write(text[start:end])
PY
}
# catalog_mutant SRC DST COUNT NEEDLE: SRC with its COUNT reads of NEEDLE
# pointed back at the checkout's catalog.
catalog_mutant() {
  python3 - "$@" <<'PY'
import sys
src, dst, count, needle = sys.argv[1:]
text = open(src).read()
assert text.count(needle) == int(count), "catalog reads must match %s times" % count
changed = text.replace(needle, needle.replace("$repo/", "$checkout/"))
assert changed != text
open(dst, "w").write(changed)
PY
}
# catalog_run FUNCTIONS SCRIPT: SCRIPT in a clean bash with the extracted
# FUNCTIONS, repo the sandbox copy and checkout the scratch working tree.
catalog_run() {
  local home
  home="$(mktemp -d "$tmp/catalog-home.XXXXXX")" || return 1
  env -i PATH="$PATH" "$BASH" -c '
    set -euo pipefail
    repo="$1" checkout="$2" home="$3"
    declare -A preview_wallpaper=([demo]="$4")
    theme_file="$home/.config/vgshell/theme.json"
    mkdir -p -- "$home/.config/vgshell"
    expect_poll() { :; }
    source "$5"
    eval "$6"
  ' _ "$catalog_sandbox" "$catalog_repo" "$home" "$tmp/catalog-wallpaper.png" "$1" "$2"
}
# preview_case FUNCTIONS: the installed demo package holds REV's values.
preview_case() {
  catalog_run "$1" '
    preview_package demo
    dest="$home/.config/vgshell/themes/demo"
    [[ $(<"$dest/terminal.json") == "{\"background\": \"rev\"}" ]]
    [[ $(<"$dest/theme.json") == "{\"name\": \"demo\", \"value\": \"rev\"}" ]]
    [[ $(<"$dest/targets/ghostty/theme") == rev ]]
  '
}
# mode_case FUNCTIONS MODE NAME: MODE publishes REV's theme.json of NAME.
mode_case() {
  catalog_run "$1" "set_mode $2; [[ \$(<\"\$theme_file\") == '{\"name\": \"$3\", \"value\": \"rev\"}' ]]"
}
preview_reader="$tmp/preview-package.sh"
mode_reader="$tmp/set-mode.sh"
catalog_extract preview_package "$preview_reader"
catalog_extract set_mode "$mode_reader"
if preview_case "$preview_reader"; then ok "a revision's preview package holds its catalog values"; else fail "a revision's preview package holds its catalog values"; fi
if mode_case "$mode_reader" catalog-demo demo; then ok "a revision's catalog mode holds its catalog values"; else fail "a revision's catalog mode holds its catalog values"; fi
if mode_case "$mode_reader" light flexoki-light; then ok "a revision's light mode holds its catalog values"; else fail "a revision's light mode holds its catalog values"; fi
catalog_controls=(
  "preview package reads the checkout's catalog|$preview_reader|5|\$repo/themes/catalog|preview_case|"
  "catalog mode reads the checkout's catalog|$mode_reader|1|\"\$repo/themes/catalog/\${1#catalog-}/theme.json\"|mode_case|catalog-demo demo"
  "light mode reads the checkout's catalog|$mode_reader|1|\"\$repo/themes/catalog/flexoki-light/theme.json\"|mode_case|light flexoki-light"
)
for spec in "${catalog_controls[@]}"; do
  IFS='|' read -r label reader count needle check check_args <<<"$spec"
  catalog_mutant_file="$tmp/catalog-mutant.sh"
  read -r -a check_args <<<"$check_args"
  if ! catalog_mutant "$reader" "$catalog_mutant_file" "$count" "$needle"; then
    fail "control: $label could not be planted"
  elif "$check" "$catalog_mutant_file" "${check_args[@]}"; then
    fail "control: $label stayed green"
  else
    ok "control: $label"
  fi
done

# The same observer setup instruments a source copy and an installed copy.
# Drive its actual file edits without starting QML or a compositor.
observer_case() {
  local tree_helper="$1" target count
  target="$(mktemp -d "$tmp/observer.XXXXXX")" || return 1
  mkdir -p "$target/shell/Core" "$target/shell/Hosts" &&
  cp -- "$repo/shell/shell.qml" "$target/shell/shell.qml" &&
  cp -- "$repo/shell/Core/Config.qml" "$target/shell/Core/Config.qml" &&
  cp -- "$repo/shell/Hosts/BackgroundHost.qml" "$target/shell/Hosts/BackgroundHost.qml" &&
  env -i PATH="/usr/bin:/bin" HOME="$tmp" "$BASH" -c '
    set -euo pipefail
    source "$1"
    tree_smoke_observer "$2" "$3"
  ' _ "$tree_helper" "$repo" "$target" &&
  cmp -s -- "$repo/scripts/smoke/Probe.qml" "$target/shell/Probe.qml" || return 1
  count="$(grep -Fc '    Probe {}' "$target/shell/shell.qml")" || return 1
  [[ $count == 1 ]] || return 1
  count="$(grep -Fc 'property alias smokeUserView: userView' "$target/shell/Core/Config.qml")" || return 1
  [[ $count == 1 ]] || return 1
  count="$(grep -Fc 'onBrokenKeysChanged: console.info("smoke: backgroundFailures="' "$target/shell/Hosts/BackgroundHost.qml")" || return 1
  [[ $count == 1 ]]
}
if observer_case "$repo/scripts/smoke/tree.sh"; then
  ok "the shared observer instruments a disposable runtime tree"
else
  fail "the shared observer instruments a disposable runtime tree"
fi
observer_controls=(
  'the root gets no probe|    Probe {}|    QtObject {}'
  'the user view gets no readable alias|property alias smokeUserView:|property alias unusedUserView:'
  'background failures get no observer|onBrokenKeysChanged:|onParentChanged:'
)
for spec in "${observer_controls[@]}"; do
  IFS='|' read -r label needle replacement <<<"$spec"
  observer_mutant="$tmp/observer-mutant.sh"
  if ! mutate "$repo/scripts/smoke/tree.sh" "$needle" "$replacement" "$observer_mutant"; then
    fail "control: $label could not be planted"
  elif observer_case "$observer_mutant" >/dev/null; then
    fail "control: $label left the observer setup green"
  else
    ok "control: $label"
  fi
done

# The harness names a missing ImageMagick among its prerequisites, since the
# notifications row and the Slack scene draw converted emoji: with no tool
# on PATH its not-measured line lists magick, and a copy without the check
# leaves it out.
# harness_missing HARNESS: the harness's missing list with an empty PATH.
harness_missing() {
  local out status=0
  out="$(env -i PATH="$tmp/no-tools" HOME="$tmp" "$BASH" -c 'repo="$1"; source "$2"' _ "$repo" "$1" 2>/dev/null)" || status=$?
  [[ $status -eq 77 ]] || { echo "exit=$status"; return; }
  sed -n 's/^qml-smoke: status=not-measured missing=//p' <<<"$out"
}
mkdir -p "$tmp/no-tools"
has_magick() { tr ',' '\n' <<<"$1" | grep -qx magick; }
got="$(harness_missing "$repo/scripts/smoke/harness.sh")"
if has_magick "$got"; then ok "the harness names a missing ImageMagick"; else fail "the harness names a missing ImageMagick: got $got"; fi
harness_mutant="$tmp/harness-mutant.sh"
needle='|| missing+=("magick")'
if [[ $(grep -cF -- "$needle" "$repo/scripts/smoke/harness.sh") -eq 1 ]]; then
  text="$(<"$repo/scripts/smoke/harness.sh")"
  printf '%s\n' "${text/"$needle"/|| true}" >"$harness_mutant"
  got="$(harness_missing "$harness_mutant")"
  if has_magick "$got"; then fail "control: a harness without the ImageMagick check still names it"; else ok "control: a harness without the ImageMagick check leaves it out"; fi
else
  fail "control: the ImageMagick check could not be planted"
fi

# Drive the Power scene's setup order without starting a sandbox. The
# plugin check must read a scan made after the fake daemon owns its name.
power_scene="$tmp/power-scene.sh"
catalog_extract scene_power "$power_scene"
power_scene_case() {
  env -i PATH="$PATH" "$BASH" -c '
    set -euo pipefail
    source "$1"
    devices_ready() { :; }
    power_start_mocks() { daemon=up; }
    tree_rescan() { [[ ${daemon:-} == up ]] && scanned=yes; }
    ipc() {
      if [[ $* == "shell setPluginEnabled vgs.power true" ]]; then
        [[ ${daemon:-} == up && ${scanned:-} == yes ]] || return 1
      fi
      echo ok
    }
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")"; [[ $got == "$want" ]]; }
    expect_poll() { :; }
    power_add_battery() { echo /org/freedesktop/UPower/devices/mock_BAT0; }
    notice_shown() { echo null; }
    power_discharging() { :; }
    power_no_battery() { :; }
    park_pointer() { :; }
    click_centre() { :; }
    bar_key() { echo bar; }
    notes_on() { :; }
    notes_clear() { :; }
    notes_off() { :; }
    power_stop_mocks() { :; }
    fail() { exit 1; }
    take() { printf "%s\n" "$1"; }
    scene_power dark
  ' _ "$1" >"$tmp/power-scene.out" &&
    [[ $(<"$tmp/power-scene.out") == $'power-dark-bar\npower-dark-panel\npower-dark-notice-low\npower-dark-notice-critical\npower-dark-panel-no-battery' ]]
}
if power_scene_case "$power_scene"; then ok "Power scans its fake daemon before enable and captures both notices and its panel with no battery"; else fail "Power scene order or captures failed"; fi
power_mutant="$tmp/power-scene-mutant.sh"
for defect in no-scan late-daemon; do
  python3 - "$power_scene" "$power_mutant" "$defect" <<'PYCONTROL'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '  tree_rescan "the Power shots\' fake daemon is scanned"\n' if sys.argv[3] == 'no-scan' else '  power_start_mocks shots-power balanced\n'
assert text.count(needle) == 1
changed = text.replace(needle, '')
if sys.argv[3] == 'late-daemon':
    at = '  expect "Power enables for its shot" ok ipc shell setPluginEnabled vgs.power true\n'
    assert changed.count(at) == 1
    changed = changed.replace(at, at + needle)
assert changed != text
pathlib.Path(sys.argv[2]).write_text(changed)
PYCONTROL
  if power_scene_case "$power_mutant"; then fail "control: Power $defect stayed green"; else ok "control: Power $defect fails"; fi
done

# Drive the capture state owner against a published shell world. Windows
# and panes are enabled without an instance. The probe initially owns lock,
# Jarvis enablement adds a required-tool notice, and fixture preparation has
# left the requested off plugins on. No compositor or authentication runs.
capture_state_case() { # SCRIPT
  local dir
  dir="$(mktemp -d "$tmp/capture-state.XXXXXX")" || return 1
  mkdir -p "$dir/home/.config/vgshell/plugins/acme.probe" "$dir/shots"
  cp -- "$repo/scripts/smoke/fixtures/plugins/acme.probe/manifest.json" "$dir/home/.config/vgshell/plugins/acme.probe/"
  printf '{"version":2,"plugins":[]}\n' >"$dir/home/.config/vgshell/shell.json"
  python3 - "$1" "$repo/scripts/smoke/harness.sh" "$dir/helpers.sh" <<'PY'
import pathlib,sys
script,harness,dst=map(pathlib.Path,sys.argv[1:])
parts=[]
for source,names in ((script,("capture_probe_release","capture_plugin_states","capture_state_record","page_state_record","lock_row_quiet","scene_desktop","close_notices","notice_plugin","notice_moved_from")),(harness,("py_reply","notice_shown"))):
    text=source.read_text()
    for name in names:
        start=text.index(name+"() {")
        # One-line readers end on their declaration line.
        line_end=text.index("\n",start)
        if text[start:line_end].rstrip().endswith("}"): end=line_end
        else: end=text.index("\n}\n",start)+3
        parts.append(text[start:end])
dst.write_text("\n".join(parts))
PY
  cat >"$dir/world.py" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); op=sys.argv[2]; args=sys.argv[3:]
file=root/"world.json"
if op=="plant":
    rows={}
    for id,kinds,on in (("vgs.gallery",["window"],False),("vgs.fonts",["pane"],False),("vgs.lock",["service"],False),("vgs.jarvis",["service"],False),("vgs.notifications",["service"],True),("vgs.devtools",["service","window"],True),("vgs.themes",["service","background"],True),("vgs.bar",["bar","service"],True),("acme.probe",["service"],True)):
        rows[id]={"id":id,"enabled":on,"kinds":kinds,"requirements":[],"settings":{"model":"fixture-model","localTier":"small"},"settingChoices":{},"status":[],"errors":[]}
    file.write_text(json.dumps({"rows":rows,"notices":["fixture."+str(i) for i in range(5)]}))
    sys.exit(0)
world=json.loads(file.read_text()); rows=world["rows"]; notices=world["notices"]
if op=="set":
    id,on=args; rows[id]["enabled"]=on=="true"
    if id=="vgs.jarvis" and on=="true": notices.append(id)
    file.write_text(json.dumps(world)); print("ok")
elif op=="enabled": print(rows[args[0]]["enabled"])
elif op=="built":
    row=rows[args[0]]
    print(row["enabled"] and "service" in row["kinds"] and not (row["id"]=="vgs.lock" and rows["acme.probe"]["enabled"]))
elif op=="list": print(json.dumps({"plugins":list(rows.values())}))
elif op=="manager": print(json.dumps(list(rows.values())))
elif op=="lent": print(json.dumps({"notices":{"shown":None if not notices else {"plugin":notices[0],"commands":["missing-tool"],"required":True,"installing":False},"waiting":notices[1:]}}))
elif op=="layer": print(int(bool(notices)))
elif op=="escape":
    if not notices: sys.exit(1)
    notices.pop(0); file.write_text(json.dumps(world))
PY
  python3 "$dir/world.py" "$dir" plant || return 1
  env -i PATH="$PATH" "$BASH" -c '
    set -euo pipefail
    at="$1" repo="$2" checkout="$2" home="$1/home" SHOT_DIR="$1/shots" capture_source=fixture-sha settings_kind=window main_name=WAYLAND-1
    node_bin="$(command -v node)"
    enable_ids=(vgs.gallery vgs.fonts vgs.lock vgs.jarvis)
    disable_ids=(vgs.notifications vgs.devtools vgs.themes vgs.bar)
    world() { python3 "$at/world.py" "$at" "$@"; }
    ipc() {
      case "$*" in
        "shell listShellConfig") printf "{\"bar\":{\"id\":\"vgs.bar\"}}\n" ;;
        "shell setPluginEnabled "*) world set "$3" "$4" ;;
        "shell listPlugins") world list ;;
        "shell lent") world lent ;;
        "smoke readInstance window vgs.settings plugins") world manager ;;
        "smoke themeName") printf "%s\n" "$mode_theme" ;;
        "smoke noticeFocused") echo true ;;
        *) exit 2 ;;
      esac
    }
    plugin_enabled() { world enabled "$1"; }
    record_exists() { world built "$1"; }
    layer_count() { world layer; }
    type_keys() { [[ $* == "-k Escape" ]] && world escape; }
    fail() { echo "$*" >&2; exit 1; }
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")" && [[ $got == "$want" ]] || fail "$label: $got != $want"; }
    expect_poll() { expect "$@"; }
    pixel() { echo 112233; }
    bg_state_names() { :; }
    background_image_on() { fail "an off Themes service was read"; }
    source "$at/helpers.sh"
    lock_row_quiet
    for mode_theme in vgs flexoki-light; do
      capture_plugin_states "$mode_theme"
      [[ $(plugin_enabled vgs.gallery) == True && $(plugin_enabled vgs.fonts) == True && $(record_exists vgs.lock) == True ]]
      [[ $(plugin_enabled vgs.notifications) == False && $(plugin_enabled vgs.devtools) == False && $(plugin_enabled vgs.themes) == False && $(plugin_enabled vgs.bar) == True ]]
      [[ $(notice_shown) == null && $(layer_count vgs:notice) == 0 ]]
      scene_desktop plugin-pages "$mode_theme"
      capture_state_record plugin-pages "$mode_theme"
      page_state_record "jarvis-$mode_theme" "$mode_theme" vgs.jarvis
    done
  ' _ "$dir" "$repo" >"$dir/out" 2>"$dir/err" || { cat -- "$dir/err" >&2; return 1; }
  python3 - "$dir" <<'PY'
import csv,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
config=json.loads((root/"home/.config/vgshell/shell.json").read_text())
rows={r["id"]:r for r in config["plugins"]}
assert rows["vgs.lock"]["idleLockSeconds"]==0 and rows["vgs.lock"]["lockBeforeSleep"] is False
assert rows["vgs.screensaver"]["idleEnabled"] is False
with (root/"shots/plugin-states.tsv").open() as file:
    records=list(csv.reader(file,delimiter="\t"))
assert {r[3] for r in records}=={"vgs","flexoki-light"}
for r in records:
    states={p["id"]:p for p in json.loads(r[-1])}
    assert states["vgs.themes"]["requested"]=="off" and states["vgs.themes"]["enabled"] is False
    assert states["vgs.bar"]["requested"]=="off" and states["vgs.bar"]["enabled"] is True and states["vgs.bar"]["reason"]=="active-bar"
with (root/"shots/page-states.tsv").open() as file:
    records=list(csv.reader(file,delimiter="\t"))
assert {r[3] for r in records}=={"vgs","flexoki-light"}
for r in records:
    state=json.loads(r[-1]); assert state["enabled"] is True and state["settings"]["model"]=="fixture-model" and "status" in state and "requirements" in state
with (root/"shots/desktop.tsv").open() as file:
    assert all(r[-1]=="112233" for r in csv.reader(file,delimiter="\t"))
PY
}
if capture_state_case "$repo/scripts/sandbox-shots.sh"; then ok "capture states cover on-demand hosts, exclusive release, notices, explicit off and actual records in both themes"; else fail "capture state contract"; fi
capture_controls=(
  "on-demand builds are required" '[[ $live != True ]] || expect_poll' 'expect_poll'
  "the probe retains its exclusive capability" '"the probe releases its capabilities for $conflicts" ok ipc shell setPluginEnabled acme.probe false' '"the probe releases its capabilities for $conflicts" ok echo ok'
  "enable notices are not closed" $'  close_notices\n}\n\n# The published inventory' $'  :\n}\n\n# The published inventory'
  "explicit off never writes" '"disabling $id for the run is allowed" ok ipc shell setPluginEnabled "$id" false' '"disabling $id for the run is allowed" ok echo ok'
  "quiet lock keeps its idle timer" '"idleLockSeconds": 0' '"idleLockSeconds": 300'
  "notice cleanup is capped before the queue ends" 'i<count' 'i<4'
)
for ((i=0; i<${#capture_controls[@]}; i+=3)); do
  label="${capture_controls[i]}"; needle="${capture_controls[i+1]}"; replacement="${capture_controls[i+2]}"
  capture_mutant="$tmp/capture-mutant.sh"
  if ! mutate "$repo/scripts/sandbox-shots.sh" "$needle" "$replacement" "$capture_mutant"; then
    fail "control: $label could not be planted"
  elif capture_state_case "$capture_mutant" >"$tmp/capture-control.out" 2>&1; then
    fail "control: $label stayed green"
  else
    ok "control: $label fails the capture state contract"
  fi
done

if node "$tmp/probe-display-control.cjs" "$repo/scripts/smoke/Probe.qml"; then
  ok "Probe source methods retain finite events, JSON characters and terminal states"
else
  fail "Probe source methods violate their bounded output contract"
fi
probe_controls=(
  "event ceiling" 'if (displayEventSequence >= displayEventCapacityEvents - 1)' 'if (false && displayEventSequence >= displayEventCapacityEvents - 1)'
  "aggregate character ceiling" 'displayEventCapacityChars - displayEventTerminalReserve - displayEventChars' 'displayEventCapacityChars - displayEventTerminalReserve'
)
for ((i=0; i<${#probe_controls[@]}; i+=3)); do
  probe_mutant="$tmp/probe-display-mutant.qml"
  if ! mutate "$repo/scripts/smoke/Probe.qml" "${probe_controls[i+1]}" "${probe_controls[i+2]}" "$probe_mutant"; then
    fail "control: Probe ${probe_controls[i]} could not be planted"
    continue
  fi
  probe_status=0
  node "$tmp/probe-display-control.cjs" "$probe_mutant" >"$tmp/probe-display-control.log" 2>&1 || probe_status=$?
  if [[ $probe_status -eq 1 ]]; then
    ok "control: bypassing the Probe ${probe_controls[i]} fails its source-method assertions"
  else
    fail "control: bypassing the Probe ${probe_controls[i]} did not produce an assertion failure (exit $probe_status)"
    cat -- "$tmp/probe-display-control.log"
  fi
done

# These source fixtures explain why connected owners can publish no actual
# trial, completion or reload event. They do not judge record completeness
# or turn an initial owner sample into event history.
cat >"$tmp/display-expected-facts.cjs" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
try {
    const repo = process.argv[2], scratch = process.argv[3];
    const { load } = require(path.join(repo, 'bin/lib/qml-library.js'));
    const core = path.join(repo, 'shell/Core');
    const monitors = load(path.join(core, 'MonitorLogic.js'));
    const dispatch = load(path.join(core, 'Dispatch.js'));
    const files = { monitor: path.join(core, 'MonitorState.qml'),
        compositor: path.join(core, 'Compositor.qml'), layer: path.join(core, 'HyprlandLayer.js') };
    const sources = Object.fromEntries(Object.entries(files).map(([key, file]) => [key, fs.readFileSync(file, 'utf8')]));

    function sourceMethod(source, name, indent) {
        const pad = ' '.repeat(indent);
        const matches = [...source.matchAll(new RegExp('^' + pad + 'function ' + name
            + '\\([^\\n]*\\) \\{[\\s\\S]*?^' + pad + '\\}', 'gm'))];
        if (matches.length !== 1) throw new Error('expected-facts extraction: ' + name);
        return matches[0][0];
    }
    function context(source, names, indent, state) {
        state.root = state;
        vm.createContext(state);
        vm.runInContext(names.map(name => sourceMethod(source, name, indent)).join('\n'), state);
        return state;
    }
    function check(name, value, expected) {
        try { assert.equal(value, expected, name); }
        catch (error) { error.expectedFact = name; throw error; }
    }
    const parsed = monitors.parseOutputs(JSON.stringify([{
        id: 0, name: 'WAYLAND-1', description: '', make: '', model: '', serial: '',
        width: 1440, height: 900, refreshRate: 60, x: 0, y: 0, scale: 1, transform: 0,
        vrr: false, disabled: false, mirrorOf: 'none', availableModes: [],
        currentFormat: 'XRGB8888', colorManagementPreset: 'srgb', sdrBrightness: 1, sdrSaturation: 1
    }]));
    if (!parsed.ok) throw new Error('expected-facts monitor fixture rejected');

    const cases = [
        { id: 'trial-wrong-owner', owner: 'monitor', method: 'trial', caller: 'other' },
        { id: 'trial-unread-outputs', owner: 'monitor', method: 'trial', unread: true },
        { id: 'trial-active', owner: 'monitor', method: 'trial', phase: 'holding' },
        { id: 'trial-plan-rejected', owner: 'monitor', method: 'trial', rules: { UNKNOWN: { scale: 1 } } },
        { id: 'keep-wrong-token', owner: 'monitor', method: 'keep', phase: 'holding' },
        { id: 'revert-wrong-token', owner: 'monitor', method: 'revert', phase: 'holding' },
        { id: 'queue-invalid-request', owner: 'compositor', operation: 'invalid' },
        { id: 'queue-full', owner: 'compositor', operation: 'full' },
        { id: 'queue-empty', owner: 'compositor', operation: 'empty' },
        { id: 'layer-unchanged', owner: 'layer', operation: 'begin' },
        { id: 'layer-missing-input', owner: 'layer', operation: 'missing' },
        { id: 'layer-busy', owner: 'layer', operation: 'busy' },
        { id: 'layer-prepare-refused', owner: 'layer', operation: 'prepare' },
        { id: 'layer-save-refused', owner: 'layer', operation: 'save' }
    ];
    function runCase(row, source) {
        if (row.owner === 'monitor') {
            let trialState = { phase: row.phase || 'idle', token: 'existing-token', deadline: 0, failure: '' };
            let publications = 0;
            const state = { ownerId: 'owner', outputs: row.unread ? null : parsed.outputs,
                support: {}, Monitors: monitors };
            Object.defineProperty(state, 'trialState', { configurable: true,
                get: () => trialState, set: value => { trialState = value; publications++; } });
            context(source, ['mustOwn', 'trial', 'keep', 'revert'], 4, state);
            const answer = row.method === 'trial'
                ? state.trial(row.caller || 'owner', row.rules || { 'WAYLAND-1': { scale: 1 } }, {})
                : state[row.method]('owner', 'wrong-token');
            check(row.id + ':no-trial-publication', publications, 0);
            check(row.id + ':refused', typeof answer === 'string' && answer.startsWith('refused:'), true);
            return;
        }
        if (row.owner === 'compositor') {
            let starts = 0, completions = 0, completion = null;
            const proc = {};
            Object.defineProperty(proc, 'running', { set: value => { if (value === true) starts++; } });
            const state = { Dispatch: dispatch, Hyprland: { usingLua: true }, proc,
                console: { error: () => {} }, pending: null, pendingDone: null, pendingJudged: false, reply: '',
                queue: row.operation === 'full' ? Array.from({ length: dispatch.QUEUE_LIMIT }, () =>
                    ({ argv: ['hyprctl', 'fixture'], done: null, judged: false })) : [] };
            Object.defineProperty(state, 'completion', { configurable: true,
                get: () => completion, set: value => { completion = value; if (value !== null) completions++; } });
            context(source, ['monitorEval', 'enqueue', 'drain'], 4, state);
            let answer;
            if (row.operation === 'invalid') answer = state.monitorEval('not-monitor-lua', null);
            else if (row.operation === 'full') answer = state.enqueue(['hyprctl', 'fixture'], null, false);
            else state.drain();
            check(row.id + ':no-completion-publication', completions, 0);
            check(row.id + ':no-process-start', starts, 0);
            if (row.operation !== 'empty')
                check(row.id + ':refused', typeof answer === 'string' && answer.startsWith('refused:'), true);
            return;
        }
        const layer = context(source, ['initialState', 'withChanges', 'expectPhase', 'consentChanges',
            'begin', 'written', 'idleDecision', 'step'], 0, {});
        const state = layer.withChanges(layer.initialState(), {
            phase: row.operation === 'busy' || row.operation === 'save' ? 'writing'
                : row.operation === 'prepare' ? 'preparing' : 'idle',
            onDisk: 'existing-layer', pending: 'changed-layer',
            // A run whose one start reload (HyprlandLayer.begin) is done.
            reloaded: true,
            consent: { phase: 'settled', queued: '', failure: '' }
        });
        let result;
        if (row.operation === 'begin') result = layer.begin(state, 'existing-layer');
        else if (row.operation === 'missing') result = layer.begin(state, null);
        else if (row.operation === 'busy') result = layer.step(state, { type: 'render' }, 'changed-layer');
        else result = layer.step(state, {
            type: row.operation === 'prepare' ? 'mkdirDone' : 'saveFailed', failure: 'fixture-refusal'
        }, 'changed-layer');
        check(row.id + ':no-reload-action', result.action === 'reload', false);
        check(row.id + ':next-action', result.action, row.operation === 'save' ? 'read' : 'none');
    }
    for (const row of cases) runCase(row, sources[row.owner]);

    // Each mutation introduces the forbidden fact at the actual return
    // boundary. It keeps the refusal/control text, so an unrelated parse
    // failure cannot count as the intended assertion's rejection.
    const publish = 'trialState = { phase: "arming" }; ';
    const ownerReturn = 'if (ownership !== "") return ownership;';
    const tokenReturn = 'return "refused: monitors-token=unknown";';
    const mutations = [
        ['trial-wrong-owner', 'trial', ownerReturn, 'if (ownership !== "") { ' + publish + 'return ownership; }', 'no-trial-publication'],
        ['trial-unread-outputs', 'trial', 'if (outputs === null) return "refused: monitors=unread";',
            'if (outputs === null) { ' + publish + 'return "refused: monitors=unread"; }', 'no-trial-publication'],
        ['trial-active', 'trial', 'if (trialState.phase !== "idle") return "refused: monitors-trial=active";',
            'if (trialState.phase !== "idle") { ' + publish + 'return "refused: monitors-trial=active"; }', 'no-trial-publication'],
        ['trial-plan-rejected', 'trial', 'if (!trial.ok) return trial.error;',
            'if (!trial.ok) { ' + publish + 'return trial.error; }', 'no-trial-publication'],
        ['keep-wrong-token', 'keep', tokenReturn, '{ ' + publish + tokenReturn + ' }', 'no-trial-publication'],
        ['revert-wrong-token', 'revert', tokenReturn, '{ ' + publish + tokenReturn + ' }', 'no-trial-publication'],
        ['queue-invalid-request', 'monitorEval', 'return r.error;',
            'root.completion = { code: 0, status: 0 }; return r.error;', 'no-completion-publication'],
        ['queue-full', 'enqueue', 'return error;', 'proc.running = true; return error;', 'no-process-start'],
        ['queue-empty', 'drain', 'if (pending !== null || queue.length === 0) return;',
            'if (pending !== null || queue.length === 0) { proc.running = true; return; }', 'no-process-start'],
        ['layer-unchanged', 'begin', 'return { state: withChanges(state, { forcing: false }), action: "none" };',
            'return { state: withChanges(state, { forcing: false }), action: "reload" };', 'no-reload-action'],
        ['layer-missing-input', 'begin', 'return { state: withChanges(state, { forcing: false }), action: "none" };',
            'return { state: withChanges(state, { forcing: false }), action: "reload" };', 'no-reload-action'],
        ['layer-busy', 'step', 'return state.phase === "idle" ? begin(state, text) : { state: state, action: "none" };',
            'return state.phase === "idle" ? begin(state, text) : { state: state, action: "reload" };', 'no-reload-action'],
        ['layer-prepare-refused', 'step',
            'if (event.failure !== "") return idleDecision(withChanges(state, { failedText: state.pending }), event.failure, text, true);',
            'if (event.failure !== "") return written(state);', 'no-reload-action'],
        ['layer-save-refused', 'step',
            'return idleDecision(withChanges(state, { stale: true, failedText: state.pending }), event.failure, text, true);',
            'return written(state);', 'no-reload-action']
    ];
    for (const [id, method, needle, replacement, intended] of mutations) {
        const row = cases.find(candidate => candidate.id === id);
        const source = sources[row.owner];
        const body = sourceMethod(source, method, row.owner === 'layer' ? 0 : 4);
        if (body.split(needle).length !== 2) throw new Error('expected-facts mutation match: ' + id);
        const changed = body.replace(needle, replacement);
        if (changed === body) throw new Error('expected-facts mutation unchanged: ' + id);
        const mutant = path.join(scratch, 'expected-facts-' + id + path.extname(files[row.owner]));
        fs.writeFileSync(mutant, source.replace(body, changed), { flag: 'wx' });
        let killed = false;
        try { runCase(row, fs.readFileSync(mutant, 'utf8')); }
        catch (error) {
            if (error.code !== 'ERR_ASSERTION' || error.expectedFact !== id + ':' + intended)
                throw new Error('expected-facts mutation failed outside intended assertion: ' + id + ': ' + error.message);
            killed = true;
        }
        check(id + ':mutation-rejected', killed, true);
        console.log('display-expected-facts: mutation-rejected=' + id + ' assertion=' + intended);
    }
    console.log('display-expected-facts: pass');
} catch (error) {
    if (error.code === 'ERR_ASSERTION') {
        console.error('display-expected-facts: assertion-failed=' + error.expectedFact + ' ' + error.message);
        process.exitCode = 1;
    } else {
        console.error('display-expected-facts: unavailable ' + error.message);
        process.exitCode = 2;
    }
}
JS
if node "$tmp/display-expected-facts.cjs" "$repo" "$tmp"; then
  ok "actual refusal and no-change paths do not imply trial, completion or reload history"
else
  fail "actual source expected-fact controls did not pass"
fi

if [[ $failures -gt 0 ]]; then
  echo "test-sandbox-shots: failed=$failures"
  exit 1
fi
echo "test-sandbox-shots: ok"
