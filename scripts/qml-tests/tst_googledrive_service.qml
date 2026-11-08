import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import "../../shell/plugins/vgs.google-drive" as Drive
import "../../shell/plugins/vgs.google-drive/GoogleDriveLogic.js" as Logic

// The Google Drive service while the runner holds the rename from the
// plugin's previous name: each runner call is a Process stand-in finished
// by hand. A held answer publishes the held sync value with no failure,
// and the service asks for the status again with no outside call. The
// retry timer's interval is shortened so the case waits no 15 seconds.
Item {
    id: root

    property var writes: []

    Component {
        id: serviceComponent
        Drive.Service {}
    }

    TestCase {
        name: "googledrive_service"
        when: windowShown

        property var service: null

        function init() {
            root.writes = [];
            ProcessRegistry.clear();
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            service.shell = {
                settings: { twoWaySync: true },
                manifest: { settings: { twoWaySync: true } },
                secrets: { revision: 0 },
                tui: { state: {} },
                ipc: { handle: () => {} },
                notify: { send: () => "ok" },
                surfaces: { summon: () => "ok" },
                status: { values: {}, isOk: PluginLogic.statusReplyOk, set: (key, value) => { root.writes = root.writes.concat([{ key: key, value: value }]); return "ok"; } }
            };
        }

        function cleanup() {
            service = null;
            ProcessRegistry.clear();
        }

        function running(verb) {
            const found = ProcessRegistry.runningWithVerb(verb);
            if (verb === "set-two-way") verify(found.length === 1, "the selected mode must reach the serialized runner before Sync now");
            return found.length === 1 ? found[0] : null;
        }

        function lastSync() {
            const rows = root.writes.filter(row => row.key === "sync");
            return rows.length === 0 ? undefined : rows[rows.length - 1].value;
        }

        function lastValue(key) {
            const rows = root.writes.filter(row => row.key === key);
            return rows.length === 0 ? undefined : rows[rows.length - 1].value;
        }

        function selected(value) {
            service.shell = Object.assign({}, service.shell, { settings: value === undefined ? {} : { twoWaySync: value } });
        }

        function settleReads() {
            const probe = JSON.stringify({ credentials: ["client-id", "client-secret", "token"].map(account => ({ account, presence: "absent", needed: true })) });
            for (let calls = 0; running("status") !== null || running("probe") !== null; calls++) {
                verify(calls < 20, "startup reads drain without another operation");
                if (running("status") !== null) running("status").finish(0, 0, "", "");
                else running("probe").finish(0, 0, probe, "");
            }
        }

        function pausedRecord() {
            const iso = "2026-11-07T20:00:00Z";
            return { state: "paused", paused: true, twoWaySync: true, units: "installed",
                lastSuccess: iso, staleAfter: null, lastError: null,
                pairs: [{ id: "docs", label: "Documents", remote: "Docs", local: "/home/me/gdrive", state: "paused",
                    route: "two-way", operation: "two-way", initialization: { state: "ready", reason: null },
                    recoveryPath: "/home/me/state/pairs/docs/conflicts", exportsPath: "/home/me/state/pairs/docs/exports",
                    lastSuccess: iso, staleAfter: null, lastError: null }],
                conflicts: [], needsYou: 0, dismissed: [], attention: null };
        }

        function test_setting_mirror_and_switch_only_data() {
            return [{ tag: "on", value: true }, { tag: "off", value: false }, { tag: "manifest-default", value: undefined }];
        }

        function test_setting_mirror_and_switch_only(data) {
            compare(running("set-two-way").command.slice(1), ["set-two-way", "true"], "startup mirrors the manifest's default On");
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            service.accept(JSON.stringify(pausedRecord()));
            settleReads();
            const before = JSON.stringify(service.record);
            selected(data.value);
            if (data.value === false) {
                compare(running("set-two-way").command.slice(1), ["set-two-way", "false"]);
                running("set-two-way").finish(0, 0, "", "");
                settleReads();
            }
            compare(service.modeConfirmed, data.value === false ? false : true);
            compare(ProcessRegistry.processes.filter(p => p.running).length, 0, "switch-only runs no start, resume or initialization");
            compare(JSON.stringify(service.record), before, "switch-only preserves accepted pause, success and operation history");
        }

        function test_failed_mirror_blocks_sync_until_success_data() {
            return [{ tag: "nonzero", code: 1, status: 0 }, { tag: "crashed", code: 0, status: 1 }];
        }

        // expected-log: google-drive: set-two-way exit= -- a nonzero or crashed mirror is surfaced, not treated as a runnable mode
        function test_failed_mirror_blocks_sync_until_success(data) {
            service.act(["start"]);
            compare(running("start"), null);
            running("set-two-way").finish(data.code, data.status, "", "mirror-write-failed");
            settleReads();
            compare(running("start"), null);
            compare(service.modeConfirmed, null);
            compare(service.problem, "set-two-way");
            service.act(["start"]);
            compare(running("set-two-way").command.slice(1), ["set-two-way", "true"]);
            compare(running("start"), null);
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            running("start").finish(0, 0, "", "");
            compare(service.problem, "");
        }

        function test_latest_setting_is_mirrored_before_queued_sync() {
            running("set-two-way").finish(0, 0, "", "");
            compare(running("status") !== null, true, "an earlier read holds the serialized runner");
            service.act(["start"]);
            selected(false);
            compare(running("start"), null);
            settleReads();
            compare(running("set-two-way").command.slice(1), ["set-two-way", "false"]);
            compare(running("start"), null, "a queued start must re-admit after a later Settings change");
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            compare(service.modeConfirmed, false);
            running("start").finish(0, 0, "", "");
        }

        function test_rapid_toggle_uses_latest_effective_setting() {
            selected(false);
            service.act(["start"]);
            selected(true);
            compare(running("set-two-way").command.slice(1), ["set-two-way", "true"]);
            compare(running("start"), null);
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            compare(service.modeConfirmed, true);
            running("start").finish(0, 0, "", "");
        }

        function test_initialize_tui_completion_refreshes_status() {
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            service.shell = Object.assign({}, service.shell, { tui: { state: { initialize: { endedAt: "2026-11-07T21:00:00Z" } } } });
            compare(running("status") !== null, true, "the declared initialization TUI end triggers the existing refresh owner");
            settleReads();
        }

        // expected-log: google-drive: status record refused: status=not-json -- malformed state withdraws the previously successful snapshot
        // expected-log: google-drive: set-two-way exit=1 -- a mirror failure must not replace the unresolved read failure
        function test_unreadable_status_withdraws_success() {
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            service.accept(JSON.stringify(pausedRecord()));
            settleReads();
            compare(lastValue("cloud").paused, true);
            service.accept("{");
            compare(service.record, null);
            compare(lastValue("cloud"), null);
            compare(lastValue("lastSync"), null);
            compare(lastValue("pairs"), null);
            compare(lastSync().tone, "danger");
            service.act(["start"]);
            compare(running("start"), null, "unreadable state does not start a sync");
            selected(false);
            service.act(["start"]);
            running("set-two-way").finish(1, 0, "", "mirror-write-failed");
            settleReads();
            service.act(["start"]);
            running("set-two-way").finish(0, 0, "", "");
            settleReads();
            compare(service.record, null, "a successful control mirror is not a readable status");
            compare(lastSync().tone, "danger");
            compare(running("start"), null, "control recovery cannot erase the failed status read");
            const recovered = pausedRecord();
            recovered.twoWaySync = false;
            recovered.pairs[0].route = "copy";
            service.accept(JSON.stringify(recovered));
            settleReads();
            compare(lastValue("cloud").paused, true, "only an accepted status restores the snapshot");
        }

        // expected-log: google-drive: status exit=75 google-drive: refused: migration=held reason=old-service-activating -- the service logs the hold once when it begins
        function test_held_rename_is_asked_again() {
            const held = "google-drive: refused: migration=held reason=old-service-activating\n";
            running("set-two-way").finish(0, 0, "", "");
            tryVerify(() => running("status") !== null);
            running("status").finish(Logic.RUNNER_HELD, 0, "", held);
            compare(service.heldReason, "old-sync");
            compare(service.problem, "", "a held answer is no failure");
            verify(lastSync() !== undefined && lastSync() !== null, "the sync value says why it waits before any record");
            compare(lastSync().tone, "info");

            // The start asks twice, once for the shell and once for the
            // TUI records it brings; every call still waiting is held too.
            for (let calls = 0; ProcessRegistry.processes.some(p => p.running); calls++) {
                verify(calls < 10, "the runner calls at start end");
                ProcessRegistry.processes.find(p => p.running).finish(Logic.RUNNER_HELD, 0, "", held);
            }
            compare(service.problem, "");

            const timer = Array.from(service.resources).find(item => item.interval === Logic.HELD_RETRY_MS);
            verify(timer !== undefined);
            timer.interval = 20;
            tryVerify(() => running("status") !== null, 2000, "the held status request is asked again");
            running("status").finish(0, 0, "", "");
            compare(service.heldReason, "");
            compare(lastSync(), null, "an answered status clears the held value");
        }
    }
}
