#!/usr/bin/env python3
"""A stand-in for the Jarvis package's satellite verbs of `jarvis-session`,
for tests and sandbox scenes. A test copies it to
<home>/.agents/skills/jarvis/scripts/jarvis-session. It opens no connection.

The verbs are the installed package's `status --home HOME --main` and
`forward --home HOME --record PATH` (scripts/lib/session.py, forward.py),
and `main-host --home HOME --set DEST:HOME`, the setter KEN-4874 asks the
package for, which prints {"v":1,"main":VALUE}. Keep that verb here until
KEN-4874 lands; if it lands under another name, follow it.

Beside itself it appends one JSON line a call to calls.log: the argv and,
for a forward, the record it read. It answers from satellite.json beside
itself, all keys optional:
  "package": "current", or "old" for a package older than the satellite
             contract, which refuses each satellite verb as its argparse
             does; plain `status`, the session reader's, answers a session
             that never started;
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


call = {"argv": argv}
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
if verb == "main-host" and option("--set") is not None:
    state["main"] = option("--set")
    with open(state_file + ".next", "w") as out:
        json.dump(state, out)
    os.replace(state_file + ".next", state_file)
    print(json.dumps({"v": 1, "main": state["main"]}))
    sys.exit(0)
if verb == "status" and "--main" in argv:
    main = state.get("main", "")
    if main == "":
        print(json.dumps({"v": 1, "role": "main"}))
        sys.exit(0)
    # The package's role judge (watch.py role).
    match = re.fullmatch(r"([^\s:/-][^\s:/]*):(/.*)", main)
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
