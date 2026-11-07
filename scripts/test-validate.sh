#!/usr/bin/env bash
# Controls for the checks scripts/validate makes itself, run as
# `scripts/validate repo`, or `scripts/validate tools` for the document byte
# ceiling row, in a scratch repository: a copy of the script and
# the kendex settings loader, a base branch `trunk` with its remote-tracking
# ref, and a feature branch on top. Each row plants one defect in a fresh
# copy and asserts the exit status and the keyed lines the script's header
# promises; one row plants nothing and passes.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
# One row removes a file's permission bits, which bind only a non-root uid;
# a run that could not measure it is not a pass.
if [[ $(id -u) == 0 ]]; then
  echo "test-validate: status=not-measured reason=euid-0"
  exit 77
fi
tmp="$(mktemp -d "$TMPDIR/test-validate.XXXXXX")" || exit 1
trap 'chmod -R u+rwx -- "${tmp:?}" 2>/dev/null; rm -rf -- "${tmp:?}"' EXIT

# Every git and validate call runs with this environment and nothing else.
# Fixed identities and dates make every fixture's trunk the same commit, so
# one trunk id names the base of every row.
# Resolve node before replacing HOME: a version-manager shim may need the
# developer's configuration, which does not belong in the test environment.
node_bin="$(node -e 'process.stdout.write(process.execPath)')"
mkdir -p "$tmp/home/.config" "$tmp/home/.cache" "$tmp/home/.local/share" "$tmp/home/.local/state" "$tmp/runtime"
chmod 700 "$tmp/runtime"
base_env=(env -i PATH="$(dirname -- "$node_bin"):$PATH" HOME="$tmp/home" LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  VGSHELL_WORLD_ROOT="${VGSHELL_WORLD_ROOT:-}"
  JARVIS_TEST_SCRATCH_ROOT="$tmp"
  XDG_CONFIG_HOME="$tmp/home/.config" XDG_CACHE_HOME="$tmp/home/.cache" XDG_DATA_HOME="$tmp/home/.local/share" XDG_STATE_HOME="$tmp/home/.local/state" XDG_RUNTIME_DIR="$tmp/runtime"
  TMPDIR="$tmp"
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z)

failures=0
test_args=()
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# Independent cases run side by side, at most nproc at once: each job
# writes its lines to its own log and its failure count beside it, and the
# logs print in case order. A job that ended before writing its count, as
# `set -e` or a fixture's `exit` ends it, is one failure.
parallel_cases() { # WORKER PREFIX SPEC...
  local worker="$1" prefix="$2" max active=0 i count
  shift 2
  local -a specs=("$@")
  max="$(nproc)"
  for i in "${!specs[@]}"; do
    (
      # shellcheck disable=SC2030 # the job's own count, by design
      failures=0
      "$worker" "${specs[i]}"
      printf '%s\n' "$failures" >"$tmp/$prefix-$i.failures"
    ) >"$tmp/$prefix-$i.log" 2>&1 &
    active=$((active + 1))
    if ((active >= max)); then
      wait -n || true
      active=$((active - 1))
    fi
  done
  wait
  for i in "${!specs[@]}"; do
    cat -- "$tmp/$prefix-$i.log"
    if count="$(cat -- "$tmp/$prefix-$i.failures" 2>/dev/null)" && [[ $count =~ ^[0-9]+$ ]]; then
      # shellcheck disable=SC2031 # the parent's count, which the jobs left alone
      failures=$((failures + count))
    else
      fail "${specs[i]%%|*}: the case's job ended before it reported"
    fi
  done
}

# A fresh scratch repository at $1: trunk holds the script, the loader, the
# md-refs checker, the document validate cites, and an exclusion list that
# keeps these borrowed files' own references out of scope, a settings file
# naming trunk as the base branch, one clean file and
# one under each root an install ships, bin/, shell/ and config/, each at a
# path the tree holds, so a fixture that copies the tree in replaces it;
# refs/remotes/origin/trunk points at it; HEAD is a feature branch on top.
# It holds the input line reader too, which the script sources, and the
# readers the smoke row selection's load reading imports.
# The repository is built once and each fixture is its own copy of it.
fresh() {
  local dir="$1"
  if [[ -e $dir ]]; then
    echo "test-validate: fixture=exists path=$dir" >&2; exit 1
  fi
  cp -a -- "$tmp/template" "$dir"
}
template() {
  local dir="$tmp/template"
  mkdir -p "$dir/scripts/smoke" "$dir/.agents/skills/orch/scripts/lib" "$dir/.agents/skills/commit-guards" "$dir/tools" "$dir/docs/architecture"
  cp -- "$repo/scripts/validate" "$dir/scripts/validate"
  cp -- "$repo/docs/architecture/validation.md" "$dir/docs/architecture/validation.md"
  cp -- "$repo/scripts/smoke/row-inputs.sh" "$dir/scripts/smoke/row-inputs.sh"
  # Selection and scheduler cases have a transparent world stand-in. The
  # boundary cases below replace it with the production world.
  printf '#!/bin/sh\nwhile [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' >"$dir/scripts/smoke/gpu-fence.sh"
  chmod +x "$dir/scripts/smoke/gpu-fence.sh"
  printf 'console.log(JSON.stringify({status: "pass"}));\n' >"$dir/scripts/check-packaging.js"
  # Consumer-selection fixtures never start a real nested runtime.
  printf '#!/bin/sh\nexit 0\n' >"$dir/scripts/test-qml-smoke.sh"
  chmod +x "$dir/scripts/test-qml-smoke.sh"
  cp -- "$repo/.agents/skills/orch/scripts/lib/kendex-env.sh" "$dir/.agents/skills/orch/scripts/lib/kendex-env.sh"
  cp -R -- "$repo/.agents/skills/commit-guards/scripts" "$dir/.agents/skills/commit-guards/"
  printf '# kendex-guard-dialect: legacy-glob\n.agents/*\tcopies of checkers, whose citations name their own repository\n' >"$dir/tools/md-excludes"
  printf 'docs/architecture/validation.md\tborrowed citation target, whose links name the full repository\n' >>"$dir/tools/md-excludes"
  # The smoke row selection's load reading and the readers it imports,
  # borrowed with their citations.
  mkdir -p "$dir/bin/lib"
  cp -- "$repo/scripts/qml_controls.py" "$repo/scripts/qml_source.py" "$repo/scripts/shell_source.py" "$repo/scripts/check-smoke-needles.py" "$dir/scripts/"
  cp -- "$repo/bin/vgshell-scan" "$dir/bin/vgshell-scan"
  cp -- "$repo/bin/lib/dbus_wire.py" "$dir/bin/lib/dbus_wire.py"
  printf '%s\tborrowed reader, whose citations name the full repository\n' bin/vgshell-scan bin/lib/dbus_wire.py 'scripts/qml_*.py' >>"$dir/tools/md-excludes"
  printf '[env]\nWORKTREE_DEFAULT_BRANCH = "trunk"\n' >"$dir/kendex.settings.toml"
  # The copied extensionless scripts need the repository's source discovery setting.
  grep '^COMMIT_GUARDS_MD_REFS_SOURCE_PATHS[[:space:]]*=' "$repo/kendex.settings.toml" >>"$dir/kendex.settings.toml"
  printf 'clean\n' >"$dir/clean.txt"
  mkdir -p "$dir/bin/lib" "$dir/shell/Core" "$dir/config/system/udev"
  printf 'clean\n' | tee "$dir/bin/lib/logo.txt" "$dir/shell/Core/qmldir" >"$dir/config/system/udev/60-vgs-apple-displays.rules"
  "${base_env[@]}" git -C "$dir" init -q -b trunk
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m base
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
  "${base_env[@]}" git -C "$dir" checkout -q -b feature
}
template

# Nightly consumes this hash across unrelated main landings. Each case
# changes one part of the complete input set, without executing a build.
input_hash_case() {
  local change="$1" dir="$tmp/input-hash-$1" before after hash_area=package
  fresh "$dir"
  mkdir -p "$dir/packaging/arch/vgshell"
  printf 'recipe\n' >"$dir/packaging/arch/vgshell/PKGBUILD"
  printf '#!/bin/sh\nexit 99\n' >"$dir/scripts/arch-packages.sh"
  [[ $change != nix-flake ]] || hash_area=nix
  if ! before="$(cd -- "$dir" && "${base_env[@]}" "$BASH" scripts/validate "$hash_area" --input-hash)"; then
    fail "input hash $change: initial hash failed"; return
  fi
  case "$change" in
    content) printf 'changed\n' >>"$dir/packaging/arch/vgshell/PKGBUILD" ;;
    added) printf 'new input\n' >"$dir/packaging/arch/vgshell/new.patch" ;;
    removed) rm -- "$dir/packaging/arch/vgshell/PKGBUILD" ;;
    mode) chmod +x "$dir/scripts/arch-packages.sh" ;;
    command) printf '# changed\n' >>"$dir/scripts/arch-packages.sh" ;;
    unrelated) printf 'documentation\n' >"$dir/README.md" ;;
    other-area|nix-flake) printf 'flake\n' >"$dir/flake.nix" ;;
  esac
  if ! after="$(cd -- "$dir" && "${base_env[@]}" "$BASH" scripts/validate "$hash_area" --input-hash)"; then
    fail "input hash $change: changed hash failed"; return
  fi
  if [[ ! $before =~ ^[a-f0-9]{64}$ || ! $after =~ ^[a-f0-9]{64}$ ]]; then
    fail "input hash $change: unreadable hash"
  elif [[ $change == unrelated || $change == other-area ]]; then
    if [[ $before == "$after" ]]; then ok "input hash ignores $change"; else fail "input hash changed for $change"; fi
  elif [[ $before != "$after" ]]; then
    ok "input hash binds $change"
  else
    fail "input hash missed $change"
  fi
}
parallel_cases input_hash_case input-hash content added removed mode command unrelated other-area nix-flake

