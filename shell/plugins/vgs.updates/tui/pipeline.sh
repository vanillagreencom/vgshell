# shellcheck shell=bash
# tui/pipeline.sh: the Updates pipeline, sourced by tui/update.sh, which
# runs every source, and tui/update-source.sh, which runs one. Both hold one
# lock and one log and run the same steps in the same order; a source the
# run leaves out is skipped where its step would stand. bin/vgshell-tui runs
# both from a private copy of the plugin's snapshot, so bin/facts is beside
# this file's directory, and the VGS tree is the one VGS_TUI_LIB lies in.
# The order:
#
#   1. the log, script(1) into $XDG_STATE_HOME/vgshell/updates/update.log, then
#      the lock vgs-tui-updates; the run writes a file of its own that
#      becomes update.log once it holds the lock, so a second run refused
#      busy never truncates the log of the run it found
#   2. a warning when / has less than 10 GiB free
#   3. the plan box, then one question unless -y
#   4. the shared package owner prepares effective config, pending identities
#      and review before Updates' snapshot and credential session. Later
#      upgrade/rebuild steps consume their exact prepared authority once.
#   5. one sudo session, when the package layer's elevation command is
#      sudo and a snapshot or the system step needs root. That command is
#      the one `vgshell pkg plan upgrade <primary>` names, from shell.json's
#      `packages.elevate`, else the first of sudo, doas and run0 on PATH;
#      doas and run0 ask as their own rules say, as bin/lib/pkg-run.sh does
#   6. a snapshot through snapper or timeshift behind that command, before
#      any step that replaces a package: the system's, the AUR's or the
#      vgshell-git rebuild. None is taken when the plugin's `snapshot` setting
#      is off, when neither tool is on PATH or when no elevation command
#      resolves, and the plan box says which; a failed snapshot warns and
#      the update goes on
#   7. VGS itself: `vgshell self update` when `vgshell self status` names the
#      step `self`, a checkout or a curl install behind; a step of `none`
#      names its reason in the plan box and runs nothing
#   8. the system: `vgshell pkg run upgrade --manager <primary>`, which joins
#      the session
#   9. Flatpak and mise: `vgshell pkg run upgrade --manager flatpak|mise`
#  10. each plugin, then each theme, behind its upstream:
#      `vgshell plugin|theme update <id>`, which shows its diff and asks
#      [y/N]; `--yes` only when the `trustPluginUpdates` setting is on
#  11. the end of the sudo session, which drops the credential
#  12. the AUR, last, so no PKGBUILD runs under the update's credential:
#      the `aurCommand` setting's words, else `vgshell pkg run upgrade
#      --manager aur`, then `<helper> -S vgshell-git` when the status names
#      the step `rebuild`, installing paru from its AUR recipe first for
#      `install-helper`, since an AUR helper rebuilds a -git package only
#      when its recipe's version changes. A rebuild removes the record
#      $(updates_state_dir)/rebuild-failed.json before it runs and, when it
#      fails, writes it: `{ current, helper, exit, conflict }`, the package
#      version it replaced, the helper, its exit status and the first
#      package pacman's `:: <a> and <b> are in conflict` line names, or
#      null. The helper asks sudo itself, so the
#      phase runs under tui.sh's sudo guard: the credential it caches is
#      dropped when the phase ends, fails or is interrupted
#  13. pacman's orphaned packages, removed only on a yes, default no, after
#      a system or AUR upgrade
#  14. a shell restart when a package step or the rebuild replaced the VGS
#      package
#  15. a check request to refresh the widget and window
#  16. a reboot question when the run changed a package, by pacman -Q
#      before the first package step and after the last, that the CachyOS
#      reboot hook names under its script's conditions
#      (UpdatesLogic.rebootPackages through bin/facts reboot), or the
#      kernel or the running Hyprland was replaced (tui.sh's
#      vgs_tui_reboot_check)
#  17. the result list, then the failure count and failed parts: the last
#      output names each failed part, its cause and its next step
#
# The package steps are the package-manager table's own plans, read with
# `vgshell pkg plan` and run with `vgshell pkg run`: they take no -y, so each
# manager asks its own questions in this terminal. -y answers only the
# pipeline's own start question; the orphan and reboot questions are then
# reported instead of asked, and the review's questions are still asked.
# A source step (7 to 10 and 12) that fails records its cause, read from
# its output (_updates_cause_of), and the run goes on with the next; a run with
# a failed step exits 1 after the reboot question. After a failed or
# declined system step the AUR step and the vgshell-git rebuild are
# skipped, since they build against the system that step left. A package a
# declined or failed AUR transaction leaves out is not retried by the VGS
# rebuild: that rebuild is skipped too, including helper installation.
# A step a Ctrl-C ended ends the run with 130. Any other failing step ends
# the run:
# the ERR trap prints `updates: failed exit=<n> log=<file>` and how to
# recover, and the session's or the guard's EXIT trap drops the credential.
#
# Every refusal prints `updates: refused: <key>=<value>` first. A bad
# invocation exits 2; a held lock exits 75.

# The ERR trap needs errtrace, so the file sets the mode its steps rely on
# whichever entry script sources it.
set -Eeuo pipefail
# Character classes spelled out: the user's locale collates a range.
_updates_digits='^[0123456789]+$'
_updates_usage="usage: update.sh [-y] | update-source.sh <source> [-y]"
# The CachyOS reboot hook, in the system hook directory pacman reads under
# its RootDir; a link of that name in /etc/pacman.d/hooks, which the
# reboot-notice system step makes, turns the hook off but not this read.
_updates_reboot_hook=usr/share/libalpm/hooks/cachyos-reboot-required.hook

_updates_diagnostic() { # RAW_LINE
  local dir
  dir="$(updates_state_dir)"
  mkdir -p -- "$dir"
  printf '%s\n' "$1" >>"$dir/diagnostics.log"
}

_updates_refuse() { # STATUS FIRST_LINE [ENGLISH...]
  local status="$1"
  if [[ -z ${VGS_TUI_LIB:-} ]]; then
    printf 'updates: refused: %s\n' "$2" >&2
  else
    _updates_diagnostic "updates: refused: $2"
    case "$2" in
      log=absent*) printf 'No update has run yet. There is no log to show.\n' >&2 ;;
      pager=missing) printf 'The log reader is unavailable. Open Updates to try again.\n' >&2 ;;
      source=missing) printf 'No update source was selected. Open Updates and choose a source.\n' >&2 ;;
      *reason=absent) printf 'This update source is not installed. Choose another source.\n' >&2 ;;
      *reason=no-plan) printf 'VGS cannot update this source. Choose another source.\n' >&2 ;;
      *) printf 'This update request is invalid. Open Updates and try again.\n' >&2 ;;
    esac
  fi
  exit "$status"
}

# The recovery message, printed once by the pipeline's own process: with
# errtrace a failing command inside a substitution runs the trap there too.
_updates_failed() { # STATUS
  [[ $BASHPID == "${_updates_pid:-}" ]] || return 0
  _updates_diagnostic "updates: failed exit=$1 log=$_updates_log"
  _updates_recheck failed
  vgs_tui_failed "$_updates_log" "The update stopped. Read the output above and try again from Updates." \
    "Select Open last log in Updates to read this run's output."
}

# Runs ARGV from $HOME, as vgshell pkg run runs its steps, so a project's
# configuration in the caller's directory changes nothing.
_updates_run() { # ARGV...
  (cd -- "$HOME" && "$@")
}

_updates_install_helper() { env -u VGS_PACKAGE_TRANSACTION "$_updates_vgshell" pkg ensure-helper; }

