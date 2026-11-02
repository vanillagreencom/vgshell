# The one reader of a smoke row's input line, the one list of the core
# rows and of the judge rows, and the one reader of the nested smoke's
# per-row outcomes, sourced by scripts/validate, which selects rows by
# them and records each smoke row's outcome, and by scripts/qml-smoke.sh,
# whose --rows adds the core rows and the rows a row reads and whose
# driver reports each row's result. The line's form is in scripts/AGENTS.md.

# The rows every run that does not run every row runs: the bar and the
# session the others build on, the consent row that answers the dialog the
# first shell raises, the start order and auth-sentinel, whose reading
# covers every row the run held. scripts/check-smoke-readers.py reads the
# line.
smoke_core=(bar hyprland-consent session start-order auth-sentinel)

# The rows that judge what every other row of their sandbox left:
# tui-guard reads the stand-in terminal's refusals and auth-sentinel the
# authentication calls. Each also plants calls or refusals of its own as its
# controls. A pass of any other row rests on the judges' readings that
# harness.sh takes at each row's start and end (smoke_judge_reading), not
# on a judge row having run after it: smoke_attempt_judged.
smoke_judges=(tui-guard auth-sentinel)

# smoke_inputs_read FILE: read FILE's one `# inputs: GLOB [GLOB...]` line,
# in its leading comment block (the lines from its first that start with
# #), into smoke_globs, with the line itself in smoke_inputs_line, and
# return 0. Otherwise leave smoke_globs empty, set smoke_inputs_fault to
# unreadable, missing, lines=<count> or empty, and return 1.
smoke_inputs_read() { # FILE
  local count=0
  smoke_globs=()
  smoke_inputs_fault=""
  if ! smoke_inputs_line="$(awk '!/^#/ { exit } /^# inputs:/ { print }' "$1")"; then
    smoke_inputs_fault=unreadable; return 1
  fi
  [[ -z $smoke_inputs_line ]] || count="$(wc -l <<<"$smoke_inputs_line")"
  if [[ $count -eq 0 ]]; then smoke_inputs_fault=missing; return 1; fi
  if [[ $count -gt 1 ]]; then smoke_inputs_fault="lines=$count"; return 1; fi
  read -r -a smoke_globs <<<"${smoke_inputs_line#\# inputs:}"
  if [[ ${#smoke_globs[@]} -eq 0 ]]; then smoke_inputs_fault=empty; return 1; fi
}

# smoke_inputs_rows ROW: the row files the globs last read name, as row
# names in smoke_inputs_named: each glob that is one file under
# scripts/smoke/rows/ other than ROW's own. ROW reads that row's functions
# or state and fails without it. A glob with a wildcard names no one row.
smoke_inputs_rows() { # ROW
  local glob name
  smoke_inputs_named=()
  for glob in "${smoke_globs[@]}"; do
    name="${glob#scripts/smoke/rows/}"; name="${name%.sh}"
    if [[ $glob == "scripts/smoke/rows/$name.sh" && $name =~ ^[a-z0-9-]+$ && $name != "$1" ]]; then
      smoke_inputs_named+=("$name")
    fi
  done
}

# smoke_attempt_judged ATTEMPT: true when the attempt directory ATTEMPT,
# one `qml-smoke: attempt=` names, proves the passes of the rows it ended:
# it read no failure outside every row (outside-failures), no judge row
# failed (results/<judge>), and its judge-readings, the lines
# `<row> start|end <calls> <refused> <state>` harness.sh's
# smoke_judge_reading gives at each row's start and end, read every
# sentinel and the stand-in terminal intact and show no authentication call
# and no refusal of a script no shipped plugin holds, from the sandbox's
# start to the last reading, but inside a judge row's own window, whose
# controls make them. A call a row's background process makes after the
# row ended lands in a later window, so a call anywhere voids every pass of
# the attempt rather than one row's. Sets smoke_attempt_ended[ROW] for each
# row the readings saw end. Reading after the attempt was cut off sees
# nothing the sandbox did after its last reading.
smoke_attempt_judged() { # ATTEMPT
  local attempt="$1" row edge calls refused state judge open="" previous=""
  local -a fields
  smoke_attempt_ended=()
  mapfile -d '' -t fields 2>/dev/null <"$attempt/outside-failures" || return 1
  [[ ${fields[0]-} == 0 ]] || return 1
  for judge in "${smoke_judges[@]}"; do
    [[ -e $attempt/results/$judge ]] || continue
    smoke_record_verdict "$attempt/results/$judge" && [[ $smoke_verdict == pass ]] || return 1
  done
  [[ -f $attempt/judge-readings ]] || return 1
  while read -r row edge calls refused state; do
    [[ $calls =~ ^[0-9]+$ && $refused =~ ^[0-9]+$ && $state == intact ]] || return 1
    if [[ -z $previous ]]; then
      ((calls == 0 && refused == 0)) || return 1
    elif ((calls != ${previous% *} || refused != ${previous#* })); then
      [[ $edge == end && $row == "$open" && " ${smoke_judges[*]} " == *" $row "* ]] || return 1
    fi
    previous="$calls $refused"
    case "$edge" in
      start) open="$row" ;;
      end) open=""; smoke_attempt_ended[$row]=1 ;;
      *) return 1 ;;
    esac
  done <"$attempt/judge-readings" || return 1
}

# smoke_record_verdict FILE: read one of a row's records, its
# results/<row> or partial/<row>, NUL-separated: the row's failure count,
# then each check it could not measure. Sets smoke_verdict to fail, skip
# for a check not measured, or pass, smoke_record_failures to the count
# and smoke_record_width to the field count; returns 1 for a record it
# cannot read or that holds no count.
smoke_record_verdict() { # FILE
  local -a fields
  mapfile -d '' -t fields 2>/dev/null <"$1" || return 1
  [[ ${fields[0]-} =~ ^[0-9]+$ ]] || return 1
  smoke_record_failures=${fields[0]} smoke_record_width=${#fields[@]}
  if ((smoke_record_failures > 0)); then smoke_verdict=fail
  elif ((smoke_record_width > 1)); then smoke_verdict=skip
  else smoke_verdict=pass; fi
}

# smoke_outcomes ATTEMPT...: each row's outcome over the attempt
# directories ATTEMPT, in the order they ran, of one or more runs of
# scripts/qml-smoke.sh. Per attempt a row's record is its results/<row>,
# written as it ends, and partial/<row>, written as it goes, which alone
# stands for a row the attempt left open. A producer replayed to rebuild
# state shows its result more than once, so the record with the most
# failures, then the most checks not measured, stands, the later on a tie:
# smoke_outcome_record[ROW]. smoke_outcome[ROW] is its verdict, fail or
# skip, also in smoke_outcome_checks[ROW], the row's own checks, with pass
# there for a record with neither. smoke_outcome[ROW] is pass when an
# attempt ended the row and every attempt that ended it proved it
# (smoke_attempt_judged), and unproved otherwise: a row no attempt ended, a
# record that cannot be read or an attempt whose passes are not proved.
# smoke_outcome_secs[ROW] is the row's last `qml-smoke: row-secs` reading
# in an attempt's run.log.
declare -gA smoke_outcome=() smoke_outcome_checks=() smoke_outcome_record=() smoke_outcome_secs=() smoke_attempt_ended=()
smoke_outcomes() { # ATTEMPT...
  local attempt record row line judged smoke_verdict smoke_record_failures smoke_record_width
  local -A ended=() unproved=() worst_count=() worst_width=()
  smoke_outcome=() smoke_outcome_checks=() smoke_outcome_record=() smoke_outcome_secs=()
  for attempt in "$@"; do
    judged=true
    smoke_attempt_judged "$attempt" || judged=false
    for record in "$attempt"/partial/* "$attempt"/results/*; do
      row="${record##*/}"
      [[ -f $record && $row =~ ^[a-z0-9-]+$ ]] || continue
      if ! smoke_record_verdict "$record"; then unproved[$row]=1; continue; fi
      if [[ -z ${worst_count[$row]-} ]] || ((smoke_record_failures > worst_count[$row] ||
        (smoke_record_failures == worst_count[$row] && smoke_record_width >= worst_width[$row]))); then
        smoke_outcome_record[$row]="$record" smoke_outcome_checks[$row]=$smoke_verdict
        worst_count[$row]=$smoke_record_failures worst_width[$row]=$smoke_record_width
      fi
      [[ $record == */results/* ]] || continue
      ended[$row]=1
      [[ $judged == true && -n ${smoke_attempt_ended[$row]-} ]] || unproved[$row]=1
    done
    if [[ -f $attempt/run.log ]]; then
      while IFS= read -r line; do
        [[ $line =~ ^qml-smoke:\ row-secs\ row=([a-z0-9-]+)\ secs=([0-9]+) ]] || continue
        smoke_outcome_secs[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
      done <"$attempt/run.log"
    fi
  done
  for row in "${!smoke_outcome_checks[@]}"; do
    smoke_outcome[$row]=${smoke_outcome_checks[$row]}
    [[ ${smoke_outcome[$row]} != pass || ( -n ${ended[$row]-} && -z ${unproved[$row]-} ) ]] || smoke_outcome[$row]=unproved
  done
  for row in "${!unproved[@]}"; do
    [[ -n ${smoke_outcome[$row]-} ]] || smoke_outcome[$row]=unproved
  done
}
