# Sourced by harness.sh: the leak check smoke_row runs over every row. The
# state a row hands to the rows after it must equal the state it found, in
# each class below, or a scoped run that holds the row and the full run on
# main read different states and one of them fails (VGS-877). A row that
# leaves a class on purpose declares it in its own leading comment block,
# `# leaves: CLASS [CLASS...]`; the check skips that class for that row and
# prints what the row left. After the raw end judgment, the boundary restores
# the wallpaper writer's JSON/link selection, then plugin enablement and
# actual bus relations. Other files, packages and images are not rolled back.
# A failed row takes one full restoration to its immutable start. A restore
# phase that cannot finish fails the row and the next phase runs; only the
# post reading ends this world, when a class reads unreadable or still
# differs, or shim fails. An unreadable entry reading also ends it. Start,
# raw end and post readings remain distinct.
#
# The classes, one reading each:
# - clients: the mapped client windows, `hyprctl -j clients`, as address,
#   class and title;
# - focus: the active window, active_window's [class, title];
# - submap: key_submap;
# - layers: the mapped layer surfaces, `hyprctl -j layers` with a pid, one
#   namespace each, read once the per-screen layers are at rest
#   (leak_layers_rest);
# - options: every Hyprland option `hyprctl -j descriptions` lists, with
#   its live value from `hyprctl -j getoption`;
# - plugins: each plugin's enablement in `shell listPlugins`;
# - bus-names: each well-known session-bus name's owner, `shell`,
#   `run:<comm>` for another harness-tree process, or `none`;
# - variables: leak_start_variables, each by `declare -p`;
# - shell: devices_guard's reading of the running shell, shell_qs_pid,
#   `no-shell` with no pid and `environ=unreadable` for a dead shell, with
#   `runner=[LINE]`, the last exit line the runner wrote to shell_log, or
#   `runner=[no-exit-line]`, so the failure names how the shell ended;
# - shim: the executable files of the shell's stand-in directory, $shim,
#   by name and content hash; the record files a stand-in writes there are
#   no command a shell runs.
#
# Each row is read at its start and at its end, so a harness step between
# two rows, such as qml-smoke.sh turning the compositor's logs on after
# hyprland-consent, belongs to no row. A row run inside another row, as
# rows/jarvis-keys.sh runs one and rows/updates.sh and rows/leak-check.sh
# run planted rows in subshells, is judged against its own start, and the
# outer row keeps its own. rows/leak-check.sh holds the controls.

# The start variables: what start_shell starts every shell with, shell_env
# and shell_start_words, and the PATH shell_resolves reads,
# shell_start_path, all defined in harness.sh.
leak_start_variables=(shell_start_path shell_start_words shell_env)
leak_classes=(clients focus submap layers options variables shell shim plugins bus-names)
# leak_starts: the start reading of each row running, innermost last.
leak_starts=()
leak_seq=0

# leak_reading: a new reading directory in leak_last. BASHPID keeps the
# readings a planted row takes in a subshell apart from the outer row's.
# leak_dir_next sets leak_next to the directory the next reading in this
# shell writes, so a planted row can name its own end reading; it sets a
# variable, since BASHPID in a command substitution is the subshell's.
leak_dir_next() { leak_next="$sandbox/leaks/$BASHPID-$((leak_seq + 1))"; }
leak_reading() {
  leak_dir_next
  leak_seq=$((leak_seq + 1))
  leak_last="$leak_next"
  leak_read "$leak_last"
}

# leak_read DIR: one file per class; a class that cannot be read has no file.
leak_read() { # DIR
  local name
  mkdir -p -- "$1"
  # Only the public driver requests advisory retention. Private detector
  # fixtures have no active metadata; required leak verdicts are independent.
  if [[ -f $sandbox/evidence/active ]]; then
    python3 "$repo/scripts/smoke/evidence.py" --reading "$sandbox" "$1" || printf 'qml-smoke: evidence=reader-command-failed reading=%s\n' "$1" >&2
  fi
  # The helper owns the product lock in its own process and starts no
  # children. Its lock descriptor cannot enter a reader or replacement
  # shell. Both sides bound a disconnected owner.
  local input output holder ready="" captured=true
  coproc leak_input_capture { leak_inputs capture "$sandbox" "$1" --hold; }
  holder=$! input="${leak_input_capture[1]:-}" output="${leak_input_capture[0]:-}"
  if [[ -z $output ]] || ! IFS= read -r -t "${stop_lock_wait_s:-10}" ready <&"$output" || [[ $ready != ready ]]; then captured=false; fi
  hypr -j clients >"$1/clients" 2>/dev/null || rm -f -- "$1/clients"
  active_window >"$1/focus" 2>/dev/null || rm -f -- "$1/focus"
  key_submap >"$1/submap" 2>/dev/null || rm -f -- "$1/submap"
  printf 'unavailable:no-probe\n' >"$1/layers.probe"
  printf '%s\n' "${shell_qs_pid:-}" >"$1/layers.pid"
  printf 'unavailable:no-layers\n' >"$1/layers.raw"
  local gone
  if leak_layers_rest "$1"; then
    if hypr -j layers >"$1/layers.raw" 2>/dev/null; then
      gone="$(leak_layers_gone "$1/layers.raw")"
      if [[ -z $gone ]]; then
        cp -- "$1/layers.raw" "$1/layers"
      else
        printf 'cause=%s\n' "$gone" >"$1/layers.unsettled"
        leak_socket_holders "$1" layers
        rm -f -- "$1/layers"
      fi
    else
      rm -f -- "$1/layers"
    fi
  else
    rm -f -- "$1/layers"
  fi
  leak_options "$1" 2>/dev/null || rm -f -- "$1/options"
  for name in "${leak_start_variables[@]}"; do
    declare -p "$name" 2>/dev/null || printf '%s unset\n' "$name"
  done >"$1/variables"
  leak_shell >"$1/shell"
  leak_plugins >"$1/plugins" 2>"$1/plugins.error" || rm -f -- "$1/plugins"
  local leak_bus_owner_file="$1/bus-pids"
  : >"$leak_bus_owner_file"
  if ! leak_bus_names >"$1/bus-names" 2>"$1/bus-names.error"; then
    rm -f -- "$1/bus-names"
    ! grep -q -F -e UnixProcessIdUnknown -- "$1/bus-names.error" || leak_socket_holders "$1" bus-names
  fi
  (cd -- "$shim" && find -L . -mindepth 1 -type f -executable -print0 | sort -z | xargs -0r sha1sum --) >"$1/shim" 2>/dev/null || rm -f -- "$1/shim"
  # Bash closes a reaped coprocess's descriptors and unsets its array, so
  # the release and the closes go only to a coprocess still listed. The
  # helper exits 3 when its hold expired after a complete capture.
  local held=0
  if [[ $ready == ready && -n ${leak_input_capture[1]:-} ]]; then { printf 'release\n' >&"$input"; } 2>/dev/null || :; fi
  if [[ -n ${leak_input_capture[1]:-} ]]; then { exec {input}>&- {output}<&-; } 2>/dev/null; fi
  wait "$holder" || held=$?
  [[ $held != 3 || $captured != true ]] || return 3
  [[ $held == 0 && $captured == true ]]
}

