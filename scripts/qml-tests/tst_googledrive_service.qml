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
    property var savedChoice: undefined
    property var configured: []
    property string configureReply: "ok"
    property var notifications: []
    property var tuiCalls: []

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
            root.savedChoice = undefined;
            root.configured = [];
            root.configureReply = "ok";
            root.notifications = [];
            root.tuiCalls = [];
            ProcessRegistry.clear();
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            service.shell = {
                settings: { twoWaySync: true },
                manifest: { settings: { twoWaySync: true } },
                secrets: { revision: 0 },
                configure: { setIfAbsent: (key, value) => {
                    root.configured.push([key, value]);
                    if (root.configureReply !== "ok") return root.configureReply;
                    if (root.savedChoice === undefined) {
                        root.savedChoice = value;
                        selected(value);
                    }
                    return "ok";
                } },
                tui: { state: {}, run: (name, args) => { root.tuiCalls.push([name, args]); return "ok"; } },
                ipc: { handle: () => {} },
                notify: { send: (options, done) => { root.notifications.push({ options, done }); return "ok"; } },
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
            if (verb === "service-mode") verify(found.length === 1, "the selected mode must reach the serialized runner before Sync now");
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
                if (running("status") !== null) {
                    running("status").finish(0, 0, "", "");
                    if (service.modeAdmission === "mirroring" && service.modeConfirmed !== null) {
                        const rec = pausedRecord();
                        rec.twoWaySync = service.selectedMode();
                        rec.pairs[0].route = rec.twoWaySync ? "two-way" : "copy";
                        service.accept(JSON.stringify(rec));
                    }
                } else running("probe").finish(0, 0, probe, "");
            }
        }

        function pausedRecord() {
            const iso = "2026-11-07T20:00:00Z";
            return { state: "paused", paused: true, twoWaySync: true, copyModeMigration: false, units: "installed",
                lastSuccess: iso, staleAfter: null, lastError: null,
                pairs: [{ id: "docs", label: "Documents", remote: "Docs", local: "/home/me/gdrive", state: "paused",
                    route: "two-way", operation: "two-way", initialization: { state: "ready", reason: null },
                    recoveryPath: "/home/me/state/pairs/docs/conflicts", exportsPath: "/home/me/state/pairs/docs/exports",
                    lastSuccess: iso, staleAfter: null, lastError: null }],
                conflicts: [], needsYou: 0, dismissed: [], attention: null };
        }

        function admitDefault() {
            compare(ProcessRegistry.runningWithVerb("service-mode").length, 0, "status precedes the first mirror");
            settleReads();
            service.accept(JSON.stringify(pausedRecord()));
        }

        function needsSetup() {
            const rec = pausedRecord();
            rec.paused = false;
            rec.state = "initialization-required";
            rec.pairs[0].state = rec.state;
            rec.pairs[0].operation = null;
            rec.pairs[0].initialization = { state: "required", reason: "baseline-missing" };
            rec.attention = { reasons: [rec.state], key: "0123456789abcdef", notified: false };
            return rec;
        }

        function test_existing_pairs_preserve_a_saved_choice_before_first_mirror_data() {
            return [{ tag: "unsaved", saved: undefined, want: false }, { tag: "saved-off", saved: false, want: false },
                { tag: "saved-on", saved: true, want: true }, { tag: "pair-list-repaired", saved: undefined, want: false, invalidFirst: true }];
        }

        function test_existing_pairs_preserve_a_saved_choice_before_first_mirror(data) {
            settleReads();
            root.savedChoice = data.saved;
            selected(data.saved);
            service.act(["start"]);
            compare(running("start"), null, "sync waits for admission");
            if (data.invalidFirst) {
                // renderStatus emits this record when readPairs cannot read
                // the list, before it can decide copy-mode migration.
                const invalid = pausedRecord();
                invalid.state = "error";
                invalid.paused = false;
                invalid.pairs = [];
                invalid.lastSuccess = null;
                invalid.lastError = { kind: "pairs-invalid", detail: "pairs-file=shape" };
                invalid.attention = { reasons: ["error"], key: "0123456789abcdef", notified: false };
                service.accept(JSON.stringify(invalid));
                compare(service.modeAdmission, "pending");
                compare(service.modeConfirmed, null);
                compare(root.configured, []);
                compare(ProcessRegistry.runningWithVerb("service-mode").length, 0);
                compare(running("start"), null);
                compare(service.problem, "");
                compare(service.heldReason, "");
                compare(lastValue("pairList").tone, "danger");
                compare(lastValue("pairList").action, true);
                compare(lastValue("cloud").lastError.kind, "pairs-invalid");
                compare(lastValue("cloud").modePending, true);
                const callout = Logic.problemCallout(lastValue("cloud"), Date.now());
                compare(callout.tone, "danger");
                compare(callout.action.tui, "reset-pairs");
            }
            const beforeAdmissionCloud = lastValue("cloud");
            const old = needsSetup();
            old.copyModeMigration = true;
            service.accept(JSON.stringify(old));
            compare(root.configured, [["twoWaySync", false]]);
            compare(root.savedChoice, data.want);
            compare(running("service-mode").command.slice(1), ["service-mode", data.want ? "true" : "false"]);
            compare(root.notifications.length, 0, "the pre-admission record sends no stopped notice");
            compare(lastValue("cloud"), beforeAdmissionCloud, "the pre-admission record is not published");
            running("service-mode").finish(0, 0, "", "");
            compare(running("start"), null, "sync waits for the confirmed status");
            settleReads();
            compare(service.modeAdmission, "ready");
            compare(lastValue("cloud").twoWaySync, data.want);
            compare(root.notifications.length, 0, "an admitted copy route raises no setup notice");
            compare(running("start") !== null, true);
            running("start").finish(0, 0, "", "");
        }

        function test_fresh_install_and_first_pair_keep_on() {
            settleReads();
            const empty = pausedRecord();
            empty.pairs = [];
            service.accept(JSON.stringify(empty));
            compare(root.configured, []);
            compare(running("service-mode").command.slice(1), ["service-mode", "true"]);
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            service.accept(JSON.stringify(needsSetup()));
            compare(root.configured, [], "a later first pair does not repeat migration");
            compare(service.selectedMode(), true);
        }

        // expected-log: google-drive: refused: user-config=unwritable -- admission retries without releasing the mirror or queued sync
        function test_failed_admission_waits_for_a_later_successful_write() {
            settleReads();
            root.configureReply = "refused: user-config=unwritable";
            const old = needsSetup();
            old.copyModeMigration = true;
            service.act(["start"]);
            service.accept(JSON.stringify(old));
            compare(service.modeAdmission, "pending");
            compare(ProcessRegistry.runningWithVerb("service-mode").length, 0);
            compare(running("start"), null);
            compare(root.notifications.length, 0);
            root.configureReply = "ok";
            service.accept(JSON.stringify(old));
            settleReads();
            compare(running("service-mode").command.slice(1), ["service-mode", "false"]);
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            compare(service.modeAdmission, "ready");
            compare(root.savedChoice, false);
            compare(running("start") !== null, true);
            running("start").finish(0, 0, "", "");
        }

        function test_a_setting_choice_survives_the_next_mismatching_status() {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            selected(false);
            service.accept(JSON.stringify(pausedRecord()));
            compare(service.selectedMode(), false);
            compare(running("service-mode").command.slice(1), ["service-mode", "false"]);
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            const current = pausedRecord();
            current.twoWaySync = false;
            current.pairs[0].route = "copy";
            service.accept(JSON.stringify(current));
            compare(service.modeConfirmed, false);
            compare(service.selectedMode(), false);
        }

        function test_stopped_notice_opens_the_same_pair_as_the_callout() {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            const rec = needsSetup();
            const expected = Logic.problemCallout(Logic.cloudValue(rec, ""), Date.now()).action;
            service.accept(JSON.stringify(rec));
            compare(root.notifications.length, 1);
            compare(root.notifications[0].options.actions, [{ id: "setup", label: expected.label }]);
            root.notifications[0].done("setup", "delivered");
            compare(root.tuiCalls, [[expected.tui, expected.args]]);
        }

        function test_retained_notice_resolves_current_stopped_pairs_data() {
            return [
                { tag: "docs then photos", remaining: ["photos"], want: [["initialize", ["photos"]]] },
                { tag: "several stopped pairs use the chooser", remaining: ["photos", "uploads"], want: [["initialize", []]] },
                { tag: "all pairs prepared", remaining: [], want: [] },
                { tag: "pair removed", remaining: [], removed: true, want: [] },
                { tag: "unreadable current status", remaining: ["photos"], unreadable: true, want: [] },
                { tag: "no consumer shell", remaining: ["photos"], noShell: true, want: [] }
            ];
        }

        function test_retained_notice_resolves_current_stopped_pairs(data) {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            const docs = needsSetup();
            service.accept(JSON.stringify(docs));
            const notice = root.notifications[0];
            const both = needsSetup();
            const photos = Object.assign({}, both.pairs[0], { id: "photos", label: "Photos" });
            both.pairs.push(photos);
            service.accept(JSON.stringify(both));
            const current = pausedRecord();
            current.paused = false;
            current.state = data.remaining.length > 0 ? "initialization-required" : "idle";
            current.pairs = data.remaining.map(id => Object.assign({}, photos, { id: id }));
            if (data.remaining.length === 0 && !data.removed) {
                current.pairs = [Object.assign({}, current.pairs[0] || docs.pairs[0],
                    { state: "idle", initialization: { state: "ready", reason: null } })];
            }
            // Even a retained attention reason grants no authority over
            // pairs that no longer need setup.
            current.attention = docs.attention;
            service.accept(JSON.stringify(current));
            if (data.unreadable) service.statusRead = { kind: "unreadable", line: "fixture" };
            if (data.noShell) service.shell = null;
            notice.done("setup", "delivered");
            compare(root.tuiCalls, data.want);
        }

        function test_setting_mirror_and_switch_only_data() {
            return [{ tag: "on", value: true }, { tag: "off", value: false }, { tag: "manifest-default", value: undefined }];
        }

        function test_setting_mirror_and_switch_only(data) {
            admitDefault();
            compare(running("service-mode").command.slice(1), ["service-mode", "true"], "startup mirrors the manifest's default On");
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            service.accept(JSON.stringify(pausedRecord()));
            settleReads();
            const before = JSON.stringify(service.record);
            selected(data.value);
            if (data.value === false) {
                compare(running("service-mode").command.slice(1), ["service-mode", "false"]);
                running("service-mode").finish(0, 0, "", "");
                settleReads();
            }
            compare(service.modeConfirmed, data.value === false ? false : true);
            compare(ProcessRegistry.processes.filter(p => p.running).length, 0, "switch-only runs no start, resume or initialization");
            compare(JSON.stringify(service.record), before, "switch-only preserves accepted pause, success and operation history");
        }

        function test_failed_mirror_blocks_sync_until_success_data() {
            return [{ tag: "nonzero", code: 1, status: 0 }, { tag: "crashed", code: 0, status: 1 }];
        }

        // expected-log: google-drive: service-mode exit= -- a nonzero or crashed mirror is surfaced, not treated as a runnable mode
        function test_failed_mirror_blocks_sync_until_success(data) {
            admitDefault();
            service.act(["start"]);
            compare(running("start"), null);
            running("service-mode").finish(data.code, data.status, "", "mirror-write-failed");
            settleReads();
            compare(running("start"), null);
            compare(service.modeConfirmed, null);
            compare(service.problem, "service-mode");
            compare(lastSync().tone, "danger", "the mirror failure stays visible while startup waits");
            service.act(["start"]);
            compare(running("service-mode").command.slice(1), ["service-mode", "true"]);
            compare(running("start"), null);
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            running("start").finish(0, 0, "", "");
            compare(service.problem, "");
        }

        function test_latest_setting_is_mirrored_before_queued_sync() {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            service.refresh();
            compare(running("status") !== null, true, "an earlier read holds the serialized runner");
            service.act(["start"]);
            selected(false);
            compare(running("start"), null);
            settleReads();
            compare(running("service-mode").command.slice(1), ["service-mode", "false"]);
            compare(running("start"), null, "a queued start must re-admit after a later Settings change");
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            compare(service.modeConfirmed, false);
            running("start").finish(0, 0, "", "");
        }

        function test_rapid_toggle_uses_latest_effective_setting() {
            admitDefault();
            selected(false);
            service.act(["start"]);
            selected(true);
            compare(running("service-mode").command.slice(1), ["service-mode", "true"]);
            compare(running("start"), null);
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            compare(running("start").command.slice(1), ["start"]);
            compare(service.modeConfirmed, true);
            running("start").finish(0, 0, "", "");
        }

        function test_initialize_tui_completion_refreshes_status() {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
            settleReads();
            service.shell = Object.assign({}, service.shell, { tui: { state: { initialize: { endedAt: "2026-11-07T21:00:00Z" } } } });
            compare(running("status") !== null, true, "the declared initialization TUI end triggers the existing refresh owner");
            settleReads();
        }

        // expected-log: google-drive: status record refused: status=not-json -- malformed state withdraws the previously successful snapshot
        // expected-log: google-drive: service-mode exit=1 -- a mirror failure must not replace the unresolved read failure
        function test_unreadable_status_withdraws_success() {
            admitDefault();
            running("service-mode").finish(0, 0, "", "");
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
            running("service-mode").finish(1, 0, "", "mirror-write-failed");
            settleReads();
            service.act(["start"]);
            running("service-mode").finish(0, 0, "", "");
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