# pacman parses CLI HookDir before configured directories. A configuration
# ending in our HookDir wins by filename while retaining every other hook.
# alpm-hooks(5), pacman/conf.c setup_libalpm and libalpm/hook.c.
# The pipeline retains each effective configuration from before review through
# the exact corresponding mutation. No helper discovers a new config in a
# live credential session.
_updates_pacman_prepare() { # KEY HELPER ARGV...
  local key="$1" helper="$2" original dirs value generated
  shift 2
  original="$(node "$_updates_tree/bin/lib/pkg-config.js" "$helper" "$@" | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0,"utf8")).config)')" || return 1
  generated="$VGS_PACKAGE_TRANSACTION/$key.conf"
  dirs="$(pacman-conf --config "$original" HookDir)" || return 1
  mkdir -p -- "$VGS_PACKAGE_TRANSACTION/hooks"
  [[ -L $VGS_PACKAGE_TRANSACTION/hooks/cachyos-reboot-required.hook ]] || ln -s -- /dev/null "$VGS_PACKAGE_TRANSACTION/hooks/cachyos-reboot-required.hook"
  {
    printf '[options]\nInclude = %s\n[options]\n' "$original"
    while IFS= read -r value; do [[ -z $value ]] || printf 'HookDir = %s\n' "$value"; done <<<"$dirs"
    printf 'HookDir = %s/hooks\n' "$VGS_PACKAGE_TRANSACTION"
  } >"$generated"
  chmod 600 -- "$generated"
  _updates_package_configs["$key"]="$generated"
}

