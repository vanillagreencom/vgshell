# The Tailscale section, vgs.tailscale, over the device fakes' stand-ins
# (docs/architecture/validation.md § Host safety). No call reaches the
# host's tailscale, tailscaled, browser or sudo: `tailscale` and `xdg-open`
# are the recorded stand-ins in the shell's PATH directory, which answer
# `status --json` from the shapes in scripts/fixtures/tailscale/, and the core's
# step probe reads the same `tailscale` through a link the row adds to the
# fakes' system tree and removes. The row stands over the tailscale
# stand-in with a wrapper that records each call through it and then, on
# the row's markers alone, holds one poll open, answers as a daemon that
# is off, refuses one `set` or one sign-in with the CLI's access-denied
# text, or prints a sign-in address and waits.
#
# Rows: the service publishes the fixture's state to the widget, the
# flyout and the pane; an unset operator offers Allow and locks the
# connection switch, whose reason opens on hover in the flyout, where it
# covers no connection text or control, over the Setup paragraph that
# repeats its cause, under pointer and keyboard focus in both themes;
# the reason also opens on keyboard focus
# in the pane; Space on the locked switch starts no change;
# the keyboard reaches Allow and then the switch's unlock mark, which runs
# the same step and hands the terminal `vgshell system apply
# tailscale-operator`, after which no reason is left; keys alone then
# toggle the connection, `down` and
# `up`, and choose an exit node, `set --exit-node=<dns name>`, with no peer
# id in any argv; a change that ends with a plain exit 1, a change the CLI
# denies and a sign-in it denies each leave a problem, the denied ones
# another than the plain one; the poll interval is 3 s while a view is open and the
# setting's 30 s while none is; every `status --json` call the stand-in
# records is one the service started; a held poll is killed 10 s after its
# start while a refresh arrives every second; sign-in hands the printed
# address to the xdg-open stand-in; a daemon that is off offers Enable.
# Controls, a copy of the plugin whose widget polls on its own, whose
# refresh restarts the watchdog and which does not know the access-denied
# text: the stand-in records a call the service did not start, the held
# poll outlives 20 s of refreshes, and the denied change leaves the plain
# one's problem. The reason's place moved onto a text reads covered. The
# pointer off the locked switch reads its reason closed, and the lock's Space reads no change, so neither reader always
# passes.
#
# The held poll's wait is the service's own 10 s watchdog, read on the
# wall clock with a refresh every second; the row accepts 9 s to 20 s,
# since a refresh that moved the deadline would hold it past any bound.
# Every other reading is expect_poll's: 25 reads 0.2 s apart.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.tailscale/* shell/plugins/vgs.system/* shell/plugins/vgs.settings/* scripts/fixtures/tailscale/* scripts/smoke/fixtures/devices/* shell/Commons/SettingValues.js shell/Commons/qmldir shell/Ui/layout/DeviceList.qml shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/plugins/vgs.vpn/manifest.json shell/Core/Config.qml shell/Core/Registry.qml shell/Core/ConfigLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system bin/vgshell-tui scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh shell/Ui/controls/RowAction.qml shell/Ui/controls/Switch.qml shell/Ui/controls/DisabledReason.qml shell/Ui/controls/UnlockMark.qml shell/Ui/layout/Pane.qml shell/Ui/overlay/Tooltip.qml shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Ui/foundation/KeyNavLogic.js themes/vgs/theme.json themes/catalog/flexoki-light/theme.json
set -euo pipefail
devices_ready tailscale || return 0
tailscale_saved="$sandbox/tailscale-shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$tailscale_saved"
tailscale_dir="$sandbox/tailscale"
tailscale_fixtures="$repo/scripts/fixtures/tailscale"
tailscale_login_url="https://login.fixture.example/a/smoke0123456789"
tailscale_system_link="$devices_system_root/usr/bin/tailscale"
mkdir -p -- "$tailscale_dir"
cp -- "$tailscale_fixtures/service-off.txt" "$tailscale_dir/service-off.text"
cp -- "$tailscale_fixtures/access-denied.txt" "$tailscale_dir/access-denied.text"
{
  printf '#!/usr/bin/env bash\ndir=%q saved=%q url=%q\n' "$tailscale_dir" "$(sentinel_saved "$shim/tailscale")" "$tailscale_login_url"
  cat <<'EOF'
if [[ "$*" == "status --json" ]]; then
  if mv -- "$dir/hang" "$dir/hang.taken" 2>/dev/null; then
    "$saved" "$@" >/dev/null 2>&1 || true
    echo $$ >"$dir/hang.pid.next" && mv -f -- "$dir/hang.pid.next" "$dir/hang.pid"
    exec sleep 60
  fi
  if [[ -e $dir/service-off ]]; then
    "$saved" "$@" >/dev/null 2>&1 || true
    cat -- "$dir/service-off.text" >&2
    exit 1
  fi
elif [[ "$*" == "login --timeout 0" ]]; then
  "$saved" "$@" >/dev/null 2>&1 || true
  if mv -- "$dir/login-denied" "$dir/login-denied.taken" 2>/dev/null; then
    cat -- "$dir/access-denied.text" >&2
    exit 1
  fi
  printf 'To authenticate, visit:\n\n\t%s\n\n' "$url" >&2
  for _ in $(seq 1 300); do
    if [[ -e $dir/login-release ]]; then exit 0; fi
    sleep 0.1
  done
  exit 1
elif [[ ${1:-} == set ]] && mv -- "$dir/denied" "$dir/denied.taken" 2>/dev/null; then
  "$saved" "$@" >/dev/null 2>&1 || true
  cat -- "$dir/access-denied.text" >&2
  exit 1
fi
exec "$saved" "$@"
EOF
} | sentinel_stand_over "$shim/tailscale"