# row NAME DIR WANT_EXIT EXTRA_ENV LINE...: run `scripts/validate repo` in
# DIR under EXTRA_ENV (words of NAME=VALUE, or "") and assert its exit
# status and that each LINE is a whole line of its output. A LINE written
# !TEXT asserts instead that TEXT appears nowhere in the output.
row() {
  local name="$1" dir="$2" want_exit="$3" extra="$4" out status=0 line missing="" present=""
  shift 4
  # shellcheck disable=SC2086
  out="$(cd -- "$dir" && "${base_env[@]}" $extra bash scripts/validate "${test_area:-repo}" "${test_args[@]}" 2>&1)" || status=$?
  for line in "$@"; do
    if [[ $line == '!'* ]]; then
      ! grep -qF -e "${line:1}" <<<"$out" || present+="[${line:1}]"
    else
      grep -qxF -e "$line" <<<"$out" || missing+="[$line]"
    fi
  done
  if [[ $status == "$want_exit" && -z $missing && -z $present ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit missing=$missing present=$present"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}

row_re() {
  local name="$1" dir="$2" want_exit="$3" extra="$4" out status=0 line missing="" present=""
  shift 4
  # shellcheck disable=SC2086
  out="$(cd -- "$dir" && "${base_env[@]}" $extra bash scripts/validate "${test_area:-repo}" "${test_args[@]}" 2>&1)" || status=$?
  for line in "$@"; do
    if [[ ${line:0:1} == '!' ]]; then
      ! grep -qF -e "${line:1}" <<<"$out" || present+="[${line:1}]"
    elif [[ ${line:0:1} == '~' ]]; then
      grep -qF -e "${line:1}" <<<"$out" || missing+="[${line:1}]"
    elif [[ ${line:0:1} == '%' ]]; then
      grep -qE -e "${line:1}" <<<"$out" || missing+="[${line:1}]"
    else
      grep -qxF -e "$line" <<<"$out" || missing+="[$line]"
    fi
  done
  if [[ $status == "$want_exit" && -z $missing && -z $present ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit missing=$missing present=$present"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}

plan_case() {
  local name="$1" changed="$2" want_scope="$3" want_runs="$4" want_total="$5" out status=0 run_count skip_count
  out="$(printf '%s\0' "$changed" >"$tmp/qml-plan.paths" && VGS_VALIDATE_CHANGED="$tmp/qml-plan.paths" "$repo/scripts/test-qml-unit.sh" --plan 2>&1)" || status=$?
  run_count="$(grep -c '^run ' <<<"$out" || true)"
  skip_count="$(grep -c '^skip ' <<<"$out" || true)"
  if [[ $status == 0 ]] &&
     grep -qxF "test-qml-unit: scope=changed mutations=$want_scope" <<<"$out" &&
     [[ $run_count == "$want_runs" && $((run_count + skip_count)) == "$want_total" ]]; then
    ok "$name"
  else
    fail "$name: status=$status runs=$run_count total=$((run_count + skip_count))"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

# The mutation total, read from the table itself rather than from --plan:
# every line of the `mutations=(...)` array is one quoted row, and a line of
# another shape there means the read no longer matches the table. The floor
# names a broken read, not a short table.
qml_total="$(awk '/^mutations=\($/ { inside = 1; next } inside && /^\)$/ { inside = 0 } inside' "$repo/scripts/test-qml-unit.sh")" || qml_total=""
qml_odd="$(grep -cv '^  "[^"].*"$' <<<"$qml_total" || true)"
qml_radio_rows="$(awk -F'|' '$2 == "controls/Radio.qml" { sub(/^  "/, "", $1); print "run " $1 }' <<<"$qml_total")"
qml_radio_total="$(grep -c '^run ' <<<"$qml_radio_rows" || true)"
qml_total="$(grep -c '^  "' <<<"$qml_total" || true)"
if [[ $qml_odd != 0 || $qml_total -lt 100 ]]; then
  fail "qml mutation table read: rows=$qml_total other-lines=$qml_odd; the array read in test-validate.sh no longer matches scripts/test-qml-unit.sh"
  qml_total=unread
fi
if out="$(env -u VGS_VALIDATE_CHANGED "$repo/scripts/test-qml-unit.sh" --plan 2>&1)" &&
   grep -qxF "test-qml-unit: scope=all mutations=$qml_total/$qml_total" <<<"$out" &&
   [[ "$(grep -c '^run ' <<<"$out")" == "$qml_total" ]]; then
  ok "qml mutation planning runs every row when the changed list is unset"
else
  fail "qml mutation planning with no changed list: table rows=$qml_total"
  printf '%s\n' "$out" | sed 's/^/        /'
fi
plan_case "qml mutation planning narrows to a changed Radio target" "shell/Ui/controls/Radio.qml" "$qml_radio_total/$qml_total" "$qml_radio_total" "$qml_total"
# The target set comes from the actual table, independently of --plan.
# Keep a required Radio member so an empty extraction cannot pass.
radio_plan="$(VGS_VALIDATE_CHANGED="$tmp/qml-plan.paths" "$repo/scripts/test-qml-unit.sh" --plan 2>&1)" || radio_plan=""
if grep -qxF 'run the radio dot ignores checked' <<<"$qml_radio_rows" &&
   [[ "$(grep '^run ' <<<"$radio_plan" || true)" == "$qml_radio_rows" ]]; then
  ok "qml mutation planning includes exactly the changed Radio target rows"
else
  fail "qml mutation planning selected the wrong Radio target set"
fi
plan_case "qml mutation planning runs every row for a harness change" "scripts/qml-unit.sh" "$qml_total/$qml_total" "$qml_total" "$qml_total"
status=0
out="$(VGS_VALIDATE_CHANGED="$tmp/missing-qml-plan.paths" "$repo/scripts/test-qml-unit.sh" --plan 2>&1)" || status=$?
if [[ $status == 1 && $out == "test-qml-unit: refused: changed-list=unreadable path=$tmp/missing-qml-plan.paths" ]]; then
  ok "qml mutation planning refuses an unreadable changed list"
else
  fail "qml mutation planning unreadable list: status=$status output=$out"
fi

# A table edit runs the rows it adds or edits. A git copy of the script
# holds the shipped table as its base; each case edits the copy as a lane
# would, and the plan must run exactly the rows the case names.
q="$tmp/qml-table"
mkdir -p "$q/scripts"
cp -- "$repo/scripts/test-qml-unit.sh" "$q/scripts/test-qml-unit.sh"
"${base_env[@]}" git -C "$q" init -q
"${base_env[@]}" git -C "$q" add -A
"${base_env[@]}" git -C "$q" commit -q -m base
q_base="$("${base_env[@]}" git -C "$q" rev-parse HEAD)"
printf '%s\0' scripts/test-qml-unit.sh >"$tmp/qml-table.paths"
# table_case NAME EDIT BASE WANT-SCOPE WANT-RUNS [WANT-LINE]: EDIT names
# one change to the copy; the edit prints the label of the row it adds or
# edits, which must be the run line; BASE `-` leaves VGS_VALIDATE_BASE unset.
table_case() {
  local name="$1" edit="$2" base="$3" want_scope="$4" want_runs="$5" want_line="${6:-}" label out status=0 run_count
  local -a base_arg=()
  [[ $base == - ]] || base_arg=(VGS_VALIDATE_BASE="$base")
  "${base_env[@]}" git -C "$q" checkout -q -- scripts/test-qml-unit.sh
  label="$(python3 - "$q/scripts/test-qml-unit.sh" "$edit" <<'PY'
import sys
path, edit = sys.argv[1:]
old = open(path, encoding="utf-8").read()
lines = old.split("\n")
start = lines.index("mutations=(") + 1
label = ""
if edit == "edit-row":
    lines[start] = '  "edited ' + lines[start][3:]
    label = lines[start][3:].split("|")[0]
elif edit == "add-row":
    lines.insert(start + 1, '  "an added row|foundation/QrMatrix.qml|planted|planted|tst_qrmatrix.qml"')
    label = "an added row"
elif edit == "remove-row":
    del lines[start]
elif edit == "move-row":
    lines[start], lines[start + 1] = lines[start + 1], lines[start]
elif edit == "outside-table":
    lines.insert(start - 1, "# an edit outside the table")
elif edit == "row-shape":
    lines.insert(start + 1, "  # a line in the table that is no row")
new = "\n".join(lines)
if edit != "none" and new == old:
    sys.exit("edit=unchanged " + edit)
open(path, "w", encoding="utf-8").write(new)
print(label)
PY
)" || { fail "$name: the edit did not apply"; return; }
  out="$("${base_env[@]}" VGS_VALIDATE_CHANGED="$tmp/qml-table.paths" "${base_arg[@]}" "$q/scripts/test-qml-unit.sh" --plan 2>&1)" || status=$?
  run_count="$(grep -c '^run ' <<<"$out" || true)"
  if [[ $status == 0 && $run_count == "$want_runs" ]] &&
     grep -qxF "test-qml-unit: scope=changed mutations=$want_scope" <<<"$out" &&
     { [[ -z $label ]] || grep -qxF "run $label" <<<"$out"; } &&
     { [[ -z $want_line ]] || grep -qF -e "$want_line" <<<"$out"; }; then
    ok "$name"
  else
    fail "$name: status=$status runs=$run_count want=$want_runs label=$label"
    printf '%s\n' "$out" | grep -v '^skip ' | sed 's/^/        /'
  fi
}
if [[ $qml_total != unread ]]; then
  table_case "qml mutation planning runs an edited table row alone" edit-row "$q_base" "1/$qml_total" 1
  table_case "qml mutation planning runs an added table row alone" add-row "$q_base" "1/$((qml_total + 1))" 1
  table_case "qml mutation planning runs nothing for a removed table row" remove-row "$q_base" "0/$((qml_total - 1))" 0
  table_case "qml mutation planning runs nothing for a moved table row" move-row "$q_base" "0/$qml_total" 0
  table_case "qml mutation planning runs every row for an edit outside the table" outside-table "$q_base" "$qml_total/$qml_total" "$qml_total" "test-qml-unit: table=all reason=outside-table"
  table_case "qml mutation planning runs every row for a table line that is no row" row-shape "$q_base" "$qml_total/$qml_total" "$qml_total" "test-qml-unit: table=all reason=row-shape"
  table_case "qml mutation planning runs every row for an unreadable base" edit-row "0000000000000000000000000000000000000000" "$qml_total/$qml_total" "$qml_total" "test-qml-unit: table=all reason=base-unreadable"
  table_case "qml mutation planning runs every row with no base" edit-row - "$qml_total/$qml_total" "$qml_total" "test-qml-unit: table=all reason=base-unset"
fi

d="$tmp/clean"; fresh "$d"
trunk="$("${base_env[@]}" git -C "$d" rev-parse refs/remotes/origin/trunk)"
row "a clean tree passes against the base the settings file names" "$d" 0 "" \
  "whitespace: base=$trunk" "validate: ok"

d="$tmp/tracked"; fresh "$d"; printf 'clean \n' >"$d/clean.txt"
row "trailing whitespace in a tracked change fails" "$d" 1 "" \
  "whitespace: findings scope=tracked" "whitespace: failed base=$trunk"

# A committed defect: the feature branch holds its own commit, so HEAD is
# ahead of the merge base and only a diff from the merge base sees the line.
d="$tmp/committed"; fresh "$d"; printf 'feature \n' >"$d/feature.txt"
"${base_env[@]}" git -C "$d" add feature.txt
"${base_env[@]}" git -C "$d" commit -q -m feature
if [[ "$("${base_env[@]}" git -C "$d" rev-parse HEAD)" != "$trunk" ]]; then ok "the committed fixture's HEAD is ahead of trunk"; else fail "the committed fixture's HEAD is trunk"; fi
row "trailing whitespace in a committed change on the branch fails" "$d" 1 "" \
  "whitespace: findings scope=tracked" "whitespace: failed base=$trunk"

d="$tmp/quoted"; fresh "$d"; mkdir -p "$d/dé"; printf 'x \n' >"$d/dé/f.txt"
row "trailing whitespace in an untracked file whose name git quotes fails" "$d" 1 "" \
  "whitespace: findings scope=untracked path=dé/f.txt" "whitespace: failed base=$trunk"

d="$tmp/unreadable"; fresh "$d"; printf 'x\n' >"$d/locked.txt"; chmod 000 "$d/locked.txt"
row "an unreadable untracked file is an error, not a pass" "$d" 1 "" \
  "whitespace: unreadable scope=untracked path=locked.txt status=128" "whitespace: failed base=$trunk"

d="$tmp/no-base"; fresh "$d"
row "no resolvable base exits 77" "$d" 77 "WORKTREE_DEFAULT_BRANCH=absent" \
  "validate: status=not-measured reason=no-base missing=base-ref branch=absent remote-refs=0"

d="$tmp/orphan"; fresh "$d"; printf 'true\n' >"$d/scripts/test-orphan.sh"
row "a scripts/test-* file named by no row is refused" "$d" 1 "" \
  "validate: refused: test-without-row=scripts/test-orphan.sh"

# A suite whose name is a proper prefix of a listed one: the fixture's
# validate lists scripts/test-validate.sh, and scripts/test-validate is
# covered by no row.
d="$tmp/prefix"; fresh "$d"; printf 'true\n' >"$d/scripts/test-validate"
row "a scripts/test-* file whose name prefixes a listed suite is refused" "$d" 1 "" \
  "validate: refused: test-without-row=scripts/test-validate"

# The runtime boundary: one file planted per row, untracked unless the row
# says committed. A load of scripts/ under bin/ or shell/ is refused with the
# count and the line; prose, markdown, a scripts directory under another
# name and a file outside bin/ and shell/ pass.
runtime_cases=(
  'path.join component|bin/judge|untracked|1|const l = require(path.join(repo, "scripts", "qml-library.js"));'
  'committed path.join component|bin/judge|committed|1|const l = require(path.join(repo, "scripts", "qml-library.js"));'
  'variable expansion|bin/vgshell|untracked|1|check="$root/scripts/check-manifests.js"'
  'braced expansion|bin/tool|untracked|1|. "${repo}/scripts/lib.sh"'
  'relative climb|bin/tool|untracked|1|node "$(dirname -- "$0")/../scripts/x.js"'
  'QML import|shell/Core/X.qml|untracked|1|import "../../scripts"'
  'python component|shell/plugins/acme.p/helper.py|untracked|1|ROOT = os.path.join(HERE, '"'"'scripts'"'"', "x.py")'
  'comment naming a test|bin/judge|untracked|0|// scripts/test-plugin-logic.js runs this under node.'
  'markdown|shell/AGENTS.md|untracked|0|node reads "$root/scripts/qml-library.js".'
  'scripts under another name|shell/plugins/acme.p/Run.qml|untracked|0|property url run: Qt.resolvedUrl("helpers/scripts/run.sh")'
  'outside bin and shell|scripts/tool.sh|untracked|0|. "$root/scripts/lib.sh"'
)
test_args=(--full)
for spec in "${runtime_cases[@]}"; do
  IFS='|' read -r name file state want text <<<"$spec"
  d="$tmp/runtime-${name// /-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf '%s\n' "$text" >"$d/$file"
  if [[ $state == committed ]]; then
    "${base_env[@]}" git -C "$d" add -- "$file"
    "${base_env[@]}" git -C "$d" commit -q -m planted
  fi
  if [[ $want == 1 ]]; then
    row "a $name under $file is refused" "$d" 1 "" \
      "validate: refused: runtime-reads-scripts=1" "$file:1:$text"
  else
    row "a $name under $file passes" "$d" 0 "" "validate: the runtime loads nothing under scripts/"
  fi
done
test_args=()

d="$tmp/runtime-unreadable"; fresh "$d"; mkdir -p "$d/bin"; printf 'x\n' >"$d/bin/locked"; chmod 000 "$d/bin/locked"
row "a file under bin/ the boundary check cannot read is an error, not a pass" "$d" 1 "" \
  "validate: unreadable: runtime-reads-scripts status=1"

# The monitor-rule writer check: one file planted per row, untracked unless
# the row says committed. An `hl.monitor` call under bin/, shell/ or config/
# is refused outside the one renderer, shell/Core/MonitorLogic.js; prose that
# names it, another `hl` call and a file outside the three roots, where the
# nested test compositor's configuration lives, pass with the count of files
# read. A root that lists no file is an error.
monitor_cases=(
  'call|shell/Core/Layer.lua|untracked|1|hl.monitor({ output = "DP-1", disabled = true })'
  'committed call|shell/Core/Layer.lua|committed|1|hl.monitor({ output = "DP-1", disabled = true })'
  'rendered line in the owner|shell/Core/MonitorLogic.js|untracked|0|        return "hl.monitor({ " + fields.join(", ") + " })";'
  'spaced call|bin/vgshell-monitor-guard|untracked|1|hyprctl eval '"'"'hl.monitor ({ output = "" })'"'"
  'call in a configuration file|config/hyprland.lua|untracked|1|hl.monitor{} hl.monitor({ output = "", mode = "preferred" })'
  'comment naming the call|shell/Core/MonitorLogic.js|untracked|0|// The user sets each output with hl.monitor in hyprland.lua.'
  'window rule|shell/Core/Layer.lua|untracked|0|hl.window_rule({ name = "vgs:monitor(1)" })'
  'call outside the shipped roots|scripts/smoke/harness.sh|untracked|0|hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })'
)
for spec in "${monitor_cases[@]}"; do
  IFS='|' read -r name file state want text <<<"$spec"
  d="$tmp/monitor-${name// /-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf '%s\n' "$text" >"$d/$file"
  if [[ $state == committed ]]; then
    "${base_env[@]}" git -C "$d" add -- "$file"
    "${base_env[@]}" git -C "$d" commit -q -m planted
  fi
  # The template's three roots hold five files: one under each, and the
  # reader and its library under bin/.
  files=5
  [[ $file == scripts/* ]] || files=6
  if [[ $want == 1 ]]; then
    row "an hl.monitor $name under $file is refused" "$d" 1 "" \
      "validate: refused: monitor-rule-writer=1" "$file:1:$text"
  else
    row "a $name under $file passes" "$d" 0 "" "validate: monitor rule renderer is unique files=$files"
  fi
done

d="$tmp/monitor-no-root"; fresh "$d"
"${base_env[@]}" git -C "$d" rm -q -- config/system/udev/60-vgs-apple-displays.rules
row "a shipped root that lists no file is an error, not a pass" "$d" 1 "" \
  "validate: unreadable: monitor-rule-writer root=config files=0"

d="$tmp/monitor-unreadable"; fresh "$d"; printf 'x\n' >"$d/config/locked"; chmod 000 "$d/config/locked"
row "a file under config/ the monitor-rule writer check cannot read is an error, not a pass" "$d" 1 "" \
  "validate: unreadable: monitor-rule-writer status=1"

# The private-key check: one PEM key planted per row, header, a body marker
# and footer, untracked unless the row says committed or ignored. An ignored
# row lists tmp/ in the fixture's .gitignore. The shape is a block of three
# lines, a one-line JSON string joined by literal backslash-n, or a JS
# template literal whose header sits partway along its first line. A
# private-key header of any type is refused with the count and the header
# alone, and the body marker appears nowhere in the output; a certificate, a
# public key, a line that spells the check's pattern and an ignored key pass.
# The armor is assembled here and never written whole, so this file holds no
# header the check or a secret scanner would match.
pem_begin='-----BEGIN'
pem_end='-----END'
key_cases=(
  'private key|keys/test.pem|untracked|1|PRIVATE KEY|block'
  'committed private key|keys/committed.pem|committed|1|PRIVATE KEY|block'
  'RSA private key|id_rsa|untracked|1|RSA PRIVATE KEY|block'
  'OpenSSH private key|shell/plugins/acme.p/key|untracked|1|OPENSSH PRIVATE KEY|block'
  'PGP private key block|docs/key.asc|untracked|1|PGP PRIVATE KEY BLOCK|block'
  'one-line JSON private key|keys/service-account.json|untracked|1|PRIVATE KEY|json'
  'private key partway along a line|scripts/fixture.js|untracked|1|PRIVATE KEY|inline'
  'certificate|keys/cert.pem|untracked|0|CERTIFICATE|block'
  'public key|keys/key.pub|untracked|0|PUBLIC KEY|block'
  'line naming the pattern|notes.txt|untracked|0|[A-Z ]*PRIVATE KEY( BLOCK)?|block'
  'git-ignored private key|tmp/key.pem|ignored|0|PRIVATE KEY|block'
)
test_args=(--full)
for spec in "${key_cases[@]}"; do
  IFS='|' read -r name file state want type shape <<<"$spec"
  d="$tmp/key-${name// /-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  header="$pem_begin $type-----"
  footer="$pem_end $type-----"
  case "$shape" in
    block) printf '%s\nBODYMARKER\n%s\n' "$header" "$footer" ;;
    json) printf '{"private_key": "%s\\nBODYMARKER\\n%s\\n"}\n' "$header" "$footer" ;;
    inline) printf 'const KEY = `%s\nBODYMARKER\n%s`;\n' "$header" "$footer" ;;
    *) echo "test-validate: key-case shape=$shape unknown" >&2; exit 1 ;;
  esac >"$d/$file"
  case "$state" in
    untracked) ;;
    committed)
      "${base_env[@]}" git -C "$d" add -- "$file"
      "${base_env[@]}" git -C "$d" commit -q -m planted ;;
    ignored) printf 'tmp/\n' >"$d/.gitignore" ;;
    *) echo "test-validate: key-case state=$state unknown" >&2; exit 1 ;;
  esac
  if [[ $want == 1 ]]; then
    row "a $name in $file is refused" "$d" 1 "" \
      "validate: refused: private-key=1" "$file:1:$header" '!BODYMARKER'
  else
    row "a $name in $file passes" "$d" 0 "" "validate: no private key in the tree"
  fi
done
test_args=()

d="$tmp/key-unreadable"; fresh "$d"; printf 'x\n' >"$d/locked.pem"; chmod 000 "$d/locked.pem"
row "a file the private-key check cannot read is an error, not a pass" "$d" 1 "" \
  "validate: unreadable: private-key status=1"

# A fresh repository whose feature branch commits a copy of the product
# tree, so a row diffed against HEAD judges only what it plants.
product_fixture() {
  local dir="$1"
  fresh "$dir"
  cp -R "$repo/scripts/." "$dir/scripts/"
  cp -R "$repo/shell" "$repo/bin" "$repo/config" "$repo/themes" "$repo/packaging" "$dir/"
  cp -- "$repo/VERSION" "$repo/LICENSE" "$repo/README.md" "$dir/"
  # The token check walks the skill templates beside the shell tree.
  mkdir -p "$dir/.agents/skills/vgs-plugin"
  cp -R "$repo/.agents/skills/vgs-plugin/templates" "$dir/.agents/skills/vgs-plugin/"
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m product
}

# Exercise the real manifest rows, including the static smoke fixtures. The
# checker controls run unchanged; this control proves validate includes the
# fixture tree, so removing that row makes the planted defect pass wrongly.
d="$tmp/smoke-fixtures"; product_fixture "$d"
test_area=manifests
test_args=(--full)
row "the smoke fixtures pass the offline manifest area" "$d" 0 "" "validate: ok"
python3 - "$d/scripts/smoke/fixtures/plugins/acme.tick/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as source:
    manifest = json.load(source)
manifest["schemaVersion"] = 0
with open(path, "w") as target:
    json.dump(manifest, target)
PY
test_args=(--changed HEAD)
row "a broken smoke fixture manifest fails the offline manifest area" "$d" 1 "" \
  "validate: failed=smoke fixture manifests (exit 1)"
test_args=()

# Selection is checked through the command the caller will run. Expected
# plans name consumers independently of the dependency table under test.
repo_plan=$'whitespace_check\nrows_cover_tests\nruntime_reads_no_scripts\nruntime_writes_monitor_rule_once\nprivate_keys_check\nmd_refs_check'
text_plan=$'python3 scripts/check-user-commands.py\nwhitespace_check\nmd_refs_check\ndoc_limits_check'
install_plan=$'scripts/test-install-tree.sh\n'"$repo_plan"
installer_plan=$'scripts/test-install-tree.sh\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-vgshell-self.sh\nscripts/test-install-sh.sh\nscripts/test-release.sh\n'"$repo_plan"
# The README check reads VERSION, bin/vgshell, install.sh, the Arch recipes,
# the plugins, README.md and docs/architecture/runtime.md.
readme_rows=$'node scripts/test-check-readme.js\nscripts/test-readme-install.sh\n'
readme_rows_trimmed="${readme_rows%$'\n'}"
curl_installer_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-install-sh.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
heap_plan=$'python3 scripts/test-attribute-heap-profile.py\n'"$repo_plan"
jarvis_local_rows=$'python3 scripts/test-jarvis-local.py\nscripts/check-jarvis-local.sh\n'
jarvis_local_tools_plan=$'python3 scripts/check-readme-images.py\npython3 scripts/test-jarvis-local.py\npython3 scripts/test-jarvis-setup.py\nscripts/check-jarvis-local.sh\npython3 scripts/test-jarvis-local-speech.py\nscripts/check-jarvis-local-speech.sh\nscripts/test-jarvis-selftest.sh'$'\nscripts/test-validate.sh'
jarvis_env_plan=$'node scripts/test-jarvis-env.js\n'"$repo_plan"
jarvis_helper_plan=$'node scripts/test-jarvis-env.js\npython3 scripts/test-jarvis-local.py\npython3 scripts/test-jarvis-setup.py\nscripts/check-jarvis-local.sh\npython3 scripts/test-jarvis-local-speech.py\nscripts/check-jarvis-local-speech.sh\n'"$repo_plan"
jarvis_policy_rows=$'node scripts/test-jarvis-tools.js\nnode scripts/test-jarvis-policy.js\nnode scripts/test-jarvis-redact.js\nnode scripts/test-jarvis-release.js\nnode scripts/test-jarvis-net.js\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-elevenlabs.js\nnode scripts/test-jarvis-denied.js\nnode scripts/test-jarvis-home.js\nnode scripts/test-jarvis-home-repair.js\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-audit.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-mcp.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex-protocol.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot-protocol.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-child.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\n'
jarvis_audio_rows=$'node scripts/test-jarvis-audio.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-playback.js\nnode scripts/test-jarvis-playback-pipewire.js\n'
jarvis_accounts_rows=$'node scripts/test-jarvis-accounts.js\nnode scripts/test-jarvis-accounts-tui.js\nnode scripts/test-jarvis-account-verify.js\n'
jarvis_secrets_plan=$'node scripts/test-jarvis-net.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows$repo_plan"
# The world helper also selects the local speech adapter beside the audio rows.
jarvis_world_audio_rows="${jarvis_audio_rows/test-jarvis-engine.js$'\n'/test-jarvis-engine.js$'\n'node scripts/test-jarvis-local-speech.js$'\n'}"
jarvis_owner_plan="$jarvis_policy_rows"$'node scripts/test-jarvis-tasks.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_world_audio_rows"$'node scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\nnode scripts/test-jarvis-claude-task.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$jarvis_helper_plan"
jarvis_daemon_plan=$'node scripts/test-jarvis-daemon.js\n'"$repo_plan"
jarvis_live_plan=$'node scripts/test-jarvis-live.js\n'"$repo_plan"
jarvis_fixture_plan=$'node scripts/test-jarvis-protocol.js\nnode scripts/test-jarvis-tasks.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\nnode scripts/test-jarvis-claude-task.js\n'"$jarvis_env_plan"
jarvis_guidance_plan=$'node scripts/test-jarvis-guidance.js\n'"$repo_plan"
jarvis_speakable_plan=$'node scripts/test-jarvis-speakable.js\n'"$repo_plan"
jarvis_language_plan=$'node scripts/test-jarvis-guidance.js\nnode scripts/test-jarvis-speakable.js\nnode scripts/test-jarvis-speech-language.js\n'"$repo_plan"
keyboard_rows=$'python3 scripts/check-keyboard.py shell\npython3 scripts/test-check-keyboard.py\n'
keyboard_check=$'python3 scripts/check-keyboard.py shell\n'
dispatch_plan=$'node scripts/test-input-facts.js\nnode scripts/test-dispatch.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\npython3 scripts/test-capture.py\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check"$'scripts/test-sandbox-shots.sh\n'"$repo_plan"$'\nscripts/test-validate.sh'
session_plan=$'node scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check$repo_plan"$'\nscripts/test-validate.sh\nscripts/test-keyboard-ui.sh\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh\nscripts/test-session-lock.sh\nscripts/test-flake.sh\nscripts/qml-smoke.sh'
fixture_plan=$'node bin/lib/check-manifests.js --base scripts/smoke/fixtures/plugins\npython3 scripts/check-plugin-boundary.py --shell scripts/smoke/fixtures\npython3 scripts/check-design-tokens.py\nsmoke_reads_named\n'"$repo_plan"$'\nscripts/test-validate.sh\nscripts/qml-smoke.sh'
smoke_plan=$'python3 scripts/check-smoke-readers.py\npython3 scripts/test-check-smoke-readers.py\npython3 scripts/check-smoke-terminal.py\npython3 scripts/test-check-smoke-terminal.py\npython3 scripts/check-smoke-hidden.py\npython3 scripts/test-check-smoke-hidden.py\nsmoke_reads_named\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
jarvis_key_plan="${smoke_plan/smoke_reads_named/$'smoke_reads_named\npython3 scripts/test-smoke-user-config.py'}"
orb_shader_plan=$'scripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-voiceorb-shader.py\npython3 scripts/test-check-voiceorb-shader.py\npython3 scripts/test-measure-shader.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_rows$repo_plan"$'\nscripts/test-validate.sh\nscripts/test-keyboard-ui.sh\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh\nnode scripts/test-key-labels.js\nscripts/test-flake.sh\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
orb_check_plan=$'python3 scripts/check-voiceorb-shader.py\npython3 scripts/test-check-voiceorb-shader.py\npython3 scripts/test-measure-shader.py\n'"$repo_plan"
shader_measure_plan=$'python3 scripts/test-measure-shader.py\n'"$repo_plan"$'\nscripts/measure-shader.sh'
keyboard_plan=$'smoke_reads_named\n'"$repo_plan"$'\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
fedora_plan=$'scripts/test-fedora-srpm.sh\n'
version_plan=$'scripts/test-vgshell-version.sh\nscripts/test-install-tree.sh\n'"$fedora_plan"$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nnode scripts/test-engine-availability.js\n'"$readme_rows"$'scripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
# A recipe change runs the recipe check and its controls, never the product
# smoke; the container build runs only where the area admits it, never
# offline.
recipe_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-publish-aur.sh\n'"$repo_plan"
# An Arch recipe is also the README's source for the AUR commands.
# The release suite's parity rows build the Arch recipes' host side.
arch_recipe_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-vgshell-requirements.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
# The package review reads each recipe's .SRCINFO for the packages VGS publishes.
arch_srcinfo_plan=$'scripts/test-updates-pipeline.sh\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-vgshell-requirements.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\nscripts/test-vgshell-pkg-run.sh\n'"$repo_plan"
settings_core_prefix=$'node scripts/test-tailscale-logic.js\nnode scripts/test-vpn-logic.js\nnode scripts/test-plugin-logic.js\nnode scripts/test-pads.js\nnode scripts/test-plugin-status.js\nnode scripts/test-plugin-menu.js\nnode scripts/test-key-capture.js\nnode scripts/test-tui-logic.js\nnode scripts/test-ipc-logic.js\nnode scripts/test-notice-logic.js\nnode scripts/test-hyprland-layer.js\nnode scripts/test-hyprland-state.js\nnode scripts/test-input-facts.js\n'
settings_theme_rows=$'bin/vgshell-theme-judge packages themes\n'
settings_plugin_rows=$'node scripts/test-launcher-model.js\nnode scripts/test-themes-setup.js\nnode scripts/test-notifications-logic.js\nnode scripts/test-greeter-logic.js\nnode scripts/test-polkit-model.js\nnode scripts/test-bluetooth-logic.js\nnode scripts/test-displays-logic.js\nnode scripts/test-screensaver-logic.js\n'
# The package table is also an input of the updates logic row, whose judge
# imports it.
settings_package_rows="${settings_plugin_rows/$'node scripts/test-displays-logic.js\n'/$'node scripts/test-updates-logic.js\nnode scripts/test-displays-logic.js\n'}"
settings_catalog_rows=$'node scripts/test-check-devtools-catalog.js\n'
settings_reply_row='node scripts/test-settings-reply.js'
settings_steps_row='node scripts/test-settings-steps.js'
settings_warden_row=$'node scripts/test-agent-warden-logic.js\n'
settings_debug_row=$'node scripts/test-agent-debug.js\n'
settings_devtools_row=$'\nnode scripts/test-devtools-view.js'
cases=(
  "notifications-app-sounds|shell/plugins/vgs.notifications/AppSounds.qml|logic|node scripts/test-notifications-logic.js"
  "notifications-sound-rule|shell/plugins/vgs.notifications/SoundRule.qml|logic|node scripts/test-notifications-logic.js"
  "notifications-service-status|shell/plugins/vgs.notifications/Service.qml|logic|node scripts/test-plugin-status.js"$'\nnode scripts/test-notifications-logic.js'
  "notifications-card-exit|shell/plugins/vgs.notifications/CardSlot.qml|logic|node scripts/test-notifications-logic.js"
  "displays-vrr-setting|shell/plugins/vgs.displays/manifest.json|logic|node scripts/test-plugin-logic.js"$'\nnode scripts/test-displays-logic.js'
  "power-logic|shell/plugins/vgs.power/PowerLogic.js|logic|node scripts/test-power-logic.js"
  "power-overlay-logic|shell/plugins/vgs.power/Overlay.qml|logic|node scripts/test-power-logic.js"
  "sysmon-logic|shell/plugins/vgs.sysmon/SysmonLogic.js|logic|node scripts/test-sysmon-logic.js"
  "voice-start-service|shell/plugins/vgs.voice/Service.qml|logic|node scripts/test-voice-logic.js"
  "voice-microphone|shell/plugins/vgs.voice/Widget.qml|logic|node scripts/test-voice-logic.js"
  "screensaver-manifest|shell/plugins/vgs.screensaver/manifest.json|logic|node scripts/test-plugin-logic.js"$'\nnode scripts/test-screensaver-logic.js'
  "duration-shared|shell/Commons/Duration.js|logic|node scripts/test-duration.js"$'\nnode scripts/test-timestamp.js\nnode scripts/test-updates-logic.js\nnode scripts/test-automations-logic.js\nnode scripts/test-automations-view-logic.js\nnode scripts/test-agent-warden-view.js\nnode scripts/test-agent-warden-notices.js\nnode scripts/test-google-drive-logic.js'
  "nmcli-shared|shell/Commons/Nmcli.js|logic|node scripts/test-network-logic.js"$'\nnode scripts/test-vpn-logic.js'
  "vpn-fixture|scripts/fixtures/vpn/list.txt|logic|text:"
  "vpn-import|shell/plugins/vgs.vpn/tui/import.sh|cli|scripts/test-vpn-import.sh"$'\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"$'\nscripts/test-tui-gum-colours.sh'
  "network-logic|shell/plugins/vgs.network/NetworkLogic.js|logic|node scripts/test-network-logic.js"
  "network-body|shell/plugins/vgs.network/NetworkBody.qml|logic|node scripts/test-network-logic.js"
  "network-share|shell/plugins/vgs.network/bin/share-qr|logic|python3 scripts/test-network-share.py"
  "network-join|shell/plugins/vgs.network/bin/join-network|logic|scripts/test-network-enterprise.sh"
  "devtools-window|shell/plugins/vgs.devtools/Window.qml|logic|node scripts/test-devtools-view.js"
  "devtools-service|shell/plugins/vgs.devtools/Service.qml|logic|node scripts/test-devtools-view.js"
  "settings-reply-window|shell/plugins/vgs.settings/Window.qml|logic|node scripts/test-settings-reply.js"
  "settings-reply-page|shell/plugins/vgs.settings/PluginPage.qml|logic|"$'node scripts/test-jarvis-setup-gate.js\nnode scripts/test-settings-reply.js'
  "settings-reply-input|shell/Commons/Reply.js|logic|node scripts/test-settings-reply.js"
  "settings-reply-suite|scripts/test-settings-reply.js|logic|node scripts/test-settings-reply.js"
  "settings-steps-input|shell/plugins/vgs.settings/Steps.js|logic|node scripts/test-bluetooth-logic.js"$'\nnode scripts/test-screensaver-logic.js\nnode scripts/test-jarvis-setup-gate.js\n'"$settings_warden_row$settings_steps_row"
  "settings-steps-suite|scripts/test-settings-steps.js|logic|$settings_steps_row"
  "settings-reply-key-label|shell/Ui/controls/BindField.qml|logic|$settings_reply_row"
  "settings-reply-launcher|shell/plugins/vgs.launcher/Service.qml|logic|$settings_reply_row"
  "settings-reply-probe|scripts/smoke/Probe.qml|logic|$settings_reply_row"
  "settings-reply-shots|scripts/sandbox-shots.sh|logic|$settings_reply_row"
  "settings-reply-fixture|scripts/smoke/fixtures/plugins/acme.hyprland/manifest.json|logic|$settings_reply_row"
  "settings-reply-layer-binding|shell/Core/HyprlandLayer.qml|logic|"$'node scripts/test-hyprland-layer.js\n'"$settings_reply_row"
  "settings-reply-producer|shell/Core/PluginLogic.js|logic|$settings_core_prefix$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_warden_row$settings_debug_row$settings_reply_row"$'\n'"$settings_steps_row$settings_devtools_row"$'\nnode scripts/test-voice-logic.js'
  "settings-reply-layer|shell/Core/HyprlandLayer.js|logic|$settings_core_prefix"$'node scripts/test-dispatch.js\n'"$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_warden_row$settings_debug_row$settings_reply_row"$'\n'"$settings_steps_row$settings_devtools_row"
  "settings-reply-values|shell/Commons/SettingValues.js|logic|$settings_core_prefix"$'node scripts/test-setting-values.js\n'"$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_warden_row$settings_debug_row$settings_reply_row"$'\n'"$settings_steps_row$settings_devtools_row"
  "settings-reply-packages|shell/Core/PackageManagers.js|logic|$settings_core_prefix$settings_theme_rows$settings_package_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_catalog_rows$settings_warden_row$settings_debug_row$settings_reply_row"$'\n'"$settings_steps_row$settings_devtools_row"
  "settings-reply-icons|shell/Ui/icons/Lucide.js|logic|$settings_core_prefix"$'node scripts/test-icon-bounds.js\n'"$settings_theme_rows"$'node scripts/test-lucide-data.js\n'"$settings_plugin_rows"$'node scripts/test-jarvis-widget.js\nnode scripts/test-jarvis-setup-gate.js\n'"$settings_catalog_rows$settings_warden_row$settings_debug_row"$'node scripts/test-agent-warden-view.js\n'"$settings_reply_row"$'\n'"$settings_steps_row$settings_devtools_row"
  "catalog-judge|themes/catalog/index.json|tools|catalog_wallpaper_names"$'\nnode scripts/test-vgshell-theme-judge.js'
  "catalog-contrast|themes/catalog/index.json|logic|"$'node scripts/test-hyprland-layer.js\nnode scripts/test-theme-logic.js\n'"$settings_theme_rows"$'node scripts/test-check-theme-contrast.js\nnode scripts/test-theme-render.js'
  "orb-source|shell/Ui/feedback/shaders/voiceorb.frag|all|$orb_shader_plan"
  "orb-pack|shell/Ui/feedback/shaders/voiceorb.frag.qsb|all|$orb_shader_plan"
  "orb-compiler|scripts/check-voiceorb-shader.py|offline|$orb_check_plan"
  "shader-instrument|scripts/measure-shader.sh|all|python3 scripts/test-measure-shader.py"$'\nscripts/test-gpu-fence.sh\n'"$repo_plan"$'\nscripts/measure-shader.sh'
  "shader-reader|scripts/shader/readings.py|all|$shader_measure_plan"
  "shader-ceilings|scripts/shader/ceilings.json|all|$shader_measure_plan"
  "shader-scene|scripts/shader/Scene.qml|all|$shader_measure_plan"
  "shader-tests|scripts/test-measure-shader.py|offline|python3 scripts/test-measure-shader.py"$'\n'"$repo_plan"
  "keyboard-source|scripts/smoke/keyboard/keyboard.c|all|$keyboard_plan"
  "keyboard-protocol|scripts/smoke/keyboard/virtual-keyboard-unstable-v1.xml|all|$keyboard_plan"
  "device-fakes-harness|scripts/smoke/devices.sh|all|python3 scripts/check-smoke-readers.py"$'\npython3 scripts/test-check-smoke-readers.py\nsmoke_reads_named\nscripts/test-sandbox-shots.sh\nscripts/test-jarvis-selftest.sh\n'"$repo_plan"$'\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
  "device-fakes-fixture|scripts/smoke/fixtures/devices/stand-in.py|all|python3 scripts/test-displays-brightness.py"$'\n'"$fixture_plan"$'\nscripts/measure-shader.sh'
  "docs|docs/architecture/overview.md|offline|text:$text_plan"
  "runtime-doc|docs/architecture/runtime.md|offline|text:$text_plan"
  "docs-html|docs/guide.html|offline|$repo_plan"$'\ndoc_limits_check'
  "root-markdown|NOTES.md|offline|text:$text_plan"
  "real-root-readme|README.md|all|text:$text_plan"
  "real-plugin-readme|shell/plugins/vgs.keyboard/README.md|all|text:$text_plan"
  "real-displayed-text|shell/plugins/vgs.screensaver/logo.txt|all|text:python3 scripts/check-user-commands.py"$'\nwhitespace_check\nmd_refs_check'
  "version|VERSION|offline|$version_plan"
  "licence|LICENSE|all|text:python3 scripts/check-user-commands.py"$'\nwhitespace_check\nmd_refs_check'
  "flake|flake.nix|all|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nnode scripts/check-packaging.js --engine-availability\nnode scripts/test-engine-availability.js\nscripts/test-publish-aur.sh\n'"$repo_plan"$'\nscripts/test-flake.sh'
  "flake-offline|flake.nix|offline|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nnode scripts/test-engine-availability.js\nscripts/test-publish-aur.sh\n'"$repo_plan"
  "installer|packaging/install-system.sh|offline|$installer_plan"
  "portal-config|packaging/xdg-desktop-portal/hyprland-portals.conf|offline|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\n'"$repo_plan"
  "curl-installer|install.sh|offline|$curl_installer_plan"
  "recipe|packaging/arch/vgshell/PKGBUILD|offline|$arch_recipe_plan"
  "curl-installer-srcinfo|packaging/arch/vgshell/.SRCINFO|offline|scripts/test-updates-pipeline.sh"$'\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-vgshell-requirements.sh\nscripts/test-install-sh.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\nscripts/test-vgshell-pkg-run.sh\n'"$repo_plan"
  "recipe-all|packaging/arch/vgshell-git/.SRCINFO|all|$arch_srcinfo_plan"$'\nscripts/arch-packages.sh'
  "debian-recipe|packaging/debian/vgshell-quickshell/control|cli|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nnode scripts/check-packaging.js --engine-availability\nnode scripts/test-engine-availability.js\nscripts/test-release.sh'
  "debian-builder|scripts/debian-packages.sh|cli|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nnode scripts/check-packaging.js --engine-availability\nnode scripts/test-engine-availability.js\nscripts/test-release.sh'
  "debian-package|packaging/debian/vgshell-quickshell/rules|package|scripts/debian-packages.sh"
  "recipe-package|packaging/arch/vgshell/PKGBUILD|package|scripts/arch-packages.sh"
  # The plugin logic table holds the core's sound table to the files.
  "sound-file|shell/assets/sounds/pop.wav|logic|node scripts/test-plugin-logic.js"
  "requirements|config/requirements.json|offline|node scripts/test-plugin-logic.js"$'\nscripts/test-install-tree.sh\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-vgshell-requirements.sh\nscripts/test-install-sh.sh\nscripts/test-publish-aur.sh\npython3 scripts/check-user-commands.py\npython3 scripts/test-check-user-commands.py\n'"$repo_plan"
  "install-manifest|packaging/install-tree.manifest|offline|scripts/test-install-tree.sh"$'\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"$'\nscripts/test-validate.sh'
  "fedora-recipe|packaging/fedora/vgshell.spec|all|$fedora_plan"$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-install-sh.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
  "copr-entry|.copr/Makefile|all|scripts/test-fedora-srpm.sh"$'\n'"$repo_plan"
  # test-validate.sh runs the mutation planner of the QML unit controls.
  "qml-unit-planner|scripts/test-qml-unit.sh|tools|scripts/test-validate.sh"
  "copied-shell-profile|shell/plugins/vgs.vpn/ProfileRow.qml|tools|python3 scripts/check-readme-images.py"$'\nscripts/test-validate.sh'
  "copied-shell-core|shell/Core/Dispatch.js|tools|scripts/test-sandbox-shots.sh"$'\nscripts/test-validate.sh'
  "copied-shell-ui|shell/Ui/controls/Label.qml|tools|scripts/test-validate.sh"
  "heap|scripts/attribute-heap-profile.py|offline|$heap_plan"
  "suite|scripts/test-attribute-heap-profile.py|offline|$heap_plan"
  "jarvis-env|scripts/lib/jarvis-env.sh|all|node scripts/check-jarvis-words.js"$'\n'"$jarvis_owner_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-env-suite|scripts/test-jarvis-env.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_env_plan"
  "jarvis-env-fixture|scripts/fixtures/jarvis-env/probe.py|all|node scripts/check-jarvis-words.js"$'\n'"$jarvis_env_plan"
  "jarvis-daemon-suite|scripts/test-jarvis-daemon.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_daemon_plan"
  "jarvis-secrets-suite|scripts/test-jarvis-secrets.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-secrets.js"$'\n'"$repo_plan"
  "jarvis-key-tui-fixture|scripts/fixtures/jarvis/key-tui.py|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\n'"$repo_plan"
  "jarvis-key-fixture|scripts/fixtures/jarvis/keys-world.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_env_plan"
  "jarvis-task-suite|scripts/test-jarvis-tasks.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-tasks.js"$'\n'"$repo_plan"
  "jarvis-audio-task-input|shell/plugins/vgs.jarvis/backend/Tasks.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\nnode scripts/test-jarvis-claude-task.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "task-event-suite|scripts/test-task-event.js|offline|node scripts/test-task-event.js"$'\n'"$repo_plan"
  "task-event-prefix|scripts/test-task-event.js|all|node scripts/test-task-event.js"$'\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-audio-suite|scripts/test-jarvis-audio.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-audio.js"$'\n'"$repo_plan"
  "jarvis-engine-suite|scripts/test-jarvis-engine.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-engine.js"$'\n'"$repo_plan"
  "jarvis-engine-input|shell/plugins/vgs.jarvis/backend/ChainedEngine.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-engine-fixture|scripts/fixtures/jarvis/engine.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-claude.js"$'\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-brain-frames|scripts/fixtures/jarvis-brain/openai-chat-frames.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-audio-daemon-suite|scripts/test-jarvis-audio-daemon.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-audio-daemon.js"$'\n'"$repo_plan"
  "jarvis-playback-suite|scripts/test-jarvis-playback.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-playback.js"$'\n'"$repo_plan"
  "jarvis-pipewire-suite|scripts/test-jarvis-playback-pipewire.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-playback-pipewire.js"$'\n'"$repo_plan"
  "jarvis-playback-fixture|scripts/fixtures/jarvis/playback.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-playback.js\nnode scripts/test-jarvis-playback-pipewire.js\n'"$repo_plan"
  "jarvis-playback-config|scripts/fixtures/jarvis/playback.conf|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-playback-pipewire.js\n'"$repo_plan"
  "jarvis-audio-fixture|scripts/fixtures/jarvis/audio-tool.py|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\n'"$jarvis_audio_rows$repo_plan"
  "jarvis-accounts-suite|scripts/test-jarvis-accounts.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-accounts.js"$'\n'"$repo_plan"
  "jarvis-sign-in-terminal|shell/plugins/vgs.jarvis/tui/sign-in.sh|cli|node scripts/test-jarvis-files.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\nnode scripts/test-jarvis-accounts-tui.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"$'\nscripts/test-tui-gum-colours.sh'
  "jarvis-accounts-tui-suite|scripts/test-jarvis-accounts-tui.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-accounts-tui.js"$'\n'"$repo_plan"
  "jarvis-account-verify-suite|scripts/test-jarvis-account-verify.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-account-verify.js"$'\n'"$repo_plan"
  "jarvis-accounts-fixture|scripts/fixtures/jarvis/accounts-world.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\n'"$jarvis_accounts_rows$jarvis_env_plan"
  "jarvis-accounts-terminal-fixture|scripts/fixtures/jarvis/accounts-tui.py|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-browser-setup.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-accounts-tui.js\n'"$repo_plan"
  "jarvis-fixture|scripts/fixtures/jarvis/prepare.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_fixture_plan"
  "jarvis-scripted-fixture|scripts/fixtures/jarvis/scripted.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-protocol.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\n'"$repo_plan"
  "jarvis-bubble-input|shell/plugins/vgs.jarvis/Bubble.qml|qml|scripts/qml-smoke.sh"
  "jarvis-bubble-row|scripts/smoke/rows/jarvis-bubble.sh|qml|scripts/qml-smoke.sh"
  "jarvis-fixture-all|scripts/fixtures/jarvis/prepare.js|all|node scripts/check-jarvis-words.js"$'\n'"$jarvis_fixture_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-protocol-suite|scripts/test-jarvis-protocol.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-protocol.js"$'\n'"$repo_plan"
  "jarvis-local-suite|scripts/test-jarvis-local.py|all|node scripts/check-jarvis-words.js"$'\n'"python3 scripts/test-jarvis-local.py"$'\n'"$repo_plan"
  "jarvis-setup-suite|scripts/test-jarvis-setup.py|all|node scripts/check-jarvis-words.js"$'\n'"python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "jarvis-setup-probe-fixture|scripts/fixtures/jarvis-setup/installed-probe.py|all|node scripts/check-jarvis-words.js"$'\n'"python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "install-tree-suite|scripts/test-install-tree.sh|all|node scripts/test-jarvis-browser-setup.js"$'\nscripts/test-install-tree.sh'$'\npython3 scripts/test-jarvis-setup.py\n'"$repo_plan"
  "jarvis-setup-fixture|scripts/fixtures/jarvis-setup/installer.py|all|node scripts/check-jarvis-words.js"$'\n'"python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "jarvis-setup-status-fixture|scripts/fixtures/jarvis-setup/status.py|all|node scripts/check-jarvis-words.js"$'\n'"python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-setup-installed-fixture|scripts/fixtures/jarvis-setup/installed.py|all|node scripts/check-jarvis-words.js"$'\n'"scripts/test-install-tree.sh"$'\npython3 scripts/test-jarvis-setup.py\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-local-runner|scripts/check-jarvis-local.sh|all|node scripts/check-jarvis-words.js"$'\n'"$jarvis_local_rows$repo_plan"
  "jarvis-local-fixture|scripts/fixtures/jarvis-local/run.py|all|node scripts/check-jarvis-words.js"$'\n'"$jarvis_local_rows$repo_plan"
  "jarvis-artifacts|shell/plugins/vgs.jarvis/artifacts.json|tools|$jarvis_local_tools_plan"
  "jarvis-artifacts-engine|shell/plugins/vgs.jarvis/artifacts.json|cli|node scripts/test-jarvis-files.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-local-speech.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-measure|shell/plugins/vgs.jarvis/measure-local|tools|$jarvis_local_tools_plan"
  "jarvis-clip|shell/plugins/vgs.jarvis/fixtures/probe.wav|tools|$jarvis_local_tools_plan"
  "jarvis-daemon-not-local-models|shell/plugins/vgs.jarvis/backend/jarvisd.js|tools|python3 scripts/check-readme-images.py"$'\npython3 scripts/test-jarvis-local.py\nscripts/test-jarvis-selftest.sh\nscripts/test-validate.sh'
  "jarvis-mailbox-reader|.agents/skills/mailbox/scripts/lane-mail|tools|scripts/test-jarvis-selftest.sh"
  "jarvis-mailbox-library|.agents/skills/mailbox/scripts/lib/lane-mail-store.py|tools|scripts/test-jarvis-selftest.sh"
  "jarvis-workflow-state|.agents/skills/orch/scripts/workflow-state|tools|scripts/test-jarvis-selftest.sh"
  "jarvis-browser-daemon-input|shell/plugins/vgs.jarvis/backend/jarvisd.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-suite|scripts/test-jarvis-browser.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"$repo_plan"
  "jarvis-browser-setup-suite|scripts/test-jarvis-browser-setup.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-browser-setup.js"$'\n'"$repo_plan"
  "jarvis-input-owner|shell/plugins/vgs.jarvis/backend/Input.js|cli|node scripts/test-jarvis-input.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-computer-help|shell/plugins/vgs.jarvis/backend/ComputerHelp.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-input-help|shell/plugins/vgs.jarvis/backend/skills/computer/input.md|cli|text:"
  "jarvis-browser-input|shell/plugins/vgs.jarvis/backend/Browser.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-setup-input|shell/plugins/vgs.jarvis/backend/browser-setup.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-browser-setup.js"$'\nnode scripts/test-jarvis-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-fixture|scripts/fixtures/jarvis/browser.py|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-daemon.js\n'"$repo_plan"
  "jarvis-words-scanned-test|scripts/test-jarvis-setup.py|logic|node scripts/check-jarvis-words.js"
  "jarvis-words-scanned-doc|docs/architecture/jarvis.md|logic|text:"
  "jarvis-tools-suite|scripts/test-jarvis-tools.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-tools.js"$'\n'"$repo_plan"
  "jarvis-policy-suite|scripts/test-jarvis-policy.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-policy.js"$'\n'"$repo_plan"
  "jarvis-release-suite|scripts/test-jarvis-release.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-release.js"$'\n'"$repo_plan"
  "jarvis-net-suite|scripts/test-jarvis-net.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-net.js"$'\n'"$repo_plan"
  "jarvis-sse-suite|scripts/test-jarvis-sse.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-sse.js"$'\n'"$repo_plan"
  "jarvis-providers-suite|scripts/test-jarvis-providers.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-providers.js"$'\n'"$repo_plan"
  "jarvis-brain-suite|scripts/test-jarvis-brain-openai.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-openai.js"$'\n'"$repo_plan"
  "jarvis-brain-scripts|scripts/fixtures/jarvis-brain/openai-chat-scripts.json|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-brain-schema|scripts/fixtures/jarvis-brain/openai-chat.schema.json|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-anthropic-suite|scripts/test-jarvis-brain-anthropic.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-anthropic-scripts|scripts/fixtures/jarvis-brain/anthropic-messages-scripts.json|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-anthropic-schema|scripts/fixtures/jarvis-brain/anthropic-messages.schema.json|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-live-suite|scripts/test-jarvis-live.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_live_plan"
  "jarvis-live-scripts|scripts/fixtures/jarvis-live/realtime-scripts.json|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_live_plan"
  "jarvis-live-schema|scripts/fixtures/jarvis-live/realtime.schema.json|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_live_plan"
  "jarvis-live-input|shell/plugins/vgs.jarvis/backend/Realtime.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-websocket-fixture|scripts/fixtures/jarvis/websocket.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-live.js\n'"$jarvis_daemon_plan"
  "jarvis-session-cli|shell/plugins/vgs.jarvis/Session.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_audio_rows"$'node scripts/test-jarvis-claude-task.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "schema-check-suite|scripts/test-schema-check.js|offline|node scripts/test-schema-check.js"$'\n'"$repo_plan"
  "schema-check|scripts/fixtures/schema-check.js|offline|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-mcp.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex-protocol.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot-protocol.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-sse-input|shell/plugins/vgs.jarvis/backend/Sse.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-sse.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-sse-cli-input|shell/plugins/vgs.jarvis/backend/Sse.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-providers-input|shell/plugins/vgs.jarvis/backend/Providers.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-providers.js"
  "jarvis-brain-input|shell/plugins/vgs.jarvis/backend/OpenAIChat.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-wire-input|shell/plugins/vgs.jarvis/backend/WireBrain.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-anthropic-input|shell/plugins/vgs.jarvis/backend/AnthropicMessages.js|cli|node scripts/test-jarvis-brain-anthropic.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-denied-suite|scripts/test-jarvis-denied.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-denied.js"$'\n'"$repo_plan"
  "jarvis-redact-suite|scripts/test-jarvis-redact.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-redact.js"$'\n'"$repo_plan"
  "jarvis-owner-asks-suite|scripts/test-jarvis-owner-asks.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-owner-asks.js"$'\n'"$repo_plan"
  "jarvis-audit-suite|scripts/test-jarvis-audit.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-audit.js"$'\n'"$repo_plan"
  "jarvis-shell-input|shell/plugins/vgs.jarvis/backend/Shell.js|cli|node scripts/test-jarvis-files.js"$'\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-shell.js'$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-computer-reference|shell/plugins/vgs.jarvis/backend/skills/computer/shell.md|cli|text:"
  "jarvis-shell-suite|scripts/test-jarvis-shell.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-shell.js"$'\n'"$repo_plan"
  "jarvis-router-suite|scripts/test-jarvis-router.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-router.js"$'\n'"$repo_plan"
  "jarvis-router-input|shell/plugins/vgs.jarvis/backend/ToolRouter.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js'$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-policy-fixture|scripts/fixtures/jarvis/policy.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_policy_rows$jarvis_daemon_plan"
  "jarvis-tools-input|shell/plugins/vgs.jarvis/backend/Tools.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-setup-gate.js"$'\nnode scripts/test-jarvis-tools.js\nnode scripts/test-jarvis-policy.js\nnode scripts/test-jarvis-redact.js\nnode scripts/test-jarvis-providers.js\nnode scripts/test-jarvis-mcp.js\nnode scripts/test-jarvis-guidance.js'
  "jarvis-audit-input|shell/plugins/vgs.jarvis/backend/Audit.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-audit.js'$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\n'$'node scripts/test-jarvis-shell.js\n'"${jarvis_daemon_plan%$repo_plan}"$'node scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-redact-input|shell/plugins/vgs.jarvis/backend/Redact.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-redact.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-redact-router-input|shell/plugins/vgs.jarvis/backend/Redact.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-audit.js'$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-policy-input|shell/plugins/vgs.jarvis/backend/Policy.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-policy.js"$'\nnode scripts/test-jarvis-release.js\nnode scripts/test-jarvis-providers.js'
  "jarvis-policy-net-input|shell/plugins/vgs.jarvis/backend/Policy.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-elevenlabs.js\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-net-input|shell/plugins/vgs.jarvis/backend/net.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-release.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-net-cli-input|shell/plugins/vgs.jarvis/backend/net.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-elevenlabs.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-add-key-input|shell/plugins/vgs.jarvis/backend/keys.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-denied-input|shell/plugins/vgs.jarvis/backend/Denied.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-policy.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-denied-cli-input|shell/plugins/vgs.jarvis/backend/Denied.js|cli|node scripts/test-jarvis-denied.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-sandbox-input|shell/plugins/vgs.jarvis/backend/Sandbox.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-sandbox.js'$'\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-child-input|shell/plugins/vgs.jarvis/backend/Child.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-child.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-input|shell/plugins/vgs.jarvis/backend/Desktop.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-session-input|shell/plugins/vgs.jarvis/backend/DesktopSession.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-executors-input|shell/plugins/vgs.jarvis/backend/Executors.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-fixture|scripts/fixtures/jarvis/desktop-tool.py|cli|node scripts/test-jarvis-desktop-tools.js"$'\nnode scripts/test-jarvis-daemon.js'
  "jarvis-forbidden-input|scripts/fixtures/jarvis/forbidden.js|logic|node scripts/check-jarvis-words.js"$'\n'""
  "jarvis-forbidden-cli-input|scripts/fixtures/jarvis/forbidden.js|cli|node scripts/test-jarvis-sandbox.js"$'\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js'
  "jarvis-sandbox-datagram-input|scripts/fixtures/jarvis/sandbox-datagram.py|cli|node scripts/test-jarvis-sandbox.js"$'\nnode scripts/test-jarvis-daemon.js'
  "jarvis-session-suite|scripts/test-jarvis-session.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-session.js"$'\n'"$repo_plan"
  "jarvis-history-input|shell/plugins/vgs.jarvis/History.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-conversation.js"
  "jarvis-owner-suite|scripts/test-jarvis-session-runner.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-session-runner.js"$'\n'"$repo_plan"
  "jarvis-session|shell/plugins/vgs.jarvis/Session.js|logic|node scripts/check-jarvis-words.js"$'\nnode scripts/test-plugin-status.js\nnode scripts/test-hyprland-layer.js\nnode scripts/test-jarvis-session.js\nnode scripts/test-jarvis-session-runner.js\nnode scripts/test-jarvis-widget.js\nnode scripts/test-jarvis-protocol.js\nnode scripts/test-jarvis-conversation.js\nnode scripts/test-jarvis-requests.js'
  "jarvis-session-router|shell/plugins/vgs.jarvis/Session.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_audio_rows"$'node scripts/test-jarvis-claude-task.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-owner|shell/plugins/vgs.jarvis/backend/session-runner.js|logic|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-session-runner.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-owner-router|shell/plugins/vgs.jarvis/backend/session-runner.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-playback.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-tools-router|shell/plugins/vgs.jarvis/backend/Tools.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-elevenlabs.js\nnode scripts/test-jarvis-denied.js\nnode scripts/test-jarvis-home.js\nnode scripts/test-jarvis-home-repair.js\nnode scripts/test-jarvis-memory.js\nnode scripts/test-jarvis-audit.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-copilot-input|shell/plugins/vgs.jarvis/backend/CopilotHarness.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-claude.js"$'\n'"node scripts/test-jarvis-codex.js"$'\n'"node scripts/test-jarvis-copilot.js"$'\n'"node scripts/test-jarvis-pi.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\n'"node scripts/test-jarvis-audio-daemon.js"$'\n'"node scripts/test-jarvis-engine.js"$'\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-claude-input|shell/plugins/vgs.jarvis/backend/ClaudeCode.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-copilot.js\nnode scripts/test-jarvis-pi.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-claude-standin|scripts/fixtures/jarvis-claude/claude|cli|node scripts/test-jarvis-claude.js"$'\nnode scripts/test-jarvis-daemon.js'
  "jarvis-guidance-suite|scripts/test-jarvis-guidance.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_guidance_plan"
  "jarvis-guidance-fixture|scripts/fixtures/jarvis-voice/guidance.json|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_guidance_plan"
  "jarvis-speakable-suite|scripts/test-jarvis-speakable.js|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_speakable_plan"
  "jarvis-speakable-fixture|scripts/fixtures/jarvis-voice/speakable.json|offline|node scripts/check-jarvis-words.js"$'\n'"$jarvis_speakable_plan"
  "jarvis-language-suite|scripts/test-jarvis-speech-language.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-speech-language.js"$'\n'"$repo_plan"
  "jarvis-voice-assertions|scripts/fixtures/jarvis-voice/assertions.js|offline|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-sse.js"$'\nnode scripts/test-jarvis-providers.js\n'"${jarvis_language_plan%$repo_plan}"$'node scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-voice-installed|scripts/fixtures/jarvis-voice/installed.js|all|node scripts/check-jarvis-words.js"$'\n'"$install_plan"$'\nscripts/qml-smoke.sh'
  "dispatch|shell/Core/Dispatch.js|offline|$dispatch_plan"
  "session|shell/Core/SessionLock.qml|all|$session_plan"
  "fixture|scripts/smoke/fixtures/plugins/acme.contention/Background.qml|all|$fixture_plan"
  "smoke-row|scripts/smoke/rows/example.sh|all|$smoke_plan"
  "capture-worker-suite|scripts/test-capture.py|cli|python3 scripts/test-capture.py"
  "share-picker-suite|scripts/test-share-picker.py|cli|python3 scripts/test-share-picker.py"
  "share-picker-consumer|scripts/fixtures/share-picker/xdph-selection.cpp|cli|python3 scripts/test-share-picker.py"
  "jarvis-key-smoke|scripts/smoke/rows/jarvis-keys.sh|all|node scripts/check-jarvis-words.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\n'"${jarvis_key_plan%$'\nscripts/qml-smoke.sh'}"$'\nscripts/test-validate.sh\nscripts/qml-smoke.sh'
  "mode-startup-entry|scripts/qml-smoke.sh|tools|scripts/test-smoke-verdict.sh"$'\nscripts/test-mode-hold.sh\npython3 scripts/check-smoke-hidden.py\npython3 scripts/test-check-smoke-hidden.py\nsmoke_reads_named\npython3 scripts/test-smoke-evidence.py\nscripts/test-gpu-fence.sh\nscripts/test-validate.sh'
  "mode-capture-entry|scripts/sandbox-shots.sh|tools|scripts/test-mode-hold.sh"$'\nscripts/test-smoke-input-guard.sh\nscripts/test-sandbox-shots.sh\nnode scripts/test-google-drive-scene.js\nscripts/test-gpu-fence.sh'
  "compositor-reveal-barrier-suite|scripts/test-compositor-reveal.py|tools|python3 scripts/test-compositor-reveal.py"
  "smoke-configuration-restore-suite|scripts/test-smoke-user-config.py|tools|python3 scripts/test-smoke-user-config.py"
  "smoke-anr-isolation-suite|scripts/test-smoke-anr.py|tools|python3 scripts/test-smoke-anr.py"
  "jarvis-poll-harness|scripts/smoke/harness.sh|all|node scripts/test-jarvis-daemon.js"$'\nscripts/test-smoke-verdict.sh\nscripts/test-smoke-hypr-bound.sh\nscripts/test-mode-hold.sh\npython3 scripts/check-smoke-readers.py\npython3 scripts/test-smoke-dumps.py\npython3 scripts/test-check-smoke-readers.py\npython3 scripts/test-compositor-reveal.py\nscripts/test-secret-tool-stand-in.sh\nscripts/test-smoke-input-guard.sh\nscripts/test-smoke-xwayland.sh\nsmoke_reads_named\nscripts/test-smoke-teardown.sh\npython3 scripts/test-smoke-persisted-inputs.py\npython3 scripts/test-smoke-evidence.py\nscripts/test-smoke-display-record.sh\npython3 scripts/test-smoke-anr.py\nscripts/test-smoke-sink.sh\npython3 scripts/test-smoke-user-config.py\nscripts/test-sandbox-shots.sh\nscripts/test-gpu-fence.sh\nnode scripts/test-jarvis-env.js\nscripts/test-jarvis-selftest.sh\n'"$repo_plan"$'\nscripts/test-validate.sh\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
  "smoke-persisted-input-suite|scripts/test-smoke-persisted-inputs.py|tools|python3 scripts/test-smoke-persisted-inputs.py"
  "smoke-persisted-input-owner|scripts/smoke/persisted-inputs.py|tools|python3 scripts/test-smoke-dumps.py"$'\nsmoke_reads_named\npython3 scripts/test-smoke-persisted-inputs.py\npython3 scripts/test-smoke-evidence.py\npython3 scripts/test-smoke-anr.py'
  "shortcut-provider|shell/Core/ShortcutRegistry.qml|unit|scripts/test-keyboard-ui.sh"$'\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh'
  "key-capture-owner|shell/Core/KeyCapture.qml|unit|scripts/test-keyboard-ui.sh"$'\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh'
  "settings-edit-set|shell/plugins/vgs.settings/EditSet.qml|unit|scripts/qml-unit.sh"$'\nscripts/test-qml-unit.sh'
  "displays-pane|shell/plugins/vgs.displays/Pane.qml|unit|scripts/qml-unit.sh"$'\nscripts/test-qml-unit.sh'
  "vpn-view|shell/plugins/vgs.vpn/VpnBody.qml|unit|scripts/qml-unit.sh"$'\nscripts/test-qml-unit.sh'
  "shell-gc-mode|shell/shell.qml|unit|scripts/test-keyboard-ui.sh"$'\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh\nnode scripts/test-key-labels.js\nscripts/test-session-lock.sh'
  "harness-render|.agents/skills/review-gate/scripts/review-policy|all|$repo_plan"
  "harness-hook|.claude/hooks/example.sh|all|$repo_plan"
  "harness-settings|kendex.local.toml|all|$repo_plan"
  "workflow|.github/workflows/example.yml|all|$repo_plan"
)
# The live and Home suites start the real daemon. Expected plans include
# those consumers of backend and shared source changes.
with_daemon_consumers() { # FILE AREA EXPECTED
  python3 - "$1" "$2" "$3" <<'PYLIVE'
import fnmatch, sys
file, area, wanted = sys.argv[1:]
inputs = ["shell/plugins/vgs.jarvis/backend/*", "shell/plugins/vgs.jarvis/AccountProviders.js",
          "shell/Core/Dispatch.js", "shell/Commons/DesktopLaunch.js", "bin/lib/judge-files.js",
          "bin/lib/anchored.js", "bin/lib/account-folders.js", "shell/Commons/AccountDirectories.js",
          "scripts/fixtures/jarvis/audio*", "scripts/fixtures/jarvis/engine.js",
          "scripts/fixtures/jarvis-brain/openai-chat*"]
command = "node scripts/test-jarvis-live.js"
lines = wanted.split("\n")
if area in ["cli", "offline", "all"] and command not in lines and any(fnmatch.fnmatchcase(file, pattern) for pattern in inputs):
    earlier = {"session", "session-runner", "widget", "setup-gate", "protocol", "tools", "requests",
               "policy", "redact", "release", "sse", "providers", "net", "brain-openai", "brain-anthropic"}
    for at, line in enumerate(lines):
        if ((line.startswith("node scripts/test-jarvis-") and line.removeprefix("node scripts/test-jarvis-").removesuffix(".js") not in earlier)
                or line == "scripts/test-install-tree.sh"):
            lines.insert(at, command)
            break
    else:
        raise AssertionError("no later consumer in expected plan: " + file)
home = "node scripts/test-jarvis-home.js"
home_input = (file.startswith(("shell/plugins/vgs.jarvis/backend/", "shell/Core/", "packaging/jarvis-home/"))
              or file in {"shell/plugins/vgs.jarvis/manifest.json", "shell/plugins/vgs.jarvis/Session.js",
                          "shell/plugins/vgs.jarvis/JarvisProtocol.js", "shell/plugins/vgs.jarvis/AccountProviders.js",
                          "shell/Ui/icons/Lucide.js", "shell/Commons/SettingValues.js", "shell/Commons/DesktopLaunch.js",
                          "shell/Commons/AccountDirectories.js", "bin/lib/qml-library.js", "bin/lib/judge-files.js",
                          "bin/lib/anchored.js", "bin/lib/account-folders.js", "scripts/fixtures/jarvis/policy.js",
                          "scripts/lib/jarvis-env.sh", "scripts/fixtures/jarvis/core.js"})
if area in ["cli", "offline", "all"] and home not in lines and home_input:
    earlier = {"session", "session-runner", "widget", "setup-gate", "protocol", "conversation", "tools", "requests",
               "policy", "redact", "release", "sse", "providers", "net", "brain-openai", "brain-anthropic", "live", "elevenlabs", "denied"}
    for at, line in enumerate(lines):
        if ((line.startswith("node scripts/test-jarvis-") and line.removeprefix("node scripts/test-jarvis-").removesuffix(".js") not in earlier)
                or line == "scripts/test-install-tree.sh"):
            lines.insert(at, home)
            break
    else:
        raise AssertionError("no later Home consumer in expected plan: " + file)
# The session control suite's row follows the Home row, and its inputs are among
# the Home suite's.
repair = "node scripts/test-jarvis-home-repair.js"
repair_input = (file.startswith("packaging/jarvis-home/") or file in {
    "shell/plugins/vgs.jarvis/backend/Home.js", "shell/plugins/vgs.jarvis/backend/Tools.js",
    "shell/plugins/vgs.jarvis/backend/Core.js", "shell/plugins/vgs.jarvis/backend/Child.js",
    "shell/plugins/vgs.jarvis/backend/fleet-setup.js", "shell/plugins/vgs.jarvis/backend/audio-child.py",
    "shell/plugins/vgs.jarvis/tui/repair-home.sh", "bin/lib/qml-library.js", "bin/lib/anchored.js",
    "bin/lib/account-folders.js", "bin/lib/codex-account.js", "shell/Commons/AccountDirectories.js",
    "scripts/fixtures/jarvis/policy.js", "scripts/fixtures/jarvis/core.js",
    "scripts/fixtures/jarvis/bounded.js", "scripts/lib/jarvis-env.sh"})
if area in ["cli", "offline", "all"] and repair not in lines and repair_input:
    lines.insert(lines.index(home) + 1 if home in lines else 0, repair)
session = "node scripts/test-jarvis-session-control.js"
session_input = (file.startswith("shell/plugins/vgs.jarvis/backend/")
                 or file in {"shell/plugins/vgs.jarvis/AccountProviders.js", "shell/Commons/AccountDirectories.js",
                             "bin/lib/qml-library.js", "bin/lib/judge-files.js", "bin/lib/anchored.js",
                             "bin/lib/account-folders.js", "scripts/lib/jarvis-env.sh"})
if area in ["cli", "offline", "all"] and session not in lines and session_input:
    lines.insert(lines.index(repair if repair in lines else home) + 1, session)
# The owner-ask package boundary sits between session-control and power-wait.
asks = "node scripts/test-jarvis-owner-asks.js"
asks_input = file in {
    "shell/plugins/vgs.jarvis/backend/OwnerAsks.js", "shell/plugins/vgs.jarvis/backend/SessionCommand.js",
    "shell/plugins/vgs.jarvis/backend/Child.js", "shell/plugins/vgs.jarvis/backend/Home.js",
    "shell/plugins/vgs.jarvis/backend/Tools.js", "shell/plugins/vgs.jarvis/backend/Core.js",
    "shell/plugins/vgs.jarvis/JarvisProtocol.js", "shell/plugins/vgs.jarvis/Session.js",
    "scripts/fixtures/jarvis/owner-asks.js", "scripts/fixtures/jarvis/core.js", "scripts/lib/jarvis-env.sh",
    "bin/lib/qml-library.js", "bin/lib/anchored.js", "bin/lib/account-folders.js", "bin/lib/codex-account.js",
    "shell/Commons/AccountDirectories.js",
    "shell/plugins/vgs.jarvis/StatusPublication.js", "shell/Core/PluginLogic.js", "shell/Core/ConfigLogic.js", "shell/Core/PackageManagers.js", "shell/Core/PackageReview.js", "shell/Core/HyprlandLayer.js", "shell/Core/MonitorLogic.js", "shell/Core/Pads.js", "shell/Commons/SettingValues.js", "shell/Commons/PageReference.js", "shell/Ui/icons/Lucide.js", "shell/Ui/icons/Own.js",
    "shell/plugins/vgs.jarvis/Conversation.js", "shell/plugins/vgs.jarvis/manifest.json",
    "shell/plugins/vgs.jarvis/Service.qml"}
if area in ["cli", "offline", "all"] and asks not in lines and asks_input:
    if session in lines:
        lines.insert(lines.index(session) + 1, asks)
    else:
        earlier = {"session", "session-runner", "widget", "setup-gate", "protocol", "conversation", "tools", "requests",
                   "policy", "redact", "release", "sse", "providers", "net", "brain-openai", "brain-anthropic",
                   "live", "elevenlabs", "denied", "home", "home-repair", "session-control"}
        for at,line in enumerate(lines):
            if ((line.startswith("node scripts/test-jarvis-") and line.removeprefix("node scripts/test-jarvis-").removesuffix(".js") not in earlier)
                    or line == "scripts/test-install-tree.sh"):
                lines.insert(at, asks)
                break
        else:
            lines.append(asks)
# The power wait suite's row follows the session control row, with the same inputs.
power = "node scripts/test-jarvis-power-wait.js"
if area in ["cli", "offline", "all"] and power not in lines and session_input:
    lines.insert(lines.index(asks if asks in lines else session) + 1, power)
# The satellite suite's row follows the router row; its inputs are its row's.
satellite = "node scripts/test-jarvis-satellite.js"
satellite_inputs = ["shell/plugins/vgs.jarvis/backend/Satellite.js", "shell/plugins/vgs.jarvis/backend/Child.js",
    "shell/plugins/vgs.jarvis/backend/Home.js", "shell/plugins/vgs.jarvis/backend/Redact.js",
    "shell/plugins/vgs.jarvis/backend/Tools.js", "shell/plugins/vgs.jarvis/backend/Core.js",
    "shell/plugins/vgs.jarvis/backend/SessionCommand.js",
    "shell/plugins/vgs.jarvis/JarvisProtocol.js", "shell/plugins/vgs.jarvis/Session.js",
    "shell/plugins/vgs.jarvis/AccountProviders.js", "shell/plugins/vgs.jarvis/manifest.json",
    "scripts/fixtures/jarvis/satellite-package.py", "scripts/fixtures/jarvis/policy.js", "scripts/fixtures/jarvis/core.js",
    "scripts/fixtures/jarvis/bounded.js", "scripts/lib/jarvis-env.sh", "bin/lib/qml-library.js", "bin/lib/anchored.js",
    "bin/lib/account-folders.js", "shell/Commons/AccountDirectories.js", ".agents/skills/jarvis/scripts/lib/*"]
if area in ["cli", "offline", "all"] and satellite not in lines and any(fnmatch.fnmatchcase(file, pattern) for pattern in satellite_inputs):
    router = "node scripts/test-jarvis-router.js"
    if router not in lines:
        raise AssertionError("no router row before the satellite row in expected plan: " + file)
    lines.insert(lines.index(router) + 1, satellite)
# The fatal-row suite starts a real disposable runtime and is the last QML
# row, so product inputs also select it, without widening non-QML areas.
fatal_smoke_input = (file.startswith(("shell/", "bin/", "config/", "themes/", "packaging/", "scripts/smoke/", "scripts/fixtures/jarvis/"))
                     or file in {"scripts/qml-smoke.sh", "scripts/test-qml-smoke.sh", "scripts/lib/jarvis-env.sh", "VERSION", "LICENSE", "README.md"})
if area in ["qml", "all"] and fatal_smoke_input and "scripts/test-qml-smoke.sh" not in lines:
    lines.append("scripts/test-qml-smoke.sh")
print("\n".join(lines), end="")
PYLIVE
}
plan_consumer_case() { # SPEC
  local spec="$1" name rest file area wanted d state status out err
  name="${spec%%|*}"; rest="${spec#*|}"
  file="${rest%%|*}"; rest="${rest#*|}"
  area="${rest%%|*}"; wanted="${rest#*|}"
  if [[ $wanted == text:* ]]; then
    wanted="${wanted#text:}"
  elif ! wanted="$(with_daemon_consumers "$file" "$area" "$wanted")"; then
    fail "$name expected consumer plan could not be built"
    return
  fi
  d="$tmp/plan-$name"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  if [[ $name == real-* ]]; then
    cp -- "$repo/$file" "$d/$file"
    printf '\nchanged\n' >>"$d/$file"
  else
    printf 'changed\n' >"$d/$file"
  fi
  for state in untracked staged committed deleted; do
    case "$state" in
      staged) "${base_env[@]}" git -C "$d" add -- "$file" ;;
      committed) "${base_env[@]}" git -C "$d" commit -q -m change ;;
      deleted)
        # Compare the deletion against a base that actually contains it.
        "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
        rm -- "${d:?}/$file" ;;
    esac
    err="$tmp/plan-$name-$state-changed.err"
    status=0
    out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate "$area" --changed refs/remotes/origin/trunk --list 2>"$err")" || status=$?
    if [[ $status == 0 && $out == "$wanted" ]]; then ok "$name selects its consumers when $state"; else fail "$name $state plan: $out"; fi
    err="$tmp/plan-$name-$state-default.err"
    if out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate "$area" --list 2>"$err")" && [[ $out == "$wanted" ]]; then
      ok "$name defaults to its consumers when $state"
    else
      fail "$name $state default plan: $out"
    fi
  done
}
# The needle rows read all product sources to locate each old text in its
# comment spans, and every row to discover edit calls. Add those commands
# to each existing fixture's independent expected plan at the tools boundary.
needle_rows=$'python3 scripts/check-smoke-needles.py\npython3 scripts/test-check-smoke-needles.py\n'
for i in "${!cases[@]}"; do
  IFS='|' read -r case_name case_input case_area _ <<<"${cases[i]}"
  case_plan="${cases[i]#*|*|*|}"
  additions=""
  if [[ $case_plan != text:* && ( $case_area == all || $case_area == offline || $case_area == tools ) ]]; then
    case "$case_input" in
      scripts/qml_source.py|bin/vgshell-scan|bin/lib/dbus_wire.py)
        additions=$'python3 scripts/test-qml-source.py\n'"$needle_rows" ;;
      shell/*|scripts/smoke/rows/*|scripts/smoke/harness.sh|scripts/smoke/tree.sh|scripts/shell_source.py) additions="$needle_rows" ;;
    esac
  fi
  if [[ -n $additions ]]; then
    if [[ $case_plan == *whitespace_check* ]]; then
      case_plan="${case_plan/whitespace_check/${additions}whitespace_check}"
    elif [[ $case_plan == *scripts/test-validate.sh* ]]; then
      case_plan="${case_plan/scripts\/test-validate.sh/${additions}scripts/test-validate.sh}"
    else
      case_plan+=$'\n'"${additions%$'\n'}"
    fi
    cases[i]="$case_name|$case_input|$case_area|$case_plan"
  fi
done
parallel_cases plan_consumer_case plan-case "${cases[@]}"

# plant FILE OLD NEW: replace the one occurrence of OLD in FILE, a copy of a
# script under test, with NEW; a count other than one stops the suite.
plant() {
  python3 - "$@" <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
}
# commit DIR MESSAGE: commit every change in DIR.
commit() {
  "${base_env[@]}" git -C "$1" add -A
  "${base_env[@]}" git -C "$1" commit -q -m "$2"
}

# A displayed plugin README reaches product rows through their real input
# patterns. Mixed changes keep that reach; a text-only change suppresses it.
for variant in text mixed control full unreadable; do
  d="$tmp/readme-scope-$variant"; fresh "$d"
  file=shell/plugins/vgs.keyboard/README.md
  mkdir -p "$d/shell/plugins/vgs.keyboard"
  cp -- "$repo/$file" "$d/$file"
  commit "$d" readme
  if [[ $variant == control ]]; then
    plant "$d/scripts/validate" 'if [[ $pass_tree != unreadable && ${#changed_paths[@]} -gt 0 ]]; then' 'if false; then'
    commit "$d" control
  fi
  printf '\nchanged\n' >>"$d/$file"
  [[ $variant != mixed ]] || printf '# mixed change\n' >>"$d/kendex.settings.toml"
  [[ $variant != unreadable ]] || chmod 000 "$d/$file"
  test_area=all test_args=(--changed HEAD --list)
  [[ $variant != full ]] || test_args=(--full --list)
  case "$variant" in
    text)
      row "a displayed README selects only text checks" "$d" 0 "" \
        'python3 scripts/check-user-commands.py' whitespace_check md_refs_check doc_limits_check \
        '!scripts/test-keyboard-ui.sh' '!scripts/qml-unit.sh' '!scripts/qml-smoke.sh' '!scripts/measure-shader.sh'
      test_area=qml
      row "a README-only diff selects no nested row in the explicit qml area" "$d" 0 "" '!scripts/' ;;
    control)
      if (failures=0; row "README text-only guarantee" "$d" 0 "" '!scripts/test-keyboard-ui.sh'; ((failures == 0))) >"$tmp/readme-text-control.log"; then
        fail "control: the old README over-selection leaves the text-only assertion green"
      elif grep -qF 'exit=0 want=0 missing= present=[scripts/test-keyboard-ui.sh]' "$tmp/readme-text-control.log"; then
        ok "control: the old README over-selection fails the text-only assertion"
      else
        cat -- "$tmp/readme-text-control.log"
        fail "control: the README assertion failed for another cause"
      fi ;;
    mixed|full|unreadable)
      row "$variant README selection retains product coverage" "$d" 0 "" \
        'scripts/test-keyboard-ui.sh' 'scripts/qml-smoke.sh' ;;
  esac
done
test_args=()

# D124 compares complete existing source, with directive comments outside
# the grant. Each variant uses product inputs so losing the grant is visible.
for variant in qml js mixed directive-keyboard directive-pointer directive-focus pragma comment-added comment-removed multiline code literal-string literal-template asi-return asi-return-cr asi-return-separator asi-throw asi-postfix fixture self-reading whitespace added removed renamed unreadable explicit-qml full control; do
  d="$tmp/comment-scope-$variant"; fresh "$d"
  file=shell/plugins/vgs.keyboard/Service.qml
  case "$variant" in
    js|asi-*) file=shell/plugins/vgs.keyboard/KeyboardLogic.js ;;
    fixture) file=scripts/smoke/fixtures/sysmon/Service.qml ;;
    self-reading) file=scripts/test-keyboard-logic.js ;;
  esac
  mkdir -p "$d/${file%/*}"
  cp -- "$repo/$file" "$d/$file"
  printf '\n// ordinary old\n' >>"$d/$file"
  case "$variant" in
    literal-string) printf 'property string url: "https://old/*literal*/"\n' >>"$d/$file" ;;
    literal-template) printf 'const template = `// old ${1} /*literal*/`;\n' >>"$d/$file" ;;
    asi-throw) printf 'function probe() { throw /* old */error; }\n' >>"$d/$file" ;;
    asi-postfix) printf 'function probe() { value /* old */++; }\n' >>"$d/$file" ;;
  esac
  commit "$d" source
  if [[ $variant == control ]]; then
    plant "$d/scripts/validate" 'if [[ $area == qml ]] || ! comment_only "$change_base" "$path"; then' 'if true; then'
    commit "$d" control
  fi
  case "$variant" in
    directive-*)
      case "$variant" in
        directive-keyboard) directive=keyboard-path ;;
        directive-pointer) directive=pointer-cursor-exempt ;;
        directive-focus) directive=focus-indicator ;;
      esac
      plant "$d/$file" '// ordinary old' "// $directive: old"
      commit "$d" directive
      plant "$d/$file" "// $directive: old" "// $directive: changed" ;;
    pragma)
      printf '//@ pragma Env QV4_GC_TIMELIMIT = 0\n' >>"$d/$file"
      commit "$d" pragma
      plant "$d/$file" '//@ pragma Env QV4_GC_TIMELIMIT = 0' '//@ pragma Env QV4_GC_TIMELIMIT = 1' ;;
    comment-added) printf '// added ordinary comment\n' >>"$d/$file" ;;
    comment-removed) plant "$d/$file" $'// ordinary old\n' '' ;;
    multiline) plant "$d/$file" '// ordinary old' $'/* ordinary\nchanged */' ;;
    code) printf 'Item {}\n' >>"$d/$file" ;;
    literal-string) plant "$d/$file" 'https://old/*literal*/' 'https://changed/*literal*/' ;;
    literal-template) plant "$d/$file" '`// old ${1} /*literal*/`' '`// changed ${1} /*literal*/`' ;;
    asi-return) plant "$d/$file" 'return layouts;' $'return /* explanation\n*/layouts;' ;;
    asi-return-cr) plant "$d/$file" 'return layouts;' $'return /* explanation\r*/layouts;' ;;
    asi-return-separator) plant "$d/$file" 'return layouts;' $'return /* explanation\u2028*/layouts;' ;;
    asi-throw|asi-postfix) plant "$d/$file" '/* old */' $'/* changed\n*/' ;;
    whitespace) printf ' \n' >>"$d/$file" ;;
    added) cp -- "$d/$file" "$d/shell/plugins/vgs.keyboard/Added.qml" ;;
    removed) rm -- "${d:?}/$file" ;;
    renamed) mv -- "$d/$file" "$d/shell/plugins/vgs.keyboard/Renamed.qml" ;;
    *) plant "$d/$file" '// ordinary old' '// ordinary changed length' ;;
  esac
  [[ $variant != mixed ]] || printf '\nchanged\n' >>"$d/clean.txt"
  [[ $variant != unreadable ]] || chmod 000 "$d/$file"
  test_area=all test_args=(--changed HEAD --list)
  [[ $variant != explicit-qml ]] || test_area=qml
  [[ $variant != full ]] || test_args=(--full --list)
  case "$variant" in
    qml|js|mixed|comment-added|comment-removed|multiline)
      row "$variant ordinary comments select text and comment consumers" "$d" 0 "" \
        whitespace_check md_refs_check 'python3 scripts/check-user-commands.py' \
        'python3 scripts/check-keyboard.py shell' 'python3 scripts/check-pointer-cursor.py' 'python3 scripts/check-smoke-needles.py' \
        '!scripts/qml-unit.sh' '!scripts/qml-smoke.sh' '!scripts/test-keyboard-ui.sh' ;;
    control)
      if (failures=0; row "comment-only guarantee" "$d" 0 "" '!scripts/qml-smoke.sh'; ((failures == 0))) >"$tmp/comment-text-control.log"; then
        fail "control: input selection leaves the comment-only assertion green"
      elif grep -qF 'exit=0 want=0 missing= present=[scripts/qml-smoke.sh]' "$tmp/comment-text-control.log"; then
        ok "control: ordinary source input selection fails the comment-only assertion"
      else
        cat -- "$tmp/comment-text-control.log"
        fail "control: comment assertion failed for another cause"
      fi ;;
    self-reading|asi-*) row "$variant source retains product selection" "$d" 0 "" 'node scripts/test-keyboard-logic.js' ;;
    *) row "$variant source retains product selection" "$d" 0 "" 'scripts/qml-smoke.sh' ;;
  esac
