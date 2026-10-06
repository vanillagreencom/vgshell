# A monitor that goes away takes its bar with it, under the key the bar
# was built under, and leaves no build record behind.
# inputs: shell/Hosts/BarHost.qml shell/Core/Registry.qml shell/Core/Plugins.qml
set -euo pipefail
extra_output=SMOKE-2
bar_hosts() { ipc shell built | py_reply 'import json,sys; print(json.dumps(sorted(k for k in json.load(sys.stdin) if k.startswith("bar:"))))'; }
before_hosts="$(bar_hosts)"
expect "the nested compositor adds a monitor" ok hypr output create headless "$extra_output"
expect_poll "the new monitor gets a bar" "$((monitors + 1))" bar_count
extra_listed() { bar_hosts | py_reply 'import json,sys; print(("bar:" + sys.argv[1]) in json.load(sys.stdin))' "$extra_output"; }
expect_poll "the new bar is in the build records" True extra_listed
expect "the nested compositor removes the monitor" ok hypr output remove "$extra_output"
expect_poll "the removed monitor's bar surface is gone" "$monitors" bar_count
expect_poll "the removed monitor's bar left the build records" "$before_hosts" bar_hosts

monitors_control_restore() {
  stop_shell || :
  start_shell "$repo" "$sandbox/monitors-restored-qs.log" || fail "the monitors control restores the repository shell"
}

if copy_tree monitors-keeps-empty-record && edit_tree monitors-keeps-empty-record shell/Core/Plugins.qml \
    'if (next[hostKey].length === 0) delete next[hostKey];' \
    'if (false && next[hostKey].length === 0) delete next[hostKey];'; then
  stop_shell || :
  if start_shell "$sandbox/tree-monitors-keeps-empty-record" "$sandbox/monitors-keeps-empty-record-qs.log"; then
    control_output=SMOKE-2-CONTROL
    control_listed() { bar_hosts | py_reply 'import json,sys; print(("bar:" + sys.argv[1]) in json.load(sys.stdin))' "$control_output"; }
    expect "control: the keeps-empty-record copy adds a monitor" ok hypr output create headless "$control_output"
    expect_poll "control: the keeps-empty-record copy records the new bar" True control_listed
    expect "control: the keeps-empty-record monitor can be removed" ok hypr output remove "$control_output"
    expect_poll "control: the shell sees the monitor control output leave" "$monitors" bar_count
    expect "control: a build registry that keeps empty host keys keeps the removed monitor record" True control_listed
  fi
  monitors_control_restore
fi
