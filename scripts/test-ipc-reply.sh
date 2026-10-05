#!/usr/bin/env bash
# Controls for bin/lib/ipc-reply.sh, the one judge of Quickshell 0.3.1
# client failure lines and the one page loop that bin/vgshell and the smoke
# harness share. The table pins each failure form's reason key and the
# replies that are no failure. Each rule kind of the judge, `contains`,
# `exact` and `prefix`, has a must-fail control on a copy of the library,
# and a copy with a row of unknown kind pins the judge's internal error.
# The detector table pins which replies vgs_ipc_paged_id reads as paged,
# and the page table pins vgs_ipc_pages over a stand-in FETCH: the
# documents it reassembles and the reason of each page it refuses. Each
# rule of both has its own must-fail control on a copy. The last-line
# reader has its own table, a control that reads the first line, and a
# bound on a 256 KiB one-line reply, with a control that reads it by
# `##*$'\n'`.
set -euo pipefail

TMP_ROOT="$(mktemp -d)" || { echo "test-ipc-reply: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-ipc-reply: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-ipc-reply: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

repo="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)" || { echo "test-ipc-reply: repo=resolve-failed" >&2; exit 1; }
lib="$repo/bin/lib/ipc-reply.sh"

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

esc=$'\e'
# NAME|LINE|WANT, WANT `-` for a line that is no failure.
cases=(
  "ANSI ERROR line|$esc[31m ERROR$esc[97m quickshell.ipc$esc[0m: Error occurred while waiting for response.|client-error"
  "plain ERROR line|ERROR quickshell.ipc: Error occurred while waiting for response.|client-error"
  "function not found|Function not found.|function-not-found"
  "target not found|Target not found.|target-not-found"
  "not ready|Not ready to accept queries yet.|not-ready"
  "target required|Target required to send message.|target-required"
  "function required|Function required to send message.|function-required"
  "too many arguments|Too many arguments provided, expected 2.|too-many-arguments"
  "too few arguments|Too few arguments provided, expected 2.|too-few-arguments"
  "unparseable argument|Unable to parse argument 2 as int.|unparseable-argument"
  "function definition|Function definition: shell.ping()|arguments"
  "ok reply|ok|-"
  "json reply|{\"a\":1}|-"
  "paged reply|paged=7|-"
  "info log line|INFO quickshell.ipc: connected|-"
  "a reply quoting a failure text|said Function not found.|-"
  "empty line||-"
)

# check_cases LIB: run every case against LIB in a subshell and print one
# line per mismatch; exit 1 when any case mismatched, 3 when LIB does not
# load or defines no judge, so a broken mutant never reads as a red table.
check_cases() { # LIB
  (
    # shellcheck source=../bin/lib/ipc-reply.sh
    source "$1" || { echo "load-failed: $1"; exit 3; }
    declare -F vgs_ipc_reply_failure >/dev/null || { echo "no-judge: $1"; exit 3; }
    bad=0
    for row in "${cases[@]}"; do
      name="${row%%|*}"; rest="${row#*|}"; line="${rest%|*}"; want="${rest##*|}"
      status=0
      got="$(vgs_ipc_reply_failure "$line")" || status=$?
      if [[ $want == - ]]; then
        [[ $status -eq 1 && -z $got ]] && continue
      else
        [[ $status -eq 0 && $got == "$want" ]] && continue
      fi
      printf '%s: got=[%s] status=%s want=%s\n' "$name" "$got" "$status" "$want"
      bad=1
    done
    exit "$bad"
  )
}

# mutant NAME NEEDLE REPLACEMENT: a copy of the library with NEEDLE, which
# must occur exactly once, replaced; prints the copy's path.
mutant() { # NAME NEEDLE REPLACEMENT
  local copy="$TMP_ROOT/$1.sh"
  NEEDLE="$2" REPLACEMENT="$3" python3 - "$lib" "$copy" <<'PY'
import os
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
needle = os.environ["NEEDLE"]
count = source.count(needle)
if count != 1:
    raise SystemExit(f"test-ipc-reply: needle-count={count} needle={needle!r}")
changed = source.replace(needle, os.environ["REPLACEMENT"])
if changed == source:
    raise SystemExit("test-ipc-reply: mutant=unchanged")
pathlib.Path(sys.argv[2]).write_text(changed)
PY
  printf '%s\n' "$copy"
}

echo "=== the table ==="
if report="$(check_cases "$lib")"; then
  ok "every failure form has its key and every reply reads as no failure (${#cases[@]} cases)"
else
  fail "the judge disagrees with the table:"
  printf '        %s\n' "$report"
fi

echo "=== must-fail controls ==="
# Each mutant keeps the rule's text and removes the rule's behaviour. A
# control passes only on a table mismatch, exit 1, never on a copy that
# does not load. Fields are tab-separated: the needles hold `|`.
controls=(
  $'contains rule\t      contains) [[ $stripped == *"$text"* ]] || continue ;;\t      contains) continue ;;'
  $'exact rule\t      exact) [[ $stripped == "$text" ]] || continue ;;\t      exact) continue ;;'
  $'prefix rule\t      prefix) [[ $stripped == "$text"* ]] || continue ;;\t      prefix) continue ;;'
)
for row in "${controls[@]}"; do
  IFS=$'\t' read -r name needle replacement <<<"$row" || { fail "control row unreadable: [$row]"; continue; }
  copy="$(mutant "${name// /-}" "$needle" "$replacement")" || { fail "control: $name: the mutant could not be written"; continue; }
  status=0
  report="$(check_cases "$copy")" || status=$?
  if [[ $status -eq 1 ]]; then
    ok "control: a judge without its $name turns the table red"
  else
    fail "control: a judge without its $name: status=$status report=[$report]"
  fi
done

copy="$(mutant unknown-kind "'client-error|contains|ERROR quickshell.ipc'" "'client-error|contain|ERROR quickshell.ipc'")" || { echo "test-ipc-reply: mutant=unknown-kind" >&2; exit 1; }
set +e
out="$(source "$copy"; vgs_ipc_reply_failure ok 2>"$TMP_ROOT/err")"
status=$?
set -e
err="$(cat -- "$TMP_ROOT/err")" || { echo "test-ipc-reply: read=err" >&2; exit 1; }
if [[ $status -eq 2 && -z $out && $err == "ipc-reply: kind=contain row=client-error" ]]; then
  ok "a table row of unknown kind is an internal error, exit 2"
else
  fail "unknown kind: status=$status out=[$out] err=[$err]"
fi

echo "=== the paged-reply detector ==="
# NAME|TARGET|LINE|WANT, WANT the id or `-` for a whole reply.
detect_cases=(
  "a shell reply|shell|paged=12|12"
  "a smoke probe reply|smoke|paged=3|3"
  "a plugin target's look-alike|acme.probe|paged=3|-"
  "a marker with no id|shell|paged=|-"
  "a marker with a suffix|shell|paged=3 more|-"
  "a document|shell|{\"paged\":3}|-"
)
check_detect() { # LIB
  (
    # shellcheck source=../bin/lib/ipc-reply.sh
    source "$1" || { echo "load-failed: $1"; exit 3; }
    declare -F vgs_ipc_paged_id >/dev/null || { echo "no-detector: $1"; exit 3; }
    bad=0
    for row in "${detect_cases[@]}"; do
      IFS='|' read -r name target line want <<<"$row"
      status=0
      vgs_ipc_paged_id "$target" "$line" || status=$?
      if [[ $want == - ]]; then
        [[ $status -eq 1 && -z $vgs_ipc_paged ]] && continue
      else
        [[ $status -eq 0 && $vgs_ipc_paged == "$want" ]] && continue
      fi
      printf '%s: status=%s id=[%s] want=%s\n' "$name" "$status" "$vgs_ipc_paged" "$want"
      bad=1
    done
    exit "$bad"
  )
}
if report="$(check_detect "$lib")"; then
  ok "the detector reads each paged reply and no other (${#detect_cases[@]} cases)"
else
  fail "the detector disagrees with the table:"
  printf '        %s\n' "$report"
fi
detect_controls=(
  $'the marker match\t  [[ $2 =~ ^paged=([0-9]+)$ ]] || return 1\t  [[ $2 =~ ^paged=([0-9]*) ]] || return 1'
  $'the paging target set\t    if [[ $1 == "$target" ]]; then\t    if true; then'
)
for row in "${detect_controls[@]}"; do
  IFS=$'\t' read -r name needle replacement <<<"$row" || { fail "control row unreadable: [$row]"; continue; }
  copy="$(mutant "detect-${name// /-}" "$needle" "$replacement")" || { fail "control: $name: the mutant could not be written"; continue; }
  status=0
  report="$(check_detect "$copy")" || status=$?
  if [[ $status -eq 1 ]]; then
    ok "control: a detector without $name turns the table red"
  else
    fail "control: a detector without $name: status=$status report=[$report]"
  fi
done

echo "=== the page loop ==="
# The page replies a stand-in shell holds, by `ID.INDEX`; FETCH answers
# `absent` for any other, as shell/Core/IpcPages.qml does for a dropped
# reply, and fails with status 5 for id `fail`.
declare -A stub_pages=(
  [two.0]='2 {"a":' [two.1]='2 1}'
  [one.0]='1 x y'
  [gone.0]='2 ab'
  [range.0]='refused: page=0 pages=0'
  [header.0]='garbage'
  [count.0]='0 x'
  [changed.0]='2 a' [changed.1]='3 b'
)
stub_fetch() { # ID INDEX
  [[ $1 == fail ]] && return 5
  vgs_ipc_page="${stub_pages[$1.$2]-absent}"
}
# NAME|ID|STATUS|WANT, WANT the document on status 0, else the failure.
page_cases=(
  "two pages reassemble|two|0|{\"a\":1}"
  "a slice keeps its spaces|one|0|x y"
  "a page the shell no longer keeps|gone|1|absent page=1"
  "an index out of range|range|1|refused page=0"
  "a line with no page header|header|1|bad-header page=0"
  "a page count of zero|count|1|bad-count page=0"
  "a page count that changes|changed|1|count-changed page=1"
  "a fetch that fails|fail|2|fetch page=0 status=5"
)

# check_pages LIB: every page case against LIB in a subshell; exit 1 on a
# mismatch, 3 when LIB does not load or defines no page loop.
check_pages() { # LIB
  (
    # shellcheck source=../bin/lib/ipc-reply.sh
    source "$1" || { echo "load-failed: $1"; exit 3; }
    declare -F vgs_ipc_pages >/dev/null || { echo "no-page-loop: $1"; exit 3; }
    bad=0
    for row in "${page_cases[@]}"; do
      IFS='|' read -r name id want_status want <<<"$row"
      status=0
      vgs_ipc_pages stub_fetch "$id" || status=$?
      if ((status == 0)); then got="$vgs_ipc_document"; else got="$vgs_ipc_page_failure"; fi
      [[ $status == "$want_status" && $got == "$want" ]] && continue
      printf '%s: status=%s got=[%s] want=%s [%s]\n' "$name" "$status" "$got" "$want_status" "$want"
      bad=1
    done
    exit "$bad"
  )
}

if report="$(check_pages "$lib")"; then
  ok "every paged reply reassembles and every bad page has its reason (${#page_cases[@]} cases)"
else
  fail "the page loop disagrees with the table:"
  printf '        %s\n' "$report"
fi

page_controls=(
  $'the append of every page\t    vgs_ipc_document+="$slice"\t    ((index)) || vgs_ipc_document+="$slice"'
  $'the stop after the last page\t    ((index < pages)) || return 0\t    ((index <= pages)) || return 0'
  $'the header rule\t    if [[ ! $vgs_ipc_page =~ ^([0-9]+)\\ (.*)$ ]]; then\t    if [[ ! $vgs_ipc_page =~ ^([0-9]*)\\ ?(.*)$ ]]; then'
  $'the absent rule\t    if [[ $vgs_ipc_page == absent ]]; then\t    if false; then'
  $'the refused rule\t    if [[ $vgs_ipc_page == "refused: "* ]]; then\t    if false; then'
  $'the count floor\t      if [[ ! $count =~ ^[1-9][0-9]*$ ]]; then\t      if false; then'
  $'the count-changed rule\t    elif [[ $count != "$pages" ]]; then\t    elif false; then'
  $'the fetch failure rule\t    if ((status)); then\t    if false; then'
)
for row in "${page_controls[@]}"; do
  IFS=$'\t' read -r name needle replacement <<<"$row" || { fail "control row unreadable: [$row]"; continue; }
  copy="$(mutant "pages-${name// /-}" "$needle" "$replacement")" || { fail "control: $name: the mutant could not be written"; continue; }
  status=0
  report="$(check_pages "$copy")" || status=$?
  if [[ $status -eq 1 ]]; then
    ok "control: a page loop without $name turns the table red"
  else
    fail "control: a page loop without $name: status=$status report=[$report]"
  fi
done

echo "=== the last line ==="
nl=$'\n'
# NAME|TEXT|WANT, a `~` in TEXT standing for a newline.
last_cases=(
  "a one-line reply|ok|ok"
  "a log line ahead of the reply|WARN qml: late~{\"a\":1}|{\"a\":1}"
  "two log lines ahead of the reply|one~two~paged=7|paged=7"
  "an empty reply||"
  "a text that ends in a newline|ok~|"
  "an empty line ahead of the reply|~ok|ok"
)
# check_last LIB: as check_cases, over the last-line table.
check_last() { # LIB
  (
    # shellcheck source=../bin/lib/ipc-reply.sh
    source "$1" || { echo "load-failed: $1"; exit 3; }
    declare -F vgs_ipc_last_line_into >/dev/null || { echo "no-reader: $1"; exit 3; }
    bad=0
    for row in "${last_cases[@]}"; do
      name="${row%%|*}"; rest="${row#*|}"; text="${rest%|*}"; want="${rest##*|}"
      vgs_ipc_last_line=unset
      vgs_ipc_last_line_into "${text//\~/$nl}"
      [[ $vgs_ipc_last_line == "$want" ]] && continue
      printf '%s: got=[%s] want=[%s]\n' "$name" "$vgs_ipc_last_line" "$want"
      bad=1
    done
    exit "$bad"
  )
}
if report="$(check_last "$lib")"; then
  ok "the reader answers the text after the last newline (${#last_cases[@]} cases)"
else
  fail "the last-line reader disagrees with its table:"
  printf '        %s\n' "$report"
fi
copy="$(mutant first-line '  head="${1%$'"'\\n'"'*}"' '  head="${1%%$'"'\\n'"'*}"')" || { echo "test-ipc-reply: mutant=first-line" >&2; exit 1; }
status=0
report="$(check_last "$copy")" || status=$?
if [[ $status -eq 1 ]]; then
  ok "control: a reader that cuts at the first newline turns the table red"
else
  fail "control: a reader that cuts at the first newline: status=$status report=[$report]"
fi
# The smoke pages its replies at 32 KiB and reads thousands of them, so the
# reader's time is the smoke's time. The bound is real time, as the cost
# is: the reader took 3 ms for this reply and the pattern form 12.2 s
# (bash 5.3.20, host cachy, 2026-10-04, load average 8), and timeout
# ends the control at the bound.
last_bound_s=3
# big_last LIB: 0 when LIB reads a 256 KiB one-line reply whole within
# last_bound_s, 124 when the bound ended it, 1 for a wrong answer.
big_last() { # LIB
  timeout "$last_bound_s" bash -c '
    source "$1" || exit 3
    printf -v big "%262144s" ""
    vgs_ipc_last_line_into "$big"
    [[ ${#vgs_ipc_last_line} -eq 262144 ]]' _ "$1"
}
status=0
big_last "$lib" || status=$?
if [[ $status -eq 0 ]]; then
  ok "a 256 KiB one-line reply is read within ${last_bound_s}s"
else
  fail "a 256 KiB one-line reply: status=$status bound=${last_bound_s}s"
fi
copy="$(mutant every-prefix $'  if [[ $1 != *$\'\\n\'* ]]; then\n    vgs_ipc_last_line="$1"\n    return 0\n  fi\n' $'  vgs_ipc_last_line="${1##*$\'\\n\'}"\n  return 0\n')" || { echo "test-ipc-reply: mutant=every-prefix" >&2; exit 1; }
status=0
big_last "$copy" || status=$?
if [[ $status -eq 124 ]]; then
  ok "control: a reader that matches every prefix is ended at the bound"
else
  fail "control: a reader that matches every prefix: status=$status"
fi
if report="$(check_last "$copy")"; then
  ok "the every-prefix control answers the table, so only its time is its defect"
else
  fail "the every-prefix control disagrees with the table: $report"
fi

if [[ $failures -gt 0 ]]; then echo "test-ipc-reply: failed=$failures"; exit 1; fi
echo "test-ipc-reply: ok"
