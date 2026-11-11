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
# none; a red run's summary, read from lines of the first batch's logs,
# lists each row whose own verdict is not a pass, a failed row that
# printed no FAIL line and an unmeasured smoke row with its status, and
# no passing row whose control printed FAIL lines; the slot command
# wraps the qml area alone; a held lock exits 75 and makes no run
# directory; --due answers at 0, 4 and 5 landings and at
# 1 landing 2 h and 0 h after the last run, and past newer runs that were
# killed partway or not run; a failed fetch exits 77 with result=not-run.
# A TERM to the runner alone while its area waits stops the area, which
# releases a lock the stand-in holds, removes the worktree from disk and
# from `git worktree list`, and ends the runner by TERM; an area starts
# with INT and QUIT at their defaults, leading its own session.
# The age cases plant the earlier run's `started` record in place of a
# clock. The retention cases plant run directories named for days before
# now beside a real run, read the retention through the copied
# orch-env ladder at its default and at 7 days from a scratch
# kendex.settings.toml, and check exactly which go; a run that cannot be
# removed is logged and leaves a green exit; a retention too large for
# shell arithmetic refuses; a root outside the clone's tmp/, tmp/ itself,
# a `..` escape and a symlink out are refused in both modes, creating
# nothing.
#
# Controls, each a copy of the runner with one rule removed by a
# substitution that must match once: a verdict that passes 77 turns the 77
# case red, a verdict that ignores area exits turns the 1 case red, and a
# landing reader that counts commits rather than identifiers turns the
# naming case red, and a trigger that reads a run with no verdict turns the
# unfinished case red, and a summary read from FAIL lines turns the
# summary case red. A retention with no age cut, one that does not keep
# the last-green run or the newest run of an area set, one that judges a
# symlink as a run, or one that does not read the ladder turns its
# retention case red, and a root bound that accepts any root turns the
# outside case red. A runner with no signal trap or one that does not stop
# its area turns the TERM case red, and one that leaves INT and QUIT
# ignored or the area in the runner's session turns the area start case red.
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
# The stand-in prints <area>.log from here as its rows' output.
report_logs="$TMP_ROOT/report-logs"
mkdir -p "$report_logs"
clone="$TMP_ROOT/clone"
runner="$clone/scripts/main-run.sh"
# Every record root sits in the clone's tmp/, the only place the runner
# accepts one.
records="$clone/tmp"

# Every child gets this environment and no other.
xenv=(env -i PATH="$PATH" HOME="$TMP_ROOT/home" LC_ALL=C
  GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  MAIN_RUN_TEST_TABLE="$table" MAIN_RUN_TEST_CALLS="$calls" MAIN_RUN_TEST_PATHS="$paths"
  MAIN_RUN_TEST_LOGS="$report_logs" MAIN_RUN_TEST_KEPT="$TMP_ROOT/kept"
  MAIN_RUN_TEST_AREA="$TMP_ROOT/area")
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
# The lock is held until this process ends; no child keeps it.
if [[ -n ${MAIN_RUN_TEST_HELD:-} ]]; then exec 8>>"$MAIN_RUN_TEST_HELD"; flock 8; fi
pwd -P >>"$MAIN_RUN_TEST_PATHS"
stat="$(</proc/$$/stat)"
read -r _ _ _ session _ <<<"${stat##*) }"
printf '%s %s %s\n' "$(sed -n 's/^SigIgn:\t*//p' /proc/self/status 8>&-)" "$session" "$$" >>"$MAIN_RUN_TEST_AREA"
while [[ -n ${MAIN_RUN_TEST_WAIT:-} && ! -f $MAIN_RUN_TEST_WAIT ]]; do sleep 0.02 8>&-; done
echo "validate: selected=1 area=$area secs=0"
[[ ! -f $MAIN_RUN_TEST_LOGS/$area.log ]] || cat -- "$MAIN_RUN_TEST_LOGS/$area.log"
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
# The runner reads its retention through the real settings ladder.
mkdir -p "$clone/.agents/skills/orch/scripts/lib"
cp -- "$repo/.agents/skills/orch/scripts/orch-env" "$clone/.agents/skills/orch/scripts/orch-env"
cp -- "$repo/.agents/skills/orch/scripts/lib/kendex-env.sh" "$clone/.agents/skills/orch/scripts/lib/kendex-env.sh"
mkdir -p "$clone/.agents/skills/linear/scripts" "$clone/.agents/skills/mailbox/scripts" "$TMP_ROOT/kept"
mkdir -p "$records/lane-mail/overseer"
printf '[]\n' >"$TMP_ROOT/kept/issues"
printf '{}\n' >"$TMP_ROOT/kept/comments"
: >"$TMP_ROOT/kept/asks"
cat >"$clone/.agents/skills/linear/scripts/linear.sh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'issues list') file=issues ;;
  'comments bulk-list') file=comments ;;
  *) exit 1 ;;
