#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$repo/tmp/test-screensaver-transcode"
mkdir -p -- "$work"
script="$repo/shell/plugins/vgs.screensaver/bin/transcode-ascii"
fixture="$work/diag.png"
magick -size 4x4 xc:none -fill black -draw 'point 0,0 point 1,1 point 0,2 point 1,3' "$fixture"
run_case() { "$1" "$fixture" "$2" --width 2 --height 1 ${3:-}; }
expect_text() {
  local label="$1" file="$2" want="$3" got
  got="$(cat -- "$file")"
  if [[ $got == "$want" ]]; then printf '  ok    %s\n' "$label"; else printf '  FAIL  %s got=[%s] want=[%s]\n' "$label" "$got" "$want"; return 1; fi
}
run_case "$script" "$work/out.txt"
expect_text "braille output is pinned" "$work/out.txt" "⢕"
run_case "$script" "$work/invert.txt" --invert
expect_text "invert changes transparent alpha reading" "$work/invert.txt" "⡪⣿"
python3 - "$script" "$work/threshold-copy" <<'PY'
from pathlib import Path
import sys
source, target = map(Path, sys.argv[1:3])
text = source.read_text()
needle = '-threshold "${threshold}%"'
if text.count(needle) != 1:
    raise SystemExit('threshold control match failed')
target.write_text(text.replace(needle, '-threshold "100%"'))
target.chmod(0o755)
PY
if "$work/threshold-copy" "$fixture" "$work/threshold.out" --width 2 --height 1 && cmp -s -- "$work/out.txt" "$work/threshold.out"; then
  echo '  FAIL  threshold control did not change output'
  exit 1
else
  echo '  ok    threshold control changes output'
fi
python3 - "$script" "$work/alpha-copy" <<'PY'
from pathlib import Path
import sys
source, target = map(Path, sys.argv[1:3])
text = source.read_text()
needle = 'if [[ $use_alpha == true ]]; then'
if text.count(needle) != 1:
    raise SystemExit('alpha control match failed')
target.write_text(text.replace(needle, 'if false; then'))
target.chmod(0o755)
PY
if "$work/alpha-copy" "$fixture" "$work/alpha.out" --width 2 --height 1 && cmp -s -- "$work/out.txt" "$work/alpha.out"; then
  echo '  FAIL  alpha control did not change output'
  exit 1
else
  echo '  ok    alpha control changes output'
fi
echo 'test-screensaver-transcode: ok'
