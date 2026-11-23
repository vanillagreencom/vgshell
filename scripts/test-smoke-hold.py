#!/usr/bin/env python3
"""Drive harness.sh's quiet-host hold from worlds that run at once.

Each world is a bash process in its own user and PID namespace, as a
validation unit's world is, sourcing the hold functions of
scripts/smoke/harness.sh unchanged: smoke_hold_row, the boundary smoke_row
calls, smoke_hold_begin and smoke_hold_end around a timed window, and the
lock takes under them, over one lock directory. A wrapper around
smoke_lock_take reports each request and grant; no compositor, shell or
GPU is used.

Cases, each a JSON line on stdout:
- order: while A holds a window, B asks for a row and holds the turn lock, and C
  then asks for a window. B's row starts before C's window: a window that
  arrives after a row waits behind it. The harness before VGS-2746 let C
  pass B, which is how measure-shader.sh's back-to-back windows kept a
  notifications retake in another unit waiting until the driver's
  no-progress stop ended its world.
- killed: a window killed while it holds the turn lock frees it; a row
  starts.
- bounded: a row whose turn wait reaches its bound behind a window that is
  draining another world's row still starts, logging turn=none.
- stream: two worlds at once. W opens twelve windows back to back, as
  measure-shader.sh does; R runs four rows, one holding a window of its
  own. No window overlaps another world's row or window, each wait passes
  at most one window or row of the other world, and both worlds wait for
  each other at least once.

Usage: scripts/test-smoke-hold.py [--harness FILE]
--harness drives another copy of harness.sh, such as the base revision's,
to show that a harness without the turn lock's order fails the order case.
The lock files each case creates, and the admission lock the order case's
barriers name, are read from the smoke_lock_take calls of the copy under
test, so that control fails on the order it asserts.
Exit 0 when every case passes, 1 with the failed cases named, 77 without
unshare or bash.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent

FIXTURE = r'''
set -euo pipefail
source "$1"
name=$2 sandbox=$3 smoke_hold_dir=$4 qml_smoke_idle_secs=$5 role=$6 events=$7
mkdir -p "$sandbox"
now_ms() { printf '%s\n' "$(( ${EPOCHREALTIME/./} / 1000 ))"; }
fail() { printf 'failure %s\n' "$*"; exit 1; }
event() { printf 'event %s %s\n' "$name" "$*"; }
# The stream worlds append to one file; each line is one O_APPEND write
# made while the world holds the lock the line reports, so the file's order
# is the order the locks were held in.
log() { printf '%s %s\n' "$name" "$*" >>"$events"; }
smoke_lock_take() {
  event "request $1 $2"
  admission_take "$@" || return $?
  event "granted $1 $2"
}
case $role in
  row)
    read -r command
    event row-request
    smoke_hold_row begin "$name"
    event row
    read -r command
    smoke_hold_row end "$name" ;;
  row-window|window)
    if [[ $role == row-window ]]; then smoke_hold_row begin "$name"; event row; else event ready; fi
    read -r command
    if [[ $command == window ]]; then
      event window-request
      smoke_hold_begin "$name" window
      event held
      read -r command
      smoke_hold_end
      event window-ended
    fi
    if [[ $role == row-window ]]; then smoke_hold_row end "$name"; fi ;;
  # Each sleep is the work inside a held section, long enough that two
  # sections the locks failed to exclude would interleave in the file.
  stream-windows)
    for i in $(seq 1 12); do
      log "request $i"
      smoke_hold_begin "$name" "w$i"
      log "held $i"; sleep 0.5; log "end $i"
      smoke_hold_end
    done ;;
  stream-rows)
    for j in 1 2 3 4; do
      log "request $j"
      smoke_hold_row begin "$name"
      log "row $j"; sleep 0.4
      if ((j == 2)); then
        log "window-request $j"
        smoke_hold_begin "$name" "r$j"
        log "held $j"; sleep 0.5; log "window-end $j"
        smoke_hold_end
        log "retaken $j"; sleep 0.4
      fi
      log "row-end $j"
      smoke_hold_row end "$name"
    done ;;
  *) fail "role=$role" ;;
esac
event done
'''


def hold_functions(harness):
    """The hold's functions from HARNESS, with smoke_lock_take renamed so
    the fixture's reporting wrapper can call it; the lock files its takes
    open; and its admission lock, the one besides hold."""
    text = harness.read_text()
    start, end = 'smoke_hold_depth=0 ', '# click X Y:'
    assert text.count(start) == 1 and text.count(end) == 1, ('harness-anchors', str(harness))
    source = text[text.index(start):text.index(end)]
    assert source.count('smoke_lock_take() {') == 1, ('harness-take', str(harness))
    locks = set(re.findall(r'smoke_lock_take -[sx] ([a-z]+)', source))
    admission = locks - {'hold'}
    assert 'hold' in locks and len(admission) == 1, ('harness-locks', sorted(locks), str(harness))
    return source.replace('smoke_lock_take() {', 'admission_take() {'), sorted(locks), admission.pop()


class Worlds:
    """Fixture worlds over one lock directory, read through their reports."""

    def __init__(self, root, harness, label, deadline_secs):
        functions, lock_names, self.admission = harness
        self.folder = root / label
        self.folder.mkdir()
        self.locks = self.folder / 'locks'
        self.locks.mkdir()
        for name in lock_names:
            (self.locks / ('vgs-smoke-' + name)).touch()
        self.script = self.folder / 'functions.sh'
        self.script.write_text(functions)
        self.events_file = self.folder / 'events'
        self.label = label
        self.poll = selectors.DefaultSelector()
        self.children, self.reports, self.events = {}, {}, []
        self.deadline = time.monotonic() + deadline_secs

    def start(self, name, role, bound):
        env = {key: os.environ[key] for key in ('PATH', 'TMPDIR') if key in os.environ}
        env.update(LC_ALL='C.UTF-8', VGS_TEST_RUN='1')
        child = subprocess.Popen([UNSHARE, '--user', '--map-current-user', '--pid', '--fork', '--kill-child', '--mount-proc',
                                  BASH, '-c', FIXTURE, '_', str(self.script), name, str(self.folder / name), str(self.locks),
                                  str(bound), role, str(self.events_file)],
                                 env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        self.children[name] = child
        self.reports[name] = []
        self.poll.register(child.stdout, selectors.EVENT_READ, name)

    def read_ready(self, timeout):
        for key, _ in self.poll.select(timeout):
            line = key.fileobj.readline()
            if not line:
                self.poll.unregister(key.fileobj)
                continue
            line = line.decode().rstrip()
            self.reports[key.data].append(line)
            if line.startswith('event '):
                self.events.append(line[6:])

    def wait_for(self, *wanted):
        while not any(item in self.events for item in wanted):
            remaining = self.deadline - time.monotonic()
            assert remaining > 0, ('deadline', self.label, wanted, self.reports)
            self.read_ready(remaining)
        return next(item for item in self.events if item in wanted)

    def send(self, name, command):
        self.children[name].stdin.write((command + '\n').encode())
        self.children[name].stdin.flush()

    def finish(self, skip=()):
        for name, child in self.children.items():
            if name in skip:
                continue
            child.wait(timeout=max(0.1, self.deadline - time.monotonic()))
            self.reports[name].extend(child.stdout.read().decode().splitlines())
            assert child.returncode == 0, (self.label, name, child.returncode, self.reports)

    def close(self):
        for child in self.children.values():
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)
        self.poll.close()


def retake_line(reports, name):
    pattern = r'qml-smoke: smoke-hold row=' + name + r' window=window lock=shared phase=retake wait_ms=[0-9]+'
    return any(re.fullmatch(pattern, line) for line in reports[name])


def case_order(root, harness):
    worlds = Worlds(root, harness, 'order', 30)
    try:
        worlds.start('A', 'row-window', 8)
        worlds.start('C', 'window', 8)
        worlds.start('B', 'row', 8)
        worlds.wait_for('A row')
        worlds.wait_for('C ready')
        worlds.send('A', 'window')
        worlds.wait_for('A held')
        worlds.send('B', 'start')
        worlds.wait_for('B granted -x ' + worlds.admission)
        worlds.send('C', 'window')
        # C's request is out: either it waits for the turn lock B holds, or
        # it passed it and asks for the hold A holds.
        worlds.wait_for('C request -x ' + worlds.admission, 'C request -s ' + worlds.admission, 'C request -x hold')
        worlds.send('A', 'release')
        first = worlds.wait_for('B row', 'C held')
        if first == 'B row':
            worlds.send('B', 'finish')
            worlds.wait_for('C held')
            worlds.send('C', 'release')
        else:
            worlds.send('C', 'release')
            worlds.wait_for('B row')
            worlds.send('B', 'finish')
        worlds.finish()
        for name, lines in worlds.reports.items():
            assert not any('hold=none' in line or worlds.admission + '=none' in line for line in lines), ('order-bound-reached', worlds.reports)
        assert retake_line(worlds.reports, 'A'), ('order-missing-retake', worlds.reports)
        assert first == 'B row', ('later-window-passed-waiting-row', worlds.events)
        return dict(events=worlds.events)
    finally:
        worlds.close()


def case_killed(root, harness):
    worlds = Worlds(root, harness, 'killed', 30)
    try:
        worlds.start('A', 'row-window', 8)
        worlds.start('C', 'row-window', 8)
        worlds.start('B', 'row', 8)
        worlds.wait_for('A row')
        worlds.wait_for('C row')
        worlds.send('C', 'window')
        worlds.wait_for('C request -x hold')
        worlds.children['C'].kill()
        worlds.children['C'].wait(timeout=5)
        worlds.send('B', 'start')
        worlds.wait_for('B row')
        worlds.send('B', 'finish')
        worlds.send('A', 'finish')
        worlds.finish(skip=('C',))
        assert 'C held' not in worlds.events, ('killed-window-held', worlds.events)
        for name in ('A', 'B'):
            assert not any('hold=none' in line or worlds.admission + '=none' in line for line in worlds.reports[name]), ('killed-turn-not-freed', worlds.reports)
        return dict(events=worlds.events)
    finally:
        worlds.close()


def case_bounded(root, harness):
    worlds = Worlds(root, harness, 'bounded', 30)
    try:
        worlds.start('A', 'row-window', 60)
        worlds.start('C', 'row-window', 60)
        worlds.start('B', 'row', 2)
        worlds.wait_for('A row')
        worlds.wait_for('C row')
        worlds.send('C', 'window')
        worlds.wait_for('C request -x hold')
        worlds.send('B', 'start')
        worlds.wait_for('B row')
        assert 'C held' not in worlds.events, ('window-held-before-bound', worlds.events)
        worlds.send('B', 'finish')
        worlds.send('A', 'finish')
        worlds.wait_for('B done')
        worlds.wait_for('A done')
        worlds.wait_for('C held')
        worlds.send('C', 'release')
        worlds.finish()
        assert any(f'{worlds.admission}=none cause=[wait-bound secs=2 lock={worlds.admission} mode=-x]' in line for line in worlds.reports['B']), ('bounded-turn-line', worlds.reports)
        for name, lines in worlds.reports.items():
            assert not any('hold=none' in line for line in lines), ('bounded-hold-none', worlds.reports)
            if name != 'B':
                assert not any(worlds.admission + '=none' in line for line in lines), ('bounded-turn-none', worlds.reports)
        assert retake_line(worlds.reports, 'C'), ('bounded-missing-retake', worlds.reports)
        return dict(events=worlds.events)
    finally:
        worlds.close()


def stream_judge(lines):
    """Exclusion, the one-pass bound and mutual waits over the stream's
    events file: a list of 'NAME KIND N' lines."""
    rows = [line.split() for line in lines]
    assert all(len(row) == 3 for row in rows), ('stream-events-shape', lines)
    window_open = row_open = None
    for who, kind, n in rows:
        if who == 'W' and kind == 'held':
            assert row_open is None, ('window-overlaps-row', row_open, n, lines)
            window_open = n
        elif who == 'W' and kind == 'end':
            window_open = None
        elif who == 'R' and kind in ('row', 'retaken', 'held'):
            assert window_open is None, ('row-overlaps-window', window_open, kind, n, lines)
            row_open = kind + n
        elif who == 'R' and kind in ('window-request', 'window-end', 'row-end'):
            row_open = None
    def span(who, start, end, n):
        first = rows.index([who, start, n])
        last = rows.index([who, end, n])
        assert first < last, ('stream-span-order', who, start, end, n, lines)
        return rows[first + 1:last]
    waits = [('R', 'request', 'row', j) for j in '1234'] + [('R', 'window-request', 'held', '2'), ('R', 'window-end', 'retaken', '2')]
    r_waited = w_waited = False
    for who, start, end, n in waits:
        inside = span(who, start, end, n)
        passed = [row for row in inside if row[:2] == ['W', 'held']]
        assert len(passed) <= 1, ('row-passed-by-windows', start, n, passed, lines)
        r_waited = r_waited or any(row[:2] == ['W', 'end'] for row in inside)
    for i in range(1, 13):
        inside = span('W', 'request', 'held', str(i))
        passed = [row for row in inside if row[0] == 'R' and row[1] in ('row', 'retaken', 'held')]
        assert len(passed) <= 1, ('window-passed-by-rows', i, passed, lines)
        w_waited = w_waited or any(row[0] == 'R' and row[1] in ('row-end', 'window-request', 'window-end') for row in inside)
    assert r_waited and w_waited, ('stream-no-contention', r_waited, w_waited, lines)


def case_stream(root, harness):
    worlds = Worlds(root, harness, 'stream', 90)
    try:
        worlds.start('W', 'stream-windows', 60)
        # R starts once W holds its first window, so the two contend.
        while not (worlds.events_file.exists() and 'W held 1' in worlds.events_file.read_text().splitlines()):
            assert time.monotonic() < worlds.deadline and worlds.children['W'].poll() is None, ('stream-first-window', worlds.reports)
            worlds.read_ready(0.05)
        worlds.start('R', 'stream-rows', 60)
        worlds.wait_for('W done')
        worlds.wait_for('R done')
        worlds.finish()
        for lines in worlds.reports.values():
            assert not any('hold=none' in line or worlds.admission + '=none' in line for line in lines), ('stream-bound-reached', worlds.reports)
        lines = worlds.events_file.read_text().splitlines()
        stream_judge(lines)
        return dict(events=lines)
    finally:
        worlds.close()


def main():
    parser = argparse.ArgumentParser(description='Drive the quiet-host hold from worlds that run at once.')
    parser.add_argument('--harness', type=Path, default=REPO / 'scripts/smoke/harness.sh')
    args = parser.parse_args()
    harness = hold_functions(args.harness)
    root = Path(tempfile.mkdtemp(prefix='test-smoke-hold.'))
    failed = []
    try:
        for name, case in (('order', case_order), ('killed', case_killed), ('bounded', case_bounded), ('stream', case_stream)):
            try:
                result = case(root, harness)
                print(json.dumps(dict(case=name, result='pass', **result)), flush=True)
            except AssertionError as error:
                failed.append(name)
                print(json.dumps(dict(case=name, result='fail', reason=repr(error.args[0] if error.args else error)[:4000])), flush=True)
    finally:
        shutil.rmtree(root)
    if failed:
        print('test-smoke-hold: failed=' + ','.join(failed), file=sys.stderr)
        sys.exit(1)


def tool(name):
    path = shutil.which(name)
    if not path:
        print('test-smoke-hold: status=not-measured missing=' + name, file=sys.stderr)
        sys.exit(77)
    return path


if __name__ == '__main__':
    UNSHARE, BASH = tool('unshare'), tool('bash')
    main()