tailscale_warning() { ipc smoke readInstance "$(bar_key)" vgs.tailscale view | py_reply 'import json,sys; print(str(json.load(sys.stdin)["warning"]).lower())'; }
tailscale_widget() { ipc smoke readInstance "$(bar_key)" vgs.tailscale visible; }
tailscale_icon() { ipc smoke readDescendant "$(bar_key)" vgs.tailscale BarItem iconName; }
tailscale_use() { device_reply tailscale 0 "$(<"$tailscale_fixtures/$1")" status --json; }
tailscale_value() { ipc smoke statusValues vgs.tailscale | py_reply 'import json,sys; v=json.load(sys.stdin).get("tailscale"); print("unpublished" if v is None else json.dumps(v[sys.argv[1]]))' "$1"; }
tailscale_setup() { ipc smoke statusValues vgs.tailscale | py_reply 'import json,sys; v=json.load(sys.stdin).get("setup"); print("unpublished" if v is None else v.get("action", "none"))'; }
tailscale_step() {
  ipc shell lent | py_reply 'import json,sys
system = json.load(sys.stdin).get("system") or {}
steps = system.get("steps") or {}
step = steps.get(sys.argv[1])
if step is None:
    print("unpublished")
else:
    print(step["state"] + " " + step["reason"])' "$1"
}
tailscale_step_cases() {
  (
    local snapshot want got
    [[ $# -eq 0 ]] || source "$1" || return 2
    while IFS='|' read -r snapshot want; do
      got="$(ipc() { printf '%s\n' "$snapshot"; }; tailscale_step service-tailscaled)" || return 1
      [[ $got == "$want" ]] || return 1
    done <<'TAILSCALE_STEPS'
{}|unpublished
{"system":null}|unpublished
{"system":{}}|unpublished
{"system":{"steps":null}}|unpublished
{"system":{"steps":{}}}|unpublished
{"system":{"steps":{"service-tailscaled":null}}}|unpublished
{"system":{"steps":{"service-tailscaled":{"state":"ready","reason":"active"}}}}|ready active
TAILSCALE_STEPS
  )
}
tailscale_step_control() {
  (
    local scratch status=0
    scratch="$(mktemp -d)" || return 1
    [[ -d $scratch && ! -L $scratch ]] || return 1
    trap 'rm -rf -- "${scratch:?}"' EXIT
    python3 - "${BASH_SOURCE[0]}" "$scratch/step.sh" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index("tailscale_step() {\n")
body = source[start:source.index("\n}\n", start) + 3]
needle = "if step is None:"
assert body.count(needle) == 1
changed = body.replace(needle, "if step is None and False:")
assert changed != body
pathlib.Path(sys.argv[2]).write_text(changed)
PY
    [[ $? -eq 0 ]] || return 1
    tailscale_step_cases "$scratch/step.sh" >"$scratch/control.log" 2>&1 || status=$?
    [[ $status -eq 1 ]]
  )
}
if tailscale_step_cases; then ok "the step reader waits for unpublished system, steps and named step, then preserves ready state and reason"; else fail "the step reader cannot distinguish unpublished from ready"; fi
if tailscale_step_control; then ok "control: direct indexing of an unpublished step fails its reader cases"; else fail "control: direct indexing of an unpublished step stayed green"; fi
tailscale_shown() { [[ $(ipc smoke instanceGeometry "$1" vgs.tailscale) != absent ]] && echo shown || echo hidden; }
tailscale_body() { ipc smoke readDescendant "$1" vgs.tailscale TailscaleBody "$2"; }
tailscale_reason_names() { tailscale_body "$1" lockReason | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$2"; }
tailscale_mark() { [[ $(ipc smoke labelledGeometry "$1" vgs.tailscale IconButton "$2") != absent ]] && echo drawn || echo absent; }
tailscale_tip() { ipc smoke itemValues "$1" vgs.tailscale Tooltip text,opened | py_reply 'import json,sys; print(next((json.dumps(v["text"]) for v in json.load(sys.stdin) if v["opened"]), "closed"))'; }
# The pointer on the flyout's header switch, 4 px in from its start edge,
# away from the unlock mark after it, then the tooltip open there. A locked
# switch reports no hover, so point_item cannot settle on it; each call
# reads the box again, as the flyout may still move.
tailscale_switch_tip() {
  local rect x y
  rect="$(ipc smoke itemGeometry panel vgs.tailscale Switch "")" || return 1
  [[ $rect == \[* ]] || { echo absent; return 0; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x + 4), int(y + h / 2))' "$rect") || return 1
  hover "$x" "$y" || return 1
  tailscale_tip panel
}
# The open reason's place against what its window draws (Tooltip's
# `placed` and `scene`): "free", or the text, image and Tab stop pixels it
# covers, "outside" past the window's content box, "closed" with none open.
# PLANT "obstacle" moves the place onto the first drawn text first, the
# judge's control.
tailscale_tip_cover() { # HOST [PLANT]
  ipc smoke itemValues "$1" vgs.tailscale Tooltip opened,placed,scene | py_reply '
import json, sys
tips = [t for t in json.load(sys.stdin) if t["opened"] and isinstance(t.get("scene"), dict)]
if not tips: print("closed"); sys.exit()
s, p = tips[0]["scene"], tips[0]["placed"]
x, y, w, h = p["x"] + s["origin"]["x"], p["y"] + s["origin"]["y"], p["width"], p["height"]
if sys.argv[1] == "obstacle":
    first = next(o for o in s["obstacles"] if not o["control"])
    x, y = first["x"], first["y"]
c = s["content"]
if x < c["x"] or y < c["y"] or x + w > c["x"] + c["width"] or y + h > c["y"] + c["height"]: print("outside"); sys.exit()
def cover(o): return max(0, min(x + w, o["x"] + o["width"]) - max(x, o["x"])) * max(0, min(y + h, o["y"] + o["height"]) - max(y, o["y"]))
area = sum(cover(o) for o in s["obstacles"])
print("free" if area == 0 else "covers %d px" % area)' "${2:-}"
}
tailscale_tip_cover_word() { local reading; reading="$(tailscale_tip_cover "$@")" || return 1; echo "${reading%% *}"; }
tailscale_tip_alignment() {
  ipc smoke itemValues panel vgs.tailscale Tooltip opened,placed,scene | py_reply '
import json, sys
tips = [t for t in json.load(sys.stdin) if t["opened"] and isinstance(t.get("scene"), dict)]
if not tips: print("closed"); sys.exit()
s, p = tips[0]["scene"], tips[0]["placed"]
left, right = p["x"], p["x"] + p["width"]
print("tailscale-reason-edges: left-minus-switch-left=%g right-minus-switch-left=%g" % (left, right), file=sys.stderr)
print("aligned" if right >= 0 else "left")'
}
tailscale_setup_opacity() { ipc smoke readMatchingDescendant panel vgs.tailscale Label objectName tailscale-setup-hint opacity; }
# Each poll sends at most one Tab until the actual switch holds focus.
tailscale_switch_focus() {
  if [[ $(ipc smoke activeFocusItem panel vgs.tailscale) == '["Switch",""]' ]]; then echo focused; return; fi
  type_keys -k Tab || return 1
  echo moving
}
tailscale_setup_field() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; rows=[row for row in json.load(sys.stdin) if row["key"]=="setup"]; print(json.dumps([[row["chips"], [[button["text"], button["enabled"]] for button in row["buttons"]]] for row in rows]))'; }
tailscale_body_state() { tailscale_body "$1" tailscale | py_reply 'import json,sys; print(json.load(sys.stdin)["state"])'; }
tailscale_exit_rows() { tailscale_body window exitRows | py_reply 'import json,sys; print(json.dumps([[r["text"], r["badge"]] for r in json.load(sys.stdin)]))'; }
tailscale_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.tailscale" in ids for ids in json.load(sys.stdin)))'; }
tailscale_interval() { ipc smoke readInstance service vgs.tailscale pollInterval; }
tailscale_polls() { ipc smoke readInstance service vgs.tailscale pollsStarted; }
tailscale_status_calls() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c == ["status", "--json"]))'; }
tailscale_call_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The commands that change Tailscale, from call N of the stand-in's record.
tailscale_changes() { device_calls tailscale | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin)[int(sys.argv[1]):] if c[:1] not in (["status"], ["get"]) and c != ["switch", "--list"]]))' "$1"; }
tailscale_argv_ids() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin)[int(sys.argv[1]):] for word in c if "nFIXTURE" in word))' "$1"; }
# The `status --json` calls the stand-in recorded since BEFORE against the
# polls the service started: `none` while the service is the only caller,
# `extra` for a call it did not start, `short` while a poll it started has
# not reached the stand-in.
tailscale_surplus() { # BEFORE
  local polls calls
  polls="$(tailscale_polls)" || return 1
  calls="$(tailscale_status_calls)" || return 1
  if ((calls - $1 == polls)); then echo none; elif ((calls - $1 > polls)); then echo extra; else echo short; fi
}
tailscale_account_ids() { ipc smoke statusValues vgs.tailscale | py_reply 'import json,sys; print(json.dumps([a["id"] for a in json.load(sys.stdin)["tailscale"]["accounts"]]))'; }
tailscale_opens() { device_calls xdg-open | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[int(sys.argv[1]):]))' "$1"; }
tailscale_record() { ipc shell lent | py_reply 'import json,sys; print("held" if "vgs.tailscale" in json.load(sys.stdin)["status"] else "absent")'; }
tailscale_refresh() { ipc vgs.tailscale invoke refresh ""; }
tailscale_act() { ipc vgs.tailscale invoke action "{\"kind\":\"$1\",\"id\":\"${2:-}\"}"; }
# Sends the action KIND and prints the problem its run left once FIELD
# reads IDLE again, `""` for none: `refused` for an action the service
# does not take, `unended` when the run has not ended after 10 s.
tailscale_problem_after() { # KIND FIELD IDLE
  local now
  [[ $(tailscale_act "$1") == ok ]] || { echo refused; return 0; }
  for _ in $(seq 1 50); do
    now="$(tailscale_value "$2")" || return 1
    if [[ $now == "$3" ]]; then tailscale_value problem; return; fi
    sleep 0.2
  done
  echo unended
}
# Fails one change with a plain exit 1, one change with the CLI's
# access-denied text and one sign-in with that text: `told-apart` when
# each change leaves a problem, the two differ and the sign-in leaves the
# denied change's; `same` when the two changes leave one problem.
tailscale_failures() {
  local plain denied login
  plain="$(tailscale_problem_after exit-node action '""')" || return 1
  : >"$tailscale_dir/denied"
  denied="$(tailscale_problem_after exit-node action '""')" || return 1
  : >"$tailscale_dir/login-denied"
  login="$(tailscale_problem_after login login '"idle"')" || return 1
  if [[ $plain != \"?*\" || $denied != \"?*\" ]]; then echo "unset plain=$plain denied=$denied"
  elif [[ $plain == "$denied" ]]; then echo same
  elif [[ $login != "$denied" ]]; then echo "login=$login denied=$denied"
  else echo told-apart
  fi
}
# `grew` once the service has started two more polls, within 10 s.
tailscale_polls_grow() {
  local first now
  first="$(tailscale_polls)" || return 1
  for _ in $(seq 1 50); do
    now="$(tailscale_polls)" || return 1
    if ((now >= first + 2)); then echo grew; return 0; fi
    sleep 0.2
  done
  echo "polls=$((now - first))"
}
# `still` when the service starts no poll over 4 s.
tailscale_polls_still() {
  local first now
  first="$(tailscale_polls)" || return 1
  sleep 4
  now="$(tailscale_polls)" || return 1
  if ((now == first)); then echo still; else echo "polls=$((now - first))"; fi
}
# Holds the next poll open and asks for a refresh every second until the
# held process is gone: `killed` when that takes 9 s to 20 s, with the
# time in $tailscale_dir/hang.ms, `killed ms=<n>` outside it, `postponed` when
# the process outlives 20 s, `unheld` when no poll took the marker.
tailscale_hang() {
  local pid start elapsed
  rm -f -- "${tailscale_dir:?}/hang.pid" "${tailscale_dir:?}/hang.taken"
  : >"$tailscale_dir/hang"
  [[ $(tailscale_refresh) == ok ]] || { echo refresh-refused; return 0; }
  for _ in $(seq 1 100); do
    if [[ -e $tailscale_dir/hang.pid ]]; then break; fi
    sleep 0.1
  done
  [[ -e $tailscale_dir/hang.pid ]] || { rm -f -- "${tailscale_dir:?}/hang"; echo unheld; return 0; }
  pid="$(<"$tailscale_dir/hang.pid")"
  start="$(now_ms)"
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(($(now_ms) - start))
    if ((elapsed >= 20000)); then echo postponed; return 0; fi
    [[ $(tailscale_refresh) == ok ]] || { echo refresh-refused; return 0; }
    sleep 1
  done
  elapsed=$(($(now_ms) - start))
  printf '%s\n' "$elapsed" >"$tailscale_dir/hang.ms"
  if ((elapsed >= 9000)); then echo killed; else echo "killed ms=$elapsed"; fi
}
tailscale_enter_pane() { # LABEL
  rest_pointer || fail "$1: moving the pointer off System failed"
  type_keys -M logo -k period -m logo
  expect_poll "$1: the System shortcut opens the Tailscale section" shown tailscale_shown window
  expect_poll "$1: System opens in its search field" '["TextField",""]' ipc smoke activeFocusItem window vgs.system
  type_keys Tailscale
  expect_poll "$1: the search names Tailscale" '"Tailscale"' ipc smoke readDescendant window vgs.system Sidebar query
  type_keys -k Return
  expect_poll "$1: Enter moves the keys into the Tailscale section" true ipc smoke activeFocusWithin window vgs.tailscale TailscaleBody
}
tailscale_leave_pane() { # LABEL
  type_keys -k Escape
  type_keys -k Escape
  type_keys -k Escape
  expect_poll "$1: Escape closes System" hidden tailscale_shown window
}

# The world: a running tailnet with Mullvad nodes, two accounts, a running
# daemon and no operator, so the operator step reads needed.
tailscale_use mullvad.json
device_reply tailscale 0 "$(<"$tailscale_fixtures/accounts.txt")" switch --list
device_reply tailscale 0 "" get operator
device_reply tailscale 0 "" down
device_reply tailscale 0 "" up
device_reply tailscale 0 "" set --exit-node=gateway.tail-fixture.ts.net
device_reply tailscale 1 "" set --exit-node=
device_reply systemctl 0 "" is-active --quiet tailscaled.service
device_reply xdg-open 0 "" "$tailscale_login_url"
expect "the core's system steps resolve in the fakes' tree" prefixed devices_system_tree
ln -sfn -- "$shim/tailscale" "$tailscale_system_link"
expect "the shell resolves tailscale to the stand-in" "$shim/tailscale" shell_resolves tailscale
expect "the shell resolves xdg-open to the stand-in" "$shim/xdg-open" shell_resolves xdg-open
expected_errors+=('tailscale: poll killed after 10000 ms' 'tailscale: (exit-node|login) failed kind=(access-denied|other) ')
# Start from real pre-split user documents, with both system steps already
# complete. Read the effective manager rows for both shipped plugins after
# each fresh startup; a disabled service cannot publish setup until enabled.
tailscale_split_layout() {
  ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); ids=("vgs.tailscale","vgs.vpn"); print(json.dumps([[section,r["id"]] for section in ("left","center","right") for r in d["bar"]["layout"].get(section,[]) if r["id"] in ids]))'
}
tailscale_split_runtime() {
  ipc smoke readInstance window vgs.settings plugins | py_reply 'import json,sys; rows=json.load(sys.stdin); print(json.dumps([[r["id"],r["enabled"],r["placed"],r["settings"]["pollSeconds"]] for i in ("vgs.tailscale","vgs.vpn") for r in rows if r["id"]==i]))'
}
device_reply tailscale 0 "$(id -un)" get operator
for tailscale_migration in disabled placed hidden; do
  stop_shell || return 1
  python3 - "$tailscale_saved" "$home/.config/vgshell/shell.json" "$tailscale_migration" <<'PYMIGRATION'
import json, os, sys
source, target, mode = sys.argv[1:]
d = json.load(open(source))
ids = ("vgs.tailscale", "vgs.vpn")
d["disabledPlugins"] = [i for i in d.get("disabledPlugins", []) if i not in ids]
if mode == "disabled": d["disabledPlugins"].append("vgs.vpn")
d["plugins"] = [r for r in d.get("plugins", []) if r["id"] not in ids] + [{"id":"vgs.vpn", "pollSeconds":60}]
for section in ("left", "center", "right"):
    d["bar"]["layout"][section] = [r for r in d["bar"]["layout"].get(section, []) if r["id"] not in ids]
if mode != "hidden": d["bar"]["layout"]["right"].insert(0, {"id":"vgs.vpn"})
json.dump(d, open(target + ".next", "w"))
os.replace(target + ".next", target)
PYMIGRATION
  if start_shell "$repo" "$sandbox/tailscale-migration-$tailscale_migration.log"; then
    expect "Settings opens for the $tailscale_migration migration readback" ok ipc shell summon window vgs.settings '{}'
    case "$tailscale_migration" in
      disabled) tailscale_tuple='[["vgs.tailscale", false, true, 60], ["vgs.vpn", false, true, 60]]' ;;
      placed) tailscale_tuple='[["vgs.tailscale", true, true, 60], ["vgs.vpn", true, true, 60]]' ;;
      hidden) tailscale_tuple='[["vgs.tailscale", true, false, 60], ["vgs.vpn", true, false, 60]]' ;;
    esac
    expect_poll "both plugins inherit the $tailscale_migration user's startup settings" "$tailscale_tuple" tailscale_split_runtime
    tailscale_layout='[["right", "vgs.tailscale"], ["right", "vgs.vpn"]]'
    [[ $tailscale_migration != hidden ]] || tailscale_layout='[]'
    expect "both plugins inherit the saved $tailscale_migration bar section and order" "$tailscale_layout" tailscale_split_layout
    if [[ $tailscale_migration == disabled ]]; then
      expect "the disabled source service stays unbuilt at startup" False record_exists vgs.vpn
      expect "the disabled split service stays unbuilt at startup" False record_exists vgs.tailscale
      expect "the inherited split can enable without repeating setup" ok ipc shell setPluginEnabled vgs.tailscale true
    fi
    expect_poll "the completed daemon step stays ready after $tailscale_migration migration" 'ready active' tailscale_step service-tailscaled
    expect_poll "the completed Allow step stays ready after $tailscale_migration migration" 'ready granted' tailscale_step tailscale-operator
    expect_poll "the completed setup offers neither Enable nor Allow after $tailscale_migration migration" none tailscale_setup
    expect "Settings closes after the migration reading" ok ipc shell hide window vgs.settings
  fi