done
test_args=()

# The same selector/required-command assertion must fail when a directly
# consumed notification source loses its edge. Mutate only the scratch
# template; the case table above owns the input family and expected command.
cp -- "$tmp/template/scripts/validate" "$tmp/notifications-input-original"
notifications_saved_area=${test_area:-}
notifications_saved_args=("${test_args[@]}")
for spec in "${cases[@]}"; do
  [[ $spec == notifications-* ]] || continue
  IFS='|' read -r name input test_area _ <<<"$spec"
  # The notifications logic row is the manifest's last consumer of these
  # inputs, so its command is the expected plan's last line.
  command=${spec#*|*|*|}; command=${command##*$'\n'}
  python3 - "$tmp/template/scripts/validate" "$input" <<'PYEDGE'
from pathlib import Path
import sys
path = Path(sys.argv[1]); source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "logic|notifications logic|')]
edge = ' ' + sys.argv[2] + ' '
assert len(rows) == 1 and rows[0].count(edge) == 1
changed = source.replace(rows[0], rows[0].replace(edge, ' ', 1))
assert changed != source
path.write_text(changed)
PYEDGE
  d="$tmp/$name-omitted-input"; fresh "$d"
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m omitted-input-control
  mkdir -p -- "$d/$(dirname -- "$input")"
  printf 'changed\n' >"$d/$input"
  test_args=(--changed HEAD --list)
  before=$failures
  row "$name requires its consumer" "$d" 0 "" "$command" >"$tmp/$name-omitted.log"
  if [[ $failures == "$((before + 1))" ]] &&
     grep -qF -- "missing=[$command] present=" "$tmp/$name-omitted.log"; then
    failures=$before
    ok "control: $name omitted input fails the required consumer assertion"
  else
    cat -- "$tmp/$name-omitted.log"
    fail "control: $name omitted input did not fail its consumer assertion"
  fi
  cp -- "$tmp/notifications-input-original" "$tmp/template/scripts/validate"
done
test_area=$notifications_saved_area
test_args=("${notifications_saved_args[@]}")

# Ordinary rows read the world through run(), while the other owners select
# only their declared inputs. The explicit consumers keep a fence edit known,
# so a missing implicit edge cannot hide behind the unknown-input full run.
world_expected=(ordinary_logic ordinary_cli network_cli explicit_control explicit_entry repository_check
  '!unrelated_control' '!undeclared_entry' '!container_step' '!nix_step' '!validate: selection=full')
for variant in real control; do
  d="$tmp/world-input-$variant"; fresh "$d"
  python3 - "$d/scripts/validate" "$variant" <<'PYWORLDINPUT'
from pathlib import Path
import sys
p = Path(sys.argv[1]); source = p.read_text()
a = source.index("rows=(\n")
b = source.index("\n)\n", a) + 3
rows = """rows=(
  "logic|ordinary logic|ordinary_logic|"
  "cli|ordinary cli|ordinary_cli||row"
  "cli|network cli|network_cli||network"
  "tools|explicit control|explicit_control|scripts/smoke/gpu-fence.sh|control"
  "tools|unrelated control|unrelated_control||control"
  "unit|explicit entry|explicit_entry|scripts/smoke/gpu-fence.sh|entry"
  "unit|undeclared entry|undeclared_entry||entry"
  "package|container step|container_step||container"
  "nix|nix step|nix_step||container"
  "repo|repository check|repository_check|"
)"""
source = source[:a] + rows + source[b:]
if sys.argv[2] == "control":
    edge = 'if [[ ${owner:-row} == row || $owner == network ]]; then'
    assert source.count(edge) == 1
    changed = source.replace(edge, 'if false; then')
    assert changed != source
    source = changed
p.write_text(source)
PYWORLDINPUT
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m world-input
  printf '\n' >>"$d/scripts/smoke/gpu-fence.sh"
  test_area=all
  test_args=(--changed HEAD --list)
  if [[ $variant == real ]]; then
    row "a world edit selects ordinary rows and preserves declared owners" "$d" 0 "" "${world_expected[@]}"
  else
    row "the missing-edge control retains explicit consumers" "$d" 0 "" \
      explicit_control explicit_entry repository_check '!validate: selection=full'
    if (failures=0; row "ordinary world dependency" "$d" 0 "" "${world_expected[@]}"; ((failures == 0))) >"$tmp/world-input-control.log"; then
      fail "control: removing the ordinary-world edge leaves its selector assertion green"
    else
      ok "control: removing the ordinary-world edge fails its selector assertion"
    fi
  fi
done
test_area=offline
test_args=()

# The Home test loads the menu judge and runs the shipped daemon. Each
# changed owner must select that consumer independently of the other suites.
for home_input in shell/Core/PluginLogic.js shell/plugins/vgs.jarvis/backend/jarvisd.js; do
  d="$tmp/plan-home-${home_input##*/}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$home_input")"
  printf 'changed\n' >"$d/$home_input"
  test_area=offline
  test_args=(--changed HEAD --list)
  row "the Home test is selected for $home_input" "$d" 0 "" "node scripts/test-jarvis-home.js"
  python3 - "$d/scripts/validate" "$home_input" <<'PYHOME'
from pathlib import Path
import sys
p = Path(sys.argv[1]); source = p.read_text()
prefix = '  "cli|Jarvis home folder|'
rows = [line for line in source.splitlines() if line.startswith(prefix)]
edge = ' shell/Core/* ' if sys.argv[2].startswith('shell/Core/') else 'shell/plugins/vgs.jarvis/backend/* '
assert len(rows) == 1 and rows[0].count(edge) == 1
changed = source.replace(rows[0], rows[0].replace(edge, ' ', 1))
assert changed != source
p.write_text(changed)
PYHOME
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: the omitted Home input loses selection for $home_input" "$d" 0 "" "!node scripts/test-jarvis-home.js"
done

# The desktop package entry loads each helper before confirming its page open.
# Other CLI rows keep these inputs known, so a missing edge must not hide
# behind the unknown-input full-area fallback.
pkg_desktop_helpers=(bin/lib/pkg-review.sh bin/lib/ipc-reply.sh bin/lib/tui.sh)
for helper in "${pkg_desktop_helpers[@]}"; do
  d="$tmp/plan-package-desktop-${helper##*/}"; fresh "$d"
  mkdir -p "$d/bin/lib"
  printf 'changed\n' >"$d/$helper"
  test_area=cli
  test_args=(--changed HEAD --list)
  row "the desktop package suite is selected for $helper" "$d" 0 "" \
    "node scripts/test-vgshell-pkg-cli.js" '!validate: selection=full'
  python3 - "$d/scripts/validate" "$helper" <<'PYPKGEDGE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
prefix = '  "cli|vgshell pkg check owner and command rows|'
rows = [line for line in source.splitlines() if line.startswith(prefix)]
edge = ' ' + sys.argv[2]
assert len(rows) == 1 and rows[0].count(edge) == 1
changed = source.replace(rows[0], rows[0].replace(edge, '', 1))
assert changed != source
path.write_text(changed)
PYPKGEDGE
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: the omitted desktop helper loses selection for $helper" "$d" 0 "" \
    '!node scripts/test-vgshell-pkg-cli.js' '!validate: selection=full'
done

# The table suite runs the verified-file source through bin/lib/pkg-file.js
# and checks the shipped key, so a change confined to either selects it.
for input in bin/lib/pkg-file.js config/keys/40DFB630FF42BCFFB047046CF0134EE680CAC571.gpg; do
  d="$tmp/plan-package-table-${input##*/}"; fresh "$d"
  mkdir -p "$d/${input%/*}"
  printf 'changed\n' >>"$d/$input"
  test_area=cli
  test_args=(--changed HEAD --list)
  row "the package manager table suite is selected for $input" "$d" 0 "" \
    "node scripts/test-vgshell-pkg-table.js" '!validate: selection=full'
done
test_area=offline; test_args=()

# Updates readers load the shipped page-reference module in their core tree.
d="$tmp/plan-updates-page-reference"; fresh "$d"
mkdir -p "$d/shell/Commons"
printf 'changed\n' >"$d/shell/Commons/PageReference.js"
test_area=cli
test_args=(--changed HEAD --list)
row "the page-reference module selects both Updates readers" "$d" 0 "" \
  "scripts/test-updates-check.sh" "scripts/test-updates-pipeline.sh"
for consumer in "updates check helper:scripts/test-updates-check.sh" "updates pipeline controls:scripts/test-updates-pipeline.sh"; do
  label="${consumer%%:*}" command="${consumer#*:}"
  python3 - "$d/scripts/validate" "$label" <<'PYEDGE'
from pathlib import Path
import sys
p = Path(sys.argv[1]); source = p.read_text()
prefix = '  "cli|' + sys.argv[2] + '|'
rows = [line for line in source.splitlines() if line.startswith(prefix)]
edge = ' shell/Commons/PageReference.js'
assert len(rows) == 1 and rows[0].count(edge) == 1
p.write_text(source.replace(rows[0], rows[0].replace(edge, '', 1)))
PYEDGE
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: omitting PageReference skips $label" "$d" 0 "" "!$command"
done

# Both Jarvis readers bind the shared file-reference formatter.
for consumer in "logic:Jarvis bar widget view:node scripts/test-jarvis-widget.js" "cli:Jarvis accounts:node scripts/test-jarvis-accounts.js"; do
  area="${consumer%%:*}"; rest="${consumer#*:}"; label="${rest%%:*}"; command="${rest#*:}"
  d="$tmp/plan-jarvis-page-reference-$area"; fresh "$d"
  mkdir -p "$d/shell/Commons"
  printf 'changed\n' >"$d/shell/Commons/PageReference.js"
  test_area="$area"
  test_args=(--changed HEAD --list)
  row "page references select $label" "$d" 0 "" "$command"
  python3 - "$d/scripts/validate" "$area" "$label" <<'PYEDGE'
from pathlib import Path
import sys
p = Path(sys.argv[1]); source = p.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "' + sys.argv[2] + '|' + sys.argv[3] + '|')]
edge = ' shell/Commons/PageReference.js'
assert len(rows) == 1 and rows[0].count(edge) == 1
p.write_text(source.replace(rows[0], rows[0].replace(edge, '', 1)))
PYEDGE
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: the omitted page-reference input loses $label" "$d" 0 "" "!$command"
done

# Settings' projection is also a consumer boundary for Jarvis recovery.
d="$tmp/plan-jarvis-settings-steps-control"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.settings"
printf 'changed\n' >"$d/shell/plugins/vgs.settings/Steps.js"
test_area=logic
test_args=(--changed HEAD --list)
row "Settings steps select the Jarvis recovery integration" "$d" 0 "" \
  "node scripts/test-jarvis-setup-gate.js" "node scripts/test-settings-steps.js"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "logic|Jarvis setup gate|')]
edge = ' shell/plugins/vgs.settings/Steps.js '
assert len(rows) == 1 and rows[0].count(edge) == 1
path.write_text(source.replace(rows[0], rows[0].replace(edge, ' ', 1)))
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: an omitted Settings input skips Jarvis integration while the Settings suite runs" "$d" 0 "" \
  "!node scripts/test-jarvis-setup-gate.js" "node scripts/test-settings-steps.js"

