#!/usr/bin/env bash
# Only the nested terminal's fixture allow-list executes this script. It
# exits 0, unless the jarvis-setup row wrote `release SECONDS` into
# smoke-local-setup in the Jarvis state folder: then it has the shell
# release the local voice through the shipped `setup-local release`, as
# tui/setup-local.sh does, takes local-setup.lock alone within SECONDS as
# setup-local install takes it within LOCK_WAIT, and publishes the marker
# again by rename. smoke-local-setup-release holds the shell's last answer
# and smoke-local-setup-outcome `ready` or `busy`.
state="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis"
[[ -f $state/smoke-local-setup ]] || exit 0
read -r mode seconds <"$state/smoke-local-setup"
[[ $mode == release && $seconds =~ ^[1-9][0-9]*$ ]] || exit 2
tree="${VGS_TUI_LIB%/bin/lib/tui.sh}"
# The keyed line `jarvis-setup: release=ANSWER`, or a busy refusal's.
answer="$(python3 -I "$VGS_PLUGIN_DIR/setup-local" release "$tree/bin/vgshell" 2>&1)"
release="$(sed -n 's/^jarvis-setup: \(failed=setup=busy \)\{0,1\}release=//p' <<<"$answer")"
printf '%s\n' "${release:-none}" >"$state/smoke-local-setup-release"
exec python3 -I - "$state" "$seconds" <<'PY'
import fcntl, sys, time
from pathlib import Path
state, seconds = Path(sys.argv[1]), int(sys.argv[2])
outcome = state / "smoke-local-setup-outcome"
with (state / "local-setup.lock").open("a") as lock:
    deadline = time.monotonic() + seconds
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                outcome.write_text("busy\n")
                sys.exit(1)
            time.sleep(0.1)
    marker, copy = state / "local-ready.json", state / ".local-ready-smoke"
    copy.write_bytes(marker.read_bytes())
    copy.replace(marker)
    outcome.write_text("ready\n")
PY
