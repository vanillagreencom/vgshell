#!/usr/bin/env bash
# The vgs.google-drive floating TUIs, shell/plugins/vgs.google-drive/tui/,
# against a stand-in runner that logs its argv and a stand-in gum that
# answers each question from a list. It proves that Set up hourly sync runs
# the runner's install; that Sign in to Google runs its authorize and turns
# this run's refusal, never an earlier run's, into a plain sentence; that
# Add a folder pair hands the runner the answers as one JSON definition, a
# quote and a backslash in a name included, turns a refused rule into a
# sentence, and says plainly when the runner added the pair but could not
# install the hourly sync; that Remove a folder pair removes the pair its
# id names after a yes, refuses an id the runner does not list, and
# refuses no id, an id over 256 characters and an id with a control
# character before any runner call; that Start the folder pair list again runs the
# runner's repair after a yes and turns this run's valid-list refusal into
# a plain sentence; that Sign out runs the runner's sign-out for its own
# direction only after a yes and turns this run's refusal into a plain
# sentence; and that each script refuses an extra argument. Each run has a
# terminal of its own from script(1), since the library asks only on a
# terminal, an empty environment but for the names the presenter hands a
# script, and a PATH of the stand-ins and a few host tools, so no run
# reaches the user's keyring, systemd or Google Drive.
#
# The controls at the end edit a copy of a script, one rule at a time, and
# require its case to fail on the copy.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
plugin_src="$repo/shell/plugins/vgs.google-drive"
TMP_ROOT="$(mktemp -d)" || { echo "test-google-drive-tui: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-google-drive-tui: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-google-drive-tui: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
for tool in script python3 stat tail grep dirname mkdir cat stty; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-google-drive-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

tools="$TMP_ROOT/tools"
plugin="$TMP_ROOT/plugin"
home="$TMP_ROOT/home"
log="$home/.local/state/vgshell/google-drive/setup.log"
mkdir -p "$tools" "$plugin/bin" "$plugin/tui" "$home"
for tool in bash sh script stat tail grep dirname mkdir cat stty; do ln -s -- "$(command -v "$tool")" "$tools/$tool"; done
# gum: `input` and `choose` print the next answer, `confirm` answers yes
# for `yes`; every other use, the header's box, prints its words.
cat >"$tools/gum" <<SH
#!$(command -v bash)
next() {
  local n=0
  [[ -f "$TMP_ROOT/answered" ]] && n=\$(<"$TMP_ROOT/answered")
  mapfile -t answers <"$TMP_ROOT/answers"
  printf '%s' "\$((n + 1))" >"$TMP_ROOT/answered"
  printf '%s' "\${answers[n]-}"
}
case "\$1" in
  input | choose) next; printf '\n' ;;
  confirm) [[ \$(next) == yes ]] ;;
  *) printf '%s\n' "\$*" ;;
esac
SH
# The runner: logs its argv as one JSON line, then answers from the mode
# file, `fail <line>` for a refusal with that line and no other, and
# `install-failed` for a pair-add that kept the pair but could not install
# the units.
cat >"$plugin/bin/google-drive" <<SH
#!$(command -v bash)
$(command -v python3) -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$TMP_ROOT/calls"
mode=""
[[ -f "$TMP_ROOT/mode" ]] && mode="\$(<"$TMP_ROOT/mode")"
if [[ \$mode == fail* ]]; then
  [[ -n \${mode#fail} ]] && printf '%s\n' "\${mode#fail }" >&2
  exit 1
fi
case "\$1" in
  install) echo "installed=vgs-google-drive.timer changed=2" ;;
  authorize) echo "authorized=\$2" ;;
  pairs) printf 'docs\tDocuments\ninbox\tAgent uploads\n' ;;
  pairs-reset) echo "reset=pairs.json.damaged-20261011T091349Z" ;;
  pair-add)
    echo "added=x"
    [[ \$mode != install-failed ]] || echo "install=failed systemctl=missing" ;;
  pair-remove) echo "removed=\$2" ;;
  sign-out) echo "signed-out=\$2" ;;
esac
SH
chmod 755 "$tools/gum" "$plugin/bin/google-drive"