# The theme judge suite reads these drawing sites. Each missing edge
# must skip that suite when only its source file changes. A plate change
# must select the suite that verifies its fill and ink bindings.
for theme_input in shell/Ui/feedback/SaveBar.qml shell/plugins/vgs.sysmon/Reading.qml shell/plugins/vgs.themes/ThemeView.qml shell/plugins/vgs.themes/WallpaperView.qml shell/Ui/controls/FormRow.qml shell/plugins/vgs.notifications/NotificationCard.qml shell/plugins/vgs.notifications/MediaSlot.qml shell/plugins/vgs.notifications/RowMeasure.qml; do
  d="$tmp/plan-theme-site-${theme_input//\//-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$theme_input")"
  printf 'changed\n' >"$d/$theme_input"
  test_area=logic
  test_args=(--changed HEAD --list)
  row "the theme judge is selected for $theme_input" "$d" 0 "" "node scripts/test-theme-logic.js"
  python3 - "$d/scripts/validate" "$theme_input" <<'PYTHEME'
from pathlib import Path
import sys
path = Path(sys.argv[1]); source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "logic|theme judge table|')]
edge = ' ' + sys.argv[2]
assert len(rows) == 1 and rows[0].count(edge) == 1
changed = source.replace(rows[0], rows[0].replace(edge, '', 1))
assert changed != source
path.write_text(changed)
PYTHEME
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: omitting $theme_input skips the theme judge" "$d" 0 "" "!node scripts/test-theme-logic.js"
done

# The terminal suite runs the shipped sign-in script. Broad Jarvis checks
# do not replace its interactive folder, vendor and failure assertions.
d="$tmp/plan-jarvis-sign-in-terminal-control"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.jarvis/tui"
printf 'changed\n' >"$d/shell/plugins/vgs.jarvis/tui/sign-in.sh"
test_area=cli
test_args=(--changed HEAD --list)
row "sign-in selects its terminal assertions" "$d" 0 "" "node scripts/test-jarvis-accounts-tui.js"
python3 - "$d/scripts/validate" <<'PYCONTROL'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "cli|Jarvis accounts terminal|')]
assert len(rows) == 1 and rows[0].count(' shell/plugins/vgs.jarvis/tui/sign-in.sh ') == 1
path.write_text(source.replace(rows[0], rows[0].replace(' shell/plugins/vgs.jarvis/tui/sign-in.sh ', ' ', 1)))
PYCONTROL
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: an omitted sign-in input skips terminal assertions" "$d" 0 "" \
  "!node scripts/test-jarvis-accounts-tui.js" "node scripts/test-jarvis-secrets.js"

# The task runner executes the viewer. Other TUI consumers do not prove
# its private socket, exact target or argument refusal behavior.
d="$tmp/plan-jarvis-task-view-control"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.jarvis/tui"
printf 'changed\n' >"$d/shell/plugins/vgs.jarvis/tui/task-view.sh"
test_area=cli
test_args=(--changed HEAD --list)
row "task-view selects its executed viewer assertions" "$d" 0 "" "node scripts/test-jarvis-task-runner.js"
python3 - "$d/scripts/validate" <<'PYCONTROL'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "cli|Jarvis task runner|')]
edge = ' shell/plugins/vgs.jarvis/tui/task-view.sh '
assert len(rows) == 1 and rows[0].count(edge) == 1
path.write_text(source.replace(rows[0], rows[0].replace(edge, ' ', 1)))
PYCONTROL
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: an omitted viewer input skips its executed assertions" "$d" 0 "" \
  "!node scripts/test-jarvis-task-runner.js" "node scripts/test-jarvis-secrets.js"

# The engine's daemon-speech case reads the catalog, independently of the
# adapter's own selection tests. Other catalog consumers cannot cover it.
d="$tmp/plan-jarvis-artifacts-engine-control"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.jarvis"
printf 'changed\n' >"$d/shell/plugins/vgs.jarvis/artifacts.json"
test_area=cli
test_args=(--changed HEAD --list)
row "the speech catalog selects the daemon lifetime engine tests" "$d" 0 "" "node scripts/test-jarvis-engine.js"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "cli|Jarvis chained engine|')]
assert len(rows) == 1 and rows[0].count(' shell/plugins/vgs.jarvis/artifacts.json ') == 1
path.write_text(source.replace(rows[0], rows[0].replace(' shell/plugins/vgs.jarvis/artifacts.json ', ' ', 1)))
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: an omitted catalog input skips engine tests while the adapter still runs" "$d" 0 "" \
  "!node scripts/test-jarvis-engine.js" "node scripts/test-jarvis-local-speech.js"

# The shipped daemon loads Dispatch and its recursive Core imports before
# loading admission. Use the shipped loader's closure, not another path list.
mapfile -t jarvis_core_imports < <("$node_bin" - "$repo" <<'JS'
const assert = require("node:assert/strict");
const path = require("node:path");
const root = process.argv[2];
const { closure } = require(path.join(root, "bin/lib/qml-library.js"));
const files = [...closure(path.join(root, "shell/Core/Dispatch.js"))].map(file => path.relative(root, file));
assert.ok(files.every(file => file.startsWith("shell/Core/")), "daemon Core import family");
process.stdout.write(files.join("\n") + "\n");
JS
)
if (( ${#jarvis_core_imports[@]} < 2 )); then fail "daemon closure must include transitive Core inputs"; fi
for imported in "${jarvis_core_imports[@]}"; do
  d="$tmp/plan-engine-core-${imported##*/}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$imported")"
  printf 'changed\n' >"$d/$imported"
  row "the daemon Core family selects engine tests for $imported" "$d" 0 "" "node scripts/test-jarvis-engine.js"
  if [[ $imported == shell/Core/Dispatch.js ]]; then continue; fi
  python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [line for line in source.splitlines() if line.startswith('  "cli|Jarvis chained engine|')]
assert len(rows) == 1 and rows[0].count(' shell/Core/* ') == 1
path.write_text(source.replace(rows[0], rows[0].replace(' shell/Core/* ', ' shell/Core/Dispatch.js ', 1)))
PY
  "${base_env[@]}" git -C "$d" add scripts/validate
  "${base_env[@]}" git -C "$d" commit -q -m control
  row "control: manual Core enumeration omits consumed $imported" "$d" 0 "" "!node scripts/test-jarvis-engine.js"
done
test_area=manifests
test_args=()

# product_fixture copies ProfileRow into the real token baseline. The
# self-check must run when that source changes, even with no validator edit.
d="$tmp/plan-copied-shell-control"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.vpn"
cp -- "$repo/shell/plugins/vgs.vpn/ProfileRow.qml" "$d/shell/plugins/vgs.vpn/ProfileRow.qml"
test_area=tools
test_args=(--changed HEAD --list)
row "the copied profile source selects the self-check" "$d" 0 "" "scripts/test-validate.sh"
python3 - "$d/scripts/validate" <<'PYSHELL'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
prefix = '  "tools|validate self-check controls|scripts/test-validate.sh|'
rows = [line for line in source.splitlines() if line.startswith(prefix)]
assert len(rows) == 1 and rows[0].count(' shell/* ') == 1
changed = source.replace(rows[0], rows[0].replace(' shell/* ', ' ', 1))
assert changed != source
path.write_text(changed)
PYSHELL
# Commit only the control, so the changed list still holds the profile alone.
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: removing the copied-shell input loses self-check selection" "$d" 0 "" \
  "python3 scripts/check-readme-images.py" "!scripts/test-validate.sh"
test_area=manifests
test_args=()

d="$tmp/plan-rename"; fresh "$d"
mkdir -p "$d/shell/Core"
printf 'source\n' >"$d/shell/Core/Dispatch.js"
"${base_env[@]}" git -C "$d" add shell/Core/Dispatch.js
"${base_env[@]}" git -C "$d" commit -q -m source
"${base_env[@]}" git -C "$d" mv shell/Core/Dispatch.js README.md
# The removed path's consumers, and README.md's: the install tree and the
# README check, and the ceiling row, since README.md is a document.
rename_plan=$'node scripts/test-input-facts.js\nnode scripts/test-dispatch.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\npython3 scripts/test-capture.py\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows"$'python3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check"$'scripts/test-sandbox-shots.sh\n'"$needle_rows$repo_plan"$'\ndoc_limits_check\nscripts/test-validate.sh'
if ! rename_plan="$(with_daemon_consumers shell/Core/Dispatch.js offline "$rename_plan")"; then
  fail "the rename's expected consumer plan could not be built"
fi
if out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")" && [[ $out == "$rename_plan" ]]; then ok "a rename selects consumers of the removed source path"; else fail "rename omitted the old path's consumers: $out"; fi

d="$tmp/plan-shared"; fresh "$d"
mkdir -p "$d/bin/lib"; printf 'changed\n' >"$d/bin/lib/qml-library.js"
out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")"
for consumer in 'node scripts/test-plugin-logic.js' 'node scripts/test-dispatch.js' 'node scripts/test-lifetime.js' 'node scripts/test-qml-library.js' 'node scripts/test-key-nav-logic.js' 'node scripts/test-clipboard-history.js' 'node bin/lib/check-manifests.js' 'node scripts/test-check-manifests.js' 'node scripts/test-jarvis-audio-daemon.js' 'scripts/test-vgshell.sh' 'scripts/test-install-tree.sh' 'python3 scripts/test-vgs-plugin.py' 'node scripts/test-check-readme.js' 'scripts/test-readme-install.sh' 'scripts/test-validate.sh'; do
  if grep -qxF "$consumer" <<<"$out"; then ok "shared loader selects $consumer"; else fail "shared loader omitted $consumer"; fi
done
if grep -qxF 'node scripts/test-inset.js' <<<"$out"; then ok "shared loader selects node scripts/test-inset.js"; else fail "shared loader omitted node scripts/test-inset.js"; fi
if grep -qxF 'node scripts/test-setting-values.js' <<<"$out"; then ok "shared loader selects node scripts/test-setting-values.js"; else fail "shared loader omitted node scripts/test-setting-values.js"; fi
if grep -qF 'heap-profile' <<<"$out"; then fail "shared loader selected unrelated heap tests"; else ok "shared loader omits unrelated heap tests"; fi

# bin/vgshell holds the preflight floors the recipe check and the README check
# read.
d="$tmp/plan-floors"; fresh "$d"
mkdir -p "$d/bin"; printf 'changed\n' >"$d/bin/vgshell"
out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")"
for consumer in 'node scripts/check-packaging.js' 'node scripts/test-check-packaging.js' 'node scripts/test-check-readme.js' 'scripts/test-readme-install.sh'; do
  if grep -qxF "$consumer" <<<"$out"; then ok "a bin/vgshell change selects $consumer"; else fail "a bin/vgshell change omitted $consumer"; fi
done

# The live operation follows only engine publication inputs. Its controls
# remain available offline; a floor cannot hide behind a known-input skip.
for file in bin/lib/engine.js packaging/arch/vgshell-quickshell/PKGBUILD packaging/arch/vgshell-quickshell/vgs-1129-fileview-read.patch packaging/fedora/vgshell-quickshell.spec packaging/fedora/copr-project packaging/debian/vgshell-quickshell/rules scripts/debian-packages.sh flake.lock; do
  d="$tmp/engine-input-${file//\//-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf 'changed\n' >>"$d/$file"
  test_area=cli; test_args=(--changed HEAD --list)
  row "engine publication input $file selects the live operation and controls" "$d" 0 "" \
    'node scripts/check-packaging.js --engine-availability' 'node scripts/test-engine-availability.js' '!validate: selection=full'
  test_area=offline
  row "engine publication input $file keeps only controls offline" "$d" 0 "" \
    '!node scripts/check-packaging.js --engine-availability' 'node scripts/test-engine-availability.js' '!validate: selection=full'
done
test_area=offline; test_args=()

# Every actual graphical entry reads the installed prerequisite before it
# dispatches. Changes to that guard or its package owner select the entries.
for file in scripts/lib/engine-availability.js scripts/check-packaging.js scripts/preflight-floor.js bin/lib/engine.js bin/lib/judge-files.js bin/vgshell-pkg bin/lib/qml-library.js shell/Core/PackageManagers.js; do
  d="$tmp/engine-entry-input-${file//\//-}"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf 'changed\n' >>"$d/$file"
  test_area=qml; test_args=(--changed HEAD --list)
  row "installed prerequisite input $file selects each graphical entry" "$d" 0 "" \
    'scripts/qml-smoke.sh' 'scripts/measure-shader.sh' '!validate: selection=full'
done
test_area=offline; test_args=()

d="$tmp/plan-full"; fresh "$d"
full_plan="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --full --list 2>"$tmp/plan.err")"
for reason in unknown unreadable; do
  base=HEAD
  case "$reason" in
    unknown) printf 'new\n' >"$d/new-source.rs" ;;
    unreadable) rm -- "${d:?}/new-source.rs"; base=missing-ref ;;
  esac
  if out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed "$base" --list 2>"$tmp/plan.err")" && [[ $out == "$full_plan" ]]; then ok "$reason input selects the full area"; else fail "$reason input omitted a suite: $out"; fi
done

# Deleting an unmapped test runs repository checks alone. Adding it still
# selects full, and a deleted source outside scripts/test-* selects full.
d="$tmp/deleted-test-plan"; fresh "$d"
test_path="scripts/test-unmapped-probe.sh"
printf 'true\n' >"$d/$test_path"
out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")"
if [[ $out == "$full_plan" ]]; then ok "an untracked unmapped test selects full"; else fail "an untracked unmapped test selected: $out"; fi
"${base_env[@]}" git -C "$d" add -- "$test_path"
"${base_env[@]}" git -C "$d" commit -q -m test
"${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
rm -- "${d:?}/$test_path"
for args in default explicit; do
  test_args=()
  [[ $args == default ]] || test_args=(--changed HEAD)
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline "${test_args[@]}" --list 2>"$tmp/plan.err")"
  if [[ $out == "$repo_plan" ]]; then ok "an unmapped deleted test selects only repository checks: $args"; else fail "a deleted test selected unrelated checks: $args $out"; fi
done
test_args=()
# The previous selection behavior must fail the deletion check.
python3 - "$d/scripts/validate" <<'PYSELECT'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
needle = '  if [[ -z $hits && ! ( $path == scripts/test-* && ! -e $path && ! -L $path ) ]]; then\n'
assert s.count(needle) == 1, "deleted test exemption must match once"
p.write_text(s.replace(needle, '  if [[ -z $hits ]]; then\n'))
PYSELECT
for args in default explicit; do
  test_args=()
  [[ $args == default ]] || test_args=(--changed HEAD)
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline "${test_args[@]}" --list 2>"$tmp/plan.err")"
  if [[ $out == "$full_plan" && $out != "$repo_plan" ]]; then ok "control: the prior full-selection behavior fails the deletion check: $args"; else fail "control: deleted test selection did not change: $args $out"; fi
done
test_args=()

d="$tmp/deleted-source-plan"; fresh "$d"
printf 'source\n' >"$d/unmapped-source.rs"
"${base_env[@]}" git -C "$d" add -- unmapped-source.rs
"${base_env[@]}" git -C "$d" commit -q -m source
rm -- "${d:?}/unmapped-source.rs"
out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")"
if [[ $out == "$full_plan" ]]; then ok "a deleted unmapped source selects full"; else fail "a deleted source omitted checks: $out"; fi

# Nested smoke row selection, read through the qml-smoke.sh command a
# `--list` prints. The fixture's runner stands in for scripts/qml-smoke.sh
# and lists the rows of its scripts/smoke/rows.list, skipping comments and
# blank lines. Each row file declares its inputs, but some cannot
# select, so they run on every change: bare declares none in its leading
# comment block, stale names a directory the tree does not hold, twice
# holds two lines, blank an empty one, and lost has no file.
# notifications-keys names notifications' file, so it brings that row, and
# notifications names notifications-keys' file, a cycle the closure must
# end. The harness's own input line names verdict.sh, the helper directory
# and gone.sh, which the tree does not hold. For the function and variable
# check, launcher defines launcher_open and launcher_close and sets
# launcher_dir, launcher_part, launcher_mode, and sandbox and failures,
# which the harness and the verdict.sh it sources set too. other names no
# row file: it runs launcher_open through the harness's expect and
# launcher_close itself, reads the variables, sets launcher_mode itself,
# and runs other-part, which no name lists and which reads launcher_part.
# The notifications-keys call of notifications' notify_open is declared,
# Array argv data defines no parent variable, but its variable expansions
# and command substitutions still read the launcher's state and function.
# The same-name top-level assignment remains a real defining write.
# twice leaves a heredoc open. Variants: no-harness-line
# carries no harness line, no-list has an empty row list, no-core one
# that does not list auth-sentinel and slow a per-row seconds file that
# names launcher at ten minutes; loads adds the real updates and
# agent-warden rows, their real input lines and the real shell files those
# match, with Badge.qml, BarItem.qml and the qs.Ui qmldir;
# chain makes the launcher row's Panel.qml import the real qs.Ui qmldir,
# naming its singleton ImagePool and internal DismissScope, and name Mid
# of shell/Lib, which names Leaf; unreadable-load adds a shell file that
# is not UTF-8, and failed-load a reader that raises at import. Expected row sets are
# written here, not derived from the selector. A control runs a copy of
# validate with one rule removed, committed so the plan judges the planted
# change alone, and wants the exact plan that rule's loss gives. No fixture
# reaches the tracked-list-unreadable branch: git ls-files fails only where
# the diff read before it fails too, and that selects the full area first.
smoke_fixture() { # DIR [VARIANT]
  local dir="$1" variant="${2:-rows}" row listed='bar hyprland-consent session launcher notifications notifications-keys other bare stale twice blank lost start-order auth-sentinel'
  fresh "$dir"
  mkdir -p "$dir/scripts/smoke/rows" "$dir/scripts/smoke/helper" "$dir/shell/plugins/acme.launcher" "$dir/shell/plugins/acme.notify" "$dir/shell/plugins/acme.other"
  case "$variant" in
    no-list) listed='' ;;
    no-core) listed="${listed% auth-sentinel}" ;;
  esac
  { printf '# The rows, in run order.\n\n'; tr ' ' '\n' <<<"$listed"; } >"$dir/scripts/smoke/rows.list"
  printf '#!/usr/bin/env bash\nif [[ ${1-} == --list-rows ]]; then awk '"'"'!/^#/ && NF'"'"' "$(dirname -- "$0")/smoke/rows.list"; fi\n' >"$dir/scripts/qml-smoke.sh"
  chmod +x "$dir/scripts/qml-smoke.sh"
  if [[ $variant == no-harness-line ]]; then
    printf '# The harness.\nset -euo pipefail\n' >"$dir/scripts/smoke/harness.sh"
  else
    printf '# The harness.\n# inputs: scripts/smoke/verdict.sh scripts/smoke/helper/* scripts/smoke/gone.sh\nset -euo pipefail\n' >"$dir/scripts/smoke/harness.sh"
  fi
  printf '%s\n' 'source "$repo/scripts/smoke/verdict.sh"' 'sandbox="$TMPDIR/sandbox"' 'expect() { # LABEL WANT CMD...' '  local label="$1" want="$2"' '  shift 2' '  [[ $("$@") == "$want" ]]' '}' >>"$dir/scripts/smoke/harness.sh"
  printf 'failures=0\n' >"$dir/scripts/smoke/verdict.sh"
  printf 'helper\n' >"$dir/scripts/smoke/helper/click.c"
  for row in Bar Consent Session Start Auth Keys; do printf 'clean\n' >"$dir/shell/Core/$row.qml"; done
  for row in launcher notify other; do printf 'clean\n' >"$dir/shell/plugins/acme.$row/Panel.qml"; done
  printf '# The bar.\n# inputs: shell/Core/Bar.qml\n' >"$dir/scripts/smoke/rows/bar.sh"
  printf '# inputs: shell/Core/Consent.qml\n' >"$dir/scripts/smoke/rows/hyprland-consent.sh"
  printf '# inputs: shell/Core/Session.qml\nset -euo pipefail\n' >"$dir/scripts/smoke/rows/session.sh"
  printf '# inputs: shell/Core/Start.qml\n' >"$dir/scripts/smoke/rows/start-order.sh"
  printf '# inputs: shell/Core/Auth.qml\n' >"$dir/scripts/smoke/rows/auth-sentinel.sh"
  printf '%s\n' '# inputs: shell/plugins/acme.launcher/*' 'launcher_open() { :; }' 'launcher_close() { :; }' 'launcher_dir="$sandbox/apps"' \
    'launcher_part=$launcher_dir/part launcher_mode=open' 'sandbox=/elsewhere failures=1' \
    'launcher_array_read=$launcher_dir' 'launcher_array_call() { :; }' 'launcher_argv=(TMPDIR="$sandbox" launcher_dir=argument)' >"$dir/scripts/smoke/rows/launcher.sh"
  printf '%s\n' '# inputs: shell/plugins/acme.notify/* scripts/smoke/rows/notifications-keys.sh' 'notify_open() { :; }' >"$dir/scripts/smoke/rows/notifications.sh"
  printf '%s\n' '# inputs: shell/Core/Keys.qml scripts/smoke/rows/notifications.sh' 'notify_open' >"$dir/scripts/smoke/rows/notifications-keys.sh"
  printf '%s\n' '# inputs: shell/plugins/acme.other/*' 'expect "the launcher opens" "" launcher_open' 'launcher_close' 'launcher_mode=other' \
    'ls -- "$launcher_dir" "$sandbox" "$launcher_mode" "$failures" "$TMPDIR"' \
    'other_argv=("$launcher_array_read" "$(launcher_array_call)")' 'smoke_row other-part' >"$dir/scripts/smoke/rows/other.sh"
  printf '%s\n' '# Run by other.sh.' 'ls -- "$launcher_part"' >"$dir/scripts/smoke/rows/other-part.sh"
  printf '# A row with no input line.\nset -euo pipefail\n# inputs: shell/plugins/acme.other/*\n' >"$dir/scripts/smoke/rows/bare.sh"
  printf '# inputs: shell/plugins/acme.gone/*\n' >"$dir/scripts/smoke/rows/stale.sh"
  printf '# inputs: shell/plugins/acme.other/*\n# inputs: shell/Core/Keys.qml\ncat <<EOF\nnever closed\n' >"$dir/scripts/smoke/rows/twice.sh"
  printf '# inputs:\n' >"$dir/scripts/smoke/rows/blank.sh"
  if [[ $variant == slow ]]; then
    printf '%s\n' '# Measured seconds.' 'launcher 600' >"$dir/scripts/smoke/rows.secs"
  fi
  if [[ $variant == unreadable-load ]]; then
    printf '\377\n' >"$dir/shell/Core/Unreadable.qml"
  fi
  # The VPN decisions table row owns scripts/fixtures/vpn/*; the nested
  # smoke table row does not, and the vpn row's input line names it.
  if [[ $variant == table-owned ]]; then
    mkdir -p "$dir/scripts/fixtures/vpn"
    printf 'details\n' >"$dir/scripts/fixtures/vpn/details.txt"
    printf '# inputs: scripts/fixtures/vpn/*\n' >"$dir/scripts/smoke/rows/vpn.sh"
    sed -i 's/^start-order$/vpn\nstart-order/' "$dir/scripts/smoke/rows.list"
  fi
  if [[ $variant == failed-load ]]; then
    printf 'raise RuntimeError("planted")\n' >>"$dir/scripts/qml_source.py"
  fi
  if [[ $variant == chain ]]; then
    mkdir -p "$dir/shell/Ui/foundation" "$dir/shell/Ui/overlay" "$dir/shell/Lib"
    cp -- "$repo/shell/Ui/qmldir" "$dir/shell/Ui/qmldir"
    printf 'clean\n' >"$dir/shell/Ui/foundation/ImagePool.qml"
    printf 'clean\n' >"$dir/shell/Ui/overlay/DismissScope.qml"
    printf 'Leaf {}\n' >"$dir/shell/Lib/Mid.qml"
    printf 'clean\n' >"$dir/shell/Lib/Leaf.qml"
    printf '%s\n' 'import qs.Ui' 'import qs.Lib' 'Mid { DismissScope {} }' 'ImagePool.size' >"$dir/shell/plugins/acme.launcher/Panel.qml"
  fi
  if [[ $variant == loads ]]; then
    python3 - "$repo" "$dir" <<'PYLOADS'
import fnmatch, os, pathlib, re, sys
repo, target = map(pathlib.Path, sys.argv[1:3])
# The real updates and agent-warden rows' input lines, with the real text of
# each shell file they match and of the shared component's path through
# BarItem, so the reading follows the real loads; other files are neutral.


def matches(pattern):
    """The files under the checkout PATTERN matches as validate matches a
    path, * across a /."""
    wild = [pattern.index(c) for c in '*?[' if c in pattern]
    if not wild:
        return [pattern] if (repo / pattern).is_file() else []
    found = []
    for folder, _dirs, names in os.walk(repo / pattern[:min(wild)].rsplit('/', 1)[0]):
        for name in names:
            relative = os.path.relpath(os.path.join(folder, name), repo)
            if fnmatch.fnmatchcase(relative, pattern):
                found.append(relative)
    return found


for row in ('updates', 'agent-warden'):
    lines = re.findall(r'^# inputs: (.+)$', (repo / f'scripts/smoke/rows/{row}.sh').read_text(), re.M)
    assert len(lines) == 1
    for pattern in lines[0].split():
        files = matches(pattern)
        assert files, pattern
        for relative in files:
            original, path = repo / relative, target / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if relative.startswith('shell/'):
                path.write_bytes(original.read_bytes())
            elif not path.exists():
                path.write_text('# neutral input\n')
    (target / f'scripts/smoke/rows/{row}.sh').write_text('# inputs: ' + lines[0] + '\n')
for relative in ('shell/Ui/qmldir', 'shell/Ui/controls/BarItem.qml', 'shell/Ui/feedback/Badge.qml'):
    path = target / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((repo / relative).read_bytes())
row_list = target / 'scripts/smoke/rows.list'
text = row_list.read_text()
assert text.count('start-order\n') == 1
row_list.write_text(text.replace('start-order\n', 'updates\nagent-warden\nstart-order\n'))
PYLOADS
  fi
  if [[ $variant == tailscale-values || $variant == tailscale-values-control ]]; then
    python3 - "$repo" "$dir" "$variant" <<'PYTAILSCALEINPUT'
import glob, pathlib, re, sys
repo, target = map(pathlib.Path, sys.argv[1:3])
variant = sys.argv[3]
source = (repo / 'scripts/smoke/rows/tailscale.sh').read_text()
lines = re.findall(r'^# inputs: (.+)$', source, re.M)
assert len(lines) == 1
inputs = lines[0]
for pattern in inputs.split():
    for original in glob.glob(str(repo / pattern)):
        original = pathlib.Path(original)
        path = target / original.relative_to(repo)
        if original.is_dir():
            path.mkdir(parents=True, exist_ok=True)
            # Git tracks files only. Preserve matched directories in this
            # committed fixture even when their contents are not inputs.
            (path / '.fixture').touch()
        if original.is_file():
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('# neutral input\n')
if variant == 'tailscale-values-control':
    edge = 'shell/Commons/SettingValues.js '
    assert inputs.count(edge) == 1
    inputs = inputs.replace(edge, '')
(target / 'scripts/smoke/rows/tailscale.sh').write_text('# inputs: ' + inputs + '\n')
(target / 'scripts/smoke/rows/device-fakes.sh').write_text('# inputs: scripts/smoke/fixtures/devices/*\n')
row_list = target / 'scripts/smoke/rows.list'
text = row_list.read_text()
assert text.count('start-order\n') == 1
row_list.write_text(text.replace('start-order\n', 'device-fakes\ntailscale\nstart-order\n'))
PYTAILSCALEINPUT
  fi
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m smoke-rows
}
smoke_always='bare,stale,twice,blank,lost'
smoke_core='bar,hyprland-consent,session'
smoke_tail='start-order,auth-sentinel'

# Unknown inline edit operands retain the producing row's existing reach.
# An unrelated source must keep its grant, so a global fallback cannot pass.
for variant in literal unknown-needle unknown-target unknown-target-output unrelated; do
  d="$tmp/comment-inline-$variant"; smoke_fixture "$d"
  printf '# inputs: shell/plugins/acme.other/*\n' >"$d/scripts/smoke/rows/twice.sh"
  file=shell/plugins/acme.launcher/Panel.qml
  [[ $variant != unrelated ]] || file=shell/Core/Consent.qml
  printf '// ordinary old\n' >>"$d/$file"
  inline_target="p = Path('shell/plugins/acme.launcher/Panel.qml')"
  inline_needle='old = "clean"'
  case "$variant" in
    unknown-needle|unrelated) inline_needle='old = make_needle()' ;;
    unknown-target) inline_target='p = Path(sys.argv[1]) / choose_name()' ;;
    unknown-target-output) inline_target=$'p = Path(sys.argv[1]) / choose_name()\noutput = Path("shell/plugins/acme.launcher/Panel.qml")' ;;
  esac
  printf '%s\n' 'python3 - "$repo" <<'"'PY'" 'from pathlib import Path' 'import sys' "$inline_target" 'text = p.read_text()' "$inline_needle" 'assert text.count(old) == 1' 'p.write_text(text.replace(old, "changed"))' 'PY' >>"$d/scripts/smoke/rows/launcher.sh"
  commit "$d" inline-producer
  plant "$d/$file" '// ordinary old' '// ordinary changed'
  test_area=all test_args=(--changed HEAD --list)
  case "$variant" in
    literal|unrelated) row "$variant inline dependency permits the comment grant" "$d" 0 "" '!scripts/qml-smoke.sh' 'python3 scripts/check-smoke-needles.py' ;;
    *) row_re "$variant inline dependency retains product reach" "$d" 0 "" '%^scripts/qml-smoke.sh --rows .*launcher' ;;
  esac
done
test_args=()
smoke_launcher="scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_always,$smoke_tail"
smoke_notify="scripts/qml-smoke.sh --rows $smoke_core,notifications,notifications-keys,$smoke_always,$smoke_tail"
smoke_none="scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,$smoke_tail"
smoke_tailscale="scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,device-fakes,tailscale,$smoke_tail"
smoke_badge="scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,updates,agent-warden,$smoke_tail"
# name|changed paths, a removed one led by -|scope|wanted plan|mutant|fixture variant
smoke_cases=(
  "the shared byte counter selects its Tailscale runtime consumer|shell/Commons/SettingValues.js|changed|scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,device-fakes,tailscale,$smoke_tail||tailscale-values"
  "control: losing the Tailscale byte counter input skips its runtime consumer|shell/Commons/SettingValues.js|changed|$smoke_none||tailscale-values-control"
  "a change to a Settings file the Tailscale row draws selects it, the status line among them|shell/plugins/vgs.settings/StatusLine.qml|changed|$smoke_tailscale||tailscale-values"
  "a change to the Settings field selects the Tailscale row, which draws a field|shell/Ui/controls/SettingField.qml|changed|$smoke_tailscale||tailscale-values"
  "a shared component selects the real rows that draw it through another file|shell/Ui/feedback/Badge.qml|changed|$smoke_badge||loads"
  "control: without the load reading the rows that draw a shared component drop out|shell/Ui/feedback/Badge.qml|changed|$smoke_none|loads|loads"
  "a qmldir change selects the real rows whose files import its directory|shell/Ui/qmldir|changed|$smoke_badge||loads"
  "control: without the qmldir edge a qmldir change drops the rows that import it|shell/Ui/qmldir|changed|$smoke_none|qmldir-edge|loads"
  "a file a row's file loads only through another selects the row|shell/Lib/Leaf.qml|changed|$smoke_launcher||chain"
  "control: without the walk past a loader the row that loads it through another drops out|shell/Lib/Leaf.qml|changed|$smoke_none|chain|chain"
  "a qmldir singleton a row's file names selects the row|shell/Ui/foundation/ImagePool.qml|changed|$smoke_launcher||chain"
  "control: without the qmldir's singletons the row that names one drops out|shell/Ui/foundation/ImagePool.qml|changed|$smoke_none|qmldir-every|chain"
  "a qmldir internal type a row's file names selects the row|shell/Ui/overlay/DismissScope.qml|changed|$smoke_launcher||chain"
  "control: without the qmldir's internal types the row that names one drops out|shell/Ui/overlay/DismissScope.qml|changed|$smoke_none|qmldir-every|chain"
  "a removed file a row's file loaded runs every row|-shell/Lib/Leaf.qml|changed|scripts/qml-smoke.sh||chain"
  "control: a removed file a row's file loaded no longer runs every row|-shell/Lib/Leaf.qml|changed|$smoke_none|absent|chain"
  "a load reading that fails runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh||failed-load"
  "control: a load reading that fails no longer runs every row|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher|failed-load|failed-load"
  "control: a shell file the load reading cannot read no longer runs every row|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher|unreadable-load|unreadable-load"
  "one plugin selects the core rows, its own and the rows that always run|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher||rows"
  "control: a row with no input line no longer runs|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,stale,twice,blank,lost,$smoke_tail|missing|rows"
  "control: a row whose glob matches nothing no longer runs|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,bare,twice,blank,lost,$smoke_tail|matches-nothing|rows"
  "control: a row with two input lines no longer runs|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,bare,stale,blank,lost,$smoke_tail|lines|rows"
  "control: a row with an empty input line no longer runs|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,bare,stale,twice,lost,$smoke_tail|empty|rows"
  "control: a row whose file cannot be read no longer runs|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,bare,stale,twice,blank,$smoke_tail|unreadable|rows"
  "control: a changed path no longer selects its row|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_none|path|rows"
  "control: the core rows no longer run|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows launcher,$smoke_always|core|rows"
  "a row that names another row's file brings that row|shell/Core/Keys.qml|changed|$smoke_notify||rows"
  "control: the rows a row reads no longer run|shell/Core/Keys.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,notifications-keys,$smoke_always,$smoke_tail|closure|rows"
  "two rows that read each other bring each other once|shell/plugins/acme.notify/Panel.qml|changed|$smoke_notify||rows"
  "control: a row in a cycle no longer brings the other|shell/plugins/acme.notify/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,notifications,$smoke_always,$smoke_tail|closure|rows"
  "a harness change runs every row|scripts/smoke/harness.sh|changed|scripts/qml-smoke.sh||rows"
  "control: a harness change no longer runs every row|scripts/smoke/harness.sh|changed|$smoke_none|harness|rows"
  "a change to a file the harness line names runs every row|scripts/smoke/helper/click.c|changed|scripts/qml-smoke.sh||rows"
  "control: a change to a file the harness line names no longer runs every row|scripts/smoke/helper/click.c|changed|$smoke_none|library|rows"
  "a harness with no input line runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh||no-harness-line"
  "control: a harness with no input line no longer runs every row|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher|harness-line|no-harness-line"
  "a runner change runs every row|scripts/qml-smoke.sh|changed|scripts/qml-smoke.sh||rows"
  "control: a runner change no longer runs every row|scripts/qml-smoke.sh|changed|$smoke_none|runner|rows"
  "an input line reader change runs every row|scripts/smoke/row-inputs.sh|changed|scripts/qml-smoke.sh||rows"
  "control: an input line reader change no longer runs every row|scripts/smoke/row-inputs.sh|changed|$smoke_none|reader|rows"
  "a runner that does not list a core row runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh||no-core"
  "control: a runner that does not list a core row no longer runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_always,start-order|core-missing|no-core"
  "an unknown input runs every row|shell/plugins/acme.launcher/Panel.qml new-source.bin|changed|scripts/qml-smoke.sh||rows"
  "control: an unknown input no longer runs every row|shell/plugins/acme.launcher/Panel.qml new-source.bin|changed|$smoke_launcher|unknown|rows"
  "--full runs every row|shell/plugins/acme.launcher/Panel.qml|full|scripts/qml-smoke.sh||rows"
  "control: --full no longer runs every row|shell/plugins/acme.launcher/Panel.qml|full|$smoke_none|full|rows"
  "a path another table row owns selects the smoke rows that name it|scripts/fixtures/vpn/details.txt|changed|scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,vpn,$smoke_tail||table-owned"
  "control: a path another table row owns no longer selects the nested smoke|scripts/fixtures/vpn/details.txt|changed||table-reach|table-owned"
  "a change to a row's own file selects that row|scripts/smoke/rows/launcher.sh|changed|$smoke_launcher||rows"
  "control: a change to a row's own file no longer selects that row|scripts/smoke/rows/launcher.sh|changed|$smoke_none|own-file|rows"
)
# Each mutant: the text it replaces in validate, then its replacement.
declare -A smoke_mutant_old=(
  [missing]=$'missing; add to the leading comment block of %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 1'
  [lines]=$'"$key" "$smoke_inputs_fault" "$file" >&2; return 1'
  [empty]=$'empty; fix the line in %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 1'
  [unreadable]=$'unreadable path=%s\\n\' "$key" "$file" >&2; return 1'
  [matches-nothing]='      smoke_glob_unmatched=true'
  [path]='      *) for row in $smoke_reach; do want[$row]=1; done ;;'
  [core]='  for row in "${smoke_core[@]}"; do want[$row]=1; done'
  [core-missing]='smoke_read_fault="core-row-missing row=$row"; return 0; fi'
  [closure]='do smoke_close_set[$needed]=1; done'
  [harness]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [library]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [runner]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [reader]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [harness-line]='    smoke_read_fault=harness-line-unreadable'
  [unknown]=$'      export VGS_VALIDATE_CHANGED="$paths_file"\n      smoke_scoped=true\n      smoke_table_reach\n    fi'
  [table-reach]=$'      smoke_scoped=true\n      smoke_table_reach\n'
  [full]=$'smoke_scoped=false\naffected=()'
  [own-file]='for glob in "$file" "${smoke_globs[@]}"; do'
  [loads]='    smoke_load_reach "$2" "$1"'
  [qmldir-edge]='loads |= consulted'
  [chain]='queue+=("$loader")'
  [qmldir-every]='every=True)'
  [absent]=$'    printf -v smoke_reach \'untraced reason=qml-load-target-absent path=%q\' "$2"'
  [failed-load]=$'    smoke_read_fault=qml-loads-failed; return 0\n  fi'
  [unreadable-load]=$'unreadable) printf -v smoke_read_fault \'qml-loads-unreadable path=%q\' "$loader${loaded:+ $loaded}"; return 0 ;;'
)
declare -A smoke_mutant_new=(
  [missing]=$'missing; add to the leading comment block of %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 0'
  [lines]=$'"$key" "$smoke_inputs_fault" "$file" >&2; return 0'
  [empty]=$'empty; fix the line in %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 0'
  [unreadable]=$'unreadable path=%s\\n\' "$key" "$file" >&2; return 0'
  [matches-nothing]='      :'
  [path]='      *) ;;'
  [core]='  :'
  [core-missing]=':; fi'
  [closure]='do :; done'
  [harness]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh "${smoke_globs[@]}")'
  [library]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/row-inputs.sh scripts/smoke/harness.sh)'
  [runner]='smoke_harness_inputs=(scripts/smoke/row-inputs.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [reader]='smoke_harness_inputs=(scripts/qml-smoke.sh scripts/smoke/harness.sh "${smoke_globs[@]}")'
  [harness-line]='    :'
  [unknown]=$'      export VGS_VALIDATE_CHANGED="$paths_file"\n      smoke_table_reach\n    fi\n    smoke_scoped=true'
  [table-reach]=$'      smoke_scoped=true\n'
  [full]=$'smoke_scoped=true\naffected=()'
  [own-file]='for glob in "${smoke_globs[@]}"; do'
  [loads]='    :'
  [qmldir-edge]='pass'
  [chain]=':'
  [qmldir-every]='every=False)'
  [absent]='    :'
  [failed-load]=$'    return 0\n  fi'
  [unreadable-load]='unreadable) return 0 ;;'
)
for spec in "${smoke_cases[@]}"; do
  IFS='|' read -r name files scope wanted mutant variant <<<"$spec"
  d="$tmp/smoke-rows-${mutant:-real}-${files//[\/ ]/-}-$scope-$variant"; smoke_fixture "$d" "$variant"
  if [[ -n $mutant ]]; then
    python3 - "$d/scripts/validate" "${smoke_mutant_old[$mutant]}" "${smoke_mutant_new[$mutant]}" <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
    "${base_env[@]}" git -C "$d" commit -q -am control
  fi
  # A comment, so the changed stand-in runner still lists its rows.
  for file in $files; do
    if [[ $file == -* ]]; then rm -- "${d:?}/${file#-}"; else printf '# changed\n' >>"$d/$file"; fi
  done
  # This case proves ordinary input reach. The text-only exception has its
  # own real-README cases above, so keep this fixture a mixed change.
  [[ $variant != table-owned ]] || printf '# mixed change\n' >>"$d/kendex.settings.toml"
  scope_args=(--changed HEAD)
  [[ $scope == changed ]] || scope_args=(--full)
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml "${scope_args[@]}" --list 2>"$tmp/smoke-rows.err")" || status=$?
  plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
  if [[ $status == 0 && $plan == "$wanted" ]]; then ok "$name"; else fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-rows.err"; fi
