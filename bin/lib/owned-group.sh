#!/usr/bin/env bash
# Private Bash job-stop API. owned-group.py executes isolated queries;
# jobspec signaling belongs here because only this Bash owns its job table.
owned_group_stop() { # PID: an asynchronous job this Bash caller started
  local pid="$1" spec job_pid rest
  # Bash's jobspec kill blocks SIGCHLD and skips already reaped members;
  # a numeric kill can instead signal a reused pid (Bash jobs.c::kill_pid).
  while read -r spec job_pid rest; do
    [[ $job_pid == "$pid" && $spec == \[* ]] || continue
    spec="${spec#\[}"
    builtin kill -TERM -- "%${spec%%]*}" 2>/dev/null || true
    return
  done < <(jobs -l)
}