esac
[[ ! -f $MAIN_RUN_TEST_KEPT/fail-$file ]] || exit 1
cat -- "$MAIN_RUN_TEST_KEPT/$file"
EOF
cat >"$clone/.agents/skills/mailbox/scripts/lane-mail" <<'EOF'
#!/usr/bin/env bash
[[ ! -f $MAIN_RUN_TEST_KEPT/fail-asks ]] || exit 1
cat -- "$MAIN_RUN_TEST_KEPT/asks"
EOF
chmod +x "$clone/.agents/skills/linear/scripts/linear.sh" "$clone/.agents/skills/mailbox/scripts/lane-mail"

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
  local root="$records/r-green" text
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
  local root="$records/r-naming" text want got
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
  local root="$records/offline+unit+package+nix+qml with space" worktree name
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
  local one="$records/one/offline+unit" two="$records/two/offline+unit"
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
if case_red "$records/r-77" qml 77; then ok "an area exiting 77 is red and keeps last-green"; else fail "77: ${problems[*]}"; fi
if case_red "$records/r-1" unit 1; then ok "an area exiting 1 is red and keeps last-green"; else fail "1: ${problems[*]}"; fi
if case_naming; then ok "a red run names one landing per identifier since the last green"; else fail "naming: ${problems[*]}"; fi

# Lines copied from the first batch, run 20261111T163144Z on 2091a4e90:
# its unit.log and qml.log. Keys labels and bluetooth passed while their
# controls printed unmarked failures; the other rows failed or went
# unmeasured by their own verdict lines. Lines prefixed CONTROL are a
# control's copy of the smoke driver.
cat >"$TMP_ROOT/batch-unit.log" <<'EOF'
  FAIL  first-label lookup reads its body's dependent height: tst_pane.qml passed on the mutated copy
validate: secs=1656 exit=1 row=qml unit controls
== Keys labels show whole
  ok    every shipped Keys label shows whole
FAIL!  : qmltestrunner::keylabels::test_every_keys_label_shows_whole() every Keys label shows whole
qml-unit: failed file=tst_keylabels.qml status=1
  ok    control: a planted long label fails the check
validate: secs=1 exit=0 row=Keys labels show whole
EOF
cat >"$TMP_ROOT/batch-qml.log" <<'EOF'
  FAIL  popup release-control: wait for target activation before typing: got false want true
  FAIL  popup release-control: native Escape returns Settings to its list: got "vgs.bluetooth" want ""
  ok    popup control: the unguarded workload exits nonzero
qml-smoke: row-result row=googledrive status=failed
qml-smoke: row-result row=diagnostics status=not-measured
qml-smoke: row-result row=keyhints status=not-measured
qml-smoke: row-result row=settings-unsaved status=failed
qml-smoke: row-result row=displays status=failed
qml-smoke: row-result row=share-picker status=failed
qml-smoke: row-result row=bluetooth status=ok
qml-smoke: row-result row=launcher-latency status=not-measured
validate: secs=9606 exit=1 row=nested smoke
  CONTROL  qml-smoke: row-result row=bar status=unreached
  CONTROL  qml-smoke: row-result row=fatal status=failed cause=fatal-bash