leak_input_idle() {
  local state
  # theme_idle answers its unreadable state with status 1; one line names it.
  state="$(theme_idle)" || :
  [[ $state == idle ]] || { printf 'qml-smoke: persisted-inputs=idle state=%s\n' "$state" >&2; return 1; }
}
# leak_inputs OPERATION ARGS...: scripts/smoke/persisted-inputs.py under
# its own bound, stop_lock_wait_s. The outer timeout is only a backstop 2 s
# past that bound, so the helper's deadline, its keyed line and its receipt
# always land first.
leak_inputs() { timeout --signal=KILL "$(( ${stop_lock_wait_s:-10} + 2 ))" python3 "$repo/scripts/smoke/persisted-inputs.py" "$@" --bound "${stop_lock_wait_s:-10}"; }
leak_input_compare() { leak_inputs compare "$sandbox" "$1" "$2"; }

# Isolated IPC and ANR fixtures replace the registry sensor without
# changing the IPC operations whose boundaries they exercise.
leak_plugins() { ipc shell listPlugins; }

# leak_bus_names [NAME]: all well-known names, or NAME even when unowned.
# GetConnectionUnixProcessID accepts well-known names (D-Bus specification,
# message-bus methods). No PID enters a reading, so a product restart with
# the same owners compares equal. Discovery and owner failures stay unreadable.
leak_bus_names() {
  local owners name pid relation comm
  owners="$("${shell_env[@]}" python3 - "$rt_dir/bus" "${1:-}" <<'PYBUS'
import sys
# A name whose owner goes away between the list and its PID lookup can
# answer UnixProcessIdUnknown (seen in a start-order restore at load1 50,
# VGS-2064). The reading starts again from a fresh list, at most READS
# times, so only a lookup that keeps failing reads unavailable.
READS = 3
try:
    import dbus
    bus = dbus.bus.BusConnection("unix:path=" + sys.argv[1])
    daemon = dbus.Interface(bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus", introspect=False), "org.freedesktop.DBus")
    for attempt in range(READS):
        names = [sys.argv[2]] if sys.argv[2] else list(daemon.ListNames(timeout=10))
        if not sys.argv[2] and "org.freedesktop.DBus" not in names:
            raise ValueError("discovery=incomplete")
        owners = []
        try:
            for name in sorted(n for n in names if not n.startswith(":")):
                try:
                    pid = daemon.GetConnectionUnixProcessID(name, timeout=10)
                except dbus.DBusException as error:
                    if error.get_dbus_name() != "org.freedesktop.DBus.Error.NameHasNoOwner":
                        raise
                    pid = "none"
                owners.append((name, pid))
        except dbus.DBusException as error:
            if error.get_dbus_name() != "org.freedesktop.DBus.Error.UnixProcessIdUnknown" or attempt == READS - 1:
                raise
            continue
        break
    for name, pid in owners:
        print(name, pid)
except Exception as error:
    print("bus-names: reading=unavailable reason=" + str(error), file=sys.stderr)
    sys.exit(1)
PYBUS
)" || return 1
  while read -r name pid; do
    if [[ $pid == none ]]; then relation=none
    elif [[ $pid == "${shell_qs_pid:-}" ]]; then relation=shell
    elif [[ $(in_harness_tree "$pid") == yes ]] && IFS= read -r comm <"/proc/$pid/comm"; then relation="run:$comm"
    else
      printf 'bus-names: name=%s owner=unreadable\n' "$name" >&2
      return 1
    fi
    [[ -z ${leak_bus_owner_file:-} || $pid == none ]] || printf '%s %s\n' "$name" "$pid" >>"$leak_bus_owner_file"
    printf '%s %s\n' "$name" "$relation"
  done <<<"$owners"
}

