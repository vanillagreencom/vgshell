# A plugin whose entry points cannot take what the core assigns is not
# built and keeps nothing it was lent: no hold, no background surface.
# It reads what rows/capability-release.sh leaves: acme.probe disabled, so
# the lock the broken fixture asks for is free and acme.tick stands alone
# in the centre section. While acme.probe holds the lock the core waits
# and builds nothing, so it refuses nothing.
# It owes no restart notice either, though rows/manager.sh has planted its
# control copies in the sandbox's shell/ by then, so the core differs from
# the one the shell started over: the engine loaded the fixture's files.
# inputs: shell/Core/PluginLogic.js scripts/smoke/fixtures/plugins/acme.broken/* scripts/smoke/fixtures/plugins/acme.nowidget/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Notices.qml shell/Hosts/BackgroundHost.qml scripts/smoke/rows/manager.sh scripts/smoke/rows/sources.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/capability-release.sh
set -euo pipefail
broken="$home/.config/vgshell/plugins/acme.broken"
mkdir -p "$broken"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.broken/." "$broken/"
expected_errors+=('plugins: acme\.broken (service|background) not built: ')
rescan "rescan after adding the broken fixture answers ok"
expect_poll "the broken fixture is discovered" True plugin_known acme.broken
expect "enabling the broken fixture is allowed" ok ipc shell setPluginEnabled acme.broken true
expect_log "the core logged both refused builds of the broken fixture" 2 'plugins: acme\.broken (service|background) not built: '
expect "the broken fixture has no build record" False record_exists acme.broken
restart_owed() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["restart"]))'; }
expect "the refused builds owe no restart notice" false restart_owed
expect "the refused builds leave no notice surface" 0 layer_count vgs:notice
expect "the broken fixture keeps no capability hold" null lent holders.lock
expect_poll "the background host shows no surface for a failed build" 0 layer_count vgs:background
# The Settings window lists each failed build among the plugin's errors,
# once per kind however many screens it failed on.
expect "the Settings window opens on the broken fixture's page" ok ipc shell summon window vgs.settings '{"plugin":"acme.broken"}'
broken_errors() { settings_rows | py_reply 'import json,sys; r=[r for r in json.load(sys.stdin) if r["id"] == "acme.broken"][0]; print(json.dumps(sorted(e.split(" not built")[0] for e in r["errors"])))'; }
expect_poll "the broken fixture's failed builds are its errors, one per kind" '["build failed: background: background", "build failed: service: service"]' broken_errors
expect "the Settings window closes after the failed builds" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone after the failed builds" 0 window_count Plugins
expect "disabling the broken fixture is allowed" ok ipc shell setPluginEnabled acme.broken false

# A nonvisual root can accept the facade but cannot belong to a host.
printf 'import QtQuick\nQtObject { property var shell: null; property var screen: null }\n' >"$broken/Item.qml"
rescan "rescan after changing the broken root answers ok"
expect "enabling the nonvisual root is allowed" ok ipc shell setPluginEnabled acme.broken true
expect_log "both nonvisual roots are refused before publication" 2 'plugins: acme\.broken (service|background) not built: entry point must be an Item'
expect "the nonvisual root has no build record" False record_exists acme.broken
expect "the nonvisual root keeps no capability hold" null lent holders.lock
expect_poll "the nonvisual background leaves no surface" 0 layer_count vgs:background
expect "disabling the nonvisual root is allowed" ok ipc shell setPluginEnabled acme.broken false
background_failures() { sed -n 's/.*smoke: backgroundFailures=//p' "$instance_log" | tail -n 1; }
expect_poll "the host remembers the installed broken background" 1 background_failures
printf 'import QtQuick\nItem { property var shell: null; property var screen: null }\n' >"$broken/Item.qml"
rescan "rescan after repairing the disabled plugin answers ok"
expect_poll "a source repair releases its stale background failure record" 0 background_failures
printf 'import QtQuick\nQtObject { property var shell: null; property var screen: null }\n' >"$broken/Item.qml"
rescan "the removal control's broken source is rescanned"
expect "the removal control enables the broken plugin" ok ipc shell setPluginEnabled acme.broken true
expect_poll "the removal control reaches a retained failure record" 1 background_failures
failed_output=SMOKE-FAILED
expect "a failed plugin can meet a new monitor" ok hypr output create headless "$failed_output"
expect_poll "the new monitor records its refused background" 1 ipc smoke failedBuilds "background:$failed_output"
expect "the failed background's monitor can be removed" ok hypr output remove "$failed_output"
expect_poll "the removed monitor leaves no background failure record" 0 ipc smoke failedBuilds "background:$failed_output"
expect "monitor removal preserves the screenless service failure" 1 ipc smoke failedBuilds service
expect "monitor removal preserves the remaining background failure" 1 ipc smoke failedBuilds "background:$(bar_key | sed 's/^bar://')"
expect "the removal control disables the broken plugin" ok ipc shell setPluginEnabled acme.broken false
python3 - "$broken" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1])
PY
rescan "rescan after removing the broken plugin answers ok"
expect_poll "removing the plugin releases its background failure record" 0 background_failures

# A bar widget that cannot take what the core assigns is not built, and the
# section's entries stay aligned with the layout: an edit to the entry after
# it reaches that entry's own widget, never a neighbour's settings.
# The user file records the fixture with a plugins row, the record a Hide
# leaves, so the first presence does not place it: the row's own entry is
# its only one, and once removed it stays out through later rescans.
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "acme.nowidget"] + [{"id": "acme.nowidget"}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
nowidget="$home/.config/vgshell/plugins/acme.nowidget"
mkdir -p "$nowidget"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.nowidget/." "$nowidget/"
expected_errors+=('plugins: acme\.nowidget bar-widget not built: ')
rescan "rescan after adding the widget that cannot be built answers ok"
expect_poll "the widget that cannot be built is discovered" True plugin_known acme.nowidget
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["bar"]["layout"]["center"].insert(0, {"id": "acme.nowidget"})
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
expect_log "the core logged the refused widget build on every bar" "$monitors" 'plugins: acme\.nowidget bar-widget not built: '
expect_widgets "the section shows the widget after the one that failed" '["acme.tick"]'
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
[e for e in d["bar"]["layout"]["center"] if e["id"] == "acme.tick"][0]["format"] = "aligned"
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
expect_poll "an edit after a failed entry reaches its own widget" '"aligned"' read_tick format
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["bar"]["layout"]["center"] = [e for e in d["bar"]["layout"]["center"] if e["id"] != "acme.nowidget"]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
expect_widgets "removing the failed entry leaves the widget in place" '["acme.tick"]'