# tui SCRIPT MODE ANSWERS [ARGS...]: runs SCRIPT, a file under the plugin
# copy's tui/, with the runner in MODE and gum answering ANSWERS, one a
# line; the exit status in $status, the screen in $screen, the runner's
# calls as one JSON list in $calls.
tui() {
  local file="$1" mode="$2" answers="$3" command
  shift 3
  printf '%s' "$mode" >"$TMP_ROOT/mode"
  printf '%s\n' "$answers" >"$TMP_ROOT/answers"
  rm -f -- "$TMP_ROOT/answered" "$TMP_ROOT/calls"
  : >"$TMP_ROOT/calls"
  command="$(printf '%q ' bash "$file" "$@")"
  status=0
  # script(1) runs the command with $SHELL, else the login shell, which
  # need not read bash's quoting.
  env -i PATH="$tools" HOME="$home" SHELL="$tools/bash" TERM=dumb VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_ID=vgs.google-drive VGS_PLUGIN_DIR="$plugin" \
    script -qec "$command" /dev/null </dev/null >"$TMP_ROOT/screen" 2>&1 || status=$?
  if ! screen="$(tr -d '\r' <"$TMP_ROOT/screen")"; then fail "${file##*/}: the screen capture is unreadable"; exit 1; fi
  calls="$(python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1]) if l.strip()]))' "$TMP_ROOT/calls")"
}
shows() { [[ $screen == *"$1"* ]]; }
# The one pair-add call's definition as sorted JSON, else what it was.
defined() { python3 -c '
import json, sys
c = json.loads(sys.argv[1])
if len(c) != 1 or c[0][:2] != ["pair-add", "--definition"]:
    print("calls=" + sys.argv[1]); sys.exit()
try:
    print(json.dumps(json.loads(c[0][2]), sort_keys=True))
except ValueError:
    print("not-json " + c[0][2])' "$calls"; }

copy_scripts() { cp -- "$plugin_src"/tui/*.sh "$plugin/tui/"; }

# The cases, each a check on its runs: they return 1 on a miss. Each takes
# the plugin copy's script it runs, which a control replaces.
case_setup_installs() {
  tui "$1" "" ""
  [[ $status == 0 && $calls == '[["install"]]' ]] && shows "Google Drive syncs every hour while you are logged in."
}
case_setup_failure_reads_plainly() {
  tui "$1" "fail google-drive: refused: systemctl=failed args=daemon-reload exit=1" ""
  [[ $status == 1 ]] && shows "VGS could not set up the hourly sync." && ! shows "systemctl=failed" && grep -q -F "systemctl=failed" -- "$log"
}
case_connect_runs_its_direction() {
  tui "$plugin/tui/connect.sh" "" ""
  [[ $status == 0 && $calls == '[["authorize"]]' ]]
}
case_connect_reads_this_runs_refusal() {
  tui "$1" "fail google-drive: refused: credential=absent account=client-secret" ""
  [[ $status == 1 ]] && shows "Add the client ID and the client secret" || return 1
  # An earlier run's refusal stays in the log; this run's failure has none.
  tui "$1" "fail" ""
  [[ $status == 1 ]] && shows "VGS could not sign you in to Google." && ! shows "client secret"
}
case_add_pair_defines_the_answers() {
  tui "$1" "" "$(printf '%s\n' 'My "Docs" \ 2026' '/Docs/Taxes/' "$home/gdrive/")"
  [[ $status == 0 ]] || return 1
  [[ $(defined) == "$(python3 -c 'import json,sys; print(json.dumps({"id": "my-docs-2026", "label": "My \"Docs\" \\ 2026", "remote": "Docs/Taxes", "local": sys.argv[1] + "/gdrive"}, sort_keys=True))' "$home")" ]]
}
case_add_pair_refusal_reads_plainly() {
  tui "$1" "fail google-drive: refused: pair=docs rule=local-overlap" "$(printf '%s\n' Docs Inbox "$home/inbox")"
  [[ $status == 1 ]] && shows "This folder overlaps a folder of another folder pair." && ! shows "rule=local-overlap"
}
case_add_pair_pairs_invalid_refusal_reads_plainly() {
  tui "$1" "fail google-drive: refused: pairs=invalid pair=docs rule=local-overlap" "$(printf '%s\n' Docs Inbox "$home/inbox")"
  [[ $status == 1 && $(defined) != calls=* ]] && shows "Start the folder pair list again" && ! shows "pairs=invalid" && ! shows "rule=local-overlap"
}
case_add_pair_install_failure_reads_plainly() {
  tui "$1" "install-failed" "$(printf '%s\n' Docs Docs "$home/docs")"
  [[ $status == 1 && $(defined) != calls=* ]] && shows "VGS could not set up the hourly sync." && ! shows "install=failed" &&
    grep -q -x -F "install=failed systemctl=missing" -- "$log" || return 1
  tui "$1" "" "$(printf '%s\n' Docs Docs "$home/docs")"
  [[ $status == 0 ]] && ! shows "VGS could not set up the hourly sync."
}
case_remove_pair_removes_the_named_after_yes() {
  tui "$1" "" yes docs
  [[ $status == 0 && $calls == '[["pairs", "--lines"], ["pair-remove", "docs"]]' ]] && shows "Documents" || return 1
  tui "$1" "" no docs
  [[ $status == 0 && $calls == '[["pairs", "--lines"]]' ]] || return 1
  tui "$1" "" yes nope
  [[ $status == 1 && $calls == '[["pairs", "--lines"]]' ]] && grep -q -x -F "google-drive: refused: pair=unknown id=nope" -- "$log"
}
case_remove_pair_refuses_a_bad_id() {
  local long
  printf -v long '%257s' ''
  tui "$1" "" yes
  [[ $status == 2 && $calls == '[]' ]] || return 1
  tui "$1" "" yes "${long// /a}"
  [[ $status == 2 && $calls == '[]' ]] || return 1
  tui "$1" "" yes "${long:0:256}"
  [[ $status == 1 && $calls == '[["pairs", "--lines"]]' ]] || return 1
  tui "$1" "" yes $'docs\tx'
  [[ $status == 2 && $calls == '[]' ]]
}
case_reset_pairs_runs_after_yes() {
  tui "$1" "" yes
  [[ $status == 0 && $calls == '[["pairs-reset"]]' ]] && grep -q -x -F "reset=pairs.json.damaged-20261011T091349Z" -- "$log" || return 1
  tui "$1" "" no
  [[ $status == 0 && $calls == '[]' ]]
}
case_reset_pairs_reads_this_runs_refusal() {
  tui "$1" "fail google-drive: refused: pairs=valid" yes
  [[ $status == 0 ]] && ! shows "pairs=valid" || return 1
  tui "$1" "fail" yes
  [[ $status == 1 ]] && shows "The details are in" && ! shows "pairs=valid"
}
case_sign_out_runs_its_direction_after_yes() {
  tui "$plugin/tui/sign-out.sh" "" yes
  [[ $status == 0 && $calls == '[["sign-out"]]' ]] || return 1
  tui "$plugin/tui/sign-out.sh" "" no
  [[ $status == 0 && $calls == '[]' ]]
}
case_sign_out_reads_this_runs_refusal() {
  tui "$1" "fail google-drive: refused: credential=locked account=token" yes
  [[ $status == 1 ]] && shows "Your keyring is locked. Unlock it, then try again." && ! shows "credential=locked" || return 1
  tui "$1" "fail" yes
  [[ $status == 1 ]] && shows "VGS could not sign out of Google Drive." && ! shows "keyring is locked"
}
case_refuses_an_argument() {
  local script
  for script in setup add-pair connect sign-out; do
    tui "$plugin/tui/$script.sh" "" "" extra
    [[ $status == 2 && $calls == '[]' ]] || return 1
  done
  tui "$plugin/tui/reset-pairs.sh" "" "" extra
  [[ $status == 2 && $calls == '[]' ]] || return 1
  tui "$plugin/tui/remove-pair.sh" "" "" docs extra
  [[ $status == 2 && $calls == '[]' ]] || return 1
  true
}
CASES=(case_setup_installs:setup case_setup_failure_reads_plainly:setup case_connect_runs_its_direction:connect case_connect_reads_this_runs_refusal:connect
  case_add_pair_defines_the_answers:add-pair case_add_pair_refusal_reads_plainly:add-pair case_add_pair_pairs_invalid_refusal_reads_plainly:add-pair case_add_pair_install_failure_reads_plainly:add-pair
  case_remove_pair_removes_the_named_after_yes:remove-pair case_remove_pair_refuses_a_bad_id:remove-pair case_reset_pairs_runs_after_yes:reset-pairs case_reset_pairs_reads_this_runs_refusal:reset-pairs
  case_sign_out_runs_its_direction_after_yes:sign-out case_sign_out_reads_this_runs_refusal:sign-out
  case_refuses_an_argument:setup)
copy_scripts
for entry in "${CASES[@]}"; do
  case="${entry%%:*}"
  if "$case" "$plugin/tui/${entry#*:}.sh"; then ok "${case#case_}"; else fail "${case#case_}: status=$status calls=$calls screen=[${screen//$'\n'/ | }]"; fi
done

# Controls: a case, its script, the text in that script it needs, and a
# replacement without the rule.
CONTROL_CASES=(case_setup_installs case_connect_reads_this_runs_refusal case_add_pair_defines_the_answers case_add_pair_refusal_reads_plainly case_add_pair_pairs_invalid_refusal_reads_plainly case_add_pair_install_failure_reads_plainly
  case_remove_pair_removes_the_named_after_yes case_remove_pair_removes_the_named_after_yes case_remove_pair_refuses_a_bad_id case_remove_pair_refuses_a_bad_id case_reset_pairs_runs_after_yes case_reset_pairs_reads_this_runs_refusal case_sign_out_runs_its_direction_after_yes case_sign_out_reads_this_runs_refusal)
CONTROL_SCRIPTS=(setup connect add-pair add-pair add-pair add-pair remove-pair remove-pair remove-pair remove-pair reset-pairs reset-pairs sign-out sign-out)
CONTROL_NEEDLES=('"$runner" install >>"$log"' 'tail -c "+$((logged + 1))" -- "$log"' 's="${s//\"/\\\"}";' '*rule=local-overlap* | *rule=remote-overlap*)' '*pairs=invalid*)' "*\$'\\n'install=failed*"
  'vgs_tui_confirm "Remove this folder pair? Its files stay." || status=$?' '[[ $listed != "$id" ]] || label="$name"' '${#1} -le 256' '$1 != *[[:cntrl:]]*' '"$runner" pairs-reset' 'tail -c "+$((logged + 1))" -- "$log"' 'vgs_tui_confirm "Sign out of Google Drive?" || status=$?' '*credential=locked*)')
CONTROL_REPLACEMENTS=('true >>"$log"' 'cat -- "$log"' ':;' '*rule=no-such-rule*)' '*pairs=no-such*)' '*no-such*' 'true' 'label="$name"' '${#1} -le 999' 'true' 'true' 'cat -- "$log"' 'true' '*credential=no-such*)')
for i in "${!CONTROL_CASES[@]}"; do
  case="${CONTROL_CASES[i]}"
  script="$plugin/tui/${CONTROL_SCRIPTS[i]}.sh"
  copy_scripts
  if ! python3 - "$script" "${CONTROL_NEEDLES[i]}" "${CONTROL_REPLACEMENTS[i]}" <<'PY2'
import sys
path, needle, replacement = sys.argv[1:]
source = open(path).read()
if source.count(needle) != 1:
    sys.exit("control text occurs %d times: %s" % (source.count(needle), needle))
open(path, "w").write(source.replace(needle, replacement))
PY2
  then
    fail "control $case: its text must occur once"
  elif "$case" "$script"; then
    fail "control $case: passed on a copy without the rule"
  else
    ok "control $case"
  fi
done

if [[ $failures -gt 0 ]]; then
  printf 'test-google-drive-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-google-drive-tui: ok cases=%d controls=%d\n' "${#CASES[@]}" "${#CONTROL_CASES[@]}"
