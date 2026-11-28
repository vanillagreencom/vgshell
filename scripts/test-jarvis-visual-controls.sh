#!/usr/bin/env bash
# The Jarvis frame and button tests run against two old behaviors in
# disposable plugin copies. A failed load or an unmeasured draw proves
# nothing. The ordinary qml-unit row runs the same tests on shipped code.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "$@"
scratch="$(mktemp -d)"
trap 'rm -rf -- "${scratch:?}"' EXIT

control() { # NAME FILE CASE-FUNCTION NEEDLE REPLACEMENT
    local name="$1" test_file="$2" test_case="$3" needle="$4" replacement="$5"
    local tree="$scratch/$name" status=0 output
    mkdir -p -- "$tree/scripts/qml-tests" "$tree/shell/plugins"
    cp -a -- "$repo/shell/plugins/vgs.jarvis" "$tree/shell/plugins/"
    cp -- "$repo/scripts/qml-tests/$test_file" "$tree/scripts/qml-tests/"
    python3 - "$tree/shell/plugins/vgs.jarvis/Bubble.qml" "$needle" "$replacement" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1])
needle, replacement = sys.argv[2:]
assert target.is_file() and not target.is_symlink()
source = target.read_text()
assert source.count(needle) == 1 and needle != replacement, needle
target.write_text(source.replace(needle, replacement))
PY
    output="$("$repo/scripts/qml-unit.sh" --tests "$repo/scripts/qml-tests" "$tree/scripts/qml-tests/$test_file" 2>&1)" || status=$?
    if [[ $status -eq 77 ]]; then printf '%s\n' "$output"; return 77; fi
    if [[ $status -eq 1 ]] && grep -F 'FAIL!' <<<"$output" | grep -F -- "$test_case"; then
        printf 'test-jarvis-visual-controls: rejected=%s\n' "$name"
        return 0
    fi
    printf 'test-jarvis-visual-controls: failed=%s exit=%s\n' "$name" "$status" >&2
    printf '%s\n' "$output" | tail -n 30 >&2
    return 1
}

control first-frame tst_jarvis_plates.qml 'jarvis-plates::test_each_swapped_frame_keeps_its_placement' \
    'service.bubbleWanted && service.callPlaced' 'service.bubbleWanted'
control closing-frame tst_jarvis_plates.qml 'jarvis-plates::test_each_swapped_frame_keeps_its_placement' \
    'closing ? lastPlacement : waitingPlacement' 'waitingPlacement'
control fixed-confirm tst_jarvis_prompt.qml 'jarvis-prompt::test_answers_take_the_looks_form' \
    'root.hold.purpose === "release" ? "Yes" : root.hold.verb' 'root.hold.purpose === "release" ? "Yes" : "Confirm"'
