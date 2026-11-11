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
# The record root must resolve strictly inside <checkout>/tmp/; any other
# root is refused before anything is created. Each run, once its result is
# written, removes the run directories of its root whose name says they
# started more than ORCH_RECORD_RETENTION_DAYS days before it, read through
# .agents/skills/orch/scripts/orch-env with a default of 5. It always keeps
# itself, `lock`, `last-green`, any entry that is not a plain directory
# named by a run id, every run whose `sha` is last-green's commit, and the
# newest run of each area set its result.txt's first line names. It prints
# `main-run: removed run=<id>`, or `main-run: remove-failed run=<id>`, to
# run.log; a failed removal leaves the exit to the verdict.
# Before pruning, one complete Linear issue/comment read and owner-ask read
# protects cited paths, open-item artifact groups and live fleet/package state.
# An unread kept set deletes nothing. Other VGS tmp files expire after seven
# days, without following links or removing newer siblings. The batch logs
# kept-set-read-secs and every removed file. See runtime.md Temporary artifacts.
#
# The run is green only when every area exits 0: exit 77, which says a row
# could not run, makes it red like any other non-zero status. Exit 0 green,
# 1 red, 77 not run, 75 when another run holds the root's lock (nothing is
# written), 2 on a refused argument: `main-run: refused: <key>=<value>`.
# A TERM, INT or HUP ends a run that has its worktree by stopping the
# running area with TERM, removing the worktree and ending the runner by
# that signal, with no result.txt. Each area runs in the background under
# `wait`, since bash runs a trap only after its foreground child ends, and
# in its own session, so a terminal's INT reaches the runner alone. The
# runner's TERM is meant as the only signal the area receives: a caller
# that starts the runner as a systemd unit sets KillMode=mixed, since the
# default control-group mode also signals the area directly. A SIGKILL,
# such as systemd-oomd's, runs no trap and leaves the worktree.
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
# The retention removes directories, so the root is bounded before it exists.
tmp="$(realpath -m -- "$checkout/tmp")" || refuse "root=$checkout/tmp"
root="$(realpath -m -- "$root")" || refuse "root=$root"
[[ $root == "$tmp"/?* ]] || refuse "root=$root" "The record root lies inside $tmp/."
if [[ $due -eq 0 ]]; then
  retention="$(cd -- "$checkout" && .agents/skills/orch/scripts/orch-env ORCH_RECORD_RETENTION_DAYS 5)" ||
    refuse 'ORCH_RECORD_RETENTION_DAYS=unreadable'
  # It reaches shell arithmetic, which evaluates any other text and wraps a
  # number too large for it.
  [[ $retention =~ ^[0-9]{1,5}$ ]] ||
    refuse "ORCH_RECORD_RETENTION_DAYS=$retention" 'The retention is a whole number of days, at most 99999.'
fi
mkdir -p -- "$root"

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

