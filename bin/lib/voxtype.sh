#!/usr/bin/env bash
# voxtype's JSON config and compiled-engine readings, shared by dictation
# setup and the system-step probe. Invalid readings fail the caller.
vgs_voxtype_supervise() { # ROLE ARGV...
  # QProcess itself drains even a stream without a parser. Keep both raw
  # pipes here, outside Quickshell. A failed transport ends the child once;
  # The existing process-group owner also covers this child's life.
  exec python3 - "$@" <<'PY'
import os, pathlib, selectors, shutil, signal, subprocess, sys, time

role, *argv = sys.argv[1:]
NIX_STORE_ROOT = "/nix/store"
# pw-play is already a required core command. Nix installs its canonical
# pw-cat binary and the ALSA modules in one PipeWire package output. Use
# that package's own module directory for flake, curl and checkout trees;
# ordinary distro libasound keeps its native (including multiarch) path.
environment = dict(os.environ)
player = shutil.which("pw-play")
if player is None:
    print("vgs-dictation: route=missing-player", file=sys.stderr)
    sys.exit(127)
player = pathlib.Path(player).resolve()
if player.is_relative_to(NIX_STORE_ROOT):
    environment["ALSA_PLUGIN_DIR"] = str(player.parent.parent / "lib/alsa-lib")
# A changed-state follower emits small JSON records; allow startup bursts,
# but refuse a continuous writer. One-shot inventories/transcripts get a
# separate total ceiling. VGS-1998's nested before/after run measures the
# shell cost of crossing these bounds, not a presumed daemon log rate.
burst = 1048576 if role == "run" else 65536
credit, updated = burst, time.monotonic()
line_credit, line_updated = 32.0, updated
result, pending, tail = bytearray(), bytearray(), b""
selector = selectors.DefaultSelector()
# ALSA_CONFIG_PATH replaces libasound's global configuration. Exposing
# only PipeWire prevents rodio's all-device retry from selecting raw HDMI
# when the default is unavailable (voxtype 1.1.1, rodio 0.19 stream.rs).
# This is the config exercised by VGS-1998's nested null-sink run. A memfd
# keeps it private to this child, without a pathname or cleanup lifetime.
alsa = b'''pcm.!default {
    type pipewire
    playback_node "-1"
    capture_node "-1"
    hint { show on description "VGS dictation through PipeWire" }
}
ctl.!default { type pipewire }
'''
try:
    config_fd = os.memfd_create("vgs-dictation-alsa", os.MFD_CLOEXEC)
    if os.write(config_fd, alsa) != len(alsa):
        raise OSError("incomplete ALSA configuration")
    os.lseek(config_fd, 0, os.SEEK_SET)
except OSError as error:
    print("vgs-dictation: route=unavailable errno=" + str(error.errno), file=sys.stderr)
    sys.exit(74)
try:
    # Pass the caller's selected environment unchanged apart from the
    # child-only ALSA route; the core owns session environment selection.
    # Each fork needs its own parent-death guard: prctl's setting is not
    # inherited by fork. The same exec/PPID contract as the core's guard
    # closes the race if this supervisor ended before setpriv started.
    guarded = ["setpriv", "--pdeathsig", "KILL", "--", "bash", "-c",
               '[[ $PPID == "$1" ]] || exit 1; shift; exec "$@"', "bash", str(os.getpid()), *argv]
    environment["ALSA_CONFIG_PATH"] = "/proc/self/fd/" + str(config_fd)
    child = subprocess.Popen(guarded, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=environment, pass_fds=(config_fd,))
except OSError as error:
    print("vgs-dictation: child=start-failed errno=" + str(error.errno), file=sys.stderr)
    sys.exit(127)
finally:
    os.close(config_fd)

def forward(signum, _frame):
    # Popen retains the child identity until wait reaps it.
    if child.poll() is None:
        child.send_signal(signum)

signal.signal(signal.SIGTERM, forward)
signal.signal(signal.SIGINT, forward)
for pipe in (child.stdout, child.stderr):
    os.set_blocking(pipe.fileno(), False)
    selector.register(pipe, selectors.EVENT_READ)
# Linux pidfds wake the same selector on child exit. A descendant retaining
# a pipe cannot keep this wrapper alive after its direct child has ended.
pidfd = os.pidfd_open(child.pid)
selector.register(pidfd, selectors.EVENT_READ)
overflow = False
ended = False
drained = 0
try:
    while selector.get_map() and not overflow:
        for key, _ in selector.select():
            if key.fd == pidfd:
                selector.unregister(pidfd)
                ended = True
                continue
            chunk = os.read(key.fd, 4096)
            if not chunk:
                selector.unregister(key.fileobj)
                key.fileobj.close()
                continue
            if ended:
                drained += len(chunk)
            now = time.monotonic()
            credit = min(burst, credit + (now - updated) * burst) - len(chunk)
            updated = now
            if credit < 0:
                overflow = True
                break
            if key.fileobj is child.stderr:
                tail = (tail + chunk)[-200:]
            elif role == "run":
                result.extend(chunk)
                if len(result) > 1048576:
                    overflow = True
                    break
            elif role == "follow":
                pending.extend(chunk)
                while b"\n" in pending:
                    line, _, remainder = pending.partition(b"\n")
                    pending = bytearray(remainder)
                    line_credit = min(32, line_credit + (now - line_updated) * 16) - 1
                    line_updated = now
                    if len(line) > 4096 or line_credit < 0:
                        overflow = True
                        break
                    sys.stdout.buffer.write(line + b"\n")
                    sys.stdout.buffer.flush()
                if len(pending) > 4096:
                    overflow = True
            # Daemon stdout is diagnostic only and is never forwarded.
        if ended and (drained >= burst or not selector.select(0)):
            break
    if overflow:
        child.kill()
    code = child.wait()
finally:
    for key in list(selector.get_map().values()):
        if key.fd != pidfd:
            key.fileobj.close()
    os.close(pidfd)
    selector.close()
    if child.poll() is None:
        child.kill()
        child.wait()
if overflow:
    print("vgs-dictation: stream=overflow role=" + role, file=sys.stderr)
    sys.exit(74)
if role == "run":
    sys.stdout.buffer.write(result)
if tail:
    # One physical line and one fixed tail, including for failed children.
    print(tail.decode(errors="replace").replace("\n", " ").replace("\r", " "), file=sys.stderr)
sys.exit(code if code >= 0 else 128 - code)
PY
}

