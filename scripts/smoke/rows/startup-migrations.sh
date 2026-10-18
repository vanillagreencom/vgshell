# The actual core runs selected disabled bundled hooks from its first scan.
# A blocked failure lets the row change source and rescan while running and
# queued snapshots stay retained. The remaining queue covers launch failure,
# timeout, former-id adoption, exclusions and continued unrelated service
# builds. The original startup owners are the must-fail control.
# The timeout case injects a short timer into a disposable core copy. It
# checks deadline wiring, not a latency budget. Polling uses expect_poll's
# existing harness bound and interval; this row adds no performance ceiling.
# inputs: shell/Core/Plugins.qml shell/Core/Registry.qml shell/Core/PluginLogic.js shell/Core/Config.qml shell/Core/ConfigLogic.js shell/Hosts/ServiceHost.qml bin/vgshell-scan scripts/smoke/fixtures/plugins/acme.migrate/* scripts/smoke/fixtures/migrations/* scripts/smoke/rows/start-order.sh
set -euo pipefail

migrations_config="$home/.config/vgshell/shell.json"
migrations_saved="$sandbox/startup-migrations-config.json"
migrations_root="$home/.local/state/vgshell/migration-fixture"
migrations_fixture="$repo/scripts/smoke/fixtures/plugins/acme.migrate"
cp -- "$migrations_config" "$migrations_saved"
expected_errors+=('plugins: migration id=acme\.migrate-a-launch failure=start-failed'
  'Process failed to start, likely because the binary could not be found.*migrate'
  'plugins: migration id=acme\.migrate-b-fail failure=exit-failed'
  'plugins: migration id=acme\.migrate-c-timeout failure=timeout'
  'plugins: hidden by a higher-precedence plugin with the same id: acme\.migrate-g-hidden')

migrations_setup() {
  "${sandbox_env[@]}" python3 "$repo/scripts/smoke/fixtures/migrations/setup.py" "$migrations_fixture" "$1" "$home"
}
migrations_attempts() {
  python3 - "$migrations_root/attempts" <<'PY'
import collections,json,pathlib,sys
path=pathlib.Path(sys.argv[1])
rows=[json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
print(json.dumps(dict(sorted(collections.Counter(row["id"] for row in rows).items())),separators=(",", ":")))
PY
}
migrations_cleaned() { if [[ -f $migrations_root/cleaned ]]; then echo yes; else echo no; fi; }
migrations_acceptance() {
  python3 - "$migrations_root" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
if not (root/"cleaned").is_file(): sys.exit("migration did not run")
if any((root/("old-sync."+suffix)).exists() for suffix in ("service","timer")): sys.exit("old units remain")
PY
}
migrations_old_units() {
  local count=0 suffix
  for suffix in service timer; do [[ ! -e $migrations_root/old-sync.$suffix ]] || count=$((count + 1)); done
  echo "$count"
}
migrations_failure() { log_lines "plugins: migration id=acme\\.migrate-$1 failure=$2"; }
migrations_revision() { ipc shell listPlugins | py_reply 'import json,sys; print(next((r["revision"] for r in json.load(sys.stdin)["plugins"] if r["id"]==sys.argv[1]),"absent"))' "$1"; }
migrations_retained() { if [[ -d $rt_dir/vgshell-sources-$shell_qs_pid/$1 ]]; then echo yes; else echo no; fi; }
migrations_snapshot() {
  python3 - "$migrations_root/attempts" "$rt_dir/vgshell-sources-$shell_qs_pid" <<'PY'
import json,pathlib,sys
rows=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
print("yes" if rows and all(pathlib.Path(row["snapshot"]).parent == pathlib.Path(sys.argv[2]) for row in rows) else "no")
PY
}
migrations_release() {
  python3 - "$migrations_root/release" <<'PY'
import os,sys
descriptor=os.open(sys.argv[1],os.O_WRONLY|os.O_NONBLOCK)
try: os.write(descriptor,b"x")
finally: os.close(descriptor)
PY
}

if stop_shell && copy_tree startup-migrations-original; then
  # copy_tree's sandbox is outside the checkout. Read the exact original
  # owners, rather than a copied model or a deletion of the new hook.
  case "$sandbox/tree-startup-migrations-original/" in
    "$source_repo/"*) fail "startup migration control must live outside the worktree" ;;
    *)
      git -C "$source_repo" show 0b9b185809ea8bfa13a2f892c4caabaec239698f:shell/Core/Plugins.qml >"$sandbox/tree-startup-migrations-original/shell/Core/Plugins.qml"
      git -C "$source_repo" show 0b9b185809ea8bfa13a2f892c4caabaec239698f:shell/Core/Registry.qml >"$sandbox/tree-startup-migrations-original/shell/Core/Registry.qml"
      migrations_setup "$sandbox/tree-startup-migrations-original"
      if start_shell "$sandbox/tree-startup-migrations-original" "$sandbox/startup-migrations-original.log"; then
        expect_poll "control: the original core builds the unrelated enabled service" True record_exists acme.migrate-e-enabled
        expect "control: the original startup leaves the planted old units" 2 migrations_old_units
        if migrations_acceptance >"$sandbox/startup-migrations-control.log" 2>&1; then
          fail "control: the migration acceptance assertion accepted the original startup"
        else
          ok "control: the migration acceptance assertion rejects the original startup"
          control_output "$sandbox/startup-migrations-control.log"
        fi
        expect "control: the original startup runs no hook" '{}' migrations_attempts
        check_unexpected_log "original startup log" "$instance_log"
      fi
      ;;
  esac