# leak_layers_rest DIR: waits for the per-screen layers to be at rest: the
# probe's perScreenLayers reports no host settling, and Hyprland maps each
# host's namespace on its screen exactly when the host's window is
# visible. A background maps only once its state file is read and its
# image decoded, both asynchronous, which can end after start_shell
# returns, so a reading taken before then misses a layer a later reading
# sees. It reads every 100 ms for up to timeout_s and writes the
# milliseconds it waited to DIR/layers.rest-ms, and the first state not at
# rest it read, if any, to DIR/layers.first-unsettled. With no shell, a
# shell whose probe has no perScreenLayers, or a compositor that does not
# answer, it returns at once and the layers are read as they stand; a
# probe that fails otherwise, or answers no list, does the same and
# leaves its reason in DIR/layers.unprobed. At the bound, or on a reading
# it cannot judge, it writes the last state to DIR/layers.unsettled and
# returns 1, so the layers class reads as unreadable there.
leak_layers_rest() { # DIR
  local start_ms probe layers state=no-reading reason
  [[ -n ${shell_qs_pid:-} ]] || return 0
  start_ms="$(now_ms)"
  while (( $(now_ms) - start_ms < timeout_s * 1000 )); do
    # Called in this shell, not a substitution, so ipc_last_reply holds
    # the raw reply for the failure's reason.
    if ! ipc smoke perScreenLayers >"$1/layers.probe" 2>/dev/null || ! probe="$(cat -- "$1/layers.probe")" || [[ $probe != \[* ]]; then
      reason="$(vgs_ipc_reply_failure "$ipc_last_reply")" || reason=unclassified
      [[ $reason == function-not-found ]] || printf 'reason=%s reply=%s\n' "$reason" "${ipc_last_reply:0:200}" >"$1/layers.unprobed"
      return 0
    fi
    layers="$(hypr -j layers 2>/dev/null)" || { printf '%s\n' "$layers" >"$1/layers.raw"; return 0; }
    printf '%s\n' "$layers" >"$1/layers.raw"
    state="$(leak_layers_gone "$1/layers.raw")"
    if [[ -n $state ]]; then
      printf 'cause=%s\n' "$state" >"$1/layers.unsettled"
      leak_socket_holders "$1" layers
      return 1
    fi
    state="$(leak_layers_state "$probe" "$layers")" || break
    if [[ $state == rest ]]; then
      echo "$(( $(now_ms) - start_ms ))" >"$1/layers.rest-ms"
      return 0
    fi
    [[ -e $1/layers.first-unsettled ]] || printf '%s\n' "$state" >"$1/layers.first-unsettled"
    sleep 0.1
  done
  printf '%s\n' "$state" >"$1/layers.unsettled"
  return 1
}

# leak_layers_gone RAW: from `hyprctl -j layers` in RAW, one word
# `owner-gone` and each mapped layer whose owner pid has no /proc entry,
# `pid=N namespace=NS screen=S`; nothing when every owner runs. The
# compositor keeps a client's surfaces while any process still holds its
# connection, so such a layer never settles and its reading is no state.
leak_layers_gone() { # RAW
  python3 - "$1" <<'PY'
import json, os, sys
try:
    layers = json.load(open(sys.argv[1]))
    gone = sorted({(l["pid"], l["namespace"], screen) for screen, m in layers.items() for level in m["levels"].values()
                   for l in level if l["pid"] != -1 and not os.path.exists(f"/proc/{l['pid']}")})
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    sys.exit(0)
if gone:
    print("owner-gone " + " ".join(f"pid={p} namespace={ns} screen={s}" for p, ns, s in gone))
PY
}
# leak_socket_holders DIR CLASS: evidence only, when reading DIR met a
# layer or bus name whose owner is gone. For each connection the nested
# compositor's Wayland socket or the session bus accepted, the holders of
# its client end, from `ss -xpnH` (unix socket inode, peer inode, holding
# processes). A connection none of whose holders the compositor (a layer
# or client pid in DIR) or the bus (a unique name's pid) names as a client
# is unclaimed, and each of its holders prints as `qml-smoke:
# socket-holder class=CLASS reading=R bus=wayland|dbus inode=N pid=P
# ppid=Q start=TICKS comm=C cmdline=[...]`, also kept in
# DIR/socket-holders. It ends and signals nothing.
leak_socket_holders() { # DIR CLASS
  python3 - "${rt_dir:-}/${nested_socket:-}" "${rt_dir:-}/bus" "$1" "$2" <<'PY' | tee -a "$1/socket-holders"
import json, os, re, subprocess, sys
wayland, bus, reading, cls = sys.argv[1:5]
key = f"qml-smoke: socket-holders class={cls} reading={os.path.basename(reading)}"
try:
    out = subprocess.run(["ss", "-xpnH"], capture_output=True, text=True, timeout=10)
except (OSError, subprocess.TimeoutExpired) as error:
    print(f"{key} status=unavailable reason=[{error}]")
    sys.exit(0)
if out.returncode:
    print(f"{key} status=unavailable reason=ss-exit-{out.returncode}")
    sys.exit(0)
sockets = {}
for line in out.stdout.splitlines():
    words = line.split()
    if len(words) < 8 or not words[0].startswith("u_"):
        continue
    users = [int(m.group(1)) for m in re.finditer(r",pid=(\d+),fd=\d+\)", line)]
    sockets[words[5]] = (words[4], words[7], users)
claimed = {"wayland": set(), "dbus": set()}
for name in ("layers.raw", "clients"):
    try:
        data = json.load(open(os.path.join(reading, name)))
        if name == "clients":
            claimed["wayland"].update(c["pid"] for c in data)
        else:
            claimed["wayland"].update(l["pid"] for m in data.values() for level in m["levels"].values() for l in level)
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        pass
try:
    import dbus
    daemon = dbus.Interface(dbus.bus.BusConnection("unix:path=" + bus).get_object("org.freedesktop.DBus", "/org/freedesktop/DBus", introspect=False), "org.freedesktop.DBus")
    for name in daemon.ListNames(timeout=10):
        if name.startswith(":"):
            try:
                claimed["dbus"].add(int(daemon.GetConnectionUnixProcessID(name, timeout=10)))
            except dbus.DBusException:
                pass
except Exception as error:
    print(f"{key} bus=dbus claims=unavailable reason=[{error}]")
def describe(pid):
    try:
        state = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
        comm = open(f"/proc/{pid}/comm").read().strip()
        argv = open(f"/proc/{pid}/cmdline", "rb").read().rstrip(b"\0").replace(b"\0", b" ").decode(errors="replace")
        return f"ppid={state[1]} start={state[19]} comm={comm} cmdline=[{argv[:300]}]"
    except (OSError, IndexError):
        return "process=gone"
for bus_name, path in (("wayland", wayland), ("dbus", bus)):
    unclaimed = 0
    for inode, (local, peer, _) in sorted(sockets.items()):
        if local != path or peer in ("0", "*"):
            continue
        holders = sockets.get(peer, (None, None, []))[2]
        if set(holders) & claimed[bus_name]:
            continue
        unclaimed += 1
        if not holders:
            print(f"{key} bus={bus_name} inode={peer} holders=none")
        for pid in sorted(set(holders)):
            print(f"qml-smoke: socket-holder class={cls} reading={os.path.basename(reading)} bus={bus_name} inode={peer} pid={pid} {describe(pid)}")
    if not unclaimed:
        print(f"{key} bus={bus_name} unclaimed=none")
PY
}

# leak_layers_state PROBE LAYERS: `rest`, or one entry per host not at
# rest, `NAMESPACE@SCREEN visible=V mapped=M settling=IDS`, from the
# probe's perScreenLayers and `hyprctl -j layers`; a host namespace a
# monitor maps with no host on it shown reads `visible=none`. A reading it
# cannot parse prints `judge=failed` and exits 1.
leak_layers_state() { # PROBE LAYERS
  python3 - "$@" <<'PY'
import json, sys
try:
    hosts, layers = json.loads(sys.argv[1]), json.loads(sys.argv[2])
    mapped = {(name, l["namespace"]) for name, m in layers.items() for level in m["levels"].values() for l in level if l["pid"] != -1}
    namespaces = {h["namespace"] for h in hosts}
    words, held = [], set()
    for h in hosts:
        held.add((h["screen"], h["namespace"]))
        on = (h["screen"], h["namespace"]) in mapped
        if h["settling"] or on != h["visible"]:
            words.append(f'{h["namespace"]}@{h["screen"]} visible={str(h["visible"]).lower()} mapped={str(on).lower()} settling={",".join(h["settling"]) or "none"}')
    words += [f"{ns}@{name} visible=none mapped=true" for name, ns in sorted(mapped - held) if ns in namespaces]
except (ValueError, KeyError, TypeError, AttributeError) as e:
    print(f"judge=failed reason={type(e).__name__}")
    sys.exit(1)
print(" ".join(words) if words else "rest")
PY
}

# leak_options DIR: options.names, every option `hyprctl -j descriptions`
# lists, and options, their `getoption` replies in that order from one
# batch. The descriptions' own `current` is not the live value: on the
# host's Hyprland 0.56.2 it read general:border_size 1 where getoption
# read the 2 the session had set.
leak_options() { # DIR
  local requests
  hypr -j descriptions | python3 -c 'import json,sys; [print(o["name"]) for o in json.load(sys.stdin)]' >"$1/options.names" || return
  requests="$(sed 's|^|j/getoption |' -- "$1/options.names" | paste -sd ';')" || return
  hypr --batch "$requests" >"$1/options"
}

leak_shell() {
  local reading
  if [[ -z ${shell_qs_pid:-} ]]; then
    echo no-shell
  elif reading="$(devices_guard "$shell_qs_pid" 2>/dev/null)"; then
    printf '%s\n' "$reading"
  else
    echo "environ=unreadable runner=[$(leak_runner_exit)]"
  fi
}
# leak_runner_exit: the last `vgshell: shell=exited` or `shell=gave-up`
# line of shell_log, which bin/vgshell's runner writes at each exit of its
# shell with the exit status; `no-exit-line` when the log holds none.
leak_runner_exit() {
  local line
  line="$(grep -E '^vgshell: shell=(exited|gave-up) ' -- "${shell_log:-/dev/null}" 2>/dev/null | tail -n 1)" || line=""
  printf '%s\n' "${line:-no-exit-line}"
}

leak_row_start() {
  local entry
  leak_input_idle || return 1
  leak_reading || return 1
  entry="$(leak_judge /dev/null "$leak_last" "$leak_last")" || return 1
  [[ -z $entry ]] || { printf 'qml-smoke: entry=unreadable value=%s\n' "$entry"; return 1; }
  leak_starts+=("$leak_last")
  local name
  : >"$leak_last/launch"
  for name in "${leak_start_variables[@]}"; do
    if declare -p "$name" >>"$leak_last/launch" 2>/dev/null; then :; else printf 'unset %s\n' "$name" >>"$leak_last/launch"; fi
  done
  cp -- "$home/.config/hypr/hyprland.lua" "$leak_last/hyprland.lua" || return 1
  display_record_call row-acquire "$leak_last" "$BASHPID" "${shell_pid:-}" "${shell_qs_pid:-}" >/dev/null
}

# leak_row_end NAME DIR: the row's end reading against its start: one fail
# per class it leaves, `NAME: leaves CLASS: +VALUE -VALUE`, and one per
# class a reading could not read.
leak_row_end() { # NAME DIR
  local start="${leak_starts[-1]}" verdicts verdict class values
  local reading_status=0
  leak_reading || reading_status=$?
  case "$reading_status" in
    0) : ;;
    3) row_class=operation fail "$1: persisted-inputs=hold-expired start=$start end=$leak_last" ;;
    *) row_class=operation fail "$1: persisted-inputs=raw-unreadable start=$start end=$leak_last" ;;
  esac
  leak_end="$leak_last"
  local input_status=0
  leak_input_compare "$start" "$leak_end" || input_status=$?
  case "$input_status" in
    0) : ;;
    1) leak_managed_delta "$1" persisted-inputs changed ;;
    *) row_class=operation fail "$1: persisted-inputs=raw-comparison-unreadable start=$start end=$leak_end" ;;
  esac
  if ! verdicts="$(leak_judge "$2/$1.sh" "$start" "$leak_last")"; then
    leak_verdicts=""
    fail "$1: leak-check judge=failed start=$start end=$leak_last"
    return 0
  fi
  leak_verdicts="$verdicts"
  while IFS=$'\t' read -r verdict class values; do
    case "$verdict" in
      leaves)
        if [[ $class == plugins || $class == bus-names ]]; then
          leak_managed_delta "$1" "$class" "$values"
        else
          fail "$1: leaves $class: $values"
        fi ;;
      declared) ok "$1: leaves $class, as its header declares: $values" ;;
      unreadable) fail "$1: leak-check reading=unreadable class=$class at=$values start=$start end=$leak_last$(leak_unsettled "$class" "$values" "$start")" ;;
      refused) fail "$1: leak-check refused: leaves=$class reason=unknown-class" ;;
    esac
    if [[ $class == layers && ( $verdict == leaves || $verdict == unreadable ) ]]; then
      leak_layer_diagnostics "$start"
      leak_layer_diagnostics "$leak_last"
    fi
  done <<<"$verdicts"
}
leak_managed_delta() { printf 'qml-smoke: boundary row=%s class=%s delta=%s\n' "$1" "$2" "$3"; }

