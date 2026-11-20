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
#   3. the plan box, then one question unless -y. Update all reads what
#      pacman, the AUR and each file source have pending with `vgshell pkg
#      check`, the Updates window's own check: one with nothing pending
#      leaves the run. The system runs whenever another package step does,
#      since each of those needs its upgrade first.
#      Another primary's system step always runs, since no other primary's
#      check reads fresh state
#   4. one sudo session, when the run replaces a package and the package
#      layer's elevation command is sudo. That command is the one `vgshell
#      pkg plan upgrade <primary>` names, from shell.json's
#      `packages.elevate`, else the first of sudo, doas and run0 on PATH;
#      doas and run0 ask as their own rules say, as bin/lib/pkg-run.sh does
#   5. a snapshot through snapper or timeshift behind that command, before
#      any step that replaces a package: the system's, a file source's, the
#      AUR's or the vgshell-git rebuild. A run with none takes no snapshot
#      and asks no password. None is taken when the plugin's `snapshot`
#      setting is off, when neither tool is on PATH or when no elevation
#      command resolves, and the plan box says which; a failed snapshot
#      warns and the update goes on
#   6. VGS itself: `vgshell self update` when `vgshell self status` names the
#      step `self`, a checkout or a curl install behind; a step of `none`
#      names its reason in the plan box and runs nothing
#   7. the system: `vgshell pkg run upgrade --manager <primary>`, which joins
#      the session
#   8. verified and release files, Flatpak and mise: `vgshell pkg run
#      upgrade --manager verified-file|deb-file|rpm-file|flatpak|mise`; a
#      file source replaces packages, so it takes the snapshot and the
#      orphan step as the system step does, and Update all takes it only
#      while its check offers one of its installed packages newer
#   9. pacman's orphaned packages, after the system and file sources,
#      inside the sudo session; pacman's removal confirmation is the only
#      question. Declared build tools stay; later AUR builds' new tools are
#      judged at the next run
#  10. each plugin, then each theme, behind its upstream:
#      `vgshell plugin|theme update <id>`, which shows its diff and asks
#      [y/N]; `--yes` only when the `trustPluginUpdates` setting is on
#  11. the end of the sudo session, which drops the credential
#  12. install a missing AUR helper for VGS's `install-helper` step,
#      reviewing its clone after the system upgrade and Updates' session
#  13. the AUR, last, so no PKGBUILD runs under the update's credential:
#      the table-owned upgrade or the non-table `aurCommand` words, then
#      the reviewed `<helper> -S vgshell-git` when the status names
#      the step `rebuild`. When self status selects `aur-upgrade` for paru's
#      tracked devel vgshell-git, the AUR upgrade builds it and no separate
#      rebuild runs; a run without the AUR step, an Update of VGS alone,
#      rebuilds it. With Devel off, no tracked devel update, or yay, status
#      selects the separate rebuild. A current installed-files judge
#      excludes vgshell-git from the table upgrade, also in AUR-only runs;
#      an unread judge excludes nothing. The helper asks sudo itself, so the
#      phase runs under tui.sh's sudo guard: the credential it caches is
#      dropped when the phase ends, fails or is interrupted
#  14. record the run's end
#  15. a reboot question when the run changed a package, by pacman -Q
#      before the first package step and after the last, that the CachyOS
#      reboot hook names under its script's conditions
#      (UpdatesLogic.rebootPackages through bin/facts reboot)
#  16. a shell restart when a package step or the rebuild replaced the VGS
#      package, unless the owner chose Reboot and it succeeded, then one
#      check request to refresh the widget and window; a successful Reboot
#      leaves that check to the outcome writer at exit
#  17. the result list, then the failure count and failed parts: the last
#      output names each failed part, its cause and its next step
#  18. the outcome file $(updates_state_dir)/outcome.json, written by
#      rename when the run ends however it ends, which the Updates window
#      shows until the next run replaces it: version 1, `ended`, a separate
#      `title` and `text`, `remedy` and `endedAt` (epoch milliseconds).
#      Restart-only remedies expire after the matching shell start or boot;
#      a run that ends at the start question writes none
#
# The package steps are the package-manager table's own plans, read with
# `vgshell pkg plan` and run with `vgshell pkg run`: they take no -y, so each
# manager asks its own questions in this terminal. The system and AUR
# steps keep their own configuration; a custom command keeps any config
# its words name. -y answers only the
# pipeline's own start question; orphan removal is skipped and the reboot
# decision is reported instead of asked. The review's questions still run.
# A printed reboot reason under -y does not prevent the shell restart.
# No part's failure ends the run. A source step (6 to 8, 10, 12 and 13) that fails
# records its cause, read from its output (_updates_cause_of), and the run
# goes on with the next; a run with a failed step exits 1 after the reboot
# question. An unread system check is a failed part. After a failed or
# declined system step, a system plan that cannot run, or in Update all a
# system check that could not be read, the file sources, the AUR
# step, the vgshell-git rebuild and the orphan removal are each skipped
# with its result line, since they act on the system that step left; a
# system step blocked before the run starts also takes no snapshot and
# asks no password. A failed paru install skips the AUR step and the
# rebuild, which need the helper. A refused password skips every step
# that needs it: the system, the file rows, the snapshot, the AUR, the
# rebuild and the orphans. An unreadable VGS status,
# plugin, theme or orphan build-tool read skips that part. A declined orphan
# removal keeps the packages; a failed removal or shell restart is a failed
# part. An unread reboot check warns once
# and adds a non-failed result line. A failed reboot permits the shell
# restart; a failed shell restart updates the already recorded end.
# An interrupted reboot question acts as Later through the restart,
# recheck and result list, then exits with the question's status.
# A package a declined AUR transaction leaves out is not retried by the
# VGS rebuild. A complete AUR build
# failure permits the separate reviewed rebuild; the helper itself fails
# a broken dependency. Other failed transactions still skip the rebuild.
# A step a Ctrl-C ended ends the run with 130. Any other failing command is
# a fault of the pipeline itself and ends the run: the ERR trap prints the
# result list so far, `updates: failed exit=<n> log=<file>` and how to
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
# The result of a part that failed without words VGS could use, after its
# label.
_updates_uncaused=" failed, and VGS could not find the cause. Next: update again."

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
  # A fault after the run reached its end, such as a failed reboot, keeps
  # the end the run recorded.
  [[ -z $_updates_part_now || -f $_updates_run_dir/ended ]] ||
    _updates_ended failed "${_updates_failed_title:-$_updates_part_now failed}" "${_updates_failed_text:-VGS could not find the cause. Update again.}" "${_updates_failed_remedy:-}"
  _updates_result_list
  vgs_tui_failed "$_updates_log" "The update stopped. Try again from Updates."
}

# PART, the label of the part that starts now, which the outcome of a run
# stopped or failing in it names (updates_main's EXIT).
_updates_part() { # PART
  _updates_part_now="$1"
  printf '%s\n' "$1" >"$_updates_run_dir/part"
}

