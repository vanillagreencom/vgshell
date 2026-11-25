#!/usr/bin/env bash
# Controls for scripts/validate. Each case runs a copy of the script in a
# scratch repository, a base branch `trunk` with its remote-tracking ref and
# a feature branch on top, and asserts the exit status and the keyed lines
# the script's header promises: the nightly input hash, the branch point,
# change selection of table rows and nested smoke rows, row record reuse
# across a stopped run and a restack, the nested smoke runner's --rows
# expansion, --skip-unprepared, scratch paths, the row weight bound, the
# stop's deadline and the reap of a killed run's scratch.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
tmp="$(mktemp -d "$TMPDIR/test-validate.XXXXXX")" || exit 1
trap 'rm -rf -- "${tmp:?}"' EXIT

# Every git and validate call runs with this environment and nothing else.
# Fixed identities and dates make every fixture's trunk the same commit.
# Resolve node before replacing HOME: a version-manager shim may need the
# developer's configuration, which does not belong in the test environment.
node_bin="$(node -e 'process.stdout.write(process.execPath)')"
mkdir -p "$tmp/home/.config" "$tmp/home/.cache" "$tmp/home/.local/share" "$tmp/home/.local/state" "$tmp/runtime"
chmod 700 "$tmp/runtime"
base_env=(env -i PATH="$(dirname -- "$node_bin"):$PATH" HOME="$tmp/home" LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
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

# A fresh scratch repository at $1: trunk holds the script and what it
# sources or runs on every run: the settings loader, the core row list,
# the scratch reaper, the harness's leading comment block with its
# `loads:` directives, the md-refs checker with
# the document validate cites and an exclusion list that keeps these
# borrowed files' own references out of scope, the load reading with the
# readers it imports, a settings file naming trunk as the base branch, and
# a file under shell/ and config/, roots the monitor rule check refuses
# when they list none; refs/remotes/origin/trunk points at it; HEAD is a feature branch on top.
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
  mkdir -p "$dir/scripts/smoke" "$dir/.agents/skills/orch/scripts/lib" "$dir/.agents/skills/commit-guards" "$dir/tools" "$dir/docs/architecture" "$dir/bin/lib"
  cp -- "$repo/scripts/validate" "$dir/scripts/validate"
  cp -- "$repo/docs/architecture/validation.md" "$dir/docs/architecture/validation.md"
  cp -- "$repo/scripts/smoke/row-inputs.sh" "$repo/scripts/smoke/reap.sh" "$dir/scripts/smoke/"
  awk '!/^#/ { exit } { print }' "$repo/scripts/smoke/harness.sh" >"$dir/scripts/smoke/harness.sh"
  # Rows run through a transparent world stand-in, and the installed-engine
  # check before the nested smoke row passes.
  printf '#!/bin/sh\nwhile [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' >"$dir/scripts/smoke/gpu-fence.sh"
  chmod +x "$dir/scripts/smoke/gpu-fence.sh"
  printf 'console.log(JSON.stringify({status: "pass"}));\n' >"$dir/scripts/check-packaging.js"
  cp -- "$repo/.agents/skills/orch/scripts/lib/kendex-env.sh" "$dir/.agents/skills/orch/scripts/lib/kendex-env.sh"
  cp -R -- "$repo/.agents/skills/commit-guards/scripts" "$dir/.agents/skills/commit-guards/"
  printf '# kendex-guard-dialect: legacy-glob\n.agents/*\tcopies of checkers, whose citations name their own repository\n' >"$dir/tools/md-excludes"
  printf 'docs/architecture/validation.md\tborrowed citation target, whose links name the full repository\n' >>"$dir/tools/md-excludes"
  cp -- "$repo/scripts/row_loads.py" "$repo/scripts/qml_controls.py" "$repo/scripts/qml_source.py" "$repo/scripts/shell_source.py" "$repo/scripts/check-smoke-needles.py" "$dir/scripts/"
  cp -- "$repo/bin/vgshell-scan" "$dir/bin/vgshell-scan"
  cp -- "$repo/bin/lib/dbus_wire.py" "$dir/bin/lib/dbus_wire.py"
  printf '%s\tborrowed reader, whose citations name the full repository\n' bin/vgshell-scan bin/lib/dbus_wire.py 'scripts/qml_*.py' >>"$dir/tools/md-excludes"
  printf '[env]\nWORKTREE_DEFAULT_BRANCH = "trunk"\n' >"$dir/kendex.settings.toml"
  # The copied extensionless scripts need the repository's source discovery setting.
  grep '^COMMIT_GUARDS_MD_REFS_SOURCE_PATHS[[:space:]]*=' "$repo/kendex.settings.toml" >>"$dir/kendex.settings.toml"
  mkdir -p "$dir/shell" "$dir/config"
  printf 'clean\n' | tee "$dir/shell/clean.txt" >"$dir/config/clean.txt"
  "${base_env[@]}" git -C "$dir" init -q -b trunk
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m base
  "${base_env[@]}" git -C "$dir" update-ref refs/remotes/origin/trunk HEAD
  "${base_env[@]}" git -C "$dir" checkout -q -b feature
}
template
trunk="$("${base_env[@]}" git -C "$tmp/template" rev-parse refs/remotes/origin/trunk)"

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

# row_re: row, where a LINE written %REGEX asserts that REGEX matches a
# line of the output.
row_re() {
  local name="$1" dir="$2" want_exit="$3" extra="$4" out status=0 line missing="" present=""
  shift 4
  # shellcheck disable=SC2086
  out="$(cd -- "$dir" && "${base_env[@]}" $extra bash scripts/validate "${test_area:-repo}" "${test_args[@]}" 2>&1)" || status=$?
  for line in "$@"; do
    if [[ ${line:0:1} == '!' ]]; then
      ! grep -qF -e "${line:1}" <<<"$out" || present+="[${line:1}]"
    elif [[ ${line:0:1} == '%' ]]; then
      grep -qE -e "${line:1}" <<<"$out" || missing+="[${line:1}]"
    else
      grep -qxF -e "$line" <<<"$out" || missing+="[$line]"
    fi
  done
  if [[ $status == "$want_exit" && -z $missing && -z $present ]]; then ok "$name"; else fail "$name: exit=$status want=$want_exit missing=$missing present=$present"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}

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

# Nightly consumes the package input hash across main landings, so an edit
# to another area's row of scripts/validate leaves it unchanged.
d="$tmp/input-hash"; fresh "$d"
mkdir -p "$d/packaging/arch/vgshell"
printf 'recipe\n' >"$d/packaging/arch/vgshell/PKGBUILD"
printf '#!/bin/sh\nexit 99\n' >"$d/scripts/arch-packages.sh"
if before="$(cd -- "$d" && "${base_env[@]}" "$BASH" scripts/validate package --input-hash)" &&
   plant "$d/scripts/validate" 'logic|duration formatter|' 'logic|unrelated duration formatter|' &&
   after="$(cd -- "$d" && "${base_env[@]}" "$BASH" scripts/validate package --input-hash)" &&
   [[ $before =~ ^[a-f0-9]{64}$ && $after == "$before" ]]; then
  ok "input hash ignores unrelated-row"
else
  fail "input hash unrelated-row: before=[${before-}] after=[${after-}]"
fi

# The branch point reads the configured branch without an environment
# override.
d="$tmp/branch-point"; fresh "$d"
sed -n '/^branch_point() {/,/^}/p' "$d/scripts/validate" >"$d/branch-point.sh"
status=0
out="$(cd -- "$d" && "${base_env[@]}" "$BASH" -c 'repo=$PWD; source branch-point.sh; branch_point' 2>&1)" || status=$?
if [[ $status == 0 && $out == "$trunk" ]]; then
  ok "branch point reads the settings branch with no environment override"
