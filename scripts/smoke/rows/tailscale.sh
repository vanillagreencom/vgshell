# The Tailscale section, vgs.tailscale, over the device fakes' stand-ins
# (docs/architecture/validation.md § Host safety). No call reaches the
# host's tailscale, tailscaled, browser or sudo: `tailscale` and `xdg-open`
# are the recorded stand-ins in the shell's PATH directory, which answer
# `status --json` from the shapes in scripts/fixtures/tailscale/, and the core's
# step probe reads the same `tailscale` through a link the row adds to the
# fakes' system tree and removes. The row stands over the tailscale
# stand-in with a wrapper that records each call through it and then, on
# the row's markers alone, holds one poll or one suggestion read open,
# answers as a daemon that is off or as one `tailscale logout` signed out,
# refuses one `set` or one sign-in with the CLI's access-denied text, or
# prints a sign-in address and waits.
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
# setting's 30 s while none is; the pane opens its account and network
# devices rows, and while this device waits for approval keeps the account
# and this device; every `status --json` call the stand-in
# records is one the service started; a held poll is killed 10 s after its
# start while a refresh arrives every second; sign-in hands the printed
# address to the xdg-open stand-in; a daemon that is off offers Enable.
#
# The flyout, over the design's stand-in tailnet (fixtures sheet.json,
# accounts.json, suggest.txt; design VGS-1923 § 4 and its VGS-1937
# revision), by keys alone: the main view's title, switch, state line,
# account, this device, network devices, exit node and footer, and no
# Check every in any view; the account row's list, then Add account and
# Sign out on Tab; Sign out's confirmation on Cancel, where Cancel sends
# nothing and Sign out hands `tailscale logout` to the stand-in and the
# flyout then reads signed out with Sign in offered; Copy on this device
# reads Copied while CopyText confirms and leaves the IPv4 address on the
# sandbox clipboard; Open admin console hands the admin address to the
# xdg-open stand-in, and with xdg-open missing raises its requirement
# notice; the Exit nodes view with Recommended, None, your exit nodes and
# Mullvad by country, a search, no match, a country's view, Back and
# Escape back to the Exit node row, a search past 20 matches drawing 20
# rows and its count (fixture sheet-cities.json), an offline node of your
# own refused with no `set`, and Tailscale stopping ending the choice;
# the other states' rows: checking, off, starting, waiting for approval,
# service off and not answering. No view opens on
# Sign out. `exit-node suggest` runs when the chooser opens and when the
# state turns running, a second ask while one runs answers busy, and a
# held one is killed 10 s after its start while an ask arrives every
# second. The poll runs every 3 s while Tailscale is starting, with no view
# open, and at the setting's 30 s once it runs.
# The System Settings section reads Connection, Account, This device,
# Exit node, Network devices, Admin console and Updates in that order.
# Keys reach its accounts, Add account, Sign out and confirmation, both
# self Copy actions, every country Disclosure and its cities, every peer
# and its Copy DNS name menu, the admin console and Check every. Each
# address and DNS copy reads the nested clipboard. Missing Tailscale
# offers its requirement and hides Updates; signed out and service off
# keep Updates. The control copy writes a wrong clipboard value while
# keeping Copied, which the same clipboard judge rejects.
# Controls, a copy of the plugin whose widget polls on its own, whose
# refresh restarts the watchdog, whose busy suggestion ask restarts the
# suggestion's deadline, retains a killed suggestion and does not know the access-denied text:
# the stand-in records a call the service did not start, the held poll
# and the held suggestion read outlive 20 s of asks, and the denied change
# leaves the plain one's problem. The reason's place moved onto a text
# reads covered. The pointer off the locked switch reads its reason
# closed, and the lock's Space reads no change, so neither reader always
# passes.
#
# The held poll's and the held suggestion's wait is the service's own 10 s
# deadline, read on the wall clock with a refresh or an ask every second;
# the row accepts 9 s to 20 s, since a request that moved the deadline
# would hold it past any bound. Every other reading is expect_poll's, 0.2 s
# apart.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.tailscale/* shell/plugins/vgs.system/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/SettingField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml scripts/fixtures/tailscale/* scripts/smoke/fixtures/devices/* shell/Commons/SettingValues.js shell/Commons/qmldir shell/Ui/layout/DeviceList.qml shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/plugins/vgs.vpn/manifest.json shell/Core/Config.qml shell/Core/Registry.qml shell/Core/ConfigLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system bin/vgshell-tui scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh shell/Ui/controls/RowAction.qml shell/Ui/controls/Switch.qml shell/Ui/controls/DisabledReason.qml shell/Ui/controls/UnlockMark.qml shell/Ui/layout/Pane.qml shell/Ui/layout/ScrollArea.qml shell/Ui/overlay/Tooltip.qml shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Ui/foundation/KeyNavLogic.js shell/Ui/feedback/CopyText.qml shell/Ui/feedback/Dialog.qml shell/Ui/feedback/EmptyState.qml shell/Ui/foundation/Scrim.qml shell/Ui/layout/Disclosure.qml shell/Ui/layout/ListItem.qml shell/Ui/layout/DeviceRow.qml shell/Ui/layout/Section.qml shell/Ui/controls/RowActions.qml shell/Ui/controls/TextField.qml shell/Hosts/NoticeHost.qml themes/vgs/theme.json themes/catalog/flexoki-light/theme.json shell/Ui/controls/Field.qml shell/Ui/controls/SegmentedControl.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Ui/controls/FormRow.qml shell/Ui/feedback/AvatarGroup.qml shell/Ui/feedback/AvatarFace.qml
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
cp -- "$tailscale_fixtures/logged-out.json" "$tailscale_dir/signed-out.status"
cp -- "$tailscale_fixtures/accounts-signed-out.json" "$tailscale_dir/signed-out.accounts"
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
  if [[ -e $dir/signed-out ]]; then
    "$saved" "$@" >/dev/null 2>&1 || true
    cat -- "$dir/signed-out.status"
    exit 0
  fi
elif [[ "$*" == "switch --list --json" && -e $dir/signed-out ]]; then
  "$saved" "$@" >/dev/null 2>&1 || true
  cat -- "$dir/signed-out.accounts"
  exit 0
elif [[ "$*" == "exit-node suggest" ]] && mv -- "$dir/suggest-hang" "$dir/suggest-hang.taken" 2>/dev/null; then
  "$saved" "$@" >/dev/null 2>&1 || true
  echo $$ >"$dir/suggest-hang.pid.next" && mv -f -- "$dir/suggest-hang.pid.next" "$dir/suggest-hang.pid"
  exec sleep 60
elif [[ "$*" == "exit-node suggest" && -e $dir/suggest-barrier ]]; then
  echo $$ >"$dir/suggest-replacement.pid.next" && mv -f -- "$dir/suggest-replacement.pid.next" "$dir/suggest-replacement.pid"
  while [[ -e $dir/suggest-barrier ]]; do sleep 0.1; done
