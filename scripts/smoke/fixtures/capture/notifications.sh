# Shared by the Capture row and its nested notification screenshot scene.
# Viewer/editor/player stand-ins record ordered argv and start no application.
capture_notice_tools() { # ROOT
  capture_open="$1/open-with"
  mkdir -p -- "$capture_open"
  python3 - "$capture_open" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
program = '''#!{python}
import json, sys
from pathlib import Path
root = Path({root!r})
name = Path(sys.argv[0]).name
with (root / (name + ".calls")).open("a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
with (root / "sequence.jsonl").open("a") as output:
    output.write(json.dumps({{"program": name, "argv": sys.argv[1:]}}) + "\\n")
'''
for name in ("viewer", "editor", "player"):
    path = root / name
    path.write_text(program.format(python=sys.executable, root=str(root)))
    path.chmod(0o755)
PY
}

capture_notice_pair() {
  ipc smoke modelRows vgs.notifications rows key,originalId,app,summary,leaving | py_reply 'import json,sys
text=sys.stdin.read().strip(); rows=json.loads(text) if text.startswith("[") else []
print(json.dumps(next(([key,id] for key,id,app,summary,leaving in rows if app=="Capture" and summary=="Screenshot saved" and leaving==""),None)))'
}

capture_notice_pills() {
  ipc smoke layerItems vgs.notifications CardSlot summary,actions | py_reply 'import json,sys
rows=json.load(sys.stdin)
print(json.dumps(next(([action["label"] for action in value["actions"]] for _,_,value in rows if value["summary"]=="Screenshot saved"),None)))'
}

capture_notice_calls() {
  python3 -c 'import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); print(json.dumps([json.loads(line) for line in path.read_text().splitlines()] if path.is_file() else []))' "$capture_open/sequence.jsonl"
}

# The existing harness owns this observer on its private session bus. It
# observes shipped traffic; no product instrumentation or alternate sender.
capture_notice_monitor() { # LOG
  capture_notice_bus_log="$1"
  spawn "$capture_notice_bus_log" "${shell_env[@]}" stdbuf -oL dbus-monitor --session "interface='org.freedesktop.Notifications'"
}

capture_notice_monitor_ready() {
  if grep -q 'member=GetServerInformation' "$capture_notice_bus_log"; then echo True; return; fi
  "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation >/dev/null || return
  echo False
}

capture_notice_bus_counts() { # original notification id, or zero
  python3 - "$capture_notice_bus_log" "${1:-0}" <<'PY'
import json,re,sys
text=open(sys.argv[1]).read(); identifier=int(sys.argv[2])
notify=len(re.findall(r'^method call [^\n]*member=Notify\n\s+string "Capture"\n',text,re.M))
closed=len(re.findall(r'^signal [^\n]*member=NotificationClosed\n\s+uint32 '+str(identifier)+r'\n',text,re.M))
print(json.dumps({"notifyRequests":notify,"closedSignals":closed}))
PY
}

capture_notice_notify_count() { capture_notice_bus_counts | py_reply 'import json,sys; print(json.load(sys.stdin)["notifyRequests"])'; }
capture_notice_closed_count() { capture_notice_bus_counts "$capture_notice_id" | py_reply 'import json,sys; print(json.load(sys.stdin)["closedSignals"])'; }
capture_notice_held() { ipc vgs.notifications invoke status '' | py_reply 'import json,sys; print(json.load(sys.stdin)["held"])'; }

capture_notice_expect_call() { # EXPECTED PROGRAM FILE: append one actual argv expectation
  python3 - "$1" "$2" "$3" <<'PY'
import json,sys
calls=json.loads(sys.argv[1]); program,path=sys.argv[2:]
argv=["--filename",path,"--output-filename",path] if program=="editor" else [path]
print(json.dumps(calls+[{"program":program,"argv":argv}]))
PY
}

capture_notice_record() { # OUTPUT STAGE PAIR PILLS CALLS
  python3 - "$@" "$(capture_notice_held)" "$(capture_notice_bus_counts "${capture_notice_id:-0}")" <<'PY'
import json,sys
path,stage,pair,pills,calls,held,bus=sys.argv[1:]
with open(path,"a") as output:
    output.write(json.dumps({"stage":stage,"pair":json.loads(pair),"pills":json.loads(pills),"calls":json.loads(calls),"heldCount":int(held),**json.loads(bus)})+"\n")
PY
}
