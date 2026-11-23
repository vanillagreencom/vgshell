# Sourced by scripts/smoke/rows/workspaces.sh and scripts/sandbox-shots.sh,
# after the harness. The two-monitor workspaces world both draw: its
# readers, its workspace rules and its settings write.
#
# ws_pills OUTPUT [ID]: the drawn pills of the bar on OUTPUT, [[number,
# lit]] in number order, of widget ID: vgs.workspaces, or the Bar's
# vgs.bar/left-workspaces built-in in a tree from before it; "absent" when
# the bar draws none. ws_placed: each workspace Hyprland holds, by name, and
# the monitor it is on, special workspaces left out. ws_focused: the focused
# workspace's id. ws_rules LUA FIRST SECOND [NUMBER=FIELDS...]: replaces the
# harness's persistent 2 and 100 in LUA with 1 on FIRST, 2 (SECOND's
# default) and 3 on SECOND, then one rule per extra argument, workspace
# NUMBER with the Lua table FIELDS; 1 when the harness's lines are not there
# once each. ws_set JSON: merges JSON object JSON into vgs.workspaces's
# plugins row in the user file.
set -euo pipefail
ws_pills() { # OUTPUT [ID]
  ipc smoke itemValues "bar:$1" "${2:-vgs.workspaces}" BarItem text,active | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(sorted([int(r["text"]), r["active"]] for r in v), separators=(",", ":")) if isinstance(v, list) else "absent")'
}
ws_placed() { hypr -j workspaces | py_reply 'import json,sys; print(json.dumps({w["name"]: w["monitor"] for w in json.load(sys.stdin) if not w["name"].startswith("special:")}, sort_keys=True, separators=(",", ":")))'; }
ws_focused() { hypr -j activeworkspace | py_reply 'import json,sys; print(json.load(sys.stdin)["id"])'; }
ws_rules() { # LUA FIRST SECOND [NUMBER=FIELDS...]
  python3 - "$@" <<'PY' && mv -T -- "$1.next" "$1"
import sys
path, first, second = sys.argv[1:4]
text = open(path).read()
for line in ('hl.workspace_rule({ workspace = "2", persistent = true })\n', 'hl.workspace_rule({ workspace = "100", persistent = true })\n'):
    if text.count(line) != 1:
        sys.exit("ws_rules: the harness line occurs %d times: %s" % (text.count(line), line.strip()))
    text = text.replace(line, "")
rules = [("1", 'monitor = "%s"' % first), ("2", 'monitor = "%s", default = true' % second), ("3", 'monitor = "%s"' % second)]
rules += [tuple(extra.split("=", 1)) for extra in sys.argv[4:]]
text += "".join('hl.workspace_rule({ workspace = "%s", %s })\n' % rule for rule in rules)
open(path + ".next", "w").write(text)
PY
}
ws_set() { # JSON
  user_config_write python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.workspaces"), None)
if row is None:
    row = {"id": "vgs.workspaces"}
    rows.append(row)
row.update(json.loads(sys.argv[2]))
print(json.dumps(config, indent=2))
PY
}