_updates_pacman_run() { # CONFIG_KEY PACKAGE_OWNER_ARGV...
  local key="$1"
  shift
  if [[ $1 == "$_updates_vgshell" ]]; then
    (cd -- "$HOME" && "$@")
  else
    local prepared words=()
    prepared="$(node "$_updates_tree/bin/lib/pkg-config.js" --apply "${_updates_package_configs[$key]}" "$1" "$@")" || return 1
    prepared="$(node -e 'for(const word of JSON.parse(process.argv[1]).argv)console.log(word)' "$prepared")" || return 1
    mapfile -t words <<<"$prepared"
    [[ ${#words[@]} -gt 0 && -n ${words[0]} ]] || return 1
    (cd -- "$HOME" && "${words[@]}")
  fi
}

_updates_package_cleanup() {
  [[ -z ${VGS_PACKAGE_TRANSACTION:-} ]] || rm -rf -- "${VGS_PACKAGE_TRANSACTION:?}"
}

_updates_package_review() { # PACMAN AUR REBUILD HELPER CUSTOM_ARGV...
  local system="$1" aur="$2" rebuild="$3" helper="$4" request result status=0 value
  shift 4
  declare -gA _updates_package_configs=()
  [[ $system != 1 ]] || _updates_pacman_prepare pacman pacman
  if [[ $aur == 1 || $rebuild == 1 ]] && [[ -n $helper ]]; then _updates_pacman_prepare aur "$helper"; fi
  if [[ $# != 0 ]]; then _updates_pacman_prepare custom "$1" "$@"; fi
  request="$VGS_PACKAGE_TRANSACTION/request.json" result="$VGS_PACKAGE_TRANSACTION/result.json"
  node - "$request" "$result" "$system" "$aur" "$rebuild" "$helper" "${_updates_package_configs[pacman]:-}" "${_updates_package_configs[aur]:-}" "${_updates_package_configs[custom]:-}" "$@" <<'JS'
const fs=require("node:fs");
const [request,result,system,aur,rebuild,helper,systemConfig,aurConfig,customConfig,...custom]=process.argv.slice(2);
const groups=[];
if(system==="1")groups.push({manager:"pacman",names:[],installs:[],ignored:[],config:systemConfig});
if(aur==="1")groups.push({manager:"aur",names:[],installs:[],ignored:[],config:customConfig||aurConfig||null});
const data={version:1,mode:"upgrade",action:"upgrade",groups,sources:groups.map(g=>g.manager),rebuild:rebuild==="1"?["vgshell-git"]:[],config:aurConfig||customConfig||systemConfig||null,customAurArgv:custom.length?custom:null};
fs.writeFileSync(request,JSON.stringify(data),{flag:"wx",mode:0o600});
fs.writeFileSync(result,"",{flag:"wx",mode:0o600});
JS
  "$_updates_vgshell" pkg review --request "$request" --result "$result" || status=$?
  [[ $status == 0 ]] || exit "$status"
  value="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1]));if(r.version!==1)process.exit(1);process.stdout.write(r.decision)' "$result")" || return 1
  case "$value" in proceed) ;; stop) exit 0 ;; cancelled) exit 130 ;; *) return 1 ;; esac
  _updates_package_receipt="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1])).receipt||"")' "$result")" || return 1
  [[ -n $_updates_package_receipt ]] || return 1
  value="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1])).skipped.join("\n"))' "$result")" || return 1
  while IFS= read -r name; do
    [[ -z $name ]] || { _updates_skip_aur+=("$name"); _updates_skip_repo+=("$name"); _updates_results+=("$name skipped. Review excluded this package."); }
  done <<<"$value"
}

# FILE's text without SGR escapes, and of each line only what follows its
# last carriage return, as the terminal showed it.
_updates_plain() { # FILE
  LC_ALL=C sed -E -e $'s/\e\\[[0-9;:?]*[ -/]*[@-~]//g' -e $'s/\r+$//' -e $'s/^.*\r//' -- "$1"
}

# The lines a tool starts a failure with, once SGR escapes and leading
# space are gone: pacman's `error: `, which its pm_printf writes to stderr
# before an ALPM_LOG_ERROR message (src/pacman/util.c). A failed commit
# prints it before the conflicting files and its stdout line `Errors
# occurred, no packages were upgraded.` (src/pacman/sync.c,
# sync_prepare_execute), and a step's output mixes such lines with its
# progress and summary lines, which never name the cause.
_updates_error_line='^[[:space:]]*error:[[:space:]]'
# What the terminal echoes after a [Y/n] or [y/N] question when the user
# answers it: nothing, for Enter, else a yes or a no.
_updates_answer='^[[:space:]]*([YyNn]|[Yy][Ee][Ss]|[Nn][Oo])?[[:space:]]*$'
# The scan line `vgshell pkg run` prints on stdout after its steps however
# they ended (bin/vgshell-pkg rescanShell, bin/vgshell rescan_if_running).
# It closes the run's block, as its `rescan=` refusal does, and is never
# the step's own text; a question its manager left unanswered can precede
# it on its line.
_updates_scan_line='(^|[[:space:]])shell=(rescan-started|rescan-queued|not-running)[[:space:]]*$'

# The cause of a failed step from its output in FILE, stdout and stderr in
# the order the terminal showed them with the answers the user typed, once
# SGR escapes and carriage returns are gone. VGS prints a `vgshell:
# refused:` or `vgs-tui: refused:` key line and English after it. A
# question and its answer can precede the key on its line, as `vgshell
# plugin update`'s [y/N] does, and that text is never a cause. With a key
# line the cause is the last line after the last one, else its value, such
# as git's message after a `fetch=` refusal. `vgshell pkg run`'s closing
# block, a `rescan=` refusal after its steps, is the exception: there the
# cause is the last error line the steps printed before it, else their last
# line. Its other closing line, the scan line, is read as no line at all.
# Without a key line it is the last error line, else the last line
# that holds text. A question the step printed text after, with no answer
# echoed, gives that text instead. Sets _updates_cause, and
# _updates_declined to 1 when the user said no: the `declined=` refusal of
# `vgshell plugin|theme update`, or a step whose own text ends on a [Y/n]
# or [y/N] question answered no or left unanswered, as pacman and an AUR
# helper leave one. Also sets _updates_next for the result line's action.
_updates_cause_of() { # FILE
  local line rest out last="" fault="" keyed=0 value="" held="" held_fault="" tail="" after="" own=""
  _updates_declined=0
  out="$(_updates_plain "$1")"
  while IFS= read -r line; do
    if [[ $line =~ (^|[[:space:]])(vgshell|vgs-tui):\ refused:\ (.*)$ ]]; then
      value="${BASH_REMATCH[3]}"
      [[ $value != declined=* ]] || _updates_declined=1
      tail="${line:0:${#line}-${#BASH_REMATCH[0]}}"
      keyed=1 held="$last" held_fault="$fault" after=""
    elif [[ -n ${line//[[:space:]]/} ]]; then
      if [[ $line =~ $_updates_scan_line ]]; then
        line="${line:0:${#line}-${#BASH_REMATCH[0]}}"
        [[ -n ${line//[[:space:]]/} ]] || continue
      fi
      if [[ $line =~ \[(Y/n|y/N)\]:?[[:space:]]+(.*[^[:space:]].*)$ ]]; then
        rest="${BASH_REMATCH[2]}"
        [[ $rest =~ $_updates_answer ]] || line="$rest"
      fi
      last="$line" after="$line"
      if [[ $line =~ $_updates_error_line ]]; then fault="$line"; fi
    fi
  done <<<"$out"
  if [[ $keyed == 0 ]]; then
    own="$last" _updates_cause="${fault:-$last}"
  elif [[ $value == rescan=* ]]; then
    own="${tail:-$held}" _updates_cause="${held_fault:-${held:-${after:-$value}}}"
  else
    _updates_cause="${after:-$value}"
  fi
  if [[ $own =~ \[(Y/n|y/N)\]:?(.*)$ ]]; then
    rest="${BASH_REMATCH[2]}"
    if [[ $rest =~ $_updates_answer && $rest != *[Yy]* ]]; then _updates_declined=1; fi
  fi
  _updates_next="update again; if it fails again, the log names the cause. Select Open last log in Updates."
  # VGS's theme refusal and makepkg's build errors can precede a closing
  # line such as Aborting, so map the whole output the step supplied.
  case "$out" in
    *"another theme command holds the theme lock"*)
      _updates_cause="Another theme change is still running."
      _updates_next="wait for it to finish, then update again from the Updates panel."
      ;;
    *"A failure occurred in pkgver()"*)
      _updates_cause="The package could not determine its version."
      _updates_next="update again from the Updates panel."
      ;;
    *"A failure occurred in build()"*|*"failed to build"*)
      _updates_cause="A package could not be built."
      _updates_next="update again from the Updates panel."
      ;;
  esac
}

# The OSC number of the marks around a step's output: one no terminal
# handles, so the terminal draws nothing for them and the log's cleaner
# drops them. Checked against the OSC tables of foot (osc.c
# osc_dispatch), kitty (vt-parser.c dispatch_osc) and Ghostty
# (terminal/osc.zig) on 2026-10-17: each discards an unknown OSC, and
# kitty also logs it as an unknown escape code.
_updates_mark_osc=8913
# How long a step's end mark may take to reach the transcript after the
# step exits, in seconds: a ceiling far above the wait measured with this
# function's tail and awk under vgs_tui_log, 200 marks each after 48 KiB
# of output, p50 5.7 ms, p99 17 ms, max 18.7 ms (a scratch timing run on
# the development host, 2026-10-17).
_updates_mark_ceiling=10

# Writes the step's output, between the marks named NONCE, from the run's
# transcript at byte FROM on into the cause file. The end mark is written
# here, after the step exited, so every byte the step wrote to the
# terminal precedes it on the one pty, and once the mark is in the
# transcript, so is all of that. GNU tail -f follows the file by inotify,
# so the wait is a read, not a poll. awk splits the stream at BEL, the
# byte that ends a mark, and sees the mark when its BEL arrives; grep
# matches only whole lines, and nothing follows the mark until the cut
# ends. Returns 1 with _updates_unread set,
# absent when the transcript was not there, late when the end mark did not
# arrive within the ceiling, lost when a mark is not in what arrived,
# copy-failed when the copy failed.
_updates_cut() { # FROM NONCE
  local from="$1" transcript="${VGS_TUI_TRANSCRIPT:-}" start end at mark first="" last="" follow follower arrived=1
  _updates_unread=copy-failed
  printf -v start '\e]%s;vgs-step;%s;start\a' "$_updates_mark_osc" "$2"
  printf -v end '\e]%s;vgs-step;%s;end\a' "$_updates_mark_osc" "$2"
  printf '%s' "$end"
  if [[ -z $from || ! -f $transcript ]]; then _updates_unread=absent; return 1; fi
  exec {follow}< <(exec timeout "$_updates_mark_ceiling" tail -c "+$((from + 1))" -f -- "$transcript")
  follower=$!
  LC_ALL=C awk -v RS='\a' -v mark="${end%$'\a'}" 'index($0, mark) { seen = 1; exit } END { exit !seen }' <&"$follow" || arrived=0
  exec {follow}<&-
  kill "$follower" 2>/dev/null || :
  wait "$follower" 2>/dev/null || :
  if [[ $arrived == 0 ]]; then _updates_unread=late; return 1; fi
  # grep -b prints each mark's byte offset from FROM.
  while IFS=: read -r at mark; do
    if [[ $mark == "$start" && -z $first ]]; then first="$at"
    elif [[ $mark == "$end" ]]; then last="$at"
    fi
  done < <(tail -c "+$((from + 1))" -- "$transcript" | LC_ALL=C grep -a -b -o -F -e "$start" -e "$end")
  if [[ -z $first || -z $last ]] || (( last < first )); then _updates_unread=lost; return 1; fi
  head -c "$((from + last))" -- "$transcript" | tail -c "+$((from + first + ${#start} + 1))" >"$_updates_cause_file"
}

# Runs one source step, ARGV, and adds its result to _updates_results as
# `LABEL <result>.`: installed; skipped when the user declined it; failed
# with its cause and next step, else `exit <n>`. _updates_outcome is installed,
# declined or failed, and _updates_exit the step's exit status. The run goes
# on after a failure, so neither errexit nor the ERR trap sees it.
#
# The step keeps the run's terminal on stdin, stdout and stderr, so a
# manager asks its questions, and both its output streams reach the
# terminal through one pty in the order it wrote them. A stderr that is
# not the terminal splits a sudo'd step's output: under sudo's use_pty,
# on by default since sudo 1.9.14 (sudoers(5)), sudo runs the command on a
# pty of its own, relays that pty to /dev/tty and passes a standard stream
# that is not the user's tty to the command unchanged (sudo src/exec_pty.c,
# exec_pty: "Read from pty leader, write to /dev/tty"; "Not logging
# stderr, do not interpose"). pacman's size summary on stdout then waited
# in sudo's relay while its [Y/n] on stderr reached the terminal first. The
# cause file is cut from the run's transcript, which vgs_tui_log's
# script(1) keeps, between a start mark written before the step and an end
# mark written after it; only a failed step's output is cut, and the file
# is whole when it is read. A closed window hangs up the run's pty, and a
# write to a pty whose master is closed fails with EIO and raises no
# signal (a Python os.write on Linux 7.2, 2026-10-17), so a step such as
# pacman still reaches the end of its transaction and unlocks its database
# instead of dying by SIGPIPE. A step a Ctrl-C ended, 130, ends the run.
_updates_source() { # ID LABEL ARGV...
  local id="$1" label="$2" status=0 from="" nonce="$BASHPID.$SRANDOM$SRANDOM"
  shift 2
  from="$(stat -c %s -- "${VGS_TUI_TRANSCRIPT:-}" 2>/dev/null)" || from=""
  printf '\e]%s;vgs-step;%s;start\a' "$_updates_mark_osc" "$nonce"
  "$@" || status=$?
  _updates_exit="$status"
  if [[ $status -eq 0 ]]; then
    _updates_outcome=installed
    _updates_results+=("$label installed.")
    return 0
  fi
  if [[ $status -eq 130 ]]; then
    _updates_diagnostic "updates: stopped source=$id exit=$status"
    exit "$status"
  fi
  : >"$_updates_cause_file"
  if _updates_cut "$from" "$nonce"; then
    _updates_cause_of "$_updates_cause_file"
  else
    _updates_diagnostic "updates: transcript=unread source=$id reason=$_updates_unread"
    _updates_declined=0
    _updates_cause="VGS could not read this step's output."
    _updates_next="select Open last log in Updates to read the step's output."
  fi
  if [[ $_updates_declined == 1 ]]; then
    _updates_outcome=declined
    _updates_results+=("$label skipped. You declined it.")
    return 0
  fi
  _updates_outcome=failed
  _updates_diagnostic "updates: failed source=$id exit=$status"
  if [[ $id == aur ]]; then label="AUR packages"
  elif [[ $label == System ]]; then label="System packages"
  fi
  local cause="${_updates_cause:-exit $status}"
  [[ $cause == *[.!?] ]] || cause+="."
  _updates_results+=("$label failed. $cause Next: $_updates_next")
  _updates_failed_parts+=("$label")
  _updates_failures=$((_updates_failures + 1))
  vgs_tui_warn "$label failed. The rest of the update goes on."
}

# The shared TUI word wrapper owns line breaks. Reserve PREFIX's columns
# on every line so continuations start under the text after the part name.
_updates_result() { # WIDTH PREFIX TEXT [SGR]
  local width="$1" prefix="$2" text="$3" sgr="${4:-}" line lines=()
  width=$((width - ${#prefix}))
  (( width > 0 )) || width=1
  _vgs_tui_lines lines "$width" "$text"
  for line in "${lines[@]}"; do
    printf '%*s%s%s%s' "$_vgs_tui_edge" '' "$sgr" "$prefix" "$line"
    [[ -z $sgr ]] || printf '\033[0m'
    printf '\n'
    printf -v prefix '%*s' "${#prefix}" ''
  done
}

# The record of a failed vgshell-git rebuild, as the header states: the
# installed version CURRENT, the HELPER and its EXIT status, and the first
# package of pacman's conflict line in the step's output, the cause file.
# pacman prints its conflict question on stderr as `:: <name>-<version> and
# <name>-<version> are in conflict...`, and a version holds no hyphen but
# the one before its release, so the name is the word without its last two
# hyphenated parts. Written by rename, so the service never reads half.
_updates_rebuild_failed() { # CURRENT HELPER EXIT
  local file conflict=null line
  file="$(updates_state_dir)/rebuild-failed.json"
  while IFS= read -r line; do
    if [[ $line =~ (^|[[:space:]])::\ ([^[:space:]]+-[^[:space:]-]+-[^[:space:]-]+)\ and\ [^[:space:]]+\ are\ in\ conflict ]]; then
      conflict="\"$(_updates_json_text "${BASH_REMATCH[2]%-*-*}")\""
      break
    fi
  done < <(_updates_plain "$_updates_cause_file")
  printf '{"current":"%s","helper":"%s","exit":%s,"conflict":%s}\n' "$(_updates_json_text "$1")" "$(_updates_json_text "$2")" "$3" "$conflict" >"$file.part"
  mv -f -- "$file.part" "$file"
}
# TEXT with JSON's two escapes a string needs here: bin/facts refuses a
# control character in the values this takes.
_updates_json_text() { # TEXT
  local text="${1//\\/\\\\}"
  printf '%s' "${text//\"/\\\"}"
}

# The directory a run writes its log in, and the last run's log in it,
# which tui/log.sh shows.
updates_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/updates"
}
updates_log_file() {
  printf '%s\n' "$(updates_state_dir)/update.log"
}

# bin/facts VERB [SOURCE] on the answer on stdin.
_updates_facts() {
  "$_updates_facts_bin" "$_updates_loader" "$@"
}

# `vgshell pkg plan upgrade ID`: sets _updates_plan_text, the steps joined by
# `; `, and _updates_plan_elevator, the elevation command the steps run
# behind, empty when they need none or none resolves; or returns 1 with the
# refusal's first line in _updates_plan_text. A refusal that leaves no
# elevator, the elevator's or the plan's own, is in
# _updates_plan_elevator_refused.
_updates_plan() { # ID
  local out facts key value
  _updates_plan_text=""
  _updates_plan_elevator=""
  _updates_plan_elevator_refused=""
  if ! out="$("$_updates_vgshell" pkg plan upgrade "$1" 2>&1)"; then
    _updates_plan_text="${out%%$'\n'*}"
    _updates_plan_elevator_refused="$_updates_plan_text"
    return 1
  fi
  facts="$(_updates_facts plan <<<"$out")"
  while read -r key value; do
    case "$key" in
      elevator) _updates_plan_elevator="$value" ;;
      elevator-refused) _updates_plan_elevator_refused="$value" ;;
      step) _updates_plan_text+="${_updates_plan_text:+; }$value" ;;
    esac
  done <<<"$facts"
}

# The snapshot tool on PATH: snapper, else timeshift; 1 when neither is.
_updates_snapshot_tool() {
  if command -v snapper >/dev/null; then echo snapper
  elif command -v timeshift >/dev/null; then echo timeshift
  else return 1
  fi
}

# One snapshot per snapper configuration, or one timeshift snapshot, each
# command behind ELEVATOR. A tool with nothing configured takes none and
# says so: a quiet success would read as a snapshot the next update could
# roll back to.
_updates_snapshot() { # snapper|timeshift ELEVATOR
  local tool="$1" elevator="$2" csv config configs=() first=1
  case "$tool" in
    snapper)
      csv="$("$elevator" snapper --csvout list-configs)" || return
      while IFS=, read -r config _; do
        if [[ $first == 1 ]]; then first=0; continue; fi
        [[ -z $config ]] || configs+=("$config")
      done <<<"$csv"
      if [[ ${#configs[@]} -eq 0 ]]; then
        vgs_tui_warn "snapper has no configuration, so no snapshot was taken."
        return 1
      fi
      vgs_tui_step "Taking a snapshot"
      for config in "${configs[@]}"; do
        "$elevator" snapper -c "$config" create -c number -d "VGS update" || return
        "$elevator" snapper -c "$config" cleanup number || return
      done
      ;;
    timeshift)
      if [[ ! -f /etc/timeshift/timeshift.json ]]; then
        vgs_tui_warn "timeshift is not set up, so no snapshot was taken."
        return 1
      fi
      vgs_tui_step "Taking a snapshot"
      "$elevator" timeshift --create --comments "VGS update" --scripted || return
      ;;
    *) _updates_diagnostic "updates: snapshot-tool=$tool"; vgs_tui_error "The snapshot tool is not supported."; return 1 ;;
  esac
}

# The version of the package that owns the VGS tree, or nothing when no
# package owns it, as for a checkout, a curl install or a Nix tree, whose
# owner query refuses.
_updates_vgs_package_version() {
  local out facts key value
  out="$("$_updates_vgshell" pkg owner "$_updates_tree/VERSION" 2>/dev/null)" || return 0
  facts="$(_updates_facts owner <<<"$out")"
  while read -r key value; do
    if [[ $key == version ]]; then printf '%s' "$value"; fi
  done <<<"$facts"
}

# The plugins or themes behind their upstream, into _updates_behind; a
# checkout whose probe failed warns, and a probe that failed as a whole
# skips the source.
_updates_outdated() { # plugin|theme SOURCE
  local out facts key value
  _updates_behind=()
  if ! out="$("$_updates_vgshell" "$1" outdated --json)"; then
    _updates_diagnostic "updates: skipped=$2 reason=outdated-failed"; vgs_tui_warn "Could not check $2 for updates. This step was skipped."
    return 0
  fi
  facts="$(_updates_facts outdated "$2" <<<"$out")"
  while read -r key value; do
    case "$key" in
      update) _updates_behind+=("$value") ;;
      error) _updates_diagnostic "$2: $value"; vgs_tui_warn "Could not check one of the $2 for updates." ;;
    esac
  done <<<"$facts"
}

_updates_update_each() { # plugin|theme ID...
  local kind="$1" id
  shift
  for id in "$@"; do
    vgs_tui_step "Updating the $kind $id"
    _updates_source "$kind:$id" "${kind^} $id" "$_updates_vgshell" "$kind" update "${_updates_yes_flag[@]}" "$id"
  done
}

_updates_orphans() {
  local out status=0 orphans=()
  out="$(pacman -Qtdq)" || status=$?
  # pacman -Qtdq exits 1 when no package is orphaned.
  if [[ $status -eq 1 && -z $out ]]; then return 0; fi
  if [[ $status -ne 0 ]]; then
    _updates_diagnostic "updates: orphans=unreadable exit=$status"; vgs_tui_warn "Could not check for unused packages. Package removal was skipped."
    return 0
  fi
  mapfile -t orphans <<<"$out"
  vgs_tui_step "Orphaned packages"
  printf '  %s\n' "${orphans[@]}"
  if [[ $_updates_yes == 1 ]]; then
    printf 'The unused packages were kept. Open Updates to review them.\n'
    return 0
  fi
  status=0
  vgs_tui_confirm "Remove ${#orphans[@]} orphaned package(s)?" --default=false || status=$?
  case "$status" in
    0) "$_updates_vgshell" pkg run remove --manager pacman "${orphans[@]}" || { _updates_diagnostic "updates: orphans=remove-failed exit=$?"; vgs_tui_warn "Could not remove the unused packages. Try again from Updates."; } ;;
    1) echo "Keeping the orphaned packages." ;;
    *) exit "$status" ;;
  esac
}