else
  fail "branch point: status=$status output=[$out]"
fi

# A plugin README reaches product rows through their real input patterns.
# A mixed change keeps that reach, except through a wildcard input of a qml
# row, which starts the shell.
d="$tmp/readme-scope"; fresh "$d"
mkdir -p "$d/shell/plugins/vgs.keyboard"
cp -- "$repo/shell/plugins/vgs.keyboard/README.md" "$d/shell/plugins/vgs.keyboard/README.md"
commit "$d" readme
printf '\nchanged\n' >>"$d/shell/plugins/vgs.keyboard/README.md"
printf '# mixed change\n' >>"$d/kendex.settings.toml"
test_area=all test_args=(--changed HEAD --list)
row "mixed README selection retains the folder's readers and starts no shell" "$d" 0 "" \
  'scripts/test-keyboard-ui.sh' '!scripts/qml-smoke.sh' '!scripts/test-qml-smoke.sh'

# The runner self-tests run only on a change to what they read: a product
# file selects the nested smoke and neither self-test, and a product smoke
# row's file selects no fatal row control.
d="$tmp/plan-product"; fresh "$d"
mkdir -p "$d/shell/plugins/acme.widget"
printf 'changed\n' >"$d/shell/plugins/acme.widget/Panel.qml"
test_area=all test_args=(--changed HEAD --list)
row "product boot selects nested smoke without runner self-tests" "$d" 0 "" \
  "scripts/qml-smoke.sh" "!scripts/test-qml-smoke.sh" "!scripts/test-validate.sh"
d="$tmp/plan-runner-updates"; fresh "$d"
mkdir -p "$d/scripts/smoke/rows"
printf '# changed\n' >"$d/scripts/smoke/rows/updates.sh"
test_area=qml test_args=(--changed HEAD --list)
row "updates retains only reached runner controls" "$d" 0 "" '!scripts/test-qml-smoke.sh'
test_args=()

# Nested smoke row selection, read through the qml-smoke.sh command a
# `--list` prints. The fixture's runner stands in for scripts/qml-smoke.sh
# and lists the rows of its scripts/smoke/rows.list, skipping comments and
# blank lines: the core rows, launcher, notifications and other, each
# reading its own files; no case changes other's, so a plan that reaches
# every other row still names its rows. Variant loads adds an updates row
# that reads a planted widget drawing a planted BarItem.qml and Badge.qml by
# a planted qs.Ui qmldir; markdown adds a jarvis row whose directive names a planted
# plugin's folder, README included; table-owned adds a vpn row that reads
# scripts/fixtures/vpn/details.txt, which the VPN decisions table row owns
# and the nested smoke table row does not; plugin adds a widget row that
# names the planted plugin acme.widget, whose manifest's entry is Panel.qml,
# beside Other.qml that no entry loads and helper.py, residue, judged by a
# stand-in PluginLogic.js that accepts a manifest unless it holds
# `refused`; loader gives the launcher plugin's Panel.qml a Loader whose
# source is computed.
smoke_fixture() { # DIR [VARIANT]
  local dir="$1" variant="${2-}" row
  fresh "$dir"
  mkdir -p "$dir/scripts/smoke/rows" "$dir/shell/Core" "$dir/shell/plugins/acme.launcher" "$dir/shell/plugins/acme.notify" "$dir/shell/plugins/acme.other"
  printf '%s\n' '# The rows, in run order.' '' bar hyprland-consent launcher notifications other start-order auth-sentinel >"$dir/scripts/smoke/rows.list"
  printf '#!/usr/bin/env bash\nif [[ ${1-} == --list-rows ]]; then awk '"'"'!/^#/ && NF'"'"' "$(dirname -- "$0")/smoke/rows.list"; fi\n' >"$dir/scripts/qml-smoke.sh"
  chmod +x "$dir/scripts/qml-smoke.sh"
  printf '# The harness.\n# loads: scripts/smoke/verdict.sh -- the harness reads its verdict\n' >"$dir/scripts/smoke/harness.sh"
  printf 'failures=0\n' >"$dir/scripts/smoke/verdict.sh"
  for row in Bar Consent Start Auth; do printf 'clean\n' >"$dir/shell/Core/$row.qml"; done
  for row in launcher notify other; do printf 'clean\n' >"$dir/shell/plugins/acme.$row/Panel.qml"; done
  printf '# loads: shell/Core/Bar.qml -- the row reads it\n' >"$dir/scripts/smoke/rows/bar.sh"
  printf '# loads: shell/Core/Consent.qml -- the row reads it\n' >"$dir/scripts/smoke/rows/hyprland-consent.sh"
  printf '# loads: shell/Core/Start.qml -- the row reads it\n' >"$dir/scripts/smoke/rows/start-order.sh"
  printf '# loads: shell/Core/Auth.qml -- the row reads it\n' >"$dir/scripts/smoke/rows/auth-sentinel.sh"
  printf '# loads: shell/plugins/acme.launcher/* -- the row reads it\n' >"$dir/scripts/smoke/rows/launcher.sh"
  printf '# loads: shell/plugins/acme.notify/* -- the row reads it\n' >"$dir/scripts/smoke/rows/notifications.sh"
  printf '# loads: shell/plugins/acme.other/* -- the row reads it\n' >"$dir/scripts/smoke/rows/other.sh"
  if [[ $variant == table-owned ]]; then
    mkdir -p "$dir/scripts/fixtures/vpn"
    printf 'details\n' >"$dir/scripts/fixtures/vpn/details.txt"
    cat >"$dir/scripts/smoke/rows/vpn.sh" <<'ROW'
cat -- "$repo/scripts/fixtures/vpn/details.txt"
ROW
    sed -i 's/^start-order$/vpn\nstart-order/' "$dir/scripts/smoke/rows.list"
  fi
  if [[ $variant == loads ]]; then
    # A planted widget the row reads, which draws a shared BarItem and
    # through it a Badge, each by the qs.Ui qmldir.
    mkdir -p "$dir/shell/plugins/acme.updates" "$dir/shell/Ui/controls" "$dir/shell/Ui/feedback"
    printf 'import qs.Ui\n\nBarItem {}\n' >"$dir/shell/plugins/acme.updates/Widget.qml"
    printf 'module qs.Ui\nBarItem 1.0 controls/BarItem.qml\nBadge 1.0 feedback/Badge.qml\n' >"$dir/shell/Ui/qmldir"
    printf 'import QtQuick\nimport qs.Ui\n\nItem {\n    Badge {}\n}\n' >"$dir/shell/Ui/controls/BarItem.qml"
    printf 'import QtQuick\n\nItem {}\n' >"$dir/shell/Ui/feedback/Badge.qml"
    printf 'cat -- "$repo/shell/plugins/acme.updates/Widget.qml"\n' >"$dir/scripts/smoke/rows/updates.sh"
    sed -i 's/^start-order$/updates\nstart-order/' "$dir/scripts/smoke/rows.list"
  fi
  if [[ $variant == plugin ]]; then
    mkdir -p "$dir/shell/plugins/acme.widget" "$dir/bin/lib"
    printf '{"id": "acme.widget", "entryPoints": {"panel": "Panel.qml"}}\n' >"$dir/shell/plugins/acme.widget/manifest.json"
    printf 'import QtQuick\n\nItem {}\n' | tee "$dir/shell/plugins/acme.widget/Panel.qml" >"$dir/shell/plugins/acme.widget/Other.qml"
    printf 'pass\n' >"$dir/shell/plugins/acme.widget/helper.py"
    printf 'exports.load = file => require(require("path").resolve(file));\n' >"$dir/bin/lib/qml-library.js"
    printf '%s\n' 'exports.CAPABILITIES = [];' 'exports.validateManifest = (manifest, dir) => manifest.refused ? { ok: false, error: "refused" } : { ok: true, manifest };' >"$dir/shell/Core/PluginLogic.js"
    printf 'ipc acme.widget open\n' >"$dir/scripts/smoke/rows/widget.sh"
    sed -i 's/^start-order$/widget\nstart-order/' "$dir/scripts/smoke/rows.list"
  fi
  if [[ $variant == loader ]]; then
    printf 'import QtQuick\n\nLoader {\n    source: view + ".qml"\n}\n' >"$dir/shell/plugins/acme.launcher/Panel.qml"
  fi
  if [[ $variant == markdown ]]; then
    # A planted plugin whose folder the row names, with a README.
    mkdir -p "$dir/shell/plugins/acme.jarvis"
    printf 'clean\n' >"$dir/shell/plugins/acme.jarvis/Service.qml"
    printf '# Jarvis\n' >"$dir/shell/plugins/acme.jarvis/README.md"
    printf '# loads: shell/plugins/acme.jarvis/* -- the row reads its plugin\n' >"$dir/scripts/smoke/rows/jarvis.sh"
    sed -i 's/^start-order$/jarvis\nstart-order/' "$dir/scripts/smoke/rows.list"
  fi
  "${base_env[@]}" git -C "$dir" add -A
  # Rows whose command files read the smoke rows run on a change to them;
  # their stand-ins pass.
  printf 'raise SystemExit(0)\n' | tee "$dir/scripts/test-smoke-dumps.py" >"$dir/scripts/check-smoke-hidden.py"
  "${base_env[@]}" git -C "$dir" add -A
  "${base_env[@]}" git -C "$dir" commit -q -m smoke-rows
}
smoke_core='bar,hyprland-consent'
smoke_tail='start-order,auth-sentinel'
smoke_launcher="scripts/qml-smoke.sh --rows $smoke_core,launcher,$smoke_tail"
smoke_notify="scripts/qml-smoke.sh --rows $smoke_core,notifications,$smoke_tail"
smoke_both="scripts/qml-smoke.sh --rows $smoke_core,launcher,notifications,$smoke_tail"
# name|changed path|wanted plan, empty for no nested smoke|fixture
# variant|a line its stderr must hold, or empty
smoke_cases=(
  "a shared component selects the rows that draw it through another file|shell/Ui/feedback/Badge.qml|scripts/qml-smoke.sh --rows $smoke_core,updates,$smoke_tail|loads|"
  "a plugin README selects no row whose directive names its folder|shell/plugins/acme.jarvis/README.md||markdown|"
  "a path another table row owns selects the smoke rows that read it|scripts/fixtures/vpn/details.txt|scripts/qml-smoke.sh --rows $smoke_core,vpn,$smoke_tail|table-owned|"
  "a plugin's entry selects the row that names its id|shell/plugins/acme.widget/Panel.qml|scripts/qml-smoke.sh --rows $smoke_core,widget,$smoke_tail|plugin|"
  "a plugin's residue selects the row that names its id|shell/plugins/acme.widget/helper.py|scripts/qml-smoke.sh --rows $smoke_core,widget,$smoke_tail|plugin|"
  "a plugin file no entry loads selects no row that names its id|shell/plugins/acme.widget/Other.qml|scripts/qml-smoke.sh --rows $smoke_core,$smoke_tail|plugin|"
  "a computed Loader source leaves the rows that load its file untraced|shell/plugins/acme.other/Panel.qml|scripts/qml-smoke.sh --rows $smoke_core,launcher,other,$smoke_tail|loader|validate: load-unread path=shell/plugins/acme.launcher/Panel.qml line=4 site=loader-source"
)
for i in "${!smoke_cases[@]}"; do
  IFS='|' read -r name file wanted variant line <<<"${smoke_cases[i]}"
  d="$tmp/smoke-rows-$i"; smoke_fixture "$d" "$variant"
  # A comment, so the changed stand-in runner still lists its rows.
  printf '# changed\n' >>"$d/$file"
  # These cases prove ordinary input reach, not the text-only exception,
  # so the change is a mixed one.
  [[ $variant == loads ]] || printf '# mixed change\n' >>"$d/kendex.settings.toml"
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml --changed HEAD --list 2>"$tmp/smoke-rows.err")" || status=$?
  plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
  if [[ $status == 0 && $plan == "$wanted" ]] && { [[ -z $line ]] || grep -qxF -e "$line" "$tmp/smoke-rows.err"; }; then
    ok "$name"
  else
    fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-rows.err"
  fi
