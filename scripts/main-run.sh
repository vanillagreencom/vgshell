#!/usr/bin/env bash
# Run whole validation areas on the newest main, on a detached worktree.
#
# Usage: scripts/main-run.sh [--root DIR] AREA... [-- SLOT-CMD [ARG...]]
#        scripts/main-run.sh [--root DIR] --due AREA...
#
# One runner serves the batch run and the nightly run: the caller names the
# areas, such as `unit qml` for the batch and `qml` for the local nightly,
# the area .github/workflows/nightly.yml cannot run. What a lane runs and
# what the batch run covers: docs/decisions/D100-validation-selects-by-inputs.md.
# The runner reports only: it opens no issue, blocks no push and holds no
# lane.
#
# A run fetches origin, makes a detached worktree of origin/main at
# <checkout parent>/.worktrees/<checkout name>/mainrunXXXXXX, and in
# it runs `scripts/validate --full AREA` for each area in the order given,
# with that commit's own scripts/validate. The qml area alone runs as
# `SLOT-CMD [ARG...] scripts/validate --full qml`: the caller passes the
# wrapper that gives the nested sandbox its slot and display environment,
# and no other area runs under it. The runner starts no graphics program:
# each one scripts/validate reaches (qml-smoke.sh, measure-shader.sh,
# qml-unit.sh) hands itself to scripts/smoke/gpu-fence.sh.
#
# The record root, by default <checkout>/tmp/main-run/<AREA+AREA...>, keeps
# one directory per run, named by its UTC start (YYYYmmddTHHMMSSZ): run.log,
# <area>.log for each area, `started` (epoch seconds), `sha` once the fetch
# answered, and result.txt, written whole at the end:
#   run=<id> sha=<sha> areas=<areas> started=<epoch>
#   area=<area> exit=<status> secs=<seconds> <its last validate: selected= line>
#     | <the failing row and FAIL lines of a non-zero area, at most 20>
#   finished=<UTC time>
#   landings since the last green <sha>:    (red only)
#   landing=<id> commit=<sha> <subject>     (one line each, newest first)
#   last-green=none                         (red, no green run recorded)
#   result=green|red
# A run that could not start writes `result=not-run cause=fetch-failed` or
# `cause=worktree-failed` and exits 77. The root's `last-green` holds the
# commit of the newest green run, so each area set keeps its own.
#
# The run is green only when every area exits 0: exit 77, which says a row
# could not run, makes it red like any other non-zero status. Exit 0 green,
# 1 red, 77 not run, 75 when another run holds the root's lock (nothing is
# written), 2 on a refused argument: `main-run: refused: <key>=<value>`.
#
# --due runs nothing. It answers whether a batch run is due: `main-run:
# due=yes|no landings=<n> secs=<seconds since the last run started>`, exit
# 0 when due and 1 when not, `due=no reason=running` while a run holds the
# lock, and exit 77 when the fetch or the landing read fails. It reads the
# newest finished run, one whose result.txt ends result=green or
# result=red: a run killed partway or one that ended result=not-run moves
# no trigger. A run is due after 5 landings on origin/main since the
# commit that run read, or 3600 s after it started with at least one
# landing since; with no finished run it is due.
#
# A landing is read from git, with no counter beside it: the commits of
# `git log --no-merges <from>..<to>` grouped by the issue identifier in
# their subject's scope, `area(VGS-12): summary`, which every vgs commit
# carries; a commit with none is a landing alone. A lane that lands one
# issue in two pushes counts once, which can only delay a batch.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"

refuse() {
  printf 'main-run: refused: %s\n' "$1" >&2
  shift
  [[ $# -eq 0 ]] || printf '%s\n' "$@" >&2
  exit 2
}

root=
due=0
areas=()
slot=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 && -n $2 ]] || refuse 'argument=--root value=missing'
      root="$2"
      shift 2
      ;;
    --due) due=1; shift ;;
    --)
      shift
      [[ $# -gt 0 ]] || refuse 'argument=-- value=missing' 'A wrapper command follows --.'
      slot=("$@")
      break
      ;;
    -*) refuse "argument=$1" 'Usage: scripts/main-run.sh [--root DIR] [--due] AREA... [-- SLOT-CMD [ARG...]]' ;;
    *)
      [[ $1 =~ ^[a-z][a-z0-9-]*$ ]] || refuse "area=$1" 'An area is a scripts/validate area name.'
      areas+=("$1")
      shift
      ;;
  esac