_updates_recheck() {
  local reply status polls=0 line unavailable
  # restart waits for core `shell guarded`, while ServiceGate builds the
  # plugin services after the bars. A package rescan can also replace this
  # service. Wait for its registered check handler, not just the core PID.
  while :; do
    status=0
    reply="$("$_updates_vgshell" ipc call "$VGS_PLUGIN_ID" invoke check '' 2>&1)" || status=$?
    if [[ $status == 0 && ( $reply == started || $reply == queued ) ]]; then return 0; fi
    # bin/vgshell emits its keyed refusal after qs's output, followed by
    # an explanation. Consume that CLI contract, not the bare qs message.
    unavailable=0
    while IFS= read -r line; do
      case "$line" in
        "vgshell: refused: ipc=$VGS_PLUGIN_ID.invoke reason=target-not-found"|'vgshell: refused: shell=not-running '*) unavailable=1 ;;
      esac
    done <<<"$reply"
    if [[ $status != 69 || $unavailable != 1 ]] || ((polls >= 300)); then break; fi
    sleep 0.2
    polls=$((polls + 1))
  done
  if [[ $status -ne 0 || ( $reply != started && $reply != queued ) ]]; then
    _updates_diagnostic "updates: recheck=failed exit=$status reply=${reply%%$'\n'*}"
  fi
}