elif [[ "$*" == "logout" ]]; then
  # tailscaled removes the signed-out account and lands on a new empty
  # profile that needs a login (LocalBackend.Logout, ipn/ipnlocal/local.go
  # at tailscale v1.104.1, the packaged CLI).
  "$saved" "$@" || exit
  : >"$dir/signed-out"
  exit 0
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
tailscale_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.tailscale" in ids for ids in json.load(sys.stdin)))'; }
tailscale_interval() { ipc smoke readInstance service vgs.tailscale pollInterval; }
tailscale_polls() { ipc smoke readInstance service vgs.tailscale pollsStarted; }
tailscale_status_calls() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c == ["status", "--json"]))'; }
tailscale_call_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The commands that change Tailscale, from call N of the stand-in's record.
tailscale_changes() { device_calls tailscale | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin)[int(sys.argv[1]):] if c[:1] not in (["status"], ["get"]) and c not in (["switch", "--list", "--json"], ["exit-node", "suggest"])]))' "$1"; }
# The `exit-node suggest` calls the stand-in recorded from call N.
tailscale_suggest_calls() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin)[int(sys.argv[1]):] if c == ["exit-node", "suggest"]))' "$1"; }
tailscale_suggests() { ipc smoke readInstance service vgs.tailscale suggestsStarted; }
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
# tailscale_drawn HOST TYPE NAME: the texts the TYPE whose objectName is
# NAME draws under HOST's Tailscale instance, in tree order, as one JSON
# list; `hidden` while it is not shown, `absent` with no such item. TYPE is
# the probe's type name, such as DeviceList or Disclosure.
tailscale_drawn() { # HOST TYPE NAME
  local values texts
  values="$(ipc smoke itemValues "$1" vgs.tailscale "$2" objectName,visible)" || return 1
  texts="$(ipc smoke itemTexts "$1" vgs.tailscale "$2")" || return 1
  python3 -c 'import json,sys
values, texts = sys.argv[1], sys.argv[2]
if values == "absent" or texts == "absent": print("absent"); sys.exit()
named = [(value, drawn) for value, drawn in zip(json.loads(values), json.loads(texts)) if value["objectName"] == sys.argv[3]]
shown = [drawn for value, drawn in named if value["visible"]]
print(json.dumps(shown[0]) if shown else "hidden" if named else "absent")' "$values" "$texts" "$3"
}
# tailscale_shown_of HOST TYPE NAME: `shown` or `hidden` for that item.
tailscale_shown_of() {
  local drawn
  drawn="$(tailscale_drawn "$@")" || return 1
  case "$drawn" in hidden|absent) echo "$drawn" ;; *) echo shown ;; esac
}
tailscale_label() { tailscale_drawn panel Label "$1"; }
tailscale_title() { ipc smoke paneHeader panel vgs.tailscale | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["title"]))'; }
# tailscale_rows_of TYPE:NAME...: `shown` or `hidden` for each, as one list.
tailscale_rows_of() {
  local row out=()
  for row; do out+=("$(tailscale_shown_of panel "${row%%:*}" "${row#*:}")") || return 1; done
  words "${out[@]}"
}
tailscale_country_count() { ipc smoke statusValues vgs.tailscale | py_reply 'import json,sys; print(len(json.load(sys.stdin)["exitNodes"]["countries"]))'; }
tailscale_own_online() { ipc smoke statusValues vgs.tailscale | py_reply 'import json,sys; print(json.dumps([[n["name"], n["online"]] for n in json.load(sys.stdin)["exitNodes"]["own"]]))'; }
# [the published suggestion, the service's suggestFault].
tailscale_suggest_reading() {
  local value fault
  value="$(tailscale_value suggestion)" || return 1
  fault="$(ipc smoke readInstance service vgs.tailscale suggestFault)" || return 1
  printf '[%s, %s]\n' "$value" "$fault"
}
tailscale_sign_out_look() { ipc smoke itemValues panel vgs.tailscale RowAction objectName,tone,markName | py_reply 'import json,sys; print(json.dumps([[r["tone"], r["markName"]] for r in json.load(sys.stdin) if r["objectName"] == "tailscale-sign-out"]))'; }
tailscale_held() { [[ -e $tailscale_dir/hang.pid ]] && echo held || echo waiting; }
tailscale_view() { ipc smoke readInstance panel vgs.tailscale view; }
tailscale_focus() { ipc smoke activeFocusItem "${1:-panel}" vgs.tailscale; }
# The flyout's header switch as [shown, checked, enabled]; [false] while
# the Pane holds none or hides it.
tailscale_header_switch() {
  ipc smoke itemValues panel vgs.tailscale Switch visible,checked,enabled,Accessible.name | py_reply 'import json,sys
shown = [s for s in json.load(sys.stdin) if s["Accessible.name"] == "Tailscale" and s["visible"]]
print(json.dumps([True, shown[0]["checked"], shown[0]["enabled"]] if shown else [False]))'
}
# How many shown texts in the flyout's Pane read "Check every".
tailscale_check_every() { ipc smoke itemTextCount "${1:-panel}" vgs.tailscale Pane "Check every"; }
# tailscale_tab LABEL WANT [HOST]: one Tab, then the keys on WANT, as
# activeFocusItem reads it.
tailscale_tab() { # LABEL WANT [HOST]
  type_keys -k Tab || { fail "$1: Tab failed"; return 0; }
  expect_poll "$1" "$2" tailscale_focus "${3:-panel}"
}
# tailscale_tab_to WANT [HOST]: each poll sends at most one Tab until the
# keys are on WANT.
tailscale_tab_to() { # WANT [HOST]
  if [[ $(tailscale_focus "${2:-panel}") == "$1" ]]; then echo reached; return; fi
  type_keys -k Tab || return 1
  echo moving
}
# tailscale_tab_focus HOST [LIST]: the keys' [type, text] in HOST; with
# LIST, followed by ` outside LIST` while the DeviceList of that objectName
# does not hold them, since two lists can draw a row of one name.
tailscale_tab_focus() { # HOST [LIST]
  local at held
  at="$(tailscale_focus "$1")" || return 1
  if [[ -n ${2:-} ]]; then
    held="$(ipc smoke readMatchingDescendant "$1" vgs.tailscale DeviceList objectName "$2" activeFocus)" || return 1
    [[ $held == true ]] || at="$at outside $2"
  fi
  printf '%s\n' "$at"
}
# tailscale_tab_until WANT [HOST [LIST]]: Tab, up to 20 presses, each
# waiting up to 1 s for the keys to move, until they are on WANT, inside
# LIST when given (tailscale_tab_focus): `reached`, else where they
# stopped.
tailscale_tab_until() { # WANT [HOST [LIST]]
  local at before
  at="$(tailscale_tab_focus "${2:-panel}" "${3:-}")" || return 1
  for _ in $(seq 1 20); do
    if [[ $at == "$1" ]]; then echo reached; return; fi
    before="$at"
    type_keys -k Tab || return 1
    for _ in $(seq 1 10); do
      at="$(tailscale_tab_focus "${2:-panel}" "${3:-}")" || return 1
      [[ $at == "$before" ]] || break
      sleep 0.1
    done
  done
  if [[ $at == "$1" ]]; then echo reached; else echo "at $at"; fi
}
tailscale_key() { type_keys -k "$1" || fail "tailscale: the key $1 failed"; }
# [CopyText's confirming, this device's drawn texts], read together: the
# confirmation lasts Theme.codeLine.confirm, 1.5 s.
tailscale_copy_reading() {
  local confirming drawn
  confirming="$(ipc smoke readDescendant panel vgs.tailscale CopyText confirming)" || return 1
  drawn="$(tailscale_drawn panel DeviceRow tailscale-this-device)" || return 1
  printf '[%s, %s]\n' "$confirming" "$drawn"
}
# The nested clipboard's text, read after the input check.
tailscale_clipboard() { nested_input_check wl-paste || return 1; "${shell_env[@]}" wl-paste --no-newline; }
tailscale_clipboard_matches() {
  local copied
  copied="$(tailscale_clipboard)" || return 1
  if [[ $copied == "$1" ]]; then echo match; else echo mismatch; fi
}
tailscale_pane_sections() { ipc smoke itemValues window vgs.tailscale Section objectName,title,visible | py_reply 'import json,sys; print(json.dumps([r["title"] for r in json.load(sys.stdin) if r["visible"] and r["objectName"].endswith("-section")]))'; }
tailscale_focus_type() { tailscale_focus "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
tailscale_pane_copy() { # NAME
  ipc smoke readMatchingDescendant window vgs.tailscale RowAction objectName "$1" text
}
tailscale_pane_menu() { ipc smoke menus window vgs.tailscale | py_reply 'import json,sys; print(json.dumps([[m["entries"], m["current"]] for m in json.load(sys.stdin) if m["opened"]]))'; }
# One named control at a time, since both this device's actions read Copy.
tailscale_pane_named_tab() { # TYPE NAME
  local held
  held="$(ipc smoke readMatchingDescendant window vgs.tailscale "$1" objectName "$2" activeFocus)" || return 1
  if [[ $held == true ]]; then echo reached; return; fi
  type_keys -k Tab || return 1
  echo moving
}
tailscale_offered() { notice_shown | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(None if v is None else v[:2]))'; }
# tailscale_status_as FIXTURE STATE: FIXTURE's tailnet with BackendState
# STATE as the stand-in's status answer, and the poll asked for it;
# tailscale_sheet_as STATE does it for the design's tailnet.
tailscale_status_as() { # FIXTURE STATE
  local doc
  doc="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["BackendState"]=sys.argv[2]; print(json.dumps(d))' "$tailscale_fixtures/$1" "$2")" || return 1
  device_reply tailscale 0 "$doc" status --json
  tailscale_refresh
}
tailscale_sheet_as() { tailscale_status_as sheet.json "$1"; }
# [the rows the flyout's search list draws, the chooser's last drawn text].
tailscale_search_reading() {
  local count drawn
  count="$(ipc smoke readMatchingDescendant panel vgs.tailscale DeviceList objectName tailscale-exit-search count)" || return 1
  drawn="$(tailscale_drawn panel ExitNodes tailscale-exit-nodes)" || return 1
  python3 -c 'import json,sys; d=sys.argv[2]; print(json.dumps([json.loads(sys.argv[1]), json.loads(d)[-1] if d.startswith("[") and json.loads(d) else d]))' "$count" "$drawn"
}
# Holds the next suggestion read open and asks for another every second
# until the held process is gone: `killed` when that takes 9 s to 20 s,
# with the time in $tailscale_dir/suggest-hang.ms, `killed ms=<n>` outside
# it, `postponed` when the process outlives 20 s, `unheld` when no read
# took the marker, `not-busy` when an ask during the read answered other
# than busy, `restarted` when the service started a second read meanwhile.
tailscale_suggest_hang() {
  local pid start elapsed started reply extra=0
  rm -f -- "${tailscale_dir:?}/suggest-hang.pid" "${tailscale_dir:?}/suggest-hang.taken"
  rm -f -- "${tailscale_dir:?}/suggest-replacement.pid"
  printf '0\n' >"$tailscale_dir/suggest-hang.extra"
  : >"$tailscale_dir/suggest-barrier"
  : >"$tailscale_dir/suggest-hang"
  started="$(tailscale_suggests)" || return 1
  reply="$(ipc vgs.tailscale invoke suggest "")" || return 1
  [[ $reply == ok ]] || { rm -f -- "${tailscale_dir:?}/suggest-hang"; echo "suggest=$reply"; return 0; }
  for _ in $(seq 1 100); do
    if [[ -e $tailscale_dir/suggest-hang.pid ]]; then break; fi
    sleep 0.1
  done
  [[ -e $tailscale_dir/suggest-hang.pid ]] || { rm -f -- "${tailscale_dir:?}/suggest-hang"; echo unheld; return 0; }
  pid="$(<"$tailscale_dir/suggest-hang.pid")"
  start="$(now_ms)"
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(($(now_ms) - start))
    if ((elapsed >= 20000)); then echo postponed; return 0; fi
    reply="$(ipc vgs.tailscale invoke suggest "")" || return 1
    # An ask that lands after the kill starts the next read, which is no
    # second read in flight.
    if [[ $reply == ok ]] && ! kill -0 "$pid" 2>/dev/null; then extra=1; printf '1\n' >"$tailscale_dir/suggest-hang.extra"; break; fi
    [[ $reply == busy ]] || { echo "not-busy reply=$reply"; return 0; }
    sleep 1
  done
  elapsed=$(($(now_ms) - start))
  printf '%s\n' "$elapsed" >"$tailscale_dir/suggest-hang.ms"
  (($(tailscale_suggests) == started + 1 + extra)) || { echo restarted; return 0; }
  if ((elapsed >= 9000)); then echo killed; else echo "killed ms=$elapsed"; fi
}
# `held` while the suggestion read tailscale_suggest_hang held runs, else
# `gone`.
tailscale_suggest_held() { kill -0 "$(<"$tailscale_dir/suggest-hang.pid")" 2>/dev/null && echo held || echo gone; }
# The replacement cannot supply the null: it must still hold its fixture
# reply after the status read, before its own deadline can clear anything.
tailscale_killed_suggestion() {
  local value
  value="$(tailscale_value suggestion)" || return 1
  if [[ ! -e $tailscale_dir/suggest-replacement.pid ]]; then echo replacement-pending
  elif kill -0 "$(<"$tailscale_dir/suggest-replacement.pid")" 2>/dev/null; then printf '%s\n' "$value"
  else echo replacement-ended; fi
}
tailscale_suggest_clear() {
  local status=0
  if [[ $(<"$tailscale_dir/suggest-hang.extra") == 0 ]]; then
    expect "an ask after the kill starts the held replacement" ok ipc vgs.tailscale invoke suggest ""
  fi
  expect_poll "a suggestion read the deadline killed names none" null tailscale_killed_suggestion || status=$?
  # expect_poll records an assertion failure without returning nonzero.
  # Release on either result so no replacement remains held after it.
  rm -f -- "${tailscale_dir:?}/suggest-barrier" || return 1
  ((status == 0)) || return "$status"
  expect_poll "the released replacement finishes without a fault" '""' ipc smoke readInstance service vgs.tailscale suggestFault
}
tailscale_leave_pane() { # LABEL
  type_keys -k Escape
  type_keys -k Escape
  type_keys -k Escape
  expect_poll "$1: Escape closes System" hidden tailscale_shown window
}

# The world: a running tailnet with Mullvad nodes, two accounts, no
# suggested exit node, a running daemon and no operator, so the operator
# step reads needed.
tailscale_use mullvad.json
device_reply tailscale 0 "$(<"$tailscale_fixtures/accounts.json")" switch --list --json
device_reply tailscale 0 "$(<"$tailscale_fixtures/suggest-none.txt")" exit-node suggest
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
expected_errors+=('tailscale: poll killed after 10000 ms' 'tailscale: (exit-node|login) failed kind=(access-denied|other) ' 'tailscale: refused: exit-node=offline')
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

# The first poll is held, so the flyout opens before any answer: Checking.
rm -f -- "${tailscale_dir:?}/hang.pid" "${tailscale_dir:?}/hang.taken"
: >"$tailscale_dir/hang"
expect "Tailscale enables over the stand-ins" ok ipc shell setPluginEnabled vgs.tailscale true
expect_poll "Tailscale's service is built" True record_exists vgs.tailscale
rest_pointer || fail "tailscale: moving the pointer off the flyout failed"
expect "the flyout opens before Tailscale answers" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the first poll is held" held tailscale_held
expect_poll "the checking flyout's state line reads Checking Tailscale" '["Checking Tailscale"]' tailscale_label tailscale-state
expect "the checking flyout draws no header switch" '[false]' tailscale_header_switch
for tailscale_row in Disclosure:tailscale-account DeviceRow:tailscale-this-device Disclosure:tailscale-network-devices ListItem:tailscale-exit-row; do
  expect "the checking flyout draws no ${tailscale_row#*:}" hidden tailscale_shown_of panel "${tailscale_row%%:*}" "${tailscale_row#*:}"
done
expect "the checking flyout closes" ok ipc shell hide panel vgs.tailscale
rescan "a scan probes the system steps over the linked stand-in"
expect_poll "the service publishes the running tailnet" '"running"' tailscale_value state
expect "the service publishes this device" '{"name": "desk", "address": "100.64.0.1", "dnsName": "desk.tail-fixture.ts.net"}' tailscale_value device
expect "the service publishes the exit node in use" '{"id": "nFIXTURE0013CNTRL", "name": "Zurich, Switzerland"}' tailscale_value exit
expect_poll "the service publishes both accounts" '["a1b2", "c3d4"]' tailscale_account_ids
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
expect "the locked flyout keeps the state line" '["Connected through Zurich, Switzerland"]' tailscale_label tailscale-state
expect "the locked flyout offers Allow as its step" '["Let my login control Tailscale"]' tailscale_drawn panel RowAction tailscale-setup
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
expect "the pane shows the account list" shown tailscale_shown_of window DeviceList tailscale-accounts
expect "the pane shows the network devices list" shown tailscale_shown_of window DeviceList tailscale-devices
# While this device waits for approval the pane keeps the account, where
# the CLI still switches and signs out, and this device.
expect "a refresh reads this device waiting for approval" ok tailscale_status_as mullvad.json NeedsMachineAuth
expect_poll "the pane reads waiting for approval" needs-approval tailscale_body_state window
expect "the approval pane keeps the account list" shown tailscale_shown_of window DeviceList tailscale-accounts
expect "the approval pane keeps this device" shown tailscale_shown_of window Section tailscale-device-section
expect "the approval pane draws no network devices" hidden tailscale_shown_of window Section tailscale-network-section
tailscale_use mullvad.json
expect "a refresh reads the running tailnet for the pane" ok tailscale_refresh
expect_poll "the pane reads the running tailnet after approval" running tailscale_body_state window
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
expect_poll "Tab reaches the locked connection switch" '["Switch",""]' ipc smoke activeFocusItem window vgs.tailscale
expect_poll "keyboard focus on the locked switch opens its reason" "$tailscale_reason" tailscale_tip window
type_keys -k space
type_keys -k Tab
expect_poll "Tab reaches the switch's unlock mark" '["IconButton","Let my login control Tailscale"]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -k Tab
expect_poll "Tab reaches Allow after the connection switch" '["RowAction","Let my login control Tailscale"]' ipc smoke activeFocusItem window vgs.tailscale
type_keys -M shift -k Tab -m shift || fail "tailscale: Shift+Tab to the unlock mark failed"
expect_poll "Shift+Tab returns to the switch's unlock mark" '["IconButton","Let my login control Tailscale"]' ipc smoke activeFocusItem window vgs.tailscale
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
expect_poll "the pane's chooser lists None, the tailnet's node, then Mullvad by country" \
  "$(words None "Use this computer's own connection" "Your exit nodes" gateway Online Mullvad Sweden Stockholm Switzerland Zurich "In use")" tailscale_drawn window ExitNodes tailscale-exit-nodes
expect "the pane draws Check every once" 1 tailscale_check_every window
# The pane opens its account and network devices rows, so the walk
# crosses their lists, Add account, Sign out and each Copy. The network
# devices list draws a gateway row too, so the walk names the chooser's
# list.
expect "the keyboard's pane opens its account list" shown tailscale_shown_of window DeviceList tailscale-accounts
expect "the keyboard's pane opens its network list" shown tailscale_shown_of window DeviceList tailscale-devices
expect "Tab reaches the tailnet's exit node in the pane's chooser" reached tailscale_tab_until '["DeviceRow","gateway"]' window tailscale-exit-own
type_keys -k Return
expect_poll "Enter on a node sets it by its DNS name" \
  '[["down"], ["up"], ["set", "--exit-node=gateway.tail-fixture.ts.net"]]' tailscale_changes "$tailscale_calls_before"
expect "no peer id reached a tailscale argv" 0 tailscale_argv_ids "$tailscale_calls_before"
expect_poll "the change ends" '""' tailscale_value action
expect "a denied change and a denied sign-in leave another problem than a plain failure" told-apart tailscale_failures
tailscale_leave_pane "keys"

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
expect "the service counts the held first poll and this one killed" 2 ipc smoke readInstance service vgs.tailscale pollsKilled
expect_poll "the refresh that waited reads the tailnet again" '"running"' tailscale_value state

# Starting: with no view open the poll runs every 3 s, and at the setting's
# 30 s once Tailscale runs; the turn to running reads the suggestion once.
device_reply tailscale 0 "$(<"$tailscale_fixtures/accounts.json")" switch --list --json
device_reply tailscale 0 "$(<"$tailscale_fixtures/suggest.txt")" exit-node suggest
device_reply xdg-open 0 "" https://login.tailscale.com/admin
device_reply tailscale 0 "" set --exit-node=attic-nas.tail-fixture.ts.net
device_reply tailscale 0 "" logout
expect_poll "no view holds a lease before the starting reading" 30000 tailscale_interval
read_count tailscale_suggests_before "tailscale: suggestion reads before running" tailscale_suggests
tailscale_calls_mark="$(tailscale_call_count tailscale)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
expect "a refresh reads Tailscale starting" ok tailscale_sheet_as Starting
expect_poll "the service publishes starting" '"starting"' tailscale_value state
expect_poll "a starting state polls every 3 s with no view open" 3000 tailscale_interval
expect "the starting poll starts two polls within 10 s" grew tailscale_polls_grow
expect "no suggestion is read while Tailscale is starting" 0 tailscale_suggest_calls "$tailscale_calls_mark"
tailscale_use sheet.json
expect_poll "the poll reads the design's tailnet running" '"running"' tailscale_value state
expect_poll "the poll returns to the setting's 30 s once Tailscale runs" 30000 tailscale_interval
expect_poll "the turn to running reads the suggestion once" 1 tailscale_suggest_calls "$tailscale_calls_mark"
expect "the service started one suggestion read" "$((tailscale_suggests_before + 1))" tailscale_suggests
expect_poll "the service publishes the suggested exit node" '{"id": "nSHEET0024CNTRL", "name": "Stockholm, Sweden"}' tailscale_value suggestion
expect "the running poll starts nothing for 4 s" still tailscale_polls_still
# One suggestion read at a time, killed at its deadline while asks arrive.
expect "a held suggestion read answers busy to every ask and is killed by the 10 s deadline" killed tailscale_suggest_hang
if [[ -e $tailscale_dir/suggest-hang.ms ]]; then printf '        the held suggestion read ended %s ms after its start\n' "$(<"$tailscale_dir/suggest-hang.ms")"; fi
tailscale_suggest_clear
device_reply tailscale 0 "$(<"$tailscale_fixtures/suggest-none.txt")" exit-node suggest
expect "an ask reads the suggestion again" ok ipc vgs.tailscale invoke suggest ""
expect_poll "no suggestion is read as none, not as a fault" '[null, ""]' tailscale_suggest_reading
device_reply tailscale 0 "$(<"$tailscale_fixtures/suggest.txt")" exit-node suggest
expect "an ask reads the suggestion back" ok ipc vgs.tailscale invoke suggest ""
expect_poll "the suggestion returns" '[{"id": "nSHEET0024CNTRL", "name": "Stockholm, Sweden"}, ""]' tailscale_suggest_reading

# The denied sign-in above left its problem, which the views draw until
# the next change starts; one change that ends clears it. The control
# copy at the end reads `set --exit-node=` failing again.
device_reply tailscale 0 "" set --exit-node=
expect "a change that ends clears the denied sign-in's problem" '""' tailscale_problem_after exit-node action '""'
device_reply tailscale 1 "" set --exit-node=

# System Settings, over the same design tailnet as the flyout below.
tailscale_enter_pane "design pane"
expect_poll "the pane opens on Connection's switch" '["Switch",""]' tailscale_focus window
expect "the Connection field draws its switch" shown tailscale_shown_of window Field tailscale-connection-section
expect "the pane's named sections end in Updates" \
  '["Account", "This device", "Exit node", "Network devices", "Admin console", "Updates"]' tailscale_pane_sections
expect "the Account section lists both accounts and its actions" \
  "$(words Account AE amelie@example.com example.com amelie@example.com example.com "In use" amelie@example.org example.org "Add account" "Sign out")" tailscale_drawn window Section tailscale-account-section
expect "This device shows its name, address, DNS name and network" \
  "$(words "This device" Name desk "Tailscale address" 100.64.0.1 Copy "DNS name" desk.tail-fixture.ts.net Copy Network example.com)" tailscale_drawn window Section tailscale-device-section
expect "Updates contains the poll setting and its hint" \
  "$(words Updates "Check every" "10 s" "30 s" "60 s" "How often VGS reads Tailscale while its flyout and this section are closed")" tailscale_drawn window Section tailscale-updates-section
expect "the complete network list draws all five peers" \
  "$(words attic-nas 100.64.0.3 Copy gateway 100.64.0.2 Copy pixel 100.64.0.4 Copy ipad "100.64.0.7 · Offline" Copy old-laptop "100.64.0.9 · Offline" Copy)" tailscale_drawn window DeviceList tailscale-devices
expect "the account list takes Tab" reached tailscale_tab_until '["DeviceRow","amelie@example.com"]' window tailscale-accounts
tailscale_key Down
expect_poll "Down reaches the other account" '["DeviceRow","amelie@example.org"]' tailscale_focus window
tailscale_key Up
expect_poll "Up returns to the account in use" '["DeviceRow","amelie@example.com"]' tailscale_focus window
tailscale_tab "Tab reaches the pane's Add account" '["RowAction","Add account"]' window
tailscale_tab "Tab reaches the pane's Sign out" '["RowAction","Sign out"]' window
tailscale_calls_mark="$(tailscale_call_count tailscale)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
tailscale_key Return
expect_poll "the pane's sign-out confirmation opens on Cancel" '["Button","Cancel"]' tailscale_focus window
tailscale_tab "the confirmation's Sign out is reachable" '["Button","Sign out"]' window
type_keys -M shift -k Tab -m shift || fail "tailscale: the confirmation's Shift+Tab failed"
tailscale_key Return
expect_poll "Cancel returns the pane's keys to Sign out" '["RowAction","Sign out"]' tailscale_focus window
expect "Cancel in the pane sends nothing" '[]' tailscale_changes "$tailscale_calls_mark"
for tailscale_self in 'tailscale-self-address|100.64.0.1' 'tailscale-self-dns|desk.tail-fixture.ts.net'; do
  IFS='|' read -r tailscale_copy_name tailscale_copy_want <<<"$tailscale_self"
  expect_poll "Tab reaches $tailscale_copy_name" reached tailscale_pane_named_tab RowAction "$tailscale_copy_name"
  tailscale_key Return
  expect_poll "$tailscale_copy_name reads Copied" '"Copied"' tailscale_pane_copy "$tailscale_copy_name"
  expect_poll "$tailscale_copy_name copies its own value" match tailscale_clipboard_matches "$tailscale_copy_want"
done
expect "Tab reaches the inline exit search" reached tailscale_tab_until '["TextField",""]' window
tailscale_key Down
expect_poll "Down reaches the recommended exit node" '["DeviceRow","Stockholm, Sweden"]' tailscale_focus window
tailscale_key Down
expect_poll "Down reaches None" '["DeviceRow","None"]' tailscale_focus window
expect "Tab reaches the own exit nodes" reached tailscale_tab_until '["DeviceRow","attic-nas"]' window tailscale-exit-own
tailscale_key Down
expect_poll "Down reaches the other own exit node" '["DeviceRow","gateway"]' tailscale_focus window
for tailscale_country in 'DE|Germany|Berlin|Frankfurt' 'SE|Sweden|Gothenburg|Malmö|Stockholm' 'US|United States|Ashburn|Chicago|Los Angeles|New York'; do
  IFS='|' read -ra tailscale_country_parts <<<"$tailscale_country"
  tailscale_code="${tailscale_country_parts[0]}"
  expect "Tab reaches ${tailscale_country_parts[1]}'s Disclosure" reached tailscale_tab_until "[\"ListItem\",\"${tailscale_country_parts[1]}\"]" window
  tailscale_key space
  expect_poll "${tailscale_country_parts[1]} expands inline" true ipc smoke readMatchingDescendant window vgs.tailscale Disclosure objectName "tailscale-exit-country-$tailscale_code" expanded
  tailscale_tab "Tab reaches ${tailscale_country_parts[1]}'s Best available" '["DeviceRow","Best available"]' window
  for tailscale_city in "${tailscale_country_parts[@]:2}"; do
    tailscale_key Down
    expect_poll "Down reaches $tailscale_city inline" "[\"DeviceRow\",\"$tailscale_city\"]" tailscale_focus window
  done
  if [[ $tailscale_code == SE ]]; then
    tailscale_tab "Tab reaches the one-city Switzerland choice" '["DeviceRow","Switzerland"]' window
    expect "Switzerland stays a one-city choice" shown tailscale_shown_of window DeviceList tailscale-exit-country-single-CH
  fi
done
expect "Tab reaches the network devices after the chooser" reached tailscale_tab_until '["DeviceRow","attic-nas"]' window tailscale-devices
for tailscale_peer in 'attic-nas|100.64.0.3' 'gateway|100.64.0.2' 'pixel|100.64.0.4' 'ipad|100.64.0.7' 'old-laptop|100.64.0.9'; do
  IFS='|' read -r tailscale_peer_name tailscale_peer_address <<<"$tailscale_peer"
  expect_poll "the network list reaches $tailscale_peer_name" "[\"DeviceRow\",\"$tailscale_peer_name\"]" tailscale_focus window
  tailscale_key Return
  expect_poll "$tailscale_peer_name still copies its address" match tailscale_clipboard_matches "$tailscale_peer_address"
  type_keys -M shift -k F10 -m shift || fail "tailscale: $tailscale_peer_name's menu key failed"
  expect_poll "$tailscale_peer_name's menu holds Copy DNS name" '[[["Copy DNS name"], "Copy DNS name"]]' tailscale_pane_menu
  tailscale_key Return
  expect_poll "$tailscale_peer_name's menu closes after Copy DNS name" '[]' tailscale_pane_menu
  expect_poll "$tailscale_peer_name copies its DNS name" match tailscale_clipboard_matches "$tailscale_peer_name.tail-fixture.ts.net"
  expect_poll "the menu returns the keys to $tailscale_peer_name" "[\"DeviceRow\",\"$tailscale_peer_name\"]" tailscale_focus window
  tailscale_key Tab
  expect_poll "$tailscale_peer_name's Copy action takes Tab" RowAction tailscale_focus_type window
  tailscale_tab "$tailscale_peer_name's overflow button takes Tab" '["IconButton","More actions"]' window
  type_keys -M shift -k Tab -k Tab -m shift || fail "tailscale: returning to $tailscale_peer_name failed"
  tailscale_key Down
done
expect "Tab reaches the pane's admin console" reached tailscale_tab_until '["RowAction","Open admin console"]' window
tailscale_opens_mark="$(tailscale_call_count xdg-open)" || { fail "tailscale: the xdg-open stand-in's calls are unreadable"; return 0; }
tailscale_key Return
expect_poll "the pane's admin console opens the stand-in browser" '[["https://login.tailscale.com/admin"]]' tailscale_opens "$tailscale_opens_mark"
expect_poll "Tab reaches Check every" reached tailscale_pane_named_tab SegmentedControl tailscale-poll
tailscale_key Right
expect_poll "Right selects the 60 s setting" 2 ipc smoke readMatchingDescendant window vgs.tailscale SegmentedControl objectName tailscale-poll currentIndex
tailscale_key Left
expect_poll "Left restores the 30 s setting" 1 ipc smoke readMatchingDescendant window vgs.tailscale SegmentedControl objectName tailscale-poll currentIndex
expect "the design pane closes" ok ipc shell hide window vgs.system

# The flyout's main view, the design's stand-in tailnet, by keys alone.
rest_pointer || fail "tailscale: moving the pointer off the flyout failed"
expect "the design flyout opens" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the design flyout is shown" shown tailscale_shown panel
expect_poll "the flyout opens on its header switch" '["Switch",""]' tailscale_focus
expect "the main view is titled Tailscale" '"Tailscale"' tailscale_title
expect "the header switch is shown and on" '[true, true, true]' tailscale_header_switch
expect_poll "the state line names the exit node" '["Connected through Stockholm, Sweden"]' tailscale_label tailscale-state
expect "the account row reads the account and tailnet, closed" '["amelie@example.com", "example.com"]' tailscale_drawn panel Disclosure tailscale-account
expect "this device reads its name, address and Copy" "$(words desk "This device · 100.64.0.1" Copy)" tailscale_drawn panel DeviceRow tailscale-this-device
expect "the network devices row reads 3 of 5 online, closed" '["Network devices", "3 of 5 online"]' tailscale_drawn panel Disclosure tailscale-network-devices
expect "the exit node row reads the node in use" '["Exit node", "Stockholm, Sweden"]' tailscale_drawn panel ListItem tailscale-exit-row
expect "the footer offers Open admin console" '["Open admin console"]' tailscale_drawn panel Button tailscale-admin-console
expect "the footer offers Tailscale settings" '["Tailscale settings"]' tailscale_drawn panel Button tailscale-settings
expect "the main view draws no Check every" 0 tailscale_check_every
expect "the main view draws no Sign out while the account row is closed" hidden tailscale_shown_of panel RowAction tailscale-sign-out
# The Pane's Settings gear follows the header switch (Pane.qml), as the
# v2-tailscale-flyout sheet draws it; this device's Copy is a Tab stop of
# its own after the row.
tailscale_tab "Tab reaches the header's Settings gear" '["IconButton","Settings"]'
tailscale_tab "Tab reaches the account row" '["ListItem","amelie@example.com"]'
tailscale_tab "Tab reaches this device" '["DeviceRow","desk"]'
tailscale_tab "Tab reaches this device's Copy" '["RowAction","Copy"]'
tailscale_tab "Tab reaches the network devices row" '["ListItem","Network devices"]'
tailscale_tab "Tab reaches the exit node row" '["ListItem","Exit node"]'
tailscale_tab "Tab reaches Open admin console" '["Button","Open admin console"]'
tailscale_tab "Tab reaches Tailscale settings" '["Button","Tailscale settings"]'

# Open admin console hands the admin address to the xdg-open stand-in.
tailscale_opens_mark="$(tailscale_call_count xdg-open)" || { fail "tailscale: the xdg-open stand-in's calls are unreadable"; return 0; }
type_keys -M shift -k Tab -m shift || fail "tailscale: Shift+Tab failed"
expect_poll "Shift+Tab returns to Open admin console" '["Button","Open admin console"]' tailscale_focus
tailscale_key Return
expect_poll "Open admin console hands the admin address to xdg-open" '[["https://login.tailscale.com/admin"]]' tailscale_opens "$tailscale_opens_mark"

# Copy: this device's address on the clipboard, Copied while it confirms.
expect "the flyout closes before Copy" ok ipc shell hide panel vgs.tailscale
expect "the flyout opens for Copy" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the reopened flyout opens on its header switch" '["Switch",""]' tailscale_focus
tailscale_tab "Tab reaches the gear for Copy" '["IconButton","Settings"]'
tailscale_tab "Tab reaches the account row for Copy" '["ListItem","amelie@example.com"]'
tailscale_tab "Tab reaches this device for Copy" '["DeviceRow","desk"]'
tailscale_key Return
expect_poll "Copy reads Copied while CopyText confirms" "[true, $(words desk "This device · 100.64.0.1" Copied)]" tailscale_copy_reading
expect_poll "the nested clipboard holds this device's IPv4 address" 100.64.0.1 tailscale_clipboard
expect_poll "Copy reads Copy again once the confirmation ends" "[false, $(words desk "This device · 100.64.0.1" Copy)]" tailscale_copy_reading
# The network devices, opened by keys.
tailscale_tab "Tab reaches this device's Copy before the network devices" '["RowAction","Copy"]'
tailscale_tab "Tab reaches the network devices row to open it" '["ListItem","Network devices"]'
tailscale_key space
expect_poll "the network devices list each peer with its address, online first" \
  "$(words "Network devices" "3 of 5 online" attic-nas 100.64.0.3 Copy gateway 100.64.0.2 Copy pixel 100.64.0.4 Copy ipad "100.64.0.7 · Offline" Copy old-laptop "100.64.0.9 · Offline" Copy)" \
  tailscale_drawn panel Disclosure tailscale-network-devices
tailscale_tab "Tab reaches the network devices' list" '["DeviceRow","attic-nas"]'
# Each device's Copy is a Tab stop of its own, so the count of presses is
# the list's, not the claim.
expect "Tab reaches the exit node row after the devices" reached tailscale_tab_until '["ListItem","Exit node"]'

# The Exit nodes view: Recommended, None, your exit nodes, Mullvad by
# country, read on its open; search, no match, a country, Back and Escape.
read_count tailscale_suggests_before "tailscale: suggestion reads before chooser" tailscale_suggests
tailscale_key Return
expect_poll "Enter on the exit node row opens the Exit nodes view" '"exit-nodes"' tailscale_view
expect_poll "the Exit nodes view opens on its search field" '["TextField",""]' tailscale_focus
# Sheet tailscale-flyout-a draws Recommended at the top of the chooser:
# the Pane's body, its one ScrollArea, rests unscrolled.
expect_poll "the Exit nodes view opens at its top, Recommended first" 0 ipc smoke readDescendant panel vgs.tailscale ScrollArea contentY
expect_poll "the chooser's opening reads the suggestion" "$((tailscale_suggests_before + 1))" tailscale_suggests
expect "the view is titled Exit nodes" '["Exit nodes"]' tailscale_label tailscale-view-title
expect "the view draws Back" drawn tailscale_mark panel Back
expect "the view hides the header switch" '[false]' tailscale_header_switch
expect_poll "the chooser lists Recommended, None, your exit nodes and Mullvad by country" \
  "$(words "Stockholm, Sweden" Recommended "In use" None "Use this computer's own connection" "Your exit nodes" attic-nas Online gateway Online Mullvad Germany "2 cities" Sweden "3 cities" "In use" Switzerland Zurich "United States" "4 cities")" \
  tailscale_drawn panel ExitNodes tailscale-exit-nodes
expect "the Exit nodes view draws no Check every" 0 tailscale_check_every
type_keys zur || fail "tailscale: typing the search failed"
expect_poll "a search shows the matching city flat" '["Zurich, Switzerland"]' tailscale_drawn panel ExitNodes tailscale-exit-nodes
type_keys -k BackSpace -k BackSpace -k BackSpace xyz || fail "tailscale: retyping the search failed"
expect_poll "a search no node matches offers Clear search" "$(words "No exit node matches “xyz”." "Clear search")" tailscale_drawn panel ExitNodes tailscale-exit-nodes
tailscale_tab "Tab reaches Clear search" '["Button","Clear search"]'
tailscale_key Return
expect_poll "Clear search returns the keys to the empty search field" '["TextField",""]' tailscale_focus
expect_poll "the cleared search lists every row again" \
  "$(words "Stockholm, Sweden" Recommended "In use" None "Use this computer's own connection" "Your exit nodes" attic-nas Online gateway Online Mullvad Germany "2 cities" Sweden "3 cities" "In use" Switzerland Zurich "United States" "4 cities")" \
  tailscale_drawn panel ExitNodes tailscale-exit-nodes
tailscale_key Down
expect_poll "Down from the search field reaches Recommended" '["DeviceRow","Stockholm, Sweden"]' tailscale_focus
tailscale_tab "Tab reaches your exit nodes" '["DeviceRow","attic-nas"]'
tailscale_tab "Tab reaches the Mullvad countries on Germany" '["DeviceRow","Germany"]'
tailscale_key Down
expect_poll "Down moves to Sweden" '["DeviceRow","Sweden"]' tailscale_focus
expect "the countries' selection is Sweden" '"SE"' ipc smoke readMatchingDescendant panel vgs.tailscale DeviceList objectName tailscale-exit-countries currentKey
tailscale_key Return
expect_poll "Enter on Sweden opens its country view" '"country"' tailscale_view
expect "the country view is titled Sweden" '["Sweden"]' tailscale_label tailscale-view-title
expect_poll "the country view lists Best available, then each city" "$(words "Best available" "Stockholm now" Gothenburg Malmö Stockholm "In use")" tailscale_drawn panel DeviceList tailscale-exit-cities
expect_poll "the country view takes the keys on Best available" '["DeviceRow","Best available"]' tailscale_focus
expect "the country view draws no Check every" 0 tailscale_check_every
tailscale_key Escape
expect_poll "Escape leaves the country view for the Exit nodes view" '"exit-nodes"' tailscale_view
expect_poll "the keys return to Sweden among the Mullvad countries" '["DeviceRow","Sweden"]' tailscale_focus
expect "the countries keep Sweden" '"SE"' ipc smoke readMatchingDescendant panel vgs.tailscale DeviceList objectName tailscale-exit-countries currentKey
tailscale_key Escape
expect_poll "Escape leaves the Exit nodes view" '"main"' tailscale_view
expect_poll "Escape returns the keys to the exit node row" '["ListItem","Exit node"]' tailscale_focus
tailscale_key Return
expect_poll "Enter opens the Exit nodes view again" '"exit-nodes"' tailscale_view
expect_poll "the search field takes the keys again" '["TextField",""]' tailscale_focus
# The gear sits between the title row's Back and the search field.
type_keys -M shift -k Tab -m shift || fail "tailscale: Shift+Tab failed"
expect_poll "Shift+Tab from the search field reaches the gear" '["IconButton","Settings"]' tailscale_focus
type_keys -M shift -k Tab -m shift || fail "tailscale: Shift+Tab failed"
expect_poll "Shift+Tab reaches Back" '["IconButton","Back"]' tailscale_focus
tailscale_key Return
expect_poll "Back leaves the Exit nodes view" '"main"' tailscale_view
expect_poll "Back returns the keys to the exit node row" '["ListItem","Exit node"]' tailscale_focus

# A search past the ceiling: Mullvad's United States and United Kingdom
# cities, 21 matches for "united", draw 20 rows and say so.
device_reply tailscale 0 "$(<"$tailscale_fixtures/sheet-cities.json")" status --json
expect "a refresh reads Mullvad's further cities" ok tailscale_refresh
expect_poll "the service publishes five Mullvad countries" 5 tailscale_country_count
tailscale_key Return
expect_poll "Enter opens the Exit nodes view for the long search" '"exit-nodes"' tailscale_view
expect_poll "the search field takes the keys for the long search" '["TextField",""]' tailscale_focus
type_keys united || fail "tailscale: typing the long search failed"
expect_poll "a search past the ceiling draws 20 rows and counts the matches" '[20, "Showing 20 of 21 matches."]' tailscale_search_reading
tailscale_key Escape
expect_poll "Escape leaves the long search for the main view" '"main"' tailscale_view
tailscale_use sheet.json
expect "a refresh reads the design's tailnet after the long search" ok tailscale_refresh
expect_poll "the service publishes the design's four countries again" 4 tailscale_country_count
expect_poll "the keys rest on the exit node row after the long search" '["ListItem","Exit node"]' tailscale_focus

# An offline exit node of your own is refused and no `set` runs; an
# online one is set by its DNS name and the view returns to the main view.
tailscale_offline="$(python3 -c 'import json,sys
status = json.load(open(sys.argv[1]))
for peer in status["Peer"].values():
    if peer["HostName"] == "gateway": peer["Online"] = False
print(json.dumps(status))' "$tailscale_fixtures/sheet.json")" || { fail "tailscale: the offline-node fixture is unreadable"; return 0; }
device_reply tailscale 0 "$tailscale_offline" status --json
expect "a refresh reads gateway offline" ok tailscale_refresh
expect_poll "the service publishes gateway offline" '[["attic-nas", true], ["gateway", false]]' tailscale_own_online
tailscale_calls_mark="$(tailscale_call_count tailscale)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
tailscale_key Return
expect_poll "Enter opens the Exit nodes view for the offline node" '"exit-nodes"' tailscale_view
expect_poll "your exit nodes read gateway offline" "$(words "Stockholm, Sweden" Recommended "In use" None "Use this computer's own connection" "Your exit nodes" attic-nas Online gateway Offline Mullvad Germany "2 cities" Sweden "3 cities" "In use" Switzerland Zurich "United States" "4 cities")" \
  tailscale_drawn panel ExitNodes tailscale-exit-nodes
tailscale_key Down
tailscale_tab "Tab reaches your exit nodes for the offline node" '["DeviceRow","attic-nas"]'
tailscale_key Down
expect_poll "Down reaches the offline gateway" '["DeviceRow","gateway"]' tailscale_focus
tailscale_key Return
expect_poll "the offline node is refused with its sentence" '["This exit node is offline."]' tailscale_label tailscale-exit-problem
expect "the refused node leaves the Exit nodes view open" '"exit-nodes"' tailscale_view
expect "no set reaches the stand-in for the offline node" '[]' tailscale_changes "$tailscale_calls_mark"
tailscale_key Up
expect_poll "Up reaches attic-nas" '["DeviceRow","attic-nas"]' tailscale_focus
tailscale_key Return
expect_poll "Enter on attic-nas sets it by its DNS name" '[["set", "--exit-node=attic-nas.tail-fixture.ts.net"]]' tailscale_changes "$tailscale_calls_mark"
expect_poll "the ended change returns to the main view" '"main"' tailscale_view
expect_poll "the keys return to the exit node row after the change" '["ListItem","Exit node"]' tailscale_focus
expect "the change leaves no problem" '""' tailscale_value problem
tailscale_use sheet.json
expect "a refresh reads gateway online again" ok tailscale_refresh
expect_poll "the service publishes gateway online again" '[["attic-nas", true], ["gateway", true]]' tailscale_own_online

# The other states the flyout draws. Tailscale stopping while the Exit
# nodes view shows ends the choice: the main view, on the header switch.
tailscale_key Return
expect_poll "Enter opens the Exit nodes view before Tailscale stops" '"exit-nodes"' tailscale_view
expect "a refresh reads Tailscale off" ok tailscale_sheet_as Stopped
expect_poll "Tailscale stopping leaves the Exit nodes view" '"main"' tailscale_view
expect_poll "the keys move to the header switch once Tailscale stops" '["Switch",""]' tailscale_focus
expect_poll "the off flyout's state line reads Off" '["Off"]' tailscale_label tailscale-state
expect "the off flyout's switch is shown and off" '[true, false, true]' tailscale_header_switch
expect "the off flyout keeps the account and this device" '["shown", "shown"]' tailscale_rows_of Disclosure:tailscale-account DeviceRow:tailscale-this-device
expect "the off flyout draws no network devices and no exit node" '["hidden", "hidden"]' tailscale_rows_of Disclosure:tailscale-network-devices ListItem:tailscale-exit-row
expect "a refresh reads Tailscale starting with the flyout open" ok tailscale_sheet_as Starting
expect_poll "the starting flyout's state line reads Starting" '["Starting"]' tailscale_label tailscale-state
expect "the starting flyout's switch is shown and on" '[true, true, true]' tailscale_header_switch
expect "the starting flyout keeps the account and this device" '["shown", "shown"]' tailscale_rows_of Disclosure:tailscale-account DeviceRow:tailscale-this-device
expect "the starting flyout draws no network devices and no exit node" '["hidden", "hidden"]' tailscale_rows_of Disclosure:tailscale-network-devices ListItem:tailscale-exit-row
expect "a refresh reads Tailscale waiting for approval" ok tailscale_sheet_as NeedsMachineAuth
expect_poll "the approval flyout's state line reads Waiting for approval" '["Waiting for approval"]' tailscale_label tailscale-state
expect "the approval flyout draws no header switch" '[false]' tailscale_header_switch
expect "the approval flyout names the tailnet's admin" '["An admin of example.com must approve this device."]' tailscale_label tailscale-state-hint
expect "the approval flyout offers Open admin console" '["Open admin console"]' tailscale_drawn panel RowAction tailscale-approval-console
expect "the approval flyout draws no account, device or exit node row" '["hidden", "hidden", "hidden", "hidden"]' tailscale_rows_of Disclosure:tailscale-account DeviceRow:tailscale-this-device Disclosure:tailscale-network-devices ListItem:tailscale-exit-row
device_reply tailscale 1 "" status --json
expect "a refresh reads Tailscale not answering" ok tailscale_refresh
expect_poll "the flyout's state line reads Not answering" '["Not answering"]' tailscale_label tailscale-state
expect "the not answering flyout draws no header switch" '[false]' tailscale_header_switch
expect "the not answering flyout says why" '["Tailscale did not answer."]' tailscale_label tailscale-state-hint
expect "the not answering flyout offers Try again" '["Try again"]' tailscale_drawn panel RowAction tailscale-try-again
tailscale_use sheet.json
expect "a refresh reads the running tailnet for the account row" ok tailscale_refresh
expect_poll "the flyout reads the running tailnet again" '["Connected through Stockholm, Sweden"]' tailscale_label tailscale-state
expect "the flyout closes after the other states" ok ipc shell hide panel vgs.tailscale

# Admin console without xdg-open: refused, and its requirement notice.
[[ $shell_host_path == "$sandbox/host-path" && -d $shell_host_path && ! -L $shell_host_path ]] || { fail "tailscale: the scanner PATH is not sandbox-owned"; return 0; }
tailscale_host_xdg=""
if [[ -e $shell_host_path/xdg-open || -L $shell_host_path/xdg-open ]]; then
  [[ -L $shell_host_path/xdg-open ]] || { fail "tailscale: the private xdg-open PATH entry is not a link"; return 0; }
  tailscale_host_xdg="$tailscale_dir/host-xdg-open"
  mv -T -- "$shell_host_path/xdg-open" "$tailscale_host_xdg"
fi
mv -- "$shim/xdg-open" "$tailscale_dir/hidden-xdg-open"
rescan "the scan reads xdg-open missing"
expect "Open admin console without xdg-open is refused" "refused: admin-console=missing-tool" tailscale_act admin-console
expect_poll "the refusal raises the requirement notice for xdg-open" '["vgs.tailscale", ["xdg-open"]]' tailscale_offered
expect_poll "the xdg-open notice holds the keyboard" true ipc smoke noticeFocused
tailscale_key Escape
expect_poll "Not now closes the xdg-open notice" null tailscale_offered
mv -- "$tailscale_dir/hidden-xdg-open" "$shim/xdg-open"
[[ -z $tailscale_host_xdg ]] || mv -T -- "$tailscale_host_xdg" "$shell_host_path/xdg-open"
rescan "the scan finds the xdg-open stand-in again"
expect "the shell resolves xdg-open to the stand-in again" "$shim/xdg-open" shell_resolves xdg-open

# Sign out: Add account and Sign out after the account list, a
# confirmation on Cancel, then `tailscale logout` and the signed-out view.
rest_pointer || fail "tailscale: moving the pointer off the flyout failed"
expect "the flyout opens for Sign out" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the flyout opens on its header switch, not Sign out" '["Switch",""]' tailscale_focus
tailscale_tab "Tab reaches the gear before the account row" '["IconButton","Settings"]'
tailscale_tab "Tab reaches the account row to open it" '["ListItem","amelie@example.com"]'
tailscale_key space
expect_poll "the account row lists both accounts, then Add account and Sign out" \
  "$(words amelie@example.com example.com amelie@example.com example.com "In use" amelie@example.org example.org "Add account" "Sign out")" \
  tailscale_drawn panel Disclosure tailscale-account
expect "Sign out takes the danger tone and the log-out mark" '[["danger", "log-out"]]' tailscale_sign_out_look
tailscale_tab "Tab reaches the account list" '["DeviceRow","amelie@example.com"]'
tailscale_tab "Tab reaches Add account after the account list" '["RowAction","Add account"]'
tailscale_tab "Tab reaches Sign out after Add account" '["RowAction","Sign out"]'
tailscale_tab "Tab leaves Sign out for this device" '["DeviceRow","desk"]'
type_keys -M shift -k Tab -m shift || fail "tailscale: Shift+Tab failed"
expect_poll "Shift+Tab returns to Sign out" '["RowAction","Sign out"]' tailscale_focus
tailscale_calls_mark="$(tailscale_call_count tailscale)" || { fail "tailscale: the tailscale stand-in's calls are unreadable"; return 0; }
tailscale_key Return
expect_poll "Sign out opens its confirmation" \
  "$(words "Sign out of example.com?" "This computer leaves example.com until you sign in again. An admin of example.com may need to approve this computer again." Cancel "Sign out")" \
  tailscale_drawn panel Dialog tailscale-sign-out-prompt
expect_poll "the confirmation opens on Cancel" '["Button","Cancel"]' tailscale_focus
tailscale_key Return
expect_poll "Cancel closes the confirmation" hidden tailscale_shown_of panel Dialog tailscale-sign-out-prompt
expect_poll "Cancel returns the keys to Sign out" '["RowAction","Sign out"]' tailscale_focus
expect "Cancel sends nothing" '[]' tailscale_changes "$tailscale_calls_mark"
tailscale_key Return
expect_poll "Sign out opens its confirmation again on Cancel" '["Button","Cancel"]' tailscale_focus
tailscale_tab "Tab reaches the confirmation's Sign out" '["Button","Sign out"]'
tailscale_key Return
expect_poll "the confirmation's Sign out hands tailscale logout to the stand-in" '[["logout"]]' tailscale_changes "$tailscale_calls_mark"
expect_poll "the flyout reads signed out" '["Signed out"]' tailscale_label tailscale-state
expect_poll "the signed-out flyout offers Sign in" '["Sign in"]' tailscale_drawn panel Button tailscale-sign-in
expect "the signed-out flyout says what Sign in does" '["Sign in to connect this computer to your tailnet."]' tailscale_label tailscale-state-hint
expect "the signed-out flyout draws no header switch" '[false]' tailscale_header_switch
expect_poll "the signed-out account row lists the other account and Add account, no Sign out" \
  "$(words Accounts "Not signed in" amelie@example.org example.org "Add account")" tailscale_drawn panel Disclosure tailscale-account
expect "the signed-out view draws no Check every" 0 tailscale_check_every
expect "the signed-out flyout closes" ok ipc shell hide panel vgs.tailscale
expect "the signed-out flyout opens again" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the signed-out flyout opens on its body, not Sign out" '["TailscaleBody",null]' tailscale_focus
expect "the signed-out flyout closes again" ok ipc shell hide panel vgs.tailscale
tailscale_enter_pane "signed-out pane"
expect_poll "the signed-out pane offers Sign in" shown tailscale_shown_of window Button tailscale-sign-in
expect "the signed-out pane keeps Updates last" '["Account", "Admin console", "Updates"]' tailscale_pane_sections
expect "the signed-out pane has no Sign out action" hidden tailscale_shown_of window RowAction tailscale-sign-out
expect "Tab reaches Sign in in the signed-out pane" reached tailscale_tab_until '["Button","Sign in"]' window
expect "the signed-out pane closes" ok ipc shell hide window vgs.system
rm -f -- "${tailscale_dir:?}/signed-out"
device_reply tailscale 0 "$(<"$tailscale_fixtures/accounts.json")" switch --list --json

# Sign-in: the printed address goes to the xdg-open stand-in.
tailscale_use logged-out.json
expect "a refresh reads the signed-out daemon" ok tailscale_refresh
expect_poll "the service publishes signed out" '"signed-out"' tailscale_value state
rm -f -- "${tailscale_dir:?}/login-release"
tailscale_opens_before="$(tailscale_call_count xdg-open)" || { fail "tailscale: the xdg-open stand-in's calls are unreadable"; return 0; }
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
rest_pointer || fail "tailscale: moving the pointer off the flyout failed"
expect "the flyout opens over the stopped daemon" ok ipc shell summon panel vgs.tailscale '{"source":"smoke"}'
expect_poll "the service-off flyout's state line names the service" '["The Tailscale service is off."]' tailscale_label tailscale-state
expect "the service-off flyout's switch is shown and off" '[true, false, true]' tailscale_header_switch
expect "the service-off switch draws its unlock mark named for Enable" drawn tailscale_mark panel Enable
expect "the service-off flyout says what Enable does" '["The Tailscale service is off. Enable turns it on."]' tailscale_label tailscale-setup-hint
expect "the service-off flyout offers Enable" '["Enable"]' tailscale_drawn panel RowAction tailscale-setup
expect "the service-off flyout closes" ok ipc shell hide panel vgs.tailscale
tailscale_enter_pane "service-off pane"
expect "the service-off pane keeps Updates last" '["Admin console", "Updates"]' tailscale_pane_sections
expect "the service-off pane keeps Check every" 1 tailscale_check_every window
expect "the service-off pane closes" ok ipc shell hide window vgs.system
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
tailscale_enter_pane "missing pane"
expect_poll "the missing pane offers Install Tailscale" shown tailscale_shown_of window EmptyState tailscale-install
expect "the missing pane hides Updates" hidden tailscale_shown_of window Section tailscale-updates-section
expect "Tab reaches Install Tailscale" reached tailscale_tab_until '["Button","Install Tailscale"]' window
tailscale_key Return
expect_poll "Install Tailscale offers its requirement" '["vgs.tailscale", ["tailscale"]]' tailscale_offered
expect_poll "the Tailscale requirement notice holds the keyboard" true ipc smoke noticeFocused
tailscale_key Escape
expect_poll "Not now closes the Tailscale requirement offer" null tailscale_offered
expect "the missing pane closes" ok ipc shell hide window vgs.system
mv -- "$tailscale_dir/hidden-command" "$shim/tailscale"
rescan "the Tailscale stand-in returns"
expect "a refresh reads the restored stand-in" ok tailscale_refresh
expect_poll "Tailscale restores its running tailnet" '"running"' tailscale_value state

# Controls, on a copy: a widget that polls on its own, a refresh that
# restarts the watchdog, a busy ask that restarts the suggestion's
# deadline, a killed read that retains its suggestion, and a failure table
# without the access-denied text.
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
for old, new in (
    ("        runPoll(\"refresh\");\n        readAccounts();\n", "        if (watchdog.running) watchdog.restart();\n        runPoll(\"refresh\");\n        readAccounts();\n"),
    ("        if (suggester.running) return \"busy\";\n", "        if (suggester.running) { suggestDeadline.restart(); return \"busy\"; }\n"),
):
    assert text.count(old) == 1, old
    text = text.replace(old, new)
old = 'root.suggestedName = root.snapshot.state === "running" ? read.name : "";'
assert text.count(old) == 1, old
text = text.replace(old, 'if (code !== -1) ' + old)
service.write_text(text)
text = body.read_text()
for old, new in (
    ('readonly property bool repeatsReason: true', 'readonly property bool repeatsReason: false'),
    ('        copier.copy(address);', '        copier.copy("wrong-clipboard.fixture.example");'),
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
tailscale_enter_pane "clipboard control"
expect_poll "control: Tab reaches this device's address Copy" reached tailscale_pane_named_tab RowAction tailscale-self-address
tailscale_key Return
expect_poll "control: a wrong clipboard value still reads Copied" '"Copied"' tailscale_pane_copy tailscale-self-address
expect "control: the clipboard judge rejects a wrong value despite Copied" mismatch tailscale_clipboard_matches 100.64.0.1
expect "the clipboard control pane closes" ok ipc shell hide window vgs.system
expect_poll "control: a widget that polls on its own is a call the service did not start" extra tailscale_surplus "$tailscale_control_before"
expect "control: a service that does not know the access-denied text leaves the plain failure's problem" same tailscale_failures
expect "control: a refresh that restarts the watchdog holds the poll past 20 s" postponed tailscale_hang
expect "the suggestion control reads the design's tailnet" ok tailscale_sheet_as Running
expect_poll "the control's service reads Tailscale running before its suggestion control" '"running"' tailscale_value state
expect_poll "the suggestion control starts with the old suggestion published" '{"id": "nSHEET0024CNTRL", "name": "Stockholm, Sweden"}' tailscale_value suggestion
expect "control: an ask that restarts the suggestion deadline holds the read past 20 s" postponed tailscale_suggest_hang
expect_poll "the control's held suggestion read ends once the asks stop" gone tailscale_suggest_held
tailscale_stale_control() { (failures=0 behaviour_failures=0; tailscale_suggest_clear >"$tailscale_dir/stale-control.log"; echo "$failures"); }
expect "control: retaining the killed read's old suggestion fails the null check with its replacement held" 1 tailscale_stale_control
control_output "$tailscale_dir/stale-control.log"
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
hypr_lua_restore tailscale || fail "hyprland.lua is put back after the Tailscale row's keyboard paths"
expect "the nested instance reloads hyprland.lua as the row found it" ok hypr reload config-only
