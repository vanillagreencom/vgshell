#!/usr/bin/env bash
# Controls for scripts/main-run.sh, the runner of whole areas on main. It
# starts no compositor and no shell: a scratch origin holds a stand-in
# scripts/validate whose exit per area comes from a table this suite
# writes, and a clone of it holds a copy of the runner, so the runner's
# toplevel, worktree and record root all sit in this suite's scratch.
#
# Cases: every area 0 is green and records last-green; one area 77 or 1 is
# red, exits 1 and keeps last-green; a red run names exactly the landings
# since the last green, one per issue identifier and one per commit with
# none; the slot command wraps the qml area alone; a held lock exits 75
# and makes no run directory; --due answers at 0, 4 and 5 landings and at
# 1 landing 2 h and 0 h after the last run, and past newer runs that were
# killed partway or not run; a failed fetch exits 77 with result=not-run.
# The age cases plant the earlier run's `started` record in place of a
# clock.
#
# Controls, each a copy of the runner with one rule removed by a
# substitution that must match once: a verdict that passes 77 turns the 77
# case red, a verdict that ignores area exits turns the 1 case red, and a
# landing reader that counts commits rather than identifiers turns the
# naming case red, and a trigger that reads a run with no verdict turns the
# unfinished case red.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

TMP_ROOT="$(mktemp -d)" || { echo "test-main-run: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-main-run: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-main-run: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

table="$TMP_ROOT/table"
calls="$TMP_ROOT/calls"
paths="$TMP_ROOT/paths"
clone="$TMP_ROOT/clone"
runner="$clone/scripts/main-run.sh"

# Every child gets this environment and no other.
xenv=(env -i PATH="$PATH" HOME="$TMP_ROOT/home" LC_ALL=C
  GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  MAIN_RUN_TEST_TABLE="$table" MAIN_RUN_TEST_CALLS="$calls" MAIN_RUN_TEST_PATHS="$paths")
g() { "${xenv[@]}" git "$@"; }
mkdir -p "$TMP_ROOT/home"

# The stand-in validate: `--full AREA`, exit from the table, one call line.
g init -q -b main "$TMP_ROOT/seed"
mkdir -p "$TMP_ROOT/seed/scripts"
cat >"$TMP_ROOT/seed/scripts/validate" <<'EOF'
#!/usr/bin/env bash
area="$2"
rc="$(awk -v a="$area" '$1 == a { rc = $2 } END { print rc }' "$MAIN_RUN_TEST_TABLE")"
printf 'area=%s args=%s slot=%s\n' "$area" "$*" "${MAIN_RUN_TEST_SLOT:-0}" >>"$MAIN_RUN_TEST_CALLS"
pwd -P >>"$MAIN_RUN_TEST_PATHS"
while [[ -n ${MAIN_RUN_TEST_WAIT:-} && ! -f $MAIN_RUN_TEST_WAIT ]]; do sleep 0.02; done
echo "validate: selected=1 area=$area secs=0"
[[ ${rc:-0} -eq 0 ]] || echo "validate: secs=0 exit=$rc row=stand-in $area"
exit "${rc:-0}"
EOF
chmod +x "$TMP_ROOT/seed/scripts/validate"
g -C "$TMP_ROOT/seed" add scripts/validate
g -C "$TMP_ROOT/seed" commit -q -m 'chore(VGS-0): seed'
g clone -q --bare "$TMP_ROOT/seed" "$TMP_ROOT/origin.git"
g clone -q "$TMP_ROOT/origin.git" "$clone"
g clone -q "$TMP_ROOT/origin.git" "$TMP_ROOT/pusher"
cp -- "$repo/scripts/main-run.sh" "$runner"

cat >"$TMP_ROOT/slot" <<'EOF'
#!/usr/bin/env bash
MAIN_RUN_TEST_SLOT=1 exec "$@"
EOF
chmod +x "$TMP_ROOT/slot"

# land SUBJECT...: one commit each on origin's main.
land() {
  local subject
  for subject in "$@"; do
    g -C "$TMP_ROOT/pusher" commit -q --allow-empty -m "$subject"
  done
  g -C "$TMP_ROOT/pusher" push -q origin main
}

# areas LINE...: the stand-in's exit table, one `area status` a line; the
# last line for an area wins.
areas() { printf '%s\n' "$@" >"$table"; }

# main ARGS...: run the runner from the clone; status in `status`.
status=0
main() {
  status=0
  : >"$calls"
  : >"$paths"
  (cd -- "$clone" && "${xenv[@]}" timeout 120 bash "$runner" "$@") >"$TMP_ROOT/out" 2>&1 || status=$?
}

# result ROOT: the newest run's result.txt.
result() {
  local dirs=("$1"/[0-9]*T*Z)
  cat -- "${dirs[-1]}/result.txt"
}

# Each case sets `problems`; an empty list is a pass.
problems=()

case_green() {
  problems=()
  local root="$TMP_ROOT/r-green" text
  areas 'unit 0' 'qml 0'
  main --root "$root" unit qml -- "$TMP_ROOT/slot"
  [[ $status -eq 0 ]] || problems+=("exit=$status")
  text="$(result "$root")" || { problems+=(result=missing); return 1; }
  [[ $text == *$'\nresult=green' ]] || problems+=("result=[${text##*$'\n'}]")
  [[ $(<"$root/last-green") == "$(g -C "$clone" rev-parse origin/main)" ]] || problems+=(last-green=wrong)
  [[ ${#problems[@]} -eq 0 ]]
}

# case_red ROOT AREA STATUS: a run whose AREA exits STATUS after a green.
case_red() {
  problems=()
  local root="$1" text before
  areas 'unit 0' 'qml 0'
  main --root "$root" unit qml
  [[ $status -eq 0 ]] || { problems+=("green-first exit=$status"); return 1; }
  before="$(<"$root/last-green")"
  land "feat(VGS-1): one"
  areas "unit 0" "qml 0" "$2 $3"
  sleep 1 # the run directory is named by the second it started
  main --root "$root" unit qml
  [[ $status -eq 1 ]] || problems+=("exit=$status")
  text="$(result "$root")" || { problems+=(result=missing); return 1; }
  [[ $text == *$'\nresult=red' ]] || problems+=("result=[${text##*$'\n'}]")
  [[ $text == *$'\n'"area=$2 exit=$3 "* ]] || problems+=(area-line=missing)
  [[ $(<"$root/last-green") == "$before" ]] || problems+=(last-green=moved)
  [[ ${#problems[@]} -eq 0 ]]
}

# The landings a red run names after a green: two commits of VGS-11 are one
# landing, the commit with no identifier is its own.
case_naming() {
  problems=()
  local root="$TMP_ROOT/r-naming" text want got
  areas 'unit 0'
  main --root "$root" unit
  [[ $status -eq 0 ]] || { problems+=("green-first exit=$status"); return 1; }
  land "feat(VGS-11): first" "fix(VGS-11): second" "docs: no identifier" "feat(VGS-12): third"
  areas 'unit 1'
  sleep 1 # the run directory is named by the second it started
  main --root "$root" unit
  [[ $status -eq 1 ]] || problems+=("exit=$status")
  text="$(result "$root")" || { problems+=(result=missing); return 1; }
  got="$(grep '^landing=' <<<"$text" | cut -d' ' -f1 | tr '\n' ' ')" || true
  want='landing=VGS-12 landing=none landing=VGS-11 '
  [[ $got == "$want" ]] || problems+=("landings=[$got]")
  [[ $text == *$'\nlandings since the last green '* ]] || problems+=(heading=missing)
  [[ ${#problems[@]} -eq 0 ]]
}

if case_green; then ok "every area 0 is green and records last-green"; else fail "green: ${problems[*]}"; fi
if [[ "$(<"$calls")" == $'area=unit args=--full unit slot=0\narea=qml args=--full qml slot=1' ]]; then
  ok "the slot command wraps the qml area alone"
else
  fail "slot: calls=[$(<"$calls")]"
fi
if [[ ! -e $(sed -n '1p' "$paths") ]]; then ok "the detached worktree is removed"; else fail "worktree left"; fi

case_worktree_path() {
  problems=()
  local root="$TMP_ROOT/offline+unit+package+nix+qml with space" worktree name
  areas 'unit 0'
  main --root "$root" unit
  [[ $status -eq 0 ]] || problems+=("exit=$status")
  worktree="$(cat -- "$paths")"
  name="${worktree##*/}"
  [[ $name =~ ^[a-zA-Z0-9]+$ && ${#name} -le 24 ]] || problems+=("worktree-name=[$name]")
  [[ ! -e $worktree ]] || problems+=(worktree-left)
  [[ $(result "$root") == *$'\nresult=green' ]] || problems+=(result=wrong)
  [[ ${#problems[@]} -eq 0 ]]
}
if case_worktree_path; then ok "a long record root with + and space has a short safe worktree name"; else fail "worktree path: ${problems[*]}"; fi

# Distinct record roots can run together even when their last component is
# the same. Both validate children wait until both worktrees exist.
case_concurrent_paths() {
  problems=()
  local release="$TMP_ROOT/release" first second count attempt one_status=0 two_status=0
  local one="$TMP_ROOT/one/offline+unit" two="$TMP_ROOT/two/offline+unit"
  rm -f -- "${release:?}"
  : >"$paths"
  areas 'unit 0'
  (cd -- "$clone" && "${xenv[@]}" MAIN_RUN_TEST_WAIT="$release" timeout 120 bash "$runner" --root "$one" unit) >"$TMP_ROOT/one.out" 2>&1 &
  first=$!
  (cd -- "$clone" && "${xenv[@]}" MAIN_RUN_TEST_WAIT="$release" timeout 120 bash "$runner" --root "$two" unit) >"$TMP_ROOT/two.out" 2>&1 &
  second=$!
  for ((attempt=0; attempt<500; attempt++)); do
    count="$(wc -l <"$paths")"
    [[ $count -lt 2 ]] || break
    sleep 0.02 # wait for both fixture validate calls, bounded above
  done
  : >"$release"
  wait "$first" || one_status=$?
  wait "$second" || two_status=$?
  [[ $count -eq 2 ]] || problems+=("started=$count")
  [[ $one_status -eq 0 && $two_status -eq 0 ]] || problems+=("exits=$one_status,$two_status")
  [[ $(sort -u "$paths" | wc -l) -eq 2 ]] || problems+=(worktrees-shared)
  [[ ${#problems[@]} -eq 0 ]]
}
if case_concurrent_paths; then ok "distinct result roots with the same name have separate worktrees"; else fail "concurrent paths: ${problems[*]}"; fi
if case_red "$TMP_ROOT/r-77" qml 77; then ok "an area exiting 77 is red and keeps last-green"; else fail "77: ${problems[*]}"; fi
if case_red "$TMP_ROOT/r-1" unit 1; then ok "an area exiting 1 is red and keeps last-green"; else fail "1: ${problems[*]}"; fi
if case_naming; then ok "a red run names one landing per identifier since the last green"; else fail "naming: ${problems[*]}"; fi

# --due on one root: no earlier run, then 0, 4 and 5 landings after a run.
due_root="$TMP_ROOT/r-due"
due_table=(
  "0|1|due=no landings=0"
  "4|1|due=no landings=4"
  "5|0|due=yes landings=5"
)
areas 'unit 0'
main --root "$due_root" --due unit
if [[ $status -eq 0 && $(<"$TMP_ROOT/out") == 'main-run: due=yes landings=unknown secs=none' ]]; then
  ok "--due with no earlier run is due"
else
  fail "--due first: exit=$status out=[$(<"$TMP_ROOT/out")]"
fi
main --root "$due_root" unit
landed=0
for entry in "${due_table[@]}"; do
  IFS='|' read -r want_count want_status want_text <<<"$entry"
  while (( landed < want_count )); do
    landed=$((landed + 1))
    land "feat(VGS-2$landed): landing $landed"
  done
  main --root "$due_root" --due unit
  if [[ $status -eq $want_status && $(<"$TMP_ROOT/out") == "main-run: $want_text secs="* ]]; then
    ok "--due at $want_count landings: $want_text"
  else
    fail "--due at $want_count: exit=$status out=[$(<"$TMP_ROOT/out")]"
  fi
done

# plant ROOT ID REV AGE [RESULT]: a run directory that read REV, started
# AGE seconds ago, with RESULT as its result.txt's last line, or none.
plant() {
  mkdir -p "$1/$2"
  g -C "$clone" rev-parse "$3" >"$1/$2/sha"
  echo $(( $(date +%s) - $4 )) >"$1/$2/started"
  [[ -z ${5-} ]] || printf 'run=%s\n%s\n' "$2" "$5" >"$1/$2/result.txt"
}
g -C "$clone" fetch -q origin

# --due at one landing, against a planted finished run 2 h and 0 h old.
age_table=(
  "7200|0|due=yes landings=1"
  "0|1|due=no landings=1"
)
for entry in "${age_table[@]}"; do
  IFS='|' read -r age want_status want_text <<<"$entry"
  age_root="$TMP_ROOT/r-age-$age"
  plant "$age_root" 20200101T000000Z 'origin/main^' "$age" result=green
  main --root "$age_root" --due unit
  if [[ $status -eq $want_status && $(<"$TMP_ROOT/out") == "main-run: $want_text secs="* ]]; then
    ok "--due at 1 landing, last run ${age} s ago: $want_text"
  else
    fail "--due age $age: exit=$status out=[$(<"$TMP_ROOT/out")]"
  fi
done

# Newer runs with no verdict, one killed partway and one not run, read
# origin/main now; --due still reads the finished run 2 h old before them.
case_unfinished() {
  problems=()
  local root="$TMP_ROOT/r-unfinished"
  plant "$root" 20200101T000000Z 'origin/main^' 7200 result=red
  plant "$root" 20200102T000000Z origin/main 0
  plant "$root" 20200103T000000Z origin/main 0 'result=not-run cause=worktree-failed'
  main --root "$root" --due unit
  [[ $status -eq 0 && $(<"$TMP_ROOT/out") == "main-run: due=yes landings=1 secs="* ]] ||
    problems+=("exit=$status out=[$(<"$TMP_ROOT/out")]")
  [[ ${#problems[@]} -eq 0 ]]
}
if case_unfinished; then
  ok "--due reads the newest finished run past a killed and a not-run one"
else
  fail "--due unfinished: ${problems[*]}"
fi

# A held lock: exit 75, no run directory, and --due answers running.
busy_root="$TMP_ROOT/r-busy"
mkdir -p "$busy_root"
exec 8>"$busy_root/lock"
flock -n 8
main --root "$busy_root" unit
dirs=("$busy_root"/[0-9]*T*Z)
if [[ $status -eq 75 && ! -e ${dirs[0]} ]]; then ok "a held lock exits 75 and runs nothing"; else fail "busy: exit=$status"; fi
main --root "$busy_root" --due unit
if [[ $status -eq 1 && $(<"$TMP_ROOT/out") == 'main-run: due=no reason=running' ]]; then
  ok "--due under a held lock answers running"
else
  fail "busy --due: exit=$status out=[$(<"$TMP_ROOT/out")]"
fi
exec 8>&-

# A failed fetch: exit 77, result=not-run.
g -C "$clone" remote set-url origin "$TMP_ROOT/nowhere.git"
main --root "$TMP_ROOT/r-fetch" unit
text="$(result "$TMP_ROOT/r-fetch" 2>/dev/null)" || text=
if [[ $status -eq 77 && $text == *$'\nresult=not-run cause=fetch-failed' ]]; then
  ok "a failed fetch exits 77 with result=not-run"
else
  fail "fetch: exit=$status result=[$text]"
fi
g -C "$clone" remote set-url origin "$TMP_ROOT/origin.git"

# Controls: each copy removes one rule and must turn its case red.
if ! source_text="$(cat -- "$repo/scripts/main-run.sh")"; then
  fail "control: scripts/main-run.sh is unreadable"
  source_text=
fi
# control NAME PATTERN REPLACEMENT CASE [ARG...]
control() {
  local name="$1" pattern="$2" replacement="$3" rest
  shift 3
  rest="${source_text#*"$pattern"}"
  if [[ $rest == "$source_text" || $rest == *"$pattern"* ]]; then
    fail "control $name: the pattern is not in scripts/main-run.sh exactly once"
    return
  fi
  printf '%s\n' "${source_text/"$pattern"/"$replacement"}" >"$runner"
  if cmp -s -- "$runner" "$repo/scripts/main-run.sh"; then
    fail "control $name: the copy did not change"
  elif "$@"; then
    fail "control $name: the case stayed green"
  else
    ok "control: $name turns its case red (${problems[*]})"
  fi
}
control "77 counted as a pass" '[[ $rc -eq 0 ]] || verdict=red' '[[ $rc -eq 0 || $rc -eq 77 ]] || verdict=red' \
  case_red "$TMP_ROOT/c-77" qml 77
control "a verdict that ignores area exits" '[[ $rc -eq 0 ]] || verdict=red' ': || verdict=red' \
  case_red "$TMP_ROOT/c-1" unit 1
control "commits counted as landings" '[[ -z ${seen[$id]-} ]] || continue' ':' case_naming
control "a worktree name copied from the record root" \
  'wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed' \
  'wt="$wt_parent/main-run-$(basename -- "$root")"' case_worktree_path
control "a worktree shared by distinct record roots" \
  'wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed' \
  'wt="$wt_parent/main-run-fixed"' case_concurrent_paths
control "a run with no verdict read as the last run" \
  '[[ $verdict != result=green && $verdict != result=red ]] || newest="$dir"' 'newest="$dir"' case_unfinished
cp -- "$repo/scripts/main-run.sh" "$runner"

if [[ $failures -gt 0 ]]; then
  echo "test-main-run: failures=$failures"
  exit 1
fi
echo "test-main-run: ok"
