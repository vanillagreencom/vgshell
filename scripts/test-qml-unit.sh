#!/usr/bin/env bash
# Controls for scripts/qml-unit.sh. Two rows pin the runner's arguments:
# a missing qmltestrunner is not a pass, and an unknown argument is
# refused. A table plants one test file per rule of the runner's log check
# and pins the exit and the line each prints. One row runs two shader tests
# at once under a stand-in xvfb-run and requires the second to start only
# once the first has ended, which a copy of the runner without its display
# lock fails. One row requires every qmltestrunner start, offscreen and
# shader, to get the QV4_ Env pragmas of shell/shell.qml, which a copy of
# the runner that does not apply them fails, and an Env pragma with no `=`
# to be refused. The final count requires no qml-unit.* folder in the
# world's TMPDIR; a copy without its exit trap leaves one under a case's
# own TMPDIR.
#
# Exit 0 when every row holds, 1 otherwise, 77 when the runner could not
# measure: qmltestrunner is absent, or scripts/smoke/gpu-fence.sh could not
# make or prove its namespace. The runner's own not-measured lines follow
# `test-qml-unit: status=not-measured runner-exit=77`.
#
# The rows run side by side, at most VGS_VALIDATE_JOBS at once, a positive
# integer (unset or empty: nproc), and print in their order; another value
# is refused with exit 2, `test-qml-unit: refused: jobs=<value>`.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
runner="$repo/scripts/qml-unit.sh"
if [[ $# -ne 0 ]]; then
  printf 'test-qml-unit: refused: argument=%s\n' "$1" >&2
  exit 2
fi
jobs_max="${VGS_VALIDATE_JOBS:-}"
if [[ -z $jobs_max ]]; then
  jobs_max="$(nproc)"
elif [[ ! $jobs_max =~ ^[1-9][0-9]*$ ]]; then
  printf 'test-qml-unit: refused: jobs=%s\n' "$jobs_max" >&2
  exit 2
fi

"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" env \
  VGS_VALIDATE_JOBS="$jobs_max" "$self" "$@"

probe_status=0
out="$("$runner" --tests "$repo/scripts/qml-tests" "$repo/scripts/qml-tests/tst_module.qml" 2>&1)" || probe_status=$?
if [[ $probe_status -eq 77 ]]; then
  echo "test-qml-unit: status=not-measured runner-exit=77"
  grep -F -- 'status=not-measured' <<<"$out" || true
  exit 77
fi
if [[ $probe_status -ne 0 ]]; then
  echo "test-qml-unit: the module test does not pass on the shipped tree:"
  printf '%s\n' "$out" | sed -n '/^qml-unit: failed file=/p; /FAIL!/,/Loc:/p'
  printf '%s\n' "$out" | tail -n 20
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

count_qml_unit_roots() {
  find "$1" -mindepth 1 -maxdepth 1 -type d -name 'qml-unit.*' -printf '.\n' | wc -l
}

# One fresh copy of the module under test at $1.
fresh() {
  rm -rf -- "$1"
  cp -R -- "$repo/shell/Ui" "$1"
}

# An unchanged copy of the module, which the missing-runner case reads.
copy="$tmp/ui"
fresh "$copy"

# Rows: label | name of the planted tst_<name>.qml | the runner's exit |
# the line it must print | the file's lines after the planted head, whose
# body starts at line 6; printf %b expands the \n.
planted_head='import QtQuick\nimport QtTest\nTestCase {\n    id: planted\n    name: "planted"\n'
logs=(
  "an unexpected console.error fails|error|1|qml-unit: unexpected-log file=tst_error.qml line=QCRITICAL: qmltestrunner::planted::test_a() critical: qml: planted log|    function test_a() { console.error(\"planted log\"); }\n"
  "an unexpected console.warn fails|warn|1|qml-unit: unexpected-log file=tst_warn.qml line=QWARN  : qmltestrunner::planted::test_a() warning: qml: planted log|    function test_a() { console.warn(\"planted log\"); }\n"
  "a declared log passes|declared|0|qml-unit: ok files=1|    // expected-log: planted log -- the row plants it\n    function test_a() { console.error(\"planted log\"); }\n"
  "a declaration that matches nothing fails|stale|1|qml-unit: expected-log unmatched file=tst_stale.qml line=6 message=planted log|    // expected-log: planted log -- the row plants it\n    function test_a() { verify(true); }\n"
  "a declaration covers no other function|other|1|qml-unit: unexpected-log file=tst_other.qml line=QCRITICAL: qmltestrunner::planted::test_b() critical: qml: planted log|    // expected-log: planted log -- the row plants it\n    function test_a() { console.error(\"planted log\"); }\n    function test_b() { console.error(\"planted log\"); }\n"
  "a declaration with no reason is refused|noreason|2|qml-unit: refused: expected-log=no-reason file=tst_noreason.qml line=6|    // expected-log: planted log\n    function test_a() { console.error(\"planted log\"); }\n"
  "a declaration with no function under it is refused|nofunction|2|qml-unit: refused: expected-log=no-function file=tst_nofunction.qml line=6|    // expected-log: planted log -- the row plants it\n    property int n: 0\n    function test_a() { console.error(\"planted log\"); }\n"
  "a log at load fails|load|1|qml-unit: unexpected-log file=tst_load.qml line=critical: qml: planted log|    Component.onCompleted: console.error(\"planted log\")\n    function test_a() { verify(true); }\n"
  "a declaration does not excuse a script error|script|1|qml-unit: warnings file=tst_script.qml|    // expected-log: ReferenceError -- the row plants it\n    function test_a() { Qt.createQmlObject(\"import QtQuick; Item { property int n: noSuchName.x }\", planted); }\n"
  "a bare waitForRendering fails|barewait|1|qml-unit: bare-wait file=tst_barewait.qml line=6|    function test_a() { waitForRendering(planted); }\n"
  "a waitForRendering named in a comment passes|barecomment|0|qml-unit: ok files=1|    // waitForRendering waits for a new frame swap\n    function test_a() { verify(true); }\n"
  "the settled-window test may call waitForRendering|rendered_frame|0|qml-unit: ok files=1|    function test_the_rendered_wait_answers_on_a_settled_window() { verify(typeof waitForRendering === \"function\"); }\n"
  "the settled-window excuse covers no other function|rendered_frame|1|qml-unit: bare-wait file=tst_rendered_frame.qml line=7|    function test_the_rendered_wait_answers_on_a_settled_window() { verify(true); }\n    function test_b() { verify(typeof waitForRendering === \"function\"); }\n"
  "the settled-window excuse covers no other file|settled|1|qml-unit: bare-wait file=tst_settled.qml line=6|    function test_the_rendered_wait_answers_on_a_settled_window() { verify(typeof waitForRendering === \"function\"); }\n"
)
mkdir -p "$tmp/logs"
log_case() { # INDEX
  local label name want_status want_line body got_status out
  IFS='|' read -r label name want_status want_line body <<<"${logs[$1]}"
  mkdir -p "$tmp/logs/$1"
  printf '%b%b}\n' "$planted_head" "$body" >"$tmp/logs/$1/tst_$name.qml"
  got_status=0
  out="$("$runner" --tests "$repo/scripts/qml-tests" "$tmp/logs/$1/tst_$name.qml" 2>&1)" || got_status=$?
  if [[ $got_status -ne $want_status ]]; then
    fail "$label: exit $got_status, want $want_status"
    printf '%s\n' "$out" | tail -n 20
  elif ! grep -qFx -- "$want_line" <<<"$out"; then
    fail "$label: no line: $want_line"
    printf '%s\n' "$out" | tail -n 20
  else
    ok "$label"
  fi
}

# Two runs of the shader test at once, each under a stand-in xvfb-run that
# waits up to 3 s for a second start: with the display lock the second run
# starts after the first has ended, and a copy of the runner without the
# lock lets both start at once.
xvfb_lock_case() {
  local dir="$tmp/xvfb-lock" tree="$tmp/xvfb-lock/tree" run want order a b
  mkdir -p -- "$dir/bin" "$tree/scripts"
  printf '#!/bin/sh\n' | tee "$dir/bin/Xvfb" >"$dir/bin/xauth"
  cat >"$dir/bin/xvfb-run" <<'SH'
#!/bin/sh
echo "start $$" >>"$XVFB_LOCK_LOG"
i=0
while [ "$(grep -c '^start ' "$XVFB_LOCK_LOG")" -lt 2 ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
echo "end $$" >>"$XVFB_LOCK_LOG"
SH
  chmod +x "$dir/bin/Xvfb" "$dir/bin/xauth" "$dir/bin/xvfb-run"
  printf 'import QtTest\nTestCase { name: "lock" }\n' >"$dir/tst_notification_scroll.qml"
  ln -s -- "$repo/shell" "$tree/shell"
  ln -s -- "$repo/scripts/smoke" "$tree/scripts/smoke"
  python3 - "$runner" "$tree/scripts/qml-unit.sh" <<'PY'
import sys
source, copy = sys.argv[1:]
text = open(source, encoding="utf-8").read()
lock = "flock -o /tmp/.vgshell-qml-unit-xvfb.lock "
assert text.count(lock) == 1, "the runner holds its display lock once"
open(copy, "w", encoding="utf-8").write(text.replace(lock, ""))
PY
  chmod +x "$tree/scripts/qml-unit.sh"
  for run in "$runner" "$tree/scripts/qml-unit.sh"; do
    : >"$dir/log"
    PATH="$dir/bin:$PATH" XVFB_LOCK_LOG="$dir/log" "$run" --tests "$repo/scripts/qml-tests" "$dir/tst_notification_scroll.qml" >"$dir/a.out" 2>&1 &
    a=$!
    PATH="$dir/bin:$PATH" XVFB_LOCK_LOG="$dir/log" "$run" --tests "$repo/scripts/qml-tests" "$dir/tst_notification_scroll.qml" >"$dir/b.out" 2>&1 &
    b=$!
    wait "$a" || true
    wait "$b" || true
    order="$(cut -d' ' -f1 <"$dir/log" | tr '\n' ' ')" || order=unreadable
    if [[ $run == "$runner" ]]; then
      want="start end start end "
      if [[ $order == "$want" ]]; then ok "two shader runs at once take the display one after the other"; else fail "two shader runs at once: xvfb-run order [$order], want [$want]"; tail -n 5 "$dir/a.out" "$dir/b.out"; fi
    elif [[ $order == "start start "* ]]; then
      ok "control: a runner without its display lock lets two runs take it at once"
    else
      fail "control: a runner without its display lock kept two runs apart: xvfb-run order [$order]"
    fi
  done
}

cleanup_case() {
  local dir="$tmp/cleanup" tree="$tmp/cleanup/tree" count status=0
  mkdir -p -- "$dir/tmp" "$tree/scripts"
  ln -s -- "$repo/shell" "$tree/shell"
  ln -s -- "$repo/scripts/smoke" "$tree/scripts/smoke"
  python3 - "$runner" "$tree/scripts/qml-unit.sh" <<'PY'
import sys
source, copy = sys.argv[1:]
text = open(source, encoding="utf-8").read()
trap = 'trap \'rm -rf -- "${root:?}"\' EXIT\n'
assert text.count(trap) == 1, "the runner registers its cleanup once"
open(copy, "w", encoding="utf-8").write(text.replace(trap, ""))
PY
  chmod +x "$tree/scripts/qml-unit.sh"
  printf '#!/bin/sh\nexit 0\n' >"$dir/runner"
  chmod +x "$dir/runner"
  printf 'import QtTest\nTestCase { name: "cleanup" }\n' >"$dir/tst_cleanup.qml"
  TMPDIR="$dir/tmp" QML_UNIT_RUNNER="$dir/runner" "$tree/scripts/qml-unit.sh" --tests "$repo/scripts/qml-tests" "$dir/tst_cleanup.qml" >"$dir/out" 2>&1 || status=$?
  count="$(count_qml_unit_roots "$dir/tmp")" || count=unreadable
  printf 'test-qml-unit: temporary-roots=%s scope=control runner-exit=%s\n' "$count" "$status"
  if [[ $status -eq 0 && $count == 1 ]]; then
    ok "control: a runner without its exit trap leaves its temporary folder"
  else
    fail "control: cleanup count [$count], runner exit $status, want one folder after a successful run"
    tail -n 5 "$dir/out"
  fi
}

# The shell's QV4_ Env pragmas, read here from shell/shell.qml, must reach
# qmltestrunner on the offscreen and the shader path: a stand-in runner
# records the environment each start gets, under a stand-in xvfb-run that
# starts its command. A copy of the runner that does not apply them fails,
# and an Env pragma with no `=` is refused before any start. The shell
# declares one today; the row goes with the last of them.
gc_mode_case() {
  local dir="$tmp/gc-mode" copy_tree="$tmp/gc-mode/copy" refusal="$tmp/gc-mode/refusal"
  local want declared run status got entry
  mkdir -p -- "$dir/bin" "$dir/tests" "$copy_tree/scripts" "$refusal/scripts" "$refusal/shell"
  if ! want="$(python3 - "$repo/shell/shell.qml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
print(" ".join(sorted(f"{m[0]}={m[1]}" for m in re.findall(r"^//@ pragma Env (QV4_\w+) = (\S+)$", text, re.M))))
PY
)" || [[ -z $want ]]; then
    fail "the shell's GC mode: shell/shell.qml holds no QV4_ Env pragma this row reads"
    return 0
  fi
  printf '#!/bin/sh\nenv >"$(mktemp "%s/env.XXXXXX")"\n' "$dir" >"$dir/runner"
  printf '#!/bin/sh\n' | tee "$dir/bin/Xvfb" >"$dir/bin/xauth"
  printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nDISPLAY=:0 XAUTHORITY=/nonexistent exec "$@"\n' >"$dir/bin/xvfb-run"
  chmod +x "$dir/runner" "$dir/bin/Xvfb" "$dir/bin/xauth" "$dir/bin/xvfb-run"
  printf 'import QtTest\nTestCase { name: "gc" }\n' | tee "$dir/tests/tst_gc.qml" >"$dir/tests/tst_notification_scroll.qml"
  ln -s -- "$repo/shell" "$copy_tree/shell"
  ln -s -- "$repo/scripts/smoke" "$copy_tree/scripts/smoke"
  python3 - "$runner" "$copy_tree/scripts/qml-unit.sh" <<'PY'
import sys
source, copy = sys.argv[1:]
text = open(source, encoding="utf-8").read()
applied = ' "${engine_environment[@]}"'
assert text.count(applied) == 1, "the runner applies the engine settings once"
open(copy, "w", encoding="utf-8").write(text.replace(applied, ""))
PY
  cp -- "$runner" "$refusal/scripts/qml-unit.sh"
  chmod +x "$copy_tree/scripts/qml-unit.sh" "$refusal/scripts/qml-unit.sh"
  ln -s -- "$repo/scripts/smoke" "$refusal/scripts/smoke"
  for entry in "$repo/shell"/*; do
    [[ ${entry##*/} == shell.qml ]] || ln -s -- "$entry" "$refusal/shell/${entry##*/}"
  done
  printf '//@ pragma Env QV4_GC_TIMELIMIT 0\nimport QtQuick\n' >"$refusal/shell/shell.qml"
  for run in "$runner" "$copy_tree/scripts/qml-unit.sh"; do
    rm -f -- "${dir:?}"/env.*
    status=0
    PATH="$dir/bin:$PATH" QML_UNIT_RUNNER="$dir/runner" "$run" --tests "$repo/scripts/qml-tests" "$dir/tests/tst_gc.qml" "$dir/tests/tst_notification_scroll.qml" >"$dir/out" 2>&1 || status=$?
    # One line per start: the path it took, then its QV4_ variables.
    got="$(for entry in "$dir"/env.*; do
      [[ -f $entry ]] || continue
      if grep -qx 'QSG_RHI_BACKEND=opengl' -- "$entry"; then printf shader; else printf offscreen; fi
      declared="$(grep '^QV4_' -- "$entry" | sort | tr '\n' ' ')" || declared=""
      printf ' %s\n' "${declared% }"
    done | sort)" || got=unreadable
    if [[ $run == "$runner" ]]; then
      if [[ $status -eq 0 && $got == "offscreen $want"$'\n'"shader $want" ]]; then
        ok "every qml test runs in the shell's GC mode"
      else
        fail "the shell's GC mode: exit $status, starts [$got], want [$want] on offscreen and shader"; tail -n 5 "$dir/out"
      fi
    elif [[ $status -eq 0 && $got == "offscreen "$'\n'"shader " ]]; then
      ok "control: a runner that does not apply the shell's GC mode fails the row"
    else
      fail "control: a runner that does not apply the shell's GC mode: exit $status, starts [$got]"; tail -n 5 "$dir/out"
    fi
  done
  rm -f -- "${dir:?}"/env.*
  status=0
  got="$(PATH="$dir/bin:$PATH" QML_UNIT_RUNNER="$dir/runner" "$refusal/scripts/qml-unit.sh" --tests "$repo/scripts/qml-tests" "$dir/tests/tst_gc.qml" 2>&1)" || status=$?
  if [[ $status -eq 2 && $got == "qml-unit: refused: pragma=unparsed file=$refusal/shell/shell.qml line=1" ]] && ! compgen -G "$dir/env.*" >/dev/null; then
    ok "an Env pragma with no = is refused before any test starts"
  else
    fail "an Env pragma with no =: exit $status, got [$got]"
  fi
}