done

# The self-check row `validation inputs are read` (smoke_reads_named), run
# as validate runs a row. A malformed directive fails it, in a row's file
# or the harness's, and so does a malformed row directive beside a harness
# load site no directive covers, which runs every row but leaves the rows
# read. A manifest the plugin judge refuses leaves the load reading
# unfinished: exit 77, not a pass.
# name|fixture variant|harness site, `site` to plant one|file to plant
# in|line to append|wanted exit|wanted line
reads_cases=(
  "the self-check passes the neutral fixture|||||0|"
  "a malformed harness directive fails the self-check|||scripts/smoke/harness.sh|# loads: scripts/smoke/verdict.sh|1|validate: smoke-input malformed path=scripts/smoke/harness.sh line=3; fix the directive: loads: GLOB [GLOB...] -- REASON"
  "a malformed row directive beside a harness site fails the self-check||site|scripts/smoke/rows/other.sh|# loads: shell/plugins/acme.other/Panel.qml|1|validate: smoke-input malformed path=scripts/smoke/rows/other.sh line=2; fix the directive: loads: GLOB [GLOB...] -- REASON"
  "a refused manifest leaves the self-check unfinished|plugin||shell/plugins/acme.widget/manifest.json|{\"refused\": true}|77|"
)
for i in "${!reads_cases[@]}"; do
  IFS='|' read -r name variant site file text wanted line <<<"${reads_cases[i]}"
  d="$tmp/smoke-reads-$i"; smoke_fixture "$d" "$variant"
  if [[ $site == site ]]; then
    printf '%s\n' 'harness_dir="$repo/scripts/smoke"' 'harness_name="$(harness_pick)"' 'python3 "$harness_dir/$harness_name.py"' >>"$d/scripts/smoke/harness.sh"
  fi
  if [[ $file == */manifest.json ]]; then printf '%s\n' "$text" >"$d/$file"; elif [[ -n $file ]]; then printf '%s\n' "$text" >>"$d/$file"; fi
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate --row HEAD -1 -- smoke_reads_named 2>&1)" || status=$?
  if [[ $status == "$wanted" ]] && { [[ -z $line ]] || grep -qxF -e "$line" <<<"$out"; } &&
     { [[ $wanted != 77 ]] || grep -q '^smoke-reads: reading=unfinished reason=qml-loads-failed operation=manifest-judge ' <<<"$out"; }; then
    ok "$name"
  else
    fail "$name: exit=$status want=$wanted"; sed 's/^/        /' <<<"$out"
  fi
done

