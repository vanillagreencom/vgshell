#!/usr/bin/env bash
# voxtype's JSON config and compiled-engine readings, shared by dictation
# setup and the system-step probe. Invalid readings fail the caller.
vgs_voxtype_supervise() { # ROLE ARGV...
  # QProcess itself drains even a stream without a parser. Keep both raw
  # pipes here, outside Quickshell. A failed transport ends the child once;
  # The existing process-group owner also covers this child's life.
  exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/voxtype.py" supervise "$@"
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
