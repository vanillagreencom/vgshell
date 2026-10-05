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
#   namespace each;
# - options: every Hyprland option `hyprctl -j descriptions` lists, with
#   its live value from `hyprctl -j getoption`;
# - variables: leak_start_variables, each by `declare -p`;
# - shell: devices_guard's reading of the running shell, shell_qs_pid,
#   `no-shell` with no pid and `environ=unreadable` for a dead shell;
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
leak_reading() {
  leak_seq=$((leak_seq + 1))
  leak_last="$sandbox/leaks/$BASHPID-$leak_seq"
  leak_read "$leak_last"
}

# leak_read DIR: one file per class; a class that cannot be read has no file.
leak_read() { # DIR
  local name
  mkdir -p -- "$1"
  hypr -j clients >"$1/clients" 2>/dev/null || rm -f -- "$1/clients"
  active_window >"$1/focus" 2>/dev/null || rm -f -- "$1/focus"
  key_submap >"$1/submap" 2>/dev/null || rm -f -- "$1/submap"
  hypr -j layers >"$1/layers" 2>/dev/null || rm -f -- "$1/layers"
  leak_options "$1" 2>/dev/null || rm -f -- "$1/options"
  for name in "${leak_start_variables[@]}"; do
    declare -p "$name" 2>/dev/null || printf '%s unset\n' "$name"
  done >"$1/variables"
  leak_shell >"$1/shell"
  (cd -- "$shim" && find -L . -mindepth 1 -type f -executable -print0 | sort -z | xargs -0r sha1sum --) >"$1/shim" 2>/dev/null || rm -f -- "$1/shim"
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
    echo environ=unreadable
  fi
}

leak_row_start() {
  leak_reading
  leak_starts+=("$leak_last")
}

# leak_row_end NAME DIR: the row's end reading against its start: one fail
# per class it leaves, `NAME: leaves CLASS: +VALUE -VALUE`, and one per
# class a reading could not read.
leak_row_end() { # NAME DIR
  local start="${leak_starts[-1]}" verdicts verdict class values
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
      unreadable) fail "$1: leak-check reading=unreadable class=$class at=$values start=$start end=$leak_last" ;;
      refused) fail "$1: leak-check refused: leaves=$class reason=unknown-class" ;;
    esac
  done <<<"$verdicts"
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