done
stop_shell || return 1
user_config_restore "$tailscale_saved"
start_shell "$repo" "$sandbox/tailscale-migration-restored.log" || return 1
device_reply tailscale 0 "" get operator

# The default set starts the plugin; the row counts one service's polls
# from its first, so it starts from a disabled plugin.
expect "Tailscale disables before its row" ok ipc shell setPluginEnabled vgs.tailscale false
expect_poll "no Tailscale service is built before the row" False record_exists vgs.tailscale
tailscale_status_before="$(tailscale_status_calls)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
tailscale_calls_before="$(tailscale_call_count tailscale)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
tailscale_opens_before="$(tailscale_call_count xdg-open)" || { fail "tailscale: the xdg-open stand-in's calls are unreadable"; return 0; }

expect "Tailscale enables over the stand-ins" ok ipc shell setPluginEnabled vgs.tailscale true
expect_poll "Tailscale's service is built" True record_exists vgs.tailscale
rescan "a scan probes the system steps over the linked stand-in"
expect_poll "the service publishes the running tailnet" '"running"' tailscale_value state
expect "the service publishes this device" '{"name": "desk", "address": "100.64.0.1"}' tailscale_value device
expect "the service publishes the exit node in use" '{"id": "nFIXTURE0013CNTRL", "name": "Zurich, Switzerland"}' tailscale_value exit
expect_poll "the service publishes both accounts" '["f1a0", "f1a1"]' tailscale_account_ids
expect_poll "Tailscale's widget is placed" True tailscale_placed
expect_poll "the widget draws the exit node from the shared record" '"earth-lock"' ipc smoke readDescendant "$(bar_key)" vgs.tailscale BarItem iconName
expect_poll "the running Tailscale backend shows its widget" true tailscale_widget
tailscale_no_exit="$(python3 -c 'import json,sys
status = json.load(open(sys.argv[1]))
for peer in status["Peer"].values():
    peer["ExitNode"] = False