# Explicit row setup, never a start/stop hook. All callers name their own
# preconditions; the boundary returns these flags to the incoming profile.
leak_plugin_setup() { # ID BOOLEAN [ID BOOLEAN...]
  local id enabled current reply
  while (( $# )); do
    (( $# >= 2 )) || return 1
    id="$1" enabled="$2"; shift 2
    [[ $enabled == true || $enabled == false ]] || return 1
    current="$(ipc shell listPlugins | py_reply 'import json,sys; r=json.load(sys.stdin); print(next((str(p["enabled"]).lower() for p in r["plugins"] if p["id"]==sys.argv[1]), "missing") if r["scanned"] else "pending")' "$id")" || return 1
    [[ $current != missing && $current != pending ]] || return 1
    if [[ $current != "$enabled" ]]; then
      reply="$(ipc shell setPluginEnabled "$id" "$enabled")" || return 1
      [[ $reply == ok ]] || return 1
    fi
    leak_plugin_wait "$id" "$enabled" || return 1
  done
}
leak_plugin_wait() { # ID BOOLEAN
  local current deadline=$(( $(now_ms) + timeout_s * 1000 ))
  while :; do
    current="$(ipc shell listPlugins | py_reply 'import json,sys; r=json.load(sys.stdin); print(next((str(p["enabled"]).lower() for p in r["plugins"] if p["id"]==sys.argv[1]), "missing") if r["scanned"] else "pending")' "$1")" || return 1
    [[ $current != "$2" ]] || return 0
    (( $(now_ms) < deadline )) || return 1
    sleep 0.1
  done
}

# A process-lifetime server may remain after its holder is disabled
# (NotificationHub.qml). The actual bus relation, never its flag, decides.
leak_notifications_setup() {
  local owner profile probe_enabled
  owner="$(leak_bus_names org.freedesktop.Notifications)" || return 1
  [[ $owner != 'org.freedesktop.Notifications shell' ]] || return 0
  profile="$(ipc shell listPlugins)" || return 1
  probe_enabled="$(py_reply 'import json,sys; print(next(str(p["enabled"]).lower() for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.probe"))' <<<"$profile")" || return 1
  leak_plugin_setup acme.probe true || return 1
  leak_name_wait org.freedesktop.Notifications shell || return 1
  leak_plugin_setup acme.probe "$probe_enabled"
}
leak_name_wait() { # NAME RELATION
  local value deadline=$(( $(now_ms) + timeout_s * 1000 ))
  while :; do
    value="$(leak_bus_names "$1")" || return 1
    [[ $value != "$1 $2" ]] || return 0
    (( $(now_ms) < deadline )) || return 1
    sleep 0.1
  done
}

leak_restore_plugins() { # START
  local target current id enabled reply
  target="$(leak_judge --profile "$1/plugins")" || return 1
  mkdir -p -- "$1.restore" || return 1
  ipc shell listPlugins >"$1.restore/plugins" || return 1
  current="$(leak_judge --profile "$1.restore/plugins")" || return 1
  # Missing enabled IDs cannot be reconstructed by changing flags. A new
  # fixture remains installed, but is disabled when it was absent at entry.
  while read -r id enabled; do
    [[ $enabled != true || $'\n'"$current"$'\n' == *$'\n'"$id "* ]] || return 1
  done <<<"$target"
  while read -r id enabled; do
    local wanted=false entry flag
    while read -r entry flag; do [[ $entry != "$id" ]] || wanted="$flag"; done <<<"$target"
    [[ $enabled == "$wanted" ]] || leak_plugin_setup "$id" "$wanted" || return 1
  done <<<"$current"
}

# The only row-boundary operation. Its phases retain the same immutable
# target, and never retry a failed managed teardown as a full restoration.
# A phase that cannot finish fails the row as `restoration step=<phase>
# cause=<key>` and the next phase runs: only leak_row_restore's post
# reading decides whether the run ends.
leak_restore_step() { # NAME PHASE CAUSE
  row_class=operation fail "$1: restoration step=$2 cause=$3"
}
# leak_restore_stop NAME PHASE: the shell's stop, under the restoration's
# policy. A forced stop or a runner already gone is cleanup that worked;
# an unproved stop or a held lock fails the row.
leak_restore_stop() { # NAME PHASE
  local restore_stop
  shell_stop restore_stop
  case "$restore_stop" in
    stopped) : ;;
    forced) printf 'qml-smoke: restore row=%s step=%s outcome=forced\n' "$1" "$2" ;;
    *) leak_restore_step "$1" "$2" "$restore_stop" ;;
  esac
  display_record_call row-stop-shells "${leak_starts[-1]}" "$$" >/dev/null || leak_restore_step "$1" "$2" stop-shells-refused
}
# leak_restore_shell NAME: the run tree's shell, for the restoration. Its
# runner refuses while another process holds the instance lock, so the
# lock is waited for first. A shell that ends as soon as it answered is
# its runner's to start again, and the runner's next shell is taken up.
leak_restore_shell() { # NAME
  local started state
  flock -w "${stop_lock_wait_s:-10}" "$rt_dir/vgshell.lock" true || leak_restore_step "$1" start-shell lock-held
  if ! start_shell "$repo" "$sandbox/shell-restore-$BASHPID-$leak_seq.log"; then
    leak_restore_step "$1" start-shell no-answer
    return 0
  fi
  started="${shell_qs_pid:-}"
  [[ -n $started ]] || return 0
  if ! state="$(ps -o stat= -p "$started")" || [[ $state == Z* ]]; then
    leak_restore_step "$1" start-shell "shell-ended pid=$started"
    adopt_shell "$started" || leak_restore_step "$1" start-shell "no-relaunch pid=$started"
  fi
}
leak_restore_start() { # NAME SCOPE ORIGINAL_STATUS
  local start="${leak_starts[-1]}" name relation owners current replace=false names=true
  printf 'qml-smoke: restore=begin row=%s scope=%s original-status=%s start=%s end=%s\n' "$1" "$2" "$3" "$start" "$leak_end"
  # declare in a sourced file would create function locals. -g preserves
  # the entry scalar/array type, indices, exact bytes and unset state.
  for name in "${leak_start_variables[@]}"; do unset "$name"; done
  source /dev/stdin < <(sed 's/^declare /declare -g /' "$start/launch")
  cmp -s -- "$start/variables" <(for name in "${leak_start_variables[@]}"; do declare -p "$name" 2>/dev/null || printf '%s unset\n' "$name"; done) || leak_restore_step "$1" variables differ
  [[ -f $start/bus-names ]] || { leak_restore_step "$1" bus-names start-unread; names=false; }
  if [[ $2 == full ]]; then
    leak_restore_stop "$1" stop
  else
    leak_input_idle || leak_restore_step "$1" input-idle not-idle
  fi
  if mkdir -p -- "$start.restore"; then
    local inputs_status=0
    leak_inputs restore "$sandbox" "$start" "$start.restore" || inputs_status=$?
    [[ $inputs_status == 0 ]] || leak_restore_step "$1" persisted-inputs "exit=$inputs_status"
  else
    leak_restore_step "$1" persisted-inputs receipt-directory
  fi
  [[ $2 != full ]] || leak_restore_shell "$1"
  # Persist the target flags before a name-release replacement. Otherwise
  # its first frame could reacquire the process-lifetime server immediately.
  leak_restore_plugins "$start" || leak_restore_step "$1" plugins refused
  if [[ $names == true ]] && owners="$(leak_bus_names)"; then
    printf '%s\n' "$owners" >"$start.restore/bus-names"
    while read -r name relation; do
      current="$(awk -v name="$name" '$1 == name { print $2 }' <<<"$owners")"
      if [[ $relation == none && ${current:-none} != none ]]; then replace=true; fi
    done < <(python3 - "$start/bus-names" "$start.restore/bus-names" <<'PY'
import sys
before, after = (dict(line.rstrip().split(" ", 1) for line in open(p)) for p in sys.argv[1:])
for name in sorted(before.keys() | after.keys()):
    print(name, before.get(name, "none"))
PY
)
  elif [[ $names == true ]]; then
    leak_restore_step "$1" bus-names unreadable
    names=false
  fi
  if [[ $replace == true ]]; then
    # A name-release replacement; it also stops a direct or abandoned
    # shell that still owns run windows.
    leak_restore_stop "$1" name-release
    leak_restore_shell "$1"
  fi
  leak_restore_plugins "$start" || leak_restore_step "$1" plugins refused
  if [[ $names == true ]]; then
    while read -r name relation; do
      if [[ $relation == shell && $name == org.freedesktop.Notifications ]]; then
        leak_notifications_setup || leak_restore_step "$1" name-holder "name=$name"
      fi
      leak_name_wait "$name" "$relation" || leak_restore_step "$1" name-wait "name=$name want=$relation"
    done <"$start/bus-names"
    local leak_bus_owner_file="$start.restore/bus-pids"
    : >"$leak_bus_owner_file"
    if leak_bus_names >"$start.restore/final-bus-names"; then
      display_record_call row-verify-bus "$start" "$leak_bus_owner_file" >/dev/null || leak_restore_step "$1" bus-owners unproved
    else
      leak_restore_step "$1" bus-owners unreadable
    fi
  fi
  if [[ $2 == full ]]; then
    { cp -- "$start/hyprland.lua" "$home/.config/hypr/hyprland.lua.next" && mv -T -- "$home/.config/hypr/hyprland.lua.next" "$home/.config/hypr/hyprland.lua"; } || leak_restore_step "$1" hyprland-config write
    hypr reload config-only >/dev/null || leak_restore_step "$1" hyprland-config reload
    display_record_call anr-cleanup "$1" >/dev/null || leak_restore_step "$1" anr-cleanup refused
    display_record_call row-close-added "$start" "$$" "${shell_qs_pid:-}" "$shell_class" "$shell_reporter_class" >/dev/null || leak_restore_step "$1" close-added refused
    local address
    if address="$(python3 - "$start/clients" "$start/focus" <<'PY'
import json,sys
clients, focus = (json.load(open(p)) for p in sys.argv[1:])
found = [c["address"] for c in clients if c["mapped"] and [c["class"],c["title"]] == focus]
if focus and len(found) != 1:
    sys.exit(1)
print(found[0] if focus else "")
PY
)"; then
      [[ -z $address ]] || hypr dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null || leak_restore_step "$1" focus dispatch
    else
      leak_restore_step "$1" focus unmatched
    fi
  fi
  printf 'qml-smoke: restore=end row=%s scope=%s original-status=%s\n' "$1" "$2" "$3"
}

