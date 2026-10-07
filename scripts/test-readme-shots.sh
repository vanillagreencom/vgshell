#!/usr/bin/env bash
# Drive scripts/readme-shots.sh over synthetic shots, with no sandbox. A
# scratch checkout holds a copy of the script, of the table's judge
# scripts/check-readme-images.py and of scripts/smoke/shot.sh, a table of
# its own, and under its tmp/ a run as scripts/sandbox-shots.sh writes one:
# shots.tsv, items.tsv and 2560x1600 PNGs made with ImageMagick over a flat
# desktop with a 56-row bar band, a clock in the band and a parked pointer
# in the bottom-right corner. Its scripts/sandbox-shots.sh is a stand-in that
# starts no compositor: it records its arguments, copies that run into its
# --out directory, as a real run leaves its shots there whether it passes
# or fails, and exits with the status its case sets. The --from cases pin
# the exit status and the first stderr line; the pass case pins every
# image's size and WebP magic. The cases without --from pin the stand-in's
# arguments, the exit status passed through, and completed images written
# on 0 or a partial 77. The controls plant one defect per rule in a copy of the script and
# require the case that rule owns to go red.
#
# Exit 0 when every case and control holds, 1 otherwise, 77 without
# ImageMagick.
set -euo pipefail

TMP_ROOT="$(mktemp -d)" || { echo "test-readme-shots: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-readme-shots: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-readme-shots: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
if ! command -v magick >/dev/null 2>&1; then
  echo "test-readme-shots: status=not-measured missing=magick"
  exit 77
fi
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

checkout="$TMP_ROOT/checkout"
mkdir -p "$checkout/scripts/smoke" "$checkout/docs/images/plugins" "$checkout/tmp"
cp -- "$repo/scripts/check-readme-images.py" "$checkout/scripts/"
cp -- "$repo/scripts/smoke/shot.sh" "$checkout/scripts/smoke/"

# The run. The desktop is #111111 with a black bar band over rows 0 to 55,
# a clock box in the band and a pointer speck in the bottom-right corner.
# Every shot keeps the band but draws its clock one box shorter, so the
# clock differs from the desktop's in every shot, and draws its pointer
# one pixel wider, so the parked pointer differs too.
run_dir="$checkout/tmp/run"
mkdir -p "$run_dir"
bar=(-fill '#000000' -draw 'rectangle 0,0 2559,55')
desk() { magick -size 2560x1600 xc:'#111111' "${bar[@]}" -fill '#eeeeee' -draw 'rectangle 1200,20 1259,35' -fill white -draw 'rectangle 2556,1596 2559,1599' "$@"; }
shot_base=(-size 2560x1600 xc:'#111111' "${bar[@]}" -fill '#eeeeee' -draw 'rectangle 1200,20 1239,35' -fill white -draw 'rectangle 2555,1596 2559,1599')
desk "$run_dir/00-desktop.png"
# panel: a box under the bar, 4 rows below the band. centre: a box in the
# middle. edge: a box on the right and bottom edges. clock: nothing but the
# clock and the pointer.
magick "${shot_base[@]}" -fill '#222222' -draw 'rectangle 2000,60 2399,459' "$run_dir/panel.png"
magick "${shot_base[@]}" -fill '#222222' -draw 'rectangle 1000,600 1399,899' "$run_dir/centre.png"
magick "${shot_base[@]}" -fill '#222222' -draw 'rectangle 2400,1400 2559,1599' "$run_dir/edge.png"
magick "${shot_base[@]}" "$run_dir/clock.png"
magick -size 1280x800 xc:'#111111' "$run_dir/small.png"
magick "${shot_base[@]}" -fill '#222222' -draw 'rectangle 1000,600 1399,899' "$run_dir/shown.png"
cp -- "$run_dir/centre.png" "$run_dir/tooltip.png"
cp -- "$run_dir/centre.png" "$run_dir/absent-window.png"
# item: the centre box, which items.tsv records. bad: a shot whose
# items.tsv line has no width. dim: the centre box on a flat colour over
# the whole output, the bar band included, as a lock screen or a scrim
# draws. dim-empty: that colour alone.
cp -- "$run_dir/centre.png" "$run_dir/item.png"
cp -- "$run_dir/centre.png" "$run_dir/bad.png"
magick -size 2560x1600 xc:'#050505' -fill '#222222' -draw 'rectangle 1000,600 1399,899' -fill white -draw 'rectangle 2555,1596 2559,1599' "$run_dir/dim.png"
magick -size 2560x1600 xc:'#050505' -fill white -draw 'rectangle 2555,1596 2559,1599' "$run_dir/dim-empty.png"
printf 'item\t1000\t600\t400\t300\nbad\t1000\t600\t0\t300\n' >"$run_dir/items.tsv"
for name in 00-desktop panel centre edge clock small item bad dim dim-empty; do printf '%s\tsha\tprev\tsettled\thidden\tclean\n' "$name"; done >"$run_dir/shots.tsv"
printf 'shown\tsha\tprev\tsettled\tshown\tclean\n' >>"$run_dir/shots.tsv"
printf 'tooltip\tsha\tprev\tsettled\thidden\ttooltip\n' >>"$run_dir/shots.tsv"
printf 'absent-window\tsha\tprev\tsettled\tabsent\tclean\n' >>"$run_dir/shots.tsv"
# A run whose desktop has no bar band.
flat_dir="$checkout/tmp/flat"
mkdir -p "$flat_dir"
magick -size 2560x1600 xc:'#111111' "$flat_dir/00-desktop.png"
cp -- "$run_dir/centre.png" "$flat_dir/"
printf '00-desktop\ts\tp\tsettled\thidden\tclean\ncentre\ts\tp\tsettled\thidden\tclean\n' >"$flat_dir/shots.tsv"

# The table each case runs over: image, shot, crop and scene per row, the
# scene `scene` when the row names none, as it is no concern of --from.
table() { # ROW...
  local row image shot crop scene
  printf 'image\tscene\tshot\tcrop\n'
  for row; do IFS=' ' read -r image shot crop scene <<<"$row"; printf '%s\t%s\t%s\t%s\n' "$image" "${scene:-scene}" "$shot" "$crop"; done
}
pass_rows=(
  "p.full.webp centre full"
  "p.bar.webp clock bar"
  "p.panel.webp panel content"
  "p.centre.webp centre content"
  "p.edge.webp edge content"
  "p.item.webp item item"
  "p.backdrop.webp dim backdrop"
)
# Expected sizes: the band is 56 rows, the margin 32 px. The panel's box
# starts 4 rows under the band, within the margin, so it runs from the top
# edge; the centre's box, the item's recorded box and the box on dim's
# backdrop grow by 32 a side; the edge's box is clamped on the right and
# the bottom.
# In the order the directory's glob lists them.
pass_sizes="p.backdrop.webp 464x364
p.bar.webp 2560x56
p.centre.webp 464x364
p.edge.webp 192x232
p.full.webp 2560x1600
p.item.webp 464x364
p.panel.webp 464x492"

# run_tool SCRIPT TABLE_TEXT ARG...: SCRIPT as the checkout's
# scripts/readme-shots.sh over TABLE_TEXT, in an environment holding PATH
# alone; sets status, out and err_line.
run_tool() {
  local script="$1" table_text="$2"
  shift 2
  cp -- "$script" "$checkout/scripts/readme-shots.sh"
  printf '%s\n' "$table_text" >"$checkout/docs/images/plugins/shots.tsv"
  status=0
  env -i PATH="$PATH" HOME="$TMP_ROOT" bash "$checkout/scripts/readme-shots.sh" "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  err_line="$(head -n 1 -- "$TMP_ROOT/err")"
}

# The sizes of the images written under DIR, one `name WxH` line each,
# every one checked WebP by its magic bytes.
sizes_in() {
  local file
  for file in "$1"/*.webp; do
    [[ $(head -c 4 -- "$file") == RIFF && $(head -c 12 -- "$file" | tail -c 4) == WEBP ]] || { echo "$(basename -- "$file") not-webp"; continue; }
    printf '%s %s\n' "$(basename -- "$file")" "$(magick identify -format '%wx%h' "$file")"
  done
}

# pass_case SCRIPT: whether SCRIPT writes every pass row at its size.
pass_case() {
  local out_dir="$checkout/tmp/out-$RANDOM$RANDOM"
  run_tool "$1" "$(table "${pass_rows[@]}")" --from "$run_dir" --out "$out_dir"
  [[ $status -eq 0 && $(sizes_in "$out_dir") == "$pass_sizes" ]] && return 0
  echo "        pass: exit=$status first stderr line: $err_line sizes: $(sizes_in "$out_dir" | tr '\n' ' ')"
  return 1
}
if pass_case "$repo/scripts/readme-shots.sh"; then ok "every crop is cut at its size and written as WebP"; else fail "every crop is cut at its size and written as WebP"; fi

absent_case() {
  local out_dir="$checkout/tmp/out-absent-$RANDOM$RANDOM"
  run_tool "$1" "$(table "p.absent.webp absent-window full")" --from "$run_dir" --out "$out_dir"
  [[ $status -eq 0 && $(sizes_in "$out_dir") == "p.absent.webp 2560x1600" ]]
}
if absent_case "$repo/scripts/readme-shots.sh"; then ok "a shot recorded with an absent host window is cut"; else fail "a shot recorded with an absent host window is cut: exit=$status first stderr line: $err_line"; fi

# Refusal cases, four fields each: label, table rows (;-separated), the
# arguments, the exit status and the first stderr line. OUT is a fresh
# directory under the checkout's tmp/.
out_ok="$checkout/tmp/out-refusals"
cases=(
  "an unknown argument is refused" "p.a.webp centre full" "--bogus" 2 "readme-shots: refused: argument=--bogus"
  "an --out outside tmp/ is refused" "p.a.webp centre full" "--from $run_dir --out $TMP_ROOT/elsewhere" 1 "readme-shots: refused: out=$TMP_ROOT/elsewhere"
  "a malformed table is refused" "p.a.webp centre zoom" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: table=docs/images/plugins/shots.tsv"
  "a run without shots.tsv is refused" "p.a.webp centre full" "--from $checkout/tmp --out $out_ok" 1 "readme-shots: refused: from=$checkout/tmp"
  "a shot the run lacks is refused" "p.a.webp absent full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: shot=absent"
  "a shot taken with the window shown is refused" "p.a.webp shown full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: shot-window=shown"
  "a shot with tooltip chrome is refused" "p.a.webp tooltip full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: shot-chrome=tooltip"
  "a shot of another size is refused" "p.a.webp small full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: shot-size=small"
  "a desktop with no bar band is refused" "p.a.webp centre full" "--from $flat_dir --out $out_ok" 1 "readme-shots: refused: bar=$flat_dir/00-desktop.png"
  "a content crop with nothing below the band is refused" "p.a.webp clock content" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: crop-empty=clock"
  "a backdrop crop with nothing on the backdrop is refused" "p.a.webp dim-empty backdrop" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: crop-empty=dim-empty"
  "a crop that leaves the recorded item under half the image is refused" "p.a.webp item full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: crop-sparse=item"
  "an item crop of a shot with no recorded box is refused" "p.a.webp centre item" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: item-missing=centre"
  "an items.tsv line with no width is refused" "p.a.webp bad full" "--from $run_dir --out $out_ok" 1 "readme-shots: refused: item-box=bad"
)
declare -A case_at
for (( i = 0; i < ${#cases[@]}; i += 5 )); do
  label="${cases[i]}"; case_at[$label]=$i
  IFS=';' read -r -a rows <<<"${cases[i + 1]}"
  read -r -a args <<<"${cases[i + 2]}"
  run_tool "$repo/scripts/readme-shots.sh" "$(table "${rows[@]}")" "${args[@]}"
  if [[ $status -eq ${cases[i + 3]} && $err_line == "${cases[i + 4]}" ]]; then ok "$label"; else fail "$label: exit=$status first stderr line: $err_line"; fi
done

# The stand-in scripts/sandbox-shots.sh: it writes its arguments one per
# line to stand_in_argv, copies the run into its --out directory and exits
# with the status in stand_in_status.
stand_in_argv="$TMP_ROOT/stand-in.argv"
stand_in_status="$TMP_ROOT/stand-in.status"
stand_in_empty="$TMP_ROOT/stand-in.empty"
cat >"$checkout/scripts/sandbox-shots.sh" <<STAND_IN
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$@" >"$stand_in_argv"
out=""
while [[ \$# -gt 0 ]]; do
  if [[ \$1 == --out && \$# -ge 2 ]]; then out="\$2"; shift 2; else shift; fi
done
[[ -n \$out ]] || { echo "sandbox-shots stand-in: no --out" >&2; exit 3; }
mkdir -p -- "\$out"
# Each fixture call writes one run, even when its second-resolution path
# was used by the preceding call.
rm -f -- "\${out:?}"/*
[[ ! -e "$stand_in_empty" ]] || exit "\$(cat -- "$stand_in_status")"
cp -- "$run_dir"/* "\$out"/
if [[ \$(cat -- "$stand_in_status") == 77 ]]; then
  printf 'sandbox-shots: scene=screensaver mode=dark status=not-measured missing=ttfx\n'
fi
exit "\$(cat -- "$stand_in_status")"
STAND_IN
chmod +x "$checkout/scripts/sandbox-shots.sh"
# The table without --from: two rows share each of the scenes panels and
# bar, so each scene must reach the sandbox once, in the table's order.
sandbox_rows=(
  "p.full.webp centre full panels"
  "p.bar.webp clock bar bar"
  "p.panel.webp panel content panels"
  "p.centre.webp centre content settings"
  "p.edge.webp edge content bar"
  "p.item.webp item item settings"
  "p.backdrop.webp dim backdrop bar"
)
sandbox_scenes="panels
bar
settings"
sandbox_head="--scale
2
--modes
dark
--size
1280x800
--out"

# sandbox_case SCRIPT STATUS: whether SCRIPT, without --from and over a
# stand-in that exits STATUS, hands the sandbox exactly its capture
# arguments, an --out under tmp/readme-shots/ named for the UTC time and
# each table scene once; exits STATUS; and writes the pass rows at their
# sizes on 0 or a partial 77, and no image on 1.
sandbox_case() {
  local script="$1" want="$2" out_dir="$checkout/tmp/out-$RANDOM$RANDOM" argv="" images=""
  printf '%s\n' "$want" >"$stand_in_status"
  rm -f -- "${stand_in_argv:?}"
  run_tool "$script" "$(table "${sandbox_rows[@]}")" --out "$out_dir"
  [[ ! -f $stand_in_argv ]] || argv="$(cat -- "$stand_in_argv")"
  [[ ! -d $out_dir ]] || images="$(find "$out_dir" -type f -name '*.webp')"
  [[ $want -ne 1 || -z $images ]] || { echo "        sandbox $want: images written: $images"; return 1; }
  [[ $want -eq 1 || $(sizes_in "$out_dir") == "$pass_sizes" ]] || { echo "        sandbox $want: sizes: $(sizes_in "$out_dir" | tr '\n' ' ')"; return 1; }
  if [[ $status -eq $want && $(head -n 7 <<<"$argv") == "$sandbox_head" \
    && $(sed -n '8p' <<<"$argv") =~ ^"$checkout"/tmp/readme-shots/[0-9]{8}T[0-9]{6}Z$ \
    && $(tail -n +9 <<<"$argv") == "$sandbox_scenes" ]]; then
    return 0
  fi
  echo "        sandbox $want: exit=$status first stderr line: $err_line argv: $(tr '\n' ' ' <<<"$argv")"
  return 1
}
declare -A sandbox_labels=(
  [0]="without --from, a sandbox run that passes is cut into every image"
  [1]="without --from, a sandbox run that fails ends with 1 and no image"
  [77]="without --from, a partial sandbox run crops completed shots and retains 77"
)
for want in 1 77 0; do
  if sandbox_case "$repo/scripts/readme-shots.sh" "$want"; then ok "${sandbox_labels[$want]}"; else fail "${sandbox_labels[$want]}"; fi
done

# The screensaver comes before Capture in the table. A missing screensaver
# shot must not hide the completed Capture shot or turn the run green.
partial_case() {
  local out_dir="$checkout/tmp/partial-$RANDOM$RANDOM" got
  printf '77\n' >"$stand_in_status"
  run_tool "$1" "$(table 'vgs.screensaver.webp absent full screensaver' 'vgs.capture.webp centre content capture')" --out "$out_dir"
  got="$(cat -- "$TMP_ROOT/out")"
  [[ $status -eq 77 && ! -e $out_dir/vgs.screensaver.webp && -e $out_dir/vgs.capture.webp \
    && $(sizes_in "$out_dir") == 'vgs.capture.webp 464x364' \
    && $got == *'scene=screensaver mode=dark status=not-measured missing=ttfx'* \
    && $got == *'scene=screensaver shot=absent status=not-measured'* ]]
}
if partial_case "$repo/scripts/readme-shots.sh"; then ok "missing ttfx leaves Capture cropped and the run not measured"; else fail "missing ttfx leaves Capture cropped and the run not measured"; fi

selection_case() {
  local out_dir="$checkout/tmp/selected-$RANDOM$RANDOM"
  printf '0\n' >"$stand_in_status"
  run_tool "$1" "$(table 'vgs.screensaver.webp absent full screensaver' 'vgs.capture.webp centre content capture')" --out "$out_dir" capture capture
  [[ $status -eq 0 && $(sizes_in "$out_dir") == 'vgs.capture.webp 464x364' \
    && $(tail -n +9 -- "$stand_in_argv") == capture ]]
}
if selection_case "$repo/scripts/readme-shots.sh"; then ok "a named scene crops only its images and runs once"; else fail "a named scene crops only its images and runs once"; fi
unknown_case() {
  run_tool "$1" "$(table 'vgs.capture.webp centre content capture')" --from "$run_dir" unknown
  [[ $status -eq 2 && $err_line == 'readme-shots: refused: scene=unknown' ]]
}
if unknown_case "$repo/scripts/readme-shots.sh"; then ok "an unknown scene is refused"; else fail "an unknown scene is refused"; fi
empty_case() {
  local out_dir="$checkout/tmp/empty-$RANDOM$RANDOM"
  : >"$stand_in_empty"
  printf '77\n' >"$stand_in_status"
  run_tool "$1" "$(table 'vgs.capture.webp centre content capture')" --out "$out_dir"
  rm -- "$stand_in_empty"
  [[ $status -eq 77 && ! -e $out_dir/vgs.capture.webp ]]
}
if empty_case "$repo/scripts/readme-shots.sh"; then ok "a sandbox with no desktop retains exit 77 without cropping"; else fail "a sandbox with no desktop retains exit 77 without cropping"; fi

# Controls, four fields each: label, the text, which must match once, its
# replacement, and the case that goes red: `pass` for the pass case,
# `sandbox-N` for the case whose stand-in exits N, else a refusal case's
# label, whose status and line must then differ.
controls=(
  "a box near the band is not taken from the top edge"
  'top=$(( $2 - MARGIN_PX <= $5 ? 0 : $2 - MARGIN_PX ))' 'top=$(( $2 - MARGIN_PX < 0 ? 0 : $2 - MARGIN_PX ))'
  pass
  "the box is read from the top row, the clock's band included"
  'python3 -c "$mask_program" box "$band"' 'python3 -c "$mask_program" box 0'
  pass
  "the parked pointer's corner is read"
  '-fill black -draw "rectangle $((width - POINTER_PX)),$((height - POINTER_PX)) $width,$height"' '-fill black'
  pass
  "an empty content crop falls back to the whole output"
  '[[ $box != none ]] || stop crop-empty "$shot"' '[[ $box != none ]] || box="0 0 $width $height"'
  "a content crop with nothing below the band is refused"
  "an item crop is cut from the whole output"
  'geometry="$(crop_box "$x" "$y" "$w" "$h" 0)" ;;' 'geometry="${width}x${height}+0+0" ;;'
  pass
  "a backdrop is read from 00-desktop.png"
  'box="$(changed_box "$png" -alpha off \( +clone -fill "$colour" -colorize 100 \))"' 'box="$(changed_box "$png" "$desktop" -alpha off)"'
  pass
  "a crop that leaves the recorded item small is accepted"
  '|| stop crop-sparse "$shot"' '|| true "$shot"'
  "a crop that leaves the recorded item under half the image is refused"
  "an item crop with no recorded box takes the whole output"
  '[[ -n $item ]] || stop item-missing "$shot"' '[[ -n $item ]] || item="0 0 $width $height"'
  "an item crop of a shot with no recorded box is refused"
  "an items.tsv line with no width is read"
  '|| stop item-box "$1" "line=$box"' '|| true'
  "an items.tsv line with no width is refused"
  "a posed shot is accepted for a README image"
  '[[ $chrome == clean ]] || stop shot-chrome "$1" "chrome=${chrome:-unlisted}"' 'true || stop shot-chrome "$1" "chrome=${chrome:-unlisted}"'
  "a shot with tooltip chrome is refused"
  "a shown host window is accepted for a README image"
  '[[ $state == hidden || $state == absent ]] || stop shot-window "$1" "state=${state:-unlisted}"' 'true || stop shot-window "$1" "state=${state:-unlisted}"'
  "a shot taken with the window shown is refused"
  "a failed sandbox run does not end the command"
  '[[ $status -eq 0 || $status -eq 77 ]] || exit "$status"' '[[ $status -eq 0 || $status -eq 77 ]] || true "$status"'
  sandbox-1
  "the old whole-run exit hides completed Capture shots"
  '[[ $status -eq 0 || $status -eq 77 ]] || exit "$status"' '[[ $status -eq 0 ]] || exit "$status"'
  partial
  "a partial run loses its not-measured status"
  $'done\nexit "$status"' $'done\nexit 0'
  partial
  "a named scene does not limit the table"
  'table_rows=("${selected_rows[@]}")' ':'
  selection
  "an unknown scene is accepted"
  '"$found" || stop scene "$scene"' 'true'
  unknown
  "a sandbox with no desktop attempts cropping"
  '[[ $status -ne 77 || -f $from/00-desktop.png ]] || exit 77' 'true'
  empty
  "a missing shot stops a partial run"
  'if [[ $status -eq 77 && ! -f $from/$shot.png ]]; then' 'if false; then'
  partial
  "a scene two rows share reaches the sandbox twice"
  '[[ " ${scenes[*]} " == *" $scene "* ]] || scenes+=("$scene")' '[[ " ${scenes[*]} " == *" $scene "* ]] || true; scenes+=("$scene")'
  sandbox-0
)
mutant="$TMP_ROOT/readme-shots-mutant.sh"
for (( i = 0; i < ${#controls[@]}; i += 4 )); do
  label="${controls[i]}"; target="${controls[i + 3]}"
  if ! python3 -c '
import sys
src, dst, needle, replacement = sys.argv[1:]
text = open(src).read()
assert text.count(needle) == 1, "the planted text must match once"
open(dst, "w").write(text.replace(needle, replacement))' "$repo/scripts/readme-shots.sh" "$mutant" "${controls[i + 1]}" "${controls[i + 2]}"; then
    fail "control: $label could not be planted"
    continue
  fi
  if [[ $target == sandbox-* ]]; then
    if sandbox_case "$mutant" "${target#sandbox-}" >/dev/null; then fail "control: $label still gave '$target'"; else ok "control: $label"; fi
    continue
  fi
  if [[ $target == partial || $target == selection || $target == unknown || $target == empty ]]; then
    if "${target}_case" "$mutant" >/dev/null; then fail "control: $label stayed green"; else ok "control: $label"; fi
    continue
  fi
  if [[ $target == pass ]]; then
    if pass_case "$mutant" >/dev/null; then fail "control: $label left the crops at their sizes"; else ok "control: $label"; fi
    continue
  fi
  if [[ -z ${case_at[$target]+set} ]]; then fail "control: $label names no case: $target"; continue; fi
  at=${case_at[$target]}
  IFS=';' read -r -a rows <<<"${cases[at + 1]}"
  read -r -a args <<<"${cases[at + 2]}"
  run_tool "$mutant" "$(table "${rows[@]}")" "${args[@]}"
  if [[ $status -eq ${cases[at + 3]} && $err_line == "${cases[at + 4]}" ]]; then fail "control: $label still gave '$target'"; else ok "control: $label"; fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-readme-shots: failures=$failures"
  exit 1
fi
echo "test-readme-shots: ok"