EOF
# The stand-in adds its own failed verdict per area, a row that prints no
# FAIL line.
case_control_report() {
  problems=()
  local text want
  cp -- "$TMP_ROOT/batch-unit.log" "$report_logs/unit.log"
  cp -- "$TMP_ROOT/batch-qml.log" "$report_logs/qml.log"
  areas 'unit 1' 'qml 1'
  main --root "$1" unit qml
  rm -f -- "${report_logs:?}/unit.log" "${report_logs:?}/qml.log"
  [[ $status -eq 1 ]] || problems+=(red-run-passed)
  text="$(result "$1")" || { problems+=(result=missing); return 1; }
  for want in 'exit=1 row=qml unit controls' 'exit=1 row=nested smoke' 'exit=1 row=stand-in unit' \
    'row=googledrive status=failed' 'row=settings-unsaved status=failed' 'row=displays status=failed' \
    'row=share-picker status=failed' 'row=diagnostics status=not-measured' \
    'row=keyhints status=not-measured' 'row=launcher-latency status=not-measured'; do
    [[ $text == *"  | "*"$want"* ]] || problems+=("missing=$want")
  done
  [[ $text != *bluetooth* ]] || problems+=(listed=bluetooth)
  [[ $text != *'Keys label'* && $text != *keylabels* ]] || problems+=(listed=keylabels)
  [[ $text != *CONTROL* ]] || problems+=(listed=control-copy)
  [[ ${#problems[@]} -eq 0 ]]
}
if case_control_report "$records/r-control-report"; then
  ok "the batch report lists each row by its own verdict, not its controls' FAIL lines"
else
  fail "control report: ${problems[*]}"
fi

# --due on one root: no earlier run, then 0, 4 and 5 landings after a run.
due_root="$records/r-due"
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
  age_root="$records/r-age-$age"
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
  local root="$records/r-unfinished"
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

# settings DAYS: the scratch clone's kendex.settings.toml sets the
# retention to DAYS, or the file is absent when DAYS is empty.
settings() {
  rm -f -- "$clone/kendex.settings.toml"
  [[ -z $1 ]] || printf '[env]\nORCH_RECORD_RETENTION_DAYS = "%s"\n' "$1" >"$clone/kendex.settings.toml"
}

# plant_run ROOT NAME DAYS REV [AREAS]: a run directory named for DAYS days
# ago that read REV, with a result.txt naming AREAS, or none; its id is
# kept in `planted[NAME]`.
declare -A planted=()
plant_run() {
  local epoch=$(( $(date +%s) - $3 * 86400 )) id sha
  id="$(date -u -d "@$epoch" +%Y%m%dT%H%M%SZ)" || return 1
  sha="$(g -C "$clone" rev-parse "$4")" || return 1
  mkdir -p "$1/$id" && echo "$sha" >"$1/$id/sha" && echo "$epoch" >"$1/$id/started" || return 1
  [[ -z ${5-} ]] || printf 'run=%s sha=%s areas=%s started=%s\nresult=green\n' "$id" "$sha" "$5" "$epoch" >"$1/$id/result.txt" ||
    return 1
  planted[$2]="$id"
}

# case_retention ROOT DAYS: a red unit run in ROOT, with DAYS as for
# `settings`, beside planted runs: old ones of `unit`, a recent one, an old
# killed one 6 days old, an old one that read last-green, the newest and
# an older run of `qml`, a non-run directory and a symlink named as an old
# run. Exactly the old, killed (under the default of 5) and older qml runs
# go.
case_retention() {
  problems=()
  local root="$1" days="$2" name current got want link="$1/../link-target-${1##*/}"
  local -a dirs gone=(old older-qml) stay=(recent green qml)
  planted=()
  if [[ -z $days ]]; then gone+=(killed); else stay+=(killed); fi
  mkdir -p "$root/notes" "$link"
  : >"$link/kept"
  g -C "$clone" rev-parse 'origin/main^' >"$root/last-green"
  plant_run "$root" old 10 origin/main unit &&
    plant_run "$root" killed 6 origin/main &&
    plant_run "$root" recent 2 origin/main unit &&
    plant_run "$root" green 20 'origin/main^' unit &&
    plant_run "$root" qml 15 origin/main qml &&
    plant_run "$root" older-qml 16 origin/main qml || { problems+=(plant=failed); return 1; }
  ln -s -- "$link" "$root/$(date -u -d "@$(( $(date +%s) - 30 * 86400 ))" +%Y%m%dT%H%M%SZ)"
  settings "$days"
  areas 'unit 1'
  main --root "$root" unit
  settings ''
  [[ $status -eq 1 ]] || problems+=("exit=$status")
  dirs=("$root"/[0-9]*T*Z)
  current="${dirs[-1]}"
  [[ -f $current/result.txt && $(tail -n 1 -- "$current/result.txt") == result=red ]] || problems+=(current=missing)
  for name in "${gone[@]}"; do [[ ! -e $root/${planted[$name]} ]] || problems+=("kept=$name"); done
  for name in "${stay[@]}"; do [[ -d $root/${planted[$name]} ]] || problems+=("removed=$name"); done
  for name in lock last-green notes; do [[ -e $root/$name ]] || problems+=("removed=$name"); done
  [[ -f $link/kept && $(find "$root" -maxdepth 1 -type l | wc -l) -eq 1 ]] || problems+=(removed=symlink)
  got="$(grep '^main-run: removed run=' "$current/run.log" | sort)" || got=
  want="$(for name in "${gone[@]}"; do echo "main-run: removed run=${planted[$name]}"; done | sort)" ||
    { problems+=(want=unbuilt); return 1; }
  [[ $got == "$want" ]] || problems+=("log=[${got//$'\n'/,}]")
  [[ ${#problems[@]} -eq 0 ]]
}
if case_retention "$records/r-retention" ''; then
  ok "a run removes old runs past the default 5 days and keeps the rest"
else
  fail "retention default: ${problems[*]}"
fi
if case_retention "$records/r-retention-7" 7; then
  ok "a run reads the retention from the settings ladder"
else
  fail "retention 7: ${problems[*]}"
fi

# An old run that cannot be removed is named in run.log and leaves a green
# run green. It read an older commit than the one the green run records.
case_remove_failed() {
  problems=()
  local root="$records/r-remove-failed" dirs
  plant_run "$root" stuck 10 'origin/main^' unit || { problems+=(plant=failed); return 1; }
  mkdir -p "$root/${planted[stuck]}/held"
  : >"$root/${planted[stuck]}/held/file"
  chmod 555 "$root/${planted[stuck]}/held"
  areas 'unit 0'
  main --root "$root" unit
  chmod 755 "$root/${planted[stuck]}/held"
  dirs=("$root"/[0-9]*T*Z)
  [[ $status -eq 0 ]] || problems+=("exit=$status")
  grep -qx "main-run: remove-failed run=${planted[stuck]}" "${dirs[-1]}/run.log" || problems+=(log=silent)
  [[ ${#problems[@]} -eq 0 ]]
}
if case_remove_failed; then ok "a failed removal is logged and leaves the verdict's exit"; else fail "remove failed: ${problems[*]}"; fi

# Each row: a record root outside the checkout's tmp/, the mode, and a path
# the refusal must not create.
outside_table=(
  "$TMP_ROOT/outside|run|$TMP_ROOT/outside"
  "$TMP_ROOT/outside-due|due|$TMP_ROOT/outside-due"
  "$records|run|$records/lock"
  "$records/../escape|run|$clone/escape"
  "$records/away/root|run|$TMP_ROOT/away/root"
)
mkdir -p "$records" "$TMP_ROOT/away"
ln -sfn -- "$TMP_ROOT/away" "$records/away"
# case_outside ROOT MODE PATH: the refusal for one row.
case_outside() {
  problems=()
  local resolved mode=()
  [[ $2 == run ]] || mode=(--due)
  resolved="$(realpath -m -- "$1")"
  areas 'unit 0'
  main --root "$1" "${mode[@]}" unit
  [[ $status -eq 2 ]] || problems+=("exit=$status")
  [[ $(sed -n '1p' "$TMP_ROOT/out") == "main-run: refused: root=$resolved" ]] || problems+=("out=[$(sed -n '1p' "$TMP_ROOT/out")]")
  [[ ! -e $3 ]] || problems+=("created=$3")
  [[ ${#problems[@]} -eq 0 ]]
}
for entry in "${outside_table[@]}"; do
  IFS='|' read -r outside_root outside_mode outside_path <<<"$entry"
  if case_outside "$outside_root" "$outside_mode" "$outside_path"; then
    ok "a $outside_mode root resolving outside tmp/ is refused: $outside_root"
  else
    fail "outside $outside_root: ${problems[*]}"
  fi
done

# A retention too large for shell arithmetic refuses and runs nothing.
case_retention_bound() {
  problems=()
  local root="$records/r-retention-bound" dirs
  settings 100000
  main --root "$root" unit
  settings ''
  dirs=("$root"/[0-9]*T*Z)
  [[ $status -eq 2 && ! -e ${dirs[0]} ]] || problems+=("exit=$status")
  [[ $(sed -n '1p' "$TMP_ROOT/out") == 'main-run: refused: ORCH_RECORD_RETENTION_DAYS=100000' ]] ||
    problems+=("out=[$(sed -n '1p' "$TMP_ROOT/out")]")
  [[ ${#problems[@]} -eq 0 ]]
}
if case_retention_bound; then ok "a retention past 99999 days refuses and runs nothing"; else fail "retention bound: ${problems[*]}"; fi

# Every case reaches the production expiry through a real scratch batch.
case_expiry() {
  problems=()
  local root="$records/$1" base="expiry-$1" path mode="${2:-complete}" dirs record span="VGS-1-focused-$1-a/file" family="VGS-1-focused-$1-b/file"
  [[ ${3-} != roots ]] || root="$records/main-run/$1"
  record="${root#"$records"/}"
  if [[ ${3-} == roots ]]; then
    mkdir -p "$records/qml-smoke"
    touch -d '10 days ago' "$records/qml-smoke/$1"
  fi
  plant_run "$root" old 10 'origin/main^' unit
  plant_run "$root" referenced 11 'origin/main^' unit
  : >"$root/${planted[referenced]}/evidence"
  mkdir -p "$records/$base/kept" "$records/$base/comment" "$records/$base/ask" "$records/$base/mixed"
  for path in kept/file 'kept/file with space' comment/file ask/file expired mixed/old; do : >"$records/$base/$path"; done
  python3 - "$records/$base" <<'PY'
import os, sys, time
for parent, dirs, files in os.walk(sys.argv[1], topdown=False):
    for name in files + dirs:
        os.utime(os.path.join(parent, name), (time.time() - 10 * 86400,) * 2)
os.utime(sys.argv[1], (time.time() - 10 * 86400,) * 2)
PY
  : >"$records/$base/mixed/new"
  printf '[{"id":"VGS-2127","state":"Verifying","description":"tmp/%s/kept/file"},{"id":"VGS-1","state":"Done","description":"tmp/%s/expired"},{"id":"VGS-2","state":"Canceled","description":"tmp/%s/mixed/old"},{"id":"VGS-3","state":"Triage","description":null},{"id":"VGS-4","state":"Todo","description":"`tmp/` `tmp/main-run/` `tmp/qml-smoke/` tmp/* `*` tmp/*/mixed/old tmp/VGS-1-focused-%s-b* `VGS-1-focused-%s-*` `VGS-1-focused-%s-a` `#[test]`"}]\n' "$base" "$base" "$base" "$1" "$1" "$1" >"$TMP_ROOT/kept/issues"
  printf '{"VGS-2127":[{"body":"tmp/%s/comment/file tmp/%s/%s/ `tmp/%s/kept/file with space`"}],"VGS-3":[],"VGS-4":[]}\n' "$base" "$record" "${planted[referenced]}" "$base" >"$TMP_ROOT/kept/comments"
  printf '{"kind":"ask","to":"owner","text":"Read tmp/%s/ask/file\\nKeep the evidence."}\n' "$base" >"$TMP_ROOT/kept/asks"
  local package_paths=("lane-archive/$1" "waiter.$1/file" "dev-validate-old/record" "validation-runs" "cycle-state/state.json" "container-close.lock")
  mkdir -p "$records/VGS-2127-focused-$1" "$records/${span%/*}" "$records/${family%/*}" "$records/lane-archive" "$records/waiter.$1" "$records/dev-validate-old" "$records/cycle-state"
  for path in "VGS-2127-focused-$1/file" "$span" "$family" "${package_paths[@]}"; do
    touch -d '10 days ago' "$records/$path"
  done
  case "$mode" in
    complete) ;;
    invalid-issues) printf '{}\n' >"$TMP_ROOT/kept/issues" ;;
    missing-description) printf '[{"id":"VGS-2127","state":"Verifying"}]\n' >"$TMP_ROOT/kept/issues" ;;
    invalid-description) printf '[{"id":"VGS-2127","state":"Verifying","description":[]}]\n' >"$TMP_ROOT/kept/issues" ;;
    invalid-comments) printf '{"VGS-2127":null}\n' >"$TMP_ROOT/kept/comments" ;;
    invalid-asks) printf '{"text":null}\n' >"$TMP_ROOT/kept/asks" ;;
    missing-asks) mv -- "$records/lane-mail/overseer" "$records/lane-mail/held" ;;
    *) : >"$TMP_ROOT/kept/fail-$mode" ;;
  esac
  areas 'unit 0'
  main --root "$root" unit
  [[ $mode != missing-asks ]] || mv -- "$records/lane-mail/held" "$records/lane-mail/overseer"
  rm -f -- "$TMP_ROOT/kept/fail-$mode"
  printf '[]\n' >"$TMP_ROOT/kept/issues"
  printf '{}\n' >"$TMP_ROOT/kept/comments"
  : >"$TMP_ROOT/kept/asks"
  [[ $status -eq 0 ]] || problems+=("exit=$status")
  for path in kept/file 'kept/file with space' comment/file ask/file mixed/new; do
    [[ -f $records/$base/$path ]] || problems+=("removed=$path")
  done
  for path in "VGS-2127-focused-$1/file" "${package_paths[@]}"; do
    [[ -f $records/$path ]] || problems+=("removed=$path")
  done
  for path in "$base/expired" "$base/mixed/old" "$span" "$family"; do
    if [[ $mode == complete ]]; then
      [[ ! -e $records/$path ]] || problems+=("kept=$path")
    else
      [[ -f $records/$path ]] || problems+=("removed-on-unread=$path")
    fi
  done
  [[ -f $root/${planted[referenced]}/evidence ]] || problems+=(batch-reference=removed)
  if [[ $mode == complete ]]; then
    [[ ! -e $root/${planted[old]} ]] || problems+=(batch-old=kept)
  else
    [[ -d $root/${planted[old]} ]] || problems+=(batch-unread=removed)
  fi
  [[ ${3-} != roots || ! -e $records/qml-smoke/$1 ]] || problems+=(writer-root=kept)
  dirs=("$root"/[0-9]*T*Z)
  grep -q '^main-run: kept-set-read-secs=' "${dirs[-1]}/run.log" || problems+=(duration=missing)
  [[ ${#problems[@]} -eq 0 ]]
}
if case_expiry r-expiry; then ok "expiry keeps referenced evidence, open item families and package state, and removes expired siblings"; else fail "expiry: ${problems[*]}"; fi
for unread in issues comments asks invalid-issues missing-description invalid-description invalid-comments invalid-asks missing-asks; do
  if case_expiry "r-expiry-$unread" "$unread"; then ok "an unread $unread kept set removes nothing"; else fail "expiry $unread: ${problems[*]}"; fi
done
if case_expiry r-expiry-roots complete roots; then ok "a bare writer root keeps no batch run while a named run stays"; else fail "expiry roots: ${problems[*]}"; fi

# A held lock: exit 75, no run directory, and --due answers running.
busy_root="$records/r-busy"
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
main --root "$records/r-fetch" unit
text="$(result "$records/r-fetch" 2>/dev/null)" || text=
if [[ $status -eq 77 && $text == *$'\nresult=not-run cause=fetch-failed' ]]; then
  ok "a failed fetch exits 77 with result=not-run"
else
  fail "fetch: exit=$status result=[$text]"
fi
g -C "$clone" remote set-url origin "$TMP_ROOT/origin.git"

# case_killed NAME: a TERM to the runner alone while its area waits.
case_killed() {
  problems=()
  local release="$TMP_ROOT/release-$1" pid attempt rc=0 worktree list
  : >"$paths"
  areas 'unit 0'
  (cd -- "$clone" && exec "${xenv[@]}" MAIN_RUN_TEST_WAIT="$release" MAIN_RUN_TEST_HELD="$release.held" \
    bash "$runner" --root "$records/$1" unit) \
    >"$TMP_ROOT/$1.out" 2>&1 &
  pid=$!
  for ((attempt=0; attempt<1500; attempt++)); do
    [[ ! -s $paths ]] || break
    sleep 0.02 # wait for the area to start, bounded above
  done
  kill -TERM "$pid" || problems+=(runner=gone)
  for ((attempt=0; attempt<1500; attempt++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.02 # wait for the runner to stop its area, bounded above
  done
  (( attempt < 1500 )) || problems+=(runner=outlived-term)
  flock -w 5 "$release.held" true || problems+=(area=left-running)
  : >"$release" # frees an area a runner left running
  wait "$pid" || rc=$?
  [[ $rc -eq 143 ]] || problems+=("exit=$rc")
  if ! worktree="$(sed -n '1p' "$paths")" || [[ -z $worktree ]]; then
    problems+=(area=unstarted)
    return 1
  fi
  [[ ! -e $worktree ]] || problems+=(worktree-left)
  list="$(g -C "$clone" worktree list --porcelain)" || { problems+=(list=unreadable); return 1; }
  if grep -Fxq -- "worktree $worktree" <<<"$list"; then problems+=(worktree-registered); fi
  [[ ${#problems[@]} -eq 0 ]]
}
if case_killed r-killed; then ok "a TERM to the runner stops its area and removes the worktree"; else fail "killed: ${problems[*]}"; fi

# case_area_start NAME: the area's inherited mask leaves INT (0x2) and QUIT
# (0x4) at their defaults, for the rows that send them, and the area leads
# its own session, so only the runner's TERM reaches it.
case_area_start() {
  problems=()
  local mask session pid
  : >"$TMP_ROOT/area"
  areas 'unit 0'
  main --root "$records/$1" unit
  [[ -s $TMP_ROOT/area ]] || { problems+=(area=missing); return 1; }
  while read -r mask session pid; do
    (( (16#$mask & 6) == 0 )) || problems+=(int-quit=ignored "sigign=$mask")
    [[ $session == "$pid" ]] || problems+=(session=shared)
  done <"$TMP_ROOT/area"
  [[ ${#problems[@]} -eq 0 ]]
}
if case_area_start r-area-start; then
  ok "an area starts with INT and QUIT at their defaults, leading its own session"
else
  fail "area start: ${problems[*]}"
fi

# Controls: each copy removes one rule and must turn its case red.
if ! source_text="$(cat -- "$repo/scripts/main-run.sh")"; then
  fail "control: scripts/main-run.sh is unreadable"
  source_text=
fi
# control NAME PATTERN REPLACEMENT CASE [ARG...]
control() {
  local name="$1" pattern="$2" replacement="$3" rest want_problem=
  shift 3
  if [[ ${1-} == --problem ]]; then want_problem="$2"; shift 2; fi
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
  elif [[ -n $want_problem && " ${problems[*]} " != *" $want_problem "* ]]; then
    fail "control $name: expected $want_problem, got ${problems[*]}"
  else
    ok "control: $name turns its case red (${problems[*]})"
  fi
}
control "a summary read from FAIL lines" \
  "grep -a -E -e '^validate: secs=[0-9]+ exit=[1-9]' -e '^qml-smoke: row-result ' \"\$out/\$area.log\" |
        grep -a -v -E '^qml-smoke: row-result row=[^ ]+ status=ok( |\$)' |" \
  "grep -a -e '^validate: secs=[0-9]* exit=[1-9]' -e '^  FAIL' -e '^FAIL' -e '^not ok' \"\$out/\$area.log\" |" \
  --problem listed=bluetooth case_control_report "$records/c-control-report"
control "77 counted as a pass" '[[ $rc -eq 0 ]] || verdict=red' '[[ $rc -eq 0 || $rc -eq 77 ]] || verdict=red' \
  case_red "$records/c-77" qml 77
control "a verdict that ignores area exits" '[[ $rc -eq 0 ]] || verdict=red' ': || verdict=red' \
  case_red "$records/c-1" unit 1
control "commits counted as landings" '[[ -z ${seen[$id]-} ]] || continue' ':' case_naming
control "a worktree name copied from the record root" \
  'wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed' \
  'wt="$wt_parent/main-run-$(basename -- "$root")"' case_worktree_path
control "a worktree shared by distinct record roots" \
  'wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed' \
  'wt="$wt_parent/main-run-fixed"' case_concurrent_paths
control "a run with no verdict read as the last run" \
  '[[ $verdict != result=green && $verdict != result=red ]] || newest="$dir"' 'newest="$dir"' case_unfinished
control "no age cut" '(( 10#${name//[TZ]/} < 10#$cut )) && [[' '[[' case_retention "$records/c-age" ''
control "the last-green run not kept" '[[ -z $green || $sha != "$green" ]] || continue' ':' \
  case_retention "$records/c-green" ''
control "the newest run of an area set not kept" 'for name in "${newest[@]}"; do keep[$name]=1; done' ':' \
  case_retention "$records/c-newest" ''
control "a symlink judged as a run" '&& -d $dir && ! -L $dir ]]' '&& -d $dir ]]' \
  case_retention "$records/c-symlink" ''
control "the retention not read from the ladder" '.agents/skills/orch/scripts/orch-env ORCH_RECORD_RETENTION_DAYS 5)' \
  'echo 5)' case_retention "$records/c-ladder" 7
control "a root outside tmp/ accepted" '[[ $root == "$tmp"/?* ]] ||' ': ||' case_outside "$TMP_ROOT/c-outside" run "$TMP_ROOT/c-outside"
control "referenced evidence not kept" 'or kept(path):' 'or False:' case_expiry c-expiry-kept
control "expired files not removed" 'os.unlink(entry.name, dir_fd=fd)' 'pass' case_expiry c-expiry-remove
control "unread kept set does not stop batch pruning" 'protected="$(expire_tmp)" || return 0' \
  'protected="$(expire_tmp)" || :' --problem batch-unread=removed case_expiry c-expiry-unread issues
control "a referenced batch run is not kept" \
  "[[ \$'\\n'\$protected\$'\\n' != *\$'\\n'\"\$name\"\$'\\n'* ]] || continue" \
  ':' --problem batch-reference=removed case_expiry c-expiry-reference
control "a bare writer root keeps every batch run" 'and p not in output_roots' '' \
  --problem batch-old=kept case_expiry c-expiry-roots complete roots
control "a glob in the first segment kept" 'and not re.search(r"[*?[]", p.split("/")[0])' '' \
  --problem kept=expiry-c-expiry-glob/expired case_expiry c-expiry-glob
control "a family glob kept unless glob characters alone" 're.search(r"[*?[]", p.split("/")[0])' \
  're.fullmatch(r"[*?\[\]!]+", p.split("/")[0])' --problem kept=VGS-1-focused-c-expiry-family-b/file \
  case_expiry c-expiry-family
control "a code span with no tmp/ path kept" 'for p in re.findall(r"`([^`\n]+)`", text) if "tmp/" in p)' \
  'for p in re.findall(r"`([^`\n]+)`", text) if "tmp/" in p)
        patterns.update(p.rstrip("/") for p in re.findall(r"`([^`\n]+)`", text)
                        if "tmp/" not in p and not re.search(r"[\s/]", p))' \
  --problem kept=VGS-1-focused-c-expiry-span-a/file case_expiry c-expiry-span
control "no signal trap" "trap 'end_run TERM' TERM; trap 'end_run INT' INT; trap 'end_run HUP' HUP" ':' \
  --problem worktree-left case_killed c-killed
control "an area the trap does not stop" 'if [[ -n $child ]]; then' 'if false; then' \
  --problem area=left-running case_killed c-killed-area
control "INT and QUIT left ignored in an area" 'setsid env --default-signal=INT,QUIT ' 'setsid ' \
  --problem int-quit=ignored case_area_start c-area-signals
control "an area in the runner's session" 'exec setsid env' 'exec env' \
  --problem session=shared case_area_start c-area-session
cp -- "$repo/scripts/main-run.sh" "$runner"

if [[ $failures -gt 0 ]]; then
  echo "test-main-run: failures=$failures"
  exit 1
fi
echo "test-main-run: ok"