# Logs DIAGNOSTIC, a read the reboot question needs that failed, and warns
# once a run that the question may leave packages out.
_updates_reboot_unread() { # DIAGNOSTIC
  _updates_diagnostic "$1"
  [[ $_updates_reboot_warned == 0 ]] || return 0
  _updates_reboot_warned=1
  vgs_tui_warn "Could not check which updates need a restart."
}

# Sets _updates_core to the packages of CHANGES, `upgrade <name>` and
# `install <name>` lines, that need a reboot: the ones the CachyOS reboot
# hook names, as its script judges them with the running kernel and the
# mounted file systems (UpdatesLogic.rebootPackages through bin/facts
# reboot). Without the hook none does. A read that fails warns through
# _updates_reboot_unread, and a failed judgement leaves the list empty, so
# the run still ends with its result.
_updates_reboot_packages() { # CHANGE...
  local root hook=- mounts="" facts key value status=0
  _updates_core=()
  if root="$(pacman-conf RootDir)"; then
    [[ ! -f ${root%/}/$_updates_reboot_hook ]] || hook="${root%/}/$_updates_reboot_hook"
  else
    _updates_reboot_unread "updates: reboot-hook=unread exit=$?"
  fi
  mounts="$(findmnt -rno FSTYPE)" || { _updates_reboot_unread "updates: mounts=unread exit=$?"; mounts=""; }
  facts="$({
    printf '%s\n' "$@"
    while read -r value; do [[ -z $value ]] || printf 'mounted %s\n' "$value"; done <<<"$mounts"
  } | _updates_facts reboot "$hook" /proc/version)" || status=$?
  if [[ $status -ne 0 ]]; then
    _updates_reboot_unread "updates: reboot-packages=failed exit=$status"
    return 0
  fi
  while read -r key value; do
    if [[ $key == reboot ]]; then _updates_core+=("$value"); fi
  done <<<"$facts"
}

# The reboot question, one confirmation, default Later: CORE are the
# packages _updates_reboot_packages kept of those the run changed, and
# tui.sh's check adds a replaced kernel or running Hyprland. Under -y the
# reasons are printed instead.
_updates_reboot() { # CORE...
  local out status=0 reason reasons=() names=""
  if [[ $# -gt 0 ]]; then
    for reason; do names+="${names:+, }$reason"; done
    reasons+=("The run updated $names, which $([[ $# -eq 1 ]] && echo takes || echo take) effect after a reboot.")
  fi
  out="$(vgs_tui_reboot_check)" || status=$?
  case "$status" in
    0)
      while read -r reason; do
        case "$reason" in
          reboot=kernel) reasons+=("The kernel was updated.") ;;
          reboot=hyprland) reasons+=("Hyprland was updated.") ;;
        esac
      done <<<"$out"
      ;;
    1) ;;
    *) _updates_diagnostic "updates: reboot-check=failed exit=$status"; vgs_tui_warn "Could not check whether a restart is needed." ;;
  esac
  [[ ${#reasons[@]} -gt 0 ]] || return 0
  if [[ $_updates_yes == 1 ]]; then
    printf '%s Reboot when you are ready.\n' "${reasons[*]}"
    return 0
  fi
  status=0
  vgs_tui_confirm "${reasons[*]} Reboot now?" --affirmative=Reboot --negative=Later --default=false || status=$?
  case "$status" in
    0) "$_updates_vgshell" power reboot ;;
    1) echo "Reboot later to run the updated system." ;;
    *) exit "$status" ;;
  esac
}

