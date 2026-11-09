# No row authenticates against the host user. The nested sandbox shares the
# host's PAM, polkit and faillock, so a sudo, a polkit authentication, a
# keyring unlock or a failed password a row caused would count against the
# owner's own account. harness.sh stands a sentinel for every command that
# asks for one in the PATH directory every sandbox shell starts with, and
# replaces the sandbox tree's bin/vgshell-browser-policy, which runs sudo from
# the system directories alone, with one more. This row, the last, reads
# that each sentinel resolves first on that PATH, or a stub a row stood
# over it that never authenticates, that the tree's writer is still the
# sentinel, and that no sentinel was called during the run. Its control:
# a call through a sentinel after that reading is logged, so an empty log
# is a run that called none, not a sentinel that logs nothing.
# inputs: bin/* shell/* scripts/smoke/fixtures/* shell/plugins/vgs.jarvis/backend/skills/*.md
set -euo pipefail
# The facts are harness.sh's judges' predicates, which smoke_judge_reading
# reads at every row's start and end too.
for name in "${auth_sentinels[@]}"; do
  expect "$name resolves to the sandbox's own stand-in on every shell's PATH" first command_placement "$name" "$shim/$name"
done
for file in "${auth_sentinel_files[@]}"; do
  expect "${file##*/} is the sentinel again, no row's stand-in" sentinel sentinel_state "$file"
done
expect "no row left a sentinel stood over" "" cat -- "$sentinels_stood"
auth_calls() { if [[ -e $auth_log ]]; then cat -- "$auth_log"; fi; }
expect "no row reached sudo, doas, run0, pkexec, su, a mutating loginctl or secret-tool, or the privileged writer" "" auth_calls
auth_before="$(auth_call_count)"
expect "the control's sudo through the shell's PATH runs nothing" 1 bash -c 'PATH="$1" sudo -n true; echo $?' _ "$shell_start_path"
expect "the control's sudo is logged" "$((auth_before + 1))" auth_call_count
expect "the control's call is the one logged" "sudo -n true" tail -n 1 -- "$auth_log"
expect "the control's loginctl enable-linger through the shell's PATH runs nothing" 1 bash -c 'PATH="$1" loginctl enable-linger x; echo $?' _ "$shell_start_path"
expect "the control's loginctl call is the one logged" "loginctl enable-linger x" tail -n 1 -- "$auth_log"
expect "the control's secret-tool store through the shell's PATH runs nothing" 1 bash -c 'PATH="$1" secret-tool store x </dev/null; echo $?' _ "$shell_start_path"
expect "the control's secret-tool call is the one logged" "secret-tool store x" tail -n 1 -- "$auth_log"
expect "the controls logged three calls" "$((auth_before + 3))" auth_call_count
