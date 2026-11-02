#!/usr/bin/env python3
"""SoundRule's filesystem and supported-user-deployment contract.

The bootstrap, update, reinstall and the start check start no audio service
job: the stub service manager records every call, and only reads may appear
(VGS-2231).
The fixture executable is an owned, held process, never an invented PID.
No PipeWire, service manager or audio device is contacted by this test.
"""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "shell/plugins/vgs.notifications/sound-rule-install.sh"
SCRIPT = ROOT / "shell/plugins/vgs.notifications/wireplumber/vgs-notification-sounds.lua"
VERSION = "v12345678"
WP = "# VGS notifications: holds an app's own notification sound silent while\nfixture = true\n"
PW = "# VGS notifications: daemon-owned notification hold\nfixture = true\n"


def verify(source, root):
    helper = root / "install.sh"
    helper.write_text(source)
    programs = root / "bin"
    programs.mkdir()
    code = root / "daemon.c"
    code.write_text("#include <unistd.h>\nint main(void) { for (;;) pause(); }\n")
    subprocess.run(["cc", str(code), "-o", str(programs / "pipewire")], check=True,
                   env={"PATH": "/usr/bin:/bin", "LANG": "C"}, capture_output=True)
    manager = programs / "systemctl"
    # A reply named for the unit ($3 of `--user show UNIT`) answers for it.
    manager.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >>"$MANAGER_LOG"\nreply=$MANAGER_REPLY\n[[ ! -e $reply.$3 ]] || reply=$reply.$3\n'
                       'cat -- "$reply"\nexit "$MANAGER_STATUS"\n')
    manager.chmod(0o755)

    def scenario(name, custom=False, manager_status=0, loaded=True):
        home = root / name
        home.mkdir()
        config, data, state = [home / p for p in (".config", ".local/share", ".local/state")]
        env = {"PATH": str(programs) + ":/usr/bin:/bin", "HOME": str(home),
               "XDG_CONFIG_HOME": str(config), "LANG": "C"}
        child_env = dict(env)
        if custom:
            child_env["PIPEWIRE_CONFIG_DIR"] = str(root / "custom")
        child = subprocess.Popen([str(programs / "pipewire")], env=child_env)
        try:
            reply = home / "manager-reply"
            reply.write_text("\n".join([
                "LoadState=" + ("loaded" if loaded else "not-found"),
                "ActiveState=active", "MainPID=" + str(child.pid), ""]))
            calls = home / "manager-calls"
            calls.write_text("")
            env.update(MANAGER_REPLY=str(reply), MANAGER_STATUS=str(manager_status), MANAGER_LOG=str(calls))
            base = [str(config), str(data), str(state), str(home)]

            def run(action, *args):
                result = subprocess.run(["/bin/bash", str(helper), action, *base, *args],
                                        env=env, text=True, capture_output=True, timeout=10)
                assert result.returncode == 0, (name, result.returncode, result.stderr)
                jobs = [c for c in calls.read_text().splitlines() if c.split()[:2] != ["--user", "show"]]
                assert not jobs, ("the install starts no audio service job", name, jobs)
                return result.stdout.strip()

            install = lambda: run("install", str(SCRIPT), VERSION, WP, PW)
            if custom or manager_status or not loaded:
                assert install().startswith("unsupported:"), "unsupported deployment must refuse"
                assert not config.exists(), "unsupported bootstrap writes no files"
                return
            # The markers of the retired restart, as their writers left them.
            markers = [(state / "vgshell/notifications/sound-rule-restarted", "v00000000\n"),
                       (state / "vgshell/notifications/sound-rule-store-restarted", "hold-store-v1 v00000000\n")]
            old_script = data / "wireplumber/scripts/vgs-notification-sounds.lua"
            old_conf = config / "wireplumber/wireplumber.conf.d/90-vgs-notification-sounds.conf"
            for path, text in markers + [(old_script, SCRIPT.read_text().splitlines()[0] + "\nold script\n"),
                                         (old_conf, WP.splitlines()[0] + "\nold fragment\n")]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            assert install() == "installed", "default user service is supported"
            assert calls.read_text(), "the bootstrap reads the user services"
            assert not any(p.exists() for p, _ in markers), "old markers are retired"
            assert old_script.read_bytes() == SCRIPT.read_bytes(), "old script migrates in place"
            assert old_conf.read_text() == WP, "old fragment migrates in place"
            hold = config / "pipewire/pipewire.conf.d/90-vgs-notification-hold.conf"
            assert hold.read_text() == PW, "daemon drop-in is installed"
            before = [(p.stat().st_ino, p.stat().st_mtime_ns) for p in (old_script, old_conf, hold)]
            checked = calls.read_text()
            assert install() == "installed"
            after = [(p.stat().st_ino, p.stat().st_mtime_ns) for p in (old_script, old_conf, hold)]
            assert after == before, "second install keeps identical files"
            assert calls.read_text() == checked, "an installed rule is not checked again"
            # Whether both services started after the newest file. The
            # script, read first, is a minute newer than the drop-ins, so a
            # start between them must still wait. The files are two days
            # old, so the midnight `date` reads from an empty start stamp
            # falls after them. [label, pipewire, wireplumber, reply]: a
            # start as seconds after the newest file, None for no start
            # recorded, (ActiveState, start) for a unit that is not active.
            dropins = time.time_ns() // 1000 - 2 * 86400 * 10**6
            for path in (old_conf, hold):
                os.utime(path, ns=(dropins * 1000,) * 2)
            newest = dropins + 60 * 10**6
            os.utime(old_script, ns=(newest * 1000,) * 2)

            def unit_reply(unit, start):
                active, start = start if isinstance(start, tuple) else ("active", start)
                stamp = ""
                if start is not None:
                    began = newest + int(start * 10**6)
                    stamp = time.strftime("%a %Y-%m-%d %H:%M:%S", time.gmtime(began // 10**6)) + ".%06d UTC" % (began % 10**6)
                (home / ("manager-reply." + unit)).write_text("ActiveState=" + active + "\nExecMainStartTimestamp=" + stamp + "\n")

            for label, pipewire, wireplumber, want in [
                ("both services started after the files", 1, 1, "started"),
                ("PipeWire started before the files", -1, 1, "waiting"),
                ("WirePlumber started before the files", 1, -1, "waiting"),
                ("a start between the script and the drop-ins", -1e-6, -30, "waiting"),
                ("a start in the newest file's microsecond", 0, 0, "waiting"),
                ("WirePlumber stopped after starting with the files", 1, ("inactive", 1), "waiting"),
                ("PipeWire records no start", None, 1, "waiting"),
            ]:
                unit_reply("pipewire.service", pipewire)
                unit_reply("wireplumber.service", wireplumber)
                assert run("started") == want, ("services started after the files are read", label)
            for unit in ("pipewire.service", "wireplumber.service"):
                (home / ("manager-reply." + unit)).unlink()
            # The managed helper can be terminated while rename is pending.
            # The acknowledgement proves that it acquired/wrote the temp;
            # signal only the session this test starts and still holds.
            old_conf.write_text(WP.splitlines()[0] + "\nchanged fragment\n")
            barrier = home / "rename-ready"
            mover = programs / "mv"
            mover.write_text('#!/bin/bash\nprintf "ready\\n" >"$RENAME_BARRIER"\nexec /usr/bin/sleep 30\n')
            mover.chmod(0o755)
            interrupted_env = dict(env, RENAME_BARRIER=str(barrier))
            interrupted = subprocess.Popen(["/bin/bash", str(helper), "install", *base,
                                            str(SCRIPT), VERSION, WP, PW], env=interrupted_env,
                                           start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                until = time.monotonic() + 5
                while not barrier.exists() and interrupted.poll() is None and time.monotonic() < until:
                    time.sleep(0.01)
                assert barrier.read_text() == "ready\n", "rename acknowledges acquired temporary"
                os.killpg(interrupted.pid, signal.SIGTERM)
                interrupted.wait(timeout=5)
                assert interrupted.returncode != 0, "interrupted install preserves failure status"
                assert not list(old_conf.parent.glob(old_conf.name + ".*")), "interrupted install removes owned temporary"
            finally:
                if interrupted.poll() is None:
                    os.killpg(interrupted.pid, signal.SIGKILL)
                    interrupted.wait(timeout=5)
                mover.unlink()
            assert install() == "installed"
            hold.unlink()
            hold.symlink_to(home / "foreign")
            assert install() == "unsupported:symlink", "symlink destination is refused"
            hold.unlink()
            hold.write_text("foreign\n")
            assert install() == "unsupported:foreign-file", "foreign destination is refused"
            assert run("remove") == "unsupported:foreign-file", "foreign destination survives removal"
            hold.write_text(PW)
            for path, _ in markers:
                path.write_text("unread\n")
            assert run("remove") == "removed"
            assert not any(p.exists() for p in [old_script, old_conf, hold] + [p for p, _ in markers])
        finally:
            child.terminate()
            child.wait(timeout=5)

    scenario("default")
    scenario("custom", custom=True)
    scenario("system", loaded=False)
    scenario("inaccessible", manager_status=1)


def main():
    source = INSTALL.read_text()
    with tempfile.TemporaryDirectory(prefix="notification-sound-install-") as scratch:
        root = Path(scratch)
        actual = root / "actual"
        actual.mkdir()
        verify(source, actual)
        controls = [
            ("deployment", 'PIPEWIRE_CONFIG_DIR=*|PIPEWIRE_CONFIG_NAME=*|PIPEWIRE_CONFIG_PREFIX=*) refuse config ;;',
             'PIPEWIRE_CONFIG_DIR=*|PIPEWIRE_CONFIG_NAME=*|PIPEWIRE_CONFIG_PREFIX=*) : ;;',
             "unsupported deployment must refuse"),
            ("unit", '[[ $\'\\n\'$properties$\'\\n\' == *$\'\\n\'"$expected"$\'\\n\'* ]] || refuse unit',
             ': "$expected"', "unsupported deployment must refuse"),
            ("inaccessible", 'properties=$(systemctl --user show "$unit" --property=LoadState,ActiveState,MainPID) || refuse unit',
             'properties=$(systemctl --user show "$unit" --property=LoadState,ActiveState,MainPID) || true',
             "unsupported deployment must refuse"),
            ("migration", 'rm -f -- "${retired_markers[@]}"\necho installed', 'echo installed', "old markers are retired"),
            # The restart the install once caused, put back in the helper.
            ("restart", '\necho installed', '\nsystemctl --user restart pipewire.service\necho installed',
             "the install starts no audio service job"),
            ("noop", '[[ $current != "$value" ]] || return 0', ': "$current"', "second install keeps identical files"),
            ("start-order", 'if (( 10#$began <= newest )); then echo waiting; exit; fi', ': "$began"',
             "services started after the files are read"),
            ("newest", '(( 10#$written <= newest )) || newest=$((10#$written))', 'newest=$((10#$written))',
             "services started after the files are read"),
            ("interrupted", '  trap \'rm -f -- "${temporary:?}"\' EXIT',
             '  : "$temporary"', "interrupted install removes owned temporary"),
        ]
        for name, old, new, assertion in controls:
            assert source.count(old) == 1, name
            mutant = root / name
            mutant.mkdir()
            try:
                verify(source.replace(old, new), mutant)
            except AssertionError as error:
                assert assertion in str(error), (name, str(error))
            else:
                raise AssertionError("control survived: " + name)
    print("notification sound install: pass controls=deployment,unit,inaccessible,migration,restart,noop,start-order,newest,interrupted")


if __name__ == "__main__":
    main()