done
# A reached row whose median is ten minutes stays selected, and the
# summary counts it. The slow fixture's seconds file puts launcher at
# 600 s, so this fails if a reader of scripts/smoke/rows.secs that drops a
# row over a bound returns. The lanes and the overseer read the summary
# line.
test_area=qml
test_args=(--changed HEAD --list)
d="$tmp/smoke-rows-slow"; smoke_fixture "$d" slow
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "a reached row with a long median stays selected" "$d" 0 "" \
  "$smoke_launcher" "validate: smoke-rows=some selected=11 total=14"
# A shell file the load reading cannot read, or a reading that fails, runs
# every row and says why in one line; the table above holds the controls.
d="$tmp/smoke-rows-unreadable-load-line"; smoke_fixture "$d" unreadable-load
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "a shell file the load reading cannot read runs every row and names itself" "$d" 0 "" \
  "scripts/qml-smoke.sh" "validate: smoke-rows=all reason=qml-loads-unreadable path=shell/Core/Unreadable.qml" '!validate: smoke-rows=some'
d="$tmp/smoke-rows-failed-load-line"; smoke_fixture "$d" failed-load
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "a load reading that fails runs every row and says so" "$d" 0 "" \
  "scripts/qml-smoke.sh" "validate: smoke-rows=all reason=qml-loads-failed" '!validate: smoke-rows=some'
# A fix round after a rebase: the lane validated its launcher change at
# $lane, main then changed acme.notify, the lane rebased onto it and edits
# launcher again. --changed $lane selects the lane's own paths only; a base
# HEAD still holds, main's old tip, selects every path since. Each control
# removes one side of the ancestor test and wants the other side's plan.
rebase_fixture() { # DIR
  local dir="$1"
  smoke_fixture "$dir"
  "${base_env[@]}" git -C "$dir" branch -q -f trunk HEAD
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
  printf 'lane\n' >>"$dir/shell/plugins/acme.launcher/Panel.qml"
  "${base_env[@]}" git -C "$dir" commit -q -am lane
  "${base_env[@]}" git -C "$dir" checkout -q trunk
  printf 'main\n' >>"$dir/shell/plugins/acme.notify/Panel.qml"
  "${base_env[@]}" git -C "$dir" commit -q -am main
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
  "${base_env[@]}" git -C "$dir" checkout -q feature
}
smoke_both="scripts/qml-smoke.sh --rows $smoke_core,launcher,notifications,notifications-keys,$smoke_always,$smoke_tail"
# name~base (lane or old-main)~wanted plan~mutant old~mutant new
rebase_cases=(
  "a fix round after a rebase selects the lane's own paths~lane~$smoke_launcher~~"
  "control: a rebased base no longer narrows~lane~$smoke_both~  [[ \$status -eq 1 ]] || return \"\$status\"~  return 0"
  "a base HEAD holds selects every path since~old-main~$smoke_both~~"
  "control: a base HEAD holds narrows too~old-main~$smoke_launcher~  [[ \$status -eq 1 ]] || return \"\$status\"~  :"
)
for spec in "${rebase_cases[@]}"; do
  IFS='~' read -r name base_kind wanted old new <<<"$spec"
  d="$tmp/smoke-rebase-$base_kind-${old:+control}"; rebase_fixture "$d"
  lane="$("${base_env[@]}" git -C "$d" rev-parse HEAD)"
  old_main="$("${base_env[@]}" git -C "$d" rev-parse HEAD^)"
  if [[ -n $old ]]; then
    python3 - "$d/scripts/validate" "$old" "$new" <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
    "${base_env[@]}" git -C "$d" commit -q -am control
    lane="$("${base_env[@]}" git -C "$d" rev-parse HEAD)"
  fi
  "${base_env[@]}" git -C "$d" rebase -q trunk
  printf 'fix\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
  base="$lane"; [[ $base_kind == lane ]] || base="$old_main"
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml --changed "$base" --list 2>"$tmp/smoke-rebase.err")" || status=$?
  plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
  if [[ $status == 0 && $plan == "$wanted" ]]; then ok "$name"; else fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-rebase.err"; fi
done
# A runner that lists no row runs every row and names why; with that branch
# removed, the empty list reaches the core check, which names another
# reason.
test_area=qml
test_args=(--changed HEAD --list)
d="$tmp/smoke-rows-no-list"; smoke_fixture "$d" no-list
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "a runner that lists no row runs every row" "$d" 0 "" \
  "scripts/qml-smoke.sh" "validate: smoke-rows=all reason=row-list-unreadable"
d="$tmp/smoke-rows-no-list-control"; smoke_fixture "$d" no-list
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
old = "smoke_read_fault=row-list-unreadable; return 0"
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, "smoke_read_fault=row-list-unreadable"))
PY
"${base_env[@]}" git -C "$d" commit -q -am control
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "control: a runner that lists no row no longer names its own reason" "$d" 0 "" \
  "validate: smoke-rows=all reason=core-row-missing row=bar"
# The self-check names each line that cannot select, with the line to add
# or fix, and leaves the exit status alone, on a listing run and a real one.
d="$tmp/smoke-rows-self-check"; smoke_fixture "$d"
printf 'changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
smoke_self_check=(
  "validate: smoke-input row=bare missing; add to the leading comment block of scripts/smoke/rows/bare.sh: # inputs: GLOB [GLOB...]"
  "validate: smoke-input row=stale glob=shell/plugins/acme.gone/* matches-nothing; fix the line in scripts/smoke/rows/stale.sh: # inputs: shell/plugins/acme.gone/*"
  "validate: smoke-input row=twice lines=2; keep one line in scripts/smoke/rows/twice.sh: # inputs: GLOB [GLOB...]"
  "validate: smoke-input row=blank empty; fix the line in scripts/smoke/rows/blank.sh: # inputs: GLOB [GLOB...]"
  "validate: smoke-input row=lost unreadable path=scripts/smoke/rows/lost.sh"
  "validate: smoke-input harness=scripts/smoke/harness.sh glob=scripts/smoke/gone.sh matches-nothing; fix the line in scripts/smoke/harness.sh: # inputs: scripts/smoke/verdict.sh scripts/smoke/helper/* scripts/smoke/gone.sh"
  "validate: smoke-input row=other function=launcher_close from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other function=launcher_open from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other function=launcher_array_call from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other variable=launcher_array_read from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other variable=launcher_dir from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other variable=launcher_part from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input unparsed path=scripts/smoke/rows/twice.sh; the function and variable check cannot read it to its end"
)
row "the smoke input self-check names each line to add or fix" "$d" 0 "" \
  "${smoke_self_check[@]}" '!row=launcher' '!row=session' '!row=notifications-keys' '!variable=sandbox' '!variable=failures' '!variable=launcher_mode' '!variable=TMPDIR'
test_args=(--changed HEAD)
row "the smoke input self-check leaves a real run passing" "$d" 0 "" \
  "${smoke_self_check[@]}" '!variable=TMPDIR' "validate: ok"
test_args=(--changed HEAD --list)
# Each control: a copy of validate whose function and variable check drops
# one rule, which wants that rule's line gone and another rule's kept, or,
# for a rule that exempts a read, the line it exempts named: a call where a
# command stands, a call through a runner's command operand, a variable
# read, a file the scan cannot read to its end, a row file run through
# smoke_row, a row's own definitions, the harness's, the libraries it
# sources, and a row file the line names.
# name|text the control replaces in validate|its replacement|wanted lines
smoke_reads_controls=(
  "command|            if name:|            if name and at > head(words):|!row=other function=launcher_close|~row=other function=launcher_open"
  "runner|    runs.update(scan.runners)|    runs.update({})|!row=other function=launcher_open|~row=other function=launcher_close"
  "variable|for kind, used, field in ((\"function\", \"calls\", \"funcs\"), (\"variable\", \"reads\", \"sets\")):|for kind, used, field in ((\"function\", \"calls\", \"funcs\"),):|!row=other variable=launcher_dir|~row=other function=launcher_open"
  "array-values|                    i = self.code(i + 1, \")\", values=True)|                    i = self.code(i + 1, \")\")|~row=other variable=TMPDIR|~row=other variable=launcher_dir"
  "unparsed|if text is None or (scan := Scan(text)).broken:|if text is None or not (scan := Scan(text)):|!smoke-input unparsed path=scripts/smoke/rows/twice.sh|~row=other function=launcher_open"
  "child|            queue += [f\"scripts/smoke/rows/{child}.sh\" for child in scans[rel].rows if child not in listed]|            queue += []|!row=other variable=launcher_part|~row=other variable=launcher_dir"
  "own|owned[row][used] - owned[row][field] - side_owned[field]|owned[row][used] - side_owned[field]|~row=other variable=launcher_mode"
  "harness|side_owned = {field: set().union(*(scans[rel].__dict__[field] for rel in side if rel in scans)) for field in (\"funcs\", \"sets\")}|side_owned = {field: set() for field in (\"funcs\", \"sets\")}|~row=other variable=sandbox"
  "library|        queue += SOURCE.findall(texts[rel] or \"\")|        queue += []|~row=other variable=failures|!row=other variable=sandbox"
  "declared|named=true|named=false|~row=notifications-keys function=notify_open"
)
for spec in "${smoke_reads_controls[@]}"; do
  IFS='|' read -r mutant old new wanted_a wanted_b <<<"$spec"
  d="$tmp/smoke-reads-$mutant"; smoke_fixture "$d"
  control_file="$d/scripts/validate"
  [[ $mutant != array-values ]] || control_file="$d/scripts/shell_source.py"
  python3 - "$control_file" "$old" "$new" <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
  "${base_env[@]}" git -C "$d" commit -q -am control
  printf 'changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
  row_re "control: the function and variable check without its $mutant rule" "$d" 0 "" "$wanted_a" ${wanted_b:+"$wanted_b"}
done
d="$tmp/smoke-rows-self-check-harness"; smoke_fixture "$d" no-harness-line
printf 'changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "the smoke input self-check names a harness with no input line" "$d" 0 "" \
  "validate: smoke-input harness=scripts/smoke/harness.sh missing; add to the leading comment block of scripts/smoke/harness.sh: # inputs: GLOB [GLOB...]" \
  "validate: smoke-rows=all reason=harness-line-unreadable"
# A real row and its real shared helpers, without starting their runtime.
# The fixture keeps the row's whole source and declared inputs. Only the
# changed helper, hunk shape or incoming commit varies; expected plans do
# not come from the reach reader.
function_fixture() { # DIR harness|library
  local dir="$1" location="$2"
  smoke_fixture "$dir"
  python3 - "$repo" "$dir" "$location" <<'PYFUNCTION'
import fnmatch, pathlib, re, subprocess, sys
repo, target = map(pathlib.Path, sys.argv[1:3])
location = sys.argv[3]
source = (repo / "scripts/smoke/rows/gallery.sh").read_text()
inputs = re.findall(r"^# inputs: (.+)$", source, re.M)
assert len(inputs) == 1
tracked = subprocess.check_output(["git", "-C", str(repo), "ls-files", "-z"]).decode().split("\0")
for pattern in inputs[0].split():
    matches = [path for path in tracked if path and fnmatch.fnmatchcase(path, pattern)]
    assert matches, pattern
    for path in matches:
        destination = target / path
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text("# neutral input\n" if path.endswith(".sh") else "")
(target / "scripts/smoke/rows/gallery.sh").write_text(source)
row_list = target / "scripts/smoke/rows.list"
text = row_list.read_text()
assert text.count("start-order\n") == 1
row_list.write_text(text.replace("start-order\n", "gallery\nstart-order\n"))
text = (repo / "scripts/smoke/harness.sh").read_text()
start, end = "# Property readback is separate", "# qs_list ARG"
assert text.count(start) == text.count(end) == 1
helpers = text.split(start)[1].split("\n", 1)[1].split(end)[0]
harness = target / "scripts/smoke/harness.sh"
if location == "library":
    (target / "scripts/smoke/helper/orbs.sh").write_text("# Orb readers\n" + helpers)
    with harness.open("a") as out:
        out.write('source "$repo/scripts/smoke/helper/orbs.sh"\n')
else:
    with harness.open("a") as out:
        out.write("# Orb readers\n" + helpers)
PYFUNCTION
  commit "$dir" real-gallery
}
smoke_gallery="scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,gallery,$smoke_tail"
test_area=qml
test_args=(--changed HEAD --list)
for function_case in harness library transitive-control top-level shared-line unreadable; do
  d="$tmp/function-reach-$function_case"
  location=harness; [[ $function_case != library ]] || location=library
  function_fixture "$d" "$location"
  function_file="$d/scripts/smoke/harness.sh"
  [[ $location != library ]] || function_file="$d/scripts/smoke/helper/orbs.sh"
  if [[ $function_case == transitive-control ]]; then
    plant "$d/scripts/validate" '            reached |= callers' '            break'
    commit "$d" control
  fi
  case "$function_case" in
    top-level) printf '# top-level edit\n' >>"$function_file"; wanted=scripts/qml-smoke.sh ;;
    shared-line)
      plant "$function_file" 'gallery_orb_offset() {' 'true; gallery_orb_offset() {'
      wanted=scripts/qml-smoke.sh ;;
    unreadable) printf "'\n" >>"$function_file"; wanted=scripts/qml-smoke.sh ;;
    *)
      plant "$function_file" $'orbs=json.load(sys.stdin)\nindex=int(sys.argv[1])' $'orbs=json.load(sys.stdin)\nindex=int(sys.argv[1])+0'
      wanted="$smoke_gallery"
      [[ $function_case != transitive-control ]] || wanted="scripts/qml-smoke.sh" ;;
  esac
  row "function reach $function_case uses the real Gallery row, never launcher" "$d" 0 "" "$wanted"
done

# PluginLogic's real functions and Dispatch's real import alias, without a
# nested runtime. The rows drive separate plugin entry points; loading the
# library alone does not observe every exported function.
core_observation_case() { # CASE
  local variant="$1" d="$tmp/core-observation-$1" wanted="$smoke_none"
  smoke_fixture "$d"
  cp -- "$repo/shell/Core/PluginLogic.js" "$repo/shell/Core/Dispatch.js" "$repo/shell/Core/HyprlandLayer.js" "$d/shell/Core/"
  printf 'import "PluginLogic.js" as Logic\nQtObject { property var value: Logic.clone({}) }\n' >"$d/shell/Core/HyprlandLayer.qml"
  printf 'import "../../Core/PluginLogic.js" as Logic\nQtObject { property bool value: Logic.isPlainObject({}) }\n' >"$d/shell/plugins/acme.launcher/Panel.qml"
  printf 'import "../../Core/Dispatch.js" as Dispatch\nQtObject { property var value: Dispatch.QUEUE_LIMIT }\n' >"$d/shell/plugins/acme.other/Panel.qml"
  case "$variant" in
    callback)
      printf 'import "../../Core/PluginLogic.js" as Logic\nQtObject { property var value: Logic.controlValue }\n' >"$d/shell/plugins/acme.launcher/Panel.qml" ;;
    computed)
      printf 'import "../../Core/PluginLogic.js" as Logic\nQtObject { property var value: Logic[method]({}) }\n' >"$d/shell/plugins/acme.launcher/Panel.qml" ;;
    direct)
      printf '# inputs: shell/plugins/acme.launcher/* shell/Core/PluginLogic.js\n' >"$d/scripts/smoke/rows/launcher.sh" ;;
  esac
  commit "$d" core-observation
  case "$variant" in
    alias)
      plant "$d/shell/Core/HyprlandLayer.qml" 'Logic.clone({})' 'Logic.clone({ changed: true })' ;;
    unobserved|direct|computed)
      plant "$d/shell/Core/PluginLogic.js" 'function fieldRows(schema, status) {' $'function fieldRows(schema, status) {\n    schema = schema || {};' ;;
    observed)
      plant "$d/shell/Core/PluginLogic.js" 'return value !== null && typeof value === "object" && !Array.isArray(value);' 'return value !== null && !Array.isArray(value) && typeof value === "object";' ;;
    callback)
      plant "$d/shell/Core/PluginLogic.js" 'return value === undefined ? undefined : JSON.parse(JSON.stringify(value));' 'return value === undefined ? value : JSON.parse(JSON.stringify(value));' ;;
    top-level)
      plant "$d/shell/Core/PluginLogic.js" 'var DEFAULT_ICON = "package";' 'var DEFAULT_ICON = "box";' ;;
    seam)
      plant "$d/shell/Core/PluginLogic.js" $'function isPlainObject(value) {\n    return value' $'var outside = true;\nfunction isPlainObject(value) {\n    return value' ;;
    removed)
      plant "$d/shell/Core/PluginLogic.js" $'function isPlainObject(value) {\n    return value !== null && typeof value === "object" && !Array.isArray(value);\n}' ' ' ;;
  esac
  case "$variant" in
    observed|callback|computed|direct|removed) wanted="$smoke_launcher" ;;
    top-level|seam) wanted="$smoke_launcher" ;;
  esac
  row "core function observation $variant" "$d" 0 "" "$wanted"
}
parallel_cases core_observation_case core-observation alias unobserved observed callback computed direct top-level seam removed

# These are actual incoming commits and a rebase, not an injected path list.
# Gallery's own file stays unchanged across restack. Its unchanged helper is
# an input even though the branch never edited that helper's pathname.
for incoming in unrelated helper core own-fix input-reach-control; do
  d="$tmp/restack-input-$incoming"; function_fixture "$d" harness
  "${base_env[@]}" git -C "$d" branch -q -f trunk HEAD
  "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
  if [[ $incoming == input-reach-control ]]; then
    plant "$d/scripts/validate" 'then reached=true; restack_qml_reached=true; fi' 'then :; fi'
    commit "$d" control
    "${base_env[@]}" git -C "$d" branch -q -f trunk HEAD
    "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
  fi
  printf '// branch\n' >>"$d/shell/plugins/vgs.gallery/Window.qml"
  commit "$d" lane
  lane="$("${base_env[@]}" git -C "$d" rev-parse HEAD)"
  "${base_env[@]}" git -C "$d" checkout -q trunk
  case "$incoming" in
    helper|input-reach-control)
      plant "$d/scripts/smoke/harness.sh" $'orbs=json.load(sys.stdin)\nindex=int(sys.argv[1])' $'orbs=json.load(sys.stdin)\nindex=int(sys.argv[1])+0'
      wanted="$smoke_gallery"
      [[ $incoming != input-reach-control ]] || wanted="" ;;
    core) printf '// incoming\n' >>"$d/shell/Core/Session.qml"; wanted="$smoke_none" ;;
    *) printf '// incoming\n' >>"$d/shell/plugins/acme.notify/Panel.qml"; wanted="" ;;
  esac
  commit "$d" incoming
  "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
  "${base_env[@]}" git -C "$d" checkout -q feature
  "${base_env[@]}" git -C "$d" rebase -q trunk
  if [[ $incoming == own-fix ]]; then
    printf '// fix\n' >>"$d/shell/plugins/vgs.gallery/Window.qml"
    wanted="$smoke_gallery"
  fi
  test_args=(--changed "$lane" --list)
  if [[ -z $wanted ]]; then
    row "restack $incoming intersects incoming reach with the real Gallery inputs" "$d" 0 "" "!scripts/qml-smoke.sh"
  else
    row "restack $incoming intersects incoming reach with the real Gallery inputs" "$d" 0 "" "$wanted" "!scripts/qml-smoke.sh --rows $smoke_core,launcher,"
  fi
done

# Keys owns the unlisted bubble row, whose diagnostics source needs the
# listed caller's input declaration even without a direct symbol read.
# Copy the actual keys input contract; only the diagnostics edge varies.
test_area=tools
test_args=(--changed HEAD)
for source_case in nested-missing nested-named direct-missing direct-named; do
  d="$tmp/smoke-source-$source_case"; smoke_fixture "$d"
  plant "$d/scripts/smoke/rows/other.sh" '# inputs: shell/plugins/acme.other/*' '# inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh'
  printf 'EOF\n' >>"$d/scripts/smoke/rows/twice.sh"
  python3 - "$repo" "$d" "$source_case" <<'PYSOURCEROW'
from pathlib import Path
import re, sys
repo, target = map(Path, sys.argv[1:3])
route, declaration = sys.argv[3].split('-')
inputs = re.findall(r'^# inputs: .+$', (repo / 'scripts/smoke/rows/jarvis-keys.sh').read_text(), re.M)
assert len(inputs) == 1
edge = ' scripts/smoke/rows/diagnostics.sh'
assert inputs[0].count(edge) == 1
line = inputs[0] if declaration == 'named' else inputs[0].replace(edge, '')
source = 'source "$repo/scripts/smoke/rows/diagnostics.sh"\n'
assert (repo / 'scripts/smoke/rows/jarvis-bubble.sh').read_text().count(source) == 1
rows = target / 'scripts/smoke/rows'
(rows / 'jarvis-keys.sh').write_text(line + '\n' + (source if route == 'direct' else 'smoke_row jarvis-bubble\n'))
(rows / 'jarvis-bubble.sh').write_text(source if route == 'nested' else '# No nested source.\n')
(rows / 'diagnostics.sh').write_text('# inputs: scripts/smoke/helper/*\n')
with (target / 'scripts/smoke/rows.list').open('a') as f:
    f.write('jarvis-keys\ndiagnostics\n')
PYSOURCEROW
  commit "$d" source-contract
  printf 'changed\n' >>"$d/scripts/smoke/helper/click.c"
  source_want=0 source_line='!row=jarvis-keys source=diagnostics'
  if [[ $source_case == *-missing ]]; then
    source_want=1
    source_line='~row=jarvis-keys source=diagnostics from=scripts/smoke/rows/diagnostics.sh;'
  fi
  row_re "a $source_case row source checks the copied keys input contract" "$d" "$source_want" "" "$source_line"
done

# The tools row that fails on what the self-check only names. In the
# fixture a helper change selects that row alone. `named` gives other the
# launcher file on its line and `closed` ends the heredoc of twice, so each
# case leaves one defect, or none; `mutant` is a copy of validate whose row
# reads a gap and no longer fails on it. Each edit is committed, so the run
# judges the helper change alone.
# name|fixture variant|edits|wanted exit|wanted lines, `;` between them
smoke_named_label='smoke rows name the rows they read'
smoke_named_gap='validate: smoke-input row=other function=launcher_open from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh'
smoke_named_unparsed='validate: smoke-input unparsed path=scripts/smoke/rows/twice.sh; the function and variable check cannot read it to its end'
smoke_named_cases=(
  "a row that calls another row's function without naming its file fails the check|rows|closed|1|$smoke_named_gap^validate: failed=$smoke_named_label (exit 1)^!smoke-input unparsed"
  "a row file the scan cannot read to its end fails the check|rows|named|1|$smoke_named_unparsed^validate: failed=$smoke_named_label (exit 1)^!row=other function="
  "rows that name the rows they read pass the check|rows|named closed|0|validate: ok^!row=other function=^!smoke-input unparsed"
  "control: a check that no longer fails on a row's unnamed read|rows|closed mutant|0|$smoke_named_gap^validate: ok"
  "a row list the check cannot read is not a pass|no-list||77|validate: smoke-rows=all reason=row-list-unreadable^validate: status=not-measured skipped=$smoke_named_label"
)
test_area=tools
test_args=(--changed HEAD)
for spec in "${smoke_named_cases[@]}"; do
  IFS='|' read -r name variant edits want_exit wanted <<<"$spec"
  d="$tmp/smoke-named-$variant-${edits// /-}"; smoke_fixture "$d" "$variant"
  for edit in $edits; do
    case "$edit" in
      named) plant "$d/scripts/smoke/rows/other.sh" '# inputs: shell/plugins/acme.other/*' '# inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh' ;;
      closed) printf 'EOF\n' >>"$d/scripts/smoke/rows/twice.sh" ;;
      mutant) plant "$d/scripts/validate" $'printf \'%s\\n\' "$line" >&2; status=1' $'printf \'%s\\n\' "$line" >&2; status=0' ;;
      *) echo "test-validate: smoke-named-edit=unknown value=$edit" >&2; exit 1 ;;
    esac
  done
  [[ -z $edits ]] || commit "$d" edits
  printf 'changed\n' >>"$d/scripts/smoke/helper/click.c"
  IFS='^' read -r -a lines <<<"$wanted"
  row "$name" "$d" "$want_exit" "" "${lines[@]}"
done

# The row list is no harness input: a change to it runs the rows its added
# lines name, so moving launcher runs launcher alone, and a comment runs
# nothing; unlisting notifications, whose file stays, runs
# notifications-keys, whose line names that file. Each edit is committed
# and read from the commit before it, so the base is not HEAD. Each control
# is a copy of validate without that rule.
# name~edit of the row list~wanted plan~text the control replaces~its replacement
smoke_list_cases=(
  "a moved row in the row list runs that row alone~move~$smoke_launcher~~"
  "control: a moved row no longer runs~move~$smoke_none~"'  if [[ -z $smoke_reach && $2 == scripts/smoke/rows.list ]]; then'"~  if false; then"
  "a comment in the row list runs no row~comment~$smoke_none~~"
  "control: a comment in the row list no longer reads as one~comment~scripts/qml-smoke.sh~"'    [[ -z $line || $line == '"'#'"'* ]] && continue'"~    :"
  "an unlisted row runs the rows that read it~unlist~scripts/qml-smoke.sh --rows $smoke_core,notifications-keys,$smoke_always,$smoke_tail~~"
  "control: an unlisted row no longer runs the rows that read it~unlist~$smoke_none~"'            [[ " ${smoke_row_lines[$row]-} " != *" scripts/smoke/rows/$needed.sh "* ]] || smoke_reach+=" $row"'"~            :"
)
test_area=qml
test_args=(--changed HEAD~1 --list)
for spec in "${smoke_list_cases[@]}"; do
  IFS='~' read -r name edit wanted old new <<<"$spec"
  d="$tmp/smoke-list-$edit${old:+-control}"; smoke_fixture "$d"
  if [[ -n $old ]]; then plant "$d/scripts/validate" "$old" "$new"; commit "$d" control; fi
  case "$edit" in
    move) plant "$d/scripts/smoke/rows.list" $'launcher\nnotifications\n' $'notifications\n' &&
          plant "$d/scripts/smoke/rows.list" $'other\n' $'other\n# After other.\nlauncher\n' ;;
    comment) plant "$d/scripts/smoke/rows.list" $'# The rows, in run order.\n' $'# The rows, in the order they run.\n' ;;
    unlist) plant "$d/scripts/smoke/rows.list" $'launcher\nnotifications\nnotifications-keys\n' $'launcher\nnotifications-keys\n' ;;
  esac
  commit "$d" edit
  row "$name" "$d" 0 "" "$wanted"
done

# The change base. A fix round's default base is this area's last pass in
# this worktree: the newest commit holding the tree the last passing run
# read. A lane validates its harness work staged and uncommitted, then
# commits it; the next run, after a fix to one row's input, runs that row,
# not every row. A stand-in shader runner keeps the harness round's other
# qml row passing.
d="$tmp/base-fix-round"; smoke_fixture "$d"
d_control="$tmp/base-fix-round-control"; smoke_fixture "$d_control"
plant "$d_control/scripts/validate" 'elif [[ -z ${VGS_VALIDATE_BASE:-} ]] && change_base="$(last_pass)"; then' 'elif false; then'
for dir in "$d" "$d_control"; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/scripts/measure-shader.sh"
  chmod +x "$dir/scripts/measure-shader.sh"
  printf '# changed\n' >>"$dir/scripts/qml-smoke.sh"
  "${base_env[@]}" git -C "$dir" add -A
done
test_args=()
row "a harness round that passes on uncommitted work records the tree it read" "$d" 0 "" \
  "validate: base=$trunk source=merge-base" "validate: smoke-rows=all reason=harness-input path=scripts/qml-smoke.sh" \
  "validate: last-pass=recorded area=qml tree=$("${base_env[@]}" git -C "$d" write-tree)" "validate: ok"
row "the control fixture's harness round records the tree it read" "$d_control" 0 "" \
  "validate: last-pass=recorded area=qml tree=$("${base_env[@]}" git -C "$d_control" write-tree)" "validate: ok"
for dir in "$d" "$d_control"; do
  commit "$dir" harness
  printf 'fix\n' >>"$dir/shell/plugins/acme.launcher/Panel.qml"
done
test_args=(--list)
row "a fix round after the harness round is committed runs the fix's rows" "$d" 0 "" \
  "validate: base=$("${base_env[@]}" git -C "$d" rev-parse HEAD) source=last-pass" "$smoke_launcher"
row "control: a fix round without the last pass runs every row" "$d_control" 0 "" \
  "validate: base=$trunk source=merge-base" "scripts/qml-smoke.sh"
# The record is per area: another area on the same worktree reads no qml
# pass. The control is a copy of validate whose record names no area.
d_area="$tmp/base-fix-round-area-control"; smoke_fixture "$d_area"
plant "$d_area/scripts/validate" 'pass_record="$(git rev-parse --absolute-git-dir)/vgs-validated-$area"' 'pass_record="$(git rev-parse --absolute-git-dir)/vgs-validated"'
printf '#!/usr/bin/env bash\nexit 0\n' >"$d_area/scripts/measure-shader.sh"
chmod +x "$d_area/scripts/measure-shader.sh"
printf '# changed\n' >>"$d_area/scripts/qml-smoke.sh"
commit "$d_area" harness
test_args=()
row "the area control's qml round records its tree" "$d_area" 0 "" "validate: last-pass=recorded area=qml tree=$("${base_env[@]}" git -C "$d_area" rev-parse 'HEAD^{tree}')"
test_area=repo
test_args=(--list)
row "another area reads no qml pass" "$d" 0 "" "validate: base=$trunk source=merge-base"
row "control: another area reads the qml pass of a record that names no area" "$d_area" 0 "" \
  "validate: base=$("${base_env[@]}" git -C "$d_area" rev-parse HEAD) source=last-pass"
test_area=qml

# A run that exits 77, a check that could not run, records nothing: the
# stand-in shader runner exits 77. The control records before the
# not-measured exit.
for variant in real control; do
  d="$tmp/base-record-skipped-$variant"; smoke_fixture "$d"
  [[ $variant == real ]] || plant "$d/scripts/validate" 'if [[ ${#skipped[@]} -gt 0 ]]; then' 'last_pass_record; if [[ ${#skipped[@]} -gt 0 ]]; then'
  printf '#!/usr/bin/env bash\nexit 77\n' >"$d/scripts/measure-shader.sh"
  chmod +x "$d/scripts/measure-shader.sh"
  commit "$d" skipped
done
test_args=()
row "a run that exits 77 records nothing" "$tmp/base-record-skipped-real" 77 "" "!validate: last-pass="
row_re "control: a run that exits 77 records its tree" "$tmp/base-record-skipped-control" 77 "" "~validate: last-pass=recorded area=qml tree="

# A run whose content changes while it runs records nothing: the stand-in
# runner writes a file when it runs. The control reads the tree once.
for variant in real control; do
  d="$tmp/base-record-changed-$variant"; smoke_fixture "$d"
  [[ $variant == real ]] || plant "$d/scripts/validate" '  tree="$(worktree_tree)"' '  tree="$pass_tree"'
  printf '#!/usr/bin/env bash\nexit 0\n' >"$d/scripts/measure-shader.sh"
  chmod +x "$d/scripts/measure-shader.sh"
  printf 'if [[ -z ${1-} ]]; then printf "ran\\n" >>"$(dirname -- "$0")/../ran.txt"; fi\n' >>"$d/scripts/qml-smoke.sh"
  commit "$d" writer
done
test_args=()
row_re "content that changes during the run keeps the pass unrecorded" "$tmp/base-record-changed-real" 0 "" \
  "~validate: last-pass=unrecorded reason=content-changed from=" "!validate: last-pass=recorded"
row_re "control: content that changes during the run no longer keeps the pass unrecorded" "$tmp/base-record-changed-control" 0 "" \
  "~validate: last-pass=recorded area=qml tree="