# prune: the retention the header states, judged against this run's start.
# Run ids are fixed-width UTC times, so their digits compare as numbers.
expire_tmp() {
  python3 - "$checkout" "$root" "$started" <<'PY'
import errno
import fnmatch
import json
import os
import re
import stat
import subprocess
import sys
import time

checkout, root, started = sys.argv[1:]
tmp = os.path.join(checkout, "tmp")
record = os.path.relpath(root, tmp)
cutoff = int(started) - 7 * 86400
begin = time.monotonic()

def read(command, data=None):
    return subprocess.run(["timeout", "--kill-after=5", "600", *command], cwd=checkout,
                          input=data, text=True, stdout=subprocess.PIPE, check=True).stdout

try:
    linear = os.path.join(checkout, ".agents/skills/linear/scripts/linear.sh")
    source = "issues"
    # Every team: VGS lanes file KEN and other teams' items citing evidence
    # under this tmp/. Their text keeps only the paths it names, and
    # over-keeping is the safe failure for a deleter.
    issues = json.loads(read([linear, "issues", "list", "--select", "owed",
                              "--all-projects", "--include-archived", "--max"]))
    if not isinstance(issues, list):
        raise ValueError("issues-not-list")
    opened = {}
    for issue in issues:
        description = issue["description"]
        if description is None:
            description = ""
        if not all(isinstance(issue[key], str) for key in ("id", "state")) or not isinstance(description, str):
            raise ValueError("issue-fields")
        if issue["state"] not in ("Done", "Canceled"):
            opened[issue["id"]] = description
    source = "comments"
    comments = json.loads(read([linear, "comments", "bulk-list", "--stdin"],
                              "\n".join(opened) + "\n")) if opened else {}
    if not isinstance(comments, dict) or set(comments) != set(opened):
        raise ValueError("comments-incomplete")
    texts = list(opened.values())
    for rows in comments.values():
        if not isinstance(rows, list):
            raise ValueError("comments-not-list")
        for row in rows:
            if not isinstance(row["body"], str):
                raise ValueError("comment-body")
            texts.append(row["body"])
    mail = os.path.join(checkout, ".agents/skills/mailbox/scripts/lane-mail")
    source = "owner-asks"
    os.stat(os.path.join(tmp, "lane-mail", "overseer"))
    for line in read([mail, "pending", "--item", "overseer", "--to", "owner"]).splitlines():
        ask = json.loads(line)
        if not isinstance(ask["text"], str):
            raise ValueError("owner-ask-text")
        texts.append(ask["text"])
    patterns = set()
    for text in texts:
        patterns.update(p.rstrip("/.,;:)") for p in re.findall(r"tmp/([^\s`\"<>]+)", text))
        patterns.update(p.split("tmp/", 1)[1].rstrip("/")
                        for p in re.findall(r"`([^`\n]+)`", text) if "tmp/" in p)
    # A writer root in prose names no artifact; a path below it does.
    output_roots = {record.split("/")[0], "main-run", "qml-smoke", "display-record", "sandbox-shots",
                    "readme-shots", "theme-previews", "shader-cost", "selftest-records",
                    "readme-install-cache"}
    # A glob in the first segment, as in tmp/* or tmp/VGS-1-*, names a family
    # of top-level entries, not an artifact; open items keep their own family.
    patterns = [p.split("/") for p in patterns if p and not p.startswith("../") and p not in output_roots
                and not re.search(r"[*?[]", p.split("/")[0])]
    groups = {identifier.lower().replace("-", "") for identifier in opened}
except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
    print(f"main-run: expiry=skipped cause=kept-set-unreadable source={source} error={type(error).__name__}", file=sys.stderr)
    sys.exit(1)
finally:
    print(f"main-run: kept-set-read-secs={time.monotonic() - begin:.3f}", file=sys.stderr)

def intersects(relative):
    parts = relative.split("/")
    return any(all(fnmatch.fnmatchcase(part, pattern) for part, pattern in zip(parts, ref))
               for ref in patterns)

def kept(relative):
    parts = relative.split("/")
    group = re.match(r"(?i)^([a-z]+)-?(\d+)(?:[^0-9]|$)", parts[0])
    return (group is not None and "".join(group.groups()).lower() in groups) or any(
        len(ref) <= len(parts) and all(fnmatch.fnmatchcase(part, pattern)
                                    for part, pattern in zip(parts, ref)) for ref in patterns)

protected = []
try:
    with os.scandir(root) as runs:
        protected = [entry.name for entry in runs if re.fullmatch(r"\d{8}T\d{6}Z", entry.name)
                     and intersects(record + "/" + entry.name)]
    # Package state and the fleet's live helper roots have another owner.
    owned = ("lane-archive", "lane-mail", "progress-reports", "handoffs", "nested-slot.sh",
             "nested-slots", "oversee-watch", "oversee-watch.*", "waiter.*", "workflow-state-*",
             "dev-validate-*", ".dev-validate-runs.*", "validation-runs", "dev-round-*", "dev-return-*",
             "round-recovered-*", "cycle-state", "container-close*", "lane-wake-*", "lane-status-*")
    def visit(fd, relative=""):
        with os.scandir(fd) as entries:
            entries = list(entries)
        for entry in entries:
            path = relative + "/" + entry.name if relative else entry.name
            if (not relative and any(fnmatch.fnmatchcase(entry.name, p) for p in owned)) or kept(path):
                continue
            # The old batch policy owns this root, using the same kept snapshot.
            if path == record or record.startswith(path + "/"):
                continue
            try:
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                    try:
                        visit(child, path)
                    finally:
                        os.close(child)
                    if info.st_mtime < cutoff:
                        try:
                            os.rmdir(entry.name, dir_fd=fd)
                        except OSError as error:
                            if error.errno not in (errno.ENOTEMPTY, errno.EEXIST):
                                raise
                elif info.st_mtime < cutoff and (stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)):
                    os.unlink(entry.name, dir_fd=fd)
                    print(f"main-run: expired path=tmp/{path}", file=sys.stderr)
            except OSError as error:
                print(f"main-run: expiry-failed path=tmp/{path} error={error.errno}", file=sys.stderr)
    fd = os.open(tmp, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        visit(fd)
    finally:
        os.close(fd)
except OSError as error:
    print(f"main-run: expiry-failed error={error.errno}", file=sys.stderr)
    sys.exit(1)
print("\n".join(protected))
PY
}

