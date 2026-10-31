#!/usr/bin/env bash
# The scratch-directory guard at the top of the suites that remove their
# scratch directory on exit: scripts/vgshell-rows.sh (sourced by every
# scripts/test-vgshell*.sh) and the suites below that make their own. A
# stub mktemp first on PATH answers each way a failed or wrong mktemp can,
# and each subject runs from a disposable caller directory inside this
# suite's scratch. Each case pins exit 1 and the first stderr line, and
# requires the caller directory, its sentinel and any file mktemp named to
# survive. The subjects are a fixed list: the other scratch-directory makers
# under scripts/ assign `mktemp -d` alone, and some of them start a sandbox,
# so they are not run here.
#
# The control at the end plants the old `cd "$(mktemp -d)"` shape in a copy
# of scripts/vgshell-rows.sh and requires the failing-mktemp case to go red,
# which it does by deleting the disposable caller directory.
#
# Exit 0 when every case and the control hold, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

tmp="$(mktemp -d)" || { echo "test-scratch-dirs: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-scratch-dirs: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
want_status=1
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# A regular file for the stub to name as the directory it made.
regular="$tmp/regular-file"
echo keep >"$regular"

# Stub answers: name | stub body | the refusal key the guard must print.
# `failed-dot` exits 1 but prints `.`, which the old shape resolved to the
# caller's directory on every bash version.
stubs=(
  "failed-dot|printf '.\\n'; exit 1|scratch=mktemp-failed"
  "failed-empty|exit 1|scratch=mktemp-failed"
  "empty|exit 0|scratch=not-a-directory"
  "regular-file|printf '%s\\n' '$regular'; exit 0|scratch=not-a-directory"
)
for entry in "${stubs[@]}"; do
  IFS='|' read -r name body _ <<<"$entry"
  mkdir -p "$tmp/stub-$name"
  printf '#!/bin/sh\n%s\n' "$body" >"$tmp/stub-$name/mktemp"
  chmod +x "$tmp/stub-$name/mktemp"
done

# Subjects: label | the script bash runs | its arguments. The library is
# sourced by a driver named test-scratch-driver, the name its refusals take.
subjects=(
  "vgshell-rows.sh|-c|source \"\$1\"|test-scratch-driver|$repo/scripts/vgshell-rows.sh"
  "test-launcher-file-search.sh|$repo/scripts/test-launcher-file-search.sh"
  "test-notifications-images.sh|$repo/scripts/test-notifications-images.sh"
  "test-notifications-token-status.sh|$repo/scripts/test-notifications-token-status.sh"
  "test-sandbox-shots.sh|$repo/scripts/test-sandbox-shots.sh"
  "test-smoke-verdict.sh|$repo/scripts/test-smoke-verdict.sh"
  "test-readme-shots.sh|$repo/scripts/test-readme-shots.sh"
)

# run PREFIX STUB KEY BASH_ARGS...: run bash BASH_ARGS from a fresh caller
# directory with the stub first on PATH. Returns 0 when it exited 1 with
# `PREFIX: KEY` first on stderr and left the caller, its sentinel and the
# regular file in place; otherwise 1, with what broke in `problems`.
cases=0
problems=()
run() {
  local prefix="$1" stub="$2" key="$3" caller status=0 first
  shift 3
  cases=$((cases + 1))
  caller="$tmp/case-$cases/caller"
  mkdir -p "$caller"
  echo keep >"$caller/sentinel"
  (cd -- "$caller" && env -i PATH="$tmp/stub-$stub:$PATH" HOME="$tmp/home" TMPDIR="$tmp" \
    timeout 60 bash "$@" >"$tmp/out" 2>"$tmp/err") || status=$?
  problems=()
  if ! first="$(head -n 1 -- "$tmp/err")"; then
    problems+=("stderr=unreadable")
  fi
  [[ $status -eq $want_status ]] || problems+=("exit=$status")
  [[ $first == "$prefix: $key"* ]] || problems+=("stderr=[$first]")
  [[ -f $caller/sentinel ]] || problems+=("caller=removed")
  [[ -f $regular ]] || { problems+=("regular-file=removed"); echo keep >"$regular"; }
  [[ ${#problems[@]} -eq 0 ]]
}

for subject in "${subjects[@]}"; do
  IFS='|' read -r -a args <<<"$subject"
  label="${args[0]}"
  args=("${args[@]:1}")
  if [[ $label == vgshell-rows.sh ]]; then prefix=test-scratch-driver; else prefix="${label%.sh}"; fi
  for entry in "${stubs[@]}"; do
    IFS='|' read -r name _ key <<<"$entry"
    if run "$prefix" "$name" "$key" "${args[@]}"; then
      ok "$label with mktemp $name refuses and keeps the caller"
    else
      fail "$label with mktemp $name: ${problems[*]}"
    fi
  done
done

# The world owns acquisition for a suite that enters it before allocating
# scratch. A failed allocator must never arm deletion of its returned name.
want_status=77
for entry in "${stubs[@]}"; do
  IFS='|' read -r name _ _ <<<"$entry"
  if run gpu-fence "$name" 'status=not-measured reason=root-failed' "$repo/scripts/smoke/gpu-fence.sh" true; then
    ok "the world with mktemp $name refuses before acquiring deletion rights"
  else
    fail "the world with mktemp $name: ${problems[*]}"
  fi
done
world_guard='[[ -d $fence_dir && ! -L $fence_dir ]] || { fault root-failed; exit 77; }'
world_text="$(<"$repo/scripts/smoke/gpu-fence.sh")" || { fail "world acquisition control: source unreadable"; exit 1; }
world_rest="${world_text#*"$world_guard"}"
if [[ $world_rest == "$world_text" || $world_rest == *"$world_guard"* ]]; then
  fail "world acquisition control: the guard does not match once"
else
  mkdir -p "$tmp/world-control/scripts/smoke"
  printf '%s\n' "${world_text/"$world_guard"/:}" >"$tmp/world-control/scripts/smoke/gpu-fence.sh"
  if run gpu-fence regular-file 'status=not-measured reason=root-failed' "$tmp/world-control/scripts/smoke/gpu-fence.sh" --checkout "$repo" true; then
    fail "control: the world without acquisition validation kept its case green"
  elif [[ " ${problems[*]} " == *" regular-file=removed "* ]]; then
    ok "control: a world without acquisition validation deletes the allocator's disposable file"
  else
    fail "control: the world went red without deleting its disposable file: ${problems[*]}"
  fi
fi
# A failed mktemp is root-failed, never the owner record's key: a copy that
# names it owner-record-unreadable must turn the failing-mktemp case red.
mktemp_refusal='.XXXXXX")" || { fault root-failed; exit 77; }'
mktemp_mislabel='.XXXXXX")" || { fault owner-record-unreadable; exit 77; }'
mktemp_rest="${world_text#*"$mktemp_refusal"}"
if [[ $mktemp_rest == "$world_text" || $mktemp_rest == *"$mktemp_refusal"* ]]; then
  fail "owner record control: the mktemp refusal does not match once"
else
  mkdir -p "$tmp/owner-control/scripts/smoke"
  printf '%s\n' "${world_text/"$mktemp_refusal"/"$mktemp_mislabel"}" >"$tmp/owner-control/scripts/smoke/gpu-fence.sh"
  if run gpu-fence failed-empty 'status=not-measured reason=root-failed' "$tmp/owner-control/scripts/smoke/gpu-fence.sh" --checkout "$repo" true; then
    fail "control: a failed mktemp named as the owner record kept its case green"
  elif [[ " ${problems[*]} " == *" stderr=[gpu-fence: status=not-measured reason=owner-record-unreadable]"* ]]; then
    ok "control: a failed mktemp named as the owner record turns its case red"
  else
    fail "control: a failed mktemp named as the owner record went red for another reason: ${problems[*]}"
  fi
fi
want_status=1

# Control: the old shape in a copy of the library. The substitution must
# match exactly once and change the copy.
guard='tmp="$(mktemp -d)" || { echo "$(basename -- "$0" .sh): scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "$(basename -- "$0" .sh): scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"'
old='tmp="$(cd -- "$(mktemp -d)" && pwd -P)"'
if ! text="$(cat -- "$repo/scripts/vgshell-rows.sh")"; then
  fail "control: scripts/vgshell-rows.sh is unreadable"
elif rest="${text#*"$guard"}"; [[ $rest == "$text" || $rest == *"$guard"* ]]; then
  fail "control: the guard block is not in scripts/vgshell-rows.sh exactly once"
else
  mkdir -p "$tmp/mutant/scripts"
  printf '%s\n' "${text/"$guard"/"$old"}" >"$tmp/mutant/scripts/vgshell-rows.sh"
  if run test-scratch-driver failed-dot scratch=mktemp-failed \
    -c 'source "$1"' test-scratch-driver "$tmp/mutant/scripts/vgshell-rows.sh"; then
    fail "control: the old shape in a copy of vgshell-rows.sh kept the caller"
  elif [[ " ${problems[*]} " != *" caller=removed "* ]]; then
    fail "control: the old shape went red without removing the caller: ${problems[*]}"
  else
    ok "control: the old shape in a copy of vgshell-rows.sh removes the caller"
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "test-scratch-dirs: failures=$failures"
  exit 1
fi
echo "test-scratch-dirs: ok"
