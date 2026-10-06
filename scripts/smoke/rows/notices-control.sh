# Control for scripts/smoke/rows/notices.sh's enable trigger: a copy of the
# tree whose Plugins.setEnabled no longer calls Notices.enabled runs as the
# guarded shell, and enabling acme.needs, which still misses a command it
# needs, must raise no notice. Notices.enabled runs before setPluginEnabled
# replies, so the lending record read after the reply is decisive. The same
# copy is the control for pluginInstalled's wait in rows/notices.sh: when a
# scan ends, its Notices runs only the callbacks waiting for an earlier
# scan, so pluginInstalled's one scan lands and raises no notice. The notice
# is raised in the turn the revision reaches the scan, so a read once
# scanRevision reaches it is decisive. The copy's Notices.dismiss also
# records no rest, the control for rows/notices.sh's rest after Not now:
# an offer raises the notice, Escape closes it, and the same reading of the
# lending record finds the plugin's offers not resting. The copy
# holds its own bin/, since bin/vgshell finds the tree from its own real path,
# and its own shell/; config/ and themes/ are links to the sandbox's. The
# row stops the shell rows/read-only-prefix.sh started, starts the copy
# through harness.sh's start_shell and leaves it running for
# rows/hidpi.sh, which stops it.
# inputs: shell/Core/Plugins.qml shell/Core/Notices.qml scripts/smoke/fixtures/plugins/acme.needs/* scripts/smoke/rows/notices.sh
set -euo pipefail
mutant="$sandbox/notice-mutant"
mkdir -p -- "$mutant"
cp -R -- "$repo/shell" "$mutant/shell"
cp -R -- "$repo/bin" "$mutant/bin"
for dir in config themes; do ln -s -- "$repo/$dir" "$mutant/$dir"; done
for file in VERSION LICENSE README.md; do cp -- "$repo/$file" "$mutant/$file"; done
trigger='        if (enabled) Notices.enabled(id);
'
plugins_qml="$mutant/shell/Core/Plugins.qml"
cp -- "$plugins_qml" "$sandbox/notice-mutant-Plugins.qml.orig"
if python3 -c '
import sys
path, needle = sys.argv[1:]
text = open(path).read()
if text.count(needle) != 1:
    sys.exit("the enable trigger occurs %d times" % text.count(needle))
open(path, "w").write(text.replace(needle, ""))' "$plugins_qml" "$trigger" && ! cmp -s -- "$plugins_qml" "$sandbox/notice-mutant-Plugins.qml.orig"; then
  ok "the control copy drops the enable trigger, which occurs once"
else
  fail "the control copy could not drop the enable trigger from $plugins_qml"
fi
notices_qml="$mutant/shell/Core/Notices.qml"
due='            const due = root.afterScans.filter(a => a.scan <= revision);
'
cp -- "$notices_qml" "$sandbox/notice-mutant-Notices.qml.orig"
if python3 -c '
import sys
path, needle = sys.argv[1:]
text = open(path).read()
if text.count(needle) != 1:
    sys.exit("the due filter occurs %d times" % text.count(needle))
open(path, "w").write(text.replace(needle, needle.replace("a.scan <= revision", "a.scan < revision")))' "$notices_qml" "$due" && ! cmp -s -- "$notices_qml" "$sandbox/notice-mutant-Notices.qml.orig"; then
  ok "the control copy runs no callback waiting for the scan that just ended, its due filter occurring once"
else
  fail "the control copy could not change the due filter in $notices_qml"
fi
rest_record='        next[notice.id] = now + Logic.NOTICE_OFFER_REST_MS;
'
cp -- "$notices_qml" "$sandbox/notice-mutant-Notices.qml.due"
if python3 -c '
import sys
path, needle = sys.argv[1:]
text = open(path).read()
if text.count(needle) != 1:
    sys.exit("the rest record occurs %d times" % text.count(needle))
open(path, "w").write(text.replace(needle, ""))' "$notices_qml" "$rest_record" && ! cmp -s -- "$notices_qml" "$sandbox/notice-mutant-Notices.qml.due"; then
  ok "the control copy's Not now records no rest, the record occurring once"
else
  fail "the control copy could not drop the rest record from $notices_qml"
fi

# acme.needs sits in the user plugin directory before the copy starts, so
# its first scan finds it and its missing command.
mkdir -p -- "$home/.config/vgshell/plugins/acme.needs"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.needs/." "$home/.config/vgshell/plugins/acme.needs/"

if stop_shell && start_shell "$mutant" "$sandbox/notice-mutant-qs.log"; then
  ok "the control copy starts as the guarded shell"
fi
expect "the control copy is the guarded shell" true ipc shell guarded
needs_required_state() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps([r["state"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.needs" for r in p["requirements"] if r["name"]=="vgs-smoke-needs"]))'; }
expect_poll "the control copy's scan finds acme.needs missing the command it needs" '["missing"]' needs_required_state
expect "no notice shows in the control copy before the enable" null notice_shown
expect "control: enabling acme.needs in the copy without the trigger is allowed" ok ipc shell setPluginEnabled acme.needs true
expect "control: the copy without the enable trigger raises no notice" null notice_shown
# pluginInstalled answers the scan it waits for; the copy raises no notice
# when that scan lands.
installed_reply="$(ipc shell pluginInstalled acme.needs)" || installed_reply="failed: $installed_reply"
if [[ $installed_reply =~ ^(ok|busy)\ scan=([0-9]+)$ ]]; then
  expect_poll "control: pluginInstalled's scan in the copy lands" landed scan_landed "${BASH_REMATCH[2]}"
  expect "control: the copy that skips the callbacks of the scan that just ended raises no notice after pluginInstalled's scan" null notice_shown
else
  fail "control: pluginInstalled in the copy answered $installed_reply"
fi
# Not now in the copy: the notice goes and no rest is recorded, so the
# reading rows/notices.sh makes after Not now reads false.
expect_poll "the copy builds the needs fixture's service" True record_exists acme.needs
expect "an offer in the copy raises the notice" ok needs offer vgs-smoke-needs
expect_poll "the copy's offered notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the copy's notice failed"
expect_poll "Escape closes the copy's notice" null notice_shown
expect "control: a Not now that records no rest fails the rest check" false notice_rests acme.needs