run_case() { # KIND [INDEX]
  local out
  case "$1" in
    missing-runner)
      if out="$(QML_UNIT_RUNNER=/nonexistent/qmltestrunner "$runner" --ui "$copy" 2>&1)"; then
        fail "a missing runner passed"
      elif [[ $out == "qml-unit: status=not-measured missing=qmltestrunner" ]]; then
        ok "a missing runner is not a pass"
      else
        fail "a missing runner: got $out"
      fi ;;
    unknown-argument)
      if out="$("$runner" --nope 2>&1)"; then fail "an unknown argument passed"; elif [[ $out == "qml-unit: refused: argument=--nope" ]]; then ok "an unknown argument is refused"; else fail "an unknown argument: got $out"; fi ;;
    xvfb-lock) xvfb_lock_case ;;
    cleanup) cleanup_case ;;
    gc-mode) gc_mode_case ;;
    log) log_case "$2" ;;
    *) fail "test-qml-unit: case=$1 unknown" ;;
  esac
}

# Run the current cases side by side, at most jobs_max at once, as the
# parallel_cases of scripts/test-validate.sh runs its own: each job writes
# its lines to its own log and its failure count beside it, and the logs
# print in case order, so the lines read as one case after another. A job
# that ended before writing its count is one failure. A job resets INT and
# QUIT, which a bare `&` ignores, so a Ctrl-C reaches every runner.
run_cases() {
  local i count active=0
  for i in "${!cases[@]}"; do
    (
      trap - INT QUIT
      # shellcheck disable=SC2030 # the job's own count, by design
      failures=0
      # shellcheck disable=SC2086 # a case is its kind and its index
      run_case ${cases[i]}
      printf '%s\n' "$failures" >"$tmp/case-$i.failures"
    ) >"$tmp/case-$i.log" 2>&1 &
    active=$((active + 1))
    if ((active >= jobs_max)); then
      wait -n || true
      active=$((active - 1))
    fi
  done
  wait
  for i in "${!cases[@]}"; do
    cat -- "$tmp/case-$i.log"
    if count="$(cat -- "$tmp/case-$i.failures" 2>/dev/null)" && [[ $count =~ ^[0-9]+$ ]]; then
      # shellcheck disable=SC2031 # the parent's count, which the jobs left alone
      failures=$((failures + count))
    else
      fail "${cases[i]}: the case's job ended before it reported"
    fi
  done
}

cases=(missing-runner unknown-argument xvfb-lock gc-mode cleanup)
for index in "${!logs[@]}"; do cases+=("log $index"); done
run_cases

count="$(count_qml_unit_roots "$TMPDIR")" || count=unreadable
printf 'test-qml-unit: temporary-roots=%s scope=world\n' "$count"
if [[ $count != 0 ]]; then
  fail "the world's temporary directory holds [$count] qml-unit folders, want zero"
fi

if [[ $failures -eq 0 ]]; then
  echo "test-qml-unit: ok logs=${#logs[@]}"
  exit 0
fi
echo "test-qml-unit: failed=$failures"
exit 1