# leak_row_restore NAME DIR FAILED ORIGINAL_STATUS: one restoration, then
# the post reading, the one judge of whether the run ends: a class that
# still differs or reads unreadable, and shim always, ends it with the
# original status. Every other failure here fails the row.
leak_row_restore() { # NAME DIR FAILED ORIGINAL_STATUS
  local start="${leak_starts[-1]}" scope=managed status="$4" verdicts verdict class values restoration=applied shim_failed=false
  [[ $3 == false ]] || scope=full
  while IFS=$'\t' read -r verdict class values; do
    if [[ $class == shim && ( $verdict == leaves || $verdict == unreadable ) ]]; then shim_failed=true; fi
  done <<<"${leak_verdicts:-}"
  # A row's IPC timeout latches the row's later calls (ipc_call_last). The
  # restoration and then the post reading each talk to the shell under a
  # latch of their own, so one stalled call cannot unread the other.
  local ipc_timeout_log="$sandbox/rows/$1.restore.ipc-timeout.log" timeout_line
  : >"$ipc_timeout_log"
  leak_restore_start "$1" "$scope" "$status"
  leak_input_idle || leak_restore_step "$1" post-idle not-idle
  while IFS= read -r timeout_line || [[ -n $timeout_line ]]; do
    leak_restore_step "$1" ipc "[$timeout_line]"
  done <"$ipc_timeout_log"
  ipc_timeout_log="$sandbox/rows/$1.post.ipc-timeout.log"
  : >"$ipc_timeout_log"
  local post_status=0
  leak_reading || post_status=$?
  local post="$leak_last"
  if [[ $post_status == 3 ]]; then
    leak_restore_step "$1" post-reading hold-expired
  elif [[ $post_status != 0 ]]; then
    row_class=operation fail "$1: restoration=unreadable class=persisted-inputs start=$start post=$post"
    restoration=failed
  fi
  local input_status=0
  leak_input_compare "$start" "$post" || input_status=$?
  case "$input_status" in
    0) : ;;
    1) row_class=operation fail "$1: restoration=leaves class=persisted-inputs start=$start end=$leak_end post=$post"; restoration=failed ;;
    *) row_class=operation fail "$1: restoration=unreadable class=persisted-inputs start=$start end=$leak_end post=$post"; restoration=failed ;;
  esac
  if ! verdicts="$(leak_judge "$2/$1.sh" "$start" "$post")"; then
    row_class=operation fail "$1: restoration=unreadable start=$start post=$post"
    restoration=failed
  else
    while IFS=$'\t' read -r verdict class values; do
      case "$verdict" in
        leaves|unreadable|refused)
          row_class=operation fail "$1: restoration=$verdict class=$class value=$values start=$start end=$leak_end post=$post"
          if [[ $class == layers && ( $verdict == leaves || $verdict == unreadable ) ]]; then
            leak_layer_diagnostics "$start"
            leak_layer_diagnostics "$post"
          fi
          restoration=failed ;;
      esac
    done <<<"$verdicts"
  fi
  ipc_timeout_check "$1" || :
  display_record_call row-release "$start" >/dev/null || leak_restore_step "$1" release refused
  unset 'leak_starts[-1]'
  if [[ $restoration == failed || $shim_failed == true ]]; then
    [[ $status != 0 ]] || status=1
    printf 'qml-smoke: restoration=terminal row=%s original-status=%s\n' "$1" "$status"
    exit "$status"
  fi
}

