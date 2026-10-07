# The shell runs every QML garbage collection to completion: shell.qml's
# Env pragma sets QV4_GC_TIMELIMIT to 0 over an inherited value, since Qt
# 6.11.2's incremental collector can destroy one object twice (the comment
# at the pragma). The row starts the shell with QV4_GC_TIMELIMIT=1 and
# reads 0 back through Probe's environment reader, then rebuilds vgs.bar
# and vgs.themes from user copies that hide the bundled ones and from the
# bundled ones again, round after round, with the shell answering ping
# after each round and its bars back at the end. The rounds guard the
# rebuild path; they reproduced no crash on the unfixed shell.
# Control: a copy of the tree without the pragma, started the same way,
# reads 1. The row ends with the tree's shell under the harness's own
# environment and no plugin copy left.
# No latency budget. Rescans and the bar count are polled every 0.2 s,
# and a start's ping every 0.2 s.
# inputs: shell/shell.qml shell/Core/Plugins.qml shell/Core/Registry.qml shell/plugins/vgs.bar/* shell/plugins/vgs.themes/*
set -euo pipefail
collector_rounds=10
collector_plugins="$home/.config/vgshell/plugins"
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.(bar|themes) at ')

stop_shell || :
if start_shell "$repo" "$sandbox/collector-qs.log" bar QV4_GC_TIMELIMIT=1; then
  expect "the shell's pragma sets QV4_GC_TIMELIMIT over the inherited value" 0 ipc smoke environment QV4_GC_TIMELIMIT
  mkdir -p -- "$collector_plugins"
  for ((round = 1; round <= collector_rounds; round++)); do
    for id in vgs.bar vgs.themes; do
      rm -rf -- "${collector_plugins:?}/$id"
      cp -R -- "$repo/shell/plugins/$id" "$collector_plugins/$id"
      # A new revision on every round, so the rescan rebuilds the copy.
      for file in "$collector_plugins/$id"/*.qml; do printf '\n// collector round %s\n' "$round" >>"$file"; done
    done
    rescan "round $round: the user copies of vgs.bar and vgs.themes are scanned"
    rm -rf -- "${collector_plugins:?}/vgs.bar" "${collector_plugins:?}/vgs.themes"
    rescan "round $round: the bundled vgs.bar and vgs.themes are scanned again"
    pong="$(ipc shell ping 2>/dev/null)" || pong=unanswered
    if [[ $pong != ok ]]; then fail "round $round: the shell answers ping: got $pong"; break; fi
  done
  [[ $pong != ok ]] || ok "the shell answers ping after $collector_rounds rebuild rounds"
  expect_poll "every monitor has its bar after the rebuild rounds" "$monitors" bar_count
fi
rm -rf -- "${collector_plugins:?}/vgs.bar" "${collector_plugins:?}/vgs.themes"

if copy_tree collector-incremental && edit_tree collector-incremental shell/shell.qml $'//@ pragma Env QV4_GC_TIMELIMIT = 0\n' ''; then
  stop_shell || :
  if start_shell "$sandbox/tree-collector-incremental" "$sandbox/collector-incremental-qs.log" bar QV4_GC_TIMELIMIT=1; then
    expect "control: without the pragma the shell keeps the inherited QV4_GC_TIMELIMIT" 1 ipc smoke environment QV4_GC_TIMELIMIT
  fi
fi

stop_shell || :
start_shell "$repo" "$sandbox/collector-restored-qs.log" || fail "the collector row restores the tree's shell"
