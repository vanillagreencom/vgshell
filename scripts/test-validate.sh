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
tmp="$repo/tmp/test-validate-$$"
rm -rf -- "$tmp"
mkdir -p -- "$tmp"
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
  JARVIS_TEST_SCRATCH_ROOT="$repo/tmp"
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
# md-refs checker with an exclusion list that keeps its own copy out of its
# scope, a settings file naming trunk as the base branch, one clean file and
# one under each root an install ships, bin/, shell/ and config/, each at a
# path the tree holds, so a fixture that copies the tree in replaces it;
# refs/remotes/origin/trunk points at it; HEAD is a feature branch on top.
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
  mkdir -p "$dir/scripts" "$dir/.agents/skills/orch/scripts/lib" "$dir/.agents/skills/commit-guards" "$dir/tools"
  cp -- "$repo/scripts/validate" "$dir/scripts/validate"
  cp -- "$repo/.agents/skills/orch/scripts/lib/kendex-env.sh" "$dir/.agents/skills/orch/scripts/lib/kendex-env.sh"
  cp -R -- "$repo/.agents/skills/commit-guards/scripts" "$dir/.agents/skills/commit-guards/"
  printf '# kendex-guard-dialect: legacy-glob\n.agents/*\tcopies of checkers, whose citations name their own repository\n' >"$dir/tools/md-excludes"
  printf '[env]\nWORKTREE_DEFAULT_BRANCH = "trunk"\n' >"$dir/kendex.settings.toml"
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
plan_case "qml mutation planning narrows to a changed Radio target" "shell/Ui/controls/Radio.qml" "3/$qml_total" 3 "$qml_total"
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
  files=3
  [[ $file == scripts/* ]] || files=4
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
install_plan=$'scripts/test-install-tree.sh\n'"$repo_plan"
installer_plan=$'scripts/test-install-tree.sh\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-vgshell-self.sh\nscripts/test-install-sh.sh\nscripts/test-release.sh\n'"$repo_plan"
# The README check reads VERSION, bin/vgshell, install.sh, the Arch recipes,
# the plugins, README.md and docs/architecture/runtime.md.
readme_rows=$'node scripts/test-check-readme.js\nscripts/test-readme-install.sh\n'
readme_rows_trimmed="${readme_rows%$'\n'}"
readme_plan="$readme_rows$repo_plan"
curl_installer_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-install-sh.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
heap_plan=$'python3 scripts/test-attribute-heap-profile.py\n'"$repo_plan"
jarvis_local_rows=$'python3 scripts/test-jarvis-local.py\nscripts/check-jarvis-local.sh\n'
jarvis_local_tools_plan=$'python3 scripts/check-readme-images.py\npython3 scripts/test-jarvis-local.py\npython3 scripts/test-jarvis-setup.py\nscripts/check-jarvis-local.sh\npython3 scripts/test-jarvis-local-speech.py\nscripts/check-jarvis-local-speech.sh'
jarvis_env_plan=$'node scripts/test-jarvis-env.js\n'"$repo_plan"
jarvis_helper_plan=$'node scripts/test-jarvis-env.js\npython3 scripts/test-jarvis-local.py\npython3 scripts/test-jarvis-setup.py\nscripts/check-jarvis-local.sh\npython3 scripts/test-jarvis-local-speech.py\nscripts/check-jarvis-local-speech.sh\n'"$repo_plan"
jarvis_policy_rows=$'node scripts/test-jarvis-tools.js\nnode scripts/test-jarvis-policy.js\nnode scripts/test-jarvis-redact.js\nnode scripts/test-jarvis-release.js\nnode scripts/test-jarvis-net.js\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-denied.js\nnode scripts/test-jarvis-audit.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-mcp.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex-protocol.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-child.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\n'
jarvis_audio_rows=$'node scripts/test-jarvis-audio.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-playback.js\nnode scripts/test-jarvis-playback-pipewire.js\n'
jarvis_accounts_rows=$'node scripts/test-jarvis-accounts.js\nnode scripts/test-jarvis-accounts-tui.js\nnode scripts/test-jarvis-account-verify.js\n'
jarvis_secrets_plan=$'node scripts/test-jarvis-net.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows$repo_plan"
# The world helper also selects the local speech adapter beside the audio rows.
jarvis_world_audio_rows="${jarvis_audio_rows/test-jarvis-engine.js$'\n'/test-jarvis-engine.js$'\n'node scripts/test-jarvis-local-speech.js$'\n'}"
jarvis_owner_plan="$jarvis_policy_rows"$'node scripts/test-jarvis-tasks.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_world_audio_rows"$'node scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$jarvis_helper_plan"
jarvis_daemon_plan=$'node scripts/test-jarvis-daemon.js\n'"$repo_plan"
jarvis_live_plan=$'node scripts/test-jarvis-live.js\n'"$repo_plan"
jarvis_fixture_plan=$'node scripts/test-jarvis-protocol.js\nnode scripts/test-jarvis-tasks.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\n'"$repo_plan"
jarvis_guidance_plan=$'node scripts/test-jarvis-guidance.js\n'"$repo_plan"
jarvis_speakable_plan=$'node scripts/test-jarvis-speakable.js\n'"$repo_plan"
jarvis_language_plan=$'node scripts/test-jarvis-guidance.js\nnode scripts/test-jarvis-speakable.js\nnode scripts/test-jarvis-speech-language.js\n'"$repo_plan"
keyboard_rows=$'python3 scripts/check-keyboard.py shell\npython3 scripts/test-check-keyboard.py\n'
keyboard_check=$'python3 scripts/check-keyboard.py shell\n'
dispatch_plan=$'node scripts/test-input-facts.js\nnode scripts/test-dispatch.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\npython3 scripts/test-capture.py\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check$repo_plan"
session_plan=$'scripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check$repo_plan"$'\nscripts/test-keyboard-ui.sh\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh\nscripts/test-session-lock.sh\nscripts/test-flake.sh\nscripts/qml-smoke.sh'
fixture_plan=$'node bin/lib/check-manifests.js --base scripts/smoke/fixtures/plugins\npython3 scripts/check-plugin-boundary.py --shell scripts/smoke/fixtures\npython3 scripts/check-design-tokens.py\nsmoke_reads_named\n'"$repo_plan"$'\nscripts/test-validate.sh\nscripts/qml-smoke.sh'
smoke_plan=$'python3 scripts/check-smoke-readers.py\npython3 scripts/test-check-smoke-readers.py\npython3 scripts/check-smoke-terminal.py\npython3 scripts/test-check-smoke-terminal.py\nsmoke_reads_named\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
orb_shader_plan=$'scripts/test-install-tree.sh\npython3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-voiceorb-shader.py\npython3 scripts/test-check-voiceorb-shader.py\npython3 scripts/test-measure-shader.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_rows$repo_plan"$'\nscripts/test-keyboard-ui.sh\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh\nnode scripts/test-key-labels.js\nscripts/test-flake.sh\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
orb_check_plan=$'python3 scripts/check-voiceorb-shader.py\npython3 scripts/test-check-voiceorb-shader.py\npython3 scripts/check-plasma-shader.py\npython3 scripts/test-check-plasma-shader.py\npython3 scripts/test-measure-shader.py\n'"$repo_plan"
shader_measure_plan=$'python3 scripts/test-measure-shader.py\n'"$repo_plan"$'\nscripts/measure-shader.sh'
keyboard_plan=$'smoke_reads_named\n'"$repo_plan"$'\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
fedora_plan=$'scripts/test-fedora-srpm.sh\n'
version_plan=$'scripts/test-vgshell-version.sh\nscripts/test-install-tree.sh\n'"$fedora_plan"$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
# A recipe change runs the recipe check and its controls, never the product
# smoke; the container build runs only where the area admits it, never
# offline.
recipe_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-publish-aur.sh\n'"$repo_plan"
# An Arch recipe is also the README's source for the AUR commands.
# The release suite's parity rows build the Arch recipes' host side.
arch_recipe_plan=$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-vgshell-requirements.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
settings_core_prefix=$'node scripts/test-vpn-logic.js\nnode scripts/test-plugin-logic.js\nnode scripts/test-pads.js\nnode scripts/test-plugin-status.js\nnode scripts/test-plugin-extras.js\nnode scripts/test-plugin-menu.js\nnode scripts/test-key-capture.js\nnode scripts/test-tui-logic.js\nnode scripts/test-ipc-logic.js\nnode scripts/test-notice-logic.js\nnode scripts/test-hyprland-layer.js\nnode scripts/test-hyprland-state.js\nnode scripts/test-input-facts.js\n'
settings_theme_rows=$'bin/vgshell-theme-judge packages themes\n'
settings_plugin_rows=$'node scripts/test-themes-setup.js\nnode scripts/test-notifications-logic.js\nnode scripts/test-greeter-logic.js\nnode scripts/test-polkit-model.js\nnode scripts/test-displays-logic.js\n'
settings_values_plugin_rows="${settings_plugin_rows%$'node scripts/test-displays-logic.js\n'}"
settings_catalog_rows=$'node scripts/test-check-devtools-catalog.js\n'
settings_reply_row='node scripts/test-settings-reply.js'
settings_steps_row='node scripts/test-settings-steps.js'
cases=(
  "displays-vrr-setting|shell/plugins/vgs.displays/manifest.json|logic|node scripts/test-displays-logic.js"
  "power-logic|shell/plugins/vgs.power/PowerLogic.js|logic|node scripts/test-power-logic.js"
  "duration-shared|shell/Commons/Duration.js|logic|node scripts/test-duration.js"$'\nnode scripts/test-automations-logic.js\nnode scripts/test-automations-view-logic.js\nnode scripts/test-agent-warden-view.js\nnode scripts/test-agent-warden-notices.js'
  "nmcli-shared|shell/Commons/Nmcli.js|logic|node scripts/test-network-logic.js"$'\nnode scripts/test-vpn-logic.js'
  "vpn-import|shell/plugins/vgs.vpn/tui/import-wireguard.sh|cli|scripts/test-vpn-import.sh"$'\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "network-logic|shell/plugins/vgs.network/NetworkLogic.js|logic|node scripts/test-network-logic.js"
  "network-share|shell/plugins/vgs.network/bin/share-qr|logic|python3 scripts/test-network-share.py"
  "devtools-window|shell/plugins/vgs.devtools/Window.qml|logic|node scripts/test-devtools-view.js"
  "settings-reply-window|shell/plugins/vgs.settings/Window.qml|logic|node scripts/test-settings-reply.js"
  "settings-reply-page|shell/plugins/vgs.settings/PluginPage.qml|logic|node scripts/test-settings-reply.js"
  "settings-reply-input|shell/Commons/Reply.js|logic|node scripts/test-settings-reply.js"
  "settings-reply-suite|scripts/test-settings-reply.js|logic|node scripts/test-settings-reply.js"
  "settings-steps-input|shell/plugins/vgs.settings/Steps.js|logic|$settings_steps_row"
  "settings-steps-suite|scripts/test-settings-steps.js|logic|$settings_steps_row"
  "settings-reply-key-label|shell/Ui/controls/BindField.qml|logic|$settings_reply_row"
  "settings-reply-launcher|shell/plugins/vgs.launcher/Service.qml|logic|$settings_reply_row"
  "settings-reply-probe|scripts/smoke/Probe.qml|logic|$settings_reply_row"
  "settings-reply-shots|scripts/sandbox-shots.sh|logic|$settings_reply_row"
  "settings-reply-fixture|scripts/smoke/fixtures/plugins/acme.hyprland/manifest.json|logic|$settings_reply_row"
  "settings-reply-layer-binding|shell/Core/HyprlandLayer.qml|logic|$settings_reply_row"
  "settings-reply-producer|shell/Core/PluginLogic.js|logic|$settings_core_prefix$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_reply_row"$'\n'"$settings_steps_row"
  "settings-reply-layer|shell/Core/HyprlandLayer.js|logic|$settings_core_prefix"$'node scripts/test-dispatch.js\n'"$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_reply_row"$'\n'"$settings_steps_row"
  "settings-reply-values|shell/Commons/SettingValues.js|logic|$settings_core_prefix"$'node scripts/test-setting-values.js\n'"$settings_theme_rows$settings_values_plugin_rows"$'node scripts/test-bluetooth-logic.js\nnode scripts/test-displays-logic.js\nnode scripts/test-jarvis-setup-gate.js\n'"$settings_reply_row"$'\n'"$settings_steps_row"
  "settings-reply-packages|shell/Core/PackageManagers.js|logic|$settings_core_prefix$settings_theme_rows$settings_plugin_rows"$'node scripts/test-jarvis-setup-gate.js\n'"$settings_catalog_rows$settings_reply_row"$'\n'"$settings_steps_row"
  "settings-reply-icons|shell/Ui/icons/Lucide.js|logic|$settings_core_prefix"$'node scripts/test-icon-bounds.js\n'"$settings_theme_rows"$'node scripts/test-lucide-data.js\n'"$settings_plugin_rows"$'node scripts/test-jarvis-widget.js\nnode scripts/test-jarvis-setup-gate.js\n'"$settings_catalog_rows"$'node scripts/test-agent-warden-view.js\n'"$settings_reply_row"$'\n'"$settings_steps_row"
  "catalog-judge|themes/catalog/index.json|tools|node scripts/test-vgshell-theme-judge.js"
  "catalog-contrast|themes/catalog/index.json|logic|node scripts/test-theme-logic.js"$'\n'"$settings_theme_rows"'node scripts/test-check-theme-contrast.js'
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
  "device-fakes-harness|scripts/smoke/devices.sh|all|python3 scripts/check-smoke-readers.py"$'\npython3 scripts/test-check-smoke-readers.py\n'"$keyboard_plan"
  "device-fakes-fixture|scripts/smoke/fixtures/devices/stand-in.py|all|python3 scripts/test-displays-brightness.py"$'\n'"$fixture_plan"$'\nscripts/measure-shader.sh'
  "docs|docs/architecture/overview.md|offline|$repo_plan"$'\ndoc_limits_check'
  "runtime-doc|docs/architecture/runtime.md|offline|$readme_plan"$'\ndoc_limits_check'
  "docs-html|docs/guide.html|offline|$repo_plan"$'\ndoc_limits_check'
  "root-markdown|NOTES.md|offline|$repo_plan"$'\ndoc_limits_check'
  "version|VERSION|offline|$version_plan"
  "licence|LICENSE|all|$install_plan"
  "flake|flake.nix|all|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nscripts/test-publish-aur.sh\n'"$repo_plan"$'\nscripts/test-flake.sh'
  "flake-offline|flake.nix|offline|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\nscripts/test-publish-aur.sh\n'"$repo_plan"
  "installer|packaging/install-system.sh|offline|$installer_plan"
  "portal-config|packaging/xdg-desktop-portal/hyprland-portals.conf|offline|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\n'"$repo_plan"
  "curl-installer|install.sh|offline|$curl_installer_plan"
  "recipe|packaging/arch/vgshell/PKGBUILD|offline|$arch_recipe_plan"
  "curl-installer-srcinfo|packaging/arch/vgshell/.SRCINFO|offline|node scripts/check-packaging.js"$'\nnode scripts/test-check-packaging.js\n'"$readme_rows"$'scripts/test-vgshell-requirements.sh\nscripts/test-install-sh.sh\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
  "recipe-all|packaging/arch/vgshell-git/.SRCINFO|all|$arch_recipe_plan"$'\nscripts/arch-packages.sh'
  "recipe-package|packaging/arch/vgshell/PKGBUILD|package|scripts/arch-packages.sh"
  "requirements|config/requirements.json|offline|node scripts/test-plugin-logic.js"$'\nscripts/test-install-tree.sh\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-vgshell-requirements.sh\nscripts/test-install-sh.sh\nscripts/test-publish-aur.sh\npython3 scripts/check-user-commands.py\npython3 scripts/test-check-user-commands.py\n'"$repo_plan"
  "install-manifest|packaging/install-tree.manifest|offline|scripts/test-install-tree.sh"$'\nnode scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-release.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"$'\nscripts/test-validate.sh'
  "fedora-recipe|packaging/fedora/vgshell.spec|all|$fedora_plan"$'node scripts/check-packaging.js\nnode scripts/test-check-packaging.js\nscripts/test-install-sh.sh\nscripts/test-publish-aur.sh\n'"$repo_plan"
  "copr-entry|.copr/Makefile|all|scripts/test-fedora-srpm.sh"$'\n'"$repo_plan"
  # test-validate.sh runs the mutation planner of the QML unit controls.
  "qml-unit-planner|scripts/test-qml-unit.sh|tools|scripts/test-validate.sh"
  "heap|scripts/attribute-heap-profile.py|offline|$heap_plan"
  "suite|scripts/test-attribute-heap-profile.py|offline|$heap_plan"
  "jarvis-env|scripts/lib/jarvis-env.sh|all|$jarvis_owner_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-env-suite|scripts/test-jarvis-env.js|offline|$jarvis_env_plan"
  "jarvis-env-fixture|scripts/fixtures/jarvis-env/probe.py|all|$jarvis_env_plan"
  "jarvis-daemon-suite|scripts/test-jarvis-daemon.js|offline|$jarvis_daemon_plan"
  "jarvis-secrets-suite|scripts/test-jarvis-secrets.js|offline|node scripts/test-jarvis-secrets.js"$'\n'"$repo_plan"
  "jarvis-key-tui-fixture|scripts/fixtures/jarvis/key-tui.py|offline|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\n'"$repo_plan"
  "jarvis-key-fixture|scripts/fixtures/jarvis/keys-world.js|offline|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\n'"$repo_plan"
  "jarvis-task-suite|scripts/test-jarvis-tasks.js|offline|node scripts/test-jarvis-tasks.js"$'\n'"$repo_plan"
  "jarvis-audio-task-input|shell/plugins/vgs.jarvis/backend/Tasks.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-task-event.js\nnode scripts/test-jarvis-task-runner.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "task-event-suite|scripts/test-task-event.js|offline|node scripts/test-task-event.js"$'\n'"$repo_plan"
  "task-event-prefix|scripts/test-task-event.js|all|node scripts/test-task-event.js"$'\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-audio-suite|scripts/test-jarvis-audio.js|offline|node scripts/test-jarvis-audio.js"$'\n'"$repo_plan"
  "jarvis-engine-suite|scripts/test-jarvis-engine.js|offline|node scripts/test-jarvis-engine.js"$'\n'"$repo_plan"
  "jarvis-engine-input|shell/plugins/vgs.jarvis/backend/ChainedEngine.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-engine-fixture|scripts/fixtures/jarvis/engine.js|offline|node scripts/test-jarvis-claude.js"$'\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-brain-frames|scripts/fixtures/jarvis-brain/openai-chat-frames.js|offline|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-audio-daemon-suite|scripts/test-jarvis-audio-daemon.js|offline|node scripts/test-jarvis-audio-daemon.js"$'\n'"$repo_plan"
  "jarvis-playback-suite|scripts/test-jarvis-playback.js|offline|node scripts/test-jarvis-playback.js"$'\n'"$repo_plan"
  "jarvis-pipewire-suite|scripts/test-jarvis-playback-pipewire.js|offline|node scripts/test-jarvis-playback-pipewire.js"$'\n'"$repo_plan"
  "jarvis-playback-fixture|scripts/fixtures/jarvis/playback.js|offline|node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-playback.js\nnode scripts/test-jarvis-playback-pipewire.js\n'"$repo_plan"
  "jarvis-playback-config|scripts/fixtures/jarvis/playback.conf|offline|node scripts/test-jarvis-daemon.js"$'\nnode scripts/test-jarvis-playback-pipewire.js\n'"$repo_plan"
  "jarvis-audio-fixture|scripts/fixtures/jarvis/audio-tool.py|offline|node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-daemon.js"$'\n'"$jarvis_audio_rows$repo_plan"
  "jarvis-accounts-suite|scripts/test-jarvis-accounts.js|offline|node scripts/test-jarvis-accounts.js"$'\n'"$repo_plan"
  "jarvis-accounts-tui-suite|scripts/test-jarvis-accounts-tui.js|offline|node scripts/test-jarvis-accounts-tui.js"$'\n'"$repo_plan"
  "jarvis-account-verify-suite|scripts/test-jarvis-account-verify.js|offline|node scripts/test-jarvis-account-verify.js"$'\n'"$repo_plan"
  "jarvis-accounts-fixture|scripts/fixtures/jarvis/accounts-world.js|offline|node scripts/test-jarvis-daemon.js"$'\n'"$jarvis_accounts_rows$repo_plan"
  "jarvis-accounts-terminal-fixture|scripts/fixtures/jarvis/accounts-tui.py|offline|node scripts/test-jarvis-browser-setup.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-accounts-tui.js\n'"$repo_plan"
  "jarvis-fixture|scripts/fixtures/jarvis/prepare.js|offline|$jarvis_fixture_plan"
  "jarvis-scripted-fixture|scripts/fixtures/jarvis/scripted.js|offline|node scripts/test-jarvis-protocol.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\n'"$repo_plan"
  "jarvis-bubble-input|shell/plugins/vgs.jarvis/Bubble.qml|qml|scripts/qml-smoke.sh"
  "jarvis-bubble-row|scripts/smoke/rows/jarvis-bubble.sh|qml|scripts/qml-smoke.sh"
  "jarvis-fixture-all|scripts/fixtures/jarvis/prepare.js|all|$jarvis_fixture_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-protocol-suite|scripts/test-jarvis-protocol.js|offline|node scripts/test-jarvis-protocol.js"$'\n'"$repo_plan"
  "jarvis-local-suite|scripts/test-jarvis-local.py|all|python3 scripts/test-jarvis-local.py"$'\n'"$repo_plan"
  "jarvis-setup-suite|scripts/test-jarvis-setup.py|all|python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "jarvis-setup-probe-fixture|scripts/fixtures/jarvis-setup/installed-probe.py|all|python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "install-tree-suite|scripts/test-install-tree.sh|all|node scripts/test-jarvis-browser-setup.js"$'\nscripts/test-install-tree.sh'$'\npython3 scripts/test-jarvis-setup.py\n'"$repo_plan"
  "jarvis-setup-fixture|scripts/fixtures/jarvis-setup/installer.py|all|python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"
  "jarvis-setup-status-fixture|scripts/fixtures/jarvis-setup/status.py|all|python3 scripts/test-jarvis-setup.py"$'\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-setup-installed-fixture|scripts/fixtures/jarvis-setup/installed.py|all|scripts/test-install-tree.sh"$'\npython3 scripts/test-jarvis-setup.py\n'"$repo_plan"$'\nscripts/qml-smoke.sh'
  "jarvis-local-runner|scripts/check-jarvis-local.sh|all|$jarvis_local_rows$repo_plan"
  "jarvis-local-fixture|scripts/fixtures/jarvis-local/run.py|all|$jarvis_local_rows$repo_plan"
  "jarvis-unbounded-probe|scripts/fixtures/jarvis-local/probe-moonshine.py|all|$jarvis_local_rows$repo_plan"
  "jarvis-artifacts|shell/plugins/vgs.jarvis/artifacts.json|tools|$jarvis_local_tools_plan"
  "jarvis-measure|shell/plugins/vgs.jarvis/measure-local|tools|$jarvis_local_tools_plan"
  "jarvis-clip|shell/plugins/vgs.jarvis/fixtures/probe.wav|tools|$jarvis_local_tools_plan"
  "jarvis-browser-daemon-input|shell/plugins/vgs.jarvis/backend/jarvisd.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-suite|scripts/test-jarvis-browser.js|offline|node scripts/test-jarvis-browser.js"$'\n'"$repo_plan"
  "jarvis-browser-setup-suite|scripts/test-jarvis-browser-setup.js|offline|node scripts/test-jarvis-browser-setup.js"$'\n'"$repo_plan"
  "jarvis-input-owner|shell/plugins/vgs.jarvis/backend/Input.js|cli|node scripts/test-jarvis-input.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-computer-help|shell/plugins/vgs.jarvis/backend/ComputerHelp.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-input-help|shell/plugins/vgs.jarvis/backend/skills/computer/input.md|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-input|shell/plugins/vgs.jarvis/backend/Browser.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-setup-input|shell/plugins/vgs.jarvis/backend/browser-setup.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\n'"node scripts/test-jarvis-browser-setup.js"$'\nnode scripts/test-jarvis-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-browser-fixture|scripts/fixtures/jarvis/browser.py|offline|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-daemon.js\n'"$repo_plan"
  "jarvis-tools-suite|scripts/test-jarvis-tools.js|offline|node scripts/test-jarvis-tools.js"$'\n'"$repo_plan"
  "jarvis-policy-suite|scripts/test-jarvis-policy.js|offline|node scripts/test-jarvis-policy.js"$'\n'"$repo_plan"
  "jarvis-release-suite|scripts/test-jarvis-release.js|offline|node scripts/test-jarvis-release.js"$'\n'"$repo_plan"
  "jarvis-net-suite|scripts/test-jarvis-net.js|offline|node scripts/test-jarvis-net.js"$'\n'"$repo_plan"
  "jarvis-sse-suite|scripts/test-jarvis-sse.js|offline|node scripts/test-jarvis-sse.js"$'\n'"$repo_plan"
  "jarvis-providers-suite|scripts/test-jarvis-providers.js|offline|node scripts/test-jarvis-providers.js"$'\n'"$repo_plan"
  "jarvis-brain-suite|scripts/test-jarvis-brain-openai.js|offline|node scripts/test-jarvis-brain-openai.js"$'\n'"$repo_plan"
  "jarvis-brain-scripts|scripts/fixtures/jarvis-brain/openai-chat-scripts.json|offline|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$repo_plan"
  "jarvis-brain-schema|scripts/fixtures/jarvis-brain/openai-chat.schema.json|offline|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-anthropic-suite|scripts/test-jarvis-brain-anthropic.js|offline|node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-anthropic-scripts|scripts/fixtures/jarvis-brain/anthropic-messages-scripts.json|offline|node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-anthropic-schema|scripts/fixtures/jarvis-brain/anthropic-messages.schema.json|offline|node scripts/test-jarvis-brain-anthropic.js"$'\n'"$repo_plan"
  "jarvis-live-suite|scripts/test-jarvis-live.js|offline|$jarvis_live_plan"
  "jarvis-live-scripts|scripts/fixtures/jarvis-live/gpt-live-scripts.json|offline|$jarvis_live_plan"
  "jarvis-live-schema|scripts/fixtures/jarvis-live/gpt-live.schema.json|offline|$jarvis_live_plan"
  "jarvis-live-input|shell/plugins/vgs.jarvis/backend/GptLive.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-websocket-fixture|scripts/fixtures/jarvis/websocket.js|offline|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-live.js\n'"$jarvis_daemon_plan"
  "jarvis-session-cli|shell/plugins/vgs.jarvis/Session.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_audio_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "schema-check-suite|scripts/test-schema-check.js|offline|node scripts/test-schema-check.js"$'\n'"$repo_plan"
  "schema-check|scripts/fixtures/schema-check.js|offline|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-mcp.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex-protocol.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-sse-input|shell/plugins/vgs.jarvis/backend/Sse.js|logic|node scripts/test-jarvis-sse.js"
  "jarvis-sse-cli-input|shell/plugins/vgs.jarvis/backend/Sse.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-providers-input|shell/plugins/vgs.jarvis/backend/Providers.js|logic|node scripts/test-jarvis-providers.js"
  "jarvis-brain-input|shell/plugins/vgs.jarvis/backend/OpenAIChat.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-wire-input|shell/plugins/vgs.jarvis/backend/WireBrain.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-anthropic-input|shell/plugins/vgs.jarvis/backend/AnthropicMessages.js|cli|node scripts/test-jarvis-brain-anthropic.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-denied-suite|scripts/test-jarvis-denied.js|offline|node scripts/test-jarvis-denied.js"$'\n'"$repo_plan"
  "jarvis-redact-suite|scripts/test-jarvis-redact.js|offline|node scripts/test-jarvis-redact.js"$'\n'"$repo_plan"
  "jarvis-audit-suite|scripts/test-jarvis-audit.js|offline|node scripts/test-jarvis-audit.js"$'\n'"$repo_plan"
  "jarvis-shell-input|shell/plugins/vgs.jarvis/backend/Shell.js|cli|node scripts/test-jarvis-files.js"$'\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-shell.js'$'\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-computer-reference|shell/plugins/vgs.jarvis/backend/skills/computer/shell.md|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-shell-suite|scripts/test-jarvis-shell.js|offline|node scripts/test-jarvis-shell.js"$'\n'"$repo_plan"
  "jarvis-router-suite|scripts/test-jarvis-router.js|offline|node scripts/test-jarvis-router.js"$'\n'"$repo_plan"
  "jarvis-router-input|shell/plugins/vgs.jarvis/backend/ToolRouter.js|cli|node scripts/test-jarvis-router.js"$'\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-policy-fixture|scripts/fixtures/jarvis/policy.js|offline|$jarvis_policy_rows$jarvis_daemon_plan"
  "jarvis-tools-input|shell/plugins/vgs.jarvis/backend/Tools.js|logic|node scripts/test-jarvis-tools.js"$'\nnode scripts/test-jarvis-policy.js\nnode scripts/test-jarvis-redact.js'
  "jarvis-audit-input|shell/plugins/vgs.jarvis/backend/Audit.js|cli|node scripts/test-jarvis-audit.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\n'$'node scripts/test-jarvis-shell.js\n'"${jarvis_daemon_plan%$repo_plan}"$'node scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-redact-input|shell/plugins/vgs.jarvis/backend/Redact.js|logic|node scripts/test-jarvis-redact.js"
  "jarvis-redact-router-input|shell/plugins/vgs.jarvis/backend/Redact.js|cli|node scripts/test-jarvis-audit.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-policy-input|shell/plugins/vgs.jarvis/backend/Policy.js|logic|node scripts/test-jarvis-policy.js"$'\nnode scripts/test-jarvis-release.js'
  "jarvis-policy-net-input|shell/plugins/vgs.jarvis/backend/Policy.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-net-input|shell/plugins/vgs.jarvis/backend/net.js|logic|node scripts/test-jarvis-release.js"$'\nnode scripts/test-jarvis-providers.js'
  "jarvis-net-cli-input|shell/plugins/vgs.jarvis/backend/net.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-brain-openai.js\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-secrets.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-add-key-input|shell/plugins/vgs.jarvis/backend/keys.js|cli|node scripts/test-jarvis-net.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-secrets.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-denied-input|shell/plugins/vgs.jarvis/backend/Denied.js|logic|node scripts/test-jarvis-policy.js"
  "jarvis-denied-cli-input|shell/plugins/vgs.jarvis/backend/Denied.js|cli|node scripts/test-jarvis-denied.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-sandbox-input|shell/plugins/vgs.jarvis/backend/Sandbox.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-sandbox.js'$'\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-child-input|shell/plugins/vgs.jarvis/backend/Child.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-child.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-input|shell/plugins/vgs.jarvis/backend/Desktop.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-session-input|shell/plugins/vgs.jarvis/backend/DesktopSession.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-executors-input|shell/plugins/vgs.jarvis/backend/Executors.js|cli|node scripts/test-jarvis-desktop.js"$'\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-desktop-fixture|scripts/fixtures/jarvis/desktop-tool.py|cli|node scripts/test-jarvis-desktop-tools.js"$'\nnode scripts/test-jarvis-daemon.js'
  "jarvis-forbidden-input|scripts/fixtures/jarvis/forbidden.js|logic|"
  "jarvis-forbidden-cli-input|scripts/fixtures/jarvis/forbidden.js|cli|node scripts/test-jarvis-sandbox.js"$'\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js'
  "jarvis-sandbox-datagram-input|scripts/fixtures/jarvis/sandbox-datagram.py|cli|node scripts/test-jarvis-sandbox.js"$'\nnode scripts/test-jarvis-daemon.js'
  "jarvis-session-suite|scripts/test-jarvis-session.js|offline|node scripts/test-jarvis-session.js"$'\n'"$repo_plan"
  "jarvis-owner-suite|scripts/test-jarvis-session-runner.js|offline|node scripts/test-jarvis-session-runner.js"$'\n'"$repo_plan"
  "jarvis-session|shell/plugins/vgs.jarvis/Session.js|logic|node scripts/test-jarvis-session.js"$'\nnode scripts/test-jarvis-session-runner.js\nnode scripts/test-jarvis-widget.js\nnode scripts/test-jarvis-protocol.js\nnode scripts/test-jarvis-requests.js'
  "jarvis-session-router|shell/plugins/vgs.jarvis/Session.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\n'"$jarvis_audio_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-owner|shell/plugins/vgs.jarvis/backend/session-runner.js|logic|node scripts/test-jarvis-session-runner.js"
  "jarvis-owner-router|shell/plugins/vgs.jarvis/backend/session-runner.js|cli|node scripts/test-jarvis-live.js"$'\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nscripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-tools-router|shell/plugins/vgs.jarvis/backend/Tools.js|cli|node scripts/test-jarvis-brain-openai.js"$'\nnode scripts/test-jarvis-brain-anthropic.js\nnode scripts/test-jarvis-live.js\nnode scripts/test-jarvis-audit.js\nnode scripts/test-jarvis-router.js\nnode scripts/test-jarvis-input.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-browser-setup.js\nnode scripts/test-jarvis-bridge.js\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-sandbox.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\nnode scripts/test-jarvis-shell.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\nnode scripts/test-jarvis-task-runner.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-claude-input|shell/plugins/vgs.jarvis/backend/ClaudeCode.js|cli|node scripts/test-jarvis-files.js"$'\n'"node scripts/test-jarvis-browser.js"$'\nnode scripts/test-jarvis-claude.js\nnode scripts/test-jarvis-codex.js\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nnode scripts/test-jarvis-engine.js\n'"$jarvis_accounts_rows"$'scripts/test-install-tree.sh\n'"$readme_rows_trimmed"
  "jarvis-claude-standin|scripts/fixtures/jarvis-claude/claude|cli|node scripts/test-jarvis-claude.js"
  "jarvis-guidance-suite|scripts/test-jarvis-guidance.js|offline|$jarvis_guidance_plan"
  "jarvis-guidance-fixture|scripts/fixtures/jarvis-voice/guidance.json|offline|$jarvis_guidance_plan"
  "jarvis-speakable-suite|scripts/test-jarvis-speakable.js|offline|$jarvis_speakable_plan"
  "jarvis-speakable-fixture|scripts/fixtures/jarvis-voice/speakable.json|offline|$jarvis_speakable_plan"
  "jarvis-language-suite|scripts/test-jarvis-speech-language.js|offline|node scripts/test-jarvis-speech-language.js"$'\n'"$repo_plan"
  "jarvis-voice-assertions|scripts/fixtures/jarvis-voice/assertions.js|offline|node scripts/test-jarvis-sse.js"$'\nnode scripts/test-jarvis-providers.js\n'"${jarvis_language_plan%$repo_plan}"$'node scripts/test-schema-check.js\n'"$repo_plan"
  "jarvis-voice-installed|scripts/fixtures/jarvis-voice/installed.js|all|$install_plan"$'\nscripts/qml-smoke.sh'
  "dispatch|shell/Core/Dispatch.js|offline|$dispatch_plan"
  "session|shell/Core/SessionLock.qml|all|$session_plan"
  "fixture|scripts/smoke/fixtures/plugins/acme.contention/Background.qml|all|$fixture_plan"
  "smoke-row|scripts/smoke/rows/example.sh|all|$smoke_plan"
  "capture-worker-suite|scripts/test-capture.py|cli|python3 scripts/test-capture.py"
  "jarvis-key-smoke|scripts/smoke/rows/jarvis-keys.sh|all|node scripts/test-jarvis-daemon.js"$'\n'"$smoke_plan"
  "compositor-reveal-barrier-suite|scripts/test-compositor-reveal.py|tools|python3 scripts/test-compositor-reveal.py"
  "jarvis-poll-harness|scripts/smoke/harness.sh|all|node scripts/test-jarvis-daemon.js"$'\npython3 scripts/check-smoke-readers.py\npython3 scripts/test-check-smoke-readers.py\npython3 scripts/test-compositor-reveal.py\nsmoke_reads_named\nscripts/test-smoke-teardown.sh\nscripts/test-sandbox-shots.sh\nscripts/test-gpu-fence.sh\nnode scripts/test-jarvis-env.js\n'"$repo_plan"$'\nscripts/qml-smoke.sh\nscripts/measure-shader.sh'
  "shortcut-provider|shell/Core/ShortcutRegistry.qml|unit|scripts/test-keyboard-ui.sh"$'\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh'
  "key-capture-owner|shell/Core/KeyCapture.qml|unit|scripts/test-keyboard-ui.sh"$'\nscripts/qml-unit.sh\nscripts/test-qml-unit.sh'
  "settings-edit-set|shell/plugins/vgs.settings/EditSet.qml|unit|scripts/qml-unit.sh"$'\nscripts/test-qml-unit.sh'
  "harness-render|.agents/skills/review-gate/scripts/review-policy|all|$repo_plan"
  "harness-hook|.claude/hooks/example.sh|all|$repo_plan"
  "harness-settings|kendex.local.toml|all|$repo_plan"
  "workflow|.github/workflows/example.yml|all|$repo_plan"
)
plan_consumer_case() { # SPEC
  local spec="$1" name rest file area wanted d state status out err
  name="${spec%%|*}"; rest="${spec#*|}"
  file="${rest%%|*}"; rest="${rest#*|}"
  area="${rest%%|*}"; wanted="${rest#*|}"
  d="$tmp/plan-$name"; fresh "$d"
  mkdir -p -- "$d/$(dirname -- "$file")"
  printf 'changed\n' >"$d/$file"
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
parallel_cases plan_consumer_case plan-case "${cases[@]}"

d="$tmp/plan-rename"; fresh "$d"
mkdir -p "$d/shell/Core"
printf 'source\n' >"$d/shell/Core/Dispatch.js"
"${base_env[@]}" git -C "$d" add shell/Core/Dispatch.js
"${base_env[@]}" git -C "$d" commit -q -m source
"${base_env[@]}" git -C "$d" mv shell/Core/Dispatch.js README.md
# The removed path's consumers, and README.md's: the install tree and the
# README check, and the ceiling row, since README.md is a document.
rename_plan=$'node scripts/test-input-facts.js\nnode scripts/test-dispatch.js\nnode scripts/test-jarvis-desktop.js\nnode scripts/test-jarvis-files.js\nnode scripts/test-jarvis-browser.js\nnode scripts/test-jarvis-desktop-tools.js\nnode scripts/test-jarvis-vision.js\npython3 scripts/test-capture.py\nnode scripts/test-jarvis-daemon.js\nnode scripts/test-jarvis-audio-daemon.js\nscripts/test-install-tree.sh\n'"$readme_rows"$'python3 scripts/check-plugin-boundary.py\npython3 scripts/check-design-tokens.py\npython3 scripts/check-pointer-cursor.py\npython3 scripts/test-check-pointer-cursor.py\npython3 scripts/check-user-commands.py\n'"$keyboard_check$repo_plan"
if out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate offline --changed HEAD --list 2>"$tmp/plan.err")" && [[ $out == "$rename_plan"$'\ndoc_limits_check' ]]; then ok "a rename selects consumers of the removed source path"; else fail "rename omitted the old path's consumers: $out"; fi

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
needle = '        if [[ $path == scripts/test-* && ! -e $path && ! -L $path ]]; then continue; fi\n'
assert s.count(needle) == 1, "deleted test exemption must match once"
p.write_text(s.replace(needle, needle.replace('continue;', ':;')))
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
# and twice leaves a heredoc open. Variants: no-harness-line
# carries no harness line, no-list has an empty row list and no-core one
# that does not list auth-sentinel. Expected row sets are
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
    'launcher_part=$launcher_dir/part launcher_mode=open' 'sandbox=/elsewhere failures=1' >"$dir/scripts/smoke/rows/launcher.sh"
  printf '%s\n' '# inputs: shell/plugins/acme.notify/* scripts/smoke/rows/notifications-keys.sh' 'notify_open() { :; }' >"$dir/scripts/smoke/rows/notifications.sh"
  printf '%s\n' '# inputs: shell/Core/Keys.qml scripts/smoke/rows/notifications.sh' 'notify_open' >"$dir/scripts/smoke/rows/notifications-keys.sh"
  printf '%s\n' '# inputs: shell/plugins/acme.other/*' 'expect "the launcher opens" "" launcher_open' 'launcher_close' 'launcher_mode=other' \
    'ls -- "$launcher_dir" "$sandbox" "$launcher_mode" "$failures"' 'smoke_row other-part' >"$dir/scripts/smoke/rows/other.sh"
  printf '%s\n' '# Run by other.sh.' 'ls -- "$launcher_part"' >"$dir/scripts/smoke/rows/other-part.sh"
  printf '# A row with no input line.\nset -euo pipefail\n# inputs: shell/plugins/acme.other/*\n' >"$dir/scripts/smoke/rows/bare.sh"
  printf '# inputs: shell/plugins/acme.gone/*\n' >"$dir/scripts/smoke/rows/stale.sh"
  printf '# inputs: shell/plugins/acme.other/*\n# inputs: shell/Core/Keys.qml\ncat <<EOF\nnever closed\n' >"$dir/scripts/smoke/rows/twice.sh"
  printf '# inputs:\n' >"$dir/scripts/smoke/rows/blank.sh"
  case "$variant" in
    slow|slow-malformed)
      printf '%s\n' '# Measured seconds.' 'bar 99' 'launcher 61' 'notifications 90' 'notifications-keys 10' 'other 60' >"$dir/scripts/smoke/rows.secs"
      sed -i '1s|$| scripts/smoke/rows/launcher-part.sh|' "$dir/scripts/smoke/rows/launcher.sh"
      printf '# Run by launcher.sh.\n' >"$dir/scripts/smoke/rows/launcher-part.sh" ;;&
    slow-malformed) printf 'stale sixty\n' >>"$dir/scripts/smoke/rows.secs" ;;
  esac
  if [[ $variant == vpn-values || $variant == vpn-values-control ]]; then
    python3 - "$repo" "$dir" "$variant" <<'PYVPNINPUT'
import glob, pathlib, re, sys
repo, target = map(pathlib.Path, sys.argv[1:3])
variant = sys.argv[3]
source = (repo / 'scripts/smoke/rows/vpn.sh').read_text()
lines = re.findall(r'^# inputs: (.+)$', source, re.M)
assert len(lines) == 1
inputs = lines[0]
for pattern in inputs.split():
    for original in glob.glob(str(repo / pattern)):
        original = pathlib.Path(original)
        if original.is_file():
            path = target / original.relative_to(repo)
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('# neutral input\n')
if variant == 'vpn-values-control':
    edge = 'shell/Commons/SettingValues.js '
    assert inputs.count(edge) == 1
    inputs = inputs.replace(edge, '')
(target / 'scripts/smoke/rows/vpn.sh').write_text('# inputs: ' + inputs + '\n')
(target / 'scripts/smoke/rows/device-fakes.sh').write_text('# inputs: scripts/smoke/fixtures/devices/*\n')
row_list = target / 'scripts/smoke/rows.list'
text = row_list.read_text()
assert text.count('start-order\n') == 1
row_list.write_text(text.replace('start-order\n', 'device-fakes\nvpn\nstart-order\n'))
PYVPNINPUT
  fi
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m smoke-rows
}
smoke_always='bare,stale,twice,blank,lost'
smoke_core='bar,hyprland-consent,session'
smoke_tail='start-order,auth-sentinel'
smoke_launcher="scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_always,$smoke_tail"
smoke_notify="scripts/qml-smoke.sh --rows $smoke_core,notifications,notifications-keys,$smoke_always,$smoke_tail"
smoke_none="scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,$smoke_tail"
# name|changed paths|scope|wanted plan|mutant|fixture variant
smoke_cases=(
  "the shared byte counter selects its VPN runtime consumer|shell/Commons/SettingValues.js|changed|scripts/qml-smoke.sh --rows $smoke_core,$smoke_always,device-fakes,vpn,$smoke_tail||vpn-values"
  "control: losing the VPN byte counter input skips its runtime consumer|shell/Commons/SettingValues.js|changed|$smoke_none||vpn-values-control"
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
  "a runner that does not list a core row runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh||no-core"
  "control: a runner that does not list a core row no longer runs every row|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_always,start-order|core-missing|no-core"
  "an unknown input runs every row|shell/plugins/acme.launcher/Panel.qml new-source.bin|changed|scripts/qml-smoke.sh||rows"
  "control: an unknown input no longer runs every row|shell/plugins/acme.launcher/Panel.qml new-source.bin|changed|$smoke_launcher|unknown|rows"
  "--full runs every row|shell/plugins/acme.launcher/Panel.qml|full|scripts/qml-smoke.sh||rows"
  "control: --full no longer runs every row|shell/plugins/acme.launcher/Panel.qml|full|$smoke_none|full|rows"
  "a row over the bound leaves a diff-scoped selection|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_none||slow"
  "control: a row over the bound no longer leaves|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher|bound|slow"
  "a row at the bound stays|shell/plugins/acme.other/Panel.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,other,$smoke_always,$smoke_tail||slow"
  "control: a row at the bound leaves|shell/plugins/acme.other/Panel.qml|changed|$smoke_none|at-bound|slow"
  "control: a core row over the bound leaves|shell/plugins/acme.launcher/Panel.qml|changed|scripts/qml-smoke.sh --rows hyprland-consent,session,$smoke_always,$smoke_tail|core-bound|slow"
  "a row over the bound whose own file changed stays|scripts/smoke/rows/launcher.sh|changed|$smoke_launcher||slow"
  "control: a row over the bound whose own file changed leaves|scripts/smoke/rows/launcher.sh|changed|$smoke_none|own|slow"
  "a row over the bound a changed row file it names reads stays|scripts/smoke/rows/launcher-part.sh|changed|$smoke_launcher||slow"
  "control: a row over the bound a changed row file it names reads leaves|scripts/smoke/rows/launcher-part.sh|changed|$smoke_none|input-row|slow"
  "a row over the bound that a selected row reads stays|shell/plugins/acme.notify/Panel.qml shell/Core/Keys.qml|changed|$smoke_notify||slow"
  "control: a row over the bound that a selected row reads leaves|shell/plugins/acme.notify/Panel.qml shell/Core/Keys.qml|changed|scripts/qml-smoke.sh --rows $smoke_core,notifications-keys,$smoke_always,$smoke_tail|read-back|slow"
  "a malformed seconds file leaves every row in|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_launcher||slow-malformed"
  "control: a malformed seconds file still narrows|shell/plugins/acme.launcher/Panel.qml|changed|$smoke_none|malformed|slow-malformed"
  "--full runs a row over the bound|shell/plugins/acme.launcher/Panel.qml|full|scripts/qml-smoke.sh||slow"
  "control: --full no longer runs a row over the bound|shell/plugins/acme.launcher/Panel.qml|full|$smoke_none|full|slow"
)
# Each mutant: the text it replaces in validate, then its replacement.
declare -A smoke_mutant_old=(
  [missing]=$'"$key" "$file" >&2; return 1\n  fi\n  if [[ $count -gt 1 ]]'
  [lines]=$'"$key" "$count" "$file" >&2; return 1'
  [empty]=$'empty; fix the line in %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 1'
  [unreadable]=$'unreadable path=%s\\n\' "$key" "$file" >&2; return 1'
  [matches-nothing]='      smoke_glob_unmatched=true'
  [path]=$'        [[ $path == $glob ]] || continue\n        want[$row]=1'
  [core]=$'      printf \'validate: smoke-rows=all reason=core-row-missing row=%s\\n\' "$row" >&2; return 0\n    fi\n    want[$row]=1\n  done'
  [core-missing]=$'reason=core-row-missing row=%s\\n\' "$row" >&2; return 0'
  [closure]='do want[$needed]=1; done'
  [harness]='for glob in scripts/qml-smoke.sh scripts/smoke/harness.sh "${smoke_globs[@]}"; do'
  [library]='for glob in scripts/qml-smoke.sh scripts/smoke/harness.sh "${smoke_globs[@]}"; do'
  [runner]='for glob in scripts/qml-smoke.sh scripts/smoke/harness.sh "${smoke_globs[@]}"; do'
  [harness-line]="    every='reason=harness-line-unreadable'"
  [unknown]=$'      export VGS_VALIDATE_CHANGED="$paths_file"\n      smoke_scoped=true\n    fi'
  [full]=$'smoke_scoped=false\naffected=()'
  [bound]='      over+=("$row")'
  [at-bound]='$secs -gt $smoke_bound_secs'
  [core-bound]='      [[ " ${smoke_core[*]} " != *" $row "* ]] || continue'
  [own]='      [[ -z ${edited[$row]-} ]] || continue'
  [input-row]='if [[ $path == scripts/smoke/rows/* ]]; then edited[$row]=1; break 2; fi'
  [moved]=$'    want[$line]=1\n    edited[$line]=1'
  [read-back]='      for needed in ${reads[$row]-}; do want[$needed]=1; done'
  [malformed]='"$number" "$file" >&2; return 1'
)
declare -A smoke_mutant_new=(
  [missing]=$'"$key" "$file" >&2; return 0\n  fi\n  if [[ $count -gt 1 ]]'
  [lines]=$'"$key" "$count" "$file" >&2; return 0'
  [empty]=$'empty; fix the line in %s: # inputs: GLOB [GLOB...]\\n\' "$key" "$file" >&2; return 0'
  [unreadable]=$'unreadable path=%s\\n\' "$key" "$file" >&2; return 0'
  [matches-nothing]='      :'
  [path]='        [[ $path == $glob ]] || continue'
  [core]=$'      printf \'validate: smoke-rows=all reason=core-row-missing row=%s\\n\' "$row" >&2; return 0\n    fi\n  done'
  [core-missing]=$'reason=core-row-missing row=%s\\n\' "$row" >&2'
  [closure]='do :; done'
  [harness]='for glob in scripts/qml-smoke.sh "${smoke_globs[@]}"; do'
  [library]='for glob in scripts/qml-smoke.sh scripts/smoke/harness.sh; do'
  [runner]='for glob in scripts/smoke/harness.sh "${smoke_globs[@]}"; do'
  [harness-line]='    :'
  [unknown]=$'      export VGS_VALIDATE_CHANGED="$paths_file"\n    fi\n    smoke_scoped=true'
  [full]=$'smoke_scoped=true\naffected=()'
  [bound]='      :'
  [at-bound]='$secs -ge $smoke_bound_secs'
  [core-bound]='      :'
  [own]='      :'
  [input-row]='if [[ $path == "$file" ]]; then edited[$row]=1; break 2; fi'
  [moved]='    want[$line]=1'
  [read-back]='      for needed in ${reads[$row]-}; do [[ " ${over[*]} " == *" $needed "* ]] || want[$needed]=1; done'
  [malformed]='"$number" "$file" >&2; continue'
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
  for file in $files; do printf '# changed\n' >>"$d/$file"; done
  scope_args=(--changed HEAD)
  [[ $scope == changed ]] || scope_args=(--full)
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml "${scope_args[@]}" --list 2>"$tmp/smoke-rows.err")" || status=$?
  plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
  if [[ $status == 0 && $plan == "$wanted" ]]; then ok "$name"; else fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-rows.err"; fi
done
# The lines a row over the bound leaves: one per row and the count in the
# summary, which the lanes and the overseer read.
test_area=qml
test_args=(--changed HEAD --list)
d="$tmp/smoke-rows-skip-lines"; smoke_fixture "$d" slow
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
row "a row over the bound is named as skipped" "$d" 0 "" \
  "validate: smoke-row skipped=over-bound row=launcher secs=61 bound=60" \
  "validate: smoke-rows=some selected=10 total=14 skipped=1" '!skipped=over-bound row=bar' '!skipped=over-bound row=other'
# A moved row over the bound runs: its row list line is an edit of it.
for mutant in "" moved; do
  d="$tmp/smoke-rows-moved-${mutant:-real}"; smoke_fixture "$d" slow
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
  sed -i -e '/^launcher$/d' -e 's/^other$/other\nlauncher/' "$d/scripts/smoke/rows.list"
  wanted="scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_always,$smoke_tail"
  name="a moved row over the bound stays"
  [[ -z $mutant ]] || { wanted="$smoke_none"; name="control: a moved row over the bound leaves"; }
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml --changed HEAD --list 2>"$tmp/smoke-moved.err")" || status=$?
  plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
  if [[ $status == 0 && $plan == "$wanted" ]]; then ok "$name"; else fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-moved.err"; fi
done
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
  "control: a rebased base no longer narrows~lane~$smoke_both~  [[ \$status -eq 1 ]] || return 0~  return 0"
  "a base HEAD holds selects every path since~old-main~$smoke_both~~"
  "control: a base HEAD holds narrows too~old-main~$smoke_launcher~  [[ \$status -eq 1 ]] || return 0~  :"
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
old = "echo 'validate: smoke-rows=all reason=row-list-unreadable' >&2; return 0"
source = path.read_text()
assert source.count(old) == 1, old
path.write_text(source.replace(old, "echo 'validate: smoke-rows=all reason=row-list-unreadable' >&2"))
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
  "validate: smoke-input row=other variable=launcher_dir from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input row=other variable=launcher_part from=scripts/smoke/rows/launcher.sh; add to the line in scripts/smoke/rows/other.sh: # inputs: shell/plugins/acme.other/* scripts/smoke/rows/launcher.sh"
  "validate: smoke-input unparsed path=scripts/smoke/rows/twice.sh; the function and variable check cannot read it to its end"
)
row "the smoke input self-check names each line to add or fix" "$d" 0 "" \
  "${smoke_self_check[@]}" '!row=launcher' '!row=session' '!row=notifications-keys' '!variable=sandbox' '!variable=failures' '!variable=launcher_mode'
test_args=(--changed HEAD)
row "the smoke input self-check leaves a real run passing" "$d" 0 "" \
  "${smoke_self_check[@]}" "validate: ok"
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
  python3 - "$d/scripts/validate" "$old" "$new" <<'PY'
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
  "control: a moved row no longer runs~move~$smoke_none~"'    if [[ -z $every && $path == "$smoke_list" ]]; then smoke_list_rows; fi'"~    :"
  "a comment in the row list runs no row~comment~$smoke_none~~"
  "control: a comment in the row list no longer reads as one~comment~scripts/qml-smoke.sh~"'    [[ -z $line || $line == '"'#'"'* ]] && continue'"~    :"
  "an unlisted row runs the rows that read it~unlist~scripts/qml-smoke.sh --rows $smoke_core,notifications-keys,$smoke_always,$smoke_tail~~"
  "control: an unlisted row no longer runs the rows that read it~unlist~$smoke_none~"'      [[ " ${lines[$row]-} " != *" scripts/smoke/rows/$needed.sh "* ]] || want[$row]=1'"~      :"
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

# A selector change after the pass: docs/selector.txt changes before the
# logic pass, which selects no row for it, and a later commit maps it to the
# plugin status judge row. The run reads the whole branch again and runs
# that row. The control drops the selector check and takes the pass as its
# base, which skips the row.
for variant in real control; do
  d="$tmp/base-selector-$variant"; fresh "$d"
  [[ $variant == real ]] || plant "$d/scripts/validate" '  git diff --quiet "$commit" -- scripts/validate || status=$?' '  status=0'
  mkdir -p "$d/docs"; printf 'selector\n' >"$d/docs/selector.txt"
  commit "$d" path
  test_area=logic test_args=()
  row_re "the $variant selector fixture's logic pass records its tree" "$d" 0 "" \
    "~validate: selected=0 area=logic" "validate: last-pass=recorded area=logic tree=$("${base_env[@]}" git -C "$d" rev-parse 'HEAD^{tree}')"
  plant "$d/scripts/validate" '"logic|plugin status judge|node scripts/test-plugin-status.js|' '"logic|plugin status judge|node scripts/test-plugin-status.js|docs/selector.txt '
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
# in run order; and it refuses a row it does not hold. The control is a
# copy whose row predicate holds every row.
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
smoke_subset=$'bar\nsession\nstart-order'
if out="$("${base_env[@]}" "$repo/scripts/qml-smoke.sh" --rows start-order,bar,session --list-rows)" && [[ $out == "$smoke_subset" ]]; then
  ok "the runner lists only the rows --rows names, in run order"
else
  fail "the runner's --rows listing: $out"
fi
mkdir -p "$tmp/runner-control/scripts/smoke"
cp -- "$repo/scripts/smoke/rows.list" "$tmp/runner-control/scripts/smoke/rows.list"
python3 - "$repo/scripts/qml-smoke.sh" "$tmp/runner-control/scripts/qml-smoke.sh" <<'PY'
from pathlib import Path
import sys
source, target = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
old = 'qml_smoke_wanted() { [[ -z $qml_smoke_only || $qml_smoke_only == *",$1,"* ]]; }'
assert source.count(old) == 1, old
target.write_text(source.replace(old, 'qml_smoke_wanted() { true; }'))
PY
if out="$("${base_env[@]}" bash "$tmp/runner-control/scripts/qml-smoke.sh" --rows start-order,bar,session --list-rows)" && [[ $out == "$listed" && $out != "$smoke_subset" ]]; then
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

d="$tmp/plan-selector"; fresh "$d"
printf '\n' >>"$d/scripts/validate"
# The smoke reader rule reads the core row list from scripts/validate.
selector_plan=$'python3 scripts/check-smoke-readers.py\npython3 scripts/test-check-smoke-readers.py\n'"$repo_plan"$'\nscripts/test-validate.sh'
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

# Every row runs with its own temporary home. The planted row runs
# `git config --global` under a scratch HOME, as an installer test does, and
# under its own HOME, and writes under XDG_CONFIG_HOME and, given `home`,
# HOME, where the scratch HOME's setting must land in that HOME's .gitconfig.
# The caller keeps its git configuration in its XDG_CONFIG_HOME and sets no
# GIT_CONFIG_GLOBAL, as a developer's shell does, or, in the last case,
# exports one naming a file of its own. The caller's files stay unchanged,
# the row's home is gone after it, and a nix row keeps the caller's HOME. A
# copy without each isolation line lets the row write the caller's files.
caller="$tmp/row-home-caller"
mkdir -p "$caller/.config/git" "$caller/.local/share" "$caller/.local/state" "$caller/.cache"
printf '[user]\n\tname = caller\n' >"$caller/.config/git/config"
cp -a -- "$caller" "$tmp/row-home-before"
home_fixture() { # DIR: a fixture holding the planted row in tools and nix
  fresh "$1"
  cat >"$1/scripts/test-home.sh" <<'SH'
#!/bin/sh
set -e
printf 'row-home=%s row-config=%s\n' "$HOME" "$XDG_CONFIG_HOME"
scratch="tmp/home-row-$$"
rm -rf -- "$scratch"
mkdir -p -- "$scratch"
HOME="$scratch" git config --global url.file:///nowhere/vgs.git.insteadOf https://example.invalid/vgs.git
if [ "${1-}" = home ]; then [ -f "$scratch/.gitconfig" ]; fi
rm -rf -- "${scratch:?}"
git config --global vgs.row planted
mkdir -p "$XDG_CONFIG_HOME/row"
printf 'planted\n' >"$XDG_CONFIG_HOME/row/file"
if [ "${1-}" = home ]; then printf 'planted\n' >"$HOME/.row"; fi
SH
  chmod +x "$1/scripts/test-home.sh"
  python3 - "$1/scripts/validate" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
assert source.count('rows=(\n') == 1
path.write_text(source.replace('rows=(\n', 'rows=(\n  "tools|row home|scripts/test-home.sh home|"\n  "nix|row home in nix|scripts/test-home.sh|"\n'))
PY
  "${base_env[@]}" git -C "$1" commit -q -am home-row
}
# home_run DIR AREA [GLOBAL]: run `scripts/validate AREA --changed HEAD` in
# DIR as the caller, from a fresh copy of the caller's files, with
# GIT_CONFIG_GLOBAL set to the caller's own GLOBAL file when given; sets out
# and status.
home_run() {
  rm -rf -- "${caller:?}"
  cp -a -- "$tmp/row-home-before" "$caller"
  status=0
  out="$(cd -- "$1" && "${base_env[@]}" HOME="$caller" XDG_CONFIG_HOME="$caller/.config" \
    XDG_DATA_HOME="$caller/.local/share" XDG_STATE_HOME="$caller/.local/state" XDG_CACHE_HOME="$caller/.cache" \
    bash -c 'if [ -n "$2" ]; then export GIT_CONFIG_GLOBAL="$2"; else unset GIT_CONFIG_GLOBAL; fi
      exec bash scripts/validate "$1" --changed HEAD' validate "$2" "${3:+$caller/$3}" 2>&1)" || status=$?
}
d="$tmp/row-home"; home_fixture "$d"
for spec in tools@ nix@ tools@explicit-gitconfig; do
  IFS='@' read -r area global <<<"$spec"
  home_run "$d" "$area" "$global"
  row_home="" row_config=""
  read -r row_home row_config < <(sed -n 's/^row-home=\([^ ]*\) row-config=\(.*\)$/\1 \2/p' <<<"$out") || true
  if [[ $area == nix ]]; then want_home="$caller"; else want_home="$row_home"; fi
  if [[ $status == 0 ]] && grep -qxF 'validate: ok' <<<"$out" &&
     diff -r -- "$tmp/row-home-before" "$caller" >/dev/null &&
     [[ -n $row_config && $row_config != "$caller"* && ! -e $row_config && $row_home == "$want_home" ]] &&
     { [[ $area == nix ]] || [[ $row_home != "$caller" && ! -e $row_home ]]; }; then
    ok "a $area row's git and configuration writes leave the caller's files unchanged${global:+ with GIT_CONFIG_GLOBAL set}"
  else
    fail "$spec row home: status=$status home=$row_home config=$row_config"
    diff -r -- "$tmp/row-home-before" "$caller" | sed 's/^/        /' || true
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
done
# Each mutant replaces one whole isolation line of the copy with the same
# line less its isolation, and runs the planted row in the area named, as a
# caller with the GIT_CONFIG_GLOBAL file named, if any.
mutants=(
  'configuration@tools@@    export XDG_CONFIG_HOME="$row_home/.config"@    :'
  'git@nix@@      package|nix) export GIT_CONFIG_GLOBAL="$row_home/gitconfig" ;;@      package|nix) ;;'
  'home@tools@@        export HOME="$row_home" XDG_DATA_HOME="$row_home/.local/share" XDG_STATE_HOME="$row_home/.local/state" XDG_CACHE_HOME="$row_home/.cache" ;;@        ;;'
  'caller git file@tools@explicit-gitconfig@        unset GIT_CONFIG_GLOBAL@        :'
)
for i in "${!mutants[@]}"; do
  IFS='@' read -r name area global line replacement <<<"${mutants[i]}"
  d="$tmp/row-home-mutant-$i"; home_fixture "$d"
  python3 - "$d/scripts/validate" "$line" "$replacement" <<'PY'
from pathlib import Path
import sys
path, line, replacement = Path(sys.argv[1]), sys.argv[2] + '\n', sys.argv[3]
source = path.read_text()
assert source.count(line) == 1, line
path.write_text(source.replace(line, replacement + '\n'))
PY
  "${base_env[@]}" git -C "$d" commit -q -am control
  home_run "$d" "$area" "$global"
  if diff -r -- "$tmp/row-home-before" "$caller" >/dev/null; then
    fail "a validate without the $name isolation still left the caller's files unchanged"
    printf '%s\n' "$out" | sed 's/^/        /'
  else
    ok "a validate without the $name isolation lets the row write the caller's files"
  fi
done

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
row = '  "tools|changed list echo|scripts/changed-list.sh|changed.txt"'
source, count = re.subn(r'rows=\(\n.*?\n\)\n', 'rows=(\n' + row + '\n)\n', source, count=1, flags=re.S)
assert count == 1
path.write_text(source)
PY
"${base_env[@]}" git -C "$d" add -A
"${base_env[@]}" git -C "$d" commit -q -m changed-list-row
printf 'changed\n' >"$d/changed.txt"
test_area=tools
test_args=(--changed HEAD)
row_re "a diff-scoped run exports the changed path list to rows" "$d" 0 "" \
  "~changed-env=" "changed-path=changed.txt" "~validate: secs=" "validate: ok"
test_args=(--full)
row "a full run unsets the changed path list inherited from the caller" "$d" 0 "VGS_VALIDATE_CHANGED=/x" \
  "changed-env=unset" "!changed-path=changed.txt" "validate: ok"
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
row "live references pass" "$d" 0 "" \
  "md-refs: summary=violations=0 references=2 markdown=1 sources=1 decisions=0:docs/decisions skipped=0"
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