# The recorder owns historical PID/instance/stop joins. This report cannot
# affect the namespace-only settlement or multiset verdict above.
leak_layer_diagnostics() { # DIR
  local report
  if report="$(display_record_call layer-reading "$1" "$(<"$1/layers.pid")" 2>"$1/layers.owners.error")"; then
    printf '%s\n' "$report" >"$1/layers.owners" || printf 'qml-smoke: evidence=layer-owner-write-failed reading=%s\n' "$1" >&2
    printf '        layer-owner %s\n' "$report"
  else
    printf 'unavailable\n' >"$1/layers.owners" || printf 'qml-smoke: evidence=layer-owner-write-failed reading=%s\n' "$1" >&2
    printf '        layer-owner unavailable raw=%s/layers.raw probe=%s/layers.probe\n' "$1" "$1"
  fi
}

# leak_unsettled CLASS SIDE START: ` unsettled=<state>` when the reading
# on SIDE, START's or leak_last's, left CLASS unread because its layers
# did not come to rest; nothing otherwise.
leak_unsettled() { # CLASS SIDE START
  local dir="$leak_last" state
  [[ $2 != start ]] || dir="$3"
  if [[ -f $dir/$1.unsettled ]] && state="$(cat -- "$dir/$1.unsettled")"; then
    if [[ $state == cause=* ]]; then printf ' %s' "$state"; else printf ' unsettled=%s' "$state"; fi
  fi
}