# A load the reading cannot read selects its row. The dyn row runs the
# stand-in its dyn_pick names, a computed path under scripts/fixtures/vpn/,
# which the VPN decisions row owns and the nested smoke row's inputs do not
# hold. Unread, the row's reach cannot be traced: the nested smoke runs it
# on a change no row's inputs hold and names the site. Covered by a
# directive, the row is traced: a change to a stand-in selects it, and one
# to another file of the folder selects no nested smoke.
# name|directive|changed path|wanted plan|wanted line
dyn_cases=(
  "a load the reading cannot read selects its row||scripts/fixtures/vpn/b.py|scripts/qml-smoke.sh --rows $smoke_core,dyn,$smoke_tail|validate: load-unread path=scripts/smoke/rows/dyn.sh line=3 site=path"
  "a directive over a computed load traces its row|# loads: scripts/fixtures/vpn/*.py -- dyn_pick names the stand-in|scripts/fixtures/vpn/b.py|scripts/qml-smoke.sh --rows $smoke_core,dyn,$smoke_tail|"
  "a traced row's unread folder file selects no nested smoke|# loads: scripts/fixtures/vpn/*.py -- dyn_pick names the stand-in|scripts/fixtures/vpn/details.txt||"
)
for i in "${!dyn_cases[@]}"; do
  IFS='|' read -r name directive file wanted line <<<"${dyn_cases[i]}"
  d="$tmp/smoke-dyn-$i"; smoke_fixture "$d"
  mkdir -p "$d/scripts/fixtures/vpn"
  printf 'pass\n' | tee "$d/scripts/fixtures/vpn/a.py" >"$d/scripts/fixtures/vpn/b.py"
  printf 'details\n' >"$d/scripts/fixtures/vpn/details.txt"
  printf '%s\n' 'dyn_dir="$repo/scripts/fixtures/vpn"' 'dyn_name="$(dyn_pick)"' ${directive:+"$directive"} 'python3 "$dyn_dir/$dyn_name.py"' >"$d/scripts/smoke/rows/dyn.sh"
  sed -i 's/^start-order$/dyn\nstart-order/' "$d/scripts/smoke/rows.list"
  "${base_env[@]}" git -C "$d" add -A
  "${base_env[@]}" git -C "$d" commit -q -m dyn
  printf '# changed\n' >>"$d/$file"
  printf '# mixed change\n' >>"$d/kendex.settings.toml"
  status=0
  out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml --changed HEAD --list 2>"$tmp/smoke-dyn.err")" || status=$?
  plan=""
  if plan="$(sed -n '/^scripts\/qml-smoke.sh/p' <<<"$out")" && [[ $status == 0 && $plan == "$wanted" ]] && { [[ -z $line ]] || grep -qxF -e "$line" "$tmp/smoke-dyn.err"; }; then
    ok "$name"
  else
    fail "$name: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-dyn.err"
  fi
done

# A fix round after a rebase: the lane validated its launcher change at
# $lane, main then changed acme.notify, the lane rebased onto it and edits
# launcher again. --changed $lane selects the lane's own paths only.
d="$tmp/smoke-rebase"; smoke_fixture "$d"
"${base_env[@]}" git -C "$d" branch -q -f trunk HEAD
"${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
printf 'lane\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
"${base_env[@]}" git -C "$d" commit -q -am lane
lane="$("${base_env[@]}" git -C "$d" rev-parse HEAD)"
"${base_env[@]}" git -C "$d" checkout -q trunk
printf 'main\n' >>"$d/shell/plugins/acme.notify/Panel.qml"
"${base_env[@]}" git -C "$d" commit -q -am main
"${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
"${base_env[@]}" git -C "$d" checkout -q feature
"${base_env[@]}" git -C "$d" rebase -q trunk
printf 'fix\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
status=0
out="$(cd -- "$d" && "${base_env[@]}" bash scripts/validate qml --changed "$lane" --list 2>"$tmp/smoke-rebase.err")" || status=$?
plan="$(grep '^scripts/qml-smoke.sh' <<<"$out" || true)"
if [[ $status == 0 && $plan == "$smoke_launcher" ]]; then
  ok "a fix round after a rebase selects the lane's own paths"
else
  fail "a fix round after a rebase selects the lane's own paths: exit=$status plan=$plan"; sed 's/^/        /' "$tmp/smoke-rebase.err"
fi

# A tracked-file list whose git command fails runs every row and names why,
# even when the command wrote the whole list first. The git stand-in fails
# only that read, `git ls-files -z`, and passes every other call through.
real_git="$(command -v git)"
mkdir -p "$tmp/failing-ls-files"
printf '#!/bin/sh\nif [ "$*" = "ls-files -z" ]; then "%s" ls-files -z; exit 1; fi\nexec "%s" "$@"\n' "$real_git" "$real_git" >"$tmp/failing-ls-files/git"
chmod +x "$tmp/failing-ls-files/git"
d="$tmp/smoke-rows-tracked-list"; smoke_fixture "$d"
printf '# changed\n' >>"$d/shell/plugins/acme.launcher/Panel.qml"
test_area=qml test_args=(--changed HEAD --list)
row "a tracked-file list whose read fails runs every row" "$d" 0 "PATH=$tmp/failing-ls-files:$(dirname -- "$node_bin"):$PATH" \
  "scripts/qml-smoke.sh" "validate: smoke-rows=all reason=tracked-list-unreadable"
test_args=()