print(json.dumps(status))' "$tailscale_fixtures/running.json")" || { fail "tailscale: the no-exit fixture is unreadable"; return 0; }
device_reply tailscale 0 "$tailscale_no_exit" status --json
expect "a refresh reads a tailnet without an exit node" ok tailscale_refresh
expect_poll "the tailnet publishes no selected exit node" null tailscale_value exit
expect_poll "the tailnet without an exit node draws route" '"route"' tailscale_icon
tailscale_use mullvad.json
expect "a refresh restores the exit node" ok tailscale_refresh
expect_poll "the exit node draws earth-lock" '"earth-lock"' tailscale_icon
expect "the poll waits the setting's 30 s while no view is open" 30000 tailscale_interval

# Access denied: no operator, so the step reads needed and Allow is offered.
expect_poll "the core reads the operator step needed" "needed operator-unset" tailscale_step tailscale-operator
expect_poll "an unset operator offers Allow" allow tailscale_setup
settings_page_open vgs.tailscale
settings_setup
expect_poll "Setup offers Allow on the Tailscale service step, To do" '[[[["To do", "warning"]], [["Let my login control Tailscale", true]]]]' tailscale_setup_field
settings_page_close vgs.tailscale
expect "changes wait for Allow" false tailscale_value writable
# The flyout's header switch is locked until Allow: it says why on hover.
rest_pointer || fail "tailscale: moving the pointer off the flyout failed"
expect "the flyout opens on a locked switch" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "Tailscale's flyout is shown on a locked switch" shown tailscale_shown panel
expect_poll "the locked switch draws its unlock mark named for Allow" drawn tailscale_mark panel "Let my login control Tailscale"
expect "the locked switch's reason names Allow's step" True tailscale_reason_names panel "Let my login control Tailscale"
tailscale_reason="$(tailscale_body panel lockReason)" || tailscale_reason=unread
expect_poll "the pointer on the locked switch opens its reason" "$tailscale_reason" tailscale_switch_tip
expect "the locked header reason covers no connection text or control" free tailscale_tip_cover panel
expect "control: the reason's place moved onto a text covers it" covers tailscale_tip_cover_word panel obstacle
rest_pointer || fail "tailscale: moving the pointer off the switch failed"
expect_poll "the pointer off the locked switch closes its reason" closed tailscale_tip panel
expect "the flyout closes before System" ok ipc shell hide panel vgs.tailscale
expect_poll "the locked flyout is gone" hidden tailscale_shown panel
expect_poll "the closed locked flyout gives the poll its 30 s back" 30000 tailscale_interval
tailscale_theme="$home/.config/vgshell/theme.json"
tailscale_theme_before="$(ipc smoke themeName)" || return 1
[[ ! -e $tailscale_theme ]] || cp -- "$tailscale_theme" "$tailscale_dir/theme-before.json"
for tailscale_theme_name in vgs flexoki-light; do
  tailscale_theme_source="$repo/themes/vgs/theme.json"
  [[ $tailscale_theme_name != flexoki-light ]] || tailscale_theme_source="$repo/themes/catalog/flexoki-light/theme.json"
  cp -- "$tailscale_theme_source" "$tailscale_theme.next" && mv -- "$tailscale_theme.next" "$tailscale_theme"
  expect_poll "the Tailscale reason theme applies: $tailscale_theme_name" "$tailscale_theme_name" ipc smoke themeName
  expect "the locked flyout opens for $tailscale_theme_name" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
  expect_poll "the pointer opens the reason in $tailscale_theme_name" "$tailscale_reason" tailscale_switch_tip
  expect "the pointer reason covers no connection text or control in $tailscale_theme_name" free tailscale_tip_cover panel
  expect "the pointer reason reaches under the switch in $tailscale_theme_name" aligned tailscale_tip_alignment
  expect "the covered Setup text fades under the pointer in $tailscale_theme_name" 0.5 tailscale_setup_opacity
  rest_pointer || fail "tailscale: moving off the switch failed"
  expect_poll "Tab reaches the header switch in $tailscale_theme_name" focused tailscale_switch_focus
  expect_poll "focus opens the reason in $tailscale_theme_name" "$tailscale_reason" tailscale_tip panel
  expect "the focus reason covers no connection text or control in $tailscale_theme_name" free tailscale_tip_cover panel
  expect "the focus reason reaches under the switch in $tailscale_theme_name" aligned tailscale_tip_alignment
  expect "the covered Setup text fades under focus in $tailscale_theme_name" 0.5 tailscale_setup_opacity
  printf 'tailscale-header-reason: theme=%s pointer=free focus=free\n' "$tailscale_theme_name"
  expect "the themed locked flyout closes" ok ipc shell hide panel vgs.tailscale
