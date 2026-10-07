# The shell runs every QML garbage collection to completion: shell.qml's
# Env pragma sets QV4_GC_TIMELIMIT to 0 over an inherited value (the
# comment at the pragma). The crash that setting avoids was never
# reproduced, so the row checks the setting, not the crash: it starts the
# shell with QV4_GC_TIMELIMIT=1 and reads 0 back through Probe's
# environment reader.
# Control: a copy of the tree without the pragma, started the same way,
# reads 1, which also holds only while bin/vgshell passes its environment
# to qs. The row ends with the tree's shell under the harness's own
# environment.
# No latency budget. A start's ping is polled every 0.2 s.
# inputs: shell/shell.qml bin/vgshell
set -euo pipefail

stop_shell || :
if start_shell "$repo" "$sandbox/collector-qs.log" bar QV4_GC_TIMELIMIT=1; then
  expect "the shell's pragma sets QV4_GC_TIMELIMIT over the inherited value" 0 ipc smoke environment QV4_GC_TIMELIMIT
fi

if copy_tree collector-incremental && edit_tree collector-incremental shell/shell.qml $'//@ pragma Env QV4_GC_TIMELIMIT = 0\n' ''; then
  stop_shell || :
  if start_shell "$sandbox/tree-collector-incremental" "$sandbox/collector-incremental-qs.log" bar QV4_GC_TIMELIMIT=1; then
    expect "control: without the pragma the shell keeps the inherited QV4_GC_TIMELIMIT" 1 ipc smoke environment QV4_GC_TIMELIMIT
  fi
fi

stop_shell || :
start_shell "$repo" "$sandbox/collector-restored-qs.log" || fail "the collector row restores the tree's shell"