# The row records. A lane's run is cut off while the nested smoke runs or
# after it, by validate's TERM at the bound or a KILL, and the next run on
# the lane's tree reruns only what did not end, did not prove a pass, or
# changed. Each fixture's stand-ins write what the real runners write for
# the records: the smoke writes each row's results, partial records, judge
# readings, outside-failures and row-secs lines under VGS_SMOKE_RESULTS_DIR
# in the shapes scripts/qml-smoke.sh and harness.sh give them, with the
# closing reading teardown.sh takes as an attempt ends, on a TERM too, and
# the stand-in named in .git/hang reports its PIDs in .git/hung and waits
# to be stopped. Before the cut the case may set, in the git directory:
# edit, which makes the smoke append to the launcher's panel while the run
# reads; harness-line, a lane that removes the harness's input line;
# fail ROW, a row that records one failure, in its partial record from its
# start; call ROW or refuse ROW, a row in whose window the judges read an
# authentication call or a refusal of an unshipped script, as harness.sh's
# smoke_judge_reading does, read by the closing reading alone when ROW is
# the one that waits; and shape SHAPE, a real producer shape for launcher: skip, a check
# not measured; partial, a row the attempt left open; outside, a failure
# outside every row; replay, a failure in a first attempt and a pass when a
# second replays it; unread, a row whose end reading is missing. The step
# `other` makes other read launcher's file as part of the lane's change.
# The lane's change stays uncommitted and
# --changed HEAD scopes both runs to it, so rows run, launcher among them,
# and fatal-controls after the smoke; a file no row maps selects the whole
# area. Each control is a copy with one binding removed: FILE^OLD^NEW.
reuse_fixture() { # DIR [FILE OLD NEW]
  local dir="$1"
  smoke_fixture "$dir"
  if [[ $# -eq 4 ]]; then plant "$dir/$2" "$3" "$4"; fi
  cat >"$dir/scripts/qml-smoke.sh" <<'SH'
#!/usr/bin/env bash
list="$(dirname -- "$0")/smoke/rows.list"
if [[ ${1-} == --list-rows ]]; then awk '!/^#/ && NF' "$list"; exit 0; fi
git_dir="$(git rev-parse --absolute-git-dir)"
knob() { cat -- "$git_dir/$1" 2>/dev/null || true; }
hang="$(knob hang)" shape="$(knob shape)"
if [[ -e $git_dir/edit ]]; then printf 'edited\n' >>shell/plugins/acme.launcher/Panel.qml; fi
rows=",${2-},"
driver="$(mktemp -d "${VGS_SMOKE_RESULTS_DIR:?}/qml-smoke-resume.XXXXXX")"
attempt() { # N
  a="$driver/$1" calls=0 refused=0
  mkdir -p "$a/results" "$a/partial"
  printf '0\0' >"$a/outside-failures"
}
close() { printf -- '- close %s %s intact\n' "$calls" "$refused" >>"$a/judge-readings"; }
attempt 1
if [[ $shape == replay ]]; then
  for row in $(awk '!/^#/ && NF' "$list"); do
    [[ $rows == ,, || $rows == *",$row,"* ]] || continue
    printf '%s start 0 0 intact\n' "$row" >>"$a/judge-readings"
    if [[ $row == launcher ]]; then printf '1\0'; else printf '0\0'; fi >"$a/results/$row"
    printf '%s end 0 0 intact\n' "$row" >>"$a/judge-readings"
    [[ $row != launcher ]] || break
  done
  close
  attempt 2
fi
for row in $(awk '!/^#/ && NF' "$list"); do
  [[ $rows == ,, || $rows == *",$row,"* ]] || continue
  printf '%s start %s %s intact\n' "$row" "$calls" "$refused" >>"$a/judge-readings"
  if [[ $row == "$(knob fail)" ]]; then printf '1\0'; else printf '0\0'; fi >"$a/partial/$row"
  if [[ $row == "$hang" ]]; then
    trap '[[ $row != "$(knob call)" ]] || calls=$((calls + 1)); close; kill "$waiting" 2>/dev/null; exit 143' TERM
    sleep 600 &
    waiting=$!
    printf '%s %s\n' "$$" "$waiting" >"$git_dir/hung"
    wait "$waiting"
  fi
  [[ $row != launcher || $shape != partial ]] || continue
  [[ $row != "$(knob call)" ]] || { calls=$((calls + 1)); status=1; }
  [[ $row != "$(knob refuse)" ]] || { refused=$((refused + 1)); status=1; }
  [[ $row == launcher && $shape == unread ]] ||
    printf '%s end %s %s intact\n' "$row" "$calls" "$refused" >>"$a/judge-readings"
  printf 'qml-smoke: row-secs row=%s secs=3 cpu_some_pct=0.1 load1=0.1\n' "$row" >>"$a/run.log"
  if [[ $row == "$(knob fail)" ]]; then printf '1\0'; status=1
  elif [[ $row == launcher && $shape == skip ]]; then printf '0\0launcher:planted-unavailable\0'
  else printf '0\0'; fi >"$a/results/$row"
  [[ $row != launcher || $shape != outside ]] || printf '1\0' >"$a/outside-failures"
done
close
exit "${status:-0}"
SH
  cat >"$dir/scripts/test-qml-smoke.sh" <<'SH'
#!/usr/bin/env bash
git_dir="$(git rev-parse --absolute-git-dir)"
if [[ "$(cat -- "$git_dir/hang" 2>/dev/null)" == fatal-controls ]]; then printf '%s\n' "$$" >"$git_dir/hung"; exec sleep 600; fi
if [[ -e $git_dir/skip-controls ]]; then exit 77; fi
SH
  commit "$dir" stand-ins
  printf 'lane\n' >>"$dir/shell/plugins/acme.launcher/Panel.qml"
  printf 'lane\n' >>"$dir/shell/plugins/acme.notify/Panel.qml"
}
# reuse_cut DIR SIGNAL HANG: run `validate qml --changed HEAD` in DIR until
# the stand-in HANG reports that it waits, then send SIGNAL to validate.
# A KILL leaves validate's rows going, so the stand-in then gets the TERM
# that ends it. Asserts the exit SIGNAL gives. HANG `-` lets the run end by
# itself. The run's log is DIR.cut.log.
reuse_cut() { # DIR SIGNAL HANG
  local dir="$1" signal="$2" git_dir pid tick status=0 want=143
  local -a hung
  git_dir="$("${base_env[@]}" git -C "$dir" rev-parse --absolute-git-dir)"
  printf '%s\n' "$3" >"$git_dir/hang"
  (cd -- "$dir" && exec "${base_env[@]}" bash scripts/validate qml --changed HEAD) >"$dir.cut.log" 2>&1 &
  pid=$!
  if [[ $3 == - ]]; then
    wait "$pid" || true
    rm -f -- "${git_dir:?}/hang" "${git_dir:?}/skip-controls"
    return 0
  fi
  # A bound on the wait for the reported state, not a reading.
  for ((tick = 0; tick < 600; tick++)); do
    if [[ -s $git_dir/hung ]] || ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if [[ ! -s $git_dir/hung ]]; then
    fail "$dir: the stand-in $3 never waited"; sed 's/^/        /' "$dir.cut.log"
    kill -KILL "$pid" 2>/dev/null || true; wait "$pid" || true; return 0
  fi
  kill -s "$signal" "$pid"
  # The redirection keeps bash's own report of a killed job off the log.
  { wait "$pid"; } 2>/dev/null || status=$?
  if [[ $signal == KILL ]]; then
    want=137
    read -r -a hung <"$git_dir/hung"
    kill -TERM "${hung[0]}" 2>/dev/null || true
    # A bound on the wait for the stand-in's end, not a reading.
    for ((tick = 0; tick < 600; tick++)); do
      kill -0 "${hung[0]}" 2>/dev/null || break
      sleep 0.1
    done
  fi
  rm -f -- "${git_dir:?}/hang" "${git_dir:?}/hung" "${git_dir:?}/edit" "${git_dir:?}/fail" "${git_dir:?}/call" "${git_dir:?}/refuse" "${git_dir:?}/shape"
  [[ $status == "$want" ]] || { fail "$dir: the cut run exited $status, not $want"; sed 's/^/        /' "$dir.cut.log"; }
}
smoke_both="scripts/qml-smoke.sh --rows $smoke_core,launcher,notifications,notifications-keys,$smoke_always,$smoke_tail"
smoke_other="scripts/qml-smoke.sh --rows $smoke_core,launcher,other,$smoke_always,$smoke_tail"
# Each control's mutant: the file it plants in, the text it replaces and its
# replacement, keyed by the case's mutant field.
declare -A reuse_mutant_file=() reuse_mutant_old=() reuse_mutant_new=()
reuse_mutant() { reuse_mutant_file[$1]="$2" reuse_mutant_old[$1]="$3" reuse_mutant_new[$1]="$4"; }
judged=scripts/smoke/row-inputs.sh
reuse_mutant direct scripts/validate '      lines+="${direct[$member]-}"' '      :'
reuse_mutant closure scripts/validate '      lines+="${direct[$member]-}"' '      [[ $member != "$row" ]] || lines+="${direct[$member]-}"'
reuse_mutant own-file scripts/validate 'for glob in "$file" "${smoke_globs[@]}"; do' 'for glob in "${smoke_globs[@]}"; do'
reuse_mutant common scripts/validate $'      harness) common+="${record_lines[j]}"$\'\\n\' ;;' '      harness) ;;'
reuse_mutant validate scripts/validate '    "$record_validate" "$record_point" "$record_untraced" "$1" "$2" "$3"' '    "" "$record_point" "$record_untraced" "$1" "$2" "$3"'
reuse_mutant untraced scripts/validate '    "$record_validate" "$record_point" "$record_untraced" "$1" "$2" "$3"' '    "$record_validate" "$record_point" "" "$1" "$2" "$3"'
reuse_mutant fault scripts/validate '  if [[ -n $smoke_read_fault ]]; then' '  if false; then'
reuse_mutant row-lines scripts/validate '  record_digest "row=${rows[$1]}" "$context" "$lines"' '  record_digest "row=${rows[$1]}" "$context" ""'
reuse_mutant void scripts/validate '  if [[ $end == "$pass_tree" ]]; then return 0; fi' '  return 0'
reuse_mutant status scripts/validate 'case "$1" in 0) echo pass ;; 77) echo skip ;; *) echo fail ;; esac' 'case "$1" in 0|77) echo pass ;; *) echo fail ;; esac'
reuse_mutant growth "$judged" '      [[ $own == calls ]] || ((calls == ${previous% *})) || return 1' '      :'
reuse_mutant refused "$judged" '      [[ $own == refused ]] || ((refused == ${previous#* })) || return 1' '      :'
reuse_mutant pair "$judged" '      [[ $own == refused ]] || ((refused == ${previous#* })) || return 1' '      [[ -n $own ]] || ((refused == ${previous#* })) || return 1'
reuse_mutant own "$judged" '      [[ $own == calls ]] || ((calls == ${previous% *})) || return 1' '      ((calls == ${previous% *})) || return 1'
reuse_mutant judge "$judged" '    smoke_record_verdict "$record" && [[ $smoke_verdict == pass ]] || return 1' '    :'
reuse_mutant partial "$judged" '    [[ -e $record ]] || record="$attempt/partial/$judge"' '    :'
reuse_mutant unread-close "$judged" '    [[ $closed == false && $calls =~' '    [[ $edge != close ]] || { closed=true; continue; }; [[ $closed == false && $calls =~'
reuse_mutant whole scripts/validate '  if [[ $reuse == on && ${row_traced[i]} == true && $command != scripts/qml-smoke.sh ]]; then' '  if [[ $reuse == on && ${row_traced[i]} == true ]]; then'
reuse_mutant skip "$judged" '  elif ((smoke_record_width > 1)); then smoke_verdict=skip' '  elif false; then smoke_verdict=skip'
reuse_mutant open "$judged" '( -n ${ended[$row]-} && -z ${unproved[$row]-} )' '( -z ${unproved[$row]-} )'
reuse_mutant outside "$judged" '  [[ ${fields[0]-} == 0 ]] || return 1' '  :'
reuse_mutant rank "$judged" '((smoke_record_failures > worst_count[$row] ||' '((smoke_record_failures < worst_count[$row] ||'
reuse_mutant reading "$judged" '[[ $judged == true && -n ${smoke_attempt_ended[$row]-} ]] || unproved' '[[ $judged == true ]] || unproved'
# name|signal|stand-in that waits|before the cut|after the cut|mutant|wanted lines, ^ between them
reuse_cases=(
  "a run cut off at its bound keeps the smoke rows it finished|TERM|notifications||||validate: reused secs=3 smoke=launcher^validate: rerun secs=unknown smoke=notifications^validate: rerun secs=3 reason=core smoke=bar^validate: rerun secs=unknown reason=untraced smoke=bare^$smoke_notify"
  "a killed run's finished smoke rows reach the next run|KILL|notifications||||validate: reused secs=3 smoke=launcher^$smoke_notify"
  "a call made during the cut row, read by the closing reading alone, leaves passes unproved|TERM|notifications|call-cut|||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: the last row reading is final|TERM|notifications|call-cut||unread-close|validate: reused secs=3 smoke=launcher"
  "a refusal in auth-sentinel's window, whose controls plant calls, leaves passes unproved|TERM|fatal-controls|refuse-auth|||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: a judge's window excuses either field|TERM|fatal-controls|refuse-auth||pair|validate: reused secs=3 smoke=launcher"
  "a call in auth-sentinel's window, its controls' own, leaves passes proved|TERM|fatal-controls|call-auth|||validate: reused secs=3 smoke=launcher"
  "control: a judge's window excuses nothing|TERM|fatal-controls|call-auth||own|validate: rerun secs=3 smoke=launcher"
  "a judge row cut off after a failure leaves its attempt's passes unproved|TERM|auth-sentinel|auth-fail|||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: a judge row cut off after a failure no longer withholds passes|TERM|auth-sentinel|auth-fail||partial|validate: reused secs=3 smoke=launcher"
  "a finished smoke row whose input changed after the cut runs again|TERM|notifications||edit||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: a smoke row's changed input no longer reruns it|TERM|notifications||edit|direct|validate: reused secs=3 smoke=launcher^$smoke_notify"
  "a row's own file changed after the cut reruns it|TERM|notifications||row-file||validate: rerun secs=3 smoke=launcher"
  "control: a row's own file no longer reruns it|TERM|notifications||row-file|own-file|validate: reused secs=3 smoke=launcher"
  "a file the harness line names changed after the cut reruns every row|TERM|notifications||harness-file||validate: rerun secs=3 smoke=launcher^scripts/qml-smoke.sh"
  "control: a harness input no longer reruns every row|TERM|notifications||harness-file|common|validate: reused secs=3 smoke=launcher"
  "scripts/validate changed after the cut reuses nothing|TERM|notifications||validate-file||validate: rerun secs=3 smoke=launcher"
  "control: a changed scripts/validate no longer stops reuse|TERM|notifications||validate-file|validate|validate: reused secs=3 smoke=launcher"
  "a lane that removes the harness line records and reuses no smoke row|TERM|notifications|harness-line|||validate: smoke-reuse=off reason=harness-line-unreadable^!validate: reused secs=3 smoke=launcher"
  "control: a lane that removes the harness line reuses its smoke rows|TERM|notifications|harness-line||fault|validate: reused secs=3 smoke=launcher"
  "a producer's input changed after its reader passed reruns the reader|TERM|fatal-controls|other|edit||validate: rerun secs=3 smoke=other^$smoke_other"
  "control: a reader no longer reruns when its producer's input changed|TERM|fatal-controls|other|edit|closure|validate: reused secs=3 smoke=other"
  "an unknown input added after the cut reuses nothing|TERM|notifications||unknown||validate: selection=full unknown-input=new-source.bin^validate: rerun secs=3 smoke=launcher^scripts/qml-smoke.sh"
  "control: an unknown input added after the cut no longer stops reuse|TERM|notifications||unknown|untraced|validate: reused secs=3 smoke=launcher"
  "a sentinel call in a run cut off before auth-sentinel reruns the calling row|TERM|notifications|call|||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: a sentinel call no longer reruns the calling row|TERM|notifications|call||growth|validate: reused secs=3 smoke=launcher"
  "an unshipped refusal the judge would fail reruns the refusing row unchanged|TERM|fatal-controls|refuse|||validate: rerun secs=3 smoke=launcher^$smoke_both"
  "control: an unshipped refusal no longer reruns the refusing row|TERM|fatal-controls|refuse||refused|validate: reused secs=3 smoke=launcher"
  "a failed judge row leaves its attempt's smoke passes unproved|TERM|fatal-controls|auth-fail|||validate: rerun secs=3 smoke=notifications^$smoke_both"
  "control: a failed judge row no longer leaves its attempt's passes unproved|TERM|fatal-controls|auth-fail||judge|validate: reused secs=3 smoke=notifications^$smoke_none"
  "a check not measured is no pass|TERM|notifications|skip|||validate: rerun secs=3 smoke=launcher"
  "control: a check not measured reads as a pass|TERM|notifications|skip||skip|validate: reused secs=3 smoke=launcher"
  "a row its attempt left open is no pass|TERM|notifications|partial|||validate: rerun secs=unknown smoke=launcher"
  "control: a row its attempt left open reads as a pass|TERM|notifications|partial||open|validate: reused secs=unknown smoke=launcher"
  "a failure outside every row leaves its attempt's passes unproved|TERM|notifications|outside|||validate: rerun secs=3 smoke=launcher"
  "control: a failure outside every row no longer leaves passes unproved|TERM|notifications|outside||outside|validate: reused secs=3 smoke=launcher"
  "a failure a replay passed stands over the replay|TERM|notifications|replay|||validate: rerun secs=3 smoke=launcher"
  "control: a replay's pass stands over its failure|TERM|notifications|replay||rank|validate: reused secs=3 smoke=launcher"
  "a row with no end reading is no pass|TERM|notifications|unread|||validate: rerun secs=3 smoke=launcher"
  "control: a row with no end reading reads as a pass|TERM|notifications|unread||reading|validate: reused secs=3 smoke=launcher"
  "a row that exited 77 is no pass|-|-|skip-controls|||scripts/test-qml-smoke.sh"
  "control: a row that exited 77 reads as a pass|-|-|skip-controls||status|!scripts/test-qml-smoke.sh"
  "a run cut off after the nested smoke reuses its smoke rows and runs the core rows again|TERM|fatal-controls||||validate: reused secs=3 smoke=launcher^validate: reused secs=3 smoke=notifications^%validate: rerun secs=[0-9]+ reason=smoke-rows row=nested smoke$^$smoke_none^scripts/test-qml-smoke.sh"
  "control: the nested smoke a cut run passed is reused whole|TERM|fatal-controls|||whole|~validate: reuse=on rows-reused=1 ^!scripts/qml-smoke.sh"
  "a changed input reruns the smoke row it reaches|TERM|fatal-controls||edit||validate: reused secs=3 smoke=notifications^$smoke_launcher"
  "a changed input reruns a table row a finished run passed|-|-||edit||%validate: rerun secs=[0-9]+ row=smoke fatal row controls$^scripts/test-qml-smoke.sh"
  "control: a changed input no longer reruns a table row|-|-||edit|row-lines|%validate: reused secs=[0-9]+ row=smoke fatal row controls$^!scripts/test-qml-smoke.sh"
  "a run whose tree changed while it ran leaves nothing to reuse|TERM|fatal-controls|revert|revert||validate: rerun secs=unknown smoke=launcher^validate: rerun secs=unknown smoke=notifications^$smoke_both"
  "control: a run whose tree changed while it ran no longer withdraws its records|TERM|fatal-controls|revert|revert|void|validate: reused secs=3 smoke=launcher^$smoke_none"
)
reuse_case() { # SPEC
  local name signal hang before after mutant wanted d git_dir panel
  local -a lines
  IFS='|' read -r name signal hang before after mutant wanted <<<"$1"
  d="$tmp/reuse-${name//[^a-z]/-}"
  if [[ -n $mutant ]]; then
    reuse_fixture "$d" "${reuse_mutant_file[$mutant]}" "${reuse_mutant_old[$mutant]}" "${reuse_mutant_new[$mutant]}"
  else
    reuse_fixture "$d"
  fi
  git_dir="$("${base_env[@]}" git -C "$d" rev-parse --absolute-git-dir)"
  panel="$(cat -- "$d/shell/plugins/acme.launcher/Panel.qml")"
  case "$before" in
    revert) : >"$git_dir/edit" ;;
    auth-fail) printf 'auth-sentinel\n' >"$git_dir/fail" ;;
    call|refuse) printf 'launcher\n' >"$git_dir/$before" ;;
    call-cut) printf 'notifications\n' >"$git_dir/call" ;;
    call-auth|refuse-auth) printf 'auth-sentinel\n' >"$git_dir/${before%-auth}" ;;
    skip|partial|outside|replay|unread) printf '%s\n' "$before" >"$git_dir/shape" ;;
    skip-controls) : >"$git_dir/skip-controls" ;;
    harness-line) plant "$d/scripts/smoke/harness.sh" $'# inputs: scripts/smoke/verdict.sh scripts/smoke/helper/* scripts/smoke/gone.sh\n' '' ;;
    other) plant "$d/scripts/smoke/rows/other.sh" '# inputs: shell/plugins/acme.other/*' '# inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh' ;;
  esac
  reuse_cut "$d" "$signal" "$hang"
  case "$after" in
    edit) printf 'fix\n' >>"$d/shell/plugins/acme.launcher/Panel.qml" ;;
    row-file) printf '# changed\n' >>"$d/scripts/smoke/rows/launcher.sh" ;;
    harness-file) printf 'changed\n' >>"$d/scripts/smoke/helper/click.c" ;;
    validate-file) printf '# changed\n' >>"$d/scripts/validate" ;;
    unknown) printf 'source\n' >"$d/new-source.bin" ;;
    revert)
      grep -q '^validate: row-records=void reason=content-changed ' "$d.cut.log" ||
        [[ -n $mutant ]] || fail "$name: the cut run withdrew nothing"
      printf '%s\n' "$panel" >"$d/shell/plugins/acme.launcher/Panel.qml" ;;
  esac
  IFS='^' read -r -a lines <<<"$wanted"
  test_area=qml test_args=(--changed HEAD --list)
  row_re "$name" "$d" 0 "" "${lines[@]}"
}
parallel_cases reuse_case reuse "${reuse_cases[@]}"
test_area=qml test_args=()

# The nested smoke row records no pass of its own: its inputs bind neither
# the change base its row selection reads nor a smoke row's input another
# table row owns. In `base` the lane's notifications change is committed,
# so a pass under `--changed HEAD` ran launcher alone, and a run on the
# same tree against HEAD~1 reaches notifications too. In `owned` other's
# line names scripts/fixtures/vpn/acme.json, which the VPN decisions row
# owns, and the lane edits that file after a passing run. The control is
# a copy of validate that reuses the nested smoke row whole.
# name|setup|mutant|wanted lines, ^ between them
smoke_bind_cases=(
  "a pass under one base reruns the smoke rows another base reaches on the same tree|base||validate: reused secs=3 smoke=launcher^validate: rerun secs=unknown smoke=notifications^$smoke_notify"
  "control: a pass under one base covers the smoke another base reaches|base|whole|!scripts/qml-smoke.sh"
  "a changed input only a smoke row's line names reruns that smoke row|owned||validate: rerun secs=3 smoke=other^scripts/qml-smoke.sh --rows $smoke_core,other,$smoke_always,$smoke_tail"
  "control: a changed input only a smoke row's line names reruns nothing|owned|whole|!scripts/qml-smoke.sh"
)
smoke_bind_case() { # SPEC
  local name setup mutant wanted d second=HEAD
  local -a lines
  IFS='|' read -r name setup mutant wanted <<<"$1"
  d="$tmp/smoke-bind-${name//[^a-z]/-}"
  if [[ -n $mutant ]]; then
    reuse_fixture "$d" "${reuse_mutant_file[$mutant]}" "${reuse_mutant_old[$mutant]}" "${reuse_mutant_new[$mutant]}"
  else
    reuse_fixture "$d"
  fi
  case "$setup" in
    base)
      "${base_env[@]}" git -C "$d" add -- shell/plugins/acme.notify/Panel.qml
      "${base_env[@]}" git -C "$d" commit -q -m notify
      second=HEAD~1 ;;
    owned)
      mkdir -p "$d/scripts/fixtures/vpn"
      printf '{}\n' >"$d/scripts/fixtures/vpn/acme.json"
      plant "$d/scripts/smoke/rows/other.sh" '# inputs: shell/plugins/acme.other/*' '# inputs: shell/plugins/acme.other/* scripts/fixtures/vpn/acme.json'
      commit "$d" owned
      printf 'lane\n' >>"$d/shell/plugins/acme.other/Panel.qml" ;;
  esac
  (cd -- "$d" && exec "${base_env[@]}" bash scripts/validate qml --changed HEAD) >"$d.first.log" 2>&1 || true
  [[ $setup != owned ]] || printf '{"lane": true}\n' >"$d/scripts/fixtures/vpn/acme.json"
  IFS='^' read -r -a lines <<<"$wanted"
  test_area=qml test_args=(--changed "$second" --list)
  row_re "$name" "$d" 0 "" "${lines[@]}"
}
parallel_cases smoke_bind_case smoke-bind "${smoke_bind_cases[@]}"
test_area=qml test_args=()

# The records of rows a run cannot bind or that read the change base. A
# fixture whose lane changes FILE runs `validate AREA --changed HEAD` to
# its end, then, after `moved`, an empty commit that changes the base and
# nothing it holds, lists the next run. A repo row and a row with a
# `device:` input record but are never reused; a row whose `%scope` says
# it reads the base reruns on a new one, and a row that reads none is
# reused. The unit stand-ins pass. Each control is a copy of validate with
# one binding removed, keyed in the record_mutant_* tables.
declare -A record_mutant_old=(
  [repo]='  [[ $row_area != repo ]] || continue'
  [device]='      \$*|device:*) row_traced[i]=false ;;'
  [every-base]='  if [[ ${row_scoped[$1]} == true ]]; then'
  [scope]='      %scope) row_scoped[i]=true ;;'
)
declare -A record_mutant_new=(
  [repo]='  :'
  [device]='      \$*|device:*) ;;'
  [every-base]='  if true; then'
  [scope]='      %scope) ;;'
)
# name|area|lane's file|after the run|mutant|wanted lines, ^ between them
record_cases=(
  "a repo row records but is never reused|repo|clean.txt|||%validate: rerun secs=[0-9]+ reason=untraced row=whitespace errors against the base$"
  "control: a repo row is reused|repo|clean.txt||repo|%validate: reused secs=[0-9]+ row=whitespace errors against the base$"
  "a device row records but is never reused|tools|scripts/test-smoke-sink.sh|||%validate: rerun secs=[0-9]+ reason=untraced row=smoke sink compositor controls$"
  "control: a device row is reused|tools|scripts/test-smoke-sink.sh||device|%validate: reused secs=[0-9]+ row=smoke sink compositor controls$"
  "a new base reruns a row that reads it and reuses one that does not|unit|scripts/qml-unit.sh|moved||%validate: reused secs=[0-9]+ row=qml unit tests$^%validate: rerun secs=[0-9]+ row=qml unit controls$"
  "control: a new base reruns a row that reads none|unit|scripts/qml-unit.sh|moved|every-base|%validate: rerun secs=[0-9]+ row=qml unit tests$"
  "control: a new base no longer reruns a row that reads it|unit|scripts/qml-unit.sh|moved|scope|%validate: reused secs=[0-9]+ row=qml unit controls$"
)
record_case() { # SPEC
  local name area file after mutant wanted d
  local -a lines
  IFS='|' read -r name area file after mutant wanted <<<"$1"
  d="$tmp/record-${name//[^a-z]/-}"
  fresh "$d"
  [[ -z $mutant ]] || plant "$d/scripts/validate" "${record_mutant_old[$mutant]}" "${record_mutant_new[$mutant]}"
  for stand_in in scripts/qml-unit.sh scripts/test-qml-unit.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$d/$stand_in"
    chmod +x "$d/$stand_in"
  done
  commit "$d" stand-ins
  if [[ -e $d/$file ]]; then printf '# lane\n' >>"$d/$file"; else printf '#!/usr/bin/env bash\nexit 0\n' >"$d/$file"; chmod +x "$d/$file"; fi
  (cd -- "$d" && exec "${base_env[@]}" bash scripts/validate "$area" --changed HEAD) >"$d.first.log" 2>&1 || true
  [[ $after != moved ]] || "${base_env[@]}" git -C "$d" commit -q --allow-empty -m moved
  IFS='^' read -r -a lines <<<"$wanted"
  test_area=$area test_args=(--changed HEAD --list)
  row_re "$name" "$d" 0 "" "${lines[@]}" || true
}
parallel_cases record_case record "${record_cases[@]}"
test_area=qml test_args=()

# A repository whose last repo pass is the commit `passed`, which a real
# run records; validate is the copy under test, with OLD replaced by NEW
# when given. Sets passed_commit and passed_tree.
passed_fixture() { # DIR [OLD NEW]
  local dir="$1" out
  fresh "$dir"
  if [[ $# -eq 3 ]]; then plant "$dir/scripts/validate" "$2" "$3"; fi
  printf 'passed\n' >"$dir/passed.txt"
  commit "$dir" passed
  passed_commit="$("${base_env[@]}" git -C "$dir" rev-parse HEAD)"
  passed_tree="$("${base_env[@]}" git -C "$dir" rev-parse 'HEAD^{tree}')"
  if ! out="$(cd -- "$dir" && "${base_env[@]}" bash scripts/validate repo 2>&1)" ||
     ! grep -qxF "validate: last-pass=recorded area=repo tree=$passed_tree" <<<"$out"; then
    fail "passed fixture $dir: the first run did not record its pass"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
}
test_area=repo

# A rebase that changes every tree since the branch point: no commit holds
# the recorded tree, and the branch point serves again. The rebased commit
# keeps the fixture's copy of validate.
rebase_head() { # DIR
  cp -- "$1/scripts/validate" "$tmp/rebase-validate"
  "${base_env[@]}" git -C "$1" reset -q --hard trunk
  cp -- "$tmp/rebase-validate" "$1/scripts/validate"
  printf 'rebased\n' >"$1/rebased.txt"
  commit "$1" rebased
}
d="$tmp/base-rebase"; passed_fixture "$d"; rebase_head "$d"
row "a rebase that drops the last pass falls back to the merge base" "$d" 0 "" \
  "validate: last-pass=ignored reason=no-commit-holds-tree tree=$passed_tree" "validate: base=$trunk source=merge-base"
d="$tmp/base-rebase-control"; passed_fixture "$d" '    [[ $tree == "$recorded" ]] && break' '    recorded="$tree"; break'; rebase_head "$d"
row "control: a commit that does not hold the recorded tree is still the base" "$d" 0 "" \
  "validate: base=$("${base_env[@]}" git -C "$d" rev-parse HEAD) source=last-pass"

# A selector change after the pass: docs/selector.dat changes before the
# logic pass, which selects no row for it, and a later commit maps it to the
# plugin status judge row. The run reads the whole branch again and runs
# that row. The control drops the selector check and takes the pass as its
# base, which skips the row.
for variant in real control; do
  d="$tmp/base-selector-$variant"; fresh "$d"
  [[ $variant == real ]] || plant "$d/scripts/validate" '  git diff --quiet "$commit" -- scripts/validate || status=$?' '  status=0'
  mkdir -p "$d/docs"; printf 'selector\n' >"$d/docs/selector.dat"
  commit "$d" path
  test_area=logic test_args=()
  row_re "the $variant selector fixture's logic pass records its tree" "$d" 0 "" \
    "~validate: selected=0 area=logic" "validate: last-pass=recorded area=logic tree=$("${base_env[@]}" git -C "$d" rev-parse 'HEAD^{tree}')"
  plant "$d/scripts/validate" '"logic|plugin status judge|node scripts/test-plugin-status.js|' '"logic|plugin status judge|node scripts/test-plugin-status.js|docs/selector.dat '
  commit "$d" selector
done
test_args=(--list)
row "a selector change after the pass reads the whole branch again" "$tmp/base-selector-real" 0 "" \
  "validate: last-pass=ignored reason=selector-changed commit=$("${base_env[@]}" git -C "$tmp/base-selector-real" rev-parse HEAD~1)" \
  "validate: base=$trunk source=merge-base" "node scripts/test-plugin-status.js"
row "control: a selector change after the pass no longer reads the whole branch" "$tmp/base-selector-control" 0 "" \
  "validate: base=$("${base_env[@]}" git -C "$tmp/base-selector-control" rev-parse HEAD~1) source=last-pass" "!node scripts/test-plugin-status.js"
test_area=repo

# Precedence: a base the caller names outranks the last pass. Each control
# drops one rule, and the last pass takes the base.
# source~arguments~environment~text the control replaces~its replacement
precedence_cases=(
  'argument~--changed HEAD~~~'
  $'argument~--changed HEAD~~if [[ -n $change_base ]]; then\n  base_source=argument~if false; then\n  base_source=argument'
  'DEV_VALIDATE_BASE~~DEV_VALIDATE_BASE=HEAD~~'
  'DEV_VALIDATE_BASE~~DEV_VALIDATE_BASE=HEAD~elif [[ -n ${DEV_VALIDATE_BASE:-} ]]; then~elif false; then'
  'VGS_VALIDATE_BASE~~VGS_VALIDATE_BASE=HEAD~~'
  'VGS_VALIDATE_BASE~~VGS_VALIDATE_BASE=HEAD~elif [[ -z ${VGS_VALIDATE_BASE:-} ]] && change_base=~elif change_base='
)
for spec in "${precedence_cases[@]}"; do
  IFS='~' read -r -d '' source arguments environment old new <<<"$spec" || true
  new="${new%$'\n'}"
  d="$tmp/base-precedence-$source${old:+-control}"
  if [[ -n $old ]]; then passed_fixture "$d" "$old" "$new"; else passed_fixture "$d"; fi
  printf 'next\n' >"$d/next.txt"; commit "$d" next
  head_commit="$("${base_env[@]}" git -C "$d" rev-parse HEAD)"
  read -r -a test_args <<<"$arguments --list"
  if [[ -z $old ]]; then
    row "$source outranks the last pass" "$d" 0 "$environment" "validate: base=$head_commit source=$source"
  else
    row "control: $source no longer outranks the last pass" "$d" 0 "$environment" "validate: base=$passed_commit source=last-pass"
  fi
done

# --changed outranks DEV_VALIDATE_BASE too. The control checks the Kendex
# base first.
for variant in real control; do
  d="$tmp/base-precedence-argument-dev-$variant"
  if [[ $variant == real ]]; then passed_fixture "$d"; else
    passed_fixture "$d" $'if [[ -n $change_base ]]; then\n  base_source=argument\nelif [[ $full_scope == true ]]; then\n  base_source=full\nelif [[ -n ${DEV_VALIDATE_BASE:-} ]]; then\n  change_base="$DEV_VALIDATE_BASE"; base_source=DEV_VALIDATE_BASE' \
      $'if [[ -n ${DEV_VALIDATE_BASE:-} ]]; then\n  change_base="$DEV_VALIDATE_BASE"; base_source=DEV_VALIDATE_BASE\nelif [[ -n $change_base ]]; then\n  base_source=argument\nelif [[ $full_scope == true ]]; then\n  base_source=full'
  fi
  printf 'next\n' >"$d/next.txt"; commit "$d" next
done
test_args=(--changed HEAD --list)
row "argument outranks DEV_VALIDATE_BASE" "$tmp/base-precedence-argument-dev-real" 0 "DEV_VALIDATE_BASE=HEAD~1" \
  "validate: base=$("${base_env[@]}" git -C "$tmp/base-precedence-argument-dev-real" rev-parse HEAD) source=argument"
row "control: argument no longer outranks DEV_VALIDATE_BASE" "$tmp/base-precedence-argument-dev-control" 0 "DEV_VALIDATE_BASE=HEAD~1" \
  "validate: base=$("${base_env[@]}" git -C "$tmp/base-precedence-argument-dev-control" rev-parse HEAD~1) source=DEV_VALIDATE_BASE"

# Recording: only a run that passes, on a base that proves the branch,
# records its tree; each control drops one condition and wants the record.
# name~setup~wanted exit~arguments~environment~wanted line, @ for HEAD's tree~text the control replaces~its replacement
record_cases=(
  'a named base keeps the pass unrecorded~named~0~--changed HEAD~~validate: last-pass=unrecorded reason=named-base source=argument~~'
  'control: a named base no longer keeps the pass unrecorded~named~0~--changed HEAD~~validate: last-pass=recorded area=repo tree=@~    merge-base|last-pass|full) ;;~    merge-base|last-pass|full|argument) ;;'
  'a Kendex base keeps the pass unrecorded~kendex~0~~DEV_VALIDATE_BASE=HEAD~validate: last-pass=unrecorded reason=named-base source=DEV_VALIDATE_BASE~~'
  'control: a Kendex base no longer keeps the pass unrecorded~kendex~0~~DEV_VALIDATE_BASE=HEAD~validate: last-pass=recorded area=repo tree=@~    merge-base|last-pass|full) ;;~    merge-base|last-pass|full|DEV_VALIDATE_BASE) ;;'
  'a failing run records nothing~failing~1~~~!validate: last-pass=~~'
  'control: a failing run records its tree~failing~1~~~validate: last-pass=recorded area=repo tree=@~if [[ ${#failed[@]} -gt 0 ]]; then~last_pass_record; if [[ ${#failed[@]} -gt 0 ]]; then'
)
for spec in "${record_cases[@]}"; do
  IFS='~' read -r name setup want_exit arguments environment wanted old new <<<"$spec"
  d="$tmp/base-record-$setup${old:+-control}"; fresh "$d"
  if [[ -n $old ]]; then plant "$d/scripts/validate" "$old" "$new"; fi
  case "$setup" in
    named|kendex) printf 'clean\n' >"$d/next.txt" ;;
    failing) printf 'defect \n' >"$d/next.txt" ;;
  esac
  commit "$d" next
  read -r -a test_args <<<"$arguments"
  row "$name" "$d" "$want_exit" "$environment" "${wanted//@/$("${base_env[@]}" git -C "$d" rev-parse 'HEAD^{tree}')}"