done
if [[ -e $tailscale_dir/theme-before.json ]]; then
  cp -- "$tailscale_dir/theme-before.json" "$tailscale_theme.next" && mv -- "$tailscale_theme.next" "$tailscale_theme"
else
  rm -f -- "${tailscale_theme:?}"
fi
expect_poll "the Tailscale row restores its theme" "$tailscale_theme_before" ipc smoke themeName
expect "System enables for the Tailscale section" ok ipc shell setPluginEnabled vgs.system true
expect "the Tailscale section opens in System" ok ipc shell summon window vgs.system '{"pane":"vgs.tailscale","source":"smoke"}'
expect_poll "Tailscale's pane is mounted" shown tailscale_shown window
expect "the pane receives its payload" '{"source":"smoke"}' ipc smoke readInstance window vgs.tailscale payload
expect_poll "the pane reads the shared record" running tailscale_body_state window
expect_poll "the pane draws the core's offered step" '{"label":"Let my login control Tailscale","hint":"The administrator holds Tailscale. After this step, VGS connects and disconnects for you without a password."}' tailscale_body window setupAction
expect_poll "an open pane makes the poll fast" 3000 tailscale_interval
expect "System closes before the keyboard path" ok ipc shell hide window vgs.system
expect_poll "the closed pane is gone" hidden tailscale_shown window
expect_poll "a closed pane gives the poll its 30 s back" 30000 tailscale_interval