vgs_voxtype_value() { # KEY [CONFIG]
  local json
  local -a config=()
  [[ $# == 1 ]] || config=(--config "$2")
  json="$(voxtype "${config[@]}" config get "$1" --json)" || return
  python3 -c 'import json,sys
v=json.load(sys.stdin)
if isinstance(v,dict): v=v["value"]
if not isinstance(v,str) or not v: raise ValueError("config value is not a string")
print(v)' <<<"$json"
}


# The inventory is voxtype's installed flag, not a guessed model path.
vgs_voxtype_installed() { # ENGINE MODEL
  local json
  json="$(voxtype info models --json)" || return
  python3 -c 'import json,sys
data=json.load(sys.stdin)
engines=data["engines"]
if not isinstance(engines,dict): raise ValueError("engines is not an object")
rows=engines.get(sys.argv[1],{}).get("models",[])
if not isinstance(rows,list): raise ValueError("models is not a list")
print("yes" if any(isinstance(r,dict) and r.get("name")==sys.argv[2] and r.get("installed") is True for r in rows) else "no")' "$1" "$2" <<<"$json"
}
vgs_voxtype_compiled() { # ENGINE
  local json
  json="$(voxtype info engines --json)" || return
  python3 -c 'import json,sys
rows=json.load(sys.stdin)
if not isinstance(rows,list): raise ValueError("engines is not a list")
print("yes" if any(isinstance(r,dict) and r.get("name")==sys.argv[1] and r.get("compiled") is True for r in rows) else "no")' "$1" <<<"$json"
}
