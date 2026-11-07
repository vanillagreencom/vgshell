#!/usr/bin/env bash
# The vgs.local-sync `log` floating TUI, shell/plugins/vgs.local-sync/tui/
# log.sh, under a PATH of stand-ins: one service unit's name reaches
# journalctl as one argv word after -u, with the newest 200 lines and no
# pager, and anything but one service unit's name, a glob, a word with a
# space, a second argument, another unit type or a non-ASCII letter under a
# UTF-8 locale included, ends with exit 2 and starts no journalctl. No run
# reaches the host's journal: journalctl is a stand-in that records its
# argv.
#
# The control at the end edits a copy of the script, dropping the unit
# judge, and requires a refusal case to fail on it.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
script="$repo/shell/plugins/vgs.local-sync/tui/log.sh"
TMP_ROOT="$(mktemp -d)" || { echo "test-local-sync-tui: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-local-sync-tui: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-local-sync-tui: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
for tool in python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-local-sync-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

tools="$TMP_ROOT/tools"
mkdir -p "$tools"
for tool in bash python3 cat; do ln -s -- "$(command -v "$tool")" "$tools/$tool"; done
cat >"$tools/journalctl" <<SH
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$TMP_ROOT/calls"
SH
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' >"$tools/gum"
chmod 755 "$tools/journalctl" "$tools/gum"

# run SCRIPT ARGS...: SCRIPT with ARGS under a UTF-8 locale, no terminal
# and a PATH of the stand-ins; the exit status in $status, the recorded
# journalctl calls in $calls.
run() {
  local file="$1"
  shift
  : >"$TMP_ROOT/calls"
  status=0
  env -i PATH="$tools" HOME="$TMP_ROOT" LANG=C.UTF-8 LC_ALL=C.UTF-8 VGS_TUI_LIB="$repo/bin/lib/tui.sh" \
    bash "$file" "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" </dev/null || status=$?
  calls="$(cat "$TMP_ROOT/calls")"
}
words() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"; }

UNITS=(scribd-brain-backup.service "sync@home:drive_1.service" "-x.service")
case_a_unit_reaches_journalctl_as_one_word() {
  local unit
  for unit in "${UNITS[@]}"; do
    run "$1" "$unit"
    [[ $status == 0 && $calls == "$(words --user -u "$unit" -n 200 --no-pager)" ]] || { detail="unit=$unit"; return 1; }
  done
}
# Each row is one argv, its words separated by a tab.
REFUSED=(
  ""
  "a*.service"
  "a?.service"
  "a[1].service"
  "my sync.service"
  "backup.timer"
  "backup.service.d"
  "é.service"
  $'a.service\nb.service'
  $'a.service\tb.service'
)
case_anything_but_one_service_unit_is_refused() {
  local row
  local -a argv
  run "$1"
  [[ $status == 2 && -z $calls ]] || { detail="argv=none"; return 1; }
  for row in "${REFUSED[@]}"; do
    IFS=$'\t' read -r -a argv <<<"$row"
    [[ ${#argv[@]} -gt 0 ]] || argv=("")
    [[ $row != *$'\n'* ]] || argv=("$row")
    run "$1" "${argv[@]}"
    [[ $status == 2 && -z $calls ]] || { detail="argv=$(words "${argv[@]}")"; return 1; }
  done
}

CASES=(case_a_unit_reaches_journalctl_as_one_word case_anything_but_one_service_unit_is_refused)
for case in "${CASES[@]}"; do
  detail="" status="" calls=""
  if "$case" "$script"; then ok "${case#case_}"; else fail "${case#case_}: $detail status=$status calls=[${calls//$'\n'/;}]"; fi
done

copy="$TMP_ROOT/copy.sh"
if ! python3 - "$script" "$copy" <<'PY'
import sys
text = open(sys.argv[1]).read()
line = 'one_unit() { local LC_ALL=C; (( $# == 1 )) && [[ $1 =~ ^[A-Za-z0-9:_.@-]+\\.service$ ]]; }\n'
judge = text.count(line)
if judge != 1:
    sys.exit("control line occurs %d times" % judge)
open(sys.argv[2], "w").write(text.replace(line, 'one_unit() { true; }\n'))
PY
then
  fail "control: its line must occur once"
elif case_anything_but_one_service_unit_is_refused "$copy"; then
  fail "control: passed on a copy without the unit judge"
else
  ok "control: a copy without the unit judge fails the refusal case"
fi

if [[ $failures -gt 0 ]]; then
  printf 'test-local-sync-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-local-sync-tui: ok cases=%d controls=1\n' "${#CASES[@]}"