hypr_lua_save tailscale
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested keyboard uses symbol bindings" ok hypr reload config-only
terminal_stand_in
terminal_ready "tailscale"
tailscale_enter_pane "Allow"
expect "the section opens on its body while the switch waits for Allow" '["TailscaleBody",null]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -k Tab
expect_poll "Tab reaches Allow" '["RowAction","Let my login control Tailscale"]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -k Tab
expect_poll "Tab reaches the locked connection switch" '["Switch",""]' ipc smoke activeFocusItem window vgs.tailscale
expect_poll "keyboard focus on the locked switch opens its reason" "$tailscale_reason" tailscale_tip window
type_keys -k space
type_keys -k Tab
expect_poll "Tab reaches the switch's unlock mark" '["IconButton","Let my login control Tailscale"]' ipc smoke activeFocusItem window vgs.tailscale
forget_record
type_keys -k Return
expect_poll "the unlock mark hands the terminal vgshell system apply tailscale-operator" \
  "$(core_words core/system "System setup" org.vgs.tui system apply tailscale-operator)" recorded
expect "Space on the locked switch starts no change" '[]' tailscale_changes "$tailscale_calls_before"
device_reply tailscale 0 "$(id -un)" get operator
expect_run_end "the Allow core/system run ends" core/system
forget_record
rescan "a scan probes the operator again"
expect_poll "the core reads the operator step ready" "ready granted" tailscale_step tailscale-operator
expect_poll "a granted operator offers no step" none tailscale_setup
expect_poll "changes are open once the operator is granted" true tailscale_value writable
expect_poll "a granted operator leaves the switch no reason" '""' tailscale_body window lockReason
# The setup run's window took the keys, so System closes by its IPC here.
expect "System closes after Allow" ok ipc shell hide window vgs.system
expect_poll "System is closed after Allow" hidden tailscale_shown window

