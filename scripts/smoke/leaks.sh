# Sourced by harness.sh: the leak check smoke_row runs over every row. The
# state a row hands to the rows after it must equal the state it found, in
# each class below, or a scoped run that holds the row and the full run on
# main read different states and one of them fails (VGS-877). A row that
# leaves a class on purpose declares it in its own leading comment block,
# `# leaves: CLASS [CLASS...]`; the check skips that class for that row and
# prints what the row left. The check reports only: it closes, restores and
# resets nothing.
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
leak_classes=(clients focus submap layers options variables shell shim)
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
  hypr -j clients >"$1/clients" 2>/dev/null || rm -f -- "$1/clients"
  active_window >"$1/focus" 2>/dev/null || rm -f -- "$1/focus"
  key_submap >"$1/submap" 2>/dev/null || rm -f -- "$1/submap"
  printf 'unavailable:no-probe\n' >"$1/layers.probe"
  printf '%s\n' "${shell_qs_pid:-}" >"$1/layers.pid"
  printf 'unavailable:no-layers\n' >"$1/layers.raw"
  if leak_layers_rest "$1"; then
    if hypr -j layers >"$1/layers.raw" 2>/dev/null; then cp -- "$1/layers.raw" "$1/layers"; else rm -f -- "$1/layers"; fi
  else
    rm -f -- "$1/layers"
  fi
  leak_options "$1" 2>/dev/null || rm -f -- "$1/options"
  for name in "${leak_start_variables[@]}"; do
    declare -p "$name" 2>/dev/null || printf '%s unset\n' "$name"
  done >"$1/variables"
  leak_shell >"$1/shell"
  (cd -- "$shim" && find -L . -mindepth 1 -type f -executable -print0 | sort -z | xargs -0r sha1sum --) >"$1/shim" 2>/dev/null || rm -f -- "$1/shim"
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
  leak_reading
  leak_starts+=("$leak_last")
}

# leak_row_end NAME DIR: the row's end reading against its start: one fail
# per class it leaves, `NAME: leaves CLASS: +VALUE -VALUE`, and one per
# class a reading could not read.
leak_row_end() { # NAME DIR
  local start="${leak_starts[-1]}" verdicts verdict class values layer_failed=false
  unset 'leak_starts[-1]'
  leak_reading
  if ! verdicts="$(leak_judge "$2/$1.sh" "$start" "$leak_last")"; then
    fail "$1: leak-check judge=failed start=$start end=$leak_last"
    return 0
  fi
  while IFS=$'\t' read -r verdict class values; do
    case "$verdict" in
      leaves) fail "$1: leaves $class: $values" ;;
      declared) ok "$1: leaves $class, as its header declares: $values" ;;
      unreadable) fail "$1: leak-check reading=unreadable class=$class at=$values start=$start end=$leak_last$(leak_unsettled "$class" "$values" "$start")" ;;
      refused) fail "$1: leak-check refused: leaves=$class reason=unknown-class" ;;
    esac
    if [[ $class == layers && ( $verdict == leaves || $verdict == unreadable ) ]]; then
      layer_failed=true
      leak_layer_diagnostics "$start"
      leak_layer_diagnostics "$leak_last"
    fi
  done <<<"$verdicts"
  if [[ $layer_failed == false ]]; then
    rm -f -- "$start/layers.raw" "$start/layers.probe" "$start/layers.pid" "$leak_last/layers.raw" "$leak_last/layers.probe" "$leak_last/layers.pid"
  fi
}

# The recorder owns historical PID/instance/stop joins. This report cannot
# affect the namespace-only settlement or multiset verdict above.
leak_layer_diagnostics() { # DIR
  local report
  if report="$(display_record_call layer-reading "$1" "$(<"$1/layers.pid")")"; then
    printf '        layer-owner %s\n' "$report"
  else
    printf '        layer-owner unavailable raw=%s/layers.raw probe=%s/layers.probe\n' "$1" "$1"
  fi
}

# leak_unsettled CLASS SIDE START: ` unsettled=<state>` when the reading
# on SIDE, START's or leak_last's, left CLASS unread because its layers
# did not come to rest; nothing otherwise.
leak_unsettled() { # CLASS SIDE START
  local dir="$leak_last" state
  [[ $2 != start ]] || dir="$3"
  if [[ -f $dir/$1.unsettled ]] && state="$(cat -- "$dir/$1.unsettled")"; then printf ' unsettled=%s' "$state"; fi
}

# leak_judge ROW_FILE START END: one tab-separated line per finding:
# `leaves CLASS VALUES`, `declared CLASS VALUES`, `unreadable CLASS
# start|end` or `refused WORD` for a `# leaves:` word that names no class.
# A class unreadable at either end is not compared.
leak_judge() { # ROW_FILE START END
  python3 - "$@" "${leak_classes[@]}" <<'PY'
import collections, json, os, re, sys
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
    added = collections.Counter(after) - collections.Counter(before)
    gone = collections.Counter(before) - collections.Counter(after)
    if added or gone:
        print(f'{"declared" if name in declared else "leaves"}\t{name}\t{render(added, gone)}')
PY
}
