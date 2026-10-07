#!/usr/bin/env python3
"""Execute the smoke row's focus race loop without a compositor.

A failed state read never starts the focus child. Its timed reader can also
end before release. These cases must record failure, restore the transport,
close the target and finish without a completion assertion. The live-reader
case proves the same loop releases both focus requests. Disposable source
mutants remove each bound and must turn its case red. Each child has a parent
deadline and an explicit environment; no graphics or host session is used.
"""
import os
from pathlib import Path
import signal
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
ROW = REPO / "scripts/smoke/rows/compositor-reveal.sh"
HARNESS = REPO / "scripts/smoke/harness.sh"


def section(text, start, end):
    assert text.count(start) == 1 and text.count(end) == 1
    return text[text.index(start):text.index(end)]


LOOP = section(ROW.read_text(), "  for focus_mode in guarded unguarded; do\n",
               "\n  # No close occurs in this control.")
POLL = section(HARNESS.read_text(), "expect_poll() { # LABEL WANT CMD...\n",
               "# rescan LABEL:")
FIXTURE = r'''
set -euo pipefail
sandbox="$1" shim="$1/shim" mode="$2"
mkdir "$shim"
hyprctl_bin=/bin/true
failures=0 closed=0 restored=0 completed=0 released=0 reader=""
expected_errors=()
fail() { failures=$((failures + 1)); }
ok() { :; }
reader_stderr() { :; }
smoke_poll_tries() { smoke_poll_n=1; }
sleep() { :; }
open_reveal() { reveal_pid=fixture; reveal_window=0x123; }
reveal_other() { :; }
close_toplevel() { closed=$((closed + 1)); }
probe() { :; }
in_view() { echo absent; }
active_ws() { echo 6; }
log_lines() { echo 0; }
expect() {
  [[ $3 != probe || ${4:-} != dispatch ]] || completed=$((completed + 1))
}
expect_log() { :; }
shim_hyprctl() {
  if [[ $1 == real ]]; then
    restored=$((restored + 1))
    if [[ -n $reader ]]; then
      wait "$reader" || fail
      [[ ! -e $focus_gate.released ]] || released=$((released + 1))
      reader=""
    fi
  elif [[ $mode == missing-reader ]]; then
    printf held >"$focus_gate.request"
  elif [[ $mode == live-reader ]]; then
    env -i PATH="$PATH" bash -c '
      set -euo pipefail
      exec 3<>"$1.release"
      printf held >"$1.request"
      read -r -t 5 release <&3
      [[ $release == release ]]
      touch "$1.released"
    ' _ "$focus_gate" &
    reader=$!
    # The reader owns both FIFO ends before it writes its marker.
    for ((i=0; i<500; i++)); do
      [[ ! -s $focus_gate.request ]] || break
      command sleep 0.01
    done
    [[ -s $focus_gate.request ]]
  fi
}
'''


def run(loop, mode):
    with tempfile.TemporaryDirectory() as scratch:
        script = Path(scratch) / "case.sh"
        script.write_text(FIXTURE + POLL + loop + '\n'
                          'printf "%s %s %s %s %s\\n" "$failures" "$closed" '
                          '"$restored" "$completed" "$released"\n'
                          '[[ $failures -eq 0 ]]\n')
        child = subprocess.Popen(["bash", str(script), scratch, mode],
                                 env={"PATH": os.environ["PATH"], "LC_ALL": "C",
                                      "VGS_TEST_RUN": "1"},
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, start_new_session=True)
        try:
            out, err = child.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.communicate()
            return "deadline", ""
        return child.returncode, out.strip()


def holds(loop, mode, status, counters):
    return run(loop, mode) == (status, counters)


cases = [
    ("missing-marker", 1, "2 2 2 0 0"),
    ("missing-reader", 1, "2 2 2 0 0"),
    ("live-reader", 0, "0 2 2 2 2"),
]
for mode, status, counters in cases:
    assert holds(LOOP, mode, status, counters), mode
    print(f"  ok    {mode}: recorded result and case cleanup")

controls = [
    ('if [[ ! -s $focus_gate.request ]]; then', 'if false; then', cases[0]),
    ('os.O_WRONLY | os.O_NONBLOCK', 'os.O_WRONLY', cases[1]),
]
for old, new, case in controls:
    assert LOOP.count(old) == 1 and old != new
    mutant = LOOP.replace(old, new)
    assert not holds(mutant, *case), f"control survived: {old}"
    print(f"  ok    control: {case[0]} rejects the removed guard")
print("test-compositor-reveal: ok")