# leak_judge ROW_FILE START END: one tab-separated line per finding:
# `leaves CLASS VALUES`, `declared CLASS VALUES`, `unreadable CLASS
# start|end` or `refused WORD` for a `# leaves:` word that names no class.
# A class unreadable at either end is not compared.
leak_judge() { # ROW_FILE START END
  python3 - "$@" "${leak_classes[@]}" <<'PY'
import collections, json, os, re, sys
def plugin_profile(text):
    registry = json.loads(text)
    rows = registry["plugins"]
    if registry["scanned"] is not True or not isinstance(rows, list) or any(not isinstance(p["id"], str) or type(p["enabled"]) is not bool for p in rows):
        raise ValueError("plugins: scan")
    profile = {p["id"]: p["enabled"] for p in rows}
    if "vgs.bar" not in profile or len(profile) != len(rows):
        raise ValueError("plugins: coverage-or-duplicate")
    return profile

if sys.argv[1] == "--profile":
    try:
        with open(sys.argv[2]) as f:
            profile = plugin_profile(f.read())
        for key, enabled in sorted(profile.items()):
            print(key, str(enabled).lower())
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print("plugins: profile=unreadable reason=" + str(error), file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
row_file, start, end, classes = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
SHOWN, CUT = 8, 200

def items(directory, name):
    try:
        with open(os.path.join(directory, name)) as f:
            text = f.read()
    except OSError:
        return None
    try:
        if name == "clients":
            return [f'{c["address"]} {c["class"]} {json.dumps(c["title"], ensure_ascii=False)}' for c in json.loads(text) if c["mapped"]]
        if name == "layers":
            return [l["namespace"] for m in json.loads(text).values() for level in m["levels"].values() for l in level if l["pid"] != -1]
        if name == "plugins":
            # Membership is retained in raw JSON; this class is enablement.
            # An absent disabled fixture has the same enablement as a retained one.
            return [key + "=" + str(enabled).lower() for key, enabled in plugin_profile(text).items()]
        if name == "options":
            return options(directory, text)
        if name == "shim":
            return [f"{line[42:].removeprefix('./')} {line[:12]}" for line in text.splitlines()]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None
    return text.splitlines()

# One getoption reply per name, a JSON document or the text Hyprland
# answers for an option it cannot print, such as `invalid type (internal
# error)`; replies are apart by blank lines. No names, or a reply count
# that differs, is an unreadable reading.
def options(directory, text):
    with open(os.path.join(directory, "options.names")) as f:
        names = f.read().split()
    replies = re.split(r"\n{2,}", text.strip())
    if not names or len(replies) != len(names):
        raise ValueError("options: replies=%d names=%d" % (len(replies), len(names)))
    out = []
    for name, reply in zip(names, replies):
        try:
            value = {k: v for k, v in json.loads(reply).items() if k not in ("option", "set")}
            out.append(f"{name}={json.dumps(value, sort_keys=True)}")
        except ValueError:
            out.append(f"{name}={reply}")
    return out

def render(added, gone):
    words = [("+", v) for v in sorted(added.elements())] + [("-", v) for v in sorted(gone.elements())]
    shown = [sign + (v if len(v) <= CUT else v[:CUT] + "...") for sign, v in words[:SHOWN]]
    if len(words) > SHOWN:
        shown.append(f"and {len(words) - SHOWN} more")
    return " ".join(shown).replace("\t", " ")

declared = set()
with open(row_file) as f:
    for line in f:
        if not line.startswith("#"):
            break
        found = re.match(r"#\s*leaves:(.*)$", line)
        for word in found.group(1).split() if found else []:
            if word in classes:
                declared.add(word)
            else:
                print(f"refused\t{word}\t")
for name in classes:
    before, after = items(start, name), items(end, name)
    for side, reading in (("start", before), ("end", after)):
        if reading is None:
            print(f"unreadable\t{name}\t{side}")
    if before is None or after is None:
        continue
    if name == "bus-names":
        before, after = (dict(line.split(" ", 1) for line in reading) for reading in (before, after))
        names = before.keys() | after.keys()
        before, after = ([f'{key} {reading.get(key, "none")}' for key in names] for reading in (before, after))
    if name == "plugins":
        before, after = (dict(line.rsplit("=", 1) for line in reading) for reading in (before, after))
        names = before.keys() | after.keys()
        before, after = ([f'{key}={reading.get(key, "false")}' for key in names] for reading in (before, after))
    added = collections.Counter(after) - collections.Counter(before)
    gone = collections.Counter(before) - collections.Counter(after)
    if added or gone:
        print(f'{"declared" if name in declared else "leaves"}\t{name}\t{render(added, gone)}')
PY
}