# Keys alone: the switch runs down and up, the list sets the exit node.
tailscale_enter_pane "keys"
expect_poll "the section opens on its connection switch" '["Switch",""]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -k space
expect_poll "Space on the switch runs down" '[["down"]]' tailscale_changes "$tailscale_calls_before"
tailscale_use stopped.json
expect_poll "the pane reads the stopped tailnet" stopped tailscale_body_state window
expect_poll "the widget draws the stopped tailnet" '"route-off"' ipc smoke readDescendant "$(bar_key)" vgs.tailscale BarItem iconName
expect_poll "the switch keeps the keys" '["Switch",""]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -k space
expect_poll "Space on the switch runs up" '[["down"], ["up"]]' tailscale_changes "$tailscale_calls_before"
tailscale_use mullvad.json
expect_poll "the pane reads the running tailnet again" running tailscale_body_state window
expect_poll "the exit nodes list the tailnet's node, then one Mullvad node a city" \
  '[["None", ""], ["gateway", ""], ["Stockholm, Sweden", ""], ["Zurich, Switzerland", "In use"]]' tailscale_exit_rows
type_keys -k Tab
expect_poll "Tab reaches the exit nodes" true ipc smoke activeFocusWithin window vgs.tailscale DeviceList
type_keys -k Down
type_keys -k Return
expect_poll "Enter on a node sets it by its DNS name" \
  '[["down"], ["up"], ["set", "--exit-node=gateway.tail-fixture.ts.net"]]' tailscale_changes "$tailscale_calls_before"
expect "no peer id reached a tailscale argv" 0 tailscale_argv_ids "$tailscale_calls_before"
expect_poll "the change ends" '""' tailscale_value action
expect "a denied change and a denied sign-in leave another problem than a plain failure" told-apart tailscale_failures
tailscale_leave_pane "keys"
hypr_lua_restore tailscale || fail "hyprland.lua is put back after the Tailscale keyboard path"
expect "the nested instance reloads hyprland.lua as the row found it" ok hypr reload config-only

# The flyout, and the poll interval behind it.
expect_poll "the poll is slow again with System closed" 30000 tailscale_interval
expect "the closed poll starts nothing for 4 s" still tailscale_polls_still
expect "the flyout opens" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "Tailscale's flyout is shown" shown tailscale_shown panel
expect "the flyout receives its payload" '{"source":"smoke"}' ipc smoke readInstance panel vgs.tailscale payload
expect_poll "the flyout reads the shared record" running tailscale_body_state panel
expect_poll "an open flyout makes the poll fast" 3000 tailscale_interval
expect "the open poll starts two polls within 10 s" grew tailscale_polls_grow
expect "the flyout closes" ok ipc shell hide panel vgs.tailscale
expect_poll "the closed flyout is gone" hidden tailscale_shown panel
expect_poll "the closed flyout gives the poll its 30 s back" 30000 tailscale_interval
expect_poll "every status call the stand-in recorded is the service's" none tailscale_surplus "$tailscale_status_before"

# A held poll: killed at the watchdog while a refresh arrives every second.
expect "a held poll is killed by the 10 s watchdog under refreshes" killed tailscale_hang
if [[ -e $tailscale_dir/hang.ms ]]; then printf '        the held poll ended %s ms after its start\n' "$(<"$tailscale_dir/hang.ms")"; fi
expect "the service counts one killed poll" 1 ipc smoke readInstance service vgs.tailscale pollsKilled
expect_poll "the refresh that waited reads the tailnet again" '"running"' tailscale_value state

# Sign-in: the printed address goes to the xdg-open stand-in.
tailscale_use logged-out.json
expect "a refresh reads the signed-out daemon" ok tailscale_refresh
expect_poll "the service publishes signed out" '"signed-out"' tailscale_value state
rm -f -- "${tailscale_dir:?}/login-release"
expect "sign-in starts" ok tailscale_act login
expect_poll "the sign-in address reaches the xdg-open stand-in alone" "[[\"$tailscale_login_url\"]]" tailscale_opens "$tailscale_opens_before"
expect_poll "the sign-in wait spins the bar icon" true ipc smoke readDescendant "$(bar_key)" vgs.tailscale BarItem spinning
expect_poll "the service waits for the browser" '"opened"' tailscale_value login
: >"$tailscale_dir/login-release"
expect_poll "the finished sign-in ends the wait" '"idle"' tailscale_value login
expect "the finished sign-in leaves no problem" '""' tailscale_value problem