# The row records. A lane's run is stopped while the nested smoke runs, and
# the next run on the lane's tree reruns only what did not end. The
# fixture's smoke stand-in writes what scripts/qml-smoke.sh and harness.sh
# write for the records under VGS_SMOKE_RESULTS_DIR: each row's partial
# record, result, judge readings and row-secs line, and the attempt's
# outside-failures and closing reading. The row named in .git/hang reports
# its PIDs in .git/hung and waits to be stopped; on its TERM it takes the
# closing reading itself, or, under the .git/teardown knob, ends through
# the real teardown.sh, whose closing reading the real
# qml_smoke_judge_reading writes once its TERM-then-KILL wait is over. The
# fatal-controls stand-in, which validate starts only once the nested
# smoke row has ended, writes .git/controls-started as it starts. The
# lane's change stays uncommitted and --changed HEAD scopes the runs to it.
# A control is a copy of validate with OLD replaced by NEW.
reuse_fixture() { # DIR [OLD NEW]
  local dir="$1"
  smoke_fixture "$dir"
  if [[ $# -eq 3 ]]; then plant "$dir/scripts/validate" "$2" "$3"; fi
  # Observe the production wait without changing its lifetime or outcome.
  plant "$dir/scripts/validate" $'rows_wait() {\n' $'rows_wait() {\n  : > "$(git rev-parse --git-dir)/group-wait"\n'
  cat >"$dir/scripts/qml-smoke.sh" <<'SH'
#!/usr/bin/env bash
list="$(dirname -- "$0")/smoke/rows.list"
if [[ ${1-} == --list-rows ]]; then awk '!/^#/ && NF' "$list"; exit 0; fi
git_dir="$(git rev-parse --absolute-git-dir)"
hang="$(cat -- "$git_dir/hang" 2>/dev/null || true)"
rows=",${2-},"
driver="$(mktemp -d "${VGS_SMOKE_RESULTS_DIR:?}/qml-smoke-resume.XXXXXX")"
a="$driver/1"
mkdir -p "$a/results" "$a/partial"
printf '0\0' >"$a/outside-failures"
close() { printf -- '- close 0 0 intact\n' >>"$a/judge-readings"; }
for row in $(awk '!/^#/ && NF' "$list"); do
  [[ $rows == ,, || $rows == *",$row,"* ]] || continue
  printf '%s start 0 0 intact\n' "$row" >>"$a/judge-readings"
  printf '0\0' >"$a/partial/$row"
  if [[ $row == "$hang" ]]; then
    if [[ -e $git_dir/teardown ]]; then
      # The real teardown takes the closing reading through the real reader
      # as this process ends on the stop's TERM.
      qml_smoke_attempt=$a pgids=() source_repo="$git_dir/real"
      smoke_judge_reading() { printf '0 0 intact\n'; }
      source "$source_repo/scripts/smoke/judge-reading.sh"
      source "$source_repo/scripts/smoke/teardown.sh"
    else
      trap 'close; kill "$waiting" 2>/dev/null; exit 143' TERM
    fi
    sleep 600 &
    waiting=$!
    printf '%s %s\n' "$$" "$waiting" >"$git_dir/hung"
    wait "$waiting"
  fi
  printf '%s end 0 0 intact\n' "$row" >>"$a/judge-readings"
  printf 'qml-smoke: row-secs row=%s secs=3 cpu_some_pct=0.1 load1=0.1\n' "$row" >>"$a/run.log"
  printf '0\0' >"$a/results/$row"
done
close
SH
  printf '#!/usr/bin/env bash\n: >"$(git rev-parse --absolute-git-dir)/controls-started"\n' >"$dir/scripts/test-qml-smoke.sh"
  chmod +x "$dir/scripts/test-qml-smoke.sh"
  commit "$dir" stand-ins
  # The real teardown and closing-reading writer, which the smoke stand-in
  # sources under the teardown knob, with a world check that passes. They
  # sit in the git directory, so no input of the lane's tree changes.
  local real="$dir/.git/real/scripts/smoke"
  mkdir -p -- "$real"
  cp -- "$repo/scripts/smoke/teardown.sh" "$real/teardown.sh"
  sed -n '/^qml_smoke_judge_reading() {/,/^}/p' "$repo/scripts/qml-smoke.sh" >"$real/judge-reading.sh"
  grep -q '^qml_smoke_judge_reading() {' "$real/judge-reading.sh" ||
    fail "$dir: scripts/qml-smoke.sh holds no qml_smoke_judge_reading"
  printf '#!/bin/sh\n[ "$1" = --check ]\n' >"$real/gpu-fence.sh"
  chmod +x "$real/gpu-fence.sh"
  printf 'lane\n' >>"$dir/shell/plugins/acme.launcher/Panel.qml"
  printf 'lane\n' >>"$dir/shell/plugins/acme.notify/Panel.qml"
  # The fatal-controls row runs after the nested smoke.
  printf '# lane\n' >>"$dir/scripts/test-qml-smoke.sh"
}
# reuse_cut DIR SIGNAL [ENV...]: run `validate qml --changed HEAD` in DIR,
# with each NAME=VALUE of ENV, until the notifications row reports that it
# waits, then stop validate. SIGNAL TERM sends validate a TERM. SIGNAL UNIT
# stops the run as a unit's stop does (systemd.kill(5),
# KillMode=control-group): validate runs in a session of its own, and every
# process of that session gets a TERM at once, validate's first, as the
# unit holds them in the order they started, so a row's leader ends with
# the rest of its group. SIGNAL LEADER forces the other order of that stop:
# it TERMs only the nested smoke row's leader, waits until validate has
# reaped it and entered the group wait (or the control started the next
# row too soon), and only then TERMs the stand-in and its wait, whose
# teardown then takes the closing reading; validate then ends by itself,
# red for the stopped row. Asserts the exit SIGNAL gives. SIGNAL `-` lets
# the run end by itself. The run's log is DIR.cut.log.
reuse_cut() { # DIR SIGNAL [ENV...]
  local dir="$1" signal="$2" git_dir pid tick status=0 want=143 sid stat file leader
  local -a hung fields members launch=(bash) cut_env=("${@:3}")
  git_dir="$("${base_env[@]}" git -C "$dir" rev-parse --absolute-git-dir)"
  [[ $signal == - ]] || printf 'notifications\n' >"$git_dir/hang"
  # -w: setsid forks when its caller leads a group, and then waits for it.
  [[ $signal != UNIT ]] || launch=(setsid -w bash)
  (cd -- "$dir" && exec "${base_env[@]}" "${cut_env[@]}" "${launch[@]}" scripts/validate qml --changed HEAD) >"$dir.cut.log" 2>&1 &
  pid=$!
  if [[ $signal == - ]]; then
    wait "$pid" || true
    return 0
  fi
  # A bound on the wait for the reported state, not a reading.
  for ((tick = 0; tick < 600; tick++)); do
    if [[ -s $git_dir/hung ]] || ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if [[ ! -s $git_dir/hung ]]; then
    fail "$dir: the stand-in notifications never waited"; sed 's/^/        /' "$dir.cut.log"
    kill -KILL "$pid" 2>/dev/null || true; wait "$pid" || true; return 0
  fi
  if [[ $signal == UNIT ]]; then
    # The session is the one setsid made: the stand-in's, led by validate,
    # which is this job or its one child, and never this suite's own.
    read -r -a hung <"$git_dir/hung"
    read -r stat <"/proc/${hung[0]}/stat" && read -r -a fields <<<"${stat##*) }" && sid=${fields[3]}
    read -r stat <"/proc/$$/stat" && read -r -a fields <<<"${stat##*) }"
    if [[ -z ${sid-} || $sid == "${fields[3]}" ]] || ! read -r stat <"/proc/$sid/stat" ||
       { read -r -a fields <<<"${stat##*) }"; [[ $sid != "$pid" && ${fields[1]} != "$pid" ]]; }; then
      fail "$dir: the cut run's session is not validate's own"
      kill -KILL "$pid" "${hung[@]}" 2>/dev/null || true; wait "$pid" || true; return 0
    fi
    members=()
    for file in /proc/[0-9]*/stat; do
      read -r stat 2>/dev/null <"$file" || continue
      read -r -a fields <<<"${stat##*) }"
      file="${file#/proc/}"
      [[ ${fields[3]} != "$sid" || ${file%/stat} == "$sid" ]] || members+=("${file%/stat}")
    done
    ((${#members[@]} == 0)) || mapfile -t members < <(printf '%s\n' "${members[@]}" | sort -n)
    # A member may end before its turn; the TERM reaches every other.
    kill -TERM -- "$sid" "${members[@]}" 2>/dev/null || true
  elif [[ $signal == LEADER ]]; then
    want=1
    # The leader leads the stand-in's group and is validate's own child.
    read -r -a hung <"$git_dir/hung"
    leader=""
    read -r stat <"/proc/${hung[0]}/stat" && read -r -a fields <<<"${stat##*) }" && leader=${fields[2]}
    if [[ -z $leader || $leader == "${hung[0]}" ]] || ! read -r stat <"/proc/$leader/stat" ||
       { read -r -a fields <<<"${stat##*) }"; [[ ${fields[1]} != "$pid" ]]; }; then
      fail "$dir: the stand-in's group is not led by a child of validate"
      kill -KILL "$pid" "${hung[@]}" 2>/dev/null || true; wait "$pid" || true; return 0
    fi
    kill -TERM "$leader"
    # A bound on the wait for the reported states, not a reading.
    for ((tick = 0; tick < 600; tick++)); do
      [[ -e /proc/$leader || ( ! -e $git_dir/group-wait && ! -e $git_dir/controls-started ) ]] || break
      sleep 0.1
    done
    if [[ -e /proc/$leader || ( ! -e $git_dir/group-wait && ! -e $git_dir/controls-started ) ]]; then
      fail "$dir: validate never reaped the smoke row's leader and handled its group"
      kill -KILL "$pid" "${hung[@]}" 2>/dev/null || true; wait "$pid" || true; return 0
    fi
    if [[ -e $git_dir/controls-started ]]; then
      [[ -e $git_dir/expect-no-wait ]] || fail "$dir: the next row started before the smoke group ended"
    else
      [[ ! -e $git_dir/expect-no-wait ]] || fail "$dir: the no-wait control unexpectedly waited for the group"
    fi
    kill -TERM "${hung[@]}" 2>/dev/null || true
  else
    kill -s "$signal" "$pid"
  fi
  # The redirection keeps bash's own report of a killed job off the log.
  { wait "$pid"; } 2>/dev/null || status=$?
  rm -f -- "${git_dir:?}/hang" "${git_dir:?}/hung" "${git_dir:?}/teardown" "${git_dir:?}/controls-started" "${git_dir:?}/tree-fail"
  [[ $status == "$want" ]] || { fail "$dir: the cut run exited $status, not $want"; sed 's/^/        /' "$dir.cut.log"; }
}
# The tree-fail knob's git stand-in: it fails `git write-tree` while the
# knob and the waiting stand-in's report are both in the git directory, so
# the run reads its start tree and not its end tree, and passes every other
# call through.
mkdir -p "$tmp/failing-write-tree"
printf '#!/bin/sh\nif [ "${1-}" = write-tree ] && g="$("%s" rev-parse --absolute-git-dir)" && [ -e "$g/tree-fail" ] && [ -s "$g/hung" ]; then exit 128; fi\nexec "%s" "$@"\n' "$real_git" "$real_git" >"$tmp/failing-write-tree/git"
chmod +x "$tmp/failing-write-tree/git"
# name|signal|knob|control|wanted lines, ^ between them. A control
# collect-first collects the records before the rows stop; reaped collects
# a smoke row as validate reaps its leader, before its group ends.
reuse_cases=(
  "a run its unit stops during a smoke row keeps the smoke rows that ended before the stop|UNIT|teardown||validate: reused secs=3 smoke=launcher^validate: rerun secs=unknown smoke=notifications^$smoke_notify"
  "control: a unit's stop collected before the closing reading keeps no smoke row|UNIT|teardown|collect-first|validate: rerun secs=3 smoke=launcher^$smoke_both"
  "a stop whose smoke row leader validate reaps before the closing reading keeps the smoke rows that ended before it|LEADER|teardown||validate: reused secs=3 smoke=launcher^validate: rerun secs=unknown smoke=notifications^$smoke_notify"
  "control: a smoke row collected as validate reaps its leader keeps no smoke row|LEADER|teardown|reaped|validate: rerun secs=3 smoke=launcher^$smoke_both"
  "a cut run whose end tree cannot be read keeps the rows it finished and reruns the open one|TERM|tree-fail||validate: reused secs=3 smoke=launcher^validate: rerun secs=unknown smoke=notifications^$smoke_notify"
)
reuse_case() { # SPEC
  local name signal knob mutant wanted d git_dir
  local -a lines cut_env=()
  IFS='|' read -r name signal knob mutant wanted <<<"$1"
  d="$tmp/reuse-${name//[^a-z]/-}"
  case "$mutant" in
    collect-first) reuse_fixture "$d" "trap 'set +e; stop_rows; records_finish; " "trap 'set +e; records_finish; stop_rows; " ;;
    reaped) reuse_fixture "$d" '      rows_wait "$pid"' '      :' ;;
    *) reuse_fixture "$d" ;;
  esac
  git_dir="$("${base_env[@]}" git -C "$d" rev-parse --absolute-git-dir)"
  : >"$git_dir/$knob"
  [[ $knob != tree-fail ]] || cut_env=("PATH=$tmp/failing-write-tree:$(dirname -- "$node_bin"):$PATH")
  [[ $mutant != reaped ]] || : >"$git_dir/expect-no-wait"
  reuse_cut "$d" "$signal" "${cut_env[@]}"
  if [[ $knob == tree-fail ]] && { ! grep -q '^validate: row-records=kept reason=end-tree-unreadable tree=[0-9a-f]' "$d.cut.log" ||
       grep -q '^validate: row-records=void' "$d.cut.log"; }; then
    fail "$name: the cut run did not keep its records on its start tree"
  fi
  IFS='^' read -r -a lines <<<"$wanted"
  test_area=qml test_args=(--changed HEAD --list)
  row "$name" "$d" 0 "" "${lines[@]}"
}
parallel_cases reuse_case reuse "${reuse_cases[@]}"

# A restack after a run that passed: trunk gains one commit that changes a
# path no row maps, the lane's commits move onto it, and the next run
# lists what it reuses. Both kinds start with trunk at the fixture's tip,
# so the lane's change alone differs from the branch point. In `unit` the
# lane changes scripts/qml-unit.sh; in `qml` the lane changes the
# launcher's and notifications' Panel.qml through reuse_fixture.
restack_cases=(
  "a restack that changes no input of a table row reuses its pass|unit|%validate: reused secs=[0-9]+ row=qml unit tests$"
  "a restack that changes no input of a smoke row reuses its pass|qml|validate: reused secs=3 smoke=launcher^validate: reused secs=3 smoke=notifications"
)
restack_case() { # SPEC
  local name kind wanted d stand_in
  local -a lines
  IFS='|' read -r name kind wanted <<<"$1"
  d="$tmp/restack-$kind"
  if [[ $kind == qml ]]; then
    reuse_fixture "$d"
  else
    fresh "$d"
    for stand_in in scripts/qml-unit.sh scripts/test-qml-unit.sh; do
      printf '#!/usr/bin/env bash\nexit 0\n' >"$d/$stand_in"
      chmod +x "$d/$stand_in"
    done
    commit "$d" stand-ins
  fi
  "${base_env[@]}" git -C "$d" branch -q -f trunk HEAD
  "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
  if [[ $kind == qml ]]; then
    reuse_cut "$d" -
  else
    printf '# lane\n' >>"$d/scripts/qml-unit.sh"
    (cd -- "$d" && exec "${base_env[@]}" bash scripts/validate unit) >"$d.first.log" 2>&1 || true
  fi
  commit "$d" lane
  "${base_env[@]}" git -C "$d" checkout -q trunk
  printf 'main\n' >>"$d/.kendex-lock.json"
  commit "$d" main
  "${base_env[@]}" git -C "$d" update-ref refs/remotes/origin/trunk HEAD
  "${base_env[@]}" git -C "$d" checkout -q feature
  "${base_env[@]}" git -C "$d" rebase -q trunk
  IFS='^' read -r -a lines <<<"$wanted"
  test_area=$kind test_args=(--list)
  row_re "$name" "$d" 0 "" "${lines[@]}"
}
parallel_cases restack_case restack "${restack_cases[@]}"
test_args=()

# The rows a run of the real runner holds, in a scratch tree whose list
# holds the core rows: top calls a function only own defines, own's
# directives name base's file and part's, a row file the tree has and the
# list does not, which is own's own; the core row start-order's directive
# names seat's. The tree's fence logs its call and
# its harness stands in, printing each row it is handed and answering the
# step the runner takes after hyprland-consent, so the run starts no
# compositor and no shell. The run prints the named and the expanded set
# once, which a lane reads to see what its retry ran, and runs the rows in
# list order: the rows top's chain reaches two reads deep and the row a
# core row reads.
d="$tmp/runner-reads"
mkdir -p "$d/scripts/smoke/rows"
cp -- "$repo/scripts/qml-smoke.sh" "$d/scripts/qml-smoke.sh"
# The fixture exercises row selection inside one attempt, not the
# world/resume driver.
plant "$d/scripts/qml-smoke.sh" 'if [[ -z ${qml_smoke_attempt:-} ]]; then' 'if false; then'
plant "$d/scripts/qml-smoke.sh" 'if [[ -n $first_bar_runs || -n ${qml_smoke_attempt:-} ]]; then' 'if true; then'
cp -- "$repo/scripts/smoke/row-inputs.sh" "$d/scripts/smoke/row-inputs.sh"
cp -- "$repo/scripts/row_loads.py" "$repo/scripts/shell_source.py" "$d/scripts/"
printf '%s\n' '# Rows.' bar hyprland-consent seat base own top start-order auth-sentinel >"$d/scripts/smoke/rows.list"
for smoke_row_name in bar hyprland-consent seat base auth-sentinel; do
  printf ':\n' >"$d/scripts/smoke/rows/$smoke_row_name.sh"
done
printf '# loads: scripts/smoke/rows/seat.sh -- the seat seat leaves\n' >"$d/scripts/smoke/rows/start-order.sh"
printf '# loads: scripts/smoke/rows/part.sh scripts/smoke/rows/base.sh -- the state base leaves\nown_helper() { :; }\n' >"$d/scripts/smoke/rows/own.sh"
printf 'own_helper\n' >"$d/scripts/smoke/rows/top.sh"
printf '# Run by own.sh.\n' >"$d/scripts/smoke/rows/part.sh"
printf '#!/usr/bin/env bash\necho fence >>"%s"\n' "$d/fence.log" >"$d/scripts/smoke/gpu-fence.sh"
chmod +x "$d/scripts/smoke/gpu-fence.sh"
mkdir -p "$d/sandbox/evidence/failed" "$d/sandbox/results"
printf 'sandbox=%q\nqml_smoke_attempt=$sandbox\nfailures=0\nnot_measured_rows=()\nleak_seq=0\n' "$d/sandbox" >"$d/scripts/smoke/harness.sh"
printf '%s\n' 'smoke_row() { printf "row=%s\n" "$1"; }' 'compositor_logs_on() { :; }' 'ok() { :; }' 'smoke_outcome_journal() { :; }' 'smoke_judge_reading() { echo 0 0 intact; }' 'smoke_finish() { :; }' >>"$d/scripts/smoke/harness.sh"
smoke_deep=(bar hyprland-consent seat base own top start-order auth-sentinel)
status=0
out="$("${base_env[@]}" bash "$d/scripts/qml-smoke.sh" --rows top 2>&1)" || status=$?
if [[ $status == 0 && $out == "qml-smoke: rows named=top run=$(IFS=,; printf '%s' "${smoke_deep[*]}")"$'\n'"$(printf 'row=%s\n' "${smoke_deep[@]}")" && $(<"$d/fence.log") == fence ]]; then
  ok "a run prints the named and the expanded rows once and runs them in list order"
else
  fail "the runner's expanded run: exit=$status output=$out"
fi

# --skip-unprepared leaves out a row the host cannot prepare and names it:
# a `$NAME` input while NAME is unset, a `device:` input that matches no
# character device, and a `bus:user` input with no user bus. Each row's
# stand-in reads not measured, as the real row does unprepared.
d="$tmp/unprepared"; fresh "$d"
plant "$d/scripts/validate" $'rows=(\n' $'rows=(\n  "logic|prepared row|scripts/check-prepared.sh|\\$VGS_TEST_PREPARED"\n'
commit "$d" prepared-row
printf '#!/bin/sh\nexit 77\n' >"$d/scripts/check-prepared.sh"; chmod +x "$d/scripts/check-prepared.sh"
test_area=logic test_args=(--changed HEAD --skip-unprepared)
row "--skip-unprepared names an unset prepared row and runs nothing" "$d" 0 "" \
  "validate: unselected unset=VGS_TEST_PREPARED row=prepared row" "validate: ok" '!exit=77 row=prepared row'
d="$tmp/device-unprepared"; fresh "$d"
plant "$d/scripts/validate" $'rows=(\n' $'rows=(\n  "logic|device row|scripts/check-device.sh|device:'"$d"$'/absent-device*"\n'
commit "$d" device-row
printf '#!/bin/sh\nexit 77\n' >"$d/scripts/check-device.sh"; chmod +x "$d/scripts/check-device.sh"
row "--skip-unprepared names an absent declared device and runs nothing" "$d" 0 "" \
  "validate: unselected missing=device:$d/absent-device* row=device row" "validate: ok" '!exit=77 row=device row'
# The real kill switch fresh-start row declares the user bus it needs, so a
# host without one, as the nightly's container, leaves it unselected. The
# stand-in reads not measured for --start, as the real test does without a
# bus, and passes for the sibling sandbox row that shares its script.
d="$tmp/bus-unprepared"; fresh "$d"
printf '#!/bin/sh\n[ "$1" = --start ] && exit 77\nexit 0\n' >"$d/scripts/test-vpn-kill-switch-unit.sh"
chmod +x "$d/scripts/test-vpn-kill-switch-unit.sh"
mkdir -m 700 -- "$d-run"
test_area=cli test_args=(--changed HEAD --skip-unprepared)
row "--skip-unprepared leaves the kill switch start row out without a user bus" "$d" 0 "XDG_RUNTIME_DIR=$d-run" \
  "validate: unselected missing=bus:user row=VPN kill switch fresh systemd start" "validate: ok" '!exit=77 row=VPN kill switch fresh systemd start'
test_args=()

# No two scratch holders of one run get one path. The holders share the
# run's root and run side by side, so a name drawn from RANDOM and made
# without exclusive creation can go to two of them. The file BASH_ENV names
# makes RANDOM a plain variable, so every draw in validate and its rows is
# one number.
printf 'unset RANDOM\nRANDOM=7\n' >"$tmp/one-draw"
d="$tmp/scratch-own-path"; fresh "$d"
test_area=repo
row "each scratch holder of one run gets a path of its own" "$d" 0 "BASH_ENV=$tmp/one-draw" "validate: ok"

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

# Rows start while their weights fit the core count, which OMP_NUM_THREADS
# sets for nproc, and VGS_VALIDATE_JOBS=32 never binds. Each row adds the
# weight its arguments name to the weight in flight under a lock, records
# the sum and holds it 0.5 s, so rows started too eagerly are seen
# together. A row given PEERS first waits up to 5 s for that many rows of
# its weight to have started, which proves rows still run at once; one
# that gives up marks the run, and the rows after it give up at once. The
# rows declared heavier than 8 count as 8, so they run at all.
d="$tmp/weigh-heavy"
heavy=('"tools|heavy a|scripts/test-weigh.sh a 3 2|%weight=3"' '"tools|heavy b|scripts/test-weigh.sh b 3 2|%weight=3"')
for name in c d e f; do heavy+=("\"tools|heavy $name|scripts/test-weigh.sh $name 3|%weight=3\""); done
heavy+=('"tools|whole g|scripts/test-weigh.sh g 8|%weight=all"' '"tools|over h|scripts/test-weigh.sh h 8|%weight=12"')
jobs_fixture "$d" test-weigh.sh "${heavy[@]}" <<'SH'
#!/bin/sh
exec 9>.git/weigh.lock
flock 9
sum=$(($(cat .git/in-flight 2>/dev/null || echo 0) + $2))
echo "$sum" >.git/in-flight
echo "$sum" >>.git/sums
: >".git/started-$2-$1"
flock -u 9
i=0
while [ -n "$3" ] && [ "$(ls .git | grep -c "^started-$2-")" -lt "$3" ]; do
  if [ -e .git/alone ] || [ "$i" -ge 50 ]; then : >.git/alone; echo "weigh: $1 ran alone"; exit 1; fi
  sleep 0.1
  i=$((i + 1))
done
sleep 0.5
flock 9
echo $(($(cat .git/in-flight) - $2)) >.git/in-flight
SH
status=0
out="$(cd -- "$d" && "${base_env[@]}" OMP_NUM_THREADS=8 VGS_VALIDATE_JOBS=32 bash scripts/validate tools --full 2>&1)" || status=$?
peak="$(sort -n -- "$d/.git/sums" | tail -n 1)" || peak=unreadable
if [[ $status == 0 && $peak == 8 && -e $d/.git/started-8-g && -e $d/.git/started-8-h ]] && grep -qxF 'validate: ok' <<<"$out"; then
  ok "heavy rows on 8 cores pass and never hold more than 8 in flight"
else
  fail "heavy rows on 8 cores: exit=$status peak=$peak, or a row heavier than the cores never started"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# A TERM to validate ends every running row's processes and removes the
# run's scratch root within the 10 s a unit's stop gives between its TERM
# and its KILL (TimeoutStopSec=10), though the rows ignore TERM and hold
# the stop's wait to its deadline KILL. Each row holds a lock with a sleep
# that outlives the stop, so a free lock proves the row's processes ended.
# validate runs in a session and process group of its own; setsid execs it
# in place, since the job that runs it leads no group, so the job's pid is
# validate's. secs runs from the TERM to validate's end, cleared is the
# milliseconds from the TERM until the run's TMPDIR holds no validate root,
# read every 0.1 s until validate ends, and freed counts the locks free
# within 1 s of that end.
d="$tmp/jobs-deadline"
jobs_fixture "$d" test-hold.sh '"tools|hold a|scripts/test-hold.sh a|"' '"tools|hold b|scripts/test-hold.sh b|"' <<'SH'
#!/bin/sh
trap '' TERM
exec 9>".git/lock-$1"
flock 9
: >".git/ready-$1"
sleep 14
SH
mkdir -p "$d/tmp"
(cd -- "$d" && exec "${base_env[@]}" TMPDIR="$d/tmp" VGS_VALIDATE_JOBS=2 setsid bash scripts/validate tools --full) >"$d.out" 2>&1 &
pid=$!
for _ in $(seq 1 100); do
  [[ -e $d/.git/ready-a && -e $d/.git/ready-b ]] && break
  sleep 0.1
done
started=$SECONDS
signalled=${EPOCHREALTIME/./}
kill -s TERM "$pid"
# The elapsed-time bound the stop of a unit sets is the claim, so this
# reads the clock; validate's end as a zombie (proc(5) state Z) ends it.
cleared=""
while [[ -z $cleared ]]; do
  if ! compgen -G "$d/tmp/validate-*" >/dev/null; then
    cleared=$(((${EPOCHREALTIME/./} - signalled) / 1000))
  else
    read -r line 2>/dev/null <"/proc/$pid/stat" || break
    line="${line##*) }"
    [[ ${line%% *} != Z ]] || break
    sleep 0.1
  fi
done
status=0
wait "$pid" || status=$?
secs=$((SECONDS - started))
freed=0
for lock in "$d/.git/lock-a" "$d/.git/lock-b"; do
  if flock -w 1 "$lock" true; then freed=$((freed + 1)); fi
done
if [[ $status == 143 && $freed == 2 && $secs -ge 8 && -n $cleared && $cleared -le 10000 ]]; then
  ok "rows that ignore TERM end by KILL once the stop's deadline passes, and the scratch root goes within 10 s of the TERM"
else
  fail "rows that ignore TERM: exit=$status freed=$freed secs=$secs cleared-ms=[$cleared]"; sed 's/^/        /' "$d.out"
fi

# A run SIGKILLed once its root and changed-paths file exist leaves both;
# the next run removes them at its start and names the root, and leaves
# the root of a run still alive alone. Each run's one row writes its pid
# and, while .git/hold exists, holds until the case KILLs it, so the pid
# file is the barrier that both scratch paths exist. An old-form root and
# changed-paths file, aged past 10800 s and named for the live run's pid,
# survive too: older code held neither open, so only that pid shows they are
# a live run's.
reap_start() { # DIR TMPDIR: start a held run; sets reap_pid and reap_root
  local made
  (cd -- "$1" && exec "${base_env[@]}" TMPDIR="$2" setsid bash scripts/validate repo --changed HEAD) >"$1.out" 2>&1 &
  reap_pid=$!
  for _ in $(seq 1 100); do [[ -s $1/.git/row-pid ]] && break; sleep 0.1; done
  [[ -s $1/.git/row-pid ]] || return 1
  made=("$2/validate-$reap_pid-"*)
  [[ ${#made[@]} -eq 1 && -d ${made[0]} ]] || return 1
  reap_root="${made[0]}"
}
reap_lines() { # OUTPUT: its `validate: cleanup=` lines
  local line
  while IFS= read -r line; do [[ $line != 'validate: cleanup='* ]] || printf '%s\n' "$line"; done <<<"$1"
}
reap_scratch="$tmp/reap-tmp"
mkdir -- "$reap_scratch"
for name in killed live next; do
  jobs_fixture "$tmp/reap-$name" test-held.sh '"repo|held|scripts/test-held.sh|"' <<'SH'
#!/bin/sh
[ -e .git/hold ] || exit 0
echo $$ >.git/row-pid.part && mv .git/row-pid.part .git/row-pid
exec sleep 300
SH
done
: >"$tmp/reap-killed/.git/hold"
: >"$tmp/reap-live/.git/hold"
if reap_start "$tmp/reap-killed" "$reap_scratch" && killed_root="$reap_root" killed_pid="$reap_pid" &&
   killed_paths="$(find "$killed_root" -maxdepth 1 -type f)" && [[ -n $killed_paths && $killed_paths != *$'\n'* ]] &&
   reap_start "$tmp/reap-live" "$reap_scratch" && live_root="$reap_root" live_pid="$reap_pid"; then
  old_root="$reap_scratch/validate-$live_pid-OldRoot1" old_paths="$reap_scratch/validate-$live_pid-OldFile1"
  mkdir -- "$old_root"
  : >"$old_paths"
  touch -d @1 -- "$old_root" "$old_paths"
  kill -KILL "$killed_pid"
  wait "$killed_pid" 2>/dev/null || true
  status=0
  out="$(cd -- "$tmp/reap-next" && "${base_env[@]}" TMPDIR="$reap_scratch" bash scripts/validate repo --changed HEAD 2>&1)" || status=$?
  reap_want="$(printf '%s\n' "validate: cleanup=reaped path=$killed_root" \
    "validate: cleanup=kept path=$old_root reason=owner-unproved" "validate: cleanup=kept path=$old_paths reason=owner-unproved" | sort)"
  if [[ $status == 0 && ! -e $killed_root && ! -e $killed_paths && -d $live_root && -d $old_root && -f $old_paths &&
        "$(reap_lines "$out" | sort)" == "$reap_want" ]]; then
    ok "a run removes a killed run's root and changed-paths file at its start, names the root, and leaves a live run's roots of either form"
  else
    fail "the reap at a run's start: exit=$status killed-root=$([[ -e $killed_root ]] && echo kept || echo gone) live-root=$([[ -d $live_root ]] && echo kept || echo gone) old-form=$([[ -d $old_root && -f $old_paths ]] && echo kept || echo gone)"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
  kill -KILL "$(<"$tmp/reap-live/.git/row-pid")" 2>/dev/null || true
  wait "$live_pid" 2>/dev/null || true
else
  fail "the reap case could not hold its runs"; sed 's/^/        /' "$tmp/reap-killed.out" "$tmp/reap-live.out" 2>/dev/null
  [[ -z ${reap_pid:-} ]] || kill -KILL "$reap_pid" 2>/dev/null || true
fi
for name in killed live; do
  [[ ! -s $tmp/reap-$name/.git/row-pid ]] || kill -KILL "$(<"$tmp/reap-$name/.git/row-pid")" 2>/dev/null || true
done

if [[ $failures -gt 0 ]]; then
  echo "test-validate: failed=$failures"
  exit 1
fi
echo "test-validate: ok"
