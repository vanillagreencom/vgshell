#!/usr/bin/env python3
"""A stand-in for the Jarvis package's `jarvis-session`, for tests and
sandbox scenes. A test copies it to
<home>/.agents/skills/jarvis/scripts/jarvis-session. It starts nothing.

Beside itself it appends one JSON line a call to calls.log: the argv, the
working folder, XDG_SESSION_ID, which of the shell's own variables
reached it and the time it started, in seconds since the epoch. It answers
from answers.json beside itself, an object keyed by verb:
{"exit": N, "object": {...}} prints the contract's object, with the
fields the entry leaves out filled in, and {"exit": N, "raw": TEXT} prints
TEXT as it is. A verb with no entry exits 2 with a keyed line, as the
contract's argument refusal does. An entry's "hold": SECONDS stalls the
call as a command does that waits on a program it started: a child that
holds the output open sleeps that long, and so does the call. An entry's
"then": {VERB: ENTRY, ...} replaces those verbs' entries in answers.json
before the call answers, as a call that changes the session changes what
the next status reads.

It holds its answers to the package's resume reasons (design VGS-1797,
`status` reason during a resume, and `dismiss`): a session `start`
started beside a kept record never reads `resuming` or `resumed`,
`running resumed` over a record comes only once the delegate step has its
outcome, and `dismiss` drops the record, so its answer carries none. A
package without `dismiss` is an answers.json with no entry for it. An
entry whose object, or an object under its "then", breaks a rule exits 2 with
`jarvis-session: stand-in=contract verb=VERB reason=REASON`, so no test
models a package that does not exist."""
import json, os, subprocess, sys, time

here = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[1:]
record = {"argv": argv, "cwd": os.getcwd(), "session": os.environ.get("XDG_SESSION_ID"),
          "leaked": sorted(name for name in ("TMUX", "TMUX_PANE", "VGSHELL_RUNNER_PID") if name in os.environ),
          "time": time.time()}
fd = os.open(os.path.join(here, "calls.log"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
os.write(fd, (json.dumps(record) + "\n").encode())
os.close(fd)
try:
    with open(os.path.join(here, "answers.json")) as source:
        answers = json.load(source)
except FileNotFoundError:
    answers = {}
entry = answers.get(argv[0]) if argv else None
if entry is None:
    sys.stderr.write("jarvis-session: verb=%s\n" % (argv[0] if argv else ""))
    sys.exit(2)
for value in [entry] + list(entry.get("then", {}).values()):
    shown = value.get("object", {})
    restart, reason = shown.get("restart"), shown.get("reason")
    if restart is None:
        continue
    if argv[0] == "dismiss":
        sys.stderr.write("jarvis-session: stand-in=contract verb=dismiss reason=%s\n" % reason)
        sys.exit(2)
    delegate = [step["outcome"] for step in restart["steps"] if step["kind"] == "delegate"]
    if (argv[0] == "start" and reason in ("resuming", "resumed")) or (reason == "resumed" and "pending" in delegate):
        sys.stderr.write("jarvis-session: stand-in=contract verb=%s reason=%s\n" % (argv[0], reason))
        sys.exit(2)
if "then" in entry:
    answers.update(entry["then"])
    with open(os.path.join(here, "answers.json.next"), "w") as out:
        json.dump(answers, out)
    os.replace(os.path.join(here, "answers.json.next"), os.path.join(here, "answers.json"))
if "hold" in entry:
    subprocess.Popen(["sleep", str(entry["hold"])])
    time.sleep(entry["hold"])
if "raw" in entry:
    sys.stdout.write(entry["raw"])
else:
    home = argv[argv.index("--home") + 1] if "--home" in argv else None
    value = {"v": 1, "home": home, "harness": None, "account": None, "origin": None, "boot": None, "terminal": None, "detail": ""}
    value.update(entry["object"])
    sys.stdout.write(json.dumps(value) + "\n")
sys.exit(entry.get("exit", 0))