done
test_area=offline
test_args=()
# The real runner, under the test environment so a regressed refusal stops
# at the harness's missing-session check: it lists the core rows, each with
# its row file; --list-rows with --rows lists the rows that run would hold,
# in run order: the named rows, the core rows and the rows an input line
# of one of those names; and it refuses a row it does not hold. The
# controls are copies: one whose row predicate holds every row, one that
# follows no input line, one that adds no core row.
smoke_core_rows=(bar hyprland-consent session start-order auth-sentinel)
if listed="$("${base_env[@]}" "$repo/scripts/qml-smoke.sh" --list-rows)" && [[ $(wc -l <<<"$listed") -ge 60 ]]; then
  for smoke_row_name in "${smoke_core_rows[@]}"; do
    if grep -qxF "$smoke_row_name" <<<"$listed"; then ok "the runner lists the core row $smoke_row_name"; else fail "the runner does not list the core row $smoke_row_name"; fi
  done
  while IFS= read -r smoke_row_name; do
    [[ -f $repo/scripts/smoke/rows/$smoke_row_name.sh ]] || fail "the runner lists $smoke_row_name, which has no row file"
  done <<<"$listed"
else
  fail "qml-smoke.sh --list-rows: the read listed under 60 rows, so the row list no longer reads as one name a line"
fi
# session and start-order read capabilities, which reads plugins, and
# start-order reads device-fakes.
smoke_subset=$'bar\nhyprland-consent\nplugins\ncapabilities\nsession\ndevice-fakes\nstart-order\nauth-sentinel'
for smoke_named in plugins,bar capabilities; do
  if out="$("${base_env[@]}" "$repo/scripts/qml-smoke.sh" --rows "$smoke_named" --list-rows)" && [[ $out == "$smoke_subset" ]]; then
    ok "the runner lists the rows --rows $smoke_named names, the core rows and the rows those read, in run order"
  else
    fail "the runner's --rows $smoke_named listing: $out"
  fi
done
for dir in runner-control runner-reads-control runner-core-control; do
  mkdir -p "$tmp/$dir/scripts/smoke/rows"
  cp -- "$repo/scripts/smoke/rows.list" "$repo/scripts/smoke/row-inputs.sh" "$tmp/$dir/scripts/smoke/"
  for smoke_row_name in $smoke_subset; do
    cp -- "$repo/scripts/smoke/rows/$smoke_row_name.sh" "$tmp/$dir/scripts/smoke/rows/"
  done
done
cp -- "$repo/scripts/qml-smoke.sh" "$tmp/runner-reads-control/scripts/qml-smoke.sh"
plant "$tmp/runner-reads-control/scripts/qml-smoke.sh" '        qml_smoke_queue+=("$qml_smoke_read")' '        :'
if out="$("${base_env[@]}" bash "$tmp/runner-reads-control/scripts/qml-smoke.sh" --rows capabilities --list-rows)" && [[ $out == $'bar\nhyprland-consent\ncapabilities\nsession\nstart-order\nauth-sentinel' ]]; then
  ok "control: a runner that follows no input line lists the named row and the core rows alone"
else
  fail "control: the runner that follows no input line listed: $out"
fi
cp -- "$repo/scripts/qml-smoke.sh" "$tmp/runner-core-control/scripts/qml-smoke.sh"
plant "$tmp/runner-core-control/scripts/qml-smoke.sh" '  qml_smoke_queue=("${qml_smoke_named[@]}" "${smoke_core[@]}")' '  qml_smoke_queue=("${qml_smoke_named[@]}")'
if out="$("${base_env[@]}" bash "$tmp/runner-core-control/scripts/qml-smoke.sh" --rows capabilities --list-rows)" && [[ $out == $'plugins\ncapabilities' ]]; then
  ok "control: a runner that adds no core row lists the named row and the row it reads alone"
else
  fail "control: the runner that adds no core row listed: $out"
fi
python3 - "$repo/scripts/qml-smoke.sh" "$tmp/runner-control/scripts/qml-smoke.sh" <<'PY'
from pathlib import Path
import sys
source, target = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
old = 'qml_smoke_wanted() { [[ -z $qml_smoke_only || $qml_smoke_only == *",$1,"* ]]; }'
assert source.count(old) == 1, old
target.write_text(source.replace(old, 'qml_smoke_wanted() { true; }'))
PY
if out="$("${base_env[@]}" bash "$tmp/runner-control/scripts/qml-smoke.sh" --rows plugins,bar --list-rows)" && [[ $out == "$listed" && $out != "$smoke_subset" ]]; then
  ok "control: a runner whose predicate holds every row lists every row"
else
  fail "control: the runner predicate copy listed: $(wc -l <<<"$out") rows"
fi
# The runner reads its rows from scripts/smoke/rows.list and refuses a line
# that is no comment, blank or row name; the control is a copy without that
# refusal, which lists the line as a row.
mkdir -p "$tmp/runner-list/scripts/smoke" "$tmp/runner-list-control/scripts/smoke"
cp -- "$repo/scripts/qml-smoke.sh" "$tmp/runner-list/scripts/qml-smoke.sh"
printf '# Rows.
bar

Bad Row
' | tee "$tmp/runner-list/scripts/smoke/rows.list" >"$tmp/runner-list-control/scripts/smoke/rows.list"
cp -- "$repo/scripts/qml-smoke.sh" "$tmp/runner-list-control/scripts/qml-smoke.sh"
plant "$tmp/runner-list-control/scripts/qml-smoke.sh" '  if [[ ! $qml_smoke_row =~ ^[a-z0-9-]+$ ]]; then' '  if false; then'
status=0
out="$("${base_env[@]}" bash "$tmp/runner-list/scripts/qml-smoke.sh" --list-rows 2>&1)" || status=$?
if [[ $status == 2 && ${out%%$'\n'*} == "qml-smoke: refused: rows-list=malformed line=4 path=$tmp/runner-list/scripts/smoke/rows.list" ]]; then
  ok "the runner refuses a row list line that is no row name"
else
  fail "the runner's row list refusal: exit=$status output=$out"
fi
status=0
out="$("${base_env[@]}" bash "$tmp/runner-list-control/scripts/qml-smoke.sh" --list-rows 2>&1)" || status=$?
if [[ $status == 0 && $out == $'bar\nBad Row' ]]; then
  ok "control: a runner without the refusal lists the line as a row"
else
  fail "control: the runner without its row list refusal: exit=$status output=$out"
fi
# An empty row list, or one that cannot be read, is refused: a run of no
# row would pass while it checks nothing. The empty control is a copy
# without that refusal, which lists nothing and passes; the unreadable
# control reads past a failed read and names the empty list instead.
# name~row list text, or - for no list~wanted exit~wanted first line~text the copy replaces~its replacement
runner_list_cases=(
  'the runner refuses an empty row list~# Rows.~2~qml-smoke: refused: rows-list=empty path=@~~'
  'control: a runner without the empty refusal lists no row and passes~# Rows.~0~~if [[ ${#qml_smoke_rows[@]} -eq 0 ]]; then~if false; then'
  'the runner refuses a row list it cannot read~-~2~qml-smoke: refused: rows-list=unreadable path=@~~'
  'control: a runner that reads past a failed read names another cause~-~2~qml-smoke: refused: rows-list=empty path=@~if ! mapfile -t qml_smoke_lines <"$qml_smoke_list_file"; then~mapfile -t qml_smoke_lines <"$qml_smoke_list_file" || :; if false; then'
)
for spec in "${runner_list_cases[@]}"; do
  IFS='~' read -r name text want_exit wanted old new <<<"$spec"
  dir="$tmp/runner-list-${#text}-${old:+control}"
  mkdir -p "$dir/scripts/smoke"
  cp -- "$repo/scripts/qml-smoke.sh" "$dir/scripts/qml-smoke.sh"
  [[ -z $old ]] || plant "$dir/scripts/qml-smoke.sh" "$old" "$new"
  [[ $text == - ]] || printf '%s\n' "$text" >"$dir/scripts/smoke/rows.list"
  status=0
  out="$("${base_env[@]}" bash "$dir/scripts/qml-smoke.sh" --list-rows 2>"$dir/err")" || status=$?
  first="$(grep -m1 '^qml-smoke:' -- "$dir/err" || true)"
  wanted="${wanted//@/$dir/scripts/smoke/rows.list}"
  if [[ $status == "$want_exit" && $first == "$wanted" && ( $status != 0 || -z $out ) ]]; then ok "$name"; else fail "$name: exit=$status first=$first output=$out"; fi
done
status=0
out="$("${base_env[@]}" "$repo/scripts/qml-smoke.sh" --rows bar,no-such-row 2>&1)" || status=$?
if [[ $status == 2 && $out == 'qml-smoke: refused: argument=--rows value=no-such-row reason=unknown-row' ]]; then
  ok "the runner refuses a row it does not hold"
else
  fail "the runner's unknown row refusal: exit=$status output=$out"
fi
# The rows a run holds, in a scratch tree whose list holds the core rows:
# top names own's file, own names base's and part's, a row file the tree
# has and the list does not, which is own's own; the core row session names
# seat's; gone names a row file the tree lacks; and the short tree's list
# lacks a core row. The tree's fence passes and its harness stands in,
# printing each row it is handed and answering the step the runner takes
# after hyprland-consent, so no run here starts a compositor or a shell. The run prints the named and the expanded set once, which a lane
# reads to see what its retry ran, and runs the rows in list order: the
# rows top's chain reaches two reads deep and the row a core row reads. A
# refused run stops before the fence, which would log its call. The
# controls are copies: one that follows the named rows' lines alone, which
# loses base and seat, and one for each refusal, which lists the rows.
for dir in runner-reads runner-deep-control runner-refusal-control runner-short runner-short-control runner-filter runner-filter-control; do
  mkdir -p "$tmp/$dir/scripts/smoke/rows"
  cp -- "$repo/scripts/qml-smoke.sh" "$tmp/$dir/scripts/qml-smoke.sh"
  # These fixtures exercise row selection inside one attempt. The fatal
  # controls in test-qml-smoke.sh exercise the real world/resume driver.
  plant "$tmp/$dir/scripts/qml-smoke.sh" 'if [[ -z ${qml_smoke_attempt:-} ]]; then' 'if false; then'
  plant "$tmp/$dir/scripts/qml-smoke.sh" 'if [[ -n $first_bar_runs || -n ${qml_smoke_attempt:-} ]]; then' 'if true; then'
  cp -- "$repo/scripts/smoke/row-inputs.sh" "$tmp/$dir/scripts/smoke/row-inputs.sh"
  printf '%s\n' '# Rows.' bar hyprland-consent seat session base own top gone start-order auth-sentinel >"$tmp/$dir/scripts/smoke/rows.list"
  for smoke_row_name in bar hyprland-consent seat base start-order auth-sentinel; do
    printf '# inputs: shell/Core/Bar.qml\n' >"$tmp/$dir/scripts/smoke/rows/$smoke_row_name.sh"
  done
  printf '# inputs: scripts/smoke/rows/seat.sh\n' >"$tmp/$dir/scripts/smoke/rows/session.sh"
  printf '# inputs: scripts/smoke/rows/part.sh scripts/smoke/rows/base.sh\n' >"$tmp/$dir/scripts/smoke/rows/own.sh"
  printf '# inputs: scripts/smoke/rows/own.sh\n' >"$tmp/$dir/scripts/smoke/rows/top.sh"
  printf '# Run by own.sh.\n' >"$tmp/$dir/scripts/smoke/rows/part.sh"
  printf '# inputs: scripts/smoke/rows/left.sh\n' >"$tmp/$dir/scripts/smoke/rows/gone.sh"
  printf '#!/usr/bin/env bash\necho fence >>"%s"\n' "$tmp/$dir/fence.log" >"$tmp/$dir/scripts/smoke/gpu-fence.sh"
  chmod +x "$tmp/$dir/scripts/smoke/gpu-fence.sh"
  mkdir -p "$tmp/$dir/sandbox/evidence/failed" "$tmp/$dir/sandbox/results"
  printf 'sandbox=%q\nqml_smoke_attempt=$sandbox\nfailures=0\nnot_measured_rows=()\nleak_seq=0\n' "$tmp/$dir/sandbox" >"$tmp/$dir/scripts/smoke/harness.sh"
  printf '%s\n' 'smoke_row() { printf "row=%s\n" "$1"; }' 'compositor_logs_on() { :; }' 'ok() { :; }' 'smoke_outcome_journal() { :; }' 'smoke_judge_reading() { echo 0 0 intact; }' 'smoke_finish() { :; }' >>"$tmp/$dir/scripts/smoke/harness.sh"
done
# The registry owner hides device commands. The runner retains earlier
# runner-specific hidden names when it appends its own absent tools.
for dir in runner-filter runner-filter-control; do
  printf 'printf "%%s\\n" "${shell_hidden_commands[@]}" >%q\n' "$tmp/$dir/filter" >>"$tmp/$dir/scripts/smoke/harness.sh"
done
runner_filter_holds() {
  local name
  for name in preexisting claude codex; do
    grep -qxF "$name" "$1" || return 1
  done
}
d="$tmp/runner-filter"
status=0
"${base_env[@]}" bash -c 'shell_hidden_commands=(preexisting); source "$1" --rows top' _ "$d/scripts/qml-smoke.sh" >"$d/run.log" 2>&1 || status=$?
if [[ $status == 0 ]] && runner_filter_holds "$d/filter"; then
  ok "the runner retains earlier hidden names while adding its own"
else
  fail "the runner lost an earlier hidden name or its own absent tool"
fi
d="$tmp/runner-filter-control"
plant "$d/scripts/qml-smoke.sh" 'shell_hidden_commands+=(' 'shell_hidden_commands=('
status=0
"${base_env[@]}" bash -c 'shell_hidden_commands=(preexisting); source "$1" --rows top' _ "$d/scripts/qml-smoke.sh" >"$d/run.log" 2>&1 || status=$?
if [[ $status == 0 ]] && ! runner_filter_holds "$d/filter" && grep -qxF claude "$d/filter" && grep -qxF codex "$d/filter"; then
  ok "control: replacing the runner filter loses the earlier hidden name"
else
  fail "control: the replacement filter did not reach the harness"
fi
d="$tmp/runner-reads"
smoke_deep=(bar hyprland-consent seat session base own top start-order auth-sentinel)
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows top 2>&1)" || status=$?
if [[ $status == 0 && $out == "qml-smoke: rows named=top run=$(IFS=,; printf '%s' "${smoke_deep[*]}")"$'\n'"$(printf 'row=%s\n' "${smoke_deep[@]}")" && $(<"$d/fence.log") == fence ]]; then
  ok "a run prints the named and the expanded rows once and runs them in list order"
else
  fail "the runner's expanded run: exit=$status output=$out"
fi
if out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows top --list-rows 2>&1)" && [[ $out == "$(printf '%s\n' "${smoke_deep[@]}")" ]]; then
  ok "the runner lists the rows a named row's chain and a core row's line reach"
else
  fail "the runner's listing of a two-read chain: $out"
fi
: >"$d/fence.log"
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows gone 2>&1)" || status=$?
if [[ $status == 2 && $out == 'qml-smoke: refused: argument=--rows value=gone reason=reads-unknown-row reads=left' && ! -s $d/fence.log ]]; then
  ok "the runner refuses a row that reads a row file the tree lacks, before the fence"
else
  fail "the runner's unknown read refusal: exit=$status output=$out"
fi
d="$tmp/runner-deep-control"
plant "$d/scripts/qml-smoke.sh" $'    qml_smoke_reach[$qml_smoke_row]=1\n' $'    qml_smoke_reach[$qml_smoke_row]=1\n    [[ " ${qml_smoke_named[*]} " == *" $qml_smoke_row "* ]] || continue\n'
if out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows top --list-rows 2>&1)" && [[ $out == $'bar\nhyprland-consent\nsession\nown\ntop\nstart-order\nauth-sentinel' ]]; then
  ok "control: a runner that follows the named rows' lines alone loses the second read and the core row's"
else
  fail "control: the runner that follows the named rows' lines alone listed: $out"
fi
d="$tmp/runner-refusal-control"
plant "$d/scripts/qml-smoke.sh" '      elif [[ ! -f $repo/scripts/smoke/rows/$qml_smoke_read.sh ]]; then' '      elif false; then'
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows gone --list-rows 2>&1)" || status=$?
if [[ $status == 0 && $out == $'bar\nhyprland-consent\nseat\nsession\ngone\nstart-order\nauth-sentinel' ]]; then
  ok "control: a runner without the refusal lists the row"
else
  fail "control: the runner without its unknown read refusal: exit=$status output=$out"
fi
for dir in runner-short runner-short-control; do
  printf '%s\n' '# Rows.' bar hyprland-consent seat session base own top start-order >"$tmp/$dir/scripts/smoke/rows.list"
done
d="$tmp/runner-short"
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows own 2>&1)" || status=$?
if [[ $status == 2 && $out == 'qml-smoke: refused: argument=--rows value=auth-sentinel reason=core-row-missing' && ! -e $d/fence.log ]]; then
  ok "the runner refuses a row list that lacks a core row, before the fence"
else
  fail "the runner's missing core row refusal: exit=$status output=$out"
fi
d="$tmp/runner-short-control"
plant "$d/scripts/qml-smoke.sh" $'  for qml_smoke_row in "${smoke_core[@]}"; do\n    if [[ " ${qml_smoke_rows[*]} " != *" $qml_smoke_row "* ]]; then' $'  for qml_smoke_row in "${smoke_core[@]}"; do\n    if false; then'
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows own --list-rows 2>/dev/null)" || status=$?
if [[ $status == 0 && $out == $'bar\nhyprland-consent\nseat\nsession\nbase\nown\nstart-order' ]]; then
  ok "control: a runner without the core row refusal lists a run that lacks the row"
else
  fail "control: the runner without its missing core row refusal: exit=$status output=$out"
fi

d="$tmp/plan-selector"; fresh "$d"
printf '\n' >>"$d/scripts/validate"
selector_plan=$'node scripts/test-engine-availability.js\nsmoke_reads_named\n'"$repo_plan"$'\nscripts/test-validate.sh'
if out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate --list 2>"$tmp/plan.err")" && [[ $out == "$selector_plan" ]]; then
  ok "selector changes run their control without unrelated product suites"
else
  fail "selector change plan: $out"
fi

# The Jarvis row must select the real environment helper, not only its suite.
# A harmless row fixture fails on a planted helper defect. Removing only the
# dependency edge lets that defect escape, without starting any test daemon.
d="$tmp/plan-jarvis-edge"; fresh "$d"
mkdir -p "$d/scripts/lib"
printf '# neutral selector fixture\n' >"$d/scripts/test-jarvis-local.py"
printf '# neutral selector fixture\n' >"$d/scripts/test-jarvis-setup.py"
printf '#!/usr/bin/env bash\nexit 0\n' >"$d/scripts/check-jarvis-local.sh"
chmod +x "$d/scripts/check-jarvis-local.sh"
printf '# neutral selector fixture\n' >"$d/scripts/test-jarvis-local-speech.py"
printf '#!/usr/bin/env bash\nexit 0\n' >"$d/scripts/check-jarvis-local-speech.sh"
chmod +x "$d/scripts/check-jarvis-local-speech.sh"
printf 'const fs = require("node:fs"); process.exit(fs.readFileSync("scripts/lib/jarvis-env.sh", "utf8") === "clean\\n" ? 0 : 1);\n' >"$d/scripts/test-jarvis-env.js"
printf 'clean\n' >"$d/scripts/lib/jarvis-env.sh"
"${base_env[@]}" git -C "$d" add -A
"${base_env[@]}" git -C "$d" commit -q -m jarvis-row
printf 'defect\n' >"$d/scripts/lib/jarvis-env.sh"
test_area=tools
test_args=(--changed HEAD)
row "a Jarvis helper change runs its row and fails on the defect" "$d" 1 "" \
  "validate: failed=Jarvis test environment controls (exit 1)"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
old = 'node scripts/test-jarvis-env.js|scripts/lib/jarvis-env.sh scripts/fixtures/jarvis-env/*'
assert source.count(old) == 1
changed = source.replace(old, old.replace('scripts/lib/jarvis-env.sh ', ''))
assert changed != source
path.write_text(changed)
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
# An unknown source would select the whole area. Keep the input known to
# another area, so this control isolates the lost tools dependency edge.
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
old = 'logic|plugin logic table|node scripts/test-plugin-logic.js|'
assert source.count(old) == 1
changed = source.replace(old, old + 'scripts/lib/jarvis-env.sh ')
assert changed != source
path.write_text(changed)
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m known-input
row "control: losing the Jarvis helper edge skips its failing row" "$d" 0 "" "validate: ok"
test_area=offline
test_args=()

# Both daemon consumers select their installed dependencies. Each disposable
# selector loses one edge while another row still knows the changed source.
for owner in 'audio-daemon|Jarvis audio daemon lifetime' 'browser|Jarvis browser executor' 'curl-installer|curl installer controls'; do
  suite="${owner%%|*}"; label="${owner#*|}"
  case "$suite" in
    audio-daemon)
      dependencies=(shell/plugins/vgs.jarvis/backend/{ToolRouter,ToolBridge,Mcp,Audit,Private,Redact,Tools,Policy,ShellRequests,DesktopSession,Executors,Desktop,Child,Input,ComputerHelp}.js
        bin/lib/qml-library.js bin/lib/judge-files.js shell/Commons/DesktopLaunch.js) ;;
    browser)
      dependencies=(
        'shell/plugins/vgs.jarvis/backend/jarvisd.js|shell/plugins/vgs.jarvis/backend/*'
        shell/plugins/vgs.jarvis/Session.js shell/plugins/vgs.jarvis/JarvisProtocol.js shell/plugins/vgs.jarvis/AccountProviders.js
        shell/Core/Dispatch.js shell/Commons/DesktopLaunch.js bin/lib/qml-library.js bin/lib/judge-files.js
        'scripts/fixtures/jarvis/audio-tool.py|scripts/fixtures/jarvis/audio*'
        scripts/fixtures/jarvis/desktop.js
        'shell/plugins/vgs.jarvis/backend/skills/computer/input.md|shell/plugins/vgs.jarvis/backend/*') ;;
    curl-installer)
      dependencies=(bin/vgshell-tui bin/vgshell-scan bin/vgshell-plugin-judge shell/Core/PluginLogic.js shell/Core/HyprlandLayer.js
        shell/Commons/SettingValues.js shell/Ui/icons/Lucide.js
        'shell/plugins/vgs.network/manifest.json|shell/plugins/*/manifest.json'
        packaging/arch/vgshell/.SRCINFO packaging/fedora/vgshell.spec) ;;
  esac
  if [[ $suite == curl-installer ]]; then consumer=scripts/test-install-sh.sh; else consumer="node scripts/test-jarvis-$suite.js"; fi
  for spec in "${dependencies[@]}"; do
    file="${spec%%|*}"; edge="${spec#*|}"
    d="$tmp/plan-$suite-edge-$(basename -- "$file")"; fresh "$d"
    mkdir -p -- "$d/$(dirname -- "$file")"
    printf 'changed\n' >"$d/$file"
    # This dependency assertion covers the ordinary mixed-change path.
    [[ $file != shell/plugins/vgs.jarvis/backend/skills/computer/input.md ]] || printf '# mixed change\n' >>"$d/kendex.settings.toml"
    out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate cli --changed HEAD --list 2>"$tmp/plan.err")"
    if grep -qxF "$consumer" <<<"$out"; then
      ok "$suite selects dependency $file"
    else
      fail "$suite omitted dependency $file"
    fi
    python3 - "$d/scripts/validate" "$edge" "$label" <<'PYTHON'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
rows = [row for row in source.splitlines() if '"cli|' + sys.argv[3] + '|' in row]
assert len(rows) == 1
row = rows[0]
prefix, inputs = row.rsplit("|", 1)
assert inputs.endswith('"')
edges = inputs[:-1].split()
assert edges.count(sys.argv[2]) == 1
edges.remove(sys.argv[2])
changed = source.replace(row, prefix + "|" + " ".join(edges) + '"')
assert changed != source
path.write_text(changed)
PYTHON
    "${base_env[@]}" git -C "$d" add scripts/validate
    "${base_env[@]}" git -C "$d" commit -q -m control
    out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate cli --changed HEAD --list 2>"$tmp/plan.err")"
    if grep -qxF "$consumer" <<<"$out"; then
      fail "$suite dependency control did not turn red: $file"
    else
      ok "control: losing $file fails the $suite consumer assertion"
    fi
  done
done

# The shader consumer builds the shared keyboard helper too. A stand-in
# consumer fails on a planted source defect, without starting a compositor.
d="$tmp/plan-keyboard-edge"; fresh "$d"
mkdir -p "$d/scripts/smoke/keyboard"
printf '#!/bin/sh\nexit 0\n' >"$d/scripts/qml-smoke.sh"
printf '#!/bin/sh\ngrep -qx clean scripts/smoke/keyboard/keyboard.c\n' >"$d/scripts/measure-shader.sh"
chmod +x "$d/scripts/qml-smoke.sh" "$d/scripts/measure-shader.sh"
printf 'clean\n' >"$d/scripts/smoke/keyboard/keyboard.c"
"${base_env[@]}" git -C "$d" add -A
"${base_env[@]}" git -C "$d" commit -q -m keyboard-consumers
printf 'defect\n' >"$d/scripts/smoke/keyboard/keyboard.c"
test_area=qml
test_args=(--changed HEAD)
row "a keyboard helper defect selects and fails the shader consumer" "$d" 1 "" \
  "validate: failed=shader GPU cost (exit 1)"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
edge = ' scripts/smoke/keyboard/*'
assert s.count(edge) == 1
changed = s.replace(edge, '')
assert changed != s
p.write_text(changed)
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "control: removing the keyboard edge hides the shader failure" "$d" 0 "" "validate: ok"
test_area=offline
test_args=()

d="$tmp/range-whitespace"; fresh "$d"
printf 'old defect \n' >"$d/clean.txt"
"${base_env[@]}" git -C "$d" add clean.txt
"${base_env[@]}" git -C "$d" commit -q -m previous-round
test_area=repo
test_args=(--changed HEAD)
row "a fix round does not recheck whitespace outside its range" "$d" 0 "" "validate: ok"
test_args=()
row "Kendex supplies the fix-round base without shell interpolation" "$d" 0 "DEV_VALIDATE_BASE=HEAD" "validate: ok"
test_args=(--changed HEAD)
printf 'new defect \n' >"$d/clean.txt"
row "a fix round still rejects new whitespace defects" "$d" 1 "" \
  "whitespace: findings scope=tracked"
test_args=()

# Exercise the real selected guard, then remove only its dependency edge.
# The policy mutation is committed into the fixture's base, so selection
# still judges the same changed source rather than its own policy edit.
# Both runs cover the boundary area, which holds the guard's row. The changed
# file still selects the area's other rows without the edge, so the escape
# run judges the tree with the defect in it rather than an empty selection.
d="$tmp/selected-guard"; product_fixture "$d"
printf 'import "../plugins/vgs.bar"\nQtObject {}\n' >"$d/shell/Core/Bad.qml"
test_area=boundary
test_args=(--changed HEAD)
row "a changed core import runs and fails its boundary check" "$d" 1 "" \
  "validate: failed=plugin boundary (exit 1)" '!validate: selection=full'
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
edge = 'plugin boundary|python3 scripts/check-plugin-boundary.py|shell/* bin/vgshell-scan scripts/qml_source.py'
assert source.count(edge) == 1
path.write_text(source.replace(edge, edge.replace('shell/* ', '')))
PY
"${base_env[@]}" git -C "$d" add scripts/validate
"${base_env[@]}" git -C "$d" commit -q -m control
row "removing the source dependency makes the planted defect escape" "$d" 0 "" \
  "validate: ok" '!row=plugin boundary' '!validate: selected=0 '

# Every row runs under the test-run marker: a planted row fails without it,
# and a copy without the export is caught.
d="$tmp/marker"; fresh "$d"
printf '#!/bin/sh\n[ "$VGS_TEST_RUN" = 1 ]\n' >"$d/scripts/test-marker.sh"; chmod +x "$d/scripts/test-marker.sh"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
assert source.count('rows=(\n') == 1
path.write_text(source.replace('rows=(\n', 'rows=(\n  "tools|test-run marker|scripts/test-marker.sh|"\n'))
PY
"${base_env[@]}" git -C "$d" commit -q -am marker-row
test_area=tools
test_args=(--changed HEAD)
row "a row runs under the test-run marker" "$d" 0 "" "validate: ok"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
assert source.count('export VGS_TEST_RUN=1\n') == 1
path.write_text(source.replace('export VGS_TEST_RUN=1\n', ''))
PY
"${base_env[@]}" git -C "$d" commit -q -am control
row "a validate without the marker export fails the planted row" "$d" 1 "" "validate: failed=test-run marker (exit 1)"

# The catalog producer runs before the row, and its consumer can only read
# the prepared directory. The checker's own suite proves archive verification.
d="$tmp/catalog-input"; fresh "$d"
cp -- "$repo/scripts/smoke/gpu-fence.sh" "$d/scripts/smoke/gpu-fence.sh"
cat >"$d/scripts/check-catalog-wallpaper-names.js" <<'JS'
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const prepare = args[0] === "--prepare";
const listings = args[prepare ? 2 : 1];
const file = path.join(listings, "fixture-sha", "listing.json");
if (prepare) {
    fs.accessSync(process.cwd(), fs.constants.W_OK);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, "prepared\n");
    console.log("producer=parent");
} else {
    if (fs.readFileSync(file, "utf8") !== "prepared\n") process.exit(1);
    try { fs.writeFileSync(file, "changed\n"); process.exit(1); }
    catch (error) { if (error.code !== "EROFS") throw error; }
    if (!process.env.VGSHELL_WORLD_ROOT) process.exit(1);
    console.log("consumer=read-only-world");
}
JS
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
a = s.index('rows=(\n')
b = s.index('\n)\n', a) + 3
p.write_text(s[:a] + 'rows=(\n  "tools|catalog input|catalog_wallpaper_names|"\n)' + s[b:])
PY
"${base_env[@]}" git -C "$d" add -A
"${base_env[@]}" git -C "$d" commit -q -m catalog-input
test_area=tools
test_args=(--full)
row "catalog preparation precedes its read-only world consumer" "$d" 0 "" \
  "producer=parent" "consumer=read-only-world" "validate: ok"
cp -- "$d/scripts/check-catalog-wallpaper-names.js" "$tmp/catalog-checker.js"
rm -rf -- "$tmp/home/.cache/vgshell/validate/theme-listings"
python3 - "$d/scripts/check-catalog-wallpaper-names.js" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '    fs.mkdirSync(path.dirname(file), { recursive: true });\n    fs.writeFileSync(file, "prepared\\n");'
assert s.count(old) == 1
p.write_text(s.replace(old, '    // A producer that returns success without producing its directory.'))
PY
row "a missing producer directory fails the input step before row entry" "$d" 1 "" \
  "validate: input-step=failed name=catalog reason=missing-output" '!consumer=read-only-world' '!== catalog input'
cp -- "$tmp/catalog-checker.js" "$d/scripts/check-catalog-wallpaper-names.js"
rm -rf -- "$tmp/home/.cache/vgshell/validate/theme-listings"
mkdir -p -- "$tmp/home/.cache/vgshell/validate/theme-listings"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '    catalog_input_prepare || exit 1'
assert s.count(old) == 1
p.write_text(s.replace(old, '    catalog_listings="${XDG_CACHE_HOME}/vgshell/validate/theme-listings"'))
PY
row "control: omitting preparation fails the actual catalog consumer" "$d" 1 "" \
  "validate: failed=catalog input (exit 1)" '!consumer=read-only-world'
test_args=()

# An entry must wait for the installed-engine prerequisite even when the
# caller explicitly selected qml and no packaging row will execute.
for spec in pass:0 refuse:1 unreadable:77 bypass:1; do
  state="${spec%:*}"; expected="${spec#*:}"
  d="$tmp/installed-entry-$state"; fresh "$d"
  printf '#!/bin/sh\nprintf "nested-entry=started\\n"\n' >"$d/scripts/qml-smoke.sh"
  chmod +x "$d/scripts/qml-smoke.sh"
  printf 'console.log(JSON.stringify({status: "%s", channel: "installed"})); process.exit(%s);\n' "${state/bypass/refuse}" "$expected" >"$d/scripts/check-packaging.js"
  python3 - "$d/scripts/validate" "$state" <<'PYENGINE'
from pathlib import Path
import sys
p = Path(sys.argv[1]); text = p.read_text()
a = text.index('rows=(\n'); b = text.index('\n)\n', a) + 3
text = text[:a] + 'rows=(\n  "qml|nested entry|scripts/qml-smoke.sh||entry"\n)' + text[b:]
if sys.argv[2] == 'bypass':
    line = '      "$repo/scripts/smoke/gpu-fence.sh" --fresh -- node "$repo/scripts/check-packaging.js" --installed-engine || exit "$?"'
    assert text.count(line) == 1
    text = text.replace(line, '      if false; then\n' + line + '\n      fi')
p.write_text(text)
PYENGINE
  test_area=qml; test_args=(--full)
  if [[ $state == pass ]]; then
    row "installed engine permits explicit qml dispatch" "$d" 0 "" 'nested-entry=started' 'validate: ok'
  elif [[ $state == bypass ]]; then
    if (failures=0; row "installed refusal before dispatch" "$d" 1 "" '!nested-entry=started'; ((failures == 0))) >"$tmp/installed-control.log"; then
      fail "control: bypassing installed prerequisite leaves its dispatch assertion green"
    else
      ok "control: bypassing installed prerequisite fails its dispatch assertion"
    fi
  else
    row "installed engine $state prevents explicit qml dispatch" "$d" "$expected" "" '!nested-entry=started'
  fi
done
test_area=offline; test_args=()

