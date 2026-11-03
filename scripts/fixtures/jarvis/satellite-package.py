#!/usr/bin/env python3
"""A stand-in for the Jarvis package's satellite verbs of `jarvis-session`,
for tests and sandbox scenes. A test copies it to
<home>/.agents/skills/jarvis/scripts/jarvis-session. It opens no connection.

The verbs are the installed package's `status --home HOME --main`,
`forward --home HOME --record PATH` (scripts/lib/session.py, forward.py)
and its setter `main-host --home HOME --set VALUE` (session.py main_host),
which judges VALUE by the package's role rule first and refuses one that is
neither empty nor DEST:/abs/home with `jarvis-session: main-host=refused
cause=setting-invalid` and exit 2, storing nothing, then prints
{"JARVIS_MAIN_HOST":VALUE}.

Beside itself it appends one JSON line a call to calls.log: the argv, the
environment and, for a forward, the record it read. It answers from
satellite.json beside itself, all keys optional:
  "package": "current", or "old" for a package older than the satellite
             contract, which refuses each satellite verb as its argparse
             does; plain `status`, the session reader's, answers a session
             that never started;
  "setter":  "absent" for the installed package before KEN-4874, which
             refuses main-host alone; "unreadable" or "unwritable" for a
             setter that cannot read the settings or write the private
             file, which refuses as settings-unreadable or
             private-file-unwritable and stores nothing;
  "main":    the stored setting, "" for the main, which main-host writes;
  "reachable": the last probe's answer, true, false or null;
  "forward": {"exit": 0} delivered, {"exit": 75, "cause": KEY} queued,
             {"exit": 2, "cause": KEY} refused.
"""
import json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
state_file = os.path.join(here, "satellite.json")
argv = sys.argv[1:]
try:
    with open(state_file) as source:
        state = json.load(source)
except FileNotFoundError:
    state = {}


def option(name):
    for index, value in enumerate(argv):
        if value == name and index + 1 < len(argv):
            return argv[index + 1]
        if value.startswith(name + "="):
            return value[len(name) + 1:]
    return None


def refuse(line):
    sys.stderr.write(line + "\n")
    sys.exit(2)


def judged(value):
    """The package's role judge (watch.py role): "main", "invalid" or the DEST:/abs/home match."""
    if not value:
        return "main"
    match = re.fullmatch(r"([^\s:/-][^\s:/]*):(/.*)", value)
    return match if match and match[2].isprintable() else "invalid"


call = {"argv": argv, "env": dict(os.environ)}
verb = argv[0] if argv else ""
if verb == "forward" and option("--record") is not None:
    with open(option("--record")) as source:
        call["record"] = json.load(source)
fd = os.open(os.path.join(here, "calls.log"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
os.write(fd, (json.dumps(call) + "\n").encode())
os.close(fd)

if option("--home") is None:
    refuse("jarvis-session: arguments=invalid")
if verb == "status" and "--main" not in argv:
    # The session reader's own status: a session that never started, as
    # scripts/fixtures/jarvis/owner-asks.js answers it.
    print(json.dumps({"v": 1, "state": "stopped", "reason": "never-started", "detail": "",
                      "home": option("--home"), "harness": None, "account": None}))
    sys.exit(0)
if state.get("package") == "old":
    refuse("jarvis-session: arguments=invalid")
if verb == "main-host" and state.get("setter") == "absent":
    refuse("jarvis-session: arguments=invalid")
if verb == "main-host" and option("--set") is not None:
    value = option("--set")
    if judged(value) == "invalid":
        refuse("jarvis-session: main-host=refused cause=setting-invalid")
    if state.get("setter") in ("unreadable", "unwritable"):
        refuse("jarvis-session: main-host=refused cause="
               + {"unreadable": "settings-unreadable", "unwritable": "private-file-unwritable"}[state["setter"]])
    state["main"] = value
    with open(state_file + ".next", "w") as out:
        json.dump(state, out)
    os.replace(state_file + ".next", state_file)
    print(json.dumps({"JARVIS_MAIN_HOST": value}))
    sys.exit(0)
if verb == "status" and "--main" in argv:
    main = state.get("main", "")
    if main == "":
        print(json.dumps({"v": 1, "role": "main"}))
        sys.exit(0)
    match = judged(main)
    match = None if match == "invalid" else match
    reachable = state.get("reachable")
    print(json.dumps({"v": 1, "role": "satellite", "main": match[1] if match else None,
                      "reachable": reachable, "checked_at": None,
                      "cause": "setting-invalid" if not match else "main-unreachable" if reachable is False else None,
                      "last_answer": None, "requests": []}))
    sys.exit(0)
if verb == "forward" and "record" in call:
    answer = state.get("forward", {"exit": 0})
    if answer["exit"] == 2:
        refuse("jarvis-session: forward=refused cause=" + answer["cause"])
    queued = answer["exit"] == 75
    print(json.dumps({"v": 1, "request": call["record"]["request"]["ref"], "key": "forward-stand-in",
                      "state": "queued" if queued else "delivered", "forwarded": None if queued else "stand-in-1",
                      "cause": answer.get("cause") if queued else None}))
    sys.exit(answer["exit"])
refuse("jarvis-session: arguments=invalid")
