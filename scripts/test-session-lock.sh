#!/usr/bin/env bash
# Exercise the real SessionLock owner through qml-unit. Each control changes
# a disposable core copy, keeps the matched code, and must fail this suite.
# The reading of one `hyprctl -j monitors` answer is
# shell/Commons/SessionLockState.js's, whose rules
# scripts/test-session-lock-state.js controls; here the controls cover how
# the owner uses that reading.
set -euo pipefail
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "$@"
TMP_ROOT="$(mktemp -d)" || { echo "test-session-lock: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-session-lock: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-session-lock: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

# qml-unit supplies an empty environment and a private HOME to Qt.
"$repo/scripts/qml-unit.sh" "$repo/scripts/qml-tests/tst_session_lock.qml"
python3 - "$repo/shell/Core" "$TMP_ROOT" <<'PY'
import pathlib, shutil, sys
source_dir, root = map(pathlib.Path, sys.argv[1:])
source = (source_dir / "SessionLock.qml").read_text()
controls = [
    ("request", "return root.lockRequested || root.lockSecure;",
     "return (false && root.lockRequested) || root.lockSecure;"),
    ("secure", "return root.lockRequested || root.lockSecure;",
     "return root.lockRequested || (false && root.lockSecure);"),
    ("frozen", "return Object.freeze({", "return Object.assign({"),
    ("unload", "        lockContentOwner = null;",
     "        lockContentOwner = null;\n        lockRequested = false;"),
    ("ended", "        if (!lockRequested) return;\n        lockRequested = false;\n        lockSecure = false;",
     "        if (!lockRequested) return;\n        lockSecure = false;"),
    ("ended-unrequested", "        if (!lockRequested) return;\n        lockRequested = false;",
     "        lockRequested = false;"),
    ("reading-once", "if (unlockedReadings >= 2) compositorEnded", "if (unlockedReadings >= 1) compositorEnded"),
    ("reading-state", 'SessionLockState.read(text) === "unlocked"', 'SessionLockState.read(text) !== "locked"'),
    ("reading-unconfirmed", "const unlocked = lockSecure && ", "const unlocked = true && "),
    ("reading-no-reset", "unlockedReadings = unlocked ? unlockedReadings + 1 : 0;", "unlockedReadings = unlocked ? unlockedReadings + 1 : unlockedReadings;"),
    ("idle-ticket", 'if (request.cause === "idle" && idle.ticketFor(ctx.id, "lock", request.ticket) === null)', "if (false)"),
    ("request-judged", "        if (refusal !== \"\") return refusal;\n", ""),
    ("first-cause", "        if (!wasLocked) lockCause = cause;", "        lockCause = cause;"),
    ("covers-told", "        covers.lockRequested(cause, wasLocked);", "        covers.lockRequested(cause, false);"),
    ("expiry-cause", 'relock("release-end", "timeout")', 'relock("restore", "timeout")'),
    ("marker-first", "if (!markRelease(milliseconds)) return", "if (false && !markRelease(milliseconds)) return"),
    ("marker-recover", 'if (releaseMarker.text() === "") return;', 'if (true) return;'),
    ("marker-readback", "        releaseMarker.reload();\n", "        if (false) releaseMarker.reload();\n"),
    ("recover-cause", 'relock("release-end", "recovered")', 'relock("restore", "recovered")')
]
for name, needle, replacement in controls:
    assert source.count(needle) == 1, (name, "control match count")
    changed = source.replace(needle, replacement)
    assert changed != source, (name, "control unchanged")
    target = root / name
    shutil.copytree(source_dir, target)
    path = target / "SessionLock.qml"
    assert not path.is_symlink(), (name, "control symlink")
    path.write_text(changed)
PY
for rule in request secure frozen unload ended ended-unrequested reading-once reading-state reading-unconfirmed reading-no-reset idle-ticket request-judged first-cause covers-told expiry-cause marker-first marker-recover marker-readback recover-cause; do
  status=0
  out="$("$repo/scripts/qml-unit.sh" --core "$TMP_ROOT/$rule" "$repo/scripts/qml-tests/tst_session_lock.qml" 2>&1)" || status=$?
  if [[ $status == 1 && $out == *"::session-lock::"* && $out == *"FAIL!  :"* ]]; then
    printf '  ok    session-lock control=%s exit=%s\n' "$rule" "$status"
  else
    printf '  FAIL  session-lock control=%s exit=%s\n%s\n' "$rule" "$status" "$out"
    exit 1
  fi
done

# Exercise only the new expiry instrument. Retain its lock action as dead
# code in the disposable source so a missing-text assertion cannot kill it.
python3 - "$repo/shell/Core" "$repo/scripts/qml-tests/tst_session_lock.qml" "$TMP_ROOT" <<'PY'
import pathlib, re, shutil, sys
source_dir, test_path, root = map(pathlib.Path, sys.argv[1:])
target = root / "expiry"
shutil.copytree(source_dir, target)
path = target / "SessionLock.qml"
assert not path.is_symlink()
source = path.read_text()
needle = '        relock("release-end", "timeout");'
assert source.count(needle) == 1
changed = source.replace(needle, '        if (false) relock("release-end", "timeout");')
assert changed != source
path.write_text(changed)
tests = test_path.read_text()
prefix = tests.split("        function test_live_state_data()", 1)[0]
case = re.search(r"(?ms)^        function test_temporary_expiry_relocks\(\) \{.*?^        \}", tests)
assert case is not None
(root / "tst_expiry.qml").write_text(prefix + case[0] + "\n    }\n}\n")
PY
status=0
out="$("$repo/scripts/qml-unit.sh" --core "$TMP_ROOT/expiry" "$TMP_ROOT/tst_expiry.qml" 2>&1)" || status=$?
if [[ $status == 1 && $out == *"::session-lock::test_temporary_expiry_relocks()"* && $out == *"FAIL!  :"* ]]; then
  printf '  ok    session-lock control=expiry exit=%s\n' "$status"
else
  printf '  FAIL  session-lock control=expiry exit=%s\n%s\n' "$status" "$out"
  exit 1
fi