# Selection cases use a transparent world stand-in. These cases use the
# production boundary and a planted reader independent of its implementation.
world_fixture() {
  fresh "$1"
  cp -- "$repo/scripts/smoke/gpu-fence.sh" "$1/scripts/smoke/gpu-fence.sh"
  cat >"$1/scripts/test-world.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'world-root=%s\n' "${VGSHELL_WORLD_ROOT:-none}"
[[ -n ${VGSHELL_WORLD_ROOT:-} && ! -w $PWD && ! -w $PWD/.git ]]
[[ $HOME == "$VGSHELL_WORLD_ROOT/"* && $TMPDIR == "$VGSHELL_WORLD_ROOT/"* ]]
[[ ! -v WAYLAND_DISPLAY && ! -v DISPLAY && ! -v HYPRLAND_INSTANCE_SIGNATURE && ! -v DBUS_SESSION_BUS_ADDRESS ]]
[[ ! -v GIT_CONFIG_GLOBAL ]]
git config --global vgs.row planted
mkdir -p "$XDG_CONFIG_HOME/row"
printf 'planted\n' >"$XDG_CONFIG_HOME/row/file"
SH
  chmod +x "$1/scripts/test-world.sh"
  cat >"$1/scripts/test-network-world.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -n ${VGSHELL_WORLD_ROOT:-} && ! -w $PWD && ! -w $PWD/.git ]]
printf 'network-namespace=%s\n' "$(readlink /proc/self/ns/net)"
SH
  chmod +x "$1/scripts/test-network-world.sh"
  cat >"$1/scripts/test-outside.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -w $PWD && -n ${GIT_CONFIG_GLOBAL:-} && $GIT_CONFIG_GLOBAL != /dev/null ]]
git config --global vgs.row planted
printf 'outside-world=yes\n'
SH
  chmod +x "$1/scripts/test-outside.sh"
  cp -- "$1/scripts/test-outside.sh" "$1/scripts/test-gpu-fence.sh"
  cp -- "$repo/scripts/qml-smoke.sh" "$1/scripts/qml-smoke.sh"
  # This fixture tests the entry's world declarations with a stand-in
  # harness. The real driver and resumed worlds have their own controls.
  plant "$1/scripts/qml-smoke.sh" 'if [[ -z ${qml_smoke_attempt:-} ]]; then' 'if false; then'
  plant "$1/scripts/qml-smoke.sh" 'if [[ -n $first_bar_runs || -n ${qml_smoke_attempt:-} ]]; then' 'if true; then'
  cp -- "$repo/scripts/smoke/rows.list" "$1/scripts/smoke/rows.list"
  printf 'tmp/\n' >"$1/.gitignore"
  cat >"$1/scripts/smoke/harness.sh" <<'SH'
[[ -n ${VGSHELL_WORLD_ROOT:-} && ! -w $repo && ! -w $repo/.git ]]
[[ ! -v WAYLAND_DISPLAY && ! -v DISPLAY && ! -v HYPRLAND_INSTANCE_SIGNATURE ]]
printf 'qml-world-root=%s\n' "$VGSHELL_WORLD_ROOT"
printf 'written\n' >"$smoke_log_dir/world-output"
exit 0
SH
  python3 - "$1/scripts/validate" <<'PYWORLD'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
a = s.index('rows=(\n')
b = s.index('\n)\n', a) + 3
areas = ('logic', 'manifests', 'boundary', 'cli', 'tools', 'repo', 'unit', 'qml')
rows = ['  "' + area + '|world ' + area + '|scripts/test-world.sh|"' for area in areas]
rows += ['  "repo|scratch under row root|world_scratch|"']
rows += ['  "cli|live world|scripts/test-network-world.sh||network"']
rows += ['  "' + area + '|outside ' + area + '|scripts/test-outside.sh||container"' for area in ('package', 'nix')]
rows += ['  "tools|world control exception|scripts/test-gpu-fence.sh||control"']
rows += ['  "qml|graphical entry owner|scripts/qml-smoke.sh --log-dir tmp/qml-output||entry"']
body = '''world_scratch() {
  local scratch
  scratch="$(scratch_file)"
  [[ $scratch == "$VGSHELL_WORLD_ROOT/"* && ! -w $PWD/.git ]]
  rm -- "${scratch:?}"
}
'''
p.write_text(s[:a] + body + 'rows=(\n' + '\n'.join(rows) + '\n)' + s[b:])
PYWORLD
  "${base_env[@]}" git -C "$1" add -A
  "${base_env[@]}" git -C "$1" commit -q -m world-row
}
world_run() { # DIR AREA: leave output and status for assertions and controls
  status=0
  out="$(cd -- "$1" && "${base_env[@]}" WAYLAND_DISPLAY=planted DISPLAY=:99 HYPRLAND_INSTANCE_SIGNATURE=planted DBUS_SESSION_BUS_ADDRESS=unix:path=planted \
    bash scripts/validate "$2" --full 2>&1)" || status=$?
}
d="$tmp/row-world"; world_fixture "$d"
network_namespace="$(readlink /proc/self/ns/net)"
for area in logic manifests boundary cli tools repo unit qml; do
  world_run "$d" "$area"
  if [[ $area == cli ]]; then
    if grep -qxF "network-namespace=$network_namespace" <<<"$out"; then ok "the live row retains its caller's network inside the read-only world"; else fail "the live row lost its declared network"; fi
  fi
  world_root="$(sed -n 's/^world-root=//p' <<<"$out")" || world_root=""
  if [[ $status == 0 && -n $world_root && $world_root != none && ! -e $world_root ]] &&
     "${base_env[@]}" git -C "$d" diff --quiet HEAD && [[ ! -e $d/.git/vgs-validate-tmp && -s $d/.git/vgs-validated-$area ]]; then
    ok "the $area area enters the world and releases its root without checkout writes"
  else
    fail "the $area area world: exit=$status root=$world_root"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
done
qml_output="$out"
cp -- "$d/scripts/validate" "$tmp/network-world-validate"
python3 - "$d/scripts/validate" <<'PYNET'
from pathlib import Path
import sys
p = Path(sys.argv[1]); text = p.read_text()
old = '[[ $owner != network ]] || declarations+=(--net)'
assert text.count(old) == 1
p.write_text(text.replace(old, '[[ $owner != network ]] || declarations+=()'))
PYNET
world_run "$d" cli
if [[ $status != 0 ]] || ! grep -q '^network-namespace=net:\[[0-9]*\]$' <<<"$out"; then
  fail "control: the network operation ended without readable namespace evidence"
elif grep -qxF "network-namespace=$network_namespace" <<<"$out"; then
  fail "control: omitting network declaration leaves its namespace assertion green"
else
  ok "control: omitting network declaration fails its namespace assertion"
fi
cp -- "$tmp/network-world-validate" "$d/scripts/validate"
# Keep the graphical row's output for the existing teardown assertions.
out="$qml_output"
qml_world_root="$(sed -n 's/^qml-world-root=//p' <<<"$out")" || qml_world_root=""
if [[ -n $qml_world_root && ! -e $qml_world_root && $(<"$d/tmp/qml-output/world-output") == written ]]; then
  ok "the graphical entry owns its world and declared output"
else
  fail "the graphical entry did not retain its declared output after world teardown"
fi
for area in package nix; do
  world_run "$d" "$area"
  if [[ $status == 0 ]] && grep -qxF 'outside-world=yes' <<<"$out"; then
    ok "the $area area uses its container boundary outside the world"
  else
    fail "the $area area exception: exit=$status"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
done
# The bypass preserves row re-entry and its data. The planted reader must
# reject the checkout that remains writable when only the boundary is gone.
d="$tmp/row-world-control"; world_fixture "$d"
plant "$d/scripts/validate" '"$repo/scripts/smoke/gpu-fence.sh" "${declarations[@]}" -- "$BASH"' '"$BASH"'
world_run "$d" tools
if [[ $status == 1 ]] && grep -qxF 'validate: failed=world tools (exit 1)' <<<"$out"; then
  ok "control: bypassing world entry exposes a writable checkout and fails the planted rows"
else
  fail "control: bypassing world entry: exit=$status"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# A diff-scoped run exports its NUL-delimited changed-path file to rows.
# A full run unsets even an inherited value, so no stale caller value can
# narrow a row accidentally.
d="$tmp/changed-export"; fresh "$d"
cat >"$d/scripts/changed-list.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'changed-env=%s\n' "${VGS_VALIDATE_CHANGED:-unset}"
if [[ -n ${VGS_VALIDATE_CHANGED:-} ]]; then
  python3 - "$VGS_VALIDATE_CHANGED" <<'PY'
import sys
with open(sys.argv[1], "rb") as source:
    for path in source.read().split(b"\0"):
        if path:
            print("changed-path=" + path.decode())
PY
fi
SH
chmod +x "$d/scripts/changed-list.sh"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
source = path.read_text()
row = '  "tools|changed list echo|scripts/changed-list.sh|changed.dat"'
source, count = re.subn(r'rows=\(\n.*?\n\)\n', 'rows=(\n' + row + '\n)\n', source, count=1, flags=re.S)
assert count == 1
path.write_text(source)
PY
"${base_env[@]}" git -C "$d" add -A
"${base_env[@]}" git -C "$d" commit -q -m changed-list-row
printf 'changed\n' >"$d/changed.dat"
test_area=tools
test_args=(--changed HEAD)
row_re "a diff-scoped run exports the changed path list to rows" "$d" 0 "" \
  "~changed-env=" "changed-path=changed.dat" "~validate: secs=" "validate: ok"
test_args=(--full)
row "a full run unsets the changed path list inherited from the caller" "$d" 0 "VGS_VALIDATE_CHANGED=/x" \
  "changed-env=unset" "!changed-path=changed.dat" "validate: ok"
test_area=offline
test_args=()

# The vgshell suites read bundled plugins through their manifests. A QML
# plugin edit in the cli area no longer selects them, while a manifest edit
# still does.
d="$tmp/plugin-vgshell-selection"; fresh "$d"
for file in shell/plugins/acme.x/Panel.qml shell/plugins/acme.x/manifest.json; do
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf 'changed\n' >"$d/$file"
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate cli --changed HEAD --list 2>"$tmp/plan.err")"
  case "$file" in
    */Panel.qml)
      for consumer in scripts/test-vgshell.sh scripts/test-vgshell-requirements.sh scripts/test-vgshell-outdated.sh scripts/test-install-sh.sh; do
        if grep -qxF "$consumer" <<<"$out"; then fail "plugin QML selected $consumer"; else ok "plugin QML omits $consumer"; fi
      done ;;
    */manifest.json)
      for consumer in scripts/test-vgshell.sh scripts/test-vgshell-requirements.sh scripts/test-vgshell-outdated.sh scripts/test-install-sh.sh; do
        if grep -qxF "$consumer" <<<"$out"; then ok "plugin manifest selects $consumer"; else fail "plugin manifest omitted $consumer"; fi
      done ;;
  esac
  rm -rf -- "$d/shell/plugins/acme.x"
done

# The document byte ceiling row. Its fixture carries the doc-limits checker
# and a 1 KiB class for every Markdown file, both in the base; only the
# documents a row plants differ from it. The keyed lines are the checker's
# notice= protocol, which its header states.
doc_fixture() {
  local dir="$1"
  fresh "$dir"
  mkdir -p "$dir/.agents/skills/doc-limits/scripts"
  cp -R "$repo/.agents/skills/doc-limits/scripts/." "$dir/.agents/skills/doc-limits/scripts/"
  printf '[env]\nWORKTREE_DEFAULT_BRANCH = "trunk"\nDOC_LIMITS_CLASSES = "*.md=1k"\nDOC_LIMITS_DEFAULT_CLASSES = ""\n' >"$dir/kendex.settings.toml"
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m docs
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
}
test_area=tools
test_args=()
d="$tmp/doc-small"; doc_fixture "$d"
printf 'small\n' >"$d/AGENTS.md"
row "an untracked load-point document under its ceiling is measured and passes" "$d" 0 "" \
  "notice=documents-checked count=1" "!notice=argument-retired" "validate: ok"
d="$tmp/doc-big"; doc_fixture "$d"
head -c 2000 /dev/zero | tr '\0' x >"$d/AGENTS.md"
row "an untracked load-point document over its ceiling fails" "$d" 1 "" \
  "notice=document-over-limit path=AGENTS.md" "validate: failed=document byte ceilings (exit 1)"
if [[ -z "$("${base_env[@]}" git -C "$d" ls-files -- AGENTS.md)" ]] && "${base_env[@]}" git -C "$d" diff --cached --quiet; then
  ok "the ceiling row leaves the real index as it was"
else
  fail "the ceiling row wrote the real index"
fi
d="$tmp/doc-budget"; doc_fixture "$d"
head -c 2000 /dev/zero | tr '\0' x >"$d/big.md"
row "an untracked document over its ceiling that no agent loads is not measured" "$d" 0 "" \
  "notice=documents-checked count=0" "!path=big.md" "validate: ok"
d="$tmp/doc-no-checker"; fresh "$d"; printf 'doc\n' >"$d/a.md"
row "a document change with no checker exits 77" "$d" 77 "" \
  "doc-limits: status=not-measured reason=checker-missing path=.agents/skills/doc-limits/scripts/doc-limits" \
  "validate: status=not-measured skipped=document byte ceilings"
d="$tmp/doc-unjudged"; doc_fixture "$d"
printf 'small\n' >"$d/small.md"
row "a checker that cannot judge fails the row" "$d" 1 "DOC_LIMITS_CLASSES=*.md=many" \
  "doc-limits: failed status=2" "validate: failed=document byte ceilings (exit 1)"
# Control: a copy of validate with the scratch index removed, committed so
# the plan against HEAD judges the planted document alone.
test_args=(--changed HEAD)
d="$tmp/doc-control-scratch-index"; doc_fixture "$d"
python3 - "$d/scripts/validate" 'GIT_INDEX_FILE="$scratch" "$checker" ||' '"$checker" ||' <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
"${base_env[@]}" git -C "$d" commit -q -am control
head -c 2000 /dev/zero | tr '\0' x >"$d/AGENTS.md"
row "control: on the real index an untracked document over its ceiling escapes" "$d" 0 "" "validate: ok"

# The markdown reference row. Its fixture commits an AGENTS.md that links
# target.md and its Kept heading; each row plants one defect in the tree the
# change will commit, and md-refs names it.
refs_fixture() {
  local dir="$1"
  fresh "$dir"
  printf '# Target\n\n## Kept\n' >"$dir/target.md"
  printf 'See [target](target.md) and [kept](target.md#kept).\n' >"$dir/AGENTS.md"
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m refs
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
}
refs_failed="validate: failed=markdown references and source citations (exit 1)"
test_area=repo
test_args=()
d="$tmp/refs-clean"; refs_fixture "$d"
row_re "live references pass" "$d" 0 "" \
  "~md-refs: summary=violations=0 references="
d="$tmp/refs-citation-target"; fresh "$d"
rm -- "$d/docs/architecture/validation.md"
row_re "control: default md-refs rejects the copied script's missing citation target" "$d" 1 "" \
  "~md-refs: citation-target=scripts/validate:" \
  "~:docs/architecture/validation.md § Test isolation" "$refs_failed"
cp -- "$repo/docs/architecture/validation.md" "$d/docs/architecture/validation.md"
row "the copied script's citation passes with its document restored" "$d" 0 "" "validate: ok"
d="$tmp/refs-untracked"; refs_fixture "$d"
mkdir -p "$d/sub"; printf 'See [gone](gone.md).\n' >"$d/sub/AGENTS.md"
row "a dead link in an untracked document fails" "$d" 1 "" \
  "md-refs: link-target=sub/AGENTS.md:1:](gone.md):sub/gone.md" "$refs_failed"
if [[ -z "$("${base_env[@]}" git -C "$d" ls-files -- sub/AGENTS.md)" ]] && "${base_env[@]}" git -C "$d" diff --cached --quiet; then
  ok "the reference row leaves the real index as it was"
else
  fail "the reference row wrote the real index"
fi
d="$tmp/refs-heading"; refs_fixture "$d"
printf '# Target\n' >"$d/target.md"
row "an unstaged edit that removes a cited heading fails its unchanged caller" "$d" 1 "" \
  "md-refs: anchor-missing=AGENTS.md:1:](target.md#kept):target.md:kept" "$refs_failed"
d="$tmp/refs-deleted"; refs_fixture "$d"
rm -- "$d/target.md"
row "an unstaged deletion of a linked document fails its unchanged caller" "$d" 1 "" \
  "md-refs: link-target=AGENTS.md:1:](target.md):target.md" "$refs_failed"
d="$tmp/refs-source"; refs_fixture "$d"
mkdir -p "$d/bin"; printf '#!/bin/sh\n# The rule is target.md § Gone.\n' >"$d/bin/tool.sh"
row "a dead section citation in an untracked source file fails" "$d" 1 "" \
  "md-refs: heading-prefix=bin/tool.sh:2:target.md § Gone.:target.md:Gone." "$refs_failed"
d="$tmp/refs-config"; refs_fixture "$d"
row "an md-refs configuration error fails the row, not a skip" "$d" 1 "COMMIT_GUARDS_MD_REFS_SOURCE_PATHS=" \
  "md-refs: glob-empty=COMMIT_GUARDS_MD_REFS_SOURCE_PATHS" "md-refs: failed status=2" "$refs_failed"
d="$tmp/refs-no-checker"; refs_fixture "$d"
rm -rf -- "${d:?}/.agents/skills/commit-guards"
row "a tree with no md-refs checker exits 77" "$d" 77 "" \
  "md-refs: status=not-measured reason=checker-missing path=.agents/skills/commit-guards/scripts/md-refs" \
  "validate: status=not-measured skipped=markdown references and source citations"
d="$tmp/refs-unreadable"; refs_fixture "$d"
printf 'x\n' >"$d/locked.txt"; chmod 000 "$d/locked.txt"
row "a tree the scratch index cannot copy is not measured, not a pass" "$d" 1 "" \
  "md-refs: status=not-measured reason=index-copy-failed path=$d/.git/index"
# Control: a copy of validate that runs md-refs on the real index, committed
# so the plan judges the planted document alone.
d="$tmp/refs-control"; refs_fixture "$d"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
old = 'GIT_INDEX_FILE="$scratch" "$checker" --all'
assert source.count(old) == 1, old
path.write_text(source.replace(old, '"$checker" --all'))
PY
"${base_env[@]}" git -C "$d" commit -q -am control
mkdir -p "$d/sub"; printf 'See [gone](gone.md).\n' >"$d/sub/AGENTS.md"
row "control: on the real index a dead link in an untracked document escapes" "$d" 0 "" "validate: ok"
test_area=offline
test_args=()

# A row's $NAME input: --skip-unprepared leaves the row unselected and named
# while NAME is unset and runs it while NAME is set; without the flag, and in
# a copy without the rule, the row runs unset and reads 77. A run that left a
# row out records no last pass; a copy without that rule records one.
d="$tmp/unprepared"; fresh "$d"
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
assert source.count('rows=(\n') == 1
path.write_text(source.replace('rows=(\n', 'rows=(\n  "logic|prepared row|scripts/check-prepared.sh|\\$VGS_TEST_PREPARED"\n'))
PY
"${base_env[@]}" git -C "$d" commit -q -am prepared-row
printf '#!/bin/sh\nexit 77\n' >"$d/scripts/check-prepared.sh"; chmod +x "$d/scripts/check-prepared.sh"
test_area=logic
test_args=(--changed HEAD --skip-unprepared)
row "--skip-unprepared names an unset prepared row and runs nothing" "$d" 0 "" \
  "validate: unselected unset=VGS_TEST_PREPARED row=prepared row" "validate: ok" '!exit=77 row=prepared row'
row "--skip-unprepared runs a prepared row whose input is set" "$d" 77 "VGS_TEST_PREPARED=1" \
  "validate: status=not-measured skipped=prepared row" '!validate: unselected'
test_args=(--changed HEAD)
row "without --skip-unprepared an unset prepared row runs" "$d" 77 "" \
  "validate: status=not-measured skipped=prepared row" '!validate: unselected'
cp -a -- "$d" "$d-record"
test_args=(--skip-unprepared)
row "a run that left a row out records no last pass" "$d" 0 "" \
  "validate: last-pass=unrecorded reason=unselected" "validate: ok"
if [[ -e $("${base_env[@]}" git -C "$d" rev-parse --absolute-git-dir)/vgs-validated-logic ]]; then
  fail "a run that left a row out wrote a last-pass record"
else
  ok "a run that left a row out wrote no last-pass record"
fi
python3 - "$d-record/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
needle = 'if [[ $unselected == true ]]; then'
assert source.count(needle) == 1
path.write_text(source.replace(needle, 'if false; then'))
PY
"${base_env[@]}" git -C "$d-record" commit -q -am control
row_re "control: a validate without the rule records a run that left a row out" "$d-record" 0 "" \
  "~validate: last-pass=recorded area=logic tree="
python3 - "$d/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
needle = 'if [[ -n $unprepared ]]; then'
assert source.count(needle) == 1
path.write_text(source.replace(needle, 'if false; then'))
PY
"${base_env[@]}" git -C "$d" commit -q -am control
test_args=(--changed HEAD --skip-unprepared)
row "control: a validate without the rule runs the unset prepared row" "$d" 77 "" \
  "validate: status=not-measured skipped=prepared row"

# The sink row's declared character device uses the same preparation
# selection as environment inputs. /dev/null supplies a harmless real
# character device; the absent path needs no host device changes.
d="$tmp/device-unprepared"; fresh "$d"
python3 - "$d/scripts/validate" "$d/absent-device*" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
assert source.count('rows=(\n') == 1
path.write_text(source.replace('rows=(\n', 'rows=(\n  "logic|device row|scripts/check-device.sh|device:' + sys.argv[2] + '"\n'))
PY
"${base_env[@]}" git -C "$d" commit -q -am device-row
printf '#!/bin/sh\nexit 77\n' >"$d/scripts/check-device.sh"
chmod +x "$d/scripts/check-device.sh"
test_args=(--changed HEAD --skip-unprepared)
row "--skip-unprepared names an absent declared device and runs nothing" "$d" 0 "" \
  "validate: unselected missing=device:$d/absent-device* row=device row" "validate: ok" '!exit=77 row=device row'
cp -a -- "$d" "$d-undeclared"
plant "$d-undeclared/scripts/validate" "device:$d/absent-device*" ""
row "control: without its declaration the absent device row runs and exits 77" "$d-undeclared" 77 "" \
  "validate: status=not-measured skipped=device row" '!validate: unselected'
plant "$d/scripts/validate" "device:$d/absent-device*" "device:/dev/nul*"
row "--skip-unprepared runs a row with a present declared character device" "$d" 77 "" \
  "validate: status=not-measured skipped=device row" '!validate: unselected'
test_area=offline
test_args=()

# No two scratch holders of one run get one path. The rows run side by side
# and share $$, so a name drawn from RANDOM and made without exclusive
# creation can go to two of them. The file BASH_ENV names makes RANDOM a
# plain variable, so every draw in validate and its rows is one number. The
# control is a copy that draws its name: its run directory is handed the
# path its changed-paths file holds.
printf 'unset RANDOM\nRANDOM=7\n' >"$tmp/one-draw"
d="$tmp/scratch-own-path"; fresh "$d"
fresh "$d-control"
plant "$d-control/scripts/validate" '  mktemp "$@" -- "$root/validate-$$-XXXXXXXX"' \
  '  local path="$root/validate-$$-$RANDOM"; if [[ $# -gt 0 ]]; then mkdir -- "$path"; else : >"$path"; fi && printf "%s\n" "$path"'
commit "$d-control" drawn-name
test_area=repo
row "each scratch holder of one run gets a path of its own" "$d" 0 "BASH_ENV=$tmp/one-draw" "validate: ok"
row "control: a drawn scratch name goes to two holders" "$d-control" 1 "BASH_ENV=$tmp/one-draw" "validate: run-dir=scratch-failed"

# Rows run side by side. jobs_fixture DIR SCRIPT ROW...: a fixture whose
# table holds only the ROWs, each a whole quoted table entry, beside
# scripts/SCRIPT, read from stdin.
jobs_fixture() {
  local dir="$1" script="$2"
  shift 2
  fresh "$dir"
  cat >"$dir/scripts/$script"
  chmod +x "$dir/scripts/$script"
  python3 - "$dir/scripts/validate" "$@" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
rows = "\n".join("  " + row for row in sys.argv[2:])
source, count = re.subn(r'rows=\(\n.*?\n\)\n', 'rows=(\n' + rows + '\n)\n', path.read_text(), count=1, flags=re.S)
assert count == 1
path.write_text(source)
PY
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m jobs-rows
}
test_area=tools
test_args=(--full)

# Two rows that write one file and read it back for 2 s: run together they
# see each other's write, and one `@NAME` on both keeps them apart.
shared_rows() { # DIR DECLARATION
  jobs_fixture "$1" test-shared.sh "\"tools|shared a|scripts/test-shared.sh a|$2\"" "\"tools|shared b|scripts/test-shared.sh b|$2\"" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >.git/shared-state
i=0
while [ "$i" -lt 20 ]; do
  [ "$(cat .git/shared-state)" = "$1" ] || { echo "shared-state: row $1 read $(cat .git/shared-state)"; exit 1; }
  sleep 0.1
  i=$((i + 1))
done
SH
}
d="$tmp/jobs-shared"; shared_rows "$d" "@shared-state"
row "rows that name one @NAME never run together" "$d" 0 "VGS_VALIDATE_JOBS=2" "validate: ok"
d="$tmp/jobs-shared-control"; shared_rows "$d" ""
row_re "control: rows sharing a file undeclared fail run together" "$d" 1 "VGS_VALIDATE_JOBS=2" "~shared-state: row " "~validate: failed=shared "

# An @alone row starts once the rows before it have ended and ends before
# a row after it starts; each row marks its start and end.
alone_rows() { # DIR DECLARATION
  jobs_fixture "$1" test-mark.sh "\"tools|mark a|scripts/test-mark.sh a 0.6|\"" "\"tools|mark b|scripts/test-mark.sh b 0.6|\"" \
    "\"tools|mark c|scripts/test-mark.sh c 0.2|$2\"" "\"tools|mark d|scripts/test-mark.sh d 0|\"" <<'SH'
#!/bin/sh
echo "start $1" >>.git/marks
sleep "$2"
echo "end $1" >>.git/marks
SH
}
for declaration in @alone ""; do
  d="$tmp/jobs-alone${declaration:+-declared}"; alone_rows "$d" "$declaration"
  row "a fixture of four marked rows passes${declaration:+ with $declaration}" "$d" 0 "VGS_VALIDATE_JOBS=4" "validate: ok"
  marks="$(sed -n '5,7p' "$d/.git/marks" | tr '\n' ' ')" || marks=unreadable
  if [[ -n $declaration ]]; then
    if [[ $marks == "start c end c start d " ]]; then ok "an @alone row runs with no row beside it"; else fail "an @alone row ran beside another: marks 5-7 [$marks]"; cat -- "$d/.git/marks"; fi
  elif [[ $marks != "start c end c start d " ]]; then
    ok "control: the row without @alone runs beside the others"
  else
    fail "control: the row without @alone still ran by itself"
  fi
done

# Rows of different lengths print whole in table order at four jobs, as at
# one, their seconds aside, and the skipped list follows the table.
d="$tmp/jobs-order"
jobs_fixture "$d" test-sleepy.sh "\"tools|one|scripts/test-sleepy.sh one 0.6 0|\"" "\"tools|two|scripts/test-sleepy.sh two 0.4 77|\"" \
  "\"tools|three|scripts/test-sleepy.sh three 0 0|\"" "\"tools|four|scripts/test-sleepy.sh four 0 77|\"" <<'SH'
#!/bin/sh
sleep "$2"
echo "out $1"
echo "err $1" >&2
exit "$3"
SH
for jobs in 1 4; do
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" VGS_VALIDATE_JOBS="$jobs" bash scripts/validate tools --full 2>&1)" || status=$?
  printf '%s\n' "$out" | sed 's/secs=[0-9]*/secs=N/' >"$tmp/jobs-order-$jobs.out"
  if [[ $status == 77 ]] && grep -qxF 'validate: status=not-measured skipped=two;four' <<<"$out"; then
    ok "the skipped list follows the table at $jobs jobs"
  else
    fail "the skipped list at $jobs jobs: exit=$status"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
done
if diff -- "$tmp/jobs-order-1.out" "$tmp/jobs-order-4.out" >/dev/null &&
   [[ "$(grep '^== ' "$tmp/jobs-order-4.out" | tr '\n' ' ')" == "== one == two == three == four " ]]; then
  ok "rows print whole in table order at four jobs as at one"
else
  fail "rows at four jobs print other lines than at one"; diff -- "$tmp/jobs-order-1.out" "$tmp/jobs-order-4.out" | sed 's/^/        /'
fi

# A signal to validate ends every running row's processes and removes the
# run's scratch directory. Each row holds a lock with a sleep that outlives
# the stop, so a free lock proves the row's processes ended. Rows given
# `ignore` ignore TERM, so only the KILL after the deadline or at a repeat
# signal ends them. Each control is a copy without one rule.
hold_rows() { # DIR [ignore]
  jobs_fixture "$1" test-hold.sh "\"tools|hold a|scripts/test-hold.sh a ${2-}|\"" "\"tools|hold b|scripts/test-hold.sh b ${2-}|\"" <<'SH'
#!/bin/sh
secs=8
if [ "$2" = ignore ]; then trap '' TERM; secs=14; fi
exec 9>".git/lock-$1"
flock 9
: >".git/ready-$1"
sleep "$secs"
SH
}
# hold_run DIR SIGNAL...: start validate, send each SIGNAL 0.5 s apart once
# both rows hold their locks; sets status, secs (from the first signal to
# validate's end) and freed, the locks free within 1 s of that end.
hold_run() {
  local dir="$1" pid lock signal started
  shift
  mkdir -p "$dir/tmp"
  (cd -- "$dir" && exec "${base_env[@]}" TMPDIR="$dir/tmp" VGS_VALIDATE_JOBS=2 bash scripts/validate tools --full) >"$dir.out" 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do
    [[ -e $dir/.git/ready-a && -e $dir/.git/ready-b ]] && break
    sleep 0.1
  done
  started=$SECONDS
  for signal in "$@"; do
    kill -s "$signal" "$pid"
    sleep 0.5
  done
  status=0
  wait "$pid" || status=$?
  secs=$((SECONDS - started))
  freed=0
  for lock in "$dir/.git/lock-a" "$dir/.git/lock-b"; do
    if flock -w 1 "$lock" true; then freed=$((freed + 1)); fi
  done
}
hold_mutant() { # DIR OLD NEW: commit the copy with OLD, one whole match, made NEW
  python3 - "$1/scripts/validate" "$2" "$3" <<'PY'
from pathlib import Path
import sys
path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, new))
PY
  "${base_env[@]}" git -C "$1" commit -q -am control
}
hold_cleanup() { # DIR: wait out rows a control left running
  flock -w 20 "$1/.git/lock-a" true || true
  flock -w 20 "$1/.git/lock-b" true || true
}
for spec in TERM@143 HUP@129; do
  signal="${spec%@*}"
  d="$tmp/jobs-$signal"; hold_rows "$d"
  hold_run "$d" "$signal"
  if [[ $status == "${spec#*@}" && $freed == 2 && -z "$(ls -A -- "$d/tmp")" ]]; then
    ok "a $signal to validate ends its rows and removes its scratch directory"
  else
    fail "a $signal to validate: exit=$status freed=$freed scratch=[$(ls -A -- "$d/tmp")]"; sed 's/^/        /' "$d.out"
  fi
done
d="$tmp/jobs-HUP-control"; hold_rows "$d"
hold_mutant "$d" "trap 'stop_rows; records_finish; chmod" "trap 'records_finish; chmod"
hold_run "$d" HUP
if [[ $freed == 0 ]]; then
  ok "control: a validate whose exit path stops no row leaves its rows running"
else
  fail "control: a validate whose exit path stops no row still ended its rows: freed=$freed"
fi
hold_cleanup "$d"
d="$tmp/jobs-deadline"; hold_rows "$d" ignore
hold_run "$d" TERM
if [[ $status == 143 && $freed == 2 && $secs -ge 8 ]]; then
  ok "rows that ignore TERM end by KILL once the stop's deadline passes"
else
  fail "rows that ignore TERM: exit=$status freed=$freed secs=$secs"; sed 's/^/        /' "$d.out"
fi
d="$tmp/jobs-deadline-control"; hold_rows "$d" ignore
hold_mutant "$d" $'  kill_groups KILL\n}\n' $'}\n'
hold_run "$d" TERM
if [[ $freed == 0 ]]; then
  ok "control: a stop without its deadline KILL leaves rows that ignore TERM running"
else
  fail "control: a stop without its deadline KILL still ended its rows: freed=$freed"
fi
hold_cleanup "$d"
d="$tmp/jobs-repeat"; hold_rows "$d" ignore
hold_run "$d" TERM TERM
if [[ $status == 143 && $freed == 2 && $secs -le 4 ]]; then
  ok "a repeat signal during the stop KILLs the rows at once"
else
  fail "a repeat signal during the stop: exit=$status freed=$freed secs=$secs"; sed 's/^/        /' "$d.out"
fi
d="$tmp/jobs-repeat-control"; hold_rows "$d" ignore
hold_mutant "$d" 'kill_groups KILL; return 0; fi' 'return 0; fi'
hold_run "$d" TERM TERM
if [[ $secs -ge 8 ]]; then
  ok "control: a stop that ignores a repeat signal waits for its deadline"
else
  fail "control: a stop that ignores a repeat signal ended in ${secs}s"
fi
hold_cleanup "$d"

d="$tmp/jobs-refused"; fresh "$d"
for value in 0 01 -1 two; do
  row "VGS_VALIDATE_JOBS=$value is refused" "$d" 2 "VGS_VALIDATE_JOBS=$value" "validate: refused: jobs=$value"
done

# scripts/test-qml-unit.sh runs its mutations side by side and prints each
# kill verdict in table order. The copy's runner is a stand-in that exits
# with the verdict its mutated file names after the delay it names, so the
# first row ends last; the copy's other rows fail on the stand-in, and only
# the mutation lines are read. A copy that prints the case logs in reverse
# is the control.
q="$tmp/qml-jobs"
mkdir -p "$q/scripts/qml-tests" "$q/scripts/smoke" "$q/shell/Ui"
printf '#!/bin/sh\nexit 0\n' >"$q/scripts/smoke/gpu-fence.sh"
chmod +x "$q/scripts/smoke/gpu-fence.sh"
printf 'base\n' >"$q/shell/Ui/a.qml"
: >"$q/scripts/qml-tests/tst_x.qml"
cat >"$q/scripts/qml-unit.sh" <<'SH'
#!/usr/bin/env bash
ui=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui) ui="$2"; shift 2 ;;
    --tests|--commons|--core) shift 2 ;;
    --nope) echo 'qml-unit: refused: argument=--nope'; exit 2 ;;
    *) shift ;;
  esac
done
[[ -z ${QML_UNIT_RUNNER:-} ]] || { echo 'qml-unit: status=not-measured missing=qmltestrunner'; exit 77; }
[[ -n $ui ]] || exit 0
read -r verdict delay <"$ui/a.qml"
sleep "${delay:-0}"
case "$verdict" in KILL) exit 1 ;; CRASH) exit 3 ;; *) exit 0 ;; esac
SH
chmod +x "$q/scripts/qml-unit.sh"
python3 - "$repo/scripts/test-qml-unit.sh" "$q/scripts/test-qml-unit.sh" <<'PY'
import sys
source, copy = sys.argv[1:]
lines = open(source, encoding="utf-8").read().split("\n")
start = lines.index("mutations=(") + 1
end = lines.index(")", start)
lines[start:end] = [
    '  "killed slow|a.qml|base|KILL 0.6|tst_x.qml"',
    '  "survived|a.qml|base|SURVIVE|tst_x.qml"',
    '  "crashed|a.qml|base|CRASH|tst_x.qml"',
    '  "killed fast|a.qml|base|KILL 0|tst_x.qml"',
]
open(copy, "w", encoding="utf-8").write("\n".join(lines))
PY
cp -- "$q/scripts/test-qml-unit.sh" "$q/scripts/test-qml-unit-reversed.sh"
python3 - "$q/scripts/test-qml-unit-reversed.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
line = '  cat -- "$tmp/case-$i.log"\n'
source = path.read_text()
assert source.count(line) == 1
path.write_text(source.replace(line, '  cat -- "$tmp/case-$((${#cases[@]} - 1 - i)).log"\n'))
PY
qml_jobs_want=$'  ok    killed slow\n  FAIL  survived: tst_x.qml passed on the mutated copy\n  FAIL  crashed: the runner exited 3, so no test judged the mutated copy\n  ok    killed fast'
for copy in test-qml-unit.sh test-qml-unit-reversed.sh; do
  status=0
  out="$("${base_env[@]}" VGS_VALIDATE_JOBS=4 bash "$q/scripts/$copy" 2>&1)" || status=$?
  got="$(grep -E '^  (ok  |FAIL)  (killed|survived|crashed)' <<<"$out")" || got=""
  if [[ $copy == test-qml-unit.sh ]]; then
    if [[ $status == 1 && $got == "$qml_jobs_want" ]]; then
      ok "qml mutations run side by side keep their kill verdicts in table order"
    else
      fail "qml mutations side by side: exit=$status"; printf '%s\n' "$got" | sed 's/^/        /'
    fi
  elif [[ $got != "$qml_jobs_want" ]]; then
    ok "control: qml mutation verdicts printed out of table order are caught"
  else
    fail "control: qml mutation verdicts printed in reverse still read in table order"
  fi
done
status=0
out="$("${base_env[@]}" VGS_VALIDATE_JOBS=0 bash "$q/scripts/test-qml-unit.sh" --plan 2>&1)" || status=$?
if [[ $status == 2 && $out == 'test-qml-unit: refused: jobs=0' ]]; then
  ok "test-qml-unit refuses VGS_VALIDATE_JOBS=0"
else
  fail "test-qml-unit VGS_VALIDATE_JOBS=0: exit=$status output=$out"
fi
test_area=offline
test_args=()

d="$tmp/arguments"; fresh "$d"
argument_cases=(
  'missing|--changed|changed-base=missing-or-repeated'
  'empty|--changed|changed-base=missing-or-repeated'
  'dash-prefixed|--changed --list|changed-base=missing-or-repeated'
  'repeated|--changed HEAD --changed HEAD|changed-base=missing-or-repeated'
  'full-and-changed|--full --changed HEAD|scope=conflicting-or-repeated'
  'changed-and-full|--changed HEAD --full|scope=conflicting-or-repeated'
  'repeated-full|--full --full|scope=conflicting-or-repeated'
  'second-area|logic|extra-argument=logic'
)
for spec in "${argument_cases[@]}"; do
  IFS='|' read -r name arguments refusal <<<"$spec"
  read -r -a test_args <<<"$arguments"
  [[ $name == empty ]] && test_args+=("")
  row "invalid $name argument is refused" "$d" 2 "" "validate: refused: $refusal"
done

if [[ $failures -gt 0 ]]; then
  echo "test-validate: failed=$failures"
  exit 1
fi
echo "test-validate: ok"
