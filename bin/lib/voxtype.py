#!/usr/bin/env python3
"""Private dictation audio admission and bounded child transport."""
import ctypes
import json
import os
import pathlib
import selectors
import shutil
import signal
import subprocess
import sys
import time

NIX_STORE_ROOT = "/nix/store"


def route_environment():
    # pw-play is already a required core command. Nix installs its canonical
    # pw-cat binary and the ALSA modules in one PipeWire package output. Use
    # that package's own module directory for flake, curl and checkout trees;
    # ordinary distro libasound keeps its native (including multiarch) path.
    environment = dict(os.environ)
    player = shutil.which("pw-play")
    if player is None:
        print("vgs-dictation: route=missing-player", file=sys.stderr)
        raise SystemExit(127)
    player = pathlib.Path(player).resolve()
    if player.is_relative_to(NIX_STORE_ROOT):
        environment["ALSA_PLUGIN_DIR"] = str(player.parent.parent / "lib/alsa-lib")
    return environment


def check_route(environment):
    # snd_dlopen is libasound's public module loader (alsa-lib dlmisc.c).
    # It loads code only: no snd_pcm_open, audio device or server is touched.
    # Nix's PCM module links alsa_dep (PipeWire alsa-plugins/meson.build),
    # so its dependency handle exposes snd_dlopen even when generic Python
    # has no libasound search path. Other distros use the native ALSA path.
    name = "libasound_module_pcm_pipewire.so"
    module_dir = environment.get("ALSA_PLUGIN_DIR")
    module = str(pathlib.Path(module_dir) / name) if module_dir else name
    library = module if module_dir and pathlib.Path(module_dir).is_relative_to(NIX_STORE_ROOT) else "libasound.so.2"
    try:
        alsa = ctypes.CDLL(library)
        alsa.snd_dlopen.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_size_t]
        alsa.snd_dlopen.restype = ctypes.c_void_p
        alsa.snd_dlclose.argtypes = [ctypes.c_void_p]
        alsa.snd_dlclose.restype = ctypes.c_int
        error = ctypes.create_string_buffer(256)
        handle = alsa.snd_dlopen(os.fsencode(module), os.RTLD_NOW, error, len(error))
        if handle and alsa.snd_dlclose(handle) == 0:
            return
    except (OSError, AttributeError):
        pass
    print("vgs-dictation: route=pipewire-module-unavailable", file=sys.stderr)
    raise SystemExit(69)


def route_package(detected):
    # Package data has one owner, also read by the packaging check.
    try:
        manager = json.loads(detected)["primary"]["id"]
        table = pathlib.Path(__file__).resolve().parents[2] / "config/runtime-libraries.json"
        rows = json.loads(table.read_text())
        package = next(row for row in rows if row["id"] == "dictation-audio")["packages"][manager]
    except (OSError, ValueError, KeyError, TypeError, StopIteration):
        print("vgs-dictation: route=package-unavailable", file=sys.stderr)
        raise SystemExit(69)
    print(manager)
    print(package)


def supervise(role, argv):
    # A changed-state follower emits small JSON records; allow startup bursts,
    # but refuse a continuous writer. One-shot inventories/transcripts get a
    # separate total ceiling. VGS-1998's nested before/after run measures the
    # shell cost of crossing these bounds, not a presumed daemon log rate.
    environment = route_environment()
    if role == "daemon":
        check_route(environment)
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

if __name__ == "__main__":
    command, *arguments = sys.argv[1:]
    if command == "check-route":
        check_route(route_environment())
    elif command == "route-package":
        route_package(*arguments)
    elif command == "supervise":
        role, *argv = arguments
        supervise(role, argv)
    else:
        raise SystemExit(2)