done
[[ ${#areas[@]} -gt 0 ]] || refuse 'areas=none' 'Name at least one scripts/validate area.'
[[ $due -eq 0 || ${#slot[@]} -eq 0 ]] || refuse 'argument=-- reason=due-runs-nothing'

checkout="$(git -C "$(dirname -- "$self")" rev-parse --show-toplevel)" || refuse 'checkout=unresolved'
[[ -n $root ]] || root="$checkout/tmp/main-run/$(IFS=+; echo "${areas[*]}")"
mkdir -p -- "$root"
root="$(cd -- "$root" && pwd -P)"

# landings FROM TO: one line per landing in FROM..TO, newest first.
landings() {
  local log sha subject id
  local -A seen=()
  log="$(git -C "$checkout" log --no-merges --format='%H %s' "$1..$2")" || return 1
  [[ -n $log ]] || return 0
  while IFS=' ' read -r sha subject; do
    id=none
    if [[ $subject =~ ^[a-z]+\(([A-Z]+-[0-9]+)\) ]]; then
      id="${BASH_REMATCH[1]}"
      [[ -z ${seen[$id]-} ]] || continue
      seen[$id]=1
    fi
    printf 'landing=%s commit=%s %s\n' "$id" "${sha:0:12}" "$subject"
  done <<<"$log"
}

# The newest run directory that reached a verdict, or nothing. A result
# that cannot be read counts as no verdict, which can only make a run due
# sooner.
last_run() {
  local dir newest= verdict
  for dir in "$root"/[0-9]*T*Z; do
    [[ -f $dir/sha && -f $dir/result.txt ]] || continue
    verdict="$(tail -n 1 -- "$dir/result.txt")" || continue
    [[ $verdict != result=green && $verdict != result=red ]] || newest="$dir"
  done
  printf '%s' "$newest"
}

exec 9>"$root/lock"
if ! flock -n 9; then
  if [[ $due -eq 1 ]]; then
    echo 'main-run: due=no reason=running'
    exit 1
  fi
  printf 'main-run: busy root=%s\n' "$root" >&2
  exit 75
fi

if [[ $due -eq 1 ]]; then
  unknown() { printf 'main-run: due=unknown cause=%s\n' "$1" >&2; exit 77; }
  git -C "$checkout" fetch -q origin || unknown fetch-failed
  head="$(git -C "$checkout" rev-parse --verify 'origin/main^{commit}')" || unknown fetch-failed
  last="$(last_run)"
  if [[ -z $last ]]; then
    echo 'main-run: due=yes landings=unknown secs=none'
    exit 0
  fi
  list="$(landings "$(<"$last/sha")" "$head")" || unknown landings-unreadable
  count=0
  [[ -z $list ]] || count="$(wc -l <<<"$list")"
  secs=$(( $(date +%s) - $(<"$last/started") ))
  if (( count >= 5 || (count >= 1 && secs >= 3600) )); then
    printf 'main-run: due=yes landings=%s secs=%s\n' "$count" "$secs"
    exit 0
  fi
  printf 'main-run: due=no landings=%s secs=%s\n' "$count" "$secs"
  exit 1
fi

id="$(date -u +%Y%m%dT%H%M%SZ)"
out="$root/$id"
mkdir -- "$out"
started="$(date +%s)"
echo "$started" >"$out/started"
exec >"$out/run.log" 2>&1

not_run() {
  printf 'run=%s areas=%s started=%s\nresult=not-run cause=%s\n' "$id" "${areas[*]}" "$started" "$1" >"$out/result.tmp"
  mv -- "$out/result.tmp" "$out/result.txt"
  exit 77
}

git -C "$checkout" fetch -q origin || not_run fetch-failed
sha="$(git -C "$checkout" rev-parse --verify 'origin/main^{commit}')" || not_run fetch-failed
echo "$sha" >"$out/sha"
wt_parent="$(dirname -- "$checkout")/.worktrees/$(basename -- "$checkout")"
mkdir -p -- "$wt_parent" || not_run worktree-failed
wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed
if ! git -C "$checkout" worktree add -q --detach "$wt" "$sha"; then
  rmdir -- "$wt" || not_run worktree-failed
  not_run worktree-failed
fi

verdict=green
{
  printf 'run=%s sha=%s areas=%s started=%s\n' "$id" "$sha" "${areas[*]}" "$started"
  for area in "${areas[@]}"; do
    begin=$SECONDS
    command=(scripts/validate --full "$area")
    [[ $area != qml ]] || command=("${slot[@]}" "${command[@]}")
    rc=0
    (cd -- "$wt" && "${command[@]}") >"$out/$area.log" 2>&1 9>&- </dev/null || rc=$?
    [[ $rc -eq 0 ]] || verdict=red
    printf 'area=%s exit=%s secs=%s %s\n' "$area" "$rc" "$((SECONDS - begin))" \
      "$(grep -a '^validate: selected=' "$out/$area.log" | tail -n 1 || true)"
    if [[ $rc -ne 0 ]]; then
      grep -a -e '^validate: secs=[0-9]* exit=[1-9]' -e '^  FAIL' -e '^FAIL' -e '^not ok' "$out/$area.log" |
        cut -c1-220 | sed -n '1,20s/^/  | /p' || true
    fi
  done
  echo "finished=$(date -u +%FT%TZ)"
  if [[ $verdict == green ]]; then
    echo "$sha" >"$root/last-green"
  elif [[ -s $root/last-green ]]; then
    last="$(<"$root/last-green")"
    echo "landings since the last green $last:"
    landings "$last" "$sha" || echo "landings=unreadable from=$last"
  else
    echo 'last-green=none'
  fi
  echo "result=$verdict"
} >"$out/result.tmp"
mv -- "$out/result.tmp" "$out/result.txt"
git -C "$checkout" worktree remove --force "$wt"
[[ $verdict == green ]]