# A daemon that is off: the service step reads needed and Enable is offered.
: >"$tailscale_dir/service-off"
device_reply systemctl 3 "" is-active --quiet tailscaled.service
device_reply systemctl 0 loaded show --property=LoadState --value tailscaled.service
rescan "a scan probes the stopped service"
expect_poll "the core reads the service step needed" "needed inactive" tailscale_step service-tailscaled
expect "a refresh reads the stopped daemon" ok tailscale_refresh
expect_poll "the service publishes the daemon off" '"service-off"' tailscale_value state
expect_poll "a stopped daemon offers Enable" enable tailscale_setup
expect_poll "the stopped daemon draws route-off" '"route-off"' tailscale_icon
expect_poll "the stopped daemon uses the warning tone" true tailscale_warning
device_reply systemctl 0 not-found show --property=LoadState --value tailscaled.service
rescan "a scan probes an absent tailscaled service"
expect_poll "the core reports the Tailscale backend absent" 'absent unit-missing' tailscale_step service-tailscaled
expect_poll "the icon hides while the daemon backend is absent" false tailscale_widget
device_reply systemctl 0 loaded show --property=LoadState --value tailscaled.service
rm -f -- "${tailscale_dir:?}/service-off"
device_reply systemctl 0 "" is-active --quiet tailscaled.service
tailscale_use mullvad.json

rescan "the running Tailscale service returns after the absence probe"
expect "a refresh restores the running tailnet" ok tailscale_refresh
expect_poll "the Tailscale icon returns after its backend returns" true tailscale_widget
mv -- "$shim/tailscale" "$tailscale_dir/hidden-command"
rescan "the scan reads tailscale absent without a host fallback"
expect_poll "Tailscale publishes its missing command" '"missing"' tailscale_value state
expect_poll "the Tailscale icon hides while its command is missing" false tailscale_widget
mv -- "$tailscale_dir/hidden-command" "$shim/tailscale"
rescan "the Tailscale stand-in returns"
expect "a refresh reads the restored stand-in" ok tailscale_refresh
expect_poll "Tailscale restores its running tailnet" '"running"' tailscale_value state

# Controls, on a copy: a widget that polls on its own, a refresh that
# restarts the watchdog, and a failure table without the access-denied text.
expect "Tailscale disables before its control copy" ok ipc shell setPluginEnabled vgs.tailscale false
expect_poll "the disabled service's build record is gone" False record_exists vgs.tailscale
expect_poll "the disabled plugin holds no status record" absent tailscale_record
tailscale_copy="$home/.config/vgshell/plugins/vgs.tailscale"
mkdir -p -- "$tailscale_copy"
cp -R -- "$repo/shell/plugins/vgs.tailscale/." "$tailscale_copy/"
python3 - "$tailscale_copy/Widget.qml" "$tailscale_copy/Service.qml" "$tailscale_copy/TailscaleLogic.js" "$tailscale_copy/TailscaleBody.qml" <<'PYCONTROL'
import pathlib, sys
widget, service, logic, body = map(pathlib.Path, sys.argv[1:])
text = widget.read_text()
for old, new in (("import QtQuick\n", "import QtQuick\nimport Quickshell.Io\n"),
                 ("    BarItem {\n", "    Process { command: [\"tailscale\", \"status\", \"--json\"]; running: true }\n\n    BarItem {\n")):
    assert text.count(old) == 1, old
    text = text.replace(old, new)
widget.write_text(text)
text = service.read_text()
old = "        runPoll(\"refresh\");\n        readAccounts();\n"
assert text.count(old) == 1, old
text = text.replace(old, "        if (watchdog.running) watchdog.restart();\n" + old)
service.write_text(text)
text = body.read_text()
for old, new in (
    ('readonly property bool repeatsReason: true', 'readonly property bool repeatsReason: false'),
):
    assert text.count(old) == 1, old
    text = text.replace(old, new)
body.write_text(text)
text = logic.read_text()
old = "pattern: /access denied/i"
assert text.count(old) == 1, old
logic.write_text(text.replace(old, "pattern: /prefs refused/i"))
PYCONTROL
rescan "the control copy is discovered"
tailscale_control_before="$(tailscale_status_calls)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
expect "the control copy enables" ok ipc shell setPluginEnabled vgs.tailscale true
expect_poll "the control's service is built" True record_exists vgs.tailscale
expect_poll "the control's service reads the tailnet" '"running"' tailscale_value state
expect_poll "control: a widget that polls on its own is a call the service did not start" extra tailscale_surplus "$tailscale_control_before"
expect "control: a service that does not know the access-denied text leaves the plain failure's problem" same tailscale_failures
expect "control: a refresh that restarts the watchdog holds the poll past 20 s" postponed tailscale_hang
device_reply tailscale 0 "" get operator
expect "the unmarked Setup control resets its earlier errors" ok ipc shell setPluginEnabled vgs.tailscale false
rescan "the unmarked Setup control needs Allow again"
expect "the unmarked Setup control starts with clean status" ok ipc shell setPluginEnabled vgs.tailscale true
expect_poll "the unmarked Setup control offers Allow" allow tailscale_setup
expect_poll "the unmarked Setup control has no other problem text" '""' tailscale_value problem
expect "the unmarked Setup control opens its flyout" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the unmarked Setup control opens the switch reason" "$tailscale_reason" tailscale_switch_tip
expect "control: unmarked Setup makes the reason cover connection text" covers tailscale_tip_cover_word panel
expect "the unmarked Setup control closes" ok ipc shell hide panel vgs.tailscale
expect "the control copy disables" ok ipc shell setPluginEnabled vgs.tailscale false
expect_poll "the control's service is gone" False record_exists vgs.tailscale
rm -rf -- "${tailscale_copy:?}"
rescan "the shipped plugin is restored"
user_config_restore "$tailscale_saved"
expect "the row restores the configuration" ok ipc shell reloadConfig
rm -f -- "$tailscale_system_link"
device_reply_clear tailscale
device_reply_clear systemctl
device_reply_clear xdg-open
sentinel_restore "$shim/tailscale"