# Whether WORD is one of the rest.
_updates_in() { # WORD LIST...
  local word="$1" item
  shift
  for item in "$@"; do [[ $item == "$word" ]] && return 0; done
  return 1
}

# updates_main all ARG... | updates_main source SOURCE ARG...: the pipeline
# over every source, or over SOURCE alone, named as a status row names it:
# the primary manager's id, aur, flatpak, mise, vgs, plugins or themes. The
# ARGs after SOURCE are -y alone; update-source.sh passes its SOURCE twice,
# once here and once among the entry script's own ARGs, which the log runs
# it again with.
_updates_main() {

  local state
  state="$(updates_state_dir)"
  _updates_log="$(updates_log_file)"
  if [[ ${VGS_TUI_LOGGED:-} != 1 ]]; then
    mkdir -p -- "$state"
    export UPDATES_LOG_PART="$state/.update.$$.log"
  fi
  vgs_tui_log "$UPDATES_LOG_PART" "${entry_args[@]}"
  local status=0
  vgs_tui_lock updates || status=$?
  if [[ $status -ne 0 ]]; then
    rm -f -- "$UPDATES_LOG_PART"
    exit "$status"
  fi
  mv -f -- "$UPDATES_LOG_PART" "$_updates_log"
  _updates_pid=$BASHPID
  trap '_updates_failed $?' ERR
  # The result list, the failed steps' count, whether a reboot read warned,
  # and the file a failed source step's output is cut into: one file, since
  # the lock holds one run at a time.
  _updates_results=() _updates_failed_parts=() _updates_failures=0 _updates_reboot_warned=0
  _updates_cause_file="$state/.step-output"

  # What the run acts on: the plugin's settings and the system's managers.
  local out facts key value aur_command=() snapshot_setting="" trust=false
  local settings
  settings="$("$_updates_vgshell" plugin settings "$VGS_PLUGIN_ID")"
  facts="$(_updates_facts settings <<<"$settings")"
  while read -r key value; do
    case "$key" in
      aur-command) read -r -a aur_command <<<"$value" ;;
      snapshot) snapshot_setting="$value" ;;
      trust) trust="$value" ;;
    esac
  done <<<"$facts"
  _updates_yes_flag=()
  if [[ $trust == true ]]; then _updates_yes_flag=(--yes); fi

  local primary="" present=() aur_binary=""
  out="$("$_updates_vgshell" pkg detect --json)"
  facts="$(_updates_facts detect <<<"$out")"
  while read -r key value; do
    case "$key" in
      primary) primary="$value" ;;
      present)
        present+=("${value%% *}")
        if [[ ${value%% *} == aur ]]; then aur_binary="${value#* }"; fi
        ;;
    esac
  done <<<"$facts"
  local aur_here=0
  if _updates_in aur "${present[@]}" || [[ ${#aur_command[@]} -gt 0 && $primary == pacman ]]; then aur_here=1; fi

  # The sources this run takes, in step order.
  local run=()
  if [[ $mode == all ]]; then
    run=(vgs)
    if [[ -n $primary ]]; then run+=("$primary"); fi
    for arg in flatpak mise; do
      if _updates_in "$arg" "${present[@]}"; then run+=("$arg"); fi
    done
    run+=(plugins themes)
    if [[ $aur_here == 1 ]]; then run+=(aur); fi
  else
    case "$only" in
      vgs|plugins|themes) ;;
      aur) [[ $aur_here == 1 ]] || _updates_refuse 1 "source=aur reason=absent" ;;
      flatpak|mise) _updates_in "$only" "${present[@]}" || _updates_refuse 1 "source=$only reason=absent" ;;
      "$primary") ;;
      *) _updates_refuse 2 "source=$only reason=unknown" "a source is the primary manager's id, aur, flatpak, mise, vgs, plugins or themes" ;;
    esac
    run=("$only")
  fi

  # Each source's plan, for the box and the steps. A package source whose
  # plan the table refuses, as it refuses nix's, leaves the run.
  local -A labels=()
  local plan=() kept=() id label vgs_package="" vgs_current="" vgs_step="" vgs_reason="" plugins=() themes=()
  local primary_planned=0 elevator="" elevator_refused=""
  local _updates_plan_text _updates_plan_elevator _updates_plan_elevator_refused
  if _updates_in vgs "${run[@]}"; then
    out="$("$_updates_vgshell" self status --json)"
    facts="$(_updates_facts self <<<"$out")"
    while read -r key value; do
      case "$key" in
        package) vgs_package="$value" ;;
        current) vgs_current="$value" ;;
        step) vgs_step="$value" ;;
        reason) vgs_reason="$value" ;;
        error) _updates_diagnostic "VGS: $value"; vgs_tui_warn "Could not check VGS for updates." ;;
      esac
    done <<<"$facts"
    # The status and this run each read `vgshell pkg detect`; use this
    # run's helper state before choosing whether installation is needed.
    if [[ $vgs_step == rebuild && -z $aur_binary ]]; then vgs_step=install-helper; fi
    if [[ $vgs_step == install-helper && -n $aur_binary ]]; then vgs_step=rebuild; fi
    # With no AUR helper, the `aurCommand` words run the AUR step (aur_here),
    # and they update the release `vgshell` package from the AUR, as
    # UpdatesLogic.publishedNote tells the Updates window. `vgshell-git`
    # installs its helper first: its rebuild runs `<helper> -S vgshell-git`.
    if [[ $vgs_step:$vgs_reason == none:no-aur-helper && $vgs_package == vgshell && $aur_here == 1 ]]; then vgs_reason=package-manager; fi
    case "$vgs_step:$vgs_reason" in
      self:) plan+=("VGS: update VGS") ;;
      rebuild:) plan+=("VGS: rebuild the VGS package after AUR updates") ;;
      install-helper:) plan+=("VGS: install paru, then rebuild the VGS package") ;;
      none:no-aur-helper) plan+=("VGS: the $vgs_package package is behind, and no AUR helper is here to update it") ;;
      none:package-manager) plan+=("VGS: the $vgs_package package updates with its package manager") ;;
      none:nix) plan+=("VGS: its flake updates it") ;;
      none:) plan+=("VGS: current") ;;
      *) plan+=("VGS: could not check for an update") ;;
    esac
  fi
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes) kept+=("$id"); continue ;;
      aur) if [[ ${#aur_command[@]} -gt 0 ]]; then kept+=(aur); continue; fi; label="AUR, last" ;;
      flatpak) label=Flatpak ;;
      mise) label=mise ;;
      *) label=System ;;
    esac
    labels[$id]="$label"
    if _updates_plan "$id"; then
      kept+=("$id")
      plan+=("$label: install available updates")
    else
      [[ $mode == all ]] || _updates_refuse 1 "source=$only reason=no-plan" "$_updates_plan_text"
      _updates_diagnostic "$label: $_updates_plan_text"; plan+=("$label: VGS cannot update this source")
    fi
    if [[ $id == "$primary" ]]; then
      primary_planned=1
      elevator="$_updates_plan_elevator"
      elevator_refused="$_updates_plan_elevator_refused"
    fi
  done
  run=("${kept[@]}")
  if [[ ${#aur_command[@]} -gt 0 ]] && _updates_in aur "${run[@]}"; then plan+=("AUR: install updates after system updates"); fi
  if _updates_in plugins "${run[@]}"; then
    _updates_outdated plugin plugins
    plugins=("${_updates_behind[@]}")
    plan+=("Plugins: ${plugins[*]:-current}")
  fi
  if _updates_in themes "${run[@]}"; then
    _updates_outdated theme themes
    themes=("${_updates_behind[@]}")
    plan+=("Themes: ${themes[*]:-current}")
  fi

  # A snapshot and the VGS version check guard every step that replaces
  # packages: the upgrades, the system's and the AUR's, and the vgshell-git
  # rebuild. The orphans follow the upgrades alone.
  local upgrades=0 rebuild=0 replaces=0
  if _updates_in aur "${run[@]}" || { [[ -n $primary ]] && _updates_in "$primary" "${run[@]}"; }; then upgrades=1; fi
  if _updates_in vgs "${run[@]}" && [[ $vgs_step == rebuild || $vgs_step == install-helper ]]; then rebuild=1; fi
  if [[ $upgrades == 1 || $rebuild == 1 ]]; then replaces=1; fi
  local snapshot_line="" snapshot_tool=""
  if [[ $replaces == 1 ]]; then
    if [[ $snapshot_setting == off ]]; then
      snapshot_line="Snapshot: off in the plugin's settings"
    elif ! snapshot_tool="$(_updates_snapshot_tool)"; then
      snapshot_tool=""
      snapshot_line="Snapshot: none, no snapper or timeshift found"
    else
      # The primary's plan names the elevation command, also when the run
      # leaves the system step out; a refused plan leaves its refusal in
      # elevator_refused, for the box.
      if [[ $primary_planned == 0 && -n $primary ]]; then
        _updates_plan "$primary" || true
        elevator="$_updates_plan_elevator"
        elevator_refused="$_updates_plan_elevator_refused"
      fi
      if [[ -n $elevator ]]; then
        snapshot_line="Snapshot: $snapshot_tool through $elevator, first"
      else
        snapshot_tool=""
        _updates_diagnostic "snapshot: $elevator_refused"; snapshot_line="Snapshot: unavailable because administrator access is not available"
      fi
    fi
  fi
  local session=0
  if [[ $elevator == sudo ]]; then session=1; fi

  # The free space and the plan box.
  local avail
  out="$(df --output=avail --block-size=1 /)"
  avail="${out##*$'\n'}"
  avail="${avail//[[:space:]]/}"
  if [[ ! $avail =~ $_updates_digits ]]; then
    _updates_diagnostic "updates: free-space=unreadable"; vgs_tui_warn "Could not check free disk space."
  elif ((avail < 10 * 1024 * 1024 * 1024)); then
    vgs_tui_warn "Less than 10 GiB is free on /. An update can fail when the disk fills up."
  fi
  local name
  _updates_skip_aur=() _updates_skip_repo=()
  local box=("Update ${only:-everything}" "")
  [[ -z $snapshot_line ]] || box+=("$snapshot_line")
  box+=("${plan[@]}")
  if [[ $rebuild == 1 ]] || _updates_in aur "${run[@]}"; then box+=("The AUR runs last, after every step that runs as root."); fi
  box+=("" "Log: $_updates_log")
  vgs_tui_header "${box[@]}"
  if [[ $_updates_yes != 1 ]]; then
    status=0
    vgs_tui_confirm "Start the update?" || status=$?
    case "$status" in
      0) ;;
      1) echo "Update cancelled."; exit 0 ;;
      *) exit "$status" ;;
    esac
  fi

  # A missing helper is a separate prerequisite transaction. It reviews
  # before its own credentials and ends them before Updates binds its plan.
  if [[ $rebuild == 1 && $vgs_step == install-helper ]]; then
    vgs_tui_step "Installing paru for VGS updates"
    _updates_source paru Paru _updates_run _updates_install_helper
    [[ $_updates_outcome == installed ]] || exit 1
    aur_binary=paru
    vgs_step=rebuild
  fi
  # The run.
  local review_system=0 review_aur=0
  if [[ $primary == pacman ]] && _updates_in pacman "${run[@]}"; then review_system=1; fi
  if _updates_in aur "${run[@]}"; then review_aur=1; fi
  if [[ $review_system == 1 || $review_aur == 1 || $rebuild == 1 ]]; then
    _updates_package_review "$review_system" "$review_aur" "$rebuild" "$aur_binary" "${aur_command[@]}"
  fi
  local vgs_before=""
  if [[ $replaces == 1 ]]; then vgs_before="$(_updates_vgs_package_version)"; fi
  if [[ $session == 1 ]]; then vgs_tui_sudo_session start; fi
  # A failed snapshot said what went wrong; it does not block the update,
  # but it must not pass for one either.
  if [[ -n $snapshot_tool ]]; then
    status=0
    _updates_snapshot "$snapshot_tool" "$elevator" || status=$?
    if [[ $status -ne 0 ]]; then
      _updates_diagnostic "updates: snapshot=failed exit=$status"; vgs_tui_warn "The snapshot failed."
      vgs_tui_warn "Continuing the update without a snapshot."
    fi
  fi
  # The installed packages before the first package step, which the
  # reboot question compares with those after the last.
  local -A installed=()
  local listed=0
  if [[ $primary == pacman && $replaces == 1 ]]; then
    if out="$(pacman -Q)"; then
      listed=1
      while read -r name value; do
        [[ -z $name ]] || installed[$name]="$value"
      done <<<"$out"
    else
      _updates_reboot_unread "updates: installed=unread when=before"
    fi
  fi
  if _updates_in vgs "${run[@]}" && [[ $vgs_step == self ]]; then
    vgs_tui_step "Updating VGS"
    _updates_source vgs VGS "$_updates_vgshell" self update
  fi
  # An AUR build links against the system the system step left: after a
  # failed or declined system upgrade, whose databases are already synced,
  # the AUR step and the rebuild would be a partial upgrade.
  local ignore=() aur_blocked=""
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes|aur) ;;
      *)
        ignore=()
        if [[ $id == pacman && ${#_updates_skip_repo[@]} -gt 0 ]]; then ignore=(--ignore "${_updates_skip_repo[@]}"); fi
        if [[ $id == pacman ]]; then
          _updates_source "$id" "${labels[$id]}" _updates_pacman_run pacman "$_updates_vgshell" pkg run upgrade --manager "$id" --review-receipt "$_updates_package_receipt" --config "${_updates_package_configs[pacman]}" "${ignore[@]}"
        else
          _updates_source "$id" "${labels[$id]}" "$_updates_vgshell" pkg run upgrade --manager "$id" "${ignore[@]}"
        fi
        if [[ $id == pacman ]]; then
          case "$_updates_outcome" in
            failed) aur_blocked="the system upgrade failed, and AUR packages build against it" ;;
            declined) aur_blocked="you declined the system upgrade, and AUR packages build against it" ;;
          esac
        fi
        ;;
    esac
  done
  if [[ ${#plugins[@]} -gt 0 ]]; then _updates_update_each plugin "${plugins[@]}"; fi
  if [[ ${#themes[@]} -gt 0 ]]; then _updates_update_each theme "${themes[@]}"; fi
  if [[ $session == 1 ]]; then vgs_tui_sudo_session end; fi

  local rebuild_run=0
  if [[ $rebuild == 1 ]] && ! _updates_in vgshell-git "${_updates_skip_aur[@]}"; then rebuild_run=1; fi
  if [[ -n $aur_blocked ]]; then
    if _updates_in aur "${run[@]}"; then _updates_results+=("AUR skipped. ${aur_blocked^}."); fi
    if [[ $rebuild_run == 1 ]]; then _updates_results+=("VGS package skipped. ${aur_blocked^}."); fi
  elif [[ $rebuild == 1 ]] || _updates_in aur "${run[@]}"; then
    local guarded=0
    if command -v sudo >/dev/null; then
      vgs_tui_sudo_session guard
      guarded=1
    fi
    if _updates_in aur "${run[@]}"; then
      ignore=()
      if [[ ${#aur_command[@]} -gt 0 ]]; then
        if [[ ${#_updates_skip_aur[@]} -gt 0 ]]; then ignore=(--ignore "${_updates_skip_aur[@]}"); fi
        vgs_tui_step "Updating AUR packages"
        local custom_json custom_mode
        custom_json="$(node -e 'process.stdout.write(JSON.stringify(process.argv.slice(1)))' "${aur_command[@]}")"
        custom_mode="$("$_updates_vgshell" pkg review-custom-mode "$custom_json")"
        if [[ $custom_mode == table ]]; then
          _updates_source aur AUR _updates_pacman_run custom "$_updates_vgshell" pkg run upgrade --manager aur --review-receipt "$_updates_package_receipt" --config "${_updates_package_configs[custom]}" "${ignore[@]}"
        else
          "$_updates_vgshell" pkg review-custom-consume "$_updates_package_receipt" "$custom_json"
          _updates_source aur AUR _updates_pacman_run custom "${aur_command[@]}"
        fi
      else
        if [[ ${#_updates_skip_aur[@]} -gt 0 ]]; then ignore=(--ignore "${_updates_skip_aur[@]}"); fi
        _updates_source aur AUR _updates_pacman_run "$aur_binary" "$_updates_vgshell" pkg run upgrade --manager aur --review-receipt "$_updates_package_receipt" --config "${_updates_package_configs[aur]}" "${ignore[@]}"
      fi
      # A second transaction can offer the engine the user just declined.
      # Only a completed AUR step permits the separate VGS rebuild.
      if [[ $rebuild_run == 1 && $_updates_outcome != installed ]]; then
        rebuild_run=0
        _updates_diagnostic "updates: skipped source=vgshell-git reason=aur-$_updates_outcome"
        case "$_updates_outcome" in
          declined) _updates_results+=("VGS package skipped. You declined the AUR update.") ;;
          failed) _updates_results+=("VGS package skipped. The AUR update failed.") ;;
        esac
      fi
    fi
    if [[ $rebuild_run == 1 ]]; then
      rm -f -- "${state:?}/rebuild-failed.json"
      vgs_tui_step "Rebuilding VGS"
      _updates_source vgshell-git "VGS package" _updates_pacman_run "$aur_binary" "$_updates_vgshell" pkg run reinstall --manager aur --review-receipt "$_updates_package_receipt" --config "${_updates_package_configs[aur]}" vgshell-git
      if [[ $_updates_outcome == failed ]]; then _updates_rebuild_failed "$vgs_current" "$aur_binary" "$_updates_exit"; fi
    fi
    if [[ $guarded == 1 ]]; then vgs_tui_sudo_session end; fi
  fi

  # The packages the run changed, a new version or a new name, and of
  # those the ones that need a reboot.
  local changes=()
  _updates_core=()
  if [[ $listed == 1 ]]; then
    if out="$(pacman -Q)"; then
      while read -r name value; do
        if [[ -z $name ]]; then continue
        elif [[ -z ${installed[$name]+set} ]]; then changes+=("install $name")
        elif [[ ${installed[$name]} != "$value" ]]; then changes+=("upgrade $name")
        fi
      done <<<"$out"
    else
      _updates_reboot_unread "updates: installed=unread when=after"
    fi
  fi
  if [[ ${#changes[@]} -gt 0 ]]; then _updates_reboot_packages "${changes[@]}"; fi

  if [[ $primary == pacman ]] && [[ $upgrades == 1 ]]; then _updates_orphans; fi
  if [[ -n $vgs_before ]] && [[ "$(_updates_vgs_package_version)" != "$vgs_before" ]] && "$_updates_vgshell" pid >/dev/null 2>&1; then
    vgs_tui_step "Restarting the shell on the updated VGS"
    "$_updates_vgshell" restart || { _updates_diagnostic "updates: restart=failed exit=$?"; vgs_tui_warn "VGS could not restart. Save your work and restart the computer."; }
  fi
  rm -f -- "${_updates_cause_file:?}"
  local ended=success
  if [[ $_updates_failures -gt 0 ]]; then ended=failed; fi
  _updates_recheck "$ended"
  _updates_reboot "${_updates_core[@]}"
  # Plain lines wrap within the window. Keep the result after the restart,
  # recheck and reboot output so the failed parts remain in view.
  local columns width result prefix
  if [[ ${#_updates_results[@]} -gt 0 ]]; then
    columns="$(vgs_tui_columns)"
    width=$((columns - 2 * _vgs_tui_edge))
    (( width > 0 )) || width=1
    vgs_tui_step "Update result"
    for result in "${_updates_results[@]}"; do
      case "$result" in
        *" failed. "*) prefix="${result%%" failed. "*} " ;;
        *" skipped. "*) prefix="${result%%" skipped. "*} " ;;
        *) prefix="${result%" installed."} " ;;
      esac
      _updates_result "$width" "$prefix" "${result#"$prefix"}"
    done
  fi
  if [[ $ended == failed ]]; then
    _updates_result "$width" '' "$_updates_failures of ${#_updates_results[@]} parts failed" "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" >&2
    local failed_parts=""
    for label in "${_updates_failed_parts[@]}"; do failed_parts+="${failed_parts:+, }$label"; done
    _updates_result "$width" 'Failed parts: ' "$failed_parts"
  fi
  [[ $ended == success ]] || exit 1
}

# The transaction lifetime is outside the credential-session subshell, whose
# sudo cleanup owns its traps. Neither owner can replace the other's EXIT.
updates_main() (
  local mode="$1" only="" arg
  shift
  if [[ $mode == source ]]; then
    only="${1:-}"
    [[ -n $only && $only != -* ]] || _updates_refuse 2 "source=missing" "$_updates_usage"
    shift
  fi
  local entry_args=("$@")
  [[ $mode == all ]] || entry_args=("$only" "$@")
  _updates_yes=0
  for arg in "$@"; do
    case "$arg" in
      -y) _updates_yes=1 ;;
      *) _updates_refuse 2 "argument=$arg" "$_updates_usage" ;;
    esac
  done

  local lib="${VGS_TUI_LIB:-}"
  _updates_tree="${lib%/bin/lib/tui.sh}"
  if [[ -z $lib || $_updates_tree == "$lib" || -z ${VGS_PLUGIN_ID:-} ]]; then
    _updates_refuse 2 "tui=missing" "run this through the vgs.updates floating TUI, which sets VGS_TUI_LIB and VGS_PLUGIN_ID"
  fi
  # shellcheck source=SCRIPTDIR/../../../../bin/lib/tui.sh
  source "$lib"
  _updates_vgshell="$_updates_tree/bin/vgshell"
  _updates_loader="$_updates_tree/bin/lib/qml-library.js"
  _updates_facts_bin="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)/bin/facts"

  VGS_PACKAGE_TRANSACTION="$("$_updates_vgshell" pkg review-transaction)" || exit 1
  export VGS_PACKAGE_TRANSACTION
  trap '_updates_package_cleanup' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  set +e
  (set -Ee; _updates_main)
  status=$?
  exit "$status"
)