fi

if stop_shell && copy_tree startup-migrations \
  && edit_tree startup-migrations shell/Core/Plugins.qml \
    'interval: (1220 + 30) * 1000' \
    'interval: root.migration !== null && root.migration.id === "acme.migrate-c-timeout" ? 1 : (1220 + 30) * 1000'; then
  migrations_setup "$sandbox/tree-startup-migrations"
  if start_shell "$sandbox/tree-startup-migrations" "$sandbox/startup-migrations.log"; then
    expect_poll "a launch failure is recorded without stopping startup" 1 migrations_failure a-launch start-failed
    expect_poll "the disabled failing hook starts once" '{"acme.migrate-b-fail":1}' migrations_attempts
    expect_poll "an unrelated enabled service builds while migration waits" True record_exists acme.migrate-e-enabled
    expect "a user can enable a plugin while its hook waits in the queue" ok ipc shell setPluginEnabled acme.migrate-d-late true
    expect_poll "the newly enabled plugin builds without waiting for the queue" True record_exists acme.migrate-d-late
    expect "former-id adoption keeps the migration plugin disabled" False plugin_enabled acme.migrate-d-clean
    migrations_running_revision="$(migrations_revision acme.migrate-b-fail)"
    migrations_queued_revision="$(migrations_revision acme.migrate-d-clean)"
    # Change both sources while their published snapshots are held. The
    # queued hook must still clean up, rather than execute the changed file.
    for migrations_id in acme.migrate-b-fail acme.migrate-d-clean; do
      printf '#!/bin/sh\nexit 9\n' >"$sandbox/tree-startup-migrations/shell/plugins/$migrations_id/migrate"
    done
    rescan "a rescan after changing queued migration sources completes"
    # The changed scan also retains the registry's previous manifest map.
    # Scan again so only the migration owner can retain the old snapshots.
    rescan "an unchanged rescan while the migration waits completes"
    expect "the scan retains the running migration snapshot" yes migrations_retained "$migrations_running_revision"
    expect "the scan retains the queued migration snapshot" yes migrations_retained "$migrations_queued_revision"
    migrations_release
    expect_poll "a hook failure is recorded without stopping its queue" 1 migrations_failure b-fail exit-failed
    expect_poll "a timed-out hook is recorded without stopping its queue" 1 migrations_failure c-timeout timeout
    expect_poll "the queued snapshot removes the planted old units" yes migrations_cleaned
    expect "the executed startup satisfies the same migration acceptance assertion" '' migrations_acceptance
    expect "no planted old service or timer remains" 0 migrations_old_units
    expect "the disabled migration plugin never builds a service" False record_exists acme.migrate-d-clean
    expect "the unrelated enabled service stays built after failure and timeout" True record_exists acme.migrate-e-enabled
    expect "the plugin enabled during the queue keeps its service" True record_exists acme.migrate-d-late
    expect "hooks execute only from immutable snapshots" yes migrations_snapshot
    # The timer can kill its child before Python starts. Both outcomes
    # prove the timeout; only the completed hooks owe one attempts record.
    migrations_once="$(migrations_attempts)"
    expect "the failed and successful hooks ran once and all excluded hooks stayed absent" yes \
      python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("yes" if d.pop("acme.migrate-c-timeout",0) in (0,1) and d=={"acme.migrate-b-fail":1,"acme.migrate-d-clean":1} else "no")' "$migrations_once"
    expect "hook stdout and stderr never reach the shell log" 0 log_lines migration-private-output
    rescan "a later unchanged rescan completes"
    expect "rescan does not rerun startup hooks" "$migrations_once" migrations_attempts
    expect "rescan does not retry a failed launch" 1 migrations_failure a-launch start-failed
    expect "rescan does not retry a failed hook" 1 migrations_failure b-fail exit-failed
    expect "rescan does not retry a timed-out hook" 1 migrations_failure c-timeout timeout
    check_unexpected_log "startup migration log" "$instance_log"
  fi
fi

# A new shell starts a new queue. Reset the planted state and original
# fixture sources, then release the failing hook after it acknowledges.
if stop_shell; then
  migrations_setup "$sandbox/tree-startup-migrations"
  if start_shell "$sandbox/tree-startup-migrations" "$sandbox/startup-migrations-retry.log"; then
    expect_poll "a fresh shell retries the hook once" '{"acme.migrate-b-fail":1}' migrations_attempts
    expect "the fresh shell can also enable a queued plugin" ok ipc shell setPluginEnabled acme.migrate-d-late true
    migrations_release
    expect_poll "a fresh shell runs the cleanup again" yes migrations_cleaned
    expect "a fresh shell also records a new launch failure" 1 migrations_failure a-launch start-failed
    check_unexpected_log "startup migration retry log" "$instance_log"
  fi
fi

if stop_shell; then
  for migrations_id in acme.migrate-f-user acme.migrate-g-hidden; do
    rm -rf -- "$home/.config/vgshell/plugins/$migrations_id"
  done
  rm -rf -- "$migrations_root" "$sandbox/tree-startup-migrations" "$sandbox/tree-startup-migrations-original"
  user_config_restore "$migrations_saved"
  start_shell "$repo" "$sandbox/startup-migrations-final.log" || fail "startup migrations restores the incoming shell"
fi