prune() {
  local dir name line areaset green= sha cut protected
  local -a runs=()
  local -A newest=() keep=()
  protected="$(expire_tmp)" || return 0
  cut="$(date -u -d "@$((started - retention * 86400))" +%Y%m%d%H%M%S)" ||
    { echo 'main-run: remove-failed cause=cutoff-unreadable'; return 0; }
  [[ ! -f $root/last-green ]] || read -r green <"$root/last-green" || :
  for dir in "$root"/*; do
    name="${dir##*/}"
    [[ $name =~ ^[0-9]{8}T[0-9]{6}Z$ && -d $dir && ! -L $dir ]] || continue
    runs+=("$name")
    [[ -f $dir/result.txt ]] && read -r line <"$dir/result.txt" &&
      [[ $line =~ (^| )areas=(.*)\ started= ]] || continue
    areaset="${BASH_REMATCH[2]}"
    [[ -n ${newest[$areaset]-} ]] && (( 10#${newest[$areaset]//[TZ]/} > 10#${name//[TZ]/} )) ||
      newest[$areaset]="$name"
  done
  for name in "${newest[@]}"; do keep[$name]=1; done
  keep[$id]=1
  for name in "${runs[@]}"; do
    (( 10#${name//[TZ]/} < 10#$cut )) && [[ -z ${keep[$name]-} ]] || continue
    [[ $'\n'$protected$'\n' != *$'\n'"$name"$'\n'* ]] || continue
    sha=
    [[ ! -f $root/$name/sha ]] || read -r sha <"$root/$name/sha" || :
    [[ -z $green || $sha != "$green" ]] || continue
    if rm -rf -- "${root:?}/$name"; then
      echo "main-run: removed run=$name"
    else
      echo "main-run: remove-failed run=$name"
    fi
  done
}

not_run() {
  printf 'run=%s areas=%s started=%s\nresult=not-run cause=%s\n' "$id" "${areas[*]}" "$started" "$1" >"$out/result.tmp"
  mv -- "$out/result.tmp" "$out/result.txt"
  prune
  exit 77
}

git -C "$checkout" fetch -q origin || not_run fetch-failed
sha="$(git -C "$checkout" rev-parse --verify 'origin/main^{commit}')" || not_run fetch-failed
echo "$sha" >"$out/sha"
wt_parent="$(dirname -- "$checkout")/.worktrees/$(basename -- "$checkout")"
mkdir -p -- "$wt_parent" || not_run worktree-failed
wt="$(mktemp -d "$wt_parent/mainrunXXXXXX")" || not_run worktree-failed
# end_run SIGNAL: the end the header states for a signal.
child=
end_run() {
  trap '' TERM INT HUP
  if [[ -n $child ]]; then
    kill -TERM "$child" 2>/dev/null || :
    wait "$child" || :
  fi
  git -C "$checkout" worktree remove --force "$wt" || rmdir -- "$wt" || :
  trap - "$1"
  kill -s "$1" "$$"
}
trap 'end_run TERM' TERM; trap 'end_run INT' INT; trap 'end_run HUP' HUP
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
    # A background command starts with INT and QUIT ignored; env puts them
    # back for validate and the rows that send them. The subshell leads no
    # process group, so setsid execs in place and `child` stays the area.
    (cd -- "$wt" && exec setsid env --default-signal=INT,QUIT "${command[@]}") >"$out/$area.log" 2>&1 9>&- </dev/null &
    child=$!
    wait "$child" || rc=$?
    child=
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
trap - TERM INT HUP
git -C "$checkout" worktree remove --force "$wt"
prune
[[ $verdict == green ]]