# The final outcome facts survive the credential subshell. A restart
# resolves the whole run only while no other part failed.
_updates_ended() { # finished|failed TITLE TEXT REMEDY
  local remedy="$4"
  [[ $1 != failed || ${#_updates_failed_parts[@]} -le 1 ]] || remedy=""
  printf '%s\n' "$1" "$2" "$3" "$remedy" >"$_updates_run_dir/ended"
}

# The terminal keeps the full result line; the window gets independent
# title and action text from the first failed producer, without splitting it.
_updates_fail() { # PART LINE TITLE TEXT [REMEDY]
  _updates_results+=("$2")
  _updates_failed_parts+=("$1")
  [[ -z $_updates_failed_title ]] || return 0
  _updates_failed_title="$3" _updates_failed_text="$4" _updates_failed_remedy="${5:-}"
  printf '%s\n' "$3" "$4" "${5:-}" >"$_updates_run_dir/failed"
}

# The outcome file, written by rename so the service never reads half, from
# the facts the run left in its private folder: none before the first
# part; the run's own sentence once it reached its end, also when a signal
# came after; a stop by Ctrl-C (130), a closed window (129) or TERM (143);
# else the first failed part's result line; else, for a failing status,
# the part it ended in for a reason it gave no words for. A run that ended
# in a part before its own check, stopped or in the error trap, asks for
# the check here, after the outcome is written: the check
# can wait a minute for the shell, and a second signal in that wait ends
# this trap. One that ended before its first part leaves the check to the
# end of its TUI.
_updates_outcome_write() { # STATUS
  local status="$1" dir="$_updates_run_dir" part ended="" title="" text="" remedy="" fields=()
  [[ -f $dir/part ]] || return 0
  read -r part <"$dir/part"
  if [[ -f $dir/ended ]]; then
    mapfile -t fields <"$dir/ended"
    ended="${fields[0]}" title="${fields[1]}" text="${fields[2]}" remedy="${fields[3]}"
  elif [[ $status == 129 || $status == 130 || $status == 143 ]]; then
    ended=stopped title="Update stopped during $part" text="Nothing after it ran."
  elif [[ -f $dir/failed ]]; then
    ended=failed
    mapfile -t fields <"$dir/failed"
    title="${fields[0]}" text="${fields[1]}" remedy="${fields[2]}"
  elif [[ $status != 0 ]]; then
    ended=failed title="$part failed" text="VGS could not find the cause. Update again."
  fi
  if [[ -n $ended ]]; then
    flock -w 10 "$(updates_state_dir)/outcome.lock" node -e 'const fs = require("node:fs"); const [file, ended, title, text, remedy] = process.argv.slice(1);
fs.writeFileSync(file + "." + process.pid, JSON.stringify({ version: 1, ended, title, text, remedy, endedAt: Date.now() }) + "\n");
fs.renameSync(file + "." + process.pid, file);' "$(updates_state_dir)/outcome.json" "$ended" "$title" "$text" "$remedy" ||
      _updates_diagnostic "updates: outcome=unwritten exit=$?"
  fi
  [[ -f $dir/checked ]] || _updates_recheck
}

# Runs ARGV from $HOME, as vgshell pkg run runs its steps, so a project's
# configuration in the caller's directory changes nothing.
_updates_run() { # ARGV...
  (cd -- "$HOME" && "$@")
}

_updates_install_helper() { "$_updates_vgshell" pkg ensure-helper; }

_updates_custom_run() {
  "$_updates_vgshell" pkg review-custom-consent || return $?
  _updates_run "$@"
}

_updates_cleanup() {
  [[ -z ${_updates_run_dir:-} ]] || rm -rf -- "${_updates_run_dir:?}"
}

# Recognition uses the package owner's terminal normalization; neither the
# saved interval nor the interactive relay is rewritten.
_updates_plain() { # FILE
  node -e 'const fs=require("node:fs"); const [loader,judge,file]=process.argv.slice(1);
process.stdout.write(require(loader).load(judge).transcriptLines(fs.readFileSync(file,"utf8")).join("\n"));' \
    "$_updates_loader" "$_updates_tree/shell/Core/PackageReview.js" "$1"
}

# TEXT, a line a step printed, as a result line may show it:
# PackageReview.failureLines masks its secret shapes and cuts its length
# (docs/architecture/secrets.md).
_updates_shown() { # TEXT
  node -e 'const [loader, judge, text] = process.argv.slice(1);
process.stdout.write(require(loader).load(judge).failureLines(text).join(" "));' \
    "$_updates_loader" "$_updates_tree/shell/Core/PackageReview.js" "$1"
}

# The lines a tool starts a failure with, once terminal controls and leading
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
# Paru can print its failed-build aggregate after a queued pacman install
# was refused (v2.1.0 src/install.rs resolve_targets/build_cleanup). Only
# explicit No to mutation/review/conflict questions is a refusal here:
# No to its earlier make-dependency cleanup question is not an abort.
_updates_refusal_question='(::[[:space:]]+(Proceed to review|Proceed with installation|Proceed with install|Accept changes)\?|are in conflict.*\?)[[:space:]]+\[(Y/n|y/N)\]:?[[:space:]]+[Nn]([Oo])?[[:space:]]*$'
# The scan line `vgshell pkg run` prints on stdout after its steps however
# they ended (bin/vgshell-pkg rescanShell, bin/vgshell rescan_if_running).
# It closes the run's block, as its `rescan=` refusal does, and is never
# the step's own text; a question its manager left unanswered can precede
# it on its line.
_updates_scan_line='(^|[[:space:]])shell=(rescan-started|rescan-queued|not-running)[[:space:]]*$'
# The characters of a package name, as the build lines below read them.
_updates_package='[A-Za-z0-9@_+.-]+'

# The cause of a failed step from its output in FILE, stdout and stderr in
# the order the terminal showed them with the answers the user typed, once
# terminal controls and carriage returns are gone. VGS prints a `vgshell:
# refused:` or `vgs-tui: refused:` key line and English after it. A
# question and its answer can precede the key on its line, as `vgshell
# plugin update`'s [y/N] does, and that text is never a cause. With a key
# line the cause is the last line after the last one, such as git's message
# after a `fetch=` refusal, else none: _updates_unworded holds the key, which
# only the developer log shows. `vgshell pkg run`'s closing
# block, a `rescan=` refusal after its steps, is the exception: there the
# cause is the last error line the steps printed before it, else their last
# line. Its other closing line, the scan line, is read as no line at all.
# Without a key line it is the last error line, else the last line
# that holds text. A question the step printed text after, with no answer
# echoed, gives that text instead, passed through _updates_shown. pacman's
# known errors, a theme lock and a failed build give VGS's own sentence.
# Sets _updates_cause, and
# _updates_declined to 1 when the user said no: the `declined=` refusal of
# `vgshell plugin|theme update`, or a step whose own text ends on a [Y/n]
# or [y/N] question answered no or left unanswered, as pacman and an AUR
# helper leave one. Also sets _updates_next for the result line's action.
_updates_cause_of() { # FILE
  local line rest out last="" fault="" keyed=0 value="" held="" held_fault="" tail="" after="" own="" built="" package summary="" build_state=unknown transaction_fault=""
  local makepkg_error="" unfetched=() finished=() others=0 sentence paru_summary="" tested="" block=0
  _updates_declined=0
  _updates_refused=0
  _updates_unworded=""
  _updates_failed_builds=()
  _updates_build_complete=0
  out="$(_updates_plain "$1")"
  while IFS= read -r line; do
    [[ ! $line =~ $_updates_refusal_question ]] || _updates_refused=1
    # The package owner's failure keys (bin/lib/pkg-retry.js afterFailure)
    # are for the log. A Stop at its retry question says the build's own
    # output ended at paru's summary, so the question's lines are not the
    # step's, and names the base that failed only its own tests.
    if [[ $line == *'vgshell: build-failure='* ]]; then
      if [[ -n $paru_summary && $line =~ (^|[[:space:]])vgshell:\ build-failure=check-only\ answer=stop\ package=($_updates_package)$ ]]; then
        tested="${BASH_REMATCH[2]}" last="$paru_summary" after="$paru_summary"
      fi
      continue
    fi
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
      [[ ! $line =~ ^error:\ packages\ failed\ to\ build:\  ]] || paru_summary="$line"
    fi
  done <<<"$out"
  # makepkg's function error identifies the cause; paru's final summary
  # identifies every failed base, with pkgver-pkgrel. These are diagnostic
  # facts only: PackageReview still alone decides retry-without-tests.
  while IFS= read -r line; do
    # Paru v2.1.0 install.rs resolve_targets calls build_cleanup before
    # returning do_install's status; exec.rs Status prints no diagnostic.
    # Thus the final aggregate proves no transaction outcome. Admit only
    # supported individual build errors, with print_error's colon-space,
    # and keep any transaction diagnostic sticky across later build errors.
    # Elevators report as COMMAND:, not error: (sudo tgetpass.c includes
    # EOF, timeout and read failures). No wording whitelist can prove success.
    # paru prints `failed to download sources` after any failed
    # --verifysource, an integrity check's included; it is a source that
    # could not be downloaded only after makepkg's own download error
    # (libmakepkg source/file.sh, local.sh and the VCS files of pacman
    # 7.1.0, read 2026-11-13), which keeps the base for its sentence.
    [[ ! $line =~ ^==\>\ ERROR:\  ]] || makepkg_error="$line"
    # makepkg's build and test output can print its own error: lines.
    # Paru's :: or parsing message ends that output even after -ofA:
    # a cached base has Sources are ready but no Finished making
    # (paru-check-pass.out; paru v2.2.0 install.rs:567-618).
    # PackageReview separately refuses a base that never finished.
    if [[ $line =~ ^==\>\ Making\ package:\  ]]; then block=1
    elif [[ $line == '    Aborting...' || $line =~ ^==\>\ Finished\ making:\  || $line =~ ^error:\ failed\ to\ (build|download\ sources) ]]; then block=0
    elif [[ $line =~ ^::\  || $line =~ ^($_updates_package-[^[:space:]-]+-[^[:space:]-]+):\ parsing\ pkg\ list\.\.\.$ ]]; then block=0
    fi
    [[ ! $line =~ ^==\>\ Finished\ making:\ ($_updates_package)\  ]] || finished+=("${BASH_REMATCH[1]}")
    if [[ $line =~ ^error:\ failed\ to\ download\ sources\ for\ \'($_updates_package-[^[:space:]-]+-[^[:space:]-]+)\':[[:space:]]*$ &&
          ( $makepkg_error == '==> ERROR: Failure while downloading '* || $makepkg_error == *' was not found in the build directory and is not a URL.' ) ]]; then
      package="${BASH_REMATCH[1]}"
      unfetched+=("${package%-*-*}")
      [[ $build_state == transaction ]] || build_state=build
    elif [[ $line =~ ^error:\ failed\ to\ build:\ [A-Za-z0-9@_+.-]+-[^[:space:]-]+-[^[:space:]-]+[[:space:]]*$ ||
          $line =~ ^error:\ failed\ to\ build\ \'[A-Za-z0-9@_+.-]+-[^[:space:]-]+-[^[:space:]-]+\':[[:space:]]*$ ]]; then
      [[ $build_state == transaction ]] || build_state=build
    elif [[ $line =~ ^error:\ packages\ failed\ to\ build:\ (.+)$ ]]; then
      : # The aggregate cannot turn unknown or transaction into build.
    elif [[ $block == 0 ]] && [[ $line =~ $_updates_error_line ||
            $line =~ ^[[:space:]]*(sudo|doas|run0|pacman|paru|yay):[[:space:]] ||
            $line =~ $_updates_refusal_question ]]; then
      build_state=transaction transaction_fault="$line"
    fi
    if [[ $line =~ ^error:\ packages\ failed\ to\ build:\ (.+)$ ]]; then
      built="${BASH_REMATCH[1]//,/ }" summary="$line"
    elif [[ -z $built && $line =~ failed\ to\ build[:\ ]+[\'\"]?([A-Za-z0-9@_+.-]+-[^[:space:]-]+-[^[:space:]-]+) ]]; then
      built="${BASH_REMATCH[1]}"
    fi
  done <<<"$out"
  for package in $built; do
    if [[ $package =~ ^[A-Za-z0-9@_+.-]+-[^[:space:]-]+-[^[:space:]-]+$ ]]; then
      _updates_failed_builds+=("${package%-*-*}")
    else
      _updates_failed_builds=()
      break
    fi
  done
  if [[ $keyed == 0 ]]; then
    own="$last" _updates_cause="${fault:-$last}"
  elif [[ $value == rescan=* ]]; then
    own="${tail:-$held}" _updates_cause="${held_fault:-${held:-$after}}"
  else
    _updates_cause="$after"
  fi
  # A per-package message is useful copy, not permission to rebuild.
  if [[ $build_state == build && -n $summary && $own == "$summary" ]]; then _updates_build_complete=1; fi
  if [[ $own =~ \[(Y/n|y/N)\]:?(.*)$ ]]; then
    rest="${BASH_REMATCH[2]}"
    if [[ $rest =~ $_updates_answer && $rest != *[Yy]* ]]; then _updates_declined=1; fi
  fi
  _updates_next="update again."
  if [[ -n $transaction_fault ]]; then
    [[ -z $summary || $own != "$summary" ]] || _updates_cause="$transaction_fault"
  fi
  # The step's own line, masked and cut as a failure shows it.
  [[ -z $_updates_cause ]] || _updates_cause="$(_updates_shown "$_updates_cause")"
  # VGS's sentences replace it. VGS's theme refusal, makepkg's build errors
  # and pacman's errors can precede a closing line such as Aborting, so map
  # the whole output the step supplied.
  if [[ -n $transaction_fault ]]; then
    # pacman's English errors: libalpm's lock error, which `failed to init
    # transaction (%s)` carries, and which a running manager's lock and a
    # stale one a crash left both give; the download error a database sync
    # and a package download end on, `failed to synchronize all databases
    # (%s)` and `failed to commit transaction (%s)` carrying `failed to
    # retrieve some files`, never the per-mirror `failed retrieving file`,
    # after which the next mirror can still succeed; and the conflict line,
    # `%s-%s and %s-%s are in conflict`, after a question that asks to
    # remove the second, the installed package (strings of pacman 7.1.0's
    # /usr/bin/pacman and libalpm.so, read 2026-11-11). A version holds no
    # hyphen but the one before its release, so a name is the word without
    # its last two hyphenated parts. Another locale keeps pacman's own line.
    case "$out" in
      *"unable to lock database"*)
        _updates_cause="Another package manager is running, or one that stopped left its lock behind."
        _updates_next="update again when it has finished. If none is running, delete the lock file pacman names, then update again."
        ;;
      *"failed to synchronize all databases (failed to retrieve some files)"*|*"failed to commit transaction (failed to retrieve some files)"*)
        _updates_cause="The package servers could not be reached."
        _updates_next="update again when the network works."
        ;;
      *)
        while IFS= read -r line; do
          if [[ $line =~ (^|[[:space:]])::\ ($_updates_package-[^[:space:]-]+-[^[:space:]-]+)\ and\ ($_updates_package-[^[:space:]-]+-[^[:space:]-]+)\ are\ in\ conflict ]]; then
            _updates_cause="${BASH_REMATCH[2]%-*-*} conflicts with ${BASH_REMATCH[3]%-*-*}, which is installed."
            break
          fi
        done <<<"$out"
        ;;
    esac
  else
    case "$out" in
      *"another theme command holds the theme lock"*)
        _updates_cause="Another theme change is still running."
        _updates_next="wait for it to finish, then update again from the Updates panel."
        ;;
      *"A failure occurred in "*|*"failed to build"*)
        _updates_cause="VGS could not build ${_updates_failed_builds[*]:-the package}."
        _updates_next="wait for its maintainer to fix the package, then update again."
        # A base whose source could not be downloaded has a sentence of its
        # own, which already says what comes next.
        if [[ ${#unfetched[@]} -gt 0 ]]; then
          rest=""
          for package in "${_updates_failed_builds[@]}"; do _updates_in "$package" "${unfetched[@]}" || rest+=" $package"; done
          _updates_cause=""
          if [[ -z $rest ]]; then _updates_next=""; else _updates_cause="VGS could not build${rest}."; fi
          for package in "${unfetched[@]}"; do
            sentence="$package failed: its source file could not be downloaded. Its maintainer must fix the package; the next update tries again."
            _updates_cause="${_updates_cause:+$_updates_cause }$sentence"
          done
        fi
        # The owner stopped at the retry its tests' failure offered, which
        # the next update offers again.
        if [[ -n $tested ]] && _updates_in "$tested" "${_updates_failed_builds[@]}"; then
          _updates_cause="$tested failed its own tests." _updates_next="update again to retry it without tests."
        fi
        # Without --failfast, paru v2.2.0 builds each base after a failed
        # one (src/install.rs:866-883), installs those it built once every
        # base was tried, and only then names the failed ones (:444-451).
        # So a complete build-only failure installed each other base that
        # finished.
        if [[ $_updates_build_complete == 1 ]]; then
          for package in "${finished[@]}"; do _updates_in "$package" "${_updates_failed_builds[@]}" || others=1; done
          [[ $others == 0 ]] || _updates_cause+=" The other AUR packages installed."
        fi
        ;;
    esac
  fi
  # A key is for the log: a refusal with no words after it, and none VGS
  # has, gives none.
  [[ $keyed == 0 || -n $_updates_cause ]] || _updates_unworded="$value"
  # The package owner's review outcome names the step's cause.
  if [[ -n $_updates_review_final ]]; then
    _updates_cause="$(_updates_shown "$_updates_review_final")"
    _updates_next="" _updates_unworded=""
  fi
}

# The package owner's lines in a step's output FILE (bin/lib/pkg-review.js):
# each `vgshell: package-result: ` line is a result line of its own, kept in
# _updates_review_results, and the last `vgshell: package-review: ` line,
# in _updates_review_final, is the review's outcome: the cause of a failed
# step, and the whole result of one that ended 0, which the review skipped.
_updates_review_of() { # FILE
  local line out
  _updates_review_results=() _updates_review_final=""
  out="$(_updates_plain "$1")"
  while IFS= read -r line; do
    case "$line" in
      'vgshell: package-result: '*) _updates_review_results+=("$(_updates_shown "${line#vgshell: package-result: }")") ;;
      'vgshell: package-review: '*) _updates_review_final="${line#vgshell: package-review: }" ;;
    esac
  done <<<"$out"
}

# Runs one source step, ARGV, and adds its result to _updates_results as
# `LABEL <result>.`: installed; skipped when the user declined it; failed
# with its cause and next step, else `exit <n>`; or, for a refusal that gave
# only its key, which goes to diagnostics.log, failed with no cause VGS
# could find. A step the package owner's review skipped whole adds the
# review's sentence instead, and each package result line the owner printed
# follows the step's own line (_updates_review_of). A failed step's LABEL
# names its packages, and the outcome of a run stopped in it names the
# same. A paru step that ended 0 with output VGS could not read may have
# been skipped, so its result is unknown and no later step counts on it.
# _updates_outcome is installed, skipped, unknown, declined or failed, and
# _updates_exit the step's exit status. The run goes on after a failure,
# so neither errexit nor the ERR trap sees it.
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
# script(1) keeps, by tui.sh's vgs_tui_interval_open and _cut; only a
# failed step's output is cut, and the file is whole when it is read. A closed window hangs up the run's pty, and a
# write to a pty whose master is closed fails with EIO and raises no
# signal (a Python os.write on Linux 7.2, 2026-10-17), so a step such as
# pacman still reaches the end of its transaction and unlocks its database
# instead of dying by SIGPIPE. A step a Ctrl-C ended, 130, ends the run.
# Only a failed step's output is cut, and a paru step's (the AUR, the VGS
# package and the helper) whatever its status, for the review's lines.
_updates_source() { # ID LABEL ARGV...
  local id="$1" label="$2" part="$2" status=0 reviewed=0
  local completed="$label installed."
  shift 2
  if [[ $id == aur ]]; then part="AUR packages"
  elif [[ $label == System ]]; then part="System packages"
  elif [[ $id == orphans ]]; then completed="$label removed."
  fi
  case "$id" in aur|vgshell-git|paru) reviewed=1 ;; esac
  _updates_part "$part"
  vgs_tui_interval_open
  "$@" || status=$?
  _updates_exit="$status"
  if [[ $status -eq 0 && $reviewed == 0 ]]; then
    _updates_outcome=installed
    _updates_results+=("$completed")
    return 0
  fi
  if [[ $status -eq 130 ]]; then
    _updates_diagnostic "updates: stopped source=$id exit=$status"
    exit "$status"
  fi
  : >"$_updates_cause_file"
  if vgs_tui_interval_cut "$_updates_cause_file"; then
    _updates_review_of "$_updates_cause_file"
    [[ $status -eq 0 ]] || _updates_cause_of "$_updates_cause_file"
  else
    _updates_diagnostic "updates: transcript=unread source=$id reason=$vgs_tui_unread"
    _updates_review_results=() _updates_review_final=""
    if [[ $status -eq 0 ]]; then
      _updates_outcome=unknown
      _updates_results+=("$label result unknown. VGS could not read this step's output, so the review may have skipped it.")
      return 0
    fi
    _updates_declined=0
    _updates_refused=0
    _updates_unworded=""
    _updates_failed_builds=()
    _updates_build_complete=0
    _updates_cause="VGS could not read this step's output."
    _updates_next="update again."
  fi
  if [[ $status -eq 0 ]]; then
    if [[ -n $_updates_review_final ]]; then
      _updates_outcome=skipped
      _updates_results+=("$(_updates_shown "$_updates_review_final")")
    else
      _updates_outcome=installed
      _updates_results+=("$completed")
    fi
    _updates_results+=("${_updates_review_results[@]}")
    return 0
  fi
  if [[ $_updates_declined == 1 ]]; then
    _updates_outcome=declined
    _updates_results+=("$label skipped. You declined it.")
    _updates_results+=("${_updates_review_results[@]}")
    return 0
  fi
  _updates_outcome=failed
  _updates_diagnostic "updates: failed source=$id exit=$status"
  if [[ -n $_updates_unworded ]]; then
    _updates_diagnostic "updates: unworded source=$id refusal=$_updates_unworded"
    _updates_fail "$part" "$part$_updates_uncaused" "$part failed" "VGS could not find the cause. Update again."
  else
    local cause="${_updates_cause:-exit $status}"
    [[ $cause == *[.!?] ]] || cause+="."
    local next=""
    [[ -z $_updates_next ]] || next=" Next: $_updates_next"
    _updates_fail "$part" "$part failed. $cause$next" "$part failed" "$cause$next"
  fi
  _updates_results+=("${_updates_review_results[@]}")
  vgs_tui_warn "$part failed. The rest of the update goes on."
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

# The result list, then the failed parts' count and names. Plain lines wrap
# within the window. A line with no part of its own has no hanging indent.
_updates_result_list() {
  local columns width result prefix label failed_parts=""
  [[ ${#_updates_results[@]} -gt 0 ]] || return 0
  columns="$(vgs_tui_columns)"
  width=$((columns - 2 * _vgs_tui_edge))
  (( width > 0 )) || width=1
  vgs_tui_step "Update result"
  for result in "${_updates_results[@]}"; do
    case "$result" in
      *" failed. "*) prefix="${result%%" failed. "*} " ;;
      *" skipped. "*) prefix="${result%%" skipped. "*} " ;;
      *" failed, and "*) prefix="${result%%" failed, and "*} " ;;
      *" installed.") prefix="${result%" installed."} " ;;
      *) prefix="" ;;
    esac
    _updates_result "$width" "$prefix" "${result#"$prefix"}"
  done
  [[ ${#_updates_failed_parts[@]} -gt 0 ]] || return 0
  _updates_result "$width" '' "${#_updates_failed_parts[@]} of ${#_updates_results[@]} parts failed" "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" >&2
  for label in "${_updates_failed_parts[@]}"; do failed_parts+="${failed_parts:+, }$label"; done
  _updates_result "$width" 'Failed parts: ' "$failed_parts"
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

# Whether SOURCE has updates, by its table row's own query through
# `vgshell pkg check`, the check the Updates window counts: 0 when it has, 1
# when it has none or the system takes no package from it, 2 when the
# check could not be read, whose cause goes to the developer log. A check
# a Ctrl-C, a closed window or TERM stopped ends the run with its status,
# as a source step does.
_updates_pending() { # SOURCE
  local out facts key value status=0
  _updates_pending_count=""
  out="$("$_updates_vgshell" pkg check --json --source "$1")" || status=$?
  case "$status" in
    129|130|143) _updates_diagnostic "updates: stopped check=$1 exit=$status"; exit "$status" ;;
  esac
  if [[ $status != 0 ]] || ! facts="$(_updates_facts check "$1" <<<"$out")"; then
    _updates_diagnostic "updates: check=unread source=$1 exit=$status"
    return 2
  fi
  [[ -n $facts ]] || return 1
  while read -r key value; do
    case "$key" in
      error) _updates_diagnostic "updates: check=failed source=$1 error=$value"; return 2 ;;
      count) _updates_pending_count="$value"; [[ $value != 0 ]] || return 1 ;;
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
        vgs_tui_warn "snapper has no configuration."
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
        vgs_tui_warn "timeshift is not set up."
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
# skips the source and returns 1, so the plan box says VGS could not check
# it.
_updates_outdated() { # plugin|theme SOURCE
  local out facts key value
  _updates_behind=()
  if ! out="$("$_updates_vgshell" "$1" outdated --json)"; then
    _updates_diagnostic "updates: skipped=$2 reason=outdated-failed"
    _updates_results+=("${2^} skipped. VGS could not check them for updates. Update again later.")
    return 1
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

# The orphans' result line when their list or its build tools could not
# be read, and DIAGNOSTIC in the developer log.
_updates_orphans_unread() { # DIAGNOSTIC
  _updates_diagnostic "updates: $1"
  _updates_results+=("Orphaned packages skipped. VGS could not check which packages are unused. Update again later.")
}

_updates_orphans() {
  local out info status=0 orphans=()
  _updates_part "Orphaned packages"
  out="$(pacman -Qtdq)" || status=$?
  # pacman -Qtdq exits 1 when no package is orphaned.
  if [[ $status -eq 1 && -z $out ]]; then return 0; fi
  if [[ $status -ne 0 ]]; then
    _updates_orphans_unread "orphans=unreadable exit=$status"
    return 0
  fi
  mapfile -t orphans <<<"$out"
  vgs_tui_step "Orphaned packages"
  info="$("$_updates_vgshell" pkg orphan-info "${orphans[@]}")" || { _updates_orphans_unread "orphans=info-failed exit=$?"; return 0; }
  out="$(node - "$info" <<'JS'
const info = JSON.parse(process.argv[2]);
// Whole-read notes refuse clean-up; missing AUR names and no helper do not.
const failure = info.unavailable.find(note => !note.includes(":") && note !== "helper=absent");
if (failure) {
  console.log("orphans=info-unread cause=" + failure);
  process.exit(1);
}
// REVISIT(D128): declared build tools stay out of the removal offer.
const kept = info.packages.filter(row => row.builds.length);
const candidates = info.packages.filter(row => !row.builds.length);
if (kept.length)
  console.error("Kept " + kept.length + " build tool(s): " + kept.map(row => row.name + " (build tool for " + row.builds.join(", ") + ")").join("; ") + ".");
for (const row of candidates)
  console.error("  " + row.name + (info.unavailable.length ? " (build use unknown)" : " (unused dependency)"));
if (info.unavailable.length) {
  const unread = [...new Set(info.unavailable.filter(note => note.includes(":")).map(note => note.split(":")[0]))];
  console.error("Build declarations could not be read for " + (unread.length ? unread.join(", ") : "some installed packages") + ".");
}
console.error("Pacman does not retain build declarations. Other orphaned packages may be build tools from earlier source builds.");
console.log(candidates.map(row => row.name).join("\n"));
JS
  )" || { _updates_orphans_unread "${out:-orphans=unjudged exit=$?}"; return 0; }
  orphans=()
  if [[ -n $out ]]; then mapfile -t orphans <<<"$out"; fi
  if [[ ${#orphans[@]} -eq 0 ]]; then return 0; fi
  if [[ $_updates_yes == 1 ]]; then
    printf 'The orphaned packages were kept. Open Updates to review them.\n'
    return 0
  fi
  _updates_source orphans "Orphaned packages" "$_updates_vgshell" pkg run remove --manager pacman "${orphans[@]}"
}

# The run's one check, asked as `run` so the service starts no second one
# when the TUI ends (Service.qml).
_updates_recheck() {
  local reply status polls=0 line unavailable
  : >"$_updates_run_dir/checked"
  # A package rescan can replace this service. ServiceGate builds plugin
  # services after the bars, so wait for the registered check handler,
  # not just the core PID.
  while :; do
    status=0
    reply="$("$_updates_vgshell" ipc call "$VGS_PLUGIN_ID" invoke check run 2>&1)" || status=$?
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
# once per run. Its advisory result does not fail a package step.
_updates_reboot_unread() { # DIAGNOSTIC
  _updates_diagnostic "$1"
  [[ $_updates_reboot_warned == 0 ]] || return 0
  _updates_reboot_warned=1
  vgs_tui_warn "VGS could not check whether a restart is needed."
  _updates_results+=("VGS could not check whether a restart is needed.")
}

# Sets _updates_core to the packages of CHANGES, `upgrade <name>` and
# `install <name>` lines, that need a reboot: the ones the CachyOS reboot
# hook names, as its script judges them with the running kernel and the
# mounted file systems (UpdatesLogic.rebootPackages through bin/facts
# reboot). Without the hook none does. A read that fails warns through
# _updates_reboot_unread, and a failed judgement leaves the list empty, so
# the run still ends with its result.
_updates_reboot_packages() { # CHANGE...
  local root hook=- mounts="" facts key value status=0 unread=0
  _updates_core=()
  if root="$(pacman-conf RootDir 2>&1)"; then
    [[ ! -f ${root%/}/$_updates_reboot_hook ]] || hook="${root%/}/$_updates_reboot_hook"
  else
    _updates_reboot_unread "updates: reboot-hook=unread exit=$?"
    _updates_diagnostic "$root"
    unread=1
  fi
  if mounts="$(findmnt -rno FSTYPE 2>&1)"; then
    :
  else
    _updates_reboot_unread "updates: mounts=unread exit=$?"
    _updates_diagnostic "$mounts"
    unread=1
  fi
  [[ $unread == 0 ]] || return 0
  facts="$({
    printf '%s\n' "$@"
    while read -r value; do [[ -z $value ]] || printf 'mounted %s\n' "$value"; done <<<"$mounts"
  } | _updates_facts reboot "$hook" /proc/version 2>&1)" || status=$?
  if [[ $status -ne 0 ]]; then
    _updates_diagnostic "$facts"
    _updates_reboot_unread "updates: reboot-packages=failed exit=$status"
    return 0
  fi
  while read -r key value; do
    if [[ $key == reboot ]]; then _updates_core+=("$value"); fi
  done <<<"$facts"
}

# The reboot question, one confirmation, default Later: CORE are the
# packages _updates_reboot_packages kept of those the run changed.
# Under -y the reasons are printed instead. Only a successful Reboot
# sets _updates_rebooted, so Later and a failed reboot permit a restart.
# A question interrupted by gum returns its status for finalization.
_updates_reboot() { # CORE...
  local status=0 reason reasons=() names=""
  if [[ $# -gt 0 ]]; then
    for reason; do names+="${names:+, }$reason"; done
    reasons+=("The run updated $names, which $([[ $# -eq 1 ]] && echo takes || echo take) effect after a reboot.")
  fi
  [[ ${#reasons[@]} -gt 0 ]] || return 0
  if [[ $_updates_yes == 1 ]]; then
    printf '%s Reboot when you are ready.\n' "${reasons[*]}"
    return 0
  fi
  status=0
  vgs_tui_confirm "${reasons[*]} Reboot now?" --affirmative=Reboot --negative=Later --default=false || status=$?
  case "$status" in
    0)
      if "$_updates_vgshell" power reboot; then
        _updates_rebooted=1
      else
        _updates_diagnostic "updates: reboot=failed exit=$?"
        vgs_tui_warn "VGS could not reboot. Restart the computer when you are ready."
      fi ;;
    1) echo "Reboot later to run the updated system." ;;
    *) return "$status" ;;
  esac
}

# Whether WORD is one of the rest.
_updates_in() { # WORD LIST...
  local word="$1" item
  shift
  for item in "$@"; do [[ $item == "$word" ]] && return 0; done
  return 1
}

# Whether SOURCE is a file row of the package table, whose packages are
# files VGS fetches: verified files and release files.
_updates_file_source() { # SOURCE
  [[ $1 == verified-file || $1 == deb-file || $1 == rpm-file ]]
}

# updates_main all ARG... | updates_main source SOURCE ARG...: the pipeline
# over every source, or over SOURCE alone, named as a status row names it:
# the primary manager's id, aur, verified-file, deb-file, rpm-file,
# flatpak, mise, vgs, plugins or themes. The ARGs after SOURCE are -y
# alone; update-source.sh passes its SOURCE twice, once here and once
# among the entry script's own ARGs, which the log runs it again with.
_updates_main() {

  local state
  state="$(updates_state_dir)"
  _updates_log="$(updates_log_file)"
  if [[ ${VGS_TUI_LOGGED:-} != 1 ]]; then
    mkdir -p -- "$state"
    export UPDATES_LOG_PART="$state/.update.$$.log"
  fi
  vgs_tui_log --build-progress "$_updates_log" "$UPDATES_LOG_PART" "${entry_args[@]}"
  local status=0
  vgs_tui_lock updates || status=$?
  if [[ $status -ne 0 ]]; then
    rm -f -- "$UPDATES_LOG_PART"
    exit "$status"
  fi
  mv -f -- "$UPDATES_LOG_PART" "$_updates_log"
  _updates_pid=$BASHPID
  # The result list, the failed parts and the first one's result, the part
  # now running, whether a reboot read warned, and the file a failed source
  # step's output is cut into: one file, since the lock holds one run at a
  # time.
  _updates_results=() _updates_failed_parts=() _updates_part_now="" _updates_reboot_warned=0 _updates_rebooted=0
  _updates_failed_title="" _updates_failed_text="" _updates_failed_remedy=""
  _updates_cause_file="$state/.step-output"
  trap '_updates_failed $?' ERR

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
  local aur_here=0 aur_current=0
  if _updates_in aur "${present[@]}" || [[ ${#aur_command[@]} -gt 0 && $primary == pacman ]]; then aur_here=1; fi

  # The sources this run takes, in step order.
  local run=()
  if [[ $mode == all ]]; then
    vgs_tui_step "Checking for updates"
    run=(vgs)
    if [[ -n $primary ]]; then run+=("$primary"); fi
    for arg in verified-file deb-file rpm-file flatpak mise; do
      _updates_in "$arg" "${present[@]}" || continue
      # A file source is present wherever its primary is; it joins only
      # while its check offers one of its installed packages newer, or
      # could not be read, which leaves the step to find out.
      if _updates_file_source "$arg"; then
        status=0
        _updates_pending "$arg" || status=$?
        [[ $status != 1 ]] || continue
      fi
      run+=("$arg")
    done
    run+=(plugins themes)
    # The AUR joins while its check offers an update, or could not be
    # read, which leaves the step to find out. VGS has no check for the
    # owner's aurCommand, so that command always runs.
    if [[ $aur_here == 1 ]]; then
      status=0
      [[ ${#aur_command[@]} -gt 0 ]] || _updates_pending aur || status=$?
      if [[ $status == 1 ]]; then aur_current=1; else run+=(aur); fi
    fi
  else
    case "$only" in
      vgs|plugins|themes) ;;
      aur) [[ $aur_here == 1 ]] || _updates_refuse 1 "source=aur reason=absent" ;;
      verified-file|deb-file|rpm-file|flatpak|mise) _updates_in "$only" "${present[@]}" || _updates_refuse 1 "source=$only reason=absent" ;;
      "$primary") ;;
      *) _updates_refuse 2 "source=$only reason=unknown" "a source is the primary manager's id, aur, verified-file, deb-file, rpm-file, flatpak, mise, vgs, plugins or themes" ;;
    esac
    run=("$only")
  fi

  # Each source's plan, for the box and the steps. A package source whose
  # plan the table refuses, as it refuses nix's, leaves the run.
  local -A labels=()
  local plan=() kept=() id label vgs_package="" vgs_step="" vgs_reason="" vgs_unread=0 plugins=() themes=()
  local primary_planned=0 elevator="" elevator_refused=""
  local _updates_plan_text _updates_plan_elevator _updates_plan_elevator_refused
  if _updates_in vgs "${run[@]}" || _updates_in aur "${run[@]}"; then
    if out="$("$_updates_vgshell" self status --json)" && facts="$(_updates_facts self <<<"$out")"; then
      while read -r key value; do
        case "$key" in
          package) vgs_package="$value" ;;
          step) vgs_step="$value" ;;
          reason) vgs_reason="$value" ;;
          error) _updates_diagnostic "VGS: $value"; vgs_unread=1 ;;
        esac
      done <<<"$facts"
    else
      _updates_diagnostic "updates: vgs-status=unread exit=$?"; vgs_unread=1
    fi
    # The AUR-only run still needs the judge's currentness, but adds no
    # VGS action or result. An unread judge never authorizes an ignore.
    if [[ $vgs_unread == 1 ]]; then
      vgs_step=""
      if _updates_in vgs "${run[@]}"; then
        _updates_results+=("VGS skipped. VGS could not check it for updates. Update again later.")
      fi
    fi
  fi
  local aur_ignore=()
  if [[ $vgs_unread == 0 && $vgs_package == vgshell-git && $vgs_step == none && -z $vgs_reason ]]; then
    aur_ignore=(--ignore vgshell-git)
  fi
  # The package steps besides the system's: the AUR, a file source and the
  # VGS package. Each runs only after a successful system upgrade in this
  # run, so the system step runs for them with nothing of its own
  # pending, and a system step that cannot run skips them
  # (system_blocked, the cause).
  local more=0 system_blocked="" system_unread=0
  for id in "${run[@]}"; do
    if [[ $id == aur ]] || _updates_file_source "$id"; then more=1; fi
  done
  case "$vgs_step" in rebuild|install-helper|aur-upgrade) more=1 ;; esac
  if [[ $mode == source && $more == 1 && -n $primary && $only != "$primary" ]]; then
    run=("$primary" "${run[@]}")
  fi
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes) kept+=("$id"); continue ;;
      aur) if [[ ${#aur_command[@]} -gt 0 ]]; then kept+=(aur); continue; fi; label="AUR, last" ;;
      verified-file) label="Verified packages" ;;
      deb-file|rpm-file) label="Release packages" ;;
      flatpak) label=Flatpak ;;
      mise) label=mise ;;
      *) label=System ;;
    esac
    labels[$id]="$label"
    if _updates_plan "$id"; then
      # Update all reads whether the system has updates, the window's
      # own check, only for pacman, whose checkupdates syncs a private copy
      # of the databases (checkupdates(8)). apt's check reads the lists of
      # the last `apt update` and never refreshes them (PackageManagers.js),
      # and no other primary's row says its check reads fresh state, so
      # their system step always runs. A source of its own runs its step.
      status=0
      local system_plan="$label: install available updates" count_status=0
      if [[ $id == "$primary" ]] && { [[ $mode == all && $id == pacman ]] || [[ $more == 1 ]]; }; then
        _updates_pending "$id" || count_status=$?
        if [[ $mode == all && $id == pacman ]]; then status="$count_status"; fi
        if [[ $more == 1 ]]; then
          if [[ -n $_updates_pending_count ]]; then
            local update_word=updates
            [[ $_updates_pending_count != 1 ]] || update_word=update
            system_plan="System: $_updates_pending_count $update_word. System packages update first so package versions stay compatible."
          else
            system_plan="System: update count unavailable. System packages update first so package versions stay compatible."
          fi
        fi
      fi
      case "$status" in
        0) kept+=("$id"); plan+=("$system_plan") ;;
        1)
          if [[ $more == 1 ]]; then kept+=("$id"); plan+=("$system_plan")
          else plan+=("$label: current")
          fi ;;
        *)
          system_blocked="VGS could not check the system for updates" system_unread=1
          plan+=("$label: could not check for updates") ;;
      esac
    else
      [[ $mode == all || $id != "$only" ]] || _updates_refuse 1 "source=$only reason=no-plan" "$_updates_plan_text"
      _updates_diagnostic "$label: $_updates_plan_text"; plan+=("$label: VGS cannot update this source")
      [[ $id != "$primary" ]] || system_blocked="VGS cannot update the system"
    fi
    if [[ $id == "$primary" ]]; then
      primary_planned=1
      elevator="$_updates_plan_elevator"
      elevator_refused="$_updates_plan_elevator_refused"
    fi
  done
  run=("${kept[@]}")
  if [[ $aur_current == 1 ]]; then plan+=("AUR: current"); fi
  if _updates_in vgs "${run[@]}"; then
    # paru's tracked devel vgshell-git (`aur-upgrade`) builds in this run's
    # AUR upgrade when the AUR step runs, so VGS runs no step of its own.
    # A run without that step, an Update of VGS alone, rebuilds it.
    if [[ $vgs_step == aur-upgrade ]] && ! _updates_in aur "${run[@]}"; then vgs_step=rebuild; fi
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
      self:) label="VGS: update VGS" ;;
      rebuild:) label="VGS: rebuild the VGS package after AUR updates" ;;
      install-helper:) label="VGS: install paru, then rebuild the VGS package" ;;
      aur-upgrade:) label="VGS: the AUR updates install the new VGS package" ;;
      none:no-aur-helper) label="VGS: the $vgs_package package is behind, and no AUR helper is here to update it" ;;
      none:package-manager) label="VGS: the $vgs_package package updates with its package manager" ;;
      none:nix) label="VGS: its flake updates it" ;;
      none:) label="VGS: current" ;;
      *) label="VGS: could not check for an update" ;;
    esac
    plan=("$label" "${plan[@]}")
  fi
  if [[ ${#aur_command[@]} -gt 0 ]] && _updates_in aur "${run[@]}"; then plan+=("AUR: install updates after system updates"); fi
  if _updates_in plugins "${run[@]}"; then
    if _updates_outdated plugin plugins; then
      plugins=("${_updates_behind[@]}")
      plan+=("Plugins: ${plugins[*]:-current}")
    else
      plan+=("Plugins: could not check for updates")
    fi
  fi
  if _updates_in themes "${run[@]}"; then
    if _updates_outdated theme themes; then
      themes=("${_updates_behind[@]}")
      plan+=("Themes: ${themes[*]:-current}")
    else
      plan+=("Themes: could not check for updates")
    fi
  fi

  # A snapshot and the VGS version check guard every step that replaces
  # packages: the upgrades, the system's, a file source's and the AUR's,
  # and the vgshell-git rebuild. The orphans follow the upgrades alone.
  # With the system step blocked none of them runs.
  local upgrades=0 rebuild=0 replaces=0 step_source
  if _updates_in aur "${run[@]}" || { [[ -n $primary ]] && _updates_in "$primary" "${run[@]}"; }; then upgrades=1; fi
  for step_source in "${run[@]}"; do
    if _updates_file_source "$step_source"; then upgrades=1; fi
  done
  if _updates_in vgs "${run[@]}" && [[ $vgs_step == rebuild || $vgs_step == install-helper ]]; then rebuild=1; fi
  if [[ $upgrades == 1 || $rebuild == 1 ]]; then replaces=1; fi
  if [[ -n $system_blocked ]]; then replaces=0; fi
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
  # The password session serves the snapshot and the package steps, so a
  # run that replaces no package asks none.
  local session=0
  if [[ $replaces == 1 && $elevator == sudo ]]; then session=1; fi

  # The free space and the plan box.
  local avail
  out="$(df --output=avail --block-size=1 /)"
  avail="${out##*$'\n'}"
  avail="${avail//[[:space:]]/}"
  # 10 GiB covers the largest one-run need measured on 2026-11-11: the
  # biggest pacman transaction whose packages were still in the cache plus
  # the biggest AUR build folder, 8.4 GiB on home (5.6 + 2.7), 4.0 on
  # jarvis-mbp (0.2 + 3.8) and 3.5 on px13 (1.3 + 2.2).
  if [[ ! $avail =~ $_updates_digits ]]; then
    _updates_diagnostic "updates: free-space=unreadable"; vgs_tui_warn "Could not check free disk space."
  elif ((avail < 10 * 1024 * 1024 * 1024)); then
    vgs_tui_warn "Less than 10 GiB is free on /. An update can fail when the disk fills up."
  fi
  local name
  local box=("Update ${only:-all}" "")
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

  # An unread system check is a failed part, recorded once the run starts,
  # so a run cancelled at its question writes no outcome.
  if [[ $system_unread == 1 ]]; then
    _updates_part "System packages"
    _updates_fail "System packages" "System packages failed. VGS could not check them for updates. Next: update again later." "System packages could not update" "VGS could not check them for updates. Update again later."
  fi

  local rebuild_run="$rebuild"
  local vgs_before=""
  if [[ $replaces == 1 ]]; then vgs_before="$(_updates_vgs_package_version)"; fi
  # A refused password skips every step that needs it, the snapshot
  # included; the steps that need none still run. A session that never
  # started has nothing to end.
  local denied=0
  if [[ $session == 1 ]] && ! vgs_tui_sudo_session start; then
    denied=1 session=0 snapshot_tool=""
    _updates_diagnostic "updates: sudo=refused"
    local skipped=() skipped_text="" i
    if [[ -n $primary ]] && _updates_in "$primary" "${run[@]}"; then skipped+=("system packages"); fi
    for id in "${run[@]}"; do
      if _updates_file_source "$id"; then skipped+=("${labels[$id],,}"); fi
    done
    if _updates_in aur "${run[@]}"; then skipped+=("AUR packages"); fi
    if [[ $rebuild_run == 1 ]]; then skipped+=("the VGS package"); fi
    for ((i = 0; i < ${#skipped[@]}; i++)); do
      if ((i == 0)); then skipped_text="${skipped[i]}"
      elif ((i == ${#skipped[@]} - 1)); then skipped_text+=" and ${skipped[i]}"
      else skipped_text+=", ${skipped[i]}"
      fi
    done
    if [[ ${#skipped[@]} -gt 0 ]]; then
      _updates_part "System packages"
      _updates_fail "System packages" "VGS could not get permission to change the system, so it skipped $skipped_text. Next: update again and enter your password." "System packages could not update" "VGS could not get permission to change the system, so it skipped $skipped_text. Update again and enter your password."
    fi
  fi
  # A failed snapshot said what went wrong; it does not block the update,
  # but it must not pass for one either.
  if [[ -n $snapshot_tool ]]; then
    status=0
    _updates_snapshot "$snapshot_tool" "$elevator" || status=$?
    if [[ $status -ne 0 ]]; then
      _updates_diagnostic "updates: snapshot=failed exit=$status"; vgs_tui_warn "Snapshot failed. The rest of the update goes on."
    fi
  fi
  # The installed packages before the first package step, which the
  # reboot question compares with those after the last.
  local -A installed=()
  local listed=0
  if [[ $primary == pacman && $replaces == 1 ]]; then
    if out="$(pacman -Q 2>&1)"; then
      listed=1
      while read -r name value; do
        [[ -z $name ]] || installed[$name]="$value"
      done <<<"$out"
    else
      _updates_reboot_unread "updates: installed=unread when=before"
      _updates_diagnostic "$out"
    fi
  fi
  if _updates_in vgs "${run[@]}" && [[ $vgs_step == self ]]; then
    vgs_tui_step "Updating VGS"
    _updates_source vgs VGS "$_updates_vgshell" self update
  fi
  # An AUR build, a file source's install and the orphan removal act on
  # the system the system step left: after a failed or declined system
  # upgrade, whose databases are already synced, they would be a partial
  # upgrade.
  for id in "${run[@]}"; do
    case "$id" in
      vgs|plugins|themes|aur) ;;
      *)
        if [[ $denied == 1 ]] && { [[ $id == "$primary" ]] || _updates_file_source "$id"; }; then continue; fi
        if [[ -n $system_blocked ]] && _updates_file_source "$id"; then
          _updates_results+=("${labels[$id]} skipped. ${system_blocked^}, and these packages install against it.")
          continue
        fi
        _updates_source "$id" "${labels[$id]}" "$_updates_vgshell" pkg run upgrade --manager "$id"
        if [[ $id == "$primary" ]]; then
          case "$_updates_outcome" in
            failed) system_blocked="the system upgrade failed" ;;
            declined) system_blocked="you declined the system upgrade" ;;
          esac
        fi
        ;;
    esac
  done
  if [[ $primary == pacman && $upgrades == 1 && $denied == 0 ]]; then
    if [[ -n $system_blocked ]]; then
      _updates_results+=("Orphaned packages skipped. ${system_blocked^}, and clean-up runs only after a system upgrade.")
    else
      _updates_orphans
    fi
  fi
  if [[ ${#plugins[@]} -gt 0 ]]; then _updates_update_each plugin "${plugins[@]}"; fi
  if [[ ${#themes[@]} -gt 0 ]]; then _updates_update_each theme "${themes[@]}"; fi
  if [[ $session == 1 ]]; then vgs_tui_sudo_session end; fi

  # A missing helper reviews its own clone after the system upgrade,
  # outside Updates' credential session. Without it the AUR builds and
  # the VGS package cannot run.
  local aur_blocked=""
  if [[ $rebuild == 1 && $vgs_step == install-helper && $denied == 0 && -z $system_blocked ]]; then
    vgs_tui_step "Installing paru for VGS updates"
    _updates_source paru Paru _updates_run _updates_install_helper
    if [[ $_updates_outcome == installed ]]; then
      aur_binary=paru
      vgs_step=rebuild
    elif [[ $_updates_outcome == skipped ]]; then
      aur_blocked="you skipped paru at its review"
    elif [[ $_updates_outcome == unknown ]]; then
      aur_blocked="VGS could not read whether paru was installed"
    else
      aur_blocked="paru could not be installed"
    fi
  fi
  [[ -z $system_blocked ]] || aur_blocked="$system_blocked, and AUR packages build against it"
  if [[ -n $aur_blocked ]]; then
    if _updates_in aur "${run[@]}"; then _updates_results+=("AUR skipped. ${aur_blocked^}."); fi
    # A tracked devel vgshell-git (aur-upgrade) builds in the AUR step.
    if [[ $rebuild_run == 1 ]] || { _updates_in vgs "${run[@]}" && [[ $vgs_step == aur-upgrade ]]; }; then
      _updates_results+=("VGS package skipped. ${aur_blocked^}.")
    fi
  elif [[ $denied == 1 ]]; then
    : # The refusal's one result line stands for the AUR and the VGS package.
  elif [[ $rebuild == 1 ]] || _updates_in aur "${run[@]}"; then
    local guarded=0
    if command -v sudo >/dev/null; then
      vgs_tui_sudo_session guard
      guarded=1
    fi
    if _updates_in aur "${run[@]}"; then
      _updates_part "AUR packages"
      if [[ ${#aur_command[@]} -gt 0 ]]; then
        vgs_tui_step "Updating AUR packages"
        local custom_json custom_mode custom_config custom_config_args=()
        custom_json="$(node -e 'process.stdout.write(JSON.stringify(process.argv.slice(1)))' "${aur_command[@]}")"
        custom_mode="$("$_updates_vgshell" pkg review-custom-mode "$custom_json")"
        if [[ $custom_mode == table ]]; then
          # customMode recognizes the table command after stripping its
          # --config. Keep that command's effective configuration in the
          # reviewed run rather than silently taking the helper's default.
          custom_config="$(node "$_updates_tree/bin/lib/pkg-config.js" "${aur_command[0]}" "${aur_command[@]}" |
            node -e 'const answer=JSON.parse(require("fs").readFileSync(0,"utf8")); if(answer.explicit)process.stdout.write(answer.config)')"
          [[ -z $custom_config ]] || custom_config_args=(--config "$custom_config")
          _updates_source aur AUR "$_updates_vgshell" pkg run upgrade --manager aur "${custom_config_args[@]}" "${aur_ignore[@]}"
        else
          _updates_source aur AUR _updates_custom_run "${aur_command[@]}"
        fi
      else
        _updates_source aur AUR "$_updates_vgshell" pkg run upgrade --manager aur "${aur_ignore[@]}"
      fi
      # Never retry a declined or unread transaction. A complete build
      # failure allows the separate reviewed rebuild without a dependency
      # precheck: the helper fails a broken dependency itself.
      if [[ $rebuild_run == 1 && $_updates_outcome != installed ]] &&
          ! [[ $_updates_outcome == failed && $_updates_exit -lt 128 && $_updates_refused == 0 && $_updates_build_complete == 1 && ${#_updates_failed_builds[@]} -gt 0 ]]; then
        rebuild_run=0
        _updates_diagnostic "updates: skipped source=vgshell-git reason=aur-$_updates_outcome"
        case "$_updates_outcome" in
          declined) _updates_results+=("VGS package skipped. You declined the AUR update.") ;;
          skipped) _updates_results+=("VGS package skipped. You skipped the AUR update at its review.") ;;
          unknown) _updates_results+=("VGS package skipped. VGS could not read the AUR result.") ;;
          failed) _updates_results+=("VGS package skipped. The AUR update failed.") ;;
        esac
      fi
    fi
    if [[ $rebuild_run == 1 ]]; then
      vgs_tui_step "Rebuilding the VGS package"
      _updates_source vgshell-git "VGS package" "$_updates_vgshell" pkg run reinstall --manager aur vgshell-git
    fi
    if [[ $guarded == 1 ]]; then vgs_tui_sudo_session end; fi
  fi

  # The packages the run changed, a new version or a new name, and of
  # those the ones that need a reboot.
  local changes=()
  _updates_core=()
  if [[ $listed == 1 ]]; then
    if out="$(pacman -Q 2>&1)"; then
      while read -r name value; do
        if [[ -z $name ]]; then continue
        elif [[ -z ${installed[$name]+set} ]]; then changes+=("install $name")
        elif [[ ${installed[$name]} != "$value" ]]; then changes+=("upgrade $name")
        fi
      done <<<"$out"
    else
      _updates_reboot_unread "updates: installed=unread when=after"
      _updates_diagnostic "$out"
    fi
  fi
  if [[ ${#changes[@]} -gt 0 ]]; then _updates_reboot_packages "${changes[@]}"; fi

  rm -f -- "${_updates_cause_file:?}"
  local ended=finished
  if [[ ${#_updates_failed_parts[@]} -gt 0 ]]; then ended=failed; fi
  # The question and recheck can be interrupted after the package work
  # ends; neither interruption changes the run's recorded outcome.
  if [[ $ended == failed ]]; then _updates_ended failed "$_updates_failed_title" "$_updates_failed_text" "$_updates_failed_remedy"; else _updates_ended finished "" "" ""; fi
  local reboot_status=0
  _updates_reboot "${_updates_core[@]}" || reboot_status=$?
  if [[ $_updates_rebooted == 0 && -n $vgs_before ]] && [[ "$(_updates_vgs_package_version)" != "$vgs_before" ]] && "$_updates_vgshell" pid >/dev/null 2>&1; then
    _updates_part "Shell restart"
    vgs_tui_step "Restarting the shell on the updated VGS"
    local restart_status=0 restart_first=""
    "$_updates_vgshell" restart >"$_updates_run_dir/restart-output" 2>&1 || restart_status=$?
    cat -- "$_updates_run_dir/restart-output"
    IFS= read -r restart_first <"$_updates_run_dir/restart-output" || :
    if [[ $restart_status == 69 && $restart_first == 'vgshell: refused: hyprland=unreachable' ]]; then
      _updates_results+=("The shell restarts at your next login.")
      if [[ $ended == finished ]]; then _updates_ended finished "" "The shell restarts at your next login." shell-restart; fi
    elif [[ $restart_status != 0 ]]; then
      _updates_diagnostic "updates: restart=failed exit=$restart_status"
      _updates_fail "Shell restart" "VGS could not restart. Restart the computer when you are ready." "VGS could not restart" "Restart the computer when you are ready." computer-restart
      vgs_tui_warn "VGS could not restart. Restart the computer when you are ready."
      ended=failed
      _updates_ended failed "$_updates_failed_title" "$_updates_failed_text" "$_updates_failed_remedy"
    fi
  fi
  # The replacement service must own the check and its run-end
  # suppression. After Reboot succeeds, the EXIT writer asks it instead.
  if [[ $_updates_rebooted == 0 ]]; then
    _updates_recheck
  fi
  # Keep the failed parts in view after all end-of-run output.
  _updates_result_list
  [[ $reboot_status == 0 ]] || exit "$reboot_status"
  [[ $ended == finished ]] || exit 1
}

# The outcome lifetime is outside the credential-session subshell, whose
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

  _updates_run_dir="$("$_updates_vgshell" pkg review-run)" || exit 1
  # The outcome's one writer: this EXIT has the run's status, and the
  # credential session's traps in the run's own subshell cannot replace it.
  trap '_updates_outcome_write $?; _updates_cleanup' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  set +e
  (set -Ee; _updates_main)
  status=$?
  exit "$status"
)
